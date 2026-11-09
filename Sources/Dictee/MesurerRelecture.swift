import Foundation
import DicteeCore

/// `Verbe --declencheurs` : rejoue l'historique (du plus ancien au plus récent) et dit combien de dictées auraient déclenché la relecture de sens,
/// pour chaque raison. Pour chaque dictée, le vocabulaire connu est celui d'avant elle (mots.txt, lexique, expressions, mots déjà dictés deux fois).
/// Ni réseau, ni micro, ni accessibilité. Les extraits affichés restent dans le terminal.
@MainActor
enum MesurerRelecture {
    static func executer(arguments: [String]) -> Int32 {
        guard let donnees = try? Data(contentsOf: HistoriqueStore.urlParDefaut), let h = Historique.depuis(donnees) else {
            print("Historique illisible ou vide."); return 1
        }
        let textes = h.entrees.reversed().map(\.texte)   // du plus ancien au plus récent
        let statiques = Relecture.plier(Dictionnaire.mots() + ExpressionsStore.partage.liste().expressions.map(\.texte) + LexiqueStore.partage.entrees().map(\.mot))
        var compte: [String: Int] = [:]
        var parRaison: [Relecture.Raison: Int] = [:]
        var exemples: [String] = []
        var debut = ProcessInfo.processInfo.systemUptime
        var tempsMax = 0.0
        for t in textes {
            let connus = statiques.union(compte.filter { $0.value >= 2 }.keys)
            let t0 = ProcessInfo.processInfo.systemUptime
            let d = Relecture.declencher(texte: t, estConnu: Orthographe.estConnu, vocabulaire: VocabulaireRelecture(connus: connus))
            tempsMax = max(tempsMax, ProcessInfo.processInfo.systemUptime - t0)
            if let d {
                parRaison[d.raison, default: 0] += 1
                if exemples.count < 12 { exemples.append("[\(d.raison)] \(d.suspects.joined(separator: ", ")) <- \(t.prefix(70))") }
            }
            for m in Relecture.plier([t]) { compte[m, default: 0] += 1 }
        }
        debut = ProcessInfo.processInfo.systemUptime - debut
        let total = parRaison.values.reduce(0, +)
        print("\(textes.count) dictées rejouées en \(Int(debut * 1000)) ms (la plus lente à décider : \(Int(tempsMax * 1000)) ms).")
        print("Relecture déclenchée : \(total) (\(textes.isEmpty ? 0 : Int((Double(total) / Double(textes.count) * 100).rounded())) %).")
        for (r, n) in parRaison.sorted(by: { $0.value > $1.value }) { print("  \(r.rawValue) : \(n)") }
        if arguments.contains("--exemples") { exemples.forEach { print("  \($0)") } }
        return 0
    }
}
