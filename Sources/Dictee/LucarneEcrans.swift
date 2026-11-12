import AppKit
import DicteeCore

// La Lucarne et le système : les écrans (NSScreen → EcranIlot → EcranLucarne), le Dock (ses préférences, lues sans rien écrire, relues
// seulement quand elles changent), la mémoire des places (une par écran, et l'écran choisi), la vibration ; et la fenêtre de l'îlot en
// régime libre (docs/plan-lucarne-deplacable.md, missions 2 et 4).

/// Un écran tel que l'îlot le voit : sa clé dans la mémoire des places (l'UUID de CoreGraphics, stable d'un branchement à l'autre), son
/// cadre et sa zone visible (repère global d'AppKit), l'encoche mesurée et son centre. `ecran` : celui d'AppKit, pour la cadence de la
/// boucle (nil : un faux écran des essais).
struct EcranIlot {
    var id: String
    /// `frame` d'AppKit (même nom : le panneau lit `ecran.frame` comme avant).
    var frame: CGRect
    var zoneVisible: CGRect
    var geometrie: GeometrieEncoche
    /// Le centre de l'encoche (x global d'AppKit) ; le milieu de l'écran s'il n'y en a pas.
    var centre: CGFloat
    weak var ecran: NSScreen?

    init(id: String, frame: CGRect, zoneVisible: CGRect, geometrie: GeometrieEncoche, centre: CGFloat, ecran: NSScreen? = nil) {
        self.id = id; self.frame = frame; self.zoneVisible = zoneVisible; self.geometrie = geometrie; self.centre = centre; self.ecran = ecran
    }

    @MainActor
    init(_ e: NSScreen) {
        let (g, c) = GeometrieEncoche.mesurer(e)
        self.init(id: Self.uuid(de: e), frame: e.frame, zoneVisible: e.visibleFrame, geometrie: g, centre: c, ecran: e)
    }

    /// L'UUID de l'écran (CoreGraphics) ; à défaut, son numéro.
    @MainActor
    static func uuid(de e: NSScreen) -> String {
        guard let n = e.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return "ecran" }
        let id = CGDirectDisplayID(n.uint32Value)
        guard let u = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return "ecran-\(id)" }
        return (CFUUIDCreateString(nil, u) as String?) ?? "ecran-\(id)"
    }
}

/// Tout ce que la Lucarne lit ou écrit hors d'elle : injectable, l'essai ne touche jamais aux vrais écrans, au vrai Dock ni aux vrais
/// réglages.
struct SystemeLucarne {
    /// Les écrans branchés, le principal (celui de la barre des menus, origine du repère global) en premier.
    var ecrans: () -> [EcranIlot] = { MainActor.assumeIsolated { NSScreen.screens.map(EcranIlot.init) } }
    /// Les préférences du Dock (lues une fois, puis seulement quand `suivreDock` dit qu'elles ont changé).
    var lireDock: () -> PrefsDock = { PrefsDock.lire() }
    /// Prévient quand une préférence du Dock change (côté, masquage, taille des icônes) ; l'objet rendu garde l'observation en vie.
    /// Aucune minuterie : macOS prévient lui-même (observation du domaine `com.apple.dock`, sondée le 12/11 entre deux processus).
    var suivreDock: (@escaping () -> Void) -> AnyObject? = { SuiviDock(surChangement: $0) }
    var lireMemoire: () -> MemoirePlaces = { Settings.lucarnePlaces }
    var ecrireMemoire: (MemoirePlaces) -> Void = { Settings.lucarnePlaces = $0 }
    /// Une petite vibration au décollage.
    var vibrer: () -> Void = { MainActor.assumeIsolated { Retours.vibrer(.legere) } }
}

/// Les préférences du Dock (`com.apple.dock`), lues seulement : son côté, s'il se masque, la taille de ses icônes.
struct PrefsDock: Equatable {
    var cote: CoteDock = .bas
    var masque = false
    var tailleIcone = 48.0

    static let domaine = "com.apple.dock"
    static let cles = ["orientation", "autohide", "tilesize"]

    /// Lues par le même accès que celui qu'on observe (`SuiviDock`) : jamais un cache en retard sur la notification.
    static func lire() -> PrefsDock {
        let r = UserDefaults(suiteName: domaine)
        return PrefsDock(cote: CoteDock.depuis(orientation: r?.string(forKey: "orientation")), masque: r?.bool(forKey: "autohide") ?? false,
                         tailleIcone: (r?.object(forKey: "tilesize") as? NSNumber)?.doubleValue ?? 48)
    }
}

/// L'observation des préférences du Dock : macOS prévient quand le Dock les réécrit (Réglages Système, `defaults`), même depuis un
/// autre processus. Rien n'est écrit ; le rappel arrive sur le fil principal.
final class SuiviDock: NSObject {
    private let reglages = UserDefaults(suiteName: PrefsDock.domaine)
    private let surChangement: () -> Void

