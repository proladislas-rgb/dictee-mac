import AppKit
import AVFoundation
import DicteeCore

/// Les retours sensibles de la dictée : un petit son et une vibration du trackpad au début, au texte collé et à l'annulation.
/// Les sons sont ceux du Mac (« Pop » au début et au collage), chargés au lancement : jouer un son ne fait que lancer
/// la lecture, sans jamais attendre, donc rien ne retarde la dictée ni le collage.
///
/// Réglages séparés : `Settings.sons` et `Settings.vibration` (tous deux activés par défaut).
/// Le Mac n'a pas d'interrupteur « silencieux » : le volume coupé du système coupe aussi ces sons.
/// La vibration ne se sent que si un doigt est posé sur un trackpad Force Touch (c'est une limite du matériel).
@MainActor
enum Retours {
    /// Sons choisis par Hugues à l'écoute (09/11) parmi les sons intégrés à macOS, lus par leur nom (rien n'est copié dans l'app) :
    /// « Pop » au début de la dictée et quand le texte est collé (« le pop, c'est le mieux ») ; l'annulation reste silencieuse (vibration seule).
    private static let nomsSystem: [SonSynthese.Son: String] = [.debut: "Pop", .fin: "Pop"]
    private static var lecteurs: [SonSynthese.Son: NSSound] = [:]

    /// À appeler une fois au lancement : charge les sons du système pour une lecture immédiate.
    static func preparer() {
        for (son, nom) in nomsSystem where lecteurs[son] == nil {
            guard let s = NSSound(named: NSSound.Name(nom)) else {
                Log.ecrire("sons : son système « \(nom) » introuvable")
                continue
            }
            s.volume = 0.7
            lecteurs[son] = s
        }
    }

    /// Début de la dictée : « Pop » et une vibration calée sur ses deux attaques (0 et 70 ms), toutes deux franches.
    static func debut() {
        jouer(.debut)
        motif([(0, .franche), (0.07, .franche)])
    }

    /// Texte collé : « Pop » et la même vibration calée sur ses deux attaques, un cran plus douce qu'au début.
    static func fin() {
        jouer(.fin)
        motif([(0, .moyenne), (0.07, .moyenne)])
    }

    /// Annulation : pas de son, deux frappes légères.
    static func annulation() {
        jouer(.annulation)
        motif([(0, .legere), (0.06, .legere)])
    }

    /// Filet de sécurité : le texte n'a pas pu être écrit, l'encoche reste ouverte. Une frappe légère, pas de son.
    static func filet() {
        motif([(0, .legere)])
    }

    /// Début d'une réunion : une frappe légère, jamais de son (un son pourrait être capté par le micro, ou gêner un appel en cours).
    static func reunionDebut() { motif([(0, .legere)]) }

    /// Fin de la réunion : deux frappes légères, sans son.
    static func reunionFin() { motif([(0, .legere), (0.06, .legere)]) }

    // MARK: îlot (minuteur, rappels, rendez-vous, notifications)

    private static var sonsIlot: [String: NSSound] = [:]
    /// Le son choisi dans les réglages (nom d'un son du Mac), joué `fois` fois, espacées de `ecart` secondes. « Aucun » : silence.
    static func sonIlot(_ nom: String, fois: Int = 1, ecart: Double = 0.55, volume: Float = 0.7) {
        guard nom != "Aucun" else { return }
        for i in 0..<max(1, fois) {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * ecart) {
                guard let s = sonsIlot[nom] ?? NSSound(named: NSSound.Name(nom)) else { return }
                sonsIlot[nom] = s
                s.volume = volume
                s.stop(); s.play()
            }
        }
    }

    /// Fin d'un minuteur : le son choisi trois fois, et trois frappes du trackpad.
    static func minuteurFini() {
        sonIlot(Settings.sonFinMinuteur, fois: 3, ecart: 0.6)
        motif([(0, .franche), (0.23, .moyenne), (0.46, .moyenne)])
    }
    /// Un rappel arrive à l'heure, ou un rendez-vous commence : deux sons, deux frappes.
    static func rappelSonne() {
        sonIlot(Settings.sonFinMinuteur, fois: 2, ecart: 0.5)
        motif([(0, .moyenne), (0.2, .legere)])
    }
    /// Un bandeau (notification, rendez-vous qui approche) : jamais de son fort.
    static func bandeauDoux() {
        sonIlot(Settings.sonFinMinuteur, fois: 1, volume: 0.35)
        motif([(0, .legere)])
    }
    /// Une alerte qui arrive pendant une réunion : vibration seulement (un son pourrait être capté par le micro).
    static func alerteSilencieuse() { motif([(0, .legere), (0.2, .legere)]) }

    /// Une suite de frappes datées (secondes après maintenant), calée sur le rythme du son qui l'accompagne.
    private static func motif(_ frappes: [(Double, ActionneurTrackpad.Force)]) {
        guard Settings.vibration else { return }
        for (instant, force) in frappes {
            if instant <= 0 { vibrer(force) } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + instant) { vibrer(force) }
            }
        }
    }

    private static func jouer(_ son: SonSynthese.Son) {
        guard Settings.sons else { return }
        if lecteurs.isEmpty { preparer() }
        guard let lecteur = lecteurs[son] else { return }
        lecteur.stop()
        lecteur.play()
    }

    /// L'actionneur du trackpad d'abord (il marche même quand Verbe est en arrière-plan, ce que `NSHapticFeedbackManager`
    /// ne fait pas) ; la vibration standard d'AppKit seulement en repli.
    static func vibrer(_ force: ActionneurTrackpad.Force) {
        guard Settings.vibration else { return }
        if ActionneurTrackpad.taper(force) { return }
        let motifStandard: NSHapticFeedbackManager.FeedbackPattern = force == .franche ? .levelChange : (force == .moyenne ? .alignment : .generic)
        NSHapticFeedbackManager.defaultPerformer.perform(motifStandard, performanceTime: .now)
    }
}
