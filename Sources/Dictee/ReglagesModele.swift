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
    @Published var secoursApple: Bool { didSet { if !installe { return }; Settings.secoursApple = secoursApple } }
    @Published var langue: String { didSet { if !installe { return }; Settings.choisirLangue(langue == ChoixLangue.automatique ? nil : langue) } }
    @Published var micro: String { didSet { if !installe { return }; Settings.micro = micro.isEmpty ? nil : micro } }
    @Published var ouvrirAuDemarrage: Bool
    @Published private(set) var micros: [MicroChoix]
    /// Phrase sobre quand le système refuse (ex. ouverture au démarrage).
    @Published var avis: String?
    @Published var confirmerEffacement = false
    @Published private(set) var disponibiliteSecours: PrechauffageParole.Disponibilite = .enPreparation
    @Published private(set) var cle: CleGroq.Etat = .absente
    @Published private(set) var autorisationsCompletes = true
    private var installe = false
    private let reel: Bool

    /// `reel = false` : valeurs d'exemple, aucun accès au système (rendus PNG).
    init(reel: Bool = true) {
        self.reel = reel
        remettreAuPropre = reel ? Settings.remettreAuPropre : true
        adapterLeTon = reel ? Settings.adapterLeTon : true
        secoursApple = reel ? Settings.secoursApple : true
        langue = reel ? Settings.langueReglage : ChoixLangue.defaut
        micro = reel ? (Settings.micro ?? "") : ""
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
        ouvrirAuDemarrage = SMAppService.mainApp.status == .enabled
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

    /// Phrase sous « Secours » : n'affirme « Dictée Apple active » qu'une fois le secours réellement prêt.
    var phraseSecours: String? {
        guard secoursApple else { return "Sans secours, une dictée échoue si Groq ne répond pas." }
        switch disponibiliteSecours {
        case .pret: return "Dictée Apple active"
        case .enPreparation: return "Dictée Apple en préparation"
        case .indisponible: return "Dictée Apple indisponible sur ce Mac"
        }
    }
}
