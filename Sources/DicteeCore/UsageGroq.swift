import Foundation

// L'usage de Groq pour la transcription (Hugues, 12/11 : « j'ai peur un jour d'arriver à mes limites sur Groq »). Logique pure : l'heure
// est toujours passée en paramètre, rien ne part sur le réseau, rien n'est lu sur le disque ici.
//
// Ce que Groq dit vraiment (relevé le 12/11/2026) :
// - console.groq.com/docs/rate-limits, offre gratuite : whisper-large-v3 ET whisper-large-v3-turbo, chacun 20 requêtes par minute,
//   2 000 par jour, 7 200 secondes d'audio par heure (ASH) et 28 800 par jour (ASD, soit 480 min) ; les limites s'appliquent à
//   l'organisation (tous les usages de la même clé comptent) ;
// - en-têtes de chaque réponse : x-ratelimit-limit-requests et x-ratelimit-remaining-requests (par JOUR), x-ratelimit-reset-requests
//   (« 2m59.56s ») ; les -tokens sont par minute et ne disent rien de l'audio ; retry-after (secondes) seulement sur une 429 ;
//   AUCUN en-tête ne donne les secondes d'audio : on les compte ici, à l'envoi ;
// - console.groq.com/docs/speech-to-text : une requête de moins de 10 s est facturée 10 s. On compte donc au moins 10 s par requête
//   (envois anticipés et requêtes de secours compris : Groq les reçoit toutes), pour ne jamais se croire plus loin de la limite qu'on l'est.

/// Les limites d'un modèle de transcription de Groq (offre gratuite).
public struct LimitesWhisper: Equatable, Sendable {
    public var requetesMinute: Int
    public var requetesJour: Int
    public var secondesHeure: Double
    public var secondesJour: Double
    public init(requetesMinute: Int = 20, requetesJour: Int = 2000, secondesHeure: Double = 7200, secondesJour: Double = 28_800) {
        self.requetesMinute = requetesMinute; self.requetesJour = requetesJour; self.secondesHeure = secondesHeure; self.secondesJour = secondesJour
    }
    /// Les mêmes pour whisper-large-v3 et whisper-large-v3-turbo (chacun compté à part).
    public static let gratuit = LimitesWhisper()
    /// Une requête plus courte est facturée 10 s.
    public static let factureMinimum: Double = 10
}

/// Une requête de transcription envoyée : quand, combien de secondes comptées (au moins 10), quel modèle.
public struct EnvoiAudio: Codable, Equatable, Sendable {
    public var instant: Date
    public var secondes: Double
    public var modele: String
    public init(instant: Date, secondes: Double, modele: String) { self.instant = instant; self.secondes = secondes; self.modele = modele }
}

/// La limite que Groq a nommée dans le corps d'une 429 (« … seconds of audio per hour (ASH): Limit 7200, Used 7195, Requested 12 »).
public enum CauseLimite: String, Codable, Sendable {
    case requetesMinute, requetesJour, audioHeure, audioJour, autre

    /// Lit le message d'erreur de Groq : le sigle entre parenthèses d'abord, sinon les mots.
    public static func depuis(message: String) -> CauseLimite {
        let m = message.lowercased()
        if m.contains("(ash)") || (m.contains("audio") && m.contains("per hour")) { return .audioHeure }
        if m.contains("(asd)") || (m.contains("audio") && m.contains("per day")) { return .audioJour }
        if m.contains("(rpm)") || m.contains("requests per minute") { return .requetesMinute }
        if m.contains("(rpd)") || m.contains("requests per day") { return .requetesJour }
        return .autre
    }

    /// « Limit 7200, Used 7195 » : ce que Groq a déjà compté (nil si le message ne le dit pas).
    public static func utilise(message: String) -> Double? {
        guard let r = message.range(of: "Used ", options: .caseInsensitive) else { return nil }
        let chiffres = message[r.upperBound...].prefix { $0.isNumber || $0 == "." }
        return Double(chiffres)
    }
}

