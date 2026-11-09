import Foundation
import DicteeCore

/// Lance une commande du système sans jamais attendre indéfiniment ; entrée vide, sortie et erreurs réunies.
/// (hdiutil, codesign, ditto, xattr : aucun ne touche au micro, à la parole, à l'accessibilité ni au clavier.)
enum Commande {
    struct Resultat {
        var code: Int32
        var texte: String
        var delaiDepasse: Bool
        var reussie: Bool { code == 0 && !delaiDepasse }
    }

    private final class Etat: @unchecked Sendable {
        let verrou = NSLock()
        var donnees = Data()
        var repris = false
        var delaiDepasse = false
    }

    static func executer(_ chemin: String, _ arguments: [String], delai: TimeInterval = 180) async -> Resultat {
        await withCheckedContinuation { suite in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: chemin)
            p.arguments = arguments
            p.standardInput = FileHandle.nullDevice
            p.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C"]
            let tube = Pipe()
            p.standardOutput = tube
            p.standardError = tube
            let etat = Etat()
            tube.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData
                etat.verrou.lock(); etat.donnees.append(d); etat.verrou.unlock()
            }
            p.terminationHandler = { fini in
                tube.fileHandleForReading.readabilityHandler = nil
                let reste = (try? tube.fileHandleForReading.readToEnd()) ?? Data()
                etat.verrou.lock()
                etat.donnees.append(reste)
                let deja = etat.repris; etat.repris = true
                let texte = String(decoding: etat.donnees, as: UTF8.self)
                let depasse = etat.delaiDepasse
                etat.verrou.unlock()
                if !deja { suite.resume(returning: Resultat(code: fini.terminationStatus, texte: texte, delaiDepasse: depasse)) }
            }
            do { try p.run() } catch {
                etat.verrou.lock(); let deja = etat.repris; etat.repris = true; etat.verrou.unlock()
                if !deja { suite.resume(returning: Resultat(code: -1, texte: "lancement impossible : \(error.localizedDescription)", delaiDepasse: false)) }
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + delai) {
                guard p.isRunning else { return }
                etat.verrou.lock(); etat.delaiDepasse = true; etat.verrou.unlock()
                p.terminate()
            }
        }
    }
}

enum EtapeInstallation: Equatable, Sendable {
    case telechargement(Double)
    case verification
    case installation
}

/// Télécharge, vérifie et installe une nouvelle version de Verbe À LA PLACE de l'app qui tourne. Une étape qui échoue ne remplace rien
/// et n'abîme jamais l'app actuelle : la nouvelle app est préparée à côté (même volume), contrôlée, puis permutée d'un seul geste
/// (`renamex_np` avec `RENAME_SWAP`) ; si le contrôle de l'app en place échoue, on permute en sens inverse.
/// Ne relance rien : c'est l'appelant qui s'en charge (ou pas, en test).
struct InstallateurMiseAJour {
    var client: ClientMiseAJour
    var identifiant = "com.hugues.dictee"
    /// Réservé aux essais en ligne de commande (`--simuler-echec-apres-echange`) : le contrôle de l'app remplacée échoue, pour prouver le retour en arrière.
    var echecSimuleApresEchange = false
    /// Marque des dossiers de préparation laissés à côté de l'app (supprimés au début de chaque installation).
    static let prefixePreparation = ".Verbe.app.maj-"

    func verdictEmplacement(_ app: URL) -> EmplacementApp.Verdict {
        let dossier = app.deletingLastPathComponent()
        let ro = (try? dossier.resourceValues(forKeys: [.volumeIsReadOnlyKey]).volumeIsReadOnly) ?? false
        return EmplacementApp.evaluer(chemin: app.path, volumeEnLectureSeule: ro, dossierEcrivable: FileManager.default.isWritableFile(atPath: dossier.path))
    }

