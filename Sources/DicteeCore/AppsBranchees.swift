import Foundation

// La façade de « Tes apps » : ce que l'interface de l'îlot appelle. Elle tient la mémoire (`MemoireApps`), les clés (par `CoffreCles`,
// le Trousseau dans l'app), le rythme (`PlanSondages`), et rend des `Nouveaute`.
//
// Pour l'interface :
// - `brancher(.mail)` / `brancher(.agenda)` ; `enregistrerCle(_:pour:)` puis `choisirBaseNotion` / `choisirPersonneNotion` ou
//   `choisirTableAirtable` ; `debrancher(_:)` (efface aussi la clé) ;
// - une minuterie appelle `sonder()` à `prochainSondage()` ; `surNouveautes` reçoit ce qui est à annoncer (jamais deux fois la même
//   chose) ; `actuelles` et `etats` disent quoi montrer.
// Tout est injectable : les contrôles n'appellent jamais le vrai réseau, la vraie Mail ni le vrai Trousseau.

/// Où sont rangées les clés (le Trousseau dans l'app ; un coffre en mémoire dans les contrôles). Jamais un fichier.
public protocol CoffreCles: Sendable {
    func lire(_ app: AppBranchee) -> String?
    @discardableResult func ranger(_ cle: String, pour app: AppBranchee) -> Bool
    func effacer(_ app: AppBranchee)
}

/// Un coffre en mémoire (contrôles, essais) : rien ne touche au Trousseau.
public final class CoffreEnMemoire: CoffreCles, @unchecked Sendable {
    private var cles: [AppBranchee: String] = [:]
    private let verrou = NSLock()
    public init(_ cles: [AppBranchee: String] = [:]) { self.cles = cles }
    public func lire(_ app: AppBranchee) -> String? { verrou.withLock { cles[app] } }
    public func ranger(_ cle: String, pour app: AppBranchee) -> Bool { verrou.withLock { cles[app] = cle }; return true }
    public func effacer(_ app: AppBranchee) { _ = verrou.withLock { cles.removeValue(forKey: app) } }
}

@MainActor
public final class AppsBranchees {
    /// Ce qu'on garde de chaque app pour l'affichage (les plus récentes d'abord).
    public static let maxActuelles = 10

    public private(set) var memoire: MemoireApps
    public private(set) var etats: [AppBranchee: EtatApp] = [:]
    /// Ce que chaque app montre en ce moment : les non lus de Mail, le prochain rendez-vous, les tâches Notion, les fiches Airtable.
    public private(set) var actuelles: [AppBranchee: [Nouveaute]] = [:]
    public private(set) var plan = PlanSondages()
    /// Ce qui est à annoncer, jamais vu avant (appelé après chaque sondage qui en trouve).
    public var surNouveautes: ([Nouveaute]) -> Void = { _ in }
    /// Un état ou une liste a changé (l'interface se redessine).
    public var surChangement: () -> Void = {}

    private let magasin: MagasinJSON<MemoireApps>
    private let coffre: CoffreCles
    private let transport: TransportHTTP
    private let mail: SourceMail
    private let agenda: @MainActor () -> [EvenementAgenda]
    private let horloge: () -> Date
    private let heure: (Date) -> String
    private let journal: (String) -> Void
    private let espacementNotion: EspacementRequetes
    private let espacementAirtable: EspacementRequetes
    private var enCours: Set<AppBranchee> = []

    /// `agenda` : les rendez-vous que l'îlot lit déjà (AgendaSysteme.prochains) ; `heure` : « 14:30 » ; `journal` : le journal de l'app
    /// (jamais une clé n'y est écrite : seulement l'app, l'état, des nombres).
    public init(magasin: MagasinJSON<MemoireApps>, coffre: CoffreCles, transport: TransportHTTP, mail: SourceMail,
                agenda: @escaping @MainActor () -> [EvenementAgenda], horloge: @escaping () -> Date = { Date() },
                heure: @escaping (Date) -> String, journal: @escaping (String) -> Void = { _ in },
                espacementNotion: EspacementRequetes = EspacementRequetes(ecart: ClientNotion.ecart),
                espacementAirtable: EspacementRequetes = EspacementRequetes(ecart: ClientAirtable.ecart)) {
        self.magasin = magasin; self.coffre = coffre; self.transport = transport; self.mail = mail; self.agenda = agenda
        self.horloge = horloge; self.heure = heure; self.journal = journal
        self.espacementNotion = espacementNotion; self.espacementAirtable = espacementAirtable
        memoire = magasin.lire() ?? MemoireApps()
        for a in AppBranchee.allCases { etats[a] = memoire.branchees.contains(a) ? .enAttente : .debranchee }
    }

