using System;
using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Shapes;
using System.Windows.Threading;

namespace Verbe;

/// Ressort amorti (façon Dynamic Island) : léger dépassement puis pose, sans rebond visible.
sealed class Ressort : EasingFunctionBase
{
    public double Amorti { get; set; } = 7;
    public double Pulsation { get; set; } = 9;
    public Ressort() { EasingMode = EasingMode.EaseIn; }   // la courbe est donnée telle quelle (EaseIn = pas d'inversion)
    protected override double EaseInCore(double t) => 1 - Math.Exp(-Amorti * t) * Math.Cos(Pulsation * t);
    protected override Freezable CreateInstanceCore() => new Ressort { Amorti = Amorti, Pulsation = Pulsation };
}

/// L'îlot : une pilule noire en haut au centre de l'écran, qui ne prend jamais le clavier à l'app où l'on écrit.
/// Il ne fait qu'afficher ; c'est `Controleur` qui décide.
public partial class IlotFenetre : Window
{
    public enum Vue { Repos, Survol, Ecoute, Traitement, Fait, Message, Reglages, Cle }
    public Vue VueActuelle { get; private set; } = Vue.Repos;

    public event Action? DemandeMicro, DemandeValider, DemandeAnnuler, DemandeReglages, DemandeFermerCarte, DemandeQuitter, DemandeChangerCle;
    public event Action<string>? CleProposee;
    public event Action<string>? LangueChoisie;
    public event Action<bool>? SonsChoisis;

    IntPtr hwnd;
    readonly Rectangle[] barres = new Rectangle[13];
    readonly double[] hauteurs = new double[13];
    readonly double[] profil = { 0.35, 0.5, 0.65, 0.8, 0.9, 0.97, 1, 0.97, 0.9, 0.8, 0.65, 0.5, 0.35 };
    double niveau;          // 0..1, lissé
    double niveauCible;
    readonly DateTime origine = DateTime.Now;
    readonly DispatcherTimer minuterieMessage = new();
    readonly DispatcherTimer minuterieSouris = new() { Interval = TimeSpan.FromMilliseconds(90) };
    DateTime sortieSouris = DateTime.MaxValue;
    bool sourisEntreeDansCarte;
    bool pointsLances;
    IntPtr avantCle;          // la fenêtre qui avait le clavier avant la carte de la clé : elle le retrouve à la fermeture
    readonly DispatcherTimer minuteriePleinEcran = new() { Interval = TimeSpan.FromSeconds(1.2) };
    Action? actionMessage;
    bool pleinEcran;

    public IlotFenetre()
    {
        InitializeComponent();
        for (int i = 0; i < barres.Length; i++)
        {
            barres[i] = new Rectangle { Width = 3, Height = 3, RadiusX = 1.5, RadiusY = 1.5, Fill = Brushes.White, Margin = new Thickness(1.5, 0, 1.5, 0), VerticalAlignment = VerticalAlignment.Center };
            onde.Children.Add(barres[i]);
        }
        version.Text = "pour Windows · " + (typeof(IlotFenetre).Assembly.GetName().Version?.ToString(3) ?? "");

        pilule.SizeChanged += (_, _) => pilule.CornerRadius = new CornerRadius(Math.Min(pilule.ActualHeight / 2, 26));
        minuterieSouris.Tick += (_, _) => SuivreSouris();
        minuterieMessage.Tick += (_, _) => { minuterieMessage.Stop(); if (VueActuelle is Vue.Message or Vue.Fait) Montrer(Vue.Repos); };
        minuteriePleinEcran.Tick += (_, _) => VerifierPleinEcran();

        boutonMicro.Click += (_, _) => DemandeMicro?.Invoke();
        boutonReglages.Click += (_, _) => DemandeReglages?.Invoke();
        boutonValider.Click += (_, _) => DemandeValider?.Invoke();
        boutonAnnuler.Click += (_, _) => DemandeAnnuler?.Invoke();
        boutonFermerReglages.Click += (_, _) => DemandeFermerCarte?.Invoke();
        boutonFermerCle.Click += (_, _) => DemandeFermerCarte?.Invoke();
        boutonQuitter.Click += (_, _) => DemandeQuitter?.Invoke();
        boutonChangerCle.Click += (_, _) => DemandeChangerCle?.Invoke();
        boutonMessage.Click += (_, _) => { var a = actionMessage; actionMessage = null; a?.Invoke(); };
        boutonObtenirCle.Click += (_, _) => OuvrirLien("https://console.groq.com/keys");
        boutonEnregistrerCle.Click += (_, _) => CleProposee?.Invoke(champCle.Text);
        champCle.KeyDown += (_, e) => { if (e.Key == System.Windows.Input.Key.Enter) CleProposee?.Invoke(champCle.Text); };
        langueFr.Checked += (_, _) => LangueChoisie?.Invoke("fr");
        langueEn.Checked += (_, _) => LangueChoisie?.Invoke("en");
        langueAuto.Checked += (_, _) => LangueChoisie?.Invoke("auto");
        sonsOui.Checked += (_, _) => SonsChoisis?.Invoke(true);
        sonsNon.Checked += (_, _) => SonsChoisis?.Invoke(false);

        SourceInitialized += (_, _) =>
        {
            hwnd = new WindowInteropHelper(this).Handle;
            RendreInactivable(true);
            RendreTraversable(true);
        };
        Loaded += (_, _) => { Placer(); minuteriePleinEcran.Start(); minuterieSouris.Start(); };
        Microsoft.Win32.SystemEvents.DisplaySettingsChanged += (_, _) => Dispatcher.BeginInvoke(Placer);
    }

