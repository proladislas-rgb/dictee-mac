import AppKit
import SwiftUI
import DicteeCore

/// Les illustrations des cartes d'accueil : `Contents/Resources/Illustrations/<nom>.png` dans l'app, `Resources/Illustrations/` du
/// dépôt pour les rendus lancés depuis le dossier de travail. Une pièce absente n'empêche rien : la scène montre un repli sobre.
@MainActor
enum Illustrations {
    private static var cache: [String: NSImage] = [:]
    private static var absentes: Set<String> = []
    private static var barresOnde: [(debut: Double, fin: Double)]?

    static let dossiers: [URL] = [
        Bundle.main.resourceURL?.appendingPathComponent("Illustrations", isDirectory: true),
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Illustrations", isDirectory: true),
    ].compactMap { $0 }

    static func image(_ nom: String) -> NSImage? {
        if let i = cache[nom] { return i }
        if absentes.contains(nom) { return nil }
        for d in dossiers {
            let url = d.appendingPathComponent("\(nom).png")
            if FileManager.default.fileExists(atPath: url.path), let i = NSImage(contentsOf: url) { cache[nom] = i; return i }
        }
        absentes.insert(nom)
        return nil
    }

    /// Toutes les pièces d'une carte sont là (sinon : le repli).
    static func completes(carte: Int) -> Bool { IllustrationsAccueil.calques(carte: carte).allSatisfy { image($0) != nil } }

    /// Les neuf barres de l'onde 5a, lues une fois dans sa transparence (colonnes vides entre les barres).
    static func barres() -> [(debut: Double, fin: Double)] {
        if let b = barresOnde { return b }
        guard let i = image("5a"), let cg = i.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return [] }
        let w = cg.width, h = cg.height
        var octets = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &octets, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var colonnes = [Int](repeating: 0, count: w)
        for y in 0..<h { for x in 0..<w where octets[(y * w + x) * 4 + 3] > 40 { colonnes[x] += 1 } }
        let b = IllustrationsAccueil.barres(colonnes: colonnes)
        barresOnde = b
        return b
    }
}

/// Une toile d'illustration (1536 × 1024, ou 1536 × 512 pour l'onde) posée dans le cadre de la scène : `fenetre` est la partie de
/// la toile qu'on voit (en fractions), le reste est rogné par la carte. Toutes les pièces d'une carte partagent la même toile : la
/// scène se dessine en coordonnées de toile (ancres et positions en fractions), puis la toile entière est posée dans le cadre.
struct Toile {
    var taille: CGSize          // la toile entière, en points
    var origine: CGPoint        // son coin haut-gauche dans le cadre

    init(cadre: CGSize, fenetre: CGRect, rapport: CGFloat = 1.5) {
        // toute la fenêtre demandée est visible (et un peu plus d'un côté si les proportions diffèrent)
        let echelle = min(cadre.width / fenetre.width, cadre.height * rapport / fenetre.height)
        taille = CGSize(width: echelle, height: echelle / rapport)
        origine = CGPoint(x: cadre.width / 2 - fenetre.midX * taille.width, y: cadre.height / 2 - fenetre.midY * taille.height)
    }
    /// Un point de la toile (fractions), en points de toile.
    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * taille.width, y: y * taille.height) }
    /// Un point de la toile (fractions) en ancre du cadre : pour les effets posés sur la scène entière (perspective, zoom).
    func ancre(_ x: CGFloat, _ y: CGFloat, dans cadre: CGSize) -> UnitPoint {
        UnitPoint(x: (origine.x + x * taille.width) / cadre.width, y: (origine.y + y * taille.height) / cadre.height)
    }
}

/// Une pièce : l'image entière, à la taille de la toile (ses transformations s'ancrent en fractions de toile).
struct Piece: View {
    var nom: String
    var toile: Toile
    var body: some View {
        Group {
            if let i = Illustrations.image(nom) { Image(nsImage: i).resizable().interpolation(.high) } else { Color.clear }
        }
        .frame(width: toile.taille.width, height: toile.taille.height)
    }
}

