import AppKit
import DicteeCore

extension IlotEssai {
    /// Revenir en arrière (13/11) : de VRAIS clics et de VRAIS défilements (deux doigts, horizontaux et verticaux) remis à la fenêtre
    /// invisible de l'essai. Centre › Outils › détail de Groq : « ‹ Outils » y ramène, deux doigts vers la droite aussi ; la liste des
    /// Dictées défile toujours ; un détail sous un pointeur immobile se referme seul, sous un pointeur qui bouge il reste. L'usage de Groq
    /// est celui de l'essai (aucun appel, aucun fichier lu).
    @MainActor
    static func retour(_ c: IlotControleur, verifier: (Bool, String) -> Void, attendre: (Double, () -> Bool) -> Void) {
        let m = c.moteur, g = m.geometrie
        func pause(_ s: Double) { attendre(s) { true } }
        func clic(_ p: CGPoint, _ apres: Double = 0.6) {
            c.panneau.envoyerSouris(.leftMouseDown, en: p); pause(0.06); c.panneau.envoyerSouris(.leftMouseUp, en: p); pause(apres)
        }
        let droite = c.panneau.signeDoigtsVersLaDroite()
        /// Un vrai geste à deux doigts : `dx` et `dy` par pas (sens AppKit pour dy ; dx déjà dans le sens « doigts vers la droite »).
        func geste(dx: [Int32], dy: [Int32], en p: CGPoint) {
            for i in 0..<max(dx.count, dy.count) {
                c.panneau.envoyerDefilement(dy: i < dy.count ? dy[i] : 0, dx: (i < dx.count ? dx[i] : 0) * droite, en: p, phase: i == 0 ? 1 : 2); pause(0.016)
            }
            c.panneau.envoyerDefilement(dy: 0, en: p, phase: 4); pause(0.02)
            // l'inertie qui suit le lever des doigts (elle ne doit rien faire de plus)
            for _ in 0..<4 { c.panneau.envoyerDefilement(dy: 0, dx: 6 * droite, en: p, phase: 0, inertie: 2); pause(0.016) }
            c.panneau.envoyerDefilement(dy: 0, en: p, phase: 0, inertie: 3); pause(0.02)
        }
        func ouvrirLeDetail(_ quoi: String) {
            clic(PlanCentre.centreRond(m, .groq), 0.9)
            verifier(m.courante == .groq && m.detailOuvert && m.bandeauVu?.retour == "Outils",
                     "\(quoi) : un vrai clic sur la jauge de Groq, le détail avec « ‹ \(m.bandeauVu?.retour ?? "?") » (\(m.courante))")
        }
        func pointRetourDetail() -> CGPoint {
            let z = m.grille.zoneAnnonce(.groq)
            return CGPoint(x: z.minX + ContenuAnnonce.largeurRetour(m.bandeauVu?.retour ?? "Outils") / 2, y: z.midY)
        }

        print("Revenir en arrière : « ‹ », deux doigts vers la droite, jamais bloqué")
        c.lecture.modele.morceau = nil; c.lecture.surIlot(false)
        m.fermer(); c.panneau.simulerPointeur(forme: false); pause(0.8)
        attendre(6) { m.bandeau != nil }
        print("  deux doigts vers la droite : dx \(droite > 0 ? "positif" : "négatif") (sens naturel de l'essai)")

        // --- Centre › Outils (vrais clics) › détail de Groq
        m.clicForme(); pause(0.9)
        verifier(m.courante == .centre && m.pileRetour.estVide && m.cibleRetour == nil, "un clic : le Centre, rien avant (la racine)")
        let ent = PlanCentre.cadreEntete(m.grille)
        clic(CGPoint(x: ent.maxX - EnteteCentre.pilule(EnteteCentre.titreModifier) - 8 - EnteteCentre.piluleDictees - 8 - EnteteCentre.piluleOutils / 2, y: ent.midY), 0.9)
        verifier(m.courante == .outils && m.pileRetour.vues == [.centre], "vrai clic sur « Outils › » : les Outils, le Centre retenu (\(m.pileRetour.vues.map(\.rawValue)))")
        ouvrirLeDetail("Centre › Outils › Groq")
        verifier(m.pileRetour.vues == [.centre, .outils] && m.pileRetour.dernier?.epingle == true, "la pile : Centre puis Outils (épinglé)")
        pause(0.5)
        // la forme du bandeau avec sa pilule : posée, dans la zone de dessin, « ‹ Outils » entier
        if let lc = m.contenus[.groq] {
            let z = m.grille.zoneAnnonce(.groq)
            verifier(z.width + 0.5 >= lc && lc >= ContenuAnnonce.largeurRetour("Outils") + 26 + 24, "le détail épouse « ‹ Outils », le symbole et le texte (\(Int(lc)) pt pour \(Int(z.width)) pt de zone)")
        }
        clic(pointRetourDetail(), 0.9)
        verifier(m.courante == .outils && m.bandeau == nil && m.epingle && m.pileRetour.vues == [.centre],
                 "vrai clic sur « ‹ Outils » du détail : la page Outils, toujours épinglée (\(m.courante))")

        // --- deux doigts vers la droite sur le détail : les Outils
        ouvrirLeDetail("de nouveau")
        pause(0.4)
        geste(dx: [6, 14, 18, 20], dy: [0, -1, 1, 0], en: pointRetourDetail().applying(.init(translationX: 120, y: 0)))
        pause(0.6)
        verifier(m.courante == .outils && m.bandeau == nil, "vrai geste deux doigts vers la droite sur le détail : les Outils (\(m.courante))")
        // sur les Outils : vers la gauche, rien ; vers la droite, le Centre (là où mène « ‹ Centre »)
        let milieu = CGPoint(x: 0, y: g.hauteur + 150)
        geste(dx: [-8, -16, -20, -20], dy: [0, 0, 0, 0], en: milieu); pause(0.6)
        verifier(m.courante == .outils, "deux doigts vers la gauche : rien (\(m.courante))")
        geste(dx: [8, 16, 20, 20], dy: [0, 1, 0, -1], en: milieu); pause(0.7)
        verifier(m.courante == .centre && m.pileRetour.estVide, "deux doigts vers la droite sur les Outils : le Centre, comme « ‹ Centre » (\(m.courante))")
        geste(dx: [8, 16, 20, 20], dy: [0, 0, 0, 0], en: milieu); pause(0.6)
        verifier(m.courante == .centre && m.fenetreOuverte, "sur le Centre sans activité (la racine) : rien, l'îlot reste ouvert (\(m.courante))")
        // un vrai défilement vertical un peu de travers change toujours de carte, une seule, sans revenir en arrière
        geste(dx: [2, 4, 5], dy: [-6, -12, -14], en: milieu); pause(0.7)
        verifier(m.courante == .outils, "défilement vertical un peu de travers : la carte suivante, pas un retour (\(m.courante))")

        // --- une carte d'outil : « ‹ Outils » et le geste mènent au même endroit
        clic(PlanCentre.centreRond(m, .pressePapiers), 0.8)
        verifier(m.courante == .outilPressePapiers, "vrai clic sur Presse-papiers : sa carte (\(m.courante))")
        geste(dx: [8, 16, 20], dy: [0, 0, 0], en: milieu); pause(0.7)
        verifier(m.courante == .outils, "deux doigts vers la droite : les Outils (\(m.courante))")

        // --- les Dictées : la liste défile toujours, le geste horizontal revient au Centre
        let sourceAvant = m.dictees.source
        defer { m.dictees.source = sourceAvant }
        m.dictees.source = { HistoriqueStore(enMemoire: IlotEssai.dicteesFactices(courtes: false, maintenant: c.maintenant())) }
        m.allerA(.centre); pause(0.4); m.allerA(.dictees); pause(0.9)
        let liste = PlanDictees.cadreListe(m.grille)
        let surListe = CGPoint(x: liste.midX, y: liste.midY)
        if m.dictees.defile {
            let avant = m.dictees.decalage
            geste(dx: [0, 1, 0, 0], dy: [-10, -20, -20, -20], en: surListe); pause(0.4)
            verifier(m.courante == .dictees && m.dictees.decalage != avant, "vrai défilement vertical sur la liste des Dictées : elle défile (\(Int(avant)) → \(Int(m.dictees.decalage)) pt), la carte reste")
        } else {
            verifier(false, "la liste des Dictées de l'essai devrait dépasser sa place")
        }
        geste(dx: [8, 16, 20, 20], dy: [0, 0, 0, 0], en: surListe); pause(0.7)
        verifier(m.courante == .centre, "deux doigts vers la droite sur la liste des Dictées : le Centre (\(m.courante))")

        // --- les rappels : « ‹ » d'où l'on vient
        m.allerA(.accueil); pause(0.6)
        m.surAction(.rappelFormulaire); pause(0.9)
        verifier(m.courante == .rappelListe && m.nomRetour == "Accueil", "« Dire un rappel » depuis l'accueil : la liste, « ‹ \(m.nomRetour ?? "?") »")
        clic(PlanRappels.pointRetour(m.grille, titre: m.nomRetour ?? "Accueil"), 0.8)
        verifier(m.courante == .accueil, "vrai clic sur « ‹ Accueil » : l'accueil (\(m.courante))")

        // --- jamais bloqué : un détail sous un pointeur IMMOBILE se referme seul (puis revient aux Outils, épinglés)
        m.allerA(.centre); pause(0.4); m.allerA(.outils); pause(0.8)
        ouvrirLeDetail("pointeur immobile")
        c.panneau.simulerPointeur(forme: true)   // posé sur le détail, sans un mouvement de plus
        let t0 = Date()
        attendre(5 + FermetureBandeau.calme + 1.5) { m.bandeau != nil }
        let duree = Date().timeIntervalSince(t0)
        verifier(m.bandeau == nil && duree < IlotControleur.dureeBandeauGroq + 1 + 1.0,
                 "pointeur posé sur le détail sans bouger : il part seul après \(String(format: "%.1f", duree)) s (avant : il restait tant que le pointeur était là)")
        pause(0.5)
        verifier(m.courante == .outils && m.epingle, "… et l'îlot revient aux Outils, épinglés comme avant (\(m.courante))")

        // --- sous un pointeur qui BOUGE, il reste (on le lit), puis part quelques secondes après le dernier mouvement
        ouvrirLeDetail("pointeur qui bouge")
        let z = m.grille.zoneAnnonce(.groq)
        let t1 = Date()
        var k = 0
        while Date().timeIntervalSince(t1) < 7 { c.panneau.envoyerMouvement(en: CGPoint(x: z.midX + CGFloat(k % 2) * 6, y: z.midY)); k += 1; pause(0.4) }
        verifier(m.courante == .groq && m.bandeau != nil, "la souris bouge sur le détail depuis 7 s : il reste (\(m.courante))")
        let t2 = Date()
        attendre(FermetureBandeau.calme + 2) { m.bandeau != nil }
        let apres = Date().timeIntervalSince(t2)
        verifier(m.bandeau == nil && apres <= FermetureBandeau.calme + 1.6, "la souris s'arrête : parti \(String(format: "%.1f", apres)) s plus tard (≤ \(Int(FermetureBandeau.calme)) s + un réveil)")
        pause(0.5)
        verifier(m.courante == .outils, "… retour aux Outils (\(m.courante))")

        // --- l'îlot se range : la pile est vidée
        c.panneau.simulerPointeur(forme: false)
        m.fermer(); pause(0.6)
        verifier(m.pileRetour.estVide && !m.fenetreOuverte, "l'îlot rangé : la pile de retour est vide")
    }
}
