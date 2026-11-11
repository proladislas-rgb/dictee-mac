import AppKit
import DicteeCore

/// `Verbe --ilot-essai` : essai de bout en bout de l'îlot « centre d'activités », SANS rien montrer à l'écran (fenêtre transparente qui ne
/// reçoit aucun clic) et sans rien toucher du système : ni micro, ni clavier, ni Accessibilité, ni son (les sons sont des compteurs), ni
/// calendrier (rendez-vous simulés), ni notifications, ni lecture réelle (le programme d'aide n'est pas lancé : on lui injecte un morceau),
/// ni ouverture de lien (capturée). Les rappels vont dans un dossier temporaire, jamais dans le vrai fichier.
enum IlotEssai {
    @MainActor
    static func executer() -> Int32 {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        var echecs = 0
        func verifier(_ ok: Bool, _ nom: String) { print(ok ? "  ok   \(nom)" : "  ÉCHEC \(nom)"); if !ok { echecs += 1 } }
        func attendre(_ s: Double, tant: () -> Bool = { true }) {
            let fin = Date().addingTimeInterval(s)
            while Date() < fin, tant() { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
        }
        let dossier = FileManager.default.temporaryDirectory.appendingPathComponent("verbe-ilot-essai-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dossier) }
        let fichier = dossier.appendingPathComponent("rappels.json")

        var decalage = 0.0
        var compteurs = (minuteur: 0, rappel: 0, doux: 0, silence: 0)
        var liensOuverts: [URL] = []
        var notes = 0
        func fabriquer() -> IlotControleur {
            let c = IlotControleur(stockage: RappelsStore(url: fichier))
            c.maintenant = { Date().addingTimeInterval(decalage) }
            c.sons = IlotControleur.SonsIlot(minuteurFini: { compteurs.minuteur += 1 }, rappel: { compteurs.rappel += 1 }, doux: { compteurs.doux += 1 }, silencieux: { compteurs.silence += 1 })
            c.ouvrir = { liensOuverts.append($0) }
            c.surNoter = { _ in notes += 1 }
            c.panneau.invisible = true
            c.lecture.essaiInvisible = true
            return c
        }
        CadenceEcran.minuterieSeulement = true
        let c = fabriquer()
        c.panneau.demarrer()
        let m = c.moteur
        let g = m.geometrie
        print("caméra : \(Int(g.largeur)) × \(Int(g.hauteur)) pt")

        // --- repos : l'îlot vide épouse l'encoche
        attendre(0.4)
        verifier(m.courante == .repos && m.resolution.principal == .repos, "rien d'actif : l'îlot est vide")
        let notch = NSScreen.screens.first.map { $0.safeAreaInsets.top > 0 } ?? false
        if notch {
            verifier(c.panneau.estVisible, "îlot vide : la fenêtre existe sur l'encoche (pour le clic qui ouvre l'accueil)")
            if let f = c.panneau.cadre { verifier(f.width <= g.largeur + 4.5 && f.height <= g.hauteur + 6.5, "fenêtre vide : \(Int(f.width)) × \(Int(f.height)) pt, à peine plus que l'encoche") }
        }
        verifier(!m.boucleActive, "au repos : aucune boucle d'animation ne tourne")

        // --- lecture : compact dans les ailes, jamais plus large que les ailes dans la barre des menus
        c.lecture.modele.morceau = MorceauEnCours(titre: "Album · Titre 3", app: "essai.lecture", joue: true, duree: 214, position: 97)
        c.lecture.surIlot(true)
        attendre(0.9)
        verifier(m.courante == .lectureCompact, "la lecture occupe l'îlot en compact")
        if let f = c.panneau.cadre {
            let demi = Double(g.largeur) / 2
            verifier(Double(f.width) <= 2 * (demi + GeoIlot.aileMax) + 4.5, "fenêtre compacte \(Int(f.width)) × \(Int(f.height)) : pas plus large que les ailes (+ 2 pt de chaque côté)")
            verifier(Double(f.height) <= Double(g.hauteur) + 6 + 6.5, "fenêtre compacte : 6 pt sous la barre au plus")
        }
        verifier(!m.boucleActive, "lecture affichée au repos : aucune boucle (l'onde tourne dans le serveur d'affichage)")

        // --- survol avec intention : passage rapide = rien, souris posée = déplié, sortie = refermé après 0,45 s
        c.panneau.simulerPointeur(forme: true); attendre(0.1); c.panneau.simulerPointeur(forme: false); attendre(0.7)
        verifier(m.courante == .lectureCompact, "passage rapide de la souris (0,1 s) : rien ne s'ouvre")
        c.panneau.simulerPointeur(forme: true); attendre(0.15)
        verifier(m.courante == .lectureCompact, "souris posée depuis 0,15 s : toujours compact (intention de 0,28 s)")
        attendre(0.4)
        verifier(m.courante == .lectureEtendu, "souris posée : la lecture se déplie")
        attendre(0.8)
        let grandeFenetre = c.panneau.cadre
        verifier((grandeFenetre?.height ?? 0) > Double(g.hauteur) + 120, "la fenêtre grandit avec l'îlot (\(Int(grandeFenetre?.width ?? 0)) × \(Int(grandeFenetre?.height ?? 0)))")
        verifier(!m.boucleActive, "îlot déplié et posé : plus de boucle (les ressorts sont arrivés)")
        c.panneau.simulerPointeur(forme: false); attendre(0.25)
        verifier(m.courante == .lectureEtendu, "souris sortie depuis 0,25 s : encore ouvert (délai de 0,32 s)")
        c.panneau.simulerPointeur(forme: true); attendre(0.6)
        verifier(m.courante == .lectureEtendu, "souris revenue avant 0,32 s : la fermeture est annulée")
        c.panneau.simulerPointeur(forme: false); attendre(0.7)
        verifier(m.courante == .lectureCompact, "souris partie : refermé")
        attendre(0.9)
        verifier((c.panneau.cadre?.height ?? 99) < 60, "la fenêtre reprend sa taille compacte")
        m.clicForme(); attendre(0.1)
        verifier(m.courante == .lectureEtendu, "clic : déplie tout de suite, sans attendre l'intention")
        m.clicForme(); attendre(0.1)
        verifier(m.courante == .lectureCompact, "second clic : se replie")

        // --- appui long sur la lecture : la rangée Minuteur (maquette apple-acces/1-controles.html)
        m.clicForme(); attendre(0.9)
        verifier(m.courante == .lectureEtendu, "lecture dépliée avant l'appui long")
        verifier(m.appuiLong(minuteurActif: true), "appui long sur la lecture dépliée : accepté")
        attendre(0.05)
        verifier(m.courante == .lectureMinuteur && m.visible(.lectureEtendu) && m.aspect(.lectureEtendu, rang: 0).opacite > 0.99,
                 "la rangée arrive SOUS la lecture, qui ne s'efface pas (titre toujours opaque)")
        verifier(abs(m.ouverture(.lecture) - 1) < 0.001, "la pochette reste posée pendant que l'îlot s'allonge")
        attendre(1.5)
        let hRangee = c.panneau.cadre?.height ?? 0
        verifier(Double(m.geo[2].x) > Double(g.hauteur) + 175 + 50 && !m.boucleActive, "îlot allongé de la rangée (\(Int(m.geo[2].x)) pt), puis plus de boucle")
        verifier(Double(hRangee) >= m.geo[2].x, "la fenêtre couvre l'îlot allongé (\(Int(hRangee)) pt)")
        c.agir(.minuteurLancerSousLecture(minutes: 10)); attendre(0.05)
        verifier(m.ouverture(.lecture) <= 1.001, "repli depuis la rangée : la pochette part de sa place, sans bond (\(String(format: "%.2f", m.ouverture(.lecture))))")
        attendre(1.0)
        verifier(m.bandeau == nil && m.courante == .lectureCompact && m.pastille == .minuteur && abs((c.minuteur?.restant(a: c.maintenant()) ?? 0) - 600) < 2,
                 "« 10 min » : l'îlot se replie sur la lecture, le minuteur part dans la pastille, sans bandeau")
        c.agir(.minuteurArreter); attendre(0.5)
        verifier(m.appuiLong(minuteurActif: false) == false && m.courante == .lectureCompact, "minuteur éteint dans les réglages : l'appui long ne fait rien")
        // vrais événements souris remis à la fenêtre (gestes SwiftUI) : clic court, appui long, clic sur une durée
        let milieu = CGPoint(x: 0, y: g.hauteur / 2)
        c.panneau.envoyerSouris(.leftMouseDown, en: milieu); attendre(0.08); c.panneau.envoyerSouris(.leftMouseUp, en: milieu); attendre(0.9)
        verifier(m.courante == .lectureEtendu, "vrai clic court sur la lecture : elle se déplie (comme avant)")
        c.panneau.envoyerSouris(.leftMouseDown, en: CGPoint(x: 0, y: g.hauteur + 10)); attendre(0.2)
        verifier(m.presse, "pendant l'appui : l'îlot gonfle sous le doigt")
        attendre(0.4)
        c.panneau.envoyerSouris(.leftMouseUp, en: CGPoint(x: 0, y: g.hauteur + 10)); attendre(0.9)
        verifier(m.courante == .lectureMinuteur && !m.presse, "vrai appui long (0,6 s) : la rangée Minuteur s'ouvre")
        // appui puis glissé hors de l'îlot : pas d'appui long, pas de clic
        m.fermer(); attendre(0.9)
        m.debutAppui(origine: CGPoint(x: 1, y: 1)); m.debutAppui(origine: CGPoint(x: 1, y: 1), distance: 30); attendre(0.6)
        m.finAppui(deplace: true); attendre(0.6)
        verifier(m.courante == .lectureCompact && !m.presse, "appui puis glissé hors de l'îlot : ni rangée ni dépliage")
        // appui interrompu par une dictée (le relâchement n'arrive jamais) : le clic suivant marche
        m.debutAppui(origine: CGPoint(x: 2, y: 2)); attendre(0.1)
        var occA = OccupationEncoche(); c.occupation = { occA }
        occA.dictee = true; c.occupationChangee(); attendre(0.6)
        verifier(!m.presse, "dictée pendant l'appui : l'îlot n'est plus gonflé")
        occA.dictee = false; c.occupationChangee(); c.occupation = { OccupationEncoche() }; attendre(0.9)
        m.debutAppui(origine: CGPoint(x: 3, y: 3)); attendre(0.05); m.finAppui(deplace: false); attendre(0.9)
        verifier(m.courante == .lectureEtendu, "après un appui resté en plan : le clic suivant déplie normalement")
        c.panneau.envoyerSouris(.leftMouseDown, en: milieu); attendre(0.6); c.panneau.envoyerSouris(.leftMouseUp, en: milieu); attendre(0.9)
        // « 25 min » : la dernière pilule, calée sur la marge droite
        let w = m.grille.corps(.lectureMinuteur)
        let cap = CGPoint(x: w - GrilleIlot.marge - 30, y: g.hauteur + 175 + 3 + 21)
        c.panneau.envoyerSouris(.leftMouseDown, en: cap); attendre(0.08); c.panneau.envoyerSouris(.leftMouseUp, en: cap); attendre(1.0)
        verifier(abs((c.minuteur?.restant(a: c.maintenant()) ?? 0) - 1500) < 2 && m.courante == .lectureCompact && m.pastille == .minuteur,
                 "vrai clic sur « 25 min » : minuteur de 25 min en pastille, la lecture garde l'îlot")
        c.agir(.minuteurArreter); attendre(0.5)
        // la commande dictée marche aussi quand la lecture est dépliée (l'accueil n'est pas ouvrable pendant une vidéo)
        m.clicForme(); attendre(0.6)
        var occL = OccupationEncoche()
        c.occupation = { occL }
        c.dicteeChange(enCours: true); occL.dictee = true; c.occupationChangee(); attendre(0.2)
        occL.dictee = false; c.dicteeChange(enCours: false); c.occupationChangee(); attendre(0.3)
        verifier(c.intercepter("Minuteur 3 minutes.") == true && abs((c.minuteur?.restant(a: c.maintenant()) ?? 0) - 180) < 2,
                 "lecture dépliée + « minuteur 3 minutes » dicté : minuteur lancé, rien n'est collé")
        verifier(m.bandeau?.vue == .minuteurLance, "dicté : le bandeau « Minuteur lancé » confirme (rien n'a été cliqué)")
        c.agir(.minuteurArreter); attendre(3.0) { m.bandeau != nil }; attendre(0.6)
        c.occupation = { OccupationEncoche() }
        verifier(m.courante == .lectureCompact && c.minuteur == nil, "retour à la lecture seule")

        // --- minuteur : bandeau, puis lecture + pastille, puis alerte
        c.lancerLeMinuteur(secondes: 30, bandeau: true)
        attendre(0.15)
        verifier(m.courante == .minuteurLance && m.bandeau != nil, "minuteur lancé : bandeau « Minuteur lancé »")
        attendre(2.4) { m.bandeau != nil }
        attendre(0.3)
        verifier(m.bandeau == nil && m.courante == .lectureCompact && m.pastille == .minuteur, "le bandeau se retire : la lecture garde l'îlot, le minuteur est en pastille")
        verifier(m.resolution.pastille == .minuteur && c.minuteur != nil, "pastille = minuteur")
        // la bulle : à droite de l'îlot, à la même hauteur, accrochée au haut de l'écran (maquette ilot-apple.html)
        attendre(0.6)
        if let r = m.rectPastille() {
            verifier(r.minY == 0 && abs(r.height - g.hauteur) < 0.01, "bulle : à la même hauteur que l'îlot (\(Int(r.height)) pt, du haut de l'écran), plus sous la barre")
            verifier(abs(r.minX - (CGFloat(m.trace.cou) + IlotMoteur.ecartBulle)) < 0.01 && r.minX > CGFloat(m.trace.bande), "bulle : à droite de l'îlot, séparée par une fente (l'épaule de l'îlot n'y entre pas)")
            let fen = m.fenetreVoulue()
            verifier(fen.minY <= r.minY && fen.maxX >= r.maxX && fen.minX <= -CGFloat(m.trace.bande), "la fenêtre couvre l'îlot et la bulle")
            // vrai clic au milieu de la bulle : les deux échangent
            let p = CGPoint(x: r.midX, y: r.midY)
            c.panneau.envoyerSouris(.leftMouseDown, en: p); attendre(0.06); c.panneau.envoyerSouris(.leftMouseUp, en: p); attendre(0.5)
            if m.courante != .minuteurCompact { m.cliquerPastille(); attendre(0.5); verifier(false, "vrai clic sur la bulle : rien ne s'est passé") }
        } else { verifier(false, "bulle : posée (rectPastille)") ; m.cliquerPastille(); attendre(0.5) }
        verifier(m.courante == .minuteurCompact && m.pastille == .lecture, "clic sur la pastille : le minuteur prend l'îlot, la lecture devient pastille")
        // pause et +1 min
        let avantPause = c.minuteur?.restant(a: c.maintenant()) ?? 0
        c.agir(.minuteurBasculer); attendre(0.5)
        let enPause = c.minuteur?.restant(a: c.maintenant()) ?? 0
        verifier(c.minuteur?.enPause == true && abs(enPause - (c.minuteur?.restant(a: c.maintenant().addingTimeInterval(5)) ?? 0)) < 0.001 && enPause <= avantPause, "pause : le temps ne passe plus")
        c.agir(.minuteurPlusUneMinute)
        verifier(abs((c.minuteur?.restant(a: c.maintenant()) ?? 0) - (enPause + 60)) < 0.05, "+1 min en pause")
        c.agir(.minuteurBasculer)
        c.agir(.minuteurArreter); attendre(0.4)
        verifier(c.minuteur == nil && m.courante == .lectureCompact && m.resolution.pastille == nil, "arrêt : plus de minuteur, plus de pastille")
        // fin du minuteur
        let sonsAvant = compteurs.minuteur
        c.lancerLeMinuteur(secondes: 1.2, bandeau: false)
        attendre(2.0) { m.alerte == nil }
        verifier(m.alerte?.vue == .minuteurFini && m.courante == .minuteurFini, "fin du minuteur : l'alerte s'ouvre d'elle-même")
        verifier(compteurs.minuteur == sonsAvant + 1, "fin du minuteur : son et vibration demandés une fois")
        verifier(m.pastille == .lecture, "alerte : la lecture patiente en pastille")
        attendre(0.9)
        c.panneau.simulerPointeur(forme: true); attendre(0.5)
        verifier(m.courante == .minuteurFini, "une alerte ne se replie ni ne se déplie au survol (verrou)")
        c.panneau.simulerPointeur(forme: false)
        c.agir(.minuteurRecommencer(minutes: 5)); attendre(0.5)
        verifier(m.alerte == nil && c.minuteur != nil, "« Encore 5 min » : nouvelle alerte acquittée, nouveau minuteur")
        c.agir(.minuteurArreter); attendre(0.3)

        // --- batterie et appareils : épaules du déplié, chargeur branché, batterie faible, écouteurs connectés (sans le vrai Bluetooth)
        let airpods = AppareilIlot(nom: "AirPods Pro", genre: .ecouteurs, gauche: 80, droit: 78, etui: 45)
        c.energieChangee(EnergieIlot(pourcent: 55, secteur: false, enCharge: false))
        m.ecouteurs = airpods; m.donneesChangees(); attendre(0.4)
        verifier(m.courante == .lectureCompact && m.bandeau == nil, "batterie lue au départ : aucune annonce")
        c.panneau.simulerPointeur(forme: true); attendre(1.4)
        verifier(m.courante == .lectureEtendu && abs(m.geo[0].x - GeoIlot.epaules) < 0.05 && m.ouvertureEpaules > 0.99, "survol : la lecture se déplie, le cou s'élargit à 56 pt, les épaules (batterie, AirPods) sont là")
        verifier(m.trace.bande <= Double(m.demiCamera) + GeoIlot.aileMax + 0.01, "épaules : rien ne dépasse 66 pt dans la barre des menus")
        c.panneau.simulerPointeur(forme: false); attendre(1.2)
        verifier(m.courante == .lectureCompact && m.ouvertureEpaules == 0, "la souris part : les épaules s'effacent avec le dépliage")
        c.energieChangee(EnergieIlot(pourcent: 55, secteur: true, enCharge: true)); attendre(0.3)
        verifier(m.courante == .batterieCharge && m.pastille == .lecture, "on branche : « En charge » dans les ailes, la vidéo passe en bulle")
        verifier(m.trace.hauteur <= Double(g.hauteur) + 0.01, "« En charge » : rien ne descend sous la barre")
        attendre(3.6) { m.bandeau != nil }
        verifier(m.bandeau == nil && m.courante == .lectureCompact, "3 s plus tard : la vidéo reprend l'îlot")
        c.energieChangee(EnergieIlot(pourcent: 21, secteur: false, enCharge: false)); attendre(0.2)
        verifier(m.bandeau == nil, "débranché à 21 % : rien")
        c.energieChangee(EnergieIlot(pourcent: 20, secteur: false, enCharge: false)); attendre(0.3)
        verifier(m.courante == .batterieFaible, "20 % : « Faible » en rouge")
        attendre(5.0) { m.bandeau != nil }
        c.energieChangee(EnergieIlot(pourcent: 19, secteur: false, enCharge: false)); attendre(0.3)
        verifier(m.bandeau == nil, "19 % : pas une deuxième fois")
        c.appareilConnecte(airpods); attendre(0.9)
        verifier(m.courante == .appareil && (m.contenus[.appareil] ?? 0) > 200, "AirPods connectés : le bandeau avec le nom et les trois jauges (\(Int(m.contenus[.appareil] ?? 0)) pt de contenu)")
        attendre(4.0) { m.bandeau != nil }
        verifier(m.bandeau == nil && m.courante == .lectureCompact, "3,5 s plus tard : il se retire")
        m.energie = nil; m.ecouteurs = nil; m.donneesChangees(); attendre(0.4)

        // --- dictée : tout est effacé ; ce qui arrive attend la fin, sans son
        var occ = OccupationEncoche()
        c.occupation = { occ }
        occ.dictee = true; c.occupationChangee(); attendre(0.9)
        verifier(m.cache && c.panneau.cadre.map { _ in !c.panneau.estVisible } ?? true, "dictée : l'îlot est effacé, la fenêtre retirée")
        let avantDictee = compteurs
        c.lancerLeMinuteur(secondes: 0.5, bandeau: false)
        attendre(1.2)
        verifier(m.alerte == nil && compteurs.minuteur == avantDictee.minuteur, "fin d'un minuteur PENDANT la dictée : rien à l'écran, aucun son")
        occ.dictee = false; c.occupationChangee(); attendre(0.9)
        verifier(m.alerte?.vue == .minuteurFini && compteurs.minuteur == avantDictee.minuteur + 1 && !m.cache, "dictée finie : l'alerte attendue s'affiche, avec son")
        c.agir(.alerteOK); attendre(0.4)

        // --- réunion : rien à l'écran, vibration seule
        occ.reunion = true; c.occupationChangee(); attendre(0.5)
        let s0 = compteurs
        c.ajouterUnRappel(texte: "Appeler Paul", quand: Date().addingTimeInterval(decalage + 0.4))
        attendre(1.4)
        verifier(m.cache && m.alerte == nil, "réunion : un rappel qui sonne n'affiche rien")
        occ.reunion = false; c.occupationChangee(); attendre(0.9)
        verifier(m.alerte?.vue == .rappelEtendu && compteurs.rappel == s0.rappel + 1, "réunion finie : le rappel s'affiche")
        verifier(c.rappels.enAttente.count == 1, "le rappel est marqué « sonné » (la cloche reste s'il n'est pas acquitté)")
        // sans réponse : l'alerte se retire seule (12 s) et la cloche reste ; ici on simule en retirant l'alerte
        c.moteur.quitterAlerte(); attendre(0.5)
        verifier(m.courante != .rappelEtendu && m.resolution.principal == .rappelCompact, "sans réponse : la cloche reste dans l'aile (compact rappel)")
        // persistance : un nouveau contrôleur relit le fichier
        let c2 = fabriquer()
        verifier(c2.rappels.enAttente.count == 1 && c2.rappels.enAttente.first?.texte == "Appeler Paul", "après relance : le rappel sonné sans réponse est toujours là")
        let rappelId = c.rappels.enAttente[0].id
        c.agir(.rappelPlusTard(rappelId)); attendre(0.4)
        verifier(c.moteur.bandeau?.vue == .rappelReporte && c.rappels.enAttente.isEmpty && c.rappels.aVenir(a: c.maintenant()).count == 1, "Plus tard : bandeau, plus de cloche, il reviendra dans 10 min")
        attendre(3.0) { m.bandeau != nil }
        // rappel arrivé à échéance pendant que Verbe était fermé
        let c3 = fabriquer()
        c3.agir(.rappelFait(rappelId))
        verifier(c3.rappels.rappels.isEmpty, "Fait : le rappel disparaît du fichier")
        var plusTard = ListeRappels(); plusTard.ajouter(texte: "Pendant que Verbe dormait", echeance: Date().addingTimeInterval(-600), maintenant: Date().addingTimeInterval(-3600))
        RappelsStore(url: fichier).ecrire(plusTard)
        let c4 = fabriquer(); c4.panneau.demarrer(); c4.verifierLesRappels(); attendre(0.5)
        verifier(c4.moteur.alerte?.vue == .rappelEtendu && c4.moteur.alerte?.rappel?.texte == "Pendant que Verbe dormait", "un rappel arrivé à échéance fermé sonne à la relance")
        c4.panneau.fermer()
        RappelsStore(url: fichier).ecrire(ListeRappels())

        // --- calendrier simulé
        let t = c.maintenant()
        let lien = URL(string: "https://meet.google.com/abc-defg-hij")!
        let ev = EvenementAgenda(id: "essai", titre: "Point équipe", debut: t.addingTimeInterval(600), fin: t.addingTimeInterval(2600), lien: lien)
        c.injecterEvenements([ev]); attendre(0.5)
        verifier(m.bandeau?.vue == .agendaAvant && m.rendezVousProche, "10 min avant : le rendez-vous s'annonce (bandeau « Dans 10 min »)")
        attendre(5.0) { m.bandeau != nil }; attendre(0.3)
        verifier(m.resolution.principal == .agendaCompact, "puis il se replie : compact « 10 min » dans l'aile")
        verifier(compteurs.doux >= 1, "10 min avant : un son très doux")
        attendre(0.2)
        decalage = 601; c.planifierAgenda(); attendre(0.5)
        verifier(m.alerte?.vue == .agendaDebut && m.courante == .agendaDebut, "au début : petite alerte")
        c.agir(.rendezVousRejoindre(ev)); attendre(0.3)
        verifier(liensOuverts == [lien] && m.alerte == nil, "« Rejoindre » ouvre le lien visio (capturé) et ferme l'alerte")
        c.injecterEvenements([EvenementAgenda(id: "essai2", titre: "Autre", debut: c.maintenant().addingTimeInterval(-60), fin: c.maintenant().addingTimeInterval(1800))]); attendre(0.4)
        c.agir(.rendezVousNoter(ev)); attendre(0.2)
        verifier(notes == 1, "« Noter la réunion » lance la prise de notes existante")
        decalage = 0

        // --- accueil et commandes dictées
        c.injecterEvenements([]); c.moteur.quitterAlerte(); attendre(0.5)
        c.lecture.modele.morceau = nil; c.lecture.surIlot(false); attendre(0.3)
        verifier(m.resolution.principal == .repos && m.resolution.survol == .accueil, "plus rien : accueil possible")
        c.panneau.simulerPointeur(forme: true); attendre(0.6)
        verifier(m.courante == .repos, "îlot vide : le survol seul n'ouvre pas l'accueil")
        c.panneau.simulerPointeur(forme: false); attendre(0.6)
        m.clicForme(); attendre(0.6)
        verifier(m.courante == .accueil, "clic sur l'îlot vide : l'accueil et ses tuiles")
        verifier(c.intercepter("minuteur 10 minutes") == false && c.minuteur == nil, "sans dictée armée, une commande n'est jamais interceptée")
        c.dicteeChange(enCours: true)   // l'accueil est ouvert à cet instant : la commande dictée est armée
        occ.dictee = true; c.occupationChangee(); attendre(0.3)
        occ.dictee = false; c.dicteeChange(enCours: false); c.occupationChangee()
        verifier(c.intercepter("Bonjour Paul, je te rappelle demain.") == false, "accueil ouvert + phrase normale : le texte est collé normalement")
        c.moteur.clicForme(); attendre(0.5)
        verifier(m.courante == .accueil, "accueil rouvert avant de dicter")
        c.dicteeChange(enCours: true); occ.dictee = true; c.occupationChangee(); attendre(0.2)
        occ.dictee = false; c.dicteeChange(enCours: false); c.occupationChangee(); attendre(0.2)
        verifier(c.intercepter("Minuteur 10 minutes.") == true && c.minuteur != nil, "accueil ouvert + « minuteur 10 minutes » : minuteur lancé, rien n'est collé")
        verifier(abs((c.minuteur?.restant(a: c.maintenant()) ?? 0) - 600) < 2, "le minuteur dicté dure 10 minutes")
        c.agir(.minuteurArreter)
        verifier(c.intercepter("Minuteur 10 minutes.") == false, "la commande n'est utilisable qu'une fois par dictée armée")

        // --- fin : plus rien ne tourne
        c.moteur.fermer(); attendre(1.3)
        verifier(!m.boucleActive, "tout est refermé : aucune boucle d'animation (bouge encore : \(m.ceQuiBouge))")
        c.arreter()
        print(echecs == 0 ? "essai terminé : tout est vert" : "essai terminé : \(echecs) échec(s)")
        return echecs == 0 ? 0 : 1
    }
}
