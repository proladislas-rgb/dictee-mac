import AppKit
import SwiftUI
import QuartzCore
import DicteeCore

// Les petites pièces de l'îlot « centre d'activités » (maquette design/maquettes/ilot-activites.html) : couleurs, tuiles d'icône,
// anneaux, boutons, pilules, onde de la lecture, trace sonore. Les écrans eux-mêmes sont dans IlotVues.swift.

enum CouleursIlot {
    static let ambre = Color(hex: 0xF2A33C)
    static let corail = Color(hex: 0xFF6B5E)
    static let vert = Color(hex: 0x4FD37D)
    static let bleu = Color(hex: 0x5AB0FF)
    static let rouge = Color(hex: 0xFF5A4E)
    static let encre2 = Color(hex: 0xA8A59E)
    static let encre3 = Color(hex: 0x88857E)
}

func lisseIlot(_ v: CGFloat) -> CGFloat { let x = min(1, max(0, v)); return x * x * (3 - 2 * x) }
func teinteIlot(_ c: CouleurRVB) -> Color { Color(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: 1) }

// MARK: forme noire

/// La forme noire, tracée à partir des points de `TraceIlot` (quarts de cercle remplacés par des courbes de Bézier). Origine : centre de
/// l'encoche en haut du rectangle.
struct FormeNoire: Shape {
    var points: TraceIlot.Points

    func path(in rect: CGRect) -> Path {
        let k = 0.5522847498
        let ox = Double(rect.midX), oy = Double(rect.minY)
        func P(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: ox + x, y: oy + y) }
        var p = Path()
        p.move(to: P(points.departX, points.departY))
        var courant = (x: points.departX, y: points.departY)
        var dir = (x: 1.0, y: 0.0)
        for s in points.segments {
            switch s.genre {
            case .ligne:
                let dx = s.x - courant.x, dy = s.y - courant.y, n = (dx * dx + dy * dy).squareRoot()
                if n > 1e-6 { dir = (dx / n, dy / n) }
                p.addLine(to: P(s.x, s.y))
            case .arc:
                guard s.rayon > 1e-6 else { p.addLine(to: P(s.x, s.y)); courant = (s.x, s.y); continue }
                let r = s.rayon
                let t1 = ((s.x - courant.x) / r - dir.x, (s.y - courant.y) / r - dir.y)
                let c1 = P(courant.x + dir.x * k * r, courant.y + dir.y * k * r)
                let c2 = P(s.x - t1.0 * k * r, s.y - t1.1 * k * r)
                p.addCurve(to: P(s.x, s.y), control1: c1, control2: c2)
                dir = (t1.0, t1.1)
            }
            courant = (s.x, s.y)
        }
        p.closeSubpath()
        return p
    }
}

// MARK: tuiles d'icône

struct TuileIlot: View {
    enum Genre { case minuteur, rappel, messages, fait, calendrier, dictee, notes, horloge }
    var genre: Genre
    var taille: CGFloat
    var jour = Calendar.current.component(.day, from: Date())

    private var rayon: CGFloat { (taille * 0.3).rounded() }
    private func glyphe(_ nom: String, _ k: CGFloat = 0.62) -> some View {
        Image(systemName: nom).font(.system(size: taille * k, weight: .semibold)).foregroundStyle(.white)
    }

    var body: some View {
        ZStack {
            switch genre {
            case .minuteur: CouleursIlot.ambre; glyphe("timer")
            case .rappel: CouleursIlot.corail; glyphe("bell.fill", 0.56)
            case .horloge: CouleursIlot.corail; glyphe("clock", 0.62)
            case .fait: CouleursIlot.vert; glyphe("checkmark", 0.6)
            case .messages: Color(hex: 0x3FCF6C); glyphe("message.fill", 0.58)
            case .notes: Color(hex: 0x2D6CDF); glyphe("note.text", 0.58)
            case .calendrier:
                VStack(spacing: 0) {
                    CouleursIlot.rouge.frame(height: taille * 0.32)
                    Color(hex: 0xF4F1EA).overlay(Text("\(jour)").font(.system(size: taille * 0.5, weight: .bold)).foregroundStyle(Color(hex: 0x15130F)))
                }
            case .dictee:
                VStack(spacing: 0) {
                    Color(hex: 0xE8C24A).frame(height: taille * 0.30)
                    Color(hex: 0xF4F1EA).overlay(
                        VStack(spacing: taille * 0.1) {
                            RoundedRectangle(cornerRadius: 1).fill(Color(hex: 0xC9C5BB)).frame(height: taille * 0.07)
                            RoundedRectangle(cornerRadius: 1).fill(Color(hex: 0xC9C5BB)).frame(height: taille * 0.07)
                        }.padding(.horizontal, taille * 0.22))
                }
            }
        }
        .frame(width: taille, height: taille)
        .clipShape(RoundedRectangle(cornerRadius: rayon, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: rayon, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        .accessibilityHidden(true)
    }
}

// MARK: anneau

struct AnneauIlot<Contenu: View>: View {
    var taille: CGFloat
    var trait: CGFloat
    var couleur: Color
    var fraction: Double
    var enPause = false
    @ViewBuilder var contenu: () -> Contenu
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.15), lineWidth: trait)
            Circle().trim(from: 0, to: CGFloat(min(1, max(0, fraction))))
                .stroke(couleur.opacity(enPause ? 0.55 : 1), style: StrokeStyle(lineWidth: trait, lineCap: .round))
                .rotationEffect(.degrees(-90))
            contenu()
        }
        .padding(trait / 2)
        .frame(width: taille, height: taille)
    }
}

