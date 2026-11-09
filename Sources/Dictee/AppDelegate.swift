import AppKit
import AVFoundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let options: Options
    private var statusItem: NSStatusItem?
    private var pollTimer: Timer?
    private var voletsDejaOuverts = Set<String>()
    private let clavier = KeyMonitor()
    private let dictee = DictationController()
    private let panneauCompact = PanneauCompact()
    private let priseEnMain = PriseEnMain()
    private var microDejaPrepare = false
    private lazy var fenetrePrincipale = FenetrePrincipale(dictees: ModeleDictees())
    private var survolStatus: SurvolStatus?
    private var derniereAppExterne: NSRunningApplication?

    init(options: Options) {
        self.options = options
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        Log.ecrire("démarrage Dictee \(version) pid=\(ProcessInfo.processInfo.processIdentifier) sansInterface=\(options.sansInterface)")
        Log.ecrire("autorisations : \(Permissions.resume())")

        if let autre = autreInstance() {
            Log.ecrire("une autre instance tourne déjà (pid \(autre.processIdentifier)), on quitte")
            Log.vider()
            exit(0)
        }

        if options.sansInterface {
            if let chemin = options.verifierParole {
                // Vérification de la reconnaissance en direct d'Apple avec un fichier son (sans micro).
                Task {
                    await VerifierParole.executer(chemin: chemin)
                    Log.vider()
                    NSApp.terminate(nil)
                }
                return
            }
            if let d = options.duree {
                DispatchQueue.main.asyncAfter(deadline: .now() + d) {
                    Log.ecrire("fin de la vérification")
                    Log.vider()
                    NSApp.terminate(nil)
                }
            }
            return
        }

        Polices.enregistrer()
        suivreLesApps()
        panneauCompact.surRecoller = { [weak self] entree, cible in
            guard let self else { return }
            Task { await self.dictee.recoller(entree.texte, dans: cible) }
        }
        panneauCompact.surOuvrirFenetre = { [weak self] onglet in self?.ouvrirFenetre(onglet) }
        configurerFenetre()
        installerMenuPrincipal()
        panneauCompact.surChangementEtat = { [weak self] ouvert in self?.survolStatus?.panneauOuvert = ouvert }
        dictee.surDebut = { [weak self] in self?.panneauCompact.fermer(animee: false, rendreLeFocus: false) }
        clavier.onAction = { [weak self] action in self?.dictee.recevoir(action) }
        dictee.compteurFrappes = { [weak self] in self?.clavier.frappes ?? 0 }
        dictee.surCapture = { [weak self] actif in self?.mettreIcone(capture: actif) }
        dictee.surFinIndependante = { [weak self] in self?.clavier.reinitialiserGeste() }
        Task.detached { await PrechauffageParole.lancer() }
        dictee.preparer()
        microDejaPrepare = Permissions.microOK
        clavier.demarrer()
        installerIcone()
        dictee.surInsertion = { [weak self] texte, appId in
            guard appId == Bundle.main.bundleIdentifier else { return }
            self?.priseEnMain.modele.texteInsere(texte)
        }
        dictee.surEchecInsertion = { [weak self] raison in self?.priseEnMain.modele.insertionImpossible(raison) }
        demarrerPriseEnMainSiBesoin()
        Task { await verifierAutorisations() }
        // Tant qu'il manque quelque chose, on surveille (l'accord se donne dans les Réglages, app ouverte).
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.surveillerAutorisations() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Log.ecrire("arrêt")
        Log.vider()
    }

    private func autreInstance() -> NSRunningApplication? {
        guard let id = Bundle.main.bundleIdentifier else { return nil }
        let moi = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: id).first { $0.processIdentifier != moi }
    }

    // MARK: autorisations

    /// Premier lancement : trois étapes sous l'encoche. Une install déjà complète (accès accordés et clé présente) n'en a pas besoin.
    private func demarrerPriseEnMainSiBesoin() {
        guard !Settings.premierLancementFait else { return }
        if Permissions.toutesOK && CleGroq.etat != .absente {
            Settings.premierLancementFait = true
            Log.ecrire("prise en main : installation déjà complète, non affichée (relançable depuis les Réglages)")
            return
        }
        priseEnMain.ouvrir()
    }

    func ouvrirPriseEnMain(etape: PriseEnMainModele.Etape = .geste, forcerCle: Bool = false) {
        panneauCompact.fermer(animee: false, rendreLeFocus: false)
        priseEnMain.ouvrir(etape: etape, forcerCle: forcerCle)
    }

    private func verifierAutorisations() async {
        // Pendant la prise en main, c'est elle qui guide : pas de volet des Réglages ouvert tout seul.
        guard Settings.premierLancementFait else { return }
        if let volet = await Permissions.demanderLePremierManquant() { voletsDejaOuverts.insert(volet.rawValue) }
    }

    private var derniereSituation = ""
    private func surveillerAutorisations() {
        // Le tap clavier n'a pu être créé qu'une fois les autorisations données : on réessaie.
        if !clavier.actif { clavier.demarrer() }
        let situation = Permissions.resume() + " clavier=\(clavier.actif ? "oui" : "non")"
        if Permissions.microOK, !microDejaPrepare { microDejaPrepare = true; dictee.microAutorise() }
        guard situation != derniereSituation else { return }
        derniereSituation = situation
        Log.ecrire("autorisations : \(situation)")
        // Quelque chose vient d'être accordé : on passe à la suite sans rouvrir ce qui est déjà fait.
        guard Settings.premierLancementFait else { return }
        if let manquant = Permissions.premierManquant, !voletsDejaOuverts.contains(manquant.rawValue) {
            voletsDejaOuverts.insert(manquant.rawValue)
            Task { await Permissions.demanderLePremierManquant() }
        }
    }

    // MARK: icône de la barre des menus (guillemets ; trait ambre pendant la capture)

    func mettreIcone(capture: Bool) {
        statusItem?.button?.image = IconeBarre.image(capture: capture)
    }


    private func installerIcone() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let bouton = item.button {
            bouton.image = IconeBarre.image(capture: false)
            bouton.target = self
            bouton.action = #selector(clicIcone(_:))
            bouton.sendAction(on: [.leftMouseUp, .rightMouseUp])
            survolStatus = SurvolStatus(bouton: bouton)
        }
        statusItem = item
    }

    /// App qui avait le curseur : la dernière app au premier plan qui n'est pas Dictée elle-même.
    private func suivreLesApps() {
        derniereAppExterne = NSWorkspace.shared.frontmostApplication.flatMap { $0.bundleIdentifier == Bundle.main.bundleIdentifier ? nil : $0 }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
            MainActor.assumeIsolated { self?.derniereAppExterne = app }
        }
    }

    /// Clic gauche : le panneau compact. Clic droit (ou ctrl-clic) : le menu.
    @objc private func clicIcone(_ sender: NSStatusBarButton) {
        let evenement = NSApp.currentEvent
        let menuDemande = evenement?.type == .rightMouseUp || evenement?.modifierFlags.contains(.control) == true
        if menuDemande {
            panneauCompact.fermer(animee: false, rendreLeFocus: false)
            let menu = NSMenu()
            menu.delegate = self
            reconstruireMenu(menu)
            statusItem?.menu = menu
            sender.performClick(nil)
            statusItem?.menu = nil
            return
        }
        // une dictée en cours garde la place : le panneau et la dictée ne se superposent pas
        guard !dictee.enCours else { return }
        let cible = NSWorkspace.shared.frontmostApplication.flatMap { $0.bundleIdentifier == Bundle.main.bundleIdentifier ? nil : $0 } ?? derniereAppExterne
        panneauCompact.basculer(cible: cible)
    }

    func ouvrirFenetre(_ onglet: Onglet) {
        fenetrePrincipale.afficher(onglet)
    }

    private func configurerFenetre() {
        let m = fenetrePrincipale.dictees
        // Dans la fenêtre, « recoller » écrit dans la dernière app utilisée avant d'ouvrir Dictée.
        m.surRecoller = { [weak self] entree in
            guard let self else { return }
            let cible = self.derniereAppExterne
            Task { await self.dictee.recoller(entree.texte, dans: cible) }
        }
        m.surCopier = { e in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(e.texte, forType: .string)
        }
        m.surEchap = {}
        fenetrePrincipale.surAutorisations = { [weak self] in self?.ouvrirAutorisations() }
        fenetrePrincipale.surRevoirPriseEnMain = { [weak self] in self?.ouvrirPriseEnMain() }
        fenetrePrincipale.surCle = { [weak self] in self?.ouvrirPriseEnMain(etape: .acces, forcerCle: true) }
    }

    /// Menu de l'app (invisible tant qu'elle n'a pas de Dock, mais ses raccourcis servent la fenêtre) :
    /// ⌘, ouvre la fenêtre, ⌘1-3 changent d'onglet, ⌘W ferme, Édition rend ⌘C ⌘V aux champs de texte.
    private func installerMenuPrincipal() {
        let principal = NSMenu()
        func sousMenu(_ titre: String, _ construire: (NSMenu) -> Void) {
            let item = NSMenuItem(); let menu = NSMenu(title: titre)
            construire(menu); item.submenu = menu; principal.addItem(item)
        }
        sousMenu("Dictée") { m in
            m.addItem(withTitle: "Ouvrir Dictée", action: #selector(ouvrirDictee), keyEquivalent: ",").target = self
            m.addItem(.separator())
            m.addItem(withTitle: "Quitter Dictée", action: #selector(quitter), keyEquivalent: "q").target = self
        }
        sousMenu("Édition") { m in
            m.addItem(withTitle: "Annuler", action: Selector(("undo:")), keyEquivalent: "z")
            let refaire = m.addItem(withTitle: "Rétablir", action: Selector(("redo:")), keyEquivalent: "z"); refaire.keyEquivalentModifierMask = [.command, .shift]
            m.addItem(.separator())
            m.addItem(withTitle: "Couper", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
            m.addItem(withTitle: "Copier", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
            m.addItem(withTitle: "Coller", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
            m.addItem(withTitle: "Tout sélectionner", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        }
        sousMenu("Aller") { m in
            for (i, o) in Onglet.allCases.enumerated() {
                let it = m.addItem(withTitle: o.rawValue, action: #selector(allerA(_:)), keyEquivalent: "\(i + 1)")
                it.target = self; it.tag = i
            }
        }
        sousMenu("Fenêtre") { m in
            m.addItem(withTitle: "Réduire", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
            m.addItem(withTitle: "Fermer", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        }
        NSApp.mainMenu = principal
    }

    @objc private func allerA(_ sender: NSMenuItem) { ouvrirFenetre(Onglet.allCases[sender.tag]) }

    func menuNeedsUpdate(_ menu: NSMenu) { reconstruireMenu(menu) }

    private func reconstruireMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        func ligne(_ titre: String, ok: Bool) {
            let it = NSMenuItem(title: "\(ok ? "✓" : "✗")  \(titre)", action: nil, keyEquivalent: "")
            it.isEnabled = false
            menu.addItem(it)
        }
        ligne("Micro", ok: Permissions.microOK)
        ligne("Accessibilité (coller le texte)", ok: Permissions.accessibiliteOK)
        ligne("Surveillance de l'entrée (touche fn)", ok: Permissions.surveillanceOK)
        menu.addItem(.separator())
        let ouvrir = menu.addItem(withTitle: "Ouvrir Dictée", action: #selector(ouvrirDictee), keyEquivalent: ",")
        ouvrir.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Prise en main…", action: #selector(revoirPriseEnMain), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Autorisations…", action: #selector(ouvrirAutorisations), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Ouvrir le journal", action: #selector(ouvrirJournal), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quitter", action: #selector(quitter), keyEquivalent: "q").target = self
    }

    @objc private func ouvrirAutorisations() {
        let alerte = NSAlert()
        alerte.messageText = "Autorisations de Dictée"
        alerte.informativeText = """
        Micro : \(Permissions.microOK ? "accordé" : "manquant")
        Accessibilité : \(Permissions.accessibiliteOK ? "accordée" : "manquante")
        Surveillance de l'entrée : \(Permissions.surveillanceOK ? "accordée" : "manquante")

        Pour que la touche fn serve à dicter :
        • Réglages Système > Clavier > « Appuyer sur 🌐 pour » : choisis « Ne rien faire », sinon les emoji s'ouvrent.
        • Si Wispr Flow tourne, coupe son raccourci fn : les deux apps ne peuvent pas partager la même touche.
        """
        alerte.addButton(withTitle: Permissions.premierManquant == nil ? "Fermer" : "Ouvrir le volet qui manque")
        if Permissions.premierManquant != nil { alerte.addButton(withTitle: "Fermer") }
        NSApp.activate(ignoringOtherApps: true)
        if alerte.runModal() == .alertFirstButtonReturn, Permissions.premierManquant != nil {
            Task { await Permissions.demanderLePremierManquant() }
        }
    }

    @objc private func revoirPriseEnMain() { ouvrirPriseEnMain() }
    @objc private func ouvrirDictee() { ouvrirFenetre(.dictees) }
    @objc private func ouvrirJournal() { NSWorkspace.shared.open(Log.url) }
    @objc private func quitter() { NSApp.terminate(nil) }
}

/// Fond anthracite doux derrière les guillemets de la barre des menus : au survol, ou quand le panneau est ouvert.
@MainActor
final class SurvolStatus: NSObject {
    private weak var bouton: NSStatusBarButton?
    private var survol = false
    var panneauOuvert = false { didSet { appliquer() } }

    init(bouton: NSStatusBarButton) {
        self.bouton = bouton
        super.init()
        bouton.wantsLayer = true
        bouton.layer?.cornerRadius = 5
        bouton.layer?.cornerCurve = .continuous
        bouton.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    @objc func mouseEntered(_ event: NSEvent) { survol = true; appliquer() }
    @objc func mouseExited(_ event: NSEvent) { survol = false; appliquer() }

    private func appliquer() {
        bouton?.layer?.backgroundColor = survol || panneauOuvert ? Palette.nsSelectionCG : NSColor.clear.cgColor
    }
}
