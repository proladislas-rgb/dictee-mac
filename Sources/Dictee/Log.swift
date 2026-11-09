import Foundation
import DicteeCore

/// Journal horodaté : ~/Library/Logs/Dictee/dictee.log
/// Règles : jamais la clé Groq, jamais plus de 30 caractères du texte dicté (voir `Log.apercu`).
enum Log {
    static let url: URL = {
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

    static func ecrire(_ message: String) {
        let ligne = "\(formatter.string(from: Date())) | \(message)\n"
        queue.async {
            let fm = FileManager.default
            if let attrs = try? fm.attributesOfItem(atPath: url.path), let size = attrs[.size] as? Int, size > maxBytes {
                let old = url.deletingLastPathComponent().appendingPathComponent("dictee.log.1")
                try? fm.removeItem(at: old)
                try? fm.moveItem(at: url, to: old)
            }
            if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
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
}
