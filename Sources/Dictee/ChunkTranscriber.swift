import Foundation
import DicteeCore

/// Envoie chaque morceau de son à Groq dès qu'il est prêt (en parallèle) et recolle les textes dans l'ordre.
final class ChunkTranscriber: @unchecked Sendable {
    enum Resultat {
        case texte(String)
        case echec(String)
        case delai
    }

    private struct Sortie { var texte: String? ; var erreur: String? }

    private let lock = NSLock()
    private var taches: [Task<Sortie, Never>] = []
    private var dernierTexte: String?          // fin du dernier morceau déjà revenu, pour la continuité
    private let mots: [String]
    private let langue: String?
    private let groq: GroqClient
    private let t0: Double

    init(groq: GroqClient = .shared, mots: [String], langue: String?) {
        self.groq = groq
        self.mots = mots
        self.langue = langue
        self.t0 = ProcessInfo.processInfo.systemUptime
    }

    var nombreDeMorceaux: Int { lock.lock(); defer { lock.unlock() }; return taches.count }

    /// Lance l'envoi d'un morceau. Ne bloque pas (appelé depuis le fil audio).
    func envoyer(wav: Data, duree: Double) {
        lock.lock()
        let numero = taches.count + 1
        let contexte = dernierTexte
        let tache = Task { [weak self, groq, mots, langue] () -> Sortie in
            guard self != nil else { return Sortie(texte: nil, erreur: "annulé") }
            let prompt = TextAssembler.prompt(mots: mots, contexte: contexte)
            let debut = ProcessInfo.processInfo.systemUptime
            do {
                let texte = try await groq.transcrire(wav: wav, prompt: prompt, langue: langue)
                let ms = Int((ProcessInfo.processInfo.systemUptime - debut) * 1000)
                Log.ecrire("morceau \(numero) : \(String(format: "%.1f", duree)) s de son -> Groq en \(ms) ms, \"\(Log.apercu(texte))\"")
                self?.noterTexte(texte)
                return Sortie(texte: texte, erreur: nil)
            } catch is CancellationError {
                return Sortie(texte: nil, erreur: "annulé")
            } catch {
                Log.ecrire("morceau \(numero) : échec Groq (\(error))")
                return Sortie(texte: nil, erreur: "\(error)")
            }
        }
        taches.append(tache)
        lock.unlock()
    }

    private func copieDesTaches() -> [Task<Sortie, Never>] { lock.lock(); defer { lock.unlock() }; return taches }

    private func noterTexte(_ texte: String) {
        lock.lock(); dernierTexte = texte; lock.unlock()
    }

    func annuler() {
        lock.lock(); let t = taches; lock.unlock()
        t.forEach { $0.cancel() }
    }

    /// Attend tous les morceaux, au plus `delai` secondes. Un morceau en échec fait échouer le tout :
    /// un texte à trous serait pire qu'un texte de secours complet.
    func resultat(delai: Double) async -> Resultat {
        let liste = copieDesTaches()
        if liste.isEmpty { return .texte("") }
        let course = await withTaskGroup(of: Resultat.self) { groupe -> Resultat in
            groupe.addTask {
                var parties: [String?] = []
                for t in liste {
                    let s = await t.value
                    if let e = s.erreur { return .echec(e) }
                    parties.append(s.texte)
                }
                return .texte(TextAssembler.joindre(parties))
            }
            groupe.addTask {
                try? await Task.sleep(for: .seconds(delai))
                return .delai
            }
            let premier = await groupe.next() ?? .delai
            groupe.cancelAll()
            return premier
        }
        if case .texte = course {} else { annuler() }
        return course
    }
}
