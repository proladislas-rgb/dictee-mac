import AppKit
import SwiftUI
import DicteeCore

enum Onglet: String, CaseIterable, Identifiable {
    case dictees = "Dictées", journee = "Journée", reunions = "Réunions", mots = "Mots", bibliotheque = "Bibliothèque", reglages = "Réglages"
    var id: String { rawValue }
}

/// Les trois mots du bas : 40 pt, filet fin au-dessus, texte seul (style B).
struct NavigationBasse<Droite: View>: View {
    var courant: Onglet
    var surChoix: (Onglet) -> Void
    var marge: CGFloat = 14
    var hauteur: CGFloat = 40
    var taille: CGFloat = 13
    @ViewBuilder var droite: Droite

    var body: some View {
        HStack(spacing: 16) {
            ForEach(Onglet.allCases) { o in
                LienNavigation(titre: o.rawValue, courant: o == courant, taille: taille, hauteur: hauteur) { surChoix(o) }
            }
            Spacer(minLength: 8)
            droite
        }
        .padding(.horizontal, marge)
        .frame(height: hauteur)
        .overlay(alignment: .top) { Rectangle().fill(Palette.filet).frame(height: 1) }
    }
}

struct LienNavigation: View {
    var titre: String
    var courant: Bool
    var taille: CGFloat
    var hauteur: CGFloat
    var action: () -> Void
    @State private var survol = false
    var body: some View {
        Button(action: action) {
            Text(titre)
                .font(Polices.commande(taille, courant ? .medium : .regular))
                .foregroundStyle(courant ? Palette.texte : (survol ? Palette.texte2 : Palette.texte3))
                .lineLimit(1)
                .fixedSize()
                .frame(height: hauteur)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { survol = $0 }
        .accessibilityAddTraits(courant ? .isSelected : [])
    }
}

/// Aide des touches, à droite de la navigation : « ↑ ↓ choisir   ↵ recoller ».
struct AideTouches: View {
    var taille: CGFloat = 12
    var body: some View {
        HStack(spacing: 8) {
            Text("\u{2191}\u{2193} choisir")
            Text("\u{21B5} recoller")
        }
        .font(Polices.commande(taille))
        .lineLimit(1)
        .fixedSize()
        .foregroundStyle(Palette.texte3)
        .accessibilityHidden(true)
    }
}

/// État d'apparition du panneau (ressort de 200 ms ancré à l'encoche ; fondu seul avec « Réduire les animations »).
@MainActor
final class ApparitionPanneau: ObservableObject {
    @Published var visible = false
    var reduire = false
}

struct PanneauVue: View {
    @ObservedObject var m: ModeleDictees
    @ObservedObject var store: HistoriqueStore
    @ObservedObject var apparition: ApparitionPanneau
    var surOnglet: (Onglet) -> Void
    var curseurFactice = false
    static let taille = CGSize(width: 352, height: 320)

    var body: some View {
        VStack(spacing: 0) {
            DicteesVue(m: m, store: store, metriques: .panneau, curseurFactice: curseurFactice)
                .padding(8)
                .frame(maxHeight: .infinity, alignment: .top)
            NavigationBasse(courant: .dictees, surChoix: surOnglet) { EmptyView() }
        }
        .frame(width: Self.taille.width, height: Self.taille.height)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        .offset(y: apparition.visible || apparition.reduire ? 0 : -44)
        .scaleEffect(apparition.visible || apparition.reduire ? 1 : 0.97, anchor: .top)
        .opacity(apparition.visible ? 1 : 0)
        .frame(width: Self.taille.width, height: Self.taille.height + PanneauCompact.ecartHaut, alignment: .bottom)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Historique des dictées")
    }
}

/// Un panneau qui peut prendre le clavier sans activer l'app (l'app n'a pas de Dock) : l'app précédente reste au premier plan.
final class PanneauClavier: NSPanel {
    var surPerteDeFocus: (() -> Void)?
    /// Touches traitées par le panneau lui-même (Retour, ⌘C, Échap du filet de sécurité). `true` : la touche est consommée.
    var surTouche: ((NSEvent) -> Bool)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    override func resignKey() {
        super.resignKey()
        surPerteDeFocus?()
    }
    override func cancelOperation(_ sender: Any?) { /* Échap est traité par le champ */ }
    override func keyDown(with event: NSEvent) {
        if surTouche?(event) == true { return }
        super.keyDown(with: event)
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if surTouche?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
}

/// Le panneau compact : clic sur les guillemets de la barre des menus, il descend sous l'encoche, la recherche reçoit
/// le focus. Il garde explicitement l'app qui avait le curseur avant l'ouverture : c'est là que « recoller » écrit.
@MainActor
final class PanneauCompact {
    static let ecartHaut: CGFloat = 6
    let modele: ModeleDictees
    let apparition = ApparitionPanneau()
    private var fenetre: PanneauClavier?
    private var moniteurClic: Any?
    private(set) var cible: NSRunningApplication?
    private var retrait: DispatchWorkItem?