    func installer(_ p: PropositionMiseAJour, appActuelle: URL, progression: @escaping @Sendable (EtapeInstallation) -> Void) async throws {
        let fm = FileManager.default
        if case .refuse(let raison) = verdictEmplacement(appActuelle) { throw ErreurMiseAJour(message: raison, detail: "emplacement refusé : \(appActuelle.path)") }
        let parent = appActuelle.deletingLastPathComponent()
        for reste in (try? fm.contentsOfDirectory(atPath: parent.path)) ?? [] where reste.hasPrefix(Self.prefixePreparation) {
            try? fm.removeItem(at: parent.appendingPathComponent(reste))
        }

        // Dossier de travail privé (0700), supprimé quoi qu'il arrive.
        let travail = fm.temporaryDirectory.appendingPathComponent("Verbe-MiseAJour-\(UUID().uuidString)", isDirectory: true)
        do { try fm.createDirectory(at: travail, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]) } catch {
            throw ErreurMiseAJour(message: "Verbe n\u{2019}a pas pu préparer un dossier de travail.", detail: error.localizedDescription)
        }
        defer { try? fm.removeItem(at: travail) }
        if let libre = try? travail.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage,
           libre < Int64(p.taille) * 3 {
            throw ErreurMiseAJour(message: "Il n\u{2019}y a pas assez de place sur le disque pour la mise à jour.", detail: "\(libre) octets libres, \(p.taille * 3) nécessaires")
        }

        // 1. Téléchargement et empreinte
        progression(.telechargement(0))
        let dmg = travail.appendingPathComponent(p.nomDMG)
        let calculee = try await client.telecharger(p, vers: dmg) { progression(.telechargement($0)) }
        progression(.verification)
        var attendues: [String] = []
        if let e = p.empreinteJSON { attendues.append(e) }
        if let e = try await client.empreinteDuFichier(p) { attendues.append(e) }
        if attendues.isEmpty {
            Log.ecrire("mise à jour : aucune empreinte publiée pour \(p.nomDMG), seules la taille et la signature sont contrôlées")
        } else if !EmpreinteSHA256.correspond(calculee: calculee, attendues: attendues) {
            throw ErreurMiseAJour(message: "Le fichier téléchargé ne correspond pas à l\u{2019}empreinte publiée.", detail: "SHA-256 calculé \(calculee), attendu \(attendues)")
        } else {
            Log.ecrire("mise à jour : empreinte SHA-256 conforme (\(attendues.count) source\(attendues.count > 1 ? "s" : ""))")
        }

