import Foundation

/// Les dernières latences mesurées pour chaque modèle de transcription (relâchement de fn → réponse complète de Groq, en ms),
/// pour afficher discrètement dans les Réglages « chez toi, environ X ms ». Logique pure (le stockage est dans `Settings`).
public struct SuiviLatence: Codable, Equatable, Sendable {
    public static let garde = 30
    /// Il faut au moins ce nombre de mesures pour afficher un chiffre.
    public static let minimum = 3

    public var parModele: [String: [Int]] = [:]

    public init() {}

    public mutating func noter(_ ms: Int, modele: ModeleWhisper) {
        guard ms >= 0, ms < 20_000 else { return }
        var l = parModele[modele.rawValue] ?? []
        l.append(ms)
        if l.count > Self.garde { l.removeFirst(l.count - Self.garde) }
        parModele[modele.rawValue] = l
    }

    public func mediane(_ modele: ModeleWhisper) -> Int? {
        guard let l = parModele[modele.rawValue], l.count >= Self.minimum else { return nil }
        let t = l.sorted()
        return t.count % 2 == 1 ? t[t.count / 2] : (t[t.count / 2 - 1] + t[t.count / 2]) / 2
    }

    /// « 290 ms » arrondi à la dizaine, ou nil tant qu'il y a trop peu de mesures.
    public func texte(_ modele: ModeleWhisper) -> String? {
        mediane(modele).map { "\(Int((Double($0) / 10).rounded()) * 10) ms" }
    }

    /// La phrase sous le réglage : les deux modèles, une ligne chacun, avec le chiffre mesuré chez Hugues quand il existe.
    public func phrase() -> String {
        ModeleWhisper.allCases.map { m in
            let nom = m == .rapide ? "Rapide" : "Précis"
            let chiffre = texte(m).map { " (environ \($0) chez toi)" } ?? ""
            return "\(nom) : \(m.phrase.lowercased().replacingOccurrences(of: ".", with: ""))\(chiffre)."
        }.joined(separator: "\n")
    }

    public func donnees() -> Data? { try? JSONEncoder().encode(self) }
    public static func depuis(_ d: Data?) -> SuiviLatence { d.flatMap { try? JSONDecoder().decode(SuiviLatence.self, from: $0) } ?? SuiviLatence() }
}
