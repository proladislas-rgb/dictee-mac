import Foundation

// « Tes apps » dans l'îlot (maquette design/maquettes/ilot-apps.html, décisions de Hugues du 13/11 au soir) : logique pure de l'interface,
// sans dessin. Ce que chaque écran montre (lignes de la liste, blocs du détail, sections des Nouveautés), leurs hauteurs (la forme de
// l'îlot les épouse), le parcours du branchement (coller la clé, choisir la base, la table, la personne), le regroupement des nouveautés
// en UNE annonce (« 3 nouveaux mails »), la clé montrée sans être lisible. Les dessins sont dans l'app (IlotAppsVues.swift).

// MARK: - textes par app

extension AppBranchee {
    /// Ce que dit la ligne d'une app pas encore branchée (maquette, étape 1).
    public var description: String {
        switch self {
        case .mail: return "Via l\u{2019}app Mail du Mac, Gmail compris"
        case .agenda: return "Calendrier du Mac, Google Agenda compris"
        case .notion: return "Tes tâches du jour \u{00B7} une clé à coller"
        case .airtable: return "Les fiches qui changent \u{00B7} une clé à coller"
        }
    }
    /// Ce qu'elle suit, une fois branchée.
    public var suit: String {
        switch self {
        case .mail: return "Nouveaux mails \u{00B7} Gmail compris"
        case .agenda: return "Ton prochain rendez-vous"
        case .notion: return "Tâches du jour et tâches qu\u{2019}on t\u{2019}assigne"
        case .airtable: return "Les fiches qui changent dans la table"
        }
    }
    /// Le nom d'une nouveauté de cette app (« mail », « tâche »…), au singulier et au pluriel, et son genre (« nouvelles tâches »).
    public var mot: (un: String, plusieurs: String) {
        switch self {
        case .mail: return ("mail", "mails")
        case .agenda: return ("rendez-vous", "rendez-vous")
        case .notion: return ("tâche", "tâches")
        case .airtable: return ("fiche", "fiches")
        }
    }
    public var feminin: Bool { self == .notion || self == .airtable }
    public func compte(_ n: Int) -> String { "\(n) " + (n > 1 ? mot.plusieurs : mot.un) }

    /// Notion et Airtable : où créer la clé, et comment la nommer.
    public var libelleCle: String { self == .airtable ? "Jeton d\u{2019}accès Airtable" : "Clé de ta connexion Notion" }
    public var nomCle: String { self == .airtable ? "Jeton" : "Clé" }
    public var exempleCle: String { self == .airtable ? "pat\u{2026}" : "ntn_\u{2026}" }
    public var pageCle: URL? {
        switch self {
        case .notion: return URL(string: "https://www.notion.so/profile/integrations")
        case .airtable: return URL(string: "https://airtable.com/create/tokens")
        default: return nil
        }
    }
    /// La ligne d'aide sous le champ : où trouver la clé (la partie `fort` en blanc).
    public var aideCle: (debut: String, fort: String, fin: String) {
        self == .airtable ? ("Où le créer : ", "airtable.com/create/tokens", " \u{203A} lecture seule")
                          : ("Où la trouver : ", "notion.so/profile/integrations", " \u{203A} ta connexion")
    }
    /// Ce que dit le pied du détail, à côté de « Débrancher ».
    public var notePied: String {
        switch self {
        case .mail: return "Voxile lit seulement qui écrit et l\u{2019}objet."
        case .agenda: return "Voxile lit le Calendrier du Mac. Pas de clé."
        case .notion, .airtable: return "La clé reste dans le Trousseau de ton Mac."
        }
    }
}

// MARK: - erreurs dites court, et le geste qui les répare

extension ErreurApp {
    /// La forme courte, pour la ligne de la liste « Tes apps » (le détail montre `texte` en entier).
    public var court: String {
        switch self {
        case .cleAbsente: return "Clé à coller"
        case .cleRefusee: return "Clé refusée"
        case .droitsManquants: return "Il manque un droit à la clé"
        case .introuvable(.notion): return "Base pas partagée avec la connexion"
        case .introuvable: return "Introuvable avec cette clé"
        case .limite: return "Demande de patienter"
        case .serveur: return "Ne répond pas en ce moment"
        case .refus(_, let c): return "Refuse la demande (\(c))"
        case .reseau: return "Pas de réseau"
        case .reponseIllisible: return "Réponse illisible"
        case .reglageIncomplet: return "Base à choisir"
        case .autorisationMail: return "Autorisation à donner dans Réglages"
        case .mailFerme: return "Mail est fermé"
        case .mail: return "Mail n\u{2019}a pas répondu"
        }
    }

