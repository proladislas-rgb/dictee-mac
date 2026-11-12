import Foundation

// Les « vocaux » de la transcription : chaque passage a sa bulle audio (lecture, onde, durée, vitesse), comme un vocal WhatsApp,
// et s'exporte en fichier .m4a. Ici, la logique pure : où est le son d'un passage (piste, bornes alignées), l'onde dessinée à partir
// du vrai niveau, le passage suivant à enchaîner, la vitesse, le nom du fichier, le mélange des deux pistes. Le son, la lecture et
// l'encodage sont dans l'app. Les fichiers son ne vivent que tant que la réunion garde son son (réglage « Garder le son des réunions »).

/// Le son d'un passage : sa piste (le micro pour « Moi », le son du Mac pour les autres) et ses bornes dans le fichier, en secondes
/// (les fichiers sont calés sur l'heure de la réunion : la seconde t du fichier est la seconde t de la réunion).
public struct ExtraitReunion: Equatable, Sendable {
    public var passage: Int
    public var piste: Locuteur
    public var debut: Double
    public var fin: Double
    public init(passage: Int, piste: Locuteur, debut: Double, fin: Double) {
        self.passage = passage; self.piste = piste; self.debut = debut; self.fin = max(fin, debut)
    }
    public var duree: Double { fin - debut }
    /// Une fraction de la bulle (0 à 1, un clic dans l'onde) → la seconde du fichier.
    public func position(_ fraction: Double) -> Double { debut + duree * min(1, max(0, fraction)) }
    /// La seconde du fichier → la fraction jouée (0 à 1).
    public func fraction(_ t: Double) -> Double { duree > 0 ? min(1, max(0, (t - debut) / duree)) : 0 }
}

public enum ExtraitsReunion {
    /// Marges autour des heures de Whisper, qui coupent au ras du mot (le début d'une consonne, la fin d'une voyelle).
    public static let avant = 0.15
    public static let apres = 0.35
    /// Barres de l'onde d'une bulle.
    public static let barres = 36

    /// L'extrait d'un passage : sa piste, ses heures élargies des marges, sans mordre sur le passage voisin de la même piste (au plus
    /// jusqu'au milieu du silence entre eux), borné au fichier (`dureeSon`, nil : inconnue). nil : rien à jouer.
    public static func extrait(_ r: Reunion, passage i: Int, dureeSon: Double? = nil) -> ExtraitReunion? {
        guard r.segments.indices.contains(i) else { return nil }
        let s = r.segments[i]
        let memePiste = r.segments.indices.filter { $0 != i && r.segments[$0].locuteur == s.locuteur }
        var debut = max(0, s.debut - avant), fin = s.fin + apres
        if let p = memePiste.filter({ r.segments[$0].fin <= s.debut + 0.01 }).map({ r.segments[$0].fin }).max() {
            debut = max(debut, min(s.debut, (p + s.debut) / 2))
        }
        if let n = memePiste.filter({ r.segments[$0].debut >= s.fin - 0.01 }).map({ r.segments[$0].debut }).min() {
            fin = min(fin, max(s.fin, (s.fin + n) / 2))
        }
        if let d = dureeSon { fin = min(fin, d); debut = min(debut, d) }
        guard fin - debut > 0.05 else { return nil }
        return ExtraitReunion(passage: i, piste: s.locuteur, debut: debut, fin: fin)
    }

    /// Le passage qui suit `i` dans la transcription et dont le son est encore là (la lecture enchaîne, comme les vocaux).
    public static func suivant(apres i: Int, dans r: Reunion, disponible: (Locuteur) -> Bool) -> Int? {
        guard i + 1 < r.segments.count else { return nil }
        return (i + 1..<r.segments.count).first { disponible(r.segments[$0].locuteur) }
    }

