import Foundation

// La présentation « D'un coup d'œil » des notes de réunion : échéances en vraies dates, tri des actions, résumé d'une ligne de la
// liste, recherche et citations retrouvées dans la transcription. Logique pure (aucune interface, aucun réseau).

// MARK: échéances

/// Une échéance dite à voix haute (« jeudi », « avant le vingt novembre », « demain soir ») ramenée à une vraie date,
/// calculée à partir du jour de la réunion. Ce qui est trop vague (« bientôt », « la semaine prochaine ») ne donne pas de date.
public enum Echeance {
    public struct Analyse: Equatable, Sendable {
        /// « 2026-11-12 », ou nil quand l'expression ne désigne pas un jour précis.
        public var date: String?
        /// « avant le 20 novembre », « d'ici jeudi » : une limite, pas un jour prévu.
        public var avant: Bool
        /// « matin », « midi », « après-midi » ou « soir » quand c'est dit.
        public var moment: String?
    }

    private static let mois: [String: Int] = [
        "janvier": 1, "fevrier": 2, "mars": 3, "avril": 4, "mai": 5, "juin": 6, "juillet": 7, "aout": 8,
        "septembre": 9, "octobre": 10, "novembre": 11, "decembre": 12,
    ]
    /// Numéros de jour selon `Calendar` (dimanche = 1).
    private static let jours: [String: Int] = ["dimanche": 1, "lundi": 2, "mardi": 3, "mercredi": 4, "jeudi": 5, "vendredi": 6, "samedi": 7]
    private static let nombres: [String: Int] = [
        "un": 1, "une": 1, "premier": 1, "deux": 2, "trois": 3, "quatre": 4, "cinq": 5, "six": 6, "sept": 7, "huit": 8, "neuf": 9, "dix": 10,
        "onze": 11, "douze": 12, "treize": 13, "quatorze": 14, "quinze": 15, "seize": 16, "vingt": 20, "trente": 30,
    ]
    private static let joursAbreges = ["dim.", "lun.", "mar.", "mer.", "jeu.", "ven.", "sam."]
    private static let moisAbreges = ["janv.", "févr.", "mars", "avr.", "mai", "juin", "juil.", "août", "sept.", "oct.", "nov.", "déc."]

    private static func jetons(_ texte: String) -> [String] {
        FusionPistes.mots(texte).map { j in
            // « 1er » : le chiffre seul
            if j.hasSuffix("er"), let n = Int(j.dropLast(2)) { return String(n) }
            return j
        }
    }

    private static func valeur(_ j: ArraySlice<String>) -> Int? {
        var total = 0, vu = false
        for t in j {
            if t == "et" { continue }
            if let n = Int(t) ?? nombres[t] { total += n; vu = true } else { return nil }
        }
        return vu ? total : nil
    }

    private static func iso(_ d: Date, _ cal: Calendar) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Lit « 2026-11-12 » dans le calendrier donné.
    public static func date(_ iso: String, calendrier: Calendar = .current) -> Date? {
        let p = iso.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        guard let d = calendrier.date(from: DateComponents(year: p[0], month: p[1], day: p[2])) else { return nil }
        let c = calendrier.dateComponents([.year, .month, .day], from: d)
        return c.year == p[0] && c.month == p[1] && c.day == p[2] ? d : nil
    }

