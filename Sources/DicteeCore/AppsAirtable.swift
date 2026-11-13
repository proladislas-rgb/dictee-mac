import Foundation

// Airtable, par son API officielle (https://airtable.com/developers/web/api), avec un jeton d'accès personnel collé une fois (rangé dans
// le Trousseau par la façade). On lit, dans UNE table que Hugues choisit, les fiches modifiées depuis le dernier passage. Lecture seule.
//
// Droits du jeton : `data.records:read` (lire les fiches) et `schema.bases:read` (lister bases et tables pour le choix).
//
// « Modifiées depuis » : la formule `IS_AFTER(LAST_MODIFIED_TIME(), …)`. Les fenêtres se suivent sur l'horloge d'Airtable (l'en-tête
// « Date » de la réponse précédente) : ni trou ni chevauchement, même si l'horloge du Mac dérive.

/// Ce que Hugues a choisi dans Airtable (gardé dans le fichier de Voxile ; jamais le jeton).
public struct ReglageAirtable: Codable, Equatable, Sendable {
    public var baseId: String
    public var baseNom: String
    public var tableId: String
    public var tableNom: String
    /// Le champ principal (le nom d'une fiche), par identifiant.
    public var champTitre: String?
    /// Un champ « Dernière modification » s'il y en a un (type `lastModifiedTime`) : la vraie heure de la modification.
    public var champModification: String?
    public init(baseId: String, baseNom: String, tableId: String, tableNom: String, champTitre: String? = nil, champModification: String? = nil) {
        self.baseId = baseId; self.baseNom = baseNom; self.tableId = tableId; self.tableNom = tableNom
        self.champTitre = champTitre; self.champModification = champModification
    }
}

/// Une fiche modifiée.
public struct FicheAirtable: Equatable, Sendable {
    public var id: String
    public var titre: String
    /// L'heure de la modification (champ « Dernière modification ») ; nil : la table n'en a pas.
    public var modifiee: Date?
    public init(id: String, titre: String, modifiee: Date?) { self.id = id; self.titre = titre; self.modifiee = modifiee }
}

/// Une table proposée au choix, avec ce qu'il faut pour la suivre.
public struct TableAirtable: Equatable, Sendable {
    public var id: String
    public var nom: String
    public var champTitre: String?
    public var champModification: String?
    public init(id: String, nom: String, champTitre: String?, champModification: String?) {
        self.id = id; self.nom = nom; self.champTitre = champTitre; self.champModification = champModification
    }
}

public struct ClientAirtable: Sendable {
    public static let racine = URL(string: "https://api.airtable.com/v0/")!
    /// 5 requêtes par seconde et par base (limite d'Airtable) : un écart d'un cinquième de seconde (et un peu plus).
    public static let ecart: TimeInterval = 0.22
    /// Les droits nécessaires.
    public static let droits = ["data.records:read", "schema.bases:read"]

    let cle: String
    let transport: TransportHTTP
    let espacement: EspacementRequetes

    public init(cle: String, transport: TransportHTTP, espacement: EspacementRequetes = EspacementRequetes(ecart: ClientAirtable.ecart)) {
        self.cle = cle.trimmingCharacters(in: .whitespacesAndNewlines); self.transport = transport; self.espacement = espacement
    }

    /// Un jeton d'accès personnel : « pat… » suivi d'un point et d'une partie secrète, sans espace.
    public static func vraisemblable(_ saisie: String) -> Bool {
        let s = saisie.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.hasPrefix("pat") && s.contains(".") && s.count >= 40 && !s.contains(where: { $0.isWhitespace })
    }

