import Foundation

/// Choix de la langue de la dictée. Whisper détecte mal la langue des phrases très courtes (« Est-ce que ça marche ? » est devenu
/// de l'allemand) : le réglage par défaut est donc « Français » (langue envoyée à Groq). En mode Automatique, une langue détectée
/// hors de la liste de l'utilisateur est refusée et le morceau est relancé dans la première langue de la liste. Logique pure.
public enum ChoixLangue {
    public static let defaut = "fr"
    public static let automatique = "auto"
    public static let autoriseesParDefaut = ["fr", "en"]

    /// Réglage enregistré (`fr`, `en`, `auto`, ou rien) → langue envoyée à Whisper (`nil` = détection automatique).
    public static func parametre(reglage: String?) -> String? {
        guard let r = reglage?.trimmingCharacters(in: .whitespaces).lowercased(), !r.isEmpty else { return defaut }
        return r == automatique ? nil : r
    }

    private static let noms: [String: String] = [
        "french": "fr", "english": "en", "german": "de", "spanish": "es", "italian": "it", "portuguese": "pt", "dutch": "nl",
        "arabic": "ar", "russian": "ru", "chinese": "zh", "japanese": "ja", "korean": "ko", "turkish": "tr", "polish": "pl",
        "swedish": "sv", "norwegian": "no", "danish": "da", "finnish": "fi", "greek": "el", "hebrew": "he", "hindi": "hi",
        "ukrainian": "uk", "czech": "cs", "romanian": "ro", "hungarian": "hu", "catalan": "ca", "latin": "la", "welsh": "cy",
    ]

    /// Nom de langue donné par Groq (« French ») → code (« fr »). Un code déjà court est gardé.
    public static func code(nom: String?) -> String? {
        guard let n = nom?.trimmingCharacters(in: .whitespaces).lowercased(), !n.isEmpty else { return nil }
        if let c = noms[n] { return c }
        return n.count <= 3 ? n : nil
    }

    /// La langue détectée est-elle acceptable ? Rien de détecté (réponse sans langue) : on accepte. Langue inconnue : on refuse.
    public static func accepter(nomDetecte: String?, autorisees: [String]) -> Bool {
        guard let nom = nomDetecte, !nom.trimmingCharacters(in: .whitespaces).isEmpty else { return true }
        guard let code = code(nom: nom) else { return false }
        return autorisees.contains(code)
    }

    /// Courte phrase placée au début du prompt de Whisper : elle ancre la langue. Aucune en détection automatique.
    public static func phraseAncre(langue: String?) -> String? {
        switch langue {
        case "fr": return "Transcription d'une dictée en français."
        case "en": return "Transcription of a dictation in English."
        default: return nil
        }
    }
}
