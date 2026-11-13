import AppKit
import SwiftUI
import DicteeCore

// Le Centre de l'îlot (maquette design/maquettes/ilot-centre.html, validée par Hugues : « une sorte de mini-agent, multitâche ») : tout ce qui
// se règle depuis l'îlot, à la souris, sans raccourci (seule la touche fn reste, pour dicter).
// - une rangée de gros boutons ronds (cinq au plus), chacun avec son nom et son état dessous : Micro, Dictée (Mac / AirPods), Téléchargements,
//   Claude Code ; Rappel et Dernière dictée s'ajoutent par « Modifier » ;
// - deux grandes cases : Minuteur (5 · 10 · 25 min, ou le temps qui reste, pause, arrêt) et Étagère (on y lâche un fichier, on l'en reprend) ;
// - la bande « Noter la réunion » ;
// - « Modifier » (CentreModifier.swift) : retirer, ajouter, ranger en glissant ; « OK » enregistre ;
// - on y arrive sans rien deviner : bouton « Centre » au pied du déplié de toute activité (la vidéo, le minuteur, Claude, un rendez-vous),
//   points de page à droite des cartes, défilement (un geste = une carte) ; l'îlot vide s'ouvre directement dessus ;
// - un clic sur un bouton épingle l'îlot (« Reste ouvert ») : on enchaîne plusieurs réglages, un bandeau attend qu'il se range ; il se
//   range au clic ailleurs ou sur l'îlot dans la barre des menus (un clic dans son vide ne compte pas : on visait un bouton).
// La pile des cartes et le défilement sont dans DicteeCore/CentreIlot.swift ; la navigation dans IlotMoteur.swift.

extension GrilleIlot {
    /// La place des points de page au bord droit des cartes (lecture, Centre, accueil) : le contenu s'arrête 12 pt plus tôt (maquette :
    /// contenu jusqu'à 28 pt du bord, points de 7 à 23 pt du bord).
    static let placePoints: CGFloat = 12
    /// La zone du contenu d'une carte : celle de l'écran, moins la place des points à droite.
    func zoneCarte(_ v: VueIlot, haut: CGFloat = 16, bas: CGFloat = 16) -> CGRect {
        var z = zone(v, haut: haut, bas: bas)
        z.size.width -= Self.placePoints
        return z
    }
}

// MARK: - le Centre

/// Les mesures du Centre (maquette, en points) : elles servent au dessin et aux essais (où cliquer). Les rangées présentes (ronds, cases,
/// bande de la réunion) dépendent de ce que le Centre montre (« Modifier ») : leur place vient de `DispositionCentre.plan`.
@MainActor
enum PlanCentre {
    static let haut = CGFloat(DispositionCentre.haut), entete = CGFloat(DispositionCentre.entete)
    static let rond: CGFloat = 52
    /// Le nom sous un rond : 11,5 pt semi-gras, serré (maquette). S'il ne tient pas dans sa place (cinq ronds : « Téléchargements »), il
    /// est écrit plus petit, mesuré, jusqu'à 9,5 pt : jamais collé à son voisin (la maquette les faisait se toucher).
    static let policeNom: CGFloat = 11.5, interlettreNom: CGFloat = -0.25, policeMin: CGFloat = 9.5
    /// Ce qui sépare deux noms (ou deux états) voisins, au moins.
    static let ecartNoms: CGFloat = 4
    /// Où sont les éléments, depuis le centre de l'encoche (x) et le haut de l'écran (y). `page` : le Centre ou sa page Outils (mêmes
    /// rangées : les ronds, les cases ou le panneau « Garder éveillé », la bande).
    static func zone(_ g: GrilleIlot, _ page: PageCentre = .centre) -> CGRect { g.zoneCarte(page.vue, haut: haut, bas: haut) }
    static func cadreEntete(_ g: GrilleIlot, _ page: PageCentre = .centre) -> CGRect { let z = zone(g, page); return CGRect(x: z.minX, y: z.minY, width: z.width, height: entete) }
    /// Tout le corps du Centre sous la barre (son vide ne range pas l'îlot).
    static func fond(_ g: GrilleIlot, _ page: PageCentre = .centre) -> CGRect {
        let w = g.corps(page.vue)
        return CGRect(x: -w, y: g.barre, width: 2 * w, height: g.hauteur(page.vue) - g.barre)
    }
    /// Une rangée (nil : elle n'est pas montrée).
    static func cadre(_ r: DispositionCentre.Rangee, _ m: IlotMoteur, _ g: GrilleIlot? = nil, page: PageCentre = .centre) -> CGRect? {
        let g = g ?? m.grille
        let p = m.planDe(page)
        guard let y = p.hauts[r] else { return nil }
        let z = zone(g, page)
        let h: Double
        switch r {
        case .etagere: h = DispositionCentre.rangeeEtagere
        case .ronds: h = DispositionCentre.ronds + (m.nomsSurDeuxLignesDe(page) ? DispositionCentre.ligneNom : 0)
        case .cases: h = DispositionCentre.cases
        case .bande: h = DispositionCentre.bande
        case .verre: h = DispositionCentre.rangeeVerre
        }
        return CGRect(x: z.minX, y: g.barre + CGFloat(y), width: z.width, height: CGFloat(h))
    }
    static func cadreRonds(_ m: IlotMoteur, _ g: GrilleIlot? = nil, page: PageCentre = .centre) -> CGRect { cadre(.ronds, m, g, page: page) ?? .zero }
    static func cadreBande(_ m: IlotMoteur, _ g: GrilleIlot? = nil, page: PageCentre = .centre) -> CGRect { cadre(.bande, m, g, page: page) ?? .zero }
    /// Une grande case : seule, elle prend toute la largeur ; à deux, le Minuteur un peu plus large que l'Étagère (maquette
    /// ilot-bibliotheque.html : 1,16 / 0,84, pour « Minuteur · Réveil » et ses quatre heures), 10 pt entre elles.
    static func cadreCase(_ m: IlotMoteur, _ e: ElementCentre, _ g: GrilleIlot? = nil) -> CGRect {
        guard let c = cadre(.cases, m, g) else { return .zero }
        let cs = m.miseEnPageCentre.cases
        guard cs.count > 1, let i = cs.firstIndex(of: e) else { return c }
        let utile = c.width - CGFloat(DispositionCentre.ecart)
        let poids = cs.map { CGFloat(DispositionCentre.poidsCase($0)) }, total = poids.reduce(0, +)
        let l0 = (utile * poids[0] / total).rounded()
        return i == 0 ? CGRect(x: c.minX, y: c.minY, width: l0, height: c.height)
                      : CGRect(x: c.minX + l0 + CGFloat(DispositionCentre.ecart), y: c.minY, width: utile - l0, height: c.height)
    }
    /// La largeur de la rangée des ronds, calculée sans la grille (la hauteur du Centre dépend des noms : pas de boucle).
    static func largeurRonds(_ hc: CGFloat) -> CGFloat {
        2 * (hc + CGFloat(GeoIlot.valeurs(.centre, hauteurBarre: 0, demiCamera: Double(hc))[1])) - 2 * GrilleIlot.marge - GrilleIlot.placePoints
    }
    /// La largeur d'une colonne de la rangée des ronds.
    static func colonne(_ m: IlotMoteur, _ g: GrilleIlot? = nil, page: PageCentre = .centre) -> CGFloat {
        cadreRonds(m, g, page: page).width / CGFloat(max(1, m.rondsDe(page).count))
    }
    /// Le centre du rond d'un élément montré (sur sa page).
    static func centreRond(_ m: IlotMoteur, _ e: ElementCentre, _ g: GrilleIlot? = nil) -> CGPoint {
        let page = e.page
        let r = cadreRonds(m, g, page: page), l = colonne(m, g, page: page), i = CGFloat(m.rondsDe(page).firstIndex(of: e) ?? 0)
        return CGPoint(x: r.minX + l * (i + 0.5), y: r.minY + rond / 2)
    }
    /// Les places des textes d'une ligne sous les ronds (noms, ou états), et la taille de chacun : un texte court laisse de la place à son
    /// voisin long, deux voisins gardent `ecartNoms` entre eux.
    /// `couper` (les noms) : un nom qui devrait descendre sous `seuilDeuxLignes` pour tenir passe sur deux lignes (six ronds :
    /// « Télécharge- / ments » à côté de « Calendrier »), plutôt que d'être écrit trop petit ou serré contre son voisin.
    static func tailles(_ textes: [String], colonne: CGFloat, poids: NSFont.Weight, interlettre: CGFloat = 0, couper: Bool = false) -> [(texte: String, place: CGFloat, taille: CGFloat)] {
        // mesurées une fois pour les mêmes textes à la même place : la grille de l'îlot les redemande à chaque calcul (chaque événement de
        // défilement, chaque dessin), et les mesurer coûtait des dizaines de mesures Core Text à chaque fois (12/11 : un quart du travail
        // d'un pas de molette sur la liste des Dictées)
        let cle = CleTailles(textes: textes, colonne: colonne, poids: poids.rawValue, interlettre: interlettre, couper: couper)
        if let r = memoireTailles[cle] { return r }
        let r = mesurerTailles(textes, colonne: colonne, poids: poids, interlettre: interlettre, couper: couper)
        if memoireTailles.count >= 64 { memoireTailles.removeAll() }
        memoireTailles[cle] = r
        return r
    }
    private struct CleTailles: Hashable { var textes: [String]; var colonne: CGFloat; var poids: CGFloat; var interlettre: CGFloat; var couper: Bool }
    private static var memoireTailles: [CleTailles: [(texte: String, place: CGFloat, taille: CGFloat)]] = [:]
    private static func mesurerTailles(_ textes: [String], colonne: CGFloat, poids: NSFont.Weight, interlettre: CGFloat, couper: Bool) -> [(texte: String, place: CGFloat, taille: CGFloat)] {
        var t = textes
        func l(_ x: [String]) -> [Double] { x.map { Double(largeur($0, policeNom, poids, interlettre: interlettre)) } }
        var p = DispositionCentre.largeursPermises(l(t), colonne: Double(colonne), ecart: Double(ecartNoms))
        if couper {
            // un nom qui ne tient pas en entier avec `ecartConfort` pt de ses voisins passe sur deux lignes, le plus serré d'abord, un à un
            // (« Télécharge- / ments » ; puis son voisin « Claude Code » tient souvent sur une ligne) ; puis les tailles avec `ecartNoms`
            var change = false
            while true {
                let lt = l(t)
                let confort = DispositionCentre.largeursPermises(lt, colonne: Double(colonne), ecart: Double(ecartConfort))
                let serres = t.indices.filter { !t[$0].contains("\n") && confort[$0] < lt[$0] - 0.01 && deuxLignes(t[$0]) != nil }
                guard let i = serres.max(by: { lt[$0] - confort[$0] < lt[$1] - confort[$1] }), let d = deuxLignes(t[i]) else { break }
                t[i] = d; change = true
            }
            // et, comme avant, un nom qui devrait descendre sous `seuilDeuxLignes` pour tenir
            for i in t.indices where !t[i].contains("\n") {
                guard police(t[i], place: CGFloat(p[i]), poids: poids, interlettre: interlettre) < seuilDeuxLignes, let d = deuxLignes(t[i]) else { continue }
                t[i] = d; change = true
            }
            if change { p = DispositionCentre.largeursPermises(l(t), colonne: Double(colonne), ecart: Double(ecartNoms)) }
        }
        return zip(t, p).map { ($0, CGFloat($1), police($0, place: CGFloat($1), poids: poids, interlettre: interlettre)) }
    }
    /// En deçà, un nom passe sur deux lignes (s'il sait se couper).
    static let seuilDeuxLignes: CGFloat = 10.5
    /// L'écart confortable entre deux noms voisins : en deçà (« Téléchargements Dictée » collés à 4 pt, qu'on lit comme un seul nom), le
    /// nom qui sait se couper passe sur deux lignes.
    static let ecartConfort: CGFloat = 8
    /// Un nom coupé en deux lignes : à l'espace le plus proche du milieu (« Claude / Code »), ou au trait d'union de « Télécharge- /
    /// ments » ; nil s'il ne se coupe pas.
    static func deuxLignes(_ s: String) -> String? {
        if s == "Téléchargements" { return "Télécharge-\nments" }
        if s == "Concentration" { return "Concentra-\ntion" }
        let espaces = s.indices.filter { s[$0] == " " }
        guard let milieu = espaces.min(by: { abs(s.distance(from: s.startIndex, to: $0) - s.count / 2) < abs(s.distance(from: s.startIndex, to: $1) - s.count / 2) }) else { return nil }
        var r = s; r.replaceSubrange(milieu...milieu, with: "\n"); return r
    }
    /// La largeur d'un texte d'une ou deux lignes (la plus longue).
    static func largeur(_ texte: String, _ taille: CGFloat, _ poids: NSFont.Weight, interlettre: CGFloat = 0) -> CGFloat {
        texte.split(separator: "\n").map { MesureIlot.texte(String($0), taille, poids, interlettre: interlettre) }.max() ?? 0
    }
    /// Le cadre d'un élément montré sur sa page (nil : il n'y est pas) : la colonne de son rond, sa case, sa bande, ou la rangée des
    /// fichiers de l'étagère en haut du Centre.
    static func cadreElement(_ m: IlotMoteur, _ e: ElementCentre, _ g: GrilleIlot? = nil, page: PageCentre) -> CGRect? {
        let g = g ?? m.grille
        guard e.page == page else { return nil }
        let rs = m.rondsDe(page)
        if let i = rs.firstIndex(of: e) {
            let r = cadreRonds(m, g, page: page), l = colonne(m, g, page: page)
            return CGRect(x: r.minX + l * CGFloat(i), y: r.minY, width: l, height: r.height)
        }
        if page == .centre {
            let mp = m.miseEnPageCentre
            if mp.cases.contains(e) { return cadreCase(m, e, g) }
            if e == .etagere, mp.etagereEnHaut { return cadre(.etagere, m, g) }
            if e == .reunion, mp.bande { return cadreBande(m, g) }
        } else if e == .noteRapide, m.dispositionOutils.bande {
            return cadreBande(m, g, page: .outils)
        }
        return nil
    }
    /// La bulle d'aide (« Te prévient quand un fichier arrive ») : 11,5 pt, une ligne de 21 pt, 9 pt de marge de chaque côté.
    static let policeAide: CGFloat = 11.5, hauteurAide: CGFloat = 21, margeAide: CGFloat = 9
    /// Où se pose la bulle d'aide d'un élément de cadre `r`, centrée sur lui, jamais hors de la zone du contenu (la forme ne la rogne
    /// pas) : un rond, juste sous son nom et son état (elle effleure le haut de la rangée suivante, son vide) ; une case ou une bande,
    /// juste au-dessus d'elle, dans l'écart qui la sépare des noms des ronds (elle mord de 4 pt sur son propre bord, jamais sur un nom).
    /// Sinon (rien au-dessus, ou rien dessous), de l'autre côté. Elle ne prend aucun clic.
    static func cadreAide(_ texte: String, sur r: CGRect, rond estRond: Bool, _ g: GrilleIlot, page: PageCentre) -> CGRect {
        let z = zone(g, page), f = fond(g, page)
        let w = min(z.width, MesureIlot.texte(texte, policeAide, .medium) + 2 * margeAide)
        let x = min(max(r.midX - w / 2, z.minX), z.maxX - w)
        // le bas du libellé d'un rond : le rond, 7 pt, le nom, l'état (la rangée a 96 pt, le libellé finit vers 88)
        let dessous = (estRond ? r.minY + rond + 37 : r.maxY) + 3
        let dessus = r.minY + 4 - hauteurAide
        let tientDessous = dessous + hauteurAide <= f.maxY - 4, tientDessus = dessus >= f.minY + 4
        let y = estRond ? (tientDessous || !tientDessus ? dessous : dessus) : (tientDessus || !tientDessous ? dessus : dessous)
        return CGRect(x: x, y: y, width: w, height: hauteurAide)
    }

