import Foundation
import CoreGraphics

// Lucarne déplaçable : le modèle pur (sans interface), tiré de la maquette design/maquettes/lucarne-position.html (fonctions `capsule`,
// `colle`, `grand`, `plusProche`, `viseLancer`, `aimant`, ressorts et passages) et du plan docs/plan-lucarne-deplacable.md §2.
// Repère : points, x depuis le CENTRE DE L'ENCOCHE (le milieu de l'écran s'il n'y en a pas), y depuis le haut de l'écran.

// MARK: les huit places

/// Les huit places aimantées. `encoche` : dans l'encoche (écran avec caméra) ou, sans caméra, une pilule de verre sous la barre au milieu.
public enum PlaceLucarne: String, Codable, CaseIterable, Sendable {
    case encoche, hautGauche, hautDroite, gauche, droite, basGauche, basMilieu, basDroite

    /// Le point qui ne bouge pas quand la Lucarne grandit depuis cette place (0, ½ ou 1 sur chaque axe) : on grandit vers l'intérieur.
    public var ancre: (x: Double, y: Double) {
        switch self {
        case .encoche: return (0.5, 0)
        case .hautGauche: return (0, 0)
        case .hautDroite: return (1, 0)
        case .gauche: return (0, 0.5)
        case .droite: return (1, 0.5)
        case .basGauche: return (0, 1)
        case .basMilieu: return (0.5, 1)
        case .basDroite: return (1, 1)
        }
    }
    /// Les places du milieu des bords gauche et droit sont des pilules debout.
    public var debout: Bool { self == .gauche || self == .droite }
}

/// Un point de l'écran, dans le repère de la Lucarne (x depuis le centre de l'encoche, y depuis le haut).
public struct PointLucarne: Equatable, Sendable {
    public var x: Double, y: Double
    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    func distance(a autre: PointLucarne) -> Double { hypot(x - autre.x, y - autre.y) }
}

/// La taille d'une pilule repliée.
public struct TailleLucarne: Equatable, Sendable {
    public var largeur: Double, hauteur: Double
    public init(largeur: Double, hauteur: Double) { self.largeur = largeur; self.hauteur = hauteur }
}

/// La forme : bords x0, x1, y0, y1 ; `r` = coins du bas ; `s` = coins du haut. `s < 0` : épaules creuses collées au bord de l'écran (la
/// forme compacte de l'encoche, au décollage et au retour) ; `s > 0` : coins arrondis comme les autres (pilule libre). En passant par 0
/// la forme se décolle sans saut. Avec s = r = (petit côté / 2) / portée, c'est une pilule.
public struct CapsuleLucarne: Equatable, Sendable {
    public var x0: Double, x1: Double, y0: Double, y1: Double, s: Double, r: Double
    public init(x0: Double, x1: Double, y0: Double, y1: Double, s: Double, r: Double) {
        self.x0 = x0; self.x1 = x1; self.y0 = y0; self.y1 = y1; self.s = s; self.r = r
    }
    public var centreX: Double { (x0 + x1) / 2 }
    public var centreY: Double { (y0 + y1) / 2 }
    public var largeur: Double { x1 - x0 }
    public var hauteur: Double { y1 - y0 }
    /// Un rectangle à coins arrondis de rayon `rayon` partout.
    public static func boite(x0: Double, y0: Double, largeur: Double, hauteur: Double, rayon: Double) -> CapsuleLucarne {
        CapsuleLucarne(x0: x0, x1: x0 + largeur, y0: y0, y1: y0 + hauteur, s: rayon, r: rayon)
    }
    /// La forme de l'encoche en capsule : la trace d'un écran (`TraceIlot.calculer`) avec son épaule et son coin du bas (valeurs 3 et 4 de
    /// `GeoIlot`). Pour une forme repliée (rien sous la barre), `TraceLucarne` redonne exactement le même tracé : la Lucarne quitte
    /// l'encoche, ou y revient, sans saut.
    public static func encoche(_ p: TraceIlot.Points, epaule: Double, coin: Double) -> CapsuleLucarne {
        CapsuleLucarne(x0: -p.corpsGauche, x1: p.corpsDroit, y0: 0, y1: p.hauteur, s: -max(0, epaule), r: max(0, coin))
    }
    /// Une pilule (couchée ou debout) de cette taille, centrée en (cx, cy).
    public static func pilule(cx: Double, cy: Double, largeur: Double, hauteur: Double) -> CapsuleLucarne {
        let rayon = min(largeur, hauteur) / 2 / TraceIlot.portee
        return CapsuleLucarne(x0: cx - largeur / 2, x1: cx + largeur / 2, y0: cy - hauteur / 2, y1: cy + hauteur / 2, s: rayon, r: rayon)
    }
}

// MARK: l'écran

/// De quel côté est le Dock.
public enum CoteDock: String, Codable, Sendable {
    case bas, gauche, droite
    /// Valeur de la préférence `com.apple.dock orientation` ("bottom", "left", "right") ; inconnue ou absente : en bas.
    public static func depuis(orientation: String?) -> CoteDock {
        switch orientation?.lowercased() { case "left": return .gauche; case "right": return .droite; default: return .bas }
    }
}

