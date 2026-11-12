import Foundation

// Le résumé de la journée : agrégation de l'historique par jour et par heure, moyenne glissante, série, meilleure journée,
// temps gagné, phrase-bilan. Logique pure : aucune interface, aucun réseau, aucune IA. La phrase vient de règles écrites ici.

// MARK: formats

public enum FormatJournee {
    /// Séparateur de milliers : espace insécable (« 4 120 »).
    public static func nombre(_ n: Int) -> String {
        let chiffres = String(abs(n))
        var groupes: [String] = []
        var fin = chiffres.endIndex
        while fin > chiffres.startIndex {
            let debut = chiffres.index(fin, offsetBy: -3, limitedBy: chiffres.startIndex) ?? chiffres.startIndex
            groupes.insert(String(chiffres[debut..<fin]), at: 0)
            fin = debut
        }
        return (n < 0 ? "-" : "") + groupes.joined(separator: "\u{00A0}")
    }

    /// « 4 120 mots », « 1 mot ».
    public static func mots(_ n: Int) -> String { "\(nombre(n))\u{00A0}mot\(n > 1 ? "s" : "")" }

    /// « 38 % » (espace insécable).
    public static func pourcent(_ p: Int) -> String { "\(p)\u{00A0}%" }

    /// Une durée arrondie, en français : « 1 h 20 », « 56 min », « moins d'une minute ». Au-delà de dix minutes, au multiple de cinq.
    public static func duree(_ secondes: Double) -> String {
        let s = max(0, secondes)
        if s < 30 { return "moins d\u{2019}une minute" }
        var minutes = Int((s / 60).rounded())
        if minutes >= 10 { minutes = Int((Double(minutes) / 5).rounded()) * 5 }
        minutes = max(1, minutes)
        if minutes < 60 { return "\(minutes)\u{00A0}min" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h)\u{00A0}h" : "\(h)\u{00A0}h\u{00A0}\(String(format: "%02d", m))"
    }

    /// « 9 h 15 », « 14 h » pile, « 10 h » (heure seule).
    public static func heureLongue(_ date: Date, calendrier: Calendar = .current) -> String {
        let c = calendrier.dateComponents([.hour, .minute], from: date)
        let h = c.hour ?? 0, m = c.minute ?? 0
        return m == 0 ? "\(h)\u{00A0}h" : "\(h)\u{00A0}h\u{00A0}\(String(format: "%02d", m))"
    }

    public static func heure(_ h: Int) -> String { "\(h)\u{00A0}h" }
}

// MARK: agrégats

public struct AppJournee: Equatable, Sendable {
    public var appId: String?
    public var nom: String
    public var mots: Int
    public var dictees: Int
    public init(appId: String? = nil, nom: String, mots: Int, dictees: Int) { self.appId = appId; self.nom = nom; self.mots = mots; self.dictees = dictees }
}

/// Ce qu'un jour contient : mots, dictées, temps de parole, répartition par heure, apps.
public struct ResumeJournee: Equatable, Sendable {
    public var jour: Date
    public var dictees: Int
    public var mots: Int
    /// Temps de parole enregistré (secondes). Les dictées sans durée enregistrée comptent 0.
    public var dureeParole: Double
    /// Dictées du jour dont la durée de parole n'a pas été enregistrée (faites avant cette fonction).
    public var sansDuree: Int
    /// Temps gagné par rapport au clavier (secondes) : mots ÷ 40 par minute, moins le temps de parole.
    public var tempsGagne: Double
    /// 24 valeurs : mots dictés pendant chaque heure.
    public var motsParHeure: [Int]
    public var dicteesParHeure: [Int]
    /// Où le texte a été écrit (dictées insérées), le plus de mots d'abord.
    public var apps: [AppJournee]
    /// L'heure où l'on a le plus dicté (la plus tôt en cas d'égalité), nil si rien.
    public var heurePic: Int?
    public init(jour: Date, dictees: Int, mots: Int, dureeParole: Double, sansDuree: Int, tempsGagne: Double, motsParHeure: [Int],
                dicteesParHeure: [Int], apps: [AppJournee], heurePic: Int?) {
        self.jour = jour; self.dictees = dictees; self.mots = mots; self.dureeParole = dureeParole; self.sansDuree = sansDuree
        self.tempsGagne = tempsGagne; self.motsParHeure = motsParHeure; self.dicteesParHeure = dicteesParHeure; self.apps = apps; self.heurePic = heurePic
    }
}

