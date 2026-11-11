import AppKit
import AudioToolbox
import CoreAudio
import SwiftUI
import DicteeCore

// « Volume et luminosité » (maquette design/maquettes/ilot-apple.html, « Cinq idées de plus », 4) : les touches du clavier s'affichent
// dans l'îlot, à la place de l'affichage de macOS. L'écoute du clavier (KeyMonitor, celle de fn) reçoit les touches spéciales
// (événements « systemDefined ») ; quand l'îlot peut les montrer, Verbe les avale et règle lui-même :
// - le volume de la sortie par défaut, par CoreAudio (volume « principal virtuel », celui de la barre des menus, et le muet) ;
// - la luminosité de l'écran intégré, par DisplayServices (cadre privé, chargé à la première touche ; absent : macOS garde la main).
// Rien ne tourne au repos : aucune minuterie, aucune écoute en plus de celle du clavier, aucune lecture tant qu'on ne touche à rien.

/// Ce que l'îlot demande au son et à l'écran : les vrais (`NiveauxSysteme`) ou des faux pour les essais, qui ne touchent jamais au
/// volume ni à la luminosité de Hugues.
@MainActor
protocol PiloteNiveaux: AnyObject {
    /// Le volume de la sortie par défaut ; nil : aucune sortie, ou un volume que macOS ne laisse pas régler (HDMI, sortie optique…).
    func volume() -> NiveauIlot?
    /// Le muet de la sortie se règle-t-il ? (Sinon la touche muet reste à macOS.)
    func muetReglable() -> Bool
    func ecrireVolume(_ n: NiveauIlot) -> Bool
    /// La luminosité de l'écran intégré ; nil : DisplayServices absent, écran fermé, écran externe seul.
    func luminosite() -> NiveauIlot?
    func ecrireLuminosite(_ v: Double) -> Bool
}

/// Le vrai son et le vrai écran du Mac.
@MainActor
final class NiveauxSysteme: PiloteNiveaux {
    // MARK: son (CoreAudio)

