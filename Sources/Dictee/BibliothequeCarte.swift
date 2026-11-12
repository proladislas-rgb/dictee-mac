import AppKit
import Combine
import SwiftUI
import DicteeCore

// La carte « Bibliothèque » de l'îlot (maquette design/maquettes/ilot-bibliotheque.html, étapes 2 à 5). On y arrive depuis la carte
// Étagère (pilule « Bibliothèque » de son en-tête) ; « ‹ Étagère » y ramène.
// - en-tête : « ‹ Étagère », le champ « Rechercher un fichier » (la fenêtre de l'îlot ne prend le clavier QUE pendant qu'on y tape, comme
//   la carte Dictées, et le rend sitôt la carte quittée, l'îlot rangé ou une dictée commencée), le tri « Récents » / « Anciens » ;
// - les pastilles : Tout, Documents, Images, Captures, AirDrop, Téléchargés ;
// - la liste : les épinglés en haut, puis par date ; une ligne = l'icône (vignette pour les images), le nom (les mots cherchés en ambre),
//   « d'où il vient · date · taille » ; un clic ouvre le fichier, on la glisse vers une app ; au survol, la punaise et « Retirer » ; les
//   petits ronds à gauche choisissent plusieurs fichiers, qu'on glisse ensemble avec « Glisser les 3 » ;
// - le pied : « Rien n'est copié : Verbe garde seulement le chemin » et « En grand » (l'onglet de la fenêtre) ; après « Retirer » :
//   « Retiré d'ici. Le fichier reste dans … » et « Annuler ».

/// L'état de la carte : recherche, filtre, tri, ligne survolée, fichiers choisis, défilement, dernier retrait. La mise en page est
/// calculée une fois et gardée tant que rien ne change.
@MainActor
final class BibliothequeCarte: ObservableObject {
    /// Le modèle (branché par le contrôleur ; les rendus en donnent un en mémoire).
    var modele: BibliothequeModele? {
        didSet {
            cache = nil
            abonnement = modele?.objectWillChange.sink { [weak self] _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.cache = nil; self?.objectWillChange.send(); self?.changement() } }
            }
        }
    }
    private var abonnement: AnyCancellable?
    var maintenant: () -> Date = { Date() }

    @Published var requete = "" { didSet { if requete != oldValue { decalage = 0; survol = nil; retrait = nil; changement() } } }
    @Published var filtre: FiltreBibliotheque = .tout { didSet { if filtre != oldValue { decalage = 0; retrait = nil; changement() } } }
    @Published var recents = true { didSet { if recents != oldValue { decalage = 0; changement() } } }
    @Published var survol: String?
    /// Les fichiers choisis (petits ronds), dans l'ordre du clic.
    @Published var choisis: [String] = [] { didSet { if choisis != oldValue, !choisis.isEmpty { retrait = nil } } }
    @Published var decalage: Double = 0
    /// « Retiré d'ici » au pied, avec « Annuler » (jusqu'au prochain geste).
    @Published var retrait: RetraitBibliotheque?
    @Published var rechercheActive = false
    @Published var jetonFocus = 0
    /// Les fichiers choisis sont en train d'être glissés (la poignée pâlit).
    @Published var tire = false
    var agir: (ActionIlot) -> Void = { _ in }
    var surChangement: () -> Void = {}
    private var muet = false
    private func changement() { if !muet { surChangement() } }

    /// Quelque chose à remettre à zéro (l'îlot rangé).
    var aRemettre: Bool { !requete.isEmpty || filtre != .tout || survol != nil || !choisis.isEmpty || decalage != 0 || retrait != nil || tire }
    /// Remise à zéro quand l'îlot se range (le tri reste).
    func reinitialiser() {
        muet = true
        requete = ""; filtre = .tout; survol = nil; choisis = []; decalage = 0; retrait = nil; tire = false
        muet = false
    }

    // MARK: la liste

    struct Element: Identifiable {
        enum Genre { case groupe(String, epingles: Bool), ligne(EntreeBibliotheque) }
        var id: String
        var genre: Genre
        var y: Double
        var h: Double
    }
    struct MiseEnPage {
        var elements: [Element] = []
        var hauteur: Double = CarteBibliotheque.rien
        var affichees: [EntreeBibliotheque] = []
        /// Rien du tout dans la bibliothèque (pas seulement aucun résultat).
        var vide = true
    }
    private var cache: (cle: String, page: MiseEnPage)?

    func miseEnPage() -> MiseEnPage {
        guard let mo = modele else { return MiseEnPage() }
        let jour = Calendar.current.ordinality(of: .day, in: .era, for: maintenant()) ?? 0
        let cle = "\(mo.version)|\(requete)|\(filtre.rawValue)|\(recents)|\(jour)"
        if let c = cache, c.cle == cle { return c.page }
        var p = MiseEnPage()
        let tout = mo.tout
        p.vide = tout.isEmpty
        var y = 0.0
        for g in BibliothequeIlot.groupes(BibliothequeIlot.filtrer(tout, filtre: filtre, requete: requete), recents: recents, maintenant: maintenant()) {
            p.elements.append(Element(id: "g:" + g.titre, genre: .groupe(g.titre, epingles: g.epingles), y: y, h: CarteBibliotheque.titreGroupe))
            y += CarteBibliotheque.titreGroupe
            for e in g.entrees {
                p.elements.append(Element(id: e.id, genre: .ligne(e), y: y, h: CarteBibliotheque.ligne))
                p.affichees.append(e)
                y += CarteBibliotheque.ligne
            }
        }
        p.hauteur = p.affichees.isEmpty ? CarteBibliotheque.rien : y
        cache = (cle, p)
        return p
    }
    var defile: Bool { miseEnPage().hauteur > CarteBibliotheque.listeMax + 0.5 }
    func defiler(_ dy: Double) {
        let n = CarteBibliotheque.borner(decalage - dy, liste: miseEnPage().hauteur)
        if abs(n - decalage) > 0.01 { decalage = n }
    }

    // MARK: gestes

    func basculerChoix(_ id: String) {
        if let i = choisis.firstIndex(of: id) { choisis.remove(at: i) } else { choisis.append(id) }
    }
    /// Les fichiers choisis, dans l'ordre de la liste (pour les glisser ensemble).
    var fichiersChoisis: [EntreeBibliotheque] {
        let ids = Set(choisis)
        return miseEnPage().affichees.filter { ids.contains($0.id) }
    }
    /// Le glisser des fichiers choisis est fini : déposés quelque part, le choix se vide (les fichiers restent dans la bibliothèque).
    func glisserFini(depose: Bool) {
        tire = false
        if depose { choisis = [] }
    }

    /// Les touches du champ : Échap efface la recherche, puis rend le clavier ; Entrée ouvre le premier fichier trouvé.
    func commande(_ c: CommandeChamp) -> Bool {
        switch c {
        case .echap:
            if requete.isEmpty { agir(.bibliothequeClavier(false)) } else { requete = "" }
        case .entree:
            if let e = miseEnPage().affichees.first { agir(.bibliothequeOuvrir(e.id)) }
        case .haut, .bas: return true
        case .copier, .voirTout, .focus, .ouvrirFenetre: return false
        }
        return true
    }
}

