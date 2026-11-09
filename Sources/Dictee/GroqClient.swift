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
    private func compterEnvoi(_ modele: ModeleWhisper) {
        verrou.lock(); compteRequetes += 1; verrou.unlock()
        BudgetRequetes.whisper(modele).noterEnvoi()
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

    /// Transcription d'un morceau. `langue` fixée (`fr`, `en`) : envoyée telle quelle à Whisper. `langue` nil (mode Automatique) :
    /// Whisper détecte, la langue détectée est lue (`verbose_json`) et, si elle n'est pas dans `autorisees`, le même morceau est
    /// relancé aussitôt en forçant la première langue autorisée (la détection se trompe souvent sur les phrases très courtes).
    func transcrire(fichier: EncodeurAudio.Fichier, prompt: String, langue: String?, autorisees: [String] = ChoixLangue.autoriseesParDefaut,
                    etiquette: String = "", modele: ModeleWhisper = Settings.modeleWhisper) async throws -> String {
        // Le modèle « Précis » est limité ou en panne : le même morceau part aussitôt en « Rapide » (limites comptées à part), jamais d'attente en plus.
        var modele = modele
        if modele == .precis, BudgetRequetes.precis.enPause() {
            Log.ecrire("\(etiquette) : modèle précis en pause (limite atteinte) -> turbo pour ce morceau")
            modele = .rapide
        }
        do {
            return try await transcrireAvec(modele: modele, fichier: fichier, prompt: prompt, langue: langue, autorisees: autorisees, etiquette: etiquette)
        } catch let e as GroqErreur where modele == .precis && Self.justifieLeSecours(e) {
            Log.ecrire("\(etiquette) : modèle précis en échec (\(e)) -> même morceau relancé en turbo")
            return try await transcrireAvec(modele: .rapide, fichier: fichier, prompt: prompt, langue: langue, autorisees: autorisees, etiquette: etiquette + " (turbo de secours)")
        }
    }

    /// Limite atteinte, panne de Groq ou réseau : le turbo a ses propres limites et peut répondre.
    static func justifieLeSecours(_ e: GroqErreur) -> Bool {
        switch e {
        case .http(let c): return c == 429 || c >= 500
        case .reseau: return true
        default: return false
        }
    }

    private func transcrireAvec(modele: ModeleWhisper, fichier: EncodeurAudio.Fichier, prompt: String, langue: String?, autorisees: [String], etiquette: String) async throws -> String {
        if let langue, !langue.isEmpty {
            return try await requete(modele: modele, fichier: fichier, prompt: prompt, langue: langue, verbose: false, etiquette: etiquette).texte
        }
        let t0 = ProcessInfo.processInfo.systemUptime
        let premiere = try await requete(modele: modele, fichier: fichier, prompt: prompt, langue: nil, verbose: true, etiquette: etiquette)
        if ChoixLangue.accepter(nomDetecte: premiere.langue, autorisees: autorisees) { return premiere.texte }
        let forcee = autorisees.first ?? ChoixLangue.defaut
        Log.ecrire("\(etiquette) : langue détectée « \(premiere.langue ?? "?") » hors de la liste (\(autorisees.joined(separator: ", "))) -> même morceau relancé en « \(forcee) » (+\(Int((ProcessInfo.processInfo.systemUptime - t0) * 1000)) ms déjà perdus)")
        return try await requete(modele: modele, fichier: fichier, prompt: prompt, langue: forcee, verbose: false, etiquette: etiquette + " (langue forcée)").texte
    }

    private func requete(modele: ModeleWhisper, fichier: EncodeurAudio.Fichier, prompt: String, langue: String?, verbose: Bool, etiquette: String) async throws -> (texte: String, langue: String?) {
        guard let cle else { throw GroqErreur.pasDeCle }
        // Mesure du « secours rapide » : la première requête de chaque morceau est retardée (jamais en usage normal).
        if let ms = ProcessInfo.processInfo.environment["DICTEE_RETARD_PREMIERE_REQUETE_MS"].flatMap({ Double($0) }), !etiquette.contains("secours") {
            try await Task.sleep(for: .milliseconds(ms))
        }
        let frontiere = "dictee-\(UUID().uuidString)"
        var corps = Data()
        func champ(_ nom: String, _ valeur: String) {
            corps.append("--\(frontiere)\r\nContent-Disposition: form-data; name=\"\(nom)\"\r\n\r\n\(valeur)\r\n".data(using: .utf8)!)
        }
        champ("model", modele.identifiant)
        champ("response_format", verbose ? "verbose_json" : "json")
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

        compterEnvoi(modele)
        let mesure = MesureReseau()
        let data: Data, reponse: URLResponse
        do { (data, reponse) = try await session.data(for: req, delegate: mesure) }
        catch is CancellationError { throw CancellationError() }
        catch let e as URLError where e.code == .cancelled { throw CancellationError() }
        catch { throw GroqErreur.reseau((error as? URLError).map { "code \($0.code.rawValue)" } ?? "inconnu") }
        if !mesure.resume.isEmpty { Log.ecrire("réseau \(etiquette) : \(mesure.resume), \(corps.count / 1024) Ko envoyés") }

        guard let http = reponse as? HTTPURLResponse else { throw GroqErreur.reponseIllisible }
        let budget = BudgetRequetes.whisper(modele)
        budget.noterRestantJour(http.value(forHTTPHeaderField: "x-ratelimit-remaining-requests").flatMap { Int($0) })
        if http.statusCode == 429 {
            let attente = BudgetRequetes.secondes(deEnTete: http.value(forHTTPHeaderField: "retry-after"))
            budget.noter429(retryAfter: attente)
            Log.ecrire("Groq limite atteinte (429, \(modele.identifiant)), nouvelle tentative possible dans \(Int(attente ?? 0)) s : envois de confort suspendus")
        }
        guard http.statusCode == 200 else { throw GroqErreur.http(http.statusCode) }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let texte = json["text"] as? String else {
            throw GroqErreur.reponseIllisible
        }
        return (texte, json["language"] as? String)
    }

    /// Une complétion de texte (remise au propre). Température basse, sortie = le texte seul.
    /// `delai` : durée maximale en secondes ; au-delà, l'appel est abandonné (`GroqErreur.reseau`).
    func completer(modele: String, systeme: String, texte: String, delai: Double) async throws -> String {
        // Les deux gpt-oss de Groq ont chacun leurs limites gratuites (200 000 jetons par jour chacun : une remise au propre en coûte ~1 000).
        // Quand l'un est à sec (429), l'autre prend le relais tout de suite, et le premier n'est pas réessayé avant la fin de la pause demandée.
        let debut = ProcessInfo.processInfo.systemUptime
        let candidats = ModelesTexte.ordre(prefere: modele, pauses: pausesModeles())
        var derniere: Error = GroqErreur.http(429)
        for (i, m) in candidats.enumerated() {
            let reste = delai - (ProcessInfo.processInfo.systemUptime - debut)
            if reste < 0.15 { break }
            do {
                if i > 0 { Log.ecrire("remise au propre : \(candidats[0]) à sec (429), \(m) prend le relais") }
                return try await completerUnModele(modele: m, systeme: systeme, texte: texte, delai: reste)
            } catch GroqErreur.http(429) { derniere = GroqErreur.http(429); continue }
        }
        throw derniere
    }

    private var pausesModelesTexte: [String: Double] = [:]
    private func pausesModeles() -> [String: Double] {
        verrou.lock(); defer { verrou.unlock() }
        return pausesModelesTexte
    }
    private func mettreEnPause(_ modele: String, secondes: Double) {
        verrou.lock(); pausesModelesTexte[modele] = ProcessInfo.processInfo.systemUptime + max(5, min(secondes, 3600)); verrou.unlock()
    }

    private func completerUnModele(modele: String, systeme: String, texte: String, delai: Double) async throws -> String {
        guard let cle else { throw GroqErreur.pasDeCle }
        var corps: [String: Any] = [
            "model": modele,
            "temperature": 0.1,
            "stream": false,
            "max_completion_tokens": 300 + texte.count,
            "messages": [["role": "system", "content": systeme], ["role": "user", "content": texte]],
        ]
        if let effort = ModelesTexte.effortDeRaisonnement(modele) { corps["reasoning_effort"] = effort; if modele.hasPrefix("openai/") { corps["include_reasoning"] = false } }
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
            let attente = BudgetRequetes.secondes(deEnTete: http.value(forHTTPHeaderField: "retry-after"))
            mettreEnPause(modele, secondes: attente ?? 30)
            // Si l'autre modèle est aussi en pause, plus aucune requête de confort pendant l'attente.
            if ModelesTexte.ordre(prefere: modele, pauses: pausesModeles()).isEmpty { BudgetRequetes.nettoyage.noter429(retryAfter: attente) }
            Log.ecrire("Groq (\(modele)) : limite atteinte (429), nouvelle tentative possible dans \(Int(attente ?? 0)) s")
        }
        guard http.statusCode == 200 else { throw GroqErreur.http(http.statusCode) }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choix = (json["choices"] as? [[String: Any]])?.first,
              let message = choix["message"] as? [String: Any],
              let contenu = message["content"] as? String else { throw GroqErreur.reponseIllisible }
        return contenu
    }
}

