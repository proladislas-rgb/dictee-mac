import AppKit
import SwiftUI
import QuartzCore
import DicteeCore

// L'îlot de la lecture en cours (maquette design/maquettes/lecture-encoche-v3.html, mélange A + C) : au repos, la pochette dans l'aile
// gauche de l'encoche et une onde teintée dans l'aile droite ; au survol, la capsule dépliée (grande pochette, titre, source, trace
// sonore qui sert de barre de progression, quatre boutons, lueur teintée). Une seule forme noire, centre vide (la caméra).

/// Mesures de la maquette (en points). Les rangées sous la barre sont décalées de `g.hauteur - 38` : la maquette suppose une barre de 38.
enum LectureMesures {
    static let reposAile: CGFloat = 66          // largeur de chaque aile au repos (332 = 200 + 2 × 66)
    /// Échelle de l'îlot déplié (Hugues : « la barre est beaucoup trop grande ») : la maquette est dessinée à 600 × 228, affichée à 78 %.
    static let echelle: CGFloat = 0.78
    static let ouvertLargeurBase: CGFloat = 600
    static let ouvertHauteurBase: CGFloat = 228
    static let ouvertLargeur: CGFloat = ouvertLargeurBase * echelle
    static let ouvertHauteur: CGFloat = ouvertHauteurBase * echelle
    static let rayonOuvert: CGFloat = 48 * echelle
    static let pochetteRepos: CGFloat = 30
    static let pochetteOuvert: CGFloat = 140 * 0.78
    static let margeLaterale: CGFloat = 28
    static let margeReposLaterale: CGFloat = 2     // la fenêtre de repos déborde à peine de la forme : elle ne capte aucun clic sur les icônes voisines
    static let margeBasse: CGFloat = 30
    static let reposMargeBasse: CGFloat = 6
    static let egaliseurBarres = 5
    static let egaliseurLargeurBarre: CGFloat = 2
    static let egaliseurEcart: CGFloat = 3
    static let egaliseurHauteurMax: CGFloat = 13
    static let egaliseurHauteurMin: CGFloat = 2.5
    static let egaliseurLargeur: CGFloat = CGFloat(egaliseurBarres) * egaliseurLargeurBarre + CGFloat(egaliseurBarres - 1) * egaliseurEcart   // 22
    static let egaliseurHauteur: CGFloat = 14
    static let egaliseurMargeDroite: CGFloat = 16

    /// Largeur de l'îlot dans la hauteur de la barre des menus : jamais plus que la bande de la dictée (caméra + 2 ailes), donc jamais sur
    /// les icônes que la dictée laisse libres. Au-dessous de la barre, le corps déplié peut être plus large.
    static func largeurBarre(_ g: GeometrieEncoche) -> CGFloat { g.largeur + 2 * GeometrieEncoche.aile }
    /// Retrait horizontal du corps déplié par rapport à la bande de la barre des menus, de chaque côté.
    static func epaule(_ g: GeometrieEncoche) -> CGFloat { max(0, (ouvertLargeur - largeurBarre(g)) / 2) }

    static func largeurRepos(_ g: GeometrieEncoche) -> CGFloat { g.largeur + 2 * reposAile }
    static func decalage(_ g: GeometrieEncoche) -> CGFloat { g.hauteur - 38 }
    static func hauteurOuvert(_ g: GeometrieEncoche) -> CGFloat { ouvertHauteur + decalage(g) }
    /// Taille de la vue (la plus grande : îlot déplié, ressort compris).
    static func tailleVue(_ g: GeometrieEncoche) -> CGSize {
        CGSize(width: ouvertLargeur + 2 * margeLaterale, height: hauteurOuvert(g) + margeBasse)
    }
    static func tailleFenetreRepos(_ g: GeometrieEncoche) -> CGSize {
        CGSize(width: largeurRepos(g) + 2 * margeReposLaterale, height: g.hauteur + reposMargeBasse)
    }
}

private func lisse(_ v: CGFloat) -> CGFloat { let x = min(1, max(0, v)); return x * x * (3 - 2 * x) }
private func teinteSwiftUI(_ c: CouleurRVB) -> Color { Color(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: 1) }

// MARK: forme