    public enum Geste: Equatable, Sendable {
        case reessayer, autreCle, choisirBase, reglagesMail, aucun
        public var titre: String? {
            switch self {
            case .reessayer: return "Réessayer"
            case .autreCle: return "Coller une autre clé"
            case .choisirBase: return "Choisir la base"
            case .reglagesMail: return "Ouvrir les Réglages"
            case .aucun: return nil
            }
        }
    }
    /// Le bouton qui accompagne l'erreur dans l'îlot (nil : rien à faire, Mail fermé).
    public var geste: Geste {
        switch self {
        case .cleAbsente, .cleRefusee, .droitsManquants: return .autreCle
        case .introuvable, .reglageIncomplet: return .choisirBase
        case .autorisationMail: return .reglagesMail
        case .mailFerme: return .aucun
        case .limite, .serveur, .refus, .reseau, .reponseIllisible, .mail: return .reessayer
        }
    }
}

// MARK: - la clé, montrée sans être lisible

public enum ClePartielle {
    /// « ntn_••••••••k7Rm », « pat••••••••9fQz » : le préfixe (jusqu'au « _ », ou trois lettres), huit points, les quatre derniers
    /// caractères. Une clé trop courte pour qu'on en montre un bout : des points seulement.
    public static func masque(_ cle: String) -> String {
        let c = cle.trimmingCharacters(in: .whitespacesAndNewlines)
        let points = String(repeating: "\u{2022}", count: 8)
        guard c.count >= 16 else { return points }
        let prefixe: Substring
        if let i = c.firstIndex(of: "_"), c.distance(from: c.startIndex, to: i) <= 7 { prefixe = c[...i] } else { prefixe = c.prefix(3) }
        return String(prefixe) + points + String(c.suffix(4))
    }
}

// MARK: - l'état d'une app, tel que l'interface le montre

extension EtatApp {
    public enum Ton: Equatable, Sendable { case vert, gris, ambre }
    /// La pastille du détail (« ● Branché ») ; nil : débranchée.
    public var pastille: (texte: String, ton: Ton)? {
        switch self {
        case .debranchee: return nil
        case .enAttente: return ("Branchement\u{2026}", .gris)
        case .aJour: return ("Branché", .vert)
        case .enPause: return ("En pause", .gris)
        case .erreur(let e): return e == .mailFerme ? ("En pause", .gris) : ("À revoir", .ambre)
        }
    }
    public var erreur: ErreurApp? { if case .erreur(let e) = self { return e }; return nil }
}

/// Le bouton à droite d'une ligne de « Tes apps ».
public enum BoutonLigneApp: Equatable, Sendable {
    case brancher
    case enCours
    case branche
    case enPause
    case aRevoir
    public var titre: String {
        switch self {
        case .brancher: return "Brancher"
        case .enCours: return "Branchement\u{2026}"
        case .branche: return "Branché"
        case .enPause: return "En pause"
        case .aRevoir: return "À revoir"
        }
    }
}

public struct LigneApp: Equatable, Sendable {
    public var app: AppBranchee
    public var sousTitre: String
    /// Le sous-titre dit une erreur (ambre).
    public var alerte: Bool
    public var bouton: BoutonLigneApp
}

// MARK: - le parcours du branchement

/// Brancher Notion ou Airtable : coller la clé, la vérifier, puis choisir la base (Notion : puis la personne, si la base a une propriété
/// « personne » ; Airtable : puis la table, s'il y en a plusieurs). « Changer » depuis le détail d'une app branchée commence au choix.
public struct ParcoursApp: Equatable, Sendable {
    public enum Etape: Equatable, Sendable { case cle, bases, tables, personnes }
    public var app: AppBranchee
    public var etape: Etape = .cle
    /// La clé collée : en mémoire seulement, le temps du branchement (jamais dans un fichier ni au journal ; montrée masquée).
    public var saisie: String?
    /// Le nom de l'espace (Notion) ou du compte (Airtable), une fois la clé vérifiée.
    public var compte: String?
    public var choix: [ChoixApp] = []
    public var tables: [TableAirtable] = []
    /// La base Airtable choisie (avant sa table).
    public var base: ChoixApp?
    public var selection: String?
    public var page = 0
    public var erreur: ErreurApp?
    /// Le presse-papiers était vide (ou ne contenait pas de texte) au clic sur « Coller ».
    public var presseVide = false
    /// La base choisie n'a ni date ni personne : rien à suivre (Notion).
    public var baseSansRien = false

