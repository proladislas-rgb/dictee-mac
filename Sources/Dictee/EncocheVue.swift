import AppKit
import SwiftUI

/// Mesures de l'encoche de l'écran (en points).
struct GeometrieEncoche: Equatable {
    var largeur: CGFloat = 200      // la caméra : on n'y dessine jamais rien
    var hauteur: CGFloat = 32       // hauteur de la barre des menus / de l'encoche
    /// Place de chaque côté de la caméra pour l'icône et les barres de son.
    static let aile: CGFloat = 90
    /// Largeur ajoutée en mains libres pour ✕ et ✓.
    static let rallongeMainsLibres: CGFloat = 64
    static let hauteurRuban: CGFloat = 24
    static let retraitRuban: CGFloat = 24
}

/// L'état affiché par l'encoche.
@MainActor
final class EncocheModele: ObservableObject {
    @Published var ouverte = false          // la bande est sortie
    @Published var ruban = false            // le ruban de texte est sorti
    @Published var mainsLibres = false
    @Published var texte = ""
    @Published var fige = false             // finalisation : tous les mots en blanc
    @Published var message: String?         // ex. « Champ protégé, texte copié »
    @Published var niveaux: [CGFloat] = Array(repeating: 0, count: 5)
    var icone: NSImage?
    var geometrie = GeometrieEncoche()
    var surAnnuler: () -> Void = {}
    var surValider: () -> Void = {}

    var largeurBande: CGFloat {
        guard ouverte else { return geometrie.largeur }
        return geometrie.largeur + 2 * GeometrieEncoche.aile + (mainsLibres ? GeometrieEncoche.rallongeMainsLibres : 0)
    }
    var hauteurRuban: CGFloat { ruban ? GeometrieEncoche.hauteurRuban : 0 }

    /// Niveau 0…1 du micro → cinq barres, avec un peu de hasard pour qu'elles vivent.
    func nouveauNiveau(_ n: Float) {
        let env: [CGFloat] = [0.6, 0.85, 1, 0.85, 0.6]
        for i in 0..<5 {
            let cible = CGFloat(n) * env[i] * (0.55 + 0.45 * CGFloat.random(in: 0...1))
            niveaux[i] = niveaux[i] * 0.45 + cible * 0.55
        }
    }
    func calmerLesBarres() { niveaux = Array(repeating: 0, count: 5) }
}

