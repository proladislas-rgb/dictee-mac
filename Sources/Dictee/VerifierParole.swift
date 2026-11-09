import AVFoundation

/// Fait lire un fichier son à la reconnaissance en direct d'Apple, comme le ferait le micro, et écrit le résultat
/// dans le journal. À lancer avec `open` (jamais depuis un shell) : `--sans-interface --verifier-parole=fichier.wav`.
enum VerifierParole {
    static func executer(chemin: String) async {
        let debut = ProcessInfo.processInfo.systemUptime
        await PrechauffageParole.lancer()
        Log.ecrire("vérif parole : préparation en \(Int((ProcessInfo.processInfo.systemUptime - debut) * 1000)) ms")
        guard let direct = PrechauffageParole.creer() else {
            Log.ecrire("vérif parole : aucune reconnaissance disponible (\(PrechauffageParole.etat))"); return
        }
        guard let fichier = try? AVAudioFile(forReading: URL(fileURLWithPath: chemin)) else {
            Log.ecrire("vérif parole : fichier illisible"); return
        }
        nonisolated(unsafe) var progressifs = 0
        direct.surTexte = { _ in progressifs += 1 }
        let format = fichier.processingFormat
        let t0 = ProcessInfo.processInfo.systemUptime
        while fichier.framePosition < fichier.length {
            guard let tampon = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096) else { break }
            do { try fichier.read(into: tampon, frameCount: 4096) } catch { break }
            if tampon.frameLength == 0 { break }
            direct.alimenter(tampon)
        }
        let texte = await direct.terminer()
        let ms = Int((ProcessInfo.processInfo.systemUptime - t0) * 1000)
        Log.ecrire("vérif parole : \(progressifs) mises à jour en direct, texte final en \(ms) ms après la dernière donnée : \"\(Log.apercu(texte))\" (\(texte.count) caractères)")
    }
}
