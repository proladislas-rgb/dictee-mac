import Foundation

// L'app de bureau (la fenêtre principale) : ce qui se décide sans écran. L'apparence (clair, sombre, automatique) et le bouton
// soleil/lune, les tuiles de la page « Aujourd'hui », le catalogue de « Découvrir » et les calques des illustrations des cartes
// d'accueil. Logique pure : aucune interface, aucun réseau. Maquette : design/maquettes/lucarne-app-final.html.

// MARK: - apparence

/// L'apparence de la fenêtre : claire, sombre, ou celle du Mac. Le bouton soleil/lune bascule toujours vers l'inverse de ce qu'on voit.
public enum ApparenceBureau: String, CaseIterable, Sendable {
    case clair, sombre, automatique

    /// Lu dans les réglages : une valeur inconnue ou absente suit le Mac.
    public static func depuis(_ brut: String?) -> ApparenceBureau { brut.flatMap(ApparenceBureau.init(rawValue:)) ?? .automatique }

    /// Ce que montre la fenêtre, selon l'apparence du Mac.
    public func sombre(systemeSombre: Bool) -> Bool {
        switch self {
        case .clair: return false
        case .sombre: return true
        case .automatique: return systemeSombre
        }
    }

    /// Un clic sur le soleil (ou la lune) : l'inverse de ce qu'on voit, choisi pour de bon (plus « automatique »).
    public func basculee(systemeSombre: Bool) -> ApparenceBureau { sombre(systemeSombre: systemeSombre) ? .clair : .sombre }

    public var libelle: String {
        switch self {
        case .clair: return "Clair"
        case .sombre: return "Sombre"
        case .automatique: return "Automatique"
        }
    }
}

// MARK: - Aujourd'hui

/// La grande tuile « Mots dictés » : le nombre du jour, l'anneau (la part du record), les trois lignes dessous.
public struct TuileMots: Equatable, Sendable {
    public var mots: Int
    public var dictees: Int
    public var apps: Int
    /// La meilleure journée AVANT aujourd'hui (nil : aucune). L'anneau se remplit vers elle.
    public var record: (jour: Date, mots: Int)?
    /// Moyenne des derniers jours actifs avant aujourd'hui (nil : aucun).
    public var moyenne: Int?
    public init(mots: Int, dictees: Int, apps: Int, record: (jour: Date, mots: Int)?, moyenne: Int?) {
        self.mots = mots; self.dictees = dictees; self.apps = apps; self.record = record; self.moyenne = moyenne
    }
    public static func == (a: TuileMots, b: TuileMots) -> Bool {
        a.mots == b.mots && a.dictees == b.dictees && a.apps == b.apps && a.moyenne == b.moyenne
            && a.record?.jour == b.record?.jour && a.record?.mots == b.record?.mots
    }

    /// La part de l'anneau, de 0 à 1 (pleine au-delà du record). Sans record, l'anneau reste vide.
    public var remplissage: Double {
        guard let r = record, r.mots > 0 else { return 0 }
        return min(1, Double(mots) / Double(r.mots))
    }
    /// Le texte au centre de l'anneau : « 71 % » ; au-delà du record : « Record » ; sans record : nil.
    public var pourcent: String? {
        guard let r = record, r.mots > 0 else { return nil }
        if mots > r.mots { return "Record" }
        return FormatJournee.pourcent(Int((Double(mots) / Double(r.mots) * 100).rounded(.down)))
    }
    /// Sous le pourcentage : « de ton record », « battu ! » ; sans record : « premier jour ».
    public var sousAnneau: String {
        guard let r = record, r.mots > 0 else { return "premier jour" }
        return mots > r.mots ? "battu aujourd\u{2019}hui" : "de ton record"
    }
}

/// « Temps gagné » : les minutes gagnées sur le clavier aujourd'hui et la semaine en petites barres.
public struct TuileTemps: Equatable, Sendable {
    public var secondes: Double
    /// Hauteur de chaque barre (0…1), du plus ancien jour à aujourd'hui (le dernier). Un jour actif a toujours une barre visible.
    public var barres: [Double]
    public init(secondes: Double, barres: [Double]) { self.secondes = secondes; self.barres = barres }
    /// Le nombre (« 52 ») et son unité (« min ») séparés : le chiffre est en grand, l'unité en petit.
    public var chiffre: (nombre: String, unite: String) {
        let m = Int((max(0, secondes) / 60).rounded())
        if m < 60 { return ("\(m)", "min") }
        return ("\(m / 60)\u{00A0}h\u{00A0}\(String(format: "%02d", m % 60))", "")
    }
    public static func == (a: TuileTemps, b: TuileTemps) -> Bool { a.secondes == b.secondes && a.barres == b.barres }
}

