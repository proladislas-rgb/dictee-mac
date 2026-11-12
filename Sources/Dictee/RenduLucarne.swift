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
        func ecrire(_ m: IlotMoteur, _ p: PlaceLucarne?, fond: FondRendu, _ nom: String) {
            let r = cadrage(p)
            let o = m.origineVue, t = m.tailleVue
            // le verre clair (ImageRenderer ne dessine pas `.glassEffect`) : le faux écran vu au travers, à peine flouté au centre, et sur
            // le bord une lentille qui le grossit et le décale (la distorsion de la maquette « Liquide ») ; la bulle de même
            let k = m.lucarne.capsule.affichee
            let forme = k.decale(dx: ecran.centreX)
            let bulle = m.bulleLibre.map { $0.decale(dx: ecran.centreX) }
            let vue = ZStack(alignment: .topLeading) {
                FauxEcran(fond: fond)
                FauxVerre(forme: forme, fond: fond)
                if let b = bulle { FauxVerre(forme: b, fond: fond) }
                IlotVue(m: m)
                    .frame(width: t.width, height: t.height)
                    .offset(x: CGFloat(ecran.centreX) + o.x - t.width / 2, y: o.y)
            }
            .frame(width: taille.width, height: taille.height, alignment: .topLeading)
            .offset(x: -r.minX, y: -r.minY)
            .frame(width: r.width, height: r.height, alignment: .topLeading)
            .clipped()
            enregistrer(vue, nom)
        }
        func enregistrer(_ vue: some View, _ nom: String) {
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
            // la Terre (lourde en PNG : un dépôt public) seulement depuis un coin du bas et un du haut
            for fond in FondRendu.allCases where fond != .terre || p == .basGauche || p == .hautDroite {
                // repliée : le minuteur, et le micro coupé dans la bulle
                ecrire(scene(p, nil) { m in m.minuteur = MinuteurIlot(minutes: 10, depuis: t0.addingTimeInterval(-128)); m.microCoupe = true }, p, fond: fond, "lucarne-\(n)-pilule-\(fond.rawValue)")
                ecrire(scene(p, "Centre"), p, fond: fond, "lucarne-\(n)-centre-\(fond.rawValue)")
            }
        }
        // tenue au doigt au milieu de l'écran, loin de l'encoche : du verre (jamais une capsule noire), levée 4 % plus grande, son ombre
        for fond in FondRendu.allCases {
            let m = scene(.basMilieu, nil) { m in m.minuteur = MinuteurIlot(minutes: 10, depuis: t0.addingTimeInterval(-128)) }
            m.lucarne.vol = true   // en main : la vue suit la capsule (comme pendant la tenue)
            m.lucarne.capsule = RessortsCapsule(.pilule(cx: 0, cy: taille.height / 2, largeur: GeoLucarne.pilule.largeur, hauteur: GeoLucarne.pilule.hauteur), noir: 0)
            m.lucarne.capsule.lever(); m.lucarne.capsule.poser()
            ecrire(m, nil, fond: fond, "lucarne-tenue-milieu-\(fond.rawValue)")
        }
        // la carte Lecture depuis le coin bas gauche (le cas de Hugues, 12/11 soir : sur la Terre de son fond d'écran), sur les trois fonds
        for fond in FondRendu.allCases {
            let m = scene(.basGauche, nil) { m in
                m.lecture.morceau = MorceauEnCours(titre: "Je détestais la mode des iPods, donc j\u{2019}en ai racheté un", artiste: "Le Coin Tech",
                                                          app: "com.google.Chrome", joue: true, duree: 754, position: 202)
                m.lecturePresente = true; m.donneesChangees(); m.survole = true
            }
            ecrire(m, .basGauche, fond: fond, "lucarne-bas-gauche-lecture-\(fond.rawValue)")
        }
        // les autres écrans, depuis un coin du bas (au-dessus du Dock) et un coin du haut, sur la page blanche
        for (nom, fichier, p) in [("Dictées", "dictees", PlaceLucarne.basDroite), ("carte Claude", "claude", .hautGauche), ("Étagère", "etagere", .basGauche),
                                  ("Réunion", "reunion", .hautDroite), ("annonce téléchargé", "telecharge", .droite), ("annonce capture", "capture", .gauche),
                                  ("alerte rappel", "alerte-rappel", .basGauche), ("alerte minuteur", "alerte-minuteur", .hautDroite),
                                  ("onde de la note dictée", "note-onde", .basDroite), ("annonce AirDrop", "airdrop", .hautGauche)] + RenduVoix.lucarne {
            ecrire(scene(p, nom), p, fond: .clair, "lucarne-ecran-\(fichier)")
        }
        // la dictée (fn) à la place de la Lucarne, en verre : dans un coin du bas et un du haut, le texte en direct, mains libres
        for (p, n) in [(PlaceLucarne.basGauche, "bas-gauche"), (.hautDroite, "haut-droite")] {
            for fond in [FondRendu.clair, .terre] {
                let d = EncocheModele()
                d.ouverte = true; d.ruban = true; d.mainsLibres = p == .hautDroite
                d.texte = "Je te rappelle demain pour confirmer le devis"
                d.niveaux = [0.3, 0.7, 1, 0.6, 0.35]
                d.icone = NSWorkspace.shared.icon(forFile: "/System/Applications/Mail.app")
                let pl = PlacementDictee(ecran: ecran, place: p, centre: CGFloat(ecran.centreX), haut: taille.height)
                let k = GeoLucarne.dictee(p, ecran, ruban: true, mainsLibres: d.mainsLibres)
                let f = pl.cadreFenetre
                let r = cadrage(p)
                let vue = ZStack(alignment: .topLeading) {
                    FauxEcran(fond: fond)
                    FauxVerre(forme: k.decale(dx: ecran.centreX), fond: fond)
                    DicteeVerreVue(m: d, placement: pl, statique: true)
                        .frame(width: f.width, height: f.height)
                        .offset(x: f.minX, y: taille.height - f.maxY)
                }
                .frame(width: taille.width, height: taille.height, alignment: .topLeading)
                .offset(x: -r.minX, y: -r.minY)
                .frame(width: r.width, height: r.height, alignment: .topLeading)
                .clipped()
                enregistrer(vue, "lucarne-dictee-\(n)-\(fond.rawValue)")
            }
        }
        return ok ? 0 : 1
    }
}

