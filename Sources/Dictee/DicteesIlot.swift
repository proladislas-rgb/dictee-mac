import AppKit
import Combine
import SwiftUI
import DicteeCore

// La carte « Dictées » de l'îlot (maquette design/maquettes/ilot-centre.html, étapes 10 à 12) : l'ancien panneau de la barre des menus
// (PanneauCompact + ListeDictees), dans l'îlot. On y arrive par le bouton « Dictées » au pied d'un déplié, par la pilule « Dictées » du
// Centre, par les points de page ou en faisant défiler (la carte qui suit le Centre).
// - en-tête : « ‹ Centre » et le champ « Rechercher » ; la fenêtre de l'îlot ne prend le clavier QUE pendant qu'on tape dans ce champ
//   (après un clic dedans), et le rend sitôt la carte quittée, l'îlot rangé ou une dictée commencée (IlotPanneau.prendreLeClavier) ;
// - la liste : les dictées groupées par jour (« Aujourd'hui », « Hier », « lundi 9 novembre »), l'heure, le texte (Newsreader, la police
//   des dictées), l'app où elles sont allées ; recherche sans accents ni majuscules, mots surlignés ; un clic copie (« Copié » dans la
//   ligne), « Coller » au survol remet le texte dans l'app d'où l'on vient, le chevron déplie le texte entier ; la liste défile dans la
//   carte au-delà de 200 pt, la carte grandit avec elle (~172 à ~331 pt) ;
// - le pied : « Journée · Réunions · Mots · Réglages » ouvrent la fenêtre principale sur l'onglet.
// Confidentialité : l'historique est lu là où il est (HistoriqueStore, sur ce Mac) ; rien de nouveau n'est écrit sur le disque, rien ne
// sort du Mac. Le journal ne note que des longueurs, jamais un texte.

