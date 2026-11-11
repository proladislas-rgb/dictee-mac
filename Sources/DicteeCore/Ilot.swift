import Foundation

// L'îlot « centre d'activités » (maquette design/maquettes/ilot-activites.html) : logique pure, sans interface.
// Une seule forme noire dans l'encoche, trois tailles (minimal, compact, étendu), une règle de priorité, une pastille pour la deuxième activité.

/// Les « écrans » que l'îlot sait montrer. Chacun a une géométrie (`GeoIlot`) : la forme noire se déforme de l'un à l'autre.
public enum VueIlot: String, CaseIterable, Sendable {
    case repos
    case minuteurMinimal, minuteurCompact, minuteurEtendu, minuteurLance, minuteurFini
    case lectureCompact, lectureEtendu, lectureMinuteur
    case rappelEtendu, rappelCompact, rappelAjoute, rappelFait, rappelReporte, rappelListe
    case agendaAvant, agendaCompact, agendaEtendu, agendaDebut
    case notification, notifications
    case accueil
    /// Des écouteurs (ou une souris, un clavier) se connectent ; le chargeur est branché ; la batterie est faible.
    case appareil, batterieCharge, batterieFaible
    /// Un fichier (ou plusieurs, en rafale) vient d'arriver dans Téléchargements, AirDrop compris.
    case telecharge
    /// Le micro est coupé (micro barré rouge, « Coupé ») ; au survol, son nom et « Rouvrir » ; rouvert : un bandeau vert court.
    case microCompact, microEtendu, microOuvert
    /// Une touche de volume ou de luminosité : le haut-parleur (ou le soleil) dans l'aile gauche, une barre fine dans l'aile droite.
    case volume, luminosite

    /// Ces écrans sont des bandeaux : ils s'annoncent, restent un instant, puis se retirent d'eux-mêmes.
    public var estBandeau: Bool {
        switch self {
        case .minuteurLance, .rappelAjoute, .rappelFait, .rappelReporte, .agendaAvant, .notification, .notifications,
             .appareil, .batterieCharge, .batterieFaible, .telecharge, .microOuvert, .volume, .luminosite: return true
        default: return false
        }
    }
    /// Ces écrans sont des alertes : l'îlot s'ouvre de lui-même, vibre, sonne, et attend un geste.
    public var estAlerte: Bool { self == .minuteurFini || self == .rappelEtendu || self == .agendaDebut }
    /// Volume et luminosité : un bandeau qui suit les touches du clavier (1,5 s après la dernière).
    public var estNiveau: Bool { self == .volume || self == .luminosite }
}

