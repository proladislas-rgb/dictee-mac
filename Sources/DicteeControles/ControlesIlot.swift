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
    controlesEtagere(t0)
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
        // curl -o, wget, cp, AirDrop : le fichier final est créé VIDE puis rempli sur place ; le dossier ne prévient plus (aucun ajout,
        // retrait ni renommage) : seules nos relectures espacées le voient se remplir
        var wv = VeilleTelechargements(existants: [])
        var tv: [String: Int64] = ["Image.iso": 0]
        func mv(_ n: String) -> EntreeDossier? { tv[n].map { EntreeDossier(nom: n, taille: $0) } }
        verifier(wv.lire(noms: ["Image.iso"], a: t0, mesure: mv).isEmpty && wv.prochaineRelecture == t0.addingTimeInterval(1),
                 "fichier créé vide, sans « .part » : rien encore, mais une relecture 1 s plus tard")
        verifier(wv.lire(noms: ["Image.iso"], a: t0.addingTimeInterval(1), mesure: mv).isEmpty && wv.prochaineRelecture == t0.addingTimeInterval(3),
                 "toujours vide : la relecture suivante est plus espacée (3 s)")
        tv["Image.iso"] = 700_000_000
        verifier(wv.lire(noms: ["Image.iso"], a: t0.addingTimeInterval(3), mesure: mv).isEmpty && wv.prochaineRelecture == t0.addingTimeInterval(4),
                 "rempli entre-temps, sans aucun événement du dossier : vu à la relecture, suivi jusqu'à ce que sa taille tienne")
        verifier(wv.lire(noms: ["Image.iso"], a: t0.addingTimeInterval(4), mesure: mv).map(\.nom) == ["Image.iso"] && wv.prochaineRelecture == nil,
                 "taille stable : « Image.iso » annoncé ; plus rien n'attend")
        var wz = VeilleTelechargements(existants: [])
        var vu = 0
        var quand = wz.lire(noms: ["vide.txt"], a: t0, mesure: { _ in vu += 1; return EntreeDossier(nom: "vide.txt", taille: 0) }).isEmpty ? wz.prochaineRelecture : nil
        while let q = quand, vu < 50 { _ = wz.lire(noms: ["vide.txt"], a: q, mesure: { _ in vu += 1; return EntreeDossier(nom: "vide.txt", taille: 0) }); quand = wz.prochaineRelecture }
        verifier(quand == nil && vu == VeilleTelechargements.pasVides.count + 1 && VeilleTelechargements.pasVides.last! <= VeilleTelechargements.abandon,
                 "un fichier qui reste vide : \(vu) relectures en une demi-heure, puis plus rien (jamais de relecture sans fin)")
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
        typealias R = VeilleMicro.Reponse
        let mac = "integre", air = "airpods"
        var w = VeilleMicro()
        verifier(w.systeme(defaut: mac, coupe: false) == .rien && !w.coupe && w.defaut == mac, "lancement, micro ouvert : rien")
        verifier(w.basculer() == R(commande: .couper(mac)) && w.coupe, "raccourci : on coupe CE micro (son UID) ; l'îlot montre « Coupé » tout de suite")
        verifier(w.systeme(defaut: mac, coupe: true) == .rien && w.coupe, "l'écho de notre commande ne change rien")
        verifier(w.basculer() == R(commande: .rouvrir(mac), annonce: .ouvert) && !w.coupe, "raccourci : on rouvre, bandeau « Micro ouvert »")
        verifier(w.systeme(defaut: mac, coupe: false) == .rien, "l'écho de la réouverture ne change rien")
        verifier(w.systeme(defaut: mac, coupe: true) == .rien && w.coupe, "coupé dans Réglages Système : l'îlot suit, sans bandeau")
        verifier(w.systeme(defaut: mac, coupe: false) == R(annonce: .ouvert) && !w.coupe, "rouvert dans Réglages Système : l'îlot suit, « Micro ouvert »")
        verifier(w.rouvrir() == .rien, "« Rouvrir » sur un micro déjà ouvert : rien")
        var sans = VeilleMicro()
        verifier(sans.systeme(defaut: nil, coupe: false) == .rien && sans.basculer() == .rien && !sans.coupe, "aucun micro d'entrée : le raccourci ne fait rien")

        // le micro par défaut change (AirPods) : rien n'a été rouvert, aucun « Micro ouvert »
        var a = VeilleMicro()
        _ = a.systeme(defaut: mac, coupe: false); _ = a.basculer()
        verifier(a.systeme(defaut: air, coupe: false) == .rien && !a.coupe && a.defaut == air, "AirPods connectés (ouverts) pendant que le Mac est coupé : l'îlot montre les AirPods, sans « Micro ouvert »")
        verifier(a.dictee(enCours: true, micro: mac, coupe: true) == R(commande: .rouvrir(mac)) && a.rouvertPourDictee == mac,
                 "dictée sur le micro du Mac (imposé), resté coupé : c'est LUI qui est rouvert, pas le micro par défaut")
        verifier(a.dictee(enCours: false) == R(commande: .couper(mac)) && a.rouvertPourDictee == nil && !a.coupe, "fin : le micro du Mac est recoupé ; les AirPods, jamais touchés")
        verifier(a.systeme(defaut: mac, coupe: true) == .rien && a.coupe, "AirPods rangés : le micro du Mac, toujours coupé, est montré, sans bandeau")
        // le défaut change PENDANT une dictée qui avait rouvert le micro du Mac
        var b = VeilleMicro()
        _ = b.systeme(defaut: mac, coupe: false); _ = b.basculer()
        verifier(b.dictee(enCours: true, micro: mac, coupe: true) == R(commande: .rouvrir(mac)), "dictée : le micro du Mac est rouvert")
        verifier(b.systeme(defaut: air, coupe: false) == .rien && !b.coupe, "les AirPods deviennent le micro par défaut pendant la dictée : rien d'annoncé")
        verifier(b.dictee(enCours: false) == R(commande: .couper(mac)), "fin : on recoupe le micro du Mac (celui qu'on avait rouvert), jamais les AirPods")
        var b2 = VeilleMicro()
        _ = b2.systeme(defaut: air, coupe: false)
        _ = b2.dictee(enCours: true, micro: mac, coupe: true)
        verifier(b2.systeme(defaut: mac, coupe: false) == .rien && b2.coupe, "le micro rouvert pour la dictée devient le défaut : l'îlot le montre coupé (il le sera à la fin)")
        verifier(b2.dictee(enCours: false) == R(commande: .couper(mac)) && b2.coupe, "fin : recoupé")

        var x = VeilleMicro()
        _ = x.systeme(defaut: mac, coupe: false); _ = x.basculer()
        verifier(x.dictee(enCours: true, micro: mac, coupe: true) == R(commande: .rouvrir(mac)) && x.coupe && x.rouvertPourDictee == mac, "fn pendant que c'est coupé : la dictée rouvre le micro (l'îlot garde « coupé »)")
        verifier(x.systeme(defaut: mac, coupe: false) == .rien && x.coupe, "l'écho de cette réouverture : rien, pas de « Micro ouvert »")
        verifier(x.dictee(enCours: true, micro: mac, coupe: false) == .rien, "la dictée déjà en cours : pas deux fois")
        verifier(x.dictee(enCours: false) == R(commande: .couper(mac)) && x.coupe && x.rouvertPourDictee == nil, "fin de la dictée : recoupé")
        verifier(x.systeme(defaut: mac, coupe: true) == .rien, "l'écho du recoupage : rien")
        verifier(x.systeme(defaut: mac, coupe: true) == .rien && x.coupe, "une notification en retard relue telle qu'est le micro maintenant : rien ne bouge")
        verifier(x.dictee(enCours: true, micro: air, coupe: false) == .rien && x.dictee(enCours: false) == .rien,
                 "la dictée écoute un autre micro, ouvert : on ne touche pas à celui-ci (l'appel l'entendrait)")
        _ = x.dictee(enCours: true, micro: mac, coupe: true)
        verifier(x.basculer() == R(annonce: .ouvert) && !x.coupe && x.rouvertPourDictee == nil, "raccourci pendant une dictée qui l'a rouvert : il reste ouvert (pas de commande), « Micro ouvert »")
        verifier(x.dictee(enCours: false) == .rien && !x.coupe, "fin de cette dictée : on ne recoupe pas")
        _ = x.dictee(enCours: true, micro: mac, coupe: false)
        verifier(x.basculer() == .rien && x.coupe && x.rouvertPourDictee == mac, "raccourci pendant une dictée : couper attend la fin (sinon la dictée n'entend plus rien)")
        verifier(x.dictee(enCours: false) == R(commande: .couper(mac)), "fin de la dictée : coupé")
        _ = x.basculer()
        _ = x.dictee(enCours: true, micro: air, coupe: false)
        verifier(x.basculer() == R(commande: .couper(mac)), "pendant une dictée sur un autre micro : couper tout de suite")
        _ = x.dictee(enCours: false)
        _ = x.dictee(enCours: true, micro: mac, coupe: true)
        verifier(x.systeme(defaut: mac, coupe: true) == .rien && x.rouvertPourDictee == nil && x.dictee(enCours: false) == .rien, "recoupé ailleurs pendant la dictée : rien à recouper à la fin")

        var y = VeilleMicro()
        _ = y.systeme(defaut: mac, coupe: false)
        _ = y.basculer(); y.commandeEchouee(.couper(mac))
        verifier(!y.coupe, "un micro qui ne se coupe pas : l'îlot reste sur « ouvert »")
        _ = y.systeme(defaut: mac, coupe: true); _ = y.dictee(enCours: true, micro: mac, coupe: true); y.commandeEchouee(.rouvrir(mac))
        verifier(y.coupe && y.rouvertPourDictee == nil && y.dictee(enCours: false) == .rien, "réouverture refusée pour la dictée : il reste coupé, rien à recouper")
        _ = y.dictee(enCours: true, micro: air, coupe: true); y.commandeEchouee(.rouvrir(air))
        verifier(y.coupe && y.rouvertPourDictee == nil, "réouverture refusée pour un autre micro : le micro par défaut garde son état")
        _ = y.dictee(enCours: false)
        _ = y.dictee(enCours: true, micro: mac, coupe: true)
        verifier(y.oublier() == R(commande: .couper(mac)) && !y.coupe && !y.dicteeEnCours, "réglage éteint pendant une dictée qui l'a rouvert : recoupé, puis tout est oublié")
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
    verifier(lectureM[0] == lectureX[0] && lectureM[1] == lectureX[1] && lectureM[2] == barre + GeoIlot.profondeurLecture + 54 && Array(lectureM[3...]) == Array(lectureX[3...]),
             "lecture + rangée Minuteur : même cou, même corps, 54 pt sous les commandes (maquette : 208 → 262) ; la rangée prend la place du pied")
    verifier(lectureX[2] == barre + GeoIlot.profondeurLecture + GeoIlot.piedLecture && lectureX[2] + 30 <= 330,
             "lecture dépliée : les commandes, puis le pied (bouton « Centre ») ; \(Int(lectureX[2])) pt, dans la zone de dessin (ombre comprise)")
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
                                         (.repos, .centre), (.centre, .repos), (.lectureEtendu, .centre), (.centre, .accueil), (.accueil, .centre), (.centre, .lectureCompact), (.centre, .microCompact),
                                         (.lectureCompact, .rappelEtendu), (.rappelEtendu, .lectureCompact), (.minuteurCompact, .minuteurEtendu),
                                         (.agendaCompact, .agendaEtendu), (.lectureEtendu, .minuteurFini), (.repos, .notification), (.agendaEtendu, .repos)]
    // les ressorts sont ceux du moteur (`PassageIlot.viser`), y compris interrompus à mi-course vers un troisième écran
    let tiers: [VueIlot] = [.repos, .accueil, .lectureCompact, .minuteurFini, .centre]
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
        let largeur = (r[1].x - fin[1]) / (144 - fin[1]), hauteur = (r[2].x - fin[2]) / GeoIlot.profondeur(.lectureEtendu)
        verifier(largeur < hauteur, "à 200 ms de la fermeture, la largeur a fait plus de chemin que la hauteur (\(Int(largeur * 100)) % restant contre \(Int(hauteur * 100)) %)")
    }

    groupe("Îlot : priorité et pastille")
    var e = EtatIlot()
    verifier(ArbitrageIlot.resoudre(e).principal == .repos && ArbitrageIlot.resoudre(e).survol == .centre, "rien : l'îlot est vide, au survol (ou au clic) le Centre")
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
    let ligneNuit = "{\"t\":1731312345,\"app\":\"\",\"e\":{\"hook_event_name\":\"Stop\",\"session_id\":\"nuit\"}}"
    let ligneTerminal = "{\"t\":1731312345,\"app\":\"com.apple.Terminal\",\"e\":{\"hook_event_name\":\"Stop\",\"session_id\":\"jour\"}}"
    verifier(EvenementClaude.depuis(ligne: ligneNuit).map(VeilleClaude.estSuivie) == false && EvenementClaude.depuis(ligne: ligneTerminal).map(VeilleClaude.estSuivie) == true,
             "session sans app d'origine (claude -p lancé par launchd ou cron, un SDK) : ignorée ; depuis le Terminal : suivie")
    verifier(ScriptCrochet.texte(dossier: "/tmp/x").contains("[ -n \"$S\" ] && [ -n \"$A\" ]"), "le script n'écrit rien pour une session sans app d'origine")

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

