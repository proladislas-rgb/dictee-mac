import Foundation

/// Apprendre des corrections : quelques secondes après un collage, l'app relit le champ (Accessibilité) et compare avec ce qu'elle
/// venait d'écrire. Si Hugues a remplacé un mot par un autre qui lui ressemble (« Brionia » → « Brillonia »), le mot corrigé est
/// proposé dans « Mots » — jamais ajouté sans son accord. Logique pure.
public enum ApprentissageCorrections {
    public struct Remplacement: Equatable, Sendable {
        public let ancien: String
        public let nouveau: String
        public init(ancien: String, nouveau: String) { self.ancien = ancien; self.nouveau = nouveau }
    }

    /// Les mots d'un texte, tels qu'écrits (lettres, chiffres, trait d'union et apostrophe intérieurs).
    public static func mots(_ texte: String) -> [String] {
        var sortie: [String] = []
        var courant = ""
        for c in texte + " " {
            if c.isLetter || c.isNumber || ((c == "-" || c == "'" || c == "\u{2019}") && !courant.isEmpty) { courant.append(c) }
            else if !courant.isEmpty { sortie.append(sansElision(courant)); courant = "" }
        }
        return sortie.filter { !$0.isEmpty }
    }

    /// « d'Ecoverdix » → « Ecoverdix » (l'élision n'est pas le mot).
    static func sansElision(_ mot: String) -> String {
        var m = mot
        if let k = m.firstIndex(where: { $0 == "'" || $0 == "\u{2019}" }) {
            let avant = m[m.startIndex..<k].lowercased()
            if avant.count <= 2 || ExtractionLexique.elisions.contains(avant) { m = String(m[m.index(after: k)...]) }
        }
        return m.trimmingCharacters(in: CharacterSet(charactersIn: "-'\u{2019}"))
    }

    /// Longueur de la plus longue suite commune de deux listes de mots, avec la correspondance (indices appariés).
    static func appariement(_ a: [String], _ b: [String]) -> [(Int, Int)] {
        let n = a.count, m = b.count
        guard n > 0, m > 0 else { return [] }
        var t = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                t[i][j] = a[i] == b[j] ? t[i + 1][j + 1] + 1 : max(t[i + 1][j], t[i][j + 1])
            }
        }
        var paires: [(Int, Int)] = []
        var i = 0, j = 0
        while i < n, j < m {
            if a[i] == b[j] { paires.append((i, j)); i += 1; j += 1 }
            else if t[i + 1][j] >= t[i][j + 1] { i += 1 } else { j += 1 }
        }
        return paires
    }

    /// Ressemblance suffisante pour dire « c'est le même mot, corrigé » (et non une phrase réécrite).
    static func ressemblent(_ ancien: String, _ nouveau: String) -> Bool {
        let a = ClePhonetique.plier(ancien), b = ClePhonetique.plier(nouveau)
        guard !a.isEmpty, !b.isEmpty else { return false }
        let ecart = ClePhonetique.distance(a, b, plafond: 4)
        let longueur = max(a.count, b.count)
        if ecart <= max(1, min(3, longueur / 3)) { return true }
        return ClePhonetique.distance(ClePhonetique.cle(ancien), ClePhonetique.cle(nouveau), plafond: 2) <= (longueur >= 7 ? 2 : 1) && ecart <= 4
    }

    /// Les mots remplacés par Hugues entre deux lectures du champ.
    /// - `inseree` : le texte que l'app a écrit ; seuls ses mots peuvent avoir été corrigés.
    /// - `avant` : lecture du champ juste après le collage ; `apres` : lecture quelques secondes plus tard (même zone).
    public static func remplacements(inseree: String, avant: String, apres: String) -> [Remplacement] {
        let a = mots(avant), b = mots(apres)
        guard a.count >= 2, !b.isEmpty else { return [] }
        let paires = appariement(a, b)
        // le champ doit être resté le même : sinon Hugues est ailleurs, on n'apprend rien
        guard Double(paires.count) / Double(a.count) >= 0.7 else { return [] }
        let dansLInseree = Set(mots(inseree).map { ClePhonetique.plier($0) })
        let zoneFinale = a.count - 1   // le dernier mot de la zone lue peut être coupé en deux : on l'ignore
        var sortie: [Remplacement] = []
        var ia = 0, ib = 0
        for (pa, pb) in paires + [(a.count, b.count)] {
            let vieux = Array(a[ia..<pa]), neufs = Array(b[ib..<pb])
            defer { ia = pa + 1; ib = pb + 1 }
            guard (1...3).contains(vieux.count), (1...3).contains(neufs.count) else { continue }
            guard pa <= zoneFinale else { continue }
            guard vieux.allSatisfy({ dansLInseree.contains(ClePhonetique.plier($0)) }) else { continue }
            let ancien = vieux.joined(separator: " "), nouveau = neufs.joined(separator: " ")
            guard ressemblent(ancien, nouveau) else { continue }
            sortie.append(Remplacement(ancien: ancien, nouveau: nouveau))
        }
        return sortie
    }

    /// Les mots à proposer dans « Mots » : le nouveau mot (ou les nouveaux mots, « Prime Zorba ») des remplacements dont au moins un mot
    /// est inconnu du correcteur orthographique, d'au moins 4 lettres.
    public static func propositions(inseree: String, avant: String, apres: String, estConnu: (String) -> Bool) -> [String] {
        var sortie: [String] = []
        for r in remplacements(inseree: inseree, avant: avant, apres: apres) {
            let c = r.nouveau
            guard c != r.ancien, ClePhonetique.plier(c).count >= 4 else { continue }
            guard mots(c).contains(where: { !estConnu($0) }) else { continue }
            if !sortie.contains(c) { sortie.append(c) }
        }
        return sortie
    }
}
