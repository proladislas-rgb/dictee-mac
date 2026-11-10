import AppKit
import DicteeCore

/// `Verbe --lecture-essai [--app identifiant]` : essai de bout en bout de la lecture en cours, SANS rien montrer à l'écran (fenêtres
/// transparentes qui ne reçoivent aucun clic). Lance le vrai programme d'aide, attend un morceau, déplie et referme l'îlot, simule une
/// dictée (pause au début, reprise à la fin) et vérifie les états. La simulation de dictée n'a lieu que si l'app qui joue est `--app`
/// (par défaut « source-test », une source de test à volume 0) : on n'envoie jamais de commande au vrai lecteur de Hugues.
/// Ni micro, ni clavier, ni Accessibilité, ni son.
enum LectureEssai {
    @MainActor
    static func executer(arguments: [String]) -> Int32 {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let appVoulue = arguments.firstIndex(of: "--app").flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil } ?? "source-test"
        var echecs = 0
        func verifier(_ ok: Bool, _ nom: String) { print(ok ? "  ok   \(nom)" : "  ÉCHEC \(nom)"); if !ok { echecs += 1 } }
        func attendre(_ s: Double, tant: () -> Bool = { true }) {
            let fin = Date().addingTimeInterval(s)
            while Date() < fin, tant() { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02)) }
        }

        let c = LectureControleur()
        c.essaiInvisible = true
        c.systeme.appExclusive = appVoulue   // jamais de commande vers une autre app que la source de test
        c.demarrer()
        attendre(8) { c.modele.morceau == nil }
        guard let m = c.modele.morceau else {
            print("rien ne joue : essai interrompu (lancer une source, par exemple la source de test)")
            c.arreter(); return 1
        }
        print("morceau reçu : app=\(m.app ?? "-") joue=\(m.joue) durée=\(m.duree.map { String(Int($0)) } ?? "direct") image=\(c.modele.image != nil) teinte=\(c.modele.teinte.clair.hexa)")
        attendre(0.8)
        verifier(c.affichage == .ilot, "rien d'autre à l'écran : l'îlot s'affiche")
        verifier(c.panneau.estVisible, "la fenêtre de l'îlot est là")
        let repos = c.panneau.cadre
        print("  fenêtre au repos : \(repos.map { "\(Int($0.width)) × \(Int($0.height))" } ?? "-")")

        // forme : dans la hauteur de la barre des menus, l'îlot (au repos comme déplié) ne dépasse jamais la bande de la dictée
        let g = c.modele.geometrie
        for (nom, p) in [("au repos", CGFloat(0)), ("déplié", CGFloat(1))] {
            let largeur = p == 0 ? LectureMesures.largeurRepos(g) : LectureMesures.ouvertLargeur
            let hauteur = p == 0 ? g.hauteur : LectureMesures.hauteurOuvert(g)
            let forme = FormeIlot(largeur: largeur, hauteur: hauteur, rayon: p == 0 ? g.hauteur / 2 : LectureMesures.rayonOuvert, oreille: p == 0 ? 0 : 1,
                                  largeurBarre: LectureMesures.largeurBarre(g), hauteurBarre: g.hauteur)
            let cadre = CGRect(x: 0, y: 0, width: largeur + 60, height: hauteur + 10)
            let chemin = forme.path(in: cadre)
            let demiBande = LectureMesures.largeurBarre(g) / 2, ears: CGFloat = p == 0 ? 0 : 10
            var depasse = 0
            var y: CGFloat = 0.5
            while y < g.hauteur - 0.5 { // hauteur de la barre des menus (hors congé de l'épaule, qui commence à g.hauteur)
                for sens in [CGFloat(-1), 1] where chemin.contains(CGPoint(x: cadre.midX + sens * (demiBande + ears + 0.6), y: y)) { depasse += 1 }
                y += 0.5
            }
            verifier(depasse == 0, "\(nom) : dans la barre des menus, jamais plus large que la bande de la dictée (\(Int(demiBande * 2)) pt + oreilles de \(Int(ears)) pt ; dictée : oreilles de \(Int(GeometrieEncoche.aile * 0 + FormeEncoche.congeHaut.width)) pt)")
            if p == 1 { verifier(chemin.contains(CGPoint(x: cadre.midX + LectureMesures.ouvertLargeur / 2 - 3, y: hauteur / 2)), "déplié : le corps est plus large que la bande, sous la barre des menus") }
        }
        verifier(repos.map { $0.width <= LectureMesures.largeurRepos(g) + 2 * LectureMesures.margeReposLaterale + 0.5 } ?? false, "la fenêtre de repos ne déborde pas de la forme de plus de \(Int(LectureMesures.margeReposLaterale)) pt (aucun clic pris aux icônes voisines)")

        // survol avec intention : un passage rapide n'ouvre rien
        c.panneau.survol(true); attendre(0.1); c.panneau.survol(false); attendre(0.7)
        verifier(c.modele.progres < 0.01 && c.panneau.cadre?.width == repos?.width, "passage rapide de la souris (0,1 s) : rien ne s'ouvre, rien ne bouge")
        // la souris reste : ouverture après l'intention (0,28 s), pas avant
        c.panneau.survol(true)
        attendre(0.2)
        verifier(c.modele.progres < 0.01, "souris posée depuis 0,2 s : toujours fermé (intention)")
        attendre(1.1)
        verifier(c.modele.progres > 0.95 && c.modele.progres < 1.15, "souris posée : déplié (progression \(String(format: "%.2f", Double(c.modele.progres))))")
        let ouvert = c.panneau.cadre
        verifier((ouvert?.width ?? 0) > (repos?.width ?? 0) && (ouvert?.height ?? 0) > (repos?.height ?? 0), "la fenêtre grandit avec l'îlot")
        print("  fenêtre au repos \(repos.map { "\(Int($0.width)) × \(Int($0.height))" } ?? "-") ; dépliée \(ouvert.map { "\(Int($0.width)) × \(Int($0.height))" } ?? "-")")
        if let o = ouvert, let r = repos { verifier(abs(o.midX - r.midX) <= 1 && abs(o.maxY - r.maxY) < 0.5, "centrée sur la caméra, collée en haut de l'écran (le centre ne bouge pas)") }
        // fermeture retardée de 0,45 s, annulée si la souris revient
        c.panneau.survol(false)
        attendre(0.25)
        verifier(c.modele.progres > 0.95, "souris sortie depuis 0,25 s : toujours ouvert (délai de 0,45 s)")
        c.panneau.survol(true); attendre(0.6)
        verifier(c.modele.progres > 0.95, "souris revenue avant 0,45 s : la fermeture est annulée")
        c.panneau.survol(false)
        attendre(0.5)
        verifier(c.modele.progres < 0.97, "souris sortie depuis 0,5 s : la fermeture a commencé")
        attendre(1.2)
        verifier(c.modele.progres < 0.02, "puis refermé")
        verifier(c.panneau.cadre.map { $0.width == repos?.width } ?? false, "la fenêtre reprend sa taille de repos")
        // interruption : la souris revient pendant la fermeture (la fenêtre est encore grande) : réouverture TOUT DE SUITE, sans attendre l'intention.
        // (La progression du modèle est la cible du ressort ; la valeur affichée, elle, repart de l'état courant avec sa vitesse : c'est le
        // comportement de SwiftUI, vérifié sur les rendus mi-course, pas ici.)
        c.panneau.survol(true); attendre(1.2); c.panneau.survol(false); attendre(0.45 + 0.1)
        verifier(c.modele.progres < 0.01 && !c.panneau.estDeplie, "fermeture en cours (cible 0)")
        c.panneau.survol(true); attendre(0.05)
        verifier(c.modele.progres > 0.99, "souris revenue pendant la fermeture : repart vers l'ouvert tout de suite (pas d'intention à attendre)")
        // clic : ferme / ouvre tout de suite
        c.modele.surClicIlot(); attendre(0.1)
        verifier(c.modele.progres < 0.01, "clic sur l'îlot ouvert : il se referme tout de suite")
        c.modele.surClicIlot(); attendre(0.1)
        verifier(c.modele.progres > 0.99, "clic sur l'îlot fermé : il s'ouvre tout de suite, sans attendre l'intention (0,28 s)")
        c.modele.surClicIlot(); attendre(1.4)
        verifier(c.modele.progres < 0.01 && c.panneau.cadre.map { $0.width == repos?.width } ?? false, "second clic : refermé, la fenêtre reprend sa taille de repos")

        // dictée simulée (seulement sur la source de test)
        attendre(0.3)
        if let courant = c.modele.morceau, courant.app == appVoulue, courant.joue {
            var ruban = false
            c.rubanDictee = { ruban }
            var reserve: CGFloat = 0
            c.reserveRuban = { reserve = $0 }
            c.dicteeChange(enCours: true)
            attendre(1.2) { c.modele.morceau?.joue != false }
            verifier(c.modele.morceau?.joue == false, "dictée : la lecture est mise en pause")
            verifier(c.affichage == .aucun && !c.panneau.estVisible && !c.miniature.estVisible, "dictée sans texte encore (pas de ruban) : rien de la lecture à l'écran, l'îlot est effacé")
            ruban = true; c.occupationChangee(); attendre(0.6)
            verifier(c.affichage == .miniature && c.miniature.estVisible && !c.panneau.estVisible, "ruban de texte sorti : l'îlot reste effacé, la mini-miniature s'affiche")
            verifier(reserve > 0, "le texte du ruban laisse la place à la miniature (\(Int(reserve)) pt)")
            if let ecran = NSScreen.screens.first, let cadre = c.miniature.cadre {
                let (g, centre) = GeometrieEncoche.mesurer(ecran)
                let finRuban = centre + (g.largeur + 2 * GeometrieEncoche.aile) / 2 - GeometrieEncoche.retraitRuban
                let dansLeRuban = cadre.maxX <= finRuban && cadre.minX >= centre + g.largeur / 2 && cadre.maxY <= ecran.frame.maxY - g.hauteur + 0.5 && cadre.minY >= ecran.frame.maxY - g.hauteur - GeometrieEncoche.hauteurRuban - 0.5
                verifier(dansLeRuban, "la miniature est entièrement dans le ruban de la dictée (\(Int(cadre.minX - centre)) … \(Int(cadre.maxX - centre)) pt du centre ; ruban jusqu'à \(Int(finRuban - centre)))")
            }
            // un clic sur la miniature reprend tout de suite la lecture ; à la fin de la dictée, rien de plus
            c.modele.surReprise()
            attendre(1.2) { c.modele.morceau?.joue != true }
            verifier(c.modele.morceau?.joue == true, "clic sur la miniature : la lecture reprend tout de suite")
            attendre(0.6)
            verifier(!c.miniature.estVisible, "la miniature s'efface (fondu) une fois la lecture reprise")
            c.dicteeChange(enCours: false)
            attendre(0.6); ruban = false; c.occupationChangee(); attendre(0.4)
            verifier(c.modele.morceau?.joue == true, "fin de dictée après la reprise par clic : aucune commande en plus, la lecture continue")
            // deuxième dictée, sans clic : la reprise automatique à la fin
            c.dicteeChange(enCours: true)
            attendre(1.2) { c.modele.morceau?.joue != false }
            ruban = true; c.occupationChangee(); attendre(0.5)
            verifier(c.modele.morceau?.joue == false && c.miniature.estVisible, "seconde dictée : pause et miniature")
            c.dicteeChange(enCours: false)
            attendre(1.2) { c.modele.morceau?.joue != true }
            verifier(c.modele.morceau?.joue == true, "fin de dictée : la lecture reprend (c'est nous qui l'avions mise en pause)")
            ruban = false; c.occupationChangee(); attendre(0.9)
            verifier(c.affichage == .ilot && !c.miniature.estVisible, "fin de dictée : l'îlot revient, la miniature a disparu")
            // appui trop court : rien ne bouge
            c.dicteeChange(enCours: true); attendre(0.05); c.dicteeChange(enCours: false); attendre(0.5)
            verifier(c.modele.morceau?.joue == true && c.affichage == .ilot, "appui trop court : ni pause ni changement")
            // réunion : pas de pause automatique, pas d'affichage
            c.occupation = { OccupationEncoche(reunion: true) }
            c.dicteeChange(enCours: true); attendre(0.5)
            verifier(c.modele.morceau?.joue == true && c.affichage == .aucun, "pendant une réunion : pas de pause, rien à l'écran")
            c.dicteeChange(enCours: false); c.occupation = { OccupationEncoche() }; c.occupationChangee(); attendre(0.6)
            verifier(c.affichage == .ilot, "réunion finie : l'îlot revient")
            // priorités : le filet de sécurité efface la lecture
            c.occupation = { OccupationEncoche(filet: true) }; c.occupationChangee(); attendre(0.5)
            verifier(c.affichage == .aucun, "filet de sécurité ouvert : la lecture s'efface")
            c.occupation = { OccupationEncoche() }; c.occupationChangee(); attendre(0.6)
            verifier(c.affichage == .ilot, "filet refermé : la lecture revient")
        } else {
            let courant = c.modele.morceau
            print("  simulation de dictée ignorée : l'app est « \(courant?.app ?? "-") » (joue : \(courant?.joue ?? false)), il faut « \(appVoulue) » en lecture (aucune commande envoyée)")
        }
        c.arreter()
        attendre(0.5)
        print(echecs == 0 ? "essai terminé : tout est vert" : "essai terminé : \(echecs) échec(s)")
        return echecs == 0 ? 0 : 1
    }
}

