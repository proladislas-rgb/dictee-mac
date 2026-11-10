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

        // ---- l'îlot « centre d'activités » : un moteur par scène, ressorts posés, aucun temps réel ----
        let cal = Calendar.current
        let t0 = cal.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 14, minute: 32))!
        let rdv = EvenementAgenda(id: "r", titre: "Point équipe", debut: t0.addingTimeInterval(600), fin: t0.addingTimeInterval(2580), lieu: nil, lien: URL(string: "https://meet.exemple.fr/pt-eq-93"))
        let rappelExemple = Rappel(texte: "Appeler Paul", echeance: t0, sonneLe: t0, cree: t0.addingTimeInterval(-3600))
        func scene(lecture: LectureModele? = nil, _ config: (IlotMoteur) -> Void) -> IlotMoteur {
            let m = IlotMoteur(lecture: lecture ?? modele(contenus[2]))
            m.geometrie = geometrie; m.statique = true; m.maintenant = { t0 }; m.horloge = "14:32"; m.calendrierActif = true
            config(m)
            m.donneesChangees(); m.poser()
            return m
        }
        func ilot(_ m: IlotMoteur) -> some View { IlotVue(m: m).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top) }
        let petitBureau: CGFloat = geometrie.hauteur + 70, moyenBureau: CGFloat = geometrie.hauteur + 130, grandBureau: CGFloat = geometrie.hauteur + 240
        func minut(_ min: Double, restant: Double? = nil) -> MinuteurIlot { MinuteurIlot(minutes: min, depuis: t0.addingTimeInterval(-(min * 60 - (restant ?? min * 60)))) }
        let lectureSerie = modele(contenus[2])
        // 1 · les états
        ecrire(bureau(hauteur: petitBureau) { ilot(scene { $0.minuteur = minut(10, restant: 392) }) }, "ilot-1b-compact-minuteur")
        ecrire(bureau(hauteur: petitBureau) { ilot(scene(lecture: lectureSerie) { $0.lecturePresente = true }) }, "ilot-1c-compact-lecture")
        ecrire(bureau(hauteur: moyenBureau) { ilot(scene { $0.minuteur = minut(10, restant: 392); $0.survole = true }) }, "ilot-1d-etendu-minuteur")
        ecrire(bureau(hauteur: grandBureau) { ilot(scene(lecture: lectureSerie) { $0.lecturePresente = true; $0.survole = true }) }, "ilot-1e-etendu-lecture")
        ecrire(bureau(hauteur: grandBureau) { ilot(scene(lecture: modele(contenus[1])) { $0.lecturePresente = true; $0.survole = true }) }, "ilot-1f-etendu-lecture-video")
        ecrire(bureau(hauteur: grandBureau) { ilot(scene(lecture: modele(contenus[0], direct: true)) { $0.lecturePresente = true; $0.survole = true }) }, "ilot-1g-etendu-lecture-direct")
        // 2 · deux activités à la fois
        ecrire(bureau(hauteur: petitBureau) { ilot(scene(lecture: lectureSerie) { $0.lecturePresente = true; $0.minuteur = minut(10, restant: 372) }) }, "ilot-2a-lecture-et-pastille-minuteur")
        ecrire(bureau(hauteur: petitBureau) { ilot(scene(lecture: lectureSerie) { $0.lecturePresente = true; $0.minuteur = minut(10, restant: 372); $0.pastilleOuverte.cible = 1 }) }, "ilot-2b-pastille-depliee")
        // 3 · minuteur
        ecrire(bureau(hauteur: grandBureau) { ilot(scene { $0.epingle = true; $0.survole = true }) }, "ilot-3a-accueil-epingle")
        ecrire(bureau(hauteur: petitBureau) { ilot(scene { $0.bandeau = BandeauIlot(vue: .minuteurLance, jusqua: t0, ligne1: "Minuteur lancé", ligne2: "10 min \u{00B7} fin à 14:42"); $0.minuteur = minut(10) }) }, "ilot-3b-minuteur-lance")
        ecrire(bureau(hauteur: moyenBureau) { ilot(scene { $0.alerte = AlerteIlot(vue: .minuteurFini, jusqua: nil, libelle: "10 min") }) }, "ilot-3d-minuteur-fini")
        ecrire(bureau(hauteur: moyenBureau) { ilot(scene { var x = minut(10, restant: 392); x.pause(a: t0); $0.minuteur = x; $0.survole = true }) }, "ilot-3e-minuteur-en-pause")
        // 4 · rappels
        ecrire(bureau(hauteur: petitBureau) { ilot(scene { $0.bandeau = BandeauIlot(vue: .rappelAjoute, jusqua: t0, ligne1: "Rappel ajouté", ligne2: "Appeler Paul \u{00B7} aujourd\u{2019}hui", meta: "15:00") }) }, "ilot-4a-rappel-ajoute")
        ecrire(bureau(hauteur: grandBureau) { ilot(scene { let r = Rappel(texte: "Appeler Paul", echeance: t0.addingTimeInterval(1700), cree: t0); let r2 = Rappel(texte: "Envoyer le devis", echeance: t0.addingTimeInterval(10000), cree: t0); $0.rappelsAVenir = [r, r2]; $0.ouvrirFormulaireRappel() }) }, "ilot-4b-rappels-liste")
        ecrire(bureau(hauteur: moyenBureau) { ilot(scene { $0.alerte = AlerteIlot(vue: .rappelEtendu, jusqua: nil, rappel: rappelExemple); $0.rappelsSonnes = [rappelExemple] }) }, "ilot-4c-rappel-arrive")
        ecrire(bureau(hauteur: petitBureau) { ilot(scene { $0.rappelsSonnes = [rappelExemple] }) }, "ilot-4d-cloche-sans-reponse")
        ecrire(bureau(hauteur: petitBureau) { ilot(scene { $0.bandeau = BandeauIlot(vue: .rappelFait, jusqua: t0, ligne1: "Fait", ligne2: "Appeler Paul") }) }, "ilot-4e-fait")
        ecrire(bureau(hauteur: petitBureau) { ilot(scene { $0.bandeau = BandeauIlot(vue: .rappelReporte, jusqua: t0, ligne1: "Je vous le redis dans 10 min", ligne2: "Appeler Paul", meta: "15:10") }) }, "ilot-4f-plus-tard")
        // 5 · calendrier
        ecrire(bureau(hauteur: petitBureau) { ilot(scene { $0.rendezVous = rdv; $0.rendezVousProche = true; $0.bandeau = BandeauIlot(vue: .agendaAvant, jusqua: t0, ligne1: "Point équipe", ligne2: "Dans 10 min \u{00B7} Visio", evenement: rdv) }) }, "ilot-5a-rendez-vous-10-min")
        ecrire(bureau(hauteur: petitBureau) { ilot(scene { $0.rendezVous = rdv; $0.rendezVousProche = true }) }, "ilot-5a2-rendez-vous-compact")
        ecrire(bureau(hauteur: grandBureau) { ilot(scene { $0.rendezVous = rdv; $0.rendezVousProche = true; $0.survole = true }) }, "ilot-5b-rendez-vous-etendu")
        ecrire(bureau(hauteur: petitBureau) { ilot(scene { $0.rendezVous = rdv; $0.alerte = AlerteIlot(vue: .agendaDebut, jusqua: nil, evenement: rdv) }) }, "ilot-5c-rendez-vous-commence")
        // 6 · notifications
        let n1 = NotificationRecue(app: "Messages", titre: "Camille", corps: "On se retrouve à 19 h devant le cinéma ?", date: t0)
        ecrire(bureau(hauteur: petitBureau) { ilot(scene { $0.notifications = [n1]; $0.bandeau = BandeauIlot(vue: .notification, jusqua: t0, ligne1: "Camille", ligne2: n1.corps) }) }, "ilot-6a-notification")
        ecrire(bureau(hauteur: petitBureau) { ilot(scene { $0.notifications = [n1, NotificationRecue(app: "Banque", titre: "Banque", corps: "", date: t0), NotificationRecue(app: "Slack", titre: "Équipe projet", corps: "", date: t0)]; $0.bandeau = BandeauIlot(vue: .notifications, jusqua: t0, ligne1: "", ligne2: "") }) }, "ilot-6b-notifications-groupees")
        // 7 · accueil
        ecrire(bureau(hauteur: grandBureau) { ilot(scene { $0.epingle = true; $0.survole = true; $0.derniereDictee = ("Je te rappelle demain pour confirmer le créneau avec l\u{2019}équipe", "3 min"); $0.rendezVousSuivant = rdv }) }, "ilot-7-accueil")
        ecrire(bureau(hauteur: petitBureau) { ilot(scene { _ in }) }, "ilot-7b-ilot-vide")
        // 8 · priorités : une alerte arrive, la lecture patiente en pastille
        ecrire(bureau(hauteur: moyenBureau) { ilot(scene(lecture: lectureSerie) { $0.lecturePresente = true; $0.minuteur = minut(10, restant: 372); $0.alerte = AlerteIlot(vue: .rappelEtendu, jusqua: nil, rappel: rappelExemple); $0.rappelsSonnes = [rappelExemple] }) }, "ilot-8-alerte-et-pastille")
        // mi-course : la forme entre le compact et l'étendu
        do {
            let m = scene { $0.minuteur = minut(10, restant: 392) }
            m.survole = true; m.donneesChangees()
            for _ in 0..<9 { m.avancer(1.0 / 60) }
            ecrire(bureau(hauteur: moyenBureau) { ilot(m) }, "ilot-9-mi-course")
        }
        // la dictée prend la place : tout est effacé, il ne reste que l'encoche de la dictée
        ecrire(bureau(hauteur: petitBureau) { ilot(scene(lecture: lectureSerie) { $0.lecturePresente = true; $0.minuteur = minut(10, restant: 372); $0.dictee = true }) }, "ilot-10-dictee-efface-tout")
        // sans image du système ni miniature : l'icône de l'app en petit sur fond sombre, teinte tirée de l'icône
        func sansImage(_ c: Contenu, joue: Bool = true) -> LectureModele {
            let m = modele(c, joue: joue)
            m.image = nil
            m.teinte = chrome.map { LectureControleur.teinte(de: $0) } ?? .neutre
            return m
        }
        ecrire(bureau(hauteur: grandBureau) { ilot(scene(lecture: sansImage(contenus[1])) { $0.lecturePresente = true; $0.survole = true }) }, "ilot-1h-etendu-sans-image")
        ecrire(bureau(hauteur: petitBureau) { ilot(scene(lecture: sansImage(contenus[1])) { $0.lecturePresente = true }) }, "ilot-1i-compact-sans-image")

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
