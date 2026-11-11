import Foundation

// « Volume et luminosité » (maquette design/maquettes/ilot-apple.html, « Cinq idées de plus », 4) : logique pure, sans système.
// Les touches du clavier (volume +, volume −, muet, luminosité + et −) arrivent comme des événements « systemDefined » (sous-type 8) ;
// Verbe les avale et règle lui-même le volume ou la luminosité, puis l'îlot montre le haut-parleur (ou le soleil) et une barre fine.
// Ici : le décodage des touches, les pas (1/16 comme macOS, 1/64 avec ⌥⇧), les bornes, la décision d'avaler ou de laisser passer
// (et la répétition d'une touche tenue), le symbole.

/// Une touche de volume ou de luminosité (codes NX_KEYTYPE_* de IOKit/hidsystem/ev_keymap.h).
public enum ToucheNiveau: Int, Sendable, CaseIterable {
    case volumePlus = 0, volumeMoins = 1, luminositePlus = 2, luminositeMoins = 3, muet = 7

    public var genre: GenreNiveau { self == .luminositePlus || self == .luminositeMoins ? .luminosite : .volume }
    /// Monte (+1), descend (−1), ou bascule (muet : 0).
    public var sens: Int {
        switch self {
        case .volumePlus, .luminositePlus: return 1
        case .volumeMoins, .luminositeMoins: return -1
        case .muet: return 0
        }
    }
}

public enum GenreNiveau: String, Sendable, CaseIterable { case volume, luminosite }

/// Un appui (ou relâchement) d'une touche de volume ou de luminosité.
public struct EvenementNiveau: Equatable, Sendable {
    public var touche: ToucheNiveau
    public var enfoncee: Bool
    /// Répétition automatique d'une touche tenue.
    public var repetition: Bool
    public init(touche: ToucheNiveau, enfoncee: Bool, repetition: Bool = false) {
        self.touche = touche; self.enfoncee = enfoncee; self.repetition = repetition
    }

    /// Le sous-type des touches spéciales (NX_SUBTYPE_AUX_CONTROL_BUTTONS).
    public static let sousTypeTouches = 8

    /// Décode `data1` d'un événement « systemDefined » : code de la touche dans les 16 bits du haut, puis l'état (0xA enfoncée, 0xB
    /// relâchée) et le bit de répétition. Nil : autre sous-type (boutons de souris…), autre touche (lecture, clavier rétroéclairé…).
    public static func decoder(sousType: Int, data1: Int) -> EvenementNiveau? {
        guard sousType == sousTypeTouches else { return nil }
        let code = (data1 & 0xFFFF_0000) >> 16, drapeaux = data1 & 0xFFFF, etat = (drapeaux & 0xFF00) >> 8
        guard let t = ToucheNiveau(rawValue: code), etat == 0xA || etat == 0xB else { return nil }
        return EvenementNiveau(touche: t, enfoncee: etat == 0xA, repetition: drapeaux & 0x1 != 0)
    }
    /// L'inverse (pour les essais, qui fabriquent des événements sans jamais les envoyer).
    public var data1: Int { (touche.rawValue << 16) | ((enfoncee ? 0xA : 0xB) << 8) | (repetition ? 1 : 0) }
}

/// Ce que l'îlot montre : le genre, la valeur (0…1) et le muet (volume seulement).
public struct NiveauIlot: Equatable, Sendable {
    public var genre: GenreNiveau
    public var valeur: Double
    public var muet: Bool
    public init(genre: GenreNiveau, valeur: Double, muet: Bool = false) {
        self.genre = genre; self.valeur = min(1, max(0, valeur)); self.muet = muet && genre == .volume
    }
    /// La barre : vide quand le son est coupé (comme sur l'iPhone).
    public var affiche: Double { muet ? 0 : valeur }
    /// Le symbole SF de l'aile gauche : le haut-parleur barré (muet ou zéro), une, deux ou trois ondes ; le soleil pour la luminosité.
    public var symbole: String {
        guard genre == .volume else { return "sun.max.fill" }
        if muet || valeur < 0.001 { return "speaker.slash.fill" }
        if valeur < 1.0 / 3 { return "speaker.wave.1.fill" }
        if valeur < 2.0 / 3 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
    /// « 50 % » pour VoiceOver.
    public var pourcent: Int { Int((affiche * 100).rounded()) }
}

/// Les pas : 16 crans de 0 à 1 comme macOS, 64 avec ⌥⇧ (les quarts de cran).
public enum PasNiveau {
    public static let normal = 1.0 / 16
    public static let fin = 1.0 / 64

    /// Le cran suivant, calé sur la grille des crans (un volume réglé ailleurs à 0,30 monte à 5/16 puis 6/16, pas à 0,3625), borné à 0…1.
    public static func suivant(_ v: Double, sens: Int, fin estFin: Bool) -> Double {
        let p = estFin ? fin : normal
        let n = v / p
        let k: Double
        if sens > 0 { k = (n + 1e-6).rounded(.down) + 1 } else if sens < 0 { k = (n - 1e-6).rounded(.up) - 1 } else { return min(1, max(0, v)) }
        return min(1, max(0, k * p))
    }

