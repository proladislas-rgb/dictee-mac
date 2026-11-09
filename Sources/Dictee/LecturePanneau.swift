import AppKit
import SwiftUI
import DicteeCore

/// La fenêtre de l'îlot de lecture : un panneau sans bord, transparent, au-dessus de la barre des menus, qui ne prend JAMAIS le focus
/// (l'app au premier plan garde le clavier) et reste visible par-dessus les apps en plein écran. Au repos, la fenêtre n'épouse que les
/// ailes de l'encoche (elle ne gêne pas les clics autour) ; au survol ou au clic elle grandit et l'îlot se déplie par ressort.
@MainActor
final class LecturePanneau {
    let modele: LectureModele
    private var fenetre: PanneauSansFocus?
    private var vue: VueHebergeeSurvol<LectureHote>?
    private var conteneur: NSView?
    private var centre: CGFloat = 0
    private var ecran: NSScreen?
    private var grande = CGSize.zero
    private var fenetreOuverte = false
    private var delaiFermeture: DispatchWorkItem?
    private var retrait: DispatchWorkItem?
    private var reduction: DispatchWorkItem?
    private var moniteurClic: Any?
    private var surveilleEcran: NSObjectProtocol?
    /// Mode d'essai (`--lecture-essai`) : fenêtres transparentes qui ne reçoivent aucun clic, pour tester sans rien montrer à l'écran.
    var invisible = false
    var cadre: NSRect? { fenetre?.frame }

    static let delaiFermeture: TimeInterval = 0.25
    /// Appelé quand l'îlot se déplie (le site du navigateur est relu à ce moment-là).
    var surDepliage: () -> Void = {}
    private var reduire: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    init(modele: LectureModele) {
        self.modele = modele
        modele.surClicIlot = { [weak self] in self?.clic() }
    }

    var estVisible: Bool { fenetre?.isVisible == true && modele.absence < 1 }
    var estDeplie: Bool { modele.progres > 0.5 }

    // MARK: ressorts

    private func mouvement(rebond: Double, duree: Double) -> Animation? { reduire ? nil : .spring(duration: duree, bounce: rebond) }

    // MARK: apparition