// MARK: - la mise en page (en points, depuis le centre de l'encoche et le haut de l'écran)

@MainActor
enum PlanBibliotheque {
    static let marge: CGFloat = 4
    static let rond: CGFloat = 20
    static let icone: CGFloat = 30
    static let ecart: CGFloat = 8
    /// Le texte d'une ligne (et le titre d'un groupe) commence après le rond et l'icône.
    static var debutTexte: CGFloat { marge + rond + ecart + icone + ecart }
    static var debutTitre: CGFloat { marge + rond + ecart }
    static let hauteurAction: CGFloat = 24
    static var largeurRetirer: CGFloat { MesureIlot.texte("Retirer", 12, .semibold) + 20 }
    static let largeurPunaise: CGFloat = 26
    static let titreRetour = "Étagère"
    static let invite = "Rechercher un fichier"
    static let notePied = "Rien n\u{2019}est copié : Verbe garde seulement le chemin"

    /// La zone du contenu : toute la largeur (pas de points de page sur cette carte, comme l'étagère).
    static func zone(_ g: GrilleIlot) -> CGRect { g.zone(.bibliotheque, haut: CGFloat(CarteBibliotheque.marge), bas: CGFloat(CarteBibliotheque.marge)) }
    static func cadreEntete(_ g: GrilleIlot) -> CGRect { let z = zone(g); return CGRect(x: z.minX, y: z.minY, width: z.width, height: CGFloat(CarteBibliotheque.entete)) }
    static func cadrePuces(_ g: GrilleIlot) -> CGRect {
        let z = zone(g)
        return CGRect(x: z.minX, y: z.minY + CGFloat(CarteBibliotheque.entete + CarteBibliotheque.ecartPuces), width: z.width, height: CGFloat(CarteBibliotheque.puces))
    }
    static func cadreListe(_ g: GrilleIlot) -> CGRect {
        let z = zone(g), haut = CGFloat(CarteBibliotheque.hautListe)
        return CGRect(x: z.minX, y: z.minY + haut, width: z.width, height: max(0, z.height - haut - CGFloat(CarteBibliotheque.pied)))
    }
    static func cadrePied(_ g: GrilleIlot) -> CGRect { let z = zone(g); return CGRect(x: z.minX, y: z.maxY - CGFloat(CarteBibliotheque.pied), width: z.width, height: CGFloat(CarteBibliotheque.pied)) }
    static func fond(_ g: GrilleIlot) -> CGRect { let w = g.corps(.bibliotheque); return CGRect(x: -w, y: g.barre, width: 2 * w, height: g.hauteur(.bibliotheque) - g.barre) }

