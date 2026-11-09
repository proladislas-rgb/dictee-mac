import Foundation

/// Une dictée gardée dans l'historique. Le texte reste récupérable même quand l'insertion a échoué.
public struct EntreeHistorique: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var date: Date
    /// App qui devait recevoir le texte (identifiant de paquet) et son nom.
    public var appId: String?
    public var appNom: String?
    public var texte: String
    /// `false` quand le texte n'a pas pu être écrit dans l'app (champ protégé, accessibilité, destination absente).
    public var insere: Bool
    public var raison: String?

    public init(id: UUID = UUID(), date: Date = Date(), appId: String? = nil, appNom: String? = nil,
                texte: String, insere: Bool = true, raison: String? = nil) {
        self.id = id; self.date = date; self.appId = appId; self.appNom = appNom
        self.texte = texte; self.insere = insere; self.raison = raison
    }
}

public struct GroupeHistorique: Equatable, Sendable {
    public var titre: String
    public var entrees: [EntreeHistorique]
    /// Le jour du groupe (celui de sa première dictée).
    public var jour: Date? { entrees.first?.date }
}

/// L'historique des dictées : les plus récentes d'abord, borné, filtrable, groupé par jour. Logique pure.
public struct Historique: Codable, Equatable, Sendable {
    public static let limiteParDefaut = 500
    public private(set) var entrees: [EntreeHistorique] = []

    public init(entrees: [EntreeHistorique] = []) { self.entrees = entrees.sorted { $0.date > $1.date } }

    public var estVide: Bool { entrees.isEmpty }

    /// Ajoute une entrée en tête et ne garde que les `limite` plus récentes.
    public mutating func ajouter(_ entree: EntreeHistorique, limite: Int = Historique.limiteParDefaut) {
        entrees.insert(entree, at: 0)
        if entrees.count > max(1, limite) { entrees.removeLast(entrees.count - max(1, limite)) }
    }

    /// Nombre de mots d'un texte (séparés par des espaces ; « l'arrivée » ou « c'est » comptent pour un).
    public static func compterMots(_ texte: String) -> Int {
        texte.split(whereSeparator: { $0.isWhitespace }).count
    }

    /// Mots dictés le jour de `jour` (le texte final, tel qu'il a été écrit).
    public func motsLe(_ jour: Date = Date(), calendrier: Calendar = .current) -> Int {
        entrees.filter { calendrier.isDate($0.date, inSameDayAs: jour) }.reduce(0) { $0 + Self.compterMots($1.texte) }
    }

    public mutating func supprimer(id: UUID) { entrees.removeAll { $0.id == id } }
    public mutating func effacer() { entrees.removeAll() }

    /// Compare sans tenir compte des majuscules ni des accents (« cafe » trouve « Café »).
    public static func plier(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
            .replacingOccurrences(of: "\u{2019}", with: "'")
    }

    /// Les entrées dont le texte ou l'app de destination contient tous les mots de la recherche.
    public func filtrer(_ requete: String) -> [EntreeHistorique] {
        let mots = Self.plier(requete).split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !mots.isEmpty else { return entrees }
        return entrees.filter { e in
            let cible = Self.plier(e.texte + " " + (e.appNom ?? ""))
            return mots.allSatisfy { cible.contains($0) }
        }
    }

    /// Groupes par jour : « Aujourd'hui », « Hier », puis « lundi 2 novembre » (avec l'année si ce n'est pas l'année courante).
    public static func groupes(_ entrees: [EntreeHistorique], maintenant: Date = Date(),
                               calendrier: Calendar = .current, locale: Locale = Locale(identifier: "fr_FR")) -> [GroupeHistorique] {
        var sortie: [GroupeHistorique] = []
        let anneeCourante = calendrier.component(.year, from: maintenant)
        let formatCourt = DateFormatter(); formatCourt.locale = locale; formatCourt.calendar = calendrier
        formatCourt.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        let formatLong = DateFormatter(); formatLong.locale = locale; formatLong.calendar = calendrier
        formatLong.setLocalizedDateFormatFromTemplate("EEEEdMMMMy")
        for e in entrees {
            let titre: String
            if calendrier.isDate(e.date, inSameDayAs: maintenant) { titre = "Aujourd\u{2019}hui" }
            else if let hier = calendrier.date(byAdding: .day, value: -1, to: maintenant), calendrier.isDate(e.date, inSameDayAs: hier) { titre = "Hier" }
            else if calendrier.component(.year, from: e.date) == anneeCourante { titre = formatCourt.string(from: e.date) }
            else { titre = formatLong.string(from: e.date) }
            if let dernier = sortie.last, dernier.titre == titre { sortie[sortie.count - 1].entrees.append(e) }
            else { sortie.append(GroupeHistorique(titre: titre, entrees: [e])) }
        }
        return sortie
    }

    // MARK: fichier

    /// JSON lisible. Une lecture qui échoue (fichier abîmé) rend un historique vide plutôt que de planter.
    public func donnees() -> Data? {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? e.encode(self)
    }
    public static func depuis(_ donnees: Data) -> Historique? {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return try? d.decode(Historique.self, from: donnees)
    }
}

/// Déplacement de la sélection au clavier (↑ ↓), avec retour de l'autre côté aux extrémités (comme panneau-v3-C).
public enum Selection {
    public static func deplacer(_ courant: Int, de delta: Int, sur total: Int) -> Int {
        guard total > 0 else { return 0 }
        let c = min(max(courant, 0), total - 1)
        return ((c + delta) % total + total) % total
    }
}
