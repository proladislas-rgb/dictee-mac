import AppKit
import DicteeCore

/// Ce que l'essai capture de l'étagère plus rapide : jamais de vrai AirDrop, jamais de vrai glisser remis au système (il prendrait la
/// vraie souris), jamais le vrai dossier des captures ni les vrais réglages.
@MainActor
enum EssaiEtagere {
    static var envois: [[URL]] = []
    static var finEnvoi: ((EnvoiEtagere.Etat) -> Void)?
    static var airDropPossible = true
    static var app: String? = "Mail"
    static var captures = false
    static var glisses: [[URL]] = []
    static var finGlisser: ((NSDragOperation, NSPoint) -> Void)?
}

extension IlotEssai {
    /// L'étagère plus rapide (maquette design/maquettes/ilot-etagere-rapide.html), de bout en bout dans la fenêtre invisible : la pile dans
    /// l'aile, le Centre avec les fichiers en haut, « Tout » et un fichier glissés hors de l'étagère, « Remettre », AirDrop, les captures
    /// d'écran. De VRAIS clics et de VRAIS glissers de souris (événements remis à la fenêtre de l'îlot, jamais au système) ; le glisser
    /// lui-même n'est jamais confié à macOS : l'essai reçoit les fichiers et dit où il finit.
    @MainActor
    static func etagereRapide(_ c: IlotControleur, dossier: URL, verifier: (Bool, String) -> Void, attendre: (Double, () -> Bool) -> Void) {
        let m = c.moteur, g = m.geometrie
        let hc = Double(m.demiCamera), barre = Double(g.hauteur)
        func pause(_ s: Double) { attendre(s) { true } }
        func clic(_ p: CGPoint, _ apres: Double = 0.5) {
            c.panneau.envoyerSouris(.leftMouseDown, en: p); pause(0.06); c.panneau.envoyerSouris(.leftMouseUp, en: p); pause(apres)
        }
        /// Un vrai glisser de souris qui part de `p` (appui, deux mouvements, relâchement) : la source AppKit le commence.
        func glisserDepuis(_ p: CGPoint) {
            c.panneau.envoyerSouris(.leftMouseDown, en: p); pause(0.05)
            c.panneau.envoyerSouris(.leftMouseDragged, en: CGPoint(x: p.x + 3, y: p.y + 2)); pause(0.03)
            c.panneau.envoyerSouris(.leftMouseDragged, en: CGPoint(x: p.x + 30, y: p.y + 24)); pause(0.05)
            c.panneau.envoyerSouris(.leftMouseUp, en: CGPoint(x: p.x + 30, y: p.y + 24)); pause(0.05)
        }

        print("L'étagère plus rapide")
        let rayon = dossier.appendingPathComponent("Étagère rapide", isDirectory: true)
        try? FileManager.default.createDirectory(at: rayon, withIntermediateDirectories: true)
        func creer(_ nom: String, _ ou: URL? = nil) -> URL { let u = (ou ?? rayon).appendingPathComponent(nom); try? Data("essai".utf8).write(to: u); return u }
        let contrat = creer("Contrat.pdf"), photo = creer("Photo-chantier.heic"), devis = creer("Devis-cuisine.pdf"), plan = creer("Plan-salon.jpg")
        c.panneau.simulerPointeur(forme: false); m.fermer(); pause(0.6)
        c.agir(.etagereVider)
        c.activerEtagere(true); pause(0.2)

        // --- 3 · replié : la pile et le nombre dans l'aile GAUCHE (rien à droite) ; rien ne tourne
        c.ranger([contrat]); pause(1.0)
        verifier(m.courante == .etagerePile && m.resolution.survol == .centre, "un fichier sur l'étagère, rien ne joue : la pile dans l'aile (\(m.courante)) ; au survol, le Centre")
        verifier(m.trace.bandeGauche - hc <= GeoIlot.aileMax + 0.01 && m.trace.bandeGauche - hc > 40, "la pile : \(Int(m.trace.bandeGauche - hc)) pt à gauche de la caméra (≤ 66)")
        verifier(m.trace.bandeDroite - hc <= 6.01, "à droite : rien que la caméra (\(Int(m.trace.bandeDroite - hc)) pt, l'épaule)")
        verifier(PileEtagere.largeur <= CGFloat(GeoIlot.valeurs(.etagerePile, hauteurBarre: barre)[0]) - 6,
                 "la pile et « 10 », mesurés : \(Int(PileEtagere.largeur)) pt, tiennent dans l'aile (\(Int(GeoIlot.valeurs(.etagerePile, hauteurBarre: barre)[0]) - 6) pt utiles)")
        if let f = c.panneau.cadre {
            verifier(Double(f.width) <= (hc + 52) + (hc + 6) + 4.5 && Double(f.height) <= barre + 6.5, "fenêtre de la pile : \(Int(f.width)) × \(Int(f.height)) pt, à peine plus que la forme")
            let droite = Double(f.maxX) - Double(NSScreen.screens.first.map { $0.frame.midX } ?? f.midX)
            verifier(droite <= hc + 6 + 2.5, "… et rien à droite de la caméra au-delà de l'épaule (\(Int(droite - hc)) pt) : les icônes voisines restent à elles")
        }
        attendre(1.0) { m.boucleActive }
        verifier(!m.boucleActive, "la pile posée : aucune boucle d'animation (bouge encore : \(m.ceQuiBouge))")
        // sans encoche (écran externe, MacBook fermé) : pas de pile dans la barre des menus, la fenêtre se cache comme au repos
        m.geometrie.reelle = false; m.donneesChangees(); c.panneau.ajuster()
        attendre(1.5) { c.panneau.estVisible }
        verifier(m.resolution.principal == .repos && m.courante == .repos && !c.panneau.estVisible,
                 "sans encoche, des fichiers sur l'étagère : rien dans la barre des menus, fenêtre cachée (\(m.courante), visible : \(c.panneau.estVisible))")
        c.panneau.glisser(CGPoint(x: -300, y: 500)) { true }; pause(0.5)
        verifier(m.courante == .etagereAppel && c.panneau.estVisible, "sans encoche, un glisser de fichiers : l'îlot appelle quand même (\(m.courante))")
        c.panneau.finDuGlisser(); pause(0.9)
        m.geometrie.reelle = true; m.donneesChangees(); c.panneau.ajuster(); pause(0.9)
        verifier(m.courante == .etagerePile && c.panneau.estVisible, "l'encoche revenue : la pile revient (\(m.courante))")
        // une vidéo occupe l'îlot : la pile disparaît (l'étagère se voit au survol, dans le Centre)
        c.lecture.modele.morceau = MorceauEnCours(titre: "Vlog", app: "essai.lecture", joue: true, duree: 600, position: 12)
        c.lecture.surIlot(true); pause(0.9)
        verifier(m.courante == .lectureCompact && m.pastille == nil, "une vidéo joue : elle a l'îlot, pas de pile ni de bulle (\(m.courante))")
        // l'appel passe par-dessus le compact d'une activité, le temps du glisser
        c.panneau.glisser(CGPoint(x: -300, y: 500)) { true }; pause(0.6)
        verifier(m.courante == .etagereAppel, "glisser de fichiers pendant la vidéo : l'îlot appelle (\(m.courante))")
        c.panneau.finDuGlisser(); pause(0.7)
        verifier(m.courante == .lectureCompact, "glisser fini ailleurs : la vidéo revient")
        c.lecture.modele.morceau = nil; c.lecture.surIlot(false); pause(0.8)
        verifier(m.courante == .etagerePile, "la vidéo partie : la pile revient")

        // --- 6 · survol de l'îlot : le Centre avec les fichiers en haut ; un vrai clic sur un fichier l'ouvre
        c.ranger([photo, devis]); pause(0.4)
        c.panneau.simulerPointeur(forme: true); pause(0.9)
        let hFichiers = barre + DispositionCentre.plan(etagere: true, ronds: !m.rondsCentre.isEmpty, cases: true, bande: false).profondeur
        verifier(m.courante == .centre && abs(m.geo[2].x - hFichiers) < 0.5, "survol : le Centre, les 3 fichiers en haut (\(Int(m.geo[2].x)) pt de haut)")
        verifier(m.geo[2].x + 15 <= Double(IlotMoteur.hauteurMax) && m.trace.bande <= hc + GeoIlot.aileMax + 0.01, "… dans la zone de dessin (ombre comprise) et ≤ 66 pt dans la barre")
        guard let r = PlanCentre.cadre(.etagere, m) else { verifier(false, "la rangée de l'étagère existe"); return }
        EssaiEtagere.glisses = []
        var ouverts: [URL] = []
        let ouvrirAvant = c.ouvrir
        c.ouvrir = { ouverts.append($0) }
        clic(CGPoint(x: r.minX + RangeeEtagere.xFichier(0, largeur: r.width, reste: false), y: r.midY - 4), 0.6)
        verifier(ouverts.map { SignetsEtagere.cheminReel($0) } == [SignetsEtagere.cheminReel(contrat)] && EssaiEtagere.glisses.isEmpty,
                 "vrai clic sur le premier fichier de la rangée : il s'ouvre (capturé), aucun glisser")
        c.ouvrir = ouvrirAvant

        // --- 7 · « Tout » : un vrai glisser de la poignée ; les 3 fichiers partent ensemble, puis « Remettre »
        c.panneau.simulerPointeur(forme: false); pause(0.1); c.panneau.simulerPointeur(forme: true); pause(0.9)
        verifier(m.courante == .centre, "le Centre rouvert")
        glisserDepuis(CGPoint(x: r.minX + RangeeEtagere.xTout(), y: r.midY))
        verifier(EssaiEtagere.glisses.last?.map(\.lastPathComponent) == ["Contrat.pdf", "Photo-chantier.heic", "Devis-cuisine.pdf"],
                 "vrai glisser de « Tout » : un seul glisser avec les 3 fichiers (\(EssaiEtagere.glisses.last?.count ?? 0))")
        verifier(m.glisserSortant && m.courante == .centre, "pendant le glisser : le Centre reste (sa vue porte le glisser)")
        // le pointeur est parti vers Mail : il n'est plus sur l'îlot
        c.panneau.simulerPointeur(forme: false)
        EssaiEtagere.finGlisser?(.copy, NSPoint(x: 600, y: 300)); pause(0.9)
        verifier(c.etagere.estVide && !m.glisserSortant && m.courante == .etagerePartis, "lâchés dans une app : les fichiers quittent l'étagère, l'îlot dit où ils sont partis (\(m.courante))")
        verifier(m.bandeau?.ligne1 == "3 fichiers partis dans Mail", "« \(m.bandeau?.ligne1 ?? "") »")
        verifier([contrat, photo, devis].allSatisfy { FileManager.default.fileExists(atPath: $0.path) }, "les fichiers eux-mêmes n'ont pas bougé")
        verifier(m.trace.bande <= hc + GeoIlot.aileMax + 0.01, "« partis dans Mail » : \(Int(m.trace.bande - hc)) pt dans la barre (≤ 66)")
        // vrai clic sur « Remettre » (à gauche de l'anneau)
        let za = m.grille.zoneAnnonce(.etagerePartis)
        let bw = MesureIlot.bouton(ContenuAnnonce.Bouton(titre: "Remettre"))
        clic(CGPoint(x: za.maxX - ContenuAnnonce.coteCompte - ContenuAnnonce.espaceBoutons - bw / 2, y: za.midY), 0.8)
        verifier(c.etagere.elements.map(\.nom) == ["Contrat.pdf", "Photo-chantier.heic", "Devis-cuisine.pdf"] && m.bandeau == nil && m.courante == .etagerePile,
                 "vrai clic sur « Remettre » : les 3 fichiers reviennent, l'îlot redevient la pile (\(c.etagere.elements.map(\.nom)))")

        // --- un vrai clic (sans glisser) sur « Tout » : la carte Étagère s'ouvre, et reste (épinglée) quand le pointeur s'en va
        c.panneau.simulerPointeur(forme: true); pause(0.9)
        verifier(m.courante == .centre, "survol : le Centre (\(m.courante))")
        let glissesAvantClic = EssaiEtagere.glisses.count
        clic(CGPoint(x: r.minX + RangeeEtagere.xTout(), y: r.midY), 0.9)
        verifier(m.courante == .etagere && EssaiEtagere.glisses.count == glissesAvantClic, "vrai clic sur « Tout » : la carte Étagère, aucun glisser (\(m.courante))")
        c.panneau.simulerPointeur(forme: false); pause(0.6)
        verifier(m.courante == .etagere, "… et elle reste quand le pointeur s'en va (\(m.courante))")
        // VoiceOver « appuie » sur « Tout » (la vue AppKit trouvée par le vrai test de position) : la carte aussi
        m.fermer(); pause(0.8)
        c.panneau.simulerPointeur(forme: true); pause(0.9)
        let sourceTout = c.panneau.sourceFichiers(en: CGPoint(x: r.minX + RangeeEtagere.xTout(), y: r.midY))
        verifier(sourceTout?.accessibilityPerformPress() == true, "VoiceOver : « Tout » a une action (\(sourceTout?.accessibilityLabel() ?? "pas de vue"))")
        pause(0.9)
        verifier(m.courante == .etagere, "… qui ouvre la carte Étagère (\(m.courante))")
        c.panneau.simulerPointeur(forme: false); pause(0.4)

        // --- un seul fichier glissé depuis la carte ; refusé : il reste ; accepté : il part, « Remettre » s'en va seul
        verifier(m.courante == .etagere, "la carte Étagère ouverte")
        let zc = m.grille.zone(.etagere, haut: 10, bas: 12)
        let lt = TuileEtagere.largeur(zc.width)
        let tuile2 = CGPoint(x: zc.minX + lt * 1.5 + TuileEtagere.espace, y: zc.minY + 42 + 8 + 26)
        glisserDepuis(tuile2)
        verifier(EssaiEtagere.glisses.last?.map(\.lastPathComponent) == ["Photo-chantier.heic"], "vrai glisser de la 2e tuile : ce fichier-là seulement")
        EssaiEtagere.finGlisser?([], NSPoint(x: 600, y: 300)); pause(0.5)
        verifier(c.etagere.elements.count == 3 && m.courante == .etagere && !m.glisserSortant, "lâché nulle part (refusé) : il reste, la carte aussi")
        // pris en lien seulement (le Terminal colle le chemin) : le fichier n'est parti nulle part, il reste
        glisserDepuis(tuile2)
        EssaiEtagere.finGlisser?(.link, NSPoint(x: 600, y: 300)); pause(0.5)
        verifier(c.etagere.elements.count == 3 && m.bandeau == nil && m.courante == .etagere, "lâché dans une app qui ne prend qu'un lien : il reste, aucun « parti » (\(m.courante))")
        verifier(VueSourceFichiers.masque(.outsideApplication) == [.copy, .link] && VueSourceFichiers.masque(.withinApplication) == [],
                 "proposé aux autres apps : copie ou lien, jamais « générique » (le Finder déplacerait le fichier) ; à l'îlot lui-même : rien")
        // le « × » d'une tuile (la source du glisser est posée sur la tuile : le « × », au-dessus, doit rester cliquable) : un vrai
        // mouvement de souris sur la 3e tuile pour qu'il paraisse, puis un vrai clic dessus
        let tuile3 = CGPoint(x: zc.minX + lt * 2.5 + TuileEtagere.espace * 2, y: zc.minY + 42 + 8 + 26)
        verifier(c.panneau.survolerSourceFichiers(en: tuile3), "sur la 3e tuile, AppKit trouve bien la source du glisser (test de position réel)")
        pause(0.4)
        clic(CGPoint(x: tuile3.x + lt / 2 - 4 - 9, y: zc.minY + 42 + 8 + 2 + 9), 0.6)
        verifier(c.etagere.elements.map(\.nom) == ["Contrat.pdf", "Photo-chantier.heic"] && EssaiEtagere.glisses.count == 3 && m.courante == .etagere,
                 "vrai clic sur le « × » de la 3e tuile (au survol) : retirée, sans glisser ni fermer la carte (\(c.etagere.elements.map(\.nom)))")
        c.ranger([devis]); pause(0.4)
        glisserDepuis(tuile2)
        EssaiEtagere.app = nil
        EssaiEtagere.finGlisser?(.copy, NSPoint(x: 600, y: 300)); pause(0.6)
        verifier(c.etagere.elements.map(\.nom) == ["Contrat.pdf", "Devis-cuisine.pdf"] && m.bandeau?.ligne1 == "1 fichier parti", "accepté (app inconnue) : « \(m.bandeau?.ligne1 ?? "") »")
        EssaiEtagere.app = "Mail"
        pause(Double(IlotControleur.dureeRemettre) + 0.2)
        verifier(m.bandeau == nil && m.courante == .etagerePile && c.etagere.elements.count == 2, "\(Int(IlotControleur.dureeRemettre)) s plus tard, sans geste : « Remettre » s'en va, le fichier reste parti")
        attendre(1.0) { m.boucleActive }
        verifier(!m.boucleActive, "au repos : aucune boucle (bouge encore : \(m.ceQuiBouge))")
        // glissé sur le panneau AirDrop de macOS (l'extension « AirDrop ») : l'envoi part, le fichier RESTE sur l'étagère
        verifier(EtagereIlot.appDuLacher(bundle: EnvoiAirDropEtat.extensionAirDrop, nom: "AirDrop") == "AirDrop", "le panneau AirDrop se reconnaît à son extension")
        m.clicForme(); pause(0.6); m.ouvrirEtagere(); pause(0.9)
        verifier(m.courante == .etagere, "la carte Étagère rouverte (\(m.courante))")
        glisserDepuis(tuile2)
        EssaiEtagere.app = "AirDrop"
        EssaiEtagere.finGlisser?(.copy, NSPoint(x: 600, y: 300)); pause(0.6)
        verifier(c.etagere.elements.map(\.nom) == ["Contrat.pdf", "Devis-cuisine.pdf"] && m.bandeau?.envoi?.etat == .glisse && m.bandeau?.envoi?.surEtagere == true
                 && m.contenuAnnonce(.etagereEnvoi)?.l1 == "Glissé vers AirDrop" && m.contenuAnnonce(.etagereEnvoi)?.l2 == "Devis-cuisine.pdf \u{00B7} reste sur l\u{2019}étagère",
                 "glissé sur le panneau AirDrop : « Glissé vers AirDrop · reste sur l'étagère » (jamais « Envoi lancé » : rien ne le dit), rien n'est retiré (\(c.etagere.elements.map(\.nom)))")
        EssaiEtagere.app = "Mail"
        pause(EnvoiAirDropEtat.glisse.duree + 0.4)
        verifier(m.bandeau == nil && c.etagere.elements.count == 2, "puis le bandeau s'en va, les fichiers sont toujours là")

        // --- 1 · les zones quittées pendant un glisser ne se rouvrent qu'à 60 pt (il visait un onglet, une barre d'outils sous l'encoche)
        c.panneau.glisser(CGPoint(x: 200, y: 520)) { true }; pause(0.3)
        c.panneau.glisser(CGPoint(x: 0, y: barre + 100)) { true }; pause(0.7)
        verifier(m.depot, "première approche : à 100 pt sous la barre, les zones s'ouvrent")
        c.panneau.glisser(CGPoint(x: 0, y: barre + 400)) { true }; pause(0.7)
        verifier(!m.depot && m.appel, "le pointeur s'en va : les zones se ferment, l'appel reste (\(m.courante))")
        c.panneau.glisser(CGPoint(x: 0, y: barre + 100)) { true }; pause(0.6)
        verifier(!m.depot, "revenu à 100 pt pendant le même glisser : elles restent fermées (\(m.courante))")
        c.panneau.glisser(CGPoint(x: 0, y: barre + 50)) { true }; pause(0.7)
        verifier(m.depot, "à 50 pt : elles se rouvrent (\(m.courante))")
        c.panneau.finDuGlisser(); pause(1.0)
        c.panneau.glisser(CGPoint(x: 0, y: barre + 100)) { true }; pause(0.7)
        verifier(m.depot, "le glisser suivant : de nouveau 140 pt (\(m.courante))")
        c.panneau.finDuGlisser(); pause(1.0)
        verifier(!m.depot && !m.appel && m.courante == .etagerePile, "glisser fini : la pile (\(m.courante))")

        /// Un glisser qui vise « AirDrop » : la forme s'ouvre, le mouvement est rejoué sur la forme ouverte (elle juge le pointeur sur la
        /// forme affichée), puis on s'y arrête un instant (un lâcher en passant irait sur l'étagère).
        func viserAirDrop() {
            c.panneau.glisser(CGPoint(x: 90, y: barre + 60)) { true }; pause(0.5)
            c.panneau.glisser(CGPoint(x: 90, y: barre + 60)) { true }; pause(ZoneDepotEtagere.attenteAirDrop + 0.1)
        }
        // --- 2, 4, 5 · AirDrop : les zones, le lâcher à droite, « Envoi… » puis la réponse du service (jamais de vrai AirDrop)
        EssaiEtagere.envois = []
        c.panneau.glisser(CGPoint(x: 200, y: 520)) { true }; pause(0.3)
        c.panneau.glisser(CGPoint(x: 90, y: barre + 60)) { true }; pause(0.7)
        c.panneau.glisser(CGPoint(x: 90, y: barre + 60)) { true }; pause(0.1)
        verifier(m.depot && m.depotZone == .airdrop, "plus près, à droite : les zones, « AirDrop » s'éclaire")
        // on s'y arrête un instant (un lâcher en passant irait sur l'étagère, essayé plus bas)
        pause(ZoneDepotEtagere.attenteAirDrop + 0.1)
        verifier(c.panneau.deposer([plan], en: CGPoint(x: 90, y: barre + 60)), "lâché sur « AirDrop » : accepté")
        pause(0.4)
        verifier(EssaiEtagere.envois.last == [plan] && m.courante == .etagereEnvoi && m.bandeau?.envoi?.etat == .enCours && c.etagere.elements.count == 2,
                 "AirDrop : le service reçoit le fichier, l'îlot dit « Envoi… » ; rien n'est rangé (\(m.courante))")
        c.panneau.finDuGlisser(); pause(0.3)
        verifier(m.courante == .etagereEnvoi, "le relâchement du bouton ne coupe pas « Envoi… »")
        EssaiEtagere.finEnvoi?(.lance); pause(0.5)
        verifier(m.bandeau?.envoi?.etat == .lance && m.contenuAnnonce(.etagereEnvoi)?.l1 == "Envoi lancé vers AirDrop" && m.contenuAnnonce(.etagereEnvoi)?.l2 == "Plan-salon.jpg",
                 "appareil choisi : « Envoi lancé vers AirDrop », jamais « Envoyé » (rien ne confirme la fin du transfert)")
        verifier(c.etagere.elements.count == 2, "l'étagère n'a pas bougé")
        pause(EnvoiAirDropEtat.lance.duree + 0.3)
        verifier(m.bandeau == nil && m.courante == .etagerePile, "puis l'îlot se range seul")
        // l'envoi annulé APRÈS le choix de l'appareil (dans le panneau) : l'îlot se corrige
        EssaiEtagere.finEnvoi?(.annule); pause(0.5)
        verifier(m.bandeau?.envoi?.etat == .annule && m.contenuAnnonce(.etagereEnvoi)?.l1 == "Annulé", "annulé après « lancé » : l'îlot le dit, « Annulé »")
        pause(2.6)
        EssaiEtagere.finEnvoi?(.lance); pause(0.4)
        verifier(m.bandeau == nil, "une réponse tardive après « Annulé » ne dit plus rien")
        viserAirDrop()
        c.panneau.deposer([plan], en: CGPoint(x: 90, y: barre + 60)); pause(0.3); c.panneau.finDuGlisser()
        EssaiEtagere.finEnvoi?(.annule); pause(0.4)
        verifier(m.bandeau?.envoi?.etat == .annule && m.contenuAnnonce(.etagereEnvoi)?.l2 == "Rien n\u{2019}a été envoyé", "panneau AirDrop annulé : « Annulé · Rien n'a été envoyé »")
        pause(2.4)
        // un fichier déjà sur l'étagère, lâché (depuis le Finder) sur « AirDrop » : il reste sur l'étagère, et le bandeau le dit
        let surEtagere = URL(fileURLWithPath: c.etagere.elements[0].chemin)
        viserAirDrop()
        c.panneau.deposer([surEtagere], en: CGPoint(x: 90, y: barre + 60)); pause(0.3); c.panneau.finDuGlisser()
        EssaiEtagere.finEnvoi?(.lance); pause(0.4)
        verifier(m.bandeau?.envoi?.etat == .lance && m.bandeau?.envoi?.surEtagere == true && c.etagere.elements.count == 2,
                 "un fichier de l'étagère envoyé par AirDrop : « reste sur l'étagère », rien n'est retiré")
        pause(EnvoiAirDropEtat.lance.duree + 0.3)
        EssaiEtagere.airDropPossible = false
        viserAirDrop()
        c.panneau.deposer([plan], en: CGPoint(x: 90, y: barre + 60)); pause(0.3); c.panneau.finDuGlisser()
        verifier(m.bandeau?.envoi?.etat == .indisponible, "AirDrop ne peut pas envoyer (Wi-Fi ou Bluetooth éteint) : « AirDrop indisponible »")
        EssaiEtagere.airDropPossible = true
        pause(3.3)
        // un lâcher EN PASSANT sur « AirDrop » (12/11 : une capture d'écran glissée vers le haut est partie par AirDrop) : il va sur
        // l'étagère, rien n'est envoyé
        let envoisAvant = EssaiEtagere.envois.count, rangesAvant = c.etagere.elements.count
        c.panneau.glisser(CGPoint(x: -90, y: barre + 60)) { true }; pause(0.6)
        c.panneau.glisser(CGPoint(x: -90, y: barre + 60)) { true }; pause(0.2)
        verifier(m.depot && m.depotZone == .etagere, "le glisser arrive par la gauche : « Étagère » éclairée")
        c.panneau.deposer([plan], en: CGPoint(x: 90, y: barre + 60)); pause(0.3); c.panneau.finDuGlisser()
        verifier(EssaiEtagere.envois.count == envoisAvant && c.etagere.elements.count == rangesAvant + 1 && m.bandeau?.vue != .etagereEnvoi,
                 "lâché sur « AirDrop » sans s'y arrêter : rangé sur l'étagère, rien n'est parti par AirDrop")
        if let e = c.etagere.elements.last, e.nom == "Plan-salon.jpg" { c.agir(.etagereRetirer(e.id)) }
        pause(1.6)

        // --- 9 · « Captures d'écran ici » : vrai clic sur l'interrupteur, une capture arrive « Nouveau » ; un autre fichier, non
        let captures = dossier.appendingPathComponent("Captures", isDirectory: true)
        try? FileManager.default.createDirectory(at: captures, withIntermediateDirectories: true)
        let dejaLa = creer("Capture d\u{2019}écran 2026-11-10 à 09.00.00.png", captures)
        EssaiEtagere.captures = false
        m.clicForme(); pause(0.6); m.ouvrirEtagere(); pause(0.9)
        let cc = CarteEtagere.cadreCaptures(m.grille)
        let interrupteur = CGPoint(x: cc.maxX - 12 - InterrupteurIlot.largeur / 2, y: cc.midY)
        verifier(!m.capturesActives && !c.capturesSource.actif, "au départ : éteint, aucun dossier lu")
        clic(interrupteur, 0.8)
        verifier(m.capturesActives && EssaiEtagere.captures && c.capturesSource.actif && c.capturesSource.dossier == captures && !m.capturesAttente,
                 "vrai clic sur l'interrupteur : allumé, le dossier des captures est surveillé (essai : un dossier temporaire)")
        verifier(m.courante == .etagere, "la carte reste ouverte")
        _ = creer("Capture d\u{2019}écran 2026-11-11 à 14.32.10.png", captures)
        _ = creer("Devis-final.pdf", captures)
        attendre(3.5) { c.etagere.elements.count < 3 }
        verifier(c.etagere.elements.map(\.nom) == ["Contrat.pdf", "Devis-cuisine.pdf", "Capture d\u{2019}écran 2026-11-11 à 14.32.10.png"],
                 "une capture arrive sur l'étagère ; la capture déjà là et l'autre fichier, non (\(c.etagere.elements.map(\.nom)))")
        verifier(m.etagere.last?.nouveau == true && m.etagere.first?.nouveau == false, "elle est marquée « Nouveau »")
        verifier(FileManager.default.fileExists(atPath: dejaLa.path), "rien n'est déplacé dans le dossier des captures")
        // le dossier changé dans Capture d'écran : relu avec l'étagère, la surveillance le suit
        let captures2 = dossier.appendingPathComponent("Captures 2", isDirectory: true)
        try? FileManager.default.createDirectory(at: captures2, withIntermediateDirectories: true)
        let dossierCapturesAvant = c.dossierCaptures
        c.dossierCaptures = { captures2 }
        c.relireEtagere(force: true); pause(0.6)
        verifier(c.capturesSource.actif && c.capturesSource.dossier == captures2 && m.capturesActives, "dossier des captures changé : la surveillance passe sur le nouveau")
        _ = creer("Capture d\u{2019}écran 2026-11-11 à 15.00.00.png", captures2)
        attendre(3.5) { c.etagere.elements.count < 4 }
        verifier(c.etagere.elements.last?.nom == "Capture d\u{2019}écran 2026-11-11 à 15.00.00.png", "… et la capture faite là arrive (\(c.etagere.elements.map(\.nom)))")
        c.dossierCaptures = dossierCapturesAvant
        c.relireEtagere(force: true); pause(0.6)
        verifier(c.capturesSource.dossier == captures, "retour au premier dossier")
        m.fermer(); pause(0.8)
        verifier(m.etagere.allSatisfy { !$0.nouveau }, "la carte vue puis fermée : plus « Nouveau »")
        m.clicForme(); pause(0.6); m.ouvrirEtagere(); pause(0.9)
        clic(interrupteur, 0.6)
        verifier(!m.capturesActives && !EssaiEtagere.captures && !c.capturesSource.actif, "second clic : éteint, le dossier n'est plus surveillé")
        // refus de macOS (joué par un dossier fermé) : l'interrupteur revient sur éteint, la ligne dit où rendre l'accès
        let ferme = dossier.appendingPathComponent("Captures fermées", isDirectory: true)
        try? FileManager.default.createDirectory(at: ferme, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: ferme.path)
        let dossierAvant = c.dossierCaptures
        c.dossierCaptures = { ferme }
        clic(interrupteur, 1.0)
        verifier(!m.capturesActives && m.capturesRefusees && !EssaiEtagere.captures && !m.capturesAttente && !c.capturesSource.actif,
                 "accès refusé : éteint, « Accès refusé : ouvrir Réglages Système »")
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ferme.path)
        // dossier absent (disque débranché) : l'interrupteur dit la vérité (éteint), la ligne dit pourquoi ; le réglage reste
        c.dossierCaptures = { dossier.appendingPathComponent("Disque débranché/Captures", isDirectory: true) }
        clic(interrupteur, 1.0)
        verifier(!m.capturesActives && m.capturesIntrouvable && !m.capturesAttente && !c.capturesSource.actif && EssaiEtagere.captures,
                 "dossier introuvable : éteint, « Dossier des captures introuvable », réglage gardé pour le prochain lancement")
        c.dossierCaptures = dossierAvant
        clic(interrupteur, 0.8)
        verifier(m.capturesActives && !m.capturesIntrouvable && c.capturesSource.actif, "le dossier revenu, un clic : allumé de nouveau")
        clic(interrupteur, 0.6)
        verifier(!m.capturesActives && !c.capturesSource.actif && !EssaiEtagere.captures, "puis éteint")

        // --- « Réduire les animations » : la forme saute à sa place, l'appel ne bouge pas
        m.fermer(); pause(0.8)
        m.reduire = true
        c.panneau.glisser(CGPoint(x: -300, y: 500)) { true }; pause(0.05)
        verifier(m.courante == .etagereAppel && m.geo.allSatisfy { $0.fini }, "« Réduire les animations » : l'appel est posé tout de suite")
        c.panneau.finDuGlisser(); pause(0.4)
        m.reduire = false
        attendre(1.0) { m.boucleActive }
        verifier(!m.boucleActive && m.courante == .etagerePile, "fin : la pile, aucune boucle (bouge encore : \(m.ceQuiBouge))")
        c.agir(.etagereVider); pause(0.6)
        verifier(m.courante == .repos, "étagère vidée : l'îlot redevient l'encoche seule")
    }
}
