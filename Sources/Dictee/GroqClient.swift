import Foundation
import DicteeCore

enum GroqErreur: Error, CustomStringConvertible {
    case pasDeCle
    case http(Int)
    case reponseIllisible
    case reseau(String)

    var description: String {
        switch self {
        case .pasDeCle: return "clé Groq introuvable (Trousseau ou ~/.config/groq/.env)"
        case .http(let code): return "Groq a répondu HTTP \(code)"
        case .reponseIllisible: return "réponse Groq illisible"
        case .reseau(let m): return "réseau : \(m)"
        }
    }
}

/// Relève les durées réseau d'une requête (URLSessionTaskMetrics) : connexion neuve ou réutilisée, protocole,
/// temps de connexion / TLS, envoi, attente du serveur, réception. Sert au journal (jamais de contenu, jamais la clé).
final class MesureReseau: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let verrou = NSLock()
    private(set) var resume = ""
    private(set) var reutilisee = false

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        guard let t = metrics.transactionMetrics.last else { return }
        func ms(_ a: Date?, _ b: Date?) -> Int? { guard let a, let b else { return nil }; return Int(((b.timeIntervalSince(a)) * 1000).rounded()) }
        var morceaux = [t.networkProtocolName ?? "?", t.isReusedConnection ? "connexion réutilisée" : "connexion neuve"]
        if !t.isReusedConnection {
            if let v = ms(t.domainLookupStartDate, t.domainLookupEndDate) { morceaux.append("DNS \(v) ms") }
            if let v = ms(t.connectStartDate, t.connectEndDate) { morceaux.append("connexion \(v) ms (dont TLS \(ms(t.secureConnectionStartDate, t.secureConnectionEndDate) ?? 0) ms)") }
        }
        if let v = ms(t.requestStartDate, t.requestEndDate) { morceaux.append("envoi \(v) ms") }
        if let v = ms(t.requestEndDate, t.responseStartDate) { morceaux.append("attente \(v) ms") }
        if let v = ms(t.responseStartDate, t.responseEndDate) { morceaux.append("réception \(v) ms") }
        verrou.lock(); resume = morceaux.joined(separator: ", "); reutilisee = t.isReusedConnection; verrou.unlock()
    }
}

/// Appels à Groq (Whisper large v3 turbo). Une seule session URLSession : la connexion HTTP/2 est réutilisée
/// par tous les morceaux, et `prechauffer()` l'ouvre dès l'appui sur fn.
/// La clé (Trousseau, sinon `~/.config/groq/.env`) est mise en mémoire et n'est jamais écrite dans le journal.
final class GroqClient: @unchecked Sendable {
    static let shared = GroqClient()

    private let session: URLSession
    private let verrou = NSLock()
    private var cleEnMemoire: String?
    private var cleLue = false
    /// La clé : lue au premier besoin (Trousseau, sinon ~/.config/groq/.env), gardée en mémoire. Jamais journalisée.
    private var cle: String? {
        verrou.lock(); defer { verrou.unlock() }
        if !cleLue { cleEnMemoire = CleGroq.lire(); cleLue = true }
        return cleEnMemoire
    }
    /// À appeler après l'enregistrement d'une nouvelle clé.
    func recharger() { verrou.lock(); cleLue = false; verrou.unlock() }
    private let base = URL(string: "https://api.groq.com/openai/v1")!

    init() {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.timeoutIntervalForRequest = 8
        config.waitsForConnectivity = false
        config.httpMaximumConnectionsPerHost = 4
        session = URLSession(configuration: config)
    }

    var cleDisponible: Bool { cle != nil }

    /// Nombre de requêtes Whisper lancées depuis le démarrage (le banc d'essai s'en sert pour compter son coût).
    private var compteRequetes = 0
    private func compterEnvoi() {
        verrou.lock(); compteRequetes += 1; verrou.unlock()
        BudgetRequetes.partage.noterEnvoi()
    }
    var requetesEnvoyees: Int { verrou.lock(); defer { verrou.unlock() }; return compteRequetes }

    /// Ouvre la connexion TLS à l'avance. Requête sans clé : seule la poignée de main compte, la réponse (401) est ignorée.
    /// Le temps de connexion est écrit dans le journal.
    func prechauffer() {
        var req = URLRequest(url: base.appendingPathComponent("models"))
        req.httpMethod = "HEAD"
        req.timeoutInterval = 4
        let mesure = MesureReseau()
        let debut = ProcessInfo.processInfo.systemUptime
        Task { [session] in
            _ = try? await session.data(for: req, delegate: mesure)
            let ms = Int((ProcessInfo.processInfo.systemUptime - debut) * 1000)
            Log.ecrire("préchauffage Groq : \(ms) ms (\(mesure.resume))")
        }
    }

