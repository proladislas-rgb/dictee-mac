import Foundation
import DicteeCore

/// La remise au propre du texte final d'une dictée : réutilise ce qui a été lancé pendant la dictée quand c'est valable
/// (unités de phrases, ou texte entier lancé à la pause d'avant le relâchement), sinon remet tout au propre d'un coup.
/// Même code pour l'app et pour le banc d'essai `--transcrire --nettoyer-aussi`.
enum NettoyageFinal {
    typealias Anticipe = (brut: String, contexte: ContexteMiseEnForme, tache: Task<Nettoyage.Resultat, Never>)

    /// Remise au propre lancée à l'avance sur le texte qu'on aurait si la parole s'arrêtait là (réponse de Groq arrivée pendant la pause).
    /// Rien ne part si elle est inutile, désactivée, ou si le budget de requêtes est bas.
    static func lancerALAvance(_ brut: String, contexte: ContexteMiseEnForme, mots: [String], relecture: RelectureSession? = nil) -> Anticipe? {
        let relirePeutServir = Settings.relecture && relecture != nil   // la décision se prend dans `Nettoyage` (rien ne part si la relecture est inutile)
        guard (Settings.remettreAuPropre && RemiseAuPropre.analyser(brut).utile) || relirePeutServir, GroqClient.shared.cleDisponible,
              BudgetRequetes.nettoyage.permet(.anticipation) else { return nil }
        return (brut, contexte, Task.detached(priority: .userInitiated) { await Nettoyage.executer(brut, contexte: contexte, mots: mots, relecture: relecture) })
    }

    static func executer(brut: String, contexte: ContexteMiseEnForme, transcripteur: ChunkTranscriber, unites: NettoyageParUnites?,
                         anticipe: Anticipe?, mots: [String], relecture: RelectureSession? = nil) async -> (resultat: Nettoyage.Resultat, mode: String) {
        let parties = transcripteur.textes()
        // Texte entier déjà remis au propre pendant la pause d'avant le relâchement : rien de plus rapide.
        if let a = anticipe, a.brut == brut, a.contexte == contexte {
            unites?.annulerTout()
            return (await a.tache.value, "lancée à l'avance et réutilisée")
        }
        if let unites, unites.nombreDUnites > 0, TextAssembler.joindre(parties) == brut,
           let r = await unites.resultat(parties: parties, contexte: contexte) {
            anticipe?.tache.cancel()
            return (r, "par unités")
        }
        var mode = "d'un coup"
        if let a = anticipe { a.tache.cancel(); mode = "d'un coup (l'avance jetée : le texte ou l'endroit a changé)" }
        return (await Nettoyage.executer(brut, contexte: contexte, mots: mots, relecture: relecture), mode)
    }
}
