import AppKit
import SwiftUI
import DicteeCore

/// Une alerte : l'îlot s'ouvre de lui-même, vibre, sonne, et attend un geste (maquette : minuteur fini, rappel, rendez-vous qui commence).
struct AlerteIlot {
    var vue: VueIlot
    /// Elle se retire seule à cette date (le rendez-vous : 15 s ; le rappel : 12 s, la cloche reste) ; nil = attend un geste.
    var jusqua: Date?
    var rappel: Rappel?
    var evenement: EvenementAgenda?
    /// « 10 min » pour un minuteur fini.
    var libelle = ""
}

/// Un bandeau passager : icône dans l'aile, deux lignes sous l'encoche.
struct BandeauIlot {
    var vue: VueIlot
    var jusqua: Date
    var ligne1: String
    var ligne2: String
    var meta = ""
    /// Un son très doux à l'arrivée (notifications, rendez-vous qui approche).
    var sonore = false
    /// Le rappel qu'on peut annuler depuis le bandeau « Rappel ajouté ».
    var rappelId: UUID?
    var evenement: EvenementAgenda?
    var rendezVous: EvenementAgenda? { evenement }
    /// Les écouteurs qui viennent de se connecter (bandeau `.appareil`).
    var appareil: AppareilIlot?
    /// La batterie au moment de l'annonce (bandeaux `.batterieCharge` et `.batterieFaible`).
    var energie: EnergieIlot?
    /// Les fichiers arrivés dans Téléchargements (bandeau `.telecharge`).
    var telechargement: TelechargementIlot?
    /// Le volume ou la luminosité (bandeaux `.volume` et `.luminosite`).
    var niveau: NiveauIlot?
    /// La session de Claude Code qui attend une réponse ou qui a fini (bandeaux `.claudeAttend` et `.claudeTermine`).
    var claude: SessionClaude?
}

/// Ce que montre le bandeau « Téléchargé » : la rafale (noms, tailles, AirDrop) et les icônes du Finder, lues une fois à l'annonce.
struct TelechargementIlot {
    var rafale: RafaleTelechargements
    var icones: [NSImage]
    var urls: [URL] { rafale.fichiers.map(\.url) }
}

/// Un fichier de l'étagère tel que l'îlot le montre : son icône du Finder est lue une fois, au rangement.
struct FichierEtagere: Identifiable {
    var id: UUID
    var nom: String
    var url: URL
    var icone: NSImage
}

/// Ce que l'îlot demande aux contrôleurs (le moteur ne sait rien du minuteur, des rappels ni du calendrier : il montre et il relaie).
enum ActionIlot {
    case minuteurLancer(minutes: Double)
    /// Depuis la rangée Minuteur sous la lecture : pas de bandeau, le minuteur part directement dans la pastille.
    case minuteurLancerSousLecture(minutes: Double)
    case minuteurBasculer, minuteurPlusUneMinute, minuteurArreter
    case minuteurRecommencer(minutes: Double)
    case alerteOK
    case rappelPlusTard(UUID), rappelFait(UUID), rappelAnnuler(UUID)
    case rappelFormulaire
    case rendezVousRejoindre(EvenementAgenda), rendezVousNoter(EvenementAgenda)
    case collerLaDerniereDictee
    /// Le micro de la dictée : celui des AirPods (vrai) ou celui du Mac (faux, le réglage Automatique).
    case microChoisir(airpods: Bool)
    /// « Ouvrir » sur le bandeau Téléchargé : le fichier (un seul) ou le Finder sur les fichiers (plusieurs).
    case fichiersOuvrir([URL])
    /// « Rouvrir » sur le micro coupé déplié.
    case microRouvrir
    /// « Ouvrir » sur Claude au travail : ramène l'app d'où vient la session (le Terminal), par son identifiant.
    case claudeOuvrir(String?)
    /// L'étagère : ouvrir un fichier (clic sur sa tuile), le retirer (« × »), tout vider.
    case etagereOuvrir(UUID), etagereRetirer(UUID), etagereVider
    /// Les boutons du Centre (CentreIlot.swift) : couper ou rouvrir le micro, allumer ou éteindre Téléchargements, brancher Claude Code
    /// (ou ramener sa session), allumer l'étagère éteinte dans les réglages.
    case centreMicro, centreTelechargements, centreClaude, etagereAllumer
    /// La bande « Noter la réunion » du Centre ; la ligne d'avis « Accès refusé » (elle ouvre Réglages Système).
    case centreReunion, centreAvis
    /// Un minuteur lancé depuis le Centre : ni bandeau ni fermeture (on enchaîne d'autres réglages), il part dans la case Minuteur.
    case minuteurLancerDansLeCentre(minutes: Double)
}

/// Les activités dont le contenu voyage d'un état à l'autre (la pochette, l'anneau et l'heure du minuteur, la cloche, le calendrier) :
/// une seule pièce qui grandit et glisse à sa place, jamais deux qui se croisent.
enum FamilleIlot: CaseIterable {
    case lecture, minuteur, rappel, agenda, micro, claude, autre
    static func de(_ v: VueIlot) -> FamilleIlot {
        switch v {
        case .lectureCompact, .lectureEtendu, .lectureMinuteur: return .lecture
        case .minuteurMinimal, .minuteurCompact, .minuteurEtendu: return .minuteur
        case .rappelCompact, .rappelEtendu: return .rappel
        case .agendaCompact, .agendaEtendu: return .agenda
        case .microCompact, .microEtendu: return .micro
        case .claudeMinimal, .claudeCompact, .claudeEtendu: return .claude
        default: return .autre
        }
    }
    var vues: (compact: VueIlot, etendu: VueIlot)? {
        switch self {
        case .lecture: return (.lectureCompact, .lectureEtendu)
        case .minuteur: return (.minuteurCompact, .minuteurEtendu)
        case .rappel: return (.rappelCompact, .rappelEtendu)
        case .agenda: return (.agendaCompact, .agendaEtendu)
        case .micro: return (.microCompact, .microEtendu)
        case .claude: return (.claudeCompact, .claudeEtendu)
        case .autre: return nil
        }
    }
}

/// Quand un écran (ou une famille) est arrivé ou parti, à l'horloge d'animation du moteur. Le contenu nouveau arrive APRÈS la forme
/// (`delai`), en cascade ; il repart AVANT elle. `depart` : l'opacité au moment du changement (une interruption repart de là).
struct ApparitionIlot: Equatable {
    var debut: Double
    var entre: Bool
    var delai: Double
    var depart: Double
    /// D'une carte à l'autre (lecture, Centre, accueil) : le contenu glisse aussi, vers le haut (+1, on descend dans la pile) ou vers le
    /// bas (−1). 0 : il apparaît sur place.
    var glisse: Double = 0
}

/// Ce qui s'ajoute à un écran sans en être un : le pied de la lecture (bouton « Centre »), les points de page à droite des cartes, la
/// bulle « Nouveau » sous l'îlot replié. Chacun a son horloge d'apparition (il reste quand on passe d'une carte à l'autre).
enum ExtraIlot: CaseIterable {
    case pied, points, bulle
}

/// Ce qu'un élément montre à un instant : opacité, flou, zoom (maquette : fondu 0,26 s, flou 8 → 0 en 0,30 s, zoom 0,92 → 1 en 0,46 s
/// sur un ressort ; départ : 0,15 s).
struct AspectIlot {
    var opacite: Double
    var flou: CGFloat
    var echelle: CGFloat
    /// Le glissé vertical d'un contenu qui change de carte (0 sinon).
    var decalage: CGFloat = 0
    static let cache = AspectIlot(opacite: 0, flou: 0, echelle: 1)
    static let visible = AspectIlot(opacite: 1, flou: 0, echelle: 1)
}

enum CourbesIlot {
    /// La courbe CSS « ease » (cubic-bezier(.25, .1, .25, 1)).
    static func ease(_ t: Double) -> Double { bezier(t, 0.25, 0.1, 0.25, 1) }
    static func bezier(_ t: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
        let x = min(1, max(0, t))
        if x <= 0 { return 0 }; if x >= 1 { return 1 }
        func bx(_ u: Double) -> Double { 3 * (1 - u) * (1 - u) * u * x1 + 3 * (1 - u) * u * u * x2 + u * u * u }
        func by(_ u: Double) -> Double { 3 * (1 - u) * (1 - u) * u * y1 + 3 * (1 - u) * u * u * y2 + u * u * u }
        var lo = 0.0, hi = 1.0, u = x
        for _ in 0..<24 { u = (lo + hi) / 2; if bx(u) < x { lo = u } else { hi = u } }
        return by(u)
    }
    /// Le ressort du zoom d'entrée (réponse 0,42 s, amortissement 0,78), en secondes depuis le départ ; 1 après 0,46 s.
    static func ressort(_ t: Double) -> Double {
        if t <= 0 { return 0 }; if t >= 0.46 { return 1 }
        let w = 2 * Double.pi / 0.42, z = 0.78, wd = w * (1 - z * z).squareRoot()
        return 1 - exp(-z * w * t) * (cos(wd * t) + z * w / wd * sin(wd * t))
    }
    static func borne(_ v: Double) -> Double { min(1, max(0, v)) }
}

