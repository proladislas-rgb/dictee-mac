import Foundation
import DicteeCore

/// Contrôles de l'îlot « centre d'activités » : géométrie, priorités, pastille, minuteur, rappels, agenda, notifications, commandes dictées.
/// Appelée depuis main.swift (un seul appel).
func controlesIlot() {
    var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Europe/Paris")!
    let t0 = cal.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 14, minute: 32))!

    groupe("Îlot : géométrie")
    for (barre, demi) in [(32.0, 100.0), (33.0, 90.0), (37.0, 92.0)] {
        for v in VueIlot.allCases {
            let g = GeoIlot.valeurs(v, hauteurBarre: barre)
            let p = TraceIlot.calculer(g, demiCamera: demi, barre: barre)
            verifier(g.count == 7 && p.bande <= demi + GeoIlot.aileMax + 0.001, "\(v.rawValue) (caméra \(Int(2 * demi)), barre \(Int(barre))) : dans la barre, \(String(format: "%.0f", p.bande - demi)) pt de chaque côté de la caméra, ≤ 66")
            if GeoIlot.profondeur(v) > 0 {
                verifier(p.corps >= p.bande + 40, "\(v.rawValue) : le corps (sous la barre) est plus large que le cou")
            }
        }
    }
    groupe("Îlot : volume et luminosité (touches du clavier)")
    do {
        typealias E = EvenementNiveau
        // décodage des événements « systemDefined » : code dans les 16 bits du haut, 0xA enfoncée / 0xB relâchée, bit 0 = répétition
        verifier(E.decoder(sousType: 8, data1: 0x0000_0A00) == E(touche: .volumePlus, enfoncee: true), "data1 0x0A00 : volume +, enfoncée")
        verifier(E.decoder(sousType: 8, data1: 0x0001_0A01) == E(touche: .volumeMoins, enfoncee: true, repetition: true), "data1 0x10A01 : volume −, répétition")
        verifier(E.decoder(sousType: 8, data1: 0x0007_0B00) == E(touche: .muet, enfoncee: false), "data1 0x70B00 : muet, relâchée")
        verifier(E.decoder(sousType: 8, data1: 0x0002_0A00)?.touche == .luminositePlus && E.decoder(sousType: 8, data1: 0x0003_0A00)?.touche == .luminositeMoins, "codes 2 et 3 : luminosité + et −")
        verifier(E.decoder(sousType: 7, data1: 0x0000_0A00) == nil, "sous-type 7 (boutons de souris) : ignoré")
        verifier(E.decoder(sousType: 8, data1: 0x0010_0A00) == nil && E.decoder(sousType: 8, data1: 0x0015_0A00) == nil, "lecture (16), clavier rétroéclairé (21) : pas pour nous")
        verifier(E.decoder(sousType: 8, data1: 0x0000_0C00) == nil, "état inconnu : ignoré")
        verifier(ToucheNiveau.allCases.allSatisfy { t in [true, false].allSatisfy { d in [true, false].allSatisfy { r in
            let e = E(touche: t, enfoncee: d, repetition: r); return E.decoder(sousType: 8, data1: e.data1) == e } } }, "aller-retour data1 pour les 5 touches")
        verifier(ToucheNiveau.muet.genre == .volume && ToucheNiveau.luminositeMoins.genre == .luminosite, "genres")

        // pas : 16 crans (1/16 comme macOS), 64 avec ⌥⇧, calés sur la grille, bornés
        typealias P = PasNiveau
        verifier(P.suivant(0.5, sens: 1, fin: false) == 0.5625 && P.suivant(0.5, sens: -1, fin: false) == 0.4375, "0,5 : un cran = 1/16")
        verifier(P.suivant(0.30, sens: 1, fin: false) == 0.3125 && P.suivant(0.30, sens: -1, fin: false) == 0.25, "0,30 (réglé ailleurs) : recalé sur la grille des crans")
        verifier(P.suivant(0.5, sens: 1, fin: true) == 0.515625 && P.suivant(0.5, sens: -1, fin: true) == 0.484375, "⌥⇧ : un quart de cran (1/64)")
        verifier(P.suivant(1, sens: 1, fin: false) == 1 && P.suivant(0, sens: -1, fin: false) == 0 && P.suivant(0.98, sens: 1, fin: false) == 1, "bornes 0 et 1")
        var v = 0.0; for _ in 0..<16 { v = P.suivant(v, sens: 1, fin: false) }
        verifier(v == 1, "16 crans de 0 : exactement 1")
        verifier(P.suivant(0.5624, sens: 1, fin: false) == 0.5625, "0,5624 (arrondi par l'appareil) sans recalage : resterait sur place")
        verifier(P.recaler(lu: 0.5617, ecrit: 0.5625) == 0.5625 && P.recaler(lu: 0.30, ecrit: 0.5625) == 0.30 && P.recaler(lu: 0.4, ecrit: nil) == 0.4,
                 "recalage sur la valeur écrite (et seulement si elle est proche)")
        verifier(P.suivant(P.recaler(lu: 0.5617, ecrit: 0.5625), sens: 1, fin: false) == 0.625, "relu 0,5617 après 0,5625 : « + » monte bien à 10/16")
        // touches de modification
        verifier(P.mode(option: false, maj: false, controle: false, commande: false) == false && P.mode(option: true, maj: true, controle: false, commande: false) == true,
                 "sans touche : un cran ; ⌥⇧ : petits pas")
        verifier(P.mode(option: true, maj: false, controle: false, commande: false) == nil && P.mode(option: false, maj: true, controle: false, commande: false) == nil
                 && P.mode(option: false, maj: false, controle: true, commande: false) == nil && P.mode(option: true, maj: true, controle: false, commande: true) == nil,
                 "⌥ seul (réglages Son de macOS), ⇧ seul, ⌃, ⌘ : laissés à macOS")
        // le niveau après une touche
        let coupe = NiveauIlot(genre: .volume, valeur: 0.5, muet: true)
        verifier(P.apres(coupe, touche: .volumePlus, fin: false) == NiveauIlot(genre: .volume, valeur: 0.5625), "son coupé + volume + : le son revient, un cran plus haut")
        verifier(P.apres(coupe, touche: .muet, fin: false) == NiveauIlot(genre: .volume, valeur: 0.5) && P.apres(NiveauIlot(genre: .volume, valeur: 0.5), touche: .muet, fin: false).muet,
                 "muet : bascule, le volume ne change pas")
        verifier(P.apres(NiveauIlot(genre: .luminosite, valeur: 0.3), touche: .luminositeMoins, fin: false) == NiveauIlot(genre: .luminosite, valeur: 0.25), "luminosité − : un cran")
        verifier(NiveauIlot(genre: .luminosite, valeur: 2, muet: true) == NiveauIlot(genre: .luminosite, valeur: 1), "luminosité : bornée, jamais « muette »")
        // symboles
        verifier(NiveauIlot(genre: .volume, valeur: 0).symbole == "speaker.slash.fill" && coupe.symbole == "speaker.slash.fill" && coupe.affiche == 0,
                 "zéro ou muet : haut-parleur barré, barre vide")
        verifier(NiveauIlot(genre: .volume, valeur: 0.2).symbole == "speaker.wave.1.fill" && NiveauIlot(genre: .volume, valeur: 0.5).symbole == "speaker.wave.2.fill"
                 && NiveauIlot(genre: .volume, valeur: 0.9).symbole == "speaker.wave.3.fill" && NiveauIlot(genre: .luminosite, valeur: 0.1).symbole == "sun.max.fill",
                 "une, deux, trois ondes ; le soleil")
        verifier(NiveauIlot(genre: .volume, valeur: 0.5625).pourcent == 56, "VoiceOver : 56 %")

        // aiguillage : appui, répétitions, relâchement
        typealias A = AiguillageNiveau
        let oui = A.Conditions(reglage: true, ilot: true, reglable: true)
        var ai = A()
        verifier(ai.recevoir(E(touche: .volumePlus, enfoncee: true), fin: false, conditions: oui) == .appliquer(.volumePlus, fin: false), "appui : avalé et appliqué")
        verifier(ai.recevoir(E(touche: .volumePlus, enfoncee: true, repetition: true), fin: false, conditions: oui) == .appliquer(.volumePlus, fin: false), "touche tenue : chaque répétition est un cran")
        verifier(ai.recevoir(E(touche: .volumePlus, enfoncee: false), fin: false, conditions: oui) == .avaler && !ai.avalee(.volumePlus), "relâchement : avalé (macOS n'a jamais vu l'appui)")
        verifier(ai.recevoir(E(touche: .volumePlus, enfoncee: false), fin: false, conditions: oui) == .laisser, "relâchement sans appui avalé : laissé")
        for (nom, c) in [("réglage éteint", A.Conditions(reglage: false, ilot: true, reglable: true)), ("îlot occupé (dictée, alerte)", A.Conditions(reglage: true, ilot: false, reglable: true)),
                         ("sortie sans volume réglable (HDMI) ou DisplayServices absent", A.Conditions(reglage: true, ilot: true, reglable: false))] {
            var b = A()
            verifier(b.recevoir(E(touche: .volumeMoins, enfoncee: true), fin: false, conditions: c) == .laisser
                     && b.recevoir(E(touche: .volumeMoins, enfoncee: true, repetition: true), fin: false, conditions: oui) == .laisser
                     && b.recevoir(E(touche: .volumeMoins, enfoncee: false), fin: false, conditions: oui) == .laisser, "\(nom) : appui, répétitions et relâchement restent à macOS")
        }
        var b = A()
        verifier(b.recevoir(E(touche: .volumePlus, enfoncee: true), fin: nil, conditions: oui) == .laisser, "⌥ seul : laissé à macOS")
        verifier(b.recevoir(E(touche: .luminositePlus, enfoncee: true), fin: true, conditions: oui) == .appliquer(.luminositePlus, fin: true), "⌥⇧ luminosité + : petit pas")
        verifier(b.recevoir(E(touche: .luminositePlus, enfoncee: true, repetition: true), fin: true, conditions: A.Conditions(reglage: true, ilot: false, reglable: false)) == .avaler,
                 "tenue pendant qu'une dictée commence : avalée sans rien faire jusqu'au relâchement")
        verifier(b.recevoir(E(touche: .luminositePlus, enfoncee: false), fin: true, conditions: oui) == .avaler, "puis le relâchement est avalé aussi")
        var mu = A()
        verifier(mu.recevoir(E(touche: .muet, enfoncee: true), fin: false, conditions: oui) == .appliquer(.muet, fin: false)
                 && mu.recevoir(E(touche: .muet, enfoncee: true, repetition: true), fin: false, conditions: oui) == .avaler, "muet tenu : une seule bascule")
        // une touche tenue de 0,25 : 1 appui + 20 répétitions, jamais au-delà de 1
        var tenue = A(), n = NiveauIlot(genre: .volume, valeur: 0.25), vus: [Double] = []
        for i in 0...20 {
            if case .appliquer(let t, let f) = tenue.recevoir(E(touche: .volumePlus, enfoncee: true, repetition: i > 0), fin: false, conditions: oui) {
                n = P.apres(n, touche: t, fin: f); vus.append(n.valeur)
            }
        }
        verifier(vus.count == 21 && vus.prefix(12) == ArraySlice((5...16).map { Double($0) / 16 }) && vus.allSatisfy { $0 <= 1 } && n.valeur == 1,
                 "touche tenue depuis 0,25 : 5/16, 6/16… puis 1, sans dépasser")

        // la barre : sur son ressort, elle suit une touche tenue sans marche et se pose vite
        var r = RessortIlot(0.25, reponse: JaugeNiveau.reponse, amortissement: JaugeNiveau.amortissement)
        var x = 0.25, maxi = 0.0, recule = false
        for k in 0..<8 {
            JaugeNiveau.viser(&r, vers: 0.25 + Double(k + 1) / 16, reduire: false)
            for _ in 0..<5 { r.avancer(1.0 / 60); recule = recule || r.x < x - 1e-9; x = r.x; maxi = max(maxi, r.x) }
        }
        verifier(!recule, "touche tenue (un cran toutes les 83 ms) : la barre ne recule jamais")
        var t = 0.0
        while !r.fini, t < 2 { r.avancer(1.0 / 60); t += 1.0 / 60; maxi = max(maxi, r.x) }
        verifier(r.fini && t < 0.75 && maxi <= 0.75 + 0.01, "après la dernière touche : posée en \(Int(t * 1000)) ms, presque sans rebond (max \(String(format: "%.3f", maxi)))")
        var rr = RessortIlot(0.2, reponse: JaugeNiveau.reponse, amortissement: JaugeNiveau.amortissement)
        JaugeNiveau.viser(&rr, vers: 1.4, reduire: true)
        verifier(rr.fini && rr.x == 1, "« Réduire les animations » : la barre saute à sa place (bornée à 1)")
        let bar = JaugeNiveau.barre(demiCamera: 100, cou: 60)
        verifier(bar.x == 108 && bar.largeur == 44 && bar.x + bar.largeur <= 100 + 60 - 8, "la barre : 44 pt, de 8 pt après la caméra à 8 pt du cou")

        // l'îlot : 1,5 s par-dessus l'activité, la bulle ne bouge pas
        var e = EtatIlot(); e.lecture = true; e.bandeau = .volume
        verifier(ArbitrageIlot.resoudre(e) == ResolutionIlot(principal: .volume, survol: nil, verrou: true, pastille: nil), "volume pendant une vidéo : l'îlot montre le volume, pas de bulle")
        e.minuteur = true
        verifier(ArbitrageIlot.resoudre(e).pastille == .minuteur, "vidéo + minuteur en bulle : la bulle reste le minuteur")
        e.bandeau = nil
        verifier(ArbitrageIlot.resoudre(e).principal == .lectureCompact && ArbitrageIlot.resoudre(e).pastille == .minuteur, "puis la vidéo revient")
        e.bandeau = .telecharge
        verifier(ArbitrageIlot.resoudre(e).pastille == .lecture, "un autre bandeau garde sa règle (la lecture en bulle)")
        verifier(VueIlot.volume.estBandeau && VueIlot.luminosite.estNiveau && !VueIlot.telecharge.estNiveau && GeoIlot.profondeur(.volume) == 0, "volume et luminosité : des bandeaux compacts")
    }
    controlesClaude(t0)
    groupe("Îlot : Téléchargé (fichiers arrivés dans Téléchargements)")
    do {
        typealias F = FiltreTelechargements
        verifier(F.estFini("Contrat-signé.pdf") && F.estFini("Photo.HEIC") && F.estFini("archive.tar.gz") && F.estFini("Lisez-moi"), "fichiers finis : pdf, heic, tar.gz, sans extension")
        for n in ["Contrat.pdf.crdownload", "Unconfirmed 41521.crdownload", "Film.mp4.download", "Film.mp4.part", "image.tmp", "x.opdownload", "y.PART"] {
            verifier(!F.estFini(n), "« \(n) » : téléchargement en cours, ignoré")
        }
        verifier(!F.estFini(".DS_Store") && !F.estFini(".Contrat.pdf.icloud") && !F.estFini("~$Devis.docx") && !F.estFini(""), "cachés (.DS_Store, .icloud), verrou de Word, vide : ignorés")
        verifier(F.cible(deEnCours: "Contrat.pdf.part") == "Contrat.pdf" && F.cible(deEnCours: "Contrat.pdf") == nil, "« Contrat.pdf.part » deviendra « Contrat.pdf »")

        verifier(FormatTaille.texte(2_400_000) == "2,4\u{00A0}Mo", "2 400 000 octets : « 2,4 Mo » (virgule, espace insécable)")
        verifier(FormatTaille.texte(2_000_000) == "2\u{00A0}Mo" && FormatTaille.texte(850_000) == "850\u{00A0}Ko", "« 2 Mo » (jamais « 2,0 »), « 850 Ko »")
        verifier(FormatTaille.texte(0) == "0\u{00A0}octet" && FormatTaille.texte(1) == "1\u{00A0}octet" && FormatTaille.texte(512) == "512\u{00A0}octets", "0 octet, 1 octet, 512 octets")
        verifier(FormatTaille.texte(999_600) == "1\u{00A0}Mo" && FormatTaille.texte(1_234_000_000) == "1,2\u{00A0}Go", "999 600 octets : « 1 Mo » (pas « 1000 Ko ») ; « 1,2 Go »")

        // la veille : rien pour ce qui existe, un fichier fini annoncé une fois après 1 s de taille stable
        var tailles: [String: Int64] = ["Ancien.pdf": 1000, "Vide.txt": 0]
        func mesure(_ n: String) -> EntreeDossier? { tailles[n].map { EntreeDossier(nom: n, taille: $0) } }
        var noms: [String] { Array(tailles.keys) }
        var w = VeilleTelechargements(existants: noms.compactMap(mesure))
        verifier(w.lire(noms: noms, a: t0, mesure: mesure).isEmpty && w.prochaineRelecture == nil, "au lancement : rien d'annoncé, aucune relecture programmée")
        tailles["Rapport.pdf.crdownload"] = 500_000
        verifier(w.lire(noms: noms, a: t0, mesure: mesure).isEmpty && w.prochaineRelecture == nil, "« .crdownload » qui grossit : rien, et aucune relecture (le renommage réveillera)")
        tailles["Rapport.pdf.crdownload"] = nil; tailles["Rapport.pdf"] = 2_400_000
        verifier(w.lire(noms: noms, a: t0.addingTimeInterval(5), mesure: mesure).isEmpty, "renommé en « Rapport.pdf » : pas tout de suite (taille à confirmer)")
        verifier(w.prochaineRelecture == t0.addingTimeInterval(6), "une seule relecture, 1 s plus tard")
        let r1 = w.lire(noms: noms, a: t0.addingTimeInterval(6), mesure: mesure)
        verifier(r1.map(\.nom) == ["Rapport.pdf"] && r1.first?.taille == 2_400_000, "1 s plus tard, même taille : « Rapport.pdf » est annoncé")
        verifier(w.lire(noms: noms, a: t0.addingTimeInterval(9), mesure: mesure).isEmpty && w.prochaineRelecture == nil, "relu ensuite : jamais deux fois ; plus rien n'attend")
        // un fichier écrit sur place (AirDrop, curl) : on attend que sa taille ne bouge plus
        tailles["Video.mov"] = 10
        _ = w.lire(noms: noms, a: t0.addingTimeInterval(10), mesure: mesure)
        tailles["Video.mov"] = 4_000
        verifier(w.lire(noms: noms, a: t0.addingTimeInterval(11), mesure: mesure).isEmpty && w.prochaineRelecture == t0.addingTimeInterval(12), "taille qui change encore : on attend une seconde de plus")
        verifier(w.lire(noms: noms, a: t0.addingTimeInterval(12), mesure: mesure).map(\.nom) == ["Video.mov"], "puis stable : annoncé")
        // Firefox : le fichier final vide est posé d'avance, le « .part » le remplace à la fin
        tailles["Doc.pdf"] = 0; tailles["Doc.pdf.part"] = 30_000
        verifier(w.lire(noms: noms, a: t0.addingTimeInterval(20), mesure: mesure).isEmpty && w.prochaineRelecture == nil, "Firefox : « Doc.pdf » vide + « Doc.pdf.part » : rien, aucune relecture")
        tailles["Doc.pdf.part"] = nil; tailles["Doc.pdf"] = 30_000
        _ = w.lire(noms: noms, a: t0.addingTimeInterval(30), mesure: mesure)
        verifier(w.lire(noms: noms, a: t0.addingTimeInterval(31), mesure: mesure).map(\.nom) == ["Doc.pdf"], "le « .part » remplace le fichier vide : « Doc.pdf » annoncé")
        verifier(w.lire(noms: noms, a: t0.addingTimeInterval(32), mesure: mesure).isEmpty, "le fichier vide du lancement (Vide.txt) n'est jamais annoncé")
        // supprimé puis retéléchargé sous le même nom : de nouveau annoncé
        tailles["Rapport.pdf"] = nil; _ = w.lire(noms: noms, a: t0.addingTimeInterval(40), mesure: mesure)
        tailles["Rapport.pdf"] = 2_400_000; _ = w.lire(noms: noms, a: t0.addingTimeInterval(41), mesure: mesure)
        verifier(w.lire(noms: noms, a: t0.addingTimeInterval(42), mesure: mesure).map(\.nom) == ["Rapport.pdf"], "supprimé puis retéléchargé : annoncé de nouveau")
        // un dossier (AirDrop d'un dossier) : suivi par sa date, annoncé sans taille
        var w2 = VeilleTelechargements(existants: [])
        let dd = EntreeDossier(nom: "Photos vacances", taille: 0, modification: t0, dossier: true)
        _ = w2.lire(noms: [dd.nom], a: t0, mesure: { _ in dd })
        verifier(w2.lire(noms: [dd.nom], a: t0.addingTimeInterval(1), mesure: { _ in dd }) == [dd], "un dossier arrivé : annoncé quand sa date ne bouge plus")
        // un fichier qui grossit sans fin n'est plus suivi au bout d'une demi-heure
        var w3 = VeilleTelechargements(existants: [])
        var k: Int64 = 1
        for i in 0...1900 where i % 100 == 0 { k += 1; _ = w3.lire(noms: ["flux.bin"], a: t0.addingTimeInterval(Double(i)), mesure: { EntreeDossier(nom: $0, taille: k) }) }
        verifier(w3.prochaineRelecture == nil, "un fichier qui grossit plus d'une demi-heure n'est plus relu (aucune relecture sans fin)")

        // AirDrop : l'agent de quarantaine est sharingd
        verifier(FichierTelecharge.estAirDrop(quarantaine: "0081;6731f2a0;sharingd;8A1B-22") && !FichierTelecharge.estAirDrop(quarantaine: "0081;6731f2a0;Chrome;8A1B")
                 && !FichierTelecharge.estAirDrop(quarantaine: nil) && !FichierTelecharge.estAirDrop(quarantaine: "abimé"), "AirDrop reconnu à l'agent « sharingd » (pas Chrome, ni sans attribut)")

        // la rafale : un bandeau pour plusieurs fichiers
        let u = URL(fileURLWithPath: "/tmp/Téléchargements")
        let contrat = FichierTelecharge(url: u.appendingPathComponent("Contrat-signé.pdf"), taille: 2_400_000)
        var r = RafaleTelechargements()
        verifier(r.ajouter([contrat], a: t0) == false && r.titre == "Contrat-signé.pdf" && r.sousTitre == "Téléchargé \u{00B7} 2,4\u{00A0}Mo", "un fichier : son nom, « Téléchargé · 2,4 Mo »")
        let photo = FichierTelecharge(url: u.appendingPathComponent("Photo.heic"), taille: 600_000)
        let note = FichierTelecharge(url: u.appendingPathComponent("Note.txt"), taille: 100_000)
        verifier(r.ajouter([photo], a: t0.addingTimeInterval(1.5)) && r.ajouter([note, photo], a: t0.addingTimeInterval(3)), "deux autres en rafale : ils rejoignent le bandeau (sans doublon)")
        verifier(r.titre == "3 fichiers téléchargés" && r.sousTitre == "Dans Téléchargements \u{00B7} 3,1\u{00A0}Mo", "« 3 fichiers téléchargés », taille totale")
        verifier(r.ajouter([contrat], a: t0.addingTimeInterval(7.5)) == false && r.titre == "Contrat-signé.pdf", "plus de 4 s après : nouvelle annonce")
        var ra = RafaleTelechargements()
        ra.ajouter([FichierTelecharge(url: u.appendingPathComponent("IMG_2041.HEIC"), taille: 3_100_000, airdrop: true)], a: t0)
        verifier(ra.sousTitre == "Reçu par AirDrop \u{00B7} 3,1\u{00A0}Mo", "AirDrop : « Reçu par AirDrop · 3,1 Mo »")
        ra.ajouter([FichierTelecharge(url: u.appendingPathComponent("IMG_2042.HEIC"), taille: 2_900_000, airdrop: true)], a: t0.addingTimeInterval(1))
        verifier(ra.titre == "2 fichiers reçus" && ra.sousTitre == "Par AirDrop \u{00B7} 6\u{00A0}Mo", "deux par AirDrop : « 2 fichiers reçus », « Par AirDrop · 6 Mo »")
        var rd = RafaleTelechargements()
        rd.ajouter([FichierTelecharge(url: u.appendingPathComponent("Photos vacances"), taille: nil, airdrop: true)], a: t0)
        verifier(rd.sousTitre == "Reçu par AirDrop", "un dossier : pas de taille")

        verifier(VueIlot.telecharge.estBandeau && GeoIlot.ajusteAuContenu(.telecharge) && GeoIlot.profondeur(.telecharge) >= 72, "Téléchargé : un bandeau qui épouse son contenu, assez haut pour l'icône de 38 pt (16 + 38 + 16)")
        verifier(ArbitrageIlot.resoudre({ var e = EtatIlot(); e.lecture = true; e.bandeau = .telecharge; return e }()).pastille == .lecture,
                 "fichier arrivé pendant une vidéo : la vidéo passe en bulle le temps de l'annonce")
    }

    groupe("Îlot : micro coupé")
    do {
        let d = RaccourciIlot.microParDefaut
        verifier(d.libelle == "\u{2303}\u{2325}M" && d.texte == "ctrl+opt+m" && d.estValide, "par défaut : ⌃⌥M, rangé « ctrl+opt+m », valide")
        verifier(RaccourciIlot(texte: "ctrl+opt+m") == d && RaccourciIlot(texte: d.texte) == d, "« ctrl+opt+m » relu à l'identique")
        verifier(RaccourciIlot(texte: "ctrl+opt++")?.touche == "+" && RaccourciIlot(texte: "ctrl+opt++")?.controle == true, "la touche « + » elle-même")
        verifier(RaccourciIlot(texte: "") == nil && RaccourciIlot(texte: "ctrl+opt+mm") == nil && RaccourciIlot(texte: "hyper+m") == nil, "textes abîmés refusés")
        verifier(RaccourciIlot(touche: "M", controle: true, option: true) == d, "la touche est rangée en minuscule")
        verifier(d.correspond(touche: "m", controle: true, option: true, maj: false, commande: false) && d.correspond(touche: "M", controle: true, option: true, maj: false, commande: false),
                 "⌃⌥M reconnu (minuscule ou capitale)")
        verifier(!d.correspond(touche: "m", controle: true, option: true, maj: false, commande: true) && !d.correspond(touche: "m", controle: true, option: false, maj: false, commande: false)
                 && !d.correspond(touche: ",", controle: true, option: true, maj: false, commande: false), "⌃⌥⌘M, ⌃M, ⌃⌥, : pas le raccourci")
        verifier(!RaccourciIlot(touche: "m", option: true).estValide, "⌥M seul : refusé (il tape « µ »)")
        verifier(!RaccourciIlot(touche: "m", commande: true).estValide, "⌘M seul : refusé (réduire la fenêtre)")
        verifier(!RaccourciIlot(touche: "m", option: true, maj: true).estValide, "⌥⇧M : refusé (ni ⌃ ni ⌘)")
        verifier(!RaccourciIlot(touche: "n", option: true, commande: true).estValide && !RaccourciIlot(touche: "q", controle: true, commande: true).estValide,
                 "⌥⌘N (noter la réunion) et ⌃⌘Q (verrouiller) : déjà pris")
        verifier(RaccourciIlot(touche: "m", maj: true, commande: true).estValide && RaccourciIlot(touche: "u", controle: true, commande: true).estValide, "⇧⌘M, ⌃⌘U : acceptés")
        verifier(RaccourciIlot(touche: " ", controle: true, option: true).libelle == "\u{2303}\u{2325}Espace", "la barre d'espace s'écrit « Espace »")

        var w = VeilleMicro()
        typealias R = VeilleMicro.Reponse
        verifier(w.systeme(coupe: false) == .rien && !w.coupe, "lancement, micro ouvert : rien")
        verifier(w.basculer() == R(commande: .couper) && w.coupe, "raccourci : on coupe ; l'îlot montre « Coupé » tout de suite")
        verifier(w.systeme(coupe: true) == .rien && w.coupe, "l'écho de notre commande ne change rien")
        verifier(w.basculer() == R(commande: .rouvrir, annonce: .ouvert) && !w.coupe, "raccourci : on rouvre, bandeau « Micro ouvert »")
        verifier(w.systeme(coupe: false) == .rien, "l'écho de la réouverture ne change rien")
        verifier(w.systeme(coupe: true) == .rien && w.coupe, "coupé dans Réglages Système : l'îlot suit, sans bandeau")
        verifier(w.systeme(coupe: false) == R(annonce: .ouvert) && !w.coupe, "rouvert dans Réglages Système : l'îlot suit, « Micro ouvert »")
        verifier(w.rouvrir() == .rien, "« Rouvrir » sur un micro déjà ouvert : rien")

        var x = VeilleMicro()
        _ = x.basculer()
        verifier(x.dictee(enCours: true) == R(commande: .rouvrir) && x.coupe && x.rouvertPourDictee, "fn pendant que c'est coupé : la dictée rouvre le micro (l'îlot garde « coupé »)")
        verifier(x.systeme(coupe: false) == .rien && x.coupe, "l'écho de cette réouverture : rien, pas de « Micro ouvert »")
        verifier(x.dictee(enCours: true) == .rien, "la dictée déjà en cours : pas deux fois")
        verifier(x.dictee(enCours: false) == R(commande: .couper) && x.coupe && !x.rouvertPourDictee, "fin de la dictée : recoupé")
        verifier(x.systeme(coupe: true) == .rien, "l'écho du recoupage : rien")
        // une notification en retard (ouvert) lue APRÈS la fin : le contrôleur relit l'état réel (coupé) au moment de la traiter
        verifier(x.systeme(coupe: true) == .rien && x.coupe, "une notification en retard relue telle qu'est le micro maintenant : rien ne bouge")
        verifier(x.dictee(enCours: true, memeMicro: false) == .rien && x.dictee(enCours: false) == .rien,
                 "la dictée écoute un autre micro (AirPods par défaut, dictée sur le micro du Mac) : on ne rouvre pas celui que l'appel entend")
        _ = x.dictee(enCours: true)
        verifier(x.basculer() == R(annonce: .ouvert) && !x.coupe && !x.rouvertPourDictee, "raccourci pendant une dictée qui l'a rouvert : il reste ouvert (pas de commande), « Micro ouvert »")
        verifier(x.dictee(enCours: false) == .rien && !x.coupe, "fin de cette dictée : on ne recoupe pas")
        _ = x.dictee(enCours: true)
        verifier(x.basculer() == .rien && x.coupe && x.rouvertPourDictee, "raccourci pendant une dictée : couper attend la fin (sinon la dictée n'entend plus rien)")
        verifier(x.dictee(enCours: false) == R(commande: .couper), "fin de la dictée : coupé")
        _ = x.basculer()
        _ = x.dictee(enCours: true, memeMicro: false)
        verifier(x.basculer() == R(commande: .couper), "pendant une dictée sur un autre micro : couper tout de suite")
        _ = x.dictee(enCours: false)
        _ = x.dictee(enCours: true)
        verifier(x.systeme(coupe: true) == .rien && !x.rouvertPourDictee && x.dictee(enCours: false) == .rien, "recoupé ailleurs pendant la dictée : rien à recouper à la fin")

        var y = VeilleMicro()
        _ = y.basculer(); y.commandeEchouee(.couper)
        verifier(!y.coupe, "un micro qui ne se coupe pas : l'îlot reste sur « ouvert »")
        _ = y.systeme(coupe: true); _ = y.dictee(enCours: true); y.commandeEchouee(.rouvrir)
        verifier(y.coupe && !y.rouvertPourDictee && y.dictee(enCours: false) == .rien, "réouverture refusée pour la dictée : il reste coupé, rien à recouper")
        _ = y.dictee(enCours: true)
        verifier(y.oublier() == R(commande: .couper) && !y.coupe && !y.dicteeEnCours, "réglage éteint pendant une dictée qui l'a rouvert : recoupé, puis tout est oublié")
        verifier(y.oublier() == .rien, "réglage éteint, micro simplement coupé : on le laisse comme il est (c'est l'état du Mac)")

        verifier(MicroIlot.volumeARendre(garde: 0.62) == 0.62 && MicroIlot.volumeARendre(garde: nil) == 0.75 && MicroIlot.volumeARendre(garde: 0) == 0.75 && MicroIlot.volumeARendre(garde: 3) == 1,
                 "micro sans muet : on rend l'ancien volume (75 % s'il était nul ou inconnu)")
        verifier(MicroIlot.estCoupe(volume: 0) && !MicroIlot.estCoupe(volume: 0.3), "volume nul = coupé")

        verifier(!VueIlot.microCompact.estBandeau && GeoIlot.profondeur(.microCompact) == 0, "micro coupé : une activité dans les ailes, rien sous la barre")
        verifier(GeoIlot.valeurs(.microCompact, hauteurBarre: 32)[0] + GeoIlot.valeurs(.microCompact, hauteurBarre: 32)[3] <= GeoIlot.aileMax,
                 "aile du micro coupé : cou + épaule ≤ 66 pt")
        verifier(GeoIlot.ajusteAuContenu(.microEtendu) && GeoIlot.profondeur(.microEtendu) >= 72 && !GeoIlot.aEpaules(.microEtendu), "survol : un petit déplié qui épouse « Micro coupé », le nom et « Rouvrir »")
        verifier(VueIlot.microOuvert.estBandeau && GeoIlot.profondeur(.microOuvert) == 0 && !GeoIlot.ajusteAuContenu(.microOuvert), "« Micro ouvert » : un bandeau court dans les ailes")
        var em = EtatIlot(); em.microCoupe = true; em.lecture = true
        var rm = ArbitrageIlot.resoudre(em)
        verifier(rm.principal == .microCompact && rm.survol == .microEtendu && rm.pastille == .lecture, "micro coupé + vidéo : le micro garde l'îlot, la vidéo devient la bulle")
        rm = ArbitrageIlot.resoudre(em, echange: .lecture)
        verifier(rm.principal == .lectureCompact && rm.pastille == .micro, "clic sur la bulle : la vidéo prend l'îlot, le micro coupé la bulle")
        em.rendezVousProche = true; em.rappelEnAttente = true
        verifier(ArbitrageIlot.resoudre(em).principal == .microCompact && ArbitrageIlot.resoudre(em).pastille == .rendezVous, "micro coupé > rendez-vous > rappel > lecture")
        em.bandeau = .microOuvert
        verifier(ArbitrageIlot.resoudre(em).principal == .microOuvert && ArbitrageIlot.resoudre(em).verrou, "« Micro ouvert » prend l'îlot un instant")
        verifier(ArbitrageIlot.etage(dictee: false, reunion: false, ecran: .microCompact) == 3 && ArbitrageIlot.etage(dictee: true, reunion: false, ecran: .microCompact) == 1,
                 "étage : le micro coupé avant la lecture, la dictée avant tout")
    }

    groupe("Îlot : épaules (batterie, écouteurs) et énergie")
    for (barre, demi) in [(32.0, 100.0), (33.0, 89.5)] {
        for v in VueIlot.allCases {
            let g = GeoIlot.valeurs(v, hauteurBarre: barre, demiCamera: demi, epaules: true)
            let p = TraceIlot.calculer(g, demiCamera: demi, barre: barre)
            verifier(p.bande <= demi + GeoIlot.aileMax + 0.001, "\(v.rawValue), épaules ouvertes : \(String(format: "%.0f", p.bande - demi)) pt de chaque côté de la caméra, ≤ 66")
            if GeoIlot.aEpaules(v) {
                verifier(g[0] == GeoIlot.epaules, "\(v.rawValue) déplié : le cou passe à 56 pt (la place de « 33 % » et de sa pile)")
            } else {
                verifier(g == GeoIlot.valeurs(v, hauteurBarre: barre, demiCamera: demi), "\(v.rawValue) : les épaules ne changent rien (pas un écran déplié)")
            }
        }
    }
    for v in [VueIlot.batterieCharge, .batterieFaible] {
        verifier(v.estBandeau && GeoIlot.profondeur(v) == 0 && !GeoIlot.ajusteAuContenu(v), "\(v.rawValue) : un bandeau qui tient dans les ailes (rien sous la barre)")
    }
    verifier(VueIlot.appareil.estBandeau && GeoIlot.ajusteAuContenu(.appareil) && GeoIlot.profondeur(.appareil) >= 79, "écouteurs connectés : un bandeau qui épouse ses jauges, assez haut pour l'anneau et son nom")
    verifier(ArbitrageIlot.resoudre({ var e = EtatIlot(); e.lecture = true; e.minuteur = true; e.bandeau = .batterieCharge; return e }()).pastille == .lecture,
             "chargeur branché pendant une vidéo : la vidéo passe en bulle le temps de l'annonce")
    do {
        let e = EnergieIlot(pourcent: 33, secteur: false, enCharge: false)
        verifier(e.texte == "33\u{202F}%" && e.symbole == "battery.25percent", "33 % : « 33 % » (espace fine), pile au quart")
        verifier(EnergieIlot(pourcent: 80, secteur: true, enCharge: true).symbole == "battery.100percent.bolt", "branché : la pile avec l'éclair")
        let a = AppareilIlot(nom: "AirPods Pro de Hugues", genre: .ecouteurs, gauche: 80, droit: 72, etui: 45)
        verifier(a.niveau == 72 && a.symbole == "airpodspro", "écouteurs : l'épaule montre le côté le plus bas (72), symbole AirPods Pro")
        verifier(AppareilIlot(nom: "", genre: .souris, unique: 60).niveau == 60 && AppareilIlot(nom: "", genre: .souris).titre == "Souris", "souris : un seul niveau ; sans nom, « Souris »")
        var w = VeilleEnergie()
        verifier(w.lire(EnergieIlot(pourcent: 15, secteur: false, enCharge: false)) == nil, "lancement à 15 % : pas d'annonce (on ne prévient pas pour une batterie qu'on connaît)")
        verifier(w.lire(EnergieIlot(pourcent: 14, secteur: false, enCharge: false)) == nil, "15 → 14 % : rien (le seuil des 20 % est déjà passé)")
        verifier(w.lire(EnergieIlot(pourcent: 10, secteur: false, enCharge: false)) == .faible(10), "→ 10 % : « Faible », une fois")
        verifier(w.lire(EnergieIlot(pourcent: 9, secteur: false, enCharge: false)) == nil, "→ 9 % : pas une deuxième fois")
        verifier(w.lire(EnergieIlot(pourcent: 9, secteur: true, enCharge: true)) == .charge, "on branche : « En charge »")
        verifier(w.lire(EnergieIlot(pourcent: 10, secteur: true, enCharge: true)) == nil, "toujours branché : rien de plus")
        verifier(w.lire(EnergieIlot(pourcent: 30, secteur: false, enCharge: false)) == nil && w.lire(EnergieIlot(pourcent: 20, secteur: false, enCharge: false)) == .faible(20),
                 "débranché à 30 %, puis 20 % : « Faible » de nouveau (rebrancher remet les seuils à zéro)")
        var v = VeilleEnergie()
        verifier(v.lire(EnergieIlot(pourcent: 50, secteur: true, enCharge: true)) == nil, "lancement déjà branché : pas d'annonce")
        verifier(v.lire(nil) == nil, "Mac sans batterie : jamais d'annonce")
    }

    let barre = 32.0, demi = 100.0
    verifier(GeoIlot.valeurs(.repos, hauteurBarre: 37)[2] == 37, "le repos épouse exactement la barre (37)")
    verifier(GeoIlot.valeurs(.minuteurCompact, hauteurBarre: 32)[2] == 32 && GeoIlot.valeurs(.minuteurCompact, hauteurBarre: 37)[2] == 37, "compact : exactement la hauteur de la barre, rien ne dépasse dessous")
    let etendu = TraceIlot.calculer(GeoIlot.valeurs(.accueil, hauteurBarre: barre), demiCamera: demi, barre: barre)
    verifier(etendu.basGauche < etendu.xGauche - 50 && etendu.basDroite > etendu.xDroite + 50, "étendu : le corps est plus large que le cou, sous la barre")
    verifier(etendu.bande <= demi + 30, "étendu (accueil) : cou étroit dans la barre (\(Int(etendu.bande - demi)) pt), les menus restent visibles")
    let compact = TraceIlot.calculer(GeoIlot.valeurs(.minuteurCompact, hauteurBarre: barre), demiCamera: demi, barre: barre)
    verifier(compact.corps == demi + 48 && compact.hauteur == barre, "compact : pas de corps sous la barre, même largeur en bas")
    let lectureC = GeoIlot.valeurs(.lectureCompact, hauteurBarre: barre), lectureX = GeoIlot.valeurs(.lectureEtendu, hauteurBarre: barre)
    verifier(lectureC[0] == lectureX[0], "lecture : le cou ne bouge pas en se dépliant (l'égaliseur reste dans l'aile)")
    let lectureM = GeoIlot.valeurs(.lectureMinuteur, hauteurBarre: barre)
    verifier(lectureM[0] == lectureX[0] && lectureM[1] == lectureX[1] && lectureM[2] == lectureX[2] + 54 && Array(lectureM[3...]) == Array(lectureX[3...]),
             "lecture + rangée Minuteur : même cou, même corps, 54 pt de plus en bas (maquette : 208 → 262)")
    verifier(Double(lectureM[2]) + 30 <= 330, "lecture + rangée Minuteur : tient dans la zone de dessin de l'îlot (330 pt, ombre comprise)")
    verifier(ArbitrageIlot.etage(dictee: false, reunion: false, ecran: .lectureMinuteur) == 4, "lecture + rangée : même étage de priorité que la lecture")
    verifier(PassageIlot.de(hauteur: barre, vers: GeoIlot.valeurs(.accueil, hauteurBarre: barre)[2]) == .ouverture
             && PassageIlot.de(hauteur: GeoIlot.valeurs(.accueil, hauteurBarre: barre)[2], vers: barre) == .fermeture
             && PassageIlot.de(hauteur: barre, vers: barre + 0.5) == .glissement, "ouverture / fermeture / glissement reconnus (ceux du moteur)")
    // le corps épouse le contenu : un « Fait » court donne un corps étroit, un long message s'arrête au plus large de la table
    for (cam, b) in [(179.0, 33.0), (200.0, 32.0)] {
        let hc = cam / 2
        for v in VueIlot.allCases where GeoIlot.ajusteAuContenu(v) {
            let t = GeoIlot.valeurs(v, hauteurBarre: b)
            let court = GeoIlot.valeurs(v, hauteurBarre: b, demiCamera: hc, contenu: 60)
            let long = GeoIlot.valeurs(v, hauteurBarre: b, demiCamera: hc, contenu: 2000)
            let juste = GeoIlot.valeurs(v, hauteurBarre: b, demiCamera: hc, contenu: 2 * (hc + t[0] + 60) - 32)
            verifier(court[1] == t[0] + GeoIlot.evasementMin && long[1] == t[1] && abs(juste[1] - (t[0] + 60)) < 1.01 && court[0] == t[0] && court[2] == t[2],
                     "\(v.rawValue) (caméra \(Int(cam))) : corps ajusté au contenu (court \(Int(court[1])), juste \(Int(juste[1])), long \(Int(long[1])) pt), cou et hauteur inchangés")
            let p = TraceIlot.calculer(court, demiCamera: hc, barre: b)
            verifier(p.bande <= hc + GeoIlot.aileMax + 0.001 && p.corps >= p.bande + 20, "\(v.rawValue) au plus court : le corps s'évase encore sous la barre, rien de plus large dans la barre")
        }
    }
    verifier(GeoIlot.valeurs(.lectureEtendu, hauteurBarre: barre, demiCamera: demi, contenu: 10) == GeoIlot.valeurs(.lectureEtendu, hauteurBarre: barre), "la lecture dépliée garde sa largeur (elle remplit déjà son corps)")
    // coins continus : chaque coin du bas est une courbe cubique (pas un arc de cercle), le haut épouse le bord de l'écran
    verifier(etendu.commandes.filter { if case .cubique = $0 { return true }; return false }.count == 4, "étendu : quatre coins continus (courbes cubiques)")
    if case let .deplacer(_, y) = etendu.commandes.first { verifier(y <= 0, "la forme part du bord haut de l'écran") }
    // pendant chaque passage (ressorts de la maquette, rebond compris), rien ne dépasse les ailes dans la barre
    let paires: [(VueIlot, VueIlot)] = [(.lectureCompact, .lectureEtendu), (.lectureEtendu, .lectureCompact), (.lectureEtendu, .lectureMinuteur), (.lectureMinuteur, .lectureCompact), (.repos, .accueil), (.accueil, .repos),
                                         (.lectureCompact, .rappelEtendu), (.rappelEtendu, .lectureCompact), (.minuteurCompact, .minuteurEtendu),
                                         (.agendaCompact, .agendaEtendu), (.lectureEtendu, .minuteurFini), (.repos, .notification), (.agendaEtendu, .repos)]
    // les ressorts sont ceux du moteur (`PassageIlot.viser`), y compris interrompus à mi-course vers un troisième écran
    let tiers: [VueIlot] = [.repos, .accueil, .lectureCompact, .minuteurFini]
    for (de, vers) in paires {
        var bandeMax = 0.0, hauteurMin = 1e9
        for interruption in [nil] + tiers.map(Optional.some) where interruption != vers {
            var r = GeoIlot.valeurs(de, hauteurBarre: barre).map { RessortIlot($0, reponse: 0.4, amortissement: 1) }
            PassageIlot.viser(&r, vers: GeoIlot.valeurs(vers, hauteurBarre: barre), alerte: vers.estAlerte)
            for k in 0..<240 {
                if k == 18, let x = interruption { PassageIlot.viser(&r, vers: GeoIlot.valeurs(x, hauteurBarre: barre), alerte: x.estAlerte) }
                for i in 0..<r.count { r[i].avancer(1.0 / 120) }
                let p = TraceIlot.calculer(r.map(\.x), demiCamera: demi, barre: barre)
                bandeMax = max(bandeMax, p.bande); hauteurMin = min(hauteurMin, p.hauteur)
            }
        }
        verifier(bandeMax <= demi + GeoIlot.aileMax + 0.01 && hauteurMin >= barre - 0.01, "passage \(de.rawValue) → \(vers.rawValue) (et interrompu) : bande max \(String(format: "%.1f", bandeMax - demi)) pt ≤ 66, jamais plus haut que la barre")
    }
    // à mi-fermeture, la forme se resserre vers l'encoche (pas de bandeau plat plus large que l'écran déplié n'était haut)
    do {
        var r = GeoIlot.valeurs(.lectureEtendu, hauteurBarre: barre).map { RessortIlot($0, reponse: 0.4, amortissement: 1) }
        let fin = GeoIlot.valeurs(.lectureCompact, hauteurBarre: barre)
        verifier(PassageIlot.viser(&r, vers: fin) == .fermeture, "lecture dépliée → compacte : une fermeture")
        for _ in 0..<24 { for i in 0..<r.count { r[i].avancer(1.0 / 120) } }
        let largeur = (r[1].x - fin[1]) / (144 - fin[1]), hauteur = (r[2].x - fin[2]) / (175)
        verifier(largeur < hauteur, "à 200 ms de la fermeture, la largeur a fait plus de chemin que la hauteur (\(Int(largeur * 100)) % restant contre \(Int(hauteur * 100)) %)")
    }

    groupe("Îlot : priorité et pastille")
    var e = EtatIlot()
    verifier(ArbitrageIlot.resoudre(e).principal == .repos && ArbitrageIlot.resoudre(e).survol == .accueil, "rien : l'îlot est vide, au survol l'accueil")
    e.minuteur = true
    verifier(ArbitrageIlot.resoudre(e).principal == .minuteurCompact && ArbitrageIlot.resoudre(e).pastille == nil, "minuteur seul : compact, pas de pastille")
    e.lecture = true
    var r = ArbitrageIlot.resoudre(e)
    verifier(r.principal == .lectureCompact && r.survol == .lectureEtendu && r.pastille == .minuteur, "lecture + minuteur : la lecture garde l'îlot, le minuteur devient pastille")
    r = ArbitrageIlot.resoudre(e, echange: .minuteur)
    verifier(r.principal == .minuteurCompact && r.pastille == .lecture, "clic sur la pastille : les deux échangent")
    e.rappelEnAttente = true
    verifier(ArbitrageIlot.resoudre(e).principal == .rappelCompact && ArbitrageIlot.resoudre(e).pastille == .lecture, "rappel sans réponse > lecture > minuteur")
    e.rendezVousProche = true
    verifier(ArbitrageIlot.resoudre(e).principal == .agendaCompact && ArbitrageIlot.resoudre(e).pastille == .rappel, "rendez-vous > rappel")
    e.alerte = .minuteurFini
    r = ArbitrageIlot.resoudre(e)
    verifier(r.principal == .minuteurFini && r.verrou && r.survol == nil && r.pastille == .rendezVous, "alerte : prend l'îlot, verrouillée ; l'activité la plus haute patiente en pastille")
    e.alerte = nil; e.bandeau = .notification
    r = ArbitrageIlot.resoudre(e)
    verifier(r.principal == .notification && r.verrou && r.pastille == .rendezVous, "bandeau : prend l'îlot un instant")
    verifier(ArbitrageIlot.resoudre(EtatIlot(), echange: .lecture).principal == .repos, "échange avec une activité absente : sans effet")
    verifier(ArbitrageIlot.etage(dictee: true, reunion: true, ecran: .minuteurFini) == 1 && ArbitrageIlot.etage(dictee: false, reunion: true, ecran: .minuteurFini) == 2
             && ArbitrageIlot.etage(dictee: false, reunion: false, ecran: .minuteurFini) == 3 && ArbitrageIlot.etage(dictee: false, reunion: false, ecran: .lectureCompact) == 4
             && ArbitrageIlot.etage(dictee: false, reunion: false, ecran: .minuteurCompact) == 5, "échelle : dictée > réunion > alerte > lecture > le reste")
    verifier(VueIlot.minuteurFini.estAlerte && VueIlot.rappelEtendu.estAlerte && VueIlot.agendaDebut.estAlerte && !VueIlot.minuteurLance.estAlerte && VueIlot.notification.estBandeau, "alertes et bandeaux distingués")

    groupe("Îlot : ressort")
    var s = RessortIlot(0, reponse: 0.48, amortissement: 0.75)
    s.cible = 1
    var pic = 0.0
    for _ in 0..<180 { s.avancer(1.0 / 60); pic = max(pic, s.x) }
    verifier(abs(s.x - 1) < 0.01, "le ressort rejoint sa cible en 3 s")
    verifier(pic > 1.01 && pic < 1.05, "ouverture (0,48 s, 0,75) : petit rebond visible, \(String(format: "%.1f", (pic - 1) * 100)) % (1 à 5 %)")
    var s2 = RessortIlot(0, reponse: 0.4, amortissement: 1); s2.cible = 1
    var depasse = false
    for _ in 0..<240 { s2.avancer(1.0 / 60); if s2.x > 1.001 { depasse = true } }
    verifier(!depasse, "amortissement 1 (fermeture) : aucun rebond")
    var s3 = RessortIlot(0, reponse: 0.48, amortissement: 0.75); s3.cible = 1
    for _ in 0..<12 { s3.avancer(1.0 / 60) }
    let avant = s3.x; s3.viser(0, reponse: 0.4, amortissement: 1); s3.avancer(1.0 / 60)
    verifier(avant > 0.05 && s3.x > 0 && s3.v != 0, "interrompu : repart de la valeur affichée, garde sa vitesse")
    var s4 = RessortIlot(1, reponse: 0.45, amortissement: 1)
    s4.viser(0, reponse: 0.45, amortissement: 1, attente: 0.11)
    s4.avancer(0.1)
    verifier(s4.x == 1 && !s4.fini && s4.cibleFinale == 0, "une cible qui attend (0,11 s) : rien ne bouge avant, le ressort n'est pas posé")
    s4.avancer(0.2)
    verifier(s4.x < 1 && s4.cible == 0, "après l'attente : il part vers la nouvelle cible")
    s4.poser()
    verifier(s4.x == 0 && s4.fini, "posé : sur la cible finale")

    groupe("Îlot : minuteur")
    var m = MinuteurIlot(minutes: 10, depuis: t0)
    verifier(m.restant(a: t0) == 600 && m.enMarche && !m.termine(a: t0), "10 min lancé")
    verifier(m.restant(a: t0.addingTimeInterval(125)) == 475 && FormatIlot.duree(475) == "7:55", "125 s plus tard : 7:55")
    verifier(FormatIlot.duree(0.2) == "0:01" && FormatIlot.duree(0) == "0:00" && FormatIlot.duree(600) == "10:00", "affichage : arrondi vers le haut (0:01 à 0,2 s), 0:00, 10:00")
    verifier(abs(m.fraction(a: t0.addingTimeInterval(300)) - 0.5) < 1e-9, "anneau à moitié à mi-parcours")
    verifier(cal.component(.minute, from: m.heureDeFin(a: t0)) == 42 && cal.component(.hour, from: m.heureDeFin(a: t0)) == 14, "fin à 14:42")
    m.pause(a: t0.addingTimeInterval(100))
    verifier(m.enPause && m.restant(a: t0.addingTimeInterval(9999)) == 500 && m.echeance == nil, "pause : le temps ne passe plus, aucune échéance à surveiller")
    m.reprendre(a: t0.addingTimeInterval(200))
    verifier(m.enMarche && m.restant(a: t0.addingTimeInterval(260)) == 440, "reprise : repart de 500 s")
    m.ajouter(60, a: t0.addingTimeInterval(260))
    verifier(m.restant(a: t0.addingTimeInterval(260)) == 500 && m.total == 660, "+1 min allonge le restant et le total")
    verifier(m.termine(a: t0.addingTimeInterval(761)) && !m.termine(a: t0.addingTimeInterval(759)), "terminé à la seconde")
    var mp = MinuteurIlot(minutes: 5, depuis: t0); mp.pause(a: t0); mp.ajouter(60, a: t0)
    verifier(mp.restant(a: t0) == 360, "+1 min en pause")
    verifier(FormatIlot.minutes(600) == "10 min" && FormatIlot.minutes(5400) == "1 h 30" && FormatIlot.minutes(3600) == "1 h", "libellés de durée")

    groupe("Îlot : commandes dictées")
    verifier(AnalyseCommandeIlot.minuteur("Minuteur 10 minutes.") == 600, "« minuteur 10 minutes. »")
    verifier(AnalyseCommandeIlot.minuteur("minuteur dix minutes") == 600 && AnalyseCommandeIlot.minuteur("Mets un minuteur de cinq minutes") == 300, "nombres en lettres, « mets un minuteur de … »")
    verifier(AnalyseCommandeIlot.minuteur("minuteur 1 heure 30") == nil && AnalyseCommandeIlot.minuteur("minuteur 1 heure 30 minutes") == 5400, "heures et minutes")
    verifier(AnalyseCommandeIlot.minuteur("minuteur d'une demi-heure") == 1800 && AnalyseCommandeIlot.minuteur("minuteur un quart d'heure") == 900, "demi-heure, quart d'heure")
    verifier(AnalyseCommandeIlot.minuteur("minuteur 90 secondes") == 90, "secondes")
    verifier(AnalyseCommandeIlot.minuteur("je veux un minuteur pour les pâtes") == nil && AnalyseCommandeIlot.minuteur("le minuteur est cassé") == nil && AnalyseCommandeIlot.minuteur("Bonjour Paul") == nil,
             "une phrase normale n'est jamais prise pour une commande")
    verifier(AnalyseCommandeIlot.minuteur("minuteur 0 minutes") == nil && AnalyseCommandeIlot.minuteur("minuteur 99999 minutes") == nil, "durées absurdes refusées")
    if let rp = AnalyseCommandeIlot.rappel("Rappelle-moi d'appeler Paul à 15 h.", maintenant: t0, calendrier: cal) {
        verifier(rp.texte == "Appeler Paul" && cal.component(.hour, from: rp.quand) == 15 && cal.component(.minute, from: rp.quand) == 0 && cal.isDate(rp.quand, inSameDayAs: t0), "rappelle-moi d'appeler Paul à 15 h")
    } else { verifier(false, "rappelle-moi d'appeler Paul à 15 h") }
    if let rp = AnalyseCommandeIlot.rappel("rappelle-moi de réserver la salle à 9h30", maintenant: t0, calendrier: cal) {
        verifier(rp.texte == "Réserver la salle" && cal.component(.hour, from: rp.quand) == 9 && cal.component(.minute, from: rp.quand) == 30 && !cal.isDate(rp.quand, inSameDayAs: t0), "heure déjà passée : demain")
    } else { verifier(false, "rappel à 9h30") }
    if let rp = AnalyseCommandeIlot.rappel("Rappelle-moi de sortir le pain dans 20 minutes", maintenant: t0, calendrier: cal) {
        verifier(rp.texte == "Sortir le pain" && rp.quand == t0.addingTimeInterval(1200), "dans 20 minutes")
    } else { verifier(false, "rappel dans 20 minutes") }
    verifier(AnalyseCommandeIlot.rappel("rappelle-moi un jour de te le dire", maintenant: t0, calendrier: cal) == nil && AnalyseCommandeIlot.rappel("Je te rappelle demain à 15 h", maintenant: t0, calendrier: cal) == nil,
             "« je te rappelle demain à 15 h » (une dictée normale) n'est pas un rappel")
    verifier(AnalyseCommandeIlot.analyser("minuteur 10 minutes", maintenant: t0) == .minuteur(secondes: 600), "analyser : minuteur")
    if case .rappel(let texteLibre, _)? = AnalyseCommandeIlot.analyser("Appeler Paul à 15 h.", maintenant: t0, calendrier: cal, exigerPrefixe: false) {
        verifier(texteLibre == "Appeler Paul", "formulaire ouvert : « appeler Paul à 15 h » suffit")
    } else { verifier(false, "formulaire ouvert : « appeler Paul à 15 h » suffit") }
    verifier(AnalyseCommandeIlot.analyser("Appeler Paul à 15 h.", maintenant: t0, calendrier: cal) == nil, "sans formulaire : une phrase qui contient une heure n'est pas un rappel")

    groupe("Îlot : rappels")
    var l = ListeRappels()
    let dans5 = t0.addingTimeInterval(300)
    let a = l.ajouter(texte: "  Appeler Paul ", echeance: dans5, maintenant: t0)
    verifier(a?.texte == "Appeler Paul" && l.ajouter(texte: "   ", echeance: dans5, maintenant: t0) == nil, "ajout (texte nettoyé), texte vide refusé")
    _ = l.ajouter(texte: "Envoyer le devis", echeance: t0.addingTimeInterval(7200), maintenant: t0)
    verifier(l.dus(a: t0).isEmpty && l.aVenir(a: t0).map(\.texte) == ["Appeler Paul", "Envoyer le devis"] && l.prochaineEcheance() == dans5, "à venir dans l'ordre, rien de dû, prochain réveil à l'heure du premier")
    verifier(l.dus(a: dans5).map(\.texte) == ["Appeler Paul"], "à l'heure dite : dû")
    l.marquerSonne(a!.id, a: dans5)
    verifier(l.dus(a: dans5).isEmpty && l.enAttente.map(\.texte) == ["Appeler Paul"], "sonné sans réponse : la cloche reste (en attente), plus dû")
    let relu = l.donnees().flatMap { ListeRappels.depuis($0) }
    verifier(relu == l && relu?.enAttente.count == 1, "enregistrement JSON aller-retour : la cloche survit à une relance")
    l.reporter(a!.id, depuis: dans5)
    verifier(l.enAttente.isEmpty && l.dus(a: dans5.addingTimeInterval(599)).isEmpty && l.dus(a: dans5.addingTimeInterval(600)).count == 1, "Plus tard : sonne à nouveau 10 min après")
    l.fait(a!.id)
    verifier(l.rappels.count == 1 && l.rappels[0].texte == "Envoyer le devis", "Fait : retiré")
    var ferme = ListeRappels(); _ = ferme.ajouter(texte: "Pendant que Verbe dormait", echeance: t0.addingTimeInterval(-3600), maintenant: t0.addingTimeInterval(-7200))
    verifier(ferme.dus(a: t0).count == 1, "un rappel arrivé à échéance pendant que Verbe était fermé sonne à la relance")
    verifier(ListeRappels.depuis(Data("pas du json".utf8)) == nil, "fichier abîmé : nil, pas de plantage")
    verifier(ListeRappels.jour(de: t0, maintenant: t0, calendrier: cal) == "aujourd\u{2019}hui" && ListeRappels.jour(de: t0.addingTimeInterval(86400), maintenant: t0, calendrier: cal) == "demain", "aujourd'hui, demain")
    verifier(ListeRappels.retard(de: t0, maintenant: t0.addingTimeInterval(20)) == "maintenant" && ListeRappels.retard(de: t0, maintenant: t0.addingTimeInterval(720)) == "il y a 12 min", "retard lisible")
    var plein = ListeRappels(); for i in 0..<(ListeRappels.limite + 20) { _ = plein.ajouter(texte: "r\(i)", echeance: t0, maintenant: t0) }
    verifier(plein.rappels.count == ListeRappels.limite, "limite de \(ListeRappels.limite) rappels")

    groupe("Îlot : agenda")
    let debut = t0.addingTimeInterval(600)
    let ev = EvenementAgenda(id: "a", titre: "Point équipe", debut: debut, fin: debut.addingTimeInterval(2000), lien: URL(string: "https://meet.google.com/abc-defg-hij"))
    verifier(PlanAgenda.etape(ev, a: t0.addingTimeInterval(-60)) == .loin(dans: 60), "11 min avant : encore loin (réveil dans 60 s)")
    verifier(PlanAgenda.etape(ev, a: t0) == .avant(600), "10 min avant : on s'annonce")
    verifier(PlanAgenda.etape(ev, a: debut) == .debut && PlanAgenda.etape(ev, a: debut.addingTimeInterval(119)) == .debut, "au début : alerte")
    verifier(PlanAgenda.etape(ev, a: debut.addingTimeInterval(121)) == .passe, "2 min après le début : on ne réveille plus personne")
    verifier(PlanAgenda.dans(600) == "dans 10 min" && PlanAgenda.dans(59) == "dans 1 min" && PlanAgenda.dans(10) == "maintenant", "libellé « dans N min »")
    verifier(PlanAgenda.court(600) == "10 min" && PlanAgenda.court(59) == "1 min" && PlanAgenda.court(10) == "1 min" && PlanAgenda.court(0) == "1 min", "aile du rendez-vous : « 1 min » jusqu'au début, jamais « maintenant » (coupé dans 38 pt)")
    let journee = EvenementAgenda(id: "j", titre: "Anniversaire", debut: t0.addingTimeInterval(60), fin: t0.addingTimeInterval(86000), toutelaJournee: true)
    let passe = EvenementAgenda(id: "p", titre: "Fini", debut: t0.addingTimeInterval(-7200), fin: t0.addingTimeInterval(-3600))
    verifier(PlanAgenda.prochain([journee, passe, ev], a: t0)?.id == "a", "le prochain : ni journée entière, ni rendez-vous fini")
    verifier(PlanAgenda.plage(ev, calendrier: cal) == "14:42 \u{2013} 15:15", "plage horaire 14:42 – 15:15")
    verifier(LienVisio.extraire(depuis: [nil, "Rejoindre : https://meet.google.com/abc-defg-hij.", "autre"])?.absoluteString == "https://meet.google.com/abc-defg-hij", "lien Meet trouvé dans les notes")
    verifier(LienVisio.extraire(depuis: ["https://us02web.zoom.us/j/123456789?pwd=abc"])?.host == "us02web.zoom.us", "lien Zoom (sous-domaine)")
    verifier(LienVisio.extraire(depuis: ["http://meet.google.com/x", "https://exemple-malveillant.fr/meet.google.com", "https://zoom.us.evil.fr/j/1", "https://evilzoom.us/j/1"]) == nil, "http, faux domaine, domaine voisin : refusés")
    verifier(LienVisio.extraire(depuis: ["(https://teams.microsoft.com/l/meetup-join/xyz)"])?.host == "teams.microsoft.com", "lien entre parenthèses")
    verifier(LienVisio.extraire(depuis: ["salle 12, 3e étage"]) == nil, "un lieu sans lien : aucun lien")

    groupe("Îlot : notifications")
    let n3 = LectureNotifications.depuis(textes: ["Messages", "Camille", "On se retrouve à 19 h devant le cinéma ?"], date: t0)
    verifier(n3?.app == "Messages" && n3?.titre == "Camille" && n3?.corps == "On se retrouve à 19 h devant le cinéma ?", "trois textes : app, titre, corps")
    let n2 = LectureNotifications.depuis(textes: ["Banque", "Virement reçu"], date: t0)
    verifier(n2?.app == "" && n2?.titre == "Banque" && n2?.corps == "Virement reçu", "deux textes : titre, corps")
    verifier(LectureNotifications.depuis(textes: ["Messages", "Camille"], nomsDApps: ["Messages"], date: t0)?.titre == "Camille", "deux textes dont le premier est une app connue")
    verifier(LectureNotifications.depuis(textes: ["Fermer", "maintenant", "  "], date: t0) == nil, "boutons et heure seuls : pas une notification")
    verifier(LectureNotifications.depuis(textes: ["Mail", "Titre", String(repeating: "x", count: 500)], date: t0)?.corps.count == 161, "corps tronqué à 160 caractères")
    let groupeN = [NotificationRecue(app: "Messages", titre: "Camille", corps: "", date: t0), NotificationRecue(app: "Banque", titre: "Banque", corps: "", date: t0), NotificationRecue(app: "Slack", titre: "Équipe projet", corps: "", date: t0), NotificationRecue(app: "Mail", titre: "Camille", corps: "", date: t0)]
    verifier(LectureNotifications.ligneDeGroupe(groupeN) == "Camille \u{00B7} Banque \u{00B7} Équipe projet" && LectureNotifications.titreDeGroupe(3) == "3 nouvelles notifications", "ligne du groupe : noms distincts")
    var pile: [NotificationRecue] = []
    pile = LectureNotifications.ajouter(groupeN[0], a: pile, maintenant: t0)
    pile = LectureNotifications.ajouter(groupeN[1], a: pile, maintenant: t0.addingTimeInterval(2))
    verifier(pile.count == 2, "deux notifications rapprochées : regroupées")
    pile = LectureNotifications.ajouter(groupeN[2], a: pile, maintenant: t0.addingTimeInterval(60))
    verifier(pile.count == 1, "une minute plus tard : la pile repart de zéro")
}