    /// Montre l'îlot au repos (ou le garde déplié s'il l'est déjà).
    func afficher() {
        retrait?.cancel()
        guard let ecran = NSScreen.screens.first else { return }
        mesurer(ecran)
        if fenetre == nil { creerFenetre() }
        guard let f = fenetre else { return }
        let etaitCache = !f.isVisible || modele.absence >= 1
        poser(ouvert: fenetreOuverte)
        f.alphaValue = invisible ? 0 : 1
        f.ignoresMouseEvents = invisible
        f.orderFrontRegardless()
        guard etaitCache else { return }
        if surveilleEcran == nil {
            surveilleEcran = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.recaler() }
            }
        }
        if reduire {
            modele.opacite = 0
            modele.absence = 0
            withAnimation(.easeOut(duration: GeometrieEncoche.dureeFondu)) { modele.opacite = 1 }
        } else {
            withAnimation(mouvement(rebond: 0.1, duree: 0.42)) { modele.absence = 0 }
        }
    }

    /// Retire l'îlot (une dictée, une réunion ou une annonce prend la place, ou plus rien ne joue) : il se replie, puis la fenêtre disparaît.
    func retirer() {
        guard let f = fenetre, f.isVisible else { modele.absence = 1; return }
        delaiFermeture?.cancel()
        reduction?.cancel()
        retirerMoniteur()
        modele.epingle = false
        f.ignoresMouseEvents = true
        if reduire {
            withAnimation(.easeOut(duration: GeometrieEncoche.dureeFondu)) { modele.opacite = 0 }
            modele.absence = 1
        } else {
            withAnimation(mouvement(rebond: 0, duree: 0.38)) { modele.absence = 1 }
        }
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.modele.absence >= 1 else { return }
            self.fenetre?.orderOut(nil)
            self.modele.progres = 0
            self.fenetreOuverte = false
            self.modele.opacite = 1
        }
        retrait = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    // MARK: survol, clic

    /// La souris entre dans l'îlot (ou en sort) : il se déplie, ou se referme après un petit délai.
    func survol(_ dedans: Bool) {
        delaiFermeture?.cancel()
        guard modele.absence < 1 else { return }
        if dedans {
            if !estDeplie || !fenetreOuverte { deplier() }
        } else {
            guard !modele.epingle, modele.fractionGlissee == nil else { return }
            let item = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, !self.modele.epingle, self.modele.fractionGlissee == nil else { return }
                    self.replier()
                }
            }
            delaiFermeture = item
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.delaiFermeture, execute: item)
        }
    }

    /// La barre vient d'être relâchée : si la souris est sortie de la fenêtre pendant le glissement, l'îlot se referme comme à une sortie normale.
    func apresGlissement() {
        guard let f = fenetre, !f.frame.contains(NSEvent.mouseLocation) else { return }
        survol(false)
    }

    /// Clic sur l'îlot (hors boutons et barre) : le déplie et le garde (ou le relâche).
    private func clic() {
        guard modele.absence < 1 else { return }
        if !estDeplie { modele.epingle = true; deplier(); return }
        modele.epingle.toggle()
        if !modele.epingle { replier() }
    }

    private func deplier() {
        retrait?.cancel(); reduction?.cancel()
        guard modele.absence < 1 else { return }
        poser(ouvert: true)
        fenetreOuverte = true
        changerProgres(1)
        installerMoniteur()
        surDepliage()
    }

    private func replier() {
        guard fenetreOuverte || estDeplie else { return }
        modele.epingle = false
        retirerMoniteur()
        changerProgres(0)
        // la fenêtre reprend sa taille de repos une fois l'îlot refermé (si rien ne l'a rouvert entre-temps)
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.modele.progres < 0.01, self.modele.absence < 1 else { return }
            self.fenetreOuverte = false
            self.poser(ouvert: false)
        }
        reduction = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65, execute: item)
    }

    /// 0 = repos, 1 = déplié. Par ressort interruptible (il repart de l'état courant) ; avec « Réduire les animations », un fondu.
    private func changerProgres(_ cible: CGFloat) {
        if reduire {
            withAnimation(.easeIn(duration: 0.06)) { modele.opacite = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.modele.progres = cible
                    withAnimation(.easeOut(duration: GeometrieEncoche.dureeFondu)) { self.modele.opacite = 1 }
                }
            }
        } else {
            withAnimation(mouvement(rebond: cible > 0.5 ? 0.28 : 0.1, duree: cible > 0.5 ? 0.5 : 0.42)) { modele.progres = cible }
        }
    }

    // MARK: fenêtre

    private func mesurer(_ ecran: NSScreen) {
        let (g, c) = GeometrieEncoche.mesurer(ecran)
        modele.geometrie = g
        modele.reduire = reduire
        centre = c
        self.ecran = ecran
        grande = LectureMesures.tailleVue(g)
    }

    private func creerFenetre() {
        let f = PanneauSansFocus(contentRect: NSRect(origin: .zero, size: LectureMesures.tailleFenetreRepos(modele.geometrie)),
                                 styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        f.isOpaque = false
        f.backgroundColor = .clear
        f.hasShadow = false
        // sous la dictée, le filet et la mise à jour (+3, +3, +1 : jamais en même temps), au-dessus de la barre des menus
        f.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
        f.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        f.hidesOnDeactivate = false
        f.isMovable = false
        f.becomesKeyOnlyIfNeeded = true
        f.animationBehavior = .none
        f.appearance = NSAppearance(named: .darkAqua)
        fenetre = f
        let v = VueHebergeeSurvol(rootView: LectureHote(m: modele, tailleFenetre: grande))
        v.frame = NSRect(origin: .zero, size: grande)
        v.autoresizingMask = []
        v.surSurvol = { [weak self] dedans in self?.survol(dedans) }
        vue = v
        let c = NSView(frame: NSRect(origin: .zero, size: LectureMesures.tailleFenetreRepos(modele.geometrie)))
        c.addSubview(v)
        conteneur = c
        f.contentView = c
    }

    /// Place la fenêtre : taille de repos (ailes de l'encoche) ou taille dépliée, centrée sur la caméra, collée en haut de l'écran.
    private func poser(ouvert: Bool) {
        guard let f = fenetre, let ecran else { return }
        let g = modele.geometrie
        let t = ouvert ? grande : LectureMesures.tailleFenetreRepos(g)
        f.setFrame(NSRect(x: centre - t.width / 2, y: ecran.frame.maxY - t.height, width: t.width, height: t.height), display: false)
        conteneur?.frame.size = t
        vue?.frame = NSRect(x: (t.width - grande.width) / 2, y: t.height - grande.height, width: grande.width, height: grande.height)
    }

    /// Écran ou résolution changés : on mesure à nouveau (l'encoche peut avoir bougé).
    private func recaler() {
        guard let ecran = NSScreen.screens.first, fenetre?.isVisible == true else { return }
        mesurer(ecran)
        vue?.rootView = LectureHote(m: modele, tailleFenetre: grande)
        poser(ouvert: fenetreOuverte)
    }

    // MARK: clic ailleurs

    private func installerMoniteur() {
        guard moniteurClic == nil else { return }
        moniteurClic = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.estDeplie else { return }
                self.replier()
            }
        }
    }

    private func retirerMoniteur() {
        if let moniteurClic { NSEvent.removeMonitor(moniteurClic) }
        moniteurClic = nil
    }

    /// Fermeture de l'app : plus rien ne doit rester à l'écran.
    func fermer() {
        retirerMoniteur()
        if let surveilleEcran { NotificationCenter.default.removeObserver(surveilleEcran) }
        surveilleEcran = nil
        fenetre?.orderOut(nil)
    }
}

