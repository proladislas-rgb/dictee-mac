import Foundation

/// Que fait la touche 🌐 (fn) du Mac quand on l'appuie seule ? Réglage système « Appuyer sur 🌐 pour » :
/// `AppleFnUsageType` dans le domaine `com.apple.HIToolbox` (0 = Ne rien faire, 1 = Changer de méthode de saisie,
/// 2 = Afficher les emoji, 3 = Lancer la dictée d'Apple). Clé absente = réglage d'origine du Mac, qui fait quelque chose.
///
/// Logique sans interface, vérifiée par `DicteeControles`. Lecture seule : l'app n'écrit jamais ce réglage, parce qu'un
/// `defaults write` n'est pas pris en compte tant qu'on ne passe pas par le volet Clavier des Réglages Système.
public enum ToucheGlobe {
    public static let domaine = "com.apple.HIToolbox"
    public static let cle = "AppleFnUsageType"
    /// Le volet Clavier des Réglages Système (c'est là qu'on règle « Appuyer sur 🌐 pour »).
    public static let adresseVoletClavier = "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"

    /// Lit le réglage dans les préférences du système. `nil` = clé absente.
    public static func lire() -> Int? {
        _ = CFPreferencesAppSynchronize(domaine as CFString)
        return interpreter(CFPreferencesCopyAppValue(cle as CFString, domaine as CFString))
    }

    /// Transforme la valeur brute (nombre, texte) en entier ; `nil` si absente ou illisible.
    public static func interpreter(_ brut: Any?) -> Int? {
        switch brut {
        case let n as NSNumber: return n.intValue
        case let t as String: return Int(t.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }

    /// Vrai tant que la touche 🌐 fait autre chose que « Ne rien faire » : fn ouvrirait aussi cette action.
    public static func doitEtreReglee(valeur: Int?) -> Bool { valeur != 0 }

    /// Ce que fait la touche, en une phrase (titre de l'étape du premier lancement et ligne des Réglages).
    public static func phrase(valeur: Int?) -> String {
        switch valeur {
        case 1: return "Ta touche 🌐 change de méthode de saisie"
        case 3: return "Ta touche 🌐 lance la dictée d\u{2019}Apple"
        default: return "Ta touche 🌐 ouvre les emoji"
        }
    }

    /// La consigne à suivre dans le volet Clavier.
    public static let consigne = "Appuyer sur la touche 🌐 pour : Ne rien faire"
}