/// Géométrie de la forme (maquette design/maquettes/ilot-pro-A.html), sept valeurs :
/// [cou, corps, hauteur, épaule, coin bas, coin haut du corps, congé du cou].
/// - cou : demi-largeur dans la barre des menus, AU-DELÀ de la demi-caméra (jamais plus de 66 pt avec l'épaule ou le congé) ;
/// - corps : demi-largeur sous la barre, au-delà de la demi-caméra (le corps n'existe que sous la barre) ;
/// - hauteur : depuis le haut de l'écran. La table donne la profondeur SOUS la barre ; `valeurs` ajoute la vraie barre ;
/// - épaule : le creux du haut, où la forme s'évase pour rejoindre le bord de l'écran ;
/// - coin bas, coin haut du corps : coins continus (pas des arcs de cercle) ; congé : le raccord creux entre le cou et le corps.
/// Tout est exprimé depuis la vraie caméra et la vraie barre : aucune mesure de la maquette n'est copiée telle quelle.
public enum GeoIlot {
    public static let aileMax: Double = 66
    /// Ce que la rangée Minuteur ajoute sous la lecture dépliée (maquette : 208 → 262 pt de haut).
    public static let rangeeMinuteur: Double = 54
    /// Repos d'une activité : rien sous la barre, le cou serré contre la caméra (la place de la pochette, de l'anneau, de l'heure).
    static func compact(_ cou: Double) -> [Double] { [cou, cou, 0, 6, 10, 0, 0] }
    /// Bandeau passager : cou étroit (les menus restent visibles), deux lignes sous la barre. Le corps s'ajuste à son contenu (comme la
    /// Dynamic Island) : la table donne le plus large permis, `corps(_:contenu:demiCamera:)` la largeur voulue.
    static let bandeau: [Double] = [14, 150, 72, 6, 28, 16, 10]
    static let alerte: [Double] = [14, 150, 79, 6, 30, 16, 10]
    static let table: [VueIlot: [Double]] = [
        // repos : exactement l'encoche (pas d'épaule : rien ne déborde sur la barre autour de la caméra)
        .repos: [0, 0, 0, 0, 8, 0, 0],
        .minuteurMinimal: compact(36), .minuteurCompact: compact(48), .minuteurEtendu: [48, 112, 91, 6, 30, 16, 10],
        .minuteurLance: bandeau, .minuteurFini: alerte,
        .lectureCompact: compact(44), .lectureEtendu: [44, 144, 175, 6, 34, 18, 10],
        // la lecture dépliée + la rangée Minuteur de l'accueil (appui long, maquette apple-acces/1-controles.html) : même largeur
        .lectureMinuteur: [44, 144, 175 + rangeeMinuteur, 6, 34, 18, 10],
        .rappelEtendu: alerte, .rappelCompact: compact(48), .rappelAjoute: bandeau,
        .rappelFait: bandeau, .rappelReporte: bandeau, .rappelListe: [14, 144, 136, 6, 34, 18, 10],
        .agendaAvant: bandeau, .agendaCompact: compact(50), .agendaEtendu: [50, 150, 130, 6, 34, 18, 10], .agendaDebut: bandeau,
        .notification: bandeau, .notifications: bandeau,
        .accueil: [14, 144, 190, 6, 34, 18, 10],
        // les jauges des écouteurs (anneau + nom) demandent un peu plus de hauteur qu'un bandeau ; l'énergie tient dans les ailes
        .appareil: [14, 150, 80, 6, 30, 16, 10],
        .batterieCharge: compact(60), .batterieFaible: compact(60),
        // le fichier arrivé : son icône (38 pt), son nom et « Téléchargé · 2,4 Mo », le bouton Ouvrir ; un bandeau ordinaire
        .telecharge: bandeau,
        // micro coupé : le micro barré (aile gauche) et « Coupé » (41 pt mesurés, aile droite : 60 − 8 − 4 = 48 pt) ; 60 + 6 = 66 ;
        // au survol, un petit déplié qui épouse « Micro coupé », le nom du micro et « Rouvrir » ; rouvert, « Ouvert » (44 pt) en vert
        .microCompact: compact(60), .microEtendu: bandeau, .microOuvert: compact(60),
        // volume et luminosité : le haut-parleur (aile gauche) et une barre fine de 44 pt (aile droite : 8 pt de la caméra, 8 pt du
        // cou) ; 60 + 6 = 66. La maquette dessinait 96 pt : ça déborderait sur les icônes de la barre des menus
        .volume: compact(60), .luminosite: compact(60),
    ]
    /// Indices des valeurs : largeurs (cou, corps) et hauteurs (hauteur, épaule, coins, congé). À l'ouverture la largeur mène ; à la
    /// fermeture la hauteur se replie d'abord.
    public static let largeurs = [0, 1]
    public static let hauteurs = [2, 3, 4, 5, 6]

    /// Marge du contenu tout autour du corps (la grille de l'îlot).
    public static let marge: Double = 16
    /// Le corps s'évase toujours d'au moins 38 pt au-delà du cou : en deçà, le congé et le coin haut n'ont plus la place de se dessiner
    /// (la forme deviendrait une languette).
    public static let evasementMin: Double = 38

    /// Écrans dont le corps épouse le contenu (bandeaux, alertes, rendez-vous déplié) : ni texte collé à gauche ni grand vide à droite.
    public static func ajusteAuContenu(_ v: VueIlot) -> Bool { ((v.estBandeau || v.estAlerte) && profondeur(v) > 0) || v == .agendaEtendu || v == .microEtendu }

    /// Les épaules (maquette ilot-apple.html) : dans un écran déplié, le cou s'élargit à 56 pt de chaque côté de la caméra pour montrer
    /// la batterie du Mac (à gauche) et celle des écouteurs (à droite). 56 + le congé du cou déplié (10 pt) = la limite des ailes (66 pt).
    public static let epaules: Double = 56
    public static func aEpaules(_ v: VueIlot) -> Bool {
        [.minuteurEtendu, .lectureEtendu, .lectureMinuteur, .rappelListe, .agendaEtendu, .accueil].contains(v)
    }

