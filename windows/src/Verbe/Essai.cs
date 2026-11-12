using System;
using System.Collections.Generic;
using System.IO;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Verbe.Coeur;

namespace Verbe;

/// `Verbe.exe --essai <dossier>` : joue le parcours complet sur un vrai Windows (sans micro ni Groq : son simulé, texte fixe),
/// capture l'écran à chaque état de l'îlot et écrit `rapport.txt`. Code de sortie 0 si tout est bon.
static class Essai
{
    public static bool Actif { get; private set; }
    const string TexteEssai = "Bonjour, ceci est un essai de Verbe.";

    public static async void Lancer(string dossier, IlotFenetre ilot, Controleur controleur)
    {
        Actif = true;
        Directory.CreateDirectory(dossier);
        var lignes = new List<string>();
        int echecs = 0;
        void V(bool ok, string nom) { lignes.Add((ok ? "ok     " : "ÉCHEC  ") + nom); if (!ok) echecs++; Journal.Ecrire("essai : " + (ok ? "ok " : "ÉCHEC ") + nom); }

        try
        {
            // Une fenêtre avec un champ de texte, au premier plan : c'est là que le texte doit s'écrire.
            var champ = new TextBox { FontSize = 16, AcceptsReturn = true, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(20) };
            var fenetre = new Window { Title = "Bloc d'essai", Width = 640, Height = 360, Left = 190, Top = 240, Content = champ, WindowStartupLocation = WindowStartupLocation.Manual };
            fenetre.Show(); fenetre.Activate(); champ.Focus();
            await Task.Delay(1200);
            Capturer(dossier, "01-repos");
            V(ilot.VueActuelle == IlotFenetre.Vue.Repos, "au lancement, l'îlot est au repos");

            // Survol : la souris sur la petite pilule.
            var p = PointEcran(ilot, ilot.Width / 2, 10);
            Natif.SetCursorPos(p.x, p.y);
            await Task.Delay(900);
            Capturer(dossier, "02-survol");
            V(ilot.VueActuelle == IlotFenetre.Vue.Survol, "survol : l'îlot s'ouvre et rappelle le geste");
            Natif.SetCursorPos(p.x, p.y + 400);
            await Task.Delay(900);
            V(ilot.VueActuelle == IlotFenetre.Vue.Repos, "la souris s'en va : l'îlot se replie");

            // Dictée tenue : Ctrl + ⊞ pendant 2 s.
            Natif.Envoyer(T(Natif.VK_LCONTROL, false), T(Natif.VK_LWIN, false));
            await Task.Delay(1400);
            Capturer(dossier, "03-ecoute");
            V(ilot.VueActuelle == IlotFenetre.Vue.Ecoute, "Ctrl + ⊞ tenus : l'îlot écoute");
            V(fenetre.IsActive, "pendant l'écoute, le clavier reste dans la fenêtre où l'on écrit");
            await Task.Delay(700);
            Natif.Envoyer(T(Natif.VK_LWIN, true), T(Natif.VK_LCONTROL, true));
            await Task.Delay(120);
            Capturer(dossier, "04-traitement");
            V(ilot.VueActuelle == IlotFenetre.Vue.Traitement, "relâché : l'îlot écrit");
            await Task.Delay(1000);
            Capturer(dossier, "05-fait");
            V(champ.Text.Trim() == TexteEssai, $"le texte est collé dans le champ (trouvé : « {champ.Text.Trim()} »)");
            V(fenetre.IsActive, "après le collage, la fenêtre où l'on écrit a toujours le clavier");
            await Task.Delay(1500);
            Capturer(dossier, "06-ecran-entier-apres", entier: true);
            V(ilot.VueActuelle == IlotFenetre.Vue.Repos, "puis l'îlot se replie");

            // Mains libres : toucher brièvement, puis ✓.
            champ.Clear();
            Natif.Envoyer(T(Natif.VK_RCONTROL, false), T(Natif.VK_RWIN, false));
            await Task.Delay(120);
            Natif.Envoyer(T(Natif.VK_RWIN, true), T(Natif.VK_RCONTROL, true));
            await Task.Delay(1500);
            Capturer(dossier, "07-mains-libres");
            V(ilot.VueActuelle == IlotFenetre.Vue.Ecoute, "touché brièvement : mains libres, l'écoute continue");
            Natif.Envoyer(T(Natif.VK_LCONTROL, false), T(Natif.VK_LWIN, false));
            await Task.Delay(80);
            Natif.Envoyer(T(Natif.VK_LWIN, true), T(Natif.VK_LCONTROL, true));
            await Task.Delay(1500);
            V(champ.Text.Trim() == TexteEssai, "mains libres : le geste termine et le texte est collé");

            // Échap annule.
            champ.Clear();
            Natif.Envoyer(T(Natif.VK_LCONTROL, false), T(Natif.VK_LWIN, false));
            await Task.Delay(800);
            Natif.Envoyer(T(Natif.VK_ESCAPE, false), T(Natif.VK_ESCAPE, true));
            await Task.Delay(150);
            Capturer(dossier, "08-annule");
            Natif.Envoyer(T(Natif.VK_LWIN, true), T(Natif.VK_LCONTROL, true));
            await Task.Delay(1500);
            V(champ.Text.Length == 0, "Échap : rien n'est écrit");

            // Ctrl + ⊞ + une autre touche : pas une dictée.
            Natif.Envoyer(T(Natif.VK_LCONTROL, false), T(Natif.VK_LWIN, false));
            await Task.Delay(150);
            Natif.Envoyer(T(0x7C, false), T(0x7C, true)); // F13 : une touche sans effet
            await Task.Delay(100);
            Natif.Envoyer(T(Natif.VK_LWIN, true), T(Natif.VK_LCONTROL, true));
            await Task.Delay(900);
            V(ilot.VueActuelle == IlotFenetre.Vue.Repos && champ.Text.Length == 0, "Ctrl + ⊞ + une autre touche : rien ne se passe");
            fenetre.Activate(); champ.Focus();
            await Task.Delay(400);

            // Cartes et messages.
            controleur.OuvrirReglages();
            await Task.Delay(900);
            Capturer(dossier, "09-reglages");
            V(ilot.VueActuelle == IlotFenetre.Vue.Reglages, "réglages ouverts dans l'îlot");
            Natif.Envoyer(T(Natif.VK_ESCAPE, false), T(Natif.VK_ESCAPE, true));
            await Task.Delay(700);
            V(ilot.VueActuelle == IlotFenetre.Vue.Repos, "Échap ferme les réglages");

            ilot.AllerCle("Bienvenue dans Verbe", null);
            await Task.Delay(900);
            Capturer(dossier, "10-cle");
            ilot.AllerRepos();
            await Task.Delay(500);
            ilot.AllerMessage("Pas de réseau. Ta dictée est gardée.", "", libelleAction: "Réessayer", action: () => { });
            await Task.Delay(800);
            Capturer(dossier, "11-message");
            ilot.AllerRepos();
            await Task.Delay(600);
        }
        catch (Exception e) { V(false, "exception : " + e); }

        lignes.Add(echecs == 0 ? "ESSAI TERMINÉ : tout est bon" : $"ESSAI TERMINÉ : {echecs} échec(s)");
        File.WriteAllLines(Path.Combine(dossier, "rapport.txt"), lignes);
        Application.Current.Shutdown(echecs == 0 ? 0 : 1);
    }

