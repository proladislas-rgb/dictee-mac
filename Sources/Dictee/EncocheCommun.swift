import AppKit
import SwiftUI

// Pièces communes aux fenêtres d'encoche (proposition de mise à jour, curseur) : elles vivaient dans l'ancienne encoche des
// réunions, remplacée par l'îlot (IlotReunion.swift).

/// Un petit bouton du ruban : texte clair, fond gris au survol ou quand il est « mis en avant » (l'action principale).
struct ActionRuban: View {
    var titre: String
    var touche: String?
    var mis = false
    var action: () -> Void
    @State private var survol = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(titre).font(.system(size: 12))
                if let touche {
                    Text(touche).font(.system(size: 11, weight: .medium)).foregroundStyle(EncocheCouleurs.t3)
                        .padding(.horizontal, 4).overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
                }
            }
            .foregroundStyle(EncocheCouleurs.t1)
            .padding(.horizontal, 8).frame(height: 20)
            .background(RoundedRectangle(cornerRadius: 5).fill(mis || survol ? EncocheCouleurs.k3 : Color.clear))
        }
        .buttonStyle(.plain)
        .onHover { survol = $0 }
        .accessibilityLabel(titre)
    }
}

/// Une vue d'hébergement qui accepte le premier clic et dit quand la souris entre ou sort (le ruban d'actions sort au survol).
final class VueHebergeeSurvol<Contenu: View>: NSHostingView<Contenu> {
    var surSurvol: ((Bool) -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for a in trackingAreas { removeTrackingArea(a) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }
    // Au-dessus de l'encoche, toujours la flèche : sans cela, la fenêtre de dessous (Terminal, éditeur) garde son curseur
    // de texte (le « I » de sélection), car ce panneau ne devient jamais la fenêtre active.
    override func mouseEntered(with event: NSEvent) { fleche(); surSurvol?(true) }
    override func mouseMoved(with event: NSEvent) { fleche() }
    override func cursorUpdate(with event: NSEvent) { fleche() }
    override func mouseExited(with event: NSEvent) { surSurvol?(false) }
    private func fleche() { CurseurEnArrierePlan.autoriser(); NSCursor.arrow.set() }
}

/// macOS ignore `NSCursor.set()` venant d'une app qui n'est pas au premier plan — et Verbe ne l'est jamais. Le réglage de connexion
/// « SetsCursorInBackground » du serveur de fenêtres lève cette limite (c'est ce que font les utilitaires de barre des menus et d'encoche).
/// Chargé à la demande ; s'il manque, rien ne casse : le curseur reste simplement celui de l'app de dessous.
@MainActor
enum CurseurEnArrierePlan {
    private static var fait = false
    static func autoriser() {
        guard !fait else { return }
        fait = true
        typealias FonctionConnexion = @convention(c) () -> Int32
        typealias FonctionPropriete = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32
        guard let pConnexion = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_CGSDefaultConnection"),
              let pPropriete = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGSSetConnectionProperty") else {
            Log.ecrire("curseur : réglage d'arrière-plan indisponible")
            return
        }
        let connexion = unsafeBitCast(pConnexion, to: FonctionConnexion.self)()
        let r = unsafeBitCast(pPropriete, to: FonctionPropriete.self)(connexion, connexion, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
        Log.ecrire("curseur : flèche autorisée en arrière-plan (\(r == 0 ? "ok" : "refus \(r)"))")
    }
}