/// « Dernière note » : la dernière réunion dont la note est écrite.
public struct TuileNote: Equatable, Sendable {
    public var id: UUID
    public var extrait: String
    /// « Réunion · 14:02 · 29 min » (ou « Hier · 14:02 · 29 min »).
    public var meta: String
    public init(id: UUID, extrait: String, meta: String) { self.id = id; self.extrait = extrait; self.meta = meta }
}

/// « Prochaine réunion » : le prochain rendez-vous du calendrier (s'il est lu).
public struct TuileRendezVous: Equatable, Sendable {
    public var heure: String
    public var titre: String
    /// « dans 28 min », « dans 2 h 05 », « en cours ».
    public var quand: String
    public init(heure: String, titre: String, quand: String) { self.heure = heure; self.titre = titre; self.quand = quand }
}

/// Une pastille en haut à droite de la page (un rappel à venir).
public struct PuceAujourdhui: Equatable, Sendable {
    public var texte: String
    public var valeur: String
    public init(texte: String, valeur: String) { self.texte = texte; self.valeur = valeur }
}

/// Tout ce que la page « Aujourd'hui » affiche, calculé en une fois.
public struct TableauAujourdhui: Equatable, Sendable {
    /// « Jeudi 12 novembre »
    public var date: String
    public var mots: TuileMots
    public var temps: TuileTemps
    public var note: TuileNote?
    public var rendezVous: TuileRendezVous?
    public var puces: [PuceAujourdhui]
    /// Les noms des fichiers de l'étagère (les plus récents d'abord) et leur nombre.
    public var etagere: [String]
}

public enum Aujourdhui {
    /// Combien de pastilles au plus en haut de la page (elles partagent la ligne du titre).
    public static let pucesMax = 2

    public static func calculer(entrees: [EntreeHistorique], reunions: [Reunion], evenements: [EvenementAgenda], rappels: [Rappel],
                                etagere: [ElementEtagere], maintenant: Date, calendrier: Calendar = .current) -> TableauAujourdhui {
        let resume = Journee.resume(jour: maintenant, entrees: entrees, calendrier: calendrier)
        let moyenne = Journee.moyenne(avant: maintenant, entrees: entrees, calendrier: calendrier)
        let mots = TuileMots(mots: resume.mots, dictees: resume.dictees, apps: resume.apps.count,
                             record: Journee.meilleure(entrees: entrees, avant: maintenant, calendrier: calendrier),
                             moyenne: moyenne.map { Int($0.mots.rounded()) })
        let sept = Journee.septJours(jusquA: maintenant, entrees: entrees, maintenant: maintenant, calendrier: calendrier)
        return TableauAujourdhui(
            date: dateLongue(maintenant, calendrier: calendrier),
            mots: mots,
            temps: TuileTemps(secondes: resume.tempsGagne, barres: barres(sept.map(\.mots))),
            note: derniereNote(reunions, maintenant: maintenant, calendrier: calendrier),
            rendezVous: prochainRendezVous(evenements, maintenant: maintenant, calendrier: calendrier),
            puces: Array(rappelsAVenir(rappels, maintenant: maintenant, calendrier: calendrier).prefix(pucesMax)),
            etagere: etagere.sorted { $0.ajout > $1.ajout }.map(\.nom))
    }

