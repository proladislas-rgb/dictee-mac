import AppKit
import DicteeCore

/// La fausse app Raccourcis de l'essai : une bibliothèque en mémoire, ce qui a été préparé, ouvert et lancé. Rien n'est créé, signé, ouvert
/// ni lancé pour de vrai ; aucune Concentration ne s'allume. Appelée depuis la file du pilote : tout passe par un verrou.
final class RaccourcisFactices: @unchecked Sendable {
    private let verrou = NSLock()
    private var _liste: [RaccourciConcentration.Installe] = [.init(nom: "Météo du matin", identifiant: "11111111-2222-4333-8444-555555555555")]
    private var _prepares: [(Data, URL)] = []
    private var _ouverts: [URL] = []
    private var _lances: [(id: String, entree: String)] = []
    private var _repond = true
    private var _etat = ""

    private func avec<T>(_ f: () -> T) -> T { verrou.lock(); defer { verrou.unlock() }; return f() }
    var prepares: [(Data, URL)] { avec { _prepares } }
    var ouverts: [URL] { avec { _ouverts } }
    var lances: [(id: String, entree: String)] { avec { _lances } }
    /// Faux : Raccourcis ne répond pas (le raccourci échoue).
    var repond: Bool { get { avec { _repond } } set { avec { _repond = newValue } } }
    /// Ce que « Concentration actuelle » donne (vide : aucune).
    var etat: String { get { avec { _etat } } set { avec { _etat = newValue } } }
    /// Hugues clique « Ajouter le raccourci » dans Raccourcis : le raccourci entre dans la bibliothèque.
    func ajouter(_ nom: String, _ id: String) { avec { _liste.append(.init(nom: nom, identifiant: id)) } }
    func supprimer(_ id: String) { avec { _liste.removeAll { $0.identifiant == id } } }

    var systeme: SystemeConcentration {
        SystemeConcentration(
            lister: { [self] in avec { _liste } },
            preparer: { [self] d, f in avec { _prepares.append((d, f)) }; return true },
            ouvrir: { [self] f in avec { _ouverts.append(f) } },
            lancer: { [self] id, entree in
                avec {
                    _lances.append((id, entree))
                    guard _repond, _liste.contains(where: { $0.identifiant == id }) else { return nil }
                    return entree == RaccourciConcentration.Commande.lire.texte ? _etat + "\n" : RaccourciConcentration.reponseOK + "\n"
                }
            })
    }
}

extension IlotEssai {
    /// Les modes de Concentration (maquette design/maquettes/ilot-concentration.html, étapes 1 à 7) de bout en bout, dans la fenêtre
    /// invisible de l'essai, avec de VRAIS clics (NSEvent) et une fausse app Raccourcis : le rond du Centre, la carte des modes, le raccourci
    /// proposé au premier clic (et seulement là), le mode lancé quand Hugues revient de Raccourcis, la bannière d'une ligne, l'icône dans
    /// l'aile, la carte du mode au survol (« +30 min », « Arrêter », « Changer de mode »), l'arrêt d'un clic depuis le Centre, la relance
    /// d'un clic, la fin à l'heure (une seule échéance, revue au réveil du Mac), les échecs, le raccourci supprimé, la relecture du fichier.
    @MainActor
    static func concentration(_ c: IlotControleur, dossier: URL, decaler: (Double) -> Void, verifier: (Bool, String) -> Void,
                              attendre: (Double, () -> Bool) -> Void, relancer: () -> IlotControleur) {
        let m = c.moteur, g = m.geometrie, p = c.concentration
        let hc = Double(m.demiCamera), barre = Double(g.hauteur)
        func pause(_ s: Double) { attendre(s) { true } }
        func clic(_ pt: CGPoint, _ apres: Double = 0.6) {
            c.panneau.envoyerSouris(.leftMouseDown, en: pt); pause(0.06); c.panneau.envoyerSouris(.leftMouseUp, en: pt); pause(apres)
        }
        func refermer() { c.panneau.simulerPointeur(forme: false); m.fermer(); pause(0.9) }
        func posee() { attendre(1.6) { m.boucleActive } }
        func centre(_ r: CGRect) -> CGPoint { CGPoint(x: r.midX, y: r.midY) }
        func revenirDeRaccourcis() { NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didActivateApplicationNotification, object: NSWorkspace.shared) }

