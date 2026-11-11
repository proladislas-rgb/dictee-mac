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
}

/// Ce que montre le bandeau « Téléchargé » : la rafale (noms, tailles, AirDrop) et les icônes du Finder, lues une fois à l'annonce.
struct TelechargementIlot {
    var rafale: RafaleTelechargements
    var icones: [NSImage]
    var urls: [URL] { rafale.fichiers.map(\.url) }
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
    /// « Ouvrir » sur le bandeau Téléchargé : le fichier (un seul) ou le Finder sur les fichiers (plusieurs).
    case fichiersOuvrir([URL])
}

/// Les activités dont le contenu voyage d'un état à l'autre (la pochette, l'anneau et l'heure du minuteur, la cloche, le calendrier) :
/// une seule pièce qui grandit et glisse à sa place, jamais deux qui se croisent.
enum FamilleIlot: CaseIterable {
    case lecture, minuteur, rappel, agenda, autre
    static func de(_ v: VueIlot) -> FamilleIlot {
        switch v {
        case .lectureCompact, .lectureEtendu, .lectureMinuteur: return .lecture
        case .minuteurMinimal, .minuteurCompact, .minuteurEtendu: return .minuteur
        case .rappelCompact, .rappelEtendu: return .rappel
        case .agendaCompact, .agendaEtendu: return .agenda
        default: return .autre
        }
    }
    var vues: (compact: VueIlot, etendu: VueIlot)? {
        switch self {
        case .lecture: return (.lectureCompact, .lectureEtendu)
        case .minuteur: return (.minuteurCompact, .minuteurEtendu)
        case .rappel: return (.rappelCompact, .rappelEtendu)
        case .agenda: return (.agendaCompact, .agendaEtendu)
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
}

/// Ce qu'un élément montre à un instant : opacité, flou, zoom (maquette : fondu 0,26 s, flou 8 → 0 en 0,30 s, zoom 0,92 → 1 en 0,46 s
/// sur un ressort ; départ : 0,15 s).
struct AspectIlot {
    var opacite: Double
    var flou: CGFloat
    var echelle: CGFloat
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
    static let hauteurMax: CGFloat = 330

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
    private(set) var resolution = ResolutionIlot(principal: .repos, survol: .accueil, verrou: false, pastille: nil)
    /// Les sept ressorts de la forme (voir `GeoIlot`).
    var geo: [RessortIlot]
    /// Horloge d'animation (secondes) : elle n'avance que pendant que la boucle tourne ; le contenu se règle sur elle.
    private(set) var tAnim: Double = 0
    private(set) var apparitions: [VueIlot: ApparitionIlot] = [:]
    private(set) var apparitionsFamille: [FamilleIlot: ApparitionIlot] = [:]
    /// La forme passe d'un état à l'autre de la même activité : ce qui existe déjà voyage (sinon il apparaît à sa place).
    private(set) var lien = false
    private var dernierMode: [FamilleIlot: Double] = [:]
    var secousse = RessortIlot(0, reponse: 0.17, amortissement: 0.13)
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
        e.alerte = alerte?.vue
        e.bandeau = bandeau?.vue
        return e
    }

    /// Tout a pu changer : on recalcule qui a l'îlot, qui a la pastille, et on déforme la forme vers la nouvelle cible.
    func donneesChangees() {
        if cache {
            if appuiEnCours { annulerAppui() }
            if resolution.principal != .repos || courante != .repos || pastille != nil {
                resolution = ResolutionIlot(principal: .repos, survol: nil, verrou: true, pastille: nil)
                epingle = false; survole = false; sousVue = nil
                afficher(.repos)
                majPastille()
            }
            surFenetre(); demarrerBoucle()
            return
        }
        vider()
        let ancien = resolution
        resolution = ArbitrageIlot.resoudre(etat, echange: echange)
        if let e = echange, resolution.pastille != e, ArbitrageIlot.ordre(etat).contains(e) == false { echange = nil }
        if resolution.verrou { epingle = false; survole = false; sousVue = nil }
        if ancien.principal != resolution.principal, !(survole || epingle) { sousVue = nil }
        if sousVue == .lectureMinuteur, FamilleIlot.de(resolution.principal) != .lecture || resolution.verrou { sousVue = nil }
        let voulu = sousVue ?? ((survole || epingle) && resolution.survol != nil && !resolution.verrou ? resolution.survol! : resolution.principal)
        afficher(voulu)
        majPastille()
        programmerReveil()
        surFenetre()
        demarrerBoucle()
    }

    /// Largeur mesurée du contenu des écrans qui s'y ajustent (bandeaux, alertes, rendez-vous déplié). Gardée après leur départ :
    /// l'écran qui s'efface garde sa grille.
    private(set) var contenus: [VueIlot: CGFloat] = [:]
    private func cible(_ v: VueIlot) -> [Double] {
        GeoIlot.valeurs(v, hauteurBarre: Double(geometrie.hauteur), demiCamera: Double(demiCamera), contenu: contenus[v].map(Double.init), epaules: epaules)
    }
    /// La grille du contenu (mêmes largeurs que la forme).
    var grille: GrilleIlot { GrilleIlot(hc: demiCamera, barre: geometrie.hauteur, contenus: contenus, epaules: epaules) }

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
        // un écran fait de plusieurs couches (la lecture + sa rangée) : seules les couches qui changent partent ou arrivent
        if avant != v { for c in Self.couches(avant) where !Self.couches(v).contains(c) { sortir(&apparitions[c]) } }
        for c in Self.couches(v) { entrer(&apparitions[c], delai: delai) }
        if avant != v, v == resolution.survol || v == .accueil || v == .rappelListe { surDepliage() }
    }