public struct MoyenneJournees: Equatable, Sendable {
    public var mots: Double
    public var dictees: Double
    public var tempsGagne: Double
    /// Nombre de jours actifs réellement comptés (14 au plus).
    public var jours: Int
    public init(mots: Double, dictees: Double, tempsGagne: Double, jours: Int) { self.mots = mots; self.dictees = dictees; self.tempsGagne = tempsGagne; self.jours = jours }
}

public struct JourSemaine: Equatable, Sendable {
    public var jour: Date
    public var mots: Int
    /// « mar. », « auj. » pour le jour affiché quand c'est aujourd'hui.
    public var etiquette: String
}

public struct ReunionJournee: Equatable, Identifiable, Sendable {
    public var id: UUID
    public var titre: String
    /// « 9 h 15 »
    public var heure: String
    public var duree: String
    /// « 2 actions à faire sur 3 », nil quand la note n'a pas d'action.
    public var actions: String?
    /// La phrase « En bref » (ou le premier point abordé pour une ancienne note) ; vide sans note.
    public var enBref: String
    public var noteEcrite: Bool
}

public struct ActionJournee: Equatable, Identifiable, Sendable {
    public var id: UUID
    public var reunion: UUID
    public var quoi: String
    public var qui: String?
    public var etiquette: String
    /// « demain », « aujourd'hui », en retard : l'étiquette ressort.
    public var urgente: Bool
    public var sansDate: Bool
    /// Cochée depuis la page de la journée (elle y reste, barrée, tant qu'on ne quitte pas la page : on peut se raviser).
    public var fait: Bool
}

public struct PhraseJournee: Equatable, Sendable {
    public enum Cas: String, Sendable {
        case aucune, premierJour, peuDeRecul, weekend, calme, enCours, dansLaMoyenne, belle, grosse, record
    }
    public var texte: String
    public var cas: Cas
}

// MARK: logique

public enum Journee {
    /// Vitesse de frappe moyenne retenue : 40 mots par minute.
    public static let motsParMinuteClavier = 40.0
    /// Moyenne glissante : les 14 derniers jours actifs avant le jour affiché.
    public static let joursDeMoyenne = 14
    /// En dessous de ce nombre de jours actifs avant, on ne compare pas.
    public static let joursMinimumPourComparer = 3

    public static func debut(_ d: Date, calendrier: Calendar = .current) -> Date { calendrier.startOfDay(for: d) }

    public static func tempsGagne(mots: Int, dureeParole: Double) -> Double {
        max(0, Double(mots) / motsParMinuteClavier * 60 - max(0, dureeParole))
    }

    public static func resume(jour: Date, entrees: [EntreeHistorique], calendrier: Calendar = .current) -> ResumeJournee {
        let delJour = entrees.filter { calendrier.isDate($0.date, inSameDayAs: jour) }
        var parHeure = Array(repeating: 0, count: 24), dParHeure = Array(repeating: 0, count: 24)
        var mots = 0, parole = 0.0, sansDuree = 0
        var apps: [String: AppJournee] = [:]
        var ordre: [String] = []
        for e in delJour {
            let n = Historique.compterMots(e.texte)
            let h = min(23, max(0, calendrier.component(.hour, from: e.date)))
            parHeure[h] += n; dParHeure[h] += 1
            mots += n
            if let d = e.dureeParole { parole += max(0, d) } else { sansDuree += 1 }
            guard e.insere, let nom = e.appNom, !nom.isEmpty else { continue }
            let cle = e.appId ?? nom
            if apps[cle] == nil { ordre.append(cle); apps[cle] = AppJournee(appId: e.appId, nom: nom, mots: 0, dictees: 0) }
            apps[cle]!.mots += n; apps[cle]!.dictees += 1
        }
        let classees = ordre.compactMap { apps[$0] }.enumerated().sorted { a, b in
            a.element.mots != b.element.mots ? a.element.mots > b.element.mots : a.offset < b.offset
        }.map(\.element)
        let pic = parHeure.enumerated().max { a, b in a.element != b.element ? a.element < b.element : a.offset > b.offset }
        return ResumeJournee(jour: calendrier.startOfDay(for: jour), dictees: delJour.count, mots: mots, dureeParole: parole, sansDuree: sansDuree,
                             tempsGagne: tempsGagne(mots: mots, dureeParole: parole), motsParHeure: parHeure, dicteesParHeure: dParHeure,
                             apps: classees, heurePic: (pic?.element ?? 0) > 0 ? pic?.offset : nil)
    }

