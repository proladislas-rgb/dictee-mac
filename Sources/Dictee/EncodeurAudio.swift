import AVFoundation
import DicteeCore

/// Codage du son envoyé à Groq. FLAC (sans perte, environ 40 % plus léger que le WAV) avec l'encodeur d'Apple ;
/// WAV si le codage échoue ou si le réglage `formatEnvoi` vaut `wav`.
enum EncodeurAudio {
    struct Fichier { var donnees: Data; var nom: String; var type: String }

    static func encoder(_ echantillons: [Int16], flac: Bool = Settings.envoiFLAC) -> Fichier {
        if flac, let d = flacEnMemoire(echantillons) { return Fichier(donnees: d, nom: "audio.flac", type: "audio/flac") }
        return Fichier(donnees: WAV.encode(samples: echantillons), nom: "audio.wav", type: "audio/wav")
    }

    /// AVAudioFile n'écrit que dans un fichier : un fichier temporaire, relu puis effacé aussitôt (quelques millisecondes).
    static func flacEnMemoire(_ echantillons: [Int16]) -> Data? {
        guard !echantillons.isEmpty else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dictee-\(UUID().uuidString).flac")
        defer { try? FileManager.default.removeItem(at: url) }
        let reglages: [String: Any] = [
            AVFormatIDKey: kAudioFormatFLAC,
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
        ]
        do {
            let fichier = try AVAudioFile(forWriting: url, settings: reglages, commonFormat: .pcmFormatInt16, interleaved: true)
            guard let tampon = AVAudioPCMBuffer(pcmFormat: fichier.processingFormat, frameCapacity: AVAudioFrameCount(echantillons.count)),
                  let canal = tampon.int16ChannelData else { return nil }
            echantillons.withUnsafeBufferPointer { canal[0].update(from: $0.baseAddress!, count: echantillons.count) }
            tampon.frameLength = AVAudioFrameCount(echantillons.count)
            try fichier.write(from: tampon)
        } catch { return nil }   // le fichier doit être fermé (libéré) avant la relecture : la portée du `do` s'en charge
        guard let donnees = try? Data(contentsOf: url), donnees.count > 8, donnees.prefix(4) == Data("fLaC".utf8) else { return nil }
        return donnees
    }
}
