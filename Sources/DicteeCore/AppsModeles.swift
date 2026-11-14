import Foundation

// « Tes apps » : sept apps branchées dans l'îlot (Mail, Agenda, Notion, Airtable ; Shopify, HubSpot, Stripe), dont on montre les nouveautés en direct. Ce fichier :
// les modèles partagés (l'app, la nouveauté, son action d'ouverture, les erreurs dites en français). Logique pure, sans interface ni
// réseau ; la façade est dans AppsBranchees.swift.

/// Une app qu'on peut brancher. L'identifiant (`rawValue`) est rangé dans le fichier de Voxile : ne jamais le changer.
public enum AppBranchee: String, CaseIterable, Codable, Sendable, Comparable {
    case mail, agenda, notion, airtable, shopify, hubspot, stripe

    public var nom: String {
        switch self {
        case .mail: return "Mail"
        case .agenda: return "Agenda"
        case .notion: return "Notion"
        case .airtable: return "Airtable"
        case .shopify: return "Shopify"
        case .hubspot: return "HubSpot"
        case .stripe: return "Stripe"
        }
    }
    /// Une clé à coller (rangée dans le Trousseau) : toutes sauf Mail et Agenda, qui passent par les apps du Mac.
    public var demandeUneCle: Bool { self != .mail && self != .agenda }

    /// Les deux pages de « Tes apps » (sept apps ne tiennent pas dans une carte : quatre au plus par page, la hauteur d'avant).
    public enum Groupe: String, CaseIterable, Sendable {
        case quotidien, vente
        public var nom: String { self == .quotidien ? "Au quotidien" : "Vente" }
        public var apps: [AppBranchee] { AppBranchee.allCases.filter { $0.groupe == self } }
    }
    public var groupe: Groupe {
        switch self {
        case .mail, .agenda, .notion, .airtable: return .quotidien
        case .shopify, .hubspot, .stripe: return .vente
        }
    }

    public static func < (a: AppBranchee, b: AppBranchee) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }
}

/// Ce qu'un clic sur une nouveauté ouvre.
public enum ActionOuverture: Codable, Equatable, Sendable {
    /// Une adresse : la page Notion, la fiche Airtable, le lien de visio d'un rendez-vous.
    case adresse(URL)
    /// Un message de Mail, par son identifiant (`Message-ID`, sans les chevrons) : `message://%3C…%3E` l'ouvre dans Mail.
    case messageMail(id: String)
    /// Un rendez-vous du calendrier, par l'identifiant d'`EvenementAgenda` (l'interface l'ouvre comme la carte du rendez-vous).
    case rendezVous(id: String)

    /// L'adresse à ouvrir avec NSWorkspace (nil pour un rendez-vous : l'interface a sa façon de l'ouvrir).
    public var adresse: URL? {
        switch self {
        case .adresse(let u): return u
        case .messageMail(let id):
            var permis = CharacterSet.alphanumerics; permis.insert(charactersIn: "-._~!$&'()*+,;=:@")
            let code = id.addingPercentEncoding(withAllowedCharacters: permis) ?? id
            return URL(string: "message://%3C\(code)%3E")
        case .rendezVous: return nil
        }
    }
}

/// Une nouveauté d'une app branchée : ce que l'îlot montre et annonce.
public struct Nouveaute: Codable, Equatable, Identifiable, Sendable {
    /// Ce qui la rend unique (`mail:<id>`, `notion:<page>@<jour>`, `airtable:<fiche>@<modification>`…) : une même clé n'est jamais
    /// annoncée deux fois (`MemoireApps.retenir`).
    public var id: String
    public var app: AppBranchee
    public var titre: String
    public var sousTitre: String
    /// La date qui compte pour elle : reçu (Mail), début (Agenda), échéance ou modification (Notion), modification (Airtable).
    public var date: Date
    public var action: ActionOuverture
    public init(id: String, app: AppBranchee, titre: String, sousTitre: String, date: Date, action: ActionOuverture) {
        self.id = id; self.app = app; self.titre = titre; self.sousTitre = sousTitre; self.date = date; self.action = action
    }

    /// Un texte reçu d'ailleurs (objet d'un mail, titre d'une page), prêt pour une ligne de l'îlot : espaces et retours à la ligne
    /// ramenés à un seul espace, caractères de contrôle retirés, coupé à `max` caractères (avec « … »).
    public static func ligne(_ s: String, max: Int = 120) -> String {
        let propre = s.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) || CharacterSet.whitespacesAndNewlines.contains($0) ? " " : String($0) }
            .joined().split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        guard propre.count > max else { return propre }
        return String(propre.prefix(max - 1)).trimmingCharacters(in: .whitespaces) + "\u{2026}"
    }
}

