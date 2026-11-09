import AppKit

/// Le correcteur orthographique du Mac (NSSpellChecker), en français et en anglais : un mot connu de l'un OU de l'autre est « connu ».
/// Sert à écarter les mots courants du lexique et à ne jamais « corriger » un mot qui existe. Utilisé sur le fil principal.
/// Aucun accès au micro, à la parole ni au clavier.
@MainActor
enum Orthographe {
    private static var langues: [String]?
    private static let balise = NSSpellChecker.uniqueSpellDocumentTag()
    private static var memoire: [String: Bool] = [:]

    private static func languesDisponibles() -> [String] {
        if let l = langues { return l }
        let correcteur = NSSpellChecker.shared
        correcteur.automaticallyIdentifiesLanguages = false
        let dispo = correcteur.availableLanguages
        var choisies: [String] = []
        for prefixe in ["fr", "en"] {
            if let l = dispo.first(where: { $0 == prefixe || $0.hasPrefix(prefixe + "_") || $0.hasPrefix(prefixe + "-") }) { choisies.append(l) }
        }
        langues = choisies
        return choisies
    }

    /// Le correcteur connaît-il ce mot (dans une des deux langues) ? Sans dictionnaire disponible, tout est « connu » (on ne corrige rien).
    static func estConnu(_ mot: String) -> Bool {
        let propre = mot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !propre.isEmpty else { return true }
        if let m = memoire[propre] { return m }
        let langues = languesDisponibles()
        guard !langues.isEmpty else { return true }
        let correcteur = NSSpellChecker.shared
        var connu = false
        for l in langues {
            let plage = correcteur.checkSpelling(of: propre, startingAt: 0, language: l, wrap: false, inSpellDocumentWithTag: balise, wordCount: nil)
            if plage.location == NSNotFound { connu = true; break }
        }
        if memoire.count > 50_000 { memoire.removeAll() }
        memoire[propre] = connu
        return connu
    }

    /// « recoit » pour « reçoit » : une des propositions du correcteur est le même mot avec ses accents.
    static func estFauteDAccents(_ mot: String) -> Bool {
        guard let l = languesDisponibles().first(where: { $0.hasPrefix("fr") }) else { return false }
        func simple(_ t: String) -> String { t.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR")) }
        let propositions = NSSpellChecker.shared.guesses(forWordRange: NSRange(location: 0, length: (mot as NSString).length), in: mot, language: l, inSpellDocumentWithTag: balise) ?? []
        return propositions.contains { $0 != mot && simple($0) == simple(mot) }
    }

    /// Charge les dictionnaires à l'avance (le premier appel coûte une centaine de millisecondes).
    static func prechauffer() { _ = estConnu("bonjour") }
}
