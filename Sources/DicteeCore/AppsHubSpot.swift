import Foundation

// HubSpot, par l'API CRM v3 (https://developers.hubspot.com/docs), en lecture seule.
//
// La clé (doc relue le 13/11/2026) : les « private apps » ne se créent plus depuis le 26 octobre 2026 (celles qui existent marchent
// encore, leur jeton `pat-…` est accepté). Le chemin sans outil de développement : une « clé de service » (Développement › Clés ›
// Clés de service › « Créer une clé de service »), avec les droits `crm.objects.contacts.read` et `crm.objects.deals.read`. Elle se
// présente aussi en `pat-…` et s'envoie en `Authorization: Bearer`.
//
// On lit : les contacts créés depuis le dernier passage (recherche CRM sur `createdate`) ; les affaires modifiées depuis (recherche sur
// `hs_lastmodifieddate`), dont on relit l'historique de l'étape (`propertiesWithHistory: dealstage`, lecture groupée) pour ne garder que
// celles qui ont CHANGÉ D'ÉTAPE dans la fenêtre (gagnée, perdue, ou une autre étape). Les noms des étapes viennent des pipelines.
// Limites : la recherche, 5 requêtes par seconde et par compte, 200 résultats par page ; un objet tout juste créé peut mettre quelques
// instants à y apparaître (d'où une fenêtre qui recouvre la précédente de 2 minutes ; le dédoublonnage s'en charge).

/// Ce qu'on retient du compte (dans le fichier de Voxile ; jamais la clé).
public struct ReglageHubSpot: Codable, Equatable, Sendable {
    /// Le numéro du compte (« portail ») : il sert aux adresses des fiches ; nil : inconnu (on ouvre l'accueil de HubSpot).
    public var portail: Int?
    /// « app.hubspot.com », ou « app-eu1.hubspot.com » pour un compte hébergé en Europe.
    public var domaine: String
    /// La devise du compte (celle d'une affaire sans devise à elle).
    public var devise: String?
    public init(portail: Int?, domaine: String, devise: String?) { self.portail = portail; self.domaine = domaine; self.devise = devise }
}

/// Une étape de pipeline : son nom, et si elle ferme l'affaire (gagnée ou perdue).
public struct EtapeHubSpot: Equatable, Sendable {
    public var nom: String
    public var gagnee: Bool
    public var perdue: Bool
    public init(nom: String, gagnee: Bool = false, perdue: Bool = false) { self.nom = nom; self.gagnee = gagnee; self.perdue = perdue }
}

public struct ContactHubSpot: Equatable, Sendable {
    public var id: String
    public var nom: String
    public var cree: Date
}

public struct AffaireHubSpot: Equatable, Sendable {
    public var id: String
    public var nom: String
    public var montant: Decimal?
    public var devise: String?
    public var etape: String
    public var creee: Date?
    /// L'heure où l'affaire est entrée dans son étape actuelle (historique de `dealstage`) ; nil : pas encore lue.
    public var entreeEtape: Date?
}

public struct ClientHubSpot: Sendable {
    public static let racine = URL(string: "https://api.hubapi.com/")!
    /// La recherche : 5 requêtes par seconde et par compte. Un écart d'un quart de seconde.
    public static let ecart: TimeInterval = 0.25
    public static let droitContacts = "crm.objects.contacts.read", droitAffaires = "crm.objects.deals.read"
    /// La doc des clés de service (l'endroit où les créer est dans le compte de chacun : Développement › Clés).
    public static let pageCle = URL(string: "https://developers.hubspot.com/docs/apps/developer-platform/build-apps/authentication/account-service-keys")!
    /// Les étapes du pipeline par défaut, si les pipelines n'ont pas pu être lus.
    public static let etapesParDefaut: [String: EtapeHubSpot] = ["closedwon": EtapeHubSpot(nom: "Gagnée", gagnee: true), "closedlost": EtapeHubSpot(nom: "Perdue", perdue: true)]

