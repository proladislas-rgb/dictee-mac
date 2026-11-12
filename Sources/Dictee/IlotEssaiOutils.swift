import AppKit
import DicteeCore

/// Garder éveillé, pour l'essai : compte, ne touche jamais la veille du Mac.
@MainActor
final class EveilFactice: PiloteEveil {
    private(set) var actif = false
    var gardes = 0, rendus = 0
    func garder(raison: String) -> Bool { actif = true; gardes += 1; return true }
    func rendre() { if actif { rendus += 1 }; actif = false }
}

/// Le presse-papiers, pour l'essai : un compteur, des types, un contenu ; jamais le vrai presse-papiers.
@MainActor
final class PressePapiersFactice: PilotePressePapiers {
    private(set) var compteur = 0
    var types: [String] = []
    var contenu = ContenuCopie()
    /// Combien de fois le contenu a été lu, et ce que Verbe a écrit.
    var lectures = 0
    var ecrits: [ContenuCopie] = []
    func lire() -> (types: [String], contenu: ContenuCopie) { lectures += 1; return (types, contenu) }
    func ecrire(_ c: ContenuCopie) { ecrits.append(c); contenu = c; types = ["public.utf8-plain-text"]; compteur += 1 }
    /// Une copie faite dans une autre app.
    func copier(_ c: ContenuCopie, types t: [String] = ["public.utf8-plain-text"]) { contenu = c; types = t; compteur += 1 }
}

