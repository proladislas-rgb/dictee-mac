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
        var finder: [[URL]] = []
        var notes = 0
        func fabriquer() -> IlotControleur {
            let c = IlotControleur(stockage: RappelsStore(url: fichier))
            c.maintenant = { Date().addingTimeInterval(decalage) }
            c.sons = IlotControleur.SonsIlot(minuteurFini: { compteurs.minuteur += 1 }, rappel: { compteurs.rappel += 1 }, doux: { compteurs.doux += 1 }, silencieux: { compteurs.silence += 1 })
            c.ouvrir = { liensOuverts.append($0) }
            c.montrer = { finder.append($0) }
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

        // --- Téléchargé : un VRAI dossier surveillé, temporaire (jamais ~/Downloads, qui demanderait une autorisation)
        let telechargements = dossier.appendingPathComponent("Téléchargements", isDirectory: true)
        try? FileManager.default.createDirectory(at: telechargements, withIntermediateDirectories: true)
        func deposer(_ nom: String, _ octets: Int) { try? Data(repeating: 0x2A, count: octets).write(to: telechargements.appendingPathComponent(nom)) }
        deposer("Déjà là.pdf", 5_000)
        c.telechargementsSource.dossier = telechargements
        c.telechargementsSource.demarrer(); attendre(0.4)
        verifier(c.telechargementsSource.actif && m.bandeau == nil, "dossier surveillé : ce qui était déjà là n'est pas annoncé")
        deposer("Contrat-signé.pdf.crdownload", 1_200_000); attendre(1.6)
        verifier(m.bandeau == nil, "« .crdownload » en cours : rien")
        try? FileManager.default.moveItem(at: telechargements.appendingPathComponent("Contrat-signé.pdf.crdownload"), to: telechargements.appendingPathComponent("Contrat-signé.pdf"))
        attendre(0.5)
        verifier(m.bandeau == nil, "renommé à l'instant : pas encore (taille à confirmer pendant 1 s)")
        attendre(2.0) { m.bandeau == nil }; attendre(0.5)
        verifier(m.courante == .telecharge && m.bandeauVu?.ligne1 == "Contrat-signé.pdf" && m.bandeauVu?.ligne2 == "Téléchargé \u{00B7} 1,2\u{00A0}Mo",
                 "fichier fini : « Contrat-signé.pdf », « Téléchargé · 1,2 Mo » (\(m.bandeauVu?.ligne2 ?? "rien"))")
        verifier(m.pastille == .lecture, "la vidéo passe en bulle le temps de l'annonce")
        verifier(m.trace.bande <= Double(m.demiCamera) + GeoIlot.aileMax + 0.01 && m.trace.hauteur > Double(g.hauteur) + 60, "bandeau : sous la barre, rien de plus de 66 pt dans la barre des menus")
        let lc = m.contenus[.telecharge] ?? 0
        verifier(lc > 200 && lc <= 2 * (m.demiCamera + CGFloat(GeoIlot.valeurs(.telecharge, hauteurBarre: Double(g.hauteur))[1])) - 2 * GrilleIlot.marge, "le bandeau épouse l'icône, le nom et « Ouvrir » (\(Int(lc)) pt)")
        attendre(1.2) { m.boucleActive }
        verifier(!m.boucleActive && m.bandeau != nil, "bandeau posé : aucune boucle d'animation (bouge encore : \(m.ceQuiBouge))")
        // vrai clic sur « Ouvrir » (au bord droit du contenu)
        let z = m.grille.zoneAnnonce(.telecharge)
        let bouton = MesureIlot.bouton(ContenuAnnonce.Bouton(titre: "Ouvrir"))
        let pb = CGPoint(x: z.maxX - bouton / 2, y: z.midY)
        c.panneau.envoyerSouris(.leftMouseDown, en: pb); attendre(0.06); c.panneau.envoyerSouris(.leftMouseUp, en: pb); attendre(0.5)
        verifier(liensOuverts.last?.lastPathComponent == "Contrat-signé.pdf" && m.bandeau == nil, "vrai clic sur « Ouvrir » : le fichier est ouvert (capturé), le bandeau se retire")
        // une rafale : un seul bandeau
        attendre(0.6)
        deposer("Photo 1.heic", 900_000); attendre(0.3); deposer("Photo 2.heic", 800_000); attendre(0.3); deposer("Notes.txt", 400)
        attendre(2.5) { m.bandeauVu?.ligne1 != "3 fichiers téléchargés" }; attendre(0.3)
        verifier(m.courante == .telecharge && m.bandeauVu?.ligne1 == "3 fichiers téléchargés", "trois fichiers en rafale : un seul bandeau « 3 fichiers téléchargés » (\(m.bandeauVu?.ligne1 ?? "rien"))")
        c.agir(.fichiersOuvrir(m.bandeauVu?.telechargement?.urls ?? [])); attendre(0.3)
        verifier(finder.last?.count == 3 && m.bandeau == nil, "« Afficher » montre les trois dans le Finder (capturé)")
        attendre(1.5)
        verifier(!m.boucleActive, "plus rien n'arrive : aucune boucle, aucune relecture du dossier")
        c.telechargementsSource.arreter(); attendre(0.2)
        deposer("Après.pdf", 3_000); attendre(1.8)
        verifier(m.bandeau == nil && !c.telechargementsSource.actif, "réglage éteint (surveillance arrêtée) : plus rien n'est annoncé")
        liensOuverts = []

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

        // --- micro coupé : un micro FACTICE (jamais CoreAudio, jamais le vrai micro) ; le raccourci est essayé sur des touches fabriquées,
        // jamais envoyées au système
        do {
            let faux = MicroFactice()
            c.micro = faux
            c.lecture.modele.morceau = MorceauEnCours(titre: "Album · Titre 3", app: "essai.lecture", joue: true, duree: 214, position: 97)
            c.lecture.surIlot(true)
            c.activerLeMicro(true); attendre(0.9)
            verifier(faux.actif && !m.microCoupe && m.resolution.principal == .lectureCompact, "micro ouvert au départ : rien ne change, la lecture garde l'îlot")
            c.basculerLeMicro(); attendre(0.9)
            verifier(faux.commandes == ["couper"] && faux.coupe && m.microCoupe, "raccourci : le micro est coupé (une seule commande)")
            verifier(m.courante == .microCompact && m.pastille == .lecture, "micro coupé : il prend l'îlot, la lecture devient la bulle")
            verifier(m.trace.bande <= Double(m.demiCamera) + GeoIlot.aileMax + 0.01 && abs(m.trace.hauteur - Double(g.hauteur)) < 0.01,
                     "micro coupé : dans les ailes, \(Int(m.trace.bande - Double(m.demiCamera))) pt de chaque côté de la caméra (≤ 66), rien sous la barre")
            let aile = m.grille.bordAile(.microCompact) - m.demiCamera - 4
            verifier(MesureIlot.texte("Coupé", 13, .semibold) <= aile && MesureIlot.texte("Ouvert", 13, .semibold) <= aile,
                     "« Coupé » (\(Int(MesureIlot.texte("Coupé", 13, .semibold))) pt) et « Ouvert » (\(Int(MesureIlot.texte("Ouvert", 13, .semibold))) pt) tiennent dans l'aile (\(Int(aile)) pt)")
            if let b = m.rectPastille() { verifier(b.minX >= CGFloat(m.trace.cou) + 5, "la bulle de la lecture est à côté de l'îlot, pas dessus") }
            attendre(1.2) { m.boucleActive }
            verifier(!m.boucleActive, "micro coupé, posé : aucune boucle d'animation (bouge encore : \(m.ceQuiBouge))")
            // survol : le petit déplié
            c.panneau.simulerPointeur(forme: true); attendre(0.9)
            verifier(m.courante == .microEtendu && m.trace.bande <= Double(m.demiCamera) + GeoIlot.aileMax + 0.01, "survol : « Micro coupé », son nom et « Rouvrir » ; cou étroit dans la barre")
            let lm = m.contenus[.microEtendu] ?? 0
            verifier(lm > 150 && lm <= 2 * m.grille.corps(.microEtendu) - 2 * GrilleIlot.marge + 0.5, "le déplié épouse son contenu (\(Int(lm)) pt)")
            verifier(m.contenuAnnonce(.microEtendu)?.l2 == "Micro MacBook Air", "le nom du micro vient de la source")
            // vrai clic sur « Rouvrir »
            let z = m.grille.zoneAnnonce(.microEtendu)
            let bouton = MesureIlot.bouton(ContenuAnnonce.Bouton(titre: "Rouvrir", icone: "mic.fill"))
            let pb = CGPoint(x: z.maxX - bouton / 2, y: z.midY)
            c.panneau.envoyerSouris(.leftMouseDown, en: pb); attendre(0.06); c.panneau.envoyerSouris(.leftMouseUp, en: pb)
            c.panneau.simulerPointeur(forme: false); attendre(0.4)
            verifier(faux.commandes.last == "rouvrir" && !faux.coupe && !m.microCoupe, "vrai clic sur « Rouvrir » : le micro est rouvert")
            verifier(m.courante == .microOuvert && m.bandeauVu?.ligne1 == "Micro ouvert", "bandeau vert « Micro ouvert »")
            attendre(1.6)
            verifier(m.bandeau == nil && m.resolution.principal == .lectureCompact && m.resolution.pastille == nil,
                     "1,5 s plus tard : il se retire, la lecture reprend l'îlot (\(m.bandeau.map { "\($0.vue)" } ?? "sans bandeau"), \(m.resolution.principal), bulle \(m.resolution.pastille.map { "\($0)" } ?? "aucune"))")
            // Réglages Système : l'îlot suit (CoreAudio prévient ; ici le faux micro prévient de même)
            let n0 = faux.commandes.count
            faux.depuisLeSysteme(coupe: true); attendre(0.6)
            verifier(m.microCoupe && m.resolution.principal == .microCompact && m.bandeau == nil && faux.commandes.count == n0, "coupé dans Réglages Système : l'îlot le montre, sans bandeau ni commande")
            faux.depuisLeSysteme(coupe: false); attendre(0.3)
            verifier(!m.microCoupe && m.courante == .microOuvert, "rouvert dans Réglages Système : « Micro ouvert »")
            attendre(1.6)
            // la dictée rouvre le micro le temps de dicter, puis le recoupe ; aucun bandeau pour ça
            c.basculerLeMicro(); attendre(0.6)
            let n1 = faux.commandes.count
            occ.dictee = true; c.dicteeChange(enCours: true)
            verifier(Array(faux.commandes.dropFirst(n1)) == ["rouvrir"] && !faux.coupe, "fn tenue pendant que c'est coupé : le micro est rouvert tout de suite, avant la capture")
            c.occupationChangee(); attendre(0.6)
            verifier(m.cache && m.bandeau == nil, "pendant la dictée : l'îlot est effacé, aucun « Micro ouvert » (l'écho est ignoré)")
            occ.dictee = false; c.dicteeChange(enCours: false)
            verifier(Array(faux.commandes.dropFirst(n1)) == ["rouvrir", "couper"] && faux.coupe, "fn relâchée : le micro est recoupé")
            c.occupationChangee(); attendre(0.9)
            verifier(m.microCoupe && m.resolution.principal == .microCompact && m.bandeau == nil, "après la dictée : « Coupé » de nouveau, aucun bandeau")
            // dictée éclair : les deux notifications arrivent après coup, relues telles qu'est le micro (coupé) : rien ne bouge
            c.dicteeChange(enCours: true); c.dicteeChange(enCours: false); attendre(0.4)
            verifier(faux.coupe && m.microCoupe && m.bandeau == nil, "dictée éclair (notifications en retard) : toujours coupé, pas de faux « Micro ouvert »")
            // la dictée écoute un autre micro : on ne rouvre pas celui que l'appel entend
            faux.memeMicroQueLaDictee = false
            let n2 = faux.commandes.count
            c.dicteeChange(enCours: true); c.dicteeChange(enCours: false); attendre(0.3)
            verifier(faux.commandes.count == n2 && faux.coupe, "dictée sur un autre micro : celui-ci reste coupé")
            faux.memeMicroQueLaDictee = true
            // le raccourci, sur des touches fabriquées (jamais envoyées) : « m » selon la disposition du clavier de ce Mac
            let src = CGEventSource(stateID: .privateState)
            func touche(_ code: CGKeyCode, _ f: CGEventFlags) -> CGEvent? { let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true); e?.flags = f; return e }
            if let codeM = (0..<128).map({ CGKeyCode($0) }).first(where: { touche($0, []).flatMap { NSEvent(cgEvent: $0)?.charactersIgnoringModifiers } == "m" }),
               let codeA = (0..<128).map({ CGKeyCode($0) }).first(where: { touche($0, []).flatMap { NSEvent(cgEvent: $0)?.charactersIgnoringModifiers } == "a" }) {
                let r = RaccourciIlot.microParDefaut
                verifier(touche(codeM, [.maskControl, .maskAlternate]).map { KeyMonitor.correspond($0, a: r) } == true, "⌃⌥M (touche \(codeM) sur ce clavier) : reconnu")
                verifier(touche(codeM, [.maskControl]).map { KeyMonitor.correspond($0, a: r) } == false
                         && touche(codeM, [.maskControl, .maskAlternate, .maskCommand]).map { KeyMonitor.correspond($0, a: r) } == false
                         && touche(codeA, [.maskControl, .maskAlternate]).map { KeyMonitor.correspond($0, a: r) } == false
                         && touche(codeM, []).map { KeyMonitor.correspond($0, a: r) } == false, "⌃M, ⌃⌥⌘M, ⌃⌥A, m seul : pas le raccourci")
            } else { verifier(false, "touche « m » introuvable sur ce clavier") }
            // un micro qui ne se coupe pas : l'îlot reste sur ce qui est vrai
            c.basculerLeMicro(); attendre(1.8)
            verifier(!m.microCoupe && m.bandeau == nil, "rouvert (raccourci), bandeau parti")
            faux.reglable = false
            c.basculerLeMicro(); attendre(0.6)
            verifier(!m.microCoupe && m.resolution.principal == .lectureCompact && m.bandeau == nil, "micro qui refuse d'être coupé : l'îlot ne ment pas")
            faux.reglable = true
            // réglage éteint : plus d'écoute ; le micro reste comme il est
            c.basculerLeMicro(); attendre(0.6)
            c.activerLeMicro(false); attendre(0.6)
            verifier(!faux.actif && !m.microCoupe && m.resolution.principal == .lectureCompact, "réglage éteint : l'îlot ne montre plus le micro")
            let n3 = faux.commandes.count
            c.basculerLeMicro(); faux.depuisLeSysteme(coupe: false); attendre(0.4)
            verifier(faux.commandes.count == n3 && m.bandeau == nil, "réglage éteint : le raccourci et CoreAudio ne font plus rien")
            attendre(1.2) { m.boucleActive }
            verifier(!m.boucleActive, "micro : tout est posé, aucune boucle d'animation")
        }

        // --- volume et luminosité : un son et un écran FACTICES (jamais CoreAudio ni DisplayServices, jamais de son) ; les touches sont
        // de vrais événements « systemDefined » fabriqués et décodés comme dans l'écoute du clavier, jamais envoyés au système
        do {
            let faux = NiveauxFactices()
            c.niveaux = faux
            c.niveauxActifs = true
            attendre(1.8) { m.bandeau != nil }
            verifier(m.resolution.principal == .lectureCompact && m.bandeau == nil, "au départ : la vidéo a l'îlot")
            /// Une touche passée par le même chemin que l'écoute du clavier ; vrai = avalée.
            func touche(_ t: ToucheNiveau, enfoncee: Bool = true, repetition: Bool = false, _ f: CGEventFlags = []) -> Bool {
                let d1 = EvenementNiveau(touche: t, enfoncee: enfoncee, repetition: repetition).data1
                guard let ns = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                                                  subtype: Int16(EvenementNiveau.sousTypeTouches), data1: d1, data2: -1),
                      let cg = ns.cgEvent else { verifier(false, "événement systemDefined impossible à fabriquer"); return false }
                cg.flags = f
                guard let e = KeyMonitor.evenementNiveau(cg) else { verifier(false, "événement fabriqué illisible (data1 \(d1))"); return false }
                return c.toucheNiveau(e, option: cg.flags.contains(.maskAlternate), maj: cg.flags.contains(.maskShift),
                                      controle: cg.flags.contains(.maskControl), commande: cg.flags.contains(.maskCommand))
            }
            func appuyer(_ t: ToucheNiveau, _ f: CGEventFlags = []) -> (bas: Bool, haut: Bool) { let b = touche(t, f); let h = touche(t, enfoncee: false, f); return (b, h) }
            // volume + : avalé, appliqué, montré dans l'îlot (la barre part de l'ancienne valeur)
            let p1 = touche(.volumePlus)
            verifier(p1 && faux.son.valeur == 0.5625 && faux.ecritures == ["volume 0.5625"], "volume + : avalé, volume 0,5 → 0,5625 (un cran de 1/16)")
            verifier(m.bandeau?.vue == .volume && m.jaugeVolume.x == 0.5 && m.jaugeVolume.cible == 0.5625, "la barre part de 0,5 et vise 0,5625 sur son ressort")
            verifier(touche(.volumePlus, enfoncee: false), "relâchement : avalé aussi")
            attendre(0.7)
            verifier(m.courante == .volume && m.resolution.pastille == nil && m.niveauVu(.volume).symbole == "speaker.wave.2.fill",
                     "l'îlot montre le haut-parleur (deux ondes) et la barre ; la vidéo ne saute pas dans la bulle")
            verifier(m.trace.bande <= Double(m.demiCamera) + GeoIlot.aileMax + 0.01 && abs(m.trace.hauteur - Double(g.hauteur)) < 0.01,
                     "volume : dans les ailes, \(Int(m.trace.bande - Double(m.demiCamera))) pt de chaque côté de la caméra (≤ 66), rien sous la barre")
            let cou = Double(m.grille.cou(.volume) - m.demiCamera)
            let barre = JaugeNiveau.barre(demiCamera: Double(m.demiCamera), cou: cou)
            verifier(barre.largeur >= 40 && barre.x + barre.largeur <= Double(m.demiCamera) + cou - 8 + 0.01,
                     "la barre (\(Int(barre.largeur)) pt) tient dans l'aile droite, à 8 pt du bord")
            let hp = MesureIlot.symbole("speaker.wave.3.fill", 15), soleil = MesureIlot.symbole("sun.max.fill", 15)
            verifier(hp <= CGFloat(cou) - 16 && soleil <= CGFloat(cou) - 16, "haut-parleur (\(Int(hp)) pt) et soleil (\(Int(soleil)) pt) tiennent dans l'aile gauche (\(Int(cou) - 16) pt)")
            // touche tenue : une répétition toutes les 83 ms (le réglage par défaut de macOS), la barre suit d'un seul mouvement
            let n0 = faux.ecritures.count
            _ = touche(.volumePlus)
            var boucle = false
            for _ in 0..<5 { attendre(0.083); boucle = boucle || m.boucleActive; _ = touche(.volumePlus, repetition: true) }
            let derniere = Date()
            _ = touche(.volumePlus, enfoncee: false)
            verifier(faux.ecritures.count == n0 + 6 && faux.son.valeur == 0.9375 && m.jaugeVolume.cible == 0.9375 && boucle,
                     "touche tenue : 6 crans (0,5625 → 0,9375), la barre suit sur son ressort")
            verifier(m.niveauVu(.volume).symbole == "speaker.wave.3.fill", "trois ondes au-dessus des deux tiers")
            for _ in 0..<4 { _ = appuyer(.volumePlus) }
            verifier(faux.son.valeur == 1, "plus haut que 1 : non, borné")
            // reste 1,5 s après la DERNIÈRE touche, puis la vidéo revient
            attendre(max(0, 1.3 - Date().timeIntervalSince(derniere)))
            verifier(m.bandeau?.vue == .volume, "1,3 s après la dernière touche : encore là")
            attendre(0.6)
            verifier(m.bandeau == nil && m.resolution.principal == .lectureCompact, "1,9 s après : il se retire, la vidéo revient")
            // muet : une seule bascule, même tenue ; barre vide, haut-parleur barré
            let mu = touche(.muet); _ = touche(.muet, repetition: true); _ = touche(.muet, repetition: true); _ = touche(.muet, enfoncee: false)
            verifier(mu && faux.son.muet && faux.son.valeur == 1 && m.niveauVu(.volume).symbole == "speaker.slash.fill" && m.jaugeVolume.cible == 0,
                     "muet (tenu) : une seule bascule, haut-parleur barré, barre vide, le volume est gardé")
            _ = appuyer(.volumeMoins)
            verifier(!faux.son.muet && faux.son.valeur == 0.9375, "volume − sur un son coupé : le son revient, un cran plus bas")
            // ⌥⇧ : petits pas ; ⌥ seul : macOS (il ouvre les réglages Son)
            let fin = appuyer(.volumeMoins, [.maskAlternate, .maskShift])
            verifier(fin.bas && fin.haut && faux.son.valeur == 0.921875, "⌥⇧ volume − : un quart de cran (1/64)")
            let n1 = faux.ecritures.count
            let opt = appuyer(.volumeMoins, [.maskAlternate])
            verifier(!opt.bas && !opt.haut && faux.ecritures.count == n1, "⌥ seul : laissé à macOS (réglages Son), rien n'est réglé")
            // luminosité, puis le volume aussitôt : l'un remplace l'autre
            let l1 = appuyer(.luminositePlus)
            attendre(0.5)
            verifier(l1.bas && l1.haut && faux.lumiere.valeur == 0.3125 && m.courante == .luminosite && m.niveauVu(.luminosite).symbole == "sun.max.fill"
                     && m.jaugeLuminosite.cible == 0.3125, "luminosité + : 0,3 → 0,3125, le soleil et sa barre")
            // la forme posée (le glissement de 44 à 60 pt peut dépasser d'un centième de point pendant qu'il se pose, comme le micro coupé)
            verifier(m.traceCible.bande <= Double(m.demiCamera) + GeoIlot.aileMax + 0.01, "luminosité : la forme visée tient dans les ailes (≤ 66 pt)")
            attendre(1.0) { !m.geo.allSatisfy(\.fini) }
            verifier(m.trace.bande <= Double(m.demiCamera) + GeoIlot.aileMax + 0.01, "luminosité, posée : \(String(format: "%.1f", m.trace.bande - Double(m.demiCamera))) pt de chaque côté de la caméra (≤ 66)")
            _ = appuyer(.volumeMoins); attendre(0.5)
            verifier(m.courante == .volume && m.jaugeLuminosite.x == 0.3125, "volume juste après : le volume remplace la luminosité, chaque barre garde sa valeur")
            attendre(1.7) { m.bandeau != nil }
            attendre(1.2) { m.boucleActive }
            verifier(!m.boucleActive && m.resolution.principal == .lectureCompact, "tout est posé : aucune boucle d'animation (bouge encore : \(m.ceQuiBouge))")
            // ce qui reste à macOS : sortie HDMI, DisplayServices absent, réglage éteint, dictée en cours
            let n2 = faux.ecritures.count
            faux.volumeReglable = false
            let hdmi = appuyer(.volumePlus)
            faux.volumeReglable = true; faux.muetPossible = false
            let sansMuet = appuyer(.muet)
            faux.muetPossible = true; faux.luminositeDisponible = false
            let sansEcran = appuyer(.luminositeMoins)
            faux.luminositeDisponible = true
            verifier(!hdmi.bas && !hdmi.haut && !sansMuet.bas && !sansEcran.bas && !sansEcran.haut && faux.ecritures.count == n2 && m.bandeau == nil,
                     "sortie HDMI, sortie sans muet, DisplayServices absent : les touches restent à macOS, l'îlot ne bouge pas")
            c.niveauxActifs = false
            let eteint = appuyer(.volumePlus)
            c.niveauxActifs = true
            verifier(!eteint.bas && !eteint.haut && faux.ecritures.count == n2, "réglage éteint : rien n'est avalé")
            occ.dictee = true; c.occupationChangee(); attendre(0.3)
            let dictee = appuyer(.volumePlus)
            verifier(m.cache && !dictee.bas && faux.ecritures.count == n2 && m.bandeau == nil, "pendant la dictée : la touche reste à macOS, rien n'attend la fin")
            // tenue au moment où la dictée commence : la suite est avalée sans rien faire, jusqu'au relâchement
            occ.dictee = false; c.occupationChangee(); attendre(0.5)
            _ = touche(.volumePlus)
            occ.dictee = true; c.occupationChangee()
            let n3 = faux.ecritures.count
            let rep = touche(.volumePlus, repetition: true), haut = touche(.volumePlus, enfoncee: false)
            verifier(rep && haut && faux.ecritures.count == n3, "touche tenue quand la dictée commence : répétitions et relâchement avalés, rien de réglé")
            occ.dictee = false; c.occupationChangee(); attendre(0.3)
            // « Réduire les animations » : la barre saute à sa place
            m.reduire = true
            _ = appuyer(.volumeMoins)
            verifier(m.jaugeVolume.fini && m.jaugeVolume.x == faux.son.valeur, "« Réduire les animations » : la barre est posée tout de suite")
            m.reduire = false
            attendre(1.8) { m.bandeau != nil }
            attendre(1.2) { m.boucleActive }
            verifier(!m.boucleActive && m.bandeau == nil, "volume et luminosité : fini, aucune boucle d'animation")
        }

        // --- Claude au travail : le VRAI script (celui que Verbe écrit) lancé comme Claude Code le lance, sur un dossier temporaire et
        // un settings.json temporaire (jamais ~/.claude) ; l'app au premier plan est simulée et le retour au Terminal capturé (aucune app
        // n'est activée)
        do {
            let morceauAvant = c.lecture.modele.morceau
            c.lecture.modele.morceau = nil; c.lecture.surIlot(false); attendre(0.6)
            let racine = dossier.appendingPathComponent("claude", isDirectory: true)
            let inst = InstallationClaude(reglages: racine.appendingPathComponent("point-claude/settings.json"),
                                          dossierVerbe: racine.appendingPathComponent("Dictee", isDirectory: true))
            try? FileManager.default.createDirectory(at: inst.reglages.deletingLastPathComponent(), withIntermediateDirectories: true)
            let original = "{\n  \"model\": \"opus\",\n  \"hooks\": {\n    \"Stop\": [\n      {\n        \"hooks\": [\n          {\n            \"type\": \"command\",\n            \"command\": \"osascript -e 'display notification \\\"Claude a terminé\\\"' || true\"\n          }\n        ]\n      }\n    ]\n  },\n  \"theme\": \"light\"\n}\n"
            try? original.write(to: inst.reglages, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: inst.reglages.path)
            func lireReglages() -> String { (try? String(contentsOf: inst.reglages, encoding: .utf8)) ?? "" }
            func droits(_ u: URL) -> Int { (try? FileManager.default.attributesOfItem(atPath: u.path)[.posixPermissions] as? Int) ?? -1 }
            verifier((try? inst.brancher()) != nil && inst.estBranche, "« Brancher Claude Code » : nos crochets sont dans settings.json")
            let branche = lireReglages()
            verifier(branche.contains("osascript") && branche.contains("\"theme\": \"light\"") && branche.contains("\"model\": \"opus\""), "le crochet Stop déjà là, le modèle et le thème sont gardés")
            verifier((try? String(contentsOf: inst.sauvegarde, encoding: .utf8)) == original, "la copie d'avant est gardée à côté (settings.json.verbe-sauvegarde)")
            verifier(droits(inst.reglages) == 0o600 && droits(inst.script) == 0o755, "les droits de settings.json sont gardés (0600) ; le script est exécutable")
            verifier((try? inst.brancher()) != nil && lireReglages() == branche, "« Brancher » deux fois : rien en double, le fichier ne change pas")
            let commande = CrochetsClaude.commande(script: inst.script.path)
            verifier(branche.contains(JSONOrdonne.citer(commande)), "la commande écrite est le chemin du script, cité")

            // le script, lancé par /bin/sh -c avec la commande écrite dans settings.json, le JSON de Claude Code sur l'entrée
            func crochet(_ json: String, app: String? = "com.apple.Terminal") -> (sortie: String, code: Int32) {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/bin/sh")
                p.arguments = ["-c", commande]
                var env = ["PATH": "/usr/bin:/bin"]
                if let app { env["__CFBundleIdentifier"] = app }
                p.environment = env
                let entree = Pipe(), sortie = Pipe()
                p.standardInput = entree; p.standardOutput = sortie; p.standardError = sortie
                do { try p.run() } catch { return ("", -1) }
                entree.fileHandleForWriting.write(Data(json.utf8)); try? entree.fileHandleForWriting.close()
                p.waitUntilExit()
                return (String(decoding: sortie.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self), p.terminationStatus)
            }
            func ev(_ session: String, _ nom: String, _ reste: String = "") -> String {
                "{\"session_id\":\"\(session)\",\"transcript_path\":\"/Users/essai/.claude/projects/x/\(session).jsonl\",\"cwd\":\"/Users/essai/dev/dictee-mac\","
                    + "\"permission_mode\":\"default\",\"hook_event_name\":\"\(nom)\"\(reste)}"
            }
            func fichier(_ session: String) -> URL { inst.etats.appendingPathComponent(session + ".jsonl") }
            let todos = ",\"tool_name\":\"TodoWrite\",\"tool_input\":{\"todos\":[" + (1...7).map { i in
                "{\"content\":\"Tâche \(i)\",\"status\":\"\(i <= 3 ? "completed" : (i == 4 ? "in_progress" : "pending"))\",\"activeForm\":\"Écrit la tâche \(i)\"}" }.joined(separator: ",")
                + "]},\"tool_response\":{\"oldTodos\":[],\"newTodos\":[]}"

            // une session déjà là avant le lancement : relue sans rien annoncer ; la demande tapée n'est jamais écrite
            let r0 = crochet(ev("avant", "UserPromptSubmit", ",\"prompt\":\"mot-de-passe-secret 1234\""))
            let l0 = (try? String(contentsOf: fichier("avant"), encoding: .utf8)) ?? ""
            verifier(r0.code == 0 && r0.sortie.isEmpty && l0.hasSuffix("\n") && l0.components(separatedBy: "\n").count == 2, "le script : une ligne ajoutée, rien sur la sortie, code 0")
            verifier(!l0.contains("mot-de-passe-secret") && l0.contains("\"app\":\"com.apple.Terminal\"") && l0.contains("\"cwd\":\"/Users/essai/dev/dictee-mac\""),
                     "la demande tapée n'est jamais écrite ; l'app d'où vient la session et le dossier le sont")
            var premierPlan: String? = "com.google.Chrome"
            var ramenes: [String?] = []
            c.appAuPremierPlan = { premierPlan }
            c.ramenerApp = { ramenes.append($0) }
            c.claudeSource.dossier = inst.etats
            c.activerClaude(true)
            attendre(2.0) { m.claude == nil }; attendre(0.9)
            verifier(m.claude?.id == "avant" && m.bandeau == nil && m.courante == .claudeMinimal, "au lancement : la session déjà là est relue (l'étoile seule), rien d'annoncé")
            verifier(m.trace.bande <= Double(m.demiCamera) + GeoIlot.aileMax + 0.01 && abs(m.trace.hauteur - Double(g.hauteur)) < 0.01, "l'étoile seule : dans les ailes, rien sous la barre")
            _ = crochet(ev("avant", "SessionEnd", ",\"reason\":\"exit\""))
            attendre(2.0) { m.claude != nil }; attendre(0.3)
            verifier(m.claude == nil && !FileManager.default.fileExists(atPath: fichier("avant").path), "fin de session : l'îlot l'oublie, son fichier est effacé")

            // une tâche : au travail, puis la liste (« 3 sur 7 »)
            let r1 = crochet(ev("s1", "UserPromptSubmit", ",\"prompt\":\"fais les contrôles\""))
            attendre(2.0) { m.claude == nil }; attendre(0.9)
            verifier(r1.code == 0 && m.claude?.etat == .travaille && m.courante == .claudeMinimal && m.bandeau == nil, "demande envoyée : l'étoile dans l'îlot, sans annonce")
            _ = crochet(ev("s1", "PostToolUse", todos))
            attendre(2.0) { m.claude?.progres == nil }; attendre(0.9)
            verifier(m.claude?.progres == ProgresClaude(faites: 3, total: 7) && m.courante == .claudeCompact, "la liste de tâches : l'anneau et « 3 sur 7 »")
            let aile = m.grille.bordAile(.claudeCompact) - m.demiCamera - 4
            verifier(m.texteClaude(m.claude) == "3 sur 7" && MesureIlot.texte("3 sur 7", 13, .semibold, chiffres: true) <= aile && MesureIlot.texte("Attend", 13, .semibold, chiffres: true) <= aile,
                     "« 3 sur 7 » (\(Int(MesureIlot.texte("3 sur 7", 13, .semibold, chiffres: true))) pt) et « Attend » tiennent dans l'aile (\(Int(aile)) pt)")
            verifier(m.trace.bande <= Double(m.demiCamera) + GeoIlot.aileMax + 0.01 && abs(m.trace.hauteur - Double(g.hauteur)) < 0.01,
                     "« 3 sur 7 » : \(Int(m.trace.bande - Double(m.demiCamera))) pt de chaque côté de la caméra (≤ 66), rien sous la barre")
            attendre(1.2) { m.boucleActive }
            verifier(!m.boucleActive, "Claude au travail, posé : aucune boucle d'animation (bouge encore : \(m.ceQuiBouge))")
            // un outil quelconque : une ligne courte, jamais son contenu (même s'il cite « session_id »)
            _ = crochet(ev("s1", "PostToolUse", ",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"/x.swift\",\"content\":\"let session_id = \\\"piege\\\" // contenu-du-fichier\"},\"tool_response\":{}"))
            let l1 = (try? String(contentsOf: fichier("s1"), encoding: .utf8)) ?? ""
            verifier(!l1.contains("contenu-du-fichier") && l1.contains("\"tool_name\":\"Write\"") && !FileManager.default.fileExists(atPath: fichier("piege").path),
                     "un outil qui écrit un fichier : une ligne courte, sans le contenu ; le « session_id » cité dans le contenu ne trompe pas le script")
            // survol : le projet, où il en est, « Ouvrir » ; vrai clic
            c.panneau.simulerPointeur(forme: true); attendre(0.9)
            verifier(m.courante == .claudeEtendu && m.trace.bande <= Double(m.demiCamera) + GeoIlot.aileMax + 0.01, "survol : le déplié ; cou étroit dans la barre")
            let ce = m.contenuAnnonce(.claudeEtendu)
            verifier(ce?.l1 == "dictee-mac" && ce?.l2 == "3 sur 7 \u{00B7} Écrit la tâche 4", "le projet, « 3 sur 7 · Écrit la tâche 4 » (\(ce?.l2 ?? "rien"))")
            let lc = m.contenus[.claudeEtendu] ?? 0
            verifier(lc > 150 && lc <= 2 * m.grille.corps(.claudeEtendu) - 2 * GrilleIlot.marge + 0.5, "le déplié épouse son contenu (\(Int(lc)) pt)")
            let z = m.grille.zoneAnnonce(.claudeEtendu)
            let pb = CGPoint(x: z.maxX - MesureIlot.bouton(ContenuAnnonce.Bouton(titre: "Ouvrir")) / 2, y: z.midY)
            c.panneau.envoyerSouris(.leftMouseDown, en: pb); attendre(0.06); c.panneau.envoyerSouris(.leftMouseUp, en: pb)
            c.panneau.simulerPointeur(forme: false); attendre(0.6)
            verifier(ramenes == ["com.apple.Terminal"] && m.courante == .claudeCompact, "vrai clic sur « Ouvrir » : le Terminal de la session est ramené (capturé), l'îlot se replie")
            // une autorisation à donner : « Claude attend ta réponse »
            _ = crochet(ev("s1", "Notification", ",\"message\":\"Claude needs your permission to use Bash\",\"notification_type\":\"permission_prompt\""))
            attendre(2.0) { m.bandeau == nil }; attendre(0.3)
            verifier(m.courante == .claudeAttend && m.bandeauVu?.ligne1 == "Claude attend ta réponse" && m.bandeauVu?.ligne2 == "dictee-mac", "notification : « Claude attend ta réponse », le projet")
            verifier(m.trace.bande <= Double(m.demiCamera) + GeoIlot.aileMax + 0.01 && m.trace.hauteur > Double(g.hauteur) + 60, "bandeau : sous la barre, cou étroit")
            attendre(5.0) { m.bandeau != nil }; attendre(0.9)
            verifier(m.bandeau == nil && m.courante == .claudeCompact && m.texteClaude(m.claude) == "Attend", "4,5 s plus tard : « Attend » dans l'aile")
            _ = crochet(ev("s1", "PostToolUse", ",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"},\"tool_response\":{}"))
            attendre(2.0) { m.claude?.etat == .attend }; attendre(0.3)
            verifier(m.claude?.etat == .travaille && m.texteClaude(m.claude) == "3 sur 7", "autorisé, l'outil a tourné : de nouveau « 3 sur 7 »")
            // fini, Terminal au premier plan : rien à annoncer
            premierPlan = "com.apple.Terminal"
            _ = crochet(ev("s1", "Stop", ",\"stop_hook_active\":false"))
            attendre(2.0) { m.claude != nil }; attendre(0.9)
            verifier(m.claude == nil && m.bandeau == nil && m.courante == .repos, "fini pendant que le Terminal est au premier plan : rien d'annoncé, l'îlot se vide")
            // fini, Hugues ailleurs : « Terminé », 3 s
            premierPlan = "com.google.Chrome"
            _ = crochet(ev("s1", "UserPromptSubmit", ",\"prompt\":\"encore\""))
            attendre(2.0) { m.claude == nil }
            _ = crochet(ev("s1", "Stop", ",\"stop_hook_active\":false"))
            attendre(2.0) { m.bandeau == nil }; attendre(0.3)
            verifier(m.courante == .claudeTermine && m.bandeauVu?.ligne1 == "Terminé" && m.bandeauVu?.ligne2 == "dictee-mac" && m.claude == nil, "fini pendant que Hugues est ailleurs : « Terminé », coche verte, le projet")
            c.agir(.claudeOuvrir(m.bandeauVu?.claude?.app)); attendre(0.3)
            verifier(ramenes.last == "com.apple.Terminal" && m.bandeau == nil, "« Ouvrir » sur « Terminé » : le Terminal est ramené, le bandeau se retire")
            _ = crochet(ev("s1", "UserPromptSubmit")); attendre(2.0) { m.claude == nil }
            _ = crochet(ev("s1", "Stop")); attendre(2.0) { m.bandeau == nil }
            attendre(3.6) { m.bandeau != nil }; attendre(0.5)
            verifier(m.bandeau == nil && m.courante == .repos, "sans geste : « Terminé » se retire après 3 s")
            _ = crochet(ev("s1", "Notification", ",\"message\":\"Claude is waiting for your input\",\"notification_type\":\"idle_prompt\""))
            attendre(1.2)
            verifier(m.bandeau == nil && m.claude == nil, "le rappel d'inactivité de Claude Code après la fin : rien")
            // pendant une vidéo : Claude au travail dans la bulle ; Claude qui attend prend l'îlot, la vidéo passe en bulle
            c.lecture.modele.morceau = MorceauEnCours(titre: "Album · Titre 3", app: "essai.lecture", joue: true, duree: 214, position: 97)
            c.lecture.surIlot(true)
            _ = crochet(ev("s1", "UserPromptSubmit")); attendre(2.0) { m.claude == nil }; attendre(0.9)
            verifier(m.resolution.principal == .lectureCompact && m.pastille == .claude && m.rectPastille() != nil, "pendant une vidéo : la vidéo garde l'îlot, Claude dans la bulle à côté")
            _ = crochet(ev("s1", "Notification", ",\"notification_type\":\"permission_prompt\""))
            attendre(2.0) { m.bandeau == nil }; attendre(5.0) { m.bandeau != nil }; attendre(0.9)
            verifier(m.resolution.principal == .claudeCompact && m.pastille == .lecture, "Claude attend une réponse : il prend l'îlot, la vidéo passe en bulle")
            _ = crochet(ev("s1", "PostToolUse", ",\"tool_name\":\"Read\""))
            attendre(2.0) { m.claude?.etat == .attend }; attendre(0.9)
            verifier(m.resolution.principal == .lectureCompact && m.pastille == .claude, "répondu : la vidéo reprend l'îlot")
            // réglage éteint : plus rien n'est lu
            c.activerClaude(false); attendre(0.6)
            verifier(!c.claudeSource.actif && m.claude == nil && m.resolution.pastille == nil, "réglage éteint : l'îlot oublie Claude")
            _ = crochet(ev("s2", "UserPromptSubmit")); attendre(1.2)
            verifier(m.claude == nil, "réglage éteint : une nouvelle session n'est pas montrée")
            // débrancher : le fichier de départ, à l'octet près
            verifier((try? inst.debrancher()) != nil && !inst.estBranche && lireReglages() == original, "« Débrancher » : settings.json redevient exactement celui d'avant")
            c.lecture.modele.morceau = morceauAvant; c.lecture.surIlot(morceauAvant != nil)
            attendre(1.5) { m.boucleActive }
            verifier(!m.boucleActive, "Claude : tout est posé, aucune boucle d'animation")
        }

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
