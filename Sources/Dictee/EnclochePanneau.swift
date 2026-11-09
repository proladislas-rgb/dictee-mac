import AppKit
import SwiftUI

/// Une vue SwiftUI qui accepte le premier clic même quand sa fenêtre n'est pas active (✕ et ✓ en mains libres).
final class VueHebergeePremierClic<Contenu: View>: NSHostingView<Contenu> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// La fenêtre de l'encoche : un panneau sans bord, transparent, au-dessus de la barre des menus, qui ne prend jamais
/// le focus et laisse passer les clics (sauf sur ✕ et ✓ en mains libres).
final class PanneauSansFocus: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    // Ne jamais repousser la fenêtre sous la barre des menus.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@MainActor
final class EnclochePanneau {
    let modele = EncocheModele()
    private var fenetre: PanneauSansFocus?
    private var fermeture: DispatchWorkItem?
    private var ouvertureRuban: DispatchWorkItem?

    static func tailleFenetre(pour g: GeometrieEncoche) -> CGSize {
        let largeurMax = g.largeur + 2 * GeometrieEncoche.aile + GeometrieEncoche.rallongeMainsLibres + 2 * 16
        return CGSize(width: ceil(largeurMax), height: g.hauteur + GeometrieEncoche.hauteurRuban + 12)
    }

    /// Mesures de l'écran principal (celui de la barre des menus) : encoche réelle si elle existe, sinon une caméra fictive.
    private func mesurer(_ ecran: NSScreen) -> (GeometrieEncoche, centreX: CGFloat) {
        var g = GeometrieEncoche()
        var centre = ecran.frame.midX
        if let gauche = ecran.auxiliaryTopLeftArea, let droite = ecran.auxiliaryTopRightArea, ecran.safeAreaInsets.top > 0 {
            g.largeur = max(100, ecran.frame.width - gauche.width - droite.width)
            g.hauteur = ecran.safeAreaInsets.top
            centre = ecran.frame.minX + gauche.width + g.largeur / 2
        } else {
            g.hauteur = max(24, ecran.frame.maxY - ecran.visibleFrame.maxY)
        }
        return (g, centre)
    }

    private var reduireLesAnimations: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private func ressort(_ reponse: Double, _ amortissement: Double) -> Animation? {
        reduireLesAnimations ? nil : .spring(response: reponse, dampingFraction: amortissement)
    }

    // MARK: ouvrir / fermer

    func ouvrir(app: NSRunningApplication?, mainsLibres: Bool) {
        fermeture?.cancel(); ouvertureRuban?.cancel()
        guard let ecran = NSScreen.screens.first else { return }
        let (g, centre) = mesurer(ecran)
        let dejaAffichee = fenetre?.isVisible == true
        modele.geometrie = g
        modele.icone = app?.icon
        modele.texte = ""
        modele.fige = false
        modele.message = nil
        if !dejaAffichee { modele.calmerLesBarres() }

        let taille = Self.tailleFenetre(pour: g)
        let cadre = NSRect(x: centre - taille.width / 2, y: ecran.frame.maxY - taille.height, width: taille.width, height: taille.height)
        if fenetre == nil {
            let f = PanneauSansFocus(contentRect: cadre, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            f.isOpaque = false
            f.backgroundColor = .clear
            f.hasShadow = false
            f.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
            f.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            f.hidesOnDeactivate = false
            f.isMovable = false
            f.becomesKeyOnlyIfNeeded = true
            f.animationBehavior = .none
            fenetre = f
        }
        guard let f = fenetre else { return }
        f.setFrame(cadre, display: false)
        let vue = VueHebergeePremierClic(rootView: EncocheVue(m: modele, tailleFenetre: taille))
        vue.frame = NSRect(origin: .zero, size: taille)
        f.contentView = vue
        f.ignoresMouseEvents = !mainsLibres
        f.orderFrontRegardless()

        withAnimation(ressort(0.32, 0.9)) {
            modele.ouverte = true
            modele.mainsLibres = mainsLibres
        }
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            withAnimation(self.ressort(0.34, 0.9)) { self.modele.ruban = true }
        }
        ouvertureRuban = item
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduireLesAnimations ? 0 : 0.11), execute: item)
    }

    func passerEnMainsLibres() {
        guard modele.ouverte else { return }
        fenetre?.ignoresMouseEvents = false
        withAnimation(ressort(0.32, 0.9)) { modele.mainsLibres = true }
    }

    func mettreAJourTexte(_ texte: String) { modele.texte = texte }
    func niveau(_ n: Float) { modele.nouveauNiveau(n) }

    /// Finalisation : les mots passent en blanc, les barres se calment.
    func figer() {
        modele.fige = true
        modele.calmerLesBarres()
    }

    /// Referme l'encoche (fermeture plus vive que l'ouverture), puis retire la fenêtre.
    func fermer() {
        ouvertureRuban?.cancel(); fermeture?.cancel()
        fenetre?.ignoresMouseEvents = true
        modele.calmerLesBarres()
        withAnimation(ressort(0.2, 1)) { modele.ruban = false }
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            withAnimation(self.ressort(0.26, 1)) {
                self.modele.ouverte = false
                self.modele.mainsLibres = false
            }
            let retrait = DispatchWorkItem { [weak self] in
                guard let self, !self.modele.ouverte else { return }
                self.fenetre?.orderOut(nil)
            }
            self.fermeture = retrait
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: retrait)
        }
        fermeture = item
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduireLesAnimations ? 0 : 0.07), execute: item)
    }

    /// Affiche un court message dans le ruban (ex. « Champ protégé, texte copié »), puis referme.
    func afficherMessage(_ texte: String, app: NSRunningApplication?, duree: TimeInterval = 2.2) {
        ouvrir(app: app, mainsLibres: false)
        modele.message = texte
        modele.calmerLesBarres()
        DispatchQueue.main.asyncAfter(deadline: .now() + duree) { [weak self] in
            guard let self, self.modele.message == texte else { return }
            self.fermer()
        }
    }
}
