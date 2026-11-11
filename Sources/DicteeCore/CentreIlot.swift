import Foundation

// Le Centre de l'îlot (maquette design/maquettes/ilot-centre.html) : logique pure, sans interface.
// L'îlot ouvert est une pile de cartes : l'activité dépliée (la vidéo, le minuteur…), le Centre, les Dictées (l'ancien panneau de la barre
// des menus), puis l'accueil (rendez-vous, rappel, dernière dictée). On passe de l'une à l'autre en un clic (boutons « Centre » et
// « Dictées », points de page) ou en faisant défiler (un geste = une carte).

public enum CartesIlot {
    /// Les cartes de l'îlot ouvert, de haut en bas. `survol` : l'écran que l'îlot prend au survol (nil : verrouillé, pas de cartes).
    /// Rien ne joue : le Centre d'abord. Une activité : son déplié d'abord (la rangée Minuteur de la lecture compte comme la lecture).
    /// Les Dictées suivent le Centre (maquette : vidéo, Centre, Dictées) ; l'accueil reste au fond.
    public static func pile(survol: VueIlot?) -> [VueIlot] {
        guard let s = survol else { return [] }
        if s == .centre || s == .accueil || s == .dictees { return [.centre, .dictees, .accueil] }
        return [s == .lectureMinuteur ? .lectureEtendu : s, .centre, .dictees, .accueil]
    }

    /// Ce que l'îlot prend au survol, une fois le Centre là. Le micro coupé n'a plus de déplié à lui (son bouton, rouge, « Coupé », est
    /// dans le Centre, et un clic le rouvre) : on ouvre la 2e activité (la vidéo passée en bulle), sinon directement le Centre.
    /// `deuxieme` : le déplié de l'activité de la bulle, s'il y en a une.
    public static func survol(_ s: VueIlot, deuxieme: VueIlot?) -> VueIlot {
        guard s == .microEtendu else { return s }
        if let d = deuxieme, d != .repos, d != .microEtendu { return d }
        return .centre
    }

    /// La carte porte-t-elle le bouton « Centre » à son pied ? Le déplié de TOUTE activité (la vidéo, le minuteur, Claude, un rendez-vous,
    /// un rappel), c'est-à-dire la première carte d'une pile qui contient le Centre : le chemin vers le Centre se voit toujours (on n'a
    /// jamais à deviner un défilement). Le Centre, les Dictées et l'accueil n'en ont pas ; la rangée Minuteur de la lecture prend sa place.
    /// Le pied porte aussi le bouton « Dictées » (maquette, étape 2), quand il tient.
    /// La carte « Réunion » n'en a pas : son bouton « Centre » est dans son en-tête (maquette ilot-reunion.html), sa rangée du bas porte
    /// les boutons de la réunion.
    public static func aUnPied(_ v: VueIlot, pile: [VueIlot]) -> Bool {
        v != .centre && v != .accueil && v != .dictees && v != .reunionEtendu && pile.first == v && pile.contains(.centre)
    }

    /// Ce que le pied ajoute à la hauteur d'une carte : la lecture l'a déjà dans sa géométrie, les autres dépliés l'ajoutent dessous.
    public static func piedEnPlus(_ v: VueIlot, pile: [VueIlot]) -> Double {
        aUnPied(v, pile: pile) && v != .lectureEtendu ? GeoIlot.piedLecture : 0
    }

    /// La carte voisine, `pas` cartes plus bas (+1) ou plus haut (−1) ; nil au bout de la pile (on ne boucle pas).
    public static func voisine(_ pile: [VueIlot], de carte: VueIlot, pas: Int) -> VueIlot? {
        guard let i = pile.firstIndex(of: carte == .lectureMinuteur ? .lectureEtendu : carte) else { return nil }
        let j = i + pas
        return pile.indices.contains(j) && j != i ? pile[j] : nil
    }
}

/// Le défilement (molette, deux doigts sur le trackpad) transformé en cartes : UN geste = UNE carte.
/// - trackpad : les mouvements d'un geste (début → fin) s'additionnent ; la carte change une seule fois, quand ils dépassent `seuil` ;
///   l'inertie (les événements qui suivent le lever des doigts) est ignorée ;
/// - molette : chaque cran change de carte, pas plus d'une fois toutes les `pauseMolette` secondes (une roue lancée ne fait pas défiler
///   toute la pile) ;
/// - un défilement surtout horizontal ne compte pas.
/// Le sens est celui d'une page : vers le bas (doigts qui montent en défilement naturel, `dy` négatif chez AppKit) = la carte d'en dessous.
public struct DefilementIlot: Equatable, Sendable {
    public enum Phase: Sendable { case debut, suite, fin, aucune }
    public static let seuil: Double = 14
    public static let pauseMolette: Double = 0.35