/// L'état de la carte : la recherche, la ligne survolée, dépliée, copiée, le défilement de la liste. La mise en page (les titres des jours
/// et les lignes, leur place et leur hauteur) est calculée une fois et gardée tant que rien ne change.
@MainActor
final class DicteesIlot: ObservableObject {
    /// D'où vient l'historique (injectable : les essais et les rendus donnent un historique en mémoire, jamais le vrai fichier).
    /// Changer de source redessine la carte (sinon elle garde les lignes de l'ancienne jusqu'au prochain changement publié, et un survol
    /// y pointe une dictée que la nouvelle source ne connaît pas).
    var source: () -> HistoriqueStore = { HistoriqueStore.shared } { didSet { store_ = nil; abonnement = nil; cache = nil; survol = nil; objectWillChange.send() } }
    private var store_: HistoriqueStore?
    private var abonnement: AnyCancellable?
    var store: HistoriqueStore {
        if let s = store_ { return s }
        let s = source()
        store_ = s
        // une nouvelle dictée (ou une dictée supprimée dans la fenêtre) : la liste et la hauteur de la carte suivent
        abonnement = s.$historique.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.cache = nil; self?.changement() } }
        }
        return s
    }
    var maintenant: () -> Date = { Date() }

    @Published var requete = "" { didSet { if requete != oldValue { deplie = nil; decalage = 0; survol = nil; changement() } } }
    @Published var survol: UUID?
    @Published var deplie: UUID? { didSet { if deplie != oldValue { changement() } } }
    @Published private(set) var copiee: UUID?
    /// Le défilement de la liste (0 en haut).
    @Published var decalage: Double = 0
    /// Le champ a le clavier (un clic dedans) : la fenêtre de l'îlot est la fenêtre clé le temps de taper.
    @Published var rechercheActive = false
    @Published var jetonFocus = 0
    /// Ce que la carte fait (copier, coller, ouvrir la fenêtre, prendre ou rendre le clavier) : branché par le moteur.
    var agir: (ActionIlot) -> Void = { _ in }
    /// La hauteur de la carte peut avoir changé (recherche, ligne dépliée, nouvelle dictée).
    var surChangement: () -> Void = {}
    /// La largeur du texte d'une ligne dépliée (pour la mesurer), donnée par le moteur depuis la vraie caméra.
    var largeurTexte: CGFloat = 276 { didSet { if largeurTexte != oldValue { cache = nil } } }
    private var muet = false
    private var finCopie: DispatchWorkItem?

    private func changement() { if !muet { surChangement() } }

    /// Remise à zéro quand l'îlot se range : la recherche, la ligne dépliée, le défilement (sans redemander une forme).
    func reinitialiser() {
        muet = true
        requete = ""; deplie = nil; survol = nil; decalage = 0
        muet = false
    }

    // MARK: la liste

    /// Un titre de jour ou une ligne, à sa place dans la liste (y depuis le haut de la liste, en points).
    struct Element: Identifiable {
        enum Genre { case jour(String), ligne(EntreeHistorique) }
        var id: String
        var genre: Genre
        var y: Double
        var h: Double
    }
    struct MiseEnPage {
        var elements: [Element] = []
        var hauteur: Double = CarteDictees.rien
        /// Aucune dictée du tout (pas seulement aucun résultat).
        var historiqueVide = true
        var affichees: [EntreeHistorique] = []
    }
    private var cache: (cle: String, page: MiseEnPage)?

    func miseEnPage() -> MiseEnPage {
        let h = store.historique
        let jour = Calendar.current.ordinality(of: .day, in: .era, for: maintenant()) ?? 0
        let cle = "\(h.entrees.count)|\(h.entrees.first?.id.uuidString ?? "")|\(requete)|\(deplie?.uuidString ?? "")|\(largeurTexte)|\(jour)"
        if let c = cache, c.cle == cle { return c.page }
        var p = MiseEnPage()
        p.historiqueVide = h.estVide
        p.affichees = h.filtrer(requete)
        var y = 0.0
        for g in Historique.groupes(p.affichees, maintenant: maintenant()) {
            p.elements.append(Element(id: "j:" + g.titre, genre: .jour(g.titre), y: y, h: CarteDictees.titreJour))
            y += CarteDictees.titreJour
            for e in g.entrees {
                let hl = e.id == deplie ? Self.hauteurDepliee(e.texte, largeur: largeurTexte) : CarteDictees.ligne
                p.elements.append(Element(id: e.id.uuidString, genre: .ligne(e), y: y, h: hl))
                y += hl
            }
        }
        p.hauteur = p.affichees.isEmpty ? CarteDictees.rien : y
        cache = (cle, p)
        return p
    }

    /// La hauteur d'une ligne dépliée : le texte mesuré (Core Text, la police des dictées) un peu plus étroit que sa place, pour ne jamais
    /// annoncer une ligne de moins que ce que SwiftUI dessinera.
    static func hauteurDepliee(_ texte: String, largeur: CGFloat) -> Double {
        let f = Polices.nsTexte(PlanDictees.policeTexte)
        let r = (texte as NSString).boundingRect(with: CGSize(width: max(40, largeur - 6), height: .greatestFiniteMagnitude),
                                                 options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: f])
        let naturelle = max(1, ceil(f.ascender - f.descender + f.leading))
        return CarteDictees.ligneDepliee(lignesDeTexte: Int((r.height / naturelle).rounded(.up)))
    }

    func entree(_ id: UUID) -> EntreeHistorique? { store.historique.entrees.first { $0.id == id } }
    /// La liste dépasse-t-elle sa place (elle défile alors dans la carte) ?
    var defile: Bool { miseEnPage().hauteur > CarteDictees.listeMax + 0.5 }
    /// Un geste de défilement sur la liste (`dy` positif : vers le haut de la liste, comme AppKit en défilement naturel).
    func defiler(_ dy: Double) {
        let n = CarteDictees.borner(decalage - dy, liste: miseEnPage().hauteur)
        if abs(n - decalage) > 0.01 { decalage = n }
    }

    // MARK: gestes

    /// « Copié » dans la ligne, 1,3 s (un seul réveil, après le clic).
    func marquerCopiee(_ id: UUID, duree: TimeInterval = 1.3) {
        copiee = id
        finCopie?.cancel()
        let item = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { if self?.copiee == id { self?.copiee = nil } } }
        finCopie = item
        DispatchQueue.main.asyncAfter(deadline: .now() + duree, execute: item)
    }
    func basculerDepliee(_ id: UUID) { deplie = deplie == id ? nil : id }

    /// Les touches du champ : Échap efface la recherche, puis rend le clavier ; Entrée colle la première dictée trouvée (comme le panneau).
    func commande(_ c: CommandeChamp) -> Bool {
        switch c {
        case .echap:
            if requete.isEmpty { agir(.dicteesClavier(false)) } else { requete = "" }
        case .entree:
            if let e = miseEnPage().affichees.first { agir(.dicteeColler(e.id)) }
        case .copier:
            if let e = miseEnPage().affichees.first { agir(.dicteeCopier(e.id)) }
        case .haut, .bas, .voirTout, .focus, .ouvrirFenetre:
            return c == .haut || c == .bas
        }
        return true
    }
}

