import AppKit
import SwiftUI
import DicteeCore

/// Vérification visuelle sans fenêtre : `Verbe --rendu-lecture dossier`
/// Dessine l'îlot de la lecture en cours (repos × 3 contenus, déplié × 2, direct, pause, sans image), la dictée (avec la mini-miniature de
/// la lecture dans le ruban) et la zone des icônes de la barre des menus avec l'îlot par-dessus, sur un faux bureau,
/// et écrit des PNG (rien n'apparaît à l'écran). Les pochettes sont fictives (formes et couleurs de la maquette, aucune marque).
/// Ni micro, ni clavier, ni Accessibilité, ni son.
enum RenduLecture {
    // MARK: pochettes fictives (les mêmes formes que la maquette lecture-encoche-v3.html)

    struct ArtSerie: View {
        var body: some View {
            Canvas { c, s in
                let k = s.width / 160
                func P(_ pts: [(CGFloat, CGFloat)]) -> Path { var p = Path(); p.move(to: CGPoint(x: pts[0].0 * k, y: pts[0].1 * k)); for q in pts.dropFirst() { p.addLine(to: CGPoint(x: q.0 * k, y: q.1 * k)) }; p.closeSubpath(); return p }
                c.fill(Path(CGRect(origin: .zero, size: s)), with: .linearGradient(Gradient(stops: [.init(color: Color(hex: 0x050D1B), location: 0), .init(color: Color(hex: 0x12406C), location: 0.5), .init(color: Color(hex: 0x0A2037), location: 1)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: s.height)))
                c.fill(Path(CGRect(origin: .zero, size: s)), with: .radialGradient(Gradient(colors: [Color(hex: 0xCDEAFF).opacity(0.95), Color(hex: 0x4AA3FF).opacity(0.5), Color(hex: 0x4AA3FF).opacity(0)]), center: CGPoint(x: 0.68 * s.width, y: 0.3 * s.height), startRadius: 0, endRadius: 0.5 * s.width))
                c.fill(Path(ellipseIn: CGRect(x: 99 * k, y: 38 * k, width: 18 * k, height: 18 * k)), with: .color(Color(hex: 0xEEF8FF)))
                c.fill(P([(0, 106), (26, 82), (50, 100), (84, 66), (118, 98), (142, 84), (160, 96), (160, 160), (0, 160)]), with: .color(Color(hex: 0x0B2744)))
                c.fill(P([(0, 130), (34, 106), (68, 126), (104, 100), (160, 132), (160, 160), (0, 160)]), with: .color(Color(hex: 0x06182B)))
                c.fill(P([(52, 140), (52, 128), (62, 121), (72, 128), (72, 140)]), with: .color(Color(hex: 0x050F1C)))
                c.fill(Path(CGRect(x: 58 * k, y: 130 * k, width: 5 * k, height: 5 * k)), with: .color(Color(hex: 0xFFB347)))
            }
        }
    }

