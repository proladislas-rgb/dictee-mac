import Foundation
import DicteeCore

/// Une étape de la mise à jour qui a échoué : `message` est la phrase sobre montrée à Hugues, `detail` va au journal.
struct ErreurMiseAJour: Error, LocalizedError {
    var message: String
    var detail: String
    var errorDescription: String? { message }
}

enum ResultatRecherche {
    case proposition(PropositionMiseAJour)
    case aJour
    /// Pas de réseau (ou GitHub injoignable) : silencieux pour une vérification automatique.
    case horsLigne
    /// La limite de requêtes de l'API est atteinte : rien avant cette heure.
    case limite(Date)
    case echec(String)
}

/// Refuse toute redirection qui sortirait de GitHub (ou de la machine, en test local).
final class GardeRedirections: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let politique: PolitiqueAdresses
    init(politique: PolitiqueAdresses) { self.politique = politique }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        if let url = request.url, politique.accepteRedirection(url) { completionHandler(request) } else {
            Log.ecrire("mise à jour : redirection refusée vers \(request.url?.host ?? "?")")
            completionHandler(nil)
        }
    }
}

/// Parle à GitHub : la dernière release, le fichier d'empreinte, le DMG. Aucun jeton, un en-tête User-Agent générique `Verbe-<version>`.
struct ClientMiseAJour {
    static let adresseAPI = URL(string: "https://api.github.com/repos/\(PolitiqueAdresses.depot)/releases/latest")!
    static let tailleMaxJSON = 2_000_000

    var versionActuelle: VersionApp
    var urlAPI = ClientMiseAJour.adresseAPI
    var politique = PolitiqueAdresses.production

    /// Une session par opération, refermée après coup (une session garde son délégué tant qu'elle n'est pas invalidée).
    private func avecSession<T>(_ corps: (URLSession) async throws -> T) async rethrows -> T {
        let s = nouvelleSession()
        defer { s.finishTasksAndInvalidate() }
        return try await corps(s)
    }

