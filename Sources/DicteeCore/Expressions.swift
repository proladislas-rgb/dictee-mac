import Foundation

/// Une expression ou un mot familier de Hugues (« t'inquiète », « on se capte », « c'est lourd »).
public struct ExpressionPerso: Codable, Equatable, Hashable, Sendable {
    public var texte: String
    /// Dans combien de dictées de l'historique elle apparaît (0 pour une expression ajoutée à la main et jamais retrouvée).
    public var dictees: Int
    public var manuelle: Bool
    public var ajouteeLe: Date
    public init(texte: String, dictees: Int = 0, manuelle: Bool = false, ajouteeLe: Date = Date()) {
        self.texte = texte; self.dictees = dictees; self.manuelle = manuelle; self.ajouteeLe = ajouteeLe
    }
}

/// Ce que Verbe a appris tout seul (ligne « Verbe a appris N mots et expressions cette semaine »).
public struct EvenementApprentissage: Codable, Equatable, Sendable {
    public enum Genre: String, Codable, Sendable { case expression, mot }
    public var date: Date
    public var texte: String
    public var genre: Genre
    public init(date: Date, texte: String, genre: Genre) { self.date = date; self.texte = texte; self.genre = genre }
}

/// Les expressions personnelles : extraites de l'historique (une fois par jour, sans geste de Hugues), modifiables à la main.
/// Stockées dans `expressions.json` (0600, jamais dans git). Logique pure.
public struct ListeExpressions: Codable, Equatable, Sendable {
    public static let maximum = 40
    public static let intervalle: TimeInterval = 20 * 3600

    public var version = 1
    public var expressions: [ExpressionPerso] = []
    /// Expressions retirées par Hugues (pliées) : l'extraction ne les remet pas.
    public var exclues: [String] = []
    public var derniereExtraction: Date?
    public var appris: [EvenementApprentissage] = []

    public init() {}

    private static func plier(_ s: String) -> String { Historique.plier(s) }

    public func contient(_ texte: String) -> Bool { expressions.contains { Self.plier($0.texte) == Self.plier(texte) } }

    /// Ajout à la main. Faux si vide ou déjà là. Une expression qu'on ajoute à la main sort de la liste des exclues.
    @discardableResult
    public mutating func ajouterManuelle(_ saisie: String, maintenant: Date = Date()) -> Bool {
        let t = saisie.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !contient(t) else { return false }
        exclues.removeAll { $0 == Self.plier(t) }
        expressions.append(ExpressionPerso(texte: t, manuelle: true, ajouteeLe: maintenant))
        return true
    }

    /// Retrait par Hugues : elle ne reviendra pas tout seule.
    public mutating func retirer(_ texte: String) {
        let p = Self.plier(texte)
        expressions.removeAll { Self.plier($0.texte) == p }
        if !exclues.contains(p) { exclues.append(p) }
    }

    /// Met à jour la liste d'après une extraction. Les expressions manuelles restent ; les automatiques sont remplacées par les extraites
    /// (celles déjà connues gardent leur date d'ajout). Renvoie les expressions nouvelles (apprises). Au plus `maximum` automatiques.
    @discardableResult
    public mutating func fusionner(extraites: [(texte: String, dictees: Int)], maintenant: Date = Date()) -> [String] {
        let anciennes = Dictionary(expressions.map { (Self.plier($0.texte), $0) }, uniquingKeysWith: { a, _ in a })
        var nouvelles: [String] = []
        var auto: [ExpressionPerso] = []
        for e in extraites.prefix(Self.maximum) {
            let p = Self.plier(e.texte)
            if exclues.contains(p) { continue }
            if let a = anciennes[p] {
                if a.manuelle { continue }
                var m = a; m.dictees = e.dictees; auto.append(m)
            } else {
                auto.append(ExpressionPerso(texte: e.texte, dictees: e.dictees, ajouteeLe: maintenant))
                nouvelles.append(e.texte)
            }
        }
        let manuelles = expressions.filter(\.manuelle).map { m -> ExpressionPerso in
            var m = m; if let e = extraites.first(where: { Self.plier($0.texte) == Self.plier(m.texte) }) { m.dictees = e.dictees }; return m
        }
        expressions = manuelles + auto
        derniereExtraction = maintenant
        for n in nouvelles { appris.append(EvenementApprentissage(date: maintenant, texte: n, genre: .expression)) }
        elaguerJournal(maintenant)
        return nouvelles
    }

