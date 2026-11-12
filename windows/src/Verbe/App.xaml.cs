using System;
using System.Threading;
using System.Windows;

namespace Verbe;

public partial class App : Application
{
    Mutex? unique;
    Controleur? controleur;
    System.Windows.Forms.NotifyIcon? icone;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        unique = new Mutex(true, @"Local\Verbe-dictee-windows", out bool premier);
        if (!premier) { Shutdown(); return; }   // déjà ouvert : l'îlot est là-haut

        DispatcherUnhandledException += (_, a) => { Journal.Ecrire("exception : " + a.Exception); a.Handled = true; };
        AppDomain.CurrentDomain.UnhandledException += (_, a) => Journal.Ecrire("exception fatale : " + a.ExceptionObject);
        Journal.Ecrire($"démarrage Verbe {typeof(App).Assembly.GetName().Version?.ToString(3)} sur {Environment.OSVersion}");

        var reglages = Reglages.Charger();
        var ilot = new IlotFenetre();
        ilot.Show();
        var clavier = new Clavier(ilot.Dispatcher);
        controleur = new Controleur(ilot, clavier, reglages);

        // Icône près de l'horloge : pour retrouver les réglages ou quitter, même si l'îlot est caché (plein écran).
        icone = new System.Windows.Forms.NotifyIcon
        {
            Icon = System.Drawing.Icon.ExtractAssociatedIcon(Environment.ProcessPath!),
            Text = "Verbe · tenir Ctrl + Windows pour dicter",
            Visible = true,
        };
        var menu = new System.Windows.Forms.ContextMenuStrip();
        menu.Items.Add("Réglages", null, (_, _) => controleur.OuvrirReglages());
        menu.Items.Add("Quitter Verbe", null, (_, _) => Shutdown());
        icone.ContextMenuStrip = menu;
        icone.MouseClick += (_, a) => { if (a.Button == System.Windows.Forms.MouseButtons.Left) controleur.OuvrirReglages(); };

        if (e.Args.Length >= 2 && e.Args[0] == "--essai")
        {
            var dossier = e.Args[1];
            ilot.Dispatcher.BeginInvoke(() => Essai.Lancer(dossier, ilot, controleur), System.Windows.Threading.DispatcherPriority.ApplicationIdle);
            return;
        }
        ilot.Dispatcher.BeginInvoke(controleur.Demarrer, System.Windows.Threading.DispatcherPriority.ApplicationIdle);
    }

    protected override void OnExit(ExitEventArgs e)
    {
        controleur?.Fermer();
        if (icone != null) { icone.Visible = false; icone.Dispose(); }
        Journal.Ecrire("arrêt");
        base.OnExit(e);
    }
}
