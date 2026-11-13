import Foundation

// Revenir en arrière dans l'îlot (13/11, Hugues : « quand j'ouvre un détail, je ne peux pas revenir en arrière ») : logique pure, sans
// interface.
// - chaque écran ouvert depuis un autre a un « ‹ » ; « ‹ X » va toujours à X (ce qui est écrit) ;
// - deux doigts vers la droite sur le trackpad = ce « ‹ » ; vers la gauche : rien (il n'y a pas d'« avant » à rejouer, un geste qui
//   rouvrirait un écran au hasard surprendrait) ;
// - une petite pile retient d'où l'on vient (et si l'îlot y était épinglé) : un détail revient là d'où il a été ouvert (le détail de
//   Groq → la page Outils), pas sur l'îlot replié. Elle se vide quand l'îlot se range ;
// - jamais bloqué : un bandeau échu reste sous le pointeur tant que la souris bouge, et part après quelques secondes sans geste.

/// Un écran quitté pour un autre : où l'on était, et si l'îlot y était épinglé (« Reste ouvert »).
public struct PasRetour: Equatable, Sendable {
    public var vue: VueIlot
    public var epingle: Bool
    public init(_ vue: VueIlot, epingle: Bool) { self.vue = vue; self.epingle = epingle }
}

/// La pile de retour : les écrans d'avant, du plus ancien au plus récent (l'écran montré n'y est pas).
public struct PileRetour: Equatable, Sendable {
    /// Au-delà, le plus ancien s'oublie (on ne remonte jamais si loin d'un geste).
    public static let profondeur = 8
    public private(set) var pas: [PasRetour] = []
    public init() {}

    public var vues: [VueIlot] { pas.map(\.vue) }
    public var dernier: PasRetour? { pas.last }
    public var estVide: Bool { pas.isEmpty }

    /// On passe de `depuis` (nil : l'îlot était rangé ou verrouillé par un bandeau) à `vers`. Si `vers` est déjà dans la pile, c'est un
    /// retour par un autre chemin (un point de page, un défilement vers le haut) : la pile redescend jusqu'à lui. Sinon `depuis` s'empile.
    public mutating func aller(depuis: VueIlot?, vers: VueIlot, epingle: Bool) {
        if let i = pas.lastIndex(where: { $0.vue == vers }) { pas.removeSubrange(i...); return }
        guard let depuis, depuis != vers else { return }
        pas.append(PasRetour(depuis, epingle: epingle))
        if pas.count > Self.profondeur { pas.removeFirst(pas.count - Self.profondeur) }
    }

    /// On revient à `cible` : la pile redescend jusqu'à elle (rend son pas, et donc si l'îlot y était épinglé) ; absente, rien ne change.
    @discardableResult
    public mutating func revenir(a cible: VueIlot) -> PasRetour? {
        guard let i = pas.lastIndex(where: { $0.vue == cible }) else { return nil }
        let p = pas[i]
        pas.removeSubrange(i...)
        return p
    }

    /// L'îlot se range (souris partie, clic ailleurs, dictée) : on repart de zéro à la prochaine ouverture.
    public mutating func vider() { pas = [] }
}

public enum NavigationIlot {
    /// Le parent fixe d'un écran, celui que nomme son « ‹ » déjà dessiné (« ‹ Centre », « ‹ Outils », « ‹ Étagère », « ‹ Vidéo ») : le
    /// bouton dit où il mène, le geste va au même endroit. `premiere` : la première carte de la pile (le déplié de l'activité), là où
    /// mène « ‹ Vidéo » depuis le Centre ; nil ou le Centre lui-même : le Centre est la racine.
    public static func parentFixe(_ v: VueIlot, premiere: VueIlot?) -> VueIlot? {
        switch v {
        case .bibliotheque: return .etagere
        case .etagere, .claudeCarte, .dictees, .outils: return .centre
        case .centre: return premiere == .centre ? nil : premiere
        default: return CartesIlot.parent(v)
        }
    }

