import AppKit
import AVFoundation
import ServiceManagement
import EventKit
import DicteeCore

struct MicroChoix: Identifiable, Equatable {
    var id: String        // identifiant CoreAudio ; vide = Automatique ; "systeme" = micro du système
    var nom: String
}

/// Les réglages montrés dans la fenêtre : lus et écrits dans `Settings` (UserDefaults) et le système.
@MainActor
final class ReglagesModele: ObservableObject {
    static let partage = ReglagesModele()

    @Published var remettreAuPropre: Bool { didSet { if !installe { return }; Settings.remettreAuPropre = remettreAuPropre } }
    @Published var adapterLeTon: Bool { didSet { if !installe { return }; Settings.adapterLeTon = adapterLeTon } }
    @Published var sons: Bool { didSet { if !installe { return }; Settings.sons = sons } }
    @Published var vibration: Bool { didSet { if !installe { return }; Settings.vibration = vibration } }
    @Published var garderSonReunions: Bool { didSet { if !installe { return }; Settings.garderSonReunions = garderSonReunions } }
    @Published var proposerLesAppels: Bool { didSet { if !installe { return }; Settings.proposerLesAppels = proposerLesAppels } }
    @Published var secoursApple: Bool { didSet { if !installe { return }; Settings.secoursApple = secoursApple } }
    @Published var afficherLaLecture: Bool { didSet { if !installe { return }; Settings.afficherLaLecture = afficherLaLecture; NotificationCenter.default.post(name: .verbeLectureReglages, object: nil) } }
    @Published var pauseLecturePendantDictee: Bool { didSet { if !installe { return }; Settings.pauseLecturePendantDictee = pauseLecturePendantDictee } }
    @Published var ilotMinuteur: Bool { didSet { if !installe { return }; Settings.ilotMinuteur = ilotMinuteur; NotificationCenter.default.post(name: .verbeIlotReglages, object: nil) } }
    @Published var ilotRappels: Bool { didSet { if !installe { return }; Settings.ilotRappels = ilotRappels; NotificationCenter.default.post(name: .verbeIlotReglages, object: nil) } }
    /// Activer le calendrier est le seul moment où macOS demande l'autorisation (jamais au lancement) ; refusée, l'interrupteur se remet sur éteint.
    @Published var ilotCalendrier: Bool { didSet { if !installe { return }; Settings.ilotCalendrier = ilotCalendrier; NotificationCenter.default.post(name: .verbeIlotReglages, object: nil) } }
    @Published var ilotNotifications: Bool { didSet { if !installe { return }; Settings.ilotNotifications = ilotNotifications; NotificationCenter.default.post(name: .verbeIlotReglages, object: nil) } }
    @Published var ilotEnergie: Bool { didSet { if !installe { return }; Settings.ilotEnergie = ilotEnergie; NotificationCenter.default.post(name: .verbeIlotReglages, object: nil) } }
    @Published var ilotTelechargements: Bool { didSet { if !installe { return }; Settings.ilotTelechargements = ilotTelechargements; NotificationCenter.default.post(name: .verbeIlotReglages, object: nil) } }
    @Published var ilotMicro: Bool { didSet { if !installe { return }; Settings.ilotMicro = ilotMicro; NotificationCenter.default.post(name: .verbeIlotReglages, object: nil) } }
    @Published var ilotNiveaux: Bool { didSet { if !installe { return }; Settings.ilotNiveaux = ilotNiveaux; NotificationCenter.default.post(name: .verbeIlotReglages, object: nil) } }
    @Published var ilotEtagere: Bool { didSet { if !installe { return }; Settings.ilotEtagere = ilotEtagere; NotificationCenter.default.post(name: .verbeIlotReglages, object: nil) } }
    @Published var ilotClaude: Bool { didSet { if !installe { return }; Settings.ilotClaude = ilotClaude; NotificationCenter.default.post(name: .verbeIlotReglages, object: nil) } }
    /// Les crochets de Verbe sont dans ~/.claude/settings.json ; `avisClaude` : ce qui n'a pas marché.
    @Published private(set) var claudeBranche = false
    @Published private(set) var avisClaude: String?
    var phraseClaude: String {
        if let avisClaude { return avisClaude }
        if claudeBranche { return "Branché : les sessions de Claude Code ouvertes dès maintenant s\u{2019}affichent dans l\u{2019}îlot. « Débrancher » retire seulement les crochets de Verbe." }
        return "Où en est Claude Code : « 3 sur 7 », ta réponse attendue, la fin. Ajoute les crochets de Verbe à ~/.claude/settings.json, sans rien toucher d\u{2019}autre."
    }
    func brancherClaude() { changerClaude { try $0.brancher() } }
    func debrancherClaude() { changerClaude { try $0.debrancher() } }
    private func changerClaude(_ faire: (InstallationClaude) throws -> Void) {
        guard reel else { return }
        let i = InstallationClaude.parDefaut
        do { try faire(i); avisClaude = nil }
        catch let e as InstallationClaude.Echec { avisClaude = e.phrase }
        catch { avisClaude = error.localizedDescription }
        claudeBranche = i.estBranche
    }
    @Published var sonFinMinuteur: String { didSet { if !installe { return }; Settings.sonFinMinuteur = sonFinMinuteur } }
    var phraseCalendrier: String {
        if reel, !ilotCalendrier, EKAutorisation.refusee { return "L\u{2019}accès est refusé : à autoriser dans Réglages Système › Confidentialité et sécurité › Calendriers." }
        return "10 minutes avant et au début d\u{2019}un rendez-vous, avec « Rejoindre ». Lit les calendriers du Mac ; la demande d\u{2019}accès n\u{2019}apparaît qu\u{2019}ici."
    }
    @Published var modeleWhisper: ModeleWhisper { didSet { if !installe { return }; Settings.modeleWhisper = modeleWhisper } }
    /// La phrase sous « Vitesse de transcription » (avec les latences mesurées chez Hugues).
    @Published private(set) var phraseVitesse = ""
    /// Test de précision sur la vraie voix : actif tant qu'il reste des dictées à garder (50 au départ, s'arrête seul).
    @Published var testPrecision: Bool {
        didSet { if !installe || testPrecision == (Settings.testPrecisionRestant > 0) { return }
                 Settings.testPrecisionRestant = testPrecision ? TestPrecision.nombreDeDictees : 0
                 testPrecisionRestant = Settings.testPrecisionRestant }
    }
    @Published private(set) var testPrecisionRestant = 0
    @Published var langue: String { didSet { if !installe { return }; Settings.choisirLangue(langue == ChoixLangue.automatique ? nil : langue) } }
    @Published var micro: String { didSet { if !installe { return }; Settings.micro = micro.isEmpty ? nil : micro; rafraichirMicroUtilise() } }
    @Published var ouvrirAuDemarrage: Bool
    @Published private(set) var micros: [MicroChoix]
    /// Phrase sobre quand le système refuse (ex. ouverture au démarrage).
    @Published var avis: String?
    @Published var confirmerEffacement = false
    @Published private(set) var disponibiliteSecours: PrechauffageParole.Disponibilite = .enPreparation
    @Published private(set) var cle: CleGroq.Etat = .absente
    @Published private(set) var autorisationsCompletes = true
    /// Combien des 3 autorisations (micro, accessibilité, saisie au clavier) sont accordées.
    @Published private(set) var autorisationsAccordees = 3
    /// Le micro que la prochaine dictée utilisera réellement (la décision d'« Automatique » comprise).
    @Published private(set) var microUtilise = "Micro du MacBook"
    /// Réglage « Appuyer sur 🌐 pour » (voir `ToucheGlobe`) ; `nil` = clé absente.
    @Published private(set) var globeValeur: Int?
    private var installe = false
    private let reel: Bool
    /// Mises à jour : l'état partagé avec la ligne sous l'encoche (réel), ou un exemple pour les rendus.
    let maj: MiseAJourModele

