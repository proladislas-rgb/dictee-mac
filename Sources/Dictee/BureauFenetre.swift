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

    init(dictees: ModeleDictees, controleurReunions: ReunionController, bibliotheque: BibliothequeModele, sources: SourcesAujourdhui) {
        self.dictees = dictees; self.controleurReunions = controleurReunions; self.bibliotheque = bibliotheque
        journee = JourneeModele(dictees: dictees, reunions: reunions)
        aujourdhui = AujourdhuiModele(store: dictees.store, reunions: reunions.store, sources: sources)
        super.init()
        journee.surOuvrirNote = { [weak self] id in self?.ouvrirNote(id) }
        journee.surOuvrirDictees = { [weak self] in self?.afficher(.dictees) }
        apparence.suivreLeMac()
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
        // Verbe reste une app d'arrière-plan (pas d'icône « active » dans le Dock) même fenêtre ouverte : une app « normale »
        // ne peut plus afficher l'encoche par-dessus une app en plein écran (constaté dans le Terminal en plein écran).
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

    /// Fenêtre fermée : Verbe reste discret dans l'encoche et la barre des menus (par sécurité, on garde la politique d'arrière-plan).
    func windowWillClose(_ notification: Notification) {
        changerVisibilite(false)
        NSApp.setActivationPolicy(.accessory)
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
        let f = NSWindow(contentRect: NSRect(origin: .zero, size: taille), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        Self.habiller(f)
        f.isReleasedWhenClosed = false
        // S'ouvre sur le bureau où l'on se trouve, pas sur celui où la fenêtre était la dernière fois.
        f.collectionBehavior.insert(.moveToActiveSpace)
        f.contentView = NSHostingView(rootView: vue())
        f.setFrameAutosaveName("VerbeFenetreBureau")
        if !f.setFrameUsingName("VerbeFenetreBureau") { f.center() }
        f.delegate = self
        apparence.fenetre = f
        fenetre = f
    }

    /// Le cadre de la fenêtre, le même pour l'app et pour les rendus : titre caché, barre de titre transparente, et une barre d'outils
    /// vide de style « unifié » pour que les trois boutons se posent à la hauteur de la barre d'onglets (centre à 26 pt du haut).
    static func habiller(_ f: NSWindow) {
        f.title = "Verbe"
        f.titleVisibility = .hidden
        f.titlebarAppearsTransparent = true
        f.titlebarSeparatorStyle = .none
        f.isMovableByWindowBackground = false
        f.backgroundColor = NSColor.dynamique(clair: NSColor(hex: 0xFAF7F2), sombre: NSColor(hex: 0x252528))
        let barre = NSToolbar(identifier: "VerbeBureau")
        barre.displayMode = .iconOnly
        barre.allowsUserCustomization = false
        f.toolbar = barre
        f.toolbarStyle = .unified
        f.minSize = NSSize(width: tailleMinimale.width, height: tailleMinimale.height)
    }
}
