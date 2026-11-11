import AppKit
import DicteeCore

extension Notification.Name {
    /// Un réglage de l'îlot a changé (Réglages) : le contrôleur relit `Settings`.
    static let verbeIlotReglages = Notification.Name("verbe.ilot.reglages")
}

/// Les rappels, gardés localement : ~/Library/Application Support/Dictee/rappels.json (0600, jamais dans git, jamais envoyés nulle part).
struct RappelsStore {
    var url: URL
    static var urlParDefaut: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Dictee", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("rappels.json")
    }
    func lire() -> ListeRappels {
        guard let d = try? Data(contentsOf: url) else { return ListeRappels() }
        if let l = ListeRappels.depuis(d) { return l }
        Log.ecrire("rappels : fichier illisible, l'ancien est gardé en .abime")
        try? FileManager.default.moveItem(at: url, to: url.appendingPathExtension("abime"))
        return ListeRappels()
    }
    func ecrire(_ liste: ListeRappels) {
        guard let d = liste.donnees() else { return }
        try? d.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

/// Le centre d'activités : relie l'îlot (moteur + fenêtre) à ce qui l'alimente — la lecture en cours, le minuteur, les rappels, le calendrier,
/// les notifications — et aux priorités de l'encoche (dictée > réunion > alerte > lecture > le reste).
@MainActor
final class IlotControleur {
    let lecture = LectureControleur()
    let moteur: IlotMoteur
    let panneau: IlotPanneau
    let agenda = AgendaSysteme()
    let notificationsSource = SourceNotifications()
    let energieSource = SourceEnergie()
    let appareilsSource = SourceAppareils()
    private var veilleEnergie = VeilleEnergie()
    let telechargementsSource = SourceTelechargements()
    private var rafale = RafaleTelechargements()
    /// Le micro du Mac (CoreAudio ; un micro factice dans les essais, jamais le vrai).
    var micro: PiloteMicro = MicroSysteme() { didSet { micro.surChangement = { [weak self] in self?.microChange() } } }
    private(set) var veilleMicro = VeilleMicro()
    /// Volume et luminosité (IlotNiveaux.swift) : le vrai son et le vrai écran (des faux dans les essais), le réglage, et la mémoire des
    /// touches avalées (appui, répétitions, relâchement).
    var niveaux: PiloteNiveaux = NiveauxSysteme()
    var niveauxActifs = Settings.ilotNiveaux
    var aiguillageNiveau = AiguillageNiveau()
    /// Claude au travail (IlotClaude.swift) : le dossier des sessions, leur état, le réveil qui oublie une session muette depuis trop
    /// longtemps ; l'app au premier plan et le retour au Terminal sont injectables (les essais n'activent jamais d'app).
    let claudeSource = SourceClaude()
    var veilleClaude = VeilleClaude()
    var reveilClaude: DispatchWorkItem?
    /// Les vieux fichiers de sessions ont été effacés (une fois par lancement, même réglage éteint).
    var claudeNettoye = false
    var appAuPremierPlan: () -> String? = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
    var ramenerApp: (String?) -> Void = { IlotControleur.ramener($0) }
    /// Le Centre (CentreIlot.swift) : l'installation des crochets de Claude Code et les réglages qu'il lit ou écrit, injectables (les
    /// essais ne touchent jamais ~/.claude, ~/Downloads ni les vrais réglages).
    var installationClaude = InstallationClaude.parDefaut
    var reglagesCentre = ReglagesCentre()
    /// Téléchargements vient d'être allumé d'un clic dans le Centre : un refus de macOS laisse alors la ligne d'avis, même si le Centre
    /// s'est rangé avant la réponse (un refus venu plus tard, d'ailleurs, n'en laisse pas).
    var telechargementsDemandesDuCentre = false

    /// Ce qui occupe l'encoche en dehors de la dictée de ce contrôleur (rempli par l'AppDelegate).
    var occupation: () -> OccupationEncoche = { OccupationEncoche() }
    /// Recolle un texte dans la dernière app (rempli par l'AppDelegate).
    var surColler: (String) -> Void = { _ in }
    /// La dernière dictée (la plus récente qui a un texte) : celle que l'accueil et le Centre montrent, et que « Coller » colle en entier
    /// (injectable : les essais ne lisent jamais l'historique).
    var lireDerniereDictee: () -> (texte: String, date: Date)? = {
        HistoriqueStore.shared.historique.entrees.first(where: { $0.insere || !$0.texte.isEmpty }).map { ($0.texte, $0.date) }
    }
    /// Lance la prise de notes d'une réunion (rempli par l'AppDelegate).
    var surNoter: (EvenementAgenda?) -> Void = { _ in }
    /// Ouvre un lien ou un fichier (injectable pour les essais : jamais d'ouverture réelle).
    var ouvrir: (URL) -> Void = { NSWorkspace.shared.open($0) }
    /// Montre des fichiers dans le Finder (injectable, comme `ouvrir`).
    var montrer: ([URL]) -> Void = { NSWorkspace.shared.activateFileViewerSelecting($0) }
    /// L'heure (injectable).
    var maintenant: () -> Date = { Date() } { didSet { moteur.maintenant = maintenant } }
    /// Les sons et vibrations (injectables : les essais n'en jouent jamais).
    var sons = SonsIlot()

    struct SonsIlot {
        var minuteurFini: @MainActor () -> Void = { Retours.minuteurFini() }
        var rappel: @MainActor () -> Void = { Retours.rappelSonne() }
        var doux: @MainActor () -> Void = { Retours.bandeauDoux() }
        var silencieux: @MainActor () -> Void = { Retours.alerteSilencieuse() }
    }

    private(set) var minuteur: MinuteurIlot?
    private(set) var rappels: ListeRappels
    var stockage: RappelsStore
    /// L'étagère (IlotEtagere.swift) : les signets des fichiers gardés, leur fichier, et leurs icônes du Finder (lues une fois).
    var etagere: EtagereIlot
    var etagereStore: EtagereStore
    var iconesEtagere: [UUID: NSImage] = [:]
    /// La relecture des signets (sur une file à part) : en cours, à refaire aussitôt, et quand elle a commencé la dernière fois.
    var relectureEtagere: (enCours: Bool, encore: Bool, derniere: Date) = (false, false, .distantPast)
    var apresRelecture: [() -> Void] = []
    /// L'étagère plus rapide (IlotEtagere.swift) : les fichiers partis vers une app, gardés le temps de « Remettre » (en mémoire
    /// seulement) ; les captures arrivées pas encore vues (« Nouveau », en mémoire seulement).
    var partisEnAttente: [ElementEtagere] = []
    var nouveautes = Set<UUID>()
    /// AirDrop (le panneau de macOS choisit l'appareil) : injectable, l'essai n'envoie jamais rien. Rend faux si AirDrop ne peut pas
    /// envoyer ces fichiers (éteint, pas de Wi-Fi) ; sinon, la réponse du service arrive plus tard.
    var envoyerParAirDrop: ([URL], @escaping (EnvoiEtagere.Etat) -> Void) -> Bool = { urls, fin in EnvoiAirDrop.envoyer(urls, fin: fin) }
    /// L'app sous un point de l'écran (où des fichiers ont été lâchés) : son nom, lu sans autorisation (injectable).
    var appSous: (NSPoint) -> String? = { IlotControleur.appSous($0) }
    /// « Captures d'écran ici » : le dossier des captures, surveillé comme Téléchargements (un dossier temporaire dans l'essai).
    let capturesSource = SourceTelechargements(etiquette: "captures")
    var dossierCaptures: () -> URL = { IlotControleur.dossierCapturesParDefaut() }
    /// Une capture se reconnaît à la marque de macOS (attribut kMDItemIsScreenCapture) ou à son nom (injectable).
    var estUneCapture: (URL) -> Bool = { IlotControleur.estUneCapture($0) }
    private var reveilMinuteur: DispatchWorkItem?
    private var reveilRappels: DispatchWorkItem?
    private var reveilAgenda: DispatchWorkItem?
    private var evenements: [EvenementAgenda] = []
    private var annonces = Set<String>()       // rendez-vous déjà annoncés (10 min avant)
    private var debutsAnnonces = Set<String>() // rendez-vous dont le début a été signalé
    private var ignores = Set<String>()        // rendez-vous rejoints ou notés : on n'en parle plus
    private var dernierRappelAjoute: UUID?
    private var reglagesObserves: NSObjectProtocol?
    /// La commande dictée est armée si, au moment où la dictée a commencé, l'accueil de l'îlot (ou son formulaire de rappel) était ouvert.
    private var armeJusqua: Date = .distantPast
    private var armeFormulaire = false

    init(stockage: RappelsStore = RappelsStore(url: RappelsStore.urlParDefaut), etagere etagereStore: EtagereStore = EtagereStore(url: EtagereStore.urlParDefaut)) {
        self.stockage = stockage
        rappels = stockage.lire()
        self.etagereStore = etagereStore
        etagere = etagereStore.lire()
        moteur = IlotMoteur(lecture: lecture.modele)
        panneau = IlotPanneau(moteur: moteur)
        lecture.surIlot = { [weak self] visible in self?.lectureVisible(visible) }
        lecture.surRecalcul = { [weak self] in self?.appliquerLesMasques() }
        lecture.surNouveauMorceau = { [weak self] in self?.moteur.donneesChangees() }
        moteur.surAction = { [weak self] a in self?.agir(a) }
        moteur.surArrivee = { [weak self] v in self?.arrivee(v) }
        moteur.surAlerteExpiree = { [weak self] in self?.alerteExpiree() }
        moteur.surDepliage = { [weak self] in self?.depliage() }
        agenda.surChangement = { [weak self] in self?.relireAgenda() }
        notificationsSource.surNotification = { [weak self] n in self?.notificationRecue(n) }
        energieSource.surChangement = { [weak self] e in self?.energieChangee(e) }
        appareilsSource.surChangement = { [weak self] in self?.appareilsChanges() }
        appareilsSource.surConnexion = { [weak self] a in self?.appareilConnecte(a) }
        telechargementsSource.surArrivee = { [weak self] l in self?.fichiersArrives(l) }
        telechargementsSource.surRefus = { [weak self] in self?.telechargementsRefuses() }
        telechargementsSource.surPret = { [weak self] in self?.moteur.telechargementsAttente = false; self?.telechargementsDemandesDuCentre = false }
        // ni accordé ni refusé (dossier absent ou illisible sur le moment) : plus de « Un instant… », le clic ailleurs range de nouveau
        telechargementsSource.surArret = { [weak self] in self?.moteur.telechargementsAttente = false; self?.telechargementsDemandesDuCentre = false }
        lecture.modele.surClicIlot = { [weak self] in self?.moteur.clicForme() }
        panneau.surDepot = { [weak self] urls in self?.ranger(urls) }
        panneau.surAirDrop = { [weak self] urls in self?.envoyerAirDrop(urls) }
        moteur.surEtagereVue = { [weak self] in self?.etagereVue() }
        capturesSource.surArrivee = { [weak self] l in self?.capturesArrivees(l) }
        capturesSource.surRefus = { [weak self] in self?.capturesRefusees() }
        capturesSource.surPret = { [weak self] in self?.moteur.capturesAttente = false }
        capturesSource.surArret = { [weak self] in self?.capturesIntrouvables() }
        claudeSource.surLignes = { [weak self] l, relecture in self?.lignesClaude(l, relecture: relecture) }
        micro.surChangement = { [weak self] in self?.microChange() }
        moteur.surBulleVue = { [weak self] in self?.reglagesCentre.marquerBulleVue() }
        moteur.surCentreUtilise = { [weak self] in self?.reglagesCentre.marquerCentreUtilise() }
        moteur.surDispositionCentre = { [weak self] d in
            self?.reglagesCentre.enregistrerDisposition(d.identifiants)
            Log.ecrire("centre : \(d.identifiants.joined(separator: ", "))")
        }
    }

    // MARK: vie

    func demarrer() {
        reglagesObserves = NotificationCenter.default.addObserver(forName: .verbeIlotReglages, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.appliquerLesReglages() }
        }
        lecture.demarrer()
        panneau.demarrer()
        moteur.rappelsAVenir = rappels.aVenir(a: maintenant())
        appliquerLesReglages()
        verifierLesRappels()
        // le Centre : l'aide sous le bouton « Centre » tant qu'il n'a pas servi ; au tout premier lancement, la bulle « Nouveau »
        moteur.aideCentre = !reglagesCentre.centreUtilise()
        moteur.disposition = DispositionCentre(identifiants: reglagesCentre.disposition())
        if !reglagesCentre.bulleVue() { moteur.montrerBulle() }
    }

    func arreter() {
        lecture.arreter()
        notificationsSource.arreter()
        energieSource.arreter(); appareilsSource.arreter()
        telechargementsSource.arreter()
        capturesSource.arreter()
        niveaux.arreter()
        activerLeMicro(false)
        activerClaude(false)
        agenda.arreter()
        panneau.fermer()
        [reveilMinuteur, reveilRappels, reveilAgenda].forEach { $0?.cancel() }
    }

    /// Lecture de `Settings` : chaque activité s'allume ou s'éteint. Le calendrier ne demande son autorisation qu'ici, à l'activation.
    func appliquerLesReglages() {
        moteur.calendrierActif = Settings.ilotCalendrier && agenda.statut == .autorise
        if Settings.ilotCalendrier {
            switch agenda.statut {
            case .autorise: agenda.ecouter(); relireAgenda()
            case .nonDemande:
                Task { @MainActor in
                    let ok = await agenda.demander()
                    if !ok { Settings.ilotCalendrier = false; Log.ecrire("calendrier : accès refusé, réglage éteint") }
                    else { agenda.ecouter() }
                    NotificationCenter.default.post(name: .verbeIlotReglagesRelus, object: nil)
                    appliquerLesReglages()
                }
            case .refuse:
                Settings.ilotCalendrier = false
                Log.ecrire("calendrier : accès refusé dans Réglages Système, réglage éteint")
                NotificationCenter.default.post(name: .verbeIlotReglagesRelus, object: nil)
            }
        } else {
            agenda.arreter(); evenements = []; reveilAgenda?.cancel()
            moteur.rendezVous = nil; moteur.rendezVousProche = false; moteur.rendezVousSuivant = nil
        }
        if Settings.ilotNotifications {
            if !notificationsSource.actif, !notificationsSource.demarrer() { Log.ecrire("notifications : non démarrées (voir plus haut)") }
        } else { notificationsSource.arreter(); moteur.notifications = [] }
        if !Settings.ilotMinuteur, minuteur != nil { arreterLeMinuteur() }
        if Settings.ilotEnergie {
            energieSource.demarrer(); appareilsSource.demarrer()
        } else {
            energieSource.arreter(); appareilsSource.arreter(); veilleEnergie = VeilleEnergie()
            moteur.energie = nil; moteur.ecouteurs = nil
        }
        // le dossier Téléchargements : macOS demande une fois l'accès, à la première ouverture (sur une file à part)
        if Settings.ilotTelechargements { telechargementsSource.demarrer() }
        else { telechargementsSource.arreter(); rafale = RafaleTelechargements() }
        moteur.telechargementsActifs = Settings.ilotTelechargements
        if !Settings.ilotTelechargements { moteur.telechargementsAttente = false }
        niveauxActifs = Settings.ilotNiveaux
        if niveauxActifs { niveaux.demarrer() } else { niveaux.arreter() }
        activerClaude(Settings.ilotClaude)
        activerEtagere(Settings.ilotEtagere)
        activerCaptures(Settings.ilotEtagere && reglagesCentre.captures())
        activerLeMicro(Settings.ilotMicro)
        moteur.donneesChangees()
    }

    // MARK: micro coupé

    /// Le réglage « Micro coupé » : on écoute le micro par défaut (CoreAudio prévient, aucun sondage) et on lit où il en est. Éteint :
    /// on n'écoute plus ; un micro rouvert pour une dictée est recoupé, un micro coupé le reste (c'est l'état du Mac, pas de Verbe).
    func activerLeMicro(_ oui: Bool) {
        if oui {
            guard !micro.actif else { return }
            micro.demarrer()
            microChange()
        } else {
            guard micro.actif else { return }
            executer(veilleMicro.oublier())
            micro.arreter()
            moteur.microCoupe = false; moteur.nomMicro = nil
            moteur.donneesChangees()
        }
    }

    /// Le bouton Micro du Centre : coupe le micro par défaut, ou le rouvre. Faux quand il ne peut rien (réglage éteint, aucun micro,
    /// micro sans muet ni volume réglable, commande refusée).
    @discardableResult
    func basculerLeMicro() -> Bool {
        guard micro.actif, let d = micro.defaut, let c = micro.estCoupe(d), micro.peutCouper(d) else { return false }
        // l'état réel d'abord (une notification de CoreAudio peut être encore en route) : le bouton agit sur ce qui est vrai
        _ = veilleMicro.systeme(defaut: d, coupe: c)
        return executer(veilleMicro.basculer())
    }

    /// CoreAudio prévient : le micro par défaut, son muet ou son volume a changé. On relit l'état tel qu'il est MAINTENANT (une
    /// notification en retard sur nos propres commandes ne compte donc pas) ; l'îlot suit, rouvert ailleurs = « Micro ouvert » (un
    /// simple changement de micro par défaut n'annonce rien).
    func microChange() {
        guard micro.actif else { return }
        moteur.nomMicro = micro.nom
        let d = micro.defaut
        executer(veilleMicro.systeme(defaut: d, coupe: d.flatMap { micro.estCoupe($0) } ?? false))
    }

    /// Envoie la commande à CoreAudio (au micro qu'elle vise), puis montre ce qui est vrai (l'activité, et le bandeau vert « Micro
    /// ouvert », 1,5 s). Faux si CoreAudio a refusé la commande.
    @discardableResult
    private func executer(_ r: VeilleMicro.Reponse) -> Bool {
        var annonce = r.annonce
        var ok = true
        if let c = r.commande {
            switch c {
            case .couper(let u): ok = micro.couper(u)
            case .rouvrir(let u): ok = micro.rouvrir(u)
            }
            let quoi: String
            switch c { case .couper: quoi = "coupé"; case .rouvrir: quoi = "rouvert" }
            let autre = c.uid != veilleMicro.defaut ? " (pas le micro par défaut)" : ""
            Log.ecrire("micro coupé : \(quoi)\(veilleMicro.dicteeEnCours ? " (dictée)" : "")\(autre)\(ok ? "" : " : REFUSÉ, l'îlot reste sur l'état réel")")
            if !ok { veilleMicro.commandeEchouee(c); annonce = nil }
        }
        let change = moteur.microCoupe != veilleMicro.coupe
        moteur.microCoupe = veilleMicro.coupe
        // le Centre ouvert montre déjà le micro (« Ouvert » sous son bouton) : pas de bandeau, qui le refermerait
        if annonce == .ouvert, moteur.centreOuvert { annonce = nil }
        if annonce == .ouvert {
            moteur.annoncer(bandeau: BandeauIlot(vue: .microOuvert, jusqua: maintenant().addingTimeInterval(1.5), ligne1: "Micro ouvert", ligne2: ""))
        } else if change { moteur.donneesChangees() }
        return ok
    }

    // MARK: téléchargements

    /// Des fichiers finis viennent d'arriver dans Téléchargements : un bandeau de 4 s. Pendant ces 4 s, ceux qui suivent le rejoignent
    /// (« 3 fichiers téléchargés ») et le prolongent.
    func fichiersArrives(_ l: [FichierTelecharge]) {
        guard !l.isEmpty else { return }
        let t = maintenant()
        rafale.ajouter(l, a: t)
        let d = TelechargementIlot(rafale: rafale, icones: Self.icones(rafale.fichiers))
        moteur.annoncer(bandeau: BandeauIlot(vue: .telecharge, jusqua: t.addingTimeInterval(RafaleTelechargements.fenetre),
                                             ligne1: rafale.titre, ligne2: rafale.sousTitre, telechargement: d))
    }

    /// Le bouton Téléchargements du Centre : allume (macOS demande une fois l'accès au dossier, après ce clic) ou éteint le réglage.
    func reglerTelechargements(_ oui: Bool) {
        reglagesCentre.reglerTelechargements(oui)
        // « Un instant… » jusqu'à la réponse (ouvert et lu : `surPret` ; refusé : `telechargementsRefuses`)
        moteur.telechargementsAttente = oui && !telechargementsSource.actif
        if oui { telechargementsSource.demarrer() } else { telechargementsSource.arreter(); rafale = RafaleTelechargements() }
        moteur.telechargementsActifs = oui
        Log.ecrire("téléchargements : \(oui ? "allumé" : "éteint") depuis le Centre")
        NotificationCenter.default.post(name: .verbeIlotReglagesRelus, object: nil)
        moteur.donneesChangees()
    }

    // MARK: batterie et appareils

    /// L'alimentation a changé : la batterie des épaules, et l'annonce du chargeur branché ou de la batterie faible.
    func energieChangee(_ e: EnergieIlot?) {
        moteur.energie = e
        switch veilleEnergie.lire(e) {
        case .charge?:
            moteur.annoncer(bandeau: BandeauIlot(vue: .batterieCharge, jusqua: maintenant().addingTimeInterval(3), ligne1: "En charge", ligne2: "", energie: e))
        case .faible?:
            moteur.annoncer(bandeau: BandeauIlot(vue: .batterieFaible, jusqua: maintenant().addingTimeInterval(4.5), ligne1: "Batterie faible", ligne2: "", energie: e))
        case nil:
            moteur.donneesChangees()
        }
    }
    private func appareilsChanges() {
        moteur.ecouteurs = appareilsSource.ecouteurs
        relireChoixMicro()
        moteur.donneesChangees()
    }
    /// Des écouteurs (ou une souris, un clavier) viennent de se connecter : 3,5 s de bandeau, avec leurs jauges.
    func appareilConnecte(_ a: AppareilIlot) {
        moteur.annoncer(bandeau: BandeauIlot(vue: .appareil, jusqua: maintenant().addingTimeInterval(3.5), ligne1: a.titre, ligne2: "", appareil: a))
    }

    // MARK: priorités

    /// À appeler quand quelque chose de l'encoche change (dictée, réunion, filet, mise à jour, panneau…).
    func occupationChangee() { lecture.occupationChangee(); appliquerLesMasques() }

    func dicteeChange(enCours: Bool) {
        if enCours {
            // la commande dictée n'existe que si l'accueil de l'îlot (ou la lecture dépliée, qui le remplace pendant une vidéo) est
            // ouvert à cet instant
            let courante = moteur.courante
            if moteur.fenetreOuverte, [.accueil, .centre, .rappelListe, .lectureEtendu, .lectureMinuteur].contains(courante) {
                armeFormulaire = courante == .rappelListe
                armeJusqua = maintenant().addingTimeInterval(60)
            }
        } else if armeJusqua > maintenant() {
            armeJusqua = maintenant().addingTimeInterval(12)   // le temps de la transcription
        }
        // le micro qu'écoutera la dictée, s'il est coupé, est rouvert AVANT qu'elle ne l'ouvre (cet appel précède le démarrage de la
        // capture), puis recoupé à la fin ; c'est bien CE micro-là (son UID), même si ce n'est pas celui par défaut
        if micro.actif {
            if enCours {
                let u = micro.microDeLaDictee()
                executer(veilleMicro.dictee(enCours: true, micro: u, coupe: u.flatMap { micro.estCoupe($0) } ?? false))
            } else { executer(veilleMicro.dictee(enCours: false)) }
        }
        lecture.dicteeChange(enCours: enCours)
        appliquerLesMasques()
    }

    private func appliquerLesMasques() {
        let o = occupation()
        let dictee = o.dictee || lecture.dicteeConfirmee
        let masque = o.filet || o.miseAJour || o.autreAnnonce
        guard dictee != moteur.dictee || o.reunion != moteur.reunion || masque != moteur.masque else { return }
        moteur.dictee = dictee; moteur.reunion = o.reunion; moteur.masque = masque
        moteur.donneesChangees()
        if !moteur.cache { moteur.vidangerAttente() }
    }

    private func lectureVisible(_ visible: Bool) {
        moteur.lecturePresente = visible
        moteur.donneesChangees()
    }

    // MARK: arrivées (son, vibration)

    private func arrivee(_ v: VueIlot) {
        if moteur.reunion { sons.silencieux(); return }
        switch v {
        case .minuteurFini: sons.minuteurFini(); moteur.bourdonner()
        case .rappelEtendu, .agendaDebut: sons.rappel(); moteur.bourdonner()
        default: sons.doux()
        }
    }

    // MARK: déploiement

    /// L'îlot se déplie : on relit ce que l'accueil montre (dernière dictée, prochain rendez-vous) et le site de la lecture. L'heure n'y
    /// est plus : la barre des menus l'affiche déjà juste à côté.
    /// Un micro Bluetooth est branché (AirPods…) : l'accueil propose de choisir le micro de la dictée. « Mac » = le réglage Automatique.
    /// Les micros du Mac (injectable : l'essai ne lit jamais les vrais).
    var lireMicros: () -> [PeripheriqueEntree] = { AudioCapture.peripheriquesEntree() }
    func relireChoixMicro() {
        let bt = lireMicros().first { $0.transport == .bluetooth }
        moteur.choixMicro = bt.map { ($0.nom, reglagesCentre.microChoisi() == $0.uid) }
    }

    private func depliage() {
        relireChoixMicro()
        if let e = lireDerniereDictee() {
            let texte = e.texte.trimmingCharacters(in: .whitespacesAndNewlines)
            moteur.derniereDictee = (String(texte.prefix(90)), ageLisible(e.date))
        } else { moteur.derniereDictee = nil }
        moteur.rendezVousSuivant = PlanAgenda.prochain(evenements, a: maintenant())
        moteur.rappelsAVenir = rappels.aVenir(a: maintenant())
        if Settings.ilotEnergie, appareilsSource.actif { appareilsSource.relireSiAncien() }
        // l'accueil s'ouvre au survol : pas plus d'une relecture toutes les 5 s ; la carte de l'étagère, elle, relit toujours
        if moteur.etagereActive { relireEtagere(force: moteur.courante == .etagere) }
        // le Centre : l'état de ses boutons (settings.json de Claude Code n'est lu qu'ici, à l'ouverture du Centre)
        if moteur.courante == .centre {
            moteur.telechargementsActifs = reglagesCentre.telechargements()
            moteur.claudeBranche = installationClaude.estBranche
        }
        lecture.ilotDeplie()
    }
    private func ageLisible(_ date: Date) -> String {
        let s = maintenant().timeIntervalSince(date)
        if s < 90 { return "à l\u{2019}instant" }
        let m = Int(s / 60)
        if m < 60 { return "\(m) min" }
        return m < 1440 ? "\(m / 60) h" : "\(m / 1440) j"
    }

    // MARK: actions de l'îlot

    func agir(_ action: ActionIlot) {
        switch action {
        case .minuteurLancer(let minutes): lancerLeMinuteur(secondes: minutes * 60, bandeau: true)
        case .minuteurLancerSousLecture(let minutes): lancerLeMinuteur(secondes: minutes * 60, bandeau: false)
        case .minuteurRecommencer(let minutes): moteur.quitterAlerte(); lancerLeMinuteur(secondes: minutes * 60, bandeau: false)
        case .minuteurBasculer:
            minuteur?.basculer(a: maintenant()); mettreAJourLeMinuteur()
        case .minuteurPlusUneMinute:
            minuteur?.ajouter(60, a: maintenant()); mettreAJourLeMinuteur()
        case .minuteurArreter: arreterLeMinuteur(); if !moteur.centreOuvert { moteur.fermer() }
        case .minuteurLancerDansLeCentre(let minutes):
            // le minuteur éteint dans les réglages : le clic l'allume (comme le bouton Micro), sinon le bouton ne ferait rien
            if !reglagesCentre.minuteurActif() {
                reglagesCentre.allumerMinuteur()
                Log.ecrire("minuteur : allumé depuis le Centre")
                NotificationCenter.default.post(name: .verbeIlotReglagesRelus, object: nil)
            }
            lancerLeMinuteur(secondes: minutes * 60, bandeau: false, fermer: false)
        case .centreMicro, .centreTelechargements, .centreClaude, .etagereAllumer, .centreReunion, .centreAvis: agirCentre(action)
        case .alerteOK: moteur.quitterAlerte()
        case .rappelPlusTard(let id):
            rappels.reporter(id, depuis: maintenant()); sauver()
            moteur.quitterAlerte()
            let t = rappels.rappels.first { $0.id == id }
            moteur.annoncer(bandeau: BandeauIlot(vue: .rappelReporte, jusqua: maintenant().addingTimeInterval(2.8), ligne1: "Je vous le redis dans 10 min", ligne2: t?.texte ?? "",
                                                 meta: FormatIlot.heure(maintenant().addingTimeInterval(600))))
        case .rappelFait(let id):
            let t = rappels.rappels.first { $0.id == id }?.texte ?? ""
            rappels.fait(id); sauver()
            moteur.quitterAlerte()
            moteur.annoncer(bandeau: BandeauIlot(vue: .rappelFait, jusqua: maintenant().addingTimeInterval(2.2), ligne1: "Fait", ligne2: t))
        case .rappelAnnuler(let id):
            rappels.annuler(id); sauver(); moteur.quitterBandeau()
        case .rappelFormulaire: moteur.ouvrirFormulaireRappel()
        case .rendezVousRejoindre(let e):
            if let lien = e.lien, LienVisio.estAutorise(lien) { ouvrir(lien) }
            oublier(e)
        case .rendezVousNoter(let e):
            surNoter(e); oublier(e)
        case .fichiersOuvrir(let urls):
            if urls.count == 1 { ouvrir(urls[0]) } else if !urls.isEmpty { montrer(urls) }
            rafale = RafaleTelechargements()
            moteur.quitterBandeau()
        case .microRouvrir:
            moteur.fermer()
            executer(veilleMicro.rouvrir())
        case .claudeOuvrir(let app):
            if moteur.bandeau?.vue == .claudeAttend || moteur.bandeau?.vue == .claudeTermine { moteur.quitterBandeau() } else { moteur.fermer() }
            ramenerApp(app)
        case .etagereOuvrir, .etagereRetirer, .etagereVider, .etagereSortis, .etagereRemettre, .etagereCaptures, .etagereCapturesReglages:
            agirEtagere(action)
        case .microChoisir(let airpods):
            let bt = lireMicros().first { $0.transport == .bluetooth }
            reglagesCentre.choisirMicro(airpods ? bt?.uid : nil)
            Log.ecrire("micro : choisi depuis l'îlot, \(airpods ? "celui de \(bt?.nom ?? "?")" : "celui du Mac (Automatique)")")
            relireChoixMicro()
            moteur.donneesChangees()
            NotificationCenter.default.post(name: .verbeIlotReglagesRelus, object: nil)
        case .collerLaDerniereDictee:
            if let d = lireDerniereDictee()?.texte, !d.isEmpty { moteur.fermer(); surColler(d) }
        }
    }

    private func oublier(_ e: EvenementAgenda) {
        ignores.insert(e.id)
        moteur.quitterAlerte()
        moteur.rendezVousProche = false; moteur.rendezVous = nil
        moteur.fermer()
        planifierAgenda()
    }

    // MARK: minuteur

    func lancerLeMinuteur(secondes: Double, bandeau: Bool, fermer: Bool = true) {
        guard reglagesCentre.minuteurActif() else { return }
        let t = maintenant()
        minuteur = MinuteurIlot(secondes: secondes, depuis: t)
        moteur.minuteur = minuteur
        if bandeau, let m = minuteur {
            moteur.annoncer(bandeau: BandeauIlot(vue: .minuteurLance, jusqua: t.addingTimeInterval(2.4), ligne1: "Minuteur lancé",
                                                 ligne2: FormatIlot.minutes(m.total) + " \u{00B7} fin à " + FormatIlot.heure(m.heureDeFin(a: t))))
        }
        if fermer { moteur.fermer() } else { moteur.donneesChangees() }
        programmerFinDuMinuteur()
    }
    private func mettreAJourLeMinuteur() {
        moteur.minuteur = minuteur
        programmerFinDuMinuteur()
        moteur.donneesChangees()
    }
    private func arreterLeMinuteur() {
        minuteur = nil; moteur.minuteur = nil
        reveilMinuteur?.cancel()
        moteur.donneesChangees()
    }
    /// Un seul réveil, à la fin du minuteur (rien ne tourne en attendant).
    private func programmerFinDuMinuteur() {
        reveilMinuteur?.cancel()
        guard let m = minuteur, let fin = m.echeance else { return }
        let item = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.minuteurTermine() } }
        reveilMinuteur = item
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, fin.timeIntervalSince(maintenant())), execute: item)
    }
    func minuteurTermine() {
        guard let m = minuteur else { return }
        let libelle = FormatIlot.minutes(m.total)
        minuteur = nil; moteur.minuteur = nil
        moteur.fermer()
        moteur.annoncer(alerte: AlerteIlot(vue: .minuteurFini, jusqua: nil, libelle: libelle))
        moteur.donneesChangees()
    }

    // MARK: rappels

    @discardableResult
    func ajouterUnRappel(texte: String, quand: Date) -> Rappel? {
        guard Settings.ilotRappels, let r = rappels.ajouter(texte: texte, echeance: quand, maintenant: maintenant()) else { return nil }
        sauver()
        dernierRappelAjoute = r.id
        moteur.fermer()
        moteur.annoncer(bandeau: BandeauIlot(vue: .rappelAjoute, jusqua: maintenant().addingTimeInterval(3), ligne1: "Rappel ajouté",
                                             ligne2: r.texte + " \u{00B7} " + ListeRappels.jour(de: quand, maintenant: maintenant()), meta: FormatIlot.heure(quand), rappelId: r.id))
        return r
    }
    private func sauver() {
        stockage.ecrire(rappels)
        moteur.rappelsSonnes = rappels.enAttente
        moteur.rappelsAVenir = rappels.aVenir(a: maintenant())
        programmerLesRappels()
        moteur.donneesChangees()
    }
    private func programmerLesRappels() {
        reveilRappels?.cancel()
        guard let prochaine = rappels.prochaineEcheance() else { return }
        let item = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.verifierLesRappels() } }
        reveilRappels = item
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.05, prochaine.timeIntervalSince(maintenant())), execute: item)
    }
    /// Les rappels dont l'heure est venue sonnent (y compris ceux arrivés à échéance pendant que Verbe était fermé).
    func verifierLesRappels() {
        guard Settings.ilotRappels else { return }
        let t = maintenant()
        let dus = rappels.dus(a: t)
        for r in dus { rappels.marquerSonne(r.id, a: t) }
        stockage.ecrire(rappels)
        moteur.rappelsSonnes = rappels.enAttente
        moteur.rappelsAVenir = rappels.aVenir(a: t)
        if let premier = dus.first {
            moteur.fermer()
            moteur.annoncer(alerte: AlerteIlot(vue: .rappelEtendu, jusqua: t.addingTimeInterval(12), rappel: premier))
        }
        programmerLesRappels()
        moteur.donneesChangees()
    }
    private func alerteExpiree() {
        moteur.rappelsSonnes = rappels.enAttente
        moteur.donneesChangees()
    }

    // MARK: calendrier

    func relireAgenda() {
        guard Settings.ilotCalendrier, agenda.statut == .autorise else { return }
        evenements = agenda.prochains(depuis: maintenant())
        moteur.calendrierActif = true
        planifierAgenda()
    }
    /// Pour les essais : des rendez-vous simulés à la place d'EventKit.
    func injecterEvenements(_ liste: [EvenementAgenda]) { evenements = liste; planifierAgenda() }

    /// Annonce ce qui doit l'être maintenant et programme le prochain réveil (jamais plus d'une demi-heure plus tard).
    func planifierAgenda() {
        reveilAgenda?.cancel()
        let t = maintenant()
        var reveil = t.addingTimeInterval(1800)
        moteur.rendezVousSuivant = PlanAgenda.prochain(evenements, a: t)
        var proche: EvenementAgenda?
        for e in evenements where !ignores.contains(e.id) && !e.toutelaJournee {
            switch PlanAgenda.etape(e, a: t) {
            case .loin(let dans): reveil = min(reveil, t.addingTimeInterval(dans))
            case .avant(let reste):
                if proche == nil { proche = e }
                reveil = min(reveil, e.debut)
                if !annonces.contains(e.id) {
                    annonces.insert(e.id)
                    moteur.rendezVous = e
                    moteur.rendezVousProche = true
                    moteur.annoncer(bandeau: BandeauIlot(vue: .agendaAvant, jusqua: t.addingTimeInterval(4.5), ligne1: e.titre,
                                                         ligne2: PlanAgenda.dans(reste).capitalizedFirst + (e.lien != nil ? " \u{00B7} Visio" : (e.lieu.map { " \u{00B7} " + $0 } ?? "")), sonore: true, evenement: e))
                }
            case .debut:
                reveil = min(reveil, e.debut.addingTimeInterval(PlanAgenda.toleranceDebut + 1))
                if !debutsAnnonces.contains(e.id) {
                    debutsAnnonces.insert(e.id)
                    moteur.rendezVousProche = false
                    moteur.rendezVous = e
                    moteur.annoncer(alerte: AlerteIlot(vue: .agendaDebut, jusqua: t.addingTimeInterval(15), evenement: e))
                }
            case .passe: break
            }
        }
        if let proche { moteur.rendezVous = proche; moteur.rendezVousProche = true }
        else { moteur.rendezVousProche = false; if moteur.alerte?.vue != .agendaDebut { moteur.rendezVous = nil } }
        let item = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.relireAgendaOuPlanifier() } }
        reveilAgenda = item
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.1, reveil.timeIntervalSince(t)), execute: item)
        moteur.donneesChangees()
    }
    private func relireAgendaOuPlanifier() {
        if Settings.ilotCalendrier, agenda.statut == .autorise { evenements = agenda.prochains(depuis: maintenant()) }
        planifierAgenda()
    }

    // MARK: notifications

    func notificationRecue(_ n: NotificationRecue) {
        guard Settings.ilotNotifications else { return }
        moteur.notifications = LectureNotifications.ajouter(n, a: moteur.notifications, maintenant: maintenant())
        let groupe = moteur.notifications.count >= 2
        moteur.annoncer(bandeau: BandeauIlot(vue: groupe ? .notifications : .notification, jusqua: maintenant().addingTimeInterval(groupe ? 4.5 : 4), ligne1: n.titre, ligne2: n.corps, sonore: true))
    }

    // MARK: commandes dictées

    /// Appelée avec le texte final d'une dictée, avant le collage. Vrai si c'était une commande de l'îlot (le texte n'est alors PAS collé).
    /// Ne s'applique que si l'accueil de l'îlot était ouvert au début de la dictée : une dictée normale n'est jamais mangée.
    func intercepter(_ texte: String) -> Bool {
        guard armeJusqua > maintenant() else { return false }
        let formulaire = armeFormulaire
        armeJusqua = .distantPast; armeFormulaire = false
        guard let commande = AnalyseCommandeIlot.analyser(texte, maintenant: maintenant(), exigerPrefixe: !formulaire) else { return false }
        switch commande {
        case .minuteur(let secondes):
            guard Settings.ilotMinuteur else { return false }
            lancerLeMinuteur(secondes: secondes, bandeau: true)
        case .rappel(let t, let quand):
            guard Settings.ilotRappels, ajouterUnRappel(texte: t, quand: quand) != nil else { return false }
        }
        Log.ecrire("îlot : commande dictée exécutée (\(formulaire ? "formulaire" : "accueil"))")
        return true
    }
}

extension Notification.Name {
    /// Les Réglages doivent relire les interrupteurs de l'îlot (le calendrier peut être éteint si l'accès est refusé).
    static let verbeIlotReglagesRelus = Notification.Name("verbe.ilot.reglages.relus")
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