    // MARK: brancher, débrancher

    public func estBranchee(_ a: AppBranchee) -> Bool { memoire.branchees.contains(a) }

    /// Mail et Agenda : un geste suffit (l'autorisation de macOS est demandée au premier sondage de Mail ; celle du calendrier, par
    /// l'îlot). Notion et Airtable : passer par `enregistrerCle`.
    public func brancher(_ a: AppBranchee) {
        guard !a.demandeUneCle || coffre.lire(a) != nil else { etats[a] = .erreur(.cleAbsente(a)); surChangement(); return }
        memoire.branchees.insert(a)
        etats[a] = .enAttente
        plan.maintenant(a, horloge())
        enregistrer()
        journal("apps : \(a.rawValue) branché")
        surChangement()
    }

    /// Débranche, oublie ses réglages et ce qui a été vu, et efface sa clé du Trousseau.
    public func debrancher(_ a: AppBranchee) {
        memoire.oublier(a)
        if a.demandeUneCle { coffre.effacer(a) }
        plan.retirer(a)
        etats[a] = .debranchee
        actuelles[a] = nil
        enregistrer()
        journal("apps : \(a.rawValue) débranché")
        surChangement()
    }

    /// L'Agenda n'a rien à brancher (Voxile lit déjà le calendrier) : la première fois que le calendrier est permis, il est branché
    /// d'office, une seule fois (débranché ensuite, il le reste).
    public func brancherAgendaUneFois(calendrierPermis: Bool) {
        guard calendrierPermis, memoire.agendaPropose != true else { return }
        memoire.agendaPropose = true
        if estBranchee(.agenda) { enregistrer() } else { brancher(.agenda) }
    }

    /// La clé rangée, montrée sans être lisible (« ntn_••••••••k7Rm ») ; nil : aucune clé.
    public func cleMasquee(_ a: AppBranchee) -> String? {
        guard a.demandeUneCle, let c = coffre.lire(a) else { return nil }
        return ClePartielle.masque(c)
    }

    /// Le branchement a été laissé en route (la clé vérifiée, la base pas encore choisie) : la clé ne reste pas dans le Trousseau d'une app
    /// qui n'est pas branchée.
    public func abandonner(_ a: AppBranchee) {
        guard a.demandeUneCle, !estBranchee(a), coffre.lire(a) != nil else { return }
        coffre.effacer(a)
        journal("apps : branchement de \(a.rawValue) laissé en route, clé effacée")
    }

    /// Un geste de Hugues (« Réessayer ») : l'app est sondée tout de suite, même arrêtée par une erreur qui demandait un geste.
    public func reessayer(_ a: AppBranchee) async -> [Nouveaute] {
        guard estBranchee(a), !enCours.contains(a) else { return [] }
        plan.maintenant(a, horloge())
        etats[a] = .enAttente
        surChangement()
        let n = await sonder(a)
        if !n.isEmpty { surNouveautes(n) }
        return n
    }

    /// Vérifie la clé auprès de l'app, puis la range dans le coffre (jamais avant : une clé refusée n'est pas gardée). Rend le nom du
    /// compte ou de l'espace. L'app n'est branchée qu'une fois la base (Notion) ou la table (Airtable) choisie.
    public func enregistrerCle(_ saisie: String, pour a: AppBranchee) async -> Result<String, ErreurApp> {
        let cle = saisie.trimmingCharacters(in: .whitespacesAndNewlines)
        guard a.demandeUneCle else { return .failure(.reglageIncomplet(a)) }
        let vraisemblable = a == .notion ? ClientNotion.vraisemblable(cle) : ClientAirtable.vraisemblable(cle)
        guard vraisemblable else { journal("apps : clé \(a.rawValue) refusée avant envoi (forme)"); return .failure(.cleRefusee(a)) }
        do {
            let nom = a == .notion ? try await notion(cle).verifier() : try await airtable(cle).verifier()
            guard coffre.ranger(cle, pour: a) else { return .failure(.refus(a, 0)) }
            journal("apps : clé \(a.rawValue) vérifiée et rangée dans le Trousseau")
            return .success(nom)
        } catch {
            journal("apps : clé \(a.rawValue) non vérifiée (\(Self.resume(error)))")
            return .failure(error)
        }
    }

