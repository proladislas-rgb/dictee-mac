import AVFoundation

/// Le micro (AVAudioEngine). Le moteur est préparé dès le lancement ; il ne tourne (et le voyant orange
/// du micro ne s'allume) que pendant une dictée. Toutes les opérations passent par une file unique :
/// démarrer / arrêter ne peuvent jamais se croiser, même si l'appui est très court.
final class AudioCapture: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let file = DispatchQueue(label: "dictee.audio")
    private var pipeline: RecordingPipeline?
    private var enCours = false
    private var observateur: NSObjectProtocol?

    init() {
        observateur = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in
            self?.file.async { self?.reconfigurer() }
        }
    }

    /// À appeler au lancement quand le micro est autorisé : prépare le moteur pour un départ instantané.
    func preparer() {
        file.async { [self] in
            guard !enCours else { return }
            _ = engine.inputNode
            engine.prepare()
            Log.ecrire("micro : moteur préparé")
        }
    }

    /// Démarre la capture. `fini` est appelé (sur la file audio) avec le temps de démarrage en ms, ou une erreur.
    func demarrer(pipeline: RecordingPipeline, fini: @escaping (Result<Int, Error>) -> Void) {
        file.async { [self] in
            let debut = ProcessInfo.processInfo.systemUptime
            do {
                self.pipeline = pipeline
                try installerEtDemarrer()
                enCours = true
                fini(.success(Int((ProcessInfo.processInfo.systemUptime - debut) * 1000)))
            } catch {
                self.pipeline = nil
                fini(.failure(error))
            }
        }
    }

    /// Arrête la capture puis appelle `fini` (sur la file audio) : plus aucun tampon n'arrivera après.
    func arreter(fini: @escaping () -> Void) {
        file.async { [self] in
            if enCours {
                engine.inputNode.removeTap(onBus: 0)
                engine.stop()
                enCours = false
                engine.prepare()
            }
            pipeline = nil
            fini()
        }
    }

    // MARK: sur la file audio

    private func installerEtDemarrer() throws {
        let entree = engine.inputNode
        let format = entree.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(domain: "Dictee", code: 1, userInfo: [NSLocalizedDescriptionKey: "aucun micro disponible"])
        }
        let p = pipeline
        entree.installTap(onBus: 0, bufferSize: 2048, format: format) { tampon, _ in p?.traiter(tampon) }
        engine.prepare()
        try engine.start()
    }

    /// Le micro a changé (casque Bluetooth branché, etc.) : on reprend avec le nouveau format.
    private func reconfigurer() {
        guard enCours else { return }
        Log.ecrire("micro : configuration changée, redémarrage de la capture")
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        do { try installerEtDemarrer() }
        catch { Log.ecrire("micro : redémarrage impossible (\(error.localizedDescription))") }
    }
}
