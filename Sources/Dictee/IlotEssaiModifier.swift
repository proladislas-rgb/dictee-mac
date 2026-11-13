import AppKit
import DicteeCore

extension IlotEssai {
    /// « Modifier » le Centre (maquette ilot-centre.html, étape 9), les autorisations au premier clic, et le raccourci du micro retiré, dans
    /// la fenêtre invisible de l'essai : de VRAIS clics et de VRAIS glissers (événements souris remis à la fenêtre, jamais au système).
    /// Les réglages restent en mémoire, Téléchargements surveille des dossiers temporaires (un dossier fermé, 000, joue le refus de macOS :
    /// la vraie demande n'est jamais posée), Claude Code est branché sur un settings.json temporaire, aucune app n'est ouverte, aucun lien
    /// n'est suivi (capturés).
    @MainActor
    static func modifierCentre(_ c: IlotControleur, dossier: URL, verifier: (Bool, String) -> Void, attendre: (Double, () -> Bool) -> Void) {
        let m = c.moteur
        func pause(_ s: Double) { attendre(s) { true } }
        func clic(_ p: CGPoint, _ apres: Double = 0.5) {
            c.panneau.envoyerSouris(.leftMouseDown, en: p); pause(0.06); c.panneau.envoyerSouris(.leftMouseUp, en: p); pause(apres)
        }
        /// Un vrai glisser : appui, déplacements par petits pas, relâchement.
        func glisser(de a: CGPoint, a b: CGPoint, pas: Int = 12) {
            c.panneau.envoyerSouris(.leftMouseDown, en: a); pause(0.08)
            for i in 1...pas {
                let t = CGFloat(i) / CGFloat(pas)
                c.panneau.envoyerSouris(.leftMouseDragged, en: CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)); pause(0.03)
            }
            pause(0.1)
            c.panneau.envoyerSouris(.leftMouseUp, en: b); pause(0.5)
        }
        func entete() -> CGRect { PlanCentre.cadreEntete(m.grille) }
        /// La pilule de droite de l'en-tête (« Modifier » ou « OK »).
        func pilule(_ titre: String) -> CGPoint { let e = entete(); return CGPoint(x: e.maxX - EnteteCentre.pilule(titre) / 2, y: e.midY) }
        /// Le « – » d'un rond (20 pt, 5 pt hors du coin du rond de 52 pt).
        func moins(_ e: ElementCentre) -> CGPoint { let p = PlanCentre.centreRond(m, e); return CGPoint(x: p.x - 26 + 5, y: p.y - 26 + 5) }
        /// Une pastille « + Rappel » de la ligne « Ajouter : » (nil : pas montrée).
        func pastille(_ e: ElementCentre) -> CGPoint? {
            let (tous, debut, n) = EnteteCentre.ajouts(m, largeur: entete().width)
            let montres = Array(tous.dropFirst(debut).prefix(n))
            guard let i = montres.firstIndex(of: e) else { return nil }
            var x = entete().minX + MesureIlot.texte(EnteteCentre.libelleAjouter, 12, .medium) + 6 + (debut > 0 ? EnteteCentre.retour + 6 : 0)
            for f in montres.prefix(i) { x += EnteteCentre.pastille(f) + 6 }
            return CGPoint(x: x + EnteteCentre.pastille(e) / 2, y: entete().midY)
        }
        /// « +2 › » au bout des pastilles (nil : tout tient).
        func suiteAjouts() -> CGPoint? {
            let (tous, debut, n) = EnteteCentre.ajouts(m, largeur: entete().width)
            let reste = tous.count - debut - n
            guard reste > 0 else { return nil }
            var x = entete().minX + MesureIlot.texte(EnteteCentre.libelleAjouter, 12, .medium) + 6 + (debut > 0 ? EnteteCentre.retour + 6 : 0)
            for f in tous.dropFirst(debut).prefix(n) { x += EnteteCentre.pastille(f) + 6 }
            return CGPoint(x: x + EnteteCentre.marque(reste) / 2, y: entete().midY)
        }
        /// La pastille de `e`, en tournant les pages de « Ajouter : » à vrais clics (« ‹ » revient au début, « +N › » avance) : la ligne
        /// en propose plus qu'elle n'en montre depuis la Concentration.
        func pastilleVisible(_ e: ElementCentre) -> CGPoint? {
            if pastille(e) == nil, EnteteCentre.ajouts(m, largeur: entete().width).debut > 0 {
                clic(CGPoint(x: entete().minX + MesureIlot.texte(EnteteCentre.libelleAjouter, 12, .medium) + 6 + EnteteCentre.retour / 2, y: entete().midY), 0.4)
            }
            for _ in 0..<3 where pastille(e) == nil { if let p = suiteAjouts() { clic(p, 0.4) } }
            return pastille(e)
        }
        func ouvrirLeCentre() {
            c.panneau.simulerPointeur(forme: true); pause(0.6)
            m.allerA(.centre); pause(0.9)
        }