    /// Un mot appris d'une correction répétée (ajouté à mots.txt par l'appelant).
    public mutating func noterMotAppris(_ mot: String, maintenant: Date = Date()) {
        appris.append(EvenementApprentissage(date: maintenant, texte: mot, genre: .mot))
        elaguerJournal(maintenant)
    }

    private mutating func elaguerJournal(_ maintenant: Date) {
        appris.removeAll { maintenant.timeIntervalSince($0.date) > 60 * 86_400 }
    }

    /// Nombre de mots et d'expressions appris sur les 7 derniers jours.
    public func apprisCetteSemaine(maintenant: Date = Date()) -> Int {
        appris.filter { maintenant.timeIntervalSince($0.date) <= 7 * 86_400 }.count
    }

    /// Faut-il refaire l'extraction ? Une fois par jour (au plus), sans geste de Hugues.
    public func extractionDue(maintenant: Date = Date()) -> Bool {
        guard let d = derniereExtraction else { return true }
        return maintenant.timeIntervalSince(d) >= Self.intervalle
    }

    /// Les expressions à donner à Whisper et à la relecture : celles de Hugues d'abord, puis les plus fréquentes ; les plus courtes à égalité.
    public func pourWhisper(maximum: Int = 10) -> [String] {
        let tri = expressions.sorted {
            if $0.manuelle != $1.manuelle { return $0.manuelle }
            if $0.dictees != $1.dictees { return $0.dictees > $1.dictees }
            return $0.texte.count < $1.texte.count
        }
        return tri.prefix(maximum).map(\.texte)
    }

    public func donnees() -> Data? {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? e.encode(self)
    }
    public static func depuis(_ d: Data?) -> ListeExpressions? {
        guard let d else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(ListeExpressions.self, from: d)
    }
}

/// Extraction des expressions et mots familiers fréquents depuis l'historique des dictées. Logique pure.
public enum ExtractionExpressions {
    /// Mots familiers ou d'oral : un candidat qui en contient un compte dès 3 dictées ; sinon il faut 6 dictées.
    static let familiers: Set<String> = {
        let l = "wesh ouais ouaip ouf bah ben bref genre grave lourd lourde chaud carre nickel impec top cool relou kiffe kiffer kiff vas y vazy tranquille tkt inquiete capte capter taf boulot dispo resto appart bosser bouffer mec meuf frere frero gars putain merde ptn bordel zero souci coup vrai franchement clairement carrement quoi hein bon ok okay yes go check checker ping debrief brief deal chiant dingue enorme ouaf mdr lol sympa chelou pote potes galere relou truc machin bidule pile poil nickel parfait voila exactement clairement vraiment trop tellement".split(separator: " ")
        return Set(l.map { ClePhonetique.plier(String($0)) })
    }()

    /// Mots d'une dictée par segment (la ponctuation coupe : aucune suite de mots ne passe par-dessus une virgule ou un point).
    static func segments(_ texte: String) -> [[String]] {
        var res: [[String]] = []
        var seg: [String] = []
        var courant = ""
        func mot() { if !courant.isEmpty { seg.append(courant.trimmingCharacters(in: CharacterSet(charactersIn: "-'"))); courant = "" } }
        func fin() { mot(); seg.removeAll { $0.isEmpty }; if !seg.isEmpty { res.append(seg) }; seg = [] }
        for c in texte.lowercased().replacingOccurrences(of: "\u{2019}", with: "'") + "." {
            if c.isLetter || c.isNumber || ((c == "-" || c == "'") && !courant.isEmpty) { courant.append(c) }
            else if c == " " || c == "\u{00A0}" { mot() }
            else { fin() }
        }
        return res
    }

