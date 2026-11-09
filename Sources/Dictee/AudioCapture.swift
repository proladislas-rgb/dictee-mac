import AVFoundation
import CoreAudio
import AudioToolbox
import DicteeCore
import VerbeObjC

enum MicroErreur: Error, LocalizedError {
    case aucunSon
    var errorDescription: String? { "aucun son reçu du micro" }
}

/// Le micro (AVAudioEngine). Un moteur est préparé dès le lancement, au micro choisi par `ChoixMicro`, et reconstruit dès que
/// le micro par défaut ou la liste des micros change (AirPods mis ou retirés…). Il ne tourne (et le voyant orange du micro ne
/// s'allume) que pendant une dictée. Toutes les opérations passent par une file unique : démarrer / arrêter ne peuvent jamais
/// se croiser, même si l'appui est très court.
///
/// Aucun format n'est gardé en mémoire : le tap est installé avec le format réel du micro lu à chaque démarrage, et la
/// conversion (RecordingPipeline) se refait d'après le premier tampon reçu.
/// Garde-fou : si aucun tampon n'arrive 0,8 s après l'appui, la cause est journalisée et le moteur est reconstruit une fois ;
/// si rien n'arrive 0,9 s plus tard, la dictée est abandonnée (`MicroErreur.aucunSon`) : l'app ne reste jamais bloquée.
final class AudioCapture: @unchecked Sendable {
    private var engine = AVAudioEngine()
    private let file = DispatchQueue(label: "dictee.audio")
    private let surveillance = DispatchQueue(label: "dictee.audio.surveillance")
    private var pipeline: RecordingPipeline?
    private var enCours = false
    private var observateur: NSObjectProtocol?
    private var decisionDuMoteur: DecisionMicro?
    private var reglageDuMoteur: String?
    private var moteurPerime = true
    private var ecouteursInstalles = false

    /// Une demande de démarrage en attente de son premier tampon. Protégé par `verrou`.
    private final class Demarrage {
        let jeton = UUID()
        let debut = ProcessInfo.processInfo.systemUptime
        var fini: ((Result<Int, Error>) -> Void)?
        var recu = false
        var termine = false
        init(fini: @escaping (Result<Int, Error>) -> Void) { self.fini = fini }
    }
    private let verrou = NSLock()
    private var demarrage: Demarrage?

    // MARK: préparation

    /// À appeler au lancement quand le micro est autorisé : prépare le moteur pour un départ instantané.
    func preparer() {
        file.async { [self] in
            installerEcouteurs()
            guard !enCours else { return }
            construireMoteur(motif: "préparation")
        }
    }

