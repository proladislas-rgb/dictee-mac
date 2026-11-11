import AppKit
import SwiftUI

/// Mesures de l'encoche de l'écran (en points).
struct GeometrieEncoche: Equatable {
    var largeur: CGFloat = 200      // la caméra : on n'y dessine jamais rien
    var hauteur: CGFloat = 32       // hauteur de la barre des menus / de l'encoche
    /// Une vraie encoche (caméra) ; faux : une caméra fictive (écran externe, MacBook fermé), où l'îlot vide n'existe pas.
    var reelle = true
    /// Place de chaque côté de la caméra pour l'icône et les barres de son.
    static let aile: CGFloat = 90
    /// Largeur ajoutée en mains libres pour ✕ et ✓.
    static let rallongeMainsLibres: CGFloat = 64
    static let hauteurRuban: CGFloat = 22
    /// Retrait du ruban par rapport à la bande, de chaque côté (au moins rayon du coin + congé).
    static let retraitRuban: CGFloat = 18
    /// Durée de l'ouverture et du retrait (design : 180 à 220 ms), du fondu de stabilisation (100 à 140 ms)
    /// et du fondu bref de « Réduire les animations ».
    static let dureeMouvement: Double = 0.2
    static let dureeFondu: Double = 0.12
}

extension GeometrieEncoche {
    /// Mesures de l'écran principal (celui de la barre des menus) : l'encoche réelle si elle existe (zones libres
    /// à gauche et à droite de la caméra, jamais des dimensions copiées d'une image), sinon une caméra fictive.
    @MainActor
    static func mesurer(_ ecran: NSScreen) -> (GeometrieEncoche, centreX: CGFloat) {
        var g = GeometrieEncoche()
        var centre = ecran.frame.midX
        if let gauche = ecran.auxiliaryTopLeftArea, let droite = ecran.auxiliaryTopRightArea, ecran.safeAreaInsets.top > 0 {
            g.largeur = max(100, ecran.frame.width - gauche.width - droite.width)
            g.hauteur = ecran.safeAreaInsets.top
            centre = ecran.frame.minX + gauche.width + g.largeur / 2
        } else {
            g.reelle = false
            g.hauteur = max(24, ecran.frame.maxY - ecran.visibleFrame.maxY)
        }
        return (g, centre)
    }
}

/// L'état affiché par l'encoche.
@MainActor
final class EncocheModele: ObservableObject {
    @Published var ouverte = false          // la bande est sortie
    /// « Réduire les animations » : pas d'expansion, un fondu bref à la place.
    var reduire = false
    @Published var ruban = false            // le ruban de texte est sorti
    @Published var mainsLibres = false
    @Published var texte = ""
    @Published var fige = false             // finalisation : tous les mots en blanc
    @Published var message: String?         // ex. « Champ protégé, texte copié »
    /// Place laissée libre à droite du texte du ruban (la mini-miniature de la lecture s'y loge pendant une dictée).
    @Published var reserveRuban: CGFloat = 0
    @Published var niveaux: [CGFloat] = Array(repeating: 0, count: 5)
    var icone: NSImage?
    var geometrie = GeometrieEncoche()
    var surAnnuler: () -> Void = {}
    var surValider: () -> Void = {}

    /// Largeur de la bande de base (sans les boutons du mode mains libres) : c'est aussi celle du ruban.
    var largeurDeBase: CGFloat {
        guard ouverte || reduire else { return geometrie.largeur }
        return geometrie.largeur + 2 * GeometrieEncoche.aile
    }
    /// Seule la bande s'élargit en mains libres ; le ruban garde sa largeur.
    var largeurBande: CGFloat { largeurDeBase + (mainsLibres ? GeometrieEncoche.rallongeMainsLibres : 0) }
    var hauteurRuban: CGFloat { ruban ? GeometrieEncoche.hauteurRuban : 0 }
    /// Opacité d'ensemble : toujours 1, sauf en « Réduire les animations » où l'apparition est un fondu.
    var opacite: Double { reduire ? (ouverte ? 1 : 0) : 1 }

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

/// Une seule masse noire, d'après la planche 03 du design : la bande (hauteur de la barre des menus) a, en haut, des
/// congés concaves qui la raccordent au bord de l'écran, et des coins bas arrondis ; le ruban d'une ligne est soudé
/// dessous, en retrait, par des congés concaves. Le centre (la caméra) n'est jamais dessiné à part : c'est du noir.
struct FormeEncoche: Shape {
    var largeur: CGFloat          // bande
    var ruban: CGFloat            // hauteur du ruban
    var largeurRuban: CGFloat
    var hauteurBande: CGFloat
    var largeurCamera: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat> {
        get { AnimatablePair(AnimatablePair(largeur, ruban), largeurRuban) }
        set { largeur = newValue.first.first; ruban = newValue.first.second; largeurRuban = newValue.second }
    }

    /// Rayon des coins bas de la bande.
    static let rayonBande: CGFloat = 9
    /// Congé du haut : étendue horizontale et verticale.
    static let congeHaut = CGSize(width: 18, height: 10)