extension IlotEssai {
    /// Les Outils (maquette ilot-claude-plus.html, étapes 8 à 14), de bout en bout, dans la fenêtre invisible de l'essai : de VRAIS clics et
    /// de VRAIS défilements remis à la fenêtre. Rien du vrai système : la veille est un compteur, le presse-papiers un faux, Reformuler
    /// répond sans réseau, la sélection et l'app Notes sont simulées, les notes vont dans le dossier temporaire.
    @MainActor
    static func outils(_ c: IlotControleur, dossier: URL, decaler: @escaping (Double) -> Void, verifier: (Bool, String) -> Void, attendre: (Double, () -> Bool) -> Void) {
        let m = c.moteur, g = m.geometrie
        let hc = Double(m.demiCamera)
        func pause(_ s: Double) { attendre(s) { true } }
        func clic(_ p: CGPoint, _ apres: Double = 0.5) {
            c.panneau.envoyerSouris(.leftMouseDown, en: p); pause(0.06); c.panneau.envoyerSouris(.leftMouseUp, en: p); pause(apres)
        }
        func geste(_ pas: [Int32], en p: CGPoint) {
            for (i, d) in pas.enumerated() { c.panneau.envoyerDefilement(dy: d, en: p, phase: i == 0 ? 1 : 2); pause(0.016) }
            c.panneau.envoyerDefilement(dy: 0, en: p, phase: 4); pause(0.02)
        }
        /// La forme posée : rien de plus de 66 pt dans la barre, dans la zone de dessin, aucune boucle d'animation.
        func pose(_ quoi: String) {
            attendre(1.4) { m.boucleActive }
            verifier(m.trace.bande <= hc + GeoIlot.aileMax + 0.01 && Double(m.geo[2].x) + 30 <= Double(IlotMoteur.hauteurMax) && !m.boucleActive,
                     "\(quoi) : \(String(format: "%.2f", m.trace.bande - hc)) pt dans la barre (≤ 66), \(Int(m.geo[2].x)) pt de haut, posé sans boucle (\(m.ceQuiBouge))")
            // la forme a la hauteur de ce qu'elle montre MAINTENANT (une liste qui a grandi sans que la forme suive : lignes mortes)
            verifier(abs(m.geo[2].x - Double(m.grille.hauteur(m.courante))) < 0.5,
                     "\(quoi) : la forme (\(Int(m.geo[2].x)) pt) épouse son contenu (\(Int(m.grille.hauteur(m.courante))) pt)")
            if let f = c.panneau.cadre { verifier(Double(f.height) >= m.trace.hauteur && Double(f.width) >= 2 * m.trace.corps, "\(quoi) : la fenêtre couvre la forme") }
        }

        print("Les Outils (2e page du Centre)")
        // tout est simulé
        var memoire: [String]? = nil
        c.reglagesCentre.dispositionOutils = { memoire }
        c.reglagesCentre.enregistrerDispositionOutils = { memoire = $0 }
        let eveil = EveilFactice(); c.eveilPilote = eveil
        let pp = PressePapiersFactice(); c.pressePapiers = pp; c.compteurPressePapiers = nil
        var commandesV = 0; c.surCommandeV = { commandesV += 1; return true }
        var colles: [String] = []; c.surColler = { colles.append($0) }
        var demandes: [(String, StyleReformulation)] = []
        var reponse: (String, StyleReformulation) throws -> String = { _, s in
            switch s {
            case .pro: return "« Bonjour, je vous confirme le devis de la cuisine : 4\u{202F}200\u{202F}€, pose et plan de travail en chêne compris. Je vous envoie ce soir les plans et les photos du chantier. Cordialement. »"
            case .court: return "OK pour le devis cuisine : 4\u{202F}200\u{202F}€ posé, chêne compris."
            case .anglais: return "Hello Mrs Martin, I confirm our appointment on Tuesday."
            }
        }
        c.reformulerTexte = { t, s in demandes.append((t, s)); try await Task.sleep(for: .milliseconds(300)); return try reponse(t, s) }
        let dictee = "OK pour le devis de la cuisine : 4\u{202F}200\u{202F}€ posé, plan de travail en chêne compris. Je te l\u{2019}envoie ce soir avec les plans."
        c.lireDerniereDictee = { (dictee, c.maintenant().addingTimeInterval(-60)) }
        c.lireAppDerniereDictee = { "Mail" }
        var selection: (texte: String, app: String?)? = ("Bonjour Madame Martin, je vous confirme le rendez-vous de mardi.", "Mail")
        c.lireSelection = { selection }
        var selectionPossible = true, selectionsDemandees: [String] = []
        c.selectionnerDansLApp = { selectionsDemandees.append($0); return selectionPossible }
        var versNotes: [String] = [], notesAccepte = true
        c.envoyerNoteVersNotes = { html, fini in versNotes.append(html); let ok = notesAccepte; DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { fini(ok) } }
        m.dispositionOutils = DispositionCentre(identifiants: memoire, page: .outils)
        m.disposition = DispositionCentre()
        c.lecture.modele.morceau = nil; c.lecture.surIlot(false)
        m.fermer(); pause(0.8)

        // --- le Centre : « Outils › » dans l'en-tête, un vrai clic
        pp.copier(ContenuCopie(texte: "4\u{202F}200\u{202F}€ posé, plan de travail en chêne compris"))
        m.clicForme(); pause(0.9)
        verifier(m.courante == .centre, "îlot vide, un clic : le Centre (\(m.courante))")
        let ent = PlanCentre.cadreEntete(m.grille)
        // « Outils › » est à gauche de « Dictées » et de « Modifier »
        let pOutils = CGPoint(x: ent.maxX - EnteteCentre.pilule(EnteteCentre.titreModifier) - 8 - EnteteCentre.piluleDictees - 8 - EnteteCentre.piluleOutils / 2, y: ent.midY)
        clic(pOutils, 0.9)
        verifier(m.courante == .outils && m.carteCourante == .outils && m.visible(ExtraIlot.points) && m.cartes == [.centre, .outils, .accueil, .dictees],
                 "vrai clic sur « Outils › » : la 2e page, son point allumé (\(m.courante))")
        verifier(m.rondsDe(.outils) == [.eveil, .pressePapiers, .reformuler, .notes, .groq] && m.dispositionOutils.bande, "quatre ronds, la jauge de Groq et la bande « Dicter une note » (maquette, étape 8)")
        verifier(m.copies.count == 1 && pp.lectures == 1, "l'îlot s'est ouvert : le presse-papiers a été regardé une fois (\(pp.lectures) lecture)")
        pose("page Outils")
        // le 1er point (le Centre), le 2e (les Outils), un défilement (une carte), « ‹ Centre »
        let n = m.cartes.count
        clic(PointsCartes.centre(0, sur: n, corps: CGFloat(m.trace.corps), hauteur: CGFloat(m.geo[2].x), barre: g.hauteur), 0.8)
        verifier(m.courante == .centre, "vrai clic sur le 1er point : le Centre")
        clic(PointsCartes.centre(1, sur: n, corps: CGFloat(m.trace.corps), hauteur: CGFloat(m.geo[2].x), barre: g.hauteur), 0.8)
        verifier(m.courante == .outils, "vrai clic sur le 2e point : les Outils")
        let milieu = CGPoint(x: 0, y: g.hauteur + 120)
        geste([5, 12], en: milieu); pause(0.7)
        verifier(m.courante == .centre, "vrai défilement vers le bas : le Centre (\(m.courante))")
        geste([-6, -12], en: milieu); pause(0.7)
        verifier(m.courante == .outils, "vrai défilement vers le haut : les Outils, une seule carte (\(m.courante))")
        clic(CGPoint(x: PlanCentre.cadreEntete(m.grille, .outils).minX + 30, y: PlanCentre.cadreEntete(m.grille, .outils).midY), 0.8)
        verifier(m.courante == .centre, "vrai clic sur « ‹ Centre » : le Centre")
        m.allerA(.outils); pause(0.8)

        // --- Garder éveillé
        let hSans = m.geo[2].cibleFinale
        clic(PlanCentre.centreRond(m, .eveil), 0.7)
        verifier(m.panneauEveil && m.eveil == nil && m.geo[2].cibleFinale > hSans + 50 && m.epingle, "vrai clic sur la tasse : le panneau « combien de temps ? » s'ouvre, la page s'allonge, « Reste ouvert »")
        pose("page Outils, panneau Garder éveillé")
        clic(PanneauEveil.pointPilule(0, m), 0.6)
        verifier(m.eveil?.duree == .uneHeure && eveil.actif && eveil.gardes == 1 && c.reveilEveil != nil, "vrai clic sur « 1 h » : le Mac est gardé éveillé (faux pilote), un réveil à l'échéance")
        verifier(m.etatCentre(.eveil) == "Encore 1 h" || m.etatCentre(.eveil) == "Encore 59 min", "sous la tasse : « \(m.etatCentre(.eveil)) »")
        clic(PanneauEveil.pointPilule(1, m), 0.6)
        verifier(m.eveil?.duree == .deuxHeures && eveil.gardes == 1 && eveil.actif, "« 2 h » : la durée change, pas de deuxième assertion")
        decaler(2 * 3600 + 5); c.verifierEcheanceEveil(); pause(0.3)
        verifier(m.eveil == nil && !eveil.actif && eveil.rendus == 1 && c.reveilEveil == nil, "l'échéance passée (heure avancée de 2 h) : rendu, veille normale, plus de réveil")
        decaler(-(2 * 3600 + 5))
        verifier(m.panneauEveil, "le panneau reste ouvert pour rechoisir")
        clic(PanneauEveil.pointPilule(2, m), 0.6)
        verifier(m.eveil?.duree == .sansLimite && m.eveil?.echeance == nil && c.reveilEveil == nil && m.etatCentre(.eveil) == "Toujours", "« Jusqu'à l'arrêt » : aucun réveil, « Toujours »")
        clic(PanneauEveil.pointPilule(3, m), 0.6)
        verifier(m.eveil == nil && !eveil.actif && eveil.rendus == 2, "vrai clic sur « Éteindre » : rendu")
        clic(PanneauEveil.pointPilule(0, m), 0.5)
        clic(PlanCentre.centreRond(m, .eveil), 0.6)
        verifier(m.eveil == nil && !eveil.actif && eveil.rendus == 3, "allumé, un clic sur la tasse ambre : éteint")
        clic(PanneauEveil.pointPilule(0, m), 0.5)
        m.fermer(); pause(0.8)
        verifier(m.eveil != nil && eveil.actif && m.courante == .repos, "l'îlot rangé : le Mac reste gardé éveillé, l'îlot replié n'en montre rien")
        m.clicForme(); pause(0.8); m.allerA(.outils); pause(0.8)
        verifier(m.panneauEveil || m.panneauEveilVisible, "rouverte, la page montre le panneau (jusqu'à quand, « Éteindre »)")
        // l'îlot replié n'en montre rien (maquette) : le menu de Verbe le dit et l'éteint ; sur batterie, à 10 %, la veille redevient normale
        verifier(c.titreMenuEveil?.hasPrefix("Rendre la veille au Mac (gardé éveillé : encore ") == true, "le menu de Verbe : « \(c.titreMenuEveil ?? "-") »")
        c.eveilSelonEnergie(EnergieIlot(pourcent: 35, secteur: false, enCharge: false))
        c.eveilSelonEnergie(EnergieIlot(pourcent: 6, secteur: true, enCharge: true))
        verifier(eveil.actif && m.eveil != nil, "batterie à 35 %, ou branché à 6 % : toujours gardé éveillé")
        c.eveilSelonEnergie(EnergieIlot(pourcent: 10, secteur: false, enCharge: false))
        verifier(!eveil.actif && m.eveil == nil && c.titreMenuEveil == nil, "sur batterie à 10 % : rendu (un « Jusqu'à l'arrêt » oublié ne vide pas la batterie), plus de ligne au menu")
        clic(PanneauEveil.pointPilule(2, m), 0.6)
        verifier(c.titreMenuEveil == "Rendre la veille au Mac (gardé éveillé : sans limite)" && eveil.actif, "« Jusqu'à l'arrêt » : « \(c.titreMenuEveil ?? "-") »")
        c.arreterEveil(journal: "menu (essai)")
        verifier(!eveil.actif && m.eveil == nil, "« Rendre la veille au Mac » (menu) : rendu")
        clic(PanneauEveil.pointPilule(0, m), 0.6)
        verifier(eveil.actif && m.eveil?.duree == .uneHeure, "« 1 h » de nouveau (pour la suite de l'essai)")

        // --- Presse-papiers
        clic(PlanCentre.centreRond(m, .pressePapiers), 0.9)
        verifier(m.courante == .outilPressePapiers && m.carteCourante == .outils && m.visible(ExtraIlot.points), "vrai clic sur Presse-papiers : sa carte, le point des Outils allumé")
        // des copies faites ailleurs ; Verbe regarde le compteur quand une app passe au premier plan (ici appelé à la main : l'essai
        // n'installe pas l'écoute de NSWorkspace)
        let lectures0 = pp.lectures
        c.verifierPressePapiers()
        verifier(pp.lectures == lectures0, "rien n'a changé (même compteur) : le contenu n'est pas relu")
        let png = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 40, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!.representation(using: .png, properties: [:])!
        pp.copier(ContenuCopie(image: (png, .png)), types: ["public.png"]); c.verifierPressePapiers()
        let pdf = dossier.appendingPathComponent("Devis-cuisine.pdf"); try? Data(repeating: 1, count: 212 * 1024).write(to: pdf)
        pp.copier(ContenuCopie(fichiers: [pdf]), types: ["public.file-url"]); c.verifierPressePapiers()
        pp.copier(ContenuCopie(texte: "MotDePasse-tres-secret"), types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]); c.verifierPressePapiers()
        pp.copier(ContenuCopie(texte: "git push origin main")); c.verifierPressePapiers()
        pp.copier(ContenuCopie(texte: "Bonjour Madame Martin, je vous confirme le rendez-vous de mardi.")); c.verifierPressePapiers()
        pp.copier(ContenuCopie(texte: "un sixième")); c.verifierPressePapiers()
        pp.copier(ContenuCopie(texte: "Bonjour Madame Martin, je vous confirme le rendez-vous de mardi.")); c.verifierPressePapiers()
        pause(0.8)
        let titres = m.copies.map(\.titre)
        verifier(m.copies.count == 5 && titres.first == "Bonjour Madame Martin, je vous confirme le rendez-vous de mardi." && titres.contains("git push origin main")
                 && titres.contains("Devis-cuisine.pdf") && titres.contains("Image") && !titres.contains { $0.contains("MotDePasse") },
                 "cinq au plus, la plus récente en haut, recopiée = remontée ; le mot de passe (ConcealedType) jamais gardé (\(titres))")
        verifier(m.copies.first { $0.titre == "git push origin main" }?.style == .commande && m.copies.first { $0.titre == "Image" }?.detail == "64 \u{00D7} 40"
                 && m.copies.first { $0.titre == "Devis-cuisine.pdf" }?.detail?.hasSuffix("Ko") == true && m.copies.first { $0.titre == "Image" }?.icone != nil,
                 "la commande en chasse fixe, l'image avec sa taille et sa miniature, le fichier avec son poids")
        verifier(c.contenusCopies.count == 5, "en mémoire : exactement ce qu'il faut pour recopier les cinq (\(c.contenusCopies.count))")
        pose("carte Presse-papiers (5 copies)")
        let zp = PlanPressePapiers.zone(m.grille)
        clic(CGPoint(x: zp.minX + EnteteOutil<ResteOuvert>.pilule + 60, y: zp.minY + 13), 0.4)
        clic(CGPoint(x: zp.minX + 60, y: zp.maxY - 15), 0.4)
        verifier(m.courante == .outilPressePapiers && pp.ecrits.isEmpty, "un clic sur le titre, puis sur « Rien ne quitte ce Mac » : rien ne se passe, l'îlot reste ouvert")
        // un vrai clic sur la 2e ligne : elle revient dans le presse-papiers, « Copié », la liste ne bouge pas
        let id2 = m.copies[1].id, t2 = m.copies[1].titre
        let ecrits0 = pp.ecrits.count
        clic(PlanPressePapiers.pointLigne(1, m), 0.3)
        verifier(pp.ecrits.count == ecrits0 + 1 && m.copieFaite?.id == id2 && m.copieFaite?.mot == "Copié" && m.courante == .outilPressePapiers,
                 "vrai clic sur « \(t2) » : recopiée, « Copié », la carte reste ouverte")
        c.verifierPressePapiers(); pause(0.2)
        verifier(m.copies[1].id == id2 && m.copies.count == 5, "c'est Verbe qui a écrit : pas une nouvelle copie, la ligne garde sa place")
        pause(1.3)
        verifier(m.copieFaite == nil, "« Copié » s'efface (un seul réveil)")
        // « Coller » au survol : un vrai déplacement de la souris sur la 3e ligne, puis un vrai clic sur « Coller »
        let id3 = m.copies[2].id
        c.panneau.envoyerSouris(.mouseMoved, en: PlanPressePapiers.pointLigne(2, m)); pause(0.3)
        let survolReel = m.survolCopie == id3
        if !survolReel { m.survolCopie = id3; pause(0.3) }
        verifier(true, "survol de la 3e ligne : \(survolReel ? "vrai déplacement de souris reçu" : "le déplacement fabriqué n'atteint pas le survol de SwiftUI, survol posé à la main")")
        c.panneau.envoyerSouris(.leftMouseDown, en: PlanPressePapiers.pointColler(2, m)); pause(0.06)
        let survolPendantAppui = m.survolCopie == id3
        c.panneau.envoyerSouris(.leftMouseUp, en: PlanPressePapiers.pointColler(2, m)); pause(0.15)
        let mot = m.copieFaite?.mot
        pause(0.65)
        verifier(pp.ecrits.count == ecrits0 + 2 && mot == "Collé" && commandesV == 1 && m.courante != .outilPressePapiers,
                 "vrai clic sur « Coller » : recopiée, « Collé », ⌘V envoyé dans l'app d'où l'on vient (simulé), l'îlot se range (écrits \(pp.ecrits.count - ecrits0), « \(mot ?? "-") », ⌘V \(commandesV), \(m.courante), survol pendant l'appui : \(survolPendantAppui))")
        m.clicForme(); pause(0.8); m.ouvrirOutil(.outilPressePapiers); pause(0.9)
        clic(PlanPressePapiers.pointToutEffacer(m), 0.8)
        verifier(m.copies.isEmpty && c.contenusCopies.isEmpty && c.historiqueCopies.elements.isEmpty && m.courante == .outilPressePapiers, "vrai clic sur « Tout effacer » : vide (en mémoire aussi)")
        let fichiers = (try? FileManager.default.contentsOfDirectory(atPath: dossier.path)) ?? []
        verifier(!fichiers.contains { $0.lowercased().contains("presse") || $0.lowercased().contains("copie") }, "rien du presse-papiers n'est écrit sur le disque (\(fichiers.sorted()))")
        pose("carte Presse-papiers vide")
        // ⌘C reconnu au caractère (fabriqué, jamais envoyé) ; trois copies dans la même app, sans changer d'app : toutes vues
        let sourceTouches = CGEventSource(stateID: .privateState)
        func touche(_ code: CGKeyCode, _ f: CGEventFlags) -> CGEvent? { let e = CGEvent(keyboardEventSource: sourceTouches, virtualKey: code, keyDown: true); e?.flags = f; return e }
        if let codeC = (0..<128).map({ CGKeyCode($0) }).first(where: { touche($0, []).map { KeyMonitor.caractere($0) } == "c" }) {
            let clavier = KeyMonitor()
            var vues = 0
            clavier.onCopie = { vues += 1 }
            let avale = [touche(codeC, .maskCommand), touche(codeC, []), touche(codeC, [.maskCommand, .maskAlternate])].compactMap { $0 }
                .map { clavier.recevoir(type: .keyDown, event: $0) }
            verifier(vues == 1 && !avale.contains(true), "⌘C (touche « c » de ce clavier) vu une fois, jamais avalé ; « c » seul et ⌥⌘C ignorés (\(vues))")
        } else { verifier(false, "touche « c » introuvable sur ce clavier") }
        for t in ["un", "deux", "trois"] { pp.copier(ContenuCopie(texte: "extrait \(t)")); c.copieTapee(); pause(IlotControleur.delaiCopie + 0.2) }
        verifier(m.copies.map(\.titre) == ["extrait trois", "extrait deux", "extrait un"], "trois ⌘C dans la même app : les trois copies (\(m.copies.map(\.titre)))")
        clic(PlanPressePapiers.pointToutEffacer(m), 0.8)
        // ‹ Outils
        clic(CGPoint(x: PlanPressePapiers.zone(m.grille).minX + 30, y: PlanPressePapiers.zone(m.grille).minY + 13), 0.8)
        verifier(m.courante == .outils, "vrai clic sur « ‹ Outils » : la page Outils")

        // --- Reformuler : la dernière dictée, « Plus pro », « Copier », « Remplacer »
        clic(PlanCentre.centreRond(m, .reformuler), 1.0)
        verifier(m.courante == .outilReformuler && m.reformulation.texte == dictee && m.reformulation.etiquette.hasPrefix("Dernière dictée \u{00B7} Mail \u{00B7} "),
                 "vrai clic sur Reformuler : la dernière dictée (« \(m.reformulation.etiquette) »)")
        pose("carte Reformuler")
        clic(PlanReformuler.pointStyle(.pro, m), 0.1)
        verifier(m.reformulation.phase == .calcul && m.reformulation.style == .pro, "vrai clic sur « Plus pro » : « Verbe réécrit… »")
        attendre(2) { m.reformulation.phase == .calcul }; pause(0.7)
        verifier(demandes.count == 1 && demandes[0].0 == dictee && demandes[0].1 == .pro, "une seule demande au service de texte (simulé, aucun réseau), avec la dictée et « Plus pro »")
        verifier(m.reformulation.resultat?.hasPrefix("Bonjour, je vous confirme") == true && m.reformulation.resultat?.hasSuffix("Cordialement.") == true,
                 "le résultat, nettoyé (guillemets retirés), dans l'îlot")
        pose("carte Reformuler, résultat")
        verifier(Double(m.geo[2].x) - Double(g.hauteur) <= GeoIlot.profondeurCentre + 0.5, "la carte ne dépasse pas la hauteur du Centre (\(Int(m.geo[2].x - Double(g.hauteur))) pt)")
        clic(PlanReformuler.pointAction(false, m), 0.4)
        verifier(pp.ecrits.last?.texte == m.reformulation.resultat && m.reformulation.remarque == "Copié" && m.courante == .outilReformuler, "vrai clic sur « Copier » : dans le presse-papiers, « Copié »")
        selectionPossible = false
        clic(PlanReformuler.pointAction(true, m), 0.4)
        verifier(selectionsDemandees.last == dictee && colles.isEmpty && m.reformulation.remarque == "Copié : colle-le à la place" && m.courante == .outilReformuler,
                 "« Remplacer », la dictée introuvable dans le champ : rien n'est collé au hasard, le texte est copié et la carte le dit")
        selectionPossible = true
        clic(PlanReformuler.pointAction(true, m), 0.7)
        verifier(colles.last == m.reformulation.resultat && m.courante != .outilReformuler, "« Remplacer » : la dictée sélectionnée dans le champ, le texte réécrit collé à sa place, l'îlot se range")
        // le texte choisi, « En anglais »
        m.clicForme(); pause(0.8); m.ouvrirOutil(.outilReformuler); pause(0.9)
        clic(PlanReformuler.pointSource(.selection, m), 0.6)
        verifier(m.reformulation.source == .selection && m.reformulation.texte == selection?.texte && m.reformulation.etiquette == "Texte choisi \u{00B7} Mail" && m.reformulation.phase == .attente,
                 "vrai clic sur « Texte choisi » : la sélection de l'app au premier plan (simulée), l'ancien résultat effacé")
        clic(PlanReformuler.pointStyle(.anglais, m), 0.1)
        attendre(2) { m.reformulation.phase == .calcul }; pause(0.5)
        verifier(m.reformulation.resultat == "Hello Mrs Martin, I confirm our appointment on Tuesday." && demandes.last?.1 == .anglais, "« En anglais »")
        let sel0 = selectionsDemandees.count
        clic(PlanReformuler.pointAction(true, m), 0.7)
        verifier(colles.last == "Hello Mrs Martin, I confirm our appointment on Tuesday." && selectionsDemandees.count == sel0, "« Remplacer » sur le texte choisi : collé par-dessus la sélection (rien à chercher)")
        // pas de sélection : les boutons ne font rien ; le service en panne : la carte le dit
        selection = nil
        m.clicForme(); pause(0.8); m.ouvrirOutil(.outilReformuler); pause(0.9)
        let d0 = demandes.count
        clic(PlanReformuler.pointStyle(.court, m), 0.5)
        verifier(m.reformulation.texte == nil && demandes.count == d0 && m.reformulation.phase == .attente && m.courante == .outilReformuler,
                 "rien de choisi : « Choisis un texte… », « Plus court » ne demande rien, et le clic ne range pas l'îlot (\(m.courante))")
        let src = PlanReformuler.cadreSource(m, m.grille)
        clic(CGPoint(x: src.midX, y: src.midY), 0.5)
        verifier(m.courante == .outilReformuler, "un clic sur le texte de départ (rien à faire là) : l'îlot reste ouvert")
        clic(PlanReformuler.pointSource(.derniereDictee, m), 0.5)
        reponse = { _, _ in throw GroqErreur.http(500) }
        clic(PlanReformuler.pointStyle(.court, m), 0.1)
        attendre(2) { m.reformulation.phase == .calcul }; pause(0.4)
        verifier(m.reformulation.phase == .echec("Pas de réponse : réessaie"), "le service ne répond pas : « Pas de réponse : réessaie »")
        clic(CGPoint(x: PlanReformuler.zone(m.grille).minX + 30, y: PlanReformuler.zone(m.grille).minY + 13), 0.8)
        verifier(m.courante == .outils, "« ‹ Outils »")

        // --- Note rapide : la bande « Dicter une note », une dictée qui devient une note
        clic(PlanCentre.cadreBande(m, page: .outils).origin.applying(.init(translationX: 80, y: 20)), 0.9)
        verifier(m.courante == .outilNote && m.notes.isEmpty, "vrai clic sur « Dicter une note » : la carte Note rapide")
        pose("carte Note rapide vide")
        var occ = OccupationEncoche(); c.occupation = { occ }
        c.dicteeChange(enCours: true); occ.dictee = true; c.occupationChangee(); pause(0.4)
        verifier(m.cache, "fn maintenue : l'encoche de la dictée prend la place, l'îlot s'efface")
        let colles0 = colles.count
        verifier(c.intercepter("Rappeler le plombier jeudi pour le devis de la salle de bain."), "la dictée faite carte ouverte devient une note (pas collée)")
        c.dicteeChange(enCours: false); occ.dictee = false; c.occupationChangee(); pause(1.0)
        verifier(m.courante == .outilNote && m.notes.first?.texte == "Rappeler le plombier jeudi pour le devis de la salle de bain." && m.noteNeuve == m.notes.first?.id && colles.count == colles0,
                 "l'encoche rangée : l'îlot se rouvre sur la carte, la note en haut (mise en avant), rien de collé dans l'app")
        let fn = dossier.appendingPathComponent("notes.json")
        let attrs = try? FileManager.default.attributesOfItem(atPath: fn.path)
        verifier((attrs?[.posixPermissions] as? NSNumber)?.intValue == 0o600 && (try? String(contentsOf: fn, encoding: .utf8))?.contains("plombier") == true,
                 "gardée dans notes.json (0600, dossier de l'essai)")
        pose("carte Note rapide, une note")
        // rouverte toute seule, la carte n'est pas épinglée : Hugues reprend son mail sans cliquer, fn maintenue, ce n'est PAS une note
        verifier(!m.epingle, "la carte rouverte après la note n'est pas épinglée (pas de « Reste ouvert »)")
        c.panneau.simulerPointeur(forme: false)
        c.dicteeChange(enCours: true); c.dicteeChange(enCours: false)
        verifier(!c.intercepter("Bonjour Paul, voici le devis."), "carte rouverte seule, souris ailleurs : la dictée suivante va dans l'app, pas dans les notes")
        attendre(IlotMoteur.dureeNoteMontree + 1.5) { m.courante == .outilNote }
        verifier(m.courante != .outilNote && !m.fenetreOuverte, "la souris n'y est pas venue : la carte se range seule (\(m.courante))")
        // une dictée de plus d'une minute, la carte ouverte d'un clic : une note quand même (armée jusqu'au relâchement de fn)
        m.clicForme(); pause(0.8); m.ouvrirOutil(.outilNote); pause(0.9)
        c.dicteeChange(enCours: true); decaler(75); c.dicteeChange(enCours: false)
        let longue = c.intercepter("Une idée dictée pendant plus d\u{2019}une minute.")
        decaler(-75); pause(0.6)
        verifier(longue && m.notes.first?.texte == "Une idée dictée pendant plus d\u{2019}une minute." && colles.count == colles0,
                 "dictée de 75 s, carte ouverte : une note, rien de collé dans l'app")
        if let id = m.notes.first?.id, longue { m.surAction(.noteSupprimer(id)); pause(0.3) }
        // la page Outils : sa bande dit « maintiens fn », la dictée y devient une note aussi
        m.ouvrirOutil(.outilNote); pause(0.5); m.allerA(.outils); pause(0.8)
        c.dicteeChange(enCours: true); c.dicteeChange(enCours: false)
        let parBande = c.intercepter("Acheter du pain.")
        pause(0.6)
        verifier(parBande && m.notes.first?.texte == "Acheter du pain." && m.courante == .outilNote && colles.count == colles0,
                 "page Outils ouverte (bande « Dicter une note · maintiens fn ») : la dictée devient une note (\(m.courante))")
        if let id = m.notes.first?.id, parBande { m.surAction(.noteSupprimer(id)); pause(0.3) }
        // une dictée faite carte fermée : collée normalement
        m.fermer(); pause(0.6)
        c.dicteeChange(enCours: true); c.dicteeChange(enCours: false)
        verifier(!c.intercepter("Ceci est une dictée normale."), "carte fermée : une dictée normale, jamais mangée")
        c.occupation = { OccupationEncoche() }
        m.clicForme(); pause(0.8); m.ouvrirOutil(.outilNote); pause(0.9)
        // « Vers Notes » (simulé : AppleScript n'est jamais lancé dans l'essai)
        guard let id0 = m.notes.first?.id else { verifier(false, "il reste une note à envoyer vers Notes (\(m.notes.count) notes, \(c.listeNotes.notes.count) gardées)"); return }
        m.noteNeuve = id0; pause(0.3)
        clic(PlanNote.pointVersNotes(0, m), 0.1)
        verifier(m.envoisNotes[id0] == .enCours && versNotes.last == ListeNotes.html(m.notes[0].texte), "vrai clic sur « Vers Notes » : envoyé à l'app Notes (simulée), en HTML échappé")
        pause(0.5)
        verifier(m.envoisNotes[id0] == .fait && c.listeNotes.note(id0)?.versNotes == true && (try? String(contentsOf: fn, encoding: .utf8))?.contains("\"versNotes\" : true") == true,
                 "« Dans Notes », retenu dans le fichier")
        // supprimer : survol de la ligne, puis un vrai clic sur « × »
        c.panneau.envoyerSouris(.mouseMoved, en: CGPoint(x: PlanNote.cadreListe(m, m.grille).midX, y: PlanNote.cadreListe(m, m.grille).minY + 16)); pause(0.3)
        if m.survolNote != id0 { m.survolNote = id0; pause(0.3) }
        clic(PlanNote.pointSupprimer(0, m), 0.6)
        verifier(m.notes.isEmpty && c.listeNotes.notes.isEmpty && (try? String(contentsOf: fn, encoding: .utf8))?.contains("plombier") == false, "vrai clic sur « × » : supprimée (du fichier aussi)")
        // Notes refuse ; une liste qui dépasse défile
        notesAccepte = false
        let douze = ["Acheter des ampoules pour le salon", "Idée : un mode nuit pour l\u{2019}îlot", "Rappeler la banque pour le prêt", "Relire le devis",
                     "Écrire à Paul", "Commander le chêne", "Prendre rendez-vous chez le dentiste", "Payer la cantine", "Réserver le train de vendredi",
                     "Rendre les livres", "Arroser les tomates", "Envoyer les photos du chantier"]
        for (i, t) in douze.enumerated() { decaler(Double(i)); _ = c.ajouterNote(t) }
        decaler(-Double(douze.count * (douze.count - 1) / 2))
        m.ouvrirOutil(.outilNote); pause(0.9)
        let idr = m.notes[0].id
        clic(PlanNote.pointVersNotes(0, m), 0.6)
        verifier(m.envoisNotes[idr] == .refuse && c.listeNotes.note(idr)?.versNotes == false, "l'app Notes refuse (autorisation non donnée) : « Notes refuse », rien de retenu")
        pose("carte Note rapide, douze notes")
        verifier(PlanNote.depassement(m) > 0 && Double(m.geo[2].x) - Double(g.hauteur) <= GeoIlot.profondeurCentre, "douze notes : la liste dépasse, la carte reste à la hauteur du Centre")
        let pl = CGPoint(x: PlanNote.cadreListe(m, m.grille).midX, y: PlanNote.cadreListe(m, m.grille).midY)
        geste([-10, -20, -30], en: pl); pause(0.4)
        verifier(m.defilementNotes > 0 && m.courante == .outilNote, "vrai défilement sur la liste : elle défile (\(Int(m.defilementNotes)) pt), la carte reste")
        for _ in 0..<12 where m.defilementNotes < PlanNote.depassement(m) - 0.5 { geste([-30, -30, -30], en: pl) }
        pause(0.4)
        verifier(abs(m.defilementNotes - PlanNote.depassement(m)) < 0.5, "défilée au bout (\(Int(m.defilementNotes)) / \(Int(PlanNote.depassement(m))) pt)")
        // les lignes remontées hors de la liste ne couvrent plus l'en-tête : un vrai clic sur le titre ne fait rien, « ‹ Outils » répond
        clic(CGPoint(x: PlanNote.zone(m.grille).minX + EnteteOutil<ResteOuvert>.pilule + 60, y: PlanNote.zone(m.grille).minY + 13), 0.4)
        verifier(m.courante == .outilNote, "défilée au bout, un vrai clic sur le titre : rien ne se passe (\(m.courante))")
        clic(CGPoint(x: PlanNote.zone(m.grille).minX + 30, y: PlanNote.zone(m.grille).minY + 13), 0.8)
        verifier(m.courante == .outils, "défilée au bout, un vrai clic sur « ‹ Outils » : la page Outils (\(m.courante))")

        // --- « Modifier » sur la page Outils : « – » sur Reformuler, « + Reformuler », « OK »
        let entO = PlanCentre.cadreEntete(m.grille, .outils)
        clic(CGPoint(x: entO.maxX - EnteteCentre.pilule(EnteteCentre.titreModifier) / 2, y: entO.midY), 0.6)
        verifier(m.editionCentre && m.courante == .outils, "vrai clic sur « Modifier » (page Outils) : les outils tremblent")
        let r = PlanCentre.centreRond(m, .reformuler)
        clic(CGPoint(x: r.x - 21, y: r.y - 21), 0.7)
        verifier(m.rondsDe(.outils) == [.eveil, .pressePapiers, .notes, .groq], "vrai clic sur « – » de Reformuler : retiré (\(m.rondsDe(.outils)))")
        let pa = CGPoint(x: entO.minX + MesureIlot.texte(EnteteCentre.libelleAjouter, 12, .medium) + 6 + EnteteCentre.pastille(.reformuler) / 2, y: entO.midY)
        clic(pa, 0.7)
        verifier(m.rondsDe(.outils) == [.eveil, .pressePapiers, .notes, .groq, .reformuler], "vrai clic sur « + Reformuler » : revenu au bout (\(m.rondsDe(.outils)))")
        clic(PlanCentre.centreRond(m, .pressePapiers).applying(.init(translationX: -21, y: -21)), 0.7)
        clic(CGPoint(x: entO.maxX - EnteteCentre.pilule(EnteteCentre.titreOK) / 2, y: entO.midY), 0.7)
        verifier(!m.editionCentre && memoire == ["eveil", "notes", "groq", "reformuler", "note-rapide"], "« OK » : la page Outils enregistrée (\(memoire ?? []))")
        verifier(m.copies.isEmpty && c.compteurPressePapiers == nil, "Presse-papiers retiré : plus rien n'est gardé")
        let lectures1 = pp.lectures
        pp.copier(ContenuCopie(texte: "après le retrait")); m.fermer(); pause(0.5); m.clicForme(); pause(0.8); c.verifierPressePapiers()
        verifier(pp.lectures == lectures1 && m.copies.isEmpty, "… ni regardé : l'îlot s'ouvre, le presse-papiers n'est pas lu")
        verifier(DispositionCentre(identifiants: memoire, page: .outils) == m.dispositionOutils, "relu au lancement suivant : la même page")
        m.dispositionOutils = DispositionCentre(DispositionCentre.parDefautOutils, page: .outils); memoire = nil

        groq(c, verifier: verifier, attendre: attendre, clic: { clic($0, $1) }, pose: { pose($0) })

        // --- Réduire les animations : la page se pose d'un coup
        m.fermer(); pause(0.6)
        m.reduire = true
        m.clicForme(); pause(0.3); m.allerA(.outils)
        verifier(m.courante == .outils && m.geo.allSatisfy(\.fini), "Réduire les animations : la page Outils est posée d'un coup")
        m.reduire = false
        m.fermer(); pause(0.8)

        // --- Verbe se ferme : le Mac n'est plus gardé éveillé
        verifier(eveil.actif, "avant la fermeture : toujours gardé éveillé")
        c.arreterLesOutils()
        verifier(!eveil.actif && m.eveil == nil, "fermeture de Verbe : rendu")
    }

