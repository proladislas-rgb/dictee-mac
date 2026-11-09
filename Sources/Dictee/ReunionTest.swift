import AVFoundation
import DicteeCore

/// `Verbe --reunion-test moi.wav eux.wav [--sortie DOSSIER] [--sans-note]` : fait passer deux fichiers son (les deux pistes d'une
/// réunion) par exactement la chaîne d'une vraie réunion — découpe aux pauses, transcription Whisper au fil de l'eau avec les
/// budgets partagés, fusion Moi / Eux, note — puis écrit la note en JSON et en Markdown dans DOSSIER (par défaut `.build/reunion-test`).
/// Réseau seulement : ni micro, ni son du Mac, ni accessibilité, ni calendrier. N'écrit jamais dans les réunions de l'app.
enum ReunionTest {
    static func executer(moi: String, eux: String, arguments: [String]) -> Int32 {
        guard GroqClient.shared.cleDisponible else {
            FileHandle.standardError.write(Data("Clé Groq introuvable (~/.config/groq/.env)\n".utf8)); return 2
        }
        var dossier = ".build/reunion-test"
        if let i = arguments.firstIndex(of: "--sortie"), i + 1 < arguments.count { dossier = arguments[i + 1] }
        let sansNote = arguments.contains("--sans-note")
        let url = URL(fileURLWithPath: (dossier as NSString).expandingTildeInPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        var sortie: Int32 = 0
        let fini = DispatchSemaphore(value: 0)
        Task.detached {
            sortie = await lancer(moi: moi, eux: eux, dossier: url, sansNote: sansNote)
            fini.signal()
        }
        fini.wait()
        Log.vider()
        return sortie
    }

    private static func lancer(moi: String, eux: String, dossier: URL, sansNote: Bool) async -> Int32 {
        let t0 = ProcessInfo.processInfo.systemUptime
        let transcripteur = TranscriptionReunion(correcteur: nil)   // la correction à l'oreille passe par le fil principal, bloqué ici par l'attente
        let segments = Verrouille<[SegmentReunion]>([])
        transcripteur.surSegment = { s in _ = segments.remplacer(segments.valeur + [s]) }
        var duree = 0.0
        let avant = GroqClient.shared.requetesEnvoyees
        for (locuteur, chemin) in [(Locuteur.moi, moi), (Locuteur.eux, eux)] {
            guard let d = alimenter(piste: locuteur, chemin: chemin, transcripteur: transcripteur) else {
                FileHandle.standardError.write(Data("Fichier son illisible : \(chemin)\n".utf8)); return 2
            }
            duree = max(duree, d)
        }
        print(String(format: "%.0f s de son par piste, transcription en cours (%d morceaux en attente)…", duree, transcripteur.restants))
        await transcripteur.attendreLaFin()
        let requetes = GroqClient.shared.requetesEnvoyees - avant
        let t1 = ProcessInfo.processInfo.systemUptime
        print(String(format: "transcription finie en %.0f s : %d morceaux reçus, %d échec(s), %d requête(s) Whisper", t1 - t0, transcripteur.recus, transcripteur.echecs, requetes))

        let brut = segments.valeur
        let (fusion, echos) = FusionPistes.transcription(moi: brut.filter { $0.locuteur == .moi }, eux: brut.filter { $0.locuteur == .eux })
        print("fusion : \(brut.count) passages -> \(fusion.count) après regroupement, \(echos) écho(s) retiré(s) de la piste Moi")

        var r = Reunion(debut: Date(), duree: duree, segments: fusion, etat: .sansNote)
        if transcripteur.echecs > 0 { r.avertissements.append("\(transcripteur.echecs) passage(s) n'ont pas pu être transcrits.") }
        if !sansNote, !fusion.isEmpty {
            do {
                let (note, retraits) = try await GenerationNote().rediger(segments: fusion, duree: duree, debut: r.debut) { print("  \($0)") }
                r.titre = note.titre; r.dit = note.dit; r.decisions = note.decisions; r.actions = note.actions
                r.participants = ["Moi"] + note.participants
                r.etat = .prete
                for x in retraits { print("  garde anti-invention : retiré \(x)") }
                print(String(format: "note écrite en %.0f s", ProcessInfo.processInfo.systemUptime - t1))
            } catch {
                print("Note impossible : \(error)")
            }
        }
        let base = ArchiveReunions.nomDeBase(r)
        let json = dossier.appendingPathComponent("\(base).json"), md = dossier.appendingPathComponent("\(base).md")
        try? ArchiveReunions.encoder(r)?.write(to: json)
        try? ReunionMarkdown.rendre(r).write(to: md, atomically: true, encoding: .utf8)
        print("écrit \(json.path)\nécrit \(md.path)\n")
        print(ReunionMarkdown.rendre(r))
        return r.etat == .prete || sansNote ? 0 : 1
    }

    /// Lit le fichier comme un micro (tampons de 100 ms) et le donne à une piste ; les morceaux coupés partent chez Whisper.
    /// L'horloge est celle du fichier : l'heure d'un morceau est sa position dans le son, comme dans une vraie réunion.
    private static func alimenter(piste locuteur: Locuteur, chemin: String, transcripteur: TranscriptionReunion) -> Double? {
        guard let fichier = try? AVAudioFile(forReading: URL(fileURLWithPath: (chemin as NSString).expandingTildeInPath)) else { return nil }
        let piste = PisteReunion(locuteur: locuteur)
        var lus = 0.0
        piste.horloge = { lus }
        piste.surMorceau = { transcripteur.soumettre($0) }
        let format = fichier.processingFormat
        let taille = AVAudioFrameCount(format.sampleRate * 0.1)
        while fichier.framePosition < fichier.length {
            guard let tampon = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: taille) else { break }
            do { try fichier.read(into: tampon, frameCount: taille) } catch { break }
            if tampon.frameLength == 0 { break }
            lus += Double(tampon.frameLength) / format.sampleRate
            piste.traiter(tampon)
        }
        piste.terminer()
        return lus
    }
}
