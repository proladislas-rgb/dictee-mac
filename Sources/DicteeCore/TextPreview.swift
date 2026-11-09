import Foundation

public enum TextPreview {
    /// Aperçu pour le journal : jamais plus de 30 caractères du texte dicté, retours à la ligne aplatis.
    public static func preview(_ text: String, limit: Int = 30) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
        if flat.count <= limit { return flat }
        return String(flat.prefix(limit)) + "…"
    }
}