    public func basesNotion() async -> Result<[ChoixApp], ErreurApp> {
        guard let c = clientNotion() else { return .failure(.cleAbsente(.notion)) }
        do { return .success(try await c.bases()) } catch { return .failure(error) }
    }
    public func personnesNotion() async -> Result<[ChoixApp], ErreurApp> {
        guard let c = clientNotion() else { return .failure(.cleAbsente(.notion)) }
        do { return .success(try await c.personnes()) } catch { return .failure(error) }
    }
    /// Lit la base choisie (ses propriétés date et personne), la retient et branche Notion.
    public func choisirBaseNotion(_ id: String) async -> Result<ReglageNotion, ErreurApp> {
        guard let c = clientNotion() else { return .failure(.cleAbsente(.notion)) }
        do {
            var r = try await c.reglage(base: id)
            r.personneId = memoire.notion?.baseId == r.baseId ? memoire.notion?.personneId : nil
            r.personneNom = r.personneId == nil ? nil : memoire.notion?.personneNom
            memoire.notion = r
            memoire.amorcees.remove(.notion)
            brancher(.notion)
            return .success(r)
        } catch { return .failure(error) }
    }
    /// La personne dont on suit les tâches assignées (nil : seulement les tâches du jour).
    public func choisirPersonneNotion(_ id: String?, nom: String? = nil) {
        guard var r = memoire.notion else { return }
        r.personneId = id.map(ClientNotion.identifiantPropre)
        r.personneNom = id == nil ? nil : nom
        memoire.notion = r
        plan.maintenant(.notion, horloge())
        enregistrer(); surChangement()
    }

    public func basesAirtable() async -> Result<[ChoixApp], ErreurApp> {
        guard let c = clientAirtable() else { return .failure(.cleAbsente(.airtable)) }
        do { return .success(try await c.bases()) } catch { return .failure(error) }
    }
    public func tablesAirtable(base: String) async -> Result<[TableAirtable], ErreurApp> {
        guard let c = clientAirtable() else { return .failure(.cleAbsente(.airtable)) }
        do { return .success(try await c.tables(base: base)) } catch { return .failure(error) }
    }
    /// Retient la table choisie et branche Airtable (la première fenêtre : les fiches modifiées dans les dernières 24 h, montrées sans
    /// être annoncées).
    public func choisirTableAirtable(base: ChoixApp, table: TableAirtable) {
        memoire.airtable = ReglageAirtable(baseId: base.id, baseNom: base.nom, tableId: table.id, tableNom: table.nom,
                                           champTitre: table.champTitre, champModification: table.champModification)
        memoire.airtableDepuis = nil
        memoire.amorcees.remove(.airtable)
        brancher(.airtable)
    }

    // MARK: sonder

    /// Quand rappeler `sonder()` (nil : rien de branché, ou tout est arrêté en attendant un geste).
    public func prochainSondage() -> Date? { plan.prochain(branchees: memoire.branchees, apres: horloge()) }

    /// Sonde les apps dont c'est l'heure (`force` : toutes celles branchées, un geste de Hugues) et rend ce qui est nouveau.
    @discardableResult
    public func sonder(force: Bool = false) async -> [Nouveaute] {
        let t = horloge()
        let apps = force ? memoire.branchees.sorted() : plan.aSonder(t, branchees: memoire.branchees)
        var toutes: [Nouveaute] = []
        for a in apps where !enCours.contains(a) {
            if force { plan.maintenant(a, t) }
            toutes += await sonder(a)
        }
        if !toutes.isEmpty { surNouveautes(toutes) }
        return toutes
    }

    private func sonder(_ a: AppBranchee) async -> [Nouveaute] {
        enCours.insert(a); defer { enCours.remove(a) }
        let debut = horloge()
        do {
            guard let lues = try await lire(a) else {
                plan.enPause(a, horloge()); etats[a] = .enPause; surChangement(); return []
            }
            guard memoire.branchees.contains(a) else { return [] }   // débranchée pendant la lecture
            let fin = horloge()
            let nouvelles = memoire.retenir(lues.elements, app: a, maintenant: fin)
            lues.apres(&memoire)
            actuelles[a] = Self.fusion(lues.remplace ? [] : (actuelles[a] ?? []), lues.elements)
            plan.reussi(a, fin, duree: fin.timeIntervalSince(debut))
            etats[a] = .aJour(fin)
            enregistrer()
            journal("apps : \(a.rawValue) lu (\(lues.elements.count), \(nouvelles.count) nouveau\(nouvelles.count > 1 ? "x" : ""), \(Int((fin.timeIntervalSince(debut) * 1000).rounded())) ms)")
            surChangement()
            return nouvelles
        } catch {
            guard memoire.branchees.contains(a) else { return [] }
            plan.echoue(a, horloge(), error)
            etats[a] = .erreur(error)
            journal("apps : \(a.rawValue) en erreur (\(Self.resume(error)))")
            surChangement()
            return []
        }
    }