// MARK: - la mise en page (en points, depuis le centre de l'encoche et le haut de l'écran)

/// Les mesures de la carte (maquette) : elles servent au dessin et aux essais (où cliquer).
@MainActor
enum PlanDictees {
    static let policeTexte: CGFloat = 15
    static let colonneHeure: CGFloat = 36
    static let margeGauche: CGFloat = 8, margeDroite: CGFloat = 4, ecart: CGFloat = 8
    /// « Coller » (24 pt de haut) et le chevron (24 × 24), 2 pt entre eux.
    static let hauteurAction: CGFloat = 24
    static var largeurColler: CGFloat { MesureIlot.texte("Coller", 12, .semibold) + 20 }
    static var largeurActions: CGFloat { largeurColler + 2 + 24 }
    /// « ✓ Copié » sans ses marges : la coche (≈ 12 pt), 4 pt, le mot mesuré ; dans une ligne dépliée, il tient à la place de « Coller ».
    static let ecartCopie: CGFloat = 4
    static var largeurCopie: CGFloat { 12 + ecartCopie + MesureIlot.texte("Copié", 12, .semibold) }
    static let liens: [Onglet] = [.journee, .reunions, .mots, .reglages]
    static let noteLiens = "ouvrent la fenêtre"

    static func zone(_ g: GrilleIlot) -> CGRect { g.zoneCarte(.dictees, haut: CGFloat(CarteDictees.marge), bas: CGFloat(CarteDictees.marge)) }
    static func cadreEntete(_ g: GrilleIlot) -> CGRect { let z = zone(g); return CGRect(x: z.minX, y: z.minY, width: z.width, height: CGFloat(CarteDictees.entete)) }
    static func cadreListe(_ g: GrilleIlot) -> CGRect {
        let z = zone(g), haut = CGFloat(CarteDictees.entete + CarteDictees.ecart)
        return CGRect(x: z.minX, y: z.minY + haut, width: z.width, height: max(0, z.height - haut - CGFloat(CarteDictees.pied)))
    }
    static func cadrePied(_ g: GrilleIlot) -> CGRect { let z = zone(g); return CGRect(x: z.minX, y: z.maxY - CGFloat(CarteDictees.pied), width: z.width, height: CGFloat(CarteDictees.pied)) }
    /// Tout le corps de la carte sous la barre (son vide ne range pas l'îlot).
    static func fond(_ g: GrilleIlot) -> CGRect { let w = g.corps(.dictees); return CGRect(x: -w, y: g.barre, width: 2 * w, height: g.hauteur(.dictees) - g.barre) }
    /// La place du texte d'une ligne dépliée (ses actions à droite), depuis la vraie caméra : la largeur de la carte ne dépend que d'elle.
    static func largeurTexte(demiCamera hc: CGFloat) -> CGFloat {
        let corps = hc + CGFloat(GeoIlot.valeurs(.dictees, hauteurBarre: 0)[1])
        let carte = 2 * corps - 2 * GrilleIlot.marge - GrilleIlot.placePoints
        return carte - margeGauche - colonneHeure - ecart - ecart - largeurActions - margeDroite
    }