/// `Verbe --miniature-essai [identifiant]` : essai du téléchargement et du cache de la miniature YouTube avec une vidéo publique (par défaut
/// dQw4w9WgXcQ). Réseau seulement : ni micro, ni clavier, ni Accessibilité, ni son. La lecture de l'adresse de l'onglet (Accessibilité) n'est
/// PAS essayée ici : elle ne se teste que dans l'app installée, avec Chrome ouvert sur une vidéo.
enum MiniatureEssai {
    @MainActor
    static func executer(arguments: [String]) -> Int32 {
        _ = NSApplication.shared
        let id = arguments.firstIndex(of: "--miniature-essai").flatMap { $0 + 1 < arguments.count && !arguments[$0 + 1].hasPrefix("--") ? arguments[$0 + 1] : nil } ?? "dQw4w9WgXcQ"
        var echecs = 0
        func verifier(_ ok: Bool, _ nom: String) { print(ok ? "  ok   \(nom)" : "  ÉCHEC \(nom)"); if !ok { echecs += 1 } }
        guard MiniatureYouTube.estIdentifiant(id) else { print("identifiant invalide"); return 2 }
        let fichier = MiniatureLecture.fichier(pour: id)
        let existait = FileManager.default.fileExists(atPath: fichier.path)
        let sauvegarde = existait ? try? Data(contentsOf: fichier) : nil
        try? FileManager.default.removeItem(at: fichier)

        var resultat1: (image: NSImage, origine: MiniatureLecture.Origine)?
        var resultat2: (image: NSImage, origine: MiniatureLecture.Origine)?
        var duree1 = 0.0, duree2 = 0.0
        var fini = false
        Task {
            let t0 = Date()
            resultat1 = await MiniatureLecture.charger(identifiant: id)
            duree1 = Date().timeIntervalSince(t0)
            let t1 = Date()
            resultat2 = await MiniatureLecture.charger(identifiant: id)
            duree2 = Date().timeIntervalSince(t1)
            fini = true
        }
        let fin = Date().addingTimeInterval(20)
        while !fini, Date() < fin { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05)) }
        verifier(fini, "terminé avant le délai de 20 s")
        if let r = resultat1 {
            print("  1er appel : \(r.origine.rawValue), \(Int(r.image.size.width)) × \(Int(r.image.size.height)) pt en \(String(format: "%.2f", duree1)) s")
            verifier(r.origine == .reseau, "premier appel : téléchargé")
            verifier(r.image.size.width >= 300 && r.image.size.height >= 150, "image 320 × 180 reçue")
        } else { verifier(false, "premier appel : image reçue (réseau ?)") }
        let attributs = try? FileManager.default.attributesOfItem(atPath: fichier.path)
        let taille = (attributs?[.size] as? Int) ?? 0
        print("  fichier en cache : \(fichier.path) (\(taille) octets)")
        verifier(taille > 1000 && taille <= MiniatureLecture.tailleMax, "fichier en cache de taille raisonnable (< \(MiniatureLecture.tailleMax / 1000) Ko)")
        verifier(((attributs?[.posixPermissions] as? Int) ?? 0) == 0o600, "fichier en cache en 0600")
        if let r = resultat2 {
            print("  2e appel : \(r.origine.rawValue) en \(String(format: "%.3f", duree2)) s")
            verifier(r.origine == .cache && duree2 < 0.2, "second appel : servi par le cache disque, sans réseau")
        } else { verifier(false, "second appel : image reçue") }
        verifier(MiniatureLecture.enCache("../../etc/passwd") == nil && MiniatureLecture.enCache("court") == nil, "identifiant piégé ou invalide : jamais lu ni écrit")
        // élagage : 45 faux fichiers, il n'en reste que 40
        let faux = (0..<45).map { MiniatureLecture.dossier.appendingPathComponent("zz-essai-\($0).jpg") }
        for (i, f) in faux.enumerated() {
            try? Data(repeating: 1, count: 10).write(to: f)
            try? FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(Double(i - 100))], ofItemAtPath: f.path)
        }
        MiniatureLecture.elaguer()
        let restants = (try? FileManager.default.contentsOfDirectory(atPath: MiniatureLecture.dossier.path).filter { $0.hasSuffix(".jpg") }.count) ?? -1
        verifier(restants <= MiniatureLecture.nombreMax, "élagage : \(restants) miniature(s) gardée(s) au plus \(MiniatureLecture.nombreMax)")
        for f in faux { try? FileManager.default.removeItem(at: f) }
        // on remet le cache comme on l'a trouvé
        try? FileManager.default.removeItem(at: fichier)
        if let sauvegarde { try? sauvegarde.write(to: fichier) }
        print(echecs == 0 ? "essai terminé : tout est vert" : "essai terminé : \(echecs) échec(s)")
        return echecs == 0 ? 0 : 1
    }
}

