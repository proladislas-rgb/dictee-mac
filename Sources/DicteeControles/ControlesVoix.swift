import Foundation
import DicteeCore

/// La voix d'un rappel ou d'une note (maquette ilot-voix-rappel.html) : la dictée reconnue en direct (pour Lucarne ? un rappel, une note ?),
/// la commande « note », le titre, le résumé, le jour et l'heure de la carte, l'état du bouton d'envoi, l'onde (le niveau du micro sur des
/// ressorts, du milieu vers les bords), et la forme (≤ 66 pt dans la barre, la carte de la largeur du Centre).
func controlesVoix() {
    var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Europe/Paris")!
    func date(_ j: Int, _ h: Int, _ m: Int = 0) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: j, hour: h, minute: m))! }
    let t = date(12, 14, 30)
    func direct(_ s: String, _ a: Date? = nil) -> DirectVoix { AnalyseCommandeIlot.directVoix(s, maintenant: a ?? t, calendrier: cal) }

    groupe("Voix : la dictée reconnue en direct")
    verifier(direct("Voxile, rappelle-moi") == .pourLucarne(.rappel) && direct("Voxile rappelle-moi demain") == .pourLucarne(.rappel)
             && direct("Voxile, mets un rappel") == .pourLucarne(.rappel), "« rappelle-moi », « mets un rappel » (avec ou sans virgule) : un rappel, tout de suite")
    verifier(direct("Voxile, note : montrer le prix") == .pourLucarne(.note) && direct("Voxile prends une note") == .pourLucarne(.note)
             && direct("Voxile, note que Paul rappelle") == .pourLucarne(.note), "« note : », « prends une note », « note que » : une note")
    verifier(direct("Voxile, note un rappel pour demain") == .pourLucarne(.rappel), "« note un rappel » : un rappel, pas une note")
    verifier(direct("Voxile, j'ai demain une livraison vers 13") == .pourLucarne(.rappel), "« j'ai demain une livraison » (Hugues, 11/11) : un rappel dès que le jour est dit")
    verifier(direct("Voxile, j'ai une livraison") == .pourLucarne(nil) && direct("Voxile, minuteur de 5 minutes") == .pourLucarne(nil),
             "pour l'app, sans genre encore (ni jour ni heure) ou un minuteur : l'onde, pas de libellé")
    verifier(direct("Voxile") == .autre && direct("Voxile,") == .autre, "« Voxile » seul (la suite n'est pas arrivée) : rien n'est pris trop tôt")
    verifier(direct("Voxile est prête, je te l'envoie demain") == .autre && direct("Voxile 0.3.3 publiée ce soir") == .autre,
             "une phrase qui PARLE de l'app (sans virgule ni demande) : l'encoche de la dictée reste")
    verifier(direct("Bonjour Paul, rappelle-moi demain") == .autre && direct("Notre réunion de demain") == .autre && direct("") == .autre,
             "sans le mot d'appel en tête : jamais pour l'app")
    verifier(direct("Lucarne, rappelle-moi") == .autre && direct("Verbe, note : le devis") == .autre,
             "« Lucarne, … », « Verbe, … » : plus des mots d'appel, l'encoche de la dictée reste")
    verifier(direct("Voxil, rappelle-moi") == .pourLucarne(.rappel) && direct("Boxile, rappelle-moi") == .pourLucarne(.rappel)
             && direct("Voxel, minuteur de 5 minutes") == .pourLucarne(nil),
             "« Voxil » (dit pareil) ou « Boxile » (proche) suivis d'une demande en toutes lettres : pour l'app")
    verifier(direct("Boxile, j'ai une livraison") == .autre && direct("Voxel, je t'envoie le fichier") == .autre && direct("Voici le rappel de la réunion") == .autre
             && direct("Boxile rappelle-moi") == .autre,
             "un mot seulement proche, sans ponctuation ou sans demande en toutes lettres (« Voici le rappel… ») : l'encoche de la dictée reste")
    verifier(direct("Voxile noté dans la liste") == .autre && direct("Voxile notre devis") == .autre, "« noté », « notre » ne sont pas « note »")

    groupe("Voix : la commande « note »")
    func lu(_ s: String) -> ResultatLucarne { AnalyseCommandeIlot.lucarne(s, maintenant: t, calendrier: cal) }
    verifier(lu("Voxile, note : montrer le prix dès la première page, avec trois exemples de clients.")
             == .note(texte: "Montrer le prix dès la première page, avec trois exemples de clients."), "la note de la maquette, telle quelle")
    verifier(lu("Voxile, prends une note pour dire que le devis est validé") == .note(texte: "Le devis est validé.")
             && lu("Voxile, note que Paul rappelle lundi s'il te plaît") == .note(texte: "Paul rappelle lundi."),
             "« pour dire que », « que », « s'il te plaît » tombent ; une majuscule, un point")
    verifier(lu("Voxile, note un rappel demain à 9 h pour appeler Paul") == .commande(.rappel(texte: "Appeler Paul", quand: date(13, 9))),
             "« note un rappel… » reste un rappel")
    verifier(lu("Voxile, note :") == .incomprise(phrase: "Voxile, note :"), "« note » sans rien après : « Je n'ai pas compris » (rien de vide n'est gardé)")
    verifier(lu("Voxile, notre devis est prêt") == .incomprise(phrase: "Voxile, notre devis est prêt"), "« notre » n'est pas une note")
    verifier(lu("Voxile, note sur le budget : réduire les frais.") == .note(texte: "Sur le budget : réduire les frais.")
             && lu("Voxile, une note de 15 sur 20 pour Paul") == .note(texte: "De 15 sur 20 pour Paul."),
             "seuls « que » et « pour dire que » tombent : « sur le budget », « de 15 sur 20 » gardent leur sens")
    verifier(lu("Voxile une note de 15 sur 20 pour Paul") == .aucune && direct("Voxile note bien les retards") == .autre
             && lu("Voxile prends une note : appeler le garage") == .note(texte: "Appeler le garage."),
             "sans virgule, « note » / « une note » seuls parlent peut-être DE l'app : collés ; « prends une note » est une demande")

    groupe("Voix : le titre et le résumé")
    verifier(ResumeVoix.titre("La livraison", sansArticle: true) == "Livraison" && ResumeVoix.titre("Le prix sur la première page", sansArticle: true) == "Prix sur la première page",
             "un rappel : l'article tombe devant un nom (« Livraison », comme la maquette)")
    verifier(ResumeVoix.titre("Le Bon Coin à relancer", sansArticle: true) == "Le Bon Coin à relancer" && ResumeVoix.titre("Les 3 devis", sansArticle: true) == "Les 3 devis",
             "jamais devant un nom propre ni un chiffre")
    verifier(ResumeVoix.titre("Le devis est validé.") == "Le devis est validé", "une note garde son article (« Devis est validé » ne se dit pas)")
    verifier(ResumeVoix.titre("Montrer le prix dès la première page, avec trois exemples de clients.") == "Montrer le prix dès la première page",
             "la première idée (jusqu'à la virgule)")
    verifier(ResumeVoix.titre("Appeler Ladislas pour le devis de la toiture") == "Appeler Ladislas" && ResumeVoix.titre("Livraison pour Paul") == "Livraison pour Paul",
             "« pour… » coupé après deux mots au moins, jamais après un seul")
    verifier(ResumeVoix.titre("Il faut. Vraiment.") == "Il faut" && ResumeVoix.titre("") == "Note" && ResumeVoix.titre("…") == "Note", "la première phrase ; rien : « Note »")
    let long = ResumeVoix.titre("Préparer la présentation complète du budget prévisionnel annuel de la direction")
    verifier(long.count <= ResumeVoix.titreMax + 1 && long.hasSuffix("\u{2026}") && !long.contains(" \u{2026}") && long.hasPrefix("Préparer la présentation"),
             "un titre trop long : coupé entre deux mots, « … » (\(long))")
    verifier(ResumeVoix.phraseEntendue("Voxile, rappelle-moi demain à 13 h pour la livraison s'il te plaît") == "Rappelle-moi demain à 13 h pour la livraison.",
             "la phrase entendue : sans le mot d'appel ni la politesse, une majuscule, un point")

    groupe("Voix : la carte de fin")
    let id = UUID()
    let c1 = CarteVoix.rappel(id: id, texte: "La livraison", echeance: date(13, 13), phrase: "Voxile, rappelle-moi demain à 13 h pour la livraison.", maintenant: t, calendrier: cal)
    verifier(c1.titre == "Livraison" && c1.quand == "demain \u{00B7} 13:00" && c1.resume == "Rappelle-moi demain à 13 h pour la livraison." && c1.genre == .rappel
             && c1.objet == .rappel(id), "le rappel de la maquette : « Livraison », « demain · 13:00 », la phrase entendue (\(c1.titre) / \(c1.quand ?? "-"))")
    let c2 = CarteVoix.rappel(id: id, texte: "Appeler Paul", echeance: date(12, 18), phrase: "Voxile, rappelle-moi d'appeler Paul à 18 h", maintenant: t, calendrier: cal)
    verifier(c2.quand == "aujourd\u{2019}hui \u{00B7} 18:00", "aujourd'hui · 18:00")
    let nuit = CarteVoix.rappel(id: id, texte: "Livraison", echeance: date(12, 13), phrase: "", maintenant: date(12, 0, 30), calendrier: cal)
    verifier(nuit.quand == "jeudi 12 \u{00B7} 13:00", "dit à 0 h 30 : le jour est nommé, jamais « demain » qui tromperait (\(nuit.quand ?? "-"))")
    let c3 = CarteVoix.note(id: id, texte: "Montrer le prix dès la première page, avec trois exemples de clients.")
    verifier(c3.titre == "Montrer le prix dès la première page" && c3.resume == "Montrer le prix dès la première page, avec trois exemples de clients."
             && c3.quand == nil && c3.genre == .note, "la note : sa première idée en titre, la note entière dessous")
    verifier(CarteVoix.note(id: id, texte: "Acheter du pain.").resume.isEmpty && CarteVoix.note(id: id, texte: "Le devis est validé.").resume.isEmpty,
             "une note qui tient dans son titre : pas de résumé (la carte est plus courte)")

    groupe("Voix : le bouton d'envoi")
    verifier(EnvoiVoix.aEnvoyer.libelle(.rappel) == "Envoyer dans Rappels" && EnvoiVoix.fait.libelle(.rappel) == "Dans Rappels"
             && EnvoiVoix.aEnvoyer.libelle(.note) == "Envoyer dans Notes" && EnvoiVoix.fait.libelle(.note) == "Dans Notes", "les libellés de la maquette")
    verifier(EnvoiVoix.rappel(lie: true, acces: .refuse) == .fait && EnvoiVoix.rappel(lie: false, acces: .refuse) == .refuse
             && EnvoiVoix.rappel(lie: false, acces: .nonDemande) == .aEnvoyer && EnvoiVoix.rappel(lie: false, acces: .autorise) == .aEnvoyer,
             "déjà dans Rappels : fait ; refusé : « Autoriser dans Réglages » ; sinon « Envoyer dans Rappels »")
    verifier(EnvoiVoix.rappel(lie: false, acces: .autorise, essaye: true) == .echec && EnvoiVoix.rappel(lie: false, acces: .refuse, essaye: true) == .refuse
             && EnvoiVoix.rappel(lie: true, acces: .autorise, essaye: true) == .fait && EnvoiVoix.rappel(lie: false, acces: .nonDemande, essaye: true) == .aEnvoyer,
             "un envoi tenté, accès donné, mais rien d'enregistré : « Réessayer » (jamais « Autoriser dans Réglages »)")
    verifier(EnvoiVoix.echec.libelle(.note) == "Réessayer" && EnvoiVoix.echec.message(.note) == "Notes n\u{2019}a pas répondu"
             && EnvoiVoix.echec.message(.rappel) == "Rappels n\u{2019}a pas répondu" && EnvoiVoix.tous.filter { $0.message(.note) != nil } == [.echec],
             "après un échec sans refus : « Réessayer » et un message court ; aucun autre état n'a de message")
    verifier(EnvoiVoix.libelles(.rappel).count == 5 && Set(EnvoiVoix.libelles(.note)).count == 5, "cinq états, cinq libellés")

    groupe("Voix : la réponse de l'app Notes")
    verifier(ResultatVersNotes.depuis(erreur: nil) == .fait, "le script a réussi : dans Notes")
    verifier(ResultatVersNotes.depuis(erreur: -1743) == .refuse && ResultatVersNotes.depuis(erreur: -1744) == .refuse,
             "-1743 (Automatisation refusée), -1744 (autorisation impossible à demander) : un refus, « Autoriser dans Réglages »")
    verifier([-1712, -600, -609, -2700, -10000, 1].allSatisfy { ResultatVersNotes.depuis(erreur: $0) == .echec },
             "trop lent (-1712), Notes fermé ou parti (-600, -609), erreur du script : un échec, « Réessayer », jamais pris pour un refus")

    groupe("Voix : une dictée prise par l'îlot sans commande")
    verifier(IssueVoix.sansCommande(priseParLIlot: true) == .garderDansLIlot && IssueVoix.sansCommande(priseParLIlot: false) == .coller,
             "l'îlot l'avait prise (l'onde, « Rappel… ») : jamais collée en silence, gardée dans l'îlot avec « Copier » ; une dictée normale est collée")
    verifier(PlanCarteRappel.envoyerTout(choix: .oui, acces: .autorise) && !PlanCarteRappel.envoyerTout(choix: nil, acces: .autorise)
             && !PlanCarteRappel.envoyerTout(choix: .non, acces: .autorise) && !PlanCarteRappel.envoyerTout(choix: .oui, acces: .nonDemande),
             "il part seul seulement si Hugues l'a déjà voulu (« Oui » ou un clic sur la carte) et que l'accès est donné ; sinon, rien sans son clic")

    groupe("Voix : l'onde")
    var o = OndeVoix()
    verifier((0..<OndeVoix.barres).allSatisfy { o.hauteur($0, a: 3) == 0 }, "rien reçu : toutes les barres en bas")
    for k in 0..<40 { o.recevoir(0.6, a: 100 + Double(k) * OndeVoix.pas) }
    let tv = 100 + 40 * OndeVoix.pas
    let h = (0..<OndeVoix.barres).map { o.hauteur($0, a: tv) }
    verifier(h[15] > 0.5 && h[15] <= 1, "une voix ordinaire (0,6) : le milieu monte haut (\(String(format: "%.2f", h[15])))")
    verifier(h[0] < h[15] && h[30] < h[15] && h[5] < h[12], "plus haute au milieu, plus basse vers les bords (une cloche)")
    // un mot qui arrive : le milieu le reçoit d'abord, les bords un pas plus tard par barre
    var o2 = OndeVoix()
    for k in 0..<20 { o2.recevoir(0, a: Double(k) * OndeVoix.pas) }
    for k in 20..<24 { o2.recevoir(0.9, a: Double(k) * OndeVoix.pas) }
    let tm = 24 * OndeVoix.pas
    verifier(o2.hauteur(15, a: tm) > 0.3 && o2.hauteur(0, a: tm) < 0.05 && o2.hauteur(30, a: tm) < 0.05,
             "un mot qui commence : le milieu monte, les bords pas encore (\(String(format: "%.2f / %.2f", o2.hauteur(15, a: tm), o2.hauteur(0, a: tm))))")
    let pasFin = stride(from: 0.8, through: 1.4, by: 1.0 / 120).map { o2.hauteur(15, a: $0) }
    verifier(zip(pasFin, pasFin.dropFirst()).allSatisfy { abs($0 - $1) < 0.08 }, "à l'écran (120 images par seconde), aucune barre ne saute : des ressorts, pas un diaporama")
    // le relâchement : la voix s'éteint, la petite vague prend le relais
    var o3 = o
    o3.relacher(a: tv)
    let apres = (0..<OndeVoix.barres).map { o3.hauteur($0, a: tv + 1.2) }
    verifier(apres.max()! <= 0.35 && apres.max()! > 0.05, "relâché : l'onde se calme, une petite vague la parcourt (\(String(format: "%.2f", apres.max()!)))")
    verifier(abs(o3.hauteur(15, a: tv) - o.hauteur(15, a: tv)) < 0.001, "au relâchement, rien ne saute")
    // le micro prend du retard (un trou de 2 s) : rien ne casse, la mémoire reste bornée
    var o4 = OndeVoix()
    o4.recevoir(0.5, a: 0); o4.recevoir(0.5, a: 2); o4.recevoir(0.5, a: 600)
    verifier(o4.niveaux.count <= 64 && o4.premier + o4.niveaux.count - 1 == Int(600 / OndeVoix.pas) && o4.hauteur(15, a: 600.2).isFinite,
             "un trou dans les niveaux (micro en retard, 10 min) : la mémoire reste à 64 pas, le dernier pas est le bon")
    var o5 = OndeVoix(); o5.recevoir(0.2, a: 0); o5.recevoir(0.9, a: 0.01)
    verifier(o5.niveaux.count == 1 && o5.niveaux[0] > 0.6, "deux niveaux dans le même pas : le plus fort reste (une syllabe brève ne se perd pas)")
    // l'onde des cartes d'accueil, recâblée sur la même somme de ressorts, n'a pas bougé
    verifier(NiveauxVoix.valeur(4, t: 1.23) == NiveauxVoix.valeur(t: 1.23, pas: NiveauxVoix.pas) { NiveauxVoix.niveau(4, $0) }, "NiveauxVoix : le même calcul pour les deux ondes")

    groupe("Voix : la forme")
    for v in [VueIlot.voixEcoute, .voixCarte] {
        let g = GeoIlot.valeurs(v, hauteurBarre: 33, epaules: true)
        verifier(g[0] + max(g[3], g[6]) <= GeoIlot.aileMax, "\(v.rawValue) : ≤ 66 pt dans la barre de chaque côté de la caméra (\(g[0] + max(g[3], g[6])))")
        verifier(g[1] >= g[0] + max(g[3], g[6]) + 40, "\(v.rawValue) : le corps s'évase assez sous la barre (pas une languette)")
        verifier(!v.estAlerte && !GeoIlot.ajusteAuContenu(v), "\(v.rawValue) : pas une alerte ; sa largeur est fixe (l'onde et la carte ne changent pas de largeur en route)")
    }
    verifier(GeoIlot.aEpaules(.voixCarte) && !GeoIlot.aEpaules(.voixEcoute), "la carte montre les épaules (batterie, écouteurs), comme la maquette ; l'écoute non")
    verifier(MesuresVoix.profondeurOnde == 48 && MesuresVoix.profondeurOnde + MesuresVoix.ligneLibelle == 72, "l'onde : 48 pt sous la barre, 72 avec le libellé (maquette)")
    verifier(MesuresVoix.profondeurCarte(quand: true, lignesResume: 1) == 127 && MesuresVoix.profondeurCarte(quand: false, lignesResume: 2) == 126
             && MesuresVoix.profondeurCarte(quand: false, lignesResume: 0) == 89, "la carte : 127 pt (rappel), 126 (note à deux lignes), 89 (note sans résumé)")
    verifier(GeoIlot.profondeur(.voixCarte) == MesuresVoix.profondeurCarteMax, "la table a la carte la plus haute")
}
