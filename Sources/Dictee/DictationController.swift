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
        let appCible: NSRunningApplication?
        let debut = ProcessInfo.processInfo.systemUptime
        var relachement: Double?
        let pipeline: RecordingPipeline
        /// Le son et la vibration de début ont été joués (sinon une annulation silencieuse : appui trop court).
        var retourDebutJoue = false
        var direct: (any ReconnaissanceDirecte)?
        var secours: Task<String, Never>?
        /// Lecture du champ focalisé (Accessibilité), lancée à l'appui puis au relâchement, pendant que Groq travaille.
        let champ = LectureChamp()
        let transcripteur: ChunkTranscriber
        /// Remise au propre lancée pendant la pause d'avant le relâchement, sur le texte qu'on aurait si la parole s'arrêtait là.
        /// Remise au propre par unités de phrases pendant les longues dictées.
        var unites: NettoyageParUnites?
        var nettoyageAnticipe: (brut: String, contexte: ContexteMiseEnForme, tache: Task<Nettoyage.Resultat, Never>)?
        init(id: Int, mainsLibres: Bool, appCible: NSRunningApplication?, transcripteur: ChunkTranscriber) {
            self.id = id; self.mainsLibres = mainsLibres; self.appCible = appCible; self.transcripteur = transcripteur
            // Le son de début est capté par le micro : la détection de parole ignore ses premières tranches (0,2 s en mains libres, 0,32 s en mode « tenir » où il part à 0,12 s).
            pipeline = RecordingPipeline(tranchesIgnorees: Settings.sons ? (mainsLibres ? 10 : 16) : 0)
        }
    }

    private(set) var etat: Etat = .repos
    private var courante: Session?
    private var compteur = 0
    private let audio = AudioCapture()

    let collage = Collage()
    let panneau = EnclochePanneau()
    private var ouvertureRetardee: DispatchWorkItem?

    /// Appelé quand une dictée finit sans passer par la touche fn (boutons ✕ / ✓, micro impossible) :
    /// la machine de la touche fn doit alors être remise à zéro.
    var surFinIndependante: (() -> Void)?
    /// Appelé au début d'une dictée : le panneau compact se ferme (les deux ne se superposent jamais).
    var surDebut: (() -> Void)?
    var enCours: Bool { etat != .repos }
    /// Appelé quand un texte vient d'être collé : (texte, identifiant de l'app cible). Sert à la première dictée réussie.
    var surInsertion: ((String, String?) -> Void)?
    /// Appelé quand le texte n'a pas pu être écrit (champ protégé, accessibilité manquante).
    var surEchecInsertion: ((String) -> Void)?
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

    // MARK: début

    private func commencer(mainsLibres: Bool) {
        guard etat == .repos else { return }
        guard Permissions.microOK else {
            Log.ecrire("dictée refusée : micro non autorisé")
            panneau.afficherMessage("Micro non autorisé, voir les Réglages", app: NSWorkspace.shared.frontmostApplication)
            if Settings.premierLancementFait { Task { await Permissions.demanderLePremierManquant() } }
            return
        }
        compteur += 1
        let transcripteur = ChunkTranscriber(mots: Dictionnaire.mots(), langue: Settings.langue)
        let s = Session(id: compteur, mainsLibres: mainsLibres, appCible: NSWorkspace.shared.frontmostApplication, transcripteur: transcripteur)
        courante = s
        let champLu = s.champ, bundle = s.appCible?.bundleIdentifier
        let unites = NettoyageParUnites(mots: Dictionnaire.mots()) {
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
        Log.ecrire("dictée \(s.id) : appui fn (\(mainsLibres ? "mains libres" : "tenu")), app cible = \(s.appCible?.bundleIdentifier ?? "inconnue")")

        if let pid = s.appCible?.processIdentifier, Permissions.accessibiliteOK { s.champ.lireAuDebut(pid: pid) }
        s.pipeline.surMorceau = { transcripteur.envoyer($0) }
        if transcripteur.anticipationActive { s.pipeline.surAnticipation = { transcripteur.anticiper($0) } }
        s.pipeline.surNiveau = { [weak self] n in
            DispatchQueue.main.async { MainActor.assumeIsolated { if self?.courante?.id == s.id { self?.panneau.niveau(n) } } }
        }
        if let direct = PrechauffageParole.creer() {
            direct.surTexte = { [weak self] texte in
                DispatchQueue.main.async { MainActor.assumeIsolated { if self?.courante?.id == s.id { self?.panneau.mettreAJourTexte(texte) } } }
            }
            s.pipeline.surTamponBrut = { [weak direct] tampon in direct?.alimenter(tampon) }
            s.direct = direct
        }
        // L'encoche s'ouvre tout de suite en mains libres ; en mode « tenir », après 0,12 s, pour qu'un appui court
        // (annulé) ne fasse pas clignoter l'encoche.
        ouvertureRetardee?.cancel()
        if mainsLibres {
            panneau.ouvrir(app: s.appCible, mainsLibres: true)
            jouerDebut(s)
        } else {
            let item = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated { if self?.courante?.id == s.id { self?.panneau.ouvrir(app: s.appCible, mainsLibres: false); self?.jouerDebut(s) } }
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
        Task { @MainActor [weak self] in await self?.finaliser(s) }
    }

    private func finaliser(_ s: Session) async {
        let relache = s.relachement ?? ProcessInfo.processInfo.systemUptime
        if s.transcripteur.nombreDeMorceaux == 0 {
            Log.ecrire("dictée \(s.id) : rien entendu, rien à écrire")
            s.direct?.annuler()
            fermerSiLibre()
            return
        }
        let restant = max(0.2, Settings.delaiGroq - (ProcessInfo.processInfo.systemUptime - relache))
        let resultat = await s.transcripteur.resultat(delai: restant)
        let attente = ms(ProcessInfo.processInfo.systemUptime - relache)
        switch resultat {
        case .texte(let texte) where !texte.isEmpty:
            Log.ecrire("dictée \(s.id) : réponse Groq complète \(attente) ms après le relâchement, \"\(Log.apercu(texte))\"")
            await ecrire(texte, session: s, relachement: relache)
        case .texte:
            Log.ecrire("dictée \(s.id) : Groq n'a rien reconnu (\(attente) ms)")
            fermerSiLibre()
        case .echec(let raison):
            Log.ecrire("dictée \(s.id) : Groq en échec après \(attente) ms (\(raison)) -> secours Apple")
            await utiliserLeSecours(s, relachement: relache)
        case .delai:
            Log.ecrire("dictée \(s.id) : Groq trop lent (> \(Settings.delaiGroq) s) -> secours Apple")
            await utiliserLeSecours(s, relachement: relache)
        }
    }

    /// Texte de la dictée d'Apple (faite sur l'appareil) quand Groq ne répond pas.
    private func utiliserLeSecours(_ s: Session, relachement relache: Double) async {
        guard Settings.secoursApple else {
            Log.ecrire("dictée \(s.id) : secours Apple désactivé dans les Réglages, rien à écrire")
            s.direct?.annuler()
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
        guard !texte.isEmpty else {
            Log.ecrire("dictée \(s.id) : pas de texte de secours, rien à écrire")
            if courante == nil { panneau.afficherMessage("Impossible de dicter, réessaie", app: s.appCible) }
            return
        }
        Log.ecrire("dictée \(s.id) : texte de secours Apple utilisé, \"\(Log.apercu(texte))\"")
        await ecrire(texte, session: s, relachement: relache)
    }

    /// La pause d'avant le relâchement a fait partir le dernier morceau et Groq a déjà répondu : on remet au propre sans attendre.
    /// Si la parole reprend, ce travail est jeté ; sinon sa réponse est prête (ou presque) au relâchement.
    private func nettoyerALAvance(_ brut: String, session s: Session) {
        guard etat != .repos, courante?.id == s.id else { return }
        if let a = s.nettoyageAnticipe, a.brut == brut { return }
        let champ = s.champ.dejaConnu()
        let contexte = Settings.adapterLeTon ? RemiseAuPropre.contexte(bundleID: s.appCible?.bundleIdentifier, role: champ?.role, titreFenetre: champ?.titreFenetre) : .general
        guard let a = NettoyageFinal.lancerALAvance(brut, contexte: contexte, mots: Dictionnaire.mots()) else { return }
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
        let kind = TextFormatter.kind(bundleID: s.appCible?.bundleIdentifier)
        let (champ, sourceChamp) = await s.champ.contexte()
        let contexte = Settings.adapterLeTon ? RemiseAuPropre.contexte(bundleID: s.appCible?.bundleIdentifier, role: champ?.role, titreFenetre: champ?.titreFenetre) : .general
        let tNettoyage = ProcessInfo.processInfo.systemUptime
        let (nettoyage, modeNettoyage) = await NettoyageFinal.executer(brut: brut, contexte: contexte, transcripteur: s.transcripteur, unites: s.unites,
                                                                      anticipe: s.nettoyageAnticipe, mots: Dictionnaire.mots())
        let attenteNettoyage = ms(ProcessInfo.processInfo.systemUptime - tNettoyage)
        Log.ecrire("dictée \(s.id) : mise en forme \(contexte.rawValue) (champ \(champ?.role ?? "?"), lu au \(sourceChamp)), \(nettoyage.utilise ? "remis au propre" : "texte brut gardé : \(nettoyage.raison)") \(modeNettoyage), \(attenteNettoyage) ms d'attente après Groq (travail de \(ms(nettoyage.duree)) ms)")
        // raccourcis vocaux (« ma signature » → le texte choisi) : après la remise au propre, pour que l'IA n'y touche pas
        // Adresses dictées (« x arobase y point com ») reconstituées d'abord par la règle locale, y compris quand la remise au propre n'a pas eu lieu.
        let apresAdresses = AdressesDictees.reconstituer(nettoyage.texte)
        let apresRaccourcis = RaccourcisVocaux.appliquer(apresAdresses, raccourcis: MotsModele.partage.raccourcis)
        let texteFinal = TextFormatter.prepare(apresRaccourcis, for: kind)
        let texte = raccorder(texteFinal, kind: kind, session: s, champ: champ)
        // Champ protégé : l'encoche reste pour le dire ; sinon elle se referme et le texte arrive au curseur.
        if !IsSecureEventInputEnabled() { fermerSiLibre() }
        let t = ProcessInfo.processInfo.systemUptime
        let issue = await collage.ecrire(texte, dans: s.appCible)
        let collageMs = ms(ProcessInfo.processInfo.systemUptime - t)
        let total = ms(ProcessInfo.processInfo.systemUptime - relache)
        func garder(inseree: Bool, raison: String? = nil) {
            HistoriqueStore.shared.ajouter(EntreeHistorique(appId: s.appCible?.bundleIdentifier, appNom: s.appCible?.localizedName,
                                                            texte: texteFinal, insere: inseree, raison: raison))
        }
        switch issue {
        case .colle:
            garder(inseree: true)
            Retours.fin()
            surInsertion?(texteFinal, s.appCible?.bundleIdentifier)
            memoire = MemoireInsertion(appId: s.appCible?.bundleIdentifier ?? "", queue: MemoireInsertion.queue(de: texte),
                                       instant: ProcessInfo.processInfo.systemUptime, frappes: compteurFrappes())
            Log.ecrire("dictée \(s.id) : collé dans \(s.appCible?.bundleIdentifier ?? "?") (\(kind)), collage \(collageMs) ms, \(total) ms après le relâchement")
        case .champProtege:
            Log.ecrire("dictée \(s.id) : champ protégé, texte copié sans collage")
            garder(inseree: false, raison: "champ protégé")
            surEchecInsertion?("Écriture impossible ici, le texte est copié.")
            if courante == nil { panneau.afficherMessage("Écriture impossible ici, texte copié", app: s.appCible) }
        case .copieSeulement(let raison):
            Log.ecrire("dictée \(s.id) : texte copié mais pas collé (\(raison))")
            garder(inseree: false, raison: raison)
            surEchecInsertion?("Le collage n\u{2019}est pas autorisé, le texte est copié.")
            fermerSiLibre()
            if courante == nil { panneau.afficherMessage("Texte copié, collage non autorisé", app: s.appCible) }
        case .vide:
            Log.ecrire("dictée \(s.id) : texte vide après mise en forme")
            fermerSiLibre()
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
        case .colle: Log.ecrire("recoller : collé dans \(cible.bundleIdentifier ?? "?") (\(kind))")
        case .champProtege:
            Log.ecrire("recoller : champ protégé, texte copié")
            panneau.afficherMessage("Écriture impossible ici, texte copié", app: cible)
        case .copieSeulement(let raison):
            Log.ecrire("recoller : texte copié mais pas collé (\(raison))")
            panneau.afficherMessage("Texte copié, collage non autorisé", app: cible)
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