    public IntPtr Handle => hwnd;

    /// En haut au centre de l'écran principal, là où serait l'encoche.
    void Placer()
    {
        var zoneTravail = SystemParameters.WorkArea;
        Left = (SystemParameters.PrimaryScreenWidth - Width) / 2;
        Top = Math.Max(0, zoneTravail.Top);   // barre des tâches en haut : l'îlot se pose juste dessous
    }

    /// Jamais de vol du clavier : un clic sur l'îlot laisse le curseur dans l'app où l'on écrit.
    /// Seule la carte de la clé (champ de saisie) rend la fenêtre activable, le temps de taper.
    void RendreInactivable(bool oui) => PoserStyle(Natif.WS_EX_NOACTIVATE, oui);

    /// Au repos, la fenêtre entière laisse passer les clics (onglets, barres de titre sous la petite pilule) ;
    /// le survol est alors détecté en suivant la position de la souris.
    void RendreTraversable(bool oui) => PoserStyle(Natif.WS_EX_TRANSPARENT, oui);

    void PoserStyle(long drapeau, bool oui)
    {
        if (hwnd == IntPtr.Zero) return;
        long ex = GetEx() | Natif.WS_EX_TOOLWINDOW | Natif.WS_EX_TOPMOST;
        ex = oui ? ex | drapeau : ex & ~drapeau;
        Natif.SetWindowLongPtr(hwnd, Natif.GWL_EXSTYLE, new IntPtr(ex));
    }
    long GetEx() => Natif.GetWindowLongPtr(hwnd, Natif.GWL_EXSTYLE).ToInt64();

    void AuPremierPlan()
    {
        if (hwnd != IntPtr.Zero) Natif.SetWindowPos(hwnd, Natif.HWND_TOPMOST, 0, 0, 0, 0, Natif.SWP_NOMOVE | Natif.SWP_NOSIZE | Natif.SWP_NOACTIVATE);
    }

    // ── tailles de chaque vue ──

    static Size TailleDe(Vue v) => v switch
    {
        Vue.Repos => new Size(110, 8),
        Vue.Survol => new Size(300, 40),
        Vue.Ecoute => new Size(236, 40),
        Vue.Traitement => new Size(196, 40),
        Vue.Fait => new Size(132, 40),
        Vue.Message => new Size(260, 40),
        Vue.Reglages => new Size(420, 252),
        Vue.Cle => new Size(440, 214),
        _ => new Size(110, 8),
    };

    FrameworkElement? PanneauDe(Vue v) => v switch
    {
        Vue.Survol => panneauSurvol,
        Vue.Ecoute => panneauEcoute,
        Vue.Traitement => panneauTraitement,
        Vue.Fait => panneauFait,
        Vue.Message => panneauMessage,
        Vue.Reglages => panneauReglages,
        Vue.Cle => panneauCle,
        _ => null,
    };

