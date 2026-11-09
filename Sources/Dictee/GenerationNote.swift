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
    func rediger(segments: [SegmentReunion], duree: Double, debut: Date, surEtape: @escaping @Sendable (String) -> Void = { _ in }) async throws -> (note: NoteBrute, retraits: [String]) {
        let garde = GardeInvention(segments: segments)
        let parties = DecoupeReunion.parties(segments, maxCaracteres: tailleDePartie)
        var brute: NoteBrute
        if parties.count <= 1 {
            surEtape("Note en préparation")
            brute = try await appeler(systeme: NoteReunion.consigneNote, message: NoteReunion.messageTranscription(segments, duree: duree, debut: debut), maxSortie: 2500, effort: "medium")
        } else {
            var notes: [NoteBrute] = []
            for (i, p) in parties.enumerated() {
                surEtape("Note en préparation, partie \(i + 1) sur \(parties.count)")
                notes.append(try await appeler(systeme: NoteReunion.consignePartie, message: NoteReunion.messagePartie(p, numero: i + 1, sur: parties.count), maxSortie: 1800, effort: "low"))
            }
            surEtape("Note en préparation, assemblage")
            brute = try await appeler(systeme: NoteReunion.consigneAssemblage, message: NoteReunion.messageAssemblage(notes, duree: duree, debut: debut), maxSortie: 2500, effort: "medium")
        }
        let (propre, retraits) = garde.nettoyer(brute)
        return (propre, retraits)
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