    /// Groq (12/11) : la jauge de la page Outils (vrai clic : le détail), les annonces (sous 15 %, limite atteinte : une fois chacune), la
    /// dictée passée par le Mac (bandeau la première fois, puis « Mac » dans les ailes), la langue du Mac en téléchargement. L'usage est
    /// fabriqué (aucun appel à Groq, aucun fichier lu) ; l'heure est celle de l'essai.
    @MainActor
    static func groq(_ c: IlotControleur, verifier: (Bool, String) -> Void, attendre: (Double, () -> Bool) -> Void, clic: (CGPoint, Double) -> Void, pose: (String) -> Void) {
        let m = c.moteur
        func pause(_ s: Double) { attendre(s) { true } }
        let large = ModeleWhisper.precis.identifiant, turbo = ModeleWhisper.rapide.identifiant
        func etat(minutesJour: Double, pause p: Double? = nil, turboAussi: Bool = false) -> EtatGroq {
            var k = CompteurGroq()
            let t = c.maintenant()
            if minutesJour > 0 { k.noterEnvoi(secondesAudio: minutesJour * 60, modele: large, a: t.addingTimeInterval(-3 * 3600)) }
            if let p {
                k.noterReponse(modele: large, statut: 429, entete: { $0 == "retry-after" ? "\(Int(p))" : nil }, messageErreur: "(ASD)", a: t)
                if turboAussi { k.noterReponse(modele: turbo, statut: 429, entete: { $0 == "retry-after" ? "\(Int(p))" : nil }, messageErreur: "(ASD)", a: t) }
            }
            return EtatGroq.calculer(k, modele: large, secours: turbo, a: t)
        }
        print("Groq : jauge, annonces, relais sur le Mac")
        var usage = etat(minutesJour: 42)
        c.lireEtatGroq = { _ in usage }
        c.lireProgressionParole = { nil }
        c.alerteGroq = AlerteGroq(); c.suiviRelais = RelaisDictee.Suivi()
        m.fermer(); pause(0.6)
        m.clicForme(); pause(0.8); m.allerA(.outils); pause(0.9)
        verifier(m.courante == .outils && m.etatCentre(.groq) == "42 min", "page Outils : la jauge de Groq, « 42 min » sous le rond (\(m.etatCentre(.groq)))")
        verifier(abs((m.groq?.utilise ?? 0) - 42.0 / 480) < 0.001, "l'anneau : 42 min sur 480 utilisés (\(String(format: "%.3f", m.groq?.utilise ?? 0)))")
        pose("page Outils avec la jauge de Groq")
        clic(PlanCentre.centreRond(m, .groq), 0.9)
        verifier(m.courante == .groq && m.bandeauVu?.ligne1 == "Groq aujourd\u{2019}hui : 42 min sur 480" && m.bandeauVu?.ligne2.hasPrefix("Tout va bien") == true,
                 "vrai clic sur la jauge : « \(m.bandeauVu?.ligne1 ?? "") · \(m.bandeauVu?.ligne2 ?? "") » (\(m.courante))")
        pose("bandeau détail de Groq")
        attendre(6) { m.bandeau != nil }
        // sous 15 % : annoncé une fois
        usage = etat(minutesJour: 420)
        c.groqChange(); pause(0.9)
        verifier(m.courante == .groq && m.bandeauVu?.ligne1 == "Groq : il reste 12 %" && m.bandeauVu?.ligne2 == "420 min sur 480 aujourd\u{2019}hui" && m.bandeauVu?.groq == .bas,
                 "sous 15 % : « \(m.bandeauVu?.ligne1 ?? "") · \(m.bandeauVu?.ligne2 ?? "") »")
        pose("bandeau Groq bientôt à sa limite")
        attendre(7) { m.bandeau != nil }
        c.groqChange(); pause(0.4)
        verifier(m.bandeau == nil, "toujours sous 15 % : pas redit (\(m.courante))")
        // la limite atteinte, le turbo aussi : « Groq en pause jusqu'à … · Dictée sur le Mac »
        usage = etat(minutesJour: 480, pause: 3600, turboAussi: true)
        c.groqChange(); pause(0.9)
        let heure = TexteGroq.quand(c.maintenant().addingTimeInterval(3600), a: c.maintenant())
        verifier(m.bandeauVu?.ligne1 == "Groq en pause jusqu\u{2019}à " + heure && m.bandeauVu?.ligne2 == "Dictée sur le Mac" && m.bandeauVu?.groq == .epuise,
                 "limite atteinte : « \(m.bandeauVu?.ligne1 ?? "") · \(m.bandeauVu?.ligne2 ?? "") »")
        verifier(c.reveilGroq != nil, "un seul réveil à la fin de la pause (aucune minuterie qui tourne)")
        pose("bandeau Groq en pause")
        attendre(7) { m.bandeau != nil }
        verifier(m.etatCentre(.groq).hasPrefix("Pause ") && m.groq?.utilise == 1, "sous le rond : « \(m.etatCentre(.groq)) », anneau plein")
        // la dictée passée par le Mac
        c.relaisDictee(.reseau); pause(0.9)
        verifier(m.courante == .groq && m.bandeauVu?.ligne1 == "Dicté sur le Mac" && m.bandeauVu?.ligne2 == "Pas de réseau" && m.bandeauVu?.groq == .relais,
                 "1re dictée passée par le Mac : « Dicté sur le Mac · Pas de réseau »")
        pose("bandeau Dicté sur le Mac")
        attendre(6) { m.bandeau != nil }
        c.relaisDictee(.reseau); pause(0.5)
        verifier(m.courante == .dicteeMac, "la suivante : « Mac » dans les ailes seulement (\(m.courante))")
        // replié dans les ailes : la fenêtre n'a pas un point sous la barre (les onglets des apps), on ne vérifie donc que la largeur
        attendre(1.4) { m.boucleActive }
        verifier(m.trace.bande <= Double(m.demiCamera) + GeoIlot.aileMax + 0.01 && !m.boucleActive, "ailes Mac : \(String(format: "%.2f", m.trace.bande - Double(m.demiCamera))) pt dans la barre (≤ 66), posé sans boucle")
        if let f = c.panneau.cadre {
            verifier(Double(f.width) >= 2 * m.trace.corps && Double(f.height) <= Double(m.geometrie.hauteur) + 0.5,
                     "ailes Mac : la fenêtre couvre les ailes (\(Int(f.width)) pt pour \(Int(2 * m.trace.corps))) sans descendre sous la barre (\(Int(f.height)) pt, trace \(String(format: "%.1f", m.trace.hauteur)))")
        }
        attendre(3) { m.bandeau != nil }
        verifier(m.bandeau == nil && m.courante == .repos, "les ailes partent seules (\(m.courante))")
        c.groqReussi()
        c.relaisDictee(.limite); pause(0.5)
        verifier(m.courante == .dicteeMac, "pour la limite (déjà annoncée) : les ailes seules")
        attendre(3) { m.bandeau != nil }
        // la langue du Mac en téléchargement
        c.relaisIndisponible("Le Mac télécharge le français \u{00B7} 42 %"); pause(0.9)
        verifier(m.bandeauVu?.ligne1 == "Dictée sur le Mac pas encore prête" && m.bandeauVu?.ligne2.hasSuffix("42 %") == true, "le Mac n'est pas prêt : la progression du téléchargement")
        attendre(6) { m.bandeau != nil }
        c.arreterGroq()
        verifier(c.reveilGroq == nil && c.observateurGroq == nil, "arrêt : plus de réveil ni d'observateur")
    }
}
