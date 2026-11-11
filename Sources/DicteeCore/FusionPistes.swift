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

    /// Recolle les passages consécutifs d'un même orateur quand le silence entre eux est court (`ecart` secondes) :
    /// une phrase coupée par le découpage redevient un paragraphe. `dureeMax` : un tour plus long est laissé en plusieurs lignes
    /// (la transcription relue montre l'heure à chaque nouvelle minute, un monologue de cinq minutes n'y fait pas une seule ligne).
    public static func regrouper(_ segments: [SegmentReunion], ecart: Double = 3.0, dureeMax: Double = .infinity) -> [SegmentReunion] {
        var sortie: [SegmentReunion] = []
        for s in segments {
            if var dernier = sortie.last, dernier.locuteur == s.locuteur, dernier.idOrateur == s.idOrateur, s.debut - dernier.fin <= ecart,
               max(dernier.fin, s.fin) - dernier.debut <= dureeMax {
                dernier.texte += TextAssembler.separateur(entre: dernier.texte, et: s.texte) + s.texte
                dernier.fin = max(dernier.fin, s.fin)
                sortie[sortie.count - 1] = dernier
            } else {
                sortie.append(s)
            }
        }
        return sortie
    }

    /// Whisper reçoit la fin du passage précédent de la même voix comme contexte, et la répète parfois en tête du suivant (le son ne
    /// se chevauche jamais : deux morceaux d'une piste se suivent). Si les premiers mots de `texte` reprennent les derniers mots de
    /// `precedent` (au moins `minimum` mots de suite, sans tenir compte des accents, majuscules ni ponctuation), ils sont retirés.
    /// Un passage qui n'est qu'une reprise devient vide.
    public static func sansReprise(_ texte: String, apres precedent: String, minimum: Int = 4) -> String {
        let jetons = texte.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        // les mêmes « mots » des deux côtés : un jeton du texte (« d'avoir ») plié en une clé (« davoir »)
        let cles = jetons.map { mots($0).joined() }
        let avant = precedent.split(whereSeparator: { $0.isWhitespace }).map { mots(String($0)).joined() }.filter { !$0.isEmpty }
        guard !avant.isEmpty, !jetons.isEmpty else { return texte }
        // le plus long recouvrement : les k derniers mots d'avant = les k premiers mots (non vides) du texte
        var meilleur = 0, coupe = 0
        var k = 0, i = 0
        var debut: [String] = []
        while i < jetons.count, k < avant.count {
            if !cles[i].isEmpty {
                debut.append(cles[i]); k += 1
                if k >= min(minimum, avant.count), Array(avant.suffix(k)) == debut { meilleur = k; coupe = i + 1 }
            }
            i += 1
        }
        guard meilleur >= minimum || (meilleur == avant.count && meilleur >= 2 && meilleur == cles.filter { !$0.isEmpty }.count) else { return texte }
        var reste = Array(jetons[coupe...])
        // le reste commence par une ponctuation isolée (« , c'est faisable ») : on la retire ; et une majuscule après une phrase finie
        while let p = reste.first, mots(p).isEmpty { reste.removeFirst() }
        guard var premier = reste.first else { return "" }
        if let fin = precedent.trimmingCharacters(in: .whitespaces).last, ".?!…".contains(fin), let c = premier.first, c.isLowercase {
            premier = c.uppercased() + premier.dropFirst()
            reste[0] = premier
        }
        return reste.joined(separator: " ")
    }

    /// Les reprises retirées dans une suite de passages d'UNE voix, dans l'ordre du son ; les passages devenus vides disparaissent.
    /// Seulement entre deux morceaux qui se suivent (moins de `ecart` secondes entre eux : un même tour coupé par le découpage, le son
    /// ne se chevauche pas, une répétition y est forcément un artefact) ; « Oui, je m'en charge. » redit une minute plus tard est gardé.
    public static func sansReprises(_ segments: [SegmentReunion], ecart: Double = 3) -> [SegmentReunion] {
        var sortie: [SegmentReunion] = []
        for s in segments {
            guard let d = sortie.last, s.debut - d.fin <= ecart else { sortie.append(s); continue }
            var t = s
            t.texte = sansReprise(s.texte, apres: d.texte)
            if !t.texte.isEmpty { sortie.append(t) }
        }
        return sortie
    }

    /// Tout d'un coup : reprises de Whisper retirées (voix par voix), échos retirés, fusion, regroupement. Renvoie aussi le nombre
    /// d'échos retirés (pour le journal).
    public static func transcription(moi: [SegmentReunion], eux: [SegmentReunion], dureeMax: Double = .infinity) -> (segments: [SegmentReunion], echos: Int) {
        let m = sansReprises(moi.sorted { $0.debut < $1.debut }), e = sansReprises(eux.sorted { $0.debut < $1.debut })
        let propre = retirerEchos(moi: m, eux: e)
        return (regrouper(fusionner(moi: propre.moi, eux: e), dureeMax: dureeMax), propre.retires)
    }
}
