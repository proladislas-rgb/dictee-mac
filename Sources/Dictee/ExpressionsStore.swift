import Foundation
import DicteeCore

/// Les expressions personnelles (`~/Library/Application Support/Dictee/expressions.json`, 0600, jamais dans git), lues par tous les fils.
/// Mises à jour toutes seules une fois par jour d'après l'historique (voir `MotsModele.apprendreDeLHistorique`) et modifiables dans l'onglet Mots.
final class ExpressionsStore: @unchecked Sendable {
    static let partage = ExpressionsStore()

    private let verrou = NSLock()
    private var cache: ListeExpressions?
    private var modifieLe: Date?

    static var url: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Dictee", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("expressions.json")
    }

    func liste() -> ListeExpressions {
        verrou.lock(); defer { verrou.unlock() }
        return lire()
    }

    /// Modifie la liste et l'enregistre (0600). Renvoie la nouvelle liste.
    @discardableResult
    func modifier(_ changement: (inout ListeExpressions) -> Void) -> ListeExpressions {
        verrou.lock(); defer { verrou.unlock() }
        var l = lire()
        changement(&l)
        cache = l
        if let d = l.donnees() {
            do {
                try d.write(to: Self.url, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.url.path)
                modifieLe = (try? FileManager.default.attributesOfItem(atPath: Self.url.path))?[.modificationDate] as? Date
            } catch { Log.ecrire("expressions : enregistrement impossible (\(error.localizedDescription))") }
        }
        return l
    }

    /// À appeler verrou pris.
    private func lire() -> ListeExpressions {
        let date = (try? FileManager.default.attributesOfItem(atPath: Self.url.path))?[.modificationDate] as? Date
        if let cache, date == modifieLe { return cache }
        let l = ListeExpressions.depuis(try? Data(contentsOf: Self.url)) ?? ListeExpressions()
        cache = l; modifieLe = date
        return l
    }

    /// Les expressions données à Whisper et à la relecture (vide si le réglage est coupé).
    func pourWhisper(maximum: Int = 10) -> [String] {
        guard Settings.expressionsPourWhisper else { return [] }
        return liste().pourWhisper(maximum: maximum)
    }
}
