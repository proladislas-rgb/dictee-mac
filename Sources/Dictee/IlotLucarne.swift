import AppKit
import EventKit
import DicteeCore

// « Voxile, … » partout (CommandesLucarne.swift pour la logique), l'app Rappels d'Apple, et la note dictée d'un clic dans la carte
// Note rapide (11/11 au soir, Hugues : « c'est pas simple à utiliser… pas clair »).
// - Une dictée qui COMMENCE par « Voxile » (le nom de l'app) est une commande, jamais collée ; rien de reconnu → « Je n'ai pas compris » et la
//   phrase (« Copier »), jamais un échec silencieux. Sans le mot d'appel, rien ne change.
// - Chaque rappel créé par Lucarne peut aller aussi dans l'app Rappels (liste par défaut, alarme à l'heure) pour arriver sur l'iPhone.
//   Dit à Lucarne (« Voxile, rappelle-moi… »), la carte de fin (IlotVoix.swift) le montre et propose « Envoyer dans Rappels » ; ajouté
//   autrement (« En faire un rappel » sous une note), la question se pose UNE fois, depuis l'îlot ; un refus est dit une fois. « Fait » le
//   coche là-bas aussi.
// - « Dicter une note » : un clic, l'écoute commence dans la carte (« J'écoute… », le niveau, le texte en direct), « Terminé » ou 2 s de
//   silence l'arrêtent ; une note qui dit un jour ou une heure propose « En faire un rappel · demain 13:00 ».
// Tout ce qui touche au système (EventKit, la dictée) passe par des fermetures ou un pilote injectables : l'essai n'y touche jamais.

// MARK: - L'app Rappels d'Apple

/// L'app Rappels, vue de l'îlot. Le vrai pilote (EventKit) n'est jamais créé par l'essai, qui en met un faux.
@MainActor
protocol PiloteRappelsApple: AnyObject {
    var acces: AccesRappelsApple { get }
    /// La fenêtre de macOS (« Verbe veut accéder à vos rappels »), une seule fois ; `fini(accordé)`.
    func demander(_ fini: @escaping @MainActor (Bool) -> Void)
    /// Crée le rappel (liste par défaut, échéance et alarme à l'heure) ; ses identifiants, nil si impossible.
    func creer(texte: String, echeance: Date) -> DoubleApple?
    func cocher(_ d: DoubleApple) -> Bool
    func supprimer(_ d: DoubleApple)
    func deplacer(_ d: DoubleApple, a echeance: Date)
    /// Coché dans l'app Rappels (sur l'iPhone, par exemple) ? nil : introuvable.
    func estFait(_ d: DoubleApple) -> Bool?
}

@MainActor
final class RappelsAppleSysteme: PiloteRappelsApple {
    /// Créé au premier usage seulement (jamais au lancement, jamais dans l'essai).
    private lazy var magasin = EKEventStore()

