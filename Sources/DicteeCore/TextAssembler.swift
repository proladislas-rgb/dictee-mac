import Foundation

/// Recolle les textes des morceaux dans l'ordre et filtre ce que Whisper invente sur du silence.
public enum TextAssembler {
    /// Phrases que Whisper « entend » dans le silence ou le bruit (normalisées : minuscules, sans ponctuation).
    private static let phrasesBrutes: [String] = [
        "merci d'avoir regardé cette vidéo",
        "merci d'avoir regardé la vidéo",
        "sous-titres réalisés par la communauté d'amara.org",
        "sous-titres réalisés para la communauté d'amara.org",
        "sous-titrage société radio-canada",
        "sous-titrage st' 501",
        "sous-titrage st'501",
        "thanks for watching",
        "thank you for watching",
        "thanks for watching!",
        "n'oubliez pas de vous abonner",
        "abonnez-vous",
        "transcription d'une dictée en français",
        "transcription of a dictation in english",
    ]
    private static let hallucinations: Set<String> = Set(phrasesBrutes.map(normaliser))

    private static func normaliser(_ s: String) -> String {
        let minuscules = s.lowercased()
        let sansPonctuation = minuscules.unicodeScalars.filter { scalar in
            !CharacterSet(charactersIn: ".,;:!?…\"«»()[]").contains(scalar)
        }
        return String(String.UnicodeScalarView(sansPonctuation))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "  ", with: " ")
    }

    /// Vrai si le texte d'un morceau est vide ou n'est qu'une phrase fantôme de Whisper.
    public static func estFantome(_ texte: String) -> Bool {
        let n = normaliser(texte)
        if n.isEmpty { return true }
        return hallucinations.contains(n)
    }

    /// Un morceau coupé en pleine parole (coupe forcée des longues dictées) finit au milieu d'une phrase : le « . » ou la « , »
    /// que Whisper ajoute à sa fin est retiré. Un « ? » ou un « ! » est gardé (l'intonation peut être réelle).
    public static func sansPonctuationDeCoupe(_ texte: String) -> String {
        var t = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        while let d = t.last, d == "." || d == "," || d == ";" || d == ":" { t.removeLast() }
        // le retrait d'un « … » n'est pas fait : il peut être dit
        return t
    }

    /// Recolle les textes des morceaux (déjà dans l'ordre), en retirant les vides et les phrases fantômes.
    public static func joindre(_ parties: [String?]) -> String {
        let propres = parties.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !estFantome($0) }
        return propres.joined(separator: " ")
    }

    /// Le texte « prompt » envoyé à Whisper : les mots du dictionnaire, puis la fin du texte précédent.
    /// Whisper ne retient que ~224 jetons : on borne à 600 caractères au total, en gardant la fin du contexte.
    public static func prompt(mots: [String], contexte: String?, ancre: String? = nil, limite: Int = 600) -> String {
        let debut = (ancre ?? "").trimmingCharacters(in: .whitespaces)
        var partie1 = mots.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: ", ")
        if !partie1.isEmpty { partie1 += "." }
        var fin = (contexte ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let place = max(0, limite - partie1.count - debut.count - 2)
        if fin.count > place { fin = String(fin.suffix(place)) }
        return [debut, partie1, fin].filter { !$0.isEmpty }.joined(separator: " ")
    }
}
