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
    /// L'écran dont l'encoche montre la dictée (celui de la Lucarne : elle peut vivre dans l'encoche d'un écran qui n'est pas le principal).
    var ecranEncoche: () -> NSScreen? = { NSScreen.screens.first }
    /// Hors de l'encoche : la place de la dictée (la fenêtre suit la pilule visée, rien de plus : son vide ne prend aucun clic aux apps
    /// voisines en mains libres).
    private var placement: PlacementDictee?
    private var vueVerre: NSView?
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
        guard let ecran = ecranEncoche() else { return }
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
        self.placement = placement
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
        if let placement {
            // la vue garde la taille de la plus grande pilule ; la fenêtre, elle, n'en montre que la pilule visée (`recadrerVerre`)
            let v = VueHebergeePremierClic(rootView: DicteeVerreVue(m: modele, placement: placement))
            v.frame = NSRect(origin: .zero, size: taille)
            let conteneur = NSView(frame: NSRect(origin: .zero, size: taille))
            conteneur.addSubview(v)
            f.contentView = conteneur
            vueVerre = v
            recadrerVerre(ruban: false, mainsLibres: mainsLibres)
        } else {
            let vue = VueHebergeePremierClic(rootView: EncocheVue(m: modele, tailleFenetre: taille))
            vue.frame = NSRect(origin: .zero, size: taille)
            f.contentView = vue
            vueVerre = nil
        }
        f.ignoresMouseEvents = !mainsLibres || invisible
        f.alphaValue = invisible ? 0 : 1
        f.orderFrontRegardless()

        withAnimation(ressort(rebond: 0.12)) {
            modele.ouverte = true
            modele.mainsLibres = mainsLibres
        }
        // Le journal dit où la dictée s'affiche (13/11 : Hugues ne voyait rien à la place de la Lucarne, sans aucune trace) ; et un
        // filet : si la fenêtre n'est plus à l'écran alors que la dictée l'est, elle revient devant (et on l'écrit).
        if !dejaAffichee {
            signale = false
            Log.ecrire(placement.map { "dictée : affichée à la place de la Lucarne (\($0.place.rawValue)), \(Int(f.frame.minX)),\(Int(f.frame.minY)) \(Int(f.frame.width))×\(Int(f.frame.height))" }
                       ?? "dictée : affichée dans l'encoche")
        }
        surveiller()
        // Le ruban sort avec les premiers mots (voir `mettreAJourTexte`) : pas de ruban vide.
    }

    /// La dictée est ouverte mais sa fenêtre n'est plus à l'écran (retirée, ou cachée par le système) : elle revient devant, et le journal le
    /// dit. Relu 0,4 s après l'ouverture puis toutes les secondes tant que la dictée est ouverte.
    private var veille: DispatchWorkItem?
    private var signale = false
    private func surveiller() {
        veille?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.modele.ouverte, let f = self.fenetre, !self.invisible else { return }
                if !f.isVisible || !f.occlusionState.contains(.visible) {
                    if !self.signale { self.signale = true; Log.ecrire("dictée : fenêtre absente de l'écran alors que la dictée est ouverte (visible \(f.isVisible), occlusion \(f.occlusionState.rawValue), alpha \(f.alphaValue)), remise devant") }
                    f.orderFrontRegardless()
                }
                self.surveiller()
            }
        }
        veille = item
        DispatchQueue.main.asyncAfter(deadline: .now() + (modele.texte.isEmpty ? 0.4 : 1.0), execute: item)
    }

    /// Hors de l'encoche : la fenêtre se cale sur la pilule visée (avec la place de son ombre) ; elle grandit tout de suite, avant la
    /// pilule qui s'allonge dedans ; la vue ne bouge pas à l'écran.
    private func recadrerVerre(ruban: Bool, mainsLibres: Bool) {
        guard let p = placement, let f = fenetre, let v = vueVerre else { return }
        let boite = p.cadreFenetre, r = p.pilule(ruban: ruban, mainsLibres: mainsLibres), m = DicteeVerreVue.marge
        let cadre = NSRect(x: boite.minX + r.minX - m, y: boite.maxY - r.maxY - m, width: r.width + 2 * m, height: r.height + 2 * m)
        f.setFrame(cadre, display: false)
        f.contentView?.frame = NSRect(origin: .zero, size: cadre.size)
        v.frame = NSRect(x: boite.minX - cadre.minX, y: boite.minY - cadre.minY, width: boite.width, height: boite.height)
    }

    func passerEnMainsLibres() {
        guard modele.ouverte else { return }
        recadrerVerre(ruban: modele.ruban || modele.message != nil, mainsLibres: true)
        fenetre?.ignoresMouseEvents = invisible
        withAnimation(ressort(rebond: 0.12)) { modele.mainsLibres = true }
    }

    func mettreAJourTexte(_ texte: String) {
        modele.texte = texte
        if !texte.isEmpty, modele.ouverte, !modele.ruban, modele.message == nil {
            recadrerVerre(ruban: true, mainsLibres: modele.mainsLibres)
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
    func fermer(depuis: String = #fileID, ligne: Int = #line) {
        fermeture?.cancel()
        veille?.cancel(); veille = nil
        // qui la range (13/11 : une dictée sans pilule visible, sans trace ; la prochaine fois, le journal dira d'où vient la fermeture)
        if modele.ouverte, !invisible { Log.ecrire("dictée : rangée (\((depuis as NSString).lastPathComponent):\(ligne))") }
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
        recadrerVerre(ruban: true, mainsLibres: false)
        withAnimation(ressort(rebond: 0.1)) { modele.ruban = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + duree) { [weak self] in
            guard let self, self.modele.message == texte else { return }
            self.fermer()
        }
    }
}