    // l'en-tête : « ‹ Étagère » (mesuré), le tri (mesuré), le champ prend le reste
    static var largeurRetour: CGFloat { 8 + 10 + 4 + MesureIlot.texte(titreRetour, 12.5, .semibold) + 11 }
    static func titreTri(_ recents: Bool) -> String { recents ? "Récents" : "Anciens" }
    static var largeurTri: CGFloat { 10 + MesureIlot.symbole("arrow.up.arrow.down", 10.5, .bold) + 4 + max(MesureIlot.texte("Récents", 12.5, .semibold), MesureIlot.texte("Anciens", 12.5, .semibold)) + 9 }

    /// Les pastilles, mesurées : la taille de leur texte (12,5 pt, réduite si elles ne tiennent pas toutes sur la largeur de la carte).
    static let espacePuces: CGFloat = 4, margePuce: CGFloat = 8
    static func largeurPuces(_ taille: CGFloat) -> CGFloat {
        FiltreBibliotheque.allCases.map { MesureIlot.texte($0.titre, taille, .semibold) + 2 * margePuce }.reduce(0, +) + CGFloat(FiltreBibliotheque.allCases.count - 1) * espacePuces
    }
    static func taillePuces(_ largeur: CGFloat) -> CGFloat {
        var t: CGFloat = 12.5
        while t > 10.5, largeurPuces(t) > largeur { t -= 0.25 }
        return t
    }
    static func cadrePuce(_ f: FiltreBibliotheque, _ g: GrilleIlot) -> CGRect {
        let p = cadrePuces(g), t = taillePuces(p.width)
        var x = p.minX
        for c in FiltreBibliotheque.allCases {
            let w = MesureIlot.texte(c.titre, t, .semibold) + 2 * margePuce
            if c == f { return CGRect(x: x, y: p.minY, width: w, height: p.height) }
            x += w + espacePuces
        }
        return .zero
    }

    // essais : où cliquer
    static func cadreLigne(_ id: String, _ m: IlotMoteur) -> CGRect? {
        let l = cadreListe(m.grille), b = m.bibliotheque
        guard let e = b.miseEnPage().elements.first(where: { $0.id == id && { if case .ligne = $0.genre { return true }; return false }($0) }) else { return nil }
        let r = CGRect(x: l.minX, y: l.minY + CGFloat(e.y - b.decalage), width: l.width, height: CGFloat(e.h))
        return r.minY >= l.minY - 0.5 && r.maxY <= l.maxY + 0.5 ? r : nil
    }
    static func pointRond(_ id: String, _ m: IlotMoteur) -> CGPoint? { cadreLigne(id, m).map { CGPoint(x: $0.minX + marge + rond / 2, y: $0.midY) } }
    static func pointNom(_ id: String, _ m: IlotMoteur) -> CGPoint? { cadreLigne(id, m).map { CGPoint(x: $0.minX + debutTexte + 40, y: $0.midY) } }
    static func pointRetirer(_ id: String, _ m: IlotMoteur) -> CGPoint? { cadreLigne(id, m).map { CGPoint(x: $0.maxX - 6 - largeurRetirer / 2, y: $0.midY) } }
    static func pointPunaise(_ id: String, _ m: IlotMoteur) -> CGPoint? { cadreLigne(id, m).map { CGPoint(x: $0.maxX - 6 - largeurRetirer - 4 - largeurPunaise / 2, y: $0.midY) } }
    static func pointRetour(_ g: GrilleIlot) -> CGPoint { let e = cadreEntete(g); return CGPoint(x: e.minX + largeurRetour / 2, y: e.minY + 15) }
    static func pointChamp(_ g: GrilleIlot) -> CGPoint { let e = cadreEntete(g); return CGPoint(x: e.minX + largeurRetour + 8 + 70, y: e.midY) }
    static func pointTri(_ g: GrilleIlot) -> CGPoint { let e = cadreEntete(g); return CGPoint(x: e.maxX - largeurTri / 2, y: e.midY) }
    static func pointPuce(_ f: FiltreBibliotheque, _ g: GrilleIlot) -> CGPoint { let c = cadrePuce(f, g); return CGPoint(x: c.midX, y: c.midY) }
    /// Le lien de droite du pied (« En grand », ou « Annuler »).
    static func largeurLienPied(_ titre: String, symbole: Bool) -> CGFloat { MesureIlot.texte(titre, 12, .semibold) + (symbole ? 4 + 13 : 0) }
    static func pointLienPied(_ titre: String, symbole: Bool, _ g: GrilleIlot) -> CGPoint {
        let p = cadrePied(g); return CGPoint(x: p.maxX - 4 - largeurLienPied(titre, symbole: symbole) / 2, y: p.minY + 4 + 15)
    }
    static var largeurPoignee: CGFloat { 7 + 15 + 6 + MesureIlot.texte("Glisser les 00", 12.5, .bold) + 11 }
    static func pointPoignee(_ g: GrilleIlot) -> CGPoint { let p = cadrePied(g); return CGPoint(x: p.minX + 6 + largeurPoignee / 2, y: p.minY + 4 + 15) }
    /// Le pied par défaut, mesuré : le lien, la note, « En grand » (la note se coupe si besoin, jamais « En grand »).
    static var largeurPiedNote: CGFloat { 6 + 14 + 6 + MesureIlot.texte(notePied, 11.5, .medium) + 12 + largeurLienPied("En grand", symbole: true) + 4 }
}