/// L'étagère : ce qu'on garde (signets, sans doublon, capacité), ce qui disparaît, le fichier, et quand le glisser ouvre l'îlot.
func controlesEtagere(_ t0: Date) {
    groupe("Îlot : l'étagère (fichiers glissés sur l'encoche)")
    func el(_ chemin: String, _ s: Double = 0) -> ElementEtagere { ElementEtagere(chemin: chemin, signet: Data(chemin.utf8), ajout: t0.addingTimeInterval(s)) }
    var e = EtagereIlot()
    verifier(e.estVide && e.resume == "Vide" && e.apercu.isEmpty, "étagère neuve : vide")
    let r1 = e.ajouter([el("/Users/h/Desktop/Contrat.pdf"), el("/Users/h/Pictures/Photo.heic", 1)])
    verifier(r1.ajoutes.count == 2 && r1.doublons == 0 && r1.sortis.isEmpty && e.elements.map(\.nom) == ["Contrat.pdf", "Photo.heic"], "deux fichiers rangés, dans l'ordre du dépôt, nom = dernier élément du chemin")
    verifier(e.resume == "2 fichiers" && EtagereIlot.resume(1) == "1 fichier", "« 2 fichiers », « 1 fichier »")
    verifier(e.apercu == "Photo.heic, Contrat.pdf", "aperçu de l'accueil : le plus récent d'abord")
    let id0 = e.elements[0].id
    let r2 = e.ajouter([el("/Users/h/Desktop/Contrat.pdf"), el("/Users/h/Desktop/./Contrat.pdf"), el("/Users/h/Desktop/Devis.pdf"), el("/Users/h/Desktop/Devis.pdf")])
    verifier(r2.ajoutes.map(\.nom) == ["Devis.pdf"] && r2.doublons == 3 && e.elements.count == 3, "sans doublon : déjà là (même chemin, « ./ » compris) ou deux fois dans le même dépôt")
    verifier(e.elements[0].id == id0, "un fichier redéposé garde sa place (et son identifiant)")
    // capacité : les plus anciens sortent
    var pleine = EtagereIlot()
    pleine.ajouter((1...10).map { el("/f/\($0).txt", Double($0)) })
    let r3 = pleine.ajouter([el("/f/11.txt"), el("/f/12.txt")])
    verifier(pleine.elements.count == EtagereIlot.capacite && r3.sortis.map(\.nom) == ["1.txt", "2.txt"] && pleine.elements.first?.nom == "3.txt" && pleine.elements.last?.nom == "12.txt",
             "au-delà de 10 : les deux plus anciens sortent, les nouveaux sont au bout")
    verifier(EtagereIlot.rangees(0) == 1 && EtagereIlot.rangees(5) == 1 && EtagereIlot.rangees(6) == 2 && EtagereIlot.rangees(10) == 2 && EtagereIlot.rangees(40) == 2, "rangées de la carte : 1 jusqu'à 5 fichiers, 2 au-delà")
    // retrait, vider
    verifier(e.retirer(id0) && !e.retirer(id0) && e.elements.map(\.nom) == ["Photo.heic", "Devis.pdf"], "« × » retire le fichier (une seule fois)")
    var v = e; v.vider()
    verifier(v.estVide, "« Tout vider »")
    // relire : disparu, déplacé, corbeille, deux signets vers le même fichier, signet renouvelé
    var d = EtagereIlot()
    d.ajouter([el("/a/Contrat.pdf"), el("/a/Photo.heic"), el("/a/Devis.pdf"), el("/a/Notes.txt"), el("/a/Copie.pdf")])
    let retires = d.relire { x in
        switch x.nom {
        case "Photo.heic": return .disparu
        case "Devis.pdf": return .present(chemin: "/b/Devis signé.pdf", signet: Data("neuf".utf8))
        case "Notes.txt": return .present(chemin: "/Users/h/.Trash/Notes.txt", signet: nil)
        case "Copie.pdf": return .present(chemin: "/a/Contrat.pdf", signet: nil)
        default: return .present(chemin: x.chemin, signet: nil)
        }
    }
    verifier(retires.map(\.nom) == ["Photo.heic", "Notes.txt", "Copie.pdf"], "relu : supprimé, mis à la Corbeille, et un 2e signet vers le même fichier sont retirés (\(retires.map(\.nom)))")
    verifier(d.elements.map(\.nom) == ["Contrat.pdf", "Devis signé.pdf"] && d.elements[1].chemin == "/b/Devis signé.pdf" && d.elements[1].signet == Data("neuf".utf8),
             "déplacé et renommé : il suit (nouveau chemin, nouveau nom, signet renouvelé)")
    verifier(d.elements[0].signet == Data("/a/Contrat.pdf".utf8), "signet encore bon : gardé tel quel")
    verifier(EtagereIlot.estALaCorbeille("/Volumes/Clé/.Trashes/501/a.pdf") && !EtagereIlot.estALaCorbeille("/Users/h/Trash notes.txt"), "corbeille d'un disque externe ; un nom qui contient « Trash » n'en est pas une")
    // fichier : aller-retour, illisible
    if let data = d.donnees(), let relu = EtagereIlot.depuis(data) {
        verifier(relu == d, "fichier : aller-retour identique (signets compris)")
    } else { verifier(false, "fichier : encodage") }
    verifier(EtagereIlot.depuis(Data("pas du json".utf8)) == nil, "fichier abîmé : refusé (gardé à part par l'app)")

    groupe("Îlot : l'étagère, le glisser près de l'encoche")
    typealias A = ApprocheEtagere
    verifier(A.ecart(x: 0, y: 10, demiCamera: 92, barre: 32) == 0 && A.ecart(x: 152, y: 20, demiCamera: 92, barre: 32) == 60, "écart : 0 sur l'encoche, 60 pt à droite de la caméra")
    verifier(A.proche(x: 150, y: 20, demiCamera: 92, barre: 32) && !A.proche(x: 160, y: 20, demiCamera: 92, barre: 32), "à 58 pt de la caméra : ouvert ; à 68 pt : rien")
    verifier(A.proche(x: 0, y: 90, demiCamera: 92, barre: 32) && !A.proche(x: 0, y: 100, demiCamera: 92, barre: 32), "sous l'encoche : jusqu'à 60 pt sous la barre")
    verifier(!A.proche(x: -400, y: 5, demiCamera: 92, barre: 32), "dans la barre des menus, loin de la caméra : rien")
    // zone ouverte : elle le reste sur la FORME ou à 40 pt autour (jugé sur le tracé, dans l'essai de bout en bout `--ilot-essai`)
    verifier(A.marge == 40, "zone ouverte : 40 pt de marge autour de la forme")
    var sg = SuiviGlisser()
    verifier(!sg.nouveau(compte: 5), "sans appui vu : pas un glisser de fichiers")
    sg.bouton(enfonce: true, compte: 5)
    verifier(!sg.nouveau(compte: 5), "presse-papiers du glisser inchangé depuis l'appui (texte étiré, fenêtre déplacée) : rien, même s'il garde les fichiers d'avant")
    verifier(sg.nouveau(compte: 6), "il a changé depuis l'appui : un vrai glisser")
    sg.bouton(enfonce: false, compte: 0)
    verifier(!sg.nouveau(compte: 7) && sg.compteAuClic == nil, "bouton relâché : oublié")

    groupe("Îlot : l'étagère, géométrie")
    for (barre, demi) in [(32.0, 92.0), (37.0, 100.0)] {
        for (vue, plus) in [(VueIlot.etagereDepot, 0.0), (.etagere, 0), (.etagere, GeoIlot.rangeeEtagere), (.accueil, GeoIlot.ligneAccueil), (.lectureMinuteur, GeoIlot.ligneAccueil)] {
            let g = GeoIlot.valeurs(vue, hauteurBarre: barre, demiCamera: demi, epaules: true, enPlus: plus)
            let p = TraceIlot.calculer(g, demiCamera: demi, barre: barre)
            verifier(p.bande <= demi + GeoIlot.aileMax + 0.001, "\(vue.rawValue)\(plus > 0 ? " + \(Int(plus)) pt" : "") : \(String(format: "%.0f", p.bande - demi)) pt dans la barre de chaque côté (≤ 66)")
            verifier(g[2] + 0 <= 330, "\(vue.rawValue)\(plus > 0 ? " + \(Int(plus)) pt" : "") : \(Int(g[2])) pt de haut, dans la zone de dessin (330)")
        }
    }
    let acc = GeoIlot.valeurs(.accueil, hauteurBarre: 32), accPlus = GeoIlot.valeurs(.accueil, hauteurBarre: 32, enPlus: GeoIlot.ligneAccueil)
    verifier(accPlus[2] - acc[2] == 42 && accPlus[1] == acc[1], "accueil avec l'étagère : une ligne de 42 pt de plus, même largeur")
    verifier(GeoIlot.valeurs(.etagereDepot, hauteurBarre: 32)[1] == GeoIlot.valeurs(.accueil, hauteurBarre: 32)[1], "« Déposez ici » : la largeur de l'accueil")
    verifier(GeoIlot.profondeur(.etagereDepot) == 16 + 70 + 16, "« Déposez ici » : 70 pt de zone, 16 pt de marge dessus et dessous (maquette)")
    verifier(!VueIlot.etagereDepot.estBandeau && !VueIlot.etagere.estBandeau && !GeoIlot.ajusteAuContenu(.etagere), "ni bandeau ni écran ajusté au contenu")
    controlesCentre()
}

