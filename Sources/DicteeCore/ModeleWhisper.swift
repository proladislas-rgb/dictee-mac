import Foundation

/// Le modèle de transcription de Groq (réglage « Vitesse de transcription »). Logique pure.
/// - `rapide` : whisper-large-v3-turbo, le plus rapide.
/// - `precis` : whisper-large-v3, plus juste sur les mots familiers et les noms, un peu plus lent.
/// Chaque modèle a ses propres limites gratuites chez Groq (comptées à part) : un budget de requêtes par modèle.
public enum ModeleWhisper: String, CaseIterable, Sendable {
    case rapide
    case precis

    /// Défaut retenu le 10/11 : large-v3 (mots justes 91,9 % contre 86,2 % pour le turbo, latence dans le bruit, quota gratuit à part). Voir docs/spec-v1.md.
    public static let parDefaut: ModeleWhisper = .precis

    /// Identifiant envoyé à Groq.
    public var identifiant: String { self == .rapide ? "whisper-large-v3-turbo" : "whisper-large-v3" }
    public var libelle: String { self == .rapide ? "Rapide (turbo)" : "Précis (large-v3)" }
    public var phrase: String { self == .rapide ? "Le plus rapide." : "Un peu plus lent, plus juste." }

    /// Lit un réglage (`rapide`, `precis`, ou l'identifiant Groq) ; nil si inconnu.
    public static func depuis(reglage: String?) -> ModeleWhisper? {
        switch reglage?.trimmingCharacters(in: .whitespaces).lowercased() {
        case "rapide", "turbo", "whisper-large-v3-turbo": return .rapide
        case "precis", "précis", "large-v3", "large", "whisper-large-v3": return .precis
        default: return nil
        }
    }

    /// Le modèle de secours quand celui-ci est limité ou en panne : l'autre (ses limites sont comptées à part).
    public var secours: ModeleWhisper { self == .rapide ? .precis : .rapide }

    /// Le modèle de la requête de secours (celle qui court en parallèle quand la réponse tarde) : toujours le turbo, le plus rapide.
    public var secoursRapide: ModeleWhisper { .rapide }
}
