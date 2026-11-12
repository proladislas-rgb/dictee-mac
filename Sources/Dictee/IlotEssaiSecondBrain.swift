import AppKit
import DicteeCore

extension IlotEssai {
    /// La case « Second Brain » (maquette design/maquettes/ilot-second-cerveau.html) de bout en bout, dans la fenêtre invisible de l'essai :
    /// le fichier d'état est un FAUX fichier dans un dossier temporaire (jamais le vrai ~/.config), les réglages restent en mémoire, l'ouverture
    /// d'un lien est capturée (rien n'est ouvert, aucune app n'est lancée). On vérifie : la case apparaît quand le fichier apparaît (dossier
    /// créé après coup, écriture atomique), disparaît sans fichier, ne dit que ce que le fichier dit, un clic appelle l'ouverture, un lien
    /// piégé ou un fichier cassé ne font rien, et la surveillance ne sonde pas (aucune relecture au repos).
    @MainActor
    static func secondBrain(_ c: IlotControleur, dossier: URL, verifier: (Bool, String) -> Void, attendre: (Double, () -> Bool) -> Void) {
        let m = c.moteur, g = m.geometrie
        let hc = Double(m.demiCamera), barre = Double(g.hauteur)
        func pause(_ s: Double) { attendre(s) { true } }
        func clic(_ p: CGPoint, _ apres: Double = 0.5) {
            c.panneau.envoyerSouris(.leftMouseDown, en: p); pause(0.06); c.panneau.envoyerSouris(.leftMouseUp, en: p); pause(apres)
        }
        func refermer() { c.panneau.simulerPointeur(forme: false); m.fermer(); pause(0.8) }

        print("Second Brain")
        // les réglages en mémoire, le faux ~/.config (un dossier qui n'existe pas encore), l'ouverture capturée
        var memoire = (propose: false, disposition: nil as [String]?)
        c.reglagesCentre = ReglagesCentre(
            microChoisi: { nil }, choisirMicro: { _ in }, bulleVue: { true }, marquerBulleVue: {}, centreUtilise: { true }, marquerCentreUtilise: {},
            disposition: { memoire.disposition }, enregistrerDisposition: { memoire.disposition = $0 },
            secondBrainPropose: { memoire.propose }, marquerSecondBrainPropose: { memoire.propose = true })
        c.reglagesCentre.dispositionOutils = { nil }
        c.reglagesCentre.enregistrerDispositionOutils = { _ in }
        m.disposition = DispositionCentre()
        c.lireMicros = { [] }; c.relireChoixMicro()
        let racine = dossier.appendingPathComponent("second-brain-essai", isDirectory: true)
        let config = racine.appendingPathComponent(".config", isDirectory: true)
        let dossierSB = config.appendingPathComponent("second-cerveau", isDirectory: true)
        let fichier = dossierSB.appendingPathComponent(FichierSecondCerveau.nom)
        try? FileManager.default.createDirectory(at: racine, withIntermediateDirectories: true)
        c.dossierSecondBrain = { dossierSB }
        var ouverts: [URL] = []
        c.ouvrir = { ouverts.append($0) }
        let appFausse = URL(fileURLWithPath: "/Applications/Second Brain.app")
        var appPresente = false
        var identifiantsDemandes: [[String]] = []
        c.appSecondBrain = { ids in identifiantsDemandes.append(ids); return appPresente ? appFausse : nil }
        // aucune app n'est interrogée pour de vrai : « une app sait ouvrir secondbrain:// » est un interrupteur de l'essai
        var gestionnairePresent = false
        c.gestionnaireSecondBrain = { _ in gestionnairePresent ? appFausse : nil }
        // les chemins de fichier : seul un document existant du faux dossier passe (jamais le vrai disque)
        let note = racine.appendingPathComponent("Plan.md")
        try? "# Plan".write(to: note, atomically: true, encoding: .utf8)
        c.existenceSecondBrain = { chemin in
            var d: ObjCBool = false
            let e = FileManager.default.fileExists(atPath: chemin, isDirectory: &d)
            return SecondCerveauIlot.Existence(existe: e && chemin.hasPrefix(racine.path), dossier: d.boolValue)
        }
        refermer()
        let debutJournal = (try? FileManager.default.attributesOfItem(atPath: Log.url.path)[.size] as? Int) ?? 0

        func ecrire(_ texte: String, atomique: Bool = true) { try? texte.data(using: .utf8)?.write(to: fichier, options: atomique ? .atomic : []) }
        // les dates du contrat final : AAAA-MM-JJ et ISO avec fuseau (le « maintenant » de l'essai est celui du contrôleur)
        func jourISO(_ jours: Int) -> String {
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
            return f.string(from: Calendar.current.date(byAdding: .day, value: jours, to: c.maintenant())!)
        }
        func contrat(lien: String? = "secondbrain://aujourdhui", messageLien: String? = "secondbrain://message/pierre", nouveautes: Int = 3) -> String {
            """
            { "version": 1, "maj": "\(ISO8601DateFormatter().string(from: c.maintenant().addingTimeInterval(-120)))",
              "resume": "Pierre t'a écrit · 3 choses demandées",
              "compteurs": { "nouveautes": \(nouveautes), "aToi": 5, "aRelancer": 2 },
              "messages": [ { "id": "pierre", "nom": "Pierre", "texte": "Pour vendredi : le plan, les chiffres et la liste des invités", "heure": "\(ISO8601DateFormatter().string(from: c.maintenant().addingTimeInterval(-3600)))", "resume": "3 choses demandées"\(messageLien.map { ", \"lien\": \"\($0)\"" } ?? "") },
                            { "id": "julie", "nom": "Julie", "texte": "Merci pour hier ! Je t'envoie les photos ce soir", "heure": null } ],
              "taches":   [ { "id": "t1", "texte": "Répondre aux 3 questions de Pierre", "echeance": "\(jourISO(1))", "lien": "secondbrain://chose/t1" },
                            { "id": "t2", "texte": "Relire le bail du local", "echeance": "\(jourISO(0))" }, { "id": "t3", "texte": "Réserver le train pour Lyon", "echeance": null } ],
              "relances": [ { "id": "ladislas", "nom": "Ladislas", "sujet": "le partenariat", "depuis": "\(jourISO(-40))" },
                            { "id": "marc", "nom": "Marc", "sujet": "le devis du site", "depuis": null, "lien": "\(note.path)" } ]\(lien.map { ", \"lien\": \"\($0)\"" } ?? "") }
            """
        }

        // --- sans dossier ni fichier : pas de case
        c.demarrerSecondBrain()
        pause(0.8)
        verifier(m.secondBrain == nil && !m.rondsCentre.contains(.secondBrain) && !m.disposition.elements.contains(.secondBrain), "sans dossier ni fichier : pas de case, aucun vide dans le Centre")
        c.panneau.simulerPointeur(forme: true); pause(1.0)
        verifier(m.courante == .centre && !m.rondsCentre.contains(.secondBrain), "le Centre s'ouvre sans bouton Second Brain")
        let hCentreSans = m.geo[2].x
        refermer()

        // --- le dossier apparaît (étape par étape), puis le fichier (écriture atomique) : la case apparaît toute seule
        try? FileManager.default.createDirectory(at: config, withIntermediateDirectories: true); pause(0.7)
        try? FileManager.default.createDirectory(at: dossierSB, withIntermediateDirectories: true); pause(0.7)
        verifier(m.secondBrain == nil, "un dossier vide : toujours pas de case")
        ecrire(contrat())
        attendre(4) { m.secondBrain == nil }
        verifier(m.secondBrain != nil, "le fichier apparaît dans un dossier créé après le lancement : la case apparaît (surveillance sans sondage)")
        verifier(memoire.propose && memoire.disposition?.contains("second-brain") == true && m.rondsCentre.contains(.secondBrain),
                 "son rond rejoint le Centre, une seule fois (réglage retenu), \(m.rondsCentre.map(\.rawValue).joined(separator: ", "))")
        verifier(m.etatCentre(.secondBrain) == "3 nouveautés" && ElementCentre.secondBrain.nom == "Second Brain", "sous le rond : « 3 nouveautés » ; nom « Second Brain »")

        // --- le Centre : le rond est là, Minuteur et Étagère n'ont pas bougé ; un clic ouvre la carte
        c.panneau.simulerPointeur(forme: true); pause(1.0)
        verifier(m.courante == .centre && abs(m.geo[2].x - hCentreSans) < 0.5, "Centre : même hauteur qu'avant (\(Int(m.geo[2].x)) pt) : Minuteur et Étagère ne descendent pas")
        let rondSB = PlanCentre.centreRond(m, .secondBrain)
        let cadreRonds = PlanCentre.cadreRonds(m)
        verifier(cadreRonds.contains(rondSB) && m.rondsCentre.count <= DispositionCentre.maxRonds, "le rond Second Brain est dans la rangée des ronds (\(m.rondsCentre.count) sur \(DispositionCentre.maxRonds))")
        if let cm = PlanCentre.cadre(.cases, m) { verifier(cm.maxY <= barre + GeoIlot.profondeurCentre, "les cases Minuteur / Étagère restent dans la forme du Centre (bas \(Int(cm.maxY)) pt)") }
        clic(rondSB, 0.9)
        let hCarte = barre + Double(PlanSecondBrain.profondeur(m))
        verifier(m.courante == .secondBrain && m.epingle, "clic sur le rond : la carte Second Brain s'ouvre (épinglée comme le Centre) (\(m.courante))")
        attendre(1.5) { m.boucleActive }
        verifier(abs(m.geo[2].x - hCarte) < 0.5 && Double(PlanSecondBrain.profondeur(m)) <= GeoIlot.profondeurCentre, "la carte épouse ses lignes : \(Int(m.geo[2].x)) pt de haut (\(Int(PlanSecondBrain.profondeur(m))) sous la barre, Centre : \(Int(GeoIlot.profondeurCentre)))")
        verifier(m.trace.bande <= hc + GeoIlot.aileMax + 0.01, "rien de plus de 66 pt dans la barre de chaque côté de la caméra (\(Int(m.trace.bande - hc)) pt)")
        verifier(!m.boucleActive, "carte posée : aucune boucle d'animation (bouge encore : \(m.ceQuiBouge))")
        if let f = c.panneau.cadre { verifier(Double(f.height) >= m.trace.hauteur, "la fenêtre couvre la carte") }
        let a = PlanSecondBrain.affichage(m)
        verifier(a.messages.count == 2 && a.taches.count == 3 && a.relances.count == 2 && a.lignes <= 7, "la carte montre 2 messages, 3 choses à toi, 2 relances (sept lignes)")
        verifier(m.visible(ExtraIlot.points), "les points de page restent (le Centre est allumé)")

        // --- le vide de la carte ne la range pas ; un clic sur « ‹ Centre » revient au Centre
        let vide = CGPoint(x: PlanSecondBrain.zone(m.grille).minX + 30, y: PlanSecondBrain.zone(m.grille).minY + 30 + CGFloat(MesuresSecondBrain.entete) + 12)
        clic(vide, 0.5)
        verifier(m.courante == .secondBrain && ouverts.isEmpty, "un clic dans le titre d'une partie (du vide) : rien ne s'ouvre, la carte reste")
        clic(PlanSecondBrain.pointCentre(m), 0.9)
        verifier(m.courante == .centre && ouverts.isEmpty, "« ‹ Centre » : retour au Centre (\(m.courante))")
        clic(rondSB, 0.9)
        verifier(m.courante == .secondBrain, "le rond rouvre la carte")

        // --- un clic sur une ligne ouvre SON lien (injecté, rien n'est ouvert pour de vrai) ; l'îlot se range
        if let p = PlanSecondBrain.pointLigne(.messages, 0, m) {
            clic(p, 0.9)
            verifier(ouverts.map(\.absoluteString) == ["secondbrain://message/pierre"], "clic sur le message de Pierre : son lien est ouvert (\(ouverts.map(\.absoluteString)))")
            verifier(m.courante != .secondBrain, "l'îlot se range après l'ouverture (\(m.courante))")
        } else { verifier(false, "la ligne du premier message existe") }
        refermer()
        c.panneau.simulerPointeur(forme: true); pause(1.0); clic(PlanCentre.centreRond(m, .secondBrain), 0.9)
        if let p = PlanSecondBrain.pointLigne(.taches, 0, m) {
            clic(p, 0.9)
            verifier(ouverts.last?.absoluteString == "secondbrain://chose/t1", "une tâche : son lien (secondbrain://chose/…)")
        }
        refermer()
        c.panneau.simulerPointeur(forme: true); pause(1.0); clic(PlanCentre.centreRond(m, .secondBrain), 0.9)
        if let p = PlanSecondBrain.pointLigne(.messages, 1, m) {
            clic(p, 0.9)
            verifier(ouverts.last?.absoluteString == "secondbrain://aujourdhui", "une ligne sans lien : le lien général du fichier")
        }
        refermer()
        c.panneau.simulerPointeur(forme: true); pause(1.0); clic(PlanCentre.centreRond(m, .secondBrain), 0.9)
        if let p = PlanSecondBrain.pointLigne(.relances, 1, m) {
            clic(p, 0.9)
            verifier(ouverts.last?.isFileURL == true && ouverts.last?.lastPathComponent == "Plan.md", "une relance dont le lien est un document qui existe : le document")
        }
        refermer()
        c.panneau.simulerPointeur(forme: true); pause(1.0); clic(PlanCentre.centreRond(m, .secondBrain), 0.9)
        let avant = ouverts.count
        clic(PlanSecondBrain.pointOuvrir(m), 0.9)
        verifier(ouverts.count == avant + 1 && ouverts.last?.absoluteString == "secondbrain://aujourdhui", "« Ouvrir Second Brain » : le lien général")
        refermer()

        // --- des liens piégés ne s'ouvrent pas ; sans lien, l'app si elle est installée (les deux identifiants), sinon rien
        ecrire(contrat(lien: "https://piege.exemple/x", messageLien: "javascript:alert(1)"))
        attendre(4) { m.secondBrain?.lien != "https://piege.exemple/x" }
        c.panneau.simulerPointeur(forme: true); pause(1.0); clic(PlanCentre.centreRond(m, .secondBrain), 0.9)
        let n0 = ouverts.count
        if let p = PlanSecondBrain.pointLigne(.messages, 0, m) { clic(p, 0.6) }
        verifier(ouverts.count == n0 && m.courante == .secondBrain, "message à lien piégé (javascript:), pas d'app : rien ne s'ouvre, la carte reste")
        appPresente = true
        if let p = PlanSecondBrain.pointLigne(.messages, 0, m) { clic(p, 0.9) }
        verifier(ouverts.last == appFausse && identifiantsDemandes.last == ["com.hugues.second-cerveau", "com.hugues.second-brain"], "pas de lien valable, aucune app pour secondbrain:// : l'app « Second Brain » installée (identifiant du contrat d'abord, l'autre en repli)")
        appPresente = false
        refermer()
        c.panneau.simulerPointeur(forme: true); pause(1.0); clic(PlanCentre.centreRond(m, .secondBrain), 0.9)
        verifier(m.courante == .secondBrain, "la carte est rouverte pour le cas suivant (\(m.courante))")
        gestionnairePresent = true
        if let p = PlanSecondBrain.pointLigne(.messages, 0, m) { clic(p, 0.9) }
        verifier(ouverts.last?.absoluteString == "secondbrain://aujourdhui", "pas de lien valable, une app sait ouvrir secondbrain:// : « Aujourd'hui » (secondbrain://aujourdhui)")
        gestionnairePresent = false
        refermer()

        // --- le fichier est modifié sur place (sans renommage) : le fichier lui-même est surveillé
        ecrire(contrat(nouveautes: 7), atomique: false)
        attendre(4) { m.etatCentre(.secondBrain) != "7 nouveautés" }
        verifier(m.etatCentre(.secondBrain) == "7 nouveautés", "écriture sur place (même fichier) : relue (« 7 nouveautés »)")
        ecrire(contrat(nouveautes: 4))
        attendre(4) { m.etatCentre(.secondBrain) != "4 nouveautés" }
        verifier(m.etatCentre(.secondBrain) == "4 nouveautés", "puis écriture atomique par-dessus : relue aussi (« 4 nouveautés »)")

        // --- une rafale d'écritures : une relecture, pas dix
        let r0 = c.secondBrainSource.relectures
        for i in 0..<10 { ecrire(contrat(nouveautes: 10 + i), atomique: i % 2 == 0); pause(0.02) }
        attendre(4) { m.etatCentre(.secondBrain) != "19 nouveautés" }
        pause(0.6)
        verifier(m.etatCentre(.secondBrain) == "19 nouveautés" && c.secondBrainSource.relectures - r0 <= 4, "dix écritures en 0,3 s : relues en \(c.secondBrainSource.relectures - r0) fois (coalescées), la dernière gagne")

        // --- au repos : aucune relecture, aucune boucle (le noyau prévient, rien ne sonde)
        let r1 = c.secondBrainSource.relectures
        pause(2.5)
        verifier(c.secondBrainSource.relectures == r1 && !m.boucleActive, "2,5 s sans changement : aucune relecture, aucune boucle (pas de minuterie, pas de sondage)")

        // --- un fichier cassé ou trop gros : la case disparaît, rien ne s'ouvre ; la carte ouverte revient au Centre
        c.panneau.simulerPointeur(forme: true); pause(1.0); clic(PlanCentre.centreRond(m, .secondBrain), 0.9)
        verifier(m.courante == .secondBrain, "carte ouverte avant le fichier cassé")
        let nOuverts = ouverts.count
        ecrire("{ ceci n'est pas du json ")
        attendre(4) { m.secondBrain != nil }
        pause(0.9)
        verifier(m.secondBrain == nil && !m.rondsCentre.contains(.secondBrain) && ouverts.count == nOuverts, "fichier cassé : la case disparaît, rien ne s'ouvre, rien ne plante")
        verifier(m.courante == .centre, "la carte ouverte revient au Centre (\(m.courante))")
        verifier(m.disposition.elements.contains(.secondBrain), "son rond n'est pas retiré de la disposition (il revient avec un fichier valable)")
        ecrire(contrat())
        attendre(4) { m.secondBrain == nil }
        verifier(m.secondBrain != nil && m.rondsCentre.contains(.secondBrain), "fichier réparé : la case revient")
        refermer()
        ecrire("{\"resume\": \"" + String(repeating: "x", count: SecondCerveauIlot.tailleMax + 50) + "\"}")
        attendre(4) { m.secondBrain != nil }
        verifier(m.secondBrain == nil, "plus de 64 Ko : la case disparaît")
        ecrire("{}")
        attendre(4) { m.secondBrain == nil }
        c.panneau.simulerPointeur(forme: true); pause(1.0); clic(PlanCentre.centreRond(m, .secondBrain), 0.9)
        verifier(m.courante == .secondBrain && PlanSecondBrain.affichage(m).lignes == 0 && abs(m.geo[2].x - (barre + Double(MesuresSecondBrain.vide + 14 + 26 + 8 + 42 + 14))) < 0.5, "fichier vide ({}) : la carte dit « Rien de neuf » (\(Int(m.geo[2].x)) pt)")
        refermer()

        // --- « Modifier » retire le rond : il ne revient pas tout seul quand le fichier change
        ecrire(contrat())
        attendre(4) { m.secondBrain?.compteurs.nouveautes != 3 }
        var d = m.disposition; d.retirer(.secondBrain); m.disposition = d; memoire.disposition = d.identifiants
        ecrire(contrat(nouveautes: 9))
        attendre(4) { m.secondBrain?.compteurs.nouveautes != 9 }
        pause(0.5)
        verifier(!m.rondsCentre.contains(.secondBrain) && m.disposition.aAjouter(disponible: m.disponibleDansLeCentre).contains(.secondBrain),
                 "rond retiré : il ne revient pas tout seul, « Ajouter : » le propose (le fichier existe)")

        // --- le fichier disparaît, puis son dossier : la case disparaît ; un dossier détruit puis recréé est suivi
        try? FileManager.default.removeItem(at: fichier)
        attendre(4) { m.secondBrain != nil }
        verifier(m.secondBrain == nil, "fichier supprimé : la case disparaît")
        try? FileManager.default.removeItem(at: dossierSB); pause(0.7)
        try? FileManager.default.createDirectory(at: dossierSB, withIntermediateDirectories: true); pause(0.7)
        ecrire(contrat())
        attendre(4) { m.secondBrain == nil }
        verifier(m.secondBrain != nil, "dossier détruit puis recréé avec un fichier : suivi, la case revient")

        // --- aucun contenu du fichier dans le journal
        // (seulement ce qui a été écrit pendant cette section)
        if let tout = try? Data(contentsOf: Log.url), tout.count >= debutJournal {
            let journal = String(decoding: tout.dropFirst(debutJournal), as: UTF8.self)
            verifier(!journal.contains("Pierre") && !journal.contains("Ladislas") && !journal.contains("devis du site") && !journal.contains("secondbrain://") && !journal.contains("Plan.md"),
                     "journal : ni nom, ni texte, ni lien venus du fichier")
        }

        c.secondBrainSource.arreter(); c.secondBrainSource.attendreLaFile()
        try? FileManager.default.removeItem(at: racine)
        c.secondBrainLu(nil)
        refermer()
    }
}