// MARK: - les vues

struct BibliothequeCarteVue: View {
    @ObservedObject var m: IlotMoteur
    @ObservedObject var b: BibliothequeCarte
    var g: GrilleIlot

    var body: some View {
        let v = VueIlot.bibliotheque
        ZStack(alignment: .topLeading) {
            // un clic dans le vide de la carte ne la range pas
            Color.clear.contentShape(Rectangle()).onTapGesture {}
                .allowsHitTesting(m.courante == v)
                .accessibilityHidden(true)
                .posee(PlanBibliotheque.fond(g))
            EnteteBibliotheque(m: m, b: b).posee(PlanBibliotheque.cadreEntete(g), m.aspect(v, rang: 0), ancre: .topLeading)
            PucesBibliotheque(b: b, largeur: PlanBibliotheque.cadrePuces(g).width).posee(PlanBibliotheque.cadrePuces(g), m.aspect(v, rang: 1), ancre: .topLeading)
            ListeBibliothequeIlot(m: m, b: b, cadre: PlanBibliotheque.cadreListe(g)).posee(PlanBibliotheque.cadreListe(g), m.aspect(v, rang: 2), ancre: .top)
            PiedBibliotheque(m: m, b: b).posee(PlanBibliotheque.cadrePied(g), m.aspect(v, rang: 3), ancre: .top)
        }
        .frame(width: IlotMoteur.largeur, height: IlotMoteur.hauteurMax, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Bibliothèque")
    }
}

/// « ‹ Étagère », le champ « Rechercher un fichier », le tri.
struct EnteteBibliotheque: View {
    @ObservedObject var m: IlotMoteur
    @ObservedObject var b: BibliothequeCarte
    @State private var survolTri = false

    var body: some View {
        HStack(spacing: 8) {
            PiluleCentre(titre: PlanBibliotheque.titreRetour, retour: true, etiquette: "Revenir à l\u{2019}étagère") { m.ouvrirEtagere() }
            ChampBibliothequeIlot(m: m, b: b)
            Button { b.recents.toggle() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down").font(.system(size: 10.5, weight: .bold))
                    Text(PlanBibliotheque.titreTri(b.recents)).font(.system(size: 12.5, weight: .semibold)).lineLimit(1).fixedSize()
                }
                .foregroundStyle(.white)
                .padding(.leading, 10).padding(.trailing, 9)
                .frame(width: PlanBibliotheque.largeurTri, height: 26, alignment: .leading)
                .background(Capsule().fill(Color.white.opacity(survolTri ? 0.2 : 0.12)))
                .contentShape(Capsule())
            }
            .buttonStyle(AppuiIlot(echelle: 0.92))
            .onHover { survolTri = $0 }
            .accessibilityLabel("Trier : \(b.recents ? "les plus récents d\u{2019}abord" : "les plus anciens d\u{2019}abord")")
        }
        .frame(height: CGFloat(CarteBibliotheque.entete))
    }
}

/// Le champ « Rechercher un fichier » : un dessin tant qu'on n'y tape pas (la fenêtre de l'îlot ne prend pas le clavier) ; un clic dedans
/// donne le clavier à l'îlot et pose un vrai champ de texte, le temps de taper (même mécanisme que la carte Dictées).
struct ChampBibliothequeIlot: View {
    @ObservedObject var m: IlotMoteur
    @ObservedObject var b: BibliothequeCarte
    @State private var survol = false

    var body: some View {
        let actif = b.rechercheActive
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.white.opacity(actif ? 0.7 : 0.5))
            ZStack(alignment: .leading) {
                if actif && !m.statique {
                    ChampRecherche(texte: $b.requete, invite: PlanBibliotheque.invite, taille: 13, jetonFocus: b.jetonFocus, surCommande: b.commande)
                } else {
                    HStack(spacing: 0) {
                        Text(b.requete.isEmpty ? PlanBibliotheque.invite : b.requete)
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(b.requete.isEmpty ? Color.white.opacity(0.45) : .white)
                            .lineLimit(1).truncationMode(.head)
                        if actif { RoundedRectangle(cornerRadius: 1).fill(CouleursIlot.ambre).frame(width: 1.6, height: 15).padding(.leading, 1) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !b.requete.isEmpty {
                Button { b.requete = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.white.opacity(0.45))
                        .frame(width: 20, height: 20).contentShape(Circle())
                }
                .buttonStyle(AppuiIlot(echelle: 0.85))
                .accessibilityLabel("Effacer la recherche")
            }
        }
        .padding(.leading, 10).padding(.trailing, b.requete.isEmpty ? 12 : 5)
        .frame(height: CGFloat(CarteBibliotheque.entete))
        .background(Capsule().fill(Color.white.opacity(actif ? 0.14 : (survol ? 0.13 : 0.1))))
        .overlay { if actif { Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 1.5) } }
        .contentShape(Capsule())
        .onTapGesture { if !b.rechercheActive { m.surAction(.bibliothequeClavier(true)) } }
        .onHover { survol = $0 }
        .animation(m.reduire || m.statique ? nil : .easeOut(duration: 0.15), value: actif)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rechercher dans la bibliothèque")
        .accessibilityValue(b.requete)
        .accessibilityAddTraits(.isSearchField)
        .accessibilityAction { if !b.rechercheActive { m.surAction(.bibliothequeClavier(true)) } }
    }
}