    /// Mots, dictées et temps gagné de chaque jour qui a au moins une dictée.
    static func parJour(_ entrees: [EntreeHistorique], calendrier: Calendar) -> [Date: (mots: Int, dictees: Int, parole: Double)] {
        var jours: [Date: (mots: Int, dictees: Int, parole: Double)] = [:]
        for e in entrees {
            let j = calendrier.startOfDay(for: e.date)
            var v = jours[j] ?? (0, 0, 0)
            v.mots += Historique.compterMots(e.texte); v.dictees += 1; v.parole += max(0, e.dureeParole ?? 0)
            jours[j] = v
        }
        return jours
    }

    /// Moyenne des 14 derniers jours actifs strictement avant `jour`. Nil s'il n'y en a aucun.
    public static func moyenne(avant jour: Date, entrees: [EntreeHistorique], calendrier: Calendar = .current) -> MoyenneJournees? {
        let debutJour = calendrier.startOfDay(for: jour)
        let jours = parJour(entrees, calendrier: calendrier).filter { $0.key < debutJour }
            .sorted { $0.key > $1.key }.prefix(joursDeMoyenne)
        guard !jours.isEmpty else { return nil }
        let n = Double(jours.count)
        return MoyenneJournees(mots: Double(jours.reduce(0) { $0 + $1.value.mots }) / n,
                               dictees: Double(jours.reduce(0) { $0 + $1.value.dictees }) / n,
                               tempsGagne: jours.reduce(0.0) { $0 + tempsGagne(mots: $1.value.mots, dureeParole: $1.value.parole) } / n,
                               jours: jours.count)
    }

    /// Jours actifs de suite qui se terminent le jour affiché ; si ce jour est aujourd'hui et n'a pas encore de dictée,
    /// la série d'hier compte encore (elle n'est pas rompue avant la fin de la journée).
    public static func serie(jusquA jour: Date, entrees: [EntreeHistorique], maintenant: Date = Date(), calendrier: Calendar = .current) -> Int {
        let actifs = Set(parJour(entrees, calendrier: calendrier).keys)
        var courant = calendrier.startOfDay(for: jour)
        if !actifs.contains(courant) {
            guard calendrier.isDate(courant, inSameDayAs: maintenant), let hier = calendrier.date(byAdding: .day, value: -1, to: courant) else { return 0 }
            courant = hier
        }
        var n = 0
        while actifs.contains(courant) {
            n += 1
            guard let precedent = calendrier.date(byAdding: .day, value: -1, to: courant) else { break }
            courant = precedent
        }
        return n
    }

    /// La journée où l'on a le plus dicté (la plus récente en cas d'égalité). `avant` : seulement les jours strictement avant celui-là.
    public static func meilleure(entrees: [EntreeHistorique], avant: Date? = nil, calendrier: Calendar = .current) -> (jour: Date, mots: Int)? {
        let limite = avant.map { calendrier.startOfDay(for: $0) }
        let jours = parJour(entrees, calendrier: calendrier).filter { limite == nil || $0.key < limite! }
        guard let m = jours.max(by: { $0.value.mots != $1.value.mots ? $0.value.mots < $1.value.mots : $0.key < $1.key }), m.value.mots > 0 else { return nil }
        return (m.key, m.value.mots)
    }

    private static let abreges = ["dim.", "lun.", "mar.", "mer.", "jeu.", "ven.", "sam."]
    public static func jourAbrege(_ d: Date, calendrier: Calendar = .current) -> String { abreges[(calendrier.component(.weekday, from: d) - 1) % 7] }

    /// Les 7 jours qui se terminent le jour affiché (le plus ancien d'abord).
    public static func septJours(jusquA jour: Date, entrees: [EntreeHistorique], maintenant: Date = Date(), calendrier: Calendar = .current) -> [JourSemaine] {
        let jours = parJour(entrees, calendrier: calendrier)
        let fin = calendrier.startOfDay(for: jour)
        return (0..<7).reversed().compactMap { retrait in
            guard let d = calendrier.date(byAdding: .day, value: -retrait, to: fin) else { return nil }
            let dernier = retrait == 0
            return JourSemaine(jour: d, mots: jours[d]?.mots ?? 0,
                               etiquette: dernier && calendrier.isDate(d, inSameDayAs: maintenant) ? "auj." : jourAbrege(d, calendrier: calendrier))
        }
    }

