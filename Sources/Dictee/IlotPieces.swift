import AppKit
import SwiftUI
import QuartzCore
import DicteeCore

// Les petites pièces de l'îlot (maquette design/maquettes/ilot-pro-A.html) : la forme noire, les couleurs, les boutons nus, les
// pilules, l'égaliseur de la lecture, la barre de progression, le titre qui défile. Les écrans eux-mêmes sont dans IlotVues.swift.
// Règle : noir opaque, une seule teinte tirée de la pochette, des symboles SF sans fond ; aucune lueur, aucune tuile, aucun liseré.

enum CouleursIlot {
    // couleurs système d'Apple en mode sombre
    static let ambre = Color(hex: 0xFF9F0A)
    static let jaune = Color(hex: 0xFFD60A)
    static let vert = Color(hex: 0x30D158)
    static let rouge = Color(hex: 0xFF453A)
    static let bleu = Color(hex: 0x0A84FF)
    static let encre2 = Color.white.opacity(0.6)
    static let encre3 = Color.white.opacity(0.42)
}

func lisseIlot(_ v: CGFloat) -> CGFloat { let x = min(1, max(0, v)); return x * x * (3 - 2 * x) }
/// La teinte de la pochette, assez lumineuse pour se lire sur le noir (au moins 60 % de luminosité).
func teinteIlot(_ c: CouleurRVB) -> Color {
    let m = max(c.r, c.g, c.b)
    let k = m < 0.6 && m > 0.001 ? 0.6 / m : 1
    return Color(.sRGB, red: min(1, c.r * k), green: min(1, c.g * k), blue: min(1, c.b * k), opacity: 1)
}

extension View {
    /// Pose la vue dans la zone de dessin de l'îlot : `r` en points depuis le centre de l'encoche (x) et le haut de l'écran (y).
    func cadreIlot(_ r: CGRect, _ al: Alignment = .topLeading) -> some View {
        frame(width: max(0, r.width), height: max(0, r.height), alignment: al)
            .offset(x: IlotMoteur.largeur / 2 + r.minX, y: r.minY)
    }
    /// L'aspect d'un élément pendant son arrivée ou son départ (fondu, flou, zoom ancré en haut).
    func aspectIlot(_ a: AspectIlot, ancre: UnitPoint = .top) -> some View {
        scaleEffect(a.echelle, anchor: ancre)
            .blur(radius: a.flou)
            .opacity(a.opacite)
            .offset(y: a.decalage)
            .allowsHitTesting(a.opacite > 0.6)
    }
}

// MARK: forme noire

/// La forme noire, tracée à partir des commandes de `TraceIlot` (coins continus). Origine : centre du rectangle en x, haut en y.
struct FormeNoire: Shape {
    var points: TraceIlot.Points

