import Foundation

/// Ce que l'encoche montre à propos des réunions. Logique pure : toutes les transitions sont ici, l'app ne fait que les appliquer.
public enum PhaseReunion: Equatable, Sendable {
    /// Rien à montrer.
    case repos
    /// L'app d'appel `app` utilise le micro : « Noter cet appel ? » (jamais d'enregistrement sans clic).
    case proposition(app: String)
    case enregistrement(enPause: Bool)
    /// Le son est fini : transcription puis rédaction de la note (en arrière-plan).
    case traitement
    /// « Note prête · Ouvrir ».
    case prete(UUID)
    /// Un message court (« Son du Mac refusé : micro seul »), qui s'efface.
    case message(String)
}

public struct MachineReunion: Equatable, Sendable {
    public private(set) var phase: PhaseReunion = .repos
    /// Une note devenue prête pendant qu'une autre réunion s'enregistrait : annoncée à l'arrêt.
    public private(set) var noteEnAttente: UUID?
    /// Réunions en cours de traitement (transcription / rédaction) : plusieurs peuvent se chevaucher.
    public private(set) var enTraitement = 0

    public init() {}

    public var enregistre: Bool { if case .enregistrement = phase { return true }; return false }
    public var enPause: Bool { phase == .enregistrement(enPause: true) }

    /// Lancer l'enregistrement : impossible pendant un enregistrement déjà en cours.
    @discardableResult
    public mutating func lancer() -> Bool {
        guard !enregistre else { return false }
        phase = .enregistrement(enPause: false)
        return true
    }

    @discardableResult
    public mutating func pause() -> Bool {
        guard phase == .enregistrement(enPause: false) else { return false }
        phase = .enregistrement(enPause: true)
        return true
    }

    @discardableResult
    public mutating func reprendre() -> Bool {
        guard phase == .enregistrement(enPause: true) else { return false }
        phase = .enregistrement(enPause: false)
        return true
    }

    /// Arrêter : la réunion passe au traitement. Faux si rien ne s'enregistrait.
    @discardableResult
    public mutating func arreter() -> Bool {
        guard enregistre else { return false }
        enTraitement += 1
        phase = .traitement
        return true
    }

    /// Un traitement est fini. `note` : l'id de la note prête, nil en cas d'échec ou d'annulation. Pendant un nouvel
    /// enregistrement, l'annonce est mise de côté jusqu'à l'arrêt.
    public mutating func traitementFini(note: UUID?) {
        enTraitement = max(0, enTraitement - 1)
        if enregistre { if let note { noteEnAttente = note }; return }
        if case .proposition = phase { if let note { noteEnAttente = note }; return }
        if let note { phase = .prete(note) } else if enTraitement == 0 { phase = .repos }
    }

    /// Propose de noter l'appel : seulement quand rien d'autre n'occupe l'encoche.
    @discardableResult
    public mutating func proposer(app: String) -> Bool {
        switch phase {
        case .repos, .message: phase = .proposition(app: app); return true
        default: return false
        }
    }

    /// « Non » ou délai écoulé : la proposition disparaît. Rend l'encoche à ce qu'elle montrait.
    public mutating func refuserProposition() {
        guard case .proposition = phase else { return }
        phase = enTraitement > 0 ? .traitement : (noteEnAttente.map { PhaseReunion.prete($0) } ?? .repos)
        if case .prete = phase { noteEnAttente = nil }
    }

    /// Un message court ; seulement quand rien d'important n'est affiché.
    public mutating func message(_ texte: String) {
        switch phase {
        case .repos, .proposition, .message: phase = .message(texte)
        default: break
        }
    }

    /// L'encoche est refermée (clic sur Ouvrir, délai, message expiré). Si une note attendait, elle est annoncée.
    public mutating func acquitter() {
        if enregistre { return }
        if let id = noteEnAttente { noteEnAttente = nil; phase = .prete(id); return }
        phase = enTraitement > 0 ? .traitement : .repos
    }

    /// À l'arrêt, une note qui attendait est annoncée à la place du traitement en cours.
    public mutating func annoncerNoteEnAttente() {
        if !enregistre, let id = noteEnAttente { noteEnAttente = nil; phase = .prete(id) }
    }
}

/// L'horloge d'une réunion : les secondes enregistrées, pauses déduites. Sûre entre les fils (les pistes la lisent depuis le fil audio).
public final class HorlogeReunion: @unchecked Sendable {
    private let verrou = NSLock()
    private let debut: Double
    private var pauseDepuis: Double?
    private var pauseTotale = 0.0

    public init(maintenant: Double = BudgetRequetes.maintenant()) { debut = maintenant }

    public func temps(a maintenant: Double = BudgetRequetes.maintenant()) -> Double {
        verrou.lock(); defer { verrou.unlock() }
        return max(0, (pauseDepuis ?? maintenant) - debut - pauseTotale)
    }

    public func pause(a maintenant: Double = BudgetRequetes.maintenant()) {
        verrou.lock(); defer { verrou.unlock() }
        if pauseDepuis == nil { pauseDepuis = maintenant }
    }

    public func reprendre(a maintenant: Double = BudgetRequetes.maintenant()) {
        verrou.lock(); defer { verrou.unlock() }
        if let p = pauseDepuis { pauseTotale += maintenant - p; pauseDepuis = nil }
    }
}
