import Foundation

/// Les fichiers qu'une fonction RETIRÉE avait écrits dans le dossier de Voxile (`DossierVerbe`) : effacés au lancement, une fois, pour ne
/// rien laisser traîner. Logique pure (le dossier et le gestionnaire de fichiers sont donnés), vérifiée par `DicteeControles` sur un dossier
/// d'essai.
///
/// La désinstallation efface déjà tout le dossier de Voxile (`Desinstallation.cheminsRelatifs`) : ces fichiers y sont donc couverts même
/// si Voxile n'a jamais été relancé après la mise à jour.
public enum AnciensFichiers {
    /// La Concentration (12 au 13/11, retirée : « aucun intérêt, c'est rapide d'accès via macOS ») gardait sa mémoire ici : le mode
    /// allumé, le dernier, l'identifiant du raccourci « Concentration Verbe ». Son `.abime` : une copie mise de côté par `MagasinJSON`.
    public static let concentration = ["concentration.json", "concentration.json.abime"]
    public static let noms = concentration

    public struct Bilan: Equatable, Sendable {
        /// Les noms effacés.
        public var effaces: [String] = []
        /// Le mode de Concentration que l'ancienne version avait allumé et devait éteindre à l'heure (« travail », …) : il reste allumé
        /// dans macOS, à éteindre depuis le Centre de contrôle. nil : rien d'allumé (ou fichier illisible).
        public var concentrationLaisseeAllumee: String?
        public init(effaces: [String] = [], concentrationLaisseeAllumee: String? = nil) {
            self.effaces = effaces; self.concentrationLaisseeAllumee = concentrationLaisseeAllumee
        }
    }

    /// Le mode qu'une mémoire de Concentration dit allumé (`{"actif":{"mode":"travail",…}}`), sans relire le reste du format.
    public static func modeAllume(_ d: Data) -> String? {
        guard let racine = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let actif = racine["actif"] as? [String: Any], let mode = actif["mode"] as? String, !mode.isEmpty else { return nil }
        return mode
    }

    /// Efface les anciens fichiers présents dans `dossier` (jamais autre chose ; un lien est effacé, pas sa cible).
    public static func nettoyer(dossier: URL, fm: FileManager = .default) -> Bilan {
        var bilan = Bilan()
        for nom in noms {
            let url = dossier.appendingPathComponent(nom)
            guard let attributs = try? fm.attributesOfItem(atPath: url.path) else { continue }
            let lien = attributs[.type] as? FileAttributeType == .typeSymbolicLink
            if nom == "concentration.json", !lien, let d = try? Data(contentsOf: url) { bilan.concentrationLaisseeAllumee = modeAllume(d) }
            if (try? fm.removeItem(at: url)) != nil { bilan.effaces.append(nom) }
        }
        return bilan
    }
}