/// Les pastilles de filtre : Tout, Documents, Images, Captures, AirDrop, Téléchargés (le texte mesuré tient sur la largeur).
struct PucesBibliotheque: View {
    @ObservedObject var b: BibliothequeCarte
    var largeur: CGFloat
    var body: some View {
        let t = PlanBibliotheque.taillePuces(largeur)
        HStack(spacing: PlanBibliotheque.espacePuces) {
            ForEach(FiltreBibliotheque.allCases, id: \.self) { f in
                PuceBibliotheque(titre: f.titre, taille: t, choisie: b.filtre == f) { b.filtre = f }
            }
        }
        .frame(height: CGFloat(CarteBibliotheque.puces))
    }
}

private struct PuceBibliotheque: View {
    var titre: String
    var taille: CGFloat
    var choisie: Bool
    var action: () -> Void
    @State private var survol = false
    var body: some View {
        Button(action: action) {
            Text(titre).font(.system(size: taille, weight: .semibold)).lineLimit(1).fixedSize()
                .foregroundStyle(choisie ? Color.black : Color.white.opacity(0.7))
                .padding(.horizontal, PlanBibliotheque.margePuce)
                .frame(height: CGFloat(CarteBibliotheque.puces))
                .background(Capsule().fill(choisie ? Color.white : Color.white.opacity(survol ? 0.16 : 0.08)))
                .contentShape(Capsule())
        }
        .buttonStyle(AppuiIlot(echelle: 0.92))
        .onHover { survol = $0 }
        .animation(.easeOut(duration: 0.12), value: survol)
        .accessibilityLabel("Filtre : \(titre)")
        .accessibilityAddTraits(choisie ? .isSelected : [])
    }
}

/// La liste : les titres des groupes et les lignes, posés à leur place, décalés du défilement, rognés à la hauteur de la liste. Seuls
/// ceux qu'on voit sont dessinés (la bibliothèque peut garder 500 fichiers et plus).
struct ListeBibliothequeIlot: View {
    @ObservedObject var m: IlotMoteur
    @ObservedObject var b: BibliothequeCarte
    var cadre: CGRect

    var body: some View {
        let p = b.miseEnPage()
        let h = Double(cadre.height), dec = b.decalage
        ZStack(alignment: .topLeading) {
            if p.affichees.isEmpty {
                Text(p.vide ? "Glisse des fichiers sur l\u{2019}encoche : ils restent ici." : "Aucun fichier")
                    .font(Polices.texte(15)).foregroundStyle(Color.white.opacity(0.45))
                    .lineLimit(1)
                    .padding(.leading, PlanBibliotheque.debutTitre).padding(.top, 14)
                    .frame(width: cadre.width, alignment: .leading)
            }
            ForEach(p.elements.filter { $0.y + $0.h > dec - 1 && $0.y < dec + h + 1 }) { e in
                element(e)
                    .frame(width: cadre.width, height: CGFloat(e.h), alignment: .leading)
                    .offset(y: CGFloat(e.y - dec))
                    .allowsHitTesting(e.y - dec >= -1 && e.y + e.h - dec <= h + 1)
            }
        }
        .frame(width: cadre.width, height: cadre.height, alignment: .topLeading)
        .clipped()
        .mask {
            VStack(spacing: 0) {
                LinearGradient(colors: [dec > 0.5 ? .clear : .black, .black], startPoint: .top, endPoint: .bottom).frame(height: 14)
                Color.black
                LinearGradient(colors: [.black, b.defile && dec < p.hauteur - h - 0.5 ? .clear : .black], startPoint: .top, endPoint: .bottom).frame(height: 22)
            }
        }
    }

    @ViewBuilder private func element(_ e: BibliothequeCarte.Element) -> some View {
        switch e.genre {
        case .groupe(let t, let ep):
            HStack(spacing: 4) {
                if ep { Image(systemName: "pin.fill").font(.system(size: 9, weight: .semibold)).rotationEffect(.degrees(35)) }
                Text(t).font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
            }
            .foregroundStyle(Color.white.opacity(0.42))
            .padding(.leading, PlanBibliotheque.debutTitre).padding(.top, 5)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .accessibilityAddTraits(.isHeader)
        case .ligne(let x):
            LigneBibliothequeIlot(e: x, m: m, b: b)
        }
    }
}

