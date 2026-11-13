import AppKit
import SwiftUI
import DicteeCore

// La dictée (fn) quand la Lucarne n'est pas dans l'encoche (Hugues, 12/11 soir : la décision C du plan est abandonnée) : elle se montre
// À LA PLACE de la Lucarne, en verre, et l'encoche reste vide. La fenêtre de la dictée (`EnclochePanneau`) reste la même ; seuls son cadre
// et son dessin changent : une pilule de verre [✕] icône · texte en direct · onde [✓] qui grandit vers l'intérieur depuis la place
// (`GeoLucarne.dictee`). La Lucarne, elle, s'efface le temps de la dictée (comme dans l'encoche) : la pilule de la dictée prend sa place.

/// Où se montre la dictée quand la Lucarne n'est pas dans l'encoche : sa place et son écran (repère de la Lucarne), et de quoi passer en
/// coordonnées globales d'AppKit (le centre de l'encoche en x, le haut de l'écran en y).
struct PlacementDictee: Equatable {
    var ecran: EcranLucarne
    var place: PlaceLucarne
    var centre: CGFloat
    var haut: CGFloat

    /// La boîte où la pilule peut grandir (la plus large : ruban et mains libres), avec la place de son ombre, en coordonnées globales.
    var cadreFenetre: NSRect {
        let k = GeoLucarne.dictee(place, ecran, ruban: true, mainsLibres: true)
        let m = DicteeVerreVue.marge
        return NSRect(x: centre + CGFloat(k.x0) - m, y: haut - CGFloat(k.y1) - m, width: CGFloat(k.largeur) + 2 * m, height: CGFloat(k.hauteur) + 2 * m)
    }
    /// La pilule voulue dans cette boîte (x depuis le bord gauche de la boîte, y depuis son haut).
    func pilule(ruban: Bool, mainsLibres: Bool) -> CGRect {
        let boite = GeoLucarne.dictee(place, ecran, ruban: true, mainsLibres: true)
        let k = GeoLucarne.dictee(place, ecran, ruban: ruban, mainsLibres: mainsLibres)
        let m = DicteeVerreVue.marge
        return CGRect(x: CGFloat(k.x0 - boite.x0) + m, y: CGFloat(k.y0 - boite.y0) + m, width: CGFloat(k.largeur), height: CGFloat(k.hauteur))
    }
}

extension IlotPanneau {
    /// Où se montre la dictée qui commence : nil dans l'encoche (la Lucarne y est, ou y est aspirée), sinon la place de la Lucarne
    /// (ailleurs, ou la pilule du haut au milieu d'un écran sans caméra). Une tenue en cours s'arrête d'abord (la dictée l'interromprait
    /// de toute façon) : sa place est décidée avant d'y poser la dictée.
    func placementDictee() -> PlacementDictee? {
        if moteur.lucarneOccupee { moteur.interrompreLucarne() }
        guard let e = moteur.lucarne.ecran, let ecran, moteur.lucarne.place != .encoche || !e.avecEncoche else { return nil }
        return PlacementDictee(ecran: e, place: moteur.lucarne.place, centre: centre, haut: ecran.frame.maxY)
    }
}

/// La pilule de verre de la dictée : le même verre que la Lucarne (variante claire, voile presque nul, liseré, ombre douce, halo serré
/// sous le contenu), le même contenu que l'encoche (icône de l'app, texte en direct, onde, ✕ et ✓ en mains libres, messages).
struct DicteeVerreVue: View {
    @ObservedObject var verre = ReglageVerre.partage
    @ObservedObject var m: EncocheModele
    var placement: PlacementDictee
    /// Rendus PNG : ImageRenderer ne dessine pas le verre (un blanc léger à la place, le rendu pose son faux verre dessous).
    var statique = false

    /// Autour de la pilule, dans la fenêtre : la place de l'ombre.
    static let marge: CGFloat = 14

    var body: some View {
        let ruban = m.ruban || m.message != nil
        let r = placement.pilule(ruban: ruban, mainsLibres: m.mainsLibres)
        let taille = placement.cadreFenetre.size
        let forme = Capsule()
        ZStack(alignment: .topLeading) {
            ZStack {
                forme.fill(Color.black.opacity(0.22)).blur(radius: 6).offset(y: 3)
                    .mask { Rectangle().padding(-20).overlay { forme.fill(Color.black).blendMode(.destinationOut) }.compositingGroup() }
                if statique { forme.fill(Color.white.opacity(0.05)) } else { Color.clear.glassEffect(.clear, in: forme).modifier(IntensiteVerre()) }
                forme.fill(Color.black.opacity(VerreLucarne.voilePilule(intensite: verre.intensite)))
                LisereVerre(forme: forme, intensite: verre.intensite)
                // rogné à la pilule : pendant qu'elle s'allonge, le texte arrivé ne déborde jamais sur la page (vu à l'écran, 13/11)
                contenu(ruban: ruban).modifier(HaloLucarne(force: 1)).clipShape(forme)
            }
            .frame(width: r.width, height: r.height)
            .offset(x: r.minX, y: r.minY)
        }
        .frame(width: taille.width, height: taille.height, alignment: .topLeading)
        .opacity(m.ouverte ? 1 : 0)
        .scaleEffect(m.ouverte || m.reduire ? 1 : 0.92, anchor: UnitPoint(x: placement.place.ancre.x, y: 0.5))
    }

    /// [✕] icône · texte (ou message) · onde [✓], sur une ligne.
    private func contenu(ruban: Bool) -> some View {
        HStack(spacing: 8) {
            if m.mainsLibres {
                BoutonBande(symbole: "xmark", couleur: EncocheCouleurs.t1, action: m.surAnnuler).accessibilityLabel("Annuler (Échap)")
            }
            if let icone = m.icone {
                Image(nsImage: icone).resizable().interpolation(.high).frame(width: 22, height: 22)
            }
            if ruban {
                Group {
                    if let message = m.message {
                        Text(message).font(.system(size: 13, weight: .semibold)).foregroundStyle(EncocheCouleurs.t1).lineLimit(1)
                    } else {
                        GeometryReader { g in TexteEnDirect(texte: m.texte, fige: m.fige, largeur: g.size.width).frame(height: g.size.height) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer(minLength: 0)
            }
            if let l = m.bulleLecture {
                MiniatureLectureVue(m: l, presence: 1).allowsHitTesting(m.mainsLibres)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
            BarresDeSon(niveaux: m.niveaux)
            if m.mainsLibres {
                BoutonBande(symbole: "checkmark", couleur: EncocheCouleurs.t1, action: m.surValider).accessibilityLabel("Valider")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: CGFloat(GeoLucarne.dicteeHauteur))
    }
}