    // essais : où cliquer
    /// Le cadre d'une ligne à l'écran (nil : hors de la liste visible).
    static func cadreLigne(_ id: UUID, _ m: IlotMoteur) -> CGRect? {
        let l = cadreListe(m.grille)
        guard let e = m.dictees.miseEnPage().elements.first(where: { $0.id == id.uuidString }) else { return nil }
        let r = CGRect(x: l.minX, y: l.minY + CGFloat(e.y - m.dictees.decalage), width: l.width, height: CGFloat(e.h))
        return r.intersects(l) ? r : nil
    }
    static func pointChevron(_ id: UUID, _ m: IlotMoteur) -> CGPoint? {
        cadreLigne(id, m).map { CGPoint(x: $0.maxX - margeDroite - 12, y: m.dictees.deplie == id ? $0.minY + 6 + 10 : $0.midY) }
    }
    static func pointColler(_ id: UUID, _ m: IlotMoteur) -> CGPoint? {
        cadreLigne(id, m).map { CGPoint(x: $0.maxX - margeDroite - 24 - 2 - largeurColler / 2, y: m.dictees.deplie == id ? $0.minY + 6 + 10 : $0.midY) }
    }
    /// Le milieu du champ « Rechercher » et de la pilule « ‹ Centre ».
    static func pointChamp(_ g: GrilleIlot) -> CGPoint { let e = cadreEntete(g); return CGPoint(x: e.minX + largeurRetour + 8 + 80, y: e.midY) }
    static func pointRetour(_ g: GrilleIlot) -> CGPoint { let e = cadreEntete(g); return CGPoint(x: e.minX + largeurRetour / 2, y: e.midY) }
    static var largeurRetour: CGFloat { PiluleCentre.largeur("Centre", retour: true) }
    /// Les liens du pied : leurs largeurs mesurées, 7 pt et un « · » entre eux.
    static func largeurLien(_ o: Onglet) -> CGFloat { MesureIlot.texte(o.rawValue, 12.5, .medium) }
    static var largeurPoint: CGFloat { MesureIlot.texte("\u{00B7}", 12, .regular) }
    static func pointLien(_ o: Onglet, _ g: GrilleIlot) -> CGPoint {
        let p = cadrePied(g)
        var x = p.minX + 8
        for l in liens {
            if l == o { return CGPoint(x: x + largeurLien(l) / 2, y: p.minY + 4 + 15) }
            x += largeurLien(l) + 7 + largeurPoint + 7
        }
        return CGPoint(x: x, y: p.midY)
    }
    /// Tout le pied mesuré : les quatre liens, leurs points, la note à droite (au moins 12 pt avant elle).
    static var largeurPied: CGFloat {
        8 + liens.map(largeurLien).reduce(0, +) + CGFloat(liens.count - 1) * (7 + largeurPoint + 7) + 12 + MesureIlot.texte(noteLiens, 11.5, .medium) + 8
    }
}

// MARK: - les vues

struct DicteesCarte: View {
    @ObservedObject var m: IlotMoteur
    /// Pas observé ici : la carte ne lit rien de `d` ; l'en-tête et la liste observent ce qu'ils dessinent (un survol ou un pas de
    /// défilement ne réévalue que la liste et les lignes qui changent).
    let d: DicteesIlot
    var g: GrilleIlot