    func path(in rect: CGRect) -> Path {
        let k: CGFloat = 0.5522847498
        var p = Path()
        let x0 = rect.midX - largeur / 2, x1 = rect.midX + largeur / 2
        let H = hauteurBande
        let R = min(Self.rayonBande, H / 2)
        // les congés du haut n'existent que quand la bande dépasse la caméra
        let ouverture = min(1, max(0, (largeur - largeurCamera) / 30))
        let fw = Self.congeHaut.width * ouverture, fh = Self.congeHaut.height * ouverture
        let r = max(0, ruban)
        let f = min(8, r * 0.4)
        let Rr = min(11, r * 0.5)
        let rx0 = rect.midX - largeurRuban / 2 + GeometrieEncoche.retraitRuban
        let rx1 = rect.midX + largeurRuban / 2 - GeometrieEncoche.retraitRuban

        /// Quart d'ellipse de centre `c` et de rayons `rx`, `ry`, du vecteur unitaire `u` au vecteur unitaire `v`.
        func quart(_ c: CGPoint, _ rx: CGFloat, _ ry: CGFloat, _ u: CGPoint, _ v: CGPoint) {
            let debut = CGPoint(x: c.x + rx * u.x, y: c.y + ry * u.y)
            let fin = CGPoint(x: c.x + rx * v.x, y: c.y + ry * v.y)
            p.addCurve(to: fin,
                       control1: CGPoint(x: debut.x + k * rx * v.x, y: debut.y + k * ry * v.y),
                       control2: CGPoint(x: fin.x + k * rx * u.x, y: fin.y + k * ry * u.y))
        }
        func quart(_ c: CGPoint, _ rayon: CGFloat, _ u: CGPoint, _ v: CGPoint) { quart(c, rayon, rayon, u, v) }
        let haut = CGPoint(x: 0, y: -1), bas = CGPoint(x: 0, y: 1), gauche = CGPoint(x: -1, y: 0), droite = CGPoint(x: 1, y: 0)

        p.move(to: CGPoint(x: x0 - fw, y: 0))
        p.addLine(to: CGPoint(x: x1 + fw, y: 0))
        quart(CGPoint(x: x1 + fw, y: fh), fw, fh, haut, gauche)                   // congé haut droit
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
        p.addLine(to: CGPoint(x: x0, y: fh))
        quart(CGPoint(x: x0 - fw, y: fh), fw, fh, droite, haut)                   // congé haut gauche
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
            FormeEncoche(largeur: largeur, ruban: m.hauteurRuban, largeurRuban: m.largeurDeBase, hauteurBande: g.hauteur, largeurCamera: g.largeur)
                .fill(Color.black)
                .frame(width: tailleFenetre.width, height: tailleFenetre.height, alignment: .top)

            bande(g: g, largeur: largeur)
            rubanTexte(g: g, largeur: m.largeurDeBase)
        }
        .frame(width: tailleFenetre.width, height: tailleFenetre.height, alignment: .top)
        .opacity(m.opacite)
        .animation(.easeOut(duration: GeometrieEncoche.dureeFondu), value: m.opacite)
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
        .animation(.easeOut(duration: m.ouverte ? 0.14 : 0.08), value: m.ouverte)
    }

    private func rubanTexte(g: GeometrieEncoche, largeur: CGFloat) -> some View {
        let largeurTexte = largeur - 2 * GeometrieEncoche.retraitRuban - 24 - m.reserveRuban
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
        .frame(width: largeur - 2 * GeometrieEncoche.retraitRuban - 24, alignment: .leading)
        .padding(.top, g.hauteur)
        .opacity(m.ruban ? 1 : 0)
        .animation(.easeOut(duration: 0.2), value: m.reserveRuban)
        .animation(.easeOut(duration: GeometrieEncoche.dureeFondu), value: m.ruban)
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
    private static let blanc = NSColor(srgbRed: 237/255, green: 237/255, blue: 237/255, alpha: 1)
    private static let gris = NSColor(srgbRed: 133/255, green: 133/255, blue: 139/255, alpha: 1)

    var body: some View {
        let mots = texte.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        let largeurTotale = (texte as NSString).size(withAttributes: [.font: Self.police]).width + 5
        let debordement = max(0, largeurTotale - largeur)
        let fondu = min(36, debordement)
        // Deux couches superposées : l'une avec les derniers mots en gris, l'autre toute blanche. À la finalisation,
        // la seconde apparaît en fondu (100 à 140 ms) : les mots incertains deviennent blancs sans saut.
        // Le curseur ambre (le seul accent de l'encoche) apparaît derrière le texte final.
        HStack(spacing: 3) {
            ZStack(alignment: debordement > 0 ? .trailing : .leading) {
                ligne(attribue(mots, provisoire: true))
                ligne(attribue(mots, provisoire: false)).opacity(fige ? 1 : 0)
            }
            RoundedRectangle(cornerRadius: 0.75).fill(Color(red: 230/255, green: 160/255, blue: 74/255))
                .frame(width: 1.5, height: 14).opacity(fige && !texte.isEmpty ? 1 : 0)
        }
        .frame(width: largeur, alignment: debordement > 0 ? .trailing : .leading)
        .mask(
            HStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing).frame(width: fondu)
                Color.black
            }
        )
        .clipped()
        .animation(.easeInOut(duration: GeometrieEncoche.dureeFondu), value: fige)
        .accessibilityHidden(true)
    }

    private func ligne(_ t: AttributedString) -> some View {
        Text(t).font(.system(size: 13)).lineLimit(1).fixedSize()
    }

    private func attribue(_ mots: [String], provisoire: Bool) -> AttributedString {
        var sortie = AttributedString()
        for (i, mot) in mots.enumerated() {
            var a = AttributedString(mot + (i < mots.count - 1 ? " " : ""))
            a.foregroundColor = provisoire && i >= mots.count - 2 ? Self.gris : Self.blanc
            sortie.append(a)
        }
        return sortie
    }
}