// MARK: boutons

/// Les pilules de la maquette : 42 pt (grande), 32 pt (petite), 26 pt (toute petite).
struct PiluleIlot: View {
    enum Style { case neutre, blanc, vert }
    var titre: String
    var icone: String?
    var style: Style = .neutre
    var hauteur: CGFloat = 42
    var largeur: CGFloat?
    var action: () -> Void
    @State private var survol = false

    private var taille: CGFloat { hauteur >= 42 ? 14.5 : (hauteur >= 32 ? 13 : 12) }
    private var marge: CGFloat { hauteur >= 42 ? 18 : (hauteur >= 32 ? 14 : 11) }
    private var fond: Color {
        switch style {
        case .neutre: return Color.white.opacity(survol ? 0.2 : 0.12)
        case .blanc: return Color(white: survol ? 0.91 : 1)
        case .vert: return survol ? Color(hex: 0x68DD90) : CouleursIlot.vert
        }
    }
    private var texte: Color { style == .blanc ? .black : (style == .vert ? Color(hex: 0x04210F) : .white) }

    private struct Appui: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label.scaleEffect(configuration.isPressed ? 0.96 : 1).animation(.easeOut(duration: 0.1), value: configuration.isPressed)
        }
    }
    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let icone { Image(systemName: icone).font(.system(size: taille + 1.5, weight: .semibold)) }
                Text(titre).font(.system(size: taille, weight: .semibold)).tracking(-0.09).lineLimit(1)
            }
            .foregroundStyle(texte)
            .padding(.horizontal, marge)
            .frame(width: largeur, height: hauteur)
            .frame(minWidth: largeur == nil ? nil : 0)
            .background(Capsule().fill(fond))
            .contentShape(Capsule())
        }
        .buttonStyle(Appui())
        .onHover { survol = $0 }
        .animation(.easeOut(duration: 0.12), value: survol)
    }
}

/// Un bouton rond de l'étendu (minuteur : pause, arrêt).
struct RondIlot: View {
    var symbole: String
    var diametre: CGFloat
    var rouge = false
    var etiquette: String
    var action: () -> Void
    @State private var survol = false
    private struct Appui: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label.scaleEffect(configuration.isPressed ? 0.9 : 1).animation(.easeOut(duration: 0.1), value: configuration.isPressed)
        }
    }
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(rouge ? CouleursIlot.rouge.opacity(survol ? 0.32 : 0.2) : Color.white.opacity(survol ? 0.2 : 0.11))
                Image(systemName: symbole).font(.system(size: diametre * 0.4, weight: .semibold))
                    .foregroundStyle(rouge ? Color(hex: 0xFF7C70) : .white)
            }
            .frame(width: diametre, height: diametre)
            .contentShape(Circle())
        }
        .buttonStyle(Appui())
        .onHover { survol = $0 }
        .accessibilityLabel(etiquette)
    }
}

// MARK: onde de la lecture (aile droite)

/// Une onde qui défile, teintée par la pochette (maquette : 50 × 24, 1,5 s par motif, amplitude qui respire en 1,2 s). Core Animation :
/// tout tourne dans le serveur d'affichage, aucune charge pour l'app. En pause : figée, à 45 %. « Réduire les animations » : figée.
struct OndeLecture: NSViewRepresentable {
    var teinte: CouleurRVB
    var joue: Bool
    var animer: Bool

