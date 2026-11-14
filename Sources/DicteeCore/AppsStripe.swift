import Foundation

// Stripe, par son API (https://docs.stripe.com/api), en lecture seule, avec une clé LIMITÉE (`rk_live_…` ou `rk_test_…`) créée dans le
// Dashboard (Développeurs › Clés API › « Créer une clé limitée »), avec seulement « Events » et « PaymentIntents » en lecture.
// Une clé secrète complète (`sk_…`) est refusée AVANT tout envoi : elle peut tout faire sur le compte (rembourser, virer), Voxile n'en
// a pas besoin. On lit les événements (`GET /v1/events`, gardés 30 jours par Stripe) de deux types : paiement reçu
// (`payment_intent.succeeded`) et paiement échoué (`payment_intent.payment_failed`), créés depuis le dernier passage.

/// Ce qu'on retient (dans le fichier de Voxile ; jamais la clé).
public struct ReglageStripe: Codable, Equatable, Sendable {
    /// Une clé du mode test (`rk_test_…`) : les paiements de test.
    public var test: Bool
    public init(test: Bool) { self.test = test }
}

public struct PaiementStripe: Equatable, Sendable {
    /// L'identifiant de l'événement (`evt_…`) : la clé de la nouveauté.
    public var evenement: String
    public var recu: Bool
    public var montant: Decimal
    public var devise: String
    public var description: String?
    /// Le paiement (`pi_…`), pour l'ouvrir dans le Dashboard.
    public var intention: String?
    public var cree: Date
    public var test: Bool
}

public struct ClientStripe: Sendable {
    public static let racine = URL(string: "https://api.stripe.com/v1/")!
    /// Bien sous la limite de Stripe (100 lectures par seconde en mode réel) : une requête par passage.
    public static let ecart: TimeInterval = 0.1
    public static let types = ["payment_intent.succeeded", "payment_intent.payment_failed"]
    public static let droits = "Events et PaymentIntents en lecture"
    public static let pageCle = URL(string: "https://dashboard.stripe.com/apikeys")!

    let cle: String
    let transport: TransportHTTP
    let espacement: EspacementRequetes

    public init(cle: String, transport: TransportHTTP, espacement: EspacementRequetes = EspacementRequetes(ecart: ClientStripe.ecart)) {
        self.cle = cle.trimmingCharacters(in: .whitespacesAndNewlines); self.transport = transport; self.espacement = espacement
    }

    /// Ce qui ne va pas dans une clé collée, avant tout envoi ; nil : une clé limitée vraisemblable. `sk_…` : trop puissante ;
    /// `pk_…` (publiable) ou autre : refusée.
    public static func controler(_ saisie: String) -> ErreurApp? {
        let s = saisie.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("sk_live_") || s.hasPrefix("sk_test_") { return .cleTropPuissante(.stripe) }
        guard s.hasPrefix("rk_live_") || s.hasPrefix("rk_test_"), s.count >= 30, !s.contains(where: { $0.isWhitespace }) else { return .cleRefusee(.stripe) }
        return nil
    }