        print("Le Centre : « Modifier », autorisations, plus de raccourci")
        // les réglages, en mémoire (le reste de ReglagesCentre est déjà en mémoire depuis l'essai du Centre)
        var rangee: [String]? = nil
        var enregistrements = 0
        c.reglagesCentre.disposition = { rangee }
        c.reglagesCentre.enregistrerDisposition = { rangee = $0; enregistrements += 1 }
        var ouverts: [URL] = []
        c.ouvrir = { ouverts.append($0) }
        var notes = 0
        c.surNoter = { _ in notes += 1 }
        var colles: [String] = []
        c.surColler = { colles.append($0) }
        c.lireDerniereDictee = { nil }
        c.lireMicros = { [] }; c.relireChoixMicro()
        let faux = (c.micro as? MicroFactice) ?? MicroFactice()
        if !(c.micro is MicroFactice) { c.micro = faux }
        c.activerLeMicro(true)
        m.disposition = DispositionCentre(identifiants: rangee)
        verifier(m.disposition.elements == DispositionCentre.parDefaut, "jamais modifié : le Centre par défaut")
        // la suite joue la maquette ilot-centre (étape 9), faite avant la Concentration (12/11) : on part du Centre d'alors
        m.disposition = DispositionCentre(DispositionCentre.parDefaut.filter { $0 != .concentration })

        // --- « Modifier » : vrai clic ; la hauteur ne change pas (les ajouts prennent la ligne de l'en-tête)
        ouvrirLeCentre()
        verifier(m.courante == .centre && m.rondsCentre == [.micro, .telechargements, .calendrier, .claude], "le Centre, sans AirPods : Micro, Téléchargements, Calendrier, Claude Code (\(m.rondsCentre.map(\.rawValue)))")
        attendre(1.0) { m.boucleActive }
        let hAvant = m.geo[2].x
        clic(pilule(EnteteCentre.titreModifier), 0.6)
        verifier(m.editionCentre && m.epingle && m.courante == .centre, "vrai clic sur « Modifier » : les boutons tremblent, le Centre reste ouvert")
        verifier(abs(m.geo[2].x - hAvant) < 0.5, "« Modifier » : la hauteur de l'îlot ne change pas")
        let aj = EnteteCentre.ajouts(m, largeur: entete().width)
        verifier(aj.tous == [.rappel, .derniereDictee, .concentration] && aj.montres >= 2, "« Ajouter : + Rappel + Dernière dictée » (maquette, étape 9 ; sans AirPods, pas le choix du micro), puis Concentration")
        // un clic sur un rond ne fait rien (ni micro coupé, ni îlot refermé)
        let cmd = faux.commandes.count
        clic(PlanCentre.centreRond(m, .micro), 0.4)
        verifier(faux.commandes.count == cmd && !m.microCoupe && m.editionCentre && m.courante == .centre, "« Modifier » : un clic sur le rond Micro ne fait rien, l'îlot reste ouvert")
        // la molette ne change pas de carte pendant qu'on range
        let milieu = CGPoint(x: 0, y: m.grille.barre + 100)
        c.panneau.envoyerDefilement(dy: -30, en: milieu, phase: 1); pause(0.02); c.panneau.envoyerDefilement(dy: 0, en: milieu, phase: 4); pause(0.5)
        verifier(m.courante == .centre && m.editionCentre, "« Modifier » : un défilement ne change pas de carte")