/// Pose la toile d'une scène dans son cadre, rognée par lui. Aucune perspective (`rotation3DEffect`) à l'intérieur : posée sous un
/// décalage, elle se dessine à l'origine (constaté) ; elle se pose sur la scène entière, après.
struct PoseToile<Contenu: View>: View {
    var toile: Toile
    var cadre: CGSize
    @ViewBuilder var contenu: Contenu
    var body: some View {
        ZStack(alignment: .topLeading) { contenu }
            .frame(width: toile.taille.width, height: toile.taille.height, alignment: .topLeading)
            .offset(x: toile.origine.x, y: toile.origine.y)
            .frame(width: cadre.width, height: cadre.height, alignment: .topLeading)
            .clipped()
    }
}

extension View {
    /// Décale une pièce de `dx`, `dy` (fractions de la toile).
    func decale(_ toile: Toile, _ dx: CGFloat, _ dy: CGFloat) -> some View { offset(x: dx * toile.taille.width, y: dy * toile.taille.height) }
}

/// L'illustration animée d'une carte d'accueil : une scène en mouvement continu, fonction du temps. Elle tourne seulement quand la
/// carte est à l'écran (`actif`) ; « Réduire les animations » donne une image posée.
struct IllustrationAccueil: View {
    var carte: Int
    var actif: Bool
    @Environment(\.accessibilityReduceMotion) private var reduire
    @Environment(\.renduStatique) private var statique
    @Environment(\.tempsScene) private var tempsImpose
    @State private var debut = Date()

    var body: some View {
        if statique {
            // rendus : l'instant demandé (vidéo image par image), sinon l'image posée
            SceneAccueil(carte: carte, t: tempsImpose ?? SceneAccueil.imagePosee(carte))
        } else {
            TimelineView(.animation(minimumInterval: nil, paused: !actif || reduire)) { ctx in
                SceneAccueil(carte: carte, t: reduire ? SceneAccueil.imagePosee(carte) : ctx.date.timeIntervalSince(debut))
            }
            .onChange(of: carte) { _, _ in debut = Date() }
        }
    }
}

private struct CleTempsScene: EnvironmentKey { static let defaultValue: Double? = nil }
extension EnvironmentValues {
    /// Rendus seulement : l'instant de la scène à dessiner (la vidéo de contrôle, image par image).
    var tempsScene: Double? {
        get { self[CleTempsScene.self] }
        set { self[CleTempsScene.self] = newValue }
    }
}

/// La scène d'une carte à l'instant `t` (secondes depuis son début). Pure : la même image dans l'app et dans la vidéo de contrôle.
struct SceneAccueil: View {
    var carte: Int
    var t: Double

    /// L'instant montré quand « Réduire les animations » est allumé : le moment le plus parlant de chaque scène.
    static func imagePosee(_ carte: Int) -> Double { [1: 1.7, 2: 0.9, 3: 2.4, 4: 2.9, 5: 1.1][carte] ?? 0 }
    /// La durée d'une boucle (la vidéo de contrôle en montre au moins une).
    static func boucle(_ carte: Int) -> Double { [1: SceneFn.boucle, 2: SceneMicro.boucle, 3: SceneEcrire.boucle, 4: SceneCle.boucle, 5: 4][carte] ?? 4 }