/// Ce que la Lucarne sait d'un écran : son cadre (repère global d'AppKit), la barre des menus, la caméra, les retraits de `visibleFrame`
/// et le Dock. Valeurs en points. Construit par le contrôleur depuis `NSScreen` et les préférences du Dock ; ici, tout est pur.
public struct EcranLucarne: Equatable, Sendable {
    public var cadre: CGRect
    public var barre: Double
    /// La moitié de la vraie caméra ; nil : pas d'encoche (écran externe, Mac sans caméra).
    public var demiCamera: Double?
    /// Où est le centre de l'encoche, en points depuis le bord gauche de l'écran (le milieu s'il n'y en a pas).
    public var centreX: Double
    /// Ce que `visibleFrame` retire à gauche, à droite et en bas (le Dock quand il est visible).
    public var retraitGauche: Double, retraitDroit: Double, retraitBas: Double
    public var dockCote: CoteDock
    public var dockMasque: Bool
    /// Largeur du Dock en bas (aucune API publique : nil = inconnue, on reste alors au-dessus de sa ligne).
    public var dockLargeur: Double?
    /// Ce qu'il occupe (son épaisseur : taille des icônes + 14 pt), même masqué : notre fenêtre voleraient ses clics sinon.
    public var dockEpaisseur: Double

    public init(cadre: CGRect, barre: Double, demiCamera: Double? = nil, centreX: Double? = nil,
                retraitGauche: Double = 0, retraitDroit: Double = 0, retraitBas: Double = 0,
                dockCote: CoteDock = .bas, dockMasque: Bool = false, dockLargeur: Double? = nil, dockEpaisseur: Double = 0) {
        self.cadre = cadre; self.barre = barre; self.demiCamera = demiCamera
        self.centreX = centreX ?? Double(cadre.width) / 2
        self.retraitGauche = retraitGauche; self.retraitDroit = retraitDroit; self.retraitBas = retraitBas
        self.dockCote = dockCote; self.dockMasque = dockMasque; self.dockLargeur = dockLargeur; self.dockEpaisseur = dockEpaisseur
    }

    /// Depuis `frame` et `visibleFrame` (AppKit) : la barre et les retraits s'en déduisent.
    public init(cadre: CGRect, zoneVisible v: CGRect, demiCamera: Double? = nil, centreX: Double? = nil,
                dockCote: CoteDock = .bas, dockMasque: Bool = false, dockLargeur: Double? = nil, dockEpaisseur: Double = 0) {
        self.init(cadre: cadre, barre: Double(cadre.maxY - v.maxY), demiCamera: demiCamera, centreX: centreX,
                  retraitGauche: Double(v.minX - cadre.minX), retraitDroit: Double(cadre.maxX - v.maxX), retraitBas: Double(v.minY - cadre.minY),
                  dockCote: dockCote, dockMasque: dockMasque, dockLargeur: dockLargeur, dockEpaisseur: dockEpaisseur)
    }

    /// L'épaisseur du Dock d'après `tilesize` : la taille des icônes + 14 pt (mesuré : 56 → `visibleFrame` retire 70 pt).
    public static func epaisseurDock(tailleIcone: Double) -> Double { tailleIcone + 14 }

    public var largeur: Double { Double(cadre.width) }
    public var hauteur: Double { Double(cadre.height) }
    public var avecEncoche: Bool { demiCamera != nil }

    /// Ce que le Dock (ou un retrait) prend de chaque côté : le Dock masqué compte quand même (son épaisseur).
    public var reserveGauche: Double { dockCote == .gauche ? max(retraitGauche, dockEpaisseur) : retraitGauche }
    public var reserveDroite: Double { dockCote == .droite ? max(retraitDroit, dockEpaisseur) : retraitDroit }
    public var reserveBas: Double { dockCote == .bas ? max(retraitBas, dockEpaisseur) : retraitBas }

    /// La zone utile (repère de la Lucarne) : à gauche et à droite, `GeoLucarne.marge` à l'intérieur du Dock ou du bord.
    public var xMin: Double { reserveGauche + GeoLucarne.marge - centreX }
    public var xMax: Double { largeur - reserveDroite - GeoLucarne.marge - centreX }
    /// Les bords de l'écran lui-même.
    public var xBordGauche: Double { -centreX }
    public var xBordDroit: Double { largeur - centreX }
    /// Sous la barre : la première rangée de places du haut.
    public var yHaut: Double { barre + GeoLucarne.ecartBarre }
    /// Le bas d'une pilule posée au-dessus du Dock (ou à la marge du bord s'il n'y a rien en bas).
    public var yFond: Double { hauteur - reserveBas - GeoLucarne.marge }
    /// Le milieu des bords gauche et droit, entre la barre et le Dock.
    public var yMilieuBords: Double { ((barre + hauteur - reserveBas) / 2).rounded() }
    /// La ligne du milieu des icônes du Dock en bas (une marge de 6 pt dessous, comme la maquette : 62 pt d'icônes + 6).
    public var yLigneDock: Double { hauteur - 3 - reserveBas / 2 }
    /// Les bords du Dock en bas (repère de la Lucarne), s'il est visible et que sa largeur est connue ; il est centré sur l'écran.
    public var intervalleDock: ClosedRange<Double>? {
        guard dockCote == .bas, !dockMasque, let l = dockLargeur else { return nil }
        let milieu = largeur / 2 - centreX
        return (milieu - l / 2)...(milieu + l / 2)
    }
    /// Une forme entre x0 et x1 (repère de la Lucarne) se pose-t-elle sur le Dock du bas ? Masqué ou de largeur inconnue : partout.
    public func recouvreDock(x0: Double, x1: Double) -> Bool {
        guard dockCote == .bas, reserveBas > 0 else { return false }
        guard let d = intervalleDock else { return true }
        return x0 < d.upperBound + 8 && x1 > d.lowerBound - 8
    }
}

// MARK: la géométrie

