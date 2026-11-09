import AppKit
import DicteeCore

/// Version de l'app qui tourne (Info.plist) ; « 0.0.0 » pour un binaire lancé hors d'une app (modes de test).
enum VersionDeLApp {
    static var texte: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0" }
}

/// Ce que montrent les Réglages et la ligne sous l'encoche : une seule source pour les deux.
@MainActor
final class MiseAJourModele: ObservableObject {
    enum Activite: Equatable {
        case repos
        case verification
        case telechargement(Double)
        case controle
        case installation
        case attenteRedemarrage
    }

    @Published var activite: Activite = .repos
    /// La version plus récente trouvée sur GitHub (jusqu'à ce qu'elle soit installée).
    @Published var disponible: PropositionMiseAJour?
    /// Dernière vérification qui a abouti.
    @Published var verifieeLe: Date?
    /// Phrase sobre du dernier échec d'une recherche demandée à la main.
    @Published var message: String?
    /// Phrase sobre quand l'installation n'a pas abouti (« Rien n'a été changé »).
    @Published var echecInstallation: String?
    /// Pourquoi cette app ne peut pas se remplacer elle-même (lancée depuis l'image disque, dossier en lecture seule…).
    @Published var refusInstallation: String?
    @Published var automatique: Bool { didSet { if installe { Settings.verifierLesMisesAJour = automatique } } }
    let versionActuelle: String
    private var installe = false

    var surRechercher: () -> Void = {}
    var surInstaller: () -> Void = {}
    var surNouveautes: () -> Void = {}

    init(versionActuelle: String = VersionDeLApp.texte, automatique: Bool = Settings.verifierLesMisesAJour) {
        self.versionActuelle = versionActuelle
        self.automatique = automatique
        installe = true
    }

    var occupe: Bool { activite != .repos }
    var peutRechercher: Bool { activite == .repos }
    var peutInstaller: Bool { disponible != nil && activite == .repos && refusInstallation == nil }

    /// Ce que dit la ligne sous l'encoche (nil : rien à montrer).
    enum Presentation: Equatable {
        case proposition(String)
        case progression(String)
        case echec(String)
    }
    var presentation: Presentation? {
        switch activite {
        case .telechargement(let x): return .progression("Téléchargement de Verbe \(disponible?.version.description ?? "")… \(Int((x * 100).rounded())) %")
        case .controle: return .progression("Vérification du fichier…")
        case .installation: return .progression("Installation de Verbe \(disponible?.version.description ?? "")…")
        case .attenteRedemarrage: return .progression("Verbe est à jour. Il se relance…")
        case .verification: return nil
        case .repos:
            if let echecInstallation { return .echec(echecInstallation) }
            if let d = disponible { return .proposition(d.version.description) }
            return nil
        }
    }

    /// Exemples pour les rendus PNG : aucun accès au réseau ni aux réglages de l'utilisateur.
    static func exemple(_ activite: Activite = .repos, disponible: String? = nil, verifieeLe: Date? = Date(), refus: String? = nil,
                        message: String? = nil, echec: String? = nil, automatique: Bool = true) -> MiseAJourModele {
        let m = MiseAJourModele(versionActuelle: "0.3.0", automatique: automatique)
        m.installe = false
        m.activite = activite
        m.verifieeLe = verifieeLe
        m.refusInstallation = refus
        m.message = message
        m.echecInstallation = echec
        if let disponible, let v = VersionApp(disponible) {
            m.disponible = PropositionMiseAJour(version: v, notes: "# Verbe \(disponible)\n\n## Ce qui change\n- **Mise à jour automatique** : Verbe cherche seul une nouvelle version.\n- Un correctif sur le collage dans Terminal.",
                                                pageURL: nil, dmgURL: URL(string: "https://github.com/proladislas-rgb/dictee-mac/releases/download/v\(disponible)/Verbe-\(disponible).dmg")!,
                                                taille: 1_500_000, empreinteJSON: nil, empreinteURL: nil)
        }
        return m
    }
}

/// Le chef d'orchestre : quand vérifier, quand proposer, installer, relancer. Un seul exemplaire dans l'app.
@MainActor
final class MiseAJourControleur {
    static let partage = MiseAJourControleur()

    let modele = MiseAJourModele()
    let bande = MiseAJourPanneau()
    let notes = NotesDeVersionFenetre()
    /// Rempli par l'AppDelegate : ce qui occupe l'encoche en ce moment (dictée, réunion, autre annonce).
    var contexte: () -> ContexteAffichage = { ContexteAffichage() }
    private let versionActuelle = VersionApp(VersionDeLApp.texte) ?? VersionApp("0.0.0")!
    private var releve: Timer?
    private var surveillance: Timer?
    private var enCours: Task<Void, Never>?