    var body: some View {
        GeometryReader { g in
            if Illustrations.completes(carte: carte) {
                switch carte {
                case 1: SceneFn(t: t, cadre: g.size)
                case 2: SceneMicro(t: t, cadre: g.size)
                case 3: SceneEcrire(t: t, cadre: g.size)
                case 4: SceneCle(t: t, cadre: g.size)
                default: SceneOnde(t: t, cadre: g.size)
                }
            } else {
                RepliIllustration(carte: carte)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(IllustrationsAccueil.calques(carte: carte).map(IllustrationsAccueil.sujet).joined(separator: ", "))
    }
}

/// Tant que les images manquent : le symbole de la carte, posé sobrement au milieu.
struct RepliIllustration: View {
    var carte: Int
    var body: some View {
        Image(systemName: ["globe", "mic", "text.bubble", "key", "waveform"][max(0, min(4, carte - 1))])
            .font(.system(size: 54, weight: .light))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - l'onde, barre par barre

/// L'onde orange (5a) découpée en ses barres : chacune a sa hauteur (0…1) et grandit depuis son milieu.
struct OndeBarres: View {
    var largeur: CGFloat
    var hauteurs: (Int) -> Double
    var body: some View {
        let b = Illustrations.barres()
        let h = largeur / 3
        ZStack(alignment: .topLeading) {
            if let i = Illustrations.image("5a") {
                ForEach(b.indices, id: \.self) { k in
                    Image(nsImage: i).resizable().interpolation(.high)
                        .frame(width: largeur, height: h)
                        .mask(alignment: .topLeading) {
                            Rectangle().frame(width: (b[k].fin - b[k].debut) * largeur + 1, height: h).offset(x: b[k].debut * largeur - 0.5)
                        }
                        .scaleEffect(x: 1, y: max(0.001, hauteurs(k)), anchor: .center)
                }
            }
        }
        .frame(width: largeur, height: h)
    }
}

/// Des niveaux de voix qui changent tous les `pas` secondes : une somme de ressorts (un par changement), donc un mouvement continu,
/// avec élan et rebond, qui ne se répète pas barre à barre.
enum NiveauxVoix {
    static let pas = 0.16
    static func niveau(_ barre: Int, _ k: Int) -> Double {
        var x = UInt64(bitPattern: Int64(barre &* 7919 &+ k &* 104_729)) &+ 0x9E37_79B9_7F4A_7C15
        x = (x ^ (x >> 30)) &* 0xBF58_476D_1CE4_E5B9
        x = (x ^ (x >> 27)) &* 0x94D0_49BB_1331_11EB
        x ^= x >> 31
        let centre = 1 - abs(Double(barre) - 4) / 6          // plus haut au milieu, comme une voix
        return 0.35 + 0.65 * centre * (0.45 + 0.55 * Double(x % 1000) / 1000)
    }
    static func valeur(_ barre: Int, t: Double) -> Double {
        let n = Int(floor(t / pas))
        var v = niveau(barre, n - 12)
        for k in (n - 11)...max(n - 11, n) {
            v += (niveau(barre, k) - niveau(barre, k - 1)) * Ressort.valeur(t - Double(k) * pas, duree: 0.32, rebond: 0.35)
        }
        return v
    }
}

// MARK: - 1 · la touche fn

/// La caméra s'approche, l'index arrive en arc depuis le bord de la carte, la touche s'enfonce (petit écrasement), un reflet glisse
/// sur l'aluminium, l'onde orange naît de la touche et monte, chaque barre sur son ressort ; puis tout revient.
struct SceneFn: View {
    var t: Double
    var cadre: CGSize
    static let boucle = 4.6
    /// La partie de la toile qu'on voit : le coin du clavier ; le haut-droit (la base de l'index) reste hors de la carte.
    static let fenetre = CGRect(x: 0.08, y: 0.22, width: 0.58, height: 0.70)
    /// Le centre de la touche fn sur la toile.
    static let touche = UnitPoint(x: 0.37, y: 0.565)

    var body: some View {
        let s = t.truncatingRemainder(dividingBy: Self.boucle)
        let toile = Toile(cadre: cadre, fenetre: Self.fenetre)
        // la caméra s'approche puis recule ; un léger balancement donne la profondeur
        let zoom = Ressort.allerRetour(1, 1.07, t: s, aller: 0.1, retour: 3.4, duree: 1.3, dureeRetour: 1.1)
        let balance = sin(2 * .pi * t / (Self.boucle * 2))
        // l'index : levé (vers le haut et la droite, hors de la carte), il descend en arc (le vertical plus vif que l'horizontal), puis remonte
        let pX = Ressort.allerRetour(0.07, 0, t: s, aller: 0.55, retour: 2.55, duree: 0.75, dureeRetour: 0.6)
        let pY = Ressort.allerRetour(-0.11, 0, t: s, aller: 0.55, retour: 2.55, duree: 0.5, dureeRetour: 0.85)
        let pR = Ressort.allerRetour(5, 0, t: s, aller: 0.55, retour: 2.55, duree: 0.7)
        // la touche : enfoncée au contact, elle rebondit en remontant
        let appui = max(0, Ressort.allerRetour(0, 1, t: s, aller: 0.92, retour: 2.6, duree: 0.24, rebond: 0.3, dureeRetour: 0.35, rebondRetour: 0.55))
        // le reflet passe une fois ; l'onde naît au contact et monte
        let reflet = Ressort.de(-0.3, vers: 1.3, t: s, depart: 0.95, duree: 1.6)
        let onde = max(0, Ressort.allerRetour(0, 1, t: s, aller: 1.0, retour: 2.7, duree: 0.45, rebond: 0.2, dureeRetour: 0.6))
        let monte = Ressort.de(0, vers: 1, t: s, depart: 1.0, duree: 1.4)
        let levee = min(1, abs(pY) * 9)   // 1 : l'index en l'air, 0 : posé

        PoseToile(toile: toile, cadre: cadre) {
            ZStack(alignment: .topLeading) {
                Piece(nom: "1a", toile: toile)
                // la touche au repos est masquée (la touche seule ne peut pas l'effacer) : un creux sombre à sa forme, puis la touche enfoncée
                if appui > 0.01 {
                    Piece(nom: "1b", toile: toile).colorMultiply(.black).opacity(0.85)
                        .scaleEffect(1.025, anchor: Self.touche)
                        .opacity(min(1, appui * 6))
                    Piece(nom: "1b", toile: toile)
                        .scaleEffect(x: 1 + 0.012 * appui, y: 1 - 0.035 * appui, anchor: Self.touche)
                        .brightness(-0.05 * appui)
                        .decale(toile, 0, 0.006 * appui)
                        .opacity(min(1, appui * 6))
                }
                // le reflet sur l'aluminium (dans la forme du clavier)
                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .white.opacity(0.5), location: 0.5), .init(color: .clear, location: 1)],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: toile.taille.width * 0.16, height: toile.taille.height * 1.3)
                    .rotationEffect(.degrees(24))
                    .position(toile.point(reflet, 0.55))
                    .frame(width: toile.taille.width, height: toile.taille.height)
                    .blendMode(.plusLighter)
                    .mask { Piece(nom: "1a", toile: toile) }
            }

            // l'onde : elle naît de la touche, monte et s'efface, chaque barre sur son propre ressort
            OndeBarres(largeur: toile.taille.width * 0.32) { k in
                let naissance = Ressort.de(0, vers: 1, t: s, depart: 1.0 + 0.035 * Double(abs(k - 4)), duree: 0.42, rebond: 0.45)
                return naissance * onde * NiveauxVoix.valeur(k, t: t)
            }
            .shadow(color: TonsBureau.orange.opacity(0.35 * onde), radius: 8)
            .opacity(min(1, onde * 1.4))
            .position(toile.point(Self.touche.x - 0.06, Self.touche.y - 0.08 - 0.17 * monte))

            // l'index, au premier plan : un peu plus de parallaxe que le clavier, et son ombre qui s'approche quand il se pose
            Piece(nom: "1c", toile: toile)
                .rotationEffect(.degrees(pR), anchor: UnitPoint(x: 0.75, y: 0.15))
                .shadow(color: .black.opacity(0.28 - 0.1 * levee), radius: 6 + 22 * levee, x: -3 - 8 * levee, y: 6 + 40 * levee)
                .decale(toile, pX + 0.008 * balance, pY + 0.006 * appui)
        }
        // la perspective : tout le plan (clavier, touche, onde, index) penche ensemble, comme une caméra qui tourne autour
        .rotation3DEffect(.degrees(5 + 2 * balance), axis: (x: 1, y: -0.35, z: 0), anchor: toile.ancre(Self.touche.x, Self.touche.y, dans: cadre), perspective: 0.5)
        .scaleEffect(zoom, anchor: toile.ancre(Self.touche.x, Self.touche.y, dans: cadre))
    }
}

// MARK: - 2 · le micro

/// Le micro tourne doucement de quelques degrés ; derrière lui, les anneaux pulsent vers l'avant et s'effacent, l'un après l'autre.
struct SceneMicro: View {
    var t: Double
    var cadre: CGSize
    static let boucle = 3.0
    static let fenetre = CGRect(x: 0.08, y: 0.02, width: 0.84, height: 0.96)
    static let capsule = UnitPoint(x: 0.508, y: 0.36)

