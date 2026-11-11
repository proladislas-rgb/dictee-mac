import Foundation

// « Modifier » le Centre de l'îlot (maquette design/maquettes/ilot-centre.html, étape 9) : comme sur l'iPhone, on retire un bouton (« – »),
// on en ajoute (« Ajouter : » en haut), on les range en les glissant ; « OK » enregistre. Logique pure, sans interface : ce que le Centre
// montre, dans quel ordre, et la place que ça prend.

/// Ce que le Centre peut montrer. Trois genres : les gros boutons ronds (une rangée, six au plus), les deux grandes cases (Minuteur,
/// Étagère) et la grande bande « Noter la réunion ». L'identifiant (`rawValue`) est ce qui est rangé dans les réglages : ne jamais le changer.
public enum ElementCentre: String, CaseIterable, Sendable {
    case micro, dictee, telechargements
    /// Le calendrier du Mac (maquette ilot-bibliotheque.html, étape 10) : éteint, un clic l'allume (macOS demande l'accès une fois).
    case calendrier
    case claude, rappel
    case derniereDictee = "derniere-dictee"
    case reunion, minuteur, etagere

    public enum Genre: Sendable { case rond, grandeCase, bande }

    public var genre: Genre {
        switch self {
        case .minuteur, .etagere: return .grandeCase
        case .reunion: return .bande
        default: return .rond
        }
    }
}

/// Ce que le Centre montre, dans l'ordre. Les ronds se rangent entre eux, les cases entre elles ; la bande est toujours en bas.
public struct DispositionCentre: Equatable, Sendable {
    /// La rangée des ronds en tient six (maquette ilot-bibliotheque.html : colonnes de 70 pt ; un nom trop long y passe sur deux lignes,
    /// `PlanCentre.tailles`) : au-delà, les noms ne tiendraient plus.
    public static let maxRonds = 6
    /// Ce que le Centre montre la première fois (maquette, étape 3) : le micro, le choix du micro de la dictée (seulement avec des
    /// AirPods), Téléchargements, Claude Code, le minuteur et l'étagère, la bande « Noter la réunion ». « Modifier » propose d'ajouter
    /// Rappel et Dernière dictée (maquette, étape 9). Le calendrier s'y ajoute (maquette ilot-bibliotheque.html, étape 10), avant Claude.
    public static let parDefaut: [ElementCentre] = [.micro, .dictee, .telechargements, .calendrier, .claude, .minuteur, .etagere, .reunion]
    /// Ce qui est arrivé après coup dans le Centre par défaut : un Centre déjà rangé (« Modifier ») le reçoit UNE fois, à sa place
    /// (`avecNouveautes`) ; retiré ensuite, il ne revient plus.
    public static let nouveautes: [ElementCentre] = [.calendrier]

    public private(set) var elements: [ElementCentre]

    public init(_ elements: [ElementCentre] = DispositionCentre.parDefaut) {
        var vus = Set<ElementCentre>()
        self.elements = elements.filter { vus.insert($0).inserted }
    }

    /// Relit ce qui est rangé dans les réglages. Rien de rangé : la disposition par défaut. Les identifiants inconnus (une version plus
    /// récente, un réglage abîmé) et les doublons sont ignorés ; si plus rien de connu ne reste d'une liste qui n'était pas vide, c'est la
    /// disposition par défaut (une liste vide, elle, est un choix : tout a été retiré).
    public init(identifiants: [String]?) {
        guard let ids = identifiants else { self.init(); return }
        let connus = ids.compactMap(ElementCentre.init(rawValue:))
        if connus.isEmpty, !ids.isEmpty { self.init(); return }
        self.init(connus)
    }

    /// Ce qui est rangé dans les réglages.
    public var identifiants: [String] { elements.map(\.rawValue) }

