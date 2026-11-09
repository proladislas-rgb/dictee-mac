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

}