    var body: some View {
        let v = VueIlot.dictees
        ZStack(alignment: .topLeading) {
            // un clic dans le vide de la carte ne la range pas (on visait une ligne à quelques points près)
            Color.clear.contentShape(Rectangle()).onTapGesture {}
                .allowsHitTesting(m.courante == v)
                .accessibilityHidden(true)
                .posee(PlanDictees.fond(g))
            EnteteDictees(m: m, d: d).posee(PlanDictees.cadreEntete(g), m.aspect(v, rang: 0), ancre: .topLeading)
            ListeDicteesIlot(m: m, d: d, cadre: PlanDictees.cadreListe(g)).posee(PlanDictees.cadreListe(g), m.aspect(v, rang: 1), ancre: .top)
            PiedDictees(m: m).posee(PlanDictees.cadrePied(g), m.aspect(v, rang: 2), ancre: .top)
        }
        .frame(width: IlotMoteur.largeur, height: IlotMoteur.hauteurMax, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Dictées")
    }
}

/// « ‹ Centre » et le champ « Rechercher ».
struct EnteteDictees: View {
    @ObservedObject var m: IlotMoteur
    let d: DicteesIlot

    var body: some View {
        HStack(spacing: 8) {
            PiluleCentre(titre: "Centre", retour: true, etiquette: "Revenir au Centre") { m.revenir() }
            ChampDicteesIlot(m: m, d: d)
        }
        .frame(height: CGFloat(CarteDictees.entete))
    }
}

/// Le champ « Rechercher » : un dessin tant qu'on n'y tape pas (la fenêtre de l'îlot ne prend pas le clavier) ; un clic dedans donne le
/// clavier à l'îlot et pose un vrai champ de texte (curseur ambre, Échap, Entrée), le temps de taper.
struct ChampDicteesIlot: View {
    @ObservedObject var m: IlotMoteur
    @ObservedObject var d: DicteesIlot
    @State private var survol = false

    var body: some View {
        let actif = d.rechercheActive
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.white.opacity(actif ? 0.7 : 0.5))
            ZStack(alignment: .leading) {
                if actif && !m.statique {
                    ChampRecherche(texte: $d.requete, invite: "Rechercher", taille: 13, jetonFocus: d.jetonFocus, surCommande: d.commande)
                } else {
                    HStack(spacing: 0) {
                        Text(d.requete.isEmpty ? "Rechercher" : d.requete)
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(d.requete.isEmpty ? Color.white.opacity(0.45) : .white)
                            .lineLimit(1).truncationMode(.head)
                        // rendus : le champ actif sans vrai champ de texte, le curseur ambre dessiné
                        if actif { RoundedRectangle(cornerRadius: 1).fill(CouleursIlot.ambre).frame(width: 1.6, height: 15).padding(.leading, 1) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !d.requete.isEmpty {
                Button { d.requete = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.white.opacity(0.45))
                        .frame(width: 20, height: 20).contentShape(Circle())
                }
                .buttonStyle(AppuiIlot(echelle: 0.85))
                .accessibilityLabel("Effacer la recherche")
            }
        }
        .padding(.leading, 10).padding(.trailing, d.requete.isEmpty ? 12 : 5)
        .frame(height: CGFloat(CarteDictees.entete))
        .background(Capsule().fill(Color.white.opacity(actif ? 0.14 : (survol ? 0.13 : 0.1))))
        .overlay { if actif { Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 1.5) } }
        .contentShape(Capsule())
        .onTapGesture { if !d.rechercheActive { m.surAction(.dicteesClavier(true)) } }
        .onHover { survol = $0 }
        .animation(m.reduire || m.statique ? nil : .easeOut(duration: 0.15), value: actif)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rechercher dans les dictées")
        .accessibilityValue(d.requete)
        .accessibilityAddTraits(.isSearchField)
        .accessibilityAction { if !d.rechercheActive { m.surAction(.dicteesClavier(true)) } }
    }
}

/// La liste : les titres des jours et les lignes, posés à leur place (`DicteesIlot.miseEnPage`), décalés du défilement, rognés à la
/// hauteur de la liste. Seuls ceux qu'on voit sont dessinés (l'historique peut garder des milliers de dictées) et reçoivent les clics.
struct ListeDicteesIlot: View {
    @ObservedObject var m: IlotMoteur
    @ObservedObject var d: DicteesIlot
    var cadre: CGRect