// MARK: bulle

/// Position et présence de la bulle, animées par ressort.
@MainActor
final class BulleEtat: ObservableObject {
    @Published var presence: CGFloat = 0
    @Published var decalage: CGFloat = 0
}

struct BulleHote: View {
    @ObservedObject var m: LectureModele
    @ObservedObject var etat: BulleEtat
    var taille: CGSize
    var body: some View { BulleLectureVue(m: m, presence: etat.presence, decalage: etat.decalage, taille: taille) }
}

/// La petite bulle ronde de la lecture pendant une dictée : détachée, à droite de l'encoche de dictée, jamais cliquable (la fenêtre laisse
/// passer tous les clics) ni prenant le focus.
@MainActor
final class LectureBulle {
    let modele: LectureModele
    let etat = BulleEtat()
    private var fenetre: PanneauSansFocus?
    private var retrait: DispatchWorkItem?
    private var centre: CGFloat = 0
    private var mainsLibres = false
    var invisible = false
    private var reduire: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    init(modele: LectureModele) { self.modele = modele }

    private func tailleFenetre(_ g: GeometrieEncoche) -> CGSize {
        let moitie = (g.largeur + 2 * GeometrieEncoche.aile + GeometrieEncoche.rallongeMainsLibres) / 2
        return CGSize(width: ceil(moitie + 14 + 36 + 16), height: g.hauteur + 10)
    }
    private func decalage(_ g: GeometrieEncoche, mainsLibres: Bool) -> CGFloat {
        (g.largeur + 2 * GeometrieEncoche.aile + (mainsLibres ? GeometrieEncoche.rallongeMainsLibres : 0)) / 2 + 14
    }

    func afficher(mainsLibres: Bool) {
        retrait?.cancel()
        guard let ecran = NSScreen.screens.first else { return }
        let (g, c) = GeometrieEncoche.mesurer(ecran)
        centre = c
        self.mainsLibres = mainsLibres
        let t = tailleFenetre(g)
        let cadre = NSRect(x: c, y: ecran.frame.maxY - t.height, width: t.width, height: t.height)
        if fenetre == nil {
            let f = PanneauSansFocus(contentRect: cadre, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            f.isOpaque = false
            f.backgroundColor = .clear
            f.hasShadow = false
            f.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
            f.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            f.hidesOnDeactivate = false
            f.isMovable = false
            f.animationBehavior = .none
            f.appearance = NSAppearance(named: .darkAqua)
            f.ignoresMouseEvents = true
            fenetre = f
        }
        guard let f = fenetre else { return }
        let dejaLa = f.isVisible && etat.presence > 0.5
        f.setFrame(cadre, display: false)
        let vue = NSHostingView(rootView: BulleHote(m: modele, etat: etat, taille: t))
        vue.frame = NSRect(origin: .zero, size: t)
        f.contentView = vue
        f.alphaValue = invisible ? 0 : 1
        f.orderFrontRegardless()
        let cible = decalage(g, mainsLibres: mainsLibres)
        if dejaLa {
            withAnimation(reduire ? nil : .spring(duration: GeometrieEncoche.dureeMouvement, bounce: 0.12)) { etat.decalage = cible }
        } else {
            etat.decalage = cible
            withAnimation(reduire ? .easeOut(duration: GeometrieEncoche.dureeFondu) : .spring(duration: 0.4, bounce: 0.3)) { etat.presence = 1 }
        }
    }

    /// La dictée passe en mains libres (ou en revient) : la bulle suit le bord de l'encoche.
    func suivre(mainsLibres: Bool) {
        guard fenetre?.isVisible == true, self.mainsLibres != mainsLibres, let ecran = NSScreen.screens.first else { return }
        self.mainsLibres = mainsLibres
        let (g, _) = GeometrieEncoche.mesurer(ecran)
        withAnimation(reduire ? nil : .spring(duration: GeometrieEncoche.dureeMouvement, bounce: 0.12)) { etat.decalage = decalage(g, mainsLibres: mainsLibres) }
    }

    func retirer() {
        guard let f = fenetre, f.isVisible else { etat.presence = 0; return }
        withAnimation(reduire ? .easeOut(duration: GeometrieEncoche.dureeFondu) : .spring(duration: 0.3, bounce: 0)) { etat.presence = 0 }
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.etat.presence < 0.01 else { return }
            self.fenetre?.orderOut(nil)
        }
        retrait = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: item)
    }

    func fermer() { fenetre?.orderOut(nil) }
}