        // 2. Montage en lecture seule, sans fenêtre Finder
        let montage = travail.appendingPathComponent("montage", isDirectory: true)
        try fm.createDirectory(at: montage, withIntermediateDirectories: false)
        let attache = await Commande.executer("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", montage.path, dmg.path])
        guard attache.reussie else { throw ErreurMiseAJour(message: "Verbe n\u{2019}a pas pu ouvrir le fichier téléchargé.", detail: "hdiutil attach : \(attache.texte)") }
        do {
            try await installerDepuis(montage: montage, proposition: p, appActuelle: appActuelle, parent: parent, progression: progression)
        } catch {
            await demonter(montage)
            throw error
        }
        await demonter(montage)
    }

    private func demonter(_ montage: URL) async {
        let d = await Commande.executer("/usr/bin/hdiutil", ["detach", montage.path])
        if !d.reussie {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            let f = await Commande.executer("/usr/bin/hdiutil", ["detach", "-force", montage.path])
            if !f.reussie { Log.ecrire("mise à jour : démontage impossible (\(f.texte.prefix(120)))") }
        }
    }

    private func installerDepuis(montage: URL, proposition p: PropositionMiseAJour, appActuelle: URL, parent: URL,
                                 progression: @Sendable (EtapeInstallation) -> Void) async throws {
        let fm = FileManager.default
        let source = montage.appendingPathComponent("Verbe.app")
        var estDossier: ObjCBool = false
        let attributs = try? fm.attributesOfItem(atPath: source.path)
        guard fm.fileExists(atPath: source.path, isDirectory: &estDossier), estDossier.boolValue, attributs?[.type] as? FileAttributeType == .typeDirectory else {
            throw ErreurMiseAJour(message: "Le fichier téléchargé ne contient pas Verbe.", detail: "Verbe.app absent ou lien dans l\u{2019}image disque")
        }
        try await controler(source, version: p.version, etape: "image disque")

        // 3. Copie à côté de l'app actuelle (même volume : l'échange est atomique)
        progression(.installation)
        let prepare = parent.appendingPathComponent(Self.prefixePreparation + UUID().uuidString.prefix(8))
        var garderPrepare = false
        // s'il reste quelque chose à cet endroit (échec, ou ancienne app après l'échange), on l'efface ; sauf si c'est la seule bonne copie
        defer { if !garderPrepare { try? fm.removeItem(at: prepare) } }
        let copie = await Commande.executer("/usr/bin/ditto", [source.path, prepare.path])
        guard copie.reussie else { throw ErreurMiseAJour(message: "La nouvelle version n\u{2019}a pas pu être copiée.", detail: "ditto : \(copie.texte)") }
        _ = await Commande.executer("/usr/bin/xattr", ["-dr", "com.apple.quarantine", prepare.path])
        try await controler(prepare, version: p.version, etape: "copie préparée")

        // 4. Échange atomique, puis contrôle de l'app en place ; sinon retour en arrière
        try echanger(prepare, appActuelle)
        do {
            if echecSimuleApresEchange { throw ErreurMiseAJour(message: "La nouvelle version n\u{2019}est pas celle attendue.", detail: "app remplacée : échec simulé") }
            try await controler(appActuelle, version: p.version, etape: "app remplacée")
        } catch {
            Log.ecrire("mise à jour : contrôle de l'app remplacée refusé, retour à l'ancienne version")
            do { try echanger(prepare, appActuelle) } catch let retour {
                garderPrepare = true
                Log.ecrire("mise à jour : RETOUR EN ARRIÈRE IMPOSSIBLE, l'ancienne version est dans \(prepare.lastPathComponent) (\(retour))")
            }
            throw error
        }
        Log.ecrire("mise à jour : \(appActuelle.lastPathComponent) remplacée par la version \(p.version)")
    }

    /// Signature intacte, bon identifiant (dans la signature et dans Info.plist), version annoncée, exécutable présent.
    private func controler(_ app: URL, version: VersionApp, etape: String) async throws {
        let verif = await Commande.executer("/usr/bin/codesign", ["--verify", "--strict", "--deep", app.path])
        guard verif.reussie else { throw ErreurMiseAJour(message: "La signature de la nouvelle version n\u{2019}est pas valide.", detail: "\(etape) : codesign --verify : \(verif.texte)") }
        let infos = await Commande.executer("/usr/bin/codesign", ["-dvv", app.path])
        let plist = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        if let raison = ControleApp.refus(identifiantAttendu: identifiant, identifiantSignature: ControleApp.identifiant(sortieCodesign: infos.texte),
                                          identifiantPlist: plist?["CFBundleIdentifier"] as? String, versionAttendue: version,
                                          versionPlist: plist?["CFBundleShortVersionString"] as? String) {
            throw ErreurMiseAJour(message: "La nouvelle version n\u{2019}est pas celle attendue.", detail: "\(etape) : \(raison)")
        }
        let executable = app.appendingPathComponent("Contents/MacOS/Verbe").path
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw ErreurMiseAJour(message: "La nouvelle version est incomplète.", detail: "\(etape) : exécutable absent")
        }
    }

    /// Permute les deux dossiers d'un seul appel système. Les volumes qui ne le savent pas (HFS+) passent par le remplacement de FileManager.
    private func echanger(_ a: URL, _ b: URL) throws {
        if renamex_np(a.path, b.path, UInt32(RENAME_SWAP)) == 0 { return }
        let code = errno
        guard code == ENOTSUP || code == EINVAL else {
            throw ErreurMiseAJour(message: "Verbe n\u{2019}a pas pu remplacer l\u{2019}ancienne version.", detail: "renamex_np : \(String(cString: strerror(code)))")
        }
        do { _ = try FileManager.default.replaceItemAt(b, withItemAt: a) } catch {
            throw ErreurMiseAJour(message: "Verbe n\u{2019}a pas pu remplacer l\u{2019}ancienne version.", detail: "replaceItemAt : \(error.localizedDescription)")
        }
    }
}
