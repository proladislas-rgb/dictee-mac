import AppKit
import AVFoundation
import DicteeCore

/// Chef d'orchestre des notes de réunion : lancer, mettre en pause, arrêter ; capter le micro (Moi) et le son du Mac (Eux) sur deux
/// pistes ; transcrire au fil de l'eau ; écrire la note après l'arrêt ; montrer l'état dans l'encoche. Toutes les transitions sont
/// dans `MachineReunion` (logique pure, contrôlée) ; ici on les applique.
///
/// Dictée pendant une réunion : la touche fn reste possible. La réunion a son propre moteur micro et sa propre fenêtre d'encoche ;
/// la dictée garde les siens et passe devant (son encoche recouvre brièvement celle de la réunion). Ce que tu dictes est aussi dit
/// dans la pièce : il se retrouve donc aussi dans la piste « Moi ».
@MainActor
final class ReunionController: ObservableObject {
    /// Ce qui s'affiche en tête de la liste des réunions pendant qu'une réunion est en cours ou en traitement (nil : rien).
    @Published private(set) var libelleEnCours: String?
    @Published private(set) var phase: PhaseReunion = .repos

    let store: ReunionStore
    let panneau = ReunionPanneau()
    private var machine = MachineReunion()
    private var session: Session?
    private var suiveur = SuiveurAppel()
    private var minuteurs: [Timer] = []
    private var annonce: DispatchWorkItem?

    /// L'app ouvre la note (fenêtre principale, onglet Réunions).
    var surOuvrirNote: (UUID) -> Void = { _ in }
    var enregistre: Bool { machine.enregistre }

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
        let m = panneau.modele
        m.surArreter = { [weak self] in self?.arreter() }
        m.surPause = { [weak self] in self?.pause() }
        m.surReprendre = { [weak self] in self?.reprendre() }
        m.surOuvrir = { [weak self] in self?.ouvrirDerniereNote() }
        m.surNoter = { [weak self] in self?.lancer() }
        m.surRefuser = { [weak self] in self?.refuserProposition() }
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
                self.panneau.modele.traitement = n > 0 ? "Transcription, \(n) morceau\(n > 1 ? "x" : "")" : "Note en préparation"
            }
        }

        let m = panneau.modele
        m.minuterie = "00:00"
        m.traceMoi = Array(repeating: 0, count: 12); m.traceEux = Array(repeating: 0, count: 12)
        m.sources = "Micro et son de l\u{2019}appel"
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
        panneau.modele.sources = "Micro seul"
        store.enregistrer(s.reunion)
    }

    private func arreterLesSources(_ s: Session) {
        Task.detached { s.micro.arreter(); s.son.arreter() }
    }

    func pause() {
        guard let s = session, machine.pause() else { return }
        s.horloge.pause()
        s.moi.suspendre(); s.eux.suspendre()
        Log.ecrire("réunion : pause à \(FormatReunion.horloge(s.horloge.temps()))")
        majPhase()
    }

    func reprendre() {
        guard let s = session, machine.reprendre() else { return }
        s.horloge.reprendre()
        s.moi.reprendre(); s.eux.reprendre()
        Log.ecrire("réunion : reprise")
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
        let m = panneau.modele
        m.minuterie = FormatReunion.horloge(duree)
        m.traitement = "Transcription…"
        s.reunion.duree = duree
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
        panneau.modele.traitement = "Note en préparation"
        do {
            let (note, retraits) = try await GenerationNote().rediger(segments: fusion, duree: r.duree, debut: r.debut) { [weak self] etape in
                Task { @MainActor in self?.panneau.modele.traitement = etape }
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
        panneau.modele.libellePrete = sansNote ? "Transcription prête" : "Note prête"
        if note == nil, let message { annoncerMessage(message) } else { majPhase() }
        if case .prete = machine.phase { programmerRetrait(apres: 25) }
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
        guard Date().timeIntervalSince(s.derniereSauvegarde) > 5 || session !== s else { return }
        s.derniereSauvegarde = Date()
        let (moi, eux) = s.copies()
        var r = s.reunion
        r.segments = FusionPistes.fusionner(moi: moi, eux: eux)
        r.duree = s.horloge.temps()
        if session === s { s.reunion = r; store.enregistrer(r) }
    }

    private func demarrerMinuteurs(_ s: Session) {
        arreterMinuteurs()
        let affichage = Timer(timeInterval: 0.1, repeats: true) { [weak self, weak s] _ in
            MainActor.assumeIsolated {
                guard let self, let s, self.session === s else { return }
                let m = self.panneau.modele
                let t = FormatReunion.horloge(s.horloge.temps())
                if m.minuterie != t { m.minuterie = t }
                ReunionEncocheModele.pousser(&m.traceMoi, s.moi.niveau())
                ReunionEncocheModele.pousser(&m.traceEux, s.eux.niveau())
            }
        }
        RunLoop.main.add(affichage, forMode: .common)
        minuteurs = [affichage]
        // Un son du Mac qui n'a donné que des zéros pendant 15 s : on le note au journal (sans conclure : un Mac silencieux est possible).
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self, weak s] in
            guard let s, self?.session === s, s.sonSystemeActif else { return }
            Log.ecrire("réunion : son du Mac après 15 s : \(Int(s.eux.secondesRecues)) s reçues, son non nul : \(s.eux.aRecuDuSon ? "oui" : "non (silence complet : rien ne jouait, ou autorisation du son système manquante)")")
        }
    }

    private func arreterMinuteurs() { minuteurs.forEach { $0.invalidate() }; minuteurs = [] }

    // MARK: encoche

    private func majPhase() {
        phase = machine.phase
        rafraichirEncoche()
    }

    private func rafraichirEncoche() {
        phase = machine.phase
        let m = panneau.modele
        m.phase = machine.phase
        if machine.phase == .repos { panneau.masquer(); return }
        if m.ouverte { panneau.ajuster() } else { panneau.afficher() }
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

    func demarrerSurveillanceDesAppels() {
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.releverLesAppels() }
        }
        RunLoop.main.add(t, forMode: .common)
    }

    private func releverLesAppels() {
        guard Settings.proposerLesAppels else { return }
        let app = DetectionAppel.appEnAppel(bundleIDs: ProcessusAudio.identifiantsEcoutantLeMicro())
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
