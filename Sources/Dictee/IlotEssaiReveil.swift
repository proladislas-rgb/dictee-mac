import AppKit
import DicteeCore

extension IlotEssai {
    /// Le Réveil et le Calendrier (maquette ilot-bibliotheque.html, étapes 7 à 13), de bout en bout, dans la fenêtre invisible de l'essai :
    /// de VRAIS clics remis à la fenêtre (onglet « Réveil », 9:00, « Autre… », − / +, « OK », « Annuler », « Encore 10 min », rond
    /// Calendrier, « Rejoindre », « Noter la réunion »). Rien du vrai système : le réveil dans un fichier temporaire, l'heure décalée (jamais
    /// d'attente de 10 h), aucun son (compteur), l'écran jamais rallumé (compteur), le calendrier jamais demandé ni lu (fermetures), aucun
    /// lien ouvert (capturé), aucune prise de notes lancée (capturée), les réglages en mémoire.
    @MainActor
    static func reveilEtCalendrier(_ c: IlotControleur, dossier: URL, verifier: (Bool, String) -> Void, attendre: (Double, () -> Bool) -> Void,
                                   relancer: () -> IlotControleur) {
        let m = c.moteur
        let hc = Double(m.demiCamera), barre = Double(m.geometrie.hauteur)
        func pause(_ s: Double) { attendre(s) { true } }
        func clic(_ p: CGPoint, _ apres: Double = 0.5) {
            c.panneau.envoyerSouris(.leftMouseDown, en: p); pause(0.06); c.panneau.envoyerSouris(.leftMouseUp, en: p); pause(apres)
        }
        func refermer() { c.panneau.simulerPointeur(forme: false); m.fermer(); pause(0.8) }
        func poseeSurLaCible() { attendre(1.5) { !m.geo.allSatisfy(\.fini) } }
        // l'heure, décalée à volonté (rendue à la fin)
        let maintenantAvant = c.maintenant
        var decalage = 0.0
        c.maintenant = { Date().addingTimeInterval(decalage) }
        // ce qui serait réel : capturé
        var sonneries = 0, ecrans = 0, notes = 0
        var liens: [URL] = []
        var colles: [String] = []
        let (sonsAvant, ecranAvant, ouvrirAvant, noterAvant, collerAvant) = (c.sons, c.allumerEcran, c.ouvrir, c.surNoter, c.surColler)
        c.surColler = { colles.append($0) }
        c.sons.reveil = { sonneries += 1 }
        c.allumerEcran = { ecrans += 1 }
        c.ouvrir = { liens.append($0) }
        c.surNoter = { _ in notes += 1 }
        // les réglages en mémoire : le minuteur allumé, le calendrier éteint, le Centre par défaut (le calendrier compris)
        var memoire = (minuteur: true, calendrier: false, allume: 0)
        c.reglagesCentre.minuteurActif = { memoire.minuteur }
        c.reglagesCentre.allumerMinuteur = { memoire.minuteur = true; memoire.allume += 1 }
        c.reglagesCentre.calendrier = { memoire.calendrier }
        c.reglagesCentre.reglerCalendrier = { memoire.calendrier = $0 }
        defer {
            c.maintenant = maintenantAvant; c.sons = sonsAvant; c.allumerEcran = ecranAvant; c.ouvrir = ouvrirAvant; c.surNoter = noterAvant
            c.surColler = collerAvant
            c.annulerLeReveil()
        }
        let fichier = c.reveilStore.url
        let fm = FileManager.default
        c.lireMicros = { [] }; c.relireChoixMicro()
        if c.minuteur != nil { c.agir(.minuteurArreter) }
        c.lecture.modele.morceau = nil; c.lecture.surIlot(false)
        m.disposition = DispositionCentre()
        refermer()

        print("Le Réveil")
        // --- étape 7 : l'onglet « Réveil » de la case Minuteur, de vrais clics
        m.clicForme(); pause(0.9)
        verifier(m.courante == .centre && m.ongletMontre == .minuteur, "îlot vide, un clic : le Centre, la case sur « Minuteur » (\(m.courante))")
        var cm = PlanCentre.cadreCase(m, .minuteur)
        let ce = PlanCentre.cadreCase(m, .etagere)
        verifier(abs(Double(cm.width / (cm.width + ce.width)) - 1.16 / 2) < 0.01, "cases : Minuteur \(Int(cm.width)) pt, Étagère \(Int(ce.width)) pt (1,16 / 0,84, maquette)")
        let yOnglets = cm.minY + CaseMinuteur.haut + CaseMinuteur.selecteur / 2
        let xOnglets = cm.minX + CaseMinuteur.cote + 18 + 7 + 2
        clic(CGPoint(x: xOnglets + SelecteurMinuteur.largeurOnglet("Minuteur") + SelecteurMinuteur.largeurOnglet("Réveil") / 2, y: yOnglets), 0.4)
        verifier(m.ongletMontre == .reveil && m.epingle && m.courante == .centre, "vrai clic sur « Réveil » : l'onglet change, le Centre reste ouvert")
        let place = cm.width - 2 * CaseMinuteur.cote
        let rangee = 3 * CapHeure.largeur("7:00") + CapHeure.largeur(CaseMinuteur.autre) + 3 * CaseMinuteur.espaceHeures
        verifier(rangee <= place && 18 + 7 + SelecteurMinuteur.largeur <= place,
                 "7:00 · 8:00 · 9:00 · Autre… (\(Int(rangee)) pt) et « Minuteur · Réveil » tiennent dans la case (\(Int(place)) pt), sans rien serrer")
        let yHeures = cm.minY + CaseMinuteur.milieuRangee
        func xHeure(_ i: Int) -> CGFloat { cm.minX + CaseMinuteur.cote + CGFloat(i) * (CapHeure.largeur("7:00") + CaseMinuteur.espaceHeures) + CapHeure.largeur("7:00") / 2 }
        let xAutre = cm.minX + CaseMinuteur.cote + 3 * (CapHeure.largeur("7:00") + CaseMinuteur.espaceHeures) + CapHeure.largeur(CaseMinuteur.autre) / 2
        clic(CGPoint(x: xHeure(2), y: yHeures), 0.5)
        let attr = try? fm.attributesOfItem(atPath: fichier.path)
        verifier(c.reveil?.heure == 9 && c.reveil?.minute == 0 && m.reveil == c.reveil && m.courante == .centre && m.bandeau == nil,
                 "vrai clic sur « 9:00 » : réveil réglé, sans bandeau, le Centre reste ouvert (\(c.reveil?.libelle() ?? "rien"))")
        verifier((attr?[.posixPermissions] as? NSNumber)?.intValue == 0o600 && fm.fileExists(atPath: fichier.path),
                 "gardé dans un fichier 0600 (Application Support ; ici, le dossier de l'essai)")
        if let r = c.reveil {
            let j = ReveilIlot.jour(r.sonnerie, maintenant: c.maintenant())
            // le jour dépend de l'heure de l'essai : avant 9 h, « aujourd'hui », qui ne tient pas toujours (il n'est alors pas écrit,
            // l'heure en ambre suffit : CaseMinuteur.droite) ; « demain », le cas courant, doit tenir
            verifier(CaseMinuteur.jourTient("demain", m) && abs(r.sonnerie.timeIntervalSince(ReveilIlot.prochaine(heure: 9, minute: 0, apres: c.maintenant()))) < 1,
                     "« demain » tient en haut à droite de la case, mesuré (ce matin : « \(j) », \(CaseMinuteur.jourTient(j, m) ? "écrit" : "pas écrit, l'heure suffit"))")
        }
        verifier(m.resolution.principal == .reveilCompact && m.resolution.survol == .centre, "derrière le Centre, l'îlot replié est déjà le réveil")
        clic(CGPoint(x: xHeure(2), y: yHeures), 0.5)
        verifier(c.reveil == nil && !fm.fileExists(atPath: fichier.path) && m.courante == .centre, "second clic sur « 9:00 » (en ambre) : annulé, le fichier est effacé")
        // « Autre… » : − et + par 15 min, « OK » ; pas de clavier
        clic(CGPoint(x: xAutre, y: yHeures), 0.4)
        verifier(m.reveilAutre.map { $0.heure == 7 && $0.minute == 30 } == true && !c.panneau.clavierPris, "vrai clic sur « Autre… » : 7:30, − et + (le clavier n'est pas pris)")
        let xMoins = cm.minX + CaseMinuteur.cote + 14
        let xPlus = cm.minX + CaseMinuteur.cote + 28 + 6 + CaseMinuteur.largeurHeure + 6 + 14
        clic(CGPoint(x: xPlus, y: yHeures), 0.25); clic(CGPoint(x: xPlus, y: yHeures), 0.25); clic(CGPoint(x: xMoins, y: yHeures), 0.25)
        verifier(m.reveilAutre.map { $0.heure == 7 && $0.minute == 45 } == true && c.reveil == nil, "vrais clics + + − : 7:45 (rien n'est réglé avant « OK »)")
        let xOK = cm.minX + CaseMinuteur.cote + 28 + 6 + CaseMinuteur.largeurHeure + 6 + 28 + 6 + 2 + (MesureIlot.texte("OK", 12.5, .semibold) + 22) / 2
        clic(CGPoint(x: xOK, y: yHeures), 0.5)
        verifier(c.reveil?.heure == 7 && c.reveil?.minute == 45 && m.reveilAutre == nil && m.courante == .centre, "vrai clic sur « OK » : réveil à 7:45, les heures proposées reviennent")
        clic(CGPoint(x: xAutre, y: yHeures), 0.5)
        verifier(c.reveil == nil, "7:45 a pris la place d'« Autre… », en ambre : un clic l'annule")
        clic(CGPoint(x: xHeure(0), y: yHeures), 0.4)
        verifier(c.reveil?.heure == 7, "vrai clic sur « 7:00 » : réglé")
        // « Autre… » s'ouvre sur l'heure réglée (7:00) : « OK » la CONFIRME (il ne l'annule pas, contrairement à un 2e clic sur la pastille)
        clic(CGPoint(x: xAutre, y: yHeures), 0.4)
        verifier(m.reveilAutre.map { $0.heure == 7 && $0.minute == 0 } == true, "vrai clic sur « Autre… », réveil à 7:00 : le réglage s'ouvre sur 7:00")
        clic(CGPoint(x: xOK, y: yHeures), 0.5)
        verifier(c.reveil?.heure == 7 && c.reveil?.minute == 0 && m.reveilAutre == nil && fm.fileExists(atPath: fichier.path),
                 "vrai clic sur « OK » sans rien changer : le réveil de 7:00 reste réglé (rien n'est annulé en silence)")
        clic(CGPoint(x: xAutre, y: yHeures), 0.4); clic(CGPoint(x: xPlus, y: yHeures), 0.25); clic(CGPoint(x: xMoins, y: yHeures), 0.25)
        clic(CGPoint(x: xOK, y: yHeures), 0.5)
        verifier(c.reveil?.heure == 7 && c.reveil?.minute == 0 && m.reveilAutre == nil, "+ puis − puis « OK » (de nouveau 7:00) : toujours réglé")
        // le réveil annulé pendant le réglage « Autre… » (bandeau, réglage éteint) : − 7:00 + OK disparaît avec lui
        clic(CGPoint(x: xAutre, y: yHeures), 0.4)
        c.agir(.reveilAnnuler); pause(0.3)
        verifier(c.reveil == nil && m.reveilAutre == nil, "réveil annulé pendant « Autre… » : la rangée − / + / OK s'en va, les heures proposées reviennent")
        clic(CGPoint(x: xHeure(0), y: yHeures), 0.4)
        verifier(c.reveil?.heure == 7, "vrai clic sur « 7:00 » : de nouveau réglé")
        // le Centre se range : l'îlot garde le réveil dans ses ailes (≤ 66 pt), rien ne tourne au repos
        m.clicAilleurs(); pause(0.9); poseeSurLaCible()
        verifier(m.courante == .reveilCompact && m.ongletMinuteur == nil, "clic ailleurs : replié, le réveil dans l'aile gauche, « 7:00 » dans la droite (\(m.courante))")
        verifier(m.trace.bande - hc <= GeoIlot.aileMax + 0.01 && abs(m.trace.hauteur - barre) < 0.5,
                 "réveil replié : \(Int(m.trace.bande - hc)) pt de chaque côté de la caméra dans la barre (≤ 66), rien sous la barre")
        if let f = c.panneau.cadre { verifier(Double(f.height) <= barre + 6.5, "fenêtre du réveil replié : \(Int(f.width)) × \(Int(f.height)) pt, aucun clic pris sous la barre") }
        attendre(1.0) { m.boucleActive }
        verifier(!m.boucleActive, "réveil replié et posé : aucune boucle d'animation (bouge encore : \(m.ceQuiBouge))")
        c.panneau.simulerPointeur(forme: true); pause(0.9)
        verifier(m.courante == .centre && m.ongletMontre == .reveil, "survol du réveil : le Centre s'ouvre sur l'onglet Réveil")
        refermer()
        // une vidéo arrive : elle prend l'îlot, le réveil passe dans la bulle
        c.lecture.modele.morceau = MorceauEnCours(titre: "Album · Titre 3", app: "essai.lecture", joue: true, duree: 214, position: 97)
        c.lecture.surIlot(true); pause(1.2)
        verifier(m.courante == .lectureCompact && m.pastille == .reveil, "une vidéo : elle prend l'îlot, le réveil dans la bulle")
        c.lecture.modele.morceau = nil; c.lecture.surIlot(false); pause(1.0)
        verifier(m.courante == .reveilCompact, "la vidéo finie : le réveil revient dans les ailes")

        // --- étape 8 : à la voix, l'îlot FERMÉ (aucune dictée armée) ; rien n'est collé
        c.annulerLeReveil(); refermer()
        verifier(c.intercepter("Réveille-moi à 9 h.") == true && c.reveil?.heure == 9 && c.reveil?.minute == 0,
                 "îlot fermé, « réveille-moi à 9 h » : réveil réglé, la dictée n'est PAS collée")
        pause(0.5)
        verifier(m.bandeau?.vue == .reveilRegle && m.courante == .reveilRegle && (m.bandeauVu?.ligne2.contains("rien n\u{2019}a été collé") ?? false),
                 "bandeau « Réveil réglé · 9:00 » (« … rien n'a été collé »), avec « Annuler »")
        verifier(m.trace.bande - hc <= GeoIlot.aileMax + 0.01, "bandeau : rien de plus de 66 pt dans la barre")
        verifier(c.intercepter("Dis-lui de me réveiller à 9 h") == false && c.intercepter("Le réveil sonne à 7 h, puis on part.") == false,
                 "une phrase qui CONTIENT un réveil sans l'être : collée normalement")
        // « Annuler » : un vrai clic, pendant que le bandeau est là
        if let mesure = m.contenus[.reveilRegle] {
            let z = m.grille.zoneAnnonce(.reveilRegle)
            let l = MesureIlot.bouton(ContenuAnnonce.Bouton(titre: "Annuler"))
            verifier(mesure > 0, "le bandeau épouse son contenu (\(Int(mesure)) pt)")
            clic(CGPoint(x: z.maxX - l / 2, y: z.midY), 0.6)
        }
        verifier(c.reveil == nil && m.bandeau == nil, "vrai clic sur « Annuler » : plus de réveil, le bandeau part")
        verifier(colles == ["Réveille-moi à 9 h."], "« Annuler » recolle la phrase dictée (elle était peut-être pour quelqu'un) : \(colles)")
        // îlot fermé : seulement un ORDRE ; « Le réveil à 7 h. » (écrit à quelqu'un) est collé normalement
        verifier(c.intercepter("Le réveil à 7 h.") == false && c.intercepter("Réveil à 7 h demain.") == false && c.intercepter("Une alarme à 7 h.") == false
                 && c.reveil == nil, "îlot fermé, « Le réveil à 7 h. », « Réveil à 7 h demain. » : collés normalement, aucun réveil")
        // « Minuteur et réveil » éteint dans Réglages › Îlot : le réveil réglé est annulé, et ne sonne jamais
        c.reglerLeReveil(heure: 6, minute: 30, aLaVoix: false)
        memoire.minuteur = false
        c.appliquerLeReglageDuReveil(); pause(0.3)
        verifier(c.reveil == nil && m.reveil == nil && !fm.fileExists(atPath: fichier.path), "« Minuteur et réveil » éteint : le réveil de 6:30 est annulé (fichier effacé, aile vide)")
        c.reglerLeReveil(heure: 6, minute: 30, aLaVoix: false)
        verifier(memoire.minuteur && c.reveil != nil, "réglé de nouveau d'un clic : le réglage se rallume (comme 5 · 10 · 25)")
        memoire.minuteur = false
        let sAvantEteint = sonneries
        decalage += c.reveil!.sonnerie.timeIntervalSince(c.maintenant()) + 5
        c.verifierLeReveil(); pause(0.4)
        verifier(m.alerte == nil && sonneries == sAvantEteint && ecrans == 0 && c.reveil == nil, "réglage éteint à l'heure du réveil : rien ne sonne, l'écran n'est pas rallumé")
        refermer()
        verifier(c.intercepter("réveille-moi à 9 h") == false && c.reveil == nil, "minuteur éteint dans les réglages : la phrase est collée (rien n'est mangé)")
        memoire.minuteur = true
        verifier(c.intercepter("Mets un réveil à 7 h 30.") == true && c.reveil?.minute == 30, "îlot fermé, « mets un réveil à 7 h 30 » : 7:30")
        verifier(m.bandeauVu?.texteDicte == "Mets un réveil à 7 h 30.", "le bandeau garde la phrase (pour « Annuler »), jamais le fichier")
        attendre(4.5) { m.bandeau != nil }
        verifier(m.courante == .reveilCompact, "le bandeau parti : le réveil dans les ailes (\(m.courante))")

        // --- étape 9 : à l'heure, il sonne (écran rallumé, son, vibration) ; « Encore 10 min », « OK »
        guard let r = c.reveil else { verifier(false, "un réveil réglé avant la sonnerie"); return }
        decalage += r.sonnerie.timeIntervalSince(c.maintenant()) - 30
        c.verifierLeReveil(); pause(0.3)
        verifier(m.alerte == nil && c.reveil != nil, "30 s avant l'heure : rien ne sonne")
        decalage += 31
        let (s0, e0) = (sonneries, ecrans)
        c.verifierLeReveil(); pause(1.0)
        verifier(m.alerte?.vue == .reveilFini && sonneries == s0 + 1 && ecrans == e0 + 1 && c.reveil == nil && !fm.fileExists(atPath: fichier.path),
                 "à 7:30 : l'alerte « Réveil · 7:30 », le son (une fois), l'écran rallumé, le fichier effacé")
        verifier(m.trace.bande - hc <= GeoIlot.aileMax + 0.01 && Double(m.trace.hauteur) > barre + 60, "l'alerte descend sous la barre, rien de plus de 66 pt dans la barre")
        let za = m.grille.zoneAnnonce(.reveilFini, haut: 20, bas: 20)
        let lOK = MesureIlot.bouton(ContenuAnnonce.Bouton(titre: "OK")), lEncore = MesureIlot.bouton(ContenuAnnonce.Bouton(titre: "Encore 10 min"))
        clic(CGPoint(x: za.maxX - lOK - ContenuAnnonce.espaceBoutons - lEncore / 2, y: za.midY), 0.8)
        verifier(m.alerte == nil && c.reveil?.repousse == true && abs((c.reveil?.sonnerie.timeIntervalSince(c.maintenant()) ?? 0) - 600) < 3 && fm.fileExists(atPath: fichier.path),
                 "vrai clic sur « Encore 10 min » : il sonnera dans 10 min (gardé dans le fichier)")
        poseeSurLaCible()
        verifier(m.courante == .reveilCompact, "replié : l'aile montre la nouvelle heure (\(c.reveil?.libelle() ?? "?"))")
        // pendant une dictée, il attend la fin (aucun son qui pourrait être capté)
        var occ = OccupationEncoche(); c.occupation = { occ }
        occ.dictee = true; c.occupationChangee(); pause(0.4)
        decalage += 601
        c.verifierLeReveil(); pause(0.4)
        verifier(m.alerte == nil && sonneries == s0 + 1, "il sonne PENDANT une dictée : il attend (aucun son)")
        occ.dictee = false; c.occupationChangee(); c.occupation = { OccupationEncoche() }; pause(1.0)
        verifier(m.alerte?.vue == .reveilFini && sonneries == s0 + 2, "la dictée finie : il sonne")
        clic(CGPoint(x: za.maxX - lOK / 2, y: za.midY), 0.8)
        verifier(m.alerte == nil && c.reveil == nil && m.courante == .repos, "vrai clic sur « OK » : arrêté, l'îlot redevient vide")
        // « Réduire les animations » : l'alerte est posée tout de suite, rien ne se secoue
        m.reduire = true
        c.reglerLeReveil(heure: 6, minute: 0, aLaVoix: false)
        decalage += c.reveil!.sonnerie.timeIntervalSince(c.maintenant()) + 1
        c.verifierLeReveil()
        verifier(m.alerte?.vue == .reveilFini && m.geo.allSatisfy(\.fini), "« Réduire les animations » : l'alerte est posée d'un coup")
        c.agir(.reveilOK); m.reduire = false; pause(0.6)
        // le Mac endormi toute la matinée : passé de plus de 2 h, il est oublié (rien ne retentit à midi)
        c.reglerLeReveil(heure: 7, minute: 0, aLaVoix: false)
        decalage += c.reveil!.sonnerie.timeIntervalSince(c.maintenant()) + 3 * 3600
        let s1 = sonneries
        c.verifierLeReveil(); pause(0.4)
        verifier(m.alerte == nil && c.reveil == nil && sonneries == s1, "passé depuis 3 h (Mac endormi) : oublié, aucun son")
        // le réveil du Mac (sortie de veille) relit l'heure : l'échéance a pu passer pendant la veille
        c.reglerLeReveil(heure: 8, minute: 0, aLaVoix: false)
        c.demarrerLeReveil()
        decalage += c.reveil!.sonnerie.timeIntervalSince(c.maintenant()) + 20
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: NSWorkspace.shared); pause(0.8)
        verifier(m.alerte?.vue == .reveilFini, "le Mac se réveille 20 s après l'heure : il sonne tout de suite")
        c.agir(.reveilOK); pause(0.5)
        // il survit à un redémarrage de Verbe (fichier relu au lancement)
        c.reglerLeReveil(heure: 9, minute: 15, aLaVoix: false)
        let autre = relancer()
        autre.maintenant = c.maintenant
        autre.allumerEcran = {}
        autre.sons.reveil = {}
        autre.demarrerLeReveil()
        verifier(autre.reveil == c.reveil && autre.moteur.reveil == c.reveil && autre.moteur.resolution.principal == .reveilCompact,
                 "Verbe relancé : le réveil de 9:15 est relu du fichier, replié dans les ailes")
        autre.annulerLeReveil(); autre.arreter()
        verifier(!fm.fileExists(atPath: fichier.path), "annulé : plus de fichier")
        c.reveil = nil; m.reveil = nil; m.donneesChangees(); pause(0.4)
        let contenu = (try? Data(contentsOf: fichier)).map { String(decoding: $0, as: UTF8.self) } ?? ""
        verifier(!contenu.contains("Réveille"), "le fichier ne garde jamais le texte dicté")

        print("Le Calendrier")
        // la nouveauté « calendrier » au lancement : un Centre jamais rangé la retient comme donnée ; retirée ensuite par « Modifier »,
        // elle ne revient pas au lancement suivant (réglages en mémoire)
        do {
            let rc = c.reglagesCentre
            var rangee: [String]? = nil, donnees: [String] = []
            c.reglagesCentre.disposition = { rangee }; c.reglagesCentre.enregistrerDisposition = { rangee = $0 }
            c.reglagesCentre.nouveautes = { donnees }; c.reglagesCentre.marquerNouveautes = { donnees = $0 }
            let d1 = c.dispositionAvecNouveautes()
            verifier(d1 == DispositionCentre() && donnees == ["calendrier", "concentration"] && rangee == nil,
                     "lancement, Centre jamais rangé : le calendrier y est, retenu comme donné (\(donnees))")
            rangee = d1.identifiants.filter { $0 != "calendrier" }   // « Modifier » : Calendrier retiré, « OK »
            let d2 = c.dispositionAvecNouveautes()
            verifier(!d2.elements.contains(.calendrier) && rangee?.contains("calendrier") == false, "retiré par « Modifier », Verbe relancé : il ne revient pas")
            c.reglagesCentre = rc
        }
        // --- étape 10 : le rond Calendrier ; macOS demande une fois (ici : une fermeture qui répond après 0,3 s)
        var statut: AgendaSysteme.Statut = .nonDemande
        var accorde = true, demandes = 0
        let lienMeet = URL(string: "https://meet.google.com/abc-defg-hij")!
        var evenements: [EvenementAgenda] = []
        c.statutCalendrier = { statut }
        c.demanderCalendrier = {
            demandes += 1
            try? await Task.sleep(nanoseconds: 300_000_000)
            statut = accorde ? .autorise : .refuse
            return accorde
        }
        c.lireEvenements = { _ in evenements }
        refermer()
        m.clicForme(); pause(0.9)
        verifier(m.rondsCentre.contains(.calendrier) && m.etatCentre(.calendrier) == "Éteint", "le Centre : le rond Calendrier, « Éteint »")
        clic(PlanCentre.centreRond(m, .calendrier), 0.1)
        verifier(m.calendrierAttente && m.etatCentre(.calendrier) == "Un instant\u{2026}" && demandes == 1, "vrai clic sur Calendrier : macOS pose sa question, « Un instant… »")
        m.clicAilleurs(); pause(0.05)
        verifier(m.courante == .centre, "on répond dans la fenêtre de macOS (un clic ailleurs) : le Centre reste là")
        pause(0.6)
        verifier(!m.calendrierAttente && memoire.calendrier && m.calendrierActif && m.etatCentre(.calendrier) == "Allumé" && m.courante == .centre,
                 "« Autoriser » : le rond s'allume (rouge, « Allumé »), le Centre reste ouvert")
        clic(PlanCentre.centreRond(m, .calendrier), 0.5)
        verifier(!memoire.calendrier && !m.calendrierActif && m.etatCentre(.calendrier) == "Éteint" && demandes == 1, "second clic : éteint (aucune nouvelle question)")
        clic(PlanCentre.centreRond(m, .calendrier), 0.5)
        verifier(memoire.calendrier && m.calendrierActif && demandes == 1, "rallumé : l'accès est déjà là, aucune question")
        clic(PlanCentre.centreRond(m, .calendrier), 0.5)
        // refusé
        statut = .nonDemande; accorde = false
        clic(PlanCentre.centreRond(m, .calendrier), 0.9)
        verifier(!memoire.calendrier && m.calendrierRefuse && m.etatCentre(.calendrier) == "Accès refusé" && m.avisCentre == .calendrierRefuse,
                 "« Refuser » : « Accès refusé » sous le rond, la ligne d'avis en haut")
        let ent = PlanCentre.cadreEntete(m.grille)
        clic(CGPoint(x: ent.minX + 60, y: ent.midY), 0.5)
        verifier(liens.last == IlotControleur.reglagesCalendriers && m.avisCentre == nil, "vrai clic sur la ligne : Réglages Système › Calendriers (capturé, rien n'est ouvert)")
        let d0 = demandes
        clic(PlanCentre.centreRond(m, .calendrier), 0.5)
        verifier(demandes == d0 && m.avisCentre == .calendrierRefuse && !memoire.calendrier, "refusé depuis : un clic ne redemande rien, la ligne revient")
        statut = .autorise
        clic(PlanCentre.centreRond(m, .calendrier), 0.5)
        verifier(memoire.calendrier && m.calendrierActif && !m.calendrierRefuse && m.avisCentre == nil, "rendu dans Réglages Système : un clic l'allume")

        // six ronds (AirPods, Rappel) : « Télécharge-ments » sur deux lignes plutôt que serré ; la rangée s'allonge d'une ligne
        c.lireMicros = { [PeripheriqueEntree(uid: "essai-airpods", nom: "AirPods Pro", transport: .bluetooth)] }; c.relireChoixMicro()
        var six = DispositionCentre(); six.ajouter(.rappel); m.disposition = six; m.donneesChangees(); pause(0.9)
        let noms = m.nomsCentre
        let col = PlanCentre.cadreRonds(m).width / CGFloat(max(1, m.rondsCentre.count))
        let l = noms.map { PlanCentre.largeur($0.texte, $0.taille, .semibold, interlettre: PlanCentre.interlettreNom) }
        verifier(m.rondsCentre.count == 6 && noms.contains { $0.texte == "Télécharge-\nments" } && m.nomsSurDeuxLignes,
                 "six ronds (colonnes de \(Int(col)) pt) : « Télécharge- / ments » sur deux lignes")
        verifier((0..<(l.count - 1)).allSatisfy { l[$0] / 2 + l[$0 + 1] / 2 + PlanCentre.ecartNoms <= col + 0.01 } && noms.allSatisfy { $0.taille >= PlanCentre.seuilDeuxLignes },
                 "noms mesurés : \(Int(PlanCentre.ecartNoms)) pt au moins entre voisins, aucun sous \(PlanCentre.seuilDeuxLignes) pt (\(noms.map { String(format: "%.1f", $0.taille) }.joined(separator: " ")))")
        poseeSurLaCible()
        verifier(abs(m.geo[2].x - (barre + GeoIlot.profondeurCentre + DispositionCentre.ligneNom)) < 0.5 && Double(m.geo[2].x) + 30 <= Double(IlotMoteur.hauteurMax)
                 && m.trace.bande - hc <= GeoIlot.aileMax + 0.01, "Centre à six ronds : \(Int(m.geo[2].x)) pt de haut (une ligne de plus), ≤ 66 pt dans la barre")
        cm = PlanCentre.cadreCase(m, .minuteur)
        verifier(cm.minY >= PlanCentre.cadreRonds(m).maxY + 9.5, "les cases descendent sous la rangée allongée")
        clic(PlanCentre.centreRond(m, .calendrier), 0.5)
        verifier(!memoire.calendrier, "six ronds : un vrai clic sur Calendrier l'éteint (le bon rond)")
        clic(PlanCentre.centreRond(m, .calendrier), 0.5)
        c.lireMicros = { [] }; c.relireChoixMicro(); m.disposition = DispositionCentre(); m.donneesChangees()
        refermer()

        // --- étapes 11 à 13 : 10 min avant, un bandeau puis la petite aile ; à l'heure, « Rejoindre » et « Noter la réunion »
        let t = c.maintenant()
        let rdv = EvenementAgenda(id: "essai-point-client", titre: "Point client", debut: t.addingTimeInterval(590), fin: t.addingTimeInterval(2390), lien: lienMeet)
        evenements = [rdv]
        c.relireAgenda(); pause(0.6)
        verifier(m.bandeau?.vue == .agendaAvant && (m.bandeauVu?.ligne2.hasPrefix("Dans 10 min") ?? false), "10 min avant : le bandeau « Point client · Dans 10 min · Visio »")
        attendre(5.5) { m.bandeau != nil }
        poseeSurLaCible()
        verifier(m.courante == .agendaCompact && m.trace.bande - hc <= GeoIlot.aileMax + 0.01 && abs(m.trace.hauteur - barre) < 0.5,
                 "puis la petite aile : le calendrier à gauche, « 10 min » à droite (\(Int(m.trace.bande - hc)) pt dans la barre)")
        decalage += 600
        c.planifierAgenda(); pause(0.9)
        verifier(m.alerte?.vue == .agendaDebut && abs(m.geo[2].cibleFinale - (barre + GeoIlot.profondeurDebutRendezVous)) < 0.5 && m.trace.bande - hc <= GeoIlot.aileMax + 0.01,
                 "à l'heure : l'alerte « Point client commence », deux lignes (\(Int(m.geo[2].cibleFinale)) pt)")
        verifier(m.contenuAnnonce(.agendaDebut)?.l2 == "Maintenant \u{00B7} Google Meet", "« Maintenant · Google Meet » (le service, pris dans le lien)")
        let zd = m.grille.zone(.agendaDebut)
        let demi = (zd.width - ContenuAnnonce.espaceBoutons) / 2
        verifier(Double(zd.width) + 0.5 >= Double(MesureIlot.boutons(ContenuAgenda.boutonsDebut(rdv), memeLargeur: true)), "« Rejoindre » et « Noter la réunion » tiennent côte à côte, de même largeur")
        clic(CGPoint(x: zd.minX + demi / 2, y: zd.minY + 50 + 16), 0.8)
        verifier(liens.last == lienMeet && m.alerte == nil, "vrai clic sur « Rejoindre » : le lien Meet s'ouvre (capturé), l'îlot se range")
        let t2 = c.maintenant()
        let rdv2 = EvenementAgenda(id: "essai-revue", titre: "Revue de projet", debut: t2.addingTimeInterval(5), fin: t2.addingTimeInterval(1800),
                                   lien: URL(string: "https://us02web.zoom.us/j/123456"))
        evenements = [rdv2]
        c.relireAgenda(); pause(0.2)
        decalage += 6
        c.planifierAgenda(); pause(0.9)
        verifier(m.alerte?.vue == .agendaDebut && m.contenuAnnonce(.agendaDebut)?.l2 == "Maintenant \u{00B7} Zoom", "un Zoom qui commence : « Maintenant · Zoom »")
        let n0 = notes
        clic(CGPoint(x: zd.maxX - demi / 2, y: m.grille.zone(.agendaDebut).minY + 50 + 16), 0.8)
        verifier(notes == n0 + 1 && m.alerte == nil, "vrai clic sur « Noter la réunion » : la prise de notes est lancée (capturée), l'îlot se range")
        evenements = []
        memoire.calendrier = false; c.appliquerLeCalendrier(); pause(0.5)
        attendre(1.2) { m.boucleActive }
        verifier(!m.boucleActive && m.courante == .repos, "tout est rangé : aucune boucle d'animation (bouge encore : \(m.ceQuiBouge))")
    }
}