    var body: some View {
        let toile = Toile(cadre: cadre, fenetre: Self.fenetre)
        let tourne = sin(2 * .pi * t / (Self.boucle * 2))
        PoseToile(toile: toile, cadre: cadre) {
            ForEach(0..<3, id: \.self) { k in
                let phase = (t / Self.boucle + Double(k) / 3).truncatingRemainder(dividingBy: 1)
                let ouvre = Ressort.valeur(phase * Self.boucle, duree: 1.9)
                Piece(nom: "2b", toile: toile)
                    .scaleEffect(0.72 + 0.5 * ouvre, anchor: Self.capsule)
                    .opacity(pow(1 - phase, 1.6) * min(1, phase * 8))
                    .blur(radius: 2.5 * phase)
            }
            Piece(nom: "2a", toile: toile)
                .shadow(color: .black.opacity(0.16), radius: 12, y: 10)
                .decale(toile, 0, -0.008 * sin(2 * .pi * t / Self.boucle))
        }
        .rotation3DEffect(.degrees(8 * tourne), axis: (x: 0, y: 1, z: 0), anchor: toile.ancre(Self.capsule.x, Self.capsule.y, dans: cadre), perspective: 0.5)
    }
}

// MARK: - 3 · écrire dans tes apps

/// La bulle flotte en légère perspective ; le texte s'y écrit lettre à lettre, le curseur le suit, puis clignote.
struct SceneEcrire: View {
    var t: Double
    var cadre: CGSize
    static let boucle = 5.2
    static let fenetre = CGRect(x: 0.1, y: 0.16, width: 0.8, height: 0.74)
    static let texte = "J\u{2019}arrive à 19 h\u{202F}!"
    /// Le curseur (3b) sur sa toile : centre et hauteur.
    static let curseur = (x: 0.499, y: 0.499, hauteur: 0.246)
    static let debutTexte = (x: 0.215, y: 0.47)