    /// Les dictées d'une heure du jour, dans l'ordre de la journée.
    public static func dictees(jour: Date, heure: Int, entrees: [EntreeHistorique], calendrier: Calendar = .current) -> [EntreeHistorique] {
        entrees.filter { calendrier.isDate($0.date, inSameDayAs: jour) && calendrier.component(.hour, from: $0.date) == heure }
            .sorted { $0.date < $1.date }
    }

    /// L'heure suivante (delta = 1) ou précédente (delta = -1) qui contient des dictées, sans revenir de l'autre côté.
    public static func heureVoisine(motsParHeure: [Int], depuis heure: Int, delta: Int) -> Int? {
        guard delta != 0 else { return nil }
        var h = heure + (delta > 0 ? 1 : -1)
        while (0..<motsParHeure.count).contains(h) {
            if motsParHeure[h] > 0 { return h }
            h += delta > 0 ? 1 : -1
        }
        return nil
    }

    public static func estWeekend(_ d: Date, calendrier: Calendar = .current) -> Bool { calendrier.isDateInWeekend(d) }

    // MARK: courbe

    /// Les heures affichées sur la courbe : de 8 h à 18 h au moins, élargies aux heures où l'on a dicté, bornes paires.
    /// `debut` est l'heure de la première tranche, `fin` la borne de droite (exclue).
    public static func plageHeures(motsParHeure: [Int]) -> (debut: Int, fin: Int) {
        let actives = motsParHeure.indices.filter { motsParHeure[$0] > 0 }
        var debut = min(8, actives.first ?? 8), fin = max(18, (actives.last ?? 17) + 1)
        debut -= debut % 2
        if fin % 2 == 1 { fin += 1 }
        return (max(0, debut), min(24, fin))
    }

    /// La valeur de la ligne repère (0 est toujours tracé) : un nombre rond, sous le pic (700 → 400).
    public static func ligneRepere(pic: Int) -> Int? {
        guard pic >= 20 else { return nil }
        let cible = Double(pic) * 0.65
        let echelle = pow(10, floor(log10(cible)))
        let candidats = [1.0, 2, 2.5, 4, 5, 10].map { $0 * echelle }
        return Int(candidats.filter { $0 <= cible }.max() ?? echelle)
    }

    // MARK: réunions et actions du jour

    public static func reunions(jour: Date, reunions: [Reunion], calendrier: Calendar = .current) -> [ReunionJournee] {
        reunions.filter { calendrier.isDate($0.debut, inSameDayAs: jour) }.sorted { $0.debut < $1.debut }.map { r in
            let resume = ResumeReunion.de(r)
            let total = resume.aFaire + resume.faites
            let actions: String? = resume.noteEcrite && total > 0
                ? "\(resume.aFaire) action\(resume.aFaire > 1 ? "s" : "") à faire sur \(total)" : nil
            return ReunionJournee(id: r.id, titre: r.titreAffiche, heure: FormatJournee.heureLongue(r.debut, calendrier: calendrier),
                                  duree: FormatReunion.duree(r.duree), actions: actions, enBref: resume.noteEcrite ? resume.enBref : "", noteEcrite: resume.noteEcrite)
        }
    }