    struct ArtVideo: View {
        var body: some View {
            Canvas { c, s in
                let k = s.width / 160
                c.fill(Path(CGRect(origin: .zero, size: s)), with: .linearGradient(Gradient(stops: [.init(color: Color(hex: 0x2A0C66), location: 0), .init(color: Color(hex: 0xFF2E88), location: 0.5), .init(color: Color(hex: 0xFFA22E), location: 1)]), startPoint: .zero, endPoint: CGPoint(x: s.width, y: s.height)))
                c.fill(Path(ellipseIn: CGRect(x: 34 * k, y: 32 * k, width: 92 * k, height: 92 * k)), with: .linearGradient(Gradient(stops: [.init(color: Color(hex: 0xFFF6B0), location: 0), .init(color: Color(hex: 0xFF9A3A), location: 0.55), .init(color: Color(hex: 0xFF3F7F), location: 1)]), startPoint: CGPoint(x: 0, y: 32 * k), endPoint: CGPoint(x: 0, y: 124 * k)))
                for (y, h) in [(86.0, 3.0), (96.0, 4.5), (107.0, 6.0)] { c.fill(Path(CGRect(x: 30 * k, y: y * k, width: 100 * k, height: h * k)), with: .color(Color(hex: 0xC4287A).opacity(0.92))) }
                var ville = Path(); ville.move(to: CGPoint(x: 0, y: 118 * k))
                for (x, y) in [(12.0, 118.0), (12, 100), (26, 100), (26, 122), (34, 122), (34, 92), (48, 92), (48, 126), (60, 126), (60, 108), (72, 108), (72, 128), (86, 128), (86, 96), (98, 96), (98, 124), (112, 124), (112, 104), (124, 104), (124, 130), (138, 130), (138, 112), (160, 112), (160, 160), (0, 160)] { ville.addLine(to: CGPoint(x: x * k, y: y * k)) }
                c.fill(ville, with: .color(Color(hex: 0x14052F)))
                for (x, y) in [(16.0, 106.0), (38, 100), (38, 112), (90, 104), (90, 114), (116, 112), (64, 116)] { c.fill(Path(CGRect(x: x * k, y: y * k, width: 3 * k, height: 3 * k)), with: .color(Color(hex: 0x00E5FF))) }
                var l1 = Path(); l1.move(to: CGPoint(x: -4 * k, y: 34 * k)); l1.addLine(to: CGPoint(x: 72 * k, y: 12 * k))
                c.stroke(l1, with: .color(Color(hex: 0x00E5FF).opacity(0.9)), style: StrokeStyle(lineWidth: 2.4 * k, lineCap: .round))
                var l2 = Path(); l2.move(to: CGPoint(x: 110 * k, y: 30 * k)); l2.addLine(to: CGPoint(x: 164 * k, y: 62 * k))
                c.stroke(l2, with: .color(Color(hex: 0x00E5FF).opacity(0.7)), style: StrokeStyle(lineWidth: 2 * k, lineCap: .round))
            }
        }
    }

    struct ArtAlbum: View {
        var body: some View {
            Canvas { c, s in
                let k = s.width / 160
                c.fill(Path(CGRect(origin: .zero, size: s)), with: .radialGradient(Gradient(stops: [.init(color: Color(hex: 0xFFD48F), location: 0), .init(color: Color(hex: 0xEE7A3D), location: 0.45), .init(color: Color(hex: 0x6E1F2C), location: 1)]), center: CGPoint(x: 0.5 * s.width, y: 0.28 * s.height), startRadius: 0, endRadius: 0.85 * s.width))
                for (r, w) in [(34.0, 1.4), (50.0, 1.2), (66.0, 1.0), (84.0, 0.9)] {
                    c.stroke(Path(ellipseIn: CGRect(x: (80 - r) * k, y: (84 - r) * k, width: 2 * r * k, height: 2 * r * k)), with: .color(Color(hex: 0xFFF1D6).opacity(0.38)), lineWidth: w * k)
                }
                c.fill(Path(ellipseIn: CGRect(x: 56 * k, y: 60 * k, width: 48 * k, height: 48 * k)), with: .radialGradient(Gradient(colors: [Color(hex: 0xFFF4DA), Color(hex: 0xFFC98A)]), center: CGPoint(x: 80 * k, y: 76 * k), startRadius: 0, endRadius: 30 * k))
                var v1 = Path(); v1.move(to: CGPoint(x: 0, y: 132 * k))
                v1.addCurve(to: CGPoint(x: 82 * k, y: 126 * k), control1: CGPoint(x: 26 * k, y: 116 * k), control2: CGPoint(x: 52 * k, y: 142 * k))
                v1.addCurve(to: CGPoint(x: 160 * k, y: 128 * k), control1: CGPoint(x: 112 * k, y: 110 * k), control2: CGPoint(x: 134 * k, y: 112 * k))
                v1.addLine(to: CGPoint(x: 160 * k, y: 160 * k)); v1.addLine(to: CGPoint(x: 0, y: 160 * k)); v1.closeSubpath()
                c.fill(v1, with: .color(Color(hex: 0x3A1220).opacity(0.62)))
                var v2 = Path(); v2.move(to: CGPoint(x: 0, y: 144 * k))
                v2.addCurve(to: CGPoint(x: 88 * k, y: 140 * k), control1: CGPoint(x: 30 * k, y: 132 * k), control2: CGPoint(x: 56 * k, y: 152 * k))
                v2.addCurve(to: CGPoint(x: 160 * k, y: 142 * k), control1: CGPoint(x: 120 * k, y: 128 * k), control2: CGPoint(x: 138 * k, y: 128 * k))
                v2.addLine(to: CGPoint(x: 160 * k, y: 160 * k)); v2.addLine(to: CGPoint(x: 0, y: 160 * k)); v2.closeSubpath()
                c.fill(v2, with: .color(Color(hex: 0x240A16).opacity(0.8)))
            }
        }
    }

