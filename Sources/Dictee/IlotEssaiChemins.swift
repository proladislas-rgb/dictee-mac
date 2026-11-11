import AppKit
import DicteeCore

extension IlotEssai {
    /// La relecture du Centre : le chemin vers lui depuis TOUT déplié (minuteur, Claude, micro coupé + Claude), le menu de Verbe quand il
    /// n'y a pas d'encoche, le Centre épinglé qui le reste (bandeaux en attente, clic dans son vide, carte plus courte sous le pointeur,
    /// question de macOS), le minuteur éteint dans les réglages, un glisser qui repart. De VRAIS clics remis à la fenêtre invisible ; le
    /// micro est factice, Téléchargements surveille des dossiers temporaires, les réglages restent en mémoire.
    @MainActor
    static func cheminsDuCentre(_ c: IlotControleur, dossier: URL, verifier: (Bool, String) -> Void, attendre: (Double, () -> Bool) -> Void) {
        let m = c.moteur, g = m.geometrie
        let hc = Double(m.demiCamera), barre = Double(g.hauteur)
        func pause(_ s: Double) { attendre(s) { true } }
        func clic(_ p: CGPoint, _ apres: Double = 0.5) {
            c.panneau.envoyerSouris(.leftMouseDown, en: p); pause(0.06); c.panneau.envoyerSouris(.leftMouseUp, en: p); pause(apres)
        }
        func refermer() { c.panneau.simulerPointeur(forme: false); m.fermer(); pause(0.8) }

        print("Le Centre : les chemins (relecture)")
        var memoire = (telechargements: false, micros: 0, minuteur: true, minuteurAllume: 0)
        c.reglagesCentre = ReglagesCentre(
            telechargements: { memoire.telechargements }, reglerTelechargements: { memoire.telechargements = $0 },
            microChoisi: { nil }, choisirMicro: { _ in }, bulleVue: { true }, marquerBulleVue: {}, centreUtilise: { true }, marquerCentreUtilise: {},
            allumerMicro: { memoire.micros += 1 }, allumerClaude: {}, allumerEtagere: {},
            disposition: { nil }, enregistrerDisposition: { _ in },
            minuteurActif: { memoire.minuteur }, allumerMinuteur: { memoire.minuteur = true; memoire.minuteurAllume += 1 })
        m.disposition = DispositionCentre()
        let faux = (c.micro as? MicroFactice) ?? MicroFactice()
        if !(c.micro is MicroFactice) { c.micro = faux }
        c.lireMicros = { [] }; c.relireChoixMicro()
        refermer()

        // --- un minuteur tourne : son déplié porte le bouton « Centre » (avant : seul un défilement, invisible, y menait)
        c.lancerLeMinuteur(secondes: 25 * 60, bandeau: false, fermer: true); pause(0.8)
        verifier(m.courante == .minuteurCompact, "un minuteur de 25 min : l'anneau et le temps dans les ailes (\(m.courante))")
        c.panneau.simulerPointeur(forme: true); pause(1.0)
        let hMin = barre + GeoIlot.profondeur(.minuteurEtendu) + GeoIlot.piedLecture
        verifier(m.courante == .minuteurEtendu && m.visible(ExtraIlot.pied) && abs(m.geo[2].x - hMin) < 0.5,
                 "survol du minuteur : son déplié, et dessous le bouton « Centre » (\(Int(m.geo[2].x)) pt de haut, attendu \(Int(hMin)))")
        let zm = m.grille.zone(.minuteurEtendu), pm = PiedCarte.cadre(m.grille, .minuteurEtendu)
        verifier(pm.minY >= zm.maxY + 8 && pm.maxY <= CGFloat(m.geo[2].x) - 10 && m.trace.bande <= hc + GeoIlot.aileMax + 0.01,
                 "le pied se pose sous le contenu du minuteur (\(Int(pm.minY - zm.maxY)) pt d'écart), dans la forme ; ≤ 66 pt dans la barre")
        if let f = c.panneau.cadre { verifier(Double(f.height) >= m.trace.hauteur, "la fenêtre couvre le minuteur et son pied") }
        attendre(1.2) { m.boucleActive }
        verifier(!m.boucleActive, "minuteur déplié, posé : aucune boucle d'animation (bouge encore : \(m.ceQuiBouge))")
        clic(PiedCarte.pointBouton(m.grille, .minuteurEtendu), 0.9)
        verifier(m.courante == .centre && !m.epingle, "vrai clic sur « Centre » sous le minuteur : le Centre (plus haut : pas épinglé, maquette étape 3) (\(m.courante))")
        refermer()

        // --- Claude au travail (et le minuteur en bulle) : le même bouton sous son déplié
        let session = SessionClaude(id: "essai-chemins", dossier: "/Users/essai/dev/dictee-mac", app: "com.apple.Terminal", derniere: c.maintenant())
        m.claude = session; m.donneesChangees(); pause(0.8)
        c.panneau.simulerPointeur(forme: true); pause(1.0)
        let premiere = m.cartes.first
        verifier(premiere.map { m.courante == $0 && CartesIlot.aUnPied($0, pile: m.cartes) } == true && m.visible(ExtraIlot.pied),
                 "Claude et un minuteur : le déplié de la 1re activité (\(m.courante)) porte aussi le bouton « Centre »")
        m.surAction(.minuteurArreter); pause(0.2)
        refermer()
        c.panneau.simulerPointeur(forme: true); pause(1.0)
        // Claude au travail (maquette ilot-claude-plus.html, étape 2) : le survol ouvre le Centre ; sa carte est à un clic (bouton Claude
        // Code), et « ‹ Centre » y ramène
        m.sessionsClaude = [session]; m.claudeAuTravail = 1; m.claudeBranche = true; m.donneesChangees(); pause(0.3)
        verifier(m.courante == .centre && !m.visible(ExtraIlot.pied), "survol de Claude au travail : le Centre directement (\(m.courante))")
        clic(PlanCentre.centreRond(m, .claude), 0.9)
        verifier(m.courante == .claudeCarte && m.epingle && m.sessionsClaude.count == 1, "vrai clic sur le bouton Claude Code : la carte « Claude Code » (\(m.courante))")
        verifier(m.trace.bande <= hc + GeoIlot.aileMax + 0.01, "la carte : \(String(format: "%.1f", m.trace.bande - hc)) pt dans la barre de chaque côté (≤ 66)")
        clic(PlanCarteClaude.pointCentre(m), 0.9)
        verifier(m.courante == .centre, "vrai clic sur « ‹ Centre » : le Centre (\(m.courante))")
        refermer()

        // --- micro coupé ET Claude au travail : le survol ouvre le Centre (Claude en bulle ne s'ouvre pas sur lui-même) ; le micro s'y rouvre
        c.activerLeMicro(true); c.basculerLeMicro(); pause(0.8)
        verifier(m.microCoupe && m.courante == .microCompact && m.pastille == .claude, "micro coupé : « Coupé » dans les ailes, Claude en bulle (\(m.courante))")
        c.panneau.simulerPointeur(forme: true); pause(1.0)
        verifier(m.courante == .centre, "survol : le Centre (le bouton Micro rouge y est) (\(m.courante))")
        clic(PlanCentre.centreRond(m, .micro), 0.5)
        verifier(!faux.coupe && !m.microCoupe && m.courante == .centre, "Micro : rouvert d'un clic, le Centre reste ouvert")
        refermer()
        m.claude = nil; m.sessionsClaude = []; m.claudeAuTravail = 0; m.claudeBranche = false; m.donneesChangees(); pause(0.6)

        // --- le menu de Verbe (barre des menus) : couper / rouvrir le micro, le chemin quand l'îlot n'a pas d'encoche où s'ouvrir
        verifier(c.titreMenuMicro == "Couper le micro", "menu de Verbe, micro ouvert : « Couper le micro »")
        c.couperOuRouvrirLeMicro(depuis: "l'essai"); pause(0.5)
        verifier(faux.coupe && m.microCoupe && c.titreMenuMicro == "Rouvrir le micro", "l'entrée du menu coupe le micro ; elle dit ensuite « Rouvrir le micro »")
        c.couperOuRouvrirLeMicro(depuis: "l'essai"); pause(0.5)
        verifier(!faux.coupe && !m.microCoupe, "et le rouvre")
        c.activerLeMicro(false); pause(0.2)
        let avant = memoire.micros
        c.couperOuRouvrirLeMicro(depuis: "l'essai"); pause(0.5)
        verifier(faux.coupe && memoire.micros == avant + 1, "« Micro coupé » éteint dans les réglages : l'entrée du menu l'allume, puis coupe")
        c.couperOuRouvrirLeMicro(depuis: "l'essai"); pause(0.5)
        c.activerLeMicro(false)
        // le micro rouvert hors du Centre s'annonce (« Micro ouvert », 1,5 s) : on attend qu'il parte
        attendre(3.0) { m.bandeau != nil }; pause(0.8)

        // --- l'îlot vide s'ouvre au survol sur le Centre (non épinglé) ; un clic sur le dernier point (l'accueil, plus court) l'épingle :
        // la forme rétrécit sous le pointeur, qui en sort, et l'îlot reste là
        c.panneau.simulerPointeur(forme: true); pause(1.0)
        verifier(m.courante == .centre && !m.epingle, "îlot vide, survol : le Centre (pas épinglé) (\(m.courante))")
        let n = m.cartes.count
        let dernier = PointsCartes.centre(n - 1, sur: n, corps: CGFloat(m.trace.corps), hauteur: CGFloat(m.geo[2].x), barre: g.hauteur)
        clic(dernier, 0.9)
        verifier(m.courante == .accueil && m.epingle, "vrai clic sur le dernier point : l'accueil (plus court que le Centre : épinglé) (\(m.courante))")
        verifier(Double(dernier.y) > m.trace.hauteur, "le point cliqué est maintenant sous la forme rétrécie (\(Int(dernier.y)) pt, forme : \(Int(m.trace.hauteur)) pt)")
        c.panneau.simulerPointeur(forme: false); pause(0.8)
        verifier(m.courante == .accueil, "le pointeur hors de la forme : l'accueil reste ouvert (« Coller », « Dire un rappel » atteignables)")
        refermer()
        // même chose avec deux doigts, le pointeur dans le bas du Centre (de vrais événements de défilement)
        c.panneau.simulerPointeur(forme: true); pause(1.0)
        let bas = CGPoint(x: 0, y: CGFloat(m.geo[2].x) - 30)
        for (i, d) in [Int32(-6), -12, -10].enumerated() { c.panneau.envoyerDefilement(dy: d, en: bas, phase: i == 0 ? 1 : 2); pause(0.016) }
        c.panneau.envoyerDefilement(dy: 0, en: bas, phase: 4); pause(0.8)
        verifier(m.courante == .outils && m.epingle && Double(bas.y) > m.trace.hauteur, "deux doigts, pointeur en bas du Centre : les Outils (plus courts), épinglés (le pointeur est sous la forme) (\(m.courante))")
        c.panneau.simulerPointeur(forme: false); pause(0.8)
        verifier(m.courante == .outils, "la souris bouge : les Outils restent ouverts")
        refermer()

        // --- le Centre épinglé : un clic dans son vide ne le range pas (ni pendant « Modifier »)
        c.panneau.simulerPointeur(forme: true); pause(1.0)
        clic(PlanCentre.centreRond(m, .micro), 0.5)
        clic(PlanCentre.centreRond(m, .micro), 0.5)
        verifier(m.courante == .centre && m.epingle, "deux clics sur Micro : le Centre épinglé")
        let ronds = PlanCentre.cadreRonds(m), cases = PlanCentre.cadreCase(m, .minuteur), fond = PlanCentre.fond(m.grille)
        for (p, ou) in [(CGPoint(x: 0, y: (ronds.maxY + cases.minY) / 2), "entre les ronds et les cases"),
                        (CGPoint(x: fond.minX + 6, y: ronds.midY), "dans la marge gauche"),
                        (CGPoint(x: 0, y: (PlanCentre.cadreEntete(m.grille).maxY + ronds.minY) / 2), "entre l'en-tête et les ronds")] {
            clic(p, 0.5)
            verifier(m.courante == .centre && m.epingle, "vrai clic \(ou) : le Centre reste ouvert")
        }
        m.editionCentre = true; pause(0.3)
        clic(CGPoint(x: 0, y: (ronds.maxY + cases.minY) / 2), 0.4)
        verifier(m.editionCentre && m.courante == .centre, "« Modifier » : un clic dans le vide ne termine pas l'édition")
        m.editionCentre = false; pause(0.3)

        // --- un bandeau pendant que le Centre est épinglé : il attend qu'il se range ; le volume reste à macOS
        m.annoncer(bandeau: BandeauIlot(vue: .appareil, jusqua: c.maintenant().addingTimeInterval(3.5), ligne1: "AirPods Pro", ligne2: "",
                                        appareil: AppareilIlot(nom: "AirPods Pro", genre: .ecouteurs, gauche: 80, droit: 78, etui: 45)))
        pause(0.5)
        verifier(m.courante == .centre && m.epingle && m.bandeau == nil, "« AirPods connectés » arrive : le Centre épinglé reste ouvert, le bandeau attend")
        verifier(!m.peutMontrerNiveau, "une touche de volume, Centre ouvert : l'îlot ne la prend pas (macOS l'affiche)")
        clic(CGPoint(x: 0, y: g.hauteur / 2), 0.6)
        verifier(m.courante == .appareil && m.bandeau?.ligne1 == "AirPods Pro", "vrai clic sur l'îlot dans la barre : le Centre se range, le bandeau paraît (\(m.courante))")
        c.panneau.simulerPointeur(forme: false)
        attendre(5.0) { m.bandeau != nil }; pause(0.8)
        verifier(m.bandeau == nil && m.courante == .repos, "le pointeur parti, le bandeau aussi : l'îlot vide (\(m.courante))")

        // --- le minuteur éteint dans les réglages : « 10 » l'allume, puis le lance (avant : le bouton ne faisait rien)
        memoire.minuteur = false
        c.panneau.simulerPointeur(forme: true); pause(1.0)
        let cm = PlanCentre.cadreCase(m, .minuteur)
        clic(CGPoint(x: cm.minX + 14 + CapMinutes.largeur + 6 + 22, y: cm.minY + 11 + 17 + 8 + 14), 0.5)
        verifier(memoire.minuteur && memoire.minuteurAllume == 1 && abs((c.minuteur?.restant(a: c.maintenant()) ?? 0) - 600) < 2 && m.courante == .centre,
                 "minuteur éteint, vrai clic sur « 10 » : le réglage s'allume, 10 min lancées, le Centre reste ouvert (\(m.courante))")
        m.surAction(.minuteurArreter); pause(0.2)
        refermer()

        // --- Téléchargements : la question de macOS se répond d'un clic dans SA fenêtre ; ce clic ailleurs ne range pas le Centre
        c.panneau.simulerPointeur(forme: true); pause(1.0)
        m.telechargementsAttente = true
        m.clicAilleurs(); pause(0.4)
        verifier(m.courante == .centre, "« Un instant… » : un clic ailleurs (la réponse à macOS) ne range pas le Centre (\(m.courante))")
        m.telechargementsAttente = false
        m.clicAilleurs(); pause(0.6)
        verifier(m.courante != .centre, "la réponse venue : un clic ailleurs range le Centre de nouveau")
        refermer()
        // refusé alors que le Centre s'est rangé : la ligne d'avis attend la prochaine ouverture, puis part quand il se range
        let ferme = dossier.appendingPathComponent("refus-chemins", isDirectory: true)
        try? FileManager.default.createDirectory(at: ferme, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: ferme.path)
        c.telechargementsSource.arreter(); c.telechargementsSource.dossier = ferme
        c.reglerTelechargements(false); pause(0.2)
        m.surAction(.centreTelechargements); pause(0.6)
        verifier(!m.telechargementsActifs && !m.telechargementsAttente && m.avisCentre == .telechargementsRefuses && m.courante != .centre,
                 "refus arrivé Centre rangé : « Éteint », la ligne « Accès refusé » attend (\(String(describing: m.avisCentre)))")
        c.panneau.simulerPointeur(forme: true); pause(1.0)
        verifier(m.courante == .centre && m.avisCentre == .telechargementsRefuses, "le Centre rouvert : la ligne « Accès refusé : ouvre Réglages Système » est là")
        refermer()
        verifier(m.avisCentre == nil, "vue, puis le Centre rangé : la ligne d'avis part")
        // un refus venu d'ailleurs (accès retiré dans Réglages Système), Centre fermé : pas d'avis
        c.reglerTelechargements(true); pause(0.6)
        verifier(m.avisCentre == nil && !m.telechargementsActifs, "refus venu d'ailleurs, Centre fermé : aucune ligne d'avis")
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ferme.path)

