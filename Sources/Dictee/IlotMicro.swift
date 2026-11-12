import AppKit
import CoreAudio
import DicteeCore

// « Micro coupé » (maquette design/maquettes/ilot-apple.html, « Cinq idées de plus », 5) : le micro d'entrée par défaut du Mac,
// coupé et rouvert par CoreAudio. Aucun sondage : CoreAudio prévient quand le micro par défaut change et quand son « muet » (ou son
// volume) change, quelle que soit l'app qui l'a fait (Réglages Système, une app d'appel). Aucun flux audio n'est ouvert : couper ou
// rouvrir un micro n'écoute rien, macOS ne demande aucune autorisation et le point orange ne s'allume pas. Coupé veut dire coupé : fn
// ne rouvre rien (IlotControleur.autoriserDictee).

/// Ce que l'îlot demande aux micros du Mac : les vrais (`MicroSysteme`) ou des faux pour les essais, qui ne touchent jamais à un vrai
/// micro. Chaque commande vise un micro précis, par son UID (le micro par défaut peut changer entre la coupure et la réouverture).
@MainActor
protocol PiloteMicro: AnyObject {
    /// Le micro par défaut, son muet ou son volume a changé : relire `defaut` et `estCoupe`.
    var surChangement: () -> Void { get set }
    var actif: Bool { get }
    func demarrer()
    func arreter()
    /// L'UID du micro d'entrée par défaut (nil : aucun micro d'entrée).
    var defaut: String? { get }
    /// Le nom du micro par défaut : « Micro MacBook Air », « AirPods Pro de Hugues ».
    var nom: String? { get }
    /// Le nom d'un micro, par son UID (nil : débranché).
    func nom(de uid: String) -> String?
    /// Ce micro est-il coupé ? nil : il n'existe pas (débranché).
    func estCoupe(_ uid: String) -> Bool?
    /// Faux si ce micro ne se coupe pas (ni muet ni volume réglable) : le bouton Micro du Centre n'a alors aucun effet.
    func peutCouper(_ uid: String) -> Bool
    func couper(_ uid: String) -> Bool
    func rouvrir(_ uid: String) -> Bool
    /// L'UID du micro qu'écoutera la dictée de Verbe (en « Automatique », des AirPods par défaut : le micro du Mac).
    func microDeLaDictee() -> String?
}

/// Les micros d'entrée, par CoreAudio : `kAudioDevicePropertyMute` sur l'entrée, ou, pour un micro qui n'a pas de muet, son volume
/// d'entrée à 0 (l'ancien volume est gardé dans les réglages, par micro, pour être rendu, même après un redémarrage de Verbe). Seul le
/// micro par défaut est écouté (c'est lui que l'îlot montre) ; un autre micro n'est lu qu'au moment de s'en servir.
@MainActor
final class MicroSysteme: PiloteMicro {
    var surChangement: () -> Void = {}
    private(set) var actif = false
    /// Le micro par défaut, écouté.
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
        suivre(Self.defautID())
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
        let d = Self.defautID()
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

    var defaut: String? { appareil == 0 ? nil : Self.texte(appareil, kAudioDevicePropertyDeviceUID) }
    var nom: String? { appareil == 0 ? nil : Self.texte(appareil, kAudioObjectPropertyName) }
    func nom(de uid: String) -> String? { Self.texte(Self.appareil(uid: uid), kAudioObjectPropertyName) }

    func estCoupe(_ uid: String) -> Bool? {
        let id = Self.appareil(uid: uid)
        guard id != 0 else { return nil }
        if let a = Self.adresseMuet(id, reglable: false) {
            var v: UInt32 = 0, t = UInt32(MemoryLayout<UInt32>.size), aa = a
            if AudioObjectGetPropertyData(id, &aa, 0, nil, &t, &v) == noErr { return v != 0 }
        }
        let vs = Self.adressesVolume(id, reglables: false).compactMap { Self.lireVolume(id, $0) }
        guard let max = vs.max() else { return false }
        return MicroIlot.estCoupe(volume: max)
    }