    init(surChangement: @escaping () -> Void) {
        self.surChangement = surChangement
        super.init()
        for c in PrefsDock.cles { reglages?.addObserver(self, forKeyPath: c, options: [], context: nil) }
    }
    deinit { for c in PrefsDock.cles { reglages?.removeObserver(self, forKeyPath: c) } }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        let rappel = surChangement
        DispatchQueue.main.async { rappel() }
    }
}

extension EcranLucarne {
    /// Depuis l'écran de l'îlot : son cadre, ce que la zone visible lui retire (la barre des menus, le Dock visible), l'encoche mesurée
    /// (sa hauteur de barre, la caméra si elle est réelle) et le Dock. La largeur du Dock n'a pas d'API publique : inconnue (les coins du
    /// bas passent alors au-dessus de sa ligne). Plein écran (décision D) : la barre et le Dock masqués ne déplacent rien, la barre vient
    /// de l'encoche (au moins 24 pt) et le Dock compte toujours son épaisseur (`reserveBas`…).
    /// `autres` : les cadres des écrans branchés (ceux qui touchent celui-ci sont ses voisins).
    init(_ e: EcranIlot, dock: PrefsDock, autres: [CGRect] = []) {
        let v = e.zoneVisible, f = e.frame, g = e.geometrie
        self.init(cadre: f, barre: Double(g.hauteur), demiCamera: g.reelle ? Double(g.largeur / 2) : nil, centreX: Double(e.centre - f.minX),
                  retraitGauche: Double(v.minX - f.minX), retraitDroit: Double(f.maxX - v.maxX), retraitBas: Double(v.minY - f.minY),
                  dockCote: dock.cote, dockMasque: dock.masque, dockEpaisseur: EcranLucarne.epaisseurDock(tailleIcone: dock.tailleIcone))
        voisins = BordsEcran.voisins(de: f, parmi: autres)
    }
}

extension Settings {
    /// La place de la Lucarne pour chaque écran (JSON de `MemoirePlaces`). Aucun réglage dans l'interface : on la déplace d'un geste.
    static var lucarnePlaces: MemoirePlaces {
        get { UserDefaults.standard.data(forKey: "lucarnePlaces").flatMap(MemoirePlaces.depuis) ?? MemoirePlaces() }
        set { UserDefaults.standard.set(newValue.donnees(), forKey: "lucarnePlaces") }
    }
}

extension IlotPanneau {
    /// L'écran où la Lucarne doit vivre : celui où on l'a posée s'il est branché, sinon le principal (un écran débranché la renvoie sur
    /// le principal ; rebranché, elle y revient).
    /// Tenue ou en vol sur un autre écran (pas encore lâchée : la mémoire ne le sait pas), elle reste sur celui-là.
    func ecranVoulu() -> EcranIlot? {
        let s = moteur.lucarne.systeme, liste = s.ecrans()
        if moteur.lucarneEnMain, let ici = liste.first(where: { $0.id == moteur.lucarne.uuid }) { return ici }
        let choisi = s.lireMemoire().ecranChoisi(parmi: liste.map(\.id))
        return liste.first { $0.id == choisi } ?? liste.first
    }

    /// Le Dock, lu une seule fois ; ensuite seulement quand il change (`dockChange`).
    func dockLu() -> PrefsDock {
        if let d = prefsDock { return d }
        let d = moteur.lucarne.systeme.lireDock()
        prefsDock = d
        return d
    }

    /// Une préférence du Dock a changé (côté, masquage, taille) : relue ; si elle diffère, la Lucarne est reposée à sa place, recalculée.
    func dockChange() {
        let d = moteur.lucarne.systeme.lireDock()
        guard d != prefsDock else { return }
        prefsDock = d
        recaler()
    }

    /// L'écran tel que la Lucarne le voit : le Dock lu, et ses voisins parmi les écrans branchés.
    func decrire(_ e: EcranIlot) -> EcranLucarne {
        EcranLucarne(e, dock: dockLu(), autres: moteur.lucarne.systeme.ecrans().map(\.frame))
    }

    /// L'écran de l'îlot vient d'être mesuré : la Lucarne y est reposée à la place retenue pour lui, sans animation.
    func mesurerLucarne(_ e: EcranIlot) {
        cadreVoulu = .zero   // posée sans animation : sa fenêtre est posée telle quelle, sans attendre
        moteur.poserLucarne(decrire(e), uuid: e.id, place: moteur.lucarne.systeme.lireMemoire().place(pour: e.id))
    }