    public init(app: AppBranchee, etape: Etape = .cle) { self.app = app; self.etape = etape }

    /// Les lignes à choisir de l'étape (bases, tables ou personnes).
    public var options: [ChoixApp] {
        etape == .tables ? tables.map { ChoixApp(id: $0.id, nom: $0.nom) } : choix
    }
    /// Combien de lignes tiennent sur une page (une de moins quand une erreur prend sa place).
    public var parPage: Int { erreur == nil && !baseSansRien ? MesuresApps.choixParPage : MesuresApps.choixParPage - 1 }
    public var pages: Int { max(1, (options.count + parPage - 1) / parPage) }
    public var pageMontree: Int { min(max(0, page), pages - 1) }
    public var optionsMontrees: [ChoixApp] { Array(options.dropFirst(pageMontree * parPage).prefix(parPage)) }

    public var question: String {
        switch etape {
        case .cle: return ""
        case .bases: return app == .airtable ? "Quelle base suivre\u{00A0}?" : "Quelle base Notion suivre\u{00A0}?"
        case .tables: return "Quelle table suivre\u{00A0}?"
        case .personnes: return "Qui es-tu dans Notion\u{00A0}?"
        }
    }
    /// Le grand bouton du bas.
    public var titreBouton: String {
        switch etape {
        case .cle: return app == .airtable ? "Vérifier le jeton" : "Vérifier la clé"
        case _ where relireLaListe: return "Réessayer"
        case .bases: return "Suivre cette base"
        case .tables: return "Suivre cette table"
        case .personnes: return selection == nil ? "Passer" : "Suivre mes tâches"
        }
    }
    /// La liste n'a pas pu être lue (réseau, serveur) : le grand bouton la relit.
    public var relireLaListe: Bool { etape != .cle && options.isEmpty && erreur != nil }
    public var titreEnCours: String { etape == .cle ? "Vérification\u{2026}" : "Un instant\u{2026}" }
    /// Le grand bouton est-il utilisable ? (Sinon grisé : un clic ne fait rien, il ne range pas l'îlot.)
    public var boutonActif: Bool {
        switch etape {
        case .cle: return !(saisie ?? "").isEmpty
        case _ where relireLaListe: return true
        case .bases, .tables: return selection != nil
        case .personnes: return true
        }
    }
    /// Le titre de l'écran (en-tête).
    public var titre: String { "Brancher " + app.nom }
    /// Ce que dit la ligne verte au-dessus du choix (« Clé valide · Espace Atelier »).
    public var valide: String? {
        guard etape != .cle else { return nil }
        let debut = app == .airtable ? "Jeton valide" : "Clé valide"
        return compte.map { debut + " \u{00B7} " + $0 } ?? debut
    }
}

// MARK: - une annonce qui regroupe les nouveautés

/// Ce que l'aile puis le bandeau annoncent : TOUTES les nouveautés arrivées ensemble (ou pendant que l'annonce est à l'écran), jamais
/// une rafale de bandeaux.
public struct AnnonceApps: Equatable, Sendable {
    /// Les plus récentes d'abord, une seule fois chaque clé.
    public private(set) var elements: [Nouveaute] = []
    public init(_ e: [Nouveaute]) { ajouter(e) }
    public mutating func ajouter(_ e: [Nouveaute]) {
        var vus = Set<String>()
        elements = (e + elements).filter { vus.insert($0.id).inserted }.sorted { $0.date > $1.date }
    }
    /// Les apps concernées, dans l'ordre de « Tes apps ».
    public var apps: [AppBranchee] { Array(Set(elements.map(\.app))).sorted() }
    public var seule: Nouveaute? { elements.count == 1 ? elements[0] : nil }

