import AppKit
import CoreAudio
import DicteeCore

// « Micro coupé » (maquette design/maquettes/ilot-apple.html, « Cinq idées de plus », 5) : le micro d'entrée par défaut du Mac,
// coupé et rouvert par CoreAudio. Aucun sondage : CoreAudio prévient quand le micro par défaut change et quand son « muet » (ou son
// volume) change, quelle que soit l'app qui l'a fait (Réglages Système, une app d'appel). Aucun flux audio n'est ouvert : couper ou
// rouvrir un micro n'écoute rien, macOS ne demande aucune autorisation et le point orange ne s'allume pas.

/// Ce que l'îlot demande au micro du Mac : le vrai (`MicroSysteme`) ou un faux pour les essais, qui ne touchent jamais au vrai micro.
@MainActor
protocol PiloteMicro: AnyObject {
    /// Le micro par défaut, son muet ou son volume a changé : relire `estCoupe()`.
    var surChangement: () -> Void { get set }
    var actif: Bool { get }
    func demarrer()
    func arreter()
    /// Coupé ? nil : aucun micro d'entrée.
    func estCoupe() -> Bool?
    /// « Micro MacBook Air », « AirPods Pro de Hugues ».
    var nom: String? { get }
    /// Faux si ce micro ne se coupe pas (ni muet ni volume réglable).
    func couper() -> Bool
    func rouvrir() -> Bool
    /// La dictée de Verbe écoute-t-elle ce micro-là ? (En « Automatique », des AirPods par défaut : la dictée prend le micro du Mac.)
    func dicteeUtiliseCeMicro() -> Bool
}

/// Le micro d'entrée par défaut, par CoreAudio : `kAudioDevicePropertyMute` sur l'entrée, ou, pour un micro qui n'a pas de muet, son
/// volume d'entrée à 0 (l'ancien volume est gardé dans les réglages, par micro, pour être rendu, même après un redémarrage de Verbe).
@MainActor
final class MicroSysteme: PiloteMicro {
    var surChangement: () -> Void = {}
    private(set) var actif = false
    private var appareil = AudioDeviceID(0)
    private var blocDefaut: AudioObjectPropertyListenerBlock?
    private var blocAppareil: AudioObjectPropertyListenerBlock?
    private var ecoutees: [AudioObjectPropertyAddress] = []

    /// Les éléments qu'on règle : l'élément principal, sinon les deux premiers canaux (certains micros USB n'ont que ceux-là).
    private static let elements: [AudioObjectPropertyElement] = [kAudioObjectPropertyElementMain, 1, 2]

