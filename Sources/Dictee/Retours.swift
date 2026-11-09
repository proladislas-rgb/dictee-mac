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

    /// Début de la dictée : (son facultatif) et une vibration longue et franche, 4 frappes.
    static func debut() {
        jouer(.debut)
        rafale(.levelChange, coups: 4)
    }

    /// Texte collé : (son facultatif) et une vibration de 3 frappes.
    static func fin() {
        jouer(.fin)
        rafale(.alignment, coups: 3)
    }

    /// Annulation : (son facultatif) et une vibration courte de 2 frappes.
    static func annulation() {
        jouer(.annulation)
        rafale(.generic, coups: 2)
    }

    /// Une vibration plus longue : plusieurs frappes rapprochées (35 ms) qui se fondent en un bourdonnement court.
    private static func rafale(_ motif: NSHapticFeedbackManager.FeedbackPattern, coups: Int) {
        guard Settings.vibration else { return }
        for i in 0..<coups {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.035 * Double(i)) { vibrer(motif) }
        }
    }

    private static func jouer(_ son: SonSynthese.Son) {
        guard Settings.sons else { return }
        if lecteurs.isEmpty { preparer() }
        guard let lecteur = lecteurs[son] else { return }
        lecteur.currentTime = 0
        lecteur.play()
    }

    /// L'actionneur du trackpad d'abord (il marche même quand Verbe est en arrière-plan, ce que `NSHapticFeedbackManager`
    /// ne fait pas) ; la vibration standard d'AppKit seulement en repli.
    private static func vibrer(_ motif: NSHapticFeedbackManager.FeedbackPattern) {
        guard Settings.vibration else { return }
        let force: ActionneurTrackpad.Force
        switch motif {
        case .levelChange: force = .franche
        case .alignment: force = .moyenne
        default: force = .legere
        }
        if ActionneurTrackpad.taper(force) { return }
        NSHapticFeedbackManager.defaultPerformer.perform(motif, performanceTime: .now)
    }
}