    var body: some View {
        let s = t.truncatingRemainder(dividingBy: Self.boucle)
        let toile = Toile(cadre: cadre, fenetre: Self.fenetre)
        let flotte = sin(2 * .pi * t / Self.boucle)
        // le curseur dessiné fait le quart de la toile : réduit de moitié, et le texte se règle sur lui
        let reduit = 0.5
        let police = NSFont.systemFont(ofSize: toile.taille.height * Self.curseur.hauteur * reduit * 0.8, weight: .medium)
        let frappe = 0.075, debut = 0.55
        let tapees = max(0, min(Self.texte.count, Int((s - debut) / frappe)))
        let ecrit = String(Self.texte.prefix(tapees))
        let largeur = (ecrit as NSString).size(withAttributes: [.font: police]).width
        let efface = Ressort.de(1, vers: 0, t: s, depart: 4.4, duree: 0.5)
        // pendant la frappe, le curseur reste allumé ; ensuite il clignote en douceur
        let finFrappe = debut + Double(Self.texte.count) * frappe + 0.25
        let clignote = s < finFrappe ? 1 : 0.5 + 0.5 * cos(2 * .pi * (s - finFrappe) / 1.05)
        let curseur = min(1, max(0, (clignote - 0.25) * 2.2))
        let debutX = Self.debutTexte.x * toile.taille.width, ligneY = Self.debutTexte.y * toile.taille.height

        PoseToile(toile: toile, cadre: cadre) {
            ZStack(alignment: .topLeading) {
                Piece(nom: "3a", toile: toile)
                Text(ecrit).font(Font(police)).foregroundStyle(Color(hex: 0x1D1D1F)).fixedSize()
                    .opacity(efface)
                    .position(x: debutX + largeur / 2, y: ligneY)
                Piece(nom: "3b", toile: toile)
                    .scaleEffect(reduit, anchor: UnitPoint(x: Self.curseur.x, y: Self.curseur.y))
                    .offset(x: debutX + largeur + 3 - Self.curseur.x * toile.taille.width, y: ligneY - Self.curseur.y * toile.taille.height)
                    .opacity(curseur)
            }
            .shadow(color: .black.opacity(0.10), radius: 14, y: 12 + 4 * flotte)
            .decale(toile, 0, -0.01 * flotte)
        }
        .rotation3DEffect(.degrees(5 * flotte), axis: (x: 0.4, y: 1, z: 0), perspective: 0.5)
    }
}

// MARK: - 4 · la clé Groq

/// La clé arrive en tournant en 3D jusqu'au champ, s'y pose, tourne un peu comme dans une serrure ; puis la coche éclot.
struct SceneCle: View {
    var t: Double
    var cadre: CGSize
    static let boucle = 4.8
    static let fenetre = CGRect(x: 0.1, y: 0.12, width: 0.8, height: 0.8)
    static let centreCoche = UnitPoint(x: 0.4975, y: 0.4975)