    /// Demi-corps (au-delà de la demi-caméra) pour un contenu de `largeur` pt : contenu + marges, borné entre le cou + 38 pt et la table.
    public static func corps(_ v: VueIlot, contenu largeur: Double, demiCamera: Double) -> Double {
        let t = table[v] ?? table[.repos]!
        return min(t[1], max(t[0] + evasementMin, (largeur / 2 + marge - demiCamera).rounded(.up)))
    }

    /// Les sept valeurs pour une vue, la hauteur comptée depuis le haut de l'écran avec la vraie barre des menus. `contenu` : la largeur
    /// mesurée du contenu (pt) pour un écran qui s'y ajuste ; nil = le plus large de la table.
    public static func valeurs(_ v: VueIlot, hauteurBarre: Double, demiCamera: Double = 0, contenu: Double? = nil, epaules avecEpaules: Bool = false) -> [Double] {
        var g = table[v] ?? table[.repos]!
        g[2] += hauteurBarre
        if avecEpaules, aEpaules(v) { g[0] = max(g[0], epaules) }
        if let contenu, ajusteAuContenu(v) { g[1] = corps(v, contenu: contenu, demiCamera: demiCamera) }
        return g
    }
    /// Profondeur sous la barre (0 pour un repos ou un compact).
    public static func profondeur(_ v: VueIlot) -> Double { (table[v] ?? table[.repos]!)[2] }
}

/// Comment la forme passe d'un écran à l'autre : les ressorts du moteur, ici pour que les contrôles essaient exactement les mêmes.
public enum PassageIlot: Equatable, Sendable {
    case ouverture, fermeture, glissement

    /// Ouverture si la forme doit descendre, fermeture si elle doit remonter (jugé sur la hauteur affichée : une interruption compte).
    public static func de(hauteur h: Double, vers c: Double) -> PassageIlot { c > h + 1 ? .ouverture : (c < h - 1 ? .fermeture : .glissement) }

    /// Vise la géométrie `c` depuis l'état affiché des ressorts (valeur et vitesse gardées).
    /// - ouverture : la largeur mène (0,40 s / 0,80), la hauteur suit (0,48 s / 0,75) ; alerte plus vive (0,38 / 0,74 et 0,46 / 0,70) ;
    /// - fermeture : le contenu part d'abord (0,06 s), puis la forme se dégonfle sans rebond, la largeur un peu plus vite que la hauteur
    ///   (0,32 s contre 0,42 s) : à mi-course elle se resserre vers l'encoche au lieu de faire un bandeau plat sous les menus ;
    /// - glissement (même hauteur) : 0,36 s / 0,86 ; « Réduire les animations » : tout saute à sa place.
    @discardableResult
    public static func viser(_ geo: inout [RessortIlot], vers c: [Double], alerte: Bool = false, reduire: Bool = false) -> PassageIlot {
        let p = de(hauteur: geo[2].x, vers: c[2])
        if reduire {
            for i in geo.indices { geo[i].viser(c[i], reponse: 0.4, amortissement: 1); geo[i].poser() }
            return p
        }
        switch p {
        case .fermeture:
            for i in GeoIlot.hauteurs { geo[i].viser(c[i], reponse: 0.42, amortissement: 1, attente: 0.06) }
            for i in GeoIlot.largeurs { geo[i].viser(c[i], reponse: 0.32, amortissement: 1, attente: 0.06) }
        case .ouverture:
            for i in GeoIlot.largeurs { geo[i].viser(c[i], reponse: alerte ? 0.38 : 0.40, amortissement: alerte ? 0.74 : 0.80) }
            for i in GeoIlot.hauteurs { geo[i].viser(c[i], reponse: alerte ? 0.46 : 0.48, amortissement: alerte ? 0.70 : 0.75) }
        case .glissement:
            for i in geo.indices { geo[i].viser(c[i], reponse: 0.36, amortissement: 0.86) }
        }
        return p
    }
}

/// Une « activité » : ce qui peut occuper l'îlot ou la pastille.
public enum ActiviteIlot: String, Sendable, Equatable {
    case minuteur, rappel, rendezVous, lecture, alerte
    /// Le micro est coupé : l'îlot le rappelle tant qu'il l'est.
    case micro
}