    /// ×1 → ×1,5 → ×2 → ×1.
    public static let vitesses: [Double] = [1, 1.5, 2]
    public static func vitesseSuivante(_ v: Double) -> Double {
        let i = vitesses.firstIndex { abs($0 - v) < 0.01 } ?? -1
        return vitesses[(i + 1) % vitesses.count]
    }
    /// « 1× », « 1,5× », « 2× »
    public static func libelleVitesse(_ v: Double) -> String {
        let t = v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",")
        return t + "\u{00D7}"
    }

    /// « 0:07 », « 1:02 », « 1:02:15 » (comme une bulle de vocal).
    public static func duree(_ secondes: Double) -> String {
        let s = max(0, Int(secondes.rounded()))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    /// « 14h05 »
    public static func heure(_ date: Date, calendrier: Calendar = .current) -> String {
        let c = calendrier.dateComponents([.hour, .minute], from: date)
        return String(format: "%dh%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// Un nom de fichier sans les caractères que le Finder ou les autres apps refusent, espaces resserrés, 80 caractères au plus.
    public static func propre(_ s: String) -> String {
        let interdits = CharacterSet(charactersIn: "/:\\?%*|\"<>").union(.newlines).union(.controlCharacters)
        let t = s.components(separatedBy: interdits).joined(separator: " ").split(whereSeparator: { $0 == " " }).joined(separator: " ")
        return t.count > 80 ? String(t.prefix(80)).trimmingCharacters(in: .whitespaces) : t
    }

    /// « Réunion – Personne 2 – 14h05.m4a » : qui parle (son nom tel que renommé) et l'heure du passage.
    public static func nomFichier(_ r: Reunion, passage i: Int, calendrier: Calendar = .current) -> String {
        guard r.segments.indices.contains(i) else { return "Réunion.m4a" }
        let s = r.segments[i]
        return propre("Réunion \u{2013} \(r.orateur(de: s).nom) \u{2013} \(heure(r.debut.addingTimeInterval(s.debut), calendrier: calendrier))") + ".m4a"
    }

    /// « Réunion – Point Dupont – 14h02.m4a » : toute la réunion (les deux pistes mélangées).
    public static func nomFichierReunion(_ r: Reunion, calendrier: Calendar = .current) -> String {
        propre("Réunion \u{2013} \(r.titreAffiche) \u{2013} \(heure(r.debut, calendrier: calendrier))") + ".m4a"
    }

    /// L'onde d'une bulle : `barres` hauteurs de 0,12 à 1, d'après le niveau réel (moyenne quadratique de chaque tranche, en échelle
    /// de décibels de -50 à 0 dB, puis rapportée à la tranche la plus forte : un passage dit doucement a aussi une onde lisible).
    public static func onde(_ echantillons: [Int16], barres: Int = ExtraitsReunion.barres) -> [Float] {
        guard barres > 0 else { return [] }
        guard !echantillons.isEmpty else { return Array(repeating: 0.12, count: barres) }
        var niveaux: [Float] = []
        niveaux.reserveCapacity(barres)
        for b in 0..<barres {
            let a = echantillons.count * b / barres, z = max(a + 1, echantillons.count * (b + 1) / barres)
            var somme: Double = 0
            for k in a..<min(z, echantillons.count) { let x = Double(echantillons[k]) / 32_768; somme += x * x }
            let rms = (somme / Double(max(1, min(z, echantillons.count) - a))).squareRoot()
            let db = 20 * log10(max(rms, 1e-6))
            niveaux.append(Float(min(1, max(0, (db + 50) / 50))))
        }
        let haut = niveaux.max() ?? 0
        return niveaux.map { haut > 0.05 ? 0.12 + 0.88 * ($0 / haut) : 0.12 }
    }

    /// Les deux pistes mélangées (toute la réunion en un fichier) : somme saturée, de la longueur de la plus longue.
    public static func mixer(_ a: [Int16], _ b: [Int16]) -> [Int16] {
        let n = max(a.count, b.count)
        var sortie = [Int16](repeating: 0, count: n)
        for i in 0..<n {
            let x = Int32(i < a.count ? a[i] : 0) + Int32(i < b.count ? b[i] : 0)
            sortie[i] = Int16(clamping: x)
        }
        return sortie
    }
}
