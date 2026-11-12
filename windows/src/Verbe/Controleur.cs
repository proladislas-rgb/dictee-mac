using System;
using System.Media;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Media;
using System.Windows.Threading;
using Verbe.Coeur;

namespace Verbe;

/// Le chef d'orchestre : geste au clavier ou clic dans l'îlot → micro → Groq → collage. Tout se passe sur le fil de l'écran.
sealed class Controleur
{
    enum Etat { Libre, Ecoute, Traitement, Carte }

    readonly IlotFenetre ilot;
    readonly Clavier clavier;
    readonly Micro micro = new();
    readonly Reglages reglages;
    readonly Groq groq;
    readonly Chaine chaine;
    readonly DispatcherTimer minuterie = new() { Interval = TimeSpan.FromMilliseconds(100) };
    readonly SoundPlayer sonDebut = new(new MemoryStream(Wav.Signal(880, 1320)));
    readonly SoundPlayer sonFin = new(new MemoryStream(Wav.Signal(1320, 990)));

    Etat etat = Etat.Libre;
    bool mainsLibres, autreTouche;
    DateTime debutAppui;
    FenetreCible? cible;
    CancellationTokenSource? annulation;
    byte[]? sonEnAttente;              // gardé quand Groq n'a pas pu répondre : « Réessayer » le renvoie
    FenetreCible? cibleEnAttente;

    /// Plus court que ça, un relâchement veut dire « mains libres » (toucher le geste au lieu de le tenir).
    static readonly TimeSpan SeuilMainsLibres = TimeSpan.FromMilliseconds(320);
    const double DureeMax = 600;       // 10 minutes par dictée

    public Controleur(IlotFenetre ilot, Clavier clavier, Reglages reglages)
    {
        this.ilot = ilot; this.clavier = clavier; this.reglages = reglages;
        groq = new Groq(reglages.Cle);
        chaine = new Chaine(groq);

        clavier.Appui += SurAppui;
        clavier.Relache += SurRelache;
        clavier.AutreTouche += SurAutreTouche;
        clavier.Echap += SurEchap;
        micro.Niveau += n => ilot.Dispatcher.BeginInvoke(() => ilot.MettreNiveau(n));
        minuterie.Tick += (_, _) => Veiller();

        ilot.DemandeMicro += () => { if (etat == Etat.Libre) Commencer(mainsLibresDirect: true); };
        ilot.DemandeValider += () => { if (etat == Etat.Ecoute) _ = Terminer(); };
        ilot.DemandeAnnuler += () => { if (etat == Etat.Ecoute) Abandonner(montrer: true); };
        ilot.DemandeReglages += OuvrirReglages;
        ilot.DemandeFermerCarte += FermerCarte;
        ilot.DemandeQuitter += () => Application.Current.Shutdown();
        ilot.DemandeChangerCle += () => OuvrirCle("Changer la clé Groq", null);
        ilot.CleProposee += c => _ = EssayerCle(c);
        ilot.LangueChoisie += l => { reglages.Langue = l; reglages.Enregistrer(); };
        ilot.SonsChoisis += s => { reglages.Sons = s; reglages.Enregistrer(); };
    }

    public void Demarrer()
    {
        if (!clavier.Actif)
        {
            ilot.AllerMessage("Windows refuse l'écoute du clavier : clique sur le micro de l'îlot pour dicter.", secondes: 8);
            return;
        }
        if (reglages.Cle() == null) { OuvrirCle("Bienvenue dans Verbe", null); return; }
        if (!reglages.PremierLancementVu)
        {
            reglages.PremierLancementVu = true; reglages.Enregistrer();
            ilot.AllerMessage("Prêt. Tiens Ctrl + Windows, parle, relâche.", "", Brushes.White, secondes: 5);
        }
        groq.Prechauffer();
    }

    // ── geste ──

    void SurAppui()
    {
        switch (etat)
        {
            case Etat.Libre: Commencer(mainsLibresDirect: false); break;
            case Etat.Ecoute when mainsLibres: _ = Terminer(); break;   // en mains libres, le geste termine
        }
    }

    void SurRelache()
    {
        if (etat != Etat.Ecoute || mainsLibres) return;
        if (autreTouche) return;
        if (DateTime.Now - debutAppui < SeuilMainsLibres)
        {
            mainsLibres = true;
            ilot.AllerEcoute(cible?.Icone(), true);
            return;
        }
        _ = Terminer();
    }

    /// Ctrl + Windows + une autre touche (changer de bureau…) : ce n'était pas une dictée, on lâche tout sans bruit.
    void SurAutreTouche()
    {
        if (etat != Etat.Ecoute || mainsLibres) return;
        autreTouche = true;
        Abandonner(montrer: false);
    }

