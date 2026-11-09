import AppKit
import SwiftUI
import DicteeCore

/// `Dictee --rendu-reunion dossier` : l'encoche des réunions (enregistrement, survol, pause, proposition, traitement, note prête),
/// la liste et la note en PNG, sans fenêtre. Réunions d'exemple, jamais celles de l'utilisateur ; ni micro ni son du Mac.
enum RenduReunions {
    static func reunionsExemple() -> [Reunion] {
        let cal = Calendar.current
        func a(_ jours: Int, _ h: Int, _ m: Int) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: cal.date(byAdding: .day, value: -jours, to: Date())!)! }
        func seg(_ d: Double, _ l: Locuteur, _ t: String) -> SegmentReunion { SegmentReunion(debut: d, fin: d + 8, locuteur: l, texte: t) }
        let garnier = Reunion(
            debut: a(0, 14, 2), duree: 2280, titre: "Appel Garnier & Fils, offre et calendrier", participants: ["Moi", "Nathalie", "Paul"],
            dit: ["Deux ateliers à équiper, un à Lyon et un à Annecy, avant janvier.",
                  "L\u{2019}offre complète comprend les machines, l\u{2019}installation et deux ans de maintenance.",
                  "Le prix reste le point sensible : Nathalie en parle à son associé jeudi.",
                  "Un troisième atelier l\u{2019}an prochain, rien n\u{2019}est décidé."],
            decisions: ["Offre complète retenue, sans l\u{2019}option formation.", "Paiement en deux fois.", "Signature visée avant le 20 novembre."],
            actions: [ActionReunion(qui: "Moi", quoi: "envoyer la proposition chiffrée, deux options", quand: "mercredi soir"),
                      ActionReunion(qui: "Nathalie", quoi: "valider le budget avec son associé", quand: "jeudi"),
                      ActionReunion(qui: "Paul", quoi: "donner les volumes de commande", quand: "vendredi"),
                      ActionReunion(qui: "Moi", quoi: "vérifier la date de livraison avec l\u{2019}usine"),
                      ActionReunion(qui: "Moi", quoi: "envoyer la fiche technique", fait: true)],
            segments: [seg(2, .eux, "Bonjour Camille, merci de prendre cet appel. Paul est avec moi, il s\u{2019}occupe de la logistique chez Garnier et Fils."),
                       seg(14, .moi, "Bonjour Nathalie, bonjour Paul. Je propose qu\u{2019}on reprenne l\u{2019}offre point par point."),
                       seg(31, .eux, "La formation, on la fera nous-mêmes. Prenons l\u{2019}offre complète sans l\u{2019}option."),
                       seg(44, .moi, "Très bien, je note : offre complète, sans la formation.")],
            etat: .prete)
        func simple(_ j: Int, _ h: Int, _ m: Int, _ t: String, _ d: Double) -> Reunion { Reunion(debut: a(j, h, m), duree: d, titre: t, etat: .prete) }
        var sansNote = simple(1, 17, 40, "", 1020)
        sansNote.etat = .sansNote
        sansNote.segments = [seg(3, .eux, "On se rappelle demain pour la suite."), seg(9, .moi, "D\u{2019}accord, à demain.")]
        sansNote.avertissements = ["La note n\u{2019}a pas pu être écrite (réseau : code -1009). La transcription est gardée : « Refaire la note » réessaie."]
        return [garnier, simple(0, 9, 30, "Point de la semaine avec l\u{2019}équipe", 1440), sansNote,
                simple(3, 11, 0, "Visio Atelier Roche, premier cadrage", 3120), simple(4, 15, 15, "Rendez-vous banque, prêt pour le matériel", 1860),
                simple(5, 10, 5, "Appel fournisseur, délais de livraison", 1020), simple(12, 14, 30, "Démonstration au cabinet Lefort", 2700)]
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
        let petite = CGSize(width: 700, height: 600)

        func fenetre(_ nom: String, store: ReunionStore, ouverte: UUID? = nil, deplier: Bool = false, suppression: Bool = false, taille: CGSize = taille, enCours: Bool = false) {
            let nav = NavigationFenetre(); nav.onglet = .reunions
            let r = ReunionsModele(store: store)
            r.selection = store.reunions.first?.id
            if let ouverte { r.ouvrir(ouverte); r.transcriptionDepliee = deplier; r.suppressionEnAttente = suppression }
            let controleur = ReunionController(store: store)
            let d = ModeleDictees(store: historique)
            let vue = RenduFenetre.Cadre(taille: taille) {
                FenetreVue(nav: nav, dictees: d, store: historique, mots: MotsModele(persistant: false, mots: [], raccourcis: [], propositions: PropositionsMots()),
                           reglages: ReglagesModele(reel: false), reunions: r, controleur: controleur, curseurFactice: true)
            }
            ok = RenduVues.ecrire(RenduVues.png(vue, taille: taille), url.appendingPathComponent("\(nom).png")) && ok
        }
        let garnier = exemples[0].id, sansNote = exemples.first { $0.etat == .sansNote }!.id
        fenetre("reunions-1-liste", store: store)
        fenetre("reunions-2-note", store: store, ouverte: garnier)
        fenetre("reunions-3-transcription", store: store, ouverte: garnier, deplier: true)
        fenetre("reunions-4-sans-note", store: store, ouverte: sansNote)
        fenetre("reunions-5-effacer", store: store, ouverte: garnier, suppression: true)
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
