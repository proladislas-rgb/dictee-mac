import AppKit
import AVFoundation
import DicteeCore

/// Les retours sensibles de la dictée : un petit son et une vibration du trackpad au début, au texte collé et à l'annulation.
/// Les sons sont fabriqués par `SonSynthese` (aucun fichier, rien de copié) et gardés prêts en mémoire : jouer un son ne
/// fait que lancer la lecture, sans jamais attendre, donc rien ne retarde la dictée ni le collage.
///
/// Réglages séparés : `Settings.sons` et `Settings.vibration` (tous deux activés par défaut).
/// Le Mac n'a pas d'interrupteur « silencieux » : le volume coupé du système coupe aussi ces sons.
/// La vibration ne se sent que si un doigt est posé sur un trackpad Force Touch (c'est une limite du matériel).
@MainActor
enum Retours {
    private static var lecteurs: [SonSynthese.Son: AVAudioPlayer] = [:]
    /// Volume de lecture par son (l'amplitude de base est déjà basse : pic d'environ -20 dBFS).
    private static let volumes: [SonSynthese.Son: Float] = [.debut: 0.55, .fin: 0.5, .annulation: 0.6]

    /// À appeler une fois au lancement : fabrique les sons et les précharge.
    static func preparer() {
        for son in SonSynthese.Son.allCases where lecteurs[son] == nil {
            guard let lecteur = try? AVAudioPlayer(data: SonSynthese.wav(son), fileTypeHint: AVFileType.wav.rawValue) else {
                Log.ecrire("sons : lecteur impossible pour \(son)")
                continue
            }
            lecteur.volume = volumes[son] ?? 0.5
            lecteur.prepareToPlay()
            lecteurs[son] = lecteur
        }
    }

    /// Début de la dictée : deux notes brèves montantes, une pulsation « changement de niveau ».
    static func debut() {
        jouer(.debut)
        vibrer(.levelChange)
    }

    /// Texte collé : une note brève qui descend, deux petits tapes « alignement » à 80 ms d'écart.
    static func fin() {
        jouer(.fin)
        vibrer(.alignment)
        guard Settings.vibration else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { vibrer(.alignment) }
    }

    /// Annulation : un tic grave étouffé, une pulsation sourde « générique ».
    static func annulation() {
        jouer(.annulation)
        vibrer(.generic)
    }

    private static func jouer(_ son: SonSynthese.Son) {
        guard Settings.sons else { return }
        if lecteurs.isEmpty { preparer() }
        guard let lecteur = lecteurs[son] else { return }
        lecteur.currentTime = 0
        lecteur.play()
    }

    private static func vibrer(_ motif: NSHapticFeedbackManager.FeedbackPattern) {
        guard Settings.vibration else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(motif, performanceTime: .now)
    }
}
