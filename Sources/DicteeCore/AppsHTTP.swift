import Foundation

// Le réseau de « Tes apps » (Notion, Airtable, Shopify, HubSpot, Stripe) : un transport injectable (les contrôles en donnent un faux, jamais le vrai réseau), un
// espacement entre deux requêtes (les limites de débit des API), et la lecture commune des réponses (codes, « Retry-After », date du
// serveur). La clé ne quitte jamais l'en-tête `Authorization` : ni journal, ni message d'erreur.

/// Envoie une requête et rend la réponse. Le vrai : `TransportURLSession` ; les contrôles : un faux qui rend des JSON d'exemple.
public protocol TransportHTTP: Sendable {
    func envoyer(_ requete: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// Le vrai transport : une session éphémère (rien en cache ni en cookie), 20 s au plus par requête.
public final class TransportURLSession: TransportHTTP {
    private let session: URLSession
    public init(delai: TimeInterval = 20) {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = delai
        c.timeoutIntervalForResource = delai * 2
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.httpCookieStorage = nil
        c.urlCache = nil
        session = URLSession(configuration: c)
    }
    public func envoyer(_ requete: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (d, r) = try await session.data(for: requete)
        guard let h = r as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (d, h)
    }
}

/// Garde un écart minimal entre deux requêtes vers la même API (Notion : 3 par seconde en moyenne ; Airtable : 5 par seconde et par
/// base). L'attente et l'horloge sont injectables : les contrôles ne dorment jamais.
public actor EspacementRequetes {
    public let ecart: TimeInterval
    private let horloge: @Sendable () -> Date
    private let dormir: @Sendable (TimeInterval) async -> Void
    private var prochaine: Date?

    public init(ecart: TimeInterval, horloge: @escaping @Sendable () -> Date = { Date() },
                dormir: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) }) {
        self.ecart = ecart; self.horloge = horloge; self.dormir = dormir
    }

    /// Attend s'il le faut, puis réserve la place de la requête suivante.
    public func patienter() async {
        let maintenant = horloge()
        let depart = max(maintenant, prochaine ?? maintenant)
        prochaine = depart.addingTimeInterval(ecart)
        let attente = depart.timeIntervalSince(maintenant)
        if attente > 0 { await dormir(attente) }
    }
}

/// Lecture commune des réponses HTTP.
public enum ReponseHTTP {
    /// « Retry-After » en secondes (un nombre ; une date HTTP n'est pas utilisée par ces API) ; nil : absent ou illisible.
    public static func reessayerApres(_ r: HTTPURLResponse) -> Double? {
        guard let v = r.value(forHTTPHeaderField: "Retry-After")?.trimmingCharacters(in: .whitespaces), let s = Double(v), s >= 0 else { return nil }
        return min(s, 3600)
    }
    /// La date du serveur (en-tête « Date », RFC 7231) : l'horloge d'Airtable, pour des fenêtres sans trou ni chevauchement.
    public static func dateServeur(_ r: HTTPURLResponse) -> Date? {
        guard let v = r.value(forHTTPHeaderField: "Date") else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return f.date(from: v)
    }
    /// Une date ISO 8601, avec ou sans fractions de seconde (« 2026-11-13T09:41:00.000Z »), ou un jour seul (« 2026-11-13 », minuit
    /// dans le fuseau `fuseau`).
    public static func date(_ s: String?, fuseau: TimeZone = .current) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: s) { return d }
        if s.count == 10 {
            var cal = Calendar(identifier: .gregorian); cal.timeZone = fuseau
            let p = s.split(separator: "-").compactMap { Int($0) }
            guard p.count == 3 else { return nil }
            return cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
        }
        return nil
    }
    /// « 2026-11-13T09:41:00.000Z » (UTC, millisecondes) : le format qu'attendent les formules d'Airtable.
    public static func iso(_ d: Date) -> String {
        d.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }
    /// Le jour local « 2026-11-13 » (filtre « date égale à » de Notion).
    public static func jour(_ d: Date, fuseau: TimeZone = .current) -> String {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = fuseau
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
    /// Un objet JSON (dictionnaire) ; nil sinon.
    public static func objet(_ d: Data) -> [String: Any]? { (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] }

    /// Le classement commun d'un code HTTP qui n'est pas un succès. `code` : le code d'erreur de l'API dans le corps, s'il y en a un.
    public static func erreur(_ app: AppBranchee, statut: Int, code: String?, reessayer: Double?) -> ErreurApp {
        switch statut {
        case 401: return .cleRefusee(app)
        case 403: return code == "restricted_resource" ? .introuvable(app) : .droitsManquants(app, "accès refusé")
        case 404: return .introuvable(app)
        // Airtable demande 30 s après un 429 ; HubSpot compte par fenêtres de 10 s ; Notion et Shopify donnent « Retry-After »
        case 429: return .limite(app, reessayerDans: reessayer ?? (app == .airtable ? 30 : app == .hubspot ? 10 : 60))
        case 500...599: return .serveur(app, statut)
        default: return .refus(app, statut)
        }
    }

    /// Envoie, classe les erreurs (réseau, codes), et rend le JSON d'une réponse réussie.
    /// `classer` : le classement propre à une API (le corps d'erreur lu) ; nil : le classement commun.
    static func json(_ app: AppBranchee, _ requete: URLRequest, transport: TransportHTTP, espacement: EspacementRequetes,
                     codeErreur: ([String: Any]) -> String?,
                     classer: (Int, [String: Any]?) -> ErreurApp? = { _, _ in nil }) async throws(ErreurApp) -> (objet: [String: Any], reponse: HTTPURLResponse) {
        await espacement.patienter()
        let d: Data, r: HTTPURLResponse
        do { (d, r) = try await transport.envoyer(requete) } catch { throw .reseau(app) }
        guard (200..<300).contains(r.statusCode) else {
            let corps = objet(d)
            throw classer(r.statusCode, corps) ?? erreur(app, statut: r.statusCode, code: corps.flatMap(codeErreur), reessayer: reessayerApres(r))
        }
        guard let o = objet(d) else { throw .reponseIllisible(app) }
        return (o, r)
    }
}
