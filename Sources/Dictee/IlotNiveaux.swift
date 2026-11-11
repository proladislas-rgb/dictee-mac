import AppKit
import AudioToolbox
import CoreAudio
import SwiftUI
import DicteeCore

// « Volume et luminosité » (maquette design/maquettes/ilot-apple.html, « Cinq idées de plus », 4) : les touches du clavier s'affichent
// dans l'îlot, à la place de l'affichage de macOS. L'écoute du clavier (KeyMonitor, celle de fn) reçoit les touches spéciales
// (événements « systemDefined ») ; quand l'îlot peut les montrer, Verbe les avale et règle lui-même :
// - le volume de la sortie par défaut, par CoreAudio (volume « principal virtuel », celui de la barre des menus, et le muet) ;
// - la luminosité de l'écran intégré, par DisplayServices (cadre privé), seulement quand c'est le seul écran allumé (sinon macOS règle
//   l'écran visé, Verbe ne saurait pas lequel).
// Le rappel du clavier ne parle JAMAIS au système (coreaudiod peut être lent pendant une bascule Bluetooth : tout le clavier gèlerait) :
// il décide avec ce qui est gardé en mémoire (sortie réglable ou non, écran seul ou non), mis à jour par les écouteurs du système ; la
// lecture et l'écriture se font ensuite sur une file à part, et l'îlot montre le résultat.
// Rien ne tourne au repos : aucune minuterie, aucun sondage ; deux écouteurs (sortie par défaut, écrans) seulement si le réglage est allumé.

/// Ce que l'îlot demande au son et à l'écran : les vrais (`NiveauxSysteme`) ou des faux pour les essais, qui ne touchent jamais au
/// volume ni à la luminosité de Hugues.
@MainActor
protocol PiloteNiveaux: AnyObject {
    /// Suivre la sortie son et les écrans (écouteurs du système), ou plus.
    func demarrer()
    func arreter()
    /// Verbe sait-il régler cette touche ? Lu dans le rappel du clavier : la réponse vient de ce qui est gardé en mémoire, sans aucun
    /// appel au système. Faux juste après une écriture refusée (la touche suivante va à macOS), jusqu'au prochain changement signalé.
    func peutRegler(_ t: ToucheNiveau) -> Bool
    /// Lit le niveau, calcule le suivant et l'écrit, hors du rappel du clavier. `fini` arrive sur le fil principal avec le niveau
    /// d'avant et celui d'après, ou nil si le système a refusé.
    func appliquer(_ t: ToucheNiveau, fin: Bool, fini: @escaping @MainActor (_ avant: NiveauIlot, _ apres: NiveauIlot) -> Void, refus: @escaping @MainActor () -> Void)
}

/// Le vrai son et le vrai écran du Mac. Ce qui est gardé ici (sur le fil principal) n'est qu'une réponse oui / non par touche.
@MainActor
final class NiveauxSysteme: PiloteNiveaux {
    private let travail = TravailNiveaux()
    private var volumeReglable = false, muetReglable = false, luminositeReglable = false
    /// Après une écriture refusée, la touche va à macOS jusqu'au prochain changement signalé (au plus 5 s).
    private var panneSon: Date?, panneEcran: Date?
    private var surveilleEcrans: NSObjectProtocol?
    private var actif = false

    func demarrer() {
        guard !actif else { return }
        actif = true
        travail.surSon = { [weak self] volume, muet in
            DispatchQueue.main.async { MainActor.assumeIsolated { guard let self, self.actif else { return }; self.volumeReglable = volume; self.muetReglable = muet; self.panneSon = nil } }
        }
        travail.surEcran = { [weak self] ok in
            DispatchQueue.main.async { MainActor.assumeIsolated { guard let self, self.actif else { return }; self.luminositeReglable = ok; self.panneEcran = nil } }
        }
        travail.demarrer()
        surveilleEcrans = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.travail.relireEcrans() }
        }
    }

    func arreter() {
        guard actif else { return }
        actif = false
        travail.arreter()
        if let surveilleEcrans { NotificationCenter.default.removeObserver(surveilleEcrans) }
        surveilleEcrans = nil
        volumeReglable = false; muetReglable = false; luminositeReglable = false
    }

    func peutRegler(_ t: ToucheNiveau) -> Bool {
        let maintenant = Date()
        switch t.genre {
        case .volume: return volumeReglable && (t != .muet || muetReglable) && (panneSon.map { maintenant >= $0 } ?? true)
        case .luminosite: return luminositeReglable && (panneEcran.map { maintenant >= $0 } ?? true)
        }
    }

    func appliquer(_ t: ToucheNiveau, fin: Bool, fini: @escaping @MainActor (NiveauIlot, NiveauIlot) -> Void, refus: @escaping @MainActor () -> Void) {
        travail.appliquer(t, fin: fin) { [weak self] r in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let r else {
                        let jusqua = Date().addingTimeInterval(5)
                        if t.genre == .volume { self?.panneSon = jusqua } else { self?.panneEcran = jusqua }
                        refus(); return
                    }
                    fini(r.avant, r.apres)
                }
            }
        }
    }
}

