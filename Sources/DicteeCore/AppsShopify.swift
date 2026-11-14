import Foundation

// Shopify, par l'API Admin GraphQL (https://shopify.dev/docs/api/admin-graphql), en lecture seule.
//
// Le jeton (doc relue le 13/11/2026) : depuis le 1er janvier 2026, on ne crée plus d'app « personnalisée » dans l'admin de la boutique.
// Le marchand crée une app dans le Dev Dashboard (Réglages › Apps › Développer des apps › « Build apps in Dev Dashboard »), lui donne
// les droits `read_orders` (et `read_products` pour le stock bas, facultatif), l'installe sur sa boutique, et copie l'identifiant client
// et le secret client (Settings). Voxile en tire un jeton par la « client credentials grant » :
// POST https://{boutique}.myshopify.com/admin/oauth/access_token (grant_type, client_id, client_secret) → `access_token`, valable
// 24 h (`expires_in` = 86399), redemandé avant son échéance. Cette voie ne marche que si l'app et la boutique sont dans la même
// organisation Shopify (sinon `shop_not_permitted`). Une ancienne app de l'admin (avant 2026) garde son jeton `shpat_…` : accepté tel quel.
//
// L'identifiant et le secret (ou le jeton `shpat_`) vont dans le Trousseau (compte « shopify ») ; le jeton de 24 h reste en mémoire.
// On lit : les commandes mises à jour depuis le dernier passage (nouvelle commande, commande payée : numéro, montant et devise de l'API) ;
// les produits suivis dont le stock total est bas (≤ 3). Jamais un client (nom, e-mail, adresse) : on ne les demande pas.

/// Ce que Hugues a donné (gardé dans le fichier de Voxile ; jamais l'identifiant, le secret ni le jeton).
public struct ReglageShopify: Codable, Equatable, Sendable {
    /// « ma-boutique.myshopify.com ».
    public var boutique: String
    /// Le nom de la boutique (lu à la vérification).
    public var nom: String
    public init(boutique: String, nom: String) { self.boutique = boutique; self.nom = nom }
    /// « ma-boutique » : le nom court qui sert aux adresses de l'admin (admin.shopify.com/store/ma-boutique/…).
    public var poignee: String { String(boutique.prefix { $0 != "." }) }
}

/// Ce qui ouvre l'API : un jeton d'une ancienne app (`shpat_…`), ou l'identifiant et le secret d'une app du Dev Dashboard.
public enum IdentifiantsShopify: Equatable, Sendable {
    case jeton(String)
    case client(id: String, secret: String)

    /// Ce qui est rangé dans le Trousseau (une seule entrée) : le jeton, ou « identifiant:secret ».
    public var rangement: String {
        switch self {
        case .jeton(let j): return j
        case .client(let id, let s): return id + ":" + s
        }
    }
    public init?(rangement r: String) {
        let s = r.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("shpat_") { self = .jeton(s); return }
        guard let i = s.firstIndex(of: ":") else { return nil }
        let id = String(s[..<i]), secret = String(s[s.index(after: i)...])
        guard !id.isEmpty, !secret.isEmpty else { return nil }
        self = .client(id: id, secret: secret)
    }
    /// Ce qu'on montre masqué dans le détail : le jeton, ou le secret.
    public var secretMontre: String {
        switch self {
        case .jeton(let j): return j
        case .client(_, let s): return s
        }
    }
}

/// Le jeton de 24 h tiré de l'identifiant et du secret : en mémoire seulement, oublié au débranchement ou sur un refus.
public final class JetonShopify: @unchecked Sendable {
    private let verrou = NSLock()
    private var valeur: String?, echeance: Date?
    public init() {}
    func lire(_ t: Date) -> String? { verrou.withLock { (echeance.map { t < $0 } ?? false) ? valeur : nil } }
    func garder(_ v: String, echeance e: Date) { verrou.withLock { valeur = v; echeance = e } }
    public func oublier() { verrou.withLock { valeur = nil; echeance = nil } }
}

