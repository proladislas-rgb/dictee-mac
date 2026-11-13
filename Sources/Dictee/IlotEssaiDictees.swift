import AppKit
import DicteeCore

extension IlotEssai {
    /// Un historique factice (celui de la maquette, et quelques jours de plus), daté depuis `maintenant` ; `courtes` : trois dictées
    /// d'aujourd'hui seulement (la liste ne défile pas). Jamais le vrai historique.
    static func dicteesFactices(courtes: Bool = false, maintenant t: Date) -> [EntreeHistorique] {
        let cal = Calendar.current
        let minuit = cal.startOfDay(for: t)
        func le(_ jours: Int, _ h: Int, _ mn: Int) -> Date {
            let jour = cal.date(byAdding: .day, value: -jours, to: minuit) ?? minuit
            // aujourd'hui, jamais dans le futur : au plus tard une minute avant maintenant
            let d = cal.date(bySettingHour: h, minute: mn, second: 0, of: jour) ?? jour
            return jours == 0 ? min(d, t.addingTimeInterval(-60 * Double(14 - h))) : d
        }
        let toutes: [(Int, Int, Int, String, String)] = [
            (0, 14, 43, "Mail", "OK pour le devis de la cuisine : 4 200 € posé, plan de travail en chêne compris. Je te l\u{2019}envoie ce soir avec les plans et les photos du chantier."),
            (0, 14, 12, "Messages", "Je serai en retard de dix minutes, commencez sans moi."),
            (0, 13, 50, "Terminal", "Ajoute une section installation dans le README avec les trois commandes."),
            (0, 11, 27, "Mail", "Bonjour Madame Martin, je vous confirme le rendez-vous de mardi à 10 h."),
            (1, 18, 32, "Messages", "Tu peux me renvoyer le DÉVIS signé pour la salle de bain ?"),
            (1, 17, 5, "Notes", "Liste de courses : pain, œufs, café, lessive."),
            (1, 9, 40, "Slack", "On décale le point d\u{2019}équipe à jeudi, même heure."),
            (2, 16, 20, "Mail", "Merci pour l\u{2019}envoi, je regarde ça demain matin."),
            (2, 10, 2, "Notes", "Idées pour le week-end : marché, vélo le long du canal."),
            (2, 8, 55, "Messages", "Je prends le pain en rentrant."),
        ]
        let l = courtes ? Array(toutes.prefix(3)) : toutes
        return l.map { EntreeHistorique(date: le($0.0, $0.1, $0.2), appId: nil, appNom: $0.3, texte: $0.4) }
    }

