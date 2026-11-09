import Foundation

/// Ce qu'on sait du moment de la dictée pour deviner quels mots du lexique comptent.
public struct ContexteMots: Sendable {
    public var genre: AppKind
    public var titreFenetre: String?
    /// Texte avant le curseur, lu par l'Accessibilité quand l'app l'expose.
    public var texteAutour: String?
    /// Textes des dictées récentes (la plus récente d'abord).
    public var recents: [String]
    /// Ce qui vient d'être dicté dans la même dictée (morceaux précédents).
    public var dejaDicte: String?

    public init(genre: AppKind = .other, titreFenetre: String? = nil, texteAutour: String? = nil, recents: [String] = [], dejaDicte: String? = nil) {
        self.genre = genre; self.titreFenetre = titreFenetre; self.texteAutour = texteAutour; self.recents = recents; self.dejaDicte = dejaDicte
    }
}

/// Choisit, à chaque dictée, les mots à glisser dans le champ `prompt` de Whisper (limité à ~224 jetons) : d'abord ceux que Hugues a
/// choisis (mots.txt), puis les mots du lexique les plus probables d'après l'app, le titre de la fenêtre, le texte autour du curseur
/// et les dictées récentes. Logique pure.
public enum ChoixMotsPrompt {
    /// Budget total du prompt, en jetons estimés (Whisper en lit 224 au plus, en gardant la FIN : rester en dessous évite que le
    /// début — l'ancre de langue et les mots — soit coupé).
    public static let budgetParDefaut = 200

    /// Estimation prudente du nombre de jetons d'un texte (les mots rares en coûtent plus : ~2,3 caractères par jeton).
    public static func jetons(_ texte: String) -> Int {
        texte.split(whereSeparator: { $0.isWhitespace }).reduce(0) { $0 + max(1, Int((Double($1.count) / 2.3).rounded(.up))) + 1 }
    }

    /// Le mot dans un prompt : « mot, » = jetons du mot + la virgule.
    static func coutDuMot(_ mot: String) -> Int { max(1, Int((Double(mot.count + 1) / 2.3).rounded(.up))) + 1 }

    private static func mots(de texte: String?) -> [String] {
        guard let texte, !texte.isEmpty else { return [] }
        var sortie: [String] = []
        var courant = ""
        for c in texte + " " {
            if c.isLetter || c.isNumber || ((c == "-" || c == "'" || c == "\u{2019}") && !courant.isEmpty) { courant.append(c) }
            else if !courant.isEmpty { sortie.append(ClePhonetique.plier(ApprentissageCorrections.sansElision(courant))); courant = "" }
        }
        return sortie.filter { $0.count >= 3 }
    }

    /// Mots du lexique classés du plus au moins probable pour ce contexte (sans ceux de `exclus`).
    public static func classer(lexique: [EntreeLexique], contexte: ContexteMots, exclus: [String] = []) -> [EntreeLexique] {
        notes(lexique: lexique, contexte: contexte, exclus: exclus).map(\.0)
    }

    /// Les mots classés, avec « cité par le contexte » : titre de la fenêtre, texte autour du curseur, dictée en cours ou dictées récentes.
    static func notes(lexique: [EntreeLexique], contexte: ContexteMots, exclus: [String]) -> [(EntreeLexique, Bool)] {
        let exclusPlies = Set(exclus.map(ClePhonetique.plier))
        let titre = Set(mots(de: contexte.titreFenetre))
        let page = Set(mots(de: contexte.texteAutour) + mots(de: contexte.dejaDicte))
        var recents: [String: Double] = [:]
        for (rang, texte) in contexte.recents.prefix(20).enumerated() {
            let poids = rang < 5 ? 1.0 : 0.6
            for m in Set(mots(de: texte)) { recents[m, default: 0] += poids }
        }
        func lie(_ plie: String, a ensemble: Set<String>) -> Bool {
            if ensemble.contains(plie) { return true }
            guard plie.count >= 6 else { return false }
            let racine = String(plie.prefix(max(5, plie.count - 2)))
            return ensemble.contains { $0.hasPrefix(racine) && abs($0.count - plie.count) <= 2 }
        }
        // premier tour : les mots cités par le titre ou la page ; leurs « voisins » (même source) sont un peu favorisés
        var sourcesCitees = Set<String>()
        var citations: [Int: Double] = [:]
        let plies = lexique.map { ClePhonetique.plier($0.mot) }
        for (i, e) in lexique.enumerated() where !exclusPlies.contains(plies[i]) {
            var bonus = 0.0
            if lie(plies[i], a: page) { bonus += 14 }
            if lie(plies[i], a: titre) { bonus += 12 }
            if bonus > 0 { citations[i] = bonus; sourcesCitees.insert(e.source) }
        }
        var notes: [(EntreeLexique, Double, Bool)] = []
        for (i, e) in lexique.enumerated() where !exclusPlies.contains(plies[i]) {
            var note = log(1 + Double(e.frequence)) + 0.5 * log(1 + Double(e.documents))
            note += citations[i] ?? 0
            var cite = citations[i] != nil
            if let r = recents[plies[i]] { note += 8 * min(r, 1.5); cite = true }
            if citations[i] == nil, sourcesCitees.contains(e.source) { note += 1.5 }
            switch contexte.genre {
            case .terminal: note += e.type == .technique ? 1.5 : (e.type == .sigle ? 0.5 : -0.5)
            case .browser: break
            case .other: note += e.type == .nom ? 1 : 0
            }
            notes.append((e, note, cite))
        }
        notes.sort { $0.1 != $1.1 ? $0.1 > $1.1 : ($0.0.frequence != $1.0.frequence ? $0.0.frequence > $1.0.frequence : $0.0.mot < $1.0.mot) }
        return notes.map { ($0.0, $0.2) }
    }

