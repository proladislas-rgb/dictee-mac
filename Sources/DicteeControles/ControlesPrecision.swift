import Foundation
import DicteeCore

/// Contrôles de la chaîne « précision » : modèle de transcription, quota par modèle, suivi de latence, relecture, expressions, test sur la vraie voix.
/// Appelée depuis main.swift (un seul appel, pour ne pas toucher au reste du fichier).
func controlesPrecision() {
    groupe("Précision : modèle de transcription")
    verifier(ModeleWhisper.parDefaut == .precis, "défaut : Précis (large-v3), choix du 10/11 d'après le banc")
    verifier(ModeleWhisper.rapide.identifiant == "whisper-large-v3-turbo", "Rapide = turbo")
    verifier(ModeleWhisper.precis.identifiant == "whisper-large-v3", "Précis = large-v3")
    verifier(ModeleWhisper.depuis(reglage: "precis") == .precis && ModeleWhisper.depuis(reglage: "Large-V3") == .precis && ModeleWhisper.depuis(reglage: "whisper-large-v3-turbo") == .rapide, "réglage lu : precis, large-v3, identifiant Groq")
    verifier(ModeleWhisper.depuis(reglage: nil) == nil && ModeleWhisper.depuis(reglage: "n'importe quoi") == nil, "réglage inconnu : nil (le défaut s'applique)")
    verifier(ModeleWhisper.rapide.secours == .precis && ModeleWhisper.precis.secours == .rapide, "le secours est l'autre modèle")
    verifier(ModeleWhisper.defautSelonMesures(medianeRapide: 290, medianePrecis: 400) == .precis, "+110 ms : le précis devient le défaut")
    verifier(ModeleWhisper.defautSelonMesures(medianeRapide: 290, medianePrecis: 440) == .precis, "+150 ms pile : le précis reste admis")
    verifier(ModeleWhisper.defautSelonMesures(medianeRapide: 290, medianePrecis: 441) == .rapide, "+151 ms : le turbo reste le défaut")

    groupe("Précision : un budget de requêtes par modèle")
    verifier(BudgetRequetes.whisper(.rapide) === BudgetRequetes.partage && BudgetRequetes.whisper(.precis) === BudgetRequetes.precis, "chaque modèle a son compteur")
    do {
        let t = 5_000.0
        let turbo = BudgetRequetes(), precis = BudgetRequetes()
        for i in 0..<12 { turbo.noterEnvoi(a: t + Double(i) * 0.1) }
        verifier(turbo.restantMinute(a: t + 2) == 6 && precis.restantMinute(a: t + 2) == 18, "12 requêtes turbo n'entament pas le compteur du précis")
        precis.noter429(retryAfter: 30, a: t)
        verifier(precis.enPause(a: t + 10) && !turbo.enPause(a: t + 10), "429 sur le précis : en pause, pas le turbo")
    }

    groupe("Précision : modèles de langue de secours (qwen / gpt-oss 120b / 20b)")
    verifier(ModelesTexte.ordre(prefere: ModelesTexte.petit, pauses: [:], maintenant: 100) == [ModelesTexte.petit, ModelesTexte.rapide, ModelesTexte.grand], "20b d'abord, puis qwen, puis le 120b")
    verifier(ModelesTexte.ordre(prefere: ModelesTexte.rapide, pauses: [:], maintenant: 100) == [ModelesTexte.rapide, ModelesTexte.grand, ModelesTexte.petit], "relecture : qwen d'abord")
    verifier(ModelesTexte.ordre(prefere: ModelesTexte.petit, pauses: [ModelesTexte.petit: 150], maintenant: 100) == [ModelesTexte.rapide, ModelesTexte.grand], "20b en pause (429) : directement le suivant")
    verifier(ModelesTexte.ordre(prefere: ModelesTexte.petit, pauses: [ModelesTexte.petit: 90], maintenant: 100).first == ModelesTexte.petit, "pause finie : le 20b revient")
    verifier(ModelesTexte.ordre(prefere: ModelesTexte.petit, pauses: Dictionary(uniqueKeysWithValues: [ModelesTexte.petit, ModelesTexte.grand, ModelesTexte.rapide].map { ($0, 150.0) }), maintenant: 100).isEmpty, "tous à sec : aucun")
    verifier(ModelesTexte.ordre(prefere: "autre/modele", pauses: [:], maintenant: 100) == ["autre/modele"], "modèle inconnu : pas de relais")
    verifier(ModelesTexte.effortDeRaisonnement(ModelesTexte.rapide) == "none" && ModelesTexte.effortDeRaisonnement(ModelesTexte.petit) == "low" && ModelesTexte.effortDeRaisonnement("autre") == nil, "raisonnement coupé pour qwen, « low » pour gpt-oss")

    groupe("Précision : latences mesurées")
    do {
        var l = SuiviLatence()
        verifier(l.mediane(.rapide) == nil && l.texte(.rapide) == nil, "moins de 3 mesures : aucun chiffre")
        for ms in [300, 280, 320] { l.noter(ms, modele: .rapide) }
        verifier(l.mediane(.rapide) == 300 && l.texte(.rapide) == "300 ms", "médiane de 3 mesures")
        for ms in [410, 380, 450, 400] { l.noter(ms, modele: .precis) }
        verifier(l.mediane(.precis) == 405, "médiane de 4 mesures = moyenne des deux du milieu")
        l.noter(-5, modele: .rapide); l.noter(99_999, modele: .rapide)
        verifier(l.parModele["rapide"]?.count == 3, "mesure absurde ignorée")
        for _ in 0..<50 { l.noter(100, modele: .rapide) }
        verifier(l.parModele["rapide"]?.count == SuiviLatence.garde, "30 mesures gardées au plus")
        verifier(SuiviLatence.depuis(l.donnees()) == l, "enregistrement aller-retour")
        verifier(SuiviLatence().phrase() == "Rapide : le plus rapide.\nPrécis : un peu plus lent, plus juste.", "phrase sans mesure")
        verifier(l.phrase().contains("environ 100 ms chez toi") && l.phrase().contains("environ 410 ms chez toi"), "phrase avec les chiffres chez Hugues")
    }

    controlesExpressions()
    controlesApprentissage()
}

