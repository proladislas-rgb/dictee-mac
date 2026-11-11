import Foundation

// « Micro coupé » (maquette design/maquettes/ilot-apple.html, « Cinq idées de plus », 5) : logique pure, sans CoreAudio ni clavier.
// Un raccourci global coupe le micro d'entrée par défaut du Mac et le rouvre ; tant qu'il est coupé, l'îlot le montre (micro barré rouge,
// « Coupé »). La dictée de Verbe rouvre le micro qu'elle écoute s'il est coupé, le temps de dicter, puis le recoupe. Ce que fait le
// système (Réglages Système) fait foi.

/// Un raccourci clavier : une touche (le caractère que la disposition du clavier donne, en minuscule : « m » sur un AZERTY comme sur un
/// QWERTY, quelle que soit la place de la touche) et ses touches de modification.
public struct RaccourciIlot: Equatable, Sendable {
    public var touche: String
    public var controle: Bool
    public var option: Bool
    public var maj: Bool
    public var commande: Bool

    public init(touche: String, controle: Bool = false, option: Bool = false, maj: Bool = false, commande: Bool = false) {
        self.touche = touche.lowercased(); self.controle = controle; self.option = option; self.maj = maj; self.commande = commande
    }

    /// ⌃⌥M : par défaut pour couper le micro.
    public static let microParDefaut = RaccourciIlot(touche: "m", controle: true, option: true)

    /// Ceux que macOS ou Verbe utilisent déjà : ⌥⌘N (noter la réunion), ⌃⌘Q (verrouiller), ⇧⌘3/4/5 (captures), ⌃⌘F (plein écran),
    /// ⌥⌘D (Dock), ⌃⌘Espace (emoji).
    static let reserves: [RaccourciIlot] = [
        RaccourciIlot(touche: "n", option: true, commande: true), RaccourciIlot(touche: "q", controle: true, commande: true),
        RaccourciIlot(touche: "3", maj: true, commande: true), RaccourciIlot(touche: "4", maj: true, commande: true),
        RaccourciIlot(touche: "5", maj: true, commande: true), RaccourciIlot(touche: "f", controle: true, commande: true),
        RaccourciIlot(touche: "d", option: true, commande: true), RaccourciIlot(touche: " ", controle: true, commande: true),
    ]

    /// Un raccourci global acceptable : une seule touche visible, au moins deux touches de modification dont ⌃ ou ⌘ (⌥ seul tape des
    /// caractères : ⌥M donne « µ » ; ⌘ seul est pris par les apps : ⌘M réduit la fenêtre), et pas un raccourci déjà pris.
    public var estValide: Bool {
        let n = [controle, option, maj, commande].filter { $0 }.count
        return touche.count == 1 && touche != "\u{1B}" && n >= 2 && (controle || commande) && !Self.reserves.contains(self)
    }

    /// « ⌃⌥M » : les touches dans l'ordre d'Apple (⌃ ⌥ ⇧ ⌘), puis la touche en capitale.
    public var libelle: String {
        (controle ? "\u{2303}" : "") + (option ? "\u{2325}" : "") + (maj ? "\u{21E7}" : "") + (commande ? "\u{2318}" : "")
            + (touche == " " ? "Espace" : touche.uppercased())
    }

    /// « ctrl+opt+m » : la forme rangée dans les réglages.
    public var texte: String {
        ([controle ? "ctrl" : nil, option ? "opt" : nil, maj ? "maj" : nil, commande ? "cmd" : nil].compactMap { $0 } + [touche]).joined(separator: "+")
    }
    public init?(texte: String) {
        var morceaux = texte.components(separatedBy: "+")
        // la touche « + » elle-même : « ctrl+opt++ »
        if texte.hasSuffix("++") { morceaux = Array(morceaux.dropLast(2)) + ["+"] }
        guard let t = morceaux.last, t.count == 1 else { return nil }
        let m = Set(morceaux.dropLast())
        guard m.isSubset(of: ["ctrl", "opt", "maj", "cmd"]) else { return nil }
        self.init(touche: t, controle: m.contains("ctrl"), option: m.contains("opt"), maj: m.contains("maj"), commande: m.contains("cmd"))
    }

    /// La touche pressée est-elle ce raccourci ? Les touches de modification doivent être exactement les mêmes (⌃⌥⌘M n'est pas ⌃⌥M).
    public func correspond(touche t: String, controle c: Bool, option o: Bool, maj s: Bool, commande k: Bool) -> Bool {
        t.lowercased() == touche && c == controle && o == option && s == maj && k == commande
    }
}

