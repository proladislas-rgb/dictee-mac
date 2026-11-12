using System;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Threading;

namespace Verbe;

/// Écoute globale du clavier (crochet bas niveau). Le geste de dictée : tenir Ctrl + ⊞ (Windows), n'importe quel côté.
/// - `Appui` : Ctrl et ⊞ sont tenues ensemble ;
/// - `Relache` : l'une des deux est relâchée ;
/// - `AutreTouche` : une 3e touche pendant le geste (Ctrl + ⊞ + → change de bureau…) : ce n'était pas une dictée ;
/// - `Echap` : Échap, avalée seulement quand `AvalerEchap` est vrai (pendant une dictée).
/// Le crochet vit sur son propre fil (avec sa boucle de messages) : si l'écran est occupé, Windows ne le coupe pas
/// (au-delà de ~300 ms sans réponse, Windows retire un crochet en silence). Le rappel ne fait que poster vers l'écran.
/// Seules les touches envoyées par Verbe lui-même (marquées) sont ignorées : PowerToys, AutoHotkey, clavier tactile marchent.
sealed class Clavier : IDisposable
{
    public event Action? Appui, Relache, AutreTouche, Echap;
    volatile bool avalerEchap;
    public bool AvalerEchap { get => avalerEchap; set => avalerEchap = value; }

    readonly Dispatcher dispatcher;
    readonly Thread fil;
    readonly ManualResetEventSlim pret = new();
    Natif.LowLevelKeyboardProc? rappel;   // gardé en champ : sinon le ramasse-miettes le libère et Windows appelle dans le vide
    IntPtr crochet;
    uint idFil;
    bool lctrl, rctrl, lwin, rwin, geste;

    public Clavier(Dispatcher dispatcher)
    {
        this.dispatcher = dispatcher;
        fil = new Thread(Boucle) { IsBackground = true, Name = "Verbe clavier", Priority = ThreadPriority.AboveNormal };
        fil.Start();
        pret.Wait(TimeSpan.FromSeconds(3));
        // Verrouillage (⊞ + L), changement d'utilisateur : des relâchements n'arriveront jamais, on repart de zéro.
        Microsoft.Win32.SystemEvents.SessionSwitch += (_, _) => { lctrl = rctrl = lwin = rwin = geste = false; };
    }

    public bool Actif => crochet != IntPtr.Zero;

    void Boucle()
    {
        idFil = Natif.GetCurrentThreadId();
        rappel = Rappel;
        crochet = Natif.SetWindowsHookEx(Natif.WH_KEYBOARD_LL, rappel, Natif.GetModuleHandle(null), 0);
        if (crochet == IntPtr.Zero) Journal.Ecrire($"crochet clavier refusé (erreur {Marshal.GetLastWin32Error()})");
        pret.Set();
        while (Natif.GetMessage(out var msg, IntPtr.Zero, 0, 0) > 0) { Natif.TranslateMessage(ref msg); Natif.DispatchMessage(ref msg); }
        if (crochet != IntPtr.Zero) { Natif.UnhookWindowsHookEx(crochet); crochet = IntPtr.Zero; }
    }

    /// Les deux touches du geste sont-elles physiquement tenues (filet de sécurité si un relâchement a été manqué) ?
    public static bool GestePhysique() =>
        (Natif.Enfoncee(Natif.VK_LCONTROL) || Natif.Enfoncee(Natif.VK_RCONTROL)) && (Natif.Enfoncee(Natif.VK_LWIN) || Natif.Enfoncee(Natif.VK_RWIN));

    IntPtr Rappel(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0)
        {
            var k = Marshal.PtrToStructure<Natif.KBDLLHOOKSTRUCT>(lParam);
            int msg = wParam.ToInt32();
            bool bas = msg is Natif.WM_KEYDOWN or Natif.WM_SYSKEYDOWN;
            bool haut = msg is Natif.WM_KEYUP or Natif.WM_SYSKEYUP;
            if (k.dwExtraInfo != Natif.Marque && (bas || haut))
            {
                int vk = (int)k.vkCode;
                bool estGeste = vk is Natif.VK_LCONTROL or Natif.VK_RCONTROL or Natif.VK_LWIN or Natif.VK_RWIN;
                // La touche de l'événement prend son nouvel état ; les trois autres sont relues sur le clavier réel
                // (un relâchement manqué pendant un verrouillage, une invite UAC ou une app administrateur ne reste pas coincé).
                lctrl = vk == Natif.VK_LCONTROL ? bas : Natif.Enfoncee(Natif.VK_LCONTROL);
                rctrl = vk == Natif.VK_RCONTROL ? bas : Natif.Enfoncee(Natif.VK_RCONTROL);
                lwin = vk == Natif.VK_LWIN ? bas : Natif.Enfoncee(Natif.VK_LWIN);
                rwin = vk == Natif.VK_RWIN ? bas : Natif.Enfoncee(Natif.VK_RWIN);
                bool avant = geste;
                geste = (lctrl || rctrl) && (lwin || rwin);
                if (!avant && geste)
                {
                    // Touche vide pendant que ⊞ est tenue : le menu Démarrer ne s'ouvrira pas au relâchement.
                    Natif.Envoyer(Natif.Touche(Natif.VK_MASQUE, false), Natif.Touche(Natif.VK_MASQUE, true));
                    dispatcher.BeginInvoke(() => Appui?.Invoke());
                }
                else if (avant && !geste) dispatcher.BeginInvoke(() => Relache?.Invoke());
                else if (geste && bas && !estGeste) dispatcher.BeginInvoke(() => AutreTouche?.Invoke());

                if (bas && vk == Natif.VK_ESCAPE)
                {
                    dispatcher.BeginInvoke(() => Echap?.Invoke());
                    if (avalerEchap) return (IntPtr)1;
                }
            }
        }
        return Natif.CallNextHookEx(crochet, nCode, wParam, lParam);
    }

    public void Dispose()
    {
        if (idFil != 0) Natif.PostThreadMessage(idFil, Natif.WM_QUIT, IntPtr.Zero, IntPtr.Zero);
    }
}