    final class Vue: NSView {
        private let masque = CALayer()
        private let defile = CALayer()
        private let onde = CAShapeLayer()
        private var etat = -1
        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.addSublayer(masque)
            masque.masksToBounds = false
            masque.addSublayer(defile)
            defile.addSublayer(onde)
            let p = CGMutablePath(), k: CGFloat = 50.0 / 30.0
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * k, y: 24 - y) }
            p.move(to: pt(0, 12))
            p.addCurve(to: pt(15, 12), control1: pt(3.75, -2), control2: pt(11.25, -2))
            p.addCurve(to: pt(30, 12), control1: pt(18.75, 26), control2: pt(26.25, 26))
            p.addCurve(to: pt(45, 12), control1: pt(33.75, -2), control2: pt(41.25, -2))
            p.addCurve(to: pt(60, 12), control1: pt(48.75, 26), control2: pt(56.25, 26))
            onde.path = p
            onde.fillColor = nil
            onde.lineWidth = 2.4
            onde.lineCap = .round
            onde.frame = CGRect(x: 0, y: 0, width: 100, height: 24)
            defile.frame = CGRect(x: 0, y: 0, width: 100, height: 24)
        }
        required init?(coder: NSCoder) { fatalError() }
        override func layout() {
            super.layout()
            CATransaction.begin(); CATransaction.setDisableActions(true)
            masque.frame = bounds
            masque.masksToBounds = true
            CATransaction.commit()
        }
        func appliquer(teinte: CouleurRVB, joue: Bool, animer: Bool) {
            let c = CGColor(srgbRed: teinte.r, green: teinte.g, blue: teinte.b, alpha: 1)
            CATransaction.begin(); CATransaction.setDisableActions(true)
            onde.strokeColor = c
            layer?.shadowColor = c; layer?.shadowOpacity = 0.7; layer?.shadowRadius = 4; layer?.shadowOffset = .zero
            masque.opacity = joue ? 1 : 0.45
            CATransaction.commit()
            let voulu = (joue && animer) ? 1 : 0
            guard voulu != etat else { return }
            etat = voulu
            defile.removeAllAnimations(); onde.removeAllAnimations()
            guard voulu == 1 else { return }
            let x = CABasicAnimation(keyPath: "position.x")
            x.fromValue = 50; x.toValue = 0; x.duration = 1.5; x.repeatCount = .infinity; x.timingFunction = CAMediaTimingFunction(name: .linear)
            defile.add(x, forKey: "defile")
            let a = CABasicAnimation(keyPath: "transform.scale.y")
            a.fromValue = 0.35; a.toValue = 1; a.duration = 1.2; a.autoreverses = true; a.repeatCount = .infinity
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            onde.add(a, forKey: "amp")
        }
    }
    func makeNSView(context: Context) -> Vue { Vue(frame: CGRect(x: 0, y: 0, width: 50, height: 24)) }
    func updateNSView(_ v: Vue, context: Context) { v.appliquer(teinte: teinte, joue: joue, animer: animer) }
}

// MARK: trace sonore (barre de progression de la lecture)

/// 54 barres : la part écoutée teintée (avec sa lueur), un trait blanc au survol ou pendant le glissement.
struct TraceIlotVue: View {
    var fraction: Double
    var teinte: TeintePochette
    var actif: Bool
    static let hauteurs: [CGFloat] = (0..<54).map { i in
        let x = Double(i)
        let h = 0.22 + 0.78 * abs(sin(x * 1.7) * cos(x * 0.43) + 0.15 * sin(x * 5.1))
        return CGFloat(min(1, h))
    }
    var body: some View {
        Canvas { ctx, taille in
            let n = Self.hauteurs.count, ecart: CGFloat = 2
            let l = (taille.width - CGFloat(n - 1) * ecart) / CGFloat(n)
            func barre(_ i: Int) -> Path {
                let h = max(3, taille.height * Self.hauteurs[i])
                return Path(roundedRect: CGRect(x: CGFloat(i) * (l + ecart), y: (taille.height - h) / 2, width: l, height: h), cornerRadius: 1.5)
            }
            for i in 0..<n { ctx.fill(barre(i), with: .color(.white.opacity(0.2))) }
            let x = taille.width * CGFloat(min(1, max(0, fraction)))
            if x > 0.5 {
                ctx.drawLayer { couche in
                    couche.clip(to: Path(CGRect(x: 0, y: -4, width: x, height: taille.height + 8)))
                    couche.addFilter(.shadow(color: teinteIlot(teinte.clair).opacity(0.8), radius: 4))
                    for i in 0..<n {
                        couche.fill(barre(i), with: .linearGradient(Gradient(colors: [teinteIlot(teinte.profond), teinteIlot(teinte.clair)]),
                                                                    startPoint: CGPoint(x: 0, y: taille.height), endPoint: CGPoint(x: 0, y: 0)))
                    }
                }
            }
            if actif {
                ctx.fill(Path(roundedRect: CGRect(x: min(max(0, x - 1), taille.width - 2), y: -1, width: 2, height: taille.height + 2), cornerRadius: 1), with: .color(.white))
            }
        }
        .accessibilityHidden(true)
    }
}
