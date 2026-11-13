import Foundation

/// Voxile dans le Dock. Fenêtre ouverte : une vraie app (icône avec son point, menu de l'app, ⌘Q, « Quitter » au clic droit). Fenêtre
/// fermée : une app d'arrière-plan, seule l'encoche reste. Exception : la fenêtre ouverte mais sur un autre bureau (ou derrière une
/// app en plein écran), Voxile repasse en arrière-plan le temps d'y être, parce qu'une app « normale » ne peut pas poser l'îlot
/// par-dessus une app en plein écran (constaté le 09/11 dans le Terminal en plein écran) ; une fenêtre réduite dans le Dock garde l'icône.
public enum PresenceDock {
    public static func dansLeDock(fenetreOuverte: Bool, reduite: Bool, surLeBureauActif: Bool) -> Bool {
        guard fenetreOuverte else { return false }
        return reduite || surLeBureauActif
    }

    /// Au lancement, la fenêtre s'ouvre comme pour un clic sur l'icône du Dock (lancée depuis le Dock, le Finder, Spotlight), sauf :
    /// la prise en main du premier lancement (c'est elle qui parle), l'ouverture de session (« Ouvrir au démarrage »), et une relance
    /// faite par Voxile elle-même (mise à jour, changement de nom, copie dans Applications).
    public static func fenetreAuLancement(premierLancementFait: Bool, ouvertureDeSession: Bool, relanceParVoxile: Bool) -> Bool {
        premierLancementFait && !ouvertureDeSession && !relanceParVoxile
    }

    /// La variable posée par Voxile quand elle se relance (`open --env`).
    public static let variableRelance = "VOXILE_RELANCE"
}