// MARK: expressions

private func controlesExpressions() {
    groupe("Précision : expressions personnelles (extraction de l'historique)")
    let phrases = [
        "Ok t'inquiète, je te rappelle demain.", "T'inquiète pas, on se capte demain.", "Bref, t'inquiète on y va.", "Wesh, on se capte demain ?",
        "Franchement c'est lourd, ce truc.", "Ah c'est lourd, grave.", "C'est lourd, vraiment.", "Wesh frère, ça va ?",
        "Le rendez-vous est confirmé pour mardi.", "Je suis en réunion jusqu'à midi.", "Peux-tu m'envoyer le devis ?", "Wesh, t'es où ?",
        "Je t'appelle ce soir.", "Voici le compte rendu de la réunion.", "On se capte demain matin, ça marche ?", "Grave, on fait comme ça.",
    ]
    let connuCorrecteur: (String) -> Bool = { m in !["wesh", "t'inquiète", "inquiète", "capte"].contains(m.lowercased()) }
    let trouvees = ExtractionExpressions.extraire(textes: phrases, estConnu: connuCorrecteur)
    let textes = trouvees.map(\.texte)
    verifier(textes.contains("wesh"), "« wesh » (4 dictées) retrouvé")
    verifier(textes.contains(where: { $0.contains("lourd") }), "« c'est lourd » retrouvé")
    verifier(textes.contains(where: { $0.contains("capte") }), "« on se capte » retrouvé")
    verifier(!textes.contains("rendez-vous") && !textes.contains("réunion") && !textes.contains("je"), "mots ordinaires non retenus")
    verifier(trouvees.allSatisfy { $0.dictees >= 3 }, "chaque expression apparaît dans au moins 3 dictées")
    verifier(ExtractionExpressions.extraire(textes: phrases, existants: ["wesh"], estConnu: connuCorrecteur).map(\.texte).contains("wesh") == false, "un mot déjà dans mots.txt n'est pas reproposé")
    verifier(ExtractionExpressions.extraire(textes: phrases, exclues: ["wesh"], estConnu: connuCorrecteur).map(\.texte).contains("wesh") == false, "une expression retirée par Hugues ne revient pas")
    verifier(ExtractionExpressions.extraire(textes: Array(phrases.prefix(2)), estConnu: connuCorrecteur).isEmpty, "trop peu de dictées : rien")
    verifier(ExtractionExpressions.extraire(textes: ["je suis là", "je suis là", "je suis là", "je suis là", "je suis là", "je suis là", "je suis là"], estConnu: { _ in true }).isEmpty, "une phrase banale répétée n'est pas une expression")

    groupe("Précision : liste d'expressions (ajout, retrait, mise à jour, semaine)")
    var l = ListeExpressions()
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    verifier(l.extractionDue(maintenant: t0), "jamais extraite : due")
    let nouvelles = l.fusionner(extraites: [("t'inquiète", 12), ("on se capte", 7)], maintenant: t0)
    verifier(nouvelles == ["t'inquiète", "on se capte"] && l.expressions.count == 2, "première extraction : deux expressions apprises")
    verifier(!l.extractionDue(maintenant: t0.addingTimeInterval(3 * 3600)), "3 h après : pas due")
    verifier(l.extractionDue(maintenant: t0.addingTimeInterval(21 * 3600)), "21 h après : due (une fois par jour)")
    verifier(l.apprisCetteSemaine(maintenant: t0.addingTimeInterval(86_400)) == 2, "deux appris cette semaine")
    verifier(l.apprisCetteSemaine(maintenant: t0.addingTimeInterval(8 * 86_400)) == 0, "huit jours plus tard : plus dans la semaine")
    verifier(l.ajouterManuelle("c'est carré", maintenant: t0) && !l.ajouterManuelle("C'est carré"), "ajout à la main, sans doublon")
    l.retirer("on se capte")
    verifier(!l.contient("on se capte") && l.exclues.count == 1, "retrait : exclue")
    let encore = l.fusionner(extraites: [("t'inquiète", 15), ("on se capte", 8), ("wesh", 5)], maintenant: t0.addingTimeInterval(86_400))
    verifier(encore == ["wesh"], "l'extraction suivante ne remet pas l'expression retirée, ajoute la nouvelle")
    verifier(l.expressions.first(where: { $0.texte == "t'inquiète" })?.dictees == 15, "compteur de dictées mis à jour")
    verifier(l.expressions.contains(where: { $0.texte == "c'est carré" && $0.manuelle }), "l'expression ajoutée à la main reste")
    verifier(l.pourWhisper(maximum: 2) == ["c'est carré", "t'inquiète"], "pour Whisper : celles de Hugues d'abord, puis les plus fréquentes")
    l.noterMotAppris("Qonto", maintenant: t0.addingTimeInterval(86_400))
    verifier(l.appris.last?.genre == .mot && l.apprisCetteSemaine(maintenant: t0.addingTimeInterval(86_400)) == 4, "un mot appris par correction répétée compte aussi")
    verifier(ListeExpressions.depuis(l.donnees()) == l, "enregistrement JSON aller-retour")
    var vieux = ListeExpressions(); vieux.noterMotAppris("ancien", maintenant: t0)
    vieux.noterMotAppris("récent", maintenant: t0.addingTimeInterval(70 * 86_400))
    verifier(vieux.appris.count == 1, "journal d'apprentissage : plus de 60 jours effacés")

    groupe("Précision : expressions dans le prompt de Whisper")
    let sans = ChoixMotsPrompt.prompt(motsChoisis: ["Groq"], lexique: [], contexte: ContexteMots(), texteDavant: nil, ancre: "Transcription d'une dictée en français.")
    let avec = ChoixMotsPrompt.prompt(motsChoisis: ["Groq"], expressions: ["t'inquiète", "on se capte", "c'est lourd"], lexique: [], contexte: ContexteMots(), texteDavant: nil, ancre: "Transcription d'une dictée en français.")
    verifier(avec.contains("t'inquiète") && avec.contains("on se capte") && avec.hasPrefix("Transcription d'une dictée en français. Groq,"), "expressions après l'ancre et mots.txt")
    verifier(!sans.contains("t'inquiète"), "sans expressions : prompt d'avant")
    let beaucoup = (1...40).map { "expression numéro \($0) assez longue" }
    let gros = ChoixMotsPrompt.prompt(motsChoisis: ["Groq"], expressions: beaucoup, lexique: [], contexte: ContexteMots(), texteDavant: String(repeating: "mot précédent ", count: 40), ancre: "Transcription d'une dictée en français.")
    verifier(ChoixMotsPrompt.jetons(gros) <= ChoixMotsPrompt.budgetParDefaut, "beaucoup d'expressions : le prompt reste dans le budget de jetons")
    let nbExpr = gros.components(separatedBy: "expression numéro").count - 1
    verifier(nbExpr <= 10 && nbExpr >= 1, "au plus 45 jetons d'expressions (\(nbExpr) retenues)")
    verifier(gros.contains("mot précédent"), "le texte précédent garde sa place")
}