/// Ce que la dernière réponse de Groq a dit pour un modèle.
public struct MargeLue: Codable, Equatable, Sendable {
    public var lueLe: Date
    /// x-ratelimit-limit-requests et x-ratelimit-remaining-requests : les requêtes du JOUR.
    public var limiteRequetes: Int?
    public var restantRequetes: Int?
    /// Après une 429 : plus rien avant cette date (retry-after), et la limite nommée par Groq.
    public var pauseJusqua: Date?
    public var cause: CauseLimite?
    /// Les secondes d'audio que Groq dit avoir déjà comptées (corps de la 429, limite à l'heure ou au jour).
    public var audioUtilise: Double?
    public init(lueLe: Date) { self.lueLe = lueLe }
}

/// Ce qui est gardé sur le Mac (un petit fichier, jamais envoyé ailleurs) : les envois des dernières 24 h et la dernière marge lue par modèle.
public struct CompteurGroq: Codable, Equatable, Sendable {
    public private(set) var envois: [EnvoiAudio] = []
    public private(set) var marges: [String: MargeLue] = [:]
    public init() {}

    static let jour: Double = 86_400, heure: Double = 3600

    /// Une requête de transcription part (même si elle sera annulée ou jetée : Groq la reçoit et la compte).
    public mutating func noterEnvoi(secondesAudio: Double, modele: String, a t: Date) {
        envois.append(EnvoiAudio(instant: t, secondes: max(LimitesWhisper.factureMinimum, secondesAudio), modele: modele))
        elaguer(a: t)
    }

    /// La réponse est arrivée : les en-têtes (`entete` rend la valeur d'un en-tête, sans casse), et pour une 429 le message d'erreur.
    public mutating func noterReponse(modele: String, statut: Int, entete: (String) -> String?, messageErreur: String?, a t: Date) {
        var m = marges[modele] ?? MargeLue(lueLe: t)
        m.lueLe = t
        if let v = entete("x-ratelimit-limit-requests").flatMap({ Int($0.trimmingCharacters(in: .whitespaces)) }) { m.limiteRequetes = v }
        if let v = entete("x-ratelimit-remaining-requests").flatMap({ Int($0.trimmingCharacters(in: .whitespaces)) }) { m.restantRequetes = v }
        if statut == 429 {
            let attente = BudgetRequetes.secondes(deEnTete: entete("retry-after")) ?? 30
            m.pauseJusqua = t.addingTimeInterval(max(1, attente))
            m.cause = messageErreur.map(CauseLimite.depuis(message:)) ?? .autre
            m.audioUtilise = messageErreur.flatMap(CauseLimite.utilise(message:))
        } else if statut == 200 {
            // Groq a répondu : la pause est finie (même si sa date n'est pas encore passée)
            m.pauseJusqua = nil; m.cause = nil; m.audioUtilise = nil
        }
        marges[modele] = m
    }

    /// Oublie ce qui a plus de 24 h.
    public mutating func elaguer(a t: Date) {
        envois.removeAll { t.timeIntervalSince($0.instant) >= Self.jour || $0.instant > t.addingTimeInterval(60) }
    }

    /// Les secondes comptées pour `modele` sur les `fenetre` dernières secondes.
    public func secondes(modele: String, fenetre: Double, a t: Date) -> Double {
        envois.filter { $0.modele == modele && t.timeIntervalSince($0.instant) < fenetre && $0.instant <= t.addingTimeInterval(60) }
            .reduce(0) { $0 + $1.secondes }
    }

