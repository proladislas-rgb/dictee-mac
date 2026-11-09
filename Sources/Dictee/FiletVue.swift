import AppKit
import SwiftUI

/// Filet de sécurité de l'écriture (variante B de design/maquettes/filet-securite.html, choisie par Hugues le 09/11) :
/// quand le texte n'a pas pu s'écrire, l'encoche reste ouverte — même silhouette noire que pendant la dictée, l'icône de l'app
/// visée à gauche et un petit point ambre à droite, le centre vide (la caméra) — et le ruban soudé dessous s'agrandit pour
/// montrer le texte complet en Newsreader (2 à 4 lignes, défilable au-delà), avec « Coller ici ↵ » et « Copier ⌘C ».
@MainActor
final class FiletModele: ObservableObject {
    @Published var ouvert = false
    /// « Copier » vient d'être pressé : le bouton le dit un instant.
    @Published var copie = false
    @Published var texte = ""
    /// « Réduire les animations » : pas d'expansion, un fondu bref à la place.
    var reduire = false
    var icone: NSImage?
    var geometrie = GeometrieEncoche()
    var nomApp: String?
    var surColler: () -> Void = {}
    var surCopier: () -> Void = {}
    var surSurvol: (Bool) -> Void = { _ in }

    static let policeTexte: CGFloat = 16
    static let interligne: CGFloat = 5
    static let retraitTexte: CGFloat = 16

    /// Largeur de la bande (celle du ruban, plus ses retraits) : 140 pt de chaque côté de la caméra.
    var largeurPleine: CGFloat { geometrie.largeur + 2 * 140 }
    var largeurBande: CGFloat { ouvert || reduire ? largeurPleine : geometrie.largeur }
    var largeurTexte: CGFloat { largeurPleine - 2 * GeometrieEncoche.retraitRuban - 2 * Self.retraitTexte }
    var opacite: Double { reduire ? (ouvert ? 1 : 0) : 1 }

    /// Hauteur d'une ligne seule, et pas d'une ligne à la suivante (hauteur + interligne : 23 pt environ, comme la maquette).
    static var hauteurLigneSeule: CGFloat {
        let a = NSAttributedString(string: "Ag", attributes: [.font: Polices.nsTexte(policeTexte)])
        return ceil(a.boundingRect(with: NSSize(width: 1000, height: 1000), options: .usesLineFragmentOrigin).height)
    }
    static var pas: CGFloat { hauteurLigneSeule + interligne }

    static func hauteurNaturelle(_ texte: String, largeur: CGFloat) -> CGFloat {
        let p = NSMutableParagraphStyle(); p.lineSpacing = interligne
        let a = NSAttributedString(string: texte, attributes: [.font: Polices.nsTexte(policeTexte), .paragraphStyle: p])
        return ceil(a.boundingRect(with: NSSize(width: largeur, height: 10_000), options: .usesLineFragmentOrigin).height)
    }
    /// Hauteur de la zone de texte : 2 à 4 lignes entières (au-delà, le texte défile).
    static func hauteurTexte(_ texte: String, largeur: CGFloat) -> CGFloat {
        let lignes = min(4, max(2, Int(((hauteurNaturelle(texte, largeur: largeur) + interligne) / pas).rounded())))
        return CGFloat(lignes) * pas - interligne + 2
    }

    /// Hauteur de la zone de texte : celle du texte, entre 2 et 4 lignes (au-delà, on fait défiler).
    var hauteurTexte: CGFloat { Self.hauteurTexte(texte, largeur: largeurTexte) }
    var texteDefile: Bool { Self.hauteurNaturelle(texte, largeur: largeurTexte) > hauteurTexte + 1 }

    /// Ruban plein : 10 de marge, le texte, 10, les boutons (28), 12 de marge basse.
    var hauteurRubanPleine: CGFloat { 12 + hauteurTexte + 10 + 28 + 12 }
    var hauteurRuban: CGFloat { ouvert || reduire ? hauteurRubanPleine : 0 }

    /// Taille de la fenêtre qui porte la vue.
    func tailleFenetre() -> CGSize {
        CGSize(width: ceil(largeurPleine + 2 * 16), height: ceil(geometrie.hauteur + hauteurRubanPleine + 6))
    }
}

struct FiletVue: View {
    @ObservedObject var m: FiletModele
    var tailleFenetre: CGSize

