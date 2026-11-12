import AVFoundation
import Speech
import CoreMedia
import DicteeCore

extension Notification.Name {
    /// La reconnaissance du Mac a changé d'état (prête, téléchargement de la langue en cours) : les Réglages et l'îlot relisent.
    static let verbeParole = Notification.Name("verbe.parole")
}

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

    enum Disponibilite: Equatable { case pret, enPreparation, telechargement(Int), indisponible(String) }
    /// Ce que les Réglages peuvent affirmer du secours Apple : seulement « prêt » une fois la préparation réussie ; pendant que macOS
    /// télécharge la langue, où il en est (en %).
    static var disponibilite: Disponibilite {
        switch etat {
        case .analyseur, .classique: return .pret
        case .enAttente: return progression.map { .telechargement(Int(($0 * 100).rounded(.down))) } ?? .enPreparation
        case .indisponible(let raison): return .indisponible(raison)
        }
    }
    /// Le téléchargement de la langue par macOS (0 à 1) ; nil s'il n'y en a pas en cours.
    nonisolated(unsafe) private static var progressionEnCours: Double?
    static var progression: Double? { lock.lock(); defer { lock.unlock() }; return progressionEnCours }
    private static func poserProgression(_ p: Double?) {
        lock.lock(); let change = progressionEnCours != p; progressionEnCours = p; lock.unlock()
        if change { DispatchQueue.main.async { NotificationCenter.default.post(name: .verbeParole, object: nil) } }
    }

    /// Les mots du lexique donnés à la reconnaissance du Mac (noms propres, mots de métier) : elle les reconnaît mieux. 100 au plus,
    /// relus toutes les 10 minutes (pas à chaque dictée).
    static func motsContexte(a t: Double = ProcessInfo.processInfo.systemUptime) -> [String] {
        lock.lock()
        if let c = motsEnCache, t - c.lus < 600 { lock.unlock(); return c.mots }
        lock.unlock()
        var vus = Set<String>()
        // le mot d'appel d'abord (« Voxile, rappelle-moi… » doit être reconnu en direct pour que l'îlot prenne la dictée)
        let tous = [MotAppel.mot] + Dictionnaire.mots() + LexiqueStore.partage.entrees().map(\.mot)
        let mots = Array(tous.filter { !$0.isEmpty && vus.insert($0.lowercased()).inserted }.prefix(100))
        lock.lock(); motsEnCache = (mots, t); lock.unlock()
        return mots
    }
    nonisolated(unsafe) private static var motsEnCache: (mots: [String], lus: Double)?

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
                    // la progression se lit pendant le téléchargement (Réglages, îlot), puis disparaît
                    poserProgression(0)
                    let suivi = Task {
                        while !Task.isCancelled {
                            poserProgression(demande.progress.fractionCompleted)
                            try? await Task.sleep(for: .milliseconds(500))
                        }
                    }
                    defer { suivi.cancel(); poserProgression(nil) }
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
            DispatchQueue.main.async { NotificationCenter.default.post(name: .verbeParole, object: nil) }
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

    /// Pour l'essai en ligne de commande (`--relais-essai`) : la reconnaissance du Mac seulement si la langue est DÉJÀ installée. Rien n'est
    /// téléchargé, aucune autorisation n'est demandée (le repli classique, qui en demande une, n'est jamais essayé ici).
    /// `reserver` : les langues du Mac sont réservées app par app (AssetInventory) ; un programme lancé depuis le Terminal n'a pas celle de
    /// Verbe. Avec `reserver`, l'essai réserve le français pour lui-même le temps de l'essai (macOS reprend la langue déjà sur le disque ;
    /// la progression s'affiche s'il doit la télécharger), puis `liberer()` rend la réservation.
    static func preparerSansDemander(reserver: Bool = false) async -> String? {
        let souhaitee = Locale(identifier: "fr-FR")
        guard SpeechTranscriber.isAvailable, let locale = await SpeechTranscriber.supportedLocale(equivalentTo: souhaitee) else { return "SpeechTranscriber indisponible" }
        let transcripteur = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [])
        var statut = await AssetInventory.status(forModules: [transcripteur])
        if statut != .installed, reserver {
            do {
                try await AssetInventory.reserve(locale: locale)
                if let demande = try await AssetInventory.assetInstallationRequest(supporting: [transcripteur]) {
                    let suivi = Task {
                        while !Task.isCancelled { print(String(format: "langue du Mac : %.0f %%", demande.progress.fractionCompleted * 100)); try? await Task.sleep(for: .seconds(1)) }
                    }
                    defer { suivi.cancel() }
                    try await demande.downloadAndInstall()
                }
                statut = await AssetInventory.status(forModules: [transcripteur])
            } catch { return "réservation de la langue impossible (\(error.localizedDescription))" }
        }
        guard statut == .installed else { return "langue \(locale.identifier) non installée pour ce programme (\(statut)) : relancer avec --reserver" }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcripteur]) else { return "format audio introuvable" }
        poser(.analyseur(format: format, locale: locale))
        return nil
    }
    /// Rend la réservation prise par l'essai.
    static func liberer() async {
        if case .analyseur(_, let locale) = etat { await AssetInventory.release(reservedLocale: locale) }
    }

    /// Une reconnaissance pour la dictée qui commence, ou `nil` si rien n'est prêt. `mots` : le lexique, pour mieux reconnaître les noms.
    static func creer(mots: [String] = []) -> (any ReconnaissanceDirecte)? {
        switch etat {
        case .analyseur(let format, let locale): return AnalyseurDirect(format: format, locale: locale, mots: mots)
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

    init(format: AVAudioFormat, locale: Locale, mots: [String] = []) {
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
            // les mots du lexique (noms, mots de métier) : la reconnaissance du Mac les préfère (AnalysisContext, macOS 26)
            if !mots.isEmpty {
                let contexte = AnalysisContext()
                contexte.contextualStrings[.general] = mots
                do { try await analyseur.setContext(contexte) }
                catch { Log.ecrire("parole : mots du lexique refusés (\(error.localizedDescription))") }
            }
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
