import Foundation

// Notion, par son API officielle (https://developers.notion.com), avec une clé d'intégration interne collée une fois (rangée dans le
// Trousseau par la façade). On lit, dans UNE base que Hugues choisit : les tâches du jour (sa propriété date est aujourd'hui) et ce qui
// lui est assigné (sa propriété personne le contient). Lecture seule : aucune écriture dans Notion.

/// Ce que Hugues a choisi dans Notion (gardé dans le fichier de Voxile ; jamais la clé).
public struct ReglageNotion: Codable, Equatable, Sendable {
    public var baseId: String
    public var baseNom: String
    /// La propriété « date » de la base (échéance), et celle des personnes (« Assigné à ») ; nil : la base n'en a pas.
    public var proprieteDate: String?
    public var proprietePersonne: String?
    /// La personne dont on suit les tâches assignées (un utilisateur Notion ; une intégration interne ne sait pas qui est « moi »).
    public var personneId: String?
    public init(baseId: String, baseNom: String, proprieteDate: String? = nil, proprietePersonne: String? = nil, personneId: String? = nil) {
        self.baseId = baseId; self.baseNom = baseNom; self.proprieteDate = proprieteDate; self.proprietePersonne = proprietePersonne; self.personneId = personneId
    }
    /// Il y a de quoi filtrer : une date, ou une personne choisie avec sa propriété.
    public var complet: Bool { proprieteDate != nil || (proprietePersonne != nil && personneId != nil) }
}

/// Un choix proposé à Hugues (une base, une personne, une table) : un identifiant et un nom lisible.
public struct ChoixApp: Equatable, Sendable, Identifiable {
    public var id: String
    public var nom: String
    public init(id: String, nom: String) { self.id = id; self.nom = nom }
}

/// Une page de la base suivie.
public struct PageNotion: Equatable, Sendable {
    public var id: String
    public var titre: String
    public var url: URL?
    public var echeance: Date?
    /// L'échéance a une heure (sinon : un jour entier).
    public var avecHeure: Bool
    public var modifiee: Date
    /// Elle est arrivée par la date du jour (sinon : par la personne assignée).
    public var duJour: Bool
}

public struct ClientNotion: Sendable {
    public static let racine = URL(string: "https://api.notion.com/v1/")!
    /// La version de l'API (en-tête obligatoire). 2022-06-28 : `databases/{id}/query`, stable et documentée.
    public static let version = "2022-06-28"
    /// 3 requêtes par seconde en moyenne (limite de Notion) : un écart d'un tiers de seconde.
    public static let ecart: TimeInterval = 0.34

    let cle: String
    let transport: TransportHTTP
    let espacement: EspacementRequetes
    let fuseau: TimeZone

    public init(cle: String, transport: TransportHTTP, espacement: EspacementRequetes = EspacementRequetes(ecart: ClientNotion.ecart), fuseau: TimeZone = .current) {
        self.cle = cle.trimmingCharacters(in: .whitespacesAndNewlines); self.transport = transport; self.espacement = espacement; self.fuseau = fuseau
    }

    /// Une clé d'intégration Notion : « secret_… » (anciennes) ou « ntn_… » (depuis 2024), sans espace. On refuse seulement l'évident.
    public static func vraisemblable(_ saisie: String) -> Bool {
        let s = saisie.trimmingCharacters(in: .whitespacesAndNewlines)
        return (s.hasPrefix("secret_") || s.hasPrefix("ntn_")) && s.count >= 30 && !s.contains(where: { $0.isWhitespace })
    }

    func requete(_ chemin: String, corps: [String: Any]? = nil) -> URLRequest {
        var r = URLRequest(url: URL(string: chemin, relativeTo: Self.racine)!.absoluteURL)
        r.httpMethod = corps == nil ? "GET" : "POST"
        r.setValue("Bearer \(cle)", forHTTPHeaderField: "Authorization")
        r.setValue(Self.version, forHTTPHeaderField: "Notion-Version")
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        if let corps {
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try? JSONSerialization.data(withJSONObject: corps, options: [.sortedKeys])
        }
        return r
    }

    private func envoyer(_ r: URLRequest) async throws(ErreurApp) -> [String: Any] {
        try await ReponseHTTP.json(.notion, r, transport: transport, espacement: espacement, codeErreur: { $0["code"] as? String }).objet
    }