/// Une ligne : le rond (choisir), l'icône, le nom et « d'où il vient · date · taille » ; à droite, la punaise d'un épinglé ; au survol, la
/// punaise (épingler / détacher) et « Retirer ».
struct LigneBibliothequeIlot: View {
    let e: EntreeBibliotheque
    @ObservedObject var m: IlotMoteur
    @ObservedObject var b: BibliothequeCarte

    var body: some View {
        let survol = b.survol == e.id, choisi = b.choisis.contains(e.id), choix = !b.choisis.isEmpty
        let actions = survol && !choix
        HStack(spacing: PlanBibliotheque.ecart) {
            Button { b.basculerChoix(e.id) } label: {
                ZStack {
                    Circle().strokeBorder(Color.white.opacity(choisi ? 0 : 0.45), lineWidth: 1.5)
                        .background(Circle().fill(choisi ? CouleursIlot.bleu : .clear))
                        .frame(width: 16, height: 16)
                    if choisi { Image(systemName: "checkmark").font(.system(size: 8.5, weight: .heavy)).foregroundStyle(.white) }
                }
                .frame(width: PlanBibliotheque.rond, height: PlanBibliotheque.rond)
                .contentShape(Circle())
            }
            .buttonStyle(AppuiIlot(echelle: 0.85))
            .opacity(survol || choix ? 1 : 0)
            .accessibilityLabel(choisi ? "Ne plus choisir \(e.nom)" : "Choisir \(e.nom)")
            Image(nsImage: b.modele?.icone(e) ?? SignetsEtagere.iconeDuType(e.chemin)).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                .frame(width: PlanBibliotheque.icone - 2, height: PlanBibliotheque.icone - 2)
                .clipShape(RoundedRectangle(cornerRadius: e.sorte == .image || e.sorte == .capture ? 5 : 0, style: .continuous))
                .frame(width: PlanBibliotheque.icone, height: PlanBibliotheque.icone)
            VStack(alignment: .leading, spacing: 0) {
                Text(LigneDicteeIlot.texte(e.nom, requete: b.requete)).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    .lineLimit(1).truncationMode(.middle)
                HStack(spacing: 4) {
                    Image(systemName: Self.symbole(e.source)).font(.system(size: 9.5, weight: .semibold))
                    Text(BibliothequeIlot.detail(e, maintenant: b.maintenant())).lineLimit(1).truncationMode(.tail)
                }
                .font(.system(size: 11.5, weight: .medium)).foregroundStyle(Color.white.opacity(0.48))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 4) {
                if actions {
                    BoutonPunaise(epinglee: e.epinglee) { m.surAction(.bibliothequeEpingler(e.id)) }
                    BoutonRetirer { m.surAction(.bibliothequeRetirer(e.id)) }
                } else if e.epinglee {
                    Image(systemName: "pin.fill").font(.system(size: 11, weight: .semibold)).rotationEffect(.degrees(35))
                        .foregroundStyle(Color.white.opacity(0.55)).frame(width: 20)
                        .accessibilityLabel("Épinglé")
                }
            }
        }
        .padding(.leading, PlanBibliotheque.marge).padding(.trailing, 6)
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(choisi ? CouleursIlot.bleu.opacity(0.2) : Color.white.opacity(survol ? 0.1 : 0)))
        .contentShape(Rectangle())
        .onHover { dedans in if dedans { b.survol = e.id } else if b.survol == e.id { b.survol = nil } }
        // un clic ouvre le fichier ; pendant un choix, il choisit (ou ne choisit plus)
        .onTapGesture { if choix { b.basculerChoix(e.id) } else { m.surAction(.bibliothequeOuvrir(e.id)) } }
        .glisserFichier(URL(fileURLWithPath: e.chemin), m)
        .animation(m.reduire || m.statique ? nil : .easeOut(duration: 0.12), value: survol)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(e.nom), \(BibliothequeIlot.detail(e, maintenant: b.maintenant()))\(e.epinglee ? ", épinglé" : "")")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Ouvrir") { m.surAction(.bibliothequeOuvrir(e.id)) }
        .accessibilityAction(named: e.epinglee ? "Détacher" : "Épingler") { m.surAction(.bibliothequeEpingler(e.id)) }
        .accessibilityAction(named: "Retirer de la bibliothèque") { m.surAction(.bibliothequeRetirer(e.id)) }
    }

    static func symbole(_ s: SourceBibliotheque) -> String {
        switch s {
        case .etagere: return "tray.full"
        case .telecharges: return "arrow.down.circle"
        case .airdrop: return "dot.radiowaves.left.and.right"
        case .captures: return "camera.viewfinder"
        }
    }
}