    func path(in rect: CGRect) -> Path {
        let ox = Double(rect.midX), oy = Double(rect.minY)
        func P(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: ox + x, y: oy + y) }
        var p = Path()
        for c in points.commandes {
            switch c {
            case let .deplacer(x, y): p.move(to: P(x, y))
            case let .ligne(x, y): p.addLine(to: P(x, y))
            case let .quad(cx, cy, x, y): p.addQuadCurve(to: P(x, y), control: P(cx, cy))
            case let .cubique(ax, ay, bx, by, x, y): p.addCurve(to: P(x, y), control1: P(ax, ay), control2: P(bx, by))
            }
        }
        p.closeSubpath()
        return p
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
            Circle().stroke(couleur.opacity(0.26), lineWidth: trait)
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

/// L'appui des boutons de l'îlot : réduit pendant l'appui, retour par un ressort vif.
struct AppuiIlot: ButtonStyle {
    var echelle: CGFloat = 0.88
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? echelle : 1)
            .animation(configuration.isPressed ? .easeOut(duration: 0.08) : .spring(response: 0.38, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Un bouton nu, façon lecteur d'Apple : le symbole seul, 40 pt de zone cliquable, un léger fond au survol.
struct BoutonNu: View {
    var symbole: String
    var taille: CGFloat = 20
    var discret = false
    var etiquette: String
    var action: () -> Void
    @State private var survol = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbole)
                .font(.system(size: taille, weight: .semibold))
                .foregroundStyle(discret ? Color.white.opacity(survol ? 0.9 : 0.55) : .white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.white.opacity(survol ? 0.07 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(AppuiIlot(echelle: 0.86))
        .onHover { survol = $0 }
        .animation(.easeOut(duration: 0.15), value: survol)
        .accessibilityLabel(etiquette)
    }
}

/// Les pilules de la maquette (« Plus tard », « Fait », « Rejoindre », « 5 min »…) : 32 pt de haut, texte de 13,5 pt semi-gras.
struct CapIlot: View {
    /// `blanc` : « Ouvrir » sur « Note prête » ; `noter` : blanc, un point rouge devant (« Noter cet appel ? », maquette ilot-reunion.html).
    enum Style { case gris, jaune, vert, ambre, blanc, noter }
    /// Le point rouge de `noter` (9 pt) et son écart (6 pt) : `MesureIlot.bouton` les compte.
    static let placePoint: CGFloat = 15
    var titre: String
    var icone: String?
    var style: Style = .gris
    var hauteur: CGFloat = 32
    var etiquette: String?
    /// Prend toute la largeur proposée (rangée de pilules de même largeur), au lieu de sa largeur naturelle.
    var remplir = false
    var action: () -> Void
    @State private var survol = false

    private var fond: Color {
        switch style {
        case .gris: return Color.white.opacity(survol ? 0.2 : 0.15)
        case .jaune: return CouleursIlot.jaune.opacity(survol ? 0.88 : 1)
        case .vert: return CouleursIlot.vert.opacity(survol ? 0.88 : 1)
        case .ambre: return CouleursIlot.ambre.opacity(survol ? 0.88 : 1)
        case .blanc, .noter: return Color.white.opacity(survol ? 0.88 : 1)
        }
    }
    private var encre: Color {
        switch style {
        case .gris: return .white
        case .jaune: return Color(hex: 0x1A1400)
        case .vert: return Color(hex: 0x04210D)
        case .ambre: return Color(hex: 0x231300)
        case .blanc, .noter: return .black
        }
    }
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if style == .noter { Circle().fill(CouleursIlot.rouge).frame(width: 9, height: 9) }
                if let icone { Image(systemName: icone).font(.system(size: hauteur >= 32 ? 13 : 11.5, weight: .semibold)) }
                Text(titre).font(.system(size: hauteur >= 32 ? 13.5 : 12.5, weight: .semibold)).lineLimit(1).fixedSize()
            }
            .foregroundStyle(encre)
            .padding(.horizontal, hauteur >= 32 ? 14 : 11)
            .frame(maxWidth: remplir ? .infinity : nil)
            .frame(height: hauteur)
            .background(Capsule().fill(fond))
            .contentShape(Capsule())
        }
        .buttonStyle(AppuiIlot(echelle: 0.92))
        .onHover { survol = $0 }
        .animation(.easeOut(duration: 0.12), value: survol)
        .accessibilityLabel(etiquette ?? titre)
    }
}