    /// Vérifie la clé (`GET /users/me`) : rend le nom de l'espace de travail (ou de l'intégration).
    public func verifier() async throws(ErreurApp) -> String {
        let o = try await envoyer(requete("users/me"))
        guard o["object"] as? String == "user" else { throw .reponseIllisible(.notion) }
        let bot = o["bot"] as? [String: Any]
        return (bot?["workspace_name"] as? String) ?? (o["name"] as? String) ?? "Notion"
    }

    /// Les bases que l'intégration voit (celles qu'on lui a partagées), pour le choix de Hugues.
    public func bases() async throws(ErreurApp) -> [ChoixApp] {
        let o = try await envoyer(requete("search", corps: ["filter": ["property": "object", "value": "database"], "page_size": 50]))
        return Self.analyserBases(o)
    }

    /// Les personnes de l'espace (pas les intégrations), pour « assigné à qui ».
    public func personnes() async throws(ErreurApp) -> [ChoixApp] {
        Self.analyserPersonnes(try await envoyer(requete("users?page_size=100")))
    }

    /// Lit la base choisie et propose un réglage : sa première propriété date, sa première propriété personne.
    public func reglage(base id: String) async throws(ErreurApp) -> ReglageNotion {
        guard let r = Self.analyserSchema(try await envoyer(requete("databases/\(Self.identifiantPropre(id))"))) else { throw .reponseIllisible(.notion) }
        return r
    }

    /// Les tâches du jour et celles assignées à la personne choisie, les plus récemment modifiées d'abord (25 au plus : une page).
    public func taches(_ reglage: ReglageNotion, maintenant: Date) async throws(ErreurApp) -> [PageNotion] {
        guard let corps = Self.filtre(reglage, jour: ReponseHTTP.jour(maintenant, fuseau: fuseau)) else { throw .reglageIncomplet(.notion) }
        let o = try await envoyer(requete("databases/\(Self.identifiantPropre(reglage.baseId))/query", corps: corps))
        guard let pages = Self.analyserPages(o, reglage: reglage, jour: ReponseHTTP.jour(maintenant, fuseau: fuseau), fuseau: fuseau) else {
            throw .reponseIllisible(.notion)
        }
        return pages
    }

    // MARK: logique pure (vérifiée par les contrôles sur des réponses d'exemple)

    /// Un identifiant Notion n'a que des chiffres hexadécimaux et des tirets : rien d'autre n'entre dans un chemin d'URL.
    public static func identifiantPropre(_ id: String) -> String { String(id.filter { $0.isHexDigit || $0 == "-" }) }

    /// Le corps de la requête : `ou` (date = aujourd'hui, personne contient), triée par dernière modification ; nil s'il n'y a rien à filtrer.
    public static func filtre(_ r: ReglageNotion, jour: String) -> [String: Any]? {
        var ou: [[String: Any]] = []
        if let p = r.proprieteDate { ou.append(["property": p, "date": ["equals": jour]]) }
        if let p = r.proprietePersonne, let qui = r.personneId { ou.append(["property": p, "people": ["contains": qui]]) }
        guard !ou.isEmpty else { return nil }
        let filtre: [String: Any] = ou.count == 1 ? ou[0] : ["or": ou]
        let tri: [[String: String]] = [["timestamp": "last_edited_time", "direction": "descending"]]
        return ["filter": filtre, "sorts": tri, "page_size": 25]
    }

    static func texteRiche(_ v: Any?) -> String {
        ((v as? [[String: Any]]) ?? []).compactMap { $0["plain_text"] as? String }.joined()
    }

    public static func analyserBases(_ o: [String: Any]) -> [ChoixApp] {
        ((o["results"] as? [[String: Any]]) ?? []).compactMap { b in
            guard b["object"] as? String == "database", let id = b["id"] as? String else { return nil }
            let nom = Nouveaute.ligne(texteRiche(b["title"]))
            return ChoixApp(id: id, nom: nom.isEmpty ? "Sans titre" : nom)
        }
    }