    func peutCouper(_ uid: String) -> Bool {
        let id = Self.appareil(uid: uid)
        return id != 0 && (Self.adresseMuet(id, reglable: true) != nil || !Self.adressesVolume(id, reglables: true).isEmpty)
    }

    func couper(_ uid: String) -> Bool {
        let id = Self.appareil(uid: uid)
        guard id != 0 else { Log.ecrire("micro coupé : micro à couper introuvable (débranché ?)"); return false }
        if let a = Self.adresseMuet(id, reglable: true) { return Self.ecrireMuet(id, a, 1) }
        let vs = Self.adressesVolume(id, reglables: true)
        guard !vs.isEmpty else { Log.ecrire("micro coupé : « \(Self.texte(id, kAudioObjectPropertyName) ?? "?") » n'a ni muet ni volume réglable"); return false }
        // l'ancien volume, gardé pour être rendu (seulement s'il était audible : recouper un micro déjà à 0 ne l'efface pas)
        if let v = vs.compactMap({ Self.lireVolume(id, $0) }).max(), !MicroIlot.estCoupe(volume: v) {
            var g = Settings.microVolumesGardes; g[uid] = v; Settings.microVolumesGardes = g
        }
        return vs.map { Self.ecrireVolume(id, $0, 0) }.allSatisfy { $0 }
    }

    func rouvrir(_ uid: String) -> Bool {
        let id = Self.appareil(uid: uid)
        guard id != 0 else { Log.ecrire("micro coupé : micro à rouvrir introuvable (débranché ?)"); return false }
        if let a = Self.adresseMuet(id, reglable: true) { return Self.ecrireMuet(id, a, 0) }
        let vs = Self.adressesVolume(id, reglables: true)
        guard !vs.isEmpty else { return false }
        let v = MicroIlot.volumeARendre(garde: Settings.microVolumesGardes[uid])
        return vs.map { Self.ecrireVolume(id, $0, v) }.allSatisfy { $0 }
    }

    func microDeLaDictee() -> String? {
        switch AudioCapture.decider() {
        case .systeme: return defaut
        case .impose(let p, _): return p.uid
        }
    }

    // MARK: CoreAudio