    func requete(_ url: URL) -> URLRequest {
        var r = URLRequest(url: url)
        r.httpMethod = "GET"
        r.setValue("Bearer \(cle)", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        return r
    }

    /// 403 : la clé n'a pas le droit de lire les événements.
    public static func erreur(statut: Int, corps: [String: Any]?) -> ErreurApp? {
        statut == 403 ? .droitsManquants(.stripe, droits) : nil
    }

    private func envoyer(_ url: URL) async throws(ErreurApp) -> (objet: [String: Any], reponse: HTTPURLResponse) {
        try await ReponseHTTP.json(.stripe, requete(url), transport: transport, espacement: espacement,
                                   codeErreur: { ($0["error"] as? [String: Any])?["code"] as? String }, classer: Self.erreur)
    }

    /// L'adresse des événements : les deux types, créés après `depuis` (secondes Unix), 20 au plus (les plus récents d'abord).
    public static func adresseEvenements(depuis: Date?, limite: Int = 20) -> URL {
        var c = URLComponents(url: URL(string: "events", relativeTo: racine)!.absoluteURL, resolvingAgainstBaseURL: false)!
        var q = types.map { URLQueryItem(name: "types[]", value: $0) }
        if let d = depuis { q.append(URLQueryItem(name: "created[gt]", value: String(Int64(d.timeIntervalSince1970.rounded(.down))))) }
        q.append(URLQueryItem(name: "limit", value: String(limite)))
        c.queryItems = q
        return c.url!
    }

    /// Vérifie la clé (une lecture d'événement) : rend le mode (test ou réel, d'après la clé).
    public func verifier() async throws(ErreurApp) -> ReglageStripe {
        if let e = Self.controler(cle) { throw e }
        let o = try await envoyer(Self.adresseEvenements(depuis: nil, limite: 1)).objet
        guard o["object"] as? String == "list" else { throw .reponseIllisible(.stripe) }
        return ReglageStripe(test: cle.hasPrefix("rk_test_"))
    }

    /// Les paiements reçus ou échoués depuis `depuis`, et l'heure de Stripe à la réponse (le début de la fenêtre suivante).
    public func paiements(depuis: Date) async throws(ErreurApp) -> (paiements: [PaiementStripe], serveur: Date?) {
        let (o, r) = try await envoyer(Self.adresseEvenements(depuis: depuis))
        guard let p = Self.analyser(o) else { throw .reponseIllisible(.stripe) }
        return (p, ReponseHTTP.dateServeur(r))
    }

    // MARK: logique pure (vérifiée par les contrôles sur des réponses d'exemple)

    public static func analyser(_ o: [String: Any]) -> [PaiementStripe]? {
        guard o["object"] as? String == "list", let liste = o["data"] as? [[String: Any]] else { return nil }
        return liste.compactMap { e in
            guard let id = e["id"] as? String, let type = e["type"] as? String, types.contains(type),
                  let cree = (e["created"] as? NSNumber)?.doubleValue,
                  let pi = (e["data"] as? [String: Any])?["object"] as? [String: Any],
                  let devise = pi["currency"] as? String else { return nil }
            let recu = type == "payment_intent.succeeded"
            // reçu : ce qui est encaissé (`amount_received`) ; échoué : ce qui était demandé (`amount`)
            let unites = ((recu ? pi["amount_received"] : nil) as? NSNumber ?? pi["amount"] as? NSNumber)?.intValue ?? 0
            let desc = (pi["description"] as? String).map { Nouveaute.ligne($0, max: 60) }.flatMap { $0.isEmpty ? nil : $0 }
            return PaiementStripe(evenement: id, recu: recu, montant: Montant.depuisUnites(unites, devise: devise), devise: devise.uppercased(),
                                  description: desc, intention: pi["id"] as? String, cree: Date(timeIntervalSince1970: cree),
                                  test: e["livemode"] as? Bool == false)
        }
    }

    /// Un identifiant Stripe (`pi_…`, `evt_…`) : lettres, chiffres, « _ ».
    public static func identifiantPropre(_ id: String) -> String { String(id.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }) }

    public static func nouveaute(_ p: PaiementStripe) -> Nouveaute {
        var sous = Montant.texte(p.montant, devise: p.devise)
        if let d = p.description { sous += " \u{00B7} " + d }
        if p.test { sous += " \u{00B7} test" }
        let base = "https://dashboard.stripe.com/" + (p.test ? "test/" : "")
        let url = p.intention.map { URL(string: base + "payments/" + identifiantPropre($0))! } ?? URL(string: base + "payments")!
        return Nouveaute(id: "stripe:\(identifiantPropre(p.evenement))", app: .stripe, titre: p.recu ? "Paiement reçu" : "Paiement échoué",
                         sousTitre: sous, date: p.cree, action: .adresse(url))
    }
}