/// Le Centre (maquette design/maquettes/ilot-centre.html) : la pile des cartes, le défilement (un geste = une carte), la géométrie.
func controlesCentre() {
    groupe("Îlot : le Centre, les cartes")
    verifier(CartesIlot.pile(survol: .centre) == [.centre, .dictees, .accueil], "rien ne joue : le Centre d'abord, les Dictées, l'accueil dessous")
    verifier(CartesIlot.pile(survol: .lectureEtendu) == [.lectureEtendu, .centre, .dictees, .accueil], "une vidéo : la lecture, le Centre, les Dictées, l'accueil (maquette : vidéo, Centre, Dictées)")
    verifier(CartesIlot.pile(survol: .lectureMinuteur) == [.lectureEtendu, .centre, .dictees, .accueil], "la rangée Minuteur compte comme la lecture")
    verifier(CartesIlot.pile(survol: .minuteurEtendu) == [.minuteurEtendu, .centre, .dictees, .accueil] && CartesIlot.pile(survol: .microEtendu).first == .microEtendu,
             "un minuteur, le micro coupé : leur déplié, puis le Centre")
    verifier(CartesIlot.pile(survol: nil).isEmpty, "verrouillé (alerte, bandeau) : aucune carte")
    let p = CartesIlot.pile(survol: .lectureEtendu)
    verifier(CartesIlot.voisine(p, de: .lectureEtendu, pas: 1) == .centre && CartesIlot.voisine(p, de: .centre, pas: 1) == .dictees
             && CartesIlot.voisine(p, de: .dictees, pas: 1) == .accueil && CartesIlot.voisine(p, de: .dictees, pas: -1) == .centre
             && CartesIlot.voisine(p, de: .centre, pas: -1) == .lectureEtendu && CartesIlot.voisine(p, de: .lectureMinuteur, pas: 1) == .centre,
             "carte suivante, précédente (le Centre → les Dictées → l'accueil ; depuis la rangée Minuteur aussi)")
    verifier(CartesIlot.voisine(p, de: .accueil, pas: 1) == nil && CartesIlot.voisine(p, de: .lectureEtendu, pas: -1) == nil && CartesIlot.voisine(p, de: .etagere, pas: 1) == nil,
             "au bout de la pile : rien (on ne boucle pas) ; hors de la pile : rien")
    verifier(ArbitrageIlot.resoudre(EtatIlot()).survol == .centre, "l'îlot vide s'ouvre sur le Centre")
    verifier(CartesIlot.survol(.microEtendu, deuxieme: nil) == .centre && CartesIlot.survol(.microEtendu, deuxieme: .lectureEtendu) == .lectureEtendu
             && CartesIlot.survol(.lectureEtendu, deuxieme: .minuteurEtendu) == .lectureEtendu,
             "micro coupé au survol : la vidéo en bulle, sinon le Centre (le bouton Micro y est) ; les autres activités gardent leur déplié")
    // le bouton « Centre » au pied de TOUT déplié d'activité (relecture : il n'existait que sous la lecture)
    for v in [VueIlot.lectureEtendu, .minuteurEtendu, .claudeEtendu, .agendaEtendu, .rappelEtendu] {
        let pile = CartesIlot.pile(survol: v)
        verifier(CartesIlot.aUnPied(v, pile: pile) && !CartesIlot.aUnPied(.centre, pile: pile) && !CartesIlot.aUnPied(.accueil, pile: pile)
                 && !CartesIlot.aUnPied(.dictees, pile: pile),
                 "\(v.rawValue) : les boutons « Centre » et « Dictées » à son pied (pas sur le Centre, les Dictées ni l'accueil)")
        verifier(CartesIlot.piedEnPlus(v, pile: pile) == (v == .lectureEtendu ? 0 : GeoIlot.piedLecture),
                 "\(v.rawValue) : le pied ajoute \(Int(CartesIlot.piedEnPlus(v, pile: pile))) pt (la lecture l'a déjà dans sa géométrie)")
        for barre in [32.0, 37.0] {
            let h = GeoIlot.valeurs(v, hauteurBarre: barre, enPlus: CartesIlot.piedEnPlus(v, pile: pile))[2]
            verifier(h + 30 <= 380, "\(v.rawValue) avec son pied (barre \(Int(barre))) : \(Int(h)) pt + 30 d'ombre, dans la zone de dessin (380)")
        }
    }
    verifier(!CartesIlot.aUnPied(.lectureMinuteur, pile: CartesIlot.pile(survol: .lectureMinuteur)) && !CartesIlot.aUnPied(.centre, pile: CartesIlot.pile(survol: .centre))
             && !CartesIlot.aUnPied(.minuteurEtendu, pile: []),
             "pas de pied : sous la rangée Minuteur (elle prend sa place), sur l'îlot vide (il s'ouvre sur le Centre), verrouillé (alerte, bandeau)")

    groupe("Îlot : le Centre, le défilement (un geste = une carte)")
    var d = DefilementIlot()
    // deux doigts vers le haut (défilement naturel : dy négatif chez AppKit) : la carte d'en dessous, une seule fois par geste
    verifier(d.recevoir(dy: -4, phase: .debut, inertie: false, t: 0) == nil, "début du geste, 4 pt : rien encore")
    verifier(d.recevoir(dy: -6, phase: .suite, inertie: false, t: 0.02) == nil, "10 pt : rien (seuil \(Int(DefilementIlot.seuil)) pt)")
    verifier(d.recevoir(dy: -6, phase: .suite, inertie: false, t: 0.04) == 1, "16 pt vers le bas : la carte suivante")
    verifier(d.recevoir(dy: -40, phase: .suite, inertie: false, t: 0.06) == nil && d.recevoir(dy: 30, phase: .suite, inertie: false, t: 0.08) == nil,
             "le même geste continue (même en revenant) : pas une 2e carte")
    verifier(d.recevoir(dy: 0, phase: .fin, inertie: false, t: 0.1) == nil, "doigts levés : fin du geste")
    verifier(d.recevoir(dy: -30, phase: .aucune, inertie: true, t: 0.12) == nil && d.recevoir(dy: -30, phase: .suite, inertie: true, t: 0.14) == nil, "l'inertie est ignorée")
    verifier(d.recevoir(dy: 9, phase: .debut, inertie: false, t: 0.5) == nil && d.recevoir(dy: 9, phase: .suite, inertie: false, t: 0.52) == -1, "nouveau geste, vers le haut : la carte précédente")
    _ = d.recevoir(dy: 0, phase: .fin, inertie: false, t: 0.6)
    verifier(d.recevoir(dy: -3, dx: -30, phase: .debut, inertie: false, t: 1) == nil && d.recevoir(dy: -12, dx: -40, phase: .suite, inertie: false, t: 1.02) == nil,
             "un défilement surtout horizontal ne compte pas")
    _ = d.recevoir(dy: 0, phase: .fin, inertie: false, t: 1.1)
    verifier(d.recevoir(dy: -10, phase: .aucune, inertie: false, t: 2) == 1, "molette, un cran vers le bas : la carte suivante")
    verifier(d.recevoir(dy: -10, phase: .aucune, inertie: false, t: 2.1) == nil, "molette lancée : pas plus d'une carte par \(String(format: "%.2f", DefilementIlot.pauseMolette)) s")
    verifier(d.recevoir(dy: 10, phase: .aucune, inertie: false, t: 2.5) == -1, "molette vers le haut, après la pause : la carte précédente")

    groupe("Îlot : le Centre, la géométrie")
    for (barre, demi) in [(32.0, 100.0), (33.0, 89.5), (37.0, 92.0)] {
        let c = GeoIlot.valeurs(.centre, hauteurBarre: barre, demiCamera: demi, epaules: true)
        let t = TraceIlot.calculer(c, demiCamera: demi, barre: barre)
        verifier(t.bande <= demi + GeoIlot.aileMax + 0.001, "Centre (caméra \(Int(2 * demi)), barre \(Int(barre))) : dans la barre, \(String(format: "%.0f", t.bande - demi)) pt de chaque côté (≤ 66), épaules comprises")
        verifier(c[2] == barre + 298 && c[2] + 30 <= 380, "Centre (avec la bande de la réunion) : \(Int(c[2])) pt de haut (maquette : 331 avec une barre de 33), + 30 pt d'ombre, dans la zone de dessin (380)")
        // sans la bande (« Modifier ») : 50 pt de moins
        let ps = DispositionCentre.plan(ronds: true, cases: true, bande: false).profondeur
        let cs = GeoIlot.valeurs(.centre, hauteurBarre: barre, demiCamera: demi, epaules: true, enPlus: ps - GeoIlot.profondeurCentre)
        verifier(cs[2] == barre + 248, "Centre sans la réunion : \(Int(cs[2])) pt de haut (maquette sans la bande : 281)")
        verifier(c[1] == GeoIlot.valeurs(.lectureEtendu, hauteurBarre: barre)[1] && c[1] == GeoIlot.valeurs(.accueil, hauteurBarre: barre)[1],
                 "Centre, lecture, accueil : la même largeur (on passe d'une carte à l'autre sans que la forme s'élargisse)")
        // la bulle « Nouveau » sous la lecture repliée et sous l'îlot vide
        for v in [VueIlot.lectureCompact, .repos, .minuteurCompact] {
            let g = GeoIlot.valeurs(v, hauteurBarre: barre, demiCamera: demi)
            let b = GeoIlot.avecBulle(g, hauteurBarre: barre, demiCamera: demi, contenu: 190)
            let tb = TraceIlot.calculer(b, demiCamera: demi, barre: barre)
            verifier(b[0] == g[0] && b[2] == barre + GeoIlot.profondeurBulle && tb.bande <= demi + GeoIlot.aileMax + 0.001 && tb.corps >= 95 + 16 - 0.01 && tb.corps >= tb.bande + 20,
                     "bulle « Nouveau » sous \(v.rawValue) : le cou ne bouge pas, 40 pt sous la barre, le corps épouse le texte (\(Int(2 * tb.corps)) pt)")
        }
    }
    verifier(GeoIlot.aEpaules(.centre) && !VueIlot.centre.estBandeau && !GeoIlot.ajusteAuContenu(.centre), "Centre : un écran déplié, avec les épaules (batterie, AirPods)")
    verifier(GeoIlot.profondeur(.centre) == 298, "Centre : 14 + 26 + 12 + 96 + 10 + 76 + 10 + 40 + 14 = 298 pt sous la barre (maquette : 331 − 33)")
    controlesDispositionCentre()
    controlesDictees()
}

