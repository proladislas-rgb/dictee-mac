import AppKit
import SwiftUI
import DicteeCore

/// Rendu hors écran des vues AppKit/SwiftUI (champs de texte compris) en PNG : une vue d'hébergement qui n'est dans
/// aucune fenêtre visible. Aucune fenêtre n'apparaît, aucun focus n'est pris ; ne touche ni au micro ni au clavier.
@MainActor
enum RenduVues {
    static func png<V: View>(_ vue: V, taille: CGSize, echelle: CGFloat = 2) -> Data? {
        let hote = NSHostingView(rootView: vue)
        hote.appearance = NSAppearance(named: .darkAqua)
        hote.frame = NSRect(origin: .zero, size: taille)
        // une fenêtre jamais affichée donne à la vue sa taille et son apparence
        let fenetre = NSWindow(contentRect: hote.frame, styleMask: [.borderless], backing: .buffered, defer: true)
        fenetre.appearance = NSAppearance(named: .darkAqua)
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

/// `Dictee --rendu-fenetre dossier` : la fenêtre principale (3 onglets et états) en PNG, sans fenêtre.
enum RenduFenetre {
    struct Cadre<V: View>: View {
        var taille: CGSize
        /// La barre du haut de la vraie fenêtre (onglets), quand le rendu doit la montrer.
        var barre: AnyView? = nil
        @ViewBuilder var contenu: V
        var body: some View {
            ZStack(alignment: .topLeading) {
                Color(hex: 0x0B0B0B)
                VStack(spacing: 0) {
                    if let barre { barre.frame(height: 60).frame(maxWidth: .infinity, alignment: .leading) }
                    contenu
                }
                    .frame(width: taille.width - 80, height: taille.height - 80)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                    .overlay(alignment: .topLeading) {
                        HStack(spacing: 8) { ForEach(0..<3, id: \.self) { _ in Circle().fill(Color(white: 0.4)).frame(width: 12, height: 12) } }.padding(20)
                    }
                    .padding(40)
            }
            .frame(width: taille.width, height: taille.height)
        }
    }

    @MainActor
    static func executer(dossier: String) -> Int32 {
        _ = NSApplication.shared
        Polices.enregistrer()
        let url = URL(fileURLWithPath: (dossier as NSString).expandingTildeInPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var ok = true
        // 1180 × 760 = fenêtre de 1100 × 680 (comme la maquette) sur un fond de bureau
        let taille = CGSize(width: 1180, height: 760)

        let storeReunions = ReunionStore(dossier: FileManager.default.temporaryDirectory.appendingPathComponent("dictee-rendu-reunions"), lire: false)
        let controleur = ReunionController(store: storeReunions)
        let reunions = ReunionsModele(store: storeReunions)
        func fenetre(_ nom: String, onglet: Onglet, store: HistoriqueStore, mots: MotsModele, reglages: ReglagesModele? = nil, requete: String = "",
                     deplier: Bool = false, taille: CGSize = taille, suppression: Bool = false) {
            let nav = NavigationFenetre(); nav.onglet = onglet
            let d = ModeleDictees(store: store)
            d.requete = requete
            d.selection = d.affichees.first?.id
            d.nomDestination = { "Mail" }
            if deplier, let e = d.affichees.first(where: { $0.texte.hasPrefix("Bonjour") }) {
                d.developpee = e.id; d.selection = e.id
                if suppression { d.suppressionEnAttente = e.id }
            }
            let vue = Cadre(taille: taille) {
                FenetreVue(nav: nav, dictees: d, store: store, mots: mots, reglages: reglages ?? ReglagesModele(reel: false), reunions: reunions, controleur: controleur, journee: JourneeModele(dictees: d, reunions: reunions), curseurFactice: true)
            }
            ok = RenduVues.ecrire(RenduVues.png(vue, taille: taille), url.appendingPathComponent("\(nom).png")) && ok
        }
        let exemple = RenduVues.historiqueExemple()
        func motsExemple(avecMessage: Bool = false, propositions: Bool = true) -> MotsModele {
            var p = PropositionsMots(); if propositions { _ = p.proposer("Brume", motsConnus: []) }
            let m = MotsModele(persistant: false, mots: ["Anaïs Morel", "Brume & Fils", "Villeurbanne", "Marchetti"],
                               raccourcis: [RaccourciVocal(expression: "ma signature", texte: "Camille Roussel"),
                                            RaccourciVocal(expression: "mon mail", texte: "camille@exemple.fr"),
                                            RaccourciVocal(expression: "mes dispos", texte: "Mardi ou jeudi après-midi")], propositions: p,
                               expressions: [ExpressionPerso(texte: "t\u{2019}inquiète", dictees: 14), ExpressionPerso(texte: "on se capte", dictees: 9),
                                             ExpressionPerso(texte: "c\u{2019}est lourd", dictees: 6), ExpressionPerso(texte: "du coup", manuelle: true)],
                               apprisCetteSemaine: 3)
            if avecMessage { m.ajouterMot("villeurbanne") }
            return m
        }
        let petite = CGSize(width: 700, height: 600)
        fenetre("fenetre-1-dictees", onglet: .dictees, store: exemple, mots: motsExemple(), deplier: true)
        fenetre("fenetre-2-mots", onglet: .mots, store: exemple, mots: motsExemple())
        fenetre("fenetre-3-reglages", onglet: .reglages, store: exemple, mots: motsExemple())
        fenetre("fenetre-4-mot-deja-enregistre", onglet: .mots, store: exemple, mots: motsExemple(avecMessage: true, propositions: false))
        fenetre("fenetre-5-historique-vide", onglet: .dictees, store: RenduVues.historiqueExemple(vide: true), mots: motsExemple())
        fenetre("fenetre-6-aucun-resultat", onglet: .dictees, store: exemple, mots: motsExemple(), requete: "zzz")
        let confirmation = ReglagesModele(reel: false); confirmation.confirmerEffacement = true
        fenetre("fenetre-7-reglages-confirmation", onglet: .reglages, store: exemple, mots: motsExemple(), reglages: confirmation)
        fenetre("fenetre-8-reglages-globe", onglet: .reglages, store: exemple, mots: motsExemple(), reglages: ReglagesModele(reel: false, globe: 2))
        fenetre("fenetre-9-dictees-liste", onglet: .dictees, store: exemple, mots: motsExemple())
        fenetre("fenetre-10-suppression", onglet: .dictees, store: exemple, mots: motsExemple(), deplier: true, suppression: true)
        fenetre("fenetre-11-petite-dictees", onglet: .dictees, store: exemple, mots: motsExemple(), deplier: true, taille: petite)
        fenetre("fenetre-12-petite-mots", onglet: .mots, store: exemple, mots: motsExemple(), taille: petite)
        fenetre("fenetre-13-petite-reglages", onglet: .reglages, store: exemple, mots: motsExemple(), taille: petite)
        // toute la hauteur des Réglages : sans encoche, l'interrupteur de l'icône allumé et grisé ; en bas, « Ouvrir le journal » et
        // « Quitter Verbe » (l'icône et son menu sont éteints par défaut) ; en deux colonnes et en une
        let sansEncoche = ReglagesModele(reel: false); sansEncoche.iconeToujours = true
        fenetre("fenetre-14-reglages-sans-encoche-toute-la-hauteur", onglet: .reglages, store: exemple, mots: motsExemple(), reglages: sansEncoche, taille: CGSize(width: 1180, height: 2000))
        fenetre("fenetre-15-petite-reglages-toute-la-hauteur", onglet: .reglages, store: exemple, mots: motsExemple(), taille: CGSize(width: 700, height: 3900))
        // l'usage de Groq (12/11) : la limite atteinte, le Mac prend le relais ; le français en téléchargement pour la dictée sur le Mac
        let enPause = ReglagesModele(reel: false)
        var k = CompteurGroq()
        let t = Date()
        k.noterEnvoi(secondesAudio: 480 * 60, modele: ModeleWhisper.precis.identifiant, a: t.addingTimeInterval(-6 * 3600))
        for m in [ModeleWhisper.precis, .rapide] {
            k.noterReponse(modele: m.identifiant, statut: 429, entete: { $0 == "retry-after" ? "2400" : nil }, messageErreur: "(ASD)", a: t)
        }
        enPause.exempleGroq(EtatGroq.calculer(k, modele: ModeleWhisper.precis.identifiant, secours: ModeleWhisper.rapide.identifiant, a: t))
        fenetre("fenetre-16-reglages-groq-en-pause", onglet: .reglages, store: exemple, mots: motsExemple(), reglages: enPause, taille: CGSize(width: 1180, height: 2000))
        return ok ? 0 : 1
    }
}

/// `Dictee --rendu-premier-lancement dossier` : les étapes et leurs états en PNG, sans fenêtre.
enum RenduPremierLancement {
    @MainActor
    static func executer(dossier: String) -> Int32 {
        _ = NSApplication.shared
        Polices.enregistrer()
        let url = URL(fileURLWithPath: (dossier as NSString).expandingTildeInPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var ok = true
        let taille = CGSize(width: 700, height: 560)

        func etape(_ nom: String, _ e: PriseEnMainModele.Etape, micro: Bool = false, refuse: Bool = false, access: Bool = false, surv: Bool = false,
                   cle: CleGroq.Etat = .absente, essai: String = "", reussie: Bool = false, echec: String? = nil, globe: Int? = 0, doubleAppuiVu: Bool = false) {
            let m = PriseEnMainModele(reel: false, micro: micro, accessibilite: access, surveillance: surv, cle: cle, globe: globe)
            m.etape = e
            m.essai = essai
            m.setEtatPourRendu(refuse: refuse, reussie: reussie, echec: echec, doubleAppuiVu: doubleAppuiVu)
            let app = ApparitionPanneau(); app.visible = true
            let vue = RenduVues.Bureau(taille: taille, camera: 180) {
                PriseEnMainVue(m: m, apparition: app, curseurFactice: true).padding(.top, PriseEnMain.ecartHaut - 6)
            }
            ok = RenduVues.ecrire(RenduVues.png(vue, taille: taille), url.appendingPathComponent("\(nom).png")) && ok
        }
        etape("premier-1-geste", .geste)
        etape("premier-2-acces-rien", .acces)
        etape("premier-2-acces-partiel", .acces, micro: true, access: true)
        etape("premier-2-micro-refuse", .acces, refuse: true, access: true, surv: true, cle: .fichier)
        etape("premier-2-acces-complets", .acces, micro: true, access: true, surv: true, cle: .trousseau)
        etape("premier-3-globe-a-regler", .globe, micro: true, access: true, surv: true, cle: .trousseau, globe: 2)
        etape("premier-3-globe-essai", .globe, micro: true, access: true, surv: true, cle: .trousseau, globe: 0)
        etape("premier-3-globe-reconnu", .globe, micro: true, access: true, surv: true, cle: .trousseau, globe: 0, doubleAppuiVu: true)
        etape("premier-4-attente", .premiere, micro: true, access: true, surv: true, cle: .trousseau)
        etape("premier-4-reussie", .premiere, micro: true, access: true, surv: true, cle: .trousseau, essai: "On se voit mercredi pour parler du devis.", reussie: true)
        etape("premier-4-echec", .premiere, micro: true, access: true, surv: true, cle: .trousseau, echec: "Écriture impossible ici, le texte est copié.")
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
