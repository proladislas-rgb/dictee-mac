import AppKit
import DicteeCore

// La Lucarne déplaçable dans le moteur (docs/plan-lucarne-deplacable.md, mission 2 « geste et fenêtre ») : un appui long de 0,4 s sur la
// forme (même dans l'encoche) la décolle ; elle suit le pointeur au point près ; lâchée (ou lancée), elle se pose sur l'une des huit places
// aimantées ; ramenée près de l'encoche, elle y est aspirée et reprend la forme noire de l'encoche. La place est retenue pour chaque écran.
// Mission 2 : hors de l'encoche, une capsule noire repliée (le verre et le contenu arrivent à la mission 3).
// Énergie : aucune minuterie au repos ; un seul réveil pour les 0,4 s de l'appui ; la boucle tourne seulement pendant que l'anneau se
// remplit ou qu'un ressort bouge ; pendant la tenue et le vol, la fenêtre suit (son origine seulement) sans que SwiftUI ne redessine.

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
    /// Tenue près de l'encoche (elle en prend la forme, noire) ; nil au décollage, tant que la forme tenue n'est pas choisie.
    var pres: Bool?
    /// Lâchée, elle vole vers sa place ; `aspiree` : vers l'encoche, dont elle reprend le régime à l'arrivée.
    var vol = false
    var aspiree = false
    /// La taille de la fenêtre pendant la tenue et le vol : fixe, seule son origine suit la capsule.
    var tailleVol = CGSize.zero
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

    /// En régime libre, la vue dessine la capsule centrée sur ce point (x = milieu de la zone de dessin) : la fenêtre se cale dessus.
    static let milieuLibre = Double(IlotMoteur.hauteurMax) / 2
    /// Rayon de l'anneau de l'appui long (maquette : cercle de 11 pt, trait de 3) et ce qu'il prend autour du pointeur.
    static let rayonAnneau: CGFloat = 11
    static let margeAnneau: CGFloat = 14
    /// Autour de la capsule tenue ou en vol : la place de l'ombre du « levé ».
    static let margeVol: CGFloat = 24

    /// Le point de l'écran (repère de la Lucarne) dessiné en haut au milieu de la vue : l'encoche (0, 0) ; en régime libre, il suit le
    /// centre de la capsule (la vue ne bouge jamais dans la fenêtre).
    var origineVue: CGPoint {
        guard lucarne.libre else { return .zero }
        return CGPoint(x: lucarne.capsule.cx.x, y: lucarne.capsule.cy.x - Self.milieuLibre)
    }
    /// Un point de la vue (x depuis son milieu, y depuis son haut) dans le repère de la Lucarne, et l'inverse.
    func depuisVue(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x + origineVue.x, y: p.y + origineVue.y) }
    func versVue(_ p: PointLucarne) -> CGPoint {
        CGPoint(x: CGFloat(p.x) - origineVue.x + IlotMoteur.largeur / 2, y: CGFloat(p.y) - origineVue.y)
    }
    /// La capsule dessinée (levée : 4 % plus grande), dans le repère de la vue.
    var capsuleVue: CapsuleLucarne {
        let a = lucarne.capsule.affichee, o = origineVue
        return CapsuleLucarne(x0: a.x0 - o.x, x1: a.x1 - o.x, y0: a.y0 - o.y, y1: a.y1 - o.y, s: a.s, r: a.r)
    }
    /// L'anneau de l'appui long : son centre dans la vue et son remplissage ; nil hors de l'appui.
    var anneauAppui: (centre: CGPoint, fraction: Double)? {
        guard lucarne.geste.phase == .appui else { return nil }
        return (versVue(lucarne.geste.pointeur), lucarne.geste.progression(a: ProcessInfo.processInfo.systemUptime))
    }
    /// Un appui ou une tenue en cours : la fenêtre garde la souris (pas de clic qui traverse, pas de survol).
    var lucarneOccupee: Bool { lucarne.bouton != nil || lucarne.geste.phase != .repos }
    /// Plus rien ne bouge côté Lucarne (pas d'anneau qui se remplit, pas de ressort, pas de vol).
    var lucarnePosee: Bool { lucarne.geste.phase != .appui && !lucarne.vol && (!lucarne.libre || lucarne.capsule.fini) }

    // MARK: mesures

    /// La capsule libre contient-elle ce point (repère de la Lucarne) ?
    func contientLibre(_ p: CGPoint) -> Bool {
        let chemin = FormeNoire(points: TraceLucarne.calculer(lucarne.capsule.affichee))
            .path(in: CGRect(x: -IlotMoteur.largeur / 2, y: 0, width: IlotMoteur.largeur, height: IlotMoteur.hauteurMax))
        return chemin.contains(p)
    }

    /// La fenêtre en régime libre (repère de la Lucarne), toujours centrée sur la capsule : au repos, serrée sur la forme (2 pt) ; pendant
    /// la tenue et le vol, une taille fixe (seule l'origine suit) ; l'anneau de l'appui y tient.
    func fenetreLibre() -> CGRect {
        let c = lucarne.capsule, cx = CGFloat(c.cx.x), cy = CGFloat(c.cy.x)
        var demiL: CGFloat, demiH: CGFloat
        if lucarne.geste.phase == .decollee || lucarne.vol {
            demiL = lucarne.tailleVol.width / 2; demiH = lucarne.tailleVol.height / 2
        } else {
            let a = c.affichee, v = c.cible
            demiL = CGFloat(max(a.largeur, v.largeur)) / 2 + 2; demiH = CGFloat(max(a.hauteur, v.hauteur)) / 2 + 2
        }
        if lucarne.geste.phase == .appui {
            let p = lucarne.geste.pointeur
            demiL = max(demiL, abs(CGFloat(p.x) - cx) + Self.margeAnneau); demiH = max(demiH, abs(CGFloat(p.y) - cy) + Self.margeAnneau)
        }
        return CGRect(x: cx - demiL, y: cy - demiH, width: 2 * demiL, height: 2 * demiH)
    }
    /// Dans l'encoche : la fenêtre voulue, plus l'anneau de l'appui long (jamais au-dessus du haut de l'écran).
    func avecAnneau(_ r: CGRect) -> CGRect {
        guard lucarne.geste.phase == .appui else { return r }
        let p = lucarne.geste.pointeur, m = Self.margeAnneau
        let a = CGRect(x: CGFloat(p.x) - m, y: max(0, CGFloat(p.y) - m), width: 2 * m, height: CGFloat(p.y) + m - max(0, CGFloat(p.y) - m))
        return r.union(a)
    }

    /// La forme de l'encoche telle qu'elle est (au décollage) ou telle qu'elle sera (le retour), en capsule.
    func capsuleEncoche(cible: Bool) -> CapsuleLucarne {
        cible ? .encoche(traceCible, epaule: geo[3].cibleFinale, coin: geo[4].cibleFinale) : .encoche(trace, epaule: geo[3].x, coin: geo[4].x)
    }

    // MARK: écran et mémoire

    /// L'écran est mesuré (démarrage, écran changé) : la Lucarne est posée à sa place, sans animation ; un geste en cours s'arrête.
    func poserLucarne(_ e: EcranLucarne, uuid: String, place: PlaceLucarne) {
        lucarne.reveil?.cancel(); lucarne.reveil = nil
        lucarne.garde?.cancel(); lucarne.garde = nil
        lucarne.geste = GesteLucarne(); lucarne.bouton = nil; lucarne.dernier = nil
        appuyer(false)
        lucarne.ecran = e; lucarne.uuid = uuid; lucarne.place = place
        lucarne.vol = false; lucarne.aspiree = false; lucarne.pres = nil
        lucarne.libre = place != .encoche
        if lucarne.libre { lucarne.capsule = RessortsCapsule(GeoLucarne.replie(place, e), noir: 0) }
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
        guard lucarne.geste.phase == .repos else { return }
        if lucarne.bouton != nil { commencerAppui(); return }
        lucarne.surForme = true
        DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.lucarne.surForme = false } }
    }

    /// L'appui est sur la forme : l'anneau se remplit sous le pointeur, l'îlot gonfle un peu, un seul réveil à 0,4 s.
    func commencerAppui() {
        guard let b = lucarne.bouton else { return }
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
            // hors de l'encoche, la capsule ne s'ouvre pas encore (son contenu arrive avec la mission 3)
            case .clic: finAppui(); if !lucarne.libre { clicForme() }
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

    /// 0,4 s d'appui : le Centre (ou une carte) se range, la forme se décolle (prise sur la forme actuelle), se lève, vibre une fois.
    private func decoller() {
        guard let e = lucarne.ecran else { return }
        lucarne.reveil?.cancel(); lucarne.reveil = nil
        appuyer(false)
        if fenetreOuverte { fermer() }
        let depart = lucarne.libre ? lucarne.capsule.valeur : capsuleEncoche(cible: false)
        if !lucarne.libre { lucarne.libre = true; lucarne.capsule = RessortsCapsule(depart, noir: 1) }
        lucarne.vol = false; lucarne.aspiree = false; lucarne.pres = nil
        lucarne.capsule.saisir(pointeur: lucarne.geste.pointeur)
        lucarne.capsule.lever()
        if reduire { lucarne.capsule.leve.poser() }
        // assez grande pour tout ce qu'elle peut devenir d'ici son arrivée (la forme de départ, celle de l'encoche, les pilules), levée
        let ailes = 2 * ((e.demiCamera ?? 0) + GeoLucarne.ailesCompactes + GeoLucarne.epaulesCompactes)
        let l = max(depart.largeur, ailes, GeoLucarne.pilule.largeur, GeoLucarne.pilouleDebout.largeur)
        let h = max(depart.hauteur, e.barre, GeoLucarne.pilule.hauteur, GeoLucarne.pilouleDebout.hauteur)
        lucarne.tailleVol = CGSize(width: CGFloat(l * GeoLucarne.echelleTenue) + 2 * Self.margeVol, height: CGFloat(h * GeoLucarne.echelleTenue) + 2 * Self.margeVol)
        lucarne.systeme.vibrer()
        suivre(lucarne.geste.pointeur)
        surveillerTenue()
        surFenetre(); demarrerBoucle()
    }

    /// Tenue : elle suit le pointeur 1:1 ; près de l'encoche, elle en prend la forme (noire), ailleurs une pilule.
    private func suivre(_ p: PointLucarne) {
        guard let e = lucarne.ecran else { return }
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
    /// vitesse du geste. La place est retenue pour cet écran.
    private func lacher(vx: Double, vy: Double) {
        guard let e = lucarne.ecran else { return }
        lucarne.garde?.cancel(); lucarne.garde = nil
        let c = lucarne.capsule.valeur
        let place = GeoLucarne.placeLachee(cx: c.centreX, cy: c.centreY, vx: vx, vy: vy, pres: lucarne.pres == true, e)
        lucarne.capsule.reposer()
        lucarne.capsule.decalX.poser(); lucarne.capsule.decalY.poser()
        if reduire { lucarne.capsule.leve.poser() }
        let v = PointLucarne(vx, vy)
        lucarne.aspiree = place == .encoche
        if lucarne.aspiree {
            lucarne.capsule.viser(capsuleEncoche(cible: true), passage: .aspiration, vitesse: v, reduire: reduire)
        } else {
            lucarne.capsule.viser(GeoLucarne.replie(place, e), passage: .atterrissage, vitesse: v, reduire: reduire)
        }
        lucarne.place = place; lucarne.vol = true; lucarne.pres = nil
        var memoire = lucarne.systeme.lireMemoire()
        memoire.memoriser(place, pour: lucarne.uuid)
        lucarne.systeme.ecrireMemoire(memoire)
        if lucarne.capsule.fini { finVol() } else { demarrerBoucle() }
    }

    /// Arrivée : sur l'encoche, elle reprend son régime (la forme de l'encoche, sans saut) ; ailleurs, la fenêtre se resserre.
    private func finVol() {
        // posée exactement sur sa cible : AppKit arrondit le cadre de la fenêtre vers l'extérieur (44,0000001 pt deviendrait 45)
        lucarne.capsule.poser()
        lucarne.vol = false
        if lucarne.aspiree { lucarne.aspiree = false; lucarne.libre = false }
        surFenetre(); demarrerBoucle()
    }

    /// Pendant la tenue seulement : le relâchement a pu se perdre (une autre app a pris la souris) ; le bouton remonté, elle est lâchée.
    private func surveillerTenue() {
        lucarne.garde?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.lucarne.geste.phase == .decollee else { return }
                if self.boutonEnfonce() { self.surveillerTenue(); return }
                self.traiter(self.lucarne.geste.relacher(self.lucarne.geste.pointeur, t: ProcessInfo.processInfo.systemUptime))
            }
        }
        lucarne.garde = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: item)
    }

    // MARK: ressorts

    /// Une image de la boucle. Vrai si la vue doit être redessinée (la forme a changé, l'anneau se remplit) : le centre seul ne
    /// redessine rien, la fenêtre le suit.
    func avancerLucarne(_ dt: Double) -> Bool {
        let anneau = lucarne.geste.phase == .appui
        guard lucarne.libre, !lucarne.capsule.fini else { return anneau }
        let a = lucarne.capsule
        lucarne.capsule.avancer(dt)
        let b = lucarne.capsule
        let forme = (a.hw.x, a.hh.x, a.s.x, a.r.x, a.leve.x) != (b.hw.x, b.hh.x, b.s.x, b.r.x, b.leve.x)
        if lucarne.geste.phase == .decollee { suivre(lucarne.geste.pointeur) }   // le point tenu glisse vers le milieu de la pilule
        else if (a.cx.x, a.cy.x) != (b.cx.x, b.cy.x) { lucarne.surDeplacement() }
        if lucarne.vol, lucarne.capsule.fini { finVol() }
        return anneau || forme
    }
    /// Tout posé (rendus, essais) : le vol arrive tout de suite.
    func poserLucarneRessorts() {
        lucarne.capsule.poser()
        if lucarne.vol { finVol() }
    }
    /// Ce qui bouge encore côté Lucarne (diagnostic des essais).
    var lucarneQuiBouge: String? {
        lucarnePosee ? nil : "Lucarne (geste \(lucarne.geste.phase), vol \(lucarne.vol), capsule posée \(lucarne.capsule.fini))"
    }
}
