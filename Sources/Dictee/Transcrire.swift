import AVFoundation
import DicteeCore

/// Mode de vérification sans micro : `Dictee --transcrire fichier.wav [--temps-reel] [--repetitions N]`
/// Fait passer le fichier par exactement la même chaîne qu'une vraie dictée (conversion 16 kHz, découpe aux pauses,
/// envoi parallèle à Groq, recollage), puis affiche le texte et la durée.
///
/// `--temps-reel` : le son est livré à la vitesse d'un vrai micro (tampons de 40 ms) et le « relâchement de fn » a lieu
/// à la fin du fichier ; on mesure alors le délai du relâchement au texte, comme dans une vraie dictée.
/// `--repetitions N` : recommence N fois (en respectant la limite gratuite de Groq) et donne médiane, minimum et maximum.
enum Transcrire {
    static func executer(chemin: String, arguments: [String] = []) -> Int32 {
        let url = URL(fileURLWithPath: (chemin as NSString).expandingTildeInPath)
        guard let fichier = try? AVAudioFile(forReading: url) else {
            FileHandle.standardError.write(Data("Fichier son illisible : \(chemin)\n".utf8)); return 2
        }
        guard GroqClient.shared.cleDisponible else {
            FileHandle.standardError.write(Data("Clé Groq introuvable (~/.config/groq/.env)\n".utf8)); return 2
        }
        let tempsReel = arguments.contains("--temps-reel")
        let avecNettoyage = arguments.contains("--nettoyer-aussi")
        var bundle: String?
        if let i = arguments.firstIndex(of: "--app"), i + 1 < arguments.count { bundle = arguments[i + 1] }
        var repetitions = 1
        if let i = arguments.firstIndex(of: "--repetitions"), i + 1 < arguments.count, let n = Int(arguments[i + 1]), n > 0 { repetitions = n }
        let format = fichier.processingFormat
        let dureeSon = Double(fichier.length) / format.sampleRate

        var sortie: Int32 = 0
        let fini = DispatchSemaphore(value: 0)
        Task.detached {
            var delais: [Double] = []
            var requetes: [Int] = []
            var premierTexte = ""
            for essai in 1...repetitions {
                if repetitions > 1 { await attendreLeBudget(nettoyage: avecNettoyage) }
                let avant = GroqClient.shared.requetesEnvoyees
                guard let r = await unEssai(url: url, tempsReel: tempsReel, nettoyage: avecNettoyage, bundle: bundle) else { sortie = 1; break }
                let nReq = GroqClient.shared.requetesEnvoyees - avant
                if essai == 1 || repetitions == 1 { print(r.texte); premierTexte = r.texte }
                else if r.texte != premierTexte { print("  TEXTE DIFFÉRENT : \(r.texte)") }
                print(String(format: "%@— %.2f s de son, %d morceau(x), %d requête(s)%@, %@ %.0f ms", repetitions > 1 ? "essai \(essai) " : "", dureeSon, r.morceaux, nReq, r.details,
                             tempsReel ? "du relâchement au texte :" : "texte obtenu en", (tempsReel ? r.apresRelachement : r.total) * (tempsReel ? 1000 : 1)))
                delais.append(r.apresRelachement * 1000)
                requetes.append(nReq)
            }
            if repetitions > 1, !delais.isEmpty {
                let tri = delais.sorted()
                let med = tri.count % 2 == 1 ? tri[tri.count / 2] : (tri[tri.count / 2 - 1] + tri[tri.count / 2]) / 2
                print(String(format: "RÉSUMÉ %@ : médiane %.0f ms, min %.0f ms, max %.0f ms, %.1f requête(s) par essai (%d essais)",
                             url.lastPathComponent, med, tri.first!, tri.last!, Double(requetes.reduce(0, +)) / Double(requetes.count), delais.count))
            }
            fini.signal()
        }
        fini.wait()
        Log.vider()
        return sortie
    }

    struct Essai { var texte: String; var morceaux: Int; var apresRelachement: Double; var total: Double; var details = "" }

