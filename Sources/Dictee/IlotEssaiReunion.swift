import AppKit
import DicteeCore

extension IlotEssai {
    /// La réunion dans l'îlot (maquette ilot-reunion.html, étapes 1 à 7) : « Noter cet appel ? » et ses deux boutons, le point rouge et le
    /// temps (≤ 66 pt dans la barre, rien sous la barre, aucune boucle), la carte au survol (son direct, « Centre », la pause, « Ajouter un
    /// point », « Ce que j'ai raté »), le défilement du direct (il s'arrête si on remonte, reprend en bas), le Centre et sa bande « Réunion
    /// en cours », un minuteur lancé pendant la réunion qui part dans la bulle, la dictée qui efface l'îlot le temps de dicter, les
    /// annonces d'après l'arrêt. Aucune vraie réunion : un contrôleur factice tient l'état et reçoit les gestes ; de VRAIS clics et de
    /// vrais défilements sont remis à la fenêtre invisible ; ni micro, ni son, ni réseau.
    @MainActor
    static func reunion(_ c: IlotControleur, verifier: (Bool, String) -> Void, attendre: (Double, () -> Bool) -> Void) {
        let m = c.moteur, g = m.geometrie
        let hc = Double(m.demiCamera), barre = Double(g.hauteur)
        func pause(_ s: Double) { attendre(s) { true } }
        func clic(_ p: CGPoint, _ apres: Double = 0.5) {
            c.panneau.envoyerSouris(.leftMouseDown, en: p); pause(0.06); c.panneau.envoyerSouris(.leftMouseUp, en: p); pause(apres)
        }
        func posee() { attendre(1.6) { m.boucleActive } }
        print("La réunion dans l'îlot")
        c.panneau.simulerPointeur(forme: false); m.fermer(); pause(0.8)

        // le contrôleur des réunions, factice : il tient l'état et applique les gestes, comme le vrai (sans micro ni réseau)
        var gestes: [String] = []
        var r = ReunionIlot()
        var annonce: AnnonceReunion?
        var lignesMoi: [SegmentReunion] = [], lignesEux: [SegmentReunion] = [], points: [Double] = [], attentes: [AttenteDirect] = []
        var enregistre = false
        func publier() { r.lignes = DirectReunion.lignes(moi: lignesMoi, eux: lignesEux, attentes: attentes, points: points); c.reunionChangee(enregistre ? r : nil, annonce: annonce) }
        c.surReunion = { a in
            gestes.append("\(a)")
            switch a {
            case .reunionNoter: annonce = nil; enregistre = true; r = ReunionIlot(); r.app = "Zoom"; r.depuis = c.maintenant()
            case .reunionRefuser: annonce = nil
            case .reunionPause: r.duree = r.temps(a: c.maintenant()); r.depuis = nil; r.enPause = true
            case .reunionReprendre: r.depuis = c.maintenant(); r.enPause = false
            case .reunionPoint: points.append(r.temps(a: c.maintenant())); r.pointFait = true; r.rattrapage = .ferme
            case .reunionRattrapage: r.rattrapage = .enCours
            case .reunionDirect: r.rattrapage = .ferme
            case .reunionArreter: enregistre = false; annonce = .prepare(etape: PreparationNote.relecture, progres: 0.1)
            default: break
            }
            publier()
        }
        let ancienneOccupation = c.occupation
        var occ = OccupationEncoche()
        c.occupation = { occ }

        // --- « Noter cet appel ? » : une annonce qui attend un geste (pas de survol), « Non » et « Noter »
        annonce = .propose(app: "Zoom"); publier(); pause(0.9)
        verifier(m.courante == .reunionPropose && m.resolution.verrou && !m.cache, "une app d'appel prend le micro : « Noter cet appel ? » dans l'îlot (\(m.courante))")
        verifier(m.trace.bande <= hc + GeoIlot.aileMax + 0.01, "l'annonce : ≤ 66 pt dans la barre de chaque côté de la caméra")
        let za = m.grille.zoneAnnonce(.reunionPropose)
        let lNoter = MesureIlot.bouton(.init(titre: "Noter", style: .noter, action: nil)), lNon = MesureIlot.bouton(.init(titre: "Non", action: nil))
        verifier(m.contenus[.reunionPropose].map { $0 <= za.width + 1.5 } == true, "la forme épouse « Noter cet appel ? » et ses deux boutons (\(Int(m.contenus[.reunionPropose] ?? 0)) pt)")
        c.panneau.simulerPointeur(forme: true); pause(0.6)
        verifier(m.courante == .reunionPropose, "survolée, l'annonce reste (pas de carte qui s'ouvre dessus)")
        clic(CGPoint(x: za.maxX - lNoter - ContenuAnnonce.espaceBoutons - lNon / 2, y: za.midY), 0.9)
        verifier(gestes.last == "reunionRefuser" && m.courante == .repos, "vrai clic sur « Non » : rien n'est enregistré, l'îlot se range (\(m.courante))")
        annonce = .propose(app: "Zoom"); publier(); pause(0.9)
        clic(CGPoint(x: za.maxX - lNoter / 2, y: za.midY), 0.9)
        verifier(gestes.last == "reunionNoter" && m.reunion != nil && !m.cache, "vrai clic sur « Noter » : la réunion commence, l'îlot ne s'efface pas (\(m.courante))")
        c.panneau.simulerPointeur(forme: false); m.fermer(); pause(0.9)

        // --- repliée : le point rouge et le temps, dans la barre, rien dessous, aucune boucle
        verifier(m.courante == .reunionCompact && m.resolution.survol == .reunionEtendu, "la réunion : le point rouge et le temps (\(m.courante))")
        verifier(m.trace.bande <= hc + GeoIlot.aileMax + 0.01 && m.trace.hauteur <= barre + 0.5, "repliée : \(Int(m.trace.bande - hc)) pt de chaque côté de la caméra (≤ 66), rien sous la barre")
        if let f = c.panneau.cadre { verifier(Double(f.height) <= barre + 0.5, "la fenêtre repliée ne descend pas sous la barre (onglets des apps cliquables) : \(Int(f.height)) pt") }
        posee()
        verifier(!m.boucleActive, "réunion repliée, posée : aucune boucle d'animation (l'onde et le point battent dans le serveur d'affichage ; bouge encore : \(m.ceQuiBouge))")
        let d0 = c.maintenant()
        r.depuis = d0.addingTimeInterval(-761); publier(); pause(0.2)
        verifier(FormatIlot.chrono((m.reunion ?? ReunionIlot()).temps(a: c.maintenant())).hasPrefix("12:4"), "le temps vient de l'heure de départ (12:41), sans minuterie de l'îlot")

        // --- le direct dans la carte, au survol
        lignesEux = [SegmentReunion(debut: 733, fin: 735.5, locuteur: .eux, texte: "Bon, la page d\u{2019}accueil me va."),
                     SegmentReunion(debut: 736, fin: 742, locuteur: .eux, texte: "Je changerais juste la couleur du bouton, il se voit mal sur téléphone.")]
        lignesMoi = [SegmentReunion(debut: 744, fin: 747.5, locuteur: .moi, texte: "D\u{2019}accord, on garde le vert de la marque alors.")]
        attentes = [AttenteDirect(locuteur: .eux, debut: 749)]
        publier()
        c.panneau.simulerPointeur(forme: true); pause(1.0)
        verifier(m.courante == .reunionEtendu && m.fenetreOuverte, "survol : la carte « Réunion » (\(m.courante))")
        verifier(m.cartes == [.reunionEtendu, .centre, .dictees, .accueil] && m.visible(ExtraIlot.points) && !m.visible(ExtraIlot.pied),
                 "les points de page (Réunion, Centre, Dictées, accueil), pas de pied (« Centre » est dans l'en-tête)")
        verifier(m.trace.bande <= hc + GeoIlot.aileMax + 0.01, "la carte : épaules ≤ 66 pt dans la barre (\(String(format: "%.1f", m.trace.bande - hc)))")
        verifier(abs(m.geo[2].cibleFinale - (barre + GeoIlot.profondeurReunion)) < 0.5, "la carte : \(Int(GeoIlot.profondeurReunion)) pt sous la barre (maquette : 291 − 33)")
        verifier(m.lignesDirect.map(\.locuteur) == [.eux, .moi, .eux] && m.lignesDirect.last?.enAttente == true,
                 "le direct : Eux, Moi, puis « Eux … » en gris (\(m.lignesDirect.map { "\($0.locuteur?.libelle ?? "point") \($0.texte)" }))")
        let p = PlanReunion.pied(m.grille)
        verifier(p.glyphes && p.point.maxX + PlanReunion.ecartBoutons <= p.pause.minX && p.arret.maxX <= PlanReunion.cadrePied(m.grille).maxX + 0.5,
                 "la rangée du bas tient avec ses glyphes (« Ajouter un point » finit \(Int(p.pause.minX - p.point.maxX)) pt avant la pause)")
        posee()
        verifier(!m.boucleActive, "carte posée : aucune boucle d'animation (bouge encore : \(m.ceQuiBouge))")
        let coteBarre = CGPoint(x: m.trace.bande + 20, y: barre / 2)
        verifier(!m.contient(coteBarre), "carte ouverte : à côté du cou, dans la barre des menus, le clic n'est pas pris (icônes de la barre)")

        // --- pause, reprise : vrais clics
        clic(CGPoint(x: p.pause.midX, y: p.pause.midY), 0.4)
        verifier(gestes.last == "reunionPause" && m.reunion?.enPause == true && m.courante == .reunionEtendu, "vrai clic sur pause : en pause, la carte reste ouverte")
        clic(CGPoint(x: p.pause.midX, y: p.pause.midY), 0.4)
        verifier(gestes.last == "reunionReprendre" && m.reunion?.enPause == false, "vrai clic sur reprise : la réunion repart")

        // --- « Ajouter un point » : le moment marqué paraît dans le direct
        clic(CGPoint(x: p.point.midX, y: p.point.midY), 0.4)
        verifier(gestes.last == "reunionPoint" && m.lignesDirect.contains { $0.estPoint } && m.reunion?.pointFait == true, "vrai clic sur « Ajouter un point » : « Point ajouté » dans le direct")
        r.pointFait = false; publier()

        // --- « Ce que j'ai raté » : en cours (les lignes qui luisent), puis les puces ; « Retour au direct »
        clic(CGPoint(x: p.rate.midX, y: p.rate.midY), 0.4)
        verifier(gestes.last == "reunionRattrapage" && m.reunion?.rattrapage == .enCours && m.courante == .reunionEtendu, "vrai clic sur « Ce que j'ai raté » : le résumé se prépare, dans la carte")
        r.rattrapage = .pret(["Claire valide la page d\u{2019}accueil.", "Tu enverras les fiches produits lundi."]); publier(); pause(0.3)
        clic(CGPoint(x: p.rate.midX, y: p.rate.midY), 0.4)
        verifier(gestes.last == "reunionDirect" && m.reunion?.rattrapage == .ferme, "second clic : retour au direct")

        // --- le direct défile : il s'arrête si on remonte, ce qu'on lit reste en place quand une phrase arrive, il reprend en bas
        lignesEux = (0..<14).map { i in SegmentReunion(debut: Double(600 + i * 10), fin: Double(605 + i * 10), locuteur: .eux, texte: "Il faudra relire les fiches produits une par une, numéro \(i + 1).") }
        lignesMoi = []; attentes = []; points = []
        publier(); pause(0.4)
        verifier(m.directDefile && m.defilementDirect.suit, "un long direct : il dépasse sa zone, la liste suit les phrases")
        let zd = PlanReunion.direct(m.grille)
        let surDirect = CGPoint(x: zd.midX, y: zd.midY)
        c.panneau.envoyerDefilement(dy: 12, en: surDirect, phase: 1); pause(0.02)
        c.panneau.envoyerDefilement(dy: 18, en: surDirect, phase: 2); pause(0.02)
        c.panneau.envoyerDefilement(dy: 0, en: surDirect, phase: 4); pause(0.3)
        let remonte = m.defilementDirect.decalage
        verifier(m.courante == .reunionEtendu && abs(remonte - 30) < 0.5, "deux doigts sur le direct : il remonte de 30 pt, la carte reste (\(Int(remonte)) pt, \(m.courante))")
        let avant = m.miseEnPageDirect().hauteur
        lignesEux.append(SegmentReunion(debut: 760, fin: 765, locuteur: .eux, texte: "Et on se revoit jeudi pour valider le tout."))
        publier(); pause(0.2)
        let ajout = m.miseEnPageDirect().hauteur - avant
        verifier(ajout > 0 && abs(m.defilementDirect.decalage - (remonte + ajout)) < 0.5, "une phrase arrive pendant qu'on relit : le texte lu ne bouge pas (+\(Int(ajout)) pt de décalage)")
        c.panneau.envoyerDefilement(dy: -2000, en: surDirect, phase: 1); pause(0.02); c.panneau.envoyerDefilement(dy: 0, en: surDirect, phase: 4); pause(0.3)
        verifier(m.defilementDirect.suit && m.courante == .reunionEtendu, "redescendu en bas : la liste suit de nouveau")
        lignesEux.append(SegmentReunion(debut: 770, fin: 774, locuteur: .eux, texte: "Parfait."))
        publier(); pause(0.2)
        verifier(m.defilementDirect.suit, "une phrase arrive en bas : on reste en bas")

        // --- le Centre reste atteignable : « Centre » dans l'en-tête, puis la bande « Réunion en cours » ramène au direct
        clic(CGPoint(x: PlanReunion.cadreCentre(m.grille).midX, y: PlanReunion.cadreCentre(m.grille).midY), 0.9)
        verifier(m.courante == .centre, "vrai clic sur « Centre » : le Centre pendant la réunion (\(m.courante))")
        verifier(m.nomPremiereCarte == "Réunion", "le Centre propose « ‹ Réunion » pour revenir")
        if let bande = PlanCentre.cadre(.bande, m) {
            clic(CGPoint(x: bande.midX, y: bande.midY), 0.9)
            verifier(m.courante == .reunionEtendu, "vrai clic sur « Réunion en cours · voir le direct » : la carte de la réunion (\(m.courante))")
        }
        // un minuteur lancé depuis le Centre pendant la réunion : replié, il part dans la bulle
        m.allerA(.centre); pause(0.8)
        c.agir(.minuteurLancerDansLeCentre(minutes: 25)); pause(0.3)
        c.panneau.simulerPointeur(forme: false); m.fermer(); pause(1.2)
        verifier(m.courante == .reunionCompact && m.pastille == .minuteur && m.pastilleMontree, "replié : la réunion garde l'îlot, le minuteur est dans la bulle (\(m.courante), \(String(describing: m.pastille)))")
        verifier(m.trace.bande <= hc + GeoIlot.aileMax + 0.01, "avec la bulle : la réunion reste ≤ 66 pt dans la barre")
        c.agir(.minuteurArreter); pause(0.6)

        // --- un défilement hors du direct change de carte, comme ailleurs
        c.panneau.simulerPointeur(forme: true); pause(1.0)
        let surEntete = CGPoint(x: PlanReunion.cadreEntete(m.grille).minX + 60, y: PlanReunion.cadreEntete(m.grille).midY)
        c.panneau.envoyerDefilement(dy: -6, en: surEntete, phase: 1); pause(0.02); c.panneau.envoyerDefilement(dy: -12, en: surEntete, phase: 2); pause(0.02)
        c.panneau.envoyerDefilement(dy: 0, en: surEntete, phase: 4); pause(0.8)
        verifier(m.courante == .centre, "deux doigts sur l'en-tête de la carte : la carte suivante, le Centre (\(m.courante))")
        c.panneau.simulerPointeur(forme: false); m.fermer(); pause(0.9)

        // --- une dictée pendant la réunion : l'îlot s'efface le temps de dicter, puis la réunion revient
        occ.dictee = true; c.occupationChangee(); pause(0.6)
        verifier(m.cache, "dictée (fn) pendant la réunion : l'îlot s'efface, la dictée a l'encoche")
        occ.dictee = false; c.occupationChangee(); pause(0.9)
        verifier(!m.cache && m.courante == .reunionCompact, "dictée finie : la réunion revient (\(m.courante))")

        // --- Arrêter (vrai clic) : « Note en préparation… », puis « Note prête · Ouvrir »
        c.panneau.simulerPointeur(forme: true); pause(1.0)
        let pa = PlanReunion.pied(m.grille).arret
        clic(CGPoint(x: pa.midX, y: pa.midY), 0.9)
        verifier(gestes.last == "reunionArreter" && m.reunion == nil && m.courante == .reunionPrepare && m.resolution.verrou,
                 "vrai clic sur Arrêter : « Note en préparation… » (\(m.courante))")
        // la progression avance (relecture puis rédaction) : la forme ne bouge pas, la barre seule avance
        let largeurAvant = m.contenus[.reunionPrepare] ?? 0, traceAvant = m.trace.bande
        annonce = .prepare(etape: PreparationNote.relecture, progres: 0.55); publier(); pause(0.5)
        annonce = .prepare(etape: PreparationNote.redaction, progres: 0.9); publier(); pause(0.6)
        verifier(m.courante == .reunionPrepare && abs((m.contenus[.reunionPrepare] ?? 0) - largeurAvant) < 0.5 && abs(m.trace.bande - traceAvant) < 0.5,
                 "« Note en préparation… » avance (10 % → 90 %, relecture → résumé) sans que la forme change de taille (\(Int(largeurAvant)) pt)")
        verifier(m.trace.bande <= hc + GeoIlot.aileMax + 0.01, "« Note en préparation… » : ≤ 66 pt dans la barre de chaque côté de la caméra")
        if let c0 = m.contenuAnnonce(.reunionPrepare) { verifier(c0.progres == 0.9 && c0.l2 == PreparationNote.redaction, "l'annonce porte l'étape et la progression") }
        let id = UUID()
        annonce = .prete(id: id, titre: "Lancement de la boutique en ligne", duree: 1740, sansNote: false); publier(); pause(0.9)
        verifier(m.courante == .reunionPrete, "« Note prête » (\(m.courante))")
        let zp = m.grille.zoneAnnonce(.reunionPrete)
        clic(CGPoint(x: zp.maxX - MesureIlot.bouton(.init(titre: "Ouvrir", style: .blanc, action: nil)) / 2, y: zp.midY), 0.6)
        verifier(gestes.last == "reunionOuvrirNote", "vrai clic sur « Ouvrir » : la note est demandée")
        annonce = nil; publier(); c.panneau.simulerPointeur(forme: false); pause(1.0)
        verifier(m.courante == .repos && m.reunion == nil && m.annonceReunion == nil, "tout est fini : l'îlot est vide (\(m.courante))")
        posee()
        verifier(!m.boucleActive, "réunion finie : aucune boucle d'animation (bouge encore : \(m.ceQuiBouge))")
        c.surReunion = { _ in }
        c.occupation = ancienneOccupation
    }

