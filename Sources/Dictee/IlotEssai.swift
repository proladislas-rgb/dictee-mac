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
        // ligne par ligne : un arrêt brutal ne perd pas les dernières lignes du compte rendu
        setvbuf(stdout, nil, _IOLBF, 0)
        var echecs = 0
        func verifier(_ ok: Bool, _ nom: String) { print(ok ? "  ok   \(nom)" : "  ÉCHEC \(nom)"); if !ok { echecs += 1 } }
        func attendre(_ s: Double, tant: () -> Bool = { true }) {
            let fin = Date().addingTimeInterval(s)
            while Date() < fin, tant() { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
        }
        let dossier = FileManager.default.temporaryDirectory.appendingPathComponent("verbe-ilot-essai-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dossier) }
        // le journal de l'essai (dossiers refusés, introuvables…) va dans le dossier temporaire, jamais dans ~/Library/Logs/Dictee
        Log.url = dossier.appendingPathComponent("dictee-essai.log")
        Log.ecrire("essai : journal temporaire"); Log.vider()
        verifier(!Log.url.path.contains("/Library/Logs/") && ((try? String(contentsOf: Log.url, encoding: .utf8)) ?? "").contains("essai : journal temporaire"),
                 "le journal de l'essai va dans un fichier temporaire, jamais dans le vrai journal")
        let fichier = dossier.appendingPathComponent("rappels.json")

        var decalage = 0.0
        var compteurs = (minuteur: 0, rappel: 0, doux: 0, silence: 0)
        var liensOuverts: [URL] = []
        var finder: [[URL]] = []
        var notes = 0
        var pressePapiers: [String] = []
        var fenetres: [Onglet] = []
        var ecransRallumes = 0
        func fabriquer() -> IlotControleur {
            // l'étagère et la bibliothèque aussi dans le dossier temporaire : jamais le vrai etagere.json ni le vrai bibliotheque.json ; les
            // sources de la bibliothèque lisent des dossiers temporaires (jamais Téléchargements ni le Bureau), sans toucher aux réglages
            let bib = BibliothequeModele(store: BibliothequeStore(url: dossier.appendingPathComponent("bibliotheque.json")), sources: [])
            bib.dossiers = DossiersBibliotheque(telechargements: dossier.appendingPathComponent("bibliotheque/Téléchargements", isDirectory: true),
                                                captures: dossier.appendingPathComponent("bibliotheque/Captures", isDirectory: true))
            bib.reglerSources = { _ in }
            // les fichiers des dossiers d'essai sont datés par leur date de création (posée par l'essai), pas par leur arrivée dans le dossier
            bib.lireDossiers = { s, d in SourcesBibliotheque.lire(s, dossiers: d).map { e in
                var x = e; if let c = try? FileManager.default.attributesOfItem(atPath: e.chemin)[.creationDate] as? Date { x.date = c }; return x } }
            // le réveil aussi dans le dossier temporaire (jamais le vrai reveil.json), l'écran jamais rallumé ; le calendrier jamais demandé ni lu
            // les notes rapides aussi (jamais le vrai notes.json)
            let c = IlotControleur(stockage: RappelsStore(url: fichier), etagere: EtagereStore(url: dossier.appendingPathComponent("etagere.json")),
                                   notes: NotesStore(url: dossier.appendingPathComponent("notes.json")), bibliotheque: bib,
                                   reveil: ReveilStore(url: dossier.appendingPathComponent("reveil.json")))
            // les Outils : jamais la vraie veille, le vrai presse-papiers, Groq, l'Accessibilité ni l'app Notes
            c.eveilPilote = EveilFactice()
            c.pressePapiers = PressePapiersFactice()
            c.surCommandeV = { false }
            c.reformulerTexte = { _, _ in throw GroqErreur.pasDeCle }
            c.lireSelection = { nil }
            c.selectionnerDansLApp = { _ in false }
            c.lireAppDerniereDictee = { nil }
            c.envoyerNoteVersNotes = { _, fini in fini(false) }
            c.reglagesCentre.dispositionOutils = { nil }
            c.reglagesCentre.enregistrerDispositionOutils = { _ in }
            c.allumerEcran = { ecransRallumes += 1 }
            c.statutCalendrier = { .nonDemande }
            c.demanderCalendrier = { false }
            c.lireEvenements = { _ in [] }
            c.reglagesCentre.calendrier = { false }
            c.reglagesCentre.reglerCalendrier = { _ in }
            c.reglagesCentre.nouveautes = { [] }
            c.reglagesCentre.marquerNouveautes = { _ in }
            c.reglagesCentre.disposition = { nil }
            c.reglagesCentre.enregistrerDisposition = { _ in }
            // Groq : jamais le vrai usage ni la vraie reconnaissance du Mac
            c.lireEtatGroq = { t in EtatGroq.calculer(CompteurGroq(), modele: ModeleWhisper.precis.identifiant, secours: ModeleWhisper.rapide.identifiant, a: t) }
            c.lireProgressionParole = { nil }
            c.maintenant = { Date().addingTimeInterval(decalage) }
            c.sons = IlotControleur.SonsIlot(minuteurFini: { compteurs.minuteur += 1 }, rappel: { compteurs.rappel += 1 }, doux: { compteurs.doux += 1 }, silencieux: { compteurs.silence += 1 },
                                             reveil: { compteurs.minuteur += 1 })
            c.ouvrir = { liensOuverts.append($0) }
            c.montrer = { finder.append($0) }
            c.surNoter = { _ in notes += 1 }
            c.panneau.invisible = true
            c.lireMicros = { [] }
            c.lireDerniereDictee = { nil }   // jamais le vrai historique
            // la carte Dictées : un historique factice en mémoire (jamais le vrai fichier), un presse-papiers factice, la fenêtre capturée
            c.moteur.dictees.source = { HistoriqueStore(enMemoire: IlotEssai.dicteesFactices(courtes: true, maintenant: c.maintenant())) }
            c.copier = { pressePapiers.append($0) }
            c.surOuvrirFenetre = { fenetres.append($0) }
            c.lecture.essaiInvisible = true
            // l'étagère plus rapide : jamais de vrai AirDrop, ni le vrai dossier des captures, ni les vrais réglages
            c.envoyerParAirDrop = { urls, fin in EssaiEtagere.envois.append(urls); EssaiEtagere.finEnvoi = fin; return EssaiEtagere.airDropPossible }
            c.appSous = { _ in EssaiEtagere.app }
            c.dossierCaptures = { dossier.appendingPathComponent("Captures", isDirectory: true) }
            c.dossierCapturesGlissees = { dossier.appendingPathComponent("TemporaryItems", isDirectory: true) }
            c.estUneCapture = { IlotControleur.estUneCapture($0, prefixe: nil) }
            c.reglagesCentre.captures = { EssaiEtagere.captures }
            c.reglagesCentre.reglerCaptures = { EssaiEtagere.captures = $0 }
            // l'app Rappels : jamais EventKit ni une vraie fenêtre d'autorisation ; les réglages des rappels et de la question, simulés
            c.rappelsApple = RappelsAppleFactice()
            // la Concentration : jamais la vraie app Raccourcis (rien de créé, signé, ouvert ni lancé), jamais le vrai fichier
            c.concentration.systeme = RaccourcisFactices().systeme
            c.concentration.store = ConcentrationStore(url: dossier.appendingPathComponent("concentration.json"))
            c.concentration.dossierTemporaire = dossier
            IlotEssai.reglagesLucarneDEssai(c)
            IlotEssai.systemeLucarneDEssai(c)
            c.vignetteSysteme = ReglageVignette(lire: { EssaiEtagere.vignette }, ecrire: { EssaiEtagere.vignette = $0 },
                                                memoire: { EssaiEtagere.vignetteAvant }, retenir: { EssaiEtagere.vignetteAvant = $0 })
            return c
        }
        // un glisser qui PART de l'îlot n'est jamais remis au système (il prendrait la vraie souris) : l'essai le reçoit
        VueSourceFichiers.essai = { urls, fin in EssaiEtagere.glisses.append(urls); EssaiEtagere.finGlisser = fin }
        CadenceEcran.minuterieSeulement = true
        let c = fabriquer()
        c.panneau.demarrer()
        let m = c.moteur
        let g = m.geometrie
        print("caméra : \(Int(g.largeur)) × \(Int(g.hauteur)) pt")

        // une section seule (pour la mettre au point sans attendre tout l'essai) : `DICTEE_ESSAI_SEUL=bibliotheque` (ou `reveil`, `places`, `places-survol`), ou
        // `--ilot-essai --seulement=survol` (le survol des Dictées, pour mesurer vite ; l'essai complet la joue aussi)
        let seul = CommandLine.arguments.contains("--seulement=survol") ? "survol" : ProcessInfo.processInfo.environment["DICTEE_ESSAI_SEUL"]
        if let seul, ["bibliotheque", "reveil", "survol", "places", "places-survol", "concentration"].contains(seul) {
            attendre(0.4)
            if seul == "bibliotheque" {
                IlotEssai.bibliotheque(c, dossier: dossier, verifier: verifier, attendre: { attendre($0, tant: $1) },
                                       fenetres: { fenetres }, relancer: { fabriquer() })
            } else if seul == "places" || seul == "places-survol" {
                IlotEssai.placesLucarne(c, verifier: verifier, attendre: { attendre($0, tant: $1) })
                IlotEssai.verreLucarne(c, verifier: verifier, attendre: { attendre($0, tant: $1) })
                // `places-survol` : le survol des Dictées juste après (comme dans l'essai complet) : la Lucarne revenue dans l'encoche ne
                // doit rien laisser qui alourdisse l'îlot
                if seul == "places-survol" { IlotEssai.survolDictees(c, verifier: verifier, attendre: { attendre($0, tant: $1) }) }
            } else if seul == "concentration" {
                IlotEssai.concentration(c, dossier: dossier, decaler: { decalage += $0 }, verifier: verifier, attendre: { attendre($0, tant: $1) }, relancer: { fabriquer() })
            } else if seul == "reveil" {
                IlotEssai.reveilEtCalendrier(c, dossier: dossier, verifier: verifier, attendre: { attendre($0, tant: $1) }, relancer: { fabriquer() })
            } else {
                IlotEssai.survolDictees(c, verifier: verifier, attendre: { attendre($0, tant: $1) })
            }
            c.arreter()
            print(echecs == 0 ? "essai terminé : tout est vert" : "essai terminé : \(echecs) échec(s)")
            return echecs == 0 ? 0 : 1
        }
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
        // la hauteur (0,48 s, amortissement 0,75 : un petit rebond) n'est posée, à 0,01 pt et 0,05 pt/s près, qu'au bout de 1,05 s
        // d'animation ; la boucle démarre APRÈS que SwiftUI a construit la carte dépliée (19 ms Mac au calme, 34 à 44 ms Mac occupé,
        // mesuré le 12/11). Ce contrôle tombait ≈ 1,08 s après le dépliage : 10 ms de marge, il échouait dès que le Mac était occupé
        // (déjà le 12/11 à 3 h 34, avant les fusions). On attend la fin de la boucle, 0,25 s au plus : une boucle qui ne s'arrête
        // pas, ou un dépliage qui tarde vraiment, échoue toujours.
        let attente0 = Date()
        attendre(0.25) { m.boucleActive }
        verifier(!m.boucleActive, "îlot déplié et posé : plus de boucle (les ressorts sont arrivés \(Int(Date().timeIntervalSince(attente0) * 1000)) ms plus tard ; bouge encore : \(m.ceQuiBouge))")
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

        // --- appui long sur la lecture : il déplace la Lucarne (plus de rangée Minuteur, le minuteur se lance du Centre) ; vrais événements
        // souris remis à la fenêtre (la vue d'hébergement lit leur point, le geste SwiftUI dit « sur la forme »)
        let milieu = CGPoint(x: 0, y: g.hauteur / 2)
        c.panneau.envoyerSouris(.leftMouseDown, en: milieu); attendre(0.08); c.panneau.envoyerSouris(.leftMouseUp, en: milieu); attendre(0.9)
        verifier(m.courante == .lectureEtendu, "vrai clic court sur la lecture : elle se déplie (comme avant)")
        m.boutonEnfonce = { true }
        let sousBarre = CGPoint(x: 0, y: g.hauteur + 10)
        c.panneau.envoyerSouris(.leftMouseDown, en: sousBarre); attendre(0.2)
        verifier(m.presse && m.anneauAppui != nil, "pendant l'appui : l'îlot gonfle sous le doigt, l'anneau se remplit")
        attendre(0.4)
        verifier(m.lucarne.geste.phase == .decollee && !m.fenetreOuverte && m.courante != .lectureMinuteur && !m.presse,
                 "vrai appui long (0,6 s) sur la lecture dépliée : elle se range (plus de rangée Minuteur)")
        // la Lucarne attend que l'encoche soit repliée pour se décoller (jamais de capsule de la largeur du corps sur la barre des menus)
        attendre(1.0) { m.lucarne.repli }
        verifier(m.lucarne.geste.phase == .decollee && m.lucarne.libre, "… puis, l'encoche repliée, la Lucarne se décolle")
        c.panneau.envoyerSouris(.leftMouseUp, en: sousBarre); attendre(1.0)
        m.boutonEnfonce = { NSEvent.pressedMouseButtons & 1 != 0 }
        verifier(!m.lucarne.libre && m.lucarne.place == .encoche && m.courante == .lectureCompact && !m.boucleActive,
                 "relâchée tout près : aspirée dans l'encoche, la lecture en compact, plus de boucle")
        // appui puis glissé de 10 pt avant 0,4 s : ni clic ni décollage
        c.panneau.envoyerSouris(.leftMouseDown, en: milieu); attendre(0.1)
        c.panneau.envoyerSouris(.leftMouseDragged, en: CGPoint(x: 10, y: milieu.y)); attendre(0.5)
        c.panneau.envoyerSouris(.leftMouseUp, en: CGPoint(x: 10, y: milieu.y)); attendre(0.6)
        verifier(m.courante == .lectureCompact && !m.lucarne.libre && !m.presse, "appui puis glissé de 10 pt : ni dépliage ni décollage")
        // appui interrompu par une dictée (le relâchement n'arrive jamais) : le clic suivant marche
        c.panneau.envoyerSouris(.leftMouseDown, en: milieu); attendre(0.1)
        var occA = OccupationEncoche(); c.occupation = { occA }
        occA.dictee = true; c.occupationChangee(); attendre(0.6)
        verifier(!m.presse && m.lucarne.geste.phase == .repos && !m.lucarne.libre, "dictée pendant l'appui : l'îlot n'est plus gonflé, rien ne se décolle")
        occA.dictee = false; c.occupationChangee(); c.occupation = { OccupationEncoche() }; attendre(0.9)
        c.panneau.envoyerSouris(.leftMouseDown, en: milieu); attendre(0.08); c.panneau.envoyerSouris(.leftMouseUp, en: milieu); attendre(0.9)
        verifier(m.courante == .lectureEtendu, "après un appui resté en plan : le clic suivant déplie normalement")
        m.fermer(); attendre(0.9)
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
        // curl -o / wget / AirDrop : le fichier est créé vide, puis écrit SUR PLACE (aucun ajout ni renommage : le dossier ne prévient pas)
        let iso = telechargements.appendingPathComponent("Image.iso")
        FileManager.default.createFile(atPath: iso.path, contents: nil); attendre(0.5)
        if let h = try? FileHandle(forWritingTo: iso) { h.write(Data(repeating: 0x2A, count: 2_000_000)); try? h.close() }
        attendre(4.0) { m.bandeauVu?.ligne1 != "Image.iso" }
        verifier(m.courante == .telecharge && m.bandeauVu?.ligne1 == "Image.iso", "fichier créé vide puis rempli sur place : annoncé quand même (\(m.bandeauVu?.ligne1 ?? "rien"))")
        // le fichier glissé hors du bandeau : le bandeau (source du glisser) reste jusqu'au relâchement, puis se retire
        var boutonTenu = true
        m.boutonEnfonce = { boutonTenu }
        m.glisserSortantCommence()
        attendre(5.0)
        verifier(m.bandeau?.vue == .telecharge && m.glisserSortant, "glisser en cours, 5 s après l'arrivée : le bandeau reste (sa vue est la source du glisser)")
        boutonTenu = false
        attendre(0.5)
        verifier(!m.glisserSortant && m.bandeau?.vue == .telecharge, "bouton relâché : le glisser est fini, le bandeau reste encore un instant")
        attendre(1.5) { m.bandeau != nil }
        verifier(m.bandeau == nil, "puis il se retire")
        m.boutonEnfonce = { NSEvent.pressedMouseButtons & 1 != 0 }
        c.telechargementsSource.arreter(); attendre(0.2)
        deposer("Après.pdf", 3_000); attendre(1.8)
        verifier(m.bandeau == nil && !c.telechargementsSource.actif, "réglage éteint (surveillance arrêtée) : plus rien n'est annoncé")
        // refus d'accès (EACCES) : le réglage s'éteint ; dossier absent : la surveillance s'arrête, le réglage reste (jamais de vrais
        // réglages touchés ici : le rappel de refus est remplacé)
        let refusAvant = c.telechargementsSource.surRefus
        var refus = 0
        c.telechargementsSource.surRefus = { refus += 1 }
        c.telechargementsSource.dossier = dossier.appendingPathComponent("absent", isDirectory: true)
        c.telechargementsSource.demarrer(); attendre(0.4)
        verifier(refus == 0 && !c.telechargementsSource.actif, "dossier absent : surveillance arrêtée, ce n'est pas un refus (le réglage reste)")
        let ferme = dossier.appendingPathComponent("ferme", isDirectory: true)
        try? FileManager.default.createDirectory(at: ferme, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: ferme.path)
        c.telechargementsSource.dossier = ferme
        c.telechargementsSource.demarrer(); attendre(0.4)
        verifier(refus == 1 && !c.telechargementsSource.actif, "accès refusé (EACCES) : c'est un refus, le réglage s'éteindrait")
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ferme.path)
        c.telechargementsSource.surRefus = refusAvant
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

        // --- micro coupé : un micro FACTICE (jamais CoreAudio, jamais le vrai micro) ; la bascule est celle du bouton Micro du Centre (de
        // vrais clics sur ce bouton dans l'essai du Centre)
        do {
            let faux = MicroFactice()
            c.micro = faux
            c.lecture.modele.morceau = MorceauEnCours(titre: "Album · Titre 3", app: "essai.lecture", joue: true, duree: 214, position: 97)
            c.lecture.surIlot(true)
            c.activerLeMicro(true); attendre(0.9)
            verifier(faux.actif && !m.microCoupe && m.resolution.principal == .lectureCompact, "micro ouvert au départ : rien ne change, la lecture garde l'îlot")
            c.basculerLeMicro(); attendre(0.9)
            verifier(faux.commandes == ["couper integre"] && faux.coupe && m.microCoupe, "bascule : le micro est coupé (une seule commande, sur ce micro)")
            verifier(m.courante == .microCompact && m.pastille == .lecture, "micro coupé : il prend l'îlot, la lecture devient la bulle")
            verifier(m.trace.bande <= Double(m.demiCamera) + GeoIlot.aileMax + 0.01 && abs(m.trace.hauteur - Double(g.hauteur)) < 0.01,
                     "micro coupé : dans les ailes, \(Int(m.trace.bande - Double(m.demiCamera))) pt de chaque côté de la caméra (≤ 66), rien sous la barre")
            let aile = m.grille.bordAile(.microCompact) - m.demiCamera - 4
            verifier(MesureIlot.texte("Coupé", 13, .semibold) <= aile && MesureIlot.texte("Ouvert", 13, .semibold) <= aile,
                     "« Coupé » (\(Int(MesureIlot.texte("Coupé", 13, .semibold))) pt) et « Ouvert » (\(Int(MesureIlot.texte("Ouvert", 13, .semibold))) pt) tiennent dans l'aile (\(Int(aile)) pt)")
            if let b = m.rectPastille() { verifier(b.minX >= CGFloat(m.trace.cou) + 5, "la bulle de la lecture est à côté de l'îlot, pas dessus") }
            attendre(1.2) { m.boucleActive }
            verifier(!m.boucleActive, "micro coupé, posé : aucune boucle d'animation (bouge encore : \(m.ceQuiBouge))")
            // survol : le micro coupé n'a plus de déplié à lui (son bouton est dans le Centre) : la vidéo en bulle se déplie
            c.panneau.simulerPointeur(forme: true); attendre(0.9)
            verifier(m.courante == .lectureEtendu && m.cartes == [.lectureEtendu, .centre, .outils, .accueil, .dictees] && m.trace.bande <= Double(m.demiCamera) + GeoIlot.aileMax + 0.01,
                     "survol, micro coupé pendant une vidéo : la vidéo se déplie, le Centre est la carte suivante (\(m.courante))")
            // vrai clic sur « Centre » au pied de la lecture, puis sur le bouton Micro, rouge
            let pc = PiedCarte.pointBouton(m.grille)
            c.panneau.envoyerSouris(.leftMouseDown, en: pc); attendre(0.06); c.panneau.envoyerSouris(.leftMouseUp, en: pc); attendre(0.9)
            verifier(m.courante == .centre, "vrai clic sur « Centre » : le Centre (\(m.courante))")
            let pm = PlanCentre.centreRond(m, .micro)
            c.panneau.envoyerSouris(.leftMouseDown, en: pm); attendre(0.06); c.panneau.envoyerSouris(.leftMouseUp, en: pm); attendre(0.4)
            verifier(faux.commandes.last == "rouvrir integre" && !faux.coupe && !m.microCoupe, "vrai clic sur le bouton Micro (« Coupé ») : le micro est rouvert")
            verifier(m.courante == .centre && m.epingle && m.bandeau == nil, "le Centre reste ouvert (« Reste ouvert ») ; pas de bandeau « Micro ouvert », qui le refermerait")
            c.panneau.simulerPointeur(forme: false); m.fermer(); attendre(0.9)
            verifier(m.bandeau == nil && m.resolution.principal == .lectureCompact && m.resolution.pastille == nil,
                     "refermé : la lecture reprend l'îlot (\(m.bandeau.map { "\($0.vue)" } ?? "sans bandeau"), \(m.resolution.principal), bulle \(m.resolution.pastille.map { "\($0)" } ?? "aucune"))")
            // Réglages Système : l'îlot suit (CoreAudio prévient ; ici le faux micro prévient de même)
            let n0 = faux.commandes.count
            faux.depuisLeSysteme(coupe: true); attendre(0.6)
            verifier(m.microCoupe && m.resolution.principal == .microCompact && m.bandeau == nil && faux.commandes.count == n0, "coupé dans Réglages Système : l'îlot le montre, sans bandeau ni commande")
            faux.depuisLeSysteme(coupe: false); attendre(0.3)
            verifier(!m.microCoupe && m.courante == .microOuvert, "rouvert dans Réglages Système : « Micro ouvert »")
            attendre(1.6)
            // coupé veut dire coupé (Hugues, 11/11 au soir : « micro coupé : rouvert (dictée) » à chaque fn) : fn ne rouvre rien, la dictée
            // ne part pas, l'îlot le dit et propose « Rouvrir le micro »
            c.basculerLeMicro(); attendre(0.6)
            let n1 = faux.commandes.count
            verifier(!c.autoriserDictee() && faux.commandes.count == n1 && faux.coupe, "fn pendant que c'est coupé : la dictée ne part pas, aucune commande (rien de rouvert, rien d'enregistré)")
            attendre(0.9)
            verifier(m.courante == .microFn && m.bandeauVu?.ligne1 == "Micro coupé" && m.contenuAnnonce(.microFn)?.l2 == "Rien n\u{2019}a été enregistré",
                     "l'îlot le dit : « Micro coupé · Rien n'a été enregistré » (\(m.courante))")
            verifier(m.trace.bande <= Double(m.demiCamera) + GeoIlot.aileMax + 0.01, "le bandeau : \(Int(m.trace.bande - Double(m.demiCamera))) pt dans la barre (≤ 66)")
            do {
                let za = m.grille.zoneAnnonce(.microFn), lc = m.contenus[.microFn] ?? 0
                let bw = MesureIlot.bouton(ContenuAnnonce.Bouton(titre: "Rouvrir le micro", icone: "mic.fill"))
                verifier(lc > bw && lc <= m.grille.zone(.microFn).width + 0.5,
                         "symbole, texte et « Rouvrir le micro » mesurés (\(Int(lc)) pt) tiennent dans le bandeau (\(Int(m.grille.zone(.microFn).width)) pt) : rien de tronqué")
                // un deuxième appui : toujours bloqué, rien de rouvert
                verifier(!c.autoriserDictee() && faux.commandes.count == n1, "un deuxième appui sur fn : toujours rien")
                attendre(0.5)
                // vrai clic sur « Rouvrir le micro » (calé à droite du bandeau)
                let pb = CGPoint(x: za.maxX - bw / 2, y: za.midY)
                c.panneau.envoyerSouris(.leftMouseDown, en: pb); attendre(0.06); c.panneau.envoyerSouris(.leftMouseUp, en: pb); attendre(0.6)
                verifier(Array(faux.commandes.dropFirst(n1)) == ["rouvrir integre"] && !faux.coupe && !m.microCoupe,
                         "vrai clic sur « Rouvrir le micro » : le micro est rouvert (\(Array(faux.commandes.dropFirst(n1))))")
                verifier(m.courante == .microOuvert, "« Micro ouvert » (\(m.courante))")
            }
            attendre(1.8)
            let n2 = faux.commandes.count
            verifier(c.autoriserDictee(), "puis fn : la dictée part")
            occ.dictee = true; c.dicteeChange(enCours: true); c.occupationChangee(); attendre(0.4)
            occ.dictee = false; c.dicteeChange(enCours: false); c.occupationChangee(); attendre(0.6)
            verifier(faux.commandes.count == n2 && !faux.coupe && m.bandeau == nil, "la dictée sur un micro ouvert ne touche à rien, aucun bandeau")
            // le Centre épinglé retient les bandeaux, mais pas la réponse à fn : sinon l'appui ne dirait rien
            c.basculerLeMicro(); attendre(0.6)
            m.survole = true; m.donneesChangees(); attendre(0.6); m.allerA(.centre); attendre(0.6); m.epinglerLeCentre(); attendre(0.3)
            verifier(m.courante == .centre && m.centreRetientLesBandeaux, "le Centre épinglé (\(m.courante))")
            verifier(!c.autoriserDictee(), "fn sur le Centre épinglé, micro coupé : refusé")
            attendre(0.8)
            verifier(m.courante == .microFn, "… et l'îlot le dit quand même (\(m.courante))")
            m.survole = false; c.agir(.microRouvrirPourDicter); attendre(0.6)
            verifier(!faux.coupe, "« Rouvrir le micro » (action) : rouvert")
            attendre(1.8)
            // micro du Mac ouvert, les AirPods arrivent (micro par défaut) puis sont coupés ; la dictée écoute le micro du Mac : elle part,
            // et l'îlot le dit à la fin, une fois
            faux.brancher("airpods"); attendre(0.4)
            verifier(!m.microCoupe && m.bandeau == nil, "AirPods connectés : l'îlot montre leur micro (ouvert), sans faux « Micro ouvert »")
            c.basculerLeMicro(); attendre(0.6)
            verifier(faux.coupes["airpods"] == true && faux.coupes["integre"] == false && m.microCoupe, "le bouton Micro coupe les AirPods (le micro par défaut)")
            faux.microDictee = "integre"
            let n4 = faux.commandes.count
            verifier(c.autoriserDictee(), "fn : la dictée écoute le micro du Mac, ouvert : elle part")
            occ.dictee = true; c.dicteeChange(enCours: true); c.occupationChangee(); attendre(0.5)
            verifier(m.cache && m.bandeau == nil, "pendant la dictée : l'îlot effacé, rien d'affiché")
            occ.dictee = false; c.dicteeChange(enCours: false); c.occupationChangee(); attendre(0.6)
            verifier(faux.commandes.count == n4 && faux.coupes["airpods"] == true, "les AirPods restent coupés (un appel ne les entendrait pas)")
            verifier(m.courante == .microFn && m.bandeauVu?.ligne1 == "Le micro des AirPods est coupé" && m.bandeauVu?.ligne2 == "Verbe dicte avec le micro du Mac"
                     && m.contenuAnnonce(.microFn).map { if case .rien = $0.droite { return true } else { return false } } == true,
                     "à la fin : « Le micro des AirPods est coupé · Verbe dicte avec le micro du Mac », sans bouton (\(m.courante))")
            attendre(4.5)
            verifier(c.autoriserDictee() && m.bandeau == nil, "le deuxième appui : la dictée part, on ne le redit pas")
            occ.dictee = true; c.dicteeChange(enCours: true); occ.dictee = false; c.dicteeChange(enCours: false); c.occupationChangee(); attendre(0.6)
            verifier(m.bandeau == nil, "… ni à la fin")
            // les AirPods coupés et le micro du Mac coupé aussi : la dictée ne part pas, et c'est le micro du Mac qui sera rouvert
            faux.coupes["integre"] = true
            let n5 = faux.commandes.count
            verifier(!c.autoriserDictee() && faux.commandes.count == n5, "le micro du Mac (celui de la dictée) coupé aussi : refusé, rien de rouvert")
            attendre(0.6)
            c.agir(.microRouvrirPourDicter); attendre(0.5)
            verifier(Array(faux.commandes.dropFirst(n5)) == ["rouvrir integre"] && faux.coupes["airpods"] == true,
                     "« Rouvrir le micro » rouvre le micro du Mac (celui de la dictée), pas les AirPods")
            faux.debrancher("airpods"); faux.microDictee = nil; attendre(0.4)
            c.basculerLeMicro(); attendre(0.6)
            verifier(m.microCoupe, "AirPods rangés, le micro du Mac coupé : l'îlot le montre")
            // réglage éteint : plus d'écoute ; le micro reste comme il est (le micro rouvert d'abord, le bandeau « Micro ouvert » parti)
            c.basculerLeMicro(); attendre(2.2) { m.bandeau != nil }
            c.activerLeMicro(false); attendre(0.6)
            verifier(!faux.actif && !m.microCoupe && m.resolution.principal == .lectureCompact, "réglage éteint : l'îlot ne montre plus le micro")
            let n3 = faux.commandes.count
            let servi = c.basculerLeMicro(); faux.depuisLeSysteme(coupe: false); attendre(0.4)
            verifier(!servi && faux.commandes.count == n3 && m.bandeau == nil, "réglage éteint : la bascule et CoreAudio ne font plus rien")
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
            // le réglage se fait hors du rappel du clavier (comme la vraie file) : la touche est avalée tout de suite, l'îlot suit
            attendre(1.8) { m.bandeau != nil }
            faux.differe = true
            let v0 = faux.son.valeur
            let d1 = touche(.volumePlus)
            verifier(d1 && faux.son.valeur == v0 && m.bandeau == nil, "touche avalée sans attendre le système (rien n'est lu ni écrit dans le rappel du clavier)")
            attendre(0.15)
            verifier(faux.son.valeur > v0 && m.bandeau?.vue == .volume, "puis le volume est réglé et l'îlot le montre")
            _ = touche(.volumePlus, enfoncee: false)
            faux.differe = false
            // une écriture refusée (sortie qui change pendant l'écriture) : la touche suivante va à macOS, plus rien n'est avalé pour rien
            attendre(1.8) { m.bandeau != nil }
            faux.refuser = true
            let n4 = faux.ecritures.count
            let r1 = appuyer(.volumePlus)
            let r2 = appuyer(.volumePlus)
            verifier(r1.bas && r1.haut && !r2.bas && !r2.haut && faux.ecritures.count == n4 && m.bandeau == nil,
                     "écriture refusée : l'appui suivant et son relâchement vont à macOS (son affichage), l'îlot ne montre rien de faux")
            faux.refuser = false; faux.changement()
            verifier(appuyer(.volumePlus).bas, "le système signale un changement (nouvelle sortie) : Verbe reprend la main")
            // le lecteur épinglé ouvert : la touche reste à macOS, l'îlot ne se referme pas sous les doigts
            attendre(1.8) { m.bandeau != nil }
            m.clicForme(); attendre(0.6)
            let n5 = faux.ecritures.count
            let ep = appuyer(.volumeMoins)
            verifier(m.epingle && !ep.bas && !ep.haut && faux.ecritures.count == n5 && m.courante == .lectureEtendu,
                     "lecteur épinglé ouvert : volume − laissé à macOS, le lecteur reste ouvert et épinglé (\(m.courante))")
            m.fermer(); attendre(0.6)
            // la souris immobile sur l'encoche ne retient pas le volume
            _ = appuyer(.volumePlus)
            c.panneau.simulerPointeur(forme: true)
            attendre(2.2)
            verifier(m.bandeau == nil, "souris posée sur l'encoche : le bandeau du volume part quand même (1,5 s après la touche)")
            c.panneau.simulerPointeur(forme: false); attendre(0.5)
            // macOS coupe puis rallume l'écoute du clavier pendant qu'une touche est tenue : ce qui la retenait repart de zéro
            _ = touche(.volumePlus)
            let clavierN = KeyMonitor()
            clavierN.onReinitialisation = { c.aiguillageNiveau = AiguillageNiveau() }
            if let ev = CGEvent(source: nil) {
                _ = clavierN.recevoir(type: .tapDisabledByTimeout, event: ev)
                verifier(!c.aiguillageNiveau.avalee(.volumePlus) && !touche(.volumePlus, enfoncee: false), "écoute coupée par macOS : la touche tenue est oubliée, son relâchement va à macOS")
            }
            attendre(1.8) { m.bandeau != nil }
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
            // le script d'une version d'avant (sans message ni titre) : remplacé tout seul au lancement, l'ancien gardé à côté ; settings.json
            // n'est pas touché
            let ancien = "#!/bin/sh\n# ancienne version\nexit 0\n"
            try? Data(ancien.utf8).write(to: inst.script)
            let avantMaj = lireReglages()
            verifier(inst.mettreAJourLeScript() && (try? String(contentsOf: inst.script, encoding: .utf8)) == ScriptCrochet.texte(dossier: inst.etats.path)
                     && (try? String(contentsOf: inst.script.appendingPathExtension("verbe-sauvegarde"), encoding: .utf8)) == ancien
                     && droits(inst.script) == 0o755 && lireReglages() == avantMaj,
                     "script d'avant : remplacé au lancement (exécutable), l'ancien gardé (.verbe-sauvegarde), settings.json intact")
            verifier(!inst.mettreAJourLeScript(), "déjà à jour : rien n'est réécrit")
            // un settings.json présent mais illisible (octets qui ne sont pas de l'UTF-8, lien cassé) : jamais remplacé par nos seuls crochets
            func echec(_ i: InstallationClaude, _ faire: (InstallationClaude) throws -> Void) -> Bool {
                do { try faire(i); return false } catch InstallationClaude.Echec.inaccessible { return true } catch { return false }
            }
            let abime = InstallationClaude(reglages: racine.appendingPathComponent("abime/settings.json"), dossierVerbe: inst.dossierVerbe)
            try? FileManager.default.createDirectory(at: abime.reglages.deletingLastPathComponent(), withIntermediateDirectories: true)
            let octets = Data([0x7B, 0x22, 0x6D, 0x6F, 0x64, 0xFF, 0xFE, 0x22, 0x3A, 0x31, 0x7D])
            try? octets.write(to: abime.reglages)
            verifier(echec(abime) { try $0.brancher() } && echec(abime) { try $0.debrancher() } && !abime.estBranche,
                     "settings.json non UTF-8 : « Brancher » et « Débrancher » refusent (« n'a pas pu être lu »)")
            verifier((try? Data(contentsOf: abime.reglages)) == octets && !FileManager.default.fileExists(atPath: abime.sauvegarde.path),
                     "… et le fichier est intact, octet pour octet (rien écrit, aucune copie à la place)")
            let casse = InstallationClaude(reglages: racine.appendingPathComponent("lien/settings.json"), dossierVerbe: inst.dossierVerbe)
            try? FileManager.default.createDirectory(at: casse.reglages.deletingLastPathComponent(), withIntermediateDirectories: true)
            let nullePart = racine.appendingPathComponent("lien/nulle-part.json")
            try? FileManager.default.createSymbolicLink(at: casse.reglages, withDestinationURL: nullePart)
            verifier(echec(casse) { try $0.brancher() } && (try? FileManager.default.destinationOfSymbolicLink(atPath: casse.reglages.path)) == nullePart.path
                     && !FileManager.default.fileExists(atPath: nullePart.path), "settings.json lien cassé : refusé, le lien reste un lien, rien n'est créé")

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
            let rn = crochet(ev("nuit", "Stop"), app: nil)
            verifier(rn.code == 0 && !FileManager.default.fileExists(atPath: fichier("nuit").path),
                     "session sans app d'origine (claude -p lancé par launchd ou cron) : le script n'écrit rien, code 0")
            var premierPlan: String? = "com.google.Chrome"
            var ramenes: [String?] = []
            c.appAuPremierPlan = { premierPlan }
            c.ramenerSession = { ramenes.append($0?.app) }
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
            verifier(m.claude?.progres == ProgresClaude(faites: 3, total: 7) && m.courante == .claudeCompact, "la liste de tâches : l'anneau, « 3/7 »")
            let r3 = m.cadreAnneauClaude(m.grille), l37 = MesureIlot.texte("3/7", 12.5, .bold, chiffres: true)
            verifier(m.avancementClaude(m.claude) == "3/7" && m.nomClaude(m.claude) == "Tâche 4" && r3.minX >= -(m.grille.bordAile(.claudeCompact)) - 0.5
                     && r3.maxX + 6 + l37 <= -(m.demiCamera + 4) + 0.5,
                     "aile gauche : l'anneau et « 3/7 » (\(Int(r3.width + 6 + l37)) pt dans 48) ; aile droite : le nom de la tâche « in_progress » (« Tâche 4 »)")
            verifier(m.trace.bande <= Double(m.demiCamera) + GeoIlot.aileMax + 0.01 && abs(m.trace.hauteur - Double(g.hauteur)) < 0.01,
                     "« 3 sur 7 » : \(Int(m.trace.bande - Double(m.demiCamera))) pt de chaque côté de la caméra (≤ 66), rien sous la barre")
            attendre(1.2) { m.boucleActive }
            verifier(!m.boucleActive, "Claude au travail, posé : aucune boucle d'animation (bouge encore : \(m.ceQuiBouge))")
            // un outil quelconque : une ligne courte, jamais son contenu (même s'il cite « session_id »)
            _ = crochet(ev("s1", "PostToolUse", ",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"/x.swift\",\"content\":\"let session_id = \\\"piege\\\" // contenu-du-fichier\"},\"tool_response\":{}"))
            let l1 = (try? String(contentsOf: fichier("s1"), encoding: .utf8)) ?? ""
            verifier(!l1.contains("contenu-du-fichier") && l1.contains("\"tool_name\":\"Write\"") && !FileManager.default.fileExists(atPath: fichier("piege").path),
                     "un outil qui écrit un fichier : une ligne courte, sans le contenu ; le « session_id » cité dans le contenu ne trompe pas le script")
            // survol, Claude au travail : le Centre (maquette, étape 2) ; vrai clic sur le bouton Claude Code : la carte ; vrai clic sur « Ouvrir »
            m.claudeBranche = true
            c.panneau.simulerPointeur(forme: true); attendre(0.9)
            verifier(m.courante == .centre && m.etatCentre(.claude) == "1 au travail", "survol : le Centre ; le bouton Claude Code dit « 1 au travail » (\(m.etatCentre(.claude)))")
            c.panneau.envoyerSouris(.leftMouseDown, en: PlanCentre.centreRond(m, .claude)); attendre(0.06); c.panneau.envoyerSouris(.leftMouseUp, en: PlanCentre.centreRond(m, .claude))
            attendre(0.9)
            verifier(m.courante == .claudeCarte && m.sessionsClaude.map(\.id) == ["s1"] && m.trace.bande <= Double(m.demiCamera) + GeoIlot.aileMax + 0.01,
                     "vrai clic sur Claude Code : la carte, un bloc (s1) ; ≤ 66 pt dans la barre (\(m.courante))")
            let hCarte = Double(g.hauteur) + Double(PlanCarteClaude.profondeur(m))
            verifier(abs(m.traceCible.hauteur - hCarte) < 0.5 && m.traceCible.hauteur <= Double(g.hauteur) + GeoIlot.profondeurCentre + 0.5,
                     "la carte épouse sa session (\(Int(m.traceCible.hauteur)) pt), jamais plus haute que le Centre")
            let po = PlanCarteClaude.pointOuvrir(0, m)
            c.panneau.envoyerSouris(.leftMouseDown, en: po); attendre(0.06); c.panneau.envoyerSouris(.leftMouseUp, en: po)
            c.panneau.simulerPointeur(forme: false); attendre(0.6)
            verifier(ramenes == ["com.apple.Terminal"] && m.courante == .claudeCompact, "vrai clic sur « Ouvrir » : la fenêtre du Terminal de la session est ramenée (capturé), l'îlot se replie")
            // une autorisation à donner : « Claude attend ta réponse »
            _ = crochet(ev("s1", "Notification", ",\"message\":\"Claude needs your permission to use Bash\",\"notification_type\":\"permission_prompt\""))
            attendre(2.0) { m.bandeau == nil }; attendre(0.3)
            verifier(m.courante == .claudeAttend && m.bandeauVu?.ligne1 == "dictee-mac attend ta réponse" && m.bandeauVu?.ligne2 == "«\u{202F}Autoriser Bash\u{202F}?\u{202F}»",
                     "notification : « dictee-mac attend ta réponse », « « Autoriser Bash ? » » (\(m.bandeauVu?.ligne2 ?? "rien"))")
            let lf = (try? String(contentsOf: fichier("s1"), encoding: .utf8)) ?? ""
            verifier(lf.contains("\"message\":\"Claude needs your permission to use Bash\""), "le script a transmis le message de la notification")
            verifier(m.trace.bande <= Double(m.demiCamera) + GeoIlot.aileMax + 0.01 && m.trace.hauteur > Double(g.hauteur) + 60, "bandeau : sous la barre, cou étroit")
            attendre(5.0) { m.bandeau != nil }; attendre(0.9)
            verifier(m.bandeau == nil && m.courante == .claudeCompact && m.nomClaude(m.claude) == "dictee-mac attend ta réponse" && m.etatCentre(.claude) == "Attend",
                     "4,5 s plus tard : « dictee-mac attend ta réponse » dans l'aile (en ambre), « Attend » sous le bouton du Centre")
            c.panneau.simulerPointeur(forme: true); attendre(0.9)
            verifier(m.courante == .claudeCarte && m.sessionsClaude.first?.etat == .attend, "une session attend : le survol ouvre directement sa carte, elle en haut (\(m.courante))")
            c.panneau.simulerPointeur(forme: false); attendre(0.8)
            verifier(m.courante == .claudeCompact, "souris partie : la carte se range")
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
            _ = crochet(ev("s1", "UserPromptSubmit", ",\"prompt\":\"encore-secret\",\"session_title\":\"Carte Dictées\""))
            let lt = (try? String(contentsOf: fichier("s1"), encoding: .utf8)) ?? ""
            verifier(lt.contains("\"session_title\":\"Carte Dictées\"") && !lt.contains("encore-secret"), "le titre de la session est transmis, jamais la demande tapée")
            attendre(2.0) { m.claude == nil }
            _ = crochet(ev("s1", "Stop", ",\"stop_hook_active\":false"))
            attendre(2.0) { m.bandeau == nil }; attendre(0.3)
            verifier(m.courante == .claudeTermine && m.bandeauVu?.ligne1 == "Carte Dictées terminée" && m.bandeauVu?.ligne2.hasPrefix("dictee-mac \u{00B7} 1 min") == true && m.claude == nil,
                     "fini pendant que Hugues est ailleurs : « Carte Dictées terminée », « \(m.bandeauVu?.ligne2 ?? "") », coche verte")
            c.agir(.claudeOuvrir(m.bandeauVu?.claude)); attendre(0.3)
            verifier(ramenes.last == "com.apple.Terminal" && m.bandeau == nil, "« Voir » sur la fin : la fenêtre du Terminal est ramenée, le bandeau se retire")
            _ = crochet(ev("s1", "UserPromptSubmit")); attendre(2.0) { m.claude == nil }
            _ = crochet(ev("s1", "Stop")); attendre(2.0) { m.bandeau == nil }
            attendre(4.2) { m.bandeau != nil }; attendre(0.5)
            verifier(m.bandeau == nil && m.courante == .repos, "sans geste : la fin se retire après 3,5 s")
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
            c.lecture.modele.morceau = nil; c.lecture.surIlot(false); attendre(0.8)
            // deux sessions au travail (et une longue liste) : le petit « 2 », la carte qui défile avec de vraies molettes, la session qui attend en haut
            func evIci(_ session: String, _ nom: String, cwd: String, _ reste: String = "") -> String {
                ev(session, nom, reste).replacingOccurrences(of: "/Users/essai/dev/dictee-mac", with: cwd)
            }
            let quatorze = ",\"tool_name\":\"TodoWrite\",\"tool_input\":{\"todos\":[" + (1...14).map { i in
                "{\"content\":\"Étape \(i)\",\"status\":\"\(i <= 5 ? "completed" : (i == 6 ? "in_progress" : "pending"))\"}" }.joined(separator: ",") + "]}"
            _ = crochet(evIci("s3", "UserPromptSubmit", cwd: "/Users/essai/second-cerveau")); _ = crochet(evIci("s3", "PostToolUse", cwd: "/Users/essai/second-cerveau", quatorze))
            attendre(2.0) { m.claudeAuTravail < 2 }; attendre(0.9)
            verifier(m.claudeAuTravail == 2 && m.etatCentre(.claude) == "2 au travail", "deux sessions au travail : le petit « 2 », « 2 au travail » sous le bouton")
            m.claudeBranche = true
            c.panneau.simulerPointeur(forme: true); attendre(0.9)
            c.panneau.envoyerSouris(.leftMouseDown, en: PlanCentre.centreRond(m, .claude)); attendre(0.06); c.panneau.envoyerSouris(.leftMouseUp, en: PlanCentre.centreRond(m, .claude))
            attendre(0.9)
            let trop = PlanCarteClaude.depassement(m)
            verifier(m.courante == .claudeCarte && m.sessionsClaude.count == 2 && trop > 50 && abs(m.traceCible.hauteur - (Double(g.hauteur) + GeoIlot.profondeurCentre)) < 0.5,
                     "la carte : deux blocs, 14 tâches ; elle prend la hauteur du Centre et dépasse de \(Int(trop)) pt")
            let milieu = CGPoint(x: 0, y: PlanCarteClaude.cadreListe(m.grille).midY)
            c.panneau.envoyerDefilement(dy: -40, en: milieu, phase: 1); c.panneau.envoyerDefilement(dy: -40, en: milieu, phase: 2); c.panneau.envoyerDefilement(dy: 0, en: milieu, phase: 4)
            attendre(0.3)
            verifier(m.courante == .claudeCarte && m.defilementClaude > 40, "vrais défilements (deux doigts) : la liste défile (\(Int(m.defilementClaude)) pt), la carte reste")
            for _ in 0..<30 { c.panneau.envoyerDefilement(dy: -40, en: milieu, phase: 2) }
            attendre(0.2)
            verifier(abs(m.defilementClaude - trop) < 0.5, "au bout : la liste s'arrête à sa fin (\(Int(m.defilementClaude)) / \(Int(trop)) pt)")
            // au bout, les blocs remontés hors de la liste ne prennent plus les clics de l'en-tête (ni `.clipped` ni `.mask` ne bornent
            // les clics) : « Reste ouvert », le titre et le corps d'un bloc ne rangent rien, « ‹ Centre » mène au Centre
            func clicReel(_ p: CGPoint) { c.panneau.envoyerSouris(.leftMouseDown, en: p); attendre(0.06); c.panneau.envoyerSouris(.leftMouseUp, en: p); attendre(0.5) }
            let ent = PlanCarteClaude.cadreEntete(m.grille), liste = PlanCarteClaude.cadreListe(m.grille)
            clicReel(CGPoint(x: ent.maxX - 30, y: ent.midY))
            clicReel(CGPoint(x: ent.minX + PlanCarteClaude.pilule + 10 + 14 + 6 + 30, y: ent.midY))
            clicReel(CGPoint(x: liste.midX, y: liste.maxY - 20))
            verifier(m.courante == .claudeCarte && m.epingle && abs(m.defilementClaude - trop) < 0.5,
                     "défilée au bout : de vrais clics sur « Reste ouvert », sur le titre et sur les tâches d'un bloc ne rangent pas l'îlot (\(m.courante))")
            clicReel(PlanCarteClaude.pointCentre(m)); attendre(0.4)
            verifier(m.courante == .centre, "défilée au bout : un vrai clic sur « ‹ Centre » mène au Centre (\(m.courante))")
            clicReel(PlanCentre.centreRond(m, .claude)); attendre(0.4)
            verifier(m.courante == .claudeCarte, "le rond Claude : de retour sur la carte (\(m.courante))")
            for _ in 0..<30 { c.panneau.envoyerDefilement(dy: 40, en: milieu, phase: 2) }
            attendre(0.2)
            verifier(m.defilementClaude == 0 && m.courante == .claudeCarte, "vers le haut : retour en haut, toujours la carte")
            // la deuxième session attend : elle passe en haut, cadre ambre ; sa fenêtre ramenée d'un vrai clic
            _ = crochet(evIci("s3", "Notification", cwd: "/Users/essai/second-cerveau", ",\"message\":\"Claude needs your permission to use Edit\",\"notification_type\":\"permission_prompt\""))
            attendre(2.0) { m.sessionsClaude.first?.id != "s3" }; attendre(0.5)
            verifier(m.sessionsClaude.first?.id == "s3" && m.sessionsClaude.first?.etat == .attend && m.courante == .claudeCarte && m.bandeau == nil,
                     "second-cerveau attend : en haut de la carte ; la carte ouverte, le bandeau attend qu'elle se range")
            let avantClic = ramenes.count
            let p0 = PlanCarteClaude.pointOuvrir(0, m)
            c.panneau.envoyerSouris(.leftMouseDown, en: p0); attendre(0.06); c.panneau.envoyerSouris(.leftMouseUp, en: p0)
            c.panneau.simulerPointeur(forme: false); attendre(0.9)
            verifier(ramenes.count == avantClic + 1 && m.courante != .claudeCarte, "vrai clic sur « Ouvrir » de second-cerveau : sa fenêtre est ramenée, la carte se range")
            verifier(m.bandeau == nil, "le bandeau « second-cerveau attend » qui attendait n'a plus lieu d'être : retiré")
            _ = crochet(evIci("s3", "SessionEnd", cwd: "/Users/essai/second-cerveau")); attendre(2.0) { m.claudeAuTravail > 1 }; attendre(0.5)
            verifier(m.claudeAuTravail == 1, "second-cerveau fermé : plus qu'une session")
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
            // le nom qui défile dans l'aile : deux passages puis il s'arrête sur son début (Claude travaille des heures : une animation
            // sans fin tenait l'écran à sa pleine fréquence tout ce temps)
            let defilant = DefilantClaude.Vue(frame: CGRect(x: 0, y: 0, width: 60, height: 17))
            defilant.appliquer("Construire la carte Dictées et brancher la recherche", ambre: false, largeur: 60)
            let anim = defilant.bande.animation(forKey: "defil")
            verifier(anim?.repeatCount == 2 && anim?.isRemovedOnCompletion == true, "le nom trop long défile deux fois puis s'arrête (\(anim?.repeatCount ?? -1) passages)")
            defilant.appliquer("Lire", ambre: false, largeur: 60)
            verifier(defilant.bande.animation(forKey: "defil") == nil, "un nom qui tient : aucune animation")
        }

        // --- réunion : l'îlot reste (la réunion y est une activité) ; un rappel qui sonne s'affiche, sans aucun son (vibration seule)
        var enCours = ReunionIlot(); enCours.depuis = c.maintenant()
        occ.reunion = true; c.occupationChangee(); c.reunionChangee(enCours, annonce: nil); attendre(0.5)
        verifier(!m.cache && m.courante == .reunionCompact, "réunion : l'îlot ne s'efface plus, la réunion y est une activité (\(m.courante))")
        let s0 = compteurs
        c.ajouterUnRappel(texte: "Appeler Paul", quand: Date().addingTimeInterval(decalage + 0.4))
        attendre(1.4)
        verifier(m.alerte?.vue == .rappelEtendu && compteurs.rappel == s0.rappel && compteurs.silence == s0.silence + 1 && m.pastille == .reunion,
                 "réunion : le rappel s'affiche sans son (vibration seule), la réunion dans la bulle")
        occ.reunion = false; c.occupationChangee(); c.reunionChangee(nil, annonce: nil); attendre(0.9)
        verifier(m.alerte?.vue == .rappelEtendu, "réunion finie : le rappel est toujours là")
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

        // --- le Centre sur l'îlot vide, et commandes dictées
        c.injecterEvenements([]); c.moteur.quitterAlerte(); attendre(0.5)
        c.lecture.modele.morceau = nil; c.lecture.surIlot(false); attendre(0.3)
        verifier(m.resolution.principal == .repos && m.resolution.survol == .centre, "plus rien : au survol, le Centre")
        c.panneau.simulerPointeur(forme: true); attendre(0.15)
        verifier(m.courante == .repos, "îlot vide, souris posée depuis 0,15 s : rien encore (intention de 0,28 s)")
        attendre(0.5)
        verifier(m.courante == .centre, "îlot vide : le survol ouvre directement le Centre")
        c.panneau.simulerPointeur(forme: false); attendre(0.7)
        verifier(m.courante == .repos, "souris partie : l'îlot vide se referme")
        m.clicForme(); attendre(0.6)
        verifier(m.courante == .centre, "clic sur l'îlot vide : le Centre")
        verifier(c.intercepter("minuteur 10 minutes") == false && c.minuteur == nil, "sans dictée armée, une commande n'est jamais interceptée")
        c.dicteeChange(enCours: true)   // le Centre est ouvert à cet instant : la commande dictée est armée
        occ.dictee = true; c.occupationChangee(); attendre(0.3)
        occ.dictee = false; c.dicteeChange(enCours: false); c.occupationChangee()
        verifier(c.intercepter("Bonjour Paul, je te rappelle demain.") == false, "Centre ouvert + phrase normale : le texte est collé normalement")
        c.moteur.clicForme(); attendre(0.5)
        verifier(m.courante == .centre, "Centre rouvert avant de dicter")
        c.dicteeChange(enCours: true); occ.dictee = true; c.occupationChangee(); attendre(0.2)
        occ.dictee = false; c.dicteeChange(enCours: false); c.occupationChangee(); attendre(0.2)
        verifier(c.intercepter("Minuteur 10 minutes.") == true && c.minuteur != nil, "Centre ouvert + « minuteur 10 minutes » : minuteur lancé, rien n'est collé")
        verifier(abs((c.minuteur?.restant(a: c.maintenant()) ?? 0) - 600) < 2, "le minuteur dicté dure 10 minutes")
        c.agir(.minuteurArreter)
        verifier(c.intercepter("Minuteur 10 minutes.") == false, "la commande n'est utilisable qu'une fois par dictée armée")

        // --- l'étagère : des fichiers TEMPORAIRES (jamais ceux de l'utilisateur), un etagere.json temporaire ; le glisser est simulé en
        // appelant directement les méthodes du panneau (en essai, aucun moniteur global : les vrais glissers de l'utilisateur n'ouvrent rien)
        do {
            // le bandeau « Minuteur lancé » de la commande dictée se retire d'abord
            attendre(3.0) { m.bandeau != nil }
            c.moteur.fermer(); attendre(0.8)
            let rayon = dossier.appendingPathComponent("Étagère", isDirectory: true)
            try? FileManager.default.createDirectory(at: rayon, withIntermediateDirectories: true)
            func creer(_ nom: String) -> URL { let u = rayon.appendingPathComponent(nom); try? Data("essai".utf8).write(to: u); return u }
            let contrat = creer("Contrat.pdf"), photo = creer("Photo.heic"), notes = creer("Notes.txt")
            verifier(c.etagereStore.url.path.hasPrefix(dossier.path) && c.etagere.estVide, "étagère d'essai : fichier temporaire, vide au départ")
            c.activerEtagere(true); attendre(0.2)
            verifier(c.panneau.accepteLesFichiers, "réglage allumé : la fenêtre accepte les fichiers lâchés (URL de fichiers)")
            let hc = Double(m.demiCamera), barre = Double(g.hauteur)
            var lu = 0
            c.panneau.glisser(CGPoint(x: 400, y: 300), nouveau: { false }) { lu += 1; return true }; attendre(0.3)
            verifier(!m.depot && !m.appel && m.courante == .repos && lu == 0, "le presse-papiers du glisser n'a pas changé (fenêtre déplacée) : rien, ce qui est glissé n'est même pas regardé")
            c.panneau.glisser(CGPoint(x: 400, y: 300)) { lu += 1; return true }; attendre(0.6)
            verifier(!m.depot && m.appel && m.courante == .etagereAppel && lu == 1, "fichiers glissés loin de l'encoche : l'îlot appelle « Glisse ici » (\(m.courante), regardé \(lu) fois)")
            verifier(m.traceCible.bande <= hc + GeoIlot.aileMax + 0.01 && abs(m.traceCible.hauteur - barre - 38) < 0.01, "« Glisse ici » : \(Int(m.traceCible.bande - hc)) pt dans la barre (≤ 66), 38 pt dessous")
            c.panneau.finDuGlisser(); attendre(0.6)
            verifier(!m.appel && m.courante == .repos, "glisser fini ailleurs : l'îlot se range aussitôt")
            c.panneau.glisser(CGPoint(x: 0, y: barre + 30)) { lu += 1; return false }; attendre(0.3)
            c.panneau.glisser(CGPoint(x: 10, y: barre + 20)) { lu += 1; return false }; attendre(0.2)
            verifier(!m.depot && !m.appel && lu == 2, "texte étiré près de l'encoche : rien (regardé une seule fois par glisser)")
            c.panneau.finDuGlisser()
            c.panneau.glisser(CGPoint(x: hc + 50, y: 12)) { lu += 1; return true }; attendre(0.9)
            verifier(m.depot && m.courante == .etagereDepot && lu == 3, "fichiers glissés à 50 pt de la caméra : l'îlot s'ouvre en grand, les deux zones")
            verifier(m.trace.bande <= hc + GeoIlot.aileMax + 0.01 && m.trace.hauteur > barre + 90, "« Déposez ici » sous la barre ; dans la barre, \(Int(m.trace.bande - hc)) pt de chaque côté de la caméra (≤ 66)")
            if let f = c.panneau.cadre { verifier(Double(f.height) >= m.trace.hauteur && Double(f.width) >= 2 * m.trace.corps, "la fenêtre couvre la zone (\(Int(f.width)) × \(Int(f.height)))") }
            verifier(!m.depotSurvole, "pointeur à côté de la forme : la zone n'est pas encore éclairée")
            c.panneau.glisser(CGPoint(x: -60, y: barre + 50)) { true }; attendre(0.1)
            verifier(m.depotSurvole && m.depotZone == .etagere, "pointeur sur la zone de gauche : « Étagère » s'éclaire")
            c.panneau.glisser(CGPoint(x: 60, y: barre + 50)) { true }; attendre(0.1)
            verifier(m.depotSurvole && m.depotZone == .airdrop, "pointeur sur la zone de droite : « AirDrop » s'éclaire")
            c.panneau.glisser(CGPoint(x: -60, y: barre + 50)) { true }; attendre(0.1)
            attendre(1.2) { m.boucleActive }
            verifier(!m.boucleActive, "« Déposez ici » posé : aucune boucle d'animation (bouge encore : \(m.ceQuiBouge))")
            c.panneau.glisser(CGPoint(x: m.trace.corps + 30, y: barre + 60)) { true }; attendre(0.3)
            verifier(m.depot, "pointeur 30 pt à côté de la zone : elle reste ouverte (on ne la perd pas en la visant)")
            verifier(!c.panneau.peutDeposer(CGPoint(x: m.trace.corps + 30, y: barre + 60)) && c.panneau.peutDeposer(CGPoint(x: -60, y: barre + 50)),
                     "un lâcher n'est accepté que sur la forme (pas dans le vide de la fenêtre autour)")
            // dans la barre des menus, à côté du cou mais dans le rectangle de la fenêtre : la zone se referme (ce sont les icônes voisines)
            let icone = CGPoint(x: m.traceCible.cou + 80, y: barre / 2)
            let fenetreLarge = c.panneau.cadre.map { Double($0.width) / 2 > Double(icone.x) } ?? false
            verifier(!c.panneau.peutDeposer(icone), "dans la barre, à côté du cou : aucun lâcher accepté")
            c.panneau.glisser(icone) { true }; attendre(0.6)
            verifier(!m.depot && fenetreLarge, "dans la barre, 80 pt à côté du cou (encore dans la fenêtre) : la zone se referme, l'icône voisine reçoit le glisser")
            c.panneau.glisser(CGPoint(x: 0, y: barre + 10)) { true }; attendre(0.6)
            verifier(m.depot, "revenu sous l'encoche : la zone se rouvre")
            c.panneau.glisser(CGPoint(x: 600, y: 420)) { true }; attendre(0.9)
            verifier(!m.depot && m.courante == .etagereAppel, "pointeur reparti loin sans lâcher : les zones se referment, l'îlot appelle encore")
            c.panneau.finDuGlisser(); attendre(0.5)
            verifier(m.courante == .repos, "puis le glisser finit ailleurs : rangé")
            // lâché sur l'îlot
            c.panneau.glisser(CGPoint(x: 0, y: barre + 10)) { true }; attendre(0.5)
            verifier(c.panneau.glisserSurLIlot(CGPoint(x: -60, y: barre + 40)) && m.depotSurvole && m.depotZone == .etagere, "le système dit que le glisser est sur la fenêtre : accepté, la zone s'éclaire")
            verifier(ConteneurIlot.operation([.copy, .link, .generic]) == .link && ConteneurIlot.operation([.copy]) == .copy, "curseur : flèche de lien (on garde un lien, pas une copie)")
            verifier(c.panneau.deposer([contrat, photo]), "fichiers lâchés : acceptés")
            verifier(c.etagere.elements.map(\.nom) == ["Contrat.pdf", "Photo.heic"] && m.etagere.map(\.nom) == ["Contrat.pdf", "Photo.heic"], "deux fichiers sur l'étagère, dans l'ordre")
            verifier(FileManager.default.fileExists(atPath: contrat.path) && FileManager.default.fileExists(atPath: photo.path), "les fichiers n'ont pas bougé (ni copiés, ni déplacés)")
            let droits = (try? FileManager.default.attributesOfItem(atPath: c.etagereStore.url.path)[.posixPermissions] as? Int) ?? -1
            verifier(droits == 0o600, "etagere.json écrit en 0600 (\(String(droits, radix: 8)))")
            verifier(m.depot && !m.depotSurvole && m.depotRange && EssaiEtagere.envois.isEmpty, "juste après : « Rangé » (rien n'est parti par AirDrop)")
            c.panneau.finDuGlisser()
            verifier(m.depot, "le relâchement du bouton, qui suit le dépôt, ne coupe pas ce coup d'œil")
            attendre(1.6)
            verifier(!m.depot && m.courante == .etagerePile, "0,85 s plus tard : l'îlot se replie de lui-même, la pile dans l'aile (\(m.courante))")
            // le relâchement du bouton arrive AVANT le message de dépôt (l'ordre dépend de macOS) : le dépôt est quand même accepté
            c.panneau.glisser(CGPoint(x: -10, y: 10)) { true }; attendre(0.3)
            c.panneau.finDuGlisser(); attendre(0.05)
            verifier(m.depot && c.panneau.peutDeposer(CGPoint(x: -60, y: barre + 40)), "relâchement vu d'abord : la zone attend un instant le dépôt")
            c.panneau.deposer([photo, notes, URL(string: "https://exemple.fr/page")!]); attendre(1.6)
            verifier(c.etagere.elements.map(\.nom) == ["Contrat.pdf", "Photo.heic", "Notes.txt"], "redéposé : pas de doublon ; un lien web est ignoré")
            verifier(fabriquer().etagere.elements.map(\.nom) == ["Contrat.pdf", "Photo.heic", "Notes.txt"], "après relance : l'étagère est relue depuis son fichier")
            // relâché ailleurs : la zone se referme, après ce court délai
            c.panneau.glisser(CGPoint(x: 0, y: 10)) { true }; attendre(0.6)
            c.panneau.finDuGlisser(); c.panneau.finDuGlisser(); attendre(0.1); c.panneau.finDuGlisser()
            verifier(m.depot, "relâché : la zone attend encore (les mouvements qui suivent ne repoussent pas l'échéance)")
            attendre(0.4)
            verifier(!m.depot, "\(Int(IlotPanneau.delaiFinGlisser * 1000)) ms après le relâchement, sans dépôt : la zone se referme")
            attendre(0.6)
            // un glisser qui PART de l'îlot (une tuile, le fichier du bandeau « Téléchargé ») n'ouvre jamais la zone sous lui-même
            verifier(!c.panneau.glisserSurLIlot(CGPoint(x: 0, y: barre + 40), interne: true) && !m.depot,
                     "glisser venu de Verbe lui-même (source dans l'app) : refusé, pas de « Déposez ici »")
            var tenu = true
            m.boutonEnfonce = { tenu }
            m.glisserSortantCommence()
            c.panneau.glisser(CGPoint(x: 0, y: 10)) { true }; attendre(0.4)
            verifier(!m.depot && !c.panneau.glisserSurLIlot(CGPoint(x: 0, y: barre + 40)), "fichier sorti d'une tuile, repassé sur l'encoche : la zone ne s'ouvre pas")
            tenu = false; attendre(0.5)
            m.boutonEnfonce = { NSEvent.pressedMouseButtons & 1 != 0 }
            c.panneau.finDuGlisser()
            // pendant la dictée : rien ne s'ouvre
            occ.dictee = true; c.occupationChangee(); attendre(0.3)
            c.panneau.glisser(CGPoint(x: 0, y: 10)) { true }; attendre(0.3)
            verifier(!m.depot, "pendant la dictée : un glisser n'ouvre rien")
            c.panneau.finDuGlisser()
            occ.dictee = false; c.occupationChangee(); attendre(0.9)
            // le Centre et les fichiers tout en haut (maquette ilot-etagere-rapide.html, étape 6)
            m.clicForme(); attendre(0.9)
            // un nom sur deux lignes (cinq ronds depuis la Concentration : « Télécharge- / ments ») allonge la rangée d'une ligne
            let hCentre = barre + DispositionCentre.plan(ronds: true, cases: true, bande: true, nomsSurDeuxLignes: m.nomsSurDeuxLignes).profondeur
            let hCentreFichiers = barre + DispositionCentre.plan(etagere: true, ronds: true, cases: true, bande: false, nomsSurDeuxLignes: m.nomsSurDeuxLignes).profondeur
            verifier(m.courante == .centre && abs(m.geo[2].x - hCentreFichiers) < 0.5 && m.etagere.count == 3 && PlanCentre.cadre(.etagere, m) != nil,
                     "Centre : les 3 fichiers tout en haut (\(Int(m.geo[2].x)) pt de haut)")
            // un fichier supprimé, un autre déplacé et renommé, pendant que l'accueil est ouvert
            try? FileManager.default.removeItem(at: notes)
            let sous = rayon.appendingPathComponent("Rangé", isDirectory: true)
            try? FileManager.default.createDirectory(at: sous, withIntermediateDirectories: true)
            let photo2 = sous.appendingPathComponent("Photo de vacances.heic")
            try? FileManager.default.moveItem(at: photo, to: photo2)
            // vrai clic sur « Étagère 3 › » dans l'en-tête du Centre
            let ce = PlanCentre.cadreEntete(m.grille)
            let pl = CGPoint(x: ce.minX + 40, y: ce.midY)
            c.panneau.envoyerSouris(.leftMouseDown, en: pl); attendre(0.06); c.panneau.envoyerSouris(.leftMouseUp, en: pl); attendre(0.9)
            verifier(m.courante == .etagere, "vrai clic sur « Étagère 3 › » en haut du Centre : la carte s'ouvre (\(m.courante))")
            verifier(c.etagere.elements.map(\.nom) == ["Contrat.pdf", "Photo de vacances.heic"], "à l'ouverture : le fichier supprimé est retiré, le fichier déplacé suit (\(c.etagere.elements.map(\.nom)))")
            verifier(c.etagere.elements.last?.chemin == SignetsEtagere.cheminReel(photo2), "… avec son nouveau chemin")
            verifier(m.trace.bande <= hc + GeoIlot.aileMax + 0.01, "carte : dans la barre, \(Int(m.trace.bande - hc)) pt de chaque côté (≤ 66)")
            attendre(1.2) { m.boucleActive }
            verifier(!m.boucleActive, "carte posée : aucune boucle d'animation (bouge encore : \(m.ceQuiBouge))")
            // vrai clic sur la première tuile : le fichier s'ouvre (capturé)
            let zc = m.grille.zone(.etagere, haut: 10, bas: 12)
            let pt = CGPoint(x: zc.minX + TuileEtagere.largeur(zc.width) / 2, y: zc.minY + 42 + 8 + 26)
            liensOuverts = []
            c.panneau.envoyerSouris(.leftMouseDown, en: pt); attendre(0.06); c.panneau.envoyerSouris(.leftMouseUp, en: pt); attendre(0.6)
            verifier(liensOuverts.map { SignetsEtagere.cheminReel($0) } == [SignetsEtagere.cheminReel(contrat)], "vrai clic sur une tuile : le fichier est ouvert (capturé, jamais réel)")
            verifier(m.courante == .etagerePile && c.etagere.elements.count == 2, "ouvert : l'îlot se replie (la pile), le fichier reste sur l'étagère")
            // « × » et « Tout vider »
            m.clicForme(); attendre(0.5); m.ouvrirEtagere(); attendre(0.5)
            if let id = c.etagere.elements.first?.id { c.agir(.etagereRetirer(id)) }
            verifier(c.etagere.elements.map(\.nom) == ["Photo de vacances.heic"] && m.courante == .etagere, "« × » : retiré, la carte reste ouverte")
            c.agir(.etagereVider); attendre(0.6)
            verifier(c.etagere.estVide && m.etagere.isEmpty && m.courante == .etagere && fabriquer().etagere.estVide, "« Tout vider » : vide, et le fichier aussi")
            verifier(FileManager.default.fileExists(atPath: contrat.path) && FileManager.default.fileExists(atPath: photo2.path), "vider l'étagère ne touche à aucun fichier")
            m.fermer(); attendre(0.6)
            m.clicForme(); attendre(0.9)
            verifier(m.courante == .centre && abs(m.geo[2].x - hCentre) < 0.5 && m.etagere.isEmpty, "étagère vide : la case du Centre dit « Glisse un fichier ici », même taille")
            m.fermer(); attendre(0.6)
            // réglage éteint
            c.ranger([contrat]); c.activerEtagere(false); attendre(0.3)
            c.panneau.glisser(CGPoint(x: 0, y: 10)) { true }; attendre(0.4)
            verifier(!m.depot && !c.panneau.accepteLesFichiers && !(c.panneau.glisserSurLIlot(CGPoint(x: 0, y: 10))), "réglage éteint : plus de « Déposez ici », la fenêtre refuse les fichiers")
            c.panneau.finDuGlisser()
            m.clicForme(); attendre(0.9)
            verifier(m.courante == .centre && !m.etagereActive, "réglage éteint : la case Étagère du Centre le dit (« Éteinte », Allumer)")
            m.fermer(); attendre(0.8)
        }

        IlotEssai.etagereRapide(c, dossier: dossier, verifier: verifier, attendre: { attendre($0, tant: $1) })
        IlotEssai.centre(c, dossier: dossier, verifier: verifier, attendre: { attendre($0, tant: $1) })
        IlotEssai.modifierCentre(c, dossier: dossier, verifier: verifier, attendre: { attendre($0, tant: $1) })
        IlotEssai.cheminsDuCentre(c, dossier: dossier, verifier: verifier, attendre: { attendre($0, tant: $1) })
        IlotEssai.outils(c, dossier: dossier, decaler: { decalage += $0 }, verifier: verifier, attendre: { attendre($0, tant: $1) })
        IlotEssai.dictees(c, verifier: verifier, attendre: { attendre($0, tant: $1) }, pressePapiers: { pressePapiers }, fenetres: { fenetres })
        IlotEssai.lucarne(c, decaler: { decalage += $0 }, verifier: verifier, attendre: { attendre($0, tant: $1) }, pressePapiers: { pressePapiers })
        IlotEssai.placesLucarne(c, verifier: verifier, attendre: { attendre($0, tant: $1) })
        IlotEssai.verreLucarne(c, verifier: verifier, attendre: { attendre($0, tant: $1) })
        IlotEssai.survolDictees(c, verifier: verifier, attendre: { attendre($0, tant: $1) })
        IlotEssai.secondBrain(c, dossier: dossier, verifier: verifier, attendre: { attendre($0, tant: $1) })
        IlotEssai.bibliotheque(c, dossier: dossier, verifier: verifier, attendre: { attendre($0, tant: $1) },
                               fenetres: { fenetres }, relancer: { fabriquer() })
        IlotEssai.reveilEtCalendrier(c, dossier: dossier, verifier: verifier, attendre: { attendre($0, tant: $1) }, relancer: { fabriquer() })
        IlotEssai.reunion(c, verifier: verifier, attendre: { attendre($0, tant: $1) })
        IlotEssai.concentration(c, dossier: dossier, decaler: { decalage += $0 }, verifier: verifier, attendre: { attendre($0, tant: $1) }, relancer: { fabriquer() })
        IlotEssai.noteApresAppel(dossier: dossier, verifier: verifier, attendre: { attendre($0, tant: $1) })
        IlotEssai.sonDeReunionGarde(dossier: dossier, verifier: verifier, attendre: { attendre($0, tant: $1) })
        IlotEssai.voixSeparees(dossier: dossier, verifier: verifier, attendre: { attendre($0, tant: $1) })
        IlotEssai.bullesAudio(dossier: dossier, verifier: verifier, attendre: { attendre($0, tant: $1) })

        // --- fin : plus rien ne tourne
        c.moteur.fermer(); attendre(1.3)
        verifier(!m.boucleActive, "tout est refermé : aucune boucle d'animation (bouge encore : \(m.ceQuiBouge))")
        c.arreter()
        print(echecs == 0 ? "essai terminé : tout est vert" : "essai terminé : \(echecs) échec(s)")
        return echecs == 0 ? 0 : 1
    }
}
