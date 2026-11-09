import Foundation

/// Un mot retenu pour le lexique, avant la mesure de sa langue.
public struct CandidatLexique: Equatable, Sendable {
    public var mot: String
    public var frequence: Int
    public var documents: Int
    public var source: String
    /// Une phrase où il apparaît (pour deviner la langue) ; jamais écrite dans le lexique.
    public var phrase: String
    public var type: TypeMot
}

/// Lit des textes (notes, specs en .md ou .txt), compte les mots et garde les candidats utiles à Whisper : noms propres, sigles,
/// mots composés, jargon, mots étrangers. Les mots courants (connus du correcteur orthographique, passé en paramètre) sont écartés,
/// sauf s'ils portent une majuscule intérieure ou s'ils sont un sigle. Logique pure : aucun accès au disque ni au correcteur ici.
public struct ExtractionLexique {
    enum Forme { case sigle, capitalise, minuscule, mixte }

    struct Cumul {
        var formes: [String: Int] = [:]       // écriture rencontrée → nombre
        var enMilieu: [String: Int] = [:]     // idem, hors début de phrase
        var total = 0
        var parDocument: [Int: Int] = [:]     // document → nombre d'apparitions
        var sources: [String: Int] = [:]
        var phrase = ""
        var impose = false                    // mot apporté tel quel (liste de base) : seuils de fréquence ignorés

        /// Fréquence qui ne se laisse pas écraser par un seul gros fichier : au plus 10 apparitions comptées par document.
        var frequencePonderee: Int { parDocument.values.reduce(0) { $0 + min($1, 10) } }
        var documents: Int { parDocument.keys.filter { $0 >= 0 }.count }
    }

    var cumuls: [String: Cumul] = [:]
    public private(set) var nombreDeDocuments = 0
    public private(set) var nombreDeMots = 0

    public init() {}

    // MARK: lecture

    /// Ajoute un texte. `document` distingue les fichiers (un mot présent dans plusieurs documents compte davantage).
    public mutating func ajouter(texte: String, source: String, document: Int) {
        nombreDeDocuments += 1
        for (jeton, debut, phrase) in Self.jetons(dans: texte) {
            noter(jeton, debutDePhrase: debut, source: source, document: document, phrase: phrase, impose: false)
        }
    }

    /// Ajoute des mots à garder quoi qu'il arrive (liste de base, mots.txt) : écrits tels quels, fréquence minimale.
    public mutating func ajouterImposes(_ mots: [String], source: String) {
        for m in mots {
            let propre = m.trimmingCharacters(in: .whitespacesAndNewlines)
            guard propre.count >= 2 else { continue }
            noter(propre, debutDePhrase: false, source: source, document: -1, phrase: "", impose: true)
        }
    }

    mutating func noter(_ jeton: String, debutDePhrase: Bool, source: String, document: Int, phrase: String, impose: Bool) {
        let cle = ClePhonetique.plier(jeton)
        guard !cle.isEmpty else { return }
        nombreDeMots += 1
        var c = cumuls[cle] ?? Cumul()
        c.formes[jeton, default: 0] += 1
        if !debutDePhrase || impose { c.enMilieu[jeton, default: 0] += 1 }
        c.total += 1
        c.parDocument[document, default: 0] += 1
        c.sources[source, default: 0] += 1
        if c.phrase.isEmpty { c.phrase = phrase }
        if impose { c.impose = true }
        cumuls[cle] = c
    }

    // MARK: découpage en mots

    static let elisions: Set<String> = ["qu", "jusqu", "lorsqu", "puisqu", "quoiqu"]

