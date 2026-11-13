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
        if let donnees = try? Data(contentsOf: u) {
            if let lu = Historique.depuis(donnees) { historique = lu }
            else { Log.ecrire("historique : fichier illisible, on repart d'un historique vide (l'ancien est gardé en .abime)"); try? FileManager.default.moveItem(at: u, to: u.appendingPathExtension("abime")) }
        }
    }

    static var urlParDefaut: URL { DossierVerbe.preparer("historique.json") }

    func ajouter(_ entree: EntreeHistorique) {
        historique.ajouter(entree, limite: Settings.limiteHistorique)
        enregistrer()
    }

    func supprimer(id: UUID) { historique.supprimer(id: id); enregistrer() }

    func effacer() { historique.effacer(); enregistrer(); Log.ecrire("historique effacé") }

    private func enregistrer() {
        guard let url, let donnees = historique.donnees() else { return }
        file.async {
            do {
                try donnees.write(to: url, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            } catch { Log.ecrire("historique : enregistrement impossible (\(error.localizedDescription))") }
        }
    }
}
