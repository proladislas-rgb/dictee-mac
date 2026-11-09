import Foundation
import DicteeCore

/// Ce que la relecture a décidé pour un texte : pourquoi, quels mots font douter, et la consigne (expressions, mots, contexte).
struct RelectureEntree {
    var declenchement: Relecture.Declenchement
    var contexte: ContexteRelecture
    /// Durée de la décision (correcteur orthographique, vocabulaire), pour le journal.
    var dureeDecision: Double
}

/// La relecture d'une dictée : lit le contexte du champ au moment voulu et décide si une relecture de sens est utile.
final class RelectureSession: @unchecked Sendable {
    private let champ: @Sendable () -> ContexteChamp?
    /// Expressions ajoutées à celles de Hugues (modes d'essai en ligne de commande : `--nettoyer ... --expressions "a;b"`).
    private let expressionsEnPlus: [String]

    init(champ: @escaping @Sendable () -> ContexteChamp?, expressionsEnPlus: [String] = []) { self.champ = champ; self.expressionsEnPlus = expressionsEnPlus }

    /// `nil` si la relecture est éteinte, sans clé, ou inutile pour ce texte.
    func preparer(_ texte: String) async -> RelectureEntree? {
        guard Settings.relecture, GroqClient.shared.cleDisponible else { return nil }
        let c = champ()
        let debut = ProcessInfo.processInfo.systemUptime
        let plus = expressionsEnPlus
        return await MainActor.run { VocabulaireRelectureStore.partage.preparer(texte: texte, champ: c, debut: debut, expressionsEnPlus: plus) }
    }
}

/// Le vocabulaire que Hugues connaît : mots.txt, expressions, lexique, mots déjà dictés au moins deux fois. Mis à jour sans relire tout
/// l'historique (seules les nouvelles dictées sont comptées), jamais sur le chemin de la dictée.
@MainActor
final class VocabulaireRelectureStore {
    static let partage = VocabulaireRelectureStore()

    private var compteHistorique: [String: Int] = [:]
    private var dejaVus = Set<UUID>()
    private var statiques = Set<String>()
    private var cleStatique = ""
    private(set) var connus = Set<String>()

    /// À appeler au lancement et après chaque dictée écrite.
    func rafraichir() {
        let entrees = HistoriqueStore.shared.historique.entrees.prefix(1500)
        var change = false
        for e in entrees where !dejaVus.contains(e.id) {
            dejaVus.insert(e.id)
            for m in Relecture.plier([e.texte]) { compteHistorique[m, default: 0] += 1 }
            change = true
        }
        let mots = Dictionnaire.mots(), expressions = ExpressionsStore.partage.liste().expressions.map(\.texte)
        let lexique = LexiqueStore.partage.entrees()
        let cle = "\(mots.count)-\(expressions.count)-\(lexique.count)"
        if cle != cleStatique {
            cleStatique = cle
            statiques = Relecture.plier(mots + expressions + lexique.map(\.mot))
            change = true
        }
        if change { connus = statiques.union(compteHistorique.filter { $0.value >= 2 }.keys) }
    }

    func preparer(texte: String, champ: ContexteChamp?, debut: Double, expressionsEnPlus: [String] = []) -> RelectureEntree? {
        if connus.isEmpty { rafraichir() }
        let avant = champ?.precedent
        let vocabulaire = VocabulaireRelecture(connus: connus.union(Relecture.plier(expressionsEnPlus)), contexte: Relecture.motsDuContexte([avant.map { String($0.suffix(400)) }, champ?.titreFenetre]))
        guard let d = Relecture.declencher(texte: texte, estConnu: Orthographe.estConnu, vocabulaire: vocabulaire) else { return nil }
        let contexte = ContexteRelecture(expressions: expressionsEnPlus + ExpressionsStore.partage.pourWhisper(maximum: 20), mots: Dictionnaire.mots(),
                                         avantCurseur: avant, titreFenetre: champ?.titreFenetre, suspects: d.suspects)
        return RelectureEntree(declenchement: d, contexte: contexte, dureeDecision: ProcessInfo.processInfo.systemUptime - debut)
    }
}
