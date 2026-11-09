import AVFoundation
import CoreAudio
import AudioToolbox
import DicteeCore
import VerbeObjC

/// Le micro de la réunion : un moteur audio à lui, séparé de celui de la dictée (touche fn). Les deux peuvent tourner en même temps :
/// dicter pendant une réunion reste possible, sans rien casser (la dictée garde son moteur, son garde-fou et ses réglages).
/// Même choix de micro que la dictée (`ChoixMicro` : le micro du Mac quand un casque Bluetooth est le micro par défaut).
/// Tout appel AVAudioEngine passe par `VerbeEssayer` : une exception d'AVFoundation ne doit jamais arrêter l'app.
final class MicroReunion: @unchecked Sendable {
    enum Erreur: Error, LocalizedError {
        case indisponible(String)
        var errorDescription: String? { if case .indisponible(let m) = self { return m }; return nil }
    }

    private let file = DispatchQueue(label: "dictee.reunion.micro")
    private var engine: AVAudioEngine?
    private var observateur: NSObjectProtocol?
    private var surTampon: ((AVAudioPCMBuffer) -> Void)?
    private var enMarche = false
    private var reconstructions = 0

    /// Démarre l'écoute du micro. Rend la main une fois le moteur lancé (ou en erreur).
    func demarrer(surTampon: @escaping (AVAudioPCMBuffer) -> Void) throws {
        self.surTampon = surTampon
        try file.sync { try lancer() }
    }

    func arreter() {
        file.sync {
            enMarche = false
            if let o = observateur { NotificationCenter.default.removeObserver(o); observateur = nil }
            if let e = engine {
                _ = VerbeEssayer { e.inputNode.removeTap(onBus: 0); e.stop() }
            }
            engine = nil
            surTampon = nil
        }
    }

    // MARK: sur la file

    private func lancer() throws {
        let neuf = AVAudioEngine()
        engine = neuf
        let decision = ChoixMicro.decider(reglage: Settings.micro, peripheriques: AudioCapture.peripheriquesEntree(), defautUID: AudioCapture.peripheriqueParDefaut()?.uid)
        _ = neuf.inputNode   // le nœud d'entrée doit exister avant `prepare()`
        if case .impose(let p, _) = decision, let unite = neuf.inputNode.audioUnit, var id = AudioCapture.identifiant(uid: p.uid) {
            let statut = AudioUnitSetProperty(unite, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &id, UInt32(MemoryLayout<AudioDeviceID>.size))
            if statut != noErr { Log.ecrire("réunion : impossible d'imposer le micro « \(p.nom) » (erreur \(statut)), micro du système utilisé") }
        }
        let entree = neuf.inputNode
        let format = entree.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw Erreur.indisponible("aucun micro disponible") }
        var erreurDemarrage: Error?
        let sortie = surTampon
        if let raison = VerbeEssayer({
            entree.installTap(onBus: 0, bufferSize: 4096, format: nil) { tampon, _ in sortie?(tampon) }
            neuf.prepare()
            do { try neuf.start() } catch { erreurDemarrage = error }
        }) {
            _ = VerbeEssayer { entree.removeTap(onBus: 0) }
            throw Erreur.indisponible("micro refusé par macOS (\(raison))")
        }
        if let erreurDemarrage { throw erreurDemarrage }
        enMarche = true
        observateur = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: neuf, queue: nil) { [weak self] _ in
            self?.file.async { self?.reconstruire() }
        }
        Log.ecrire("réunion : micro démarré (\(decision.raison) ; \(Int(format.sampleRate)) Hz, \(format.channelCount) canal)")
    }

    /// Le micro a changé en cours de réunion (casque branché…) : on repart avec le nouveau, quelques fois au plus.
    private func reconstruire() {
        guard enMarche, reconstructions < 5 else { return }
        reconstructions += 1
        Log.ecrire("réunion : configuration du micro changée, redémarrage (\(reconstructions))")
        if let o = observateur { NotificationCenter.default.removeObserver(o); observateur = nil }
        if let e = engine { _ = VerbeEssayer { e.inputNode.removeTap(onBus: 0); e.stop() } }
        do { try lancer() } catch { Log.ecrire("réunion : redémarrage du micro impossible (\(error.localizedDescription))") }
    }
}
