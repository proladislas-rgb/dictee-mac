import Foundation
import DicteeCore

/// L'historique enregistré localement : ~/Library/Application Support/Dictee/historique.json (lisible par Hugues seul).
/// Date, app cible, texte final ; en cas d'échec d'insertion le texte y est aussi, récupérable.
@MainActor
final class HistoriqueStore: ObservableObject {
    static let shared = HistoriqueStore()

    @Published private(set) var historique = Historique()
    /// nil : un historique en mémoire seulement (essais, rendus), jamais écrit sur le disque.
    private let url: URL?
    private let file = DispatchQueue(label: "dictee.historique")

    /// Un historique factice, en mémoire : rien n'est lu ni écrit sur le disque (essais et rendus de l'îlot).
    init(enMemoire entrees: [EntreeHistorique]) {
        url = nil
        historique = Historique(entrees: entrees)
    }

    init(url: URL? = nil) {
        let u = url ?? Self.urlParDefaut
        self.url = u
        // illisible : mis de côté en .abime (jamais écrasé par la prochaine écriture), on repart d'un historique vide
        if let lu = Self.magasin(u).lire() { historique = lu }
    }

    static var urlParDefaut: URL { DossierVerbe.preparer("historique.json") }

    func ajouter(_ entree: EntreeHistorique) {
        historique.ajouter(entree, limite: Settings.limiteHistorique)
        enregistrer()
    }

    func supprimer(id: UUID) { historique.supprimer(id: id); enregistrer() }

    func effacer() { historique.effacer(); enregistrer(); Log.ecrire("historique effacé") }

    /// Le fichier de l'historique : lu tel quel, écrit d'un coup en 0600 (`FichierPrive`), échec tracé sans le contenu.
    nonisolated static func magasin(_ url: URL) -> MagasinJSON<Historique> { MagasinJSON(url: url, nom: "historique", journal: { Log.ecrire($0) }) }

    private func enregistrer() {
        guard let url else { return }
        let h = historique
        file.async { Self.magasin(url).ecrire(h) }
    }
}
