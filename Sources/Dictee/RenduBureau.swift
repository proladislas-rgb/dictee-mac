import AppKit
import SwiftUI
import DicteeCore

/// `Dictee --rendu-fenetre dossier` : chaque écran de la fenêtre principale en PNG, en clair et en sombre, avec des données
/// fictives (jamais celles de l'utilisateur, jamais ses réglages). Aucune fenêtre n'apparaît. Vérifie aussi, sur une vraie fenêtre
/// jamais montrée, qu'un clic sur chaque onglet et sur le soleil arrive bien à la vue (et pas à la barre de titre).
@MainActor
enum RenduBureau {
    /// « Maintenant » des rendus : jeudi 12 novembre 2026, 14:32 (comme la maquette).
    static let maintenant = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 14, minute: 32))!
    static let tailleFenetre = FenetrePrincipale.tailleParDefaut
    /// La scène : la fenêtre sur un bout de bureau (marge de 40 pt).
    static let taille = CGSize(width: tailleFenetre.width + 80, height: tailleFenetre.height + 80)

    /// Tous les modèles d'une fenêtre d'exemple.
    @MainActor
    struct Exemple {
        let nav = NavigationBureau()
        let apparence: ApparenceFenetre
        let store: HistoriqueStore
        let dictees: ModeleDictees
        let mots: MotsModele
        let reglages: ReglagesModele
        let reunionsStore: ReunionStore
        let reunions: ReunionsModele
        let controleur: ReunionController
        let journee: JourneeModele
        let bibliotheque: BibliothequeModele
        let aujourdhui: AujourdhuiModele
        var actions = ActionsBureau(essais: { [.etagere, .minuteur, .rappels, .claude] })

        init(sombre: Bool, historique: [EntreeHistorique]? = nil, reunions listeReunions: [Reunion]? = nil, reglages: ReglagesModele? = nil,
             mots: MotsModele? = nil, rappels: [Rappel]? = nil, etagere: [ElementEtagere]? = nil, rendezVous: [EvenementAgenda]? = nil) {
            apparence = ApparenceFenetre(lire: { sombre ? "sombre" : "clair" }, ecrire: { _ in }, systemeSombre: sombre)
            store = HistoriqueStore(enMemoire: historique ?? RenduBureau.historique())
            dictees = ModeleDictees(store: store)
            dictees.nomDestination = { "Mail" }
            self.mots = mots ?? RenduBureau.mots()
            self.reglages = reglages ?? ReglagesModele(reel: false)
            reunionsStore = ReunionStore(dossier: FileManager.default.temporaryDirectory.appendingPathComponent("verbe-rendu-bureau-\(UUID().uuidString)"), lire: false)
            for r in listeReunions ?? ([RenduReunions.boutique()] + RenduReunions.autres()) { reunionsStore.enregistrer(r) }
            reunions = ReunionsModele(store: reunionsStore)
            reunions.aujourdhui = { RenduBureau.maintenant }
            controleur = ReunionController(store: reunionsStore)
            journee = JourneeModele(dictees: dictees, reunions: reunions, horloge: { RenduBureau.maintenant })
            bibliotheque = RenduBibliotheque.modele(RenduBureau.maintenant)
            let r = rappels ?? [Rappel(texte: "Appeler le garage", echeance: RenduBureau.a(0, 17, 0), cree: RenduBureau.a(0, 9, 0))]
            let e = etagere ?? [ElementEtagere(chemin: "/Users/exemple/Desktop/Devis-Brume.pdf", signet: Data(), ajout: RenduBureau.a(0, 10, 0)),
                                ElementEtagere(chemin: "/Users/exemple/Desktop/Atelier.jpg", signet: Data(), ajout: RenduBureau.a(0, 11, 0)),
                                ElementEtagere(chemin: "/Users/exemple/Desktop/Contrat.docx", signet: Data(), ajout: RenduBureau.a(0, 9, 0))]
            let rdv = rendezVous ?? [EvenementAgenda(id: "rdv", titre: "Point fournisseurs", debut: RenduBureau.a(0, 15, 0), fin: RenduBureau.a(0, 15, 45))]
            aujourdhui = AujourdhuiModele(store: store, reunions: reunionsStore,
                                          sources: SourcesAujourdhui(rappels: { r }, etagere: { e }, rendezVous: { rdv }),
                                          horloge: { RenduBureau.maintenant })
            aujourdhui.recalculer()
        }

        var vue: BureauVue {
            BureauVue(nav: nav, apparence: apparence, aujourdhui: aujourdhui, dictees: dictees, store: store, mots: mots, reglages: reglages,
                      reunions: reunions, controleur: controleur, journee: journee, bibliotheque: bibliotheque,
                      etatBibliotheque: BibliothequeFenetreEtat(), actions: actions)
        }
    }

    static func a(_ jours: Int, _ h: Int, _ m: Int) -> Date {
        let cal = Calendar.current
        return cal.date(bySettingHour: h, minute: m, second: 0, of: cal.date(byAdding: .day, value: -jours, to: maintenant)!)!
    }

    /// Un historique fictif : 46 dictées aujourd'hui dans 7 apps (≈ 2 840 mots), un record mardi, une semaine ordinaire avant.
    static func historique() -> [EntreeHistorique] {
        let phrases = ["Bonjour Madame Martin, je vous confirme le rendez-vous de jeudi à dix heures, avec les deux options chiffrées.",
                       "Penser à envoyer la proposition avant jeudi et à relancer le fournisseur pour les boîtes.",
                       "Reprends le tableau des factures, ajoute une colonne pour la date de relance et trie par montant.",
                       "J\u{2019}arrive dans dix minutes, commande-moi un café s\u{2019}il te plaît.",
                       "On se voit mercredi pour parler du devis et du calendrier de livraison.",
                       "Merci pour ton retour, je corrige la page d\u{2019}accueil et je te renvoie la version ce soir."]
        let apps = [("Mail", "com.apple.mail"), ("Notes", "com.apple.Notes"), ("Messages", "com.apple.MobileSMS"), ("Claude", "com.anthropic.claudefordesktop"),
                    ("WhatsApp", "net.whatsapp.WhatsApp"), ("Slack", "com.tinyspeck.slackmacgap"), ("Pages", "com.apple.iWork.Pages")]
        func texte(_ mots: Int, _ graine: Int) -> String {
            var sortie: [Substring] = []
            var k = graine
            while sortie.count < mots { sortie += phrases[k % phrases.count].split(separator: " "); k += 1 }
            return sortie.prefix(mots).joined(separator: " ")
        }
        var l: [EntreeHistorique] = []
        // aujourd'hui : 46 dictées, de 8 h 30 à 14 h 30
        for i in 0..<46 {
            let (nom, id) = apps[i % apps.count]
            let mots = i == 45 ? 2840 - 61 * 45 : 61
            l.append(EntreeHistorique(date: a(0, 8 + (i * 6) / 46, (i * 37) % 60), appId: id, appNom: nom, texte: texte(mots, i), dureeParole: Double(mots) / 2.6))
        }
        // les six jours d'avant (mardi : le record, 3 120 mots)
        for (jour, total) in [(1, 2350), (2, 3120), (3, 1980), (4, 2210), (5, 640), (6, 1720)] {
            for j in 0..<10 {
                let (nom, id) = apps[(j + jour) % apps.count]
                l.append(EntreeHistorique(date: a(jour, 9 + j, 10), appId: id, appNom: nom, texte: texte(total / 10, j + jour), dureeParole: Double(total / 10) / 2.6))
            }
        }
        return l
    }

    static func mots() -> MotsModele {
        var p = PropositionsMots(); _ = p.proposer("Brume", motsConnus: [])
        return MotsModele(persistant: false, mots: ["Anaïs Morel", "Brume & Fils", "Villeurbanne", "Marchetti"],
                          raccourcis: [RaccourciVocal(expression: "ma signature", texte: "Camille Roussel"),
                                       RaccourciVocal(expression: "mon mail", texte: "camille@exemple.fr")], propositions: p,
                          expressions: [ExpressionPerso(texte: "t\u{2019}inquiète", dictees: 14), ExpressionPerso(texte: "du coup", manuelle: true)],
                          apprisCetteSemaine: 3)
    }

    /// La fenêtre dessinée sur un bout de bureau : coins de 16 pt, fil fin, ombre, et les trois boutons à leur place (centre à 26 pt).
    struct Cadre<Contenu: View>: View {
        var sombre: Bool
        var tailleFenetre: CGSize = RenduBureau.tailleFenetre
        @ViewBuilder var contenu: Contenu
        var body: some View {
            ZStack {
                LinearGradient(colors: sombre ? [Color(hex: 0x1D2733), Color(hex: 0x2E2621)] : [Color(hex: 0xC9DAEC), Color(hex: 0xF0D9C4)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                contenu
                    .frame(width: tailleFenetre.width, height: tailleFenetre.height)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(alignment: .topLeading) {
                        HStack(spacing: 8) {
                            ForEach([0xFF5F57, 0xFEBC2E, 0x28C840], id: \.self) { c in Circle().fill(Color(hex: UInt32(c))).frame(width: 14, height: 14) }
                        }
                        .padding(.leading, 19 - 7 + 7).padding(.top, 26 - 7)
                    }
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(sombre ? Color.white.opacity(0.14) : Color.black.opacity(0.12), lineWidth: 0.5))
                    .shadow(color: .black.opacity(sombre ? 0.5 : 0.22), radius: 26, y: 14)
            }
            .environment(\.renduStatique, true)
        }
    }

    /// Une fenêtre faite des modèles d'un autre rendu (Journée, Réunions, Bibliothèque, mises à jour), posée sur le bureau.
    static func fenetre(_ nav: NavigationBureau, sombre: Bool, taille: CGSize, store: HistoriqueStore, dictees: ModeleDictees, mots: MotsModele,
                        reglages: ReglagesModele, reunions: ReunionsModele, controleur: ReunionController, journee: JourneeModele,
                        bibliotheque: BibliothequeModele? = nil, etat: BibliothequeFenetreEtat? = nil) -> some View {
        let apparence = ApparenceFenetre(lire: { sombre ? "sombre" : "clair" }, ecrire: { _ in }, systemeSombre: sombre)
        let aujourdhui = AujourdhuiModele(store: store, reunions: reunions.store, sources: SourcesAujourdhui(), horloge: { maintenant })
        return Cadre(sombre: sombre, tailleFenetre: CGSize(width: taille.width - 80, height: taille.height - 80)) {
            BureauVue(nav: nav, apparence: apparence, aujourdhui: aujourdhui, dictees: dictees, store: store, mots: mots, reglages: reglages,
                      reunions: reunions, controleur: controleur, journee: journee, bibliotheque: bibliotheque ?? BibliothequeModele(enMemoire: []),
                      etatBibliotheque: etat ?? BibliothequeFenetreEtat())
        }
    }

    static func png<V: View>(_ vue: V, taille: CGSize, sombre: Bool, echelle: CGFloat = 2) -> Data? {
        RenduVues.png(vue, taille: taille, echelle: echelle, apparence: sombre ? .darkAqua : .aqua)
    }

    /// Les tailles de fenêtre où Hugues lit l'app (12/11) : chaque onglet doit tenir et se lire à chacune.
    static let taillesHugues: [(CGFloat, CGFloat)] = [(760, 600), (900, 920), (1200, 900)]

    static func executer(dossier: String) -> Int32 {
        _ = NSApplication.shared
        Polices.enregistrer()
        let url = URL(fileURLWithPath: (dossier as NSString).expandingTildeInPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var ok = true

        func ecran(_ nom: String, sombre: Bool, taille: CGSize? = nil, regler: (Exemple) -> Void = { _ in }, exemple: ((Bool) -> Exemple)? = nil) {
            let e = exemple?(sombre) ?? Exemple(sombre: sombre)
            regler(e)
            let fenetre = taille.map { CGSize(width: $0.width - 80, height: $0.height - 80) } ?? tailleFenetre
            let vue = Cadre(sombre: sombre, tailleFenetre: fenetre) { e.vue }
            ok = RenduVues.ecrire(png(vue, taille: taille ?? Self.taille, sombre: sombre), url.appendingPathComponent("\(nom)-\(sombre ? "sombre" : "clair").png")) && ok
        }
        for sombre in [false, true] {
            ecran("bureau-01-aujourdhui", sombre: sombre)
            ecran("bureau-02-decouvrir", sombre: sombre) { $0.nav.aller(.decouvrir) }
            ecran("bureau-03-reunions", sombre: sombre) { e in e.nav.aller(.reunions); e.reunions.ouverte = e.reunionsStore.reunions.first?.id }
            ecran("bureau-04-reglages", sombre: sombre) { $0.nav.aller(.reglages) }
            ecran("bureau-05-dictees", sombre: sombre) { e in
                e.nav.ouvrir(.dictees); e.dictees.reinitialiser()
                if let x = e.dictees.affichees.first { e.dictees.developpee = x.id; e.dictees.selection = x.id }
            }
            ecran("bureau-06-journee", sombre: sombre) { $0.nav.ouvrir(.journee) }
            ecran("bureau-07-bibliotheque", sombre: sombre) { $0.nav.ouvrir(.bibliotheque) }
            ecran("bureau-08-reglages-dictee", sombre: sombre) { $0.nav.ouvrir(.dictee) }
            ecran("bureau-09-reglages-mots", sombre: sombre) { $0.nav.ouvrir(.mots) }
            ecran("bureau-10-reglages-encoche", sombre: sombre) { $0.nav.ouvrir(.lucarne) }
            ecran("bureau-11-reglages-confidentialite", sombre: sombre) { $0.nav.ouvrir(.confidentialite) }
            // les états vides : premier jour, rien au calendrier, aucune note, étagère vide
            ecran("bureau-12-aujourdhui-vide", sombre: sombre, exemple: { Exemple(sombre: $0, historique: [], reunions: [], rappels: [], etagere: [], rendezVous: []) })
            // la plus petite fenêtre permise
            ecran("bureau-13-aujourdhui-petite", sombre: sombre, taille: CGSize(width: FenetrePrincipale.tailleMinimale.width + 80, height: FenetrePrincipale.tailleMinimale.height + 80))
            ecran("bureau-14-reglages-petite", sombre: sombre, taille: CGSize(width: FenetrePrincipale.tailleMinimale.width + 80, height: FenetrePrincipale.tailleMinimale.height + 80)) { $0.nav.aller(.reglages) }
            // les états des pages reprises (ceux de l'ancien --rendu-fenetre)
            ecran("bureau-15-dictees-vides", sombre: sombre, regler: { $0.nav.ouvrir(.dictees) }, exemple: { Exemple(sombre: $0, historique: []) })
            ecran("bureau-16-dictees-aucun-resultat", sombre: sombre) { e in e.nav.ouvrir(.dictees); e.dictees.requete = "zzz" }
            ecran("bureau-17-dictees-suppression", sombre: sombre) { e in
                e.nav.ouvrir(.dictees); e.dictees.reinitialiser()
                if let x = e.dictees.affichees.first { e.dictees.developpee = x.id; e.dictees.selection = x.id; e.dictees.suppressionEnAttente = x.id }
            }
            ecran("bureau-18-mot-deja-enregistre", sombre: sombre) { e in e.nav.ouvrir(.mots); e.mots.ajouterMot("villeurbanne") }
            ecran("bureau-19-reglages-mises-a-jour", sombre: sombre, taille: CGSize(width: taille.width, height: 1100)) { $0.nav.aller(.reglages) }
            // les tailles de Hugues (12/11 : « l'app est inutilisable » à 900 × 920) : les quatre onglets à 760 × 600, 900 × 920, 1200 × 900
            for (l, h) in RenduBureau.taillesHugues {
                let t = CGSize(width: l + 80, height: h + 80), suffixe = "\(Int(l))x\(Int(h))"
                ecran("bureau-20-aujourdhui-\(suffixe)", sombre: sombre, taille: t)
                ecran("bureau-21-decouvrir-\(suffixe)", sombre: sombre, taille: t) { $0.nav.aller(.decouvrir) }
                ecran("bureau-22-reunions-\(suffixe)", sombre: sombre, taille: t) { e in e.nav.aller(.reunions); e.reunions.ouverte = e.reunionsStore.reunions.first?.id }
                ecran("bureau-23-reglages-\(suffixe)", sombre: sombre, taille: t) { $0.nav.aller(.reglages) }
            }
        }
        ok = verifierLesClics() && ok
        return ok ? 0 : 1
    }

    /// Une vraie fenêtre, habillée comme dans l'app et jamais montrée : chaque onglet et le soleil doivent recevoir le clic (le test
    /// de la vue sous le point, comme le fait AppKit pour un clic), pas la barre de titre ni la barre d'outils.
    static func verifierLesClics() -> Bool {
        let e = Exemple(sombre: false)
        let f = NSWindow(contentRect: NSRect(origin: CGPoint(x: -5000, y: -5000), size: tailleFenetre),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: true)
        FenetrePrincipale.habiller(f)
        let hote = NSHostingView(rootView: e.vue.environment(\.renduStatique, true))
        f.contentView = hote
        guard let cadre = hote.superview else { return false }
        cadre.layoutSubtreeIfNeeded()
        let bouton = f.standardWindowButton(.closeButton).map { $0.convert($0.bounds, to: nil) } ?? .zero
        let centreFeux = tailleFenetre.height - bouton.midY
        print("boutons de la fenêtre : centre à \(centreFeux) pt du haut (barre d'onglets : \(BarreBureau.centre))")
        var ok = abs(centreFeux - BarreBureau.centre) < 1.5
        if !ok { print("ÉCHEC : la barre d'onglets n'est pas à la hauteur des boutons de la fenêtre") }
        // les points : le milieu de chaque onglet (mesuré avec la même police) et le soleil
        let polices = PageBureau.allCases.map { p in (p.rawValue as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13.5, weight: .semibold)]).width + 34 }
        let total = polices.reduce(0, +) + 6
        var x = tailleFenetre.width / 2 - total / 2 + 3
        var points: [(String, CGPoint)] = []
        for (p, l) in zip(PageBureau.allCases, polices) { points.append((p.rawValue, CGPoint(x: x + l / 2, y: BarreBureau.centre))); x += l }
        points.append(("soleil", CGPoint(x: tailleFenetre.width - 14 - BarreBureau.hauteur / 2, y: BarreBureau.centre)))
        for (nom, p) in points {
            let vue = cadre.hitTest(NSPoint(x: p.x, y: tailleFenetre.height - p.y))
            let dansLaVue = vue.map { $0 === hote || $0.isDescendant(of: hote) } ?? false
            print("clic sur « \(nom) » (\(Int(p.x)), \(Int(p.y))) : \(vue.map { String(describing: type(of: $0)) } ?? "rien")\(dansLaVue ? "" : " — ÉCHEC")")
            ok = ok && dansLaVue
        }
        return ok
    }
}
