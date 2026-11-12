import AppKit
import DicteeCore

/// Le passage du nom Verbe à Voxile (13/11, Hugues : « pourquoi j'ai toujours le truc Verbe ? il faudrait une app Voxile directement »).
/// Au lancement de l'app installée :
/// - lancée depuis une `Verbe.app` (posée par la mise à jour automatique d'une Verbe 0.3.x, qui ne connaît que ce nom), elle se renomme
///   en `Voxile.app` au même endroit, puis se relance depuis là : une seule app, au nouveau nom ;
/// - lancée depuis une `Voxile.app` (installée à la main), une ancienne `Verbe.app` du même identifiant, à côté ou dans l'autre dossier
///   Applications, part à la corbeille (récupérable) : jamais deux apps.
/// Le paquet garde l'identifiant com.hugues.dictee : autorisations, réglages et historique restent.
enum MigrationNom {
    @MainActor
    static func appliquer() -> Bool {
        let fm = FileManager.default
        let ici = Bundle.main.bundleURL
        let identifiant = NomApp.identifiant
        func memeApp(_ url: URL) -> Bool { Bundle(url: url)?.bundleIdentifier == identifiant }
        switch PassageNom.decision(nomPaquet: ici.lastPathComponent) {
        case .renommer(let nouveau):
            let cible = ici.deletingLastPathComponent().appendingPathComponent(nouveau)
            guard !fm.fileExists(atPath: cible.path) else {
                // une Voxile.app est déjà là (installée à la main) : on la lance, et l'ancienne part à la corbeille
                Log.ecrire("nom : Voxile.app déjà présente à côté, l'ancienne Verbe.app part à la corbeille")
                guard memeApp(cible) else { Log.ecrire("nom : une Voxile.app d'un autre identifiant est déjà là, rien n'est touché"); return false }
                try? fm.trashItem(at: ici, resultingItemURL: nil)
                MiseAJourControleur.relancer(cible)
                return true
            }
            do {
                try fm.moveItem(at: ici, to: cible)
                Log.ecrire("nom : Verbe.app renommée en Voxile.app, relance")
                MiseAJourControleur.relancer(cible)
                return true
            } catch {
                Log.ecrire("nom : renommage impossible (\(error.localizedDescription)), l'app continue sous l'ancien nom")
                return false
            }
        case .rangerLesAnciennes(let anciens):
            let dossiers = [ici.deletingLastPathComponent(), URL(fileURLWithPath: "/Applications"), fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
            var vus = Set<String>()
            for d in dossiers {
                for nom in anciens {
                    let u = d.appendingPathComponent(nom).standardizedFileURL
                    guard vus.insert(u.path).inserted, u.path != ici.standardizedFileURL.path, fm.fileExists(atPath: u.path), memeApp(u) else { continue }
                    do { try fm.trashItem(at: u, resultingItemURL: nil); Log.ecrire("nom : ancienne \(nom) mise à la corbeille (\(d.path))") }
                    catch { Log.ecrire("nom : ancienne \(nom) laissée en place (\(error.localizedDescription))") }
                }
            }
            return false
        case .rien:
            return false
        }
    }
}
