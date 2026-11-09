import Foundation

/// Ce que le modèle de langue rend pour une réunion (ou pour une partie d'une longue réunion).
public struct NoteBrute: Equatable, Sendable {
    public var titre: String = ""
    /// « En bref » : une phrase.
    public var enBref: String = ""
    public var dit: [String] = []
    /// La phrase de la transcription que le modèle donne pour chaque point de `dit` (même ordre ; vide = aucune). À vérifier.
    public var citations: [String] = []
    public var decisions: [String] = []
    /// L'échéance dite pour chaque décision (même ordre ; vide = aucune).
    public var decisionsQuand: [String] = []
    public var actions: [ActionReunion] = []
    public var participants: [String] = []
    public init(titre: String = "", dit: [String] = [], decisions: [String] = [], actions: [ActionReunion] = [], participants: [String] = [],
                enBref: String = "", citations: [String] = [], decisionsQuand: [String] = []) {
        self.titre = titre; self.dit = dit; self.decisions = decisions; self.actions = actions; self.participants = participants
        self.enBref = enBref; self.citations = citations; self.decisionsQuand = decisionsQuand
    }
}

/// Les consignes et la lecture des réponses pour la note de réunion. Logique pure ; l'appel à Groq est dans l'app.
public enum NoteReunion {
    private static let regles = """
    Règles absolues :
    - N'écris que ce qui est dit dans la transcription. N'invente aucun nom, chiffre, date, décision ni tâche.
    - Si une information manque (qui, quand, un prix…), ne l'écris pas : laisse le champ vide ou null. Ne complète jamais par une supposition.
    - Ne calcule pas de date : recopie ce qui est dit dans « quand » (« jeudi », « avant le vingt novembre »). L'application en tire la vraie date.
    - « dit » : les points abordés, un par sujet, dans l'ordre de la réunion. Chaque point est COURT (12 mots au maximum, comme un titre de ligne : « Prix sensible, Nathalie en parle à son associé jeudi »). Pas de paragraphe.
    - Pour chaque point de « dit », « citation » est la phrase de la transcription qui l'appuie le mieux, recopiée MOT POUR MOT (une seule phrase, la plus courte qui suffit), sans rien corriger, sans reformuler, sans l'heure ni « Moi / Eux » devant. Si aucune phrase ne l'appuie clairement : null. Ne résume jamais dans « citation ».
    - « decisions » : seulement ce qui a été décidé, convenu ou fait pendant la réunion, c'est-à-dire accepté ou arrêté par les participants. Un souhait, une préférence ou une demande d'un participant (« on aimerait », « je voudrais », « on préférerait », « j'aimerais bien ») n'est PAS une décision tant que personne n'a répondu « d'accord » ou « je retiens ». Une idée évoquée, un « on verra », un « peut-être » non plus : mets-les dans « dit » si elles comptent. Exemple : Paul dit « On aimerait recevoir les machines à Lyon en premier » et Moi répond « Je ne peux pas vous donner de date » : c'est un point de « dit », pas une décision. Autres exemples de vraies décisions : Nathalie dit « on préférerait payer en deux fois » et Moi répond « Alors je retiens le paiement en deux fois » ; Nathalie dit « prenons l'offre complète sans l'option » et Moi répond « Très bien, je note : offre complète, sans la formation ». Dès qu'une proposition est acceptée (« très bien », « d'accord », « je note », « je retiens », « c'est noté »), c'est une décision : ne la laisse pas dans « dit » seulement.
    - Une décision a un « quand » seulement si une échéance est dite pour elle (« signature avant le vingt novembre »), sinon null.
    - « actions » : ce qu'il reste à faire. Une action est une tâche que quelqu'un s'est engagé à faire. « qui » est le prénom dit dans la réunion, « Moi » si c'est la personne dont la voix est « Moi », sinon null. Un engagement pris par un autre participant (« je peux vous donner les chiffres vendredi ») est aussi une action, même si son prénom n'est pas connu (« qui » : null).
    - Écris en français, de façon sobre : des phrases courtes et simples, sans formule de politesse ni mots creux.
    """

