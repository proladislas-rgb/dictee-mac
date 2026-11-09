import Foundation

/// Les petits sons de l'app, fabriqués ici de toutes pièces (sinus avec enveloppe douce) : aucun fichier son, rien
/// n'est copié ni extrait d'une autre app. Logique sans interface, vérifiée par `DicteeControles`.
///
/// - début de dictée : deux notes brèves montantes (120 ms en tout) ;
/// - texte collé : une note brève qui descend (90 ms) ;
/// - annulation : un tic grave étouffé (50 ms).
public enum SonSynthese {
    public static let frequenceEchantillonnage = 44_100

    /// Une note : fréquence au début et à la fin (glissando), départ et durée en secondes, amplitude de 0 à 1.
    public struct Note: Equatable, Sendable {
        public var frequenceDebut: Double
        public var frequenceFin: Double
        public var depart: Double
        public var duree: Double
        public var amplitude: Double
        public init(frequenceDebut: Double, frequenceFin: Double? = nil, depart: Double = 0, duree: Double, amplitude: Double) {
            self.frequenceDebut = frequenceDebut; self.frequenceFin = frequenceFin ?? frequenceDebut
            self.depart = depart; self.duree = duree; self.amplitude = amplitude
        }
    }

    public enum Son: CaseIterable, Sendable { case debut, fin, annulation }

    public static func notes(_ son: Son) -> [Note] {
        switch son {
        case .debut:       // mi5 puis la5, qui se chevauchent un peu
            return [Note(frequenceDebut: 659.25, depart: 0, duree: 0.060, amplitude: 0.16),
                    Note(frequenceDebut: 880.0, depart: 0.045, duree: 0.075, amplitude: 0.16)]
        case .fin:         // sol5 qui descend vers mi5
            return [Note(frequenceDebut: 783.99, frequenceFin: 659.25, duree: 0.090, amplitude: 0.16)]
        case .annulation:  // tic grave, étouffé : peu d'aigus, très court
            return [Note(frequenceDebut: 175.0, frequenceFin: 140.0, duree: 0.050, amplitude: 0.22)]
        }
    }

    /// Durée totale d'un son, en secondes.
    public static func duree(_ son: Son) -> Double { notes(son).map { $0.depart + $0.duree }.max() ?? 0 }

    /// Les échantillons 16 bits mono. Chaque note a une enveloppe en cloche (sin²) : départ et arrivée à zéro, donc aucun « clic ».
    public static func echantillons(_ notes: [Note], frequence: Int = frequenceEchantillonnage) -> [Int16] {
        let fin = notes.map { $0.depart + $0.duree }.max() ?? 0
        let total = Int((fin * Double(frequence)).rounded(.up)) + 1
        var mix = [Double](repeating: 0, count: total)
        for note in notes {
            let debut = Int((note.depart * Double(frequence)).rounded())
            let n = Int((note.duree * Double(frequence)).rounded())
            guard n > 1 else { continue }
            var phase = 0.0
            for i in 0..<n {
                let t = Double(i) / Double(n - 1)                       // 0 → 1 sur la note
                let enveloppe = pow(sin(Double.pi * t), 2)
                let f = note.frequenceDebut + (note.frequenceFin - note.frequenceDebut) * t
                phase += 2 * Double.pi * f / Double(frequence)
                if debut + i < total { mix[debut + i] += note.amplitude * enveloppe * sin(phase) }
            }
        }
        return mix.map { Int16(max(-1, min(1, $0)) * Double(Int16.max)) }
    }

    /// Le fichier WAV du son, prêt à être lu depuis la mémoire.
    public static func wav(_ son: Son) -> Data {
        WAV.encode(samples: echantillons(notes(son)), sampleRate: frequenceEchantillonnage)
    }
}
