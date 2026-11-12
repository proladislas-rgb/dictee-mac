import Foundation
import DicteeCore

/// Après l'arrêt : tout l'enregistrement est relu d'un coup avec le modèle précis (whisper-large-v3, horodatages par phrase), à partir
/// des deux fichiers son gardés le temps de la note (`PisteReunion` les cale sur l'heure de la réunion). Seuls les passages de parole
/// vus pendant l'appel partent, en lots de deux minutes au plus (`RelectureReunion.lots`). Un lot que Groq refuse (réseau, limite trop
/// longue) garde les passages du direct : rien ne se perd. Le réseau passe par `transcrire`, que l'essai remplace (aucun réseau).
struct RelectureAudio: Sendable {
    /// Un lot : son 16 kHz mono → phrases horodatées dans ce son. Par défaut : Groq, avec les budgets partagés.
    var transcrire: @Sendable (LotRelecture, [Int16], Int) async throws -> [PhraseWhisper] = RelectureAudio.parGroq
    /// Attente de budget au-delà de laquelle un lot est abandonné (le direct le remplace).
    var attenteMax: Double = 300
    /// Lots envoyés en même temps : chaque requête attend surtout Groq (2 s pour 2 minutes de son), trois à la fois divisent
    /// l'attente par trois sans dépasser le budget (chaque lot réserve sa part d'audio avant de partir).
    var enParallele = 3

    struct Resultat: Sendable {
        /// Les passages, voix par voix (pas encore fusionnés).
        var segments: [SegmentReunion]
        var lots: Int
        var echoues: Int
        /// Tout l'appel a été relu (aucun lot en échec).
        var complete: Bool { lots > 0 && echoues == 0 }
        /// Au moins un lot relu.
        var relue: Bool { lots > 0 && echoues < lots }
    }

    /// `avance(fait, total)` après chaque lot. Lecture du son hors du fil principal.
    func relire(passages: [Locuteur: [PassageParole]], direct: [SegmentReunion], fichiers: [Locuteur: URL], duree: Double,
                avance: @escaping @Sendable (Int, Int) -> Void) async -> Resultat {
        var tous: [(LotRelecture, URL)] = []
        for l in [Locuteur.eux, .moi] {
            guard let url = fichiers[l], FileManager.default.fileExists(atPath: url.path) else { continue }
            let dureeFichier = LectureWAV.duree(url)
            let p = passages[l] ?? RelectureReunion.passagesInconnus(direct: direct, locuteur: l, dureeSon: dureeFichier)
            tous += RelectureReunion.lots(p, locuteur: l, duree: max(duree, dureeFichier)).map { ($0, url) }
        }
        // les lots dans l'ordre du temps : si la relecture s'arrête en route, le début de la réunion est relu
        tous.sort { $0.0.debut < $1.0.debut }
        let lots = tous.map(\.0)
        var relus: [SegmentReunion] = []
        var echoues = Set<Int>()
        avance(0, lots.count)
        // les lots partent dans l'ordre du temps, `enParallele` à la fois ; chacun lit son son au moment de partir (jamais toute la
        // réunion en mémoire)
        let transcrire = transcrire, total = lots.count
        await withTaskGroup(of: (Int, [SegmentReunion]?).self) { groupe in
            var prochain = 0, faits = 0
            func lancer() {
                guard prochain < tous.count else { return }
                let i = prochain, (lot, url) = tous[i]
                prochain += 1
                groupe.addTask {
                    if Task.isCancelled { return (i, nil) }
                    var son: [Int16] = []
                    for (j, p) in lot.passages.enumerated() {
                        if j > 0 { son += [Int16](repeating: 0, count: Int(LotRelecture.silence * 16_000)) }
                        son += LectureWAV.echantillons(url, de: p.debut, a: p.fin) ?? []
                    }
                    // un passage plus court que prévu dans le fichier (arrêt brutal) : le silence complète, les heures restent justes
                    do { return (i, RelectureReunion.segments(try await transcrire(lot, son, i + 1), lot: lot)) }
                    catch {
                        Log.ecrire("réunion : relecture du lot \(i + 1)/\(total) (\(lot.locuteur.libelle), \(Int(lot.duree)) s) impossible (\(error)) -> passages du direct gardés")
                        return (i, nil)
                    }
                }
            }
            for _ in 0..<max(1, enParallele) { lancer() }
            while let (i, r) = await groupe.next() {
                if let r { relus += r } else { echoues.insert(i) }
                faits += 1
                avance(faits, total)
                lancer()
            }
        }
        let parVoix = [Locuteur.moi, .eux].flatMap { l -> [SegmentReunion] in
            let rangs = lots.indices.filter { lots[$0].locuteur == l }
            return RelectureReunion.assembler(relus: relus.filter { $0.locuteur == l }, direct: direct.filter { $0.locuteur == l },
                                              lots: rangs.map { lots[$0] }, echoues: Set(rangs.indices.filter { echoues.contains(rangs[$0]) }))
        }
        Log.ecrire("réunion : relecture finie, \(lots.count - echoues.count)/\(lots.count) lot(s) relus, \(relus.count) phrase(s)")
        return Resultat(segments: parVoix, lots: lots.count, echoues: echoues.count)
    }

    /// Groq : whisper-large-v3 seulement, avec le budget d'audio et de requêtes du modèle précis (jamais le turbo : sa part est
    /// celle de la dictée), quelques essais en cas de réseau ou de limite, abandon au-delà de cinq minutes d'attente.
    static let parGroq: @Sendable (LotRelecture, [Int16], Int) async throws -> [PhraseWhisper] = { lot, son, numero in
        let prompt = PreparationLexique.promptPour(langue: Settings.langue, genre: .other, champ: { nil }, recents: [])(nil)
        var attendu = 0.0, essais = 0
        while true {
            try Task.checkCancellation()
            let requete = BudgetRequetes.precis.delaiAvantDePermettre(.anticipation)
            // l'audio est réservé d'un seul geste : les lots partis en parallèle ne dépassent jamais le plafond
            let attente = requete > 0 ? requete : BudgetAudio.precis.reserver(duree: lot.duree)
            if attente > 0 {
                if attendu + attente > 300 { throw GenerationNote.Erreur.abandon("budget de Whisper épuisé pour l\u{2019}instant") }
                Log.ecrire("réunion : relecture, attente de budget (\(Int(attente)) s)")
                let pas = min(attente, 20)
                try await Task.sleep(for: .seconds(pas)); attendu += pas
                continue
            }
            do {
                let t0 = ProcessInfo.processInfo.systemUptime
                let phrases = try await GroqClient.shared.transcrirePhrases(fichier: EncodeurAudio.encoder(son), prompt: prompt, langue: Settings.langue,
                                                                             etiquette: "relecture \(lot.locuteur.libelle) lot \(numero)")
                Log.ecrire("réunion : relecture lot \(numero) (\(lot.locuteur.libelle), \(Int(lot.duree)) s) -> \(phrases.count) phrase(s) en \(Int((ProcessInfo.processInfo.systemUptime - t0) * 1000)) ms")
                return phrases
            } catch let e as GroqErreur where essais < 3 && GroqClient.justifieLeSecours(e) {
                essais += 1
                try await Task.sleep(for: .seconds(Double([3, 8, 20][essais - 1])))
            }
        }
    }
}
