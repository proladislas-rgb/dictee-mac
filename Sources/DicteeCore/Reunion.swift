import Foundation

/// Qui parle : la personne qui utilise Verbe (le micro) ou les autres participants (le son du Mac).
/// Deux pistes séparées donnent cette information sans rien deviner.
public enum Locuteur: String, Codable, Sendable {
    case moi, eux
    public var libelle: String { self == .moi ? "Moi" : "Eux" }
}

/// Un passage de la transcription : qui, quand (secondes depuis le début de la réunion, pauses déduites) et quoi.
public struct SegmentReunion: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var debut: Double
    public var fin: Double
    /// La piste d'où vient le passage (le micro ou le son du Mac).
    public var locuteur: Locuteur
    public var texte: String
    /// L'orateur (`OrateurReunion.id`) : nil = celui de la piste (« moi » ou « eux »). La séparation des voix donnera plusieurs
    /// orateurs à la piste du Mac ; leur nom vit dans `Reunion.orateurs`, jamais dans le passage (on renomme une fois pour toutes).
    public var orateur: String?

    public init(id: UUID = UUID(), debut: Double, fin: Double, locuteur: Locuteur, texte: String, orateur: String? = nil) {
        self.id = id; self.debut = debut; self.fin = max(fin, debut); self.locuteur = locuteur; self.texte = texte; self.orateur = orateur
    }

    /// L'identifiant de l'orateur, celui de la piste par défaut.
    public var idOrateur: String { orateur ?? locuteur.rawValue }
}

/// Une voix de la réunion. Aujourd'hui une par piste (« Moi » : le micro, « Eux » : le son du Mac). Le nom se change une fois pour
/// toutes : chaque passage renvoie à l'orateur par son identifiant, jamais par son nom.
public struct OrateurReunion: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var nom: String
    public var piste: Locuteur
    public init(id: String, nom: String, piste: Locuteur) { self.id = id; self.nom = nom; self.piste = piste }
    /// L'orateur d'une piste tant qu'on ne sépare pas les voix.
    public static func dePiste(_ l: Locuteur) -> OrateurReunion { OrateurReunion(id: l.rawValue, nom: l.libelle, piste: l) }
}

/// Un sujet du résumé : un titre court et ses puces (une puce peut avoir des détails en dessous).
public struct SujetReunion: Codable, Equatable, Sendable {
    public var titre: String
    public var puces: [PuceReunion]
    public init(titre: String, puces: [PuceReunion]) { self.titre = titre; self.puces = puces }
}

public struct PuceReunion: Codable, Equatable, Sendable {
    public var texte: String
    public var sous: [String]
    public init(texte: String, sous: [String] = []) { self.texte = texte; self.sous = sous }
}

/// Une chose à faire notée dans la réunion. `qui` et `quand` restent vides quand la réunion ne les a pas dits.
public struct ActionReunion: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var qui: String?
    public var quoi: String
    /// L'échéance telle qu'elle a été dite (« jeudi », « avant le vingt novembre »).
    public var quand: String?
    public var fait: Bool
    /// L'échéance en date réelle (« 2026-11-12 »), calculée à partir de la date de la réunion quand « quand » le permet.
    /// Absente dans les anciennes notes et quand « quand » est trop vague (« bientôt »).
    public var echeance: String?

    public init(id: UUID = UUID(), qui: String? = nil, quoi: String, quand: String? = nil, fait: Bool = false, echeance: String? = nil) {
        self.id = id; self.qui = qui; self.quoi = quoi; self.quand = quand; self.fait = fait; self.echeance = echeance
    }
}

/// Une phrase exacte de la transcription qui appuie un point de « Dit » : qui l'a dite et quand dans l'appel.
/// `texte` est toujours une portion de la transcription, jamais une reformulation.
public struct CitationReunion: Codable, Equatable, Sendable {
    /// Rang du point dans `Reunion.dit`.
    public var point: Int
    public var texte: String
    public var locuteur: Locuteur
    /// Secondes depuis le début de la réunion (début du passage où la phrase a été dite).
    public var debut: Double
    public var fin: Double
    public init(point: Int, texte: String, locuteur: Locuteur, debut: Double, fin: Double) {
        self.point = point; self.texte = texte; self.locuteur = locuteur; self.debut = debut; self.fin = max(fin, debut)
    }
}

/// L'échéance d'une décision (« avant le vingt novembre ») : ce qui a été dit et, si on peut, la date réelle.
public struct EcheanceReunion: Codable, Equatable, Sendable {
    public var quand: String
    public var date: String?
    public init(quand: String, date: String? = nil) { self.quand = quand; self.date = date }
}

