import AppKit
import AVFoundation
import DicteeCore

/// Chef d'orchestre des notes de réunion : lancer, mettre en pause, arrêter ; capter le micro (Moi) et le son du Mac (Eux) sur deux
/// pistes ; transcrire au fil de l'eau ; écrire la note après l'arrêt ; montrer l'état dans l'îlot (IlotReunion.swift : la réunion y est
/// une activité, avec son direct). Toutes les transitions sont dans `MachineReunion` (logique pure, contrôlée) ; ici on les applique.
///
/// Dictée pendant une réunion : la touche fn reste possible. La réunion a son propre moteur micro ; la dictée garde le sien et passe
/// devant (l'îlot s'efface le temps de la dictée). Ce que tu dictes est aussi dit dans la pièce : il se retrouve donc aussi dans « Moi ».
@MainActor
final class ReunionController: ObservableObject {
    /// Ce qui s'affiche en tête de la liste des réunions pendant qu'une réunion est en cours ou en traitement (nil : rien).
    @Published private(set) var libelleEnCours: String?
    @Published private(set) var phase: PhaseReunion = .repos

    let store: ReunionStore
    private var machine = MachineReunion()
    private var session: Session?
    private var suiveur = SuiveurAppel()
    private var minuteurs: [Timer] = []
    private var annonce: DispatchWorkItem?

    /// L'app ouvre la note (fenêtre principale, onglet Réunions).
    var surOuvrirNote: (UUID) -> Void = { _ in }
    var enregistre: Bool { machine.enregistre }
    /// Ce que l'îlot montre : la réunion qui s'enregistre (le temps, le direct, « Ce que j'ai raté »…) et l'annonce du moment.
    var surIlot: (ReunionIlot?, AnnonceReunion?) -> Void = { _, _ in }
    /// La souris est-elle sur l'îlot ? Une annonce (« Note prête ») ne se retire pas sous le pointeur.
    var annonceSurvolee: () -> Bool = { false }
    /// « Ce que j'ai raté » : le résumé des dernières minutes (le même service que la note ; remplacé dans les essais).
    var resumer: ([SegmentReunion]) async throws -> [String] = { try await GenerationNote().rattraper($0) }
    /// L'heure (injectable).
    var maintenant: () -> Date = { Date() }
    private(set) var etatIlot: ReunionIlot?
    /// L'app de l'appel qu'on a proposé de noter (« Noter » la garde pour l'en-tête de la carte).
    private var appProposee: String?
    /// Ce qui se passe après l'arrêt (« Transcription, 3 morceaux », « Note en préparation, partie 2 sur 4 »).
    private var etapeTraitement = "Transcription\u{2026}"
    private var finPoint: DispatchWorkItem?
    private var rattrapage: Task<Void, Never>?

    private final class Session: @unchecked Sendable {
        let id = UUID()
        var reunion: Reunion
        let horloge = HorlogeReunion()
        let moi: PisteReunion
        let eux: PisteReunion
        let micro = MicroReunion()
        let son = SonSysteme()
        let transcripteur = TranscriptionReunion()
        let verrou = NSLock()
        var segmentsMoi: [SegmentReunion] = []
        var segmentsEux: [SegmentReunion] = []
        var points: [Double] = []
        var sonSystemeActif = false
        var derniereSauvegarde = Date.distantPast
        init(reunion: Reunion, fichiers: (Locuteur) -> URL?) {
            self.reunion = reunion
            moi = PisteReunion(locuteur: .moi, fichierSon: fichiers(.moi))
            eux = PisteReunion(locuteur: .eux, fichierSon: fichiers(.eux))
            moi.horloge = { [horloge] in horloge.temps() }
            eux.horloge = { [horloge] in horloge.temps() }
        }
        func ajouter(_ s: SegmentReunion) {
            verrou.lock(); defer { verrou.unlock() }
            if s.locuteur == .moi { segmentsMoi.append(s) } else { segmentsEux.append(s) }
        }
        func copies() -> ([SegmentReunion], [SegmentReunion]) { verrou.lock(); defer { verrou.unlock() }; return (segmentsMoi, segmentsEux) }
    }