    void Montrer(Vue v, Size? taille = null)
    {
        var avant = VueActuelle;
        VueActuelle = v;
        AuPremierPlan();
        RendreTraversable(v == Vue.Repos);
        if (avant == Vue.Cle && v != Vue.Cle)
        {
            RendreInactivable(true);
            Natif.Activer(avantCle);   // le clavier retourne à l'app où l'on écrivait
        }
        if (v != Vue.Traitement && pointsLances) { pointsLances = false; (FindResource("Points") as Storyboard)?.Stop(this); }
        if (v != Vue.Ecoute) CompositionTarget.Rendering -= Animer;
        if (v is not (Vue.Message or Vue.Fait)) minuterieMessage.Stop();
        sortieSouris = DateTime.MaxValue;
        sourisEntreeDansCarte = false;

        var t = taille ?? TailleDe(v);
        // Le repli est plus calme que l'ouverture (moins de dépassement).
        var ressort = v == Vue.Repos ? new Ressort { Amorti = 9, Pulsation = 7 } : new Ressort();
        var duree = TimeSpan.FromMilliseconds(v == Vue.Repos ? 420 : 520);
        pilule.BeginAnimation(WidthProperty, new DoubleAnimation(t.Width, duree) { EasingFunction = ressort });
        pilule.BeginAnimation(HeightProperty, new DoubleAnimation(t.Height, duree) { EasingFunction = ressort });
        pilule.BeginAnimation(OpacityProperty, new DoubleAnimation(v == Vue.Repos ? (pleinEcran ? 0 : 0.92) : 1, TimeSpan.FromMilliseconds(180)));

        foreach (var p in new FrameworkElement[] { panneauSurvol, panneauEcoute, panneauTraitement, panneauFait, panneauMessage, panneauReglages, panneauCle })
        {
            if (p == PanneauDe(v)) continue;
            p.BeginAnimation(OpacityProperty, null);
            p.Opacity = 0;
            p.Visibility = Visibility.Collapsed;
        }
        if (PanneauDe(v) is { } nouveau && (avant != v || nouveau.Visibility != Visibility.Visible))
        {
            nouveau.Visibility = Visibility.Visible;
            nouveau.BeginAnimation(OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(200)) { BeginTime = TimeSpan.FromMilliseconds(avant == Vue.Repos ? 110 : 60) });
        }
    }

    // ── survol au repos ──

    /// Toutes les 90 ms : la souris arrive-t-elle sur la petite pilule (ouvrir), quitte-t-elle l'îlot (replier) ?
    void SuivreSouris()
    {
        if (hwnd == IntPtr.Zero || !IsLoaded || !Natif.GetCursorPos(out var c)) return;
        var v = VueActuelle;
        if (v == Vue.Repos)
        {
            if (pleinEcran) return;
            // une bande de 240 × 30 autour de la petite pilule, plus facile à viser qu'un trait de 8 px
            var centre = PointToScreen(new Point(Width / 2, 0));
            var echelle = PointToScreen(new Point(1, 1)) - PointToScreen(new Point(0, 0));
            if (Math.Abs(c.X - centre.X) <= 120 * echelle.X && c.Y >= centre.Y - 2 && c.Y <= centre.Y + 30 * echelle.Y) Montrer(Vue.Survol);
            return;
        }
        if (v is not (Vue.Survol or Vue.Reglages)) return;
        var a = pilule.PointToScreen(new Point(-12, -12));
        var b = pilule.PointToScreen(new Point(pilule.ActualWidth + 12, pilule.ActualHeight + 12));
        bool dedans = c.X >= a.X && c.X <= b.X && c.Y >= Math.Min(a.Y, 0) && c.Y <= b.Y;
        if (dedans) { sortieSouris = DateTime.MaxValue; sourisEntreeDansCarte = true; return; }
        if (sortieSouris == DateTime.MaxValue) sortieSouris = DateTime.Now;
        if (v == Vue.Survol && DateTime.Now - sortieSouris > TimeSpan.FromMilliseconds(250)) Montrer(Vue.Repos);
        // Les réglages se referment quand la souris les quitte (après y être entrée : ouverts depuis l'icône près de l'horloge, la souris est loin).
        if (v == Vue.Reglages && sourisEntreeDansCarte && DateTime.Now - sortieSouris > TimeSpan.FromSeconds(1.5)) DemandeFermerCarte?.Invoke();
    }

    void VerifierPleinEcran()
    {
        bool p = FenetreCible.PleinEcran(hwnd);
        if (p == pleinEcran) return;
        pleinEcran = p;
        if (VueActuelle == Vue.Repos) pilule.BeginAnimation(OpacityProperty, new DoubleAnimation(p ? 0 : 0.92, TimeSpan.FromMilliseconds(200)));
    }

    // ── vues publiques ──

    public void AllerRepos() => Montrer(Vue.Repos);

    public void AllerEcoute(ImageSource? icone, bool mainsLibres)
    {
        iconeCible.Source = icone;
        pointRouge.Visibility = icone == null ? Visibility.Visible : Visibility.Collapsed;
        boutonsMainsLibres.Visibility = mainsLibres ? Visibility.Visible : Visibility.Collapsed;
        var t = TailleDe(Vue.Ecoute);
        if (mainsLibres) t.Width += 70;
        if (VueActuelle != Vue.Ecoute) { niveau = niveauCible = 0; chrono.Text = "0:00"; CompositionTarget.Rendering -= Animer; CompositionTarget.Rendering += Animer; }
        Montrer(Vue.Ecoute, t);
    }

    public void MettreNiveau(double efficace)
    {
        // -50 dB → 0, -12 dB → 1
        double db = 20 * Math.Log10(Math.Max(efficace, 1e-6));
        niveauCible = Math.Clamp((db + 50) / 38, 0, 1);
    }

    public void MettreChrono(double secondes) => chrono.Text = $"{(int)secondes / 60}:{(int)secondes % 60:00}";

    void Animer(object? s, EventArgs e)
    {
        niveau += (niveauCible - niveau) * (niveauCible > niveau ? 0.45 : 0.18);
        double t = (DateTime.Now - origine).TotalSeconds;
        for (int i = 0; i < barres.Length; i++)
        {
            double vie = 0.62 + 0.38 * Math.Sin(t * (7.3 + i * 0.9) + i * 1.7);
            double cible = 3 + 19 * niveau * profil[i] * vie;
            hauteurs[i] += (cible - hauteurs[i]) * 0.5;
            barres[i].Height = hauteurs[i];
            barres[i].Opacity = 0.55 + 0.45 * Math.Min(1, niveau * 1.4);
        }
    }

    public void AllerTraitement(ImageSource? icone)
    {
        iconeTraitement.Source = icone;
        iconeTraitement.Visibility = icone == null ? Visibility.Collapsed : Visibility.Visible;
        Montrer(Vue.Traitement);
        (FindResource("Points") as Storyboard)?.Begin(this, true);
        pointsLances = true;
    }

    public void AllerFait(string texte = "Écrit")
    {
        texteFait.Text = texte;
        Montrer(Vue.Fait);
        minuterieMessage.Interval = TimeSpan.FromMilliseconds(950);
        minuterieMessage.Start();
    }

    /// Un message court, sur une ligne. `action` : un bouton blanc (« Réessayer »…). Sans action, il se referme seul.
    public void AllerMessage(string texte, string glyphe = "", Brush? couleur = null, string? libelleAction = null, Action? action = null, double secondes = 2.6)
    {
        texteMessage.Text = texte;
        glypheMessage.Text = glyphe;
        glypheMessage.Foreground = couleur ?? (Brush)FindResource("Orange");
        actionMessage = action;
        boutonMessage.Content = libelleAction;
        boutonMessage.Visibility = action != null ? Visibility.Visible : Visibility.Collapsed;

        var police = new Typeface(texteMessage.FontFamily, FontStyles.Normal, FontWeights.Normal, FontStretches.Normal);
        double largeurTexte = new FormattedText(texte, CultureInfo.CurrentUICulture, FlowDirection.LeftToRight, police, texteMessage.FontSize, Brushes.White, VisualTreeHelper.GetDpi(this).PixelsPerDip).Width;
        double largeurAction = 0;
        if (libelleAction != null)
            largeurAction = 32 + new FormattedText(libelleAction, CultureInfo.CurrentUICulture, FlowDirection.LeftToRight, police, 13, Brushes.Black, VisualTreeHelper.GetDpi(this).PixelsPerDip).Width;
        double l = Math.Clamp(14 + 14 + 10 + largeurTexte + 8 + largeurAction + 14 + 4, 180, Width - 24);
        Montrer(Vue.Message, new Size(l, 40));
        minuterieMessage.Interval = TimeSpan.FromSeconds(action != null ? Math.Max(secondes, 8) : secondes);
        minuterieMessage.Start();
    }

    public void AllerReglages(string langue, bool sons)
    {
        (langue switch { "en" => langueEn, "auto" => langueAuto, _ => langueFr }).IsChecked = true;
        (sons ? sonsOui : sonsNon).IsChecked = true;
        Montrer(Vue.Reglages);
    }

    public void AllerCle(string titre, string? etat)
    {
        titreCle.Text = titre;
        etatCle.Text = etat ?? "";
        etatCle.Foreground = (Brush)FindResource("Orange");
        boutonEnregistrerCle.IsEnabled = true;
        bool deja = VueActuelle == Vue.Cle;
        if (!deja) { var f = Natif.GetForegroundWindow(); avantCle = f == hwnd ? IntPtr.Zero : f; }
        Montrer(Vue.Cle);
        if (!deja)
        {
            RendreInactivable(false);
            Natif.Activer(hwnd);
            Activate();
            champCle.Focus();
            System.Windows.Input.Keyboard.Focus(champCle);
            champCle.SelectAll();
        }
    }

    public void EtatCle(string texte, bool enCours)
    {
        etatCle.Text = texte;
        etatCle.Foreground = enCours ? (Brush)FindResource("Gris") : (Brush)FindResource("Orange");
        boutonEnregistrerCle.IsEnabled = !enCours;
    }

    public void ViderCle() => champCle.Text = "";

    static void OuvrirLien(string url)
    {
        try { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(url) { UseShellExecute = true }); } catch { }
    }
}
