import Foundation

// Le Centre de l'îlot (maquette design/maquettes/ilot-centre.html) : logique pure, sans interface.
// L'îlot ouvert est une pile de cartes : l'activité dépliée (la vidéo, le minuteur…), le Centre, sa 2e page « Outils », puis l'accueil
// (rendez-vous, rappel, dernière dictée). On passe de l'une à l'autre en un clic (bouton « Centre », « Outils », points de page) ou en
// faisant défiler (un geste = une carte).

public enum CartesIlot {
    /// Les cartes de l'îlot ouvert, de haut en bas. `survol` : l'écran que l'îlot prend au survol (nil : verrouillé, pas de cartes).
    /// Rien ne joue : le Centre d'abord. Une activité : son déplié d'abord (la rangée Minuteur de la lecture compte comme la lecture).
    /// Les Outils sont la page juste sous le Centre (maquette ilot-claude-plus.html, étape 8 : « 2e point à droite »).
    public static func pile(survol: VueIlot?) -> [VueIlot] {
        guard let s = survol else { return [] }
        if s == .centre || s == .accueil || s == .outils { return [.centre, .outils, .accueil] }
        return [s == .lectureMinuteur ? .lectureEtendu : s, .centre, .outils, .accueil]
    }

    /// Les cartes des outils (presse-papiers, Reformuler, Note rapide) sont rangées sous la page Outils : ses points de page restent, celui
    /// des Outils allumé, et un défilement y ramène.
    public static func parent(_ v: VueIlot) -> VueIlot? {
        [.outilPressePapiers, .outilReformuler, .outilNote].contains(v) ? .outils : nil
    }

    /// Ce que l'îlot prend au survol, une fois le Centre là. Le micro coupé n'a plus de déplié à lui (son bouton, rouge, « Coupé », est
    /// dans le Centre, et un clic le rouvre) : on ouvre la 2e activité (la vidéo passée en bulle), sinon directement le Centre.
    /// `deuxieme` : le déplié de l'activité de la bulle, s'il y en a une.
    public static func survol(_ s: VueIlot, deuxieme: VueIlot?) -> VueIlot {
        guard s == .microEtendu else { return s }
        if let d = deuxieme, d != .repos, d != .microEtendu { return d }
        return .centre
    }

    /// La carte porte-t-elle le bouton « Centre » à son pied ? Le déplié de TOUTE activité (la vidéo, le minuteur, Claude, un rendez-vous,
    /// un rappel), c'est-à-dire la première carte d'une pile qui contient le Centre : le chemin vers le Centre se voit toujours (on n'a
    /// jamais à deviner un défilement). Le Centre et l'accueil n'en ont pas ; la rangée Minuteur de la lecture prend sa place.
    /// La carte « Claude Code » n'en a pas : son en-tête a déjà « ‹ Centre ».
    public static func aUnPied(_ v: VueIlot, pile: [VueIlot]) -> Bool {
        v != .centre && v != .accueil && v != .claudeCarte && v != .outils && parent(v) == nil && pile.first == v && pile.contains(.centre)
    }

    /// Ce que le pied ajoute à la hauteur d'une carte : la lecture l'a déjà dans sa géométrie, les autres dépliés l'ajoutent dessous.
    public static func piedEnPlus(_ v: VueIlot, pile: [VueIlot]) -> Double {
        aUnPied(v, pile: pile) && v != .lectureEtendu ? GeoIlot.piedLecture : 0
    }

    /// La carte voisine, `pas` cartes plus bas (+1) ou plus haut (−1) ; nil au bout de la pile (on ne boucle pas).
    public static func voisine(_ pile: [VueIlot], de carte: VueIlot, pas: Int) -> VueIlot? {
        guard let i = pile.firstIndex(of: carte == .lectureMinuteur ? .lectureEtendu : carte) else { return nil }
        let j = i + pas
        return pile.indices.contains(j) && j != i ? pile[j] : nil
    }
}

/// Le défilement (molette, deux doigts sur le trackpad) transformé en cartes : UN geste = UNE carte.
/// - trackpad : les mouvements d'un geste (début → fin) s'additionnent ; la carte change une seule fois, quand ils dépassent `seuil` ;
///   l'inertie (les événements qui suivent le lever des doigts) est ignorée ;
/// - molette : chaque cran change de carte, pas plus d'une fois toutes les `pauseMolette` secondes (une roue lancée ne fait pas défiler
///   toute la pile) ;
/// - un défilement surtout horizontal ne compte pas.
/// Le sens est celui d'une page : vers le bas (doigts qui montent en défilement naturel, `dy` négatif chez AppKit) = la carte d'en dessous.
public struct DefilementIlot: Equatable, Sendable {
    public enum Phase: Sendable { case debut, suite, fin, aucune }
    public static let seuil: Double = 14
    public static let pauseMolette: Double = 0.35

    private var cumul = 0.0
    private var fait = false
    private var derniereMolette = -1e9

    public init() {}

    /// Un événement de défilement ; rend +1 (carte suivante), −1 (précédente) ou nil (rien encore). `t` : en secondes, croissant.
    public mutating func recevoir(dy: Double, dx: Double = 0, phase: Phase, inertie: Bool, t: Double) -> Int? {
        if inertie { return nil }
        switch phase {
        case .debut:
            cumul = 0; fait = false
            return compter(dy: dy, dx: dx)
        case .suite:
            return compter(dy: dy, dx: dx)
        case .fin:
            cumul = 0; fait = false
            return nil
        case .aucune:
            // une molette (ou un événement sans phase) : un cran = une carte, avec une pause
            guard abs(dy) >= 0.5, abs(dy) >= abs(dx), t - derniereMolette >= Self.pauseMolette else { return nil }
            derniereMolette = t
            return dy < 0 ? 1 : -1
        }
    }

    private mutating func compter(dy: Double, dx: Double) -> Int? {
        guard !fait, abs(dy) >= abs(dx) else { return nil }
        cumul += dy
        guard abs(cumul) >= Self.seuil else { return nil }
        fait = true
        return cumul < 0 ? 1 : -1
    }
}

extension GeoIlot {
    /// La bulle « Nouveau : survole l'îlot » (une seule fois, au premier lancement) : l'îlot replié (ou vide) descend de 40 pt sous la barre,
    /// le corps épouse le texte (maquette : bandeau de 300 pt sur 40). Le cou ne bouge pas : la pochette et l'onde restent dans les ailes.
    public static let profondeurBulle: Double = 40

    /// Les sept valeurs de `g` (un écran replié) avec la bulle dessous. `contenu` : la largeur mesurée du texte.
    public static func avecBulle(_ g: [Double], hauteurBarre: Double, demiCamera: Double, contenu: Double) -> [Double] {
        var r = g
        r[1] = max(g[0] + evasementMin, (contenu / 2 + marge - demiCamera).rounded(.up))
        r[2] = hauteurBarre + profondeurBulle
        r[3] = 6; r[4] = 22; r[5] = 14; r[6] = 10
        return r
    }
}
