import AppKit
import SwiftUI

/// Les teintes de la fenêtre principale, en clair et en sombre (maquette lucarne-app-final.html, `#fen` et `#fen.nuit`).
/// Toutes suivent l'apparence de la fenêtre : le bouton soleil/lune change tout d'un coup, cartes et verre compris.
enum TonsBureau {
    static let fondHaut = Color(clair: 0xFAF7F2, sombre: 0x252528)
    static let fondBas = Color(clair: 0xF4EEE6, sombre: 0x1C1C1E)
    static let carte = Color(clair: 0xFFFFFF, sombre: 0x2C2C2F)
    static let encre = Color(clair: 0x1D1D1F, sombre: 0xF5F5F7)
    static let encre2 = Color(clair: 0x6C6C71, sombre: 0xAEAEB3)
    static let encre3 = Color(clair: 0x86868B, sombre: 0x8E8E93)
    static let filet = Color(nsColor: .dynamique(clair: NSColor.black.withAlphaComponent(0.075), sombre: NSColor.white.withAlphaComponent(0.08)))
    /// Fond des pastilles, des boutons doux, des pistes.
    static let remplissage = Color(nsColor: .dynamique(clair: NSColor.black.withAlphaComponent(0.05), sombre: NSColor.white.withAlphaComponent(0.08)))
    /// L'onglet choisi dans la barre en verre.
    static let selection = Color(nsColor: .dynamique(clair: NSColor.white.withAlphaComponent(0.95), sombre: NSColor.white.withAlphaComponent(0.17)))
    static let orange = Color(clair: 0xF2841C, sombre: 0xFF9F0A)
    static let vert = Palette.vert
    static let bleu = Color(clair: 0x0A7AFF, sombre: 0x0A84FF)
    static let jaune = Color(clair: 0xC98A00, sombre: 0xFFD60A)
    static let sarcelle = Color(clair: 0x1F9FB5, sombre: 0x40C8E0)
    static let corail = Color(hex: 0xE8835C)
    /// Les petites scènes de « Découvrir » : un ciel doux, bleu vers sable.
    static let scene = [Color(clair: 0xD7E2EF, sombre: 0x2C3440), Color(clair: 0xE9E9EA, sombre: 0x30302F), Color(clair: 0xF3E2D2, sombre: 0x3B3129)]

    /// Marges de la page (maquette : `.pg { padding: 62px 28px 18px }`).
    static let margeH: CGFloat = 28
    static let margeHaut: CGFloat = 62
    static let margeBas: CGFloat = 18
    /// Écart entre deux tuiles.
    static let ecart: CGFloat = 12
}

// MARK: - rendus statiques

private struct CleRenduStatique: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    /// Vrai dans les rendus PNG (`--rendu-fenetre`) : le verre de macOS ne se dessine pas hors écran, on le remplace par sa teinte ;
    /// les petites scènes s'arrêtent sur une image parlante.
    var renduStatique: Bool {
        get { self[CleRenduStatique.self] }
        set { self[CleRenduStatique.self] = newValue }
    }
}

/// Le verre de macOS 26 (Liquid Glass) sur une forme : la barre d'onglets, le bouton soleil/lune, la carte d'accueil. Dans un rendu
/// PNG, la même forme en teinte de verre (blanc laiteux en clair, gris fumé en sombre), avec son fil clair et son ombre.
struct Verre<S: InsettableShape>: ViewModifier {
    var forme: S
    var interactif = false
    @Environment(\.renduStatique) private var statique
    @Environment(\.colorScheme) private var schema

    func body(content: Content) -> some View {
        if statique {
            content
                .background(forme.fill(schema == .dark ? Color(white: 0.24, opacity: 0.86) : Color.white.opacity(0.72)))
                .overlay(forme.strokeBorder(schema == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.12), lineWidth: 0.5))
                .shadow(color: .black.opacity(schema == .dark ? 0.4 : 0.12), radius: 10, y: 5)
        } else {
            content.glassEffect(interactif ? .regular.interactive() : .regular, in: forme)
        }
    }
}

extension View {
    func verre<S: InsettableShape>(_ forme: S, interactif: Bool = false) -> some View { modifier(Verre(forme: forme, interactif: interactif)) }
}

// MARK: - pièces communes

/// Une tuile : fond de carte, coins de 22 pt, fil d'un demi-point, ombre douce en clair seulement.
struct CarteBureau<Contenu: View>: View {
    var rayon: CGFloat = 22
    @ViewBuilder var contenu: Contenu
    @Environment(\.colorScheme) private var schema
    var body: some View {
        contenu
            .background(RoundedRectangle(cornerRadius: rayon, style: .continuous).fill(TonsBureau.carte))
            .overlay(RoundedRectangle(cornerRadius: rayon, style: .continuous)
                .strokeBorder(schema == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 0.5))
            .shadow(color: Color(red: 70/255, green: 45/255, blue: 20/255).opacity(schema == .dark ? 0 : 0.10), radius: 9, y: 5)
    }
}

/// Une tuile qu'on clique en entier (Aujourd'hui) : elle s'enfonce un peu sous le doigt et s'éclaire au survol.
struct TuileBouton<Contenu: View>: View {
    var etiquette: String
    var action: () -> Void
    @ViewBuilder var contenu: Contenu
    @State private var survol = false
    var body: some View {
        Button(action: action) {
            CarteBureau { contenu.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading) }
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.primary.opacity(survol ? 0.025 : 0)).allowsHitTesting(false))
                .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(Enfonce())
        .onHover { survol = $0 }
        .accessibilityLabel(etiquette)
    }
}

