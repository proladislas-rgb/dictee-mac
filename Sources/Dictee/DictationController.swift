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
        let pipeline = RecordingPipeline()
        var direct: (any ReconnaissanceDirecte)?
        var secours: Task<String, Never>?
        /// Lecture du champ focalisé (Accessibilité), lancée au relâchement pendant que Groq travaille.
        var champ: Task<ContexteChamp, Never>?
        let transcripteur: ChunkTranscriber
        init(id: Int, mainsLibres: Bool, appCible: NSRunningApplication?, transcripteur: ChunkTranscriber) {
            self.id = id; self.mainsLibres = mainsLibres; self.appCible = appCible; self.transcripteur = transcripteur
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
            Task { await Permissions.demanderLePremierManquant() }
            return
        }
        compteur += 1
        let transcripteur = ChunkTranscriber(mots: Dictionnaire.mots(), langue: Settings.langue)
        let s = Session(id: compteur, mainsLibres: mainsLibres, appCible: NSWorkspace.shared.frontmostApplication, transcripteur: transcripteur)
        courante = s
        etat = .ecoute(mainsLibres: mainsLibres)
        surDebut?()
        surCapture?(true)
        Log.ecrire("dictée \(s.id) : appui fn (\(mainsLibres ? "mains libres" : "tenu")), app cible = \(s.appCible?.bundleIdentifier ?? "inconnue")")

        s.pipeline.surMorceau = { wav, duree in transcripteur.envoyer(wav: wav, duree: duree) }
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
        } else {
            let item = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated { if self?.courante?.id == s.id { self?.panneau.ouvrir(app: s.appCible, mainsLibres: false) } }
            }
            ouvertureRetardee = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: item)
        }
        GroqClient.shared.prechauffer()
        let idSession = s.id
        audio.demarrer(pipeline: s.pipeline) { resultat in
            switch resultat {
            case .success(let ms): Log.ecrire("dictée \(idSession) : micro prêt après \(ms) ms")
            case .failure(let e):
                Log.ecrire("dictée \(idSession) : micro impossible (\(e.localizedDescription))")
                DispatchQueue.main.async { [weak self] in
                    MainActor.assumeIsolated {
                        if self?.courante?.id == idSession { self?.annuler(); self?.surFinIndependante?() }
                    }
                }
            }
        }
    }

    // MARK: fin

    private func terminer() {
        guard case .ecoute = etat, let s = courante else { return }
        let t = ProcessInfo.processInfo.systemUptime
        s.relachement = t
        etat = .repos
        courante = nil
        surCapture?(false)
        Log.ecrire("dictée \(s.id) : relâchement après \(ms(t - s.debut)) ms")
        if let pid = s.appCible?.processIdentifier, Permissions.accessibiliteOK {
            s.champ = Task.detached(priority: .userInitiated) { LecteurCurseur.lire(pid: pid) }
        }
        ouvertureRetardee?.cancel()
        // Finalisation : le texte du ruban se fixe en blanc (l'encoche reste ouverte jusqu'au texte final).
        if panneau.modele.ouverte { panneau.figer() }

        audio.arreter { [weak self] in
            // Sur la file audio : plus aucun tampon n'arrive. On envoie le dernier morceau.
            if let dernier = s.pipeline.terminer() { s.transcripteur.envoyer(wav: dernier.wav, duree: dernier.duree) }
            // La reconnaissance d'Apple finit en parallèle : son texte ne sert que si Groq échoue.
            if let direct = s.direct { s.secours = Task { await direct.terminer() } }
            Task { @MainActor in await self?.finaliser(s) }
        }
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
        var texte = ""
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
            if courante == nil { panneau.afficherMessage("Dictée impossible, réessaie", app: s.appCible) }
            return
        }
        Log.ecrire("dictée \(s.id) : texte de secours Apple utilisé, \"\(Log.apercu(texte))\"")
        await ecrire(texte, session: s, relachement: relache)
    }

    /// Referme l'encoche, sauf si une nouvelle dictée l'a déjà reprise.
    private func fermerSiLibre() {
        if courante == nil { panneau.fermer() }
    }

    /// Mise en forme selon l'app cible, puis collage au curseur.
    private func ecrire(_ brut: String, session s: Session, relachement relache: Double) async {
        let kind = TextFormatter.kind(bundleID: s.appCible?.bundleIdentifier)
        let champ = await s.champ?.value
        let contexte = RemiseAuPropre.contexte(bundleID: s.appCible?.bundleIdentifier, role: champ?.role, titreFenetre: champ?.titreFenetre)
        let nettoyage = await Nettoyage.executer(brut, contexte: contexte, mots: Dictionnaire.mots())
        Log.ecrire("dictée \(s.id) : mise en forme \(contexte.rawValue) (champ \(champ?.role ?? "?")), \(nettoyage.utilise ? "remis au propre" : "texte brut gardé : \(nettoyage.raison)") en \(ms(nettoyage.duree)) ms")
        let texteFinal = TextFormatter.prepare(nettoyage.texte, for: kind)
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
            memoire = MemoireInsertion(appId: s.appCible?.bundleIdentifier ?? "", queue: MemoireInsertion.queue(de: texte),
                                       instant: ProcessInfo.processInfo.systemUptime, frappes: compteurFrappes())
            Log.ecrire("dictée \(s.id) : collé dans \(s.appCible?.bundleIdentifier ?? "?") (\(kind)), collage \(collageMs) ms, \(total) ms après le relâchement")
        case .champProtege:
            Log.ecrire("dictée \(s.id) : champ protégé, texte copié sans collage")
            garder(inseree: false, raison: "champ protégé")
            if courante == nil { panneau.afficherMessage("Écriture impossible ici, texte copié", app: s.appCible) }
        case .copieSeulement(let raison):
            Log.ecrire("dictée \(s.id) : texte copié mais pas collé (\(raison))")
            garder(inseree: false, raison: raison)
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
        s.transcripteur.annuler()
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
