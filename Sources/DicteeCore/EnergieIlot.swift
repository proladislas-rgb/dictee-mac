import Foundation

// La batterie du Mac et des appareils Bluetooth, et quand l'îlot l'annonce (logique pure : voir Dictee/IlotEnergie.swift pour les sources).

/// La batterie du Mac.
public struct EnergieIlot: Equatable {
    public var pourcent: Int
    /// Branché sur le secteur (en charge ou déjà plein).
    public var secteur: Bool
    public var enCharge: Bool
    public init(pourcent: Int, secteur: Bool, enCharge: Bool) { self.pourcent = pourcent; self.secteur = secteur; self.enCharge = enCharge }
    /// « 33 % » avec l'espace fine insécable des pourcentages.
    public var texte: String { "\(pourcent)\u{202F}%" }
    /// Le symbole SF de la pile : l'éclair si elle est branchée, sinon le cran le plus proche (0, 25, 50, 75, 100).
    public var symbole: String {
        if secteur { return "battery.100percent.bolt" }
        let c = [0, 25, 50, 75, 100].min(by: { abs($0 - pourcent) < abs($1 - pourcent) }) ?? 100
        return "battery.\(c)percent"
    }
}

/// Un appareil Bluetooth avec une batterie : écouteurs (deux côtés et un étui), souris, clavier.
public struct AppareilIlot: Equatable {
    public enum Genre: Equatable { case ecouteurs, souris, clavier, autre }
    public var nom: String
    public var genre: Genre
    public var gauche: Int?
    public var droit: Int?
    public var etui: Int?
    public var unique: Int?
    public init(nom: String, genre: Genre, gauche: Int? = nil, droit: Int? = nil, etui: Int? = nil, unique: Int? = nil) {
        self.nom = nom; self.genre = genre; self.gauche = gauche; self.droit = droit; self.etui = etui; self.unique = unique
    }
    /// Le niveau à montrer dans l'épaule : le plus bas des deux écouteurs (c'est lui qui s'éteindra le premier), sinon le seul connu.
    public var niveau: Int? { [gauche, droit].compactMap { $0 }.min() ?? unique }
    public var symbole: String {
        switch genre {
        case .ecouteurs: return nom.localizedCaseInsensitiveContains("pro") ? "airpodspro" : (nom.localizedCaseInsensitiveContains("airpods") ? "airpods" : "headphones")
        case .souris: return "magicmouse.fill"
        case .clavier: return "keyboard.fill"
        case .autre: return "dot.radiowaves.left.and.right"
        }
    }
    /// Le nom tel que l'îlot l'écrit : « AirPods Pro de Hugues » reste tel quel ; vide → le genre.
    public var titre: String {
        let n = nom.trimmingCharacters(in: .whitespaces)
        if !n.isEmpty { return n }
        switch genre { case .ecouteurs: return "Écouteurs"; case .souris: return "Souris"; case .clavier: return "Clavier"; case .autre: return "Appareil" }
    }
}

/// Quand annoncer : le chargeur qu'on branche (pas au lancement), la batterie qui passe sous 20 % puis sous 10 % (une fois par seuil,
/// remis à zéro dès qu'on rebranche). Logique pure, pour les essais.
public struct VeilleEnergie {
    public private(set) var derniere: EnergieIlot?
    private var seuilsDits = Set<Int>()
    public init() {}
    public static let seuils = [20, 10]
    public enum Annonce: Equatable { case charge, faible(Int) }

    public mutating func lire(_ e: EnergieIlot?) -> Annonce? {
        defer { derniere = e }
        guard let e else { return nil }
        if e.secteur { seuilsDits = []; if let d = derniere, !d.secteur { return .charge }; return nil }
        // au lancement, une batterie déjà basse compte comme dite (on ne prévient pas pour une batterie qu'on connaît)
        if derniere == nil { seuilsDits = Set(Self.seuils.filter { e.pourcent <= $0 }); return nil }
        if let s = Self.seuils.sorted().first(where: { e.pourcent <= $0 && !seuilsDits.contains($0) }) {
            seuilsDits.formUnion(Self.seuils.filter { e.pourcent <= $0 })
            return .faible(s)
        }
        return nil
    }
}

