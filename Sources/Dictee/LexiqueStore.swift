import Foundation
import DicteeCore

/// Le lexique local (`~/Library/Application Support/Dictee/lexique.json`), relu seulement quand le fichier change.
/// Il contient des noms de la vie de Hugues : lisible par lui seul, jamais dans git.
final class LexiqueStore: @unchecked Sendable {
    static let partage = LexiqueStore()

    private let verrou = NSLock()
    private var entreesCache: [EntreeLexique] = []
    private var modifieLe: Date?
    private var derniereVerification = Date.distantPast
    private var indexCache: (cle: [String], index: IndexCorrection)?

    static var url: URL { DossierVerbe.preparer("lexique.json") }

    /// Les mots du lexique (vide si le fichier n'existe pas ou si le lexique est éteint dans les réglages).
    func entrees() -> [EntreeLexique] {
        guard Settings.lexiquePourWhisper else { return [] }
        verrou.lock(); defer { verrou.unlock() }
        recharger()
        return entreesCache
    }

    /// L'index de la correction à l'oreille : mots.txt (devant) + lexique.
    func index(motsChoisis: [String]) -> IndexCorrection? {
        guard Settings.correctionALOreille, Settings.lexiquePourWhisper else { return nil }
        verrou.lock(); defer { verrou.unlock() }
        recharger()
        if let c = indexCache, c.cle == motsChoisis { return c.index }
        let index = IndexCorrection(motsChoisis: motsChoisis, lexique: entreesCache)
        indexCache = (motsChoisis, index)
        return index
    }

    private func recharger() {
        if Date().timeIntervalSince(derniereVerification) < 3 { return }
        derniereVerification = Date()
        let attrs = try? FileManager.default.attributesOfItem(atPath: Self.url.path)
        let date = attrs?[.modificationDate] as? Date
        if date == modifieLe { return }
        modifieLe = date
        indexCache = nil
        guard date != nil, let donnees = try? Data(contentsOf: Self.url), let lu = Lexique.depuis(donnees) else { entreesCache = []; return }
        entreesCache = lu.entrees
        Log.ecrire("lexique chargé : \(lu.entrees.count) mots")
    }
}