    /// Ce qu'une lecture rend : les éléments, ce qu'il faut retenir pour la suivante, et si la liste remplace l'affichage (Mail, Notion,
    /// Agenda : l'état complet) ou s'y ajoute (Airtable : seulement ce qui a changé).
    private struct Lecture {
        var elements: [Nouveaute]
        var remplace = true
        var apres: (inout MemoireApps) -> Void = { _ in }
    }

    /// nil : rien à lire maintenant (Mail fermé).
    private func lire(_ a: AppBranchee) async throws(ErreurApp) -> Lecture? {
        let t = horloge()
        switch a {
        case .mail:
            guard await mail.estOuvert() else { return nil }
            let fenetre = memoire.fenetreMail(maintenant: t)
            let messages: [MessageMail]
            do { messages = try await mail.nonLus(depuisSecondes: fenetre, max: ScriptMail.maximum) }
            catch .mailFerme { return nil }   // fermé entre les deux questions
            return Lecture(elements: messages.map(ScriptMail.nouveaute), apres: { $0.mailDernier = t })
        case .agenda:
            return Lecture(elements: AgendaApps.nouveaute(agenda(), maintenant: t, heure: heure).map { [$0] } ?? [])
        case .notion:
            guard let c = clientNotion() else { throw .cleAbsente(.notion) }
            guard let r = memoire.notion, r.complet else { throw .reglageIncomplet(.notion) }
            let jour = ReponseHTTP.jour(t)
            let pages = try await c.taches(r, maintenant: t)
            return Lecture(elements: pages.map { ClientNotion.nouveaute($0, jour: jour, heure: heure) })
        case .airtable:
            guard let c = clientAirtable() else { throw .cleAbsente(.airtable) }
            guard let r = memoire.airtable else { throw .reglageIncomplet(.airtable) }
            let depuis = memoire.airtableDepuis ?? t.addingTimeInterval(-86_400)
            let (fiches, serveur) = try await c.modifiees(r, depuis: depuis)
            // sans l'heure d'Airtable, l'heure du Mac moins une minute (un chevauchement : le dédoublonnage s'en charge si la table a un
            // champ « Dernière modification » ; sinon une fiche peut revenir une fois, jamais disparaître)
            let suivante = serveur ?? t.addingTimeInterval(-60)
            return Lecture(elements: fiches.map { ClientAirtable.nouveaute($0, reglage: r, fenetre: depuis, vue: t) }, remplace: false,
                           apres: { $0.airtableDepuis = suivante })
        }
    }

    // MARK: outils

    private func notion(_ cle: String) -> ClientNotion { ClientNotion(cle: cle, transport: transport, espacement: espacementNotion) }
    private func airtable(_ cle: String) -> ClientAirtable { ClientAirtable(cle: cle, transport: transport, espacement: espacementAirtable) }
    private func clientNotion() -> ClientNotion? { coffre.lire(.notion).map(notion) }
    private func clientAirtable() -> ClientAirtable? { coffre.lire(.airtable).map(airtable) }

    private func enregistrer() { magasin.ecrire(memoire) }

    /// Les plus récentes d'abord, une seule fois chaque clé, `maxActuelles` au plus.
    static func fusion(_ avant: [Nouveaute], _ nouvelles: [Nouveaute]) -> [Nouveaute] {
        var vus = Set<String>()
        return (nouvelles + avant).filter { vus.insert($0.id).inserted }.sorted { $0.date > $1.date }.prefix(maxActuelles).map { $0 }
    }

    /// Une erreur au journal : son genre, jamais un texte reçu ni une clé.
    static func resume(_ e: ErreurApp) -> String {
        switch e {
        case .cleAbsente: return "pas de clé"
        case .cleRefusee: return "clé refusée"
        case .droitsManquants(_, let d): return "droits manquants : \(d)"
        case .introuvable: return "introuvable"
        case .limite(_, let s): return "limite de débit, \(Int(s)) s"
        case .serveur(_, let c): return "serveur \(c)"
        case .refus(_, let c): return "refus \(c)"
        case .reseau: return "réseau"
        case .reponseIllisible: return "réponse illisible"
        case .reglageIncomplet: return "réglage incomplet"
        case .autorisationMail: return "Automatisation refusée"
        case .mailFerme: return "Mail fermé"
        case .mail(let c): return "AppleScript \(c)"
        }
    }
}