    /// Les mots d'un texte, avec « est-ce un début de phrase » et la phrase. Retire blocs de code, liens, adresses, chemins.
    static func jetons(dans texte: String) -> [(String, Bool, String)] {
        var sortie: [(String, Bool, String)] = []
        var dansCode = false
        for ligneBrute in texte.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let ligne = ligneBrute.trimmingCharacters(in: .whitespaces)
            if ligne.hasPrefix("```") || ligne.hasPrefix("~~~") { dansCode.toggle(); continue }
            if dansCode || ligne.isEmpty { continue }
            let propre = nettoyerLigne(String(ligne))
            sortie.append(contentsOf: jetonsDeLigne(propre))
        }
        return sortie
    }

    private static let motifs: [NSRegularExpression] = [
        "`[^`]*`", "https?://\\S+", "www\\.\\S+", "\\S+@\\S+\\.\\S+", "\\]\\([^)]*\\)", "<[^>]+>", "&[a-z]+;",
    ].compactMap { try? NSRegularExpression(pattern: $0) }

    static func nettoyerLigne(_ ligne: String) -> String {
        var s = ligne
        for m in motifs {
            s = m.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: " ")
        }
        // un morceau qui ressemble à un chemin de fichier ou à une affectation (a=b) est ignoré ; « client/prospect » est coupé en deux mots
        let morceaux = s.split(separator: " ", omittingEmptySubsequences: true).map { m -> String in
            let t = String(m)
            if t.contains("=") || t.contains("\\") || t.contains("{") || t.contains("}") || t.contains("::") { return " " }
            if t.contains("/") {
                let commence = t.hasPrefix("/") || t.hasPrefix("~") || t.hasPrefix(".")
                let extension_ = t.range(of: "\\.[A-Za-z0-9]{1,5}[)\\]\\.,;:]*$", options: .regularExpression) != nil
                if commence || extension_ || t.filter({ $0 == "/" }).count >= 2 { return " " }
                return t.replacingOccurrences(of: "/", with: " ")
            }
            return t
        }
        return morceaux.joined(separator: " ")
    }

    private static func jetonsDeLigne(_ ligne: String) -> [(String, Bool, String)] {
        let caracteres = Array(ligne)
        var sortie: [(String, Bool, String)] = []
        var debut = true
        var i = 0
        let phrase = String(ligne.prefix(160))
        func estJoint(_ c: Character) -> Bool { c == "-" || c == "'" || c == "\u{2019}" }
        while i < caracteres.count {
            let c = caracteres[i]
            if c.isLetter || c.isNumber {
                var j = i
                while j < caracteres.count {
                    let d = caracteres[j]
                    if d.isLetter || d.isNumber { j += 1 }
                    else if estJoint(d), j + 1 < caracteres.count, caracteres[j + 1].isLetter || caracteres[j + 1].isNumber, j > i { j += 1 }
                    else { break }
                }
                var jeton = String(caracteres[i..<j])
                // « l'Ecoverdix », « d'Orléans » : on garde le mot après l'élision
                if let k = jeton.firstIndex(where: { $0 == "'" || $0 == "\u{2019}" }) {
                    let avant = String(jeton[jeton.startIndex..<k]).lowercased()
                    if avant.count <= 2 || elisions.contains(avant) { jeton = String(jeton[jeton.index(after: k)...]) }
                }
                if let valide = retenir(jeton) { sortie.append((valide, debut, phrase)) }
                debut = false
                i = j
            } else {
                if ".!?\u{2026}".contains(c) || c == "|" { debut = true }
                i += 1
            }
        }
        return sortie
    }

    /// Le jeton est-il un mot plausible (ni nombre, ni identifiant de code, ni hexadécimal) ? Renvoie le jeton ou `nil`.
    static func retenir(_ jeton: String) -> String? {
        let lettres = jeton.filter(\.isLetter).count
        let chiffres = jeton.filter(\.isNumber).count
        guard lettres >= 3 || (lettres >= 2 && chiffres >= 1), jeton.count <= 28, chiffres <= lettres else { return nil }
        guard let premier = jeton.first, premier.isLetter else { return nil }
        if chiffres > 0 {
            // seuls les sigles à tirets (TRA-SE-104, BAR-TH-104) peuvent contenir des chiffres
            let motif = "^[A-Z][A-Z0-9]*(-[A-Z0-9]+)+$"
            guard jeton.range(of: motif, options: .regularExpression) != nil else { return nil }
        }
        if jeton.count >= 6, jeton.allSatisfy({ $0.isHexDigit }) { return nil }   // couleurs (FAFAFA) et empreintes
        if !jeton.contains("-") {
            if lettres > 18 { return nil }
            let voyelles = jeton.lowercased().filter { "aeiouyàâäéèêëîïôöùûüœ".contains($0) }.count
            if lettres >= 8, Double(voyelles) / Double(lettres) < 0.18, jeton.contains(where: \.isLowercase) { return nil }   // identifiants au hasard
        }
        // plages de numéros (B1-B4, K2-K4)
        let parties = jeton.split(separator: "-")
        if parties.count >= 2, parties.allSatisfy({ $0.count <= 3 && $0.first?.isLetter == true && $0.dropFirst().allSatisfy(\.isNumber) }) { return nil }
        return jeton
    }

    static func forme(_ jeton: String) -> Forme {
        let lettres = jeton.filter(\.isLetter)
        if lettres.count >= 2, lettres.allSatisfy(\.isUppercase) { return .sigle }
        if lettres.allSatisfy(\.isLowercase) { return .minuscule }
        let parties = jeton.split(whereSeparator: { $0 == "-" || $0 == "'" || $0 == "\u{2019}" })
        let toutesCapitalisees = parties.allSatisfy { p in
            guard let f = p.first, f.isUppercase else { return false }
            return p.dropFirst().filter(\.isLetter).allSatisfy(\.isLowercase)
        }
        if toutesCapitalisees { return .capitalise }
        return .mixte
    }

    /// Identifiant de code (maPetiteFonction, HistoriqueStoreVue) : plusieurs bosses de majuscules. « iPhone », « macOS », « GitHub » restent.
    static func ressembleACode(_ jeton: String) -> Bool {
        var bosses = 0
        var precedent: Character?
        for c in jeton {
            if c.isUppercase, let p = precedent, p.isLowercase { bosses += 1 }
            precedent = c
        }
        guard let premier = jeton.first else { return false }
        return premier.isLowercase ? bosses >= 2 : bosses >= 3
    }

    /// Pourquoi un mot est retenu ou non (pour comprendre un lexique : `--construire-lexique --pourquoi mot`).
    public func diagnostic(_ mot: String, estConnu: (String) -> Bool, variantesAvecAccents: (String) -> Bool = { _ in false }) -> String {
        guard let c = cumuls[ClePhonetique.plier(mot)] else { return "\(mot) : jamais vu" }
        let formes = c.formes.sorted { $0.value > $1.value }.prefix(6).map { "\($0.key)×\($0.value)" }.joined(separator: ", ")
        let choix = choisir(cle: ClePhonetique.plier(mot), cumul: c, seuils: Seuils(), estConnu: estConnu, variantesAvecAccents: variantesAvecAccents)
        return "\(mot) : \(formes) ; fréquence pondérée \(c.frequencePonderee), \(c.documents) document(s) ; \(choix.map { "retenu sous la forme « \($0.mot) » (\($0.type.rawValue))" } ?? "écarté")"
    }

    // MARK: choix

    /// Réglages du tri (seuils de fréquence).
    public struct Seuils: Sendable {
        public var nomFrequence = 2   // un nom cité une seule fois entre aussi, s'il porte une majuscule en milieu de phrase
        public var sigleFrequence = 2
        public var techniqueFrequence = 3
        public var techniqueDocuments = 2
        public var maximum = 6000
        public init() {}
    }

    /// Les candidats utiles, classés par fréquence. `estConnu` dit si le correcteur orthographique connaît le mot (français ou anglais).
    public func candidats(seuils: Seuils = Seuils(), estConnu: (String) -> Bool, variantesAvecAccents: (String) -> Bool = { _ in false }) -> [CandidatLexique] {
        var sortie: [CandidatLexique] = []
        for (cle, c) in cumuls {
            guard let choix = choisir(cle: cle, cumul: c, seuils: seuils, estConnu: estConnu, variantesAvecAccents: variantesAvecAccents) else { continue }
            let source = c.sources.max { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }?.key ?? ""
            sortie.append(CandidatLexique(mot: choix.mot, frequence: c.frequencePonderee, documents: c.documents,
                                          source: source, phrase: c.phrase, type: choix.type))
        }
        sortie.sort {
            if $0.frequence != $1.frequence { return $0.frequence > $1.frequence }
            if $0.documents != $1.documents { return $0.documents > $1.documents }
            return $0.mot < $1.mot
        }
        return Array(sortie.prefix(seuils.maximum))
    }

    func choisir(cle: String, cumul c: Cumul, seuils: Seuils, estConnu: (String) -> Bool, variantesAvecAccents: (String) -> Bool = { _ in false }) -> (mot: String, type: TypeMot)? {
        func plusFrequent(_ test: (Forme) -> Bool) -> (String, Int)? {
            c.formes.filter { test(Self.forme($0.key)) }.max { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }.map { ($0.key, $0.value) }
        }
        let tropCourant = MotsTropCourants.sigles.contains(cle)
        let docs = c.documents
        let frequence = c.frequencePonderee
        let sigle = plusFrequent { $0 == .sigle }
        let mixte = plusFrequent { $0 == .mixte }
        let mixteAcceptable = mixte.flatMap { Self.ressembleACode($0.0) ? nil : $0 }
        var mot: String
        var type: TypeMot
        if let s = sigle, s.1 * 2 >= c.total || c.impose {
            if tropCourant && !c.impose { return nil }
            // un mot courant écrit en capitales (IMPORTANT, FAIL, GET) n'est pas un sigle ; les codes à tirets ou chiffres (TRA-SE-104) restent
            if !c.impose, s.0.allSatisfy(\.isLetter), c.formes.keys.contains(where: { Self.forme($0) == .minuscule && estConnu($0) }) || estConnu(s.0.lowercased()) { return nil }
            // OU-J-EN-SUIS, SOUS-COMPÉTENCE : un titre en capitales, pas un sigle
            if !c.impose, !s.0.contains(where: \.isNumber), s.0.contains("-"),
               s.0.split(separator: "-").contains(where: { $0.count >= 2 && estConnu($0.lowercased()) }) { return nil }
            mot = s.0; type = .sigle
            if !c.impose && frequence < seuils.sigleFrequence { return nil }
            return (mot, type)
        }
        if let m = mixteAcceptable, m.1 * 5 >= c.total * 2 || c.impose {
            // majuscule intérieure : gardé même si le correcteur le connaît, mais un identifiant de code (keyDown, ChatWindow) ne se
            // distingue d'une marque (iPhone, GitHub) que par sa rareté : une marque est citée dans plusieurs documents
            if !c.impose {
                guard frequence >= max(6, seuils.techniqueFrequence), docs >= max(4, seuils.techniqueDocuments) else { return nil }
                if let p = m.0.first, p.isLowercase, let bosse = m.0.firstIndex(where: \.isUppercase), m.0.distance(from: m.0.startIndex, to: bosse) > 2, !m.0.hasPrefix("mac") { return nil }
            }
            return (m.0, .technique)
        }
        if mixte != nil && mixteAcceptable == nil && !c.impose { return nil }
        // majuscule initiale en milieu de phrase = nom propre
        let capital = c.enMilieu.filter { Self.forme($0.key) == .capitalise }.reduce(0) { $0 + $1.value }
        let minuscule = c.enMilieu.filter { Self.forme($0.key) == .minuscule }.reduce(0) { $0 + $1.value }
        let capitalSeulement = c.formes.allSatisfy { Self.forme($0.key) == .capitalise }
        if let nom = plusFrequent({ $0 == .capitalise }), (capital > 0 && capital >= minuscule) || capitalSeulement || c.impose {
            if !c.impose {
                guard frequence >= seuils.nomFrequence || (frequence == 1 && capital >= 1) else { return nil }
                // une écriture connue du correcteur (avec ou sans accents, avec ou sans majuscule) : mot courant
                if c.formes.keys.contains(where: { Self.forme($0) == .capitalise && (estConnu($0) || estConnu($0.lowercased())) }) { return nil }
            }
            return (nom.0, .nom)
        }
        guard let min = plusFrequent({ $0 == .minuscule }) else { return nil }
        if !c.impose {
            guard frequence >= seuils.techniqueFrequence, docs >= seuils.techniqueDocuments || frequence >= 6 else { return nil }
            guard min.0.filter(\.isLetter).count >= 5 else { return nil }   // rgb, mjs, dpl : trop courts pour être utiles en minuscules
            if c.formes.keys.contains(where: { Self.forme($0) == .minuscule && estConnu($0) }) { return nil }
            if variantesAvecAccents(min.0) { return nil }   // « recoit » pour « reçoit » : une faute d'accent de code, pas un mot
            // un nom de fichier (verif-hors-ligne, carte-legende) : composé dont une partie n'est pas un vrai mot ; bas-carbone reste
            let parties = min.0.split(separator: "-").map(String.init)
            if parties.count >= 2, !parties.allSatisfy({ estConnu($0) }) { return nil }
        }
        return (min.0, .technique)
    }
}