/// Ce qui est vrai à l'instant, pour décider qui a l'îlot et qui a la pastille.
public struct EtatIlot: Equatable, Sendable {
    public var minuteur = false            // un minuteur tourne (ou est en pause)
    public var rappelEnAttente = false     // un rappel a sonné sans réponse : la cloche reste dans l'aile
    public var rendezVousProche = false    // un rendez-vous dans 10 minutes
    public var lecture = false             // quelque chose joue
    public var microCoupe = false          // le micro du Mac est coupé (raccourci, ou Réglages Système)
    public var alerte: VueIlot?            // minuteurFini, rappelEtendu ou agendaDebut, en cours
    public var bandeau: VueIlot?           // un bandeau passager
    public init() {}
}

public struct ResolutionIlot: Equatable, Sendable {
    /// L'écran de l'îlot, au repos (compact, bandeau, alerte, ou repos).
    public var principal: VueIlot
    /// L'écran que l'îlot prend au survol (nil : rien, l'alerte et le bandeau n'ont pas de dépliage).
    public var survol: VueIlot?
    /// Verrou : ni survol ni dépliage (alerte, bandeau).
    public var verrou: Bool
    /// L'activité qui vit dans la pastille sous l'encoche, s'il y en a une.
    public var pastille: ActiviteIlot?
    public init(principal: VueIlot, survol: VueIlot?, verrou: Bool, pastille: ActiviteIlot?) {
        self.principal = principal; self.survol = survol; self.verrou = verrou; self.pastille = pastille
    }
}

public enum ArbitrageIlot {
    /// L'ordre de priorité des activités qui se partagent l'îlot : micro coupé, rendez-vous, rappel, lecture, minuteur. Le micro coupé
    /// passe avant tout : c'est ce qui gêne le plus si on l'oublie (on parle dans un appel où personne n'entend) ; la vidéo devient la bulle.
    public static func ordre(_ e: EtatIlot, echange: ActiviteIlot? = nil) -> [ActiviteIlot] {
        var p: [ActiviteIlot] = []
        if e.microCoupe { p.append(.micro) }
        if e.rendezVousProche { p.append(.rendezVous) }
        if e.rappelEnAttente { p.append(.rappel) }
        if e.lecture { p.append(.lecture) }
        if e.minuteur { p.append(.minuteur) }
        if let echange, p.contains(echange) { p = [echange] + p.filter { $0 != echange } }
        return p
    }

    public static func vues(_ a: ActiviteIlot) -> (compact: VueIlot, etendu: VueIlot) {
        switch a {
        case .minuteur: return (.minuteurCompact, .minuteurEtendu)
        case .rappel: return (.rappelCompact, .rappelEtendu)
        case .rendezVous: return (.agendaCompact, .agendaEtendu)
        case .lecture: return (.lectureCompact, .lectureEtendu)
        case .micro: return (.microCompact, .microEtendu)
        case .alerte: return (.repos, .repos)
        }
    }

    public static func resoudre(_ e: EtatIlot, echange: ActiviteIlot? = nil) -> ResolutionIlot {
        let p = ordre(e, echange: echange)
        if let a = e.alerte { return ResolutionIlot(principal: a, survol: nil, verrou: true, pastille: p.first) }
        // volume et luminosité : un coup d'œil de 1,5 s qui passe par-dessus l'activité ; la bulle ne bouge pas (pas de vidéo qui saute
        // dans la bulle et en revient à chaque touche)
        if let b = e.bandeau, b.estNiveau { return ResolutionIlot(principal: b, survol: nil, verrou: true, pastille: p.count > 1 ? p[1] : nil) }
        if let b = e.bandeau { return ResolutionIlot(principal: b, survol: nil, verrou: true, pastille: p.first) }
        if let premiere = p.first {
            let v = vues(premiere)
            return ResolutionIlot(principal: v.compact, survol: v.etendu, verrou: false, pastille: p.count > 1 ? p[1] : nil)
        }
        return ResolutionIlot(principal: .repos, survol: .accueil, verrou: false, pastille: nil)
    }