    private var cumul = 0.0
    private var fait = false
    private var derniereMolette = -1e9
    private var gesteSurListe = false

    public init() {}

    /// Le geste va-t-il à la liste des Dictées (elle défile) plutôt qu'aux cartes ? Décidé là où il COMMENCE (premier contact, ou chaque
    /// cran de molette) : `surListe` dit si le pointeur est alors sur la liste, carte Dictées montrée. Toute la suite et l'inertie suivent
    /// ce choix. Un geste parti du Centre, qui passe aux Dictées en chemin, ne fait donc jamais défiler la liste, ni lui ni son inertie ;
    /// un geste parti de la liste la fait défiler jusqu'au bout, même si le pointeur en sort.
    public mutating func pourLaListe(phase: Phase, inertie: Bool, surListe: Bool) -> Bool {
        if !inertie, phase == .debut || phase == .aucune { gesteSurListe = surListe }
        return gesteSurListe
    }

    /// Un événement de défilement ; rend +1 (carte suivante), −1 (précédente) ou nil (rien encore). `t` : en secondes, croissant.
    public mutating func recevoir(dy: Double, dx: Double = 0, phase: Phase, inertie: Bool, t: Double) -> Int? {
        if inertie { return nil }
        switch phase {
        case .debut:
            cumul = 0; fait = false
            return compter(dy: dy, dx: dx)
        case .suite:
            return compter(dy: dy, dx: dx)
        case .fin:
            cumul = 0; fait = false
            return nil
        case .aucune:
            // une molette (ou un événement sans phase) : un cran = une carte, avec une pause
            guard abs(dy) >= 0.5, abs(dy) >= abs(dx), t - derniereMolette >= Self.pauseMolette else { return nil }
            derniereMolette = t
            return dy < 0 ? 1 : -1
        }
    }

    private mutating func compter(dy: Double, dx: Double) -> Int? {
        guard !fait, abs(dy) >= abs(dx) else { return nil }
        cumul += dy
        guard abs(cumul) >= Self.seuil else { return nil }
        fait = true
        return cumul < 0 ? 1 : -1
    }
}

extension GeoIlot {
    /// La bulle « Nouveau : survole l'îlot » (une seule fois, au premier lancement) : l'îlot replié (ou vide) descend de 40 pt sous la barre,
    /// le corps épouse le texte (maquette : bandeau de 300 pt sur 40). Le cou ne bouge pas : la pochette et l'onde restent dans les ailes.
    public static let profondeurBulle: Double = 40

    /// Les sept valeurs de `g` (un écran replié) avec la bulle dessous. `contenu` : la largeur mesurée du texte.
    public static func avecBulle(_ g: [Double], hauteurBarre: Double, demiCamera: Double, contenu: Double) -> [Double] {
        var r = g
        r[1] = max(g[0] + evasementMin, (contenu / 2 + marge - demiCamera).rounded(.up))
        r[2] = hauteurBarre + profondeurBulle
        r[3] = 6; r[4] = 22; r[5] = 14; r[6] = 10
        return r
    }
}

/// La carte « Dictées » (maquette ilot-centre.html, carte 3), en points : 14 de marge, l'en-tête (« ‹ Centre » et la recherche, 30), 6,
/// la liste (200 au plus, elle défile au-delà), le pied (un filet, « Journée · Réunions · Mots · Réglages », 4 + 30), 14. La carte épouse
/// sa liste : de ~140 pt sous la barre (« Aucun résultat ») à 298 (maquette : 331 − 33).
public enum CarteDictees {
    public static let marge: Double = 14
    public static let entete: Double = 30
    public static let ecart: Double = 6
    public static let pied: Double = 4 + 30
    public static let listeMax: Double = 200
    /// Le titre d'un jour (« Aujourd'hui », « Hier », « lundi 9 novembre ») et une ligne (heure, texte, app).
    public static let titreJour: Double = 20
    public static let ligne: Double = 32
    /// « Aucun résultat » (ou « Aucune dictée pour l'instant »).
    public static let rien: Double = 42
    /// Une ligne dépliée : 6 au-dessus, des lignes de texte de 21 pt, 7 dessous (jamais moins qu'une ligne repliée).
    public static let interligne: Double = 21
    public static func ligneDepliee(lignesDeTexte n: Int) -> Double { max(ligne, 6 + interligne * Double(max(1, n)) + 7) }
    public static let profondeurMax = marge + entete + ecart + listeMax + pied + marge

