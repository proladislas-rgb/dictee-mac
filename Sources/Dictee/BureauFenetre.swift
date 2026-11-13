import AppKit
import Combine
import SwiftUI
import DicteeCore

/// Les quatre pages de la barre d'onglets (maquette lucarne-app-final.html).
enum PageBureau: String, CaseIterable, Identifiable {
    case aujourdhui = "Aujourd\u{2019}hui", decouvrir = "Découvrir", reunions = "Réunions", reglages = "Réglages"
    var id: String { rawValue }
}

/// Les pages qu'on ouvre d'un clic sur une tuile ou une ligne : elles gardent leur page parente (son onglet reste choisi) et un
/// « ‹ parent » en haut pour y revenir. Rien n'est caché : chaque sous-page a sa tuile ou sa ligne visible.
enum SousPageBureau: Equatable {
    case dictees, journee, bibliotheque, dictee, mots, lucarne, confidentialite

    var parent: PageBureau {
        switch self {
        case .dictees, .journee, .bibliotheque: return .aujourdhui
        case .dictee, .mots, .lucarne, .confidentialite: return .reglages
        }
    }
    var titre: String {
        switch self {
        case .dictees: return "Dictées"
        case .journee: return "Ta journée"
        case .bibliotheque: return "Bibliothèque"
        case .dictee: return "Dictée"
        case .mots: return "Mots"
        case .lucarne: return "Ce qu\u{2019}elle montre"
        case .confidentialite: return "Confidentialité"
        }
    }
}

/// Où en est la fenêtre : la page, et la sous-page ouverte s'il y en a une.
@MainActor
final class NavigationBureau: ObservableObject {
    @Published private(set) var page: PageBureau = .aujourdhui
    @Published private(set) var sousPage: SousPageBureau?
    /// La fenêtre est à l'écran (ni fermée, ni cachée derrière une autre) : les petites scènes de Découvrir ne tournent que là.
    @Published var visible = true
    /// Un endroit d'une page où défiler en arrivant (puis oublié).
    enum Ancre: Hashable { case misesAJour }
    @Published var defilerVers: Ancre?

    func aller(_ p: PageBureau) { page = p; sousPage = nil }
    func ouvrir(_ s: SousPageBureau) { page = s.parent; sousPage = s }
    func revenir() { sousPage = nil }

    /// Les destinations venues d'ailleurs (l'îlot, le panneau compact, le menu) : chacune a sa place dans la nouvelle fenêtre.
    func allerA(_ o: Onglet) {
        switch o {
        case .dictees: ouvrir(.dictees)
        case .journee: ouvrir(.journee)
        case .bibliotheque: ouvrir(.bibliotheque)
        case .mots: ouvrir(.mots)
        case .reunions: aller(.reunions)
        case .reglages: aller(.reglages)
        }
    }
}

/// L'apparence de la fenêtre (clair, sombre, celle du Mac), gardée dans les réglages. Le bouton soleil/lune bascule ; les trois
/// vignettes de Réglages › Apparence choisissent. La fenêtre seule change : l'encoche et ses panneaux restent sombres.
@MainActor
final class ApparenceFenetre: ObservableObject {
    @Published var choix: ApparenceBureau { didSet { if choix != oldValue { ecrire(choix.rawValue); appliquer() } } }
    @Published private(set) var systemeSombre: Bool
    weak var fenetre: NSWindow? { didSet { appliquer() } }
    private let ecrire: (String) -> Void
    private var observation: NSKeyValueObservation?

    var sombre: Bool { choix.sombre(systemeSombre: systemeSombre) }

    /// `lire` / `ecrire` : le réglage (les rendus passent des fermetures muettes, jamais les vrais réglages).
    init(lire: () -> String?, ecrire: @escaping (String) -> Void, systemeSombre: Bool) {
        choix = ApparenceBureau.depuis(lire())
        self.ecrire = ecrire
        self.systemeSombre = systemeSombre
    }

    /// Le Mac passe en clair ou en sombre : « Automatique » suit, et l'icône du bouton aussi.
    func suivreLeMac() {
        observation = NSApp.observe(\.effectiveAppearance, options: [.initial, .new]) { [weak self] app, _ in
            let sombre = app.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            DispatchQueue.main.async { self?.systemeSombre = sombre }
        }
    }

    func basculer() { choix = choix.basculee(systemeSombre: systemeSombre) }

    private func appliquer() {
        fenetre?.appearance = choix == .automatique ? nil : NSAppearance(named: choix == .sombre ? .darkAqua : .aqua)
    }
}