        print("Concentration")
        let fx = RaccourcisFactices()
        p.systeme = fx.systeme
        let fichier = dossier.appendingPathComponent("concentration.json")
        p.store = ConcentrationStore(url: fichier)
        p.dossierTemporaire = dossier
        c.lireMicros = { [] }; c.relireChoixMicro()
        m.disposition = DispositionCentre()
        refermer()
        attendre(IlotEssai.sousCharge(4)) { m.bandeau != nil }
        p.demarrer()
        pause(0.3)
        verifier(fx.lances.isEmpty && fx.prepares.isEmpty && p.echeance == nil, "au lancement, rien d'allumé : aucune commande vers Raccourcis, aucune échéance")

        // --- étape 1 : le rond « Concentration » du Centre, « Désactivée »
        c.panneau.simulerPointeur(forme: true); pause(1.0)
        verifier(m.courante == .centre && m.rondsCentre.contains(.concentration) && m.etatCentre(.concentration) == "Désactivée",
                 "le Centre a son rond « Concentration », « Désactivée » (étape 1) (\(m.courante), \(m.rondsCentre))")
        verifier(PlanCentre.cadreRonds(m).contains(PlanCentre.centreRond(m, .concentration)), "le rond est dans la rangée des ronds")

        // --- étape 2 : un clic, la carte des modes
        clic(PlanCentre.centreRond(m, .concentration), 0.9)
        posee()
        verifier(m.courante == .concentration && m.epingle, "un vrai clic sur le rond : la carte des modes, épinglée (\(m.courante))")
        verifier(abs(m.geo[2].x - (barre + MesuresConcentration.profondeurCarte)) < 0.5 && m.trace.bande <= hc + GeoIlot.aileMax + 0.01,
                 "la carte : \(Int(m.geo[2].x - barre)) pt sous la barre (290 attendus), ≤ 66 pt dans la barre")
        verifier(!m.boucleActive, "carte posée : aucune boucle (bouge encore : \(m.ceQuiBouge))")
        verifier(fx.lances.isEmpty, "sans raccourci, rien n'est lancé (pas même la lecture de l'état)")
        let gr = m.grille
        for mode in ModeConcentration.allCases {
            let r = PlanConcentration.cadre(mode, gr)
            verifier(r.maxY <= m.geo[2].x - 14 && r.minX >= -gr.corps(.concentration) + 16 - 0.5, "le bouton « \(mode.nom) » est dans la carte")
        }
        verifier(PlanConcentration.cadre(.jusquALArret, gr).maxX <= PlanConcentration.zone(gr).maxX + 0.5, "les trois durées tiennent sur une ligne (\(Int(PlanConcentration.cadre(.jusquALArret, gr).maxX)) ≤ \(Int(PlanConcentration.zone(gr).maxX)))")
        // une durée sans mode choisi : rien
        clic(centre(PlanConcentration.cadre(.uneHeure, gr)), 0.5)
        verifier(fx.lances.isEmpty && fx.prepares.isEmpty && m.courante == .concentration, "« 1 h » sans mode choisi : rien ne part, la carte reste")

