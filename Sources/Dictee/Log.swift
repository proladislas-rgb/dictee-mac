import Foundation
import DicteeCore

/// Journal horodaté : ~/Library/Logs/Dictee/dictee.log
/// Règles : jamais la clé Groq, jamais plus de 30 caractères du texte dicté (voir `Log.apercu`) ; seule exception, la ligne
/// « texte Groq → texte final » (60 caractères de chaque côté autour de la première différence, voir `ComparaisonJournal`).
enum Log {
    /// Les essais le remplacent par un fichier temporaire avant la première ligne : jamais le vrai journal de Hugues.
    nonisolated(unsafe) static var url: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Dictee", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("dictee.log")
    }()

    private static let queue = DispatchQueue(label: "dictee.log")
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()
    private static let maxBytes = 1_000_000

    /// Faux après une désinstallation : plus rien ne doit recréer le dossier du journal.
    nonisolated(unsafe) private static var actif = true

    static func ecrire(_ message: String) {
        guard actif else { return }
        let ligne = "\(formatter.string(from: Date())) | \(message)\n"
        queue.async {
            guard actif else { return }
            let fm = FileManager.default
            // le journal est lisible par Hugues seul (0600) : créé ainsi, et un ancien journal en 0644 y est ramené
            if let attrs = try? fm.attributesOfItem(atPath: url.path) {
                if let size = attrs[.size] as? Int, size > maxBytes {
                    let old = url.deletingLastPathComponent().appendingPathComponent("dictee.log.1")
                    try? fm.removeItem(at: old)
                    try? fm.moveItem(at: url, to: old)
                    try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: old.path)
                } else if let droits = attrs[.posixPermissions] as? Int, droits != 0o600 {
                    try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                }
            }
            if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) }
            guard let handle = try? FileHandle(forWritingTo: url), let data = ligne.data(using: .utf8) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        }
    }

    /// Aperçu autorisé du texte dicté (30 caractères au plus).
    static func apercu(_ texte: String) -> String { TextPreview.preview(texte) }

    /// Attend que les écritures en attente soient faites (avant de quitter).
    static func vider() { queue.sync {} }

    /// Vide les écritures en attente puis arrête le journal pour de bon (désinstallation).
    static func desactiver() { queue.sync { actif = false } }
}