    /// L'étage de la priorité (1 = le plus haut) : 1 dictée, 2 réunion, 3 alerte (minuteur fini, rappel, rendez-vous) et micro coupé,
    /// 4 lecture, 5 le reste.
    public static func etage(dictee: Bool, reunion: Bool, ecran: VueIlot) -> Int {
        if dictee { return 1 }
        if reunion { return 2 }
        switch ecran {
        case .minuteurFini, .rappelEtendu, .agendaDebut, .agendaAvant, .agendaCompact, .rappelCompact, .rappelAjoute,
             .microCompact, .microEtendu, .microOuvert: return 3
        case .lectureCompact, .lectureEtendu, .lectureMinuteur: return 4
        default: return 5
        }
    }
}

/// Un ressort amorti (comme celui de la maquette) : part toujours de la valeur affichée et garde sa vitesse, donc interruptible.
/// `reponse` en secondes ; `amortissement` 1 = sans rebond. Une cible peut attendre (`viser(..., attente:)`) : pendant l'attente, le ressort
/// continue vers l'ancienne cible (la maquette fait partir la largeur avant la hauteur à l'ouverture, et l'inverse à la fermeture).
public struct RessortIlot: Equatable, Sendable {
    public var x: Double
    public var v: Double = 0
    public var cible: Double
    public var reponse: Double
    public var amortissement: Double
    public private(set) var attente: Double = 0
    private var cibleFuture: Double?
    private var reponseFuture = 0.0, amortissementFuture = 1.0
    public init(_ valeur: Double, reponse: Double, amortissement: Double) {
        x = valeur; cible = valeur; self.reponse = reponse; self.amortissement = amortissement
    }
    public mutating func regler(reponse: Double, amortissement: Double) { self.reponse = reponse; self.amortissement = amortissement }
    /// La cible où le ressort finira (celle qui attend, sinon la cible courante).
    public var cibleFinale: Double { cibleFuture ?? cible }
    /// Nouvelle cible, tout de suite ou après `attente` secondes. Valeur et vitesse sont gardées : jamais de saut.
    public mutating func viser(_ c: Double, reponse r: Double, amortissement z: Double, attente a: Double = 0) {
        if a > 0 { cibleFuture = c; reponseFuture = r; amortissementFuture = z; attente = a; return }
        cibleFuture = nil; attente = 0; cible = c; reponse = r; amortissement = z
    }
    private mutating func simuler(_ dt: Double) {
        guard dt > 0 else { return }
        let w = 2 * Double.pi / reponse, k = w * w, c = 2 * amortissement * w
        let n = max(1, Int((dt * 240).rounded(.up))), h = dt / Double(n)
        for _ in 0..<n { let a = k * (cible - x) - c * v; v += a * h; x += v * h }
    }
    private mutating func prendreLaCibleFuture() {
        if let c = cibleFuture { cible = c; reponse = reponseFuture; amortissement = amortissementFuture }
        cibleFuture = nil; attente = 0
    }
    public mutating func avancer(_ dt: Double) {
        var dt = dt
        if cibleFuture != nil {
            if dt < attente { attente -= dt; simuler(dt); return }
            simuler(attente); dt -= attente
            prendreLaCibleFuture()
        }
        simuler(dt)
    }
    /// Posé : à moins d'un centième de point (ou de pour cent) de sa cible, pratiquement immobile, et plus rien n'attend.
    public var fini: Bool { cibleFuture == nil && abs(cible - x) < 0.01 && abs(v) < 0.05 }
    public mutating func poser() { prendreLaCibleFuture(); x = cible; v = 0 }
}

/// La forme noire : le chemin de la maquette (fonctions `calculer` et `chemin` de ilot-pro-A.html), en points. Origine = centre de
/// l'encoche, y = haut de l'écran. Coins continus : chaque coin s'étend sur 1,6 fois son rayon, poignées à 0,18 de cette portée (courbure
/// nulle aux deux bouts, comme les coins d'Apple, et non un quart de cercle).
public enum TraceIlot {
    public enum Commande: Equatable, Sendable {
        case deplacer(Double, Double)
        case ligne(Double, Double)
        case quad(Double, Double, Double, Double)                         // contrôle, point
        case cubique(Double, Double, Double, Double, Double, Double)     // contrôle 1, contrôle 2, point
    }

