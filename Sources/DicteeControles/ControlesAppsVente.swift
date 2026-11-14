import Foundation
import DicteeCore

// « Tes apps » : Shopify, HubSpot, Stripe (13/11). Réponses d'exemple calquées sur la doc officielle (formes des JSON), données
// inventées (aucun vrai client). Faux réseau, coffre en mémoire, dossier temporaire : jamais une vraie boutique, un vrai HubSpot, un vrai
// Stripe, ni le Trousseau.

enum ExemplesVente {
    // Shopify : la réponse du jeton (client credentials), une boutique, des commandes, le stock
    static let shopifyJeton = #"{"access_token":"f85632530bf277ec9ac6f649fc327f17","scope":"read_orders,read_products","expires_in":86399}"#
    static let shopifyBoutique = #"{"data":{"shop":{"name":"Boutique Essai"},"orders":{"nodes":[]}},"extensions":{"cost":{"requestedQueryCost":3}}}"#
    static func shopifyCommandes(_ c: [(id: Int, nom: String, cree: String, statut: String, montant: String, paye: String?, annulee: Bool)]) -> String {
        let n = c.map { x in
            let tr = x.paye.map { #"[{"kind":"SALE","status":"SUCCESS","processedAt":"\#($0)"},{"kind":"AUTHORIZATION","status":"SUCCESS","processedAt":"2026-11-01T00:00:00Z"}]"# } ?? "[]"
            return #"{"id":"gid://shopify/Order/\#(x.id)","name":"\#(x.nom)","createdAt":"\#(x.cree)","cancelledAt":\#(x.annulee ? #""2026-11-13T09:00:00Z""# : "null"),"displayFinancialStatus":"\#(x.statut)","totalPriceSet":{"shopMoney":{"amount":"\#(x.montant)","currencyCode":"EUR"}},"transactions":\#(tr)}"#
        }
        return #"{"data":{"orders":{"nodes":["# + n.joined(separator: ",") + #"]}}}"#
    }
    static let shopifyStock = #"{"data":{"products":{"nodes":[{"id":"gid://shopify/Product/101","title":"Bougie Essai","totalInventory":2,"tracksInventory":true,"updatedAt":"2026-11-13T09:05:00Z"},{"id":"gid://shopify/Product/102","title":"Savon Essai","totalInventory":0,"tracksInventory":true,"updatedAt":"2026-11-13T09:06:00Z"},{"id":"gid://shopify/Product/103","title":"Carte cadeau","totalInventory":0,"tracksInventory":false,"updatedAt":"2026-11-13T09:07:00Z"},{"id":"gid://shopify/Product/104","title":"Assez","totalInventory":12,"tracksInventory":true,"updatedAt":"2026-11-13T09:07:00Z"}]}}}"#
    static let shopifyLimite = #"{"errors":[{"message":"Throttled","extensions":{"code":"THROTTLED","documentation":"https://shopify.dev/api/usage/rate-limits"}}]}"#
    static let shopifyRefus = #"{"errors":[{"message":"Access denied for products field.","extensions":{"code":"ACCESS_DENIED"}}],"data":null}"#

    // HubSpot : le compte, des contacts, des affaires, l'historique de l'étape, les pipelines
    static let hubspotCompte = #"{"portalId":12345678,"accountType":"STANDARD","timeZone":"Europe/Paris","companyCurrency":"EUR","utcOffset":"+01:00","uiDomain":"app-eu1.hubspot.com","dataHostingLocation":"eu1"}"#
    static let hubspotUn = #"{"results":[],"paging":{}}"#
    static let hubspotContacts = #"{"total":2,"results":[{"id":"501","properties":{"createdate":"2026-11-13T09:10:00.000Z","email":"camille@exemple.fr","firstname":"Camille","hs_object_id":"501","lastmodifieddate":"2026-11-13T09:10:00.000Z","lastname":"Essai"},"createdAt":"2026-11-13T09:10:00.000Z","updatedAt":"2026-11-13T09:10:00.000Z","archived":false},{"id":"502","properties":{"createdate":"2026-11-13T09:11:00.000Z","email":"contact@exemple.fr","firstname":null,"lastname":null},"createdAt":"2026-11-13T09:11:00.000Z","updatedAt":"2026-11-13T09:11:00.000Z","archived":false}]}"#
    static let hubspotAffaires = #"{"total":3,"results":[{"id":"901","properties":{"amount":"12000","dealname":"Atelier Essai, agrandissement","dealstage":"closedwon","pipeline":"default","createdate":"2026-10-01T08:00:00.000Z","deal_currency_code":null},"archived":false},{"id":"902","properties":{"amount":"","dealname":"Projet Essai","dealstage":"presentationscheduled","pipeline":"default","createdate":"2026-10-02T08:00:00.000Z"},"archived":false},{"id":"903","properties":{"amount":"800","dealname":"Petit devis","dealstage":"appointmentscheduled","pipeline":"default","createdate":"2026-10-03T08:00:00.000Z"},"archived":false}]}"#
    static let hubspotHistorique = #"{"status":"COMPLETE","results":[{"id":"901","properties":{"dealstage":"closedwon"},"propertiesWithHistory":{"dealstage":[{"value":"closedwon","timestamp":"2026-11-13T09:12:00.000Z","sourceType":"CRM_UI"},{"value":"contractsent","timestamp":"2026-11-02T09:00:00.000Z","sourceType":"CRM_UI"}]}},{"id":"902","properties":{"dealstage":"presentationscheduled"},"propertiesWithHistory":{"dealstage":[{"value":"presentationscheduled","timestamp":"2026-11-13T09:13:00.000Z","sourceType":"CRM_UI"}]}},{"id":"903","properties":{"dealstage":"appointmentscheduled"},"propertiesWithHistory":{"dealstage":[{"value":"appointmentscheduled","timestamp":"2026-10-03T08:00:00.000Z","sourceType":"CRM_UI"}]}}]}"#
    static let hubspotPipelines = #"{"results":[{"id":"default","label":"Pipeline des ventes","stages":[{"id":"appointmentscheduled","label":"Rendez-vous fixé","metadata":{"isClosed":"false","probability":"0.2"}},{"id":"presentationscheduled","label":"Présentation prévue","metadata":{"isClosed":"false","probability":"0.6"}},{"id":"closedwon","label":"Conclue gagnée","metadata":{"isClosed":"true","probability":"1.0"}},{"id":"closedlost","label":"Conclue perdue","metadata":{"isClosed":"true","probability":"0.0"}}]}]}"#
    static let hubspotScopes = #"{"status":"error","message":"This app hasn't been granted all required scopes to make this call.","correlationId":"x","category":"MISSING_SCOPES"}"#

    // Stripe : des événements (payment_intent.succeeded / payment_failed)
    static func stripeEvenements(_ e: [(id: String, type: String, cree: Int, montant: Int, devise: String, description: String?)], live: Bool = true) -> String {
        let d = e.map { x in
            let desc = x.description.map { #""\#($0)""# } ?? "null"
            return #"{"id":"\#(x.id)","object":"event","api_version":"2026-10-28.endive","created":\#(x.cree),"data":{"object":{"id":"pi_\#(x.id.dropFirst(4))","object":"payment_intent","amount":\#(x.montant),"amount_received":\#(x.type == "payment_intent.succeeded" ? x.montant : 0),"currency":"\#(x.devise)","description":\#(desc),"status":"\#(x.type == "payment_intent.succeeded" ? "succeeded" : "requires_payment_method")"}},"livemode":\#(live),"pending_webhooks":0,"type":"\#(x.type)"}"#
        }
        return #"{"object":"list","url":"/v1/events","has_more":false,"data":["# + d.joined(separator: ",") + "]}"
    }
    static let stripeDroits = #"{"error":{"message":"The provided key 'rk_test_***' does not have the required permissions for this endpoint. Having the 'rak_event_read' permission would allow this request to continue.","type":"invalid_request_error"}}"#
}

@MainActor
func controlesAppsVente() async {
    func date(_ s: String) -> Date { ReponseHTTP.date(s)! }
    func espaces(_ s: String) -> String { s.replacingOccurrences(of: "\u{00A0}", with: " ").replacingOccurrences(of: "\u{202F}", with: " ") }
    func objet(_ s: String) -> [String: Any] { ReponseHTTP.objet(Data(s.utf8))! }

    groupe("Tes apps, vente : modèles (montants, genres)")
    verifier(AppBranchee.Groupe.quotidien.apps == [.mail, .agenda, .notion, .airtable] && AppBranchee.Groupe.vente.apps == [.shopify, .hubspot, .stripe],
             "deux pages : « Au quotidien » (4), « Vente » (3)")
    verifier(espaces(Montant.texte(Decimal(string: "49.9")!, devise: "EUR")) == "49,90 €" && espaces(Montant.texte(12000, devise: "eur")) == "12 000 €",
             "montants à la française, la devise de l'API (« 49,90 € », « 12 000 € » : \(espaces(Montant.texte(12000, devise: "EUR"))))")
    verifier(Montant.depuisUnites(4990, devise: "eur") == Decimal(string: "49.9")! && Montant.depuisUnites(1500, devise: "jpy") == 1500
             && Montant.depuisUnites(1234, devise: "kwd") == Decimal(string: "1.234")!, "Stripe en centimes ; le yen sans décimale ; le dinar koweïtien à trois")
    verifier(Montant.valeur("12000") == 12000 && Montant.valeur("") == nil && Montant.valeur("abc") == nil, "une valeur texte de l'API")
    func nv(_ id: String, _ app: AppBranchee) -> Nouveaute { Nouveaute(id: id, app: app, titre: id, sousTitre: "", date: Date(), action: .messageMail(id: id)) }
    verifier(nv("shopify:payee:1", .shopify).genre == .commande && nv("shopify:stock:1@bas", .shopify).genre == .stock && nv("hubspot:contact:1", .hubspot).genre == .contact
             && nv("hubspot:affaire:1@x@1", .hubspot).genre == .affaire && nv("stripe:evt_1", .stripe).genre == .paiement, "le genre d'une nouveauté se lit dans sa clé")
    verifier(AppBranchee.allCases.filter(\.demandeUneCle) == [.notion, .airtable, .shopify, .hubspot, .stripe]
             && Desinstallation.comptesTrousseauApps == ["notion", "airtable", "shopify", "hubspot", "stripe"],
             "Shopify, HubSpot, Stripe : une clé chacun dans le Trousseau (comptes « shopify », « hubspot », « stripe ») ; la désinstallation les efface")

    // --- Shopify
    groupe("Tes apps, vente : Shopify (réponses d'exemple)")
    verifier(ClientShopify.boutique(depuis: "ma-boutique") == "ma-boutique.myshopify.com"
             && ClientShopify.boutique(depuis: " https://Ma-Boutique.myshopify.com/admin/orders ") == "ma-boutique.myshopify.com"
             && ClientShopify.boutique(depuis: "admin.shopify.com/store/ma-boutique/orders?x=1") == "ma-boutique.myshopify.com",
             "l'adresse de la boutique : le nom, l'adresse en .myshopify.com, ou celle de l'admin")
    verifier(ClientShopify.boutique(depuis: "boutique.fr") == nil && ClientShopify.boutique(depuis: "ma boutique") == nil
             && ClientShopify.boutique(depuis: "x.myshopify.com.exemple.fr") == nil && ClientShopify.boutique(depuis: "evil@x.myshopify.com") == nil
             && ClientShopify.boutique(depuis: "") == nil, "un domaine à soi, un espace, un autre hôte : refusés (jamais une autre adresse)")
    let idShopify = "0123456789abcdef0123456789abcdef", secretShopify = "shpss_" + String(repeating: "S", count: 32)
    let jetonAncien = "shpat_" + String(repeating: "a", count: 32)
    verifier(IdentifiantsShopify(rangement: IdentifiantsShopify.client(id: idShopify, secret: secretShopify).rangement) == .client(id: idShopify, secret: secretShopify)
             && IdentifiantsShopify(rangement: jetonAncien) == .jeton(jetonAncien) && IdentifiantsShopify(rangement: "rien") == nil,
             "le Trousseau garde « identifiant:secret » ou l'ancien jeton, et les relit")
    verifier(ClientShopify.estJeton(jetonAncien) && !ClientShopify.estJeton(idShopify) && ClientShopify.identifiantVraisemblable(idShopify)
             && !ClientShopify.identifiantVraisemblable("abc") && ClientShopify.secretVraisemblable(secretShopify) && !ClientShopify.secretVraisemblable("a b"),
             "formes : ancien jeton shpat_, identifiant, secret")
    let rS = ReglageShopify(boutique: "ma-boutique.myshopify.com", nom: "Boutique Essai")
    let depuis = date("2026-11-13T09:00:00Z")
    let commandes = ClientShopify.analyserCommandes(objet(ExemplesVente.shopifyCommandes([
        (id: 1001, nom: "#1001", cree: "2026-11-13T09:01:00Z", statut: "PAID", montant: "49.9", paye: "2026-11-13T09:01:05Z", annulee: false),
        (id: 1002, nom: "#1002", cree: "2026-11-13T09:02:00Z", statut: "PENDING", montant: "120.0", paye: nil, annulee: false),
        (id: 990, nom: "#990", cree: "2026-11-10T09:00:00Z", statut: "PAID", montant: "15.0", paye: "2026-11-10T09:00:30Z", annulee: false),
        (id: 991, nom: "#991", cree: "2026-11-11T09:00:00Z", statut: "PAID", montant: "30.0", paye: "2026-11-13T09:03:00Z", annulee: false),
        (id: 992, nom: "#992", cree: "2026-11-13T09:04:00Z", statut: "PAID", montant: "10.0", paye: "2026-11-13T09:04:00Z", annulee: true),
    ]))["data"] as! [String: Any]) ?? []
    let ns = commandes.compactMap { ClientShopify.nouveaute($0, reglage: rS, depuis: depuis) }
    verifier(commandes.count == 5 && commandes[0].payeeLe == date("2026-11-13T09:01:05Z") && commandes[0].montant == Decimal(string: "49.9")!,
             "les commandes : numéro, montant et devise de l'API, l'heure de l'encaissement (une vente réussie)")
    verifier(ns.map(\.id) == ["shopify:payee:1001", "shopify:commande:1002", "shopify:payee:991"],
             "nouvelle et payée : une annonce ; nouvelle pas payée ; ancienne payée maintenant ; ni l'ancienne déjà payée (juste expédiée), ni l'annulée (\(ns.map(\.id)))")
    verifier(espaces(ns[0].sousTitre) == "Nouvelle, payée \u{00B7} 49,90 €" && ns[0].titre == "Commande #1001" && espaces(ns[1].sousTitre) == "Nouvelle \u{00B7} 120 €"
             && espaces(ns[2].sousTitre) == "Payée \u{00B7} 30 €" && ns[0].action == .adresse(URL(string: "https://admin.shopify.com/store/ma-boutique/orders/1001")!),
             "« Commande #1001 · Nouvelle, payée · 49,90 € », elle s'ouvre dans l'admin (\(ns.map { espaces($0.sousTitre) }))")
    let stocks = ClientShopify.analyserStocks(objet(ExemplesVente.shopifyStock)["data"] as! [String: Any]) ?? []
    verifier(stocks.map(\.titre) == ["Bougie Essai", "Savon Essai"] && ClientShopify.nouveaute(stocks[0], reglage: rS).sousTitre == "Stock bas : 2"
             && ClientShopify.nouveaute(stocks[1], reglage: rS).sousTitre == "Rupture de stock"
             && ClientShopify.nouveaute(stocks[0], reglage: rS).id == "shopify:stock:101@bas" && ClientShopify.nouveaute(stocks[1], reglage: rS).id == "shopify:stock:102@rupture",
             "stock bas (≤ 3) et rupture, seulement pour les produits suivis ; annoncé une fois par palier")
    verifier(ClientShopify.erreurJeton(statut: 400, corps: ["error": "shop_not_permitted"]) == .droitsManquants(.shopify, "la boutique n\u{2019}est pas dans ton organisation Shopify")
             && ClientShopify.erreurJeton(statut: 401, corps: ["error": "invalid_client"]) == .cleRefusee(.shopify)
             && ClientShopify.erreurJeton(statut: 404, corps: nil) == .introuvable(.shopify)
             && ClientShopify.erreurGraphQL(objet(ExemplesVente.shopifyLimite)) == .limite(.shopify, reessayerDans: 2)
             && ClientShopify.erreurGraphQL(objet(ExemplesVente.shopifyRefus), droit: "read_products") == .droitsManquants(.shopify, "read_products"),
             "erreurs : boutique hors de l'organisation, identifiant refusé, boutique introuvable, limite de points, droit manquant")
    verifier(ClientShopify.filtreCommandes(depuis: depuis) == "updated_at:>'2026-11-13T09:00:00Z'", "le filtre des commandes (mises à jour depuis)")
    do {
        let reseau = FauxReseau()
        let jeton = JetonShopify()
        func client(_ t: Date) -> ClientShopify {
            ClientShopify(boutique: "ma-boutique.myshopify.com", identifiants: .client(id: idShopify, secret: secretShopify), transport: reseau,
                          espacement: EspacementRequetes(ecart: 0), jeton: jeton, maintenant: t)
        }
        reseau.repondre("POST https://ma-boutique.myshopify.com/admin/oauth/access_token", .init(corps: ExemplesVente.shopifyJeton))
        reseau.repondre("POST https://ma-boutique.myshopify.com/admin/api/2026-10/graphql.json", .init(corps: ExemplesVente.shopifyBoutique))
        let nom = try? await client(depuis).verifier()
        let rj = reseau.requetes.first, rg = reseau.requetes.last
        let corpsJeton = rj?.httpBody.map { String(decoding: $0, as: UTF8.self) } ?? ""
        verifier(nom == "Boutique Essai" && reseau.requetes.count == 2 && rj?.url?.query == nil && corpsJeton.hasPrefix("grant_type=client_credentials&client_id=\(idShopify)")
                 && rj?.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded"
                 && rg?.value(forHTTPHeaderField: "X-Shopify-Access-Token") == "f85632530bf277ec9ac6f649fc327f17",
                 "client credentials : un formulaire (jamais le secret dans l'adresse), puis GraphQL avec le jeton en en-tête")
        _ = try? await client(depuis.addingTimeInterval(3600)).verifier()
        verifier(reseau.requetes.count == 3, "le jeton de 24 h est gardé : une heure plus tard, pas de nouvelle demande")
        _ = try? await client(depuis.addingTimeInterval(86_400)).verifier()
        verifier(reseau.requetes.count == 5 && reseau.requetes[3].url?.path == "/admin/oauth/access_token", "24 h plus tard : redemandé")
        reseau.repondre("POST https://ma-boutique.myshopify.com/admin/api/2026-10/graphql.json", .init(statut: 401, corps: #"{"errors":"[API] Invalid API key or access token"}"#))
        let refus: ErreurApp?
        do { _ = try await client(depuis.addingTimeInterval(86_500)).verifier(); refus = nil } catch { refus = error }
        verifier(refus == .cleRefusee(.shopify) && reseau.requetes.count == 8, "jeton refusé (révoqué) : redemandé une fois, puis « clé refusée » (\(reseau.requetes.count) requêtes)")
        reseau.repondre("POST https://ma-boutique.myshopify.com/admin/oauth/access_token", .init(statut: 400, corps: #"{"error":"shop_not_permitted","error_description":"x"}"#))
        jeton.oublier()
        do { _ = try await client(depuis).verifier(); verifier(false, "boutique hors organisation") }
        catch { verifier(error == .droitsManquants(.shopify, "la boutique n\u{2019}est pas dans ton organisation Shopify") && error.texte.count < 110, "« \(error.texte) »") }
    }

    // --- HubSpot
    groupe("Tes apps, vente : HubSpot (réponses d'exemple)")
    let cleHubSpot = "pat" + "-eu1-" + String(repeating: "1", count: 8) + "-2222-3333-4444-" + String(repeating: "5", count: 12)
    verifier(ClientHubSpot.vraisemblable(cleHubSpot) && !ClientHubSpot.vraisemblable("pat-court") && !ClientHubSpot.vraisemblable("ntn_" + String(repeating: "x", count: 40)),
             "forme d'une clé de service HubSpot (pat-…)")
    verifier(ClientHubSpot.domaine(cle: cleHubSpot) == "app-eu1.hubspot.com" && ClientHubSpot.domaine(cle: "pat-na1-abc") == "app.hubspot.com", "un compte en Europe : app-eu1")
    let compte = ClientHubSpot.analyserCompte(objet(ExemplesVente.hubspotCompte), cle: cleHubSpot)
    verifier(compte == ReglageHubSpot(portail: 12345678, domaine: "app-eu1.hubspot.com", devise: "EUR"), "le compte : numéro, domaine, devise")
    let corpsR = ClientHubSpot.recherche("createdate", depuis: date("2026-11-13T09:00:00Z"), proprietes: ["email"])
    let filtre = ((corpsR["filterGroups"] as? [[String: Any]])?.first?["filters"] as? [[String: String]])?.first
    verifier(filtre == ["propertyName": "createdate", "operator": "GT", "value": "1794560400000"] && corpsR["limit"] as? Int == 20,
             "la recherche : « createdate > depuis » en millisecondes, 20 au plus (\(filtre ?? [:]))")
    let contacts = ClientHubSpot.analyserContacts(objet(ExemplesVente.hubspotContacts)) ?? []
    verifier(contacts.map(\.nom) == ["Camille Essai", "contact@exemple.fr"] && ClientHubSpot.nouveaute(contacts[0], reglage: compte).action
             == .adresse(URL(string: "https://app-eu1.hubspot.com/contacts/12345678/record/0-1/501")!),
             "nouveau contact : son nom (sinon son e-mail), sa fiche s'ouvre")
    let etapes = ClientHubSpot.analyserEtapes(objet(ExemplesVente.hubspotPipelines))
    verifier(etapes["closedwon"]?.gagnee == true && etapes["closedlost"]?.perdue == true && etapes["presentationscheduled"]?.nom == "Présentation prévue"
             && etapes["appointmentscheduled"]?.gagnee == false, "les étapes : gagnée (fermée, 100 %), perdue (fermée, 0 %), leurs noms")
    var affaires = ClientHubSpot.analyserAffaires(objet(ExemplesVente.hubspotAffaires)) ?? []
    let hist = ClientHubSpot.analyserHistorique(objet(ExemplesVente.hubspotHistorique))
    for i in affaires.indices { affaires[i].entreeEtape = hist[affaires[i].id] }
    let na = affaires.compactMap { ClientHubSpot.nouveaute($0, etapes: etapes, reglage: compte, depuis: depuis) }
    verifier(na.count == 2 && espaces(na[0].sousTitre) == "Gagnée \u{00B7} 12 000 €" && na[1].sousTitre == "Étape : Présentation prévue"
             && na[0].id == "hubspot:affaire:901@closedwon@1794561120000",
             "affaire gagnée (montant, devise du compte), affaire qui change d'étape ; modifiée sans changer d'étape : rien (\(na.map(\.sousTitre)))")
    var perdue = affaires[1]; perdue.etape = "closedlost"
    verifier(ClientHubSpot.nouveaute(perdue, etapes: [:], reglage: compte, depuis: depuis)?.sousTitre == "Perdue", "perdue (même sans les pipelines : étapes par défaut)")
    var neuve = affaires[2]; neuve.creee = date("2026-11-13T09:20:00Z"); neuve.entreeEtape = neuve.creee
    verifier(ClientHubSpot.nouveaute(neuve, etapes: etapes, reglage: compte, depuis: depuis)?.sousTitre == "Nouvelle \u{00B7} Rendez-vous fixé", "une affaire créée : « Nouvelle · Rendez-vous fixé »")
    verifier(ClientHubSpot.erreur(statut: 403, corps: objet(ExemplesVente.hubspotScopes), droit: ClientHubSpot.droitAffaires) == .droitsManquants(.hubspot, "crm.objects.deals.read")
             && ReponseHTTP.erreur(.hubspot, statut: 429, code: "RATE_LIMITS", reessayer: nil) == .limite(.hubspot, reessayerDans: 10)
             && ReponseHTTP.erreur(.hubspot, statut: 401, code: "INVALID_AUTHENTICATION", reessayer: nil) == .cleRefusee(.hubspot),
             "erreurs : droit manquant (nommé), limite (fenêtre de 10 s), clé refusée")
    do {
        let reseau = FauxReseau()
        let c = ClientHubSpot(cle: cleHubSpot, transport: reseau, espacement: EspacementRequetes(ecart: 0))
        reseau.repondre("POST https://api.hubapi.com/crm/v3/objects/deals/search", .init(corps: ExemplesVente.hubspotAffaires))
        reseau.repondre("POST https://api.hubapi.com/crm/v3/objects/deals/batch/read", .init(corps: ExemplesVente.hubspotHistorique))
        let lues = (try? await c.affaires(depuis: depuis)) ?? []
        let lot = reseau.requetes.last.flatMap { $0.httpBody }.flatMap { ReponseHTTP.objet($0) }
        verifier(lues.count == 3 && lues[0].entreeEtape == date("2026-11-13T09:12:00Z") && (lot?["propertiesWithHistory"] as? [String]) == ["dealstage"]
                 && (lot?["inputs"] as? [[String: String]])?.count == 3 && reseau.requetes.first?.value(forHTTPHeaderField: "Authorization") == "Bearer \(cleHubSpot)",
                 "les affaires modifiées, puis l'historique de l'étape en une lecture groupée (clé en en-tête)")
    }

    // --- Stripe
    groupe("Tes apps, vente : Stripe (réponses d'exemple)")
    let rkTest = "rk" + "_test_" + String(repeating: "R", count: 40), skLive = "sk" + "_live_" + String(repeating: "S", count: 40)
    verifier(ClientStripe.controler(skLive) == .cleTropPuissante(.stripe) && ClientStripe.controler("sk" + "_test_" + String(repeating: "S", count: 40)) == .cleTropPuissante(.stripe)
             && ClientStripe.controler("pk" + "_live_" + String(repeating: "P", count: 40)) == .cleRefusee(.stripe) && ClientStripe.controler(rkTest) == nil,
             "une clé secrète complète (sk_) est refusée : « \(ErreurApp.cleTropPuissante(.stripe).texte) » ; une clé publiable aussi ; une clé limitée passe")
    let adresse = ClientStripe.adresseEvenements(depuis: date("2026-11-13T09:00:00Z")).absoluteString
    verifier(adresse.contains("types%5B%5D=payment_intent.succeeded") && adresse.contains("types%5B%5D=payment_intent.payment_failed")
             && adresse.contains("created%5Bgt%5D=1794560400") && adresse.contains("limit=20") && !adresse.contains("type="),
             "les événements : deux types (types[]), créés après la fenêtre, 20 au plus (\(adresse))")
    let evts = ClientStripe.analyser(objet(ExemplesVente.stripeEvenements([
        (id: "evt_1Essai", type: "payment_intent.succeeded", cree: 1_794_560_500, montant: 4990, devise: "eur", description: "Abonnement Essai"),
        (id: "evt_2Essai", type: "payment_intent.payment_failed", cree: 1_794_560_600, montant: 12000, devise: "eur", description: nil),
        (id: "evt_3Essai", type: "payment_intent.succeeded", cree: 1_794_560_700, montant: 1500, devise: "jpy", description: nil),
        (id: "evt_4Essai", type: "charge.refunded", cree: 1_794_560_800, montant: 100, devise: "eur", description: nil),
    ]))) ?? []
    let nst = evts.map(ClientStripe.nouveaute)
    verifier(nst.map(\.titre) == ["Paiement reçu", "Paiement échoué", "Paiement reçu"] && espaces(nst[0].sousTitre) == "49,90 € \u{00B7} Abonnement Essai"
             && espaces(nst[1].sousTitre) == "120 €" && espaces(nst[2].sousTitre).hasPrefix("1 500") && nst[0].id == "stripe:evt_1Essai"
             && nst[0].action == .adresse(URL(string: "https://dashboard.stripe.com/payments/pi_1Essai")!),
             "reçu, échoué (centimes, devise de l'API), un autre type ignoré ; le paiement s'ouvre dans le Dashboard (\(nst.map { espaces($0.sousTitre) }))")
    let test = ClientStripe.analyser(objet(ExemplesVente.stripeEvenements([(id: "evt_9Essai", type: "payment_intent.succeeded", cree: 1_794_560_500, montant: 100, devise: "eur", description: nil)], live: false))) ?? []
    verifier(test.first.map(ClientStripe.nouveaute)?.sousTitre.hasSuffix("test") == true
             && test.first.map(ClientStripe.nouveaute)?.action == .adresse(URL(string: "https://dashboard.stripe.com/test/payments/pi_9Essai")!), "mode test : dit, et ouvert dans le Dashboard de test")
    verifier(ClientStripe.erreur(statut: 403, corps: objet(ExemplesVente.stripeDroits)) == .droitsManquants(.stripe, ClientStripe.droits)
             && ReponseHTTP.erreur(.stripe, statut: 401, code: nil, reessayer: nil) == .cleRefusee(.stripe)
             && ReponseHTTP.erreur(.stripe, statut: 429, code: "rate_limit", reessayer: nil) == .limite(.stripe, reessayerDans: 60),
             "erreurs : droits manquants (« \(ErreurApp.droitsManquants(.stripe, ClientStripe.droits).texte) »), clé refusée, limite")

    // --- la façade, de bout en bout
    groupe("Tes apps, vente : la façade (faux réseau, coffre en mémoire)")
    let fm = FileManager.default
    let dossier = fm.temporaryDirectory.appendingPathComponent("voxile-apps-vente-\(UUID().uuidString)", isDirectory: true)
    try? fm.createDirectory(at: dossier, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: dossier) }
    let fichier = dossier.appendingPathComponent("apps.json")
    let horloge = HorlogeEssai(date("2026-11-13T09:30:00Z"))
    let reseau = FauxReseau(), coffre = CoffreEnMemoire()
    var journal: [String] = [], annonces: [[Nouveaute]] = []
    let zero = EspacementRequetes(ecart: 0)
    func fabriquer() -> AppsBranchees {
        let a = AppsBranchees(magasin: MagasinJSON(url: fichier, nom: "apps"), coffre: coffre, transport: reseau, mail: FauxMail(), agenda: { [] },
                              horloge: { horloge.t }, heure: { _ in "10:00" }, journal: { journal.append($0) },
                              espacementNotion: zero, espacementAirtable: zero, espacementShopify: zero, espacementHubSpot: zero, espacementStripe: zero)
        a.surNouveautes = { annonces.append($0) }
        return a
    }
    let apps = fabriquer()
    // Stripe : la clé secrète refusée sans rien envoyer
    let r0 = await apps.enregistrerCle(skLive, pour: .stripe)
    verifier(r0 == .failure(.cleTropPuissante(.stripe)) && reseau.requetes.isEmpty && coffre.lire(.stripe) == nil && !apps.estBranchee(.stripe),
             "sk_ : refusée AVANT tout envoi, rien n'est gardé")
    reseau.repondre("GET https://api.stripe.com/v1/events?", .init(corps: ExemplesVente.stripeEvenements([])))
    let r1 = await apps.enregistrerCle(rkTest, pour: .stripe)
    verifier(r1 == .success("mode test") && coffre.lire(.stripe) == rkTest && apps.estBranchee(.stripe) && apps.memoire.stripe == ReglageStripe(test: true),
             "rk_test_ : vérifiée, rangée, Stripe branché d'un coup (rien à choisir)")
    // HubSpot
    reseau.repondre("GET https://api.hubapi.com/crm/v3/objects/contacts?limit=1", .init(corps: ExemplesVente.hubspotUn))
    reseau.repondre("GET https://api.hubapi.com/crm/v3/objects/deals?limit=1", .init(statut: 403, corps: ExemplesVente.hubspotScopes))
    let h0 = await apps.enregistrerCle(cleHubSpot, pour: .hubspot)
    verifier(h0 == .failure(.droitsManquants(.hubspot, "crm.objects.deals.read")) && coffre.lire(.hubspot) == nil,
             "HubSpot sans le droit des affaires : « \(ErreurApp.droitsManquants(.hubspot, "crm.objects.deals.read").texte) », rien de gardé")
    reseau.repondre("GET https://api.hubapi.com/crm/v3/objects/deals?limit=1", .init(corps: ExemplesVente.hubspotUn))
    reseau.repondre("GET https://api.hubapi.com/account-info/v3/details", .init(corps: ExemplesVente.hubspotCompte))
    let h1 = await apps.enregistrerCle(cleHubSpot, pour: .hubspot)
    verifier(h1 == .success("compte 12345678") && apps.estBranchee(.hubspot) && apps.memoire.hubspot?.portail == 12345678, "HubSpot : vérifiée, branché, le compte retenu")
    // Shopify
    reseau.repondre("POST https://ma-boutique.myshopify.com/admin/oauth/access_token", .init(corps: ExemplesVente.shopifyJeton))
    reseau.repondre("POST https://ma-boutique.myshopify.com/admin/api/2026-10/graphql.json", .init(corps: ExemplesVente.shopifyBoutique))
    let s0 = await apps.enregistrerShopify(boutique: "boutique.fr", identifiant: idShopify, secret: secretShopify)
    verifier(s0 == .failure(.introuvable(.shopify)), "une adresse qui n'est pas en .myshopify.com : refusée sans envoi")
    let s1 = await apps.enregistrerShopify(boutique: "ma-boutique", identifiant: idShopify, secret: secretShopify)
    verifier(s1 == .success("Boutique Essai") && coffre.lire(.shopify) == "\(idShopify):\(secretShopify)" && apps.estBranchee(.shopify)
             && apps.memoire.shopify == ReglageShopify(boutique: "ma-boutique.myshopify.com", nom: "Boutique Essai")
             && apps.cleMasquee(.shopify) == ClePartielle.masque(secretShopify), "Shopify : vérifié, rangé (une entrée), branché ; le détail montre le secret masqué")
    // premier passage : rien d'annoncé ; puis du neuf dans les trois
    reseau.repondre("POST https://ma-boutique.myshopify.com/admin/api/2026-10/graphql.json", .init(corps: #"{"data":{"orders":{"nodes":[]},"products":{"nodes":[]}}}"#))
    reseau.repondre("POST https://api.hubapi.com/crm/v3/objects/contacts/search", .init(corps: #"{"total":0,"results":[]}"#))
    reseau.repondre("POST https://api.hubapi.com/crm/v3/objects/deals/search", .init(corps: #"{"total":0,"results":[]}"#))
    reseau.repondre("GET https://api.stripe.com/v1/events?", .init(entetes: ["Date": "Fri, 13 Nov 2026 09:30:00 GMT"], corps: ExemplesVente.stripeEvenements([])))
    var n = await apps.sonder()
    verifier(n.isEmpty && annonces.isEmpty && [AppBranchee.shopify, .hubspot, .stripe].allSatisfy { apps.etats[$0] == .aJour(horloge.t) },
             "premier passage des trois : à jour, rien d'annoncé")
    verifier(apps.plan.suivis[.stripe]?.prochain == horloge.t.addingTimeInterval(180) && apps.plan.suivis[.shopify]?.prochain == horloge.t.addingTimeInterval(180),
             "le rythme : toutes les 3 minutes")
    horloge.avancer(180)
    reseau.repondre("POST https://ma-boutique.myshopify.com/admin/api/2026-10/graphql.json", .init(corps: ExemplesVente.shopifyCommandes([
        (id: 1003, nom: "#1003", cree: "2026-11-13T09:31:00Z", statut: "PAID", montant: "64.5", paye: "2026-11-13T09:31:10Z", annulee: false)])))
    reseau.repondre("POST https://api.hubapi.com/crm/v3/objects/contacts/search", .init(corps: ExemplesVente.hubspotContacts.replacingOccurrences(of: "2026-11-13T09:1", with: "2026-11-13T09:3")
        .replacingOccurrences(of: #","results":[{"id":"501""#, with: #","results":[{"id":"501""#)))
    reseau.repondre("GET https://api.stripe.com/v1/events?", .init(entetes: ["Date": "Fri, 13 Nov 2026 09:33:00 GMT"], corps: ExemplesVente.stripeEvenements([
        (id: "evt_5Essai", type: "payment_intent.succeeded", cree: 1_794_562_300, montant: 6450, devise: "eur", description: nil),
        (id: "evt_6Essai", type: "payment_intent.payment_failed", cree: 1_794_562_310, montant: 2000, devise: "eur", description: nil)])))
    n = await apps.sonder()
    let annonce = AnnonceApps(n)
    verifier(n.count == 5 && annonce.titre == "5 nouveautés" && annonce.sousTitre == "1 commande, 2 contacts, 2 paiements",
             "3 min plus tard : une commande, deux contacts, deux paiements, en UNE annonce « \(annonce.titre) · \(annonce.sousTitre) »")
    let stripeRequete = reseau.requetes.last { $0.url?.host == "api.stripe.com" }?.url?.absoluteString ?? ""
    verifier(stripeRequete.contains("created%5Bgt%5D=1794562140"), "Stripe : la fenêtre part de l'heure de Stripe moins une minute (\(stripeRequete.suffix(60)))")
    horloge.avancer(180)
    n = await apps.sonder()
    verifier(n.isEmpty, "les mêmes réponses 3 min plus tard : rien de réannoncé")
    // une erreur : l'attente double
    reseau.repondre("POST https://api.hubapi.com/crm/v3/objects/contacts/search", .init(statut: 502, corps: "{}"))
    horloge.avancer(180)
    _ = await apps.sonder()
    let p1 = apps.plan.suivis[.hubspot]?.prochain
    horloge.avancer(180)
    _ = await apps.sonder()
    let p2 = apps.plan.suivis[.hubspot]?.prochain
    verifier(apps.etats[.hubspot] == .erreur(.serveur(.hubspot, 502)) && p1 == horloge.t.addingTimeInterval(-180 + 180) && p2 == horloge.t.addingTimeInterval(360),
             "HubSpot en panne : 3 min, puis 6 min (l'attente double)")
    reseau.repondre("POST https://api.hubapi.com/crm/v3/objects/contacts/search", .init(statut: 429, corps: #"{"status":"error","category":"RATE_LIMITS"}"#))
    horloge.avancer(400)
    _ = await apps.sonder()
    verifier(apps.etats[.hubspot] == .erreur(.limite(.hubspot, reessayerDans: 10)), "HubSpot 429 : « \(ErreurApp.limite(.hubspot, reessayerDans: 10).texte) »")
    // débrancher
    apps.debrancher(.shopify)
    verifier(coffre.lire(.shopify) == nil && apps.memoire.shopify == nil && apps.memoire.shopifyDepuis == nil, "débrancher Shopify : la clé quitte le coffre, la boutique est oubliée")
    // vie privée
    let texte = (try? String(contentsOf: fichier, encoding: .utf8)) ?? ""
    verifier(!texte.isEmpty && ![rkTest, cleHubSpot, idShopify, secretShopify, "f85632530bf277ec9ac6f649fc327f17"].contains { texte.contains($0) },
             "apps.json : ni clé, ni identifiant, ni secret, ni jeton")
    let interdits = [rkTest, skLive, cleHubSpot, idShopify, secretShopify, "f85632530bf2", "Camille", "exemple.fr", "49,90", "64,5", "Boutique Essai", "ma-boutique", "#1003", "12345678"]
    verifier(!journal.isEmpty && journal.allSatisfy { l in !interdits.contains { l.contains($0) } },
             "le journal : ni clé, ni nom de client, ni e-mail, ni montant, ni boutique (\(journal.count) lignes)\(journal.first { l in interdits.contains { l.contains($0) } }.map { " : « \($0) »" } ?? "")")
    let attrs = try? fm.attributesOfItem(atPath: fichier.path)
    verifier((attrs?[.posixPermissions] as? Int) == 0o600, "apps.json en 0600")
    let ailleurs = reseau.requetes.contains { r in
        let u = r.url?.absoluteString ?? ""
        return [rkTest, cleHubSpot, secretShopify, "f85632530bf2"].contains { u.contains($0) }
    }
    verifier(!ailleurs && reseau.requetes.allSatisfy { $0.url?.scheme == "https" }, "aucune clé dans une adresse, toujours en https")

    // --- l'interface
    groupe("Tes apps, vente : l'interface (onglets, parcours, regroupement)")
    let t = date("2026-11-13T10:00:00Z")
    func x(_ id: String, _ app: AppBranchee, _ s: TimeInterval = 0) -> Nouveaute { Nouveaute(id: id, app: app, titre: id, sousTitre: "s", date: t.addingTimeInterval(s), action: .messageMail(id: id)) }
    let a = AnnonceApps([x("shopify:commande:1", .shopify), x("hubspot:contact:2", .hubspot, 1), x("stripe:evt_a", .stripe, 2), x("stripe:evt_b", .stripe, 3)])
    verifier(a.titre == "4 nouveautés" && a.sousTitre == "1 commande, 1 contact, 2 paiements" && a.aile.first == "4 nouv.", "« 4 nouveautés · 1 commande, 1 contact, 2 paiements »")
    let deux = AnnonceApps([x("shopify:commande:1", .shopify), x("shopify:payee:2", .shopify, 1)])
    verifier(deux.titre == "2 nouvelles commandes" && deux.aile.first == "2 commandes" && AnnonceApps([x("stripe:evt_a", .stripe), x("stripe:evt_b", .stripe, 1)]).titre == "2 nouveaux paiements",
             "un seul genre : « 2 nouvelles commandes », « 2 nouveaux paiements »")
    let melange = AnnonceApps([x("shopify:commande:1", .shopify), x("shopify:stock:2@bas", .shopify, 1)])
    verifier(melange.titre == "2 nouveautés" && melange.sousTitre == "1 commande, 1 alerte de stock", "une app, deux genres : comptés à part")
    var act: [AppBranchee: [Nouveaute]] = [:]
    for (i, app) in AppBranchee.allCases.enumerated() { act[app] = [x("\(app.rawValue):1", app, Double(i) * 10)] }
    let s = PlanNouveautes.sections(act)
    verifier(PlanNouveautes.hauteur(s) <= PlanNouveautes.corpsMax && s.map(\.app) == [.airtable, .shopify, .hubspot, .stripe],
             "sept apps avec du neuf : celles qui tiennent sont les plus récentes, rangées dans l'ordre de Tes apps (\(s.map(\.app.rawValue)))")
    verifier(MesuresApps.profondeurListe(.quotidien) <= GeoIlot.profondeurCentre && MesuresApps.profondeurListe(.vente) < MesuresApps.profondeurListe(.quotidien),
             "Tes apps : \(Int(MesuresApps.profondeurListe(.quotidien))) pt (quatre apps), \(Int(MesuresApps.profondeurListe(.vente))) pt (trois), sous le Centre")
    var p = ParcoursApp(app: .shopify)
    verifier(p.etape == .boutique && p.titreBouton == "Continuer" && !p.boutonActif && p.champ?.masque == false && p.champ?.page == ClientShopify.pageBoutique,
             "Shopify commence par l'adresse de la boutique (en clair, « Continuer »)")
    p.saisie = "https://ma-boutique.myshopify.com/admin"
    verifier(p.saisieMontree == "ma-boutique.myshopify.com" && p.boutonActif, "l'adresse collée se montre ramenée à sa forme .myshopify.com")
    p.boutique = "ma-boutique.myshopify.com"; p.etape = .identifiant; p.saisie = jetonAncien
    var e = EtatAppsIlot(); e.detail = .shopify; e.parcours = p
    verifier(p.jetonShopify && p.titreBouton == "Vérifier le jeton" && e.blocs.first == .valide("Boutique \u{00B7} ma-boutique.myshopify.com") && p.champ?.page == ClientShopify.pageApp,
             "un ancien jeton shpat_ collé à l'identifiant : « Vérifier le jeton » (pas de secret) ; la boutique rappelée en vert")
    p.saisie = idShopify
    verifier(!p.jetonShopify && p.titreBouton == "Continuer" && p.saisieMontree == ClePartielle.masque(idShopify), "un identifiant : « Continuer » vers le secret")
    p.etape = .cle; p.saisie = nil
    verifier(p.titreBouton == "Vérifier et brancher" && p.champ?.libelle == "Secret client de ton app", "le secret : « Vérifier et brancher »")
    verifier(ParcoursApp(app: .stripe).champ?.exemple.hasPrefix("rk_") == true && ParcoursApp(app: .hubspot).champ?.exemple.hasPrefix("pat-") == true
             && ParcoursApp(app: .stripe).champ?.page == ClientStripe.pageCle, "Stripe et HubSpot : une clé, l'exemple (rk_…, pat-…), la page où la créer")
    // la hauteur la plus chargée de chaque parcours, et du détail de chaque app branchée
    var pire = 0.0
    for app in [AppBranchee.shopify, .hubspot, .stripe] {
        for etape in (app == .shopify ? [ParcoursApp.Etape.boutique, .identifiant, .cle] : [.cle]) {
            var q = ParcoursApp(app: app, etape: etape); q.boutique = "ma-boutique.myshopify.com"; q.saisie = "x"
            for err in [nil, ErreurApp.cleTropPuissante(app), .droitsManquants(app, "la boutique n\u{2019}est pas dans ton organisation Shopify")] {
                q.erreur = err
                var f = EtatAppsIlot(); f.detail = app; f.parcours = q
                pire = max(pire, f.profondeurDetail)
            }
        }
        var f = EtatAppsIlot(); f.detail = app; f.branchees = [app]; f.etats = [app: .erreur(.droitsManquants(app, ClientStripe.droits))]
        f.shopify = rS; f.hubspot = compte; f.stripe = ReglageStripe(test: true); f.cles = [app: "rk_test_\u{2022}\u{2022}RRRR"]
        pire = max(pire, f.profondeurDetail)
        f.confirmation = true
        pire = max(pire, f.profondeurDetail)
    }
    verifier(pire <= MesuresApps.profondeurMax, "le détail le plus chargé des apps de vente : \(Int(pire)) pt ≤ \(Int(MesuresApps.profondeurMax))")
    verifier(ErreurApp.cleTropPuissante(.stripe).geste == .autreCle && ErreurApp.introuvable(.shopify).geste == .autreCle && ErreurApp.introuvable(.notion).geste == .choisirBase
             && ErreurApp.reglageIncomplet(.shopify).geste == .autreCle && ErreurApp.cleTropPuissante(.stripe).demandeUnGeste,
             "les gestes : une clé trop puissante, une boutique introuvable → recoller ; une base Notion → la choisir")
    let erreurs: [ErreurApp] = [.cleTropPuissante(.stripe), .introuvable(.shopify), .reglageIncomplet(.shopify), .reglageIncomplet(.hubspot), .droitsManquants(.hubspot, "x")]
    verifier(erreurs.allSatisfy { $0.court.count <= 36 }, "les formes courtes tiennent en 36 caractères")
    var l = EtatAppsIlot()
    l.branchees = [.shopify, .stripe]; l.etats = [.shopify: .aJour(t), .stripe: .aJour(t)]; l.shopify = rS; l.stripe = ReglageStripe(test: true)
    verifier(l.ligne(.shopify).sousTitre == "Boutique : Boutique Essai" && l.ligne(.stripe).sousTitre == "Paiements du mode test" && l.ligne(.hubspot).bouton == .brancher,
             "les lignes : la boutique suivie, le mode test dit, HubSpot à brancher")
}