/// Une commande lue (aucune donnée de client).
public struct CommandeShopify: Equatable, Sendable {
    public var id: String
    /// « #1001 ».
    public var nom: String
    public var creee: Date
    public var annulee: Bool
    /// `displayFinancialStatus` : PAID, PENDING, AUTHORIZED, PARTIALLY_PAID, REFUNDED…
    public var paiement: String
    /// L'heure du dernier encaissement réussi (transaction SALE ou CAPTURE) ; nil : aucune lue.
    public var payeeLe: Date?
    public var montant: Decimal?
    public var devise: String
}

/// Un produit suivi dont le stock total est bas.
public struct StockShopify: Equatable, Sendable {
    public var id: String
    public var titre: String
    public var stock: Int
    public var modifie: Date
}

public struct ClientShopify: Sendable {
    /// La version de l'API Admin (une par trimestre, chacune tenue environ un an) : 2026-10, la dernière stable au 13/11/2026.
    public static let version = "2026-10"
    /// Deux requêtes par passage (les commandes, le stock) : un écart d'une demi-seconde, loin du seau de points de GraphQL.
    public static let ecart: TimeInterval = 0.5
    /// Un stock total à 3 ou moins : « stock bas » ; 0 ou moins : « rupture ».
    public static let seuilStock = 3
    public static let droits = "read_orders"
    /// Où créer l'app (Dev Dashboard) et où lire l'adresse de la boutique.
    public static let pageApp = URL(string: "https://dev.shopify.com/dashboard/")!
    public static let pageBoutique = URL(string: "https://admin.shopify.com/settings/domains")!

    let boutique: String
    let identifiants: IdentifiantsShopify
    let transport: TransportHTTP
    let espacement: EspacementRequetes
    let jeton: JetonShopify
    /// L'heure de la façade (le client est refait à chaque passage) : l'échéance du jeton se juge sur elle.
    let maintenant: Date

    public init(boutique: String, identifiants: IdentifiantsShopify, transport: TransportHTTP,
                espacement: EspacementRequetes = EspacementRequetes(ecart: ClientShopify.ecart), jeton: JetonShopify = JetonShopify(),
                maintenant: Date = Date()) {
        self.boutique = boutique; self.identifiants = identifiants; self.transport = transport; self.espacement = espacement
        self.jeton = jeton; self.maintenant = maintenant
    }

    // MARK: ce que Hugues colle

    /// L'adresse de la boutique, ramenée à « ma-boutique.myshopify.com ». Accepte « ma-boutique », « ma-boutique.myshopify.com »,
    /// « https://ma-boutique.myshopify.com/admin », et l'adresse de l'admin « admin.shopify.com/store/ma-boutique/… ». nil : illisible
    /// (un domaine à soi, « boutique.fr », ne sert pas : l'API ne répond que sur l'adresse en .myshopify.com).
    public static func boutique(depuis saisie: String) -> String? {
        var s = saisie.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for p in ["https://", "http://"] where s.hasPrefix(p) { s.removeFirst(p.count) }
        var poignee: String
        if s.hasPrefix("admin.shopify.com/store/") {
            poignee = String(s.dropFirst("admin.shopify.com/store/".count).prefix { $0 != "/" && $0 != "?" })
        } else {
            let hote = String(s.prefix { $0 != "/" && $0 != "?" })
            if hote.hasSuffix(".myshopify.com") { poignee = String(hote.dropLast(".myshopify.com".count)) }
            else if !hote.contains(".") { poignee = hote }
            else { return nil }
        }
        poignee = poignee.trimmingCharacters(in: .whitespaces)
        // le nom d'une boutique : lettres, chiffres, tirets (jamais rien qui change l'hôte de l'adresse)
        guard !poignee.isEmpty, poignee.count <= 60, !poignee.hasPrefix("-"),
              poignee.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else { return nil }
        return poignee + ".myshopify.com"
    }

