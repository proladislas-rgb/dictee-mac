import Foundation

/// Un mot que la correction « à l'oreille » connaît : ceux que Hugues a choisis (mots.txt) et ceux du lexique.
public struct MotConnuDeLOreille: Sendable {
    public let mot: String
    public let plie: String
    public let cle: String
    public let prioritaire: Bool
    public let frequence: Int
    public let sigle: Bool

    init(mot: String, prioritaire: Bool, frequence: Int, sigle: Bool) {
        self.mot = mot; plie = ClePhonetique.plier(mot); cle = ClePhonetique.cle(mot)
        self.prioritaire = prioritaire; self.frequence = frequence; self.sigle = sigle
    }
}

/// Les mots contre lesquels on compare, avec leurs clés phonétiques calculées une fois pour toutes.
public struct IndexCorrection: Sendable {
    public let mots: [MotConnuDeLOreille]
    let parPlie: [String: Int]

    public init(motsChoisis: [String], lexique: [EntreeLexique]) {
        var liste: [MotConnuDeLOreille] = []
        var vus = Set<String>()
        for m in motsChoisis {
            let propre = m.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !propre.contains(" "), !propre.isEmpty else { continue }   // les expressions de plusieurs mots ne se corrigent pas ici
            let e = MotConnuDeLOreille(mot: propre, prioritaire: true, frequence: Int.max / 2, sigle: false)
            if vus.insert(e.plie).inserted { liste.append(e) }
        }
        for l in lexique where !l.mot.contains(" ") {
            let e = MotConnuDeLOreille(mot: l.mot, prioritaire: false, frequence: l.frequence, sigle: l.type == .sigle)
            if vus.insert(e.plie).inserted { liste.append(e) }
        }
        mots = liste
        var p: [String: Int] = [:]
        for (i, e) in liste.enumerated() { p[e.plie] = i }
        parPlie = p
    }
}

public struct Correction: Equatable, Sendable {
    public let original: String
    public let remplacement: String
    public init(original: String, remplacement: String) { self.original = original; self.remplacement = remplacement }
    /// Ligne de journal : chaque côté borné à 60 caractères.
    public var ligneDeJournal: String {
        func borne(_ t: String) -> String { t.count > 60 ? String(t.prefix(59)) + "\u{2026}" : t }
        return "correction \u{00E0} l\u{2019}oreille : \"\(borne(original))\" \u{2192} \"\(borne(remplacement))\""
    }
}

/// Correction « à l'oreille » après Whisper : un mot que le correcteur orthographique ne connaît pas, qui ressemble à l'oreille à UN
/// mot du lexique, est remplacé par lui (« Brionia » → « Brillonia »). Prudence :
///  - jamais un mot connu du correcteur, jamais un mot de moins de 4 lettres ;
///  - la clé phonétique doit être à une lettre au plus, l'écriture à 1 à 3 lettres selon la longueur ;
///  - seulement si un seul candidat est nettement meilleur que tous les autres ;
///  - deux mots collés ensemble (« Eco verdix » = « Ecoverdix ») ne sont réunis que si leur assemblage est exactement un mot connu.
/// Logique pure : `estConnu` (le correcteur orthographique) est fourni par l'appelant.
public enum CorrectionOreille {
    struct Jeton {
        let plage: Range<String.Index>   // le mot entier, élision comprise
        let coeur: Range<String.Index>   // le mot sans l'élision (« l' » retiré)
    }

    static func jetons(_ texte: String) -> [Jeton] {
        var sortie: [Jeton] = []
        var i = texte.startIndex
        func alnum(_ c: Character) -> Bool { c.isLetter || c.isNumber }
        while i < texte.endIndex {
            guard alnum(texte[i]) else { i = texte.index(after: i); continue }
            var j = i
            var apostrophe: String.Index?
            while j < texte.endIndex {
                let c = texte[j]
                if alnum(c) { j = texte.index(after: j); continue }
                if c == "-" || c == "'" || c == "\u{2019}" {
                    let k = texte.index(after: j)
                    if k < texte.endIndex, alnum(texte[k]), j > i {
                        if c != "-", apostrophe == nil { apostrophe = j }
                        j = k; continue
                    }
                }
                break
            }
            var coeur = i..<j
            if let a = apostrophe {
                let avant = texte[i..<a].lowercased()
                if avant.count <= 2 || ExtractionLexique.elisions.contains(avant) { coeur = texte.index(after: a)..<j }
            }
            sortie.append(Jeton(plage: i..<j, coeur: coeur))
            i = j
        }
        return sortie
    }