        // --- étape 3 : Travail, le raccourci proposé UNE fois, puis 1 h
        clic(centre(PlanConcentration.cadre(.travail, gr)), 0.8)
        attendre(2) { fx.ouverts.isEmpty }
        verifier(m.concentration.choisi == .travail && m.courante == .concentration, "un vrai clic sur Travail : choisi, la carte reste")
        verifier(fx.prepares.count == 1 && fx.ouverts.count == 1 && fx.ouverts.first?.lastPathComponent == "Concentration Verbe.shortcut" && fx.lances.isEmpty,
                 "premier clic sur un mode : le raccourci est préparé et ouvert dans Raccourcis (« Ajouter le raccourci »), rien d'allumé")
        let contenu = fx.prepares.first.flatMap { try? PropertyListSerialization.propertyList(from: $0.0, format: nil) as? [String: Any] }
        let actionsRaccourci = (contenu?["WFWorkflowActions"] as? [[String: Any]])?.compactMap { $0["WFWorkflowActionIdentifier"] as? String } ?? []
        verifier(actionsRaccourci.filter { $0 == "is.workflow.actions.dnd.set" }.count == 10, "le raccourci préparé : les « Définir la concentration » des cinq modes")
        verifier(fx.prepares.first?.1.path.hasPrefix(dossier.path) == true, "le fichier signé attend dans le dossier temporaire (jamais ailleurs)")
        verifier(m.concentration.raccourciManquant && LegendeConcentration.texte(actif: nil, choisi: .travail, raccourciManquant: true).contains("Raccourcis"),
                 "la légende dit d'ajouter le raccourci dans Raccourcis")
        clic(centre(PlanConcentration.cadre(.personnel, gr)), 0.5)
        clic(centre(PlanConcentration.cadre(.travail, gr)), 0.5)
        verifier(fx.prepares.count == 1 && fx.ouverts.count == 1, "d'autres clics pendant que Raccourcis montre sa question : il n'est pas rouvert")
        clic(centre(PlanConcentration.cadre(.uneHeure, gr)), 0.8)
        verifier(fx.lances.isEmpty && m.concentration.actif == nil, "« 1 h » avant l'ajout : rien d'allumé, il attend le raccourci")
        // Hugues clique « Ajouter le raccourci » dans Raccourcis, puis revient (changement d'app)
        let idVerbe = "A0A0A0A0-1111-4222-8333-444444444444"
        fx.ajouter("Concentration Verbe", idVerbe)
        let t0 = c.maintenant()
        // la souris est partie dans Raccourcis (sur l'îlot, une bannière reste tant qu'elle est dessous)
        c.panneau.simulerPointeur(forme: false)
        revenirDeRaccourcis()
        attendre(3) { m.concentration.actif == nil }
        verifier(fx.lances.map(\.entree) == ["on:com.apple.focus.work"] && fx.lances.first?.id == idVerbe,
                 "Hugues revient de Raccourcis : le raccourci ajouté est reconnu, Travail part (« on:com.apple.focus.work », par son identifiant)")
        verifier(m.concentration.actif?.mode == .travail && m.concentration.actif?.duree == .uneHeure && abs((m.concentration.actif?.fin?.timeIntervalSince(t0) ?? 0) - 3600) < 5,
                 "Travail pendant 1 h")
        attendre(1) { m.bandeau?.vue != .concentrationLance }
        let ligne = m.bandeau?.ligne1 ?? ""
        verifier(m.bandeau?.vue == .concentrationLance && ligne.hasPrefix("Travail \u{00B7} jusqu\u{2019}à ") && !ligne.contains("\n") && m.courante == .concentrationLance,
                 "l'îlot se replie, la bannière d'une ligne : « \(ligne) » (étape 3)")
        posee()
        verifier(m.trace.bande <= hc + GeoIlot.aileMax + 0.01 && m.trace.couGauche >= hc + MesuresConcentration.cou - 0.5, "la bannière garde l'icône dans l'aile gauche, ≤ 66 pt dans la barre")
        let attrs = try? FileManager.default.attributesOfItem(atPath: fichier.path)
        let relu = (try? Data(contentsOf: fichier)).flatMap(MemoireConcentration.depuis)
        verifier(relu?.raccourci == idVerbe && relu?.actif?.mode == .travail && (attrs?[.posixPermissions] as? Int) == 0o600, "le fichier (0600) garde le raccourci et le mode")
        verifier(!FileManager.default.fileExists(atPath: fx.prepares.first?.1.deletingLastPathComponent().path ?? "/"), "le fichier signé temporaire est effacé une fois le raccourci ajouté")

