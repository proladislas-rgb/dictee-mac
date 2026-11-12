using System;
using System.Runtime.InteropServices;
using System.Windows.Threading;

namespace Verbe;

/// Écoute globale du clavier (crochet bas niveau). Le geste de dictée : tenir Ctrl + ⊞ (Windows), n'importe quel côté.
/// - `Appui` : Ctrl et ⊞ sont tenues ensemble ;
/// - `Relache` : l'une des deux est relâchée ;
/// - `AutreTouche` : une 3e touche pendant le geste (Ctrl + ⊞ + → change de bureau…) : ce n'était pas une dictée ;
/// - `Echap` : Échap, avalée seulement quand `AvalerEchap` est vrai (pendant une dictée).
/// Les touches envoyées par un programme (dont le Ctrl+V de Verbe) sont ignorées.
sealed class Clavier : IDisposable
{
    public event Action? Appui, Relache, AutreTouche, Echap;
    public bool AvalerEchap { get; set; }

    readonly Natif.LowLevelKeyboardProc rappel;   // gardé en champ : sinon le ramasse-miettes le libère et Windows appelle dans le vide
    readonly Dispatcher dispatcher;
    IntPtr crochet;
    bool lctrl, rctrl, lwin, rwin, geste;

    public Clavier(Dispatcher dispatcher)
    {
        this.dispatcher = dispatcher;
        rappel = Rappel;
        crochet = Natif.SetWindowsHookEx(Natif.WH_KEYBOARD_LL, rappel, Natif.GetModuleHandle(null), 0);
        if (crochet == IntPtr.Zero) Journal.Ecrire($"crochet clavier refusé (erreur {Marshal.GetLastWin32Error()})");
    }

    public bool Actif => crochet != IntPtr.Zero;
    public bool GesteTenu => geste;

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
            bool simulee = (k.flags & Natif.LLKHF_INJECTED) != 0;
            bool aPrendre = !simulee || (Essai.Actif && k.dwExtraInfo != Natif.Marque);
            if (aPrendre && (bas || haut))
            {
                int vk = (int)k.vkCode;
                bool estGeste = true;
                switch (vk)
                {
                    case Natif.VK_LCONTROL: lctrl = bas; break;
                    case Natif.VK_RCONTROL: rctrl = bas; break;
                    case Natif.VK_LWIN: lwin = bas; break;
                    case Natif.VK_RWIN: rwin = bas; break;
                    default: estGeste = false; break;
                }
                bool avant = geste;
                geste = (lctrl || rctrl) && (lwin || rwin);
                if (!avant && geste)
                {
                    dispatcher.BeginInvoke(() =>
                    {
                        Natif.Envoyer(Natif.Touche(Natif.VK_MASQUE, false), Natif.Touche(Natif.VK_MASQUE, true));
                        Appui?.Invoke();
                    });
                }
                else if (avant && !geste) dispatcher.BeginInvoke(() => Relache?.Invoke());
                else if (geste && bas && !estGeste) dispatcher.BeginInvoke(() => AutreTouche?.Invoke());

                if (bas && vk == Natif.VK_ESCAPE)
                {
                    dispatcher.BeginInvoke(() => Echap?.Invoke());
                    if (AvalerEchap) return (IntPtr)1;
                }
            }
        }
        return Natif.CallNextHookEx(crochet, nCode, wParam, lParam);
    }

    public void Dispose()
    {
        if (crochet != IntPtr.Zero) { Natif.UnhookWindowsHookEx(crochet); crochet = IntPtr.Zero; }
    }
}
