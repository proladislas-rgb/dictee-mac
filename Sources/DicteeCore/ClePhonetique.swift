import Foundation

/// Clé phonétique « française adaptée » et distances d'édition : de quoi dire que « Brionia » et « Brillonia » se prononcent presque
/// pareil, sans dictionnaire de prononciation. La clé n'est pas une transcription exacte : elle écrase les variantes d'écriture
/// (ph/f, c/k/qu, ll, h muet, lettres finales muettes, voyelles nasales) pour que deux écritures d'un même son se rapprochent.
/// Logique pure, testée.
public enum ClePhonetique {
    /// Minuscules, sans accents, lettres et chiffres seulement (« Éco-Distrib » → « ecodistrib »).
    public static func plier(_ mot: String) -> String {
        var s = ""
        for c in mot.lowercased() {
            if c == "\u{00E7}" { s.append("s"); continue }   // ç se prononce « s » : à traiter avant le retrait des accents
            if c == "\u{00E6}" { s += "ae"; continue }
            if c == "\u{0153}" { s += "oe"; continue }
            s.append(c)
        }
        let sansAccents = s.folding(options: [.diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
        return String(sansAccents.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    private static let voyelles: Set<Character> = ["a", "e", "i", "o", "u", "y"]

    /// La clé phonétique d'un mot (lettres seules : « s », « k », « j », « x » pour le son « ch », « 1 » pour les nasales…).
    public static func cle(_ mot: String) -> String {
        let m = Array(plier(mot))
        guard !m.isEmpty else { return "" }
        func suivant(_ i: Int) -> Character? { i + 1 < m.count ? m[i + 1] : nil }
        var s: [Character] = []
        var i = 0
        while i < m.count {
            let c = m[i]
            let n = suivant(i)
            let n2: Character? = i + 2 < m.count ? m[i + 2] : nil
            func prendre(_ cle: String, _ avance: Int) { s.append(contentsOf: cle); i += avance }
            switch c {
            case "p" where n == "h": prendre("f", 2)
            case "s" where n == "c" && n2 == "h": prendre("x", 3)
            case "s" where n == "h": prendre("x", 2)
            case "c" where n == "h": prendre("x", 2)
            case "g" where n == "n": prendre("n", 2)
            case "q": prendre("k", n == "u" ? 2 : 1)
            case "c" where n == "k": prendre("k", 2)
            case "c": prendre(n.map { "eiy".contains($0) } == true ? "s" : "k", 1)
            case "g" where n == "u" && n2.map({ "eiy".contains($0) }) == true: prendre("g", 2)
            case "g": prendre(n.map { "eiy".contains($0) } == true ? "j" : "g", 1)
            case "w": prendre("v", 1)
            case "y": prendre("i", 1)
            case "h": i += 1
            case "x": prendre("ks", 1)
            case "e" where n == "a" && n2 == "u": prendre("o", 3)
            case "a" where n == "u": prendre("o", 2)
            case "o" where n == "u": prendre("u", 2)
            case "o" where n == "i": prendre("oa", 2)
            case "a" where n == "i", "e" where n == "i": prendre("e", 2)
            case "a" where n == "e", "o" where n == "e": prendre("e", 2)
            case "e" where n == "u", "o" where n == "e": prendre("e", 2)
            case "a", "e", "i", "o", "u":
                // voyelle nasale : voyelle + n/m suivie d'une consonne (ou de la fin du mot), « m » doublé et « nn » exclus
                if let n, n == "n" || n == "m" {
                    let apres: Character? = i + 2 < m.count ? m[i + 2] : nil
                    let nasale = apres == nil || (!voyelles.contains(apres!) && apres != n)
                    if nasale {
                        switch c {
                        case "a", "e": s.append("a")
                        case "o": s.append("o")
                        default: s.append("1")   // in, un, ain, ein
                        }
                        i += 2
                        continue
                    }
                }
                s.append(c == "e" ? "e" : c)
                i += 1
            default: s.append(c); i += 1
            }
        }
        // lettres doubles écrasées
        var sans: [Character] = []
        for c in s where sans.last != c { sans.append(c) }
        // lettres muettes en fin de mot (s, t, x, d, z, e, p, r pour les infinitifs trop courts sont gardés)
        while sans.count > 3, let d = sans.last, "stdze".contains(d) { sans.removeLast() }
        return String(sans)
    }

    /// Distance d'édition de Levenshtein. S'arrête plus tôt (et renvoie `plafond + 1`) quand le résultat dépasserait `plafond`.
    public static func distance(_ a: String, _ b: String, plafond: Int = Int.max) -> Int {
        let x = Array(a), y = Array(b)
        if x == y { return 0 }
        if abs(x.count - y.count) > plafond { return plafond + 1 }
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }
        var precedent = Array(0...y.count)
        var courant = [Int](repeating: 0, count: y.count + 1)
        for i in 1...x.count {
            courant[0] = i
            var minimum = courant[0]
            for j in 1...y.count {
                let cout = x[i - 1] == y[j - 1] ? 0 : 1
                courant[j] = min(precedent[j] + 1, courant[j - 1] + 1, precedent[j - 1] + cout)
                minimum = min(minimum, courant[j])
            }
            if minimum > plafond { return plafond + 1 }
            swap(&precedent, &courant)
        }
        return precedent[y.count]
    }
}
