import Foundation

/// Ce que fait la touche fn, décidé sans toucher au clavier : la machine reçoit des événements datés
/// et répond par des actions. Toute la logique « tenir / appui court / double appui / annuler » est ici.
public enum FnEvent: Sendable {
    case fnDown
    case fnUp
    /// Une autre touche que fn et Échap a été pressée.
    case otherKey
    case escape
}

public enum GestureAction: Equatable, Sendable {
    /// Commencer à écouter. `handsFree` : mains libres (le double appui).
    case begin(handsFree: Bool)
    /// Finir et écrire le texte.
    case end
    /// Abandonner sans rien écrire.
    case cancel
}

public struct GestureOutcome: Equatable, Sendable {
    public var actions: [GestureAction] = []
    /// Le clavier ne doit pas transmettre cet événement à l'app au premier plan (Échap qui annule).
    public var swallow = false
}

public struct FnGestureDetector: Sendable {
    /// Sous cette durée, fn tenue est un appui court.
    public var shortPress: Double = 0.25
    /// Délai maximal entre la fin du premier appui court et le début du second.
    public var doubleTapWindow: Double = 0.35

    private enum Phase: Equatable {
        case idle
        /// fn est tenue, dictée en cours (mode « tenir »).
        case holding(since: Double)
        /// fn est tenue mais la dictée a été annulée (raccourci clavier, Échap) : on attend le relâchement.
        case ignoringUntilRelease
        /// Mains libres actif ; `fnDown` dit si fn est encore physiquement tenue (le second appui du double appui).
        case handsFree(fnDown: Bool)
        /// Un appui a arrêté le mains libres : on attend son relâchement.
        case stoppingUntilRelease
    }
    private var phase: Phase = .idle
    private var lastShortRelease: Double?

    public init() {}

    /// Codes de touche de fn / 🌐 elle-même (63 = kVK_Function, 179 = 🌐 sur les Mac récents). Quand 🌐 est réglée
    /// sur « Emoji », macOS émet aussi un keyDown/keyUp pour la touche : ce n'est PAS une autre touche, sinon
    /// il casserait le double appui (journal du 09/11 : dictées 15 et 16).
    public static let codesToucheFn: Set<Int64> = [63, 179]
    public static let codeEchap: Int64 = 53

    /// Événement du détecteur pour un keyDown de code `code` ; `nil` si la touche est fn / 🌐 (à ignorer).
    public static func evenement(pourToucheCode code: Int64) -> FnEvent? {
        if codesToucheFn.contains(code) { return nil }
        return code == codeEchap ? .escape : .otherKey
    }

    /// À appeler quand la dictée se termine pour une autre raison (erreur, fin forcée).
    public mutating func reset() { phase = .idle; lastShortRelease = nil }

    public var isActive: Bool {
        switch phase {
        case .holding, .handsFree: return true
        default: return false
        }
    }

    public mutating func handle(_ event: FnEvent, at t: Double) -> GestureOutcome {
        var out = GestureOutcome()
        switch (phase, event) {

        case (.idle, .fnDown):
            if let last = lastShortRelease, t - last <= doubleTapWindow {
                lastShortRelease = nil
                phase = .handsFree(fnDown: true)
                out.actions = [.begin(handsFree: true)]
            } else {
                lastShortRelease = nil
                phase = .holding(since: t)
                out.actions = [.begin(handsFree: false)]
            }

        case (.holding(let since), .fnUp):
            if t - since < shortPress {
                lastShortRelease = t
                phase = .idle
                out.actions = [.cancel]
            } else {
                lastShortRelease = nil
                phase = .idle
                out.actions = [.end]
            }

        case (.holding, .otherKey):
            phase = .ignoringUntilRelease
            lastShortRelease = nil
            out.actions = [.cancel]

        case (.holding, .escape):
            phase = .ignoringUntilRelease
            lastShortRelease = nil
            out.actions = [.cancel]
            out.swallow = true

        case (.ignoringUntilRelease, .fnUp), (.stoppingUntilRelease, .fnUp):
            phase = .idle

        case (.handsFree(fnDown: true), .fnUp):
            phase = .handsFree(fnDown: false)

        case (.handsFree(fnDown: false), .fnDown):
            phase = .stoppingUntilRelease
            out.actions = [.end]

        case (.handsFree(let down), .escape):
            phase = down ? .ignoringUntilRelease : .idle
            out.actions = [.cancel]
            out.swallow = true

        default:
            // Tout le reste ne change rien (autres touches en mains libres, Échap au repos…).
            break
        }
        // Une autre touche pressée après un appui court casse le double appui.
        if event == .otherKey || event == .escape { lastShortRelease = nil }
        return out
    }
}

extension FnEvent: Equatable {}