    /// Un ancien jeton d'app de l'admin : « shpat_… ».
    public static func estJeton(_ saisie: String) -> Bool {
        let s = saisie.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.hasPrefix("shpat_") && s.count >= 30 && !s.contains(where: { $0.isWhitespace })
    }
    /// L'identifiant client d'une app (32 caractères hexadécimaux chez Shopify ; on refuse seulement l'évident).
    public static func identifiantVraisemblable(_ saisie: String) -> Bool {
        let s = saisie.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.count >= 16 && s.count <= 100 && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }
    /// Le secret client (« shpss_… » le plus souvent).
    public static func secretVraisemblable(_ saisie: String) -> Bool {
        let s = saisie.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.count >= 16 && !s.contains(where: { $0.isWhitespace }) && !s.contains(":")
    }

    // MARK: le jeton

    func adresse(_ chemin: String) -> URL { URL(string: "https://\(boutique)/admin/\(chemin)")! }

    /// La requête du jeton (client credentials) : un formulaire, jamais l'identifiant ni le secret dans l'adresse.
    func requeteJeton(id: String, secret: String) -> URLRequest {
        var r = URLRequest(url: adresse("oauth/access_token"))
        r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        var permis = CharacterSet.alphanumerics; permis.insert(charactersIn: "-._~")
        func e(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: permis) ?? "" }
        r.httpBody = Data("grant_type=client_credentials&client_id=\(e(id))&client_secret=\(e(secret))".utf8)
        return r
    }

    /// Le classement des refus de la demande de jeton.
    public static func erreurJeton(statut: Int, corps: [String: Any]?) -> ErreurApp? {
        let code = (corps?["error"] as? String) ?? ""
        if code == "shop_not_permitted" { return .droitsManquants(.shopify, "la boutique n\u{2019}est pas dans ton organisation Shopify") }
        if code == "invalid_client" || statut == 401 { return .cleRefusee(.shopify) }
        if statut == 404 { return .introuvable(.shopify) }
        if statut == 400 || statut == 403 { return .droitsManquants(.shopify, "installe d\u{2019}abord l\u{2019}app sur ta boutique") }
        return nil
    }

    func jetonValide() async throws(ErreurApp) -> String {
        switch identifiants {
        case .jeton(let j): return j
        case .client(let id, let secret):
            let t = maintenant
            if let j = jeton.lire(t) { return j }
            let o = try await ReponseHTTP.json(.shopify, requeteJeton(id: id, secret: secret), transport: transport, espacement: espacement,
                                                codeErreur: { $0["error"] as? String }, classer: Self.erreurJeton).objet
            guard let j = o["access_token"] as? String, !j.isEmpty else { throw .reponseIllisible(.shopify) }
            let duree = (o["expires_in"] as? NSNumber)?.doubleValue ?? 86_399
            // redemandé une minute avant l'échéance
            jeton.garder(j, echeance: t.addingTimeInterval(max(60, duree - 60)))
            return j
        }
    }

    // MARK: GraphQL

    func requeteGraphQL(_ requete: String, variables: [String: Any], jeton j: String) -> URLRequest {
        var r = URLRequest(url: adresse("api/\(Self.version)/graphql.json"))
        r.httpMethod = "POST"
        r.setValue(j, forHTTPHeaderField: "X-Shopify-Access-Token")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["query": requete, "variables": variables], options: [.sortedKeys])
        return r
    }

    /// Les erreurs d'une réponse GraphQL réussie (HTTP 200) : limite de points (THROTTLED), droit manquant (ACCESS_DENIED).
    public static func erreurGraphQL(_ o: [String: Any], droit: String = ClientShopify.droits) -> ErreurApp? {
        guard let erreurs = o["errors"] as? [[String: Any]], !erreurs.isEmpty else { return nil }
        let codes = erreurs.compactMap { ($0["extensions"] as? [String: Any])?["code"] as? String }
        if codes.contains("THROTTLED") { return .limite(.shopify, reessayerDans: 2) }
        if codes.contains("ACCESS_DENIED") { return .droitsManquants(.shopify, droit) }
        // des erreurs sans données : illisible ; avec des données (une erreur partielle), on lit ce qui est là
        return o["data"] is [String: Any] ? nil : .reponseIllisible(.shopify)
    }

    /// Une requête GraphQL ; un jeton de 24 h refusé (échu plus tôt, révoqué) est redemandé une fois.
    func graphql(_ requete: String, variables: [String: Any] = [:], droit: String = ClientShopify.droits) async throws(ErreurApp) -> [String: Any] {
        for essai in 0..<2 {
            let j = try await jetonValide()
            do throws(ErreurApp) {
                let o = try await ReponseHTTP.json(.shopify, requeteGraphQL(requete, variables: variables, jeton: j), transport: transport,
                                                    espacement: espacement, codeErreur: { _ in nil }, classer: { statut, _ in
                    statut == 403 ? .droitsManquants(.shopify, droit) : (statut == 402 || statut == 423 ? .refus(.shopify, statut) : nil)
                }).objet
                if let e = Self.erreurGraphQL(o, droit: droit) { throw e }
                guard let d = o["data"] as? [String: Any] else { throw ErreurApp.reponseIllisible(.shopify) }
                return d
            } catch {
                // un jeton de 24 h refusé : oublié et redemandé une fois (un ancien jeton `shpat_` refusé l'est pour de bon)
                if error == .cleRefusee(.shopify), essai == 0, case .client = identifiants { jeton.oublier(); continue }
                throw error
            }
        }
        throw .cleRefusee(.shopify)
    }

    /// Vérifie l'accès (le jeton, puis la boutique et le droit de lire les commandes) ; rend le nom de la boutique.
    public func verifier() async throws(ErreurApp) -> String {
        let d = try await graphql("{ shop { name } orders(first: 1) { nodes { id } } }")
        let nom = ((d["shop"] as? [String: Any])?["name"] as? String).map { Nouveaute.ligne($0) } ?? ""
        return nom.isEmpty ? boutique : nom
    }

    public static let requeteCommandes = """
    query Commandes($q: String!) { orders(first: 25, sortKey: UPDATED_AT, reverse: true, query: $q) { nodes { \
    id name createdAt cancelledAt displayFinancialStatus totalPriceSet { shopMoney { amount currencyCode } } \
    transactions(first: 10) { kind status processedAt } } } }
    """
    public static let requeteStock = """
    query Stock($q: String!) { products(first: 10, query: $q) { nodes { id title totalInventory tracksInventory updatedAt } } }
    """

    /// Le filtre des commandes : mises à jour après `depuis` (une commande payée est mise à jour).
    public static func filtreCommandes(depuis: Date) -> String {
        "updated_at:>'\(depuis.formatted(Date.ISO8601FormatStyle()))'"
    }
    public static let filtreStock = "inventory_total:<=\(seuilStock) status:active"

    /// Les commandes mises à jour depuis `depuis`, et les produits au stock bas (vide si la clé n'a pas `read_products` : facultatif).
    public func lire(depuis: Date) async throws(ErreurApp) -> (commandes: [CommandeShopify], stocks: [StockShopify]) {
        let d = try await graphql(Self.requeteCommandes, variables: ["q": Self.filtreCommandes(depuis: depuis)])
        guard let commandes = Self.analyserCommandes(d) else { throw .reponseIllisible(.shopify) }
        var stocks: [StockShopify] = []
        do throws(ErreurApp) {
            let s = try await graphql(Self.requeteStock, variables: ["q": Self.filtreStock], droit: "read_products")
            stocks = Self.analyserStocks(s) ?? []
        } catch {
            // pas de `read_products` : le stock n'est pas suivi, rien de plus ; toute autre erreur compte
            guard case .droitsManquants = error else { throw error }
        }
        return (commandes, stocks)
    }

    // MARK: logique pure (vérifiée par les contrôles sur des réponses d'exemple)

    /// « gid://shopify/Order/450789469 » → « 450789469 » (chiffres seulement : rien d'autre n'entre dans une adresse).
    public static func numero(_ gid: String) -> String { String(gid.split(separator: "/").last.map { $0.filter(\.isNumber) } ?? "") }

    public static func analyserCommandes(_ data: [String: Any]) -> [CommandeShopify]? {
        guard let noeuds = (data["orders"] as? [String: Any])?["nodes"] as? [[String: Any]] else { return nil }
        return noeuds.compactMap { o in
            guard let id = o["id"] as? String, let creee = ReponseHTTP.date(o["createdAt"] as? String) else { return nil }
            let argent = (o["totalPriceSet"] as? [String: Any])?["shopMoney"] as? [String: Any]
            let encaisse = ((o["transactions"] as? [[String: Any]]) ?? []).filter {
                ($0["status"] as? String) == "SUCCESS" && ["SALE", "CAPTURE"].contains($0["kind"] as? String ?? "")
            }.compactMap { ReponseHTTP.date($0["processedAt"] as? String) }.max()
            return CommandeShopify(id: id, nom: Nouveaute.ligne((o["name"] as? String) ?? ""), creee: creee, annulee: o["cancelledAt"] is String,
                                   paiement: (o["displayFinancialStatus"] as? String) ?? "", payeeLe: encaisse,
                                   montant: Montant.valeur(argent?["amount"] as? String), devise: (argent?["currencyCode"] as? String) ?? "")
        }
    }

    public static func analyserStocks(_ data: [String: Any]) -> [StockShopify]? {
        guard let noeuds = (data["products"] as? [String: Any])?["nodes"] as? [[String: Any]] else { return nil }
        return noeuds.compactMap { p in
            guard let id = p["id"] as? String, p["tracksInventory"] as? Bool == true, let n = (p["totalInventory"] as? NSNumber)?.intValue,
                  n <= seuilStock, let quand = ReponseHTTP.date(p["updatedAt"] as? String) else { return nil }
            let titre = Nouveaute.ligne((p["title"] as? String) ?? "")
            return StockShopify(id: id, titre: titre.isEmpty ? "Produit sans nom" : titre, stock: n, modifie: quand)
        }
    }

    /// Une commande en nouveauté, ou nil (rien de neuf pour elle dans la fenêtre, ou annulée). Payée dans la fenêtre : « payée » (une
    /// seule annonce, même si elle vient d'être passée) ; passée dans la fenêtre sans être payée : « nouvelle » (sa paie, plus tard, est
    /// une autre nouveauté). Les clés ne se recoupent jamais : `commande:` et `payee:`.
    public static func nouveaute(_ c: CommandeShopify, reglage r: ReglageShopify, depuis: Date) -> Nouveaute? {
        guard !c.annulee else { return nil }
        let montant = c.montant.map { Montant.texte($0, devise: c.devise) }
        let titre = c.nom.isEmpty ? "Commande" : "Commande \(c.nom)"
        let action = ActionOuverture.adresse(URL(string: "https://admin.shopify.com/store/\(r.poignee)/orders/\(numero(c.id))")!)
        let nouvelle = c.creee > depuis
        if c.paiement == "PAID" {
            let payee = c.payeeLe ?? c.creee
            if payee > depuis {
                let sous = (nouvelle ? "Nouvelle, payée" : "Payée") + (montant.map { " \u{00B7} " + $0 } ?? "")
                return Nouveaute(id: "shopify:payee:\(numero(c.id))", app: .shopify, titre: titre, sousTitre: sous, date: payee, action: action)
            }
        }
        guard nouvelle else { return nil }
        return Nouveaute(id: "shopify:commande:\(numero(c.id))", app: .shopify, titre: titre,
                         sousTitre: "Nouvelle" + (montant.map { " \u{00B7} " + $0 } ?? ""), date: c.creee, action: action)
    }

    /// Un stock bas en nouveauté : annoncé une fois quand il passe sous le seuil, une autre fois s'il tombe à zéro.
    public static func nouveaute(_ s: StockShopify, reglage r: ReglageShopify) -> Nouveaute {
        let rupture = s.stock <= 0
        return Nouveaute(id: "shopify:stock:\(numero(s.id))@\(rupture ? "rupture" : "bas")", app: .shopify, titre: s.titre,
                         sousTitre: rupture ? "Rupture de stock" : "Stock bas : \(s.stock)", date: s.modifie,
                         action: .adresse(URL(string: "https://admin.shopify.com/store/\(r.poignee)/products/\(numero(s.id))")!))
    }
}
