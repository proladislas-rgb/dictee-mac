import Foundation

// L'îlot « centre d'activités » (maquette design/maquettes/ilot-activites.html) : logique pure, sans interface.
// Une seule forme noire dans l'encoche, trois tailles (minimal, compact, étendu), une règle de priorité, une pastille pour la deuxième activité.

/// Les « écrans » que l'îlot sait montrer. Chacun a une géométrie (`GeoIlot`) : la forme noire se déforme de l'un à l'autre.
public enum VueIlot: String, CaseIterable, Sendable {
    case repos
    case minuteurMinimal, minuteurCompact, minuteurEtendu, minuteurLance, minuteurFini
    case lectureCompact, lectureEtendu
    case rappelEtendu, rappelCompact, rappelAjoute, rappelFait, rappelReporte, rappelListe
    case agendaAvant, agendaCompact, agendaEtendu, agendaDebut
    case notification, notifications
    case accueil

    /// Ces écrans sont des bandeaux : ils s'annoncent, restent un instant, puis se retirent d'eux-mêmes.
    public var estBandeau: Bool {
        switch self {
        case .minuteurLance, .rappelAjoute, .rappelFait, .rappelReporte, .agendaAvant, .notification, .notifications: return true
        default: return false
        }
    }
    /// Ces écrans sont des alertes : l'îlot s'ouvre de lui-même, vibre, sonne, et attend un geste.
    public var estAlerte: Bool { self == .minuteurFini || self == .rappelEtendu || self == .agendaDebut }
}

/// Géométrie de la forme : [aile gauche, aile droite, corps gauche, corps droit, hauteur, rayon].
/// Les ailes (≤ 66 pt) sont ce qui touche la barre des menus ; le corps, plus large, vit SOUS la barre. Hauteurs données pour une barre de
/// 32 pt (celle de la maquette) : `GeoIlot.valeurs` ajoute la différence avec la vraie barre.
public enum GeoIlot {
    public static let aileMax: Double = 66
    static let comp: [Double] = [66, 66, 66, 66, 32, 12]
    static let ban: [Double] = [66, 66, 110, 110, 84, 28]
    static let table: [VueIlot: [Double]] = [
        .repos: [0, 0, 0, 0, 32, 10],
        .minuteurMinimal: [44, 0, 44, 0, 32, 12], .minuteurCompact: comp, .minuteurEtendu: [66, 66, 130, 130, 162, 34],
        .minuteurLance: ban, .minuteurFini: [66, 66, 130, 130, 154, 34],
        .lectureCompact: comp, .lectureEtendu: [66, 66, 130, 130, 182, 34],
        .rappelEtendu: [66, 66, 130, 130, 158, 34], .rappelCompact: comp, .rappelAjoute: ban,
        .rappelFait: [66, 66, 110, 110, 84, 28], .rappelReporte: ban, .rappelListe: [66, 66, 130, 130, 178, 34],
        .agendaAvant: ban, .agendaCompact: comp, .agendaEtendu: [66, 66, 130, 130, 180, 34], .agendaDebut: ban,
        .notification: ban, .notifications: ban,
        .accueil: [66, 66, 130, 130, 222, 36],
    ]
    public static let barreMaquette: Double = 32

    /// Les six valeurs pour une vue, la hauteur ajustée à la vraie barre des menus (`hauteurBarre`). Le repos épouse exactement la barre.
    public static func valeurs(_ v: VueIlot, hauteurBarre: Double) -> [Double] {
        var g = table[v] ?? table[.repos]!
        g[4] += hauteurBarre - barreMaquette
        return g
    }
    /// Vrai quand la forme est plus grande que la précédente (ouverture : ressort plus vif, un peu de rebond).
    public static func ouvre(de a: [Double], vers b: [Double]) -> Bool { b[4] > a[4] + 4 || b[3] > a[3] + 4 }
}

/// Une « activité » : ce qui peut occuper l'îlot ou la pastille.
public enum ActiviteIlot: String, Sendable, Equatable {
    case minuteur, rappel, rendezVous, lecture, alerte
}

/// Ce qui est vrai à l'instant, pour décider qui a l'îlot et qui a la pastille.
public struct EtatIlot: Equatable, Sendable {
    public var minuteur = false            // un minuteur tourne (ou est en pause)
    public var rappelEnAttente = false     // un rappel a sonné sans réponse : la cloche reste dans l'aile
    public var rendezVousProche = false    // un rendez-vous dans 10 minutes
    public var lecture = false             // quelque chose joue
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
    /// L'ordre de priorité des activités qui se partagent l'îlot : rendez-vous, rappel, lecture, minuteur.
    public static func ordre(_ e: EtatIlot, echange: ActiviteIlot? = nil) -> [ActiviteIlot] {
        var p: [ActiviteIlot] = []
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
        case .alerte: return (.repos, .repos)
        }
    }

    public static func resoudre(_ e: EtatIlot, echange: ActiviteIlot? = nil) -> ResolutionIlot {
        let p = ordre(e, echange: echange)
        if let a = e.alerte { return ResolutionIlot(principal: a, survol: nil, verrou: true, pastille: p.first) }
        if let b = e.bandeau { return ResolutionIlot(principal: b, survol: nil, verrou: true, pastille: p.first) }
        if let premiere = p.first {
            let v = vues(premiere)
            return ResolutionIlot(principal: v.compact, survol: v.etendu, verrou: false, pastille: p.count > 1 ? p[1] : nil)
        }
        return ResolutionIlot(principal: .repos, survol: .accueil, verrou: false, pastille: nil)
    }

    /// L'étage de la priorité (1 = le plus haut) : 1 dictée, 2 réunion, 3 alerte (minuteur fini, rappel, rendez-vous), 4 lecture, 5 le reste.
    public static func etage(dictee: Bool, reunion: Bool, ecran: VueIlot) -> Int {
        if dictee { return 1 }
        if reunion { return 2 }
        switch ecran {
        case .minuteurFini, .rappelEtendu, .agendaDebut, .agendaAvant, .agendaCompact, .rappelCompact, .rappelAjoute: return 3
        case .lectureCompact, .lectureEtendu: return 4
        default: return 5
        }
    }
}

