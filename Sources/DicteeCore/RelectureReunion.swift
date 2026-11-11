import Foundation

// Après l'appel, tout l'enregistrement est retranscrit d'un coup avec le modèle précis (whisper-large-v3, horodatages par phrase) au
// lieu de recoller les morceaux du direct : Whisper entend chaque passage avec deux minutes de contexte autour, la ponctuation et les
// mots sont plus justes. Seuls les passages de parole vus pendant l'appel sont envoyés (pas les silences) : ils sont mis bout à bout,
// avec un court silence entre eux, en lots de deux minutes au plus ; les horodatages de Whisper sont ramenés à l'heure de la réunion.
// Logique pure : le son, le réseau et les fichiers sont dans l'app.

/// Un passage de parole d'une piste, en secondes de réunion (tel que le découpage l'a vu pendant l'appel).
public struct PassageParole: Codable, Equatable, Sendable {
    public var debut: Double
    public var fin: Double
    public init(debut: Double, fin: Double) { self.debut = debut; self.fin = max(fin, debut) }
    public var duree: Double { fin - debut }
}

/// Un envoi de la relecture : des passages d'UNE piste mis bout à bout, `LotRelecture.silence` secondes de silence entre deux.
public struct LotRelecture: Equatable, Sendable {
    public var locuteur: Locuteur
    public var passages: [PassageParole]
    /// Silence posé entre deux passages dans le son envoyé (Whisper y voit une pause, pas une coupure).
    public static let silence = 0.6

    public init(locuteur: Locuteur, passages: [PassageParole]) { self.locuteur = locuteur; self.passages = passages }

    /// Durée du son envoyé.
    public var duree: Double { passages.reduce(0) { $0 + $1.duree } + Self.silence * Double(max(0, passages.count - 1)) }
    public var debut: Double { passages.first?.debut ?? 0 }
    public var fin: Double { passages.last?.fin ?? 0 }

    /// Une position dans le son du lot → l'heure de la réunion. Dans un silence ajouté : la fin du passage d'avant.
    public func versReunion(_ t: Double) -> Double {
        var x = 0.0
        for (i, p) in passages.enumerated() {
            if t <= x + p.duree || i == passages.count - 1 { return p.debut + min(max(0, t - x), p.duree) }
            x += p.duree
            if t < x + Self.silence { return p.fin }
            x += Self.silence
        }
        return fin
    }

    /// Le passage du direct qui commence dans ce lot (à une demi-seconde près).
    public func couvre(_ s: SegmentReunion) -> Bool {
        s.locuteur == locuteur && passages.contains { s.debut >= $0.debut - 0.5 && s.debut <= $0.fin }
    }
}

/// Une phrase rendue par Whisper (`verbose_json`) : horodatée dans le son envoyé.
public struct PhraseWhisper: Equatable, Sendable {
    public var debut: Double
    public var fin: Double
    public var texte: String
    /// Probabilité qu'il n'y ait pas de parole (`no_speech_prob`).
    public var pasDeParole: Double
    public init(debut: Double, fin: Double, texte: String, pasDeParole: Double = 0) {
        self.debut = debut; self.fin = fin; self.texte = texte; self.pasDeParole = pasDeParole
    }
}

public enum RelectureReunion {
    /// Durée maximale du son d'un lot (deux minutes : assez de contexte, une requête courte).
    public static let dureeMax = 120.0
    /// Un tour de parole de la transcription relue ne dépasse pas 45 s (l'heure revient à chaque nouvelle minute).
    public static let tourMax = 45.0

    /// Les lots d'une piste. Chaque passage est élargi de `marge` (le découpage coupe parfois au ras du mot), deux passages à moins
    /// de `ecartFusion` s l'un de l'autre n'en font qu'un, un passage plus long que `dureeMax` est coupé.
    public static func lots(_ passages: [PassageParole], locuteur: Locuteur, duree: Double, marge: Double = 0.3, ecartFusion: Double = 1.0,
                            dureeMax: Double = RelectureReunion.dureeMax) -> [LotRelecture] {
        var fusion: [PassageParole] = []
        for p in passages.sorted(by: { $0.debut < $1.debut }) {
            let e = PassageParole(debut: max(0, p.debut - marge), fin: min(max(duree, p.fin), p.fin + marge))
            guard e.duree > 0.05 else { continue }
            if var d = fusion.last, e.debut - d.fin <= ecartFusion { d.fin = max(d.fin, e.fin); fusion[fusion.count - 1] = d }
            else { fusion.append(e) }
        }
        var coupes: [PassageParole] = []
        for p in fusion {
            var a = p.debut
            while p.fin - a > dureeMax { coupes.append(PassageParole(debut: a, fin: a + dureeMax)); a += dureeMax }
            coupes.append(PassageParole(debut: a, fin: p.fin))
        }
        var lots: [LotRelecture] = []
        var courant = LotRelecture(locuteur: locuteur, passages: [])
        for p in coupes {
            if !courant.passages.isEmpty, courant.duree + LotRelecture.silence + p.duree > dureeMax { lots.append(courant); courant.passages = [] }
            courant.passages.append(p)
        }
        if !courant.passages.isEmpty { lots.append(courant) }
        return lots
    }

