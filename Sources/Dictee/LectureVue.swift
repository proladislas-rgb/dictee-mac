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
    static let margeReposLaterale: CGFloat = 12
    static let margeBasse: CGFloat = 30
    static let reposMargeBasse: CGFloat = 6
    static let ondeLargeur: CGFloat = 50
    static let ondeHauteur: CGFloat = 24

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
/// coins du bas arrondis. Le centre n'est jamais dessiné à part : c'est du noir, la caméra.
struct FormeIlot: Shape {
    var largeur: CGFloat
    var hauteur: CGFloat
    var rayon: CGFloat
    var oreille: CGFloat   // 0…1

    func path(in rect: CGRect) -> Path {
        let k: CGFloat = 0.5522847498
        var p = Path()
        let x0 = rect.midX - largeur / 2, x1 = rect.midX + largeur / 2
        let R = max(0, min(rayon, hauteur / 2 + 12, largeur / 2))
        let e = 10 * min(1, max(0, oreille))
        p.move(to: CGPoint(x: x0 - e, y: 0))
        p.addLine(to: CGPoint(x: x1 + e, y: 0))
        // congé concave droit : de (x1 + e, 0) à (x1, e)
        p.addCurve(to: CGPoint(x: x1, y: e), control1: CGPoint(x: x1 + e - k * e, y: 0), control2: CGPoint(x: x1, y: e - k * e))
        p.addLine(to: CGPoint(x: x1, y: hauteur - R))
        p.addCurve(to: CGPoint(x: x1 - R, y: hauteur), control1: CGPoint(x: x1, y: hauteur - R + k * R), control2: CGPoint(x: x1 - R + k * R, y: hauteur))
        p.addLine(to: CGPoint(x: x0 + R, y: hauteur))
        p.addCurve(to: CGPoint(x: x0, y: hauteur - R), control1: CGPoint(x: x0 + R - k * R, y: hauteur), control2: CGPoint(x: x0, y: hauteur - R + k * R))
        p.addLine(to: CGPoint(x: x0, y: e))
        p.addCurve(to: CGPoint(x: x0 - e, y: 0), control1: CGPoint(x: x0, y: e - k * e), control2: CGPoint(x: x0 - e + k * e, y: 0))
        p.closeSubpath()
        return p
    }
}

// MARK: couches Core Animation (aucune charge pour l'app : l'animation tourne dans le serveur d'affichage)

/// L'onde sinusoïdale de l'aile droite : défile et respire tant que ça joue, se fige (amplitude basse) en pause.
struct OndeSinus: NSViewRepresentable {
    var teinte: CouleurRVB
    var joue: Bool
    var reduire: Bool

    final class Vue: NSView {
        private let amplitude = CALayer()
        private let defilement = CAShapeLayer()
        private var enMarche = false
        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.masksToBounds = true
            let l = LectureMesures.ondeLargeur, h = LectureMesures.ondeHauteur
            amplitude.frame = CGRect(x: 0, y: 0, width: l, height: h)
            defilement.frame = CGRect(x: 0, y: 0, width: 2 * l, height: h)
            // deux périodes complètes (100 pt) : le motif défile d'une période (50 pt) puis recommence
            let chemin = CGMutablePath()
            let demi = l / 2, haut: CGFloat = 1.5, bas = h - 1.5, milieu = h / 2
            chemin.move(to: CGPoint(x: 0, y: milieu))
            for i in 0..<4 {
                let x = CGFloat(i) * demi, sommet = i % 2 == 0 ? haut : bas
                chemin.addCurve(to: CGPoint(x: x + demi, y: milieu), control1: CGPoint(x: x + demi * 0.25, y: sommet), control2: CGPoint(x: x + demi * 0.75, y: sommet))
            }
            defilement.path = chemin
            defilement.fillColor = nil
            defilement.lineWidth = 2.4
            defilement.lineCap = .round
            amplitude.addSublayer(defilement)
            layer?.addSublayer(amplitude)
        }
        required init?(coder: NSCoder) { fatalError() }
        override var isFlipped: Bool { true }