    init(store: ReunionStore? = nil) {
        self.store = store ?? ReunionStore.shared
    }

    /// Un geste dans l'îlot.
    func agir(_ a: ActionIlot) {
        switch a {
        case .reunionNoter: lancer()
        case .reunionRefuser: refuserProposition()
        case .reunionPause: pause()
        case .reunionReprendre: reprendre()
        case .reunionArreter: arreter()
        case .reunionPoint: ajouterUnPoint()
        case .reunionRattrapage: rattraper()
        case .reunionDirect: fermerRattrapage()
        case .reunionOuvrirNote: ouvrirDerniereNote()
        default: break
        }
    }

    // MARK: lancer / arrêter

    /// ⌥⌘N : lance la réunion, ou l'arrête si elle est en cours.
    func basculer() {
        if machine.enregistre { arreter() } else { lancer() }
    }

    func lancer() {
        guard !machine.enregistre else { return }
        guard Permissions.microOK else {
            Log.ecrire("réunion refusée : micro non autorisé")
            annoncerMessage("Micro non autorisé, voir les Réglages")
            return
        }
        guard GroqClient.shared.cleDisponible else {
            Log.ecrire("réunion refusée : clé Groq absente")
            annoncerMessage("Clé Groq manquante, voir les Réglages")
            return
        }
        annonce?.cancel()
        if case .proposition(let app) = machine.phase { appProposee = app } else { appProposee = nil }
        let reunion = Reunion(debut: Date(), etat: .enregistrement, sonGarde: Settings.garderSonReunions)
        let s = Session(reunion: reunion, fichiers: { [store] l in Settings.garderSonReunions ? store.fichierSon(reunion, l) : nil })
        session = s
        machine.lancer()
        store.enregistrer(reunion)
        Log.ecrire("réunion : début (son gardé : \(Settings.garderSonReunions ? "oui" : "non"))")

        s.moi.surMorceau = { [weak s] m in s?.transcripteur.soumettre(m) }
        s.eux.surMorceau = { [weak s] m in s?.transcripteur.soumettre(m) }
        s.transcripteur.surSegment = { [weak self, weak s] seg in
            guard let s else { return }
            s.ajouter(seg)
            Task { @MainActor in self?.segmentRecu(s) }
        }
        s.transcripteur.surProgression = { [weak self, weak s] n in
            Task { @MainActor in
                guard let self, let s, self.machine.phase == .traitement, self.session !== s || !self.machine.enregistre else { return }
                self.etapeTraitement = n > 0 ? "Transcription, \(n) morceau\(n > 1 ? "x" : "") à finir" : "Note en préparation"
                self.majPhase()
            }
        }

        var e = ReunionIlot()
        e.depuis = maintenant()
        e.app = appProposee
        etatIlot = e
        rafraichirEncoche()
        Retours.reunionDebut()
        demarrerLesSources(s)
        demarrerMinuteurs(s)
    }

    /// Le micro et le son du Mac démarrent hors du fil principal (macOS peut afficher sa fenêtre d'autorisation du son du Mac).
    private func demarrerLesSources(_ s: Session) {
        Task.detached { [weak self] in
            do { try s.micro.demarrer { s.moi.traiter($0) } }
            catch {
                Log.ecrire("réunion : micro impossible (\(error.localizedDescription))")
                await MainActor.run { [weak self] in self?.echecMicro(s) }
                return
            }
            do {
                try s.son.demarrer { s.eux.traiter($0) }
                s.sonSystemeActif = true
            } catch {
                Log.ecrire("réunion : son du Mac impossible (\(error.localizedDescription)) -> micro seul")
                await MainActor.run { [weak self] in self?.sonSystemeRefuse(s) }
            }
        }
    }

