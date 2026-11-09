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
        alerte.messageText = "Placer Dictée dans Applications ?"
        alerte.informativeText = "Dictée tourne depuis l\u{2019}image disque. Pour qu\u{2019}elle reste installée, elle va être copiée dans Applications, puis relancée de là."
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
            echec.messageText = "Dictée n\u{2019}a pas pu être copiée"
            echec.informativeText = "Glisse Dictée dans le dossier Applications à la main, puis ouvre-la de là."
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
        let alerte = NSAlert()
        alerte.messageText = "Désinstaller Dictée ?"
        alerte.informativeText = "Cela efface l\u{2019}historique, les mots, les raccourcis, le journal, les réglages et la clé Groq rangée dans le Trousseau, puis place l\u{2019}app à la corbeille. Un fichier de clé que tu aurais créé toi-même (~/.config/groq/.env) n\u{2019}est pas touché."
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

        NSWorkspace.shared.recycle([Bundle.main.bundleURL]) { _, erreur in
            DispatchQueue.main.async {
                if erreur != nil {
                    let reste = NSAlert()
                    reste.messageText = "Tes données sont effacées"
                    reste.informativeText = "Dictée n\u{2019}a pas pu se placer elle-même à la corbeille. Glisse-la à la corbeille à la main."
                    reste.addButton(withTitle: "OK")
                    reste.runModal()
                }
                // Sortie directe : plus aucun réglage ni fichier ne doit être réécrit après l'effacement.
                exit(0)
            }
        }
    }
}