/// La forme noire : haut plat avec, de chaque côté, un congé concave qui la raccorde au bord de l'écran (les « oreilles » de la maquette),
/// coins du bas arrondis. Le centre n'est jamais dessiné à part : c'est du noir, la caméra. Quand le corps est plus large que la bande
/// (`largeurBarre`), il s'élargit sous la barre des menus par une épaule (congé concave puis coin arrondi), comme le ruban de la dictée.
struct FormeIlot: Shape {
    var largeur: CGFloat
    var hauteur: CGFloat
    var rayon: CGFloat
    var oreille: CGFloat   // 0…1
    var largeurBarre: CGFloat
    var hauteurBarre: CGFloat

    func path(in rect: CGRect) -> Path {
        let k: CGFloat = 0.5522847498
        var p = Path()
        let x0 = rect.midX - largeur / 2, x1 = rect.midX + largeur / 2
        let R = max(0, min(rayon, hauteur / 2 + 12, largeur / 2))
        let e = 10 * min(1, max(0, oreille))
        let haut = min(largeur, largeurBarre)
        let pas = (largeur - haut) / 2                      // largeur de l'épaule
        let x0t = rect.midX - haut / 2, x1t = rect.midX + haut / 2
        let f = min(10, pas * 0.45), Rs = max(0, min(14, pas - f))
        let ys = max(0, min(hauteurBarre, hauteur - R - f - Rs - 1))
        let epaule = pas >= 1
        p.move(to: CGPoint(x: x0t - e, y: 0))
        p.addLine(to: CGPoint(x: x1t + e, y: 0))
        // congé concave droit : de (x1t + e, 0) à (x1t, e)
        p.addCurve(to: CGPoint(x: x1t, y: e), control1: CGPoint(x: x1t + e - k * e, y: 0), control2: CGPoint(x: x1t, y: e - k * e))
        if epaule {
            p.addLine(to: CGPoint(x: x1t, y: ys))
            p.addCurve(to: CGPoint(x: x1t + f, y: ys + f), control1: CGPoint(x: x1t, y: ys + k * f), control2: CGPoint(x: x1t + f - k * f, y: ys + f))
            p.addLine(to: CGPoint(x: x1 - Rs, y: ys + f))
            p.addCurve(to: CGPoint(x: x1, y: ys + f + Rs), control1: CGPoint(x: x1 - Rs + k * Rs, y: ys + f), control2: CGPoint(x: x1, y: ys + f + Rs - k * Rs))
        }
        p.addLine(to: CGPoint(x: epaule ? x1 : x1t, y: hauteur - R))
        let dx1 = epaule ? x1 : x1t, dx0 = epaule ? x0 : x0t
        p.addCurve(to: CGPoint(x: dx1 - R, y: hauteur), control1: CGPoint(x: dx1, y: hauteur - R + k * R), control2: CGPoint(x: dx1 - R + k * R, y: hauteur))
        p.addLine(to: CGPoint(x: dx0 + R, y: hauteur))
        p.addCurve(to: CGPoint(x: dx0, y: hauteur - R), control1: CGPoint(x: dx0 + R - k * R, y: hauteur), control2: CGPoint(x: dx0, y: hauteur - R + k * R))
        if epaule {
            p.addLine(to: CGPoint(x: x0, y: ys + f + Rs))
            p.addCurve(to: CGPoint(x: x0 + Rs, y: ys + f), control1: CGPoint(x: x0, y: ys + f + Rs - k * Rs), control2: CGPoint(x: x0 + Rs - k * Rs, y: ys + f))
            p.addLine(to: CGPoint(x: x0t - f, y: ys + f))
            p.addCurve(to: CGPoint(x: x0t, y: ys), control1: CGPoint(x: x0t - f + k * f, y: ys + f), control2: CGPoint(x: x0t, y: ys + k * f))
        }
        p.addLine(to: CGPoint(x: x0t, y: e))
        p.addCurve(to: CGPoint(x: x0t - e, y: 0), control1: CGPoint(x: x0t, y: e - k * e), control2: CGPoint(x: x0t - e + k * e, y: 0))
        p.closeSubpath()
        return p
    }
}

// MARK: couches Core Animation (aucune charge pour l'app : l'animation tourne dans le serveur d'affichage)

/// Le petit égaliseur de l'aile droite : cinq barres fines arrondies, teintées par la pochette. Chaque barre suit sa propre courbe de
/// hauteurs tirées au hasard et adoucies (durées différentes d'une barre à l'autre : le motif ne se répète pas à l'œil). Tout tourne dans
/// le serveur d'affichage (animation Core Animation) : aucune charge pour l'app. À la pause, les barres s'aplatissent en douceur.
/// Avec « Réduire les animations » : hauteurs fixes, jamais d'animation.
struct Egaliseur: NSViewRepresentable {
    var teinte: CouleurRVB
    var joue: Bool
    var reduire: Bool

