import AppKit
import SwiftUI
import CoreText

/// Palette du panneau B (design/chatgpt-v3/BRIEF-POUR-CLAUDE-CODE.md) : surfaces unies, aucun dégradé ni halo.
/// Chaque teinte a sa version claire, prise selon l'apparence de la vue : les panneaux de l'encoche imposent le sombre
/// (`darkAqua`) et ne changent pas ; seule la fenêtre principale suit le réglage clair / sombre (maquette lucarne-app-final.html).
enum Palette {
    static let fondExterieur = Color(clair: 0xF2F2F4, sombre: 0x0B0B0B)
    static let surface = Color(clair: 0xF8F5F0, sombre: 0x1A1A19)
    static let selection = Color(clair: 0xEFECE7, sombre: 0x262624)
    static let texte = Color(clair: 0x1D1D1F, sombre: 0xECE9E3)
    static let texte2 = Color(clair: 0x6C6C71, sombre: 0xA8A59E)
    static let texte3 = Color(clair: 0x86868B, sombre: 0x88857E)
    static let accent = Color(clair: 0xC2741A, sombre: 0xE6A04A)
    static let filet = Color(nsColor: .dynamique(clair: NSColor.black.withAlphaComponent(0.08), sombre: NSColor(srgbRed: 236/255, green: 233/255, blue: 227/255, alpha: 0.09)))
    /// Interrupteurs allumés, coches, « prêt ».
    static let vert = Color(clair: 0x2FB457, sombre: 0x30D158)
    /// Pastilles, touches (kbd) et onglet actif : un cran au-dessus de la sélection.
    static let relief = Color(clair: 0xE5E3DE, sombre: 0x2F2F2D)
    /// Contour des champs et boutons encadrés.
    static let contour = Color(nsColor: .dynamique(clair: NSColor.black.withAlphaComponent(0.13), sombre: NSColor(srgbRed: 236/255, green: 233/255, blue: 227/255, alpha: 0.16)))
    /// Texte sur un bouton plein (plein = la couleur du texte : sombre en clair, clair en sombre).
    static let surBouton = Color(clair: 0xFFFFFF, sombre: 0x0B0B0B)
    /// Un voile sur la surface (survol, choix, fond d'un champ) : blanc en sombre, noir plus léger en clair.
    static func voile(_ opacite: Double) -> Color {
        Color(nsColor: .dynamique(clair: NSColor.black.withAlphaComponent(opacite * 0.6), sombre: NSColor.white.withAlphaComponent(opacite)))
    }
    /// L'ombre d'une carte qui flotte : légère en clair, profonde en sombre.
    static let ombre = Color(nsColor: .dynamique(clair: NSColor.black.withAlphaComponent(0.14), sombre: NSColor.black.withAlphaComponent(0.55)))
    /// Les couleurs vives des pages reprises, plus soutenues en clair pour rester lisibles sur le blanc.
    static let orangeVif = Color(clair: 0xC76A00, sombre: 0xFFB340)
    static let vertDoux = Color(clair: 0x248A3D, sombre: 0x8FCF9A)
    static let bleuVif = Color(clair: 0x0A7AFF, sombre: 0x5EB0FF)
    static let nsAccent = NSColor.dynamique(clair: NSColor(hex: 0xC2741A), sombre: NSColor(srgbRed: 230/255, green: 160/255, blue: 74/255, alpha: 1))
    static let nsSelectionCG = CGColor(srgbRed: 38/255, green: 38/255, blue: 36/255, alpha: 1)
    static let nsTexte = NSColor.dynamique(clair: NSColor(hex: 0x1D1D1F), sombre: NSColor(srgbRed: 236/255, green: 233/255, blue: 227/255, alpha: 1))
    static let nsTexte3 = NSColor.dynamique(clair: NSColor(hex: 0x86868B), sombre: NSColor(srgbRed: 136/255, green: 133/255, blue: 126/255, alpha: 1))
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
    /// Une couleur qui suit l'apparence de la vue qui la dessine (claire ou sombre).
    static func dynamique(clair: NSColor, sombre: NSColor) -> NSColor {
        NSColor(name: nil) { a in a.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? sombre : clair }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
    /// Deux teintes : la claire pour l'apparence claire, la sombre sinon.
    init(clair: UInt32, sombre: UInt32) { self.init(nsColor: .dynamique(clair: NSColor(hex: clair), sombre: NSColor(hex: sombre))) }
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
    /// La même police pour AppKit (mesure du texte avant de le dessiner).
    static func nsTexte(_ taille: CGFloat) -> NSFont {
        if let f = NSFont(name: "Newsreader16pt-Regular", size: taille) ?? NSFont(name: "Newsreader", size: taille) { return f }
        let base = NSFont.systemFont(ofSize: taille)
        return base.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: taille) } ?? base
    }
    /// Commandes et métadonnées.
    static func commande(_ taille: CGFloat, _ poids: Font.Weight = .regular) -> Font { .system(size: taille, weight: poids) }
}