    var body: some View {
        let p = d.miseEnPage()
        let h = Double(cadre.height), dec = d.decalage
        ZStack(alignment: .topLeading) {
            if p.affichees.isEmpty {
                Text(p.historiqueVide ? "Aucune dictée pour l\u{2019}instant" : "Aucun résultat")
                    .font(Polices.texte(PlanDictees.policeTexte)).foregroundStyle(Color.white.opacity(0.45))
                    .padding(.leading, PlanDictees.margeGauche + PlanDictees.colonneHeure + PlanDictees.ecart).padding(.top, 14)
                    .frame(width: cadre.width, alignment: .leading)
            }
            ForEach(p.elements.filter { $0.y + $0.h > dec - 1 && $0.y < dec + h + 1 }) { e in
                // une ligne à moitié sous le bord ne prend pas le clic destiné à ce qui est autour ; une dictée dépliée plus haute que la
                // liste le prend sur sa partie visible (`.clipped()` ne rogne que le dessin, pas les clics)
                let z = CarteDictees.partieCliquable(y: e.y, h: e.h, decalage: dec, liste: h)
                element(e)
                    .frame(width: cadre.width, height: CGFloat(e.h), alignment: .leading)
                    .contentShape(Rectangle().path(in: CGRect(x: 0, y: CGFloat(z?.debut ?? 0), width: cadre.width, height: CGFloat((z?.fin ?? 0) - (z?.debut ?? 0)))))
                    .allowsHitTesting(z != nil)
                    .offset(y: CGFloat(e.y - dec))
            }
        }
        .frame(width: cadre.width, height: cadre.height, alignment: .topLeading)
        .clipped()
        // ce qui dépasse en bas (ou en haut, une fois défilé) s'efface en fondu : on voit qu'il y a la suite
        .mask {
            VStack(spacing: 0) {
                LinearGradient(colors: [dec > 0.5 ? .clear : .black, .black], startPoint: .top, endPoint: .bottom).frame(height: 14)
                Color.black
                LinearGradient(colors: [.black, d.defile && dec < p.hauteur - h - 0.5 ? .clear : .black], startPoint: .top, endPoint: .bottom).frame(height: 18)
            }
        }
    }

    @ViewBuilder private func element(_ e: DicteesIlot.Element) -> some View {
        switch e.genre {
        case .jour(let t):
            Text(t).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Color.white.opacity(0.42))
                .lineLimit(1)
                .padding(.leading, PlanDictees.margeGauche + PlanDictees.colonneHeure + PlanDictees.ecart).padding(.top, 5)
                .frame(maxHeight: .infinity, alignment: .topLeading)
                .accessibilityAddTraits(.isHeader)
        case .ligne(let x):
            // une ligne ne reçoit que SON état : un survol qui passe d'une ligne à l'autre ne réévalue que ces deux-là, un pas de défilement
            // seulement celles qui entrent (12/11 : toutes les lignes observaient la carte, chaque pas les redessinait toutes, deux fois)
            LigneDicteeIlot(e: x, survol: d.survol == x.id, deplie: d.deplie == x.id, copie: d.copiee == x.id, requete: d.requete,
                            animer: !(m.reduire || m.statique), m: m, d: d)
                .equatable()
        }
    }
}

/// Une dictée : l'heure, le texte (les mots cherchés en ambre), l'app à droite. Au survol : « Coller » et le chevron (à la place de l'app) ;
/// un clic copie (« Copié » en vert) ; dépliée, le texte entier.
struct LigneDicteeIlot: View, Equatable {
    let e: EntreeHistorique
    let survol: Bool, deplie: Bool, copie: Bool
    /// Les mots cherchés (surlignés en ambre).
    let requete: String
    let animer: Bool
    /// Pour les gestes seulement (copier, coller, déplier, le survol) : ni le moteur ni la carte ne sont observés ici, la liste passe l'état.
    let m: IlotMoteur, d: DicteesIlot