    private static let contexte = """
    « Moi » est la personne qui utilise l'application. « Eux » regroupe tous les autres participants : leurs voix ne sont pas séparées, \
    leurs prénoms ne sont connus que s'ils sont dits. La transcription vient d'une reconnaissance vocale et peut contenir des erreurs de mots.
    """

    /// Consigne pour une réunion courte : la transcription entière donne directement la note.
    public static let consigneNote = """
    Tu rédiges la note d'une réunion à partir de sa transcription. \(contexte)

    \(regles)

    Réponds par un seul objet JSON, sans texte autour, de cette forme :
    {"titre": "3 à 8 mots qui disent de quoi parle la réunion", "en_bref": "UNE phrase (25 mots au maximum) : l'essentiel de la réunion, ce qui est décidé et ce qui suit", "dit": [{"point": "un point abordé, 12 mots au maximum", "citation": "la phrase exacte de la transcription, ou null"}], "decisions": [{"quoi": "…", "quand": "échéance dite, ou null"}], "actions": [{"qui": "Prénom ou Moi ou null", "quoi": "…", "quand": "tel que dit, ou null"}], "participants": ["prénoms entendus dans la réunion"]}
    Listes vides si rien n'a été décidé ou promis (une section vide est simplement omise). Le titre n'est pas une phrase ; n'y mets un nom propre que s'il est dit. « en_bref » ne dit que ce que la note contient, en une phrase naturelle et lisible (pas de point-virgule, pas de liste) : ce qui est décidé et la suite précise (qui fait quoi, quand), jamais une formule vague comme « plusieurs actions à réaliser ».
    """

    /// Consigne pour une partie d'une longue réunion : des points, pas encore la note.
    public static let consignePartie = """
    Tu lis une partie de la transcription d'une longue réunion et tu en retires l'essentiel, pour qu'on rédige la note plus tard. \(contexte)

    \(regles)

    Réponds par un seul objet JSON, sans texte autour :
    {"dit": [{"point": "ce qui a été dit d'important, 12 mots au maximum", "citation": "la phrase exacte de la transcription, ou null"}], "decisions": [{"quoi": "…", "quand": "échéance dite, ou null"}], "actions": [{"qui": "Prénom ou Moi ou null", "quoi": "…", "quand": "tel que dit, ou null"}], "participants": ["prénoms entendus"]}
    """

    /// Consigne pour la note finale d'une longue réunion, à partir des parties déjà lues.
    public static let consigneAssemblage = """
    Tu rédiges la note d'une réunion à partir des notes de ses différentes parties (dans l'ordre). \(contexte)

    \(regles)
    - Regroupe ce qui se répète ; garde chaque point, chaque décision et chaque action une seule fois.
    - Garde avec chaque point sa « citation » telle quelle (recopiée des parties ci-dessous, jamais réécrite) ; null s'il n'y en a pas.

    Réponds par un seul objet JSON, sans texte autour, de cette forme :
    {"titre": "3 à 8 mots qui disent de quoi parle la réunion", "en_bref": "UNE phrase (25 mots au maximum) : l'essentiel de la réunion, ce qui est décidé et ce qui suit", "dit": [{"point": "un point abordé, 12 mots au maximum", "citation": "la phrase exacte, ou null"}], "decisions": [{"quoi": "…", "quand": "échéance dite, ou null"}], "actions": [{"qui": "Prénom ou Moi ou null", "quoi": "…", "quand": "tel que dit, ou null"}], "participants": ["prénoms entendus"]}
    """

    public static func messageTranscription(_ segments: [SegmentReunion], duree: Double, debut: Date, calendrier: Calendar = .current) -> String {
        "Réunion du \(FormatReunion.jourHeure(debut, calendrier: calendrier)), durée \(FormatReunion.duree(duree)).\n\nTranscription :\n\(DecoupeReunion.texte(segments))"
    }

