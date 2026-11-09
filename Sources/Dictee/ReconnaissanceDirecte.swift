import AVFoundation
import Speech
import CoreMedia

/// Texte en direct (pour l'encoche) et texte de secours si Groq ne répond pas : reconnaissance d'Apple,
/// toujours faite sur l'appareil. Le texte collé est celui de Groq ; celui-ci ne sert qu'à l'affichage et au secours.
protocol ReconnaissanceDirecte: AnyObject {
    /// Texte courant (mots sûrs + mots provisoires), appelé sur un fil quelconque.
    var surTexte: (@Sendable (String) -> Void)? { get set }
    /// Reçoit un tampon du micro (fil audio : rendre la main vite, et copier ce qu'on garde).
    func alimenter(_ tampon: AVAudioPCMBuffer)
    /// Termine et renvoie le texte final (vide si rien).
    func terminer() async -> String
    func annuler()
}

/// Prépare une fois, au lancement, ce qui est lent : téléchargement éventuel du modèle de langue du Mac
/// (géré par le système) et format audio attendu. Une dictée ne fait que consommer ce qui est prêt.
enum PrechauffageParole {
    enum Mode {
        case enAttente
        case analyseur(format: AVAudioFormat, locale: Locale)
        case classique
        case indisponible(String)
    }
    nonisolated(unsafe) private(set) static var mode: Mode = .enAttente
    private static let lock = NSLock()

    static var etat: Mode { lock.lock(); defer { lock.unlock() }; return mode }
    private static func poser(_ m: Mode) { lock.lock(); mode = m; lock.unlock() }

    static func lancer() async {
        let souhaitee = Locale(identifier: "fr-FR")
        guard SpeechTranscriber.isAvailable,
              let locale = await SpeechTranscriber.supportedLocale(equivalentTo: souhaitee) else {
            Log.ecrire("parole : SpeechTranscriber indisponible, repli sur la reconnaissance classique")
            await preparerClassique()
            return
        }
        let transcripteur = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [])
        do {
            var statut = await AssetInventory.status(forModules: [transcripteur])
            if statut != .installed {
                Log.ecrire("parole : modèle de langue « \(locale.identifier) » pas encore installé (\(statut)), demande d'installation au système")
                if let demande = try await AssetInventory.assetInstallationRequest(supporting: [transcripteur]) {
                    try await demande.downloadAndInstall()
                }
                statut = await AssetInventory.status(forModules: [transcripteur])
            }
            guard statut == .installed else {
                Log.ecrire("parole : modèle de langue non installé (\(statut)), repli sur la reconnaissance classique")
                await preparerClassique()
                return
            }
            guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcripteur]) else {
                Log.ecrire("parole : format audio introuvable, repli sur la reconnaissance classique")
                await preparerClassique()
                return
            }
            poser(.analyseur(format: format, locale: locale))
            Log.ecrire("parole : prête (SpeechAnalyzer, \(locale.identifier), \(Int(format.sampleRate)) Hz)")
        } catch {
            Log.ecrire("parole : préparation impossible (\(error.localizedDescription)), repli sur la reconnaissance classique")
            await preparerClassique()
        }
    }

    private static func preparerClassique() async {
        guard let rec = SFSpeechRecognizer(locale: Locale(identifier: "fr-FR")), rec.supportsOnDeviceRecognition else {
            poser(.indisponible("reconnaissance sur l'appareil indisponible en français"))
            Log.ecrire("parole : aucune reconnaissance sur l'appareil disponible, pas de texte en direct ni de secours")
            return
        }
        let statut = SFSpeechRecognizer.authorizationStatus()
        if statut == .notDetermined {
            let nouveau: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { c in
                SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
            }
            Log.ecrire("parole : autorisation de reconnaissance vocale = \(nouveau.rawValue)")
            poser(nouveau == .authorized ? .classique : .indisponible("reconnaissance vocale refusée"))
        } else {
            poser(statut == .authorized ? .classique : .indisponible("reconnaissance vocale refusée"))
        }
    }

    /// Une reconnaissance pour la dictée qui commence, ou `nil` si rien n'est prêt.
    static func creer() -> (any ReconnaissanceDirecte)? {
        switch etat {
        case .analyseur(let format, let locale): return AnalyseurDirect(format: format, locale: locale)
        case .classique: return ClassiqueDirect()
        case .enAttente, .indisponible: return nil
        }
    }
}

// MARK: SpeechAnalyzer (macOS 26)

final class AnalyseurDirect: ReconnaissanceDirecte, @unchecked Sendable {
    var surTexte: (@Sendable (String) -> Void)?

    private let format: AVAudioFormat
    private let transcripteur: SpeechTranscriber
    private let analyseur: SpeechAnalyzer
    private let flux: AsyncStream<AnalyzerInput>
    private let entree: AsyncStream<AnalyzerInput>.Continuation
    private var convertisseur: AVAudioConverter?
    private var formatSource: AVAudioFormat?
    private let lock = NSLock()
    private var texteFinal = ""
    private var texteProvisoire = ""
    private var tache: Task<Void, Never>?
    private var resultats: Task<Void, Never>?

