import AppKit
import SwiftUI
import DicteeCore

/// La vue qui héberge l'îlot : elle accepte le premier clic et dit où est la souris (entrée, déplacement, sortie), en points depuis le centre
/// de l'encoche et le haut de l'écran. C'est le moteur qui décide si la souris est sur la forme ou sur la pastille.
final class VueHebergeeIlot<Contenu: View>: NSHostingView<Contenu> {
    var surPointeur: ((CGPoint?) -> Void)?
    /// La molette ou deux doigts sur le trackpad, au-dessus de l'îlot : passer d'une carte à l'autre (lecture, Centre, accueil).
    var surDefilement: ((NSEvent) -> Void)?
    override func scrollWheel(with event: NSEvent) {
        if let surDefilement { surDefilement(event) } else { super.scrollWheel(with: event) }
    }
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
    private var surveilleReduire: NSObjectProtocol?
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
        // « Réduire les animations » lu en direct (pas seulement au démarrage)
        if surveilleReduire == nil {
            surveilleReduire = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { guard let self else { return }; self.moteur.reduire = self.reduire; self.moteur.lecture.reduire = self.reduire; self.moteur.demarrerBoucle() }
            }
        }
        moteur.donneesChangees()
        ajuster()
    }

    func fermer() {
        retirerMoniteur()
        ecouterLesGlissers(false)
        laisserPasser(false)
        if let surveilleEcran { NotificationCenter.default.removeObserver(surveilleEcran) }
        surveilleEcran = nil
        if let surveilleReduire { NSWorkspace.shared.notificationCenter.removeObserver(surveilleReduire) }
        surveilleReduire = nil
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
        v.surDefilement = { [weak self] e in self?.defilement(e) }
        // le fond de la fenêtre reçoit les fichiers lâchés (l'étagère) ; la vue SwiftUI au-dessus n'en veut pas, ils lui passent dessous
        let c = ConteneurIlot(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        c.panneau = self
        c.registerForDraggedTypes([.fileURL])
        c.addSubview(v)
        f.contentView = c
        fenetre = f; vue = v; conteneur = c
    }

    // MARK: fenêtre

    /// Place la fenêtre sur ce que l'îlot veut couvrir. Elle grandit tout de suite, rétrécit 0,65 s plus tard (le temps que la forme se referme).
    func ajuster() {
        guard let f = fenetre, let ecran else { return }
        let veut = moteur.cache || (!encocheReelle && moteur.resolution.principal == .repos && moteur.pastille == nil && !moteur.depot)
        if veut {
            laisserPasser(false)
            if f.isVisible, moteur.courante == .repos, moteur.geo.allSatisfy(\.fini) { f.orderOut(nil) }
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
        f.ignoresMouseEvents = invisible || moniteurTraversee != nil
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
        // la forme elle-même : le vide à côté du cou (où sont les menus) ne compte pas
        let surForme = moteur.contient(p)
        let surPastille = moteur.rectPastille()?.contains(p) ?? false
        if surForme != sousForme { sousForme = surForme; moteur.survolForme(surForme) }
        if surPastille != sousPastille { sousPastille = surPastille; moteur.survolPastille(surPastille) }
        laisserPasser(!(surForme || surPastille))
    }

    // MARK: défilement (molette, deux doigts)

    /// Un geste de défilement sur l'îlot ouvert : une carte de plus ou de moins (le moteur compte : un geste = une carte, l'inertie
    /// ignorée, un défilement surtout horizontal ne compte pas).
    private func defilement(_ e: NSEvent) {
        let phase: DefilementIlot.Phase
        if e.phase.contains(.began) || e.phase.contains(.mayBegin) { phase = .debut }
        else if e.phase.contains(.ended) || e.phase.contains(.cancelled) { phase = .fin }
        else if e.phase.contains(.changed) || e.phase.contains(.stationary) { phase = .suite }
        else { phase = .aucune }
        // une molette (crans) donne des valeurs en lignes : on les compte comme un cran chacune
        let dy = Double(e.hasPreciseScrollingDeltas ? e.scrollingDeltaY : e.scrollingDeltaY * 10)
        let dx = Double(e.hasPreciseScrollingDeltas ? e.scrollingDeltaX : e.scrollingDeltaX * 10)
        moteur.recevoirDefilement(dy: dy, dx: dx, phase: phase, inertie: e.momentumPhase != [])
    }

    /// Pour les essais : un VRAI événement de défilement (CGEvent → NSEvent) remis à la fenêtre, au point `p`. `phase` : 1 début,
    /// 2 suite, 4 fin, 0 molette ; `inertie` : 1 début, 2 suite, 3 fin (0 : aucune). Rien n'est envoyé au système.
    func envoyerDefilement(dy: Int32, en p: CGPoint, phase: Int64, inertie: Int64 = 0, trackpad: Bool = true) {
        guard let f = fenetre, let ecran, let ev = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: dy, wheel2: 0, wheel3: 0) else { return }
        // position globale (origine en haut à gauche de l'écran principal) du point de l'îlot
        let principal = NSScreen.screens.first?.frame.maxY ?? ecran.frame.maxY
        ev.location = CGPoint(x: centre + p.x, y: principal - (ecran.frame.maxY - p.y))
        ev.setIntegerValueField(.scrollWheelEventIsContinuous, value: trackpad ? 1 : 0)
        ev.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        ev.setIntegerValueField(.scrollWheelEventMomentumPhase, value: inertie)
        ev.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(f.windowNumber))
        ev.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(f.windowNumber))
        guard let e = NSEvent(cgEvent: ev) else { return }
        if e.window === f { f.sendEvent(e) }
        else { vue?.scrollWheel(with: e) }   // sans fenêtre associée, l'événement va droit à la vue de l'îlot (même chemin ensuite)
    }

    // MARK: clics qui traversent

    /// Le vide de la fenêtre (à côté du cou quand l'îlot est déplié, la petite marge autour du compact) laisse passer les clics vers les
    /// menus et les onglets dessous. Pendant que la souris y est, la fenêtre ignore la souris et un moniteur global (installé seulement
    /// à ce moment-là) guette son retour sur la forme ou sa sortie de la fenêtre : rien ne tourne le reste du temps.
    private var moniteurTraversee: Any?
    private func laisserPasser(_ oui: Bool) {
        guard let f = fenetre, !invisible else { return }
        if oui {
            guard moniteurTraversee == nil else { return }
            f.ignoresMouseEvents = true
            moniteurTraversee = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
                MainActor.assumeIsolated { self?.souris(NSEvent.mouseLocation) }
            }
        } else {
            if let m = moniteurTraversee { NSEvent.removeMonitor(m) }
            moniteurTraversee = nil
            f.ignoresMouseEvents = false
        }
    }
    /// La souris vue par le moniteur global (fenêtre traversée) : position en points depuis le centre de l'encoche et le haut de l'écran.
    private func souris(_ ecranPt: NSPoint) {
        guard let f = fenetre, let ecran else { return }
        guard f.frame.contains(ecranPt) else { laisserPasser(false); pointeur(nil); return }
        let p = CGPoint(x: ecranPt.x - centre, y: ecran.frame.maxY - ecranPt.y)
        if moteur.contient(p) || (moteur.rectPastille()?.contains(p) ?? false) { laisserPasser(false); pointeur(p) }
    }

    /// Pour les essais : un vrai événement souris remis à la fenêtre (il passe par les gestes SwiftUI, comme un clic réel), au point `p`
    /// (x depuis le centre de l'encoche, y depuis le haut de l'écran). Rien n'est envoyé au système : la fenêtre seule le reçoit.
    func envoyerSouris(_ type: NSEvent.EventType, en p: CGPoint) {
        guard let f = fenetre, let ecran else { return }
        let local = NSPoint(x: centre + p.x - f.frame.minX, y: ecran.frame.maxY - p.y - f.frame.minY)
        guard let e = NSEvent.mouseEvent(with: type, location: local, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                         windowNumber: f.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1) else { return }
        f.sendEvent(e)
    }

    /// Pour les essais : simule la souris sur la forme ou ailleurs.
    func simulerPointeur(forme: Bool, pastille: Bool = false) {
        if forme != sousForme { sousForme = forme; moteur.survolForme(forme) }
        if pastille != sousPastille { sousPastille = pastille; moteur.survolPastille(pastille) }
    }

    // MARK: étagère (des fichiers glissés sur l'encoche)

    /// Le réglage « Étagère » : on écoute, sans rien prendre, les glissers de la souris (moniteur global : il ne voit que les événements,
    /// il ne les retient pas, et ne demande aucune autorisation). Rien ne tourne entre deux glissers.
    var etagereActive = false { didSet { if etagereActive != oldValue { ecouterLesGlissers(etagereActive) } } }
    /// Des fichiers viennent d'être lâchés sur l'îlot.
    var surDepot: ([URL]) -> Void = { _ in }
    private var moniteurGlisser: Any?
    private var moniteurFinGlisser: Any?
    private var suiviGlisser = SuiviGlisser()
    /// Le glisser en cours porte-t-il des fichiers ? nil : pas encore regardé (on ne lit le presse-papiers du glisser qu'une fois par
    /// glisser, et seulement près de l'encoche).
    private var glisserDeFichiers: Bool?
    /// Des fichiers viennent d'être lâchés : l'îlot les montre un instant, la fin du glisser ne le referme pas.
    private(set) var depotLache = false
    private let pressePapiersGlisser = NSPasteboard(name: .drag)
    /// La fenêtre accepte-t-elle des fichiers lâchés ? (essais)
    var accepteLesFichiers: Bool { (fenetre?.contentView?.registeredDraggedTypes.contains(.fileURL) ?? false) && etagereActive }

    private func ecouterLesGlissers(_ oui: Bool) {
        if oui {
            // en essai (fenêtre invisible), jamais : les vrais glissers de l'utilisateur ne doivent rien ouvrir
            guard moniteurGlisser == nil, !invisible else { return }
            moniteurGlisser = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] e in
                let type = e.type
                MainActor.assumeIsolated { self?.glisserGlobal(type) }
            }
        } else {
            if let m = moniteurGlisser { NSEvent.removeMonitor(m) }
            moniteurGlisser = nil
            finDuGlisser()
        }
    }

    private func glisserGlobal(_ type: NSEvent.EventType) {
        switch type {
        case .leftMouseDown:
            suiviGlisser.bouton(enfonce: true, compte: pressePapiersGlisser.changeCount)
            glisserDeFichiers = nil; depotLache = false
        case .leftMouseDragged:
            guard let p = pointEcran(NSEvent.mouseLocation) else { return }
            glisser(p) { [pressePapiersGlisser, suiviGlisser] in
                suiviGlisser.nouveau(compte: pressePapiersGlisser.changeCount) && Self.contientDesFichiers(pressePapiersGlisser)
            }
        case .leftMouseUp:
            suiviGlisser.bouton(enfonce: false, compte: 0)
            glisserDeFichiers = nil
            finDuGlisser()
        default: break
        }
    }

    static func contientDesFichiers(_ pb: NSPasteboard) -> Bool {
        pb.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
    }

    /// Le pointeur glisse quelque chose en `p` (points depuis le centre de l'encoche et le haut de l'écran). `fichiers` n'est appelé
    /// qu'une fois par glisser, et seulement près de l'encoche : loin d'elle, on ne regarde même pas ce qui est glissé.
    func glisser(_ p: CGPoint, fichiers: () -> Bool) {
        // un fichier qui PART de l'îlot (bandeau « Téléchargé », tuile de la carte) n'ouvre jamais la zone sous lui-même
        guard etagereActive, !moteur.glisserSortant else { return }
        guard moteur.depot || procheEncoche(p) || (moteur.centreOuvert && moteur.contient(p)) else { return }
        if glisserDeFichiers == nil { glisserDeFichiers = fichiers() }
        guard glisserDeFichiers == true else { return }
        approcher(p)
    }

    private func procheEncoche(_ p: CGPoint) -> Bool {
        ApprocheEtagere.proche(x: Double(p.x), y: Double(p.y), demiCamera: Double(moteur.demiCamera), barre: Double(moteur.geometrie.hauteur))
    }

    /// Des fichiers glissés sont en `p` : près de l'encoche, l'îlot s'ouvre en « Déposez ici » et la fenêtre les accepte ; ouvert, il le
    /// reste tant que le pointeur est sur la FORME ou à 40 pt autour (pas sur tout le rectangle de la fenêtre, qui couvre les icônes de
    /// la barre à côté du cou) ; la zone s'éclaire quand le pointeur est sur la forme, le seul endroit où un lâcher est accepté.
    func approcher(_ p: CGPoint) {
        // dans la barre des menus, seulement près du cou (à côté, ce sont les icônes des autres apps) ; dessous, près de la forme
        let marge = CGFloat(ApprocheEtagere.marge)
        let garde = moteur.depot && (p.y < moteur.geometrie.hauteur ? abs(p.x) <= CGFloat(moteur.traceCible.cou) + marge : moteur.contient(p, marge: marge))
        // le Centre ouvert reçoit les fichiers sur toute sa forme (sa case Étagère s'éclaire) : on y lâche un fichier venu du Finder
        let proche = procheEncoche(p) || garde || (moteur.centreOuvert && moteur.contient(p))
        if proche, !moteur.depot {
            moteur.montrerDepot(true)
            if moteur.depot { accepterLeDepot(true) }
        } else if !proche, moteur.depot, !depotLache {
            moteur.montrerDepot(false)
            accepterLeDepot(false)
            // la fenêtre, encore grande le temps que la forme se referme, laisse passer le glisser vers ce qui est dessous
            laisserPasser(true)
        }
        if moteur.depot, !depotLache { moteur.depotSurvole = moteur.contient(p) }
    }
    /// Un lâcher en `p` serait-il accepté ? Seulement sur la forme de « Déposez ici » (pas dans le vide de la fenêtre à côté).
    func peutDeposer(_ p: CGPoint) -> Bool { etagereActive && moteur.depot && !depotLache && moteur.contient(p) }

    /// La zone est ouverte : la fenêtre prend la souris (sinon le dépôt passerait aux menus dessous) ; un petit moniteur guette la fin
    /// du glisser (le premier mouvement sans bouton), au cas où le relâchement ne nous parviendrait pas. Il disparaît avec la zone.
    private func accepterLeDepot(_ oui: Bool) {
        if oui {
            laisserPasser(false)
            if let f = fenetre, !invisible { f.ignoresMouseEvents = false }
            guard moniteurFinGlisser == nil, !invisible else { return }
            moniteurFinGlisser = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseUp]) { [weak self] _ in
                MainActor.assumeIsolated { if NSEvent.pressedMouseButtons & 1 == 0 { self?.finDuGlisser() } }
            }
        } else {
            if let m = moniteurFinGlisser { NSEvent.removeMonitor(m) }
            moniteurFinGlisser = nil
        }
    }

    /// Le glisser est fini (lâché ailleurs, ou annulé) : la zone se referme, sauf si les fichiers viennent d'être lâchés sur l'îlot
    /// (il les montre un instant, puis se referme de lui-même). Le relâchement du bouton peut nous parvenir AVANT le message de dépôt
    /// (l'ordre dépend de macOS) : la zone attend donc `delaiFinGlisser` avant de se refermer, et un dépôt arrivé entre-temps l'emporte.
    func finDuGlisser() {
        glisserDeFichiers = nil
        guard moteur.depot, !depotLache else { accepterLeDepot(false); return }
        // déjà en attente : chaque mouvement de la souris après le glisser ne repousse pas la fermeture
        guard fermetureGlisser == nil else { return }
        let item = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.fermerApresGlisser() } }
        fermetureGlisser = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.delaiFinGlisser, execute: item)
    }
    static let delaiFinGlisser: TimeInterval = 0.3
    private var fermetureGlisser: DispatchWorkItem?
    private func fermerApresGlisser() {
        fermetureGlisser = nil
        accepterLeDepot(false)
        if moteur.depot, !depotLache { moteur.montrerDepot(false) }
    }

    /// Le glisser passe sur la fenêtre de l'îlot (le système le dit lui-même) : s'il n'avait pas été vu venir, la zone s'ouvre ici. Un
    /// glisser parti de Verbe lui-même (`interne` : une tuile de la carte, le fichier du bandeau « Téléchargé ») n'ouvre rien. Vrai : un
    /// lâcher à cet endroit serait accepté.
    func glisserSurLIlot(_ p: CGPoint, interne: Bool = false) -> Bool {
        guard etagereActive, !moteur.cache, !interne, !moteur.glisserSortant else { return false }
        glisserDeFichiers = true
        approcher(p)
        return peutDeposer(p)
    }
    func glisserHorsDeLIlot() { if !depotLache { moteur.depotSurvole = false } }

    /// Des fichiers sont lâchés sur l'îlot : ils sont rangés (des signets, jamais des copies), l'îlot les montre 0,9 s puis se referme.
    @discardableResult
    func deposer(_ urls: [URL]) -> Bool {
        let fichiers = urls.filter(\.isFileURL)
        guard etagereActive, moteur.depot, !fichiers.isEmpty else { finDuGlisser(); return false }
        fermetureGlisser?.cancel(); fermetureGlisser = nil
        depotLache = true
        accepterLeDepot(false)
        surDepot(fichiers)
        moteur.depotTermine()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in MainActor.assumeIsolated { self?.depotLache = false } }
        return true
    }

    /// Un point de l'écran (coordonnées de AppKit) en points depuis le centre de l'encoche et le haut de l'écran ; nil hors de l'écran
    /// de l'îlot.
    func pointEcran(_ e: NSPoint) -> CGPoint? {
        guard let ecran, ecran.frame.insetBy(dx: 0, dy: -1).contains(e) else { return nil }
        return CGPoint(x: e.x - centre, y: ecran.frame.maxY - e.y)
    }

    // MARK: clic ailleurs

    /// Un clic ailleurs referme l'îlot ouvert. Le bouton gauche est jugé au RELÂCHEMENT : s'il a servi à glisser un fichier (vers la case
    /// Étagère du Centre, par exemple), l'îlot reste ouvert ; les autres boutons referment tout de suite.
    private var glisserAuClic = 0
    private func installerMoniteur() {
        guard moniteurClic == nil else { return }
        moniteurClic = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .rightMouseDown, .otherMouseDown]) { [weak self] e in
            let type = e.type
            MainActor.assumeIsolated {
                guard let self else { return }
                switch type {
                case .leftMouseDown: self.glisserAuClic = self.pressePapiersGlisser.changeCount
                case .leftMouseUp:
                    guard self.pressePapiersGlisser.changeCount == self.glisserAuClic, !self.moteur.depot else { return }
                    self.moteur.clicAilleurs()
                default: self.moteur.clicAilleurs()
                }
            }
        }
    }
    private func retirerMoniteur() {
        if let moniteurClic { NSEvent.removeMonitor(moniteurClic) }
        moniteurClic = nil
    }
}

