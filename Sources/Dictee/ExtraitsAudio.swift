import Accelerate
import AVFoundation
import DicteeCore
import Foundation

/// Ce dont la bulle audio a besoin d'un lecteur : AVAudioPlayer en vrai, un lecteur factice (muet) dans l'essai.
protocol LecteurSon: AnyObject {
    var currentTime: TimeInterval { get set }
    var rate: Float { get set }
    var isPlaying: Bool { get }
    func play() -> Bool
    func pause()
    func stop()
}

extension AVAudioPlayer: LecteurSon {
    /// Un lecteur de fichier son, vitesse réglable (×1,5, ×2 : la voix garde sa hauteur).
    static func pourBulle(_ url: URL) -> LecteurSon? {
        guard let p = try? AVAudioPlayer(contentsOf: url) else { return nil }
        p.enableRate = true
        p.prepareToPlay()
        return p
    }
}

/// Les fichiers .m4a (AAC) des extraits et de toute la réunion. Tout se fait sur ce Mac, rien n'est envoyé ; chaque fichier écrit
/// est en 0600, d'abord sous un nom caché puis renommé (jamais de fichier à moitié écrit sous son vrai nom).
enum ExportAudio {
    enum Erreur: Error, CustomStringConvertible {
        case sonIllisible
        var description: String { "son de la réunion illisible" }
    }

    /// AAC mono 16 kHz (le son des pistes) à 32 kbit/s : environ 240 Ko par minute, la voix reste nette.
    static let reglages: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 16_000.0,
                                          AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 32_000]

    /// Écrit un .m4a à partir de blocs de son 16 kHz mono (`bloc(n)` rend le n-ième bloc, nil à la fin).
    static func ecrire(vers url: URL, blocs bloc: (Int) throws -> [Int16]?) throws {
        let fm = FileManager.default
        let cache = url.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).m4a")
        defer { try? fm.removeItem(at: cache) }
        do {
            let f = try AVAudioFile(forWriting: cache, settings: reglages, commonFormat: .pcmFormatFloat32, interleaved: false)
            var n = 0
            while let s = try bloc(n), !s.isEmpty {
                guard let b = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(s.count)), let d = b.floatChannelData else { throw Erreur.sonIllisible }
                s.withUnsafeBufferPointer { vDSP_vflt16($0.baseAddress!, 1, d[0], 1, vDSP_Length(s.count)) }
                var echelle: Float = 1 / 32_768
                vDSP_vsmul(d[0], 1, &echelle, d[0], 1, vDSP_Length(s.count))
                b.frameLength = AVAudioFrameCount(s.count)
                try f.write(from: b)
                n += 1
            }
            f.close()
        }
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cache.path)
        if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
        try fm.moveItem(at: cache, to: url)
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// L'extrait d'un passage, lu dans le fichier de sa piste.
    static func extrait(_ e: ExtraitReunion, fichier: URL, vers url: URL) throws {
        guard let s = LectureWAV.echantillons(fichier, de: e.debut, a: e.fin), !s.isEmpty else { throw Erreur.sonIllisible }
        try ecrire(vers: url) { $0 == 0 ? s : nil }
    }

    /// Toute la réunion : les deux pistes mélangées, lues et encodées par blocs de 20 s (une réunion de deux heures ne passe jamais
    /// entière en mémoire). `avance` : 0 à 1.
    static func reunion(moi: URL?, eux: URL?, vers url: URL, avance: (Double) -> Void = { _ in }) throws {
        let fm = FileManager.default
        let pistes = [moi, eux].compactMap { $0 }.filter { fm.fileExists(atPath: $0.path) }
        guard !pistes.isEmpty else { throw Erreur.sonIllisible }
        let duree = pistes.map(LectureWAV.duree).max() ?? 0
        let pas = 20.0
        try ecrire(vers: url) { n in
            let a = Double(n) * pas
            guard a < duree else { return nil }
            avance(a / max(1, duree))
            let morceaux = pistes.map { LectureWAV.echantillons($0, de: a, a: min(duree, a + pas)) ?? [] }
            return morceaux.dropFirst().reduce(morceaux[0]) { ExtraitsReunion.mixer($0, $1) }
        }
        avance(1)
    }
}

extension ReunionStore {
    /// Les extraits fabriqués pour un glisser-déposer (une copie du son, le temps que l'autre app la prenne) : un dossier caché à côté
    /// des réunions (0700), effacé avec le son de la réunion, avec la réunion, et entièrement à chaque lancement.
    var dossierExtraits: URL { dossier.appendingPathComponent(".extraits", isDirectory: true) }
    func dossierExtraits(_ r: Reunion) -> URL { dossierExtraits.appendingPathComponent(ArchiveReunions.nomDeBase(r), isDirectory: true) }

    /// Le fichier .m4a d'un passage, prêt à glisser vers une autre app (fabriqué une fois).
    func fichierExtrait(_ r: Reunion, passage i: Int) throws -> URL {
        guard r.segments.indices.contains(i) else { throw ExportAudio.Erreur.sonIllisible }
        let son = fichierSon(r, r.segments[i].locuteur)
        guard let e = ExtraitsReunion.extrait(r, passage: i, dureeSon: LectureWAV.duree(son)) else { throw ExportAudio.Erreur.sonIllisible }
        let d = dossierExtraits(r)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dossierExtraits.path)
        // le nom suit l'orateur (renommé entre-temps : un autre fichier) et le passage
        let url = d.appendingPathComponent("\(i)", isDirectory: true).appendingPathComponent(ExtraitsReunion.nomFichier(r, passage: i))
        if FileManager.default.fileExists(atPath: url.path) { return url }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try ExportAudio.extrait(e, fichier: son, vers: url)
        return url
    }

    func effacerExtraits(_ r: Reunion) { try? FileManager.default.removeItem(at: dossierExtraits(r)) }
    func effacerTousLesExtraits() { try? FileManager.default.removeItem(at: dossierExtraits) }
}