    public static func messagePartie(_ segments: [SegmentReunion], numero: Int, sur total: Int) -> String {
        "Partie \(numero) sur \(total) de la transcription :\n\(DecoupeReunion.texte(segments))"
    }

    public static func messageAssemblage(_ parties: [NoteBrute], duree: Double, debut: Date, calendrier: Calendar = .current) -> String {
        var l = ["Réunion du \(FormatReunion.jourHeure(debut, calendrier: calendrier)), durée \(FormatReunion.duree(duree)).", ""]
        for (i, p) in parties.enumerated() {
            l.append("Partie \(i + 1) :")
            for (i, d) in p.dit.enumerated() {
                l.append("Dit : \(d)")
                if p.citations.indices.contains(i), !p.citations[i].isEmpty { l.append("  Citation : « \(p.citations[i]) »") }
            }
            for (i, d) in p.decisions.enumerated() {
                let q = p.decisionsQuand.indices.contains(i) && !p.decisionsQuand[i].isEmpty ? " — \(p.decisionsQuand[i])" : ""
                l.append("Décision : \(d)\(q)")
            }
            for a in p.actions { l.append("Action : \(a.qui ?? "?") — \(a.quoi) — \(a.quand ?? "?")") }
            if !p.participants.isEmpty { l.append("Participants : " + p.participants.joined(separator: ", ")) }
            l.append("")
        }
        return l.joined(separator: "\n")
    }

    // MARK: lecture de la réponse

    /// Extrait l'objet JSON d'une réponse (le modèle peut l'entourer de ```json … ``` ou de quelques mots).
    static func objetJSON(_ reponse: String) -> [String: Any]? {
        guard let debut = reponse.firstIndex(of: "{"), let fin = reponse.lastIndex(of: "}"), debut < fin else { return nil }
        guard let d = String(reponse[debut...fin]).data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }

    private static func texte(_ v: Any?) -> String? {
        guard let s = v as? String else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return nil }
        if ["null", "none", "n/a", "inconnu", "?", "-", "—"].contains(t.lowercased()) { return nil }
        return t
    }

    /// Lit une note (ou une partie) : titre, « En bref », points avec citations, décisions, actions, participants. Nil si ce n'est pas du JSON exploitable.
    public static func analyser(_ reponse: String) -> NoteBrute? {
        guard let o = objetJSON(reponse) else { return nil }
        var n = NoteBrute()
        n.titre = texte(o["titre"]) ?? ""
        n.enBref = texte(o["en_bref"] ?? o["enbref"] ?? o["en bref"]) ?? ""
        // « dit » (ou « points ») est une liste de points, en texte ou en objet {point, citation} ; un « resume » en texte seul est gardé comme un seul point.
        if let pts = (o["dit"] ?? o["points"]) as? [Any] {
            for p in pts {
                if let d = p as? [String: Any], let point = texte(d["point"] ?? d["texte"] ?? d["quoi"]) { n.dit.append(point); n.citations.append(texte(d["citation"]) ?? "") }
                else if let point = texte(p) { n.dit.append(point); n.citations.append("") }
            }
        } else if let r = texte(o["resume"]) { n.dit = [r]; n.citations = [""] }
        for d in o["decisions"] as? [Any] ?? [] {
            if let x = d as? [String: Any], let quoi = texte(x["quoi"] ?? x["decision"] ?? x["texte"]) { n.decisions.append(quoi); n.decisionsQuand.append(texte(x["quand"]) ?? "") }
            else if let quoi = texte(d) { n.decisions.append(quoi); n.decisionsQuand.append("") }
        }
        n.participants = (o["participants"] as? [Any] ?? []).compactMap { texte($0) }
        for a in o["actions"] as? [Any] ?? [] {
            if let d = a as? [String: Any], let quoi = texte(d["quoi"]) {
                n.actions.append(ActionReunion(qui: texte(d["qui"]), quoi: quoi, quand: texte(d["quand"])))
            } else if let quoi = texte(a) {
                n.actions.append(ActionReunion(quoi: quoi))
            }
        }
        return n
    }
}

