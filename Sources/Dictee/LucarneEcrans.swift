import AppKit
import DicteeCore

// La Lucarne et le système : l'écran (NSScreen → EcranLucarne), le Dock (ses préférences, lues sans rien écrire), la mémoire des places
// (une par écran), la vibration ; et la fenêtre de l'îlot en régime libre (docs/plan-lucarne-deplacable.md, mission 2).

/// Tout ce que la Lucarne lit ou écrit hors d'elle : injectable, l'essai ne touche jamais aux vrais réglages ni au vrai Dock.
struct SystemeLucarne {
    /// L'écran tel que la Lucarne le voit (`centre` : le centre de l'encoche, coordonnées globales d'AppKit).
    var decrire: (NSScreen, GeometrieEncoche, CGFloat) -> EcranLucarne = { e, g, c in
        MainActor.assumeIsolated { EcranLucarne(ecran: e, geometrie: g, centre: c, dock: .lire()) }
    }
    /// La clé de l'écran dans la mémoire (son UUID, stable d'un branchement à l'autre).
    var identifiant: (NSScreen) -> String = { e in MainActor.assumeIsolated { EcranLucarne.uuid(de: e) } }
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

    static func lire() -> PrefsDock {
        let domaine = "com.apple.dock" as CFString
        func valeur(_ cle: String) -> Any? { CFPreferencesCopyAppValue(cle as CFString, domaine) }
        return PrefsDock(cote: CoteDock.depuis(orientation: valeur("orientation") as? String), masque: valeur("autohide") as? Bool ?? false,
                         tailleIcone: (valeur("tilesize") as? NSNumber)?.doubleValue ?? 48)
    }
}

extension EcranLucarne {
    /// Depuis l'écran d'AppKit : son cadre, ce que `visibleFrame` lui retire (la barre des menus, le Dock visible), l'encoche mesurée (sa
    /// hauteur de barre, la caméra si elle est réelle) et le Dock. La largeur du Dock n'a pas d'API publique : inconnue (les coins du bas
    /// passent alors au-dessus de sa ligne).
    @MainActor
    init(ecran e: NSScreen, geometrie g: GeometrieEncoche, centre: CGFloat, dock: PrefsDock) {
        let v = e.visibleFrame, f = e.frame
        self.init(cadre: f, barre: Double(g.hauteur), demiCamera: g.reelle ? Double(g.largeur / 2) : nil, centreX: Double(centre - f.minX),
                  retraitGauche: Double(v.minX - f.minX), retraitDroit: Double(f.maxX - v.maxX), retraitBas: Double(v.minY - f.minY),
                  dockCote: dock.cote, dockMasque: dock.masque, dockEpaisseur: EcranLucarne.epaisseurDock(tailleIcone: dock.tailleIcone))
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

extension Settings {
    /// La place de la Lucarne pour chaque écran (JSON de `MemoirePlaces`). Aucun réglage dans l'interface : on la déplace d'un geste.
    static var lucarnePlaces: MemoirePlaces {
        get { UserDefaults.standard.data(forKey: "lucarnePlaces").flatMap(MemoirePlaces.depuis) ?? MemoirePlaces() }
        set { UserDefaults.standard.set(newValue.donnees(), forKey: "lucarnePlaces") }
    }
}

extension IlotPanneau {
    /// L'écran de l'îlot vient d'être mesuré : la Lucarne y est reposée à la place retenue pour lui, sans animation ; la boucle bat au
    /// rythme de cet écran.
    func mesurerLucarne(_ e: NSScreen) {
        let s = moteur.lucarne.systeme
        let id = s.identifiant(e)
        moteur.cadence.ecran = e
        moteur.poserLucarne(s.decrire(e, moteur.geometrie, centre), uuid: id, place: s.lireMemoire().place(pour: id))
    }

    /// Un événement du bouton gauche sur la vue de l'îlot : son point GLOBAL (`cgEvent.location`, origine en haut à gauche de l'écran
    /// principal) dans le repère de la Lucarne, et l'heure de l'événement.
    func bouton(_ e: NSEvent) {
        guard let g = e.cgEvent?.location, let ecran else { return }
        let principal = NSScreen.screens.first?.frame.maxY ?? ecran.frame.maxY
        let p = PointLucarne(Double(g.x - centre), Double(ecran.frame.maxY - (principal - g.y)))
        switch e.type {
        case .leftMouseDown: moteur.sourisBas(p, t: e.timestamp)
        case .leftMouseDragged: moteur.sourisGlisse(p, t: e.timestamp)
        case .leftMouseUp: moteur.sourisHaut(p, t: e.timestamp)
        default: break
        }
    }

    /// Le cadre `r` doit-il être posé tout de suite (même plus petit) ? Oui si la Lucarne change de régime (encoche ↔ libre : la vue n'est
    /// plus au même endroit dans la fenêtre) ; libre, si son centre a bougé (la fenêtre reste centrée sur elle) ou si elle est posée (rien
    /// ne se referme, la fenêtre n'a pas à attendre pour se resserrer).
    func poserToutDeSuite(_ r: CGRect) -> Bool {
        if cadreLibre != moteur.lucarne.libre { return true }
        return cadreLibre && r != cadreVoulu && (moteur.lucarnePosee || abs(r.midX - cadreVoulu.midX) > 0.01 || abs(r.midY - cadreVoulu.midY) > 0.01)
    }

    /// Tenue ou vol : la fenêtre suit la capsule par son ORIGINE seulement (même taille, la vue ne bouge pas dedans : rien à redessiner).
    func deplacerLibre() {
        guard let f = fenetre, let ecran, moteur.lucarne.libre else { return }
        let r = moteur.fenetreVoulue()
        // pas encore le cadre du régime libre (le décollage le pose), ou une autre taille : c'est à `ajuster` de le poser en entier
        guard cadreLibre, r.size == cadreVoulu.size else { ajuster(); return }
        cadreVoulu = r
        f.setFrameOrigin(NSPoint(x: centre + r.minX, y: ecran.frame.maxY - r.maxY))
    }
}