public enum GeoLucarne {
    public static let marge = 10.0                    // écart aux bords de l'écran
    public static let ecartBarre = 8.0                // places du haut : sous la barre des menus
    public static let pilule = TailleLucarne(largeur: 120, hauteur: 36)   // pilule couchée (repliée, ou tenue au doigt)
    public static let pilouleDebout = TailleLucarne(largeur: 40, hauteur: 112)
    public static let echelleTenue = 1.04             // tenue au doigt : 4 % plus grande
    public static let dureeAppui = 0.4                // appui long (s)
    public static let toleranceAppui = 6.0            // le doigt peut bouger de 6 pt pendant l'appui long
    public static let seuilLancer = 350.0             // pt/s : au-delà, c'est un lancer
    public static let projectionLancer = 0.5          // s : où le geste emmènerait la forme
    public static let tolerancesDirection = [30.0, 60.0]   // degrés
    public static let seuilAimant = 0.45
    /// Les ailes de la forme compacte dans l'encoche (de chaque côté de la caméra) : celles de `VueIlot.lectureCompact`.
    public static let ailesCompactes = 44.0
    public static let epaulesCompactes = 6.0
    public static let coinsCompacts = 10.0

    // MARK: tailles

    /// Taille repliée d'une pilule d'après la largeur de son contenu : couchée 36 pt de haut (contenu + 2 × 16 de marge, de 72 à 260 pt) ;
    /// debout 112 pt de haut, largeur mesurée entre 40 et 66 pt (contenu + 2 × 8).
    public static func tailleCompacte(contenu: Double, debout: Bool) -> TailleLucarne {
        debout ? TailleLucarne(largeur: min(max(contenu + 16, pilouleDebout.largeur), 66), hauteur: pilouleDebout.hauteur)
               : TailleLucarne(largeur: min(max(contenu + 32, 72), 260), hauteur: pilule.hauteur)
    }

    // MARK: les places

    /// La forme repliée d'une place. `taille` : celle du contenu (sinon la pilule par défaut).
    /// - encoche, avec caméra : la forme compacte de l'encoche (épaules) ; sans caméra : une pilule de verre sous la barre, au milieu ;
    /// - coins du bas : à côté du Dock, centrés sur sa ligne, seulement si sa largeur est connue et que la place suffit ; sinon au-dessus.
    public static func replie(_ place: PlaceLucarne, _ e: EcranLucarne, taille: TailleLucarne? = nil) -> CapsuleLucarne {
        let t = taille ?? (place.debout ? pilouleDebout : pilule)
        let w = t.largeur, h = t.hauteur
        func couchee(cx: Double, cy: Double) -> CapsuleLucarne { .pilule(cx: cx, cy: cy, largeur: w, hauteur: h) }
        switch place {
        case .encoche:
            if let demi = e.demiCamera {
                return CapsuleLucarne(x0: -(demi + ailesCompactes), x1: demi + ailesCompactes, y0: 0, y1: e.barre, s: -epaulesCompactes, r: coinsCompacts)
            }
            return couchee(cx: 0, cy: e.yHaut + h / 2)
        case .hautGauche: return couchee(cx: e.xMin + w / 2, cy: e.yHaut + h / 2)
        case .hautDroite: return couchee(cx: e.xMax - w / 2, cy: e.yHaut + h / 2)
        case .gauche: return .pilule(cx: e.xMin + w / 2, cy: e.yMilieuBords, largeur: w, hauteur: h)
        case .droite: return .pilule(cx: e.xMax - w / 2, cy: e.yMilieuBords, largeur: w, hauteur: h)
        case .basMilieu: return couchee(cx: 0, cy: e.yFond - h / 2)
        case .basGauche:
            let cx = e.xMin + w / 2
            if let d = e.intervalleDock, cx + w / 2 + 8 <= d.lowerBound { return couchee(cx: cx, cy: e.yLigneDock) }
            return couchee(cx: cx, cy: e.yFond - h / 2)
        case .basDroite:
            let cx = e.xMax - w / 2
            if let d = e.intervalleDock, cx - w / 2 - 8 >= d.upperBound { return couchee(cx: cx, cy: e.yLigneDock) }
            return couchee(cx: cx, cy: e.yFond - h / 2)
        }
    }

    /// Le centre de chaque place repliée (avec les tailles par défaut).
    static func centre(_ p: PlaceLucarne, _ e: EcranLucarne) -> PointLucarne {
        let c = replie(p, e); return PointLucarne(c.centreX, c.centreY)
    }

    /// Grandir depuis sa place, vers l'intérieur de l'écran : depuis un coin en diagonale, depuis un bord à l'opposé du bord. Reste dans la
    /// zone utile, et jamais par-dessus le Dock : depuis un coin du bas, la forme monte au-dessus de sa ligne (validé sur la maquette).
    public static func grand(_ place: PlaceLucarne, _ e: EcranLucarne, largeur w: Double, hauteur h: Double, rayon: Double) -> CapsuleLucarne {
        let g = replie(place, e), a = place.ancre
        let x0 = min(e.xMax - w, max(e.xMin, g.x0 + (g.x1 - g.x0) * a.x - a.x * w))
        let yMin = (place == .encoche && e.avecEncoche) ? 0 : e.yHaut
        var y0 = min(e.hauteur - 8 - h, max(yMin, g.y0 + (g.y1 - g.y0) * a.y - a.y * h))
        if y0 + h > e.yFond && e.recouvreDock(x0: x0, x1: x0 + w) { y0 = max(yMin, e.yFond - h) }
        return .boite(x0: x0, y0: y0, largeur: w, hauteur: h, rayon: rayon)
    }

    /// L'encoche aimante : 1 tout près, 0 au-delà d'environ 150 pt (plus large que haute, comme l'encoche). 0 sans encoche.
    public static func aimant(x: Double, y: Double, _ e: EcranLucarne) -> Double {
        guard e.avecEncoche else { return 0 }
        let d = hypot(x / 2, y - e.barre / 2)
        return min(1, max(0, 1 - (d - 40) / 110))
    }

