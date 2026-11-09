import AppKit
import SwiftUI

/// Le signe de l'app : deux guillemets fermants (« ” ») dessinés en vectoriel, d'après la planche 05 du design.
/// Un seul dessin, une seule orientation, pour l'icône d'app, la barre des menus et la fenêtre.
enum Guillemets {
    /// Proportions d'un guillemet : largeur 1, hauteur `hauteurUnite`.
    static let hauteurUnite: CGFloat = 1.5
    /// Espace entre les deux guillemets.
    static let ecart: CGFloat = 0.10
    /// Rapport largeur / hauteur de la paire.
    static var rapport: CGFloat { (2 + ecart) / hauteurUnite }

    /// Un guillemet fermant dans le carré unité (x de 0 à 1, y vers le bas de 0 à `hauteurUnite`) : un bloc aux coins
    /// arrondis, une encoche en bas, et une queue en virgule dont la pointe tombe en bas à gauche.
    private static func unGuillemet(_ p: CGMutablePath, dx: CGFloat) {
        let r: CGFloat = 0.21
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: dx + x, y: y) }
        p.move(to: pt(r, 0))
        p.addLine(to: pt(1 - r, 0))
        p.addQuadCurve(to: pt(1, r), control: pt(1, 0))
        p.addLine(to: pt(1, 0.50))
        // dessous de la queue : une longue courbe vers la pointe
        p.addCurve(to: pt(0.28, 1.50), control1: pt(1, 0.98), control2: pt(0.64, 1.38))
        // dessus de la queue : remonte vers l'encoche
        p.addCurve(to: pt(0.41, 1.04), control1: pt(0.36, 1.40), control2: pt(0.43, 1.20))
        p.addQuadCurve(to: pt(0.33, 1.0), control: pt(0.40, 1.0))
        p.addLine(to: pt(0.10, 1.0))
        p.addQuadCurve(to: pt(0, 0.90), control: pt(0, 1.0))
        p.addLine(to: pt(0, r))
        p.addQuadCurve(to: pt(r, 0), control: pt(0, 0))
        p.closeSubpath()
    }

    /// La paire, ajustée à `rect` (centrée, proportions gardées, y vers le bas comme un contexte retourné).
    static func chemin(dans rect: CGRect) -> CGPath {
        let brut = CGMutablePath()
        unGuillemet(brut, dx: 0)
        unGuillemet(brut, dx: 1 + ecart)
        let largeur = 2 + ecart
        let echelle = min(rect.width / largeur, rect.height / hauteurUnite)
        var t = CGAffineTransform(translationX: rect.midX - largeur * echelle / 2, y: rect.midY - hauteurUnite * echelle / 2)
            .scaledBy(x: echelle, y: echelle)
        return brut.copy(using: &t) ?? brut
    }
}

/// La paire en forme SwiftUI (petit signe de la fenêtre).
struct FormeGuillemets: Shape {
    func path(in rect: CGRect) -> Path { Path(Guillemets.chemin(dans: rect)) }
}

/// Icône d'app : carré noir arrondi au format des icônes macOS (corps de 824 pt dans 1024 pt), guillemets clairs.
enum IconeApp {
    static let encre = CGColor(srgbRed: 236/255, green: 233/255, blue: 227/255, alpha: 1)

    /// Dessine l'icône dans un contexte de `cote` pixels de côté (origine en haut à gauche).
    static func dessiner(_ ctx: CGContext, cote: CGFloat) {
        let k = cote / 1024
        let corps = CGRect(x: 100 * k, y: 100 * k, width: 824 * k, height: 824 * k)
        let forme = RoundedRectangle(cornerRadius: 185 * k, style: .continuous).path(in: corps).cgPath
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10 * k), blur: 22 * k, color: CGColor(gray: 0, alpha: 0.28))
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.addPath(forme)
        ctx.fillPath()
        ctx.restoreGState()
        // guillemets : 62 % de la largeur du corps, un peu remontés pour que les queues ne tirent pas le signe vers le bas
        let largeur = 824 * k * 0.62
        let hauteur = largeur / Guillemets.rapport
        let zone = CGRect(x: corps.midX - largeur / 2, y: corps.midY - hauteur / 2 - 6 * k, width: largeur, height: hauteur)
        ctx.setFillColor(encre)
        ctx.addPath(Guillemets.chemin(dans: zone))
        ctx.fillPath()
    }

    static func pixels(cote: Int) -> NSBitmapImageRep? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: cote, pixelsHigh: cote, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let gc = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        let ctx = gc.cgContext
        // contexte retourné : origine en haut à gauche, comme les chemins ci-dessus
        ctx.translateBy(x: 0, y: CGFloat(cote))
        ctx.scaleBy(x: 1, y: -1)
        dessiner(ctx, cote: CGFloat(cote))
        return rep
    }
}

/// Icône de la barre des menus : guillemets monochromes (suivent la couleur de la barre), 18 pt de haut au plus.
/// Pendant la capture : un fin trait ambre à côté du signe.
enum IconeBarre {
    static let ambre = NSColor(srgbRed: 230/255, green: 160/255, blue: 74/255, alpha: 1)
    static let taille = NSSize(width: 26, height: 18)

    /// Image de la barre des menus. Au repos : image « template » (le système la teinte). En capture : image dessinée
    /// avec la couleur du texte de la barre (le trait ambre ne peut pas être teinté).
    static func image(capture: Bool) -> NSImage {
        let image = NSImage(size: taille, flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let largeur: CGFloat = 15.5
            let hauteur = largeur / Guillemets.rapport
            let decalage: CGFloat = capture ? -2.5 : 0
            let zone = CGRect(x: rect.midX - largeur / 2 + decalage, y: rect.midY - hauteur / 2 - 0.2, width: largeur, height: hauteur)
            let encre: NSColor = capture ? (NSColor.controlTextColor.usingColorSpace(.sRGB) ?? .white) : .black
            ctx.setFillColor(encre.cgColor)
            ctx.addPath(Guillemets.chemin(dans: zone))
            ctx.fillPath()
            if capture {
                let trait = CGRect(x: zone.maxX + 3.2, y: rect.midY - 5.5, width: 1.7, height: 11)
                ctx.setFillColor(ambre.cgColor)
                ctx.addPath(CGPath(roundedRect: trait, cornerWidth: 0.85, cornerHeight: 0.85, transform: nil))
                ctx.fillPath()
            }
            return true
        }
        image.isTemplate = !capture
        image.accessibilityDescription = "Verbe"
        return image
    }
}