    /// La valeur relue au système, recalée sur celle que Verbe vient d'écrire : un appareil arrondit son volume à ses propres crans
    /// (0,5625 relu 0,5617) ; sans ce recalage, « + » repartirait du cran d'en dessous et resterait sur place.
    public static func recaler(lu: Double, ecrit: Double?) -> Double {
        guard let e = ecrit, abs(lu - e) < 0.01 else { return lu }
        return e
    }

    /// Les touches de modification : aucune = un cran ; ⌥⇧ = un quart de cran ; toute autre combinaison (⌥ seul ouvre les réglages Son ou
    /// Moniteurs de macOS, ⌘, ⌃…) : nil, on laisse macOS faire.
    public static func mode(option: Bool, maj: Bool, controle: Bool, commande: Bool) -> Bool? {
        if controle || commande { return nil }
        if !option && !maj { return false }
        if option && maj { return true }
        return nil
    }

    /// Le niveau après une touche : volume + et − rendent le son coupé (comme macOS), le muet bascule, la luminosité va de 0 à 1.
    public static func apres(_ n: NiveauIlot, touche: ToucheNiveau, fin estFin: Bool) -> NiveauIlot {
        var r = n
        switch touche {
        case .muet: r.muet = !n.muet
        default:
            r.valeur = suivant(n.valeur, sens: touche.sens, fin: estFin)
            r.muet = false
        }
        return r
    }
}

/// Avaler ou laisser passer chaque touche, et garder la cohérence entre l'appui, ses répétitions et le relâchement : une touche
/// avalée à l'appui l'est jusqu'au relâchement (macOS ne doit jamais recevoir un relâchement sans appui, ni l'inverse) ; une touche
/// laissée à macOS l'est jusqu'au bout, même si les conditions changent pendant qu'on la tient.
public struct AiguillageNiveau: Sendable {
    /// Ce qui permet de prendre la touche : le réglage, l'îlot (ni dictée, ni réunion, ni alerte), et un volume (ou un muet, ou une
    /// luminosité) que Verbe sait régler. Sinon macOS fait comme d'habitude, avec son propre affichage.
    public struct Conditions: Sendable {
        public var reglage: Bool
        public var ilot: Bool
        public var reglable: Bool
        public init(reglage: Bool, ilot: Bool, reglable: Bool) { self.reglage = reglage; self.ilot = ilot; self.reglable = reglable }
        public var toutes: Bool { reglage && ilot && reglable }
    }

    public enum Decision: Equatable, Sendable {
        case laisser
        /// Avaler sans rien faire (le relâchement, la répétition du muet).
        case avaler
        /// Avaler et appliquer cette touche (`fin` : un quart de cran).
        case appliquer(ToucheNiveau, fin: Bool)
    }

    private var avalees: Set<Int> = []
    public init() {}

    /// `fin` : nil si les touches de modification demandent de laisser macOS faire (voir `PasNiveau.mode`).
    public mutating func recevoir(_ e: EvenementNiveau, fin: Bool?, conditions c: Conditions) -> Decision {
        let k = e.touche.rawValue
        guard e.enfoncee else { return avalees.remove(k) != nil ? .avaler : .laisser }
        if e.repetition {
            guard avalees.contains(k) else { return .laisser }
            // tenue : chaque répétition est un cran de plus, sauf le muet (il ne bascule qu'une fois) ; si l'îlot n'est plus libre
            // (une dictée commence), on avale sans rien faire jusqu'au relâchement
            guard e.touche != .muet, c.toutes, let f = fin else { return .avaler }
            return .appliquer(e.touche, fin: f)
        }
        guard c.toutes, let f = fin else { avalees.remove(k); return .laisser }
        avalees.insert(k)
        return .appliquer(e.touche, fin: f)
    }
    /// Une touche est tenue et avalée (pour les essais).
    public func avalee(_ t: ToucheNiveau) -> Bool { avalees.contains(t.rawValue) }
}

/// La barre suit la valeur sur un ressort (vif, presque sans rebond) : une touche tenue la fait glisser d'un seul mouvement, sans
/// marches. « Réduire les animations » : elle saute à sa place.
public enum JaugeNiveau {
    public static let reponse = 0.24
    public static let amortissement = 0.9
    public static func viser(_ r: inout RessortIlot, vers v: Double, reduire: Bool) {
        r.viser(min(1, max(0, v)), reponse: reponse, amortissement: amortissement)
        if reduire { r.poser() }
    }
    /// La barre de l'aile droite : 8 pt après la caméra, 8 pt avant le bord du cou (comme l'heure des autres compacts).
    public static func barre(demiCamera hc: Double, cou: Double) -> (x: Double, largeur: Double) {
        (hc + 8, max(0, cou - 16))
    }
}
