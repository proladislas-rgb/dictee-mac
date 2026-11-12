import AppKit
import AVFoundation
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
        verifier(m.cartes == [.reunionEtendu, .centre, .outils, .accueil, .dictees] && m.visible(ExtraIlot.points) && !m.visible(ExtraIlot.pied),
                 "les points de page (Réunion, Centre, Outils, accueil, Dictées : la pile de main), pas de pied (« Centre » est dans l'en-tête)")
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
            // la piste « Eux » reste sans en-tête complet (arrêt brutal) : la lecture doit tenir quand même
            if l == .moi { w.fermer() } else { w.vider() }
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
        verifier(r.relue == false && r.segments.contains { $0.locuteur == .moi && $0.texte.hasPrefix("Relu à 10") && abs($0.debut - 10) < 0.5 }, "« Moi » : la transcription relue, à la bonne heure ; un lot en échec : l'appel n'est pas « entièrement relu » (\(r.segments.map(\.texte)))")
        verifier(r.passagesParVoix == passages, "les passages de parole restent avec la réunion (« Refaire la note » les relira)")
        verifier(!ArchiveReunions.sonInutile(apresNote: r), "un lot pas relu : le son n'est PAS effacé après la note")
        verifier(!r.segments.contains { $0.texte == "direct moi" } && r.segments.contains { $0.texte == "Le direct d'Eux est gardé." }, "le direct relu disparaît ; le lot en échec garde le direct (rien ne se perd)")
        verifier(r.avertissements.contains { $0.contains("pas pu être relu") }, "la note dit qu'un passage vient du direct")
        verifier(r.etat == .prete && r.sujets?.first?.titre == "Sujet" && r.titre == "Essai" && enregistre.valeur, "la note est rangée ; la transcription relue a été enregistrée avant la rédaction")
        let a = avances.valeur
        verifier(!a.isEmpty && zip(a, a.dropFirst()).allSatisfy { $0 <= $1 + 1e-9 } && (a.last ?? 0) > 0.9, "la progression ne recule jamais et finit au-delà de 90 % (\(a.map { Int($0 * 100) }))")
        store.effacerSon(r)
        attendre(2) { store.sonPresent(r, .moi) || store.sonPresent(r, .eux) }
        verifier(!store.sonPresent(r, .moi) && !store.sonPresent(r, .eux), "effacerSon : les deux fichiers son sont effacés")
    }

    /// Relecture de l'équipe : le son de l'appel n'est jamais effacé tant qu'il peut encore servir (relecture en échec, note pas écrite),
    /// Verbe fermé pendant l'appel, une réunion effacée ou renommée pendant la préparation, le son hors de Time Machine, le direct qui
    /// ne prend plus de retard à l'arrêt, les puces de « Ce que j'ai raté » coupées à un mot entier. Le vrai contrôleur, un dossier à
    /// part, une relecture et une rédaction factices : ni micro, ni réseau.
    @MainActor
    static func sonDeReunionGarde(dossier: URL, verifier: @escaping (Bool, String) -> Void, attendre: (Double, () -> Bool) -> Void) {
        print("Réunions : le son gardé tant qu'il peut servir (relecture en échec, Verbe fermé, réunion effacée)")
        let d = dossier.appendingPathComponent("reunions-son-garde", isDirectory: true)
        try? FileManager.default.removeItem(at: d)
        let store = ReunionStore(dossier: d, lire: false)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        let echoue = Verrouille<Int>(0)
        let note: ReunionController.RedigerNote = { segments, _, _, _ in
            (NoteBrute(titre: "Note factice", sujets: [SujetReunion(titre: "Sujet", puces: [PuceReunion(texte: segments.first?.texte ?? "")])]), [])
        }
        func controleur(relit: Bool, rediger: @escaping ReunionController.RedigerNote = note) -> ReunionController {
            let c = ReunionController(store: store)
            var rel = RelectureAudio()
            rel.transcrire = { lot, _, _ in
                guard relit else { _ = echoue.remplacer(echoue.valeur + 1); throw GroqErreur.http(429) }
                return [PhraseWhisper(debut: 0.2, fin: max(0.3, lot.duree - 0.2), texte: "Relu à \(Int(lot.debut)) s, \(lot.locuteur.libelle).")]
            }
            c.relecture = rel
            c.rediger = rediger
            c.separation = nil   // jamais la vraie séparation des voix dans l'essai (elle téléchargerait son modèle)
            return c
        }
        func reunion(_ n: Int) -> Reunion {
            var r = Reunion(debut: Date(timeIntervalSince1970: 1_800_000_000 + Double(n) * 3600), duree: 60, etat: .transcription, sonGarde: false)
            r.passagesParVoix = [.moi: [PassageParole(debut: 5, fin: 20)], .eux: [PassageParole(debut: 25, fin: 50)]]
            for l in [Locuteur.moi, .eux] {
                guard let w = EcrivainWAV(url: store.fichierSon(r, l)) else { verifier(false, "fichier son créé"); return r }
                w.ajouter([Int16](repeating: 100, count: 16_000 * 60)); w.fermer()
            }
            store.enregistrer(r)
            return r
        }
        func json(_ r: Reunion) -> Bool {
            store.attendreEcritures()
            return FileManager.default.fileExists(atPath: d.appendingPathComponent(ArchiveReunions.nomDeBase(r) + ".json").path)
        }
        func son(_ r: Reunion) -> Bool { store.attendreEcritures(); return store.sonPresent(r, .moi) && store.sonPresent(r, .eux) }
        func finir(_ c: ReunionController, _ r: Reunion, direct: [SegmentReunion] = []) {
            var fini = false
            Task { await c.finir(r, passages: r.passagesParVoix, direct: direct, fichiers: [.moi: store.fichierSon(r, .moi), .eux: store.fichierSon(r, .eux)]); fini = true }
            attendre(10) { !fini }
            verifier(fini, "le traitement se termine")
        }

        // 1. Groq en panne pendant tout l'appel : le direct est vide, chaque lot de la relecture échoue
        let r1 = reunion(1)
        finir(controleur(relit: false), r1)
        let v1 = store.reunion(id: r1.id)
        verifier(echoue.valeur == 2, "relecture factice en échec : deux lots essayés (\(echoue.valeur))")
        verifier(v1?.etat == .sansNote && v1?.relue == false, "relecture impossible, direct vide : la réunion reste, sans note (\(String(describing: v1?.etat)))")
        verifier(json(r1) && son(r1), "relecture impossible : le JSON et les deux WAV restent sur le disque")
        verifier(v1?.avertissements.contains { $0.contains("pas pu être relu") } == true && v1?.avertissements.contains { $0.hasPrefix(ReunionController.avertissementSonGarde) } == true,
                 "la note dit que l'appel n'a pas été relu et que le son est gardé (\(v1?.avertissements ?? []))")

        // « Refaire la note » sur cette réunion, sans aucune transcription : le son et les passages enregistrés sont relus
        var fini = false
        let c1 = controleur(relit: true)
        let t1 = c1.refaireLaNote(id: r1.id)
        verifier(t1 != nil, "« Refaire la note » possible sans transcription, le son est là")
        Task { await t1?.value; fini = true }
        attendre(10) { !fini }
        let v1b = store.reunion(id: r1.id)
        verifier(v1b?.etat == .prete && v1b?.relue == true && v1b?.segments.contains { $0.texte.hasPrefix("Relu à 4 s") } == true,
                 "« Refaire la note » relit l'appel avec les passages gardés, puis écrit la note (\(v1b?.segments.map(\.texte) ?? []))")
        verifier(v1b?.avertissements.contains { $0.contains("pas pu être relu") || $0.hasPrefix(ReunionController.avertissementSonGarde) } == false, "tout est relu : les avertissements de relecture partent")
        attendre(2) { store.sonPresent(r1, .moi) }
        verifier(!store.sonPresent(r1, .moi) && !store.sonPresent(r1, .eux) && v1b?.passagesMoi == nil, "note prête et tout l'appel relu : le son (et les passages) sont effacés")

        // 2. relecture en échec mais un peu de direct : note écrite, le son reste pour réessayer
        let r2 = reunion(2)
        finir(controleur(relit: false), r2, direct: [SegmentReunion(debut: 25, fin: 35, locuteur: .eux, texte: "Un bout du direct.")])
        let v2 = store.reunion(id: r2.id)
        verifier(v2?.etat == .prete && v2?.relue == false && son(r2), "relecture en échec, note écrite depuis le direct : le son n'est pas effacé")

        // 3. tout relu : le son part
        let r3 = reunion(3)
        finir(controleur(relit: true), r3)
        attendre(2) { store.sonPresent(r3, .moi) }
        verifier(store.reunion(id: r3.id)?.relue == true && !store.sonPresent(r3, .moi) && !store.sonPresent(r3, .eux), "tout l'appel relu, note prête : le son est effacé")

        // 4. rien entendu (aucun passage, aucun direct) : la réunion n'est pas gardée
        var r4 = reunion(4)
        r4.passagesParVoix = [.moi: [], .eux: []]
        store.enregistrer(r4)
        finir(controleur(relit: false), r4)
        attendre(2) { json(r4) }
        verifier(store.reunion(id: r4.id) == nil && !json(r4) && !store.sonPresent(r4, .moi), "rien entendu : réunion et son effacés")

        // 5. renommée puis 6. effacée pendant la préparation de la note
        let r5 = reunion(5)
        let renommer: ReunionController.RedigerNote = { segments, duree, debut, avance in
            await MainActor.run {
                guard var x = store.reunion(id: r5.id) else { return }
                x.titre = "Point Dupont"; x.renommer(orateur: Locuteur.eux.rawValue, en: "Claire")
                store.enregistrer(x)
            }
            return try await note(segments, duree, debut, avance)
        }
        finir(controleur(relit: true, rediger: renommer), r5)
        let v5 = store.reunion(id: r5.id)
        verifier(v5?.titre == "Point Dupont" && v5?.orateur(id: Locuteur.eux.rawValue).nom == "Claire", "titre et orateur changés pendant la préparation : gardés (\(v5?.titre ?? "-"))")
        let r6 = reunion(6)
        let effacer: ReunionController.RedigerNote = { segments, duree, debut, avance in
            await MainActor.run { store.supprimer(id: r6.id) }
            return try await note(segments, duree, debut, avance)
        }
        finir(controleur(relit: true, rediger: effacer), r6)
        attendre(2) { json(r6) }
        verifier(store.reunion(id: r6.id) == nil && !json(r6) && !store.sonPresent(r6, .moi), "effacée pendant la préparation : rien n'est recréé")

        // 7. Verbe fermé : le son reste quelques jours, puis il est effacé au lancement
        var r7 = reunion(7)
        r7.etat = .sansNote; store.enregistrer(r7)
        let fin7 = r7.debut.addingTimeInterval(r7.duree)
        store.attendreEcritures()
        _ = ReunionStore(dossier: d, maintenant: fin7.addingTimeInterval(86_400))
        verifier(son(r7), "son gardé pour réessayer : encore là le lendemain")
        _ = ReunionStore(dossier: d, maintenant: fin7.addingTimeInterval(Double(ArchiveReunions.joursSonEnAttente + 1) * 86_400))
        verifier(!store.sonPresent(r7, .moi) && !store.sonPresent(r7, .eux) && json(r7), "après \(ArchiveReunions.joursSonEnAttente) jours : le son est effacé au lancement, la réunion reste")

        // 8. le son temporaire hors de Time Machine ; gardé (réglage) : sauvegardé
        let u1 = d.appendingPathComponent("tm-hors.wav"), u2 = d.appendingPathComponent("tm-garde.wav")
        EcrivainWAV(url: u1, horsSauvegarde: true)?.fermer(); EcrivainWAV(url: u2, horsSauvegarde: false)?.fermer()
        let ex1 = (try? u1.resourceValues(forKeys: [.isExcludedFromBackupKey]))?.isExcludedFromBackup
        let ex2 = (try? u2.resourceValues(forKeys: [.isExcludedFromBackupKey]))?.isExcludedFromBackup
        verifier(ex1 == true && ex2 == false, "son temporaire exclu de Time Machine, son gardé (réglage) sauvegardé (\(String(describing: ex1)), \(String(describing: ex2)))")
        // l'écriture du son se fait sur une file à part, dans l'ordre, et le compte des échantillons suit tout de suite
        let u3 = d.appendingPathComponent("ordre.wav")
        if let w = EcrivainWAV(url: u3) {
            w.ajouter([1, 2]); w.caler(sur: 1); w.ajouter([3])
            verifier(w.echantillons == 16_001, "le compte des échantillons ne dépend pas de l'écriture (\(w.echantillons))")
            w.fermer()
            let e = LectureWAV.echantillons(u3, de: 0, a: 2) ?? []
            verifier(e.count == 16_001 && e[0] == 1 && e[1] == 2 && e[2] == 0 && e[16_000] == 3, "écrit dans l'ordre, silence de calage compris (\(e.count) échantillons)")
        }

        // 9. à l'arrêt, les morceaux du direct pas encore partis ne partent plus (aucun réseau : abandon avant l'envoi)
        let t = TranscriptionReunion(correcteur: nil)
        t.abandonnerLaFile()
        for i in 0..<3 { t.soumettre(MorceauReunion(locuteur: .eux, debut: Double(i * 10), echantillons: [Int16](repeating: 0, count: 16_000))) }
        var finiT = false
        Task { await t.attendreLaFin(); finiT = true }
        attendre(3) { !finiT }
        verifier(finiT && t.abandonnes == 3 && t.echecs == 0 && t.recus == 0, "relecture qui prend le relais : les morceaux en attente renoncent sans partir (\(t.abandonnes) abandonnés)")

        // 10. « Ce que j'ai raté » : une puce trop longue finit à un mot entier sur deux lignes au plus, à la vraie police
        let longue = "Claire envoie le devis signé jeudi avant midi, et Paul relance le fournisseur pour la livraison des panneaux du 2 décembre à Lyon."
        for l: CGFloat in [380, 424, 460] {
            let p = RattrapageVue.puce(longue, largeur: l)
            let n = MesureIlot.lignes(p, 13.5, .regular, largeur: RattrapageVue.largeurPuce(l))
            verifier(n <= 2 && (p == longue || (p.hasSuffix("\u{2026}") && longue.hasPrefix(String(p.dropLast())) && longue.dropFirst(p.count - 1).first.map { " ,;:".contains($0) } == true)),
                     "puce de \(longue.count) caractères à \(Int(l)) pt : \(n) ligne(s), coupée à un mot entier (« \(p.suffix(24)) »)")
        }
        verifier(RattrapageVue.puce("Paul envoie le devis jeudi.", largeur: 424) == "Paul envoie le devis jeudi.", "une puce courte reste entière")
        verifier(MesureIlot.lignes("Un mot", 13.5, .regular, largeur: 400) == 1 && MesureIlot.lignes(longue + " " + longue, 13.5, .regular, largeur: 400) >= 3, "mesure des lignes : 1 pour un texte court, 3 ou plus pour un très long")
        try? FileManager.default.removeItem(at: d)
    }

    /// Les voix des autres séparées après l'appel (« Personne 1, Personne 2… ») : le vrai contrôleur et la vraie chaîne d'après l'appel,
    /// avec une relecture, une séparation et une rédaction factices. Ni micro, ni son du Mac, ni réseau, ni modèle : les deux pistes
    /// sont des fichiers fabriqués dans un dossier à part.
    @MainActor
    static func voixSeparees(dossier: URL, verifier: @escaping (Bool, String) -> Void, attendre: (Double, () -> Bool) -> Void) {
        print("Réunions : les voix des autres séparées (séparation factice)")
        let d = dossier.appendingPathComponent("reunions-voix", isDirectory: true)
        try? FileManager.default.removeItem(at: d)
        let store = ReunionStore(dossier: d, lire: false)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        func reunion(_ n: Int, eux: [PassageParole] = [PassageParole(debut: 5, fin: 48)]) -> Reunion {
            var r = Reunion(debut: Date(timeIntervalSince1970: 1_800_100_000 + Double(n) * 3600), duree: 60, etat: .transcription, sonGarde: false)
            r.passagesParVoix = [.moi: [PassageParole(debut: 0, fin: 4)], .eux: eux]
            for l in [Locuteur.moi, .eux] {
                guard let w = EcrivainWAV(url: store.fichierSon(r, l)) else { verifier(false, "fichier son créé"); return r }
                w.ajouter([Int16](repeating: 100, count: 16_000 * 60)); w.fermer()
            }
            store.enregistrer(r)
            return r
        }
        // la relecture : « Moi » une phrase, « Eux » quatre phrases de 10 s (heures de la réunion : 5, 15, 25, 35 s)
        var rel = RelectureAudio()
        rel.transcrire = { lot, _, _ in
            if lot.locuteur == .moi { return [PhraseWhisper(debut: 0.3, fin: 3.5, texte: "On commence ?")] }
            let x = 5 - lot.debut   // le lot commence un peu avant 5 s (marge)
            return ["Bonjour à tous.", "Les machines arrivent mardi.", "D'accord, c'est noté.", "Je vous envoie le devis."].enumerated().map { i, t in
                PhraseWhisper(debut: x + Double(i) * 10 + 0.2, fin: x + Double(i) * 10 + 9.5, texte: t)
            }
        }
        let fichiersRecus = Verrouille<[URL]>([])
        let separee = SeparationVoixAudio { url, _, avance in
            _ = fichiersRecus.remplacer(fichiersRecus.valeur + [url])
            avance(.telechargement(0.5)); avance(.telechargement(1)); avance(.separation(0.5)); avance(.separation(1))
            return VoixSeparees(tours: [TourDeParole(voix: "S4", debut: 5, fin: 15), TourDeParole(voix: "S1", debut: 15, fin: 25),
                                        TourDeParole(voix: "S4", debut: 25, fin: 35), TourDeParole(voix: "S1", debut: 35, fin: 48)],
                                empreintes: ["S4": [0.1, 0.2], "S1": [0.3, 0.4]])
        }
        let lus = Verrouille<String>("")
        let rediger: ReunionController.RedigerNote = { segments, _, _, _ in
            _ = lus.remplacer(DecoupeReunion.texte(segments))
            return (NoteBrute(titre: "Devis", enBref: "Personne 2 envoie le devis.", sujets: [SujetReunion(titre: "Livraison", puces: [PuceReunion(texte: "Personne 1 annonce les machines mardi.")])]), [])
        }
        func controleur(_ s: SeparationVoixAudio?) -> ReunionController {
            let c = ReunionController(store: store)
            c.relecture = rel; c.rediger = rediger; c.separation = s
            return c
        }
        func finir(_ c: ReunionController, _ r: Reunion) {
            var fini = false
            Task { await c.finir(r, passages: r.passagesParVoix, direct: [], fichiers: [.moi: store.fichierSon(r, .moi), .eux: store.fichierSon(r, .eux)]); fini = true }
            attendre(10) { !fini }
            verifier(fini, "le traitement se termine")
        }

        // 1. deux voix : « Personne 1 », « Personne 2 », dans la note et la transcription
        let r1 = reunion(1)
        finir(controleur(separee), r1)
        guard var v1 = store.reunion(id: r1.id) else { verifier(false, "la réunion est rangée"); return }
        verifier(fichiersRecus.valeur == [store.fichierSon(r1, .eux)], "la séparation ne reçoit que la piste « Eux » (le son du Mac), jamais « Moi »")
        verifier(v1.orateursEntendus.map(\.nom) == ["Moi", "Personne 1", "Personne 2"], "les orateurs : Moi, Personne 1, Personne 2 (\(v1.orateursEntendus.map(\.nom)))")
        let eux = v1.segments.filter { $0.locuteur == .eux }
        verifier(eux.map(\.orateur) == ["p1", "p2", "p1", "p2"] && eux.map(\.texte).first == "Bonjour à tous.",
                 "chaque phrase relue à sa voix ; deux voix qui alternent ne sont pas recollées en un seul tour (\(eux.map { "\($0.orateur ?? "-") \($0.texte)" }))")
        verifier(lus.valeur.contains("Personne 1 : Bonjour à tous.") && lus.valeur.contains("Personne 2 : Les machines") && lus.valeur.contains("Moi : On commence"),
                 "la rédaction de la note lit « Personne 1 », « Personne 2 » et « Moi »")
        verifier(v1.orateurs?.map(\.empreinte) == [[0.1, 0.2], [0.3, 0.4]], "l'empreinte de chaque voix est gardée avec la réunion")
        verifier(v1.etat == .prete && v1.relue == true && !v1.avertissements.contains { $0.hasPrefix(ReunionController.avertissementVoix) }, "note prête, aucun avertissement sur les voix")
        store.attendreEcritures(); attendre(2) { store.sonPresent(r1, .eux) }
        verifier(!store.sonPresent(r1, .eux), "la séparation finie avant la note : le son peut partir comme avant")
        v1.renommer(orateur: "p2", en: "Claire"); store.enregistrer(v1)
        let w1 = store.reunion(id: r1.id)
        verifier(w1?.enBref == "Claire envoie le devis." && w1?.orateur(de: eux[1]).nom == "Claire" && w1?.orateur(de: eux[0]).nom == "Personne 1",
                 "« Personne 2 » renommée « Claire » : toute la note suit (\(w1?.enBref ?? "-"))")
        store.attendreEcritures()
        let md = (try? String(contentsOf: d.appendingPathComponent(ArchiveReunions.nomDeBase(r1) + ".md"), encoding: .utf8)) ?? ""
        verifier(md.contains("**Claire**") && md.contains("**Personne 1**") && !md.contains("**Personne 2**"), "le Markdown enregistré porte le nouveau nom")

        // 2. séparation impossible (pas de réseau pour le modèle) : repli « Eux », la note se fait quand même
        let r2 = reunion(2)
        finir(controleur(SeparationVoixAudio { _, _, _ in throw URLError(.notConnectedToInternet) }), r2)
        let v2 = store.reunion(id: r2.id)
        verifier(v2?.etat == .prete && v2?.orateursEntendus.map(\.nom) == ["Moi", "Eux"], "séparation impossible : « Moi / Eux », note prête (\(v2?.orateursEntendus.map(\.nom) ?? []))")
        verifier(v2?.avertissements.contains { $0.hasPrefix(ReunionController.avertissementVoix) } == true, "la note dit que les voix n'ont pas été séparées")

        // 3. rien du son du Mac (micro seul) : aucune séparation lancée
        _ = fichiersRecus.remplacer([])
        let r3 = reunion(3, eux: [])
        finir(controleur(separee), r3)
        verifier(fichiersRecus.valeur.isEmpty && store.reunion(id: r3.id)?.orateursEntendus.map(\.nom) == ["Moi"], "aucun passage « Eux » : la séparation n'est pas lancée")

        // 4. la progression (premier usage : le téléchargement du modèle se voit), et une seule voix : « Eux »
        let r4 = reunion(4)
        let avances = Verrouille<[(Double, String)]>([])
        let uneVoix = SeparationVoixAudio { _, _, avance in
            avance(.telechargement(0.3)); avance(.telechargement(1)); avance(.separation(1))
            return VoixSeparees(tours: [TourDeParole(voix: "S0", debut: 5, fin: 48)])
        }
        var prepare: Reunion?
        var fini = false
        Task {
            prepare = await ReunionController.preparer(r4, passages: r4.passagesParVoix, direct: [], fichiers: [.moi: store.fichierSon(r4, .moi), .eux: store.fichierSon(r4, .eux)],
                                                     relecture: rel, rediger: rediger, separation: uneVoix) { p, e in _ = avances.remplacer(avances.valeur + [(p, e)]) }
            fini = true
        }
        attendre(10) { !fini }
        let etapes = avances.valeur.map(\.1)
        verifier(etapes.contains(PreparationNote.telechargementVoix) && etapes.last == PreparationNote.redaction, "l'îlot montre « \(PreparationNote.telechargementVoix) » au premier usage, puis la rédaction")
        verifier(prepare?.orateursEntendus.map(\.nom) == ["Moi", "Eux"] && prepare?.orateurs == nil, "une seule voix trouvée : « Eux », comme avant")
        try? FileManager.default.removeItem(at: d)
    }

    /// Les bulles audio de la transcription (les « vocaux ») : lecture de l'extrait exact sur la bonne piste, enchaînement, vitesse,
    /// pause, clic dans l'onde, ondes du vrai son, extrait .m4a (nom, 0600, durée), glisser vers une app, toute la réunion mélangée,
    /// puis le son effacé (réglage de rétention) : bulles grises, extraits effacés. Un lecteur muet remplace AVAudioPlayer : aucun
    /// son ne sort ; les pistes sont des fichiers fabriqués dans un dossier à part (ni micro, ni son du Mac, ni réseau).
    @MainActor
    static func bullesAudio(dossier: URL, verifier: @escaping (Bool, String) -> Void, attendre: (Double, () -> Bool) -> Void) {
        print("Réunions : les bulles audio de la transcription (lecteur muet)")
        let d = dossier.appendingPathComponent("reunions-bulles", isDirectory: true)
        try? FileManager.default.removeItem(at: d)
        let store = ReunionStore(dossier: d, lire: false)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        var cal = Calendar(identifier: .gregorian); cal.timeZone = .current
        let debut = cal.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 14, minute: 2))!
        var r = Reunion(debut: debut, duree: 10, titre: "Point devis", etat: .prete, sonGarde: true)
        r.segments = [SegmentReunion(debut: 1, fin: 3, locuteur: .eux, texte: "Bonjour à tous.", orateur: "p1"),
                      SegmentReunion(debut: 3.5, fin: 5, locuteur: .moi, texte: "Salut.", orateur: nil),
                      SegmentReunion(debut: 6, fin: 8, locuteur: .eux, texte: "Je vous envoie le devis.", orateur: "p2")]
        r.orateurs = [OrateurReunion(id: "p1", nom: "Personne 1", piste: .eux), OrateurReunion(id: "p2", nom: "Personne 2", piste: .eux)]
        // le son : un bruit sur les passages de chaque piste, le silence ailleurs (10 s chacune)
        for l in [Locuteur.moi, .eux] {
            guard let w = EcrivainWAV(url: store.fichierSon(r, l)) else { verifier(false, "son fabriqué"); return }
            var son = [Int16](repeating: 0, count: 16_000 * 10)
            for s in r.segments where s.locuteur == l { for i in Int(s.debut * 16_000)..<Int(s.fin * 16_000) { son[i] = Int16(i % 7 == 0 ? 9_000 : -6_000) } }
            w.ajouter(son); w.fermer()
        }
        store.enregistrer(r)
        let m = ReunionsModele(store: store)
        let ouverts = Verrouille<[URL]>([])
        m.ouvrirLecteur = { url in _ = ouverts.remplacer(ouverts.valeur + [url]); return LecteurMuet() }

        // lecture : l'extrait exact, la bonne piste, puis l'enchaînement sur la piste « Moi »
        m.jouer(r, passage: 0)
        let e0 = ExtraitsReunion.extrait(r, passage: 0, dureeSon: 10)!
        verifier(m.ecoute == 0 && ouverts.valeur == [store.fichierSon(r, .eux)] && m.progression(0) < 0.1, "▶︎ : le passage de Personne 1 joue sur la piste « Eux », depuis son début")
        attendre(4) { m.ecoute == 0 }
        verifier(m.ecoute == 1 && ouverts.valeur.last == store.fichierSon(r, .moi), "fin de l'extrait (\(String(format: "%.2f", e0.duree)) s) : la lecture enchaîne sur « Moi », sur la piste du micro")
        // pause, reprise, vitesse
        m.basculerPause()
        let enPause = m.progression(1)
        attendre(0.4) { true }
        verifier(m.enPause && abs(m.progression(1) - enPause) < 0.001, "pause : la bulle ne bouge plus (\(String(format: "%.2f", enPause)))")
        m.ecouter(r, passage: 1)
        verifier(!m.enPause && m.ecoute == 1, "un clic sur le même passage : reprise")
        m.changerVitesse()
        verifier(m.vitesse == 1.5, "vitesse : ×1,5")
        m.changerVitesse(); verifier(m.vitesse == 2, "vitesse : ×2")
        // un clic dans l'onde d'un autre passage : il joue depuis cet endroit
        m.placer(r, passage: 2, fraction: 0.5)
        verifier(m.ecoute == 2 && abs(m.progression(2) - 0.5) < 0.05, "un clic au milieu de l'onde : la lecture part du milieu (\(String(format: "%.2f", m.progression(2))))")
        attendre(3) { m.ecoute != nil }
        verifier(m.ecoute == nil, "le dernier passage fini (à ×2) : la lecture s'arrête")
        m.changerVitesse(); verifier(m.vitesse == 1, "vitesse : retour à ×1")

        // les ondes : le vrai niveau du son de chaque passage
        m.chargerOndesMaintenant(r)
        verifier(m.ondes.count == 3 && m.ondes.values.allSatisfy { $0.count == ExtraitsReunion.barres && ($0.max() ?? 0) > 0.9 }, "une onde de 36 barres par passage, tirée du son")

        // l'extrait en .m4a
        do {
            let url = try store.fichierExtrait(r, passage: 2)
            let droits = (try? FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int) ?? 0
            let f = try AVAudioFile(forReading: url)
            let duree = Double(f.length) / f.fileFormat.sampleRate
            let e2 = ExtraitsReunion.extrait(r, passage: 2, dureeSon: 10)!
            verifier(url.lastPathComponent == "Réunion \u{2013} Personne 2 \u{2013} 14h02.m4a", "le fichier s'appelle « \(url.lastPathComponent) »")
            verifier(droits == 0o600 && url.path.hasPrefix(store.dossierExtraits.path), "extrait en 0600, rangé à côté des réunions (\(String(droits, radix: 8)))")
            verifier(f.fileFormat.settings[AVFormatIDKey] as? UInt32 == kAudioFormatMPEG4AAC && abs(duree - e2.duree) < 0.15,
                     "AAC, la durée de l'extrait (\(String(format: "%.2f", duree)) s pour \(String(format: "%.2f", e2.duree)) s)")
        } catch { verifier(false, "extrait .m4a fabriqué (\(error))") }
        let fourni = m.fournisseurGlisser(r, passage: 0)
        verifier(fourni.hasItemConformingToTypeIdentifier("public.file-url") || fourni.hasItemConformingToTypeIdentifier("public.mpeg-4-audio"),
                 "glisser la bulle : un fichier .m4a pour Finder, Mail, WhatsApp (\(fourni.registeredTypeIdentifiers))")

        // toute la réunion, les deux pistes mélangées
        let tout = d.appendingPathComponent("tout.m4a")
        do {
            var avances: [Double] = []
            try ExportAudio.reunion(moi: store.fichierSon(r, .moi), eux: store.fichierSon(r, .eux), vers: tout) { avances.append($0) }
            let f = try AVAudioFile(forReading: tout)
            let duree = Double(f.length) / f.fileFormat.sampleRate
            let droits = (try? FileManager.default.attributesOfItem(atPath: tout.path)[.posixPermissions] as? Int) ?? 0
            verifier(abs(duree - 10) < 0.2 && droits == 0o600 && avances.last == 1, "toute la réunion en un .m4a : \(String(format: "%.1f", duree)) s, 0600")
            let b = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length))!
            try f.read(into: b)
            func niveau(_ a: Double, _ z: Double) -> Float {
                let p = b.floatChannelData![0]; var m: Float = 0
                for i in Int(a * f.fileFormat.sampleRate)..<Int(z * f.fileFormat.sampleRate) { m = max(m, abs(p[i])) }
                return m
            }
            verifier(niveau(1.5, 2.5) > 0.1 && niveau(3.8, 4.7) > 0.1 && niveau(8.6, 9.6) < 0.02, "le mélange a la voix des autres ET la mienne, le silence reste silencieux")
        } catch { verifier(false, "toute la réunion exportée (\(error))") }
        let caches = ((try? FileManager.default.contentsOfDirectory(atPath: d.path)) ?? []).filter { $0.hasPrefix(".") && $0.hasSuffix(".m4a") }
        verifier(caches.isEmpty, "aucun fichier à moitié écrit ne reste (\(caches))")

        // le son effacé (rétention) : bulles grises, extraits effacés, rien ne joue
        store.effacerSon(r)
        store.attendreEcritures(); attendre(1) { store.sonPresent(r, .eux) }
        verifier(!m.sonDisponible(r) && !FileManager.default.fileExists(atPath: store.dossierExtraits(r).path), "son effacé : plus de son, et les extraits fabriqués partent avec lui")
        m.jouer(r, passage: 0)
        verifier(m.ecoute == nil && m.repere == 0, "son effacé : la bulle ne joue plus (« audio effacé »)")
        // au lancement, les extraits d'un glisser-déposer de la veille sont effacés
        try? FileManager.default.createDirectory(at: store.dossierExtraits(r), withIntermediateDirectories: true)
        _ = ReunionStore(dossier: d)
        verifier(!FileManager.default.fileExists(atPath: store.dossierExtraits.path), "au lancement : aucun extrait ne reste")
        try? FileManager.default.removeItem(at: d)
    }
}

/// Un lecteur muet pour l'essai : le temps avance comme une vraie lecture (vitesse comprise), aucun son ne sort.
final class LecteurMuet: LecteurSon {
    private var depart: Double?
    private var position: TimeInterval = 0
    private static func horloge() -> Double { ProcessInfo.processInfo.systemUptime }
    var rate: Float = 1 { willSet { if depart != nil { position = currentTime; depart = Self.horloge() } } }
    var currentTime: TimeInterval {
        get { depart.map { position + (Self.horloge() - $0) * Double(rate) } ?? position }
        set { position = newValue; if depart != nil { depart = Self.horloge() } }
    }
    var isPlaying: Bool { depart != nil }
    func play() -> Bool { if depart == nil { depart = Self.horloge() }; return true }
    func pause() { position = currentTime; depart = nil }
    func stop() { pause() }
}