/// Une seule masse noire : la bande (hauteur de l'encoche) et, collé dessous, le ruban en retrait de 24 pt de chaque
/// côté, raccordé par des congés de 8 pt. Mêmes noirs, aucune coupure. Modèle : design/maquettes/encoche-v5.html.
struct FormeEncoche: Shape {
    var largeur: CGFloat
    var ruban: CGFloat
    var hauteurBande: CGFloat
    var largeurCamera: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(largeur, ruban) }
        set { largeur = newValue.first; ruban = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let k: CGFloat = 0.5522847498
        var p = Path()
        let x0 = rect.midX - largeur / 2, x1 = rect.midX + largeur / 2
        let H = hauteurBande
        let R = min(10 + 4 * min(1, max(0, (largeur - largeurCamera) / 180)), H / 2)
        // petit évasement en haut, de chaque côté, seulement quand la bande dépasse la caméra
        let ft = 8 * min(1, max(0, (largeur - largeurCamera) / 30))
        let r = max(0, ruban)
        let f = min(8, r * 0.4)
        let Rr = min(12, r * 0.5)
        let rx0 = x0 + GeometrieEncoche.retraitRuban, rx1 = x1 - GeometrieEncoche.retraitRuban

        /// Quart de cercle de centre `c`, du vecteur unitaire `u` au vecteur unitaire `v`.
        func quart(_ c: CGPoint, _ rayon: CGFloat, _ u: CGPoint, _ v: CGPoint) {
            let fin = CGPoint(x: c.x + rayon * v.x, y: c.y + rayon * v.y)
            let debut = CGPoint(x: c.x + rayon * u.x, y: c.y + rayon * u.y)
            p.addCurve(to: fin,
                       control1: CGPoint(x: debut.x + k * rayon * v.x, y: debut.y + k * rayon * v.y),
                       control2: CGPoint(x: fin.x + k * rayon * u.x, y: fin.y + k * rayon * u.y))
        }
        let haut = CGPoint(x: 0, y: -1), bas = CGPoint(x: 0, y: 1), gauche = CGPoint(x: -1, y: 0), droite = CGPoint(x: 1, y: 0)

        p.move(to: CGPoint(x: x0 - ft, y: 0))
        p.addLine(to: CGPoint(x: x1 + ft, y: 0))
        quart(CGPoint(x: x1 + ft, y: ft), ft, haut, gauche)                       // évasement haut droit
        p.addLine(to: CGPoint(x: x1, y: H - R))
        quart(CGPoint(x: x1 - R, y: H - R), R, droite, bas)                       // coin bas droit de la bande
        if r > 0.5 {
            p.addLine(to: CGPoint(x: rx1 + f, y: H))
            quart(CGPoint(x: rx1 + f, y: H + f), f, haut, gauche)                 // congé concave droit
            p.addLine(to: CGPoint(x: rx1, y: H + r - Rr))
            quart(CGPoint(x: rx1 - Rr, y: H + r - Rr), Rr, droite, bas)           // coin bas droit du ruban
            p.addLine(to: CGPoint(x: rx0 + Rr, y: H + r))
            quart(CGPoint(x: rx0 + Rr, y: H + r - Rr), Rr, bas, gauche)           // coin bas gauche du ruban
            p.addLine(to: CGPoint(x: rx0, y: H + f))
            quart(CGPoint(x: rx0 - f, y: H + f), f, droite, haut)                 // congé concave gauche
        }
        p.addLine(to: CGPoint(x: x0 + R, y: H))
        quart(CGPoint(x: x0 + R, y: H - R), R, bas, gauche)                       // coin bas gauche de la bande
        p.addLine(to: CGPoint(x: x0, y: ft))
        quart(CGPoint(x: x0 - ft, y: ft), ft, droite, haut)                       // évasement haut gauche
        p.closeSubpath()
        return p
    }
}

enum EncocheCouleurs {
    static let t1 = Color(red: 237/255, green: 237/255, blue: 237/255)
    static let t2 = Color(red: 161/255, green: 161/255, blue: 166/255)
    static let t3 = Color(red: 133/255, green: 133/255, blue: 139/255)
    static let k3 = Color(red: 42/255, green: 42/255, blue: 45/255)
}

struct EncocheVue: View {
    @ObservedObject var m: EncocheModele
    /// Taille de la fenêtre qui porte la vue.
    var tailleFenetre: CGSize

    var body: some View {
        let g = m.geometrie
        let largeur = m.largeurBande
        ZStack(alignment: .top) {
            FormeEncoche(largeur: largeur, ruban: m.hauteurRuban, hauteurBande: g.hauteur, largeurCamera: g.largeur)
                .fill(Color.black)
                .frame(width: tailleFenetre.width, height: tailleFenetre.height, alignment: .top)

            bande(g: g, largeur: largeur)
            rubanTexte(g: g, largeur: largeur)
        }
        .frame(width: tailleFenetre.width, height: tailleFenetre.height, alignment: .top)
    }

