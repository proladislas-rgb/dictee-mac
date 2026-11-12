import AppKit
import DicteeCore

/// La Lucarne déplaçable pendant l'essai : de faux écrans, un faux Dock, une mémoire des places en mémoire, une vibration comptée.
/// Jamais les vrais réglages (`lucarnePlaces`), jamais les préférences du Dock, jamais l'actionneur du trackpad.
@MainActor
enum EssaiPlaces {
    static var memoire = MemoirePlaces()
    static var ecritures = 0
    static var vibrations = 0
    static let ecran = "ECRAN-ESSAI"
    /// Les faux écrans, le principal d'abord ; le faux Dock (en bas, icônes de 56 : 70 pt).
    static var ecrans: [EcranIlot] = [principal()]
    static var dock = PrefsDock(cote: .bas, masque: false, tailleIcone: 56)
    static var lecturesDock = 0

    /// Le faux écran principal : le cadre et l'encoche du vrai (les événements fabriqués passent par la conversion d'AppKit, qui suit le
    /// vrai écran principal : son cadre doit être le même), avec la zone visible d'un Dock de 70 pt en bas. Sans écran (essai sans
    /// affichage) : un MacBook de 1470 × 956.
    static func principal(dock bas: CGFloat = 70) -> EcranIlot {
        let vrai = NSScreen.screens.first
        let f = vrai?.frame ?? CGRect(x: 0, y: 0, width: 1470, height: 956)
        let (g, c) = vrai.map(GeometrieEncoche.mesurer) ?? (GeometrieEncoche(largeur: 179, hauteur: 33), f.midX)
        return EcranIlot(id: ecran, frame: f, zoneVisible: CGRect(x: f.minX, y: f.minY + bas, width: f.width, height: f.height - g.hauteur - bas),
                         geometrie: g, centre: c)
    }

    /// Un faux écran externe sans encoche (barre de 24 pt), collé à droite du principal, haut contre haut.
    static func externe(largeur: CGFloat = 1920, hauteur: CGFloat = 1080) -> EcranIlot {
        let p = principal().frame
        let f = CGRect(x: p.maxX, y: p.maxY - hauteur, width: largeur, height: hauteur)
        var g = GeometrieEncoche(); g.reelle = false; g.hauteur = 24
        return EcranIlot(id: "ECRAN-EXTERNE", frame: f, zoneVisible: CGRect(x: f.minX, y: f.minY, width: f.width, height: f.height - 24), geometrie: g, centre: f.midX)
    }
}