    /// La taille d'un texte sous un rond, mesurée pour tenir dans `place` pt.
    static func police(_ texte: String, place: CGFloat, poids: NSFont.Weight, interlettre: CGFloat = 0) -> CGFloat {
        let l = largeur(texte, policeNom, poids, interlettre: interlettre)
        guard l > place, l > 0 else { return policeNom }
        // la largeur suit la taille (à 0,1 pt près, l'interlettre compris) : on réduit, puis on vérifie
        var t = max(policeMin, (policeNom * place / l * 10).rounded(.down) / 10)
        while t > policeMin, largeur(texte, t, poids, interlettre: interlettre) > place { t -= 0.1 }
        return t
    }
}

extension ElementCentre {
    /// Le nom (sous le rond, dans « Ajouter : »).
    var nom: String {
        switch self {
        case .micro: return "Micro"
        case .dictee: return "Dictée"
        case .telechargements: return "Téléchargements"
        case .calendrier: return "Calendrier"
        case .claude: return "Claude Code"
        case .rappel: return "Rappel"
        case .derniereDictee: return "Dernière dictée"
        case .reunion: return "Réunion"
        case .minuteur: return "Minuteur"
        case .etagere: return "Étagère"
        case .eveil: return "Garder éveillé"
        case .pressePapiers: return "Presse-papiers"
        case .reformuler: return "Reformuler"
        case .notes: return "Notes"
        case .noteRapide: return "Dicter une note"
        case .secondBrain: return SecondCerveauIlot.nomApp
        case .groq: return "Groq"
        case .concentration: return "Concentration"
        }
    }
}

extension PageCentre {
    /// L'écran de l'îlot qui montre cette page.
    var vue: VueIlot { self == .centre ? .centre : .outils }
}

extension IlotMoteur {
    /// Comment le Centre se range maintenant : les fichiers de l'étagère en haut quand elle en garde (pas pendant « Modifier », où l'on
    /// range la disposition telle qu'elle est enregistrée).
    var miseEnPageCentre: DispositionCentre.MiseEnPage {
        disposition.miseEnPage(fichiers: etagereActive && !etagere.isEmpty && !editionCentre)
    }
    /// Un élément peut-il paraître ? Le choix du micro de la dictée n'existe qu'avec des AirPods (un micro Bluetooth) branchés.
    /// Second Brain n'existe que si son fichier d'état existe : aucun vide pour qui n'a pas cette app.
    func disponibleDansLeCentre(_ e: ElementCentre) -> Bool {
        switch e {
        case .dictee: return choixMicro != nil
        case .secondBrain: return secondBrain != nil
        default: return true
        }
    }
    /// Les ronds montrés, dans l'ordre (six au plus).
    var rondsCentre: [ElementCentre] { disposition.ronds(disponible: disponibleDansLeCentre) }
    /// La disposition d'une page (le Centre, ou les Outils) et ses ronds montrés.
    func dispositionDe(_ p: PageCentre) -> DispositionCentre { p == .centre ? disposition : dispositionOutils }
    func rondsDe(_ p: PageCentre) -> [ElementCentre] { dispositionDe(p).ronds(disponible: disponibleDansLeCentre) }
    /// Les noms sous les ronds d'une page, mesurés ensemble (un nom trop long passe sur deux lignes), et leur taille. La colonne est
    /// calculée sans la grille (la hauteur du Centre dépend des noms : pas de boucle) ; le Centre et les Outils ont la même largeur.
    func nomsDe(_ p: PageCentre) -> [(texte: String, place: CGFloat, taille: CGFloat)] {
        let rs = rondsDe(p)
        return PlanCentre.tailles(rs.map(\.nom), colonne: PlanCentre.largeurRonds(demiCamera) / CGFloat(max(1, rs.count)), poids: .semibold,
                                  interlettre: PlanCentre.interlettreNom, couper: true)
    }
    /// Un nom au moins est sur deux lignes : la rangée des ronds s'allonge d'une ligne.
    func nomsSurDeuxLignesDe(_ p: PageCentre) -> Bool { nomsDe(p).contains { $0.texte.contains("\n") } }
    /// Ceux du Centre.
    var nomsCentre: [(texte: String, place: CGFloat, taille: CGFloat)] { nomsDe(.centre) }
    var nomsSurDeuxLignes: Bool { nomsSurDeuxLignesDe(.centre) }
    /// Les rangées d'une page et sa profondeur sous la barre. Sur la page Outils, le panneau « Garder éveillé » prend la place des cases.
    /// Le curseur « Verre » au bas du Centre : seulement quand la Lucarne est en verre (hors de l'encoche).
    var verreDansLeCentre: Bool { lucarne.libre }
    func planDe(_ p: PageCentre) -> (hauts: [DispositionCentre.Rangee: Double], profondeur: Double) {
        let deux = nomsSurDeuxLignesDe(p)
        // le Centre suit sa mise en page du moment (les fichiers de l'étagère en haut, la réunion en case) ; les Outils, leur disposition
        if p == .centre {
            let mp = miseEnPageCentre
            return DispositionCentre.plan(etagere: mp.etagereEnHaut, ronds: !rondsDe(p).isEmpty, cases: !mp.cases.isEmpty, bande: mp.bande, nomsSurDeuxLignes: deux,
                                          verre: verreDansLeCentre)
        }
        return DispositionCentre.plan(ronds: !rondsDe(p).isEmpty, cases: panneauEveilVisible, bande: dispositionDe(p).bande, nomsSurDeuxLignes: deux)
    }
    /// L'état écrit sous un rond (« Coupé », « Allumé », « 3 sur 7 »…).
    func etatCentre(_ e: ElementCentre) -> String {
        switch e {
        case .micro: return microCoupe ? "Coupé" : "Ouvert"
        case .dictee: return choixMicro?.airpods == true ? "AirPods" : "Mac"
        case .telechargements: return telechargementsAttente ? "Un instant\u{2026}" : (telechargementsActifs ? "Allumé" : "Éteint")
        case .calendrier: return calendrierAttente ? "Un instant\u{2026}" : (calendrierActif ? "Allumé" : (calendrierRefuse ? "Accès refusé" : "Éteint"))
        case .claude:
            // « 2 au travail », « Attend » (une session attend une réponse), « Prêt » ; « Brancher » tant que les crochets ne sont pas là
            if !sessionsClaude.isEmpty { return TexteClaude.bouton(sessions: sessionsClaude) }
            if let s = claude { return TexteClaude.bouton(sessions: [s]) }
            return claudeBranche ? "Prêt" : "Brancher"
        case .rappel: return "Dire un rappel"
        case .derniereDictee: return derniereDictee != nil ? "Coller" : "Aucune"
        case .eveil: return eveil.map { $0.etat(a: maintenant()) } ?? "Éteint"
        case .pressePapiers: return copies.isEmpty ? "Vide" : (copies.count == 1 ? "1 récent" : "\(copies.count) récents")
        case .reformuler: return derniereDictee != nil ? "Dernière dictée" : "Texte choisi"
        case .notes: return notes.isEmpty ? "Aucune" : (notes.count == 1 ? "1 note" : "\(notes.count) notes")
        case .secondBrain: return secondBrain?.etat ?? ""
        case .groq: return groq.map { TexteGroq.court($0, a: maintenant()) } ?? "\u{2014}"
        case .concentration: return concentration.occupe ? "Un instant\u{2026}" : concentration.rond.etat
        case .reunion, .minuteur, .etagere, .noteRapide: return ""
        }
    }
    /// Le nom de la première carte, pour le bouton de retour du Centre (« ‹ Vidéo »).
    var nomPremiereCarte: String? {
        guard let p = cartes.first, p != .centre else { return nil }
        switch p {
        case .lectureEtendu: return lecture.genre == .musique ? "Musique" : "Vidéo"
        case .minuteurEtendu: return "Minuteur"
        case .microEtendu: return "Micro"
        case .claudeCarte: return "Claude"
        case .outils: return "Outils"
        case .reunionEtendu: return "Réunion"
        case .concentrationStatut: return "Concentration"
        case .agendaEtendu: return "Rendez-vous"
        case .rappelEtendu, .rappelListe: return "Rappel"
        default: return nil
        }
    }
}

