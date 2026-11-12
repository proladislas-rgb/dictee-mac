import AppKit
import SwiftUI
import UniformTypeIdentifiers
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
    static func image<V: View>(_ vue: V, cote: CGFloat, hauteur: CGFloat? = nil) -> NSImage? {
        let r = ImageRenderer(content: vue.frame(width: cote, height: hauteur ?? cote).clipped())
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
                    site: "YouTube", art: image(ArtVideo(), cote: 480, hauteur: 270)),  // 16:9, comme une vraie miniature YouTube
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

        /// Un faux bureau de la largeur utile de l'îlot. Clair par défaut (page blanche d'un lecteur vidéo, barre des menus claire) : la
        /// silhouette noire, ses épaules creuses et son ombre s'y jugent bien ; sombre comme le Chrome de Hugues pour comparer.
        func bureau<Contenu: View>(hauteur: CGFloat, clair: Bool = true, geo: GeometrieEncoche? = nil, @ViewBuilder _ contenu: () -> Contenu) -> some View {
            let gg = geo ?? geometrie
            let encre = clair ? Color(hex: 0x1D1D1F) : Color.white.opacity(0.88)
            return ZStack(alignment: .top) {
                (clair ? Color(hex: 0xF5F5F7) : Color(hex: 0x18181A))
                // la page : une grande miniature jaune (une vidéo) et une colonne de suggestions
                HStack(alignment: .top, spacing: 18) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LinearGradient(colors: clair ? [Color(hex: 0xFFD54A), Color(hex: 0xF29A1F)] : [Color(hex: 0x0F0F11), Color(hex: 0x111114)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 380)
                    VStack(spacing: 10) {
                        ForEach(0..<4, id: \.self) { _ in RoundedRectangle(cornerRadius: 9, style: .continuous).fill(clair ? Color(hex: 0xE4E4E8) : Color(hex: 0x222225)).frame(height: 54) }
                    }
                }
                .padding(.horizontal, 28).padding(.top, gg.hauteur + 52)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                // onglets du navigateur, sous la barre
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { _ in Circle().fill(clair ? Color(hex: 0xC9C9CE) : Color(hex: 0x4A4A4F)).frame(width: 9, height: 9) }
                    RoundedRectangle(cornerRadius: 7).fill(clair ? Color.white : Color(hex: 0x26262A)).frame(width: 190, height: 24).padding(.leading, 18)
                    Spacer()
                }
                .padding(.leading, 14).frame(height: 40).frame(maxWidth: .infinity)
                .background(clair ? Color(hex: 0xE8E8EC) : Color(hex: 0x141416))
                .padding(.top, gg.hauteur)
                HStack(spacing: 18) {
                    Image(systemName: "apple.logo").font(.system(size: 13, weight: .semibold))
                    Text("Chrome").fontWeight(.bold)
                    Text("Fichier"); Text("Édition"); Text("Présentation"); Text("Historique"); Text("Aide")
                    Spacer()
                    Image(systemName: "wifi"); Image(systemName: "magnifyingglass")
                    Text("Mar. 10 nov.  14:32")
                }
                .font(.system(size: 12.5, weight: .medium)).foregroundStyle(encre)
                .padding(.horizontal, 16).frame(height: gg.hauteur)
                .background(clair ? Color.white.opacity(0.78) : Color(hex: 0x161618).opacity(0.85))
                contenu()
            }
            .frame(width: 640, height: hauteur, alignment: .top)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }

        var ok = true
        func ecrire<V: View>(_ vue: V, _ nom: String) {
            let rendu = ImageRenderer(content: vue)
            rendu.scale = 1.5
            guard let image = rendu.nsImage, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { print("échec du rendu \(nom)"); ok = false; return }
            let fichier = url.appendingPathComponent("\(nom).png")
            try? png.write(to: fichier)
            print("écrit \(fichier.path) (\(rep.pixelsWide)×\(rep.pixelsHigh))")
        }

        // ---- l'îlot : un moteur par scène, ressorts posés, aucun temps réel ----
        let cal = Calendar.current
        let t0 = cal.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 14, minute: 32))!
        let rdv = EvenementAgenda(id: "r", titre: "Point équipe", debut: t0.addingTimeInterval(600), fin: t0.addingTimeInterval(2580), lieu: nil, lien: URL(string: "https://meet.exemple.fr/pt-eq-93"))
        let rappelExemple = Rappel(texte: "Appeler Paul", echeance: t0, sonneLe: t0, cree: t0.addingTimeInterval(-3600))
        // les dictées de la maquette (14:43, 14:12…), datées d'aujourd'hui pour un « maintenant » à 14:32 (le rendu ne les compare qu'au jour)
        let dicteesRendu = IlotEssai.dicteesFactices(maintenant: t0.addingTimeInterval(40 * 60))
        func scene(lecture: LectureModele? = nil, geo: GeometrieEncoche? = nil, poser: Bool = true, _ config: (IlotMoteur) -> Void) -> IlotMoteur {
            let gg = geo ?? geometrie
            let lec = lecture ?? modele(contenus[2])
            lec.geometrie = gg
            let m = IlotMoteur(lecture: lec)
            m.geometrie = gg; m.statique = true; m.maintenant = { t0 }; m.calendrierActif = true
            // la carte Dictées : un historique factice en mémoire (jamais le vrai : ces images sont dans un dépôt public)
            m.dictees.source = { HistoriqueStore(enMemoire: dicteesRendu) }
            config(m)
            m.donneesChangees()
            if poser { m.poser() }
            return m
        }
        func ilot(_ m: IlotMoteur) -> some View { IlotVue(m: m).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top) }
        let petitBureau: CGFloat = geometrie.hauteur + 70, moyenBureau: CGFloat = geometrie.hauteur + 130, grandBureau: CGFloat = geometrie.hauteur + 240
        func minut(_ min: Double, restant: Double? = nil) -> MinuteurIlot { MinuteurIlot(minutes: min, depuis: t0.addingTimeInterval(-(min * 60 - (restant ?? min * 60)))) }
        let musique = modele(contenus[2])
        let videoLongue = modele(Contenu(nom: "ipod", morceau: MorceauEnCours(titre: "Je détestais la mode des iPods, donc j\u{2019}en ai racheté un en 2026", artiste: "Le Coin Tech", app: "com.google.Chrome", joue: true, duree: 774, position: 202),
                                         site: "YouTube", art: image(ArtVideo(), cote: 480, hauteur: 270)))
        let video = modele(contenus[1])
        /// Une image à mi-course : on part de la scène posée, on change l'état, on avance de `t` secondes.
        func miCourse(_ m: IlotMoteur, _ t: Double, _ changer: (IlotMoteur) -> Void) -> IlotMoteur {
            changer(m); m.donneesChangees()
            var r = t; while r > 0.0001 { let d = min(1.0 / 120, r); m.avancer(d); r -= d }
            return m
        }
        // 1 · lecture et minuteur
        ecrire(bureau(hauteur: petitBureau) { ilot(scene { _ in }) }, "ilot-1a-vide")
        ecrire(bureau(hauteur: petitBureau) { ilot(scene { $0.minuteur = minut(10, restant: 392) }) }, "ilot-1b-compact-minuteur")
        ecrire(bureau(hauteur: petitBureau) { ilot(scene(lecture: musique) { $0.lecturePresente = true }) }, "ilot-1c-compact-musique")
        ecrire(bureau(hauteur: petitBureau) { ilot(scene(lecture: videoLongue) { $0.lecturePresente = true }) }, "ilot-1c2-compact-video")
        // les dépliés d'activité portent le bouton « Centre » à leur pied (40 pt de plus) : `piedBureau` les montre en entier
        let piedBureau: CGFloat = geometrie.hauteur + 175
        ecrire(bureau(hauteur: piedBureau) { ilot(scene { $0.minuteur = minut(10, restant: 392); $0.survole = true }) }, "ilot-1d-etendu-minuteur")
        ecrire(bureau(hauteur: grandBureau) { ilot(scene(lecture: musique) { $0.lecturePresente = true; $0.survole = true }) }, "ilot-1e-etendu-musique")
        ecrire(bureau(hauteur: grandBureau) { ilot(scene(lecture: videoLongue) { $0.lecturePresente = true; $0.survole = true }) }, "ilot-1f-etendu-video-titre-long")
        ecrire(bureau(hauteur: grandBureau, clair: false) { ilot(scene(lecture: videoLongue) { $0.lecturePresente = true; $0.survole = true }) }, "ilot-1f2-etendu-video-fond-sombre")
        ecrire(bureau(hauteur: grandBureau) { ilot(scene(lecture: modele(contenus[0], direct: true)) { $0.lecturePresente = true; $0.survole = true }) }, "ilot-1g-etendu-direct")
        ecrire(bureau(hauteur: grandBureau) { ilot(scene(lecture: modele(contenus[2], joue: false)) { $0.lecturePresente = true; $0.survole = true }) }, "ilot-1m-etendu-en-pause")
        // appui long sur la lecture : la rangée Minuteur (maquette apple-acces/1-controles.html), seule puis avec un minuteur qui tourne
        ecrire(bureau(hauteur: geometrie.hauteur + 300) { ilot(scene(lecture: videoLongue) { $0.lecturePresente = true; $0.donneesChangees(); $0.appuiLong(minuteurActif: true) }) }, "ilot-1n-lecture-rangee-minuteur")
        ecrire(bureau(hauteur: geometrie.hauteur + 300, clair: false) { ilot(scene(lecture: musique) { $0.lecturePresente = true; $0.minuteur = minut(10, restant: 252); $0.donneesChangees(); $0.appuiLong(minuteurActif: true) }) }, "ilot-1n2-lecture-rangee-minuteur-en-cours")
        for (cam, barre) in [(179.0, 33.0), (200.0, 32.0)] {
            let gg = GeometrieEncoche(largeur: CGFloat(cam), hauteur: CGFloat(barre))
            // une vidéo de plus d'une heure : les temps (« −1:05:12 ») ne sont jamais coupés
            let longue = modele(Contenu(nom: "heure", morceau: MorceauEnCours(titre: "Je détestais la mode des iPods, donc j\u{2019}en ai racheté un en 2026", artiste: "Le Coin Tech", app: "com.google.Chrome", joue: true, duree: 4523, position: 1211),
                                        site: "YouTube", art: image(ArtVideo(), cote: 480, hauteur: 270)))
            ecrire(bureau(hauteur: barre + 240, geo: gg) { ilot(scene(lecture: longue, geo: gg) { $0.lecturePresente = true; $0.survole = true }) }, "ilot-1j-etendu-video-camera-\(Int(cam))")
            ecrire(bureau(hauteur: barre + 70, geo: gg) { ilot(scene(lecture: video, geo: gg) { $0.lecturePresente = true }) }, "ilot-1k-compact-video-camera-\(Int(cam))")
        }
        // 2 · deux activités à la fois : la deuxième goutte sous la barre
        ecrire(bureau(hauteur: petitBureau) { ilot(scene(lecture: musique) { $0.lecturePresente = true; $0.minuteur = minut(10, restant: 372) }) }, "ilot-2a-lecture-et-pastille-minuteur")
        ecrire(bureau(hauteur: petitBureau) { ilot(scene(lecture: videoLongue) { m in m.lecturePresente = true; m.minuteur = minut(10, restant: 372); m.donneesChangees(); m.poser(); m.cliquerPastille(); m.poser(); m.pastilleOuverte.cible = 1 }) }, "ilot-2b-minuteur-et-pastille-lecture-survolee")
        for (t, nom) in [(0.20, "c"), (0.26, "d"), (0.32, "e")] {
            ecrire(bureau(hauteur: petitBureau) { ilot(miCourse(scene(lecture: musique) { $0.lecturePresente = true }, t) { $0.minuteur = minut(10, restant: 372) }) }, "ilot-2\(nom)-goutte-\(Int(t * 1000))ms")
        }
        // 3 · accueil et minuteur
        // l'accueil est devenu la carte sous le Centre (points de page à droite)
        ecrire(bureau(hauteur: grandBureau) { ilot(scene { m in m.derniereDictee = ("Je te rappelle demain pour confirmer le créneau avec l\u{2019}équipe", "3 min"); m.rendezVousSuivant = rdv
            m.donneesChangees(); m.allerA(.accueil) }) }, "ilot-3a-accueil")
        ecrire(bureau(hauteur: grandBureau) { ilot(scene { m in m.calendrierActif = false; m.donneesChangees(); m.allerA(.accueil) }) }, "ilot-3a2-accueil-vide")
        ecrire(bureau(hauteur: petitBureau + 20) { ilot(scene { $0.bandeau = BandeauIlot(vue: .minuteurLance, jusqua: t0, ligne1: "Minuteur lancé", ligne2: "10 min \u{00B7} fin à 14:42"); $0.minuteur = minut(10) }) }, "ilot-3b-minuteur-lance")
        ecrire(bureau(hauteur: moyenBureau) { ilot(scene { $0.alerte = AlerteIlot(vue: .minuteurFini, jusqua: nil, libelle: "10 min") }) }, "ilot-3d-minuteur-fini")
        ecrire(bureau(hauteur: piedBureau) { ilot(scene { var x = minut(10, restant: 392); x.pause(a: t0); $0.minuteur = x; $0.survole = true }) }, "ilot-3e-minuteur-en-pause")
        // 4 · rappels
        ecrire(bureau(hauteur: petitBureau + 20) { ilot(scene { $0.bandeau = BandeauIlot(vue: .rappelAjoute, jusqua: t0, ligne1: "Rappel ajouté", ligne2: "Appeler Paul \u{00B7} aujourd\u{2019}hui", meta: "15:00") }) }, "ilot-4a-rappel-ajoute")
        ecrire(bureau(hauteur: grandBureau) { ilot(scene { let r = Rappel(texte: "Appeler Paul", echeance: t0.addingTimeInterval(1700), cree: t0); let r2 = Rappel(texte: "Envoyer le devis à la mairie avant la réunion de jeudi", echeance: t0.addingTimeInterval(10000), cree: t0); $0.rappelsAVenir = [r, r2]; $0.ouvrirFormulaireRappel() }) }, "ilot-4b-rappels-liste")
        ecrire(bureau(hauteur: moyenBureau) { ilot(scene { $0.alerte = AlerteIlot(vue: .rappelEtendu, jusqua: nil, rappel: rappelExemple); $0.rappelsSonnes = [rappelExemple] }) }, "ilot-4c-rappel-arrive")
        ecrire(bureau(hauteur: petitBureau) { ilot(scene { $0.rappelsSonnes = [rappelExemple] }) }, "ilot-4d-cloche-sans-reponse")
        ecrire(bureau(hauteur: petitBureau + 20) { ilot(scene { $0.bandeau = BandeauIlot(vue: .rappelFait, jusqua: t0, ligne1: "Fait", ligne2: "Appeler Paul") }) }, "ilot-4e-fait")
        ecrire(bureau(hauteur: petitBureau + 20) { ilot(scene { $0.bandeau = BandeauIlot(vue: .rappelReporte, jusqua: t0, ligne1: "Je vous le redis dans 10 min", ligne2: "Appeler Paul", meta: "15:10") }) }, "ilot-4f-plus-tard")
        // 5 · calendrier
        ecrire(bureau(hauteur: petitBureau + 20) { ilot(scene { $0.rendezVous = rdv; $0.rendezVousProche = true; $0.bandeau = BandeauIlot(vue: .agendaAvant, jusqua: t0, ligne1: "Point équipe", ligne2: "Dans 10 min \u{00B7} Visio", evenement: rdv) }) }, "ilot-5a-rendez-vous-10-min")
        ecrire(bureau(hauteur: petitBureau) { ilot(scene { $0.rendezVous = rdv; $0.rendezVousProche = true }) }, "ilot-5a2-rendez-vous-compact")
        ecrire(bureau(hauteur: grandBureau) { ilot(scene { $0.rendezVous = rdv; $0.rendezVousProche = true; $0.survole = true }) }, "ilot-5b-rendez-vous-etendu")
        ecrire(bureau(hauteur: petitBureau + 20) { ilot(scene { $0.rendezVous = rdv; $0.alerte = AlerteIlot(vue: .agendaDebut, jusqua: nil, evenement: rdv) }) }, "ilot-5c-rendez-vous-commence")
        // 6 · notifications
        let n1 = NotificationRecue(app: "Messages", titre: "Camille", corps: "On se retrouve à 19 h devant le cinéma ? Je réserve les places si tu confirmes avant ce soir", date: t0)
        ecrire(bureau(hauteur: petitBureau + 20) { ilot(scene { $0.notifications = [n1]; $0.bandeau = BandeauIlot(vue: .notification, jusqua: t0, ligne1: "Camille", ligne2: n1.corps) }) }, "ilot-6a-notification")
        ecrire(bureau(hauteur: petitBureau + 20) { ilot(scene { $0.notifications = [n1, NotificationRecue(app: "Banque", titre: "Banque", corps: "", date: t0), NotificationRecue(app: "Slack", titre: "Équipe projet", corps: "", date: t0)]; $0.bandeau = BandeauIlot(vue: .notifications, jusqua: t0, ligne1: "", ligne2: "") }) }, "ilot-6b-notifications-groupees")
        // 8 · priorités : une alerte arrive, la lecture patiente (la pastille rentre dans l'îlot)
        ecrire(bureau(hauteur: moyenBureau) { ilot(scene(lecture: musique) { $0.lecturePresente = true; $0.minuteur = minut(10, restant: 372); $0.alerte = AlerteIlot(vue: .rappelEtendu, jusqua: nil, rappel: rappelExemple); $0.rappelsSonnes = [rappelExemple] }) }, "ilot-8-alerte-et-pastille")
        // 9 · à mi-course : la forme se gonfle, la pochette voyage, le contenu arrive après
        for (t, nom) in [(0.08, "a"), (0.16, "b"), (0.26, "c"), (0.40, "d")] {
            ecrire(bureau(hauteur: grandBureau) { ilot(miCourse(scene(lecture: videoLongue) { $0.lecturePresente = true }, t) { $0.survole = true }) }, "ilot-9\(nom)-ouverture-\(Int(t * 1000))ms")
        }
        for (t, nom) in [(0.08, "e"), (0.20, "f")] {
            ecrire(bureau(hauteur: grandBureau) { ilot(miCourse(scene(lecture: videoLongue) { $0.lecturePresente = true; $0.survole = true }, t) { $0.survole = false }) }, "ilot-9\(nom)-fermeture-\(Int(t * 1000))ms")
        }
        ecrire(bureau(hauteur: piedBureau) { ilot(miCourse(scene { $0.minuteur = minut(10, restant: 392) }, 0.2) { $0.survole = true }) }, "ilot-9g-minuteur-mi-course")
        // la dictée prend la place : tout est effacé, il ne reste que l'encoche de la dictée
        ecrire(bureau(hauteur: petitBureau) { ilot(scene(lecture: musique) { $0.lecturePresente = true; $0.minuteur = minut(10, restant: 372); $0.dictee = true }) }, "ilot-10-dictee-efface-tout")
        // batterie et appareils (maquette ilot-apple.html) : épaules du déplié, écouteurs connectés, chargeur branché, batterie faible
        let batterie = EnergieIlot(pourcent: 33, secteur: true, enCharge: true)
        let airpods = AppareilIlot(nom: "AirPods Pro de Hugues", genre: .ecouteurs, gauche: 80, droit: 78, etui: 45)
        ecrire(bureau(hauteur: geometrie.hauteur + 300, clair: false) { ilot(scene(lecture: videoLongue) { m in m.energie = batterie; m.ecouteurs = airpods; m.lecturePresente = true; m.minuteur = minut(10, restant: 578); m.donneesChangees(); m.appuiLong(minuteurActif: true) }) }, "ilot-11a-epaules-lecture-minuteur")
        ecrire(bureau(hauteur: grandBureau) { ilot(scene { m in m.energie = EnergieIlot(pourcent: 64, secteur: false, enCharge: false); m.ecouteurs = airpods; m.derniereDictee = ("Je te rappelle demain pour confirmer le créneau avec l\u{2019}équipe", "3 min"); m.rendezVousSuivant = rdv
            m.donneesChangees(); m.allerA(.accueil) }) }, "ilot-11b-epaules-accueil")
        ecrire(bureau(hauteur: geometrie.hauteur + 230, clair: false) { ilot(scene(lecture: videoLongue) { m in m.energie = EnergieIlot(pourcent: 100, secteur: true, enCharge: false); m.ecouteurs = airpods; m.lecturePresente = true; m.donneesChangees(); m.survole = true; m.donneesChangees() }) }, "ilot-11f-epaules-100-branche")
        ecrire(bureau(hauteur: geometrie.hauteur + 230, clair: false) { ilot(scene(lecture: videoLongue) { m in m.energie = EnergieIlot(pourcent: 14, secteur: false, enCharge: false); m.ecouteurs = airpods; m.lecturePresente = true; m.donneesChangees(); m.survole = true; m.donneesChangees() }) }, "ilot-11g-epaules-14")
        // le choix du micro de la dictée est passé dans le Centre (bouton « Dictée », Mac / AirPods)
        ecrire(bureau(hauteur: geometrie.hauteur + 300) { ilot(scene { m in m.energie = EnergieIlot(pourcent: 64, secteur: false, enCharge: false); m.ecouteurs = airpods; m.choixMicro = ("AirPods Pro de Hugues", false); m.survole = true }) }, "ilot-11h-centre-choix-micro")
        ecrire(bureau(hauteur: petitBureau + 30) { ilot(scene { $0.energie = batterie; $0.bandeau = BandeauIlot(vue: .appareil, jusqua: t0, ligne1: airpods.titre, ligne2: "", appareil: airpods) }) }, "ilot-11c-airpods-connectes")
        ecrire(bureau(hauteur: petitBureau) { ilot(scene { $0.energie = batterie; $0.bandeau = BandeauIlot(vue: .batterieCharge, jusqua: t0, ligne1: "En charge", ligne2: "", energie: batterie) }) }, "ilot-11d-en-charge")
        ecrire(bureau(hauteur: petitBureau) { ilot(scene(lecture: videoLongue) { let e = EnergieIlot(pourcent: 20, secteur: false, enCharge: false); $0.energie = e; $0.lecturePresente = true; $0.bandeau = BandeauIlot(vue: .batterieFaible, jusqua: t0, ligne1: "Batterie faible", ligne2: "", energie: e) }) }, "ilot-11e-batterie-faible-pendant-video")
        // téléchargé (maquette ilot-apple.html, cinq idées de plus) : le fichier arrivé, un nom trop long coupé au milieu, AirDrop, une rafale
        func telecharge(_ l: [(String, Int64?, Bool, UTType)]) -> BandeauIlot {
            var r = RafaleTelechargements()
            for (i, f) in l.enumerated() { r.ajouter([FichierTelecharge(url: URL(fileURLWithPath: "/Users/exemple/Downloads/" + f.0), taille: f.1, airdrop: f.2)], a: t0.addingTimeInterval(Double(i))) }
            let icones = l.suffix(2).reversed().map { NSWorkspace.shared.icon(for: $0.3) }
            return BandeauIlot(vue: .telecharge, jusqua: t0, ligne1: r.titre, ligne2: r.sousTitre, telechargement: TelechargementIlot(rafale: r, icones: icones))
        }
        ecrire(bureau(hauteur: petitBureau + 30) { ilot(scene { $0.bandeau = telecharge([("Contrat-signé.pdf", 2_400_000, false, .pdf)]) }) }, "ilot-14a-telecharge")
        ecrire(bureau(hauteur: petitBureau + 30) { ilot(scene { $0.bandeau = telecharge([("Rapport-annuel-2026-direction-financière-version-définitive-signée-v3.pdf", 18_734_000, false, .pdf)]) }) }, "ilot-14b-telecharge-nom-long")
        ecrire(bureau(hauteur: petitBureau + 30) { ilot(scene { $0.bandeau = telecharge([("IMG_2041.HEIC", 3_100_000, true, .heic)]) }) }, "ilot-14c-recu-par-airdrop")
        ecrire(bureau(hauteur: petitBureau + 30) { ilot(scene(lecture: videoLongue) { $0.lecturePresente = true; $0.bandeau = telecharge([("Photo 1.heic", 900_000, false, .heic), ("Photo 2.heic", 800_000, false, .heic), ("Devis.pdf", 1_400_000, false, .pdf)]) }) }, "ilot-14d-trois-fichiers-pendant-video")
        // une capture d'écran arrive sur l'étagère (« Captures d'écran ici ») : sa miniature (une fausse capture, écrite dans un dossier
        // temporaire, lue par le vrai chemin), « Capture d’écran · Sur l’étagère » ; une rafale de trois
        let fausseCapture = FileManager.default.temporaryDirectory.appendingPathComponent("rendu-ilot-capture.png")
        let dessin = NSImage(size: NSSize(width: 1600, height: 1000), flipped: false) { r in
            NSGradient(starting: NSColor(calibratedRed: 0.20, green: 0.36, blue: 0.62, alpha: 1), ending: NSColor(calibratedRed: 0.55, green: 0.32, blue: 0.58, alpha: 1))?.draw(in: r, angle: -35)
            NSColor.white.setFill(); NSBezierPath(roundedRect: NSRect(x: 240, y: 170, width: 1120, height: 680), xRadius: 24, yRadius: 24).fill()
            NSColor(white: 0.92, alpha: 1).setFill(); NSRect(x: 240, y: 790, width: 1120, height: 60).fill()
            NSColor(white: 0.80, alpha: 1).setFill(); for i in 0..<6 { NSRect(x: 300, y: 690 - i * 80, width: 640 - (i % 3) * 120, height: 26).fill() }
            return true
        }
        if let t = dessin.tiffRepresentation, let png = NSBitmapImageRep(data: t)?.representation(using: .png, properties: [:]) { try? png.write(to: fausseCapture) }
        let vignette = IlotControleur.vignetteCapture(fausseCapture)
        func captures(_ n: Int) -> BandeauIlot {
            var r = RafaleCaptures()
            r.ajouter((1...n).map { "Capture d\u{2019}écran 2026-11-12 à 00.16.\(20 + $0).png" }, a: t0)
            return BandeauIlot(vue: .etagereCapture, jusqua: t0, ligne1: r.titre, ligne2: RafaleCaptures.sousTitre, vignette: vignette)
        }
        ecrire(bureau(hauteur: petitBureau + 30) { ilot(scene { $0.bandeau = captures(1) }) }, "ilot-14e-capture-sur-etagere")
        ecrire(bureau(hauteur: petitBureau + 30) { ilot(scene { $0.bandeau = captures(3) }) }, "ilot-14f-trois-captures-sur-etagere")
        // micro coupé (maquette ilot-apple.html, cinq idées de plus, 5) : seul, pendant une vidéo (la vidéo en bulle), au survol (le
        // Centre, où est le bouton Micro ; pendant une vidéo, la vidéo), rouvert, et la vidéo reprise par un clic sur la bulle
        ecrire(bureau(hauteur: petitBureau) { ilot(scene { $0.microCoupe = true; $0.nomMicro = "Micro MacBook Air" }) }, "ilot-19a-micro-coupe")
        ecrire(bureau(hauteur: petitBureau) { ilot(scene(lecture: videoLongue) { $0.lecturePresente = true; $0.microCoupe = true }) }, "ilot-19b-micro-coupe-video-en-bulle")
        ecrire(bureau(hauteur: geometrie.hauteur + 300) { ilot(scene { $0.microCoupe = true; $0.nomMicro = "Micro MacBook Air"; $0.survole = true }) }, "ilot-19c-micro-coupe-survol")
        ecrire(bureau(hauteur: grandBureau, clair: false) { ilot(scene(lecture: videoLongue) { $0.lecturePresente = true; $0.microCoupe = true; $0.nomMicro = "AirPods Pro de Hugues"; $0.survole = true }) }, "ilot-19d-micro-coupe-survol-airpods")
        ecrire(bureau(hauteur: petitBureau) { ilot(scene { $0.bandeau = BandeauIlot(vue: .microOuvert, jusqua: t0, ligne1: "Micro ouvert", ligne2: "") }) }, "ilot-19e-micro-ouvert")
        // fn sur un micro coupé (11/11 au soir) : la dictée ne part pas, « Rouvrir et dicter » ; ou elle passe par un autre micro, ouvert
        ecrire(bureau(hauteur: petitBureau + 30) { ilot(scene { $0.microCoupe = true; $0.bandeau = BandeauIlot(vue: .microFn, jusqua: t0, ligne1: "Micro coupé", ligne2: "Rien n\u{2019}a été enregistré") }) }, "ilot-19h-fn-micro-coupe")
        let autre = MicroIlot.autreMicro(coupe: "AirPods Pro de Hugues", dictee: "Micro MacBook Air")
        ecrire(bureau(hauteur: petitBureau + 30, clair: false) { ilot(scene { $0.microCoupe = true; $0.bandeau = BandeauIlot(vue: .microFn, jusqua: t0, ligne1: autre.titre, ligne2: autre.sousTitre) }) }, "ilot-19i-fn-autre-micro")
        ecrire(bureau(hauteur: petitBureau) { ilot(scene(lecture: videoLongue) { m in m.lecturePresente = true; m.microCoupe = true; m.donneesChangees(); m.poser(); m.cliquerPastille(); m.poser() }) }, "ilot-19f-video-et-bulle-micro-coupe")
        ecrire(bureau(hauteur: geometrie.hauteur + 300) { ilot(miCourse(scene { $0.microCoupe = true; $0.nomMicro = "Micro MacBook Air" }, 0.16) { $0.survole = true }) }, "ilot-19g-micro-coupe-survol-mi-course")
        // volume et luminosité (maquette ilot-apple.html, cinq idées de plus, 4) : le haut-parleur et la barre dans les ailes (66 pt de
        // chaque côté au plus) ; pendant une vidéo avec un minuteur en bulle (la bulle ne bouge pas) ; son coupé ; une onde, trois ondes ;
        // la luminosité ; et l'arrivée à mi-course depuis la vidéo (la forme s'élargit, la barre glisse de l'ancienne valeur)
        func niveau(_ g: GenreNiveau, _ v: Double, muet: Bool = false, avant: Double? = nil) -> (IlotMoteur) -> Void {
            { $0.montrerNiveau(NiveauIlot(genre: g, valeur: v, muet: muet), avant: avant ?? v) }
        }
        ecrire(bureau(hauteur: petitBureau) { ilot(scene(niveau(.volume, 0.5625, avant: 0.5))) }, "ilot-20a-volume")
        ecrire(bureau(hauteur: petitBureau) { ilot(scene(lecture: videoLongue) { m in m.lecturePresente = true; m.minuteur = minut(10, restant: 372); niveau(.volume, 0.5625)(m) }) }, "ilot-20b-volume-pendant-video-et-minuteur")
        ecrire(bureau(hauteur: petitBureau) { ilot(scene(niveau(.volume, 0.6, muet: true))) }, "ilot-20c-son-coupe")
        ecrire(bureau(hauteur: petitBureau) { ilot(scene(niveau(.volume, 0.125))) }, "ilot-20d-volume-bas")
        ecrire(bureau(hauteur: petitBureau, clair: false) { ilot(scene(niveau(.volume, 1))) }, "ilot-20e-volume-max-sombre")
        ecrire(bureau(hauteur: petitBureau, clair: false) { ilot(scene(niveau(.luminosite, 0.3125, avant: 0.25))) }, "ilot-20f-luminosite")
        ecrire(bureau(hauteur: petitBureau) { ilot(miCourse(scene(lecture: videoLongue) { $0.lecturePresente = true }, 0.22, niveau(.volume, 0.75, avant: 0.6875))) }, "ilot-20g-volume-mi-course")
        // Claude au travail (maquette ilot-apple.html, cinq idées de plus, 1) : l'étoile dans son anneau et « 3 sur 7 » (66 pt de chaque
        // côté au plus), l'étoile seule sans liste, « 12/14 » quand « 12 sur 14 » ne tient pas, le déplié au survol, « Claude attend ta
        // réponse » et « Terminé », Claude en bulle pendant une vidéo, Claude qui attend prend l'îlot (la vidéo en bulle), mi-course
        // Claude Code en carte (maquette ilot-claude-plus.html, étapes 1 à 7) : replié (l'anneau, « 3/7 », le nom de la tâche, le « 2 »),
        // ambre quand une session attend, le Centre (« 2 au travail »), la carte (deux sessions, celle qui attend en haut, défilée), les
        // bandeaux (« second-cerveau attend ta réponse », « Carte Dictées terminée »)
        let tachesDM = ["Lire le moteur de l\u{2019}îlot", "Écrire le modèle des dictées", "Dessiner la liste", "Construire la carte Dictées",
                        "Brancher la recherche", "Copier et coller au clic", "Essai complet"]
        func claude(_ etat: EtatClaude = .travaille, faites: Int = 3, total: Int = 7, projet: String = "dictee-mac", noms: [String]? = nil, titre: String? = "Carte Dictées",
                    question: String? = nil, depuis: Double = 42 * 60, id: String = "rendu") -> SessionClaude {
            let n = noms ?? (total == 7 ? tachesDM : (0..<total).map { "Étape \($0 + 1)" })
            let t = (0..<total).map { i in TacheClaude(id: "\(i + 1)", sujet: n[i % max(1, n.count)], statut: i < faites ? .faite : (i == faites && etat != .termine ? .enCours : (etat == .termine ? .faite : .aFaire))) }
            return SessionClaude(id: id, dossier: "/Users/hugues/" + projet, app: "com.apple.Terminal", etat: etat, taches: t, derniere: t0, titre: titre,
                                 question: question, debut: t0.addingTimeInterval(-depuis), fin: etat == .termine ? t0 : nil)
        }
        let sc = claude(faites: 1, total: 3, projet: "second-cerveau", noms: ["Lire LIS-MOI.md", "Ranger les fiches projets", "Mettre à jour OU-J-EN-SUIS"],
                        titre: "Second cerveau", depuis: 12 * 60, id: "sc")
        let scAttend = claude(.attend, faites: 1, total: 3, projet: "second-cerveau", noms: ["Lire LIS-MOI.md", "Ranger les fiches projets", "Mettre à jour OU-J-EN-SUIS"],
                              titre: "Second cerveau", question: "Je range la fiche Verbe dans projets/ ou dans docs/ ?", depuis: 12 * 60, id: "sc")
        func sessions(_ l: [SessionClaude]) -> (IlotMoteur) -> Void {
            { m in m.sessionsClaude = l; m.claude = l.first { $0.etat != .termine }; m.claudeAuTravail = l.filter { $0.etat != .termine }.count; m.claudeBranche = true }
        }
        let batterie64 = EnergieIlot(pourcent: 64, secteur: false, enCharge: false)
        let airpods78 = AppareilIlot(nom: "AirPods Pro de Hugues", genre: .ecouteurs, gauche: 80, droit: 78, etui: 45)
        let hCarte = geometrie.hauteur + 350
        ecrire(bureau(hauteur: petitBureau) { ilot(scene(sessions([claude()]))) }, "ilot-21a-claude-3-sur-7-nom")
        ecrire(bureau(hauteur: petitBureau) { ilot(scene(sessions([claude(total: 0, titre: nil)]))) }, "ilot-21b-claude-sans-liste")
        ecrire(bureau(hauteur: petitBureau, clair: false) { ilot(scene(sessions([claude(faites: 12, total: 14)]))) }, "ilot-21c-claude-12-sur-14-sombre")
        ecrire(bureau(hauteur: hCarte) { ilot(scene { m in sessions([claude(), sc])(m); m.energie = batterie64; m.ecouteurs = airpods78; m.survole = true }) }, "ilot-21d-claude-survol-le-centre")
        ecrire(bureau(hauteur: petitBureau + 30) { ilot(scene { m in sessions([scAttend, claude()])(m)
            m.bandeau = BandeauIlot(vue: .claudeAttend, jusqua: t0, ligne1: "second-cerveau attend ta réponse",
                                    ligne2: TexteClaude.premiersMots(scAttend.question) ?? "", claude: scAttend) }) }, "ilot-21e-claude-attend-ta-reponse")
        ecrire(bureau(hauteur: petitBureau) { ilot(scene(lecture: videoLongue) { m in m.lecturePresente = true; sessions([scAttend])(m) }) }, "ilot-21f-claude-attend-video-en-bulle")
        let fini = claude(.termine, faites: 7)
        ecrire(bureau(hauteur: petitBureau + 30, clair: false) { ilot(scene { m in
            m.bandeau = BandeauIlot(vue: .claudeTermine, jusqua: t0, ligne1: TexteClaude.fin(fini), ligne2: TexteClaude.ligneFin(fini, a: t0), claude: fini) }) }, "ilot-21g-claude-termine")
        ecrire(bureau(hauteur: petitBureau) { ilot(scene(lecture: videoLongue) { m in m.lecturePresente = true; sessions([claude()])(m) }) }, "ilot-21h-video-et-claude-en-bulle")
        ecrire(bureau(hauteur: hCarte) { ilot(miCourse(scene(sessions([claude()])), 0.16) { $0.survole = true }) }, "ilot-21i-claude-survol-mi-course")
        ecrire(bureau(hauteur: petitBureau) { ilot(scene(sessions([claude(), sc]))) }, "ilot-24a-claude-deux-sessions-badge")
        ecrire(bureau(hauteur: petitBureau) { ilot(scene(sessions([scAttend, claude()]))) }, "ilot-24b-claude-attend-ambre")
        ecrire(bureau(hauteur: hCarte) { ilot(scene { m in sessions([claude(), sc])(m); m.energie = batterie64; m.ecouteurs = airpods78; m.donneesChangees(); m.ouvrirCarteClaude() }) },
               "ilot-24c-carte-claude-deux-sessions")
        ecrire(bureau(hauteur: hCarte) { ilot(scene { m in sessions([scAttend, claude()])(m); m.energie = batterie64; m.ecouteurs = airpods78; m.survole = true }) },
               "ilot-24d-carte-claude-attend-en-haut")
        ecrire(bureau(hauteur: hCarte, clair: false) { ilot(scene { m in sessions([scAttend, claude()])(m); m.energie = batterie64; m.ecouteurs = airpods78; m.survole = true; m.donneesChangees()
            m.defilerCarteClaude(-150) }) }, "ilot-24e-carte-claude-defilee")
        ecrire(bureau(hauteur: hCarte) { ilot(scene { m in sessions([claude(), claude(.termine, faites: 7, projet: "verbe-site", titre: "Page d\u{2019}accueil", depuis: 18 * 60, id: "vs")])(m); m.energie = batterie64; m.donneesChangees(); m.ouvrirCarteClaude() }) }, "ilot-24f-carte-claude-une-finie")
        ecrire(bureau(hauteur: hCarte) { ilot(scene { m in m.claudeBranche = true; m.energie = batterie64; m.donneesChangees(); m.ouvrirCarteClaude() }) }, "ilot-24g-carte-claude-vide")
        ecrire(bureau(hauteur: hCarte) { ilot(miCourse(scene { m in sessions([scAttend, claude()])(m); m.energie = batterie64; m.ecouteurs = airpods78 }, 0.16) { $0.survole = true }) },
               "ilot-24h-carte-claude-ouverture-mi-course")
        // l'étagère (maquette ilot-apple.html, cinq idées de plus, 2) : « Déposez ici » pendant qu'on glisse des fichiers près de l'encoche
        // (vide, puis sous les derniers fichiers rangés, éclairé quand le pointeur est dessus), la ligne de l'accueil, la carte (une et deux
        // rangées, noms longs coupés au milieu, vide), pendant une vidéo, et l'ouverture à mi-course
        func etagere(_ l: [(String, UTType)]) -> [FichierEtagere] {
            l.map { FichierEtagere(id: UUID(), nom: $0.0, url: URL(fileURLWithPath: "/Users/exemple/Desktop/" + $0.0), icone: NSWorkspace.shared.icon(for: $0.1)) }
        }
        let deux = etagere([("Contrat.pdf", .pdf), ("Photo.heic", .heic)])
        let huit = etagere([("Contrat.pdf", .pdf), ("Photo.heic", .heic), ("Rapport-annuel-2026-direction-financière-v3.pdf", .pdf), ("Devis.xlsx", .spreadsheet),
                            ("Notes de réunion.txt", .plainText), ("Maquette.png", .png), ("Présentation client.key", .presentation), ("Archive.zip", .zip)])
        func depot(_ f: [FichierEtagere], survol: Bool) -> (IlotMoteur) -> Void { { m in m.etagereActive = true; m.etagere = f; m.montrerDepot(true); m.depotSurvole = survol } }
        ecrire(bureau(hauteur: petitBureau + 80) { ilot(scene(depot([], survol: false))) }, "ilot-22a-etagere-deposez-ici-vide")
        ecrire(bureau(hauteur: petitBureau + 80) { ilot(scene(depot(deux, survol: true))) }, "ilot-22b-etagere-deposez-ici-survol")
        ecrire(bureau(hauteur: petitBureau + 80, clair: false) { ilot(scene(depot(Array(huit.prefix(5)), survol: false))) }, "ilot-22c-etagere-cinq-fichiers-sombre")
        // l'étagère est passée de l'accueil au Centre (sa case : les fichiers rangés, glissables)
        ecrire(bureau(hauteur: geometrie.hauteur + 300) { ilot(scene { m in m.etagereActive = true; m.etagere = deux; m.survole = true }) }, "ilot-22d-centre-case-etagere")
        ecrire(bureau(hauteur: grandBureau) { ilot(scene { m in m.etagereActive = true; m.etagere = Array(huit.prefix(3)); m.energie = batterie; m.ouvrirEtagere() }) }, "ilot-22e-carte-etagere")
        ecrire(bureau(hauteur: grandBureau + 40, clair: false) { ilot(scene { m in m.etagereActive = true; m.etagere = huit; m.ouvrirEtagere() }) }, "ilot-22f-carte-etagere-deux-rangees")
        ecrire(bureau(hauteur: grandBureau) { ilot(scene { m in m.etagereActive = true; m.etagere = []; m.ouvrirEtagere() }) }, "ilot-22g-carte-etagere-vide")
        ecrire(bureau(hauteur: petitBureau + 80) { ilot(scene(lecture: videoLongue) { m in m.lecturePresente = true; m.minuteur = minut(10, restant: 372); depot(deux, survol: false)(m) }) }, "ilot-22h-etagere-pendant-video")
        ecrire(bureau(hauteur: petitBureau + 80) { ilot(miCourse(scene { m in m.etagereActive = true; m.etagere = deux }, 0.16) { $0.montrerDepot(true) }) }, "ilot-22i-etagere-ouverture-mi-course")
        ecrire(bureau(hauteur: grandBureau + 70) { ilot(scene(lecture: videoLongue) { m in m.etagereActive = true; m.etagere = deux; m.lecturePresente = true
            m.donneesChangees(); m.appuiLong(minuteurActif: true) }) }, "ilot-22j-lecture-rangee-et-etagere")
        // l'étagère plus rapide (maquette ilot-etagere-rapide.html, validée) : l'appel dès que le glisser commence, les deux zones (Étagère
        // éclairée, AirDrop éclairée, « Rangé »), la pile replié dans l'aile gauche, l'envoi AirDrop (en cours, envoyé, annulé), le Centre
        // avec les fichiers en haut (et « Tout »), « 3 fichiers partis dans Mail · Remettre », la carte avec une capture « Nouveau » et
        // l'interrupteur, l'ouverture à mi-course
        let trois = etagere([("Contrat.pdf", .pdf), ("Photo-chantier.heic", .heic), ("Devis-cuisine.pdf", .pdf)])
        let cinq = trois + etagere([("Budget-2026.xlsx", .spreadsheet), ("Lettre-banque.docx", .plainText)])
        func zones(_ f: [FichierEtagere], _ z: ZoneDepotEtagere?) -> (IlotMoteur) -> Void {
            { m in m.etagereActive = true; m.etagere = f; m.montrerAppel(true); m.montrerDepot(true); m.depotSurvole = z != nil; m.depotZone = z }
        }
        ecrire(bureau(hauteur: petitBureau + 40) { ilot(scene { m in m.etagereActive = true; m.etagere = Array(trois.prefix(2)); m.montrerAppel(true) }) }, "ilot-24a-etagere-glisse-ici")
        ecrire(bureau(hauteur: petitBureau + 140) { ilot(scene(zones(Array(trois.prefix(2)), .etagere))) }, "ilot-24b-etagere-zones-etagere-eclairee")
        ecrire(bureau(hauteur: petitBureau + 140, clair: false) { ilot(scene(zones(Array(trois.prefix(2)), .airdrop))) }, "ilot-24c-etagere-zones-airdrop-eclairee")
        ecrire(bureau(hauteur: petitBureau + 140) { ilot(scene { m in zones(trois, .etagere)(m); m.depotTermine(apres: 60) }) }, "ilot-24d-etagere-range")
        ecrire(bureau(hauteur: petitBureau) { ilot(scene { m in m.etagereActive = true; m.etagere = trois }) }, "ilot-24e-etagere-pile-repliee")
        ecrire(bureau(hauteur: petitBureau, clair: false) { ilot(scene { m in m.etagereActive = true; m.etagere = huit + Array(trois.prefix(2)) }) }, "ilot-24f-etagere-pile-dix-sombre")
        let plan = NSWorkspace.shared.icon(for: .jpeg)
        func envoi(_ e: EnvoiEtagere.Etat, surEtagere: Bool = false) -> (IlotMoteur) -> Void {
            { m in m.etagereActive = true; m.etagere = trois
                m.bandeau = BandeauIlot(vue: .etagereEnvoi, jusqua: t0, ligne1: "", ligne2: "", envoi: EnvoiEtagere(etat: e, noms: ["Plan-salon.jpg"], icone: plan, surEtagere: surEtagere)) }
        }
        ecrire(bureau(hauteur: petitBureau + 30) { ilot(scene(envoi(.enCours))) }, "ilot-24g-etagere-airdrop-envoi")
        // jamais « Envoyé » : aucune interface ne confirme la fin du transfert (11/11 au soir, Hugues avait annulé, l'îlot disait « Envoyé »)
        ecrire(bureau(hauteur: petitBureau + 30) { ilot(scene(envoi(.lance))) }, "ilot-24h-etagere-airdrop-lance")
        ecrire(bureau(hauteur: petitBureau + 30, clair: false) { ilot(scene(envoi(.lance, surEtagere: true))) }, "ilot-24s-etagere-airdrop-lance-reste-sur-etagere")
        ecrire(bureau(hauteur: petitBureau + 30, clair: false) { ilot(scene(envoi(.annule))) }, "ilot-24i-etagere-airdrop-annule")
        ecrire(bureau(hauteur: geometrie.hauteur + 345) { ilot(scene { m in m.etagereActive = true; m.etagere = trois; m.energie = batterie; m.survole = true }) }, "ilot-24j-centre-fichiers-en-haut")
        ecrire(bureau(hauteur: geometrie.hauteur + 345, clair: false) { ilot(scene(lecture: videoLongue) { m in m.etagereActive = true; m.etagere = cinq; m.lecturePresente = true
            m.donneesChangees(); m.allerA(.centre) }) }, "ilot-24k-centre-fichiers-en-haut-depuis-video")
        // l'en-tête le plus chargé (« ‹ Vidéo », « Outils › », « Dictées », « Modifier ») épinglé : l'épingle seule, jamais « Reste ouv… »
        ecrire(bureau(hauteur: geometrie.hauteur + 345) { ilot(scene(lecture: videoLongue) { m in m.etagereActive = true; m.etagere = cinq; m.lecturePresente = true
            m.donneesChangees(); m.allerA(.centre); m.epingle = true }) }, "ilot-24r-centre-en-tete-charge-epingle")
        ecrire(bureau(hauteur: petitBureau + 30) { ilot(scene { m in m.etagereActive = true
            m.bandeau = BandeauIlot(vue: .etagerePartis, jusqua: t0.addingTimeInterval(3.6), ligne1: EtagereIlot.partis(3, app: "Mail"), ligne2: "Ils ont quitté l\u{2019}étagère",
                                    partis: PartisEtagere(nombre: 3, app: "Mail", icones: trois.suffix(2).reversed().map(\.icone), duree: 5)) }) }, "ilot-24l-etagere-partis-remettre")
        // une capture glissée vers une app au nom long : « Remettre » et la croix tiennent sans rien couper
        ecrire(bureau(hauteur: petitBureau + 30, clair: false) { ilot(scene { m in m.etagereActive = true
            m.bandeau = BandeauIlot(vue: .etagerePartis, jusqua: t0.addingTimeInterval(4.6), ligne1: EtagereIlot.partis(1, app: "Google Chrome"), ligne2: "Il a quitté l\u{2019}étagère",
                                    partis: PartisEtagere(nombre: 1, app: "Google Chrome", icones: [trois[0].icone], duree: 5)) }) }, "ilot-24t-etagere-parti-croix")
        var capture = etagere([("Capture d\u{2019}écran 2026-11-11 à 14.32.10.png", .png)])
        capture[0].nouveau = true
        // l'option allumée : la ligne « Vignette des captures en haut » s'ajoute dessous (éteinte ; puis allumée, au premier clic, qui explique)
        ecrire(bureau(hauteur: grandBureau + 66) { ilot(scene { m in m.etagereActive = true; m.etagere = Array(trois.prefix(1)) + capture; m.capturesActives = true; m.energie = batterie; m.ouvrirEtagere() }) }, "ilot-24m-carte-capture-nouveau")
        ecrire(bureau(hauteur: grandBureau + 66) { ilot(scene { m in m.etagereActive = true; m.etagere = Array(trois.prefix(1)) + capture; m.capturesActives = true
            m.vignetteEnHaut = true; m.vignetteExpliquee = true; m.energie = batterie; m.ouvrirEtagere() }) }, "ilot-24s-carte-vignette-en-haut")
        ecrire(bureau(hauteur: grandBureau + 20, clair: false) { ilot(scene { m in m.etagereActive = true; m.etagere = trois; m.capturesRefusees = true; m.ouvrirEtagere() }) }, "ilot-24n-carte-captures-acces-refuse")
        ecrire(bureau(hauteur: grandBureau + 20) { ilot(scene { m in m.etagereActive = true; m.etagere = trois; m.capturesIntrouvable = true; m.ouvrirEtagere() }) }, "ilot-24q-carte-captures-dossier-introuvable")
        ecrire(bureau(hauteur: petitBureau + 140) { ilot(miCourse(scene { m in m.etagereActive = true; m.etagere = trois; m.montrerAppel(true) }, 0.16) { $0.montrerDepot(true) }) }, "ilot-24o-etagere-appel-vers-zones-mi-course")
        ecrire(bureau(hauteur: petitBureau + 40) { ilot(miCourse(scene { m in m.etagereActive = true; m.etagere = trois }, 0.14) { $0.montrerAppel(true) }) }, "ilot-24p-etagere-pile-vers-appel-mi-course")
        // le Centre (maquette ilot-centre.html, mêmes étapes) : la bulle « Nouveau », la lecture et son bouton « Centre », le Centre et
        // ses boutons (micro coupé et « Reste ouvert », l'étagère qui reçoit un fichier, Téléchargements allumé, Claude prêt), puis d'autres
        // états (îlot vide, minuteur qui tourne, Claude au travail, l'accueil sous le Centre, la carte Étagère, le passage à mi-course)
        let hCentre = geometrie.hauteur + 350
        let airpodsPro = AppareilIlot(nom: "AirPods Pro de Hugues", genre: .ecouteurs, gauche: 80, droit: 78, etui: 45)
        func centre(_ config: @escaping (IlotMoteur) -> Void = { _ in }) -> (IlotMoteur) -> Void {
            { m in m.lecturePresente = true; m.energie = EnergieIlot(pourcent: 64, secteur: false, enCharge: false); m.ecouteurs = airpodsPro
                m.choixMicro = ("AirPods Pro de Hugues", true); m.etagereActive = true; m.aideCentre = true
                m.donneesChangees(); m.survole = true; m.donneesChangees(); m.allerA(.centre); config(m); m.donneesChangees() }
        }
        ecrire(bureau(hauteur: petitBureau + 50) { ilot(scene(lecture: videoLongue) { m in m.lecturePresente = true; m.donneesChangees(); m.montrerBulle() }) }, "ilot-23a-centre-1-bulle-nouveau")
        ecrire(bureau(hauteur: hCentre) { ilot(scene(lecture: videoLongue) { m in m.lecturePresente = true; m.energie = EnergieIlot(pourcent: 64, secteur: false, enCharge: false)
            m.ecouteurs = airpodsPro; m.aideCentre = true; m.donneesChangees(); m.survole = true; m.donneesChangees() }) }, "ilot-23b-centre-2-lecture-bouton-centre")
        ecrire(bureau(hauteur: hCentre) { ilot(scene(lecture: videoLongue, centre())) }, "ilot-23c-centre-3-le-centre")
        ecrire(bureau(hauteur: hCentre) { ilot(scene(lecture: videoLongue, centre { m in m.microCoupe = true; m.epinglerLeCentre() })) }, "ilot-23d-centre-4-micro-coupe-reste-ouvert")
        ecrire(bureau(hauteur: hCentre) { ilot(scene(lecture: videoLongue, centre { m in m.microCoupe = true; m.epinglerLeCentre(); m.montrerDepot(true); m.depotSurvole = true })) }, "ilot-23e-centre-5-etagere-lache-ici")
        ecrire(bureau(hauteur: hCentre) { ilot(scene(lecture: videoLongue, centre { m in m.microCoupe = true; m.epinglerLeCentre(); m.etagere = Array(deux.prefix(1)) })) }, "ilot-23f-centre-5-etagere-un-fichier")
        ecrire(bureau(hauteur: hCentre) { ilot(scene(lecture: videoLongue, centre { m in m.microCoupe = true; m.epinglerLeCentre(); m.etagere = Array(deux.prefix(1)); m.telechargementsActifs = true })) }, "ilot-23g-centre-7-telechargements-allume")
        ecrire(bureau(hauteur: hCentre) { ilot(scene(lecture: videoLongue, centre { m in m.microCoupe = true; m.epinglerLeCentre(); m.etagere = Array(deux.prefix(1)); m.telechargementsActifs = true; m.claudeBranche = true })) }, "ilot-23h-centre-8-claude-pret")
        ecrire(bureau(hauteur: hCentre, clair: false) { ilot(scene { m in m.etagereActive = true; m.survole = true }) }, "ilot-23i-centre-ilot-vide-sombre")
        ecrire(bureau(hauteur: hCentre, clair: false) { ilot(scene(lecture: musique, centre { m in m.minuteur = minut(10, restant: 392); m.etagere = huit; m.epinglerLeCentre() })) }, "ilot-23j-centre-minuteur-et-cinq-fichiers")
        ecrire(bureau(hauteur: hCentre) { ilot(scene(lecture: videoLongue, centre { m in m.choixMicro = nil; m.claude = claude(); m.epinglerLeCentre() })) }, "ilot-23k-centre-claude-au-travail-sans-airpods")
        ecrire(bureau(hauteur: hCentre) { ilot(scene(lecture: videoLongue, centre { m in m.derniereDictee = ("Je te rappelle demain pour confirmer le créneau avec l\u{2019}équipe", "3 min"); m.rendezVousSuivant = rdv; m.allerA(.accueil) })) }, "ilot-23l-centre-accueil-dessous")
        ecrire(bureau(hauteur: hCentre) { ilot(scene(lecture: videoLongue, centre { m in m.etagere = deux; m.ouvrirEtagere() })) }, "ilot-23m-centre-carte-etagere-retour")
        // le chemin vers le Centre depuis TOUT déplié (relecture) : le minuteur (avec l'aide, la première fois), Claude quand le micro est
        // coupé (le survol ouvre Claude, la 2e activité ; le micro rouge est dans le bouton)
        ecrire(bureau(hauteur: piedBureau) { ilot(scene { m in m.minuteur = minut(25, restant: 1380); m.energie = EnergieIlot(pourcent: 64, secteur: false, enCharge: false)
            m.ecouteurs = airpodsPro; m.aideCentre = true; m.donneesChangees(); m.survole = true; m.donneesChangees() }) }, "ilot-23q-centre-chemin-depuis-le-minuteur")
        ecrire(bureau(hauteur: piedBureau, clair: false) { ilot(scene { m in m.microCoupe = true; m.nomMicro = "Micro MacBook Air"; m.claude = claude()
            m.donneesChangees(); m.survole = true; m.donneesChangees() }) }, "ilot-23r-centre-chemin-depuis-claude-micro-coupe")
        // les Dictées (maquette ilot-centre.html, étapes 2, 10, 11, 12) : « Centre » et « Dictées » au pied de la vidéo, la carte, la
        // recherche « devis » (champ actif, mots surlignés), « Copié » et « Coller » au survol, une ligne dépliée, la liste défilée,
        // « Aucun résultat », le fond sombre de Hugues
        func carteDictees(_ config: @escaping (IlotMoteur) -> Void = { _ in }) -> (IlotMoteur) -> Void {
            centre { m in m.allerA(.dictees); config(m); m.donneesChangees() }
        }
        let d1 = dicteesRendu[0].id, d2 = dicteesRendu[1].id
        ecrire(bureau(hauteur: hCentre) { ilot(scene(lecture: videoLongue) { m in m.lecturePresente = true; m.energie = EnergieIlot(pourcent: 64, secteur: false, enCharge: false)
            m.ecouteurs = airpodsPro; m.aideCentre = true; m.donneesChangees(); m.survole = true; m.donneesChangees() }) }, "ilot-24a-dictees-2-pied-centre-et-dictees")
        ecrire(bureau(hauteur: hCentre) { ilot(scene(lecture: videoLongue, carteDictees())) }, "ilot-24b-dictees-10-la-carte")
        ecrire(bureau(hauteur: hCentre) { ilot(scene(lecture: videoLongue, carteDictees { m in m.dictees.requete = "devis"; m.dictees.rechercheActive = true })) }, "ilot-24c-dictees-11-chercher-devis")
        ecrire(bureau(hauteur: hCentre) { ilot(scene(lecture: videoLongue, carteDictees { m in m.dictees.requete = "devis"; m.dictees.survol = d1; m.dictees.marquerCopiee(d1) })) }, "ilot-24d-dictees-12-copie-et-coller")
        ecrire(bureau(hauteur: hCentre) { ilot(scene(lecture: videoLongue, carteDictees { m in m.dictees.deplie = d1 })) }, "ilot-24e-dictees-ligne-depliee")
        ecrire(bureau(hauteur: hCentre) { ilot(scene(lecture: videoLongue, carteDictees { m in m.dictees.deplie = d1; m.dictees.survol = d1; m.dictees.marquerCopiee(d1) })) }, "ilot-24i-dictees-depliee-copiee")
        ecrire(bureau(hauteur: hCentre) { ilot(scene(lecture: videoLongue, carteDictees { m in m.dictees.survol = d2; m.dictees.decalage = 70 })) }, "ilot-24f-dictees-liste-defilee-survol")
        ecrire(bureau(hauteur: hCentre) { ilot(scene(lecture: videoLongue, carteDictees { m in m.dictees.requete = "facture plombier" })) }, "ilot-24g-dictees-aucun-resultat")
        ecrire(bureau(hauteur: hCentre, clair: false) { ilot(scene { m in m.etagereActive = true; m.survole = true; m.donneesChangees(); m.allerA(.dictees) }) }, "ilot-24h-dictees-ilot-vide-sombre")
        // « Modifier » (maquette, étape 9) : le Centre avec Rappel ajouté (cinq ronds) ; « Modifier » lui-même (inclinaison figée : dans
        // l'app, ils tremblent), « Ajouter : + Rappel + Dernière dictée », puis Rappel ajouté ; « Modifier » quand les ajouts ne tiennent
        // pas tous (« +3 › ») ; enfin les autorisations (« Un instant… », accès refusé et sa ligne d'avis)
        let maquette = DispositionCentre([.micro, .dictee, .telechargements, .claude, .rappel, .minuteur, .etagere, .reunion])
        let hReunion = hCentre
        func etape8(_ m: IlotMoteur) { m.microCoupe = true; m.etagere = Array(deux.prefix(1)); m.telechargementsActifs = true; m.claudeBranche = true }
        ecrire(bureau(hauteur: hReunion) { ilot(scene(lecture: videoLongue, centre { m in m.disposition = maquette; etape8(m); m.epinglerLeCentre() })) }, "ilot-23oa-centre-cinq-ronds-et-reunion")
        ecrire(bureau(hauteur: hReunion) { ilot(scene(lecture: videoLongue, centre { m in m.disposition = DispositionCentre(); etape8(m)
            m.commencerEditionCentre() })) }, "ilot-23ob-centre-9-modifier")
        ecrire(bureau(hauteur: hReunion) { ilot(scene(lecture: videoLongue, centre { m in m.disposition = maquette; etape8(m); m.commencerEditionCentre() })) }, "ilot-23oc-centre-9-modifier-rappel-ajoute")
        ecrire(bureau(hauteur: hCentre) { ilot(scene(lecture: videoLongue, centre { m in m.disposition = DispositionCentre([.micro, .claude, .minuteur, .etagere]); etape8(m)
            m.commencerEditionCentre() })) }, "ilot-23od-centre-modifier-ajouts-qui-ne-tiennent-pas")
        ecrire(bureau(hauteur: hCentre) { ilot(scene(lecture: videoLongue, centre { m in m.disposition = DispositionCentre([.claude, .etagere]); etape8(m); m.commencerEditionCentre() })) },
               "ilot-23oe-centre-modifier-presque-vide")
        ecrire(bureau(hauteur: hCentre) { ilot(scene(lecture: videoLongue, centre { m in m.microCoupe = true; m.epinglerLeCentre(); m.etagere = Array(deux.prefix(1))
            m.telechargementsAttente = true; m.telechargementsActifs = true })) }, "ilot-23pa-centre-6-telechargements-un-instant")
        ecrire(bureau(hauteur: hCentre) { ilot(scene(lecture: videoLongue, centre { m in m.microCoupe = true; m.epinglerLeCentre(); m.etagere = Array(deux.prefix(1))
            m.avisCentre = .telechargementsRefuses })) }, "ilot-23pb-centre-telechargements-refuse")
        ecrire(bureau(hauteur: hCentre, clair: false) { ilot(scene(lecture: videoLongue, centre { m in m.epinglerLeCentre(); m.avisCentre = .claudeImpossible(ecriture: false) })) },
               "ilot-23pc-centre-claude-illisible-sombre")
        for (t, nom) in [(0.08, "a"), (0.18, "b")] {
            ecrire(bureau(hauteur: hCentre) { ilot(miCourse(scene(lecture: videoLongue) { m in m.lecturePresente = true; m.energie = EnergieIlot(pourcent: 64, secteur: false, enCharge: false); m.ecouteurs = airpodsPro
                m.donneesChangees(); m.survole = true; m.donneesChangees() }, t) { $0.allerA(.centre) }) }, "ilot-23n\(nom)-centre-passage-\(Int(t * 1000))ms")
        }
        // les Outils, 2e page du Centre (maquette ilot-claude-plus.html, étapes 8 à 14) : la page (« Outils › » dans l'en-tête du Centre,
        // 2e point), Garder éveillé 1 h, le presse-papiers (« Copié », « Coller » au survol), Reformuler (« Verbe réécrit… », le résultat),
        // Note rapide (la note qui vient d'arriver, « Dans Notes »), « Modifier » sur la page Outils, les cartes vides, un passage à mi-course
        func outils(_ config: @escaping (IlotMoteur) -> Void = { _ in }) -> (IlotMoteur) -> Void {
            { m in centre()(m); m.allerA(.outils); config(m); m.donneesChangees() }
        }
        func copie(_ g: GenreCopie, _ titre: String, _ detail: String? = nil, _ style: CopieVue.Style, _ icone: NSImage? = nil, il minutes: Double) -> CopieVue {
            CopieVue(element: ElementCopie(genre: g, date: t0.addingTimeInterval(-minutes * 60), empreinte: titre), titre: titre, detail: detail, style: style, icone: icone)
        }
        let cinqCopies = [
            copie(.texte("4 200 € posé"), "4\u{202F}200\u{202F}€ posé, plan de travail en chêne compris", nil, .texte, il: 1),
            copie(.image(largeur: 1280, hauteur: 800), "Image", LecturePressePapiers.dimensions(1280, 800), .nom, image(ArtVideo(), cote: 120, hauteur: 75), il: 6),
            copie(.fichiers(["Devis-cuisine.pdf"]), "Devis-cuisine.pdf", "212 Ko", .nom, NSWorkspace.shared.icon(for: .pdf), il: 14),
            copie(.texte("git push origin main"), "git push origin main", nil, .commande, il: 31),
            copie(.texte("Bonjour"), "Bonjour Madame Martin, je vous confirme le rendez-vous de mardi à 10 h.", nil, .texte, il: 62),
        ]
        let dicteeMail = "OK pour le devis de la cuisine : 4\u{202F}200\u{202F}€ posé, plan de travail en chêne compris. Je te l\u{2019}envoie ce soir avec les plans et les photos du chantier."
        func reformulation(_ phase: EtatReformulation.Phase, style: StyleReformulation? = .pro) -> EtatReformulation {
            var r = EtatReformulation(); r.texte = dicteeMail; r.etiquette = "Dernière dictée \u{00B7} Mail \u{00B7} 14:31"; r.style = style; r.phase = phase; return r
        }
        let notesExemple = [NoteRapide(texte: "Rappeler le plombier jeudi pour le devis de la salle de bain", date: t0),
                            NoteRapide(texte: "Acheter des ampoules pour le salon", date: t0.addingTimeInterval(-3.5 * 3600)),
                            NoteRapide(texte: "Idée : un mode nuit pour l\u{2019}îlot, plus sombre après 22 h", date: t0.addingTimeInterval(-26 * 3600), versNotes: true),
                            NoteRapide(texte: "Rappeler la banque pour le prêt", date: t0.addingTimeInterval(-30 * 3600))]
        ecrire(bureau(hauteur: hCentre) { ilot(scene(lecture: videoLongue, outils())) }, "ilot-25a-outils-8-la-page")
        ecrire(bureau(hauteur: hCentre) { ilot(scene(lecture: videoLongue, outils { m in m.epinglerLeCentre(); m.eveil = EveilIlot(duree: .uneHeure, depuis: t0.addingTimeInterval(-8 * 60)); m.panneauEveil = true })) },
               "ilot-25b-outils-9-garder-eveille-1h")
        ecrire(bureau(hauteur: hCentre) { ilot(scene(lecture: videoLongue, outils { m in m.copies = cinqCopies; m.ouvrirOutil(.outilPressePapiers); m.copieFaite = (cinqCopies[1].id, "Copié"); m.survolCopie = cinqCopies[2].id })) },
               "ilot-25c-outils-10-presse-papiers")
        ecrire(bureau(hauteur: hCentre) { ilot(scene(lecture: videoLongue, outils { m in m.reformulation = reformulation(.fait("Bonjour, je vous confirme le devis de la cuisine : 4\u{202F}200\u{202F}€, pose et plan de travail en chêne compris. Je vous envoie ce soir les plans et les photos du chantier. Cordialement."))
            m.ouvrirOutil(.outilReformuler) })) }, "ilot-25d-outils-11-reformuler-plus-pro")
        ecrire(bureau(hauteur: hCentre, clair: false) { ilot(scene(lecture: videoLongue, outils { m in m.reformulation = reformulation(.calcul); m.ouvrirOutil(.outilReformuler) })) },
               "ilot-25e-outils-reformuler-calcul-sombre")
        ecrire(bureau(hauteur: hCentre) { ilot(scene(lecture: videoLongue, outils { m in m.notes = notesExemple; m.noteNeuve = notesExemple[0].id; m.envoisNotes = [notesExemple[0].id: .fait]
            m.ouvrirOutil(.outilNote) })) }, "ilot-25f-outils-14-note-rapide")
        ecrire(bureau(hauteur: hCentre) { ilot(scene(lecture: videoLongue, outils { m in m.dispositionOutils.retirer(.reformuler); m.commencerEditionCentre() })) },
               "ilot-25g-outils-modifier")
        ecrire(bureau(hauteur: hCentre, clair: false) { ilot(scene(lecture: videoLongue, outils { m in m.ouvrirOutil(.outilNote) })) }, "ilot-25h-outils-note-rapide-vide-sombre")
        ecrire(bureau(hauteur: hCentre) { ilot(scene(lecture: videoLongue, outils { m in m.ouvrirOutil(.outilPressePapiers) })) }, "ilot-25i-outils-presse-papiers-vide")
        ecrire(bureau(hauteur: hCentre) { ilot(scene(lecture: videoLongue, outils { m in m.reformulation.source = .selection; m.reformulation.etiquette = "Texte choisi"; m.ouvrirOutil(.outilReformuler) })) },
               "ilot-25j-outils-reformuler-rien-de-choisi")
        ecrire(bureau(hauteur: hCentre) { ilot(miCourse(scene(lecture: videoLongue, centre()), 0.2) { $0.allerA(.outils) }) }, "ilot-25k-outils-passage-200ms")
        // Second Brain (maquette ilot-second-cerveau.html) : un FAUX fichier d'état écrit dans un dossier temporaire, lu par le vrai code de
        // lecture (FichierSecondCerveau.lire, 64 Ko au plus) ; jamais le vrai ~/.config, aucune donnée de Hugues dans ces images
        func fauxFichierSecondBrain(_ json: String) -> SecondCerveauIlot? {
            let dossierTmp = FileManager.default.temporaryDirectory.appendingPathComponent("verbe-rendu-second-brain-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
            try? FileManager.default.createDirectory(at: dossierTmp, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dossierTmp) }
            let f = dossierTmp.appendingPathComponent(FichierSecondCerveau.nom)
            try? json.data(using: .utf8)?.write(to: f)
            return SecondCerveauIlot.decoder(FichierSecondCerveau.lire(f))
        }
        // les dates du contrat final : AAAA-MM-JJ pour `echeance` et `depuis`, une ISO avec fuseau pour `heure`
        func jourSB(_ jours: Int) -> String {
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
            return f.string(from: cal.date(byAdding: .day, value: jours, to: t0)!)
        }
        func heureSB(_ h: Int, _ min: Int) -> String {
            ISO8601DateFormatter().string(from: cal.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: h, minute: min))!)
        }
        func jsonSB(maj: Date, messages: String, taches: String, relances: String, nouveautes: Int, aToi: Int, aRelancer: Int) -> String {
            "{ \"version\": 1, \"maj\": \"\(ISO8601DateFormatter().string(from: maj))\", \"resume\": \"Pierre t'a écrit · 3 choses demandées\", \"compteurs\": { \"nouveautes\": \(nouveautes), \"aToi\": \(aToi), \"aRelancer\": \(aRelancer) }, \"messages\": [\(messages)], \"taches\": [\(taches)], \"relances\": [\(relances)], \"lien\": \"secondbrain://aujourdhui\" }"
        }
        let sbMaquette = fauxFichierSecondBrain(jsonSB(maj: t0.addingTimeInterval(-120),
            messages: "{\"id\":\"pierre\",\"nom\":\"Pierre\",\"texte\":\"Pour vendredi : le plan, les chiffres et la liste des invités\",\"heure\":\"\(heureSB(9, 12))\"},{\"id\":\"julie\",\"nom\":\"Julie\",\"texte\":\"Merci pour hier ! Je t'envoie les photos ce soir\",\"heure\":\"\(heureSB(8, 47))\"}",
            taches: "{\"id\":\"t1\",\"texte\":\"Répondre aux 3 questions de Pierre\",\"echeance\":\"\(jourSB(4))\"},{\"id\":\"t2\",\"texte\":\"Relire le bail du local\",\"echeance\":\"\(jourSB(6))\"},{\"id\":\"t3\",\"texte\":\"Réserver le train pour Lyon\",\"echeance\":\"\(jourSB(10))\"}",
            relances: "{\"id\":\"ladislas\",\"nom\":\"Ladislas\",\"sujet\":\"le partenariat\",\"depuis\":\"\(jourSB(-40))\"},{\"id\":\"marc\",\"nom\":\"Marc\",\"sujet\":\"le devis du site\",\"depuis\":\"\(jourSB(-22))\"}",
            nouveautes: 2, aToi: 14, aRelancer: 2))
        // trop de lignes (3 + 3 + 3 devient 3 + 2 + 2), des textes beaucoup trop longs, un nom très long
        let sbChargee = fauxFichierSecondBrain(jsonSB(maj: t0.addingTimeInterval(-3 * 3600),
            messages: (1...4).map { "{\"id\":\"m\($0)\",\"nom\":\"\(["Alexandre-Emmanuel de la Tour", "Camille", "Inès", "Sam"][$0 - 1])\",\"texte\":\"On décale le point de jeudi ? Je ne suis pas sûr de pouvoir être là avant dix-sept heures, dis-moi ce qui t'arrange pour la semaine prochaine\",\"heure\":\"\(heureSB(10 + $0, 40 + $0))\"}" }.joined(separator: ","),
            taches: (1...4).map { "{\"id\":\"t\($0)\",\"texte\":\"Relire et valider le contrat de prestation avec toutes les annexes techniques et financières (\($0))\",\"echeance\":\"\(jourSB($0 * 2))\"}" }.joined(separator: ","),
            relances: (1...4).map { "{\"id\":\"r\($0)\",\"nom\":\"Relance \($0)\",\"sujet\":\"un sujet vraiment très long qui ne tient pas sur une seule ligne de la carte\",\"depuis\":\"\(jourSB(-$0 * 20))\"}" }.joined(separator: ","),
            nouveautes: 12, aToi: 31, aRelancer: 4))
        let sbVideHier = fauxFichierSecondBrain(jsonSB(maj: t0.addingTimeInterval(-30 * 3600), messages: "", taches: "", relances: "", nouveautes: 0, aToi: 0, aRelancer: 0))
        let sbSeulementDesRelances = fauxFichierSecondBrain(jsonSB(maj: t0.addingTimeInterval(-45 * 60), messages: "", taches: "",
            relances: "{\"id\":\"marc\",\"nom\":\"Marc\",\"sujet\":\"le devis du site\",\"depuis\":\"\(jourSB(-70))\"}", nouveautes: 0, aToi: 0, aRelancer: 1))
        let avecSB = DispositionCentre([.micro, .dictee, .telechargements, .claude, .secondBrain, .minuteur, .etagere, .reunion])
        func carteSB(_ f: SecondCerveauIlot?) -> (IlotMoteur) -> Void {
            { m in centre()(m); m.secondBrain = f; m.disposition = avecSB; m.donneesChangees(); m.ouvrirSecondBrain(); m.donneesChangees() }
        }
        ecrire(bureau(hauteur: hCentre) { ilot(scene(lecture: videoLongue, centre { m in m.secondBrain = sbMaquette; m.disposition = avecSB; m.epinglerLeCentre() })) }, "ilot-27a-second-brain-le-rond-dans-le-centre")
        ecrire(bureau(hauteur: hCentre) { ilot(scene(lecture: videoLongue, carteSB(sbMaquette))) }, "ilot-27b-second-brain-carte")
        ecrire(bureau(hauteur: hCentre, clair: false) { ilot(scene(lecture: videoLongue, carteSB(sbChargee))) }, "ilot-27c-second-brain-carte-chargee-sombre")
        ecrire(bureau(hauteur: hCentre) { ilot(scene(lecture: videoLongue, carteSB(sbVideHier))) }, "ilot-27d-second-brain-carte-rien-de-neuf-hier")
        ecrire(bureau(hauteur: hCentre) { ilot(scene(lecture: videoLongue, carteSB(sbSeulementDesRelances))) }, "ilot-27e-second-brain-carte-une-seule-ligne")
        ecrire(bureau(hauteur: hCentre) { ilot(miCourse(scene(lecture: videoLongue, centre { m in m.secondBrain = sbMaquette; m.disposition = avecSB }), 0.2) { $0.ouvrirSecondBrain() }) }, "ilot-27f-second-brain-passage-200ms")
        // l'aide au survol (11/11 au soir, « pas clair ») : une phrase sous le bouton ou la case survolés, ou au-dessus quand elle ne
        // tiendrait pas dessous ; calée dans le contenu au bord (Micro, à gauche)
        ecrire(bureau(hauteur: hCentre) { ilot(scene(lecture: videoLongue, centre { m in m.epinglerLeCentre(); m.bulleAide = .telechargements })) }, "ilot-26a-aide-centre-telechargements")
        ecrire(bureau(hauteur: hCentre, clair: false) { ilot(scene(lecture: videoLongue, centre { m in m.epinglerLeCentre(); m.bulleAide = .micro })) }, "ilot-26b-aide-centre-micro-au-bord")
        ecrire(bureau(hauteur: hCentre) { ilot(scene(lecture: videoLongue, centre { m in m.epinglerLeCentre(); m.etagere = Array(deux.prefix(2)); m.bulleAide = .etagere })) }, "ilot-26c-aide-centre-etagere-en-haut")
        ecrire(bureau(hauteur: hCentre) { ilot(scene(lecture: videoLongue, centre { m in m.epinglerLeCentre(); m.bulleAide = .minuteur })) }, "ilot-26d-aide-centre-case-minuteur")
        ecrire(bureau(hauteur: hCentre) { ilot(scene(lecture: videoLongue, outils { m in m.epinglerLeCentre(); m.bulleAide = .eveil })) }, "ilot-26e-aide-outils-garder-eveille")
        ecrire(bureau(hauteur: hCentre, clair: false) { ilot(scene(lecture: videoLongue, outils { m in m.epinglerLeCentre(); m.bulleAide = .pressePapiers })) }, "ilot-26f-aide-outils-presse-papiers-sombre")
        ecrire(bureau(hauteur: hCentre) { ilot(scene(lecture: videoLongue, outils { m in m.epinglerLeCentre(); m.bulleAide = .noteRapide })) }, "ilot-26g-aide-outils-dicter-une-note")
        // sans image du système ni miniature : l'icône de l'app en petit sur fond sombre, teinte tirée de l'icône
        func sansImage(_ c: Contenu, joue: Bool = true) -> LectureModele {
            let m = modele(c, joue: joue)
            m.image = nil
            m.teinte = chrome.map { LectureControleur.teinte(de: $0) } ?? .neutre
            return m
        }
        ecrire(bureau(hauteur: grandBureau) { ilot(scene(lecture: sansImage(contenus[1])) { $0.lecturePresente = true; $0.survole = true }) }, "ilot-1h-etendu-sans-image")
        ecrire(bureau(hauteur: petitBureau) { ilot(scene(lecture: sansImage(contenus[1])) { $0.lecturePresente = true }) }, "ilot-1i-compact-sans-image")
        // ni image ni icône d'app (cas rare) : le pictogramme à l'échelle de la case
        let sansRien = sansImage(contenus[2]); sansRien.iconeApp = nil
        ecrire(bureau(hauteur: grandBureau) { ilot(scene(lecture: sansRien) { $0.lecturePresente = true; $0.survole = true }) }, "ilot-1h2-etendu-sans-image-ni-icone")
        // 2e rappel qui sonne alors que la cloche d'un rappel sans réponse est dans l'aile ; pastille d'un rappel survolée (son titre)
        ecrire(bureau(hauteur: petitBureau) { ilot(scene(lecture: musique) { m in
            m.rendezVous = rdv; m.rendezVousProche = true; m.rappelsSonnes = [rappelExemple]; m.lecturePresente = true
            m.donneesChangees(); m.poser(); m.pastilleOuverte.cible = 1 }) }, "ilot-4g-pastille-rappel-survolee")

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
            let finRuban = 640 / 2 + (geometrie.largeur + 2 * GeometrieEncoche.aile) / 2 - GeometrieEncoche.retraitRuban
            let droite = finRuban - LectureMiniature.retraitDroit + 4
            return ZStack(alignment: .topLeading) {
                EncocheVue(m: dictee(mainsLibres: mainsLibres, avecMiniature: lecture != nil), tailleFenetre: tailleDictee)
                    .frame(width: 640, height: tailleDictee.height, alignment: .top)
                if let lecture {
                    MiniatureLectureVue(m: lecture, presence: 1)
                        .frame(width: LectureMiniature.tailleFenetre.width, height: LectureMiniature.tailleFenetre.height)
                        .offset(x: droite - LectureMiniature.tailleFenetre.width, y: geometrie.hauteur)
                }
            }
            .frame(width: 640, height: tailleDictee.height, alignment: .topLeading)
        }
        ecrire(bureau(hauteur: geometrie.hauteur + 80) { scene(nil).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top) }, "dictee-sans-lecture")
        ecrire(bureau(hauteur: geometrie.hauteur + 80) { scene(modele(contenus[2], joue: false)).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top) }, "dictee-miniature-musique")
        ecrire(bureau(hauteur: geometrie.hauteur + 80) { scene(modele(contenus[1], joue: false)).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top) }, "dictee-miniature-video")
        ecrire(bureau(hauteur: geometrie.hauteur + 80) { scene(sansImage(contenus[1], joue: false)).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top) }, "dictee-miniature-icone-app")
        ecrire(bureau(hauteur: geometrie.hauteur + 80) { scene(modele(contenus[0], joue: false), mainsLibres: true).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top) }, "dictee-mains-libres-miniature")

        return ok ? 0 : 1
    }
}