/// La carte Dictées (maquette ilot-centre.html, étapes 10 à 12) : sa géométrie (elle épouse sa liste), le défilement de la liste, les mots
/// surlignés, l'icône de la barre des menus.
func controlesDictees() {
    groupe("Îlot : les Dictées, la géométrie")
    verifier(CarteDictees.profondeurMax == 298 && GeoIlot.profondeur(.dictees) == 298, "Dictées au plus haut : 14 + 30 + 6 + 200 + 34 + 14 = 298 pt sous la barre (maquette : 331 − 33)")
    verifier(GeoIlot.aEpaules(.dictees) && !VueIlot.dictees.estBandeau && !GeoIlot.ajusteAuContenu(.dictees), "Dictées : un écran déplié, avec les épaules")
    for (barre, demi) in [(32.0, 100.0), (33.0, 89.5), (37.0, 92.0)] {
        let c = GeoIlot.valeurs(.dictees, hauteurBarre: barre, demiCamera: demi, epaules: true)
        let t = TraceIlot.calculer(c, demiCamera: demi, barre: barre)
        verifier(t.bande <= demi + GeoIlot.aileMax + 0.001, "Dictées (caméra \(Int(2 * demi)), barre \(Int(barre))) : \(String(format: "%.0f", t.bande - demi)) pt dans la barre de chaque côté (≤ 66)")
        verifier(c[1] == GeoIlot.valeurs(.centre, hauteurBarre: barre, demiCamera: demi)[1], "Dictées : la largeur du Centre (on passe de l'un à l'autre sans que la forme s'élargisse)")
        verifier(c[2] + 30 <= 380, "Dictées au plus haut : \(Int(c[2])) pt + 30 d'ombre, dans la zone de dessin (380)")
    }
    // la carte épouse sa liste : « Aucun résultat » (~172 pt avec la barre de 33), deux jours de trois lignes, au-delà elle défile
    let rien = CarteDictees.profondeur(liste: CarteDictees.hauteurListe(lignesParJour: []))
    verifier(abs(rien + 33 - 172) <= 8, "Dictées, « Aucun résultat » : \(Int(rien + 33)) pt de haut avec une barre de 33 (maquette : ~172)")
    let deux = CarteDictees.hauteurListe(lignesParJour: [1, 1])
    verifier(deux == 2 * 20 + 2 * 32, "« devis » : deux jours d'une ligne = \(Int(deux)) pt de liste")
    let six = CarteDictees.hauteurListe(lignesParJour: [4, 2])
    verifier(six == 2 * 20 + 6 * 32 && CarteDictees.profondeur(liste: six) == 298, "six dictées sur deux jours (\(Int(six)) pt) : la carte à son plus haut, la liste défile (\(Int(six - 200)) pt cachés)")
    verifier(CarteDictees.hauteurListe(lignesParJour: [1], deplie: 31) == 20 + 32 + 31, "une ligne dépliée ajoute sa hauteur")
    verifier(CarteDictees.ligneDepliee(lignesDeTexte: 1) == 34 && CarteDictees.ligneDepliee(lignesDeTexte: 3) == 76, "ligne dépliée : 6 + 21 par ligne de texte + 7")
    verifier(CarteDictees.borner(-20, liste: six) == 0 && CarteDictees.borner(500, liste: six) == six - 200 && CarteDictees.borner(30, liste: six) == 30
             && CarteDictees.borner(30, liste: 150) == 0, "défilement borné : ni au-dessus du haut, ni plus bas que la fin ; une liste courte ne défile pas")

    groupe("Îlot : les Dictées, où une ligne prend les clics")
    let L = CarteDictees.listeMax
    verifier(CarteDictees.partieCliquable(y: 20, h: 32, decalage: 0, liste: L).map { $0 == (0, 32) } == true, "une ligne entière à l'écran : toute la ligne")
    verifier(CarteDictees.partieCliquable(y: 180, h: 32, decalage: 0, liste: L) == nil && CarteDictees.partieCliquable(y: 20, h: 32, decalage: 30, liste: L) == nil,
             "une ligne à moitié sous le bas ou sous le haut : aucun clic (il visait ce qui est autour)")
    // une longue dictée dépliée : 9 lignes de texte = 6 + 21 × 9 + 7 = 202 pt, plus haute que la liste (200) ; elle ne tient jamais entière
    let longue = CarteDictees.ligneDepliee(lignesDeTexte: 9)
    verifier(longue == 202 && longue > L, "une dictée dépliée de 9 lignes : \(Int(longue)) pt, plus haute que la liste (\(Int(L)))")
    let enHaut = CarteDictees.partieCliquable(y: 20, h: longue, decalage: 0, liste: L)
    verifier(enHaut.map { $0 == (0, 180) } == true, "dépliée, en haut de la liste : cliquable sur sa partie visible (0 à 180 pt), pas sur le pied")
    let auMilieu = CarteDictees.partieCliquable(y: 20, h: longue, decalage: 21, liste: L)
    verifier(auMilieu.map { abs($0.debut - 1) < 0.001 && abs($0.fin - 201) < 0.001 } == true, "défilée de 21 pt : sa partie visible (1 à 201 pt), pas l'en-tête au-dessus")
    verifier(CarteDictees.partieCliquable(y: 20, h: 500, decalage: 300, liste: L).map { $0 == (280, 480) } == true, "très longue, défilée au milieu : les 200 pt visibles")
    verifier(CarteDictees.partieCliquable(y: 20, h: longue, decalage: 300, liste: L) == nil, "sortie par le haut : aucun clic")

    groupe("Îlot : les Dictées, à qui va le geste (la liste ou les cartes)")
    var a = DefilementIlot()
    // parti du Centre, le pointeur au milieu (là où sera la liste) : la carte change en chemin, la suite et l'inertie n'y vont pas
    verifier(!a.pourLaListe(phase: .debut, inertie: false, surListe: false), "geste commencé sur le Centre : aux cartes")
    verifier(!a.pourLaListe(phase: .suite, inertie: false, surListe: true) && !a.pourLaListe(phase: .fin, inertie: false, surListe: true),
             "la carte est passée aux Dictées en plein geste : la suite reste aux cartes (la liste ne bouge pas)")
    verifier(!a.pourLaListe(phase: .aucune, inertie: true, surListe: true), "son inertie non plus")
    // parti de la liste : la suite et l'inertie la font défiler, même si le pointeur en sort
    verifier(a.pourLaListe(phase: .debut, inertie: false, surListe: true) && a.pourLaListe(phase: .suite, inertie: false, surListe: false)
             && a.pourLaListe(phase: .aucune, inertie: true, surListe: false), "geste commencé sur la liste : elle défile jusqu'au bout, inertie comprise")
    verifier(!a.pourLaListe(phase: .debut, inertie: false, surListe: false), "geste suivant, commencé ailleurs : aux cartes")
    verifier(a.pourLaListe(phase: .aucune, inertie: false, surListe: true) && !a.pourLaListe(phase: .aucune, inertie: false, surListe: false),
             "molette : chaque cran décide là où il tombe")

    groupe("Îlot : les Dictées, les mots surlignés")
    verifier(Surlignage.plages("OK pour le devis de la cuisine", requete: "devis") == [11 ..< 16], "« devis » : le mot, à sa place")
    verifier(Surlignage.plages("Le DÉVIS signé", requete: "devis") == [3 ..< 8], "sans accents ni majuscules : « DÉVIS » trouvé par « devis »")
    verifier(Surlignage.plages("Café crème", requete: "cafe creme") == [0 ..< 4, 5 ..< 10], "plusieurs mots : chacun surligné")
    verifier(Surlignage.plages("devis, devis", requete: "devis") == [0 ..< 5, 7 ..< 12], "chaque occurrence")
    verifier(Surlignage.plages("l\u{2019}équipe", requete: "l'equipe") == [0 ..< 8], "l'apostrophe typographique trouvée par l'apostrophe droite")
    verifier(Surlignage.plages("Rien à voir", requete: "devis").isEmpty && Surlignage.plages("Texte", requete: "  ").isEmpty, "pas trouvé, ou recherche vide : rien")
    verifier(Surlignage.plages("Œuvre 🎉 devis", requete: "devis") == [8 ..< 13], "les positions comptent des caractères (emoji compris)")

    groupe("Îlot : l'icône de la barre des menus")
    verifier(!PresenceIcone.montree(reglage: nil, encoche: true), "Mac à encoche, jamais réglée : pas d'icône (tout est dans l'îlot)")
    verifier(PresenceIcone.montree(reglage: true, encoche: true) && !PresenceIcone.montree(reglage: false, encoche: true), "Mac à encoche : le réglage décide")
    verifier(PresenceIcone.montree(reglage: nil, encoche: false) && PresenceIcone.montree(reglage: false, encoche: false),
             "sans encoche (écran externe principal) : l'icône toujours là, même éteinte dans les réglages (l'îlot vide n'existe pas)")
}