    private static func adresse(_ s: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeInput,
                                element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: s, mScope: scope, mElement: element)
    }
    /// Le micro qui porte cet UID (0 : aucun, débranché).
    private static func appareil(uid: String) -> AudioDeviceID {
        var a = adresse(kAudioHardwarePropertyTranslateUIDToDevice, scope: kAudioObjectPropertyScopeGlobal)
        var cle: CFString = uid as CFString
        var id = AudioDeviceID(0), t = UInt32(MemoryLayout<AudioDeviceID>.size)
        let s = withUnsafeMutablePointer(to: &cle) {
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, UInt32(MemoryLayout<CFString>.size), $0, &t, &id)
        }
        return s == noErr && id != kAudioObjectUnknown ? id : 0
    }
    private static func reglable(_ id: AudioDeviceID, _ a: AudioObjectPropertyAddress) -> Bool {
        var aa = a, r: DarwinBoolean = false
        return AudioObjectIsPropertySettable(id, &aa, &r) == noErr && r.boolValue
    }
    private static func existe(_ id: AudioDeviceID, _ a: AudioObjectPropertyAddress) -> Bool { var aa = a; return AudioObjectHasProperty(id, &aa) }
    /// Le muet de l'entrée (élément principal seulement : un muet par canal ne coupe pas tout).
    private static func adresseMuet(_ id: AudioDeviceID, reglable r: Bool) -> AudioObjectPropertyAddress? {
        let a = adresse(kAudioDevicePropertyMute)
        return existe(id, a) && (!r || reglable(id, a)) ? a : nil
    }
    private static func adressesVolume(_ id: AudioDeviceID, reglables r: Bool) -> [AudioObjectPropertyAddress] {
        let principal = adresse(kAudioDevicePropertyVolumeScalar)
        if existe(id, principal), !r || reglable(id, principal) { return [principal] }
        return elements.dropFirst().map { adresse(kAudioDevicePropertyVolumeScalar, element: $0) }.filter { existe(id, $0) && (!r || reglable(id, $0)) }
    }
    private static func lireVolume(_ id: AudioDeviceID, _ a: AudioObjectPropertyAddress) -> Double? {
        var v: Float32 = 0, t = UInt32(MemoryLayout<Float32>.size), aa = a
        return AudioObjectGetPropertyData(id, &aa, 0, nil, &t, &v) == noErr ? Double(v) : nil
    }
    private static func ecrireMuet(_ id: AudioDeviceID, _ a: AudioObjectPropertyAddress, _ v: UInt32) -> Bool {
        var x = v, aa = a
        let s = AudioObjectSetPropertyData(id, &aa, 0, nil, UInt32(MemoryLayout<UInt32>.size), &x)
        if s != noErr { Log.ecrire("micro coupé : muet = \(v) refusé par CoreAudio (\(s))") }
        return s == noErr
    }
    private static func ecrireVolume(_ id: AudioDeviceID, _ a: AudioObjectPropertyAddress, _ v: Double) -> Bool {
        var x = Float32(v), aa = a
        let s = AudioObjectSetPropertyData(id, &aa, 0, nil, UInt32(MemoryLayout<Float32>.size), &x)
        if s != noErr { Log.ecrire("micro coupé : volume d'entrée refusé par CoreAudio (\(s))") }
        return s == noErr
    }
    private static func defautID() -> AudioDeviceID {
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

/// Des micros factices pour les essais (`--ilot-essai`) : ils obéissent aux commandes et préviennent comme CoreAudio le ferait, sans
/// rien toucher. Deux micros : celui du Mac (« integre ») et des AirPods (« airpods »), branchés ou non.
@MainActor
final class MicroFactice: PiloteMicro {
    var surChangement: () -> Void = {}
    private(set) var actif = false
    /// Les micros branchés : UID → coupé.
    var coupes: [String: Bool] = ["integre": false]
    var noms = ["integre": "Micro MacBook Air", "airpods": "AirPods Pro"]
    private(set) var defaut: String? = "integre"
    /// Le micro de la dictée (nil : celui par défaut).
    var microDictee: String?
    var reglable = true
    /// Le micro par défaut est coupé.
    var coupe: Bool { defaut.flatMap { coupes[$0] } ?? false }
    var nom: String? { defaut.flatMap { noms[$0] } }
    func nom(de uid: String) -> String? { coupes[uid] == nil ? nil : noms[uid] }
    /// Les commandes reçues, dans l'ordre (« couper integre », « rouvrir airpods »).
    private(set) var commandes: [String] = []
    func demarrer() { actif = true }
    func arreter() { actif = false }
    func estCoupe(_ uid: String) -> Bool? { coupes[uid] }
    func peutCouper(_ uid: String) -> Bool { reglable && coupes[uid] != nil }
    func couper(_ uid: String) -> Bool { commander("couper", uid, true) }
    func rouvrir(_ uid: String) -> Bool { commander("rouvrir", uid, false) }
    func microDeLaDictee() -> String? { microDictee ?? defaut }
    private func commander(_ c: String, _ uid: String, _ v: Bool) -> Bool {
        commandes.append("\(c) \(uid)")
        guard reglable, coupes[uid] != nil else { return false }
        coupes[uid] = v; notifier()
        return true
    }
    /// Comme CoreAudio : la notification arrive un peu après, sur la file principale.
    private func notifier() {
        DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { if self?.actif == true { self?.surChangement() } } }
    }
    /// Quelqu'un d'autre coupe ou rouvre le micro par défaut (Réglages Système).
    func depuisLeSysteme(coupe c: Bool) { if let d = defaut { coupes[d] = c }; notifier() }
    /// Un autre micro devient celui par défaut (des AirPods qui se connectent), dans l'état donné.
    func brancher(_ uid: String, coupe c: Bool = false) { coupes[uid] = c; defaut = uid; notifier() }
    /// Le micro par défaut revient à celui du Mac (AirPods rangés).
    func debrancher(_ uid: String) { coupes[uid] = nil; if defaut == uid { defaut = "integre" }; notifier() }
}
