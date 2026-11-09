import Foundation
import DicteeCore

/// Réglages simples (le panneau de réglages arrive au lot 7). Modifiables avec `defaults write com.hugues.dictee ...`.
enum Settings {
    private static let defaults = UserDefaults.standard

    /// Langue forcée pour Whisper (`fr`, `en`…). `nil` = détection automatique.
    /// Exemple : defaults write com.hugues.dictee langue fr
    static var langue: String? {
        guard let l = defaults.string(forKey: "langue"), !l.isEmpty, l != "auto" else { return nil }
        return l
    }

    /// Délai maximal d'attente de Groq après le relâchement, avant de passer au texte de secours d'Apple.
    static let delaiGroq: Double = 4.0

    /// « Remettre au propre » (hésitations, corrections dites, ponctuation, mise en forme). Activé par défaut.
    /// Exemple : defaults write com.hugues.dictee remettreAuPropre -bool false
    static var remettreAuPropre: Bool {
        get { defaults.object(forKey: "remettreAuPropre") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "remettreAuPropre") }
    }

    /// Modèle de langue de Groq pour la remise au propre (nom vérifié avec GET /openai/v1/models le 09/11).
    static var modeleNettoyage: String {
        defaults.string(forKey: "modeleNettoyage").flatMap { $0.isEmpty ? nil : $0 } ?? "openai/gpt-oss-20b"
    }

    /// Délai maximal de la remise au propre ; au-delà, le texte brut de Groq est collé.
    static let delaiNettoyage: Double = 1.2

    /// Nombre maximal de dictées gardées dans l'historique.
    static var limiteHistorique: Int {
        let v = defaults.integer(forKey: "limiteHistorique")
        return v > 0 ? v : Historique.limiteParDefaut
    }

    /// Adapter le ton à l'app qui reçoit le texte (courriel soigné, message direct, terminal brut…). Activé par défaut.
    static var adapterLeTon: Bool {
        get { defaults.object(forKey: "adapterLeTon") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "adapterLeTon") }
    }

    /// Secours : le texte de la dictée d'Apple quand Groq ne répond pas. Activé par défaut.
    static var secoursApple: Bool {
        get { defaults.object(forKey: "secoursApple") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "secoursApple") }
    }

    /// Langue choisie dans les Réglages (`fr`, `en`) ou `nil` pour la détection automatique.
    static func choisirLangue(_ code: String?) { defaults.set(code ?? "auto", forKey: "langue") }

    /// Micro choisi (identifiant CoreAudio). `nil` = micro par défaut du système.
    static var micro: String? {
        get { defaults.string(forKey: "microUID").flatMap { $0.isEmpty ? nil : $0 } }
        set { defaults.set(newValue ?? "", forKey: "microUID") }
    }

    /// Le premier lancement (3 étapes) a été fait : il ne s'affiche plus tout seul.
    static var premierLancementFait: Bool {
        get { defaults.bool(forKey: "premierLancementFait") }
        set { defaults.set(newValue, forKey: "premierLancementFait") }
    }
}
