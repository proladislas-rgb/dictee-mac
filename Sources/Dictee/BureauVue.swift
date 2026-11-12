import AppKit
import SwiftUI
import DicteeCore

/// Ce que la fenêtre demande au reste de l'app (prise en main, autorisations, clé, désinstallation, « Essayer ») et ce qu'une page
/// relit en s'ouvrant. Les rendus passent des actions muettes.
struct ActionsBureau {
    var revoirPriseEnMain: () -> Void = {}
    var autorisations: () -> Void = {}
    var cle: () -> Void = {}
    var desinstaller: () -> Void = {}
    var essayer: (Decouverte) -> Void = { _ in }
    /// Les tuiles de Découvrir que l'encoche sait montrer en vrai (« Essayer »), relues à chaque affichage.
    var essais: () -> Set<Decouverte> = { [] }
    var preparer: (SousPageBureau?, PageBureau) -> Void = { _, _ in }
}

/// La fenêtre : un fond chaud (ou gris fumé en sombre), la barre d'onglets en verre en haut au milieu, le bouton soleil/lune à droite,
/// et la page du moment. Une page change en fondu (rien ne glisse quand « Réduire les animations » est allumé).
struct BureauVue: View {
    @ObservedObject var nav: NavigationBureau
    @ObservedObject var apparence: ApparenceFenetre
    @ObservedObject var aujourdhui: AujourdhuiModele
    @ObservedObject var dictees: ModeleDictees
    @ObservedObject var store: HistoriqueStore
    @ObservedObject var mots: MotsModele
    @ObservedObject var reglages: ReglagesModele
    @ObservedObject var reunions: ReunionsModele
    @ObservedObject var controleur: ReunionController
    @ObservedObject var journee: JourneeModele
    @ObservedObject var bibliotheque: BibliothequeModele
    @ObservedObject var etatBibliotheque: BibliothequeFenetreEtat
    var actions = ActionsBureau()
    @Environment(\.accessibilityReduceMotion) private var reduire
    @Environment(\.renduStatique) private var statique

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [TonsBureau.fondHaut, TonsBureau.fondBas], startPoint: .top, endPoint: .bottom)
            page
                .id(cle)
                .transition(.opacity.combined(with: reduire ? .identity : .offset(y: 6)))
                .padding(.top, TonsBureau.margeHaut)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // la bande du haut (hors des onglets et du soleil) déplace la fenêtre, comme une barre de titre
            Color.clear.frame(height: TonsBureau.margeHaut - 10).frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
                .allowsWindowActivationEvents(true)
            BarreBureau(nav: nav, apparence: apparence, preparer: actions.preparer)
        }
        .animation(.easeOut(duration: 0.22), value: cle)
        .ignoresSafeArea()
        .environment(\.colorScheme, apparence.sombre ? .dark : .light)
        // Le micro réellement utilisé peut changer (casque branché) : relu de temps en temps, seulement fenêtre à l'écran (la vue
        // survit à la fermeture de la fenêtre : sans cette garde, la minuterie tournerait pour rien).
        .onReceive(Minuterie.tant(nav.visible, toutesLes: 5)) { _ in reglages.rafraichirMicroUtilise() }
    }

    /// Une clé par écran : la page, ou la sous-page.
    private var cle: String { nav.sousPage.map { "\($0)" } ?? nav.page.rawValue }

    private func revenir() -> (titre: String, action: () -> Void) {
        (nav.page.rawValue, { nav.revenir(); actions.preparer(nil, nav.page) })
    }

    @ViewBuilder private var page: some View {
        if let s = nav.sousPage {
            VStack(alignment: .leading, spacing: 0) {
                EntetePage(petit: "", titre: s.titre, retour: revenir()) { droiteSousPage(s) }
                    .padding(.horizontal, TonsBureau.margeH)
                // la sous-page prend la place qui reste, ni plus ni moins (une page plus haute défile ou se rogne, la barre ne bouge pas)
                GeometryReader { g in sousPage(s).frame(width: g.size.width, height: g.size.height, alignment: .top).clipped() }
            }
        } else {
            switch nav.page {
            case .aujourdhui:
                AujourdhuiVue(m: aujourdhui, controleur: controleur,
                              ouvrir: { s in nav.ouvrir(s); actions.preparer(s, s.parent) },
                              ouvrirNote: { id in
                                  if let id { reunions.ouvrir(id) }
                                  nav.aller(.reunions); actions.preparer(nil, .reunions)
                              },
                              noter: { reunions.surNoter() },
                              visible: nav.visible)
            case .decouvrir:
                DecouvrirVue(essais: actions.essais(), essayer: actions.essayer, actif: nav.visible)
            case .reunions:
                ReunionsPageVue(m: reunions, store: reunions.store, controleur: controleur)
            case .reglages:
                ReglagesBureauVue(r: reglages, store: store, mots: mots, apparence: apparence, nav: nav, actions: actions, visible: nav.visible,
                                  ouvrir: { s in nav.ouvrir(s); actions.preparer(s, s.parent) })
            }
        }
    }

    @ViewBuilder private func droiteSousPage(_ s: SousPageBureau) -> some View {
        switch s {
        case .dictees: PhraseEntete(texte: "Tout ce que tu as dicté, gardé sur ce Mac. Clique une dictée pour la recoller ou la copier.")
        case .mots: PhraseEntete(texte: "Les noms qu\u{2019}il doit bien écrire, et ce que tu dis souvent.")
        default: EmptyView()
        }
    }

    @ViewBuilder private func sousPage(_ s: SousPageBureau) -> some View {
        switch s {
        case .dictees: DicteesFenetreVue(m: dictees, store: store, reglages: reglages)
        case .journee: JourneeVue(m: journee)
        case .bibliotheque: BibliothequeFenetreVue(b: bibliotheque, e: etatBibliotheque, statique: statique).padding(.leading, TonsBureau.margeH)
        case .mots: MotsVue(m: mots).padding(.horizontal, TonsBureau.margeH)
        case .dictee, .lucarne, .confidentialite:
            ReglagesDetailVue(sous: s, r: reglages, store: store, actions: actions)
        }
    }
}

