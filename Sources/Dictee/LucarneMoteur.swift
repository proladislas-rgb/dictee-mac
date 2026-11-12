import AppKit
import SwiftUI
import DicteeCore

// La Lucarne déplaçable dans le moteur (docs/plan-lucarne-deplacable.md) : un appui long de 0,4 s sur la forme (même dans l'encoche) la
// décolle ; elle suit le pointeur au point près ; lâchée (ou lancée), elle se pose sur l'une des huit places aimantées ; ramenée près de
// l'encoche, elle y est aspirée et reprend la forme noire de l'encoche. La place est retenue pour chaque écran.
// Hors de l'encoche (mission 3), la forme est de verre : repliée, une pilule avec le contenu compact ; dépliée (survol, clic, alerte,
// bandeau, dépôt de fichiers), elle grandit vers l'intérieur de l'écran depuis sa place, avec les écrans de l'encoche dedans.
// Énergie : aucune minuterie au repos ; un seul réveil pour les 0,4 s de l'appui (l'anneau s'anime seul, sans la boucle) ; la boucle tourne
// seulement pendant qu'un ressort bouge ; pendant la tenue et le vol, la fenêtre suit (son origine seulement) sans que SwiftUI ne redessine.

/// Où en est la Lucarne : sa place, sa forme hors de l'encoche, le geste en cours.
struct EtatLucarne {
    /// Ce qu'elle lit et écrit du système (l'écran, le Dock, la mémoire des places, la vibration) : l'essai le remplace.
    var systeme = SystemeLucarne()
    /// L'écran où elle vit (repère de la Lucarne) et sa clé dans la mémoire des places.
    var ecran: EcranLucarne?
    var uuid = ""
    var place = PlaceLucarne.encoche
    /// Le régime libre (toute place autre que l'encoche) : la capsule est dessinée au lieu de la forme de l'encoche.
    var libre = false
    var capsule = RessortsCapsule(CapsuleLucarne(x0: 0, x1: 0, y0: 0, y1: 0, s: 0, r: 0))
    var geste = GesteLucarne()
    /// Décollée d'une encoche dépliée (Centre, carte) : elle attend que la forme de l'encoche soit repliée pour passer en régime libre
    /// (une capsule ne sait pas dessiner le cou étroit dans la barre des menus : partie dépliée, elle couvrirait les icônes voisines).
    var repli = false
    /// Tenue près de l'encoche (elle en prend la forme, noire) ; nil au décollage, tant que la forme tenue n'est pas choisie.
    var pres: Bool?
    /// Lâchée, elle vole vers sa place ; `aspiree` : vers l'encoche, dont elle reprend le régime à l'arrivée.
    var vol = false
    var aspiree = false
    /// La taille de la fenêtre pendant la tenue et le vol : fixe, seule son origine suit la capsule.
    var tailleVol = CGSize.zero
    /// Posée : le point de l'écran dessiné au milieu de la zone de dessin (le centre de la pilule à son arrivée). La vue ne bouge plus
    /// tant qu'elle est posée : la forme y grandit et s'y replie, la fenêtre se cale autour.
    var centreVue = PointLucarne(0, 0)
    /// Le bouton enfoncé sur la vue de l'îlot (point, heure de l'événement), en attendant que le geste SwiftUI de la forme dise « sur la
    /// forme, hors d'un bouton » ; et le dernier mouvement d'ici là.
    var bouton: (p: PointLucarne, t: Double)?
    var dernier: (p: PointLucarne, t: Double)?
    /// Le geste SwiftUI vient de dire « sur la forme » pour l'événement en cours, avant que la vue d'hébergement ne le reçoive (SwiftUI
    /// voit les événements de la fenêtre avant ses vues) ; oublié à la fin de cet événement.
    var surForme = false
    /// Le réveil des 0,4 s, et le garde-fou d'un relâchement perdu pendant la tenue.
    var reveil: DispatchWorkItem?
    var garde: DispatchWorkItem?
    /// Tenue ou vol : la fenêtre doit suivre la capsule (le panneau déplace son origine).
    var surDeplacement: () -> Void = {}
}

extension IlotMoteur {
    // MARK: repère de la vue