        // --- étape 4 : replié, l'icône du mode dans l'aile gauche ; à droite, la caméra seule ; aucune minuterie
        attendre(IlotEssai.sousCharge(4)) { m.bandeau != nil }
        posee()
        verifier(m.courante == .concentrationCompact, "la bannière partie : l'icône du mode dans l'aile (\(m.courante))")
        verifier(abs(m.trace.couGauche - (hc + MesuresConcentration.cou)) < 0.5 && m.trace.cou <= hc + 0.5 && m.trace.bande <= hc + GeoIlot.aileMax + 0.01,
                 "aile gauche de 40 pt, rien à droite de la caméra (\(Int(m.trace.couGauche - hc)) / \(Int(m.trace.cou - hc)) pt)")
        let envoyees = p.commandesEnvoyees
        pause(2)
        verifier(!m.boucleActive && p.commandesEnvoyees == envoyees && p.echeance != nil, "au repos : aucune boucle, aucune commande, une seule échéance (la fin)")

        // --- étape 5 : survol, où en est le mode ; « +30 min »
        c.panneau.simulerPointeur(forme: true); pause(1.0)
        posee()
        verifier(m.courante == .concentrationStatut, "survol : où en est le mode (étape 5) (\(m.courante))")
        verifier(abs(m.geo[2].x - (barre + MesuresConcentration.profondeurStatut + GeoIlot.piedLecture)) < 0.5, "la carte du mode et son pied « Centre » (\(Int(m.geo[2].x - barre)) pt)")
        verifier(m.concentration.actif?.encore(a: c.maintenant()) == "encore 1 h 00" || m.concentration.actif?.encore(a: c.maintenant()) == "encore 59 min",
                 "« encore 1 h 00 » (\(m.concentration.actif?.encore(a: c.maintenant()) ?? ""))")
        clic(centre(PlanConcentration.cadrePlus(m.grille)), 0.6)
        verifier(abs((m.concentration.actif?.fin?.timeIntervalSince(t0) ?? 0) - 5400) < 5 && fx.lances.count == 1, "un vrai clic sur « +30 min » : 1 h 30 en tout, sans repasser par Raccourcis")
        verifier(((try? Data(contentsOf: fichier)).flatMap(MemoireConcentration.depuis))?.actif?.fin == m.concentration.actif?.fin, "la nouvelle fin est gardée dans le fichier")
        verifier(m.courante == .concentrationStatut, "la carte reste ouverte")
        // « Changer de mode » : la grille, Travail allumé ; « ‹ Centre » : le Centre, le rond dit « Travail »
        clic(centre(PlanConcentration.cadreChanger(m.grille)), 0.9)
        posee()
        verifier(m.courante == .concentration && m.concentration.actif?.mode == .travail, "un vrai clic sur « Changer de mode » : la grille, Travail allumé (\(m.courante))")
        let n0 = fx.lances.count
        clic(PlanConcentration.pointCentre(m.grille), 0.9)
        verifier(m.courante == .centre && m.etatCentre(.concentration) == "Travail", "« ‹ Centre » : le Centre ; sous le rond, « Travail »")
        verifier(fx.lances.count == n0, "la carte ouverte avec un mode allumé par Voxile : aucune lecture de l'état (ce que Voxile allume ne dépend pas d'elle)")