/// `Verbe --lecture-mesure [secondes]` : processeur de Verbe pendant que l'îlot est affiché au repos (égaliseur animé si ça joue). Aucune
/// commande n'est envoyée. L'îlot est VISIBLE pendant la mesure (une animation dans une fenêtre invisible ne coûterait rien et ne prouverait rien).
/// Le temps de processeur est celui du processus Verbe (`getrusage`) ; le rendu de l'animation lui-même se fait dans le serveur d'affichage.
enum LectureMesure {
    @MainActor
    static func executer(secondes: Double) -> Int32 {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        func attendre(_ s: Double, tant: () -> Bool = { true }) {
            let fin = Date().addingTimeInterval(s)
            while Date() < fin, tant() { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02)) }
        }
        func cpu() -> Double {
            var u = rusage(); getrusage(RUSAGE_SELF, &u)
            return Double(u.ru_utime.tv_sec + u.ru_stime.tv_sec) + Double(u.ru_utime.tv_usec + u.ru_stime.tv_usec) / 1e6
        }
        let c = LectureControleur()
        c.essaiInvisible = false
        c.demarrer()
        attendre(8) { c.modele.morceau == nil }
        guard let m = c.modele.morceau else { print("rien ne joue : mesure impossible"); c.arreter(); return 1 }
        attendre(3)   // l'îlot est apparu, tout est posé
        print("source : \(m.app ?? "-") joue=\(c.modele.joue) ; îlot visible : \(c.panneau.estVisible)")
        let t0 = cpu(), h0 = Date()
        attendre(secondes)
        let dt = Date().timeIntervalSince(h0), dc = cpu() - t0
        print(String(format: "processeur de Verbe au repos (égaliseur animé) : %.3f s sur %.1f s = %.2f %%", dc, dt, 100 * dc / dt))
        c.arreter()
        return 0
    }
}