    /// La zone de dessin du régime libre : assez grande pour la plus grande carte posée depuis n'importe quelle place autour du centre de
    /// sa pilule (467 pt de large depuis un bord, 348 pt de haut au-dessus de la ligne d'un Dock aux icônes de 128 pt), plus l'ombre.
    static let tailleLibre = CGSize(width: 1000, height: 900)
    /// En régime libre, la vue dessine le point `centreVue` (ou, tenue et en vol, le centre de la capsule) au milieu de sa zone.
    static let milieuLibre = Double(tailleLibre.height) / 2
    /// Rayon de l'anneau de l'appui long (maquette : cercle de 11 pt, trait de 3) et ce qu'il prend autour du pointeur.
    static let rayonAnneau: CGFloat = 11
    static let margeAnneau: CGFloat = 14
    /// L'anneau n'apparaît qu'après ce délai : un clic ordinaire (plus court) ne le montre jamais.
    static let delaiAnneau = 0.12
    /// Autour de la capsule tenue ou en vol : la place de l'ombre du « levé ».
    static let margeVol: CGFloat = 24

    /// La taille de la zone de dessin (celle de l'encoche, ou celle du régime libre).
    var tailleVue: CGSize { lucarne.libre ? Self.tailleLibre : CGSize(width: Self.largeur, height: Self.hauteurMax) }
    /// Tenue ou en vol : la fenêtre suit la capsule (pas pendant le repli qui précède le décollage : elle est encore posée).
    var lucarneEnMain: Bool { lucarne.libre && ((lucarne.geste.phase == .decollee && !lucarne.repli) || lucarne.vol) }