extension IlotEssai {
    /// Branché par `fabriquer()` avant le démarrage du panneau : les faux écrans et le faux Dock, et tout ce qui toucherait au système
    /// remplacé (aucune observation du vrai Dock).
    @MainActor
    static func systemeLucarneDEssai(_ c: IlotControleur) {
        c.moteur.lucarne.systeme = SystemeLucarne(
            ecrans: { MainActor.assumeIsolated { EssaiPlaces.ecrans } },
            lireDock: { MainActor.assumeIsolated { EssaiPlaces.lecturesDock += 1; return EssaiPlaces.dock } },
            suivreDock: { _ in nil },
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
        func etat() -> String { IlotEssai.etatLucarne(m) }
        /// Tenue ou en vol, la fenêtre est-elle centrée sur la capsule (repère de la Lucarne) ? Posée, est-elle celle de la forme posée
        /// (la pilule avec la place de son ombre) ?
        func fenetreSurCapsule() -> Bool {
            guard let f = c.panneau.cadre, let ecran = c.panneau.ecran else { return false }
            let cx = f.midX - c.panneau.centre, cy = ecran.frame.maxY - f.midY
            if m.lucarneEnMain { return abs(cx - centre().x) < 1 && abs(cy - centre().y) < 1 }
            let k = m.lucarne.capsule.valeur
            let voulu = CGRect(x: k.x0 - 8, y: k.y0 - 6, width: k.largeur + 16, height: k.hauteur + 18)
            let r = CGRect(x: f.minX - c.panneau.centre, y: ecran.frame.maxY - f.maxY, width: f.width, height: f.height)
            return abs(r.minX - voulu.minX) < 1 && abs(r.minY - voulu.minY) < 1 && abs(r.width - voulu.width) < 1 && abs(r.height - voulu.height) < 1
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
        let rempli = m.lucarne.geste.progression(a: ProcessInfo.processInfo.systemUptime)
        verifier(m.presse && anneau != nil && rempli > 0.3 && rempli < 0.8 && !m.boucleActive,
                 "à 0,2 s : l'îlot gonfle, l'anneau se remplit (\(String(format: "%.2f", rempli))) de lui-même : aucune boucle de l'îlot")
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
        verifier(m.lucarne.capsule.noir.cibleFinale == 0 && m.lucarne.capsule.fonduNoir < 0.01 && m.lucarneEnMain && m.lucarneDeplie == 0,
                 "pendant la tenue loin de l'encoche : régime verre (noir = \(String(format: "%.3f", m.lucarne.capsule.fonduNoir)), voile de la pilule)")
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
        let posee = m.capsuleRepliee(e)
        verifier(!m.lucarne.vol && m.lucarne.capsule.fini && abs(centre().x - posee.centreX) < 0.01 && abs(centre().y - posee.centreY) < 0.01,
                 "posée à sa place (centre \(Int(centre().x)), \(Int(centre().y)))")
        verifier(!m.boucleActive, "posée au repos : aucune boucle (bouge encore : \(m.ceQuiBouge))")
        if let f = c.panneau.cadre {
            verifier(fenetreSurCapsule(), "fenêtre serrée sur la pilule, la place de son ombre autour (\(Int(f.width)) × \(Int(f.height)) pt)")
        }
        let coin = CGPoint(x: posee.x0 + 1, y: posee.y0 + 1)
        verifier(m.contient(CGPoint(x: posee.centreX, y: posee.centreY)) && !m.contient(coin),
                 "le milieu de la capsule la touche, le coin arrondi non (le vide laisse passer les clics)")

        // --- appui puis 10 pt avant 0,4 s : rien (ni clic, ni déplacement)
        let ici = centre(), place1 = m.lucarne.place
        bas(ici); pause(0.2); glisse(CGPoint(x: ici.x + 10, y: ici.y)); pause(0.4); haut(CGPoint(x: ici.x + 10, y: ici.y)); pause(0.3)
        verifier(m.lucarne.geste.phase == .repos && m.lucarne.place == place1 && abs(centre().x - ici.x) < 0.01 && !m.presse && !m.fenetreOuverte,
                 "appui puis 10 pt à 0,2 s : ni clic ni déplacement")
        // un clic court hors de l'encoche : le Centre s'ouvre depuis la place, vers l'intérieur ; un clic ailleurs le range
        bas(ici); pause(0.08); haut(ici); pause(0.9)
        let ouvert = m.lucarne.capsule.valeur
        verifier(m.lucarne.libre && m.courante == .centre && m.epingle && m.lucarne.geste.phase == .repos && ouvert.hauteur > 200
                 && (place1.ancre.x == 0 ? abs(ouvert.x0 - e.xMin) < 0.5 : place1.ancre.x == 1 ? abs(ouvert.x1 - e.xMax) < 0.5 : true),
                 "clic court sur la pilule : le Centre s'ouvre depuis sa place, vers l'intérieur (\(Int(ouvert.largeur)) × \(Int(ouvert.hauteur)))")
        m.clicAilleurs(); pause(0.6); attendre(1.5) { m.boucleActive }
        verifier(!m.fenetreOuverte && m.lucarne.capsule.cible == posee && !m.boucleActive, "clic ailleurs : rangé dans la pilule, plus rien ne tourne \(etat())")

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

        // --- le Centre ouvert : l'appui long le range, l'encoche se replie d'abord (sa forme dépliée, avec son cou dans la barre, ne
        // devient jamais une capsule qui couvrirait les icônes voisines), puis elle se décolle de la forme repliée, sans saut
        m.clicForme(); pause(0.9)
        verifier(m.courante == .centre && m.fenetreOuverte, "le Centre est ouvert (clic)")
        let surCentre = CGPoint(x: 0, y: e.barre / 2)
        bas(surCentre); pause(0.45)
        verifier(m.lucarne.geste.phase == .decollee && !m.fenetreOuverte && !m.lucarne.libre && m.lucarne.repli,
                 "appui long sur le Centre ouvert : il se range, la Lucarne attend que l'encoche soit repliée \(etat())")
        attendre(1.0) { m.lucarne.repli }
        verifier(m.lucarne.libre && !m.lucarne.repli && m.lucarne.geste.phase == .decollee && m.trace.hauteur <= Double(m.geometrie.hauteur) + 0.5,
                 "repliée : elle se décolle de la forme de l'encoche (\(Int(2 * m.lucarne.capsule.hh.x)) pt de haut), le doigt la tient toujours \(etat())")
        haut(surCentre); pause(1.0)
        verifier(!m.lucarne.libre && m.courante != .centre && !m.boucleActive, "relâchée sur place : de retour dans l'encoche, le Centre rangé")
        // relâchée pendant le repli : elle reste dans l'encoche
        m.clicForme(); pause(0.9)
        bas(surCentre); pause(0.45); haut(surCentre); pause(0.6); attendre(1.5) { m.boucleActive }
        verifier(!m.lucarne.libre && !m.lucarne.repli && m.lucarne.geste.phase == .repos && !m.boucleActive, "relâchée pendant le repli : elle reste dans l'encoche \(etat())")

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
        let hd = m.capsuleRepliee(e)
        verifier(m.lucarne.libre && m.lucarne.place == .hautDroite && abs(centre().x - hd.centreX) < 0.01 && fenetreSurCapsule() && !m.boucleActive,
                 "relancée : reposée en haut à droite, sans animation, aucune boucle \(etat())")
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

// MARK: - le verre hors de l'encoche (mission 3)

/// Tout ce que l'îlot sait montrer, posé sur un moteur (exigence de Hugues, 12/11 : TOUT doit marcher en verre depuis les quatre coins
/// et les places du milieu) : le Centre, les cartes, les annonces, les alertes, l'onde de la note dictée. Des données factices et
/// génériques (le dépôt est public) ; l'essai et les rendus de la Lucarne s'en servent.
@MainActor
enum CatalogueLucarne {
    struct Ecran {
        var nom: String
        /// L'écran attendu une fois posé.
        var vue: VueIlot
        var poser: (IlotMoteur) -> Void
    }

    /// Le moteur revient au repos : rien d'ouvert, aucune annonce, aucune activité.
    static func vider(_ m: IlotMoteur) {
        m.alerte = nil; m.bandeau = nil; m.rappelsSonnes = []; m.minuteur = nil; m.reunion = nil; m.annonceReunion = nil
        m.claude = nil; m.sessionsClaude = []; m.microCoupe = false; m.lecturePresente = false; m.reveil = nil
        m.ecouteNote.phase = .repos; m.ecouteNote.texte = ""; m.ecouteNote.niveau = 0
        m.fermer()
    }

    static func ecrans(t0: Date) -> [Ecran] {
        let rappel = Rappel(texte: "Appeler le fournisseur", echeance: t0, sonneLe: t0, cree: t0.addingTimeInterval(-3600))
        let session = SessionClaude(id: "essai", dossier: "/Users/exemple/projet", app: "com.apple.Terminal", etat: .travaille,
                                    taches: (1...4).map { TacheClaude(id: "\($0)", sujet: "Étape \($0)", statut: $0 < 2 ? .faite : ($0 == 2 ? .enCours : .aFaire)) },
                                    derniere: t0, titre: "Carte des réglages")
        func telecharge() -> BandeauIlot {
            var r = RafaleTelechargements()
            r.ajouter([FichierTelecharge(url: URL(fileURLWithPath: "/Users/exemple/Downloads/Contrat-signé.pdf"), taille: 2_400_000, airdrop: false)], a: t0)
            return BandeauIlot(vue: .telecharge, jusqua: t0.addingTimeInterval(60), ligne1: r.titre, ligne2: r.sousTitre,
                               telechargement: TelechargementIlot(rafale: r, icones: [NSWorkspace.shared.icon(for: .pdf)]))
        }
        func fichiers(_ n: Int) -> [FichierEtagere] {
            (0..<n).map { i in FichierEtagere(id: UUID(), nom: "Document \(i + 1).pdf", url: URL(fileURLWithPath: "/Users/exemple/Document \(i + 1).pdf"), icone: NSWorkspace.shared.icon(for: .pdf)) }
        }
        return [
            Ecran(nom: "Centre", vue: .centre) { m in m.clicForme() },
            Ecran(nom: "Outils", vue: .outils) { m in m.clicForme(); m.allerA(.outils) },
            Ecran(nom: "Dictées", vue: .dictees) { m in m.clicForme(); m.allerA(.dictees) },
            Ecran(nom: "carte Claude", vue: .claudeCarte) { m in m.claude = session; m.sessionsClaude = [session]; m.ouvrirCarteClaude() },
            Ecran(nom: "Second Brain", vue: .secondBrain) { m in m.ouvrirSecondBrain() },
            Ecran(nom: "Étagère", vue: .etagere) { m in m.etagereActive = true; m.etagere = fichiers(3); m.ouvrirEtagere() },
            Ecran(nom: "Réunion", vue: .reunionEtendu) { m in
                var r = ReunionIlot(); r.depuis = t0.addingTimeInterval(-754); m.reunion = r; m.donneesChangees(); m.clicForme()
            },
            Ecran(nom: "annonce capture", vue: .etagereCapture) { m in
                m.annoncer(bandeau: BandeauIlot(vue: .etagereCapture, jusqua: t0.addingTimeInterval(60), ligne1: "Capture d\u{2019}écran", ligne2: RafaleCaptures.sousTitre))
            },
            Ecran(nom: "annonce rappel (Rappels d'Apple ?)", vue: .lucarne) { m in
                m.annoncer(bandeau: BandeauIlot(vue: .lucarne, jusqua: t0.addingTimeInterval(60), ligne1: "", ligne2: "", lucarne: .questionRappelsApple))
            },
            Ecran(nom: "annonce rappel ajouté", vue: .rappelAjoute) { m in
                m.annoncer(bandeau: BandeauIlot(vue: .rappelAjoute, jusqua: t0.addingTimeInterval(60), ligne1: "Rappel ajouté", ligne2: "Appeler le fournisseur · 15:00"))
            },
            Ecran(nom: "annonce téléchargé", vue: .telecharge) { m in m.annoncer(bandeau: telecharge()) },
            Ecran(nom: "annonce AirDrop", vue: .etagereEnvoi) { m in
                m.annoncer(bandeau: BandeauIlot(vue: .etagereEnvoi, jusqua: t0.addingTimeInterval(60), ligne1: "", ligne2: "",
                                                envoi: EnvoiEtagere(etat: .lance, noms: ["Plan.pdf"], icone: NSWorkspace.shared.icon(for: .pdf))))
            },
            Ecran(nom: "alerte minuteur", vue: .minuteurFini) { m in m.annoncer(alerte: AlerteIlot(vue: .minuteurFini, jusqua: nil, libelle: "10 min")) },
            Ecran(nom: "alerte rappel", vue: .rappelEtendu) { m in
                m.rappelsSonnes = [rappel]; m.annoncer(alerte: AlerteIlot(vue: .rappelEtendu, jusqua: nil, rappel: rappel))
            },
            Ecran(nom: "onde de la note dictée", vue: .outilNote) { m in
                m.ouvrirOutil(.outilNote); m.ecouteNote.phase = .ecoute; m.ecouteNote.niveau = 0.6; m.ecouteNote.texte = "J\u{2019}ai demain une livraison"
            },
        ]
    }
}

extension IlotEssai {
    /// L'état de la Lucarne en une ligne (messages des essais).
    @MainActor
    static func etatLucarne(_ m: IlotMoteur) -> String {
        let k = m.lucarne.capsule.valeur, v = m.lucarne.capsule.cible
        func r(_ c: CapsuleLucarne) -> String { "\(Int(c.x0)),\(Int(c.y0)) \(Int(c.largeur))×\(Int(c.hauteur))" }
        return "[\(m.courante.rawValue), bulle \(m.pastille?.rawValue ?? "—"), \(m.lucarne.place.rawValue), libre \(m.lucarne.libre), geste \(m.lucarne.geste.phase), repli \(m.lucarne.repli), forme \(r(k)) → \(r(v)), boucle \(m.boucleActive ? m.ceQuiBouge : "non")]"
    }

    /// Le verre hors de l'encoche, depuis les quatre coins et les places du milieu à gauche et à droite : la pilule (contenu compact,
    /// bulle de la deuxième activité), puis chaque écran de l'îlot posé dedans. Rien de coupé (la forme a la taille de la mise en page
    /// de l'écran, elle tient dans l'écran, hors de la barre des menus et du Dock, dans la fenêtre et dans la zone de dessin), ouverte
    /// vers l'intérieur, voile de lecture, le vide autour laisse passer les clics, rien ne tourne une fois posée. Puis, en vrai temps :
    /// survol qui ouvre, clic qui ouvre, survol d'un bouton du Centre (SwiftUI reçoit la souris au travers du décalage), et les zones
    /// de l'étagère sous des fichiers glissés.
    @MainActor
    static func verreLucarne(_ c: IlotControleur, verifier: (Bool, String) -> Void, attendre: (Double, () -> Bool) -> Void) {
        func pause(_ s: Double) { attendre(s) { true } }
        let m = c.moteur
        func etat() -> String { IlotEssai.etatLucarne(m) }
        print("— la Lucarne hors de l'encoche : verre, contenu, depuis chaque place")
        guard let e = m.lucarne.ecran, e.avecEncoche else { print("  (écran sans encoche : essai du verre sauté)"); return }
        // les réglages du Centre en mémoire (jamais les vrais : ouvrir le Centre marque l'aide vue, le Centre utilisé…)
        var memoire = (bulle: true, utilise: true, telechargements: false, micro: nil as String?)
        c.reglagesCentre.telechargements = { memoire.telechargements }; c.reglagesCentre.reglerTelechargements = { memoire.telechargements = $0 }
        c.reglagesCentre.microChoisi = { memoire.micro }; c.reglagesCentre.choisirMicro = { memoire.micro = $0 }
        c.reglagesCentre.bulleVue = { memoire.bulle }; c.reglagesCentre.marquerBulleVue = { memoire.bulle = true }
        c.reglagesCentre.centreUtilise = { memoire.utilise }; c.reglagesCentre.marquerCentreUtilise = { memoire.utilise = true }
        c.reglagesCentre.allumerMicro = {}; c.reglagesCentre.allumerClaude = {}; c.reglagesCentre.allumerEtagere = {}
        c.reglagesCentre.secondBrainPropose = { true }; c.reglagesCentre.marquerSecondBrainPropose = {}
        IlotEssai.reglagesLucarneDEssai(c)
        let etagere0 = m.etagereActive, panneauEtagere0 = c.panneau.etagereActive
        defer { m.etagereActive = etagere0; c.panneau.etagereActive = panneauEtagere0 }

        // tous les écrans repliés ont un contenu compact à eux (le logo n'est que pour l'îlot vide)
        let sansContenu = VueIlot.allCases.filter { GeoIlot.profondeur($0) == 0 && $0 != .repos && GenreCompact.de($0) == .logo }
        verifier(sansContenu.isEmpty, "chaque écran replié a son contenu compact dans la pilule \(sansContenu)")

        func rect(_ k: CapsuleLucarne) -> CGRect { CGRect(x: k.x0, y: k.y0, width: k.largeur, height: k.hauteur) }
        /// Posée à cette place, sans geste (comme au lancement).
        func aller(_ p: PlaceLucarne) {
            CatalogueLucarne.vider(m)
            EssaiPlaces.memoire.memoriser(p, pour: EssaiPlaces.ecran)
            c.panneau.demarrer(); m.poser(); pause(0.05)
        }
        /// La zone de dessin de la vue libre, dans le repère de la Lucarne.
        func zoneVue() -> CGRect {
            let o = m.origineVue, t = m.tailleVue
            return CGRect(x: o.x - t.width / 2, y: o.y, width: t.width, height: t.height)
        }
        /// La forme posée tient : dans l'écran, sous la barre, hors du Dock, dans la fenêtre et la zone de dessin (avec son ombre).
        func tient(_ k: CapsuleLucarne) -> String? {
            if k.x0 < e.xBordGauche - 0.01 || k.x1 > e.xBordDroit + 0.01 || k.y1 > e.hauteur + 0.01 { return "hors de l'écran" }
            if k.y0 < e.barre + GeoLucarne.ecartBarre - 0.01 { return "dans la barre des menus (haut à \(Int(k.y0)))" }
            if k.y1 > e.yFond + 0.01, e.recouvreDock(x0: k.x0, x1: k.x1) { return "sur le Dock" }
            if !c.panneau.cadreVoulu.contains(rect(k)) { return "hors de la fenêtre" }
            if !zoneVue().contains(rect(k).insetBy(dx: -12, dy: -12)) { return "hors de la zone de dessin" }
            return nil
        }
        let places: [PlaceLucarne] = [.hautGauche, .hautDroite, .basGauche, .basDroite, .gauche, .droite]
        let t0 = m.maintenant()
        let ecrans = CatalogueLucarne.ecrans(t0: t0)
        var bilan: [String] = []

        for p in places {
            // --- repliée : la pilule de verre, son contenu compact, la bulle de la deuxième activité vers l'intérieur
            aller(p)
            m.minuteur = MinuteurIlot(minutes: 10, depuis: t0.addingTimeInterval(-128)); m.microCoupe = true
            m.donneesChangees(); m.poser(); c.panneau.ajuster()
            let pil = m.lucarne.capsule.cible, genre = GenreCompact.de(m.courante) ?? .logo
            let attendue = GeoLucarne.replie(p, e, taille: GeoLucarne.tailleCompacte(contenu: m.largeurCompacte(genre, debout: p.debout), debout: p.debout))
            verifier(genre == .activite(.micro) && pil == attendue && tient(pil) == nil && m.lucarneDeplie == 0,
                     "\(p.rawValue) : pilule \(p.debout ? "debout" : "couchée") du micro coupé (\(Int(pil.largeur)) × \(Int(pil.hauteur))) \(tient(pil) ?? "") \(etat())")
            if let b = m.rectBulleLibre() {
                let dedans = b.minX >= e.xBordGauche && b.maxX <= e.xBordDroit && b.maxY <= e.hauteur && c.panneau.cadreVoulu.contains(b)
                let interieur = p.debout ? b.minY > pil.y1 : (p.ancre.x > 0.5 ? b.maxX < pil.x0 : b.minX > pil.x1)
                verifier(m.pastille == .minuteur && dedans && interieur && m.contient(CGPoint(x: b.midX, y: b.midY)),
                         "\(p.rawValue) : la bulle du minuteur sort vers l'intérieur, dans la fenêtre, et prend la souris \(etat())")
            } else { verifier(false, "\(p.rawValue) : la bulle du minuteur est là \(etat())") }
            verifier(!m.boucleActive, "\(p.rawValue) : repliée, aucune boucle (bouge encore : \(m.ceQuiBouge))")

            // --- chaque écran de l'îlot, posé dans le verre
            for x in ecrans {
                CatalogueLucarne.vider(m); m.poser()
                x.poser(m); m.donneesChangees(); m.poser(); c.panneau.ajuster()
                let k = m.lucarne.capsule.cible, g = m.grille, v = m.courante
                let largeur = 2 * Double(g.corps(v)), hauteur = Double(g.hauteur(v) - g.barre)
                let mesure = abs(k.largeur - largeur) < 0.5 && abs(k.hauteur - hauteur) < 0.5
                let pr = GeoLucarne.replie(p, e)
                let interieur: Bool
                switch p.ancre.x { case 0: interieur = abs(k.x0 - e.xMin) < 0.5; case 1: interieur = abs(k.x1 - e.xMax) < 0.5; default: interieur = true }
                let vertical = p.ancre.y == 0 ? abs(k.y0 - pr.y0) < 0.5 : (p.ancre.y == 1 ? k.y1 <= pr.y1 + 0.5 : abs(k.centreY - pr.centreY) < 0.5 || k.y0 <= e.yHaut + 0.5 || k.y1 >= e.yFond - 0.5)
                let coin = m.coinContenuLibre
                let contenu = abs(coin.x - k.centreX) < 0.01 && abs(coin.y - k.y0) < 0.01
                let ici = CGPoint(x: k.centreX, y: k.y0 + min(40, k.hauteur / 2)), dehors = CGPoint(x: c.panneau.cadreVoulu.minX + 2, y: c.panneau.cadreVoulu.minY + 2)
                let probleme = v != x.vue ? "écran \(v.rawValue)" : (!mesure ? "taille \(Int(k.largeur)) × \(Int(k.hauteur)) pour \(Int(largeur)) × \(Int(hauteur))" :
                    (tient(k) ?? (!interieur || !vertical ? "pas ouvert vers l'intérieur" : (!contenu ? "contenu décalé" :
                    (m.lucarneDeplie < 1 ? "voile de lecture absent" : (!m.contient(ici) || m.contient(dehors) ? "clics" : (m.boucleActive ? "boucle au repos" : nil)))))))
                if let probleme { bilan.append("\(p.rawValue) · \(x.nom) : \(probleme)") }
            }
        }
        verifier(bilan.isEmpty, "\(ecrans.count) écrans × \(places.count) places : en verre, entiers, vers l'intérieur, lisibles, clics justes, rien ne tourne\(bilan.isEmpty ? "" : " — " + bilan.joined(separator: " ; "))")

        // --- en vrai temps, depuis le coin bas gauche (au-dessus de la ligne du Dock) : le survol ouvre le Centre, il se range en partant
        aller(.basGauche)
        let pil = m.lucarne.capsule.cible
        c.panneau.simulerPointeur(forme: true); pause(0.6); attendre(1.5) { m.boucleActive }
        let k = m.lucarne.capsule.valeur
        verifier(m.courante == .centre && m.lucarne.capsule.fini && k.y1 <= e.yFond + 0.01 && abs(k.x0 - pil.x0) < 0.5 && !m.boucleActive,
                 "coin bas gauche : le survol ouvre le Centre au-dessus du Dock, depuis le bord gauche, puis plus rien ne tourne \(etat())")
        // un vrai mouvement de souris sur un bouton du Centre (posé pour l'encoche, décalé dans le verre) : SwiftUI le reçoit
        m.oublierAide()
        let rond = PlanCentre.centreRond(m, .telechargements), surRond = m.depuisContenu(rond)
        c.panneau.envoyerMouvement(en: surRond); pause(0.8)
        verifier(m.bulleAide == .telechargements, "survol d'un bouton du Centre dans le verre : son aide paraît (la souris atteint le bon bouton)")
        c.panneau.envoyerMouvement(en: CGPoint(x: e.xBordDroit - 40, y: e.hauteur / 2)); c.panneau.simulerPointeur(forme: false); pause(0.6); attendre(1.5) { m.boucleActive }
        verifier(m.courante != .centre && m.lucarne.capsule.fini && m.lucarne.capsule.cible == pil && !m.boucleActive, "souris partie : il se range dans la pilule, plus rien ne tourne \(etat())")
        // un clic court sur la pilule : le Centre s'ouvre (et reste ouvert) ; un clic ailleurs le range
        let centre = CGPoint(x: pil.centreX, y: pil.centreY)
        c.panneau.envoyerSouris(.leftMouseDown, en: centre); pause(0.08); c.panneau.envoyerSouris(.leftMouseUp, en: centre); pause(0.9)
        verifier(m.courante == .centre && m.epingle, "clic court sur la pilule : le Centre s'ouvre depuis la place et reste ouvert")
        m.clicAilleurs(); pause(0.6); attendre(1.5) { m.boucleActive }
        verifier(m.courante != .centre && !m.boucleActive, "clic ailleurs : rangé \(etat())")

        // --- une alerte qui arrive pendant que la Lucarne est en haut à droite : elle part de la place, vers l'intérieur
        aller(.hautDroite)
        m.annoncer(alerte: AlerteIlot(vue: .minuteurFini, jusqua: nil, libelle: "10 min")); pause(0.8); attendre(1.5) { m.boucleActive }
        let a = m.lucarne.capsule.valeur
        verifier(m.courante == .minuteurFini && abs(a.x1 - e.xMax) < 0.5 && abs(a.y0 - e.yHaut) < 0.5 && !m.boucleActive,
                 "alerte du minuteur en haut à droite : elle s'ouvre de la place vers le bas et la gauche, puis plus rien ne tourne \(etat())")
        m.quitterAlerte(); pause(0.9)

        // --- des fichiers glissés vers la Lucarne en haut à gauche : les zones s'ouvrent depuis elle, la zone sous le pointeur s'éclaire
        aller(.hautGauche)
        m.etagereActive = true; c.panneau.etagereActive = true
        let p0 = m.lucarne.capsule.cible
        c.panneau.glisser(CGPoint(x: p0.centreX + 60, y: p0.y1 + 90), fichiers: { true }); pause(0.9)
        let z = m.lucarne.capsule.cible
        verifier(m.depot && m.courante == .etagereDepot && abs(z.x0 - p0.x0) < 0.5 && abs(z.y0 - p0.y0) < 0.5, "fichiers glissés près d'elle : les zones s'ouvrent depuis sa place")
        let gauche = CGPoint(x: z.x0 + z.largeur * 0.25, y: z.y0 + z.hauteur / 2), droite = CGPoint(x: z.x0 + z.largeur * 0.75, y: z.y0 + z.hauteur / 2)
        c.panneau.glisser(gauche, fichiers: { true }); let zg = m.depotZone
        c.panneau.glisser(droite, fichiers: { true }); let zd = m.depotZone
        verifier(zg == .etagere && zd == .airdrop, "sur les zones : « Étagère » à gauche, « AirDrop » à droite (\(String(describing: zg)), \(String(describing: zd)))")
        c.panneau.finDuGlisser(); pause(0.8); attendre(1.5) { m.boucleActive }
        verifier(!m.depot && !m.boucleActive, "glisser fini : les zones se referment \(etat())")

        // --- appui long sur une carte ouverte dans le verre (l'Étagère) : elle se range, la pilule se replie, puis elle se décolle d'elle
        // (jamais de la grande forme) ; relâchée, elle revient à sa place. (Sur le Centre et les cartes qui gardent les clics dans leur
        // vide, l'appui long se fait sur la pilule : dans l'encoche, c'est le cou, dans la barre, qui le reçoit.)
        aller(.hautGauche)
        var tenu = false
        m.boutonEnfonce = { tenu }
        defer { m.boutonEnfonce = { NSEvent.pressedMouseButtons & 1 != 0 } }
        m.etagereActive = true; m.etagere = (0..<3).map { FichierEtagere(id: UUID(), nom: "Document \($0 + 1).pdf", url: URL(fileURLWithPath: "/Users/exemple/Document \($0 + 1).pdf"), icone: NSWorkspace.shared.icon(for: .pdf)) }
        m.ouvrirEtagere(); pause(0.6); attendre(1.5) { m.boucleActive }
        let ouvert = m.lucarne.capsule.cible
        let surFond = CGPoint(x: ouvert.centreX, y: ouvert.y1 - 5)
        tenu = true; c.panneau.envoyerSouris(.leftMouseDown, en: surFond); pause(0.45)
        verifier(m.courante != .etagere && m.lucarne.geste.phase == .decollee && m.lucarne.repli && !m.lucarneEnMain,
                 "appui long sur l'Étagère dans le verre : elle se range, la Lucarne attend d'être repliée \(etat())")
        attendre(1.2) { m.lucarne.repli }
        let pilule = m.lucarne.capsule.valeur
        verifier(m.lucarneEnMain && !m.lucarne.repli && pilule.hauteur < 60, "repliée : elle se décolle de sa pilule (\(Int(pilule.largeur)) × \(Int(pilule.hauteur))) \(etat())")
        c.panneau.envoyerSouris(.leftMouseUp, en: surFond); tenu = false; pause(0.6); attendre(1.5) { m.boucleActive }
        verifier(m.lucarne.libre && !m.lucarneEnMain && !m.boucleActive, "relâchée : posée à sa place (\(m.lucarne.place.rawValue)), plus rien ne tourne \(etat())")
        // un bandeau dans le verre ne se décolle pas (il attend sa fin, comme dans l'encoche) : l'appui s'arrête
        aller(.hautGauche)
        m.annoncer(bandeau: BandeauIlot(vue: .rappelAjoute, jusqua: m.maintenant().addingTimeInterval(60), ligne1: "Rappel ajouté", ligne2: "Appeler le fournisseur · 15:00"))
        pause(0.6); attendre(1.5) { m.boucleActive }
        let b = m.lucarne.capsule.cible, surBandeau = CGPoint(x: b.x0 + 14, y: b.centreY)
        tenu = true; c.panneau.envoyerSouris(.leftMouseDown, en: surBandeau); pause(0.6)
        verifier(m.courante == .rappelAjoute && m.lucarne.geste.phase == .repos && !m.lucarneEnMain && m.lucarne.capsule.cible == b,
                 "appui long sur un bandeau dans le verre : rien ne se décolle \(etat())")
        c.panneau.envoyerSouris(.leftMouseUp, en: surBandeau); tenu = false; pause(0.3)
        m.quitterBandeau(); pause(0.6); attendre(1.5) { m.boucleActive }

        // --- retour dans l'encoche pour la suite de l'essai
        CatalogueLucarne.vider(m)
        EssaiPlaces.memoire.memoriser(.encoche, pour: EssaiPlaces.ecran)
        c.panneau.demarrer(); m.poser(); pause(0.3)
        verifier(!m.lucarne.libre && !m.boucleActive, "de retour dans l'encoche, plus rien ne tourne")
    }
}

// MARK: - les bords (mission 4)

extension IlotEssai {
    /// La Lucarne au bord des choses, avec de faux écrans et un faux Dock (jamais les vrais) : Dock à gauche, à droite, masqué (lu une
    /// fois, relu seulement quand il change) ; lâchée au milieu de l'écran (jamais l'encoche) ; deux écrans (glissée de l'un à l'autre,
    /// une place par écran, écran débranché puis rebranché) ; écran principal sans encoche (la pilule du haut au milieu, visible même
    /// vide) ; VoiceOver « Déplacer vers… ». Vrais événements souris remis à la fenêtre, fenêtre invisible.
    @MainActor
    static func bordsLucarne(_ c: IlotControleur, verifier: (Bool, String) -> Void, attendre: (Double, () -> Bool) -> Void) {
        func pause(_ s: Double) { attendre(s) { true } }
        let m = c.moteur
        print("— la Lucarne aux bords : Dock, deux écrans, sans encoche, VoiceOver")
        guard let principal = EssaiPlaces.ecrans.first, principal.geometrie.reelle else { print("  (écran sans encoche : essai des bords sauté)"); return }
        func etat() -> String { IlotEssai.etatLucarne(m) }
        let ecrans0 = EssaiPlaces.ecrans, dock0 = EssaiPlaces.dock
        var tenu = false
        m.boutonEnfonce = { tenu }
        defer {
            m.boutonEnfonce = { NSEvent.pressedMouseButtons & 1 != 0 }
            EssaiPlaces.ecrans = ecrans0; EssaiPlaces.dock = dock0
        }
        CatalogueLucarne.vider(m); pause(0.6)

        /// Un point de l'écran `e` (repère de la Lucarne sur lui) en coordonnées globales d'AppKit, et un point global dans le repère de
        /// l'écran où vit l'îlot en ce moment (les événements de l'essai se donnent dans ce repère).
        func global(_ q: CGPoint, sur e: EcranIlot) -> CGPoint { CGPoint(x: e.centre + q.x, y: e.frame.maxY - q.y) }
        func ici(_ g: CGPoint) -> CGPoint {
            guard let e = c.panneau.ecran else { return g }
            return CGPoint(x: g.x - c.panneau.centre, y: e.frame.maxY - g.y)
        }
        func bas(_ g: CGPoint) { tenu = true; c.panneau.envoyerSouris(.leftMouseDown, en: ici(g)) }
        func glisse(_ g: CGPoint) { c.panneau.envoyerSouris(.leftMouseDragged, en: ici(g)) }
        func haut(_ g: CGPoint) { c.panneau.envoyerSouris(.leftMouseUp, en: ici(g)); tenu = false }
        /// Un glisser (coordonnées globales) de `a` à `b` en `n` pas de 16 ms : chaque point est redonné dans le repère du moment.
        func trainer(_ a: CGPoint, _ b: CGPoint, n: Int = 24) {
            for i in 1...n { let u = CGFloat(i) / CGFloat(n); glisse(CGPoint(x: a.x + (b.x - a.x) * u, y: a.y + (b.y - a.y) * u)); pause(0.016) }
        }
        /// Le milieu de la forme, en coordonnées globales (dans l'encoche : son milieu dans la barre).
        func centreG() -> CGPoint {
            guard let e = c.panneau.ecran else { return .zero }
            let p = m.lucarne.libre ? CGPoint(x: m.lucarne.capsule.cx.x, y: m.lucarne.capsule.cy.x) : CGPoint(x: 0, y: Double(m.geometrie.hauteur) / 2)
            return CGPoint(x: c.panneau.centre + p.x, y: e.frame.maxY - p.y)
        }
        /// Appui long sur la forme, glissé jusqu'à `b` (global), immobile 0,2 s puis relâché : sans élan.
        func deplacer(vers b: CGPoint) {
            let a = centreG()
            bas(a); pause(0.5); trainer(a, b); pause(0.25); haut(b); pause(1.2); attendre(1.5) { m.boucleActive }
        }
        /// Posée à cette place du principal, sans geste (comme au lancement).
        func reposer(_ p: PlaceLucarne) {
            CatalogueLucarne.vider(m)
            EssaiPlaces.memoire.poser(p, sur: EssaiPlaces.ecran)
            c.panneau.recaler(); m.poser(); pause(0.1)
        }
        /// La fenêtre (globale) entoure-t-elle la forme posée ?
        func fenetreAutour() -> Bool {
            guard let f = c.panneau.cadre, let e = c.panneau.ecran else { return false }
            let k = m.lucarne.capsule.valeur
            let r = CGRect(x: c.panneau.centre + k.x0, y: e.frame.maxY - k.y1, width: k.largeur, height: k.hauteur)
            return f.insetBy(dx: -0.5, dy: -0.5).contains(r)
        }
        /// Le faux écran principal avec ce Dock (sa zone visible suit) ; le faux Dock change, le panneau est prévenu.
        func dock(_ cote: CoteDock, masque: Bool) {
            var p = EssaiPlaces.principal(dock: cote == .bas && !masque ? 70 : 0)
            if !masque, cote != .bas {
                let f = p.frame
                p.zoneVisible = CGRect(x: f.minX + (cote == .gauche ? 70 : 0), y: f.minY, width: f.width - 70, height: f.height - p.geometrie.hauteur)
            }
            EssaiPlaces.ecrans = [p]
            EssaiPlaces.dock = PrefsDock(cote: cote, masque: masque, tailleIcone: 56)
            c.panneau.dockChange(); m.poser(); pause(0.1)
        }

        // --- le Dock : lu une fois, relu seulement quand il change
        let lectures0 = EssaiPlaces.lecturesDock
        c.panneau.recaler(); c.panneau.recaler()
        verifier(EssaiPlaces.lecturesDock == lectures0, "écrans remesurés deux fois : le Dock n'est pas relu (\(EssaiPlaces.lecturesDock - lectures0) lecture)")
        let place0 = m.lucarne.place, ecritures0 = EssaiPlaces.ecritures
        c.panneau.dockChange()
        verifier(EssaiPlaces.lecturesDock == lectures0 + 1 && m.lucarne.place == place0 && EssaiPlaces.ecritures == ecritures0,
                 "le Dock prévient d'un changement qui n'en est pas un : relu une fois, rien ne bouge")

        // --- Dock à gauche, à droite, masqué : les places de son côté sont décalées, les dépliés ne le couvrent pas
        for (cote, masque, nom) in [(CoteDock.gauche, false, "à gauche"), (.droite, false, "à droite"), (.bas, true, "masqué")] {
            dock(cote, masque: masque)
            guard let e = m.lucarne.ecran else { verifier(false, "Dock \(nom) : écran mesuré"); continue }
            verifier(e.dockCote == cote && e.dockMasque == masque, "Dock \(nom) : lu depuis le faux Dock (relu parce qu'il a changé)")
            let places: [PlaceLucarne] = cote == .gauche ? [.hautGauche, .gauche, .basGauche] : (cote == .droite ? [.hautDroite, .droite, .basDroite] : [.basGauche, .basMilieu, .basDroite])
            var bilan: [String] = []
            for p in places {
                reposer(p)
                let k = m.lucarne.capsule.valeur
                let libre: Bool
                switch cote {
                case .gauche: libre = k.x0 >= e.xBordGauche + 70 + GeoLucarne.marge - 0.01
                case .droite: libre = k.x1 <= e.xBordDroit - 70 - GeoLucarne.marge + 0.01
                case .bas: libre = k.y1 <= e.hauteur - 70 - GeoLucarne.marge + 0.01
                }
                if !libre || !fenetreAutour() || m.boucleActive { bilan.append("\(p.rawValue) \(etat())") }
                // le Centre ouvert depuis cette place : vers l'intérieur, jamais sur le Dock
                m.clicForme(); m.poser(); c.panneau.ajuster()
                let o = m.lucarne.capsule.valeur
                let surDock: Bool
                switch cote {
                case .gauche: surDock = o.x0 < e.xBordGauche + 70 - 0.01
                case .droite: surDock = o.x1 > e.xBordDroit - 70 + 0.01
                case .bas: surDock = o.y1 > e.hauteur - 70 + 0.01
                }
                if m.courante != .centre || surDock || o.y0 < e.yHaut - 0.01 { bilan.append("\(p.rawValue) Centre \(etat())") }
                m.fermer(); m.poser()
            }
            verifier(bilan.isEmpty, "Dock \(nom) : \(places.map(\.rawValue).joined(separator: ", ")) décalées hors du Dock (70 pt + 10), le Centre s'ouvre à côté\(bilan.isEmpty ? "" : " — " + bilan.joined(separator: " ; "))")
        }
        dock(.bas, masque: false)

        // --- lâchée au milieu de l'écran : la place la plus proche parmi les sept autres, jamais l'encoche
        reposer(.encoche)
        guard let e = m.lucarne.ecran else { return }
        let milieu = global(CGPoint(x: 0, y: e.hauteur / 2), sur: principal)
        deplacer(vers: milieu)
        let attendue = GeoLucarne.plusProche(x: m.lucarne.capsule.cx.x, y: m.lucarne.capsule.cy.x, e)
        verifier(m.lucarne.libre && m.lucarne.place != .encoche && m.lucarne.place == attendue && !m.boucleActive,
                 "lâchée au milieu de l'écran : \(m.lucarne.place.rawValue), pas l'encoche \(etat())")

        // --- deux écrans : glissée de l'un à l'autre, une place par écran
        let externe = EssaiPlaces.externe()
        EssaiPlaces.ecrans = [EssaiPlaces.principal(), externe]
        reposer(.hautDroite)
        let surExterne = global(CGPoint(x: -300, y: 500), sur: externe)
        let a = centreG()
        bas(a); pause(0.5)
        verifier(m.lucarneEnMain, "appui long sur la Lucarne en haut à droite : décollée")
        // pas à pas : jamais de saut au passage d'un écran à l'autre (la forme passe le bord avec le doigt)
        var saut = 0.0, avant = centreG()
        for i in 1...40 {
            let u = CGFloat(i) / 40, q = CGPoint(x: a.x + (surExterne.x - a.x) * u, y: a.y + (surExterne.y - a.y) * u)
            glisse(q); pause(0.016)
            let k = centreG(); saut = max(saut, hypot(k.x - avant.x, k.y - avant.y)); avant = k
        }
        pause(0.3)
        let pas = hypot(surExterne.x - a.x, surExterne.y - a.y) / 40
        verifier(saut < pas + 12, "d'un écran à l'autre : la forme suit le doigt sans saut (au plus \(Int(saut)) pt d'un mouvement à l'autre, pas de \(Int(pas)) pt)")
        let pointe = m.lucarne.geste.pointeur, d = m.lucarne.capsule.decalage
        verifier(c.panneau.ecran?.id == externe.id && m.lucarne.uuid == externe.id && m.lucarne.ecran?.avecEncoche == false,
                 "glissée sur l'écran externe : l'îlot y vit (sa géométrie, sa clé) \(etat())")
        verifier(abs(pointe.x - (-300)) < 0.5 && abs(pointe.y - 500) < 0.5 && abs(m.lucarne.capsule.cx.x - (pointe.x + d.x)) < 0.01
                 && abs(m.lucarne.capsule.cy.x - (pointe.y + d.y)) < 0.01,
                 "… et elle reste sous le doigt, dans le repère du nouvel écran (pointeur \(Int(pointe.x)), \(Int(pointe.y)))")
        if let f = c.panneau.cadre {
            let k = centreG()
            verifier(abs(f.midX - k.x) < 1 && abs(f.midY - k.y) < 1 && externe.frame.contains(k), "la fenêtre la suit sur l'écran externe")
        }
        verifier(m.lucarne.pres == false && m.lucarne.capsule.noir.cibleFinale == 0, "tenue sur l'écran sans encoche : une pilule de verre")
        haut(surExterne); pause(1.2); attendre(1.5) { m.boucleActive }
        let surE = EssaiPlaces.memoire.place(pour: externe.id)
        verifier(m.lucarne.libre && m.lucarne.place == surE && EssaiPlaces.memoire.ecranChoisi == externe.id
                 && EssaiPlaces.memoire.place(pour: EssaiPlaces.ecran) == .hautDroite && !m.boucleActive,
                 "lâchée sur l'écran externe : posée (\(surE.rawValue)), retenue pour lui, il devient le sien ; la place du principal reste")
        if let f = c.panneau.cadre { verifier(externe.frame.contains(f) && fenetreAutour(), "posée : sa fenêtre est sur l'écran externe, autour d'elle") }
        // tout en haut au milieu de l'écran externe (sans caméra) : la pilule du haut, jamais aspirée dans une fausse encoche
        deplacer(vers: global(CGPoint(x: 6, y: 34), sur: externe))
        let haute = GeoLucarne.replie(.encoche, m.lucarne.ecran ?? e)
        verifier(m.lucarne.libre && m.lucarne.place == .encoche && !m.lucarne.aspiree && abs(m.lucarne.capsule.cy.x - haute.centreY) < 0.01 && c.panneau.estVisible,
                 "écran externe sans encoche, lâchée en haut au milieu : la pilule de verre sous la barre, visible \(etat())")

        // --- l'écran externe débranché : elle revient sur le principal, à sa place ; rebranché, elle y retourne
        EssaiPlaces.ecrans = [EssaiPlaces.principal()]
        c.panneau.recaler(); m.poser(); pause(0.2)
        verifier(c.panneau.ecran?.id == EssaiPlaces.ecran && m.lucarne.place == .hautDroite && m.lucarne.libre && fenetreAutour() && !m.boucleActive,
                 "écran externe débranché : de retour sur le principal, à sa place (\(m.lucarne.place.rawValue)) \(etat())")
        verifier(EssaiPlaces.memoire.ecranChoisi == externe.id, "… l'écran choisi reste retenu (rebranché, elle y retournera)")
        EssaiPlaces.ecrans = [EssaiPlaces.principal(), externe]
        c.panneau.recaler(); m.poser(); pause(0.2)
        verifier(c.panneau.ecran?.id == externe.id && m.lucarne.place == .encoche && m.lucarne.libre, "rebranché : elle y retourne, à sa place \(etat())")

        // --- ramenée de l'écran externe dans l'encoche du principal : aspirée, l'encoche de cet écran, retenu comme le sien
        let a2 = centreG(), encoche = global(CGPoint(x: 0, y: principal.geometrie.hauteur / 2 + 6), sur: principal)
        bas(a2); pause(0.5); trainer(a2, encoche, n: 40); pause(0.4)
        verifier(c.panneau.ecran?.id == EssaiPlaces.ecran && m.lucarne.pres == true, "glissée vers l'encoche du principal : de retour sur lui, aimantée \(etat())")
        haut(encoche); pause(1.2); attendre(1.5) { m.boucleActive }
        verifier(!m.lucarne.libre && m.lucarne.place == .encoche && EssaiPlaces.memoire.ecranChoisi == EssaiPlaces.ecran && !m.boucleActive
                 && m.trace.bande <= Double(m.demiCamera) + GeoIlot.aileMax + 0.01,
                 "lâchée près de l'encoche du principal : aspirée (cou ≤ 66 pt), le principal redevient le sien \(etat())")

        // --- VoiceOver : « Déplacer vers… », une action par autre place, sur la Lucarne
        EssaiPlaces.ecrans = [EssaiPlaces.principal()]
        reposer(.encoche)
        let attendues = PlaceLucarne.actionsDeplacer(depuis: .encoche, avecEncoche: true).map(\.nom)
        let trouvees = IlotEssai.actionsAccessibles(c.panneau.vueEssai)
        verifier(attendues.allSatisfy(trouvees.keys.contains) && !trouvees.keys.contains("Déplacer vers l'encoche"),
                 "VoiceOver trouve sur la Lucarne : \(attendues.filter(trouvees.keys.contains).count)/7 actions « Déplacer vers… » (pas vers sa propre place)")
        m.clicForme(); pause(0.6)
        let e0 = EssaiPlaces.ecritures
        let versBG = IlotEssai.actionsAccessibles(c.panneau.vueEssai)["Déplacer vers le bas à gauche"]
        let parVoiceOver = versBG?() ?? false
        if versBG == nil { m.lucarne.deplacer(.basGauche) }   // l'essai continue, l'échec est déjà dit
        m.poser(); pause(0.2)
        let bg = m.capsuleRepliee(e)
        verifier(parVoiceOver && m.lucarne.place == .basGauche && m.lucarne.libre && !m.fenetreOuverte && m.lucarne.capsule.valeur == bg && EssaiPlaces.ecritures == e0 + 1
                 && EssaiPlaces.memoire.place(pour: EssaiPlaces.ecran) == .basGauche && fenetreAutour() && !m.boucleActive,
                 "VoiceOver « Déplacer vers le bas à gauche » (Centre ouvert) : le Centre se range, posée en bas à gauche, retenue, plus rien ne tourne \(etat())")
        let depuisBG = IlotEssai.actionsAccessibles(c.panneau.vueEssai)
        verifier(depuisBG.keys.contains("Déplacer vers l'encoche") && !depuisBG.keys.contains("Déplacer vers le bas à gauche") && depuisBG.count >= 7,
                 "hors de l'encoche, dans le verre : les actions suivent la place")
        let versEncoche = depuisBG["Déplacer vers l'encoche"]
        let parVoiceOver2 = versEncoche?() ?? false
        if versEncoche == nil { m.lucarne.deplacer(.encoche) }
        m.poser(); pause(0.2)
        verifier(parVoiceOver2 && !m.lucarne.libre && m.lucarne.place == .encoche && !m.boucleActive, "VoiceOver « Déplacer vers l'encoche » : de retour dans l'encoche \(etat())")

        // --- écran principal sans encoche : la place du haut au milieu est une pilule de verre, visible même vide (décision A)
        var sans = EssaiPlaces.principal()
        sans.geometrie.reelle = false; sans.geometrie.hauteur = 24; sans.centre = sans.frame.midX
        sans.zoneVisible = CGRect(x: sans.frame.minX, y: sans.frame.minY + 70, width: sans.frame.width, height: sans.frame.height - 24 - 70)
        EssaiPlaces.ecrans = [sans]
        reposer(.encoche)
        guard let es = m.lucarne.ecran else { return }
        let pil = m.lucarne.capsule.valeur
        verifier(!es.avecEncoche && m.lucarne.libre && m.courante == .repos && abs(pil.centreX) < 0.01 && abs(pil.y0 - es.yHaut) < 0.01 && pil.s > 0
                 && c.panneau.estVisible && fenetreAutour() && m.contient(CGPoint(x: pil.centreX, y: pil.centreY)) && !m.boucleActive,
                 "écran sans encoche, rien d'actif : la pilule de verre en haut au milieu, visible, cliquable, rien ne tourne \(etat())")
        c.panneau.envoyerSouris(.leftMouseDown, en: CGPoint(x: pil.centreX, y: pil.centreY)); pause(0.08)
        c.panneau.envoyerSouris(.leftMouseUp, en: CGPoint(x: pil.centreX, y: pil.centreY)); pause(0.9)
        let ouvert = m.lucarne.capsule.valeur
        verifier(m.courante == .centre && abs(ouvert.centreX) < 0.5 && abs(ouvert.y0 - es.yHaut) < 0.5, "un clic : le Centre s'ouvre de la pilule, vers le bas \(etat())")
        m.clicAilleurs(); pause(0.6); attendre(1.5) { m.boucleActive }
        // retirée d'elle puis lâchée en haut au milieu : elle reste une pilule (jamais aspirée)
        deplacer(vers: global(CGPoint(x: -500, y: 600), sur: sans))
        let noms = IlotEssai.actionsAccessibles(c.panneau.vueEssai)
        verifier(m.lucarne.place != .encoche && noms.keys.contains("Déplacer vers le haut au milieu") && !noms.keys.contains("Déplacer vers l'encoche"),
                 "VoiceOver, sans caméra : « Déplacer vers le haut au milieu » (jamais « l'encoche ») depuis \(m.lucarne.place.rawValue) — trouvées : \(noms.keys.sorted())")
        deplacer(vers: global(CGPoint(x: 4, y: 30), sur: sans))
        verifier(m.lucarne.place == .encoche && m.lucarne.libre && !m.lucarne.aspiree && c.panneau.estVisible && !m.boucleActive,
                 "lâchée en haut au milieu : la pilule de verre, jamais une fausse encoche \(etat())")

        // --- retour : le vrai principal, le Dock d'origine, dans l'encoche
        EssaiPlaces.ecrans = ecrans0; EssaiPlaces.dock = dock0
        c.panneau.dockChange()
        reposer(.encoche)
        verifier(!m.lucarne.libre && c.panneau.ecran?.id == EssaiPlaces.ecran && !m.boucleActive && m.lucarne.reveil == nil && m.lucarne.garde == nil,
                 "fin : dans l'encoche du principal, plus rien ne tourne, aucun réveil")
    }

    /// Les actions d'accessibilité nommées sous la vue (ce que VoiceOver propose), par nom : de quoi les déclencher comme lui. SwiftUI ne
    /// construit son arbre d'accessibilité que pour un client d'accessibilité : l'essai se déclare comme VoiceOver le fait (l'attribut
    /// « AXEnhancedUserInterface » de l'app, dans ce processus seulement, rendu tout de suite après) ; les nœuds de SwiftUI
    /// (`AccessibilityNode`) ne se lisent que par leurs sélecteurs (sondé le 12/11 : ils ne se déclarent pas `NSAccessibilityProtocol`).
    @MainActor
    static func actionsAccessibles(_ vue: NSView?) -> [String: () -> Bool] {
        let regler = NSSelectorFromString("accessibilitySetValue:forAttribute:"), attribut = "AXEnhancedUserInterface" as NSString
        _ = NSApp.perform(regler, with: NSNumber(value: true), with: attribut)
        defer { _ = NSApp.perform(regler, with: NSNumber(value: false), with: attribut) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        func lire(_ o: NSObject, _ nom: String) -> [Any] {
            let sel = NSSelectorFromString(nom)
            guard o.responds(to: sel) else { return [] }
            return o.perform(sel)?.takeUnretainedValue() as? [Any] ?? []
        }
        var trouvees: [String: () -> Bool] = [:]
        func parcourir(_ el: Any, profondeur: Int) {
            guard profondeur < 40, let o = el as? NSObject else { return }
            for case let x as NSAccessibilityCustomAction in lire(o, "accessibilityCustomActions") where trouvees[x.name] == nil {
                trouvees[x.name] = { x.handler?() ?? false }
            }
            for e in lire(o, "accessibilityChildren") { parcourir(e, profondeur: profondeur + 1) }
        }
        if let vue { parcourir(vue, profondeur: 0) }
        return trouvees
    }
}

// MARK: - la dictée à la place de la Lucarne

extension IlotEssai {
    /// La dictée (fn) quand la Lucarne est posée dans un coin : la fenêtre de la dictée (la vraie, invisible) se montre à sa place, en
    /// verre, et rien dans l'encoche ; le texte en direct élargit la pilule vers l'intérieur ; mains libres, ✕ et ✓ prennent le clic ; un
    /// message (« Champ protégé… ») aussi ; la Lucarne s'efface le temps de la dictée et revient à sa place. Dans l'encoche : comme avant.
    @MainActor
    static func dicteeLucarne(_ c: IlotControleur, verifier: (Bool, String) -> Void, attendre: (Double, () -> Bool) -> Void) {
        func pause(_ s: Double) { attendre(s) { true } }
        let m = c.moteur
        print("— la dictée à la place de la Lucarne (en verre), l'encoche vide")
        guard let principal = EssaiPlaces.ecrans.first, principal.geometrie.reelle else { print("  (écran sans encoche : essai de la dictée sauté)"); return }
        let d = EnclochePanneau()
        d.invisible = true
        d.placementLibre = { [weak c] in c?.panneau.placementDictee }
        var valide = 0, annule = 0
        d.modele.surValider = { valide += 1 }
        d.modele.surAnnuler = { annule += 1 }
        var occ = OccupationEncoche()
        c.occupation = { occ }
        defer { d.fermer(); c.occupation = { OccupationEncoche() }; c.occupationChangee() }
        func dicter(_ oui: Bool) { occ.dictee = oui; c.occupationChangee() }
        func reposer(_ p: PlaceLucarne) {
            CatalogueLucarne.vider(m)
            EssaiPlaces.memoire.poser(p, sur: EssaiPlaces.ecran)
            c.panneau.recaler(); m.poser(); pause(0.2)
        }
        /// L'encoche du principal (la caméra et ses ailes), en coordonnées globales : rien de la dictée n'y va quand la Lucarne est ailleurs.
        let g = principal.geometrie
        let encoche = NSRect(x: principal.centre - g.largeur / 2 - GeometrieEncoche.aile, y: principal.frame.maxY - g.hauteur - GeometrieEncoche.hauteurRuban,
                             width: g.largeur + 2 * GeometrieEncoche.aile, height: g.hauteur + GeometrieEncoche.hauteurRuban)
        func globale(_ k: CapsuleLucarne) -> NSRect {
            NSRect(x: principal.centre + CGFloat(k.x0), y: principal.frame.maxY - CGFloat(k.y1), width: CGFloat(k.largeur), height: CGFloat(k.hauteur))
        }
        var bilan: [String] = []
        for p in [PlaceLucarne.hautGauche, .hautDroite, .basGauche, .basDroite] {
            reposer(p)
            guard let e = m.lucarne.ecran, c.panneau.placementDictee?.place == p else { bilan.append("\(p.rawValue) : pas de placement"); continue }
            let lucarne = m.lucarne.capsule.valeur
            d.ouvrir(app: nil, mainsLibres: false); dicter(true); pause(0.9)
            let compacte = GeoLucarne.dictee(p, e, ruban: false, mainsLibres: false)
            guard let f = d.cadre else { bilan.append("\(p.rawValue) : fenêtre absente"); continue }
            // à sa place : la pilule de la dictée part du même bord que la Lucarne, dans l'écran, hors de la barre et du Dock
            let bord = p.ancre.x == 0 ? abs(compacte.x0 - lucarne.x0) < 0.5 : abs(compacte.x1 - lucarne.x1) < 0.5
            let ici = globale(compacte)
            if !d.horsEncoche || !f.contains(ici) || f.intersects(encoche) { bilan.append("\(p.rawValue) : fenêtre \(f) pas à la place (pilule \(ici))") }
            if !bord || compacte.y0 < e.yHaut - 0.01 || (compacte.y1 > e.yFond + 0.01 && e.recouvreDock(x0: compacte.x0, x1: compacte.x1)) {
                bilan.append("\(p.rawValue) : pilule \(Int(compacte.x0)),\(Int(compacte.y0)) loin de la Lucarne \(Int(lucarne.x0)),\(Int(lucarne.y0))")
            }
            if c.panneau.estVisible || !m.cache { bilan.append("\(p.rawValue) : la Lucarne reste affichée pendant la dictée") }
            // le texte arrive : la pilule s'allonge vers l'intérieur, son bord côté écran ne bouge pas
            d.mettreAJourTexte("Je te rappelle demain pour le devis"); pause(0.4)
            let ruban = GeoLucarne.dictee(p, e, ruban: true, mainsLibres: false)
            let fixe = p.ancre.x == 0 ? abs(ruban.x0 - compacte.x0) < 0.01 : abs(ruban.x1 - compacte.x1) < 0.01
            if !d.modele.ruban || !fixe || !f.contains(globale(ruban)) { bilan.append("\(p.rawValue) : le ruban ne s'ouvre pas vers l'intérieur") }
            // mains libres : ✓ au bout, côté intérieur ou extérieur, prend le clic (un vrai clic remis à la fenêtre)
            d.passerEnMainsLibres(); pause(0.5)
            let r = d.placementLibre()?.pilule(ruban: true, mainsLibres: true) ?? .zero
            let v0 = valide, a0 = annule
            d.cliquerEssai(en: NSPoint(x: f.minX + r.maxX - 24, y: f.maxY - r.midY)); pause(0.2)
            d.cliquerEssai(en: NSPoint(x: f.minX + r.minX + 24, y: f.maxY - r.midY)); pause(0.2)
            if valide != v0 + 1 || annule != a0 + 1 { bilan.append("\(p.rawValue) : ✕ / ✓ ne prennent pas le clic (✓ \(valide - v0), ✕ \(annule - a0))") }
            d.figer(); d.fermer(); dicter(false); pause(1.0)
            if d.cadre != nil || !c.panneau.estVisible || m.lucarne.place != p || m.boucleActive {
                bilan.append("\(p.rawValue) : après la dictée \(IlotEssai.etatLucarne(m)), fenêtre de dictée \(String(describing: d.cadre))")
            }
        }
        verifier(bilan.isEmpty, "dictée avec la Lucarne dans chacun des 4 coins : en verre à sa place (rien dans l'encoche), le texte l'allonge vers l'intérieur, ✕ et ✓ cliquables, la Lucarne revient après\(bilan.isEmpty ? "" : " — " + bilan.joined(separator: " ; "))")

        // un message (« Champ protégé… », une erreur) depuis le bas du milieu : à la place, en verre
        reposer(.basMilieu)
        d.afficherMessage("Champ protégé, texte copié", app: nil, duree: 0.6); dicter(true); pause(0.3)
        if let f = d.cadre, let e = m.lucarne.ecran {
            let k = GeoLucarne.dictee(.basMilieu, e, ruban: true, mainsLibres: false)
            verifier(d.horsEncoche && d.modele.message != nil && f.contains(globale(k)) && !f.intersects(encoche) && abs(k.centreX) < 0.01,
                     "un message en bas au milieu : dans la pilule de verre à la place de la Lucarne (\(Int(k.largeur)) pt), rien dans l'encoche")
        } else { verifier(false, "un message en bas au milieu : la fenêtre de dictée est là") }
        pause(0.8); dicter(false); pause(0.8)
        verifier(d.cadre == nil, "le message parti, la fenêtre de la dictée s'en va")

        // dans l'encoche : la dictée comme avant (noire, dans l'encoche)
        reposer(.encoche)
        d.ouvrir(app: nil, mainsLibres: false); dicter(true); pause(0.5)
        if let f = d.cadre {
            verifier(!d.horsEncoche && c.panneau.placementDictee == nil && abs(f.midX - principal.centre) < 1 && abs(f.maxY - principal.frame.maxY) < 1,
                     "la Lucarne dans l'encoche : la dictée s'y montre, comme avant")
        } else { verifier(false, "la Lucarne dans l'encoche : la fenêtre de dictée est là") }
        d.fermer(); dicter(false); pause(1.0)
        verifier(!m.lucarne.libre && c.panneau.estVisible && !m.boucleActive, "fin de la dictée : la Lucarne dans l'encoche, plus rien ne tourne")
    }
}
