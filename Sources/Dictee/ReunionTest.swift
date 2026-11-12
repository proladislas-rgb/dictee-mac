import AVFoundation
import DicteeCore

/// `Verbe --reunion-test moi.wav eux.wav [--sortie DOSSIER] [--sans-note] [--modeles DOSSIER]` : fait passer deux fichiers son (les deux pistes d'une
/// réunion) par exactement la chaîne d'une vraie réunion — découpe aux pauses, transcription Whisper au fil de l'eau avec les
/// budgets partagés, son écrit calé sur l'heure de la réunion, puis après « l'arrêt » : relecture de tout l'enregistrement par
/// whisper-large-v3, voix des autres séparées sur le Mac (modèle dans le dossier de `--modeles`, celui de Verbe sinon), fusion,
/// note par sujets — et écrit la note en JSON et en Markdown dans DOSSIER (par défaut `.build/reunion-test`).
/// Réseau seulement : ni micro, ni son du Mac, ni accessibilité, ni calendrier. N'écrit jamais dans les réunions de l'app.
enum ReunionTest {
    static func executer(moi: String, eux: String, arguments: [String]) -> Int32 {
        guard GroqClient.shared.cleDisponible else {
            FileHandle.standardError.write(Data("Clé Groq introuvable (~/.config/groq/.env)\n".utf8)); return 2
        }
        var dossier = ".build/reunion-test"
        if let i = arguments.firstIndex(of: "--sortie"), i + 1 < arguments.count { dossier = arguments[i + 1] }
        let sansNote = arguments.contains("--sans-note")
        let modeles = arguments.firstIndex(of: "--modeles").flatMap { $0 + 1 < arguments.count ? URL(fileURLWithPath: (arguments[$0 + 1] as NSString).expandingTildeInPath, isDirectory: true) : nil }
            ?? SeparationVoixLocale.dossierParDefaut
        let url = URL(fileURLWithPath: (dossier as NSString).expandingTildeInPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        var sortie: Int32 = 0
        let fini = DispatchSemaphore(value: 0)
        Task.detached {
            sortie = await lancer(moi: moi, eux: eux, dossier: url, sansNote: sansNote, modeles: modeles)
            fini.signal()
        }
        fini.wait()
        Log.vider()
        return sortie
    }

    private static func lancer(moi: String, eux: String, dossier: URL, sansNote: Bool, modeles: URL) async -> Int32 {
        let t0 = ProcessInfo.processInfo.systemUptime
        let transcripteur = TranscriptionReunion(correcteur: nil)   // la correction à l'oreille passe par le fil principal, bloqué ici par l'attente
        let segments = Verrouille<[SegmentReunion]>([])
        let passages = Verrouille<[Locuteur: [PassageParole]]>([:])
        transcripteur.surSegment = { s in _ = segments.remplacer(segments.valeur + [s]) }
        var duree = 0.0
        let avant = GroqClient.shared.requetesEnvoyees
        let r0 = Reunion(debut: Date(), etat: .transcription)
        let fichiers = [Locuteur.moi: dossier.appendingPathComponent("son-moi.wav"), .eux: dossier.appendingPathComponent("son-eux.wav")]
        for (locuteur, chemin) in [(Locuteur.moi, moi), (Locuteur.eux, eux)] {
            guard let d = alimenter(piste: locuteur, chemin: chemin, transcripteur: transcripteur, fichier: fichiers[locuteur], passages: passages) else {
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
        var depart = r0; depart.duree = duree
        var r: Reunion
        if sansNote {
            r = depart; r.etat = .sansNote
            r.segments = FusionPistes.transcription(moi: brut.filter { $0.locuteur == .moi }, eux: brut.filter { $0.locuteur == .eux }).segments
        } else {
            // après « l'arrêt » : la même chaîne que l'app (relecture de tout l'enregistrement, puis note)
            let rediger: ReunionController.RedigerNote = { segments, duree, debut, avance in
                try await GenerationNote().rediger(segments: segments, duree: duree, debut: debut, surEtape: { print("  \($0)") }, avance: avance)
            }
            let separation = SeparationVoixAudio { url, avance in try await SeparationVoixLocale.separer(url, modeles: modeles, avance: avance).voix }
            guard let prepare = await ReunionController.preparer(depart, passages: passages.valeur, direct: brut, fichiers: fichiers, relecture: RelectureAudio(),
                                                                 rediger: rediger, separation: separation,
                                                                 avance: { p, etape in print("  \(PreparationNote.pourcent(p)) \(etape)") }) else {
                print("Rien entendu."); return 1
            }
            r = prepare
            print(String(format: "relecture et note en %.0f s (relue : %@)", ProcessInfo.processInfo.systemUptime - t1, r.relue == true ? "oui" : "non"))
        }
        if transcripteur.echecs > 0, r.relue != true { r.avertissements.append("\(transcripteur.echecs) passage(s) n'ont pas pu être transcrits.") }
        for f in fichiers.values { try? FileManager.default.removeItem(at: f) }
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
        controle(!(r.enBref ?? "").isEmpty, "phrase d'ouverture écrite : \(r.enBref ?? "(vide)")")
        controle(!(r.sujets ?? []).isEmpty, "résumé par sujets : \((r.sujets ?? []).map(\.titre).joined(separator: " · "))")
        controle(r.relue == true, "transcription relue par le modèle précis")
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
    private static func alimenter(piste locuteur: Locuteur, chemin: String, transcripteur: TranscriptionReunion, fichier son: URL?, passages: Verrouille<[Locuteur: [PassageParole]]>) -> Double? {
        guard let fichier = try? AVAudioFile(forReading: URL(fileURLWithPath: (chemin as NSString).expandingTildeInPath)) else { return nil }
        let piste = PisteReunion(locuteur: locuteur, fichierSon: son)
        var lus = 0.0
        piste.horloge = { lus }
        piste.surMorceau = { m in
            var p = passages.valeur; p[m.locuteur, default: []].append(PassageParole(debut: m.debut, fin: m.debut + m.duree)); _ = passages.remplacer(p)
            transcripteur.soumettre(m)
        }
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