    /// Les actions non cochées des réunions du jour, par échéance. « demain » et « aujourd'hui » se lisent par rapport à `maintenant`.
    /// `aussi` : des actions déjà cochées à garder dans la liste (celles qu'on vient de cocher ici).
    public static func actions(jour: Date, reunions: [Reunion], aussi: Set<UUID> = [], maintenant: Date = Date(), calendrier: Calendar = .current) -> [ActionJournee] {
        let aujourdhui = calendrier.startOfDay(for: maintenant)
        let demain = calendrier.date(byAdding: .day, value: 1, to: aujourdhui)
        var sortie: [(date: Date?, action: ActionJournee)] = []
        for r in reunions.filter({ calendrier.isDate($0.debut, inSameDayAs: jour) }).sorted(by: { $0.debut < $1.debut }) {
            let calculee = r.echeancesCalculees(calendrier: calendrier)
            // le tri ignore « fait » : une action qu'on vient de cocher garde sa place
            let gardees = calculee.actions.filter { !$0.fait || aussi.contains($0.id) }.map { a -> ActionReunion in var b = a; b.fait = false; return b }
            for a in ActionsReunion.triees(gardees).aFaire {
                let fait = calculee.actions.first { $0.id == a.id }?.fait ?? false
                let date = a.echeance.flatMap { Echeance.date($0, calendrier: calendrier) }
                var etiquette = Echeance.etiquette(quand: a.quand, date: a.echeance, court: true, calendrier: calendrier)
                var urgente = false
                if let date {
                    if date == aujourdhui { etiquette.texte = "aujourd\u{2019}hui"; urgente = true }
                    else if date == demain { etiquette.texte = "demain"; urgente = true }
                    else if date < aujourdhui { etiquette.texte = "en retard"; urgente = true }
                }
                sortie.append((date, ActionJournee(id: a.id, reunion: r.id, quoi: a.quoi, qui: a.qui, etiquette: etiquette.texte, urgente: urgente && !fait, sansDate: etiquette.sansDate, fait: fait)))
            }
        }
        // Par échéance, toutes réunions confondues : les dates réelles d'abord, puis les échéances seulement dites, puis « sans date ».
        // À égalité, l'ordre des notes (stable).
        return sortie.enumerated().sorted { x, y in
            func rang(_ a: (date: Date?, action: ActionJournee)) -> Int { a.date != nil ? 0 : (a.action.sansDate ? 2 : 1) }
            let (a, b) = (x.element, y.element)
            if rang(a) != rang(b) { return rang(a) < rang(b) }
            if let da = a.date, let db = b.date, da != db { return da < db }
            return x.offset < y.offset
        }.map(\.element.action)
    }

    // MARK: titre du jour

    /// « Aujourd'hui », « Hier » ou nil, puis « lundi 9 novembre » (avec l'année si ce n'est pas l'année en cours).
    public static func titreJour(_ jour: Date, maintenant: Date = Date(), calendrier: Calendar = .current) -> (relatif: String?, date: String) {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR"); f.calendar = calendrier; f.timeZone = calendrier.timeZone
        let autreAnnee = calendrier.component(.year, from: jour) != calendrier.component(.year, from: maintenant)
        f.setLocalizedDateFormatFromTemplate(autreAnnee ? "EEEEdMMMMy" : "EEEEdMMMM")
        var relatif: String?
        if calendrier.isDate(jour, inSameDayAs: maintenant) { relatif = "Aujourd\u{2019}hui" }
        else if let hier = calendrier.date(byAdding: .day, value: -1, to: maintenant), calendrier.isDate(jour, inSameDayAs: hier) { relatif = "Hier" }
        return (relatif, f.string(from: jour))
    }

    public static func piedDePage(sansDuree: Int) -> String {
        var t = "Temps gagné = mots ÷ 40 par minute (vitesse de frappe moyenne), moins ton temps de parole."
        if sansDuree > 0 {
            t += sansDuree == 1
                ? " Une dictée de ce jour date d\u{2019}avant l\u{2019}enregistrement du temps de parole : il compte pour 0."
                : " \(sansDuree) dictées de ce jour datent d\u{2019}avant l\u{2019}enregistrement du temps de parole : il compte pour 0."
        }
        return t
    }

    // MARK: la phrase

    /// « Mail », « Mail et Claude ». La deuxième app est citée si elle pèse au moins 30 % de la première.
    /// Le bool dit s'il en reste d'autres (« surtout »).
    static func nomsApps(_ apps: [AppJournee]) -> (texte: String, autres: Bool)? {
        guard let premiere = apps.first else { return nil }
        if apps.count > 1, apps[1].mots * 100 >= premiere.mots * 30 {
            return ("\(premiere.nom) et \(apps[1].nom)", apps.count > 2)
        }
        return (premiere.nom, apps.count > 1)
    }