    func transcrire(fichier: EncodeurAudio.Fichier, prompt: String, langue: String?, etiquette: String = "") async throws -> String {
        guard let cle else { throw GroqErreur.pasDeCle }
        let frontiere = "dictee-\(UUID().uuidString)"
        var corps = Data()
        func champ(_ nom: String, _ valeur: String) {
            corps.append("--\(frontiere)\r\nContent-Disposition: form-data; name=\"\(nom)\"\r\n\r\n\(valeur)\r\n".data(using: .utf8)!)
        }
        champ("model", "whisper-large-v3-turbo")
        champ("response_format", "json")
        champ("temperature", "0")
        if let langue, !langue.isEmpty { champ("language", langue) }
        if !prompt.isEmpty { champ("prompt", prompt) }
        corps.append("--\(frontiere)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(fichier.nom)\"\r\nContent-Type: \(fichier.type)\r\n\r\n".data(using: .utf8)!)
        corps.append(fichier.donnees)
        corps.append("\r\n--\(frontiere)--\r\n".data(using: .utf8)!)

        var req = URLRequest(url: base.appendingPathComponent("audio/transcriptions"))
        req.httpMethod = "POST"
        req.setValue("Bearer \(cle)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(frontiere)", forHTTPHeaderField: "Content-Type")
        req.httpBody = corps

        compterEnvoi()
        let mesure = MesureReseau()
        let data: Data, reponse: URLResponse
        do { (data, reponse) = try await session.data(for: req, delegate: mesure) }
        catch is CancellationError { throw CancellationError() }
        catch let e as URLError where e.code == .cancelled { throw CancellationError() }
        catch { throw GroqErreur.reseau((error as? URLError).map { "code \($0.code.rawValue)" } ?? "inconnu") }
        if !mesure.resume.isEmpty { Log.ecrire("réseau \(etiquette) : \(mesure.resume), \(corps.count / 1024) Ko envoyés") }

        guard let http = reponse as? HTTPURLResponse else { throw GroqErreur.reponseIllisible }
        BudgetRequetes.partage.noterRestantJour(http.value(forHTTPHeaderField: "x-ratelimit-remaining-requests").flatMap { Int($0) })
        if http.statusCode == 429 {
            let attente = BudgetRequetes.secondes(deEnTete: http.value(forHTTPHeaderField: "retry-after"))
            BudgetRequetes.partage.noter429(retryAfter: attente)
            Log.ecrire("Groq limite atteinte (429), nouvelle tentative possible dans \(Int(attente ?? 0)) s : envois de confort suspendus")
        }
        guard http.statusCode == 200 else { throw GroqErreur.http(http.statusCode) }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let texte = json["text"] as? String else {
            throw GroqErreur.reponseIllisible
        }
        return texte
    }

    /// Une complétion de texte (remise au propre). Température basse, sortie = le texte seul.
    /// `delai` : durée maximale en secondes ; au-delà, l'appel est abandonné (`GroqErreur.reseau`).
    func completer(modele: String, systeme: String, texte: String, delai: Double) async throws -> String {
        guard let cle else { throw GroqErreur.pasDeCle }
        var corps: [String: Any] = [
            "model": modele,
            "temperature": 0.1,
            "stream": false,
            "max_completion_tokens": 300 + texte.count,
            "messages": [["role": "system", "content": systeme], ["role": "user", "content": texte]],
        ]
        if modele.hasPrefix("openai/gpt-oss") { corps["reasoning_effort"] = "low"; corps["include_reasoning"] = false }
        var req = URLRequest(url: base.appendingPathComponent("chat/completions"))
        req.httpMethod = "POST"
        req.timeoutInterval = delai
        req.setValue("Bearer \(cle)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: corps)

        BudgetRequetes.nettoyage.noterEnvoi()
        let mesure = MesureReseau()
        let data: Data, reponse: URLResponse
        do { (data, reponse) = try await session.data(for: req, delegate: mesure) }
        catch is CancellationError { throw CancellationError() }
        catch let e as URLError where e.code == .cancelled { throw CancellationError() }
        catch { throw GroqErreur.reseau((error as? URLError).map { "code \($0.code.rawValue)" } ?? "inconnu") }
        if !mesure.resume.isEmpty { Log.ecrire("réseau remise au propre : \(mesure.resume)") }

        guard let http = reponse as? HTTPURLResponse else { throw GroqErreur.reponseIllisible }
        BudgetRequetes.nettoyage.noterRestantJour(http.value(forHTTPHeaderField: "x-ratelimit-remaining-requests").flatMap { Int($0) })
        BudgetRequetes.nettoyage.noterRestantJetons(http.value(forHTTPHeaderField: "x-ratelimit-remaining-tokens").flatMap { Int($0) })
        if http.statusCode == 429 {
            BudgetRequetes.nettoyage.noter429(retryAfter: BudgetRequetes.secondes(deEnTete: http.value(forHTTPHeaderField: "retry-after")))
            Log.ecrire("Groq (remise au propre) : limite atteinte (429)")
        }
        guard http.statusCode == 200 else { throw GroqErreur.http(http.statusCode) }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choix = (json["choices"] as? [[String: Any]])?.first,
              let message = choix["message"] as? [String: Any],
              let contenu = message["content"] as? String else { throw GroqErreur.reponseIllisible }
        return contenu
    }
}