struct CentreVue: View {
    @ObservedObject var m: IlotMoteur
    var g: GrilleIlot
    /// Le Centre, ou sa 2e page « Outils » (mêmes rangées, mêmes gestes, même « Modifier »).
    var page: PageCentre = .centre
    /// Le bouton ou la case qu'on range en le glissant (« Modifier ») : où est le pointeur, et où on l'a pris (depuis le milieu de sa place).
    @State private var glisse: GlisseCentre?
    static let espace = "centre"

    var body: some View {
        let v = page.vue
        ZStack(alignment: .topLeading) {
            // un clic dans le vide du Centre (entre l'en-tête, les ronds, les cases et la bande, dans les marges) ne le range pas : on
            // visait un bouton à quelques points près ; il se range au clic ailleurs. Seulement tant qu'il est là (pas pendant son départ)
            Color.clear.contentShape(Rectangle()).onTapGesture {}
                .allowsHitTesting(m.courante == v)
                .accessibilityHidden(true)
                .posee(PlanCentre.fond(g, page))
            EnteteCentre(m: m, largeur: PlanCentre.cadreEntete(g, page).width, page: page).posee(PlanCentre.cadreEntete(g, page), m.aspect(v, rang: 0), ancre: .topLeading)
            if page == .centre, let r = PlanCentre.cadre(.etagere, m, g) {
                RangeeEtagere(m: m, largeur: r.width).onHover { m.survolAide(.etagere, $0) }.posee(r, m.aspect(v, rang: 1), ancre: .top)
            }
            if !m.rondsDe(page).isEmpty { rondsVivants.posee(PlanCentre.cadreRonds(m, g, page: page), m.aspect(v, rang: 1), ancre: .top) }
            if page == .centre {
                ForEach(Array(m.miseEnPageCentre.cases.enumerated()), id: \.element) { i, e in
                    grandeCase(e, rang: i).posee(PlanCentre.cadreCase(m, e, g), m.aspect(v, rang: 2 + i), ancre: .top)
                        .zIndex(glisse?.element == e ? 1 : 0)
                }
                if m.miseEnPageCentre.bande {
                    BandeReunion(m: m).posee(PlanCentre.cadreBande(m, g), m.aspect(v, rang: 4), ancre: .top)
                }
                if let r = PlanCentre.cadre(.verre, m, g) {
                    CurseurVerreCentre(m: m, largeur: r.width).posee(r, m.aspect(v, rang: 5), ancre: .top)
                }
            } else {
                if m.panneauEveilVisible, let c = PlanCentre.cadre(.cases, m, g, page: .outils) {
                    PanneauEveil(m: m).posee(c, m.aspect(v, rang: 2), ancre: .top)
                }
                if m.dispositionOutils.bande {
                    BandeNoteRapide(m: m).onHover { m.survolAide(.noteRapide, $0) }
                        .posee(PlanCentre.cadreBande(m, g, page: .outils), m.aspect(v, rang: 4), ancre: .top)
                }
            }
            // la bulle d'aide du bouton ou de la case survolés, par-dessus tout, sans prendre aucun clic
            if let e = m.bulleAide, m.courante == v, !m.editionCentre, let r = PlanCentre.cadreElement(m, e, g, page: page) {
                BulleAide(texte: e.aide)
                    .posee(PlanCentre.cadreAide(e.aide, sur: r, rond: e.genre == .rond, g, page: page), ancre: .top, .center)
                    .transition(.opacity)
                    .zIndex(5)
            }
        }
        .animation(m.reduire || m.statique ? nil : .easeOut(duration: 0.12), value: m.bulleAide)
        .frame(width: IlotMoteur.largeur, height: IlotMoteur.hauteurMax, alignment: .topLeading)
        .coordinateSpace(name: Self.espace)
        .animation(m.reduire || m.statique ? nil : .spring(response: 0.32, dampingFraction: 0.82), value: m.dispositionDe(page))
    }

    /// Les ronds ; sur la page Outils, « Encore 52 min » sous « Garder éveillé » se relit à chaque minute (seulement pendant que la page
    /// est à l'écran et que le Mac est gardé éveillé pour un temps donné : rien ne tourne sinon).
    @ViewBuilder private var rondsVivants: some View {
        if page == .outils, !m.statique, let e = m.eveil?.echeance {
            TimelineView(.periodic(from: e.addingTimeInterval(-86_400 * 2), by: 60)) { _ in ronds }
        } else {
            ronds
        }
    }

    private var ronds: some View {
        let rs = m.rondsDe(page)
        let cadre = PlanCentre.cadreRonds(m, g, page: page)
        let l = PlanCentre.colonne(m, g, page: page)
        // les noms et les états, mesurés ensemble : un texte court laisse de la place à son voisin long ; un nom qui devrait devenir trop
        // petit passe sur deux lignes (la rangée s'allonge alors d'une ligne)
        let noms = m.nomsDe(page)
        let etats = PlanCentre.tailles(rs.map(m.etatCentre), colonne: l, poids: .medium)
        let hauteur = CGFloat(DispositionCentre.ronds + (m.nomsSurDeuxLignesDe(page) ? DispositionCentre.ligneNom : 0))
        return HStack(spacing: 0) {
            ForEach(Array(rs.enumerated()), id: \.element) { i, e in
                let milieu = cadre.minX + l * (CGFloat(i) + 0.5)
                bouton(e, colonne: l, rang: i, tailles: (noms[i].taille, etats[i].taille), nomAffiche: noms[i].texte)
                    .frame(width: l, height: hauteur, alignment: .top)
                    .contentShape(Rectangle())
                    .onHover { m.survolAide(e, $0) }
                    .accessibilityHint(e.aide)
                    .offset(x: glisse.flatMap { $0.element == e ? $0.x - $0.prise - milieu : nil } ?? 0)
                    .zIndex(glisse?.element == e ? 1 : 0)
                    .gesture(ranger(e, milieu: milieu) { centre in
                        let cible = min(rs.count - 1, max(0, Int(((centre - cadre.minX) / l).rounded(.down))))
                        m.rangerDansLeCentre(e, versRang: cible, parmi: m.rondsDe(page))
                    }, including: m.editionCentre ? .all : .subviews)
                    // « Modifier » : un clic sur un rond ne fait rien (il ne referme pas l'îlot non plus)
                    .gesture(TapGesture().onEnded {}, including: m.editionCentre ? .all : .subviews)
            }
        }
    }

