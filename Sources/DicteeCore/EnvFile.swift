import Foundation

/// Lecture d'un fichier `.env` simple (une ligne `CLE=valeur`).
/// Gère `export CLE=...`, les guillemets simples ou doubles, les espaces et les fins de ligne Windows.
public enum EnvFile {
    public static func value(for key: String, in content: String) -> String? {
        for rawLine in content.split(whereSeparator: { $0 == "\n" || $0 == "\r\n" }) {
            var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("export ") { line = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let name = line[..<eq].trimmingCharacters(in: .whitespaces)
            guard name == key else { continue }
            var value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if value.count >= 2,
               let first = value.first, let last = value.last,
               (first == "\"" || first == "'"), first == last {
                value = String(value.dropFirst().dropLast())
            }
            return value.isEmpty ? nil : value
        }
        return nil
    }

    public static func load(key: String, fromFile path: String) -> String? {
        guard let content = try? String(contentsOfFile: (path as NSString).expandingTildeInPath, encoding: .utf8) else { return nil }
        return value(for: key, in: content)
    }
}
