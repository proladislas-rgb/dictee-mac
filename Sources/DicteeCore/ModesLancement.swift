import Foundation

/// Comment l'exécutable a été lancé : la vraie app (aucune option, ou `--sans-interface` lancé par `open` pour vérifier la parole), ou
/// un mode de vérification en ligne de commande (`--ilot-essai`, `--rendu-…`, `--transcrire`…).
public enum ModesLancement {
    /// Les options de la vraie app : elles écrivent dans le vrai journal (~/Library/Logs/Dictee/dictee.log).
    static let optionsDeLApp: Set<String> = ["--sans-interface"]
    static let prefixesDeLApp = ["--duree=", "--verifier-parole="]

    /// Vrai : un mode de vérification. Son journal va dans un dossier temporaire, jamais dans le vrai journal de Hugues (12/11 : les
    /// « dossier inaccessible (errno 13) » d'un essai, mêlés à son usage réel, avaient été pris pour un vrai refus de Téléchargements).
    public static func journalAPart(_ arguments: [String]) -> Bool {
        arguments.dropFirst().contains { a in
            a.hasPrefix("--") && !optionsDeLApp.contains(a) && !prefixesDeLApp.contains(where: { a.hasPrefix($0) })
        }
    }

    /// Le journal des modes de vérification : un seul fichier dans le dossier temporaire de l'utilisateur (il tourne à 1 Mo comme le vrai).
    public static var journalTemporaire: URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("verbe-essais", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return dir.appendingPathComponent("dictee.log")
    }
}
