import AppKit
import DicteeCore

/// La Lucarne déplaçable pendant l'essai : un faux Dock, une mémoire des places en mémoire, une vibration comptée. Jamais les vrais
/// réglages (`lucarnePlaces`), jamais les préférences du Dock, jamais l'actionneur du trackpad.
@MainActor
enum EssaiPlaces {
    static var memoire = MemoirePlaces()
    static var ecritures = 0
    static var vibrations = 0
    static let ecran = "ECRAN-ESSAI"
}

extension IlotEssai {
    /// Branché par `fabriquer()` avant le démarrage du panneau : l'écran réel (son cadre, son encoche) avec un Dock factice en bas
    /// (70 pt, largeur inconnue), et tout ce qui toucherait au système remplacé.
    @MainActor
    static func systemeLucarneDEssai(_ c: IlotControleur) {
        c.moteur.lucarne.systeme = SystemeLucarne(
            decrire: { e, g, centre in
                EcranLucarne(cadre: e.frame, barre: Double(g.hauteur), demiCamera: g.reelle ? Double(g.largeur / 2) : nil,
                             centreX: Double(centre - e.frame.minX), retraitBas: 70, dockCote: .bas, dockEpaisseur: 70)
            },
            identifiant: { _ in EssaiPlaces.ecran },
            lireMemoire: { MainActor.assumeIsolated { EssaiPlaces.memoire } },
            ecrireMemoire: { m in MainActor.assumeIsolated { EssaiPlaces.memoire = m; EssaiPlaces.ecritures += 1 } },
            vibrer: { MainActor.assumeIsolated { EssaiPlaces.vibrations += 1 } })
    }

