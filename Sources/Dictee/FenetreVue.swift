import AppKit
import SwiftUI
import DicteeCore

@MainActor
final class NavigationFenetre: ObservableObject {
    @Published var onglet: Onglet = .dictees
}

/// La fenêtre principale (planches 01 et 02) : un titre, un onglet à la fois, trois liens texte en bas, pas de barre latérale.
struct FenetreVue: View {
    @ObservedObject var nav: NavigationFenetre
    @ObservedObject var dictees: ModeleDictees
    @ObservedObject var store: HistoriqueStore
    @ObservedObject var mots: MotsModele
    @ObservedObject var reglages: ReglagesModele
    var surRevoirPriseEnMain: () -> Void = {}
    var surAutorisations: () -> Void = {}
    var surCle: () -> Void = {}
    var surDesinstaller: () -> Void = {}
    var curseurFactice = false
    static let tailleParDefaut = CGSize(width: 960, height: 640)

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                FormeGuillemets().fill(Palette.texte).frame(width: 15, height: 15 / Guillemets.rapport)
                Text("Verbe").font(Polices.commande(15, .medium)).foregroundStyle(Palette.texte)
            }
            .frame(height: 52)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            Group {
                switch nav.onglet {
                case .dictees:
                    DicteesVue(m: dictees, store: store, metriques: .fenetre, invite: "Rechercher dans les dictées", curseurFactice: curseurFactice)
                case .mots:
                    MotsVue(m: mots, curseurFactice: curseurFactice)
                case .reglages:
                    ReglagesVue(r: reglages, store: store, surRevoirPriseEnMain: surRevoirPriseEnMain, surAutorisations: surAutorisations, surCle: surCle, surDesinstaller: surDesinstaller)
                }
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            NavigationBasse(courant: nav.onglet, surChoix: { nav.onglet = $0 }, marge: 28, hauteur: 52, taille: 15) {
                if nav.onglet == .dictees { AideTouches(taille: 13) }
            }
        }
        .background(Palette.surface)
    }
}

/// Fenêtre de l'app : ~960 × 640 (réduite pour les petits écrans), sombre, titre intégré.
@MainActor
final class FenetrePrincipale: NSObject, NSWindowDelegate {
    let nav = NavigationFenetre()
    let dictees: ModeleDictees
    private(set) lazy var reglages = ReglagesModele.partage
    private var fenetre: NSWindow?
    var surRevoirPriseEnMain: () -> Void = {}
    var surAutorisations: () -> Void = {}
    var surCle: () -> Void = {}
    var surDesinstaller: () -> Void = {}

    init(dictees: ModeleDictees) { self.dictees = dictees; super.init() }

    var estOuverte: Bool { fenetre?.isVisible == true }

    func afficher(_ onglet: Onglet) {
        nav.onglet = onglet
        reglages.rafraichir()
        if fenetre == nil { creer() }
        guard let f = fenetre else { return }
        if onglet == .dictees { dictees.reinitialiser() }
        // Tant que la fenêtre est ouverte, Verbe est une app « normale » : icône dans le Dock et dans ⌘Tab.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        f.makeKeyAndOrderFront(nil)
    }

    /// Fenêtre fermée : Verbe redevient discret (plus d'icône dans le Dock), il reste dans l'encoche et la barre des menus.
    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func fermer() { fenetre?.close() }

    private func creer() {
        let ecran = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let taille = CGSize(width: min(FenetreVue.tailleParDefaut.width, ecran.width * 0.92), height: min(FenetreVue.tailleParDefaut.height, ecran.height * 0.92))
        let f = NSWindow(contentRect: NSRect(origin: .zero, size: taille), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        f.title = "Verbe"
        f.titleVisibility = .hidden
        f.titlebarAppearsTransparent = true
        f.isMovableByWindowBackground = false
        f.backgroundColor = NSColor(srgbRed: 26/255, green: 26/255, blue: 25/255, alpha: 1)
        f.appearance = NSAppearance(named: .darkAqua)
        f.isReleasedWhenClosed = false
        f.minSize = NSSize(width: 560, height: 420)
        f.contentView = NSHostingView(rootView: FenetreVue(nav: nav, dictees: dictees, store: dictees.store, mots: MotsModele.partage, reglages: reglages,
                                                           surRevoirPriseEnMain: { [weak self] in self?.surRevoirPriseEnMain() },
                                                           surAutorisations: { [weak self] in self?.surAutorisations() },
                                                           surCle: { [weak self] in self?.surCle() },
                                                           surDesinstaller: { [weak self] in self?.surDesinstaller() }))
        f.setFrameAutosaveName("DicteeFenetrePrincipale")
        if !f.setFrameUsingName("DicteeFenetrePrincipale") { f.center() }
        f.delegate = self
        fenetre = f
    }
}