    /// Quand rien ne dit d'où l'on vient (pile vide) : le détail de Groq vient de la page Outils (sa jauge), la liste des rappels du
    /// Centre (son bouton « Rappel »).
    public static func secours(_ v: VueIlot) -> VueIlot? {
        switch v {
        case .groq: return .outils
        case .rappelListe: return .centre
        default: return nil
        }
    }

    /// Où mène « ‹ » (et le geste) depuis `v` : le parent fixe s'il y en a un, sinon le dernier écran de la pile, sinon le secours. nil :
    /// rien avant (le Centre sans activité, la vidéo dépliée tout juste ouverte) : le geste ne fait rien.
    public static func retour(de v: VueIlot, pile: [VueIlot], premiere: VueIlot?) -> VueIlot? {
        if let p = parentFixe(v, premiere: premiere) { return p }
        if let h = pile.last(where: { $0 != v }) { return h }
        return secours(v)
    }

    /// Le mot du « ‹ » pour une destination (nil : celle-ci n'a pas de nom court ; l'îlot prend celui de la première carte).
    public static func nom(_ v: VueIlot) -> String? {
        switch v {
        case .centre: return "Centre"
        case .outils: return "Outils"
        case .accueil: return "Accueil"
        case .dictees: return "Dictées"
        case .etagere: return "Étagère"
        case .bibliotheque: return "Bibliothèque"
        case .claudeCarte: return "Claude"
        case .outilPressePapiers: return "Presse-papiers"
        case .outilReformuler: return "Reformuler"
        case .outilNote: return "Notes"
        case .rappelListe: return "Rappels"
        default: return nil
        }
    }
}

/// Deux doigts vers la droite sur le trackpad = « ‹ ». Un geste net : les mouvements d'un geste (début → fin) s'additionnent ; il compte
/// une seule fois, quand les doigts ont parcouru `seuil` pt vers la droite ET au moins `dominance` fois plus en largeur qu'en hauteur
/// (un défilement vertical un peu de travers ne revient jamais en arrière). L'inertie est ignorée ; la molette aussi (une souris n'a pas
/// ce geste). Un geste qui a servi au retour ne fait plus rien d'autre jusqu'à sa fin (`avale`).
/// `doigtsX` : positif quand les doigts vont vers la droite (le panneau corrige le sens du défilement naturel).
public struct BalayageRetour: Equatable, Sendable {
    public static let seuil: Double = 36
    public static let dominance: Double = 2

    private var x = 0.0, y = 0.0
    /// Le geste en cours (et sa fin, et son inertie) a servi au retour : il ne fait plus défiler ni changer de carte. Revient à faux au
    /// début du geste suivant.
    public private(set) var avale = false

    public init() {}

    /// Rend vrai une seule fois par geste, au moment où il devient un retour.
    public mutating func recevoir(doigtsX dx: Double, dy: Double, phase: DefilementIlot.Phase, inertie: Bool) -> Bool {
        if inertie || phase == .aucune { return false }
        if phase == .debut { x = 0; y = 0; avale = false }
        if phase == .fin { return false }
        guard !avale else { return false }
        x += dx; y += dy
        guard x >= Self.seuil, x >= Self.dominance * abs(y) else { return false }
        avale = true
        return true
    }
}

/// Un bandeau (ou un détail) arrivé à son échéance, sous le pointeur : il reste tant qu'on s'en sert, jamais plus.
public enum FermetureBandeau {
    /// Sans un geste (mouvement de la souris, clic, défilement) depuis `calme` secondes, il part même sous le pointeur.
    public static let calme: TimeInterval = 3

    /// La prochaine date où revoir le bandeau, ou nil : il part maintenant. Avant l'échéance : l'échéance. Après : seulement sous le
    /// pointeur, jusqu'à `calme` s après le dernier geste.
    public static func prochainExamen(echeance: Date, maintenant t: Date, pointeurDessus: Bool, dernierGeste: Date) -> Date? {
        if t < echeance { return echeance }
        guard pointeurDessus else { return nil }
        let limite = dernierGeste.addingTimeInterval(calme)
        return limite > t ? limite : nil
    }
}