    /// La première ligne : le nom de l'expéditeur (ou la tâche, la fiche, le rendez-vous) ; plusieurs d'une même app : « 3 nouveaux
    /// mails » ; de plusieurs apps : « 4 nouveautés ».
    public var titre: String {
        if let s = seule { return s.titre }
        let n = elements.count
        if apps.count == 1, let a = apps.first {
            let adjectif = a.feminin ? "nouvelles" : "nouveaux"
            return "\(n) \(adjectif) \(a.mot.plusieurs)"
        }
        return "\(n) nouveautés"
    }
    /// La deuxième ligne : « Devis cuisine · Mail » ; « Camille Roche, Atelier Nord et 1 autre » ; « 2 mails, 1 tâche, 1 fiche ».
    public var sousTitre: String {
        if let s = seule { return s.sousTitre + " \u{00B7} " + s.app.nom }
        if apps.count == 1 {
            var noms: [String] = []
            for e in elements where !noms.contains(e.titre) { noms.append(e.titre) }
            let montres = noms.prefix(2).joined(separator: ", ")
            let reste = noms.count - min(2, noms.count)
            return reste == 0 ? montres : montres + " et \(reste) autre" + (reste > 1 ? "s" : "")
        }
        return apps.map { a in a.compte(elements.filter { $0.app == a }.count) }.joined(separator: ", ")
    }
    /// Ce que dit l'aile droite, du plus long au plus court : l'îlot prend le premier qui tient (« 3 mails », sinon « 3 »).
    public var aile: [String] {
        let n = elements.count
        if apps.count == 1, let a = apps.first { return [a.compte(n), "\(n)"] }
        return ["\(n) nouv.", "\(n)"]
    }
    /// Ce que fait « Ouvrir » : la nouveauté elle-même si elle est seule, sinon la liste des Nouveautés.
    public var ouvreLaListe: Bool { seule == nil }
}

// MARK: - la liste « Nouveautés », bornée par sa hauteur

public enum PlanNouveautes {
    public struct Section: Equatable, Sendable {
        public var app: AppBranchee
        public var lignes: [Nouveaute]
        /// Celles qui n'ont pas la place (dites « +2 » à droite du nom de l'app).
        public var cachees: Int
    }
    /// L'en-tête d'une app (logo, nom) : 20 pt ; une ligne : 30 pt ; entre deux apps : 6 pt.
    public static let titre: Double = 20, ligne: Double = 30, ecart: Double = 6
    /// Le corps de la carte au plus haut : sous la hauteur du Centre (14 + 26 + 8 + 230 + 14 = 292).
    public static let corpsMax: Double = 230
    /// Rien de neuf : une ligne de texte et la pilule vers « Tes apps ».
    public static let corpsVide: Double = 74

    /// Les apps qui ont quelque chose (dans l'ordre de « Tes apps »), une ligne chacune d'abord, puis les plus récentes tant qu'elles
    /// tiennent dans `corpsMax`. Jamais une ligne coupée par le bas de la carte.
    public static func sections(_ actuelles: [AppBranchee: [Nouveaute]], corpsMax: Double = corpsMax) -> [Section] {
        let apps = AppBranchee.allCases.filter { !(actuelles[$0] ?? []).isEmpty }
        var montrees: [AppBranchee: Int] = [:]
        var h = 0.0
        for (i, a) in apps.enumerated() {
            let ajout = (i > 0 ? ecart : 0) + titre + ligne
            guard h + ajout <= corpsMax + 0.001 else { break }
            h += ajout; montrees[a] = 1
        }
        // puis les plus récentes, une à une, tant qu'elles tiennent
        let reste = apps.filter { montrees[$0] != nil }.flatMap { a in (actuelles[a] ?? []).sorted { $0.date > $1.date }.dropFirst().map { (a, $0.date) } }
            .sorted { $0.1 > $1.1 }
        for (a, _) in reste where h + ligne <= corpsMax + 0.001 {
            montrees[a, default: 0] += 1; h += ligne
        }
        return apps.compactMap { a in
            guard let n = montrees[a] else { return nil }
            let l = (actuelles[a] ?? []).sorted { $0.date > $1.date }
            return Section(app: a, lignes: Array(l.prefix(n)), cachees: l.count - n)
        }
    }
    public static func hauteur(_ s: [Section]) -> Double {
        s.isEmpty ? corpsVide : s.enumerated().map { (i, x) in (i > 0 ? ecart : 0) + titre + ligne * Double(x.lignes.count) }.reduce(0, +)
    }
}

