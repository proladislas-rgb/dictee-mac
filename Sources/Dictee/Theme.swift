import AppKit
import SwiftUI
import CoreText

/// Palette du panneau B (design/chatgpt-v3/BRIEF-POUR-CLAUDE-CODE.md) : surfaces unies, aucun dégradé ni halo.
enum Palette {
    static let fondExterieur = Color(hex: 0x0B0B0B)
    static let surface = Color(hex: 0x1A1A19)
    static let selection = Color(hex: 0x262624)
    static let texte = Color(hex: 0xECE9E3)
    static let texte2 = Color(hex: 0xA8A59E)
    static let texte3 = Color(hex: 0x88857E)
    static let accent = Color(hex: 0xE6A04A)
    static let filet = Color(red: 236/255, green: 233/255, blue: 227/255).opacity(0.09)
    static let interrupteurEteint = Color(hex: 0x2F2F2D)
    static let nsAccent = NSColor(srgbRed: 230/255, green: 160/255, blue: 74/255, alpha: 1)
    static let nsSelectionCG = CGColor(srgbRed: 38/255, green: 38/255, blue: 36/255, alpha: 1)
    static let nsTexte = NSColor(srgbRed: 236/255, green: 233/255, blue: 227/255, alpha: 1)
    static let nsTexte3 = NSColor(srgbRed: 136/255, green: 133/255, blue: 126/255, alpha: 1)
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}

/// Polices : SF Pro (système) pour les commandes, Newsreader (licence OFL, embarquée dans Resources) pour le texte dicté,
/// les noms à retenir et les valeurs des raccourcis.
enum Polices {
    private static var enregistree = false

    /// Enregistre Newsreader pour ce processus. Dans l'app : Contents/Resources/Newsreader.ttf. Dans les modes de rendu
    /// lancés depuis le dépôt : Resources/Polices/ à côté des sources.
    static func enregistrer() {
        guard !enregistree else { return }
        enregistree = true
        let candidats = [
            Bundle.main.resourceURL?.appendingPathComponent("Newsreader.ttf"),
            URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Resources/Polices/Newsreader.ttf"),
        ].compactMap { $0 }
        guard let url = candidats.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            Log.ecrire("police Newsreader introuvable : serif du système à la place")
            return
        }
        var erreur: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &erreur) {
            Log.ecrire("police Newsreader : enregistrement refusé")
        }
    }

    static var newsreaderDisponible: Bool { NSFont(name: "Newsreader16pt-Regular", size: 15) != nil || NSFont(name: "Newsreader", size: 15) != nil }

    /// Texte dicté.
    static func texte(_ taille: CGFloat) -> Font {
        newsreaderDisponible ? .custom("Newsreader", size: taille) : .system(size: taille, design: .serif)
    }
    /// Commandes et métadonnées.
    static func commande(_ taille: CGFloat, _ poids: Font.Weight = .regular) -> Font { .system(size: taille, weight: poids) }
}