        // --- « – » retire, « + » ajoute (à la fin des ronds : l'ordre d'ajout)
        clic(moins(.telechargements), 0.6)
        verifier(m.rondsCentre == [.micro, .calendrier, .claude] && m.editionCentre && rangee == nil, "vrai clic sur le « – » de Téléchargements : retiré (rien d'enregistré avant « OK »)")
        if let p = pastille(.rappel) { clic(p, 0.6) } else { verifier(false, "pastille « + Rappel » introuvable") }
        verifier(m.rondsCentre == [.micro, .calendrier, .claude, .rappel], "vrai clic sur « + Rappel » : il arrive au bout de la rangée (\(m.rondsCentre.map(\.rawValue)))")
        verifier(EnteteCentre.ajouts(m, largeur: entete().width).tous == [.telechargements, .derniereDictee, .concentration], "Téléchargements, retiré, est proposé à son tour")
        // le « – » de la bande « Noter la réunion » : 50 pt de moins
        attendre(1.0) { m.boucleActive }
        let hAvecBande = m.geo[2].x
        let bd = PlanCentre.cadreBande(m)
        clic(CGPoint(x: bd.minX + 4, y: bd.minY + 4), 0.9)
        attendre(1.2) { m.boucleActive }
        verifier(!m.disposition.bande && abs(m.geo[2].x - (hAvecBande - 50)) < 0.5 && m.editionCentre, "vrai clic sur le « – » de la réunion : la bande part, l'îlot raccourcit de 50 pt")
        let hSansBande = m.geo[2].x
        // « Téléchargements », « Dernière dictée », « Réunion » ne tiennent pas tous : « +1 › » montre la suite
        if pastille(.reunion) == nil, let p = suiteAjouts() {
            clic(p, 0.5)
            verifier(pastille(.reunion) != nil && m.debutAjouts > 0, "vrai clic sur « +1 › » : la pastille suivante, « Réunion »")
        }
        if let p = pastille(.reunion) { clic(p, 0.9) } else { verifier(false, "pastille « + Réunion » introuvable") }
        attendre(1.2) { m.boucleActive }
        verifier(m.disposition.bande && abs(m.geo[2].x - (hSansBande + 50)) < 0.5 && Double(m.geo[2].x) + 30 <= Double(IlotMoteur.hauteurMax),
                 "vrai clic sur « + Réunion » : la bande « Noter la réunion » revient en bas, l'îlot grandit de 50 pt (\(Int(m.geo[2].x)) pt, zone de dessin \(Int(IlotMoteur.hauteurMax)))")
        if let f = c.panneau.cadre { verifier(Double(f.height) >= m.trace.hauteur, "la fenêtre couvre le Centre et sa bande (\(Int(f.height)) pt)") }
        verifier(m.trace.bande <= Double(m.demiCamera) + GeoIlot.aileMax + 0.01, "avec la bande : rien de plus de 66 pt dans la barre")

        // --- ranger en glissant : un vrai glisser de Rappel tout à gauche, puis du Minuteur sur la droite
        glisser(de: PlanCentre.centreRond(m, .rappel), a: CGPoint(x: PlanCentre.cadreRonds(m).minX + 20, y: PlanCentre.centreRond(m, .micro).y))
        verifier(m.rondsCentre == [.rappel, .micro, .calendrier, .claude] && m.editionCentre, "vrai glisser de Rappel vers la gauche : il passe en premier (\(m.rondsCentre.map(\.rawValue)))")
        let cm = PlanCentre.cadreCase(m, .minuteur), ce = PlanCentre.cadreCase(m, .etagere)
        glisser(de: CGPoint(x: cm.midX, y: cm.midY), a: CGPoint(x: ce.midX + 20, y: ce.midY))
        verifier(m.disposition.cases == [.etagere, .minuteur], "vrai glisser du Minuteur sur l'Étagère : elles s'échangent (\(m.disposition.cases.map(\.rawValue)))")
        verifier(c.minuteur == nil, "glisser la case Minuteur ne lance pas de minuteur")

        // --- « OK » enregistre ; relu au lancement suivant, tout revient à l'identique
        clic(pilule(EnteteCentre.titreOK), 0.6)
        let attendu = ["rappel", "micro", "dictee", "calendrier", "claude", "etagere", "minuteur", "reunion"]
        verifier(!m.editionCentre && rangee == attendu && enregistrements == 1 && m.courante == .centre,
                 "vrai clic sur « OK » : enregistré (\(rangee?.joined(separator: ", ") ?? "rien")), le Centre reste ouvert")
        verifier(DispositionCentre(identifiants: rangee) == m.disposition, "relu au lancement suivant : le même Centre")
        attendre(1.2) { m.boucleActive }
        verifier(!m.boucleActive, "« OK » : aucune boucle d'animation (bouge encore : \(m.ceQuiBouge))")

