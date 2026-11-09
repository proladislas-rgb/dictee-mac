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

    /// Ouvre la connexion TLS à l'avance. Requête sans clé : seule la poignée de main compte, la réponse (401) est ignorée.
    func prechauffer() {
        var req = URLRequest(url: base.appendingPathComponent("models"))
        req.httpMethod = "HEAD"
        req.timeoutInterval = 4
        session.dataTask(with: req) { _, _, _ in }.resume()
    }

    func transcrire(wav: Data, prompt: String, langue: String?) async throws -> String {
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
        corps.append("--\(frontiere)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        corps.append(wav)
        corps.append("\r\n--\(frontiere)--\r\n".data(using: .utf8)!)

        var req = URLRequest(url: base.appendingPathComponent("audio/transcriptions"))
        req.httpMethod = "POST"
        req.setValue("Bearer \(cle)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(frontiere)", forHTTPHeaderField: "Content-Type")
        req.httpBody = corps

        let data: Data, reponse: URLResponse
        do { (data, reponse) = try await session.data(for: req) }
        catch is CancellationError { throw CancellationError() }
        catch let e as URLError where e.code == .cancelled { throw CancellationError() }
        catch { throw GroqErreur.reseau((error as? URLError).map { "code \($0.code.rawValue)" } ?? "inconnu") }

        guard let http = reponse as? HTTPURLResponse else { throw GroqErreur.reponseIllisible }
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

        let data: Data, reponse: URLResponse
        do { (data, reponse) = try await session.data(for: req) }
        catch is CancellationError { throw CancellationError() }
        catch let e as URLError where e.code == .cancelled { throw CancellationError() }
        catch { throw GroqErreur.reseau((error as? URLError).map { "code \($0.code.rawValue)" } ?? "inconnu") }

        guard let http = reponse as? HTTPURLResponse else { throw GroqErreur.reponseIllisible }
        guard http.statusCode == 200 else { throw GroqErreur.http(http.statusCode) }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choix = (json["choices"] as? [[String: Any]])?.first,
              let message = choix["message"] as? [String: Any],
              let contenu = message["content"] as? String else { throw GroqErreur.reponseIllisible }
        return contenu
    }
}
