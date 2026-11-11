import AppKit
import IOBluetooth
import IOKit.ps
import DicteeCore

// La batterie du Mac et celle des appareils Bluetooth (maquette design/maquettes/ilot-apple.html) : ce que l'îlot montre dans ses
// épaules quand il est déplié, et les trois annonces (écouteurs connectés, chargeur branché, batterie faible).
// Aucun sondage : le Mac prévient quand l'alimentation change (IOPowerSources) et quand un appareil se connecte (IOBluetooth).

/// La batterie du Mac, relue à chaque changement d'alimentation (notification du système, pas de minuterie).
@MainActor
final class SourceEnergie {
    var surChangement: (EnergieIlot?) -> Void = { _ in }
    private var source: CFRunLoopSource?

    var actif: Bool { source != nil }

    func demarrer() {
        guard source == nil else { return }
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        guard let s = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let moi = Unmanaged<SourceEnergie>.fromOpaque(ctx).takeUnretainedValue()
            MainActor.assumeIsolated { moi.surChangement(SourceEnergie.lire()) }
        }, ctx)?.takeRetainedValue() else { return }
        source = s
        CFRunLoopAddSource(CFRunLoopGetMain(), s, .defaultMode)
        surChangement(Self.lire())
    }

    func arreter() {
        if let s = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .defaultMode) }
        source = nil
    }

    /// La batterie interne (nil sur un Mac sans batterie).
    static func lire() -> EnergieIlot? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let liste = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for s in liste {
            guard let d = IOPSGetPowerSourceDescription(info, s)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType,
                  let cap = d[kIOPSCurrentCapacityKey] as? Int else { continue }
            let max = (d[kIOPSMaxCapacityKey] as? Int).flatMap { $0 > 0 ? $0 : nil } ?? 100
            let secteur = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            return EnergieIlot(pourcent: Swift.max(0, Swift.min(100, Int((Double(cap) / Double(max) * 100).rounded()))),
                               secteur: secteur, enCharge: (d[kIOPSIsChargingKey] as? Bool) ?? false)
        }
        return nil
    }
}

/// Les appareils Bluetooth connectés qui ont une batterie. Le Mac prévient à chaque connexion ; la batterie des écouteurs se lit par
/// les méthodes `batteryPercent…` d'IOBluetoothDevice (non documentées, celles qu'utilisent les apps de batterie connues), relues
/// au dépliage de l'îlot. Une valeur 0 veut dire « inconnue ».
@MainActor
final class SourceAppareils: NSObject {
    /// Un appareil vient de se connecter (sa batterie est lue 2 s plus tard : les écouteurs la donnent après coup).
    var surConnexion: (AppareilIlot) -> Void = { _ in }
    /// La liste a changé (connexion, déconnexion, relecture).
    var surChangement: () -> Void = {}
    private(set) var connectes: [AppareilIlot] = []
    private var notificationConnexion: IOBluetoothUserNotification?
    private var notificationsDeconnexion: [IOBluetoothUserNotification] = []
    /// Les appareils dont on guette déjà la déconnexion (adresse Bluetooth).
    private var guettes = Set<String>()
    /// Dernière annonce par appareil : une souris qui se reconnecte à chaque réveil ne s'annonce qu'une fois par demi-heure.
    private var annonces: [String: Date] = [:]
    private var derniereLecture = Date.distantPast

    var actif: Bool { notificationConnexion != nil }

    func demarrer() {
        guard notificationConnexion == nil else { return }
        notificationConnexion = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(connecte(_:appareil:)))
        relire()
    }

    func arreter() {
        notificationConnexion?.unregister(); notificationConnexion = nil
        notificationsDeconnexion.forEach { $0.unregister() }; notificationsDeconnexion = []
        guettes = []; connectes = []
    }

    /// Les écouteurs à montrer dans l'épaule droite : les premiers écouteurs connectés dont on connaît la batterie.
    var ecouteurs: AppareilIlot? { connectes.first { $0.genre == .ecouteurs && $0.niveau != nil } }

    func relire() {
        guard actif else { return }
        derniereLecture = Date()
        let presents = ((IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []).filter { $0.isConnected() }
        // ceux qui étaient déjà connectés au lancement : on guette aussi leur départ
        presents.forEach(guetter)
        connectes = presents.compactMap(Self.lire)
        surChangement()
    }
    /// Au dépliage : relit la batterie, au plus une fois toutes les 5 s (la liste des appareils se lit sur le fil principal).
    func relireSiAncien() { if Date().timeIntervalSince(derniereLecture) > 5 { relire() } }

    private func guetter(_ d: IOBluetoothDevice) {
        let cle = d.addressString ?? ""
        guard !cle.isEmpty, !guettes.contains(cle),
              let fin = d.register(forDisconnectNotification: self, selector: #selector(deconnecte(_:appareil:))) else { return }
        guettes.insert(cle); notificationsDeconnexion.append(fin)
    }

    @objc private func connecte(_ n: IOBluetoothUserNotification, appareil d: IOBluetoothDevice) {
        guetter(d)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            MainActor.assumeIsolated {
                // le réglage a pu être éteint entre-temps : plus rien
                guard let self, self.actif, d.isConnected(), let a = Self.lire(d) else { return }
                self.relire()
                let cle = d.addressString ?? a.nom
                if let t = self.annonces[cle], Date().timeIntervalSince(t) < 1800 { return }
                self.annonces[cle] = Date()
                self.surConnexion(a)
            }
        }
    }

    @objc private func deconnecte(_ n: IOBluetoothUserNotification, appareil d: IOBluetoothDevice) {
        n.unregister()
        notificationsDeconnexion.removeAll { $0 === n }
        if let cle = d.addressString { guettes.remove(cle) }
        relire()
    }

    static func genre(_ d: IOBluetoothDevice) -> AppareilIlot.Genre {
        // classes Bluetooth : 0x04 audio/vidéo, 0x05 périphérique (souris 0x20, clavier 0x10 dans la classe mineure)
        switch d.deviceClassMajor {
        case 0x04: return .ecouteurs
        case 0x05: return (d.deviceClassMinor & 0x20) != 0 ? .souris : ((d.deviceClassMinor & 0x10) != 0 ? .clavier : .autre)
        default: return .autre
        }
    }

    private static func pourcent(_ d: IOBluetoothDevice, _ cle: String) -> Int? {
        guard d.responds(to: NSSelectorFromString(cle)), let n = d.value(forKey: cle) as? NSNumber else { return nil }
        let v = n.intValue
        return (1...100).contains(v) ? v : nil
    }

    /// Un appareil connecté avec au moins une batterie connue, sinon nil.
    static func lire(_ d: IOBluetoothDevice) -> AppareilIlot? {
        let a = AppareilIlot(nom: d.name ?? "", genre: genre(d),
                             gauche: pourcent(d, "batteryPercentLeft"), droit: pourcent(d, "batteryPercentRight"),
                             etui: pourcent(d, "batteryPercentCase"), unique: pourcent(d, "batteryPercentSingle"))
        guard a.genre != .autre || a.niveau != nil else { return nil }
        return a.niveau != nil || a.etui != nil ? a : nil
    }
}