/// Un ressort amorti (comme celui de la maquette) : part toujours de la valeur affichée et garde sa vitesse, donc interruptible.
/// `reponse` en secondes ; `amortissement` 1 = sans rebond.
public struct RessortIlot: Equatable, Sendable {
    public var x: Double
    public var v: Double = 0
    public var cible: Double
    public var reponse: Double
    public var amortissement: Double
    public init(_ valeur: Double, reponse: Double, amortissement: Double) {
        x = valeur; cible = valeur; self.reponse = reponse; self.amortissement = amortissement
    }
    public mutating func regler(reponse: Double, amortissement: Double) { self.reponse = reponse; self.amortissement = amortissement }
    public mutating func avancer(_ dt: Double) {
        let w = 2 * Double.pi / reponse, k = w * w, c = 2 * amortissement * w
        let n = max(1, Int((dt * 240).rounded(.up))), h = dt / Double(n)
        for _ in 0..<n { let a = k * (cible - x) - c * v; v += a * h; x += v * h }
    }
    /// Posé : à moins d'un centième de point (ou de pour cent) de sa cible et pratiquement immobile : rien de visible ne change plus.
    public var fini: Bool { abs(cible - x) < 0.01 && abs(v) < 0.05 }
    public mutating func poser() { x = cible; v = 0 }
}

/// La forme noire : le chemin de la maquette, calculé en points. Origine = centre de l'encoche, y = haut de l'écran.
public enum TraceIlot {
    public struct Segment: Equatable, Sendable {
        public enum Genre: Sendable { case ligne, arc }
        public var genre: Genre
        public var x: Double, y: Double
        public var rayon: Double = 0
        public var sens: Bool = false   // pour un arc : sens horaire (true) ou non
    }

    public struct Points: Equatable, Sendable {
        public var departX: Double, departY: Double
        public var segments: [Segment]
        /// Largeur de la forme dans la hauteur de la barre (jamais plus que les ailes).
        public var xGauche: Double, xDroite: Double, basGauche: Double, basDroite: Double
    }

    static func lisse(_ v: Double) -> Double { let x = min(1, max(0, v)); return x * x * (3 - 2 * x) }

    /// `demiCamera` : la moitié de la vraie caméra ; `barre` : la hauteur de la barre des menus.
    public static func calculer(_ g: [Double], demiCamera: Double, barre: Double) -> Points {
        let tl = g[0], tr = g[1], bl = g[2], br = g[3], h = g[4]
        let r = max(0, min(g[5], h / 2))
        // le corps ne s'élargit qu'une fois assez haut : jamais plus large que les ailes dans la bande de la barre des menus
        let wf = lisse((h - r - (barre - 6)) / 12)
        let dl = max(0, bl - tl) * wf, dr = max(0, br - tr) * wf
        let xl = -demiCamera - tl, xr = demiCamera + tr, xbl = xl - dl, xbr = xr + dr
        let fL = min(10, dl * 0.45), fR = min(10, dr * 0.45), cL = min(12, dl * 0.55), cR = min(12, dr * 0.55)
        let b = max(0, min(barre, h - r - max(cL, cR) - 1))
        var s: [Segment] = []
        func L(_ x: Double, _ y: Double) { s.append(Segment(genre: .ligne, x: x, y: y)) }
        func A(_ ra: Double, _ x: Double, _ y: Double, _ sens: Bool) { s.append(Segment(genre: .arc, x: x, y: y, rayon: ra, sens: sens)) }
        L(xr, 0)
        L(xr, b - fR)
        A(fR, xr + fR, b, false)
        L(xbr - cR, b)
        A(cR, xbr, b + cR, true)
        L(xbr, h - r)
        A(r, xbr - r, h, true)
        L(xbl + r, h)
        A(r, xbl, h - r, true)
        L(xbl, b + cL)
        A(cL, xbl + cL, b, true)
        L(xl - fL, b)
        A(fL, xl, b - fL, false)
        return Points(departX: xl, departY: 0, segments: s, xGauche: xl, xDroite: xr, basGauche: xbl, basDroite: xbr)
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
