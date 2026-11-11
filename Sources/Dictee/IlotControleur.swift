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

    /// Ce qui occupe l'encoche en dehors de la dictée de ce contrôleur (rempli par l'AppDelegate).
    var occupation: () -> OccupationEncoche = { OccupationEncoche() }
    /// Recolle un texte dans la dernière app (rempli par l'AppDelegate).
    var surColler: (String) -> Void = { _ in }
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

    init(stockage: RappelsStore = RappelsStore(url: RappelsStore.urlParDefaut)) {
        self.stockage = stockage
        rappels = stockage.lire()
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
        telechargementsSource.surRefus = {
            Settings.ilotTelechargements = false
            Log.ecrire("téléchargements : accès au dossier refusé, réglage éteint")
            NotificationCenter.default.post(name: .verbeIlotReglagesRelus, object: nil)
        }
        lecture.modele.surClicIlot = { [weak self] in self?.moteur.clicForme() }
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
    }

    func arreter() {
        lecture.arreter()
        notificationsSource.arreter()
        energieSource.arreter(); appareilsSource.arreter()
        telechargementsSource.arreter()
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
        moteur.donneesChangees()
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
            if moteur.fenetreOuverte, [.accueil, .rappelListe, .lectureEtendu, .lectureMinuteur].contains(courante) {
                armeFormulaire = courante == .rappelListe
                armeJusqua = maintenant().addingTimeInterval(60)
            }
        } else if armeJusqua > maintenant() {
            armeJusqua = maintenant().addingTimeInterval(12)   // le temps de la transcription
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
    private func depliage() {
        if let e = HistoriqueStore.shared.historique.entrees.first(where: { $0.insere || !$0.texte.isEmpty }) {
            let texte = e.texte.trimmingCharacters(in: .whitespacesAndNewlines)
            moteur.derniereDictee = (String(texte.prefix(90)), ageLisible(e.date))
        } else { moteur.derniereDictee = nil }
        moteur.rendezVousSuivant = PlanAgenda.prochain(evenements, a: maintenant())
        moteur.rappelsAVenir = rappels.aVenir(a: maintenant())
        if Settings.ilotEnergie, appareilsSource.actif { appareilsSource.relireSiAncien() }
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
        case .minuteurArreter: arreterLeMinuteur(); moteur.fermer()
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
        case .collerLaDerniereDictee:
            if let d = HistoriqueStore.shared.historique.entrees.first?.texte, !d.isEmpty { moteur.fermer(); surColler(d) }
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

    func lancerLeMinuteur(secondes: Double, bandeau: Bool) {
        guard Settings.ilotMinuteur else { return }
        let t = maintenant()
        minuteur = MinuteurIlot(secondes: secondes, depuis: t)
        moteur.minuteur = minuteur
        if bandeau, let m = minuteur {
            moteur.annoncer(bandeau: BandeauIlot(vue: .minuteurLance, jusqua: t.addingTimeInterval(2.4), ligne1: "Minuteur lancé",
                                                 ligne2: FormatIlot.minutes(m.total) + " \u{00B7} fin à " + FormatIlot.heure(m.heureDeFin(a: t))))
        }
        moteur.fermer()
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