    /// Ranger en glissant (« Modifier ») : la pièce suit le pointeur ; quand son milieu passe sur une autre place, elle la prend.
    private func ranger(_ e: ElementCentre, milieu: CGFloat, viser: @escaping (CGFloat) -> Void) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(Self.espace))
            .onChanged { v in
                let x = v.location.x - IlotMoteur.largeur / 2
                if glisse?.element != e { glisse = GlisseCentre(element: e, prise: v.startLocation.x - IlotMoteur.largeur / 2 - milieu, x: x) }
                else { glisse?.x = x }
                if let gl = glisse { viser(gl.x - gl.prise) }
            }
            .onEnded { _ in
                if m.reduire || m.statique { glisse = nil } else { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { glisse = nil } }
            }
    }

    @ViewBuilder private func grandeCase(_ e: ElementCentre, rang: Int) -> some View {
        let ed = m.editionCentre
        let cs = m.disposition.cases
        let c = PlanCentre.cadreCase(m, e, g)
        let rangee = PlanCentre.cadre(.cases, m, g) ?? c
        Group {
            switch e {
            case .minuteur: CaseMinuteur(m: m)
            case .reunion: CaseReunion(m: m)
            default: CaseEtagere(m: m)
            }
        }
        .allowsHitTesting(!ed)
        .onHover { m.survolAide(e, $0) }
        .accessibilityHint(e.aide)
        .overlay { if ed { Color.clear.contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous)).onTapGesture {} } }
        .tremblement(ed && (m.statique || !m.reduire), amplitude: 1.4, decale: rang % 2 == 1, fige: m.statique)
        .overlay(alignment: .topLeading) {
            if ed { BadgeRetirer(nom: e.nom) { m.retirerDuCentre(e) }.offset(x: -6, y: -6) }
        }
        .offset(x: glisse.flatMap { $0.element == e ? $0.x - $0.prise - c.midX : nil } ?? 0)
        .gesture(ranger(e, milieu: c.midX) { centre in
            guard cs.count > 1 else { return }
            m.rangerDansLeCentre(e, versRang: centre > rangee.midX ? 1 : 0, parmi: m.disposition.cases)
        }, including: ed ? .all : .subviews)
    }

    /// Un clic sur un bouton : l'îlot reste ouvert, puis l'action (celles de l'îlot, déjà construites).
    private func agir(_ a: ActionIlot) { m.epinglerLeCentre(); m.surAction(a) }

    @ViewBuilder private func bouton(_ e: ElementCentre, colonne l: CGFloat, rang: Int, tailles t: (nom: CGFloat, etat: CGFloat), nomAffiche: String) -> some View {
        let ed = m.editionCentre
        let etat = m.etatCentre(e)
        let fige = m.reduire || m.statique
        let retirer: (() -> Void)? = ed ? { m.retirerDuCentre(e) } : nil
        switch e {
        case .micro:
            let coupe = m.microCoupe
            TuileRonde(nom: e.nom, nomAffiche: nomAffiche, etat: etat, couleurEtat: coupe ? Color(hex: 0xFF6961) : CouleursIlot.encre2,
                       fond: coupe ? CouleursIlot.rouge : nil, colonne: l, tailleNom: t.nom, tailleEtat: t.etat, reduire: fige, edition: ed, rang: rang, statique: m.statique, retirer: retirer,
                       etiquette: coupe ? "Micro coupé : le rouvrir" : "Micro ouvert : le couper") {
                Image(systemName: coupe ? "mic.slash.fill" : "mic.fill").font(.system(size: 21, weight: .semibold)).foregroundStyle(.white)
            } action: { agir(.centreMicro) }
        case .dictee:
            let airpods = m.choixMicro?.airpods ?? false
            TuileRonde(nom: e.nom, nomAffiche: nomAffiche, etat: etat, couleurEtat: CouleursIlot.encre2, fond: nil, colonne: l, tailleNom: t.nom, tailleEtat: t.etat,
                       reduire: fige, edition: ed, rang: rang, statique: m.statique, retirer: retirer,
                       etiquette: airpods ? "La dictée écoute les AirPods : passer au micro du Mac" : "La dictée écoute le micro du Mac : passer aux AirPods") {
                Image(systemName: airpods ? "airpodspro" : "laptopcomputer").font(.system(size: airpods ? 22 : 20, weight: .semibold)).foregroundStyle(.white)
            } action: { agir(.microChoisir(airpods: !airpods)) }
        case .telechargements:
            let on = m.telechargementsActifs, attente = m.telechargementsAttente
            TuileRonde(nom: e.nom, nomAffiche: nomAffiche, etat: etat,
                       couleurEtat: on && !attente ? Color(hex: 0x5EB0FF) : CouleursIlot.encre2,
                       fond: on && !attente ? CouleursIlot.bleu : nil, anneau: attente, colonne: l, tailleNom: t.nom, tailleEtat: t.etat, reduire: fige, edition: ed, rang: rang,
                       statique: m.statique, retirer: retirer,
                       etiquette: attente ? "Téléchargements : macOS demande l\u{2019}accès" : (on ? "Téléchargements allumé : l'éteindre" : "Téléchargements éteint : l'allumer")) {
                Image(systemName: "arrow.down.circle").font(.system(size: 22, weight: .semibold)).foregroundStyle(.white)
            } action: { agir(.centreTelechargements) }
        case .calendrier:
            // éteint : gris ; un clic l'allume (macOS demande l'accès une fois : « Un instant… », un anneau) ; allumé : rouge, comme le
            // calendrier des rendez-vous ; refusé : « Accès refusé », la ligne d'avis mène à Réglages Système
            let on = m.calendrierActif, attente = m.calendrierAttente
            TuileRonde(nom: e.nom, nomAffiche: nomAffiche, etat: etat,
                       couleurEtat: on && !attente ? Color(hex: 0xFF6961) : (m.calendrierRefuse && !attente ? Color(hex: 0xFF6961) : CouleursIlot.encre2),
                       fond: on && !attente ? CouleursIlot.rouge : nil, anneau: attente, colonne: l, tailleNom: t.nom, tailleEtat: t.etat, reduire: fige, edition: ed,
                       rang: rang, statique: m.statique, retirer: retirer,
                       etiquette: attente ? "Calendrier : macOS demande l\u{2019}accès" : (on ? "Calendrier allumé : l'éteindre" : "Calendrier éteint : l'allumer")) {
                GlypheIlot(nom: GlypheIlot.calendrier, couleur: .white, taille: 20).frame(width: 24, height: 24)
            } action: { agir(.centreCalendrier) }
        case .claude:
            let s = m.claude
            let branche = m.claudeBranche || s != nil || !m.sessionsClaude.isEmpty
            let attend = m.sessionsClaude.contains { $0.etat == .attend }
            TuileRonde(nom: e.nom, nomAffiche: nomAffiche, etat: etat, couleurEtat: attend ? Color(hex: 0xFFB340) : (branche ? CouleursIlot.encre2 : Color(hex: 0x5EB0FF)),
                       fond: branche ? CouleursIlot.corail : nil, pointille: !branche, colonne: l, tailleNom: t.nom, tailleEtat: t.etat, reduire: fige, edition: ed, rang: rang,
                       statique: m.statique, retirer: retirer,
                       etiquette: branche ? "Claude Code, \(etat) : ouvrir la carte des sessions" : "Brancher Claude Code") {
                EtoileClaude(couleur: branche ? .white : Color.white.opacity(0.75)).frame(width: 21, height: 21)
            } action: { agir(.centreClaude) }
        case .rappel:
            TuileRonde(nom: e.nom, nomAffiche: nomAffiche, etat: etat, couleurEtat: CouleursIlot.encre2, fond: nil, colonne: l, tailleNom: t.nom, tailleEtat: t.etat, reduire: fige, edition: ed,
                       rang: rang, statique: m.statique, retirer: retirer, etiquette: "Dire un rappel") {
                Image(systemName: "bell.fill").font(.system(size: 20, weight: .semibold)).foregroundStyle(CouleursIlot.jaune)
            } action: { agir(.rappelFormulaire) }
        case .derniereDictee:
            let la = m.derniereDictee != nil
            TuileRonde(nom: e.nom, nomAffiche: nomAffiche, etat: etat, couleurEtat: la ? Color(hex: 0x5EB0FF) : CouleursIlot.encre3, fond: nil, colonne: l, tailleNom: t.nom, tailleEtat: t.etat,
                       reduire: fige, edition: ed, rang: rang, statique: m.statique, retirer: retirer,
                       etiquette: la ? "Coller la dernière dictée" : "Aucune dictée à coller") {
                Image(systemName: "quote.opening").font(.system(size: 19, weight: .bold)).foregroundStyle(.white.opacity(la ? 1 : 0.5))
            } action: { if la { agir(.collerLaDerniereDictee) } }
        case .eveil:
            let on = m.eveil != nil
            TuileRonde(nom: e.nom, nomAffiche: nomAffiche, etat: etat, couleurEtat: on ? Color(hex: 0xFFB340) : CouleursIlot.encre2,
                       fond: on ? CouleursIlot.ambre : (m.panneauEveil ? Color.white.opacity(0.26) : nil), declencheur: on ? "allumé" : "éteint",
                       colonne: l, tailleNom: t.nom, tailleEtat: t.etat, reduire: fige, edition: ed, rang: rang, statique: m.statique, retirer: retirer,
                       etiquette: on ? "Garder éveillé, \(etat) : arrêter" : "Garder le Mac éveillé : choisir combien de temps") {
                Image(systemName: "cup.and.saucer.fill").font(.system(size: 19, weight: .semibold)).foregroundStyle(on ? Color.black : Color.white)
            } action: {
                m.epinglerLeCentre()
                if on { m.surAction(.eveil(nil)) } else { m.panneauEveil.toggle(); m.donneesChangees() }
            }
        case .pressePapiers:
            TuileRonde(nom: e.nom, nomAffiche: nomAffiche, etat: etat, couleurEtat: CouleursIlot.encre2, fond: nil, colonne: l, tailleNom: t.nom, tailleEtat: t.etat,
                       reduire: fige, edition: ed, rang: rang, statique: m.statique, retirer: retirer, etiquette: "Presse-papiers : les cinq dernières copies") {
                Image(systemName: "list.clipboard").font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
            } action: { m.epinglerLeCentre(); m.ouvrirOutil(.outilPressePapiers) }
        case .reformuler:
            TuileRonde(nom: e.nom, nomAffiche: nomAffiche, etat: etat, couleurEtat: CouleursIlot.encre2, fond: nil, colonne: l, tailleNom: t.nom, tailleEtat: t.etat,
                       reduire: fige, edition: ed, rang: rang, statique: m.statique, retirer: retirer, etiquette: "Reformuler la dernière dictée ou le texte choisi") {
                Image(systemName: "pencil.line").font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
            } action: { m.epinglerLeCentre(); m.ouvrirOutil(.outilReformuler) }
        case .notes:
            TuileRonde(nom: e.nom, nomAffiche: nomAffiche, etat: etat, couleurEtat: CouleursIlot.encre2, fond: nil, colonne: l, tailleNom: t.nom, tailleEtat: t.etat,
                       reduire: fige, edition: ed, rang: rang, statique: m.statique, retirer: retirer, etiquette: "Notes rapides") {
                Image(systemName: "note.text").font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
            } action: { m.epinglerLeCentre(); m.ouvrirOutil(.outilNote) }
        case .secondBrain:
            let sb = m.secondBrain
            let neuf = (sb?.nouveautes ?? 0) > 0
            TuileRonde(nom: e.nom, nomAffiche: nomAffiche, etat: etat, couleurEtat: neuf ? Color(hex: 0x5EB0FF) : CouleursIlot.encre2, fond: nil, colonne: l, tailleNom: t.nom, tailleEtat: t.etat,
                       reduire: fige, edition: ed, rang: rang, statique: m.statique, retirer: retirer,
                       etiquette: "\(SecondCerveauIlot.nomApp) : ouvrir la carte" + (sb?.resume.map { ", " + $0 } ?? "")) {
                SigneSecondBrain(taille: 24, point: .white, trait: Color.white.opacity(0.5))
            } action: { m.epinglerLeCentre(); m.ouvrirSecondBrain() }
        case .groq:
            // la jauge : l'anneau = la part utilisée de la limite la plus serrée (vert, ambre sous 15 %, rouge à la limite)
            let u = m.groq
            let niveau = u?.niveau ?? .ok
            TuileRonde(nom: e.nom, nomAffiche: nomAffiche, etat: etat, couleurEtat: JaugeGroq.encre(niveau), fond: nil,
                       declencheur: "\(niveau)", colonne: l, tailleNom: t.nom, tailleEtat: t.etat, reduire: fige, edition: ed, rang: rang,
                       statique: m.statique, retirer: retirer,
                       etiquette: u.map { TexteGroq.ligne($0, a: m.maintenant()) + ". Voir le détail" } ?? "Groq : voir le détail") {
                JaugeGroq(utilise: u?.utilise ?? 0, couleur: JaugeGroq.couleur(niveau))
            } action: { agir(.groqDetail) }
        case .concentration:
            TuileConcentration(m: m, nom: e.nom, nomAffiche: nomAffiche, etat: etat, colonne: l, tailles: t, edition: ed, rang: rang, retirer: retirer)
        case .reunion, .minuteur, .etagere, .noteRapide:
            EmptyView()
        }
    }
}

/// La bulle d'aide d'un bouton ou d'une case du Centre : une ligne sobre, gris foncé sur le noir de l'îlot, qui ne prend aucun clic.
struct BulleAide: View {
    var texte: String
    var body: some View {
        Text(texte).font(.system(size: PlanCentre.policeAide, weight: .medium)).foregroundStyle(Color.white.opacity(0.92))
            .lineLimit(1).fixedSize()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color(hex: 0x3A3A3C)))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.55), radius: 6, y: 2)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Le bouton ou la case qu'on range en glissant.
struct GlisseCentre: Equatable {
    var element: ElementCentre
    /// Où on l'a pris, depuis le milieu de sa place (il ne saute pas sous le pointeur).
    var prise: CGFloat
    /// Le pointeur (x depuis le centre de l'encoche).
    var x: CGFloat
}

/// Un gros bouton rond du Centre (comme le Centre de contrôle de l'iPhone) : le rond de 52 pt, son nom, son état dessous. Le rond prend
/// la couleur de l'état (rouge coupé, bleu allumé, corail Claude) ; « Brancher » : un rond en pointillé ; « Un instant… » : un anneau bleu.
/// « Modifier » : le rond tremble, un « – » le retire, un clic dessus ne fait rien (on le range en le glissant).
struct TuileRonde<Glyphe: View>: View {
    var nom: String
    /// Le nom tel qu'il est écrit (sur deux lignes : « Télécharge-\nments ») ; nil : `nom`.
    var nomAffiche: String? = nil
    var etat: String
    var couleurEtat: Color
    var fond: Color?
    var pointille = false
    var anneau = false
    /// La couleur de l'anneau (bleu : macOS pose sa question ; la couleur du dernier mode de Concentration, qu'un clic relance).
    var couleurAnneau = CouleursIlot.bleu
    /// Ce qui fait « rebondir » le rond (par défaut : son état). « Encore 52 min » change chaque minute : le rond ne rebondit qu'à
    /// l'allumage et à l'arrêt.
    var declencheur: String? = nil
    var colonne: CGFloat
    /// Les tailles du nom et de l'état, mesurées avec les voisins (`PlanCentre.tailles`).
    var tailleNom = PlanCentre.policeNom
    var tailleEtat = PlanCentre.policeNom
    var reduire: Bool
    var edition = false
    var rang = 0
    var statique = false
    var retirer: (() -> Void)?
    var etiquette: String
    @ViewBuilder var glyphe: () -> Glyphe
    var action: () -> Void
    @State private var survol = false

    var body: some View {
        // « Modifier » : plus un bouton (un clic ne fait rien, le glisser du Centre range le rond), seul le « – » répond
        Group {
            if edition {
                contenu
            } else {
                Button(action: action) { contenu }
                    .buttonStyle(AppuiIlot(echelle: 0.94))
                    .onHover { survol = $0 }
                    .animation(.easeOut(duration: 0.15), value: survol)
            }
        }
        .accessibilityElement(children: edition ? .contain : .combine)
        .accessibilityLabel(etiquette)
        .accessibilityValue(etat)
    }