    /// Les passages de parole d'une piste retrouvés dans une transcription (quand la liste du direct n'a pas été gardée : « Refaire
    /// la note » après un arrêt brutal).
    public static func passages(de segments: [SegmentReunion], locuteur: Locuteur) -> [PassageParole] {
        segments.filter { $0.locuteur == locuteur }.map { PassageParole(debut: $0.debut, fin: max($0.fin, $0.debut + 1)) }
    }

    /// Les passages à relire d'une piste dont on ne connaît pas les passages de parole (réunion d'avant leur enregistrement) : ceux de
    /// la transcription ; si elle n'a rien de cette voix (le direct avait échoué, Verbe fermé tôt), tout le son du fichier.
    public static func passagesInconnus(direct: [SegmentReunion], locuteur: Locuteur, dureeSon: Double) -> [PassageParole] {
        let p = passages(de: direct, locuteur: locuteur)
        return p.isEmpty && dureeSon > 0.5 ? [PassageParole(debut: 0, fin: dureeSon)] : p
    }

    /// Lit une réponse `verbose_json` de Whisper : ses phrases horodatées. Une réponse sans phrases mais avec un texte en donne une seule.
    public static func analyser(_ donnees: Data) -> [PhraseWhisper]? {
        guard let o = (try? JSONSerialization.jsonObject(with: donnees)) as? [String: Any] else { return nil }
        if let liste = o["segments"] as? [[String: Any]] {
            return liste.compactMap { s in
                guard let t = s["text"] as? String else { return nil }
                let d = (s["start"] as? NSNumber)?.doubleValue ?? 0, f = (s["end"] as? NSNumber)?.doubleValue ?? d
                return PhraseWhisper(debut: d, fin: max(d, f), texte: t.trimmingCharacters(in: .whitespacesAndNewlines),
                                     pasDeParole: (s["no_speech_prob"] as? NSNumber)?.doubleValue ?? 0)
            }
        }
        guard let t = o["text"] as? String else { return nil }
        let d = (o["duration"] as? NSNumber)?.doubleValue ?? 0
        return [PhraseWhisper(debut: 0, fin: d, texte: t.trimmingCharacters(in: .whitespacesAndNewlines))]
    }

    /// Les phrases d'un lot en passages de la réunion : heure ramenée à la réunion, phrases vides, « fantômes » de Whisper (« Merci
    /// d'avoir regardé ») et phrases sans parole retirées.
    public static func segments(_ phrases: [PhraseWhisper], lot: LotRelecture) -> [SegmentReunion] {
        phrases.compactMap { p in
            let t = p.texte.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, !TextAssembler.estFantome(t), p.pasDeParole < 0.8 || FusionPistes.mots(t).count >= 4 else { return nil }
            let d = lot.versReunion(p.debut)
            return SegmentReunion(debut: d, fin: max(d, lot.versReunion(p.fin)), locuteur: lot.locuteur, texte: t)
        }
    }

    /// La transcription d'une piste : la relecture, et pour chaque lot que la relecture n'a pas pu refaire (réseau, limite), les
    /// passages du direct qui y commencent. Un passage du direct qu'aucun lot ne couvre est gardé aussi (rien ne se perd).
    public static func assembler(relus: [SegmentReunion], direct: [SegmentReunion], lots: [LotRelecture], echoues: Set<Int>) -> [SegmentReunion] {
        let repli = direct.filter { d in
            let couvrants = lots.indices.filter { lots[$0].couvre(d) }
            return couvrants.isEmpty || couvrants.contains { echoues.contains($0) }
        }
        return (relus + repli).sorted { $0.debut < $1.debut }
    }
}

/// « Note en préparation… » : les étapes et la progression (0 à 1) montrées dans l'îlot.
public enum PreparationNote {
    public static let relecture = "Relecture de tout l\u{2019}appel"
    public static let redaction = "Résumé, décisions, prochaines étapes"
    public static let etapes = [relecture, redaction]
    /// La relecture va jusqu'à 70 %, la rédaction de la note le reste.
    public static let partRelecture = 0.7

    /// `fait` lots relus sur `total` (les derniers morceaux du direct comptent comme un premier lot).
    public static func progresRelecture(fait: Int, sur total: Int) -> Double {
        guard total > 0 else { return partRelecture }
        return partRelecture * min(1, Double(fait) / Double(total))
    }

    /// `partie` parties rédigées sur `total` (+ l'assemblage pour une longue réunion) ; jamais 100 % avant la fin.
    public static func progresRedaction(fait: Int, sur total: Int) -> Double {
        let part = total > 0 ? min(1, Double(fait) / Double(total)) : 0
        return partRelecture + (0.97 - partRelecture) * part
    }

    /// « 34 % »
    public static func pourcent(_ p: Double) -> String { "\(Int((min(1, max(0, p)) * 100).rounded()))\u{202F}%" }
}
