import AppKit
import SwiftUI
import DicteeCore

// Dictee --rendu-lucarne dossier : la Lucarne hors de l'encoche en PNG, sans fenêtre (docs/plan-lucarne-deplacable.md, mission 3). Un faux
// écran de MacBook (1470 × 956, barre de 33 pt, caméra de 179 pt, Dock en bas de 70 pt et 600 pt de large), sur une page blanche (le pire
// cas pour le texte blanc) et sur un fond sombre ; le quart de l'écran où vit la Lucarne. ImageRenderer ne dessine pas le verre de macOS :
// c'est le faux verre (blanc léger, même voile, même liseré, même ombre).

@MainActor
enum RenduLucarne {
    static let taille = CGSize(width: 1470, height: 956)
    static let geometrie: GeometrieEncoche = { var g = GeometrieEncoche(); g.largeur = 179; g.hauteur = 33; g.reelle = true; return g }()
    static let ecran = EcranLucarne(cadre: CGRect(origin: .zero, size: taille), barre: 33, demiCamera: 89.5, centreX: 735,
                                    retraitBas: 70, dockCote: .bas, dockLargeur: 600, dockEpaisseur: 70)

    static func executer(dossier: String) -> Int32 {
        _ = NSApplication.shared
        let url = URL(fileURLWithPath: (dossier as NSString).expandingTildeInPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let t0 = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 14, minute: 32))!
        let ecrans = Dictionary(uniqueKeysWithValues: CatalogueLucarne.ecrans(t0: t0).map { ($0.nom, $0) })
        var ok = true

        /// Un moteur posé à `place`, l'écran du catalogue `nom` ouvert (nil : replié), ressorts posés.
        func scene(_ place: PlaceLucarne, _ nom: String?, _ config: (IlotMoteur) -> Void = { _ in }) -> IlotMoteur {
            let lec = LectureModele(); lec.geometrie = geometrie; lec.statique = true
            let m = IlotMoteur(lecture: lec)
            m.geometrie = geometrie; m.statique = true; m.maintenant = { t0 }
            m.dictees.source = { HistoriqueStore(enMemoire: IlotEssai.dicteesFactices(maintenant: t0.addingTimeInterval(40 * 60))) }
            m.poserLucarne(ecran, uuid: "RENDU", place: place)
            config(m)
            if let nom, let e = ecrans[nom] { e.poser(m) }
            m.donneesChangees()
            m.poser()
            return m
        }
        /// Le quart de l'écran (ou la moitié du milieu, à gauche et à droite) où vit la place ; nil : le milieu de l'écran (la tenue).
        func cadrage(_ p: PlaceLucarne?) -> CGRect {
            guard let p else { return CGRect(x: taille.width / 4, y: taille.height / 4, width: taille.width / 2, height: taille.height / 2) }
            let w = taille.width / 2, h = taille.height / 2
            let x: CGFloat = p.ancre.x > 0.5 ? w : (p.ancre.x < 0.5 ? 0 : w / 2)
            let y: CGFloat = p.ancre.y > 0.5 ? h : (p.ancre.y < 0.5 ? 0 : h / 2)
            return CGRect(x: x, y: y, width: w, height: h)
        }
        func ecrire(_ m: IlotMoteur, _ p: PlaceLucarne?, clair: Bool, _ nom: String) {
            let r = cadrage(p)
            let o = m.origineVue, t = m.tailleVue
            // le verre clair (ImageRenderer ne dessine pas `.glassEffect`) : le faux écran vu au travers, à peine flouté au centre, et sur
            // le bord une lentille qui le grossit et le décale (la distorsion de la maquette « Liquide ») ; la bulle de même
            let k = m.lucarne.capsule.affichee
            let forme = CapsuleLucarne(x0: k.x0 + ecran.centreX, x1: k.x1 + ecran.centreX, y0: k.y0, y1: k.y1, s: k.s, r: k.r)
            let bulle = m.bulleLibre.map { CapsuleLucarne(x0: $0.x0 + ecran.centreX, x1: $0.x1 + ecran.centreX, y0: $0.y0, y1: $0.y1, s: $0.s, r: $0.r) }
            let vue = ZStack(alignment: .topLeading) {
                FauxEcran(clair: clair)
                FauxVerre(forme: forme, clair: clair)
                if let b = bulle { FauxVerre(forme: b, clair: clair) }
                IlotVue(m: m)
                    .frame(width: t.width, height: t.height)
                    .offset(x: CGFloat(ecran.centreX) + o.x - t.width / 2, y: o.y)
            }
            .frame(width: taille.width, height: taille.height, alignment: .topLeading)
            .offset(x: -r.minX, y: -r.minY)
            .frame(width: r.width, height: r.height, alignment: .topLeading)
            .clipped()
            let rendu = ImageRenderer(content: vue)
            rendu.scale = 1.5
            guard let image = rendu.nsImage, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { print("échec du rendu \(nom)"); ok = false; return }
            let fichier = url.appendingPathComponent("\(nom).png")
            try? png.write(to: fichier)
            print("écrit \(fichier.path) (\(rep.pixelsWide)×\(rep.pixelsHigh))")
        }

