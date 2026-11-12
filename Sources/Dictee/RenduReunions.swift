import AppKit
import SwiftUI
import DicteeCore

/// `Dictee --rendu-reunion dossier` : la liste et la note en PNG (la réunion dans l'îlot : `--rendu-ilot`, ilot-27*), sans fenêtre. Réunions d'exemple, jamais celles de l'utilisateur ; ni micro ni son du Mac.
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

    /// La réunion de la maquette ilot-reunion.html (étapes 11 et 12) : « Lancement de la boutique en ligne », mercredi 11 novembre
    /// 2026, 14:02, 29 min. Les voix restent « Moi » et « Eux » (pas encore de séparation des voix).
    static func boutique() -> Reunion {
        let cal = Calendar.current
        let debut = cal.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 14, minute: 2))!
        func seg(_ m: Int, _ s: Int, _ d: Double, _ l: Locuteur, _ t: String) -> SegmentReunion {
            let t0 = Double(m * 60 + s); return SegmentReunion(debut: t0, fin: t0 + d, locuteur: l, texte: t, orateur: l.rawValue)
        }
        let segments = [
            seg(11, 10, 9, .eux, "Bon, la page d\u{2019}accueil me va. Je changerais juste la couleur du bouton « Commander », il se voit mal sur téléphone."),
            seg(11, 22, 5, .moi, "D\u{2019}accord, on garde le vert de la marque alors, il ressort mieux."),
            seg(12, 4, 8, .eux, "Pour la mise en ligne, le 2 décembre, c\u{2019}est faisable de mon côté. À condition d\u{2019}avoir tous les textes avant le 25."),
            seg(12, 15, 4, .moi, "Je m\u{2019}occupe des fiches produits. Je te les envoie lundi."),
            seg(13, 12, 7, .eux, "Parfait. Et pour les photos, je préfère qu\u{2019}on fasse une seule séance à l\u{2019}atelier, plutôt que deux."),
            seg(13, 24, 5, .eux, "Oui, les photos actuelles sont trop sombres, surtout pour les tasses."),
            seg(14, 2, 6, .eux, "Je réserve la séance avant le 20 et je vous dis le jour demain."),
            seg(14, 30, 4, .eux, "Et le paiement en trois fois, on le met dès le lancement ?"),
            seg(15, 3, 5, .moi, "Non, après. On lance simple, on l\u{2019}ajoute en janvier."),
        ]
        func act(_ qui: String, _ quoi: String, _ quand: String) -> ActionReunion {
            ActionReunion(qui: qui, quoi: quoi, quand: quand, echeance: Echeance.analyser(quand, depuis: debut).date)
        }
        var r = Reunion(debut: debut, duree: 29 * 60, titre: "Lancement de la boutique en ligne", participants: ["Moi"],
                        decisions: ["Mise en ligne le 2 décembre", "Bouton « Commander » en vert", "Paiement en trois fois en janvier"],
                        actions: [act("Moi", "Écrire les 40 fiches produits, les envoyer à Marc", "lundi"),
                                  act("Claire", "Passer le bouton en vert sur la maquette", "vendredi"),
                                  act("Inès", "Réserver la séance photo à l\u{2019}atelier", "avant le vingt novembre"),
                                  act("Marc", "Mettre le site en ligne", "le 2 décembre")],
                        segments: segments, etat: .prete, sonGarde: true,
                        enBref: "La page d\u{2019}accueil est validée et le site sortira le 2 décembre, à condition que les textes arrivent avant le 25 novembre.")
        r.decisionsEcheances = [EcheanceReunion(quand: "textes avant le 25"), nil, nil]
        r.sujets = [SujetReunion(titre: "Page d\u{2019}accueil", puces: [PuceReunion(texte: "Claire valide la maquette, seul le bouton « Commander » change de couleur", sous: ["On garde le vert de la marque, plus lisible sur téléphone"]),
                                                                        PuceReunion(texte: "Les avis clients passent sous les photos")]),
                    SujetReunion(titre: "Date de mise en ligne", puces: [PuceReunion(texte: "Marc peut mettre le site en ligne le mercredi 2 décembre", sous: ["À une condition : tous les textes avant le 25 novembre"]),
                                                                        PuceReunion(texte: "Paiement en trois fois ajouté après le lancement, en janvier")]),
                    SujetReunion(titre: "Photos et fiches produits", puces: [PuceReunion(texte: "40 produits à photographier, les photos actuelles sont trop sombres"),
                                                                            PuceReunion(texte: "Une seule séance à l\u{2019}atelier plutôt que deux")])]
        r.points = [Double(13 * 60 + 10)]
        r.relue = true
        return r
    }

    /// Les autres réunions de la colonne (titres de la maquette) et une ancienne note (« Dit » seulement, avant les sujets).
    static func autres() -> [Reunion] {
        let cal = Calendar.current
        func d(_ jour: Int, _ h: Int, _ m: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: jour, hour: h, minute: m))! }
        func note(_ debut: Date, _ titre: String, _ duree: Double, _ gens: [String], _ bref: String) -> Reunion {
            var r = Reunion(debut: debut, duree: duree, titre: titre, participants: gens, etat: .prete, enBref: bref)
            r.sujets = [SujetReunion(titre: "L\u{2019}essentiel", puces: [PuceReunion(texte: bref)])]
            return r
        }
        var ancienne = Reunion(debut: d(5, 9, 15), duree: 25 * 60, titre: "Visite de l\u{2019}atelier", participants: ["Moi", "Inès", "Marc"],
                               dit: ["Deux postes de travail à déplacer avant la séance photo", "La lumière du fond est trop faible pour les tasses"],
                               decisions: ["Séance photo à l\u{2019}atelier"], etat: .prete, enBref: "L\u{2019}atelier accueillera la séance photo, deux postes seront déplacés.")
        ancienne.segments = [SegmentReunion(debut: 12, fin: 20, locuteur: .eux, texte: "On peut pousser ces deux tables contre le mur."),
                             SegmentReunion(debut: 22, fin: 26, locuteur: .moi, texte: "D\u{2019}accord, on fera ça la veille.")]
        var sansNote = Reunion(debut: d(10, 17, 40), duree: 1020, etat: .sansNote)
        sansNote.segments = [SegmentReunion(debut: 3, fin: 6, locuteur: .eux, texte: "On se rappelle demain pour la suite."),
                             SegmentReunion(debut: 9, fin: 11, locuteur: .moi, texte: "D\u{2019}accord, à demain.")]
        sansNote.avertissements = ["La note n\u{2019}a pas pu être écrite (réseau : code -1009). La transcription est gardée : « Refaire la note » réessaie."]
        return [note(d(9, 10, 30), "Point fournisseur emballages", 18 * 60, ["Moi", "Paul"], "Livraison des boîtes confirmée pour le 23 novembre."),
                sansNote,
                note(d(5, 16, 0), "Appel avec la comptable", 42 * 60, ["Moi", "Sophie"], "Bilan à rendre avant fin janvier, deux justificatifs manquent."),
                ancienne]
    }

    /// Un son fabriqué pour les rendus : sur chaque passage de sa piste, un bruit modulé comme une voix (syllabes, intensité qui
    /// varie), le silence ailleurs. Écrit comme pendant un appel (calé sur l'heure de la réunion).
    @MainActor
    static func sonFabrique(_ r: Reunion, store: ReunionStore) {
        var graine: UInt32 = 12_345
        func hasard() -> Float { graine = graine &* 1_664_525 &+ 1_013_904_223; return Float(graine >> 8) / Float(1 << 24) * 2 - 1 }
        for l in [Locuteur.moi, .eux] {
            guard let w = EcrivainWAV(url: store.fichierSon(r, l)) else { continue }
            for s in r.segments where s.locuteur == l {
                w.caler(sur: s.debut)
                let n = Int((s.fin - s.debut) * 16_000)
                var son = [Int16](repeating: 0, count: n)
                for i in 0..<n {
                    let t = Float(i) / 16_000
                    let syllabe = max(0, sin(t * 2 * .pi * 3.7 + Float(s.debut)))
                    let phrase = 0.55 + 0.45 * sin(t * 2 * .pi * 0.31 + Float(s.debut) * 0.7)
                    son[i] = Int16(hasard() * 9_000 * syllabe * phrase)
                }
                w.ajouter(son)
            }
            w.fermer()
        }
    }

    @MainActor
    static func executer(dossier: String) -> Int32 {
        _ = NSApplication.shared
        Polices.enregistrer()
        let url = URL(fileURLWithPath: (dossier as NSString).expandingTildeInPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var ok = true

        // L'encoche des réunions est devenue une activité de l'îlot : ses rendus sont avec ceux de l'îlot (`--rendu-ilot`, ilot-27*).

        let boutique = boutique()
        let exemples = [boutique] + autres()
        let dossierRendu = FileManager.default.temporaryDirectory.appendingPathComponent("dictee-rendu-reunions")
        try? FileManager.default.removeItem(at: dossierRendu)
        let store = ReunionStore(dossier: dossierRendu, lire: false)
        for r in exemples { store.enregistrer(r) }
        let vide = ReunionStore(dossier: FileManager.default.temporaryDirectory.appendingPathComponent("dictee-rendu-reunions-vide"), lire: false)
        // le son gardé : un son fabriqué (un bruit modulé comme une voix, sur les heures des passages de chaque piste), pour que les
        // bulles aient une vraie onde ; jamais le son de l'utilisateur
        try? FileManager.default.createDirectory(at: store.dossier, withIntermediateDirectories: true)
        Self.sonFabrique(boutique, store: store)
        defer { try? FileManager.default.removeItem(at: dossierRendu) }
        let historique = RenduVues.historiqueExemple()
        let maquette = CGSize(width: 1190, height: 760)   // la taille de la capture de la maquette, pour comparer
        let haute = CGSize(width: 1190, height: 1400)
        let petite = CGSize(width: 700, height: 640)
        let aujourdhui = boutique.debut.addingTimeInterval(40 * 60)

        func fenetre(_ nom: String, store: ReunionStore, ouverte: UUID? = nil, taille: CGSize = maquette, regler: (ReunionsModele) -> Void = { _ in }) {
            let nav = NavigationFenetre(); nav.onglet = .reunions
            let r = ReunionsModele(store: store)
            r.aujourdhui = { aujourdhui }
            r.ouverte = ouverte
            for x in store.reunions { r.chargerOndesMaintenant(x) }
            regler(r)
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
        let photo = boutique.segments.firstIndex { $0.texte.hasPrefix("Je réserve la séance") }!
        fenetre("reunions-1-note", store: store)
        fenetre("reunions-2-note-entiere", store: store, taille: haute)
        fenetre("reunions-3-ecoute-et-demander", store: store, taille: haute) { m in
            m.simulerEcoute(photo, fraction: 0.35)
            m.reponse = .prete(question: "Qui s\u{2019}occupe des photos ?", QuestionReunion.Reponse(texte: "Inès. Elle réserve une seule séance photo à l\u{2019}atelier avant le 20 novembre et donne le jour demain.", passage: photo))
        }
        fenetre("reunions-3b-reponse-en-attente", store: store) { m in m.reponse = .attente(question: "Quand le site sort-il ?") }
        var renommee = boutique; renommee.renommer(orateur: "eux", en: "Claire")
        let storeRenomme = ReunionStore(dossier: FileManager.default.temporaryDirectory.appendingPathComponent("dictee-rendu-reunions-renomme"), lire: false)
        storeRenomme.enregistrer(renommee)
        fenetre("reunions-4-eux-renomme-claire", store: storeRenomme, taille: haute)
        fenetre("reunions-5-demander-a-mes-reunions", store: store) { m in
            m.demandeToutes = true
            m.poserReponseToutes(.prete(question: "Quand sort le site ?", QuestionReunion.Reponse(texte: "Le mercredi 2 décembre, si Marc a tous les textes avant le 25 novembre (appel du 11 novembre).", reunion: 0)), envoyees: [boutique])
        }
        fenetre("reunions-6-sans-note", store: store, ouverte: exemples.first { $0.etat == .sansNote }!.id)
        fenetre("reunions-7-ancienne-note", store: store, ouverte: exemples.last!.id)
        fenetre("reunions-8-effacer", store: store) { m in m.suppressionEnAttente = true }
        fenetre("reunions-9-recherche", store: store) { m in m.requete = "photos" }
        fenetre("reunions-10-vide", store: vide)
        fenetre("reunions-11-etroite-note", store: store, ouverte: boutique.id, taille: petite)
        fenetre("reunions-12-etroite-liste", store: store, taille: petite)
        fenetre("reunions-13-a-la-taille-de-hugues", store: store, taille: CGSize(width: 1190, height: 650))
        // une partie de l'appel n'a pas pu être relue (réseau, limite) : le son est gardé quelques jours, « Refaire la note » réessaie
        var partielle = boutique; partielle.relue = false; partielle.sonGarde = false
        partielle.avertissements = ["2 passages de l\u{2019}appel n\u{2019}ont pas pu être relus (réseau ou limite de Groq) : c\u{2019}est la transcription du direct.",
                                    "\(ReunionController.avertissementSonGarde) \(ArchiveReunions.joursSonEnAttente) jours sur ce Mac, le temps de « Refaire la note »."]
        let dossierPartielle = FileManager.default.temporaryDirectory.appendingPathComponent("dictee-rendu-reunions-partielle")
        try? FileManager.default.removeItem(at: dossierPartielle)
        let storePartielle = ReunionStore(dossier: dossierPartielle, lire: false)
        storePartielle.enregistrer(partielle)
        try? FileManager.default.createDirectory(at: dossierPartielle, withIntermediateDirectories: true)
        for l in [Locuteur.moi, .eux] { FileManager.default.createFile(atPath: storePartielle.fichierSon(partielle, l).path, contents: Data()) }
        fenetre("reunions-14-pas-entierement-relue", store: storePartielle)
        try? FileManager.default.removeItem(at: dossierPartielle)

        // MARK: les bulles audio de la transcription, de près (son gardé, en lecture, son effacé)
        do {
            let mb = ReunionsModele(store: store)
            mb.chargerOndesMaintenant(boutique)
            let premiers = Array(boutique.segments.indices.prefix(4))
            mb.simulerEcoute(premiers[1], fraction: 0.42)
            let me = ReunionsModele(store: storeRenomme)
            let tailleB = CGSize(width: 820, height: 620)
            let vue = ZStack(alignment: .topLeading) {
                Palette.surface
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(premiers, id: \.self) { i in LigneTranscriptionVue(m: mb, r: boutique, index: i, heure: i == 0 ? "14:13" : nil, son: true) }
                    Text("Son effacé (réglage « Garder le son des réunions » éteint) :").font(Polices.commande(12)).foregroundStyle(Palette.texte3).padding(.top, 18)
                    LigneTranscriptionVue(m: me, r: renommee, index: 1, heure: nil, son: false)
                }
                .padding(.horizontal, 36).padding(.vertical, 24)
            }
            ok = RenduVues.ecrire(RenduVues.png(vue, taille: tailleB), url.appendingPathComponent("reunions-15-bulles-audio.png")) && ok
        }

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