    /// Hauteurs fixes (rendus PNG, « Réduire les animations »).
    static let hauteursFixes: [CGFloat] = [6, 11, 13, 8, 5]
    private static let enveloppe: [CGFloat] = [0.78, 1, 0.92, 1, 0.74]
    private static let durees: [CFTimeInterval] = [3.1, 2.3, 3.7, 2.7, 3.3]

    final class Vue: NSView {
        private var barres: [CALayer] = []
        private var etat = -1   // 0 à plat, 1 en marche, 2 figé en hauteurs fixes
        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.masksToBounds = false
            for i in 0..<LectureMesures.egaliseurBarres {
                let b = CALayer()
                b.cornerRadius = LectureMesures.egaliseurLargeurBarre / 2
                let x = CGFloat(i) * (LectureMesures.egaliseurLargeurBarre + LectureMesures.egaliseurEcart) + LectureMesures.egaliseurLargeurBarre / 2
                b.bounds = CGRect(x: 0, y: 0, width: LectureMesures.egaliseurLargeurBarre, height: LectureMesures.egaliseurHauteurMin)
                b.position = CGPoint(x: x, y: LectureMesures.egaliseurHauteur / 2)
                layer?.addSublayer(b)
                barres.append(b)
            }
        }
        required init?(coder: NSCoder) { fatalError() }

        private func hauteurAffichee(_ b: CALayer) -> CGFloat { b.presentation()?.bounds.height ?? b.bounds.height }

        func appliquer(teinte: CouleurRVB, joue: Bool, reduire: Bool) {
            let c = CGColor(srgbRed: teinte.r, green: teinte.g, blue: teinte.b, alpha: 1)
            CATransaction.begin(); CATransaction.setDisableActions(true)
            for b in barres { b.backgroundColor = c }
            layer?.shadowColor = c; layer?.shadowOpacity = 0.65; layer?.shadowRadius = 3.5; layer?.shadowOffset = .zero
            CATransaction.commit()
            let voulu = !joue ? 0 : (reduire ? 2 : 1)
            guard voulu != etat else { return }
            etat = voulu
            CATransaction.begin(); CATransaction.setDisableActions(true)   // seules nos animations explicites bougent les barres
            for (i, b) in barres.enumerated() {
                let depart = hauteurAffichee(b)
                b.removeAllAnimations()
                switch voulu {
                case 1:
                    var valeurs = (0..<8).map { _ in LectureMesures.egaliseurHauteurMin + (LectureMesures.egaliseurHauteurMax * Egaliseur.enveloppe[i] - LectureMesures.egaliseurHauteurMin) * CGFloat.random(in: 0.05...1) }
                    // pas deux sommets de suite trop proches : la courbe respire au lieu de frémir
                    for j in 1..<valeurs.count where abs(valeurs[j] - valeurs[j - 1]) < 2 { valeurs[j] = min(LectureMesures.egaliseurHauteurMax, valeurs[j - 1] + 4) }
                    // montée douce depuis la hauteur courante, puis la courbe en boucle (son dernier point rejoint le premier)
                    let montee = CABasicAnimation(keyPath: "bounds.size.height")
                    montee.fromValue = depart; montee.toValue = valeurs[0]
                    montee.duration = 0.45; montee.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    b.bounds.size.height = valeurs[0]
                    b.add(montee, forKey: "montee")
                    let boucle = CAKeyframeAnimation(keyPath: "bounds.size.height")
                    boucle.values = (valeurs + [valeurs[0]]).map { NSNumber(value: Double($0)) }
                    boucle.calculationMode = .cubic
                    boucle.duration = Egaliseur.durees[i] * 2.4
                    boucle.repeatCount = .infinity
                    boucle.beginTime = b.convertTime(CACurrentMediaTime(), from: nil) + 0.45
                    b.add(boucle, forKey: "boucle")
                case 2:
                    b.bounds.size.height = Egaliseur.hauteursFixes[i]
                default:
                    let aplat = CABasicAnimation(keyPath: "bounds.size.height")
                    aplat.fromValue = depart; aplat.toValue = LectureMesures.egaliseurHauteurMin
                    aplat.duration = 0.6; aplat.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    b.bounds.size.height = LectureMesures.egaliseurHauteurMin
                    b.add(aplat, forKey: "aplat")
                }
            }
            CATransaction.commit()
        }
    }

    func makeNSView(context: Context) -> Vue { Vue(frame: CGRect(x: 0, y: 0, width: LectureMesures.egaliseurLargeur, height: LectureMesures.egaliseurHauteur)) }
    func updateNSView(_ v: Vue, context: Context) { v.appliquer(teinte: teinte, joue: joue, reduire: reduire) }
}