        // --- l'arrêt d'un clic depuis le Centre, puis la relance d'un clic (étape 7)
        clic(PlanCentre.centreRond(m, .concentration), 0.9)
        attendre(2) { m.concentration.actif != nil }
        verifier(fx.lances.last?.entree == "off:com.apple.focus.work" && m.concentration.actif == nil && p.echeance == nil, "un clic sur le rond allumé : Travail s'arrête (« off »), plus d'échéance")
        verifier(m.courante == .centre && m.etatCentre(.concentration) == "Travail \u{00B7} 1 h" && m.bandeau == nil,
                 "le Centre reste ouvert ; le rond se souvient : « Travail · 1 h » (étape 7), pas de bannière")
        clic(PlanCentre.centreRond(m, .concentration), 0.9)
        attendre(2) { m.concentration.actif == nil }
        verifier(fx.lances.last?.entree == "on:com.apple.focus.work" && m.concentration.actif?.duree == .uneHeure && m.courante == .centre,
                 "un clic sur « Travail · 1 h » : le mode repart sans rouvrir la carte (étape 7)")

        // --- étape 6 : la fin à l'heure (l'échéance, ou le réveil du Mac après une veille)
        refermer()
        attendre(IlotEssai.sousCharge(4)) { m.bandeau != nil }
        decaler(2 * 3600)
        let offAvant = fx.lances.filter { $0.entree.hasPrefix("off:") }.count
        // le réveil du Mac et l'échéance tombent ensemble : une seule extinction
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: NSWorkspace.shared)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: NSWorkspace.shared)
        attendre(3) { m.concentration.actif != nil }
        attendre(1) { m.bandeau?.vue != .concentrationFin }
        pause(0.5)
        verifier(fx.lances.last?.entree == "off:com.apple.focus.work" && m.concentration.actif == nil, "le Mac se réveille après l'heure : Travail s'éteint (« off »)")
        verifier(fx.lances.filter { $0.entree.hasPrefix("off:") }.count == offAvant + 1, "deux réveils d'affilée : une seule extinction, une seule bannière")
        verifier(m.bandeau?.vue == .concentrationFin && m.bandeau?.ligne1 == "Fin de Travail" && m.bandeau?.ligne2 == BanniereConcentration.finSous,
                 "« Fin de Travail » (étape 6), sans nombre de notifications inventé")
        // la bannière part à SON heure (décalée) : on l'attend avant de remettre l'horloge
        attendre(IlotEssai.sousCharge(6)) { m.bandeau != nil }
        decaler(-2 * 3600)

        // --- un échec : Raccourcis ne répond pas
        fx.repond = false
        c.panneau.simulerPointeur(forme: true); pause(1.0)
        clic(PlanCentre.centreRond(m, .concentration), 1.0)
        attendre(2) { m.concentration.occupe }
        verifier(m.concentration.actif == nil && m.concentration.message != nil && m.concentration.raccourciManquant == false,
                 "Raccourcis ne répond pas : rien d'allumé, l'échec est dit (\(m.concentration.message ?? "rien"), \(m.courante), \(fx.lances.last?.entree ?? ""))")
        fx.repond = true
        refermer(); attendre(IlotEssai.sousCharge(5)) { m.bandeau != nil }

        // --- le raccourci supprimé par Hugues : proposé de nouveau ; le nouveau est reconnu
        fx.supprimer(idVerbe)
        let preparesAvant = fx.prepares.count
        c.panneau.simulerPointeur(forme: true); pause(1.0)
        clic(PlanCentre.centreRond(m, .concentration), 1.0)
        attendre(2) { fx.prepares.count == preparesAvant }
        verifier(fx.prepares.count == preparesAvant + 1 && m.concentration.raccourciManquant && p.memoire.raccourci == nil,
                 "raccourci supprimé : Voxile l'oublie et le propose de nouveau")
        let idNeuf = "B1B1B1B1-1111-4222-8333-444444444444"
        fx.ajouter("Concentration Verbe", idNeuf)
        revenirDeRaccourcis()
        attendre(2) { p.memoire.raccourci == nil }
        verifier(p.memoire.raccourci == idNeuf && !m.concentration.raccourciManquant, "le nouveau raccourci est reconnu")
        clic(PlanCentre.centreRond(m, .concentration), 1.0)
        attendre(2) { m.concentration.actif == nil }
        verifier(fx.lances.last?.id == idNeuf && m.concentration.actif?.mode == .travail, "le rond relance avec le nouveau raccourci")

        // --- relu au lancement suivant (Verbe relancé)
        let c2 = relancer()
        c2.concentration.systeme = fx.systeme
        c2.concentration.store = ConcentrationStore(url: fichier)
        c2.concentration.demarrer()
        verifier(c2.moteur.concentration.actif?.mode == .travail && c2.concentration.memoire.raccourci == idNeuf && c2.concentration.echeance != nil,
                 "Voxile relancé : le mode, sa fin (une échéance) et le raccourci sont relus")
        c2.concentration.arreter()
        verifier(c2.concentration.echeance == nil, "arrêté : plus d'échéance")

        // --- éteint ; la carte ouverte lit le mode allumé ailleurs (une fois par minute au plus)
        clic(PlanCentre.centreRond(m, .concentration), 1.0)
        attendre(2) { m.concentration.actif != nil }
        verifier(m.concentration.actif == nil && p.echeance == nil, "éteint d'un clic")
        fx.etat = "Repos"
        p.agir(.changer); pause(0.9)
        attendre(2) { m.concentration.externe == nil }
        verifier(fx.lances.last?.entree == "etat" && m.concentration.externe == "Sommeil" && m.etatCentre(.concentration) == "Sommeil",
                 "la carte ouverte, rien d'allumé par Voxile : Raccourcis dit le mode allumé ailleurs (« Repos » → Sommeil)")
        let lectures = fx.lances.filter { $0.entree == "etat" }.count
        clic(PlanConcentration.pointCentre(m.grille), 0.6); p.agir(.changer); pause(0.6)
        verifier(fx.lances.filter { $0.entree == "etat" }.count == lectures, "rouverte tout de suite : pas de nouvelle lecture (une par minute au plus)")
        fx.etat = ""

        // --- l'heure venue, le raccourci supprimé entre-temps : Raccourcis ne s'ouvre jamais tout seul, la bannière le dit
        clic(centre(PlanConcentration.cadre(.travail, m.grille)), 0.5)
        clic(centre(PlanConcentration.cadre(.uneHeure, m.grille)), 0.8)
        attendre(2) { m.concentration.actif == nil }
        verifier(m.concentration.actif?.mode == .travail && fx.lances.last?.entree == "on:com.apple.focus.work", "depuis la carte : Travail, 1 h")
        refermer(); attendre(IlotEssai.sousCharge(5)) { m.bandeau != nil }
        fx.supprimer(idNeuf)
        let (prepares0, ouverts0) = (fx.prepares.count, fx.ouverts.count)
        decaler(2 * 3600)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: NSWorkspace.shared)
        attendre(3) { m.bandeau?.vue != .concentrationFin }
        verifier(fx.prepares.count == prepares0 && fx.ouverts.count == ouverts0 && m.bandeau?.ligne1 == "Travail est resté allumé"
                 && (m.bandeau?.ligne2 ?? "").contains("manque") && p.memoire.raccourci == nil,
                 "l'heure venue sans raccourci : Raccourcis ne s'ouvre pas tout seul, « Travail est resté allumé » (\(m.bandeau?.ligne1 ?? "rien"))")
        // la bannière part à SON heure (décalée) : on l'attend avant de remettre l'horloge
        attendre(IlotEssai.sousCharge(6)) { m.bandeau != nil }
        decaler(-2 * 3600)

        refermer()
        p.arreter()
        attendre(1.5) { m.boucleActive }
        verifier(p.echeance == nil && !m.boucleActive, "fin de la section : aucune échéance, aucune boucle (bouge encore : \(m.ceQuiBouge))")
        verifier(fx.lances.allSatisfy { $0.id == idVerbe || $0.id == idNeuf }, "Voxile n'a jamais lancé que SON raccourci (jamais « Météo du matin »)")
        m.concentration = AffichageConcentration()
        m.donneesChangees()
        pause(0.8)
    }
}