/// Un bouton rond de 44 pt (minuteur : pause sur l'anneau, arrêt en gris).
struct RondIlot: View {
    var symbole: String
    var ambre = false
    var etiquette: String
    var action: () -> Void
    @State private var survol = false
    var body: some View {
        Button(action: action) {
            ZStack {
                if ambre { Circle().fill(CouleursIlot.ambre.opacity(survol ? 0.32 : 0.24)).padding(5) }
                else { Circle().fill(Color.white.opacity(survol ? 0.22 : 0.16)) }
                Image(systemName: symbole).font(.system(size: ambre ? 17 : 15, weight: .bold))
                    .foregroundStyle(ambre ? CouleursIlot.ambre : .white)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
        .buttonStyle(AppuiIlot(echelle: 0.86))
        .onHover { survol = $0 }
        .accessibilityLabel(etiquette)
    }
}

// MARK: égaliseur de la lecture (aile droite)

/// Cinq barres arrondies teintées par la pochette (maquette : 2,6 × 14 pt, 0,74 à 1,18 s par cycle, décalées). Core Animation : tout
/// tourne dans le serveur d'affichage, aucune charge pour l'app. En pause et avec « Réduire les animations » : barres basses, immobiles.
struct EgaliseurLecture: NSViewRepresentable {
    var teinte: Color
    var joue: Bool
    var animer: Bool
    static let durees: [Double] = [0.82, 1.06, 0.74, 0.95, 1.18]
    static let decalages: [Double] = [0.3, 0.7, 0.1, 0.5, 0.2]

    final class Vue: NSView {
        private var barres: [CALayer] = []
        private var etat = -1
        private let largeurBarre: CGFloat
        init(frame: NSRect, barres nombre: Int = 5, largeur: CGFloat = 2.6) {
            largeurBarre = largeur
            super.init(frame: frame)
            wantsLayer = true
            for _ in 0..<nombre { let b = CALayer(); b.cornerRadius = largeur / 2; layer?.addSublayer(b); barres.append(b) }
        }
        override convenience init(frame: NSRect) { self.init(frame: frame, barres: 5, largeur: 2.6) }
        required init?(coder: NSCoder) { fatalError() }
        override var isFlipped: Bool { true }
        override func layout() {
            super.layout()
            CATransaction.begin(); CATransaction.setDisableActions(true)
            let l = largeurBarre, n = CGFloat(barres.count)
            let ecart = (bounds.width - n * l) / (n - 1)
            for (i, b) in barres.enumerated() {
                b.bounds = CGRect(x: 0, y: 0, width: l, height: bounds.height)
                b.position = CGPoint(x: CGFloat(i) * (l + ecart) + l / 2, y: bounds.midY)
            }
            CATransaction.commit()
        }
        /// Essais : les barres bougent-elles (une animation posée sur au moins une barre) ?
        var anime: Bool { barres.contains { $0.animation(forKey: "eq") != nil } }
        func appliquer(teinte: Color, joue: Bool, animer: Bool) {
            let c = NSColor(teinte).cgColor
            CATransaction.begin(); CATransaction.setDisableActions(true)
            for b in barres { b.backgroundColor = c }
            CATransaction.commit()
            let voulu = (joue && animer) ? 1 : 0
            guard voulu != etat else { return }
            etat = voulu
            for (i, b) in barres.enumerated() {
                b.removeAllAnimations()
                if voulu == 1 {
                    let a = CAKeyframeAnimation(keyPath: "transform.scale.y")
                    a.values = [0.28, 0.95, 0.5, 1, 0.36, 0.28]
                    a.keyTimes = [0, 0.22, 0.41, 0.63, 0.82, 1]
                    a.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: 5)
                    a.duration = EgaliseurLecture.durees[i]
                    a.timeOffset = EgaliseurLecture.decalages[i]
                    a.repeatCount = .infinity
                    b.add(a, forKey: "eq")
                } else {
                    b.transform = CATransform3DMakeScale(1, joue ? 0.5 : 0.2, 1)
                }
            }
            if voulu == 1 { for b in barres { b.transform = CATransform3DIdentity } }
        }
    }
    func makeNSView(context: Context) -> Vue { Vue(frame: CGRect(x: 0, y: 0, width: 19.4, height: 14)) }
    func updateNSView(_ v: Vue, context: Context) { v.appliquer(teinte: teinte, joue: joue, animer: animer) }
}

/// L'égaliseur immobile (rendus PNG : ImageRenderer ne dessine pas Core Animation).
struct EgaliseurFixe: View {
    var teinte: Color
    var joue: Bool
    var nombre = 5
    var largeurBarre: CGFloat = 2.6
    static let hauteurs: [CGFloat] = [0.45, 0.95, 0.6, 1, 0.4]
    var body: some View {
        GeometryReader { g in
            let n = CGFloat(nombre), ecart = (g.size.width - n * largeurBarre) / max(1, n - 1)
            ForEach(0..<nombre, id: \.self) { i in
                let h = g.size.height * (joue ? Self.hauteurs[i % 5] : 0.2)
                Capsule().fill(teinte).frame(width: largeurBarre, height: h)
                    .position(x: CGFloat(i) * (largeurBarre + ecart) + largeurBarre / 2, y: g.size.height / 2)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: barre de progression

/// La barre de la lecture : une capsule fine (5 pt), la part écoutée teintée, le reste en blanc 20 % ; elle grossit à 9 pt au survol et
/// pendant le glissement. Temps écoulé et restant aux deux bouts, en chiffres fixes.
struct BarreLecture: View {
    @ObservedObject var lecture: LectureModele
    var largeur: CGFloat
    var teinte: Color
    @State private var survol = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
            let duree = lecture.morceau?.duree
            let position = lecture.positionAffichee(a: ctx.date)
            let fraction = (position != nil && duree != nil) ? TempsLecture.fraction(position: position!, duree: duree!) : 0
            if lecture.morceau?.positionnable == true, let duree {
                let actif = survol || lecture.fractionGlissee != nil
                // les temps prennent leur largeur (« −1:02:15 » compris), la piste prend le reste : rien n'est jamais coupé
                HStack(spacing: 6) {
                    temps(TempsLecture.format(position ?? 0), .leading)
                    GeometryReader { geo in
                        let piste = geo.size.width
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.2))
                            Capsule().fill(teinte).frame(width: max(actif ? 9 : 5, piste * CGFloat(fraction)))
                        }
                        .frame(width: piste, height: actif ? 9 : 5)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
                            .onChanged { v in lecture.fractionGlissee = TempsLecture.fractionSousSouris(x: v.location.x, largeur: piste) }
                            .onEnded { v in
                                let f = TempsLecture.fractionSousSouris(x: v.location.x, largeur: piste)
                                lecture.fractionGlissee = nil
                                lecture.surPosition(TempsLecture.position(fraction: f, duree: duree))
                                lecture.surFinGlissement()
                            })
                    }
                    .frame(height: 20)
                    .animation(.spring(response: 0.32, dampingFraction: 0.78), value: actif)
                    .onHover { survol = $0 }
                    .accessibilityElement()
                    .accessibilityLabel("Position")
                    .accessibilityValue("\(TempsLecture.format(position ?? 0)) sur \(TempsLecture.format(duree))")
                    .accessibilityAdjustableAction { sens in
                        let p = position ?? 0
                        lecture.surPosition(min(duree, max(0, p + (sens == .increment ? 10 : -10))))
                    }
                    temps(TempsLecture.restant(position: position ?? 0, duree: duree), .trailing)
                }
                .frame(width: largeur, height: 20)
            } else {
                Text(lecture.morceau?.joue == true ? "En direct" : "Durée inconnue")
                    .font(.system(size: 11.5, weight: .medium)).foregroundStyle(Color.white.opacity(0.55))
                    .frame(width: largeur, height: 20, alignment: .leading)
            }
        }
    }
    private func temps(_ s: String, _ al: Alignment) -> some View {
        Text(s).font(.system(size: 11.5, weight: .medium).monospacedDigit()).foregroundStyle(Color.white.opacity(0.55))
            .lineLimit(1).fixedSize().frame(minWidth: 38, alignment: al)
    }
}