    /// La place la plus proche du point (centre de la forme), sauf `sauf`. À égalité, la première dans l'ordre des places.
    public static func plusProche(x: Double, y: Double, _ e: EcranLucarne, sauf: PlaceLucarne? = nil) -> PlaceLucarne {
        var mieux = PlaceLucarne.encoche, dmin = Double.infinity
        for p in PlaceLucarne.allCases where p != sauf {
            let c = centre(p, e), d = hypot(c.x - x, c.y - y)
            if d < dmin { dmin = d; mieux = p }
        }
        return mieux
    }

    /// Lancée : parmi les places dans la direction du lancer (à 30° près, sinon 60°), celle qui est la plus proche du point où le geste
    /// prolongé d'une demi-seconde emmènerait la forme (comme l'iPhone). L'encoche ne se vise jamais en lançant : on l'y amène.
    public static func viseLancer(cx: Double, cy: Double, vx: Double, vy: Double, _ e: EcranLucarne) -> PlaceLucarne {
        let px = min(e.xBordDroit, max(e.xBordGauche, cx + vx * projectionLancer)), py = min(e.hauteur, max(0, cy + vy * projectionLancer))
        let a = atan2(vy, vx)
        for tol in tolerancesDirection {
            var mieux: PlaceLucarne?, dmin = Double.infinity
            for p in PlaceLucarne.allCases where p != .encoche {
                let q = centre(p, e)
                var ecart = abs(atan2(q.y - cy, q.x - cx) - a) * 180 / .pi
                if ecart > 180 { ecart = 360 - ecart }
                let d = hypot(q.x - px, q.y - py)
                if ecart <= tol && d < dmin { dmin = d; mieux = p }
            }
            if let mieux { return mieux }
        }
        return plusProche(x: px, y: py, e, sauf: .encoche)
    }

    /// Où elle se pose quand on lâche : l'encoche si elle y est aimantée, sinon la place dans la direction du lancer (> 350 pt/s), sinon
    /// la plus proche.
    public static func placeLachee(cx: Double, cy: Double, vx: Double, vy: Double, pres: Bool, _ e: EcranLucarne) -> PlaceLucarne {
        if pres { return .encoche }
        return hypot(vx, vy) > seuilLancer ? viseLancer(cx: cx, cy: cy, vx: vx, vy: vy, e) : plusProche(x: cx, y: cy, e)
    }

    /// La forme tenue au doigt : elle suit le pointeur 1:1 (le point tenu glisse doucement vers le milieu de la pilule) ; l'encoche la
    /// retient un peu (`aimant` lissé). `decalage` : où le doigt tient la forme (centre − pointeur) ; `hw`, `hh` : ses demi-tailles
    /// affichées (avant l'échelle de la tenue). `pres` : assez près de l'encoche pour y devenir noire.
    public static func tenue(pointeur p: PointLucarne, decalage d: PointLucarne, hw: Double = pilule.largeur / 2, hh: Double = pilule.hauteur / 2,
                             _ e: EcranLucarne) -> (cx: Double, cy: Double, pres: Bool) {
        let m = aimant(x: p.x, y: p.y, e), lisse = m * m * (3 - 2 * m)
        let demiL = hw * echelleTenue, demiH = hh * echelleTenue
        func lerp(_ a: Double, _ b: Double) -> Double { a + (b - a) * lisse }
        let cx = min(e.xBordDroit - demiL - 4, max(e.xBordGauche + demiL + 4, lerp(p.x + d.x, 0)))
        // l'encoche attire le centre à la demi-hauteur de la forme tenue (son haut collé au bord de l'écran), pas au milieu de la barre
        let cy = min(e.hauteur - demiH - 4, max(e.barre / 2, lerp(p.y + d.y, hh)))
        return (cx, cy, m > seuilAimant)
    }
}

// MARK: hors de l'encoche : le contenu, la bulle, le verre (mission 3)

extension GeoLucarne {
    /// Le haut-milieu du contenu d'un déplié (le point (0, barre) de la grille de l'encoche) dans la forme `actuelle`, qui va vers `cible`.
    /// Le contenu est mis en page pour la cible et suit le bord ancré de la forme : depuis un coin du haut il ne bouge pas (la forme se
    /// déroule sur lui) ; depuis un coin du bas, il monte avec le haut de la forme. Posée (actuelle = cible) : le haut-milieu de la cible.
    public static func coinContenu(actuelle a: CapsuleLucarne, cible c: CapsuleLucarne, place: PlaceLucarne) -> PointLucarne {
        let k = place.ancre
        return PointLucarne(a.x0 + k.x * (a.largeur - c.largeur) + c.largeur / 2, a.y0 + k.y * (a.hauteur - c.hauteur))
    }

    /// L'écart entre la pilule et sa bulle (la deuxième activité), et la hauteur d'une bulle à côté d'une pilule debout.
    public static let ecartBulle = 8.0
    public static let hauteurBulleDebout = 64.0

