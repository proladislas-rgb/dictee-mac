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
    /// Ce qui se passe après l'arrêt : l'étape (« Relecture de tout l'appel »…) et la progression (0 à 1) montrées dans l'îlot.
    private var etapeTraitement = PreparationNote.relecture
    private var progresTraitement = 0.0
    /// La relecture de tout l'enregistrement après l'appel (réseau remplaçable dans les essais).
    var relecture = RelectureAudio()
    /// La rédaction de la note (réseau remplaçable dans les essais) : passages, durée, début, avance(fait, total).
    var rediger: RedigerNote = { segments, duree, debut, avance in
        try await GenerationNote().rediger(segments: segments, duree: duree, debut: debut, avance: avance)
    }
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
        /// Les passages de parole vus pendant l'appel, voix par voix : ce que la relecture renverra (sans les silences). Les deux voix
        /// sont toujours là (une liste vide : cette voix n'a rien dit, la relecture n'envoie rien).
        var passages: [Locuteur: [PassageParole]] = [.moi: [], .eux: []]
        var points: [Double] = []
        var sonSystemeActif = false
        var derniereSauvegarde = Date.distantPast
        /// Change à chaque passage transcrit ou entendu : la sauvegarde de 5 s ne réécrit que si quelque chose a changé.
        private var version = 0
        var versionSauvee = -1
        init(reunion: Reunion, fichiers: (Locuteur) -> URL?) {
            self.reunion = reunion
            // le son n'est que de passage (réglage « garder » éteint) : hors de Time Machine
            moi = PisteReunion(locuteur: .moi, fichierSon: fichiers(.moi), horsSauvegarde: !reunion.sonGarde)
            eux = PisteReunion(locuteur: .eux, fichierSon: fichiers(.eux), horsSauvegarde: !reunion.sonGarde)
            moi.horloge = { [horloge] in horloge.temps() }
            eux.horloge = { [horloge] in horloge.temps() }
        }
        func ajouter(_ s: SegmentReunion) {
            verrou.lock(); defer { verrou.unlock() }
            if s.locuteur == .moi { segmentsMoi.append(s) } else { segmentsEux.append(s) }
            version += 1
        }
        func copies() -> ([SegmentReunion], [SegmentReunion]) { verrou.lock(); defer { verrou.unlock() }; return (segmentsMoi, segmentsEux) }
        func noterPassage(_ m: MorceauReunion) {
            verrou.lock(); defer { verrou.unlock() }
            passages[m.locuteur, default: []].append(PassageParole(debut: m.debut, fin: m.debut + m.duree))
            version += 1
        }
        func versionActuelle() -> Int { verrou.lock(); defer { verrou.unlock() }; return version }
        func copiePassages() -> [Locuteur: [PassageParole]] { verrou.lock(); defer { verrou.unlock() }; return passages }
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
        // le son des deux pistes est toujours écrit sur ce Mac (0600) : la relecture d'après l'appel en a besoin ; il est effacé dès la
        // note faite, sauf si « Garder le son des réunions » est actif
        let s = Session(reunion: reunion, fichiers: { [store] l in store.fichierSon(reunion, l) })
        session = s
        machine.lancer()
        store.enregistrer(reunion)
        Log.ecrire("réunion : début (son gardé : \(Settings.garderSonReunions ? "oui" : "non"))")

        s.moi.surMorceau = { [weak s] m in s?.noterPassage(m); s?.transcripteur.soumettre(m) }
        s.eux.surMorceau = { [weak s] m in s?.noterPassage(m); s?.transcripteur.soumettre(m) }
        s.transcripteur.surSegment = { [weak self, weak s] seg in
            guard let s else { return }
            s.ajouter(seg)
            Task { @MainActor in self?.segmentRecu(s) }
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
        guard sauver(s) else { return }
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
        etapeTraitement = PreparationNote.relecture; progresTraitement = 0
        // effacée pendant l'appel (onglet Réunions) : rien n'est recréé
        guard let actuelle = store.reunion(id: s.reunion.id) else {
            s.transcripteur.annuler()
            Log.ecrire("réunion : effacée pendant l'enregistrement, aucune note")
            terminerTraitement(note: nil, message: "Réunion effacée")
            return
        }
        var r = Self.photo(s, actuelle: actuelle)
        r.etat = .transcription
        s.reunion = r
        store.enregistrer(r)
        majPhase()
        libelleEnCours = "Transcription en cours…"
        Task { await traiter(s) }
    }

    /// Verbe se ferme pendant l'appel (⌘Q, fin de session) : les sources se coupent, les pistes envoient leur dernier morceau (noté
    /// dans les passages) et ferment leur fichier son, la réunion est enregistrée avec ses passages de parole, et on ATTEND l'écriture
    /// sur le disque. Au lancement suivant elle passe en « sans note » ; « Refaire la note » relit le son (gardé quelques jours).
    func terminerAvantDeQuitter() {
        if let s = session {
            session = nil
            arreterMinuteurs()
            s.horloge.pause()
            s.micro.arreter(); s.son.arreter()
            s.moi.terminer(); s.eux.terminer()
            s.transcripteur.annuler()
            if let actuelle = store.reunion(id: s.reunion.id) {
                s.reunion = Self.photo(s, actuelle: actuelle)
                store.enregistrer(s.reunion)
                Log.ecrire("réunion : Verbe se ferme pendant l'appel, réunion et son gardés (\(FormatReunion.horloge(s.reunion.duree)))")
            }
        }
        store.attendreEcritures()
    }

    // MARK: après l'arrêt

    typealias RedigerNote = @Sendable ([SegmentReunion], Double, Date, @escaping @Sendable (Int, Int) -> Void) async throws -> (note: NoteBrute, retraits: [String])

    /// Après l'arrêt : tout l'appel est relu avec le modèle précis, puis la note s'écrit. L'îlot montre l'étape et la progression.
    /// Quand le son est sur le disque, les morceaux du direct pas encore partis ne partent plus (la relecture les reprend avec le
    /// modèle précis) : on n'attend que ceux déjà chez Groq, qui servent de repli à un lot que la relecture n'aurait pas pu refaire.
    private func traiter(_ s: Session) async {
        let r0 = s.reunion
        let fichiers = [Locuteur.moi: store.fichierSon(r0, .moi), .eux: store.fichierSon(r0, .eux)]
        if fichiers.values.contains(where: { FileManager.default.fileExists(atPath: $0.path) }) { s.transcripteur.abandonnerLaFile() }
        await s.transcripteur.attendreLaFin()
        let (moi, eux) = s.copies()
        await finir(r0, passages: s.copiePassages(), direct: moi + eux, fichiers: fichiers, echecsDirect: s.transcripteur.echecs,
                    sonMuet: s.sonSystemeActif && s.eux.secondesRecues >= 10 && !s.eux.aRecuDuSon)
    }

    /// La fin du traitement, sans la session (l'essai l'appelle avec une relecture et une rédaction factices, dans un dossier à part) :
    /// relecture, note, avertissements, son effacé ou gardé, annonce. Rien n'est effacé si la relecture a échoué ; rien n'est recréé
    /// si la réunion a été effacée pendant ce temps ; ce que l'utilisateur a changé entre-temps (titre, orateurs) est gardé.
    func finir(_ r0: Reunion, passages: [Locuteur: [PassageParole]], direct: [SegmentReunion], fichiers: [Locuteur: URL],
               echecsDirect: Int = 0, sonMuet: Bool = false) async {
        let prepare = await Self.preparer(r0, passages: passages, direct: direct, fichiers: fichiers, relecture: relecture, rediger: rediger,
                                          surNote: { [weak self] r in
            Task { @MainActor in
                // jamais par-dessus la note déjà rangée (la transcription relue n'est enregistrée que si la réunion attend encore)
                guard let self, let actuelle = self.store.reunion(id: r.id), actuelle.etat == .transcription else { return }
                self.store.enregistrer(ArchiveReunions.garderLesModifications(de: actuelle, depuis: r0, dans: r))
                self.libelleEnCours = "Note en préparation…"
            }
        }) { [weak self] p, etape in
            Task { @MainActor in self?.avancer(p, etape) }
        }
        guard var r = prepare else {
            Log.ecrire("réunion : rien entendu, non gardée")
            store.supprimer(id: r0.id)
            terminerTraitement(note: nil, message: "Rien entendu, réunion non gardée")
            return
        }
        guard let actuelle = store.reunion(id: r0.id) else {
            Log.ecrire("réunion : effacée pendant la préparation de la note, rien n'est réécrit")
            terminerTraitement(note: nil)
            return
        }
        r = ArchiveReunions.garderLesModifications(de: actuelle, depuis: r0, dans: r)
        if echecsDirect > 0, r.relue != true {
            r.avertissements.append("\(echecsDirect) passage\(echecsDirect > 1 ? "s" : "") du direct n'\(echecsDirect > 1 ? "ont" : "a") pas pu être transcrit\(echecsDirect > 1 ? "s" : "") (réseau ou limite de Groq).")
        }
        if sonMuet {
            r.avertissements.append("Le son du Mac est resté totalement silencieux. Soit rien ne jouait, soit l'autorisation d'enregistrer le son du système manque (Réglages Système › Confidentialité et sécurité).")
        }
        rangerLeSon(&r)
        store.enregistrer(r)
        avancer(1, PreparationNote.redaction)
        if r.segments.isEmpty {
            // ni relecture ni direct : pas de « Transcription prête » vide ; la réunion attend dans Réunions, son gardé
            terminerTraitement(note: nil, message: "Relecture impossible, son gardé")
        } else {
            terminerTraitement(note: r.id, sansNote: r.etat == .sansNote)
        }
    }

    /// Le son n'a servi qu'à la relecture : il part quand la note est prête ET que tout l'appel a été relu (sauf si le réglage demande
    /// de le garder, pour réécouter un moment). Sinon il reste `joursSonEnAttente` jours pour « Refaire la note », et la note le dit.
    private func rangerLeSon(_ r: inout Reunion) {
        r.avertissements.removeAll { $0.hasPrefix(Self.avertissementSonGarde) }
        if ArchiveReunions.sonInutile(apresNote: r) {
            store.effacerSon(r)
            r.passagesParVoix = [:]
        } else if !r.sonGarde, store.sonPresent(r, .moi) || store.sonPresent(r, .eux) {
            r.avertissements.append("\(Self.avertissementSonGarde) \(ArchiveReunions.joursSonEnAttente) jours sur ce Mac, le temps de « Refaire la note ».")
        }
    }
    static let avertissementSonGarde = "Le son de l\u{2019}appel est gardé"
    static let avertissementRelecture = "pas pu être relu"

    /// La relecture puis la note, sans rien du contrôleur (l'essai l'appelle avec une relecture et une rédaction factices) : la réunion
    /// prête (ou « sans note » si la rédaction ou la relecture a échoué), nil seulement si rien n'a été entendu (aucun passage, ou une
    /// relecture complète qui n'a rien trouvé) : une relecture en échec ne fait JAMAIS effacer l'appel. `surNote` : la transcription relue, juste avant
    /// la rédaction (elle est enregistrée tout de suite : rien ne se perd si la rédaction échoue ou si Verbe est fermé).
    nonisolated static func preparer(_ depart: Reunion, passages: [Locuteur: [PassageParole]], direct: [SegmentReunion], fichiers: [Locuteur: URL],
                                     relecture: RelectureAudio, rediger: RedigerNote, surNote: @escaping @Sendable (Reunion) -> Void = { _ in },
                                     avance: @escaping @Sendable (Double, String) -> Void) async -> Reunion? {
        avance(0, PreparationNote.relecture)
        let relu = await relecture.relire(passages: passages, direct: direct, fichiers: fichiers, duree: depart.duree) { fait, total in
            avance(PreparationNote.progresRelecture(fait: fait, sur: total), PreparationNote.relecture)
        }
        let (fusion, echos) = FusionPistes.transcription(moi: relu.segments.filter { $0.locuteur == .moi }, eux: relu.segments.filter { $0.locuteur == .eux },
                                                         dureeMax: RelectureReunion.tourMax)
        if echos > 0 { Log.ecrire("réunion : \(echos) écho(s) du haut-parleur retiré(s) de la piste Moi") }
        guard depart.duree >= 3 else { return nil }
        var r = depart
        r.passagesParVoix = passages
        // relue : TOUT l'appel relu ; sinon le son reste pour « Refaire la note »
        r.relue = relu.complete
        if fusion.isEmpty {
            // vraiment rien entendu (la relecture a tout relu, ou il n'y avait aucun passage) : la réunion n'est pas gardée ; mais si la
            // relecture a échoué, l'enregistrement est intact sur le disque : la réunion reste, sans note, pour réessayer
            guard relu.echoues > 0 else { return nil }
            r.etat = .sansNote
            r.avertissements.append("L\u{2019}appel n\u{2019}a pas pu être relu (réseau ou limite de Groq) et le direct n\u{2019}a rien donné. « Refaire la note » réessaiera.")
            return r
        }
        r.segments = fusion
        if relu.echoues > 0 {
            r.avertissements.append("\(relu.echoues) passage\(relu.echoues > 1 ? "s" : "") de l\u{2019}appel n\u{2019}\(relu.echoues > 1 ? "ont" : "a") pas pu être relu\(relu.echoues > 1 ? "s" : "") (réseau ou limite de Groq) : c\u{2019}est la transcription du direct.")
        }
        r.etat = .redaction
        surNote(r)
        avance(PreparationNote.progresRedaction(fait: 0, sur: 1), PreparationNote.redaction)
        do {
            let (note, retraits) = try await rediger(fusion, r.duree, r.debut) { fait, total in
                avance(PreparationNote.progresRedaction(fait: fait, sur: total), PreparationNote.redaction)
            }
            for x in retraits { Log.ecrire("réunion : garde anti-invention, retiré \(x)") }
            NoteReunion.appliquer(note, a: &r, segments: fusion)
            r.etat = .prete
        } catch {
            Log.ecrire("réunion : note impossible (\(error))")
            r.etat = .sansNote
            r.avertissements.append("La note n'a pas pu être écrite (\(error)). La transcription est gardée : « Refaire la note » réessaie.")
        }
        return r
    }

    /// La progression ne recule jamais (deux traitements qui se chevauchent montrent le plus avancé).
    private func avancer(_ p: Double, _ etape: String) {
        guard machine.phase == .traitement || machine.enTraitement > 0 else { return }
        if p < progresTraitement && etape == etapeTraitement { return }
        progresTraitement = max(progresTraitement, p); etapeTraitement = etape
        majPhase()
    }

    private func terminerTraitement(note: UUID?, sansNote: Bool = false, message: String? = nil) {
        libelleEnCours = machine.enregistre ? "Réunion en cours…" : nil
        machine.traitementFini(note: note)
        if note == nil, let message { annoncerMessage(message) } else { majPhase() }
        // « Note prête » : 8 s sans clic, puis l'îlot se range (maquette, étape 10) ; la note attend dans Réunions
        if case .prete = machine.phase { programmerRetrait(apres: 8) }
    }

    /// Réécrit la note d'une réunion : bouton « Refaire la note » (note pas écrite, appel pas entièrement relu, Verbe fermé pendant
    /// l'appel). Si le son est encore là et que l'appel n'a pas été entièrement relu, il est relu d'abord, avec les passages de parole
    /// enregistrés pendant l'appel. Rien n'est effacé tant que la note n'est pas prête ET l'appel entièrement relu.
    @discardableResult
    func refaireLaNote(id: UUID) -> Task<Void, Never>? {
        guard var r = store.reunion(id: id), r.etat == .sansNote || r.etat == .prete else { return nil }
        let sonLa = store.sonPresent(r, .moi) || store.sonPresent(r, .eux)
        guard !r.segments.isEmpty || sonLa else { return nil }
        r.etat = .redaction
        r.avertissements.removeAll { $0.hasPrefix("La note n'a pas pu être écrite") }
        store.enregistrer(r)
        let depart = r
        libelleEnCours = "Note en préparation…"
        let fichiers = [Locuteur.moi: store.fichierSon(r, .moi), .eux: store.fichierSon(r, .eux)]
        let relire = r.relue != true && sonLa
        return Task {
            if relire {
                let relu = await relecture.relire(passages: r.passagesParVoix, direct: r.segments, fichiers: fichiers, duree: r.duree) { _, _ in }
                if relu.relue {
                    r.segments = FusionPistes.transcription(moi: relu.segments.filter { $0.locuteur == .moi }, eux: relu.segments.filter { $0.locuteur == .eux },
                                                            dureeMax: RelectureReunion.tourMax).segments
                }
                if relu.lots > 0 { r.relue = relu.complete }
                if relu.complete { r.avertissements.removeAll { $0.contains(Self.avertissementRelecture) } }
            }
            if r.segments.isEmpty {
                r.etat = .sansNote
                if !r.avertissements.contains(where: { $0.contains(Self.avertissementRelecture) }) {
                    r.avertissements.append("L\u{2019}appel n\u{2019}a pas pu être relu (réseau ou limite de Groq). « Refaire la note » réessaiera.")
                }
            } else {
                do {
                    let (note, _) = try await rediger(r.segments, r.duree, r.debut) { _, _ in }
                    NoteReunion.appliquer(note, a: &r, segments: r.segments)
                    r.etat = .prete
                } catch {
                    r.etat = .sansNote
                    r.avertissements.append("La note n'a pas pu être écrite (\(error)). La transcription est gardée : « Refaire la note » réessaie.")
                }
            }
            libelleEnCours = machine.enregistre ? "Réunion en cours…" : (machine.enTraitement > 0 ? "Note en préparation…" : nil)
            // effacée pendant ce temps : rien n'est recréé ; sinon ce qui a été changé entre-temps est gardé
            guard let actuelle = store.reunion(id: id) else { return }
            r = ArchiveReunions.garderLesModifications(de: actuelle, depuis: depart, dans: r)
            rangerLeSon(&r)
            store.enregistrer(r)
        }
    }

    // MARK: pendant l'enregistrement

    private func segmentRecu(_ s: Session) {
        guard session === s else { return }
        majDirect(s)
        sauverSiBesoin(s)
    }

    /// Toutes les 5 s au plus, si quelque chose a changé (passage entendu ou transcrit) : la réunion en cours est enregistrée, avec
    /// ses passages de parole (rien ne se perd si Verbe s'arrête, même quand le direct échoue).
    private func sauverSiBesoin(_ s: Session) {
        guard Date().timeIntervalSince(s.derniereSauvegarde) > 5, s.versionActuelle() != s.versionSauvee else { return }
        sauver(s)
    }

    /// Enregistre la réunion en cours. Effacée entre-temps (onglet Réunions) : l'enregistrement s'arrête, sans note, et rien n'est
    /// recréé (faux dans ce cas).
    @discardableResult
    private func sauver(_ s: Session) -> Bool {
        guard session === s else { return false }
        guard let actuelle = store.reunion(id: s.reunion.id) else { abandonnerEffacee(s); return false }
        s.versionSauvee = s.versionActuelle()
        s.derniereSauvegarde = Date()
        s.reunion = Self.photo(s, actuelle: actuelle)
        store.enregistrer(s.reunion)
        return true
    }

    /// La réunion de la session telle qu'elle est maintenant : transcription du direct, durée, points, passages de parole ; le titre
    /// et les orateurs sont ceux de la version enregistrée (l'utilisateur a pu les changer pendant l'appel).
    private static func photo(_ s: Session, actuelle: Reunion) -> Reunion {
        let (moi, eux) = s.copies()
        var r = s.reunion
        r.segments = FusionPistes.transcription(moi: moi, eux: eux).segments
        r.duree = s.horloge.temps()
        r.points = s.points.isEmpty ? nil : s.points
        r.passagesParVoix = s.copiePassages()
        r.titre = actuelle.titre
        r.orateurs = actuelle.orateurs
        return r
    }

    /// La réunion en cours a été effacée : tout s'arrête, sans note (ses fichiers sont déjà effacés).
    private func abandonnerEffacee(_ s: Session) {
        guard session === s, machine.arreter() else { return }
        session = nil
        Log.ecrire("réunion : effacée pendant l'enregistrement, arrêtée sans note")
        s.horloge.pause()
        s.moi.terminer(); s.eux.terminer()
        arreterLesSources(s)
        s.transcripteur.annuler()
        arreterMinuteurs()
        rattrapage?.cancel(); rattrapage = nil
        finPoint?.cancel()
        etatIlot = nil
        terminerTraitement(note: nil, message: "Réunion effacée")
    }

    /// Pendant l'enregistrement seulement : une fois par seconde, le direct est recalculé (la parole en cours, les morceaux partis chez
    /// Whisper) et poussé à l'îlot s'il a changé. Le temps, lui, s'affiche seul (l'îlot le calcule depuis l'heure de départ).
    private func demarrerMinuteurs(_ s: Session) {
        arreterMinuteurs()
        let direct = Timer(timeInterval: 1, repeats: true) { [weak self, weak s] _ in
            MainActor.assumeIsolated {
                guard let self, let s, self.session === s, self.machine.enregistre else { return }
                self.majDirect(s)
                self.sauverSiBesoin(s)
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
        guard sauver(s) else { return }
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
        case .traitement: return .prepare(etape: etapeTraitement, progres: progresTraitement)
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
