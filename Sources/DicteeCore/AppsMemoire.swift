import Foundation

// La mémoire de « Tes apps » (fichier `apps.json` du dossier de Voxile, 0600) : ce qui est branché, ce que Hugues a choisi (base Notion,
// table Airtable), ce qui a déjà été vu (pour ne jamais annoncer deux fois la même chose) et où reprendre (fenêtres de Mail et
// d'Airtable). JAMAIS une clé : elles sont dans le Trousseau.

public struct MemoireApps: Codable, Equatable, Sendable {
    public var branchees: Set<AppBranchee> = []
    public var notion: ReglageNotion?
    public var airtable: ReglageAirtable?
    /// Les clés déjà vues, avec l'heure où on les a vues (oubliées après `garde`).
    public var vues: [String: Date] = [:]
    /// Les apps dont le premier passage est fait. Au premier passage, tout ce qui existe déjà est retenu SANS être annoncé (300 mails non
    /// lus ne deviennent pas 300 annonces) ; on l'affiche seulement.
    public var amorcees: Set<AppBranchee> = []
    /// Le début de la prochaine fenêtre d'Airtable (heure d'Airtable).
    public var airtableDepuis: Date?
    /// Le dernier passage réussi dans Mail (heure du Mac).
    public var mailDernier: Date?

    /// Une clé vue reste retenue 30 jours (au-delà, la même chose ne peut plus revenir : un mail non lu de plus de 2 jours n'est pas relu,
    /// une fiche modifiée a une autre clé), 4 000 au plus (les plus anciennes partent d'abord).
    public static let garde: TimeInterval = 30 * 86_400
    public static let maxVues = 4_000

    public init() {}

    /// Ne garde, de `elements`, que ce qui n'a jamais été vu (et pas deux fois la même clé dans la liste), et le retient comme vu. Avant
    /// le premier passage de l'app (`amorcees`), rien n'est rendu : tout est retenu.
    public mutating func retenir(_ elements: [Nouveaute], app: AppBranchee, maintenant: Date) -> [Nouveaute] {
        var nouvelles: [Nouveaute] = []
        for e in elements where vues[e.id] == nil {
            vues[e.id] = maintenant
            nouvelles.append(e)
        }
        let premiere = !amorcees.contains(app)
        amorcees.insert(app)
        oublierLesVieilles(maintenant: maintenant)
        return premiere ? [] : nouvelles
    }

    public mutating func oublierLesVieilles(maintenant: Date) {
        vues = vues.filter { maintenant.timeIntervalSince($0.value) < Self.garde }
        if vues.count > Self.maxVues {
            let gardees = vues.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.prefix(Self.maxVues)
            vues = Dictionary(uniqueKeysWithValues: gardees.map { ($0.key, $0.value) })
        }
    }

    /// Débrancher oublie ce qui touche à l'app : son réglage, ses clés vues, son amorce (rebranchée, elle repart sans rien annoncer
    /// d'ancien).
    public mutating func oublier(_ app: AppBranchee) {
        branchees.remove(app); amorcees.remove(app)
        vues = vues.filter { !$0.key.hasPrefix(app.rawValue + ":") }
        switch app {
        case .notion: notion = nil
        case .airtable: airtable = nil; airtableDepuis = nil
        case .mail: mailDernier = nil
        case .agenda: break
        }
    }

    /// La fenêtre de Mail : 2 jours la première fois ; ensuite, depuis le dernier passage réussi avec une marge, jamais plus de 2 jours.
    public func fenetreMail(maintenant: Date) -> Int {
        guard let d = mailDernier else { return ScriptMail.fenetreInitiale }
        return min(ScriptMail.fenetreInitiale, max(60, Int(maintenant.timeIntervalSince(d).rounded(.up)) + ScriptMail.marge))
    }
}

extension MemoireApps: FichierJSON {
    public static func depuis(_ d: Data) -> MemoireApps? {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(MemoireApps.self, from: d)
    }
    public func donnees() -> Data? {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.sortedKeys]
        return try? enc.encode(self)
    }
}