    var acces: AccesRappelsApple {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: return .autorise
        case .notDetermined: return .nonDemande
        default: return .refuse
        }
    }

    func demander(_ fini: @escaping @MainActor (Bool) -> Void) {
        guard acces == .nonDemande else { fini(acces == .autorise); return }
        let m = magasin
        Task { @MainActor in
            do { fini(try await m.requestFullAccessToReminders()) } catch {
                Log.ecrire("rappels : la demande d'accès à l'app Rappels a échoué (\(error.localizedDescription))")
                fini(false)
            }
        }
    }

    func creer(texte: String, echeance: Date) -> DoubleApple? {
        guard acces == .autorise else { Log.ecrire("rappels : création impossible, accès à l'app Rappels non accordé"); return nil }
        // la liste par défaut peut manquer (aucune liste choisie par défaut, liste iCloud pas encore là) : la première liste modifiable
        // (12/11 : « 0 mis aussi dans l'app Rappels », trois fois, sans un mot ; le rappel de Hugues n'est jamais parti)
        let modifiables = magasin.calendars(for: .reminder).filter(\.allowsContentModifications)
        guard let liste = magasin.defaultCalendarForNewReminders().flatMap({ $0.allowsContentModifications ? $0 : nil }) ?? modifiables.first else {
            Log.ecrire("rappels : création impossible, aucune liste modifiable dans l'app Rappels (\(magasin.calendars(for: .reminder).count) liste(s))")
            return nil
        }
        let r = EKReminder(eventStore: magasin)
        r.title = texte
        r.calendar = liste
        r.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: echeance)
        r.addAlarm(EKAlarm(absoluteDate: echeance))
        do { try magasin.save(r, commit: true); return DoubleApple(id: r.calendarItemIdentifier, externe: r.calendarItemExternalIdentifier) } catch {
            Log.ecrire("rappels : création dans l'app Rappels impossible (\(error.localizedDescription))")
            return nil
        }
    }

    /// Le double, par son identifiant local, puis (il peut changer après une synchronisation complète ou un changement de liste) par
    /// son identifiant externe. Introuvable : dit au journal (sans le texte).
    private func rappel(_ d: DoubleApple) -> EKReminder? {
        guard acces == .autorise else { return nil }
        if let r = magasin.calendarItem(withIdentifier: d.id) as? EKReminder { return r }
        if let e = d.externe, let r = magasin.calendarItems(withExternalIdentifier: e).compactMap({ $0 as? EKReminder }).first { return r }
        Log.ecrire("rappels : un double introuvable dans l'app Rappels (supprimé là-bas, ou identifiant changé)")
        return nil
    }

    func cocher(_ d: DoubleApple) -> Bool {
        guard let r = rappel(d) else { return false }
        r.isCompleted = true
        return (try? magasin.save(r, commit: true)) != nil
    }
    func supprimer(_ d: DoubleApple) {
        guard let r = rappel(d) else { return }
        try? magasin.remove(r, commit: true)
    }
    func deplacer(_ d: DoubleApple, a echeance: Date) {
        guard let r = rappel(d) else { return }
        r.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: echeance)
        r.alarms?.forEach { r.removeAlarm($0) }
        r.addAlarm(EKAlarm(absoluteDate: echeance))
        try? magasin.save(r, commit: true)
    }
    func estFait(_ d: DoubleApple) -> Bool? { rappel(d)?.isCompleted }
}

extension IlotControleur {
    // MARK: « Voxile, … »

    /// Combien de temps « Je n'ai pas compris » reste (le temps de lire la phrase et de la copier) ; la question de l'app Rappels.
    static let dureeLucarne: TimeInterval = 6
    static let dureeQuestionRappels: TimeInterval = 15

    /// Une dictée qui commence par « Voxile » : la commande est faite, ou l'îlot dit pourquoi pas. Vrai : la dictée était
    /// pour Lucarne, rien n'est collé. Le journal ne garde jamais la phrase.
    func commandeLucarne(_ texte: String) -> Bool {
        let resultat = AnalyseCommandeIlot.lucarne(texte, maintenant: maintenant())
        switch resultat {
        case .aucune:
            return false
        case .commande(.minuteur(let secondes)):
            // une demande dite en toutes lettres : le minuteur éteint dans les réglages s'allume (comme un clic dans le Centre)
            if !reglagesCentre.minuteurActif() {
                reglagesCentre.allumerMinuteur()
                NotificationCenter.default.post(name: .verbeIlotReglagesRelus, object: nil)
            }
            lancerLeMinuteur(secondes: secondes, bandeau: true)
            Log.ecrire("lucarne : minuteur lancé (\(FormatIlot.minutes(secondes)))")
        case .commande(.rappel(let t, let quand)):
            if !reglagesCentre.rappelsActifs() {
                reglagesCentre.allumerRappels()
                NotificationCenter.default.post(name: .verbeIlotReglagesRelus, object: nil)
                Log.ecrire("lucarne : rappels allumés (demandés en toutes lettres)")
            }
            if ajouterUnRappel(texte: t, quand: quand, phraseDite: texte) != nil { Log.ecrire("lucarne : rappel ajouté (\(ListeRappels.jour(de: quand, maintenant: maintenant())) \(FormatIlot.heure(quand)))") }
            else { direLucarne(.incomprise(texte.trimmingCharacters(in: .whitespacesAndNewlines))) }
        case .commande(.reveil(let heure, let minute)):
            // le réveil (case Minuteur, onglet Réveil) : demandé en toutes lettres, « Minuteur et réveil » éteint se rallume
            if !reglagesCentre.minuteurActif() {
                reglagesCentre.allumerMinuteur()
                NotificationCenter.default.post(name: .verbeIlotReglagesRelus, object: nil)
            }
            reglerLeReveil(heure: heure, minute: minute, aLaVoix: true)
            Log.ecrire("lucarne : réveil réglé")
        case .incomprise(let phrase):
            direLucarne(.incomprise(phrase))
            Log.ecrire("lucarne : rien de reconnu (\(phrase.split(separator: " ").count) mots), rien n'est collé")
        case .sansHeure(let phrase):
            direLucarne(.sansHeure(phrase))
            Log.ecrire("lucarne : rappel sans heure, rien n'est collé")
        case .passe(let phrase):
            direLucarne(.passe(phrase))
            Log.ecrire("lucarne : rappel pour une heure déjà passée, pas ajouté, rien n'est collé")
        case .note(let t):
            if let n = enregistrerNote(t) { montrerCarteNote(n) } else { direLucarne(.incomprise(texte.trimmingCharacters(in: .whitespacesAndNewlines))) }
        }
        return true
    }