    /// La bulle de la deuxième activité, posée à côté de la pilule `p`, du côté de l'intérieur de l'écran : à droite depuis la gauche
    /// et le milieu, à gauche depuis la droite ; sous une pilule debout. `largeur` : celle de son contenu (couchée) ; debout, la bulle
    /// prend la largeur de la pilule. `sortie` : 0 = rentrée au milieu de la pilule (invisible sous elle), 1 = posée.
    public static func bulle(_ p: CapsuleLucarne, place: PlaceLucarne, largeur: Double, sortie: Double = 1) -> CapsuleLucarne {
        let posee: CapsuleLucarne
        if place.debout {
            posee = .pilule(cx: p.centreX, cy: p.y1 + ecartBulle + hauteurBulleDebout / 2, largeur: p.largeur, hauteur: hauteurBulleDebout)
        } else if place.ancre.x > 0.5 {
            posee = .pilule(cx: p.x0 - ecartBulle - largeur / 2, cy: p.centreY, largeur: largeur, hauteur: p.hauteur)
        } else {
            posee = .pilule(cx: p.x1 + ecartBulle + largeur / 2, cy: p.centreY, largeur: largeur, hauteur: p.hauteur)
        }
        let s = min(1.2, max(0, sortie))
        // la goutte part du milieu de la pilule, petite, et grandit en sortant
        let cx = p.centreX + (posee.centreX - p.centreX) * s, cy = p.centreY + (posee.centreY - p.centreY) * s
        let k = 0.4 + 0.6 * min(1, s)
        return .pilule(cx: cx, cy: cy, largeur: posee.largeur * k, hauteur: posee.hauteur * k)
    }
}

/// Le verre hors de l'encoche (niveau « Liquide » de la maquette lucarne-position.html) : un verre clair, un givre (le fond flouté sous le
/// contenu : les lettres d'une page derrière ne se mêlent plus au texte) et un voile noir. Le contenu de l'îlot est fait pour le noir
/// (texte blanc, rouge, ambre, bleu) ; sans lecture du fond (il faudrait l'enregistrement de l'écran), le voile est réglé sur le pire
/// fond, une page blanche, par le calcul du contraste (WCAG) : blanc ≥ 12, gris à 60 % ≥ 5, rouge et bleu système ≥ 3,4. Le verre se voit
/// à son bord (liseré, lentille, ombre) ; sur un fond sombre, il est noir comme l'encoche.
public enum VerreLucarne {
    public static let voile = 0.8
    /// L'ombre posée (repliée, dépliée) : opacité, flou, décalage vers le bas.
    public static let ombrePosee = (opacite: 0.22, flou: 5.0, y: 3.0)
    public static let ombreDepliee = (opacite: 0.32, flou: 11.0, y: 6.0)
    /// Le givre rentre de ce bord : la lisière reste du verre.
    public static let rentreeGivre = 5.0