// MARK: apprentissage automatique des corrections

private func controlesApprentissage() {
    groupe("Précision : une correction qui revient 2 fois est apprise toute seule")
    var p = PropositionsMots()
    verifier(p.noter("Qonto", dictee: "a-1", motsConnus: []) == .proposee && p.enAttente == ["Qonto"], "première correction : proposée dans Mots")
    verifier(p.noter("Qonto", dictee: "a-1", motsConnus: []) == .dejaVue && p.enAttente == ["Qonto"], "relue 15 s plus tard dans la même dictée : ne compte pas deux fois")
    verifier(p.noter("qonto", dictee: "a-2", motsConnus: []) == .apprise && p.enAttente.isEmpty, "même correction dans une autre dictée : apprise, sortie de la liste d'attente")
    verifier(p.noter("Qonto", dictee: "a-3", motsConnus: ["Qonto"]) == .ignoree, "déjà dans mots.txt : rien")
    var q = PropositionsMots()
    _ = q.noter("Brume", dictee: "b-1", motsConnus: [])
    q.ignorer("Brume")
    verifier(q.noter("Brume", dictee: "b-2", motsConnus: []) == .ignoree, "mot ignoré par Hugues : jamais appris tout seul")
    var vide = PropositionsMots()
    verifier(vide.noter("   ", dictee: "x", motsConnus: []) == .ignoree, "mot vide : rien")
    var r = PropositionsMots()
    _ = r.noter("Tuget", dictee: "c-1", motsConnus: [])
    let donnees = try? JSONEncoder().encode(r)
    var relu = donnees.flatMap { try? JSONDecoder().decode(PropositionsMots.self, from: $0) }
    verifier(relu?.noter("Tuget", dictee: "c-2", motsConnus: []) == .apprise, "le compte survit à l'enregistrement (propositions.json)")
    let ancien = Data(#"{"enAttente":["Brume"],"ignores":["Zed"]}"#.utf8)
    verifier((try? JSONDecoder().decode(PropositionsMots.self, from: ancien))?.enAttente == ["Brume"], "ancien propositions.json (sans compteur) toujours lisible")
}
