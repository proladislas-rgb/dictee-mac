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
        ] + CatalogueVoix.ecrans(t0: t0)
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