    /// Icône de l'app cible à gauche, barres de son à droite, ✕ ✓ en mains libres. Rien au centre : la caméra.
    private func bande(g: GeometrieEncoche, largeur: CGFloat) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                if m.mainsLibres {
                    BoutonBande(symbole: "xmark", couleur: EncocheCouleurs.t2, action: m.surAnnuler)
                        .padding(.trailing, 8)
                        .accessibilityLabel("Annuler (Échap)")
                        .transition(.opacity)
                }
                if let icone = m.icone {
                    Image(nsImage: icone).resizable().interpolation(.high).frame(width: 24, height: 24)
                } else {
                    Color.clear.frame(width: 24, height: 24)
                }
            }
            .frame(width: GeometrieEncoche.aile + (m.mainsLibres ? GeometrieEncoche.rallongeMainsLibres / 2 : 0) - 14, alignment: .leading)
            .padding(.leading, 14)

            Spacer(minLength: 0).frame(width: g.largeur)

            HStack(spacing: 0) {
                BarresDeSon(niveaux: m.niveaux)
                if m.mainsLibres {
                    BoutonBande(symbole: "checkmark", couleur: EncocheCouleurs.t1, action: m.surValider)
                        .padding(.leading, 8)
                        .accessibilityLabel("Valider")
                        .transition(.opacity)
                }
            }
            .frame(width: GeometrieEncoche.aile + (m.mainsLibres ? GeometrieEncoche.rallongeMainsLibres / 2 : 0) - 14, alignment: .trailing)
            .padding(.trailing, 14)
        }
        .frame(width: largeur, height: g.hauteur)
        .opacity(m.ouverte ? 1 : 0)
        .animation(.easeOut(duration: m.ouverte ? 0.18 : 0.08), value: m.ouverte)
    }

    private func rubanTexte(g: GeometrieEncoche, largeur: CGFloat) -> some View {
        let largeurTexte = largeur - 2 * GeometrieEncoche.retraitRuban - 32
        return Group {
            if let message = m.message {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(EncocheCouleurs.t1)
                    .lineLimit(1)
                    .frame(width: largeurTexte, height: GeometrieEncoche.hauteurRuban, alignment: .center)
            } else {
                TexteEnDirect(texte: m.texte, fige: m.fige, largeur: largeurTexte)
                    .frame(width: largeurTexte, height: GeometrieEncoche.hauteurRuban, alignment: .leading)
            }
        }
        .padding(.top, g.hauteur)
        .opacity(m.ruban ? 1 : 0)
        .animation(.easeOut(duration: 0.15), value: m.ruban)
    }
}

/// Cinq barres de 2 pt, de 3 à 16 pt de haut.
struct BarresDeSon: View {
    var niveaux: [CGFloat]
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(EncocheCouleurs.t1)
                    .frame(width: 2, height: 3 + 13 * min(1, max(0, niveaux[i] * 1.5)))
            }
        }
        .frame(height: 20)
        .accessibilityHidden(true)
    }
}

struct BoutonBande: View {
    var symbole: String
    var couleur: Color
    var action: () -> Void
    @State private var survol = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbole)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(survol ? EncocheCouleurs.t1 : couleur)
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(survol ? EncocheCouleurs.k3 : Color.clear))
        }
        .buttonStyle(.plain)
        .onHover { survol = $0 }
    }
}

/// Le texte du ruban : une ligne, les derniers mots visibles, les plus anciens qui s'effacent à gauche.
/// Les deux derniers mots restent gris tant qu'ils ne sont pas sûrs ; à la finalisation tout passe en blanc.
struct TexteEnDirect: View {
    var texte: String
    var fige: Bool
    var largeur: CGFloat

    private static let police = NSFont.systemFont(ofSize: 13)

    var body: some View {
        let mots = texte.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        let largeurTotale = (texte as NSString).size(withAttributes: [.font: Self.police]).width
        let debordement = max(0, largeurTotale - largeur)
        let fondu = min(36, debordement)
        Text(attribue(mots))
            .font(.system(size: 13))
            .lineLimit(1)
            .fixedSize()
            .frame(width: largeur, alignment: debordement > 0 ? .trailing : .leading)
            .mask(
                HStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing).frame(width: fondu)
                    Color.black
                }
            )
            .clipped()
            .accessibilityHidden(true)
    }

    private func attribue(_ mots: [String]) -> AttributedString {
        var sortie = AttributedString()
        for (i, mot) in mots.enumerated() {
            var a = AttributedString(mot + (i < mots.count - 1 ? " " : ""))
            let provisoire = !fige && i >= mots.count - 2
            a.foregroundColor = provisoire ? NSColor(srgbRed: 133/255, green: 133/255, blue: 139/255, alpha: 1) : NSColor(srgbRed: 237/255, green: 237/255, blue: 237/255, alpha: 1)
            sortie.append(a)
        }
        return sortie
    }
}