/// Le travail sur la file : écouteurs de CoreAudio, lectures et écritures. Tout son état ne vit que sur `file`.
private final class TravailNiveaux: @unchecked Sendable {
    private let file = DispatchQueue(label: "verbe.ilot.niveaux", qos: .userInitiated)
    /// Appelés sur `file` : la sortie par défaut a changé (volume réglable, muet réglable) ; les écrans ont changé (luminosité réglable).
    var surSon: (Bool, Bool) -> Void = { _, _ in }
    var surEcran: (Bool) -> Void = { _ in }
    private var blocDefaut: AudioObjectPropertyListenerBlock?
    private var ecran: CGDirectDisplayID?
    /// La dernière valeur écrite, par sortie : relue arrondie par l'appareil, elle est recalée (`PasNiveau.recaler`).
    private var ecrit: [AudioDeviceID: Double] = [:]
    private var ecritLuminosite: Double?

    func demarrer() {
        file.async {
            guard self.blocDefaut == nil else { return }
            var a = Self.adresse(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
            let b: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.relireSon() }
            self.blocDefaut = b
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &a, self.file, b)
            self.relireSon()
            self.relireEcransIci()
        }
    }

    func arreter() {
        file.async {
            guard let b = self.blocDefaut else { return }
            var a = Self.adresse(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &a, self.file, b)
            self.blocDefaut = nil
        }
    }

    func relireEcrans() { file.async { self.relireEcransIci() } }

    private func relireSon() {
        guard let id = Self.sortie() else { surSon(false, false); return }
        surSon(Self.reglable(id, Self.volumePrincipal), Self.reglable(id, Self.muet))
    }

    /// La luminosité se règle seulement quand l'écran intégré est le SEUL écran allumé (un écran externe branché : macOS règle celui
    /// qu'on vise, la touche lui revient). DisplayServices est chargé ici, hors du clavier ; aucune de ses fonctions ne demande
    /// d'autorisation.
    private func relireEcransIci() {
        var n: UInt32 = 0
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        let liste = CGGetActiveDisplayList(16, &ids, &n) == .success ? Array(ids.prefix(Int(n))) : []
        if let f = Self.affichage, liste.count == 1, CGDisplayIsBuiltin(liste[0]) != 0, f.peut?(liste[0]) ?? true { ecran = liste[0] } else { ecran = nil }
        surEcran(ecran != nil)
    }

    func appliquer(_ t: ToucheNiveau, fin: Bool, fini: @escaping ((avant: NiveauIlot, apres: NiveauIlot)?) -> Void) {
        file.async {
            let r = t.genre == .volume ? self.appliquerVolume(t, fin: fin) : self.appliquerLuminosite(t, fin: fin)
            if r == nil { Log.ecrire("volume et luminosité : \(t.genre == .volume ? "le volume" : "la luminosité") n'a pas pu être réglé(e), la touche suivante ira à macOS") }
            fini(r)
        }
    }

    private func appliquerVolume(_ t: ToucheNiveau, fin: Bool) -> (avant: NiveauIlot, apres: NiveauIlot)? {
        guard let id = Self.sortie(), Self.reglable(id, Self.volumePrincipal) else { return nil }
        var a = Self.volumePrincipal, v: Float32 = 0, tv = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &tv, &v) == noErr else { return nil }
        var m = Self.muet, u: UInt32 = 0, tm = UInt32(MemoryLayout<UInt32>.size)
        let coupe = AudioObjectHasProperty(id, &m) && AudioObjectGetPropertyData(id, &m, 0, nil, &tm, &u) == noErr && u != 0
        let avant = NiveauIlot(genre: .volume, valeur: PasNiveau.recaler(lu: Double(v), ecrit: ecrit[id]), muet: coupe)
        let apres = PasNiveau.apres(avant, touche: t, fin: fin)
        var ok = true
        if Self.reglable(id, Self.muet) {
            var mm = Self.muet, x: UInt32 = apres.muet ? 1 : 0
            ok = AudioObjectSetPropertyData(id, &mm, 0, nil, UInt32(MemoryLayout<UInt32>.size), &x) == noErr
        } else if t == .muet { ok = false }
        // le muet seul ne touche pas au volume (il est rendu tel quel au retour du son)
        if ok, !apres.muet {
            var aa = Self.volumePrincipal, x = Float32(apres.valeur)
            ok = AudioObjectSetPropertyData(id, &aa, 0, nil, UInt32(MemoryLayout<Float32>.size), &x) == noErr
            if ok { ecrit[id] = apres.valeur }
        }
        return ok ? (avant, apres) : nil
    }

    private func appliquerLuminosite(_ t: ToucheNiveau, fin: Bool) -> (avant: NiveauIlot, apres: NiveauIlot)? {
        guard let f = Self.affichage, let d = ecran else { return nil }
        var b: Float = 0
        guard f.lire(d, &b) == 0 else { return nil }
        let avant = NiveauIlot(genre: .luminosite, valeur: PasNiveau.recaler(lu: Double(b), ecrit: ecritLuminosite))
        let apres = PasNiveau.apres(avant, touche: t, fin: fin)
        guard f.ecrire(d, Float(apres.valeur)) == 0 else { return nil }
        ecritLuminosite = apres.valeur
        return (avant, apres)
    }

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

    // MARK: écran (DisplayServices, privé)

    private typealias FnLire = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias FnEcrire = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias FnPeut = @convention(c) (CGDirectDisplayID) -> Bool
    /// Chargé une fois, sur la file (jamais dans le rappel du clavier) ; nil si le cadre ou ses fonctions manquent.
    private static let affichage: (lire: FnLire, ecrire: FnEcrire, peut: FnPeut?)? = {
        guard let h = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
              let l = dlsym(h, "DisplayServicesGetBrightness"), let e = dlsym(h, "DisplayServicesSetBrightness") else {
            Log.ecrire("volume et luminosité : DisplayServices introuvable, les touches de luminosité restent à macOS")
            return nil
        }
        return (unsafeBitCast(l, to: FnLire.self), unsafeBitCast(e, to: FnEcrire.self), dlsym(h, "DisplayServicesCanChangeBrightness").map { unsafeBitCast($0, to: FnPeut.self) })
    }()
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
    /// faux : macOS la reçoit et l'affiche comme d'habitude (réglage éteint, dictée en cours, alerte, îlot déplié ou épinglé, sortie HDMI,
    /// écran externe, écriture refusée juste avant, ⌥ seul qui ouvre les réglages Son…). Appelée dans le rappel du clavier : aucune
    /// lecture ni écriture du système ici, seulement des valeurs gardées en mémoire ; le réglage lui-même se fait ensuite, sur une file.
    func toucheNiveau(_ e: EvenementNiveau, option: Bool, maj: Bool, controle: Bool, commande: Bool) -> Bool {
        let fin = PasNiveau.mode(option: option, maj: maj, controle: controle, commande: commande)
        let ilot = moteur.peutMontrerNiveau
        let reglable = e.enfoncee && niveauxActifs && ilot && fin != nil && niveaux.peutRegler(e.touche)
        switch aiguillageNiveau.recevoir(e, fin: fin, conditions: .init(reglage: niveauxActifs, ilot: ilot, reglable: reglable)) {
        case .laisser: return false
        case .avaler: return true
        case .appliquer(let t, let f):
            niveaux.appliquer(t, fin: f, fini: { [weak self] avant, apres in
                self?.moteur.montrerNiveau(apres, avant: avant.affiche)
            }, refus: {})
            return true
        }
    }
}