    public static func analyserPersonnes(_ o: [String: Any]) -> [ChoixApp] {
        ((o["results"] as? [[String: Any]]) ?? []).compactMap { u in
            guard u["type"] as? String == "person", let id = u["id"] as? String else { return nil }
            return ChoixApp(id: id, nom: (u["name"] as? String).map { Nouveaute.ligne($0) } ?? "Sans nom")
        }
    }

    /// Le schéma d'une base : son nom, sa première propriété date et sa première propriété personne (par ordre alphabétique : l'ordre
    /// d'un dictionnaire JSON n'est pas garanti, le choix doit être le même à chaque fois).
    public static func analyserSchema(_ o: [String: Any]) -> ReglageNotion? {
        guard o["object"] as? String == "database", let id = o["id"] as? String, let props = o["properties"] as? [String: Any] else { return nil }
        func premiere(_ type: String) -> String? {
            props.compactMap { (nom, v) in ((v as? [String: Any])?["type"] as? String) == type ? nom : nil }.sorted().first
        }
        let nom = Nouveaute.ligne(texteRiche(o["title"]))
        return ReglageNotion(baseId: id, baseNom: nom.isEmpty ? "Sans titre" : nom, proprieteDate: premiere("date"), proprietePersonne: premiere("people"))
    }

    /// Les pages d'une réponse de `query` ; nil : ce n'est pas une liste.
    public static func analyserPages(_ o: [String: Any], reglage: ReglageNotion, jour: String, fuseau: TimeZone = .current) -> [PageNotion]? {
        guard o["object"] as? String == "list", let res = o["results"] as? [[String: Any]] else { return nil }
        return res.compactMap { p in
            guard p["object"] as? String == "page", let id = p["id"] as? String, p["archived"] as? Bool != true, p["in_trash"] as? Bool != true,
                  let modifiee = ReponseHTTP.date(p["last_edited_time"] as? String) else { return nil }
            let props = (p["properties"] as? [String: Any]) ?? [:]
            let titreBrut = props.values.compactMap { $0 as? [String: Any] }.first { $0["type"] as? String == "title" }.map { texteRiche($0["title"]) } ?? ""
            let titre = Nouveaute.ligne(titreBrut)
            var echeance: Date?, avecHeure = false
            if let nomDate = reglage.proprieteDate, let d = (props[nomDate] as? [String: Any])?["date"] as? [String: Any], let debut = d["start"] as? String {
                echeance = ReponseHTTP.date(debut, fuseau: fuseau); avecHeure = debut.count > 10
            }
            // un jour seul se lit tel quel ; une date avec heure se compare au jour LOCAL (« 2026-11-13T23:30:00Z » est le 14 à Paris)
            let jourEcheance = echeance.map { ReponseHTTP.jour($0, fuseau: fuseau) }
            let url = (p["url"] as? String).flatMap(URL.init(string:)).flatMap { $0.scheme == "https" ? $0 : nil }
            return PageNotion(id: id, titre: titre.isEmpty ? "Sans titre" : titre, url: url, echeance: echeance,
                              avecHeure: echeance != nil && avecHeure,
                              modifiee: modifiee,
                              duJour: jourEcheance == jour)
        }
    }

    /// Une page en nouveauté. Une tâche du jour : sa clé tient le jour (annoncée une fois ce jour-là ; reportée à demain, de nouveau
    /// demain). Une tâche seulement assignée : annoncée une fois.
    public static func nouveaute(_ p: PageNotion, jour: String, heure: (Date) -> String) -> Nouveaute {
        let sous: String
        if p.duJour, p.avecHeure, let e = p.echeance { sous = "Aujourd\u{2019}hui \u{00B7} \(heure(e))" }
        else if p.duJour { sous = "Aujourd\u{2019}hui" }
        else { sous = "Assignée à toi" }
        let action: ActionOuverture = p.url.map { .adresse($0) } ?? .adresse(URL(string: "https://www.notion.so/\(identifiantPropre(p.id).replacingOccurrences(of: "-", with: ""))")!)
        return Nouveaute(id: p.duJour ? "notion:\(p.id)@\(jour)" : "notion:\(p.id)", app: .notion, titre: p.titre, sousTitre: sous, date: p.duJour ? (p.echeance ?? p.modifiee) : p.modifiee, action: action)
    }
}
