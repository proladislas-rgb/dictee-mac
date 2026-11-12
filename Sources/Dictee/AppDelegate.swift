import AppKit
import AVFoundation
import Combine
import DicteeCore

extension Notification.Name {
    /// Le réglage « Icône dans la barre des menus » a changé.
    static let verbeIconeBarre = Notification.Name("verbe.icone.barre")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let options: Options
    private var statusItem: NSStatusItem?
    private var pollTimer: Timer?
    private var voletsDejaOuverts = Set<String>()
    private let clavier = KeyMonitor()
    private let dictee = DictationController()
    private let panneauCompact = PanneauCompact()
    private let filet = FiletPanneau()
    private let priseEnMain = PriseEnMain()
    private let ilot = IlotControleur()
    private var lecture: LectureControleur { ilot.lecture }
    private var microDejaPrepare = false
    private lazy var reunionControleur = ReunionController()
    private lazy var fenetrePrincipale = FenetrePrincipale(dictees: ModeleDictees(), controleurReunions: reunionControleur, bibliotheque: ilot.bibliotheque)
    private var survolStatus: SurvolStatus?
    private var derniereAppExterne: NSRunningApplication?
    private var abonnements = Set<AnyCancellable>()

    init(options: Options) {
        self.options = options
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        Log.ecrire("démarrage Verbe \(version) pid=\(ProcessInfo.processInfo.processIdentifier) sansInterface=\(options.sansInterface)")
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

        // Lancée depuis l'image disque : propose de se placer dans Applications (et de se relancer de là).
        if InstallationApp.proposerDeplacementSiBesoin() { return }

        Polices.enregistrer()
        suivreLesApps()
        panneauCompact.surRecoller = { [weak self] entree, cible in
            guard let self else { return }
            Task { await self.dictee.recoller(entree.texte, dans: cible) }
        }
        panneauCompact.surOuvrirFenetre = { [weak self] onglet in self?.ouvrirFenetre(onglet) }
        // Filet de sécurité : le texte n'est pas arrivé, l'encoche reste ouverte avec le texte (jamais en même temps que le panneau compact).
        dictee.surFilet = { [weak self] texte, cible in self?.ouvrirFilet(texte, cible: cible) }
        filet.surColler = { [weak self] texte, app in
            guard let self else { return }
            Task { await self.dictee.recoller(texte, dans: app) }
        }
        configurerFenetre()
        configurerReunions()
        configurerMiseAJour()
        configurerLecture()
        installerMenuPrincipal()
        panneauCompact.surChangementEtat = { [weak self] ouvert in
            self?.survolStatus?.panneauOuvert = ouvert
            self?.ilot.occupationChangee()
        }
        dictee.surDebut = { [weak self] in
            self?.panneauCompact.fermer(animee: false, rendreLeFocus: false)
            self?.filet.fermer(animee: false, rendreLeFocus: false)
            MiseAJourControleur.partage.occuper()   // jamais de proposition de mise à jour pendant une dictée
        }
        clavier.onAction = { [weak self] action in
            guard let self else { return }
            // Étape 🌐 du premier lancement : le double appui sert d'essai, il ne lance pas de vraie dictée.
            if self.priseEnMain.estOuvert, self.priseEnMain.modele.attendDoubleAppui {
                self.priseEnMain.modele.noterGeste(action)
                if action == .begin(handsFree: true) { self.clavier.reinitialiserGeste() }
                return
            }
            self.dictee.recevoir(action)
        }
        dictee.compteurFrappes = { [weak self] in self?.clavier.frappes ?? 0 }
        dictee.surCapture = { [weak self] actif in self?.mettreIcone(capture: actif) }
        dictee.surFinIndependante = { [weak self] in self?.clavier.reinitialiserGeste() }
        Task.detached { await PrechauffageParole.lancer() }
        dictee.preparer()
        microDejaPrepare = Permissions.microOK
        clavier.demarrer()
        appliquerIcone()
        // l'icône suit l'écran principal (une encoche ou pas) et son réglage
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.appliquerIcone() }
        }
        NotificationCenter.default.addObserver(forName: .verbeIconeBarre, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.appliquerIcone() }
        }
        dictee.surInsertion = { [weak self] texte, appId in
            guard appId == Bundle.main.bundleIdentifier else { return }
            self?.priseEnMain.modele.texteInsere(texte)
        }
        dictee.surEchecInsertion = { [weak self] raison in self?.priseEnMain.modele.insertionImpossible(raison) }
        // Groq n'a pas répondu, la dictée est passée par le Mac : l'îlot le signale ; Groq de nouveau là : le prochain relais se redira
        dictee.surRelais = { [weak self] echec in self?.ilot.relaisDictee(echec) }
        dictee.surGroqReussi = { [weak self] in self?.ilot.groqReussi() }
        dictee.surRelaisIndisponible = { [weak self] texte in self?.ilot.relaisIndisponible(texte) }
        demarrerPriseEnMainSiBesoin()
        Task { await verifierAutorisations() }
        // Tant qu'il manque quelque chose, on surveille (l'accord se donne dans les Réglages, app ouverte) ; tout accordé, on arrête :
        // plus rien ne tourne au repos. Verbe qui revient au premier plan relance une vérification (et la surveillance si besoin).
        relancerLaSurveillanceDesAutorisations()
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.relancerLaSurveillanceDesAutorisations() }
        }
    }

    private func relancerLaSurveillanceDesAutorisations() {
        surveillerAutorisations()
        guard pollTimer == nil, !toutEstAccorde else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.surveillerAutorisations() }
        }
    }
    private var toutEstAccorde: Bool { Permissions.premierManquant == nil && Permissions.microOK && clavier.actif }

    func applicationWillTerminate(_ notification: Notification) {
        // une réunion en cours : son fermé, passages et transcription enregistrés avant de partir (« Refaire la note » au retour)
        reunionControleur.terminerAvantDeQuitter()
        ilot.arreter()
        UsageGroqStore.partage.ecrire()
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
        if toutEstAccorde, pollTimer != nil { pollTimer?.invalidate(); pollTimer = nil; Log.ecrire("autorisations : tout est accordé, la surveillance s'arrête") }
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


    /// Tout est dans l'îlot (Centre, Dictées) : l'icône ❞ n'est là que si on la veut (Réglages › Îlot), ou si l'écran principal n'a pas
    /// d'encoche (l'îlot vide n'y existe pas : sans elle, aucun chemin vers Verbe ni vers « Couper le micro »). Sans icône, rouvrir Verbe
    /// (Finder, Spotlight, Launchpad) ouvre la fenêtre principale (`applicationShouldHandleReopen`).
    private func appliquerIcone() {
        let encoche = PresenceIcone.encochePrincipale
        let voulue = PresenceIcone.montree(reglage: Settings.iconeBarreMenus, encoche: encoche)
        if voulue, statusItem == nil {
            installerIcone()
            Log.ecrire("barre des menus : icône montrée (\(encoche ? "réglage" : "pas d'encoche sur l'écran principal"))")
        } else if !voulue, let item = statusItem {
            panneauCompact.fermer(animee: false, rendreLeFocus: false)
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil; survolStatus = nil
            Log.ecrire("barre des menus : icône retirée (tout est dans l'îlot)")
        }
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

    /// App qui avait le curseur : la dernière app au premier plan qui n'est pas Verbe elle-même.
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
        filet.fermer(animee: false, rendreLeFocus: false)
        let cible = NSWorkspace.shared.frontmostApplication.flatMap { $0.bundleIdentifier == Bundle.main.bundleIdentifier ? nil : $0 } ?? derniereAppExterne
        panneauCompact.modele.reunionEnCours = reunionControleur.enregistre
        panneauCompact.basculer(cible: cible)
    }

    /// Ouvre le filet de sécurité avec ce texte (échec d'écriture, ou « Dernière dictée » du menu).
    private func ouvrirFilet(_ texte: String, cible: NSRunningApplication?) {
        panneauCompact.fermer(animee: false, rendreLeFocus: false)
        filet.ouvrir(texte: texte, cible: cible)
    }

    /// Menu › « Dernière dictée » : le texte de la dernière dictée dans le filet, à copier ou à coller dans l'app au premier plan.
    @objc private func derniereDictee() {
        guard let derniere = HistoriqueStore.shared.historique.entrees.first, !dictee.enCours else { return }
        let cible = NSWorkspace.shared.frontmostApplication.flatMap { $0.bundleIdentifier == Bundle.main.bundleIdentifier ? nil : $0 } ?? derniereAppExterne
        ouvrirFilet(derniere.texte, cible: cible)
    }

    /// Verbe relancé alors qu'il tourne déjà (clic sur son icône dans le Dock, Applications, Launchpad ou Spotlight) :
    /// on ouvre la fenêtre principale au lieu de ne rien faire.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        ouvrirFenetre(.dictees)
        return true
    }

    func ouvrirFenetre(_ onglet: Onglet) {
        fenetrePrincipale.afficher(onglet)
    }

    private func configurerFenetre() {
        let m = fenetrePrincipale.dictees
        // Dans la fenêtre, « recoller » écrit dans la dernière app utilisée avant d'ouvrir Verbe.
        m.surRecoller = { [weak self] entree in
            guard let self else { return }
            let cible = self.derniereAppExterne
            Task { await self.dictee.recoller(entree.texte, dans: cible) }
        }
        m.nomDestination = { [weak self] in self?.derniereAppExterne?.localizedName }
        m.surCopier = { e in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(e.texte, forType: .string)
        }
        m.surEchap = {}
        fenetrePrincipale.surAutorisations = { [weak self] in self?.ouvrirAutorisations() }
        fenetrePrincipale.surRevoirPriseEnMain = { [weak self] in self?.ouvrirPriseEnMain() }
        fenetrePrincipale.surCle = { [weak self] in self?.ouvrirPriseEnMain(etape: .acces, forcerCle: true) }
        fenetrePrincipale.surDesinstaller = { InstallationApp.desinstaller() }
    }

    /// Notes de réunion : ⌥⌘N, entrée du panneau compact, note prête qui ouvre l'onglet Réunions, proposition « Noter cet appel ? ».
    private func configurerReunions() {
        reunionControleur.surOuvrirNote = { [weak self] id in self?.fenetrePrincipale.ouvrirNote(id) }
        fenetrePrincipale.reunions.surNoter = { [weak self] in self?.reunionControleur.basculer() }
        fenetrePrincipale.reunions.surRefaireLaNote = { [weak self] id in self?.reunionControleur.refaireLaNote(id: id) }
        panneauCompact.modele.surNoterLaReunion = { [weak self] in
            self?.panneauCompact.fermer(animee: false, rendreLeFocus: true)
            self?.reunionControleur.basculer()
        }
        clavier.onReunion = { [weak self] in self?.reunionControleur.basculer() }
        // la réunion vit dans l'îlot (plus de fenêtre d'encoche à part) : son état y est poussé, ses gestes en reviennent
        reunionControleur.surIlot = { [weak self] r, annonce in self?.ilot.reunionChangee(r, annonce: annonce) }
        reunionControleur.annonceSurvolee = { [weak self] in self?.ilot.moteur.pointeurSurLaForme ?? false }
        ilot.surReunion = { [weak self] a in self?.reunionControleur.agir(a) }
        reunionControleur.demarrerSurveillanceDesAppels()
    }

    /// Mise à jour automatique : vérification une fois par jour, proposition sous l'encoche (jamais pendant une dictée, une réunion
    /// ni une autre annonce), installation et relance. Voir MiseAJourControleur.
    private func configurerMiseAJour() {
        let maj = MiseAJourControleur.partage
        maj.contexte = { [weak self] in
            guard let self else { return ContexteAffichage() }
            let phase = self.reunionControleur.phase
            return ContexteAffichage(
                dicteeEnCours: self.dictee.enCours,
                reunionEnCours: phase != .repos,   // enregistrement, traitement, note prête, « Noter cet appel ? »
                autreAnnonce: self.panneauCompact.estOuvert || self.filet.estOuvert || self.priseEnMain.estOuvert)
        }
        reunionControleur.$phase.sink { phase in if phase != .repos { MiseAJourControleur.partage.occuper() } }.store(in: &abonnements)
        maj.demarrer()
    }

    /// Lecture en cours dans l'encoche : ce qui occupe l'encoche (dictée, réunion, filet, mise à jour, panneau compact, prise en main)
    /// est relu à chaque changement ; le programme d'aide ne démarre que si le réglage est actif.
    private func configurerLecture() {
        ilot.occupation = { [weak self] in
            guard let self else { return OccupationEncoche() }
            return OccupationEncoche(dictee: self.dictee.panneau.modele.ouverte,
                                     reunion: self.reunionControleur.phase != .repos,
                                     filet: self.filet.estOuvert,
                                     miseAJour: MiseAJourControleur.partage.bande.estOuverte,
                                     autreAnnonce: self.panneauCompact.estOuvert || self.priseEnMain.estOuvert)
        }
        lecture.rubanDictee = { [weak self] in self?.dictee.panneau.modele.ruban ?? false }
        lecture.reserveRuban = { [weak self] r in self?.dictee.panneau.modele.reserveRuban = r }
        dictee.panneau.modele.$ruban.dropFirst().sink { [weak self] _ in self?.ilot.occupationChangee() }.store(in: &abonnements)
        dictee.surChangementEtat = { [weak self] enCours in self?.ilot.dicteeChange(enCours: enCours) }
        dictee.peutCommencer = { [weak self] in self?.ilot.autoriserDictee() ?? true }
        dictee.panneau.modele.$ouverte.dropFirst().sink { [weak self] _ in self?.ilot.occupationChangee() }.store(in: &abonnements)
        reunionControleur.$phase.dropFirst().sink { [weak self] _ in self?.ilot.occupationChangee() }.store(in: &abonnements)
        MiseAJourControleur.partage.bande.etat.$ouverte.dropFirst().sink { [weak self] _ in self?.ilot.occupationChangee() }.store(in: &abonnements)
        filet.surChangementEtat = { [weak self] _ in self?.ilot.occupationChangee() }
        priseEnMain.surChangementEtat = { [weak self] in self?.ilot.occupationChangee() }
        // Îlot : « Coller » de l'accueil, « Noter la réunion » d'un rendez-vous, commandes dictées (accueil ouvert seulement).
        ilot.surColler = { [weak self] texte in
            guard let self else { return }
            let cible = self.derniereAppExterne
            Task { await self.dictee.recoller(texte, dans: cible) }
        }
        ilot.surOuvrirFenetre = { [weak self] onglet in self?.ouvrirFenetre(onglet) }
        // Outils › Presse-papiers › « Coller » : la copie est déjà dans le presse-papiers, ⌘V part dans l'app d'où l'on vient (comme le
        // collage des dictées ; il faut l'Accessibilité, déjà accordée pour la dictée)
        ilot.surCommandeV = { [weak self] in
            guard let self, Permissions.accessibiliteOK else { return false }
            let cible = self.derniereAppExterne
            Task { @MainActor in
                if let cible, !cible.isTerminated, NSWorkspace.shared.frontmostApplication?.processIdentifier != cible.processIdentifier {
                    cible.activate()
                    try? await Task.sleep(for: .milliseconds(150))
                }
                try? await Task.sleep(for: .milliseconds(70))
                Collage.posterCommandeV()
            }
            return true
        }
        ilot.surNoter = { [weak self] _ in
            guard let self, self.reunionControleur.phase == .repos else { return }
            self.reunionControleur.lancer()
        }
        dictee.surInterception = { [weak self] texte in self?.ilot.intercepter(texte) ?? false }
        dictee.surCommandeLucarne = { [weak self] texte in self?.ilot.intercepterLucarne(texte) ?? false }
        dictee.surNoteParClic = { [weak self] texte in self?.ilot.noteParClicEcrite(texte) ?? false }
        // « Dicter une note » dans l'îlot : une dictée lancée d'un clic, sans encoche (la carte montre l'écoute), jamais collée
        ilot.surDicterNote = { [weak self] in self?.dictee.commencerSansEncoche() ?? false }
        ilot.surTerminerNote = { [weak self] in self?.dictee.terminerSansEncoche() }
        dictee.surNiveauSansEncoche = { [weak self] n in self?.ilot.niveauDeNote(n) }
        dictee.surTexteSansEncoche = { [weak self] t in self?.ilot.texteDeNote(t) }
        dictee.surRienEcrit = { [weak self] in self?.ilot.noteSansTexte() }
        clavier.onReinitialisation = { [weak self] in self?.ilot.aiguillageNiveau = AiguillageNiveau() }
        clavier.onCopie = { [weak self] in self?.ilot.copieTapee() }
        // « Volume et luminosité » : les touches spéciales passent par la même écoute ; avalées seulement si l'îlot les montre
        clavier.onNiveau = { [weak self] e, f in
            self?.ilot.toucheNiveau(e, option: f.contains(.maskAlternate), maj: f.contains(.maskShift),
                                    controle: f.contains(.maskControl), commande: f.contains(.maskCommand)) ?? false
        }
        ilot.demarrer()
        // le script des crochets de Claude Code a changé avec cette version : s'il est branché, il est remplacé tout seul (l'ancien gardé à
        // côté), hors du fil principal ; settings.json n'est pas touché (mêmes crochets, même chemin)
        DispatchQueue.global(qos: .utility).async { InstallationClaude.parDefaut.mettreAJourLeScript() }
    }

    @objc private func rechercherLesMisesAJour() {
        let maj = MiseAJourControleur.partage
        // La progression et le résultat se lisent dans Réglages › Compte & données : on l'ouvre.
        ouvrirFenetre(.reglages)
        if maj.modele.disponible != nil, maj.modele.peutInstaller { maj.installer() } else { maj.rechercher(manuel: true) }
    }

    @objc private func noterLaReunion() { reunionControleur.basculer() }
    @objc private func couperOuRouvrirLeMicro() { ilot.couperOuRouvrirLeMicro(depuis: "le menu") }
    @objc private func rendreLaVeille() { ilot.arreterEveil(journal: "éteint depuis le menu") }

    /// Menu de l'app (invisible tant qu'elle n'a pas de Dock, mais ses raccourcis servent la fenêtre) :
    /// ⌘, ouvre la fenêtre, ⌘1-3 changent d'onglet, ⌘W ferme, Édition rend ⌘C ⌘V aux champs de texte.
    private func installerMenuPrincipal() {
        let principal = NSMenu()
        func sousMenu(_ titre: String, _ construire: (NSMenu) -> Void) {
            let item = NSMenuItem(); let menu = NSMenu(title: titre)
            construire(menu); item.submenu = menu; principal.addItem(item)
        }
        sousMenu("Verbe") { m in
            m.addItem(withTitle: "Ouvrir Verbe", action: #selector(ouvrirVerbe), keyEquivalent: ",").target = self
            let noter = m.addItem(withTitle: "Noter la réunion", action: #selector(noterLaReunion), keyEquivalent: "n")
            noter.keyEquivalentModifierMask = [.command, .option]; noter.target = self
            m.addItem(.separator())
            m.addItem(withTitle: "Quitter Verbe", action: #selector(quitter), keyEquivalent: "q").target = self
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
        let noter = menu.addItem(withTitle: reunionControleur.enregistre ? "Arrêter la réunion" : "Noter la réunion", action: #selector(noterLaReunion), keyEquivalent: "n")
        noter.keyEquivalentModifierMask = [.command, .option]; noter.target = self
        // le micro, comme le bouton Micro du Centre : sans encoche (écran externe, MacBook fermé), l'îlot vide n'existe pas, c'est le chemin
        menu.addItem(withTitle: ilot.titreMenuMicro, action: #selector(couperOuRouvrirLeMicro), keyEquivalent: "").target = self
        if let eveil = ilot.titreMenuEveil {
            menu.addItem(withTitle: eveil, action: #selector(rendreLaVeille), keyEquivalent: "").target = self
        }
        let ouvrir = menu.addItem(withTitle: "Ouvrir Verbe", action: #selector(ouvrirVerbe), keyEquivalent: ",")
        ouvrir.target = self
        if !HistoriqueStore.shared.historique.estVide {
            menu.addItem(withTitle: "Dernière dictée", action: #selector(derniereDictee), keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        let maj = MiseAJourControleur.partage.modele
        if let d = maj.disponible, maj.peutInstaller {
            menu.addItem(withTitle: "Installer Verbe \(d.version)…", action: #selector(rechercherLesMisesAJour), keyEquivalent: "").target = self
        } else {
            menu.addItem(withTitle: "Rechercher les mises à jour…", action: #selector(rechercherLesMisesAJour), keyEquivalent: "").target = self
        }
        menu.addItem(withTitle: "Prise en main…", action: #selector(revoirPriseEnMain), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Autorisations…", action: #selector(ouvrirAutorisations), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Ouvrir le journal", action: #selector(ouvrirJournal), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Désinstaller Verbe…", action: #selector(desinstaller), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quitter", action: #selector(quitter), keyEquivalent: "q").target = self
    }

    @objc private func ouvrirAutorisations() {
        let alerte = NSAlert()
        alerte.messageText = "Autorisations de Verbe"
        alerte.informativeText = """
        Micro : \(Permissions.microOK ? "accordé" : "manquant")
        Accessibilité : \(Permissions.accessibiliteOK ? "accordée" : "manquante")
        Surveillance de l'entrée : \(Permissions.surveillanceOK ? "accordée" : "manquante")

        Pour que la touche fn serve à dicter :
        • Réglages Système > Clavier > « Appuyer sur la touche 🌐 pour » : choisis « Ne rien faire » (en ce moment : \(ToucheGlobe.doitEtreReglee(valeur: ToucheGlobe.lire()) ? "à régler" : "réglé")).
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
    @objc private func ouvrirVerbe() { ouvrirFenetre(.dictees) }
    @objc private func ouvrirJournal() { NSWorkspace.shared.open(Log.url) }
    @objc private func desinstaller() { InstallationApp.desinstaller() }
    @objc private func quitter() { NSApp.terminate(nil) }
}

extension PresenceIcone {
    /// L'écran principal (celui de la barre des menus) a-t-il une encoche ?
    @MainActor static var encochePrincipale: Bool { NSScreen.screens.first.map { $0.safeAreaInsets.top > 0 } ?? false }
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
