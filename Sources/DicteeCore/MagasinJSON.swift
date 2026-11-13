import Foundation

/// Le dossier de Voxile sur ce Mac : ~/Library/Application Support/Dictee (le nom date de « Dictée » ; le garder, c'est ne rien
/// perdre). Tous les fichiers de l'utilisateur passent par ici : jamais un chemin écrit en dur ailleurs.
public enum DossierVerbe {
    /// Le chemin depuis le dossier personnel (la désinstallation l'efface).
    public static let relatif = "Library/Application Support/Dictee"

    /// `nom` dans le dossier de Voxile (un fichier, ou un sous-dossier avec `dossier: true`) ; sans nom, le dossier lui-même. Rien
    /// n'est créé.
    public static func url(_ nom: String? = nil, dossier: Bool = false, maison: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        let racine = maison.appendingPathComponent(relatif, isDirectory: true)
        guard let nom else { return racine }
        return racine.appendingPathComponent(nom, isDirectory: dossier)
    }

    /// Comme `url(_:)`, le dossier de Voxile créé s'il manque (pour les fichiers lus et écrits hors de `MagasinJSON`).
    public static func preparer(_ nom: String) -> URL {
        try? FileManager.default.createDirectory(at: url(), withIntermediateDirectories: true)
        return url(nom)
    }
}

/// Un type gardé dans un fichier JSON : il se relit (nil : illisible) et s'écrit (nil : rien à écrire). Le format est le sien.
public protocol FichierJSON {
    static func depuis(_ d: Data) -> Self?
    func donnees() -> Data?
}

extension ListeRappels: FichierJSON {}
extension EtagereIlot: FichierJSON {}
extension ListeNotes: FichierJSON {}
extension BibliothequeIlot: FichierJSON {}
extension ReveilIlot: FichierJSON {}
extension MemoireConcentration: FichierJSON {}
extension Historique: FichierJSON {}

/// Un fichier JSON de l'utilisateur (rappels, étagère, notes…) : relu tel quel, écrit d'un coup en 0600 (`FichierPrive`), échec tracé
/// au journal (jamais le contenu). Le magasin ne touche pas au format : c'est celui du type (`depuis` / `donnees`).
public struct MagasinJSON<Valeur: FichierJSON>: Sendable {
    /// Que faire d'un fichier illisible : le garder à côté en `.abime` (à la place d'un `.abime` plus ancien), ou l'oublier.
    public enum SiIllisible: Sendable { case garderEnAbime, oublier }

    /// nil : en mémoire seulement (essais, rendus) ; rien n'est lu ni écrit.
    public var url: URL?
    /// Le nom au journal (« rappels »).
    public var nom: String
    public var siIllisible: SiIllisible
    /// Le journal de l'app (le cœur n'en a pas).
    public var journal: @Sendable (String) -> Void

    public init(url: URL?, nom: String, siIllisible: SiIllisible = .garderEnAbime, journal: @escaping @Sendable (String) -> Void = { _ in }) {
        self.url = url; self.nom = nom; self.siIllisible = siIllisible; self.journal = journal
    }

    public var existe: Bool { url.map { FileManager.default.fileExists(atPath: $0.path) } ?? false }

    /// La valeur gardée ; nil : pas de fichier, ou un fichier illisible (mis de côté ou oublié, et tracé).
    public func lire() -> Valeur? {
        guard let url, let d = try? Data(contentsOf: url) else { return nil }
        if let v = Valeur.depuis(d) { return v }
        let fm = FileManager.default
        switch siIllisible {
        case .garderEnAbime:
            FichierIllisible.mettreDeCote(url, nom: nom, journal: journal)
        case .oublier:
            journal("\(nom) : fichier illisible, oublié")
            try? fm.removeItem(at: url)
        }
        return nil
    }

    /// Écrit la valeur (le dossier est créé s'il manque). Faux : rien d'écrit (en mémoire, rien à écrire, ou échec tracé).
    @discardableResult
    public func ecrire(_ valeur: Valeur) -> Bool {
        guard let url, let d = valeur.donnees() else { return false }
        do {
            try FichierPrive.ecrire(d, vers: url)
            return true
        } catch {
            let e = error as NSError
            journal("\(nom) : écriture impossible (\(e.domain) \(e.code))")
            return false
        }
    }

    public func effacer() {
        if let url { try? FileManager.default.removeItem(at: url) }
    }
}

/// Un fichier de l'utilisateur qu'on ne sait plus lire : mis de côté à côté de lui, en `.abime` (un `.abime` plus ancien est remplacé :
/// sinon le déplacement échoue et la prochaine écriture écrase le fichier abîmé, 12/11), et la ligne du journal dit ce qui s'est vraiment
/// passé. Pour les magasins JSON comme pour les fichiers lus à part (raccourcis, propositions de mots).
public enum FichierIllisible {
    @discardableResult
    public static func mettreDeCote(_ url: URL, nom: String, journal: (String) -> Void) -> Bool {
        let fm = FileManager.default
        let abime = url.appendingPathExtension("abime")
        try? fm.removeItem(at: abime)
        do {
            try fm.moveItem(at: url, to: abime)
            journal("\(nom) : fichier illisible, l'ancien est gardé en .abime")
            return true
        } catch {
            journal("\(nom) : fichier illisible, impossible de le mettre de côté (\((error as NSError).domain) \((error as NSError).code))")
            return false
        }
    }
}

/// Écriture d'un fichier privé : un fichier temporaire à côté, CRÉÉ en 0600 (jamais lisible par un autre compte, même un instant), puis
/// renommé sur le vrai (jamais un fichier à moitié écrit).
public enum FichierPrive {
    public static func ecrire(_ donnees: Data, vers url: URL) throws {
        let dossier = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        let temporaire = dossier.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString)")
        let fd = open(temporaire.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let h = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        do {
            try h.write(contentsOf: donnees)
            try h.close()
            guard rename(temporaire.path, url.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        } catch {
            unlink(temporaire.path)
            throw error
        }
    }
}
