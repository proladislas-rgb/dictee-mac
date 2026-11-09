import AVFoundation
import DicteeCore

/// Un morceau de son d'une piste de réunion, prêt à partir chez Whisper : qui parle, quand (secondes de réunion) et le son 16 kHz mono.
struct MorceauReunion: @unchecked Sendable {
    var locuteur: Locuteur
    var debut: Double
    var echantillons: [Int16]
    var duree: Double { Double(echantillons.count) / 16_000 }
}

/// Une piste de la réunion (le micro = « Moi », le son du Mac = « Eux ») : convertit les tampons en 16 kHz mono 16 bits, mesure le
/// niveau, coupe aux pauses (`DecoupeReunion`) et rend chaque morceau avec son heure de début. Contrairement à la dictée, elle ne garde
/// pas tout le son en mémoire (une réunion dure des heures) : seul le morceau en cours est conservé. Utilisable sans micro (mode
/// `--reunion-test` : on lui donne les tampons d'un fichier).
final class PisteReunion: @unchecked Sendable {
    static let formatSortie = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true)!

    let locuteur: Locuteur
    /// Appelé sur le fil audio : doit rendre la main tout de suite.
    var surMorceau: ((MorceauReunion) -> Void)?
    /// L'horloge de la réunion (secondes enregistrées, pauses déduites) : donne l'heure du premier tampon de chaque tranche d'enregistrement.
    var horloge: () -> Double = { 0 }
    /// Si renseigné, tout le son de la piste est écrit dans ce fichier WAV (réglage « Garder le son des réunions »).
    private var ecrivain: EcrivainWAV?

    private let verrou = NSLock()
    private var chunker = VoiceChunker(config: DecoupeReunion.configurationSon())
    private var echantillons: [Int16] = []        // son depuis `decalage`
    private var decalage = 0                      // échantillons déjà jetés (avant le morceau en cours)
    private var tranchesTraitees = 0
    private var base: Double?                     // heure de réunion du premier échantillon de la tranche d'enregistrement en cours
    private var actif = true
    private var convertisseur: AVAudioConverter?
    private var formatEntree: AVAudioFormat?
    private var niveauCourant: Float = 0
    private(set) var secondesRecues: Double = 0
    private(set) var aRecuDuSon = false           // au moins un échantillon non nul (un son du Mac qui ne donne que des zéros est suspect)
    private(set) var morceauxEmis = 0

    init(locuteur: Locuteur, fichierSon: URL? = nil) {
        self.locuteur = locuteur
        if let fichierSon { ecrivain = EcrivainWAV(url: fichierSon) }
    }

    /// Niveau 0…1 depuis la dernière lecture (puis retombe) : sert aux deux traces de l'encoche.
    func niveau() -> Float {
        verrou.lock(); defer { verrou.unlock() }
        let n = niveauCourant; niveauCourant = 0; return n
    }

    func traiter(_ tampon: AVAudioPCMBuffer) {
        guard let mono = Self.enMono(tampon), let converti = convertir(mono), converti.frameLength > 0, let canal = converti.int16ChannelData else { return }
        let nouveaux = UnsafeBufferPointer(start: canal[0], count: Int(converti.frameLength))
        var emis: [MorceauReunion] = []
        verrou.lock()
        guard actif else { verrou.unlock(); return }
        if base == nil { base = max(0, horloge() - Double(nouveaux.count) / 16_000) }
        secondesRecues += Double(nouveaux.count) / 16_000
        if !aRecuDuSon, nouveaux.contains(where: { $0 != 0 }) { aRecuDuSon = true }
        echantillons.append(contentsOf: nouveaux)
        ecrivain?.ajouter(Array(nouveaux))
        let taille = chunker.config.frameSamples
        while (tranchesTraitees + 1) * taille <= decalage + echantillons.count {
            let debut = tranchesTraitees * taille - decalage
            let db = echantillons.withUnsafeBufferPointer { VoiceChunker.levelDb(of: UnsafeBufferPointer(rebasing: $0[debut..<(debut + taille)])) }
            tranchesTraitees += 1
            niveauCourant = max(niveauCourant, RecordingPipeline.niveauAffichable(db))
            if let r = chunker.feed(levelDb: db) { if let m = morceau(r) { emis.append(m) } }
        }
        elaguer()
        verrou.unlock()
        for m in emis { surMorceau?(m) }
    }

    /// Pause ou arrêt : le dernier morceau de la tranche d'enregistrement part, et la piste cesse d'écouter.
    /// Après une pause, `reprendre()` repart sur une horloge neuve (les pauses ne comptent pas dans les heures).
    func suspendre() {
        verrou.lock()
        var dernier: MorceauReunion?
        if actif, let r = chunker.finish(totalSamples: decalage + echantillons.count) { dernier = morceau(r) }
        actif = false
        echantillons = []; decalage = 0; tranchesTraitees = 0; base = nil
        chunker = VoiceChunker(config: DecoupeReunion.configurationSon())
        verrou.unlock()
        if let dernier { surMorceau?(dernier) }
    }

    func reprendre() { verrou.lock(); actif = true; verrou.unlock() }

    func terminer() { suspendre(); ecrivain?.fermer(); ecrivain = nil }

    /// À appeler verrou pris. Les bornes du découpeur sont en échantillons depuis le début de la tranche d'enregistrement.
    private func morceau(_ r: VoiceChunker.Range) -> MorceauReunion? {
        let debut = max(r.start, decalage), fin = min(r.end, decalage + echantillons.count)
        guard fin > debut, let b = base else { return nil }
        morceauxEmis += 1
        return MorceauReunion(locuteur: locuteur, debut: b + Double(r.start) / 16_000, echantillons: Array(echantillons[(debut - decalage)..<(fin - decalage)]))
    }

    /// Jette ce qui précède le morceau en cours : tant qu'aucune parole n'a été entendue, tout sauf les dernières 0,8 s ; après une
    /// coupe, tout ce qui précède la fin du morceau envoyé.
    private func elaguer() {
        guard !chunker.hasSpeechInChunk else { return }
        let garder = 40 * chunker.config.frameSamples
        let total = decalage + echantillons.count
        let nouveau = max(decalage, total - garder)
        if nouveau > decalage { echantillons.removeFirst(nouveau - decalage); decalage = nouveau }
    }

    // MARK: conversion

    /// Un tampon à un seul canal en flottants (la moyenne des canaux s'il y en a plusieurs) : AVAudioConverter ne mélange pas les canaux.
    static func enMono(_ source: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let f = source.format
        guard f.commonFormat == .pcmFormatFloat32, let donnees = source.floatChannelData else { return nil }
        if f.channelCount == 1, !f.isInterleaved { return source }
        let cible = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: f.sampleRate, channels: 1, interleaved: false)!
        guard let sortie = AVAudioPCMBuffer(pcmFormat: cible, frameCapacity: source.frameLength), let dest = sortie.floatChannelData else { return nil }
        let n = Int(source.frameLength), canaux = Int(f.channelCount), pas = source.stride
        for i in 0..<n {
            var somme: Float = 0
            for c in 0..<canaux { somme += donnees[c][i * pas] }
            dest[0][i] = somme / Float(canaux)
        }
        sortie.frameLength = source.frameLength
        return sortie
    }

    private func convertir(_ source: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let sortie = Self.formatSortie
        if convertisseur == nil || formatEntree != source.format {
            convertisseur = AVAudioConverter(from: source.format, to: sortie)
            formatEntree = source.format
        }
        guard let conv = convertisseur else { return nil }
        let ratio = sortie.sampleRate / source.format.sampleRate
        guard let tampon = AVAudioPCMBuffer(pcmFormat: sortie, frameCapacity: AVAudioFrameCount(Double(source.frameLength) * ratio + 64)) else { return nil }
        var fourni = false
        var erreur: NSError?
        let etat = conv.convert(to: tampon, error: &erreur) { _, statut in
            if fourni { statut.pointee = .noDataNow; return nil }
            fourni = true; statut.pointee = .haveData
            return source
        }
        return etat == .error ? nil : tampon
    }
}

