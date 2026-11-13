import Foundation
import DicteeCore

extension Notification.Name {
    /// L'usage de Groq a changé (une requête partie, une réponse lue) : l'îlot et les Réglages relisent `UsageGroqStore.partage.etat()`.
    static let verbeUsageGroq = Notification.Name("verbe.usage.groq")
}

/// L'usage de Groq pour la transcription, gardé sur ce Mac : ~/Library/Application Support/Dictee/groq-usage.json (0600). Seulement des
/// heures, des durées, le nom du modèle et ce que les en-têtes de Groq ont dit : jamais de texte ni de son, rien n'est envoyé ailleurs.
/// La logique (comptage, marge, niveau) est dans DicteeCore/UsageGroq.swift.
final class UsageGroqStore: @unchecked Sendable {
    static let partage = UsageGroqStore()

    private let verrou = NSLock()
    private var compteur: CompteurGroq
    private let url: URL?
    private let file = DispatchQueue(label: "verbe.usage.groq", qos: .utility)
    private var ecritureProgrammee = false

    /// Le dossier du fichier : `DICTEE_DOSSIER_USAGE_GROQ` pour un essai (jamais HOME, que FileManager n'honore pas), sinon Application Support.
    static var urlParDefaut: URL? {
        let fm = FileManager.default
        let dir: URL
        if let d = ProcessInfo.processInfo.environment["DICTEE_DOSSIER_USAGE_GROQ"], !d.isEmpty { dir = URL(fileURLWithPath: d, isDirectory: true) }
        else { dir = DossierVerbe.url() }
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("groq-usage.json")
    }

    init(url: URL? = UsageGroqStore.urlParDefaut) {
        self.url = url
        if let url, let d = try? Data(contentsOf: url), let c = CompteurGroq.depuis(d) { compteur = c } else { compteur = CompteurGroq() }
    }

    /// Une requête de transcription part (`secondes` : la durée du son envoyé).
    func noterEnvoi(secondes: Double, modele: ModeleWhisper, a t: Date = Date()) {
        verrou.lock(); compteur.noterEnvoi(secondesAudio: secondes, modele: modele.identifiant, a: t); verrou.unlock()
        changer()
    }

    /// La réponse de Groq : ses en-têtes, et pour une 429 le message d'erreur (lu pour savoir QUELLE limite ; il n'est ni gardé ni journalisé).
    func noterReponse(modele: ModeleWhisper, http: HTTPURLResponse, corps: Data, a t: Date = Date()) {
        var message: String?
        if http.statusCode == 429 {
            message = ((try? JSONSerialization.jsonObject(with: corps) as? [String: Any])?["error"] as? [String: Any])?["message"] as? String
        }
        verrou.lock()
        compteur.noterReponse(modele: modele.identifiant, statut: http.statusCode, entete: { http.value(forHTTPHeaderField: $0) }, messageErreur: message, a: t)
        let cause = compteur.marges[modele.identifiant]?.cause
        verrou.unlock()
        if http.statusCode == 429 { Log.ecrire("usage Groq : \(modele.identifiant) limité (\(cause?.rawValue ?? "?"))") }
        changer()
    }

    /// L'état pour la dictée : le modèle réglé, et le turbo qui prend le relais quand large-v3 est limité (GroqClient.transcrire).
    func etat(modele: ModeleWhisper = Settings.modeleWhisper, a t: Date = Date()) -> EtatGroq {
        verrou.lock(); defer { verrou.unlock() }
        return EtatGroq.calculer(compteur, modele: modele.identifiant, secours: modele == .precis ? ModeleWhisper.rapide.identifiant : nil, a: t)
    }

    private func changer() {
        DispatchQueue.main.async { NotificationCenter.default.post(name: .verbeUsageGroq, object: nil) }
        // une écriture au plus toutes les 2 s (une dictée envoie plusieurs morceaux d'affilée)
        verrou.lock(); let deja = ecritureProgrammee; ecritureProgrammee = true; verrou.unlock()
        guard !deja else { return }
        file.asyncAfter(deadline: .now() + 2) { [weak self] in self?.ecrire() }
    }

    /// Écrit tout de suite (à la fermeture de Verbe).
    func ecrire() {
        verrou.lock()
        ecritureProgrammee = false
        compteur.elaguer(a: Date())
        let d = compteur.donnees()
        verrou.unlock()
        guard let url, let d else { return }
        try? FichierPrive.ecrire(d, vers: url)
    }
}
