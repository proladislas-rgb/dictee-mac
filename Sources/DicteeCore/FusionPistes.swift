import Foundation

/// Fusion des deux pistes (micro = « Moi », son du Mac = « Eux ») en une seule transcription, et retrait des échos.
/// Logique pure.
public enum FusionPistes {
    /// Les mots d'un texte, sans accents ni casse ni ponctuation (pour comparer).
    public static func mots(_ texte: String) -> [String] {
        var sortie: [String] = []
        var courant = ""
        for c in Historique.plier(texte) {
            if c.isLetter || c.isNumber { courant.append(c) }
            else if !courant.isEmpty { sortie.append(courant); courant = "" }
        }
        if !courant.isEmpty { sortie.append(courant) }
        return sortie
    }

    /// Part des mots de `a` qu'on retrouve dans `b` (0 à 1).
    static func recouvrement(_ a: String, dans b: String) -> Double {
        let ma = mots(a)
        guard !ma.isEmpty else { return 0 }
        let sb = Set(mots(b))
        return Double(ma.filter { sb.contains($0) }.count) / Double(ma.count)
    }

    /// Découpe un texte en phrases (après « . », « ? », « ! » suivis d'une espace), ponctuation gardée.
    public static func phrases(_ texte: String) -> [String] {
        var sortie: [String] = []
        var courante = ""
        let c = Array(texte)
        for (i, ch) in c.enumerated() {
            courante.append(ch)
            if ".?!".contains(ch), i + 1 >= c.count || c[i + 1] == " " {
                sortie.append(courante.trimmingCharacters(in: .whitespaces)); courante = ""
            }
        }
        let reste = courante.trimmingCharacters(in: .whitespaces)
        if !reste.isEmpty { sortie.append(reste) }
        return sortie
    }

    /// Sans casque, le micro entend aussi les haut-parleurs : la voix des autres se retrouve dans la piste « Moi », mêlée à la
    /// vraie voix dans un même morceau. On compare donc phrase par phrase : une phrase « Moi » qui reprend presque tous ses mots
    /// (`seuil`) d'un passage « Eux » qui chevauche son morceau (à `tolerance` secondes près) est un écho et disparaît ; le reste du
    /// morceau est gardé. La piste « Eux », prise directement dans le Mac, est la propre. Les phrases de moins de 4 mots
    /// (« oui », « d'accord, merci ») sont toujours gardées. `retires` = nombre de phrases retirées.
    public static func retirerEchos(moi: [SegmentReunion], eux: [SegmentReunion], tolerance: Double = 2.0, seuil: Double = 0.8) -> (moi: [SegmentReunion], retires: Int) {
        var gardes: [SegmentReunion] = []
        var retires = 0
        for m in moi {
            let voisins = eux.filter { $0.debut - tolerance < m.fin && m.debut < $0.fin + tolerance }.map(\.texte).joined(separator: " ")
            guard !voisins.isEmpty else { gardes.append(m); continue }
            var restes: [String] = []
            for p in phrases(m.texte) {
                if mots(p).count >= 4, recouvrement(p, dans: voisins) >= seuil { retires += 1 } else { restes.append(p) }
            }
            if restes.isEmpty { continue }
            var s = m
            s.texte = restes.joined(separator: " ")
            gardes.append(s)
        }
        return (gardes, retires)
    }

    /// Une seule suite classée par heure de début ; à heure égale, « Eux » avant « Moi » (celui qui parlait déjà).
    public static func fusionner(moi: [SegmentReunion], eux: [SegmentReunion]) -> [SegmentReunion] {
        (moi + eux).enumerated().sorted { a, b in
            if a.element.debut != b.element.debut { return a.element.debut < b.element.debut }
            if a.element.locuteur != b.element.locuteur { return a.element.locuteur == .eux }
            return a.offset < b.offset
        }.map(\.element)
    }

    /// Recolle les passages consécutifs d'un même locuteur quand le silence entre eux est court (`ecart` secondes) :
    /// une phrase coupée par le découpage redevient un paragraphe.
    public static func regrouper(_ segments: [SegmentReunion], ecart: Double = 3.0) -> [SegmentReunion] {
        var sortie: [SegmentReunion] = []
        for s in segments {
            if var dernier = sortie.last, dernier.locuteur == s.locuteur, s.debut - dernier.fin <= ecart {
                dernier.texte += TextAssembler.separateur(entre: dernier.texte, et: s.texte) + s.texte
                dernier.fin = max(dernier.fin, s.fin)
                sortie[sortie.count - 1] = dernier
            } else {
                sortie.append(s)
            }
        }
        return sortie
    }

    /// Tout d'un coup : échos retirés, fusion, regroupement. Renvoie aussi le nombre d'échos retirés (pour le journal).
    public static func transcription(moi: [SegmentReunion], eux: [SegmentReunion]) -> (segments: [SegmentReunion], echos: Int) {
        let propre = retirerEchos(moi: moi, eux: eux)
        return (regrouper(fusionner(moi: propre.moi, eux: eux)), propre.retires)
    }
}
