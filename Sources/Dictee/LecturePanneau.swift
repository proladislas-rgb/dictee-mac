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
    private var intention: DispatchWorkItem?
    private var retrait: DispatchWorkItem?
    private var reduction: DispatchWorkItem?
    private var moniteurClic: Any?
    private var surveilleEcran: NSObjectProtocol?
    /// Mode d'essai (`--lecture-essai`) : fenêtres transparentes qui ne reçoivent aucun clic, pour tester sans rien montrer à l'écran.
    var invisible = false
    var cadre: NSRect? { fenetre?.frame }

    static let delaiFermeture: TimeInterval = 0.45
    /// Temps que la souris doit rester sur l'îlot avant qu'il s'ouvre.
    static let delaiIntention: TimeInterval = 0.28
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
        intention?.cancel()
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

    /// La souris entre dans l'îlot (ou en sort). Entrée : l'îlot ne s'ouvre qu'après une petite intention (la souris reste 0,28 s dessus ;
    /// un passage rapide n'ouvre rien, et si la souris repart pendant ce délai rien ne bouge). Sortie : il se referme 0,45 s plus tard
    /// (annulé si la souris revient). Si l'îlot est encore à moitié ouvert quand la souris revient, il repart tout de suite vers l'ouvert.
    func survol(_ dedans: Bool) {
        delaiFermeture?.cancel()
        intention?.cancel()
        guard modele.absence < 1 else { return }
        if dedans {
            if estDeplie && modele.progres > 0.99 { return }
            if fenetreOuverte { deplier(); return }   // revient pendant la fermeture : on repart de l'état courant, sans attendre
            let item = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.modele.absence < 1, !self.estDeplie else { return }
                    self.deplier()
                }
            }
            intention = item
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.delaiIntention, execute: item)
        } else {
            guard fenetreOuverte || estDeplie, !modele.epingle, modele.fractionGlissee == nil else { return }
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
        intention?.cancel(); delaiFermeture?.cancel()
        // Clic : déplie tout de suite (sans attendre l'intention) ; nouveau clic : replie. L'îlot se referme aussi quand la souris le quitte.
        if !estDeplie { modele.epingle = false; deplier(); return }
        modele.epingle = false
        replier()
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
            // ressort doux : presque critique (rebond 0,06 à l'ouverture, aucun à la fermeture), repart de l'état et de la vitesse courants
            withAnimation(mouvement(rebond: cible > 0.5 ? 0.06 : 0, duree: cible > 0.5 ? 0.55 : 0.45)) { modele.progres = cible }
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

// MARK: mini-miniature

@MainActor
final class MiniatureEtat: ObservableObject {
    @Published var presence: CGFloat = 0
}

struct MiniatureHote: View {
    @ObservedObject var m: LectureModele
    @ObservedObject var etat: MiniatureEtat
    var body: some View {
        MiniatureLectureVue(m: m, presence: etat.presence).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// La mini-miniature de la lecture pendant une dictée. Elle ne s'affiche pas dans la fenêtre de la dictée (qui laisse passer tous les clics) :
/// c'est un tout petit panneau posé exactement sur le bout droit du ruban de texte, qui ne prend jamais le focus et ne capte que son propre clic.
@MainActor
final class LectureMiniature {
    let modele: LectureModele
    let etat = MiniatureEtat()
    private var fenetre: PanneauSansFocus?
    private var retrait: DispatchWorkItem?
    var invisible = false
    private var reduire: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// Réserve à droite du texte du ruban (miniature + marge) pour que le texte dicté ne passe jamais dessous.
    static let reserve: CGFloat = MiniatureLectureVue.cote + 8
    /// Distance entre le bout droit du ruban et le bord droit de la miniature (le coin du ruban est arrondi à 11 pt).
    static let retraitDroit: CGFloat = 12
    static let tailleFenetre = CGSize(width: MiniatureLectureVue.cote + 8, height: GeometrieEncoche.hauteurRuban)

    init(modele: LectureModele) { self.modele = modele }

    /// Le cadre exact : bout droit du ruban de la dictée (centre + moitié de la bande de base − retrait du ruban), à la hauteur du ruban.
    static func cadre(ecran: NSScreen) -> NSRect {
        let (g, centre) = GeometrieEncoche.mesurer(ecran)
        let finRuban = centre + (g.largeur + 2 * GeometrieEncoche.aile) / 2 - GeometrieEncoche.retraitRuban
        let droite = finRuban - retraitDroit + 4          // 4 pt de zone de clic au-delà de la miniature
        return NSRect(x: droite - tailleFenetre.width, y: ecran.frame.maxY - g.hauteur - GeometrieEncoche.hauteurRuban,
                      width: tailleFenetre.width, height: tailleFenetre.height)
    }

    func afficher() {
        retrait?.cancel()
        guard let ecran = NSScreen.screens.first else { return }
        let cadre = Self.cadre(ecran: ecran)
        if fenetre == nil {
            let f = PanneauSansFocus(contentRect: cadre, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            f.isOpaque = false
            f.backgroundColor = .clear
            f.hasShadow = false
            f.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 4)   // au-dessus de la dictée (+3)
            f.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            f.hidesOnDeactivate = false
            f.isMovable = false
            f.becomesKeyOnlyIfNeeded = true
            f.animationBehavior = .none
            f.appearance = NSAppearance(named: .darkAqua)
            let vue = VueHebergeePremierClic(rootView: MiniatureHote(m: modele, etat: etat))
            vue.frame = NSRect(origin: .zero, size: cadre.size)
            f.contentView = vue
            fenetre = f
        }
        guard let f = fenetre else { return }
        f.setFrame(cadre, display: false)
        f.alphaValue = invisible ? 0 : 1
        f.ignoresMouseEvents = invisible
        f.orderFrontRegardless()
        withAnimation(reduire ? .easeOut(duration: GeometrieEncoche.dureeFondu) : .easeOut(duration: 0.28)) { etat.presence = 1 }
    }

    func retirer() {
        guard let f = fenetre, f.isVisible else { etat.presence = 0; return }
        f.ignoresMouseEvents = true
        withAnimation(.easeOut(duration: reduire ? GeometrieEncoche.dureeFondu : 0.2)) { etat.presence = 0 }
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.etat.presence < 0.01 else { return }
            self.fenetre?.orderOut(nil)
        }
        retrait = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    var estVisible: Bool { fenetre?.isVisible == true && etat.presence > 0.01 }
    var cadre: NSRect? { fenetre?.frame }
    func fermer() { fenetre?.orderOut(nil) }
}