/// Le fond des rendus : une page blanche (le pire cas pour le texte blanc), une page sombre, ou un fond d'écran sombre (la Terre dans la
/// nuit, comme chez Hugues : on doit la voir au travers du verre).
enum FondRendu: String, CaseIterable {
    case clair, sombre, terre
}

private extension CapsuleLucarne {
    /// La même forme, décalée en x (repère de la Lucarne → repère du faux écran, depuis son bord gauche).
    func decale(dx: Double) -> CapsuleLucarne { CapsuleLucarne(x0: x0 + dx, x1: x1 + dx, y0: y0, y1: y1, s: s, r: r) }
}

/// Un faux écran de MacBook : une fenêtre de texte (page blanche ou sombre) sous la barre des menus, ou le seul fond d'écran (la Terre) ;
/// le Dock en bas.
private struct FauxEcran: View {
    var fond: FondRendu
    var body: some View {
        let t = RenduLucarne.taille, barre: CGFloat = 33
        let clair = fond == .clair
        let encre = clair ? Color(hex: 0x1D1D1F) : Color.white.opacity(0.85)
        ZStack(alignment: .topLeading) {
            if fond == .terre {
                Terre()
            } else {
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
            }
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

/// Un fond d'écran sombre : la Terre de nuit vue de l'espace (océans bleus, continents, nuages, le liseré de l'atmosphère) et des étoiles.
/// Des détails fins, pour juger ce que le verre laisse voir au travers.
private struct Terre: View {
    var body: some View {
        let t = RenduLucarne.taille
        Canvas { ctx, taille in
            ctx.fill(Path(CGRect(origin: .zero, size: taille)), with: .color(Color(hex: 0x03050B)))
            var g = SystemRandomNumberGenerator.Fixe(graine: 7)
            for _ in 0..<260 {
                let x = Double.random(in: 0...taille.width, using: &g), y = Double.random(in: 0...taille.height, using: &g), r = Double.random(in: 0.4...1.3, using: &g)
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)), with: .color(.white.opacity(Double.random(in: 0.3...0.9, using: &g))))
            }
            let c = CGPoint(x: taille.width * 0.5, y: taille.height * 0.62), rayon = taille.height * 0.42
            let disque = Path(ellipseIn: CGRect(x: c.x - rayon, y: c.y - rayon, width: 2 * rayon, height: 2 * rayon))
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - rayon - 14, y: c.y - rayon - 14, width: 2 * rayon + 28, height: 2 * rayon + 28)),
                     with: .radialGradient(Gradient(colors: [Color(hex: 0x6FB7FF).opacity(0.55), .clear]), center: c, startRadius: rayon - 6, endRadius: rayon + 14))
            ctx.fill(disque, with: .radialGradient(Gradient(colors: [Color(hex: 0x1D5FAF), Color(hex: 0x0B2E63), Color(hex: 0x061632)]),
                                                     center: CGPoint(x: c.x - rayon * 0.3, y: c.y - rayon * 0.6), startRadius: 0, endRadius: rayon * 1.2))
            ctx.clip(to: disque)
            for _ in 0..<26 {
                let x = Double.random(in: c.x - rayon...c.x + rayon, using: &g), y = Double.random(in: c.y - rayon...c.y + rayon, using: &g)
                let w = Double.random(in: 40...190, using: &g), h = Double.random(in: 20...90, using: &g)
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: w, height: h)), with: .color(Color(hex: 0x3E6B3A).opacity(0.85)))
                ctx.fill(Path(ellipseIn: CGRect(x: x + w * 0.3, y: y + h * 0.2, width: w * 0.4, height: h * 0.5)), with: .color(Color(hex: 0x8A7448).opacity(0.7)))
            }
            for _ in 0..<40 {
                let x = Double.random(in: c.x - rayon...c.x + rayon, using: &g), y = Double.random(in: c.y - rayon...c.y + rayon, using: &g)
                var p = Path(); p.move(to: CGPoint(x: x, y: y))
                p.addQuadCurve(to: CGPoint(x: x + Double.random(in: 60...200, using: &g), y: y + Double.random(in: -20...20, using: &g)),
                               control: CGPoint(x: x + 50, y: y - Double.random(in: 10...40, using: &g)))
                ctx.stroke(p, with: .color(.white.opacity(0.75)), lineWidth: Double.random(in: 1.5...5, using: &g))
            }
        }
        .frame(width: t.width, height: t.height)
    }
}

