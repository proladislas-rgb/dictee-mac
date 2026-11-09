import Foundation

/// Les modèles de langue de Groq pour la remise au propre et la relecture. Chacun a son quota gratuit (1 000 requêtes et 8 000 jetons par minute,
/// 200 000 jetons par jour pour les gpt-oss : une remise au propre en coûte ~1 000) : quand l'un est à sec, le suivant prend le relais.
/// qwen3.8-27b (sans raisonnement) répond en 150 à 270 ms contre 300 à 510 ms pour gpt-oss-120b : c'est lui qui relit. Logique pure.
public enum ModelesTexte {
    public static let petit = "openai/gpt-oss-20b"
    public static let grand = "openai/gpt-oss-120b"
    public static let rapide = "qwen/qwen3.8-27b"
    static let reserve = [rapide, grand, petit]

    /// Le modèle préféré d'abord, puis les autres ; ceux dont la pause n'est pas finie sont écartés (`pauses` : modèle → instant de fin, `maintenant` même horloge).
    public static func ordre(prefere: String, pauses: [String: Double], maintenant: Double = ProcessInfo.processInfo.systemUptime) -> [String] {
        let suite = reserve.contains(prefere) ? [prefere] + reserve.filter { $0 != prefere } : [prefere]
        return suite.filter { (pauses[$0] ?? 0) <= maintenant }
    }

    /// qwen3.8 réfléchit par défaut : on le coupe (sinon plusieurs secondes). Les gpt-oss ne descendent pas sous « low ».
    public static func effortDeRaisonnement(_ modele: String) -> String? {
        if modele.hasPrefix("openai/gpt-oss") { return "low" }
        if modele.hasPrefix("qwen/qwen3") { return "none" }
        return nil
    }
}