    private var contenu: some View {
        VStack(spacing: 0) {
            ZStack {
                if pointille {
                    Circle().strokeBorder(Color.white.opacity(survol ? 0.6 : 0.4), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3.2]))
                } else {
                    Circle().fill(fond ?? Color.white.opacity(0.14)).brightness(survol && !edition ? 0.08 : 0)
                }
                if anneau { Circle().strokeBorder(couleurAnneau, lineWidth: 2) }
                glyphe()
            }
            .frame(width: PlanCentre.rond, height: PlanCentre.rond)
            .keyframeAnimator(initialValue: 1.0, trigger: declencheur ?? etat) { v, s in v.scaleEffect(reduire ? 1 : s) } keyframes: { _ in
                KeyframeTrack { LinearKeyframe(0.86, duration: 0.09); SpringKeyframe(1.04, duration: 0.14); SpringKeyframe(1, duration: 0.2, spring: Spring(response: 0.3, dampingRatio: 0.7)) }
            }
            .overlay(alignment: .topLeading) {
                if edition, let retirer { BadgeRetirer(nom: nom, action: retirer).offset(x: -5, y: -5) }
            }
            .tremblement(edition && (statique || !reduire), amplitude: 1.4, decale: rang % 2 == 1, fige: statique)
            // le nom et l'état, mesurés : plus petits s'ils ne tiennent pas dans la colonne (jamais tassés contre le voisin)
            Text(nomAffiche ?? nom).font(.system(size: tailleNom, weight: .semibold)).tracking(PlanCentre.interlettreNom)
                .foregroundStyle(.white).lineLimit(2).multilineTextAlignment(.center).lineSpacing(-1).fixedSize()
                .padding(.top, 7)
                .accessibilityLabel(nom)
            Text(etat).font(.system(size: tailleEtat, weight: .medium)).foregroundStyle(couleurEtat)
                .lineLimit(1).fixedSize()
                .contentTransition(.opacity)
                .padding(.top, 1)
        }
        .frame(width: colonne)
        .contentShape(Rectangle())
    }
}

/// Le « – » de « Modifier » (20 pt, gris, cerné de noir comme sur l'iPhone) : retire le bouton ou la case du Centre.
struct BadgeRetirer: View {
    var nom: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "minus").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color(hex: 0x5A5A5F)))
                .background(Circle().fill(Color.black).padding(-2))
                .contentShape(Circle().inset(by: -3))
        }
        .buttonStyle(AppuiIlot(echelle: 0.85))
        .accessibilityLabel("Retirer « \(nom) » du Centre")
    }
}

/// Les pilules de l'en-tête : « ‹ Vidéo », « Modifier » (26 pt, maquette).
struct PiluleCentre: View {
    var titre: String
    var retour = false
    /// Un glyphe avant le titre (les guillemets de « Dictées »).
    var symbole: String? = nil
    /// « Outils › » : un chevron après le mot.
    var suite = false
    /// « OK » de « Modifier » : blanche, texte noir (maquette).
    var plein = false
    var etiquette: String
    var action: () -> Void
    @State private var survol = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if retour { Image(systemName: "chevron.left").font(.system(size: 10.5, weight: .bold)) }
                if let symbole { Image(systemName: symbole).font(.system(size: 10, weight: .bold)) }
                Text(titre).font(.system(size: 12.5, weight: .semibold)).lineLimit(1).fixedSize()
                if suite { Image(systemName: "chevron.right").font(.system(size: 10.5, weight: .bold)) }
            }
            .foregroundStyle(plein ? .black : .white)
            .padding(.leading, retour ? 8 : 11).padding(.trailing, suite ? 9 : 11)
            .frame(height: 26)
            .background(Capsule().fill(plein ? Color.white.opacity(survol ? 0.88 : 1) : Color.white.opacity(survol ? 0.2 : 0.12)))
            .contentShape(Capsule())
        }
        .buttonStyle(AppuiIlot(echelle: 0.92))
        .onHover { survol = $0 }
        .animation(.easeOut(duration: 0.12), value: survol)
        .accessibilityLabel(etiquette)
    }
}

/// Le fond d'une grande case du Centre (20 pt de rayon) ; un clic dans son vide ne referme pas l'îlot (on visait la case).
private struct FondCase: View {
    var plein: Bool
    var pointille = false
    var eclaire = false
    var body: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(eclaire ? CouleursIlot.bleu.opacity(0.22) : Color.white.opacity(plein ? 0.1 : 0))
            .overlay {
                if pointille || eclaire {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(eclaire ? 0.9 : 0.3), style: StrokeStyle(lineWidth: 1.5, dash: eclaire ? [] : [5, 4]))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .onTapGesture {}
    }
}

/// « Noter la réunion » en grande case, à côté du Minuteur, quand les fichiers de l'étagère prennent le haut du Centre (maquette
/// ilot-etagere-rapide.html, étape 6) : le point rouge, le titre, ce que ça fait. Pendant une réunion, comme la bande (BandeReunion) :
/// « Réunion en cours », le temps, et un clic ramène à la carte de la réunion (jamais une deuxième réunion).
struct CaseReunion: View {
    @ObservedObject var m: IlotMoteur
    @State private var survol = false
    var body: some View {
        let r = m.reunion
        Button {
            if r != nil, m.cartes.contains(.reunionEtendu) { m.allerA(.reunionEtendu) } else { m.epinglerLeCentre(); m.surAction(.centreReunion) }
        } label: {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(r != nil ? CouleursIlot.rouge.opacity(survol ? 0.3 : 0.24) : Color.white.opacity(survol ? 0.14 : 0.1))
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 7) {
                        Group {
                            if let r {
                                Circle().strokeBorder(CouleursIlot.rouge, lineWidth: 1.8)
                                    .overlay(PointReunion(enPause: r.enPause, animer: !m.reduire && !m.statique, cote: 10))
                            } else {
                                Circle().strokeBorder(CouleursIlot.rouge, lineWidth: 1.8).overlay(Circle().fill(CouleursIlot.rouge).padding(4.2))
                            }
                        }
                        .frame(width: 16, height: 16).frame(width: 18, height: 17)
                        Text(r == nil ? BandeReunion.titre : BandeReunion.titreEnCours).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    }
                    .frame(height: 17)
                    if r != nil {
                        HStack(spacing: 0) {
                            ChronoReunion(m: m, taille: 12).fixedSize()
                            Text(BandeReunion.suiteEnCours).font(.system(size: 12, weight: .medium)).foregroundStyle(Color(hex: 0xFF8A82)).lineLimit(1)
                        }
                    } else {
                        Text(BandeReunion.sousTitre).font(.system(size: 12, weight: .medium)).foregroundStyle(Color.white.opacity(0.5))
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 11)
            }
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(AppuiIlot(echelle: 0.97))
        .onHover { survol = $0 }
        .accessibilityLabel(r == nil ? "Noter la réunion : Voxile écrit tout ce qui se dit" : "Réunion en cours : voir le direct")
    }
}

/// La case Minuteur : deux onglets (maquette ilot-bibliotheque.html, étape 7), « Minuteur · Réveil ».
/// - Minuteur : 5 · 10 · 25 min ; un minuteur qui tourne montre son temps, pause (ou reprise) et arrêt ;
/// - Réveil : 7:00 · 8:00 · 9:00 · Autre… ; l'heure choisie en ambre, « demain » en haut à droite ; un clic sur l'heure choisie l'annule ;
///   « Autre… » : − et + (15 min), puis « OK » (pas de clavier dans l'îlot).
struct CaseMinuteur: View {
    @ObservedObject var m: IlotMoteur
    /// Les mesures de la case (essais : où cliquer) : 10 pt en haut, le sélecteur (20), 7, la rangée (28), 11 en bas ; 14 de chaque côté.
    static let haut: CGFloat = 10, selecteur: CGFloat = 20, ecart: CGFloat = 7, rangee: CGFloat = 28, cote: CGFloat = 14
    /// Le milieu de la rangée, depuis le haut de la case.
    static var milieuRangee: CGFloat { haut + selecteur + ecart + rangee / 2 }

    var body: some View {
        let onglet = m.ongletMontre
        ZStack(alignment: .topLeading) {
            FondCase(plein: true)
            VStack(alignment: .leading, spacing: Self.ecart) {
                HStack(spacing: 0) {
                    HStack(spacing: 7) {
                        GlypheIlot(nom: "timer", couleur: CouleursIlot.ambre, taille: 15).frame(width: 18, height: 17)
                        SelecteurMinuteur(m: m, onglet: onglet)
                    }
                    Spacer(minLength: Self.avantDroite)
                    droite(onglet)
                }
                .frame(height: Self.selecteur)
                Group {
                    if onglet == .reveil { rangeeReveil } else { rangeeMinuteur }
                }
                .frame(height: Self.rangee)
            }
            .padding(.horizontal, Self.cote).padding(.top, Self.haut).padding(.bottom, 11)
        }
        .animation(m.reduire || m.statique ? nil : .easeOut(duration: 0.18), value: onglet)
    }

    /// En haut à droite : le temps du minuteur (onglet Minuteur), ou le jour du réveil (« demain »), s'il tient.
    @ViewBuilder private func droite(_ onglet: OngletMinuteur) -> some View {
        if onglet == .minuteur, let mn = m.minuteur {
            TimelineView(.periodic(from: mn.echeance ?? Date(timeIntervalSinceReferenceDate: 0), by: 1)) { _ in
                Text(FormatIlot.duree(mn.restant(a: m.maintenant()))).font(.system(size: 13.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(CouleursIlot.ambre).lineLimit(1).fixedSize()
                    .accessibilityLabel("Temps restant").accessibilityValue(FormatIlot.duree(mn.restant(a: m.maintenant())))
            }
        } else if onglet == .reveil, let r = m.reveil {
            let j = ReveilIlot.jour(r.sonnerie, maintenant: m.maintenant())
            if Self.jourTient(j, m) {
                Text(j).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Color(hex: 0xFFB340)).lineLimit(1).fixedSize()
                    .accessibilityLabel("Le réveil sonnera \(j)")
            }
        }
    }
    /// Le jour tient-il à droite du sélecteur ? (Mesuré : jamais coupé ni serré ; sinon il n'est pas écrit, l'heure en ambre suffit.)
    static func jourTient(_ j: String, _ m: IlotMoteur) -> Bool {
        let c = PlanCentre.cadreCase(m, .minuteur)
        return 18 + 7 + SelecteurMinuteur.largeur + avantDroite + MesureIlot.texte(j, 11.5, .semibold) <= c.width - 2 * cote
    }
    /// Au moins cet écart entre le sélecteur et ce qui est à droite (le temps, le jour).
    static let avantDroite: CGFloat = 6

    @ViewBuilder private var rangeeMinuteur: some View {
        if let mn = m.minuteur {
            HStack(spacing: 8) {
                BoutonRondIlot(symbole: mn.enPause ? "play.fill" : "pause.fill", couleur: CouleursIlot.ambre, fond: CouleursIlot.ambre.opacity(0.22),
                               etiquette: mn.enPause ? "Reprendre le minuteur" : "Mettre le minuteur en pause", cote: 28) { agir(.minuteurBasculer) }
                BoutonRondIlot(symbole: "xmark", couleur: .white, fond: Color.white.opacity(0.14), etiquette: "Arrêter le minuteur", cote: 28) { agir(.minuteurArreter) }
                Text(mn.enPause ? "En pause" : "fin à " + FormatIlot.heure(mn.heureDeFin(a: m.maintenant())))
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Color.white.opacity(0.5)).lineLimit(1)
            }
        } else {
            HStack(spacing: 6) {
                ForEach([5, 10, 25], id: \.self) { n in CapMinutes(minutes: n) { agir(.minuteurLancerDansLeCentre(minutes: Double(n))) } }
                Text("min").font(.system(size: 12, weight: .medium)).foregroundStyle(Color.white.opacity(0.5)).padding(.leading, 3)
            }
        }
    }

