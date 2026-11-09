import Foundation

/// Compte les requêtes envoyées à Groq pour rester sous la limite gratuite (environ 20 par minute, 2 000 par jour pour
/// Whisper). Les requêtes « de confort » (envoi anticipé, requête de secours rapide) ne partent que s'il reste de la
/// marge : la vraie dictée passe toujours en premier. Logique pure : l'horloge est passée en paramètre.
public final class BudgetRequetes: @unchecked Sendable {
    public enum Usage: Sendable {
        /// Envoi anticipé du dernier morceau pendant une pause (peut être jeté).
        case anticipation
        /// Seconde requête identique pour couper la traîne.
        case secours
    }

    public static let partage = BudgetRequetes()

    /// Limite par minute de Groq (20), moins une marge de sécurité.
    public let limiteMinute: Int
    /// Marge à garder pour les vraies requêtes : en dessous, plus d'envoi anticipé / plus de secours.
    private let margeAnticipation: Int
    private let margeSecours: Int
    private let verrou = NSLock()
    private var envois: [Double] = []
    private var restantJour: Int?
    private var pauseJusqua: Double = 0
    private var restantJetons: (valeur: Int, instant: Double)?

    public init(limiteMinute: Int = 18, margeAnticipation: Int = 8, margeSecours: Int = 4) {
        self.limiteMinute = limiteMinute
        self.margeAnticipation = margeAnticipation
        self.margeSecours = margeSecours
    }

    /// Budget de la remise au propre (modèle de langue de Groq : limites plus serrées, surtout en jetons par minute).
    public static let nettoyage = BudgetRequetes(limiteMinute: 10, margeAnticipation: 6, margeSecours: 3)

    public static func maintenant() -> Double { ProcessInfo.processInfo.systemUptime }

    /// À appeler à chaque requête envoyée (même si elle sera annulée : Groq la compte).
    public func noterEnvoi(a maintenant: Double = BudgetRequetes.maintenant()) {
        verrou.lock(); defer { verrou.unlock() }
        envois.append(maintenant)
        elaguer(maintenant)
    }

    /// Nombre de requêtes que la dernière minute permet encore.
    public func restantMinute(a maintenant: Double = BudgetRequetes.maintenant()) -> Int {
        verrou.lock(); defer { verrou.unlock() }
        elaguer(maintenant)
        return limiteMinute - envois.count
    }

    /// Lu dans l'en-tête `x-ratelimit-remaining-requests` de chaque réponse (restant du jour).
    public func noterRestantJour(_ restant: Int?) {
        verrou.lock(); defer { verrou.unlock() }
        if let restant { restantJour = restant }
    }

    /// Lu dans l'en-tête `x-ratelimit-remaining-tokens` (remise au propre : environ 8 000 jetons par minute).
    /// Une valeur de plus de 30 s est ignorée (le compteur se remplit entre-temps).
    public func noterRestantJetons(_ restant: Int?, a maintenant: Double = BudgetRequetes.maintenant()) {
        verrou.lock(); defer { verrou.unlock() }
        if let restant { restantJetons = (restant, maintenant) }
    }

    /// Réponse 429 : plus aucune requête de confort pendant `retryAfter` secondes (au moins 5).
    public func noter429(retryAfter: Double?, a maintenant: Double = BudgetRequetes.maintenant()) {
        verrou.lock(); defer { verrou.unlock() }
        pauseJusqua = maintenant + max(5, retryAfter ?? 20)
    }

    public func enPause(a maintenant: Double = BudgetRequetes.maintenant()) -> Bool {
        verrou.lock(); defer { verrou.unlock() }
        return maintenant < pauseJusqua
    }

    /// Une requête de confort peut-elle partir ?
    public func permet(_ usage: Usage, a maintenant: Double = BudgetRequetes.maintenant()) -> Bool {
        verrou.lock(); defer { verrou.unlock() }
        if maintenant < pauseJusqua { return false }
        elaguer(maintenant)
        let (minuteMini, jourMini): (Int, Int) = {
            switch usage {
            case .anticipation: return (margeAnticipation, 200)   // il faut garder de quoi envoyer les vrais morceaux
            case .secours: return (margeSecours, 60)
            }
        }()
        if limiteMinute - envois.count < minuteMini { return false }
        if let restantJour, restantJour < jourMini { return false }
        if let j = restantJetons, maintenant - j.instant < 30, j.valeur < (usage == .anticipation ? 3500 : 1500) { return false }
        return true
    }

    /// Valeur de `retry-after` (secondes) ou de `x-ratelimit-reset-*` (« 2m52.8s », « 340ms », « 12s »).
    public static func secondes(deEnTete valeur: String?) -> Double? {
        guard var v = valeur?.trimmingCharacters(in: .whitespaces), !v.isEmpty else { return nil }
        if let d = Double(v) { return d }
        var total = 0.0
        var lu = false
        for (suffixe, facteur) in [("h", 3600.0), ("m", 60.0), ("s", 1.0)] {
            // « ms » ne doit pas être pris pour « m » puis « s »
            if suffixe == "m", let r = v.range(of: "ms"), r.upperBound == v.endIndex {
                if let d = Double(v[v.startIndex..<r.lowerBound].split(separator: "h").last.map(String.init) ?? "") { total += d / 1000; lu = true }
                v = ""
                break
            }
            if let r = v.range(of: suffixe) {
                let nombre = String(v[v.startIndex..<r.lowerBound])
                guard let d = Double(nombre) else { return nil }
                total += d * facteur; lu = true
                v = String(v[r.upperBound...])
            }
        }
        return lu ? total : nil
    }

    private func elaguer(_ maintenant: Double) {
        envois.removeAll { maintenant - $0 >= 60 }
    }
}