    private func echecMicro(_ s: Session) {
        guard session === s else { return }
        arreterLesSources(s)
        s.moi.terminer(); s.eux.terminer()
        s.transcripteur.annuler()
        store.supprimer(id: s.reunion.id)
        session = nil
        arreterMinuteurs()
        machine = MachineReunion()
        majPhase()
        annoncerMessage("Micro indisponible, réunion non lancée")
    }

    private func sonSystemeRefuse(_ s: Session) {
        guard session === s else { return }
        s.reunion.avertissements.append("Le son du Mac n'a pas pu être capté : seul ton micro est dans cette note. Vérifie, dans Réglages Système › Confidentialité et sécurité, l'autorisation d'enregistrer le son du système pour Verbe.")
        etatIlot?.microSeul = true
        store.enregistrer(s.reunion)
        rafraichirEncoche()
    }

    private func arreterLesSources(_ s: Session) {
        Task.detached { s.micro.arreter(); s.son.arreter() }
    }

    func pause() {
        guard let s = session, machine.pause() else { return }
        s.horloge.pause()
        s.moi.suspendre(); s.eux.suspendre()
        Log.ecrire("réunion : pause à \(FormatReunion.horloge(s.horloge.temps()))")
        etatIlot?.duree = s.horloge.temps(); etatIlot?.depuis = nil; etatIlot?.enPause = true
        majPhase()
    }

    func reprendre() {
        guard let s = session, machine.reprendre() else { return }
        s.horloge.reprendre()
        s.moi.reprendre(); s.eux.reprendre()
        Log.ecrire("réunion : reprise")
        etatIlot?.duree = s.horloge.temps(); etatIlot?.depuis = maintenant(); etatIlot?.enPause = false
        majPhase()
    }

    func arreter() {
        guard let s = session, machine.arreter() else { return }
        session = nil
        s.horloge.pause()
        let duree = s.horloge.temps()
        // Les pistes envoient leur dernier morceau, puis les sources se coupent.
        s.moi.terminer(); s.eux.terminer()
        arreterLesSources(s)
        arreterMinuteurs()
        Retours.reunionFin()
        Log.ecrire("réunion : arrêt à \(FormatReunion.horloge(duree)) (\(s.transcripteur.restants) morceau(x) encore à transcrire)")
        rattrapage?.cancel(); rattrapage = nil
        finPoint?.cancel()
        etatIlot = nil
        etapeTraitement = s.transcripteur.restants > 0 ? "Transcription de la fin de l\u{2019}appel" : "Note en préparation"
        s.reunion.duree = duree
        s.reunion.points = s.points.isEmpty ? nil : s.points
        s.reunion.etat = .transcription
        store.enregistrer(s.reunion)
        majPhase()
        libelleEnCours = "Transcription en cours…"
        Task { await traiter(s) }
    }

    // MARK: après l'arrêt

