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
    public var locuteur: Locuteur
    public var texte: String

    public init(id: UUID = UUID(), debut: Double, fin: Double, locuteur: Locuteur, texte: String) {
        self.id = id; self.debut = debut; self.fin = max(fin, debut); self.locuteur = locuteur; self.texte = texte
    }
}

/// Une chose à faire notée dans la réunion. `qui` et `quand` restent vides quand la réunion ne les a pas dits.
public struct ActionReunion: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var qui: String?
    public var quoi: String
    public var quand: String?
    public var fait: Bool

    public init(id: UUID = UUID(), qui: String? = nil, quoi: String, quand: String? = nil, fait: Bool = false) {
        self.id = id; self.qui = qui; self.quoi = quoi; self.quand = quand; self.fait = fait
    }
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

    public init(id: UUID = UUID(), debut: Date = Date(), duree: Double = 0, titre: String = "", participants: [String] = [],
                dit: [String] = [], decisions: [String] = [], actions: [ActionReunion] = [], segments: [SegmentReunion] = [],
                etat: EtatNote = .enregistrement, avertissements: [String] = [], sonGarde: Bool = false) {
        self.id = id; self.debut = debut; self.duree = duree; self.titre = titre; self.participants = participants
        self.dit = dit; self.decisions = decisions; self.actions = actions; self.segments = segments
        self.etat = etat; self.avertissements = avertissements; self.sonGarde = sonGarde
    }

    /// Titre à afficher : celui de la note, sinon un titre simple d'après le jour.
    public var titreAffiche: String {
        let t = titre.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Réunion du \(FormatReunion.jourHeure(debut))" : t
    }

    /// Voix distinctes dans la transcription (1 ou 2 : Moi, Eux).
    public var voix: Int { Set(segments.map(\.locuteur)).count }

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

/// Export Markdown de la note : lisible tel quel, collable dans Notion (qui le convertit en blocs).
public enum ReunionMarkdown {
    public static func rendre(_ r: Reunion, calendrier: Calendar = .current) -> String {
        var l: [String] = []
        l.append("# \(r.titreAffiche)")
        l.append("")
        var meta = "\(FormatReunion.jourHeure(r.debut, calendrier: calendrier)) · \(FormatReunion.duree(r.duree))"
        if !r.participants.isEmpty { meta += "\nParticipants : \(r.participants.joined(separator: ", "))" }
        l.append(meta)
        if !r.dit.isEmpty { l += ["", "## Ce qui a été dit", ""] + r.dit.map { "- \($0)" } }
        if !r.decisions.isEmpty { l += ["", "## Ce qui a été décidé", ""] + r.decisions.map { "- \($0)" } }
        if !r.actions.isEmpty {
            l += ["", "## Ce qu'il reste à faire", ""]
            for a in r.actions {
                var ligne = "- [\(a.fait ? "x" : " ")] "
                if let q = a.qui, !q.isEmpty { ligne += "**\(q)** : " }
                ligne += a.quoi
                if let q = a.quand, !q.isEmpty { ligne += " (\(q))" }
                l.append(ligne)
            }
        }
        if !r.avertissements.isEmpty { l += ["", "## À savoir", ""] + r.avertissements.map { "- \($0)" } }
        if !r.segments.isEmpty {
            l += ["", "## Transcription", ""]
            for s in r.segments {
                let heure = FormatReunion.heure(r.debut.addingTimeInterval(s.debut), calendrier: calendrier)
                l.append("**\(s.locuteur.libelle)** (\(heure)) : \(s.texte)")
                l.append("")
            }
            l.removeLast()
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
