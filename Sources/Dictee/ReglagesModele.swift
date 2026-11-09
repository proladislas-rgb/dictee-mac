import AppKit
import AVFoundation
import ServiceManagement
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
    @Published var secoursApple: Bool { didSet { if !installe { return }; Settings.secoursApple = secoursApple } }
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

    var globeAReglerEncore: Bool { ToucheGlobe.doitEtreReglee(valeur: globeValeur) }

    /// `reel = false` : valeurs d'exemple, aucun accès au système (rendus PNG).
    init(reel: Bool = true, globe: Int? = 0) {
        self.reel = reel
        globeValeur = reel ? ToucheGlobe.lire() : globe
        remettreAuPropre = reel ? Settings.remettreAuPropre : true
        adapterLeTon = reel ? Settings.adapterLeTon : true
        secoursApple = reel ? Settings.secoursApple : true
        sons = reel ? Settings.sons : true
        vibration = reel ? Settings.vibration : true
        langue = reel ? Settings.langueReglage : ChoixLangue.defaut
        micro = reel ? (Settings.micro ?? "") : "exemple"
        ouvrirAuDemarrage = reel ? SMAppService.mainApp.status == .enabled : false
        micros = [MicroChoix(id: ChoixMicro.automatique, nom: "Automatique"), MicroChoix(id: ChoixMicro.systeme, nom: "Micro du système")]
        installe = true
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