        // --- les nouveaux boutons, de vrais clics : Rappel, la bande « Noter la réunion », Dernière dictée
        clic(PlanCentre.centreRond(m, .rappel), 0.8)
        verifier(m.courante == .rappelListe, "vrai clic sur Rappel : « Dire un rappel » (\(m.courante))")
        m.fermer(); pause(0.6)
        ouvrirLeCentre()
        let b = PlanCentre.cadreBande(m)
        clic(CGPoint(x: b.minX + 80, y: b.midY), 0.8)
        verifier(notes == 1 && m.courante != .centre, "vrai clic sur « Noter la réunion » : la prise de notes est lancée (capturée), l'îlot se range")
        ouvrirLeCentre()
        clic(pilule(EnteteCentre.titreModifier), 0.5)
        if let p = pastilleVisible(.derniereDictee) { clic(p, 0.5) } else { verifier(false, "pastille « + Dernière dictée » introuvable") }
        verifier(m.rondsCentre == [.rappel, .micro, .calendrier, .claude, .derniereDictee], "+ Dernière dictée : cinq ronds")
        // les noms et les états sous les ronds : mesurés, jamais plus larges que leur colonne (5 ronds : « Téléchargements », « Dire un rappel »)
        for nb in [4, 5] {
            let col = PlanCentre.cadreRonds(m).width / CGFloat(nb)
            for (t, poids, il) in [("Téléchargements", NSFont.Weight.semibold, PlanCentre.interlettreNom), ("Dernière dictée", .semibold, PlanCentre.interlettreNom),
                                   ("Dire un rappel", .medium, 0), ("Un instant\u{2026}", .medium, 0)] {
                // le pire voisin : un autre texte aussi long que lui, dans une rangée pleine
                let rang = Array(repeating: t, count: nb)
                let tailles = PlanCentre.tailles(rang, colonne: col, poids: poids, interlettre: il)
                let l = tailles.map { MesureIlot.texte(t, $0.taille, poids, interlettre: il) }
                let ok = (0..<(nb - 1)).allSatisfy { l[$0] / 2 + l[$0 + 1] / 2 + PlanCentre.ecartNoms <= col + 0.01 } && tailles.allSatisfy { $0.taille >= PlanCentre.policeMin }
                verifier(ok, "« \(t) » \(nb) fois côte à côte (colonnes de \(Int(col)) pt) : \(String(format: "%.1f", tailles[0].taille)) pt, \(Int(PlanCentre.ecartNoms)) pt au moins entre voisins")
            }
        }
        // les AirPods arrivent : la rangée est pleine (6), la pastille « Dictée »… il n'y en a pas : la dictée est déjà dans la disposition
        c.lireMicros = { [PeripheriqueEntree(uid: "essai-airpods", nom: "AirPods Pro", transport: .bluetooth)] }; c.relireChoixMicro(); m.donneesChangees(); pause(0.6)
        verifier(m.rondsCentre == [.rappel, .micro, .dictee, .calendrier, .claude, .derniereDictee], "AirPods là : six ronds, la dictée à sa place (\(m.rondsCentre.map(\.rawValue)))")
        clic(moins(.dictee), 0.5)
        verifier(m.rondsCentre.count == 5 && EnteteCentre.ajouts(m, largeur: entete().width).tous.first == .dictee, "« – » sur Dictée : cinq ronds ; « + Dictée » proposé")
        if let p = pastilleVisible(.telechargements) { clic(p, 0.5) } else { verifier(false, "pastille « + Téléchargements » introuvable") }
        verifier(m.rondsCentre.count == 6 && !m.disposition.peutAjouter(.dictee, disponible: m.disponibleDansLeCentre), "six ronds : la rangée est pleine")
        if let p = pastilleVisible(.dictee) { clic(p, 0.5) } else { verifier(false, "pastille « Dictée » (éteinte) introuvable") }
        verifier(m.rondsCentre.count == 6 && !m.disposition.elements.contains(.dictee), "rangée pleine : la pastille « Dictée » est éteinte, un clic n'ajoute rien")
        // fermer pendant « Modifier » (clic sur la forme, hors des boutons) : c'est enregistré
        clic(CGPoint(x: 0, y: entete().midY), 0.9)
        verifier(!m.editionCentre && m.courante != .centre && rangee?.contains("derniere-dictee") == true && rangee?.contains("dictee") == false && enregistrements == 2,
                 "le Centre se range pendant « Modifier » : ce qui a été fait est enregistré")
        c.lireMicros = { [] }; c.relireChoixMicro(); m.donneesChangees(); pause(0.4)
        // Dernière dictée : « Aucune » (rien ne se passe), puis « Coller »
        ouvrirLeCentre()
        clic(PlanCentre.centreRond(m, .derniereDictee), 0.5)
        verifier(colles.isEmpty && m.courante == .centre, "aucune dictée : « Aucune », un clic ne colle rien")
        c.lireDerniereDictee = { [unowned c] in ("Je te rappelle demain pour confirmer.", c.maintenant().addingTimeInterval(-120)) }
        m.fermer(); pause(0.5); ouvrirLeCentre()
        verifier(m.derniereDictee?.texte == "Je te rappelle demain pour confirmer.", "une dictée : le rond dit « Coller »")
        clic(PlanCentre.centreRond(m, .derniereDictee), 0.8)
        verifier(colles == ["Je te rappelle demain pour confirmer."] && m.courante != .centre, "vrai clic sur « Coller » : la dernière dictée, en entier, part dans l'app (capturé) ; l'îlot se range")
        c.lireDerniereDictee = { nil }