    var body: some View {
        let s = t.truncatingRemainder(dividingBy: Self.boucle)
        let toile = Toile(cadre: cadre, fenetre: Self.fenetre)
        let arrive = Ressort.de(0, vers: 1, t: s, depart: 0.25, duree: 1.0, rebond: 0.18)
        let tourne3D = Ressort.de(75, vers: 0, t: s, depart: 0.25, duree: 1.15, rebond: 0.12)
        let serrure = Ressort.de(0, vers: -10, t: s, depart: 1.45, duree: 0.45, rebond: 0.4)
        let coche = Ressort.de(0, vers: 1, t: s, depart: 1.8, duree: 0.55, rebond: 0.55)
        let anneau = Ressort.de(0, vers: 1, t: s, depart: 1.8, duree: 1.2)
        let fin = Ressort.de(1, vers: 0, t: s, depart: 4.1, duree: 0.5)
        let flotte = sin(2 * .pi * t / Self.boucle)
        let diametre = toile.taille.width * 0.3 * (0.6 + 0.8 * anneau)

        PoseToile(toile: toile, cadre: cadre) {
            Piece(nom: "4b", toile: toile)
                .decale(toile, 0, -0.004 * flotte)
            // la clé tourne sur elle-même : sa largeur suit le cosinus de l'angle (un tour en 3D dessiné à plat), un peu d'ombre sur la tranche
            Piece(nom: "4a", toile: toile)
                .rotationEffect(.degrees(serrure), anchor: UnitPoint(x: 0.66, y: 0.6))
                .scaleEffect(x: max(0.06, cos(tourne3D * .pi / 180)), y: 1 - 0.08 * sin(tourne3D * .pi / 180), anchor: UnitPoint(x: 0.5, y: 0.5))
                .brightness(-0.12 * sin(tourne3D * .pi / 180))
                .shadow(color: .black.opacity(0.2), radius: 10, y: 8)
                .decale(toile, -0.28 * (1 - arrive), -0.16 * (1 - arrive))
                .opacity(min(1, arrive * 2) * fin)
            // l'éclosion de la coche : un anneau vert s'ouvre et s'efface derrière elle
            Circle().strokeBorder(TonsBureau.vert.opacity(0.5 * (1 - anneau)), lineWidth: 3)
                .frame(width: diametre, height: diametre)
                .position(toile.point(Self.centreCoche.x, Self.centreCoche.y))
                .opacity(coche > 0.01 ? fin : 0)
            Piece(nom: "4c", toile: toile)
                .scaleEffect(max(0.001, coche), anchor: Self.centreCoche)
                .opacity(min(1, coche * 3) * fin)
        }
        .rotation3DEffect(.degrees(6 * flotte), axis: (x: 1, y: 0.2, z: 0), perspective: 0.5)
    }
}

// MARK: - 5 · l'essai

/// L'onde seule, qui parle : chaque barre sur son ressort, l'onde flotte et penche doucement. Elle est posée sur sa toile
/// (1536 × 512), comme les autres scènes.
struct SceneOnde: View {
    var t: Double
    var cadre: CGSize
    static let fenetre = CGRect(x: 0.15, y: -0.5, width: 0.7, height: 2)
    var body: some View {
        let toile = Toile(cadre: cadre, fenetre: Self.fenetre, rapport: 3)
        PoseToile(toile: toile, cadre: cadre) {
            OndeBarres(largeur: toile.taille.width) { k in Ressort.de(0, vers: 1, t: t, depart: 0.05 * Double(abs(k - 4)), duree: 0.5, rebond: 0.4) * NiveauxVoix.valeur(k, t: t) }
                .shadow(color: TonsBureau.orange.opacity(0.3), radius: 10)
                .position(toile.point(0.5, 0.5 - 0.03 * sin(2 * .pi * t / 3)))
        }
        .rotation3DEffect(.degrees(10 * sin(2 * .pi * t / 6)), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
    }
}
