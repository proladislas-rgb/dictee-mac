import Foundation

/// Options de lancement (surtout pour les vérifications sans écran).
struct Options {
    /// Pas d'icône, pas de fenêtre, aucune demande d'autorisation : on vérifie seulement que tout démarre.
    var sansInterface = false
    /// Quitter tout seul après N secondes (avec --sans-interface).
    var duree: Double?
    /// Fichier son à faire lire à la reconnaissance en direct d'Apple (vérification, résultat dans le journal).
    var verifierParole: String?

    init(_ args: [String]) {
        sansInterface = args.contains("--sans-interface")
        if let a = args.first(where: { $0.hasPrefix("--verifier-parole=") }) { verifierParole = String(a.dropFirst(18)) }
        if let a = args.first(where: { $0.hasPrefix("--duree=") }), let d = Double(a.dropFirst(8)) { duree = d }
    }
}