    /// La phrase-bilan du jour, en tutoiement, ton motivant et sobre. Les jours calmes ont une phrase calme.
    /// Règles, dans l'ordre : aucune dictée ; week-end (aucune comparaison) ; premier jour (rien avant : pas de comparaison) ;
    /// moins de 3 jours de recul (pas de comparaison) ; record ; puis le rapport à la moyenne (≥ 125 % grosse, ≥ 108 % belle,
    /// ≥ 92 % dans la moyenne, ≥ 50 % plus calme, sinon calme). Aujourd'hui, un total sous la moyenne n'est pas un verdict :
    /// la journée n'est pas finie (« pour l'instant »).
    public static func phrase(_ r: ResumeJournee, moyenne: MoyenneJournees?, meilleurAvant: Int?, maintenant: Date = Date(),
                              calendrier: Calendar = .current) -> PhraseJournee {
        let estAujourdhui = calendrier.isDate(r.jour, inSameDayAs: maintenant)
        let weekend = estWeekend(r.jour, calendrier: calendrier)

        if r.mots == 0 {
            if estAujourdhui { return PhraseJournee(texte: weekend ? "Pas encore de dictée aujourd\u{2019}hui, et c\u{2019}est le week-end : rien ne presse." : "Pas encore de dictée aujourd\u{2019}hui.", cas: .aucune) }
            return PhraseJournee(texte: weekend ? "Pas de dictée ce jour-là, c\u{2019}était le week-end." : "Aucune dictée ce jour-là.", cas: .aucune)
        }

        let apps = nomsApps(r.apps)
        let gagne = r.tempsGagne >= 180
        /// « Tu as gagné environ 1 h 20 par rapport au clavier, surtout en écrivant dans Mail et Claude. »
        var suite: String {
            switch (gagne, apps) {
            case (true, let a?):
                return " Tu as gagné environ \(FormatJournee.duree(r.tempsGagne)) par rapport au clavier, \(a.autres ? "surtout " : "")en écrivant dans \(a.texte)."
            case (true, nil): return " Tu as gagné environ \(FormatJournee.duree(r.tempsGagne)) par rapport au clavier."
            case (false, let a?): return " Tu as \(a.autres ? "surtout " : "")écrit dans \(a.texte)."
            case (false, nil): return ""
            }
        }
        let dictes = "\(FormatJournee.nombre(r.mots))\u{00A0}mot\(r.mots > 1 ? "s" : "") dicté\(r.mots > 1 ? "s" : "")"

        if weekend { return PhraseJournee(texte: "Week-end : \(dictes).\(suite)", cas: .weekend) }
        guard let m = moyenne else {
            return PhraseJournee(texte: "Première journée avec Voxile : \(dictes).\(suite) Les comparaisons arriveront avec les jours suivants.", cas: .premierJour)
        }
        guard m.jours >= joursMinimumPourComparer, m.mots > 0 else {
            return PhraseJournee(texte: "\(dictes).\(suite)", cas: .peuDeRecul)
        }
        let rapport = Double(r.mots) / m.mots
        let ecart = Int(abs(rapport - 1) * 100 + 0.5)
        let plus = ecart >= 5 ? ", \(FormatJournee.pourcent(ecart)) de plus que ta moyenne" : ""

        if let meilleur = meilleurAvant, r.mots > meilleur {
            return PhraseJournee(texte: "Ta meilleure journée jusqu\u{2019}ici : \(dictes)\(plus).\(suite)", cas: .record)
        }
        if rapport >= 1.25 { return PhraseJournee(texte: "Grosse journée : \(dictes)\(plus).\(suite)", cas: .grosse) }
        if rapport >= 1.08 { return PhraseJournee(texte: "Belle journée : \(dictes)\(plus).\(suite)", cas: .belle) }
        if rapport >= 0.92 { return PhraseJournee(texte: "Une journée dans ta moyenne : \(dictes).\(suite)", cas: .dansLaMoyenne) }
        if estAujourdhui {
            return PhraseJournee(texte: "\(dictes) pour l\u{2019}instant. Ta moyenne sur une journée : \(FormatJournee.nombre(Int(m.mots.rounded()))).\(suite)", cas: .enCours)
        }
        if rapport >= 0.5 {
            return PhraseJournee(texte: "Une journée plus calme que d\u{2019}habitude : \(dictes), \(FormatJournee.pourcent(ecart)) de moins que ta moyenne.\(suite)", cas: .calme)
        }
        return PhraseJournee(texte: "Journée calme : \(dictes).\(suite)", cas: .calme)
    }
}