/// Un fichier WAV (16 kHz mono 16 bits) écrit au fil de l'eau, droits 0600 ; l'en-tête est complété à la fermeture.
final class EcrivainWAV: @unchecked Sendable {
    private let url: URL
    private var handle: FileHandle?
    private var octets = 0

    init?(url: URL) {
        self.url = url
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard fm.createFile(atPath: url.path, contents: WAV.encode(samples: []), attributes: [.posixPermissions: 0o600]),
              let h = try? FileHandle(forWritingTo: url) else { return nil }
        _ = try? h.seekToEnd()
        handle = h
    }

    func ajouter(_ s: [Int16]) {
        guard let handle, !s.isEmpty else { return }
        let donnees = s.withUnsafeBufferPointer { Data(buffer: $0) }   // petit boutiste sur Apple Silicon et Intel
        try? handle.write(contentsOf: donnees)
        octets += donnees.count
    }

    func fermer() {
        guard let h = handle else { return }
        handle = nil
        func u32(_ v: Int) -> Data { var x = UInt32(v).littleEndian; return Data(bytes: &x, count: 4) }
        try? h.seek(toOffset: 4); try? h.write(contentsOf: u32(36 + octets))
        try? h.seek(toOffset: 40); try? h.write(contentsOf: u32(octets))
        try? h.close()
    }
}
