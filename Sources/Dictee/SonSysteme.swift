import AVFoundation
import CoreAudio
import AudioToolbox
import DicteeCore
import VerbeObjC

/// Le son du Mac (la voix des autres participants d'un appel) par un « process tap » de Core Audio (macOS 14.4 et plus) :
/// un tap global mono de tout ce que le Mac joue, sauf Verbe lui-même, rangé dans un appareil agrégé privé que l'app lit.
/// L'autorisation « Enregistrement du son du système » est demandée par macOS au premier usage (texte : NSAudioCaptureUsageDescription).
///
/// Rien n'est joué ni coupé : le tap n'altère pas le son que Hugues entend. Si macOS refuse ou si le tap ne s'installe pas,
/// `demarrer()` lève une erreur et la réunion continue avec le micro seul.
final class SonSysteme: @unchecked Sendable {
    enum Erreur: Error, LocalizedError {
        case etape(String, OSStatus)
        case format
        var errorDescription: String? {
            switch self {
            case .etape(let nom, let code): return "\(nom) refusé par macOS (erreur \(code))"
            case .format: return "format du son du Mac illisible"
            }
        }
    }

    /// Les commandes (démarrer, arrêter, réinstaller) passent par `file` ; la lecture du tap a sa propre file : arrêter le tap
    /// attend la fin de la lecture en cours, qui ne doit jamais attendre `file`.
    private let file = DispatchQueue(label: "dictee.reunion.sonsysteme")
    private let lecture = DispatchQueue(label: "dictee.reunion.sonsysteme.lecture", qos: .userInitiated)
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var agregatID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var surTampon: ((AVAudioPCMBuffer) -> Void)?
    private var enMarche = false
    private var ecouteurSortie: AudioObjectPropertyListenerBlock?
    private var reconstructions = 0

    func demarrer(surTampon: @escaping (AVAudioPCMBuffer) -> Void) throws {
        self.surTampon = surTampon
        try file.sync { try installer() }
        installerEcouteurSortie()
    }

    func arreter() {
        retirerEcouteurSortie()
        file.sync { enMarche = false; demonter(); surTampon = nil }
    }

    // MARK: installation (sur la file)

    private static func objet(pid: pid_t) -> AudioObjectID? {
        var adresse = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var id = AudioObjectID(kAudioObjectUnknown)
        var taille = UInt32(MemoryLayout<AudioObjectID>.size)
        var p = pid
        let statut = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &adresse, UInt32(MemoryLayout<pid_t>.size), &p, &taille, &id)
        return statut == noErr && id != AudioObjectID(kAudioObjectUnknown) ? id : nil
    }

    private static func texte(_ id: AudioObjectID, _ selecteur: AudioObjectPropertySelector) -> String? {
        var adresse = AudioObjectPropertyAddress(mSelector: selecteur, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var ref: Unmanaged<CFString>?
        var taille = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &adresse, 0, nil, &taille, &ref) == noErr, let ref else { return nil }
        return ref.takeRetainedValue() as String
    }

    /// L'appareil de sortie par défaut (là où le Mac joue le son) : l'appareil agrégé s'y rattache pour l'horloge.
    private static func sortieParDefaut() -> (id: AudioObjectID, uid: String)? {
        var adresse = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var id = AudioObjectID(kAudioObjectUnknown)
        var taille = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &adresse, 0, nil, &taille, &id) == noErr,
              id != AudioObjectID(kAudioObjectUnknown), let uid = texte(id, kAudioDevicePropertyDeviceUID) else { return nil }
        return (id, uid)
    }

    private func installer() throws {
        // 1. le tap : tout le son du Mac, sauf celui de Verbe (ses propres sons ne doivent pas entrer dans la réunion)
        let moi = Self.objet(pid: ProcessInfo.processInfo.processIdentifier)
        let description = CATapDescription(monoGlobalTapButExcludeProcesses: moi.map { [$0] } ?? [])
        description.uuid = UUID()
        description.name = "Voxile — réunion"
        description.muteBehavior = .unmuted
        description.isPrivate = true
        var statut = AudioHardwareCreateProcessTap(description, &tapID)
        guard statut == noErr else { tapID = AudioObjectID(kAudioObjectUnknown); throw Erreur.etape("tap du son du Mac", statut) }

        // 2. l'appareil agrégé privé qui porte le tap
        var dict: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Voxile — son de la réunion",
            kAudioAggregateDeviceUIDKey: "com.hugues.dictee.reunion.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: description.uuid.uuidString]],
        ]
        if let sortie = Self.sortieParDefaut() {
            dict[kAudioAggregateDeviceMainSubDeviceKey] = sortie.uid
            dict[kAudioAggregateDeviceSubDeviceListKey] = [[kAudioSubDeviceUIDKey: sortie.uid]]
        }
        statut = AudioHardwareCreateAggregateDevice(dict as CFDictionary, &agregatID)
        guard statut == noErr else { demonter(); throw Erreur.etape("appareil agrégé", statut) }

        // 3. le format du tap, puis la lecture
        var adresse = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var asbd = AudioStreamBasicDescription()
        var taille = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        statut = AudioObjectGetPropertyData(tapID, &adresse, 0, nil, &taille, &asbd)
        guard statut == noErr, let format = AVAudioFormat(streamDescription: &asbd) else { demonter(); throw statut == noErr ? Erreur.format : Erreur.etape("format du tap", statut) }

        let sortie = surTampon
        statut = AudioDeviceCreateIOProcIDWithBlock(&procID, agregatID, lecture) { _, entree, _, _, _ in
            var tampon: AVAudioPCMBuffer?
            _ = VerbeEssayer { tampon = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: entree, deallocator: nil) }
            if let tampon { sortie?(tampon) }
        }
        guard statut == noErr, procID != nil else { demonter(); throw Erreur.etape("lecture du tap", statut) }
        statut = AudioDeviceStart(agregatID, procID)
        guard statut == noErr else { demonter(); throw Erreur.etape("démarrage du tap", statut) }
        enMarche = true
        Log.ecrire("réunion : son du Mac démarré (\(Int(format.sampleRate)) Hz, \(format.channelCount) canal, sortie « \(Self.sortieParDefaut()?.uid ?? "aucune") »)")
    }

    private func demonter() {
        if let p = procID, agregatID != AudioObjectID(kAudioObjectUnknown) {
            _ = AudioDeviceStop(agregatID, p)
            _ = AudioDeviceDestroyIOProcID(agregatID, p)
        }
        procID = nil
        if agregatID != AudioObjectID(kAudioObjectUnknown) { _ = AudioHardwareDestroyAggregateDevice(agregatID); agregatID = AudioObjectID(kAudioObjectUnknown) }
        if tapID != AudioObjectID(kAudioObjectUnknown) { _ = AudioHardwareDestroyProcessTap(tapID); tapID = AudioObjectID(kAudioObjectUnknown) }
    }

    // MARK: la sortie change (casque branché pendant la réunion)

    private func installerEcouteurSortie() {
        var adresse = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let bloc: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.file.async { self?.reconstruire() } }
        ecouteurSortie = bloc
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &adresse, file, bloc)
    }

    private func retirerEcouteurSortie() {
        guard let bloc = ecouteurSortie else { return }
        var adresse = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &adresse, file, bloc)
        ecouteurSortie = nil
    }

    private func reconstruire() {
        guard enMarche, reconstructions < 5 else { return }
        reconstructions += 1
        Log.ecrire("réunion : la sortie du son a changé, le son du Mac est réinstallé (\(reconstructions))")
        demonter()
        do { try installer() } catch { enMarche = false; Log.ecrire("réunion : réinstallation du son du Mac impossible (\(error.localizedDescription))") }
    }
}