        let places: [(PlaceLucarne, String)] = [(.hautGauche, "haut-gauche"), (.hautDroite, "haut-droite"), (.basGauche, "bas-gauche"),
                                                (.basDroite, "bas-droite"), (.gauche, "gauche"), (.droite, "droite")]
        for (p, n) in places {
            for clair in [true, false] {
                let fond = clair ? "clair" : "sombre"
                // repliée : le minuteur, et le micro coupé dans la bulle
                ecrire(scene(p, nil) { m in m.minuteur = MinuteurIlot(minutes: 10, depuis: t0.addingTimeInterval(-128)); m.microCoupe = true }, p, clair: clair, "lucarne-\(n)-pilule-\(fond)")
                ecrire(scene(p, "Centre"), p, clair: clair, "lucarne-\(n)-centre-\(fond)")
            }
        }
        // tenue au doigt au milieu de l'écran, loin de l'encoche : du verre (jamais une capsule noire), levée 4 % plus grande, son ombre
        for clair in [true, false] {
            let m = scene(.basMilieu, nil) { m in m.minuteur = MinuteurIlot(minutes: 10, depuis: t0.addingTimeInterval(-128)) }
            m.lucarne.vol = true   // en main : la vue suit la capsule (comme pendant la tenue)
            m.lucarne.capsule = RessortsCapsule(.pilule(cx: 0, cy: taille.height / 2, largeur: GeoLucarne.pilule.largeur, hauteur: GeoLucarne.pilule.hauteur), noir: 0)
            m.lucarne.capsule.lever(); m.lucarne.capsule.poser()
            ecrire(m, nil, clair: clair, "lucarne-tenue-milieu-\(clair ? "clair" : "sombre")")
        }
                // les autres écrans, depuis un coin du bas (au-dessus du Dock) et un coin du haut, sur la page blanche
        for (nom, fichier, p) in [("Dictées", "dictees", PlaceLucarne.basDroite), ("carte Claude", "claude", .hautGauche), ("Étagère", "etagere", .basGauche),
                                  ("Réunion", "reunion", .hautDroite), ("annonce téléchargé", "telecharge", .droite), ("annonce capture", "capture", .gauche),
                                  ("alerte rappel", "alerte-rappel", .basGauche), ("alerte minuteur", "alerte-minuteur", .hautDroite),
                                  ("onde de la note dictée", "note-onde", .basDroite), ("annonce AirDrop", "airdrop", .hautGauche)] {
            ecrire(scene(p, nom), p, clair: true, "lucarne-ecran-\(fichier)")
        }
        return ok ? 0 : 1
    }
}

