import AppKit
import DicteeCore

/// Le programme d'aide « lecture en cours » (Resources/lecture) : lancé par /usr/bin/perl, il dit ce qui joue sur le Mac, ligne JSON par ligne
/// JSON, et exécute nos commandes (lecture, pause, suivant, position). Il ne fait rien tant que rien ne change : MediaRemote le réveille
/// par notification, aucune boucle de sondage.
///
/// Cycle de vie : lancé seulement si le réglage est actif, relancé s'il meurt (délai croissant, voir `PlanRelanceAide`), arrêté proprement
/// à la sortie de Verbe (fermeture de son entrée : il s'arrête de lui-même, puis `terminate`). Si MediaRemote devient inaccessible
/// (future version de macOS), la fonction se désactive en silence avec une ligne au journal.
@MainActor
final class LecteurSysteme {
    /// Un événement lu sur la sortie du programme d'aide (toujours sur le fil principal).
    var surEvenement: (EvenementLecture) -> Void = { _ in }
    /// Abandon définitif (MediaRemote inaccessible, ou trop d'arrêts de suite).
    var surAbandon: (String) -> Void = { _ in }

    private var processus: Process?
    private var entree: FileHandle?
    private var tampon = Data()
    private var plan = PlanRelanceAide()
    private var relance: DispatchWorkItem?
    private var lanceLe = Date()
    private var echecMediaRemote = false
    private(set) var actif = false

    /// Dossier des images de pochettes (supprimé avec le dossier de cache à la désinstallation).
    static let dossierImages: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/\(Desinstallation.identifiant)/lecture", isDirectory: true)

    /// Les deux fichiers du programme d'aide, dans les ressources de l'app (nil pendant un `swift run`, hors de l'app assemblée).
    static var fichiers: (lanceur: URL, module: URL)? {
        guard let dossier = Bundle.main.resourceURL?.appendingPathComponent("lecture", isDirectory: true) else { return nil }
        let l = dossier.appendingPathComponent("lanceur.pl"), m = dossier.appendingPathComponent("verbe-lecture.dylib")
        let fm = FileManager.default
        return fm.fileExists(atPath: l.path) && fm.fileExists(atPath: m.path) ? (l, m) : nil
    }

    func demarrer() {
        guard !actif else { return }
        actif = true
        plan = PlanRelanceAide()
        echecMediaRemote = false
        lancer()
    }

    func arreter() {
        guard actif else { return }
        actif = false
        relance?.cancel(); relance = nil
        liberer(terminer: true)
    }

    /// Mode d'essai : si défini, aucune commande ne part tant que la dernière app annoncée par le système n'est pas exactement celle-ci
    /// (la source de test) : une commande de lecture ne doit jamais atteindre le vrai lecteur de Hugues.
    var appExclusive: String?
    private var derniereApp: String?

    func envoyer(_ commande: CommandeLecture) {
        if let appExclusive, derniereApp != appExclusive { Log.ecrire("lecture : commande refusée (l'app élue n'est pas la source de test)"); return }
        guard let entree, processus?.isRunning == true else { return }
        try? entree.write(contentsOf: Data(AideLecture.ligne(commande).utf8))
    }

    // MARK: processus

    private func lancer() {
        guard actif, processus == nil else { return }
        guard let (lanceur, module) = Self.fichiers else {
            Log.ecrire("lecture : programme d'aide absent des ressources de l'app, fonction désactivée")
            actif = false; surAbandon("absent"); return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = [lanceur.path, module.path]
        var env = ProcessInfo.processInfo.environment
        env["VERBE_LECTURE_DIR"] = Self.dossierImages.path
        p.environment = env
        let sortie = Pipe(), erreur = Pipe(), entreePipe = Pipe()
        p.standardOutput = sortie; p.standardError = erreur; p.standardInput = entreePipe
        tampon = Data()
        sortie.fileHandleForReading.readabilityHandler = { [weak self] h in
            let donnees = h.availableData
            if donnees.isEmpty { h.readabilityHandler = nil; return }   // fin du flux : le processus s'est arrêté
            Task { @MainActor in self?.recevoir(donnees) }
        }
        erreur.fileHandleForReading.readabilityHandler = { h in
            if h.availableData.isEmpty { h.readabilityHandler = nil }   // jamais gardé : seul le code de sortie compte
        }
        p.terminationHandler = { [weak self] fini in
            Task { @MainActor in self?.processusArrete(fini) }
        }
        do {
            try p.run()
        } catch {
            Log.ecrire("lecture : lancement impossible (\(error.localizedDescription))")
            planifierRelance(apresArret: true)
            return
        }
        processus = p
        entree = entreePipe.fileHandleForWriting
        lanceLe = Date()
        Log.ecrire("lecture : programme d'aide lancé (pid \(p.processIdentifier))")
    }

    private func recevoir(_ donnees: Data) {
        tampon.append(donnees)
        while let fin = tampon.firstIndex(of: 0x0A) {
            let ligne = String(decoding: tampon[tampon.startIndex..<fin], as: UTF8.self)
            tampon.removeSubrange(tampon.startIndex...fin)
            guard let evenement = AideLecture.decoder(ligne) else { continue }
            if case .echec(let raison) = evenement { echecMediaRemote = true; Log.ecrire("lecture : programme d'aide en échec (\(raison))") }
            if case .pret = evenement { Log.ecrire("lecture : programme d'aide prêt") }
            switch evenement { case .etat(let m): derniereApp = m.app; case .rien: derniereApp = nil; default: break }
            surEvenement(evenement)
        }
        if tampon.count > 1_000_000 { tampon = Data() }
    }

    private func processusArrete(_ fini: Process) {
        guard fini === processus else { return }
        let code = fini.terminationStatus
        liberer(terminer: false)
        guard actif else { return }
        Log.ecrire("lecture : programme d'aide arrêté (code \(code))")
        planifierRelance(apresArret: true)
    }

    private func planifierRelance(apresArret: Bool) {
        let vie = Date().timeIntervalSince(lanceLe)
        switch plan.processusArrete(dureeDeVie: vie, echecMediaRemote: echecMediaRemote) {
        case .abandonner(let raison):
            Log.ecrire("lecture : fonction désactivée (\(raison))")
            actif = false
            surAbandon(raison)
        case .relancer(let apres):
            Log.ecrire("lecture : nouvel essai dans \(Int(apres)) s")
            let item = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.relance = nil; self?.lancer() } }
            relance = item
            DispatchQueue.main.asyncAfter(deadline: .now() + apres, execute: item)
        }
    }

    /// Ferme les tuyaux ; `terminer` demande aussi l'arrêt du processus (il s'arrête déjà tout seul quand son entrée se ferme).
    private func liberer(terminer: Bool) {
        let p = processus
        processus = nil
        try? entree?.close()
        entree = nil
        if let p {
            (p.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
            (p.standardError as? Pipe)?.fileHandleForReading.readabilityHandler = nil
            if terminer, p.isRunning { p.terminate() }
        }
    }
}
