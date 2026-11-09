import AVFoundation
import DicteeCore

/// Mode de vérification sans micro : `Dictee --transcrire fichier.wav`
/// Fait passer le fichier par exactement la même chaîne qu'une vraie dictée (conversion 16 kHz, découpe aux pauses,
/// envoi parallèle à Groq, recollage), puis affiche le texte et la durée.
enum Transcrire {
    static func executer(chemin: String) -> Int32 {
        let url = URL(fileURLWithPath: (chemin as NSString).expandingTildeInPath)
        guard let fichier = try? AVAudioFile(forReading: url) else {
            FileHandle.standardError.write(Data("Fichier son illisible : \(chemin)\n".utf8)); return 2
        }
        guard GroqClient.shared.cleDisponible else {
            FileHandle.standardError.write(Data("Clé Groq introuvable (~/.config/groq/.env)\n".utf8)); return 2
        }
        let transcripteur = ChunkTranscriber(mots: Dictionnaire.mots(), langue: Settings.langue)
        let pipeline = RecordingPipeline()
        pipeline.surMorceau = { wav, duree in transcripteur.envoyer(wav: wav, duree: duree) }

        let debut = ProcessInfo.processInfo.systemUptime
        GroqClient.shared.prechauffer()
        let format = fichier.processingFormat
        let taille: AVAudioFrameCount = 4096
        while fichier.framePosition < fichier.length {
            guard let tampon = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: taille) else { break }
            do { try fichier.read(into: tampon, frameCount: taille) } catch { break }
            if tampon.frameLength == 0 { break }
            pipeline.traiter(tampon)
        }
        if let dernier = pipeline.terminer() { transcripteur.envoyer(wav: dernier.wav, duree: dernier.duree) }
        let dureeSon = Double(fichier.length) / format.sampleRate

        var sortie: Int32 = 0
        let fini = DispatchSemaphore(value: 0)
        Task {
            let r = await transcripteur.resultat(delai: 15)
            let ecoule = ProcessInfo.processInfo.systemUptime - debut
            switch r {
            case .texte(let t):
                print(t)
                print(String(format: "— %.2f s de son, %d morceau(x), texte obtenu en %.2f s", dureeSon, transcripteur.nombreDeMorceaux, ecoule))
            case .echec(let e): print("Échec : \(e)"); sortie = 1
            case .delai: print("Trop lent (> 15 s)"); sortie = 1
            }
            fini.signal()
        }
        fini.wait()
        Log.vider()
        return sortie
    }
}