    /// Attend que la dernière minute ait laissé de la place (limite gratuite : environ 20 requêtes par minute).
    private static func attendreLeBudget(nettoyage: Bool) async {
        while BudgetRequetes.whisper(Settings.modeleWhisper).restantMinute() < 10 || (nettoyage && BudgetRequetes.nettoyage.restantMinute() < 8) {
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    /// `lexique` : comme l'app (mots choisis dans le lexique et les expressions pour Whisper, correction à l'oreille) ; le comparateur de précision s'en sert.
    static func unEssai(url: URL, tempsReel: Bool, nettoyage: Bool, bundle: String?, lexique: Bool = false) async -> Essai? {
        guard let fichier = try? AVAudioFile(forReading: url) else { return nil }
        let transcripteur = lexique
            ? ChunkTranscriber(mots: Dictionnaire.mots(), langue: Settings.langue,
                               promptPour: PreparationLexique.promptPour(langue: Settings.langue, genre: TextFormatter.kind(bundleID: bundle), champ: { nil }, recents: []),
                               correcteur: PreparationLexique.correcteur())
            : ChunkTranscriber(mots: Dictionnaire.mots(), langue: Settings.langue)
        let pipeline = RecordingPipeline()
        pipeline.surMorceau = { transcripteur.envoyer($0) }
        if transcripteur.anticipationActive { pipeline.surAnticipation = { transcripteur.anticiper($0) } }
        // Remise au propre comme dans l'app : par unités pendant la dictée, ou d'un coup à la pause d'avant le relâchement.
        let mots = Dictionnaire.mots()
        let contexte = RemiseAuPropre.contexte(bundleID: bundle, role: nil, titreFenetre: nil)
        let unites = NettoyageParUnites(mots: mots) { contexte }
        let anticipe = Verrouille<NettoyageFinal.Anticipe?>(nil)
        if nettoyage {
            transcripteur.surMorceauRevenu = { unites.morceauRevenu(numero: $0, texte: $1, finParPause: $2) }
            transcripteur.surTexteAnticipe = { parties in
                if unites.nombreDUnites > 0 { unites.anticiperQueue(parties: parties); return }
                if let a = NettoyageFinal.lancerALAvance(TextAssembler.joindre(parties), contexte: contexte, mots: mots) { anticipe.remplacer(a)?.tache.cancel() }
            }
        }

        let debut = ProcessInfo.processInfo.systemUptime
        GroqClient.shared.prechauffer()
        let format = fichier.processingFormat
        let taille = AVAudioFrameCount(tempsReel ? format.sampleRate * 0.04 : 4096)
        var lus: Double = 0
        while fichier.framePosition < fichier.length {
            guard let tampon = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: taille) else { break }
            do { try fichier.read(into: tampon, frameCount: taille) } catch { break }
            if tampon.frameLength == 0 { break }
            lus += Double(tampon.frameLength) / format.sampleRate
            if tempsReel {   // le tampon n'est « livré » qu'une fois l'heure de sa fin venue, comme avec un micro
                let attente = debut + lus - ProcessInfo.processInfo.systemUptime
                if attente > 0 { try? await Task.sleep(for: .seconds(attente)) }
            }
            pipeline.traiter(tampon)
        }
        let relachement = ProcessInfo.processInfo.systemUptime
        if let dernier = pipeline.terminer() { transcripteur.envoyer(dernier) }
        let r = await transcripteur.resultat(delai: 15)
        var maintenant = ProcessInfo.processInfo.systemUptime
        var detailNettoyage = ""
        var texteFinal: String?
        if nettoyage, case .texte(let t) = r {
            let tG = maintenant
            let (n, mode) = await NettoyageFinal.executer(brut: t, contexte: contexte, transcripteur: transcripteur, unites: unites, anticipe: anticipe.valeur, mots: mots)
            maintenant = ProcessInfo.processInfo.systemUptime
            texteFinal = n.texte
            detailNettoyage = String(format: " [Groq %.0f ms, remise au propre %@ : %.0f ms, %@]", (tG - relachement) * 1000, mode, (maintenant - tG) * 1000, n.utilise ? "faite" : n.raison)
        }
        switch r {
        case .texte(let t0):
            let t = texteFinal ?? t0
            var e = Essai(texte: t, morceaux: transcripteur.nombreDeMorceaux, apresRelachement: maintenant - relachement, total: maintenant - debut)
            e.details = detailNettoyage + String(format: " [parole mesurée %.1f s sur %.1f s enregistrées]", pipeline.dureeParole, pipeline.dureeEnregistree) + " [anticipés réutilisés \(transcripteur.anticipesReutilises), jetés \(transcripteur.anticipesJetes), secours \(transcripteur.secoursLances)]"
            return e
        case .echec(let e): print("Échec : \(e)"); return nil
        case .delai: print("Trop lent (> 15 s)"); return nil
        }
    }
}

/// Une valeur partagée entre fils (le banc d'essai range ici la remise au propre lancée à l'avance).
final class Verrouille<T>: @unchecked Sendable {
    private let verrou = NSLock()
    private var contenu: T
    init(_ v: T) { contenu = v }
    var valeur: T { verrou.lock(); defer { verrou.unlock() }; return contenu }
    /// Remplace la valeur et rend l'ancienne.
    func remplacer(_ v: T) -> T { verrou.lock(); defer { verrou.unlock() }; let ancien = contenu; contenu = v; return ancien }
}