    /// La hauteur de toute la liste (titres des jours et lignes) ; une ligne dépliée ajoute `deplie` points ; vide : « Aucun résultat ».
    public static func hauteurListe(lignesParJour: [Int], deplie: Double = 0) -> Double {
        let n = lignesParJour.reduce(0, +)
        guard n > 0 else { return rien }
        return Double(lignesParJour.filter { $0 > 0 }.count) * titreJour + Double(n) * ligne + max(0, deplie)
    }
    /// La profondeur sous la barre pour une liste de `liste` points (bornée à `listeMax`, la liste défile au-delà).
    public static func profondeur(liste: Double) -> Double { marge + entete + ecart + min(max(0, liste), listeMax) + pied + marge }
    /// Le défilement de la liste, borné : 0 en haut, la hauteur cachée en bas.
    public static func borner(_ decalage: Double, liste: Double) -> Double { min(max(0, liste - listeMax), max(0, decalage)) }
    /// La partie d'un élément de la liste (titre de jour, ligne) qui prend les clics, en points depuis son haut ; nil : aucune. `y` et `h` :
    /// sa place et sa hauteur dans la liste, `liste` : la hauteur visible. Un élément qui tient dans la liste ne prend les clics qu'entier
    /// à l'écran (à moitié sous un bord, le clic visait ce qui est autour). Plus haut que la liste (une longue dictée dépliée), il ne tient
    /// jamais entier : il prend alors les clics sur sa partie visible, jamais sur l'en-tête ni sur le pied.
    public static func partieCliquable(y: Double, h: Double, decalage: Double, liste: Double) -> (debut: Double, fin: Double)? {
        let haut = y - decalage
        if h <= liste { return haut >= -1 && haut + h <= liste + 1 ? (0, h) : nil }
        let debut = max(0, -haut), fin = min(h, liste - haut)
        return fin - debut >= 1 ? (debut, fin) : nil
    }
}

/// Les mots de la recherche dans le texte d'une dictée, pour les surligner : sans tenir compte des accents ni des majuscules (la même
/// règle que `Historique.filtrer`), en positions de caractères, fusionnées et triées.
public enum Surlignage {
    public static func plages(_ texte: String, requete: String) -> [Range<Int>] {
        let mots = Historique.plier(requete).split(whereSeparator: { $0.isWhitespace }).map { Array($0) }.filter { !$0.isEmpty }
        guard !mots.isEmpty, !texte.isEmpty else { return [] }
        // le texte plié caractère par caractère, chaque caractère plié se souvient de sa place dans le texte d'origine
        var plie: [Character] = [], origine: [Int] = []
        for (i, ch) in texte.enumerated() { for c in Historique.plier(String(ch)) { plie.append(c); origine.append(i) } }
        var marque = [Bool](repeating: false, count: texte.count)
        for m in mots where m.count <= plie.count {
            var i = 0
            while i + m.count <= plie.count {
                if plie[i] == m[0], Array(plie[i ..< i + m.count]) == m {
                    for k in i ..< i + m.count { marque[origine[k]] = true }
                    i += m.count
                } else { i += 1 }
            }
        }
        var plages: [Range<Int>] = []
        var debut: Int?
        for (i, x) in marque.enumerated() {
            if x, debut == nil { debut = i }
            if !x, let d = debut { plages.append(d ..< i); debut = nil }
        }
        if let d = debut { plages.append(d ..< marque.count) }
        return plages
    }
}

/// L'icône ❞ de Verbe dans la barre des menus. Tout vit dans l'îlot ; mais sans encoche sur l'écran principal (Mac sans encoche, écran
/// externe principal), l'îlot vide n'existe pas : l'icône est alors toujours là (c'est le chemin vers Verbe, et vers « Couper le micro »).
/// Avec une encoche, le réglage décide ; jamais réglé, elle est éteinte.
public enum PresenceIcone {
    public static func montree(reglage: Bool?, encoche: Bool) -> Bool { !encoche || (reglage ?? false) }
}