    /// Le bilan d'un modèle maintenant.
    public func bilan(modele: String, limites l: LimitesWhisper = .gratuit, a t: Date) -> BilanGroq {
        var b = BilanGroq(modele: modele, limites: l)
        let fenetreJour = envois.filter { $0.modele == modele && t.timeIntervalSince($0.instant) < Self.jour && $0.instant <= t.addingTimeInterval(60) }
        b.secondesJour = fenetreJour.reduce(0) { $0 + $1.secondes }
        b.secondesHeure = fenetreJour.filter { t.timeIntervalSince($0.instant) < Self.heure }.reduce(0) { $0 + $1.secondes }
        let marge = marges[modele]
        // Groq a dit combien il avait compté (429) : on le croit s'il en compte plus que nous (une autre app avec la même clé)
        if let m = marge, let u = m.audioUtilise, let p = m.pauseJusqua, p > t {
            if m.cause == .audioJour { b.secondesJour = max(b.secondesJour, u) }
            if m.cause == .audioHeure { b.secondesHeure = max(b.secondesHeure, u) }
        }
        // la marge des requêtes du jour : seulement si elle est fraîche (moins d'une heure ; le compteur de Groq se remplit ensuite)
        if let m = marge, t.timeIntervalSince(m.lueLe) < Self.heure, let r = m.restantRequetes {
            b.requetesRestantes = r
            b.requetesLimite = m.limiteRequetes ?? l.requetesJour
        }
        if let m = marge, let p = m.pauseJusqua, p > t {
            b.pauseJusqua = p
            b.cause = m.cause
        }
        // sans 429, nos propres comptes au bout de la limite valent une pause : jusqu'à ce que le plus ancien envoi sorte de la fenêtre
        if b.pauseJusqua == nil {
            if b.secondesHeure >= l.secondesHeure, let premier = fenetreJour.filter({ t.timeIntervalSince($0.instant) < Self.heure }).map(\.instant).min() {
                b.pauseJusqua = premier.addingTimeInterval(Self.heure); b.cause = .audioHeure
            } else if b.secondesJour >= l.secondesJour, let premier = fenetreJour.map(\.instant).min() {
                b.pauseJusqua = premier.addingTimeInterval(Self.jour); b.cause = .audioJour
            }
        }
        return b
    }

    public func donnees() -> Data? {
        let e = JSONEncoder(); e.dateEncodingStrategy = .secondsSince1970
        return try? e.encode(self)
    }
    public static func depuis(_ d: Data) -> CompteurGroq? {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .secondsSince1970
        return try? dec.decode(CompteurGroq.self, from: d)
    }
}

/// Où en est un modèle : ce qui est compté, ce que Groq a dit, et la marge qui reste.
public struct BilanGroq: Equatable, Sendable {
    public enum Limitant: Equatable, Sendable { case jour, heure, requetes }

    public var modele: String
    public var limites: LimitesWhisper
    public var secondesJour: Double = 0
    public var secondesHeure: Double = 0
    public var requetesRestantes: Int?
    public var requetesLimite: Int?
    public var pauseJusqua: Date?
    public var cause: CauseLimite?

    public init(modele: String, limites: LimitesWhisper = .gratuit) { self.modele = modele; self.limites = limites }

    /// Ce qui reste de chaque limite (0 à 1), la plus serrée d'abord.
    public var marges: [(Limitant, Double)] {
        var r: [(Limitant, Double)] = [(.jour, 1 - secondesJour / limites.secondesJour), (.heure, 1 - secondesHeure / limites.secondesHeure)]
        if let rr = requetesRestantes, let rl = requetesLimite, rl > 0 { r.append((.requetes, Double(rr) / Double(rl))) }
        return r.map { ($0.0, min(1, max(0, $0.1))) }.sorted { $0.1 < $1.1 }
    }
    /// La marge la plus serrée (0 à 1) et laquelle.
    public var fractionRestante: Double { pauseJusqua != nil ? 0 : (marges.first?.1 ?? 1) }
    public var limitant: Limitant { marges.first?.0 ?? .jour }
    public var niveau: NiveauGroq {
        if pauseJusqua != nil { return .epuise }
        return fractionRestante < NiveauGroq.seuilBas ? .bas : .ok
    }
    /// « 42 » (minutes comptées sur 24 h, à la minute du dessus) et « 480 ».
    public var minutesJour: Int { Int((secondesJour / 60).rounded(.up)) }
    public var limiteMinutesJour: Int { Int(limites.secondesJour / 60) }
    public var minutesHeure: Int { Int((secondesHeure / 60).rounded(.up)) }
    public var limiteMinutesHeure: Int { Int(limites.secondesHeure / 60) }
}

public enum NiveauGroq: Equatable, Sendable {
    case ok, bas, epuise
    /// En dessous de 15 % de marge, l'îlot prévient.
    public static let seuilBas = 0.15
}