    void SurEchap()
    {
        switch (etat)
        {
            case Etat.Ecoute: Abandonner(montrer: true); break;
            case Etat.Traitement: annulation?.Cancel(); break;
            case Etat.Carte: FermerCarte(); break;
        }
    }

    void Commencer(bool mainsLibresDirect)
    {
        if (!Essai.Actif && reglages.Cle() == null) { OuvrirCle("Bienvenue dans Verbe", "Il faut d'abord ta clé Groq gratuite."); return; }
        cible = FenetreCible.Capturer();
        try { micro.Demarrer(); }
        catch (Exception e)
        {
            Journal.Ecrire("micro introuvable : " + e.Message);
            ilot.AllerMessage("Aucun micro trouvé. Branche-en un, puis réessaie.", "");
            return;
        }
        etat = Etat.Ecoute;
        mainsLibres = mainsLibresDirect;
        autreTouche = false;
        debutAppui = DateTime.Now;
        clavier.AvalerEchap = true;
        ilot.AllerEcoute(cible.Icone(), mainsLibres);
        if (reglages.Sons) Jouer(sonDebut);
        groq.Prechauffer();
        minuterie.Start();
    }

    /// Toutes les 100 ms pendant l'écoute : chrono, durée maximale, et relâchement manqué (filet de sécurité).
    void Veiller()
    {
        if (etat != Etat.Ecoute) { minuterie.Stop(); return; }
        double d = micro.DureeEnCours;
        ilot.MettreChrono(d);
        if (d >= DureeMax) { _ = Terminer(); return; }
        if (!mainsLibres && DateTime.Now - debutAppui > SeuilMainsLibres && !Clavier.GestePhysique()) SurRelache();
    }

    void Abandonner(bool montrer)
    {
        micro.Abandonner();
        minuterie.Stop();
        etat = Etat.Libre;
        clavier.AvalerEchap = false;
        if (montrer) ilot.AllerMessage("Annulé", "", Brushes.White, secondes: 1.0);
        else ilot.AllerRepos();
    }

    async Task Terminer()
    {
        if (etat != Etat.Ecoute) return;
        etat = Etat.Traitement;
        minuterie.Stop();
        annulation = new CancellationTokenSource();   // dès maintenant : Échap pendant l'arrêt du micro annule aussi
        var jeton = annulation.Token;
        var c = cible;
        bool parti = false;
        try
        {
            ilot.AllerTraitement(c?.Icone());
            var pcm = await micro.Arreter();
            if (reglages.Sons) Jouer(sonFin);
            if (jeton.IsCancellationRequested) { ilot.AllerMessage("Annulé", "\uE711", Brushes.White, secondes: 1.0); return; }

            double duree = Wav.Duree(pcm), crete = Wav.Crete(pcm);
            if (duree < 0.3) { ilot.AllerRepos(); return; }
            if (crete < 0.003)
            {
                ilot.AllerMessage("Le micro ne capte rien. Vérifie Paramètres › Confidentialité › Microphone.", "", libelleAction: "Ouvrir",
                    action: () => Ouvrir("ms-settings:privacy-microphone"));
                return;
            }
            if (crete < 0.015) { ilot.AllerMessage("Rien entendu", "", Brushes.White, secondes: 1.4); return; }
            parti = true;
            await Envoyer(pcm, c, annulation);
        }
        catch (Exception e)
        {
            Journal.Ecrire("fin de dictée : " + e);
            ilot.AllerMessage("Un souci inattendu. Réessaie.");
        }
        finally { if (!parti) Liberer(); }
    }