    nonisolated static func == (a: Self, b: Self) -> Bool {
        a.e == b.e && a.survol == b.survol && a.deplie == b.deplie && a.copie == b.copie && a.requete == b.requete && a.animer == b.animer
            && a.m === b.m && a.d === b.d
    }

    private static let formatHeure: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.dateFormat = "HH:mm"; return f
    }()

    var body: some View {
        let dep = deplie
        let actions = dep || survol
        HStack(alignment: dep ? .top : .center, spacing: PlanDictees.ecart) {
            Text(Self.formatHeure.string(from: e.date))
                .font(.system(size: 12, weight: .medium).monospacedDigit()).foregroundStyle(Color.white.opacity(0.42))
                .frame(width: PlanDictees.colonneHeure, alignment: .leading)
                .padding(.top, dep ? 3 : 0)
            Text(Self.texte(e.texte, requete: requete))
                .font(Polices.texte(PlanDictees.policeTexte))
                .foregroundStyle(actions ? Color.white : Color.white.opacity(0.78))
                .lineLimit(dep ? nil : 1)
                .lineSpacing(dep ? Self.interligne : 0)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: dep)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 4) {
                // repliée : « Copié » à côté de « Coller » (maquette, étape 12) ; dépliée, il prend la place de « Coller », à la même largeur :
                // la place du texte ne change pas (sa hauteur a été mesurée pour elle ; plus étroit, il déborderait de la ligne)
                if copie && !dep { MarqueCopie().transition(.opacity) }
                if actions {
                    HStack(spacing: 2) {
                        if copie && dep {
                            MarqueCopie(largeur: PlanDictees.largeurColler).transition(.opacity)
                        } else {
                            BoutonColler { m.surAction(.dicteeColler(e.id)) }
                                .accessibilityLabel("Coller dans \(e.appNom ?? "l\u{2019}app précédente")")
                        }
                        BoutonChevron(haut: dep) { d.basculerDepliee(e.id) }
                            .accessibilityLabel(dep ? "Réduire" : "Lire en entier")
                    }
                } else if !copie {
                    Text(e.insere ? (e.appNom ?? "") : "Non écrite")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Color.white.opacity(0.42))
                        .lineLimit(1).fixedSize()
                        .frame(minWidth: 44, alignment: .trailing).padding(.trailing, 4)
                }
            }
            .frame(minHeight: 20)
            .padding(.top, dep ? -2 : 0)
        }
        .padding(.leading, PlanDictees.margeGauche).padding(.trailing, PlanDictees.margeDroite)
        .padding(.top, dep ? 6 : 0).padding(.bottom, dep ? 7 : 0)
        .frame(maxHeight: .infinity, alignment: dep ? .top : .center)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(survol ? 0.1 : (dep ? 0.07 : 0))))
        .contentShape(Rectangle())
        .onHover { dedans in if dedans { d.survol = e.id } else if d.survol == e.id { d.survol = nil } }
        .onTapGesture { m.surAction(.dicteeCopier(e.id)) }
        // le survol s'allume d'un coup, sans fondu (comme les listes du Mac) : chaque image d'un fondu redessine toute la forme de l'îlot
        // sur le processeur (≈ 10 ms) ; en se promenant sur la liste, les fondus s'enchaînaient et occupaient le fil principal
        .animation(animer ? .easeOut(duration: 0.18) : nil, value: copie)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(Self.formatHeure.string(from: e.date)), \(e.texte)\(e.appNom.map { ", \($0)" } ?? "")")
        .accessibilityHint("Un clic copie la dictée")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Copier") { m.surAction(.dicteeCopier(e.id)) }
        .accessibilityAction(named: "Coller") { m.surAction(.dicteeColler(e.id)) }
        .accessibilityAction(named: dep ? "Réduire" : "Lire en entier") { d.basculerDepliee(e.id) }
    }

    /// L'interligne d'une ligne dépliée : des lignes de 21 pt (maquette), quelle que soit la hauteur naturelle de la police.
    static var interligne: CGFloat {
        let f = Polices.nsTexte(PlanDictees.policeTexte)
        return max(0, CGFloat(CarteDictees.interligne) - ceil(f.ascender - f.descender + f.leading))
    }

    /// Le texte, les mots cherchés en ambre (sans accents ni majuscules, `Surlignage`).
    static func texte(_ s: String, requete: String) -> AttributedString {
        var a = AttributedString(s)
        for r in Surlignage.plages(s, requete: requete) {
            let lo = a.characters.index(a.startIndex, offsetBy: r.lowerBound), hi = a.characters.index(a.startIndex, offsetBy: r.upperBound)
            a[lo ..< hi].foregroundColor = CouleursIlot.ambre
        }
        return a
    }
}

