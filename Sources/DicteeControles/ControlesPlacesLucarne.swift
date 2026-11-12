import Foundation
import CoreGraphics
import DicteeCore

/// Contrôles de la Lucarne déplaçable (modèle pur) : places, Dock, aimant, lancer, tracé, ressorts, geste, mémoire. Trois faux écrans :
/// un MacBook à encoche (valeurs sondées le 12/11 : 1470 × 956, barre 33, caméra 179, Dock en bas de 70 pt, icônes de 56), un écran externe
/// 2560 × 1440 sans encoche, et un 1920 × 1080 avec le Dock à gauche (puis masqué en bas).
/// Appelée depuis main.swift (un seul appel).
func controlesPlacesLucarne() {
    typealias G = GeoLucarne
    let macBook = EcranLucarne(cadre: CGRect(x: 0, y: 0, width: 1470, height: 956), barre: 33, demiCamera: 89.5, centreX: 735.5,
                               retraitBas: 70, dockCote: .bas, dockLargeur: 600, dockEpaisseur: 70)
    let externe = EcranLucarne(cadre: CGRect(x: 0, y: 0, width: 2560, height: 1440), barre: 24, demiCamera: nil,
                               retraitBas: 70, dockCote: .bas, dockLargeur: 900, dockEpaisseur: 70)
    let dockGauche = EcranLucarne(cadre: CGRect(x: 0, y: 0, width: 1920, height: 1080), barre: 24, demiCamera: nil,
                                  retraitGauche: 70, dockCote: .gauche, dockEpaisseur: 70)
    var dockMasque = EcranLucarne(cadre: CGRect(x: 0, y: 0, width: 1920, height: 1080), barre: 24, demiCamera: nil,
                                  dockCote: .bas, dockMasque: true, dockEpaisseur: 70)
    dockMasque.dockLargeur = 700
    var dockDroite = dockGauche; dockDroite.retraitGauche = 0; dockDroite.retraitDroit = 70; dockDroite.dockCote = .droite
    let faux: [(String, EcranLucarne)] = [("MacBook à encoche", macBook), ("externe sans encoche", externe), ("Dock à gauche", dockGauche),
                                          ("Dock masqué", dockMasque), ("Dock à droite", dockDroite)]

    /// La forme recouvre-t-elle le Dock ? (ou la barre des menus, hors encoche)
    func surDock(_ c: CapsuleLucarne, _ e: EcranLucarne) -> Bool {
        let marge = 0.01
        switch e.dockCote {
        case .gauche: return c.x0 < e.xBordGauche + e.dockEpaisseur - marge
        case .droite: return c.x1 > e.xBordDroit - e.dockEpaisseur + marge
        case .bas:
            guard c.y1 > e.hauteur - e.dockEpaisseur + marge else { return false }
            guard let d = e.intervalleDock else { return true }
            return c.x1 > d.lowerBound && c.x0 < d.upperBound
        }
    }
    func dansEcran(_ c: CapsuleLucarne, _ e: EcranLucarne) -> Bool {
        c.x0 >= e.xBordGauche - 0.01 && c.x1 <= e.xBordDroit + 0.01 && c.y0 >= -0.01 && c.y1 <= e.hauteur + 0.01
    }

    groupe("Lucarne : les huit places")
    verifier(PlaceLucarne.allCases.count == 8 && Set(PlaceLucarne.allCases.map(\.rawValue)).count == 8, "huit places distinctes")
    verifier(PlaceLucarne.allCases.filter(\.debout) == [.gauche, .droite], "debout : le milieu des bords gauche et droit")
    verifier(PlaceLucarne.basGauche.ancre == (0, 1) && PlaceLucarne.hautDroite.ancre == (1, 0) && PlaceLucarne.gauche.ancre == (0, 0.5) && PlaceLucarne.basMilieu.ancre == (0.5, 1),
             "ancres : coin, bord, milieu (0, ½, 1)")
    verifier(PlaceLucarne(rawValue: "basGauche") == .basGauche && PlaceLucarne(rawValue: "nimporte") == nil, "texte ↔ place")
    for (nom, e) in faux {
        for p in PlaceLucarne.allCases {
            let c = G.replie(p, e)
            let encocheReelle = p == .encoche && e.avecEncoche
            verifier(dansEcran(c, e) && c.largeur > 0 && c.hauteur > 0, "\(nom) · \(p.rawValue) : dans l'écran")
            if !encocheReelle {
                verifier(c.y0 >= e.barre + G.ecartBarre - 0.001, "\(nom) · \(p.rawValue) : jamais dans la barre des menus (y0 \(Int(c.y0)) ≥ \(Int(e.barre + 8)))")
                verifier(c.x0 >= e.xMin - 0.001 && c.x1 <= e.xMax + 0.001, "\(nom) · \(p.rawValue) : dans la zone utile")
                verifier(!surDock(c, e), "\(nom) · \(p.rawValue) : jamais sur le Dock")
            }
        }
    }
    do {
        let c = G.replie(.encoche, macBook)
        verifier(c.x0 == -(89.5 + 44) && c.x1 == 89.5 + 44 && c.y0 == 0 && c.y1 == 33 && c.s == -6 && c.r == 10, "encoche : la forme compacte (caméra 179 + ailes de 44, épaules -6)")
        let compact = TraceIlot.calculer(GeoIlot.valeurs(.lectureCompact, hauteurBarre: 33), demiCamera: 89.5, barre: 33)
        verifier(TraceLucarne.calculer(c).commandes == compact.commandes, "encoche : le même tracé que l'îlot compact d'aujourd'hui")
        let h = G.replie(.hautGauche, macBook), d = G.replie(.hautDroite, macBook)
        verifier(h.largeur == 120 && h.hauteur == 36 && h.y0 == 41 && d.y0 == 41, "places du haut : pilule 120 × 36 à barre + 8 = 41")
        let g = G.replie(.gauche, macBook)
        verifier(g.largeur == 40 && g.hauteur == 112 && abs(g.x0 - (-735.5 + 10)) < 0.001, "milieu gauche : pilule debout 40 × 112 à 10 pt du bord")
        verifier(abs(g.centreY - ((33.0 + 956 - 70) / 2).rounded()) < 0.001, "milieu des bords : entre la barre et le Dock")
        verifier(abs(h.s - 18 / 1.6) < 1e-9 && h.s == h.r, "pilule : coins = petit côté / 2 / 1,6")
    }

    groupe("Lucarne : le Dock (bas, à côté, à gauche, masqué)")
    do {
        let bg = G.replie(.basGauche, macBook), bd = G.replie(.basDroite, macBook), bm = G.replie(.basMilieu, macBook)
        let dock = macBook.intervalleDock!
        verifier(abs(dock.upperBound - dock.lowerBound - 600) < 0.001, "Dock en bas de 600 pt de large, centré sur l'écran")
        verifier(bg.x1 + 8 <= dock.lowerBound && bd.x0 - 8 >= dock.upperBound, "Dock de 600 pt : les coins du bas sont À CÔTÉ du Dock")
        verifier(abs(bg.centreY - macBook.yLigneDock) < 0.001 && abs(bd.centreY - macBook.yLigneDock) < 0.001, "… centrés sur la ligne du Dock (956 − 3 − 35 = 918)")
        verifier(bm.y1 <= 956 - 70 - 10 + 0.001, "bas du milieu : toujours au-dessus du Dock (y1 \(Int(bm.y1)) ≤ 876)")
        var inconnu = macBook; inconnu.dockLargeur = nil
        let ig = G.replie(.basGauche, inconnu), id = G.replie(.basDroite, inconnu)
        verifier(ig.y1 <= 956 - 70 - 10 + 0.001 && id.y1 <= 956 - 70 - 10 + 0.001, "largeur du Dock inconnue : les coins du bas passent AU-DESSUS")
        var large = macBook; large.dockLargeur = 1300
        verifier(G.replie(.basGauche, large).y1 <= 956 - 70 - 10 + 0.001, "Dock trop large (1300 pt) : pas la place à côté, au-dessus")
        // Dock de 1470 − 2 × 138 = 1194 pt : il reste pile 138 pt (10 + 120 + 8) de chaque côté pour un coin ; 1 pt de plus et le coin passe au-dessus
        var pile = macBook; pile.dockLargeur = 1194
        var trop = macBook; trop.dockLargeur = 1195
        verifier(abs(G.replie(.basGauche, pile).centreY - pile.yLigneDock) < 0.001 && G.replie(.basGauche, trop).y1 <= 876.001, "juste la place du coin (138 pt de reste) : à côté ; 1 pt de moins : au-dessus")
        let gauche = G.replie(.gauche, dockGauche), hg = G.replie(.hautGauche, dockGauche), bgg = G.replie(.basGauche, dockGauche)
        let bord = dockGauche.xBordGauche
        verifier(gauche.x0 - bord >= 80 - 0.001 && hg.x0 - bord >= 80 - 0.001 && bgg.x0 - bord >= 80 - 0.001, "Dock à gauche : les places de ce côté sont décalées (à 80 pt du bord : 70 de Dock + 10)")
        verifier(abs(G.replie(.droite, dockGauche).x1 - (dockGauche.xBordDroit - 10)) < 0.001, "Dock à gauche : la droite garde sa marge de 10 pt")
        verifier(G.replie(.basMilieu, dockGauche).y1 == 1080 - 10, "Dock à gauche : rien en bas, le bas du milieu est à 10 pt du bord")
        let dd = G.replie(.droite, dockDroite)
        verifier(dd.x1 <= dockDroite.xBordDroit - 70 - 10 + 0.001, "Dock à droite : la place de droite s'arrête avant lui")
        for p in [PlaceLucarne.basGauche, .basMilieu, .basDroite] {
            verifier(G.replie(p, dockMasque).y1 <= 1080 - 70 - 10 + 0.001, "Dock masqué · \(p.rawValue) : au-dessus de son épaisseur (il garderait nos clics)")
        }
        verifier(EcranLucarne.epaisseurDock(tailleIcone: 56) == 70, "épaisseur du Dock : icônes de 56 → 70 pt (sondé : visibleFrame retire 70)")
        verifier(CoteDock.depuis(orientation: "bottom") == .bas && CoteDock.depuis(orientation: "left") == .gauche && CoteDock.depuis(orientation: "right") == .droite
                 && CoteDock.depuis(orientation: nil) == .bas && CoteDock.depuis(orientation: "?") == .bas, "préférence « orientation » du Dock lue (absente : en bas)")
        let sonde = EcranLucarne(cadre: CGRect(x: 0, y: 0, width: 1470, height: 956), zoneVisible: CGRect(x: 0, y: 70, width: 1470, height: 853),
                                 demiCamera: 89.5, centreX: 735.5, dockLargeur: 600, dockEpaisseur: 70)
        verifier(sonde.barre == 33 && sonde.retraitBas == 70 && sonde.retraitGauche == 0 && sonde.retraitDroit == 0, "frame / visibleFrame sondés (0,70,1470,853) → barre 33, retrait bas 70")
        verifier(sonde == macBook, "… ce qui redonne exactement le faux MacBook")
    }

    groupe("Lucarne : sans encoche")
    do {
        verifier(G.aimant(x: 0, y: 12, externe) == 0 && G.aimant(x: 0, y: 0, dockGauche) == 0, "aucun aimant sans encoche")
        let c = G.replie(.encoche, externe)
        verifier(c.s > 0 && c.y0 == 32 && c.centreX == 0 && c.largeur == 120 && c.hauteur == 36, "la place « encoche » : une pilule de verre (coins arrondis, pas d'épaules) sous la barre, au milieu")
        let t = G.tenue(pointeur: PointLucarne(0, 12), decalage: PointLucarne(0, 0), externe)
        verifier(!t.pres && t.cx == 0 && t.cy == 12, "tenue pile sous la barre : jamais aimantée, suit le doigt")
        verifier(G.plusProche(x: 0, y: 40, externe) == .encoche, "près du haut au milieu : la pilule de verre")
        verifier(G.placeLachee(cx: 0, cy: 40, vx: 0, vy: 0, pres: false, externe) == .encoche, "lâchée là : la pilule du haut (pas de forme noire)")
    }

    groupe("Lucarne : l'aimant de l'encoche")
    do {
        let e = macBook
        verifier(G.aimant(x: 0, y: 16.5, e) == 1 && G.aimant(x: 0, y: 16.5 + 40, e) == 1, "aimant : 1 tout près (jusqu'à 40 pt)")
        verifier(abs(G.aimant(x: 0, y: 16.5 + 95, e) - 0.5) < 1e-9, "aimant : 0,5 à 95 pt")
        verifier(G.aimant(x: 0, y: 16.5 + 150, e) == 0 && G.aimant(x: 300, y: 16.5, e) == 0 && G.aimant(x: 0, y: 500, e) == 0, "aimant : 0 au-delà de ~150 pt")
        verifier(G.aimant(x: 160, y: 16.5, e) > 0 && G.aimant(x: 301, y: 16.5, e) == 0, "plus large que haute : portée 300 pt en x contre 150 en y")
        let juste = G.tenue(pointeur: PointLucarne(0, 116.5), decalage: PointLucarne(0, 0), e)   // distance 100 → 0,4545
        let loin = G.tenue(pointeur: PointLucarne(0, 117.5), decalage: PointLucarne(0, 0), e)    // distance 101 → 0,4455
        verifier(juste.pres && !loin.pres, "seuil 0,45 : à 100 pt elle s'aimante, à 101 pt non")
        let pile = G.tenue(pointeur: PointLucarne(0, 16.5), decalage: PointLucarne(0, 0), hh: 16.5, e)
        verifier(pile.pres && abs(pile.cx) < 1e-9 && abs(pile.cy - 16.5) < 1e-9, "sur l'encoche : la forme de l'encoche centrée dans l'encoche")
        let pilule = G.tenue(pointeur: PointLucarne(0, 16.5), decalage: PointLucarne(0, 0), hh: 18, e)
        verifier(abs(pilule.cy - 18) < 1e-9, "sur l'encoche : une forme plus haute garde son haut au bord de l'écran (centre à sa demi-hauteur, pas au milieu de la barre)")
        let a = G.tenue(pointeur: PointLucarne(10, 70), decalage: PointLucarne(0, 0), e)
        verifier(a.pres && abs(a.cx) < 10 && a.cy < 70 && a.cy > 16.5, "près de l'encoche : elle est retenue, tirée vers l'encoche")
    }
    do {
        let e = macBook
        let libre = G.tenue(pointeur: PointLucarne(300, 400), decalage: PointLucarne(10, -6), e)
        verifier(!libre.pres && libre.cx == 310 && libre.cy == 394, "tenue loin de l'encoche : elle suit le pointeur à 1 pt près (+ l'écart de la prise)")
        let bord = G.tenue(pointeur: PointLucarne(5000, 400), decalage: PointLucarne(0, 0), e)
        verifier(abs(bord.cx - (e.xBordDroit - 60 * 1.04 - 4)) < 1e-9, "tenue : jamais hors de l'écran à droite")
        let fond = G.tenue(pointeur: PointLucarne(0, 5000), decalage: PointLucarne(0, 0), e)
        verifier(abs(fond.cy - (956 - 18 * 1.04 - 4)) < 1e-9, "tenue : jamais hors de l'écran en bas")
        let gauche = G.tenue(pointeur: PointLucarne(-5000, 400), decalage: PointLucarne(0, 0), e)
        verifier(abs(gauche.cx - (e.xBordGauche + 60 * 1.04 + 4)) < 1e-9, "tenue : jamais hors de l'écran à gauche")
    }

    groupe("Lucarne : la place la plus proche")
    for (nom, e) in faux {
        verifier(PlaceLucarne.allCases.allSatisfy { p in let c = G.replie(p, e); return G.plusProche(x: c.centreX, y: c.centreY, e) == p },
                 "\(nom) : chacun des 8 centres → sa place")
        // un point intermédiaire : à 30 % du chemin entre une place et sa voisine la plus proche
        var ok = true
        for p in PlaceLucarne.allCases {
            let c = G.replie(p, e), autres = PlaceLucarne.allCases.filter { $0 != p }
            let q = autres.map { G.replie($0, e) }.min { hypot($0.centreX - c.centreX, $0.centreY - c.centreY) < hypot($1.centreX - c.centreX, $1.centreY - c.centreY) }!
            let x = c.centreX + 0.3 * (q.centreX - c.centreX), y = c.centreY + 0.3 * (q.centreY - c.centreY)
            if G.plusProche(x: x, y: y, e) != p { ok = false }
        }
        verifier(ok, "\(nom) : à 30 % du chemin vers la voisine, on reste sur sa place")
    }
    verifier(G.plusProche(x: 0, y: 20, macBook, sauf: .encoche) != .encoche && G.plusProche(x: 0, y: 20, macBook) == .encoche, "« sauf » écarte une place")

    groupe("Lucarne : l'encoche n'attire que près d'elle (la zone de son aimant)")
    do {
        let e = macBook
        verifier(G.plusProche(x: 0, y: e.hauteur / 2, e) != .encoche && G.plusProche(x: 0, y: 450, e) == .basMilieu,
                 "lâchée au milieu de l'écran (ou à 450 pt sous l'encoche) : la plus proche des sept autres places, jamais l'encoche")
        verifier(G.plusProche(x: 0, y: 16.5 + 149, e) == .encoche && G.plusProche(x: 0, y: 16.5 + 151, e) != .encoche,
                 "sous l'encoche : elle attire jusqu'à 150 pt (149 : l'encoche ; 151 : une autre place)")
        verifier(G.plusProche(x: 290, y: 16.5, e) == .encoche && G.plusProche(x: 310, y: 30, e) != .encoche, "de côté : jusqu'à ~300 pt, comme l'aimant")
        // partout où l'aimant ne tient plus, jamais l'encoche ; partout où l'aimant retient la forme tenue (seuil 0,45), l'encoche
        var horsZone = true, dansZone = true
        for x in stride(from: e.xBordGauche, through: e.xBordDroit, by: 15) {
            for y in stride(from: 0.0, through: e.hauteur, by: 15) {
                let a = G.aimant(x: x, y: y, e), p = G.plusProche(x: x, y: y, e)
                if a <= 0, p == .encoche { horsZone = false }
                if a > G.seuilAimant, p != .encoche { dansZone = false }
            }
        }
        verifier(horsZone, "hors de la zone de l'aimant (tout l'écran, tous les 15 pt) : jamais l'encoche")
        verifier(dansZone, "là où l'aimant retient la forme (> 0,45) : l'encoche reste la plus proche")
        verifier(G.plusProche(x: 0, y: 300, externe) == .encoche, "sans caméra : la pilule du haut au milieu est une place comme les autres (pas de zone d'aimant)")
        verifier(G.placeLachee(cx: 0, cy: 450, vx: 0, vy: 0, pres: false, e) == .basMilieu, "lâchée sans élan au milieu : le bas du milieu, pas l'encoche")
    }

    groupe("Lucarne : VoiceOver, « Déplacer vers… »")
    do {
        let a = PlaceLucarne.actionsDeplacer(depuis: .hautDroite, avecEncoche: true)
        verifier(a.count == 7 && !a.contains { $0.place == .hautDroite } && Set(a.map(\.place)).count == 7, "une action par AUTRE place (7), jamais la sienne")
        verifier(a.map(\.nom) == ["Déplacer vers l'encoche", "Déplacer vers le haut à gauche", "Déplacer vers le bord gauche", "Déplacer vers le bord droit",
                                  "Déplacer vers le bas à gauche", "Déplacer vers le bas au milieu", "Déplacer vers le bas à droite"],
                 "les noms, dans l'ordre des places : \(a.map(\.nom).joined(separator: " · "))")
        let sans = PlaceLucarne.actionsDeplacer(depuis: .basGauche, avecEncoche: false)
        verifier(sans.first?.nom == "Déplacer vers le haut au milieu" && sans.count == 7, "sans caméra : « Déplacer vers le haut au milieu » (la pilule du haut)")
        verifier(Set(PlaceLucarne.allCases.map { $0.nom(avecEncoche: true) }).count == 8, "huit noms distincts")
    }

    groupe("Lucarne : deux écrans (on la glisse de l'un à l'autre)")
    do {
        let mac = CGRect(x: 0, y: 0, width: 1470, height: 956), ext = CGRect(x: 1470, y: -124, width: 1920, height: 1080)
        let dessus = CGRect(x: 200, y: 956, width: 1000, height: 800), loin = CGRect(x: 5000, y: 0, width: 800, height: 600)
        verifier(BordsEcran.voisins(de: mac, parmi: [mac, ext]) == .droite && BordsEcran.voisins(de: ext, parmi: [mac, ext]) == .gauche,
                 "deux écrans côte à côte : le bord droit de l'un touche le bord gauche de l'autre")
        verifier(BordsEcran.voisins(de: mac, parmi: [mac, dessus]) == .haut && BordsEcran.voisins(de: dessus, parmi: [mac, dessus]) == .bas,
                 "un écran posé au-dessus : le haut de l'un, le bas de l'autre")
        verifier(BordsEcran.voisins(de: mac, parmi: [mac, loin]).isEmpty && BordsEcran.voisins(de: mac, parmi: [mac]).isEmpty,
                 "un écran qui ne touche pas, ou seul : aucun voisin")
        var e = macBook; e.voisins = .droite
        let bord = G.tenue(pointeur: PointLucarne(e.xBordDroit + 30, 400), decalage: PointLucarne(0, 0), e)
        verifier(bord.cx == e.xBordDroit + 30, "tenue vers l'écran voisin : elle passe le bord avec le doigt (sans buter, sans saut à la bascule)")
        let gauche = G.tenue(pointeur: PointLucarne(-5000, 400), decalage: PointLucarne(0, 0), e)
        verifier(abs(gauche.cx - (e.xBordGauche + 60 * 1.04 + 4)) < 1e-9, "… mais toujours retenue du côté sans voisin")
    }

    groupe("Lucarne : la dictée (fn) à sa place, hors de l'encoche")
    for (nom, e) in faux {
        var ok = true, fixe = true
        for p in PlaceLucarne.allCases where p != .encoche || !e.avecEncoche {
            let c = G.dictee(p, e, ruban: false, mainsLibres: false), r = G.dictee(p, e, ruban: true, mainsLibres: false), l = G.dictee(p, e, ruban: true, mainsLibres: true)
            for k in [c, r, l] where !dansEcran(k, e) || k.y0 < e.yHaut - 0.001 || surDock(k, e) || k.hauteur != G.dicteeHauteur { ok = false }
            // elle s'allonge vers l'intérieur : le bord côté écran ne bouge pas (au milieu : centrée)
            switch p.ancre.x {
            case 0: if abs(c.x0 - r.x0) > 0.001 || abs(r.x0 - l.x0) > 0.001 { fixe = false }
            case 1: if abs(c.x1 - r.x1) > 0.001 || abs(r.x1 - l.x1) > 0.001 { fixe = false }
            default: if abs(c.centreX - r.centreX) > 0.001 || abs(r.centreX - l.centreX) > 0.001 { fixe = false }
            }
            if abs(c.centreY - G.grand(p, e, largeur: 404, hauteur: 36, rayon: 1).centreY) > 0.001 { fixe = false }
        }
        verifier(ok, "\(nom) : la pilule de la dictée, à chaque place : dans l'écran, hors de la barre et du Dock")
        verifier(fixe, "\(nom) : le texte et les boutons l'allongent vers l'intérieur (le bord côté écran ne bouge pas)")
    }
    do {
        verifier(G.largeurDictee(ruban: false, mainsLibres: false) == 120 && G.largeurDictee(ruban: true, mainsLibres: true) == 404, "dictée : 120 pt repliée, 340 avec le texte, + 64 mains libres")
        let bg = G.dictee(.basGauche, macBook, ruban: true, mainsLibres: false), lucarne = G.replie(.basGauche, macBook)
        verifier(abs(bg.x0 - lucarne.x0) < 0.001 && abs(bg.centreY - lucarne.centreY) < 0.001 && !macBook.recouvreDock(x0: bg.x0, x1: bg.x1),
                 "en bas à gauche, à côté d'un Dock de 600 pt : exactement à la place de la Lucarne (même bord, même ligne), sans toucher le Dock")
        var large = macBook; large.dockLargeur = 1000
        let bl = G.dictee(.basGauche, large, ruban: true, mainsLibres: true)
        verifier(abs(bl.x0 - G.replie(.basGauche, large).x0) < 0.001 && bl.y1 <= large.yFond + 0.001, "un Dock plus large qu'elle n'a de place à côté : elle monte au-dessus de lui")
    }

    groupe("Lucarne : plein écran (décision D : elle reste à sa place)")
    do {
        // dans un Space plein écran, la barre des menus et le Dock se masquent : la zone visible devient tout l'écran. La barre vient de
        // l'encoche (ou de 24 pt au moins), le Dock compte toujours son épaisseur : les places ne bougent pas.
        func pleinEcran(_ e: EcranLucarne) -> EcranLucarne {
            var p = e; p.retraitGauche = 0; p.retraitDroit = 0; p.retraitBas = 0; return p
        }
        for (nom, e) in faux where !e.dockMasque {
            let pe = pleinEcran(e)
            let ecart = PlaceLucarne.allCases.map { p -> Double in
                let a = G.replie(p, e), b = G.replie(p, pe)
                return max(abs(a.x0 - b.x0), abs(a.x1 - b.x1), abs(a.y0 - b.y0), abs(a.y1 - b.y1))
            }.max() ?? 0
            verifier(ecart < 0.001, "\(nom) : en plein écran (barre et Dock masqués), les 8 places ne bougent pas (écart \(ecart) pt)")
        }
        var barre25 = externe; barre25.barre = 25
        let ecart = PlaceLucarne.allCases.map { p in abs(G.replie(p, barre25).y0 - G.replie(p, externe).y0) }.max() ?? 0
        verifier(ecart <= 1.001, "écran sans encoche : la barre de 25 pt masquée (lue 24 au moins), les places du haut bougent d'1 pt au plus")
    }

    groupe("Lucarne : le lancer")
    do {
        let e = macBook, cx = 0.0, cy = 478.0
        let v = 800.0, d = v / 2.0.squareRoot()
        let cas: [(String, Double, Double, [PlaceLucarne])] = [
            ("droite", v, 0, [.droite]), ("gauche", -v, 0, [.gauche]), ("bas", 0, v, [.basMilieu]),
            ("haut", 0, -v, [.hautGauche, .hautDroite]), ("bas-droite", d, d, [.basDroite]), ("bas-gauche", -d, d, [.basGauche]),
            ("haut-droite", d, -d, [.hautDroite]), ("haut-gauche", -d, -d, [.hautGauche])]
        for (nom, vx, vy, attendu) in cas {
            let p = G.viseLancer(cx: cx, cy: cy, vx: vx, vy: vy, e)
            verifier(attendu.contains(p), "lancer 800 pt/s vers \(nom) → \(p.rawValue)")
            verifier(p != .encoche, "lancer vers \(nom) : jamais l'encoche")
        }
        verifier(G.viseLancer(cx: 0, cy: 200, vx: 0, vy: -900, e) != .encoche && G.viseLancer(cx: 10, cy: 60, vx: 0, vy: -2000, e) != .encoche, "même droit sur l'encoche : une place du haut, pas l'encoche")
        verifier(G.placeLachee(cx: 100, cy: 700, vx: 300, vy: 0, pres: false, e) == G.plusProche(x: 100, y: 700, e), "moins de 350 pt/s : la place la plus proche, pas la direction")
        verifier(G.placeLachee(cx: 100, cy: 700, vx: 0, vy: 0, pres: false, e) == G.plusProche(x: 100, y: 700, e), "sans vitesse : la place la plus proche")
        verifier(G.placeLachee(cx: 0, cy: 478, vx: 800, vy: 0, pres: false, e) == .droite, "au-delà de 350 pt/s : la direction")
        verifier(G.placeLachee(cx: 0, cy: 20, vx: 800, vy: 0, pres: true, e) == .encoche, "lâchée aimantée : l'encoche, même lancée")
        verifier(G.placeLachee(cx: 0, cy: 478, vx: 351, vy: 0, pres: false, e) == .droite && G.placeLachee(cx: 0, cy: 478, vx: 349, vy: 0, pres: false, e) == G.plusProche(x: 0, y: 478, e), "seuil à 350 pt/s")
        // un lancer presque à l'opposé de toute place : on retombe sur la plus proche du point projeté (60° puis repli)
        let p = G.viseLancer(cx: 0, cy: 478, vx: 0, vy: 400, e)
        verifier(p == .basMilieu, "lancer vers le bas à 400 pt/s → bas du milieu")
    }

    groupe("Lucarne : grandir depuis sa place")
    do {
        let e = macBook
        let bg = G.grand(.basGauche, e, largeur: 464, hauteur: 298, rayon: 30)
        verifier(bg.y1 <= e.yFond + 0.001 && bg.y1 == e.yFond, "depuis le coin bas gauche : monte au-dessus de la ligne du Dock (y1 \(bg.y1) = 876)")
        verifier(bg.x0 == e.xMin, "… et reste calée à gauche")
        let hd = G.grand(.hautDroite, e, largeur: 464, hauteur: 298, rayon: 30), r = G.replie(.hautDroite, e)
        verifier(abs(hd.x1 - r.x1) < 0.001 && abs(hd.y0 - r.y0) < 0.001, "depuis le coin haut droit : l'ancre ne bouge pas (vers le bas et la gauche)")
        let g = G.grand(.gauche, e, largeur: 360, hauteur: 66, rayon: 22), rg = G.replie(.gauche, e)
        verifier(abs(g.x0 - rg.x0) < 0.001 && abs(g.centreY - rg.centreY) < 0.001, "depuis le bord gauche : grandit vers l'intérieur, centrée sur le bord")
        let bm = G.grand(.basMilieu, e, largeur: 464, hauteur: 298, rayon: 30)
        verifier(abs(bm.centreX) < 0.001 && bm.y1 <= e.yFond + 0.001, "depuis le bas du milieu : centrée, au-dessus du Dock")
        let en = G.grand(.encoche, externe, largeur: 464, hauteur: 298, rayon: 30)
        verifier(abs(en.centreX) < 0.001 && en.y0 == 32, "écran sans encoche, depuis la pilule du haut : centrée sous la barre")
        for (nom, e) in faux {
            var ok = true, ok2 = true
            for p in PlaceLucarne.allCases {
                for (w, h, r) in [(464.0, 298.0, 30.0), (360.0, 66.0, 22.0), (464.0, 400.0, 30.0)] {
                    let c = G.grand(p, e, largeur: w, hauteur: h, rayon: r)
                    if !dansEcran(c, e) || c.largeur != w || c.hauteur != h { ok = false }
                    if p != .encoche || !e.avecEncoche, c.y0 < e.yHaut - 0.001 || surDock(c, e) { ok2 = false }
                }
            }
            verifier(ok, "\(nom) : toutes les places, grandes cartes : toujours dans l'écran, taille respectée")
            verifier(ok2, "\(nom) : toutes les places, grandes cartes : jamais sur le Dock ni dans la barre")
        }
        let h = G.grand(.hautGauche, dockGauche, largeur: 464, hauteur: 298, rayon: 30)
        verifier(h.x0 - dockGauche.xBordGauche >= 80 - 0.001, "Dock à gauche : la carte du haut gauche s'ouvre à côté du Dock")
    }

    groupe("Lucarne : le tracé")
    do {
        func boite(_ p: TraceIlot.Points) -> (x0: Double, x1: Double, y0: Double, y1: Double) {
            var x0 = Double.infinity, x1 = -Double.infinity, y0 = Double.infinity, y1 = -Double.infinity
            func vu(_ x: Double, _ y: Double) { x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y) }
            for c in p.commandes {
                switch c {
                case let .deplacer(x, y), let .ligne(x, y): vu(x, y)
                case let .quad(a, b, x, y): vu(a, b); vu(x, y)
                case let .cubique(a, b, c2, d, x, y): vu(a, b); vu(c2, d); vu(x, y)
                }
            }
            return (x0, x1, y0, y1)
        }
        func fini(_ p: TraceIlot.Points) -> Bool {
            p.commandes.allSatisfy { c in
                switch c {
                case let .deplacer(x, y), let .ligne(x, y): return x.isFinite && y.isFinite
                case let .quad(a, b, x, y): return [a, b, x, y].allSatisfy(\.isFinite)
                case let .cubique(a, b, c, d, x, y): return [a, b, c, d, x, y].allSatisfy(\.isFinite)
                }
            }
        }
        func debutFin(_ p: TraceIlot.Points) -> (Double, Double)? {
            func pt(_ c: TraceIlot.Commande) -> (Double, Double) {
                switch c { case let .deplacer(x, y), let .ligne(x, y): return (x, y); case let .quad(_, _, x, y): return (x, y); case let .cubique(_, _, _, _, x, y): return (x, y) }
            }
            guard let a = p.commandes.first, let b = p.commandes.last, case .deplacer = a else { return nil }
            return (pt(b).1 - pt(a).1, pt(b).0 - pt(a).0)
        }
        let pilule = CapsuleLucarne.pilule(cx: 100, cy: 200, largeur: 120, hauteur: 36)
        let t = TraceLucarne.calculer(pilule), b = boite(t)
        verifier(fini(t) && abs(b.x0 - 40) < 1e-9 && abs(b.x1 - 160) < 1e-9 && abs(b.y0 - 182) < 1e-9 && abs(b.y1 - 218) < 1e-9, "pilule : la boîte du tracé est exactement la capsule")
        verifier(debutFin(t)?.0 == 0, "pilule : fermé (la ligne de fermeture est horizontale, en haut)")
        let carte = CapsuleLucarne.boite(x0: -300, y0: 50, largeur: 464, hauteur: 298, rayon: 30)
        let bc = boite(TraceLucarne.calculer(carte))
        verifier(abs(bc.x0 + 300) < 1e-9 && abs(bc.x1 - 164) < 1e-9 && abs(bc.y0 - 50) < 1e-9 && abs(bc.y1 - 348) < 1e-9, "carte dépliée : boîte = capsule")
        let epaules = CapsuleLucarne(x0: -134, x1: 134, y0: 0, y1: 33, s: -6, r: 10)
        let te = TraceLucarne.calculer(epaules), be = boite(te)
        verifier(abs(be.x0 + 140) < 1e-9 && abs(be.x1 - 140) < 1e-9 && be.y0 == -1 && abs(be.y1 - 33) < 1e-9, "s < 0 : épaules de 6 pt de chaque côté, le tracé dépasse de 1 pt au-dessus de l'écran")
        verifier(debutFin(te)?.0 == 0 && te.bande == 140 && te.corps == 134 && te.hauteur == 33, "épaules : fermé, bande 140, corps 134")
        let m = TraceLucarne.calculer(CapsuleLucarne(x0: 0, x1: 100, y0: 50, y1: 90, s: 0, r: 8))
        verifier(fini(m) && !m.commandes.isEmpty, "s = 0 : angle vif en haut, tracé valide")
        verifier(TraceLucarne.calculer(CapsuleLucarne(x0: 10, x1: 10, y0: 5, y1: 40, s: 5, r: 5)).commandes.isEmpty, "capsule vide (largeur 0) : aucun tracé")
        let petite = TraceLucarne.calculer(CapsuleLucarne(x0: 0, x1: 4, y0: 0, y1: 4, s: 30, r: 30))
        let bp = boite(petite)
        verifier(fini(petite) && bp.x0 >= 0 && bp.x1 <= 4 && bp.y0 >= 0 && bp.y1 <= 4, "coins trop grands pour la forme : bornés, rien ne dépasse")
        // la transition s : l'épaule se referme sans saut (le tracé reste dans la boîte élargie de |s|)
        var ok = true
        for s in stride(from: -6.0, through: 12.0, by: 0.5) {
            let bt = boite(TraceLucarne.calculer(CapsuleLucarne(x0: -60, x1: 60, y0: 41, y1: 77, s: s, r: 11.25)))
            if bt.x0 < -60 - max(0, -s) - 1e-9 || bt.x1 > 60 + max(0, -s) + 1e-9 { ok = false }
        }
        verifier(ok, "de s = −6 à +12 : le tracé n'a pas de saut de boîte")
    }

    groupe("Lucarne : quitter l'encoche et y revenir sans saut")
    do {
        // chaque forme repliée de l'encoche (rien sous la barre), sur des barres de 32 à 38 pt : la capsule tirée de sa trace redonne
        // exactement le même tracé (le passage du régime de l'encoche au régime libre, et retour, ne se voit pas)
        var pareils = 0, total = 0
        for barre in [32.0, 33, 37, 38] {
            for v in VueIlot.allCases where GeoIlot.profondeur(v) == 0 && v != .repos {
                let g = GeoIlot.valeurs(v, hauteurBarre: barre, demiCamera: 89.5)
                let p = TraceIlot.calculer(g, demiCamera: 89.5, barre: barre)
                let q = TraceLucarne.calculer(.encoche(p, epaule: g[3], coin: g[4]))
                total += 1
                if q.commandes == p.commandes { pareils += 1 } else { print("    écart : \(v) barre \(barre)") }
            }
        }
        verifier(total > 5 && pareils == total, "formes repliées : la capsule de l'encoche redonne le même tracé (\(pareils)/\(total))")
        // l'encoche vide (la caméra seule, coins carrés en haut) : même boîte
        let g = GeoIlot.valeurs(.repos, hauteurBarre: 33, demiCamera: 89.5)
        let p = TraceIlot.calculer(g, demiCamera: 89.5, barre: 33)
        let c = CapsuleLucarne.encoche(p, epaule: g[3], coin: g[4])
        verifier(c.x0 == -89.5 && c.x1 == 89.5 && c.y0 == 0 && c.y1 == 33, "encoche vide : la capsule épouse la caméra (−89,5…89,5 × 0…33)")
        // une forme dépliée (le Centre) : la capsule prend son corps et sa hauteur (elle se replie ensuite en pilule, tenue)
        let gc = GeoIlot.valeurs(.centre, hauteurBarre: 33, demiCamera: 89.5)
        let pc = TraceIlot.calculer(gc, demiCamera: 89.5, barre: 33)
        let cc = CapsuleLucarne.encoche(pc, epaule: gc[3], coin: gc[4])
        verifier(cc.x0 == -pc.corps && cc.x1 == pc.corps && cc.y1 == pc.hauteur && cc.s < 0, "Centre ouvert : la capsule part de son corps et de sa hauteur, épaules creuses")
    }

    groupe("Lucarne : les ressorts")
    do {
        let depart = G.replie(.hautGauche, macBook), arrivee = G.replie(.basDroite, macBook)
        func faire(_ r: inout RessortsCapsule, _ dt: Double = 1.0 / 60, pendant: Double) { var t = 0.0; while t < pendant { r.avancer(dt); t += dt } }
        var r = RessortsCapsule(depart, noir: 0)
        verifier(r.fini && r.valeur == depart && r.fonduNoir == 0, "au départ : posée sur sa forme, verre")
        r.viser(arrivee, passage: .atterrissage)
        verifier(!r.fini && r.cible == arrivee, "viser : en mouvement, la cible est la forme voulue")
        verifier(r.cx.reponse == 0.5 && r.cx.amortissement == 0.8 && r.hw.reponse == 0.3 && r.hw.amortissement == 0.9 && r.noir.cible == 0 && r.noir.reponse == 0.3, "atterrissage : 0,5 s / 0,8 au centre, 0,3 s / 0,9 aux tailles, verre en 0,3 s")
        faire(&r, pendant: 3)
        verifier(r.fini || { r.poser(); return true }(), "convergence : posée après quelques secondes")
        verifier(abs(r.valeur.x0 - arrivee.x0) < 0.05 && abs(r.valeur.y1 - arrivee.y1) < 0.05 && abs(r.valeur.s - arrivee.s) < 0.05, "convergence : sur la forme visée")

        var o = RessortsCapsule(depart, noir: 0)
        o.viser(arrivee, passage: .atterrissage, vitesse: PointLucarne(800, 0))
        verifier(o.cx.v == 800 && o.cy.v == 0, "lancer : le centre garde la vitesse du geste (800, 0)")
        var sans = RessortsCapsule(depart, noir: 0)
        sans.viser(arrivee, passage: .atterrissage)
        o.avancer(0.016); sans.avancer(0.016)
        verifier(o.cx.x - depart.centreX > sans.cx.x - depart.centreX + 5, "lancer : part plus vite qu'un simple déplacement")
        var v = RessortsCapsule(depart); v.cx.v = 300
        v.viser(arrivee, passage: .ouverture)
        verifier(v.cx.v == 300, "viser garde la vitesse du ressort (jamais de saut)")

        var red = RessortsCapsule(depart, noir: 1)
        red.viser(arrivee, passage: .atterrissage, reduire: true)
        verifier(red.fini && red.valeur == arrivee && red.fonduNoir == 0 && red.cx.v == 0, "Réduire les animations : tout est posé tout de suite (forme, verre)")
        red.viser(depart, passage: .aspiration, reduire: true)
        verifier(red.valeur == depart && red.fonduNoir == 1, "… et l'aspiration aussi : forme et noir")

        var f = RessortsCapsule(CapsuleLucarne.boite(x0: 0, y0: 100, largeur: 464, hauteur: 298, rayon: 30))
        let avant = f.valeur
        f.viser(G.replie(.basMilieu, macBook), passage: .fermeture)
        f.avancer(0.03)
        verifier(f.valeur == avant && !f.fini, "fermeture : le contenu part d'abord (0,06 s d'attente, la forme ne bouge pas encore)")
        f.avancer(0.5)
        verifier(f.valeur != avant && f.hw.reponse == 0.38 && f.hw.amortissement == 1, "fermeture : puis la forme se dégonfle (0,38 s sans rebond)")
        var ouv = RessortsCapsule(depart, noir: 0)
        ouv.viser(CapsuleLucarne.boite(x0: 0, y0: 100, largeur: 464, hauteur: 298, rayon: 30), passage: .ouverture)
        verifier(ouv.cx.reponse == 0.46 && ouv.hh.reponse == 0.46 && ouv.hh.amortissement == 0.8 && ouv.noir.cibleFinale == 0, "ouverture : 0,46 s / 0,8, le noir ne change pas")

        var asp = RessortsCapsule(depart, noir: 0)
        asp.viser(G.replie(.encoche, macBook), passage: .aspiration)
        verifier(asp.noir.cibleFinale == 1 && asp.noir.reponse == 0.14 && asp.s.reponse == 0.26 && asp.s.amortissement == 1 && asp.cx.reponse == 0.36, "aspiration : noire en 0,14 s, coins 0,26 s / 1, centre 0,36 s / 0,9")
        var t = RessortsCapsule(depart, noir: 0)
        t.viser(G.replie(.encoche, macBook), passage: .tenueEncoche)
        t.suivre(cx: 50, cy: 80)
        verifier(t.cx.x == 50 && t.cy.x == 80 && t.cx.v == 0 && t.hw.reponse == 0.28 && t.hw.amortissement == 0.86 && t.noir.cibleFinale == 1, "tenue près de l'encoche : le centre suit le doigt (posé), forme 0,28 s / 0,86, noire")
        t.viser(CapsuleLucarne.pilule(cx: 0, cy: 0, largeur: 120, hauteur: 36), passage: .tenueVerre)
        verifier(t.noir.cibleFinale == 0 && t.cx.cibleFinale == 50, "tenue ailleurs : redevient verre, le centre n'est pas visé")

        var l = RessortsCapsule(depart, noir: 0)
        l.lever()
        verifier(l.leve.cible == 1 && l.leve.reponse == 0.26 && l.leve.amortissement == 0.7, "levé : 0,26 s / 0,7")
        faire(&l, pendant: 2)
        verifier(abs(l.leve.x - 1) < 0.01 && abs(l.affichee.largeur - depart.largeur * 1.04) < 0.5, "levée : échelle 1,04")
        l.reposer()
        verifier(l.leve.cible == 0 && l.leve.reponse == 0.4 && l.leve.amortissement == 0.9, "reposée : 0,4 s / 0,9")
        faire(&l, pendant: 3)
        verifier(abs(l.affichee.largeur - depart.largeur) < 0.2, "reposée : retour à l'échelle 1")

        var s = RessortsCapsule(depart, noir: 0)
        s.cx.x = depart.centreX + 40; s.cy.x = depart.centreY + 18       // la forme est au doigt : cx − pointeur = 40, 18
        s.saisir(pointeur: PointLucarne(depart.centreX, depart.centreY))
        verifier(s.decalage == PointLucarne(40, 18) && s.decalX.cibleFinale == 40 && s.decalY.cibleFinale == 10, "saisie : écart du doigt retenu, ramené vers le milieu (bornes 44 et 10)")
        var posee = RessortsCapsule(depart, noir: 0)
        posee.viser(arrivee, passage: .atterrissage)
        posee.poser()
        verifier(posee.fini && posee.valeur == arrivee, "poser : tout à sa cible sans animation")
        var plac = RessortsCapsule(depart)
        plac.placer(arrivee)
        verifier(plac.fini && plac.valeur == arrivee, "placer : saute sur la forme")
    }

    groupe("Lucarne : réduire les animations pendant la tenue")
    do {
        var r = RessortsCapsule(.pilule(cx: 400, cy: 300, largeur: 120, hauteur: 36))
        r.viser(G.replie(.encoche, macBook), passage: .tenueEncoche, reduire: true)
        verifier(r.cx.x == 400 && r.cy.x == 300 && r.hh.x == macBook.barre / 2 && r.fini, "réduire : la forme tenue saute, le centre reste au doigt")
    }

    groupe("Lucarne : le geste (appui long, glisser, lancer)")
    do {
        let o = PointLucarne(100, 200)
        var g = GesteLucarne()
        g.appuyer(o, t: 10)
        verifier(g.phase == .appui && abs((g.echeanceAppui ?? 0) - 10.4) < 1e-9 && abs(g.progression(a: 10.2) - 0.5) < 1e-9, "appui : l'échéance à 0,4 s, l'anneau se remplit")
        verifier(g.bouger(PointLucarne(105, 200), t: 10.1) == [] && g.phase == .appui, "5 pt avant 0,4 s : l'appui continue")
        verifier(g.bouger(PointLucarne(100, 206), t: 10.2) == [] && g.phase == .appui, "6 pt pile : l'appui continue")
        verifier(g.echeance(10.39) == [], "avant 0,4 s : pas de décollage")
        verifier(g.echeance(10.4) == [.decolle] && g.phase == .decollee, "à 0,4 s : elle se décolle")
        verifier(g.echeance(10.5) == [], "… une seule fois")
        verifier(g.bouger(PointLucarne(300, 300), t: 10.5) == [.suit(PointLucarne(300, 300))], "décollée : elle suit le pointeur, même loin (plus de limite de 6 pt)")

        var a = GesteLucarne()
        a.appuyer(o, t: 0)
        verifier(a.bouger(PointLucarne(107, 200), t: 0.2) == [.annule] && a.phase == .annulee, "7 pt avant 0,4 s : annulé (ni clic ni déplacement)")
        verifier(a.bouger(PointLucarne(300, 300), t: 0.5) == [] && a.echeance(0.5) == [] && a.relacher(PointLucarne(300, 300), t: 0.6) == [] && a.phase == .repos, "annulé : plus rien ne se passe, ni au réveil, ni au relâchement")

        var c = GesteLucarne()
        c.appuyer(o, t: 0)
        verifier(c.relacher(o, t: 0.3) == [.clic] && c.phase == .repos, "relâché à 0,3 s sans bouger : un clic")
        var c2 = GesteLucarne()
        c2.appuyer(o, t: 0)
        _ = c2.bouger(PointLucarne(103, 200), t: 0.1)
        verifier(c2.relacher(PointLucarne(103, 200), t: 0.3) == [.clic], "relâché à 0,3 s après 3 pt : un clic")
        var c3 = GesteLucarne()
        c3.appuyer(o, t: 0)
        verifier(c3.relacher(PointLucarne(120, 200), t: 0.3) == [.annule], "relâché à 0,3 s, 20 pt plus loin (sans mouvement vu) : annulé")

        var d = GesteLucarne()
        d.appuyer(o, t: 0)
        verifier(d.echeance(0.4) == [.decolle] && d.relacher(o, t: 0.45) == [.lacher(vx: 0, vy: 0)] && d.phase == .repos, "décollée puis relâchée sans bouger : lâchée sans vitesse")

        // vitesse : 1000 pt/s vers la droite, un point toutes les 10 ms
        var v = GesteLucarne()
        v.appuyer(o, t: 0)
        _ = v.echeance(0.4)
        for i in 0...20 { _ = v.bouger(PointLucarne(100 + 1000 * Double(i) * 0.01, 200), t: 0.4 + Double(i) * 0.01) }
        let fin = v.relacher(PointLucarne(300, 200), t: 0.6)
        if case let .lacher(vx, vy)? = fin.first {
            verifier(abs(vx - 1000) < 1 && abs(vy) < 1e-9, "lâcher : vitesse mesurée (\(Int(vx)) pt/s ≈ 1000)")
        } else { verifier(false, "lâcher : vitesse mesurée") }
        // seulement les 100 dernières ms : 0,2 s lent puis 0,1 s à 2000 pt/s
        var w = GesteLucarne()
        w.appuyer(o, t: 0)
        _ = w.echeance(0.4)
        for i in 0...20 { _ = w.bouger(PointLucarne(100 + 10 * Double(i), 200), t: 0.4 + Double(i) * 0.01) }       // 1000 pt/s
        for i in 1...10 { _ = w.bouger(PointLucarne(300 + 20 * Double(i), 200), t: 0.6 + Double(i) * 0.01) }       // 2000 pt/s
        if case let .lacher(vx, _)? = w.relacher(PointLucarne(500, 200), t: 0.7).first {
            verifier(abs(vx - 2000) < 5, "lâcher : seulement les 100 dernières ms comptent (\(Int(vx)) ≈ 2000, pas la moyenne)")
        } else { verifier(false, "lâcher : 100 dernières ms") }
        // dernier mouvement trop vieux
        var z = GesteLucarne()
        z.appuyer(o, t: 0)
        _ = z.echeance(0.4)
        for i in 0...10 { _ = z.bouger(PointLucarne(100 + 10 * Double(i), 200), t: 0.4 + Double(i) * 0.01) }
        verifier(z.relacher(PointLucarne(200, 200), t: 0.5 + 0.09) == [.lacher(vx: 0, vy: 0)], "dernier mouvement il y a 90 ms : vitesse nulle")
        var y = GesteLucarne()
        y.appuyer(o, t: 0)
        _ = y.echeance(0.4)
        for i in 0...10 { _ = y.bouger(PointLucarne(100 + 10 * Double(i), 200), t: 0.4 + Double(i) * 0.01) }
        if case let .lacher(vx, _)? = y.relacher(PointLucarne(200, 200), t: 0.5 + 0.07).first {
            verifier(vx > 900, "dernier mouvement il y a 70 ms : la vitesse compte encore (\(Int(vx)))")
        } else { verifier(false, "70 ms") }
        // réveil en retard : le mouvement le rattrape
        var r = GesteLucarne()
        r.appuyer(o, t: 0)
        verifier(r.bouger(PointLucarne(150, 200), t: 0.45) == [.decolle, .suit(PointLucarne(150, 200))], "réveil en retard : le mouvement décolle d'abord, puis suit")
        var r2 = GesteLucarne()
        r2.appuyer(o, t: 0)
        verifier(r2.relacher(o, t: 0.5) == [.decolle, .lacher(vx: 0, vy: 0)], "relâché après 0,4 s sans réveil : décolle puis lâche, jamais un clic")
        // interruption (dictée, réunion…)
        var i1 = GesteLucarne(); i1.appuyer(o, t: 0)
        var i2 = GesteLucarne(); i2.appuyer(o, t: 0); _ = i2.echeance(0.4)
        verifier(i1.interrompre() == [.annule] && i2.interrompre() == [.lacher(vx: 0, vy: 0)] && i2.interrompre() == [] && i2.phase == .repos, "interruption : appui annulé, tenue lâchée sans vitesse (retombe à la place la plus proche)")
        var n = GesteLucarne()
        n.appuyer(o, t: 0)
        n.appuyer(PointLucarne(5, 5), t: 5)
        verifier(n.depart == PointLucarne(5, 5) && abs((n.echeanceAppui ?? 0) - 5.4) < 1e-9, "un nouvel appui (relâchement perdu) repart de zéro")
        // tenue, elle passe sur un autre écran : le geste change de repère sans changer de vitesse
        var g0 = GesteLucarne(), g1 = GesteLucarne()
        for g in [0, 1] {
            var x = g == 0 ? g0 : g1
            x.appuyer(o, t: 0); _ = x.echeance(0.4)
            for i in 1...6 { _ = x.bouger(PointLucarne(Double(i) * 10, 0), t: 0.4 + Double(i) * 0.016) }
            if g == 0 { g0 = x } else { g1 = x }
        }
        g1.decaler(dx: -1470, dy: 120)
        verifier(g1.pointeur == PointLucarne(60 - 1470, 120) && g1.depart == PointLucarne(100 - 1470, 320), "changement d'écran : départ et pointeur dans le repère du nouvel écran")
        verifier(g0.relacher(PointLucarne(70, 0), t: 0.5) == g1.relacher(PointLucarne(70 - 1470, 120), t: 0.5), "… la vitesse du lancer ne change pas")
    }

    groupe("Lucarne : la mémoire des places")
    do {
        var m = MemoirePlaces()
        verifier(m.place(pour: "UUID-1") == .encoche, "écran inconnu : l'encoche")
        m.memoriser(.basGauche, pour: "UUID-1"); m.memoriser(.droite, pour: "UUID-2"); m.ecranChoisi = "UUID-2"
        verifier(m.place(pour: "UUID-1") == .basGauche && m.place(pour: "UUID-2") == .droite && m.place(pour: "UUID-3") == .encoche, "une place par écran")
        let json = m.donnees()
        verifier(MemoirePlaces.depuis(json) == m, "JSON aller-retour")
        verifier(String(decoding: json, as: UTF8.self).contains("basGauche"), "enregistrée en texte lisible")
        verifier(MemoirePlaces.depuis(Data("pas du json".utf8)) == nil && MemoirePlaces.depuis(Data()) == nil, "mémoire abîmée : nil (le défaut s'applique)")
        let future = Data(#"{"places":{"A":"hautDroite","B":"coinSecret"},"ecranChoisi":"A"}"#.utf8)
        let lue = MemoirePlaces.depuis(future)
        verifier(lue?.place(pour: "A") == .hautDroite && lue?.place(pour: "B") == .encoche, "une place inconnue (version future) retombe sur l'encoche sans perdre le reste")
        verifier(m.ecranChoisi(parmi: ["UUID-1", "UUID-2"]) == "UUID-2" && m.ecranChoisi(parmi: ["UUID-1"]) == nil, "écran choisi débranché : nil (on prend l'écran principal)")
        verifier(MemoirePlaces().ecranChoisi(parmi: ["UUID-1"]) == nil, "aucun écran choisi : nil")
        m.oublier("UUID-1")
        verifier(m.place(pour: "UUID-1") == .encoche, "oublier un écran")
        m.poser(.basDroite, sur: "UUID-3")
        verifier(m.place(pour: "UUID-3") == .basDroite && m.ecranChoisi == "UUID-3" && m.place(pour: "UUID-2") == .droite,
                 "lâchée sur un autre écran : sa place y est retenue, il devient le sien, les autres places restent")
        // sans encoche : la même mémoire, la place « encoche » est la pilule de verre en haut au milieu
        var sans = MemoirePlaces(); sans.memoriser(.encoche, pour: "EXTERNE")
        let c = G.replie(sans.place(pour: "EXTERNE"), externe)
        verifier(c.s > 0 && c.centreX == 0 && c.y0 == externe.yHaut, "écran sans encoche : « encoche » = pilule de verre en haut au milieu")
    }

    groupe("Lucarne : tailles repliées")
    do {
        verifier(G.tailleCompacte(contenu: 88, debout: false) == TailleLucarne(largeur: 120, hauteur: 36), "couchée : contenu 88 → 120 × 36")
        verifier(G.tailleCompacte(contenu: 10, debout: false).largeur == 72 && G.tailleCompacte(contenu: 900, debout: false).largeur == 260, "couchée : de 72 à 260 pt")
        verifier(G.tailleCompacte(contenu: 4, debout: true).largeur == 40 && G.tailleCompacte(contenu: 30, debout: true).largeur == 46 && G.tailleCompacte(contenu: 300, debout: true).largeur == 66, "debout : largeur mesurée entre 40 et 66 pt")
        verifier(G.tailleCompacte(contenu: 30, debout: true).hauteur == 112, "debout : 112 pt de haut")
        let large = G.replie(.hautDroite, macBook, taille: TailleLucarne(largeur: 200, hauteur: 36))
        verifier(large.largeur == 200 && abs(large.x1 - macBook.xMax) < 0.001, "pilule plus large : toujours calée sur le bord droit")
        let haute = G.replie(.droite, macBook, taille: TailleLucarne(largeur: 60, hauteur: 112))
        verifier(haute.largeur == 60 && abs(haute.x1 - macBook.xMax) < 0.001, "pilule debout plus large : toujours calée sur le bord")
    }

    groupe("Lucarne : le contenu hors de l'encoche")
    do {
        // le contenu suit le haut-milieu de la forme telle qu'elle est : posé, celui de la cible ; en route, il glisse avec elle
        for (nom, e) in faux {
            for p in PlaceLucarne.allCases where !(p == .encoche && e.avecEncoche) {
                let g = G.grand(p, e, largeur: 467, hauteur: 300, rayon: 34)
                let k = G.coinContenu(g)
                verifier(abs(k.x - g.centreX) < 0.001 && abs(k.y - g.y0) < 0.001, "\(nom), \(p.rawValue) : posé, le contenu en haut au milieu de la forme")
            }
        }
        let a = G.replie(.basDroite, macBook), b = G.grand(.basDroite, macBook, largeur: 467, hauteur: 300, rayon: 34)
        var saut = 0.0, avant = G.coinContenu(a)
        for i in 1...50 {
            let u = Double(i) / 50
            let c = CapsuleLucarne(x0: a.x0 + (b.x0 - a.x0) * u, x1: a.x1 + (b.x1 - a.x1) * u, y0: a.y0 + (b.y0 - a.y0) * u, y1: a.y1 + (b.y1 - a.y1) * u, s: 20, r: 20)
            let k = G.coinContenu(c); saut = max(saut, hypot(k.x - avant.x, k.y - avant.y)); avant = k
        }
        verifier(saut < 12, "de la pilule au déplié en 50 images : le contenu glisse avec la forme, jamais plus de 12 pt d'une image à l'autre (\(Int(saut)) pt)")

        groupe("Lucarne : la bulle de la deuxième activité")
        for (nom, e) in faux {
            for p in PlaceLucarne.allCases where !(p == .encoche && e.avecEncoche) {
                let r = G.replie(p, e), b = G.bulle(r, place: p, largeur: 74)
                let dedans = b.x0 >= e.xBordGauche && b.x1 <= e.xBordDroit && b.y0 >= e.barre && b.y1 <= e.hauteur
                let separee = p.debout ? abs(b.y0 - r.y1 - G.ecartBulle) < 0.001 : (abs(b.x0 - r.x1 - G.ecartBulle) < 0.001 || abs(r.x0 - b.x1 - G.ecartBulle) < 0.001)
                let interieur = p.debout || (p.ancre.x > 0.5 ? b.centreX < r.centreX : b.centreX > r.centreX)
                verifier(dedans && separee && interieur && !surDock(b, e), "\(nom), \(p.rawValue) : la bulle à côté, vers l'intérieur, dans l'écran, hors du Dock")
            }
        }
        let r = G.replie(.hautDroite, macBook), rentree = G.bulle(r, place: .hautDroite, largeur: 74, sortie: 0)
        verifier(abs(rentree.centreX - r.centreX) < 0.001 && rentree.largeur < r.largeur && rentree.hauteur < r.hauteur, "bulle rentrée : cachée sous le milieu de la pilule")
        verifier(G.bulle(r, place: .hautDroite, largeur: 74, sortie: 1.2) == G.bulle(r, place: .hautDroite, largeur: 74), "le rebond de la sortie ne la pousse pas au-delà de sa place (la fenêtre la contient)")

        groupe("Lucarne : le verre Liquide reste lisible (voile léger + halo sous le contenu, comme iOS 26)")
        let V = VerreLucarne.self
        func ct(_ l: (r: Double, g: Double, b: Double), _ o: Double = 1, voile: Double = V.voileDeplie, fond: Double = 1) -> Double {
            V.contraste(lettre: l, opacite: o, voile: voile, fond: fond)
        }
        func f(_ x: Double) -> String { String(format: "%.1f", x) }
        let rouge = (1.0, 0x45 / 255.0, 0x3A / 255.0), bleu = (0x0A / 255.0, 0x84 / 255.0, 1.0)
        verifier(V.voilePilule == 0 && V.voileDeplie == 0, "le verre se voit au travers : aucun voile (\(V.voilePilule), \(V.voileDeplie))")
        verifier(V.verreClair && V.intensite(deplie: 0) == V.intensitePilule && V.intensite(deplie: 1) == V.intensiteDeplie && V.intensite(deplie: 2) == V.intensiteDeplie
                 && V.intensitePilule <= 0.35 && V.intensiteDeplie <= 0.6 && V.intensitePilule <= V.intensiteDeplie,
                 "« vraiment beaucoup plus transparent » (12/11 soir) : le verre système clair, atténué (pilule \(V.intensitePilule), déplié \(V.intensiteDeplie))")
        verifier(V.halo.rayonPres <= 1 && V.halo.rayonLarge <= 2, "halo serré autour des glyphes (\(V.halo.rayonPres) et \(V.halo.rayonLarge) pt) : jamais une plaque floutée")
        verifier(V.contraste(lettre: (1, 1, 1), voile: V.voileDeplie, halo: 0, fond: 1) < 2, "sans halo, le blanc sur une page blanche ne se lirait pas : le halo est indispensable")
        verifier(ct((1, 1, 1)) >= 4.5 && ct((1, 1, 1), voile: V.voilePilule) >= 4.5, "texte blanc sur page blanche, avec halo : ≥ 4,5 (\(f(ct((1, 1, 1)))), pilule \(f(ct((1, 1, 1), voile: V.voilePilule))))")
        verifier(ct((1, 1, 1), 0.6) >= 2.5, "texte gris (60 %) ≥ 2,5 (\(f(ct((1, 1, 1), 0.6))))")
        verifier(ct(rouge) >= 2 && ct(bleu) >= 1.9, "rouge et bleu système dans une carte ≥ 1,9 sur page blanche (\(f(ct(rouge))), \(f(ct(bleu))))")
        let rv = V.rougeVerre
        verifier(ct(rv, voile: V.voilePilule) >= 2.1 && ct(rv, voile: V.voilePilule) > ct(rouge, voile: V.voilePilule),
                 "rouge « verre » de la pilule (« Coupé », en gras) : ≥ 2,1 et mieux que celui fait pour le noir (\(f(ct(rv, voile: V.voilePilule))))")
        verifier(ct((1, 1, 1), fond: 0) >= 15, "sur fond noir : comme l'encoche")
    }
}
