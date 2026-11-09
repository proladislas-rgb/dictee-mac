import Foundation

/// Ce que « Désinstaller Dictée… » efface, et rien d'autre. Fonctions sans interface, vérifiées par `DicteeControles`
/// (sur un faux dossier personnel, jamais sur le vrai).
///
/// Ne touche jamais à `~/.config/groq/.env` : ce fichier appartient à la personne, pas à l'app.
public enum Desinstallation {
    public static let identifiant = "com.hugues.dictee"
    /// L'élément du Trousseau qui garde la clé Groq (service + compte).
    public static let serviceTrousseau = "com.hugues.dictee"
    public static let compteTrousseau = "groq"

    /// Chemins relatifs au dossier personnel : historique, mots, raccourcis, journal, réglages, caches.
    public static let cheminsRelatifs: [String] = [
        "Library/Application Support/Dictee",
        "Library/Logs/Dictee",
        "Library/Preferences/\(identifiant).plist",
        "Library/Caches/\(identifiant)",
        "Library/HTTPStorages/\(identifiant)",
        "Library/Saved Application State/\(identifiant).savedState",
    ]

    public static func elements(maison: URL) -> [URL] {
        cheminsRelatifs.map { maison.appendingPathComponent($0) }
    }

    public struct Resultat: Equatable {
        public var effaces: [URL] = []
        public var absents: [URL] = []
        public var echecs: [URL] = []
    }

    /// Efface la liste ci-dessus. Refuse de travailler si `maison` n'a pas l'air d'un vrai dossier personnel (racine, vide).
    public static func effacer(maison: URL, fm: FileManager = .default) -> Resultat {
        var resultat = Resultat()
        let racine = maison.standardizedFileURL.path
        guard racine != "/", racine.count > 1, maison.isFileURL else { return resultat }
        let bibliotheque = racine + "/Library/"
        for url in elements(maison: maison) {
            let chemin = url.standardizedFileURL.path
            guard chemin.hasPrefix(bibliotheque), !chemin.contains("..") else { resultat.echecs.append(url); continue }
            // fileExists suit les liens ; on veut aussi voir un lien cassé.
            guard (try? fm.attributesOfItem(atPath: chemin)) != nil else { resultat.absents.append(url); continue }
            do { try fm.removeItem(atPath: chemin); resultat.effaces.append(url) } catch { resultat.echecs.append(url) }
        }
        return resultat
    }
}

/// Où se trouve l'app, et comment la placer dans Applications (glisser-déposer ou proposition au premier lancement).
public enum Installation {
    /// Proposer de se déplacer : l'app tourne depuis l'image disque (volume en lecture seule) ou depuis un dossier « translocalisé » par macOS.
    public static func doitProposerDeplacement(chemin: String, volumeEnLectureSeule: Bool) -> Bool {
        if chemin.contains("/AppTranslocation/") { return true }
        return chemin.hasPrefix("/Volumes/") && volumeEnLectureSeule
    }

    /// Dossier d'installation : /Applications si on peut y écrire, sinon ~/Applications.
    public static func dossierDestination(maison: URL, applicationsEcrivable: Bool) -> URL {
        applicationsEcrivable ? URL(fileURLWithPath: "/Applications", isDirectory: true)
                              : maison.appendingPathComponent("Applications", isDirectory: true)
    }

    public enum Erreur: Error { case sourceIntrouvable }

    /// Copie l'app dans `dossier` (créé au besoin). Si une version y est déjà, elle est remplacée d'un seul geste
    /// (la copie est d'abord faite à côté, donc une copie interrompue ne détruit pas l'ancienne).
    @discardableResult
    public static func copier(app: URL, dansDossier dossier: URL, fm: FileManager = .default) throws -> URL {
        guard fm.fileExists(atPath: app.path) else { throw Erreur.sourceIntrouvable }
        try fm.createDirectory(at: dossier, withIntermediateDirectories: true)
        let cible = dossier.appendingPathComponent(app.lastPathComponent)
        let temporaire = dossier.appendingPathComponent(".\(app.lastPathComponent).installation")
        try? fm.removeItem(at: temporaire)
        try fm.copyItem(at: app, to: temporaire)
        if fm.fileExists(atPath: cible.path) {
            _ = try fm.replaceItemAt(cible, withItemAt: temporaire)
        } else {
            try fm.moveItem(at: temporaire, to: cible)
        }
        return cible
    }
}
