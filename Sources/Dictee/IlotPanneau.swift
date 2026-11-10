import AppKit
import SwiftUI
import DicteeCore

/// La vue qui héberge l'îlot : elle accepte le premier clic et dit où est la souris (entrée, déplacement, sortie), en points depuis le centre
/// de l'encoche et le haut de l'écran. C'est le moteur qui décide si la souris est sur la forme ou sur la pastille.
final class VueHebergeeIlot<Contenu: View>: NSHostingView<Contenu> {
    var surPointeur: ((CGPoint?) -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for a in trackingAreas { removeTrackingArea(a) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }
    private func position(_ e: NSEvent) -> CGPoint {
        let p = convert(e.locationInWindow, from: nil)
        return CGPoint(x: p.x - bounds.width / 2, y: isFlipped ? p.y : bounds.height - p.y)
    }
    override func mouseEntered(with event: NSEvent) { fleche(); surPointeur?(position(event)) }
    override func mouseMoved(with event: NSEvent) { fleche(); surPointeur?(position(event)) }
    override func cursorUpdate(with event: NSEvent) { fleche() }
    override func mouseExited(with event: NSEvent) { surPointeur?(nil) }
    private func fleche() { CurseurEnArrierePlan.autoriser(); NSCursor.arrow.set() }
}

/// La fenêtre de l'îlot : un panneau sans bord, transparent, au-dessus de la barre des menus, qui ne prend JAMAIS le focus (l'app au premier
/// plan garde le clavier) et reste visible par-dessus les apps en plein écran. Elle n'épouse que la forme voulue (et la pastille) : au repos
/// à peine plus que les ailes, pour ne jamais prendre un clic aux icônes voisines ; elle grandit seulement quand l'îlot se déplie.
@MainActor
final class IlotPanneau {
    let moteur: IlotMoteur
    private var fenetre: PanneauSansFocus?
    private var vue: VueHebergeeIlot<IlotVue>?
    private var conteneur: NSView?
    private var centre: CGFloat = 0
    private var ecran: NSScreen?
    private var cadreVoulu = CGRect.zero
    private var reduction: DispatchWorkItem?
    private var moniteurClic: Any?
    private var surveilleEcran: NSObjectProtocol?
    private var sousForme = false
    private var sousPastille = false
    /// Mode d'essai : fenêtre transparente qui ne reçoit aucun clic, pour tester sans rien montrer à l'écran.
    var invisible = false
    var cadre: NSRect? { fenetre?.frame }
    var estVisible: Bool { fenetre?.isVisible == true }
    private var reduire: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    init(moteur: IlotMoteur) {
        self.moteur = moteur
        moteur.surFenetre = { [weak self] in self?.ajuster() }
        moteur.surMoniteur = { [weak self] actif in if actif { self?.installerMoniteur() } else { self?.retirerMoniteur() } }
    }

    // MARK: vie

