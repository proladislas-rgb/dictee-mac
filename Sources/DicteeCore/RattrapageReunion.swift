import Foundation

/// « Ce que j'ai raté » (maquette design/maquettes/ilot-reunion.html, étape 5) : pendant l'appel, les dernières minutes en deux ou trois
/// puces courtes, par le même service que la note de fin de réunion. Logique pure : la consigne, le message, la lecture de la réponse.
public enum RattrapageReunion {
    /// La fenêtre résumée (secondes) : les 3 dernières minutes.
    public static let fenetre: Double = 180
    /// Au plus trois puces, chacune courte (la carte de l'îlot en montre trois sur deux lignes au plus).
    public static let maxPuces = 3
    public static let maxCaracteres = 140

    public static let consigne = """
    Tu aides quelqu'un qui vient de décrocher quelques minutes pendant un appel. On te donne la transcription des dernières minutes. \
    « Moi » est la personne qui te lit (tutoie-la : « tu as dit… ») ; « Eux » sont les autres participants, leurs prénoms ne sont connus \
    que s'ils sont dits. La transcription vient d'une reconnaissance vocale et peut contenir des erreurs de mots.

    Règles :
    - Deux ou trois puces, les plus utiles d'abord : ce qui a été décidé, demandé ou promis, puis le sujet en cours.
    - Chaque puce : une phrase simple, 18 mots au maximum, en français courant.
    - N'invente rien : ni nom, ni date, ni chiffre qui ne soit pas dans la transcription.
    - S'il ne s'est rien dit d'important, une seule puce qui le dit simplement.

    Réponds par un seul objet JSON, sans texte autour : {"puces": ["…", "…"]}
    """

    public static func message(_ segments: [SegmentReunion]) -> String {
        "Transcription des dernières minutes :\n" + DecoupeReunion.texte(segments)
    }

    /// Les puces de la réponse (nil si ce n'est pas du JSON exploitable) : au plus trois, vides retirées, coupées proprement au besoin.
    public static func analyser(_ reponse: String) -> [String]? {
        guard let o = NoteReunion.objetJSON(reponse), let l = o["puces"] as? [Any] else { return nil }
        let puces = l.compactMap { $0 as? String }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "-•·* ")) }
            .filter { !$0.isEmpty }
            .prefix(maxPuces)
            .map(couper)
        return puces.isEmpty ? nil : Array(puces)
    }

    /// Une puce trop longue est coupée au dernier mot entier, avec « … ».
    static func couper(_ s: String) -> String {
        guard s.count > maxCaracteres else { return s }
        let debut = String(s.prefix(maxCaracteres))
        let jusquAuMot = debut.range(of: " ", options: .backwards).map { String(debut[..<$0.lowerBound]) } ?? debut
        return jusquAuMot.trimmingCharacters(in: CharacterSet(charactersIn: ",;: ")) + "\u{2026}"
    }
}

/// Où en est « Ce que j'ai raté » dans la carte : fermé (le direct), en cours (trois lignes qui luisent), les puces, ou un échec dit
/// simplement (« Rien de nouveau ces 3 dernières minutes », « Résumé impossible pour l'instant »).
public enum EtatRattrapage: Equatable, Sendable {
    case ferme
    case enCours
    case pret([String])
    case echec(String)
    public var ouvert: Bool { self != .ferme }
}

/// Ce que l'îlot montre d'une réunion qui s'enregistre (poussé par le contrôleur des réunions) : le temps, la pause, l'app de l'appel,
/// le direct, « Ce que j'ai raté », le point qu'on vient d'ajouter.
public struct ReunionIlot: Equatable, Sendable {
    public var enPause = false
    /// Secondes enregistrées à l'instant `depuis` ; le temps avance depuis `depuis` (nil : en pause, il est figé).
    public var duree: Double = 0
    public var depuis: Date?
    /// L'app de l'appel (« Zoom », « Teams »), si la réunion a commencé par « Noter cet appel ? ».
    public var app: String?
    public var lignes: [LigneDirect] = []
    public var rattrapage: EtatRattrapage = .ferme
    /// « Point ajouté » (le bouton change un instant).
    public var pointFait = false
    /// Le son du Mac n'a pas pu être capté : seul le micro est écouté (« Micro seul » dans la carte).
    public var microSeul = false
    public init() {}
    public func temps(a maintenant: Date) -> Double { duree + (depuis.map { max(0, maintenant.timeIntervalSince($0)) } ?? 0) }
}

/// Les annonces de la réunion dans l'îlot.
public enum AnnonceReunion: Equatable, Sendable {
    /// Une app d'appel utilise le micro : « Noter cet appel ? » (jamais d'enregistrement sans clic).
    case propose(app: String)
    /// Après l'arrêt : tout l'appel est relu, puis la note s'écrit (`etape` : « Relecture de tout l'appel »… ; `progres` : 0 à 1).
    case prepare(etape: String, progres: Double)
    /// « Note prête · Ouvrir » (ou « Transcription prête » si la note n'a pas pu être écrite).
    case prete(id: UUID, titre: String, duree: Double, sansNote: Bool)
    case message(String)
    public var vue: VueIlot {
        switch self {
        case .propose: return .reunionPropose
        case .prepare: return .reunionPrepare
        case .prete: return .reunionPrete
        case .message: return .reunionMessage
        }
    }
}