    /// La carte Dictées (maquette ilot-centre.html, étapes 2, 10 à 12) : le bouton « Dictées » au pied de la lecture et la pilule du
    /// Centre, la recherche (le clavier pris SEULEMENT pendant qu'on tape, et rendu dès qu'on quitte la carte), les mots surlignés, copier,
    /// coller, déplier, la liste qui défile dans la carte, « Aucun résultat », les liens vers la fenêtre, une dictée qui arrive. De VRAIS
    /// clics, de vraies touches et de vrais défilements remis à la fenêtre invisible (jamais rendue clé) ; l'historique est factice et en
    /// mémoire, le presse-papiers aussi ; rien n'est collé dans une app, rien n'est écrit sur le disque.
    @MainActor
    static func dictees(_ c: IlotControleur, verifier: (Bool, String) -> Void, attendre: (Double, () -> Bool) -> Void,
                        pressePapiers: () -> [String], fenetres: () -> [Onglet]) {
        let m = c.moteur, g = m.geometrie, d = m.dictees
        let hc = Double(m.demiCamera), barre = Double(g.hauteur)
        func pause(_ s: Double) { attendre(s) { true } }
        func clic(_ p: CGPoint, _ apres: Double = 0.5) {
            c.panneau.envoyerSouris(.leftMouseDown, en: p); pause(0.06); c.panneau.envoyerSouris(.leftMouseUp, en: p); pause(apres)
        }
        func refermer() { c.panneau.simulerPointeur(forme: false); m.fermer(); pause(0.8) }
        func poseeSurLaCible() { attendre(1.5) { !m.geo.allSatisfy(\.fini) } }

        print("Les Dictées dans l'îlot")
        let factices = dicteesFactices(maintenant: c.maintenant())
        let memoire = HistoriqueStore(enMemoire: factices)
        d.source = { memoire }
        var colles: [String] = []
        let collerAvant = c.surColler
        c.surColler = { colles.append($0) }
        refermer()

        // --- une vidéo joue : son déplié porte « Centre » ET « Dictées » (maquette, étape 2)
        c.lecture.modele.morceau = MorceauEnCours(titre: "Je détestais la mode des iPods", app: "essai.lecture", joue: true, duree: 774, position: 202)
        c.lecture.surIlot(true); pause(0.9)
        c.panneau.simulerPointeur(forme: true); pause(1.0)
        verifier(m.courante == .lectureEtendu && m.visible(ExtraIlot.pied) && PiedCarte.dicteesTient(m.grille, .lectureEtendu),
                 "lecture dépliée : « Centre » et « Dictées » au pied (\(Int(PiedCarte.largeurBouton + 10 + PiedCarte.largeurDictees)) pt sur \(Int(PiedCarte.cadre(m.grille, .lectureEtendu).width)))")
        verifier(m.cartes == [.lectureEtendu, .centre, .outils, .accueil, .dictees], "cinq cartes : la vidéo, le Centre, les Outils, l'accueil, les Dictées en dernier (cinq points)")
        clic(PiedCarte.pointDictees(m.grille), 0.9)
        verifier(m.courante == .dictees && m.epingle, "vrai clic sur « Dictées » sous la vidéo : la carte Dictées, qui reste ouverte (\(m.courante))")
        poseeSurLaCible()
        let hMax = barre + CarteDictees.profondeurMax
        verifier(d.defile && abs(m.geo[2].x - hMax) < 0.5, "dix dictées : la carte à son plus haut (\(Int(m.geo[2].x)) pt, attendu \(Int(hMax))), la liste défile dedans")
        verifier(m.trace.bande <= hc + GeoIlot.aileMax + 0.01, "Dictées : \(String(format: "%.1f", m.trace.bande - hc)) pt dans la barre de chaque côté (≤ 66)")
        if let f = c.panneau.cadre { verifier(Double(f.height) >= m.trace.hauteur && Double(f.width) >= 2 * m.trace.corps, "la fenêtre couvre la carte") }
        verifier(m.visible(ExtraIlot.points) && !m.visible(ExtraIlot.pied), "les points de page à droite, pas de pied « Centre » sur les Dictées")
        attendre(1.5) { m.boucleActive }
        verifier(!m.boucleActive, "Dictées posées : aucune boucle d'animation (bouge encore : \(m.ceQuiBouge))")
        verifier(!c.panneau.clavierPris && !c.panneau.estCle && !d.rechercheActive, "arrivée sur les Dictées : le clavier reste à l'app au premier plan")
        // ce qui doit tenir : le pied, l'en-tête, les lignes
        let pied = PlanDictees.cadrePied(m.grille), ent = PlanDictees.cadreEntete(m.grille)
        verifier(PlanDictees.largeurPied <= pied.width, "pied « Journée · Réunions · Mots · Réglages … ouvrent la fenêtre » : \(Int(PlanDictees.largeurPied)) pt mesurés, tiennent dans \(Int(pied.width))")
        verifier(PlanDictees.largeurRetour + 8 + 140 <= ent.width, "en-tête : « ‹ Centre » (\(Int(PlanDictees.largeurRetour)) pt) et au moins 140 pt de champ")
        verifier(PlanDictees.largeurTexte(demiCamera: m.demiCamera) >= 220, "une ligne dépliée garde \(Int(PlanDictees.largeurTexte(demiCamera: m.demiCamera))) pt de texte à côté de « Coller » et du chevron")

        // --- « ‹ Centre », puis la pilule « Dictées » du Centre
        clic(PlanDictees.pointRetour(m.grille), 0.9)
        verifier(m.courante == .centre, "vrai clic sur « ‹ Centre » : le Centre (\(m.courante))")
        let ec = PlanCentre.cadreEntete(m.grille)
        let pDictees = EnteteCentre.centrePilule(.dictees, m, entete: ec)
        clic(pDictees, 0.9)
        verifier(m.courante == .dictees, "vrai clic sur la pilule « Dictées » du Centre : les Dictées (\(m.courante))")
        poseeSurLaCible()

        // --- la liste défile dans la carte (vrais défilements de deux doigts, inertie comprise) ; ailleurs, on change de carte. Les Dictées
        // sont la dernière carte : au bout de la liste, on reste sur elles ; vers le bas sur le pied, rien (on ne boucle pas)
        let liste = PlanDictees.cadreListe(m.grille)
        let surListe = CGPoint(x: liste.midX - 40, y: liste.midY)
        c.panneau.envoyerDefilement(dy: -12, en: surListe, phase: 1); pause(0.02)
        c.panneau.envoyerDefilement(dy: -18, en: surListe, phase: 2); pause(0.02)
        c.panneau.envoyerDefilement(dy: 0, en: surListe, phase: 4); pause(0.02)
        c.panneau.envoyerDefilement(dy: -10, en: surListe, phase: 0, inertie: 1); pause(0.02)
        c.panneau.envoyerDefilement(dy: 0, en: surListe, phase: 0, inertie: 3); pause(0.3)
        verifier(m.courante == .dictees && abs(d.decalage - 40) < 0.5, "deux doigts sur la liste : elle défile de 40 pt (inertie comprise), la carte reste (\(Int(d.decalage)) pt, \(m.courante))")
        c.panneau.envoyerDefilement(dy: -900, en: surListe, phase: 1); pause(0.02); c.panneau.envoyerDefilement(dy: 0, en: surListe, phase: 4); pause(0.3)
        let fin = d.miseEnPage().hauteur - Double(liste.height)
        verifier(abs(d.decalage - fin) < 0.5 && m.courante == .dictees, "jusqu'au bout : la liste s'arrête sur sa dernière ligne (\(Int(d.decalage)) pt cachés, attendu \(Int(fin)))")
        c.panneau.envoyerDefilement(dy: -6, en: surListe, phase: 1); pause(0.02); c.panneau.envoyerDefilement(dy: -40, en: surListe, phase: 2); pause(0.02)
        c.panneau.envoyerDefilement(dy: 0, en: surListe, phase: 4); pause(0.7)
        verifier(abs(d.decalage - fin) < 0.5 && m.courante == .dictees, "un autre geste au bout de la liste : elle reste sur sa dernière ligne, jamais une autre carte (\(m.courante))")
        let derniere = factices.last!.id
        verifier(PlanDictees.cadreLigne(derniere, m).map { $0.maxY <= liste.maxY + 0.5 } == true, "la dernière dictée est entière dans la carte")
        c.panneau.envoyerDefilement(dy: 2000, en: surListe, phase: 1); pause(0.02); c.panneau.envoyerDefilement(dy: 0, en: surListe, phase: 4); pause(0.3)
        verifier(d.decalage == 0 && m.courante == .dictees, "et revient en haut")
        let surPied = CGPoint(x: pied.midX + 60, y: pied.midY)
        c.panneau.envoyerDefilement(dy: -6, en: surPied, phase: 1); pause(0.02); c.panneau.envoyerDefilement(dy: -12, en: surPied, phase: 2); pause(0.02)
        c.panneau.envoyerDefilement(dy: 0, en: surPied, phase: 4); pause(0.7)
        verifier(m.courante == .dictees && d.decalage == 0, "le même geste sur le pied de la carte : au bout de la pile, on ne boucle pas (\(m.courante))")
        c.panneau.envoyerDefilement(dy: 6, en: surPied, phase: 1); pause(0.02); c.panneau.envoyerDefilement(dy: 12, en: surPied, phase: 2); pause(0.02)
        c.panneau.envoyerDefilement(dy: 0, en: surPied, phase: 4); pause(0.7)
        verifier(m.courante == .accueil, "le geste inverse sur le pied : la carte d'avant, l'accueil (\(m.courante))")
        m.allerA(.dictees); pause(0.8)

        // --- un geste parti de l'accueil (la carte juste avant), le pointeur au milieu (là où sera la liste) : la carte passe aux Dictées en
        // chemin ; ni la suite du geste ni son inertie ne font défiler la liste (on arrive en haut, « Aujourd'hui » et les dernières dictées)
        c.panneau.envoyerDefilement(dy: -40, en: surListe, phase: 1); pause(0.02); c.panneau.envoyerDefilement(dy: 0, en: surListe, phase: 4); pause(0.3)
        verifier(abs(d.decalage - 40) < 0.5, "la liste défilée de 40 pt avant de partir (\(Int(d.decalage)) pt)")
        c.panneau.envoyerDefilement(dy: 6, en: surPied, phase: 1); pause(0.02); c.panneau.envoyerDefilement(dy: 12, en: surPied, phase: 2); pause(0.02)
        c.panneau.envoyerDefilement(dy: 0, en: surPied, phase: 4); pause(0.7)
        verifier(m.courante == .accueil, "deux doigts vers le haut sur le pied : l'accueil (\(m.courante))")
        c.panneau.envoyerDefilement(dy: -6, en: surListe, phase: 1); pause(0.02)
        c.panneau.envoyerDefilement(dy: -12, en: surListe, phase: 2); pause(0.02)
        let passee = m.courante == .dictees
        for _ in 0 ..< 4 { c.panneau.envoyerDefilement(dy: -30, en: surListe, phase: 2); pause(0.02) }
        c.panneau.envoyerDefilement(dy: 0, en: surListe, phase: 4); pause(0.02)
        c.panneau.envoyerDefilement(dy: -40, en: surListe, phase: 0, inertie: 1); pause(0.02)
        for _ in 0 ..< 6 { c.panneau.envoyerDefilement(dy: -25, en: surListe, phase: 0, inertie: 2); pause(0.02) }
        c.panneau.envoyerDefilement(dy: 0, en: surListe, phase: 0, inertie: 3); pause(0.8)
        verifier(passee && m.courante == .dictees && d.decalage == 0,
                 "deux doigts depuis l'accueil (328 pt de geste et d'inertie) : les Dictées, en haut de la liste (\(Int(d.decalage)) pt défilés, \(m.courante))")
        c.panneau.envoyerDefilement(dy: -20, en: surListe, phase: 1); pause(0.02); c.panneau.envoyerDefilement(dy: 0, en: surListe, phase: 4); pause(0.3)
        verifier(abs(d.decalage - 20) < 0.5 && m.courante == .dictees, "le geste suivant, sur la liste : elle défile (\(Int(d.decalage)) pt)")
        clic(PlanDictees.pointRetour(m.grille), 0.9)
        clic(pDictees, 0.9)
        verifier(m.courante == .dictees && d.decalage == 0, "retour aux Dictées par la pilule du Centre : la liste repart du haut (\(Int(d.decalage)) pt)")

        // --- copier : un clic sur la ligne ; « Copié » dans la ligne ; la carte reste
        let d1 = factices[0]
        guard let l1 = PlanDictees.cadreLigne(d1.id, m) else { verifier(false, "la première dictée est à l'écran"); return }
        clic(CGPoint(x: l1.minX + 8 + 36 + 8 + 80, y: l1.midY), 0.3)
        verifier(pressePapiers().last == d1.texte && d.copiee == d1.id && m.courante == .dictees,
                 "vrai clic sur une dictée : copiée (presse-papiers factice), « Copié » dans la ligne, la carte reste ouverte")
        attendre(2.0) { d.copiee != nil }
        verifier(d.copiee == nil, "« Copié » s'en va de lui-même (un seul réveil)")

        // --- déplier (le chevron, au survol) : la carte grandit d'autant, ou la liste
        // la souris passe sur la deuxième dictée, jusqu'à son chevron (il paraît au survol), puis clique : comme une vraie main. (Le
        // survol posé à la main ne tenait pas : la liste redessinée relit la souris fabriquée, restée sur la première dictée.)
        let pc = PlanDictees.pointChevron(factices[1].id, m)
        if let p = pc { c.panneau.envoyerMouvement(en: p) }
        pause(0.3)
        let survolReel = d.survol == factices[1].id
        if let p = pc { clic(p, 0.3) }
        verifier(d.deplie == factices[1].id, "vrai survol puis vrai clic sur le chevron : la dictée se déplie (texte entier) [survol \(survolReel ? "par la souris" : "absent"), \(m.courante.rawValue)]")
        let hDep = d.miseEnPage().elements.first { $0.id == factices[1].id.uuidString }?.h ?? 0
        verifier(hDep >= CarteDictees.ligneDepliee(lignesDeTexte: 1), "ligne dépliée : \(Int(hDep)) pt (une ligne de texte de plus au moins)")
        d.deplie = nil; d.survol = nil; pause(0.4)

        // --- une longue dictée dépliée, plus haute que la liste : elle ne tient jamais entière, elle prend les clics sur sa partie visible
        // (le chevron, son texte), jamais ceux de l'en-tête quand elle passe dessous
        let longue = EntreeHistorique(date: c.maintenant(), appNom: "Notes", texte: String(repeating: "Compte rendu du chantier de la rue des Lilas : la dalle est coulée, les menuiseries arrivent lundi, il reste la peinture du couloir et les prises de la cuisine. ", count: 4))
        memoire.ajouter(longue); pause(0.4)
        d.survol = longue.id; pause(0.2)
        if let p = PlanDictees.pointChevron(longue.id, m) { clic(p, 0.4) }
        let hLongue = d.miseEnPage().elements.first { $0.id == longue.id.uuidString }?.h ?? 0
        verifier(d.deplie == longue.id && hLongue > Double(liste.height),
                 "vrai clic sur le chevron d'une dictée de \(longue.texte.count) caractères : dépliée, \(Int(hLongue)) pt, plus haute que la liste (\(Int(liste.height)))")
        clic(CGPoint(x: liste.minX + 8 + 36 + 8 + 80, y: liste.midY), 0.3)
        verifier(pressePapiers().last == longue.texte && d.copiee == longue.id, "vrai clic sur son texte, au milieu de la liste : copiée")
        // « Copié » prend la place de « Coller » (à sa largeur) : le texte garde sa place, le chevron la sienne
        verifier(PlanDictees.largeurCopie + 4 <= PlanDictees.largeurColler,
                 "dépliée : « ✓ Copié » (\(Int(PlanDictees.largeurCopie)) pt mesurés) tient à la place de « Coller » (\(Int(PlanDictees.largeurColler)) pt)")
        if let p = PlanDictees.pointChevron(longue.id, m) { clic(p, 0.4) }
        verifier(d.deplie == nil && d.copiee == longue.id, "vrai clic sur son chevron « Réduire », « Copié » encore affiché : repliée")
        if let p = PlanDictees.pointChevron(longue.id, m) { clic(p, 0.4) }
        // défilée de 50 pt : son haut et son chevron passent sous l'en-tête ; un clic là va au champ « Rechercher »
        c.panneau.envoyerDefilement(dy: -50, en: surListe, phase: 1); pause(0.02); c.panneau.envoyerDefilement(dy: 0, en: surListe, phase: 4); pause(0.3)
        let sousEntete = PlanDictees.pointChevron(longue.id, m)
        verifier(d.deplie == longue.id && abs(d.decalage - 50) < 0.5 && sousEntete.map { PlanDictees.cadreEntete(m.grille).contains($0) } == true,
                 "dépliée de nouveau, défilée de 50 pt : son chevron est caché sous l'en-tête")
        if let p = sousEntete { clic(p, 0.4) }
        verifier(d.deplie == longue.id && d.rechercheActive, "vrai clic là : le champ « Rechercher » le reçoit, pas le chevron caché (dépliée \(d.deplie == longue.id))")
        attendre(1.0) { !c.panneau.champAuPremierPlan }
        c.panneau.envoyerTouche(code: 53, caractere: "\u{1b}"); pause(0.3)
        verifier(!d.rechercheActive && !c.panneau.clavierPris, "Échap : le clavier est rendu")
        attendre(2.0) { d.copiee != nil }
        clic(CGPoint(x: liste.minX + 8 + 36 + 8 + 80, y: liste.maxY - 10), 0.3)
        verifier(d.copiee == longue.id, "défilée : un clic en bas de la liste, sur elle, la copie encore")
        memoire.supprimer(id: longue.id); d.deplie = nil; d.survol = nil; d.decalage = 0; pause(0.5)

        // --- chercher : un clic dans le champ prend le clavier (en essai : simulé, la fenêtre n'est jamais rendue clé) ; de vraies touches
        clic(PlanDictees.pointChamp(m.grille), 0.4)
        verifier(d.rechercheActive && c.panneau.clavierPris && !c.panneau.estCle, "vrai clic dans « Rechercher » : le champ prend le clavier (essai : jamais la vraie fenêtre clé)")
        attendre(1.0) { !c.panneau.champAuPremierPlan }
        verifier(c.panneau.champAuPremierPlan, "le vrai champ de texte est posé, premier répondant de la fenêtre")
        c.panneau.envoyerTouches("dévis"); pause(0.5)
        verifier(d.requete == "dévis", "de vraies touches remises à la fenêtre : « dévis » est tapé (\(d.requete))")
        let trouvees = d.miseEnPage().affichees
        verifier(trouvees.count == 2 && trouvees.allSatisfy { Historique.plier($0.texte).contains("devis") },
                 "recherche sans accents ni majuscules : « dévis » trouve « devis » et « DÉVIS » (\(trouvees.count) dictées)")
        verifier(Surlignage.plages(trouvees[1].texte, requete: d.requete).count == 1, "le mot est surligné dans « DÉVIS » aussi")
        poseeSurLaCible()
        let h2 = barre + CarteDictees.profondeur(liste: CarteDictees.hauteurListe(lignesParJour: [1, 1]))
        verifier(abs(m.geo[2].x - h2) < 0.5, "l'îlot se resserre autour des deux dictées (\(Int(m.geo[2].x)) pt, attendu \(Int(h2)))")
        // Échap : efface la recherche, puis rend le clavier
        c.panneau.envoyerTouche(code: 53, caractere: "\u{1b}"); pause(0.3)
        verifier(d.requete.isEmpty && d.rechercheActive, "Échap : la recherche s'efface, le champ garde le clavier")
        c.panneau.envoyerTouche(code: 53, caractere: "\u{1b}"); pause(0.3)
        verifier(!d.rechercheActive && !c.panneau.clavierPris && m.courante == .dictees, "Échap encore : le clavier est rendu, la carte reste")
        // « Aucun résultat » : la carte la plus courte (~172 pt)
        d.requete = "zzzz"; poseeSurLaCible()
        let hRien = barre + CarteDictees.profondeur(liste: CarteDictees.rien)
        verifier(d.miseEnPage().affichees.isEmpty && abs(m.geo[2].x - hRien) < 0.5, "« Aucun résultat » : \(Int(m.geo[2].x)) pt de haut")
        d.requete = ""; poseeSurLaCible()

        // --- quitter la carte rend le clavier, tout de suite (« ‹ Centre », un point de page, une dictée qui commence)
        clic(PlanDictees.pointChamp(m.grille), 0.4)
        verifier(c.panneau.clavierPris, "le champ a de nouveau le clavier")
        clic(PlanDictees.pointRetour(m.grille), 0.6)
        verifier(!d.rechercheActive && !c.panneau.clavierPris && m.courante == .centre, "« ‹ Centre » : le clavier est rendu à l'app d'où l'on vient")
        m.allerA(.dictees); pause(0.8)
        clic(PlanDictees.pointChamp(m.grille), 0.4)
        verifier(c.panneau.clavierPris && m.courante == .dictees, "retour aux Dictées, clic dans le champ : il a le clavier (\(m.courante))")
        var occ = OccupationEncoche(); c.occupation = { occ }
        occ.dictee = true; c.occupationChangee(); pause(0.3)
        verifier(!d.rechercheActive && !c.panneau.clavierPris && m.cache,
                 "une dictée commence pendant la recherche : l'îlot s'efface et rend le clavier (le texte ira dans l'app) (recherche \(d.rechercheActive), clavier \(c.panneau.clavierPris), effacé \(m.cache))")
        occ.dictee = false; c.occupationChangee(); c.occupation = { OccupationEncoche() }; pause(0.8)

        // --- une dictée arrive pendant que la carte est ouverte : elle paraît en tête
        c.panneau.simulerPointeur(forme: true); pause(1.0)
        m.allerA(.dictees); pause(0.8)
        let nouvelle = EntreeHistorique(date: c.maintenant(), appNom: "Notes", texte: "Rappelle-moi le devis du plombier.")
        memoire.ajouter(nouvelle); pause(0.4)
        verifier(d.miseEnPage().affichees.first?.id == nouvelle.id && m.courante == .dictees, "une nouvelle dictée paraît en tête de la liste (en mémoire, rien d'écrit)")
        // un bandeau pendant que les Dictées sont ouvertes : il attend qu'elles se rangent
        m.annoncer(bandeau: BandeauIlot(vue: .appareil, jusqua: c.maintenant().addingTimeInterval(3.5), ligne1: "AirPods Pro", ligne2: "",
                                        appareil: AppareilIlot(nom: "AirPods Pro", genre: .ecouteurs, gauche: 80, droit: 78, etui: 45)))
        pause(0.4)
        verifier(m.courante == .dictees && m.bandeau == nil, "« AirPods connectés » pendant une recherche : les Dictées restent, le bandeau attend")

        // --- « Coller » au survol : dans l'app d'où l'on vient (capturé), l'îlot se range
        d.survol = nouvelle.id; pause(0.2)
        if let p = PlanDictees.pointColler(nouvelle.id, m) { clic(p, 0.5) }
        verifier(colles.last == nouvelle.texte && m.courante != .dictees, "vrai clic sur « Coller » : la dictée part vers l'app d'où l'on vient (capturé), l'îlot se range")
        attendre(5.0) { m.bandeau != nil || m.courante == .appareil }; c.panneau.simulerPointeur(forme: false); pause(1.0)

        // --- les liens du pied : la fenêtre principale sur l'onglet
        c.panneau.simulerPointeur(forme: true); pause(1.0)
        m.allerA(.dictees); pause(0.8)
        clic(PlanDictees.pointLien(.reglages, m.grille), 0.5)
        verifier(fenetres().last == .reglages && m.courante != .dictees, "vrai clic sur « Réglages » : la fenêtre de Voxile sur l'onglet Réglages, l'îlot se range")
        refermer()
        c.panneau.simulerPointeur(forme: true); pause(1.0)
        m.allerA(.dictees); pause(0.8)
        clic(PlanDictees.pointLien(.journee, m.grille), 0.5)
        verifier(fenetres().last == .journee, "« Journée » : l'onglet Journée")
        refermer()
        verifier(d.requete.isEmpty && d.decalage == 0, "l'îlot rangé : la carte repart de zéro à la prochaine ouverture")

        // --- « Réduire les animations » : la forme saute à sa place
        m.reduire = true
        c.panneau.simulerPointeur(forme: true); pause(1.0)
        m.allerA(.dictees); pause(0.05)
        verifier(m.geo.allSatisfy(\.fini) && m.courante == .dictees, "Réduire les animations : la carte Dictées est posée tout de suite")
        m.reduire = false
        refermer()

        c.lecture.modele.morceau = nil; c.lecture.surIlot(false); pause(0.8)
        c.surColler = collerAvant
        d.source = { HistoriqueStore(enMemoire: IlotEssai.dicteesFactices(courtes: true, maintenant: c.maintenant())) }
    }
}
