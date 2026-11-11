import Foundation
import DicteeCore

/// Écrit la note d'une réunion avec Groq : une transcription courte en un seul appel, une longue par parties (chacune résumée),
/// puis une note finale qui assemble les parties. Les appels sont espacés sous le plafond de jetons par minute du modèle
/// (`BudgetJetons`). La réponse est lue en JSON puis passée à la garde anti-invention : la note ne garde que ce que la transcription soutient.
struct GenerationNote {
    enum Erreur: Error, CustomStringConvertible {
        case reponseIllisible
        case abandon(String)
        var description: String {
            switch self { case .reponseIllisible: return "réponse illisible du modèle"; case .abandon(let m): return m }
        }
    }

    static let budget = BudgetJetons(limiteMinute: 8000)
    var modele = Settings.modeleNoteReunion
    var groq = GroqClient.shared
    /// Nombre de caractères maximal d'une partie : ~3 300 jetons d'entrée, de quoi rester sous 8 000 jetons par minute avec la réponse.
    var tailleDePartie = 10_000

    /// `surEtape` : un court libellé de ce qui se passe (« Note en préparation, partie 2 sur 4 »). Journal sans contenu de la réunion.
    /// `avance(fait, total)` : les appels faits sur le total (une partie par appel, plus l'assemblage), pour « Note en préparation… ».
    func rediger(segments: [SegmentReunion], duree: Double, debut: Date,
                 surEtape: @escaping @Sendable (String) -> Void = { _ in },
                 avance: @escaping @Sendable (Int, Int) -> Void = { _, _ in }) async throws -> (note: NoteBrute, retraits: [String]) {
        let garde = GardeInvention(segments: segments)
        let parties = DecoupeReunion.parties(segments, maxCaracteres: tailleDePartie)
        var brute: NoteBrute
        if parties.count <= 1 {
            surEtape("Note en préparation")
            avance(0, 1)
            brute = try await appeler(systeme: NoteReunion.consigneNote, message: NoteReunion.messageTranscription(segments, duree: duree, debut: debut), maxSortie: 5000, effort: "medium")
            avance(1, 1)
        } else {
            var notes: [NoteBrute] = []
            let total = parties.count + 1
            for (i, p) in parties.enumerated() {
                surEtape("Note en préparation, partie \(i + 1) sur \(parties.count)")
                avance(i, total)
                notes.append(try await appeler(systeme: NoteReunion.consignePartie, message: NoteReunion.messagePartie(p, numero: i + 1, sur: parties.count), maxSortie: 2600, effort: "low"))
            }
            surEtape("Note en préparation, assemblage")
            avance(parties.count, total)
            brute = try await appeler(systeme: NoteReunion.consigneAssemblage, message: NoteReunion.messageAssemblage(notes, duree: duree, debut: debut), maxSortie: 5000, effort: "medium")
            avance(total, total)
        }
        let (propre, retraits) = garde.nettoyer(brute)
        return (propre, retraits)
    }

    /// « Ce que j'ai raté » : les dernières minutes en deux ou trois puces, un seul appel court (le même modèle et le même plafond de
    /// jetons que la note). On n'attend pas plus de 8 s une place sous le plafond : au-delà, le résumé est dit impossible pour l'instant.
    func rattraper(_ segments: [SegmentReunion]) async throws -> [String] {
        let message = RattrapageReunion.message(segments)
        let maxSortie = 1500   // le raisonnement du modèle compte dans la limite (leçon du 09/11)
        let estimation = DecoupeReunion.jetons(RattrapageReunion.consigne) + DecoupeReunion.jetons(message) + maxSortie
        let attente = Self.budget.delaiAvant(jetons: estimation)
        if attente > 8 { throw Erreur.abandon("plafond de jetons par minute") }
        if attente > 0 { try await Task.sleep(for: .seconds(attente)) }
        let t0 = ProcessInfo.processInfo.systemUptime
        let r = try await groq.completerNote(modele: modele, systeme: RattrapageReunion.consigne, texte: message, maxSortie: maxSortie, effort: "low", delai: 30)
        Self.budget.noter(jetons: r.jetons > 0 ? r.jetons : estimation)
        Log.ecrire("réunion : « Ce que j'ai raté », réponse de \(modele) en \(Int((ProcessInfo.processInfo.systemUptime - t0) * 1000)) ms (\(r.jetons) jetons)")
        guard let puces = RattrapageReunion.analyser(r.texte) else { throw Erreur.reponseIllisible }
        return puces
    }