private struct BoutonPunaise: View {
    var epinglee: Bool
    var action: () -> Void
    @State private var survol = false
    var body: some View {
        Button(action: action) {
            Image(systemName: epinglee ? "pin.slash.fill" : "pin.fill").font(.system(size: 11, weight: .semibold))
                .foregroundStyle(epinglee ? CouleursIlot.ambre : .white)
                .frame(width: PlanBibliotheque.largeurPunaise, height: PlanBibliotheque.hauteurAction)
                .background(Capsule().fill(epinglee ? CouleursIlot.ambre.opacity(0.25) : Color.white.opacity(survol ? 0.26 : 0.14)))
                .contentShape(Capsule())
        }
        .buttonStyle(AppuiIlot(echelle: 0.88))
        .onHover { survol = $0 }
        .accessibilityLabel(epinglee ? "Détacher" : "Épingler en haut")
    }
}

private struct BoutonRetirer: View {
    var action: () -> Void
    @State private var survol = false
    var body: some View {
        Button(action: action) {
            Text("Retirer").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).lineLimit(1).fixedSize()
                .frame(width: PlanBibliotheque.largeurRetirer, height: PlanBibliotheque.hauteurAction)
                .background(Capsule().fill(Color.white.opacity(survol ? 0.26 : 0.14)))
                .contentShape(Capsule())
        }
        .buttonStyle(AppuiIlot(echelle: 0.92))
        .onHover { survol = $0 }
        .accessibilityLabel("Retirer de la bibliothèque (le fichier reste où il est)")
    }
}

/// Le pied : un filet, puis selon le moment — des fichiers choisis : « Glisser les 3 », « 3 choisis », « Annuler » ; juste après
/// « Retirer » : « Retiré d'ici. Le fichier reste dans … », « Annuler » ; sinon : « Rien n'est copié : Verbe garde seulement le chemin »
/// et « En grand ».
struct PiedBibliotheque: View {
    @ObservedObject var m: IlotMoteur
    @ObservedObject var b: BibliothequeCarte

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1).padding(.top, 4)
            HStack(spacing: 6) {
                if !b.choisis.isEmpty {
                    PoigneeGlisser(m: m, b: b)
                    Text(BibliothequeIlot.choisis(b.choisis.count)).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Color.white.opacity(0.7)).lineLimit(1).fixedSize()
                    Spacer(minLength: 8)
                    LienPied(titre: "Annuler") { b.choisis = [] }.accessibilityLabel("Ne plus rien choisir")
                } else if let r = b.retrait {
                    Image(systemName: "checkmark").font(.system(size: 10.5, weight: .bold)).foregroundStyle(Color(hex: 0x5FE08A))
                    Text(BibliothequeIlot.messageRetrait(dossier: b.modele?.dossier(r.entree) ?? "son dossier"))
                        .font(.system(size: 11.5, weight: .medium)).foregroundStyle(Color.white.opacity(0.62)).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 8)
                    LienPied(titre: "Annuler") { m.surAction(.bibliothequeAnnuler) }.accessibilityLabel("Annuler le retrait")
                } else {
                    Image(systemName: "link").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.white.opacity(0.45)).frame(width: 14)
                    Text(PlanBibliotheque.notePied).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Color.white.opacity(0.45))
                        .lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 8)
                    LienPied(titre: "En grand", symbole: "arrow.up.forward.square") { m.surAction(.ouvrirFenetre(.bibliotheque)) }
                        .accessibilityLabel("Ouvrir la Bibliothèque en grand, dans la fenêtre de Verbe")
                }
            }
            .padding(.leading, 6).padding(.trailing, 4)
            .frame(height: 29)
        }
    }
}

private struct LienPied: View {
    var titre: String
    var symbole: String? = nil
    var action: () -> Void
    @State private var survol = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(titre).font(.system(size: 12, weight: .semibold)).lineLimit(1).fixedSize()
                if let symbole { Image(systemName: symbole).font(.system(size: 11, weight: .semibold)).frame(width: 13) }
            }
            .foregroundStyle(survol ? Color.white : Color.white.opacity(0.62))
            .frame(height: 29).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { survol = $0 }
        .animation(.easeOut(duration: 0.15), value: survol)
    }
}

/// « Glisser les 3 » : on la tire vers une app, les fichiers choisis partent ensemble (un élément par fichier : Mail en fait 3 pièces
/// jointes). Le dessin est en SwiftUI ; le glisser lui-même, par AppKit (SwiftUI ne sait glisser qu'un élément à la fois).
struct PoigneeGlisser: View {
    @ObservedObject var m: IlotMoteur
    @ObservedObject var b: BibliothequeCarte
    var body: some View {
        let n = b.choisis.count
        HStack(spacing: 6) {
            Image(systemName: "square.stack.3d.up.fill").font(.system(size: 12, weight: .semibold)).frame(width: 15)
            Text("Glisser les \(n)").font(.system(size: 12.5, weight: .bold)).lineLimit(1).fixedSize()
        }
        .foregroundStyle(.white)
        .padding(.leading, 7).padding(.trailing, 11)
        .frame(height: 26)
        .background(Capsule().fill(CouleursIlot.bleu.opacity(0.26)))
        .overlay(Capsule().strokeBorder(Color(hex: 0x5EB0FF).opacity(0.6), lineWidth: 1.5))
        .opacity(b.tire ? 0.35 : 1)
        .scaleEffect(b.tire && !m.reduire ? 0.94 : 1)
        .overlay {
            // rendus PNG : pas de vue AppKit (ImageRenderer ne sait pas la dessiner)
            if !m.statique { SourceGlisserFichiers(fichiers: {
                let mo = b.modele
                return b.fichiersChoisis.map { (URL(fileURLWithPath: $0.chemin), mo?.icone($0) ?? SignetsEtagere.iconeDuType($0.chemin)) }
            }, surDebut: { b.tire = true; m.glisserSortantCommence() }, surFin: { b.glisserFini(depose: $0) }) }
        }
        .animation(m.reduire || m.statique ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: b.tire)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Glisser les \(n) fichiers choisis vers une app")
    }
}

