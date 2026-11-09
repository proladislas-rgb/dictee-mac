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
                NoteReunion.appliquer(note, a: &r, segments: fusion)
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
        var controle = true
        if r.etat == .prete { controle = verifierPresentation(r) }
        return (r.etat == .prete || sansNote) && controle ? 0 : 1
    }

    /// Contrôle automatique de la présentation « D'un coup d'œil » : « En bref » présent, chaque citation est une portion exacte
    /// d'un passage de la transcription (et le passage porte bien l'heure et le locuteur donnés), les échéances sont en vraies dates.
    private static func verifierPresentation(_ r: Reunion) -> Bool {
        var ok = true
        func controle(_ condition: Bool, _ nom: String) { print("  \(condition ? "ok   " : "ÉCHEC")  \(nom)"); if !condition { ok = false } }
        print("Contrôle de la présentation")
        controle(!(r.enBref ?? "").isEmpty, "« En bref » écrit : \(r.enBref ?? "(vide)")")
        for (i, p) in r.dit.enumerated() {
            if let c = r.citation(point: i) {
                let exacte = r.segments.contains { $0.texte.contains(c.texte) && $0.locuteur == c.locuteur && $0.debut == c.debut }
                controle(exacte, "point \(i + 1) « \(p) » : citation exacte (\(c.locuteur.libelle), \(FormatReunion.horloge(c.debut))) « \(c.texte) »")
            } else {
                print("  --    point \(i + 1) « \(p) » : pas de citation")
            }
        }
        controle(r.citations?.count ?? 0 > 0, "au moins une citation retrouvée")
        for a in r.actions {
            let e = Echeance.etiquette(quand: a.quand, date: a.echeance)
            print("  --    action « \(a.quoi) » (\(a.qui ?? "?")) quand « \(a.quand ?? "-") » -> \(a.echeance ?? "-") -> \(e.texte)")
            if a.echeance != nil { controle(Echeance.analyser(a.quand ?? "", depuis: r.debut).date == a.echeance, "échéance recalculée identique") }
        }
        for (i, d) in r.decisions.enumerated() {
            let e = r.echeance(decision: i)
            print("  --    décision « \(d) »\(e.map { " : « \($0.quand) » -> \($0.date ?? "-")" } ?? "")")
        }
        return ok
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