    /// Le texte du prompt : ancre de langue, mots (mots.txt d'abord, puis le lexique), fin du texte précédent.
    /// Le total reste sous `budget` jetons estimés ; le texte précédent garde toujours un peu de place (continuité de la ponctuation).
    /// Part du budget réservée aux expressions de Hugues (« t'inquiète, on se capte ») : assez pour que Whisper reconnaisse son style, pas plus.
    public static let budgetExpressions = 45

    public static func prompt(motsChoisis: [String], expressions: [String] = [], lexique: [EntreeLexique], contexte: ContexteMots, texteDavant: String?,
                              ancre: String?, budget: Int = budgetParDefaut, maxMots: Int = 60, maxGeneraux: Int = 10, maxSiglesGeneraux: Int = 2) -> String {
        let debut = (ancre ?? "").trimmingCharacters(in: .whitespaces)
        var fin = (texteDavant ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if fin.count > 400 { fin = String(fin.suffix(400)) }
        let coutAncre = debut.isEmpty ? 0 : jetons(debut)
        let reserveFin = min(jetons(fin), 45)
        var place = budget - coutAncre - reserveFin - 2
        var retenus: [String] = []
        var vus = Set<String>()
        func essayer(_ mot: String) -> Bool {
            let m = mot.trimmingCharacters(in: .whitespaces)
            let p = ClePhonetique.plier(m)
            guard !m.isEmpty, !p.isEmpty, !vus.contains(p) else { return true }
            let cout = coutDuMot(m)
            guard cout <= place, retenus.count < maxMots else { return false }
            retenus.append(m); vus.insert(p); place -= cout
            return true
        }
        for m in motsChoisis { if !essayer(m) { break } }
        // Les expressions de Hugues juste après ses mots : dans leur propre budget de jetons, jamais au détriment de l'ancre ni du texte précédent.
        var placeExpressions = min(budgetExpressions, max(0, place - 40))
        for e in expressions {
            let cout = coutDuMot(e.trimmingCharacters(in: .whitespaces))
            guard cout <= placeExpressions, cout <= place, retenus.count < maxMots else { continue }
            let avant = retenus.count
            _ = essayer(e)
            if retenus.count > avant { placeExpressions -= cout }
        }
        // Sans rien qui désigne un mot (ni titre, ni texte, ni historique), une longue liste de mots rares ne fait pas mieux et peut nuire
        // (Whisper en imite le style : capitales partout si beaucoup de sigles). On garde donc : les mots cités par le contexte (jusqu'à
        // `maxMots`), puis quelques mots parmi les plus fréquents, dont très peu de sigles.
        var generaux = 0, sigles = 0
        for (e, cite) in notes(lexique: lexique, contexte: contexte, exclus: motsChoisis) {
            if retenus.count >= maxMots || place <= 2 { break }
            if !cite {
                if generaux >= maxGeneraux { continue }
                if e.type == .sigle, sigles >= maxSiglesGeneraux { continue }
            }
            let avant = retenus.count
            _ = essayer(e.mot)   // un mot trop long est sauté : un plus court peut encore tenir
            if !cite, retenus.count > avant { generaux += 1; if e.type == .sigle { sigles += 1 } }
        }
        var partieMots = retenus.joined(separator: ", ")
        if !partieMots.isEmpty { partieMots += "." }
        // ce qui reste du budget va au texte précédent (sa fin, coupée entre deux mots)
        let reste = budget - coutAncre - jetons(partieMots) - 1
        if jetons(fin) > reste {
            var morceaux = fin.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            while !morceaux.isEmpty, jetons(morceaux.joined(separator: " ")) > max(0, reste) { morceaux.removeFirst() }
            fin = morceaux.joined(separator: " ")
        }
        return [debut, partieMots, fin].filter { !$0.isEmpty }.joined(separator: " ")
    }
}