// MARK: titre qui défile

/// Un titre sur une ligne. S'il est trop long : « … » au repos, et il défile deux fois (après 1,6 s), bord droit estompé, puis revient.
/// Aucun défilement avec « Réduire les animations » ni dans les rendus PNG.
struct TitreDefilant: View {
    /// Tout le défilement tient en 20 s (puis plus rien ne tourne).
    static let budget = 20.0
    /// Le masque du titre : fondu de 18 pt à droite (la suite du titre), et à gauche de 0 à 18 pt selon `gauche` (0 au repos, le texte
    /// commence net sur la marge ; 1 dès qu'il glisse : les lettres qui sortent s'effacent au lieu d'être coupées).
    static func fondu(largeur: CGFloat, gauche: CGFloat) -> LinearGradient {
        let f = min(0.5, 18 / max(1, largeur))
        return LinearGradient(stops: [.init(color: .black.opacity(Double(1 - gauche)), location: 0), .init(color: .black, location: f),
                                      .init(color: .black, location: 1 - f), .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing)
    }
    var texte: String
    var police: Font
    var largeur: CGFloat
    var defiler: Bool
    @State private var mesure: CGFloat = 0
    @State private var lancer = false

    var body: some View {
        let trop = mesure - largeur
        ZStack(alignment: .leading) {
            // sert à mesurer la largeur naturelle, invisible
            Text(texte).font(police).lineLimit(1).fixedSize().hidden()
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { mesure = $0 }
            if trop > 1, defiler {
                let dist = trop + 22
                // ~26 pt/s ; deux passages si cela tient en 20 s, sinon un seul, accéléré pour finir en 20 s (un titre YouTube de 200
                // caractères faisait tourner l'animation 75 s). Les pauses font 3,3 s par passage.
                let naturel = max(5, dist / 26 + 2.4)
                let deux = 2 * (3.3 + 0.76 * naturel) <= TitreDefilant.budget
                let duree = deux ? naturel : min(naturel, (TitreDefilant.budget - 3.3) / 0.76)
                let d2 = deux ? 1.0 : 0
                Text(texte).font(police).foregroundStyle(.white).lineLimit(1).fixedSize()
                    .keyframeAnimator(initialValue: 0.0, trigger: lancer) { v, x in
                        // le bord gauche s'estompe dès que le titre a commencé à glisser (jamais une lettre coupée net)
                        v.offset(x: x)
                            .frame(width: largeur, alignment: .leading)
                            .clipped()
                            .mask(TitreDefilant.fondu(largeur: largeur, gauche: min(1, max(0, -x / 10))))
                    } keyframes: { _ in
                        KeyframeTrack {
                            LinearKeyframe(0, duration: 1.6)
                            LinearKeyframe(-dist, duration: duree * 0.76)
                            LinearKeyframe(-dist, duration: 1.2)
                            CubicKeyframe(0, duration: 0.5)
                            LinearKeyframe(0, duration: 1.6 * d2)
                            LinearKeyframe(-dist * d2, duration: duree * 0.76 * d2)
                            LinearKeyframe(-dist * d2, duration: 1.2 * d2)
                            CubicKeyframe(0, duration: 0.5 * d2)
                        }
                    }
                    .frame(width: largeur, alignment: .leading)
                    .onAppear { lancer.toggle() }
                    .onChange(of: texte) { lancer.toggle() }
            } else {
                Text(texte).font(police).foregroundStyle(.white).lineLimit(1).truncationMode(.tail)
                    .frame(width: largeur, alignment: .leading)
            }
        }
        .frame(width: largeur, alignment: .leading)
        .accessibilityLabel(texte)
    }
}

// MARK: cloche

/// La cloche du rappel qui sonne : elle se secoue deux fois (14°, −12°, 9°, −6°, 3°) après 0,18 s, puis se repose. Rien ne tourne ensuite.
/// `sonnerie` : l'identifiant du rappel qui sonne (nil : aucun, ou « Réduire les animations »). Elle se secoue à son apparition ET à
/// chaque nouveau rappel qui sonne pendant qu'elle est déjà là (la cloche d'un rappel sans réponse, restée dans l'aile).
struct ClocheSecouee: View {
    var taille: CGFloat
    var sonnerie: UUID?
    /// La cloche du rappel, ou le réveil (qui sonne de la même façon : deux secousses à l'arrivée, puis plus rien qui tourne).
    var symbole = "bell.fill"
    var couleur = CouleursIlot.jaune
    @State private var lancer = false
    var body: some View {
        Image(systemName: symbole).font(.system(size: taille, weight: .semibold)).foregroundStyle(couleur)
            .keyframeAnimator(initialValue: 0.0, trigger: lancer) { v, a in
                v.rotationEffect(.degrees(a), anchor: UnitPoint(x: 0.5, y: 0.12))
            } keyframes: { _ in
                KeyframeTrack {
                    LinearKeyframe(0, duration: 0.18)
                    CubicKeyframe(14, duration: 0.108); CubicKeyframe(-12, duration: 0.126); CubicKeyframe(9, duration: 0.126)
                    CubicKeyframe(-6, duration: 0.126); CubicKeyframe(3, duration: 0.126); CubicKeyframe(0, duration: 0.108)
                    LinearKeyframe(0, duration: 0.18)
                    CubicKeyframe(14, duration: 0.108); CubicKeyframe(-12, duration: 0.126); CubicKeyframe(9, duration: 0.126)
                    CubicKeyframe(-6, duration: 0.126); CubicKeyframe(3, duration: 0.126); CubicKeyframe(0, duration: 0.108)
                }
            }
            .onAppear { if sonnerie != nil { lancer.toggle() } }
            .onChange(of: sonnerie) { _, n in if n != nil { lancer.toggle() } }
            .accessibilityHidden(true)
    }
}

/// Un symbole SF de l'îlot, sans fond (cloche, calendrier, minuteur…).
struct GlypheIlot: View {
    /// Le calendrier, dessiné au trait : le symbole « calendar » du système est devenu une tuile pleine (fond rouge, points découpés),
    /// bien plus lourde que la cloche ou le minuteur.
    static let calendrier = "îlot.calendrier"
    var nom: String
    var couleur: Color
    var taille: CGFloat
    var body: some View {
        Group {
            if nom == Self.calendrier { CalendrierTrait(couleur: couleur, taille: taille) }
            else { Image(systemName: nom).font(.system(size: taille, weight: .semibold)).foregroundStyle(couleur) }
        }
        .accessibilityHidden(true)
    }
}

/// Un calendrier au trait, du poids du minuteur et de l'horloge : cadre arrondi, filet sous l'en-tête, deux anneaux, et la date du jour.
struct CalendrierTrait: View {
    var couleur: Color
    var taille: CGFloat
    var body: some View {
        let l = taille * 0.92, h = taille * 0.84, t = max(1.2, taille * 0.085)
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: taille * 0.2, style: .continuous).strokeBorder(couleur, lineWidth: t)
                .frame(width: l, height: h).padding(.top, taille * 0.1)
            Rectangle().fill(couleur).frame(width: l - t, height: t).padding(.top, taille * 0.1 + h * 0.3)
            HStack(spacing: l * 0.36) {
                Capsule().fill(couleur).frame(width: t, height: taille * 0.22)
                Capsule().fill(couleur).frame(width: t, height: taille * 0.22)
            }
        }
        .frame(width: taille, height: taille)
    }
}
