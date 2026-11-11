import AppKit
import CoreGraphics
import DicteeCore

/// Écoute globale du clavier (CGEventTap actif) : détecte fn tenue / relâchée, les autres touches et Échap.
/// Toute la décision (tenir, appui court, double appui, annuler) est dans `FnGestureDetector`.
///
/// Le tap est « actif » (`.defaultTap`) pour pouvoir :
///  - avaler les changements de la touche fn, afin que l'ouverture des emoji (réglage 🌐) ne se déclenche pas ;
///  - avaler Échap quand il sert à annuler une dictée, pour qu'il n'aille pas aussi dans l'app au premier plan.
/// Le rappel tourne sur le fil principal (source ajoutée à la boucle principale) et doit rester très court.
@MainActor
final class KeyMonitor {
    /// Marque posée sur les événements que l'app fabrique elle-même (⌘V) : le tap les laisse passer sans les lire.
    nonisolated static let marqueInterne: Int64 = 0x44494354 // « DICT »

    /// Laisser à `true` : la touche fn n'est pas transmise aux apps. Si un jour cela gêne, passer à `false`.
    private let avalerFn = true

    private let keyCodeEchap: Int64 = FnGestureDetector.codeEchap

    private var dernierRelachementFn: Double = -10

    /// Nombre de vraies frappes (hors fn / 🌐, hors ⌘V interne) depuis le lancement : les espaces intelligents
    /// s'en servent pour savoir si le curseur a pu bouger depuis la dernière insertion.
    private(set) var frappes = 0

    var onAction: ((GestureAction) -> Void)?
    /// ⌥⌘N : noter la réunion (lancer / arrêter). La touche est avalée : l'app au premier plan ne la reçoit pas.
    var onReunion: (() -> Void)?
    private var reunionAvalee = false
    private let codeN: Int64 = 45
    /// « Micro coupé » : le raccourci (⌃⌥M par défaut ; nil = réglage éteint) coupe ou rouvre le micro. La touche est avalée.
    var raccourciMicro: RaccourciIlot?
    var onMicro: (() -> Void)?
    private var microAvale: Int64?
    /// Les Réglages enregistrent un nouveau raccourci : on laisse passer la touche jusqu'à eux.
    static var enregistrementEnCours = false
    private(set) var detector = FnGestureDetector()

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var fnEnfoncee = false
    private var echapAvale = false
    private var dejaLogueEchec = false

    var actif: Bool { tap != nil }

    /// Crée le tap. Renvoie `false` si macOS refuse (autorisations manquantes) ; on peut réessayer plus tard.
    @discardableResult
    func demarrer() -> Bool {
        if tap != nil { return true }
        let masque: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)
        let rappel: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let moi = Unmanaged<KeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
            let avaler = MainActor.assumeIsolated { moi.recevoir(type: type, event: event) }
            return avaler ? nil : Unmanaged.passUnretained(event)
        }
        guard let nouveau = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: masque,
            callback: rappel,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            if !dejaLogueEchec {
                Log.ecrire("écoute du clavier : refusée par macOS (autorisations accessibilité / surveillance de l'entrée ?)")
                dejaLogueEchec = true
            }
            return false
        }
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, nouveau, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: nouveau, enable: true)
        tap = nouveau
        source = src
        Log.ecrire("écoute du clavier : active (fn avalée = \(avalerFn))")
        return true
    }

    func arreter() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    /// Quand une dictée se termine d'elle-même (erreur), on remet la machine à zéro.
    func reinitialiserGeste() { detector.reset() }

    /// Renvoie `true` si l'événement doit être avalé.
    private func recevoir(type: CGEventType, event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            Log.ecrire("écoute du clavier : coupée par macOS (\(type == .tapDisabledByTimeout ? "trop lent" : "entrée utilisateur")), on la rallume")
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            // On a pu rater un relâchement : on repart de zéro plutôt que de rester bloqué en dictée.
            if detector.isActive { onAction?(.cancel) }
            detector.reset()
            fnEnfoncee = false
            return false

        case .flagsChanged:
            if event.getIntegerValueField(.eventSourceUserData) == Self.marqueInterne { return false }
            let fn = event.flags.contains(.maskSecondaryFn)
            guard fn != fnEnfoncee else { return false } // une autre touche de modification a changé : sans effet
            fnEnfoncee = fn
            if !fn { dernierRelachementFn = ProcessInfo.processInfo.systemUptime }
            appliquer(fn ? .fnDown : .fnUp)
            return avalerFn

        case .keyDown:
            if event.getIntegerValueField(.eventSourceUserData) == Self.marqueInterne { return false }
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            // La touche fn / 🌐 elle-même peut émettre un keyDown : ni une frappe, ni « une autre touche ».
            guard FnGestureDetector.evenement(pourToucheCode: code) != nil else { return false }
            if code == codeN, event.flags.contains(.maskAlternate), event.flags.contains(.maskCommand),
               !event.flags.contains(.maskControl), !event.flags.contains(.maskShift), onReunion != nil {
                if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 { reunionAvalee = true; onReunion?() }
                return true
            }
            if let r = raccourciMicro, onMicro != nil, !Self.enregistrementEnCours, Self.correspond(event, a: r) {
                if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 { onMicro?() }
                microAvale = code
                return true
            }
            frappes += 1
            // Les répétitions de touche ne comptent pas comme de nouvelles frappes.
            if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return echapAvale && code == keyCodeEchap }
            if code == keyCodeEchap {
                let avale = appliquer(.escape)
                echapAvale = avale
                return avale
            }
            let delai = ProcessInfo.processInfo.systemUptime - dernierRelachementFn
            if delai < 0.5 { Log.ecrire("touche \(code) reçue \(Int(delai * 1000)) ms après le relâchement de fn (casse un éventuel double appui)") }
            appliquer(.otherKey)
            return false

        case .keyUp:
            if event.getIntegerValueField(.keyboardEventKeycode) == codeN, reunionAvalee { reunionAvalee = false; return true }
            if let c = microAvale, event.getIntegerValueField(.keyboardEventKeycode) == c { microAvale = nil; return true }
            if event.getIntegerValueField(.keyboardEventKeycode) == keyCodeEchap, echapAvale {
                echapAvale = false
                return true
            }
            return false

        default:
            return false
        }
    }

    /// La touche est-elle ce raccourci ? Les touches de modification d'abord (le cas courant : aucune, on s'arrête là), puis le caractère
    /// que la disposition du clavier donne à la touche (« m » sur un AZERTY comme sur un QWERTY), sans ⌃ ni ⌥.
    static func correspond(_ event: CGEvent, a r: RaccourciIlot) -> Bool {
        let f = event.flags
        let c = f.contains(.maskControl), o = f.contains(.maskAlternate), s = f.contains(.maskShift), k = f.contains(.maskCommand)
        guard c == r.controle, o == r.option, s == r.maj, k == r.commande else { return false }
        guard let t = NSEvent(cgEvent: event)?.charactersIgnoringModifiers, !t.isEmpty else { return false }
        return r.correspond(touche: t, controle: c, option: o, maj: s, commande: k)
    }

    @discardableResult
    private func appliquer(_ evenement: FnEvent) -> Bool {
        let sortie = detector.handle(evenement, at: ProcessInfo.processInfo.systemUptime)
        for action in sortie.actions { onAction?(action) }
        return sortie.swallow
    }
}
