import Foundation
import DicteeCore

/// Les mots que Whisper doit savoir écrire (noms propres, termes métier). Un mot par ligne dans
/// ~/Library/Application Support/Dictee/mots.txt — le fichier est créé préremplie au premier lancement.
enum Dictionnaire {
    static let motsParDefaut = ["Groq", "Whisper", "macOS"]

    static var url: URL { DossierVerbe.preparer("mots.txt") }

    static func creerSiAbsent() {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try? (motsParDefaut.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    static func mots() -> [String] {
        guard let contenu = try? String(contentsOf: url, encoding: .utf8) else { return motsParDefaut }
        return contenu.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    /// Réécrit la liste (un mot par ligne).
    static func enregistrer(_ mots: [String]) {
        try? (mots.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