/// Où en est une réunion : de l'enregistrement à la note prête.
public enum EtatNote: String, Codable, Sendable {
    case enregistrement      // en cours (ou interrompue par un arrêt brutal : voir `ArchiveReunions.reprendreApresArret`)
    case transcription       // le son est découpé et envoyé à Whisper
    case redaction           // la note est écrite à partir de la transcription
    case prete
    case sansNote            // la transcription est là, la note n'a pas pu être écrite (réseau, quota) : on peut réessayer
}

/// Une réunion enregistrée : transcription « Moi / Eux » et note. Tout est gardé sur le Mac, en JSON et en Markdown.
public struct Reunion: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var debut: Date
    /// Durée enregistrée en secondes (les pauses ne comptent pas).
    public var duree: Double
    public var titre: String
    public var participants: [String]
    /// « Ce qui a été dit » : les points abordés, une phrase courte par sujet.
    public var dit: [String]
    public var decisions: [String]
    public var actions: [ActionReunion]
    public var segments: [SegmentReunion]
    public var etat: EtatNote
    /// Ce que la réunion a rencontré de gênant (son du Mac absent, passages non transcrits…), dit simplement.
    public var avertissements: [String]
    public var sonGarde: Bool
    // Ajouts de la présentation « D'un coup d'œil » : tous facultatifs, les anciennes notes se lisent sans eux.
    /// « En bref » : une phrase.
    public var enBref: String?
    /// Une citation exacte par point de « Dit » quand la transcription l'a permis (les autres points n'en ont pas).
    public var citations: [CitationReunion]?
    /// Une échéance (ou rien) par décision, dans l'ordre de `decisions`.
    public var decisionsEcheances: [EcheanceReunion?]?
    /// Les moments marqués pendant l'appel (« Ajouter un point » dans l'îlot), en secondes de réunion.
    public var points: [Double]?
    // Ajouts de la note « façon Wispr Flow » : facultatifs eux aussi.
    /// Le résumé rangé par sujets (titres et puces). Les notes plus anciennes n'ont que `dit`.
    public var sujets: [SujetReunion]?
    /// Les orateurs et leur nom (nil : « Moi » et « Eux »).
    public var orateurs: [OrateurReunion]?
    /// Vrai quand tout l'enregistrement a été retranscrit d'un coup après l'appel (modèle précis) ; faux ou absent : la transcription
    /// est celle du direct, recollée.
    public var relue: Bool?

    public init(id: UUID = UUID(), debut: Date = Date(), duree: Double = 0, titre: String = "", participants: [String] = [],
                dit: [String] = [], decisions: [String] = [], actions: [ActionReunion] = [], segments: [SegmentReunion] = [],
                etat: EtatNote = .enregistrement, avertissements: [String] = [], sonGarde: Bool = false,
                enBref: String? = nil, citations: [CitationReunion]? = nil, decisionsEcheances: [EcheanceReunion?]? = nil) {
        self.id = id; self.debut = debut; self.duree = duree; self.titre = titre; self.participants = participants
        self.dit = dit; self.decisions = decisions; self.actions = actions; self.segments = segments
        self.etat = etat; self.avertissements = avertissements; self.sonGarde = sonGarde
        self.enBref = enBref; self.citations = citations; self.decisionsEcheances = decisionsEcheances
    }

    /// La même réunion avec les échéances que la note n'a pas enregistrées calculées depuis le jour de la réunion (les anciennes notes
    /// gardent seulement « jeudi » : « jeudi » devient la date du jeudi suivant). Ce qui est déjà calculé n'est pas touché.
    public func echeancesCalculees(calendrier: Calendar = .current) -> Reunion {
        var r = self
        r.actions = actions.map { a in
            guard a.echeance == nil, let q = a.quand else { return a }
            var b = a; b.echeance = Echeance.analyser(q, depuis: debut, calendrier: calendrier).date; return b
        }
        return r
    }

    /// La citation d'un point de « Dit », s'il y en a une.
    public func citation(point: Int) -> CitationReunion? { citations?.first { $0.point == point } }

    /// L'échéance d'une décision, si elle en a une.
    public func echeance(decision i: Int) -> EcheanceReunion? {
        guard let e = decisionsEcheances, e.indices.contains(i) else { return nil }
        return e[i]
    }

    /// Titre à afficher : celui de la note, sinon un titre simple d'après le jour.
    public var titreAffiche: String {
        let t = titre.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Réunion du \(FormatReunion.jourHeure(debut))" : t
    }

    /// Voix distinctes dans la transcription (1 ou 2 : Moi, Eux).
    public var voix: Int { Set(segments.map(\.idOrateur)).count }

    /// L'orateur d'un passage (son nom tel que renommé).
    public func orateur(de s: SegmentReunion) -> OrateurReunion { orateur(id: s.idOrateur, piste: s.locuteur) }

    public func orateur(id: String, piste: Locuteur = .eux) -> OrateurReunion {
        orateurs?.first { $0.id == id } ?? (Locuteur(rawValue: id).map(OrateurReunion.dePiste) ?? OrateurReunion(id: id, nom: id, piste: piste))
    }

    /// Les orateurs qu'on entend, dans l'ordre où ils parlent pour la première fois.
    public var orateursEntendus: [OrateurReunion] {
        var vus: [String] = []
        for s in segments where !vus.contains(s.idOrateur) { vus.append(s.idOrateur) }
        return vus.map { id in orateur(id: id, piste: segments.first { $0.idOrateur == id }?.locuteur ?? .eux) }
    }

    /// Renomme un orateur une fois pour toutes : chaque passage le suit (il ne garde que l'identifiant), et les prochaines étapes
    /// et participants qui portaient l'ancien nom prennent le nouveau. Un nom vide rend le nom de la piste.
    public mutating func renommer(orateur id: String, en nom: String) {
        let ancien = orateur(id: id)
        let n = nom.trimmingCharacters(in: .whitespacesAndNewlines)
        let nouveau = n.isEmpty ? (Locuteur(rawValue: id)?.libelle ?? ancien.nom) : n
        guard nouveau != ancien.nom else { return }
        var liste = orateurs ?? orateursEntendus
        if let i = liste.firstIndex(where: { $0.id == id }) { liste[i].nom = nouveau } else { liste.append(OrateurReunion(id: id, nom: nouveau, piste: ancien.piste)) }
        orateurs = liste
        for i in actions.indices where actions[i].qui == ancien.nom { actions[i].qui = nouveau }
        if let i = participants.firstIndex(of: ancien.nom) { participants[i] = nouveau }
        else if ancien.nom == Locuteur.eux.libelle, !participants.contains(nouveau) { participants.append(nouveau) }
    }

    public var motsTranscrits: Int { segments.reduce(0) { $0 + Historique.compterMots($1.texte) } }
}