    /// Ce que l'essai met à la place de Groq : le texte fixe, après une petite attente réaliste.
    public static async Task<Resultat> Traiter(byte[] pcm)
    {
        await Task.Delay(400);
        return new Resultat(TexteEssai, $"essai : {Wav.Duree(pcm):0.0} s de son simulé");
    }

    static Natif.INPUT T(int vk, bool relachee) => Natif.Touche(vk, relachee, deVerbe: false);

    static (int x, int y) PointEcran(Window w, double x, double y)
    {
        var src = PresentationSource.FromVisual(w);
        var m = src?.CompositionTarget?.TransformToDevice ?? Matrix.Identity;
        return ((int)((w.Left + x) * m.M11), (int)((w.Top + y) * m.M22));
    }

    /// Capture de la zone de l'îlot (ou de l'écran entier), telle que Windows l'affiche.
    static void Capturer(string dossier, string nom, bool entier = false)
    {
        try
        {
            int l = (int)SystemParameters.PrimaryScreenWidth, h = (int)SystemParameters.PrimaryScreenHeight;
            var zone = entier ? new System.Drawing.Rectangle(0, 0, l, h) : new System.Drawing.Rectangle(l / 2 - 300, 0, 600, 300);
            using var bmp = new System.Drawing.Bitmap(zone.Width, zone.Height);
            using (var g = System.Drawing.Graphics.FromImage(bmp)) g.CopyFromScreen(zone.Left, zone.Top, 0, 0, zone.Size);
            bmp.Save(Path.Combine(dossier, nom + ".png"), System.Drawing.Imaging.ImageFormat.Png);
        }
        catch (Exception e) { Journal.Ecrire("capture impossible : " + e.Message); }
    }
}