        func appliquer(teinte: CouleurRVB, joue: Bool, reduire: Bool) {
            let c = CGColor(srgbRed: teinte.r, green: teinte.g, blue: teinte.b, alpha: 1)
            defilement.strokeColor = c
            // la lueur est portée par la vue, hors du masque : on la pose sur le calque de la vue lui-même
            layer?.shadowColor = c; layer?.shadowOpacity = 0.9; layer?.shadowRadius = 5; layer?.shadowOffset = .zero
            layer?.masksToBounds = false
            amplitude.masksToBounds = true
            let marche = joue && !reduire
            if marche == enMarche { if !marche { fixer() }; return }
            enMarche = marche
            defilement.removeAllAnimations(); amplitude.removeAllAnimations()
            guard marche else { fixer(); return }
            amplitude.setAffineTransform(.identity)
            let flux = CABasicAnimation(keyPath: "position.x")
            flux.fromValue = defilement.position.x; flux.toValue = defilement.position.x - LectureMesures.ondeLargeur
            flux.duration = 1.5; flux.repeatCount = .infinity; flux.timingFunction = CAMediaTimingFunction(name: .linear)
            defilement.add(flux, forKey: "flux")
            let souffle = CABasicAnimation(keyPath: "transform.scale.y")
            souffle.fromValue = 0.35; souffle.toValue = 1
            souffle.duration = 1.2; souffle.autoreverses = true; souffle.repeatCount = .infinity
            souffle.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            amplitude.add(souffle, forKey: "souffle")
        }
        private func fixer() { amplitude.setAffineTransform(CGAffineTransform(scaleX: 1, y: 0.4)) }
    }

    func makeNSView(context: Context) -> Vue { Vue(frame: CGRect(x: 0, y: 0, width: LectureMesures.ondeLargeur, height: LectureMesures.ondeHauteur)) }
    func updateNSView(_ v: Vue, context: Context) { v.appliquer(teinte: teinte, joue: joue, reduire: reduire) }
}