/// « Claude au travail » : le JSON gardé dans l'ordre, la fusion des crochets dans settings.json (sur des JSON d'exemple, jamais le vrai
/// ~/.claude), le script, la lecture des lignes et l'état des sessions, les priorités dans l'îlot.
func controlesClaude(_ t0: Date) {
    groupe("Îlot : Claude au travail (JSON ordonné)")
    let exemple = """
    {
      "model": "opus",
      "prix": 1.50,
      "grand": -2.5e+10,
      "vide": {},
      "liste": [],
      "texte": "Claude a terminé sa tâche \\"vite\\" \\\\ \\u0001 \\ud83d\\ude00 / ok",
      "drapeaux": [
        true,
        false,
        null
      ]
    }

    """
    if let j = try? JSONOrdonne.lire(exemple) {
        verifier(j.membres?.map(\.cle) == ["model", "prix", "grand", "vide", "liste", "texte", "drapeaux"], "les clés gardent leur ordre")
        verifier(j["prix"] == .nombre("1.50") && j["grand"] == .nombre("-2.5e+10"), "les nombres gardent leur texte (« 1.50 » reste « 1.50 »)")
        verifier(j["texte"]?.texte == "Claude a terminé sa tâche \"vite\" \\ \u{01} 😀 / ok", "échappements lus (guillemet, barre, \\u0001, paire de substitution)")
        let re = j.texteIndente() + "\n"
        verifier(re == exemple.replacingOccurrences(of: "\\ud83d\\ude00", with: "😀"),
                 "réécrit à la façon de JSON.stringify(x, null, 2) : identique (l'émoji écrit tel quel, \\u0001 gardé échappé)")
    } else { verifier(false, "le JSON d'exemple est lu") }
    for mauvais in ["", "{", "{'a': 1}", "[1,]", "tru", "{\"a\": 1} x", "{\"a\" 1}", "\"\u{01}\"", "01x", "-", "1."] {
        verifier((try? JSONOrdonne.lire(mauvais)) == nil, "« \(mauvais) » : refusé")
    }

    groupe("Îlot : Claude au travail (crochets dans settings.json)")
    let script = "/Users/essai/Library/Application Support/Dictee/claude-crochet.sh"
    let commande = CrochetsClaude.commande(script: script)
    verifier(commande == "'/Users/essai/Library/Application Support/Dictee/claude-crochet.sh'", "la commande : le chemin entre apostrophes (il contient une espace)")
    verifier(CrochetsClaude.commande(script: "/x/l'appli/Dictee/claude-crochet.sh") == "'/x/l'\\''appli/Dictee/claude-crochet.sh'", "une apostrophe dans le chemin est échappée pour le shell")
    // le fichier absent ou vide : on le crée avec nos cinq crochets
    for depart in [nil, "", "  \n"] as [String?] {
        guard let t = try? CrochetsClaude.brancher(depart, script: script), let j = try? JSONOrdonne.lire(t) else { verifier(false, "fichier absent ou vide : branché"); continue }
        verifier(CrochetsClaude.estBranche(t) && j.membres?.map(\.cle) == ["hooks"], "fichier \(depart == nil ? "absent" : "vide") : un objet avec nos crochets")
        verifier(j["hooks"]?.membres?.map(\.cle) == ["UserPromptSubmit", "PostToolUse", "Notification", "Stop", "SessionEnd"], "cinq événements écoutés")
        verifier(j["hooks"]?["PostToolUse"]?.elements?.first?["matcher"]?.texte == "*" && j["hooks"]?["Stop"]?.elements?.first?["matcher"] == nil,
                 "les outils : filtre « * » ; les autres événements sans filtre")
        let h = j["hooks"]?["Stop"]?.elements?.first?["hooks"]?.elements?.first
        verifier(h?["type"]?.texte == "command" && h?["command"]?.texte == commande && h?["timeout"] == .nombre("5"), "l'entrée : commande, chemin cité, 5 s au plus")
        verifier(t.hasSuffix("}\n"), "le fichier finit par un retour à la ligne")
    }
    // le fichier de Hugues (forme réelle) : son crochet Stop et tout le reste sont gardés, à leur place
    let hugues = """
    {
      "model": "opus",
      "hooks": {
        "Stop": [
          {
            "hooks": [
              {
                "type": "command",
                "command": "osascript -e 'display notification \\"Claude a terminé sa tâche\\" with title \\"Claude Code\\" sound name \\"Glass\\"' 2>/dev/null || true"
              }
            ]
          }
        ]
      },
      "enabledPlugins": {
        "superpowers@claude-plugins-official": true
      },
      "modelSettings": {
        "claude-opus-5": {
          "effortLevel": "xhigh"
        }
      },
      "tui": "fullscreen"
    }

    """
    if let b = try? CrochetsClaude.brancher(hugues, script: script), let j = try? JSONOrdonne.lire(b), let j0 = try? JSONOrdonne.lire(hugues) {
        verifier(j.membres?.map(\.cle) == j0.membres?.map(\.cle), "les clés de premier niveau restent les mêmes, dans le même ordre")
        verifier(j["model"] == j0["model"] && j["enabledPlugins"] == j0["enabledPlugins"] && j["modelSettings"] == j0["modelSettings"] && j["tui"] == j0["tui"], "tout le reste est identique")
        let stop = j["hooks"]?["Stop"]?.elements ?? []
        verifier(stop.count == 2 && stop.first == j0["hooks"]?["Stop"]?.elements?.first, "Stop : le crochet de Hugues (osascript) d'abord, intact, puis le nôtre")
        verifier(j["hooks"]?.membres?.first?.cle == "Stop", "les événements déjà là gardent leur place")
        verifier(CrochetsClaude.estBranche(b) && !CrochetsClaude.estBranche(hugues), "branché après, pas avant")
        verifier((try? CrochetsClaude.brancher(b, script: script)) == b, "double installation : le texte ne change pas (rien en double)")
        verifier((try? CrochetsClaude.debrancher(b)) == hugues, "débrancher rend le fichier de départ, à l'octet près")
        verifier((try? CrochetsClaude.debrancher(hugues)) == hugues, "débrancher un fichier sans nos crochets : rien ne change")
        // le script a changé de place : le chemin est mis à jour, rien n'est ajouté
        let ailleurs = "/Users/autre/Library/Application Support/Dictee/claude-crochet.sh"
        if let b2 = try? CrochetsClaude.brancher(b, script: ailleurs), let j2 = try? JSONOrdonne.lire(b2) {
            verifier(j2["hooks"]?["Stop"]?.elements?.count == 2 && b2.contains(CrochetsClaude.commande(script: ailleurs)) && !b2.contains(commande), "script déplacé : la commande est mise à jour, sans doublon")
        } else { verifier(false, "script déplacé : branché") }
        // un crochet à nous déplacé à la main dans le groupe de Hugues : débrancher garde le sien
        let mele = hugues.replacingOccurrences(of: "2>/dev/null || true\"\n          }", with: "2>/dev/null || true\"\n          },\n          {\n            \"type\": \"command\",\n            \"command\": \"\(commande)\"\n          }")
        if let d = try? CrochetsClaude.debrancher(mele) { verifier(d == hugues, "notre crochet dans le groupe de Hugues : seul le nôtre part") }
        else { verifier(false, "groupe mêlé : débranché") }
    } else { verifier(false, "le fichier de Hugues est branché") }
    // un fichier vidé de nos seuls crochets perd la clé « hooks » qu'on avait créée
    if let b = try? CrochetsClaude.brancher("{\n  \"theme\": \"light\"\n}\n", script: script) {
        verifier((try? CrochetsClaude.debrancher(b)) == "{\n  \"theme\": \"light\"\n}\n", "débrancher retire la clé « hooks » qu'on avait ajoutée")
    }
    // ce qu'on ne comprend pas, on n'y touche pas
    do { _ = try CrochetsClaude.brancher("{ \"model\": \"opus\", }", script: script); verifier(false, "JSON abîmé : refusé") }
    catch { verifier(error as? CrochetsClaude.Erreur == .illisible, "JSON abîmé (virgule de trop) : refusé, rien n'est réécrit") }
    for forme in ["[1]", "{\"hooks\": []}", "{\"hooks\": {\"Stop\": {}}}"] {
        do { _ = try CrochetsClaude.brancher(forme, script: script); verifier(false, "\(forme) : refusé") }
        catch { verifier(error as? CrochetsClaude.Erreur == .formeInattendue, "« \(forme) » : forme inattendue, refusé") }
    }

    groupe("Îlot : Claude au travail (le script)")
    let s = ScriptCrochet.texte(dossier: "/Users/essai/Library/Application Support/Dictee/claude")
    verifier(s.hasPrefix("#!/bin/sh\n") && s.contains("D='/Users/essai/Library/Application Support/Dictee/claude'"), "shell, dossier cité")
    verifier(s.contains("exit 0") && s.contains("} >/dev/null 2>&1"), "muet (Claude Code lirait sa sortie) et toujours 0")
    verifier(s.contains("TodoWrite|TaskCreate|TaskUpdate)") && s.contains("/usr/bin/grep") && s.contains("${__CFBundleIdentifier:-}"),
             "les listes de tâches en entier ; les outils du système par leur chemin ; l'app d'où vient la session")

    groupe("Îlot : Claude au travail (lignes et sessions)")
    func ligne(_ t: Double, _ e: String, app: String = "com.apple.Terminal") -> String { "{\"t\":\(Int(t0.timeIntervalSince1970 + t)),\"app\":\"\(app)\",\"e\":\(e)}" }
    func court(_ ev: String, outil: String = "", cwd: String = "/Users/essai/dev/dictee-mac", type: String = "") -> String {
        "{\"hook_event_name\":\"\(ev)\",\"tool_name\":\"\(outil)\",\"cwd\":\"\(cwd)\",\"notification_type\":\"\(type)\"}"
    }
    let todos = "{\"session_id\":\"s1\",\"cwd\":\"/Users/essai/dev/dictee-mac\",\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"TodoWrite\",\"tool_input\":{\"todos\":["
        + (1...7).map { i in "{\"content\":\"Tâche \(i)\",\"status\":\"\(i <= 3 ? "completed" : (i == 4 ? "in_progress" : "pending"))\",\"activeForm\":\"Écrit la tâche \(i)\"}" }.joined(separator: ",") + "]},\"tool_response\":{}}"
    let ev0 = EvenementClaude.depuis(ligne: ligne(0, court("UserPromptSubmit")))
    verifier(ev0?.genre == .invite && ev0?.dossier == "/Users/essai/dev/dictee-mac" && ev0?.app == "com.apple.Terminal" && ev0?.date == t0, "une ligne courte : la demande, le dossier, l'app, l'heure")
    verifier(EvenementClaude.depuis(ligne: "{\"t\":12,\"e\":{\"hook_event_name\":\"Stop\"") == nil && EvenementClaude.depuis(ligne: "bonjour") == nil, "une ligne abîmée (coupée) : ignorée")
    if case .liste(let l)? = EvenementClaude.depuis(ligne: ligne(1, todos))?.taches {
        verifier(l.count == 7 && l.filter { $0.statut == .faite }.count == 3 && l[3].statut == .enCours && l[3].enCours == "Écrit la tâche 4", "TodoWrite : 7 tâches, 3 faites, la 4e en cours")
    } else { verifier(false, "TodoWrite lu") }
    let cree = EvenementClaude.depuis(ligne: ligne(2, "{\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"TaskCreate\",\"tool_input\":{\"subject\":\"Écrire les contrôles\",\"description\":\"…\",\"activeForm\":\"Écrit les contrôles\"},\"tool_response\":{\"task\":{\"id\":\"3\",\"subject\":\"Écrire les contrôles\"}}}"))
    verifier(cree?.taches == .creer(id: "3", sujet: "Écrire les contrôles", enCours: "Écrit les contrôles"), "TaskCreate : le sujet, et l'identifiant pris dans la réponse")
    let creeTexte = EvenementClaude.depuis(ligne: ligne(2, "{\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"TaskCreate\",\"tool_input\":{\"subject\":\"Relire\"},\"tool_response\":\"Task #12 created successfully: Relire\"}"))
    verifier(creeTexte?.taches == .creer(id: "12", sujet: "Relire", enCours: nil), "TaskCreate : l'identifiant pris dans le texte « Task #12 »")
    let modif = EvenementClaude.depuis(ligne: ligne(3, "{\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"TaskUpdate\",\"tool_input\":{\"taskId\":3,\"status\":\"completed\"}}"))
    verifier(modif?.taches == .modifier(id: "3", statut: "completed", sujet: nil, enCours: nil), "TaskUpdate : l'identifiant (même en nombre) et le statut")
    verifier(EvenementClaude.depuis(ligne: ligne(4, court("PostToolUse", outil: "Bash")))?.taches == nil, "un autre outil : pas de liste")

    var w = VeilleClaude()
    func lire(_ l: String, _ id: String = "s1") -> AnnonceClaude? { EvenementClaude.depuis(ligne: l).flatMap { w.lire($0, session: id) } }
    verifier(lire(ligne(0, court("UserPromptSubmit"))) == nil && w.principale(a: t0)?.etat == .travaille && w.principale(a: t0)?.projet == "dictee-mac",
             "demande envoyée : au travail, projet « dictee-mac », rien d'annoncé")
    verifier(w.principale(a: t0)?.progres == nil, "pas encore de liste : pas d'avancement (l'étoile seule)")
    _ = lire(ligne(5, todos))
    verifier(w.principale(a: t0)?.progres == ProgresClaude(faites: 3, total: 7) && w.principale(a: t0)?.tacheEnCours == "Écrit la tâche 4", "TodoWrite : « 3 sur 7 », la tâche en cours")
    verifier(ProgresClaude(faites: 3, total: 7).texte == "3 sur 7" && ProgresClaude(faites: 12, total: 14).court == "12/14", "« 3 sur 7 », forme courte « 12/14 »")
    if case .attend(let s)? = lire(ligne(10, court("Notification", type: "permission_prompt"))) {
        verifier(s.etat == .attend && s.projet == "dictee-mac" && s.app == "com.apple.Terminal", "une autorisation à donner : « Claude attend ta réponse », annoncé")
    } else { verifier(false, "notification : annoncée") }
    verifier(lire(ligne(11, court("Notification", type: "permission_prompt"))) == nil, "une 2e notification pendant l'attente : pas de 2e annonce")
    _ = lire(ligne(20, court("PostToolUse", outil: "Bash")))
    verifier(w.principale(a: t0)?.etat == .travaille && w.principale(a: t0)?.progres?.faites == 3, "l'outil autorisé a tourné : de nouveau au travail, la liste gardée")
    if case .termine(let s)? = lire(ligne(30, court("Stop"))) { verifier(s.projet == "dictee-mac", "fin du tour : « Terminé », annoncé avec le projet") }
    else { verifier(false, "fin du tour : annoncée") }
    verifier(w.principale(a: t0) == nil && lire(ligne(31, court("Stop"))) == nil, "terminé : plus rien dans l'îlot ; un 2e arrêt n'annonce rien")
    verifier(lire(ligne(90, court("Notification", type: "idle_prompt"))) == nil && w.principale(a: t0) == nil, "le rappel d'inactivité après la fin : ignoré")
    verifier(lire(ligne(91, court("Notification"))) == nil, "une notification sans genre après la fin (ancienne version) : ignorée aussi")
    verifier(VeilleClaude.attenteReelle("permission_prompt") && VeilleClaude.attenteReelle("elicitation_dialog") && VeilleClaude.attenteReelle(nil)
             && !VeilleClaude.attenteReelle("idle_prompt") && !VeilleClaude.attenteReelle("auth_success"), "« à toi » : autorisation, question ; pas l'inactivité ni la connexion réussie")
    // une nouvelle demande : la liste d'avant est gardée tant qu'elle n'est pas finie
    _ = lire(ligne(100, court("UserPromptSubmit")))
    verifier(w.principale(a: t0)?.progres?.total == 7, "nouvelle demande, liste pas finie : gardée")
    // Task* : création, avancement, suppression, identifiants inconnus
    _ = lire(ligne(0, court("UserPromptSubmit")), "s2")
    for (i, sujet) in ["Lire", "Écrire", "Relire"].enumerated() {
        _ = lire(ligne(1, "{\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"TaskCreate\",\"tool_input\":{\"subject\":\"\(sujet)\"},\"tool_response\":{\"task\":{\"id\":\"\(i + 1)\"}}}"), "s2")
    }
    func maj(_ id: String, _ st: String) { _ = lire(ligne(2, "{\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"TaskUpdate\",\"tool_input\":{\"taskId\":\"\(id)\",\"status\":\"\(st)\"}}"), "s2") }
    maj("1", "completed"); maj("2", "in_progress"); maj("9", "completed")
    let s2 = w.sessions["s2"]
    verifier(s2?.progres == ProgresClaude(faites: 1, total: 3) && s2?.tacheEnCours == "Écrire", "TaskCreate ×3, TaskUpdate : « 1 sur 3 », « Écrire » en cours ; un identifiant inconnu ne compte pas")
    maj("3", "deleted")
    verifier(w.sessions["s2"]?.progres == ProgresClaude(faites: 1, total: 2), "une tâche supprimée : « 1 sur 2 »")
    maj("2", "completed"); _ = lire(ligne(3, court("Stop")), "s2")
    _ = lire(ligne(400, court("UserPromptSubmit")), "s2")
    verifier(w.sessions["s2"]?.progres == nil, "nouvelle demande après une liste finie : la liste repart de zéro")
    // deux sessions : celle qui attend passe devant ; sinon la plus récente
    _ = lire(ligne(500, court("Notification", type: "permission_prompt")), "s1")
    verifier(w.principale(a: t0.addingTimeInterval(500))?.id == "s1", "deux sessions : celle qui attend une réponse est montrée")
    _ = lire(ligne(510, court("PostToolUse", outil: "Read")), "s1")
    verifier(w.principale(a: t0.addingTimeInterval(510))?.id == "s1", "deux au travail : la plus récente")
    // oubli : 30 min sans nouvelle
    verifier(w.prochainOubli(a: t0.addingTimeInterval(510)) == t0.addingTimeInterval(400 + VeilleClaude.oubliTravail), "un seul réveil : quand la plus ancienne sera oubliée")
    verifier(w.principale(a: t0.addingTimeInterval(510 + 1801)) == nil, "30 min sans nouvelle : oubliée (fenêtre fermée sans fin de session)")
    _ = lire(ligne(600, court("SessionEnd")), "s1")
    verifier(w.sessions["s1"] == nil, "fin de session : oubliée")

    verifier(VeilleClaude.dejaSousLesYeux(app: "com.apple.Terminal", premierPlan: "com.apple.Terminal") && !VeilleClaude.dejaSousLesYeux(app: "com.apple.Terminal", premierPlan: "com.google.Chrome"),
             "le Terminal de la session est au premier plan : rien à annoncer ; Chrome : on annonce")
    verifier(VeilleClaude.dejaSousLesYeux(app: nil, premierPlan: "com.googlecode.iterm2") && !VeilleClaude.dejaSousLesYeux(app: "com.googlecode.iterm2", premierPlan: "com.apple.Terminal")
             && !VeilleClaude.dejaSousLesYeux(app: nil, premierPlan: nil), "app inconnue : un terminal connu au premier plan suffit ; un autre terminal que celui de la session : on annonce")

    groupe("Îlot : Claude au travail (dans l'îlot)")
    func etat(_ f: (inout EtatIlot) -> Void) -> ResolutionIlot { var e = EtatIlot(); f(&e); return ArbitrageIlot.resoudre(e) }
    verifier(etat { $0.claude = true }.principal == .claudeMinimal && etat { $0.claude = true }.survol == .claudeEtendu, "au travail sans liste : l'étoile seule ; au survol, le déplié")
    verifier(etat { $0.claude = true; $0.claudeListe = true }.principal == .claudeCompact && etat { $0.claude = true; $0.claudeAttend = true }.principal == .claudeCompact,
             "avec une liste, ou une question : l'anneau et « 3 sur 7 » (ou « Attend »)")
    let video = etat { $0.claude = true; $0.claudeListe = true; $0.lecture = true }
    verifier(video.principal == .lectureCompact && video.pastille == .claude, "pendant une vidéo : la vidéo garde l'îlot, Claude dans la bulle")
    let question = etat { $0.claude = true; $0.claudeAttend = true; $0.lecture = true }
    verifier(question.principal == .claudeCompact && question.pastille == .lecture, "Claude attend une réponse pendant une vidéo : il prend l'îlot, la vidéo passe en bulle")
    verifier(etat { $0.claude = true; $0.claudeAttend = true; $0.microCoupe = true }.principal == .microCompact, "le micro coupé passe encore avant")
    verifier(etat { $0.claude = true; $0.minuteur = true }.principal == .minuteurCompact && etat { $0.claude = true; $0.minuteur = true }.pastille == .claude, "un minuteur passe avant Claude au travail")
    verifier(VueIlot.claudeAttend.estBandeau && VueIlot.claudeTermine.estBandeau && !VueIlot.claudeEtendu.estBandeau, "attend, terminé : des bandeaux ; le déplié : non")
    verifier([VueIlot.claudeEtendu, .claudeAttend, .claudeTermine].allSatisfy(GeoIlot.ajusteAuContenu), "les trois écrans dépliés épousent leur contenu")
    for (barre, demi) in [(32.0, 100.0), (33.0, 89.5)] {
        for v in [VueIlot.claudeMinimal, .claudeCompact] {
            let p = TraceIlot.calculer(GeoIlot.valeurs(v, hauteurBarre: barre), demiCamera: demi, barre: barre)
            verifier(p.bande - demi <= GeoIlot.aileMax + 0.001 && p.hauteur == barre, "\(v.rawValue) : dans la barre, \(Int(p.bande - demi)) pt de chaque côté de la caméra (≤ 66), rien sous la barre")
        }
    }
}