    /// Les heures proposées, l'heure choisie (ambre) et « Autre… » ; ou, après « Autre… », − l'heure + et « OK ».
    @ViewBuilder private var rangeeReveil: some View {
        let r = m.reveil
        if let a = m.reveilAutre {
            HStack(spacing: 6) {
                BoutonRondIlot(symbole: "minus", couleur: .white, fond: Color.white.opacity(0.14), etiquette: "15 minutes plus tôt", cote: 28) {
                    m.epinglerLeCentre(); m.reveilAutre = ReveilIlot.decaler(heure: a.heure, minute: a.minute, de: -1)
                }
                Text(ReveilIlot.texte(a.heure, a.minute)).font(.system(size: 15, weight: .semibold).monospacedDigit()).foregroundStyle(.white)
                    .frame(width: Self.largeurHeure).accessibilityLabel("Heure du réveil").accessibilityValue(ReveilIlot.texte(a.heure, a.minute))
                BoutonRondIlot(symbole: "plus", couleur: .white, fond: Color.white.opacity(0.14), etiquette: "15 minutes plus tard", cote: 28) {
                    m.epinglerLeCentre(); m.reveilAutre = ReveilIlot.decaler(heure: a.heure, minute: a.minute, de: 1)
                }
                CapIlot(titre: "OK", style: .ambre, hauteur: 28, etiquette: "Régler le réveil à \(ReveilIlot.texte(a.heure, a.minute))") {
                    agir(.reveilRegler(heure: a.heure, minute: a.minute, basculer: false))
                }
                .padding(.leading, 2)
            }
        } else {
            HStack(spacing: Self.espaceHeures) {
                ForEach(Array(ReveilIlot.proposees.enumerated()), id: \.offset) { _, h in
                    let choisie = r.map { !$0.repousse && $0.heure == h.heure && $0.minute == h.minute } ?? false
                    CapHeure(titre: ReveilIlot.texte(h.heure, h.minute), choisie: choisie,
                             etiquette: choisie ? "Réveil à \(ReveilIlot.texte(h.heure, h.minute)) : l'annuler" : "Réveil à \(ReveilIlot.texte(h.heure, h.minute))") {
                        agir(.reveilRegler(heure: h.heure, minute: h.minute, basculer: true))
                    }
                }
                // une autre heure choisie (ou repoussée de 10 min) : elle prend la place d'« Autre… », en ambre ; un clic l'annule
                if let r, r.repousse || !ReveilIlot.proposees.contains(where: { $0.heure == r.heure && $0.minute == r.minute }) {
                    CapHeure(titre: r.libelle(), choisie: true, etiquette: "Réveil à \(r.libelle()) : l'annuler") { agir(.reveilAnnuler) }
                } else {
                    CapHeure(titre: Self.autre, choisie: false, etiquette: "Une autre heure") {
                        m.epinglerLeCentre(); m.reveilAutre = r.map { ($0.heure, $0.minute) } ?? (7, 30)
                    }
                }
            }
        }
    }
    static let autre = "Autre\u{2026}"
    static let espaceHeures: CGFloat = 5
    static let largeurHeure: CGFloat = 46
    private func agir(_ a: ActionIlot) { m.epinglerLeCentre(); m.surAction(a) }
}

/// « Minuteur · Réveil » : deux onglets dans une capsule (maquette : 22 pt ; 20 ici, la case garde ses 76 pt).
struct SelecteurMinuteur: View {
    @ObservedObject var m: IlotMoteur
    var onglet: OngletMinuteur
    static let titres: [(OngletMinuteur, String)] = [(.minuteur, "Minuteur"), (.reveil, "Réveil")]
    /// Chaque onglet : 9 pt de chaque côté du texte (12 pt semi-gras) ; 2 pt autour.
    static func largeurOnglet(_ t: String) -> CGFloat { MesureIlot.texte(t, 12, .semibold) + 18 }
    static var largeur: CGFloat { titres.map { largeurOnglet($0.1) }.reduce(0, +) + 4 }
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Self.titres, id: \.1) { o, t in
                Button { m.epinglerLeCentre(); m.ongletMinuteur = o; m.reveilAutre = nil } label: {
                    Text(t).font(.system(size: 12, weight: .semibold)).foregroundStyle(onglet == o ? .white : Color.white.opacity(0.6))
                        .lineLimit(1).fixedSize()
                        .frame(width: Self.largeurOnglet(t), height: 16)
                        .background(Capsule().fill(Color.white.opacity(onglet == o ? 0.22 : 0)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t)
                .accessibilityAddTraits(onglet == o ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.white.opacity(0.1)))
    }
}

/// Une heure du réveil (« 7:00 », « Autre… ») : 28 pt de haut, 44 au moins ; l'heure choisie en ambre (texte noir).
struct CapHeure: View {
    var titre: String
    var choisie: Bool
    var etiquette: String
    var action: () -> Void
    @State private var survol = false
    static func largeur(_ t: String) -> CGFloat { max(40, MesureIlot.texte(t, 13, .semibold, chiffres: true) + 14) }
    var body: some View {
        Button(action: action) {
            Text(titre).font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundStyle(choisie ? Color(hex: 0x231300) : .white)
                .lineLimit(1).fixedSize()
                .frame(width: Self.largeur(titre), height: 28)
                .background(Capsule().fill(choisie ? CouleursIlot.ambre.opacity(survol ? 0.88 : 1) : Color.white.opacity(survol ? 0.22 : 0.14)))
                .contentShape(Capsule())
        }
        .buttonStyle(AppuiIlot(echelle: 0.9))
        .onHover { survol = $0 }
        .accessibilityLabel(etiquette)
        .accessibilityAddTraits(choisie ? .isSelected : [])
    }
}

/// « 5 », « 10 », « 25 » : 44 × 28 pt (maquette).
struct CapMinutes: View {
    var minutes: Int
    var action: () -> Void
    @State private var survol = false
    static let largeur: CGFloat = 44
    var body: some View {
        Button(action: action) {
            Text("\(minutes)").font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundStyle(.white)
                .frame(width: Self.largeur, height: 28)
                .background(Capsule().fill(Color.white.opacity(survol ? 0.22 : 0.14)))
                .contentShape(Capsule())
        }
        .buttonStyle(AppuiIlot(echelle: 0.9))
        .onHover { survol = $0 }
        .accessibilityLabel("Minuteur de \(minutes) minutes")
    }
}

/// La case Étagère : « Glisse un fichier ici » ; les fichiers rangés (glissables vers une app, un clic les ouvre) ; « Lâche ici » quand
/// un fichier glissé passe sur le Centre (c'est le Centre entier qui le reçoit, la case s'éclaire).
struct CaseEtagere: View {
    @ObservedObject var m: IlotMoteur

