import Foundation

/// Garde-fou contre les mots collés : la remise au propre (petite IA) peut écrire « àplus tard » ou « àplustard » alors que la
/// transcription disait « à plus tard ». Un mot de la sortie qui n'existe pas dans l'entrée mais qui est exactement la
/// concaténation de 2 à 4 mots consécutifs de l'entrée est remis en mots séparés. Logique pure, vérifiée par `DicteeControles`.
public enum MotsColles {
    /// Mots qui s'écrivent vraiment d'un bloc même si Whisper les avait séparés.
    private static let legitimes: Set<String> = ["pourquoi", "parceque", "afin", "bientot", "autrefois", "toutefois", "cependant", "puisque", "lorsque", "quoique"]

    private static func plier(_ s: String) -> String {
        s.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "fr_FR")).replacingOccurrences(of: "\u{2019}", with: "'")
    }

    private static func estCaractereDeMot(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "'" || c == "\u{2019}" }

    /// Mots (lettres, chiffres, apostrophes) d'un texte, avec leur plage.
    private static func mots(_ texte: String) -> [(mot: String, plage: Range<String.Index>)] {
        var sortie: [(String, Range<String.Index>)] = []
        var i = texte.startIndex
        while i < texte.endIndex {
            if estCaractereDeMot(texte[i]) {
                var j = i
                while j < texte.endIndex, estCaractereDeMot(texte[j]) { j = texte.index(after: j) }
                sortie.append((String(texte[i..<j]), i..<j))
                i = j
            } else { i = texte.index(after: i) }
        }
        return sortie
    }

    /// Les mots d'`entree` consécutifs dont la concaténation (pliée) vaut `colle`, ou `nil`.
    private static func decomposer(_ colle: String, entree: [String], depuis: Int = 0, profondeur: Int = 4) -> [String]? {
        guard profondeur > 0 else { return nil }
        for debut in 0..<entree.count {
            var cumul = ""
            var pieces: [String] = []
            for k in debut..<min(entree.count, debut + profondeur) {
                cumul += plier(entree[k])
                pieces.append(entree[k])
                if cumul == colle { return pieces.count >= 2 ? pieces : nil }
                if !colle.hasPrefix(cumul) { break }
            }
        }
        return nil
    }

    /// Remet en mots séparés les mots de `sortie` qui sont des mots de `entree` collés. Renvoie le texte et les mots réparés.
    public static func reparer(entree: String, sortie: String) -> (texte: String, repares: [String]) {
        let motsEntree = mots(entree).map(\.mot)
        let connus = Set(motsEntree.map(plier))
        var texte = sortie
        var repares: [String] = []
        // de la fin vers le début : les plages restent valides
        for (mot, plage) in mots(sortie).reversed() {
            let cle = plier(mot)
            guard cle.count >= 4, !connus.contains(cle), !legitimes.contains(cle), cle.allSatisfy({ $0.isLetter || $0 == "'" }) else { continue }
            guard var pieces = decomposer(cle, entree: motsEntree) else { continue }
            if mot.first?.isUppercase == true, let p = pieces.first { pieces[0] = p.prefix(1).uppercased() + p.dropFirst() }
            else if mot.first?.isLowercase == true, let p = pieces.first { pieces[0] = p.prefix(1).lowercased() + p.dropFirst() }
            texte.replaceSubrange(plage, with: pieces.joined(separator: " "))
            repares.append(mot)
        }
        return (texte, repares.reversed())
    }
}

/// Ligne de journal « texte Groq → texte final » : seulement quand les deux diffèrent autrement que par la ponctuation
/// (ou la casse), avec 60 caractères au plus de chaque côté, centrés sur la première différence.
public enum ComparaisonJournal {
    public static let limite = 60

    private static func normaliser(_ t: String) -> [(c: Character, brut: String.Index)] {
        var sortie: [(Character, String.Index)] = []
        for i in t.indices {
            let c = t[i]
            if c.isLetter || c.isNumber {
                for l in String(c).lowercased() { sortie.append((l, i)) }
            } else if sortie.last?.0 != " " && !sortie.isEmpty {
                sortie.append((" ", i))
            }
        }
        while sortie.last?.0 == " " { sortie.removeLast() }
        return sortie
    }

    private static func fenetre(_ t: String, autour i: String.Index?, limite: Int) -> String {
        let plat = t.replacingOccurrences(of: "\n", with: " ")
        guard plat.count > limite else { return plat }
        let offset = i.map { min(t.distance(from: t.startIndex, to: $0), plat.count) } ?? 0
        let debut = max(0, min(offset - limite / 3, plat.count - limite))
        let a = plat.index(plat.startIndex, offsetBy: debut), b = plat.index(a, offsetBy: limite)
        return (debut > 0 ? "…" : "") + plat[a..<b] + (b < plat.endIndex ? "…" : "")
    }

    /// `nil` quand rien ne diffère en dehors de la ponctuation et de la casse.
    public static func ligne(groq: String, final: String) -> String? {
        let a = normaliser(groq), b = normaliser(final)
        var k = 0
        while k < a.count, k < b.count, a[k].c == b[k].c { k += 1 }
        if k == a.count && k == b.count { return nil }
        let ia = k < a.count ? a[k].brut : nil, ib = k < b.count ? b[k].brut : nil
        return "texte Groq \u{2192} final : \"\(fenetre(groq, autour: ia, limite: limite))\" \u{2192} \"\(fenetre(final, autour: ib, limite: limite))\""
    }
}