    init(format: AVAudioFormat, locale: Locale) {
        self.format = format
        transcripteur = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [])
        analyseur = SpeechAnalyzer(modules: [transcripteur])
        (flux, entree) = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .unbounded)

        resultats = Task { [weak self, transcripteur] in
            do {
                for try await r in transcripteur.results {
                    guard let self else { return }
                    self.recevoir(texte: String(r.text.characters), final: r.isFinal)
                }
            } catch {
                Log.ecrire("parole : erreur des résultats (\(error.localizedDescription))")
            }
        }
        tache = Task { [analyseur, flux] in
            do { try await analyseur.start(inputSequence: flux) }
            catch { Log.ecrire("parole : démarrage de l'analyse impossible (\(error.localizedDescription))") }
        }
    }

    private func recevoir(texte: String, final: Bool) {
        lock.lock()
        if final {
            texteFinal += (texteFinal.isEmpty || texte.hasPrefix(" ") ? "" : " ") + texte
            texteProvisoire = ""
        } else {
            texteProvisoire = texte
        }
        let courant = (texteFinal + (texteProvisoire.isEmpty ? "" : (texteFinal.isEmpty || texteProvisoire.hasPrefix(" ") ? "" : " ") + texteProvisoire))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        lock.unlock()
        surTexte?(courant)
    }

    func alimenter(_ tampon: AVAudioPCMBuffer) {
        if convertisseur == nil || formatSource != tampon.format {
            convertisseur = AVAudioConverter(from: tampon.format, to: format)
            formatSource = tampon.format
        }
        guard let conv = convertisseur else { return }
        let capacite = AVAudioFrameCount(Double(tampon.frameLength) * format.sampleRate / tampon.format.sampleRate + 64)
        guard let sortie = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacite) else { return }
        var fourni = false
        var erreur: NSError?
        let etat = conv.convert(to: sortie, error: &erreur) { _, statut in
            if fourni { statut.pointee = .noDataNow; return nil }
            fourni = true; statut.pointee = .haveData; return tampon
        }
        guard etat != .error, sortie.frameLength > 0 else { return }
        entree.yield(AnalyzerInput(buffer: sortie))
    }

    func terminer() async -> String {
        entree.finish()
        do { try await analyseur.finalizeAndFinishThroughEndOfInput() }
        catch { Log.ecrire("parole : finalisation impossible (\(error.localizedDescription))") }
        // laisse arriver le dernier résultat
        _ = await resultats?.value
        return texteComplet()
    }

    private func texteComplet() -> String {
        lock.lock(); defer { lock.unlock() }
        return (texteFinal + (texteProvisoire.isEmpty ? "" : " " + texteProvisoire)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func annuler() {
        entree.finish()
        Task { [analyseur] in await analyseur.cancelAndFinishNow() }
        resultats?.cancel()
    }
}

// MARK: reconnaissance classique (repli), sur l'appareil

final class ClassiqueDirect: ReconnaissanceDirecte, @unchecked Sendable {
    var surTexte: (@Sendable (String) -> Void)?

    private let reconnaisseur = SFSpeechRecognizer(locale: Locale(identifier: "fr-FR"))
    private let requete = SFSpeechAudioBufferRecognitionRequest()
    private var tache: SFSpeechRecognitionTask?
    private let lock = NSLock()
    private var dernier = ""
    private var continuation: CheckedContinuation<String, Never>?
    private var fini = false

    init() {
        requete.requiresOnDeviceRecognition = true
        requete.shouldReportPartialResults = true
        tache = reconnaisseur?.recognitionTask(with: requete) { [weak self] resultat, erreur in
            guard let self else { return }
            if let resultat {
                let t = resultat.bestTranscription.formattedString
                self.lock.lock(); self.dernier = t; self.lock.unlock()
                self.surTexte?(t)
                if resultat.isFinal { self.terminerAttente() }
            } else if erreur != nil {
                self.terminerAttente()
            }
        }
    }

    private func terminerAttente() {
        lock.lock()
        fini = true
        let c = continuation; continuation = nil
        let t = dernier
        lock.unlock()
        c?.resume(returning: t)
    }

    func alimenter(_ tampon: AVAudioPCMBuffer) {
        // append copie les données : le tampon du micro peut être réutilisé après l'appel
        requete.append(tampon)
    }

    func terminer() async -> String {
        requete.endAudio()
        return await withCheckedContinuation { (c: CheckedContinuation<String, Never>) in
            lock.lock()
            if fini { let t = dernier; lock.unlock(); c.resume(returning: t); return }
            continuation = c
            lock.unlock()
            // garde-fou : on n'attend pas plus de 1,5 s le résultat final
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.terminerAttente() }
        }
    }

    func annuler() {
        requete.endAudio()
        tache?.cancel()
    }
}