// MARK: - les mesures des cartes

/// Les mesures des cartes de « Tes apps » (en points) : elles servent au dessin, à la hauteur de la forme et aux essais (où cliquer).
public enum MesuresApps {
    public static let haut: Double = 14, entete: Double = 26, bas: Double = 14
    /// La liste « Tes apps » : la phrase sous l'en-tête, puis la boîte des quatre apps (une ligne de 48 pt chacune).
    public static let ecartPhrase: Double = 6, phrase: Double = 16, ecartBoite: Double = 8, ligne: Double = 48
    public static var profondeurListe: Double { haut + entete + ecartPhrase + phrase + ecartBoite + Double(AppBranchee.allCases.count) * ligne + bas }
    /// Les Nouveautés : l'en-tête, 8 pt, le corps (`PlanNouveautes`).
    public static let ecartNouveautes: Double = 8
    public static func profondeurNouveautes(corps: Double) -> Double { haut + entete + ecartNouveautes + corps + bas }
    /// Les choix (bases, tables, personnes) : quatre par page.
    public static let choixParPage = 4
    /// Jamais plus haut que ce que la fenêtre de l'îlot peut montrer (384 − barre − ombre).
    public static let profondeurMax: Double = 336
}

/// Un bloc du détail d'une app (brancher, ou branchée) : sa hauteur et l'écart au-dessus. La vue dessine les mêmes blocs, dans l'ordre :
/// la hauteur de la forme est leur somme.
public enum BlocDetailApp: Equatable, Sendable {
    /// « Clé de ta connexion Notion » et « Ouvrir la page ↗ ».
    case libelleCle
    /// Le champ (la clé masquée, ou l'exemple en gris) et « Coller ».
    case champCle
    /// « Où la trouver : notion.so/profile/integrations › ta connexion ».
    case aideCle
    /// « ✓ Clé valide · Espace » (vert), au-dessus du choix.
    case valide(String)
    /// « Quelle base suivre ? » et, s'il y a plusieurs pages, « ‹ 1/3 › ».
    case question
    /// Une ligne à choisir (rond, nom).
    case choix(ChoixApp)
    /// Une ligne d'erreur (ambre) et son geste (« Réessayer »).
    case erreur(String, ErreurApp.Geste)
    /// Le grand bouton du bas (« Vérifier la clé », « Suivre cette base »).
    case bouton
    /// Ce que l'app branchée suit (une ligne d'information, avec « Changer » à droite pour la base ou la personne).
    case info(InfoApp)
    /// Le prochain rendez-vous (Agenda) avec « Rejoindre » et « Noter la réunion » ; nil : rien d'ici 12 h.
    case rendezVous(EvenementAgenda?)
    /// La note et « Débrancher ».
    case pied
    /// « Débrancher Airtable ? » : la phrase, « Annuler », « Débrancher ».
    case confirmation

    public var hauteur: Double {
        switch self {
        case .libelleCle: return 24
        case .champCle: return 36
        case .aideCle: return 16
        case .valide: return 28
        case .question: return 20
        case .choix: return 34
        // la phrase sur deux lignes ; avec son geste (« Réessayer », « Ouvrir les Réglages »), le bouton dessous, à droite
        case .erreur(_, let g): return g == .aucun ? 44 : 80
        case .bouton: return 34
        case .info: return 34
        case .rendezVous(let e): return e == nil ? 34 : 44 + 10 + 32
        case .pied: return 30
        // 12 de marge, le titre (18), 4, la phrase sur deux lignes (32), 8, les boutons (30), 12
        case .confirmation: return 116
        }
    }
}

/// Une ligne d'information du détail d'une app branchée.
public struct InfoApp: Equatable, Sendable {
    public enum Genre: Equatable, Sendable { case suit, base, personne, cle, etat }
    public var genre: Genre
    public var libelle: String
    /// En gras après le libellé (« Chantiers »), ou à droite pour la clé masquée.
    public var valeur: String?
    /// « Changer » à droite (la base, la personne).
    public var changer: Bool
    public init(_ genre: Genre, _ libelle: String, valeur: String? = nil, changer: Bool = false) {
        self.genre = genre; self.libelle = libelle; self.valeur = valeur; self.changer = changer
    }
}