    /// « Jeudi 12 novembre » (majuscule au jour).
    public static func dateLongue(_ d: Date, calendrier: Calendar = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR"); f.calendar = calendrier; f.timeZone = calendrier.timeZone
        f.dateFormat = "EEEE d MMMM"
        let s = f.string(from: d)
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    /// Les barres de la semaine : proportionnelles au plus grand jour ; un jour actif garde au moins 12 % (il se voit), un jour vide 0.
    public static func barres(_ valeurs: [Int]) -> [Double] {
        let pic = valeurs.max() ?? 0
        guard pic > 0 else { return valeurs.map { _ in 0 } }
        return valeurs.map { $0 > 0 ? max(0.12, Double($0) / Double(pic)) : 0 }
    }

    /// La réunion la plus récente dont la note est écrite (une note en préparation ne compte pas).
    public static func derniereNote(_ reunions: [Reunion], maintenant: Date, calendrier: Calendar = .current) -> TuileNote? {
        guard let r = reunions.filter({ ResumeReunion.de($0).noteEcrite }).max(by: { $0.debut < $1.debut }) else { return nil }
        let resume = ResumeReunion.de(r)
        let extrait = resume.enBref.isEmpty ? r.titreAffiche : resume.enBref
        let jour: String
        if calendrier.isDate(r.debut, inSameDayAs: maintenant) { jour = "Réunion" }
        else if let hier = calendrier.date(byAdding: .day, value: -1, to: maintenant), calendrier.isDate(r.debut, inSameDayAs: hier) { jour = "Hier" }
        else {
            let f = DateFormatter()
            f.locale = Locale(identifier: "fr_FR"); f.calendar = calendrier; f.timeZone = calendrier.timeZone
            f.dateFormat = "d MMM"
            jour = f.string(from: r.debut)
        }
        return TuileNote(id: r.id, extrait: extrait,
                         meta: [jour, FormatReunion.heure(r.debut, calendrier: calendrier), FormatReunion.duree(r.duree)].joined(separator: " \u{00B7} "))
    }

    /// Le prochain rendez-vous (pas les journées entières) : celui en cours d'abord, sinon le plus proche à venir, dans les 12 heures.
    public static func prochainRendezVous(_ evenements: [EvenementAgenda], maintenant: Date, calendrier: Calendar = .current) -> TuileRendezVous? {
        let utiles = evenements.filter { !$0.toutelaJournee && $0.fin > maintenant && $0.debut < maintenant.addingTimeInterval(12 * 3600) }
        guard let e = utiles.min(by: { $0.debut < $1.debut }) else { return nil }
        return TuileRendezVous(heure: FormatReunion.heure(e.debut, calendrier: calendrier), titre: e.titre, quand: dans(e.debut, maintenant: maintenant))
    }

    /// « dans 28 min », « dans 1 h 05 », « en cours » (déjà commencé), « maintenant » (moins d'une minute).
    public static func dans(_ debut: Date, maintenant: Date) -> String {
        let s = debut.timeIntervalSince(maintenant)
        if s <= 0 { return "en cours" }
        if s < 60 { return "maintenant" }
        let m = Int((s / 60).rounded(.up))
        if m < 60 { return "dans \(m)\u{00A0}min" }
        let h = m / 60, r = m % 60
        return r == 0 ? "dans \(h)\u{00A0}h" : "dans \(h)\u{00A0}h\u{00A0}\(String(format: "%02d", r))"
    }

    /// Les rappels pas encore sonnés, du plus proche au plus lointain : « Appeler le garage » · « 17:00 » (« demain 9:00 » au-delà de minuit).
    public static func rappelsAVenir(_ rappels: [Rappel], maintenant: Date, calendrier: Calendar = .current) -> [PuceAujourdhui] {
        rappels.filter { $0.sonneLe == nil && $0.echeance > maintenant }.sorted { $0.echeance < $1.echeance }.map { r in
            let heure = FormatReunion.heure(r.echeance, calendrier: calendrier)
            let valeur: String
            if calendrier.isDate(r.echeance, inSameDayAs: maintenant) { valeur = heure }
            else if let demain = calendrier.date(byAdding: .day, value: 1, to: maintenant), calendrier.isDate(r.echeance, inSameDayAs: demain) { valeur = "demain \(heure)" }
            else { valeur = Journee.jourAbrege(r.echeance, calendrier: calendrier) + " " + heure }
            return PuceAujourdhui(texte: r.texte, valeur: valeur)
        }
    }
}

// MARK: - Découvrir

/// Une chose que fait l'encoche, montrée en petite scène dans « Découvrir ».
public enum Decouverte: String, CaseIterable, Sendable {
    case centre, etagere, minuteur, rappels, reunions, claude, lecture

    public var titre: String {
        switch self {
        case .centre: return "Le Centre"
        case .etagere: return "Étagère"
        case .minuteur: return "Minuteur"
        case .rappels: return "Rappels"
        case .reunions: return "Réunions"
        case .claude: return "Claude Code"
        case .lecture: return "Lecture"
        }
    }