    /// Le texte de la note dictée d'un clic : liée à SA dictée (pas à une échéance), elle devient une note même si elle arrive tard
    /// (réseau lent, secours d'Apple sur une longue note) ; ou une commande si elle commence par « Voxile ». Faux : texte vide.
    func noteParClicEcrite(_ texte: String) -> Bool {
        intercepterLucarne(texte) || ajouterNote(texte)
    }

    private func direLucarne(_ m: MessageLucarne) {
        annoncerTout(BandeauIlot(vue: .lucarne, jusqua: maintenant().addingTimeInterval(Self.dureeLucarne), ligne1: "", ligne2: "", lucarne: m))
    }

    func agirLucarne(_ a: ActionIlot) {
        switch a {
        case .noteDicter: dicterUneNote()
        case .noteTerminer: terminerLaNote(raison: "Terminé")
        case .noteEnRappel(let id): faireUnRappelDeLaNote(id)
        case .lucarneCopier(let phrase):
            copier(phrase)
            moteur.quitterBandeau()
            Log.ecrire("lucarne : phrase copiée (\(phrase.count) caractères)")
        case .rappelsApple(let oui): repondreRappelsApple(oui)
        default: break
        }
    }

    // MARK: l'app Rappels

    enum SuiviRappel { case cocher, supprimer, deplacer }

    /// « Fait », « Annuler », « Plus tard » dans Lucarne : pareil dans l'app Rappels (si le rappel y a son double).
    func suivreDansRappels(_ r: Rappel, _ quoi: SuiviRappel) {
        guard let a = r.doubleApple, rappelsApple.acces == .autorise else { return }
        switch quoi {
        case .cocher: _ = rappelsApple.cocher(a)
        case .supprimer: rappelsApple.supprimer(a)
        case .deplacer: rappelsApple.deplacer(a, a: r.echeance)
        }
        Log.ecrire("rappels : \(quoi == .cocher ? "coché" : quoi == .supprimer ? "supprimé" : "déplacé") aussi dans l'app Rappels")
    }

    /// Avant de sonner : ceux qui ont été cochés dans l'app Rappels (sur l'iPhone) ne sonnent pas ici ; ils partent sans bruit.
    func retirerCeuxFaitsDansRappels(_ dus: [Rappel]) {
        guard rappelsApple.acces == .autorise else { return }
        var n = 0
        for r in dus { if let a = r.doubleApple, rappelsApple.estFait(a) == true { rappels.fait(r.id); n += 1 } }
        if n > 0 { Log.ecrire("rappels : \(n) déjà coché(s) dans l'app Rappels, ne sonne(nt) pas") }
    }

