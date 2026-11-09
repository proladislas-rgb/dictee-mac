import AppKit
import SwiftUI

/// Interrupteur monochrome (surface claire quand activé), 44 × 26.
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
                Circle().fill(actif ? Palette.surface : Color(hex: 0x8A877F)).frame(width: 20, height: 20).padding(3)
            }
            .frame(width: 44, height: 26)
            .animation(.easeOut(duration: 0.18), value: actif)
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($focus)
        .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(Palette.texte3, lineWidth: 1.5).padding(-3).opacity(focus ? 1 : 0))
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

/// Titre de section : un mot net, une phrase dessous, un filet fin.
struct EnteteSection: View {
    var titre: String
    var phrase: String
    var compte: Int?
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(titre).font(Polices.commande(18, .medium)).foregroundStyle(Palette.texte).accessibilityAddTraits(.isHeader)
                if let compte { Text("\(compte)").font(Polices.commande(15)).foregroundStyle(Palette.texte3) }
            }
            Text(phrase).font(Polices.commande(13)).foregroundStyle(Palette.texte2).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.contour).frame(height: 1) }
        .accessibilityElement(children: .combine)
    }
}

/// Une ligne de réglage : libellé et une phrase à gauche, contrôle ou état à droite, filet fin au-dessus (sauf la première).
struct LigneReglage<Valeur: View>: View {
    var libelle: String
    var note: String?
    var premiere = false
    @ViewBuilder var valeur: Valeur
    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 2) {
                Text(libelle).font(Polices.commande(15)).foregroundStyle(Palette.texte)
                if let note {
                    Text(note).font(Polices.commande(13)).foregroundStyle(Palette.texte2).lineSpacing(1).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 12) { valeur }
                .font(Polices.commande(15)).foregroundStyle(Palette.texte2)
                .fixedSize()
        }
        .padding(.vertical, 8)
        .frame(minHeight: 56)
        .overlay(alignment: .top) { if !premiere { Rectangle().fill(Palette.filet).frame(height: 1) } }
        .accessibilityElement(children: .contain)
    }
}

/// Bouton encadré (Modifier, Voir, Effacer…, Copier) : surface un cran au-dessus, contour fin.
struct BoutonCadre: View {
    var titre: String
    var symbole: String?
    var hauteur: CGFloat = 36
    var action: () -> Void
    @State private var survol = false
    @FocusState private var focus: Bool
    init(_ titre: String, symbole: String? = nil, hauteur: CGFloat = 36, action: @escaping () -> Void) {
        self.titre = titre; self.symbole = symbole; self.hauteur = hauteur; self.action = action
    }
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let symbole { Image(systemName: symbole).font(.system(size: 13, weight: .regular)) }
                Text(titre).font(Polices.commande(14)).lineLimit(1)
            }
            .foregroundStyle(Palette.texte)
            .padding(.horizontal, 14)
            .frame(height: hauteur)
            .background(RoundedRectangle(cornerRadius: 8).fill(survol ? Palette.relief : Palette.selection))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.contour, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($focus)
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.texte3, lineWidth: 1.5).padding(-3).opacity(focus ? 1 : 0))
        .onHover { survol = $0 }
        .accessibilityLabel(titre)
    }
}

/// Bouton plein clair : l'action principale (Ajouter, Recoller dans…).
struct BoutonPlein<Pied: View>: View {
    var titre: String
    var symbole: String?
    var hauteur: CGFloat = 36
    var action: () -> Void
    @ViewBuilder var pied: Pied
    @State private var survol = false
    @FocusState private var focus: Bool
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let symbole { Image(systemName: symbole).font(.system(size: 13, weight: .medium)) }
                Text(titre).font(Polices.commande(14, .medium)).lineLimit(1)
                pied
            }
            .foregroundStyle(Palette.surBouton)
            .padding(.horizontal, 14)
            .frame(height: hauteur)
            .background(RoundedRectangle(cornerRadius: 8).fill(Palette.texte.opacity(survol ? 0.9 : 1)))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($focus)
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.texte3, lineWidth: 1.5).padding(-3).opacity(focus ? 1 : 0))
        .onHover { survol = $0 }
        .accessibilityLabel(titre)
    }
}
extension BoutonPlein where Pied == EmptyView {
    init(titre: String, symbole: String? = nil, hauteur: CGFloat = 36, action: @escaping () -> Void) {
        self.init(titre: titre, symbole: symbole, hauteur: hauteur, action: action) { EmptyView() }
    }
}

/// Une touche du clavier (« fn », « espace », « ⌘ C »), en relief discret.
struct Touche: View {
    var texte: String?
    var symbole: String?
    var sombre = false
    var petit = false
    var body: some View {
        Group {
            if let symbole { Image(systemName: symbole).font(.system(size: petit ? 10 : 11, weight: .medium)) }
            else if let texte { Text(texte).font(Polices.commande(petit ? 12 : 13, .medium)) }
        }
        .foregroundStyle(sombre ? Palette.surBouton : Palette.texte)
        .padding(.horizontal, petit ? 6 : 8)
        .frame(minWidth: petit ? 20 : 24, minHeight: petit ? 20 : 24)
        .background(RoundedRectangle(cornerRadius: 6).fill(sombre ? Color.black.opacity(0.12) : Palette.relief))
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
            HStack(spacing: 8) {
                Text(courant).font(Polices.commande(15)).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.texte2)
            }
            .foregroundStyle(Palette.texte)
            .padding(.leading, 14).padding(.trailing, 10)
            .frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 8).fill(Palette.selection))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.contour, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($focus)
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.texte3, lineWidth: 1.5).padding(-3).opacity(focus ? 1 : 0))
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
    var body: some View { Touche(texte: "fn") }
}