    private func traiter(_ s: Session) async {
        await s.transcripteur.attendreLaFin()
        let (moi, eux) = s.copies()
        let (fusion, echos) = FusionPistes.transcription(moi: moi, eux: eux)
        var r = s.reunion
        r.segments = fusion
        if echos > 0 { Log.ecrire("réunion : \(echos) écho(s) du haut-parleur retiré(s) de la piste Moi") }
        if s.transcripteur.echecs > 0 {
            r.avertissements.append("\(s.transcripteur.echecs) passage\(s.transcripteur.echecs > 1 ? "s" : "") n'ont pas pu être transcrit\(s.transcripteur.echecs > 1 ? "s" : "") (réseau ou limite de Groq).")
        }
        if s.sonSystemeActif, s.eux.secondesRecues >= 10, !s.eux.aRecuDuSon {
            r.avertissements.append("Le son du Mac est resté totalement silencieux. Soit rien ne jouait, soit l'autorisation d'enregistrer le son du système manque (Réglages Système › Confidentialité et sécurité).")
        }
        guard !fusion.isEmpty, r.duree >= 3 else {
            Log.ecrire("réunion : rien entendu, non gardée")
            store.supprimer(id: r.id)
            terminerTraitement(note: nil, message: "Rien entendu, réunion non gardée")
            return
        }
        r.etat = .redaction
        store.enregistrer(r)
        libelleEnCours = "Note en préparation…"
        etapeTraitement = "Résumé, décisions, prochaines étapes"
        majPhase()
        do {
            let (note, retraits) = try await GenerationNote().rediger(segments: fusion, duree: r.duree, debut: r.debut) { [weak self] etape in
                Task { @MainActor in self?.etapeTraitement = etape; self?.majPhase() }
            }
            for x in retraits { Log.ecrire("réunion : garde anti-invention, retiré \(x)") }
            NoteReunion.appliquer(note, a: &r, segments: fusion)
            r.etat = .prete
        } catch {
            Log.ecrire("réunion : note impossible (\(error))")
            r.etat = .sansNote
            r.avertissements.append("La note n'a pas pu être écrite (\(error)). La transcription est gardée : « Refaire la note » réessaie.")
        }
        store.enregistrer(r)
        terminerTraitement(note: r.id, sansNote: r.etat == .sansNote)
    }

    private func terminerTraitement(note: UUID?, sansNote: Bool = false, message: String? = nil) {
        libelleEnCours = machine.enregistre ? "Réunion en cours…" : nil
        machine.traitementFini(note: note)
        if note == nil, let message { annoncerMessage(message) } else { majPhase() }
        // « Note prête » : 8 s sans clic, puis l'îlot se range (maquette, étape 10) ; la note attend dans Réunions
        if case .prete = machine.phase { programmerRetrait(apres: 8) }
    }

    /// Réécrit la note d'une réunion qui n'en a pas (la transcription est gardée) : bouton « Refaire la note ».
    func refaireLaNote(id: UUID) {
        guard var r = store.reunion(id: id), !r.segments.isEmpty, r.etat == .sansNote || r.etat == .prete else { return }
        r.etat = .redaction
        r.avertissements.removeAll { $0.hasPrefix("La note n'a pas pu être écrite") }
        store.enregistrer(r)
        libelleEnCours = "Note en préparation…"
        Task {
            do {
                let (note, _) = try await GenerationNote().rediger(segments: r.segments, duree: r.duree, debut: r.debut)
                NoteReunion.appliquer(note, a: &r, segments: r.segments)
                r.etat = .prete
            } catch {
                r.etat = .sansNote
                r.avertissements.append("La note n'a pas pu être écrite (\(error)). La transcription est gardée : « Refaire la note » réessaie.")
            }
            store.enregistrer(r)
            libelleEnCours = machine.enregistre ? "Réunion en cours…" : (machine.enTraitement > 0 ? "Note en préparation…" : nil)
        }
    }

    // MARK: pendant l'enregistrement

    private func segmentRecu(_ s: Session) {
        if session === s { majDirect(s) }
        guard Date().timeIntervalSince(s.derniereSauvegarde) > 5 || session !== s else { return }
        s.derniereSauvegarde = Date()
        let (moi, eux) = s.copies()
        var r = s.reunion
        r.segments = FusionPistes.transcription(moi: moi, eux: eux).segments
        r.duree = s.horloge.temps()
        r.points = s.points.isEmpty ? nil : s.points
        if session === s { s.reunion = r; store.enregistrer(r) }
    }