    private func nouvelleSession() -> URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 20
        c.timeoutIntervalForResource = 600
        c.waitsForConnectivity = false
        c.httpCookieStorage = nil
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: c, delegate: GardeRedirections(politique: politique), delegateQueue: nil)
    }

    private func requete(_ url: URL, accept: String) -> URLRequest {
        var r = URLRequest(url: url)
        r.setValue("Verbe-\(versionActuelle)", forHTTPHeaderField: "User-Agent")
        r.setValue(accept, forHTTPHeaderField: "Accept")
        r.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        return r
    }

    static func estHorsLigne(_ erreur: Error) -> Bool {
        guard let e = erreur as? URLError else { return false }
        switch e.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .timedOut,
             .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed, .secureConnectionFailed, .cannotLoadFromNetwork:
            return true
        default:
            return false
        }
    }

    /// Une seule requête : GET releases/latest.
    func chercher(maintenant: Date = Date()) async -> ResultatRecherche {
        do {
            let (donnees, reponse) = try await avecSession { try await $0.data(for: requete(urlAPI, accept: "application/vnd.github+json")) }
            guard let http = reponse as? HTTPURLResponse else { return .echec("réponse inattendue") }
            var entetes: [String: String] = [:]
            for (k, v) in http.allHeaderFields { if let k = k as? String, let v = v as? String { entetes[k] = v } }
            if let pause = PlanVerification.pasAvant(statut: http.statusCode, enTetes: entetes, maintenant: maintenant) { return .limite(pause) }
            if http.statusCode == 404 { return .aJour }   // aucune release publiée
            guard http.statusCode == 200 else { return .echec("code \(http.statusCode)") }
            guard donnees.count <= Self.tailleMaxJSON else { return .echec("réponse démesurée") }
            switch ChoixMiseAJour.analyser(json: donnees, versionActuelle: versionActuelle, politique: politique) {
            case .proposition(let p): return .proposition(p)
            case .aJour: return .aJour
            case .inutilisable(let raison):
                Log.ecrire("mise à jour : release plus récente inutilisable (\(raison))")
                return .aJour
            case .illisible: return .echec("JSON illisible")
            }
        } catch {
            return Self.estHorsLigne(error) ? .horsLigne : .echec(error.localizedDescription)
        }
    }

    /// Le petit fichier `.sha256` de la release : l'empreinte qu'il donne, `nil` si la release n'en a pas.
    func empreinteDuFichier(_ p: PropositionMiseAJour) async throws -> String? {
        guard let url = p.empreinteURL else { return nil }
        let (donnees, reponse) = try await avecSession { try await $0.data(for: requete(url, accept: "application/octet-stream")) }
        guard (reponse as? HTTPURLResponse)?.statusCode == 200, donnees.count <= 4096,
              let texte = String(data: donnees, encoding: .utf8),
              let e = EmpreinteSHA256.depuisFichier(texte, nomFichier: p.nomDMG) else {
            throw ErreurMiseAJour(message: "L\u{2019}empreinte publiée avec la mise à jour est illisible.", detail: "fichier .sha256 illisible ou inattendu")
        }
        return e
    }

    /// Télécharge le DMG dans `destination`, en vérifiant la taille au fil de l'eau ; renvoie son empreinte SHA-256.
    func telecharger(_ p: PropositionMiseAJour, vers destination: URL, progression: @escaping @Sendable (Double) -> Void) async throws -> String {
        let session = nouvelleSession()
        defer { session.finishTasksAndInvalidate() }
        let (octets, reponse) = try await session.bytes(for: requete(p.dmgURL, accept: "application/octet-stream"))
        guard let http = reponse as? HTTPURLResponse, http.statusCode == 200 else {
            throw ErreurMiseAJour(message: "Le téléchargement n\u{2019}a pas abouti.", detail: "code HTTP \((reponse as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        if let final = http.url, !politique.accepteRedirection(final) {
            throw ErreurMiseAJour(message: "Le téléchargement n\u{2019}a pas abouti.", detail: "adresse finale refusée (\(final.host ?? "?"))")
        }
        guard FileManager.default.createFile(atPath: destination.path, contents: nil, attributes: [.posixPermissions: 0o600]),
              let sortie = try? FileHandle(forWritingTo: destination) else {
            throw ErreurMiseAJour(message: "Verbe n\u{2019}a pas pu écrire le fichier téléchargé.", detail: "création de \(destination.path)")
        }
        defer { try? sortie.close() }
        var calcul = EmpreinteSHA256.Calcul()
        var tampon = Data(); tampon.reserveCapacity(1 << 18)
        var dernierePart = -1.0
        func vider() throws {
            guard !tampon.isEmpty else { return }
            try sortie.write(contentsOf: tampon)
            calcul.ajouter(tampon)
            tampon.removeAll(keepingCapacity: true)
            let part = (Double(calcul.octets) / Double(p.taille) * 100).rounded() / 100
            if part != dernierePart { dernierePart = part; progression(min(1, part)) }
        }
        do {
            for try await octet in octets {
                tampon.append(octet)
                if tampon.count >= 1 << 18 {
                    try vider()
                    if calcul.octets > p.taille { throw ErreurMiseAJour(message: "Le fichier téléchargé est plus gros que prévu.", detail: "plus de \(p.taille) octets reçus") }
                }
            }
            try vider()
        } catch let e as ErreurMiseAJour {
            throw e
        } catch {
            throw ErreurMiseAJour(message: Self.estHorsLigne(error) ? "La connexion s\u{2019}est coupée pendant le téléchargement." : "Le téléchargement n\u{2019}a pas abouti.", detail: error.localizedDescription)
        }
        guard calcul.octets == p.taille else {
            throw ErreurMiseAJour(message: "Le fichier téléchargé est incomplet.", detail: "\(calcul.octets) octets reçus, \(p.taille) annoncés")
        }
        return calcul.resultat()
    }
}
