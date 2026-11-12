import Foundation
import DicteeCore

/// Les modes de Concentration dans l'îlot (maquette ilot-concentration.html) : les modes et leurs noms chez macOS, les durées (« ce soir »
/// aux heures limites), ce que disent le rond, la carte et les bannières, la mémoire, le raccourci « Concentration Verbe » (son contenu,
/// la liste de Raccourcis, ce qu'il répond), la forme (≤ 66 pt dans la barre) et la place dans le Centre (nouveauté donnée une fois).
func controlesConcentration() {
    var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Europe/Paris")!
    func date(_ j: Int, _ h: Int, _ m: Int = 0) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: j, hour: h, minute: m))! }
    typealias M = ModeConcentration
    typealias D = DureeConcentration

    groupe("Concentration : les modes")
    verifier(M.allCases.map(\.identifiantSysteme) == ["com.apple.donotdisturb.mode.default", "com.apple.focus.work", "com.apple.focus.personal-time",
                                                       "com.apple.sleep.sleep-mode", "com.apple.focus.reduce-interruptions"],
             "les cinq modes de la maquette, avec les identifiants de macOS 26")
    verifier(M.allCases.map(\.nom) == ["Ne pas déranger", "Travail", "Personnel", "Sommeil", "Réduire les interruptions"], "leurs noms (maquette)")
    verifier(Set(M.allCases.map(\.couleur)).count == 5 && M.travail.couleur == 0x32B6C8 && M.nePasDeranger.couleur == 0x5E5CE6, "une couleur par mode (maquette)")
    verifier(M.allCases.filter(\.largeurPleine) == [.reduire] && M.reduire.symbole == nil && M.allCases.filter { $0.symbole != nil }.count == 4,
             "« Réduire les interruptions » : toute la largeur, son glyphe dessiné ; les quatre autres : un symbole")
    verifier(M.depuisNomSysteme("Travail") == .travail && M.depuisNomSysteme("travail\n") == .travail && M.depuisNomSysteme("Temps pour soi") == .personnel
             && M.depuisNomSysteme("Repos") == .sommeil && M.depuisNomSysteme("Do Not Disturb") == .nePasDeranger
             && M.depuisNomSysteme("REDUIRE LES INTERRUPTIONS") == .reduire && M.depuisNomSysteme("Reduce Interruptions") == .reduire,
             "un nom donné par macOS (français, anglais, ceux de la configuration, sans casse ni accents) : le bon mode")
    verifier(M.depuisNomSysteme("Lecture") == nil && M.depuisNomSysteme("") == nil && M.depuisNomSysteme("Travail du soir") == nil, "un mode créé par Hugues, ou rien : aucun mode connu")

    groupe("Concentration : les durées")
    let t = date(12, 14, 30)
    verifier(D.uneHeure.fin(depuis: t, calendrier: cal) == date(12, 15, 30) && D.jusquALArret.fin(depuis: t, calendrier: cal) == nil, "1 h ; jusqu'à l'arrêt : pas de fin")
    verifier(D.ceSoir.fin(depuis: t, calendrier: cal) == date(12, 18), "ce soir à 14:30 : 18:00 (maquette)")
    verifier(D.ceSoir.fin(depuis: date(12, 17, 30), calendrier: cal) == date(12, 18) && D.ceSoir.fin(depuis: date(12, 17, 31), calendrier: cal) == date(12, 22),
             "17:30 : 18:00 ; 17:31 (moins de 30 min) : 22:00")
    verifier(D.ceSoir.fin(depuis: date(12, 21, 45), calendrier: cal) == date(13, 0) && D.ceSoir.fin(depuis: date(12, 23, 45), calendrier: cal) == date(13, 0, 15),
             "21:45 : minuit ; 23:45 : 0:15 (30 min au moins)")
    verifier(D.ceSoir.fin(depuis: date(12, 0, 30), calendrier: cal) == date(12, 18) && D.ceSoir.fin(depuis: date(12, 5), calendrier: cal) == date(12, 18)
             && D.ceSoir.fin(depuis: date(12, 6), calendrier: cal) == date(12, 18), "aux heures limites (0:30, 5:00, 6:00) : le soir du même jour")
    var cal2 = cal; cal2.timeZone = TimeZone(identifier: "America/New_York")!
    let soirNY = D.ceSoir.fin(depuis: t, calendrier: cal2)!
    verifier(cal2.component(.hour, from: soirNY) == 18 || cal2.component(.hour, from: soirNY) == 22 || cal2.component(.hour, from: soirNY) == 0, "« ce soir » suit le fuseau du calendrier")
    verifier(D.allCases.map(\.libelle) == ["1 h", "Jusqu\u{2019}à ce soir", "Jusqu\u{2019}à ce que je l\u{2019}arrête"], "les libellés de la maquette")
    // le changement d'heure (dimanche 29 mars 2026 à Paris) : 1 h dure une heure, « ce soir » reste 18:00 à l'horloge
    let ete = cal.date(from: DateComponents(year: 2026, month: 3, day: 29, hour: 1, minute: 30))!
    verifier(D.uneHeure.fin(depuis: ete, calendrier: cal)!.timeIntervalSince(ete) == 3600
             && cal.component(.hour, from: D.ceSoir.fin(depuis: ete, calendrier: cal)!) == 18, "changement d'heure : 1 h = 3 600 s, « ce soir » = 18:00 à l'horloge")

    groupe("Concentration : où en est le mode")
    var a = EtatConcentration(mode: .travail, duree: .uneHeure, debut: t, calendrier: cal)
    verifier(a.fin == date(12, 15, 30) && a.jusqua(calendrier: cal) == "jusqu\u{2019}à 15:30", "Travail 1 h à 14:30 : jusqu'à 15:30 (maquette, étape 3)")
    verifier(a.encore(a: date(12, 14, 48)) == "encore 42 min" && a.encore(a: t) == "encore 1 h 00" && a.encore(a: t.addingTimeInterval(60 * 41 + 50)) == "encore 19 min",
             "« encore 42 min » (étape 5), « encore 1 h 00 », arrondi à la minute du dessus")
    verifier(abs(a.fraction(a: date(12, 14, 48)) - 0.7) < 1e-9 && a.fraction(a: t) == 1 && a.fraction(a: date(12, 16)) == 0, "la barre : la part qui reste (0,7 à 42 min sur 60)")
    verifier(!a.estFini(a: date(12, 15, 29)) && a.estFini(a: date(12, 15, 30)), "fini à l'heure dite, pas avant")
    verifier(a.prolonger(a: date(12, 14, 48)) && a.fin == date(12, 16) && a.encore(a: date(12, 14, 48)) == "encore 1 h 12", "« +30 min » : 16:00, encore 1 h 12")
    var passe = EtatConcentration(mode: .travail, duree: .uneHeure, debut: t, calendrier: cal)
    verifier(passe.prolonger(a: date(12, 15, 40)) && passe.fin == date(12, 16, 10), "« +30 min » après l'heure : 30 min à partir de maintenant")
    var sansFin = EtatConcentration(mode: .sommeil, duree: .jusquALArret, debut: t, calendrier: cal)
    verifier(!sansFin.prolonger(a: t) && sansFin.fin == nil && sansFin.encore(a: t) == "jusqu\u{2019}à l\u{2019}arrêt" && sansFin.jusqua(calendrier: cal) == "jusqu\u{2019}à l\u{2019}arrêt"
             && sansFin.fraction(a: date(13, 9)) == 1 && !sansFin.estFini(a: date(20, 9)), "jusqu'à l'arrêt : rien à prolonger, jamais fini, la barre pleine")

    groupe("Concentration : ce que disent le rond, la carte, les bannières")
    let dernier = DernierConcentration(mode: .travail, duree: .uneHeure)
    typealias R = RondConcentration
    verifier(R.depuis(actif: nil, dernier: nil, externe: nil) == .eteint && R.eteint.etat == "Désactivée", "rien : « Désactivée » (étape 1)")
    verifier(R.depuis(actif: a, dernier: dernier, externe: "Lecture") == .actif(.travail) && R.actif(.travail).etat == "Travail", "un mode allumé par Verbe : son nom, avant tout le reste")
    verifier(R.depuis(actif: nil, dernier: dernier, externe: nil).etat == "Travail \u{00B7} 1 h", "le dernier mode : « Travail · 1 h » (étape 7)")
    verifier(R.dernier(.init(mode: .reduire, duree: .ceSoir)).etat == "Réduire \u{00B7} ce soir" && R.dernier(.init(mode: .sommeil, duree: .jusquALArret)).etat == "Sommeil",
             "sous le rond, la forme courte (« Réduire · ce soir », « Sommeil »)")
    verifier(R.depuis(actif: nil, dernier: dernier, externe: "Lecture") == .autre("Lecture") && R.depuis(actif: nil, dernier: dernier, externe: "") == .dernier(dernier),
             "allumé ailleurs (un mode à Hugues) : son nom ; vide : comme rien")
    typealias L = LegendeConcentration
    verifier(L.texte(actif: nil, choisi: nil, raccourciManquant: false, calendrier: cal) == "Choisis un mode, puis une durée"
             && L.texte(actif: nil, choisi: .travail, raccourciManquant: false, calendrier: cal) == "Travail \u{00B7} pendant combien de temps\u{00A0}?"
             && L.texte(actif: a, choisi: nil, raccourciManquant: false, calendrier: cal) == "Travail \u{00B7} jusqu\u{2019}à 16:00",
             "la légende de la carte (maquette)")
    verifier(L.texte(actif: nil, choisi: .travail, raccourciManquant: true, calendrier: cal).contains("Raccourcis"), "le raccourci manque : la légende dit quoi faire, en clair")
    let l1 = BanniereConcentration.lance(EtatConcentration(mode: .travail, duree: .uneHeure, debut: t, calendrier: cal), calendrier: cal)
    verifier(l1 == "Travail \u{00B7} jusqu\u{2019}à 15:30" && !l1.contains("\n"), "la bannière, sur une seule ligne : « Travail · jusqu'à 15:30 »")
    verifier(BanniereConcentration.fin(.travail) == "Fin de Travail" && BanniereConcentration.fin(.nePasDeranger) == "Fin du mode Ne pas déranger"
             && !BanniereConcentration.finSous.lowercased().contains("retenue"), "« Fin de Travail » ; aucun nombre de notifications retenues (Verbe ne les voit pas)")

    groupe("Concentration : la mémoire")
    let mem = MemoireConcentration(actif: a, dernier: dernier, raccourci: "0A1B2C3D-0000-4000-8000-00000000ABCD")
    verifier(mem.donnees().flatMap(MemoireConcentration.depuis) == mem, "mode allumé, dernier mode et raccourci : relus à l'identique")
    verifier(MemoireConcentration.depuis(Data("{".utf8)) == nil && MemoireConcentration.depuis(Data("{}".utf8)) == MemoireConcentration(), "fichier abîmé : rien ; vide : rien d'allumé")
    let plusRecent = MemoireConcentration.depuis(Data("{\"actif\":{\"mode\":\"lecture\",\"duree\":\"1h\",\"debut\":\"2026-11-12T13:30:00Z\"},\"raccourci\":\"0A1B2C3D-0000-4000-8000-00000000ABCD\"}".utf8))
    verifier(plusRecent?.actif == nil && plusRecent?.raccourci == "0A1B2C3D-0000-4000-8000-00000000ABCD",
             "un mode inconnu (version plus récente) : pas de mode imaginaire, mais le raccourci est gardé (pas de second raccourci)")

    groupe("Concentration : le raccourci « Concentration Verbe »")
    typealias K = RaccourciConcentration
    verifier(K.Commande.allumer(.travail).texte == "on:com.apple.focus.work" && K.Commande.eteindre(.nePasDeranger).texte == "off:com.apple.donotdisturb.mode.default"
             && K.Commande.lire.texte == "etat", "les commandes : « on:… », « off:… », « etat »")
    var n = 0
    let donnees = K.donnees(uuid: { n += 1; return String(format: "00000000-0000-4000-8000-%012d", n) })
    let relu = donnees.flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] }
    let actions = (relu?["WFWorkflowActions"] as? [[String: Any]]) ?? []
    func id(_ x: [String: Any]) -> String { x["WFWorkflowActionIdentifier"] as? String ?? "" }
    func p(_ x: [String: Any]) -> [String: Any] { x["WFWorkflowActionParameters"] as? [String: Any] ?? [:] }
    verifier(donnees != nil && !actions.isEmpty && id(actions[0]) == "is.workflow.actions.text.trimwhitespace", "une liste de propriétés binaire ; l'entrée est d'abord nettoyée")
    let entree = p(actions[0])["UUID"] as? String
    let definir = actions.filter { id($0) == "is.workflow.actions.dnd.set" }
    verifier(definir.count == 10 && actions.filter { id($0) == "is.workflow.actions.dnd.getfocus" }.count == 1,
             "dix « Définir la concentration » (cinq modes, allumer et éteindre) et une « Concentration actuelle »")
    let conditions = actions.filter { id($0) == "is.workflow.actions.conditional" && (p($0)["WFControlFlowMode"] as? Int) == 0 }
    verifier(conditions.compactMap { p($0)["WFConditionalActionString"] as? String }.sorted()
             == (M.allCases.flatMap { [K.Commande.allumer($0).texte, K.Commande.eteindre($0).texte] } + ["etat"]).sorted(),
             "une branche par commande, ni plus ni moins")
    verifier(conditions.allSatisfy { (p($0)["WFCondition"] as? Int) == 4
        && (((p($0)["WFInput"] as? [String: Any])?["Variable"] as? [String: Any])?["Value"] as? [String: Any])?["OutputUUID"] as? String == entree },
             "chaque branche compare l'entrée nettoyée (« est égal à »)")
    let groupes = Dictionary(grouping: actions.filter { id($0) == "is.workflow.actions.conditional" }, by: { p($0)["GroupingIdentifier"] as? String ?? "" })
    verifier(groupes.count == 11 && groupes.values.allSatisfy { Set($0.compactMap { p($0)["WFControlFlowMode"] as? Int }) == [0, 1, 2] && $0.count == 3 },
             "chaque « si » a son « sinon » et sa fin, sous le même identifiant de groupe")
    let parMode = Dictionary(grouping: definir, by: { ((p($0)["FocusModes"] as? [String: Any])?["Identifier"] as? String) ?? "défaut" })
    verifier(parMode["défaut"]?.count == 2 && M.allCases.filter { $0 != .nePasDeranger }.allSatisfy { parMode[$0.identifiantSysteme]?.count == 2 }
             && Set(definir.compactMap { p($0)["Enabled"] as? Int }) == [0, 1] && definir.allSatisfy { p($0)["AssertionType"] == nil && p($0)["Operation"] == nil },
             "Ne pas déranger = le mode par défaut de l'action ; les autres nommés ; allumer (1) et éteindre (0), sans « jusqu'à » (Verbe éteint à l'heure)")
    let dernierTexte = ((p(actions.last ?? [:])["WFOutput"] as? [String: Any])?["Value"] as? [String: Any])?["string"] as? String
    verifier(id(actions.last ?? [:]) == "is.workflow.actions.output" && dernierTexte == K.reponseInconnue, "une commande inconnue : « inconnu », rien d'allumé")
    let brut = donnees.map { String(decoding: $0, as: UTF8.self) } ?? ""
    verifier(!brut.contains("hugues") && !brut.contains("/Users/") && relu?["WFWorkflowImportQuestions"] as? [Any] != nil, "rien de personnel dans le raccourci, aucune question à l'import")

    let liste = """
    Mon (petit) raccourci (11111111-2222-4333-8444-555555555555)
    Concentration Verbe (0a1b2c3d-0000-4000-8000-00000000abcd)
    pas une ligne de raccourci
    Concentration Verbe 2 (99999999-0000-4000-8000-000000000001)
    Concentration Verbeuse (99999999-0000-4000-8000-000000000002)
    """
    let lus = K.lireListe(liste)
    verifier(lus.count == 4 && lus[0] == .init(nom: "Mon (petit) raccourci", identifiant: "11111111-2222-4333-8444-555555555555")
             && lus[1].identifiant == "0A1B2C3D-0000-4000-8000-00000000ABCD", "`shortcuts list --show-identifiers` : nom (même avec des parenthèses) et identifiant")
    verifier(K.nouveau(dans: lus, avant: ["0A1B2C3D-0000-4000-8000-00000000ABCD", "11111111-2222-4333-8444-555555555555"]) == "99999999-0000-4000-8000-000000000001",
             "après l'import : le NOUVEAU « Concentration Verbe 2 » (Hugues en avait déjà un)")
    verifier(K.nouveau(dans: lus, avant: Set(lus.map(\.identifiant))) == nil && K.nouveau(dans: [lus[3]], avant: []) == nil
             && K.nouveau(dans: [.init(nom: "Concentration Verbe copie", identifiant: "99999999-0000-4000-8000-000000000003")], avant: []) == nil,
             "rien de nouveau : aucun ; « Concentration Verbeuse » et « Concentration Verbe copie » ne sont pas le nôtre")
    verifier(K.present("0a1b2c3d-0000-4000-8000-00000000abcd", dans: lus) && !K.present("0A1B2C3D-0000-4000-8000-0000000000FF", dans: lus), "le raccourci retenu est-il toujours là ?")
    verifier(K.lireEtat("") == .aucun && K.lireEtat("\n") == .aucun && K.lireEtat("Travail\n") == .mode(.travail) && K.lireEtat("Repos") == .mode(.sommeil)
             && K.lireEtat("Lecture") == .autre("Lecture"), "« etat » : rien, un mode connu, ou un mode à Hugues")

    groupe("Concentration : la forme et la place")
    let barre = 37.0
    for demi in [90.0, 89.5, 100.0] {
        for v in [VueIlot.concentrationCompact, .concentrationStatut, .concentration, .concentrationLance, .concentrationFin] {
            for ep in [false, true] {
                let tr = TraceIlot.calculer(GeoIlot.valeurs(v, hauteurBarre: barre, demiCamera: demi, contenu: 300, epaules: ep), demiCamera: demi, barre: barre)
                verifier(tr.bande - demi <= GeoIlot.aileMax + 0.01, "\(v) (caméra \(Int(2 * demi)) pt, épaules \(ep)) : \(String(format: "%.1f", tr.bande - demi)) pt dans la barre (≤ 66)")
            }
        }
    }
    let compact = TraceIlot.calculer(GeoIlot.valeurs(.concentrationCompact, hauteurBarre: barre, demiCamera: 90), demiCamera: 90, barre: barre)
    verifier(compact.couGauche == 90 + MesuresConcentration.cou && compact.cou == 90, "replié : l'aile gauche (40 pt) pour l'icône, à droite la caméra seule")
    verifier(MesuresConcentration.profondeurCarte <= GeoIlot.profondeurCentre && MesuresConcentration.profondeurCarte == 290
             && MesuresConcentration.profondeurStatut + GeoIlot.piedLecture <= GeoIlot.profondeurCentre, "la carte des modes (290 pt) et celle du mode, avec son pied, tiennent sous le Centre")
    verifier(VueIlot.concentrationLance.estBandeau && VueIlot.concentrationFin.estBandeau && !VueIlot.concentrationCompact.estBandeau
             && GeoIlot.ajusteAuContenu(.concentrationLance), "les bannières épousent leur contenu et se retirent seules")
    var e = EtatIlot(); e.concentration = true
    let r1 = ArbitrageIlot.resoudre(e)
    verifier(r1.principal == .concentrationCompact && r1.survol == .concentrationStatut && r1.pastille == nil, "un mode allumé, seul : l'aile ; au survol, où en est le mode (étapes 4 et 5)")
    e.lecture = true
    verifier(ArbitrageIlot.resoudre(e).principal == .lectureCompact && ArbitrageIlot.resoudre(e).pastille == .concentration, "une vidéo : elle a l'îlot, la Concentration va dans la bulle")
    e.lecture = false; e.reveil = true
    verifier(ArbitrageIlot.ordre(e) == [.concentration, .reveil], "avec un réveil réglé : la Concentration d'abord (elle est là maintenant)")
    verifier(CartesIlot.parent(.concentration) == .centre && CartesIlot.aUnPied(.concentrationStatut, pile: CartesIlot.pile(survol: .concentrationStatut))
             && !CartesIlot.aUnPied(.concentration, pile: CartesIlot.pile(survol: .centre)),
             "la carte des modes est rangée sous le Centre ; celle du mode a le bouton « Centre » à son pied")

    groupe("Concentration : le rond du Centre, donné une fois")
    let d0 = DispositionCentre()
    verifier(d0.elements.firstIndex(of: .concentration) == d0.elements.firstIndex(of: .claude).map { $0 + 1 } && d0.ronds().count == 6,
             "par défaut : après Claude Code (six ronds avec les AirPods, la rangée en tient six)")
    verifier(ElementCentre.concentration.aide.count <= ElementCentre.aideMax && ElementCentre.concentration.genre == .rond && ElementCentre.concentration.page == .centre,
             "un rond du Centre, avec son aide de survol")
    let rangeAvant = ["micro", "telechargements", "calendrier", "claude", "minuteur", "etagere", "reunion"]
    let r = DispositionCentre.relire(identifiants: rangeAvant, dejaProposees: ["calendrier", "groq"])
    verifier(r.disposition.elements == [.micro, .telechargements, .calendrier, .claude, .concentration, .minuteur, .etagere, .reunion]
             && r.ajoutees == [.concentration] && r.aRetenir == ["calendrier", "concentration", "groq"],
             "un Centre rangé avant : la Concentration arrive une fois, à la fin des ronds, et c'est retenu")
    let retire = DispositionCentre.relire(identifiants: rangeAvant, dejaProposees: ["calendrier", "groq", "concentration"])
    verifier(!retire.disposition.elements.contains(.concentration) && retire.aRetenir == nil && retire.ajoutees.isEmpty, "retirée ensuite par « Modifier » : elle ne revient pas")
    let jamais = DispositionCentre.relire(identifiants: nil, dejaProposees: ["calendrier", "groq"])
    verifier(jamais.disposition.elements.contains(.concentration) && jamais.aRetenir == ["calendrier", "concentration", "groq"] && jamais.ajoutees.isEmpty,
             "jamais rangé : déjà dans le Centre par défaut, retenue comme donnée")
    let plein = DispositionCentre.relire(identifiants: ["micro", "dictee", "telechargements", "calendrier", "claude", "rappel", "minuteur"], dejaProposees: ["calendrier", "groq"])
    verifier(!plein.disposition.elements.contains(.concentration) && plein.aRetenir?.contains("concentration") == true
             && plein.disposition.aAjouter().contains(.concentration), "rangée pleine (six ronds) : rien n'entre, « Modifier » la propose")
}