/// D'où viennent les tuiles d'Aujourd'hui qui appartiennent à l'encoche (les rappels, l'étagère) : des fermetures posées par
/// l'AppDelegate. La fenêtre ne connaît pas l'îlot.
struct SourcesAujourdhui {
    var rappels: () -> [Rappel] = { [] }
    var etagere: () -> [ElementEtagere] = { [] }
    /// Les rendez-vous des prochaines heures (calendrier du Mac, seulement s'il est allumé et autorisé).
    var rendezVous: () -> [EvenementAgenda] = { [] }
}

/// La fenêtre de l'app : environ 900 × 560 pt, la barre d'onglets en verre en haut au milieu, alignée sur les boutons de la fenêtre.
@MainActor
final class FenetrePrincipale: NSObject, NSWindowDelegate {
    static let tailleParDefaut = CGSize(width: 900, height: 560)
    static let tailleMinimale = CGSize(width: 760, height: 520)

    let nav = NavigationBureau()
    let dictees: ModeleDictees
    let reunions = ReunionsModele()
    let controleurReunions: ReunionController
    let journee: JourneeModele
    let bibliotheque: BibliothequeModele
    let etatBibliotheque = BibliothequeFenetreEtat()
    let apparence = ApparenceFenetre(lire: { Settings.apparenceFenetre }, ecrire: { Settings.apparenceFenetre = $0 },
                                     systemeSombre: NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
    let aujourdhui: AujourdhuiModele
    private(set) lazy var reglages = ReglagesModele.partage
    private var fenetre: NSWindow?
    var surRevoirPriseEnMain: () -> Void = {}
    var surAutorisations: () -> Void = {}
    var surCle: () -> Void = {}
    var surDesinstaller: () -> Void = {}
    /// « Essayer » d'une tuile de Découvrir : l'AppDelegate le fait faire à la vraie encoche (seulement celles qu'il sait montrer).
    var surEssayer: (Decouverte) -> Void = { _ in }
    /// Celles qu'elle sait montrer en ce moment (une fonction éteinte n'a pas de bouton « Essayer »).
    var essais: () -> Set<Decouverte> = { [] }
    /// La fenêtre fermée, Voxile repasse en arrière-plan : le clavier et la barre des menus reviennent à l'app d'avant (AppDelegate).
    var surFermee: () -> Void = {}

    init(dictees: ModeleDictees, controleurReunions: ReunionController, bibliotheque: BibliothequeModele, sources: SourcesAujourdhui) {
        self.dictees = dictees; self.controleurReunions = controleurReunions; self.bibliotheque = bibliotheque
        journee = JourneeModele(dictees: dictees, reunions: reunions)
        aujourdhui = AujourdhuiModele(store: dictees.store, reunions: reunions.store, sources: sources)
        super.init()
        journee.surOuvrirNote = { [weak self] id in self?.ouvrirNote(id) }
        journee.surOuvrirDictees = { [weak self] in self?.afficher(.dictees) }
        apparence.suivreLeMac()
        // Un autre bureau, une app en plein écran : Voxile repasse en arrière-plan le temps d'y être (l'îlot reste par-dessus) ;
        // de retour sur le bureau de la fenêtre, l'icône revient dans le Dock.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.suivreLeDock(cause: "bureau changé") }
        }
    }

    var estOuverte: Bool { fenetre?.isVisible == true }

    /// Ouvre la fenêtre sur « Aujourd'hui » (icône du Dock, Spotlight, menu).
    func afficherAccueil() { montrer { $0.aller(.aujourdhui) } }

    /// Ouvre Réglages et fait défiler jusqu'aux mises à jour (menu « Rechercher les mises à jour »).
    func afficherMisesAJour() { montrer { $0.aller(.reglages); $0.defilerVers = .misesAJour } }

    /// Ouvre la fenêtre sur une page (menu « Aller »).
    func afficher(page: PageBureau) { montrer { $0.aller(page) } }

    /// Ouvre la fenêtre là où mène une destination venue de l'îlot, du panneau ou du menu.
    func afficher(_ onglet: Onglet) { montrer { $0.allerA(onglet) } }

