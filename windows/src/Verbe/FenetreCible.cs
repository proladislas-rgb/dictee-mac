using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace Verbe;

/// La fenêtre où le texte va s'écrire : son programme (pour la mise en forme), son titre (sites dans un navigateur), son icône (dans l'îlot).
sealed record FenetreCible(IntPtr Handle, string Programme, string Titre, string? Chemin)
{
    static readonly Dictionary<string, ImageSource?> Icones = new(StringComparer.OrdinalIgnoreCase);

    public static FenetreCible Capturer()
    {
        var h = Natif.GetForegroundWindow();
        var titre = new StringBuilder(512);
        Natif.GetWindowText(h, titre, titre.Capacity);
        Natif.GetWindowThreadProcessId(h, out var pid);
        string? chemin = null;
        var p = Natif.OpenProcess(Natif.PROCESS_QUERY_LIMITED_INFORMATION, false, pid);
        if (p != IntPtr.Zero)
        {
            var nom = new StringBuilder(1024); int taille = nom.Capacity;
            if (Natif.QueryFullProcessImageName(p, 0, nom, ref taille)) chemin = nom.ToString();
            Natif.CloseHandle(p);
        }
        var programme = chemin != null ? Path.GetFileNameWithoutExtension(chemin) : "";
        return new FenetreCible(h, programme, titre.ToString(), chemin);
    }

    public ImageSource? Icone()
    {
        if (Chemin == null) return null;
        if (Icones.TryGetValue(Chemin, out var deja)) return deja;
        ImageSource? image = null;
        try
        {
            using var ico = System.Drawing.Icon.ExtractAssociatedIcon(Chemin);
            if (ico != null)
            {
                var b = Imaging.CreateBitmapSourceFromHIcon(ico.Handle, Int32Rect.Empty, BitmapSizeOptions.FromEmptyOptions());
                b.Freeze();
                image = b;
            }
        }
        catch { }
        Icones[Chemin] = image;
        return image;
    }

    /// La fenêtre au premier plan occupe-t-elle tout son écran (vidéo, jeu, présentation) ? L'îlot au repos se cache alors.
    public static bool PleinEcran(IntPtr soi)
    {
        var h = Natif.GetForegroundWindow();
        if (h == IntPtr.Zero || h == soi) return false;
        var classe = new StringBuilder(64);
        Natif.GetClassName(h, classe, classe.Capacity);
        var c = classe.ToString();
        if (c is "Progman" or "WorkerW" or "Shell_TrayWnd") return false;
        if (!Natif.GetWindowRect(h, out var r)) return false;
        var info = new Natif.MONITORINFO { cbSize = System.Runtime.InteropServices.Marshal.SizeOf<Natif.MONITORINFO>() };
        if (!Natif.GetMonitorInfo(Natif.MonitorFromWindow(h, Natif.MONITOR_DEFAULTTONEAREST), ref info)) return false;
        var m = info.rcMonitor;
        return r.Left <= m.Left && r.Top <= m.Top && r.Right >= m.Right && r.Bottom >= m.Bottom;
    }
}
