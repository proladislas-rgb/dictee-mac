import Foundation
import IOKit

/// Fait « taper » le moteur haptique du trackpad Force Touch, même quand Verbe n'est pas l'app active.
///
/// Pourquoi : `NSHapticFeedbackManager` n'est honoré par macOS que pour l'app au premier plan. Verbe est une app d'arrière-plan
/// (pas d'icône dans le Dock) : ses demandes de vibration étaient ignorées. On passe donc par l'actionneur du trackpad
/// (cadre système MultitouchSupport, chargé à la demande). Si quoi que ce soit manque, `taper` renvoie `false` et l'appelant
/// se replie sur `NSHapticFeedbackManager` : rien ne peut planter ici.
@MainActor
enum ActionneurTrackpad {
    private typealias FonctionCreer = @convention(c) (UInt64) -> Unmanaged<CFTypeRef>?
    private typealias FonctionOuvrir = @convention(c) (CFTypeRef) -> Int32
    private typealias FonctionTaper = @convention(c) (CFTypeRef, Int32, UInt32, Float, Float) -> Int32

    private static var actionneur: CFTypeRef?
    private static var fonctionTaper: FonctionTaper?
    private static var essaye = false

    /// Intensités (identifiants d'actionnement du trackpad) : de la plus légère à la plus franche.
    enum Force {
        case legere, moyenne, franche
        /// Identifiant d'actionnement du trackpad et intensité de la frappe.
        var reglage: (identifiant: Int32, intensite: Float) {
            switch self {
            case .legere: return (6, 2.5)
            case .moyenne: return (6, 3.0)
            case .franche: return (6, 3.0)
            }
        }
    }

    /// Renvoie `true` si le trackpad a bien tapé.
    @discardableResult
    static func taper(_ force: Force) -> Bool {
        guard let actionneur = ouvrir(), let taper = fonctionTaper else { return false }
        let r = force.reglage
        return taper(actionneur, r.identifiant, 0, 0, r.intensite) == 0
    }

    private static func ouvrir() -> CFTypeRef? {
        if let actionneur { return actionneur }
        guard !essaye else { return nil }
        essaye = true
        guard let cadre = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_LAZY),
              let pCreer = dlsym(cadre, "MTActuatorCreateFromDeviceID"),
              let pOuvrir = dlsym(cadre, "MTActuatorOpen"),
              let pTaper = dlsym(cadre, "MTActuatorActuate") else {
            Log.ecrire("vibration : actionneur du trackpad indisponible (cadre système absent), repli sur la vibration standard")
            return nil
        }
        guard let identifiant = identifiantTrackpad() else {
            Log.ecrire("vibration : aucun trackpad Force Touch trouvé, repli sur la vibration standard")
            return nil
        }
        let creer = unsafeBitCast(pCreer, to: FonctionCreer.self)
        let ouvrirActionneur = unsafeBitCast(pOuvrir, to: FonctionOuvrir.self)
        guard let cree = creer(identifiant)?.takeRetainedValue() else {
            Log.ecrire("vibration : création de l'actionneur refusée, repli sur la vibration standard")
            return nil
        }
        let statut = ouvrirActionneur(cree)
        guard statut == 0 else {
            Log.ecrire("vibration : ouverture de l'actionneur refusée (\(statut)), repli sur la vibration standard")
            return nil
        }
        actionneur = cree
        fonctionTaper = unsafeBitCast(pTaper, to: FonctionTaper.self)
        Log.ecrire("vibration : actionneur du trackpad prêt")
        return cree
    }

    /// L'identifiant « Multitouch ID » du premier trackpad qui sait vibrer (ActuationSupported).
    private static func identifiantTrackpad() -> UInt64? {
        var iterateur: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleMultitouchDevice"), &iterateur) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterateur) }
        var service = IOIteratorNext(iterateur)
        while service != 0 {
            defer { IOObjectRelease(service); service = IOIteratorNext(iterateur) }
            let supporte = IORegistryEntryCreateCFProperty(service, "ActuationSupported" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? Bool ?? false
            guard supporte,
                  let id = IORegistryEntryCreateCFProperty(service, "Multitouch ID" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? NSNumber else { continue }
            return id.uint64Value
        }
        return nil
    }
}