/// Ce qui peut empêcher une app de répondre, dit en français à Hugues (jamais la clé, jamais le corps d'une réponse).
public enum ErreurApp: Error, Equatable, Sendable, LocalizedError {
    case cleAbsente(AppBranchee)
    case cleRefusee(AppBranchee)
    /// La clé est bonne mais il lui manque un droit (Airtable : `data.records:read`…).
    case droitsManquants(AppBranchee, String)
    /// La base ou la table n'est pas visible avec cette clé (Notion : la base n'est pas partagée avec l'intégration ; Shopify : la
    /// boutique n'existe pas à cette adresse).
    case introuvable(AppBranchee)
    /// Une clé qui donne TOUS les droits (Stripe : la clé secrète `sk_…`) : refusée avant tout envoi, on demande une clé limitée.
    case cleTropPuissante(AppBranchee)
    /// Trop de requêtes : l'app demande d'attendre (secondes).
    case limite(AppBranchee, reessayerDans: Double)
    case serveur(AppBranchee, Int)
    case refus(AppBranchee, Int)
    case reseau(AppBranchee)
    case reponseIllisible(AppBranchee)
    /// Rien n'est choisi (la base Notion, la table Airtable).
    case reglageIncomplet(AppBranchee)
    /// macOS refuse à Voxile de piloter Mail (autorisation Automatisation).
    case autorisationMail
    case mailFerme
    case mail(Int)

    public var app: AppBranchee {
        switch self {
        case .cleAbsente(let a), .cleRefusee(let a), .droitsManquants(let a, _), .introuvable(let a), .cleTropPuissante(let a), .limite(let a, _), .serveur(let a, _),
             .refus(let a, _), .reseau(let a), .reponseIllisible(let a), .reglageIncomplet(let a): return a
        case .autorisationMail, .mailFerme, .mail: return .mail
        }
    }

    public var texte: String {
        switch self {
        case .cleAbsente(let a): return "Colle ta clé \(a.nom) pour la brancher"
        case .cleRefusee(let a): return "\(a.nom) refuse cette clé : vérifie qu\u{2019}elle est complète"
        // Shopify dit parfois autre chose qu'un droit (la boutique hors de l'organisation, l'app pas installée) : une phrase entière
        case .droitsManquants(.shopify, let d) where d.contains(" "): return "Shopify refuse : \(d)"
        case .droitsManquants(let a, let d): return "Il manque un droit à la clé \(a.nom) : \(d)"
        case .introuvable(.notion): return "Base introuvable : dans Notion, ajoute ta connexion à cette base"
        case .introuvable(.shopify): return "Boutique introuvable : vérifie son adresse (\u{2026}.myshopify.com)"
        case .introuvable(let a): return "Introuvable dans \(a.nom) avec cette clé"
        case .cleTropPuissante(.stripe): return "Clé secrète refusée : elle donne tous les droits. Crée une clé limitée en lecture (rk_\u{2026})"
        case .cleTropPuissante(let a): return "Cette clé \(a.nom) donne tous les droits : crée-en une en lecture seule"
        case .limite(let a, let s): return "\(a.nom) demande de patienter (\(Int(s.rounded(.up))) s)"
        case .serveur(let a, _): return "\(a.nom) ne répond pas en ce moment"
        case .refus(let a, let code): return "\(a.nom) refuse la demande (\(code))"
        case .reseau(let a): return "Pas de réseau pour \(a.nom)"
        case .reponseIllisible(let a): return "Réponse de \(a.nom) illisible"
        case .reglageIncomplet(.notion): return "Choisis la base Notion à suivre"
        case .reglageIncomplet(.airtable): return "Choisis la base et la table Airtable à suivre"
        case .reglageIncomplet(.shopify): return "Donne l\u{2019}adresse de ta boutique Shopify"
        case .reglageIncomplet(let a): return "\(a.nom) n\u{2019}est pas encore réglé"
        case .autorisationMail: return "Autorise Voxile à lire Mail : Réglages Système › Confidentialité › Automatisation"
        case .mailFerme: return "Mail est fermé"
        case .mail(let code): return "Mail n\u{2019}a pas répondu (\(code))"
        }
    }
    public var errorDescription: String? { texte }

    /// L'app ne marchera pas sans un geste de Hugues (nouvelle clé, autorisation, choix) : on cesse de la sonder jusque-là.
    public var demandeUnGeste: Bool {
        switch self {
        case .cleAbsente, .cleRefusee, .droitsManquants, .introuvable, .cleTropPuissante, .reglageIncomplet, .autorisationMail: return true
        default: return false
        }
    }
}

