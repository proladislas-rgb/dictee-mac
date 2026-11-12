import Foundation
import DicteeCore

// `Premiere` (le premier arrivé gagne) vit dans DicteeCore, avec ses contrôles.

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