    /// Le geste de la Lucarne avec de VRAIS événements souris remis à la fenêtre (appui, mouvements, relâchement : la vue d'hébergement
    /// lit leur point global, le geste SwiftUI dit « sur la forme ») ; faux écran, mémoire et vibration injectées, fenêtre invisible.
    @MainActor
    static func placesLucarne(_ c: IlotControleur, verifier: (Bool, String) -> Void, attendre: (Double, () -> Bool) -> Void) {
        func pause(_ s: Double) { attendre(s) { true } }
        let m = c.moteur
        print("— la Lucarne déplaçable : appui long, tenue, lâcher, lancer, retour dans l'encoche")
        guard let e = m.lucarne.ecran else { verifier(false, "Lucarne : l'écran est mesuré au démarrage"); return }
        guard e.avecEncoche else { print("  (écran sans encoche : essai des places sauté)"); return }
        m.fermer(); pause(0.8)
        EssaiPlaces.memoire = MemoirePlaces()
        var tenu = false
        m.boutonEnfonce = { tenu }
        defer { m.boutonEnfonce = { NSEvent.pressedMouseButtons & 1 != 0 } }
        func bas(_ p: CGPoint) { tenu = true; c.panneau.envoyerSouris(.leftMouseDown, en: p) }
        func glisse(_ p: CGPoint) { c.panneau.envoyerSouris(.leftMouseDragged, en: p) }
        func haut(_ p: CGPoint) { c.panneau.envoyerSouris(.leftMouseUp, en: p); tenu = false }
        /// Un glisser de `a` à `b` en `n` pas, `dt` entre chaque.
        func trainer(_ a: CGPoint, _ b: CGPoint, n: Int = 12, dt: Double = 0.016) {
            for i in 1...n { let u = CGFloat(i) / CGFloat(n); glisse(CGPoint(x: a.x + (b.x - a.x) * u, y: a.y + (b.y - a.y) * u)); pause(dt) }
        }
        func centre() -> CGPoint { CGPoint(x: m.lucarne.capsule.cx.x, y: m.lucarne.capsule.cy.x) }
        /// La fenêtre est-elle centrée sur la capsule (repère de la Lucarne) ?
        func fenetreSurCapsule() -> Bool {
            guard let f = c.panneau.cadre, let ecran = c.panneau.ecran else { return false }
            let cx = f.midX - c.panneau.centre, cy = ecran.frame.maxY - f.midY
            return abs(cx - centre().x) < 1 && abs(cy - centre().y) < 1
        }
        let encoche = CGPoint(x: 0, y: e.barre / 2)
        /// Ramène la Lucarne dans l'encoche d'un vrai geste (appui long sur elle, glisser en haut au milieu, lâcher).
        func ramener() {
            let depart = m.lucarne.libre ? centre() : encoche
            bas(depart); pause(0.5); trainer(depart, CGPoint(x: 0, y: e.barre / 2 + 6)); pause(0.2); haut(CGPoint(x: 0, y: e.barre / 2 + 6)); pause(1.0)
        }

        // --- au repos dans l'encoche : rien ne tourne, aucune minuterie
        verifier(!m.lucarne.libre && m.lucarne.place == .encoche && m.lucarne.reveil == nil && m.lucarne.garde == nil && !m.boucleActive,
                 "Lucarne au repos dans l'encoche : régime de l'encoche, aucun réveil, aucune boucle")

        // --- appui long dans l'encoche : l'anneau se remplit, à 0,4 s elle se décolle
        let n0 = EssaiPlaces.vibrations, e0 = EssaiPlaces.ecritures
        bas(encoche)
        verifier(m.lucarne.geste.phase == .appui, "le geste SwiftUI de la forme répond dans le même tour que l'appui (aucun clic perdu)")
        pause(0.2)
        let anneau = m.anneauAppui
        verifier(m.presse && anneau != nil && (anneau?.fraction ?? 0) > 0.3 && (anneau?.fraction ?? 1) < 0.8 && m.boucleActive,
                 "à 0,2 s : l'îlot gonfle, l'anneau se remplit (\(String(format: "%.2f", anneau?.fraction ?? -1))), la boucle tourne pour lui")
        if let f = c.panneau.cadre, let ecran = c.panneau.ecran {
            let x0 = f.minX - c.panneau.centre, y1 = ecran.frame.maxY - f.minY, r = IlotMoteur.rayonAnneau + 1.5
            verifier(x0 <= encoche.x - r && x0 + f.width >= encoche.x + r && y1 >= encoche.y + r,
                     "la fenêtre couvre l'anneau sous le pointeur (\(Int(f.width)) × \(Int(f.height)) pt)")
        }
        pause(0.3)
        verifier(m.lucarne.geste.phase == .decollee && m.lucarne.libre && EssaiPlaces.vibrations == n0 + 1 && !m.presse && m.anneauAppui == nil,
                 "à 0,4 s : elle se décolle (régime libre), une vibration, l'anneau s'efface")
        verifier(m.lucarne.pres == true && abs(m.lucarne.capsule.hh.cibleFinale - e.barre / 2) < 0.01,
                 "tenue tout près de l'encoche : elle en garde la forme (noire)")

        // --- elle suit le pointeur au point près ; la fenêtre la suit, sans redessiner la vue
        let loin = CGPoint(x: -300, y: 420)
        trainer(encoche, loin, n: 20); pause(0.6)
        let d = m.lucarne.capsule.decalage
        verifier(m.lucarne.pres == false && abs(m.lucarne.capsule.hh.cibleFinale - GeoLucarne.pilule.hauteur / 2) < 0.01,
                 "loin de l'encoche : une pilule (\(Int(2 * m.lucarne.capsule.hw.cibleFinale)) × \(Int(2 * m.lucarne.capsule.hh.cibleFinale)))")
        verifier(abs(centre().x - (loin.x + d.x)) < 0.01 && abs(centre().y - (loin.y + d.y)) < 0.01 && fenetreSurCapsule(),
                 "elle suit le pointeur (centre = pointeur + prise) et la fenêtre est centrée sur elle")
        verifier(!m.boucleActive, "tenue immobile : plus de boucle (bouge encore : \(m.ceQuiBouge))")
        let rev0 = m.rev, avant = centre()
        let pas = CGPoint(x: loin.x + 37.5, y: loin.y - 12.5)
        glisse(pas); pause(0.05)
        verifier(abs(centre().x - avant.x - 37.5) < 0.01 && abs(centre().y - avant.y + 12.5) < 0.01 && fenetreSurCapsule(),
                 "un mouvement de 37,5 × −12,5 pt : la capsule et la fenêtre bougent d'autant, au point près")
        verifier(m.rev == rev0 && !m.boucleActive, "pendant la tenue : la fenêtre seule bouge (aucune réévaluation de la vue, aucune boucle)")

        // --- lâchée sans élan : la place la plus proche, retenue pour cet écran ; posée, la fenêtre se resserre
        pause(0.2)
        let attendue = GeoLucarne.plusProche(x: centre().x, y: centre().y, e)
        haut(pas)
        verifier(m.lucarne.vol && m.lucarne.place == attendue && EssaiPlaces.memoire.place(pour: EssaiPlaces.ecran) == attendue && EssaiPlaces.ecritures == e0 + 1,
                 "lâchée : elle vole vers la place la plus proche (\(attendue.rawValue)), retenue dans la mémoire factice")
        pause(1.2)
        let posee = GeoLucarne.replie(attendue, e)
        verifier(!m.lucarne.vol && m.lucarne.capsule.fini && abs(centre().x - posee.centreX) < 0.01 && abs(centre().y - posee.centreY) < 0.01,
                 "posée à sa place (centre \(Int(centre().x)), \(Int(centre().y)))")
        verifier(!m.boucleActive, "posée au repos : aucune boucle (bouge encore : \(m.ceQuiBouge))")
        if let f = c.panneau.cadre {
            verifier(abs(Double(f.width) - posee.largeur - 4) < 0.5 && abs(Double(f.height) - posee.hauteur - 4) < 0.5 && fenetreSurCapsule(),
                     "fenêtre serrée sur la capsule (\(Int(f.width)) × \(Int(f.height)) pt)")
        }
        let coin = CGPoint(x: posee.x0 + 1, y: posee.y0 + 1)
        verifier(m.contient(CGPoint(x: posee.centreX, y: posee.centreY)) && !m.contient(coin),
                 "le milieu de la capsule la touche, le coin arrondi non (le vide laisse passer les clics)")

        // --- appui puis 10 pt avant 0,4 s : rien (ni clic, ni déplacement)
        let ici = centre(), place1 = m.lucarne.place
        bas(ici); pause(0.2); glisse(CGPoint(x: ici.x + 10, y: ici.y)); pause(0.4); haut(CGPoint(x: ici.x + 10, y: ici.y)); pause(0.3)
        verifier(m.lucarne.geste.phase == .repos && m.lucarne.place == place1 && abs(centre().x - ici.x) < 0.01 && !m.presse && !m.fenetreOuverte,
                 "appui puis 10 pt à 0,2 s : ni clic ni déplacement")
        // un clic court hors de l'encoche : rien ne s'ouvre (le contenu de la capsule libre arrive à la mission 3)
        bas(ici); pause(0.08); haut(ici); pause(0.5)
        verifier(m.lucarne.libre && !m.fenetreOuverte && m.lucarne.geste.phase == .repos, "clic court sur la capsule libre : rien ne s'ouvre encore")

        // --- un lancer vers le bas (≈ 800 pt/s) : en bas au milieu, au-dessus du Dock ; le ressort garde l'élan
        bas(ici); pause(0.5)
        let haut0 = CGPoint(x: 0, y: e.hauteur * 0.42)
        trainer(ici, haut0, n: 15); pause(0.3)
        for i in 1...6 { glisse(CGPoint(x: haut0.x, y: haut0.y + 13 * Double(i))); pause(0.016) }
        haut(CGPoint(x: haut0.x, y: haut0.y + 78))
        verifier(m.lucarne.place == .basMilieu && m.lucarne.capsule.cy.v > 200,
                 "lancée vers le bas : en bas au milieu (\(m.lucarne.place.rawValue)), partie avec l'élan (\(Int(m.lucarne.capsule.cy.v)) pt/s)")
        pause(1.2)
        let basMilieu = GeoLucarne.replie(.basMilieu, e)
        verifier(abs(centre().y - basMilieu.centreY) < 0.01 && basMilieu.y1 <= e.hauteur - 70 - GeoLucarne.marge + 0.01 && !m.boucleActive,
                 "posée au-dessus du Dock factice (bas à \(Int(basMilieu.y1)) pt), plus de boucle")

        // --- ramenée en haut au milieu : aspirée par l'encoche, noire, la forme de l'encoche (jamais plus de 66 pt dans la barre)
        bas(centre()); pause(0.5)
        trainer(centre(), CGPoint(x: 4, y: e.barre / 2 + 8), n: 20); pause(0.4)
        verifier(m.lucarne.pres == true && m.lucarne.capsule.noir.cibleFinale == 1, "tenue près de l'encoche : aimantée, elle redevient noire")
        haut(CGPoint(x: 4, y: e.barre / 2 + 8))
        verifier(m.lucarne.place == .encoche && m.lucarne.vol, "lâchée près de l'encoche : aspirée")
        pause(1.0)
        verifier(!m.lucarne.libre && EssaiPlaces.memoire.place(pour: EssaiPlaces.ecran) == .encoche && m.trace.bande <= Double(m.demiCamera) + GeoIlot.aileMax + 0.01,
                 "de retour dans l'encoche : son régime, sa forme (cou ≤ 66 pt), la mémoire le dit")
        verifier(!m.boucleActive && (c.panneau.cadre?.height ?? 99) <= CGFloat(e.barre) + 6.5, "dans l'encoche : plus de boucle, la fenêtre de l'encoche")

        // --- le Centre ouvert : l'appui long le replie, puis elle se décolle
        m.clicForme(); pause(0.9)
        verifier(m.courante == .centre && m.fenetreOuverte, "le Centre est ouvert (clic)")
        let surCentre = CGPoint(x: 0, y: e.barre / 2)
        bas(surCentre); pause(0.5)
        verifier(m.lucarne.geste.phase == .decollee && !m.fenetreOuverte && m.lucarne.capsule.hh.x > 40,
                 "appui long sur le Centre ouvert : il se range, elle se décolle (prise sur sa forme, \(Int(2 * m.lucarne.capsule.hh.x)) pt de haut)")
        haut(surCentre); pause(1.0)
        verifier(!m.lucarne.libre && m.courante != .centre && !m.boucleActive, "relâchée sur place : de retour dans l'encoche, le Centre rangé")

        // --- relâchement perdu pendant la tenue (une autre app a pris la souris) : elle est lâchée d'elle-même
        bas(encoche); pause(0.5); trainer(encoche, CGPoint(x: 560, y: 420)); pause(0.1)
        tenu = false; pause(0.4)
        verifier(m.lucarne.geste.phase == .repos && m.lucarne.garde == nil, "bouton remonté sans relâchement reçu : elle est lâchée (garde-fou de la tenue)")
        pause(1.0)
        verifier(m.lucarne.libre && !m.boucleActive, "posée à la place la plus proche (\(m.lucarne.place.rawValue))")
        ramener()
        verifier(!m.lucarne.libre, "ramenée dans l'encoche")

        // --- dictée pendant la tenue : le geste s'arrête, elle retombe à sa place la plus proche ; effacée le temps de la dictée
        bas(encoche); pause(0.5); trainer(encoche, CGPoint(x: -560, y: 420)); pause(0.2)
        var occ = OccupationEncoche(); c.occupation = { occ }
        occ.dictee = true; c.occupationChangee(); pause(0.9)
        verifier(m.lucarne.geste.phase == .repos && m.lucarne.libre && !c.panneau.estVisible, "dictée pendant la tenue : lâchée, effacée pendant la dictée")
        occ.dictee = false; c.occupationChangee(); c.occupation = { OccupationEncoche() }; pause(1.0)
        verifier(m.lucarne.libre && c.panneau.estVisible && fenetreSurCapsule() && !m.boucleActive,
                 "fin de la dictée : de retour à sa place (\(m.lucarne.place.rawValue)), plus de boucle")
        haut(centre())   // le relâchement de l'appui interrompu arrive enfin : il ne fait rien
        pause(0.3)
        verifier(m.lucarne.geste.phase == .repos && !m.lucarne.vol, "le relâchement d'un appui interrompu ne fait rien")

        // --- au redémarrage (ou écran changé) : reposée à la place retenue, sans animation
        EssaiPlaces.memoire.memoriser(.hautDroite, pour: EssaiPlaces.ecran)
        c.panneau.demarrer(); pause(0.3)
        let hd = GeoLucarne.replie(.hautDroite, e)
        verifier(m.lucarne.libre && m.lucarne.place == .hautDroite && abs(centre().x - hd.centreX) < 0.01 && fenetreSurCapsule() && !m.boucleActive,
                 "relancée : reposée en haut à droite, sans animation, aucune boucle")
        verifier(hd.y0 >= e.barre + GeoLucarne.ecartBarre - 0.01 && hd.x1 <= e.xMax + 0.01, "en haut à droite : sous la barre, dans la zone utile")

        // --- « Réduire les animations » : tout saute à sa place
        m.reduire = true
        bas(centre()); pause(0.5)
        verifier(m.lucarne.capsule.leve.x == 1, "réduire les animations : levée d'un coup")
        trainer(centre(), CGPoint(x: -200, y: e.hauteur * 0.55)); pause(0.1)
        haut(CGPoint(x: -200, y: e.hauteur * 0.55)); pause(0.05)
        verifier(!m.lucarne.vol && m.lucarne.capsule.fini && m.lucarne.capsule.leve.x == 0, "réduire les animations : posée tout de suite à sa place (\(m.lucarne.place.rawValue))")
        ramener()
        verifier(!m.lucarne.libre, "réduire les animations : de retour dans l'encoche sans vol")
        m.reduire = false

        pause(0.8)
        verifier(!m.lucarne.libre && EssaiPlaces.memoire.place(pour: EssaiPlaces.ecran) == .encoche && !m.boucleActive && m.lucarne.reveil == nil && m.lucarne.garde == nil,
                 "fin : dans l'encoche, plus de boucle, aucun réveil (bouge encore : \(m.ceQuiBouge))")
    }
}
