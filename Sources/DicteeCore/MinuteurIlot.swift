import Foundation

/// Le minuteur de l'îlot. Il ne compte rien lui-même : il garde une date de fin (ou, en pause, ce qu'il reste), donc aucune minuterie ne
/// tourne pour lui ; l'îlot ne se réveille qu'à sa fin, et une fois par seconde tant que le temps restant est affiché.
public struct MinuteurIlot: Equatable, Sendable {
    /// Durée totale en secondes (+1 min l'allonge).
    public private(set) var total: Double
    private var fin: Date?
    private var resteEnPause: Double?

    public init(minutes: Double, depuis: Date) {
        total = max(1, minutes * 60)
        fin = depuis.addingTimeInterval(total)
    }
    public init(secondes: Double, depuis: Date) {
        total = max(1, secondes)
        fin = depuis.addingTimeInterval(total)
    }

    public var enMarche: Bool { fin != nil }
    public var enPause: Bool { resteEnPause != nil }

    public func restant(a date: Date) -> Double {
        if let r = resteEnPause { return r }
        return max(0, (fin ?? date).timeIntervalSince(date))
    }
    public func termine(a date: Date) -> Bool { enMarche && restant(a: date) <= 0 }
    /// La part qu'il reste, 0…1 (l'anneau).
    public func fraction(a date: Date) -> Double { min(1, max(0, restant(a: date) / total)) }
    /// L'heure à laquelle il sonnera (maintenant + le restant).
    public func heureDeFin(a date: Date) -> Date { date.addingTimeInterval(restant(a: date)) }
    /// Le réveil de l'îlot : quand il faut regarder à nouveau (la fin), nil en pause.
    public var echeance: Date? { fin }

    public mutating func pause(a date: Date) {
        guard let f = fin else { return }
        resteEnPause = max(0, f.timeIntervalSince(date)); fin = nil
    }
    public mutating func reprendre(a date: Date) {
        guard let r = resteEnPause else { return }
        fin = date.addingTimeInterval(r); resteEnPause = nil
    }
    public mutating func basculer(a date: Date) { enMarche ? pause(a: date) : reprendre(a: date) }
    public mutating func ajouter(_ secondes: Double, a date: Date) {
        total += secondes
        if let f = fin { fin = f.addingTimeInterval(secondes) } else if let r = resteEnPause { resteEnPause = r + secondes }
    }
}

/// Les commandes qu'on peut dicter quand l'accueil de l'îlot est ouvert. Elles ne sont JAMAIS cherchées dans une dictée normale :
/// l'appelant ne les consulte que si l'accueil (ou le formulaire de rappel) est ouvert, donc une phrase dictée ailleurs n'est jamais mangée.
public enum CommandeIlot: Equatable, Sendable {
    case minuteur(secondes: Double)
    case rappel(texte: String, quand: Date)
}

public enum AnalyseCommandeIlot {
    private static let nombres: [String: Double] = [
        "un": 1, "une": 1, "deux": 2, "trois": 3, "quatre": 4, "cinq": 5, "six": 6, "sept": 7, "huit": 8, "neuf": 9, "dix": 10,
        "onze": 11, "douze": 12, "treize": 13, "quatorze": 14, "quinze": 15, "seize": 16, "vingt": 20, "trente": 30, "quarante": 40,
        "cinquante": 50, "soixante": 60, "quarante-cinq": 45, "vingt-cinq": 25, "quarante cinq": 45, "vingt cinq": 25,
        "dix-sept": 17, "dix-huit": 18, "dix-neuf": 19, "vingt et une": 21, "trente-cinq": 35, "cinquante-cinq": 55,
    ]

