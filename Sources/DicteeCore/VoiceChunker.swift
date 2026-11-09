import Foundation

/// Découpe le flux sonore aux pauses de parole, sans jamais toucher au son lui-même :
/// on lui donne le niveau (en dBFS) de chaque petite tranche de 20 ms, il répond par des bornes en échantillons.
///
/// Règles : on coupe quand il y a eu de la parole puis plus de 0,5 s de silence, à condition que le morceau
/// dure au moins 2 s (les morceaux trop courts font halluciner Whisper et multiplient les requêtes).
/// Longues dictées d'une traite : au-delà de 8 s, une micro-pause de 0,24 s suffit ; au-delà de 12 s sans pause,
/// on coupe au point le plus calme des 1,5 dernière seconde (jamais au milieu d'un son fort). Un morceau ne dépasse
/// ainsi jamais ~12 s : le dernier, celui qui fait attendre au relâchement, reste court.
/// Un silence de début de morceau est rogné (on garde 0,3 s avant la parole), et le silence de fin aussi
/// (on garde 0,25 s après le dernier son) : moins de son à envoyer, et deux envois du même morceau sont identiques.
///
/// Envoi anticipé : 0,3 s après le dernier son, `anticipation` donne le morceau tel qu'il serait envoyé si la parole
/// s'arrêtait là. Si au relâchement rien de plus n'a été dit, `finish` rend exactement le même morceau (même `Range`).
public struct MorceauSon: Sendable {
    /// Les échantillons 16 kHz mono du morceau, silence de fin déjà rogné.
    public let echantillons: [Int16]
    /// Bornes dans l'enregistrement : sert de clé pour reconnaître deux envois du même morceau.
    public let cle: VoiceChunker.Range
    public var duree: Double { Double(echantillons.count) / 16_000 }
    /// Vrai si le morceau a été coupé en pleine parole (coupe forcée des longues dictées) et non à une pause.
    public let coupeForcee: Bool
    public init(echantillons: [Int16], cle: VoiceChunker.Range, coupeForcee: Bool = false) {
        self.echantillons = echantillons; self.cle = cle; self.coupeForcee = coupeForcee
    }
}

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
        public var tailFrames = 12               // 0,25 s gardés après le dernier son
        public var anticipationFrames = 15       // 0,3 s sans le moindre son : on peut envoyer à l'avance
        public var microChunkFrames = 400        // 8 s : au-delà, une micro-pause suffit pour couper
        public var microSilenceFrames = 12       // 0,24 s
        public var forcedCutFrames = 600         // 12 s sans pause : coupe forcée au point le plus calme
        public var forcedWindowFrames = 75       // ... cherché dans les 1,5 dernière seconde
        /// Tranches du tout début ignorées par la détection de parole (le petit son de début de dictée, capté par le micro,
        /// ne doit pas passer pour de la voix). Le son, lui, n'est pas touché, et le rognage de début garde d'autant plus de tranches avant la parole.
        public var ignoredStartFrames = 0
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
    private var lastLoudEnd = 0               // fin (en tranches) de la dernière tranche au-dessus du seuil
    private var recentLevels: [Float] = []    // niveaux des dernières tranches (pour la coupe forcée)
    private var recentSpeech: [Bool] = []     // ... et si chacune comptait comme parole

    /// Morceau à envoyer à l'avance, non nul seulement juste après la tranche qui a atteint la pause d'anticipation.
    public private(set) var anticipation: Range?
    /// Vrai si la dernière coupe renvoyée par `feed` était une coupe forcée (en pleine parole).
    public private(set) var derniereCoupeForcee = false

    public init(config: Config = Config()) { self.config = config }

    public var thresholdDb: Float {
        min(config.maxThresholdDb, max(config.minThresholdDb, noiseFloorDb + config.marginDb))
    }
    public var hasSpeechInChunk: Bool { speechFrames >= config.minSpeechFrames }
    public var framesReceived: Int { frame }

    /// Donne le niveau d'une tranche. Renvoie un morceau à envoyer si une pause vient de le terminer.
    public mutating func feed(levelDb: Float) -> Range? {
        frame += 1
        anticipation = nil
        derniereCoupeForcee = false
        let ignoree = frame <= config.ignoredStartFrames
        let loud = !ignoree && levelDb > thresholdDb
        if loud { lastLoudEnd = frame }
        recentLevels.append(levelDb)
        if recentLevels.count > config.forcedWindowFrames + 10 { recentLevels.removeFirst(recentLevels.count - config.forcedWindowFrames - 10) }
        if loud {
            aboveRun += 1
            if aboveRun >= config.onsetFrames { inSpeech = true }
        } else {
            aboveRun = 0
            // le bruit de fond ne se met à jour que dans les silences (pas dans les tranches ignorées du début)
            if !ignoree { noiseFloorDb = noiseFloorDb * 0.97 + levelDb * 0.03 }
            if inSpeech { inSpeech = false }
        }
        let parole = loud && aboveRun >= config.onsetFrames
        if parole {
            speechFrames += 1
            silenceRun = 0
        } else if !loud {
            silenceRun += 1
        }
        recentSpeech.append(parole)
        if recentSpeech.count > config.forcedWindowFrames + 10 { recentSpeech.removeFirst(recentSpeech.count - config.forcedWindowFrames - 10) }

        if speechFrames == 0 {
            // Pas encore de parole : on ne garde que les 0,3 s les plus récentes.
            // (les tranches ignorées du début s'ajoutent : une parole commencée pendant le petit son n'est pas rognée)
            chunkStartFrame = max(chunkStartFrame, frame - config.preRollFrames - config.ignoredStartFrames)
            return nil
        }
        let length = frame - chunkStartFrame
        if hasSpeechInChunk && frame - lastLoudEnd == config.anticipationFrames {
            anticipation = Range(start: chunkStartFrame * config.frameSamples, end: trimmedEndFrame(maxFrame: frame) * config.frameSamples)
        }
        let silenceVoulu = length >= config.microChunkFrames ? config.microSilenceFrames : config.silenceToCut
        if hasSpeechInChunk && silenceRun >= silenceVoulu && length >= config.minChunkFrames {
            let r = Range(start: chunkStartFrame * config.frameSamples, end: trimmedEndFrame(maxFrame: frame) * config.frameSamples)
            chunkStartFrame = frame
            speechFrames = 0
            silenceRun = 0
            aboveRun = 0
            return r
        }
        if hasSpeechInChunk && length >= config.forcedCutFrames {
            let r = forcedCut()
            derniereCoupeForcee = r != nil
            return r
        }
        return nil
    }

    /// Coupe forcée : le point le plus calme (niveau lissé sur 3 tranches) des `forcedWindowFrames` dernières tranches,
    /// sans les 4 plus récentes. Le morceau suivant commence là, avec la parole déjà entendue après ce point.
    private mutating func forcedCut() -> Range? {
        let n = recentLevels.count
        let fenetre = min(config.forcedWindowFrames, n - 6)
        guard fenetre > 3 else { return nil }
        var meilleur = -1
        var niveau = Float.greatestFiniteMagnitude
        for i in (n - 4 - fenetre)..<(n - 4) {
            let lisse = (recentLevels[i - 1] + recentLevels[i] + recentLevels[i + 1]) / 3
            if lisse <= niveau { niveau = lisse; meilleur = i }   // à égalité, le plus récent : morceaux plus longs, moins de requêtes
        }
        guard meilleur >= 0 else { return nil }
        // recentLevels[i] est la tranche numéro (frame - n + i + 1) ; la coupe se place après elle.
        let coupe = frame - n + meilleur + 1
        guard coupe > chunkStartFrame + config.minChunkFrames else { return nil }
        let r = Range(start: chunkStartFrame * config.frameSamples, end: coupe * config.frameSamples)
        chunkStartFrame = coupe
        let apres = frame - coupe
        speechFrames = recentSpeech.suffix(apres).filter { $0 }.count
        return r
    }

    /// Fin de la dictée : renvoie le dernier morceau s'il contient de la parole.
    public mutating func finish(totalSamples: Int) -> Range? {
        defer { speechFrames = 0 }
        guard speechFrames >= max(2, config.minSpeechFrames / 2) else { return nil }
        let start = chunkStartFrame * config.frameSamples
        guard totalSamples > start else { return nil }
        let fin = trimmedEndFrame(maxFrame: frame)
        // Le son continue jusqu'au bout : on garde aussi la fin de la dernière tranche, incomplète.
        let end = fin >= frame ? totalSamples : fin * config.frameSamples
        return Range(start: start, end: end)
    }

    /// Fin du morceau courant, silence de fin rogné : dernier son + `tailFrames`, sans dépasser `maxFrame`.
    private func trimmedEndFrame(maxFrame: Int) -> Int {
        min(maxFrame, max(lastLoudEnd, chunkStartFrame + 1) + config.tailFrames)
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