/// Où en est une app branchée (ce que l'interface montre à côté de son nom).
public enum EtatApp: Equatable, Sendable {
    case debranchee
    /// Branchée, rien de lu encore.
    case enAttente
    /// Le dernier sondage a réussi, à cette heure.
    case aJour(Date)
    /// En pause : Mail fermé (rien n'est sondé tant qu'il l'est).
    case enPause
    case erreur(ErreurApp)
}

/// Le genre d'une nouveauté, lu dans sa clé (`shopify:commande:…`, `hubspot:contact:…`) : ce que compte une annonce regroupée
/// (« 1 commande, 1 contact, 2 paiements »). Rangés dans l'ordre de « Tes apps ».
public enum GenreNouveaute: Int, CaseIterable, Comparable, Sendable {
    case mail, rendezVous, tache, fiche, commande, stock, contact, affaire, paiement

    public var mots: (un: String, plusieurs: String) {
        switch self {
        case .mail: return ("mail", "mails")
        case .rendezVous: return ("rendez-vous", "rendez-vous")
        case .tache: return ("tâche", "tâches")
        case .fiche: return ("fiche", "fiches")
        case .commande: return ("commande", "commandes")
        case .stock: return ("alerte de stock", "alertes de stock")
        case .contact: return ("contact", "contacts")
        case .affaire: return ("affaire", "affaires")
        case .paiement: return ("paiement", "paiements")
        }
    }
    /// « nouvelles tâches », « nouveaux paiements ».
    public var feminin: Bool { [.tache, .fiche, .commande, .stock, .affaire].contains(self) }
    public func compte(_ n: Int) -> String { "\(n) " + (n > 1 ? mots.plusieurs : mots.un) }
    public static func < (a: GenreNouveaute, b: GenreNouveaute) -> Bool { a.rawValue < b.rawValue }
}

extension Nouveaute {
    public var genre: GenreNouveaute {
        switch app {
        case .mail: return .mail
        case .agenda: return .rendezVous
        case .notion: return .tache
        case .airtable: return .fiche
        case .shopify: return id.hasPrefix("shopify:stock:") ? .stock : .commande
        case .hubspot: return id.hasPrefix("hubspot:contact:") ? .contact : .affaire
        case .stripe: return .paiement
        }
    }
}

/// Un montant tel que le donne l'API (valeur et devise ISO), écrit à la française : « 49,90 € », « 12 000 € », « 1 500 ¥ ».
public enum Montant {
    /// Stripe compte en plus petite unité (les centimes), sauf ces devises sans décimale (liste de Stripe) et celles à trois décimales.
    public static let sansDecimale: Set<String> = ["BIF", "CLP", "DJF", "GNF", "JPY", "KMF", "KRW", "MGA", "PYG", "RWF", "UGX", "VND", "VUV", "XAF", "XOF", "XPF"]
    public static let troisDecimales: Set<String> = ["BHD", "JOD", "KWD", "OMR", "TND"]

    /// Une valeur en plus petite unité (Stripe : 4990 en EUR = 49,90).
    public static func depuisUnites(_ n: Int, devise: String) -> Decimal {
        let d = devise.uppercased()
        let diviseur: Decimal = sansDecimale.contains(d) ? 1 : (troisDecimales.contains(d) ? 1000 : 100)
        return Decimal(n) / diviseur
    }

    /// Une valeur texte de l'API (« 49.9 », « 12000 ») ; nil si ce n'est pas un nombre.
    public static func valeur(_ s: String?) -> Decimal? {
        guard let s = s?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        return Decimal(string: s, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// « 49,90 € » ; un montant rond sans décimales (« 12 000 € ») ; une devise inconnue : son code (« 49,90 ABC »).
    public static func texte(_ v: Decimal, devise: String) -> String {
        let code = devise.uppercased().filter { $0.isASCII && $0.isLetter }
        let f = NumberFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.numberStyle = .currency
        f.currencyCode = code.isEmpty ? "EUR" : code
        if v == v.rounded0 { f.minimumFractionDigits = 0; f.maximumFractionDigits = 0 }
        return f.string(from: v as NSDecimalNumber) ?? "\(v) \(code)"
    }
}

extension Decimal {
    /// La partie entière (vers zéro).
    var rounded0: Decimal {
        var x = self, r = Decimal()
        NSDecimalRound(&r, &x, 0, self < 0 ? .up : .down)
        return r
    }
}
