import Foundation

// « Micro coupé » (maquette design/maquettes/ilot-apple.html, « Cinq idées de plus », 5) : logique pure, sans CoreAudio ni clavier.
// Un raccourci global coupe le micro d'entrée par défaut du Mac et le rouvre ; tant qu'il est coupé, l'îlot le montre (micro barré rouge,
// « Coupé »). La dictée de Verbe le rouvre le temps de dicter, puis le recoupe. Ce que fait le système (Réglages Système) fait foi.

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

/// Ce que Verbe sait du micro et ce qu'il doit faire. L'îlot montre `coupe` ; les commandes partent vers CoreAudio. Le système fait foi :
/// chaque changement qu'il signale est relu tel qu'il est au moment où on le traite (jamais la valeur d'une notification ancienne), et
/// l'écho de nos propres commandes ne change rien.
public struct VeilleMicro: Equatable, Sendable {
    public enum Commande: Equatable, Sendable { case couper, rouvrir }
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

    /// Le micro est coupé (ce que l'îlot montre). Reste vrai pendant une dictée qui l'a rouvert : il sera recoupé à la fin.
    public private(set) var coupe = false
    /// La dictée de Verbe l'a rouvert le temps de dicter : il faudra le recouper à la fin.
    public private(set) var rouvertPourDictee = false
    public private(set) var dicteeEnCours = false
    /// La dictée en cours écoute ce micro-là.
    private var dicteeSurCeMicro = false
    public init() {}

    /// Le raccourci : coupe, ou rouvre.
    public mutating func basculer() -> Reponse { coupe ? rouvrir() : couper() }

    public mutating func couper() -> Reponse {
        guard !coupe else { return .rien }
        coupe = true
        // pendant une dictée, couper le micro couperait la dictée : il reste ouvert jusqu'à la fin, puis il est coupé
        if dicteeEnCours, dicteeSurCeMicro { rouvertPourDictee = true; return .rien }
        return Reponse(commande: .couper)
    }

    /// Le raccourci ou « Rouvrir ». Pendant une dictée qui l'avait rouvert, il est déjà ouvert : il le reste après.
    public mutating func rouvrir() -> Reponse {
        guard coupe else { return .rien }
        coupe = false
        if rouvertPourDictee { rouvertPourDictee = false; return Reponse(annonce: .ouvert) }
        return Reponse(commande: .rouvrir, annonce: .ouvert)
    }

    /// Le système dit où en est le micro (au lancement, ou quand la propriété change : Réglages Système, autre app, autre micro).
    public mutating func systeme(coupe c: Bool) -> Reponse {
        if rouvertPourDictee {
            // ouvert : c'est nous, pour la dictée. Coupé pendant la dictée : quelqu'un d'autre l'a fait, il n'y a plus rien à recouper.
            if c { rouvertPourDictee = false }
            return .rien
        }
        guard c != coupe else { return .rien }      // l'écho de nos commandes
        coupe = c
        return c ? .rien : Reponse(annonce: .ouvert)
    }

    /// La dictée de Verbe commence ou finit. `memeMicro` : la dictée écoute ce micro-là (en « Automatique » avec des AirPods par défaut,
    /// elle écoute le micro du Mac : inutile de rouvrir celui des AirPods, qu'un appel entendrait).
    public mutating func dictee(enCours: Bool, memeMicro: Bool = true) -> Reponse {
        guard enCours != dicteeEnCours else { return .rien }
        dicteeEnCours = enCours
        dicteeSurCeMicro = enCours && memeMicro
        if enCours {
            guard coupe, memeMicro, !rouvertPourDictee else { return .rien }
            rouvertPourDictee = true
            return Reponse(commande: .rouvrir)
        }
        guard rouvertPourDictee else { return .rien }
        rouvertPourDictee = false
        return Reponse(commande: .couper)
    }

    /// CoreAudio a refusé la commande (un micro sans muet ni volume réglable) : on revient à ce qui est vrai, sans rien annoncer.
    public mutating func commandeEchouee(_ c: Commande) {
        switch c {
        case .couper:
            // couper a échoué : le micro est ouvert (pendant une dictée qui l'avait rouvert, il le reste)
            coupe = false; rouvertPourDictee = false
        case .rouvrir:
            // rouvrir a échoué : il reste coupé (la dictée n'entendra rien), rien à recouper à la fin
            coupe = true; rouvertPourDictee = false
        }
    }

    /// Le réglage s'éteint : on oublie tout (le micro reste comme il est ; s'il était rouvert pour une dictée, il est recoupé).
    public mutating func oublier() -> Reponse {
        let r = rouvertPourDictee && coupe ? Reponse(commande: .couper) : .rien
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
