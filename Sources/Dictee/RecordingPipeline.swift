import AVFoundation
import DicteeCore

/// Reçoit les tampons du micro (n'importe quel format), les convertit en 16 kHz mono 16 bits, mesure le niveau,
/// coupe aux pauses et remet chaque morceau (déjà en WAV) à `surMorceau`. Utilisable sans micro : on peut lui
/// donner les tampons d'un fichier (mode `--transcrire`).
final class RecordingPipeline: @unchecked Sendable {
    static let formatSortie = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true)!

    /// Appelé sur le fil audio : doit rendre la main tout de suite.
    var surMorceau: ((MorceauSon) -> Void)?
    /// Pause d'au moins 0,3 s : voici le morceau tel qu'il partirait si la parole s'arrêtait là (envoi anticipé).
    var surAnticipation: ((MorceauSon) -> Void)?
    /// Niveau instantané 0…1 (pour les barres de l'encoche), appelé sur le fil audio.
    var surNiveau: ((Float) -> Void)?
    /// Le tampon d'origine, tel que reçu du micro (pour la reconnaissance en direct). Valable le temps de l'appel.
    var surTamponBrut: ((AVAudioPCMBuffer) -> Void)?

    /// Appelé une seule fois, au premier tampon reçu (sur le fil audio) : le format réel du micro. Preuve que le micro marche.
    var surPremierTampon: ((AVAudioFormat) -> Void)?
    private var premierRecu = false

    private let lock = NSLock()
    private var echantillons: [Int16] = []
    private var chunker: VoiceChunker
    private var tranchesTraitees = 0
    private var convertisseur: AVAudioConverter?
    private var formatEntree: AVAudioFormat?
    private(set) var termine = false

    /// `tranchesIgnorees` : tranches de 20 ms du début que la détection de parole ignore (petit son de début de dictée).
    init(tranchesIgnorees: Int = 0) {
        var config = VoiceChunker.Config()
        config.ignoredStartFrames = tranchesIgnorees
        if !Settings.rognageFin { config.tailFrames = 1_000_000 }   // mesure : ancien comportement (aucun rognage de fin)
        if !Settings.decoupeLongue { config.microChunkFrames = 1_000_000; config.forcedCutFrames = 1_000_000 }   // mesure : ancien comportement
        chunker = VoiceChunker(config: config)
    }

    var dureeEnregistree: Double { lock.lock(); defer { lock.unlock() }; return Double(echantillons.count) / 16_000 }

    func traiter(_ tampon: AVAudioPCMBuffer) {
        if !premierRecu { premierRecu = true; surPremierTampon?(tampon.format) }
        surTamponBrut?(tampon)
        guard let converti = convertir(tampon), converti.frameLength > 0, let canal = converti.int16ChannelData else { return }
        let nouveaux = UnsafeBufferPointer(start: canal[0], count: Int(converti.frameLength))

        var aEnvoyer: [MorceauSon] = []
        var anticipes: [MorceauSon] = []
        var niveau: Float = 0
        lock.lock()
        if termine { lock.unlock(); return }
        echantillons.append(contentsOf: nouveaux)
        let taille = chunker.config.frameSamples
        while (tranchesTraitees + 1) * taille <= echantillons.count {
            let db = echantillons.withUnsafeBufferPointer { p in
                VoiceChunker.levelDb(of: UnsafeBufferPointer(rebasing: p[(tranchesTraitees * taille)..<((tranchesTraitees + 1) * taille)]))
            }
            tranchesTraitees += 1
            niveau = max(niveau, Self.niveauAffichable(db))
            if let r = chunker.feed(levelDb: db) { aEnvoyer.append(morceau(r, forcee: chunker.derniereCoupeForcee)) }
            else if let r = chunker.anticipation, surAnticipation != nil { anticipes.append(morceau(r)) }
        }
        lock.unlock()
        if niveau > 0 || !aEnvoyer.isEmpty { surNiveau?(niveau) }
        for m in anticipes { surAnticipation?(m) }
        for m in aEnvoyer { surMorceau?(m) }
    }

    /// Fin de la dictée : renvoie le dernier morceau s'il contient de la parole.
    func terminer() -> MorceauSon? {
        lock.lock(); defer { lock.unlock() }
        termine = true
        guard let r = chunker.finish(totalSamples: echantillons.count) else { return nil }
        return morceau(r)
    }

    /// À appeler verrou pris.
    private func morceau(_ r: VoiceChunker.Range, forcee: Bool = false) -> MorceauSon {
        MorceauSon(echantillons: Array(echantillons[r.start..<r.end]), cle: r, coupeForcee: forcee)
    }

    /// -60 dB (silence) → 0, -15 dB (voix forte) → 1.
    static func niveauAffichable(_ db: Float) -> Float { max(0, min(1, (db + 60) / 45)) }

    private func convertir(_ source: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let sortie = Self.formatSortie
        if convertisseur == nil || formatEntree != source.format {
            convertisseur = AVAudioConverter(from: source.format, to: sortie)
            formatEntree = source.format
            if convertisseur == nil { return nil }
        }
        guard let conv = convertisseur else { return nil }
        let ratio = sortie.sampleRate / source.format.sampleRate
        let capacite = AVAudioFrameCount(Double(source.frameLength) * ratio + 64)
        guard let tampon = AVAudioPCMBuffer(pcmFormat: sortie, frameCapacity: capacite) else { return nil }
        var fourni = false
        var erreur: NSError?
        let etat = conv.convert(to: tampon, error: &erreur) { _, statut in
            if fourni { statut.pointee = .noDataNow; return nil }
            fourni = true
            statut.pointee = .haveData
            return source
        }
        if etat == .error { return nil }
        return tampon
    }
}