/// Un bouton qui s'enfonce légèrement quand on appuie (comme les tuiles d'Apple).
struct Enfonce: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.spring(duration: 0.25, bounce: 0.3), value: configuration.isPressed)
    }
}

/// L'en-tête d'une tuile : symbole et mot en couleur (« Mots dictés »), et à droite ce que fait le clic (« Voir › »).
struct EnteteTuile: View {
    var symbole: String
    var titre: String
    /// Le titre court, quand le long ne tient pas (fenêtre au plus étroit).
    var titreCourt: String? = nil
    var teinte: Color
    var lien: String?
    /// Un chevron seul (les petites tuiles : le titre garde toute la place).
    var chevron = false
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbole).font(.system(size: 12, weight: .semibold))
            ViewThatFits(in: .horizontal) {
                Text(titre).fixedSize()
                Text(titreCourt ?? titre).lineLimit(1)
            }
            .font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 6)
            if let lien {
                HStack(spacing: 3) {
                    Text(lien)
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                }
                .font(.system(size: 12, weight: .medium)).foregroundStyle(TonsBureau.encre3)
                .lineLimit(1).fixedSize()
            } else if chevron {
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(TonsBureau.encre3)
            }
        }
        .foregroundStyle(teinte)
    }
}

/// Le haut d'une page : une petite ligne grise (ou « ‹ Aujourd'hui » dans une sous-page), le grand titre, et ce qui va à droite.
struct EntetePage<Droite: View>: View {
    var petit: String
    var titre: String
    /// Dans une sous-page : le nom de la page parente, cliquable, à la place de la petite ligne.
    var retour: (titre: String, action: () -> Void)? = nil
    @ViewBuilder var droite: Droite

    var body: some View {
        HStack(alignment: .bottom, spacing: 20) {
            VStack(alignment: .leading, spacing: 0) {
                if let retour {
                    Button(action: retour.action) {
                        HStack(spacing: 3) {
                            Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold))
                            Text(retour.titre).font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(TonsBureau.bleu)
                        .frame(height: 16)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Revenir à \(retour.titre)")
                } else {
                    Text(petit).font(.system(size: 13, weight: .semibold)).foregroundStyle(TonsBureau.encre3).frame(height: 16).lineLimit(1)
                }
                Text(titre).font(.system(size: 32, weight: .bold)).tracking(-0.9).foregroundStyle(TonsBureau.encre)
                    .lineLimit(1).frame(height: 38, alignment: .bottom)
                    .accessibilityAddTraits(.isHeader)
            }
            .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 0)
            droite
        }
        .padding(.bottom, 14)
    }
}
extension EntetePage where Droite == EmptyView {
    init(petit: String, titre: String, retour: (titre: String, action: () -> Void)? = nil) {
        self.init(petit: petit, titre: titre, retour: retour) { EmptyView() }
    }
}

/// Une phrase d'aide à droite du titre (gris, alignée à droite, deux lignes au plus).
struct PhraseEntete: View {
    var texte: String
    var body: some View {
        Text(texte).font(.system(size: 13.5)).foregroundStyle(TonsBureau.encre2).multilineTextAlignment(.trailing)
            .lineSpacing(2).frame(maxWidth: 420, alignment: .trailing).fixedSize(horizontal: false, vertical: true)
    }
}

/// Un bouton en capsule : plein (bleu, l'action principale) ou doux (fond léger, texte bleu).
struct BoutonCapsule: View {
    enum Style { case plein, doux }
    var titre: String
    var symbole: String?
    var style: Style = .plein
    var hauteur: CGFloat = 28
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbole { Image(systemName: symbole).font(.system(size: hauteur > 28 ? 11 : 9.5, weight: .bold)) }
                Text(titre).font(.system(size: hauteur > 28 ? 13 : 12.5, weight: .semibold)).lineLimit(1)
            }
            .foregroundStyle(style == .plein ? Color.white : TonsBureau.bleu)
            .padding(.horizontal, hauteur > 28 ? 15 : 12)
            .frame(height: hauteur)
            .background(Capsule().fill(style == .plein ? TonsBureau.bleu : TonsBureau.remplissage))
            .contentShape(Capsule())
            .fixedSize()
        }
        .buttonStyle(Enfonce())
        .accessibilityLabel(titre)
    }
}

/// Une pastille d'information (en haut d'Aujourd'hui) : « 🔔 Appeler le garage · 17:00 ».
struct PastilleBureau: View {
    var symbole: String
    var teinte: Color
    var texte: String
    var valeur: String
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbole).font(.system(size: 11, weight: .semibold)).foregroundStyle(teinte)
            Text(texte).foregroundStyle(TonsBureau.encre2).lineLimit(1)
            Text(valeur).fontWeight(.semibold).monospacedDigit().foregroundStyle(TonsBureau.encre).lineLimit(1)
        }
        .font(.system(size: 12.5, weight: .medium))
        .padding(.leading, 10).padding(.trailing, 13)
        .frame(height: 30)
        .background(Capsule().fill(TonsBureau.remplissage))
        .accessibilityElement(children: .combine)
    }
}