    /// Ce que dit `quand`, rapporté au jour de la réunion (`debut`). Un nom de jour désigne le jour suivant la réunion
    /// (la réunion un lundi et « jeudi » : le jeudi de la même semaine ; un jeudi et « jeudi » : le jeudi d'après).
    public static func analyser(_ quand: String, depuis debut: Date, calendrier: Calendar = .current) -> Analyse {
        let j = jetons(quand)
        func suit(_ a: String, _ b: String) -> Bool { zip(j, j.dropFirst()).contains { $0 == a && $1 == b } }
        let avant = j.contains("avant") || suit("d", "ici") || j.contains("jusqu")
        var moment: String?
        if suit("apres", "midi") { moment = "après-midi" }
        else if j.contains("soir") { moment = "soir" }
        else if j.contains("matin") { moment = "matin" }
        else if j.contains("midi") { moment = "midi" }

        let cal = calendrier
        let aujourdhui = cal.startOfDay(for: debut)
        func plus(_ n: Int) -> String? { cal.date(byAdding: .day, value: n, to: aujourdhui).map { iso($0, cal) } }
        func resultat(_ date: String?) -> Analyse { Analyse(date: date, avant: avant, moment: moment) }

        // 1. un jour et un mois : « le vingt novembre », « jeudi 12 novembre », « 20/11 » n'est pas lu (trop ambigu)
        if let m = j.firstIndex(where: { mois[$0] != nil }) {
            var i = m
            while i > 0, Int(j[i - 1]) != nil || nombres[j[i - 1]] != nil || j[i - 1] == "et" { i -= 1 }
            while i < m, j[i] == "et" { i += 1 }
            if i < m, let jour = valeur(j[i..<m]), (1...31).contains(jour) {
                var annee = cal.component(.year, from: aujourdhui)
                let explicite = j.dropFirst(m + 1).first.flatMap { Int($0) }.flatMap { (2000...2100).contains($0) ? $0 : nil }
                if let e = explicite { annee = e }
                if var d = date(String(format: "%04d-%02d-%02d", annee, mois[j[m]]!, jour), calendrier: cal) {
                    if explicite == nil, d < aujourdhui { d = date(String(format: "%04d-%02d-%02d", annee + 1, mois[j[m]]!, jour), calendrier: cal) ?? d }
                    return resultat(iso(d, cal))
                }
                return resultat(nil)
            }
        }
        // 2. un nom de jour
        if let nom = j.first(where: { jours[$0] != nil }), let cible = jours[nom] {
            var delta = (cible - cal.component(.weekday, from: aujourdhui) + 7) % 7
            if delta == 0 { delta = 7 }
            return resultat(plus(delta))
        }
        // 3. relatif
        if suit("apres", "demain") { return resultat(plus(2)) }
        if j.contains("demain") { return resultat(plus(1)) }
        if j.contains("aujourd") || suit("ce", "soir") || suit("ce", "matin") { return resultat(plus(0)) }
        if let d = j.firstIndex(of: "dans"), let u = j[(d + 1)...].firstIndex(where: { ["jour", "jours", "semaine", "semaines", "mois"].contains($0) }), let n = valeur(j[(d + 1)..<u]) {
            switch j[u] {
            case "jour", "jours":
                // « dans huit jours » = une semaine, « dans quinze jours » = deux semaines (usage)
                let mots = j[d + 1] == "huit" ? 7 : (j[d + 1] == "quinze" ? 14 : n)
                return resultat(plus(mots))
            case "semaine", "semaines": return resultat(plus(7 * n))
            default: return resultat(cal.date(byAdding: .month, value: n, to: aujourdhui).map { iso($0, cal) })
            }
        }
        if j.contains("fin"), j.contains("mois"), let fin = cal.range(of: .day, in: .month, for: aujourdhui)?.upperBound {
            var c = cal.dateComponents([.year, .month], from: aujourdhui); c.day = fin - 1
            return resultat(cal.date(from: c).map { iso($0, cal) })
        }
        if j.contains("fin"), j.contains("semaine") {
            let delta = (6 - cal.component(.weekday, from: aujourdhui) + 7) % 7
            return resultat(plus(delta))
        }
        return resultat(nil)
    }

    /// « mer. 11 » (avec `court`) ou « mer. 11 nov. ».
    public static func jour(_ iso: String, court: Bool = false, calendrier: Calendar = .current) -> String? {
        guard let d = date(iso, calendrier: calendrier) else { return nil }
        let c = calendrier.dateComponents([.weekday, .day, .month], from: d)
        guard let w = c.weekday, let j = c.day, let m = c.month else { return nil }
        let nom = joursAbreges[(w - 1) % 7]
        return court ? "\(nom) \(j)" : "\(nom) \(j) \(moisAbreges[(m - 1) % 12])"
    }

    public struct Etiquette: Equatable, Sendable {
        public var texte: String
        /// « sans date » : la note n'a retenu aucune échéance.
        public var sansDate: Bool
    }

    /// Le texte de l'étiquette d'une échéance : « mer. 11 nov. · soir », « avant le 20 nov. », l'expression dite quand elle
    /// ne donne pas de date (« la semaine prochaine »), sinon « sans date ».
    public static func etiquette(quand: String?, date iso: String?, court: Bool = false, calendrier: Calendar = .current) -> Etiquette {
        let dit = quand?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let iso, let d = date(iso, calendrier: calendrier) {
            let marques = analyser(dit, depuis: d, calendrier: calendrier)   // « avant », « soir » : seulement des mots, la date vient d'ailleurs
            let c = calendrier.dateComponents([.day, .month], from: d)
            if marques.avant, let j = c.day, let m = c.month {
                return Etiquette(texte: "avant le \(j == 1 ? "1er" : String(j)) \(moisAbreges[(m - 1) % 12])", sansDate: false)
            }
            var t = Self.jour(iso, court: court, calendrier: calendrier) ?? dit
            if let moment = marques.moment { t += " · \(moment)" }
            return Etiquette(texte: t, sansDate: false)
        }
        if !dit.isEmpty { return Etiquette(texte: dit, sansDate: false) }
        return Etiquette(texte: "sans date", sansDate: true)
    }
}

// MARK: actions

