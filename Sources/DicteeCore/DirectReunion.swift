import Foundation

// Le direct d'une réunion dans l'îlot (maquette design/maquettes/ilot-reunion.html, étapes 3 et 4) : les dernières phrases, « Moi » /
// « Eux » en petit à gauche, les mots pas encore sûrs en gris clair. Logique pure.
//
// Pourquoi le direct était haché, et ce qui est corrigé ici, à la racine :
// - chaque piste est coupée en morceaux de 10 à 30 s, transcrits UN à la fois dans l'ordre où ils FINISSENT : un long tour de
//   « Eux » arrivait après une réplique de « Moi » qui l'avait suivi → tout est remis dans l'ordre de leur DÉBUT ;
// - un même tour de parole coupé en deux morceaux faisait deux lignes → les morceaux consécutifs d'une même voix sont recollés en
//   une phrase (moins de 3 s de silence entre eux) ;
// - Whisper reçoit la fin du morceau précédent comme contexte et la répète parfois en tête du suivant (« … le 2 décembre. Le 2
//   décembre, c'est faisable ») → la reprise est retirée (`FusionPistes.sansReprise`) ;
// - sans casque, la voix des autres revient dans le micro (« Moi » répétait « Eux ») : les échos n'étaient retirés qu'après la
//   réunion → retirés aussi en direct ; une phrase de « Moi » reste grise tant que le passage de « Eux » qui la chevauche n'est pas
//   transcrit (on ne peut pas encore dire si c'est un écho), puis disparaît ou devient blanche.

/// Un morceau de son entendu mais pas encore transcrit : la parole en cours (`fin` nil) ou un morceau parti chez Whisper.
public struct AttenteDirect: Equatable, Sendable {
    public var locuteur: Locuteur
    public var debut: Double
    public var fin: Double?
    public init(locuteur: Locuteur, debut: Double, fin: Double? = nil) { self.locuteur = locuteur; self.debut = debut; self.fin = fin }
}

/// Une ligne du direct : un tour de parole (ou un point marqué). `morceaux` : le texte, sûr (blanc) ou pas encore (gris clair) ;
/// `suite` : la voix parle encore (« … » gris au bout).
public struct LigneDirect: Equatable, Sendable, Identifiable {
    public struct Morceau: Equatable, Sendable {
        public var texte: String
        public var sur: Bool
        public init(texte: String, sur: Bool) { self.texte = texte; self.sur = sur }
    }
    /// Stable d'une mise à jour à l'autre (début du tour, voix) : la ligne qui grandit garde son identité.
    public var id: String
    /// nil : un point marqué (« Point ajouté · 14:15 »).
    public var locuteur: Locuteur?
    public var debut: Double
    public var morceaux: [Morceau]
    public var suite: Bool
    public init(id: String, locuteur: Locuteur?, debut: Double, morceaux: [Morceau], suite: Bool) {
        self.id = id; self.locuteur = locuteur; self.debut = debut; self.morceaux = morceaux; self.suite = suite
    }
    public var estPoint: Bool { locuteur == nil }
    /// Tout le texte, dans l'ordre (le sûr et le gris).
    public var texte: String { morceaux.map(\.texte).joined(separator: " ") }
    /// Rien de sûr encore : la ligne entière est grise.
    public var enAttente: Bool { !estPoint && morceaux.allSatisfy { !$0.sur } }
}

public enum DirectReunion {
    /// Deux passages d'une même voix séparés de moins que ça (secondes) forment un seul tour.
    public static let ecartTour: Double = 3
    /// Le direct ne garde que les dernières lignes (la carte en montre 5 à 7 ; on remonte un peu pour relire).
    public static let maxLignes = 40

