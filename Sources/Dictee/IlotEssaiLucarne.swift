import AppKit
import DicteeCore

/// L'app Rappels, pour l'essai : une liste en mémoire ; jamais EventKit, jamais de vraie fenêtre d'autorisation.
@MainActor
final class RappelsAppleFactice: PiloteRappelsApple {
    var acces: AccesRappelsApple = .nonDemande
    /// La réponse de la « fenêtre de macOS » simulée.
    var accorder = true
    var demandes = 0
    var crees: [String: (texte: String, echeance: Date)] = [:]
    /// L'identifiant local de chaque double peut « changer » (synchronisation complète) : retrouvé alors par l'externe.
    var locaux: [String: String] = [:]
    var coches: [String] = [], supprimes: [String] = [], deplaces: [String] = []
    var faitsAilleurs = Set<String>()
    private var compteur = 0
    func demander(_ fini: @escaping @MainActor (Bool) -> Void) {
        demandes += 1
        let ok = accorder
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { MainActor.assumeIsolated { self.acces = ok ? .autorise : .refuse; fini(ok) } }
    }
    func creer(texte: String, echeance: Date) -> DoubleApple? {
        guard acces == .autorise else { return nil }
        compteur += 1
        let id = "EXT-\(compteur)"
        crees[id] = (texte, echeance)
        locaux[id] = "EK-\(compteur)"
        return DoubleApple(id: "EK-\(compteur)", externe: id)
    }
    /// Comme EventKit : par l'identifiant local, sinon par l'externe. Les clés de `crees` sont les identifiants externes.
    private func trouver(_ d: DoubleApple) -> String? {
        if let e = locaux.first(where: { $0.value == d.id })?.key { return e }
        return d.externe.flatMap { crees[$0] != nil ? $0 : nil }
    }
    func cocher(_ d: DoubleApple) -> Bool { guard let e = trouver(d) else { return false }; coches.append(e); return true }
    func supprimer(_ d: DoubleApple) { guard let e = trouver(d) else { return }; supprimes.append(e); crees[e] = nil; locaux[e] = nil }
    func deplacer(_ d: DoubleApple, a echeance: Date) { guard let e = trouver(d), let c = crees[e] else { return }; deplaces.append(e); crees[e] = (c.texte, echeance) }
    func estFait(_ d: DoubleApple) -> Bool? { trouver(d).map { faitsAilleurs.contains($0) } }
}

/// Les réglages que l'essai remplace (jamais les vrais) : la réponse à « Aussi dans l'app Rappels ? », le refus dit, les rappels allumés.
enum EssaiLucarne {
    /// « Non » d'avance : le reste de l'essai n'est jamais interrompu par la question ; la section Lucarne repart de zéro.
    static var choix: ChoixRappelsApple? = .non
    static var refusDit = true
    static var rappelsActifs = true
}

extension IlotEssai {
    /// Les réglages des rappels et de l'app Rappels, simulés (jamais les vrais `Settings`). À reposer après CHAQUE remplacement de
    /// `c.reglagesCentre` dans l'essai : un `ReglagesCentre(…)` neuf revient aux vrais réglages pour tout ce qu'il ne nomme pas.
    @MainActor
    static func reglagesLucarneDEssai(_ c: IlotControleur) {
        c.reglagesCentre.choixRappelsApple = { EssaiLucarne.choix }
        c.reglagesCentre.enregistrerChoixRappelsApple = { EssaiLucarne.choix = $0 }
        c.reglagesCentre.refusRappelsDit = { EssaiLucarne.refusDit }
        c.reglagesCentre.marquerRefusRappelsDit = { EssaiLucarne.refusDit = true }
        c.reglagesCentre.rappelsActifs = { EssaiLucarne.rappelsActifs }
        c.reglagesCentre.allumerRappels = { EssaiLucarne.rappelsActifs = true }
    }