/// L'état de Groq pour la dictée : le modèle réglé, et le turbo qui prend le relais quand large-v3 est limité (ses limites sont à part).
public struct EtatGroq: Equatable, Sendable {
    public var principal: BilanGroq
    /// Le turbo, quand le modèle réglé est large-v3 (sinon nil : rien ne prend le relais chez Groq).
    public var secours: BilanGroq?

    public init(principal: BilanGroq, secours: BilanGroq?) { self.principal = principal; self.secours = secours }

    /// Calcule l'état depuis le compteur.
    public static func calculer(_ c: CompteurGroq, modele: String, secours: String?, a t: Date) -> EtatGroq {
        EtatGroq(principal: c.bilan(modele: modele, a: t), secours: secours.map { c.bilan(modele: $0, a: t) })
    }

    /// Le modèle réglé est en pause, le turbo répond encore.
    public var relaisTurbo: Bool { principal.niveau == .epuise && (secours.map { $0.niveau != .epuise } ?? false) }
    public var niveau: NiveauGroq {
        if principal.niveau != .epuise { return principal.niveau }
        return relaisTurbo ? .bas : .epuise
    }
    /// Quand Groq répondra de nouveau (le premier des deux modèles libéré), si tout est en pause.
    public var pauseJusqua: Date? {
        guard niveau == .epuise else { return nil }
        return [principal.pauseJusqua, secours?.pauseJusqua].compactMap { $0 }.min()
    }
    /// La part utilisée de la limite la plus serrée du modèle qui transcrit (0 à 1) : l'anneau de la jauge.
    public var utilise: Double {
        if niveau == .epuise { return 1 }
        return 1 - (relaisTurbo ? (secours?.fractionRestante ?? 0) : principal.fractionRestante)
    }
}

/// Les mots de l'usage de Groq (Réglages, îlot), au tutoiement, sans jargon.
public enum TexteGroq {
    /// « 15:00 », ou « demain 9:12 » si ce n'est pas aujourd'hui.
    public static func quand(_ d: Date, a t: Date, calendrier: Calendar = .current) -> String {
        let h = FormatIlot.heure(d, calendrier: calendrier)
        return calendrier.isDate(d, inSameDayAs: t) ? h : "demain " + h
    }

    /// La ligne des Réglages : « Groq aujourd'hui : 42 min sur 480 · tout va bien ».
    public static func ligne(_ e: EtatGroq, a t: Date, calendrier: Calendar = .current) -> String {
        let p = e.principal
        return "Groq aujourd\u{2019}hui : \(p.minutesJour) min sur \(p.limiteMinutesJour) \u{00B7} " + etat(e, a: t, calendrier: calendrier)
    }

    /// Ce qui suit le compte : « tout va bien », « il reste 12 % », « le turbo prend le relais », « en pause jusqu'à 15:00 ».
    public static func etat(_ e: EtatGroq, a t: Date, calendrier: Calendar = .current) -> String {
        if let p = e.pauseJusqua { return "en pause jusqu\u{2019}à " + quand(p, a: t, calendrier: calendrier) }
        if e.relaisTurbo { return "large-v3 en pause, le turbo prend le relais" }
        switch e.niveau {
        case .ok: return "tout va bien"
        case .bas, .epuise: return "il reste \(pourcent(e.principal.fractionRestante)) %"
        }
    }

    /// Sous le rond de la page Outils : « 42 min », « Reste 12 % », « Turbo », « Pause 15:00 ».
    public static func court(_ e: EtatGroq, a t: Date, calendrier: Calendar = .current) -> String {
        if let p = e.pauseJusqua { return "Pause " + (calendrier.isDate(p, inSameDayAs: t) ? FormatIlot.heure(p, calendrier: calendrier) : "demain") }
        if e.relaisTurbo { return "Turbo" }
        if e.niveau == .bas { return "Reste \(pourcent(e.principal.fractionRestante)) %" }
        return "\(e.principal.minutesJour) min"
    }

    /// Le détail (le clic sur la jauge de l'îlot) : « Groq aujourd'hui : 42 min sur 480 », puis « Tout va bien · cette heure : 3 min sur 120 ».
    public static func detail(_ e: EtatGroq, a t: Date, calendrier: Calendar = .current) -> (titre: String, sousTitre: String) {
        let p = e.principal
        let etat = etat(e, a: t, calendrier: calendrier)
        return ("Groq aujourd\u{2019}hui : \(p.minutesJour) min sur \(p.limiteMinutesJour)",
                etat.prefix(1).uppercased() + etat.dropFirst() + " \u{00B7} cette heure : \(p.minutesHeure) min sur \(p.limiteMinutesHeure)")
    }

