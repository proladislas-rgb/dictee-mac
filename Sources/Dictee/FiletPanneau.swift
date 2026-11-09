import AppKit
import SwiftUI
import Carbon.HIToolbox

/// La fenêtre du filet de sécurité : un panneau sans bord qui peut prendre le clavier sans activer l'app (comme le panneau
/// compact), posé contre le haut de l'écran à la place de l'encoche de dictée. Se ferme par Échap, par un clic ailleurs, ou
/// seul après 10 s sans interaction (jamais tant que la souris est dessus). Le focus revient à l'app visée.
@MainActor
final class FiletPanneau {
    static let delaiAutomatique: TimeInterval = 10
    let modele = FiletModele()
    private var fenetre: PanneauClavier?
    private var moniteurClic: Any?
    private var minuterie: DispatchWorkItem?
    private var retrait: DispatchWorkItem?
    private var souris = false
    private(set) var cible: NSRunningApplication?

    /// Appelé par « Coller ici » : (texte, app au premier plan). Le filet est déjà refermé.
    var surColler: (String, NSRunningApplication?) -> Void = { _, _ in }
    var surChangementEtat: (Bool) -> Void = { _ in }

    var estOuvert: Bool { modele.ouvert && fenetre?.isVisible == true }

    private var reduireLesAnimations: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private func ressort(rebond: Double) -> Animation {
        reduireLesAnimations ? .easeOut(duration: GeometrieEncoche.dureeFondu) : .spring(duration: GeometrieEncoche.dureeMouvement, bounce: rebond)
    }

    // MARK: ouvrir / fermer

    func ouvrir(texte: String, cible: NSRunningApplication?) {
        guard let ecran = NSScreen.screens.first else { return }
        retrait?.cancel()
        self.cible = cible
        let (g, centre) = GeometrieEncoche.mesurer(ecran)
        modele.geometrie = g
        modele.reduire = reduireLesAnimations
        modele.icone = cible?.icon
        modele.nomApp = cible?.localizedName
        modele.texte = texte
        modele.copie = false
        modele.surColler = { [weak self] in self?.coller() }
        modele.surCopier = { [weak self] in self?.copier() }
        modele.surSurvol = { [weak self] in self?.sourisSurLeFilet($0) }

        let taille = modele.tailleFenetre()
        let cadre = NSRect(x: centre - taille.width / 2, y: ecran.frame.maxY - taille.height, width: taille.width, height: taille.height)
        if fenetre == nil {
            let f = PanneauClavier(contentRect: cadre, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            f.isOpaque = false
            f.backgroundColor = .clear
            f.hasShadow = false
            f.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
            f.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            f.hidesOnDeactivate = false
            f.isMovable = false
            f.animationBehavior = .none
            f.appearance = NSAppearance(named: .darkAqua)
            f.surPerteDeFocus = { [weak self] in
                // Un clic dans une autre fenêtre de l'app visée retire le clavier au filet : il se referme.
                guard let self, self.modele.ouvert else { return }
                self.fermer(rendreLeFocus: false)
            }
            f.surTouche = { [weak self] e in self?.touche(e) ?? false }
            fenetre = f
        }
        guard let f = fenetre else { return }
        // Le contenu est refait à chaque ouverture : la taille dépend du texte.
        modele.ouvert = false
        let vue = VueHebergeePremierClic(rootView: FiletVue(m: modele, tailleFenetre: taille))
        vue.frame = NSRect(origin: .zero, size: taille)
        f.contentView = vue
        f.setFrame(cadre, display: false)
        f.orderFrontRegardless()
        f.makeKey()
        withAnimation(ressort(rebond: 0.12)) { modele.ouvert = true }
        installerMoniteur()
        surChangementEtat(true)
        Retours.filet()
        redemarrerMinuterie()
        Log.ecrire("filet de sécurité ouvert (\(texte.count) caractères), cible = \(cible?.bundleIdentifier ?? "aucune")")
    }

    /// Referme le filet (bande et ruban ensemble, 200 ms) puis retire la fenêtre.
    func fermer(animee: Bool = true, rendreLeFocus: Bool = true) {
        guard modele.ouvert || fenetre?.isVisible == true else { return }
        minuterie?.cancel()
        retirerMoniteur()
        surChangementEtat(false)
        let f = fenetre
        if animee {
            withAnimation(ressort(rebond: 0)) { modele.ouvert = false }
            let item = DispatchWorkItem { [weak self] in
                guard let self, !self.modele.ouvert else { return }
                f?.orderOut(nil)
            }
            retrait = item
            DispatchQueue.main.asyncAfter(deadline: .now() + GeometrieEncoche.dureeMouvement + 0.1, execute: item)
        } else {
            modele.ouvert = false
            f?.orderOut(nil)
        }
        // L'app visée n'a jamais été désactivée ; on la réactive seulement si le clavier est parti ailleurs.
        if rendreLeFocus, let cible, !cible.isTerminated, NSWorkspace.shared.frontmostApplication?.processIdentifier != cible.processIdentifier {
            cible.activate()
        }
    }

    // MARK: actions

    private func copier() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(modele.texte, forType: .string)
        Log.ecrire("filet de sécurité : texte copié (\(modele.texte.count) caractères)")
        modele.copie = true
        minuterie?.cancel()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            guard let self, self.modele.copie else { return }
            self.fermer()
        }
    }

    /// « Coller ici » : on retente dans l'app qui est au premier plan (jamais Verbe elle-même).
    private func coller() {
        let texte = modele.texte
        let moi = Bundle.main.bundleIdentifier
        let devant = NSWorkspace.shared.frontmostApplication.flatMap { $0.bundleIdentifier == moi ? nil : $0 } ?? cible
        fermer(animee: false, rendreLeFocus: false)
        surColler(texte, devant)
    }

    /// Retour = coller ici, ⌘C = copier, Échap = fermer.
    private func touche(_ e: NSEvent) -> Bool {
        redemarrerMinuterie()
        switch Int(e.keyCode) {
        case kVK_Return, kVK_ANSI_KeypadEnter:
            coller(); return true
        case kVK_Escape:
            fermer(); return true
        case kVK_ANSI_C where e.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command:
            copier(); return true
        default:
            return false
        }
    }

    // MARK: fermeture seule et clic ailleurs

    /// La souris est sur le filet : le compte à rebours s'arrête ; elle part : il repart de zéro.
    func sourisSurLeFilet(_ dessus: Bool) {
        souris = dessus
        if dessus { minuterie?.cancel() } else { redemarrerMinuterie() }
    }

    private func redemarrerMinuterie() {
        minuterie?.cancel()
        guard !souris, modele.ouvert, !modele.copie else { return }
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.modele.ouvert, !self.souris else { return }
                Log.ecrire("filet de sécurité : fermé seul après \(Int(Self.delaiAutomatique)) s")
                self.fermer()
            }
        }
        minuterie = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.delaiAutomatique, execute: item)
    }

    private func installerMoniteur() {
        retirerMoniteur()
        moniteurClic = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.fermer(rendreLeFocus: false) }
        }
    }
    private func retirerMoniteur() {
        if let moniteurClic { NSEvent.removeMonitor(moniteurClic) }
        moniteurClic = nil
    }
}