/// La source AppKit du glisser de plusieurs fichiers : au premier mouvement du bouton enfoncé (3 pt), une session avec un élément par
/// fichier (son URL ; son icône sous le pointeur, en pile). Vers une autre app : copie (le Finder copie, Mail joint) ; jamais un
/// déplacement : la bibliothèque ne bouge aucun fichier.
struct SourceGlisserFichiers: NSViewRepresentable {
    var fichiers: () -> [(URL, NSImage)]
    var surDebut: () -> Void
    var surFin: (Bool) -> Void
    func makeNSView(context: Context) -> VueGlisserFichiers { let v = VueGlisserFichiers(); maj(v); return v }
    func updateNSView(_ v: VueGlisserFichiers, context: Context) { maj(v) }
    private func maj(_ v: VueGlisserFichiers) { v.fichiers = fichiers; v.surDebut = surDebut; v.surFin = surFin }
}

final class VueGlisserFichiers: NSView, NSDraggingSource {
    var fichiers: () -> [(URL, NSImage)] = { [] }
    var surDebut: () -> Void = {}
    var surFin: (Bool) -> Void = { _ in }
    private var appui: NSEvent?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with e: NSEvent) { appui = e }
    override func mouseUp(with e: NSEvent) { appui = nil }
    override func mouseDragged(with e: NSEvent) {
        guard let a = appui else { return }
        let dx = e.locationInWindow.x - a.locationInWindow.x, dy = e.locationInWindow.y - a.locationInWindow.y
        guard dx * dx + dy * dy >= 9 else { return }
        appui = nil
        let items = Self.elements(fichiers(), dans: bounds)
        guard !items.isEmpty else { return }
        surDebut()
        beginDraggingSession(with: items, event: a, source: self)
    }
    /// Un élément par fichier, les icônes en petite pile sous le pointeur.
    static func elements(_ f: [(URL, NSImage)], dans r: NSRect) -> [NSDraggingItem] {
        f.enumerated().map { i, x in
            let it = NSDraggingItem(pasteboardWriter: x.0 as NSURL)
            let c: CGFloat = 34, d = CGFloat(min(i, 3)) * 6
            it.setDraggingFrame(NSRect(x: r.midX - c / 2 + d, y: r.midY - c / 2 - d, width: c, height: c), contents: x.1)
            return it
        }
    }
    func draggingSession(_ s: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }
    func draggingSession(_ s: NSDraggingSession, endedAt p: NSPoint, operation: NSDragOperation) { surFin(operation != []) }
}

// MARK: - le contrôleur

extension IlotControleur {
    /// Ce que la carte Bibliothèque demande : ouvrir, épingler, retirer, annuler, prendre ou rendre le clavier.
    func agirBibliotheque(_ action: ActionIlot) {
        let b = moteur.bibliotheque
        switch action {
        case .bibliothequeOuvrir(let id):
            guard let e = bibliotheque.entree(id) else { return }
            moteur.fermer()
            // le chemin d'aujourd'hui (le fichier a pu être déplacé), relu hors du fil principal, puis on ouvre
            bibliotheque.rafraichir(force: true) { [weak self] in
                guard let self else { return }
                let x = self.bibliotheque.entree(id) ?? e
                guard FileManager.default.fileExists(atPath: x.chemin) else { return }
                self.ouvrir(URL(fileURLWithPath: x.chemin))
            }
        case .bibliothequeEpingler(let id):
            guard let e = bibliotheque.entree(id) else { return }
            b.retrait = nil
            bibliotheque.epingler(e, !e.epinglee)
        case .bibliothequeRetirer(let id):
            guard let e = bibliotheque.entree(id) else { return }
            b.survol = nil
            b.choisis.removeAll { $0 == id }
            b.retrait = bibliotheque.retirer(e)
        case .bibliothequeAnnuler:
            guard let r = b.retrait else { return }
            bibliotheque.annuler(r)
            b.retrait = nil
        case .bibliothequeClavier(let oui):
            if oui {
                guard moteur.courante == .bibliotheque, !moteur.cache else { return }
                panneau.prendreLeClavier()
                b.rechercheActive = true
                b.jetonFocus += 1
            } else {
                b.rechercheActive = false
                panneau.rendreLeClavier()
            }
        default: break
        }
    }
}
