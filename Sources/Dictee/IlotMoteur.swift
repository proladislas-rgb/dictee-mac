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
}

/// Ce que l'îlot demande aux contrôleurs (le moteur ne sait rien du minuteur, des rappels ni du calendrier : il montre et il relaie).
enum ActionIlot {
    case minuteurLancer(minutes: Double)
    case minuteurBasculer, minuteurPlusUneMinute, minuteurArreter
    case minuteurRecommencer(minutes: Double)
    case alerteOK
    case rappelPlusTard(UUID), rappelFait(UUID), rappelAnnuler(UUID)
    case rappelFormulaire
    case rendezVousRejoindre(EvenementAgenda), rendezVousNoter(EvenementAgenda)
    case collerLaDerniereDictee
}

/// Le moteur de l'îlot : tout ce que la maquette fait dans `class Isl` (ressorts, arbitrage, survol, pastille, bandeaux, alertes), sans
/// aucune minuterie qui tourne au repos. Une boucle à 60 Hz n'existe que pendant qu'un ressort bouge ; les bandeaux et alertes ont une
/// date de fin et un seul réveil programmé.
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
    var horloge = ""

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
    var geo: [RessortIlot]
    var poids: [VueIlot: RessortIlot] = [:]
    var secousse = RessortIlot(0, reponse: 0.17, amortissement: 0.13)
    var pastilleVisible = RessortIlot(0, reponse: 0.46, amortissement: 0.78)
    var pastilleOuverte = RessortIlot(0, reponse: 0.36, amortissement: 0.88)
    private(set) var pastille: ActiviteIlot?
    private var echange: ActiviteIlot?
    var survole = false          // la souris est sur l'îlot assez longtemps
    var epingle = false
    private(set) var sousVue: VueIlot?
    private var pointeurSurForme = false
    private var intention: DispatchWorkItem?
    private var fermeture: DispatchWorkItem?
    private var reveil: DispatchWorkItem?
    private var boucle: Timer?
    private var dernierPas: TimeInterval = 0

    static let delaiIntention: TimeInterval = 0.28
    static let delaiFermeture: TimeInterval = 0.45

    init(lecture: LectureModele) {
        self.lecture = lecture
        geo = GeoIlot.valeurs(.repos, hauteurBarre: 32).map { RessortIlot($0, reponse: 0.5, amortissement: 0.84) }
        for v in VueIlot.allCases { poids[v] = RessortIlot(v == .repos ? 1 : 0, reponse: 0.26, amortissement: 1) }
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
        let voulu = sousVue ?? ((survole || epingle) && resolution.survol != nil && !resolution.verrou ? resolution.survol! : resolution.principal)
        afficher(voulu)
        majPastille()
        programmerReveil()
        surFenetre()
        demarrerBoucle()
    }

    /// Montre une vue : la forme se déforme vers sa géométrie, son calque monte pendant que les autres descendent.
    private func afficher(_ v: VueIlot) {
        let cible = GeoIlot.valeurs(v, hauteurBarre: Double(geometrie.hauteur))
        let ouvre = GeoIlot.ouvre(de: geo.map(\.cible), vers: cible)
        if v == courante, geo.enumerated().allSatisfy({ $0.element.cible == cible[$0.offset] }) { return }
        let avant = courante
        courante = v
        for i in 0..<6 {
            geo[i].cible = cible[i]
            if ouvre { geo[i].regler(reponse: 0.5, amortissement: 0.84) } else { geo[i].regler(reponse: 0.42, amortissement: 1) }
        }
        for vue in VueIlot.allCases {
            let actif = vue == v
            poids[vue]?.cible = actif ? 1 : 0
            poids[vue]?.regler(reponse: actif ? 0.34 : 0.2, amortissement: 1)
        }
        if avant != v, v == resolution.survol || v == .accueil || v == .rappelListe { surDepliage() }
    }

    // MARK: pastille

    private func majPastille() {
        let voulue = cache ? nil : resolution.pastille
        if let voulue, voulue != pastille {
            pastille = voulue
            pastilleVisible.x = min(pastilleVisible.x, 0.4); pastilleVisible.v = 0
        }
        pastilleVisible.cible = voulue == nil ? 0 : 1
        if voulue == nil { pastilleOuverte.cible = 0 }
    }
    private func vider() {
        if pastilleVisible.fini, pastilleVisible.x < 0.01, resolution.pastille == nil { pastille = nil }
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
        else if let b = l.last(where: { $0.bandeau != nil })?.bandeau { afficherMaintenant(alerte: nil, bandeau: b) }
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

    /// La souris est sur la forme (`true`) ou en est sortie. L'accueil (îlot vide) ne s'ouvre qu'au clic ; les autres s'ouvrent après l'intention.
    func survolForme(_ dedans: Bool) {
        pointeurSurForme = dedans
        fermeture?.cancel(); intention?.cancel()
        guard !cache, !resolution.verrou else { return }
        if dedans {
            guard resolution.principal != .repos else { return }
            if survole || epingle { return }
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
    func fermer() {
        epingle = false; survole = false; sousVue = nil
        intention?.cancel()
        donneesChangees(); fermerMoniteur()
    }

    /// La souris est sur la pastille (`true`) : elle se déplie après 0,14 s ; elle se replie 0,16 s après la sortie.
    private var delaiPastille: DispatchWorkItem?
    func survolPastille(_ dedans: Bool) {
        delaiPastille?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.pastilleOuverte.cible = dedans ? 1 : 0; self?.demarrerBoucle(); self?.surFenetre() }
        }
        delaiPastille = item
        DispatchQueue.main.asyncAfter(deadline: .now() + (dedans ? 0.14 : 0.16), execute: item)
    }
    /// Clic sur la pastille : une alerte patiente s'acquitte ; sinon les deux activités échangent leur place.
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

    var boucleActive: Bool { boucle != nil }
    private var tousLesRessorts: Bool {
        geo.allSatisfy(\.fini) && poids.values.allSatisfy(\.fini) && secousse.fini && pastilleVisible.fini && pastilleOuverte.fini
    }
    func demarrerBoucle() {
        if reduire { poser(); return }   // « Réduire les animations » : tout saute à sa place, sans ressort
        rev += 1
        if tousLesRessorts { boucle?.invalidate(); boucle = nil; return }
        guard boucle == nil else { return }
        dernierPas = ProcessInfo.processInfo.systemUptime
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.pas() } }
        RunLoop.main.add(t, forMode: .common)
        boucle = t
    }
    private func pas() {
        let maintenantSysteme = ProcessInfo.processInfo.systemUptime
        let dt = min(0.05, max(0.001, maintenantSysteme - dernierPas))
        dernierPas = maintenantSysteme
        avancer(dt)
    }
    func avancer(_ dt: Double) {
        for i in 0..<geo.count { if geo[i].fini { geo[i].poser() } else { geo[i].avancer(dt) } }
        for v in VueIlot.allCases { if poids[v]!.fini { poids[v]!.poser() } else { poids[v]!.avancer(dt) } }
        if secousse.fini { secousse.poser() } else { secousse.avancer(dt) }
        if pastilleVisible.fini { pastilleVisible.poser() } else { pastilleVisible.avancer(dt) }
        if pastilleOuverte.fini { pastilleOuverte.poser() } else { pastilleOuverte.avancer(dt) }
        rev += 1
        if tousLesRessorts { boucle?.invalidate(); boucle = nil; vider(); surFenetre() }
    }

    /// Les ressorts sont posés tout de suite sur leur cible (rendus PNG, essais).
    func poser() {
        for i in 0..<geo.count { geo[i].poser() }
        for v in VueIlot.allCases { poids[v]!.poser() }
        secousse.poser(); pastilleVisible.poser(); pastilleOuverte.poser()
        boucle?.invalidate(); boucle = nil
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

    /// Moitié de la caméra, décalage latéral des éléments des ailes quand la caméra n'a pas 200 pt, et décalages verticaux.
    var demiCamera: CGFloat { geometrie.largeur / 2 }
    var dAile: CGFloat { demiCamera - 100 }
    var dy: CGFloat { geometrie.hauteur - 32 }

    /// La forme actuelle (points) pour le dessin.
    var trace: TraceIlot.Points {
        TraceIlot.calculer(geo.map(\.x), demiCamera: Double(demiCamera), barre: Double(geometrie.hauteur))
    }
    /// Le rectangle de la forme au point voulu (x depuis le centre, y depuis le haut de l'écran).
    func rectCible() -> CGRect {
        let p = TraceIlot.calculer(geo.map(\.cible), demiCamera: Double(demiCamera), barre: Double(geometrie.hauteur))
        let g = geo.map(\.cible)
        return CGRect(x: p.basGauche, y: 0, width: p.basDroite - p.basGauche, height: g[4])
    }
    func rectActuel() -> CGRect {
        let p = trace
        let h = geo[4].x
        return CGRect(x: min(p.basGauche, p.xGauche), y: 0, width: max(p.basDroite, p.xDroite) - min(p.basGauche, p.xGauche), height: h)
    }
    /// La largeur de la pastille quand elle est dépliée.
    func largeurPastille(_ a: ActiviteIlot) -> CGFloat {
        switch a {
        case .lecture: return 112
        case .minuteur: return 90
        case .rendezVous: return 108
        case .rappel: return 124
        case .alerte: return 130
        }
    }
    func rectPastille() -> CGRect? {
        guard let p = pastille else { return nil }
        let g = geo.map(\.cible)
        let x = demiCamera + CGFloat(g[3]) + 8
        return CGRect(x: x, y: 41 + dy, width: largeurPastille(p), height: 34)
    }
    /// Le rectangle que la fenêtre doit couvrir (centre = 0) : la forme voulue, la pastille et une marge pour l'ombre et la secousse.
    func fenetreVoulue() -> CGRect {
        var r = rectCible()
        if let p = rectPastille(), !cache { r = r.union(p) }
        // au repos ou en compact : à peine plus que la forme (aucun clic pris aux icônes voisines) ; déplié : de la place pour l'ombre
        let petit = r.height <= CGFloat(geometrie.hauteur) + 10
        let cote: CGFloat = petit ? 2 : 18, bas: CGFloat = petit ? 6 : 30
        return CGRect(x: r.minX - cote, y: 0, width: r.width + 2 * cote, height: r.height + bas)
    }
}