/// Le même égaliseur, immobile, pour les rendus PNG (`joue` : hauteurs fixes ; sinon à plat).
struct EgaliseurFixe: View {
    var teinte: CouleurRVB
    var joue: Bool
    var body: some View {
        HStack(spacing: LectureMesures.egaliseurEcart) {
            ForEach(0..<LectureMesures.egaliseurBarres, id: \.self) { i in
                Capsule().fill(teinteSwiftUI(teinte))
                    .frame(width: LectureMesures.egaliseurLargeurBarre, height: joue ? Egaliseur.hauteursFixes[i] : LectureMesures.egaliseurHauteurMin)
            }
        }
        .shadow(color: teinteSwiftUI(teinte).opacity(0.65), radius: 3.5)
        .frame(width: LectureMesures.egaliseurLargeur, height: LectureMesures.egaliseurHauteur)
    }
}

/// Pochette de musique : le disque tourne (26 s par tour) tant que ça joue, s'arrête là où il est en pause.
struct ImageRotative: NSViewRepresentable {
    var image: NSImage?
    var tourne: Bool

    final class Vue: NSView {
        private let disque = CALayer()
        private var enMarche = false
        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.addSublayer(disque)
            disque.contentsGravity = .resizeAspectFill
            disque.masksToBounds = true
        }
        required init?(coder: NSCoder) { fatalError() }
        override func layout() {
            super.layout()
            CATransaction.begin(); CATransaction.setDisableActions(true)
            // le disque est toujours rond : le rognage est porté par la couche elle-même (le disque qui tourne ne déborde jamais)
            layer?.cornerRadius = min(bounds.width, bounds.height) / 2
            layer?.masksToBounds = true
            disque.bounds = CGRect(origin: .zero, size: bounds.size)
            disque.position = CGPoint(x: bounds.midX, y: bounds.midY)
            CATransaction.commit()
        }
        func appliquer(image: NSImage?, tourne: Bool) {
            CATransaction.begin(); CATransaction.setDisableActions(true)
            disque.contents = image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
            CATransaction.commit()
            if tourne == enMarche { return }
            enMarche = tourne
            if tourne {
                if disque.animation(forKey: "tour") == nil {
                    let a = CABasicAnimation(keyPath: "transform.rotation.z")
                    a.fromValue = 0; a.toValue = -2 * Double.pi
                    a.duration = 26; a.repeatCount = .infinity; a.timingFunction = CAMediaTimingFunction(name: .linear)
                    disque.add(a, forKey: "tour")
                }
                // reprise là où le disque s'était arrêté
                let arret = disque.timeOffset
                disque.speed = 1; disque.timeOffset = 0; disque.beginTime = 0
                disque.beginTime = disque.convertTime(CACurrentMediaTime(), from: nil) - arret
            } else {
                let maintenant = disque.convertTime(CACurrentMediaTime(), from: nil)
                disque.speed = 0
                disque.timeOffset = maintenant
            }
        }
    }

    func makeNSView(context: Context) -> Vue { Vue(frame: .zero) }
    func updateNSView(_ v: Vue, context: Context) { v.appliquer(image: image, tourne: tourne) }
}

// MARK: pièces

/// Un bouton rond de l'îlot : fond blanc 9 %, 18 % au survol, réduit à 90 % pendant l'appui ; le bouton lecture/pause est plein.
struct BoutonLecture: View {
    var symbole: String
    var diametre: CGFloat
    var taillePictogramme: CGFloat
    var plein = false
    var etiquette: String
    var action: () -> Void
    @State private var survol = false

    private struct Style: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.9 : 1)
                .animation(.spring(duration: 0.18, bounce: 0.2), value: configuration.isPressed)
        }
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(plein ? Color(white: survol ? 0.91 : 1) : Color.white.opacity(survol ? 0.18 : 0.09))
                Image(systemName: symbole)
                    .font(.system(size: taillePictogramme, weight: .semibold))
                    .foregroundStyle(plein ? Color.black : Color.white)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: diametre, height: diametre)
            .contentShape(Circle())
        }
        .buttonStyle(Style())
        .onHover { survol = $0 }
        .accessibilityLabel(etiquette)
    }
}