    var body: some View {
        let f = m.etagere
        let depot = m.depot && m.depotSurvole
        let vide = f.isEmpty || !m.etagereActive
        // l'étagère vide mais la bibliothèque non : le titre ouvre quand même la carte (et sa pilule « Bibliothèque »)
        let ouvrable = !vide || (m.etagereActive && m.bibliothequeNonVide)
        ZStack(alignment: .topLeading) {
            FondCase(plein: !vide && !depot, pointille: vide, eclaire: depot)
            VStack(alignment: .leading, spacing: vide ? 12 : 5) {
                HStack(spacing: 7) {
                    GlypheIlot(nom: vide ? "tray" : "tray.full.fill", couleur: Color(hex: 0x5EB0FF), taille: 14).frame(width: 18, height: 17)
                    Text("Étagère").font(.system(size: 13.5, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    Spacer(minLength: 4)
                    if ouvrable {
                        if !vide {
                            Text("\(f.count)").font(.system(size: 12, weight: .bold).monospacedDigit()).foregroundStyle(.white)
                                .padding(.horizontal, 6).frame(minWidth: 19, minHeight: 19).background(Capsule().fill(Color.white.opacity(0.2)))
                        }
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(CouleursIlot.encre3)
                    }
                }
                .frame(height: 17)
                .contentShape(Rectangle())
                .onTapGesture { if ouvrable { m.epinglerLeCentre(); m.ouvrirEtagere() } }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(ouvrable ? .isButton : [])
                .accessibilityAction { if ouvrable { m.ouvrirEtagere() } }
                if depot {
                    Text("Lâche ici").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white)
                } else if !m.etagereActive {
                    HStack(spacing: 8) {
                        Text("Éteinte").font(.system(size: 12.5, weight: .medium)).foregroundStyle(Color.white.opacity(0.55))
                        CapIlot(titre: "Allumer", hauteur: 24, etiquette: "Allumer l\u{2019}étagère") { m.epinglerLeCentre(); m.surAction(.etagereAllumer) }
                    }
                    .padding(.top, -6)
                } else if f.isEmpty {
                    Text("Glisse un fichier ici").font(.system(size: 12.5, weight: .medium)).foregroundStyle(Color.white.opacity(0.55)).lineLimit(1)
                } else if f.count == 1, let un = f.first {
                    HStack(spacing: 9) {
                        icone(un, cote: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(un.nom).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white).lineLimit(1).truncationMode(.middle)
                            Text(Self.aideGlisser(largeur: PlanCentre.cadreCase(m, .etagere).width - 28 - 28 - 9))
                                .font(.system(size: 11, weight: .medium)).foregroundStyle(Color.white.opacity(0.5)).lineLimit(1)
                        }
                    }
                } else {
                    // les plus récents d'abord, autant que la case en tient (28 pt + 6 d'écart, mesuré : la case est plus étroite à côté du
                    // Minuteur) ; « +3 » pour le reste
                    HStack(spacing: 6) {
                        let montres = Array(f.reversed().prefix(Self.iconesQuiTiennent(f.count, largeur: PlanCentre.cadreCase(m, .etagere).width - 28)))
                        ForEach(montres) { x in icone(x, cote: 28) }
                        if f.count > montres.count {
                            Text("+\(f.count - montres.count)").font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundStyle(Color.white.opacity(0.6))
                        }
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
        }
        .animation(m.reduire || m.statique ? nil : .easeOut(duration: 0.2), value: depot)
    }

    /// Sous le nom du fichier : la phrase la plus longue qui tient (la case est plus étroite à côté du Minuteur), jamais coupée.
    static func aideGlisser(largeur: CGFloat) -> String {
        let phrases = ["glisse-le vers une app", "glisse-le où tu veux", "à glisser"]
        return phrases.first { MesureIlot.texte($0, 11, .medium) <= largeur } ?? phrases[phrases.count - 1]
    }
    /// Combien d'icônes de 28 pt (6 pt d'écart) tiennent dans `largeur`, avec « +N » après elles s'il en reste (4 au plus).
    static func iconesQuiTiennent(_ n: Int, largeur: CGFloat) -> Int {
        var k = min(4, n)
        while k > 1 {
            let reste = n - k
            let l = CGFloat(k) * 28 + CGFloat(k - 1) * 6 + (reste > 0 ? 6 + MesureIlot.texte("+\(reste)", 12, .semibold, chiffres: true) : 0)
            if l <= largeur { return k }
            k -= 1
        }
        return k
    }
    /// L'icône d'un fichier rangé : on la glisse vers une app (le fichier lui-même), un clic l'ouvre.
    private func icone(_ x: FichierEtagere, cote: CGFloat) -> some View {
        Image(nsImage: x.icone).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            .frame(width: cote, height: cote)
            .contentShape(Rectangle())
            .onTapGesture { m.surAction(.etagereOuvrir(x.id)) }
            .glisserFichier(x.url, m)
            .accessibilityLabel(x.nom)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { m.surAction(.etagereOuvrir(x.id)) }
    }
}

// MARK: - le pied des dépliés, les points de page, la bulle « Nouveau »

/// Sous le déplié d'une activité (la vidéo, le minuteur, Claude, un rendez-vous, un rappel) : le bouton « Centre » (avec les petites
/// icônes de ce qu'il contient, le micro en rouge s'il est coupé), le bouton « Dictées » (maquette, étape 2 : l'ancien panneau de la
/// barre des menus) s'il tient, et, tant que le Centre n'a jamais servi et s'il y a la place, l'aide « ou fais défiler ». Il est posé en
/// bas de la forme : 30 pt, 14 pt sous lui (la lecture l'a dans sa géométrie, les autres dépliés l'ajoutent sous leur contenu,
/// `CartesIlot.piedEnPlus`).
struct PiedCarte: View {
    @ObservedObject var m: IlotMoteur
    var g: GrilleIlot
    /// La carte qui le porte.
    var v: VueIlot
    @State private var survol = false

    static func cadre(_ g: GrilleIlot, _ v: VueIlot) -> CGRect {
        let w = g.corps(v)
        return CGRect(x: -w + GrilleIlot.marge, y: g.hauteur(v) - 44, width: 2 * w - 2 * GrilleIlot.marge - GrilleIlot.placePoints, height: 30)
    }
    /// Le milieu du bouton « Centre » (essais : où cliquer) : 50 pt après le bord gauche, sur le mot « Centre ».
    static func pointBouton(_ g: GrilleIlot, _ v: VueIlot = .lectureEtendu) -> CGPoint { let c = cadre(g, v); return CGPoint(x: c.minX + 50, y: c.midY) }
    /// Le milieu du bouton « Dictées » (essais).
    static func pointDictees(_ g: GrilleIlot, _ v: VueIlot = .lectureEtendu) -> CGPoint {
        let c = cadre(g, v); return CGPoint(x: c.minX + largeurBouton + 10 + largeurDictees / 2, y: c.midY)
    }
    static let aide = "ou fais défiler"
    /// Le bouton, mesuré (Core Text, mêmes polices) : 9 + glyphe 15 + 7 + « Centre » + 7 + 1 + trois petites icônes (5 pt entre) + 13.
    static var largeurBouton: CGFloat {
        let icones = ["mic.slash.fill", "tray.fill", "arrow.down.circle"].map { MesureIlot.symbole($0, 10.5) }.reduce(0, +) + 10
        return 9 + 15 + 7 + MesureIlot.texte("Centre", 13, .semibold) + 7 + 1 + icones + 13
    }
    /// Le bouton « Dictées », mesuré : 9 + glyphe 15 + 7 + « Dictées » + 13.
    static var largeurDictees: CGFloat { 9 + 15 + 7 + MesureIlot.texte("Dictées", 13, .semibold) + 13 }
    /// Le bouton « Dictées » tient-il à côté du bouton « Centre » ? (Sinon : la pilule « Dictées » du Centre y mène.)
    static func dicteesTient(_ g: GrilleIlot, _ v: VueIlot) -> Bool { largeurBouton + 10 + largeurDictees <= cadre(g, v).width }
    /// L'aide « ⌄ ou fais défiler », mesurée ; elle ne paraît que si elle tient à côté des boutons (pas sous un Claude étroit).
    static var largeurAide: CGFloat { MesureIlot.symbole("chevron.down", 10) + 6 + MesureIlot.texte(aide, 12, .medium) }
    static func aideTient(_ g: GrilleIlot, _ v: VueIlot) -> Bool {
        largeurBouton + 10 + (dicteesTient(g, v) ? largeurDictees + 10 : 0) + largeurAide <= cadre(g, v).width
    }

    var body: some View {
        HStack(spacing: 10) {
            Button { m.allerA(.centre) } label: {
                HStack(spacing: 7) {
                    Image(systemName: "switch.2").font(.system(size: 13, weight: .semibold)).frame(width: 15)
                    Text("Centre").font(.system(size: 13, weight: .semibold)).lineLimit(1).fixedSize()
                    HStack(spacing: 5) {
                        // le micro coupé se voit encore, en rouge, quand la vidéo s'est dépliée par-dessus
                        Image(systemName: m.microCoupe ? "mic.slash.fill" : "mic.fill").foregroundStyle(m.microCoupe ? CouleursIlot.rouge : Color.white.opacity(0.55))
                        Image(systemName: "tray.fill")
                        Image(systemName: "arrow.down.circle")
                    }
                    .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Color.white.opacity(0.55))
                    .padding(.leading, 1)
                }
                .foregroundStyle(.white)
                .padding(.leading, 9).padding(.trailing, 13)
                .frame(height: 30)
                .background(Capsule().fill(Color.white.opacity(survol ? 0.2 : 0.14)))
                .contentShape(Capsule())
            }
            .buttonStyle(AppuiIlot(echelle: 0.94))
            .onHover { survol = $0 }
            .accessibilityLabel("Ouvrir le Centre : micro, étagère, téléchargements, minuteur")
            .aspectIlot(m.aspect(ExtraIlot.pied, rang: 0), ancre: .leading)
            if Self.dicteesTient(g, v) {
                BoutonPiedDictees { m.allerA(.dictees) }
                    .aspectIlot(m.aspect(ExtraIlot.pied, rang: 1), ancre: .leading)
            }
            HStack(spacing: 6) {
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                Text(Self.aide).font(.system(size: 12, weight: .medium)).lineLimit(1).fixedSize()
            }
            .foregroundStyle(Color.white.opacity(0.45))
            .opacity(m.aideCentre && Self.aideTient(g, v) ? 1 : 0)
            .animation(m.reduire || m.statique ? nil : .easeOut(duration: 0.3), value: m.aideCentre)
            .aspectIlot(m.aspect(ExtraIlot.pied, rang: 2), ancre: .leading)
            .accessibilityHidden(true)
            Spacer(minLength: 0)
        }
        .posee(Self.cadre(g, v))
    }
}

/// Le bouton « Dictées » du pied : les guillemets de Verbe et « Dictées » (30 pt, comme « Centre »).
struct BoutonPiedDictees: View {
    var action: () -> Void
    @State private var survol = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: "quote.opening").font(.system(size: 12, weight: .bold)).frame(width: 15)
                Text("Dictées").font(.system(size: 13, weight: .semibold)).lineLimit(1).fixedSize()
            }
            .foregroundStyle(.white)
            .padding(.leading, 9).padding(.trailing, 13)
            .frame(height: 30)
            .background(Capsule().fill(Color.white.opacity(survol ? 0.2 : 0.14)))
            .contentShape(Capsule())
        }
        .buttonStyle(AppuiIlot(echelle: 0.94))
        .onHover { survol = $0 }
        .accessibilityLabel("Ouvrir les dictées : chercher, copier, coller")
    }
}

/// Les points de page, au bord droit des cartes (lecture, Centre, accueil, Dictées) : un point par carte, celui de la carte montrée en blanc ; un
/// clic sur un point y mène. Ils suivent le milieu du corps pendant que la forme change de hauteur.
struct PointsCartes: View {
    @ObservedObject var m: IlotMoteur
    var g: GrilleIlot
    static let pas: CGFloat = 16, largeur: CGFloat = 22

    /// Le centre du point n°`i` (sur `n`) pour une forme de demi-corps `corps` et de hauteur `hauteur` (essais : où cliquer).
    static func centre(_ i: Int, sur n: Int, corps: CGFloat, hauteur: CGFloat, barre: CGFloat) -> CGPoint {
        let total = CGFloat(n) * pas
        let y0 = barre + (hauteur - barre) / 2 - total / 2
        return CGPoint(x: corps - 15, y: y0 + pas * (CGFloat(i) + 0.5))
    }