/// Le moteur de l'îlot : ressorts de la forme, arbitrage, survol, pastille, bandeaux, alertes, et l'horloge du contenu, sans aucune
/// minuterie qui tourne au repos. La boucle (calée sur l'écran) n'existe que pendant qu'un ressort ou un fondu bouge ; les bandeaux et
/// alertes ont une date de fin et un seul réveil programmé.
@MainActor
final class IlotMoteur: ObservableObject {
    /// Zone de dessin : l'origine des coordonnées de la maquette (centre de l'encoche) est au milieu, en haut.
    static let largeur: CGFloat = 800
    static let hauteurMax: CGFloat = 380

    @Published private(set) var rev = 0
    var geometrie = GeometrieEncoche()
    var reduire = false
    var maintenant: () -> Date = { Date() }

    // MARK: données (poussées par les contrôleurs)
    let lecture: LectureModele
    var minuteur: MinuteurIlot? { didSet { if let minuteur { dernierMinuteur = minuteur } } }
    /// Les derniers contenus vus : un écran qui s'efface garde son texte pendant qu'il disparaît.
    private(set) var dernierMinuteur = MinuteurIlot(minutes: 10, depuis: Date())
    private(set) var dernierRappel: Rappel?
    private(set) var dernierRendezVous: EvenementAgenda?
    private(set) var alerteVu: AlerteIlot?
    private(set) var bandeauVu: BandeauIlot?
    /// Rappels sonnés sans réponse (la cloche) et rappels à venir (la liste).
    var rappelsSonnes: [Rappel] = [] { didSet { if let r = rappelsSonnes.first { dernierRappel = r } } }
    var rappelsAVenir: [Rappel] = []
    var rendezVous: EvenementAgenda? { didSet { if let rendezVous { dernierRendezVous = rendezVous } } }
    var rendezVousProche = false
    var rendezVousSuivant: EvenementAgenda?
    var lecturePresente = false
    var alerte: AlerteIlot? { didSet { if let alerte { alerteVu = alerte; if let r = alerte.rappel { dernierRappel = r }; if let e = alerte.evenement { dernierRendezVous = e } } } }
    var bandeau: BandeauIlot? { didSet { if let bandeau { bandeauVu = bandeau } } }
    /// Rendus PNG : pas d'animation Core Animation (ImageRenderer ne sait pas les dessiner).
    var statique = false
    var notifications: [NotificationRecue] = []
    var derniereDictee: (texte: String, age: String)?
    /// Dit à l'accueil si le calendrier est branché (sinon la tuile propose de l'activer).
    var calendrierActif = false
    /// Le micro du Mac est coupé (bouton Micro du Centre, ou Réglages Système), et son nom pour le déplié (« Micro MacBook Air »).
    var microCoupe = false
    var nomMicro: String?
    /// La session de Claude Code que l'îlot montre (au travail, ou qui attend une réponse) ; la dernière vue, pour un écran qui s'efface.
    var claude: SessionClaude? { didSet { if let claude { dernierClaude = claude } } }
    private(set) var dernierClaude: SessionClaude?
    /// L'étagère (réglage allumé) et ses fichiers, dans l'ordre où ils ont été rangés.
    var etagereActive = false
    /// Des écouteurs Bluetooth avec un micro sont là : l'accueil propose « Micro : Mac / AirPods » (nom des écouteurs, leur micro choisi ?).
    var choixMicro: (nom: String, airpods: Bool)?
    var etagere: [FichierEtagere] = []
    /// Un glisser de fichiers est près de l'encoche : l'îlot s'ouvre en « Déposez ici ». `depotSurvole` : le pointeur est sur la zone,
    /// elle s'éclaire.
    private(set) var depot = false
    var depotSurvole = false { didSet { if depotSurvole != oldValue { rev += 1 } } }
    private var finDepot: DispatchWorkItem?
    /// La batterie du Mac (nil : Mac sans batterie, ou réglage éteint) et les écouteurs connectés : les épaules de l'îlot déplié.
    var energie: EnergieIlot?
    var ecouteurs: AppareilIlot?
    /// Les épaules s'ouvrent (cou de 56 pt) quand il y a quelque chose à y montrer.
    var epaules: Bool { energie != nil || ecouteurs != nil }
    /// 0 → 1 : les épaules paraissent quand le cou s'est élargi ET que le corps est descendu ; à la fermeture, le cou se resserre
    /// d'abord et elles s'effacent avant d'être rognées.
    var ouvertureEpaules: Double {
        guard epaules, geo.count > 2 else { return 0 }
        let corps = (geo[2].x - Double(geometrie.hauteur) - 24) / 40, cou = (geo[0].x - (GeoIlot.epaules - 10)) / 8
        return min(1, max(0, min(corps, cou)))
    }

    // MARK: le Centre (CentreIlot.swift pour ses vues)
    /// Ce que le Centre montre de l'état du Mac (poussé par le contrôleur) : Téléchargements allumé, Claude Code branché.
    var telechargementsActifs = false
    var claudeBranche = false
    /// La bulle « Nouveau : survole l'îlot » (une seule fois, au premier lancement) et l'aide « Fais défiler ou clique ici » sous le
    /// bouton Centre de la lecture (jusqu'au premier passage de la lecture au Centre). Le contrôleur les garde en mémoire.
    private(set) var bulleNouveau = false
    var aideCentre = false
    var surBulleVue: () -> Void = {}
    var surCentreUtilise: () -> Void = {}
    /// Ce que le Centre montre, dans l'ordre (« Modifier », CentreModifier.swift) ; le contrôleur la relit des réglages au lancement.
    var disposition = DispositionCentre() { didSet { if disposition != oldValue { rev += 1 } } }
    /// « Modifier » : les boutons tremblent, « – » retire, « Ajouter : » ajoute, on les range en les glissant ; « OK » enregistre
    /// (`surDispositionCentre`). Un Centre qui se range (clic ailleurs, alerte) enregistre aussi.
    var editionCentre = false { didSet { if editionCentre != oldValue { rev += 1 } } }
    var surDispositionCentre: (DispositionCentre) -> Void = { _ in }
    /// La ligne « Ajouter : » montre les pastilles qui tiennent, puis « +2 › » : un clic montre les suivantes (à partir de celle-ci).
    var debutAjouts = 0 { didSet { if debutAjouts != oldValue { rev += 1 } } }
    /// Téléchargements allumé depuis le Centre : macOS pose sa question (« Un instant… » sous le bouton) jusqu'à la réponse.
    var telechargementsAttente = false { didSet { if telechargementsAttente != oldValue { rev += 1 } } }
    /// Une ligne en haut du Centre quand une action n'a pas pu se faire (accès refusé, crochets de Claude impossibles à écrire).
    var avisCentre: AvisCentre? { didSet { if avisCentre != oldValue { rev += 1 } } }
    private var finBulle: DispatchWorkItem?
    private var defilement = DefilementIlot()

    // MARK: masques (dictée, réunion, autres annonces : l'îlot s'efface)
    var dictee = false
    var reunion = false
    var masque = false
    var cache: Bool { dictee || reunion || masque }
    private var enAttente: [(alerte: AlerteIlot?, bandeau: BandeauIlot?)] = []

    // MARK: sorties
    var surAction: (ActionIlot) -> Void = { _ in }
    /// Une alerte ou un bandeau sonore vient de s'afficher : son et vibration.
    var surArrivee: (VueIlot) -> Void = { _ in }
    /// La zone voulue pour la fenêtre a changé.
    var surFenetre: () -> Void = {}
    /// L'îlot est déplié (ou revient) : le contrôleur peut relire des choses (site de la lecture, lien du rendez-vous…).
    var surDepliage: () -> Void = {}