/// Prévient quand la liste des apps qui écoutent le micro PEUT avoir changé, sans aucun sondage : le système signale l'arrivée ou le
/// départ d'un processus audio, et chaque processus signale quand il commence ou arrête d'écouter le micro. (Avant : une question
/// à tous les processus toutes les 2 s, même sans appel ; elle coûtait du processeur à Verbe et au service audio de macOS.)
final class VeilleProcessusAudio: @unchecked Sendable {
    private let file = DispatchQueue(label: "verbe.audio.processus")
    private var ecoutes: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private var blocListe: AudioObjectPropertyListenerBlock?
    private let surChangement: @Sendable () -> Void

    init(surChangement: @escaping @Sendable () -> Void) { self.surChangement = surChangement }

    func demarrer() {
        file.async { [self] in
            guard blocListe == nil else { return }
            var a = Self.adresse(kAudioHardwarePropertyProcessObjectList)
            let bloc: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.rebrancher() }
            guard AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &a, file, bloc) == noErr else { return }
            blocListe = bloc
            rebrancher()
        }
    }

    /// Sur la file : écoute chaque processus présent (et seulement eux), puis prévient.
    private func rebrancher() {
        let presents = Set(ProcessusAudio.processus())
        for (id, bloc) in ecoutes where !presents.contains(id) {
            var a = Self.adresse(kAudioProcessPropertyIsRunningInput)
            AudioObjectRemovePropertyListenerBlock(id, &a, file, bloc)
            ecoutes[id] = nil
        }
        for id in presents where ecoutes[id] == nil {
            var a = Self.adresse(kAudioProcessPropertyIsRunningInput)
            let bloc: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.surChangement() }
            if AudioObjectAddPropertyListenerBlock(id, &a, file, bloc) == noErr { ecoutes[id] = bloc }
        }
        surChangement()
    }

    private static func adresse(_ s: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: s, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }
}

/// Qui utilise le micro en ce moment ? Lecture seule des propriétés des processus audio (aucune autorisation, aucun son capté) :
/// sert à proposer « Noter cet appel ? » quand une app d'appel écoute le micro.
enum ProcessusAudio {
    /// Les processus audio du moment.
    static func processus() -> [AudioObjectID] {
        var adresse = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var taille: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &adresse, 0, nil, &taille) == noErr, taille > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(taille) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &adresse, 0, nil, &taille, &ids) == noErr else { return [] }
        return ids
    }

    static func identifiantsEcoutantLeMicro() -> [String] {
        var sortie: [String] = []
        for id in processus() {
            var a = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyIsRunningInput, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var ecoute: UInt32 = 0
            var t = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(id, &a, 0, nil, &t, &ecoute) == noErr, ecoute != 0 else { continue }
            var b = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyBundleID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var ref: Unmanaged<CFString>?
            var tb = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            if AudioObjectGetPropertyData(id, &b, 0, nil, &tb, &ref) == noErr, let ref { sortie.append(ref.takeRetainedValue() as String) }
        }
        return sortie
    }
}
