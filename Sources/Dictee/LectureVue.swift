import AppKit
import SwiftUI
import DicteeCore

// Les pièces de la lecture en cours qui servent à l'îlot (IlotVues.swift) et à la mini-miniature de la dictée.

/// Un bouton rond de l'îlot : fond blanc 9 %, 18 % au survol, réduit à 90 % pendant l'appui ; le bouton lecture/pause est plein.
struct BoutonLecture: View {
    var symbole: String
    var diametre: CGFloat
    var taillePictogramme: CGFloat
    var plein = false
    var etiquette: String
    var action: () -> Void
    @State private var survol = false

    private struct Style: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.9 : 1)
                .animation(.spring(duration: 0.18, bounce: 0.2), value: configuration.isPressed)
        }
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(plein ? Color(white: survol ? 0.91 : 1) : Color.white.opacity(survol ? 0.18 : 0.09))
                Image(systemName: symbole)
                    .font(.system(size: taillePictogramme, weight: .semibold))
                    .foregroundStyle(plein ? Color.black : Color.white)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: diametre, height: diametre)
            .contentShape(Circle())
        }
        .buttonStyle(Style())
        .onHover { survol = $0 }
        .accessibilityLabel(etiquette)
    }
}

/// La pochette. Chaîne de repli : l'image du système, sinon la miniature de la vidéo (déposée dans `m.image` par le contrôleur), sinon l'icône
/// de l'app qui joue, en petit sur fond sombre, sinon un pictogramme sobre.
struct PochetteLecture: View {
    @ObservedObject var m: LectureModele
    /// La mini-miniature de la dictée : l'image réduite à la main, jamais en rotation.
    var miniature = false
    // Le fond donne la taille (exactement celle proposée par l'appelant) et l'image vit dans un calque par-dessus, rogné : une miniature
    // de vidéo en 16:9 remplit la case sans l'élargir. Dans un ZStack, l'image en `.fill` dictait la taille (192 × 108 pour une case
    // de 108) et débordait sur le titre, l'onde et le temps, le découpage de l'appelant suivant ce cadre élargi.
    var body: some View {
        Color(white: 0.11)
            .overlay { contenu }
            .clipped()
    }

    @ViewBuilder private var contenu: some View {
            if let image = m.image {
                if miniature {
                    Image(nsImage: m.imageMini ?? image).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                } else {
                    Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                }
            } else if let icone = m.iconeApp {
                GeometryReader { geo in
                    Image(nsImage: icone).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                        .frame(width: geo.size.width * (miniature ? 0.86 : 0.58), height: geo.size.height * (miniature ? 0.86 : 0.58))
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
            } else {
                // ni image ni icône d'app : un pictogramme à l'échelle de la case (40 % de sa hauteur), jamais un point perdu au milieu
                GeometryReader { geo in
                    Image(systemName: m.genre == .musique ? "music.note" : "play.rectangle.fill")
                        .font(.system(size: max(9, min(geo.size.width, geo.size.height) * 0.4), weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.42))
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
            }
    }
}

// MARK: mini-miniature pendant la dictée

/// La lecture pendant une dictée : une mini-miniature de 18 pt DANS le ruban de la dictée (au bout, côté droit). La vraie image de ce qui
/// joue (pochette, miniature de la vidéo, à défaut icône de l'app), légèrement assombrie, avec un fin glyphe pause blanc ; ronde pour la
/// musique. Un clic dessus reprend la lecture. Apparaît et disparaît en fondu doux avec la pause et la reprise.
struct MiniatureLectureVue: View {
    @ObservedObject var m: LectureModele
    /// 0 = absente, 1 = présente.
    var presence: CGFloat
    static let cote: CGFloat = 18
    @State private var survol = false

    private var forme: AnyShape { m.genre == .musique ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 4.5, style: .continuous)) }

    var body: some View {
        Button { m.surReprise() } label: {
            ZStack {
                PochetteLecture(m: m, miniature: true)
                    .frame(width: Self.cote, height: Self.cote)
                    .overlay(Color.black.opacity(m.image == nil ? (survol ? 0.22 : 0.36) : (survol ? 0.30 : 0.46)))
                Image(systemName: "pause.fill").font(.system(size: 7.5, weight: .bold)).foregroundStyle(.white.opacity(0.95))
            }
            .frame(width: Self.cote, height: Self.cote)
            .clipShape(forme)
            .overlay(forme.stroke(Color.white.opacity(0.14), lineWidth: 0.5))
            .contentShape(Rectangle().inset(by: -4))
        }
        .buttonStyle(.plain)
        .onHover { survol = $0 }
        .scaleEffect(0.82 + 0.18 * presence)
        .opacity(Double(min(1, max(0, presence))))
        .animation(.easeOut(duration: 0.12), value: survol)
        .accessibilityLabel("Reprendre la lecture")
    }
}
