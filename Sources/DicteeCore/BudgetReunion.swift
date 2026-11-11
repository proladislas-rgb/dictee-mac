import Foundation

/// Quota d'audio de Groq pour Whisper : environ 7 200 secondes d'audio par heure (glissante). Chaque requête est comptée
/// au moins 10 secondes. La réunion n'a le droit d'en prendre qu'une partie : le reste est gardé pour la dictée (touche fn).
/// Logique pure : l'horloge est passée en paramètre.
public final class BudgetAudio: @unchecked Sendable {
    public static let partage = BudgetAudio()
    /// Le quota d'audio de whisper-large-v3 (« Précis ») : compté à part chez Groq. La relecture d'après l'appel s'en sert.
    public static let precis = BudgetAudio()

    public let limiteHeure: Double
    /// Part de l'heure réservée à la dictée : la réunion n'y touche jamais.
    public let reserveDictee: Double
    private let verrou = NSLock()
    private var envois: [(instant: Double, secondes: Double)] = []

    public init(limiteHeure: Double = 7200, reserveDictee: Double = 1500) {
        self.limiteHeure = limiteHeure; self.reserveDictee = reserveDictee
    }

    /// Ce que Groq compte pour un morceau : au moins 10 secondes.
    public static func facture(duree: Double) -> Double { max(10, duree) }

    public func noter(duree: Double, a maintenant: Double = BudgetRequetes.maintenant()) {
        verrou.lock(); defer { verrou.unlock() }
        envois.append((maintenant, Self.facture(duree: duree)))
        elaguer(maintenant)
    }

    private func elaguer(_ maintenant: Double) { envois.removeAll { maintenant - $0.instant >= 3600 } }

    public func utilise(a maintenant: Double = BudgetRequetes.maintenant()) -> Double {
        verrou.lock(); defer { verrou.unlock() }
        elaguer(maintenant)
        return envois.reduce(0) { $0 + $1.secondes }
    }

    /// Secondes d'audio que la réunion peut encore envoyer cette heure.
    public func restantPourReunion(a maintenant: Double = BudgetRequetes.maintenant()) -> Double {
        max(0, limiteHeure - reserveDictee - utilise(a: maintenant))
    }

    /// Secondes à attendre avant de pouvoir envoyer `duree` secondes d'audio : 0 si c'est possible tout de suite.
    public func delaiAvant(duree: Double, a maintenant: Double = BudgetRequetes.maintenant()) -> Double {
        verrou.lock(); defer { verrou.unlock() }
        elaguer(maintenant)
        let besoin = Self.facture(duree: duree)
        let plafond = limiteHeure - reserveDictee
        var total = envois.reduce(0) { $0 + $1.secondes }
        if total + besoin <= plafond { return 0 }
        // On laisse vieillir les envois les plus anciens jusqu'à ce que la place soit faite.
        for e in envois.sorted(by: { $0.instant < $1.instant }) {
            total -= e.secondes
            if total + besoin <= plafond { return max(0, e.instant + 3600 - maintenant) }
        }
        return max(0, (envois.map(\.instant).max() ?? maintenant) + 3600 - maintenant)
    }
}

/// Jetons de la rédaction de la note : le modèle de langue de Groq plafonne à environ 8 000 jetons par minute
/// (entrée + sortie). La note d'une longue réunion se fait par parties, espacées pour rester sous ce plafond.
public final class BudgetJetons: @unchecked Sendable {
    public let limiteMinute: Int
    private let verrou = NSLock()
    private var usages: [(instant: Double, jetons: Int)] = []

    public init(limiteMinute: Int = 8000) { self.limiteMinute = limiteMinute }

    public func noter(jetons: Int, a maintenant: Double = BudgetRequetes.maintenant()) {
        verrou.lock(); defer { verrou.unlock() }
        usages.append((maintenant, jetons))
        usages.removeAll { maintenant - $0.instant >= 60 }
    }

    /// Secondes à attendre avant d'envoyer une requête de `jetons` jetons (0 : tout de suite). On garde 10 % de marge.
    public func delaiAvant(jetons: Int, a maintenant: Double = BudgetRequetes.maintenant()) -> Double {
        verrou.lock(); defer { verrou.unlock() }
        usages.removeAll { maintenant - $0.instant >= 60 }
        let plafond = Int(Double(limiteMinute) * 0.9)
        var total = usages.reduce(0) { $0 + $1.jetons }
        if total + jetons <= plafond || usages.isEmpty { return 0 }
        for u in usages.sorted(by: { $0.instant < $1.instant }) {
            total -= u.jetons
            if total + jetons <= plafond { return max(0, u.instant + 60 - maintenant) }
        }
        return max(0, (usages.map(\.instant).max() ?? maintenant) + 60 - maintenant)
    }
}