    // MARK: état de l'affichage
    private(set) var courante: VueIlot = .repos
    private(set) var resolution = ResolutionIlot(principal: .repos, survol: .centre, verrou: false, pastille: nil)
    /// Les sept ressorts de la forme (voir `GeoIlot`).
    var geo: [RessortIlot]
    /// Horloge d'animation (secondes) : elle n'avance que pendant que la boucle tourne ; le contenu se règle sur elle.
    private(set) var tAnim: Double = 0
    private(set) var apparitions: [VueIlot: ApparitionIlot] = [:]
    private(set) var apparitionsFamille: [FamilleIlot: ApparitionIlot] = [:]
    private(set) var apparitionsExtra: [ExtraIlot: ApparitionIlot] = [:]
    /// La forme passe d'un état à l'autre de la même activité : ce qui existe déjà voyage (sinon il apparaît à sa place).
    private(set) var lien = false
    private var dernierMode: [FamilleIlot: Double] = [:]
    var secousse = RessortIlot(0, reponse: 0.17, amortissement: 0.13)
    /// Les barres du volume et de la luminosité (0…1) : elles suivent la valeur sur un ressort. Une par genre : la barre qui s'efface
    /// garde sa valeur pendant que l'autre arrive.
    var jaugeVolume = RessortIlot(0, reponse: JaugeNiveau.reponse, amortissement: JaugeNiveau.amortissement)
    var jaugeLuminosite = RessortIlot(0, reponse: JaugeNiveau.reponse, amortissement: JaugeNiveau.amortissement)
    func jauge(_ g: GenreNiveau) -> RessortIlot { g == .volume ? jaugeVolume : jaugeLuminosite }
    /// Le dernier volume et la dernière luminosité montrés (le symbole de l'écran qui s'efface ne change pas sous les yeux).
    private(set) var derniersNiveaux: [GenreNiveau: NiveauIlot] = [:]
    /// 0 = la bulle est rentrée sous l'aile droite de l'îlot, 1 = posée à côté (elle glisse hors de l'îlot).
    var pastilleChute = RessortIlot(0, reponse: 0.5, amortissement: 0.62)
    var pastilleOuverte = RessortIlot(0, reponse: 0.36, amortissement: 0.88)
    private(set) var apparitionPastille = ApparitionIlot(debut: -10, entre: false, delai: 0, depart: 0)
    private(set) var pastille: ActiviteIlot?
    private var echange: ActiviteIlot?
    var survole = false          // la souris est sur l'îlot assez longtemps
    var epingle = false
    private(set) var sousVue: VueIlot?
    private var pointeurSurForme = false
    private var intention: DispatchWorkItem?
    private var fermeture: DispatchWorkItem?
    private var reveil: DispatchWorkItem?
    private let cadence = CadenceEcran()
    private var dernierPas: TimeInterval = 0

    static let delaiIntention: TimeInterval = 0.28
    static let delaiFermeture: TimeInterval = 0.32

    init(lecture: LectureModele) {
        self.lecture = lecture
        geo = GeoIlot.valeurs(.repos, hauteurBarre: 32).map { RessortIlot($0, reponse: 0.45, amortissement: 1) }
        cadence.tic = { [weak self] in self?.pas() }
    }

    // MARK: arbitrage

    var etat: EtatIlot {
        var e = EtatIlot()
        e.minuteur = minuteur != nil
        e.rappelEnAttente = !rappelsSonnes.isEmpty && !(alerte?.rappel.map { r in rappelsSonnes.count == 1 && rappelsSonnes[0].id == r.id } ?? false)
        e.rendezVousProche = rendezVousProche && rendezVous != nil
        e.lecture = lecturePresente
        e.microCoupe = microCoupe
        e.claude = claude != nil
        e.claudeAttend = claude?.etat == .attend
        e.claudeListe = claude?.progres != nil
        e.alerte = alerte?.vue
        e.bandeau = bandeau?.vue
        return e
    }

    /// Tout a pu changer : on recalcule qui a l'îlot, qui a la pastille, et on déforme la forme vers la nouvelle cible.
    func donneesChangees() {
        if cache {
            if appuiEnCours { annulerAppui() }
            if depot { depot = false; depotSurvole = false; finDepot?.cancel() }
            if resolution.principal != .repos || courante != .repos || pastille != nil {
                resolution = ResolutionIlot(principal: .repos, survol: nil, verrou: true, pastille: nil)
                epingle = false; survole = false; sousVue = nil
                afficher(.repos)
                majPastille()
            }
            majExtras()
            surFenetre(); demarrerBoucle()
            return
        }
        vider()
        let ancien = resolution
        resolution = ArbitrageIlot.resoudre(etat, echange: echange)
        // le micro coupé s'ouvre sur la vidéo en bulle, ou sur le Centre (où est son bouton) : plus de déplié à lui
        if let sv = resolution.survol { resolution.survol = CartesIlot.survol(sv, deuxieme: resolution.pastille.map { ArbitrageIlot.vues($0).etendu }) }
        if let e = echange, resolution.pastille != e, ArbitrageIlot.ordre(etat).contains(e) == false { echange = nil }
        if resolution.verrou { epingle = false; survole = false; sousVue = nil }
        if ancien.principal != resolution.principal, !(survole || epingle) { sousVue = nil }
        if sousVue == .lectureMinuteur, FamilleIlot.de(resolution.principal) != .lecture || resolution.verrou { sousVue = nil }
        if sousVue == .etagere, !etagereActive { sousVue = nil }
        if depot, !etagereActive { depot = false; depotSurvole = false }
        // le Centre ouvert le reste quand une activité commence (un minuteur lancé, le micro coupé, une vidéo) : on ne saute pas ailleurs
        if courante == .centre, survole || epingle, sousVue == nil, !resolution.verrou, resolution.survol != .centre, ancien.survol != resolution.survol { sousVue = .centre }
        // la bulle « Nouveau » a servi : l'îlot vient d'être ouvert
        if bulleNouveau, survole || epingle { cacherBulle() }
        let carte = sousVue ?? ((survole || epingle) && resolution.survol != nil && !resolution.verrou ? resolution.survol! : resolution.principal)
        // un glisser de fichiers près de l'encoche passe avant tout le reste : on vise la zone, puis l'îlot revient où il en était. Sur le
        // Centre ouvert, c'est la case Étagère qui reçoit les fichiers : la forme ne bouge pas
        let voulu = depot && carte != .centre ? .etagereDepot : carte
        afficher(voulu)
        // le Centre s'est rangé (clic ailleurs, alerte, autre carte) : « Modifier » se termine et enregistre ; la ligne d'avis s'en va
        if editionCentre, courante != .centre { finirEditionCentre() }
        if avisCentre != nil, !fenetreOuverte { avisCentre = nil }
        majExtras()
        majPastille()
        programmerReveil()
        surFenetre()
        demarrerBoucle()
    }

    /// Largeur mesurée du contenu des écrans qui s'y ajustent (bandeaux, alertes, rendez-vous déplié). Gardée après leur départ :
    /// l'écran qui s'efface garde sa grille.
    private(set) var contenus: [VueIlot: CGFloat] = [:]
    private func cible(_ v: VueIlot) -> [Double] {
        let g = GeoIlot.valeurs(v, hauteurBarre: Double(geometrie.hauteur), demiCamera: Double(demiCamera), contenu: contenus[v].map(Double.init), epaules: epaules,
                                enPlus: Double(hauteursEnPlus[v] ?? 0))
        guard bulleSous(v) else { return g }
        return GeoIlot.avecBulle(g, hauteurBarre: Double(geometrie.hauteur), demiCamera: Double(demiCamera), contenu: Double(BulleNouveau.largeur))
    }
    /// La grille du contenu (mêmes largeurs que la forme).
    var grille: GrilleIlot { GrilleIlot(hc: demiCamera, barre: geometrie.hauteur, contenus: contenus, epaules: epaules, enPlus: hauteursEnPlus) }
    /// Ce qu'un contenu variable ajoute à la hauteur d'un écran : la ligne de l'étagère en bas de l'accueil, la deuxième rangée de
    /// fichiers de la carte Étagère. Sous la rangée Minuteur de la lecture dépliée (appui long), la ligne de l'étagère. (L'accueil n'a
    /// plus de ligne variable : l'étagère et le choix du micro sont dans le Centre.)
    var hauteursEnPlus: [VueIlot: CGFloat] {
        var d: [VueIlot: CGFloat] = [:]
        if etagereActive, !etagere.isEmpty { d[.lectureMinuteur] = CGFloat(GeoIlot.ligneAccueil) }
        if EtagereIlot.rangees(etagere.count) > 1 { d[.etagere] = CGFloat(GeoIlot.rangeeEtagere) }
        // le Centre suit ce qu'il montre (« Modifier ») : ronds, cases et bande de la réunion, la hauteur de la table
        let p = DispositionCentre.plan(ronds: !rondsCentre.isEmpty, cases: !disposition.cases.isEmpty, bande: disposition.bande).profondeur
        if p != GeoIlot.profondeurCentre { d[.centre] = CGFloat(p - GeoIlot.profondeurCentre) }
        return d
    }

