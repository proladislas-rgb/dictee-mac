import AppKit
import DicteeCore

extension IlotEssai {
    /// Le Centre (maquette design/maquettes/ilot-centre.html), de bout en bout, dans la fenêtre invisible de l'essai : de VRAIS clics et de
    /// VRAIS défilements (CGEvent → NSEvent) remis à la fenêtre, jamais au système. Le micro est factice, Téléchargements surveille un
    /// dossier temporaire, Claude Code est branché sur un settings.json temporaire, les réglages restent en mémoire (jamais les vrais),
    /// aucune app n'est activée, aucune autorisation n'est demandée.
    @MainActor
    static func centre(_ c: IlotControleur, dossier: URL, verifier: (Bool, String) -> Void, attendre: (Double, () -> Bool) -> Void) {
        let m = c.moteur, g = m.geometrie
        let hc = Double(m.demiCamera), barre = Double(g.hauteur)
        func pause(_ s: Double) { attendre(s) { true } }
        func clic(_ p: CGPoint, _ apres: Double = 0.5) {
            c.panneau.envoyerSouris(.leftMouseDown, en: p); pause(0.06); c.panneau.envoyerSouris(.leftMouseUp, en: p); pause(apres)
        }
        /// Un geste de deux doigts : début, quelques mouvements, fin (de vrais événements de défilement).
        func geste(_ pas: [Int32], en p: CGPoint) {
            for (i, d) in pas.enumerated() { c.panneau.envoyerDefilement(dy: d, en: p, phase: i == 0 ? 1 : 2); pause(0.016) }
            c.panneau.envoyerDefilement(dy: 0, en: p, phase: 4); pause(0.02)
        }
        func rond(_ e: ElementCentre) -> CGPoint { PlanCentre.centreRond(m, e) }

        print("Le Centre")
        // les réglages, en mémoire
        var memoire = (bulle: false, utilise: false, telechargements: false, micro: nil as String?, micros: 0, claude: 0, etagere: 0)
        c.reglagesCentre = ReglagesCentre(
            telechargements: { memoire.telechargements }, reglerTelechargements: { memoire.telechargements = $0 },
            microChoisi: { memoire.micro }, choisirMicro: { memoire.micro = $0 },
            bulleVue: { memoire.bulle }, marquerBulleVue: { memoire.bulle = true },
            centreUtilise: { memoire.utilise }, marquerCentreUtilise: { memoire.utilise = true },
            allumerMicro: { memoire.micros += 1 }, allumerClaude: { memoire.claude += 1 }, allumerEtagere: { memoire.etagere += 1 })
        let racine = dossier.appendingPathComponent("centre", isDirectory: true)
        let inst = InstallationClaude(reglages: racine.appendingPathComponent("point-claude/settings.json"), dossierVerbe: racine.appendingPathComponent("Dictee", isDirectory: true))
        c.installationClaude = inst
        c.claudeSource.dossier = inst.etats
        var ramenes: [String?] = []
        c.ramenerSession = { ramenes.append($0?.app) }
        let faux = (c.micro as? MicroFactice) ?? MicroFactice()
        if !(c.micro is MicroFactice) { c.micro = faux }
        m.aideCentre = !memoire.utilise

        // --- la bulle « Nouveau : survole l'îlot » (premier lancement), sous la lecture repliée
        c.lecture.modele.morceau = MorceauEnCours(titre: "Je détestais la mode des iPods", app: "essai.lecture", joue: true, duree: 774, position: 202)
        c.lecture.surIlot(true); m.fermer(); pause(1.0)
        verifier(m.courante == .lectureCompact && !m.bulleNouveau, "avant : la lecture repliée, pas de bulle")
        m.montrerBulle(duree: 30); pause(0.9)
        verifier(m.bulleNouveau && m.visible(ExtraIlot.bulle) && abs(m.trace.hauteur - (barre + GeoIlot.profondeurBulle)) < 0.5 && m.courante == .lectureCompact,
                 "bulle « Nouveau » : l'îlot replié descend de 40 pt, la lecture reste dans les ailes")
        verifier(m.trace.bande <= hc + GeoIlot.aileMax + 0.01 && Double(m.trace.corps) * 2 >= Double(BulleNouveau.largeur) + 2 * GeoIlot.marge - 0.5,
                 "bulle : rien de plus de 66 pt dans la barre, le corps épouse le texte (\(Int(BulleNouveau.largeur)) pt)")
        attendre(1.2) { m.boucleActive }
        verifier(!m.boucleActive, "bulle posée : aucune boucle d'animation (bouge encore : \(m.ceQuiBouge))")
        c.panneau.simulerPointeur(forme: true); pause(0.9)
        verifier(!m.bulleNouveau && memoire.bulle && m.courante == .lectureEtendu, "survol : la lecture se déplie, la bulle a servi (retenu : elle ne reviendra plus)")
        c.panneau.simulerPointeur(forme: false); pause(0.5); attendre(1.5) { m.boucleActive }
        verifier(m.courante == .lectureCompact && abs(m.trace.hauteur - barre) < 0.5, "refermé : plus de bulle sous l'îlot (\(Int(m.trace.hauteur)) pt)")
        m.montrerBulle(duree: 0.4); pause(1.3)
        verifier(!m.bulleNouveau && abs(m.trace.hauteur - barre) < 0.5, "jamais survolée : la bulle part d'elle-même (un seul réveil)")

        // --- la lecture dépliée : le bouton « Centre », l'aide, les points de page
        c.panneau.simulerPointeur(forme: true); pause(1.0)
        verifier(m.courante == .lectureEtendu && m.visible(ExtraIlot.pied) && m.visible(ExtraIlot.points) && m.aideCentre,
                 "lecture dépliée : « Centre » en bas, « Fais défiler ou clique ici », trois points à droite")
        verifier(abs(m.geo[2].x - (barre + GeoIlot.profondeur(.lectureEtendu))) < 0.5 && Double(m.geo[2].x) + 30 <= Double(IlotMoteur.hauteurMax),
                 "lecture dépliée avec son pied : \(Int(m.geo[2].x)) pt, dans la zone de dessin")
        if let f = c.panneau.cadre { verifier(Double(f.height) >= m.trace.hauteur, "la fenêtre couvre la lecture et son pied") }
        // un vrai défilement de deux doigts : UNE carte, même si le geste continue ; l'inertie qui suit ne compte pas
        let milieu = CGPoint(x: 0, y: g.hauteur + 100)
        geste([-4, -6, -8, -20, -30], en: milieu); pause(0.6)
        verifier(m.courante == .centre, "vrai défilement (deux doigts vers le haut) : le Centre, une seule carte (\(m.courante))")
        verifier(memoire.utilise && !m.aideCentre, "l'aide « Fais défiler ou clique ici » a servi : retenu, elle ne revient plus")
        for (i, d) in [Int32(-30), -25, -10].enumerated() { c.panneau.envoyerDefilement(dy: d, en: milieu, phase: 0, inertie: i == 0 ? 1 : (i == 2 ? 3 : 2)); pause(0.02) }
        pause(0.4)
        verifier(m.courante == .centre, "l'inertie qui suit le geste : ignorée, toujours le Centre")
        geste([-6, -12], en: milieu); pause(0.6)
        verifier(m.courante == .outils, "un autre geste : les Outils, la 2e page du Centre (\(m.courante))")
        geste([-6, -12], en: milieu); pause(0.6)
        verifier(m.courante == .accueil, "encore un : l'accueil (rendez-vous, rappel, dernière dictée)")
        geste([-20, -20], en: milieu); pause(0.4)
        verifier(m.courante == .accueil, "au bout de la pile : on ne boucle pas")
        geste([5, 12], en: milieu); pause(0.6)
        verifier(m.courante == .outils, "geste vers le bas : les Outils")
        geste([5, 12], en: milieu); pause(0.6)
        verifier(m.courante == .centre, "encore un : retour au Centre")
        c.panneau.envoyerDefilement(dy: 3, en: milieu, phase: 0, trackpad: false); pause(0.05)
        c.panneau.envoyerDefilement(dy: 3, en: milieu, phase: 0, trackpad: false); pause(0.6)
        verifier(m.courante == .lectureEtendu, "molette, deux crans rapprochés : une seule carte (la lecture) (\(m.courante))")
        geste([-3, -40], en: CGPoint(x: 0, y: 10)); pause(0.6)
        verifier(m.courante == .centre, "défilement sur le haut de l'îlot (dans la barre) : marche aussi")
        // les points de page : un vrai clic sur le 1er (la lecture), puis sur le 2e (le Centre)
        attendre(1.0) { m.boucleActive }
        let n = m.cartes.count
        var p = PointsCartes.centre(0, sur: n, corps: CGFloat(m.trace.corps), hauteur: CGFloat(m.geo[2].x), barre: g.hauteur)
        clic(p, 0.8)
        verifier(m.courante == .lectureEtendu, "vrai clic sur le 1er point : la lecture (\(m.courante))")
        p = PointsCartes.centre(1, sur: n, corps: CGFloat(m.trace.corps), hauteur: CGFloat(m.geo[2].x), barre: g.hauteur)
        clic(p, 0.8)
        verifier(m.courante == .centre, "vrai clic sur le 2e point : le Centre (\(m.courante))")
        // « ‹ Vidéo » en haut à gauche, puis le bouton « Centre » de la lecture
        let ent = PlanCentre.cadreEntete(m.grille)
        clic(CGPoint(x: ent.minX + 30, y: ent.midY), 0.8)
        verifier(m.courante == .lectureEtendu, "vrai clic sur « ‹ Vidéo » : la lecture (\(m.courante))")
        clic(PiedCarte.pointBouton(m.grille), 0.9)
        verifier(m.courante == .centre, "vrai clic sur « Centre » : le Centre (\(m.courante))")
        verifier(m.trace.bande <= hc + GeoIlot.aileMax + 0.01 && Double(m.geo[2].x) + 30 <= Double(IlotMoteur.hauteurMax),
                 "Centre : \(Int(m.trace.bande - hc)) pt de chaque côté de la caméra dans la barre (≤ 66), \(Int(m.geo[2].x)) pt de haut (zone de dessin : \(Int(IlotMoteur.hauteurMax)))")
        attendre(1.2) { m.boucleActive }
        verifier(!m.boucleActive, "Centre posé : aucune boucle d'animation (bouge encore : \(m.ceQuiBouge))")
        if let f = c.panneau.cadre { verifier(Double(f.height) >= m.trace.hauteur && Double(f.width) >= 2 * m.trace.corps, "la fenêtre couvre le Centre (\(Int(f.width)) × \(Int(f.height)))") }
        // les noms sous les ronds, mesurés : sur une ligne, sans toucher le voisin (3 ou 4 colonnes)
        for nb in [3, 4] {
            let col = PlanCentre.cadreRonds(m).width / CGFloat(nb)
            let l = MesureIlot.texte("Téléchargements", PlanCentre.policeNom, .semibold, interlettre: PlanCentre.interlettreNom)
            verifier(l <= col - 8, "« Téléchargements » (\(Int(l)) pt) tient sur une ligne dans sa colonne (\(Int(col)) pt, \(nb) boutons)")
        }

        // --- plusieurs actions d'affilée : le micro, le minuteur, Téléchargements, Claude ; l'îlot reste ouvert
        c.activerLeMicro(false); pause(0.2)
        clic(rond(.micro), 0.5)
        verifier(faux.actif && faux.coupe && m.microCoupe && memoire.micros == 1, "vrai clic sur Micro (réglage éteint) : le réglage s'allume, le micro est coupé")
        verifier(m.courante == .centre && m.epingle, "après ce clic : « Reste ouvert », toujours le Centre")
        c.panneau.simulerPointeur(forme: false); pause(0.7)
        verifier(m.courante == .centre, "la souris s'en va : le Centre reste ouvert (épinglé)")
        let cm = PlanCentre.cadreCase(m, .minuteur)
        let yCaps = cm.minY + 11 + 17 + 8 + 14
        clic(CGPoint(x: cm.minX + 14 + 22, y: yCaps), 0.5)
        verifier(abs((c.minuteur?.restant(a: c.maintenant()) ?? 0) - 300) < 2 && m.courante == .centre && m.bandeau == nil,
                 "vrai clic sur « 5 » : minuteur de 5 min, sans bandeau, le Centre reste ouvert")
        clic(CGPoint(x: cm.minX + 14 + 14, y: yCaps), 0.4)
        verifier(c.minuteur?.enPause == true && m.courante == .centre, "vrai clic sur pause : en pause")
        clic(CGPoint(x: cm.minX + 14 + 28 + 8 + 14, y: yCaps), 0.5)
        verifier(c.minuteur == nil && m.courante == .centre, "vrai clic sur arrêt : plus de minuteur, le Centre reste ouvert")
        clic(rond(.telechargements), 0.5)
        verifier(memoire.telechargements && m.telechargementsActifs && c.telechargementsSource.actif && m.courante == .centre,
                 "vrai clic sur Téléchargements : allumé (dossier temporaire surveillé, aucune demande d'accès), toujours ouvert")
        clic(rond(.telechargements), 0.5)
        verifier(!memoire.telechargements && !m.telechargementsActifs && !c.telechargementsSource.actif, "second clic : éteint")
        verifier(!inst.estBranche && !m.claudeBranche, "Claude Code pas encore branché : « Brancher »")
        clic(rond(.claude), 0.5)
        verifier(inst.estBranche && m.claudeBranche && c.claudeSource.actif && m.courante == .centre && ramenes.isEmpty,
                 "vrai clic sur « Brancher » : crochets écrits (settings.json temporaire), « Prêt », le Centre reste ouvert")
        clic(rond(.claude), 0.5)
        verifier(ramenes.isEmpty && m.courante == .claudeCarte && m.epingle, "« Prêt » : la carte « Claude Code » (aucune session : elle le dit) ; rien n'est activé (\(m.courante))")
        m.fermer(); pause(0.6)
        try? inst.debrancher(); c.activerClaude(false); m.claudeBranche = false
        // la Dictée : seulement avec un micro Bluetooth
        c.lireMicros = { [PeripheriqueEntree(uid: "essai-airpods", nom: "AirPods Pro", transport: .bluetooth)] }
        m.allerA(.centre); pause(0.9)
        verifier(m.courante == .centre && m.rondsCentre == [.micro, .dictee, .telechargements, .claude], "AirPods là : le bouton Dictée paraît (4 boutons)")
        clic(rond(.dictee), 0.5)
        verifier(memoire.micro == "essai-airpods" && m.choixMicro?.airpods == true && m.courante == .centre, "vrai clic sur Dictée : la dictée écoutera les AirPods")
        clic(rond(.dictee), 0.5)
        verifier(memoire.micro == nil && m.choixMicro?.airpods == false, "second clic : le micro du Mac (réglage Automatique)")
        c.lireMicros = { [] }; c.relireChoixMicro(); m.donneesChangees(); pause(0.5)
        verifier(m.rondsCentre.count == 3, "AirPods partis : trois boutons")

        // --- un fichier glissé sur le Centre ouvert : la case Étagère s'éclaire, la forme ne bouge pas, le Centre reste ouvert
        let rayon = dossier.appendingPathComponent("Centre-étagère", isDirectory: true)
        try? FileManager.default.createDirectory(at: rayon, withIntermediateDirectories: true)
        let devis = rayon.appendingPathComponent("Devis-cuisine.pdf"); try? Data("essai".utf8).write(to: devis)
        c.activerEtagere(true); pause(0.3)
        let avantDepot = c.etagere.elements.count
        let hAvant = m.geo[2].x
        let ce = PlanCentre.cadreCase(m, .etagere)
        let pd = CGPoint(x: ce.midX, y: ce.midY)
        verifier(c.panneau.glisserSurLIlot(pd) && m.depot && m.depotSurvole && m.courante == .centre, "fichier glissé sur la case Étagère : accepté, la case s'éclaire (« Lâche ici »), toujours le Centre")
        pause(0.4)
        verifier(abs(m.geo[2].x - hAvant) < 0.5, "la forme ne bouge pas (pas de « Déposez ici » par-dessus)")
        verifier(c.panneau.deposer([devis]), "lâché : accepté")
        pause(1.4)
        verifier(c.etagere.elements.count == avantDepot + 1 && c.etagere.elements.last?.nom == "Devis-cuisine.pdf" && !m.depot && m.courante == .centre && m.epingle,
                 "le fichier est sur l'étagère ; le Centre reste ouvert, épinglé")
        c.panneau.finDuGlisser()

        // --- un clic sur l'îlot dans la barre (pas dans le vide du Centre, qui ne compte pas) le range ; replié, le micro coupé dit « Coupé »
        attendre(1.0) { m.boucleActive }
        clic(CGPoint(x: 0, y: g.hauteur / 2), 0.9)
        verifier(m.courante == .microCompact && m.pastille == .lecture, "vrai clic sur l'îlot dans la barre : il se range ; micro coupé : « Coupé » dans les ailes, la vidéo en bulle (\(m.courante))")
        if let f = c.panneau.cadre {
            verifier(Double(f.width) <= 2 * (hc + GeoIlot.aileMax) + 4.5 + Double(m.largeurPastilleOuverte(.lecture)) + 20 && Double(f.height) <= barre + 6.5,
                     "replié : la fenêtre reprend la taille des ailes et de la bulle (\(Int(f.width)) × \(Int(f.height)))")
        }
        // survol du micro coupé : la vidéo en bulle se déplie, le Centre est la carte suivante ; on rouvre le micro depuis le Centre
        c.panneau.simulerPointeur(forme: true); pause(0.9)
        verifier(m.courante == .lectureEtendu, "survol du micro coupé : la vidéo se déplie (\(m.courante))")
        geste([-8, -10], en: milieu); pause(0.6)
        clic(rond(.micro), 0.5)
        verifier(!faux.coupe && !m.microCoupe && m.courante == .centre && m.bandeau == nil, "vrai clic sur Micro : rouvert, sans bandeau, le Centre reste ouvert")
        c.panneau.simulerPointeur(forme: false); m.fermer(); pause(0.9)
        verifier(m.courante == .lectureCompact, "refermé : la lecture")
        // l'îlot replié ne défile pas
        geste([-10, -20], en: CGPoint(x: 0, y: g.hauteur / 2)); pause(0.4)
        verifier(m.courante == .lectureCompact, "îlot replié : un défilement ne l'ouvre pas")

        // --- « Réduire les animations » : tout se pose tout de suite
        m.reduire = true
        c.panneau.simulerPointeur(forme: true); pause(0.5)
        m.allerA(.centre)
        verifier(m.courante == .centre && m.geo.allSatisfy(\.fini), "Réduire les animations : le Centre est posé d'un coup, sans ressort")
        m.reduire = false
        c.panneau.simulerPointeur(forme: false); m.fermer(); pause(0.9)
        c.activerLeMicro(false); c.activerEtagere(false)
        c.lecture.modele.morceau = nil; c.lecture.surIlot(false); pause(0.6)
    }
}