    var globeAReglerEncore: Bool { ToucheGlobe.doitEtreReglee(valeur: globeValeur) }

    /// `reel = false` : valeurs d'exemple, aucun accès au système (rendus PNG).
    init(reel: Bool = true, globe: Int? = 0, maj: MiseAJourModele? = nil) {
        self.reel = reel
        self.maj = maj ?? (reel ? MiseAJourControleur.partage.modele : MiseAJourModele.exemple(verifieeLe: Date()))
        globeValeur = reel ? ToucheGlobe.lire() : globe
        remettreAuPropre = reel ? Settings.remettreAuPropre : true
        adapterLeTon = reel ? Settings.adapterLeTon : true
        secoursApple = reel ? Settings.secoursApple : true
        garderSonReunions = reel ? Settings.garderSonReunions : false
        proposerLesAppels = reel ? Settings.proposerLesAppels : true
        sons = reel ? Settings.sons : true
        vibration = reel ? Settings.vibration : true
        afficherLaLecture = reel ? Settings.afficherLaLecture : true
        pauseLecturePendantDictee = reel ? Settings.pauseLecturePendantDictee : true
        ilotMinuteur = reel ? Settings.ilotMinuteur : true
        ilotRappels = reel ? Settings.ilotRappels : true
        ilotCalendrier = reel ? Settings.ilotCalendrier : false
        ilotNotifications = reel ? Settings.ilotNotifications : false
        sonFinMinuteur = reel ? Settings.sonFinMinuteur : "Pop"
        ilotEnergie = reel ? Settings.ilotEnergie : true
        ilotTelechargements = reel ? Settings.ilotTelechargements : false
        ilotMicro = reel ? Settings.ilotMicro : true
        ilotNiveaux = reel ? Settings.ilotNiveaux : true
        ilotEtagere = reel ? Settings.ilotEtagere : true
        ilotClaude = reel ? Settings.ilotClaude : true
        claudeBranche = reel ? InstallationClaude.parDefaut.estBranche : false
        modeleWhisper = reel ? Settings.modeleWhisper : ModeleWhisper.parDefaut
        testPrecision = reel ? Settings.testPrecisionRestant > 0 : false
        langue = reel ? Settings.langueReglage : ChoixLangue.defaut
        micro = reel ? (Settings.micro ?? "") : "exemple"
        ouvrirAuDemarrage = reel ? SMAppService.mainApp.status == .enabled : false
        micros = [MicroChoix(id: ChoixMicro.automatique, nom: "Automatique"), MicroChoix(id: ChoixMicro.systeme, nom: "Micro du système")]
        installe = true
        if reel {
            NotificationCenter.default.addObserver(forName: .verbeIlotReglagesRelus, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { guard let self else { return }; if self.ilotCalendrier != Settings.ilotCalendrier { self.ilotCalendrier = Settings.ilotCalendrier }
                    if self.ilotTelechargements != Settings.ilotTelechargements { self.ilotTelechargements = Settings.ilotTelechargements }
                    if self.micro != (Settings.micro ?? "") { self.micro = Settings.micro ?? "" } }
            }
        }
        if reel { rafraichir() } else { micros.append(MicroChoix(id: "exemple", nom: "Micro du MacBook")); disponibiliteSecours = .pret; cle = .trousseau }
    }