    var body: some View {
        let pile = m.cartes
        let corps = CGFloat(m.trace.corps), h = CGFloat(m.geo[2].x)
        let p0 = Self.centre(0, sur: pile.count, corps: corps, hauteur: h, barre: g.barre)
        VStack(spacing: 0) {
            ForEach(Array(pile.enumerated()), id: \.offset) { _, c in
                let on = m.carteCourante == c
                Button { m.allerA(c) } label: {
                    Circle().fill(Color.white.opacity(on ? 1 : 0.3)).frame(width: 7, height: 7).scaleEffect(on ? 1.1 : 1)
                        .frame(width: Self.largeur, height: Self.pas).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Self.nom(c, m))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .animation(m.reduire || m.statique ? nil : .easeOut(duration: 0.2), value: m.carteCourante)
        .posee(CGRect(x: p0.x - Self.largeur / 2, y: p0.y - Self.pas / 2, width: Self.largeur, height: Self.pas * CGFloat(pile.count)),
               m.aspect(ExtraIlot.points), ancre: .center)
    }
    static func nom(_ c: VueIlot, _ m: IlotMoteur) -> String {
        switch c {
        case .centre: return "Le Centre"
        case .outils: return "Les outils"
        case .dictees: return "Les dictées"
        case .accueil: return "Rendez-vous, rappel et dernière dictée"
        default: return m.nomPremiereCarte ?? "Activité"
        }
    }
}

/// La bulle « Nouveau : survole l'îlot », sous l'îlot replié, une seule fois (premier lancement).
struct BulleNouveau: View {
    @ObservedObject var m: IlotMoteur
    var g: GrilleIlot
    static let gras = "Nouveau", suite = "\u{00A0}: survole l\u{2019}îlot"
    /// La largeur du texte (Core Text, mêmes polices) : la forme l'épouse.
    static var largeur: CGFloat { MesureIlot.texte(gras, 14, .bold) + MesureIlot.texte(suite, 14, .medium) }
    var body: some View {
        let l = Self.largeur + 4
        HStack(spacing: 0) {
            Text(Self.gras).font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
            Text(Self.suite).font(.system(size: 14, weight: .medium)).foregroundStyle(Color.white.opacity(0.8))
        }
        .lineLimit(1).fixedSize()
        .posee(CGRect(x: -l / 2, y: g.barre + (CGFloat(GeoIlot.profondeurBulle) - 20) / 2 - 1, width: l, height: 20), m.aspect(ExtraIlot.bulle), ancre: .top, .center)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - les actions du Centre

/// Ce que le Centre lit et écrit des réglages : injectable (les essais n'écrivent jamais les vrais réglages).
struct ReglagesCentre {
    var telechargements: () -> Bool = { Settings.ilotTelechargements }
    var reglerTelechargements: (Bool) -> Void = { Settings.ilotTelechargements = $0 }
    var microChoisi: () -> String? = { Settings.micro }
    var choisirMicro: (String?) -> Void = { Settings.micro = $0 }
    var bulleVue: () -> Bool = { Settings.ilotBulleVue }
    var marquerBulleVue: () -> Void = { Settings.ilotBulleVue = true }
    var centreUtilise: () -> Bool = { Settings.ilotCentreUtilise }
    var marquerCentreUtilise: () -> Void = { Settings.ilotCentreUtilise = true }
    var allumerMicro: () -> Void = { Settings.ilotMicro = true }
    var allumerClaude: () -> Void = { Settings.ilotClaude = true }
    var allumerEtagere: () -> Void = { Settings.ilotEtagere = true }
    /// « Captures d'écran ici » (carte Étagère) : lu au lancement, écrit par l'interrupteur.
    var captures: () -> Bool = { Settings.ilotCapturesEtagere }
    var reglerCaptures: (Bool) -> Void = { Settings.ilotCapturesEtagere = $0 }
    /// Ce que le Centre montre (« Modifier ») : les identifiants, dans l'ordre ; nil = jamais modifié.
    var disposition: () -> [String]? = { Settings.ilotCentreBoutons }
    var enregistrerDisposition: ([String]) -> Void = { Settings.ilotCentreBoutons = $0 }
    /// Second Brain : son bouton est ajouté au Centre une seule fois, quand son fichier d'état apparaît (puis « Modifier » décide).
    var secondBrainPropose: () -> Bool = { Settings.ilotSecondBrainPropose }
    var marquerSecondBrainPropose: () -> Void = { Settings.ilotSecondBrainPropose = true }
    /// Ce que la page Outils montre (« Modifier ») ; nil = jamais modifiée.
    var dispositionOutils: () -> [String]? = { Settings.ilotOutilsBoutons }
    var enregistrerDispositionOutils: ([String]) -> Void = { Settings.ilotOutilsBoutons = $0 }
    /// Le minuteur (Réglages › Îlot) : éteint, un clic sur « 5 », « 10 » ou « 25 » dans le Centre l'allume, puis lance le minuteur.
    var minuteurActif: () -> Bool = { Settings.ilotMinuteur }
    var allumerMinuteur: () -> Void = { Settings.ilotMinuteur = true }
    /// Les rappels (Réglages › Îlot) : éteints, « Lucarne, rappelle-moi… » les rallume (une demande dite en toutes lettres).
    var rappelsActifs: () -> Bool = { Settings.ilotRappels }
    var allumerRappels: () -> Void = { Settings.ilotRappels = true }
    /// L'app Rappels d'Apple : la réponse à « Aussi dans l'app Rappels ? » (nil : jamais répondu), et le refus déjà dit.
    var choixRappelsApple: () -> ChoixRappelsApple? = { Settings.ilotRappelsApple.flatMap(ChoixRappelsApple.init(rawValue:)) }
    var enregistrerChoixRappelsApple: (ChoixRappelsApple) -> Void = { Settings.ilotRappelsApple = $0.rawValue }
    var refusRappelsDit: () -> Bool = { Settings.ilotRappelsAppleRefusDit }
    var marquerRefusRappelsDit: () -> Void = { Settings.ilotRappelsAppleRefusDit = true }
    /// Le calendrier (Réglages › Îlot, ou le rond Calendrier du Centre).
    var calendrier: () -> Bool = { Settings.ilotCalendrier }
    var reglerCalendrier: (Bool) -> Void = { Settings.ilotCalendrier = $0 }
    /// Les nouveautés déjà données une fois à une page rangée, Centre et Outils (`DispositionCentre.relire`).
    var nouveautes: () -> [String] = { Settings.ilotCentreNouveautes }
    var marquerNouveautes: ([String]) -> Void = { Settings.ilotCentreNouveautes = $0 }
}

extension IlotControleur {
    /// Le volet de Réglages Système où l'on rend l'accès à Téléchargements (Confidentialité et sécurité › Fichiers et dossiers).
    static let reglagesFichiers = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")!
    /// Le volet où l'on rend l'accès aux calendriers (Confidentialité et sécurité › Calendriers).
    static let reglagesCalendriers = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!

    /// Les boutons du Centre. Chacun réutilise ce qui existe (micro coupé, téléchargements, crochets de Claude, étagère, réunion) ; l'îlot
    /// reste ouvert (sauf pour aller au Terminal ou noter une réunion). Les autorisations se demandent ici, au premier clic, jamais avant.
    func agirCentre(_ a: ActionIlot) {
        switch a {
        case .centreMicro:
            couperOuRouvrirLeMicro(depuis: "le Centre")
        case .centreTelechargements:
            // allumer : macOS pose sa question à la première lecture du dossier (« Un instant… » jusqu'à la réponse) ; refusé, le bouton
            // revient sur « Éteint » et une ligne mène à Réglages Système
            moteur.avisCentre = nil
            telechargementsDemandesDuCentre = !moteur.telechargementsActifs
            reglerTelechargements(!moteur.telechargementsActifs)
        case .centreAvis:
            if moteur.avisCentre == .telechargementsRefuses { ouvrir(Self.reglagesFichiers) }
            if moteur.avisCentre == .calendrierRefuse { ouvrir(Self.reglagesCalendriers) }
            moteur.avisCentre = nil
        case .centreCalendrier:
            basculerLeCalendrier()
        case .centreClaude:
            // branché (ou des sessions déjà là) : la carte « Claude Code », un bloc par session ; sinon, on branche (les crochets
            // s'écrivent dans ~/.claude/settings.json, l'ancien gardé à côté en .verbe-sauvegarde, comme le bouton des Réglages)
            if moteur.claudeBranche || moteur.claude != nil || !moteur.sessionsClaude.isEmpty { moteur.ouvrirCarteClaude(); return }
            moteur.avisCentre = nil
            do {
                try installationClaude.brancher()
                moteur.claudeBranche = true
                if !claudeSource.actif { reglagesCentre.allumerClaude(); activerClaude(true) }
                NotificationCenter.default.post(name: .verbeIlotReglagesRelus, object: nil)
            } catch let e as InstallationClaude.Echec {
                Log.ecrire("claude : branchement depuis le Centre impossible (\(e.phrase))")
                if case .ecriture = e { moteur.avisCentre = .claudeImpossible(ecriture: true) } else { moteur.avisCentre = .claudeImpossible(ecriture: false) }
            } catch {
                Log.ecrire("claude : branchement depuis le Centre impossible")
                moteur.avisCentre = .claudeImpossible(ecriture: true)
            }
            moteur.donneesChangees()
        case .centreReunion:
            moteur.fermer()
            surNoter(nil)
        case .etagereAllumer:
            reglagesCentre.allumerEtagere()
            activerEtagere(true)
            NotificationCenter.default.post(name: .verbeIlotReglagesRelus, object: nil)
        default: break
        }
    }

    /// Le rond Calendrier (maquette ilot-bibliotheque.html, étape 10). Allumé : un clic l'éteint. Éteint : un clic l'allume ; la première
    /// fois, macOS demande l'accès (« Un instant… » sous le rond, le Centre reste là pendant qu'on répond dans SA fenêtre) ; refusé (tout
    /// de suite ou plus tôt dans Réglages Système) : « Accès refusé » sous le rond, et la ligne d'avis mène à Réglages Système.
    func basculerLeCalendrier() {
        moteur.avisCentre = nil
        if reglagesCentre.calendrier(), statutCalendrier() == .autorise {
            reglagesCentre.reglerCalendrier(false)
            Log.ecrire("calendrier : éteint depuis le Centre")
            NotificationCenter.default.post(name: .verbeIlotReglagesRelus, object: nil)
            appliquerLeCalendrier()
            return
        }
        switch statutCalendrier() {
        case .autorise:
            allumerLeCalendrier()
        case .refuse:
            calendrierRefuse()
        case .nonDemande:
            moteur.calendrierAttente = true
            moteur.donneesChangees()
            Task { @MainActor in
                let ok = await demanderLAccesAuCalendrier()
                moteur.calendrierAttente = false
                if ok { allumerLeCalendrier() } else { calendrierRefuse() }
            }
        }
    }
    private func allumerLeCalendrier() {
        moteur.calendrierRefuse = false
        reglagesCentre.reglerCalendrier(true)
        Log.ecrire("calendrier : allumé depuis le Centre")
        NotificationCenter.default.post(name: .verbeIlotReglagesRelus, object: nil)
        appliquerLeCalendrier()
    }
    private func calendrierRefuse() {
        reglagesCentre.reglerCalendrier(false)
        moteur.calendrierActif = false
        moteur.calendrierRefuse = true
        moteur.avisCentre = .calendrierRefuse
        Log.ecrire("calendrier : accès refusé (depuis le Centre)")
        NotificationCenter.default.post(name: .verbeIlotReglagesRelus, object: nil)
        moteur.donneesChangees()
    }

    /// Coupe le micro du Mac, ou le rouvre : le bouton Micro du Centre, et l'entrée du menu de Verbe (barre des menus), seul chemin
    /// quand l'îlot n'a pas d'encoche où s'ouvrir (écran externe, MacBook fermé). « Micro coupé » éteint dans les réglages : il s'allume
    /// d'abord (rien n'est demandé à macOS pour couper un micro).
    func couperOuRouvrirLeMicro(depuis origine: String) {
        if !micro.actif {
            reglagesCentre.allumerMicro()
            activerLeMicro(true)
            NotificationCenter.default.post(name: .verbeIlotReglagesRelus, object: nil)
        }
        if !basculerLeMicro() { Log.ecrire("micro coupé : \(origine) n'a pas pu basculer le micro (aucun micro, ou commande refusée)") }
        moteur.donneesChangees()
    }
    /// Le titre de l'entrée du menu de Verbe : ce qu'un clic fera.
    var titreMenuMicro: String { moteur.microCoupe ? "Rouvrir le micro" : "Couper le micro" }

    /// macOS a refusé l'accès au dossier Téléchargements (à la demande, ou plus tard dans Réglages Système) : le réglage s'éteint, le
    /// bouton du Centre revient sur « Éteint » et la ligne d'avis dit où le rendre. Demandé depuis le Centre, l'avis est posé même si
    /// le Centre s'est rangé entre-temps : il attend sa prochaine ouverture.
    func telechargementsRefuses() {
        let depuisLeCentre = moteur.centreOuvert || telechargementsDemandesDuCentre
        telechargementsDemandesDuCentre = false
        reglagesCentre.reglerTelechargements(false)
        Log.ecrire("téléchargements : accès au dossier refusé, réglage éteint")
        NotificationCenter.default.post(name: .verbeIlotReglagesRelus, object: nil)
        moteur.telechargementsActifs = false
        moteur.telechargementsAttente = false
        if depuisLeCentre { moteur.avisCentre = .telechargementsRefuses }
        moteur.donneesChangees()
    }
}

/// Le curseur « Verre » du Centre (13/11, Hugues : régler l'opacité de la pilule depuis l'îlot, avec un bouton visible, comme le curseur de
/// luminosité du Centre de contrôle de macOS) : une piste en capsule qui se remplit, le symbole du verre au bout rempli ; on la glisse ou
/// on clique où l'on veut. C'est la même valeur que le curseur des Réglages (`ReglageVerre`) : l'aperçu est immédiat sur la Lucarne.
struct CurseurVerreCentre: View {
    @ObservedObject var m: IlotMoteur
    @ObservedObject var verre = ReglageVerre.partage
    var largeur: CGFloat
    static let hauteurPiste: CGFloat = 26, etiquette: CGFloat = 44, ecart: CGFloat = 10
    /// La piste (repère du Centre) : utile aux essais pour viser un point.
    static func piste(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX + etiquette + ecart, y: r.midY - hauteurPiste / 2, width: r.width - etiquette - ecart, height: hauteurPiste)
    }

    var body: some View {
        let w = largeur - Self.etiquette - Self.ecart, h = Self.hauteurPiste
        let i = verre.intensite
        HStack(spacing: Self.ecart) {
            Text("Verre").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(CouleursIlot.encre2)
                .frame(width: Self.etiquette, alignment: .leading).allowsHitTesting(false)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.16))
                Capsule().fill(Color.white.opacity(0.92)).frame(width: h + (w - h) * CGFloat(i))
                Image(systemName: "circle.lefthalf.filled").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.black.opacity(0.7))
                    .frame(width: h, height: h)
            }
            .frame(width: w, height: h)
            .contentShape(Capsule())
            // un clic pose la valeur sous le pointeur, un glisser la suit ; le Centre reste ouvert (épinglé), comme pour ses boutons
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                m.epinglerLeCentre()
                verre.regler(Double((g.location.x - h / 2) / max(1, w - h)))
            })
            .accessibilityElement()
            .accessibilityLabel("Intensité du verre")
            .accessibilityValue(VerreLucarne.nomIntensite(i))
            .accessibilityAdjustableAction { d in verre.regler(i + (d == .increment ? 0.1 : -0.1)) }
        }
        .frame(width: largeur, height: CGFloat(DispositionCentre.rangeeVerre))
    }
}