    async Task Envoyer(byte[] pcm, FenetreCible? c, CancellationTokenSource? jeton = null)
    {
        etat = Etat.Traitement;
        clavier.AvalerEchap = true;
        ilot.AllerTraitement(c?.Icone());
        annulation = jeton ?? new CancellationTokenSource();
        try
        {
            var contexte = RemiseAuPropre.ContexteDe(c?.Programme, c?.Titre);
            var r = Essai.Actif ? await Essai.Traiter(pcm)
                                : await chaine.Traiter(pcm, reglages.LangueWhisper, contexte, reglages.Mots, annulation.Token);
            Journal.Ecrire(r.Journal + (c != null ? $", app {c.Programme}" : ""));
            sonEnAttente = null;
            if (r.Texte == null) { ilot.AllerMessage("Rien entendu", "", Brushes.White, secondes: 1.4); return; }
            try
            {
                // L'îlot a le clavier (carte de la clé juste fermée) : on le rend à l'app de départ avant de coller.
                if (c != null && Natif.GetForegroundWindow() == ilot.Handle) { Natif.Activer(c.Handle); await Task.Delay(150); }
                await Collage.Coller(r.Texte);
                ilot.AllerFait();
            }
            catch
            {
                ilot.AllerMessage("Le presse-papiers est occupé. Réessaie.", libelleAction: "Réessayer", action: () => _ = Recoller(r.Texte));
            }
        }
        catch (OperationCanceledException) { ilot.AllerMessage("Annulé", "", Brushes.White, secondes: 1.0); }
        catch (GroqException e)
        {
            Journal.Ecrire($"Groq : {e.Genre} {e.Code}");
            sonEnAttente = pcm; cibleEnAttente = c;
            switch (e.Genre)
            {
                case Echec.PasDeCle:
                case Echec.CleRefusee:
                    etat = Etat.Libre;
                    OuvrirCle("Clé Groq refusée", "Groq n'accepte plus cette clé. Colles-en une nouvelle : ta dictée partira juste après.");
                    return;
                case Echec.Limite:
                    var attente = e.AttenteSecondes is { } s ? (s >= 60 ? $"{Math.Ceiling(s / 60)} min" : $"{Math.Ceiling(s)} s") : "un moment";
                    ilot.AllerMessage($"Limite gratuite de Groq atteinte. Réessaie dans {attente}.", libelleAction: "Réessayer", action: Reessayer);
                    break;
                case Echec.Reseau:
                    ilot.AllerMessage("Pas de réseau. Ta dictée est gardée.", "", libelleAction: "Réessayer", action: Reessayer);
                    break;
                default:
                    ilot.AllerMessage("Groq ne répond pas. Ta dictée est gardée.", libelleAction: "Réessayer", action: Reessayer);
                    break;
            }
        }
        catch (Exception e)
        {
            Journal.Ecrire("erreur inattendue : " + e);
            ilot.AllerMessage("Un souci inattendu. Réessaie.");
        }
        finally { Liberer(); }
    }

    void Liberer()
    {
        if (etat == Etat.Traitement) etat = Etat.Libre;
        clavier.AvalerEchap = false;
        annulation?.Dispose(); annulation = null;
    }

    void Reessayer()
    {
        if (sonEnAttente is { } son && etat == Etat.Libre) _ = Envoyer(son, cibleEnAttente);
    }

    async Task Recoller(string texte)
    {
        try { await Collage.Coller(texte); ilot.AllerFait(); }
        catch { ilot.AllerMessage("Le presse-papiers est encore occupé."); }
    }

    // ── cartes ──

    public void OuvrirReglages()
    {
        if (etat is Etat.Ecoute or Etat.Traitement) return;
        etat = Etat.Carte;
        clavier.AvalerEchap = false;   // hors dictée, Échap n'est jamais pris aux autres apps (il ferme quand même la carte)
        ilot.AllerReglages(reglages.Langue, reglages.Sons);
    }

    void OuvrirCle(string titre, string? texte)
    {
        etat = Etat.Carte;
        clavier.AvalerEchap = false;   // Échap ferme la carte sans être pris aux autres apps
        ilot.ViderCle();
        ilot.AllerCle(titre, texte);
    }

    void FermerCarte()
    {
        if (etat != Etat.Carte) return;
        etat = Etat.Libre;
        clavier.AvalerEchap = false;
        ilot.AllerRepos();
    }

    async Task EssayerCle(string brute)
    {
        var cle = brute.Trim().Trim('"', '\'');
        if (cle.StartsWith("GROQ_API_KEY=", StringComparison.OrdinalIgnoreCase)) cle = cle["GROQ_API_KEY=".Length..].Trim('"', '\'');
        if (cle.Length < 20) { ilot.EtatCle("Ça ne ressemble pas à une clé Groq (elle commence par gsk_).", false); return; }
        ilot.EtatCle("Vérification auprès de Groq…", true);
        try
        {
            if (!await groq.TesterCle(cle)) { ilot.EtatCle("Groq refuse cette clé. Vérifie-la sur console.groq.com.", false); return; }
        }
        catch (GroqException) { ilot.EtatCle("Pas de réseau : impossible de vérifier la clé.", false); return; }
        reglages.DefinirCle(cle);
        ilot.ViderCle();
        etat = Etat.Libre;
        clavier.AvalerEchap = false;
        if (sonEnAttente != null) { Reessayer(); return; }
        reglages.PremierLancementVu = true; reglages.Enregistrer();
        ilot.AllerMessage("C'est prêt. Tiens Ctrl + Windows, parle, relâche.", "", (Brush)new BrushConverter().ConvertFrom("#30D158")!, secondes: 5);
    }

    static void Jouer(SoundPlayer s)
    {
        try { s.Play(); } catch (Exception e) { Journal.Ecrire("son impossible : " + e.GetType().Name); }
    }

    static void Ouvrir(string url)
    {
        try { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(url) { UseShellExecute = true }); } catch { }
    }

    public void Fermer()
    {
        micro.Abandonner();
        clavier.Dispose();
    }
}