    /// Un rappel vient d'être ajouté : dans l'app Rappels aussi (accès donné), la question (jamais posée), ou le refus dit une fois.
    func synchroniserApresAjout(_ r: Rappel) {
        switch PlanRappelsApple.apresAjout(choix: reglagesCentre.choixRappelsApple(), acces: rappelsApple.acces) {
        case .creer:
            creerDansRappelsApple([r], annoncer: false)
        case .demander:
            guard !questionRappelsPosee else { return }
            questionRappelsPosee = true
            apresRappelAjoute { [weak self] in
                self?.annoncerTout(BandeauIlot(vue: .lucarne, jusqua: (self?.maintenant() ?? Date()).addingTimeInterval(Self.dureeQuestionRappels), ligne1: "", ligne2: "",
                                               lucarne: .questionRappelsApple))
            }
        case .direRefus:
            guard !reglagesCentre.refusRappelsDit() else { return }
            reglagesCentre.marquerRefusRappelsDit()
            apresRappelAjoute { [weak self] in self?.direLucarne(.rappelsRestentIci(systeme: true)) }
        case .rien:
            break
        }
    }

    /// Après « Rappel ajouté » (qu'on ait le temps de le lire, et « Annuler ») ; « Annuler » retire aussi ce qui attendait.
    private func apresRappelAjoute(_ f: @escaping () -> Void) {
        questionRappelsApple?.cancel()
        let item = DispatchWorkItem { MainActor.assumeIsolated { f() } }
        questionRappelsApple = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.dureeRappelAjoute + 1, execute: item)
    }

    /// « Oui » : la fenêtre de macOS (une fois), puis les rappels à venir vont dans l'app Rappels ; « Non » ou refus : dit une fois.
    func repondreRappelsApple(_ oui: Bool) {
        moteur.quitterBandeau()
        func refus(systeme: Bool) {
            reglagesCentre.enregistrerChoixRappelsApple(.non)
            reglagesCentre.marquerRefusRappelsDit()
            Log.ecrire("rappels : l'app Rappels \(systeme ? "refusée dans la fenêtre de macOS" : "refusée dans l'îlot"), les rappels restent dans Lucarne")
            direLucarne(.rappelsRestentIci(systeme: systeme))
        }
        guard oui else { refus(systeme: false); return }
        reglagesCentre.enregistrerChoixRappelsApple(.oui)
        rappelsApple.demander { [weak self] accorde in
            guard let self else { return }
            if accorde { self.creerDansRappelsApple(self.rappels.sansDoubleApple(a: self.maintenant()), annoncer: true) } else { refus(systeme: true) }
        }
    }

    /// Les met dans l'app Rappels, chacun une seule fois (un rappel déjà lié n'est jamais recréé).
    func creerDansRappelsApple(_ liste: [Rappel], annoncer: Bool) {
        var n = 0
        for r in liste where r.idApple == nil {
            guard let a = rappelsApple.creer(texte: r.texte, echeance: r.echeance) else { continue }
            // supprimé entre-temps (« Annuler ») : le double ne doit pas rester seul là-bas
            if rappels.lier(r.id, apple: a.id, externe: a.externe) { n += 1 } else { rappelsApple.supprimer(a) }
        }
        if n > 0 { sauver() }
        Log.ecrire("rappels : \(n) mis aussi dans l'app Rappels")
        if annoncer, n > 0 {
            annoncerTout(BandeauIlot(vue: .lucarne, jusqua: maintenant().addingTimeInterval(3), ligne1: "", ligne2: "", lucarne: .dansRappelsApple(n)))
        }
    }

    // MARK: la note dictée d'un clic

    /// « Dicter une note » : la dictée part sans encoche, la carte montre « J'écoute… » ; elle s'arrête sur « Terminé » ou après 2 s de
    /// silence (FinDeNote), et devient une note (jamais collée dans l'app).
    func dicterUneNote() {
        let e = moteur.ecouteNote
        guard e.phase == .repos else { return }
        noteParClic = true
        moteur.suggestionRappel = nil
        e.message = nil
        guard surDicterNote() else { noteParClic = false; Log.ecrire("note rapide : l'écoute n'a pas pu partir"); return }
        e.texte = ""; e.niveau = 0; e.phase = .ecoute
        finDeNote = FinDeNote(debut: maintenant())
        minuterieNote?.invalidate()
        minuterieNote = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.verifierFinDeNote() } }
        minuterieNote?.tolerance = 0.05
        Log.ecrire("note rapide : écoute lancée d'un clic")
    }

    /// Le niveau du micro (vingt fois par seconde) et le texte en direct, pendant l'écoute.
    func niveauDeNote(_ n: Float) {
        guard moteur.ecouteNote.phase == .ecoute else { return }
        moteur.ecouteNote.niveau = n
        finDeNote?.niveau(n, a: maintenant())
    }
    func texteDeNote(_ t: String) {
        guard moteur.ecouteNote.phase == .ecoute else { return }
        moteur.ecouteNote.texte = t
    }

    func verifierFinDeNote() {
        guard moteur.ecouteNote.phase == .ecoute, let f = finDeNote else { minuterieNote?.invalidate(); minuterieNote = nil; return }
        guard let r = f.fin(a: maintenant()) else { return }
        terminerLaNote(raison: r == .silence ? "2 s de silence" : r == .rienEntendu ? "rien entendu en 8 s" : "2 minutes")
    }

    func terminerLaNote(raison: String) {
        guard moteur.ecouteNote.phase == .ecoute else { return }
        Log.ecrire("note rapide : fin de l'écoute (\(raison))")
        noteEnEcriture()
        surTerminerNote()
    }

    /// Le filet de « J'écris la note… » : la dictée dit toujours comment elle finit (le texte, ou rien) ; ce réveil ne sert que si elle ne
    /// disait rien. Au-delà de la note la plus longue (2 min) transcrite par le secours d'Apple ; un texte qui arrive encore après devient
    /// une note quand même (`noteParClicEcrite`).
    static let filetNote: TimeInterval = 180

    /// « J'écris la note… » jusqu'à la note (ajouterNote) ou « rien entendu » ; un seul réveil la remet au repos si rien n'arrive.
    func noteEnEcriture() {
        minuterieNote?.invalidate(); minuterieNote = nil; finDeNote = nil
        let e = moteur.ecouteNote
        e.phase = .ecriture; e.niveau = 0
        echeanceNote?.cancel()
        let item = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.noteSansTexte() } }
        echeanceNote = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.filetNote, execute: item)
    }

    /// La note d'un clic n'a rien donné (rien entendu, rien reconnu, annulée) : la carte revient au bouton, et le dit.
    func noteSansTexte() {
        echeanceNote?.cancel(); echeanceNote = nil
        minuterieNote?.invalidate(); minuterieNote = nil; finDeNote = nil
        let e = moteur.ecouteNote
        guard e.phase != .repos else { return }
        e.phase = .repos; e.texte = ""; e.niveau = 0
        e.message = "Je n\u{2019}ai rien entendu, réessaie"
        noteArmeeJusqua = .distantPast
        Log.ecrire("note rapide : rien entendu, pas de note")
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            MainActor.assumeIsolated { if self?.moteur.ecouteNote.message != nil, self?.moteur.ecouteNote.phase == .repos { self?.moteur.ecouteNote.message = nil } }
        }
    }

    /// La note vient d'être écrite : la carte revient au bouton ; si la note dit un jour ou une heure, « En faire un rappel » dessous.
    func noteEcrite(_ n: NoteRapide) {
        echeanceNote?.cancel(); echeanceNote = nil
        let e = moteur.ecouteNote
        e.phase = .repos; e.texte = ""; e.niveau = 0; e.message = nil
        moteur.suggestionRappel = AnalyseCommandeIlot.rappelDansUneNote(n.texte, maintenant: maintenant()).map { (n.id, $0.texte, $0.quand) }
        if moteur.suggestionRappel != nil { Log.ecrire("note rapide : elle ressemble à un rappel, « En faire un rappel » proposé") }
    }

    /// « En faire un rappel · demain 13:00 » : le rappel est ajouté (« Rappel ajouté » et « Annuler »), la note reste.
    func faireUnRappelDeLaNote(_ id: UUID) {
        guard let s = moteur.suggestionRappel, s.note == id else { return }
        moteur.suggestionRappel = nil
        if !reglagesCentre.rappelsActifs() { reglagesCentre.allumerRappels(); NotificationCenter.default.post(name: .verbeIlotReglagesRelus, object: nil) }
        if ajouterUnRappel(texte: s.texte, quand: s.quand) != nil { Log.ecrire("note rapide : transformée en rappel") }
    }
}

/// La phrase telle qu'on la MONTRE sous « Je n'ai pas compris » (l'aperçu ; « Copier » garde la phrase entière).
enum TexteDictePropre {
    static func apercu(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count > 120 ? String(t.prefix(119)) + "\u{2026}" : t
    }
}