/// Garde contre l'invention : la note ne garde que ce que la transcription permet de retrouver. Les noms propres, les nombres
/// et les repères de temps (« jeudi », « janvier ») de la note doivent figurer dans ce qui a été dit. Logique pure.
public struct GardeInvention: Sendable {
    private let mots: Set<String>
    private let cles: Set<String>

    public init(segments: [SegmentReunion], motsConnus: [String] = []) {
        var ensemble = Set<String>()
        for s in segments { ensemble.formUnion(FusionPistes.mots(s.texte)) }
        for m in motsConnus { ensemble.formUnion(FusionPistes.mots(m)) }
        mots = ensemble
        cles = Set(ensemble.filter { $0.count >= 4 }.map { ClePhonetique.cle($0) })
    }

    /// Ce mot (ou un mot qui s'écrit presque pareil, ou se prononce pareil) a-t-il été dit ?
    public func dit(_ mot: String) -> Bool {
        let m = ClePhonetique.plier(mot)
        if m.isEmpty || mots.contains(m) { return true }
        if m.count >= 4 {
            if cles.contains(ClePhonetique.cle(m)) { return true }
            let tolerance = m.count >= 8 ? 2 : 1
            for c in mots where abs(c.count - m.count) <= tolerance && ClePhonetique.distance(m, c, plafond: tolerance) <= tolerance { return true }
        }
        return false
    }

    private static let nombresEnLettres: [Int: String] = [
        0: "zero", 1: "un", 2: "deux", 3: "trois", 4: "quatre", 5: "cinq", 6: "six", 7: "sept", 8: "huit", 9: "neuf", 10: "dix",
        11: "onze", 12: "douze", 13: "treize", 14: "quatorze", 15: "quinze", 16: "seize", 20: "vingt", 30: "trente", 40: "quarante",
        50: "cinquante", 60: "soixante", 80: "vingt", 100: "cent",
    ]

    /// Un nombre écrit en chiffres : retrouvé en chiffres, en lettres (jusqu'à 100), ou — pour les grands nombres — avec « mille ».
    func nombreDit(_ n: String) -> Bool {
        if mots.contains(n) { return true }
        guard let v = Int(n) else { return true }
        if v <= 100 {
            if let l = Self.nombresEnLettres[v] { return mots.contains(l) }
            // 17 à 99 : « dix-sept », « vingt-deux »… sont découpés en mots ; on accepte si l'un des morceaux est là
            let dizaine = (v / 10) * 10, unite = v % 10
            let d = Self.nombresEnLettres[dizaine == 70 || dizaine == 90 ? dizaine - 10 : dizaine]
            let u = Self.nombresEnLettres[unite]
            return (d.map { mots.contains($0) } ?? false) || (u.map { mots.contains($0) } ?? false) || mots.contains("dix")
        }
        return mots.contains("mille") || mots.contains("cent") || mots.contains("million") || mots.contains("millions") || mots.contains("milliers")
    }

    private static let reperesTemps: Set<String> = [
        "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche",
        "janvier", "fevrier", "mars", "avril", "mai", "juin", "juillet", "aout", "septembre", "octobre", "novembre", "decembre",
        "demain", "hier", "semaine", "matin", "midi", "soir", "mois", "annee", "trimestre", "prochain", "prochaine",
    ]

    /// Mots qui ressemblent à des noms propres : une majuscule au milieu d'une phrase.
    static func nomsPropres(_ texte: String) -> [String] {
        var sortie: [String] = []
        var debutDePhrase = true
        var courant = ""
        func fermer() {
            defer { courant = "" }
            guard !courant.isEmpty else { return }
            let lettres = courant.filter(\.isLetter).count
            if !debutDePhrase, lettres >= 3, courant.first?.isUppercase == true, courant != "Moi", courant != "Eux" { sortie.append(courant) }
            debutDePhrase = false
        }
        for c in texte {
            if c.isLetter || c.isNumber || ((c == "-" || c == "'" || c == "\u{2019}") && !courant.isEmpty) { courant.append(c) }
            else {
                fermer()
                if ".!?:;\n".contains(c) { debutDePhrase = true }
            }
        }
        fermer()
        return sortie
    }

