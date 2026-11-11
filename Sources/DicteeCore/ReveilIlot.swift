import Foundation

// Le réveil de l'îlot (maquette design/maquettes/ilot-bibliotheque.html, étapes 7 à 9) : logique pure, sans interface.
// Un 2e onglet de la case Minuteur du Centre (7:00 · 8:00 · 9:00 · Autre…), ou à la voix : « réveille-moi à 9 h ». Replié, l'îlot garde
// le réveil et l'heure dans ses ailes ; à l'heure, il sonne comme le minuteur fini (« Encore 10 min » ou « OK »).
// Comme le minuteur, il ne compte rien : il garde l'heure de sa sonnerie, et un seul réveil est programmé pour elle.

/// Un réveil réglé (un seul à la fois). Gardé dans ~/Library/Application Support/Dictee/reveil.json : il survit à un redémarrage de Verbe.
public struct ReveilIlot: Codable, Equatable, Sendable {
    /// L'heure réglée (« 9:00 »), en heure locale.
    public var heure: Int
    public var minute: Int
    /// Quand il sonnera : la prochaine fois que l'heure revient, ou 10 minutes après « Encore 10 min ».
    public var sonnerie: Date
    /// Il a été repoussé (« Encore 10 min ») : l'aile montre l'heure de la sonnerie (« 9:10 »), pas l'heure réglée.
    public var repousse: Bool

    public init(heure: Int, minute: Int, apres maintenant: Date, calendrier: Calendar = .current) {
        self.heure = min(23, max(0, heure)); self.minute = min(59, max(0, minute))
        sonnerie = Self.prochaine(heure: self.heure, minute: self.minute, apres: maintenant, calendrier: calendrier)
        repousse = false
    }

    /// Les heures proposées d'un clic (maquette : 7:00 · 8:00 · 9:00, puis « Autre… »).
    public static let proposees: [(heure: Int, minute: Int)] = [(7, 0), (8, 0), (9, 0)]
    /// « Autre… » : − et + changent l'heure de 15 minutes (pas de clavier dans l'îlot).
    public static let pas = 15
    /// « Encore 10 min ».
    public static let encore: Double = 600
    /// Un réveil dont l'heure est passée depuis plus longtemps (Mac éteint ou endormi toute la matinée, Verbe fermé) ne sonne plus :
    /// il est oublié, rien ne retentit à midi pour un réveil de 7 h.
    public static let retardMax: Double = 2 * 3600

    /// La prochaine fois que `heure:minute` revient, strictement après `maintenant` (le jour même si l'heure n'est pas passée, sinon
    /// le lendemain ; un changement d'heure est compté par le calendrier).
    public static func prochaine(heure: Int, minute: Int, apres maintenant: Date, calendrier: Calendar = .current) -> Date {
        var c = DateComponents(); c.hour = heure; c.minute = minute; c.second = 0
        return calendrier.nextDate(after: maintenant, matching: c, matchingPolicy: .nextTime, direction: .forward)
            ?? maintenant.addingTimeInterval(24 * 3600)
    }

    /// « 9:00 » : l'heure qu'on montre (celle de la sonnerie une fois repoussé).
    public func libelle(calendrier: Calendar = .current) -> String {
        repousse ? FormatIlot.heure(sonnerie, calendrier: calendrier) : Self.texte(heure, minute)
    }
    public static func texte(_ h: Int, _ m: Int) -> String { String(format: "%d:%02d", h, m) }

    /// Il est l'heure (ou l'heure est passée, pendant la veille du Mac ou Verbe fermé).
    public func du(a maintenant: Date) -> Bool { sonnerie <= maintenant }
    /// Passé depuis trop longtemps : on ne sonne plus.
    public func perime(a maintenant: Date) -> Bool { maintenant.timeIntervalSince(sonnerie) > Self.retardMax }

    /// « Encore 10 min » : il sonnera de nouveau 10 minutes après maintenant.
    public mutating func repousser(a maintenant: Date, de secondes: Double = ReveilIlot.encore) {
        sonnerie = maintenant.addingTimeInterval(secondes)
        repousse = true
    }

    /// Une heure choisie avec − et + (« Autre… ») : `pas` minutes de plus ou de moins, sur 24 heures, toujours sur un multiple du pas.
    public static func decaler(heure h: Int, minute m: Int, de n: Int) -> (heure: Int, minute: Int) {
        let total = h * 60 + m
        let cale = n > 0 ? (total / pas + n) * pas : ((total + pas - 1) / pas + n) * pas
        let r = ((cale % 1440) + 1440) % 1440
        return (r / 60, r % 60)
    }

    // MARK: ce que l'îlot écrit

    private static func francais(_ calendrier: Calendar, _ format: String, _ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR"); f.calendar = calendrier; f.timeZone = calendrier.timeZone
        f.dateFormat = format
        return f.string(from: d)
    }
    /// « aujourd'hui », « demain », ou le jour (« jeudi ») au-delà.
    public static func jour(_ d: Date, maintenant: Date, calendrier: Calendar = .current) -> String {
        if calendrier.isDate(d, inSameDayAs: maintenant) { return "aujourd\u{2019}hui" }
        if let demain = calendrier.date(byAdding: .day, value: 1, to: maintenant), calendrier.isDate(d, inSameDayAs: demain) { return "demain" }
        return francais(calendrier, "EEEE", d)
    }
    /// Le bandeau « Réveil réglé · 9:00 » : « Demain, jeudi · rien n'a été collé » (la commande dictée n'a rien écrit dans l'app).
    public func ligneReglee(maintenant: Date, calendrier: Calendar = .current) -> String {
        let j = Self.jour(sonnerie, maintenant: maintenant, calendrier: calendrier)
        let nom = Self.francais(calendrier, "EEEE", sonnerie)
        let quand = j == nom ? nom.prefix(1).uppercased() + nom.dropFirst() : j.prefix(1).uppercased() + j.dropFirst() + ", " + nom
        return quand + " \u{00B7} rien n\u{2019}a été collé"
    }
    /// L'alerte : « Bonjour · jeudi 12 novembre » (« Bonsoir » à partir de 18 h).
    public static func salut(_ d: Date, calendrier: Calendar = .current) -> String {
        let h = calendrier.component(.hour, from: d)
        return (h >= 18 ? "Bonsoir" : "Bonjour") + " \u{00B7} " + francais(calendrier, "EEEE d MMMM", d)
    }

