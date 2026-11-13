import AppKit
import SwiftUI
import DicteeCore

/// L'état de la lecture en cours affiché par l'îlot et par la mini-miniature de la dictée. Rien ici n'interroge le système : le contrôleur
/// (`LectureControleur`) pousse ce que dit le programme d'aide, la vue calcule la position toute seule à partir de là.
@MainActor
final class LectureModele: ObservableObject {
    @Published var morceau: MorceauEnCours?
    @Published var image: NSImage?
    /// La même image réduite à la main (40 × 40 pixels, rognée au carré, interpolation haute) pour la mini-miniature de la dictée : nette à 18 pt.
    @Published var imageMini: NSImage?
    @Published var teinte: TeintePochette = .neutre
    /// Site reconnu dans le navigateur (« YouTube »), s'il a pu être établi.
    @Published var site: String?
    @Published var nomApp: String?
    @Published var iconeApp: NSImage?
    /// 0 = au repos dans les ailes de l'encoche, 1 = déplié. Animé par ressort (peut dépasser un peu 1 au rebond).
    @Published var progres: CGFloat = 0
    /// 0 = présent, 1 = retiré (une dictée, une réunion ou une annonce a pris la place, ou plus rien ne joue).
    @Published var absence: CGFloat = 1
    /// Opacité d'ensemble : 1, sauf le bref fondu de « Réduire les animations » entre repos et déplié.
    @Published var opacite: CGFloat = 1
    /// L'îlot est resté déplié par un clic (il se referme au clic ailleurs).
    @Published var epingle = false
    /// Pendant qu'on glisse la barre : la fraction visée (0…1). La position affichée la suit 1:1, la commande part au relâchement.
    @Published var fractionGlissee: Double?
    /// Change à chaque nouveau morceau : la pochette « pop ».
    @Published var pop = 0
    /// Change quand la lecture reprend après une dictée : un anneau s'étend autour de la pochette.
    @Published var impulsion = 0
    /// Vrai dans les rendus PNG (ImageRenderer ne sait pas dessiner les couches Core Animation) : versions fixes de la pochette et de l'onde.
    var statique = false
    var reduire = false
    var geometrie = GeometrieEncoche()

    var surBascule: () -> Void = {}
    var surSuivant: () -> Void = {}
    var surPrecedent: () -> Void = {}
    var surSaut: (Double) -> Void = { _ in }
    var surPosition: (Double) -> Void = { _ in }
    var surClicIlot: () -> Void = {}
    /// Un clic sur la mini-miniature pendant une dictée : reprend la lecture tout de suite.
    var surReprise: () -> Void = {}
    var surFinGlissement: () -> Void = {}

    var genre: GenreLecture {
        SourceLecture.genre(bundle: morceau?.app, album: morceau?.album, duree: morceau?.duree, site: site)
    }
    var joue: Bool { morceau?.joue ?? false }
    /// La deuxième ligne de l'îlot déplié : l'artiste ou la chaîne d'abord, puis le site ou l'app (« Le Coin Tech · YouTube »).
    var sousTitre: String {
        let qui = [morceau?.artiste, morceau?.album].compactMap { $0 }.first { !$0.isEmpty && $0 != morceau?.titre }
        let ou = site ?? SourceLecture.nomCourt(bundle: morceau?.app, nomApp: nomApp)
        return [qui, ou].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
    }

    /// Position affichée à l'instant `date` : celle de la barre pendant qu'on la glisse, sinon celle calculée à partir du dernier état.
    func positionAffichee(a date: Date) -> Double? {
        guard let morceau else { return nil }
        if let f = fractionGlissee, let d = morceau.duree { return TempsLecture.position(fraction: f, duree: d) }
        return morceau.positionA(date)
    }
}
