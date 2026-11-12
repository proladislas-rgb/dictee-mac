import AppKit
import Carbon.HIToolbox
import DicteeCore

/// Chef d'orchestre d'une dictée : reçoit les gestes de la touche fn et mène la dictée de bout en bout.
@MainActor
final class DictationController {
    enum Etat: Equatable {
        case repos
        case ecoute(mainsLibres: Bool)
    }

    /// Une dictée, de l'appui au texte final. Plusieurs peuvent se chevaucher (on redicte pendant qu'une finit).
    final class Session {
        let id: Int
        let mainsLibres: Bool
        /// Faux pour la note dictée d'un clic dans l'îlot : pas d'encoche de dictée (l'îlot montre « J'écoute… »), jamais de collage.
        var encoche = true
        /// « Lucarne, rappelle-moi… » reconnu en direct : l'îlot a pris la dictée (l'onde de la voix) ; l'encoche de la dictée est rangée.
        var voix = false
        let appCible: NSRunningApplication?
        let debut = ProcessInfo.processInfo.systemUptime
        var relachement: Double?
        let pipeline: RecordingPipeline
        /// Le son et la vibration de début ont été joués (sinon une annulation silencieuse : appui trop court).
        var retourDebutJoue = false
        var direct: (any ReconnaissanceDirecte)?
        var secours: Task<String, Never>?
        /// Lecture du champ focalisé (Accessibilité), lancée à l'appui puis au relâchement, pendant que Groq travaille.
        let champ: LectureChamp
        let transcripteur: ChunkTranscriber
        /// Relecture de sens (mots mal entendus), avec le champ lu par l'Accessibilité.
        let relecture: RelectureSession
        /// Remise au propre lancée pendant la pause d'avant le relâchement, sur le texte qu'on aurait si la parole s'arrêtait là.
        /// Remise au propre par unités de phrases pendant les longues dictées.
        var unites: NettoyageParUnites?
        var nettoyageAnticipe: (brut: String, contexte: ContexteMiseEnForme, tache: Task<Nettoyage.Resultat, Never>)?
        init(id: Int, mainsLibres: Bool, appCible: NSRunningApplication?, transcripteur: ChunkTranscriber, champ: LectureChamp) {
            self.id = id; self.mainsLibres = mainsLibres; self.appCible = appCible; self.transcripteur = transcripteur; self.champ = champ
            relecture = RelectureSession(champ: { [champ] in champ.dejaConnu() })
            // Le son de début est capté par le micro : la détection de parole ignore ses premières tranches (0,2 s en mains libres, 0,32 s en mode « tenir » où il part à 0,12 s).
            pipeline = RecordingPipeline(tranchesIgnorees: Settings.sons ? (mainsLibres ? 10 : 16) : 0)
        }
    }

    private(set) var etat: Etat = .repos {
        didSet { if (oldValue != .repos) != (etat != .repos) { surChangementEtat?(etat != .repos) } }
    }
    /// Appelé quand une dictée commence (`true`) ou finit (`false`, relâchement ou annulation) : la lecture en cours se met en pause, puis reprend.
    var surChangementEtat: ((Bool) -> Void)?
    private var courante: Session?
    private var compteur = 0
    private let audio = AudioCapture()

    let collage = Collage()
    let panneau = EnclochePanneau()
    private var ouvertureRetardee: DispatchWorkItem?

