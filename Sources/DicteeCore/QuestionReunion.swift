import Foundation

/// « Demander » : une question sur une réunion (sa note et sa transcription numérotée), ou sur toutes les réunions (leurs notes).
/// La réponse est courte et renvoie au moment exact (le numéro du passage) ou à la réunion qui la porte. Rien n'est inventé : le
/// numéro rendu par le modèle n'est gardé que s'il existe. Logique pure ; l'appel au modèle de langue est dans l'app.
public enum QuestionReunion {
    public static let rien = "Je n\u{2019}ai rien trouvé là-dessus dans cette réunion."
    public static let rienToutes = "Je n\u{2019}ai rien trouvé là-dessus dans tes réunions."

    public struct Reponse: Equatable, Sendable {
        public var texte: String
        /// Le passage (rang dans `Reunion.segments`) qui appuie la réponse.
        public var passage: Int?
        /// La réunion (rang dans la liste envoyée) qui porte la réponse (« Demander à mes réunions »).
        public var reunion: Int?
        public init(texte: String, passage: Int? = nil, reunion: Int? = nil) { self.texte = texte; self.passage = passage; self.reunion = reunion }
    }

    public static let consigne = """
    Tu réponds à une question sur UNE réunion, à partir de sa note et de sa transcription. Chaque ligne de la transcription commence \
    par son numéro entre crochets, l'heure et la personne qui parle (« Moi » est la personne qui pose la question).
    Règles : réponds en français, en une ou deux phrases courtes et directes, seulement avec ce qui est dit dans la réunion. N'invente \
    rien. Donne le prénom de la personne quand il est connu. Si la réunion ne permet pas de répondre, la réponse est exactement : \
    « \(rien) »
    Réponds par un seul objet JSON, sans texte autour : {"reponse": "…", "passage": le numéro de la ligne de la transcription qui appuie le mieux la réponse, ou null}
    """

    public static let consigneToutes = """
    Tu réponds à une question sur les réunions de l'utilisateur, à partir de leurs notes. Chaque réunion commence par son numéro entre \
    crochets (« [R3] »), son titre et sa date. « Moi » est la personne qui pose la question.
    Règles : réponds en français, en une ou deux phrases courtes et directes, seulement avec ce que disent les notes. N'invente rien. \
    Dis de quelle réunion vient la réponse quand c'est utile (« lors de l'appel du 9 novembre »). Si aucune note ne permet de \
    répondre, la réponse est exactement : « \(rienToutes) »
    Réponds par un seul objet JSON, sans texte autour : {"reponse": "…", "reunion": le numéro de la réunion qui porte la réponse (3 pour [R3]), ou null}
    """

    /// La note d'une réunion en quelques lignes (sujets, décisions, prochaines étapes).
    public static func resumeNote(_ r: Reunion) -> [String] {
        var l: [String] = []
        if let b = r.enBref, !b.isEmpty { l.append("En bref : \(b)") }
        for s in r.sujets ?? [] {
            l.append("Sujet : \(s.titre)")
            for p in s.puces { l.append("- \(p.texte)" + (p.sous.isEmpty ? "" : " (" + p.sous.joined(separator: " ; ") + ")")) }
        }
        l += r.dit.map { "- \($0)" }
        l += r.decisions.map { "Décision : \($0)" }
        l += r.actions.map { "Prochaine étape : \($0.qui ?? "?") — \($0.quoi)" + ($0.quand.map { " — \($0)" } ?? "") }
        return l
    }

    /// Une ligne de transcription numérotée : « [12] 14:16 Inès : … ».
    static func ligne(_ r: Reunion, _ i: Int, calendrier: Calendar) -> String {
        let s = r.segments[i]
        return "[\(i + 1)] \(FormatReunion.heure(r.debut.addingTimeInterval(s.debut), calendrier: calendrier)) \(r.orateur(de: s).nom) : \(s.texte)"
    }

    /// Le message pour une réunion. Si la transcription dépasse `maxCaracteres`, on garde les lignes qui partagent le plus de mots avec
    /// la question (dans l'ordre du temps) : les numéros restent ceux de la transcription entière.
    public static func message(_ question: String, reunion r: Reunion, maxCaracteres: Int = 18_000, calendrier: Calendar = .current) -> String {
        var tete = ["Réunion : \(r.titreAffiche), \(FormatReunion.jourHeure(r.debut, calendrier: calendrier)), \(FormatReunion.duree(r.duree))."]
        let note = resumeNote(r)
        if !note.isEmpty { tete += ["", "Note :"] + note }
        let lignes = r.segments.indices.map { ligne(r, $0, calendrier: calendrier) }
        var gardees = Array(lignes.indices)
        let total = lignes.reduce(0) { $0 + $1.count + 1 }
        if total > maxCaracteres {
            let q = Set(FusionPistes.mots(question).filter { $0.count >= 3 })
            let score = lignes.indices.map { i in Set(FusionPistes.mots(r.segments[i].texte)).intersection(q).count }
            var taille = 0
            gardees = []
            for i in lignes.indices.sorted(by: { score[$0] != score[$1] ? score[$0] > score[$1] : $0 < $1 }) {
                if taille + lignes[i].count + 1 > maxCaracteres { continue }
                gardees.append(i); taille += lignes[i].count + 1
            }
            gardees.sort()
        }
        return (tete + ["", "Transcription :"] + gardees.map { lignes[$0] } + ["", "Question : \(question)"]).joined(separator: "\n")
    }

    /// Le message pour toutes les réunions (les plus récentes d'abord, tant qu'elles tiennent dans `maxCaracteres`). Renvoie aussi le
    /// nombre de réunions envoyées (les numéros [R1]… suivent l'ordre de `reunions`).
    public static func messageToutes(_ question: String, reunions: [Reunion], maxCaracteres: Int = 18_000, calendrier: Calendar = .current) -> (texte: String, nombre: Int) {
        var l: [String] = []
        var taille = 0, n = 0
        for (i, r) in reunions.enumerated() {
            let bloc = (["[R\(i + 1)] \(r.titreAffiche) — \(FormatReunion.jourHeure(r.debut, calendrier: calendrier)) — \(FormatReunion.duree(r.duree))"] + resumeNote(r) + [""]).joined(separator: "\n")
            if taille + bloc.count > maxCaracteres { break }
            l.append(bloc); taille += bloc.count; n += 1
        }
        return ((l + ["Question : \(question)"]).joined(separator: "\n"), n)
    }

    private static func entier(_ v: Any?) -> Int? {
        if let n = v as? NSNumber { return n.intValue }
        if let s = v as? String { return Int(s.filter(\.isNumber)) }
        return nil
    }

    /// Lit la réponse pour une réunion de `passages` passages : le texte, et le passage (rang 0…) s'il existe.
    public static func analyser(_ reponse: String, passages: Int) -> Reponse? {
        guard let o = NoteReunion.objetJSON(reponse), let t = (o["reponse"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        let n = entier(o["passage"]).map { $0 - 1 }
        return Reponse(texte: t, passage: n.flatMap { (0..<passages).contains($0) ? $0 : nil })
    }

    /// Lit la réponse pour `nombre` réunions : le texte, et la réunion (rang 0…) si elle existe.
    public static func analyserToutes(_ reponse: String, nombre: Int) -> Reponse? {
        guard let o = NoteReunion.objetJSON(reponse), let t = (o["reponse"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        let n = entier(o["reunion"]).map { $0 - 1 }
        return Reponse(texte: t, reunion: n.flatMap { (0..<nombre).contains($0) ? $0 : nil })
    }
}
