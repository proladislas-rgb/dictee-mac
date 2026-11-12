using System;
using System.Collections.Generic;
using System.IO;
using System.Threading.Tasks;
using System.Windows;

namespace Verbe;

/// Écrit le texte là où est le curseur : presse-papiers + Ctrl+V, puis remet l'ancien contenu du presse-papiers.
/// Le texte dicté est marqué pour ne pas entrer dans l'historique du presse-papiers de Windows (⊞ + V) ni dans le cloud.
static class Collage
{
    static readonly string[] FormatsGardes =
    {
        DataFormats.UnicodeText, DataFormats.Text, DataFormats.Rtf, DataFormats.Html, DataFormats.Bitmap, DataFormats.FileDrop,
    };

    public static async Task Coller(string texte)
    {
        // ⊞ encore tenue : Ctrl+V deviendrait ⊞+V (historique du presse-papiers). On attend qu'elle soit relâchée (1,5 s au plus).
        for (int i = 0; i < 60 && (Natif.Enfoncee(Natif.VK_LWIN) || Natif.Enfoncee(Natif.VK_RWIN)); i++) await Task.Delay(25);

        var ancien = Sauver();
        var donnees = new DataObject();
        donnees.SetData(DataFormats.UnicodeText, texte);
        donnees.SetData("ExcludeClipboardContentFromMonitorProcessing", new MemoryStream(new byte[] { 1, 0, 0, 0 }));
        donnees.SetData("CanIncludeInClipboardHistory", new MemoryStream(BitConverter.GetBytes(0)));
        donnees.SetData("CanUploadToCloudClipboard", new MemoryStream(BitConverter.GetBytes(0)));
        if (!await Essayer(() => Clipboard.SetDataObject(donnees, true)))
        {
            Journal.Ecrire("presse-papiers occupé : collage impossible");
            throw new InvalidOperationException("presse-papiers occupé");
        }

        Natif.Envoyer(
            Natif.Touche(Natif.VK_CONTROL, false), Natif.Touche(Natif.VK_V, false),
            Natif.Touche(Natif.VK_V, true), Natif.Touche(Natif.VK_CONTROL, true));

        // L'app cible lit le presse-papiers un peu après Ctrl+V : on lui laisse le temps avant de remettre l'ancien contenu.
        await Task.Delay(350);
        if (ancien != null) await Essayer(() => Clipboard.SetDataObject(ancien, true));
    }

    static DataObject? Sauver()
    {
        try
        {
            var actuel = Clipboard.GetDataObject();
            if (actuel == null) return null;
            var copie = new DataObject();
            int n = 0;
            foreach (var f in FormatsGardes)
            {
                try { if (actuel.GetDataPresent(f, false) && actuel.GetData(f, false) is { } d) { copie.SetData(f, d); n++; } }
                catch { }
            }
            return n > 0 ? copie : null;
        }
        catch { return null; }
    }

    static async Task<bool> Essayer(Action a)
    {
        for (int i = 0; i < 10; i++)
        {
            try { a(); return true; }
            catch (System.Runtime.InteropServices.COMException) { await Task.Delay(30); }
            catch (System.Runtime.InteropServices.ExternalException) { await Task.Delay(30); }
        }
        return false;
    }
}
