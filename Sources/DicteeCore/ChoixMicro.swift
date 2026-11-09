import Foundation

/// Comment le micro est relié à l'ordinateur.
public enum TransportMicro: Sendable { case integre, bluetooth, usb, autre }

public struct PeripheriqueEntree: Equatable, Sendable {
    public var uid: String
    public var nom: String
    public var transport: TransportMicro
    public init(uid: String, nom: String, transport: TransportMicro) { self.uid = uid; self.nom = nom; self.transport = transport }
}

public enum DecisionMicro: Equatable, Sendable {
    /// On laisse le micro par défaut du système.
    case systeme(raison: String)
    /// On impose ce périphérique à l'entrée du moteur audio.
    case impose(PeripheriqueEntree, raison: String)

    public var raison: String {
        switch self { case .systeme(let r): return r; case .impose(_, let r): return r }
    }
}

/// Quel micro utiliser. Réglage « Automatique » : le micro intégré du Mac dès qu'un casque Bluetooth est le micro par défaut
/// (un micro Bluetooth fait basculer les AirPods en mode téléphone : son dégradé et démarrage lent) ; sinon le micro par défaut.
/// Un micro choisi dans les Réglages est toujours respecté, AirPods compris. Logique pure, testée par `DicteeControles`.
public enum ChoixMicro {
    /// Valeur du réglage pour « Automatique » (aucun réglage enregistré).
    public static let automatique = ""
    /// Valeur du réglage pour « Micro du système » (celui de Réglages Système › Son).
    public static let systeme = "systeme"

    public static func decider(reglage: String?, peripheriques: [PeripheriqueEntree], defautUID: String?) -> DecisionMicro {
        let defaut = peripheriques.first { $0.uid == defautUID }
        var prefixe = ""
        if let r = reglage, !r.isEmpty, r != systeme {
            if let choisi = peripheriques.first(where: { $0.uid == r }) { return .impose(choisi, raison: "micro choisi dans les Réglages") }
            prefixe = "micro choisi absent, "
        }
        if reglage == systeme { return .systeme(raison: "Micro du système choisi dans les Réglages") }
        if let defaut, defaut.transport == .bluetooth, let integre = peripheriques.first(where: { $0.transport == .integre }) {
            return .impose(integre, raison: prefixe + "casque Bluetooth connecté (\(defaut.nom)) : micro intégré préféré")
        }
        return .systeme(raison: prefixe + "micro par défaut du système" + (defaut.map { " (\($0.nom))" } ?? ""))
    }
}