    /// Appelé quand une dictée finit sans passer par la touche fn (boutons ✕ / ✓, micro impossible) :
    /// la machine de la touche fn doit alors être remise à zéro.
    var surFinIndependante: (() -> Void)?
    /// Consulté à l'appui sur fn, AVANT tout (aucun son capté, aucun son joué) : faux = la dictée ne part pas (le micro qu'elle
    /// écouterait est coupé dans l'îlot, qui le dit lui-même).
    var peutCommencer: () -> Bool = { true }
    /// Appelé au début d'une dictée : le panneau compact se ferme (les deux ne se superposent jamais).
    var surDebut: (() -> Void)?
    var enCours: Bool { etat != .repos }
    /// Appelé quand un texte vient d'être collé : (texte, identifiant de l'app cible). Sert à la première dictée réussie.
    var surInsertion: ((String, String?) -> Void)?
    /// Appelé quand le texte n'a pas pu être écrit (champ protégé, accessibilité manquante).
    var surEchecInsertion: ((String) -> Void)?
    /// Appelé quand le texte n'est pas arrivé dans l'app : (texte, app visée). L'encoche reste ouverte avec le texte à copier.
    var surFilet: ((String, NSRunningApplication?) -> Void)?
    /// Appelé quand une dictée est passée par la reconnaissance du Mac (Groq n'a pas répondu, et pourquoi) : l'îlot le signale.
    var surRelais: ((EchecGroq) -> Void)?
    /// Appelé quand Groq a de nouveau donné le texte d'une dictée (le prochain relais se dira en entier).
    var surGroqReussi: (() -> Void)?
    /// Appelé quand la dictée aurait dû passer par le Mac mais qu'il n'est pas prêt (langue en téléchargement) : l'îlot le dit.
    var surRelaisIndisponible: ((String) -> Void)?
    /// Appelé avec le texte final avant le collage : vrai si c'était une commande de l'îlot (le texte n'est alors pas collé).
    var surInterception: ((String) -> Bool)?
    /// « Lucarne, … » cherché sur le texte de Groq, AVANT la remise au propre (l'IA, le lexique ou les raccourcis pourraient changer ou
    /// retirer le mot d'appel, et la commande serait collée dans l'app) : vrai si c'était pour Lucarne (rien n'est collé).
    var surCommandeLucarne: ((String) -> Bool)?
    /// Le texte de la note dictée d'un clic, lié à SA dictée (jamais à une échéance) : vrai s'il est devenu une note (ou une commande).
    var surNoteParClic: ((String) -> Bool)?
    /// La dictée sans encoche (la note dictée d'un clic dans l'îlot) : le niveau du micro et le texte en direct vont à l'îlot ; une fin
    /// sans texte le lui dit (rien entendu, rien reconnu).
    var surNiveauSansEncoche: ((Float) -> Void)?
    var surTexteSansEncoche: ((String) -> Void)?
    var surRienEcrit: (() -> Void)?
    /// La voix d'un rappel ou d'une note (IlotVoix.swift) : le texte en direct d'une dictée fn tenue ; vrai si l'îlot la prend (« Lucarne,
    /// rappelle-moi… ») : l'encoche se range, le niveau du micro va à l'onde de l'îlot. Puis la fin de cette dictée (texte écrit, commande
    /// faite, rien entendu, annulée), dite au plus tôt et parfois deux fois (l'îlot ne fait rien la deuxième) : l'onde s'en va si la carte
    /// ne l'a pas remplacée.
    var surVoixEnDirect: ((Int, String) -> Bool)?
    var surVoixNiveau: ((Float) -> Void)?
    var surVoixFin: ((Int) -> Void)?
    /// À appeler quand le micro vient d'être autorisé : prépare le moteur pour un départ instantané.
    func microAutorise() { audio.preparer() }
    /// Appelé quand la capture commence (`true`) ou finit (`false`) : l'icône de la barre des menus montre un trait ambre.
    var surCapture: ((Bool) -> Void)?
    /// Nombre de frappes au clavier depuis le lancement (fourni par l'écoute du clavier).
    var compteurFrappes: () -> Int = { 0 }
    /// Dernière insertion : sert de repli pour savoir ce qu'il y a avant le curseur.
    private var memoire: MemoireInsertion?

    func preparer() {
        panneau.modele.surAnnuler = { [weak self] in self?.annulerParBouton() }
        panneau.modele.surValider = { [weak self] in self?.validerParBouton() }
        Dictionnaire.creerSiAbsent()
        Orthographe.prechauffer()
        // Apprentissage automatique (une fois par jour au plus) et vocabulaire de la relecture : hors du chemin de la dictée.
        Task { @MainActor in
            MotsModele.partage.apprendreDeLHistorique()
            VocabulaireRelectureStore.partage.rafraichir()
        }
        // Le premier codage FLAC de la session coûte ~20 ms de plus : on le fait à vide, tout de suite.
        Task.detached(priority: .utility) { _ = EncodeurAudio.flacEnMemoire(Array(repeating: 0, count: 3200)) }
        Retours.preparer()
        if Permissions.microOK { audio.preparer() }
        if !GroqClient.shared.cleDisponible { Log.ecrire("ATTENTION : clé Groq introuvable (~/.config/groq/.env), seul le secours Apple sera possible") }
    }

    func recevoir(_ action: GestureAction) {
        switch action {
        case .begin(let mainsLibres): commencer(mainsLibres: mainsLibres)
        case .end: terminer()
        case .cancel: annuler()
        }
    }

    /// « Dicter une note » dans l'îlot : une dictée lancée d'un clic, sans encoche (l'îlot montre l'écoute) ; fn n'est pas tenue. Faux si
    /// elle n'a pas pu partir (micro non autorisé, micro coupé : l'îlot ou l'encoche le disent).
    func commencerSansEncoche() -> Bool {
        guard etat == .repos else { return false }
        commencer(mainsLibres: true, encoche: false)
        return etat != .repos
    }
    /// « Terminé » (ou le silence) : la note dictée d'un clic s'arrête ; la touche fn repart de zéro.
    func terminerSansEncoche() {
        guard courante?.encoche == false else { return }
        terminer()
        surFinIndependante?()
    }

