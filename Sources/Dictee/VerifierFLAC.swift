import AVFoundation
import DicteeCore

/// `Dictee --verifier-flac` : le FLAC d'Apple est sans perte (relu = identique), et combien il gagne en taille et coûte en temps.
/// Aucun micro, aucun réseau.
enum VerifierFLAC {
    static func executer() -> Int32 {
        var echec = false
        for secondes in [2, 6, 20] {
            // Un signal proche de la voix : plusieurs sinusoïdes, enveloppe lente, un peu de bruit.
            var g: UInt64 = 12345
            func bruit() -> Double { g = g &* 6364136223846793005 &+ 1442695040888963407; return Double(g >> 33) / Double(1 << 31) - 0.5 }
            let n = secondes * 16_000
            let echantillons: [Int16] = (0..<n).map { i in
                let t = Double(i) / 16_000
                let env = 0.5 + 0.5 * sin(2 * .pi * 3 * t)
                let v = env * (0.3 * sin(2 * .pi * 180 * t) + 0.15 * sin(2 * .pi * 540 * t) + 0.08 * sin(2 * .pi * 1700 * t)) + 0.01 * bruit()
                return Int16(max(-1, min(1, v)) * 32767)
            }
            let t0 = ProcessInfo.processInfo.systemUptime
            guard let flac = EncodeurAudio.flacEnMemoire(echantillons) else { print("FLAC \(secondes) s : encodage impossible"); echec = true; continue }
            let ms = (ProcessInfo.processInfo.systemUptime - t0) * 1000
            let wav = WAV.encode(samples: echantillons)
            // relecture
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("verif-\(UUID().uuidString).flac")
            defer { try? FileManager.default.removeItem(at: url) }
            try? flac.write(to: url)
            var identique = false
            if let f = try? AVAudioFile(forReading: url, commonFormat: .pcmFormatInt16, interleaved: true),
               let tampon = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length)), (try? f.read(into: tampon)) != nil,
               let canal = tampon.int16ChannelData, Int(tampon.frameLength) == echantillons.count {
                identique = (0..<echantillons.count).allSatisfy { canal[0][$0] == echantillons[$0] }
            }
            print(String(format: "FLAC %d s : %d Ko contre %d Ko en WAV (%.0f %%), encodé en %.1f ms, relu identique : %@", secondes, flac.count / 1024, wav.count / 1024,
                         Double(flac.count) / Double(wav.count) * 100, ms, identique ? "oui" : "NON"))
            if !identique { echec = true }
        }
        return echec ? 1 : 0
    }
}
