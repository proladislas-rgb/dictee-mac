import Foundation

// « Tes apps » : quatre apps branchées dans l'îlot (Mail, Agenda, Notion, Airtable), dont on montre les nouveautés en direct. Ce fichier :
// les modèles partagés (l'app, la nouveauté, son action d'ouverture, les erreurs dites en français). Logique pure, sans interface ni
// réseau ; la façade est dans AppsBranchees.swift.

/// Une app qu'on peut brancher. L'identifiant (`rawValue`) est rangé dans le fichier de Voxile : ne jamais le changer.
public enum AppBranchee: String, CaseIterable, Codable, Sendable, Comparable {
    case mail, agenda, notion, airtable

    public var nom: String {
        switch self {
        case .mail: return "Mail"
        case .agenda: return "Agenda"
        case .notion: return "Notion"
        case .airtable: return "Airtable"
        }
    }
    /// Une clé à coller (rangée dans le Trousseau) : Notion et Airtable. Mail et Agenda passent par les apps du Mac.
    public var demandeUneCle: Bool { self == .notion || self == .airtable }

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
    /// La base ou la table n'est pas visible avec cette clé (Notion : la base n'est pas partagée avec l'intégration).
    case introuvable(AppBranchee)
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
        case .cleAbsente(let a), .cleRefusee(let a), .droitsManquants(let a, _), .introuvable(let a), .limite(let a, _), .serveur(let a, _),
             .refus(let a, _), .reseau(let a), .reponseIllisible(let a), .reglageIncomplet(let a): return a
        case .autorisationMail, .mailFerme, .mail: return .mail
        }
    }

    public var texte: String {
        switch self {
        case .cleAbsente(let a): return "Colle ta clé \(a.nom) pour la brancher"
        case .cleRefusee(let a): return "\(a.nom) refuse cette clé : vérifie qu\u{2019}elle est complète"
        case .droitsManquants(let a, let d): return "Il manque un droit à la clé \(a.nom) : \(d)"
        case .introuvable(.notion): return "Base introuvable : dans Notion, ajoute ta connexion à cette base"
        case .introuvable(let a): return "Introuvable dans \(a.nom) avec cette clé"
        case .limite(let a, let s): return "\(a.nom) demande de patienter (\(Int(s.rounded(.up))) s)"
        case .serveur(let a, _): return "\(a.nom) ne répond pas en ce moment"
        case .refus(let a, let code): return "\(a.nom) refuse la demande (\(code))"
        case .reseau(let a): return "Pas de réseau pour \(a.nom)"
        case .reponseIllisible(let a): return "Réponse de \(a.nom) illisible"
        case .reglageIncomplet(.notion): return "Choisis la base Notion à suivre"
        case .reglageIncomplet(.airtable): return "Choisis la base et la table Airtable à suivre"
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
        case .cleAbsente, .cleRefusee, .droitsManquants, .introuvable, .reglageIncomplet, .autorisationMail: return true
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