/// « Modifier » le Centre : ce qu'il montre, dans quel ordre, ce qui est rangé dans les réglages, et la place que ça prend.
func controlesDispositionCentre() {
    groupe("Îlot : le Centre, « Modifier » (ajouter, retirer, ranger)")
    typealias D = DispositionCentre
    let tout: (ElementCentre) -> Bool = { _ in true }
    let sansAirPods: (ElementCentre) -> Bool = { $0 != .dictee }
    // la valeur par défaut, et ce qui est rangé dans les réglages
    let d0 = D(identifiants: nil)
    verifier(d0.elements == [.micro, .dictee, .telechargements, .claude, .minuteur, .etagere, .reunion], "jamais modifié : micro, dictée, Téléchargements, Claude Code, minuteur, étagère, réunion (maquette, étape 3)")
    verifier(d0.ronds(disponible: sansAirPods) == [.micro, .telechargements, .claude] && d0.ronds(disponible: tout).count == 4 && d0.cases == [.minuteur, .etagere] && d0.bande,
             "par défaut : 3 ronds sans AirPods (4 avec), les deux cases, la bande « Noter la réunion »")
    verifier(D(identifiants: d0.identifiants) == d0 && d0.identifiants.contains("derniere-dictee") == false && ElementCentre.derniereDictee.rawValue == "derniere-dictee",
             "les identifiants rangés se relisent à l'identique")
    verifier(D(identifiants: ["claude", "fusee", "micro", "claude", "etagere"]).elements == [.claude, .micro, .etagere], "identifiants inconnus et doublons ignorés, l'ordre gardé")
    verifier(D(identifiants: ["fusee", "laser"]) == d0, "plus rien de connu dans une liste non vide (réglage abîmé, version plus récente) : la valeur par défaut")
    verifier(D(identifiants: []).elements.isEmpty, "une liste vide est un choix (tout retiré) : gardée vide")
    // retirer
    var d = d0
    verifier(d.retirer(.telechargements) && !d.retirer(.telechargements) && d.ronds(disponible: tout) == [.micro, .dictee, .claude], "« – » sur Téléchargements : retiré (une seule fois)")
    verifier(d.retirer(.minuteur) && d.cases == [.etagere], "« – » sur Minuteur : l'étagère reste seule")
    // ajouter : ce qui n'est pas montré, dans l'ordre du catalogue ; à la fin de son genre
    verifier(d.aAjouter(disponible: tout) == [.telechargements, .rappel, .derniereDictee, .minuteur], "« Ajouter : » propose ce qui n'est pas montré, dans l'ordre du catalogue")
    verifier(d0.aAjouter(disponible: sansAirPods) == [.rappel, .derniereDictee], "par défaut : « + Rappel », « + Dernière dictée » (maquette, étape 9) ; sans AirPods, pas le choix du micro")
    verifier(d.ajouter(.rappel) && d.elements == [.micro, .dictee, .claude, .rappel, .etagere, .reunion], "+ Rappel : à la fin des ronds (l'ordre d'ajout), avant les cases")
    verifier(d.ajouter(.minuteur) && d.cases == [.etagere, .minuteur], "+ Minuteur : après l'étagère")
    verifier(d.retirer(.reunion) && !d.bande && d.ajouter(.reunion) && d.bande && d.elements.last == .reunion, "« – » puis « + » Réunion : la bande revient en bas")
    verifier(!d.ajouter(.rappel) && d.elements.filter { $0 == .rappel }.count == 1, "déjà là : pas ajouté deux fois")
    verifier(d.ajouter(.telechargements) && d.ronds(disponible: tout) == [.micro, .dictee, .claude, .rappel, .telechargements], "cinq ronds")
    verifier(!d.peutAjouter(.derniereDictee, disponible: tout) && !d.ajouter(.derniereDictee, disponible: tout), "rangée pleine (5) : un 6e rond est refusé")
    verifier(d.peutAjouter(.derniereDictee, disponible: sansAirPods) && d.ronds(disponible: sansAirPods).count == 4, "sans AirPods, la dictée ne prend pas de place : il en reste une")
    let pleine = D([.micro, .dictee, .telechargements, .claude, .rappel, .derniereDictee])
    verifier(pleine.ronds(disponible: tout).count == D.maxRonds && pleine.ronds(disponible: sansAirPods).last == .derniereDictee,
             "six ronds rangés (AirPods partis puis revenus) : cinq au plus à l'écran")
    // ranger en glissant
    var r = D([.micro, .dictee, .telechargements, .claude, .minuteur, .etagere])
    let vis = r.ronds(disponible: tout)
    verifier(r.deplacer(.claude, versRang: 0, parmi: vis) && r.ronds(disponible: tout) == [.claude, .micro, .dictee, .telechargements], "Claude glissé tout à gauche")
    verifier(r.deplacer(.claude, versRang: 9, parmi: r.ronds(disponible: tout)) && r.ronds(disponible: tout) == [.micro, .dictee, .telechargements, .claude], "puis tout à droite (rang borné)")
    verifier(!r.deplacer(.claude, versRang: 3, parmi: r.ronds(disponible: tout)), "lâché à sa place : rien ne change")
    verifier(r.deplacer(.micro, versRang: 1, parmi: r.ronds(disponible: sansAirPods)) && r.elements == [.dictee, .telechargements, .micro, .claude, .minuteur, .etagere],
             "sans AirPods, Micro glissé d'un cran : il passe après Téléchargements, la dictée (cachée) garde sa place")
    verifier(r.deplacer(.etagere, versRang: 0, parmi: r.cases) && r.cases == [.etagere, .minuteur] && !r.deplacer(.reunion, versRang: 0, parmi: r.cases), "les cases s'échangent ; un élément absent ne bouge rien")
    verifier(D(identifiants: r.identifiants) == r, "l'ordre rangé se relit à l'identique")
    // la place
    let p0 = D.plan(ronds: true, cases: true, bande: true)
    verifier(p0.profondeur == GeoIlot.profondeurCentre && p0.hauts[.ronds] == 52 && p0.hauts[.cases] == 158 && p0.hauts[.bande] == 244,
             "par défaut : la profondeur de la table (298), ronds à 52 pt, cases à 158 pt, bande à 244 pt")
    verifier(D.plan(ronds: true, cases: true, bande: false).profondeur == 248, "sans la bande : 248 pt (maquette sans la réunion : 281 − 33)")
    verifier(D.plan(ronds: false, cases: true, bande: false).hauts[.cases] == 52 && D.plan(ronds: false, cases: true, bande: false).profondeur == 54 + 12 + 76,
             "sans ronds : les cases montent sous l'en-tête (12 pt d'écart)")
    verifier(D.plan(ronds: false, cases: false, bande: false).profondeur == 54, "tout retiré : l'en-tête seul (« Modifier » pour en remettre)")
    let g = GeoIlot.valeurs(.centre, hauteurBarre: 33, enPlus: 54 - GeoIlot.profondeurCentre)
    verifier(g[2] == 33 + 54, "une profondeur plus petite que la table passe par `enPlus` négatif")
    // les noms sous les ronds : un nom court laisse sa place à un voisin long ; deux longs cèdent ; jamais moins de `ecart` entre eux
    let lp = D.largeursPermises([36, 95, 70], colonne: 84, ecart: 4)
    verifier(lp == [36, 90, 70], "« Micro », « Téléchargements » (95 pt), « Claude Code » dans 84 pt : le long déborde chez « Micro », cède 5 pt pour garder 4 pt avec « Claude Code »")
    let lq = D.largeursPermises([95, 84.5, 36], colonne: 84, ecart: 4)
    verifier(lq[0] <= 84 && (lq[0] + lq[1]) / 2 + 4 <= 84 + 1e-9 && lq[2] == 36, "« Téléchargements » au bord, « Dernière dictée » à côté : le bord tient dans sa colonne, les deux voisins gardent 4 pt")
    let lr = D.largeursPermises([95, 95, 95, 95, 95], colonne: 84, ecart: 4)
    verifier(lr.allSatisfy { abs($0 - 80) < 1e-9 }, "cinq noms trop longs : chacun 80 pt (84 − 4)")
    verifier(D.largeursPermises([], colonne: 84, ecart: 4).isEmpty && D.largeursPermises([120], colonne: 400, ecart: 4) == [120], "rien, ou un seul nom qui tient : inchangé")
    // les pastilles « Ajouter : » qui tiennent dans la ligne
    let m3: (Int) -> Double = { _ in 20 }
    verifier(D.pastillesQuiTiennent([70, 120, 80], place: 300, ecart: 6, marque: m3) == 3, "trois pastilles qui tiennent : toutes")
    verifier(D.pastillesQuiTiennent([70, 120, 80, 90], place: 300, ecart: 6, marque: m3) == 2, "une de trop : deux, puis « +2 » (qui doit tenir aussi)")
    verifier(D.pastillesQuiTiennent([400], place: 300, ecart: 6, marque: m3) == 0 && D.pastillesQuiTiennent([], place: 300, ecart: 6, marque: m3) == 0, "aucune ne tient, ou rien à ajouter : zéro")
}