/// Dates et durées à la française.
public enum FormatReunion {
    /// « lun. 9 nov. 2026, 14:02 »
    public static func jourHeure(_ date: Date, calendrier: Calendar = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR"); f.calendar = calendrier; f.timeZone = calendrier.timeZone
        f.dateFormat = "EEE d MMM yyyy, HH:mm"
        return f.string(from: date)
    }

    public static func heure(_ date: Date, calendrier: Calendar = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR"); f.calendar = calendrier; f.timeZone = calendrier.timeZone
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    /// « 38 min », « 1 h 12 », « 45 s » (moins d'une minute), « 2 h » pile.
    public static func duree(_ secondes: Double) -> String {
        let s = max(0, Int(secondes.rounded()))
        if s < 60 { return "\(s) s" }
        let minutes = Int((Double(s) / 60).rounded())
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) h" : "\(h) h \(String(format: "%02d", m))"
    }

    /// Minuterie : « 12:48 », « 1:02:15 ».
    public static func horloge(_ secondes: Double) -> String {
        let s = max(0, Int(secondes))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
    }
}

/// La transcription telle que la note la montre : les passages dans l'ordre, l'heure seulement sur la première ligne de chaque minute
/// (« 14:13 »), les points marqués pendant l'appel posés avant le premier passage qui commence après eux. Logique pure.
public enum LignesTranscription {
    public enum Element: Equatable, Sendable {
        /// Le passage `index` de `Reunion.segments` ; `heure` (« 14:13 ») sur la première ligne d'une nouvelle minute, sinon nil.
        case passage(index: Int, heure: String?)
        /// Un point marqué, en secondes de réunion.
        case point(Double)
    }

    public static func elements(_ r: Reunion, calendrier: Calendar = .current) -> [Element] {
        var sortie: [Element] = []
        var points = (r.points ?? []).sorted()
        var minute: Int?
        for (i, s) in r.segments.enumerated() {
            while let t = points.first, t < s.debut { sortie.append(.point(t)); points.removeFirst() }
            let instant = r.debut.addingTimeInterval(s.debut)
            let m = Int((instant.timeIntervalSinceReferenceDate / 60).rounded(.down))
            sortie.append(.passage(index: i, heure: m == minute ? nil : FormatReunion.heure(instant, calendrier: calendrier)))
            minute = m
        }
        sortie += points.map { .point($0) }
        return sortie
    }
}