    /// Le mot colle-t-il à une adresse, un chemin, un identifiant (« ecodistrib.fr », « @brillonia », « nom_de_fichier ») ?
    static func partDUnLien(_ texte: String, _ j: Jeton) -> Bool {
        if j.plage.lowerBound > texte.startIndex {
            let avant = texte[texte.index(before: j.plage.lowerBound)]
            if "@/#_\\~".contains(avant) { return true }
            if avant == ".", j.plage.lowerBound > texte.index(after: texte.startIndex), texte[texte.index(texte.index(before: j.plage.lowerBound), offsetBy: -1)].isLetter { return true }
        }
        if j.plage.upperBound < texte.endIndex {
            let apres = texte[j.plage.upperBound]
            if "@/_\\".contains(apres) { return true }
            if apres == ".", let suivant = texte.index(j.plage.upperBound, offsetBy: 1, limitedBy: texte.endIndex), suivant < texte.endIndex, texte[suivant].isLetter { return true }
        }
        return false
    }

    /// Distance maximale d'écriture admise selon la longueur du plus court des deux mots.
    static func ecartAutorise(_ longueur: Int) -> Int { longueur <= 5 ? 1 : (longueur <= 7 ? 2 : 3) }

    /// Un nom du lexique écrit « Alloco » alors que Whisper a mis une minuscule (« alocco ») : la minuscule est gardée, sauf pour les
    /// écritures qui ne se devinent pas (kWh, CEE) et les mots choisis par Hugues.
    static func adapterLaCasse(_ e: MotConnuDeLOreille, a mot: String) -> String {
        guard !e.prioritaire, let premier = mot.first, premier.isLowercase, let f = e.mot.first, f.isUppercase,
              !e.mot.dropFirst().contains(where: \.isUppercase) else { return e.mot }
        return f.lowercased() + e.mot.dropFirst()
    }

    /// Le meilleur candidat du lexique pour `mot`, ou `nil` s'il n'y en a pas ou s'il n'est pas nettement le meilleur.
    public static func meilleurCandidat(pour mot: String, index: IndexCorrection) -> MotConnuDeLOreille? {
        let ft = ClePhonetique.plier(mot), kt = ClePhonetique.cle(mot)
        guard ft.count >= 4, !ft.contains(where: \.isNumber) else { return nil }
        var meilleurs: [(MotConnuDeLOreille, Int)] = []
        for e in index.mots where !e.sigle && e.plie.count >= 5 && abs(e.plie.count - ft.count) <= 3 && e.plie != ft {
            guard abs(e.cle.count - kt.count) <= 2 else { continue }
            guard e.plie.first == ft.first || e.cle.first == kt.first else { continue }
            let dk = ClePhonetique.distance(kt, e.cle, plafond: 1)
            let l = min(ft.count, e.plie.count)
            let df = ClePhonetique.distance(ft, e.plie, plafond: ecartAutorise(l))
            guard df <= ecartAutorise(l) else { continue }
            // sons voisins (clé phonétique à une lettre) ; ou UNE seule lettre de différence dans un mot assez long (Vermflow / Vermiflow)
            guard dk <= 1 || (df <= 1 && l >= 6) else { continue }
            meilleurs.append((e, dk * 2 + df))
        }
        guard !meilleurs.isEmpty else { return nil }
        meilleurs.sort { $0.1 != $1.1 ? $0.1 < $1.1 : ($0.0.prioritaire != $1.0.prioritaire ? $0.0.prioritaire : $0.0.frequence > $1.0.frequence) }
        if meilleurs.count >= 2, meilleurs[1].1 - meilleurs[0].1 < 2 { return nil }
        return meilleurs[0].0
    }