    /// Démarre la capture. `fini` est appelé une seule fois : au premier tampon reçu (`.success`, avec le délai en ms depuis l'appel),
    /// ou `.failure` si le moteur n'a pas pu démarrer ou si aucun son n'est arrivé après une nouvelle tentative.
    func demarrer(pipeline: RecordingPipeline, fini: @escaping (Result<Int, Error>) -> Void) {
        let d = Demarrage(fini: fini)
        verrou.lock(); demarrage = d; verrou.unlock()
        pipeline.surPremierTampon = { [weak self, weak d] format in
            guard let self, let d else { return }
            self.premierTampon(d, format: format)
        }
        file.async { [self] in
            self.pipeline = pipeline
            if moteurPerime || reglageDuMoteur != Settings.micro { construireMoteur(motif: "le micro a changé") }
            tenter(d, essai: 1)
        }
        surveillance.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.verifier(d, essai: 1) }
    }

    /// Arrête la capture puis appelle `fini` (sur la file audio) : plus aucun tampon n'arrivera après.
    func arreter(fini: @escaping () -> Void) {
        verrou.lock(); demarrage?.termine = true; demarrage = nil; verrou.unlock()
        file.async { [self] in
            arreterMoteur()
            pipeline = nil
            fini()
        }
    }

    // MARK: démarrage et surveillance

    /// Sur la file audio.
    private func tenter(_ d: Demarrage, essai: Int) {
        let debut = ProcessInfo.processInfo.systemUptime
        do {
            try installerEtDemarrer()
            enCours = true
            Log.ecrire("micro : moteur démarré en \(Int((ProcessInfo.processInfo.systemUptime - debut) * 1000)) ms (essai \(essai))")
        } catch {
            Log.ecrire("micro : démarrage impossible à l'essai \(essai) (\(error.localizedDescription))")
            enCours = false
            if essai == 1 {
                construireMoteur(motif: "nouvel essai après échec")
                tenter(d, essai: 2)
            } else {
                echouer(d, MicroErreur.aucunSon, cause: error)
            }
        }
    }

    private func premierTampon(_ d: Demarrage, format: AVAudioFormat) {
        verrou.lock()
        guard !d.recu, !d.termine else { verrou.unlock(); return }
        d.recu = true
        let fini = d.fini; d.fini = nil
        verrou.unlock()
        let ms = Int((ProcessInfo.processInfo.systemUptime - d.debut) * 1000)
        Log.ecrire("micro : premier son reçu après \(ms) ms, format réel \(Int(format.sampleRate)) Hz, \(format.channelCount) canal")
        fini?(.success(ms))
    }

    /// Sur la file de surveillance : aucun tampon 0,8 s après l'appui ?
    private func verifier(_ d: Demarrage, essai: Int) {
        verrou.lock()
        let attend = !d.recu && !d.termine
        verrou.unlock()
        guard attend else { return }
        if essai == 1 {
            Log.ecrire("micro : aucun son reçu 800 ms après l'appui (\(description())) -> moteur reconstruit, nouvel essai")
            file.async { [self] in
                arreterMoteur()
                construireMoteur(motif: "aucun son après 800 ms")
                tenter(d, essai: 2)
            }
            surveillance.asyncAfter(deadline: .now() + 0.9) { [weak self] in self?.verifier(d, essai: 2) }
        } else {
            echouer(d, MicroErreur.aucunSon, cause: nil)
        }
    }

    /// Abandon : le moteur est arrêté, l'appelant est prévenu (une seule fois).
    private func echouer(_ d: Demarrage, _ erreur: Error, cause: Error?) {
        verrou.lock()
        guard !d.recu, !d.termine, let fini = d.fini else { verrou.unlock(); return }
        d.termine = true; d.fini = nil
        verrou.unlock()
        Log.ecrire("micro : abandon, aucun son même après un nouvel essai (\(description()))\(cause.map { ", dernière erreur : \($0.localizedDescription)" } ?? "")")
        file.async { [self] in arreterMoteur(); pipeline = nil }
        fini(.failure(erreur))
    }

    // MARK: moteur (toujours sur la file audio)

    /// Un moteur neuf, relié au micro que `ChoixMicro` désigne. Remplace l'ancien : aucun format n'est conservé.
    private func construireMoteur(motif: String) {
        if let o = observateur { NotificationCenter.default.removeObserver(o); observateur = nil }
        if enCours { engine.inputNode.removeTap(onBus: 0); engine.stop(); enCours = false }
        let neuf = AVAudioEngine()
        engine = neuf
        observateur = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: neuf, queue: nil) { [weak self] _ in
            self?.file.async { self?.reconfigurer() }
        }
        let decision = Self.decider()
        decisionDuMoteur = decision
        reglageDuMoteur = Settings.micro
        moteurPerime = false
        if case .impose(let p, _) = decision, let unite = neuf.inputNode.audioUnit, var id = Self.identifiant(uid: p.uid) {
            let statut = AudioUnitSetProperty(unite, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &id, UInt32(MemoryLayout<AudioDeviceID>.size))
            if statut != noErr { Log.ecrire("micro : impossible d'imposer « \(p.nom) » (erreur \(statut)), micro du système utilisé") }
        }
        // -[AVAudioEngine prepare] peut lever une exception Objective-C (graphe invalide, micro imposé incompatible…) :
        // rattrapée ici ; on repart alors sur un moteur neuf au micro du système, sans préparation anticipée.
        // Le nœud d'entrée doit exister dans le graphe avant `prepare()` (sinon : « inputNode != nullptr || outputNode != nullptr »).
        _ = neuf.inputNode
        if let raison = VerbeEssayer({ neuf.prepare() }) {
            Log.ecrire("micro : préparation refusée par macOS (\(raison)) ; moteur neuf au micro du système")
            if let o = observateur { NotificationCenter.default.removeObserver(o); observateur = nil }
            let secours = AVAudioEngine()
            engine = secours
            observateur = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: secours, queue: nil) { [weak self] _ in
                self?.file.async { self?.reconfigurer() }
            }
            decisionDuMoteur = .systeme(raison: "secours après refus de préparation")
            _ = secours.inputNode
        }
        Log.ecrire("micro : moteur construit (\(motif)) ; \(decisionDuMoteur?.raison ?? decision.raison) ; \(description())")
    }

    private func installerEtDemarrer() throws {
        let entree = engine.inputNode
        let format = entree.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(domain: "Dictee", code: 1, userInfo: [NSLocalizedDescriptionKey: "aucun micro disponible"])
        }
        let p = pipeline
        entree.removeTap(onBus: 0)
        // format nil : le tap prend le format réel du micro à cet instant (jamais un format gardé d'avant)
        var erreurDemarrage: Error?
        if let raison = VerbeEssayer({
            entree.installTap(onBus: 0, bufferSize: 2048, format: nil) { tampon, _ in p?.traiter(tampon) }
            engine.prepare()
            do { try engine.start() } catch { erreurDemarrage = error }
        }) {
            entree.removeTap(onBus: 0)
            throw NSError(domain: "Dictee", code: 2, userInfo: [NSLocalizedDescriptionKey: "micro refusé par macOS (\(raison))"])
        }
        if let erreurDemarrage { throw erreurDemarrage }
    }

    private func arreterMoteur() {
        if enCours {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            enCours = false
            if let raison = VerbeEssayer({ self.engine.prepare() }) { Log.ecrire("micro : préparation après arrêt refusée (\(raison))") }
        }
    }

    /// Le micro a changé pendant la dictée (casque branché…) : on repart avec le nouveau micro et son format.
    private func reconfigurer() {
        guard enCours else { moteurPerime = true; return }
        Log.ecrire("micro : configuration changée pendant la dictée, redémarrage de la capture")
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        enCours = false
        construireMoteur(motif: "configuration changée")
        do { try installerEtDemarrer(); enCours = true }
        catch { Log.ecrire("micro : redémarrage impossible (\(error.localizedDescription))") }
    }

    /// Où en est le micro, pour le journal : périphérique choisi et format du moteur.
    private func description() -> String {
        var morceaux: [String] = []
        switch decisionDuMoteur {
        case .impose(let p, _)?: morceaux.append("micro imposé « \(p.nom) »")
        default: if let d = Self.peripheriqueParDefaut() { morceaux.append("micro du système « \(d.nom) » (\(Self.nomTransport(d.transport)))") }
        }
        let f = engine.inputNode.outputFormat(forBus: 0)
        morceaux.append("format du moteur \(Int(f.sampleRate)) Hz, \(f.channelCount) canal, moteur \(engine.isRunning ? "en marche" : "arrêté")")
        return morceaux.joined(separator: ", ")
    }

    // MARK: CoreAudio

    private static func nomTransport(_ t: TransportMicro) -> String {
        switch t { case .integre: return "intégré"; case .bluetooth: return "Bluetooth"; case .usb: return "USB"; case .autre: return "autre" }
    }

    private func installerEcouteurs() {
        guard !ecouteursInstalles else { return }
        ecouteursInstalles = true
        for selecteur in [kAudioHardwarePropertyDefaultInputDevice, kAudioHardwarePropertyDevices] {
            var adresse = AudioObjectPropertyAddress(mSelector: selecteur, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &adresse, file) { [weak self] _, _ in
                guard let self else { return }
                self.moteurPerime = true
                Log.ecrire("micro : le micro par défaut ou la liste des micros a changé (\(Self.peripheriqueParDefaut()?.nom ?? "aucun"))")
                if !self.enCours { self.construireMoteur(motif: "changement de micro") }
            }
        }
    }

    private static func decider() -> DecisionMicro {
        ChoixMicro.decider(reglage: Settings.micro, peripheriques: peripheriquesEntree(), defautUID: peripheriqueParDefaut()?.uid)
    }

    private static func propriete<T: BitwiseCopyable>(_ id: AudioObjectID, _ selecteur: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, valeur: inout T) -> Bool {
        var adresse = AudioObjectPropertyAddress(mSelector: selecteur, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var taille = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(id, &adresse, 0, nil, &taille, &valeur) == noErr
    }

    private static func texte(_ id: AudioObjectID, _ selecteur: AudioObjectPropertySelector) -> String? {
        var adresse = AudioObjectPropertyAddress(mSelector: selecteur, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var ref: Unmanaged<CFString>?
        var taille = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &adresse, 0, nil, &taille, &ref) == noErr, let ref else { return nil }
        return ref.takeRetainedValue() as String
    }

    private static func aUneEntree(_ id: AudioObjectID) -> Bool {
        var adresse = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration, mScope: kAudioObjectPropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        var taille: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &adresse, 0, nil, &taille) == noErr, taille > 0 else { return false }
        let brut = UnsafeMutableRawPointer.allocate(byteCount: Int(taille), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { brut.deallocate() }
        guard AudioObjectGetPropertyData(id, &adresse, 0, nil, &taille, brut) == noErr else { return false }
        let liste = UnsafeMutableAudioBufferListPointer(brut.assumingMemoryBound(to: AudioBufferList.self))
        return liste.contains { $0.mNumberChannels > 0 }
    }

    private static func peripherique(_ id: AudioObjectID) -> PeripheriqueEntree? {
        guard let uid = texte(id, kAudioDevicePropertyDeviceUID) else { return nil }
        var transport: UInt32 = 0
        _ = propriete(id, kAudioDevicePropertyTransportType, valeur: &transport)
        let t: TransportMicro
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn: t = .integre
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: t = .bluetooth
        case kAudioDeviceTransportTypeUSB: t = .usb
        default: t = .autre
        }
        return PeripheriqueEntree(uid: uid, nom: texte(id, kAudioObjectPropertyName) ?? uid, transport: t)
    }

    /// Tous les périphériques qui ont une entrée audio.
    static func peripheriquesEntree() -> [PeripheriqueEntree] {
        var adresse = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var taille: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &adresse, 0, nil, &taille) == noErr, taille > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(taille) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &adresse, 0, nil, &taille, &ids) == noErr else { return [] }
        return ids.filter(aUneEntree).compactMap(peripherique)
    }

    static func peripheriqueParDefaut() -> PeripheriqueEntree? {
        var id = AudioObjectID(0)
        guard propriete(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultInputDevice, valeur: &id), id != 0 else { return nil }
        return peripherique(id)
    }

    /// Identifiant CoreAudio d'un micro d'après son UID, s'il est branché.
    static func identifiant(uid: String) -> AudioDeviceID? {
        var adresse = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var id = AudioDeviceID(0)
        var taille = UInt32(MemoryLayout<AudioDeviceID>.size)
        var cle = uid as CFString
        let statut = withUnsafeMutablePointer(to: &cle) { pointeur in
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &adresse, UInt32(MemoryLayout<CFString>.size), pointeur, &taille, &id)
        }
        return statut == noErr && id != 0 ? id : nil
    }
}