    /// Une phrase, deux lignes au plus dans une petite tuile.
    public var phrase: String {
        switch self {
        case .centre: return "Survole l\u{2019}encoche\u{202F}: tout ce qui compte est à un clic."
        case .etagere: return "Glisse un fichier vers l\u{2019}encoche\u{202F}: il t\u{2019}attend là."
        case .minuteur: return "5, 10 ou 25 min, d\u{2019}un clic, puis dans l\u{2019}encoche."
        case .rappels: return "À la voix\u{202F}: «\u{202F}Voxile, rappelle-moi demain à 9 h\u{202F}»."
        case .reunions: return "Un clic\u{202F}: Voxile écoute et écrit la note."
        case .claude: return "Où en sont tes sessions, et qui attend ta réponse."
        case .lecture: return "La musique ou la vidéo qui joue, avec ses commandes."
        }
    }

    /// La grande tuile (deux colonnes) : la première.
    public var grande: Bool { self == .centre }
}

// MARK: - illustrations des cartes d'accueil

/// Les illustrations des cartes d'accueil : des PNG transparents par calques, posés les uns sur les autres dans le même cadre
/// (même toile, même caméra). Le numéro est celui de la carte, la lettre celle du calque (a = le fond de la scène).
public enum IllustrationsAccueil {
    /// Toutes les pièces, dans l'ordre de la série (`Resources/Illustrations/<nom>.png`).
    public static let noms = ["1a", "1b", "1c", "2a", "2b", "3a", "3b", "4a", "4b", "4c", "5a"]

    /// Les calques d'une carte (1 à 5), du fond vers le dessus.
    public static func calques(carte: Int) -> [String] { noms.filter { $0.hasPrefix("\(carte)") } }

    /// Largeur sur hauteur de la toile : 1536 × 1024, sauf l'onde 5a, 1536 × 512.
    public static func rapport(carte: Int) -> Double { carte == 5 ? 3 : 1.5 }

    /// Ce que montre chaque pièce (le LISEZ-MOI et les noms d'accessibilité).
    public static func sujet(_ nom: String) -> String {
        switch nom {
        case "1a": return "le coin du clavier, touche fn au repos"
        case "1b": return "la touche fn enfoncée"
        case "1c": return "l\u{2019}index qui appuie"
        case "2a": return "le micro"
        case "2b": return "les anneaux autour du micro"
        case "3a": return "la bulle de message"
        case "3b": return "le curseur"
        case "4a": return "la clé"
        case "4b": return "le champ en verre"
        case "4c": return "la pastille verte cochée"
        case "5a": return "l\u{2019}onde de la voix"
        default: return nom
        }
    }
}

// MARK: - le mouvement des cartes d'accueil

/// Un ressort amorti, en temps : la même physique que les ressorts de SwiftUI (`duree` perçue, `rebond` de 0 à 1), mais calculée
/// pour un instant donné. Les scènes des cartes d'accueil sont des fonctions du temps : la même image à l'écran (120 i/s) et dans
/// la vidéo de contrôle image par image.
public enum Ressort {
    /// La position, de 0 (départ) vers 1 (arrivée), `t` secondes après le départ (0 avant). Avec du rebond, elle dépasse 1 puis revient.
    public static func valeur(_ t: Double, duree: Double = 0.5, rebond: Double = 0) -> Double {
        guard t > 0 else { return 0 }
        let w0 = 2 * Double.pi / max(0.01, duree)
        let zeta = 1 - min(0.95, max(0, rebond))
        if zeta >= 1 { return 1 - exp(-w0 * t) * (1 + w0 * t) }
        let wd = w0 * (1 - zeta * zeta).squareRoot()
        return 1 - exp(-zeta * w0 * t) * (cos(wd * t) + zeta * w0 / wd * sin(wd * t))
    }

    /// De `a` vers `b`, parti à `depart` (secondes de la boucle).
    public static func de(_ a: Double, vers b: Double, t: Double, depart: Double, duree: Double = 0.5, rebond: Double = 0) -> Double {
        a + (b - a) * valeur(t - depart, duree: duree, rebond: rebond)
    }