    /// Appelés par l'app : recoller le texte dans la cible, ouvrir la fenêtre principale sur un onglet.
    var surRecoller: (EntreeHistorique, NSRunningApplication?) -> Void = { _, _ in }
    var surOuvrirFenetre: (Onglet) -> Void = { _ in }
    var surChangementEtat: (Bool) -> Void = { _ in }

    var estOuvert: Bool { fenetre?.isVisible == true && apparition.visible }

    init(store: HistoriqueStore? = nil) {
        modele = ModeleDictees(store: store)
        modele.surEchap = { [weak self] in self?.fermer() }
        modele.surOuvrirFenetre = { [weak self] in self?.fermer(animee: false); self?.surOuvrirFenetre(.dictees) }
        modele.surRecoller = { [weak self] e in self?.recoller(e) }
        modele.surCopier = { e in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(e.texte, forType: .string)
            Log.ecrire("historique : texte copié (\(e.texte.count) caractères)")
        }
    }

    /// Instant de la dernière fermeture causée par un clic ailleurs : un clic sur les guillemets qui suit aussitôt est
    /// le même geste (fermer), pas une demande de rouvrir.
    private var fermetureParClic = Date.distantPast

    func basculer(cible: NSRunningApplication?) {
        if estOuvert { fermer(); return }
        if Date().timeIntervalSince(fermetureParClic) < 0.3 { return }
        ouvrir(cible: cible)
    }

    func ouvrir(cible: NSRunningApplication?) {
        guard let ecran = NSScreen.screens.first else { return }
        retrait?.cancel()
        self.cible = cible
        apparition.reduire = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        modele.reinitialiser()

        let (g, centre) = GeometrieEncoche.mesurer(ecran)
        let taille = CGSize(width: PanneauVue.taille.width, height: PanneauVue.taille.height + Self.ecartHaut)
        let cadre = NSRect(x: centre - taille.width / 2, y: ecran.frame.maxY - g.hauteur - taille.height, width: taille.width, height: taille.height)
        if fenetre == nil {
            let f = PanneauClavier(contentRect: cadre, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            f.isOpaque = false
            f.backgroundColor = .clear
            f.hasShadow = false
            f.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
            f.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            f.hidesOnDeactivate = false
            f.isMovable = false
            f.animationBehavior = .none
            f.appearance = NSAppearance(named: .darkAqua)
            let vue = NSHostingView(rootView: PanneauVue(m: modele, store: modele.store, apparition: apparition) { [weak self] o in
                self?.fermer(animee: false)
                self?.surOuvrirFenetre(o)
            })
            vue.frame = NSRect(origin: .zero, size: taille)
            f.contentView = vue
            f.surPerteDeFocus = { [weak self] in
                guard let self, self.apparition.visible else { return }
                self.fermetureParClic = Date()
                self.fermer(rendreLeFocus: false)
            }
            fenetre = f
        }
        guard let f = fenetre else { return }
        f.setFrame(cadre, display: false)
        f.orderFrontRegardless()
        f.makeKey()
        withAnimation(apparition.reduire ? .easeOut(duration: GeometrieEncoche.dureeFondu) : .spring(duration: GeometrieEncoche.dureeMouvement, bounce: 0.1)) {
            apparition.visible = true
        }
        installerMoniteur()
        surChangementEtat(true)
        Log.ecrire("panneau compact ouvert, cible = \(cible?.bundleIdentifier ?? "aucune")")
    }

    /// Ferme le panneau. `rendreLeFocus` : redonne le clavier à l'app qui l'avait (utile si le focus a bougé).
    func fermer(animee: Bool = true, rendreLeFocus: Bool = true) {
        guard fenetre?.isVisible == true else { return }
        retirerMoniteur()
        surChangementEtat(false)
        let f = fenetre
        if animee {
            withAnimation(apparition.reduire ? .easeOut(duration: GeometrieEncoche.dureeFondu) : .spring(duration: GeometrieEncoche.dureeMouvement, bounce: 0)) {
                apparition.visible = false
            }
            let item = DispatchWorkItem { [weak self] in
                guard let self, !self.apparition.visible else { return }
                f?.orderOut(nil)
            }
            retrait = item
            DispatchQueue.main.asyncAfter(deadline: .now() + GeometrieEncoche.dureeMouvement + 0.08, execute: item)
        } else {
            apparition.visible = false
            f?.orderOut(nil)
        }
        // L'app précédente n'a jamais été désactivée ; on la réactive seulement si le focus est parti ailleurs.
        if rendreLeFocus, let cible, !cible.isTerminated, NSWorkspace.shared.frontmostApplication?.processIdentifier != cible.processIdentifier {
            cible.activate()
        }
    }

    private func recoller(_ e: EntreeHistorique) {
        let destination = cible
        fermer(animee: false, rendreLeFocus: false)
        surRecoller(e, destination)
    }

    // MARK: clic ailleurs

    private func installerMoniteur() {
        retirerMoniteur()
        moniteurClic = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.fermetureParClic = Date(); self?.fermer(rendreLeFocus: false) }
        }
    }
    private func retirerMoniteur() {
        if let moniteurClic { NSEvent.removeMonitor(moniteurClic) }
        moniteurClic = nil
    }
}