    /// Relit ce qui peut changer hors de l'app (micros branchés, état du secours, de la clé, du démarrage).
    func rafraichir() {
        guard reel else { return }
        let decouverte = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified)
        micros = [MicroChoix(id: ChoixMicro.automatique, nom: "Automatique"), MicroChoix(id: ChoixMicro.systeme, nom: "Micro du système")] + decouverte.devices.map { MicroChoix(id: $0.uniqueID, nom: $0.localizedName) }
        if !micro.isEmpty, micro != ChoixMicro.systeme, !micros.contains(where: { $0.id == micro }) { micros.append(MicroChoix(id: micro, nom: "Micro absent")) }
        disponibiliteSecours = PrechauffageParole.disponibilite
        cle = CleGroq.etat
        phraseVitesse = Settings.latences.phrase()
        modeleWhisper = Settings.modeleWhisper
        autorisationsCompletes = Permissions.toutesOK
        autorisationsAccordees = [Permissions.microOK, Permissions.accessibiliteOK, Permissions.surveillanceOK].filter { $0 }.count
        rafraichirMicroUtilise()
        ouvrirAuDemarrage = SMAppService.mainApp.status == .enabled
        rafraichirGlobe()
    }

    /// Relit le micro réellement utilisé : même décision que celle de la capture (`ChoixMicro`), sans toucher au micro.
    func rafraichirMicroUtilise() {
        guard reel else { return }
        let decision = ChoixMicro.decider(reglage: micro.isEmpty ? nil : micro, peripheriques: AudioCapture.peripheriquesEntree(), defautUID: AudioCapture.peripheriqueParDefaut()?.uid)
        let nom: String
        switch decision {
        case .impose(let p, _): nom = p.nom
        case .systeme: nom = AudioCapture.peripheriqueParDefaut()?.nom ?? "Aucun micro"
        }
        if nom != microUtilise { microUtilise = nom }
    }

    /// Relit seulement la touche 🌐 (appelé chaque seconde pendant que les Réglages sont à l'écran).
    func rafraichirGlobe() {
        guard reel else { return }
        let v = ToucheGlobe.lire()
        if v != globeValeur { globeValeur = v }
        let restant = Settings.testPrecisionRestant
        if restant != testPrecisionRestant { testPrecisionRestant = restant }
        if testPrecision != (restant > 0) { testPrecision = restant > 0 }
    }

    func ouvrirVoletClavier() {
        guard let url = URL(string: ToucheGlobe.adresseVoletClavier) else { return }
        NSWorkspace.shared.open(url)
    }

    func choisirOuvertureAuDemarrage(_ voulu: Bool) {
        guard reel else { ouvrirAuDemarrage = voulu; return }
        do {
            if voulu { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            avis = nil
        } catch {
            Log.ecrire("ouverture au démarrage : \(error.localizedDescription)")
            avis = voulu ? "Impossible de l\u{2019}activer pour l\u{2019}instant." : "Impossible de le désactiver pour l\u{2019}instant."
        }
        ouvrirAuDemarrage = SMAppService.mainApp.status == .enabled
    }

    /// Phrase sous « Secours » : n'affirme que le secours prend le relais qu'une fois la dictée d'Apple réellement prête.
    var phraseSecours: String {
        guard secoursApple else { return "Sans secours, une dictée échoue si Groq ne répond pas." }
        switch disponibiliteSecours {
        case .pret: return "Si Groq ne répond pas, la dictée d\u{2019}Apple prend le relais."
        case .enPreparation: return "La dictée d\u{2019}Apple est en préparation."
        case .indisponible: return "La dictée d\u{2019}Apple est indisponible sur ce Mac."
        }
    }

    /// Le nom de la langue réglée, pour la ligne d'état.
    var nomLangue: String {
        switch langue { case "fr": return "Français"; case "en": return "Anglais"; default: return "Automatique" }
    }
}

/// L'état de l'autorisation du calendrier, lu sans jamais la demander.
enum EKAutorisation {
    static var refusee: Bool {
        switch EKEventStore.authorizationStatus(for: .event) { case .denied, .restricted, .writeOnly: return true; default: return false }
    }
}