    /// Montre une vue. La forme se déforme vers sa géométrie avec les ressorts de la maquette ; le contenu nouveau arrive après la forme,
    /// l'ancien part avant elle ; ce qui appartient à la même activité (pochette, anneau, heure) voyage.
    private func afficher(_ v: VueIlot) {
        // un écran qui épouse son contenu est mesuré à chaque changement de données (un 2e message arrive, un titre change…)
        if GeoIlot.ajusteAuContenu(v), let l = largeurContenu(v) { contenus[v] = l }
        let c = cible(v)
        if v == courante, geo.enumerated().allSatisfy({ $0.element.cibleFinale == c[$0.offset] }) { return }
        let avant = courante
        let fa = FamilleIlot.de(avant), fv = FamilleIlot.de(v)
        let modeAvant = fa == .autre ? 0 : ouvertureCourante(fa)
        courante = v
        // ouverture : la largeur mène, la hauteur suit (petit rebond) ; fermeture : le contenu part d'abord, puis la forme se dégonfle
        // sans rebond, la largeur un peu devant (jamais de bandeau plat sous les menus). Les mêmes ressorts que les contrôles.
        let passage = PassageIlot.viser(&geo, vers: c, alerte: v.estAlerte, reduire: reduire)
        let ouvre = passage == .ouverture, ferme = passage == .fermeture
        // contenu : la famille (ce qui voyage) et l'écran (ce qui est propre à cet état)
        lien = fa == fv && fv != .autre
        // la lecture dépliée qui gagne (ou perd) sa rangée Minuteur : la pochette reste où elle est
        glisseLecture = lien && fa == .lecture && avant != .lectureCompact && v != .lectureCompact
        repliDepuisRangee = lien && avant == .lectureMinuteur && v == .lectureCompact
        let delai = ferme ? 0.22 : (ouvre ? 0.12 : 0.10)
        if !lien {
            if fa != .autre { dernierMode[fa] = min(1, max(0, modeAvant)); sortir(&apparitionsFamille[fa]) }
            if fv != .autre { entrer(&apparitionsFamille[fv], delai: delai) }
        }
        // d'une carte à l'autre de la pile (lecture, Centre, accueil) : le contenu glisse dans le sens du passage, comme une page
        let pile = cartes
        var glisse = 0.0
        if avant != v, !reduire, let i = Self.rang(avant, pile), let j = Self.rang(v, pile), i != j { glisse = j > i ? 1 : -1 }
        // d'une carte à l'autre, la nouvelle arrive plus tôt (l'ancienne part en 0,15 s) : pas de trou noir entre les deux
        let delaiContenu = glisse != 0 ? 0.06 : delai
        // un écran fait de plusieurs couches (la lecture + sa rangée) : seules les couches qui changent partent ou arrivent
        if avant != v { for c in Self.couches(avant) where !Self.couches(v).contains(c) { sortir(&apparitions[c], glisse: glisse) } }
        for c in Self.couches(v) { entrer(&apparitions[c], delai: delaiContenu, glisse: glisse) }
        if avant != v, v == resolution.survol || v == .accueil || v == .rappelListe || v == .etagere || v == .centre { surDepliage() }
    }

    /// Les couches de contenu d'un écran : la rangée Minuteur se pose sous la lecture dépliée, qui ne s'efface pas pour autant.
    static func couches(_ v: VueIlot) -> [VueIlot] { v == .lectureMinuteur ? [.lectureEtendu, .lectureMinuteur] : [v] }
    /// La place d'un écran dans la pile des cartes (la rangée Minuteur compte comme la lecture).
    static func rang(_ v: VueIlot, _ pile: [VueIlot]) -> Int? { pile.firstIndex(of: v == .lectureMinuteur ? .lectureEtendu : v) }
    /// La forme passe de la lecture dépliée à la lecture + rangée (ou l'inverse) : la pochette ne bouge pas.
    private var glisseLecture = false
    /// La lecture + rangée se replie d'un coup en compact : la pochette se règle sur la hauteur de la rangée (sinon, partie de 262 pt
    /// pour une référence de 208, elle « rebondirait » de 30 % au premier instant du repli).
    private var repliDepuisRangee = false

    // MARK: horloge du contenu

    private func opaciteActuelle(_ a: ApparitionIlot?) -> Double { a.map { aspect($0, rang: 0).opacite } ?? 0 }
    private func entrer(_ a: inout ApparitionIlot?, delai: Double, glisse: Double = 0) {
        if let x = a, x.entre { return }
        a = ApparitionIlot(debut: tAnim, entre: true, delai: delai, depart: opaciteActuelle(a), glisse: glisse)
    }
    private func sortir(_ a: inout ApparitionIlot?, glisse: Double = 0) {
        guard let x = a, x.entre else { return }
        a = ApparitionIlot(debut: tAnim, entre: false, delai: 0, depart: opaciteActuelle(x), glisse: glisse)
    }

    /// L'aspect d'un élément de rang `rang` (0 = le premier de la cascade, un bloc toutes les 35 ms). `voyage` : sans zoom (la pièce
    /// garde sa taille, c'est son cadre qui change).
    func aspect(_ a: ApparitionIlot, rang: Int, voyage: Bool = false) -> AspectIlot {
        let t = tAnim - a.debut
        if reduire {
            let p = CourbesIlot.borne(t / 0.15)
            let op = a.entre ? a.depart + (1 - a.depart) * p : a.depart * (1 - p)
            return AspectIlot(opacite: op, flou: 0, echelle: 1)
        }
        if a.entre {
            let t0 = t - (a.delai + 0.035 * Double(rang))
            let r = a.depart
            let op = r + (1 - r) * CourbesIlot.ease(t0 / 0.26)
            let flou = 8 * (1 - r) * (1 - CourbesIlot.ease(t0 / 0.30))
            let ech = voyage ? 1 : 1 - 0.08 * (1 - r) * (1 - CourbesIlot.ressort(t0))
            // la carte qui arrive vient d'en dessous (on descend dans la pile) ou d'au-dessus, 22 pt, sur le ressort du zoom
            let dec = Self.glisseCarte * a.glisse * (1 - CourbesIlot.ressort(t0))
            return AspectIlot(opacite: op, flou: CGFloat(flou), echelle: CGFloat(ech), decalage: CGFloat(dec))
        }
        let p = CourbesIlot.ease(t / 0.15)
        return AspectIlot(opacite: a.depart * (1 - p), flou: CGFloat(8 * p), echelle: voyage ? 1 : CGFloat(1 - 0.06 * p),
                          decalage: CGFloat(-Self.glisseCarte * a.glisse * p))
    }
    func aspect(_ v: VueIlot, rang: Int) -> AspectIlot { apparitions[v].map { aspect($0, rang: rang) } ?? .cache }
    func aspect(_ f: FamilleIlot) -> AspectIlot { apparitionsFamille[f].map { aspect($0, rang: 0, voyage: true) } ?? .cache }
    func aspect(_ e: ExtraIlot, rang: Int = 0) -> AspectIlot { apparitionsExtra[e].map { aspect($0, rang: rang) } ?? .cache }
    func visible(_ e: ExtraIlot) -> Bool { apparitionsExtra[e].map(enCours) ?? false }
    /// Le glissé d'une carte qui arrive (maquette : 26 pt ; un peu moins ici, la forme bouge déjà).
    static let glisseCarte = 22.0
    /// Faut-il dessiner cet écran (ou cette famille) ? Oui tant qu'il est là ou qu'il n'a pas fini de partir.
    func visible(_ v: VueIlot) -> Bool { apparitions[v].map(enCours) ?? false }
    func visible(_ f: FamilleIlot) -> Bool { apparitionsFamille[f].map(enCours) ?? false }
    private func enCours(_ a: ApparitionIlot) -> Bool { a.entre || tAnim - a.debut < 0.16 }
    private func fini(_ a: ApparitionIlot) -> Bool {
        let t = tAnim - a.debut
        return a.entre ? t > a.delai + 0.035 * 4 + 0.47 : t > 0.16
    }
    private var contenuPose: Bool {
        apparitions.values.allSatisfy(fini) && apparitionsFamille.values.allSatisfy(fini) && apparitionsExtra.values.allSatisfy(fini) && fini(apparitionPastille)
    }

    /// Ouverture d'une famille : 0 = au repos dans les ailes, 1 = dépliée (peut dépasser un peu au rebond). C'est la hauteur réelle de la
    /// forme qui la donne quand la forme passe d'un état à l'autre de cette activité.
    func ouverture(_ f: FamilleIlot) -> Double {
        guard f == FamilleIlot.de(courante) else { return dernierMode[f] ?? 0 }
        return ouvertureCourante(f)
    }
    private func ouvertureCourante(_ f: FamilleIlot) -> Double {
        guard let (c, x0) = f.vues else { return 1 }
        // la lecture + rangée compte comme dépliée ; entre les deux états dépliés, la pochette reste posée
        let x = f == .lecture && courante == .lectureMinuteur ? .lectureMinuteur : x0
        let estEtendu: Double = courante == x ? 1 : 0
        guard lien else { return estEtendu }
        if f == .lecture, glisseLecture { return 1 }
        let ref = f == .lecture && (courante == .lectureMinuteur || repliDepuisRangee) ? VueIlot.lectureMinuteur : x
        let hc = cible(c)[2], hx = cible(ref)[2]
        guard hx - hc > 1 else { return estEtendu }
        return (geo[2].x - hc) / (hx - hc)
    }