    public static func corriger(_ texte: String, index: IndexCorrection, estConnu: (String) -> Bool) -> (texte: String, corrections: [Correction]) {
        guard !index.mots.isEmpty, !texte.isEmpty else { return (texte, []) }
        let js = jetons(texte)
        var remplacements: [(Range<String.Index>, String, String)] = []   // plage, nouveau texte, original
        var i = 0
        while i < js.count {
            let j = js[i]
            let mot = String(texte[j.coeur])
            defer { i += 1 }
            if partDUnLien(texte, j) { continue }

            // 1. deux mots séparés par une seule espace dont l'assemblage est un mot connu (« Eco verdix »)
            if i + 1 < js.count, !partDUnLien(texte, js[i + 1]) {
                let entre = texte[j.plage.upperBound..<js[i + 1].plage.lowerBound]
                let suivant = String(texte[js[i + 1].coeur])
                if entre == " ", mot.count >= 2, suivant.count >= 2,
                   let k = index.parPlie[ClePhonetique.plier(mot + suivant)], index.mots[k].plie.count >= 7, !index.mots[k].sigle,
                   !mot.contains(where: \.isNumber), !suivant.contains(where: \.isNumber) {
                    let cible = index.mots[k].mot
                    if cible != mot + " " + suivant { remplacements.append((j.coeur.lowerBound..<js[i + 1].coeur.upperBound, cible, mot + " " + suivant)) }
                    i += 1
                    continue
                }
            }

            let ft = ClePhonetique.plier(mot)
            guard ft.count >= 4 else { continue }

            // 2. même mot, autre écriture (casse, accents) : « brillonia » → « Brillonia », seulement si le correcteur ne le connaît pas
            if let k = index.parPlie[ft] {
                let entree = index.mots[k]
                // la casse n'est imposée que pour une écriture qui ne se devine pas (kWh, iPhone, CEE) ou pour un mot choisi par Hugues ;
                // un nom du lexique écrit en minuscules (« alloco ») est laissé tel que Whisper l'a mis
                let imposee = entree.mot.dropFirst().contains(where: \.isUppercase) || (entree.prioritaire && entree.mot.first?.isUppercase == true)
                let seuleLaCasseDiffere = mot.lowercased() == entree.mot.lowercased()
                // « WISPR » écrit en capitales par Whisper (imitation du prompt) : un mot en capitales n'est jamais « connu » pour ça
                let toutEnCapitales = mot.count >= 4 && mot == mot.uppercased() && entree.mot != entree.mot.uppercased()
                if mot != entree.mot, imposee || !seuleLaCasseDiffere, toutEnCapitales || !estConnu(mot) { remplacements.append((j.coeur, entree.mot, mot)) }
                continue
            }
            // pluriel d'un mot du lexique
            if ft.hasSuffix("s"), let k = index.parPlie[String(ft.dropLast())], index.mots[k].plie.count >= 5, !estConnu(mot) {
                let cible = index.mots[k].mot + "s"
                if mot != cible { remplacements.append((j.coeur, cible, mot)) }
                continue
            }

            // 3. mot inconnu qui ressemble à l'oreille à un seul mot du lexique. Avec une élision (« l'adislas »), le mot entier passe en
            //    premier : le « l' » entendu était la première lettre du nom (Ladomir), pas un article.
            if j.plage != j.coeur {
                let entier = String(texte[j.plage])
                let exact = index.parPlie[ClePhonetique.plier(entier)].map { index.mots[$0] }
                if let e = exact ?? meilleurCandidat(pour: entier, index: index), !estConnu(mot), !estConnu(entier) {
                    remplacements.append((j.plage, e.mot, entier))   // après une élision, la casse du lexique
                    continue
                }
            }
            if let e = meilleurCandidat(pour: mot, index: index) {
                if estConnu(mot) { continue }
                remplacements.append((j.coeur, adapterLaCasse(e, a: mot), mot))
            }
        }
        guard !remplacements.isEmpty else { return (texte, []) }
        var resultat = ""
        var curseur = texte.startIndex
        for (plage, nouveau, _) in remplacements {   // dans l'ordre du texte
            resultat += texte[curseur..<plage.lowerBound] + nouveau
            curseur = plage.upperBound
        }
        resultat += texte[curseur...]
        return (resultat, remplacements.map { Correction(original: $0.2, remplacement: $0.1) })
    }
}