    /// La note sous la ligne des Réglages : ce qui est compté, et la marge des requêtes lue dans la dernière réponse de Groq.
    public static func note(_ e: EtatGroq) -> String {
        let p = e.principal
        var n = "Compté sur ce Mac, sur les dernières 24 h. Cette heure : \(p.minutesHeure) min sur \(p.limiteMinutesHeure)."
        if let r = p.requetesRestantes, let l = p.requetesLimite { n += " Requêtes : \(milliers(r)) sur \(milliers(l)) (dit par Groq)." }
        return n
    }

    /// « 12 » : arrondi vers le bas (jamais « 15 % » quand il en reste 14,6).
    public static func pourcent(_ f: Double) -> Int { Int((max(0, min(1, f)) * 100).rounded(.down)) }

    /// « 1 940 » (espace fine insécable).
    public static func milliers(_ n: Int) -> String {
        let s = String(n)
        guard s.count > 3 else { return s }
        var r = ""
        for (i, ch) in s.enumerated() { if i > 0, (s.count - i) % 3 == 0 { r.append("\u{202F}") }; r.append(ch) }
        return r
    }
}

/// Les annonces de l'îlot sur la limite : une seule fois par passage (sous 15 %, puis la limite atteinte), jamais répétées à chaque réponse.
public struct AlerteGroq: Equatable, Sendable {
    public enum Annonce: Equatable, Sendable {
        /// « Groq : il reste 12 % » · « 422 min sur 480 aujourd'hui ».
        case bas(titre: String, sousTitre: String)
        /// « Groq en pause jusqu'à 15:00 » · « Dictée sur le Mac ».
        case epuise(titre: String, sousTitre: String)
        public var titre: String { switch self { case .bas(let t, _), .epuise(let t, _): return t } }
        public var sousTitre: String { switch self { case .bas(_, let s), .epuise(_, let s): return s } }
    }

    /// Ce qui a déjà été dit : « bas » une fois tant qu'on ne remonte pas au-dessus du seuil ; « épuisé » une fois par pause.
    public private(set) var basDit = false
    public private(set) var pauseDite: Date?
    public init() {}

    /// Le nouvel état : faut-il annoncer quelque chose ?
    public mutating func apres(_ e: EtatGroq, a t: Date, calendrier: Calendar = .current) -> Annonce? {
        switch e.niveau {
        case .ok:
            basDit = false; pauseDite = nil
            return nil
        case .bas:
            pauseDite = nil
            guard !basDit else { return nil }
            basDit = true
            if e.relaisTurbo {
                let fin = e.principal.pauseJusqua.map { " jusqu\u{2019}à " + TexteGroq.quand($0, a: t, calendrier: calendrier) } ?? ""
                return .bas(titre: "Groq : large-v3 en pause" + fin, sousTitre: "Le turbo prend le relais")
            }
            return .bas(titre: "Groq : il reste \(TexteGroq.pourcent(e.principal.fractionRestante)) %", sousTitre: Self.sousTitreBas(e.principal))
        case .epuise:
            basDit = true
            let p = e.pauseJusqua
            // une même pause (à la minute près : retry-after bouge d'une réponse à l'autre) ne s'annonce qu'une fois
            if let d = pauseDite, let p, abs(d.timeIntervalSince(p)) < 120 || p < d { return nil }
            if pauseDite != nil, p == nil { return nil }
            pauseDite = p ?? t
            let titre = "Groq en pause" + (p.map { " jusqu\u{2019}à " + TexteGroq.quand($0, a: t, calendrier: calendrier) } ?? "")
            return .epuise(titre: titre, sousTitre: "Dictée sur le Mac")
        }
    }