    /// Les lignes du direct. `moi`, `eux` : les passages transcrits de chaque piste (dans n'importe quel ordre) ; `attentes` : ce qui
    /// est entendu mais pas encore transcrit ; `points` : les moments marqués (secondes de réunion).
    public static func lignes(moi: [SegmentReunion], eux: [SegmentReunion], attentes: [AttenteDirect] = [], points: [Double] = []) -> [LigneDirect] {
        // les reprises de Whisper, voix par voix, dans l'ordre du son
        let moiPropre = FusionPistes.sansReprises(moi.sorted { $0.debut < $1.debut })
        let euxPropre = FusionPistes.sansReprises(eux.sorted { $0.debut < $1.debut })
        // les échos : jugés contre ce qu'on a déjà de « Eux » ; tant qu'un passage de « Eux » qui chevauche n'est pas transcrit, la
        // phrase de « Moi » reste grise
        let echos = FusionPistes.retirerEchos(moi: moiPropre, eux: euxPropre).moi
        let attentesEux = attentes.filter { $0.locuteur == .eux }
        func douteux(_ s: SegmentReunion) -> Bool {
            attentesEux.contains { a in a.debut - 2 < s.fin && s.debut < (a.fin ?? .infinity) + 2 }
        }
        struct Passage { var s: SegmentReunion; var sur: Bool }
        var passages = euxPropre.map { Passage(s: $0, sur: true) } + echos.map { Passage(s: $0, sur: !douteux($0)) }
        passages.sort { a, b in
            if a.s.debut != b.s.debut { return a.s.debut < b.s.debut }
            return a.s.locuteur == .eux && b.s.locuteur == .moi
        }
        // les tours de parole
        var lignes: [LigneDirect] = []
        var fins: [Double] = []
        for p in passages {
            if let i = lignes.indices.last, lignes[i].locuteur == p.s.locuteur, p.s.debut - fins[i] <= ecartTour {
                if let j = lignes[i].morceaux.indices.last, lignes[i].morceaux[j].sur == p.sur {
                    let avant = lignes[i].morceaux[j].texte
                    lignes[i].morceaux[j].texte = avant + TextAssembler.separateur(entre: avant, et: p.s.texte) + p.s.texte
                } else {
                    lignes[i].morceaux.append(.init(texte: p.s.texte, sur: p.sur))
                }
                fins[i] = max(fins[i], p.s.fin)
            } else {
                lignes.append(LigneDirect(id: cle(p.s.locuteur, p.s.debut), locuteur: p.s.locuteur, debut: p.s.debut, morceaux: [.init(texte: p.s.texte, sur: p.sur)], suite: false))
                fins.append(p.s.fin)
            }
        }
        // ce qui s'entend encore : la dernière ligne de cette voix continue (« … »), sinon une ligne grise « … » à sa place dans le temps
        // « Moi » pendant que « Eux » parle : c'est surtout l'écho des haut-parleurs dans le micro, pas de « … » pour lui
        let attentesMoi = attentes.filter { a in
            a.locuteur == .moi && !attentesEux.contains { e in e.debut - 2 < (a.fin ?? .infinity) && a.debut < (e.fin ?? .infinity) + 2 }
        }
        for l in [Locuteur.eux, .moi] {
            guard let a = (l == .eux ? attentesEux : attentesMoi).min(by: { $0.debut < $1.debut }) else { continue }
            if let i = lignes.lastIndex(where: { $0.locuteur == l }), a.debut - fins[i] <= ecartTour {
                lignes[i].suite = true
            } else {
                let i = lignes.firstIndex { $0.debut > a.debut } ?? lignes.count
                lignes.insert(LigneDirect(id: cle(l, a.debut), locuteur: l, debut: a.debut, morceaux: [], suite: true), at: i)
                fins.insert(a.fin ?? a.debut, at: i)
            }
        }
        // les points marqués, à leur place dans le temps (après les tours commencés avant eux)
        for t in points.sorted() {
            let i = lignes.firstIndex { $0.debut > t } ?? lignes.count
            lignes.insert(LigneDirect(id: "point-\(Int(t * 10))", locuteur: nil, debut: t, morceaux: [.init(texte: FormatIlot.chrono(t), sur: true)], suite: false), at: i)
        }
        return Array(lignes.suffix(maxLignes))
    }

    private static func cle(_ l: Locuteur, _ debut: Double) -> String { "\(l.rawValue)-\(Int((debut * 10).rounded()))" }

    /// Les passages des `secondes` dernières secondes (pour « Ce que j'ai raté »), échos et reprises retirés, dans l'ordre.
    public static func dernieresMinutes(moi: [SegmentReunion], eux: [SegmentReunion], maintenant: Double, secondes: Double = 180) -> [SegmentReunion] {
        let (tout, _) = FusionPistes.transcription(moi: moi, eux: eux)
        return tout.filter { $0.fin >= maintenant - secondes }
    }
}

/// Le défilement du direct (maquette, étape 4) : la liste suit les nouvelles phrases tant qu'on est en bas ; si on remonte pour
/// relire, elle s'arrête (ce qu'on lit ne bouge plus quand une phrase arrive) ; revenue en bas, elle suit de nouveau.
/// `decalage` : points remontés depuis le bas (0 = on suit).
public struct DefilementDirect: Equatable, Sendable {
    public private(set) var decalage: Double = 0
    public init() {}
    public var suit: Bool { decalage < 0.5 }
    /// Un geste : `dy` positif = remonter (les doigts descendent en défilement naturel, comme AppKit). `cache` : la hauteur de la
    /// liste qui ne tient pas dans sa zone (0 : tout tient, rien ne défile).
    public mutating func defiler(_ dy: Double, cache: Double) {
        decalage = min(max(0, cache), max(0, decalage + dy))
    }
    /// La liste a grandi de `ajout` points (une phrase arrive, ou une ligne grandit) : à l'arrêt, le texte lu reste en place.
    public mutating func contenuAjoute(_ ajout: Double, cache: Double) {
        guard !suit else { return }
        decalage = min(max(0, cache), max(0, decalage + ajout))
    }
    public mutating func revenirEnBas() { decalage = 0 }
}
