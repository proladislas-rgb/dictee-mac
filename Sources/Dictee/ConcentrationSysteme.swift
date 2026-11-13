import AppKit
import DicteeCore

// La couche système des modes de Concentration : tout ce qui touche à l'app Raccourcis passe par ici, et nulle part ailleurs. Le pilote
// (IlotConcentration.swift) ne connaît que ces quatre fermetures : l'essai de l'îlot les remplace par des fausses (jamais de vrai raccourci
// créé, signé, ouvert ni lancé, jamais de vraie Concentration allumée pendant un essai).
//
// Pourquoi l'app Raccourcis (preuves dans docs/concentration-ilot.md) : macOS 26 n'a aucune interface publique pour ALLUMER un mode ;
// le service du système (`donotdisturbd`) refuse toute app sans droits réservés à Apple (« XPC connection without any valid
// entitlements tried to connect, will reject ») ; seule l'action « Définir la concentration » de Raccourcis le fait.

/// Ce que Verbe demande à l'app Raccourcis. Chaque fermeture est appelée HORS du fil principal (sauf `ouvrir`) et rend la main en un
/// temps borné (un garde-fou chronométré coupe la commande qui ne répond pas).
struct SystemeConcentration {
    /// Les raccourcis de la bibliothèque (`shortcuts list --show-identifiers`, lecture seule) ; nil : Raccourcis n'a pas répondu.
    var lister: () -> [RaccourciConcentration.Installe]?
    /// Écrit le raccourci et le signe pour ce Mac (`shortcuts sign --mode people-who-know-me`) dans `fichier` ; faux : échec.
    var preparer: (_ contenu: Data, _ fichier: URL) -> Bool
    /// Ouvre le fichier signé : Raccourcis montre « Ajouter le raccourci » (la seule question, posée une fois). Sur le fil principal.
    var ouvrir: (_ fichier: URL) -> Void
    /// Lance le raccourci `identifiant` avec la commande `entree` (sur son entrée standard) ; rend sa réponse, nil : échec.
    var lancer: (_ identifiant: String, _ entree: String) -> String?
}

extension SystemeConcentration {
    static let outil = URL(fileURLWithPath: "/usr/bin/shortcuts")

    /// Le vrai : l'outil `shortcuts` de macOS (le même que l'extension « Focus Modes » de Raycast).
    static let reel = SystemeConcentration(
        lister: {
            guard let r = executer(["list", "--show-identifiers"], delai: 5), r.code == 0 else { return nil }
            return RaccourciConcentration.lireListe(r.sortie)
        },
        preparer: { contenu, fichier in
            let brouillon = fichier.deletingLastPathComponent().appendingPathComponent("brouillon.shortcut")
            do {
                try FileManager.default.createDirectory(at: fichier.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                        attributes: [.posixPermissions: 0o700])
                try contenu.write(to: brouillon, options: .atomic)
            } catch { return false }
            defer { try? FileManager.default.removeItem(at: brouillon) }
            guard let r = executer(["sign", "--mode", "people-who-know-me", "--input", brouillon.path, "--output", fichier.path], delai: 20) else { return false }
            return r.code == 0 && FileManager.default.fileExists(atPath: fichier.path)
        },
        ouvrir: { NSWorkspace.shared.open($0) },
        lancer: { identifiant, entree in
            guard let r = executer(["run", identifiant], entree: Data((entree + "\n").utf8), delai: 20), r.code == 0 else { return nil }
            return r.sortie
        }
    )

    /// Lance `shortcuts` avec `arguments`, attend au plus `delai` secondes (au-delà : la commande est coupée, nil) et rend son code et sa
    /// sortie. Jamais sur le fil principal (il attend).
    static func executer(_ arguments: [String], entree: Data? = nil, delai: TimeInterval) -> (code: Int32, sortie: String)? {
        let p = Process()
        p.executableURL = outil
        p.arguments = arguments
        let sortie = Pipe(), erreurs = Pipe()
        p.standardOutput = sortie
        p.standardError = erreurs
        let entreePipe = entree.map { _ in Pipe() }
        p.standardInput = entreePipe ?? FileHandle.nullDevice
        let fini = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in fini.signal() }
        do { try p.run() } catch { Log.ecrire("concentration : Raccourcis introuvable (\(error.localizedDescription))"); return nil }
        if let entree, let e = entreePipe {
            // jamais de SIGPIPE ni d'exception si `shortcuts` s'arrête avant d'avoir lu (l'app en mourrait)
            _ = fcntl(e.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
            try? e.fileHandleForWriting.write(contentsOf: entree)
            try? e.fileHandleForWriting.close()
        }
        // la sortie est lue pendant que la commande tourne (un tuyau plein la bloquerait)
        var lu = Data()
        let lecture = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async { lu = sortie.fileHandleForReading.readDataToEndOfFile(); lecture.signal() }
        DispatchQueue.global(qos: .utility).async { _ = erreurs.fileHandleForReading.readDataToEndOfFile() }
        if fini.wait(timeout: .now() + delai) == .timedOut {
            p.terminate()
            _ = fini.wait(timeout: .now() + 1)
            Log.ecrire("concentration : « shortcuts \(arguments.first ?? "") » sans réponse après \(Int(delai)) s, coupé")
            return nil
        }
        // la sortie pas finie de lire une seconde après la fin : on ne la lit pas (l'autre fil l'écrit encore)
        guard lecture.wait(timeout: .now() + 1) == .success else { return nil }
        return (p.terminationStatus, String(decoding: lu, as: UTF8.self))
    }
}

/// Ce que Verbe garde des modes de Concentration : ~/Library/Application Support/Dictee/concentration.json (0600, jamais dans git, jamais
/// envoyé). Rien : pas de fichier.
typealias ConcentrationStore = MagasinJSON<MemoireConcentration>
extension MagasinJSON where Valeur == MemoireConcentration {
    init(url: URL) { self.init(url: url, nom: "concentration", journal: { Log.ecrire($0) }) }
    /// Le chemin seulement : le dossier n'est créé qu'à la première écriture (construire le pilote, essais compris, ne touche à rien).
    static var urlParDefaut: URL { DossierVerbe.url("concentration.json") }
}