    @MainActor
    static func image<V: View>(_ vue: V, cote: CGFloat) -> NSImage? {
        let r = ImageRenderer(content: vue.frame(width: cote, height: cote))
        r.scale = 2
        return r.nsImage
    }

    struct Contenu {
        var nom: String
        var morceau: MorceauEnCours
        var site: String?
        var art: NSImage?
    }

    // MARK: rendu

    @MainActor
    static func executer(dossier: String) -> Int32 {
        _ = NSApplication.shared
        let url = URL(fileURLWithPath: (dossier as NSString).expandingTildeInPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let geometrie = NSScreen.screens.first.map { GeometrieEncoche.mesurer($0).0 } ?? GeometrieEncoche()
        print("caméra : \(Int(geometrie.largeur)) × \(Int(geometrie.hauteur)) pt")
        let chrome = ["/Applications/Google Chrome.app"].first { FileManager.default.fileExists(atPath: $0) }.map { NSWorkspace.shared.icon(forFile: $0) }.map { LectureControleur.reduire($0, pixels: 256, rogner: false) ?? $0 }
        let notes = NSWorkspace.shared.icon(forFile: "/System/Applications/Notes.app")

        let contenus: [Contenu] = [
            Contenu(nom: "serie", morceau: MorceauEnCours(titre: "Série · S2 É4 · Le Retour", app: "com.google.Chrome", joue: true, duree: 2530, position: 725),
                    site: "YouTube", art: image(ArtSerie(), cote: 320)),
            Contenu(nom: "video", morceau: MorceauEnCours(titre: "Vlog — Tokyo la nuit", app: "com.google.Chrome", joue: true, duree: 1126, position: 312),
                    site: "YouTube", art: image(ArtVideo(), cote: 320)),
            Contenu(nom: "album", morceau: MorceauEnCours(titre: "Album · Titre 3", app: "com.google.Chrome", joue: true, duree: 214, position: 97),
                    site: "YouTube Music", art: image(ArtAlbum(), cote: 320)),
        ]

        func modele(_ c: Contenu, joue: Bool = true, direct: Bool = false) -> LectureModele {
            let m = LectureModele()
            m.geometrie = geometrie
            m.statique = true
            var mo = c.morceau
            mo.joue = joue
            if direct { mo.duree = nil; mo.position = nil }
            m.morceau = mo
            m.image = c.art
            m.teinte = c.art.map { LectureControleur.teinte(de: $0) } ?? .neutre
            m.site = c.site
            m.nomApp = "Google Chrome"
            m.iconeApp = chrome
            return m
        }

        /// Un faux bureau (fond sombre bleu-violet, barre des menus, fenêtre) de la largeur de la maquette.
        func bureau<Contenu: View>(hauteur: CGFloat, @ViewBuilder _ contenu: () -> Contenu) -> some View {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0x1F2A44), Color(hex: 0x181C27), Color(hex: 0x2A2038)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(RadialGradient(colors: [Color(hex: 0x34456A).opacity(0.9), .clear], center: UnitPoint(x: 0.14, y: 0), startRadius: 0, endRadius: 520))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.09)))
                HStack(spacing: 16) {
                    Text("Chrome").bold().foregroundStyle(.white)
                    Text("Fichier"); Text("Édition"); Text("Présentation"); Text("Fenêtre")
                    Spacer()
                    Text("lun. 9 nov.  14:32")
                }
                .font(.system(size: 12.5)).foregroundStyle(Color.white.opacity(0.7))
                .padding(.horizontal, 16).frame(height: geometrie.hauteur)
                .background(Color.black.opacity(0.3))
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: 0x0E1016).opacity(0.62))
                    .overlay(alignment: .topLeading) {
                        HStack(spacing: 8) { ForEach(0..<3, id: \.self) { _ in Circle().fill(Color(hex: 0x6B6F78)).frame(width: 7, height: 7) } }.padding(.leading, 14).padding(.top, 11)
                    }
                    .frame(height: max(0, hauteur - geometrie.hauteur - 30))
                    .padding(.horizontal, 28).padding(.top, geometrie.hauteur + 30).frame(maxHeight: .infinity, alignment: .top)
                contenu()
            }
            .frame(width: 1142, height: hauteur, alignment: .top)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }

        func ilot(_ m: LectureModele, p: CGFloat) -> some View {
            IlotVue(p: p, absence: 0, m: m, tailleFenetre: LectureMesures.tailleVue(geometrie))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }

        var ok = true
        func ecrire<V: View>(_ vue: V, _ nom: String) {
            let rendu = ImageRenderer(content: vue)
            rendu.scale = 2
            guard let image = rendu.nsImage, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { print("échec du rendu \(nom)"); ok = false; return }
            let fichier = url.appendingPathComponent("\(nom).png")
            try? png.write(to: fichier)
            print("écrit \(fichier.path) (\(rep.pixelsWide)×\(rep.pixelsHigh))")
        }

        let petitBureau: CGFloat = 132, grandBureau: CGFloat = geometrie.hauteur + 270
        for c in contenus {
            let m = modele(c)
            print("teinte \(c.nom) : \(m.teinte.clair.hexa) / \(m.teinte.profond.hexa), genre \(m.genre), source « \(m.libelleSource) »")
            ecrire(bureau(hauteur: petitBureau) { ilot(m, p: 0) }, "repos-\(c.nom)")
        }
        for c in [contenus[0], contenus[2]] {
            ecrire(bureau(hauteur: grandBureau) { ilot(modele(c), p: 1) }, "ouvert-\(c.nom)")
        }
        ecrire(bureau(hauteur: grandBureau) { ilot(modele(contenus[1], joue: false), p: 1) }, "ouvert-video-en-pause")
        ecrire(bureau(hauteur: grandBureau) { ilot(modele(contenus[0], direct: true), p: 1) }, "ouvert-direct")
        ecrire(bureau(hauteur: petitBureau) { ilot(modele(contenus[2], joue: false), p: 0) }, "repos-album-en-pause")
        ecrire(bureau(hauteur: grandBureau) { ilot(modele(contenus[2]), p: 0.5) }, "transition-mi-course")

        // sans image du système ni miniature : l'icône de l'app en petit sur fond sombre, teinte tirée de l'icône
        func sansImage(_ c: Contenu, joue: Bool = true) -> LectureModele {
            let m = modele(c, joue: joue)
            m.image = nil
            m.teinte = chrome.map { LectureControleur.teinte(de: $0) } ?? .neutre
            return m
        }
        do {
            let m = sansImage(contenus[1])
            print("teinte (icône de l'app) : \(m.teinte.clair.hexa)")
            ecrire(bureau(hauteur: petitBureau) { ilot(m, p: 0) }, "repos-sans-image")
            ecrire(bureau(hauteur: grandBureau) { ilot(m, p: 1) }, "ouvert-sans-image")
        }

        // la dictée prend la place : l'îlot s'efface ; la lecture (en pause) devient une mini-miniature DANS le ruban de texte, au bout, côté droit
        let tailleDictee = EnclochePanneau.tailleFenetre(pour: geometrie)
        func dictee(mainsLibres: Bool, avecMiniature: Bool) -> EncocheModele {
            let e = EncocheModele()
            e.geometrie = geometrie
            e.ouverte = true; e.ruban = true; e.texte = "Je te rappelle demain pour confirmer le rendez-vous de jeudi"
            e.mainsLibres = mainsLibres
            e.reserveRuban = avecMiniature ? LectureMiniature.reserve : 0
            e.icone = notes
            e.niveaux = [0.35, 0.7, 1.0, 0.55, 0.25]
            return e
        }
        /// La dictée et, posée dessus à son vrai emplacement (celui du petit panneau cliquable), la mini-miniature.
        func scene(_ lecture: LectureModele?, mainsLibres: Bool = false) -> some View {
            let finRuban = 1142 / 2 + (geometrie.largeur + 2 * GeometrieEncoche.aile) / 2 - GeometrieEncoche.retraitRuban
            let droite = finRuban - LectureMiniature.retraitDroit + 4
            return ZStack(alignment: .topLeading) {
                EncocheVue(m: dictee(mainsLibres: mainsLibres, avecMiniature: lecture != nil), tailleFenetre: tailleDictee)
                    .frame(width: 1142, height: tailleDictee.height, alignment: .top)
                if let lecture {
                    MiniatureLectureVue(m: lecture, presence: 1)
                        .frame(width: LectureMiniature.tailleFenetre.width, height: LectureMiniature.tailleFenetre.height)
                        .offset(x: droite - LectureMiniature.tailleFenetre.width, y: geometrie.hauteur)
                }
            }
            .frame(width: 1142, height: tailleDictee.height, alignment: .topLeading)
        }
        ecrire(bureau(hauteur: geometrie.hauteur + 80) { scene(nil).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top) }, "dictee-sans-lecture")
        ecrire(bureau(hauteur: geometrie.hauteur + 80) { scene(modele(contenus[2], joue: false)).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top) }, "dictee-miniature-musique")
        ecrire(bureau(hauteur: geometrie.hauteur + 80) { scene(modele(contenus[1], joue: false)).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top) }, "dictee-miniature-video")
        ecrire(bureau(hauteur: geometrie.hauteur + 80) { scene(sansImage(contenus[1], joue: false)).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top) }, "dictee-miniature-icone-app")
        ecrire(bureau(hauteur: geometrie.hauteur + 80) { scene(modele(contenus[0], joue: false), mainsLibres: true).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top) }, "dictee-mains-libres-miniature")

        // la zone des icônes : barre des menus remplie d'icônes jusqu'à la caméra ; les repères en pointillé marquent la limite de la bande
        // de la dictée (caméra + 90 pt de chaque côté). L'îlot, au repos comme déplié, ne doit rien cacher au-delà.
        func zoneIcones(_ m: LectureModele, p: CGFloat, avecDictee: Bool = false, hauteur: CGFloat) -> some View {
            let demiCamera = geometrie.largeur / 2, limite = demiCamera + GeometrieEncoche.aile
            let symboles = ["wifi", "battery.100", "magnifyingglass", "switch.2", "speaker.wave.2.fill", "moon.fill", "bell.fill", "airplayvideo"]
            let menus = ["Aide", "Fenêtre", "Signets", "Historique", "Présentation", "Édition", "Fichier"]
            return ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: 0x3B5B8C))
                    .overlay(LinearGradient(colors: [Color.white.opacity(0.18), .clear], startPoint: .top, endPoint: .bottom))
                HStack(spacing: 0) {
                    HStack(spacing: 14) { ForEach(menus, id: \.self) { Text($0).font(.system(size: 12.5)) } }
                        .frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 8)
                    Color.clear.frame(width: geometrie.largeur)
                    HStack(spacing: 16) { ForEach(symboles, id: \.self) { Image(systemName: $0).font(.system(size: 12.5)) } }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 8)
                }
                .foregroundStyle(Color.white.opacity(0.92)).frame(height: geometrie.hauteur)
                .background(Color.black.opacity(0.18))
                // repères : limite de la bande de la dictée, de part et d'autre de la caméra
                HStack(spacing: 0) {
                    Rectangle().fill(Color.clear).frame(width: 1142 / 2 - limite)
                    Rectangle().fill(Color(hex: 0xFF3B30)).frame(width: 1, height: hauteur)
                    Spacer(minLength: 0)
                    Rectangle().fill(Color(hex: 0xFF3B30)).frame(width: 1, height: hauteur)
                    Rectangle().fill(Color.clear).frame(width: 1142 / 2 - limite)
                }
                .frame(width: 1142, height: hauteur)
                if avecDictee {
                    scene(m).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                } else {
                    ilot(m, p: p)
                }
            }
            .frame(width: 1142, height: hauteur, alignment: .top)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        ecrire(zoneIcones(modele(contenus[1]), p: 0, hauteur: geometrie.hauteur + 40), "zone-icones-repos")
        ecrire(zoneIcones(modele(contenus[1]), p: 1, hauteur: grandBureau), "zone-icones-ouvert")
        ecrire(zoneIcones(modele(contenus[1], joue: false), p: 0, avecDictee: true, hauteur: geometrie.hauteur + 40), "zone-icones-dictee")

        return ok ? 0 : 1
    }
}