/// Un faux écran de MacBook : une fenêtre de texte (page blanche ou sombre) sous la barre des menus, le Dock en bas.
private struct FauxEcran: View {
    var clair: Bool
    var body: some View {
        let t = RenduLucarne.taille, barre: CGFloat = 33
        let encre = clair ? Color(hex: 0x1D1D1F) : Color.white.opacity(0.85)
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: clair ? [Color(hex: 0xDCE6F2), Color(hex: 0xF4E9DA)] : [Color(hex: 0x1C2233), Color(hex: 0x0E0F14)], startPoint: .topLeading, endPoint: .bottomTrailing)
            // la fenêtre : une page de texte (blanche ou sombre) qui couvre presque tout l'écran
            VStack(alignment: .leading, spacing: 12) {
                Text("Compte rendu du chantier").font(.system(size: 24, weight: .bold)).foregroundStyle(encre)
                ForEach(0..<26, id: \.self) { i in
                    Text("Ligne \(i + 1) du document : les livraisons arrivent mardi, le devis est validé, la réunion de suivi est jeudi à 10 h.")
                        .font(.system(size: 14)).foregroundStyle(encre.opacity(0.8))
                }
            }
            .padding(30)
            .frame(width: t.width - 40, height: t.height - barre - 100, alignment: .topLeading)
            .background(clair ? Color.white : Color(hex: 0x1E1E20))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .offset(x: 20, y: barre + 12)
            // la barre des menus
            HStack(spacing: 18) {
                Image(systemName: "apple.logo"); Text("Pages").fontWeight(.bold); Text("Fichier"); Text("Édition"); Text("Format")
                Spacer()
                Image(systemName: "wifi"); Text("Jeu. 12 nov.  14:32")
            }
            .font(.system(size: 13, weight: .medium)).foregroundStyle(clair ? Color.black : Color.white)
            .padding(.horizontal, 16).frame(width: t.width, height: barre)
            .background(clair ? Color.white.opacity(0.7) : Color.black.opacity(0.5))
            // la caméra
            Rectangle().fill(Color.black).frame(width: 179, height: barre).offset(x: t.width / 2 - 89.5)
            // le Dock
            HStack(spacing: 10) {
                ForEach(0..<9, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hue: Double(i) / 9, saturation: 0.55, brightness: 0.9)).frame(width: 52, height: 52)
                }
            }
            .padding(.horizontal, 12).frame(width: 600, height: 64)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(clair ? Color.white.opacity(0.55) : Color.white.opacity(0.18)))
            .offset(x: t.width / 2 - 300, y: t.height - 68)
        }
        .frame(width: t.width, height: t.height, alignment: .topLeading)
    }
}

/// Le faux verre clair d'un rendu : à travers la forme, le faux écran flouté de 3 pt (le flou du verre clair, juste assez pour brouiller les lettres derrière) ; sur une bande au bord (la lentille), le même
/// écran grossi de 9 % depuis le centre de la forme et un peu plus flou : ce qui passe sous le bord est déformé, comme dans la maquette.
private struct FauxVerre: View {
    var forme: CapsuleLucarne
    var clair: Bool
    var body: some View {
        let t = RenduLucarne.taille
        let petit = min(forme.largeur, forme.hauteur), bande = min(18, petit * 0.32)
        let dedans = CapsuleLucarne(x0: forme.x0 + bande, x1: forme.x1 - bande, y0: forme.y0 + bande, y1: forme.y1 - bande,
                                    s: max(1, forme.s - bande / TraceIlot.portee), r: max(1, forme.r - bande / TraceIlot.portee))
        let centre = UnitPoint(x: forme.centreX / Double(t.width), y: forme.centreY / Double(t.height))
        func masque(_ c: CapsuleLucarne) -> some View {
            FormeNoire(points: TraceLucarne.calculer(c)).fill(Color.black).frame(width: t.width, height: t.height).offset(x: -t.width / 2)
        }
        return ZStack(alignment: .topLeading) {
            FauxEcran(clair: clair).blur(radius: 3)
                .mask(alignment: .topLeading) { masque(forme) }
            FauxEcran(clair: clair).scaleEffect(1.09, anchor: centre).blur(radius: 2.4)
                .mask(alignment: .topLeading) {
                    ZStack(alignment: .topLeading) {
                        masque(forme)
                        masque(dedans).blendMode(.destinationOut)
                    }
                    .compositingGroup()
                    .frame(width: t.width, height: t.height, alignment: .topLeading)
                }
        }
        .frame(width: t.width, height: t.height, alignment: .topLeading)
    }
}
