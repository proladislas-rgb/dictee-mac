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
    /// Où est la Lucarne : nil, dans l'encoche (la dictée s'y montre, noire) ; sinon sa place hors de l'encoche, où la dictée se montre en
    /// verre (LucarneDictee.swift) et l'encoche reste vide. Lu à chaque ouverture.
    var placementLibre: () -> PlacementDictee? = { nil }
    /// La dictée en cours se montre hors de l'encoche (la mini-miniature de la lecture, qui se loge au bout du ruban de l'encoche, n'a
    /// alors pas lieu d'être).
    private(set) var horsEncoche = false
    /// Essais : la fenêtre est là, mais transparente et sans clics.
    var invisible = false
    /// Essais : le cadre de la fenêtre (nil : pas affichée).
    var cadre: NSRect? { fenetre?.isVisible == true ? fenetre?.frame : nil }

    static func tailleFenetre(pour g: GeometrieEncoche) -> CGSize {
        let largeurMax = g.largeur + 2 * GeometrieEncoche.aile + GeometrieEncoche.rallongeMainsLibres + 2 * 16
        return CGSize(width: ceil(largeurMax), height: g.hauteur + GeometrieEncoche.hauteurRuban + 12)
    }

    private func mesurer(_ ecran: NSScreen) -> (GeometrieEncoche, centreX: CGFloat) { GeometrieEncoche.mesurer(ecran) }

    private var reduireLesAnimations: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    /// Ressort amorti de 200 ms, interruptible : une nouvelle animation repart de l'état courant. Sans expansion
    /// quand « Réduire les animations » est actif (l'apparition est alors un fondu).
    private func ressort(rebond: Double) -> Animation? {
        reduireLesAnimations ? nil : .spring(duration: GeometrieEncoche.dureeMouvement, bounce: rebond)
    }

    // MARK: ouvrir / fermer

    func ouvrir(app: NSRunningApplication?, mainsLibres: Bool) {
        fermeture?.cancel()
        guard let ecran = NSScreen.screens.first else { return }
        let (g, centre) = mesurer(ecran)
        let dejaAffichee = fenetre?.isVisible == true
        modele.geometrie = g
        modele.reduire = reduireLesAnimations
        modele.icone = app?.icon
        modele.texte = ""
        modele.fige = false
        modele.message = nil
        if !dejaAffichee { modele.calmerLesBarres(); modele.ruban = false }

        let placement = placementLibre()
        horsEncoche = placement != nil
        let taille = placement?.cadreFenetre.size ?? Self.tailleFenetre(pour: g)
        let cadre = placement?.cadreFenetre
            ?? NSRect(x: centre - taille.width / 2, y: ecran.frame.maxY - taille.height, width: taille.width, height: taille.height)
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
        let vue: NSView = placement.map { VueHebergeePremierClic(rootView: DicteeVerreVue(m: modele, placement: $0)) }
            ?? VueHebergeePremierClic(rootView: EncocheVue(m: modele, tailleFenetre: taille))
        vue.frame = NSRect(origin: .zero, size: taille)
        f.contentView = vue
        f.ignoresMouseEvents = !mainsLibres || invisible
        f.alphaValue = invisible ? 0 : 1
        f.orderFrontRegardless()

        withAnimation(ressort(rebond: 0.12)) {
            modele.ouverte = true
            modele.mainsLibres = mainsLibres
        }
        // Le ruban sort avec les premiers mots (voir `mettreAJourTexte`) : pas de ruban vide.
    }

    func passerEnMainsLibres() {
        guard modele.ouverte else { return }
        fenetre?.ignoresMouseEvents = invisible
        withAnimation(ressort(rebond: 0.12)) { modele.mainsLibres = true }
    }

    func mettreAJourTexte(_ texte: String) {
        modele.texte = texte
        if !texte.isEmpty, modele.ouverte, !modele.ruban, modele.message == nil {
            withAnimation(ressort(rebond: 0.1)) { modele.ruban = true }
        }
    }
    func niveau(_ n: Float) { modele.nouveauNiveau(n) }

    /// Finalisation : les mots passent en blanc (fondu), les barres se calment.
    func figer() {
        modele.fige = true
        modele.calmerLesBarres()
    }

    /// Referme l'encoche (bande et ruban ensemble, 200 ms), puis retire la fenêtre. N'attend jamais rien : l'insertion
    /// du texte ne dépend pas de cette animation.
    func fermer() {
        fermeture?.cancel()
        fenetre?.ignoresMouseEvents = true
        modele.calmerLesBarres()
        withAnimation(ressort(rebond: 0)) {
            modele.ruban = false
            modele.ouverte = false
            modele.mainsLibres = false
        }
        let retrait = DispatchWorkItem { [weak self] in
            guard let self, !self.modele.ouverte else { return }
            self.fenetre?.orderOut(nil)
        }
        fermeture = retrait
        DispatchQueue.main.asyncAfter(deadline: .now() + GeometrieEncoche.dureeMouvement + 0.1, execute: retrait)
    }

    /// Essais : un vrai clic (appui, relâchement) remis à la fenêtre au point global `p` (rien n'est envoyé au système).
    func cliquerEssai(en p: NSPoint) {
        guard let f = fenetre else { return }
        let local = NSPoint(x: p.x - f.frame.minX, y: p.y - f.frame.minY)
        for (type, pression) in [(NSEvent.EventType.leftMouseDown, 1.0), (.leftMouseUp, 0.0)] {
            guard let e = NSEvent.mouseEvent(with: type, location: local, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                             windowNumber: f.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: Float(pression)) else { continue }
            f.sendEvent(e)
        }
    }

    /// Affiche un court message dans le ruban (ex. « Champ protégé, texte copié »), puis referme.
    func afficherMessage(_ texte: String, app: NSRunningApplication?, duree: TimeInterval = 2.2) {
        ouvrir(app: app, mainsLibres: false)
        modele.message = texte
        modele.calmerLesBarres()
        withAnimation(ressort(rebond: 0.1)) { modele.ruban = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + duree) { [weak self] in
            guard let self, self.modele.message == texte else { return }
            self.fermer()
        }
    }
}
