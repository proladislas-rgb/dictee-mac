import Foundation
import DicteeCore

/// L'historique enregistré localement : ~/Library/Application Support/Dictee/historique.json (lisible par Hugues seul).
/// Date, app cible, texte final ; en cas d'échec d'insertion le texte y est aussi, récupérable.
@MainActor
final class HistoriqueStore: ObservableObject {
    static let shared = HistoriqueStore()

    @Published private(set) var historique = Historique()
    private let url: URL
    private let file = DispatchQueue(label: "dictee.historique")

    init(url: URL? = nil) {
        self.url = url ?? Self.urlParDefaut
        if let donnees = try? Data(contentsOf: self.url) {
            if let lu = Historique.depuis(donnees) { historique = lu }
            else { Log.ecrire("historique : fichier illisible, on repart d'un historique vide (l'ancien est gardé en .abime)"); try? FileManager.default.moveItem(at: self.url, to: self.url.appendingPathExtension("abime")) }
        }
    }

    static var urlParDefaut: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Dictee", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("historique.json")
    }

    func ajouter(_ entree: EntreeHistorique) {
        historique.ajouter(entree, limite: Settings.limiteHistorique)
        enregistrer()
    }

    func supprimer(id: UUID) { historique.supprimer(id: id); enregistrer() }

    func effacer() { historique.effacer(); enregistrer(); Log.ecrire("historique effacé") }

    private func enregistrer() {
        guard let donnees = historique.donnees() else { return }
        let url = url
        file.async {
            do {
                try donnees.write(to: url, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            } catch { Log.ecrire("historique : enregistrement impossible (\(error.localizedDescription))") }
        }
    }
}
