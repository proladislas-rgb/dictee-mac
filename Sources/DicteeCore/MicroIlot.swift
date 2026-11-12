import Foundation

// « Micro coupé » (maquette design/maquettes/ilot-apple.html, « Cinq idées de plus », 5) : logique pure, sans CoreAudio ni clavier.
// Le bouton Micro du Centre de l'îlot coupe le micro d'entrée par défaut du Mac et le rouvre (plus de raccourci clavier depuis le 11/11 :
// le Centre est le seul chemin, seule la touche fn reste, pour dicter) ; tant qu'il est coupé, l'îlot le montre (micro barré rouge,
// « Coupé »). Coupé veut dire coupé (Hugues, 11/11 au soir : fn rouvrait le micro en douce, il ne s'y attendait pas) : fn ne démarre
// PAS la dictée sur un micro coupé, l'îlot le dit et propose « Rouvrir le micro ». Si la dictée écoute un AUTRE micro, ouvert (le micro
// du Mac pendant que les AirPods sont coupés), elle part, et l'îlot le dit. Ce que fait le système (Réglages Système) fait foi.

/// Ce que Verbe sait des micros et ce qu'il doit faire. L'îlot montre `coupe` (le micro PAR DÉFAUT, celui que les apps entendent) ;
/// les commandes partent vers CoreAudio, chacune pour un micro précis (son UID). Le système fait foi : chaque changement qu'il signale
/// est relu tel qu'il est au moment où on le traite (jamais la valeur d'une notification ancienne), et l'écho de nos propres commandes
/// ne change rien.
///
/// La dictée peut écouter un autre micro que celui par défaut (le micro du Mac quand des AirPods sont là, ou un micro choisi dans les
/// Réglages) : c'est CE micro-là (son UID) qui décide si fn dicte ou non.
public struct VeilleMicro: Equatable, Sendable {
    public enum Commande: Equatable, Sendable {
        case couper(String)
        case rouvrir(String)
        public var uid: String { switch self { case .couper(let u), .rouvrir(let u): return u } }
    }
    public enum Annonce: Equatable, Sendable {
        /// Le micro vient d'être rouvert (bouton Micro, « Rouvrir », ou Réglages Système) : un bandeau vert court.
        case ouvert
    }
    public struct Reponse: Equatable, Sendable {
        public var commande: Commande?
        public var annonce: Annonce?
        public init(commande: Commande? = nil, annonce: Annonce? = nil) { self.commande = commande; self.annonce = annonce }
        public static let rien = Reponse()
    }
    /// Ce que fait un appui sur fn, décidé AVANT que la dictée ne démarre (aucun son n'est encore capté).
    public enum AvantDictee: Equatable, Sendable {
        /// Rien de coupé (ou rien qui concerne la dictée) : elle part.
        case dicter
        /// Le micro qu'écouterait la dictée est coupé (son UID) : elle ne part pas, l'îlot dit « Micro coupé » et propose « Rouvrir et
        /// dicter ». Rien n'est rouvert en douce.
        case bloquer(String)
        /// Le micro par défaut est coupé (son UID), mais la dictée en écoute un autre, ouvert : elle part, et l'îlot le dit (une fois par
        /// coupure, pas à chaque appui).
        case dicterAvecUnAutre(coupe: String)
    }

    /// L'UID du micro par défaut (nil : aucun micro d'entrée).
    public private(set) var defaut: String?
    /// Le micro par défaut est coupé (ce que l'îlot montre). Reste vrai pendant une dictée qui le garde ouvert : il sera coupé à la fin.
    public private(set) var coupe = false
    /// L'UID du micro coupé pendant une dictée qui l'écoutait : il reste ouvert jusqu'à la fin de la dictée, puis il est coupé (nil :
    /// rien à couper à la fin).
    public private(set) var aCouperApres: String?
    public private(set) var dicteeEnCours = false
    /// L'UID du micro qu'écoute la dictée en cours.
    private var microDictee: String?
    /// Le micro coupé dont on a déjà dit « la dictée passe par un autre micro » (pas à chaque appui sur fn).
    private var autreDejaDit: String?
    public init() {}

    /// Le bouton Micro : coupe, ou rouvre (le micro par défaut).
    public mutating func basculer() -> Reponse { coupe ? rouvrir() : couper() }

    public mutating func couper() -> Reponse {
        guard let d = defaut, !coupe else { return .rien }
        coupe = true
        autreDejaDit = nil
        // pendant une dictée sur ce micro, le couper couperait la dictée : il reste ouvert jusqu'à la fin, puis il est coupé
        if dicteeEnCours, microDictee == d { aCouperApres = d; return .rien }
        return Reponse(commande: .couper(d))
    }

    /// Le bouton Micro ou « Rouvrir ». Pendant une dictée qui le gardait ouvert, il l'est déjà : il le reste après.
    public mutating func rouvrir() -> Reponse {
        guard let d = defaut, coupe else { return .rien }
        coupe = false
        if aCouperApres == d { aCouperApres = nil; return Reponse(annonce: .ouvert) }
        return Reponse(commande: .rouvrir(d), annonce: .ouvert)
    }

