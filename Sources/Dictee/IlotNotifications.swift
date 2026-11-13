import AppKit
import ApplicationServices
import DicteeCore

/// Les notifications des autres apps dans l'îlot. macOS n'offre AUCUNE interface publique pour lire les notifications des autres apps.
/// Options étudiées (détail dans docs/spec-v1.md) :
///  1. Accessibilité sur le Centre de notifications (`com.apple.notificationcenterui`) : on lit les textes des bannières au moment où elles
///     s'affichent. Aucune autorisation de plus que celle déjà donnée pour coller le texte ; rien n'est lu au repos (le système réveille
///     Verbe quand une fenêtre apparaît chez le Centre de notifications) ; mais la structure des bannières change d'une version de macOS à
///     l'autre, donc c'est FRAGILE, et la bannière du système s'affiche quand même.
///  2. La base de données de `usernoted` (~/Library/Group Containers/group.com.apple.usernoted) : demande l'accès complet au disque, qui
///     ouvre aussi tout le reste de la vie privée de Hugues. Rejeté.
/// Choix : 1, derrière un réglage ÉTEINT par défaut (« expérimental ») et jamais testable depuis le shell (il faut l'app installée).
@MainActor
final class SourceNotifications {
    var surNotification: (NotificationRecue) -> Void = { _ in }
    private var observateur: AXObserver?
    private var pid: pid_t = 0
    private var vues: [String: Date] = [:]
    private var enCours = false
    private(set) var actif = false

    static let bundleCentre = "com.apple.notificationcenterui"

    /// Démarre l'écoute. Faux si l'Accessibilité n'est pas accordée ou si le Centre de notifications est introuvable.
    @discardableResult
    func demarrer() -> Bool {
        guard !actif else { return true }
        guard Permissions.accessibiliteOK, let app = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleCentre).first else {
            Log.ecrire("notifications : Accessibilité ou Centre de notifications indisponible, écoute non démarrée")
            return false
        }
        pid = app.processIdentifier
        var obs: AXObserver?
        let rappel: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            let source = Unmanaged<SourceNotifications>.fromOpaque(refcon).takeUnretainedValue()
            DispatchQueue.main.async { MainActor.assumeIsolated { source.reveil() } }
        }
        guard AXObserverCreate(pid, rappel, &obs) == .success, let obs else { Log.ecrire("notifications : observateur refusé"); return false }
        let element = AXUIElementCreateApplication(pid)
        let moi = Unmanaged.passUnretained(self).toOpaque()
        var ajoutees = 0
        for n in [kAXWindowCreatedNotification, kAXCreatedNotification, kAXLayoutChangedNotification] {
            if AXObserverAddNotification(obs, element, n as CFString, moi) == .success { ajoutees += 1 }
        }
        guard ajoutees > 0 else { Log.ecrire("notifications : aucune notification d'Accessibilité acceptée"); return false }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        observateur = obs
        actif = true
        Log.ecrire("notifications : écoute du Centre de notifications (pid \(pid))")
        return true
    }

    func arreter() {
        if let observateur { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observateur), .defaultMode) }
        observateur = nil
        actif = false
    }

    /// Une fenêtre ou une mise en page a bougé chez le Centre de notifications : on relit les textes (hors du fil principal).
    private func reveil() {
        guard actif, !enCours else { return }
        enCours = true
        let p = pid
        Task.detached(priority: .utility) { [weak self] in
            let groupes = SourceNotifications.lireLesBannieres(pid: p)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.enCours = false
                let maintenant = Date()
                self.vues = self.vues.filter { maintenant.timeIntervalSince($0.value) < 12 }
                for textes in groupes {
                    let signature = textes.joined(separator: "\u{1F}")
                    guard self.vues[signature] == nil else { continue }
                    self.vues[signature] = maintenant
                    if let n = LectureNotifications.depuis(textes: textes, nomsDApps: Set(NSWorkspace.shared.runningApplications.compactMap(\.localizedName)), date: maintenant) {
                        self.surNotification(n)
                    }
                }
            }
        }
    }

    /// Les textes visibles de chaque fenêtre du Centre de notifications (une liste par fenêtre).
    nonisolated static func lireLesBannieres(pid: pid_t) -> [[String]] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        var valeur: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &valeur) == .success, let fenetres = valeur as? [AXUIElement] else { return [] }
        return fenetres.prefix(6).compactMap { f in
            AXUIElementSetMessagingTimeout(f, 0.3)
            var textes: [String] = []
            var vus = 0
            func parcourir(_ e: AXUIElement, _ profondeur: Int) {
                guard profondeur < 9, vus < 80 else { return }
                vus += 1
                var role: CFTypeRef?
                if AXUIElementCopyAttributeValue(e, kAXRoleAttribute as CFString, &role) == .success, (role as? String) == kAXStaticTextRole {
                    var v: CFTypeRef?
                    if AXUIElementCopyAttributeValue(e, kAXValueAttribute as CFString, &v) == .success, let s = v as? String { textes.append(s) }
                }
                var enfants: CFTypeRef?
                if AXUIElementCopyAttributeValue(e, kAXChildrenAttribute as CFString, &enfants) == .success, let liste = enfants as? [AXUIElement] {
                    for c in liste.prefix(30) { parcourir(c, profondeur + 1) }
                }
            }
            parcourir(f, 0)
            return textes.isEmpty ? nil : textes
        }
    }
}
