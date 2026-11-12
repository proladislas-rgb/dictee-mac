import Foundation

/// Le nom de l'app (Voxile depuis le 13/11 ; Verbe avant, Dictée au tout début). L'identifiant reste com.hugues.dictee : autorisations,
/// réglages, historique et dictionnaire sont gardés d'un nom à l'autre.
public enum NomApp {
    public static let nom = "Voxile"
    public static let paquet = "Voxile.app"
    /// Les anciens noms du paquet, du plus récent au plus ancien.
    public static let anciensPaquets = ["Verbe.app", "Dictee.app"]
    public static let identifiant = "com.hugues.dictee"
    /// Le fichier de la release que l'app télécharge pour se mettre à jour.
    public static func dmg(_ version: VersionApp) -> String { "\(nom)-\(version).dmg" }
}

/// Au lancement de l'app installée : ce qu'il faut faire du nom de son paquet.
/// - lancée depuis une `Verbe.app` (posée par la mise à jour automatique d'une Verbe 0.3.x, qui ne connaît que ce nom) : se renommer en
///   `Voxile.app` au même endroit, puis se relancer de là ;
/// - lancée depuis une `Voxile.app` : ranger à la corbeille les anciennes `Verbe.app` du même identifiant (installée à la main à côté
///   d'une Verbe : jamais deux apps) ;
/// - autre chose (le binaire de `.build`, un nom choisi à la main) : rien.
public enum PassageNom: Equatable, Sendable {
    case renommer(en: String)
    case rangerLesAnciennes([String])
    case rien

    public static func decision(nomPaquet: String) -> PassageNom {
        if nomPaquet == "Verbe.app" { return .renommer(en: NomApp.paquet) }
        if nomPaquet == NomApp.paquet { return .rangerLesAnciennes(["Verbe.app"]) }
        return .rien
    }
}