/// Le rythme des sondages : chaque app a son intervalle ; une erreur l'espace (doublé à chaque fois, 30 min au plus) ; une limite de débit
/// est respectée à la seconde ; une erreur qui demande un geste (clé refusée, autorisation) arrête l'app jusqu'à ce geste ; Mail
/// fermé n'est jamais sondé. Logique pure : l'interface n'a qu'à rappeler `AppsBranchees.sonder()` à `prochainSondage`.
public struct PlanSondages: Equatable, Sendable {
    /// Mail : une minute (le script coûte quelques dizaines de millisecondes) ; Agenda : 5 min (rien n'y change sans prévenir, l'îlot
    /// écoute déjà les changements) ; Notion et Airtable : 3 min (loin de leurs limites).
    public static func intervalle(_ a: AppBranchee) -> TimeInterval {
        switch a {
        case .mail: return 60
        case .agenda: return 300
        case .notion, .airtable: return 180
        }
    }
    public static let espacementMax: TimeInterval = 30 * 60
    /// Un sondage de Mail qui a pris `d` secondes repousse le suivant à au moins 30 fois `d` (Mail occupé, boîte énorme : jamais plus
    /// de 3 % du temps passé à le sonder).
    public static let facteurCout: Double = 30

    public struct Suivi: Equatable, Sendable {
        public var prochain: Date
        public var echecs = 0
        public var arrete = false
    }
    public private(set) var suivis: [AppBranchee: Suivi] = [:]

    public init() {}

    /// À sonder tout de suite (branchement, geste de Hugues qui relève l'arrêt).
    public mutating func maintenant(_ a: AppBranchee, _ t: Date) { suivis[a] = Suivi(prochain: t) }
    public mutating func retirer(_ a: AppBranchee) { suivis[a] = nil }

    /// Les apps à sonder à `t`, parmi celles branchées.
    public func aSonder(_ t: Date, branchees: Set<AppBranchee>) -> [AppBranchee] {
        branchees.sorted().filter { a in
            guard let s = suivis[a] else { return true }
            return !s.arrete && s.prochain <= t
        }
    }

    /// Un sondage réussi (qui a pris `duree` secondes).
    public mutating func reussi(_ a: AppBranchee, _ t: Date, duree: TimeInterval = 0) {
        let attente = max(Self.intervalle(a), a == .mail ? duree * Self.facteurCout : 0)
        suivis[a] = Suivi(prochain: t.addingTimeInterval(min(attente, Self.espacementMax)))
    }

    /// Mail fermé : rien de sondé ; on regarde de nouveau à l'intervalle normal (savoir s'il tourne ne coûte rien).
    public mutating func enPause(_ a: AppBranchee, _ t: Date) {
        suivis[a] = Suivi(prochain: t.addingTimeInterval(Self.intervalle(a)), echecs: suivis[a]?.echecs ?? 0)
    }

    public mutating func echoue(_ a: AppBranchee, _ t: Date, _ e: ErreurApp) {
        var s = suivis[a] ?? Suivi(prochain: t)
        s.echecs += 1
        if e.demandeUnGeste { s.arrete = true; suivis[a] = s; return }
        var attente = min(Self.intervalle(a) * pow(2, Double(s.echecs - 1)), Self.espacementMax)
        if case .limite(_, let r) = e { attente = max(r, min(attente, Self.espacementMax)) }
        s.prochain = t.addingTimeInterval(attente)
        suivis[a] = s
    }

    /// Le prochain rendez-vous de l'interface : la plus proche échéance d'une app branchée non arrêtée (nil : rien à faire).
    public func prochain(branchees: Set<AppBranchee>, apres t: Date) -> Date? {
        branchees.compactMap { a -> Date? in
            guard let s = suivis[a] else { return t }
            return s.arrete ? nil : max(s.prochain, t)
        }.min()
    }
}
