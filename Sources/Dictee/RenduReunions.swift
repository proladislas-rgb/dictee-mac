import AppKit
import SwiftUI
import DicteeCore

/// `Dictee --rendu-reunion dossier` : l'encoche des réunions (enregistrement, survol, pause, proposition, traitement, note prête),
/// la liste et la note en PNG, sans fenêtre. Réunions d'exemple, jamais celles de l'utilisateur ; ni micro ni son du Mac.
enum RenduReunions {
    /// Les réunions d'exemple de la maquette `reunions-v2.html` (jour de référence : lundi 9 novembre 2026, comme la maquette).
    static func reunionsExemple() -> [Reunion] {
        let cal = Calendar.current
        let reference = cal.date(from: DateComponents(year: 2026, month: 11, day: 9))!
        func a(_ jours: Int, _ h: Int, _ m: Int) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: cal.date(byAdding: .day, value: -jours, to: reference)!)! }
        func seg(_ d: Double, _ l: Locuteur, _ t: String) -> SegmentReunion { SegmentReunion(debut: d, fin: d + 8, locuteur: l, texte: t) }
        /// Une action dont l'échéance est calculée comme dans l'app (depuis le jour de la réunion).
        func act(_ debut: Date, _ qui: String?, _ quoi: String, _ quand: String? = nil, fait: Bool = false) -> ActionReunion {
            ActionReunion(qui: qui, quoi: quoi, quand: quand, fait: fait, echeance: quand.flatMap { Echeance.analyser($0, depuis: debut).date })
        }
        let jGarnier = a(0, 14, 2)
        let segments = [seg(2, .eux, "Bonjour Camille, merci de prendre cet appel. Paul est avec moi, il s\u{2019}occupe de la logistique chez Garnier et Fils."),
                        seg(14, .moi, "Bonjour Nathalie, bonjour Paul. Je propose qu\u{2019}on reprenne l\u{2019}offre point par point."),
                        seg(120, .eux, "Nous avons deux ateliers à équiper, un à Lyon et un à Annecy, et on voudrait que tout soit en place avant janvier."),
                        seg(495, .moi, "L\u{2019}offre complète comprend les machines, l\u{2019}installation et la maintenance pendant deux ans."),
                        seg(560, .eux, "La formation, on la fera nous-mêmes. Prenons l\u{2019}offre complète sans l\u{2019}option."),
                        seg(1300, .eux, "Le prix, c\u{2019}est ce qui m\u{2019}inquiète. J\u{2019}en parle à mon associé jeudi."),
                        seg(1770, .eux, "Peut-être qu\u{2019}on pourra parler d\u{2019}un troisième atelier l\u{2019}an prochain, mais rien n\u{2019}est décidé."),
                        seg(2110, .moi, "Très bien, je note : offre complète, sans la formation.")]
        var garnier = Reunion(
            debut: jGarnier, duree: 2280, titre: "Appel Garnier & Fils, offre et calendrier", participants: ["Moi", "Nathalie", "Paul"],
            dit: ["Deux ateliers, Lyon et Annecy, avant janvier", "Machines, installation, maintenance 2 ans",
                  "Prix sensible, Nathalie en parle à son associé jeudi", "Troisième atelier l\u{2019}an prochain, pas décidé"],
            decisions: ["Offre complète, sans l\u{2019}option formation", "Paiement en deux fois", "Signature visée"],
            actions: [act(jGarnier, "Moi", "Envoyer la proposition chiffrée, deux options", "mercredi soir"),
                      act(jGarnier, "Nathalie", "Valider le budget avec son associé", "jeudi"),
                      act(jGarnier, "Paul", "Donner les volumes de commande", "vendredi"),
                      act(jGarnier, "Moi", "Vérifier la date de livraison avec l\u{2019}usine"),
                      act(jGarnier, "Moi", "Envoyer la fiche technique", fait: true)],
            segments: segments, etat: .prete, sonGarde: true,
            enBref: "Offre complète retenue, budget à valider jeudi, signature visée avant le 20 novembre.")
        func cite(_ point: Int, _ i: Int, _ t: String) -> CitationReunion { CitationReunion(point: point, texte: t, locuteur: segments[i].locuteur, debut: segments[i].debut, fin: segments[i].fin) }
        garnier.citations = [cite(0, 2, "Nous avons deux ateliers à équiper, un à Lyon et un à Annecy"), cite(1, 3, "L\u{2019}offre complète comprend les machines, l\u{2019}installation et la maintenance pendant deux ans."),
                             cite(2, 5, "Le prix, c\u{2019}est ce qui m\u{2019}inquiète. J\u{2019}en parle à mon associé jeudi."), cite(3, 6, "rien n\u{2019}est décidé")]
        garnier.decisionsEcheances = [nil, nil, EcheanceReunion(quand: "avant le vingt novembre", date: "2026-11-20")]

        func note(_ j: Int, _ h: Int, _ m: Int, _ titre: String, _ duree: Double, _ bref: String, _ actions: [(String?, String, String?, Bool)]) -> Reunion {
            let d = a(j, h, m)
            return Reunion(debut: d, duree: duree, titre: titre, actions: actions.map { act(d, $0.0, $0.1, $0.2, fait: $0.3) }, etat: .prete, enBref: bref)
        }
        var sansNote = Reunion(debut: a(1, 17, 40), duree: 1020, etat: .sansNote)
        sansNote.segments = [seg(3, .eux, "On se rappelle demain pour la suite."), seg(9, .moi, "D\u{2019}accord, à demain.")]
        sansNote.avertissements = ["La note n\u{2019}a pas pu être écrite (réseau : code -1009). La transcription est gardée : « Refaire la note » réessaie."]
        return [garnier,
                note(0, 9, 30, "Point de la semaine avec l\u{2019}équipe", 1440, "Trois priorités pour la semaine, le planning des congés de décembre reste à boucler.",
                     [("Moi", "Boucler le planning des congés", "demain", false), ("Paul", "Préparer le point client", "jeudi", false)]),
                sansNote,
                note(3, 11, 0, "Visio Atelier Roche, premier cadrage", 3120, "Périmètre limité à une ligne de production, visite sur site à caler semaine du 16.",
                     [("Moi", "Envoyer le cadrage écrit", "jeudi", false), ("Moi", "Caler la visite sur site", "vendredi", false), ("Moi", "Demander le plan de l\u{2019}atelier", "le dix-huit novembre", false)]),
                note(4, 15, 15, "Rendez-vous banque, prêt pour le matériel", 1860, "Accord de principe sur 40 000 €, dossier complet à rendre avant le 18 novembre.",
                     [("Moi", "Rendre le dossier complet", "avant le dix-huit novembre", false)]),
                note(5, 10, 5, "Appel fournisseur, délais de livraison", 1020, "Livraison confirmée sous six semaines, rien en attente.",
                     [("Moi", "Confirmer la commande", nil, true)])]
    }

    @MainActor
    static func executer(dossier: String) -> Int32 {
        _ = NSApplication.shared
        Polices.enregistrer()
        let url = URL(fileURLWithPath: (dossier as NSString).expandingTildeInPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var ok = true
        let g = GeometrieEncoche()   // caméra fictive 200 × 32 pt, comme les maquettes

        // MARK: encoche
        func encoche(_ nom: String, phase: PhaseReunion, survol: Bool = false, minuterie: String = "12:48", sources: String = "Micro et son de l\u{2019}appel", traitement: String = "Transcription…", prete: String = "Note prête") {
            let m = ReunionEncocheModele()
            m.geometrie = g; m.ouverte = true; m.phase = phase; m.survol = survol; m.minuterie = minuterie; m.sources = sources; m.traitement = traitement; m.libellePrete = prete
            m.traceMoi = [3, 5, 8, 6, 4, 7, 8, 5, 3, 6, 4, 2].map { $0 / 8 }
            m.traceEux = [2, 2, 3, 5, 7, 8, 6, 4, 3, 2, 2, 3].map { $0 / 8 }
            let largeur = g.largeur + 2 * GeometrieEncoche.aile + 2 * (FormeEncoche.congeHaut.width + 4)
            let taille = CGSize(width: ceil(largeur), height: g.hauteur + GeometrieEncoche.hauteurRuban + 8)
            let scene = CGSize(width: 640, height: 130)
            let vue = ZStack(alignment: .top) {
                Color(hex: 0x0F0F0E)
                HStack {
                    Text("Visio").bold(); Text("Fichier"); Text("Édition"); Spacer()
                    FormeGuillemets().fill(Palette.texte).frame(width: 14, height: 14 / Guillemets.rapport)
                    Text("lun. 9 nov.  14:15")
                }
                .font(.system(size: 13)).foregroundStyle(Palette.texte2)
                .padding(.horizontal, 16).frame(height: g.hauteur).frame(maxWidth: .infinity)
                .background(Color(hex: 0x141413))
                ReunionEncocheVue(m: m, tailleFenetre: taille)
            }
            .frame(width: scene.width, height: scene.height, alignment: .top)
            ok = RenduVues.ecrire(RenduVues.png(vue, taille: scene), url.appendingPathComponent("\(nom).png")) && ok
        }
        encoche("encoche-1-enregistrement", phase: .enregistrement(enPause: false))
        encoche("encoche-2-survol", phase: .enregistrement(enPause: false), survol: true)
        encoche("encoche-3-pause", phase: .enregistrement(enPause: true), survol: true)
        encoche("encoche-4-micro-seul", phase: .enregistrement(enPause: false), survol: true, sources: "Micro seul")
        encoche("encoche-5-proposition", phase: .proposition(app: "Zoom"), minuterie: "")
        encoche("encoche-6-traitement", phase: .traitement, minuterie: "38:12", traitement: "Note en préparation, partie 2 sur 4")
        encoche("encoche-7-note-prete", phase: .prete(UUID()), minuterie: "38:12")
        encoche("encoche-8-sans-note", phase: .prete(UUID()), minuterie: "38:12", prete: "Transcription prête")

        // MARK: fenêtre
        let exemples = reunionsExemple()
        let store = ReunionStore(dossier: FileManager.default.temporaryDirectory.appendingPathComponent("dictee-rendu-reunions"), lire: false)
        for r in exemples { store.enregistrer(r) }
        let vide = ReunionStore(dossier: FileManager.default.temporaryDirectory.appendingPathComponent("dictee-rendu-reunions-vide"), lire: false)
        let historique = RenduVues.historiqueExemple()
        let taille = CGSize(width: 1180, height: 760)
        let maquette = CGSize(width: 1190, height: 760)   // la taille de la capture de la maquette, pour comparer au pixel près
        let petite = CGSize(width: 700, height: 600)

        func fenetre(_ nom: String, store: ReunionStore, ouverte: UUID? = nil, deplier: Bool = false, suppression: Bool = false, taille: CGSize = taille, enCours: Bool = false, point: Int? = nil, filtre: FiltreReunions = .toutes) {
            let nav = NavigationFenetre(); nav.onglet = .reunions
            let r = ReunionsModele(store: store)
            r.selection = store.reunions.first?.id
            r.filtre = filtre
            if let ouverte { r.ouvrir(ouverte); r.transcriptionDepliee = deplier; r.suppressionEnAttente = suppression; r.pointOuvert = point }
            let controleur = ReunionController(store: store)
            let d = ModeleDictees(store: historique)
            let mots = MotsModele(persistant: false, mots: [], raccourcis: [], propositions: PropositionsMots())
            let barre = AnyView(HStack(spacing: 0) { BarreOngletsVue(nav: nav, mots: mots).padding(.leading, 68); Spacer(); BarreReglagesVue(nav: nav).padding(.trailing, 20) })
            let vue = RenduFenetre.Cadre(taille: taille, barre: barre) {
                FenetreVue(nav: nav, dictees: d, store: historique, mots: mots,
                           reglages: ReglagesModele(reel: false), reunions: r, controleur: controleur, journee: JourneeModele(dictees: d, reunions: r), curseurFactice: true)
            }
            ok = RenduVues.ecrire(RenduVues.png(vue, taille: taille), url.appendingPathComponent("\(nom).png")) && ok
        }
        let garnier = exemples[0].id, sansNote = exemples.first { $0.etat == .sansNote }!.id
        // le son gardé : un fichier vide suffit au rendu (il n'est jamais lu), pour montrer le bouton « Écouter »
        let sonFactice = store.fichierSon(exemples[0], .eux)
        try? FileManager.default.createDirectory(at: store.dossier, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: sonFactice.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: sonFactice) }
        var sansSon = exemples[0]; sansSon.id = UUID(); sansSon.sonGarde = false
        let storeSansSon = ReunionStore(dossier: FileManager.default.temporaryDirectory.appendingPathComponent("dictee-rendu-reunions-sans-son"), lire: false)
        storeSansSon.enregistrer(sansSon)
        var ancienne = exemples[0]; ancienne.id = UUID(); ancienne.enBref = nil; ancienne.citations = nil; ancienne.decisionsEcheances = nil; ancienne.sonGarde = false
        ancienne.dit = ["Deux ateliers à équiper, un à Lyon et un à Annecy, avant janvier.", "Le prix reste le point sensible : Nathalie en parle à son associé jeudi."]
        ancienne.actions = ancienne.actions.map { var b = $0; b.echeance = nil; return b }
        let storeAncienne = ReunionStore(dossier: FileManager.default.temporaryDirectory.appendingPathComponent("dictee-rendu-reunions-ancienne"), lire: false)
        storeAncienne.enregistrer(ancienne)

        fenetre("reunions-1-liste", store: store, taille: maquette)
        fenetre("reunions-1b-liste-avec-actions", store: store, taille: maquette, filtre: .avecActions)
        fenetre("reunions-2-note", store: store, ouverte: garnier, taille: maquette)
        fenetre("reunions-2b-note-depliee", store: store, ouverte: garnier, taille: maquette, point: 2)
        fenetre("reunions-2c-note-depliee-sans-son", store: storeSansSon, ouverte: sansSon.id, taille: maquette, point: 2)
        fenetre("reunions-2d-note-etroite", store: store, ouverte: garnier, taille: CGSize(width: 760, height: 1260), point: 2)
        fenetre("reunions-2e-ancienne-note", store: storeAncienne, ouverte: ancienne.id, taille: maquette)
        fenetre("reunions-3-transcription", store: store, ouverte: garnier, deplier: true, taille: CGSize(width: 1190, height: 1100))
        fenetre("reunions-4-sans-note", store: store, ouverte: sansNote)
        fenetre("reunions-5-effacer", store: store, ouverte: garnier, suppression: true, taille: maquette)
        fenetre("reunions-6-vide", store: vide)
        fenetre("reunions-7-petite-note", store: store, ouverte: garnier, taille: petite)
        fenetre("reunions-8-petite-liste", store: store, taille: petite)

        // MARK: panneau compact avec l'entrée « Noter la réunion »
        for (nom, enCours) in [("panneau-reunion-1", false), ("panneau-reunion-2-en-cours", true)] {
            let m = ModeleDictees(store: historique)
            m.selection = m.affichees.first?.id
            m.surNoterLaReunion = {}
            m.reunionEnCours = enCours
            let app = ApparitionPanneau(); app.visible = true
            let tailleP = CGSize(width: 720, height: 420)
            let vue = RenduVues.Bureau(taille: tailleP) { PanneauVue(m: m, store: historique, apparition: app, surOnglet: { _ in }, curseurFactice: true) }
            ok = RenduVues.ecrire(RenduVues.png(vue, taille: tailleP), url.appendingPathComponent("\(nom).png")) && ok
        }
        return ok ? 0 : 1
    }
}
