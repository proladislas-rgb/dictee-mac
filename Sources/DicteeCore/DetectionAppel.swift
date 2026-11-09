import Foundation

/// Reconnaître une app d'appel (visio, téléphone) qui utilise le micro, pour proposer — jamais enregistrer sans clic — de noter l'appel.
/// Liste blanche : une app inconnue (dictée, assistant vocal, Verbe lui-même) ne propose jamais rien.
public enum DetectionAppel {
    public struct AppAppel: Equatable, Sendable {
        public var prefixe: String
        public var nom: String
        /// Les navigateurs servent aussi à Meet, Teams web, etc. : la proposition y est la même, mais plus discrète (une seule par épisode).
        public var navigateur: Bool
    }

    /// Identifiants de paquet (ou leurs débuts : les processus auxiliaires d'une app ont un identifiant qui commence comme elle).
    public static let apps: [AppAppel] = [
        AppAppel(prefixe: "us.zoom.xos", nom: "Zoom", navigateur: false),
        AppAppel(prefixe: "com.microsoft.teams", nom: "Teams", navigateur: false),
        AppAppel(prefixe: "com.apple.FaceTime", nom: "FaceTime", navigateur: false),
        AppAppel(prefixe: "com.skype.skype", nom: "Skype", navigateur: false),
        AppAppel(prefixe: "net.whatsapp.WhatsApp", nom: "WhatsApp", navigateur: false),
        AppAppel(prefixe: "io.aircall", nom: "Aircall", navigateur: false),      // « Aircall Workspace », identifiant lu sur ce Mac
        AppAppel(prefixe: "com.aircall", nom: "Aircall", navigateur: false),
        AppAppel(prefixe: "com.cisco.webexmeetingsapp", nom: "Webex", navigateur: false),
        AppAppel(prefixe: "Cisco-Systems.Spark", nom: "Webex", navigateur: false),
        AppAppel(prefixe: "com.tinyspeck.slackmacgap", nom: "Slack", navigateur: false),
        AppAppel(prefixe: "com.hnc.Discord", nom: "Discord", navigateur: false),
        AppAppel(prefixe: "ru.keepcoder.Telegram", nom: "Telegram", navigateur: false),
        AppAppel(prefixe: "com.google.Chrome", nom: "Chrome", navigateur: true),
        AppAppel(prefixe: "com.apple.Safari", nom: "Safari", navigateur: true),
        AppAppel(prefixe: "company.thebrowser.Browser", nom: "Arc", navigateur: true),
        AppAppel(prefixe: "org.mozilla.firefox", nom: "Firefox", navigateur: true),
        AppAppel(prefixe: "com.microsoft.edgemac", nom: "Edge", navigateur: true),
        AppAppel(prefixe: "com.brave.Browser", nom: "Brave", navigateur: true),
    ]

    /// L'app d'appel qui correspond à cet identifiant de paquet, s'il y en a une. Les applis de dictée et Verbe n'en font pas partie.
    public static func reconnaitre(bundleID: String) -> AppAppel? {
        let id = bundleID.lowercased()
        return apps.first { id.hasPrefix($0.prefixe.lowercased()) }
    }

    /// Parmi les identifiants des processus qui écoutent le micro, la première app d'appel (les apps dédiées avant les navigateurs).
    public static func appEnAppel(bundleIDs: [String], moi: String = "com.hugues.dictee") -> AppAppel? {
        let reconnues = bundleIDs.filter { !$0.lowercased().hasPrefix(moi.lowercased()) }.compactMap(reconnaitre)
        return reconnues.first { !$0.navigateur } ?? reconnues.first
    }
}

/// Décide quand proposer « Noter cet appel ? ». Une proposition par épisode d'appel (de la première écoute du micro jusqu'à
/// 20 s sans écoute), jamais si une réunion est déjà en cours, et seulement après 6 s d'écoute continue (un test de micro, une
/// dictée vocale de navigateur ne déclenchent rien). Logique pure : l'horloge est passée en paramètre.
public struct SuiveurAppel: Sendable {
    public var delaiAvantProposition: Double = 6
    public var silenceFinEpisode: Double = 20

    private var debutEcoute: Double?
    private var derniereEcoute: Double = -1000
    private var proposeDansEpisode = false

    public init() {}

    /// À appeler à chaque relevé (toutes les 2 s environ) avec l'app d'appel qui écoute le micro (nil : aucune) et l'état de Verbe.
    /// Rend l'app à proposer, ou nil.
    public mutating func observer(app: DetectionAppel.AppAppel?, reunionEnCours: Bool, maintenant: Double) -> DetectionAppel.AppAppel? {
        guard let app else {
            if maintenant - derniereEcoute >= silenceFinEpisode { debutEcoute = nil; proposeDansEpisode = false }
            return nil
        }
        if maintenant - derniereEcoute >= silenceFinEpisode { debutEcoute = nil; proposeDansEpisode = false }
        derniereEcoute = maintenant
        if debutEcoute == nil { debutEcoute = maintenant }
        if reunionEnCours { proposeDansEpisode = true; return nil }   // on enregistre déjà : rien à proposer, pour tout l'épisode
        guard !proposeDansEpisode, let debut = debutEcoute, maintenant - debut >= delaiAvantProposition else { return nil }
        proposeDansEpisode = true
        return app
    }
}