public enum ActionsReunion {
    private static func rangMoment(_ a: ActionReunion) -> Int {
        let q = Historique.plier(a.quand ?? "")
        if q.contains("matin") { return 0 }
        if q.contains("apres midi") || q.contains("apres-midi") { return 2 }
        if q.contains("midi") { return 1 }
        if q.contains("soir") { return 3 }
        return 4
    }

    /// Les actions à faire par échéance (dates réelles d'abord, puis celles dont l'échéance n'est qu'un texte, puis « sans date »),
    /// et les actions faites à part. L'ordre de la note départage les égalités.
    public static func triees(_ actions: [ActionReunion]) -> (aFaire: [ActionReunion], faites: [ActionReunion]) {
        func rang(_ a: ActionReunion) -> Int {
            if a.echeance != nil { return 0 }
            return (a.quand ?? "").trimmingCharacters(in: .whitespaces).isEmpty ? 2 : 1
        }
        let restantes = actions.enumerated().filter { !$0.element.fait }
        let tri = restantes.sorted { x, y in
            let (a, b) = (x.element, y.element)
            if rang(a) != rang(b) { return rang(a) < rang(b) }
            if let da = a.echeance, let db = b.echeance, da != db { return da < db }
            if rangMoment(a) != rangMoment(b) { return rangMoment(a) < rangMoment(b) }
            return x.offset < y.offset
        }
        return (tri.map(\.element), actions.filter(\.fait))
    }
}

// MARK: liste

/// Ce que la liste dit d'une réunion sur une ligne.
public struct ResumeReunion: Equatable, Sendable {
    public var enBref: String
    public var noteEcrite: Bool
    public var aFaire: Int
    public var faites: Int
    /// La première échéance des actions à faire : date « 2026-11-11 » et « avant » si c'est une limite.
    public var premiere: String?
    public var premiereAvant: Bool
    public var toutFait: Bool { noteEcrite && aFaire == 0 && faites > 0 }

    public static func de(_ reunion: Reunion) -> ResumeReunion {
        let r = reunion.echeancesCalculees()
        let t = ActionsReunion.triees(r.actions)
        let premiere = t.aFaire.first { $0.echeance != nil }
        let bref = (r.enBref ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        // ancienne note, écrite avant « En bref » : le premier point abordé tient lieu de résumé
        let repli = r.dit.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return ResumeReunion(enBref: bref.isEmpty ? repli : bref, noteEcrite: r.etat == .prete, aFaire: t.aFaire.count, faites: t.faites.count,
                             premiere: premiere?.echeance, premiereAvant: premiere.map { Echeance.analyser($0.quand ?? "", depuis: Date()).avant } ?? false)
    }
}

public enum ListeReunions {
    /// Les réunions dont la note a encore au moins une action à faire.
    public static func avecActions(_ reunions: [Reunion]) -> [Reunion] {
        reunions.filter { $0.etat == .prete && $0.actions.contains { !$0.fait } }
    }

    public static func totalActions(_ reunions: [Reunion]) -> Int {
        reunions.filter { $0.etat == .prete }.reduce(0) { $0 + $1.actions.filter { !$0.fait }.count }
    }

    /// La recherche : tous les mots, sans casse ni accents, dans le titre, « En bref », la note et la transcription.
    public static func correspond(_ r: Reunion, requete: String) -> Bool {
        let mots = Historique.plier(requete).split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !mots.isEmpty else { return true }
        let cible = Historique.plier(([r.titreAffiche, r.enBref ?? ""] + r.dit + r.decisions + r.actions.map(\.quoi) + r.segments.map(\.texte)).joined(separator: " "))
        return mots.allSatisfy { cible.contains($0) }
    }
}

// MARK: citations

/// Retrouve, dans la transcription réelle, la phrase qui appuie un point de « Dit ». Rien n'est jamais construit : le texte rendu
/// est une portion exacte d'un passage de la transcription, ou il n'y a pas de citation.
public enum CitationsReunion {
    /// Texte replié (sans accents ni casse, tout ce qui n'est pas lettre ou chiffre devient un espace) et, pour chaque caractère,
    /// sa place dans le texte d'origine.
    private struct Replie {
        var texte = ""
        var origine: [String.Index] = []
        init(_ s: String) {
            var chars: [Character] = []
            for i in s.indices {
                let pli = String(s[i]).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
                for c in pli {
                    if c.isLetter || c.isNumber { chars.append(c); origine.append(i) }
                    else if let dernier = chars.last, dernier != " " { chars.append(" "); origine.append(i) }
                }
            }
            while chars.last == " " { chars.removeLast(); origine.removeLast() }
            texte = String(chars)
        }
    }

    private static let banales: Set<String> = [
        "dans", "pour", "avec", "sans", "cette", "comme", "tout", "tous", "plus", "mais", "donc", "elle", "elles", "sont", "etre", "avoir", "nous", "vous",
        "leur", "leurs", "chez", "apres", "avant", "aussi", "tres", "fait", "faire", "sera", "ceci", "cela", "dont", "bien", "entre",
    ]