    func demarrer() {
        guard !actif else { return }
        actif = true
        var a = Self.adresse(kAudioHardwarePropertyDefaultInputDevice, scope: kAudioObjectPropertyScopeGlobal)
        // les rappels arrivent sur le fil principal (file principale donnée à CoreAudio)
        let b: AudioObjectPropertyListenerBlock = { [weak self] _, _ in MainActor.assumeIsolated { self?.defautChange() } }
        blocDefaut = b
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &a, .main, b)
        suivre(Self.defaut())
    }

    func arreter() {
        guard actif else { return }
        actif = false
        if let b = blocDefaut {
            var a = Self.adresse(kAudioHardwarePropertyDefaultInputDevice, scope: kAudioObjectPropertyScopeGlobal)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &a, .main, b)
        }
        blocDefaut = nil
        suivre(0)
    }

    private func defautChange() {
        let d = Self.defaut()
        Log.ecrire("micro coupé : le micro par défaut a changé (\(Self.texte(d, kAudioObjectPropertyName) ?? "aucun"))")
        suivre(d)
        surChangement()
    }

    /// Écoute le muet et le volume d'entrée de ce micro (et plus ceux de l'ancien).
    private func suivre(_ id: AudioDeviceID) {
        guard id != appareil else { return }
        if appareil != 0, let b = blocAppareil {
            for var a in ecoutees { AudioObjectRemovePropertyListenerBlock(appareil, &a, .main, b) }
        }
        ecoutees = []; blocAppareil = nil
        appareil = id
        guard id != 0 else { return }
        let b: AudioObjectPropertyListenerBlock = { [weak self] _, _ in MainActor.assumeIsolated { self?.surChangement() } }
        blocAppareil = b
        for s in [kAudioDevicePropertyMute, kAudioDevicePropertyVolumeScalar] {
            for e in Self.elements {
                var a = Self.adresse(s, element: e)
                if AudioObjectHasProperty(id, &a), AudioObjectAddPropertyListenerBlock(id, &a, .main, b) == noErr { ecoutees.append(a) }
            }
        }
    }

    var nom: String? { appareil == 0 ? nil : Self.texte(appareil, kAudioObjectPropertyName) }
    private var uid: String? { appareil == 0 ? nil : Self.texte(appareil, kAudioDevicePropertyDeviceUID) }

    func estCoupe() -> Bool? {
        guard appareil != 0 else { return nil }
        if let a = adresseMuet(reglable: false) {
            var v: UInt32 = 0, t = UInt32(MemoryLayout<UInt32>.size), aa = a
            if AudioObjectGetPropertyData(appareil, &aa, 0, nil, &t, &v) == noErr { return v != 0 }
        }
        let vs = adressesVolume(reglables: false).compactMap(lireVolume)
        guard let max = vs.max() else { return false }
        return MicroIlot.estCoupe(volume: max)
    }

    func couper() -> Bool {
        guard appareil != 0 else { return false }
        if let a = adresseMuet(reglable: true) { return ecrireMuet(a, 1) }
        let vs = adressesVolume(reglables: true)
        guard !vs.isEmpty else { Log.ecrire("micro coupé : « \(nom ?? "?") » n'a ni muet ni volume réglable"); return false }
        // l'ancien volume, gardé pour être rendu (seulement s'il était audible : recouper un micro déjà à 0 ne l'efface pas)
        if let v = vs.compactMap(lireVolume).max(), !MicroIlot.estCoupe(volume: v), let u = uid {
            var g = Settings.microVolumesGardes; g[u] = v; Settings.microVolumesGardes = g
        }
        return vs.map { ecrireVolume($0, 0) }.allSatisfy { $0 }
    }

    func rouvrir() -> Bool {
        guard appareil != 0 else { return false }
        if let a = adresseMuet(reglable: true) { return ecrireMuet(a, 0) }
        let vs = adressesVolume(reglables: true)
        guard !vs.isEmpty else { return false }
        let v = MicroIlot.volumeARendre(garde: uid.flatMap { Settings.microVolumesGardes[$0] })
        return vs.map { ecrireVolume($0, v) }.allSatisfy { $0 }
    }

    func dicteeUtiliseCeMicro() -> Bool {
        switch AudioCapture.decider() {
        case .systeme: return true
        case .impose(let p, _): return p.uid == uid
        }
    }

    // MARK: CoreAudio

    private static func adresse(_ s: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeInput,
                                element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: s, mScope: scope, mElement: element)
    }
    private func reglable(_ a: AudioObjectPropertyAddress) -> Bool {
        var aa = a, r: DarwinBoolean = false
        return AudioObjectIsPropertySettable(appareil, &aa, &r) == noErr && r.boolValue
    }
    private func existe(_ a: AudioObjectPropertyAddress) -> Bool { var aa = a; return AudioObjectHasProperty(appareil, &aa) }
    /// Le muet de l'entrée (élément principal seulement : un muet par canal ne coupe pas tout).
    private func adresseMuet(reglable r: Bool) -> AudioObjectPropertyAddress? {
        let a = Self.adresse(kAudioDevicePropertyMute)
        return existe(a) && (!r || reglable(a)) ? a : nil
    }
    private func adressesVolume(reglables r: Bool) -> [AudioObjectPropertyAddress] {
        let principal = Self.adresse(kAudioDevicePropertyVolumeScalar)
        if existe(principal), !r || reglable(principal) { return [principal] }
        return Self.elements.dropFirst().map { Self.adresse(kAudioDevicePropertyVolumeScalar, element: $0) }.filter { existe($0) && (!r || reglable($0)) }
    }
    private func lireVolume(_ a: AudioObjectPropertyAddress) -> Double? {
        var v: Float32 = 0, t = UInt32(MemoryLayout<Float32>.size), aa = a
        return AudioObjectGetPropertyData(appareil, &aa, 0, nil, &t, &v) == noErr ? Double(v) : nil
    }
    private func ecrireMuet(_ a: AudioObjectPropertyAddress, _ v: UInt32) -> Bool {
        var x = v, aa = a
        let s = AudioObjectSetPropertyData(appareil, &aa, 0, nil, UInt32(MemoryLayout<UInt32>.size), &x)
        if s != noErr { Log.ecrire("micro coupé : muet = \(v) refusé par CoreAudio (\(s))") }
        return s == noErr
    }
    private func ecrireVolume(_ a: AudioObjectPropertyAddress, _ v: Double) -> Bool {
        var x = Float32(v), aa = a
        let s = AudioObjectSetPropertyData(appareil, &aa, 0, nil, UInt32(MemoryLayout<Float32>.size), &x)
        if s != noErr { Log.ecrire("micro coupé : volume d'entrée refusé par CoreAudio (\(s))") }
        return s == noErr
    }
    private static func defaut() -> AudioDeviceID {
        var id = AudioDeviceID(0), t = UInt32(MemoryLayout<AudioDeviceID>.size)
        var a = adresse(kAudioHardwarePropertyDefaultInputDevice, scope: kAudioObjectPropertyScopeGlobal)
        return AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &t, &id) == noErr ? id : 0
    }
    private static func texte(_ id: AudioObjectID, _ s: AudioObjectPropertySelector) -> String? {
        guard id != 0 else { return nil }
        var a = adresse(s, scope: kAudioObjectPropertyScopeGlobal)
        var ref: Unmanaged<CFString>?
        var t = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &t, &ref) == noErr, let ref else { return nil }
        return ref.takeRetainedValue() as String
    }
}

/// Un micro factice pour les essais (`--ilot-essai`) : il obéit aux commandes et prévient comme CoreAudio le ferait, sans rien toucher.
@MainActor
final class MicroFactice: PiloteMicro {
    var surChangement: () -> Void = {}
    private(set) var actif = false
    var coupe = false
    var nom: String? = "Micro MacBook Air"
    var reglable = true
    var memeMicroQueLaDictee = true
    /// Les commandes reçues, dans l'ordre (« couper », « rouvrir »).
    private(set) var commandes: [String] = []
    func demarrer() { actif = true }
    func arreter() { actif = false }
    func estCoupe() -> Bool? { coupe }
    func couper() -> Bool { commandes.append("couper"); guard reglable else { return false }; changer(true); return true }
    func rouvrir() -> Bool { commandes.append("rouvrir"); guard reglable else { return false }; changer(false); return true }
    func dicteeUtiliseCeMicro() -> Bool { memeMicroQueLaDictee }
    /// Comme CoreAudio : la notification arrive un peu après, sur la file principale.
    func changer(_ c: Bool) {
        coupe = c
        DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { if self?.actif == true { self?.surChangement() } } }
    }
    /// Quelqu'un d'autre change le micro (Réglages Système).
    func depuisLeSysteme(coupe c: Bool) { changer(c) }
}
