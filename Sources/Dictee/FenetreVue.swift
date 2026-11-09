import AppKit
import SwiftUI
import DicteeCore

@MainActor
final class NavigationFenetre: ObservableObject {
    @Published var onglet: Onglet = .dictees
}

/// La fenêtre principale : les onglets en haut (comme les apps du Mac), un onglet à la fois, pas de barre latérale.
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
            // Barre du haut, comme dans les apps du Mac : la place des boutons de fenêtre, puis les onglets, « Réglages » à droite.
            HStack(spacing: 4) {
                Color.clear.frame(width: 84, height: 1)
                OngletBarre(titre: Onglet.dictees.rawValue, actif: nav.onglet == .dictees) { nav.onglet = .dictees }
                OngletBarre(titre: Onglet.mots.rawValue, actif: nav.onglet == .mots, pastille: mots.propositions.enAttente.count) { nav.onglet = .mots }
                OngletBientot(titre: "Réunions")
                Spacer(minLength: 8)
                OngletBarre(titre: Onglet.reglages.rawValue, actif: nav.onglet == .reglages) { nav.onglet = .reglages }
            }
            .padding(.horizontal, 20)
            .frame(height: 52)
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.filet).frame(height: 1) }

            Group {
                switch nav.onglet {
                case .dictees:
                    DicteesFenetreVue(m: dictees, store: store, reglages: reglages, curseurFactice: curseurFactice)
                case .mots:
                    MotsVue(m: mots, curseurFactice: curseurFactice).padding(.horizontal, DicteesFenetreVue.margeH)
                case .reglages:
                    ReglagesVue(r: reglages, store: store, surRevoirPriseEnMain: surRevoirPriseEnMain, surAutorisations: surAutorisations, surCle: surCle, surDesinstaller: surDesinstaller)
                        .padding(.horizontal, DicteesFenetreVue.margeH)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        // La barre des onglets occupe la zone de titre (même ligne que les boutons rouge/jaune/vert) au lieu de se placer dessous.
        .ignoresSafeArea(.container, edges: .top)
        .background(Palette.surface)
        // Le micro réellement utilisé peut changer (casque branché) : relu de temps en temps tant que la fenêtre est ouverte.
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in reglages.rafraichirMicroUtilise() }
    }
}

/// Un onglet de la barre du haut : texte seul, pastille discrète quand il est actif, pastille de nombre éventuelle.
struct OngletBarre: View {
    var titre: String
    var actif: Bool
    var pastille = 0
    var action: () -> Void
    @State private var survol = false
    @FocusState private var focus: Bool
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(titre).font(Polices.commande(14, .medium))
                if pastille > 0 {
                    Text("\(pastille)").font(Polices.commande(12, .medium)).foregroundStyle(Palette.texte)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(Capsule().fill(actif ? Palette.surface : Palette.relief))
                }
            }
            .foregroundStyle(actif ? Palette.texte : (survol ? Palette.texte : Palette.texte2))
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 8).fill(actif ? Palette.relief : (survol ? Palette.selection : .clear)))
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .fixedSize()
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($focus)
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.texte3, lineWidth: 1.5).padding(-2).opacity(focus ? 1 : 0))
        .onHover { survol = $0 }
        .accessibilityLabel(pastille > 0 ? "\(titre), \(pastille) en attente" : titre)
        .accessibilityAddTraits(actif ? .isSelected : [])
    }
}

/// « Réunions · bientôt » : grisé, non cliquable pour l'instant.
struct OngletBientot: View {
    var titre: String
    var body: some View {
        HStack(spacing: 8) {
            Text(titre).font(Polices.commande(14))
            Text("bientôt").font(Polices.commande(12))
                .padding(.horizontal, 8).frame(height: 20)
                .overlay(Capsule().strokeBorder(Palette.contour, lineWidth: 1))
        }
        .foregroundStyle(Palette.texte3)
        .padding(.horizontal, 12)
        .frame(height: 32)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(titre), bientôt disponible")
        .accessibilityAddTraits(.isStaticText)
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
        // Barre de titre « unifiée » de 52 px : les boutons rouge/jaune/vert sont centrés sur la ligne des onglets.
        f.toolbar = NSToolbar(identifier: "VerbeBarre")
        f.toolbarStyle = .unified
        f.titlebarSeparatorStyle = .none
        // S'ouvre sur le bureau où l'on se trouve, pas sur celui où la fenêtre était la dernière fois.
        f.collectionBehavior.insert(.moveToActiveSpace)
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