    /// Un aller-retour : vers `b` à `aller`, revenu à `a` à `retour` (le retour part de là où l'aller en est).
    public static func allerRetour(_ a: Double, _ b: Double, t: Double, aller: Double, retour: Double, duree: Double = 0.5, rebond: Double = 0,
                                   dureeRetour: Double? = nil, rebondRetour: Double? = nil) -> Double {
        let haut = de(a, vers: b, t: min(t, retour), depart: aller, duree: duree, rebond: rebond)
        guard t > retour else { return haut }
        return de(haut, vers: a, t: t, depart: retour, duree: dureeRetour ?? duree, rebond: rebondRetour ?? rebond)
    }
}

extension IllustrationsAccueil {
    /// Les barres d'une onde dessinée d'un seul tenant (5a) : les colonnes opaques séparées par des colonnes vides. `colonnes` : le
    /// nombre de pixels opaques de chaque colonne. Rend chaque barre en fraction de la largeur (début, fin), de gauche à droite.
    public static func barres(colonnes: [Int]) -> [(debut: Double, fin: Double)] {
        let n = Double(max(1, colonnes.count))
        var sortie: [(debut: Double, fin: Double)] = []
        var debut: Int?
        for (x, c) in Array(colonnes.enumerated().map { ($0.offset, $0.element) }) + [(colonnes.count, 0)] {
            if c > 0, debut == nil { debut = x }
            if c == 0, let d = debut { sortie.append((Double(d) / n, Double(x) / n)); debut = nil }
        }
        return sortie
    }
}

/// Des niveaux de voix qui changent tous les `pas` secondes, barre par barre (l'onde des cartes d'accueil) : une somme de ressorts,
/// un par changement, donc un mouvement continu avec élan et rebond, qui ne se répète pas d'une barre à l'autre.
public enum NiveauxVoix {
    public static let pas = 0.16
    /// Le niveau visé par la barre au changement `k` (0,35 à 1), plus haut au milieu de l'onde (barre 4 sur 9), comme une voix.
    public static func niveau(_ barre: Int, _ k: Int) -> Double {
        let centre = 1 - abs(Double(barre) - 4) / 6
        return 0.35 + 0.65 * centre * (0.45 + 0.55 * bruit(barre, k))
    }
    /// Un nombre de 0 à 1 qui ne se répète pas d'une barre ni d'un changement à l'autre (toujours le même pour les mêmes : rien au hasard).
    public static func bruit(_ barre: Int, _ k: Int) -> Double {
        var x = UInt64(bitPattern: Int64(barre &* 7919 &+ k &* 104_729)) &+ 0x9E37_79B9_7F4A_7C15
        x = (x ^ (x >> 30)) &* 0xBF58_476D_1CE4_E5B9
        x = (x ^ (x >> 27)) &* 0x94D0_49BB_1331_11EB
        x ^= x >> 31
        return Double(x % 1000) / 1000
    }
    /// La hauteur de la barre à l'instant `t` (les douze derniers changements comptent, les plus vieux sont posés).
    public static func valeur(_ barre: Int, t: Double) -> Double { valeur(t: t, pas: pas) { niveau(barre, $0) } }
    /// La même somme de ressorts pour des niveaux venus d'ailleurs (`niveau(k)` : celui du changement `k`, un tous les `pas` secondes,
    /// le premier à 0) : l'onde de la voix dictée (`OndeVoix`) y passe le vrai niveau du micro.
    public static func valeur(t: Double, pas: Double, niveau: (Int) -> Double) -> Double {
        let n = Int(floor(t / pas))
        var v = niveau(n - 12)
        for k in (n - 11)...max(n - 11, n) {
            v += (niveau(k) - niveau(k - 1)) * Ressort.valeur(t - Double(k) * pas, duree: 0.32, rebond: 0.35)
        }
        return v
    }
}

// MARK: - la fenêtre dans l'écran

/// Le cadre de la fenêtre de l'app, ramené dans la partie visible de l'écran (sous la barre des menus, au-dessus du Dock) : jamais plus
/// grand qu'elle, entièrement dedans. Sert à l'ouverture (une taille enregistrée sur un écran plus grand, ou une fenêtre qui avait
/// grandi toute seule) et quand les écrans changent. Coordonnées d'AppKit (origine en bas à gauche).
public enum CadreFenetre {
    /// `minimum` : la taille minimale de la fenêtre, elle-même bornée par l'écran (un écran plus petit qu'elle gagne).
    public static func borner(_ c: CGRect, dans ecran: CGRect, minimum: CGSize) -> CGRect {
        let l = min(max(c.width, min(minimum.width, ecran.width)), ecran.width)
        let h = min(max(c.height, min(minimum.height, ecran.height)), ecran.height)
        let x = min(max(c.minX, ecran.minX), ecran.maxX - l)
        let y = min(max(c.minY, ecran.minY), ecran.maxY - h)
        return CGRect(x: x, y: y, width: l, height: h)
    }

    /// La taille minimale réellement imposée sur cet écran.
    public static func minimum(_ voulu: CGSize, dans ecran: CGRect) -> CGSize {
        CGSize(width: min(voulu.width, ecran.width), height: min(voulu.height, ecran.height))
    }
}