    // MARK: pastille

    /// La bulle est posée à côté de l'îlot seulement quand il est replié (pas déplié, pas d'alerte ni de bandeau qui descendent).
    var pastilleMontree: Bool {
        guard pastille != nil, !cache else { return false }
        return GeoIlot.profondeur(courante) == 0 && courante != .repos
    }
    private func majPastille() {
        let voulue = cache ? nil : resolution.pastille
        if let voulue, voulue != pastille {
            // une autre activité prend la pastille (échange) : elle repart de l'intérieur de l'îlot (noir sur noir, invisible) et goutte
            // de nouveau ; son contenu attend d'être détaché
            pastille = voulue
            pastilleChute.viser(0, reponse: 0.34, amortissement: 1); pastilleChute.poser()
            apparitionPastille = ApparitionIlot(debut: tAnim - 10, entre: false, delai: 0, depart: 0)
        }
        let montree = voulue != nil && pastilleMontree
        let avant = apparitionPastille.entre
        if montree {
            pastilleChute.viser(1, reponse: 0.5, amortissement: 0.62, attente: pastilleChute.cibleFinale > 0.5 ? 0 : 0.16)
            if !avant { apparitionPastille = ApparitionIlot(debut: tAnim, entre: true, delai: 0.42, depart: 0) }
        } else {
            pastilleChute.viser(0, reponse: 0.34, amortissement: 1)
            pastilleOuverte.cible = 0
            if avant { apparitionPastille = ApparitionIlot(debut: tAnim, entre: false, delai: 0, depart: 1) }
        }
        if reduire { pastilleChute.poser() }
    }
    private func vider() {
        if pastilleChute.fini, pastilleChute.x < 0.01, resolution.pastille == nil { pastille = nil }
    }
    /// Le contenu de la pastille (anneau et temps, pochette et égaliseur…) : il arrive une fois la goutte détachée.
    var aspectPastille: AspectIlot {
        let a = apparitionPastille, t = tAnim - a.debut
        if a.entre { return AspectIlot(opacite: CourbesIlot.ease((t - (reduire ? 0 : a.delai)) / (reduire ? 0.15 : 0.22)), flou: 0, echelle: 1) }
        return AspectIlot(opacite: 1 - CourbesIlot.ease(t / 0.12), flou: 0, echelle: 1)
    }

    // MARK: alertes et bandeaux

    /// Une alerte ou un bandeau arrive. Pendant la dictée ou la réunion, il attend la fin (aucun son qui pourrait gêner ou être capté).
    func annoncer(alerte a: AlerteIlot? = nil, bandeau b: BandeauIlot? = nil) {
        if cache { enAttente.append((a, b)); return }
        afficherMaintenant(alerte: a, bandeau: b)
    }
    private func afficherMaintenant(alerte a: AlerteIlot?, bandeau b: BandeauIlot?) {
        survole = false; epingle = false; sousVue = nil; fermerMoniteur()
        if let a { alerte = a; bandeau = nil; surArrivee(a.vue) }
        if let b { if alerte == nil { bandeau = b; if b.sonore { surArrivee(b.vue) } } }
        donneesChangees()
    }
    /// Après la dictée ou la réunion : ce qui attendait s'affiche.
    func vidangerAttente() {
        guard !cache, !enAttente.isEmpty else { return }
        let l = enAttente; enAttente = []
        // l'alerte la plus récente gagne, le dernier bandeau aussi
        if let a = l.last(where: { $0.alerte != nil })?.alerte { afficherMaintenant(alerte: a, bandeau: nil) }
        else if var b = l.last(where: { $0.bandeau != nil })?.bandeau {
            // il a attendu la fin de la dictée : il reste au moins 3 s à l'écran au lieu de clignoter, déjà échu
            b.jusqua = max(b.jusqua, maintenant().addingTimeInterval(3))
            afficherMaintenant(alerte: nil, bandeau: b)
        }
    }
    func quitterAlerte() { alerte = nil; donneesChangees() }

    // MARK: volume et luminosité

    /// L'îlot peut-il montrer une touche de volume ou de luminosité ? Pas pendant la dictée, la réunion ou une autre annonce de l'encoche
    /// (il est effacé), ni pendant une alerte (elle attend un geste), ni quand il est déplié, épinglé ou sur une carte (le lecteur ouvert
    /// se refermerait sous les doigts), ni pendant un glisser de fichiers : la touche reste alors à macOS, avec son propre affichage.
    var peutMontrerNiveau: Bool { !cache && alerte == nil && !fenetreOuverte && !depot && !glisserSortant }

    /// Une touche de volume ou de luminosité vient d'être appliquée : le bandeau reste 1,5 s après la DERNIÈRE touche ; la barre part
    /// de `avant` (la valeur d'avant la touche) et glisse sur son ressort. Une touche tenue (répétitions) prolonge le même bandeau,
    /// sans rien rejouer : seule la barre avance.
    func montrerNiveau(_ n: NiveauIlot, avant: Double, duree: TimeInterval = 1.5) {
        guard peutMontrerNiveau else { return }
        let vue: VueIlot = n.genre == .volume ? .volume : .luminosite
        let dejaLa = bandeau?.vue == vue
        derniersNiveaux[n.genre] = n
        var r = jauge(n.genre)
        if !dejaLa { r.viser(min(1, max(0, avant)), reponse: JaugeNiveau.reponse, amortissement: JaugeNiveau.amortissement); r.poser() }
        JaugeNiveau.viser(&r, vers: n.affiche, reduire: reduire)
        if n.genre == .volume { jaugeVolume = r } else { jaugeLuminosite = r }
        let b = BandeauIlot(vue: vue, jusqua: maintenant().addingTimeInterval(duree), ligne1: "", ligne2: "", niveau: n)
        if dejaLa {
            bandeau = b
            programmerReveil()
            demarrerBoucle()
        } else {
            annoncer(bandeau: b)
        }
    }
    /// Le niveau qu'un écran de volume ou de luminosité montre (celui du bandeau, sinon le dernier vu).
    func niveauVu(_ g: GenreNiveau) -> NiveauIlot {
        if let n = bandeau?.niveau, n.genre == g { return n }
        return derniersNiveaux[g] ?? NiveauIlot(genre: g, valeur: 0.5)
    }
    func quitterBandeau() { bandeau = nil; donneesChangees() }