/// La trace sonore qui sert de barre : 54 barres, la part déjà écoutée teintée (avec sa lueur). Un trait blanc au survol ou pendant le glissement.
struct TraceBarre: View {
    var fraction: Double
    var teinte: TeintePochette
    var actif: Bool
    static let hauteurs = TraceSonore.hauteurs()
    static let barreEcran: CGFloat = 4, ecartEcran: CGFloat = 1.5
    /// Largeur (dans le repère de la maquette) qui donne des barres de 4 pt et des écarts de 1,5 pt à l'écran.
    static let largeur: CGFloat = (CGFloat(hauteurs.count) * barreEcran + CGFloat(hauteurs.count - 1) * ecartEcran) / LectureMesures.echelle

    var body: some View {
        Canvas { ctx, taille in
            let n = Self.hauteurs.count
            // Dessinée à l'échelle de l'îlot (78 %) : barres de 4 pt et écarts de 1,5 pt À L'ÉCRAN (8 et 3 pixels sur un écran Retina), pour
            // qu'aucune barre ne tombe entre deux pixels ; `Self.largeur` est la largeur qui donne exactement ces mesures.
            let ecart = Self.ecartEcran / LectureMesures.echelle
            let l = Self.barreEcran / LectureMesures.echelle
            func barre(_ i: Int) -> Path {
                let h = max(3, taille.height * CGFloat(Self.hauteurs[i]))
                return Path(roundedRect: CGRect(x: CGFloat(i) * (l + ecart), y: (taille.height - h) / 2, width: l, height: h), cornerRadius: 1.5 / LectureMesures.echelle)
            }
            for i in 0..<n { ctx.fill(barre(i), with: .color(.white.opacity(0.2))) }
            let x = taille.width * CGFloat(min(1, max(0, fraction)))
            if x > 0.5 {
                ctx.drawLayer { couche in
                    couche.clip(to: Path(CGRect(x: 0, y: -4, width: x, height: taille.height + 8)))
                    couche.addFilter(.shadow(color: teinteSwiftUI(teinte.clair).opacity(0.85), radius: 4))
                    for i in 0..<n {
                        couche.fill(barre(i), with: .linearGradient(Gradient(colors: [teinteSwiftUI(teinte.profond), teinteSwiftUI(teinte.clair)]),
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

/// La pochette. Chaîne de repli : l'image du système, sinon la miniature de la vidéo (déposée dans `m.image` par le contrôleur), sinon l'icône
/// de l'app qui joue, en petit sur fond sombre, sinon un pictogramme sobre.
struct PochetteLecture: View {
    @ObservedObject var m: LectureModele
    /// La mini-miniature de la dictée : l'image réduite à la main, jamais en rotation.
    var miniature = false
    var body: some View {
        ZStack {
            Color(white: 0.11)
            if let image = m.image {
                if miniature {
                    Image(nsImage: m.imageMini ?? image).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                } else if m.genre == .musique && !m.statique {
                    ImageRotative(image: image, tourne: m.joue && !m.reduire)
                } else {
                    Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                }
            } else if let icone = m.iconeApp {
                GeometryReader { geo in
                    Image(nsImage: icone).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                        .frame(width: geo.size.width * (miniature ? 0.86 : 0.58), height: geo.size.height * (miniature ? 0.86 : 0.58))
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
            } else {
                Image(systemName: m.genre == .musique ? "music.note" : "play.rectangle.fill")
                    .font(.system(size: 14, weight: .regular)).foregroundStyle(Palette.texte3)
            }
        }
    }
}

// MARK: l'îlot

struct IlotVue: View, Animatable {
    var p: CGFloat
    var absence: CGFloat
    @ObservedObject var m: LectureModele
    var tailleFenetre: CGSize

    @State private var survolBarre = false
    @State private var echellePochette: CGFloat = 1
    @State private var anneau: CGFloat = 0

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(p, absence) }
        set { p = newValue.first; absence = newValue.second }
    }

    private func L(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * p }

    var body: some View {
        let g = m.geometrie
        let dy = LectureMesures.decalage(g)
        let reposL = LectureMesures.largeurRepos(g)
        let largeur = max(L(reposL, LectureMesures.ouvertLargeur), reposL * 0.96)
        let hauteur = max(L(g.hauteur, LectureMesures.hauteurOuvert(g)), g.hauteur * 0.96)
        let rayon = L(g.hauteur / 2, LectureMesures.rayonOuvert)
        let genreMusique = m.genre == .musique
        let tailleP = L(LectureMesures.pochetteRepos, LectureMesures.pochetteOuvert)
        let e = LectureMesures.echelle
        let xP = L(12, 30 * e), yP = L((g.hauteur - LectureMesures.pochetteRepos) / 2, (60 + dy) * e)
        let rayonP = genreMusique ? tailleP / 2 : L(9, 30)
        let oc = lisse((p - 0.42) / 0.5) * (1 - lisse(absence * 2.4))
        let present = 1 - lisse(absence)
        let t = m.teinte
        let forme = FormeIlot(largeur: largeur, hauteur: hauteur, rayon: rayon, oreille: min(1, p * 3),
                              largeurBarre: L(reposL, LectureMesures.largeurBarre(g)), hauteurBarre: g.hauteur)

        ZStack(alignment: .top) {
            // fond noir, filet clair, ombre portée
            forme.fill(Color.black)
                .overlay(forme.stroke(Color.white.opacity(0.08), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.55 * Double(lisse(p)) * Double(present)), radius: 22, x: 0, y: 14)

            // île : tout le reste est dans le repère de l'îlot (origine en haut à gauche), rogné à la forme
            ZStack(alignment: .topLeading) {
                // lueur teintée par la pochette
                if let image = m.image ?? m.iconeApp, p > 0.05 {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: LectureMesures.ouvertLargeur, height: LectureMesures.hauteurOuvert(g))
                        .scaleEffect(1.5)
                        .blur(radius: 26).saturation(1.5)
                        .mask(RadialGradient(colors: [.black, .clear], center: UnitPoint(x: 0.15, y: 0.5), startRadius: 0, endRadius: LectureMesures.ouvertLargeur * 0.5))
                        .opacity(0.42 * Double(lisse((p - 0.1) / 0.6)) * Double(1 - lisse(absence * 2)))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }

                // pochette : de 30 pt dans l'aile à 140 pt déployée
                PochetteLecture(m: m)
                    .frame(width: tailleP, height: tailleP)
                    .clipShape(RoundedRectangle(cornerRadius: rayonP, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: rayonP, style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
                    .overlay(RoundedRectangle(cornerRadius: rayonP, style: .continuous).strokeBorder(teinteSwiftUI(t.clair), lineWidth: 1.5)
                        .scaleEffect(1 + anneau * 0.4).opacity(Double(1 - anneau) * (anneau > 0 ? 1 : 0)))
                    .scaleEffect(echellePochette)
                    .offset(x: xP, y: yP)
                    .opacity(Double(1 - lisse(absence * 1.8)))
                    .accessibilityLabel("Pochette")

                // égaliseur de l'aile droite
                Group {
                    if m.statique { EgaliseurFixe(teinte: t.clair, joue: m.joue) }
                    else { Egaliseur(teinte: t.clair, joue: m.joue, reduire: m.reduire) }
                }
                .frame(width: LectureMesures.egaliseurLargeur, height: LectureMesures.egaliseurHauteur)
                .offset(x: largeur - LectureMesures.egaliseurMargeDroite - LectureMesures.egaliseurLargeur,
                        y: (g.hauteur - LectureMesures.egaliseurHauteur) / 2)
                .opacity(Double(1 - lisse(absence * 2)) * Double(1 - lisse(p * 4)))
                .accessibilityHidden(true)

                // contenu déplié
                if oc > 0.001 {
                    contenu(g: g, dy: dy)
                        .frame(width: LectureMesures.ouvertLargeurBase, height: LectureMesures.ouvertHauteurBase + dy, alignment: .topLeading)
                        .scaleEffect(LectureMesures.echelle, anchor: .topLeading)
                        // le contenu arrive après la forme : fondu léger et petite montée de 5 pt
                        .offset(y: (1 - oc) * 5)
                        .blur(radius: (1 - oc) * 4)
                        .opacity(Double(oc))
                        .allowsHitTesting(oc > 0.6)
                }
            }
            .frame(width: largeur, height: hauteur, alignment: .topLeading)
            .clipShape(forme)
            .contentShape(Rectangle())
        }
        .scaleEffect(1 - 0.04 * lisse(absence), anchor: .top)
        .opacity(Double(present) * Double(m.opacite))
        .frame(width: tailleFenetre.width, height: tailleFenetre.height, alignment: .top)
        .onChange(of: m.pop) { _, _ in
            guard !m.reduire else { return }
            echellePochette = 0.86
            withAnimation(.spring(duration: 0.42, bounce: 0.45)) { echellePochette = 1 }
        }
        .onChange(of: m.impulsion) { _, _ in
            guard !m.reduire else { return }
            anneau = 0.001
            withAnimation(.easeOut(duration: 1.3)) { anneau = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.35) { anneau = 0 }
        }
    }

    // MARK: contenu déplié

    @ViewBuilder
    private func contenu(g: GeometrieEncoche, dy: CGFloat) -> some View {
        let t = m.teinte
        ZStack(alignment: .topLeading) {
            // « En lecture » dans la barre, à gauche de la caméra
            HStack(spacing: 7) {
                Circle().fill(teinteSwiftUI(t.clair)).frame(width: 6, height: 6)
                    .shadow(color: teinteSwiftUI(t.clair), radius: 4.5)
                    .opacity(m.joue ? 1 : 0.4)
                Text(m.joue ? "En lecture" : "En pause").font(.system(size: 11.5)).foregroundStyle(Palette.texte2)
            }
            .frame(height: g.hauteur / LectureMesures.echelle)
            // dans la bande de la barre des menus, à gauche de la caméra (jamais au-delà de la bande de la dictée)
            .offset(x: (LectureMesures.epaule(g) + 14) / LectureMesures.echelle, y: 0)

            VStack(alignment: .leading, spacing: 0) {
                Text(m.morceau?.titre ?? "")
                    .font(.system(size: 18, weight: .semibold)).tracking(-0.2).foregroundStyle(.white)
                    .lineLimit(1).truncationMode(.tail)
                    .frame(width: 376, height: 24, alignment: .leading)
                HStack(spacing: 6) {
                    if let icone = m.iconeApp {
                        Image(nsImage: icone).resizable().interpolation(.high).frame(width: 14, height: 14)
                            .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
                    }
                    Text(m.libelleSource).font(.system(size: 13)).foregroundStyle(Palette.texte2).lineLimit(1).truncationMode(.tail)
                }
                .frame(width: 376, height: 18, alignment: .leading)
                .padding(.top, 2)
            }
            .offset(x: 196, y: 52 + dy)

            barreEtTemps(dy: dy)

            // Commandes (Hugues : « pas bien dimensionnées ni bien placées », et « passer à la musique d'avant ») :
            // musique = précédent · lecture · suivant ; vidéo = −10 s · lecture · +10 s · suivant. Tailles proches d'Apple,
            // une marge sous la rangée, rangée centrée sous le titre.
            HStack(spacing: 18) {
                if m.genre == .musique {
                    BoutonLecture(symbole: "backward.fill", diametre: 42, taillePictogramme: 18, etiquette: "Précédent") { m.surPrecedent() }
                    BoutonLecture(symbole: m.joue ? "pause.fill" : "play.fill", diametre: 50, taillePictogramme: 21, plein: true, etiquette: m.joue ? "Pause" : "Lecture") { m.surBascule() }
                    BoutonLecture(symbole: "forward.fill", diametre: 42, taillePictogramme: 18, etiquette: "Suivant") { m.surSuivant() }
                } else {
                    BoutonLecture(symbole: "gobackward.10", diametre: 42, taillePictogramme: 18, etiquette: "Reculer de 10 secondes") { m.surSaut(-10) }
                    BoutonLecture(symbole: m.joue ? "pause.fill" : "play.fill", diametre: 50, taillePictogramme: 21, plein: true, etiquette: m.joue ? "Pause" : "Lecture") { m.surBascule() }
                    BoutonLecture(symbole: "goforward.10", diametre: 42, taillePictogramme: 18, etiquette: "Avancer de 10 secondes") { m.surSaut(10) }
                    BoutonLecture(symbole: "forward.end.fill", diametre: 42, taillePictogramme: 16, etiquette: "Suivant") { m.surSuivant() }
                }
            }
            .frame(width: 376, height: 50)
            .offset(x: 196, y: 160 + dy)
        }
    }

    @ViewBuilder
    private func barreEtTemps(dy: CGFloat) -> some View {
        let teinte = m.teinte
        TimelineView(.periodic(from: .now, by: 0.2)) { contexte in
            let duree = m.morceau?.duree
            let position = m.positionAffichee(a: contexte.date)
            let fraction = (position != nil && duree != nil) ? TempsLecture.fraction(position: position!, duree: duree!) : 0
            ZStack(alignment: .topLeading) {
                if m.morceau?.positionnable == true, let duree {
                    TraceBarre(fraction: fraction, teinte: teinte, actif: survolBarre || m.fractionGlissee != nil)
                        .frame(width: TraceBarre.largeur, height: 34)
                        .scaleEffect(x: 1, y: m.fractionGlissee != nil ? 1.12 : 1)
                        .animation(.spring(duration: 0.2, bounce: 0.2), value: m.fractionGlissee != nil)
                        .contentShape(Rectangle())
                        .onHover { survolBarre = $0 }
                        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
                            .onChanged { v in m.fractionGlissee = TempsLecture.fractionSousSouris(x: v.location.x, largeur: TraceBarre.largeur) }
                            .onEnded { v in
                                let f = TempsLecture.fractionSousSouris(x: v.location.x, largeur: TraceBarre.largeur)
                                m.fractionGlissee = nil
                                m.surPosition(TempsLecture.position(fraction: f, duree: duree))
                                m.surFinGlissement()
                            })
                        .accessibilityElement()
                        .accessibilityLabel("Position")
                        .accessibilityValue("\(TempsLecture.format(position ?? 0)) sur \(TempsLecture.format(duree))")
                    HStack {
                        Text(TempsLecture.format(position ?? 0))
                        Spacer(minLength: 0)
                        Text(TempsLecture.restant(position: position ?? 0, duree: duree))
                    }
                    .font(.system(size: 12).monospacedDigit()).foregroundStyle(Palette.texte3)
                    .frame(width: TraceBarre.largeur).offset(y: 38)
                } else {
                    // direct, ou durée inconnue : pas de barre à glisser
                    Text(m.morceau?.joue == true ? "En direct" : "Durée inconnue")
                        .font(.system(size: 12)).foregroundStyle(Palette.texte3)
                        .frame(width: TraceBarre.largeur, height: 34, alignment: .leading)
                }
            }
            .frame(width: TraceBarre.largeur, height: 54, alignment: .topLeading)
        }
        .offset(x: 196, y: 106 + dy)
    }
}

/// Le contenu de la fenêtre de l'îlot : relit l'état animé du modèle et le passe à `IlotVue` (qui interpole `p` et `absence`).
struct LectureHote: View {
    @ObservedObject var m: LectureModele
    var tailleFenetre: CGSize
    var body: some View {
        IlotVue(p: m.progres, absence: m.absence, m: m, tailleFenetre: tailleFenetre)
            .onTapGesture { m.surClicIlot() }   // un clic hors des boutons et de la barre : épingler / désépingler
    }
}


// MARK: mini-miniature pendant la dictée

/// La lecture pendant une dictée : une mini-miniature de 18 pt DANS le ruban de la dictée (au bout, côté droit). La vraie image de ce qui
/// joue (pochette, miniature de la vidéo, à défaut icône de l'app), légèrement assombrie, avec un fin glyphe pause blanc ; ronde pour la
/// musique. Un clic dessus reprend la lecture. Apparaît et disparaît en fondu doux avec la pause et la reprise.
struct MiniatureLectureVue: View {
    @ObservedObject var m: LectureModele
    /// 0 = absente, 1 = présente.
    var presence: CGFloat
    static let cote: CGFloat = 18
    @State private var survol = false

    private var forme: AnyShape { m.genre == .musique ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 4.5, style: .continuous)) }

    var body: some View {
        Button { m.surReprise() } label: {
            ZStack {
                PochetteLecture(m: m, miniature: true)
                    .frame(width: Self.cote, height: Self.cote)
                    .overlay(Color.black.opacity(m.image == nil ? (survol ? 0.22 : 0.36) : (survol ? 0.30 : 0.46)))
                Image(systemName: "pause.fill").font(.system(size: 7.5, weight: .bold)).foregroundStyle(.white.opacity(0.95))
            }
            .frame(width: Self.cote, height: Self.cote)
            .clipShape(forme)
            .overlay(forme.stroke(Color.white.opacity(0.14), lineWidth: 0.5))
            .contentShape(Rectangle().inset(by: -4))
        }
        .buttonStyle(.plain)
        .onHover { survol = $0 }
        .scaleEffect(0.82 + 0.18 * presence)
        .opacity(Double(min(1, max(0, presence))))
        .animation(.easeOut(duration: 0.12), value: survol)
        .accessibilityLabel("Reprendre la lecture")
    }
}