    func demarrer() {
        guard let e = NSScreen.screens.first else { return }
        mesurer(e)
        if fenetre == nil { creerFenetre() }
        if surveilleEcran == nil {
            surveilleEcran = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.recaler() }
            }
        }
        moteur.donneesChangees()
        ajuster()
    }

    func fermer() {
        retirerMoniteur()
        if let surveilleEcran { NotificationCenter.default.removeObserver(surveilleEcran) }
        surveilleEcran = nil
        fenetre?.orderOut(nil)
    }

    private func mesurer(_ e: NSScreen) {
        let (g, c) = GeometrieEncoche.mesurer(e)
        moteur.geometrie = g
        moteur.reduire = reduire
        centre = c
        ecran = e
    }
    /// Une encoche réelle (caméra) : l'îlot vide a sa place dans l'encoche. Sans encoche, l'îlot vide n'existe pas.
    private var encocheReelle: Bool { ecran.map { $0.safeAreaInsets.top > 0 } ?? false }

    private func creerFenetre() {
        let f = PanneauSansFocus(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        f.isOpaque = false
        f.backgroundColor = .clear
        f.hasShadow = false
        // sous la dictée, le filet et la mise à jour (+3, +3, +1 : jamais en même temps), au-dessus de la barre des menus
        f.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
        f.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        f.hidesOnDeactivate = false
        f.isMovable = false
        f.becomesKeyOnlyIfNeeded = true
        f.animationBehavior = .none
        f.appearance = NSAppearance(named: .darkAqua)
        let v = VueHebergeeIlot(rootView: IlotVue(m: moteur))
        v.frame = NSRect(x: 0, y: 0, width: IlotMoteur.largeur, height: IlotMoteur.hauteurMax)
        v.autoresizingMask = []
        v.surPointeur = { [weak self] p in self?.pointeur(p) }
        let c = NSView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        c.addSubview(v)
        f.contentView = c
        fenetre = f; vue = v; conteneur = c
    }

    // MARK: fenêtre

    /// Place la fenêtre sur ce que l'îlot veut couvrir. Elle grandit tout de suite, rétrécit 0,65 s plus tard (le temps que la forme se referme).
    func ajuster() {
        guard let f = fenetre, let ecran else { return }
        let veut = moteur.cache || (!encocheReelle && moteur.resolution.principal == .repos && moteur.pastille == nil)
        if veut {
            if f.isVisible, moteur.poids[VueIlot.repos]?.cible == 1, moteur.geo[4].fini { f.orderOut(nil) }
            else if f.isVisible { retarderMasquage() }
            return
        }
        let r = moteur.fenetreVoulue()
        let grandit = r.width > cadreVoulu.width + 0.5 || r.height > cadreVoulu.height + 0.5 || !f.isVisible
        if grandit { appliquer(r) }
        else if r != cadreVoulu {
            reduction?.cancel()
            let item = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { guard let self else { return }; self.appliquer(self.moteur.fenetreVoulue()) } }
            reduction = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.65, execute: item)
        }
        f.alphaValue = invisible ? 0 : 1
        f.ignoresMouseEvents = invisible
        if !f.isVisible { f.orderFrontRegardless() }
        _ = ecran
    }

    private func retarderMasquage() {
        reduction?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.moteur.cache || self.moteur.resolution.principal == .repos else { return }
                if self.moteur.cache { self.fenetre?.orderOut(nil) }
            }
        }
        reduction = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: item)
    }

    private func appliquer(_ r: CGRect) {
        guard let f = fenetre, let ecran else { return }
        reduction?.cancel()
        cadreVoulu = r
        let cadre = NSRect(x: centre + r.minX, y: ecran.frame.maxY - r.height, width: r.width, height: r.height)
        f.setFrame(cadre, display: false)
        conteneur?.frame = NSRect(origin: .zero, size: cadre.size)
        vue?.frame = NSRect(x: -r.minX - IlotMoteur.largeur / 2, y: cadre.height - IlotMoteur.hauteurMax, width: IlotMoteur.largeur, height: IlotMoteur.hauteurMax)
    }

    private func recaler() {
        guard let e = NSScreen.screens.first else { return }
        mesurer(e)
        cadreVoulu = .zero
        moteur.donneesChangees()
        ajuster()
    }

    // MARK: souris

    private func pointeur(_ p: CGPoint?) {
        guard let p else {
            if sousForme { sousForme = false; moteur.survolForme(false) }
            if sousPastille { sousPastille = false; moteur.survolPastille(false) }
            return
        }
        let surForme = moteur.rectActuel().insetBy(dx: -1, dy: -1).contains(p)
        let surPastille = moteur.rectPastille()?.contains(p) ?? false
        if surForme != sousForme { sousForme = surForme; moteur.survolForme(surForme) }
        if surPastille != sousPastille { sousPastille = surPastille; moteur.survolPastille(surPastille) }
    }

    /// Pour les essais : simule la souris sur la forme ou ailleurs.
    func simulerPointeur(forme: Bool, pastille: Bool = false) {
        if forme != sousForme { sousForme = forme; moteur.survolForme(forme) }
        if pastille != sousPastille { sousPastille = pastille; moteur.survolPastille(pastille) }
    }

    // MARK: clic ailleurs

    private func installerMoniteur() {
        guard moniteurClic == nil else { return }
        moniteurClic = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.moteur.fermer() }
        }
    }
    private func retirerMoniteur() {
        if let moniteurClic { NSEvent.removeMonitor(moniteurClic) }
        moniteurClic = nil
    }
}