    /// La note après l'appel, sans réseau ni micro (maquette, étapes 9 à 12) : deux fichiers son écrits comme pendant un appel (calés sur
    /// l'heure de la réunion, 0600), la relecture lot par lot avec un Whisper factice qui vérifie que chaque lot reçoit le son du bon
    /// moment, un lot en échec qui garde le direct, la progression qui ne recule jamais, la note factice rangée, puis le son effacé.
    @MainActor
    static func noteApresAppel(dossier: URL, verifier: @escaping (Bool, String) -> Void, attendre: (Double, () -> Bool) -> Void) {
        print("La note après l'appel (relecture et note factices)")
        let d = dossier.appendingPathComponent("reunions-note", isDirectory: true)
        let store = ReunionStore(dossier: d, lire: false)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        var r0 = Reunion(debut: Date(timeIntervalSince1970: 1_800_000_000), duree: 90, etat: .transcription, sonGarde: false)
        r0.points = [30]
        // le son : chaque seconde t porte la valeur t (on reconnaît le moment de la réunion dans un lot)
        func ecrire(_ l: Locuteur, de a: Int, a b: Int) {
            guard let w = EcrivainWAV(url: store.fichierSon(r0, l)) else { verifier(false, "fichier son \(l.libelle) créé"); return }
            w.caler(sur: Double(a))
            for t in a..<b { w.ajouter([Int16](repeating: Int16(t), count: 16_000)) }
            if l == .moi { w.fermer() }   // la piste « Eux » reste sans en-tête complet (arrêt brutal) : la lecture doit tenir quand même
        }
        ecrire(.moi, de: 10, a: 40); ecrire(.eux, de: 50, a: 80)
        let droits = (try? FileManager.default.attributesOfItem(atPath: store.fichierSon(r0, .moi).path)[.posixPermissions] as? Int) ?? 0
        verifier(droits == 0o600, "le son de la réunion : fichier en 0600 (\(String(droits, radix: 8)))")
        verifier(abs(LectureWAV.duree(store.fichierSon(r0, .eux)) - 80) < 0.01, "son calé sur l'heure de la réunion, lisible même sans en-tête complet (\(LectureWAV.duree(store.fichierSon(r0, .eux))) s)")
        verifier(LectureWAV.echantillons(store.fichierSon(r0, .moi), de: 12.5, a: 12.6)?.allSatisfy { $0 == 12 } == true, "la seconde 12 de la réunion est bien à 12 s dans le fichier")

        let passages: [Locuteur: [PassageParole]] = [.moi: [PassageParole(debut: 10, fin: 20), PassageParole(debut: 25, fin: 40)], .eux: [PassageParole(debut: 50, fin: 80)]]
        let direct = [SegmentReunion(debut: 10, fin: 20, locuteur: .moi, texte: "direct moi"), SegmentReunion(debut: 50, fin: 60, locuteur: .eux, texte: "Le direct d'Eux est gardé.")]
        let bonsSons = Verrouille<[Bool]>([])
        var relecture = RelectureAudio()
        relecture.transcrire = { lot, son, _ in
            // chaque passage du lot : on lit la valeur une seconde après son début, elle doit être la seconde de la réunion
            var x = 0.0, ok = true
            for p in lot.passages {
                let i = Int((x + 1) * 16_000)
                ok = ok && i < son.count && Int(son[i]) == Int(p.debut + 1)
                x += p.duree + LotRelecture.silence
            }
            _ = bonsSons.remplacer(bonsSons.valeur + [ok])
            if lot.locuteur == .eux { throw GroqErreur.http(429) }
            var y = 0.0
            return lot.passages.map { p in defer { y += p.duree + LotRelecture.silence }; return PhraseWhisper(debut: y + 0.3, fin: y + p.duree - 0.3, texte: "Relu à \(Int(p.debut + 0.3)) s.") }
        }
        let avances = Verrouille<[Double]>([])
        let enregistre = Verrouille<Bool>(false)
        let rediger: ReunionController.RedigerNote = { segments, _, _, avance in
            avance(0, 2); avance(1, 2); avance(2, 2)
            return (NoteBrute(titre: "Essai", sujets: [SujetReunion(titre: "Sujet", puces: [PuceReunion(texte: segments.first?.texte ?? "")])]), [])
        }
        var resultat: Reunion?
        var fini = false
        Task {
            resultat = await ReunionController.preparer(r0, passages: passages, direct: direct, fichiers: [.moi: store.fichierSon(r0, .moi), .eux: store.fichierSon(r0, .eux)],
                                                       relecture: relecture, rediger: rediger, surNote: { _ in _ = enregistre.remplacer(true) }) { p, _ in _ = avances.remplacer(avances.valeur + [p]) }
            fini = true
        }
        attendre(10) { !fini }
        guard let r = resultat else { verifier(false, "la note est préparée"); return }
        verifier(bonsSons.valeur.count == 2 && bonsSons.valeur.allSatisfy { $0 }, "deux lots (un par voix), chacun reçoit le son du bon moment de la réunion (\(bonsSons.valeur))")
        verifier(r.relue == true && r.segments.contains { $0.locuteur == .moi && $0.texte.hasPrefix("Relu à 10") && abs($0.debut - 10) < 0.5 }, "« Moi » : la transcription relue, à la bonne heure (\(r.segments.map(\.texte)))")
        verifier(!r.segments.contains { $0.texte == "direct moi" } && r.segments.contains { $0.texte == "Le direct d'Eux est gardé." }, "le direct relu disparaît ; le lot en échec garde le direct (rien ne se perd)")
        verifier(r.avertissements.contains { $0.contains("pas pu être relu") }, "la note dit qu'un passage vient du direct")
        verifier(r.etat == .prete && r.sujets?.first?.titre == "Sujet" && r.titre == "Essai" && enregistre.valeur, "la note est rangée ; la transcription relue a été enregistrée avant la rédaction")
        let a = avances.valeur
        verifier(!a.isEmpty && zip(a, a.dropFirst()).allSatisfy { $0 <= $1 + 1e-9 } && (a.last ?? 0) > 0.9, "la progression ne recule jamais et finit au-delà de 90 % (\(a.map { Int($0 * 100) }))")
        store.effacerSon(r)
        attendre(2) { store.sonPresent(r, .moi) || store.sonPresent(r, .eux) }
        verifier(!store.sonPresent(r, .moi) && !store.sonPresent(r, .eux), "note prête, réglage « garder le son » éteint : les deux fichiers son sont effacés")
    }
}