    /// Pendant l'enregistrement seulement : une fois par seconde, le direct est recalculé (la parole en cours, les morceaux partis chez
    /// Whisper) et poussé à l'îlot s'il a changé. Le temps, lui, s'affiche seul (l'îlot le calcule depuis l'heure de départ).
    private func demarrerMinuteurs(_ s: Session) {
        arreterMinuteurs()
        let direct = Timer(timeInterval: 1, repeats: true) { [weak self, weak s] _ in
            MainActor.assumeIsolated {
                guard let self, let s, self.session === s, self.machine.enregistre else { return }
                self.majDirect(s)
            }
        }
        direct.tolerance = 0.3
        RunLoop.main.add(direct, forMode: .common)
        minuteurs = [direct]
        // Un son du Mac qui n'a donné que des zéros pendant 15 s : on le note au journal (sans conclure : un Mac silencieux est possible).
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self, weak s] in
            guard let s, self?.session === s, s.sonSystemeActif else { return }
            Log.ecrire("réunion : son du Mac après 15 s : \(Int(s.eux.secondesRecues)) s reçues, son non nul : \(s.eux.aRecuDuSon ? "oui" : "non (silence complet : rien ne jouait, ou autorisation du son système manquante)")")
        }
    }

    /// Le direct : passages transcrits, ce qui s'entend encore, les points marqués (DirectReunion décide de l'ordre, des tours, des échos).
    private func majDirect(_ s: Session) {
        guard etatIlot != nil else { return }
        let (moi, eux) = s.copies()
        let attentes = s.transcripteur.attentes() + [s.moi.parole(), s.eux.parole()].compactMap { $0 }
        let lignes = DirectReunion.lignes(moi: moi, eux: eux, attentes: attentes, points: s.points)
        guard lignes != etatIlot?.lignes else { return }
        etatIlot?.lignes = lignes
        rafraichirEncoche()
    }

    // MARK: « Ajouter un point », « Ce que j'ai raté »

    /// Marque le moment (secondes de réunion) : il apparaît dans le direct, puis dans la note et l'export.
    private func ajouterUnPoint() {
        guard let s = session, machine.enregistre else { return }
        let t = s.horloge.temps()
        s.points.append(t)
        s.reunion.points = s.points
        store.enregistrer(s.reunion)
        Log.ecrire("réunion : point marqué à \(FormatReunion.horloge(t))")
        etatIlot?.rattrapage = .ferme
        rattrapage?.cancel(); rattrapage = nil
        etatIlot?.pointFait = true
        majDirect(s)
        rafraichirEncoche()
        finPoint?.cancel()
        let item = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.etatIlot?.pointFait = false; self?.rafraichirEncoche() } }
        finPoint = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: item)
    }

    /// Les 3 dernières minutes en deux ou trois puces, par le même service que la note (seulement ces minutes-là sont envoyées).
    private func rattraper() {
        guard let s = session, machine.enregistre, etatIlot != nil else { return }
        let (moi, eux) = s.copies()
        let segments = DirectReunion.dernieresMinutes(moi: moi, eux: eux, maintenant: s.horloge.temps(), secondes: RattrapageReunion.fenetre)
        rattrapage?.cancel()
        guard !segments.isEmpty else {
            etatIlot?.rattrapage = .echec("Rien de nouveau ces 3 dernières minutes.")
            rafraichirEncoche(); return
        }
        etatIlot?.rattrapage = .enCours
        rafraichirEncoche()
        let resumer = self.resumer
        rattrapage = Task { [weak self] in
            let resultat: EtatRattrapage
            do { resultat = .pret(try await resumer(segments)) }
            catch is CancellationError { return }
            catch {
                Log.ecrire("réunion : « Ce que j'ai raté » impossible (\(error))")
                resultat = .echec("Résumé impossible pour l\u{2019}instant (réseau ou limite de Groq).")
            }
            guard let self, !Task.isCancelled, self.session === s, self.etatIlot?.rattrapage == .enCours else { return }
            self.etatIlot?.rattrapage = resultat
            self.rafraichirEncoche()
        }
    }

    private func fermerRattrapage() {
        rattrapage?.cancel(); rattrapage = nil
        guard etatIlot?.rattrapage != .ferme else { return }
        etatIlot?.rattrapage = .ferme
        rafraichirEncoche()
    }

    private func arreterMinuteurs() { minuteurs.forEach { $0.invalidate() }; minuteurs = [] }

    // MARK: îlot

    private func majPhase() {
        phase = machine.phase
        rafraichirEncoche()
    }

    /// Pousse à l'îlot ce qu'il doit montrer : la réunion qui s'enregistre (activité) et l'annonce du moment.
    private func rafraichirEncoche() {
        phase = machine.phase
        if !machine.enregistre { etatIlot = nil }
        surIlot(etatIlot, annonceActuelle())
    }

    private func annonceActuelle() -> AnnonceReunion? {
        switch machine.phase {
        case .repos, .enregistrement: return nil
        case .proposition(let app): return .propose(app: app)
        case .traitement: return .prepare(etape: etapeTraitement)
        case .message(let t): return .message(t)
        case .prete(let id):
            let r = store.reunion(id: id)
            return .prete(id: id, titre: r?.titreAffiche ?? "", duree: r?.duree ?? 0, sansNote: r?.etat == .sansNote)
        }
    }

    private func annoncerMessage(_ texte: String) {
        machine.message(texte)
        majPhase()
        guard case .message(texte) = machine.phase else { return }
        programmerRetrait(apres: 3)
    }

    /// Referme l'annonce affichée (message, note prête, proposition) après un délai, si elle n'a pas changé entre-temps.
    private func programmerRetrait(apres secondes: Double) {
        annonce?.cancel()
        let avant = machine.phase
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.machine.phase == avant else { return }
            // la souris est sur l'annonce : elle reste (même règle que les bandeaux de l'îlot)
            if self.annonceSurvolee() { self.programmerRetrait(apres: 1.5); return }
            if case .proposition = avant { self.machine.refuserProposition() } else { self.machine.acquitter() }
            self.majPhase()
        }
        annonce = item
        DispatchQueue.main.asyncAfter(deadline: .now() + secondes, execute: item)
    }

    private func ouvrirDerniereNote() {
        guard case .prete(let id) = machine.phase else { return }
        annonce?.cancel()
        machine.acquitter()
        majPhase()
        surOuvrirNote(id)
    }

    // MARK: proposition « Noter cet appel ? » (jamais d'enregistrement sans clic)

    /// Aucun sondage au repos : le système prévient quand une app commence ou arrête d'écouter le micro. Seulement PENDANT qu'une
    /// app d'appel écoute, un relevé toutes les 3 s tient le compte des 6 s d'écoute continue avant de proposer (SuiveurAppel).
    private var veilleProcessus: VeilleProcessusAudio?
    private var releveSuivant: DispatchWorkItem?
    func demarrerSurveillanceDesAppels() {
        guard veilleProcessus == nil else { return }
        let v = VeilleProcessusAudio { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.releverLesAppels() } }
        }
        veilleProcessus = v
        v.demarrer()
    }

    private func releverLesAppels() {
        releveSuivant?.cancel(); releveSuivant = nil
        guard Settings.proposerLesAppels else { return }
        let app = DetectionAppel.appEnAppel(bundleIDs: ProcessusAudio.identifiantsEcoutantLeMicro())
        if app != nil {
            let item = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.releverLesAppels() } }
            releveSuivant = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: item)
        }
        guard let proposee = suiveur.observer(app: app, reunionEnCours: machine.enregistre, maintenant: BudgetRequetes.maintenant()) else { return }
        guard machine.proposer(app: proposee.nom) else { return }
        Log.ecrire("réunion : \(proposee.nom) utilise le micro, proposition « Noter cet appel ? »")
        majPhase()
        programmerRetrait(apres: 15)
    }

    private func refuserProposition() {
        annonce?.cancel()
        machine.refuserProposition()
        majPhase()
    }
}