private extension SystemRandomNumberGenerator {
    /// Un tirage toujours le même (les rendus ne changent pas d'une fois à l'autre).
    struct Fixe: RandomNumberGenerator {
        var etat: UInt64
        init(graine: UInt64) { etat = graine &* 0x9E3779B97F4A7C15 | 1 }
        mutating func next() -> UInt64 { etat ^= etat << 13; etat ^= etat >> 7; etat ^= etat << 17; return etat }
    }
}

/// Le faux verre clair d'un rendu, fidèle au verre « Liquide » : à travers la forme, le faux écran presque net (flou de 0,8 pt) ; sur une
/// bande au bord (la lentille), le même écran grossi de 9 % depuis le centre de la forme : ce qui passe sous le bord est déformé, comme
/// dans la maquette ; un reflet clair suit le haut du bord.
private struct FauxVerre: View {
    var forme: CapsuleLucarne
    var fond: FondRendu
    var body: some View {
        let t = RenduLucarne.taille
        let petit = min(forme.largeur, forme.hauteur), bande = min(14, petit * 0.28)
        let dedans = CapsuleLucarne(x0: forme.x0 + bande, x1: forme.x1 - bande, y0: forme.y0 + bande, y1: forme.y1 - bande,
                                    s: max(1, forme.s - bande / TraceIlot.portee), r: max(1, forme.r - bande / TraceIlot.portee))
        let centre = UnitPoint(x: forme.centreX / Double(t.width), y: forme.centreY / Double(t.height))
        func masque(_ c: CapsuleLucarne) -> some View {
            FormeNoire(points: TraceLucarne.calculer(c)).fill(Color.black).frame(width: t.width, height: t.height).offset(x: -t.width / 2)
        }
        return ZStack(alignment: .topLeading) {
            FauxEcran(fond: fond).blur(radius: 0.8)
                .mask(alignment: .topLeading) { masque(forme) }
            FauxEcran(fond: fond).scaleEffect(1.09, anchor: centre).blur(radius: 1.2)
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