    /// Le point de l'écran (repère de la Lucarne) dessiné en haut au milieu de la vue : l'encoche (0, 0) ; en régime libre, le centre de
    /// la capsule tenue ou en vol (la vue ne bouge jamais dans la fenêtre), `centreVue` posée.
    var origineVue: CGPoint {
        guard lucarne.libre else { return .zero }
        let c = lucarneEnMain ? PointLucarne(lucarne.capsule.cx.x, lucarne.capsule.cy.x) : lucarne.centreVue
        return CGPoint(x: c.x, y: c.y - Self.milieuLibre)
    }
    /// Un point de la vue (x depuis son milieu, y depuis son haut) dans le repère de la Lucarne.
    func depuisVue(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x + origineVue.x, y: p.y + origineVue.y) }
    /// Un point du repère de la Lucarne à poser dans la vue (`.position` : x depuis son bord gauche, y depuis son haut).
    func positionVue(_ p: PointLucarne) -> CGPoint {
        CGPoint(x: CGFloat(p.x) - origineVue.x + tailleVue.width / 2, y: CGFloat(p.y) - origineVue.y)
    }
    /// Une capsule du repère de la Lucarne dans celui de la vue, pour `FormeNoire` (x depuis le milieu de la vue, y depuis son haut).
    func capsuleVue(_ c: CapsuleLucarne) -> CapsuleLucarne {
        let o = origineVue
        return CapsuleLucarne(x0: c.x0 - o.x, x1: c.x1 - o.x, y0: c.y0 - o.y, y1: c.y1 - o.y, s: c.s, r: c.r)
    }
    /// La capsule dessinée (levée : 4 % plus grande), dans le repère de la vue.
    var capsuleVue: CapsuleLucarne { capsuleVue(lucarne.capsule.affichee) }
    /// L'anneau de l'appui long : son centre dans la vue et son heure de départ ; nil hors de l'appui. Il s'anime seul (une horloge
    /// d'animation dans sa propre vue, le temps de l'appui) : rien d'autre n'est redessiné.
    var anneauAppui: (centre: CGPoint, debut: Double)? {
        guard lucarne.geste.phase == .appui else { return nil }
        return (positionVue(lucarne.geste.pointeur), lucarne.geste.debut)
    }
    /// Un appui ou une tenue en cours : la fenêtre garde la souris (pas de clic qui traverse, pas de survol).
    var lucarneOccupee: Bool { lucarne.bouton != nil || lucarne.geste.phase != .repos }
    /// Plus rien ne bouge côté Lucarne (pas de ressort, pas de vol, pas de repli attendu).
    var lucarnePosee: Bool { !lucarne.vol && !lucarne.repli && (!lucarne.libre || lucarne.capsule.fini) }

    // MARK: la forme posée hors de l'encoche

    /// La pilule repliée de sa place, à la taille de son contenu compact (celui de l'écran visé, ou le logo). Sans caméra, la place du
    /// haut au milieu est elle aussi une pilule de verre (décision A).
    func capsuleRepliee(_ e: EcranLucarne) -> CapsuleLucarne {
        let debout = lucarne.place.debout
        let g = GenreCompact.de(courante) ?? .logo
        return GeoLucarne.replie(lucarne.place, e, taille: GeoLucarne.tailleCompacte(contenu: largeurCompacte(g, debout: debout), debout: debout))
    }
    /// La forme voulue hors de l'encoche : ce que vise la forme de l'encoche (géométrie `geo`), sans le cou ni les épaules — dépliée,
    /// une boîte de la largeur du corps et de la hauteur sous la barre, qui grandit vers l'intérieur depuis sa place ; repliée, la pilule.
    func capsuleLibreVoulue(_ e: EcranLucarne) -> CapsuleLucarne {
        let c = geo.map(\.cibleFinale), barre = Double(geometrie.hauteur), profondeur = c[2] - barre
        guard profondeur > 0.5 else { return capsuleRepliee(e) }
        return GeoLucarne.grand(lucarne.place, e, largeur: 2 * (Double(demiCamera) + c[1]), hauteur: profondeur, rayon: c[4])
    }
    /// Hors de l'encoche, la forme vise ce que l'îlot montre (appelé après chaque changement des données). Pas pendant la tenue ni le vol :
    /// c'est le geste qui mène.
    func viserLucarne() {
        guard lucarne.libre, !lucarneEnMain, let e = lucarne.ecran else { return }
        let voulue = capsuleLibreVoulue(e), cible = lucarne.capsule.cible
        guard voulue != cible else { return }
        let ouvre = voulue.largeur * voulue.hauteur > cible.largeur * cible.hauteur
        lucarne.capsule.viser(voulue, passage: ouvre ? .ouverture : .fermeture, reduire: reduire)
    }
    /// La forme vise-t-elle un repli (rien sous la barre, dans l'encoche) ?
    var lucarneVisePlie: Bool { geo[2].cibleFinale - Double(geometrie.hauteur) <= 0.5 }
    /// Le contenu déplié est-il à dessiner ? Posée, quand la forme vise un déplié ou n'est pas encore revenue à sa pilule.
    var lucarneDepliee: Bool { lucarneDeplie > 0 || (lucarne.libre && !lucarneEnMain && !lucarneVisePlie) }
    /// Dépliée (pour l'ombre et le contenu) : 0 sur la pilule, 1 dès 30 pt d'écart avec elle ; continu dans les deux sens. Une pilule
    /// visée se compare à elle-même : posée, c'est exactement 0.
    var lucarneDeplie: Double {
        guard lucarne.libre, !lucarneEnMain, let e = lucarne.ecran else { return 0 }
        let a = lucarne.capsule.affichee, p = lucarneVisePlie ? lucarne.capsule.cible : capsuleRepliee(e)
        let ecart = max(abs(a.largeur - p.largeur), abs(a.hauteur - p.hauteur))
        return ecart < 0.01 ? 0 : min(1, ecart / 30)
    }
    /// Tenue ou aspirée près de l'encoche : la forme est celle de l'encoche (noire) et son contenu compact est dans ses ailes, comme dans
    /// l'encoche (pas au milieu, sous la caméra) : au décollage comme à l'arrivée, rien ne disparaît d'un coup.
    var lucarneAilesEncoche: Bool { lucarne.libre && (lucarne.pres == true || lucarne.aspiree) }
    /// Pilule debout (milieu des bords) : décidée par la forme visée, pour que le contenu se mette debout en même temps qu'elle.
    var lucarneDebout: Bool { let c = lucarne.capsule.cible; return c.hauteur > c.largeur }
    /// Le haut-milieu du contenu déplié (repère de la Lucarne) : celui de la forme telle qu'elle est (`GeoLucarne.coinContenu`).
    var coinContenuLibre: PointLucarne { GeoLucarne.coinContenu(lucarne.capsule.valeur) }
    /// Où poser `IlotCalques` (sa zone de 800 × 380, contenu en (0, barre) au haut-milieu du contenu) dans la vue libre ; près de
    /// l'encoche, dans sa forme : le point (0, 0) de l'encoche au haut-milieu de la capsule.
    var origineCalques: CGPoint? {
        guard lucarne.libre else { return nil }
        let k = lucarneAilesEncoche ? PointLucarne(lucarne.capsule.cx.x, lucarne.capsule.affichee.y0 + Double(geometrie.hauteur)) : coinContenuLibre
        let p = positionVue(k)
        return CGPoint(x: p.x - Self.largeur / 2, y: p.y - geometrie.hauteur)
    }
    /// Un point de l'écran (repère de la Lucarne) dans le repère des écrans de l'encoche (x depuis le milieu du contenu, y depuis le haut de
    /// l'écran, la barre comprise) : les tests de position du contenu (liste des Dictées, zones de l'étagère) le reçoivent. Identique
    /// dans l'encoche.
    func versContenu(_ p: CGPoint) -> CGPoint {
        guard lucarne.libre else { return p }
        let k = coinContenuLibre
        return CGPoint(x: p.x - CGFloat(k.x), y: p.y - CGFloat(k.y) + geometrie.hauteur)
    }

    /// L'inverse : un point des écrans de l'encoche dans le repère de la Lucarne (essais : où cliquer un bouton du Centre dans le verre).
    func depuisContenu(_ p: CGPoint) -> CGPoint {
        guard lucarne.libre else { return p }
        let k = coinContenuLibre
        return CGPoint(x: p.x + CGFloat(k.x), y: p.y + CGFloat(k.y) - geometrie.hauteur)
    }

    /// La bulle de la deuxième activité hors de l'encoche (repère de la Lucarne), posée ou en train de sortir ; nil sans bulle, pendant la
    /// tenue et le vol.
    var bulleLibre: CapsuleLucarne? {
        guard lucarne.libre, !lucarneEnMain, lucarneVisePlie, let a = pastille, pastilleChute.x > 0.005 else { return nil }
        // elle sort de la pilule visée (jamais à côté d'un déplié qui se replie)
        return GeoLucarne.bulle(lucarne.capsule.cible, place: lucarne.place, largeur: largeurBulleLibre(a), sortie: pastilleChute.x)
    }
    var bulleLibreVue: CapsuleLucarne? { bulleLibre.map(capsuleVue) }
    /// Couchée : son contenu et 10 pt de chaque côté (la bulle de l'encoche) ; debout, la largeur de la pilule.
    func largeurBulleLibre(_ a: ActiviteIlot) -> Double {
        largeurCompacte(.activite(a), debout: lucarne.place.debout) + 20
    }

    // MARK: mesures

    /// La capsule libre (ou sa bulle sortie) contient-elle ce point (repère de la Lucarne) ?
    func contientLibre(_ p: CGPoint) -> Bool {
        if let b = rectBulleLibre(), b.contains(p) { return true }
        return cheminLibre(lucarne.capsule.affichee).contains(p)
    }
    /// La forme visée, élargie de `marge` points tout autour (la zone de dépôt ne se perd pas en la visant).
    func contientLibre(_ p: CGPoint, marge: CGFloat) -> Bool {
        let chemin = cheminLibre(lucarne.capsule.cible)
        return chemin.contains(p) || chemin.strokedPath(StrokeStyle(lineWidth: 2 * marge, lineCap: .round, lineJoin: .round)).contains(p)
    }
    private func cheminLibre(_ c: CapsuleLucarne) -> Path {
        FormeNoire(points: TraceLucarne.calculer(c)).path(in: CGRect(x: -IlotMoteur.largeur / 2, y: 0, width: IlotMoteur.largeur, height: IlotMoteur.hauteurMax))
    }
    /// La bulle sortie (au moins à moitié), où elle prend la souris.
    func rectBulleLibre() -> CGRect? {
        guard pastilleMontree, pastilleChute.x >= 0.5, let b = bulleLibre else { return nil }
        return CGRect(x: b.x0, y: b.y0, width: b.largeur, height: b.hauteur)
    }

    /// La fenêtre en régime libre (repère de la Lucarne). Tenue et vol : une taille fixe centrée sur la capsule (seule l'origine suit),
    /// l'anneau de l'appui y tient. Posée : la pilule et la forme visée (et la bulle), avec la place de l'ombre ; la fenêtre grandit tout
    /// de suite et ne rétrécit que 0,65 s plus tard, le temps que la forme se referme (`IlotPanneau.ajuster`). Marges (plus larges que
    /// dans l'encoche, qui n'a pas d'ombre repliée) : 8 sur les côtés, 6 en haut, 12 en bas repliée ; 20, 12 et 32 dépliée.
    func fenetreLibre() -> CGRect {
        let c = lucarne.capsule
        if lucarneEnMain {
            let cx = CGFloat(c.cx.x), cy = CGFloat(c.cy.x)
            return CGRect(x: cx - lucarne.tailleVol.width / 2, y: cy - lucarne.tailleVol.height / 2, width: lucarne.tailleVol.width, height: lucarne.tailleVol.height)
        }
        guard let e = lucarne.ecran else { return .zero }
        func rect(_ k: CapsuleLucarne) -> CGRect { CGRect(x: k.x0, y: k.y0, width: k.largeur, height: k.hauteur) }
        let p = capsuleRepliee(e), v = c.cible
        var r = rect(p).union(rect(v))
        if pastilleMontree, let a = pastille { r = r.union(rect(GeoLucarne.bulle(p, place: lucarne.place, largeur: largeurBulleLibre(a))).insetBy(dx: -4, dy: -4)) }
        let deplie = v.hauteur > p.hauteur + 0.5
        let (cote, haut, bas): (CGFloat, CGFloat, CGFloat) = deplie ? (20, 12, 32) : (8, 6, 12)
        r = CGRect(x: r.minX - cote, y: r.minY - haut, width: r.width + 2 * cote, height: r.height + haut + bas)
        guard lucarne.geste.phase == .appui else { return r }
        let q = lucarne.geste.pointeur, m = Self.margeAnneau
        return r.union(CGRect(x: CGFloat(q.x) - m, y: CGFloat(q.y) - m, width: 2 * m, height: 2 * m))
    }
    /// Dans l'encoche : la fenêtre voulue, plus l'anneau de l'appui long (jamais au-dessus du haut de l'écran).
    func avecAnneau(_ r: CGRect) -> CGRect {
        guard lucarne.geste.phase == .appui else { return r }
        let p = lucarne.geste.pointeur, m = Self.margeAnneau
        let a = CGRect(x: CGFloat(p.x) - m, y: max(0, CGFloat(p.y) - m), width: 2 * m, height: CGFloat(p.y) + m - max(0, CGFloat(p.y) - m))
        return r.union(a)
    }

    /// La forme de l'encoche telle qu'elle est (au décollage) ou telle qu'elle sera (le retour), en capsule. Repliée seulement : une
    /// forme dépliée n'a pas de capsule fidèle (son cou).
    func capsuleEncoche(cible: Bool) -> CapsuleLucarne {
        cible ? .encoche(traceCible, epaule: geo[3].cibleFinale, coin: geo[4].cibleFinale) : .encoche(trace, epaule: geo[3].x, coin: geo[4].x)
    }
    /// La forme compacte de l'encoche (celle de la lecture repliée), en géométrie et en capsule : le retour par aspiration y arrive quand
    /// l'encoche veut un déplié (une alerte arrivée pendant que la Lucarne était ailleurs), puis s'ouvre depuis elle.
    private var geoCompacte: [Double] {
        GeoIlot.valeurs(.lectureCompact, hauteurBarre: Double(geometrie.hauteur), demiCamera: Double(demiCamera))
    }
    private var capsuleCompacte: CapsuleLucarne {
        let g = geoCompacte
        return .encoche(TraceIlot.calculer(g, demiCamera: Double(demiCamera), barre: Double(geometrie.hauteur)), epaule: g[3], coin: g[4])
    }
    /// La forme de départ est à un demi-point de sa cible (la queue du ressort, invisible, peut durer encore une demi-seconde) : celle
    /// de l'encoche, ou la capsule libre.
    private var quasiRepliee: Bool {
        if lucarne.libre {
            let a = lucarne.capsule.valeur, c = lucarne.capsule.cible
            return max(abs(a.x0 - c.x0), abs(a.x1 - c.x1), abs(a.y0 - c.y0), abs(a.y1 - c.y1)) < 0.5
        }
        return geo.allSatisfy { abs($0.x - $0.cibleFinale) < 0.5 }
    }
    /// L'encoche vise-t-elle un déplié (quelque chose sous la barre) ?
    private var encocheDepliee: Bool { traceCible.hauteur > Double(geometrie.hauteur) + 0.5 }

    // MARK: écran et mémoire

    /// L'écran est mesuré (démarrage, écran changé) : la Lucarne est posée à sa place, sans animation. Tenue à ce moment-là, elle tombe
    /// à la place la plus proche (retenue) ; un geste en cours s'arrête.
    func poserLucarne(_ e: EcranLucarne, uuid: String, place: PlaceLucarne) {
        var place = place
        if lucarne.libre, lucarne.geste.phase == .decollee || lucarne.vol, uuid == lucarne.uuid {
            let c = lucarne.capsule.valeur
            place = GeoLucarne.plusProche(x: c.centreX, y: c.centreY, e)
            var memoire = lucarne.systeme.lireMemoire()
            memoire.memoriser(place, pour: uuid)
            lucarne.systeme.ecrireMemoire(memoire)
        }
        lucarne.reveil?.cancel(); lucarne.reveil = nil
        lucarne.garde?.cancel(); lucarne.garde = nil
        lucarne.geste = GesteLucarne(); lucarne.bouton = nil; lucarne.dernier = nil
        appuyer(false)
        lucarne.ecran = e; lucarne.uuid = uuid; lucarne.place = place
        lucarne.vol = false; lucarne.aspiree = false; lucarne.pres = nil; lucarne.repli = false
        // sans caméra, la place du haut au milieu est une pilule de verre, visible même vide (décision A) : jamais cachée, introuvable
        lucarne.libre = place != .encoche || !e.avecEncoche
        if lucarne.libre {
            lucarne.capsule = RessortsCapsule(capsuleLibreVoulue(e), noir: 0)
            lucarne.centreVue = PointLucarne(lucarne.capsule.cx.x, lucarne.capsule.cy.x)
        }
        demarrerBoucle()
    }

    // MARK: le geste (événements de la vue d'hébergement : point global de l'événement, heure de l'événement)

    /// Le bouton s'enfonce sur la vue : on retient le point ; le geste SwiftUI de la forme dira s'il est sur elle (`appuiSurForme`).
    func sourisBas(_ p: PointLucarne, t: Double) {
        // un appui resté en plan (relâchement jamais reçu) : il s'arrête avant le nouveau
        if lucarne.geste.phase != .repos { traiter(lucarne.geste.interrompre()) }
        lucarne.bouton = (p, t); lucarne.dernier = nil
        if lucarne.surForme { lucarne.surForme = false; commencerAppui() }
    }
    func sourisGlisse(_ p: PointLucarne, t: Double) {
        if lucarne.geste.phase == .repos { if lucarne.bouton != nil { lucarne.dernier = (p, t) }; return }
        traiter(lucarne.geste.bouger(p, t: t))
    }
    func sourisHaut(_ p: PointLucarne, t: Double) {
        lucarne.bouton = nil; lucarne.dernier = nil
        guard lucarne.geste.phase != .repos else { return }
        traiter(lucarne.geste.relacher(p, t: t))
    }

    /// Le geste SwiftUI dit « sur la forme » : l'appui commence si la vue d'hébergement a déjà le bouton ; sinon (SwiftUI passe d'abord)
    /// elle le commencera en le recevant, dans le même événement. Un appui sur une vue AppKit de l'îlot (la miniature d'une capture) ne
    /// passe pas par la vue d'hébergement : rien ne commence, la marque est oubliée à la fin de l'événement.
    func formeAppuyee() {
        // `.annulee` : l'appui d'avant n'a jamais reçu son relâchement (un glisser de fichier l'a gardé) ; le nouveau le remplace
        guard lucarne.geste.phase == .repos || lucarne.geste.phase == .annulee else { return }
        if lucarne.bouton != nil { commencerAppui(); return }
        lucarne.surForme = true
        DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.lucarne.surForme = false } }
    }

    /// L'appui est sur la forme : l'îlot gonfle un peu, l'anneau se remplit sous le pointeur (il s'anime seul), un seul réveil à 0,4 s.
    func commencerAppui() {
        guard let b = lucarne.bouton else { return }
        // le bouton ne sert qu'une fois : un appui resté en plan ne relance jamais un geste avec son vieux point
        lucarne.bouton = nil
        lucarne.geste.appuyer(b.p, t: b.t)
        appuyer(true)
        let echeance = b.t + GeoLucarne.dureeAppui
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.traiter(self.lucarne.geste.echeance(max(ProcessInfo.processInfo.systemUptime, echeance)))
            }
        }
        lucarne.reveil?.cancel(); lucarne.reveil = item
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, echeance - ProcessInfo.processInfo.systemUptime), execute: item)
        if let d = lucarne.dernier { lucarne.dernier = nil; traiter(lucarne.geste.bouger(d.p, t: d.t)) }
        surFenetre(); demarrerBoucle()
    }

    /// Dictée, réunion, annonce qui efface l'îlot : l'appui s'oublie, une tenue retombe à la place la plus proche.
    func interrompreLucarne() {
        lucarne.bouton = nil; lucarne.dernier = nil
        traiter(lucarne.geste.interrompre())
    }

    private func traiter(_ evenements: [GesteLucarne.Evenement]) {
        for e in evenements {
            switch e {
            case .decolle: decoller()
            case .annule: finAppui()
            case .clic: finAppui(); clicForme()
            case .suit(let p): suivre(p)
            case .lacher(let vx, let vy): lacher(vx: vx, vy: vy)
            }
        }
    }

    private func finAppui() {
        lucarne.reveil?.cancel(); lucarne.reveil = nil
        appuyer(false)
        surFenetre(); demarrerBoucle()
    }

    /// 0,4 s d'appui : le Centre (ou une carte) se range, une vibration ; elle se décolle une fois repliée (`decollerDuRepli`), dans
    /// l'encoche comme ailleurs. Une alerte ou un bandeau (que « fermer » ne range pas) ne se déplace pas : il attend un geste ou sa fin,
    /// l'appui s'arrête.
    private func decoller() {
        guard lucarne.ecran != nil else { return }
        lucarne.reveil?.cancel(); lucarne.reveil = nil
        appuyer(false)
        // pendant le rangement, la forme libre n'est pas « en main » : elle vise sa pilule comme posée
        lucarne.repli = true
        if fenetreOuverte { fermer() }
        lucarne.repli = false
        if lucarne.libre ? !lucarneVisePlie : encocheDepliee {
            lucarne.geste = GesteLucarne()
            surFenetre(); demarrerBoucle()
            return
        }
        lucarne.systeme.vibrer()
        surveillerTenue()
        if !quasiRepliee {
            lucarne.repli = true
            surFenetre(); demarrerBoucle()
            return
        }
        decollerDuRepli()
    }

    /// La forme de départ est repliée (la forme compacte de l'encoche, ou la pilule) : régime libre, prise sur la forme actuelle, levée ; le point
    /// tenu glisse doucement vers le milieu de la pilule (la forme rejoint le doigt sans saut s'il a bougé pendant le repli).
    private func decollerDuRepli() {
        guard let e = lucarne.ecran else { return }
        lucarne.repli = false
        let depart = lucarne.libre ? lucarne.capsule.valeur : capsuleEncoche(cible: false)
        if !lucarne.libre { lucarne.libre = true; lucarne.capsule = RessortsCapsule(depart, noir: 1) }
        lucarne.vol = false; lucarne.aspiree = false; lucarne.pres = nil
        lucarne.capsule.saisir(pointeur: lucarne.geste.pointeur)
        lucarne.capsule.lever()
        if reduire { lucarne.capsule.leve.poser(); lucarne.capsule.decalX.poser(); lucarne.capsule.decalY.poser() }
        // assez grande pour tout ce qu'elle peut devenir d'ici son arrivée (la forme de départ, celle de l'encoche, les pilules), levée
        let ailes = 2 * ((e.demiCamera ?? 0) + GeoLucarne.ailesCompactes + GeoLucarne.epaulesCompactes)
        let l = max(depart.largeur, ailes, GeoLucarne.pilule.largeur, GeoLucarne.pilouleDebout.largeur)
        let h = max(depart.hauteur, e.barre, GeoLucarne.pilule.hauteur, GeoLucarne.pilouleDebout.hauteur)
        lucarne.tailleVol = CGSize(width: ceil(CGFloat(l * GeoLucarne.echelleTenue)) + 2 * Self.margeVol,
                                   height: ceil(CGFloat(h * GeoLucarne.echelleTenue)) + 2 * Self.margeVol)
        suivre(lucarne.geste.pointeur)
        surveillerTenue()
        surFenetre(); demarrerBoucle()
    }

    /// Tenue : elle suit le pointeur 1:1 ; près de l'encoche, elle en prend la forme (noire), ailleurs une pilule.
    private func suivre(_ p: PointLucarne) {
        guard lucarne.libre, !lucarne.repli, let e = lucarne.ecran else { return }
        let c = lucarne.capsule
        let t = GeoLucarne.tenue(pointeur: p, decalage: c.decalage, hw: c.hw.x, hh: c.hh.x, e)
        lucarne.capsule.suivre(cx: t.cx, cy: t.cy)
        if t.pres != lucarne.pres {
            lucarne.pres = t.pres
            let forme = t.pres ? GeoLucarne.replie(.encoche, e)
                               : .pilule(cx: 0, cy: 0, largeur: GeoLucarne.pilule.largeur, hauteur: GeoLucarne.pilule.hauteur)
            lucarne.capsule.viser(forme, passage: t.pres ? .tenueEncoche : .tenueVerre, reduire: reduire)
            demarrerBoucle()
        }
        lucarne.surDeplacement()
    }

    /// Lâchée : l'encoche si elle y est aimantée, la place dans la direction d'un lancer, sinon la plus proche ; le ressort garde la
    /// vitesse du geste. La place est retenue pour cet écran. Relâchée pendant le repli de l'encoche : elle y reste.
    private func lacher(vx: Double, vy: Double) {
        guard let e = lucarne.ecran else { return }
        lucarne.garde?.cancel(); lucarne.garde = nil
        if lucarne.repli { lucarne.repli = false; surFenetre(); demarrerBoucle(); return }
        // un appui arrêté au décollage (une alerte occupe l'encoche) : rien ne vole
        guard lucarne.libre else { return }
        let c = lucarne.capsule.valeur
        let place = GeoLucarne.placeLachee(cx: c.centreX, cy: c.centreY, vx: vx, vy: vy, pres: lucarne.pres == true, e)
        lucarne.capsule.reposer()
        lucarne.capsule.decalX.poser(); lucarne.capsule.decalY.poser()
        if reduire { lucarne.capsule.leve.poser() }
        let v = PointLucarne(vx, vy)
        lucarne.place = place
        // sans caméra, la place du haut au milieu est une pilule de verre : jamais aspirée dans une fausse encoche où elle disparaîtrait
        lucarne.aspiree = place == .encoche && e.avecEncoche
        if lucarne.aspiree {
            lucarne.capsule.viser(encocheDepliee ? capsuleCompacte : capsuleEncoche(cible: true), passage: .aspiration, vitesse: v, reduire: reduire)
        } else {
            lucarne.capsule.viser(capsuleRepliee(e), passage: .atterrissage, vitesse: v, reduire: reduire)
        }
        lucarne.vol = true; lucarne.pres = nil
        var memoire = lucarne.systeme.lireMemoire()
        memoire.memoriser(place, pour: lucarne.uuid)
        lucarne.systeme.ecrireMemoire(memoire)
        if lucarne.capsule.fini { finVol() } else { surFenetre(); demarrerBoucle() }
    }

    /// Arrivée : sur l'encoche, elle reprend son régime (la forme de l'encoche, sans saut ; dépliée si l'encoche le veut, en s'ouvrant
    /// depuis la forme compacte) ; ailleurs, la vue se fixe sur elle et la forme vise ce que l'îlot montre.
    private func finVol() {
        // posée exactement sur sa cible : AppKit arrondit le cadre de la fenêtre vers l'extérieur (44,0000001 pt deviendrait 45)
        lucarne.capsule.poser()
        lucarne.vol = false
        if lucarne.aspiree {
            lucarne.aspiree = false; lucarne.libre = false
            if encocheDepliee {
                let cibles = geo.map(\.cibleFinale), depart = geoCompacte
                for i in geo.indices { geo[i].x = depart[i]; geo[i].v = 0 }
                PassageIlot.viser(&geo, vers: cibles, reduire: reduire)
            }
        } else {
            lucarne.centreVue = PointLucarne(lucarne.capsule.cx.x, lucarne.capsule.cy.x)
            viserLucarne()
        }
        surFenetre(); demarrerBoucle()
    }

    /// Pendant la tenue seulement : le relâchement a pu se perdre (une autre app a pris la souris) ; le bouton remonté, elle est lâchée.
    private func surveillerTenue() {
        lucarne.garde?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.lucarne.geste.phase == .decollee else { return }
                if self.boutonEnfonce() { self.surveillerTenue(); return }
                self.lucarne.bouton = nil; self.lucarne.dernier = nil
                self.traiter(self.lucarne.geste.relacher(self.lucarne.geste.pointeur, t: ProcessInfo.processInfo.systemUptime))
            }
        }
        lucarne.garde = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: item)
    }

    // MARK: ressorts

    /// Une image de la boucle. Vrai si la vue doit être redessinée (la forme a changé) : le centre seul ne redessine rien pendant la
    /// tenue et le vol, la fenêtre le suit.
    func avancerLucarne(_ dt: Double) -> Bool {
        // l'encoche est repliée (à un demi-point près : la fin du ressort ne se voit pas) : elle se décolle
        if lucarne.repli, quasiRepliee { decollerDuRepli() }
        if lucarne.vol, lucarne.capsule.fini { finVol(); return true }
        guard lucarne.libre, !lucarne.capsule.fini else { return false }
        let a = lucarne.capsule
        lucarne.capsule.avancer(dt)
        let b = lucarne.capsule
        let forme = (a.hw.x, a.hh.x, a.s.x, a.r.x, a.leve.x, a.noir.x) != (b.hw.x, b.hh.x, b.s.x, b.r.x, b.leve.x, b.noir.x)
        let bouge = (a.cx.x, a.cy.x) != (b.cx.x, b.cy.x)
        if lucarne.geste.phase == .decollee { suivre(lucarne.geste.pointeur) }   // le point tenu glisse vers le milieu de la pilule
        else if lucarne.vol, bouge { lucarne.surDeplacement() }
        if lucarne.vol, lucarne.capsule.fini { finVol() }
        // arrivée : exactement sur sa cible (comme les ressorts de l'encoche), sans reste qui laisserait le déplié dessiné
        else if lucarne.capsule.fini { lucarne.capsule.poser() }
        // posée, la vue ne suit pas la capsule : un centre qui bouge (la forme grandit depuis sa place) se redessine
        return forme || (bouge && !lucarneEnMain)
    }
    /// Tout posé (rendus, essais) : le vol arrive tout de suite.
    func poserLucarneRessorts() {
        lucarne.capsule.poser()
        if lucarne.vol { finVol() }
    }
    /// Ce qui bouge encore côté Lucarne (diagnostic des essais).
    var lucarneQuiBouge: String? {
        lucarnePosee ? nil : "Lucarne (geste \(lucarne.geste.phase), vol \(lucarne.vol), repli \(lucarne.repli), capsule posée \(lucarne.capsule.fini))"
    }
}