    init() {
        modele.verifieeLe = Settings.miseAJourDerniereReussite
        modele.surRechercher = { [weak self] in self?.rechercher(manuel: true) }
        modele.surInstaller = { [weak self] in self?.installer() }
        modele.surNouveautes = { [weak self] in self?.montrerLesNotes() }
        bande.surInstaller = { [weak self] in self?.installer() }
        bande.surPlusTard = { [weak self] in self?.plusTard() }
        bande.surNouveautes = { [weak self] in self?.montrerLesNotes() }
        bande.surFermer = { [weak self] in self?.fermerLEchec() }
        bande.surDelaiEcoule = { [weak self] in
            Log.ecrire("mise à jour : proposition restée sans réponse, rappel demain")
            self?.plusTard()
        }
        notes.surInstaller = { [weak self] in self?.installer() }
    }

    // MARK: démarrage et vérification

    /// Au lancement : première vérification 30 s après, puis relevé toutes les 10 minutes (la règle décide si 24 h se sont écoulées).
    func demarrer() {
        evaluerEmplacement()
        if let installee = Settings.miseAJourInstallee {
            Settings.miseAJourInstallee = nil
            Log.ecrire("mise à jour : installée, Verbe \(VersionDeLApp.texte) tourne (version attendue \(installee))")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + PlanVerification.delaiAuLancement) { [weak self] in self?.verifierSiNecessaire() }
        let t = Timer(timeInterval: PlanVerification.periodeDeReleve, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.verifierSiNecessaire() }
        }
        RunLoop.main.add(t, forMode: .common)
        releve = t
    }

    private func verifierSiNecessaire() {
        guard PlanVerification.doitVerifierSeul(automatique: modele.automatique, derniereReussite: Settings.miseAJourDerniereReussite,
                                                derniereTentative: Settings.miseAJourDerniereTentative, pasAvant: Settings.miseAJourPasAvant, maintenant: Date()) else { return }
        rechercher(manuel: false)
    }

    private func evaluerEmplacement() {
        if case .refuse(let raison) = InstallateurMiseAJour(client: ClientMiseAJour(versionActuelle: versionActuelle)).verdictEmplacement(Bundle.main.bundleURL) {
            modele.refusInstallation = raison
        } else {
            modele.refusInstallation = nil
        }
    }

    func rechercher(manuel: Bool) {
        guard modele.activite == .repos, enCours == nil else { return }
        let maintenant = Date()
        if manuel, !PlanVerification.demandePermise(derniereTentative: Settings.miseAJourDerniereTentative, pasAvant: Settings.miseAJourPasAvant, maintenant: maintenant) {
            modele.message = "Patiente quelques instants avant de relancer la recherche."
            return
        }
        Settings.miseAJourDerniereTentative = maintenant
        if manuel { modele.message = nil; modele.activite = .verification }
        let client = ClientMiseAJour(versionActuelle: versionActuelle)
        enCours = Task { [weak self] in
            let resultat = await client.chercher(maintenant: maintenant)
            await MainActor.run { self?.traiter(resultat, manuel: manuel) }
        }
    }

    private func traiter(_ resultat: ResultatRecherche, manuel: Bool) {
        enCours = nil
        if modele.activite == .verification { modele.activite = .repos }
        switch resultat {
        case .proposition(let p):
            noterReussite()
            Log.ecrire("mise à jour : Verbe \(p.version) disponible (installée : \(versionActuelle))")
            modele.disponible = p
            modele.message = nil
        case .aJour:
            noterReussite()
            Log.ecrire("mise à jour : à jour (\(versionActuelle))")
            modele.disponible = nil
            modele.message = nil
        case .horsLigne:
            Log.ecrire("mise à jour : pas de connexion")
            if manuel { modele.message = "Impossible de vérifier : pas de connexion à GitHub." }
        case .limite(let jusqua):
            Settings.miseAJourPasAvant = jusqua
            Log.ecrire("mise à jour : limite de requêtes de GitHub atteinte, rien avant \(jusqua)")
            if manuel { modele.message = "GitHub demande de patienter. Réessaie un peu plus tard." }
        case .echec(let detail):
            Log.ecrire("mise à jour : vérification impossible (\(detail))")
            if manuel { modele.message = "La vérification n\u{2019}a pas abouti." }
        }
        majBande()
    }

    private func noterReussite() {
        let maintenant = Date()
        Settings.miseAJourDerniereReussite = maintenant
        Settings.miseAJourPasAvant = nil
        modele.verifieeLe = maintenant
    }

    // MARK: la ligne sous l'encoche

    private func contexteComplet() -> ContexteAffichage {
        var c = contexte()
        c.installationPossible = modele.refusInstallation == nil
        return c
    }

    /// Montre ou retire la ligne selon la règle (jamais pendant une dictée ni une réunion). Appelée à chaque changement et toutes les 2 s
    /// tant qu'une version est en attente.
    func majBande() {
        let besoinSurveillance = modele.disponible != nil
        if besoinSurveillance, surveillance == nil {
            let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.majBande() } }
            RunLoop.main.add(t, forMode: .common)
            surveillance = t
        } else if !besoinSurveillance { surveillance?.invalidate(); surveillance = nil }

        guard let presentation = modele.presentation else { bande.fermer(); return }
        switch presentation {
        case .proposition:
            guard let d = modele.disponible,
                  AffichageMiseAJour.peutProposer(version: d.version, versionActuelle: versionActuelle, contexte: contexteComplet(),
                                                  report: Settings.miseAJourReport, maintenant: Date()) else { bande.fermer(); return }
            bande.afficher(modele: modele)
        case .progression, .echec:
            // Une installation lancée depuis la ligne s'y suit ; lancée depuis les Réglages, elle ne s'affiche pas sous l'encoche.
            if bande.estOuverte { bande.afficher(modele: modele) }
        }
    }

    /// Une dictée ou une réunion commence : la ligne part tout de suite, sans attendre le relevé suivant.
    func occuper() { bande.fermer(animee: false) }

    private func plusTard() {
        guard let d = modele.disponible else { bande.fermer(); return }
        Settings.miseAJourReport = ReportProposition.plusTard(version: d.version, maintenant: Date())
        Log.ecrire("mise à jour : « Plus tard » pour \(d.version), rappel demain")
        bande.fermer()
    }

    private func fermerLEchec() {
        modele.echecInstallation = nil
        if let d = modele.disponible { Settings.miseAJourReport = ReportProposition.plusTard(version: d.version, maintenant: Date()) }
        majBande()
    }

    func montrerLesNotes() {
        guard let d = modele.disponible else { return }
        bande.suspendreLeDelai()
        notes.afficher(d, peutInstaller: modele.peutInstaller)
    }

    // MARK: installation

    func installer() {
        guard let p = modele.disponible, modele.peutInstaller, enCours == nil else { return }
        let appActuelle = Bundle.main.bundleURL
        bande.annulerLeRetrait()
        modele.echecInstallation = nil
        modele.message = nil
        modele.activite = .telechargement(0)
        notes.fermer()
        Log.ecrire("mise à jour : installation de la version \(p.version) demandée")
        let installateur = InstallateurMiseAJour(client: ClientMiseAJour(versionActuelle: versionActuelle))
        enCours = Task { [weak self] in
            do {
                try await installateur.installer(p, appActuelle: appActuelle) { etape in
                    Task { @MainActor in self?.etape(etape) }
                }
                await self?.installee(p)
            } catch {
                let e = error as? ErreurMiseAJour
                Log.ecrire("mise à jour : échec, rien n'est remplacé (\(e?.detail ?? error.localizedDescription))")
                await MainActor.run { self?.echec(e?.message ?? "La mise à jour n\u{2019}a pas abouti.") }
            }
        }
        majBande()
    }

    private func etape(_ e: EtapeInstallation) {
        guard modele.activite != .repos, modele.activite != .attenteRedemarrage else { return }
        switch e {
        case .telechargement(let x): modele.activite = .telechargement(x)
        case .verification: modele.activite = .controle
        case .installation: modele.activite = .installation
        }
        majBande()
    }

    private func echec(_ phrase: String) {
        enCours = nil
        modele.activite = .repos
        modele.message = "\(phrase) Rien n\u{2019}a été changé."
        // Après un échec, la ligne se tait jusqu'à demain (Réglages garde l'échec et le bouton Installer).
        if let d = modele.disponible { Settings.miseAJourReport = ReportProposition.plusTard(version: d.version, maintenant: Date()) }
        if bande.estOuverte {
            modele.echecInstallation = "Mise à jour impossible. Rien n\u{2019}a été changé."   // courte : elle tient dans la ligne sous l'encoche
            majBande()
            bande.fermerSeulApres(8) { [weak self] in self?.fermerLEchec() }
        } else {
            majBande()
        }
    }

    /// L'app en place est la nouvelle : on attend la fin d'une éventuelle dictée ou réunion, puis on relance.
    private func installee(_ p: PropositionMiseAJour) async {
        await MainActor.run {
            Settings.miseAJourInstallee = p.version.description
            modele.activite = .attenteRedemarrage
            majBande()
        }
        while !AffichageMiseAJour.peutRedemarrer(contexte: await MainActor.run(body: { self.contexte() })) {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        await MainActor.run { Self.relancer(Bundle.main.bundleURL) }
    }

    /// Lance la nouvelle copie une fois cette instance partie (l'app refuse de tourner en double), puis quitte.
    static func relancer(_ app: URL) {
        Log.ecrire("mise à jour : relance de \(app.lastPathComponent)")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "i=0; while kill -0 \"$1\" 2>/dev/null && [ $i -lt 50 ]; do sleep 0.2; i=$((i+1)); done; /usr/bin/open \"$2\"",
                       "sh", String(ProcessInfo.processInfo.processIdentifier), app.path]
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        NSApp.terminate(nil)
    }
}