    private func programmerReveil() {
        reveil?.cancel()
        let echeances = [alerte?.jusqua, bandeau?.jusqua].compactMap { $0 }
        guard let prochaine = echeances.min() else { return }
        let attente = max(0.02, prochaine.timeIntervalSince(maintenant()))
        let item = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.reveilleToi() } }
        reveil = item
        DispatchQueue.main.asyncAfter(deadline: .now() + attente, execute: item)
    }
    private func reveilleToi() {
        let t = maintenant()
        // un fichier est en train d'être glissé hors du bandeau : il reste (sa vue est la source du glisser) jusqu'au relâchement
        if glisserSortant, let b = bandeau, b.jusqua <= t {
            bandeau?.jusqua = t.addingTimeInterval(0.5)
            programmerReveil(); return
        }
        // la souris est dessus : on ne retire rien (même règle que la maquette), sauf le volume et la luminosité (la souris immobile
        // sur l'encoche n'a rien à voir avec les touches du clavier)
        let niveau = bandeau?.vue.estNiveau ?? false
        if pointeurSurForme, (alerte?.jusqua ?? .distantFuture) <= t || (!niveau && (bandeau?.jusqua ?? .distantFuture) <= t) {
            if alerte?.jusqua.map({ $0 <= t }) == true { alerte?.jusqua = t.addingTimeInterval(1.5) }
            if bandeau.map({ $0.jusqua <= t }) == true { bandeau?.jusqua = t.addingTimeInterval(1.5) }
            programmerReveil(); return
        }
        if let j = alerte?.jusqua, j <= t { alerte = nil; surAlerteExpiree() }
        if let j = bandeau?.jusqua, j <= t { bandeau = nil }
        donneesChangees()
    }
    var surAlerteExpiree: () -> Void = {}

    // MARK: glisser un fichier hors de l'îlot

    /// Un fichier part de l'îlot (bandeau « Téléchargé », tuile de l'étagère) : sa vue est la source du glisser, elle ne doit pas
    /// disparaître en route. Le bandeau reste, la carte ne se referme pas, et la zone de dépôt ne s'ouvre pas pour ce glisser-là ; tout
    /// redevient normal au relâchement du bouton (regardé toutes les 0,25 s, seulement pendant le glisser).
    private(set) var glisserSortant = false
    /// Le bouton de la souris est-il enfoncé ? (Injectable : les essais simulent le glisser sans toucher à la souris.)
    var boutonEnfonce: () -> Bool = { NSEvent.pressedMouseButtons & 1 != 0 }
    private var suiviSortant: DispatchWorkItem?
    func glisserSortantCommence() {
        glisserSortant = true
        intention?.cancel(); fermeture?.cancel()
        surveillerSortant()
    }
    private func surveillerSortant() {
        suiviSortant?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.glisserSortant else { return }
                if self.boutonEnfonce() { self.surveillerSortant(); return }
                self.glisserSortantFini()
            }
        }
        suiviSortant = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: item)
    }
    private func glisserSortantFini() {
        glisserSortant = false; suiviSortant?.cancel(); suiviSortant = nil
        // le bandeau se retire une seconde après (le temps de voir le fichier arrivé) ; la carte se referme si la souris est partie
        if let b = bandeau, b.jusqua < maintenant().addingTimeInterval(1) { bandeau?.jusqua = maintenant().addingTimeInterval(1) }
        programmerReveil()
        if !pointeurSurForme { survolForme(false) }
    }

    // MARK: souris

    /// La souris est sur la forme (`true`) ou en est sortie. Elle s'ouvre après l'intention (l'îlot vide aussi : sur le Centre). Revenue
    /// pendant que la forme se referme : elle repart vers l'ouvert tout de suite, depuis sa vitesse.
    func survolForme(_ dedans: Bool) {
        pointeurSurForme = dedans
        fermeture?.cancel(); intention?.cancel()
        guard !cache, !resolution.verrou else { return }
        if dedans {
            if survole || epingle { return }
            if resolution.survol != nil, geo[2].x > geo[2].cibleFinale + 2 {
                survole = true; donneesChangees(); surDepliageMoniteur(); return
            }
            let item = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { guard let self, self.pointeurSurForme else { return }; self.survole = true; self.donneesChangees(); self.surDepliageMoniteur() } }
            intention = item
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.delaiIntention, execute: item)
        } else {
            guard survole || epingle else { return }
            if epingle { return }
            let item = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { guard let self, !self.epingle, !self.pointeurSurForme, !self.glisserSortant, !self.depot else { return }; self.survole = false; self.sousVue = nil; self.donneesChangees(); self.fermerMoniteur() } }
            fermeture = item
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.delaiFermeture, execute: item)
        }
    }
    var fenetreOuverte: Bool { survole || epingle || sousVue != nil }

    /// Clic sur la forme (hors boutons) : épingle ou relâche l'état déplié. L'îlot vide s'ouvre sur le Centre.
    func clicForme() {
        guard !cache, !resolution.verrou, resolution.survol != nil else { return }
        intention?.cancel(); fermeture?.cancel()
        if epingle { fermer(); return }
        epingle = true; survole = true
        donneesChangees(); surDepliageMoniteur()
    }
    /// L'îlot est enfoncé sous le doigt (il gonfle un peu), en attendant l'appui long.
    private(set) var presse = false
    func appuyer(_ oui: Bool) {
        let voulu = oui && !cache && FamilleIlot.de(courante) == .lecture && courante != .lectureMinuteur
        guard voulu != presse else { return }
        presse = voulu; rev += 1
    }
    /// Le bouton de la souris s'enfonce sur la forme (hors boutons). Relâché avant 0,4 s : un clic (`clicForme`) ; tenu 0,4 s : l'appui
    /// long, déclenché pendant que le bouton est encore enfoncé (comme sur l'iPhone). Un seul geste SwiftUI pour les deux : sur le Mac,
    /// le clic de SwiftUI prenait le dessus sur son appui long, qui ne se déclenchait jamais.
    private var minuterieAppui: DispatchWorkItem?
    private var appuiEnCours = false
    private var appuiLongFait = false
    private var appuiDeplace = false
    private var origineAppui: CGPoint?
    static let dureeAppuiLong: TimeInterval = 0.4
    /// Appelé à chaque mouvement du bouton enfoncé : `origine` (le point d'appui) distingue un nouvel appui d'un ancien resté en plan
    /// (relâchement jamais reçu) ; `distance` au-delà de 12 pt annule l'appui long (on ne l'ouvre pas pointeur parti).
    func debutAppui(origine: CGPoint = .zero, distance: CGFloat = 0) {
        if appuiEnCours, origine != origineAppui { annulerAppui() }
        if appuiEnCours {
            if distance > 12, !appuiDeplace { minuterieAppui?.cancel(); minuterieAppui = nil; appuiDeplace = true; appuyer(false) }
            return
        }
        appuiEnCours = true; appuiLongFait = false; appuiDeplace = false; origineAppui = origine
        appuyer(true)
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { guard let self, self.appuiEnCours else { return }; self.appuiLongFait = self.appuiLong() }
        }
        minuterieAppui = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.dureeAppuiLong, execute: item)
    }
    /// Le bouton remonte. `deplace` : la souris a glissé de plus de 12 pt (ni clic ni appui long).
    func finAppui(deplace: Bool) {
        guard appuiEnCours else { return }
        let long = appuiLongFait, glisse = deplace || appuiDeplace
        annulerAppui()
        if !long, !glisse { clicForme() }
    }
    /// Oublie l'appui en cours (la fenêtre a disparu sous le doigt, pendant une dictée : le relâchement n'arrivera jamais).
    func annulerAppui() {
        minuterieAppui?.cancel(); minuterieAppui = nil
        appuiEnCours = false; appuiLongFait = false; appuiDeplace = false; origineAppui = nil
        appuyer(false)
    }

    /// Appui long (0,4 s) sur la lecture : sous elle, la rangée Minuteur de l'accueil (comme l'appui long sur la Dynamic Island).
    /// Faux si rien ne s'est passé (pas de lecture, minuteur éteint dans les réglages, îlot verrouillé).
    @discardableResult
    func appuiLong(minuteurActif: Bool = Settings.ilotMinuteur) -> Bool {
        presse = false; rev += 1
        guard minuteurActif, !cache, !resolution.verrou, FamilleIlot.de(resolution.principal) == .lecture else { return false }
        intention?.cancel(); fermeture?.cancel()
        sousVue = .lectureMinuteur; epingle = true; survole = true
        donneesChangees(); surDepliageMoniteur()
        return true
    }

    func fermer() {
        epingle = false; survole = false; sousVue = nil
        intention?.cancel()
        donneesChangees(); fermerMoniteur()
    }

    /// La souris est sur la pastille : elle grossit un peu (et la lecture montre son titre) après 0,14 s ; elle revient 0,16 s après.
    private var delaiPastille: DispatchWorkItem?
    func survolPastille(_ dedans: Bool) {
        delaiPastille?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.pastilleOuverte.cible = dedans ? 1 : 0; self?.demarrerBoucle(); self?.surFenetre() }
        }
        delaiPastille = item
        DispatchQueue.main.asyncAfter(deadline: .now() + (dedans ? 0.14 : 0.16), execute: item)
    }
    /// Clic sur la pastille : les deux activités échangent leur place.
    func cliquerPastille() {
        guard let p = pastille else { return }
        echange = p
        pastilleOuverte.cible = 0
        survole = false; epingle = false; sousVue = nil
        donneesChangees(); fermerMoniteur()
    }

    // MARK: étagère

    /// Un glisser de fichiers approche de l'encoche (ou s'en éloigne) : l'îlot s'ouvre en « Déposez ici », puis revient où il en était.
    /// Rien pendant la dictée ou la réunion (l'îlot est effacé), ni si l'étagère est éteinte dans les réglages.
    func montrerDepot(_ oui: Bool) {
        finDepot?.cancel(); finDepot = nil
        let voulu = oui && etagereActive && !cache
        if !voulu { depotSurvole = false }
        guard voulu != depot else { return }
        depot = voulu
        if voulu { intention?.cancel(); fermeture?.cancel() }
        donneesChangees()
    }
    /// Les fichiers sont lâchés sur l'îlot : la zone s'éteint, les nouveaux paraissent parmi les derniers rangés (un coup d'œil de
    /// 0,9 s), puis l'îlot revient où il en était. Un seul réveil, aucune minuterie.
    func depotTermine(apres: TimeInterval = 0.9) {
        depotSurvole = false
        // lâché sur le Centre : il reste ouvert (un geste, comme un clic sur un bouton)
        if centreOuvert { epinglerLeCentre() }
        finDepot?.cancel()
        let item = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.montrerDepot(false) } }
        finDepot = item
        DispatchQueue.main.asyncAfter(deadline: .now() + apres, execute: item)
    }
    /// La ligne « Étagère » de l'accueil : la carte des fichiers gardés.
    func ouvrirEtagere() {
        guard etagereActive, !cache else { return }
        sousVue = .etagere; epingle = true; survole = true
        donneesChangees(); surDepliageMoniteur()
    }

    func ouvrirFormulaireRappel() {
        sousVue = .rappelListe; epingle = true; survole = true
        donneesChangees(); surDepliageMoniteur()
    }

    // MARK: cartes (lecture, Centre, accueil)

    /// Les cartes de l'îlot ouvert, de haut en bas (vide quand il est verrouillé par une alerte ou un bandeau).
    var cartes: [VueIlot] { cache ? [] : CartesIlot.pile(survol: resolution.verrou ? nil : resolution.survol) }
    /// La carte montrée (nil : îlot replié, ou un écran hors de la pile, comme la carte Étagère).
    var carteCourante: VueIlot? {
        guard fenetreOuverte, let i = Self.rang(courante, cartes) else { return nil }
        return cartes[i]
    }
    /// Le Centre est à l'écran (ou y arrive).
    var centreOuvert: Bool { courante == .centre }

    /// Passe à une carte de la pile (bouton « Centre », points de page, défilement). L'îlot reste ouvert ; épinglé, il le reste.
    func allerA(_ carte: VueIlot) {
        guard !cache, !resolution.verrou, cartes.contains(carte) else { return }
        intention?.cancel(); fermeture?.cancel()
        // depuis la lecture vers le Centre : l'aide « Fais défiler ou clique ici » a servi
        if carte == .centre, carteCourante == .lectureEtendu, aideCentre { aideCentre = false; surCentreUtilise() }
        // la première carte d'une activité est son déplié (pas de sous-vue) ; le Centre et l'accueil sont gardés tels quels, même si une
        // activité commence pendant qu'ils sont ouverts
        sousVue = carte == cartes.first && carte != .centre ? nil : carte
        survole = true
        donneesChangees(); surDepliageMoniteur()
    }
    /// Une carte plus bas (+1) ou plus haut (−1). Depuis la carte Étagère (ouverte depuis le Centre), on revient au Centre.
    func defiler(_ pas: Int) {
        // « Modifier » : on range les boutons, la molette ne change pas de carte
        guard fenetreOuverte, !cache, !resolution.verrou, !editionCentre else { return }
        if courante == .etagere { allerA(.centre); return }
        guard let c = carteCourante, let v = CartesIlot.voisine(cartes, de: c, pas: pas) else { return }
        allerA(v)
    }
    /// Un événement de défilement (molette, deux doigts) sur l'îlot ouvert : un geste = une carte, l'inertie ignorée.
    func recevoirDefilement(dy: Double, dx: Double, phase: DefilementIlot.Phase, inertie: Bool, t: Double = ProcessInfo.processInfo.systemUptime) {
        guard fenetreOuverte, !cache else { return }
        if let pas = defilement.recevoir(dy: dy, dx: dx, phase: phase, inertie: inertie, t: t) { defiler(pas) }
    }
    /// Un clic sur un bouton du Centre : l'îlot reste ouvert (« Reste ouvert ») pour enchaîner d'autres réglages ; il se range au clic
    /// ailleurs ou d'un clic sur la forme.
    func epinglerLeCentre() {
        guard !cache, !resolution.verrou else { return }
        intention?.cancel(); fermeture?.cancel()
        if courante == .centre, sousVue == nil { sousVue = .centre }
        guard !epingle else { return }
        epingle = true; survole = true
        rev += 1
        surDepliageMoniteur()
    }

    // MARK: ce qui s'ajoute aux écrans (pied de la lecture, points de page, bulle « Nouveau »)

    private func majExtras() {
        let pile = cartes
        let pied = courante == .lectureEtendu && pile.contains(.centre)
        let points = [.lectureEtendu, .centre, .accueil].contains(courante) && pile.count > 1 && fenetreOuverte
        let bulle = bulleSous(courante)
        for (e, voulu) in [(ExtraIlot.pied, pied), (.points, points), (.bulle, bulle)] {
            if voulu { entrer(&apparitionsExtra[e], delai: e == .bulle ? 0.2 : 0.14) } else { sortir(&apparitionsExtra[e]) }
        }
    }

    /// La bulle se pose-t-elle sous cet écran ? Seulement sous l'îlot replié (ou vide), sans bulle d'une 2e activité à côté, et tant
    /// que rien ne s'ouvre ni ne s'annonce.
    func bulleSous(_ v: VueIlot) -> Bool {
        bulleNouveau && !cache && !fenetreOuverte && !depot && !resolution.verrou && resolution.pastille == nil && GeoIlot.profondeur(v) == 0
    }
    /// Premier lancement : la bulle « Nouveau : survole l'îlot », une seule fois. Elle part quand l'îlot s'ouvre, ou d'elle-même après
    /// `duree` secondes (un seul réveil, aucune minuterie).
    func montrerBulle(duree: TimeInterval = 12) {
        guard !bulleNouveau else { return }
        bulleNouveau = true
        finBulle?.cancel()
        let item = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { guard let self, self.bulleNouveau else { return }; self.cacherBulle(); self.donneesChangees() } }
        finBulle = item
        DispatchQueue.main.asyncAfter(deadline: .now() + duree, execute: item)
        donneesChangees()
    }
    private func cacherBulle() {
        guard bulleNouveau else { return }
        bulleNouveau = false
        finBulle?.cancel(); finBulle = nil
        surBulleVue()
    }

    // clic ailleurs : refermer (installé par le panneau)
    var surMoniteur: (Bool) -> Void = { _ in }
    private func surDepliageMoniteur() { surMoniteur(true) }
    private func fermerMoniteur() { surMoniteur(false) }

    // MARK: ressorts et boucle

    var boucleActive: Bool { cadence.active }
    /// Ce qui bouge encore (diagnostic des essais).
    var ceQuiBouge: String {
        var l: [String] = []
        for (i, r) in geo.enumerated() where !r.fini { l.append("geo[\(i)] \(r.x)→\(r.cible)") }
        if !secousse.fini { l.append("secousse") }
        if !jaugeVolume.fini { l.append("barre du volume \(jaugeVolume.x)→\(jaugeVolume.cible)") }
        if !jaugeLuminosite.fini { l.append("barre de la luminosité \(jaugeLuminosite.x)→\(jaugeLuminosite.cible)") }
        if !pastilleChute.fini { l.append("bulle \(pastilleChute.x)→\(pastilleChute.cible)") }
        if !pastilleOuverte.fini { l.append("bulle ouverte \(pastilleOuverte.x)→\(pastilleOuverte.cible)") }
        if !contenuPose { l.append("contenu (apparitions)") }
        if !apparitionsExtra.values.allSatisfy(fini) { l.append("extras \(apparitionsExtra.filter { !fini($0.value) }.keys.map { "\($0)" })") }
        return l.isEmpty ? "rien" : l.joined(separator: ", ")
    }
    private var tousLesRessorts: Bool {
        geo.allSatisfy(\.fini) && secousse.fini && pastilleChute.fini && pastilleOuverte.fini && jaugeVolume.fini && jaugeLuminosite.fini && contenuPose
    }
    /// La boucle d'animation, calée sur l'écran (CADisplayLink : 60 ou 120 images par seconde), ne tourne que si quelque chose bouge.
    func demarrerBoucle() {
        rev += 1
        if tousLesRessorts { cadence.arreter(); return }
        guard !cadence.active else { return }
        dernierPas = ProcessInfo.processInfo.systemUptime
        cadence.demarrer()
    }
    private func pas() {
        let t = ProcessInfo.processInfo.systemUptime
        let dt = min(0.05, max(0.001, t - dernierPas))
        dernierPas = t
        avancer(dt)
    }
    func avancer(_ dt: Double) {
        tAnim += dt
        for i in 0..<geo.count { if geo[i].fini { geo[i].poser() } else { geo[i].avancer(dt) } }
        if secousse.fini { secousse.poser() } else { secousse.avancer(dt) }
        if pastilleChute.fini { pastilleChute.poser() } else { pastilleChute.avancer(dt) }
        if pastilleOuverte.fini { pastilleOuverte.poser() } else { pastilleOuverte.avancer(dt) }
        if jaugeVolume.fini { jaugeVolume.poser() } else { jaugeVolume.avancer(dt) }
        if jaugeLuminosite.fini { jaugeLuminosite.poser() } else { jaugeLuminosite.avancer(dt) }
        rev += 1
        if tousLesRessorts { cadence.arreter(); vider(); surFenetre() }
    }

    /// Tout est posé tout de suite à sa place (rendus PNG, essais) : ressorts sur leur cible, fondus terminés.
    func poser() {
        for i in 0..<geo.count { geo[i].poser() }
        secousse.poser(); pastilleChute.poser(); pastilleOuverte.poser(); jaugeVolume.poser(); jaugeLuminosite.poser()
        tAnim += 30
        cadence.arreter()
        rev += 1
    }

    /// Le bourdonnement de l'alerte : trois secousses latérales (maquette : vitesses +150, −120, +90 px/s à 0, 230 et 460 ms).
    func bourdonner() {
        guard !reduire else { return }
        for (i, d) in [0.0, 0.23, 0.46].enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + d) { [weak self] in
                MainActor.assumeIsolated { guard let self else { return }; self.secousse.v = Double(i % 2 == 1 ? -1 : 1) * Double(150 - i * 30); self.demarrerBoucle() }
            }
        }
    }

    // MARK: mesures (fenêtre, tests)

    var demiCamera: CGFloat { geometrie.largeur / 2 }

    /// La forme actuelle (points) pour le dessin.
    var trace: TraceIlot.Points {
        TraceIlot.calculer(geo.map(\.x), demiCamera: Double(demiCamera), barre: Double(geometrie.hauteur))
    }
    var traceCible: TraceIlot.Points {
        TraceIlot.calculer(geo.map(\.cibleFinale), demiCamera: Double(demiCamera), barre: Double(geometrie.hauteur))
    }
    /// Le rectangle de la forme au point voulu (x depuis le centre, y depuis le haut de l'écran).
    func rectCible() -> CGRect {
        let p = traceCible
        let w = max(p.corps, p.bande)
        return CGRect(x: -w, y: 0, width: 2 * w, height: p.hauteur)
    }
    func rectActuel() -> CGRect {
        let p = trace
        let w = max(p.corps, p.bande)
        return CGRect(x: -w, y: 0, width: 2 * w, height: p.hauteur)
    }
    /// La souris est-elle sur la forme elle-même (pas sur le vide à côté du cou, où sont les menus) ?
    func contient(_ point: CGPoint) -> Bool {
        // rectangle centré sur 0 : les coordonnées du chemin sont celles du point (x depuis le centre, y depuis le haut)
        let chemin = FormeNoire(points: trace).path(in: CGRect(x: -IlotMoteur.largeur / 2, y: 0, width: IlotMoteur.largeur, height: IlotMoteur.hauteurMax))
        return chemin.contains(point) || chemin.contains(CGPoint(x: point.x, y: point.y + 1.5))
    }

    /// La forme visée, élargie de `marge` points tout autour (la zone de dépôt ne se perd pas en la visant, mais le vide de la fenêtre
    /// loin de la forme, à côté du cou dans la barre, n'en fait pas partie).
    func contient(_ point: CGPoint, marge: CGFloat) -> Bool {
        let chemin = FormeNoire(points: traceCible).path(in: CGRect(x: -IlotMoteur.largeur / 2, y: 0, width: IlotMoteur.largeur, height: IlotMoteur.hauteurMax))
        return chemin.contains(point) || chemin.strokedPath(StrokeStyle(lineWidth: 2 * marge, lineCap: .round, lineJoin: .round)).contains(point)
    }

    /// La pastille, devenue « bulle » (maquette ilot-apple.html, comme les deux activités de la Dynamic Island) : À DROITE de l'îlot,
    /// à la même hauteur que lui, accrochée au haut de l'écran, séparée par une fente de `ecartBulle` pt. Elle s'ouvre vers la droite.
    func largeurPastille(_ a: ActiviteIlot) -> CGFloat {
        switch a {
        case .lecture: return 62
        case .minuteur: return 74
        case .rendezVous: return 84
        case .rappel: return 76
        // le micro barré et « Coupé », mesurés : 10 + glyphe + 6 + texte + 10
        case .micro: return 26 + MesureIlot.symbole("mic.slash.fill", 12) + MesureIlot.texte("Coupé", 12.5, .semibold)
        // l'étoile, puis « 3 sur 7 » (ou « Attend ») s'il y a quelque chose à dire : 10 + 13 + 6 + texte + 10
        case .claude:
            let t = texteClaude(claude ?? dernierClaude, taille: 12.5)
            return t.isEmpty ? 33 : 39 + MesureIlot.texte(t, 12.5, .semibold, chiffres: true)
        case .alerte: return 30
        }
    }
    /// Ouverte au survol : la lecture montre son titre, le rappel le sien (à côté de la cloche et de l'heure).
    func largeurPastilleOuverte(_ a: ActiviteIlot) -> CGFloat {
        switch a {
        case .lecture: return 62 + 150
        case .rappel: return largeurPastille(a) + 6 + min(150, MesureIlot.texte(rappelVu?.texte ?? "", 12.5, .semibold))
        default: return largeurPastille(a)
        }
    }
    /// La fente entre l'îlot et la bulle (bord du cou → bord gauche de la bulle) : l'épaule de l'îlot (6 pt) y tient, il reste 5 pt.
    static let ecartBulle: CGFloat = 11
    /// Hauteur de la bulle : celle de l'îlot replié, c'est-à-dire la barre des menus.
    var hauteurPastille: CGFloat { geometrie.hauteur }
    /// Bord gauche de la bulle posée (depuis le centre) : le cou de l'îlot tel qu'il est dessiné, plus la fente.
    var bordPastille: CGFloat { CGFloat(trace.cou) + Self.ecartBulle }
    func largeurPastilleActuelle(_ a: ActiviteIlot) -> CGFloat {
        largeurPastille(a) + (largeurPastilleOuverte(a) - largeurPastille(a)) * CGFloat(min(1, max(0, pastilleOuverte.x)))
    }
    /// Bord gauche de la bulle selon sa sortie (`pastilleChute` : 0 = rangée sous l'aile droite de l'îlot, noir sur noir ; 1 = posée).
    func xPastille(_ a: ActiviteIlot) -> CGFloat {
        let rentree = CGFloat(trace.cou) - largeurPastille(a)
        return rentree + (bordPastille - rentree) * CGFloat(pastilleChute.x)
    }
    func rectPastille() -> CGRect? {
        // tant que la bulle n'est pas sortie, sa place ne prend aucun clic (l'icône de la barre à côté reste cliquable)
        guard let p = pastille, pastilleMontree, pastilleChute.x >= 0.5 else { return nil }
        return CGRect(x: bordPastille, y: 0, width: largeurPastilleActuelle(p), height: hauteurPastille)
    }
    /// Le rectangle que la fenêtre doit couvrir (centre = 0) : la forme voulue, la pastille et une marge pour l'ombre et la secousse.
    func fenetreVoulue() -> CGRect {
        var r = rectCible()
        if let p = rectPastille(), !cache {
            let l = largeurPastilleOuverte(pastille ?? .minuteur)
            r = r.union(CGRect(x: CGFloat(traceCible.cou) + Self.ecartBulle, y: 0, width: l + 6, height: p.height))
        }
        // au repos ou en compact : à peine plus que la forme (aucun clic pris aux icônes voisines) ; déplié : de la place pour l'ombre
        let petit = r.height <= CGFloat(geometrie.hauteur) + 40
        let cote: CGFloat = petit ? 2 : 18, bas: CGFloat = petit ? 6 : 30
        return CGRect(x: r.minX - cote, y: 0, width: r.width + 2 * cote, height: r.height + bas)
    }
}

/// La cadence de la boucle d'animation : un CADisplayLink de l'écran (calé sur son rafraîchissement, 120 Hz sur un écran ProMotion),
/// une minuterie à 60 Hz s'il n'y a pas d'écran. Arrêtée dès que tout est posé.
final class CadenceEcran: NSObject {
    private var lien: CADisplayLink?
    private var minuterie: Timer?
    var tic: () -> Void = {}
    var active: Bool { lien != nil || minuterie != nil }
    /// Les essais (`--ilot-essai`) tournent sur la minuterie : écran éteint, le lien de l'écran ne bat plus et rien ne bougerait.
    nonisolated(unsafe) static var minuterieSeulement = false
    func demarrer() {
        guard !active else { return }
        if !Self.minuterieSeulement, let ecran = NSScreen.screens.first {
            let l = ecran.displayLink(target: self, selector: #selector(image(_:)))
            l.add(to: .main, forMode: .common)
            lien = l
        } else {
            let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tic() }
            RunLoop.main.add(t, forMode: .common)
            minuterie = t
        }
    }
    @objc private func image(_ l: CADisplayLink) { tic() }
    func arreter() { lien?.invalidate(); lien = nil; minuterie?.invalidate(); minuterie = nil }
}
