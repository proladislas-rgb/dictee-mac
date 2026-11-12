import AppKit
import SwiftUI
import DicteeCore

/// Rendu hors écran des vues AppKit/SwiftUI (champs de texte compris) en PNG : une vue d'hébergement qui n'est dans
/// aucune fenêtre visible. Aucune fenêtre n'apparaît, aucun focus n'est pris ; ne touche ni au micro ni au clavier.
@MainActor
enum RenduVues {
    static func png<V: View>(_ vue: V, taille: CGSize, echelle: CGFloat = 2, apparence: NSAppearance.Name = .darkAqua) -> Data? {
        let hote = NSHostingView(rootView: vue)
        hote.appearance = NSAppearance(named: apparence)
        hote.frame = NSRect(origin: .zero, size: taille)
        // une fenêtre jamais affichée donne à la vue sa taille et son apparence
        let fenetre = NSWindow(contentRect: hote.frame, styleMask: [.borderless], backing: .buffered, defer: true)
        fenetre.appearance = NSAppearance(named: apparence)
        fenetre.contentView = hote
        hote.layoutSubtreeIfNeeded()
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(taille.width * echelle), pixelsHigh: Int(taille.height * echelle),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = taille
        hote.cacheDisplay(in: hote.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    /// Historique d'exemple (jamais celui de l'utilisateur), dans un fichier temporaire.
    static func historiqueExemple(vide: Bool = false) -> HistoriqueStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dictee-rendu-\(UUID().uuidString).json")
        let store = HistoriqueStore(url: url)
        if vide { return store }
        let cal = Calendar.current
        func a(_ jours: Int, _ h: Int, _ m: Int) -> Date {
            cal.date(bySettingHour: h, minute: m, second: 0, of: cal.date(byAdding: .day, value: -jours, to: Date())!)!
        }
        let lignes: [(Int, Int, Int, String, String, String, Bool)] = [
            (1, 16, 24, "Notes", "com.apple.Notes", "Le rendez-vous est confirmé pour dix heures.", false),
            (1, 18, 2, "Mail", "com.apple.mail", "Peux-tu m\u{2019}envoyer le récapitulatif avant jeudi ?", true),
            (0, 10, 8, "Notes", "com.apple.Notes", "Penser à envoyer la proposition avant jeudi.", true),
            (0, 11, 30, "Claude", "com.anthropic.claudefordesktop", "Reprends le tableau des factures, ajoute une colonne pour la date de relance et trie par montant.", true),
            (0, 13, 55, "WhatsApp", "net.whatsapp.WhatsApp", "J\u{2019}arrive dans dix minutes, commande-moi un café.", true),
            (0, 14, 12, "Mail", "com.apple.mail", "Bonjour Madame Martin, suite à notre échange de ce matin, je vous transmets la proposition avec les deux options chiffrées. Je reste disponible demain pour en discuter et ajuster le calendrier si besoin.", true),
            (0, 14, 41, "Messages", "com.apple.MobileSMS", "On se voit mercredi pour parler du devis.", true),
        ]
        for (j, h, m, app, id, texte, insere) in lignes {
            store.ajouter(EntreeHistorique(date: a(j, h, m), appId: id, appNom: app, texte: texte, insere: insere, raison: insere ? nil : "champ protégé"))
        }
        return store
    }

    /// Faux bureau : fond, barre des menus, encoche.
    struct Bureau<Contenu: View>: View {
        var taille: CGSize
        var haut: CGFloat = 32
        var camera: CGFloat = 180
        @ViewBuilder var contenu: Contenu
        var body: some View {
            ZStack(alignment: .top) {
                Color(hex: 0x0B0B0B)
                HStack {
                    Text("Notes").bold(); Text("Fichier"); Text("Édition"); Spacer()
                    FormeGuillemets().fill(Palette.texte).frame(width: 14, height: 14 / Guillemets.rapport)
                    Image(systemName: "wifi"); Image(systemName: "battery.75percent"); Text("lun. 9 nov.  14:42")
                }
                .font(.system(size: 13)).foregroundStyle(Palette.texte2)
                .padding(.horizontal, 16).frame(height: haut)
                .frame(maxWidth: .infinity)
                .background(Color(hex: 0x141413))
                UnevenRoundedRectangle(bottomLeadingRadius: 9, bottomTrailingRadius: 9).fill(Color.black).frame(width: camera, height: haut)
                contenu.padding(.top, haut + 6)
            }
            .frame(width: taille.width, height: taille.height, alignment: .top)
        }
    }

    static func ecrire(_ donnees: Data?, _ fichier: URL) -> Bool {
        guard let donnees, (try? donnees.write(to: fichier)) != nil else { print("échec du rendu \(fichier.lastPathComponent)"); return false }
        print("écrit \(fichier.path)")
        return true
    }
}

/// `Dictee --rendu-panneau dossier` : le panneau compact (et ses états) en PNG, sans fenêtre.
enum RenduPanneau {
    @MainActor
    static func executer(dossier: String) -> Int32 {
        _ = NSApplication.shared
        Polices.enregistrer()
        print("Newsreader disponible : \(Polices.newsreaderDisponible)")
        let url = URL(fileURLWithPath: (dossier as NSString).expandingTildeInPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var ok = true

        func panneau(_ nom: String, store: HistoriqueStore, requete: String = "", developper: Bool = false, taille: CGSize = CGSize(width: 720, height: 420)) {
            let m = ModeleDictees(store: store)
            m.requete = requete
            m.selection = m.affichees.first?.id
            if developper { m.developpee = m.affichees.first { $0.texte.hasPrefix("Bonjour") }?.id; m.selection = m.developpee }
            let app = ApparitionPanneau(); app.visible = true
            let vue = RenduVues.Bureau(taille: taille) {
                PanneauVue(m: m, store: store, apparition: app, surOnglet: { _ in }, curseurFactice: true)
            }
            ok = RenduVues.ecrire(RenduVues.png(vue, taille: taille), url.appendingPathComponent("\(nom).png")) && ok
        }
        let plein = RenduVues.historiqueExemple()
        // la ligne choisie par défaut est la plus récente
        func choisir(_ s: HistoriqueStore) -> HistoriqueStore { s }
        panneau("panneau-1-historique", store: plein)
        panneau("panneau-2-texte-complet", store: plein, developper: true)
        panneau("panneau-3-recherche", store: plein, requete: "mail")
        panneau("panneau-4-aucun-resultat", store: plein, requete: "zzz")
        panneau("panneau-5-historique-vide", store: RenduVues.historiqueExemple(vide: true))
        // les mots du bas tiennent entiers (rien n'est rogné par les coins du panneau)
        let mots = NavigationBasse<EmptyView>.largeurMots(Onglet.panneau)
        print("mots du bas du panneau : \(Int(mots)) pt pour \(Int(PanneauVue.taille.width)) pt")
        if mots > PanneauVue.taille.width { print("ÉCHEC : les mots du bas du panneau ne tiennent pas"); ok = false }
        return ok ? 0 : 1
    }
}

/// `Dictee --rendu-premier-lancement dossier` : les cartes d'accueil et leurs états en PNG (clair et sombre), puis une vidéo MP4 de
/// chaque scène animée (60 images par seconde, rendues une à une : la scène est une fonction du temps), sans fenêtre.
/// `--carte N` : seulement la vidéo de la carte N (pour mettre une scène au point).
enum RenduPremierLancement {
    @MainActor
    static func executer(dossier: String) -> Int32 {
        _ = NSApplication.shared
        Polices.enregistrer()
        let url = URL(fileURLWithPath: (dossier as NSString).expandingTildeInPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var ok = true
        // les illustrations du dépôt (le rendu se lance depuis sa racine)
        Illustrations.dossierDesRendus = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/Illustrations", isDirectory: true)
        let taille = CGSize(width: 780, height: 420)

        func modele(_ e: PriseEnMainModele.Etape, micro: Bool = false, refuse: Bool = false, access: Bool = false, surv: Bool = false,
                    cle: CleGroq.Etat = .absente, essai: String = "", reussie: Bool = false, echec: String? = nil, globe: Int? = 0, doubleAppuiVu: Bool = false) -> PriseEnMainModele {
            let m = PriseEnMainModele(reel: false, micro: micro, accessibilite: access, surveillance: surv, cle: cle, globe: globe)
            m.etape = e
            m.essai = essai
            m.setEtatPourRendu(refuse: refuse, reussie: reussie, echec: echec, doubleAppuiVu: doubleAppuiVu)
            return m
        }
        /// La carte sous l'encoche, sur un bout de bureau ; `t` : l'instant de la scène (nil : son image posée).
        func scene(_ m: PriseEnMainModele, sombre: Bool, t: Double? = nil) -> some View {
            let app = ApparitionPanneau(); app.visible = true
            return ZStack(alignment: .top) {
                LinearGradient(colors: sombre ? [Color(hex: 0x1D2733), Color(hex: 0x2E2621)] : [Color(hex: 0xBFD4EC), Color(hex: 0xF2D9C2)], startPoint: .top, endPoint: .bottom)
                UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10).fill(Color.black).frame(width: 180, height: 32)
                PriseEnMainVue(m: m, apparition: app, curseurFactice: true)
                    .environment(\.renduStatique, true)
                    .environment(\.tempsScene, t)
                    .padding(.top, 32 + PriseEnMain.ecartHaut - 30)
            }
            .frame(width: taille.width, height: taille.height)
            .environment(\.colorScheme, sombre ? .dark : .light)
        }
        func etape(_ nom: String, _ m: PriseEnMainModele, sombre: Bool) {
            ok = RenduVues.ecrire(RenduVues.png(scene(m, sombre: sombre), taille: taille, apparence: sombre ? .darkAqua : .aqua),
                                  url.appendingPathComponent("\(nom)-\(sombre ? "sombre" : "clair").png")) && ok
        }
        let tout = (micro: true, access: true, surv: true, cle: CleGroq.Etat.trousseau)
        let seule = CommandLine.arguments.firstIndex(of: "--carte").flatMap { i in i + 1 < CommandLine.arguments.count ? Int(CommandLine.arguments[i + 1]) : nil }
        for sombre in [false, true] where seule == nil {
            etape("accueil-0-bonjour", modele(.bonjour), sombre: sombre)
            etape("accueil-1-micro", modele(.micro, surv: true), sombre: sombre)
            etape("accueil-1-micro-refuse", modele(.micro, refuse: true, surv: true), sombre: sombre)
            etape("accueil-1-micro-pret", modele(.micro, micro: true, surv: true), sombre: sombre)
            etape("accueil-2-ecrire", modele(.ecrire, micro: true, surv: true), sombre: sombre)
            etape("accueil-2-ecrire-pret", modele(.ecrire, micro: true, access: true, surv: true), sombre: sombre)
            etape("accueil-3-touche-a-autoriser", modele(.touche, micro: true, access: true), sombre: sombre)
            etape("accueil-3-touche-globe-a-regler", modele(.touche, micro: true, access: true, surv: true, globe: 2), sombre: sombre)
            etape("accueil-3-touche-prete", modele(.touche, micro: true, access: true, surv: true, doubleAppuiVu: true), sombre: sombre)
            etape("accueil-4-cle", modele(.cle, micro: true, access: true, surv: true), sombre: sombre)
            etape("accueil-4-cle-enregistree", modele(.cle, micro: tout.micro, access: tout.access, surv: tout.surv, cle: tout.cle), sombre: sombre)
            etape("accueil-5-essai", modele(.essai, micro: true, access: true, surv: true, cle: tout.cle), sombre: sombre)
            etape("accueil-5-essai-reussi", modele(.essai, micro: true, access: true, surv: true, cle: tout.cle, essai: "On se voit mercredi pour parler du devis.", reussie: true), sombre: sombre)
            etape("accueil-5-essai-echec", modele(.essai, micro: true, access: true, surv: true, cle: tout.cle, echec: "Écriture impossible ici, le texte est copié."), sombre: sombre)
        }
        // les vidéos : chaque carte en mouvement, une boucle et demie, image par image, en clair
        let images = 60.0
        // dans l'ordre des cartes (1 le micro … 5 l'essai)
        let etats: [PriseEnMainModele] = [modele(.micro, micro: true, surv: true), modele(.ecrire, micro: true, access: true, surv: true),
                                          modele(.touche, micro: true, access: true, surv: true), modele(.cle, micro: true, access: true, surv: true, cle: tout.cle),
                                          modele(.essai, micro: true, access: true, surv: true, cle: tout.cle)]
        for m in etats where seule == nil || seule == m.etape.rawValue {
            let carte = m.etape.rawValue
            let dossierImages = FileManager.default.temporaryDirectory.appendingPathComponent("verbe-video-accueil-\(carte)-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: dossierImages, withIntermediateDirectories: true)
            let duree = max(6, SceneAccueil.boucle(m.etape.illustration) * 1.5)
            let n = Int(duree * images)
            for k in 0..<n {
                let donnees = RenduVues.png(scene(m, sombre: false, t: Double(k) / images), taille: taille, echelle: 1.5, apparence: .aqua)
                guard let donnees, (try? donnees.write(to: dossierImages.appendingPathComponent(String(format: "%04d.png", k)))) != nil else { ok = false; break }
            }
            let sortie = url.appendingPathComponent("accueil-\(carte)-anime.mp4")
            try? FileManager.default.removeItem(at: sortie)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
            p.arguments = ["-loglevel", "error", "-framerate", "60", "-i", dossierImages.appendingPathComponent("%04d.png").path,
                           "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18", "-movflags", "+faststart", sortie.path]
            do { try p.run(); p.waitUntilExit() } catch { print("ffmpeg introuvable : \(error.localizedDescription)"); ok = false }
            if p.terminationStatus == 0 { print("écrit \(sortie.path) (\(n) images)") } else { ok = false }
            try? FileManager.default.removeItem(at: dossierImages)
        }
        return ok ? 0 : 1
    }
}

/// `Dictee --rendu-filet dossier` : le filet de sécurité (texte court, texte long, après « Copier ») en PNG, sans fenêtre.
enum RenduFilet {
    @MainActor
    static func executer(dossier: String) -> Int32 {
        _ = NSApplication.shared
        Polices.enregistrer()
        print("Newsreader disponible : \(Polices.newsreaderDisponible)")
        let url = URL(fileURLWithPath: (dossier as NSString).expandingTildeInPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var ok = true
        let geometrie = GeometrieEncoche()   // caméra fictive 200 × 32 pt, comme la maquette
        let notes = NSWorkspace.shared.icon(forFile: "/System/Applications/Notes.app")

        func rendre(_ nom: String, texte: String, copie: Bool = false, reduire: Bool = false) {
            let m = FiletModele()
            m.geometrie = geometrie; m.texte = texte; m.ouvert = true; m.copie = copie; m.reduire = reduire; m.icone = notes
            let taille = m.tailleFenetre()
            let scene = CGSize(width: 760, height: 250)
            let vue = ZStack(alignment: .top) {
                Color(hex: 0x121211)
                HStack {
                    Text("Notes").bold(); Text("Fichier"); Text("Édition"); Spacer()
                    FormeGuillemets().fill(Palette.texte).frame(width: 14, height: 14 / Guillemets.rapport)
                    Text("lun. 9 nov.  19:41")
                }
                .font(.system(size: 13)).foregroundStyle(Palette.texte2)
                .padding(.horizontal, 16).frame(height: geometrie.hauteur).frame(maxWidth: .infinity)
                .background(Color(hex: 0x161615))
                Text("Aucune note ouverte : le curseur n\u{2019}est dans aucun champ de texte.")
                    .font(.system(size: 13)).foregroundStyle(Palette.texte3)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 60).padding(.top, 190)
                FiletVue(m: m, tailleFenetre: taille)
            }
            .frame(width: scene.width, height: scene.height, alignment: .top)
            print("\(nom) : fenêtre \(Int(taille.width)) × \(Int(taille.height)) pt, texte \(Int(m.hauteurTexte)) pt de haut, défile : \(m.texteDefile)")
            ok = RenduVues.ecrire(RenduVues.png(vue, taille: scene), url.appendingPathComponent("\(nom).png")) && ok
        }
        let court = "Bonjour Madame Martin, je vous confirme le rendez-vous de jeudi à dix heures. À plus tard."
        let long = "Bonjour Madame Martin, suite à notre échange de ce matin, je vous transmets la proposition avec les deux options dont on a parlé. La première couvre l\u{2019}installation seule, la seconde inclut la maintenance pendant deux ans. Dites-moi laquelle vous convient et je prépare le devis pour jeudi, avec les délais de livraison et les conditions de paiement. Je reste disponible demain toute la journée pour en discuter au téléphone, et je peux aussi passer vous voir sur place si vous préférez. À très vite."
        rendre("filet-1-texte-court", texte: "On se voit mercredi.")
        rendre("filet-2-texte-moyen", texte: court)
        rendre("filet-3-texte-long", texte: long)
        rendre("filet-4-apres-copier", texte: court, copie: true)
        rendre("filet-5-reduire-animations", texte: court, reduire: true)
        return ok ? 0 : 1
    }
}