    /// Les couches de contenu d'un écran : la rangée Minuteur se pose sous la lecture dépliée, qui ne s'efface pas pour autant.
    static func couches(_ v: VueIlot) -> [VueIlot] { v == .lectureMinuteur ? [.lectureEtendu, .lectureMinuteur] : [v] }
    /// La forme passe de la lecture dépliée à la lecture + rangée (ou l'inverse) : la pochette ne bouge pas.
    private var glisseLecture = false
    /// La lecture + rangée se replie d'un coup en compact : la pochette se règle sur la hauteur de la rangée (sinon, partie de 262 pt
    /// pour une référence de 208, elle « rebondirait » de 30 % au premier instant du repli).
    private var repliDepuisRangee = false

    // MARK: horloge du contenu

    private func opaciteActuelle(_ a: ApparitionIlot?) -> Double { a.map { aspect($0, rang: 0).opacite } ?? 0 }
    private func entrer(_ a: inout ApparitionIlot?, delai: Double) {
        if let x = a, x.entre { return }
        a = ApparitionIlot(debut: tAnim, entre: true, delai: delai, depart: opaciteActuelle(a))
    }
    private func sortir(_ a: inout ApparitionIlot?) {
        guard let x = a, x.entre else { return }
        a = ApparitionIlot(debut: tAnim, entre: false, delai: 0, depart: opaciteActuelle(x))
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
            return AspectIlot(opacite: op, flou: CGFloat(flou), echelle: CGFloat(ech))
        }
        let p = CourbesIlot.ease(t / 0.15)
        return AspectIlot(opacite: a.depart * (1 - p), flou: CGFloat(8 * p), echelle: voyage ? 1 : CGFloat(1 - 0.06 * p))
    }
    func aspect(_ v: VueIlot, rang: Int) -> AspectIlot { apparitions[v].map { aspect($0, rang: rang) } ?? .cache }
    func aspect(_ f: FamilleIlot) -> AspectIlot { apparitionsFamille[f].map { aspect($0, rang: 0, voyage: true) } ?? .cache }
    /// Faut-il dessiner cet écran (ou cette famille) ? Oui tant qu'il est là ou qu'il n'a pas fini de partir.
    func visible(_ v: VueIlot) -> Bool { apparitions[v].map(enCours) ?? false }
    func visible(_ f: FamilleIlot) -> Bool { apparitionsFamille[f].map(enCours) ?? false }
    private func enCours(_ a: ApparitionIlot) -> Bool { a.entre || tAnim - a.debut < 0.16 }
    private func fini(_ a: ApparitionIlot) -> Bool {
        let t = tAnim - a.debut
        return a.entre ? t > a.delai + 0.035 * 4 + 0.47 : t > 0.16
    }
    private var contenuPose: Bool {
        apparitions.values.allSatisfy(fini) && apparitionsFamille.values.allSatisfy(fini) && fini(apparitionPastille)
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
        // la souris est dessus : on ne retire rien (même règle que la maquette)
        if pointeurSurForme, (alerte?.jusqua ?? .distantFuture) <= t || (bandeau?.jusqua ?? .distantFuture) <= t {
            if alerte?.jusqua.map({ $0 <= t }) == true { alerte?.jusqua = t.addingTimeInterval(1.5) }
            if bandeau.map({ $0.jusqua <= t }) == true { bandeau?.jusqua = t.addingTimeInterval(1.5) }
            programmerReveil(); return
        }
        if let j = alerte?.jusqua, j <= t { alerte = nil; surAlerteExpiree() }
        if let j = bandeau?.jusqua, j <= t { bandeau = nil }
        donneesChangees()
    }
    var surAlerteExpiree: () -> Void = {}

    // MARK: souris

    /// La souris est sur la forme (`true`) ou en est sortie. L'accueil (îlot vide) ne s'ouvre qu'au clic ; les autres s'ouvrent après
    /// l'intention. Revenue pendant que la forme se referme : elle repart vers l'ouvert tout de suite, depuis sa vitesse.
    func survolForme(_ dedans: Bool) {
        pointeurSurForme = dedans
        fermeture?.cancel(); intention?.cancel()
        guard !cache, !resolution.verrou else { return }
        if dedans {
            guard resolution.principal != .repos else { return }
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
            let item = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { guard let self, !self.epingle, !self.pointeurSurForme else { return }; self.survole = false; self.sousVue = nil; self.donneesChangees(); self.fermerMoniteur() } }
            fermeture = item
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.delaiFermeture, execute: item)
        }
    }
    var fenetreOuverte: Bool { survole || epingle || sousVue != nil }

    /// Clic sur la forme (hors boutons) : épingle ou relâche l'état déplié. L'îlot vide s'ouvre sur l'accueil.
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

    func ouvrirFormulaireRappel() {
        sousVue = .rappelListe; epingle = true; survole = true
        donneesChangees(); surDepliageMoniteur()
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
        if !pastilleChute.fini { l.append("bulle \(pastilleChute.x)→\(pastilleChute.cible)") }
        if !pastilleOuverte.fini { l.append("bulle ouverte \(pastilleOuverte.x)→\(pastilleOuverte.cible)") }
        if !contenuPose { l.append("contenu (apparitions)") }
        return l.isEmpty ? "rien" : l.joined(separator: ", ")
    }
    private var tousLesRessorts: Bool {
        geo.allSatisfy(\.fini) && secousse.fini && pastilleChute.fini && pastilleOuverte.fini && contenuPose
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
        rev += 1
        if tousLesRessorts { cadence.arreter(); vider(); surFenetre() }
    }

    /// Tout est posé tout de suite à sa place (rendus PNG, essais) : ressorts sur leur cible, fondus terminés.
    func poser() {
        for i in 0..<geo.count { geo[i].poser() }
        secousse.poser(); pastilleChute.poser(); pastilleOuverte.poser()
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

    /// La pastille, devenue « bulle » (maquette ilot-apple.html, comme les deux activités de la Dynamic Island) : À DROITE de l'îlot,
    /// à la même hauteur que lui, accrochée au haut de l'écran, séparée par une fente de `ecartBulle` pt. Elle s'ouvre vers la droite.
    func largeurPastille(_ a: ActiviteIlot) -> CGFloat {
        switch a {
        case .lecture: return 62
        case .minuteur: return 74
        case .rendezVous: return 84
        case .rappel: return 76
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