/// La même onde, immobile, pour les rendus PNG.
struct OndeFixe: View {
    var teinte: CouleurRVB
    var body: some View {
        Path { p in
            let l = LectureMesures.ondeLargeur, h = LectureMesures.ondeHauteur, demi = l / 2
            let a: CGFloat = 0.95
            let milieu = h / 2
            p.move(to: CGPoint(x: 0, y: milieu))
            for i in 0..<2 {
                let x = CGFloat(i) * demi, sommet = i % 2 == 0 ? milieu - (milieu - 1.5) * a : milieu + (milieu - 1.5) * a
                p.addCurve(to: CGPoint(x: x + demi, y: milieu), control1: CGPoint(x: x + demi * 0.25, y: sommet), control2: CGPoint(x: x + demi * 0.75, y: sommet))
            }
        }
        .stroke(teinteSwiftUI(teinte), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        .shadow(color: teinteSwiftUI(teinte).opacity(0.9), radius: 5)
        .frame(width: LectureMesures.ondeLargeur, height: LectureMesures.ondeHauteur)
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

    var body: some View {
        Canvas { ctx, taille in
            let n = Self.hauteurs.count
            let ecart: CGFloat = 2
            let l = (taille.width - ecart * CGFloat(n - 1)) / CGFloat(n)
            func barre(_ i: Int) -> Path {
                let h = max(3, taille.height * CGFloat(Self.hauteurs[i]))
                return Path(roundedRect: CGRect(x: CGFloat(i) * (l + ecart), y: (taille.height - h) / 2, width: l, height: h), cornerRadius: 1.5)
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

/// La pochette (ou, à défaut, une pastille sobre).
struct PochetteLecture: View {
    @ObservedObject var m: LectureModele
    var body: some View {
        ZStack {
            Color(white: 0.11)
            if let image = m.image {
                if m.genre == .musique && !m.statique {
                    ImageRotative(image: image, tourne: m.joue && !m.reduire)
                } else {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
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
        let oc = lisse((p - 0.5) / 0.35) * (1 - lisse(absence * 2.4))
        let present = 1 - lisse(absence)
        let t = m.teinte
        let forme = FormeIlot(largeur: largeur, hauteur: hauteur, rayon: rayon, oreille: min(1, p * 3))

        ZStack(alignment: .top) {
            // fond noir, filet clair, ombre portée
            forme.fill(Color.black)
                .overlay(forme.stroke(Color.white.opacity(0.08), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.55 * Double(lisse(p)) * Double(present)), radius: 22, x: 0, y: 14)

            // île : tout le reste est dans le repère de l'îlot (origine en haut à gauche), rogné à la forme
            ZStack(alignment: .topLeading) {
                // lueur teintée par la pochette
                if let image = m.image, p > 0.05 {
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

                // onde de l'aile droite
                Group {
                    if m.statique { OndeFixe(teinte: t.clair) }
                    else { OndeSinus(teinte: t.clair, joue: m.joue, reduire: m.reduire) }
                }
                .frame(width: LectureMesures.ondeLargeur, height: LectureMesures.ondeHauteur)
                .offset(x: largeur - 12 - LectureMesures.ondeLargeur, y: (g.hauteur - LectureMesures.ondeHauteur) / 2)
                .opacity(Double(1 - lisse(absence * 2)))
                .accessibilityHidden(true)

                // contenu déplié
                if oc > 0.001 {
                    contenu(g: g, dy: dy)
                        .frame(width: LectureMesures.ouvertLargeurBase, height: LectureMesures.ouvertHauteurBase + dy, alignment: .topLeading)
                        .scaleEffect((0.94 + 0.06 * oc) * LectureMesures.echelle, anchor: .topLeading)
                        .blur(radius: (1 - oc) * 9)
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
            .frame(height: g.hauteur)
            .offset(x: 28, y: 0)

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

            HStack(spacing: 14) {
                BoutonLecture(symbole: "gobackward.10", diametre: 52, taillePictogramme: 22, etiquette: "Reculer de 10 secondes") { m.surSaut(-10) }
                BoutonLecture(symbole: m.joue ? "pause.fill" : "play.fill", diametre: 62, taillePictogramme: 26, plein: true, etiquette: m.joue ? "Pause" : "Lecture") { m.surBascule() }
                BoutonLecture(symbole: "goforward.10", diametre: 52, taillePictogramme: 22, etiquette: "Avancer de 10 secondes") { m.surSaut(10) }
                BoutonLecture(symbole: "forward.end.fill", diametre: 52, taillePictogramme: 20, etiquette: "Suivant") { m.surSuivant() }
            }
            .frame(width: 376, height: 62)
            .offset(x: 196, y: 166 + dy - 2)
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
                        .frame(width: 376, height: 34)
                        .scaleEffect(x: 1, y: m.fractionGlissee != nil ? 1.12 : 1)
                        .animation(.spring(duration: 0.2, bounce: 0.2), value: m.fractionGlissee != nil)
                        .contentShape(Rectangle())
                        .onHover { survolBarre = $0 }
                        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
                            .onChanged { v in m.fractionGlissee = TempsLecture.fractionSousSouris(x: v.location.x, largeur: 376) }
                            .onEnded { v in
                                let f = TempsLecture.fractionSousSouris(x: v.location.x, largeur: 376)
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
                    .frame(width: 376).offset(y: 38)
                } else {
                    // direct, ou durée inconnue : pas de barre à glisser
                    Text(m.morceau?.joue == true ? "En direct" : "Durée inconnue")
                        .font(.system(size: 12)).foregroundStyle(Palette.texte3)
                        .frame(width: 376, height: 34, alignment: .leading)
                }
            }
            .frame(width: 376, height: 54, alignment: .topLeading)
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

// MARK: bulle pendant la dictée

/// Petite bulle ronde détachée, à droite de l'encoche de dictée : la pochette (à demi éteinte) et l'icône pause.
struct BulleLectureVue: View {
    @ObservedObject var m: LectureModele
    /// 0 = absente, 1 = présente (animé par ressort).
    var presence: CGFloat
    /// Écart horizontal depuis le bord gauche de la vue jusqu'à la bulle (animé quand la dictée passe en mains libres).
    var decalage: CGFloat
    var taille: CGSize

    var body: some View {
        ZStack {
            Circle().fill(Color.black)
                .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 8)
            PochetteLecture(m: m)
                .frame(width: 28, height: 28)
                .clipShape(Circle())
                .opacity(0.5)
            if !m.joue {
                Image(systemName: "pause.fill").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                    .transition(.opacity)
            }
        }
        .frame(width: 36, height: 36)
        .scaleEffect(0.4 + 0.6 * presence)
        .opacity(Double(min(1, max(0, (presence - 0.15) / 0.6))))
        .offset(x: decalage, y: 1)
        .frame(width: taille.width, height: taille.height, alignment: .topLeading)
        .animation(.easeOut(duration: 0.12), value: m.joue)
        .accessibilityLabel(m.joue ? "Lecture en cours" : "Lecture en pause pendant la dictée")
    }
}