/// Un son et un écran factices pour les essais : rien n'est jamais réglé sur le vrai Mac (ni volume, ni luminosité, ni son joué).
@MainActor
final class NiveauxFactices: PiloteNiveaux {
    var son = NiveauIlot(genre: .volume, valeur: 0.5)
    var lumiere = NiveauIlot(genre: .luminosite, valeur: 0.3)
    /// Faux : une sortie HDMI (volume non réglable) ; un Mac sans DisplayServices, couvercle fermé ou écran externe branché.
    var volumeReglable = true
    var muetPossible = true
    var luminositeDisponible = true
    /// Vrai : l'écriture est refusée (une sortie qui change pendant l'écriture) ; la touche suivante va à macOS.
    var refuser = false
    /// Vrai : le résultat arrive plus tard sur le fil principal, comme celui de la vraie file.
    var differe = false
    private var panne = false
    private(set) var ecritures: [String] = []
    func demarrer() {}
    func arreter() {}
    /// Le système signale un changement (une autre sortie par défaut) : la panne est oubliée.
    func changement() { panne = false }
    func peutRegler(_ t: ToucheNiveau) -> Bool {
        guard !panne else { return false }
        return t.genre == .volume ? volumeReglable && (t != .muet || muetPossible) : luminositeDisponible
    }
    func appliquer(_ t: ToucheNiveau, fin: Bool, fini: @escaping @MainActor (NiveauIlot, NiveauIlot) -> Void, refus: @escaping @MainActor () -> Void) {
        let faire = { [self] in
            if refuser { panne = true; refus(); return }
            let avant = t.genre == .volume ? son : lumiere
            let apres = PasNiveau.apres(avant, touche: t, fin: fin)
            if t.genre == .volume { son = apres; ecritures.append("volume \(apres.valeur)\(apres.muet ? " muet" : "")") }
            else { lumiere = apres; ecritures.append("luminosité \(apres.valeur)") }
            fini(avant, apres)
        }
        if differe { DispatchQueue.main.async { MainActor.assumeIsolated { faire() } } } else { faire() }
    }
}