    /// Un Centre rangé avant l'arrivée d'une nouveauté (le calendrier) la reçoit à sa place par défaut : devant ce qui la suit dans le
    /// Centre par défaut (Claude Code), sinon après le dernier de son genre. `dejaProposees` : les nouveautés déjà données une fois
    /// (retirées depuis, elles ne reviennent pas). Rend la disposition et ce qui a été proposé cette fois (à retenir), ajouté ou non (une
    /// rangée pleine ne reçoit rien : « Modifier » le propose).
    public func avecNouveautes(dejaProposees: Set<String>) -> (disposition: DispositionCentre, proposees: [ElementCentre]) {
        var d = self
        var proposees: [ElementCentre] = []
        for n in Self.nouveautes where !dejaProposees.contains(n.rawValue) {
            proposees.append(n)
            guard !d.elements.contains(n), d.peutAjouter(n) else { continue }
            let suivants = Self.parDefaut.drop { $0 != n }.dropFirst().filter { $0.genre == n.genre }
            if let s = suivants.first(where: { d.elements.contains($0) }), let i = d.elements.firstIndex(of: s) { d.elements.insert(n, at: i) }
            else { d.ajouter(n) }
        }
        return (d, proposees)
    }

    /// Les ronds montrés : ceux qui sont disponibles (le choix du micro n'existe qu'avec des AirPods), six au plus.
    public func ronds(disponible: (ElementCentre) -> Bool = { _ in true }) -> [ElementCentre] {
        Array(elements.filter { $0.genre == .rond && disponible($0) }.prefix(Self.maxRonds))
    }
    /// Les grandes cases montrées (0, 1 ou 2 ; une seule prend toute la largeur).
    public var cases: [ElementCentre] { elements.filter { $0.genre == .grandeCase } }
    /// La bande « Noter la réunion » est montrée.
    public var bande: Bool { elements.contains(.reunion) }

    /// Ce qu'on peut ajouter, dans l'ordre du catalogue : ce qui n'est pas montré et qui est disponible.
    public func aAjouter(disponible: (ElementCentre) -> Bool = { _ in true }) -> [ElementCentre] {
        ElementCentre.allCases.filter { !elements.contains($0) && disponible($0) }
    }
    /// On peut l'ajouter : il n'est pas déjà là, il est disponible, et pour un rond, la rangée n'est pas pleine.
    public func peutAjouter(_ e: ElementCentre, disponible: (ElementCentre) -> Bool = { _ in true }) -> Bool {
        guard !elements.contains(e), disponible(e) else { return false }
        return e.genre != .rond || ronds(disponible: disponible).count < Self.maxRonds
    }

    /// Ajoute à la fin de son genre (l'ordre d'ajout ; on le range ensuite en le glissant). Faux si ce n'est pas possible.
    @discardableResult
    public mutating func ajouter(_ e: ElementCentre, disponible: (ElementCentre) -> Bool = { _ in true }) -> Bool {
        guard peutAjouter(e, disponible: disponible) else { return false }
        if let dernier = elements.lastIndex(where: { $0.genre == e.genre }) { elements.insert(e, at: dernier + 1) }
        else { elements.append(e) }
        return true
    }

    @discardableResult
    public mutating func retirer(_ e: ElementCentre) -> Bool {
        guard let i = elements.firstIndex(of: e) else { return false }
        elements.remove(at: i)
        return true
    }

    /// Range `e` au rang `rang` parmi `visibles` (les éléments de son genre tels qu'ils sont montrés, `e` compris). Ce qui n'est pas
    /// montré (le choix du micro sans AirPods) garde sa place. Faux si rien n'a changé.
    @discardableResult
    public mutating func deplacer(_ e: ElementCentre, versRang rang: Int, parmi visibles: [ElementCentre]) -> Bool {
        guard let avant = visibles.firstIndex(of: e), elements.contains(e) else { return false }
        let r = min(max(0, rang), visibles.count - 1)
        guard r != avant else { return false }
        let autres = visibles.filter { $0 != e }
        elements.removeAll { $0 == e }
        if r < autres.count, let i = elements.firstIndex(of: autres[r]) { elements.insert(e, at: i) }
        else if let dernier = autres.last, let i = elements.firstIndex(of: dernier) { elements.insert(e, at: i + 1) }
        else { elements.append(e) }
        return true
    }

