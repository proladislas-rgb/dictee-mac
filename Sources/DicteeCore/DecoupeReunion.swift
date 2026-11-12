import Foundation

/// Découpes propres aux réunions : le son (par morceaux de 10 à 30 s, pour peu de requêtes) et la transcription
/// (par parties, pour que la note passe dans les limites de Groq). Logique pure.
public enum DecoupeReunion {
    /// Réglage du découpeur de pauses pour une piste de réunion. Contrairement à la dictée (morceaux courts, réponse vite),
    /// on veut peu de requêtes : coupe à une pause de 0,6 s seulement après 10 s, à une micro-pause de 0,24 s après 20 s,
    /// coupe forcée au point le plus calme après 30 s.
    public static func configurationSon() -> VoiceChunker.Config {
        var c = VoiceChunker.Config()
        c.silenceToCut = 30            // 0,6 s
        c.minChunkFrames = 500         // 10 s
        c.microChunkFrames = 1000      // 20 s
        c.forcedCutFrames = 1500       // 30 s
        c.anticipationFrames = 1_000_000
        return c
    }

    /// « [12:04] Moi : … » une ligne par passage : le texte que la rédaction de la note lit. Les voix séparées y sont « Personne 1 »,
    /// « Personne 2 »… (jamais le nom donné ensuite : la note suit le renommage, `Reunion.renommer`).
    public static func ligne(_ s: SegmentReunion) -> String {
        "[\(FormatReunion.horloge(s.debut))] \(SeparationVoix.nomParDefaut(id: s.idOrateur) ?? s.locuteur.libelle) : \(s.texte)"
    }

    /// Les noms des voix séparées présentes (« Personne 1 »…) : la garde contre l'invention les accepte dans « qui ».
    public static func nomsDesVoix(_ segments: [SegmentReunion]) -> [String] {
        var vus: [String] = []
        for s in segments where SeparationVoix.rang(id: s.idOrateur) != nil {
            if let n = SeparationVoix.nomParDefaut(id: s.idOrateur), !vus.contains(n) { vus.append(n) }
        }
        return vus
    }

    public static func texte(_ segments: [SegmentReunion]) -> String { segments.map(ligne).joined(separator: "\n") }

    /// Coupe la transcription en parties d'au plus `maxCaracteres` (un passage n'est jamais coupé en deux, sauf s'il est
    /// à lui seul plus long). Une transcription courte reste en une partie.
    public static func parties(_ segments: [SegmentReunion], maxCaracteres: Int = 10_000) -> [[SegmentReunion]] {
        var sortie: [[SegmentReunion]] = []
        var courante: [SegmentReunion] = []
        var taille = 0
        for s in segments {
            let n = ligne(s).count + 1
            if !courante.isEmpty, taille + n > maxCaracteres { sortie.append(courante); courante = []; taille = 0 }
            courante.append(s); taille += n
        }
        if !courante.isEmpty { sortie.append(courante) }
        return sortie
    }

    /// Estimation prudente du nombre de jetons d'un texte français (environ 3 caractères par jeton).
    public static func jetons(_ texte: String) -> Int { texte.count / 3 + 1 }
}
