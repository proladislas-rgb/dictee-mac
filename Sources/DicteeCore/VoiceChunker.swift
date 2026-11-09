import Foundation

/// Découpe le flux sonore aux pauses de parole, sans jamais toucher au son lui-même :
/// on lui donne le niveau (en dBFS) de chaque petite tranche de 20 ms, il répond par des bornes en échantillons.
///
/// Règles : on coupe quand il y a eu de la parole puis plus de 0,5 s de silence, à condition que le morceau
/// dure au moins 2 s (les morceaux trop courts font halluciner Whisper et multiplient les requêtes).
/// Un silence de début de morceau est rogné (on garde 0,3 s avant la parole).
public struct VoiceChunker: Sendable {
    public struct Config: Sendable {
        public var frameSamples = 320            // 20 ms à 16 kHz
        public var silenceToCut = 25             // 0,5 s
        public var minChunkFrames = 100          // 2 s
        public var minSpeechFrames = 5           // 100 ms de parole pour compter comme parlé
        public var onsetFrames = 3               // 60 ms de suite au-dessus du seuil pour déclarer la parole
        public var preRollFrames = 15            // 0,3 s gardés avant la parole
        public var marginDb: Float = 10          // le seuil de parole est le bruit de fond + 10 dB
        public var minThresholdDb: Float = -45
        public var maxThresholdDb: Float = -35
        public init() {}
    }

    public struct Range: Equatable, Sendable {
        public var start: Int   // en échantillons
        public var end: Int
        public var count: Int { end - start }
    }

    public let config: Config
    private var frame = 0                 // nombre de tranches reçues
    private var chunkStartFrame = 0
    private var speechFrames = 0          // tranches de parole dans le morceau courant
    private var aboveRun = 0              // tranches de suite au-dessus du seuil
    private var silenceRun = 0            // tranches de silence de suite depuis la dernière parole
    private var noiseFloorDb: Float = -55
    private var inSpeech = false

    public init(config: Config = Config()) { self.config = config }

    public var thresholdDb: Float {
        min(config.maxThresholdDb, max(config.minThresholdDb, noiseFloorDb + config.marginDb))
    }
    public var hasSpeechInChunk: Bool { speechFrames >= config.minSpeechFrames }
    public var framesReceived: Int { frame }

    /// Donne le niveau d'une tranche. Renvoie un morceau à envoyer si une pause vient de le terminer.
    public mutating func feed(levelDb: Float) -> Range? {
        frame += 1
        let loud = levelDb > thresholdDb
        if loud {
            aboveRun += 1
            if aboveRun >= config.onsetFrames { inSpeech = true }
        } else {
            aboveRun = 0
            // le bruit de fond ne se met à jour que dans les silences
            noiseFloorDb = noiseFloorDb * 0.97 + levelDb * 0.03
            if inSpeech { inSpeech = false }
        }
        if loud && aboveRun >= config.onsetFrames {
            speechFrames += 1
            silenceRun = 0
        } else if !loud {
            silenceRun += 1
        }

        if speechFrames == 0 {
            // Pas encore de parole : on ne garde que les 0,3 s les plus récentes.
            chunkStartFrame = max(chunkStartFrame, frame - config.preRollFrames)
            return nil
        }
        let length = frame - chunkStartFrame
        if hasSpeechInChunk && silenceRun >= config.silenceToCut && length >= config.minChunkFrames {
            let r = Range(start: chunkStartFrame * config.frameSamples, end: frame * config.frameSamples)
            chunkStartFrame = frame
            speechFrames = 0
            silenceRun = 0
            aboveRun = 0
            return r
        }
        return nil
    }

    /// Fin de la dictée : renvoie le dernier morceau s'il contient de la parole.
    public mutating func finish(totalSamples: Int) -> Range? {
        defer { speechFrames = 0 }
        guard speechFrames >= max(2, config.minSpeechFrames / 2) else { return nil }
        let start = chunkStartFrame * config.frameSamples
        guard totalSamples > start else { return nil }
        return Range(start: start, end: totalSamples)
    }

    /// Niveau d'une tranche, en dBFS (0 = pleine échelle), pour des échantillons 16 bits.
    public static func levelDb(of samples: UnsafeBufferPointer<Int16>) -> Float {
        guard !samples.isEmpty else { return -120 }
        var sum: Double = 0
        for s in samples { let v = Double(s) / 32768.0; sum += v * v }
        let rms = (sum / Double(samples.count)).squareRoot()
        return rms < 1e-6 ? -120 : Float(20 * log10(rms))
    }
}