        // --- un glisser de fichiers passe sur le Centre ouvert au survol, puis repart vers une autre app : le Centre se referme
        c.activerEtagere(true); pause(0.2)
        c.panneau.simulerPointeur(forme: true); pause(1.0)
        verifier(m.courante == .centre && !m.epingle, "survol : le Centre (pas épinglé)")
        let ce = PlanCentre.cadreCase(m, .etagere)
        verifier(c.panneau.glisserSurLIlot(CGPoint(x: ce.midX, y: ce.midY)) && m.depot, "un fichier glissé passe sur la case Étagère")
        c.panneau.simulerPointeur(forme: false); pause(0.6)
        verifier(m.courante == .centre, "pendant le glisser, le pointeur sorti : le Centre attend (on pourrait lâcher)")
        c.panneau.glisser(CGPoint(x: 0, y: 600), fichiers: { true }); pause(0.8)
        verifier(!m.depot && m.courante != .centre, "le glisser repart vers une autre app : le Centre se referme (\(m.courante))")
        c.panneau.finDuGlisser(); c.activerEtagere(false)
        refermer()
        c.reglagesCentre = ReglagesCentre(telechargements: { false }, reglerTelechargements: { _ in }, microChoisi: { nil }, choisirMicro: { _ in },
                                          bulleVue: { true }, marquerBulleVue: {}, centreUtilise: { true }, marquerCentreUtilise: {},
                                          allumerMicro: {}, allumerClaude: {}, allumerEtagere: {}, disposition: { nil }, enregistrerDisposition: { _ in },
                                          minuteurActif: { true }, allumerMinuteur: {})
    }
}
