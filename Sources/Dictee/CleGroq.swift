import Foundation
import Security
import DicteeCore

/// La clé Groq : rangée dans le Trousseau (Security framework). La lecture de ~/.config/groq/.env reste un repli.
/// Jamais affichée, jamais écrite dans le journal.
enum CleGroq {
    enum Etat: Equatable { case trousseau, fichier, absente }

    /// Les modes en ligne de commande (--transcrire, --nettoyer) ne touchent jamais au Trousseau : seulement le fichier .env.
    nonisolated(unsafe) static var utiliserTrousseau = true

    private static let service = "com.hugues.dictee"
    private static let compte = "groq"

    private static func requete() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: compte]
    }

    /// La clé du Trousseau, sinon celle du fichier d'environnement, sinon `nil`.
    static func lire() -> String? { lireTrousseau() ?? EnvFile.load(key: "GROQ_API_KEY", fromFile: "~/.config/groq/.env") }

    static var etat: Etat {
        if lireTrousseau() != nil { return .trousseau }
        return EnvFile.load(key: "GROQ_API_KEY", fromFile: "~/.config/groq/.env") != nil ? .fichier : .absente
    }

    private static func lireTrousseau() -> String? {
        guard utiliserTrousseau else { return nil }
        var q = requete()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var sortie: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &sortie) == errSecSuccess, let data = sortie as? Data,
              let cle = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !cle.isEmpty else { return nil }
        return cle
    }

    /// Range la clé dans le Trousseau (remplace l'ancienne). Renvoie `false` si le Trousseau refuse.
    @discardableResult
    static func enregistrer(_ cle: String) -> Bool {
        let propre = cle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !propre.isEmpty, let data = propre.data(using: .utf8) else { return false }
        SecItemDelete(requete() as CFDictionary)
        var q = requete()
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        let statut = SecItemAdd(q as CFDictionary, nil)
        if statut != errSecSuccess { Log.ecrire("clé Groq : Trousseau refuse l'écriture (code \(statut))") }
        return statut == errSecSuccess
    }

    static func effacer() { SecItemDelete(requete() as CFDictionary) }

    /// Une clé Groq ressemble à « gsk_… » ; on refuse seulement ce qui est évidemment autre chose (vide, avec espaces).
    static func vraisemblable(_ saisie: String) -> Bool {
        let s = saisie.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.count >= 20 && !s.contains(where: { $0.isWhitespace })
    }
}
