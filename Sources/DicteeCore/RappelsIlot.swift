import Foundation

/// Un rappel. Gardé localement par Verbe (Application Support/Dictee/rappels.json, jamais dans git), jamais envoyé nulle part.
public struct Rappel: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var texte: String
    public var echeance: Date
    /// Le moment où l'îlot a sonné pour lui. Tant qu'il est là sans réponse, la cloche reste dans l'aile.
    public var sonneLe: Date?
    public var cree: Date
    public init(id: UUID = UUID(), texte: String, echeance: Date, sonneLe: Date? = nil, cree: Date) {
        self.id = id; self.texte = texte; self.echeance = echeance; self.sonneLe = sonneLe; self.cree = cree
    }
}

public struct ListeRappels: Codable, Equatable, Sendable {
    public private(set) var rappels: [Rappel] = []
    public init(rappels: [Rappel] = []) { self.rappels = rappels }
    public static let reportParDefaut: Double = 600     // « Plus tard » : 10 minutes
    public static let limite = 200

    @discardableResult
    public mutating func ajouter(texte: String, echeance: Date, maintenant: Date) -> Rappel? {
        let t = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        let r = Rappel(texte: String(t.prefix(200)), echeance: echeance, cree: maintenant)
        rappels.append(r)
        if rappels.count > Self.limite { rappels.removeFirst(rappels.count - Self.limite) }
        return r
    }
    public mutating func fait(_ id: UUID) { rappels.removeAll { $0.id == id } }
    public mutating func annuler(_ id: UUID) { fait(id) }
    /// « Plus tard » : il sonnera à nouveau dans 10 minutes.
    public mutating func reporter(_ id: UUID, de secondes: Double = reportParDefaut, depuis maintenant: Date) {
        guard let i = rappels.firstIndex(where: { $0.id == id }) else { return }
        rappels[i].echeance = maintenant.addingTimeInterval(secondes); rappels[i].sonneLe = nil
    }
    public mutating func marquerSonne(_ id: UUID, a maintenant: Date) {
        guard let i = rappels.firstIndex(where: { $0.id == id }) else { return }
        rappels[i].sonneLe = maintenant
    }
    /// Ceux dont l'heure est venue et qui n'ont pas encore sonné (y compris ceux arrivés pendant que Verbe était fermé).
    public func dus(a maintenant: Date) -> [Rappel] {
        rappels.filter { $0.sonneLe == nil && $0.echeance <= maintenant }.sorted { $0.echeance < $1.echeance }
    }
    /// Ceux qui ont sonné sans réponse : la cloche reste dans l'aile.
    public var enAttente: [Rappel] { rappels.filter { $0.sonneLe != nil }.sorted { $0.echeance < $1.echeance } }
    /// Ceux qui n'ont pas encore sonné, du plus proche au plus lointain.
    public func aVenir(a maintenant: Date) -> [Rappel] {
        rappels.filter { $0.sonneLe == nil && $0.echeance > maintenant }.sorted { $0.echeance < $1.echeance }
    }
    /// La prochaine heure à laquelle il faudra se réveiller.
    public func prochaineEcheance() -> Date? { rappels.filter { $0.sonneLe == nil }.map(\.echeance).min() }

    public func donnees() -> Data? {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys]
        return try? e.encode(self)
    }
    public static func depuis(_ donnees: Data) -> ListeRappels? {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return try? d.decode(ListeRappels.self, from: donnees)
    }

    /// « aujourd'hui », « demain », ou la date courte : sous « Rappel ajouté ».
    public static func jour(de date: Date, maintenant: Date, calendrier: Calendar = .current) -> String {
        if calendrier.isDate(date, inSameDayAs: maintenant) { return "aujourd\u{2019}hui" }
        if let demain = calendrier.date(byAdding: .day, value: 1, to: maintenant), calendrier.isDate(date, inSameDayAs: demain) { return "demain" }
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.setLocalizedDateFormatFromTemplate("EEEd MMM")
        return f.string(from: date)
    }

    /// « maintenant », « il y a 12 min », sur la ligne d'un rappel sonné.
    public static func retard(de echeance: Date, maintenant: Date) -> String {
        let s = maintenant.timeIntervalSince(echeance)
        if s < 60 { return "maintenant" }
        let m = Int(s / 60)
        return m < 60 ? "il y a \(m) min" : "il y a \(m / 60) h"
    }
}