extension GroqClient {
    /// Une complétion pour la note de réunion : réponse en JSON, modèle de raisonnement (effort réglable), longue attente permise.
    /// Renvoie le texte et le nombre de jetons utilisés (pour espacer les requêtes sous le plafond par minute de Groq).
    /// En cas de 429, `GroqErreur.http(429)` est levée et `retryApres` donne l'attente demandée par Groq.
    func completerNote(modele: String, systeme: String, texte: String, maxSortie: Int, effort: String, delai: Double = 120) async throws -> (texte: String, jetons: Int, retryApres: Double?) {
        guard let cle = CleGroq.lire() else { throw GroqErreur.pasDeCle }
        var corps: [String: Any] = [
            "model": modele,
            "temperature": 0.2,
            "stream": false,
            "max_completion_tokens": maxSortie,
            "response_format": ["type": "json_object"],
            "messages": [["role": "system", "content": systeme], ["role": "user", "content": texte]],
        ]
        if modele.hasPrefix("openai/gpt-oss") { corps["reasoning_effort"] = effort; corps["include_reasoning"] = false }
        var req = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.timeoutInterval = delai
        req.setValue("Bearer \(cle)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: corps)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = delai
        config.timeoutIntervalForResource = delai
        let data: Data, reponse: URLResponse
        do { (data, reponse) = try await URLSession(configuration: config).data(for: req) }
        catch is CancellationError { throw CancellationError() }
        catch let e as URLError where e.code == .cancelled { throw CancellationError() }
        catch { throw GroqErreur.reseau((error as? URLError).map { "code \($0.code.rawValue)" } ?? "inconnu") }
        guard let http = reponse as? HTTPURLResponse else { throw GroqErreur.reponseIllisible }
        if http.statusCode == 429 {
            let attente = BudgetRequetes.secondes(deEnTete: http.value(forHTTPHeaderField: "retry-after"))
            Log.ecrire("Groq (note de réunion) : limite atteinte (429), attente demandée \(Int(attente ?? 0)) s")
            throw NoteLimite(retryApres: attente)
        }
        guard http.statusCode == 200 else {
            // Le code d'erreur seulement (jamais le corps : « failed_generation » contient le texte de la note).
            let code = ((try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? [String: Any])?["code"] as? String
            Log.ecrire("Groq (note de réunion) : HTTP \(http.statusCode)\(code.map { ", code « \($0) »" } ?? "")")
            throw GroqErreur.http(http.statusCode)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choix = (json["choices"] as? [[String: Any]])?.first,
              let message = choix["message"] as? [String: Any],
              let contenu = message["content"] as? String else { throw GroqErreur.reponseIllisible }
        let jetons = ((json["usage"] as? [String: Any])?["total_tokens"] as? Int) ?? 0
        return (contenu, jetons, nil)
    }
}

/// La limite de Groq est atteinte pendant la rédaction de la note : il faut attendre `retryApres` secondes.
struct NoteLimite: Error { var retryApres: Double? }