/// Le fond de la fenêtre de l'îlot : il reçoit les fichiers lâchés sur l'encoche (l'étagère). La vue SwiftUI posée dessus ne s'inscrit
/// pour aucun type glissé : le système remonte jusqu'à ce fond.
final class ConteneurIlot: NSView {
    weak var panneau: IlotPanneau?
    /// Pas de rappel périodique pendant que le pointeur ne bouge pas : seulement quand il bouge.
    override func wantsPeriodicDraggingUpdates() -> Bool { false }

    private func point(_ s: NSDraggingInfo) -> CGPoint? {
        guard let w = window else { return nil }
        return panneau?.pointEcran(w.convertPoint(toScreen: s.draggingLocation))
    }
    /// On garde un LIEN vers le fichier (un signet), jamais une copie : le curseur le dit (flèche de lien), si la source le permet.
    static func operation(_ masque: NSDragOperation) -> NSDragOperation {
        masque.contains(.link) ? .link : (masque.contains(.copy) ? .copy : .generic)
    }
    /// Un glisser venu d'une autre app (le Finder, Mail…) : `draggingSource` est nil. Non nil, il part de Verbe lui-même (une tuile de
    /// l'étagère, le bandeau « Téléchargé ») : ce n'est jamais un dépôt.
    private func accepte(_ s: NSDraggingInfo) -> NSDragOperation {
        guard let panneau, let p = point(s), IlotPanneau.contientDesFichiers(s.draggingPasteboard),
              panneau.glisserSurLIlot(p, interne: s.draggingSource != nil) else { return [] }
        return Self.operation(s.draggingSourceOperationMask)
    }
    override func draggingEntered(_ s: NSDraggingInfo) -> NSDragOperation { accepte(s) }
    override func draggingUpdated(_ s: NSDraggingInfo) -> NSDragOperation { accepte(s) }
    override func draggingExited(_ s: NSDraggingInfo?) { panneau?.glisserHorsDeLIlot() }
    override func prepareForDragOperation(_ s: NSDraggingInfo) -> Bool {
        guard let panneau, s.draggingSource == nil, let p = point(s) else { return false }
        return panneau.peutDeposer(p)
    }
    override func performDragOperation(_ s: NSDraggingInfo) -> Bool {
        let urls = s.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return panneau?.deposer(urls) ?? false
    }
}