/// Ce que Verbe sait des micros et ce qu'il doit faire. L'îlot montre `coupe` (le micro PAR DÉFAUT, celui que les apps entendent) ;
/// les commandes partent vers CoreAudio, chacune pour un micro précis (son UID). Le système fait foi : chaque changement qu'il signale
/// est relu tel qu'il est au moment où on le traite (jamais la valeur d'une notification ancienne), et l'écho de nos propres commandes
/// ne change rien.
///
/// La dictée peut écouter un autre micro que celui par défaut (le micro du Mac quand des AirPods sont là, ou un micro choisi dans les
/// Réglages) : c'est CE micro-là qu'elle rouvre s'il est coupé, puis qu'elle recoupe à la fin, même si le micro par défaut a changé entre
/// temps (son UID est gardé).
public struct VeilleMicro: Equatable, Sendable {
    public enum Commande: Equatable, Sendable {
        case couper(String)
        case rouvrir(String)
        public var uid: String { switch self { case .couper(let u), .rouvrir(let u): return u } }
    }
    public enum Annonce: Equatable, Sendable {
        /// Le micro vient d'être rouvert (raccourci, bouton « Rouvrir », ou Réglages Système) : un bandeau vert court.
        case ouvert
    }
    public struct Reponse: Equatable, Sendable {
        public var commande: Commande?
        public var annonce: Annonce?
        public init(commande: Commande? = nil, annonce: Annonce? = nil) { self.commande = commande; self.annonce = annonce }
        public static let rien = Reponse()
    }

    /// L'UID du micro par défaut (nil : aucun micro d'entrée).
    public private(set) var defaut: String?
    /// Le micro par défaut est coupé (ce que l'îlot montre). Reste vrai pendant une dictée qui l'a rouvert : il sera recoupé à la fin.
    public private(set) var coupe = false
    /// L'UID du micro que la dictée a rouvert le temps de dicter : à recouper à la fin (nil : rien à recouper).
    public private(set) var rouvertPourDictee: String?
    public private(set) var dicteeEnCours = false
    /// L'UID du micro qu'écoute la dictée en cours.
    private var microDictee: String?
    public init() {}

    /// Le raccourci : coupe, ou rouvre (le micro par défaut).
    public mutating func basculer() -> Reponse { coupe ? rouvrir() : couper() }

    public mutating func couper() -> Reponse {
        guard let d = defaut, !coupe else { return .rien }
        coupe = true
        // pendant une dictée sur ce micro, le couper couperait la dictée : il reste ouvert jusqu'à la fin, puis il est coupé
        if dicteeEnCours, microDictee == d { rouvertPourDictee = d; return .rien }
        return Reponse(commande: .couper(d))
    }

    /// Le raccourci ou « Rouvrir ». Pendant une dictée qui l'avait rouvert, il est déjà ouvert : il le reste après.
    public mutating func rouvrir() -> Reponse {
        guard let d = defaut, coupe else { return .rien }
        coupe = false
        if rouvertPourDictee == d { rouvertPourDictee = nil; return Reponse(annonce: .ouvert) }
        return Reponse(commande: .rouvrir(d), annonce: .ouvert)
    }

    /// Le système dit quel est le micro par défaut et où il en est (au lancement, ou quand quelque chose change : Réglages Système,
    /// autre app, autre micro par défaut).
    public mutating func systeme(defaut d: String?, coupe c: Bool) -> Reponse {
        if d != defaut {
            // un autre micro par défaut (des AirPods qui arrivent) : l'îlot montre où en est celui-là, sans annonce (rien n'a été rouvert)
            defaut = d
            coupe = d != nil && (c || rouvertPourDictee == d)
            return .rien
        }
        if let r = rouvertPourDictee, r == d {
            // ouvert : c'est nous, pour la dictée. Coupé pendant la dictée : quelqu'un d'autre l'a fait, il n'y a plus rien à recouper.
            if c { rouvertPourDictee = nil }
            return .rien
        }
        guard d != nil, c != coupe else { return .rien }      // l'écho de nos commandes
        coupe = c
        return c ? .rien : Reponse(annonce: .ouvert)
    }

    /// La dictée de Verbe commence (`micro` : l'UID du micro qu'elle écoutera, `coupe` : ce micro est coupé en ce moment) ou finit.
    /// Un micro coupé est rouvert le temps de dicter, puis recoupé, quel que soit le micro par défaut ; un autre micro n'est jamais touché
    /// (celui des AirPods, qu'un appel entendrait, reste coupé quand la dictée écoute le micro du Mac).
    public mutating func dictee(enCours: Bool, micro m: String? = nil, coupe c: Bool = false) -> Reponse {
        guard enCours != dicteeEnCours else { return .rien }
        dicteeEnCours = enCours
        microDictee = enCours ? m : nil
        if enCours {
            guard let m, c, rouvertPourDictee == nil else { return .rien }
            rouvertPourDictee = m
            return Reponse(commande: .rouvrir(m))
        }
        guard let r = rouvertPourDictee else { return .rien }
        rouvertPourDictee = nil
        return Reponse(commande: .couper(r))
    }

    /// CoreAudio a refusé la commande (un micro sans muet ni volume réglable, débranché entre-temps) : on revient à ce qui est vrai,
    /// sans rien annoncer.
    public mutating func commandeEchouee(_ c: Commande) {
        let u = c.uid
        if rouvertPourDictee == u { rouvertPourDictee = nil }
        guard u == defaut else { return }
        switch c {
        case .couper: coupe = false     // couper a échoué : le micro est ouvert
        case .rouvrir: coupe = true     // rouvrir a échoué : il reste coupé (la dictée n'entendra rien), rien à recouper à la fin
        }
    }

    /// Le réglage s'éteint : on oublie tout (les micros restent comme ils sont ; celui rouvert pour une dictée est recoupé).
    public mutating func oublier() -> Reponse {
        let r = rouvertPourDictee.map { Reponse(commande: .couper($0)) } ?? .rien
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
}