/// La barre du haut : les quatre onglets dans une capsule de verre, centrée sur la ligne des boutons de la fenêtre (26 pt du haut),
/// et le soleil (ou la lune) à droite. Les onglets sont de vrais boutons : un clic, le nom lu par VoiceOver, l'onglet choisi annoncé.
struct BarreBureau: View {
    @ObservedObject var nav: NavigationBureau
    @ObservedObject var apparence: ApparenceFenetre
    var preparer: (SousPageBureau?, PageBureau) -> Void = { _, _ in }
    @Namespace private var espace
    @Environment(\.accessibilityReduceMotion) private var reduire
    /// Le centre de la barre, à la hauteur du centre des boutons de la fenêtre (barre d'outils « unifiée » de macOS 26).
    static let centre: CGFloat = 26
    static let hauteur: CGFloat = 38

    var body: some View {
        ZStack {
            onglets
            HStack {
                Spacer()
                boutonApparence
            }
            .padding(.trailing, 14)
        }
        .frame(height: Self.hauteur)
        .padding(.top, Self.centre - Self.hauteur / 2)
    }

    private var onglets: some View {
        HStack(spacing: 0) {
            ForEach(PageBureau.allCases) { p in
                let choisi = nav.page == p
                Button {
                    withAnimation(reduire ? nil : .spring(duration: 0.45, bounce: 0.18)) { nav.aller(p) }
                    preparer(nil, p)
                } label: {
                    Text(p.rawValue)
                        .font(.system(size: 13.5, weight: choisi ? .semibold : .medium))
                        .foregroundStyle(choisi ? TonsBureau.encre : TonsBureau.encre2)
                        .padding(.horizontal, 17)
                        .frame(height: 32)
                        .background {
                            if choisi {
                                Capsule().fill(TonsBureau.selection)
                                    .shadow(color: .black.opacity(0.1), radius: 1.5, y: 1)
                                    .matchedGeometryEffect(id: "choisi", in: espace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(choisi ? .isSelected : [])
            }
        }
        .padding(3)
        .verre(Capsule())
        .fixedSize()
    }

    private var boutonApparence: some View {
        Button { withAnimation(.easeInOut(duration: 0.35)) { apparence.basculer() } } label: {
            ZStack {
                // le soleil tourne et rapetisse en laissant la place à la lune (un simple fondu avec « Réduire les animations »)
                Image(systemName: "sun.max").opacity(apparence.sombre ? 0 : 1)
                    .rotationEffect(.degrees(apparence.sombre && !reduire ? 60 : 0)).scaleEffect(apparence.sombre && !reduire ? 0.6 : 1)
                Image(systemName: "moon").opacity(apparence.sombre ? 1 : 0)
                    .rotationEffect(.degrees(apparence.sombre || reduire ? 0 : -60)).scaleEffect(apparence.sombre || reduire ? 1 : 0.6)
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(TonsBureau.encre)
            .frame(width: Self.hauteur, height: Self.hauteur)
            .contentShape(Circle())
        }
        .buttonStyle(Enfonce())
        .verre(Circle(), interactif: true)
        .help(apparence.sombre ? "Passer en clair" : "Passer en sombre")
        .accessibilityLabel(apparence.sombre ? "Passer en clair" : "Passer en sombre")
    }
}
