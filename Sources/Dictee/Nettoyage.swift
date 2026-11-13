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
        /// La relecture de sens a changé des mots : (avant, après) en mots.
        var relecture: String?
    }

    static func executer(_ brut: String, contexte: ContexteMiseEnForme, mots: [String],
                         modele: String = Settings.modeleNettoyage, delai: Double = Settings.delaiNettoyage, secours: Double = Settings.secoursNettoyage,
                         forcer: Bool = false, finDeTexte: Bool = true, relecture: RelectureSession? = nil) async -> Resultat {
        let debut = ProcessInfo.processInfo.systemUptime
        func rendre(_ texte: String, _ utilise: Bool, _ raison: String) -> Resultat {
            Resultat(texte: texte, utilise: utilise, raison: raison, duree: ProcessInfo.processInfo.systemUptime - debut)
        }
        let nettoyageActif = forcer || Settings.remettreAuPropre
        guard GroqClient.shared.cleDisponible else { return rendre(brut, false, "pas de clé") }
        let analyse = RemiseAuPropre.analyser(brut)
        let remiseUtile = nettoyageActif && analyse.utile
        // Relecture de sens : décidée sur le texte brut (correcteur orthographique, vocabulaire de Hugues, contexte du champ).
        let tDecision = ProcessInfo.processInfo.systemUptime
        let entreeRelecture = await relecture?.preparer(brut)
        let decisionMs = Int((ProcessInfo.processInfo.systemUptime - tDecision) * 1000)
        if entreeRelecture == nil, relecture != nil, decisionMs >= 8 { Log.ecrire("relecture : inutile pour ce texte (décision en \(decisionMs) ms)") }
        if let r = entreeRelecture {
            Log.ecrire("relecture : utile (\(r.declenchement.raison.rawValue) : \(r.declenchement.suspects.map { Log.apercu($0) }.joined(separator: ", "))), décision en \(Int(r.dureeDecision * 1000)) ms, \(remiseUtile ? "avec la remise au propre en un seul appel" : "appel seul")")
        }
        guard remiseUtile || entreeRelecture != nil else {
            return rendre(brut, false, nettoyageActif ? "inutile (\(analyse.nombreDeMots) mots, rien à corriger)" : "réglage désactivé")
        }
        // Relecture seule : pas de remise au propre à faire, une courte requête avec son propre délai (au plus +250 ms, sinon on colle tel quel).
        let relectureSeule = !remiseUtile
        // Groq vient de refuser ce réseau (VPN) : pas de requête vouée au même refus, le texte tel quel
        if GroqClient.shared.reseauRefuse { return rendre(brut, false, "Groq refuse ce réseau (VPN ?), aucune requête") }
        if relectureSeule, !BudgetRequetes.nettoyage.permet(.anticipation) {
            return rendre(brut, false, "relecture non faite : budget de requêtes bas")
        }
        let modele = relectureSeule ? Settings.modeleRelecture : modele
        let delai = relectureSeule ? Settings.delaiRelecture : delai
        let secours = relectureSeule ? 99 : secours
        let systeme = relectureSeule ? Relecture.consigne(entreeRelecture!.contexte)
                                     : RemiseAuPropre.consignes(contexte: contexte, mots: mots, relecture: entreeRelecture?.contexte)
        // Requête de secours : si la réponse tarde (> 0,55 s), une seconde requête identique part (budget permettant) ;
        // la première réponse arrivée gagne. Le délai maximal reste `delai`.
        enum Issue { case texte(String), echec, delai }
        let reponse: String? = await withTaskGroup(of: Issue.self) { groupe -> String? in
            groupe.addTask {
                do { return .texte(try await GroqClient.shared.completer(modele: modele, systeme: systeme, texte: brut, delai: delai)) }
                catch is CancellationError { return .echec }
                catch { Log.ecrire("remise au propre / relecture : échec de la requête (\(error))"); return .echec }
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
        guard let reponse else {
            return rendre(brut, false, relectureSeule ? "relecture trop lente (> \(Int(delai * 1000)) ms), texte collé tel quel" : "trop lent ou en erreur (> \(delai) s)")
        }
        if relectureSeule, let entree = entreeRelecture {
            switch Relecture.verifier(entree: brut, sortie: reponse, suspects: entree.declenchement.suspects) {
            case .refuse(let pourquoi):
                var r = rendre(brut, false, "relecture refusée : \(pourquoi)"); r.sortieRefusee = reponse; return r
            case .accepte(let texte):
                var r = rendre(RemiseAuPropre.retoucher(RemiseAuPropre.corrigerMots(texte, dictionnaire: mots), entree: brut, contexte: contexte, finDeTexte: finDeTexte), true, "ok (relecture seule)")
                r.relecture = Self.differences(brut, texte)
                return r
            }
        }
        switch RemiseAuPropre.verifier(entree: brut, sortie: reponse, analyse: analyse, motsRelus: min(3, entreeRelecture?.declenchement.suspects.count ?? 0)) {
        case .refuse(let pourquoi):
            var r = rendre(brut, false, "sortie refusée : \(pourquoi)"); r.sortieRefusee = reponse; return r
        case .accepte(let texte):
            if let entree = entreeRelecture, let perdu = Relecture.suspectEfface(entree: brut, sortie: texte, suspects: entree.declenchement.suspects) {
                var r = rendre(brut, false, "sortie refusée : mot « \(Log.apercu(perdu)) » effacé au lieu d'être corrigé"); r.sortieRefusee = reponse; return r
            }
            let collés = MotsColles.reparer(entree: brut, sortie: reponse).repares
            if !collés.isEmpty { Log.ecrire("remise au propre : mots collés par l\u{2019}IA remis en mots séparés : \(collés.map { Log.apercu($0) }.joined(separator: ", "))") }
            var r = rendre(RemiseAuPropre.retoucher(RemiseAuPropre.corrigerMots(texte, dictionnaire: mots), entree: brut, contexte: contexte, finDeTexte: finDeTexte), true, "ok")
            if let entree = entreeRelecture { r.relecture = Self.differencesSuspects(brut, texte, suspects: entree.declenchement.suspects) }
            return r
        }
    }

    /// Les mots qui ont changé entre `avant` et `apres`, pour le journal : « Tuget » → « t'inquiète ».
    static func differences(_ avant: String, _ apres: String) -> String? {
        let (de, vers) = Relecture.ecarts(avant, apres)
        guard !de.isEmpty || !vers.isEmpty else { return nil }
        return "\"\(Log.apercu(de.joined(separator: " ")))\" → \"\(Log.apercu(vers.joined(separator: " ")))\""
    }

    /// Dans un appel unique (remise au propre + relecture) : seulement ce qui touche aux mots suspects.
    static func differencesSuspects(_ avant: String, _ apres: String, suspects: [String]) -> String? {
        let permis = Set(suspects.flatMap { RemiseAuPropre.mots($0) })
        guard permis.contains(where: { !RemiseAuPropre.mots(apres).contains($0) }) else { return nil }
        return differences(avant, apres)
    }
}
