import AppKit
import ServiceManagement
import DicteeCore

/// Installation et désinstallation de l'app elle-même. Aucun chemin n'est écrit en dur : tout part de `Bundle.main`
/// et du dossier personnel de la session.
@MainActor
enum InstallationApp {
    private static var maison: URL { FileManager.default.homeDirectoryForCurrentUser }

    // MARK: déplacement dans Applications (app lancée depuis l'image disque)

    /// Si l'app tourne depuis l'image disque, propose de la copier dans Applications puis de la relancer de là.
    /// Renvoie `true` quand l'app a été relancée ailleurs (l'appelant doit alors s'arrêter là).
    static func proposerDeplacementSiBesoin() -> Bool {
        let app = Bundle.main.bundleURL
        let lectureSeule = (try? app.resourceValues(forKeys: [.volumeIsReadOnlyKey]).volumeIsReadOnly) ?? false
        guard Installation.doitProposerDeplacement(chemin: app.path, volumeEnLectureSeule: lectureSeule) else { return false }

        let alerte = NSAlert()
        alerte.messageText = "Placer Verbe dans Applications ?"
        alerte.informativeText = "Verbe tourne depuis l\u{2019}image disque. Pour qu\u{2019}il reste installé, il va être copié dans Applications, puis relancé de là."
        alerte.addButton(withTitle: "Placer dans Applications")
        alerte.addButton(withTitle: "Pas maintenant")
        NSApp.activate(ignoringOtherApps: true)
        guard alerte.runModal() == .alertFirstButtonReturn else { return false }

        let ecrivable = FileManager.default.isWritableFile(atPath: "/Applications")
        let dossier = Installation.dossierDestination(maison: maison, applicationsEcrivable: ecrivable)
        do {
            let installee = try Installation.copier(app: app, dansDossier: dossier)
            Log.ecrire("installation : copiée dans \(dossier.lastPathComponent)")
            relancer(installee)
            return true
        } catch {
            Log.ecrire("installation : copie impossible (\(error.localizedDescription))")
            let echec = NSAlert()
            echec.messageText = "Verbe n\u{2019}a pas pu être copié"
            echec.informativeText = "Glisse Verbe dans le dossier Applications à la main, puis ouvre-le de là."
            echec.addButton(withTitle: "OK")
            echec.runModal()
            return false
        }
    }

    /// Lance la nouvelle copie une fois cette instance partie (l'app refuse de tourner en double).
    private static func relancer(_ app: URL) {
        let processus = Process()
        processus.executableURL = URL(fileURLWithPath: "/bin/sh")
        processus.arguments = ["-c", "sleep 1; /usr/bin/open \"$1\"", "sh", app.path]
        try? processus.run()
        NSApp.terminate(nil)
    }

    // MARK: désinstallation

    /// Confirmation sobre, puis efface tout ce que l'app a créé (voir `Desinstallation`), met l'app à la corbeille et quitte.
    /// Ne touche jamais à ~/.config/groq/.env.
    static func desinstaller() {
        // Une ancienne copie « Dictee.app » (nom d'avant Verbe) part aussi, mais on le dit avant, pas après.
        let anciennes = Desinstallation.anciennesApps(dossiers: Desinstallation.dossiersApplications(maison: maison), exclure: Bundle.main.bundleURL)
        let alerte = NSAlert()
        alerte.messageText = "Désinstaller Verbe ?"
        let ancienne = anciennes.isEmpty ? "" : " L\u{2019}ancienne app « \(Desinstallation.ancienNomApp) » (\(anciennes.map { $0.deletingLastPathComponent().path }.joined(separator: ", "))) est aussi placée à la corbeille."
        alerte.informativeText = "Cela efface l\u{2019}historique, les mots, les raccourcis, le journal, les réglages et la clé Groq rangée dans le Trousseau, puis place l\u{2019}app à la corbeille. Un fichier de clé que tu aurais créé toi-même (~/.config/groq/.env) n\u{2019}est pas touché." + ancienne
        alerte.addButton(withTitle: "Annuler")
        let bouton = alerte.addButton(withTitle: "Désinstaller")
        bouton.hasDestructiveAction = true
        NSApp.activate(ignoringOtherApps: true)
        guard alerte.runModal() == .alertSecondButtonReturn else { return }

        Log.ecrire("désinstallation demandée")
        try? SMAppService.mainApp.unregister()
        CleGroq.effacer()
        let resultat = Desinstallation.effacer(maison: maison)
        UserDefaults.standard.removePersistentDomain(forName: Desinstallation.identifiant)
        // Dernier mot du journal avant son arrêt définitif (sinon il recréerait son dossier à la sortie).
        Log.ecrire("désinstallation : \(resultat.effaces.count) éléments effacés, \(resultat.echecs.count) échecs")
        Log.desactiver()
        // Les préférences relues ci-dessus peuvent avoir recréé le fichier : on le retire une dernière fois.
        _ = Desinstallation.effacer(maison: maison)

        NSWorkspace.shared.recycle([Bundle.main.bundleURL] + anciennes) { _, erreur in
            DispatchQueue.main.async {
                if erreur != nil {
                    let reste = NSAlert()
                    reste.messageText = "Tes données sont effacées"
                    reste.informativeText = "Verbe n\u{2019}a pas pu se placer lui-même à la corbeille. Glisse-le à la corbeille à la main."
                    reste.addButton(withTitle: "OK")
                    reste.runModal()
                }
                // Sortie directe : plus aucun réglage ni fichier ne doit être réécrit après l'effacement.
                exit(0)
            }
        }
    }
}
