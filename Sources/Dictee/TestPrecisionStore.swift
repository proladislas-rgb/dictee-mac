import Foundation
import DicteeCore

/// Le test de précision sur la vraie voix de Hugues : garde le son (WAV) et le texte de chaque dictée dans `test-precision/` (dossier 0700,
/// fichiers 0600) pour les 50 prochaines dictées, puis s'arrête seul. `Verbe --comparer-precision` repasse ensuite ces sons.
enum TestPrecisionStore {
    static var dossier: URL {
        // DICTEE_DOSSIER_TEST_PRECISION : dossier d'essai (contrôles du comparateur), jamais utilisé en usage normal.
        if let d = ProcessInfo.processInfo.environment["DICTEE_DOSSIER_TEST_PRECISION"], !d.isEmpty { return URL(fileURLWithPath: d, isDirectory: true) }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Dictee/test-precision", isDirectory: true)
    }

    static func fichiers() -> [String] { (try? FileManager.default.contentsOfDirectory(atPath: dossier.path)) ?? [] }

    /// Garde le son et les textes de cette dictée si le test est actif. Écriture hors du fil principal ; le compteur baisse tout de suite.
    @MainActor
    static func enregistrerSiActif(echantillons: [Int16], appId: String?, appNom: String?, texteGroq: String, texteFinal: String, duree: Double, idDictee: Int) {
        let restant = Settings.testPrecisionRestant
        guard restant > 0, !echantillons.isEmpty else { return }
        Settings.testPrecisionRestant = TestPrecision.apresUnSon(restant: restant)
        let fini = Settings.testPrecisionRestant == 0
        let langue = Settings.langue
        Task.detached(priority: .utility) {
            let fm = FileManager.default
            do {
                try fm.createDirectory(at: dossier, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                let numero = TestPrecision.prochainNumero(fichiers: fichiers())
                let base = TestPrecision.nomDeFichier(numero: numero)
                let meta = EchantillonPrecision(numero: numero, date: Date(), appId: appId, appNom: appNom, modele: Settings.modeleWhisper.identifiant, langue: langue,
                                                texteGroq: texteGroq, texteFinal: texteFinal, duree: duree)
                let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted, .sortedKeys]
                for (nom, donnees) in [("\(base).wav", WAV.encode(samples: echantillons)), ("\(base).json", try enc.encode(meta))] {
                    let url = dossier.appendingPathComponent(nom)
                    try donnees.write(to: url, options: .atomic)
                    try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                }
                Log.ecrire("dictée \(idDictee) : son gardé pour le test de précision (\(base), \(String(format: "%.1f", duree)) s)\(fini ? " ; c'était la dernière, le test s'arrête" : "")")
            } catch {
                Log.ecrire("dictée \(idDictee) : test de précision, son non gardé (\(error.localizedDescription))")
            }
        }
    }
}