    /// Luminance relative (WCAG) d'une composante sRGB.
    public static func luminance(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
    /// Le contraste d'un texte de couleur sRGB `lettre` (opacité `opacite`) posé sur le voile noir, lui-même sur un fond gris sRGB `fond`
    /// (1 = page blanche) vu au travers du verre.
    public static func contraste(lettre: (r: Double, g: Double, b: Double) = (1, 1, 1), opacite: Double = 1, voile v: Double = voile, fond: Double) -> Double {
        let dessous = fond * (1 - v)
        func melange(_ c: Double) -> Double { dessous + (c - dessous) * opacite }
        let a = 0.2126 * luminance(melange(lettre.r)) + 0.7152 * luminance(melange(lettre.g)) + 0.0722 * luminance(melange(lettre.b))
        let b = luminance(dessous)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
    /// La forme du givre : la capsule rentrée de `rentreeGivre` (ses coins continus rentrés d'autant).
    public static func givre(_ c: CapsuleLucarne) -> CapsuleLucarne {
        let e = rentreeGivre, k = { (v: Double) in max(1, (TraceIlot.portee * v - e) / TraceIlot.portee) }
        return CapsuleLucarne(x0: c.x0 + e, x1: c.x1 - e, y0: c.y0 + e, y1: c.y1 - e, s: c.s < 0 ? c.s : k(c.s), r: k(c.r))
    }
}

// MARK: le tracé

/// Le tracé d'une capsule, en commandes de `TraceIlot` (mêmes coins continus : portée 1,6, poignée 0,18), dessiné par `FormeNoire`.
/// Dans DicteeCore parce que l'init de `TraceIlot.Points` n'est pas public. Les distances de `Points` sont prises depuis le centre de
/// l'encoche (x = 0).
public enum TraceLucarne {
    public static func calculer(_ c: CapsuleLucarne) -> TraceIlot.Points {
        let portee = TraceIlot.portee, poignee = TraceIlot.poignee
        let x0 = c.x0, x1 = max(c.x1, c.x0), y0 = c.y0, y1 = max(c.y1, c.y0), w = x1 - x0, h = y1 - y0
        guard w >= 0.5, h >= 0.5 else { return TraceIlot.Points(commandes: [], bande: 0, cou: 0, corps: 0, hauteur: 0) }
        let lim = min(w, h) / 2
        let rb = min(max(c.r, 0), lim / portee), a = portee * rb, k = poignee * a
        var cmd: [TraceIlot.Commande] = []
        var gauche = max(0, -x0), droite = max(0, x1)     // jusqu'où va la forme de chaque côté, épaules comprises
        if c.s >= 0 {
            let t = portee * min(c.s, lim / portee), u = poignee * t
            cmd.append(.deplacer(x0 + t, y0))
            cmd.append(.cubique(x0 + u, y0, x0, y0 + u, x0, y0 + t))
            cmd.append(.ligne(x0, y1 - a)); cmd.append(.cubique(x0, y1 - k, x0 + k, y1, x0 + a, y1))
            cmd.append(.ligne(x1 - a, y1)); cmd.append(.cubique(x1 - k, y1, x1, y1 - k, x1, y1 - a))
            cmd.append(.ligne(x1, y0 + t)); cmd.append(.cubique(x1, y0 + u, x1 - u, y0, x1 - t, y0))
        } else {
            let rs = min(-c.s, max(0, h - a))
            cmd.append(.deplacer(x0 - rs, y0 - 1)); cmd.append(.ligne(x0 - rs, y0)); cmd.append(.quad(x0, y0, x0, y0 + rs))
            cmd.append(.ligne(x0, y1 - a)); cmd.append(.cubique(x0, y1 - k, x0 + k, y1, x0 + a, y1))
            cmd.append(.ligne(x1 - a, y1)); cmd.append(.cubique(x1 - k, y1, x1, y1 - k, x1, y1 - a))
            cmd.append(.ligne(x1, y0 + rs)); cmd.append(.quad(x1, y0, x1 + rs, y0)); cmd.append(.ligne(x1 + rs, y0 - 1))
            gauche = max(0, -(x0 - rs)); droite = max(0, x1 + rs)
        }
        let coeur = (couG: max(0, -x0), couD: max(0, x1))
        return TraceIlot.Points(commandes: cmd, bande: max(gauche, droite), cou: coeur.couD, corps: max(coeur.couG, coeur.couD), hauteur: y1,
                                couGauche: coeur.couG, bandeGauche: gauche, bandeDroite: droite, corpsGauche: coeur.couG, corpsDroit: coeur.couD)
    }
}

// MARK: les ressorts

/// Comment la capsule passe d'une forme à l'autre : les ressorts de la maquette, ici pour que les contrôles et le moteur utilisent les mêmes.
public enum PassageLucarne: Equatable, Sendable {
    /// Elle grandit depuis sa place : 0,46 s / 0,8.
    case ouverture
    /// Elle se replie : 0,38 s / 1, après 0,06 s d'attente (le contenu part d'abord).
    case fermeture
    /// Lâchée sur une place : centre 0,5 s / 0,8 (garde la vitesse du lancer), tailles et coins 0,3 s / 0,9 ; elle redevient verre (0,3 s).
    case atterrissage
    /// Aspirée par l'encoche : centre 0,36 s / 0,9, tailles 0,3 s / 0,9, coins 0,26 s / 1 ; elle redevient noire (0,14 s).
    case aspiration
    /// Tenue près de l'encoche : la forme compacte, noire (0,28 s / 0,86 ; noir en 0,14 s). Le centre, lui, suit le doigt.
    case tenueEncoche
    /// Tenue ailleurs : une pilule de verre.
    case tenueVerre

    public struct Reglage: Equatable, Sendable {
        public var reponse: Double, amortissement: Double, attente: Double
        public init(_ reponse: Double, _ amortissement: Double, _ attente: Double = 0) {
            self.reponse = reponse; self.amortissement = amortissement; self.attente = attente
        }
    }
    public enum Axe: Sendable { case cx, cy, hw, hh, s, r }

    /// Le réglage d'un ressort pour ce passage (nil : on n'y touche pas).
    public func reglage(_ axe: Axe) -> Reglage? {
        switch self {
        case .ouverture: return Reglage(0.46, 0.8)
        case .fermeture: return Reglage(0.38, 1, 0.06)
        case .atterrissage: return (axe == .cx || axe == .cy) ? Reglage(0.5, 0.8) : Reglage(0.3, 0.9)
        case .aspiration:
            switch axe { case .cx, .cy: return Reglage(0.36, 0.9); case .hw, .hh: return Reglage(0.3, 0.9); case .s, .r: return Reglage(0.26, 1) }
        case .tenueEncoche, .tenueVerre:
            return (axe == .cx || axe == .cy) ? nil : Reglage(0.28, 0.86)
        }
    }
    /// Où va le fondu noir ↔ verre (1 = noir, 0 = verre) et avec quel ressort ; nil : inchangé (ouverture, fermeture).
    public var noir: (cible: Double, reglage: Reglage)? {
        switch self {
        case .ouverture, .fermeture: return nil
        case .atterrissage: return (0, Reglage(0.3, 1))
        case .aspiration: return (1, Reglage(0.14, 1))
        case .tenueEncoche: return (1, Reglage(0.14, 1))
        case .tenueVerre: return (0, Reglage(0.14, 1))
        }
    }
}

/// Les ressorts de la capsule libre : centre (cx, cy), demi-tailles (hw, hh), coins (s, r), le fondu noir ↔ verre, le « levé » (échelle
/// 1,04 + ombre pendant la tenue) et l'écart où le doigt tient la forme. Un lancer garde la vitesse de cx et cy.
public struct RessortsCapsule: Equatable, Sendable {
    public var cx: RessortIlot, cy: RessortIlot, hw: RessortIlot, hh: RessortIlot, s: RessortIlot, r: RessortIlot
    public var noir: RessortIlot, leve: RessortIlot
    public var decalX: RessortIlot, decalY: RessortIlot

    public init(_ c: CapsuleLucarne, noir: Double = 1) {
        func rs(_ v: Double) -> RessortIlot { RessortIlot(v, reponse: 0.45, amortissement: 0.8) }
        cx = rs(c.centreX); cy = rs(c.centreY); hw = rs(c.largeur / 2); hh = rs(c.hauteur / 2); s = rs(c.s); r = rs(c.r)
        self.noir = rs(noir); leve = rs(0); decalX = rs(0); decalY = rs(0)
    }

    private static func capsule(cx: Double, cy: Double, hw: Double, hh: Double, s: Double, r: Double) -> CapsuleLucarne {
        CapsuleLucarne(x0: cx - hw, x1: cx + hw, y0: cy - hh, y1: cy + hh, s: s, r: r)
    }
    /// La forme telle qu'elle est à l'instant.
    public var valeur: CapsuleLucarne { Self.capsule(cx: cx.x, cy: cy.x, hw: hw.x, hh: hh.x, s: s.x, r: r.x) }
    /// La forme où les ressorts finiront.
    public var cible: CapsuleLucarne { Self.capsule(cx: cx.cibleFinale, cy: cy.cibleFinale, hw: hw.cibleFinale, hh: hh.cibleFinale, s: s.cibleFinale, r: r.cibleFinale) }
    /// La forme dessinée : tenue au doigt, un peu plus grande (1 → 1,04).
    public var affichee: CapsuleLucarne {
        let k = 1 + (GeoLucarne.echelleTenue - 1) * max(0, leve.x)
        return Self.capsule(cx: cx.x, cy: cy.x, hw: hw.x * k, hh: hh.x * k, s: s.x * k, r: r.x * k)
    }
    /// 1 = noir, 0 = verre.
    public var fonduNoir: Double { min(1, max(0, noir.x)) }
    /// Où le doigt tient la forme (centre − pointeur).
    public var decalage: PointLucarne { PointLucarne(decalX.x, decalY.x) }

    private static func viser(_ r: inout RessortIlot, _ cible: Double, _ g: PassageLucarne.Reglage?) {
        guard let g else { return }
        r.viser(cible, reponse: g.reponse, amortissement: g.amortissement, attente: g.attente)
    }
    private static func poser(_ r: inout RessortIlot, _ v: Double) {
        r.x = v; r.v = 0; r.viser(v, reponse: r.reponse, amortissement: r.amortissement)
    }

    /// Vise la forme `c` depuis l'état affiché (valeur et vitesse gardées : jamais de saut). `vitesse` : celle du lancer, donnée au centre.
    /// « Réduire les animations » : tout saute à sa place.
    public mutating func viser(_ c: CapsuleLucarne, passage: PassageLucarne, vitesse: PointLucarne? = nil, reduire: Bool = false) {
        if reduire {
            // seulement les axes que le passage vise : tenue, le centre reste au doigt
            func p(_ r: inout RessortIlot, _ v: Double, _ a: PassageLucarne.Axe) { if passage.reglage(a) != nil { Self.poser(&r, v) } }
            p(&cx, c.centreX, .cx); p(&cy, c.centreY, .cy); p(&hw, c.largeur / 2, .hw); p(&hh, c.hauteur / 2, .hh); p(&s, c.s, .s); p(&r, c.r, .r)
            if let n = passage.noir { Self.poser(&noir, n.cible) }
            return
        }
        if let vitesse { cx.v = vitesse.x; cy.v = vitesse.y }
        Self.viser(&cx, c.centreX, passage.reglage(.cx)); Self.viser(&cy, c.centreY, passage.reglage(.cy))
        Self.viser(&hw, c.largeur / 2, passage.reglage(.hw)); Self.viser(&hh, c.hauteur / 2, passage.reglage(.hh))
        Self.viser(&s, c.s, passage.reglage(.s)); Self.viser(&r, c.r, passage.reglage(.r))
        if let n = passage.noir { Self.viser(&noir, n.cible, n.reglage) }
    }

    /// Pose la forme tout de suite (centre, tailles, coins), sans vitesse.
    public mutating func placer(_ c: CapsuleLucarne) {
        Self.poser(&cx, c.centreX); Self.poser(&cy, c.centreY); Self.poser(&hw, c.largeur / 2); Self.poser(&hh, c.hauteur / 2)
        Self.poser(&s, c.s); Self.poser(&r, c.r)
    }
    /// Le centre suit le doigt à chaque image (posé, pas de ressort : 1 pt pour 1 pt).
    public mutating func suivre(cx x: Double, cy y: Double) { Self.poser(&cx, x); Self.poser(&cy, y) }
    /// Saisie : on retient où le doigt tient la forme (centre − pointeur), qui glisse doucement vers le milieu de la pilule.
    public mutating func saisir(pointeur p: PointLucarne) {
        let ox = cx.x - p.x, oy = cy.x - p.y
        Self.poser(&decalX, ox); Self.poser(&decalY, oy)
        let bx = GeoLucarne.pilule.largeur / 2 - 16, by = GeoLucarne.pilule.hauteur / 2 - 8
        Self.viser(&decalX, min(bx, max(-bx, ox)), .init(0.3, 1)); Self.viser(&decalY, min(by, max(-by, oy)), .init(0.3, 1))
    }
    /// Levée (tenue au doigt) : 0,26 s / 0,7. Reposée : 0,4 s / 0,9.
    public mutating func lever() { leve.viser(1, reponse: 0.26, amortissement: 0.7) }
    public mutating func reposer() { leve.viser(0, reponse: 0.4, amortissement: 0.9) }

    public mutating func avancer(_ dt: Double) {
        cx.avancer(dt); cy.avancer(dt); hw.avancer(dt); hh.avancer(dt); s.avancer(dt); r.avancer(dt)
        noir.avancer(dt); leve.avancer(dt); decalX.avancer(dt); decalY.avancer(dt)
    }
    public mutating func poser() {
        cx.poser(); cy.poser(); hw.poser(); hh.poser(); s.poser(); r.poser(); noir.poser(); leve.poser(); decalX.poser(); decalY.poser()
    }
    /// Tout est posé : plus de boucle d'animation à faire tourner.
    public var fini: Bool {
        cx.fini && cy.fini && hw.fini && hh.fini && s.fini && r.fini && noir.fini && leve.fini && decalX.fini && decalY.fini
    }
}

// MARK: le geste

/// Le geste d'appui long puis glisser/lancer, sans horloge : on lui donne l'heure `t` (secondes) et le point (repère de la Lucarne).
/// - appui puis > 6 pt avant 0,4 s : annulé (ni clic ni déplacement) ; relâché avant 0,4 s sans avoir bougé : clic ;
/// - à 0,4 s (`echeance`) : elle se décolle ; ensuite elle suit le pointeur ; relâchée : lâcher avec la vitesse des 100 dernières ms
///   (nulle si le dernier mouvement date de plus de 80 ms).
public struct GesteLucarne: Sendable {
    public enum Phase: Equatable, Sendable { case repos, appui, decollee, annulee }
    public enum Evenement: Equatable, Sendable {
        case decolle
        case annule
        case clic
        case suit(PointLucarne)
        case lacher(vx: Double, vy: Double)
    }

    public private(set) var phase = Phase.repos
    public private(set) var depart = PointLucarne(0, 0)
    public private(set) var debut = 0.0
    public private(set) var pointeur = PointLucarne(0, 0)
    private var echantillons: [(t: Double, p: PointLucarne)] = []

    public init() {}

    /// L'heure où elle se décollera (pour armer un seul réveil) ; nil hors appui.
    public var echeanceAppui: Double? { phase == .appui ? debut + GeoLucarne.dureeAppui : nil }
    /// Le remplissage de l'anneau pendant l'appui (0 → 1).
    public func progression(a t: Double) -> Double { phase == .appui ? min(1, max(0, (t - debut) / GeoLucarne.dureeAppui)) : 0 }

    public mutating func appuyer(_ p: PointLucarne, t: Double) {
        phase = .appui; depart = p; debut = t; pointeur = p; echantillons = [(t, p)]
    }

    /// À 0,4 s d'appui : elle se décolle. Appelée par le réveil ; `bouger` et `relacher` la rattrapent si le réveil est en retard.
    public mutating func echeance(_ t: Double) -> [Evenement] {
        guard phase == .appui, t - debut >= GeoLucarne.dureeAppui - 1e-9 else { return [] }
        phase = .decollee
        return [.decolle]
    }

    public mutating func bouger(_ p: PointLucarne, t: Double) -> [Evenement] {
        var ev = echeance(t)
        pointeur = p
        switch phase {
        case .appui:
            echantillons.append((t, p))
            if p.distance(a: depart) > GeoLucarne.toleranceAppui { phase = .annulee; ev.append(.annule) }
        case .decollee:
            noter(p, t)
            ev.append(.suit(p))
        case .repos, .annulee: break
        }
        return ev
    }

    public mutating func relacher(_ p: PointLucarne, t: Double) -> [Evenement] {
        var ev = echeance(t)
        switch phase {
        case .appui:
            ev.append(p.distance(a: depart) > GeoLucarne.toleranceAppui ? .annule : .clic)
        case .decollee:
            let v = vitesse(a: t)
            ev.append(.lacher(vx: v.x, vy: v.y))
        case .repos, .annulee: break
        }
        phase = .repos; echantillons = []
        return ev
    }

    /// Dictée, réunion, écran qui change… : le geste s'arrête. Tenue : lâchée sans vitesse (elle retombe à la place la plus proche).
    public mutating func interrompre() -> [Evenement] {
        defer { phase = .repos; echantillons = [] }
        switch phase {
        case .appui: return [.annule]
        case .decollee: return [.lacher(vx: 0, vy: 0)]
        case .repos, .annulee: return []
        }
    }

    private mutating func noter(_ p: PointLucarne, _ t: Double) {
        echantillons.append((t, p))
        echantillons.removeAll { $0.t < t - 0.25 }
    }

    /// Vitesse sur les 100 dernières ms de mouvement (pt/s) ; 0 si le dernier mouvement date de plus de 80 ms.
    private func vitesse(a t: Double) -> PointLucarne {
        guard let dernier = echantillons.last, t - dernier.t <= 0.08 else { return PointLucarne(0, 0) }
        guard let premier = echantillons.first(where: { $0.t >= dernier.t - 0.1 - 1e-9 }) else { return PointLucarne(0, 0) }
        let dt = dernier.t - premier.t
        guard dt > 0.005 else { return PointLucarne(0, 0) }
        return PointLucarne((dernier.p.x - premier.p.x) / dt, (dernier.p.y - premier.p.y) / dt)
    }
}

// MARK: la mémoire

/// La place de la Lucarne, une par écran (clé : l'UUID de l'écran), et l'écran choisi. Codable : enregistrée en JSON dans les réglages
/// (`Settings.lucarnePlaces`, `Settings.lucarneEcran`). Les places sont gardées en texte : une valeur inconnue (version future) retombe
/// sur l'encoche au lieu de rendre toute la mémoire illisible.
public struct MemoirePlaces: Codable, Equatable, Sendable {
    public private(set) var places: [String: String] = [:]
    public var ecranChoisi: String?

    public init() {}

    /// La place mémorisée pour cet écran ; inconnue ou illisible : l'encoche (sans caméra, c'est la pilule en haut au milieu).
    public func place(pour uuid: String) -> PlaceLucarne { places[uuid].flatMap(PlaceLucarne.init(rawValue:)) ?? .encoche }
    public mutating func memoriser(_ p: PlaceLucarne, pour uuid: String) { places[uuid] = p.rawValue }
    public mutating func oublier(_ uuid: String) { places[uuid] = nil }
    /// L'écran choisi s'il est encore branché ; sinon nil (le contrôleur prend l'écran principal).
    public func ecranChoisi(parmi branches: [String]) -> String? { ecranChoisi.flatMap { branches.contains($0) ? $0 : nil } }

    public func donnees() -> Data { (try? JSONEncoder().encode(self)) ?? Data() }
    public static func depuis(_ donnees: Data) -> MemoirePlaces? { try? JSONDecoder().decode(MemoirePlaces.self, from: donnees) }
}