// MARK: - l'état de l'interface

/// Ce que les cartes de « Tes apps » montrent : recopié de la façade (`AppsBranchees`) à chaque changement, plus ce qui n'appartient qu'à
/// l'interface (le détail ouvert, le parcours du branchement, la confirmation, les nouveautés pas encore vues).
public struct EtatAppsIlot: Equatable, Sendable {
    public var branchees: Set<AppBranchee> = []
    public var etats: [AppBranchee: EtatApp] = [:]
    public var actuelles: [AppBranchee: [Nouveaute]] = [:]
    /// Les nouveautés annoncées et pas encore ouvertes (le point bleu de leur ligne).
    public var nonLues: Set<String> = []
    /// Du neuf est arrivé depuis la dernière fois que la liste « Nouveautés » a été vue : le survol de l'îlot s'ouvre dessus.
    public var neuf = false
    /// L'app dont le détail est ouvert.
    public var detail: AppBranchee?
    /// Le branchement en cours (dans le détail).
    public var parcours: ParcoursApp?
    /// « Débrancher ? » est ouvert dans le détail.
    public var confirmation = false
    /// Une vérification, une lecture ou un sondage demandé d'un clic est en cours (le bouton montre un rouet, un clic ne fait rien).
    public var occupe = false
    /// Les clés rangées, masquées (« ntn_••••••••k7Rm »).
    public var cles: [AppBranchee: String] = [:]
    public var notion: ReglageNotion?
    public var airtable: ReglageAirtable?
    /// Le prochain rendez-vous (détail de l'Agenda).
    public var rendezVous: EvenementAgenda?
    /// macOS permet à Voxile de lire le calendrier.
    public var calendrierPermis = false

    public init() {}

    public func etat(_ a: AppBranchee) -> EtatApp { etats[a] ?? (branchees.contains(a) ? .enAttente : .debranchee) }
    public var toutes: [Nouveaute] { AppBranchee.allCases.flatMap { actuelles[$0] ?? [] } }
    public var aDesNouveautes: Bool { !toutes.isEmpty }

    /// La ligne de « Tes apps » pour une app.
    public func ligne(_ a: AppBranchee) -> LigneApp {
        let e = etat(a)
        switch e {
        case .debranchee:
            if a == .agenda, !calendrierPermis { return LigneApp(app: a, sousTitre: "Calendrier du Mac \u{00B7} accès à permettre", alerte: false, bouton: .brancher) }
            return LigneApp(app: a, sousTitre: a.description, alerte: false, bouton: .brancher)
        case .enAttente: return LigneApp(app: a, sousTitre: resume(a), alerte: false, bouton: .enCours)
        case .aJour: return LigneApp(app: a, sousTitre: resume(a), alerte: false, bouton: .branche)
        case .enPause: return LigneApp(app: a, sousTitre: "Mail est fermé : rien n\u{2019}est lu", alerte: false, bouton: .enPause)
        case .erreur(let x):
            if x == .mailFerme { return LigneApp(app: a, sousTitre: "Mail est fermé : rien n\u{2019}est lu", alerte: false, bouton: .enPause) }
            return LigneApp(app: a, sousTitre: x.court, alerte: true, bouton: .aRevoir)
        }
    }
    /// Ce que suit une app branchée, en une ligne (« Base suivie : Chantiers »).
    func resume(_ a: AppBranchee) -> String {
        switch a {
        case .notion: return notion.map { "Base suivie : " + $0.baseNom } ?? a.suit
        case .airtable: return airtable.map { "Table suivie : " + $0.tableNom } ?? a.suit
        default: return a.suit
        }
    }

    /// Le titre du détail (« Brancher Notion », « Airtable »).
    public var titreDetail: String { parcours?.titre ?? detail?.nom ?? "" }

