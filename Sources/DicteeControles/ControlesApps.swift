import Foundation
import DicteeCore

// « Tes apps » (Mail, Agenda, Notion, Airtable) : le cœur, sur des réponses JSON d'exemple. Aucun appel réseau réel (faux transport),
// jamais la vraie Mail (faux Mail), jamais le vrai Trousseau (coffre en mémoire), jamais le vrai dossier de Voxile (dossier temporaire).

/// Un faux réseau : rend une réponse d'exemple selon l'adresse, et garde chaque requête pour qu'on la relise.
final class FauxReseau: TransportHTTP, @unchecked Sendable {
    struct Reponse { var statut = 200; var entetes: [String: String] = [:]; var corps = "{}"; var panne = false }
    private let verrou = NSLock()
    private var _requetes: [URLRequest] = []
    private var _routes: [(String, Reponse)] = []
    var requetes: [URLRequest] { verrou.withLock { _requetes } }
    /// La première route dont le motif est dans l'adresse (méthode comprise : « POST databases/…/query ») ; les plus récentes d'abord.
    func repondre(_ motif: String, _ r: Reponse) { verrou.withLock { _routes.insert((motif, r), at: 0) } }
    func oublierRequetes() { verrou.withLock { _requetes = [] } }
    func envoyer(_ requete: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let cle = (requete.httpMethod ?? "GET") + " " + (requete.url?.absoluteString ?? "")
        let r: Reponse = verrou.withLock {
            _requetes.append(requete)
            return _routes.first { cle.contains($0.0) }?.1 ?? Reponse(statut: 404, corps: #"{"code":"object_not_found"}"#)
        }
        if r.panne { throw URLError(.notConnectedToInternet) }
        let h = HTTPURLResponse(url: requete.url!, statusCode: r.statut, httpVersion: "HTTP/1.1", headerFields: r.entetes)!
        return (Data(r.corps.utf8), h)
    }
}

/// Un faux Mail : ouvert ou fermé, une liste de non lus, ou une erreur d'AppleScript.
final class FauxMail: SourceMail, @unchecked Sendable {
    private let verrou = NSLock()
    private var _ouvert = true, _messages: [MessageMail] = [], _erreur: ErreurApp?, _appels: [Int] = []
    var ouvert: Bool { get { verrou.withLock { _ouvert } } set { verrou.withLock { _ouvert = newValue } } }
    var messages: [MessageMail] { get { verrou.withLock { _messages } } set { verrou.withLock { _messages = newValue } } }
    var erreur: ErreurApp? { get { verrou.withLock { _erreur } } set { verrou.withLock { _erreur = newValue } } }
    /// Les fenêtres demandées (secondes), une par lecture.
    var appels: [Int] { verrou.withLock { _appels } }
    func estOuvert() async -> Bool { ouvert }
    func nonLus(depuisSecondes s: Int, max: Int) async throws(ErreurApp) -> [MessageMail] {
        let (e, m): (ErreurApp?, [MessageMail]) = verrou.withLock { _appels.append(s); return (_erreur, _messages) }
        if let e { throw e }
        return Array(m.prefix(max))
    }
}

/// Une horloge qu'on avance à la main.
final class HorlogeEssai: @unchecked Sendable {
    private let verrou = NSLock()
    private var _t: Date
    init(_ t: Date) { _t = t }
    var t: Date { get { verrou.withLock { _t } } set { verrou.withLock { _t = newValue } } }
    func avancer(_ s: TimeInterval) { t = t.addingTimeInterval(s) }
}

/// Un espacement qui ne dort jamais (il note les attentes demandées).
final class Attentes: @unchecked Sendable {
    private let verrou = NSLock()
    private var _liste: [TimeInterval] = []
    var liste: [TimeInterval] { verrou.withLock { _liste } }
    func noter(_ s: TimeInterval) { verrou.withLock { _liste.append(s) } }
}

// MARK: réponses d'exemple (inventées : aucun vrai nom, aucune vraie donnée)

enum ExemplesApps {
    static let notionMoi = #"{"object":"user","id":"9a1b2c3d-0000-4000-8000-000000000001","type":"bot","name":"Voxile","bot":{"owner":{"type":"workspace","workspace":true},"workspace_name":"Espace Essai"}}"#
    static let notionBases = #"{"object":"list","results":[{"object":"database","id":"0f0e0d0c-1111-4222-8333-444455556666","title":[{"plain_text":"Tâches "},{"plain_text":"de l'équipe"}]},{"object":"page","id":"x"},{"object":"database","id":"aaaabbbb-1111-4222-8333-444455556666","title":[]}],"has_more":false}"#
    static let notionPersonnes = #"{"object":"list","results":[{"object":"user","id":"11111111-2222-4333-8444-555555555555","type":"person","name":"Camille Essai","person":{"email":"camille@exemple.fr"}},{"object":"user","id":"b0b","type":"bot","name":"Voxile"}]}"#
    static let notionSchema = #"{"object":"database","id":"0f0e0d0c-1111-4222-8333-444455556666","title":[{"plain_text":"Tâches de l'équipe"}],"properties":{"Nom":{"id":"title","type":"title","title":{}},"Échéance":{"id":"a1","type":"date","date":{}},"Créée":{"id":"a0","type":"date","date":{}},"Assigné à":{"id":"b1","type":"people","people":{}},"Statut":{"id":"c1","type":"status","status":{}}}}"#
    static func notionPages(_ pages: [(id: String, titre: String, echeance: String?, modif: String, archivee: Bool)]) -> String {
        let r = pages.map { p in
            let ech = p.echeance.map { #""Échéance":{"type":"date","date":{"start":"\#($0)","end":null}},"# } ?? ""
            return #"{"object":"page","id":"\#(p.id)","url":"https://www.notion.so/Page-\#(p.id.replacingOccurrences(of: "-", with: ""))","archived":\#(p.archivee),"last_edited_time":"\#(p.modif)","properties":{\#(ech)"Nom":{"type":"title","title":[{"plain_text":"\#(p.titre)"}]}}}"#
        }
        return #"{"object":"list","results":["# + r.joined(separator: ",") + #"],"has_more":false}"#
    }
    static let airtableMoi = #"{"id":"usrEssai0000001","scopes":["data.records:read","schema.bases:read"]}"#
    static let airtableMoiSansSchema = #"{"id":"usrEssai0000001","scopes":["data.records:read"]}"#
    static let airtableBases = #"{"bases":[{"id":"appEssai00000001","name":"Suivi des ventes","permissionLevel":"create"}]}"#
    static let airtableTables = #"{"tables":[{"id":"tblEssai00000001","name":"Contacts","primaryFieldId":"fldNom000000001","fields":[{"id":"fldNom000000001","name":"Nom","type":"singleLineText"},{"id":"fldModif00000001","name":"Dernière modification","type":"lastModifiedTime"}]},{"id":"tblEssai00000002","name":"Notes","primaryFieldId":"fldTitre0000001","fields":[{"id":"fldTitre0000001","name":"Titre","type":"multilineText"}]}]}"#
    static func airtableFiches(_ f: [(id: String, nom: String, modif: String?)]) -> String {
        #"{"records":["# + f.map { x in
            let m = x.modif.map { #","fldModif00000001":"\#($0)""# } ?? ""
            return #"{"id":"\#(x.id)","createdTime":"2026-11-01T08:00:00.000Z","fields":{"fldNom000000001":"\#(x.nom)"\#(m)}}"#
        }.joined(separator: ",") + "]}"
    }
}

@MainActor
func controlesApps() async {
    let paris = TimeZone(identifier: "Europe/Paris")!
    func date(_ s: String) -> Date { ReponseHTTP.date(s)! }

    groupe("Tes apps : modèles")
    verifier(Nouveaute.ligne("  Réunion\n\tde   suivi \u{0007} ") == "Réunion de suivi", "une ligne : espaces, retours et caractères de contrôle ramenés à un seul espace")
    verifier(Nouveaute.ligne(String(repeating: "a", count: 200), max: 10) == "aaaaaaaaa\u{2026}", "coupée à la longueur voulue, avec « … »")
    verifier(ActionOuverture.messageMail(id: "abc+1@mail.exemple.fr").adresse?.absoluteString == "message://%3Cabc+1@mail.exemple.fr%3E",
             "un mail s'ouvre dans Mail par message://%3C…%3E")
    verifier(ActionOuverture.messageMail(id: "a b/c?d#e").adresse?.absoluteString == "message://%3Ca%20b%2Fc%3Fd%23e%3E", "un identifiant bizarre est encodé (jamais une autre adresse)")
    verifier(ActionOuverture.rendezVous(id: "x").adresse == nil, "un rendez-vous : l'interface l'ouvre à sa façon")
    verifier(ErreurApp.introuvable(.notion).texte.contains("ajoute ta connexion") && ErreurApp.autorisationMail.texte.contains("Automatisation"),
             "les erreurs disent quoi faire, en français")
    verifier(ErreurApp.cleRefusee(.airtable).demandeUnGeste && !ErreurApp.reseau(.notion).demandeUnGeste && !ErreurApp.limite(.notion, reessayerDans: 2).demandeUnGeste,
             "clé refusée : on attend un geste ; réseau, limite : on réessaie")
    verifier(AppBranchee.allCases.filter(\.demandeUneCle) == [.notion, .airtable] && Desinstallation.comptesTrousseauApps == ["notion", "airtable"],
             "Notion et Airtable ont une clé (Trousseau, même service que Groq) ; Mail et Agenda non")

    groupe("Tes apps : lecture des réponses HTTP")
    func reponse(_ e: [String: String]) -> HTTPURLResponse { HTTPURLResponse(url: URL(string: "https://exemple.fr")!, statusCode: 200, httpVersion: nil, headerFields: e)! }
    verifier(ReponseHTTP.reessayerApres(reponse(["Retry-After": "2"])) == 2 && ReponseHTTP.reessayerApres(reponse([:])) == nil
             && ReponseHTTP.reessayerApres(reponse(["Retry-After": "99999"])) == 3600, "« Retry-After » en secondes (borné à 1 h)")
    verifier(ReponseHTTP.dateServeur(reponse(["Date": "Fri, 13 Nov 2026 10:00:05 GMT"])) == date("2026-11-13T10:00:05Z"), "l'heure du serveur (en-tête Date)")
    verifier(ReponseHTTP.date("2026-11-13T09:41:00.250Z") == date("2026-11-13T09:41:00Z").addingTimeInterval(0.25)
             && ReponseHTTP.date("2026-11-13T09:41:00+01:00") == date("2026-11-13T08:41:00Z"), "dates ISO avec et sans fractions de seconde, avec fuseau")
    verifier(ReponseHTTP.date("2026-11-13", fuseau: paris) == date("2026-11-12T23:00:00Z") && ReponseHTTP.date("13/11/2026") == nil && ReponseHTTP.date("") == nil,
             "un jour seul : minuit dans le fuseau ; un format inconnu : nil")
    verifier(ReponseHTTP.iso(date("2026-11-13T09:41:00Z")) == "2026-11-13T09:41:00.000Z", "le format des formules d'Airtable")
    verifier(ReponseHTTP.jour(date("2026-11-13T23:30:00Z"), fuseau: paris) == "2026-11-14", "le jour LOCAL (23 h 30 UTC = le 14 à Paris)")
    verifier(ReponseHTTP.erreur(.notion, statut: 401, code: "unauthorized", reessayer: nil) == .cleRefusee(.notion)
             && ReponseHTTP.erreur(.notion, statut: 403, code: "restricted_resource", reessayer: nil) == .introuvable(.notion)
             && ReponseHTTP.erreur(.airtable, statut: 403, code: "INVALID_PERMISSIONS_OR_MODEL_NOT_FOUND", reessayer: nil) == .droitsManquants(.airtable, "accès refusé")
             && ReponseHTTP.erreur(.notion, statut: 404, code: nil, reessayer: nil) == .introuvable(.notion)
             && ReponseHTTP.erreur(.airtable, statut: 429, code: nil, reessayer: nil) == .limite(.airtable, reessayerDans: 30)
             && ReponseHTTP.erreur(.notion, statut: 429, code: "rate_limited", reessayer: 3) == .limite(.notion, reessayerDans: 3)
             && ReponseHTTP.erreur(.notion, statut: 502, code: nil, reessayer: nil) == .serveur(.notion, 502)
             && ReponseHTTP.erreur(.notion, statut: 400, code: "validation_error", reessayer: nil) == .refus(.notion, 400),
             "chaque code a sa cause : 401 clé, 403 droits (Notion : base non partagée), 404, 429 (Airtable : 30 s), 5xx, autre")

    groupe("Tes apps : espacement des requêtes (limites de débit)")
    do {
        let h = HorlogeEssai(date("2026-11-13T10:00:00Z")), a = Attentes()
        let e = EspacementRequetes(ecart: ClientNotion.ecart, horloge: { h.t }, dormir: { a.noter($0) })
        await e.patienter(); await e.patienter(); await e.patienter()
        verifier(a.liste.count == 2 && abs(a.liste[0] - 0.34) < 0.001 && abs(a.liste[1] - 0.68) < 0.001, "trois requêtes d'affilée : 0, 0,34 puis 0,68 s d'attente (Notion : 3 par seconde)")
        h.avancer(5); await e.patienter()
        verifier(a.liste.count == 2, "après un moment sans requête : aucune attente")
        verifier(ClientAirtable.ecart >= 0.2, "Airtable : 5 par seconde au plus")
    }

    groupe("Tes apps : Notion (réponses d'exemple)")
    let cleNotion = "ntn_" + String(repeating: "E", count: 40)
    let cleAirtable = "patEssai0000000001." + String(repeating: "f", count: 40)
    verifier(ClientNotion.vraisemblable(cleNotion) && ClientNotion.vraisemblable("secret_" + String(repeating: "x", count: 40))
             && !ClientNotion.vraisemblable("ntn_court") && !ClientNotion.vraisemblable("ntn_" + String(repeating: "x", count: 20) + " " + String(repeating: "x", count: 20))
             && !ClientNotion.vraisemblable(cleAirtable), "forme d'une clé Notion (ntn_ ou secret_, longue, sans espace)")
    verifier(ClientNotion.identifiantPropre("0f0e0d0c-1111/../x?y") == "0f0e0d0c-1111", "un identifiant n'apporte jamais « / », « .. » ni « ? » dans une adresse")
    let schema = ClientNotion.analyserSchema(ReponseHTTP.objet(Data(ExemplesApps.notionSchema.utf8))!)
    verifier(schema == ReglageNotion(baseId: "0f0e0d0c-1111-4222-8333-444455556666", baseNom: "Tâches de l'équipe", proprieteDate: "Créée", proprietePersonne: "Assigné à"),
             "schéma : le nom, la première propriété date (ordre alphabétique : stable), la propriété personne (\(String(describing: schema)))")
    verifier(ClientNotion.analyserBases(ReponseHTTP.objet(Data(ExemplesApps.notionBases.utf8))!)
             == [ChoixApp(id: "0f0e0d0c-1111-4222-8333-444455556666", nom: "Tâches de l'équipe"), ChoixApp(id: "aaaabbbb-1111-4222-8333-444455556666", nom: "Sans titre")],
             "les bases partagées (une page n'en est pas une ; sans titre : « Sans titre »)")
    verifier(ClientNotion.analyserPersonnes(ReponseHTTP.objet(Data(ExemplesApps.notionPersonnes.utf8))!) == [ChoixApp(id: "11111111-2222-4333-8444-555555555555", nom: "Camille Essai")],
             "les personnes (pas les intégrations)")
    var rn = ReglageNotion(baseId: "0f0e0d0c-1111-4222-8333-444455556666", baseNom: "Tâches", proprieteDate: "Échéance", proprietePersonne: "Assigné à")
    verifier(rn.complet && ClientNotion.filtre(ReglageNotion(baseId: "x", baseNom: "x"), jour: "2026-11-13") == nil && !ReglageNotion(baseId: "x", baseNom: "x", proprietePersonne: "A").complet,
             "rien à filtrer (ni date, ni personne choisie) : pas de requête")
    let f1 = ClientNotion.filtre(rn, jour: "2026-11-13")!
    verifier((f1["filter"] as? [String: Any])?["property"] as? String == "Échéance" && ((f1["filter"] as? [String: Any])?["date"] as? [String: String])?["equals"] == "2026-11-13",
             "sans personne choisie : seulement « échéance = aujourd'hui »")
    rn.personneId = "11111111-2222-4333-8444-555555555555"
    let f2 = ClientNotion.filtre(rn, jour: "2026-11-13")!
    let ou = ((f2["filter"] as? [String: Any])?["or"] as? [[String: Any]]) ?? []
    verifier(ou.count == 2 && (ou[1]["people"] as? [String: String])?["contains"] == rn.personneId && f2["page_size"] as? Int == 25,
             "avec la personne : « aujourd'hui » OU « assignée », triées par modification, 25 au plus")
    let pagesJSON = ExemplesApps.notionPages([
        (id: "p1000000-0000-4000-8000-000000000001", titre: "Relancer le devis", echeance: "2026-11-13", modif: "2026-11-13T08:00:00.000Z", archivee: false),
        (id: "p2000000-0000-4000-8000-000000000002", titre: "Appel fournisseur", echeance: "2026-11-13T13:30:00.000+01:00", modif: "2026-11-12T08:00:00.000Z", archivee: false),
        (id: "p3000000-0000-4000-8000-000000000003", titre: "Préparer la démo", echeance: "2026-11-13T23:30:00.000Z", modif: "2026-11-11T08:00:00.000Z", archivee: false),
        (id: "p4000000-0000-4000-8000-000000000004", titre: "Ancienne", echeance: nil, modif: "2026-11-10T08:00:00.000Z", archivee: true),
    ])
    let pages = ClientNotion.analyserPages(ReponseHTTP.objet(Data(pagesJSON.utf8))!, reglage: rn, jour: "2026-11-13", fuseau: paris) ?? []
    verifier(pages.map(\.titre) == ["Relancer le devis", "Appel fournisseur", "Préparer la démo"], "les pages, sans l'archivée")
    verifier(pages.map(\.duJour) == [true, true, false] && pages.map(\.avecHeure) == [false, true, true],
             "« du jour » se juge au jour LOCAL (23 h 30 UTC, c'est demain à Paris : arrivée par la personne)")
    let heureParis: (Date) -> String = { d in var c = Calendar(identifier: .gregorian); c.timeZone = paris; return FormatIlot.heure(d, calendrier: c) }
    let n2 = ClientNotion.nouveaute(pages[1], jour: "2026-11-13", heure: heureParis)
    verifier(n2.id == "notion:p2000000-0000-4000-8000-000000000002@2026-11-13" && n2.sousTitre == "Aujourd\u{2019}hui \u{00B7} 13:30"
             && n2.action == .adresse(URL(string: "https://www.notion.so/Page-p2000000000040008000000000000002")!),
             "nouveauté Notion : clé page + jour, « Aujourd'hui · 13:30 », la page s'ouvre (\(n2.sousTitre))")
    verifier(ClientNotion.nouveaute(pages[0], jour: "2026-11-13", heure: heureParis).sousTitre == "Aujourd\u{2019}hui"
             && ClientNotion.nouveaute(pages[2], jour: "2026-11-13", heure: heureParis).sousTitre == "Assignée à toi", "jour sans heure ; assignée")
    verifier(ClientNotion.nouveaute(pages[2], jour: "2026-11-13", heure: heureParis).id == "notion:p3000000-0000-4000-8000-000000000003"
             && ClientNotion.nouveaute(pages[2], jour: "2026-11-14", heure: heureParis).id == ClientNotion.nouveaute(pages[2], jour: "2026-11-13", heure: heureParis).id,
             "une tâche seulement assignée : la même clé chaque jour (annoncée une fois)")
    verifier(ClientNotion.analyserPages(["object": "error"], reglage: rn, jour: "2026-11-13") == nil, "une réponse qui n'est pas une liste : nil (dite illisible)")
    do {
        let reseau = FauxReseau()
        let c = ClientNotion(cle: cleNotion, transport: reseau, espacement: EspacementRequetes(ecart: 0), fuseau: paris)
        reseau.repondre("GET https://api.notion.com/v1/users/me", .init(corps: ExemplesApps.notionMoi))
        let nom = try? await c.verifier()
        let r0 = reseau.requetes.first
        verifier(nom == "Espace Essai" && r0?.value(forHTTPHeaderField: "Authorization") == "Bearer \(cleNotion)"
                 && r0?.value(forHTTPHeaderField: "Notion-Version") == "2022-06-28", "vérifier la clé : /users/me, avec la clé en en-tête et la version de l'API")
        reseau.repondre("POST https://api.notion.com/v1/databases/0f0e0d0c-1111-4222-8333-444455556666/query", .init(corps: pagesJSON))
        let lues = try? await c.taches(rn, maintenant: date("2026-11-13T09:00:00Z"))
        let corps = reseau.requetes.last?.httpBody.flatMap { ReponseHTTP.objet($0) }
        verifier(lues?.count == 3 && reseau.requetes.last?.httpMethod == "POST" && corps?["page_size"] as? Int == 25, "lire les tâches : POST databases/…/query")
        func erreur(_ r: FauxReseau.Reponse) async -> ErreurApp? {
            reseau.repondre("GET https://api.notion.com/v1/users/me", r)
            do { _ = try await c.verifier(); return nil } catch { return error }
        }
        let e401 = await erreur(.init(statut: 401, corps: #"{"object":"error","status":401,"code":"unauthorized","message":"API token is invalid."}"#))
        let e429 = await erreur(.init(statut: 429, entetes: ["Retry-After": "2"], corps: #"{"code":"rate_limited"}"#))
        let ePanne = await erreur(.init(panne: true))
        let eTexte = await erreur(.init(corps: "<html>"))
        let e503 = await erreur(.init(statut: 503, corps: "Service Unavailable"))
        verifier(e401 == .cleRefusee(.notion) && e429 == .limite(.notion, reessayerDans: 2) && ePanne == .reseau(.notion) && eTexte == .reponseIllisible(.notion)
                 && e503 == .serveur(.notion, 503), "erreurs : clé refusée, limite (Retry-After), pas de réseau, réponse illisible, serveur")
        verifier(e401.map { !$0.texte.contains(cleNotion) && !$0.texte.contains("API token") } == true, "le message dit la cause, jamais la clé ni le texte reçu")
    }

    groupe("Tes apps : Airtable (réponses d'exemple)")
    verifier(ClientAirtable.vraisemblable(cleAirtable) && !ClientAirtable.vraisemblable("patcourt.x") && !ClientAirtable.vraisemblable("key" + String(repeating: "x", count: 40)),
             "forme d'un jeton d'accès personnel (pat….…)")
    let tables = ClientAirtable.analyserTables(ReponseHTTP.objet(Data(ExemplesApps.airtableTables.utf8))!)
    verifier(tables == [TableAirtable(id: "tblEssai00000001", nom: "Contacts", champTitre: "fldNom000000001", champModification: "fldModif00000001"),
                        TableAirtable(id: "tblEssai00000002", nom: "Notes", champTitre: "fldTitre0000001", champModification: nil)],
             "les tables : le champ principal, et le champ « Dernière modification » s'il existe")
    verifier(ClientAirtable.analyserBases(ReponseHTTP.objet(Data(ExemplesApps.airtableBases.utf8))!) == [ChoixApp(id: "appEssai00000001", nom: "Suivi des ventes")], "les bases")
    verifier(ClientAirtable.droitsManquants(ReponseHTTP.objet(Data(ExemplesApps.airtableMoiSansSchema.utf8))!) == "schema.bases:read"
             && ClientAirtable.droitsManquants(ReponseHTTP.objet(Data(ExemplesApps.airtableMoi.utf8))!) == nil, "les droits manquants du jeton")
    let ra = ReglageAirtable(baseId: "appEssai00000001", baseNom: "Suivi", tableId: "tblEssai00000001", tableNom: "Contacts", champTitre: "fldNom000000001", champModification: "fldModif00000001")
    let adr = ClientAirtable.adresseModifiees(ra, depuis: date("2026-11-13T09:00:00Z"))
    let items = URLComponents(url: adr, resolvingAgainstBaseURL: false)?.queryItems ?? []
    verifier(adr.absoluteString.hasPrefix("https://api.airtable.com/v0/appEssai00000001/tblEssai00000001?")
             && items.first { $0.name == "filterByFormula" }?.value == "IS_AFTER(LAST_MODIFIED_TIME(), DATETIME_PARSE('2026-11-13T09:00:00.000Z'))"
             && items.first { $0.name == "returnFieldsByFieldId" }?.value == "true" && items.first { $0.name == "sort[0][field]" }?.value == "fldModif00000001"
             && !adr.absoluteString.contains(" "), "l'adresse : la formule « modifiée après », 20 fiches, champs par identifiant, tri par la modification")
    let adrPlus = ClientAirtable.adresseModifiees(ReglageAirtable(baseId: "app+1", baseNom: "", tableId: "tbl/../x", tableNom: ""), depuis: Date(timeIntervalSince1970: 0))
    verifier(adrPlus.path == "/v0/app1/tblx" && !adrPlus.absoluteString.contains("sort"), "identifiants nettoyés ; sans champ de modification, pas de tri")
    let fichesJSON = ExemplesApps.airtableFiches([(id: "recEssai0000001", nom: "Atelier Lumière", modif: "2026-11-13T09:30:00.000Z"), (id: "recEssai0000002", nom: "", modif: nil)])
    let fiches = ClientAirtable.analyserFiches(ReponseHTTP.objet(Data(fichesJSON.utf8))!, reglage: ra) ?? []
    verifier(fiches == [FicheAirtable(id: "recEssai0000001", titre: "Atelier Lumière", modifiee: date("2026-11-13T09:30:00Z")),
                        FicheAirtable(id: "recEssai0000002", titre: "Fiche sans nom", modifiee: nil)], "les fiches : nom (champ principal), heure de modification")
    var rb = ra; rb.champTitre = "fldListe"
    let liste = ReponseHTTP.objet(Data(#"{"records":[{"id":"r1","fields":{"fldListe":["Un",{"name":"Camille Essai"},3]}}]}"#.utf8))!
    verifier(ClientAirtable.analyserFiches(liste, reglage: rb)?.first?.titre == "Un, Camille Essai, 3",
             "un champ principal en liste, collaborateur ou nombre devient une ligne")
    let na = ClientAirtable.nouveaute(fiches[0], reglage: ra, fenetre: date("2026-11-13T09:00:00Z"), vue: date("2026-11-13T09:31:00Z"))
    let nb = ClientAirtable.nouveaute(fiches[1], reglage: ra, fenetre: date("2026-11-13T09:00:00Z"), vue: date("2026-11-13T09:31:00Z"))
    verifier(na.id == "airtable:recEssai0000001@2026-11-13T09:30:00.000Z" && nb.id == "airtable:recEssai0000002@2026-11-13T09:00:00.000Z"
             && na.action == .adresse(URL(string: "https://airtable.com/appEssai00000001/tblEssai00000001/recEssai0000001")!) && nb.date == date("2026-11-13T09:31:00Z"),
             "clé : fiche + heure de SA modification (sans le champ : la fenêtre) ; la fiche s'ouvre dans Airtable")
    do {
        let reseau = FauxReseau()
        let c = ClientAirtable(cle: cleAirtable, transport: reseau, espacement: EspacementRequetes(ecart: 0))
        reseau.repondre("GET https://api.airtable.com/v0/meta/whoami", .init(corps: ExemplesApps.airtableMoiSansSchema))
        var e: ErreurApp?
        do { _ = try await c.verifier() } catch { e = error }
        verifier(e == .droitsManquants(.airtable, "schema.bases:read") && reseau.requetes.first?.value(forHTTPHeaderField: "Authorization") == "Bearer \(cleAirtable)",
                 "vérifier le jeton : /meta/whoami ; un droit manque, c'est dit")
        reseau.repondre("GET https://api.airtable.com/v0/appEssai00000001/tblEssai00000001", .init(entetes: ["Date": "Fri, 13 Nov 2026 09:31:00 GMT"], corps: fichesJSON))
        let m = try? await c.modifiees(ra, depuis: date("2026-11-13T09:00:00Z"))
        verifier(m?.fiches.count == 2 && m?.serveur == date("2026-11-13T09:31:00Z"), "les fiches modifiées, et l'heure d'Airtable pour la fenêtre suivante")
        reseau.repondre("GET https://api.airtable.com/v0/appEssai00000001/tblEssai00000001", .init(statut: 429, corps: #"{"errors":[{"error":"RATE_LIMIT_REACHED"}]}"#))
        do { _ = try await c.modifiees(ra, depuis: date("2026-11-13T09:00:00Z")); e = nil } catch { e = error }
        verifier(e == .limite(.airtable, reessayerDans: 30), "429 sans Retry-After : Airtable demande 30 s")
    }

    groupe("Tes apps : Mail (script et sortie, jamais la vraie Mail)")
    let script = ScriptMail.texte(depuisSecondes: 3600, max: 30)
    verifier(script.contains("messages of inbox whose read status is false and date received > seuil") && script.contains("set seuil to maintenant - 3600")
             && script.contains("if n > 30 then exit repeat") && script.contains("with timeout of 15 seconds"),
             "le script : non lus de la boîte de réception, depuis la fenêtre, 30 au plus, 15 s au plus")
    verifier(script.range(of: "current date")!.lowerBound < script.range(of: "tell application")!.lowerBound && !script.contains("content of"),
             "l'heure est prise hors du bloc Mail ; le contenu des mails n'est jamais lu")
    verifier(ScriptMail.texte(depuisSecondes: 5, max: 0).contains("maintenant - 60") && ScriptMail.texte(depuisSecondes: 5, max: 0).contains("if n > 1 then"), "bornes : 60 s et 1 mail au moins")
    let t0 = date("2026-11-13T10:00:00Z")
    let sortie = "<id-1@exemple.fr>\u{1F}Camille Martin <camille@exemple.fr>\u{1F}Devis\nsignée\u{1F}-120\u{1E}"
        + "id-2@exemple.fr\u{1F}\"Martin, Paul\" <paul@exemple.fr>\u{1F}Re: planning\u{1F}-30\u{1E}"
        + "abîmée\u{1F}sans date\u{1E}id-3\u{1F}x\u{1F}y\u{1F}pas un nombre\u{1E}"
        + "id-4@exemple.fr\u{1F}alerte@exemple.fr\u{1F}\u{1F}-3600\u{1E}"
    let lus = ScriptMail.analyser(sortie, maintenant: t0)
    verifier(lus.map(\.id) == ["id-2@exemple.fr", "id-1@exemple.fr", "id-4@exemple.fr"] && lus.map(\.expediteur) == ["Martin, Paul", "Camille Martin", "alerte@exemple.fr"]
             && lus[1].objet == "Devis signée" && lus[1].recu == t0.addingTimeInterval(-120), "la sortie : les fiches bien formées, les plus récentes d'abord ; noms lisibles")
    verifier(ScriptMail.analyser("", maintenant: t0).isEmpty, "aucun non lu : rien")
    verifier(ScriptMail.erreur(code: -1743) == .autorisationMail && ScriptMail.erreur(code: -600) == .mailFerme && ScriptMail.erreur(code: -1712) == .mail(-1712),
             "codes d'AppleScript : Automatisation refusée, Mail fermé, trop long")
    let nm = ScriptMail.nouveaute(lus[2])
    verifier(nm.id == "mail:id-4@exemple.fr" && nm.sousTitre == "(sans objet)" && nm.action == .messageMail(id: "id-4@exemple.fr"), "nouveauté Mail : expéditeur, objet, ouvrir dans Mail")

    groupe("Tes apps : Agenda (ce que l'îlot lit déjà)")
    let rdv = [EvenementAgenda(id: "e1@1", titre: "Point hebdo", debut: t0.addingTimeInterval(1800), fin: t0.addingTimeInterval(3600), lien: URL(string: "https://meet.google.com/abc-defg-hij")),
               EvenementAgenda(id: "e2@2", titre: "Déjeuner", debut: t0.addingTimeInterval(7200), fin: t0.addingTimeInterval(9000), lieu: "Café du coin"),
               EvenementAgenda(id: "e0@0", titre: "Toute la journée", debut: t0, fin: t0.addingTimeInterval(86_400), toutelaJournee: true)]
    let na1 = AgendaApps.nouveaute(rdv, maintenant: t0, heure: heureParis)
    verifier(na1 == Nouveaute(id: "agenda:e1@1", app: .agenda, titre: "Point hebdo", sousTitre: "11:30 \u{00B7} Google Meet", date: t0.addingTimeInterval(1800),
                              action: .adresse(URL(string: "https://meet.google.com/abc-defg-hij")!)), "le prochain rendez-vous (PlanAgenda.prochain), sa visio en un clic")
    verifier(AgendaApps.nouveaute(Array(rdv.dropFirst()), maintenant: t0, heure: heureParis)?.sousTitre == "13:00 \u{00B7} Café du coin"
             && AgendaApps.nouveaute(Array(rdv.dropFirst()), maintenant: t0, heure: heureParis)?.action == .rendezVous(id: "e2@2"), "sans visio : le lieu, et le rendez-vous s'ouvre")
    verifier(AgendaApps.nouveaute([EvenementAgenda(id: "loin", titre: "Demain", debut: t0.addingTimeInterval(13 * 3600), fin: t0.addingTimeInterval(14 * 3600))], maintenant: t0, heure: heureParis) == nil,
             "au-delà de 12 h : rien")

    groupe("Tes apps : mémoire de ce qui est vu (dédoublonnage)")
    func n(_ id: String, _ app: AppBranchee = .mail) -> Nouveaute { Nouveaute(id: "\(app.rawValue):\(id)", app: app, titre: id, sousTitre: "", date: t0, action: .messageMail(id: id)) }
    var mem = MemoireApps()
    verifier(mem.retenir([n("a"), n("b")], app: .mail, maintenant: t0).isEmpty && mem.vues.count == 2, "premier passage : tout est retenu, rien n'est annoncé")
    verifier(mem.retenir([n("a"), n("b"), n("c"), n("c")], app: .mail, maintenant: t0).map(\.id) == ["mail:c"], "ensuite : seulement le nouveau, une seule fois même en double")
    verifier(mem.retenir([n("a"), n("c")], app: .mail, maintenant: t0).isEmpty, "rien de nouveau : rien")
    verifier(mem.retenir([n("x", .notion)], app: .notion, maintenant: t0).isEmpty, "chaque app a son premier passage")
    var vieille = MemoireApps(); vieille.amorcees = [.mail]
    _ = vieille.retenir([n("ancien")], app: .mail, maintenant: t0)
    _ = vieille.retenir([], app: .mail, maintenant: t0.addingTimeInterval(MemoireApps.garde + 1))
    verifier(vieille.vues.isEmpty, "une clé vue est oubliée après 30 jours sans être revue")
    var revue = MemoireApps(); revue.amorcees = [.notion]
    _ = revue.retenir([n("t", .notion)], app: .notion, maintenant: t0)
    _ = revue.retenir([n("t", .notion)], app: .notion, maintenant: t0.addingTimeInterval(20 * 86_400))
    verifier(revue.retenir([n("t", .notion)], app: .notion, maintenant: t0.addingTimeInterval(40 * 86_400)).isEmpty,
             "revue entre-temps (tâche toujours assignée) : jamais réannoncée, même après 40 jours")
    var pleine = MemoireApps(); pleine.amorcees = [.mail]
    _ = pleine.retenir((0..<(MemoireApps.maxVues + 10)).map { n("m\($0)") }, app: .mail, maintenant: t0)
    verifier(pleine.vues.count == MemoireApps.maxVues, "\(MemoireApps.maxVues) clés au plus")
    mem.notion = rn; mem.branchees = [.mail, .notion]; mem.mailDernier = t0
    mem.oublier(.notion)
    verifier(mem.notion == nil && !mem.branchees.contains(.notion) && !mem.amorcees.contains(.notion) && mem.vues.keys.allSatisfy { !$0.hasPrefix("notion:") } && mem.vues["mail:a"] != nil,
             "débrancher Notion oublie son réglage et ses clés vues, pas celles de Mail")
    verifier(MemoireApps().fenetreMail(maintenant: t0) == 2 * 86_400 && mem.fenetreMail(maintenant: t0.addingTimeInterval(60)) == 180
             && mem.fenetreMail(maintenant: t0.addingTimeInterval(10 * 86_400)) == 2 * 86_400, "fenêtre de Mail : 2 jours d'abord, puis depuis le dernier passage + 2 min, 2 jours au plus")
    let relue = MemoireApps.depuis(mem.donnees()!)
    verifier(relue == mem, "apps.json se relit à l'identique")

    groupe("Tes apps : rythme des sondages")
    var plan = PlanSondages()
    verifier(plan.aSonder(t0, branchees: [.notion, .mail]) == [.mail, .notion], "branchées, jamais sondées : tout de suite")
    plan.reussi(.mail, t0, duree: 0.05); plan.reussi(.notion, t0)
    verifier(plan.aSonder(t0.addingTimeInterval(59), branchees: [.notion, .mail]).isEmpty && plan.aSonder(t0.addingTimeInterval(60), branchees: [.notion, .mail]) == [.mail]
             && plan.aSonder(t0.addingTimeInterval(180), branchees: [.notion, .mail]) == [.mail, .notion], "Mail chaque minute, Notion toutes les 3 min")
    plan.reussi(.mail, t0, duree: 4)
    verifier(plan.suivis[.mail]?.prochain == t0.addingTimeInterval(120), "un passage dans Mail de 4 s : le suivant dans 2 min (30 × le coût)")
    plan.echoue(.notion, t0, .reseau(.notion)); let p1 = plan.suivis[.notion]!.prochain
    plan.echoue(.notion, t0, .serveur(.notion, 502)); let p2 = plan.suivis[.notion]!.prochain
    for _ in 0..<10 { plan.echoue(.notion, t0, .reseau(.notion)) }
    verifier(p1 == t0.addingTimeInterval(180) && p2 == t0.addingTimeInterval(360) && plan.suivis[.notion]!.prochain == t0.addingTimeInterval(1800),
             "erreurs : l'attente double, 30 min au plus")
    plan.reussi(.notion, t0)
    verifier(plan.suivis[.notion]?.echecs == 0, "un succès remet le compteur à zéro")
    plan.echoue(.airtable, t0, .limite(.airtable, reessayerDans: 600))
    verifier(plan.suivis[.airtable]?.prochain == t0.addingTimeInterval(600), "une limite de débit est respectée à la seconde")
    plan.echoue(.notion, t0, .cleRefusee(.notion))
    verifier(plan.aSonder(t0.addingTimeInterval(86_400), branchees: [.notion]).isEmpty && plan.prochain(branchees: [.notion], apres: t0) == nil,
             "clé refusée : plus jamais sondée, jusqu'à un geste")
    plan.maintenant(.notion, t0)
    verifier(plan.aSonder(t0, branchees: [.notion]) == [.notion], "le geste (nouvelle clé, « Réessayer ») la relance")
    verifier(plan.prochain(branchees: [], apres: t0) == nil, "rien de branché : aucune minuterie")

    groupe("Tes apps : la façade, de bout en bout (faux réseau, faux Mail, coffre en mémoire)")
    let fm = FileManager.default
    let dossier = fm.temporaryDirectory.appendingPathComponent("voxile-apps-\(UUID().uuidString)", isDirectory: true)
    try? fm.createDirectory(at: dossier, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: dossier) }
    let fichier = dossier.appendingPathComponent("apps.json")
    let horloge = HorlogeEssai(date("2026-11-13T08:00:00Z"))
    let reseau = FauxReseau(), mail = FauxMail(), coffre = CoffreEnMemoire()
    var journal: [String] = [], annonces: [[Nouveaute]] = []
    var rendezVous: [EvenementAgenda] = []
    func fabriquer() -> AppsBranchees {
        let a = AppsBranchees(magasin: MagasinJSON(url: fichier, nom: "apps"), coffre: coffre, transport: reseau, mail: mail, agenda: { rendezVous },
                              horloge: { horloge.t }, heure: heureParis, journal: { journal.append($0) },
                              espacementNotion: EspacementRequetes(ecart: 0), espacementAirtable: EspacementRequetes(ecart: 0))
        a.surNouveautes = { annonces.append($0) }
        return a
    }
    var apps = fabriquer()
    verifier(apps.prochainSondage() == nil && AppBranchee.allCases.allSatisfy { apps.etats[$0] == .debranchee }, "rien de branché : rien à sonder")
    apps.brancher(.notion)
    verifier(!apps.estBranchee(.notion) && apps.etats[.notion] == .erreur(.cleAbsente(.notion)), "Notion sans clé : pas branché, « Colle ta clé »")
    let avant = reseau.requetes.count
    let mauvaise = await apps.enregistrerCle("ntn_court", pour: .notion)
    verifier(mauvaise == .failure(.cleRefusee(.notion)) && reseau.requetes.count == avant && coffre.lire(.notion) == nil, "une clé de mauvaise forme : refusée sans rien envoyer")
    reseau.repondre("GET https://api.notion.com/v1/users/me", .init(statut: 401, corps: #"{"code":"unauthorized"}"#))
    let refusee = await apps.enregistrerCle(cleNotion, pour: .notion)
    verifier(refusee == .failure(.cleRefusee(.notion)) && coffre.lire(.notion) == nil, "une clé que Notion refuse n'est pas gardée")
    reseau.repondre("GET https://api.notion.com/v1/users/me", .init(corps: ExemplesApps.notionMoi))
    let acceptee = await apps.enregistrerCle("  \(cleNotion)\n", pour: .notion)
    verifier(acceptee == .success("Espace Essai") && coffre.lire(.notion) == cleNotion, "vérifiée, puis rangée dans le coffre (espaces retirés)")
    reseau.repondre("POST https://api.notion.com/v1/search", .init(corps: ExemplesApps.notionBases))
    reseau.repondre("GET https://api.notion.com/v1/users?", .init(corps: ExemplesApps.notionPersonnes))
    reseau.repondre("GET https://api.notion.com/v1/databases/0f0e0d0c", .init(corps: ExemplesApps.notionSchema))
    let bases = await apps.basesNotion(), gens = await apps.personnesNotion()
    verifier((try? bases.get())?.count == 2 && (try? gens.get())?.count == 1, "les bases et les personnes, pour le choix")
    let choix = await apps.choisirBaseNotion("0f0e0d0c-1111-4222-8333-444455556666")
    verifier((try? choix.get())?.proprieteDate == "Créée" && apps.estBranchee(.notion) && apps.etats[.notion] == .enAttente, "la base choisie : Notion branché")
    apps.choisirPersonneNotion("11111111-2222-4333-8444-555555555555")
    reseau.repondre("POST https://api.notion.com/v1/databases/0f0e0d0c-1111-4222-8333-444455556666/query", .init(corps: pagesJSON))
    var nouvelles = await apps.sonder()
    verifier(nouvelles.isEmpty && apps.actuelles[.notion]?.count == 3 && annonces.isEmpty && apps.etats[.notion] == .aJour(horloge.t),
             "premier passage : 3 tâches montrées, rien d'annoncé")
    verifier(await apps.sonder().isEmpty, "trop tôt : rien n'est sondé")
    horloge.avancer(180)
    let pagesPlus = ExemplesApps.notionPages([(id: "p5000000-0000-4000-8000-000000000005", titre: "Nouvelle tâche", echeance: "2026-11-13", modif: "2026-11-13T08:02:00.000Z", archivee: false)])
    let plus = String(pagesJSON.dropLast(#"],"has_more":false}"#.count)) + "," + String(pagesPlus.dropFirst(#"{"object":"list","results":["#.count))
    reseau.repondre("POST https://api.notion.com/v1/databases/0f0e0d0c-1111-4222-8333-444455556666/query", .init(corps: plus))
    nouvelles = await apps.sonder()
    verifier(nouvelles.map(\.titre) == ["Nouvelle tâche"] && annonces.count == 1 && apps.actuelles[.notion]?.count == 4, "3 min plus tard : la nouvelle tâche, annoncée une fois")
    horloge.avancer(180)
    verifier(await apps.sonder().isEmpty && annonces.count == 1, "la même liste : rien de plus (jamais deux fois)")

    // Mail
    mail.ouvert = false
    apps.brancher(.mail)
    verifier(await apps.sonder().isEmpty && mail.appels.isEmpty && apps.etats[.mail] == .enPause, "Mail fermé : jamais sondé (aucun script), « en pause »")
    mail.ouvert = true
    mail.messages = [MessageMail(id: "m1@exemple.fr", expediteur: "Camille Martin", objet: "Devis", recu: horloge.t.addingTimeInterval(-600))]
    horloge.avancer(60)
    _ = await apps.sonder()
    verifier(mail.appels == [2 * 86_400] && apps.actuelles[.mail]?.count == 1 && annonces.count == 1, "Mail ouvert : premier passage sur 2 jours, montré sans annonce")
    mail.messages.insert(MessageMail(id: "m2@exemple.fr", expediteur: "Paul", objet: "Planning", recu: horloge.t), at: 0)
    horloge.avancer(60)
    nouvelles = await apps.sonder()
    verifier(nouvelles.map(\.id) == ["mail:m2@exemple.fr"] && mail.appels.last == 180, "un nouveau mail : annoncé une fois ; fenêtre = depuis le dernier passage + 2 min")
    mail.erreur = .autorisationMail
    horloge.avancer(60)
    _ = await apps.sonder()
    verifier(apps.etats[.mail] == .erreur(.autorisationMail) && apps.plan.suivis[.mail]?.arrete == true, "Automatisation refusée : dit, et plus de sondage jusqu'à un geste")
    mail.erreur = nil
    _ = await apps.sonder(force: true)
    verifier(apps.etats[.mail].map { (e: EtatApp) -> Bool in if case .aJour = e { return true }; return false } == true, "« Réessayer » (force) : relu")

    // Agenda
    rendezVous = [EvenementAgenda(id: "r1@1", titre: "Point hebdo", debut: horloge.t.addingTimeInterval(1800), fin: horloge.t.addingTimeInterval(3600))]
    apps.brancher(.agenda)
    _ = await apps.sonder()
    verifier(apps.actuelles[.agenda]?.first?.titre == "Point hebdo", "Agenda : le prochain rendez-vous, lu par l'îlot (aucune autre lecture du calendrier)")

    // Airtable
    reseau.repondre("GET https://api.airtable.com/v0/meta/whoami", .init(corps: ExemplesApps.airtableMoi))
    let okA = await apps.enregistrerCle(cleAirtable, pour: .airtable)
    reseau.repondre("GET https://api.airtable.com/v0/meta/bases", .init(corps: ExemplesApps.airtableBases))
    reseau.repondre("GET https://api.airtable.com/v0/meta/bases/appEssai00000001/tables", .init(corps: ExemplesApps.airtableTables))
    let basesA = (try? await apps.basesAirtable().get()) ?? []
    let tablesA = (try? await apps.tablesAirtable(base: "appEssai00000001").get()) ?? []
    verifier(okA == .success("Airtable") && basesA.count == 1 && tablesA.count == 2, "Airtable : jeton vérifié, bases et tables proposées")
    apps.choisirTableAirtable(base: basesA[0], table: tablesA[0])
    reseau.repondre("GET https://api.airtable.com/v0/appEssai00000001/tblEssai00000001?", .init(entetes: ["Date": "Fri, 13 Nov 2026 08:09:00 GMT"], corps: fichesJSON))
    reseau.oublierRequetes()
    _ = await apps.sonder()
    let premiere = reseau.requetes.first { $0.url?.path.hasSuffix("tblEssai00000001") == true }?.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "filterByFormula" }?.value }
    verifier(premiere?.contains("2026-11-12T08:09:00.000Z") == true && apps.memoire.airtableDepuis == date("2026-11-13T08:09:00Z") && apps.actuelles[.airtable]?.count == 2,
             "premier passage : les fiches des dernières 24 h, montrées ; la fenêtre suivante part de l'heure d'Airtable (\(premiere ?? "?"))")
    horloge.avancer(180)
    reseau.repondre("GET https://api.airtable.com/v0/appEssai00000001/tblEssai00000001?", .init(entetes: ["Date": "Fri, 13 Nov 2026 08:12:00 GMT"],
        corps: ExemplesApps.airtableFiches([(id: "recEssai0000001", nom: "Atelier Lumière", modif: "2026-11-13T08:11:00.000Z")])))
    reseau.oublierRequetes()
    nouvelles = await apps.sonder()
    let seconde = reseau.requetes.first { $0.url?.path.hasSuffix("tblEssai00000001") == true }?.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "filterByFormula" }?.value }
    verifier(seconde?.contains("2026-11-13T08:09:00.000Z") == true && nouvelles.map(\.id) == ["airtable:recEssai0000001@2026-11-13T08:11:00.000Z"]
             && apps.actuelles[.airtable]?.count == 3, "une fiche modifiée de nouveau : une autre nouveauté, annoncée ; la fenêtre suit sans trou (\(seconde ?? "?"), \(nouvelles.map(\.id)), \(apps.actuelles[.airtable]?.count ?? 0))")
    horloge.avancer(180)
    reseau.repondre("GET https://api.airtable.com/v0/appEssai00000001/tblEssai00000001?", .init(statut: 429, corps: "{}"))
    _ = await apps.sonder()
    verifier(apps.etats[.airtable] == .erreur(.limite(.airtable, reessayerDans: 30)) && apps.plan.suivis[.airtable]?.prochain == horloge.t.addingTimeInterval(180)
             && apps.memoire.airtableDepuis == date("2026-11-13T08:12:00Z"), "429 : l'attente respecte la limite, la fenêtre ne bouge pas (rien de perdu)")

    // relancer Voxile : la mémoire est relue, rien n'est réannoncé
    let annoncesAvant = annonces.count
    apps = fabriquer()
    verifier(apps.estBranchee(.notion) && apps.estBranchee(.mail) && apps.estBranchee(.airtable) && apps.memoire.notion?.personneId != nil, "relancé : tout est encore branché et réglé")
    reseau.repondre("POST https://api.notion.com/v1/databases/0f0e0d0c-1111-4222-8333-444455556666/query", .init(corps: plus))
    _ = await apps.sonder(force: true)
    verifier(annonces.count == annoncesAvant, "relancé : rien de déjà vu n'est réannoncé")

    // débrancher
    apps.debrancher(.notion)
    verifier(coffre.lire(.notion) == nil && apps.memoire.notion == nil && apps.actuelles[.notion] == nil && apps.etats[.notion] == .debranchee,
             "débrancher Notion : la clé quitte le coffre, le réglage est oublié")

    // jamais la clé ailleurs que dans l'en-tête
    let fichierTexte = (try? String(contentsOf: fichier, encoding: .utf8)) ?? ""
    let ailleurs = reseau.requetes.contains { r in
        [r.url?.absoluteString ?? "", r.httpBody.map { String(decoding: $0, as: UTF8.self) } ?? ""].contains { $0.contains(cleNotion) || $0.contains(cleAirtable) }
    }
    verifier(!fichierTexte.isEmpty && !fichierTexte.contains(cleNotion) && !fichierTexte.contains(cleAirtable) && !fichierTexte.contains("patEssai"),
             "apps.json ne contient aucune clé")
    verifier(!journal.isEmpty && journal.allSatisfy { !$0.contains(cleNotion) && !$0.contains(cleAirtable) && !$0.contains("patEssai") && !$0.contains("ntn_") },
             "le journal ne contient aucune clé (\(journal.count) lignes)")
    verifier(!ailleurs && reseau.requetes.allSatisfy { $0.url?.scheme == "https" }, "la clé ne voyage que dans l'en-tête, toujours en https")
    let attrs = try? fm.attributesOfItem(atPath: fichier.path)
    verifier((attrs?[.posixPermissions] as? Int) == 0o600, "apps.json en 0600")
}

// MARK: - l'interface de « Tes apps » dans l'îlot (logique pure : écrans, navigation, regroupement, hauteurs)

@MainActor
func controlesAppsIlot() {
    groupe("Tes apps : l'interface de l'îlot")
    let t = Date(timeIntervalSince1970: 1_794_560_000)
    func n(_ id: String, _ app: AppBranchee, _ titre: String, _ sous: String, _ s: TimeInterval) -> Nouveaute {
        Nouveaute(id: id, app: app, titre: titre, sousTitre: sous, date: t.addingTimeInterval(s), action: .messageMail(id: id))
    }

    // les écrans : des cartes rangées sous le Centre, l'aile et le bandeau sont des bandeaux ; « ‹ » mène où il dit
    verifier([VueIlot.apps, .appsDetail, .appsNouveautes].allSatisfy { CartesIlot.parent($0) == .centre && GeoIlot.aEpaules($0) && !$0.estBandeau },
             "Tes apps, le détail et les Nouveautés : des cartes sous le Centre (point du Centre allumé, épaules)")
    verifier(VueIlot.appsAile.estBandeau && VueIlot.appsBandeau.estBandeau && GeoIlot.ajusteAuContenu(.appsBandeau) && !GeoIlot.ajusteAuContenu(.appsAile),
             "l'aile et le bandeau se retirent seuls ; le bandeau épouse son contenu")
    verifier(NavigationIlot.parentFixe(.apps, premiere: nil) == .centre && NavigationIlot.parentFixe(.appsDetail, premiere: nil) == .apps
             && NavigationIlot.parentFixe(.appsNouveautes, premiere: .lectureEtendu) == .apps && NavigationIlot.nom(.apps) == "Tes apps",
             "« ‹ Centre » depuis Tes apps, « ‹ Tes apps » depuis le détail et les Nouveautés")
    verifier(NavigationIlot.retour(de: .appsNouveautes, pile: [.centre, .outils], premiere: .centre) == .apps, "le geste va où mène le « ‹ », pas à la pile")

    // le regroupement : une seule annonce, jamais une rafale
    var a = AnnonceApps([n("mail:1", .mail, "Camille Roche", "Devis cuisine", 0)])
    verifier(a.titre == "Camille Roche" && a.sousTitre == "Devis cuisine \u{00B7} Mail" && !a.ouvreLaListe && a.aile == ["1 mail", "1"],
             "une nouveauté : qui, quoi, l'app ; « Ouvrir » l'ouvre ; l'aile « 1 mail »")
    a.ajouter([n("mail:2", .mail, "Atelier Nord", "Facture", 10), n("mail:3", .mail, "Atelier Nord", "Relance", 20), n("mail:1", .mail, "Camille Roche", "Devis cuisine", 0)])
    verifier(a.elements.count == 3 && a.titre == "3 nouveaux mails" && a.sousTitre == "Atelier Nord, Camille Roche" && a.ouvreLaListe && a.aile.first == "3 mails",
             "trois mails (un en double) : « 3 nouveaux mails », les noms une fois chacun, « Ouvrir » ouvre la liste (\(a.sousTitre))")
    a.ajouter([n("notion:1", .notion, "Rappeler le menuisier", "Aujourd'hui", 30), n("airtable:1", .airtable, "Chantier Les Tilleuls", "Statut", 40)])
    verifier(a.titre == "5 nouveautés" && a.sousTitre == "3 mails, 1 tâche, 1 fiche" && a.apps == [.mail, .notion, .airtable],
             "plusieurs apps : « 5 nouveautés · 3 mails, 1 tâche, 1 fiche »")
    let deuxTaches = AnnonceApps([n("notion:1", .notion, "A", "x", 0), n("notion:2", .notion, "B", "y", 1)])
    verifier(deuxTaches.titre == "2 nouvelles tâches" && AnnonceApps([n("agenda:1", .agenda, "P", "x", 0), n("agenda:2", .agenda, "Q", "y", 1)]).titre == "2 nouveaux rendez-vous",
             "les accords : « 2 nouvelles tâches », « 2 nouveaux rendez-vous »")
    let quatre = AnnonceApps((1...4).map { n("mail:\($0)", .mail, "Nom \($0)", "o", Double($0)) })
    verifier(quatre.sousTitre == "Nom 4, Nom 3 et 2 autres", "plus de deux noms : « et 2 autres »")

    // la liste « Nouveautés » : bornée par sa hauteur, une ligne par app d'abord, puis les plus récentes
    var act: [AppBranchee: [Nouveaute]] = [:]
    act[.mail] = (1...10).map { n("mail:\($0)", .mail, "M\($0)", "o", Double($0)) }
    act[.notion] = (1...5).map { n("notion:\($0)", .notion, "T\($0)", "o", 100 + Double($0)) }
    act[.agenda] = [n("agenda:1", .agenda, "R", "o", 5000)]
    let s = PlanNouveautes.sections(act)
    verifier(s.map(\.app) == [.mail, .agenda, .notion] && PlanNouveautes.hauteur(s) <= PlanNouveautes.corpsMax
             && s.allSatisfy { !$0.lignes.isEmpty } && s.map { $0.lignes.count + $0.cachees } == [10, 1, 5],
             "Nouveautés : rangées par app, \(s.map(\.lignes.count)) lignes, \(Int(PlanNouveautes.hauteur(s))) pt ≤ \(Int(PlanNouveautes.corpsMax)), le reste compté « +N »")
    verifier(s.first { $0.app == .notion }?.lignes.first?.id == "notion:5", "les plus récentes d'abord")
    verifier(PlanNouveautes.sections([:]).isEmpty && PlanNouveautes.hauteur([]) == PlanNouveautes.corpsVide, "rien : la phrase « Rien de nouveau »")
    verifier(MesuresApps.profondeurNouveautes(corps: PlanNouveautes.corpsMax) <= GeoIlot.profondeurCentre, "les Nouveautés jamais plus hautes que le Centre")
    verifier(MesuresApps.profondeurListe <= GeoIlot.profondeurCentre, "Tes apps : \(Int(MesuresApps.profondeurListe)) pt, sous la hauteur du Centre")

    // la clé, jamais lisible
    verifier(ClePartielle.masque("ntn_abcdefghijklmnopqrstuvwxyzK7Rm") == "ntn_\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}K7Rm"
             && ClePartielle.masque("patAbc123.defghijklmnopqrstuvwxyz9fQz").hasPrefix("pat\u{2022}") && ClePartielle.masque("court") == String(repeating: "\u{2022}", count: 8),
             "la clé masquée : le préfixe, huit points, les quatre derniers caractères (une clé courte : des points seulement)")

    // les erreurs : un texte court pour la liste, un geste qui répare
    verifier(ErreurApp.reseau(.notion).geste == .reessayer && ErreurApp.autorisationMail.geste == .reglagesMail && ErreurApp.cleRefusee(.airtable).geste == .autreCle
             && ErreurApp.mailFerme.geste == .aucun && ErreurApp.introuvable(.notion).geste == .choisirBase, "chaque erreur a son geste")
    let toutes: [ErreurApp] = [.cleAbsente(.notion), .cleRefusee(.notion), .droitsManquants(.airtable, "x"), .introuvable(.notion), .introuvable(.airtable),
                               .limite(.airtable, reessayerDans: 30), .serveur(.notion, 502), .refus(.notion, 400), .reseau(.mail), .reponseIllisible(.notion),
                               .reglageIncomplet(.notion), .autorisationMail, .mailFerme, .mail(-1712)]
    verifier(toutes.allSatisfy { $0.court.count <= 36 && !$0.court.isEmpty }, "les formes courtes tiennent en 36 caractères")

    // le parcours : le grand bouton, les pages de choix, « Réessayer » quand la liste n'a pas pu être lue
    var p = ParcoursApp(app: .notion)
    verifier(!p.boutonActif && p.titreBouton == "Vérifier la clé", "clé vide : « Vérifier la clé » grisé")
    p.saisie = "ntn_x"
    verifier(p.boutonActif, "clé collée : « Vérifier la clé »")
    p.etape = .bases; p.choix = (1...9).map { ChoixApp(id: "\($0)", nom: "Base \($0)") }
    verifier(p.pages == 3 && p.optionsMontrees.count == 4 && !p.boutonActif && p.titreBouton == "Suivre cette base", "neuf bases : trois pages de quatre, rien de choisi")
    p.page = 7
    verifier(p.pageMontree == 2 && p.optionsMontrees.map(\.id) == ["9"], "une page trop loin : la dernière")
    var vide = ParcoursApp(app: .airtable, etape: .bases); vide.erreur = .reseau(.airtable)
    verifier(vide.relireLaListe && vide.boutonActif && vide.titreBouton == "Réessayer", "la liste n'a pas pu être lue : « Réessayer » la relit")

    // les blocs du détail, et la hauteur de la forme qui les épouse (jamais plus haute que la fenêtre de l'îlot)
    var e = EtatAppsIlot()
    e.branchees = Set(AppBranchee.allCases)
    e.etats = [.mail: .erreur(.autorisationMail), .agenda: .aJour(t), .notion: .erreur(.reseau(.notion)), .airtable: .aJour(t)]
    e.notion = ReglageNotion(baseId: "b", baseNom: "Tâches", proprieteDate: "d", proprietePersonne: "p", personneId: "x", personneNom: "Camille")
    e.airtable = ReglageAirtable(baseId: "a", baseNom: "Chantiers", tableId: "t", tableNom: "Suivi")
    e.cles = [.notion: "ntn_\u{2022}\u{2022}k7Rm", .airtable: "pat\u{2022}\u{2022}9fQz"]
    var pire = 0.0
    for app in AppBranchee.allCases {
        e.detail = app
        for conf in [false, true] {
            e.confirmation = conf
            pire = max(pire, e.profondeurDetail)
            verifier(e.blocs.last == (conf ? .confirmation : .pied), "\(app.nom)\(conf ? ", « Débrancher ? »" : "") : le détail finit par \(conf ? "la confirmation" : "le pied")")
        }
    }
    e.confirmation = false
    for app in [AppBranchee.notion, .airtable] {
        e.detail = app
        var q = ParcoursApp(app: app); q.erreur = .cleRefusee(app); e.parcours = q
        pire = max(pire, e.profondeurDetail)
        q.etape = .bases; q.choix = (1...6).map { ChoixApp(id: "\($0)", nom: "B\($0)") }; q.compte = "Espace"; e.parcours = q
        pire = max(pire, e.profondeurDetail)
        q.erreur = nil; e.parcours = q
        pire = max(pire, e.profondeurDetail)
    }
    verifier(pire <= MesuresApps.profondeurMax, "le détail le plus chargé : \(Int(pire)) pt ≤ \(Int(MesuresApps.profondeurMax)) (rien n'est rogné)")
    e.detail = .notion; e.parcours = nil
    verifier(e.blocs.contains { if case .erreur(_, .reessayer) = $0 { return true }; return false }, "Notion en erreur réseau : la phrase et « Réessayer »")
    e.confirmation = true
    verifier(!e.blocs.contains { if case .erreur = $0 { return true }; return false }, "« Débrancher ? » ouvert : l'erreur s'efface (on débranche)")

    // les lignes de « Tes apps »
    e.confirmation = false
    verifier(e.ligne(.mail).bouton == .aRevoir && e.ligne(.mail).alerte && e.ligne(.agenda).bouton == .branche && e.ligne(.airtable).sousTitre == "Table suivie : Suivi",
             "les lignes : « À revoir » en ambre, « Branché », ce qui est suivi")
    var x = EtatAppsIlot()
    verifier(x.ligne(.agenda).bouton == .brancher && x.ligne(.agenda).sousTitre.contains("permettre") && x.ligne(.notion).sousTitre == AppBranchee.notion.description,
             "rien de branché : « Brancher » partout ; l'Agenda dit que l'accès au calendrier est à permettre")
    x.calendrierPermis = true
    verifier(x.ligne(.agenda).sousTitre == AppBranchee.agenda.description, "le calendrier permis : la phrase de la maquette")
}

/// L'Agenda branché d'office, une seule fois ; une clé laissée en route effacée ; « Réessayer » relance une app arrêtée.
@MainActor
func controlesAppsFacadeInterface() async {
    groupe("Tes apps : la façade pour l'interface")
    let fm = FileManager.default
    let dossier = fm.temporaryDirectory.appendingPathComponent("controles-apps-ui-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
    try? fm.createDirectory(at: dossier, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: dossier) }
    let coffre = CoffreEnMemoire(), mail = FauxMail(), reseau = FauxReseau()
    let horloge = HorlogeEssai(Date(timeIntervalSince1970: 1_794_560_000))
    func fabriquer() -> AppsBranchees {
        AppsBranchees(magasin: MagasinJSON(url: dossier.appendingPathComponent("apps.json"), nom: "apps"), coffre: coffre, transport: reseau, mail: mail,
                      agenda: { [] }, horloge: { horloge.t }, heure: { _ in "10:00" },
                      espacementNotion: EspacementRequetes(ecart: 0), espacementAirtable: EspacementRequetes(ecart: 0))
    }
    var f = fabriquer()
    f.brancherAgendaUneFois(calendrierPermis: false)
    verifier(!f.estBranchee(.agenda) && f.memoire.agendaPropose == nil, "le calendrier pas permis : l'Agenda n'est pas branché")
    f.brancherAgendaUneFois(calendrierPermis: true)
    verifier(f.estBranchee(.agenda) && f.memoire.agendaPropose == true, "le calendrier permis : l'Agenda est branché d'office")
    f.debrancher(.agenda)
    f = fabriquer()
    f.brancherAgendaUneFois(calendrierPermis: true)
    verifier(!f.estBranchee(.agenda), "débranché par Hugues, il ne revient pas tout seul (même relancé)")

    // une clé vérifiée puis laissée en route (la base jamais choisie) : effacée ; celle d'une app branchée reste
    _ = coffre.ranger("ntn_enroute", pour: .notion)
    f.abandonner(.notion)
    verifier(coffre.lire(.notion) == nil, "branchement laissé en route : la clé ne reste pas dans le coffre")
    verifier(f.cleMasquee(.notion) == nil && f.cleMasquee(.mail) == nil, "pas de clé : rien à montrer (Mail n'en a jamais)")

    // « Réessayer » : une app arrêtée par une erreur qui demandait un geste est relue tout de suite
    mail.erreur = .autorisationMail
    f.brancher(.mail)
    _ = await f.sonder()
    verifier(f.etats[.mail] == .erreur(.autorisationMail) && f.plan.suivis[.mail]?.arrete == true, "autorisation refusée : Mail arrêté jusqu'à un geste")
    mail.erreur = nil
    _ = await f.reessayer(.mail)
    verifier(f.etats[.mail].map { if case .aJour = $0 { return true }; return false } == true && f.plan.suivis[.mail]?.arrete == false, "« Réessayer » : relu, il repart")

    // le nom de la personne Notion suit le choix
    _ = coffre.ranger("ntn_essaiEssaiEssaiEssaiEssaiEssaiK7Rm", pour: .notion)
    reseau.repondre("GET https://api.notion.com/v1/databases/0f0e0d0c", .init(corps: ExemplesApps.notionSchema))
    _ = await f.choisirBaseNotion("0f0e0d0c-1111-4222-8333-444455556666")
    f.choisirPersonneNotion("11111111-2222-4333-8444-555555555555", nom: "Camille")
    verifier(f.memoire.notion?.personneNom == "Camille", "la personne choisie garde son nom pour l'affichage")
    f.choisirPersonneNotion(nil, nom: "Camille")
    verifier(f.memoire.notion?.personneNom == nil && f.memoire.notion?.personneId == nil, "aucune personne : ni identifiant ni nom")
}