    var body: some View {
        let g = m.geometrie
        ZStack(alignment: .top) {
            FormeEncoche(largeur: m.largeurBande, ruban: m.hauteurRuban, largeurRuban: m.largeurPleine, hauteurBande: g.hauteur, largeurCamera: g.largeur)
                .fill(Color.black)
                .frame(width: tailleFenetre.width, height: tailleFenetre.height, alignment: .top)
            bande(g: g)
            ruban(g: g)
        }
        .frame(width: tailleFenetre.width, height: tailleFenetre.height, alignment: .top)
        .contentShape(FormeEncoche(largeur: m.largeurPleine, ruban: m.hauteurRubanPleine, largeurRuban: m.largeurPleine, hauteurBande: g.hauteur, largeurCamera: g.largeur))
        .onHover { m.surSurvol($0) }
        .opacity(m.opacite)
        .animation(.easeOut(duration: GeometrieEncoche.dureeFondu), value: m.opacite)
    }

    /// L'icône de l'app visée à gauche, un point ambre à droite. Rien au centre : la caméra.
    private func bande(g: GeometrieEncoche) -> some View {
        HStack(spacing: 0) {
            Group {
                if let icone = m.icone {
                    Image(nsImage: icone).resizable().interpolation(.high).frame(width: 24, height: 24)
                } else {
                    Color.clear.frame(width: 24, height: 24)
                }
            }
            .frame(width: GeometrieEncoche.aile - 14, alignment: .leading)
            .padding(.leading, 14)
            Spacer(minLength: 0).frame(width: g.largeur)
            Circle().fill(Palette.accent).frame(width: 6, height: 6)
                .frame(width: GeometrieEncoche.aile - 14, alignment: .trailing)
                .padding(.trailing, 14)
        }
        .frame(width: m.largeurPleine, height: g.hauteur)
        .opacity(m.ouvert ? 1 : 0)
        .animation(.easeOut(duration: m.ouvert ? 0.14 : 0.08), value: m.ouvert)
        .accessibilityHidden(true)
    }

    private func ruban(g: GeometrieEncoche) -> some View {
        VStack(spacing: 0) {
            texte
                .frame(width: m.largeurTexte, height: m.hauteurTexte, alignment: .topLeading)
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                BoutonFilet(titre: "Coller ici", touche: "\u{21B5}", action: m.surColler)
                    .accessibilityHint("Écrit le texte dans l\u{2019}app au premier plan")
                BoutonFilet(titre: m.copie ? "Copié" : "Copier", touche: m.copie ? nil : "\u{2318}C", accent: m.copie, action: m.surCopier)
            }
            .frame(width: m.largeurTexte)
            .padding(.top, 10)
        }
        .padding(.top, g.hauteur + 12)
        .frame(width: m.largeurPleine, height: g.hauteur + m.hauteurRubanPleine, alignment: .top)
        .opacity(m.ouvert ? 1 : 0)
        .animation(.easeOut(duration: m.ouvert ? 0.16 : 0.08), value: m.ouvert)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Texte non écrit\(m.nomApp.map { " dans \($0)" } ?? "")")
    }

    @ViewBuilder private var texte: some View {
        let contenu = Text(m.texte)
            .font(Polices.texte(FiletModele.policeTexte))
            .lineSpacing(FiletModele.interligne)
            .foregroundStyle(Palette.texte)
            .frame(width: m.largeurTexte, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
        if m.texteDefile {
            ScrollView(.vertical, showsIndicators: true) { contenu }
                .scrollIndicators(.automatic)
                // la dernière ligne visible s'efface : « il y en a encore dessous »
                .mask(VStack(spacing: 0) { Color.black; LinearGradient(colors: [.black, .black.opacity(0.15)], startPoint: .top, endPoint: .bottom).frame(height: 14) })
        } else {
            contenu
        }
    }
}

/// « Coller ici ↵ » et « Copier ⌘C » : 28 pt de haut, fond #1d1d1c (un cran au-dessus au survol), la touche dans une pastille.
struct BoutonFilet: View {
    var titre: String
    var touche: String?
    var accent = false
    var action: () -> Void
    @State private var survol = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if accent { Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.accent) }
                Text(titre).font(Polices.commande(13)).foregroundStyle(Palette.texte)
                if let touche {
                    Text(touche)
                        .font(Polices.commande(11, .medium))
                        .foregroundStyle(Palette.texte2)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Palette.filet, lineWidth: 1))
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(survol ? Palette.selection : Color(hex: 0x1D1D1C)))
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { survol = $0 }
    }
}