    /// Un identifiant Airtable (« app… », « tbl… », « fld… ») : lettres et chiffres seulement, rien d'autre n'entre dans un chemin.
    public static func identifiantPropre(_ id: String) -> String { String(id.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }) }

    func requete(_ url: URL) -> URLRequest {
        var r = URLRequest(url: url)
        r.httpMethod = "GET"
        r.setValue("Bearer \(cle)", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        return r
    }

    private func envoyer(_ url: URL) async throws(ErreurApp) -> (objet: [String: Any], reponse: HTTPURLResponse) {
        // le code d'erreur d'Airtable : {"error": {"type": "…"}} ou {"error": "NOT_FOUND"}
        try await ReponseHTTP.json(.airtable, requete(url), transport: transport, espacement: espacement, codeErreur: {
            ($0["error"] as? [String: Any])?["type"] as? String ?? $0["error"] as? String
        })
    }

    /// Vérifie le jeton (`GET /meta/whoami`) et ses droits. Rend l'adresse du compte si le jeton la donne, sinon « Airtable ».
    public func verifier() async throws(ErreurApp) -> String {
        let o = try await envoyer(URL(string: "meta/whoami", relativeTo: Self.racine)!.absoluteURL).objet
        guard o["id"] is String else { throw .reponseIllisible(.airtable) }
        if let manquants = Self.droitsManquants(o) { throw .droitsManquants(.airtable, manquants) }
        return (o["email"] as? String) ?? "Airtable"
    }

    /// Les droits qui manquent, d'après `scopes` (nil : rien ne manque, ou le jeton ne dit pas ses droits).
    public static func droitsManquants(_ whoami: [String: Any]) -> String? {
        guard let scopes = whoami["scopes"] as? [String] else { return nil }
        let manque = droits.filter { !scopes.contains($0) }
        return manque.isEmpty ? nil : manque.joined(separator: ", ")
    }

    public func bases() async throws(ErreurApp) -> [ChoixApp] {
        Self.analyserBases(try await envoyer(URL(string: "meta/bases", relativeTo: Self.racine)!.absoluteURL).objet)
    }

    public func tables(base: String) async throws(ErreurApp) -> [TableAirtable] {
        let url = URL(string: "meta/bases/\(Self.identifiantPropre(base))/tables", relativeTo: Self.racine)!.absoluteURL
        return Self.analyserTables(try await envoyer(url).objet)
    }

    /// Les fiches modifiées après `depuis` (20 au plus), et l'heure d'Airtable à la réponse (le début de la fenêtre suivante).
    public func modifiees(_ r: ReglageAirtable, depuis: Date) async throws(ErreurApp) -> (fiches: [FicheAirtable], serveur: Date?) {
        let (o, reponse) = try await envoyer(Self.adresseModifiees(r, depuis: depuis))
        guard let fiches = Self.analyserFiches(o, reglage: r) else { throw .reponseIllisible(.airtable) }
        return (fiches, ReponseHTTP.dateServeur(reponse))
    }

    // MARK: logique pure (vérifiée par les contrôles sur des réponses d'exemple)

    public static func formule(depuis: Date) -> String {
        "IS_AFTER(LAST_MODIFIED_TIME(), DATETIME_PARSE('\(ReponseHTTP.iso(depuis))'))"
    }

    /// L'adresse de la liste : la formule, 20 fiches, les champs par identifiant (un champ renommé ne casse rien), triées par le champ
    /// « Dernière modification » s'il existe.
    public static func adresseModifiees(_ r: ReglageAirtable, depuis: Date) -> URL {
        var c = URLComponents(url: URL(string: "\(identifiantPropre(r.baseId))/\(identifiantPropre(r.tableId))", relativeTo: racine)!.absoluteURL,
                              resolvingAgainstBaseURL: false)!
        var q = [URLQueryItem(name: "filterByFormula", value: formule(depuis: depuis)),
                 URLQueryItem(name: "pageSize", value: "20"),
                 URLQueryItem(name: "returnFieldsByFieldId", value: "true")]
        if let m = r.champModification {
            q.append(URLQueryItem(name: "sort[0][field]", value: identifiantPropre(m)))
            q.append(URLQueryItem(name: "sort[0][direction]", value: "desc"))
        }
        c.queryItems = q
        // URLComponents laisse « + » tel quel : un serveur le lirait comme une espace
        c.percentEncodedQuery = c.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return c.url!
    }

    public static func analyserBases(_ o: [String: Any]) -> [ChoixApp] {
        ((o["bases"] as? [[String: Any]]) ?? []).compactMap { b in
            guard let id = b["id"] as? String, let nom = b["name"] as? String else { return nil }
            return ChoixApp(id: id, nom: Nouveaute.ligne(nom))
        }
    }

    public static func analyserTables(_ o: [String: Any]) -> [TableAirtable] {
        ((o["tables"] as? [[String: Any]]) ?? []).compactMap { t in
            guard let id = t["id"] as? String, let nom = t["name"] as? String else { return nil }
            let champs = (t["fields"] as? [[String: Any]]) ?? []
            let modif = champs.first { $0["type"] as? String == "lastModifiedTime" }?["id"] as? String
            return TableAirtable(id: id, nom: Nouveaute.ligne(nom), champTitre: t["primaryFieldId"] as? String, champModification: modif)
        }
    }

    /// Une valeur de champ en texte d'une ligne : texte, nombre, liste (liens, choix multiples), collaborateur (`name`), pièce jointe
    /// (`filename`).
    static func texte(_ v: Any?) -> String {
        switch v {
        case let s as String: return s
        case let n as NSNumber: return n.stringValue
        case let l as [Any]: return l.map { texte($0) }.filter { !$0.isEmpty }.joined(separator: ", ")
        case let o as [String: Any]: return (o["name"] as? String) ?? (o["filename"] as? String) ?? (o["email"] as? String) ?? ""
        default: return ""
        }
    }

    /// Les fiches d'une réponse ; nil : ce n'est pas une liste de fiches.
    public static func analyserFiches(_ o: [String: Any], reglage: ReglageAirtable) -> [FicheAirtable]? {
        guard let res = o["records"] as? [[String: Any]] else { return nil }
        return res.compactMap { f in
            guard let id = f["id"] as? String else { return nil }
            let champs = (f["fields"] as? [String: Any]) ?? [:]
            let titre = Nouveaute.ligne(reglage.champTitre.map { texte(champs[$0]) } ?? "")
            let modif = reglage.champModification.flatMap { ReponseHTTP.date(champs[$0] as? String) }
            return FicheAirtable(id: id, titre: titre.isEmpty ? "Fiche sans nom" : titre, modifiee: modif)
        }
    }

    /// Une fiche en nouveauté. Sa clé : la fiche et l'heure de SA modification (champ « Dernière modification ») ; sans ce champ, la
    /// fenêtre où on l'a vue changer (les fenêtres ne se chevauchent pas). Une fiche modifiée de nouveau plus tard est une autre nouveauté.
    public static func nouveaute(_ f: FicheAirtable, reglage r: ReglageAirtable, fenetre: Date, vue: Date) -> Nouveaute {
        let quand = f.modifiee ?? vue
        let url = URL(string: "https://airtable.com/\(identifiantPropre(r.baseId))/\(identifiantPropre(r.tableId))/\(identifiantPropre(f.id))")!
        return Nouveaute(id: "airtable:\(f.id)@\(ReponseHTTP.iso(f.modifiee ?? fenetre))", app: .airtable, titre: f.titre,
                         sousTitre: "Modifiée \u{00B7} \(r.tableNom)", date: quand, action: .adresse(url))
    }
}
