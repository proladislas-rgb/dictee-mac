import Foundation
import DicteeCore

/// Remise au propre du texte de Whisper par la petite IA de Groq (lot 6). Ne casse jamais la dictée :
/// à la moindre difficulté (inutile, lent, erreur, sortie suspecte), on rend le texte brut.
enum Nettoyage {
    struct Resultat {
        var texte: String
        var utilise: Bool
        /// Pourquoi le texte brut a été gardé, ou « ok ».
        var raison: String
        var duree: Double
        /// Réponse brute de l'IA quand elle a été refusée (affichée par `--nettoyer` seulement, jamais journalisée).
        var sortieRefusee: String?
    }

    static func executer(_ brut: String, contexte: ContexteMiseEnForme, mots: [String],
                         modele: String = Settings.modeleNettoyage, delai: Double = Settings.delaiNettoyage, secours: Double = Settings.secoursNettoyage,
                         forcer: Bool = false, finDeTexte: Bool = true) async -> Resultat {
        let debut = ProcessInfo.processInfo.systemUptime
        func rendre(_ texte: String, _ utilise: Bool, _ raison: String) -> Resultat {
            Resultat(texte: texte, utilise: utilise, raison: raison, duree: ProcessInfo.processInfo.systemUptime - debut)
        }
        guard forcer || Settings.remettreAuPropre else { return rendre(brut, false, "réglage désactivé") }
        guard GroqClient.shared.cleDisponible else { return rendre(brut, false, "pas de clé") }
        let analyse = RemiseAuPropre.analyser(brut)
        guard analyse.utile else { return rendre(brut, false, "inutile (\(analyse.nombreDeMots) mots, rien à corriger)") }

        let systeme = RemiseAuPropre.consignes(contexte: contexte, mots: mots)
        // Requête de secours : si la réponse tarde (> 0,55 s), une seconde requête identique part (budget permettant) ;
        // la première réponse arrivée gagne. Le délai maximal reste `delai`.
        enum Issue { case texte(String), echec, delai }
        let reponse: String? = await withTaskGroup(of: Issue.self) { groupe -> String? in
            groupe.addTask {
                if let t = try? await GroqClient.shared.completer(modele: modele, systeme: systeme, texte: brut, delai: delai) { return .texte(t) }
                return .echec
            }
            groupe.addTask {
                if secours >= delai { return .echec }
                try? await Task.sleep(for: .seconds(secours))
                guard !Task.isCancelled, BudgetRequetes.nettoyage.permet(.secours) else { return .echec }
                Log.ecrire("remise au propre : réponse attendue depuis \(Int(secours * 1000)) ms, requête de secours lancée")
                if let t = try? await GroqClient.shared.completer(modele: modele, systeme: systeme, texte: brut, delai: max(0.2, delai - secours)) { return .texte(t) }
                return .echec
            }
            groupe.addTask { try? await Task.sleep(for: .seconds(delai)); return .delai }
            var echecs = 0
            for await issue in groupe {
                switch issue {
                case .texte(let t): groupe.cancelAll(); return t
                case .delai: groupe.cancelAll(); return nil
                case .echec: echecs += 1; if echecs >= 2 { groupe.cancelAll(); return nil }
                }
            }
            return nil
        }
        guard let reponse else { return rendre(brut, false, "trop lent ou en erreur (> \(delai) s)") }
        switch RemiseAuPropre.verifier(entree: brut, sortie: reponse, analyse: analyse) {
        case .refuse(let pourquoi):
            var r = rendre(brut, false, "sortie refusée : \(pourquoi)"); r.sortieRefusee = reponse; return r
        case .accepte(let texte): return rendre(RemiseAuPropre.retoucher(RemiseAuPropre.corrigerMots(texte, dictionnaire: mots), entree: brut, contexte: contexte, finDeTexte: finDeTexte), true, "ok")
        }
    }
}
