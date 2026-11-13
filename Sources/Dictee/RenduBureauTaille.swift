import AppKit
import SwiftUI
import DicteeCore

/// La fenêtre de l'app ne doit jamais grandir toute seule au-delà de sa taille (13/11 : « je peux même pas défiler en entier tout en
/// bas, la fenêtre est beaucoup trop grosse »). Ce contrôle construit la VRAIE fenêtre (`FenetrePrincipale.fabriquer`, jamais
/// montrée), lui donne une taille, laisse SwiftUI la mettre en page, puis vérifie : la fenêtre a gardé sa taille, chaque zone qui
/// défile tient dans la fenêtre, et, défilée au bout, la dernière ligne est à l'écran. Les images sont celles de la vraie fenêtre
/// (`cacheDisplay`) : le verre de macOS 26 n'y est pas dessiné (rendu hors écran), le reste est ce que voit Hugues.
@MainActor
extension RenduBureau {
    /// Les tailles du contrôle : celle de la fenêtre de Hugues le 13/11 (900 × 847), la plus petite des siennes, une grande.
    static let taillesControle: [CGSize] = [CGSize(width: 900, height: 847), CGSize(width: 760, height: 600), CGSize(width: 1200, height: 900)]

    /// Une longue réunion inventée (jamais celle de Hugues) : 48 passages, « Eux » et « Moi » en alternance, le dernier reconnaissable.
    static func reunionLongue() -> Reunion {
        let phrases = ["On reprend le planning de la semaine, il reste trois livraisons à caler avant vendredi.",
                       "D\u{2019}accord, je regarde avec l\u{2019}atelier et je te redis ce soir.",
                       "Le devis de l\u{2019}imprimeur est arrivé, il est un peu plus cher que prévu mais les délais sont bons.",
                       "On le prend quand même, on n\u{2019}a pas le temps de chercher ailleurs.",
                       "Et pour la salle de jeudi, quelqu\u{2019}un a rappelé le traiteur ?",
                       "Pas encore, je m\u{2019}en occupe juste après l\u{2019}appel."]
        var segments: [SegmentReunion] = []
        for i in 0..<47 {
            let l: Locuteur = i % 2 == 0 ? .eux : .moi
            segments.append(SegmentReunion(debut: Double(i * 20), fin: Double(i * 20 + 12), locuteur: l, texte: "\(i + 1). " + phrases[i % phrases.count]))
        }
        segments.append(SegmentReunion(debut: 47 * 20, fin: 47 * 20 + 6, locuteur: .moi, texte: "48. Dernier passage : on se rappelle vendredi à neuf heures."))
        return Reunion(debut: a(0, 10, 0), duree: 980, titre: "Point d\u{2019}équipe, planning de la semaine", participants: ["Moi", "Eux"],
                       dit: ["Trois livraisons à caler avant vendredi", "Devis de l\u{2019}imprimeur accepté"],
                       decisions: ["On garde l\u{2019}imprimeur"], actions: [], segments: segments, etat: .prete, sonGarde: false,
                       enBref: "Planning de la semaine repris, devis accepté, traiteur à rappeler.")
    }

    /// Toutes les zones qui défilent d'une vue AppKit (SwiftUI pose un NSScrollView sous chaque ScrollView).
    private static func zonesQuiDefilent(_ v: NSView) -> [NSScrollView] {
        (v as? NSScrollView).map { [$0] } ?? [] + v.subviews.flatMap { zonesQuiDefilent($0) }
    }

    /// Laisse tourner la boucle principale (les `onAppear`, les mesures de largeur et les mises en page de SwiftUI).
    private static func laisserTourner(_ secondes: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(secondes))
    }

    /// `true` si tout tient. Écrit `taille-<page>-<l>x<h>.png` dans `dossier`.
    static func verifierLaTaille(dossier: URL) -> Bool {
        var ok = true
        let pages: [(String, (Exemple) -> Void)] = [
            ("aujourdhui", { _ in }),
            ("decouvrir", { $0.nav.aller(.decouvrir) }),
            ("reunions", { e in e.nav.aller(.reunions); e.reunions.ouverte = e.reunionsStore.reunions.first { $0.titre.hasPrefix("Point d\u{2019}équipe") }?.id }),
            ("reglages", { $0.nav.aller(.reglages) }),
        ]
        for taille in taillesControle {
            for (nom, regler) in pages {
                let e = Exemple(sombre: true, reunions: [reunionLongue()] + RenduReunions.autres())
                regler(e)
                let f = FenetrePrincipale.fabriquer(e.vue, taille: taille)
                f.appearance = NSAppearance(named: .darkAqua)
                f.setFrame(NSRect(origin: CGPoint(x: 0, y: 0), size: taille), display: false)
                laisserTourner(0.6)
                f.contentView?.layoutSubtreeIfNeeded()
                f.layoutIfNeeded()
                laisserTourner(0.2)
                let etiquette = "\(nom) \(Int(taille.width))×\(Int(taille.height))"
                let reelle = f.frame.size
                if abs(reelle.width - taille.width) > 0.5 || abs(reelle.height - taille.height) > 0.5 {
                    print("ÉCHEC taille \(etiquette) : la fenêtre a pris \(Int(reelle.width))×\(Int(reelle.height)) toute seule")
                    ok = false
                }
                guard let contenu = f.contentView else { ok = false; continue }
                let bornes = contenu.bounds
                var lignes: [String] = []
                for z in zonesQuiDefilent(contenu) where z.window != nil && !z.isHiddenOrHasHiddenAncestor {
                    guard let doc = z.documentView else { continue }
                    let cadre = z.convert(z.bounds, to: contenu)
                    // la zone dépasse du contenu de la fenêtre (un demi-point de tolérance) : son bas n'est jamais visible
                    if cadre.minY < bornes.minY - 0.5 || cadre.maxY > bornes.maxY + 0.5 {
                        print("ÉCHEC taille \(etiquette) : une zone qui défile (\(Int(cadre.height)) pt) sort de la fenêtre (\(Int(bornes.height)) pt), y \(Int(cadre.minY))…\(Int(cadre.maxY))")
                        ok = false
                    }
                    // défiler au bout
                    let visible = z.contentView.bounds.height
                    let fin = doc.isFlipped ? max(0, doc.frame.height - visible) : 0
                    z.contentView.scroll(to: NSPoint(x: z.contentView.bounds.minX, y: fin))
                    z.reflectScrolledClipView(z.contentView)
                    lignes.append("\(Int(cadre.height)) pt visibles sur \(Int(doc.frame.height))")
                }
                laisserTourner(0.3)
                print("taille \(etiquette) : fenêtre \(Int(reelle.width))×\(Int(reelle.height)), zones qui défilent : \(lignes.joined(separator: " ; "))")
                // l'image de la vraie fenêtre, défilée au bout (cadre compris : le contenu de la fenêtre et sa barre de titre)
                let vue = contenu.superview ?? contenu
                if let rep = vue.bitmapImageRepForCachingDisplay(in: vue.bounds) {
                    vue.cacheDisplay(in: vue.bounds, to: rep)
                    _ = RenduVues.ecrire(rep.representation(using: .png, properties: [:]),
                                         dossier.appendingPathComponent("taille-\(nom)-\(Int(taille.width))x\(Int(taille.height)).png"))
                }
                f.close()
            }
        }
        return ok
    }
}