    /// Les blocs du détail ouvert, dans l'ordre.
    public var blocs: [BlocDetailApp] {
        guard let a = detail else { return [] }
        if let p = parcours, p.app == a { return blocsParcours(p) }
        var b: [BlocDetailApp] = []
        switch a {
        case .mail:
            b = [.info(InfoApp(.suit, "Les mails non lus de ta boîte de réception")), .info(InfoApp(.etat, "Via l\u{2019}app Mail du Mac, Gmail compris"))]
        case .agenda:
            b = [.rendezVous(rendezVous)]
        case .notion:
            b = [.info(InfoApp(.suit, a.suit))]
            if let r = notion {
                b.append(.info(InfoApp(.base, "Base suivie : ", valeur: r.baseNom, changer: true)))
                if r.proprietePersonne != nil {
                    b.append(.info(InfoApp(.personne, "Assignées à : ", valeur: r.personneNom ?? (r.personneId == nil ? "personne" : "choisie"), changer: true)))
                }
            }
            if let c = cles[a] { b.append(.info(InfoApp(.cle, a.nomCle, valeur: c))) }
        case .airtable:
            b = [.info(InfoApp(.suit, a.suit))]
            if let r = airtable { b.append(.info(InfoApp(.base, "Table suivie : ", valeur: r.tableNom, changer: true))) }
            if let c = cles[a] { b.append(.info(InfoApp(.cle, a.nomCle, valeur: c))) }
        }
        // la confirmation ouverte, on ne parle plus de l'erreur (on débranche)
        if !confirmation {
            if let x = etat(a).erreur, x != .mailFerme { b.append(.erreur(x.texte, x.geste)) }
            else if etat(a) == .enPause || etat(a).erreur == .mailFerme { b.append(.erreur(ErreurApp.mailFerme.texte + " : rien n\u{2019}est lu", .aucun)) }
        }
        b.append(confirmation ? .confirmation : .pied)
        return b
    }

    private func blocsParcours(_ p: ParcoursApp) -> [BlocDetailApp] {
        var b: [BlocDetailApp] = []
        let erreur: BlocDetailApp? = {
            if p.presseVide { return .erreur("Le presse-papiers est vide : copie d\u{2019}abord ta clé", .aucun) }
            if p.baseSansRien { return .erreur("Cette base n\u{2019}a ni date ni personne : choisis-en une autre", .aucun) }
            // dans le parcours, le geste est déjà là : le champ et « Coller » (une autre clé), le choix, ou le grand bouton (il revérifie,
            // relit la liste, ou refait le choix) ; l'erreur n'a pas de bouton à elle
            if let x = p.erreur { return .erreur(x.texte, .aucun) }
            return nil
        }()
        switch p.etape {
        case .cle:
            b = [.libelleCle, .champCle, .aideCle]
            if let e = erreur { b.append(e) }
        case .bases, .tables, .personnes:
            // une erreur prend la place de « Clé valide » (elle compte plus, et la carte reste sous la hauteur permise)
            if erreur == nil, let v = p.valide { b.append(.valide(v)) }
            b.append(.question)
            b += p.optionsMontrees.map { .choix($0) }
            if let e = erreur { b.append(e) }
        }
        b.append(.bouton)
        return b
    }

    /// L'écart au-dessus d'un bloc (le premier suit l'en-tête de 12 pt ; les choix se serrent à 4 pt).
    public static func ecart(avant b: BlocDetailApp, apres precedent: BlocDetailApp?) -> Double {
        guard let p = precedent else { return 12 }
        switch (p, b) {
        case (.libelleCle, .champCle): return 6
        case (.champCle, .aideCle): return 8
        case (.valide, .question): return 10
        case (.question, .choix): return 6
        case (.choix, .choix): return 4
        case (.info, .info): return 0
        default: return 12
        }
    }

    /// La hauteur du corps du détail (les blocs et leurs écarts).
    public var corpsDetail: Double {
        var h = 0.0, avant: BlocDetailApp? = nil
        for b in blocs { h += Self.ecart(avant: b, apres: avant) + b.hauteur; avant = b }
        return h
    }
    /// La profondeur du détail sous la barre : marge, en-tête, blocs, marge.
    public var profondeurDetail: Double { MesuresApps.haut + MesuresApps.entete + corpsDetail + MesuresApps.bas }
    /// La profondeur des Nouveautés.
    public var profondeurNouveautes: Double { MesuresApps.profondeurNouveautes(corps: PlanNouveautes.hauteur(PlanNouveautes.sections(actuelles))) }
}
