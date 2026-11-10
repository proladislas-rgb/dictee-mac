import AppKit
import SwiftUI
import DicteeCore

// MARK: mini-miniature

@MainActor
final class MiniatureEtat: ObservableObject {
    @Published var presence: CGFloat = 0
}

struct MiniatureHote: View {
    @ObservedObject var m: LectureModele
    @ObservedObject var etat: MiniatureEtat
    var body: some View {
        MiniatureLectureVue(m: m, presence: etat.presence).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// La mini-miniature de la lecture pendant une dictée. Elle ne s'affiche pas dans la fenêtre de la dictée (qui laisse passer tous les clics) :
/// c'est un tout petit panneau posé exactement sur le bout droit du ruban de texte, qui ne prend jamais le focus et ne capte que son propre clic.
@MainActor
final class LectureMiniature {
    let modele: LectureModele
    let etat = MiniatureEtat()
    private var fenetre: PanneauSansFocus?
    private var retrait: DispatchWorkItem?
    var invisible = false
    private var reduire: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// Réserve à droite du texte du ruban (miniature + marge) pour que le texte dicté ne passe jamais dessous.
    static let reserve: CGFloat = MiniatureLectureVue.cote + 8
    /// Distance entre le bout droit du ruban et le bord droit de la miniature (le coin du ruban est arrondi à 11 pt).
    static let retraitDroit: CGFloat = 12
    static let tailleFenetre = CGSize(width: MiniatureLectureVue.cote + 8, height: GeometrieEncoche.hauteurRuban)

    init(modele: LectureModele) { self.modele = modele }

    /// Le cadre exact : bout droit du ruban de la dictée (centre + moitié de la bande de base − retrait du ruban), à la hauteur du ruban.
    static func cadre(ecran: NSScreen) -> NSRect {
        let (g, centre) = GeometrieEncoche.mesurer(ecran)
        let finRuban = centre + (g.largeur + 2 * GeometrieEncoche.aile) / 2 - GeometrieEncoche.retraitRuban
        let droite = finRuban - retraitDroit + 4          // 4 pt de zone de clic au-delà de la miniature
        return NSRect(x: droite - tailleFenetre.width, y: ecran.frame.maxY - g.hauteur - GeometrieEncoche.hauteurRuban,
                      width: tailleFenetre.width, height: tailleFenetre.height)
    }

    func afficher() {
        retrait?.cancel()
        guard let ecran = NSScreen.screens.first else { return }
        let cadre = Self.cadre(ecran: ecran)
        if fenetre == nil {
            let f = PanneauSansFocus(contentRect: cadre, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            f.isOpaque = false
            f.backgroundColor = .clear
            f.hasShadow = false
            f.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 4)   // au-dessus de la dictée (+3)
            f.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            f.hidesOnDeactivate = false
            f.isMovable = false
            f.becomesKeyOnlyIfNeeded = true
            f.animationBehavior = .none
            f.appearance = NSAppearance(named: .darkAqua)
            let vue = VueHebergeePremierClic(rootView: MiniatureHote(m: modele, etat: etat))
            vue.frame = NSRect(origin: .zero, size: cadre.size)
            f.contentView = vue
            fenetre = f
        }
        guard let f = fenetre else { return }
        f.setFrame(cadre, display: false)
        f.alphaValue = invisible ? 0 : 1
        f.ignoresMouseEvents = invisible
        f.orderFrontRegardless()
        withAnimation(reduire ? .easeOut(duration: GeometrieEncoche.dureeFondu) : .easeOut(duration: 0.28)) { etat.presence = 1 }
    }

    func retirer() {
        guard let f = fenetre, f.isVisible else { etat.presence = 0; return }
        f.ignoresMouseEvents = true
        withAnimation(.easeOut(duration: reduire ? GeometrieEncoche.dureeFondu : 0.2)) { etat.presence = 0 }
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.etat.presence < 0.01 else { return }
            self.fenetre?.orderOut(nil)
        }
        retrait = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    var estVisible: Bool { fenetre?.isVisible == true && etat.presence > 0.01 }
    var cadre: NSRect? { fenetre?.frame }
    func fermer() { fenetre?.orderOut(nil) }
}
