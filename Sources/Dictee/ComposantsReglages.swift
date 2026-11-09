import AppKit
import SwiftUI

/// Interrupteur monochrome (surface claire quand activé), 36 × 20 dans la fenêtre.
struct Interrupteur: View {
    @Binding var actif: Bool
    var etiquette: String
    var action: ((Bool) -> Void)?
    @FocusState private var focus: Bool

    var body: some View {
        Button {
            let nouveau = !actif
            if let action { action(nouveau) } else { actif = nouveau }
        } label: {
            ZStack(alignment: actif ? .trailing : .leading) {
                Capsule().fill(actif ? Palette.texte : Palette.interrupteurEteint)
                Circle().fill(actif ? Palette.surface : Palette.texte2).frame(width: 16, height: 16).padding(2)
            }
            .frame(width: 36, height: 20)
            .animation(.easeOut(duration: 0.18), value: actif)
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($focus)
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Palette.texte3, lineWidth: 1.5).padding(-3).opacity(focus ? 1 : 0))
        .accessibilityLabel(etiquette)
        .accessibilityValue(actif ? "activé" : "désactivé")
        .accessibilityAddTraits(.isToggle)
    }
}

/// Un lien en texte seul (souligné fin au survol), pour Ajouter, Effacer, Revoir…
struct LienTexte: View {
    var titre: String
    var fort = false
    var action: () -> Void
    @State private var survol = false
    @FocusState private var focus: Bool
    var body: some View {
        Button(action: action) {
            Text(titre)
                .font(Polices.commande(13))
                .foregroundStyle(fort || survol ? Palette.texte : Palette.texte2)
                .underline(survol || fort, color: Palette.texte3)
                .lineLimit(1)
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($focus)
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.texte3, lineWidth: 1.5).padding(-3).opacity(focus ? 1 : 0))
        .onHover { survol = $0 }
    }
}

/// Une ligne de réglage : libellé à gauche, valeur à droite.
struct LigneReglage<Valeur: View>: View {
    var libelle: String
    var note: String?
    var hauteur: CGFloat = 40
    @ViewBuilder var valeur: Valeur
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text(libelle).font(Polices.commande(15)).foregroundStyle(Palette.texte)
                Spacer(minLength: 12)
                valeur.font(Polices.commande(15)).foregroundStyle(Palette.texte2)
            }
            .frame(minHeight: hauteur)
            if let note {
                Text(note).font(Polices.commande(12)).foregroundStyle(Palette.texte3).padding(.bottom, 6).offset(y: -6)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// Une action de menu qui garde sa fermeture (les NSMenuItem n'en acceptent pas directement).
final class ActionMenu: NSObject {
    let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func lancer() { action() }
}

/// Valeur à choisir dans un menu : « Micro du MacBook ⌄ ». Le menu est un vrai menu du système, ouvert à l'endroit du clic.
struct ChoixReglage<V: Hashable>: View {
    var libelle: String
    @Binding var valeur: V
    var options: [(V, String)]
    @FocusState private var focus: Bool

    var body: some View {
        let courant = options.first { $0.0 == valeur }?.1 ?? ""
        Button(action: ouvrir) {
            HStack(spacing: 6) {
                Text(courant).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(Palette.texte2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($focus)
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.texte3, lineWidth: 1.5).padding(-3).opacity(focus ? 1 : 0))
        .accessibilityLabel(libelle)
        .accessibilityValue(courant)
    }

    private func ouvrir() {
        let menu = NSMenu()
        for (v, titre) in options {
            let action = ActionMenu { valeur = v }
            let item = NSMenuItem(title: titre, action: #selector(ActionMenu.lancer), keyEquivalent: "")
            item.target = action
            item.representedObject = action
            item.state = v == valeur ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: menu.items.first { $0.state == .on }, at: NSEvent.mouseLocation, in: nil)
    }
}

/// Touche en relief discret : « fn ».
struct ToucheFn: View {
    var body: some View {
        Text("fn")
            .font(Polices.commande(12, .medium))
            .foregroundStyle(Palette.texte)
            .padding(.horizontal, 7).padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 4).fill(Palette.selection))
    }
}
