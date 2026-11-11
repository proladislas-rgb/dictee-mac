import AVFoundation
import AudioToolbox
import CoreAudio

/// Un micro PRÉCIS, ouvert directement (unité HAL de Core Audio, entrée seule), sans jamais passer par le micro par défaut du Mac.
///
/// Pourquoi : AVAudioEngine relie toujours son nœud d'entrée au micro par défaut avant qu'on puisse en imposer un autre. Avec des
/// AirPods connectés (micro par défaut), ce simple passage suffit à faire basculer les AirPods en mode « casque-micro » (24 kHz) ;
/// la bascule change la configuration, le moteur est reconstruit, rebascule… et aucun son n'arrive (journal du 10/11 et du 11/11 :
/// « configuration changée pendant la dictée » toutes les 100 ms, puis « aucun son reçu »). Ici l'unité est liée au micro voulu
/// AVANT d'être initialisée : le micro des AirPods n'est jamais ouvert.
///
/// Les tampons sont lus sur le fil temps réel de Core Audio, copiés, puis remis sur une file ordinaire (`livraison`).
final class EntreeHAL: @unchecked Sendable {
    private var unite: AudioUnit?
    private let appareil: AudioDeviceID
    let format: AVAudioFormat
    private let livraison = DispatchQueue(label: "dictee.audio.hal")
    private var surTampon: ((AVAudioPCMBuffer) -> Void)?
    private var tamponRendu: AVAudioPCMBuffer?
    private(set) var enMarche = false

    /// nil si l'unité ne peut pas être créée ou liée à ce micro.
    init?(appareil: AudioDeviceID) {
        self.appareil = appareil
        var desc = AudioComponentDescription(componentType: kAudioUnitType_Output, componentSubType: kAudioUnitSubType_HALOutput,
                                             componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
        guard let comp = AudioComponentFindNext(nil, &desc) else { return nil }
        var u: AudioUnit?
        guard AudioComponentInstanceNew(comp, &u) == noErr, let u else { return nil }
        // entrée ouverte (élément 1), sortie fermée (élément 0) : l'unité ne touche jamais la sortie audio (les AirPods restent en stéréo)
        var un: UInt32 = 1, zero: UInt32 = 0
        var id = appareil
        let taille32 = UInt32(MemoryLayout<UInt32>.size)
        guard AudioUnitSetProperty(u, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &un, taille32) == noErr,
              AudioUnitSetProperty(u, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &zero, taille32) == noErr,
              AudioUnitSetProperty(u, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &id, UInt32(MemoryLayout<AudioDeviceID>.size)) == noErr
        else { AudioComponentInstanceDispose(u); return nil }
        // format du micro (côté matériel), puis format demandé : flottants 32 bits non entrelacés, un canal, à la cadence du micro
        var materiel = AudioStreamBasicDescription()
        var tailleFormat = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioUnitGetProperty(u, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 1, &materiel, &tailleFormat) == noErr,
              materiel.mSampleRate > 0,
              let f = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: materiel.mSampleRate, channels: 1, interleaved: false)
        else { AudioComponentInstanceDispose(u); return nil }
        var client = f.streamDescription.pointee
        guard AudioUnitSetProperty(u, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &client, tailleFormat) == noErr
        else { AudioComponentInstanceDispose(u); return nil }
        format = f
        var rappel = AURenderCallbackStruct(inputProc: { ref, drapeaux, horodatage, _, images, _ in
            Unmanaged<EntreeHAL>.fromOpaque(ref).takeUnretainedValue().lire(drapeaux, horodatage, images)
        }, inputProcRefCon: Unmanaged.passUnretained(self).toOpaque())
        guard AudioUnitSetProperty(u, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0, &rappel, UInt32(MemoryLayout<AURenderCallbackStruct>.size)) == noErr,
              AudioUnitInitialize(u) == noErr
        else { AudioComponentInstanceDispose(u); return nil }
        unite = u
        tamponRendu = AVAudioPCMBuffer(pcmFormat: f, frameCapacity: 8192)
    }

    deinit {
        if let u = unite { AudioOutputUnitStop(u); AudioUnitUninitialize(u); AudioComponentInstanceDispose(u) }
    }

    /// Démarre la lecture du micro ; `surTampon` reçoit chaque tampon (copie) sur une file ordinaire.
    func demarrer(surTampon: @escaping (AVAudioPCMBuffer) -> Void) throws {
        guard let u = unite else { throw NSError(domain: "Dictee", code: 3, userInfo: [NSLocalizedDescriptionKey: "micro direct indisponible"]) }
        self.surTampon = surTampon
        let s = AudioOutputUnitStart(u)
        guard s == noErr else { self.surTampon = nil; throw NSError(domain: "Dictee", code: Int(s), userInfo: [NSLocalizedDescriptionKey: "micro direct refusé (erreur \(s))"]) }
        enMarche = true
    }

    /// Arrête le micro : plus aucun tampon ne sera livré après le retour (les tampons déjà en route sont jetés).
    func arreter() {
        if let u = unite, enMarche { AudioOutputUnitStop(u) }
        enMarche = false
        livraison.sync { surTampon = nil }
    }

    /// Fil temps réel : rend les images dans le tampon réutilisable, en fait une copie, la livre ailleurs.
    private func lire(_ drapeaux: UnsafeMutablePointer<AudioUnitRenderActionFlags>, _ horodatage: UnsafePointer<AudioTimeStamp>, _ images: UInt32) -> OSStatus {
        guard let u = unite, let t = tamponRendu, images <= t.frameCapacity else { return noErr }
        t.frameLength = images
        let s = AudioUnitRender(u, drapeaux, horodatage, 1, images, t.mutableAudioBufferList)
        guard s == noErr, let copie = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: images),
              let src = t.floatChannelData, let dst = copie.floatChannelData else { return s }
        copie.frameLength = images
        dst[0].update(from: src[0], count: Int(images))
        livraison.async { [weak self] in self?.surTampon?(copie) }
        return noErr
    }
}