    private static func racines(_ t: String) -> Set<String> {
        Set(FusionPistes.mots(t).filter { $0.count >= 4 && !banales.contains($0) }.map { String($0.prefix(5)) })
    }

    private static func phrases(_ texte: String) -> [String] {
        var sortie: [String] = []
        var debut = texte.startIndex
        for i in texte.indices where ".?!…\n".contains(texte[i]) {
            sortie.append(String(texte[debut...i])); debut = texte.index(after: i)
        }
        if debut < texte.endIndex { sortie.append(String(texte[debut...])) }
        return sortie.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { FusionPistes.mots($0).count >= 3 }
    }

    /// Le rang du passage et la citation exacte. `proposee` est la phrase que le modèle de langue a donnée : elle n'est gardée que
    /// si on la retrouve mot pour mot (à la casse, aux accents et à la ponctuation près) dans un seul passage, et c'est alors le
    /// texte du passage qui est rendu, pas la version du modèle. Sinon : la phrase de la transcription qui partage le plus de mots
    /// avec le point (au moins la moitié, deux mots au moins), ou rien.
    public static func trouver(point: String, proposee: String?, segments: [SegmentReunion]) -> (segment: Int, texte: String)? {
        if let p = proposee {
            let cherche = Replie(p).texte
            if cherche.split(separator: " ").count >= 3 {
                for (i, s) in segments.enumerated() {
                    let r = Replie(s.texte)
                    guard let trouve = r.texte.range(of: cherche) else { continue }
                    let a = r.texte.distance(from: r.texte.startIndex, to: trouve.lowerBound)
                    let b = r.texte.distance(from: r.texte.startIndex, to: trouve.upperBound)
                    guard b > a, b <= r.origine.count else { continue }
                    let debut = r.origine[a], fin = s.texte.index(after: r.origine[b - 1])
                    var morceau = String(s.texte[debut..<fin])
                    // la ponctuation qui suit la phrase fait partie de la citation (« … jeudi. »)
                    if fin < s.texte.endIndex, ".?!…".contains(s.texte[fin]) { morceau.append(s.texte[fin]) }
                    return (i, morceau.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
        }
        let cible = racines(point)
        guard !cible.isEmpty else { return nil }
        var meilleur: (segment: Int, texte: String, communs: Int, part: Double)?
        for (i, s) in segments.enumerated() {
            for ph in phrases(s.texte) {
                let communs = cible.intersection(racines(ph)).count
                let part = Double(communs) / Double(cible.count)
                guard part >= 0.5, communs >= min(2, cible.count) else { continue }
                if meilleur == nil || part > meilleur!.part || (part == meilleur!.part && communs > meilleur!.communs) { meilleur = (i, ph, communs, part) }
            }
        }
        return meilleur.map { ($0.segment, $0.texte) }
    }
}

// MARK: de la réponse du modèle à la réunion

extension NoteReunion {
    /// Range la note rédigée dans la réunion : titre, « En bref », points de « Dit » avec leur citation retrouvée dans la
    /// transcription, décisions et actions avec leurs échéances en vraies dates (calculées depuis le jour de la réunion).
    public static func appliquer(_ n: NoteBrute, a r: inout Reunion, segments: [SegmentReunion], calendrier: Calendar = .current) {
        r.titre = n.titre
        r.enBref = n.enBref.isEmpty ? nil : n.enBref
        r.dit = n.dit
        var citations: [CitationReunion] = []
        for (i, point) in n.dit.enumerated() {
            let proposee = n.citations.indices.contains(i) && !n.citations[i].isEmpty ? n.citations[i] : nil
            guard let t = CitationsReunion.trouver(point: point, proposee: proposee, segments: segments) else { continue }
            let s = segments[t.segment]
            citations.append(CitationReunion(point: i, texte: t.texte, locuteur: s.locuteur, debut: s.debut, fin: s.fin))
        }
        r.citations = citations
        r.decisions = n.decisions
        let echeances: [EcheanceReunion?] = n.decisions.indices.map { i in
            guard n.decisionsQuand.indices.contains(i), !n.decisionsQuand[i].isEmpty else { return nil }
            let q = n.decisionsQuand[i]
            return EcheanceReunion(quand: q, date: Echeance.analyser(q, depuis: r.debut, calendrier: calendrier).date)
        }
        r.decisionsEcheances = echeances.contains { $0 != nil } ? echeances : nil
        r.actions = n.actions.map { a in
            var b = a
            b.echeance = a.quand.flatMap { Echeance.analyser($0, depuis: r.debut, calendrier: calendrier).date }
            return b
        }
        r.participants = ["Moi"] + n.participants
    }
}