    // MARK: début

    private func commencer(mainsLibres: Bool, encoche: Bool = true) {
        guard etat == .repos else { return }
        guard Permissions.microOK else {
            Log.ecrire("dictée refusée : micro non autorisé")
            panneau.afficherMessage("Micro non autorisé, voir les Réglages", app: NSWorkspace.shared.frontmostApplication)
            if Settings.premierLancementFait { Task { await Permissions.demanderLePremierManquant() } }
            return
        }
        // coupé veut dire coupé : rien ne rouvre le micro en douce ; la touche fn repart de zéro (mains libres compris)
        guard peutCommencer() else { surFinIndependante?(); return }
        compteur += 1
        let appCible = NSWorkspace.shared.frontmostApplication
        let champ = LectureChamp()
        let recents = HistoriqueStore.shared.historique.entrees.prefix(20).map(\.texte)
        let transcripteur = ChunkTranscriber(mots: Dictionnaire.mots(), langue: Settings.langue,
                                             promptPour: PreparationLexique.promptPour(langue: Settings.langue, genre: TextFormatter.kind(bundleID: appCible?.bundleIdentifier),
                                                                                       champ: { champ.dejaConnu() }, recents: Array(recents)),
                                             correcteur: PreparationLexique.correcteur())
        let s = Session(id: compteur, mainsLibres: mainsLibres, appCible: appCible, transcripteur: transcripteur, champ: champ)
        s.encoche = encoche
        courante = s
        let champLu = s.champ, bundle = s.appCible?.bundleIdentifier
        let unites = NettoyageParUnites(mots: Dictionnaire.mots(), relecture: s.relecture) {
            guard Settings.adapterLeTon else { return .general }
            let c = champLu.dejaConnu()
            return RemiseAuPropre.contexte(bundleID: bundle, role: c?.role, titreFenetre: c?.titreFenetre)
        }
        s.unites = unites
        transcripteur.surMorceauRevenu = { numero, texte, finParPause in unites.morceauRevenu(numero: numero, texte: texte, finParPause: finParPause) }
        transcripteur.surTexteAnticipe = { [weak self] parties in
            // Une dictée déjà découpée en unités : seule la queue est remise au propre à l'avance.
            if unites.nombreDUnites > 0 { unites.anticiperQueue(parties: parties); return }
            let texte = TextAssembler.joindre(parties)
            Task { @MainActor in self?.nettoyerALAvance(texte, session: s) }
        }
        etat = .ecoute(mainsLibres: mainsLibres)
        surDebut?()
        surCapture?(true)
        Log.ecrire("dictée \(s.id) : \(encoche ? "appui fn (\(mainsLibres ? "mains libres" : "tenu"))" : "note dictée d\u{2019}un clic dans l\u{2019}îlot"), app cible = \(s.appCible?.bundleIdentifier ?? "inconnue")")

        if let pid = s.appCible?.processIdentifier, Permissions.accessibiliteOK { s.champ.lireAuDebut(pid: pid) }
        s.pipeline.surMorceau = { transcripteur.envoyer($0) }
        if transcripteur.anticipationActive { s.pipeline.surAnticipation = { transcripteur.anticiper($0) } }
        s.pipeline.surNiveau = { [weak self] n in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.courante?.id == s.id else { return }
                    if s.voix { self.surVoixNiveau?(n) } else if s.encoche { self.panneau.niveau(n) } else { self.surNiveauSansEncoche?(n) }
                }
            }
        }
        if let direct = PrechauffageParole.creer(mots: PrechauffageParole.motsContexte()) {
            direct.surTexte = { [weak self] texte in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self, self.courante?.id == s.id else { return }
                        // fn tenue (pas en mains libres : l'encoche y garde ✕ et ✓) : « Lucarne, rappelle-moi… » passe à l'îlot, qui suit
                        // ensuite le texte (le genre, « Rappel… » ou « Note… », peut arriver plus tard)
                        let pourLIlot = s.encoche && !s.mainsLibres && self.surVoixEnDirect?(s.id, texte) == true
                        if pourLIlot, !s.voix { s.voix = true; self.panneau.fermer() }
                        if !s.voix { if s.encoche { self.panneau.mettreAJourTexte(texte) } else { self.surTexteSansEncoche?(texte) } }
                    }
                }
            }
            s.pipeline.surTamponBrut = { [weak direct] tampon in direct?.alimenter(tampon) }
            s.direct = direct
        }
        // L'encoche s'ouvre tout de suite en mains libres ; en mode « tenir », après 0,12 s, pour qu'un appui court
        // (annulé) ne fasse pas clignoter l'encoche.
        ouvertureRetardee?.cancel()
        if !encoche {
            // la note d'un clic : l'îlot montre l'écoute, l'encoche de dictée ne s'ouvre pas ; le son de départ dit que ça écoute
            jouerDebut(s)
        } else if mainsLibres {
            panneau.ouvrir(app: s.appCible, mainsLibres: true)
            jouerDebut(s)
        } else {
            let item = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated { if self?.courante?.id == s.id { if !s.voix { self?.panneau.ouvrir(app: s.appCible, mainsLibres: false) }; self?.jouerDebut(s) } }
            }
            ouvertureRetardee = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: item)
        }
        GroqClient.shared.prechauffer()
        let idSession = s.id
        audio.demarrer(pipeline: s.pipeline) { resultat in
            switch resultat {
            case .success(let ms): Log.ecrire("dictée \(idSession) : micro prêt, premier son \(ms) ms après l'appui")
            case .failure(let e):
                Log.ecrire("dictée \(idSession) : micro impossible (\(e.localizedDescription))")
                DispatchQueue.main.async { [weak self] in
                    MainActor.assumeIsolated {
                        if self?.courante?.id == idSession {
                            let app = self?.courante?.appCible
                            self?.annuler(); self?.surFinIndependante?()
                            self?.panneau.afficherMessage("Micro indisponible", app: app)
                        }
                    }
                }
            }
        }
    }

    /// Son + vibration de début. Lancés sans attendre : la lecture et le retour haptique ne bloquent rien.
    private func jouerDebut(_ s: Session) {
        s.retourDebutJoue = true
        Retours.debut()
    }

    // MARK: fin

    private func terminer() {
        guard case .ecoute = etat, let s = courante else { return }
        let t = ProcessInfo.processInfo.systemUptime
        s.relachement = t
        etat = .repos
        courante = nil
        // Le dernier morceau part avant tout le reste (arrêt du micro, interface, journal) : c'est lui qui fait attendre.
        // Si la pause d'avant le relâchement l'avait déjà envoyé, la requête en cours est simplement reprise.
        let dernier = s.pipeline.terminer()
        if let dernier { s.transcripteur.envoyer(dernier) }
        let envoye = ProcessInfo.processInfo.systemUptime
        surCapture?(false)
        Log.ecrire("dictée \(s.id) : relâchement après \(ms(t - s.debut)) ms, dernier morceau \(dernier.map { String(format: "%.1f s", $0.duree) } ?? "aucun") \(dernier == nil ? "à envoyer" : "parti") en \(ms(envoye - t)) ms")
        if let pid = s.appCible?.processIdentifier, Permissions.accessibiliteOK { s.champ.lireALaFin(pid: pid) }
        ouvertureRetardee?.cancel()
        // Finalisation : le texte du ruban se fixe en blanc (l'encoche reste ouverte jusqu'au texte final).
        if panneau.modele.ouverte { panneau.figer() }

        audio.arreter {
            // Sur la file audio : plus aucun tampon n'arrive. La reconnaissance d'Apple finit en parallèle :
            // son texte ne sert que si Groq échoue.
            if let direct = s.direct { s.secours = Task { await direct.terminer() } }
        }
        Task { @MainActor [weak self] in
            await self?.finaliser(s)
            if s.voix { self?.surVoixFin?(s.id) }
        }
    }

    private func finaliser(_ s: Session) async {
        let relache = s.relachement ?? ProcessInfo.processInfo.systemUptime
        if s.transcripteur.nombreDeMorceaux == 0 {
            Log.ecrire("dictée \(s.id) : rien entendu, rien à écrire")
            s.direct?.annuler()
            fermerSiLibre()
            if !s.encoche { surRienEcrit?() }
            return
        }
        let restant = max(0.2, Settings.delaiGroq - (ProcessInfo.processInfo.systemUptime - relache))
        let resultat = await s.transcripteur.resultat(delai: restant)
        let attente = ms(ProcessInfo.processInfo.systemUptime - relache)
        switch resultat {
        case .texte(let texte) where !texte.isEmpty:
            Log.ecrire("dictée \(s.id) : réponse Groq complète \(attente) ms après le relâchement (\(Settings.modeleWhisper.identifiant)), \"\(Log.apercu(texte))\"")
            if s.transcripteur.nombreDeMorceaux <= 2 { var l = Settings.latences; l.noter(attente, modele: Settings.modeleWhisper); Settings.latences = l }
            surGroqReussi?()
            await ecrire(texte, session: s, relachement: relache)
        case .texte:
            Log.ecrire("dictée \(s.id) : Groq n'a rien reconnu (\(attente) ms)")
            fermerSiLibre()
            if !s.encoche { surRienEcrit?() }
        case .echec(let raison, let echec):
            Log.ecrire("dictée \(s.id) : Groq en échec après \(attente) ms (\(raison)) -> relais sur le Mac")
            await utiliserLeSecours(s, relachement: relache, echec: echec ?? .autre)
        case .delai:
            Log.ecrire("dictée \(s.id) : Groq trop lent (> \(Settings.delaiGroq) s) -> relais sur le Mac")
            await utiliserLeSecours(s, relachement: relache, echec: .delai)
        }
    }

    /// Texte de la reconnaissance du Mac (macOS 26, faite sur l'appareil) quand Groq ne répond pas (limite, réseau, panne, clé absente).
    /// Le même chemin que le texte de Groq ensuite : correction à l'oreille (lexique), remise au propre si Groq la permet encore, adresses,
    /// raccourcis, mise en forme selon l'app. La dictée suivante retente Groq (rien n'est retenu ici, sinon le signe dans l'îlot).
    private func utiliserLeSecours(_ s: Session, relachement relache: Double, echec: EchecGroq) async {
        guard Settings.secoursApple else {
            Log.ecrire("dictée \(s.id) : secours Apple désactivé dans les Réglages, rien à écrire")
            s.direct?.annuler()
            if !s.encoche { surRienEcrit?() }
            if courante == nil { panneau.afficherMessage("Impossible de dicter, réessaie", app: s.appCible) }
            return
        }
        var texte = ""
        if s.secours == nil, let direct = s.direct { s.secours = Task { await direct.terminer() } }
        if let secours = s.secours {
            texte = await withTaskGroup(of: String.self) { groupe in
                groupe.addTask { await secours.value }
                groupe.addTask { try? await Task.sleep(for: .seconds(1.5)); return "" }
                let premier = await groupe.next() ?? ""
                groupe.cancelAll()
                return premier
            }
        }
        texte = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        guard RelaisDictee.utiliserLeMac(echec: echec, relaisPermis: true, texteDuMac: texte) else {
            Log.ecrire("dictée \(s.id) : pas de texte du Mac, rien à écrire (\(PrechauffageParole.disponibilite))")
            if !s.encoche { surRienEcrit?() }
            if case .telechargement(let p) = PrechauffageParole.disponibilite {
                surRelaisIndisponible?("Le Mac télécharge le français \u{00B7} \(p) %")
            } else if courante == nil { panneau.afficherMessage("Impossible de dicter, réessaie", app: s.appCible) }
            return
        }
        // les mots du lexique mal entendus, comme pour un morceau de Groq
        texte = await PreparationLexique.correcteur()(texte, 0)
        Log.ecrire("dictée \(s.id) : texte du Mac utilisé (\(echec.rawValue)), \"\(Log.apercu(texte))\"")
        await ecrire(texte, session: s, relachement: relache)
        surRelais?(echec)
    }

    /// La pause d'avant le relâchement a fait partir le dernier morceau et Groq a déjà répondu : on remet au propre sans attendre.
    /// Si la parole reprend, ce travail est jeté ; sinon sa réponse est prête (ou presque) au relâchement.
    private func nettoyerALAvance(_ brut: String, session s: Session) {
        guard etat != .repos, courante?.id == s.id else { return }
        if let a = s.nettoyageAnticipe, a.brut == brut { return }
        let champ = s.champ.dejaConnu()
        let contexte = Settings.adapterLeTon ? RemiseAuPropre.contexte(bundleID: s.appCible?.bundleIdentifier, role: champ?.role, titreFenetre: champ?.titreFenetre) : .general
        guard let a = NettoyageFinal.lancerALAvance(brut, contexte: contexte, mots: Dictionnaire.mots(), relecture: s.relecture) else { return }
        s.nettoyageAnticipe?.tache.cancel()
        s.nettoyageAnticipe = a
        Log.ecrire("dictée \(s.id) : remise au propre lancée à l'avance (pause en cours)")
    }

    /// Referme l'encoche, sauf si une nouvelle dictée l'a déjà reprise.
    private func fermerSiLibre() {
        if courante == nil { panneau.fermer() }
    }

    /// Mise en forme selon l'app cible, puis collage au curseur.
    private func ecrire(_ brut: String, session s: Session, relachement relache: Double) async {
        // « Lucarne, … » sur le texte de Groq : une commande ne passe jamais par la remise au propre (ni l'IA, ni le lexique)
        if AnalyseCommandeIlot.sansAppel(brut) != nil, surCommandeLucarne?(brut) == true {
            s.unites?.annulerTout(); s.nettoyageAnticipe?.tache.cancel()
            Log.ecrire("dictée \(s.id) : commande pour Lucarne (lue sur le texte de Groq), rien n\u{2019}est collé")
            fermerSiLibre()
            Retours.fin()
            return
        }
        // pas une commande (« Lucarne est prête… ») : l'onde s'en va avant la remise au propre et le collage
        if s.voix { surVoixFin?(s.id) }
        let kind = TextFormatter.kind(bundleID: s.appCible?.bundleIdentifier)
        let (champ, sourceChamp) = await s.champ.contexte()
        let contexte = Settings.adapterLeTon ? RemiseAuPropre.contexte(bundleID: s.appCible?.bundleIdentifier, role: champ?.role, titreFenetre: champ?.titreFenetre) : .general
        let tNettoyage = ProcessInfo.processInfo.systemUptime
        let (nettoyage, modeNettoyage) = await NettoyageFinal.executer(brut: brut, contexte: contexte, transcripteur: s.transcripteur, unites: s.unites,
                                                                      anticipe: s.nettoyageAnticipe, mots: Dictionnaire.mots(), relecture: s.relecture)
        let attenteNettoyage = ms(ProcessInfo.processInfo.systemUptime - tNettoyage)
        Log.ecrire("dictée \(s.id) : mise en forme \(contexte.rawValue) (champ \(champ?.role ?? "?"), lu au \(sourceChamp)), \(nettoyage.utilise ? "remis au propre" : "texte brut gardé : \(nettoyage.raison)") \(modeNettoyage), \(attenteNettoyage) ms d'attente après Groq (travail de \(ms(nettoyage.duree)) ms)\(nettoyage.relecture.map { ", relecture de sens : \($0)" } ?? "")")
        // raccourcis vocaux (« ma signature » → le texte choisi) : après la remise au propre, pour que l'IA n'y touche pas
        // Adresses dictées (« x arobase y point com ») reconstituées d'abord par la règle locale, y compris quand la remise au propre n'a pas eu lieu.
        let apresAdresses = AdressesDictees.reconstituer(nettoyage.texte)
        let apresRaccourcis = RaccourcisVocaux.appliquer(apresAdresses, raccourcis: MotsModele.partage.raccourcis)
        let texteFinal = TextFormatter.prepare(apresRaccourcis, for: kind)
        if let comparaison = ComparaisonJournal.ligne(groq: brut, final: texteFinal) { Log.ecrire("dictée \(s.id) : \(comparaison)") }
        // la note d'un clic : son texte va à la carte, même arrivé tard ; JAMAIS collé dans l'app au premier plan (même vide ou refusé)
        if !s.encoche {
            if surNoteParClic?(texteFinal) == true { Retours.fin(); return }
            Log.ecrire("dictée \(s.id) : note d\u{2019}un clic non retenue, rien n\u{2019}est collé")
            surRienEcrit?()
            return
        }
        // Commande de l'îlot (« minuteur 10 minutes ») : seulement si l'accueil de l'îlot était ouvert au début de la dictée ; sinon jamais
        // touchée. « Lucarne, … » y est cherché encore, en secours, sur le texte final.
        if surInterception?(texteFinal) == true {
            Log.ecrire("dictée \(s.id) : commande de l\u{2019}îlot, rien n\u{2019}est collé")
            fermerSiLibre()
            Retours.fin()
            return
        }
        let texte = raccorder(texteFinal, kind: kind, session: s, champ: champ)
        TestPrecisionStore.enregistrerSiActif(echantillons: s.pipeline.echantillonsComplets(), appId: s.appCible?.bundleIdentifier, appNom: s.appCible?.localizedName,
                                              texteGroq: brut, texteFinal: texteFinal, duree: s.pipeline.dureeEnregistree, idDictee: s.id)
        // L'encoche de dictée se referme ; en cas d'échec le filet de sécurité la remplace par une encoche avec le texte à copier.
        fermerSiLibre()
        let creation = Date()
        let t = ProcessInfo.processInfo.systemUptime
        let issue = await collage.ecrire(texte, dans: s.appCible)
        let collageMs = ms(ProcessInfo.processInfo.systemUptime - t)
        let total = ms(ProcessInfo.processInfo.systemUptime - relache)
        let parole = s.pipeline.dureeParole
        func garder(inseree: Bool, raison: String? = nil) {
            HistoriqueStore.shared.ajouter(EntreeHistorique(date: creation, appId: s.appCible?.bundleIdentifier, appNom: s.appCible?.localizedName,
                                                            texte: texteFinal, insere: inseree, raison: raison, dureeParole: parole))
        }
        switch issue {
        case .colle:
            Retours.fin()
            Log.ecrire("dictée \(s.id) : collé dans \(s.appCible?.bundleIdentifier ?? "?") (\(kind)), collage \(collageMs) ms, \(total) ms après le relâchement")
            let verdict = await verifierInsertion(texte, cible: s.appCible, kind: kind, idDictee: s.id)
            if case .nonInseree(let raison) = verdict {
                garder(inseree: false, raison: raison)
                surEchecInsertion?("Le texte n\u{2019}est pas arrivé dans le champ, il est gardé dans l\u{2019}historique.")
                signalerEchec(texteFinal, cible: s.appCible, raison: raison, ancienMessage: "Texte non écrit, voir l\u{2019}historique", idDictee: s.id)
            } else {
                garder(inseree: true)
                VocabulaireRelectureStore.partage.rafraichir()
                MotsModele.partage.apprendreDeLHistorique()
                surInsertion?(texteFinal, s.appCible?.bundleIdentifier)
                SurveillanceCorrections.lancer(texte: texte, cible: s.appCible, genre: kind, idDictee: s.id)
                memoire = MemoireInsertion(appId: s.appCible?.bundleIdentifier ?? "", queue: MemoireInsertion.queue(de: texte),
                                           instant: ProcessInfo.processInfo.systemUptime, frappes: compteurFrappes())
            }
        case .champProtege:
            Log.ecrire("dictée \(s.id) : champ protégé, texte copié sans collage")
            garder(inseree: false, raison: "champ protégé")
            surEchecInsertion?("Écriture impossible ici, le texte est copié.")
            signalerEchec(texteFinal, cible: s.appCible, raison: "champ protégé", ancienMessage: "Écriture impossible ici, texte copié", idDictee: s.id)
        case .copieSeulement(let raison):
            Log.ecrire("dictée \(s.id) : texte copié mais pas collé (\(raison))")
            garder(inseree: false, raison: raison)
            surEchecInsertion?("Le collage n\u{2019}est pas autorisé, le texte est copié.")
            signalerEchec(texteFinal, cible: s.appCible, raison: raison, ancienMessage: "Texte copié, collage non autorisé", idDictee: s.id)
        case .cibleIndisponible(let raison):
            Log.ecrire("dictée \(s.id) : rien collé (\(raison))")
            garder(inseree: false, raison: raison)
            surEchecInsertion?("Le texte n\u{2019}a pas pu être écrit, il est gardé dans l\u{2019}historique.")
            signalerEchec(texteFinal, cible: s.appCible, raison: raison, ancienMessage: "Destination indisponible, voir l\u{2019}historique", idDictee: s.id)
        case .vide:
            Log.ecrire("dictée \(s.id) : texte vide après mise en forme")
        }
    }

    /// Après le ⌘V : relit le champ par l'Accessibilité (à 250, 400 puis 650 ms) pour s'assurer que le texte est arrivé.
    /// Ne conclut à un échec que sur une preuve ; si l'app ne laisse rien lire, le verdict est « indéterminé ».
    private func verifierInsertion(_ texte: String, cible: NSRunningApplication?, kind: AppKind, idDictee: Int) async -> VerdictInsertion {
        guard Settings.filetDeSecurite, Permissions.accessibiliteOK, let cible, !cible.isTerminated,
              cible.bundleIdentifier != Bundle.main.bundleIdentifier else { return .indetermine }
        let (verdict, lectures) = await LecteurInsertion.verifier(texte: texte, pid: cible.processIdentifier, genre: kind)
        let resume: String
        switch verdict {
        case .inseree: resume = "texte retrouvé devant le curseur"
        case .nonInseree(let raison): resume = "ÉCHEC : \(raison)"
        case .indetermine: resume = "indéterminé (l\u{2019}app ne laisse pas relire), pas d\u{2019}alarme"
        }
        Log.ecrire("dictée \(idDictee) : vérification de l\u{2019}écriture, \(lectures) lecture(s) : \(resume)")
        return verdict
    }

    /// Le texte n'est pas arrivé : le filet de sécurité (encoche ouverte avec le texte) ; sans lui, l'ancien message bref.
    private func signalerEchec(_ texte: String, cible: NSRunningApplication?, raison: String, ancienMessage: String, idDictee: Int) {
        if Settings.filetDeSecurite {
            guard courante == nil else {
                Log.ecrire("dictée \(idDictee) : filet de sécurité non affiché (une nouvelle dictée est en cours), texte dans l\u{2019}historique")
                return
            }
            surFilet?(texte, cible)
        } else if courante == nil {
            panneau.afficherMessage(ancienMessage, app: cible)
        }
    }

    /// Recolle un texte de l'historique dans l'app qui avait le curseur avant l'ouverture du panneau (jamais dans la
    /// recherche du panneau). Mise en forme selon l'app (terminal : une ligne, aucun Entrée). Si la destination n'existe
    /// plus, ou si l'écriture est impossible, le texte reste dans le presse-papiers et l'encoche le dit.
    func recoller(_ texte: String, dans cible: NSRunningApplication?) async {
        guard etat == .repos else { return }
        guard let cible, !cible.isTerminated else {
            copierSeulement(texte)
            Log.ecrire("recoller : destination indisponible, texte copié")
            panneau.afficherMessage("Destination indisponible, texte copié", app: nil)
            return
        }
        let kind = TextFormatter.kind(bundleID: cible.bundleIdentifier)
        let pret = TextFormatter.prepare(texte, for: kind)
        // laisse au clavier le temps de revenir dans la fenêtre de l'app après la fermeture du panneau
        try? await Task.sleep(for: .milliseconds(70))
        switch await collage.ecrire(pret, dans: cible) {
        case .colle:
            Log.ecrire("recoller : collé dans \(cible.bundleIdentifier ?? "?") (\(kind))")
            if case .nonInseree(let raison) = await verifierInsertion(pret, cible: cible, kind: kind, idDictee: 0) {
                signalerEchec(texte, cible: cible, raison: raison, ancienMessage: "Texte non écrit, voir l\u{2019}historique", idDictee: 0)
            }
        case .champProtege:
            Log.ecrire("recoller : champ protégé, texte copié")
            signalerEchec(texte, cible: cible, raison: "champ protégé", ancienMessage: "Écriture impossible ici, texte copié", idDictee: 0)
        case .copieSeulement(let raison):
            Log.ecrire("recoller : texte copié mais pas collé (\(raison))")
            signalerEchec(texte, cible: cible, raison: raison, ancienMessage: "Texte copié, collage non autorisé", idDictee: 0)
        case .cibleIndisponible(let raison):
            Log.ecrire("recoller : rien collé (\(raison))")
            signalerEchec(texte, cible: cible, raison: raison, ancienMessage: "Destination indisponible, texte copié", idDictee: 0)
        case .vide: break
        }
    }

    private func copierSeulement(_ texte: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(texte, forType: .string)
    }

    /// Espace devant et minuscule en milieu de phrase, d'après ce qui précède le curseur.
    /// Source : l'Accessibilité si l'app l'expose ; sinon (ou d'abord, pour un terminal, dont la zone de texte ne
    /// donne pas la position du curseur de façon sûre) la dernière insertion si rien n'a été tapé depuis.
    private func raccorder(_ texte: String, kind: AppKind, session s: Session, champ: ContexteChamp?) -> String {
        let appId = s.appCible?.bundleIdentifier
        let repli = memoire?.precedent(appId: appId, instant: ProcessInfo.processInfo.systemUptime, frappes: compteurFrappes())
        let precedent: String?, source: String
        if kind == .terminal, let repli { (precedent, source) = (repli, "dernière insertion") }
        else if let p = champ?.precedent { (precedent, source) = (p, champ?.methode ?? "AX") }
        else if let repli { (precedent, source) = (repli, "dernière insertion") }
        else { (precedent, source) = (nil, "inconnu") }
        let adapte = EspacesIntelligents.adapter(texte, precedent: precedent, mots: Dictionnaire.mots())
        Log.ecrire("dictée \(s.id) : avant le curseur = \(Self.classe(precedent)) (\(source)), espace \(adapte.hasPrefix(" ") ? "ajoutée" : "non"), minuscule \(adapte.trimmingCharacters(in: .whitespaces).first != texte.first ? "oui" : "non")")
        return adapte
    }

    /// Nature du dernier caractère avant le curseur (le journal ne garde jamais le texte lui-même).
    private static func classe(_ precedent: String?) -> String {
        guard let precedent else { return "inconnu" }
        guard let c = precedent.last else { return "début de champ" }
        if c.isNewline { return "saut de ligne" }
        if c.isWhitespace { return "espace" }
        if c.isLetter { return "lettre" }
        if c.isNumber { return "chiffre" }
        return "signe"
    }

    // MARK: annulation

    private func annuler() {
        guard case .ecoute = etat, let s = courante else { return }
        Log.ecrire("dictée \(s.id) : annulée après \(ms(ProcessInfo.processInfo.systemUptime - s.debut)) ms, rien n'est écrit")
        etat = .repos
        courante = nil
        surCapture?(false)
        if s.retourDebutJoue { Retours.annulation() }
        s.transcripteur.annuler()
        s.nettoyageAnticipe?.tache.cancel()
        s.unites?.annulerTout()
        s.direct?.annuler()
        ouvertureRetardee?.cancel()
        panneau.fermer()
        audio.arreter { }
        if !s.encoche { surRienEcrit?() }
        if s.voix { surVoixFin?(s.id) }
    }

    private func annulerParBouton() {
        Log.ecrire("bouton ✕ pressé")
        annuler()
        surFinIndependante?()
    }

    private func validerParBouton() {
        Log.ecrire("bouton ✓ pressé")
        terminer()
        surFinIndependante?()
    }

    private func ms(_ secondes: Double) -> Int { Int((secondes * 1000).rounded()) }
}