    private func montrer(_ aller: (NavigationBureau) -> Void) {
        aller(nav)
        reglages.rafraichir()
        if fenetre == nil { creer() }
        guard let f = fenetre else { return }
        preparer(nav.sousPage, nav.page)
        borner(f, cause: "ouverture")
        // Fenêtre ouverte : une vraie app (icône et point dans le Dock, menu de l'app, ⌘Q, « Quitter » au clic droit du Dock), avant
        // de l'activer pour que la barre des menus soit la sienne. Elle s'ouvre sur le bureau actif (`.moveToActiveSpace`).
        mettreDansLeDock(true, cause: "fenêtre ouverte")
        NSApp.activate(ignoringOtherApps: true)
        f.makeKeyAndOrderFront(nil)
        changerVisibilite(true)
    }

    /// Ce qu'une page relit en s'ouvrant.
    private func preparer(_ sous: SousPageBureau?, _ page: PageBureau) {
        switch sous {
        case .dictees: dictees.reinitialiser()
        case .journee: journee.reinitialiser()
        case .bibliotheque: bibliotheque.rafraichir(force: true)
        default: break
        }
        if page == .reunions, sous == nil, reunions.ouverte == nil { reunions.reinitialiser() }
    }

    /// Fenêtre fermée : Voxile repasse en arrière-plan (l'icône quitte le Dock), l'encoche reste.
    func windowWillClose(_ notification: Notification) {
        changerVisibilite(false)
        let active = NSApp.isActive
        mettreDansLeDock(false, cause: "fenêtre fermée")
        if active { surFermee() }
    }

    /// Réduite dans le Dock, elle y garde l'icône ; rouverte, pareil.
    func windowDidMiniaturize(_ notification: Notification) { suivreLeDock(cause: "fenêtre réduite") }
    func windowDidDeminiaturize(_ notification: Notification) { suivreLeDock(cause: "fenêtre rouverte du Dock") }

    /// La place de Voxile dans le Dock selon l'état de la fenêtre (`PresenceDock`) : ouverte sur le bureau actif ou réduite, une
    /// vraie app ; fermée, ou ouverte sur un autre bureau / derrière une app en plein écran, l'arrière-plan.
    private func suivreLeDock(cause: String) {
        guard let f = fenetre else { return }
        let ouverte = f.isVisible || f.isMiniaturized
        mettreDansLeDock(PresenceDock.dansLeDock(fenetreOuverte: ouverte, reduite: f.isMiniaturized, surLeBureauActif: f.isOnActiveSpace), cause: cause)
    }

    private func mettreDansLeDock(_ oui: Bool, cause: String) {
        let voulue: NSApplication.ActivationPolicy = oui ? .regular : .accessory
        guard NSApp.activationPolicy() != voulue else { return }
        NSApp.setActivationPolicy(voulue)
        Log.ecrire("Dock : \(oui ? "icône montrée (app normale)" : "icône retirée (arrière-plan)") — \(cause)")
        // De retour en arrière-plan alors que l'îlot est à l'écran (un autre bureau, une app en plein écran) : ses panneaux sont remis
        // devant, du plus lointain au plus proche (leur ordre ne change pas), pour qu'ils rejoignent l'espace où l'on est.
        if !oui {
            for w in NSApp.orderedWindows.reversed() where w is NSPanel && w.isVisible { w.orderFrontRegardless() }
        }
    }

    /// La fenêtre paraît ou disparaît : ses pages ne recalculent (nouvelle dictée, note qui change) et ne s'animent que visibles.
    /// La vue survit à la fermeture (fenêtre gardée) : `onAppear` / `onDisappear` ne suffisent pas.
    private func changerVisibilite(_ v: Bool) {
        nav.visible = v
        aujourdhui.affichee = v && nav.page == .aujourdhui && nav.sousPage == nil
        journee.affichee = v && nav.sousPage == .journee
        if v { aujourdhui.recalculerSiAffichee(); journee.recalculerSiAffichee() }
    }

    /// Cachée derrière d'autres fenêtres, sur un autre bureau, réduite : les animations s'arrêtent ; de retour, elles reprennent.
    func windowDidChangeOcclusionState(_ notification: Notification) {
        guard let f = fenetre else { return }
        let v = f.occlusionState.contains(.visible)
        if v != nav.visible { changerVisibilite(v) }
    }

    func fermer() { fenetre?.close() }

    /// La fenêtre ramenée dans la partie visible de son écran (ou de l'écran principal si le sien a disparu) : jamais plus grande que
    /// lui, entièrement dedans, même avec une taille enregistrée sur un écran plus grand. À l'ouverture et quand les écrans changent.
    private func borner(_ f: NSWindow, cause: String) {
        guard let ecran = (f.screen ?? NSScreen.main)?.visibleFrame else { return }
        f.minSize = CadreFenetre.minimum(Self.tailleMinimale, dans: ecran)
        let cadre = CadreFenetre.borner(f.frame, dans: ecran, minimum: f.minSize)
        guard cadre != f.frame else { return }
        Log.ecrire("fenêtre : ramenée dans l'écran (\(cause)) \(Int(f.frame.width))×\(Int(f.frame.height)) → \(Int(cadre.width))×\(Int(cadre.height))")
        f.setFrame(cadre, display: true)
    }