    /// « Demander » sur une réunion : une réponse courte et le passage qui l'appuie (le même service et le même plafond que la note).
    func demander(_ question: String, reunion r: Reunion) async throws -> QuestionReunion.Reponse {
        let message = QuestionReunion.message(question, reunion: r)
        let texte = try await completer(systeme: QuestionReunion.consigne, message: message, maxSortie: 1200)
        guard let rep = QuestionReunion.analyser(texte, passages: r.segments.count) else { throw Erreur.reponseIllisible }
        return rep
    }

    /// « Demander à mes réunions » : à partir des notes (les plus récentes d'abord) ; la réponse dit de quelle réunion elle vient.
    func demander(_ question: String, reunions: [Reunion]) async throws -> (reponse: QuestionReunion.Reponse, envoyees: [Reunion]) {
        let (message, n) = QuestionReunion.messageToutes(question, reunions: reunions)
        let texte = try await completer(systeme: QuestionReunion.consigneToutes, message: message, maxSortie: 1200)
        guard let rep = QuestionReunion.analyserToutes(texte, nombre: n) else { throw Erreur.reponseIllisible }
        return (rep, Array(reunions.prefix(n)))
    }

    /// Un appel court : pas plus de 10 s d'attente sous le plafond de jetons, 45 s de réponse.
    private func completer(systeme: String, message: String, maxSortie: Int) async throws -> String {
        let estimation = DecoupeReunion.jetons(systeme) + DecoupeReunion.jetons(message) + maxSortie
        let attente = Self.budget.delaiAvant(jetons: estimation)
        if attente > 10 { throw Erreur.abandon("plafond de jetons par minute") }
        if attente > 0 { try await Task.sleep(for: .seconds(attente)) }
        let t0 = ProcessInfo.processInfo.systemUptime
        let r = try await groq.completerNote(modele: modele, systeme: systeme, texte: message, maxSortie: maxSortie, effort: "low", delai: 45)
        Self.budget.noter(jetons: r.jetons > 0 ? r.jetons : estimation)
        Log.ecrire("réunions : « Demander », réponse de \(modele) en \(Int((ProcessInfo.processInfo.systemUptime - t0) * 1000)) ms (\(r.jetons) jetons)")
        return r.texte
    }

    private func appeler(systeme: String, message: String, maxSortie: Int, effort: String) async throws -> NoteBrute {
        let estimation = DecoupeReunion.jetons(systeme) + DecoupeReunion.jetons(message) + maxSortie
        for essai in 1...6 {
            let attente = Self.budget.delaiAvant(jetons: estimation)
            if attente > 0 { Log.ecrire("réunion : note, attente de \(Int(attente)) s (plafond de jetons par minute)"); try await Task.sleep(for: .seconds(attente)) }
            do {
                let t0 = ProcessInfo.processInfo.systemUptime
                let r = try await groq.completerNote(modele: modele, systeme: systeme, texte: message, maxSortie: maxSortie, effort: effort)
                Self.budget.noter(jetons: r.jetons > 0 ? r.jetons : estimation)
                Log.ecrire("réunion : note, réponse de \(modele) en \(Int((ProcessInfo.processInfo.systemUptime - t0) * 1000)) ms (\(r.jetons) jetons)")
                if let n = NoteReunion.analyser(r.texte) { return n }
                Log.ecrire("réunion : note, réponse illisible à l'essai \(essai)")
                if essai >= 2 { throw Erreur.reponseIllisible }
            } catch let limite as NoteLimite {
                Self.budget.noter(jetons: estimation)
                try await Task.sleep(for: .seconds(min(70, max(5, limite.retryApres ?? 20))))
            } catch GroqErreur.reseau(let m) {
                if essai >= 4 { throw Erreur.abandon("réseau : \(m)") }
                try await Task.sleep(for: .seconds(Double(essai) * 4))
            } catch GroqErreur.http(let code) where code >= 500 {
                if essai >= 4 { throw Erreur.abandon("Groq a répondu HTTP \(code)") }
                try await Task.sleep(for: .seconds(Double(essai) * 4))
            }
        }
        throw Erreur.abandon("trop d'essais")
    }
}
