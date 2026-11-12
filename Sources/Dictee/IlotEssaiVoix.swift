import AppKit
import DicteeCore

extension IlotEssai {
    /// La voix d'un rappel ou d'une note (maquette ilot-voix-rappel.html), de bout en bout et avec de VRAIS clics : l'îlot prend la dictée
    /// quand le texte en direct est pour Lucarne (jamais avant, jamais une phrase sur Lucarne), l'onde suit le niveau, « Rappel… » arrive,
    /// les annonces attendent, puis la carte de fin : rien n'est envoyé sans clic, « Envoyer dans Rappels » (la fenêtre de macOS simulée,
    /// une fois), le suivant part seul, « Annuler », la note (« Envoyer dans Notes », « Copier »), les refus (le bon volet des Réglages),
    /// la fin sans commande, l'annulation, une autre dictée qui finit. Jamais EventKit, jamais l'app Notes, jamais le micro.
    @MainActor
    static func voix(_ c: IlotControleur, verifier: (Bool, String) -> Void, attendre: (Double, () -> Bool) -> Void,
                     pressePapiers: () -> [String]) {
        let m = c.moteur
        // les volets des Réglages ouverts : capturés ici (une section d'avant a pu remplacer `ouvrir`), jamais le vrai système
        var ouverts: [URL] = []
        let ouvrirAvant = c.ouvrir
        c.ouvrir = { ouverts.append($0) }
        defer { c.ouvrir = ouvrirAvant }
        func liens() -> [URL] { ouverts }
        func pause(_ s: Double) { attendre(s) { true } }
        func clic(_ r: CGRect, _ apres: Double = 0.6) {
            let p = CGPoint(x: r.midX, y: r.midY)
            c.panneau.envoyerSouris(.leftMouseDown, en: p); pause(0.06); c.panneau.envoyerSouris(.leftMouseUp, en: p); pause(apres)
            c.panneau.simulerPointeur(forme: false)
        }
        print("— la voix : l'onde pendant la dictée, la carte de fin (Rappels, Notes)")
        reglagesLucarneDEssai(c)
        let faux = RappelsAppleFactice(); c.rappelsApple = faux
        EssaiLucarne.choix = nil; EssaiLucarne.refusDit = false; c.questionRappelsPosee = false
        var notesEnvoyees: [String] = []
        var notesAccepte = true
        c.envoyerNoteVersNotes = { html, fini in
            notesEnvoyees.append(html); let ok = notesAccepte
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { fini(ok) }
        }
        // ce que fait le contrôleur de la dictée : fn appuyée (l'encoche s'ouvre), le texte en direct (l'îlot prend la dictée : l'encoche se
        // range), fn relâchée, la commande lue sur le texte de Groq, puis la fin de la dictée
        var occ = OccupationEncoche(); c.occupation = { occ }
        var session = 900
        func appuyer() { session += 1; occ.dictee = true; c.dicteeChange(enCours: true); c.occupationChangee(); pause(0.3) }
        func direct(_ texte: String) -> Bool {
            let pris = c.voixEnDirect(session: session, texte: texte)
            if pris { occ.dictee = false }
            pause(0.4)
            return pris
        }
        func relacher() { occ.dictee = false; c.dicteeChange(enCours: false); c.occupationChangee(); pause(0.3) }
        func ecrire(_ texte: String) -> Bool {
            let pris = c.intercepterLucarne(texte)
            c.finDeVoix(session: session); c.occupationChangee(); pause(1.0)
            return pris
        }
        let barre = Double(m.geometrie.hauteur)
        for r in c.rappels.rappels { c.agir(.rappelAnnuler(r.id)) }
        m.quitterBandeau(); m.fermer(); pause(0.8)

        // --- une dictée normale, une phrase SUR Lucarne : l'encoche de la dictée reste, l'îlot ne prend rien
        appuyer()
        verifier(!direct("Bonjour Paul, je t'envoie le devis demain") && !direct("Lucarne est prête, je te l'envoie demain") && !direct("Lucarne")
                 && m.cache && m.courante == .repos && !m.voix.retient,
                 "une dictée normale, « Lucarne est prête… », « Lucarne » seul : l'encoche de la dictée reste, l'îlot ne prend rien (\(m.courante))")
        relacher(); c.occupationChangee(); pause(0.4)

        // --- « Lucarne, rappelle-moi… » : l'îlot prend la dictée, l'onde, « Rappel… »
        appuyer()
        verifier(direct("Lucarne, rappelle-moi"), "« Lucarne, rappelle-moi » en direct : l'îlot prend la dictée")
        attendre(1.0) { m.courante != .voixEcoute }
        pause(0.6)
        verifier(!m.cache && m.courante == .voixEcoute && m.voix.phase == .ecoute && m.voix.genre == .rappel && c.panneau.estVisible,
                 "l'encoche rangée, l'îlot est là : l'onde et « Rappel… » (\(m.courante), effacé \(m.cache))")
        verifier(abs(m.geo[2].x - (barre + MesuresVoix.profondeurOnde + MesuresVoix.ligneLibelle)) < 0.6,
                 "l'îlot a grandi d'une ligne pour le libellé (\(Int(m.geo[2].x - barre)) pt sous la barre, 72 attendus)")
        verifier(m.trace.bande <= Double(m.demiCamera) + GeoIlot.aileMax + 0.01, "l'écoute : ≤ 66 pt dans la barre de chaque côté de la caméra")
        // le niveau du micro fait vivre l'onde (le milieu d'abord) ; un niveau d'une autre dictée n'existe pas : seul celui-ci arrive
        for _ in 0..<12 { c.niveauDeVoix(0.7); pause(0.05) }
        let t = EcouteVoix.horloge()
        verifier(m.voix.onde.hauteur(15, a: t) > 0.3 && m.voix.onde.hauteur(15, a: t) > m.voix.onde.hauteur(0, a: t),
                 "le niveau du micro fait monter l'onde, plus haut au milieu (\(String(format: "%.2f", m.voix.onde.hauteur(15, a: t))))")
        // une annonce pendant qu'on parle : elle attend (aucun son, rien ne recouvre l'onde)
        c.appareilConnecte(AppareilIlot(nom: "AirPods Pro", genre: .ecouteurs, gauche: 80, droit: 78, etui: 45)); pause(0.3)
        verifier(m.courante == .voixEcoute && m.bandeau?.vue == .voixEcoute, "des écouteurs se connectent pendant qu'on parle : l'annonce attend (\(m.courante))")
        // une fin qui vient d'une AUTRE dictée (plus ancienne) ne touche à rien
        c.finDeVoix(session: session - 1); pause(0.2)
        verifier(m.courante == .voixEcoute && m.voix.retient, "la fin d'une autre dictée ne range pas l'onde")
        relacher()
        verifier(m.voix.phase == .attente && m.courante == .voixEcoute, "fn relâchée : l'onde se calme, l'îlot attend le texte")

        // --- la carte du rappel : rien n'est envoyé sans clic
        let cal = Calendar.current
        let demain13 = cal.date(bySettingHour: 13, minute: 0, second: 0, of: MomentDicte.demain(c.maintenant()))!
        let jourDit = ListeRappels.jour(de: demain13, maintenant: c.maintenant())
        verifier(ecrire("Lucarne, rappelle-moi demain à 13 h pour la livraison."), "la commande : un rappel, rien n'est collé")
        let r1 = c.rappels.rappels.last
        verifier(r1?.echeance == demain13 && m.courante == .voixCarte && m.voix.carte?.titre == "Livraison" && m.voix.carte?.quand == jourDit + " \u{00B7} 13:00"
                 && m.voix.carte?.resume == "Rappelle-moi demain à 13 h pour la livraison.",
                 "la carte : « Livraison », « \(jourDit) · 13:00 », la phrase entendue (\(m.courante), \(m.voix.carte?.titre ?? "-"))")
        verifier(m.voix.phase == .repos && m.voix.carteAffichee && m.envoiVoix == .aEnvoyer && faux.demandes == 0 && faux.crees.isEmpty,
                 "rien n'est envoyé dans l'app Rappels sans clic, aucune fenêtre de macOS : « Envoyer dans Rappels »")
        verifier(abs(m.geo[2].cibleFinale - (barre + MesuresVoix.profondeurCarte(quand: true, lignesResume: 1))) < 0.5 && m.trace.bande <= Double(m.demiCamera) + GeoIlot.aileMax + 0.01,
                 "la forme a la hauteur de la carte (127 pt sous la barre) ; ≤ 66 pt dans la barre")
        pause(0.8)
        // un VRAI clic sur « Envoyer dans Rappels » : la fenêtre de macOS (simulée), une fois, puis « ✓ Dans Rappels »
        clic(PlanVoix.cadreEnvoi(m.grille, genre: .rappel))
        attendre(1.0) { m.envoiVoix != .fait }
        verifier(faux.demandes == 1 && EssaiLucarne.choix == .oui && faux.crees.count == 1 && c.rappels.rappel(r1?.id ?? UUID())?.idApple != nil && m.envoiVoix == .fait,
                 "vrai clic sur « Envoyer dans Rappels » : la fenêtre de macOS une fois, créé et lié, « ✓ Dans Rappels » (\(m.envoiVoix))")
        verifier((m.bandeau?.jusqua ?? .distantPast) <= c.maintenant().addingTimeInterval(IlotControleur.dureeApresEnvoi + 0.1),
                 "envoyé : la carte part peu après (\(IlotControleur.dureeApresEnvoi) s)")
        verifier(m.bandeauVu?.vue != .lucarne, "jamais la question « Aussi dans l'app Rappels ? » en plus de la carte")
        m.quitterBandeau(); pause(0.6)
        verifier(m.bandeau?.vue == .appareil && !m.voix.retient, "la carte partie, l'annonce qui attendait passe (\(m.bandeau?.vue.rawValue ?? "rien"))")
        m.quitterBandeau(); pause(0.5)

        // --- le suivant part seul (Hugues l'a voulu une fois) ; « Annuler » le retire de Lucarne ET de l'app Rappels
        appuyer(); _ = direct("Lucarne, rappelle-moi d'appeler Paul demain à 15 h"); relacher()
        verifier(ecrire("Lucarne, rappelle-moi d'appeler Paul demain à 15 h.") && m.courante == .voixCarte && m.envoiVoix == .fait && faux.crees.count == 2
                 && m.voix.carte?.titre == "Appeler Paul", "le rappel suivant part seul : la carte dit déjà « ✓ Dans Rappels » (\(m.envoiVoix))")
        let r2 = c.rappels.rappels.last, ext2 = r2?.idAppleExterne
        pause(0.6)
        clic(PlanVoix.cadreSecondaire(m.grille, genre: .rappel))
        verifier(!c.rappels.rappels.contains { $0.id == r2?.id } && ext2.map { faux.supprimes.contains($0) } == true && m.bandeau == nil,
                 "vrai clic sur « Annuler » : retiré de Lucarne et de l'app Rappels, la carte part")
        pause(0.4)

        // --- une note : « Note… », puis « Envoyer dans Notes » et « Copier »
        appuyer()
        verifier(direct("Lucarne, note") && m.voix.genre == .note, "« Lucarne, note » : « Note… »")
        relacher()
        let texteNote = "Montrer le prix dès la première page, avec trois exemples de clients."
        verifier(ecrire("Lucarne, note : montrer le prix dès la première page, avec trois exemples de clients.") && m.courante == .voixCarte
                 && m.notes.first?.texte == texteNote && m.voix.carte?.genre == .note && m.envoiVoix == .aEnvoyer && notesEnvoyees.isEmpty,
                 "la carte de la note : gardée dans Note rapide, rien d'envoyé dans Notes sans clic (\(m.courante))")
        verifier(m.voix.lignesResume == 2 && abs(m.geo[2].cibleFinale - (barre + MesuresVoix.profondeurCarte(quand: false, lignesResume: 2))) < 0.5,
                 "le résumé sur deux lignes, la forme à sa hauteur (\(m.voix.lignesResume) lignes)")
        pause(0.8)
        clic(PlanVoix.cadreEnvoi(m.grille, genre: .note))
        attendre(1.0) { m.envoiVoix != .fait }
        verifier(notesEnvoyees.count == 1 && notesEnvoyees.first?.contains("Montrer le prix") == true && m.envoiVoix == .fait && m.notes.first?.versNotes == true,
                 "vrai clic sur « Envoyer dans Notes » : une note dans l'app Notes (simulée), « ✓ Dans Notes »")
        let copies0 = pressePapiers().count
        clic(PlanVoix.cadreSecondaire(m.grille, genre: .note))
        verifier(pressePapiers().count == copies0 + 1 && pressePapiers().last == texteNote && m.voix.copie && m.bandeau?.vue == .voixCarte,
                 "vrai clic sur « Copier » : la note entière dans le presse-papiers, « Copié », la carte reste")
        clic(PlanVoix.cadreEnvoi(m.grille, genre: .note), 0.3)
        verifier(notesEnvoyees.count == 1, "déjà dans Notes : un autre clic n'envoie rien deux fois")
        m.quitterBandeau(); pause(0.5)

        // --- les refus : l'app Notes refusée (Automatisation), puis l'app Rappels refusée : « Autoriser dans Réglages », le bon volet
        notesAccepte = false
        appuyer(); _ = direct("Lucarne, note que le devis est validé"); relacher()
        _ = ecrire("Lucarne, note que le devis est validé.")
        pause(0.6)
        clic(PlanVoix.cadreEnvoi(m.grille, genre: .note))
        attendre(1.0) { m.envoiVoix != .refuse }
        verifier(m.envoiVoix == .refuse && m.voix.carte?.resume.isEmpty == true && m.voix.lignesResume == 0,
                 "l'app Notes refusée : « Autoriser dans Réglages » ; une note qui tient dans son titre n'a pas de résumé")
        let liens0 = liens().count
        clic(PlanVoix.cadreEnvoi(m.grille, genre: .note))
        verifier(liens().count == liens0 + 1 && liens().last == IlotControleur.reglagesAutomatisation && notesEnvoyees.count == 2,
                 "vrai clic sur « Autoriser dans Réglages » : le volet Automatisation, sans renvoyer la note")
        m.quitterBandeau(); pause(0.5)
        let faux2 = RappelsAppleFactice(); faux2.acces = .refuse; c.rappelsApple = faux2
        appuyer(); _ = direct("Lucarne, rappelle-moi de rendre les livres jeudi à 10 h"); relacher()
        _ = ecrire("Lucarne, rappelle-moi de rendre les livres jeudi à 10 h.")
        verifier(m.envoiVoix == .refuse && faux2.demandes == 0, "l'app Rappels refusée dans Réglages Système : « Autoriser dans Réglages », aucune fenêtre")
        pause(0.6)
        clic(PlanVoix.cadreEnvoi(m.grille, genre: .rappel))
        verifier(liens().last == IlotControleur.reglagesRappels && faux2.crees.isEmpty, "vrai clic : le volet Rappels des Réglages, rien de créé")
        m.quitterBandeau(); pause(0.5)
        c.rappelsApple = faux

        // --- une dictée prise qui finit sans commande (Groq n'a pas lu « Lucarne, » en tête : collée) : l'onde s'en va, sans reste
        appuyer(); _ = direct("Lucarne, j'ai une question"); relacher()
        c.finDeVoix(session: session); c.occupationChangee(); pause(0.9)
        verifier(m.courante == .repos && !m.voix.retient && m.bandeau == nil && !m.cache, "la dictée finit sans commande : l'onde s'en va, l'îlot revient (\(m.courante))")
        // --- annulée (fn relâchée trop tôt, Échap) : de même
        appuyer(); _ = direct("Verbe, rappelle-moi"); occ.dictee = false; c.dicteeChange(enCours: false)
        c.finDeVoix(session: session); c.occupationChangee(); pause(0.9)
        verifier(m.courante == .repos && !m.voix.retient, "la dictée annulée : l'onde s'en va")
        // --- une alerte à l'écran : l'îlot ne prend pas la dictée par-dessus (l'encoche de la dictée reste)
        m.annoncer(alerte: AlerteIlot(vue: .minuteurFini, jusqua: nil, libelle: "10 min")); pause(0.5)
        appuyer()
        verifier(!direct("Lucarne, rappelle-moi demain") && m.cache, "une alerte attend un geste : la dictée garde l'encoche, l'îlot ne la prend pas")
        relacher(); m.quitterAlerte(); pause(0.6)

        // --- au repos : plus rien ne tourne
        for r in c.rappels.rappels { c.agir(.rappelAnnuler(r.id)) }
        c.occupation = { OccupationEncoche() }
        c.envoyerNoteVersNotes = { _, fini in fini(false) }
        EssaiLucarne.choix = .non; EssaiLucarne.refusDit = true
        m.quitterBandeau(); m.fermer(); pause(1.2)
        verifier(!m.voix.retient && !m.boucleActive && m.courante == .repos, "fin : l'îlot au repos, aucune boucle d'animation")
    }
}