    private static func adresse(_ s: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioDevicePropertyScopeOutput,
                                element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: s, mScope: scope, mElement: element)
    }
    private static func sortie() -> AudioDeviceID? {
        var a = adresse(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        var id = AudioDeviceID(0), t = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &t, &id) == noErr, id != 0 else { return nil }
        return id
    }
    private static func reglable(_ id: AudioDeviceID, _ a: AudioObjectPropertyAddress) -> Bool {
        var a = a, s: DarwinBoolean = false
        return AudioObjectHasProperty(id, &a) && AudioObjectIsPropertySettable(id, &a, &s) == noErr && s.boolValue
    }
    /// Le volume « principal virtuel » : celui que règlent la barre des menus et les touches de macOS, y compris sur une sortie
    /// stéréo sans volume principal (il répartit sur les canaux).
    private static let volumePrincipal = adresse(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
    private static let muet = adresse(kAudioDevicePropertyMute)

    /// La dernière valeur écrite, par sortie : relue arrondie par l'appareil, elle est recalée (`PasNiveau.recaler`).
    private var ecrit: [AudioDeviceID: Double] = [:]
    private var ecritLuminosite: Double?

    func volume() -> NiveauIlot? {
        guard let id = Self.sortie(), Self.reglable(id, Self.volumePrincipal) else { return nil }
        var a = Self.volumePrincipal, v: Float32 = 0, t = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &t, &v) == noErr else { return nil }
        var m = Self.muet, u: UInt32 = 0, tm = UInt32(MemoryLayout<UInt32>.size)
        let coupe = AudioObjectHasProperty(id, &m) && AudioObjectGetPropertyData(id, &m, 0, nil, &tm, &u) == noErr && u != 0
        return NiveauIlot(genre: .volume, valeur: PasNiveau.recaler(lu: Double(v), ecrit: ecrit[id]), muet: coupe)
    }

    func muetReglable() -> Bool { Self.sortie().map { Self.reglable($0, Self.muet) } ?? false }

    func ecrireVolume(_ n: NiveauIlot) -> Bool {
        guard let id = Self.sortie() else { return false }
        var ok = true
        if Self.reglable(id, Self.muet) {
            var m = Self.muet, u: UInt32 = n.muet ? 1 : 0
            ok = AudioObjectSetPropertyData(id, &m, 0, nil, UInt32(MemoryLayout<UInt32>.size), &u) == noErr
        }
        // le muet seul ne touche pas au volume (il est rendu tel quel au retour du son)
        if !n.muet {
            var a = Self.volumePrincipal, v = Float32(n.valeur)
            ok = AudioObjectSetPropertyData(id, &a, 0, nil, UInt32(MemoryLayout<Float32>.size), &v) == noErr && ok
            ecrit[id] = n.valeur
        }
        return ok
    }

    // MARK: écran (DisplayServices, privé)

    private typealias FnLire = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias FnEcrire = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias FnPeut = @convention(c) (CGDirectDisplayID) -> Bool
    /// Chargé une fois, à la première touche de luminosité (jamais au lancement) ; nil si le cadre ou ses fonctions manquent.
    private static let affichage: (lire: FnLire, ecrire: FnEcrire, peut: FnPeut?)? = {
        guard let h = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
              let l = dlsym(h, "DisplayServicesGetBrightness"), let e = dlsym(h, "DisplayServicesSetBrightness") else {
            Log.ecrire("volume et luminosité : DisplayServices introuvable, les touches de luminosité restent à macOS")
            return nil
        }
        return (unsafeBitCast(l, to: FnLire.self), unsafeBitCast(e, to: FnEcrire.self), dlsym(h, "DisplayServicesCanChangeBrightness").map { unsafeBitCast($0, to: FnPeut.self) })
    }()
    /// L'écran intégré, s'il est allumé (couvercle fermé, écran externe seul : nil).
    private static func ecranIntegre() -> CGDirectDisplayID? {
        var n: UInt32 = 0
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        guard CGGetActiveDisplayList(16, &ids, &n) == .success else { return nil }
        return ids.prefix(Int(n)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    func luminosite() -> NiveauIlot? {
        guard let f = Self.affichage, let d = Self.ecranIntegre(), f.peut?(d) ?? true else { return nil }
        var b: Float = 0
        guard f.lire(d, &b) == 0 else { return nil }
        return NiveauIlot(genre: .luminosite, valeur: PasNiveau.recaler(lu: Double(b), ecrit: ecritLuminosite))
    }

    func ecrireLuminosite(_ v: Double) -> Bool {
        guard let f = Self.affichage, let d = Self.ecranIntegre() else { return false }
        ecritLuminosite = v
        return f.ecrire(d, Float(v)) == 0
    }
}

/// La barre fine de l'aile droite : un rail à 22 % de blanc et le niveau en blanc, arrondis ensemble (comme sur l'iPhone).
struct BarreNiveau: View {
    var valeur: Double
    var largeur: CGFloat
    static let epaisseur: CGFloat = 5
    var body: some View {
        Capsule().fill(Color.white.opacity(0.22))
            .overlay(alignment: .leading) { Rectangle().fill(Color.white).frame(width: largeur * CGFloat(min(1, max(0, valeur)))) }
            .clipShape(Capsule())
            .frame(width: largeur, height: Self.epaisseur)
    }
}

extension IlotControleur {
    /// Une touche de volume ou de luminosité arrive de l'écoute du clavier. Vrai : elle est avalée (Verbe l'applique, l'îlot la montre) ;
    /// faux : macOS la reçoit et l'affiche comme d'habitude (réglage éteint, dictée en cours, alerte, sortie HDMI, DisplayServices absent,
    /// ⌥ seul qui ouvre les réglages Son…). Appelée dans le rappel du clavier : très court, et rien n'est lu si la touche n'est pas pour nous.
    func toucheNiveau(_ e: EvenementNiveau, option: Bool, maj: Bool, controle: Bool, commande: Bool) -> Bool {
        let fin = PasNiveau.mode(option: option, maj: maj, controle: controle, commande: commande)
        let ilot = moteur.peutMontrerNiveau
        var actuel: NiveauIlot?
        var reglable = false
        if e.enfoncee, niveauxActifs, ilot, fin != nil {
            actuel = e.touche.genre == .volume ? niveaux.volume() : niveaux.luminosite()
            reglable = actuel != nil && (e.touche != .muet || niveaux.muetReglable())
        }
        let decision = aiguillageNiveau.recevoir(e, fin: fin, conditions: .init(reglage: niveauxActifs, ilot: ilot, reglable: reglable))
        switch decision {
        case .laisser: return false
        case .avaler: return true
        case .appliquer(let t, let f):
            guard let a = actuel else { return true }
            let n = PasNiveau.apres(a, touche: t, fin: f)
            let ok = n.genre == .volume ? niveaux.ecrireVolume(n) : niveaux.ecrireLuminosite(n.valeur)
            if ok { moteur.montrerNiveau(n, avant: a.affiche) }
            else { Log.ecrire("volume et luminosité : \(n.genre == .volume ? "le volume" : "la luminosité") n'a pas pu être réglé(e)") }
            return true
        }
    }
}

/// Un son et un écran factices pour les essais : rien n'est jamais réglé sur le vrai Mac (ni volume, ni luminosité, ni son joué).
@MainActor
final class NiveauxFactices: PiloteNiveaux {
    var son = NiveauIlot(genre: .volume, valeur: 0.5)
    var lumiere = NiveauIlot(genre: .luminosite, valeur: 0.3)
    /// Faux : une sortie HDMI (volume non réglable) ; un Mac sans DisplayServices ou couvercle fermé.
    var volumeReglable = true
    var muetPossible = true
    var luminositeDisponible = true
    private(set) var ecritures: [String] = []
    func volume() -> NiveauIlot? { volumeReglable ? son : nil }
    func muetReglable() -> Bool { muetPossible }
    func ecrireVolume(_ n: NiveauIlot) -> Bool { son = n; ecritures.append("volume \(n.valeur)\(n.muet ? " muet" : "")"); return true }
    func luminosite() -> NiveauIlot? { luminositeDisponible ? lumiere : nil }
    func ecrireLuminosite(_ v: Double) -> Bool { lumiere = NiveauIlot(genre: .luminosite, valeur: v); ecritures.append("luminosité \(v)"); return true }
}