    /// Les pièces d'un mot : « t'inquiète » → « t » « inquiète » (pour savoir s'il contient un mot de contenu).
    private static func cœur(_ mot: String) -> String { ApprentissageCorrections.sansElision(mot) }

    /// `textes` : les dictées de l'historique (la plus récente d'abord). `existants` : mots déjà dans mots.txt (pliés ou non, ils sont pliés ici).
    /// `estConnu` : correcteur orthographique du Mac. Rend au plus `maximum` expressions, avec le nombre de dictées où elles apparaissent.
    public static func extraire(textes: [String], existants: [String] = [], exclues: [String] = [], estConnu: (String) -> Bool, maximum: Int = ListeExpressions.maximum) -> [(texte: String, dictees: Int)] {
        let pliesExistants = Set(existants.map(ClePhonetique.plier)), pliesExclues = Set(exclues.map(ClePhonetique.plier))
        var frequence: [String: Int] = [:]
        var longueur: [String: Int] = [:]
        for t in textes {
            var vus = Set<String>()
            for seg in segments(t) {
                for n in 1...3 where seg.count >= n {
                    for i in 0...(seg.count - n) {
                        let gram = seg[i..<(i + n)].joined(separator: " ")
                        if vus.insert(gram).inserted { longueur[gram] = n }
                    }
                }
            }
            for g in vus { frequence[g, default: 0] += 1 }
        }
        var candidats: [(String, Int, Int)] = []   // texte, dictées, nombre de mots
        for (gram, df) in frequence where df >= 3 {
            let n = longueur[gram] ?? 1
            let mots = gram.split(separator: " ").map(String.init)
            if gram.count > 32 || gram.contains(where: \.isNumber) { continue }
            let contenu = mots.filter { m in let c = ClePhonetique.plier(cœur(m)); return c.count >= 3 && !MotsDuQuotidien.courants.contains(c) }
            if contenu.isEmpty { continue }
            let pliee = ClePhonetique.plier(gram)
            if pliesExistants.contains(pliee) || pliesExclues.contains(pliee) { continue }
            let familier = mots.contains { m in
                let c = ClePhonetique.plier(cœur(m)), entier = ClePhonetique.plier(m)
                return familiers.contains(c) || familiers.contains(entier) || (c.count >= 4 && !estConnu(cœur(m)) && !estConnu(m))
            }
            if n == 1 {
                // un mot seul : seulement un mot familier ou inconnu du correcteur (jamais un mot ordinaire fréquent)
                guard familier, contenu.count == 1, cœur(mots[0]).count >= 3 else { continue }
            } else {
                guard (familier && df >= 3) || df >= 6 else { continue }
                // une suite qui commence ou finit par un mot de liaison seul (« de », « que »…) est une coupe, pas une expression
                guard let a = mots.first, let b = mots.last, !coupeurs.contains(a), !coupeurs.contains(b) else { continue }
            }
            candidats.append((gram, df, n))
        }
        // du plus long au plus court : un sous-ensemble presque aussi fréquent qu'une suite plus longue est retiré
        candidats.sort { $0.2 != $1.2 ? $0.2 > $1.2 : ($0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0) }
        var gardes: [(String, Int, Int)] = []
        for c in candidats {
            if gardes.contains(where: { g in g.2 > c.2 && (" " + g.0 + " ").contains(" " + c.0 + " ") && Double(g.1) >= 0.7 * Double(c.1) }) { continue }
            gardes.append(c)
        }
        gardes.sort { let a = Double($0.1) * (1 + 0.5 * Double($0.2 - 1)), b = Double($1.1) * (1 + 0.5 * Double($1.2 - 1)); return a != b ? a > b : $0.0 < $1.0 }
        return gardes.prefix(maximum).map { ($0.0, $0.1) }
    }

    private static let coupeurs: Set<String> = ["de", "du", "des", "le", "la", "les", "un", "une", "que", "qui", "et", "ou", "à", "a", "au", "en", "dans", "sur", "pour", "par", "avec", "ne", "d'", "l'", "je", "tu", "il"]
}
