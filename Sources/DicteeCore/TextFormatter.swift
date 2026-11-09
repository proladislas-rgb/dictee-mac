import Foundation

public enum AppKind: Equatable, Sendable {
    case terminal
    case browser
    case other
}

/// Mise en forme du texte selon l'app qui le reçoit. Fonctions pures, testées.
public enum TextFormatter {
    /// Terminaux : un retour à la ligne ferait partir la commande toute seule. VS Code est traité en entier
    /// comme un terminal (son terminal intégré ne se distingue pas sans lire l'arbre d'accessibilité).
    public static let terminalBundleIDs: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.mitchellh.ghostty",
        "net.kovidgoyal.kitty", "co.zeit.hyper", "org.alacritty", "com.github.wez.wezterm",
        "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.todesktop.230313mzl4w4u92",
    ]

    public static let browserBundleIDs: Set<String> = [
        "com.apple.Safari", "com.apple.SafariTechnologyPreview",
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary",
        "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition",
        "company.thebrowser.Browser", "com.microsoft.edgemac", "com.brave.Browser",
        "com.operasoftware.Opera", "com.vivaldi.Vivaldi",
    ]

    public static func kind(bundleID: String?) -> AppKind {
        guard let id = bundleID else { return .other }
        if terminalBundleIDs.contains(id) { return .terminal }
        if browserBundleIDs.contains(id) { return .browser }
        return .other
    }

    /// Mots d'une requête courte : en dessous, un navigateur reçoit le texte sans point final.
    public static let seuilRequeteCourte = 8

    public static func prepare(_ texte: String, for kind: AppKind) -> String {
        switch kind {
        case .terminal:
            return nettoyerPourTerminal(texte)
        case .browser:
            let propre = nettoyerEspaces(texte)
            return nombreDeMots(propre) < seuilRequeteCourte ? sansPointFinal(propre) : propre
        case .other:
            return nettoyerEspaces(texte)
        }
    }

    /// Texte brut sur une seule ligne, jamais de retour à la ligne (ni au milieu, ni à la fin).
    public static func nettoyerPourTerminal(_ texte: String) -> String {
        let uneLigne = texte.unicodeScalars.map { s -> Character in
            CharacterSet.newlines.contains(s) || s == "\u{2028}" || s == "\u{2029}" ? " " : Character(s)
        }
        return collapse(String(uneLigne)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Retire les espaces en trop (doubles, en bout de ligne, aux extrémités) en gardant les retours à la ligne.
    public static func nettoyerEspaces(_ texte: String) -> String {
        let lignes = texte.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { collapse($0).trimmingCharacters(in: .whitespaces) }
        return lignes.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func collapse(_ s: String) -> String {
        var sortie = ""
        var dernierEspace = false
        for c in s {
            if c == " " || c == "\t" || c == "\u{00A0}" {
                if !dernierEspace { sortie.append(" ") }
                dernierEspace = true
            } else {
                sortie.append(c)
                dernierEspace = false
            }
        }
        return sortie
    }

    public static func nombreDeMots(_ s: String) -> Int {
        s.split(whereSeparator: { $0.isWhitespace }).count
    }

    /// Retire un point final isolé (pas les points de suspension).
    public static func sansPointFinal(_ s: String) -> String {
        guard s.hasSuffix("."), !s.hasSuffix("..") else { return s }
        return String(s.dropLast())
    }
}