    /// Les noms propres et nombres de ce texte sont-ils tous dans la réunion ?
    public func soutenu(_ texte: String) -> Bool {
        for nom in Self.nomsPropres(texte) {
            for morceau in nom.split(whereSeparator: { $0 == "-" || $0 == "'" || $0 == "\u{2019}" }) where !dit(String(morceau)) { return false }
        }
        for m in FusionPistes.mots(texte) where m.allSatisfy(\.isNumber) && !nombreDit(m) { return false }
        return true
    }

    /// Un repère de temps (« jeudi 12 nov. ») : chaque jour, mois, nombre écrit doit avoir été dit.
    func tempsSoutenu(_ texte: String) -> Bool {
        for m in FusionPistes.mots(texte) {
            if m.allSatisfy(\.isNumber) { if !nombreDit(m) { return false } }
            else if Self.reperesTemps.contains(m), !mots.contains(m) { return false }
        }
        return true
    }

    private func qui(_ valeur: String?) -> String? {
        guard let v = valeur?.trimmingCharacters(in: .whitespaces), !v.isEmpty else { return nil }
        if v.lowercased() == "moi" { return "Moi" }
        let morceaux = FusionPistes.mots(v)
        return !morceaux.isEmpty && morceaux.allSatisfy({ dit($0) }) ? v : nil
    }

    /// La note débarrassée de ce que la transcription ne soutient pas. `retraits` dit, pour le journal, ce qui a été retiré.
    public func nettoyer(_ note: NoteBrute) -> (note: NoteBrute, retraits: [String]) {
        var n = note
        var retraits: [String] = []
        if !soutenu(n.titre) { retraits.append("titre « \(n.titre) »"); n.titre = "" }
        if !n.enBref.isEmpty, !soutenu(n.enBref) { retraits.append("« en bref » « \(n.enBref) »"); n.enBref = "" }
        var points: [String] = [], citations: [String] = []
        for (i, d) in n.dit.enumerated() {
            if soutenu(d) { points.append(d); citations.append(n.citations.indices.contains(i) ? n.citations[i] : "") } else { retraits.append("point « \(d) »") }
        }
        n.dit = points; n.citations = citations
        var decisions: [String] = [], quand: [String] = []
        for (i, d) in n.decisions.enumerated() {
            guard soutenu(d) else { retraits.append("décision « \(d) »"); continue }
            var q = n.decisionsQuand.indices.contains(i) ? n.decisionsQuand[i] : ""
            if !q.isEmpty, !tempsSoutenu(q) { retraits.append("« quand » de la décision « \(d) » (\(q))"); q = "" }
            decisions.append(d); quand.append(q)
        }
        n.decisions = decisions; n.decisionsQuand = quand
        n.actions = n.actions.compactMap { a in
            guard soutenu(a.quoi) else { retraits.append("action « \(a.quoi) »"); return nil }
            var b = a
            let q = qui(a.qui)
            if a.qui != nil, q == nil { retraits.append("« qui » de l'action « \(a.quoi) » (\(a.qui ?? ""))") }
            b.qui = q
            if let t = a.quand, !tempsSoutenu(t) { retraits.append("« quand » de l'action « \(a.quoi) » (\(t))"); b.quand = nil }
            return b
        }
        n.participants = n.participants.filter { p in
            if ["moi", "eux"].contains(p.lowercased()) { return false }
            let morceaux = FusionPistes.mots(p)
            if !morceaux.isEmpty, morceaux.allSatisfy({ dit($0) }) { return true }
            retraits.append("participant « \(p) »"); return false
        }
        return (n, retraits)
    }
}