    /// VoiceOver « Déplacer vers… » : ce qui est ouvert se range, la Lucarne est posée à cette place sans geste ni animation (une action
    /// d'accessibilité est un saut), retenue pour cet écran ; VoiceOver annonce où elle est.
    func deplacerLucarne(vers place: PlaceLucarne) {
        // une alerte ou un bandeau (que « fermer » ne range pas) ne se déplace pas, comme pour le geste
        guard let e = ecran, let el = moteur.lucarne.ecran, place != moteur.lucarne.place, !moteur.lucarneOccupee, !moteur.lucarne.vol,
              !moteur.resolution.verrou else { return }
        if moteur.fenetreOuverte { moteur.fermer() }
        var memoire = moteur.lucarne.systeme.lireMemoire()
        memoire.poser(place, sur: e.id)
        moteur.lucarne.systeme.ecrireMemoire(memoire)
        cadreVoulu = .zero
        moteur.poserLucarne(el, uuid: e.id, place: place)
        moteur.donneesChangees()
        ajuster()
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: "Lucarne déplacée vers " + place.nom(avecEncoche: el.avecEncoche), .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    /// Un événement du bouton gauche sur la vue de l'îlot : son point GLOBAL (`cgEvent.location`, origine en haut à gauche de l'écran
    /// principal) dans le repère de la Lucarne, et l'heure de l'événement. Tenue, le pointeur passé sur un autre écran l'emmène avec lui.
    func bouton(_ e: NSEvent) {
        guard let g = e.cgEvent?.location, var ecran else { return }
        // la conversion qu'AppKit a faite pour donner ce point : celle du vrai écran principal
        let global = CGPoint(x: g.x, y: (NSScreen.screens.first?.frame.maxY ?? ecran.frame.maxY) - g.y)
        // `NSMouseInRect` (repère d'AppKit, y vers le haut) : la rangée tout en haut d'un écran est à lui, pas à l'écran posé dessus
        if e.type == .leftMouseDragged, moteur.lucarneEnMain, !moteur.lucarne.vol, !NSMouseInRect(global, ecran.frame, false),
           let autre = moteur.lucarne.systeme.ecrans().first(where: { $0.id != ecran.id && NSMouseInRect(global, $0.frame, false) }) {
            passerSur(autre)
            ecran = autre
        }
        let p = PointLucarne(Double(global.x - centre), Double(ecran.frame.maxY - global.y))
        switch e.type {
        case .leftMouseDown: moteur.sourisBas(p, t: e.timestamp)
        case .leftMouseDragged: moteur.sourisGlisse(p, t: e.timestamp)
        case .leftMouseUp: moteur.sourisHaut(p, t: e.timestamp)
        default: break
        }
    }

    /// Le cadre `r` doit-il être posé tout de suite (même plus petit) ? Oui si la Lucarne change de régime (encoche ↔ libre : la vue n'est
    /// plus au même endroit dans la fenêtre), pendant la tenue et le vol (la fenêtre est centrée sur la capsule), et à l'arrivée (la forme
    /// est posée : la grande fenêtre du vol n'a rien à attendre pour se resserrer).
    func poserToutDeSuite(_ r: CGRect) -> Bool {
        if cadreLibre != moteur.lucarne.libre || cadreEnMain != moteur.lucarneEnMain { return true }
        return cadreLibre && moteur.lucarneEnMain && r != cadreVoulu
    }

    /// Hors de l'encoche, posée (ni tenue ni vol, déjà en régime libre) : le cadre à poser tout de suite, ou nil (la règle de l'encoche
    /// s'applique). Un cadre qui sort de l'actuel (la forme monte au-dessus de la ligne du Dock, une carte plus haute) est posé tout de
    /// suite, réuni à l'actuel : la forme qui se replie y tient encore ; il se resserre 0,65 s plus tard.
    func cadreLibrePose(_ r: CGRect, visible: Bool) -> CGRect? {
        guard visible, cadreLibre, !cadreEnMain, !cadreVoulu.isEmpty, moteur.lucarne.libre, !moteur.lucarneEnMain, !cadreVoulu.contains(r) else { return nil }
        return cadreVoulu.union(r)
    }

    /// Des fichiers glissés près de la Lucarne hors de l'encoche : à 140 pt de sa pilule (60 pt si on a déjà quitté ses zones pendant ce
    /// glisser), comme près de l'encoche.
    func procheLucarne(_ p: CGPoint, retour: Bool) -> Bool {
        guard let e = moteur.lucarne.ecran else { return false }
        let c = moteur.capsuleRepliee(e)
        let dx = max(0, max(c.x0 - Double(p.x), Double(p.x) - c.x1)), dy = max(0, max(c.y0 - Double(p.y), Double(p.y) - c.y1))
        return hypot(dx, dy) <= (retour ? ApprocheEtagere.distanceRetour : ApprocheEtagere.distance)
    }

    /// Tenue ou vol : la fenêtre suit la capsule par son ORIGINE seulement (même taille, la vue ne bouge pas dedans : rien à redessiner).
    func deplacerLibre() {
        guard let f = fenetre, let ecran, moteur.lucarneEnMain else { return }
        let r = moteur.fenetreVoulue()
        // pas encore le cadre du régime libre (le décollage le pose), ou une autre taille : c'est à `ajuster` de le poser en entier
        guard cadreLibre, r.size == cadreVoulu.size else { ajuster(); return }
        cadreVoulu = r
        f.setFrameOrigin(NSPoint(x: centre + r.minX, y: ecran.frame.maxY - r.maxY))
    }
}
