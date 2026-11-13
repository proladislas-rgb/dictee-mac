import Foundation
import DicteeCore

/// Voxile dans le Dock : app normale fenêtre ouverte, arrière-plan sinon ; la fenêtre au lancement.
func controlesPresenceDock() {
    groupe("Bureau : Voxile dans le Dock (app normale fenêtre ouverte, arrière-plan sinon)")
    verifier(!PresenceDock.dansLeDock(fenetreOuverte: false, reduite: false, surLeBureauActif: true), "fenêtre fermée : pas d'icône, l'encoche seule")
    verifier(PresenceDock.dansLeDock(fenetreOuverte: true, reduite: false, surLeBureauActif: true), "fenêtre ouverte sur ce bureau : l'icône dans le Dock")
    verifier(!PresenceDock.dansLeDock(fenetreOuverte: true, reduite: false, surLeBureauActif: false),
             "fenêtre ouverte mais ailleurs (autre bureau, app en plein écran) : arrière-plan, pour que l'îlot passe par-dessus le plein écran")
    verifier(PresenceDock.dansLeDock(fenetreOuverte: true, reduite: true, surLeBureauActif: false), "fenêtre réduite dans le Dock : l'icône reste")
    verifier(PresenceDock.fenetreAuLancement(premierLancementFait: true, ouvertureDeSession: false, relanceParVoxile: false),
             "lancée d'un clic (Dock, Finder, Spotlight) : la fenêtre s'ouvre")
    verifier(!PresenceDock.fenetreAuLancement(premierLancementFait: false, ouvertureDeSession: false, relanceParVoxile: false), "premier lancement : la prise en main d'abord")
    verifier(!PresenceDock.fenetreAuLancement(premierLancementFait: true, ouvertureDeSession: true, relanceParVoxile: false), "ouverture de session : rien ne s'ouvre")
    verifier(!PresenceDock.fenetreAuLancement(premierLancementFait: true, ouvertureDeSession: false, relanceParVoxile: true), "relance après une mise à jour : rien ne s'ouvre")
}
