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
    /// « Volume et luminosité » : les touches spéciales (volume, muet, luminosité) ; vrai = avalée (l'îlot l'applique et la montre).
    var onNiveau: ((EvenementNiveau, CGEventFlags) -> Bool)?
    /// ⌘C ou ⌘X vient d'être tapé (le presse-papiers va changer, peut-être sans changement d'app) ; reconnu au caractère que donne la
    /// disposition du clavier, pas au code de la touche. Rien n'est avalé, rien n'est lu ici.
    var onCopie: (() -> Void)?
    /// macOS a coupé puis rallumé l'écoute : des relâchements ont pu se perdre, ce qui retenait des touches (volume, luminosité)
    /// repart de zéro.
    var onReinitialisation: (() -> Void)?
    /// Les événements « systemDefined » (NX_SYSDEFINED) : touches de volume, de luminosité, de lecture.
    nonisolated static let typeSysteme = CGEventType(rawValue: 14)!
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
            (1 << CGEventType.keyUp.rawValue) |
            (1 << Self.typeSysteme.rawValue)
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

    /// Renvoie `true` si l'événement doit être avalé. (Interne pour les essais, qui lui passent des touches fabriquées, jamais envoyées.)
    func recevoir(type: CGEventType, event: CGEvent) -> Bool {
        if type == Self.typeSysteme {
            guard let onNiveau, event.getIntegerValueField(.eventSourceUserData) != Self.marqueInterne,
                  let e = Self.evenementNiveau(event) else { return false }
            return onNiveau(e, event.flags)
        }
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            Log.ecrire("écoute du clavier : coupée par macOS (\(type == .tapDisabledByTimeout ? "trop lent" : "entrée utilisateur")), on la rallume")
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            // On a pu rater un relâchement : on repart de zéro plutôt que de rester bloqué en dictée.
            if detector.isActive { onAction?(.cancel) }
            detector.reset()
            fnEnfoncee = false
            reunionAvalee = false; echapAvale = false
            onReinitialisation?()
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
            frappes += 1
            // Les répétitions de touche ne comptent pas comme de nouvelles frappes.
            if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return echapAvale && code == keyCodeEchap }
            if code == keyCodeEchap {
                let avale = appliquer(.escape)
                echapAvale = avale
                return avale
            }
            if let onCopie, event.flags.contains(.maskCommand), !event.flags.contains(.maskControl), !event.flags.contains(.maskAlternate),
               ["c", "x"].contains(Self.caractere(event)) { onCopie() }
            let delai = ProcessInfo.processInfo.systemUptime - dernierRelachementFn
            if delai < 0.5 { Log.ecrire("touche \(code) reçue \(Int(delai * 1000)) ms après le relâchement de fn (casse un éventuel double appui)") }
            appliquer(.otherKey)
            return false

        case .keyUp:
            if event.getIntegerValueField(.keyboardEventKeycode) == codeN, reunionAvalee { reunionAvalee = false; return true }
            if event.getIntegerValueField(.keyboardEventKeycode) == keyCodeEchap, echapAvale {
                echapAvale = false
                return true
            }
            return false

        default:
            return false
        }
    }

    /// Le caractère de la touche selon la disposition du clavier (« c » pour ⌘C, en AZERTY comme en QWERTY), en minuscule.
    static func caractere(_ event: CGEvent) -> String {
        var n = 0
        var u = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &n, unicodeString: &u)
        return String(utf16CodeUnits: u, count: min(n, 4)).lowercased()
    }

    /// Une touche de volume ou de luminosité (nil : un autre événement « systemDefined », boutons de souris, touches de lecture…).
    static func evenementNiveau(_ event: CGEvent) -> EvenementNiveau? {
        guard event.type == typeSysteme, let ns = NSEvent(cgEvent: event), ns.type == .systemDefined else { return nil }
        return EvenementNiveau.decoder(sousType: Int(ns.subtype.rawValue), data1: ns.data1)
    }

    @discardableResult
    private func appliquer(_ evenement: FnEvent) -> Bool {
        let sortie = detector.handle(evenement, at: ProcessInfo.processInfo.systemUptime)
        for action in sortie.actions { onAction?(action) }
        return sortie.swallow
    }
}
