import Foundation

/// « Le premier arrivé gagne » sans attendre les perdants : une valeur donnée une seule fois, attendue par un seul appelant.
/// (`withTaskGroup` attend tous ses enfants avant de rendre la main, même annulés, quand l'un d'eux attend une autre tâche :
/// une course faite avec lui reste donc aussi lente que la plus lente des deux.)
final class Premiere<T: Sendable>: @unchecked Sendable {
    private let verrou = NSLock()
    private var continuation: CheckedContinuation<T?, Never>?
    private var fait = false
    private var valeur: T?

    /// Donne la valeur ; les appels suivants sont ignorés.
    func resoudre(_ v: T?) {
        verrou.lock()
        if fait { verrou.unlock(); return }
        fait = true; valeur = v
        let c = continuation; continuation = nil
        verrou.unlock()
        c?.resume(returning: v)
    }

    func attendre() async -> T? {
        await withCheckedContinuation { (c: CheckedContinuation<T?, Never>) in
            verrou.lock()
            if fait { verrou.unlock(); c.resume(returning: valeur) } else { continuation = c; verrou.unlock() }
        }
    }
}

/// Deux requêtes identiques : la première réponse réussie gagne ; si les deux échouent, la dernière erreur est rendue.
final class Duel: @unchecked Sendable {
    let course = Premiere<(secours: Bool, sortie: ChunkTranscriber.Sortie)>()
    private let verrou = NSLock()
    private var echecs = 0

    func fini(secours: Bool, sortie: ChunkTranscriber.Sortie) {
        if sortie.texte != nil { course.resoudre((secours, sortie)); return }
        verrou.lock(); echecs += 1; let tous = echecs >= 2; verrou.unlock()
        if tous { course.resoudre((secours, sortie)) }
    }
}