        // --- « Réduire les animations » : « Modifier » sans tremblement (rien ne bouge), juste les « – »
        m.reduire = true
        ouvrirLeCentre()
        clic(pilule(EnteteCentre.titreModifier), 0.4)
        verifier(m.editionCentre && m.geo.allSatisfy(\.fini), "Réduire les animations : « Modifier » sans ressort ni tremblement")
        clic(pilule(EnteteCentre.titreOK), 0.4)
        m.reduire = false
        m.fermer(); pause(0.8)

        // --- Téléchargements au premier clic : macOS refuse (un dossier fermé joue la réponse « Refuser ») → « Éteint » et la ligne d'avis
        let ferme = dossier.appendingPathComponent("refus-centre", isDirectory: true)
        try? FileManager.default.createDirectory(at: ferme, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: ferme.path)
        let ouvert = dossier.appendingPathComponent("accord-centre", isDirectory: true)
        try? FileManager.default.createDirectory(at: ouvert, withIntermediateDirectories: true)
        c.telechargementsSource.arreter(); c.telechargementsSource.dossier = ferme
        c.reglerTelechargements(false); pause(0.2)
        ouvrirLeCentre()
        clic(PlanCentre.centreRond(m, .telechargements), 0.8)
        verifier(!m.telechargementsActifs && !m.telechargementsAttente && !c.reglagesCentre.telechargements() && !c.telechargementsSource.actif,
                 "accès refusé : le bouton revient sur « Éteint », le réglage aussi")
        verifier(m.avisCentre == .telechargementsRefuses && m.courante == .centre, "la ligne d'avis « Accès refusé : ouvre Réglages Système » paraît, le Centre reste ouvert")
        let placeAvis = EnteteCentre.placeAvis(largeur: entete().width)
        for a in [AvisCentre.telechargementsRefuses, .claudeImpossible(ecriture: false), .claudeImpossible(ecriture: true)] {
            verifier(a.largeur <= placeAvis, "avis « \(a.texte) » : \(Int(a.largeur)) pt, tient dans l'en-tête (\(Int(placeAvis)) pt)")
        }
        clic(CGPoint(x: entete().minX + 60, y: entete().midY), 0.5)
        verifier(ouverts == [IlotControleur.reglagesFichiers] && m.avisCentre == nil && m.courante == .centre,
                 "vrai clic sur l'avis : Réglages Système › Fichiers et dossiers (lien capturé, rien d'ouvert)")
        // autorisé : « Un instant… » le temps de la réponse, puis « Allumé »
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ferme.path)
        c.telechargementsSource.dossier = ouvert
        let pt = PlanCentre.centreRond(m, .telechargements)
        c.panneau.envoyerSouris(.leftMouseDown, en: pt); pause(0.06); c.panneau.envoyerSouris(.leftMouseUp, en: pt)
        let attenteVue = m.telechargementsAttente
        pause(0.6)
        verifier(attenteVue && !m.telechargementsAttente && m.telechargementsActifs && c.telechargementsSource.actif && c.reglagesCentre.telechargements(),
                 "accès accordé : « Un instant… » le temps de la réponse, puis « Allumé » (dossier temporaire, jamais ~/Downloads)")
        clic(pt, 0.4)
        verifier(!m.telechargementsActifs && !c.telechargementsSource.actif, "second clic : éteint")
        // un refus plus tard, Centre fermé (accès retiré dans Réglages Système) : réglage éteint, pas d'avis qui traîne
        m.fermer(); pause(0.6)
        c.telechargementsSource.dossier = ferme
        try? FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: ferme.path)
        c.reglerTelechargements(true); pause(0.6)
        verifier(!c.reglagesCentre.telechargements() && !m.telechargementsActifs && m.avisCentre == nil, "refus Centre fermé : réglage éteint, aucune ligne d'avis qui attend")
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ferme.path)

        // --- Claude Code : « Brancher » sur un settings.json illisible : rien n'est écrit, la ligne d'avis le dit
        let racine = dossier.appendingPathComponent("claude-abime", isDirectory: true)
        let inst = InstallationClaude(reglages: racine.appendingPathComponent("point-claude/settings.json"), dossierVerbe: racine.appendingPathComponent("Dictee", isDirectory: true))
        try? FileManager.default.createDirectory(at: inst.reglages.deletingLastPathComponent(), withIntermediateDirectories: true)
        let abime = "{ \"hooks\": [ pas du json"
        try? Data(abime.utf8).write(to: inst.reglages)
        c.installationClaude = inst; m.claudeBranche = false
        ouvrirLeCentre()
        clic(PlanCentre.centreRond(m, .claude), 0.6)
        verifier(m.avisCentre == .claudeImpossible(ecriture: false) && !m.claudeBranche && (try? String(contentsOf: inst.reglages, encoding: .utf8)) == abime
                 && !FileManager.default.fileExists(atPath: inst.sauvegarde.path),
                 "« Brancher » sur un settings.json illisible : rien n'est écrit, « Brancher » reste, la ligne le dit")
        // réparé : « Brancher » écrit les crochets, l'ancien fichier gardé à côté (.verbe-sauvegarde), « Prêt »
        try? Data("{}".utf8).write(to: inst.reglages)
        clic(PlanCentre.centreRond(m, .claude), 0.6)
        verifier(inst.estBranche && m.claudeBranche && m.avisCentre == nil && (try? String(contentsOf: inst.sauvegarde, encoding: .utf8)) == "{}",
                 "réparé : crochets écrits, l'ancien settings.json gardé en .verbe-sauvegarde, « Prêt »")
        try? inst.debrancher(); c.activerClaude(false); m.claudeBranche = false
        m.fermer(); pause(0.8)

        // --- plus de raccourci pour le micro : ⌃⌥M (sur la touche « m » de ce clavier) n'est plus avalé, même micro réglé ; fn et ⌥⌘N restent
        let src = CGEventSource(stateID: .privateState)
        func touche(_ code: CGKeyCode, _ f: CGEventFlags, bas: Bool = true) -> CGEvent? { let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: bas); e?.flags = f; return e }
        if let codeM = (0..<128).map({ CGKeyCode($0) }).first(where: { touche($0, []).flatMap { NSEvent(cgEvent: $0)?.charactersIgnoringModifiers } == "m" }),
           let bas = touche(codeM, [.maskControl, .maskAlternate]), let haut = touche(codeM, [.maskControl, .maskAlternate], bas: false) {
            let clavier = KeyMonitor()
            var reunions = 0
            clavier.onReunion = { reunions += 1 }
            let n0 = faux.commandes.count
            verifier(!clavier.recevoir(type: .keyDown, event: bas) && !clavier.recevoir(type: .keyUp, event: haut) && faux.commandes.count == n0,
                     "⌃⌥M : plus avalé (l'app au premier plan le reçoit), le micro ne bouge pas")
            if let n = touche(45, [.maskAlternate, .maskCommand]) { verifier(clavier.recevoir(type: .keyDown, event: n) && reunions == 1, "⌥⌘N (noter la réunion) : toujours là") }
        } else { verifier(false, "touche « m » introuvable sur ce clavier") }

        // remise en état pour la suite
        c.activerLeMicro(false)
        m.disposition = DispositionCentre()
    }
}