    let cle: String
    let transport: TransportHTTP
    let espacement: EspacementRequetes

    public init(cle: String, transport: TransportHTTP, espacement: EspacementRequetes = EspacementRequetes(ecart: ClientHubSpot.ecart)) {
        self.cle = cle.trimmingCharacters(in: .whitespacesAndNewlines); self.transport = transport; self.espacement = espacement
    }

    /// Une clé de service ou un jeton d'app privée : « pat-na1-… », « pat-eu1-… », sans espace.
    public static func vraisemblable(_ saisie: String) -> Bool {
        let s = saisie.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.hasPrefix("pat-") && s.count >= 30 && !s.contains(where: { $0.isWhitespace })
    }
    /// Le domaine de l'interface d'après la clé (« pat-eu1-… » : un compte en Europe).
    public static func domaine(cle: String) -> String {
        let p = cle.split(separator: "-")
        if p.count > 2, p[1].hasPrefix("eu") { return "app-\(p[1]).hubspot.com" }
        return "app.hubspot.com"
    }
    /// Un identifiant d'objet HubSpot : des chiffres.
    public static func identifiantPropre(_ id: String) -> String { id.filter(\.isNumber) }

    func requete(_ chemin: String, corps: [String: Any]? = nil) -> URLRequest {
        var r = URLRequest(url: URL(string: chemin, relativeTo: Self.racine)!.absoluteURL)
        r.httpMethod = corps == nil ? "GET" : "POST"
        r.setValue("Bearer \(cle)", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        if let corps {
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try? JSONSerialization.data(withJSONObject: corps, options: [.sortedKeys])
        }
        return r
    }

    /// Le classement propre à HubSpot : 403 « MISSING_SCOPES » = le droit `droit` manque.
    public static func erreur(statut: Int, corps: [String: Any]?, droit: String) -> ErreurApp? {
        guard statut == 403 else { return nil }
        let categorie = corps?["category"] as? String
        return categorie == nil || categorie == "MISSING_SCOPES" ? .droitsManquants(.hubspot, droit) : .refus(.hubspot, 403)
    }

    private func envoyer(_ r: URLRequest, droit: String) async throws(ErreurApp) -> [String: Any] {
        try await ReponseHTTP.json(.hubspot, r, transport: transport, espacement: espacement, codeErreur: { $0["category"] as? String },
                                   classer: { Self.erreur(statut: $0, corps: $1, droit: droit) }).objet
    }

    /// Vérifie la clé et ses deux droits (une lecture d'un contact, d'une affaire), puis lit le compte (numéro, domaine, devise : sans
    /// droit particulier ; si la lecture échoue, on s'en passe).
    public func verifier() async throws(ErreurApp) -> ReglageHubSpot {
        _ = try await envoyer(requete("crm/v3/objects/contacts?limit=1"), droit: Self.droitContacts)
        _ = try await envoyer(requete("crm/v3/objects/deals?limit=1"), droit: Self.droitAffaires)
        let compte = try? await envoyer(requete("account-info/v3/details"), droit: "")
        return Self.analyserCompte(compte ?? [:], cle: cle)
    }

    public func etapes() async throws(ErreurApp) -> [String: EtapeHubSpot] {
        Self.analyserEtapes(try await envoyer(requete("crm/v3/pipelines/deals"), droit: Self.droitAffaires))
    }

    /// Le corps d'une recherche : `propriete` après `depuis` (en millisecondes), les plus récents d'abord, 20 au plus.
    public static func recherche(_ propriete: String, depuis: Date, proprietes: [String]) -> [String: Any] {
        let ms = String(Int64((depuis.timeIntervalSince1970 * 1000).rounded(.down)))
        return ["filterGroups": [["filters": [["propertyName": propriete, "operator": "GT", "value": ms]]]],
                "sorts": [["propertyName": propriete, "direction": "DESCENDING"]],
                "properties": proprietes, "limit": 20]
    }

    public func contacts(depuis: Date) async throws(ErreurApp) -> [ContactHubSpot] {
        let o = try await envoyer(requete("crm/v3/objects/contacts/search", corps: Self.recherche("createdate", depuis: depuis,
                                                                                                    proprietes: ["firstname", "lastname", "email", "createdate"])),
                                  droit: Self.droitContacts)
        guard let c = Self.analyserContacts(o) else { throw .reponseIllisible(.hubspot) }
        return c
    }

    /// Les affaires modifiées depuis `depuis`, avec l'heure d'entrée dans leur étape (historique relu par lecture groupée).
    public func affaires(depuis: Date) async throws(ErreurApp) -> [AffaireHubSpot] {
        let o = try await envoyer(requete("crm/v3/objects/deals/search", corps: Self.recherche("hs_lastmodifieddate", depuis: depuis,
            proprietes: ["dealname", "amount", "deal_currency_code", "dealstage", "pipeline", "createdate"])), droit: Self.droitAffaires)
        guard var affaires = Self.analyserAffaires(o) else { throw .reponseIllisible(.hubspot) }
        guard !affaires.isEmpty else { return [] }
        let corps: [String: Any] = ["inputs": affaires.map { ["id": $0.id] }, "properties": ["dealstage"], "propertiesWithHistory": ["dealstage"]]
        let h = try await envoyer(requete("crm/v3/objects/deals/batch/read", corps: corps), droit: Self.droitAffaires)
        let entrees = Self.analyserHistorique(h)
        for i in affaires.indices { affaires[i].entreeEtape = entrees[affaires[i].id] }
        return affaires
    }

    // MARK: logique pure (vérifiée par les contrôles sur des réponses d'exemple)

    public static func analyserCompte(_ o: [String: Any], cle: String) -> ReglageHubSpot {
        let portail = (o["portalId"] as? NSNumber)?.intValue
        let ui = (o["uiDomain"] as? String).flatMap { d -> String? in
            d.hasSuffix(".hubspot.com") && d.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == ".") }) ? d : nil
        }
        return ReglageHubSpot(portail: portail, domaine: ui ?? domaine(cle: cle), devise: o["companyCurrency"] as? String)
    }

    /// Les étapes de tous les pipelines d'affaires : gagnée = fermée à 100 % ; perdue = fermée à 0 %.
    public static func analyserEtapes(_ o: [String: Any]) -> [String: EtapeHubSpot] {
        var r: [String: EtapeHubSpot] = [:]
        for p in (o["results"] as? [[String: Any]]) ?? [] {
            for e in (p["stages"] as? [[String: Any]]) ?? [] {
                guard let id = e["id"] as? String else { continue }
                let meta = (e["metadata"] as? [String: Any]) ?? [:]
                let fermee = "\(meta["isClosed"] ?? "false")" == "true"
                let proba = Double("\(meta["probability"] ?? "")")
                r[id] = EtapeHubSpot(nom: Nouveaute.ligne((e["label"] as? String) ?? id, max: 40), gagnee: fermee && proba == 1, perdue: fermee && proba == 0)
            }
        }
        return r
    }

    public static func analyserContacts(_ o: [String: Any]) -> [ContactHubSpot]? {
        guard let res = o["results"] as? [[String: Any]] else { return nil }
        return res.compactMap { c in
            guard let id = c["id"] as? String else { return nil }
            let p = (c["properties"] as? [String: Any]) ?? [:]
            guard let cree = ReponseHTTP.date(p["createdate"] as? String) ?? ReponseHTTP.date(c["createdAt"] as? String) else { return nil }
            let nom = Nouveaute.ligne([p["firstname"] as? String, p["lastname"] as? String].compactMap { $0 }.joined(separator: " "))
            let email = Nouveaute.ligne((p["email"] as? String) ?? "")
            return ContactHubSpot(id: identifiantPropre(id), nom: !nom.isEmpty ? nom : (!email.isEmpty ? email : "Contact sans nom"), cree: cree)
        }
    }

    public static func analyserAffaires(_ o: [String: Any]) -> [AffaireHubSpot]? {
        guard let res = o["results"] as? [[String: Any]] else { return nil }
        return res.compactMap { a in
            guard let id = a["id"] as? String else { return nil }
            let p = (a["properties"] as? [String: Any]) ?? [:]
            let nom = Nouveaute.ligne((p["dealname"] as? String) ?? "")
            return AffaireHubSpot(id: identifiantPropre(id), nom: nom.isEmpty ? "Affaire sans nom" : nom, montant: Montant.valeur(p["amount"] as? String),
                                  devise: (p["deal_currency_code"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                                  etape: (p["dealstage"] as? String) ?? "", creee: ReponseHTTP.date(p["createdate"] as? String), entreeEtape: nil)
        }
    }

    /// L'heure d'entrée dans l'étape actuelle de chaque affaire : la plus récente des valeurs de l'historique de `dealstage`.
    public static func analyserHistorique(_ o: [String: Any]) -> [String: Date] {
        var r: [String: Date] = [:]
        for a in (o["results"] as? [[String: Any]]) ?? [] {
            guard let id = a["id"] as? String else { continue }
            let h = ((a["propertiesWithHistory"] as? [String: Any])?["dealstage"] as? [[String: Any]]) ?? []
            if let d = h.compactMap({ ReponseHTTP.date($0["timestamp"] as? String) }).max() { r[identifiantPropre(id)] = d }
        }
        return r
    }

    static func adresse(_ r: ReglageHubSpot, objet: String, id: String) -> URL {
        guard let p = r.portail else { return URL(string: "https://\(r.domaine)/")! }
        return URL(string: "https://\(r.domaine)/contacts/\(p)/record/\(objet)/\(identifiantPropre(id))")!
    }

    public static func nouveaute(_ c: ContactHubSpot, reglage r: ReglageHubSpot) -> Nouveaute {
        Nouveaute(id: "hubspot:contact:\(c.id)", app: .hubspot, titre: c.nom, sousTitre: "Nouveau contact", date: c.cree,
                  action: .adresse(adresse(r, objet: "0-1", id: c.id)))
    }

    /// Une affaire qui a changé d'étape dans la fenêtre (ou qui vient d'être créée) ; nil sinon (modifiée sans changer d'étape). Sa clé
    /// tient l'étape et l'heure d'entrée : repassée plus tard dans la même étape, c'est une autre nouveauté.
    public static func nouveaute(_ a: AffaireHubSpot, etapes: [String: EtapeHubSpot], reglage r: ReglageHubSpot, depuis: Date) -> Nouveaute? {
        guard let entree = a.entreeEtape, entree > depuis, !a.etape.isEmpty else { return nil }
        let e = etapes[a.etape] ?? etapesParDefaut[a.etape]
        let montant = a.montant.flatMap { m in (a.devise ?? r.devise).map { Montant.texte(m, devise: $0) } }
        let sous: String
        if e?.gagnee == true { sous = "Gagnée" + (montant.map { " \u{00B7} " + $0 } ?? "") }
        else if e?.perdue == true { sous = "Perdue" }
        else if let c = a.creee, c > depuis { sous = "Nouvelle" + (e.map { " \u{00B7} " + $0.nom } ?? "") }
        else { sous = e.map { "Étape : " + $0.nom } ?? "Change d\u{2019}étape" }
        let ms = Int64((entree.timeIntervalSince1970 * 1000).rounded())
        return Nouveaute(id: "hubspot:affaire:\(a.id)@\(a.etape)@\(ms)", app: .hubspot, titre: a.nom, sousTitre: sous, date: entree,
                         action: .adresse(adresse(r, objet: "0-3", id: a.id)))
    }
}
