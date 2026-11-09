import Foundation

/// Nature d'un mot du lexique : elle sert à choisir les mots qui comptent selon l'app qui reçoit la dictée
/// (noms de personnes et de sociétés dans un mail, termes techniques dans un terminal).
public enum TypeMot: String, Codable, Sendable {
    case nom        // Brillonia, Orléans : majuscule initiale
    case sigle      // CEE, TRA-SE-104 : majuscules
    case technique  // supabase, macOS, bas-carbone : minuscules ou majuscule intérieure
}

/// Un mot du lexique local : écrit tel qu'il doit apparaître, avec sa fréquence dans les sources de Hugues.
public struct EntreeLexique: Codable, Equatable, Sendable {
    public var mot: String
    public var frequence: Int
    /// Nombre de documents différents où le mot apparaît.
    public var documents: Int
    /// Source principale (nom de dossier, jamais un chemin complet).
    public var source: String
    /// `fr`, `en` ou `autre`.
    public var langue: String
    public var type: TypeMot

    public init(mot: String, frequence: Int, documents: Int = 1, source: String, langue: String = "autre", type: TypeMot) {
        self.mot = mot; self.frequence = frequence; self.documents = documents; self.source = source; self.langue = langue; self.type = type
    }
}

/// Le lexique : `~/Library/Application Support/Dictee/lexique.json`. Il contient des noms de la vie de Hugues et ne va jamais dans git.
public struct Lexique: Codable, Equatable, Sendable {
    public var version = 1
    public var construitLe: Date
    public var entrees: [EntreeLexique]

    public init(construitLe: Date = Date(), entrees: [EntreeLexique] = []) {
        self.construitLe = construitLe; self.entrees = entrees
    }

    public func donnees() -> Data? {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; e.dateEncodingStrategy = .iso8601
        return try? e.encode(self)
    }

    public static func depuis(_ donnees: Data) -> Lexique? {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return try? d.decode(Lexique.self, from: donnees)
    }
}

/// Mots que Whisper écrit déjà bien et qui feraient perdre de la place dans le prompt (sigles ultra courants).
public enum MotsTropCourants {
    public static let sigles: Set<String> = [
        "api", "url", "pdf", "html", "css", "json", "http", "https", "sql", "csv", "ui", "ux", "ok", "faq", "todo", "id", "ia", "ai",
        "gps", "usb", "wifi", "sms", "mms", "tva", "ttc", "ht", "rdv", "cv", "tv", "pc", "os", "ios", "cpu", "gpu", "ram", "ssd",
        "png", "jpg", "jpeg", "gif", "svg", "xml", "yaml", "md", "txt", "uuid", "cli", "sdk", "ide", "lts", "iso", "ean", "iban",
        "siret", "siren", "rgpd", "git", "npm", "dns", "ssl", "tls", "ssh", "ftp", "smtp", "imap", "rss", "seo", "crm",
    ]
}