    /// Sans ponctuation de fin, espaces simples, apostrophes droites (la casse est gardée).
    static func nettoyer(_ texte: String) -> String {
        var t = texte.replacingOccurrences(of: "\u{2019}", with: "'")
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: " .!?,;:\n\t"))
        while t.contains("  ") { t = t.replacingOccurrences(of: "  ", with: " ") }
        return t
    }
    /// Pareil, en minuscules.
    static func normaliser(_ texte: String) -> String { nettoyer(texte).lowercased() }

    private static func nombre(_ s: String) -> Double? {
        if let d = Double(s.replacingOccurrences(of: ",", with: ".")) { return d }
        return nombres[s]
    }

    /// « minuteur 10 minutes », « mets un minuteur de 5 minutes », « minuteur d'une demi-heure », « minuteur 90 secondes ».
    public static func minuteur(_ texte: String) -> Double? {
        var t = normaliser(texte)
        for debut in ["mets-moi ", "mets moi ", "mets ", "lance ", "lance-moi ", "démarre ", "programme ", "fais-moi ", "fais "] where t.hasPrefix(debut) { t.removeFirst(debut.count); break }
        for debut in ["un ", "le "] where t.hasPrefix(debut) { t.removeFirst(debut.count); break }
        guard t.hasPrefix("minuteur") || t.hasPrefix("compte à rebours") || t.hasPrefix("timer") else { return nil }
        t = t.replacingOccurrences(of: "compte à rebours", with: "minuteur")
        t.removeFirst(t.hasPrefix("timer") ? 5 : 8)
        t = t.trimmingCharacters(in: .whitespaces)
        for liaison in ["de ", "d'", "pour ", "à "] where t.hasPrefix(liaison) { t.removeFirst(liaison.count); break }
        t = t.trimmingCharacters(in: .whitespaces)
        switch t {
        case "une demi-heure", "une demi heure", "demi-heure", "une demie heure": return 1800
        case "un quart d'heure", "quinze minutes": return 900
        case "trois quarts d'heure": return 2700
        default: break
        }
        let mots = t.split(separator: " ").map(String.init)
        guard mots.count >= 1 else { return nil }
        // « 1 heure 30 », « une heure et demie »
        var total = 0.0, i = 0, vu = false
        while i < mots.count {
            guard let n = nombre(mots[i]), i + 1 < mots.count else { return nil }
            let unite = mots[i + 1]
            if unite.hasPrefix("heure") || unite == "h" { total += n * 3600 }
            else if unite.hasPrefix("minute") || unite == "min" || unite == "mn" { total += n * 60 }
            else if unite.hasPrefix("seconde") || unite == "s" || unite == "sec" { total += n }
            else { return nil }
            vu = true
            i += 2
            if i < mots.count, mots[i] == "et" { i += 1 }
            if i < mots.count, mots[i] == "demie" || mots[i] == "demi" { total += 1800; i += 1 }
        }
        guard vu, total >= 1, total <= 24 * 3600 else { return nil }
        return total
    }

    /// « rappelle-moi d'appeler Paul à 15 h », « rappelle-moi de réserver la salle dans 20 minutes », « … demain à 9 h 30 ».
    public static func rappel(_ texte: String, maintenant: Date, calendrier: Calendar = .current, exigerPrefixe: Bool = true) -> (texte: String, quand: Date)? {
        // la casse du texte est gardée (« Appeler Paul ») : seuls les mots-clés sont cherchés sans casse
        var t = nettoyer(texte)
        var corps: String?
        for debut in ["rappelle-moi ", "rappelle moi ", "rappelez-moi ", "rappelle-moi, "] where t.lowercased().hasPrefix(debut) { corps = String(t.dropFirst(debut.count)); break }
        // dans le formulaire de rappel (l'accueil de l'îlot est ouvert), « appeler Paul à 15 h » suffit : le préfixe est facultatif
        if corps == nil, !exigerPrefixe { corps = t }
        guard var reste = corps else { return nil }
        for lien in ["de ", "d'", "que ", "qu'"] where reste.lowercased().hasPrefix(lien) { reste.removeFirst(lien.count); break }
        t = reste
        // « dans N minutes / heures »
        if let r = t.range(of: " dans ", options: [.backwards, .caseInsensitive]) {
            let duree = String(t[r.upperBound...]).trimmingCharacters(in: .whitespaces).lowercased()
            let mots = duree.split(separator: " ").map(String.init)
            if mots.count == 2, let n = nombre(mots[0]) {
                let u = mots[1]
                let secondes: Double? = u.hasPrefix("minute") || u == "min" ? n * 60 : (u.hasPrefix("heure") ? n * 3600 : nil)
                if let secondes, secondes > 0, secondes <= 24 * 3600 {
                    let sujet = majuscule(String(t[..<r.lowerBound]))
                    return sujet.isEmpty ? nil : (sujet, maintenant.addingTimeInterval(secondes))
                }
            }
        }
        // « à 15 h », « à 15h30 », « à 15 h 30 », « à 9:30 », avec « demain » possible
        var demain = false
        var avant = t
        if avant.lowercased().hasSuffix(" demain") { demain = true; avant.removeLast(7) }
        guard let r = avant.range(of: " à ", options: [.backwards, .caseInsensitive]) else { return nil }
        var heureTexte = String(avant[r.upperBound...]).trimmingCharacters(in: .whitespaces).lowercased()
        var sujetBrut = String(avant[..<r.lowerBound])
        if heureTexte.hasPrefix("demain ") { demain = true; heureTexte.removeFirst(7) }
        if sujetBrut.lowercased().hasSuffix(" demain") { demain = true; sujetBrut.removeLast(7) }
        guard let (h, m) = heureEtMinute(heureTexte) else { return nil }
        var c = calendrier.dateComponents([.year, .month, .day], from: maintenant)
        c.hour = h; c.minute = m; c.second = 0
        guard var quand = calendrier.date(from: c) else { return nil }
        if demain { quand = calendrier.date(byAdding: .day, value: 1, to: quand) ?? quand }
        else if quand <= maintenant { quand = calendrier.date(byAdding: .day, value: 1, to: quand) ?? quand }
        let sujet = majuscule(sujetBrut)
        return sujet.isEmpty ? nil : (sujet, quand)
    }

    static func heureEtMinute(_ s: String) -> (Int, Int)? {
        let nettoye = s.replacingOccurrences(of: "heures", with: "h").replacingOccurrences(of: "heure", with: "h").replacingOccurrences(of: ":", with: "h")
            .replacingOccurrences(of: " ", with: "")
        let parts = nettoye.split(separator: "h", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, let h = Int(parts[0]), (0...23).contains(h) else { return nil }
        if parts[1].isEmpty { return (h, 0) }
        guard let m = Int(parts[1]), (0...59).contains(m) else { return nil }
        return (h, m)
    }

    static func majuscule(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard let premier = t.first else { return "" }
        return premier.uppercased() + t.dropFirst()
    }

    /// La commande dictée, s'il y en a une (le minuteur d'abord, puis le rappel).
    public static func analyser(_ texte: String, maintenant: Date, calendrier: Calendar = .current, exigerPrefixe: Bool = true) -> CommandeIlot? {
        if let s = minuteur(texte) { return .minuteur(secondes: s) }
        if let r = rappel(texte, maintenant: maintenant, calendrier: calendrier, exigerPrefixe: exigerPrefixe) { return .rappel(texte: r.texte, quand: r.quand) }
        return nil
    }
}