    public struct Points: Equatable, Sendable {
        public var commandes: [Commande]
        /// Plus grande demi-largeur dans la hauteur de la barre (cou + épaule ou congé) : jamais plus que les ailes.
        public var bande: Double
        /// Demi-largeur du cou lui-même (le bord droit de l'îlot sous l'épaule, là où s'aligne la pastille).
        public var cou: Double
        /// Demi-largeur du corps sous la barre.
        public var corps: Double
        public var hauteur: Double
        /// Largeur dans la barre (gauche, droite) et largeur du bas (gauche, droite).
        public var xGauche: Double { -bande }
        public var xDroite: Double { bande }
        public var basGauche: Double { -corps }
        public var basDroite: Double { corps }
    }

    public static let portee = 1.6, poignee = 0.18

    /// `g` : les sept valeurs de `GeoIlot.valeurs` ; `demiCamera` : la moitié de la vraie caméra ; `barre` : la hauteur de la barre.
    public static func calculer(_ g: [Double], demiCamera: Double, barre: Double) -> Points {
        let n = demiCamera + max(0, g[0]), bw = demiCamera + max(0, g[1]), h = max(1, g[2])
        let rs = max(0, g[3]), rb = max(0, g[4]), rt = max(0, g[5]), f = max(0, g[6])
        let B = barre
        let sousBarre = max(0, h - B)
        // le corps s'élargit dès qu'il existe sous la barre (pas de languette qui tombe avant de s'ouvrir)
        let u = min(sousBarre, 40) / 40
        let e = 1 - pow(1 - u, 2.5)
        let d = max(0, bw - n) * e
        let W = n + d
        let fe = max(0, min(f, d * 0.45, B - rs - 2, sousBarre * 0.6))
        let rte = max(0, min(rt, (d - fe) / portee, sousBarre / 3.2))
        let lam = min(1, d / 6)
        let dispo = (1 - lam) * (h - rs) + lam * (h - B - portee * rte)
        let rbe = max(0, min(rb, dispo / portee, W / portee))
        let a1 = portee * rte, c1 = poignee * a1, a2 = portee * rbe, c2 = poignee * a2
        var c: [Commande] = []
        c.append(.deplacer(-n - rs, -1)); c.append(.ligne(-n - rs, 0)); c.append(.quad(-n, 0, -n, rs))
        if d > 0.5 {
            c.append(.ligne(-n, B - fe)); c.append(.quad(-n, B, -n - fe, B))
            c.append(.ligne(-W + a1, B)); c.append(.cubique(-W + c1, B, -W, B + c1, -W, B + a1))
        }
        c.append(.ligne(-W, h - a2)); c.append(.cubique(-W, h - c2, -W + c2, h, -W + a2, h))
        c.append(.ligne(W - a2, h)); c.append(.cubique(W - c2, h, W, h - c2, W, h - a2))
        if d > 0.5 {
            c.append(.ligne(W, B + a1)); c.append(.cubique(W, B + c1, W - c1, B, W - a1, B))
            c.append(.ligne(n + fe, B)); c.append(.quad(n, B, n, B - fe))
        }
        c.append(.ligne(n, rs)); c.append(.quad(n, 0, n + rs, 0)); c.append(.ligne(n + rs, -1))
        return Points(commandes: c, bande: max(n + rs, n + fe), cou: n, corps: W, hauteur: h)
    }

    /// Plus grande demi-largeur de la forme à la hauteur `y` (pour vérifier que rien ne dépasse dans la barre des menus).
    public static func demiLargeur(_ p: Points, y: Double, barre: Double) -> (gauche: Double, droite: Double) {
        y < barre - 0.01 ? (p.xGauche, p.xDroite) : (p.basGauche, p.basDroite)
    }
}

public enum FormatIlot {
    /// « 10:00 », « 0:42 » : minutes et secondes, arrondi vers le haut (un compte à rebours à 0:00,2 montre 0:01).
    public static func duree(_ secondes: Double) -> String {
        let s = Int(max(0, secondes - 0.001).rounded(.up))
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }
    /// « 14:42 » en heure locale.
    public static func heure(_ date: Date, calendrier: Calendar = .current) -> String {
        let c = calendrier.dateComponents([.hour, .minute], from: date)
        return String(format: "%d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
    /// « 5 min », « 1 h 30 ».
    public static func minutes(_ secondes: Double) -> String {
        let m = Int((secondes / 60).rounded())
        if m >= 60 { return m % 60 == 0 ? "\(m / 60) h" : "\(m / 60) h \(String(format: "%02d", m % 60))" }
        return "\(m) min"
    }
}