    // MARK: la place

    /// Les rangées du Centre sous la barre (maquette) : 14 pt de marge, l'en-tête (26), puis chaque rangée présente avec son écart (12 pt
    /// sous l'en-tête, 10 entre deux rangées) : les ronds (96), les cases (76), la bande (40) ; 14 pt de marge en bas. Un nom de rond sur
    /// deux lignes (six ronds : « Télécharge-ments ») allonge la rangée des ronds d'une ligne (`ligneNom`).
    public static let haut: Double = 14, entete: Double = 26, ronds: Double = 96, cases: Double = 76, bande: Double = 40, bas: Double = 14
    public static let ecartEntete: Double = 12, ecart: Double = 10
    /// Une ligne de plus sous les ronds (un nom en 11,5 pt sur deux lignes).
    public static let ligneNom: Double = 14
    /// Les grandes cases côte à côte : la case Minuteur un peu plus large que l'Étagère (maquette ilot-bibliotheque.html : 1,16 / 0,84),
    /// pour son sélecteur « Minuteur · Réveil » et ses quatre heures.
    public static func poidsCase(_ e: ElementCentre) -> Double { e == .minuteur ? 1.16 : 0.84 }

    public enum Rangee: Sendable { case ronds, cases, bande }

    /// Le haut de chaque rangée présente, depuis le haut du corps (sous la barre), et la profondeur totale.
    public static func plan(ronds r: Bool, cases c: Bool, bande b: Bool, nomsSurDeuxLignes: Bool = false) -> (hauts: [Rangee: Double], profondeur: Double) {
        var y = haut + entete
        var hauts: [Rangee: Double] = [:]
        var premiere = true
        for (rangee, presente, h) in [(Rangee.ronds, r, ronds + (nomsSurDeuxLignes ? ligneNom : 0)), (.cases, c, cases), (.bande, b, bande)] where presente {
            y += premiere ? ecartEntete : ecart
            premiere = false
            hauts[rangee] = y
            y += h
        }
        return (hauts, y + bas)
    }

    /// Les largeurs permises pour des textes centrés dans des colonnes de `colonne` pt (les noms sous les ronds) : deux voisins gardent au
    /// moins `ecart` pt entre eux, ceux des bords ne dépassent pas leur colonne. Un nom court laisse sa place à son voisin long
    /// (« Micro » à côté de « Téléchargements ») ; deux voisins trop longs cèdent, le plus long d'abord, puis tous les deux.
    public static func largeursPermises(_ l: [Double], colonne: Double, ecart: Double) -> [Double] {
        var a = l
        guard !a.isEmpty else { return a }
        for _ in 0..<(4 * a.count) {
            var change = false
            for i in [0, a.count - 1] where a[i] > colonne + 1e-9 { a[i] = colonne; change = true }
            for i in 0..<(a.count - 1) {
                let exces = (a[i] + a[i + 1]) / 2 + ecart - colonne
                guard exces > 1e-9 else { continue }
                var reste = 2 * exces
                let (g, p) = a[i] >= a[i + 1] ? (i, i + 1) : (i + 1, i)
                let d = min(reste, a[g] - a[p])
                a[g] -= d; reste -= d
                a[g] -= reste / 2; a[p] -= reste / 2
                change = true
            }
            if !change { break }
        }
        return a
    }

    /// Combien de pastilles « + Rappel » tiennent dans `place` pt (largeurs mesurées, `ecart` entre elles). S'il en reste, la marque
    /// « +N » (largeur `marque(N)`) doit tenir aussi, après la dernière montrée.
    public static func pastillesQuiTiennent(_ largeurs: [Double], place: Double, ecart: Double, marque: (Int) -> Double) -> Int {
        var n = largeurs.count
        while n > 0 {
            let utile = largeurs.prefix(n).reduce(0, +) + ecart * Double(n - 1)
            let reste = largeurs.count - n
            if utile + (reste > 0 ? ecart + marque(reste) : 0) <= place { return n }
            n -= 1
        }
        return 0
    }
}