    // MARK: fichier

    public func donnees() -> Data? {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys]
        return try? e.encode(self)
    }
    public static func depuis(_ d: Data) -> ReveilIlot? {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        guard let r = try? dec.decode(ReveilIlot.self, from: d), (0...23).contains(r.heure), (0...59).contains(r.minute) else { return nil }
        return r
    }
}

extension AnalyseCommandeIlot {
    private static let heuresEnMots: [String: Int] = [
        "une": 1, "un": 1, "deux": 2, "trois": 3, "quatre": 4, "cinq": 5, "six": 6, "sept": 7, "huit": 8, "neuf": 9, "dix": 10, "onze": 11,
        "douze": 12, "treize": 13, "quatorze": 14, "quinze": 15, "seize": 16, "dix-sept": 17, "dix-huit": 18, "dix-neuf": 19, "vingt": 20,
        "vingt et une": 21, "vingt-et-une": 21, "vingt-deux": 22, "vingt deux": 22, "vingt-trois": 23, "vingt trois": 23,
    ]
    private static let minutesEnMots: [String: Int] = [
        "cinq": 5, "dix": 10, "quinze": 15, "vingt": 20, "vingt-cinq": 25, "vingt cinq": 25, "trente": 30, "trente-cinq": 35, "trente cinq": 35,
        "quarante": 40, "quarante-cinq": 45, "quarante cinq": 45, "cinquante": 50, "cinquante-cinq": 55, "cinquante cinq": 55,
    ]

    /// « réveille-moi à 9 h », « réveil à 7 h 30 », « réveille-moi demain à 7h30 », « mets un réveil à 8 heures », « réveille-moi à
    /// sept heures et demie ». La phrase ENTIÈRE doit être la commande (rien avant, rien après) : c'est la seule commande qu'on peut dicter
    /// l'îlot fermé (maquette, étape 8), elle ne doit jamais manger une phrase qui la contient.
    public static func reveil(_ texte: String) -> (heure: Int, minute: Int)? {
        var t = normaliser(texte).replacingOccurrences(of: "reveil", with: "réveil")
        var prefixe = false
        for debut in ["réveille-moi", "réveille moi", "réveillez-moi", "réveillez moi", "mets-moi un réveil", "mets moi un réveil", "mets un réveil",
                      "mets le réveil", "règle le réveil", "règle un réveil", "programme un réveil", "un réveil", "le réveil", "réveil",
                      "mets une alarme", "une alarme", "alarme"] where t.hasPrefix(debut) {
            t.removeFirst(debut.count); prefixe = true; break
        }
        guard prefixe else { return nil }
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: " ,"))
        // « demain » avant ou après l'heure, « du matin » après : le réveil sonne de toute façon à la prochaine fois que l'heure revient
        for mot in ["demain matin ", "demain "] where t.hasPrefix(mot) { t.removeFirst(mot.count); break }
        for liaison in ["à ", "pour ", "a "] where t.hasPrefix(liaison) { t.removeFirst(liaison.count); break }
        for fin in [" demain matin", " demain", " du matin", " ce matin"] where t.hasSuffix(fin) { t.removeLast(fin.count); break }
        t = t.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        if t == "midi" { return (12, 0) }
        if t == "minuit" { return (0, 0) }
        // les chiffres : « 9 h », « 9h30 », « 7 h 30 », « 9:30 », « 9 heures », « 9 heures 30 »
        if t.first?.isNumber == true {
            var s = t
            var demie = 0
            for (fin, m) in [(" et demie", 30), (" et quart", 15)] where s.hasSuffix(fin) { s.removeLast(fin.count); demie = m; break }
            if s.hasSuffix(" h") || s.hasSuffix("h") || s.hasSuffix("heure") || s.hasSuffix("heures") || s.contains("h") || s.contains(":") {
                guard let (h, m) = heureEtMinute(s) else { return nil }
                return demie > 0 && m == 0 ? (h, demie) : (h, m)
            }
            // « réveil à 7 » : une heure seule, sans unité
            if let h = Int(s), (0...23).contains(h), demie == 0 { return (h, 0) }
            return nil
        }
        // en toutes lettres : « sept heures », « sept heures trente », « sept heures et demie », « huit heures et quart »
        guard let r = t.range(of: " heure") else { return nil }
        guard let h = heuresEnMots[String(t[..<r.lowerBound])] else { return nil }
        var reste = String(t[r.upperBound...])
        if reste.hasPrefix("s") { reste.removeFirst() }
        reste = reste.trimmingCharacters(in: .whitespaces)
        switch reste {
        case "": return (h, 0)
        case "et demie", "et demi": return (h, 30)
        case "et quart": return (h, 15)
        default:
            if let m = minutesEnMots[reste] ?? Int(reste), (0...59).contains(m) { return (h, m) }
            return nil
        }
    }
}