    static func sousTitreBas(_ b: BilanGroq) -> String {
        switch b.limitant {
        case .jour: return "\(b.minutesJour) min sur \(b.limiteMinutesJour) aujourd\u{2019}hui"
        case .heure: return "\(b.minutesHeure) min sur \(b.limiteMinutesHeure) cette heure"
        case .requetes: return "\(TexteGroq.milliers(b.requetesRestantes ?? 0)) requêtes restantes aujourd\u{2019}hui"
        }
    }
}

/// Pourquoi Groq n'a pas donné le texte d'une dictée.
public enum EchecGroq: String, Equatable, Sendable {
    case pasDeCle, limite, reseau, panne, delai, autre

    /// D'après l'erreur de la requête : code HTTP (429 limite, 5xx panne), réseau, clé absente.
    public static func depuis(codeHTTP: Int?, reseau: Bool, pasDeCle: Bool) -> EchecGroq {
        if pasDeCle { return .pasDeCle }
        if reseau { return .reseau }
        guard let c = codeHTTP else { return .autre }
        if c == 429 { return .limite }
        if c >= 500 { return .panne }
        return .autre
    }
}

/// Le relais de la dictée sur le Mac (reconnaissance vocale de macOS, sur l'appareil) quand Groq ne répond pas.
public enum RelaisDictee {
    /// Chaque dictée commence par Groq quand la clé est là, même juste après un relais : la dictée suivante retente toujours Groq.
    public static func essayerGroq(cleDisponible: Bool) -> Bool { cleDisponible }

    /// Le texte du Mac sert-il ? Groq en échec (ou trop lent), le relais permis dans les Réglages, et un texte non vide.
    public static func utiliserLeMac(echec: EchecGroq?, relaisPermis: Bool, texteDuMac: String) -> Bool {
        echec != nil && relaisPermis && !texteDuMac.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Ce que la dictée attend au plus le texte de la reconnaissance du Mac, une fois Groq en échec.
    public static let attenteDuMac: Double = 1.5

    /// Le texte de la reconnaissance du Mac, ou "" s'il n'est pas là après `attente` secondes : la dictée rend toujours la main à temps,
    /// même si la reconnaissance ne finit jamais (elle continue seule, son texte est ignoré).
    public static func texteDuMac(attente: Double = attenteDuMac, _ terminer: @escaping @Sendable () async -> String) async -> String {
        await Premiere<String>.avantDelai(attente, parDefaut: "", terminer)
    }

    /// Ce que l'îlot dit de la raison (sous « Dicté sur le Mac »).
    public static func raison(_ e: EchecGroq, pauseJusqua: Date?, a t: Date, calendrier: Calendar = .current) -> String {
        switch e {
        case .limite: return "Groq en pause" + (pauseJusqua.map { " jusqu\u{2019}à " + TexteGroq.quand($0, a: t, calendrier: calendrier) } ?? "")
        case .reseau: return "Pas de réseau"
        case .panne: return "Groq ne répond pas"
        case .pasDeCle: return "Clé Groq absente"
        case .delai: return "Groq trop lent"
        case .autre: return "Groq n\u{2019}a pas répondu"
        }
    }

    /// Le signe dans l'îlot après une dictée passée par le Mac : la première fois (ou pour une autre raison), un bandeau qui dit pourquoi ;
    /// ensuite, seulement « Mac » dans les ailes, discret. La limite atteinte a déjà son annonce (« Groq en pause jusqu'à 15:00 ») :
    /// pour elle, les ailes seules.
    public enum Signe: Equatable, Sendable {
        case bandeau(titre: String, sousTitre: String)
        case ailes
    }

    /// Ce qui a été dit depuis la dernière dictée réussie par Groq.
    public struct Suivi: Equatable, Sendable {
        public private(set) var dit: EchecGroq?
        public init() {}
        public mutating func apresRelais(_ e: EchecGroq, pauseJusqua: Date?, a t: Date, calendrier: Calendar = .current) -> Signe {
            defer { dit = e }
            if e == .limite || dit == e { return .ailes }
            return .bandeau(titre: "Dicté sur le Mac", sousTitre: RelaisDictee.raison(e, pauseJusqua: pauseJusqua, a: t, calendrier: calendrier))
        }
        /// Groq a de nouveau donné le texte : le prochain relais se dira en entier.
        public mutating func apresGroq() { dit = nil }
    }
}