    /// « Rouvrir le micro » : rouvre le micro qu'écoute la dictée (`u`, celui qu'un appui sur fn a trouvé coupé), même si ce n'est pas
    /// celui par défaut. Le prochain appui sur fn dicte.
    public mutating func rouvrirPourDicter(_ u: String) -> Reponse {
        if u == defaut { return coupe ? rouvrir() : Reponse(commande: .rouvrir(u), annonce: .ouvert) }
        return Reponse(commande: .rouvrir(u), annonce: .ouvert)
    }

    /// Le système dit quel est le micro par défaut et où il en est (au lancement, ou quand quelque chose change : Réglages Système,
    /// autre app, autre micro par défaut).
    public mutating func systeme(defaut d: String?, coupe c: Bool) -> Reponse {
        if d != defaut {
            // un autre micro par défaut (des AirPods qui arrivent) : l'îlot montre où en est celui-là, sans annonce (rien n'a été rouvert)
            defaut = d
            coupe = d != nil && (c || aCouperApres == d)
            autreDejaDit = nil
            return .rien
        }
        if let r = aCouperApres, r == d {
            // ouvert : c'est la dictée en cours. Coupé pendant la dictée : quelqu'un d'autre l'a fait, il n'y a plus rien à couper.
            if c { aCouperApres = nil }
            return .rien
        }
        guard d != nil, c != coupe else { return .rien }      // l'écho de nos commandes
        coupe = c
        if c { autreDejaDit = nil }
        return c ? .rien : Reponse(annonce: .ouvert)
    }

    /// fn vient d'être appuyée : la dictée écouterait le micro `m` (son UID), qui est coupé (`c`) ou non. Rien n'est rouvert ici.
    public mutating func avantDictee(micro m: String?, coupe c: Bool) -> AvantDictee {
        if let m, c { return .bloquer(m) }
        guard let d = defaut, coupe, m != d else { return .dicter }
        if autreDejaDit == d { return .dicter }
        autreDejaDit = d
        return .dicterAvecUnAutre(coupe: d)
    }

    /// La dictée de Verbe commence (`micro` : l'UID du micro qu'elle écoute) ou finit. Elle ne rouvre jamais rien : un micro coupé
    /// pendant qu'elle l'écoutait est coupé à sa fin.
    public mutating func dictee(enCours: Bool, micro m: String? = nil) -> Reponse {
        guard enCours != dicteeEnCours else { return .rien }
        dicteeEnCours = enCours
        microDictee = enCours ? m : nil
        guard !enCours, let r = aCouperApres else { return .rien }
        aCouperApres = nil
        return Reponse(commande: .couper(r))
    }

    /// CoreAudio a refusé la commande (un micro sans muet ni volume réglable, débranché entre-temps) : on revient à ce qui est vrai,
    /// sans rien annoncer.
    public mutating func commandeEchouee(_ c: Commande) {
        let u = c.uid
        if aCouperApres == u { aCouperApres = nil }
        guard u == defaut else { return }
        switch c {
        case .couper: coupe = false     // couper a échoué : le micro est ouvert
        case .rouvrir: coupe = true     // rouvrir a échoué : il reste coupé (fn le dira encore)
        }
    }

    /// Le réglage s'éteint : on oublie tout (les micros restent comme ils sont ; celui qu'une dictée gardait ouvert est coupé).
    public mutating func oublier() -> Reponse {
        let r = aCouperApres.map { Reponse(commande: .couper($0)) } ?? .rien
        self = VeilleMicro()
        return r
    }
}

public enum MicroIlot {
    /// Repli pour un micro sans « muet » (volume d'entrée à 0) : le volume à rendre en rouvrant. Celui d'avant, s'il était audible ;
    /// sinon 75 % (un volume gardé à 0 rouvrirait un micro qui n'entend rien).
    public static func volumeARendre(garde: Double?) -> Double {
        guard let g = garde, g.isFinite, g > 0.05 else { return 0.75 }
        return min(1, g)
    }
    /// Un micro « au volume » est coupé quand son volume est nul.
    public static func estCoupe(volume: Double) -> Bool { volume < 0.001 }

    /// Comment l'îlot désigne un micro, d'après son nom : « le micro des AirPods », « le micro du Mac » (Micro MacBook Air, MacBook Pro
    /// Microphone, iMac…), sinon « le micro « Yeti » » ; nom inconnu : « un autre micro ».
    public static func designation(nom: String?) -> String {
        guard let n = nom?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty else { return "un autre micro" }
        let b = n.lowercased()
        if b.contains("airpods") { return "le micro des AirPods" }
        if ["macbook", "imac", "mac mini", "mac studio", "mac pro"].contains(where: b.contains) { return "le micro du Mac" }
        return "le micro \u{00AB}\u{00A0}" + n + "\u{00A0}\u{00BB}"
    }
    /// Le bandeau de fn quand le micro par défaut est coupé mais que la dictée en écoute un autre : « Le micro des AirPods est coupé »,
    /// « Verbe dicte avec le micro du Mac ».
    public static func autreMicro(coupe: String?, dictee: String?) -> (titre: String, sousTitre: String) {
        let c = designation(nom: coupe)
        return (c.prefix(1).uppercased() + c.dropFirst() + " est coupé", "Verbe dicte avec " + designation(nom: dictee))
    }
}
