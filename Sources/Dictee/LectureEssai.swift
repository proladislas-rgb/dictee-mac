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

        // survol : l'îlot se déplie, puis se referme après un petit délai
        c.panneau.survol(true)
        attendre(1.0)
        verifier(c.modele.progres > 0.95 && c.modele.progres < 1.2, "survol : déplié (progression \(String(format: "%.2f", Double(c.modele.progres))))")
        let ouvert = c.panneau.cadre
        verifier((ouvert?.width ?? 0) > (repos?.width ?? 0) && (ouvert?.height ?? 0) > (repos?.height ?? 0), "la fenêtre grandit avec l'îlot")
        print("  fenêtre dépliée : \(ouvert.map { "\(Int($0.width)) × \(Int($0.height))" } ?? "-")")
        if let o = ouvert, let r = repos { verifier(abs(o.midX - r.midX) <= 1 && abs(o.maxY - r.maxY) < 0.5, "centrée sur la caméra, collée en haut de l'écran (le centre ne bouge pas)") }
        c.panneau.survol(false)
        attendre(0.15)
        verifier(c.modele.progres > 0.9, "souris sortie : pas de fermeture immédiate (petit délai)")
        attendre(1.4)
        verifier(c.modele.progres < 0.05, "puis refermé")
        verifier(c.panneau.cadre.map { $0.width == repos?.width } ?? false, "la fenêtre reprend sa taille de repos")
        // interruption : on rouvre en pleine fermeture
        c.panneau.survol(true); attendre(0.15); c.panneau.survol(false); attendre(0.5); c.panneau.survol(true); attendre(1.0)
        verifier(c.modele.progres > 0.95, "ressort interruptible : rouvert en pleine fermeture")
        c.panneau.survol(false); attendre(1.6)

        // dictée simulée (seulement sur la source de test)
        if m.app == appVoulue, m.joue {
            c.dicteeChange(enCours: true)
            attendre(1.2) { c.modele.morceau?.joue != false || c.affichage != .bulle }
            verifier(c.modele.morceau?.joue == false, "dictée : la lecture est mise en pause")
            verifier(c.affichage == .bulle, "dictée : la lecture devient une bulle")
            c.dicteeChange(enCours: false)
            attendre(1.2) { c.modele.morceau?.joue != true }
            verifier(c.modele.morceau?.joue == true, "fin de dictée : la lecture reprend (c'est nous qui l'avions mise en pause)")
            attendre(0.8)
            verifier(c.affichage == .ilot, "fin de dictée : l'îlot revient")
            // appui trop court : rien ne bouge
            c.dicteeChange(enCours: true); attendre(0.05); c.dicteeChange(enCours: false); attendre(0.5)
            verifier(c.modele.morceau?.joue == true && c.affichage == .ilot, "appui trop court : ni pause ni bulle")
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
            print("  simulation de dictée ignorée : l'app qui joue est « \(m.app ?? "-") », pas « \(appVoulue) » (aucune commande envoyée)")
        }
        c.arreter()
        attendre(0.5)
        print(echecs == 0 ? "essai terminé : tout est vert" : "essai terminé : \(echecs) échec(s)")
        return echecs == 0 ? 0 : 1
    }
}