/// « ✓ Copié » en vert, dans sa pastille : à sa largeur (marges 7 et 9 pt), ou à une largeur donnée (celle de « Coller »).
private struct MarqueCopie: View {
    var largeur: CGFloat?
    var body: some View {
        let contenu = HStack(spacing: PlanDictees.ecartCopie) {
            Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
            Text("Copié").font(.system(size: 12, weight: .semibold)).lineLimit(1).fixedSize()
        }
        Group {
            if let largeur { contenu.frame(width: largeur) } else { contenu.padding(.leading, 7).padding(.trailing, 9) }
        }
        .foregroundStyle(Color(hex: 0x5FE08A))
        .frame(height: PlanDictees.hauteurAction)
        .background(Capsule().fill(CouleursIlot.vert.opacity(0.18)))
    }
}

private struct BoutonColler: View {
    var action: () -> Void
    @State private var survol = false
    var body: some View {
        Button(action: action) {
            Text("Coller").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).lineLimit(1).fixedSize()
                .frame(width: PlanDictees.largeurColler, height: PlanDictees.hauteurAction)
                .background(Capsule().fill(Color.white.opacity(survol ? 0.24 : 0.14)))
                .contentShape(Capsule())
        }
        .buttonStyle(AppuiIlot(echelle: 0.92))
        .onHover { survol = $0 }
    }
}

private struct BoutonChevron: View {
    var haut: Bool
    var action: () -> Void
    @State private var survol = false
    var body: some View {
        Button(action: action) {
            Image(systemName: haut ? "chevron.up" : "chevron.down").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.white.opacity(survol ? 0.12 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(AppuiIlot(echelle: 0.88))
        .onHover { survol = $0 }
    }
}

/// Le pied : un filet, puis « Journée · Réunions · Mots · Réglages » (la fenêtre principale sur cet onglet) et « ouvrent la fenêtre ».
struct PiedDictees: View {
    @ObservedObject var m: IlotMoteur

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1).padding(.top, 4)
            HStack(spacing: 7) {
                ForEach(Array(PlanDictees.liens.enumerated()), id: \.element) { i, o in
                    if i > 0 { Text("\u{00B7}").font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.25)).accessibilityHidden(true) }
                    LienDictees(titre: o.rawValue) { m.surAction(.ouvrirFenetre(o)) }
                        .accessibilityLabel("Ouvrir la fenêtre de Voxile : \(o.rawValue)")
                }
                Spacer(minLength: 12)
                Text(PlanDictees.noteLiens).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Color.white.opacity(0.32)).lineLimit(1).fixedSize()
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 8)
            .frame(height: 29)
        }
    }
}

private struct LienDictees: View {
    var titre: String
    var action: () -> Void
    @State private var survol = false
    var body: some View {
        Button(action: action) {
            Text(titre).font(.system(size: 12.5, weight: .medium)).foregroundStyle(survol ? Color.white : Color.white.opacity(0.55))
                .lineLimit(1).fixedSize().frame(height: 29).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { survol = $0 }
    }
}