    /// Un écran branché, débranché, ou sa résolution changée : la fenêtre ouverte reste dans le sien.
    func ecransChanges() {
        guard let f = fenetre, f.isVisible else { return }
        borner(f, cause: "écrans changés")
    }

    /// Ouvre la note d'une réunion dans la page Réunions.
    func ouvrirNote(_ id: UUID) {
        reunions.ouvrir(id)
        afficher(.reunions)
    }

    /// La vue de la fenêtre (aussi utilisée telle quelle par les rendus PNG).
    func vue() -> BureauVue {
        BureauVue(nav: nav, apparence: apparence, aujourdhui: aujourdhui, dictees: dictees, store: dictees.store, mots: MotsModele.partage,
                  reglages: reglages, reunions: reunions, controleur: controleurReunions, journee: journee,
                  bibliotheque: bibliotheque, etatBibliotheque: etatBibliotheque,
                  actions: ActionsBureau(revoirPriseEnMain: { [weak self] in self?.surRevoirPriseEnMain() },
                                         autorisations: { [weak self] in self?.surAutorisations() },
                                         cle: { [weak self] in self?.surCle() },
                                         desinstaller: { [weak self] in self?.surDesinstaller() },
                                         essayer: { [weak self] d in self?.surEssayer(d) },
                                         essais: { [weak self] in self?.essais() ?? [] },
                                         preparer: { [weak self] sous, page in self?.preparer(sous, page) }))
    }

    private func creer() {
        let ecran = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let taille = CGSize(width: min(Self.tailleParDefaut.width, ecran.width * 0.94), height: min(Self.tailleParDefaut.height, ecran.height * 0.92))
        let f = Self.fabriquer(vue(), taille: taille)
        f.setFrameAutosaveName("VerbeFenetreBureau")
        if !f.setFrameUsingName("VerbeFenetreBureau") { f.center() }
        f.delegate = self
        apparence.fenetre = f
        fenetre = f
    }

    /// La fenêtre et sa vue, construites comme dans l'app (les contrôles de taille de `--rendu-fenetre` passent par ici aussi).
    static func fabriquer<V: View>(_ vue: V, taille: CGSize) -> NSWindow {
        let f = NSWindow(contentRect: NSRect(origin: .zero, size: taille), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        habiller(f)
        f.isReleasedWhenClosed = false
        // S'ouvre sur le bureau où l'on se trouve, pas sur celui où la fenêtre était la dernière fois.
        f.collectionBehavior.insert(.moveToActiveSpace)
        let hote = NSHostingView(rootView: vue)
        // La fenêtre décide de sa taille, jamais le contenu. Par défaut, NSHostingView pose des contraintes de taille idéale
        // (`.intrinsicContentSize`) plus fortes que la taille de la fenêtre : une page haute (une longue réunion, Découvrir) faisait
        // grandir la fenêtre toute seule jusqu'à ~1 500 pt, sous le bas de l'écran, et la fin ne défilait plus (13/11). Les pages
        // prennent la taille de la fenêtre et défilent ; la taille minimale est celle de la fenêtre (`tailleMinimale`).
        hote.sizingOptions = []
        f.contentView = hote
        return f
    }

    /// Le cadre de la fenêtre, le même pour l'app et pour les rendus : titre caché, barre de titre transparente, et une barre d'outils
    /// vide de style « unifié » pour que les trois boutons se posent à la hauteur de la barre d'onglets (centre à 26 pt du haut).
    static func habiller(_ f: NSWindow) {
        f.title = "Voxile"
        f.titleVisibility = .hidden
        f.titlebarAppearsTransparent = true
        f.titlebarSeparatorStyle = .none
        f.isMovableByWindowBackground = false
        f.backgroundColor = NSColor.dynamique(clair: NSColor(hex: 0xFAF7F2), sombre: NSColor(hex: 0x252528))
        let barre = NSToolbar(identifier: "VoxileBureau")
        barre.displayMode = .iconOnly
        barre.allowsUserCustomization = false
        f.toolbar = barre
        f.toolbarStyle = .unified
        f.minSize = NSSize(width: tailleMinimale.width, height: tailleMinimale.height)
    }
}
