import Foundation
import DicteeCore

/// « Lucarne, … » partout, les rappels dits naturellement, la note qui ressemble à un rappel, la fin de note au silence, l'app Rappels.
/// Les phrases sont celles qu'on dicte vraiment (dont celle de Hugues du 11/11 : « j'ai demain une livraison vers 13-14h »).
func controlesLucarne() {
    var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Europe/Paris")!; cal.locale = Locale(identifier: "fr_FR")
    // mercredi 11 novembre 2026, 23 h 05 (l'heure de l'essai de Hugues) ; jeudi 12 novembre, 14 h
    let t0 = cal.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 23, minute: 5))!
    let t1 = cal.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 14, minute: 0))!
    // vendredi 13 novembre, 0 h 30 : Hugues dicte souvent après minuit (« demain » veut alors dire ce vendredi)
    let t2 = cal.date(from: DateComponents(year: 2026, month: 11, day: 13, hour: 0, minute: 30))!
    func le(_ jour: Int, _ h: Int, _ m: Int = 0, mois: Int = 11) -> Date { cal.date(from: DateComponents(year: 2026, month: mois, day: jour, hour: h, minute: m))! }
    func lucarne(_ s: String, _ t: Date = t0) -> ResultatLucarne { AnalyseCommandeIlot.lucarne(s, maintenant: t, calendrier: cal) }
    func rappel(_ s: String, _ texte: String, _ quand: Date, _ t: Date = t0) {
        let r = lucarne(s, t)
        if case .commande(.rappel(let x, let q)) = r { verifier(x == texte && q == quand, "« \(s) » → « \(x) » \(q == quand ? "à la bonne heure" : "à la MAUVAISE heure (\(q))")") }
        else { verifier(false, "« \(s) » → rappel attendu, obtenu \(r)") }
    }

    groupe("Lucarne : le mot d'appel")
    verifier(AnalyseCommandeIlot.sansAppel("Lucarne, rappelle-moi") == "rappelle-moi" && AnalyseCommandeIlot.sansAppel("Lucarne rappelle-moi") == "rappelle-moi",
             "« Lucarne, » ou « Lucarne » sans virgule")
    verifier(AnalyseCommandeIlot.sansAppel("Verbe. Minuteur de 10 minutes") == "Minuteur de 10 minutes" && AnalyseCommandeIlot.sansAppel("verbe : minuteur") == "minuteur",
             "« Verbe. », « verbe : » (la ponctuation de Whisper)")
    verifier(["Lucarnes, minuteur", "L'ucarne, minuteur", "Lu carne minuteur", "La carne, minuteur", "« Lucarne, minuteur"].allSatisfy { AnalyseCommandeIlot.sansAppel($0) == "minuteur" },
             "transcriptions ratées du mot d'appel : « Lucarnes », « L'ucarne », « Lu carne », « La carne », guillemet ouvrant")
    verifier(["Verbes irréguliers à revoir", "La lucarne de la salle de bain est cassée", "Bonjour Lucarne", "Lucarneau est là", "Le verbe être",
              "Je te rappelle demain à 15 h", "J'ai une livraison demain vers 13-14 h"].allSatisfy { AnalyseCommandeIlot.sansAppel($0) == nil },
             "sans le mot d'appel EN TÊTE : rien (« Verbes… », « La lucarne… », « Bonjour Lucarne », un mail)")
    for s in ["Bonjour Paul, rappelle-moi demain à 15 h.", "J'ai une livraison demain vers 13-14 h.", "Minuteur de 10 minutes", "Le verbe être au présent"] {
        verifier(lucarne(s) == .aucune, "« \(s) » : dictée normale, collée comme avant")
    }

    groupe("Lucarne : rappels dits naturellement")
    rappel("Lucarne, rappelle-moi d'appeler Ladislas demain à 15 h.", "Appeler Ladislas", le(12, 15))
    rappel("Lucarne rappelle-moi d'appeler Ladislas demain à 15h", "Appeler Ladislas", le(12, 15))
    rappel("Lucarne, crée-moi un rappel pour appeler Ladislas demain à 15 h.", "Appeler Ladislas", le(12, 15))
    rappel("Lucarne, crée un rappel demain à 15 heures : appelez Ladislas.", "Appeler Ladislas", le(12, 15))
    rappel("Verbe, mets un rappel demain à 9 h pour sortir les poubelles.", "Sortir les poubelles", le(12, 9))
    rappel("Lucarne, ajoute un rappel : appelez Ladislas demain à 15 h", "Appeler Ladislas", le(12, 15))
    rappel("Lucarne, mets-moi un rappel pour demain 10 h, appeler la banque.", "Appeler la banque", le(12, 10))
    rappel("Lucarne, rappel demain 15 h : appeler Paul", "Appeler Paul", le(12, 15))
    rappel("Lucarne, n'oublie pas que j'ai une livraison demain à 13 h.", "Livraison", le(12, 13))
    rappel("Lucarne, j'ai une livraison demain vers 13-14 h.", "Livraison", le(12, 13))
    rappel("Lucarne, j'ai demain une livraison vers 13-14h.", "Livraison", le(12, 13))
    rappel("Lucarne, j'ai une livraison demain entre 13 et 14 heures.", "Livraison", le(12, 13))
    rappel("Lucarne, j'ai une livraison demain de 13 h à 14 h", "Livraison", le(12, 13))
    rappel("Lucarne, j'ai une livraison demain, 13 h - 14 h.", "Livraison", le(12, 13))
    rappel("Lucarne j'ai une livraison demain 13h-14h", "Livraison", le(12, 13))
    rappel("Lucarnes, rappelle-moi de rappeler maman lundi à 18 h.", "Rappeler maman", le(16, 18))
    rappel("Lucarne, rappelle-moi dans 20 minutes de sortir le gâteau.", "Sortir le gâteau", t0.addingTimeInterval(1200))
    rappel("Lucarne, rappelle-moi de sortir le gâteau dans vingt minutes s'il te plaît.", "Sortir le gâteau", t0.addingTimeInterval(1200))
    rappel("Lucarne, rappelle-moi dans une heure de relancer Marc", "Relancer Marc", t0.addingTimeInterval(3600))
    rappel("Lucarne, rappelle-moi ce soir d'appeler le garage.", "Appeler le garage", le(12, 19), t1)
    rappel("Lucarne, demain à 8 h du matin, rendez-vous chez le dentiste.", "Rendez-vous chez le dentiste", le(12, 8))
    rappel("Lucarne, n'oublie pas que j'ai rendez-vous chez le dentiste lundi à 10 h 30.", "Rendez-vous chez le dentiste", le(16, 10, 30))
    rappel("Lucarne, rappelle-moi à 3 h d'appeler Paul.", "Appeler Paul", le(12, 15), t1)
    rappel("Lucarne, rappelle-moi à 15h30 de rappeler Marc.", "Rappeler Marc", le(12, 15, 30), t1)
    rappel("Lucarne, rappelle-moi à midi et demi de déjeuner avec Julie.", "Déjeuner avec Julie", le(13, 12, 30), t1)
    rappel("Lucarne, rappelle-moi demain matin d'arroser les plantes.", "Arroser les plantes", le(12, 9))
    rappel("Lucarne, rappelle-moi demain soir à 8 h de préparer la valise", "Préparer la valise", le(12, 20))
    rappel("Lucarne, rappelle-moi le 20 novembre de payer le loyer.", "Payer le loyer", le(20, 9))
    rappel("Lucarne, il faut que j'appelle le plombier jeudi.", "Appeler le plombier", le(12, 9))
    rappel("Lucarne, rappelle-moi jeudi prochain à 14 h de déposer le colis", "Déposer le colis", le(12, 14))
    rappel("Lucarne, fais-moi penser à acheter du pain à 18 h.", "Acheter du pain", le(12, 18), t1)
    rappel("Lucarne, rappelle-moi après-demain à 9 h que je dois envoyer le devis", "Envoyer le devis", le(13, 9))
    rappel("Verbe, réveille-moi à 7 h.", "Réveil", le(12, 7))

    groupe("Lucarne : minuteur, et ce qui n'est pas compris")
    verifier(lucarne("Lucarne, minuteur de 10 minutes.") == .commande(.minuteur(secondes: 600)), "« Lucarne, minuteur de 10 minutes »")
    verifier(lucarne("Verbe, lance un minuteur de cinq minutes s'il te plaît.") == .commande(.minuteur(secondes: 300)), "« lance un minuteur de cinq minutes s'il te plaît »")
    verifier(lucarne("Lucarne minuteur d'une demi-heure") == .commande(.minuteur(secondes: 1800)), "minuteur d'une demi-heure, sans virgule")
    if case .incomprise(let p) = lucarne("Lucarne, ouvre le dossier des factures.") { verifier(p == "Lucarne, ouvre le dossier des factures.", "« Lucarne, ouvre le dossier… » : « Je n'ai pas compris » + la phrase, rien de plus") }
    else { verifier(false, "« Lucarne, ouvre le dossier… » : incomprise attendue, obtenu \(lucarne("Lucarne, ouvre le dossier des factures."))") }
    let longue = "Lucarne, " + String(repeating: "un long paragraphe dicté pour le compte rendu de la réunion. ", count: 6)
    if case .incomprise(let p) = lucarne(longue) { verifier(p == longue.trimmingCharacters(in: .whitespaces) && p.count > 300, "une longue phrase incomprise est gardée ENTIÈRE (\(p.count) caractères) : « Copier » ne perd rien") }
    else { verifier(false, "longue phrase : incomprise attendue") }
    verifier(lucarne("Lucarne.") == .incomprise(phrase: "Lucarne.") && lucarne("Verbe, euh…") != .aucune, "« Lucarne. » seul : incompris (jamais collé)")
    verifier(lucarne("Lucarne, rappelle-moi d'appeler Paul.") == .sansHeure(phrase: "Lucarne, rappelle-moi d'appeler Paul."), "un rappel sans heure : « Il me manque l'heure »")
    verifier(lucarne("Lucarne, rappelle-moi un jour de te le dire") == .sansHeure(phrase: "Lucarne, rappelle-moi un jour de te le dire"), "« un jour » n'est pas une date")
    if case .incomprise = lucarne("Lucarne, ouvre Safari.") { verifier(true, "une demande inconnue (« ouvre Safari ») : incomprise") } else { verifier(false, "« ouvre Safari » : incomprise") }
    if case .incomprise = lucarne("Lucarne, une heure de sport c'est bien.") { verifier(true, "« une heure de sport » : pas une heure du jour") } else { verifier(false, "« une heure de sport » : \(lucarne("Lucarne, une heure de sport c'est bien."))") }

    groupe("Lucarne : une phrase SUR Lucarne n'est pas une commande (relecture du 12/11)")
    for s in ["Lucarne est prête, je te l'envoie demain.", "Verbe 0.3.3 publiée ce soir", "Lucarne est une fenêtre.", "Verbe être au passé composé demain matin"] {
        verifier(lucarne(s) == .aucune, "« \(s) » (pas de virgule, aucune demande) : dictée normale, collée, aucun rappel")
    }
    if case .incomprise = lucarne("Lucarne : sortie demain") { verifier(true, "« Lucarne : sortie demain » (une ligne de liste) : un nom et une date ne font pas un rappel") }
    else { verifier(false, "« Lucarne : sortie demain » : \(lucarne("Lucarne : sortie demain"))") }
    rappel("Lucarne, demain à 9 h, tester l'AirDrop.", "Tester l'AirDrop", le(12, 9))

    groupe("Lucarne : après minuit, « demain » est le jour qui commence")
    rappel("Lucarne, j'ai demain une livraison vers 13-14h.", "Livraison", le(13, 13), t2)
    rappel("Lucarne, rappelle-moi demain à 9 h d'appeler Paul.", "Appeler Paul", le(13, 9), t2)
    rappel("Lucarne, j'ai une réunion de 10 h à 11 h demain.", "Réunion", le(13, 10), t2)
    rappel("Lucarne, rappelle-moi après-demain de payer le loyer.", "Payer le loyer", le(14, 9), t2)
    rappel("Lucarne, rappelle-moi vendredi d'appeler le garage.", "Appeler le garage", le(13, 9), t2)
    rappel("Lucarne, rappelle-moi demain à 9 h d'appeler Paul.", "Appeler Paul", le(13, 9), t1)
    verifier(ListeRappels.jour(de: le(13, 13), maintenant: t2, calendrier: cal) == "vendredi 13" && ListeRappels.jour(de: le(14, 9), maintenant: t2, calendrier: cal) == "samedi 14",
             "la nuit, la confirmation NOMME le jour (« vendredi 13 ») au lieu de « demain »")
    verifier(ListeRappels.jour(de: le(13, 13), maintenant: t1, calendrier: cal) == "demain", "le jour, « demain » reste « demain »")

    groupe("Lucarne : 5 h, 6 h, c'est le matin ; un réveil n'est jamais l'après-midi")
    rappel("Lucarne, réveille-moi à 6 h.", "Réveil", le(12, 6))
    rappel("Lucarne, réveille-moi à 4 h.", "Réveil", le(12, 4))
    rappel("Lucarne, rappelle-moi demain à 6 h 30 de prendre le train.", "Prendre le train", le(12, 6, 30))
    rappel("Lucarne, rappelle-moi à 5 h de partir à l'aéroport.", "Partir à l'aéroport", le(12, 5))
    rappel("Lucarne, rappelle-moi demain à 3 h d'appeler Paul.", "Appeler Paul", le(12, 15))
    rappel("Lucarne, rappelle-moi cette nuit à 2 h de couper le four.", "Couper le four", le(12, 2))

    groupe("Lucarne : dates en chiffres, plages sans tiret")
    rappel("Lucarne, rappelle-moi d'appeler Paul le 13/11 à 14 h.", "Appeler Paul", le(13, 14))
    rappel("Lucarne, j'ai une livraison demain vers 13 14 h.", "Livraison", le(12, 13))
    rappel("Lucarne, rappelle-moi de prendre la ligne 13, 14 h.", "Prendre la ligne 13", le(12, 14))
    rappel("Lucarne, rappelle-moi le 20/11 de payer le loyer.", "Payer le loyer", le(20, 9))

    groupe("Lucarne : un moment déjà passé n'est pas ajouté")
    verifier(lucarne("Lucarne, rappelle-moi aujourd'hui à 9 h d'appeler Paul.", t1) == .passe(phrase: "Lucarne, rappelle-moi aujourd'hui à 9 h d'appeler Paul."),
             "« aujourd'hui à 9 h » dit à 14 h : « Cette heure est passée », rien d'ajouté (il sonnerait aussitôt)")
    verifier(AnalyseCommandeIlot.rappel("Rappelle-moi aujourd'hui à 9 h d'appeler Paul.", maintenant: t1, calendrier: cal) == nil, "îlot ouvert : pas de rappel déjà passé non plus")
    rappel("Lucarne, rappelle-moi aujourd'hui à 18 h d'appeler Paul.", "Appeler Paul", le(12, 18), t1)

    groupe("Rappels : texte remis au propre")
    verifier(TexteRappel.propre("Appelez Ladislas") == "Appeler Ladislas" && TexteRappel.propre("appelle Ladislas") == "Appeler Ladislas", "« Appelez / appelle Ladislas » → « Appeler Ladislas »")
    verifier(TexteRappel.propre("achète du pain") == "Acheter du pain" && TexteRappel.propre("j'envoie le devis") == "Envoyer le devis", "achète → acheter, j'envoie → envoyer")
    verifier(TexteRappel.propre("Demande de devis") == "Demande de devis" && TexteRappel.propre("chez le médecin") == "Chez le médecin" && TexteRappel.propre("Note de frais") == "Note de frais",
             "des noms restent des noms (« Demande de devis », « Chez le médecin », « Note de frais »)")
    verifier(TexteRappel.propre("j'ai une livraison") == "Livraison" && TexteRappel.propre("qu'il faut appeler Paul") == "Appeler Paul", "« j'ai une livraison » → « Livraison »")
    verifier(TexteRappel.propre("") == "Rappel" && TexteRappel.propre(" , vers") == "Rappel", "rien de dit : « Rappel »")
    verifier(TexteRappel.propre("dire merci à Paul") == "Dire merci à Paul" && TexteRappel.propre("appeler Paul merci") == "Appeler Paul", "« merci » gardé au milieu, retiré au bout")

    groupe("Rappels : l'ancienne commande (îlot ouvert) profite des heures naturelles")
    if let r = AnalyseCommandeIlot.rappel("Rappelle-moi d'appeler Paul vers 13-14 h.", maintenant: t1, calendrier: cal) {
        verifier(r.texte == "Appeler Paul" && r.quand == le(13, 13), "« rappelle-moi d'appeler Paul vers 13-14 h » (îlot ouvert)")
    } else { verifier(false, "« rappelle-moi d'appeler Paul vers 13-14 h » (îlot ouvert)") }
    verifier(AnalyseCommandeIlot.rappel("J'ai une livraison demain à 13 h", maintenant: t1, calendrier: cal) == nil, "îlot ouvert, sans « rappelle-moi » : toujours rien (comportement inchangé)")

    groupe("Note rapide : elle ressemble à un rappel ?")
    if let r = AnalyseCommandeIlot.rappelDansUneNote("J'ai demain une livraison vers 13-14h.", maintenant: t0, calendrier: cal) {
        verifier(r.texte == "Livraison" && r.quand == le(12, 13), "la note de Hugues → « En faire un rappel · demain 13:00 » (« Livraison »)")
        verifier(ListeRappels.jour(de: r.quand, maintenant: t0, calendrier: cal) + " " + FormatIlot.heure(r.quand, calendrier: cal) == "demain 13:00", "libellé « demain 13:00 »")
    } else { verifier(false, "la note de Hugues → rappel proposé") }
    if let r = AnalyseCommandeIlot.rappelDansUneNote("Appeler le comptable lundi", maintenant: t0, calendrier: cal) {
        verifier(r.texte == "Appeler le comptable" && r.quand == le(16, 9), "« Appeler le comptable lundi » → lundi 9:00")
    } else { verifier(false, "« Appeler le comptable lundi »") }
    verifier(AnalyseCommandeIlot.rappelDansUneNote("Idée : refaire le logo en vert.", maintenant: t0, calendrier: cal) == nil, "une idée sans jour ni heure : rien à proposer")
    verifier(AnalyseCommandeIlot.rappelDansUneNote("Réunion de ce matin très bien passée", maintenant: t1, calendrier: cal) == nil, "un moment déjà passé : rien à proposer")

    groupe("Note au clic : fin au silence")
    var f = FinDeNote(debut: t0)
    f.niveau(0.95, a: t0.addingTimeInterval(0.15))   // le petit son de départ, capté par le micro
    verifier(!f.aParle && f.fin(a: t0.addingTimeInterval(1)) == nil, "le son de départ (0,15 s) ne compte pas comme de la voix")
    for i in 0..<10 { f.niveau(0.2, a: t0.addingTimeInterval(0.5 + Double(i) * 0.05)) }
    verifier(!f.aParle && abs(f.fond - 0.2) < 0.01, "bruit de fond appris (\(f.fond))")
    for i in 0..<40 { f.niveau(0.7, a: t0.addingTimeInterval(1 + Double(i) * 0.05)) }
    verifier(f.aParle && f.fin(a: t0.addingTimeInterval(3.5)) == nil, "voix entendue : on écoute encore 1,5 s après")
    for i in 0..<60 { f.niveau(0.22, a: t0.addingTimeInterval(3 + Double(i) * 0.05)) }
    verifier(f.fin(a: t0.addingTimeInterval(5.0)) == .silence && f.fin(a: t0.addingTimeInterval(4.8)) == nil, "2 s de silence après la dernière voix (2,95 s) : fin à 4,95 s")
    var muet = FinDeNote(debut: t0)
    for i in 0..<160 { muet.niveau(0.25, a: t0.addingTimeInterval(Double(i) * 0.05)) }
    verifier(muet.fin(a: t0.addingTimeInterval(7.9)) == nil && muet.fin(a: t0.addingTimeInterval(8.1)) == .rienEntendu, "rien dit en 8 s : fin (« Rien entendu »)")
    var bruyant = FinDeNote(debut: t0)
    for i in 0..<200 { bruyant.niveau(0.45, a: t0.addingTimeInterval(0.5 + Double(i) * 0.05)) }
    verifier(!bruyant.aParle, "un ventilateur constant (fond à -40 dB) n'est pas de la voix : le seuil suit le fond")
    var long = FinDeNote(debut: t0); long.niveau(0.8, a: t0.addingTimeInterval(119.5))
    verifier(long.fin(a: t0.addingTimeInterval(120)) == .tropLong, "2 minutes : fin quoi qu'il arrive")

    groupe("App Rappels : demander une fois, refus dit une fois, pas de doublon")
    verifier(PlanRappelsApple.apresAjout(choix: nil, acces: .nonDemande) == .demander, "premier rappel, jamais demandé : la question dans l'îlot")
    verifier(PlanRappelsApple.apresAjout(choix: nil, acces: .autorise) == .creer && PlanRappelsApple.apresAjout(choix: .oui, acces: .autorise) == .creer, "accès donné : créé dans l'app Rappels")
    verifier(PlanRappelsApple.apresAjout(choix: .non, acces: .nonDemande) == .rien && PlanRappelsApple.apresAjout(choix: .non, acces: .autorise) == .rien, "« Non » dans l'îlot : plus jamais demandé ni créé")
    verifier(PlanRappelsApple.apresAjout(choix: nil, acces: .refuse) == .direRefus && PlanRappelsApple.apresAjout(choix: .oui, acces: .refuse) == .rien,
             "refusé dans Réglages Système : dit une fois")
    var l = ListeRappels()
    let a = l.ajouter(texte: "Livraison", echeance: le(12, 13), maintenant: t0)!
    let b = l.ajouter(texte: "Appeler Ladislas", echeance: le(12, 15), maintenant: t0)!
    verifier(l.sansDoubleApple(a: t0).count == 2, "deux rappels sans double")
    verifier(l.lier(a.id, apple: "EK-1") && !l.lier(a.id, apple: "EK-2") && l.rappel(a.id)?.idApple == "EK-1", "un seul double par rappel (le second lien est refusé)")
    verifier(l.sansDoubleApple(a: t0).map(\.id) == [b.id], "après « Oui » : seul celui qui manque est rattrapé")
    let relu = l.donnees().flatMap { ListeRappels.depuis($0) }
    verifier(relu == l && relu?.rappel(a.id)?.idApple == "EK-1", "le lien est gardé dans rappels.json")
    let ancien = Data(#"{"rappels":[{"cree":"2026-11-11T20:00:00Z","echeance":"2026-11-12T14:00:00Z","id":"9F1A2C3D-0000-4000-8000-000000000001","texte":"Appeler Paul"}]}"#.utf8)
    verifier(ListeRappels.depuis(ancien)?.rappels.first?.idApple == nil && ListeRappels.depuis(ancien)?.rappels.count == 1, "un ancien rappels.json (sans lien) se relit")
}