/// Export Markdown de la note : lisible tel quel, collable dans Notion (qui le convertit en blocs).
public enum ReunionMarkdown {
    /// « , juste après « tous les textes avant le 25 » » : la fin de ce qui venait d'être dit au moment marqué.
    public static func avant(_ t: Double, dans segments: [SegmentReunion]) -> String {
        guard let s = segments.last(where: { $0.debut <= t }) else { return "" }
        let m = s.texte.split(separator: " ")
        guard !m.isEmpty else { return "" }
        let fin = m.suffix(6).joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?…"))
        return ", juste après « " + (m.count > 6 ? "\u{2026}" : "") + fin + " »"
    }

    public static func rendre(_ r: Reunion, calendrier: Calendar = .current) -> String {
        var l: [String] = []
        l.append("# \(r.titreAffiche)")
        l.append("")
        var meta = "\(FormatReunion.jourHeure(r.debut, calendrier: calendrier)) · \(FormatReunion.duree(r.duree))"
        if !r.participants.isEmpty { meta += "\nParticipants : \(r.participants.joined(separator: ", "))" }
        l.append(meta)
        if let b = r.enBref?.trimmingCharacters(in: .whitespacesAndNewlines), !b.isEmpty { l += ["", b] }
        if let sujets = r.sujets, !sujets.isEmpty {
            l += ["", "## Résumé par sujet"]
            for s in sujets {
                l.append("")
                if !s.titre.isEmpty { l += ["### \(s.titre)", ""] }
                for p in s.puces {
                    l.append("- \(p.texte)")
                    l += p.sous.map { "  - \($0)" }
                }
            }
        } else if !r.dit.isEmpty {
            l += ["", "## Ce qui a été dit", ""] + r.dit.map { "- \($0)" }
        }
        if !r.decisions.isEmpty {
            l += ["", "## Décisions", ""] + r.decisions.enumerated().map { i, d in "- \(d)" + (r.echeance(decision: i).map { " (\($0.quand))" } ?? "") }
        }
        if !r.actions.isEmpty {
            l += ["", "## Prochaines étapes", ""]
            for a in r.actions {
                var ligne = "- [\(a.fait ? "x" : " ")] "
                if let q = a.qui, !q.isEmpty { ligne += "**\(q)** : " }
                ligne += a.quoi
                let e = Echeance.etiquette(quand: a.quand, date: a.echeance, calendrier: calendrier)
                if !e.sansDate { ligne += " (\(e.texte))" }
                l.append(ligne)
            }
        }
        if let p = r.points, !p.isEmpty {
            l += ["", "## Points marqués pendant l'appel", ""] + p.sorted().map { "- " + FormatReunion.heure(r.debut.addingTimeInterval($0), calendrier: calendrier) + Self.avant($0, dans: r.segments) }
        }
        if !r.avertissements.isEmpty { l += ["", "## À savoir", ""] + r.avertissements.map { "- \($0)" } }
        if !r.segments.isEmpty {
            l += ["", "## Transcription"]
            for e in LignesTranscription.elements(r, calendrier: calendrier) {
                switch e {
                case .point(let t):
                    l += ["", "*Point marqué · \(FormatReunion.heure(r.debut.addingTimeInterval(t), calendrier: calendrier))*"]
                case .passage(let i, let heure):
                    let s = r.segments[i]
                    l += ["", "**\(r.orateur(de: s).nom)**" + (heure.map { " · \($0)" } ?? ""), s.texte]
                }
            }
        }
        return l.joined(separator: "\n") + "\n"
    }
}

/// Fichiers d'une réunion dans le dossier des réunions : un JSON et un Markdown par réunion, nom stable.
public enum ArchiveReunions {
    public static func nomDeBase(_ r: Reunion, calendrier: Calendar = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR_POSIX"); f.calendar = calendrier; f.timeZone = calendrier.timeZone
        f.dateFormat = "yyyy-MM-dd_HHmm"
        return "\(f.string(from: r.debut))_\(r.id.uuidString.prefix(8).lowercased())"
    }

    public static func encoder(_ r: Reunion) -> Data? {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? e.encode(r)
    }

    public static func decoder(_ donnees: Data) -> Reunion? {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return try? d.decode(Reunion.self, from: donnees)
    }

    /// Au lancement : une réunion restée « en cours » ou « en transcription » n'a plus personne pour la mener (arrêt brutal,
    /// app quittée). Sa transcription est gardée telle quelle ; elle passe en « sans note » pour qu'on puisse en écrire une.
    public static func reprendreApresArret(_ r: Reunion) -> Reunion {
        guard r.etat == .enregistrement || r.etat == .transcription || r.etat == .redaction else { return r }
        var s = r
        s.etat = .sansNote
        if s.segments.isEmpty == false || s.duree > 0 {
            s.avertissements.append("Cette réunion s'est arrêtée avant la fin (Verbe a été fermé). La transcription est celle des morceaux déjà reçus.")
        }
        return s
    }
}