    /// « Lucarne, … » partout (îlot fermé), « Je n'ai pas compris », l'app Rappels (la question une fois, « Oui », « Non », « Fait »,
    /// « Annuler », coché sur l'iPhone, pas de doublon), le minuteur dit. De VRAIS clics sur les bandeaux.
    @MainActor
    static func lucarne(_ c: IlotControleur, decaler: @escaping (Double) -> Void, verifier: (Bool, String) -> Void, attendre: (Double, () -> Bool) -> Void,
                        pressePapiers: () -> [String]) {
        let m = c.moteur
        func pause(_ s: Double) { attendre(s) { true } }
        func clic(_ p: CGPoint, _ apres: Double = 0.5) {
            c.panneau.envoyerSouris(.leftMouseDown, en: p); pause(0.06); c.panneau.envoyerSouris(.leftMouseUp, en: p); pause(apres)
        }
        /// Le centre du bouton `i` (à partir de la droite : 0 = le dernier) d'un bandeau.
        func bouton(_ v: VueIlot, _ titres: [String], depuisLaDroite i: Int) -> CGPoint {
            let za = m.grille.zoneAnnonce(v)
            let largeurs = titres.map { MesureIlot.bouton(ContenuAnnonce.Bouton(titre: $0)) }
            var x = za.maxX
            for k in stride(from: largeurs.count - 1, to: largeurs.count - 1 - i, by: -1) { x -= largeurs[k] + ContenuAnnonce.espaceBoutons }
            return CGPoint(x: x - largeurs[largeurs.count - 1 - i] / 2, y: za.midY)
        }
        /// Une dictée dite îlot FERMÉ, dans une autre app (l'encoche de la dictée prend la place pendant qu'on parle).
        var occ = OccupationEncoche(); c.occupation = { occ }
        func dicter(_ texte: String) -> Bool {
            occ.dictee = true; c.dicteeChange(enCours: true); c.occupationChangee(); pause(0.3)
            occ.dictee = false; c.dicteeChange(enCours: false)
            let pris = c.intercepter(texte)
            c.occupationChangee(); pause(0.5)
            return pris
        }

        print("Lucarne, … (commandes dites partout), l'app Rappels")
        reglagesLucarneDEssai(c)
        let faux = RappelsAppleFactice(); c.rappelsApple = faux
        EssaiLucarne.choix = nil; EssaiLucarne.refusDit = false; c.questionRappelsPosee = false
        m.fermer(); pause(0.8)
        for r in c.rappels.rappels { c.agir(.rappelAnnuler(r.id)) }
        pause(0.3)

        // --- sans le mot d'appel : rien ne change (un mail reste un mail)
        verifier(!dicter("J'ai une livraison demain vers 13-14 h.") && c.rappels.rappels.isEmpty && m.bandeau == nil,
                 "sans « Lucarne » en tête, îlot fermé : dictée normale, collée (aucun rappel, aucun bandeau)")
        // --- une phrase qui PARLE de Lucarne (pas de virgule, aucune demande) : collée elle aussi, jamais un rappel
        verifier(!dicter("Lucarne est prête, je te l'envoie demain.") && !dicter("Verbe 0.3.3 publiée ce soir.") && c.rappels.rappels.isEmpty && m.bandeau == nil,
                 "« Lucarne est prête, je te l'envoie demain », « Verbe 0.3.3 publiée ce soir » : collées dans le mail, aucun rappel, aucun bandeau")

        // --- « Lucarne, … » îlot fermé : le rappel de Hugues (11/11)
        verifier(dicter("Lucarne, j'ai demain une livraison vers 13-14h."), "« Lucarne, j'ai demain une livraison vers 13-14h » : une commande, rien n'est collé")
        let cal = Calendar.current
        // « demain » : le jour qui commence si l'essai tourne entre minuit et 4 h (on vit encore la veille), et l'îlot nomme alors le jour
        let demain13 = cal.date(bySettingHour: 13, minute: 0, second: 0, of: MomentDicte.demain(c.maintenant()))!
        let jourDit = ListeRappels.jour(de: demain13, maintenant: c.maintenant())
        let r1 = c.rappels.rappels.last
        verifier(r1?.texte == "Livraison" && r1?.echeance == demain13, "rappel « Livraison », demain 13:00 (\(r1?.texte ?? "aucun"), \(r1.map { FormatIlot.heure($0.echeance) } ?? "-"))")
        // dit à Lucarne : la carte de fin (IlotVoix.swift) remplace « Rappel ajouté » et la question de l'app Rappels
        verifier(m.courante == .voixCarte && m.voix.carte?.titre == "Livraison" && m.voix.carte?.quand == jourDit + " \u{00B7} 13:00" && m.envoiVoix == .aEnvoyer,
                 "confirmation visible : la carte « Livraison · \(jourDit) · 13:00 » et « Envoyer dans Rappels » (\(m.courante))")
        verifier(m.trace.bande <= Double(m.demiCamera) + GeoIlot.aileMax + 0.01, "la carte : ≤ 66 pt dans la barre")
        attendre(IlotControleur.dureeRappelAjoute + 2.5) { m.bandeauVu?.lucarne != .questionRappelsApple }
        verifier(m.bandeauVu?.lucarne != .questionRappelsApple && faux.demandes == 0 && faux.crees.isEmpty,
                 "jamais la question « Aussi dans l'app Rappels ? » en plus de la carte ; rien n'est envoyé sans clic")
        pause(0.4)
        clic(CGPoint(x: PlanVoix.cadreEnvoi(m.grille, genre: .rappel).midX, y: PlanVoix.cadreEnvoi(m.grille, genre: .rappel).midY), 0.1)
        attendre(1.0) { faux.crees.isEmpty }
        pause(0.2)
        verifier(faux.demandes == 1 && EssaiLucarne.choix == .oui, "vrai clic sur « Envoyer dans Rappels » : la fenêtre de macOS (simulée), une fois ; vaut le « Oui »")
        verifier(faux.crees.count == 1 && faux.crees.values.first?.texte == "Livraison" && faux.crees.values.first?.echeance == demain13 && c.rappels.rappels.last?.idApple != nil
                 && m.envoiVoix == .fait, "accordé : « Livraison » créé dans l'app Rappels, à l'heure (alarme), lié dans rappels.json ; « ✓ Dans Rappels »")
        m.quitterBandeau(); pause(0.5)

        // --- le rappel suivant va directement dans l'app Rappels (sans question), une seule fois
        verifier(dicter("Lucarne, rappelle-moi d'appeler Ladislas demain à 15 h."), "« Lucarne, rappelle-moi d'appeler Ladislas demain à 15 h »")
        let r2 = c.rappels.rappels.last
        verifier(r2?.texte == "Appeler Ladislas" && faux.crees.count == 2 && r2?.idApple != nil && m.envoiVoix == .fait,
                 "« Appeler Ladislas » (à l'infinitif), aussi dans l'app Rappels, sans question : la carte dit « ✓ Dans Rappels »")
        c.creerDansRappelsApple(c.rappels.rappels, annoncer: false)
        verifier(faux.crees.count == 2, "re-synchroniser ne crée aucun doublon (\(faux.crees.count) dans l'app Rappels)")
        m.quitterBandeau(); pause(0.5)

        // --- « Annuler » sur la carte : retiré là-bas aussi
        verifier(dicter("Verbe, mets un rappel demain à 9 h pour sortir les poubelles."), "« Verbe, mets un rappel… » (l'ancien nom marche aussi)")
        let r3 = c.rappels.rappels.last, id3 = r3?.idAppleExterne
        verifier(r3?.texte == "Sortir les poubelles" && id3 != nil, "« Sortir les poubelles », créé dans l'app Rappels")
        pause(0.4)
        clic(CGPoint(x: PlanVoix.cadreSecondaire(m.grille, genre: .rappel).midX, y: PlanVoix.cadreSecondaire(m.grille, genre: .rappel).midY), 0.5)
        verifier(!c.rappels.rappels.contains { $0.id == r3?.id } && id3.map { faux.supprimes.contains($0) } == true, "vrai clic sur « Annuler » : retiré de Lucarne ET de l'app Rappels")

        // --- « Fait » dans Lucarne : coché dans l'app Rappels ; coché sur l'iPhone : ne sonne pas ici
        if let r = r2, let a = r.idAppleExterne {
            // l'identifiant local a changé là-bas (synchronisation complète d'iCloud) : retrouvé par l'identifiant externe
            faux.locaux[a] = "EK-apres-synchronisation"
            c.agir(.rappelFait(r.id)); pause(0.3)
            verifier(faux.coches.contains(a) && !c.rappels.rappels.contains { $0.id == r.id }, "« Fait » dans Lucarne : coché aussi dans l'app Rappels, même après un changement d'identifiant local")
        }
        if let r = r1.flatMap({ c.rappels.rappel($0.id) }), let a = r.idAppleExterne {
            faux.faitsAilleurs.insert(a)
            let sonneries = m.alerte
            decaler(2 * 86400); c.verifierLesRappels(); pause(0.4)
            verifier(!c.rappels.rappels.contains { $0.id == r.id } && m.alerte?.vue != .rappelEtendu && sonneries == nil,
                     "coché sur l'iPhone avant l'heure : il ne sonne pas une deuxième fois sur le Mac, il part sans bruit")
            decaler(-2 * 86400)
        }
        m.fermer(); pause(0.6)

        // --- ce qui n'est pas compris : jamais collé, jamais silencieux ; « Copier » rend la phrase ENTIÈRE (l'aperçu seul est coupé)
        let longue = "Lucarne, " + String(repeating: "voici un long paragraphe dicté pour le compte rendu de la réunion de ce matin avec l'équipe. ", count: 4) + "Fin."
        verifier(dicter(longue), "une longue dictée pour Lucarne, pas comprise : rien n'est collé, pas de plantage")
        verifier(m.courante == .lucarne && m.bandeauVu?.lucarne == .incomprise(longue) && m.contenuAnnonce(.lucarne)?.l1 == "Je n\u{2019}ai pas compris"
                 && (m.contenuAnnonce(.lucarne)?.l2.count ?? 999) < 130,
                 "« Je n'ai pas compris » et l'aperçu de la phrase (\(m.courante))")
        let copies0 = pressePapiers().count
        clic(bouton(.lucarne, ["Copier"], depuisLaDroite: 0), 0.5)
        verifier(pressePapiers().count == copies0 + 1 && pressePapiers().last == longue && m.bandeau == nil,
                 "vrai clic sur « Copier » : la phrase ENTIÈRE (\(longue.count) caractères) est dans le presse-papiers, rien de perdu")
        // un moment déjà passé : pas de rappel qui sonnerait aussitôt, « Cette heure est passée »
        let n0 = c.rappels.rappels.count
        verifier(dicter("Lucarne, rappelle-moi le 2/1/2020 à 9 h d'appeler Paul.") && c.rappels.rappels.count == n0 && m.bandeauVu?.lucarne == .passe("Lucarne, rappelle-moi le 2/1/2020 à 9 h d'appeler Paul.")
                 && m.contenuAnnonce(.lucarne)?.l1 == "Cette heure est passée", "un moment passé : rien d'ajouté, « Cette heure est passée » (\(m.courante))")
        m.quitterBandeau(); pause(0.4)
        verifier(dicter("Lucarne, rappelle-moi d'appeler Paul.") && m.contenuAnnonce(.lucarne)?.l1 == "Il me manque l\u{2019}heure", "un rappel sans heure : « Il me manque l'heure »")
        m.quitterBandeau(); pause(0.4)

        // --- le minuteur dit
        verifier(dicter("Lucarne, minuteur de 5 minutes.") && abs((c.minuteur?.total ?? 0) - 300) < 0.5 && m.bandeauVu?.vue == .minuteurLance, "« Lucarne, minuteur de 5 minutes » : lancé, « Minuteur lancé »")
        c.agir(.minuteurArreter); pause(0.6)

        // --- l'îlot ouvert (Centre épinglé) : le bandeau passe quand même (la réponse à ce qu'on vient de dire)
        m.clicForme(); pause(0.8); m.epinglerLeCentre(); pause(0.3)
        occ.dictee = true; c.dicteeChange(enCours: true); c.occupationChangee(); pause(0.3)
        occ.dictee = false; c.dicteeChange(enCours: false)
        verifier(c.intercepter("Lucarne, ouvre Safari."), "Centre épinglé : « Lucarne, ouvre Safari » est pour Lucarne")
        c.occupationChangee(); pause(0.8)
        verifier(m.courante == .lucarne, "… et « Je n'ai pas compris » se voit même sur le Centre épinglé (\(m.courante))")
        m.quitterBandeau(); m.fermer(); pause(0.6)

        // --- la question de l'app Rappels reste pour un rappel ajouté autrement qu'en parlant à Lucarne (« En faire un rappel » sous une
        // note) : « Non » est dit une fois, plus jamais demandé
        func ajouter(_ texte: String) -> Bool { c.ajouterUnRappel(texte: texte, quand: c.maintenant().addingTimeInterval(86_400)) != nil }
        EssaiLucarne.choix = nil; EssaiLucarne.refusDit = false; c.questionRappelsPosee = false
        let faux2 = RappelsAppleFactice(); c.rappelsApple = faux2
        verifier(ajouter("Relancer Marc") && m.courante == .rappelAjoute, "un rappel ajouté sans parler à Lucarne : « Rappel ajouté », accès jamais demandé")
        attendre(IlotControleur.dureeRappelAjoute + 2.5) { m.bandeauVu?.lucarne != .questionRappelsApple }
        verifier(m.bandeauVu?.lucarne == .questionRappelsApple, "la question (\(m.courante))")
        pause(0.8)
        clic(bouton(.lucarne, ["Non", "Oui"], depuisLaDroite: 1), 0.5)
        verifier(EssaiLucarne.choix == .non && faux2.demandes == 0 && faux2.crees.isEmpty && m.bandeauVu?.lucarne == .rappelsRestentIci(systeme: false),
                 "vrai clic sur « Non » : aucune fenêtre de macOS, « Tes rappels restent ici » (une fois)")
        pause(6.5)
        c.questionRappelsPosee = false
        verifier(ajouter("Payer la cantine"), "rappel suivant")
        pause(IlotControleur.dureeRappelAjoute + 1.8)
        verifier(m.bandeau == nil && faux2.demandes == 0 && faux2.crees.isEmpty, "plus jamais demandé, rien dans l'app Rappels")

        // --- refus dans la fenêtre de macOS : dit une fois
        EssaiLucarne.choix = nil; EssaiLucarne.refusDit = false; c.questionRappelsPosee = false
        let faux3 = RappelsAppleFactice(); faux3.accorder = false; c.rappelsApple = faux3
        verifier(ajouter("Arroser les plantes"), "un rappel, la fenêtre de macOS dira non")
        attendre(IlotControleur.dureeRappelAjoute + 2.5) { m.bandeauVu?.lucarne != .questionRappelsApple }
        pause(0.8)
        clic(bouton(.lucarne, ["Non", "Oui"], depuisLaDroite: 0), 0.1)
        attendre(1.0) { m.bandeauVu?.lucarne != .rappelsRestentIci(systeme: true) }
        verifier(faux3.demandes == 1 && faux3.crees.isEmpty && EssaiLucarne.choix == .non && m.bandeauVu?.lucarne == .rappelsRestentIci(systeme: true),
                 "« Oui » puis refus dans la fenêtre de macOS : le rappel reste dans Lucarne, « Accès refusé · Réglages Système pour changer »")
        // déjà refusé dans Réglages Système, jamais rien dit : dit une fois, sans question
        EssaiLucarne.choix = nil; EssaiLucarne.refusDit = false; c.questionRappelsPosee = false
        let faux4 = RappelsAppleFactice(); faux4.acces = .refuse; c.rappelsApple = faux4
        m.quitterBandeau(); pause(0.4)
        verifier(ajouter("Rendre les livres"), "accès déjà refusé dans Réglages Système")
        attendre(IlotControleur.dureeRappelAjoute + 2.5) { m.bandeauVu?.lucarne != .rappelsRestentIci(systeme: true) }
        verifier(m.bandeauVu?.lucarne == .rappelsRestentIci(systeme: true) && faux4.demandes == 0 && EssaiLucarne.refusDit, "dit une fois, sans question ni fenêtre")
        m.quitterBandeau(); pause(0.4)
        for r in c.rappels.rappels { c.agir(.rappelAnnuler(r.id)) }
        EssaiLucarne.choix = .non; EssaiLucarne.refusDit = true
        c.occupation = { OccupationEncoche() }
        m.fermer(); pause(0.8)
    }
}
