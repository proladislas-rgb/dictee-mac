import AppKit
import SwiftUI
import DicteeCore

// La réunion dans l'îlot (maquette design/maquettes/ilot-reunion.html, étapes 1 à 7, validée par Hugues : « très bien pour ce visuel »),
// sur le modèle du Notetaker de Wispr Flow :
// - la réunion n'est plus un masque (l'îlot ne s'efface plus) : c'est une activité comme une autre. Repliée : un point rouge et l'onde
//   dans l'aile gauche, le temps dans l'aile droite ; une vidéo ou un minuteur passe dans la bulle ;
// - au survol, la carte « Réunion » : le direct (« Moi » / « Eux » discrets à gauche, les mots pas encore sûrs en gris clair, la liste
//   qui suit en bas, s'arrête si on remonte, reprend en bas), « Ce que j'ai raté », « Ajouter un point », pause, Arrêter, « Centre » ;
//   le Centre, les Dictées et l'accueil restent dessous (points de page, défilement hors du direct) ;
// - les annonces : « Noter cet appel ? » (Noter / Non), « Note en préparation… », « Note prête · Ouvrir », un message court.
// Ce que le direct contient (ordre, tours de parole, échos, reprises) est décidé dans DicteeCore/DirectReunion.swift.

/// Les mesures de la carte « Réunion » (maquette, en points) : le dessin et les essais (où cliquer) s'en servent.
@MainActor
enum PlanReunion {
    static let marge: CGFloat = 14, entete: CGFloat = 26, ecartEntete: CGFloat = 10, hauteurDirect: CGFloat = 152, ecartPied: CGFloat = 12, pied: CGFloat = 30
    /// Le direct : « Moi » / « Eux » sur 30 pt, 10 pt, puis le texte (Newsreader 15 pt, lignes de 21 pt).
    static let colonneQui: CGFloat = 30, ecartQui: CGFloat = 10
    static let policeTexte: CGFloat = 15, interligne: Double = 21
    /// Une ligne « Point ajouté » (22 pt + 2 au-dessus et dessous).
    static let lignePoint: Double = 26
    /// Le fondu du haut du direct (les phrases plus anciennes s'effacent sous l'en-tête).
    static let fondu: CGFloat = 40

    static func zone(_ g: GrilleIlot) -> CGRect { g.zoneCarte(.reunionEtendu, haut: marge, bas: marge) }
    static func cadreEntete(_ g: GrilleIlot) -> CGRect { let z = zone(g); return CGRect(x: z.minX, y: z.minY, width: z.width, height: entete) }
    static func direct(_ g: GrilleIlot) -> CGRect { let z = zone(g); return CGRect(x: z.minX, y: z.minY + entete + ecartEntete, width: z.width, height: hauteurDirect) }
    static func cadrePied(_ g: GrilleIlot) -> CGRect { let d = direct(g); return CGRect(x: d.minX, y: d.maxY + ecartPied, width: d.width, height: pied) }
    /// Tout le corps de la carte sous la barre : un clic dans son vide ne range pas l'îlot (on visait un bouton).
    static func fond(_ g: GrilleIlot) -> CGRect {
        let w = g.corps(.reunionEtendu)
        return CGRect(x: -w, y: g.barre, width: 2 * w, height: g.hauteur(.reunionEtendu) - g.barre)
    }
    static func largeurTexte(_ g: GrilleIlot) -> CGFloat { direct(g).width - colonneQui - ecartQui }
    /// Le bouton « Centre » de l'en-tête (mesuré : 11 + glyphe + 4 + « Centre » + 11).
    static var largeurCentre: CGFloat { 11 + MesureIlot.symbole("square.grid.2x2.fill", 10, .bold) + 4 + MesureIlot.texte("Centre", 12.5, .semibold) + 11 }
    static func cadreCentre(_ g: GrilleIlot) -> CGRect { let e = cadreEntete(g); return CGRect(x: e.maxX - largeurCentre, y: e.minY, width: largeurCentre, height: entete) }

    // MARK: la rangée du bas (mesurée : rien ne se tasse ni ne déborde)

    static let titreRate = "Ce que j\u{2019}ai raté", titrePoint = "Ajouter un point", titrePointFait = "Point ajouté", titreArret = "Arrêter"
    /// 12,5 pt (la maquette dit 13 px) : à 13 pt, SF est plus large que la police du navigateur et les quatre boutons ne tiennent plus
    /// avec leurs glyphes derrière une caméra de 179 pt (432 pt pour 423) ; à 12,5 pt : 414.
    static let policeBouton: CGFloat = 12.5, glyphe: CGFloat = 14, espaceGlyphe: CGFloat = 6, ecartBoutons: CGFloat = 8, rond: CGFloat = 30
    struct Pied { var rate: CGRect; var point: CGRect; var pause: CGRect; var arret: CGRect; var glyphes: Bool }
    /// Un bouton « Ce que j'ai raté » / « Ajouter un point » : 10 + glyphe + 6 + texte + 12 (sans glyphe : 12 + texte + 12).
    static func largeurBouton(_ titres: [String], glyphe avec: Bool) -> CGFloat {
        let t = titres.map { MesureIlot.texte($0, policeBouton, .semibold) }.max() ?? 0
        return avec ? 10 + glyphe + espaceGlyphe + t + 12 : 12 + t + 12
    }
    static var largeurArret: CGFloat { 12 + 9 + 6 + MesureIlot.texte(titreArret, policeBouton, .semibold) + 13 }
    static func pied(_ g: GrilleIlot) -> Pied {
        let c = cadrePied(g)
        func essai(_ avec: Bool) -> Pied {
            let lr = largeurBouton([titreRate], glyphe: avec), lp = largeurBouton([titrePoint, titrePointFait], glyphe: avec)
            let arret = CGRect(x: c.maxX - largeurArret, y: c.minY, width: largeurArret, height: pied)
            let pause = CGRect(x: arret.minX - ecartBoutons - rond, y: c.minY, width: rond, height: pied)
            let rate = CGRect(x: c.minX, y: c.minY, width: lr, height: pied)
            let point = CGRect(x: rate.maxX + ecartBoutons, y: c.minY, width: lp, height: pied)
            return Pied(rate: rate, point: point, pause: pause, arret: arret, glyphes: avec)
        }
        let p = essai(true)
        return p.point.maxX + ecartBoutons <= p.pause.minX ? p : essai(false)
    }
}

/// La mise en page du direct : chaque ligne, sa place et sa hauteur (mesurées avec la police du dessin).
struct MiseEnPageDirect: Equatable {
    struct Element: Equatable { var ligne: LigneDirect; var y: Double; var h: Double }
    var elements: [Element] = []
    var hauteur: Double = 0
}

extension IlotMoteur {
    // MARK: le direct

    /// Les lignes du direct telles qu'on les montre (celles de la réunion en cours, ou les dernières vues pendant qu'elle s'efface).
    var lignesDirect: [LigneDirect] { (reunion ?? derniereReunion).lignes }

    func miseEnPageDirect() -> MiseEnPageDirect {
        let largeur = PlanReunion.largeurTexte(grille)
        let lignes = lignesDirect
        if let g = miseEnPageDirectGardee, g.largeur == largeur, g.lignes == lignes { return g.p }
        var p = MiseEnPageDirect()
        var y = 0.0
        for l in lignes {
            let h = l.estPoint ? PlanReunion.lignePoint : Self.hauteurLigne(l, largeur: largeur)
            p.elements.append(.init(ligne: l, y: y, h: h))
            y += h
        }
        p.hauteur = y
        miseEnPageDirectGardee = (lignes, largeur, p)
        return p
    }

    /// Une ligne de parole : son texte (et « … » s'il continue) mesuré en Newsreader 15 pt un peu plus étroit que sa place (jamais une
    /// ligne de moins que ce que SwiftUI dessinera), des lignes de 21 pt, 2 pt dessus et dessous.
    static func hauteurLigne(_ l: LigneDirect, largeur: CGFloat) -> Double {
        let texte = l.texte + (l.suite || l.morceaux.isEmpty ? " \u{2026}" : "")
        let f = Polices.nsTexte(PlanReunion.policeTexte)
        let r = (texte as NSString).boundingRect(with: CGSize(width: max(40, largeur - 6), height: .greatestFiniteMagnitude),
                                                 options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: f])
        let naturelle = max(1, ceil(f.ascender - f.descender + f.leading))
        return Double(max(1, Int((r.height / naturelle).rounded(.up)))) * PlanReunion.interligne + 4
    }

    /// La partie du direct qui ne tient pas dans sa zone (0 : tout tient).
    var cacheDirect: Double { max(0, miseEnPageDirect().hauteur - Double(PlanReunion.hauteurDirect)) }
    /// Le direct dépasse-t-il sa zone (il défile alors sous le pointeur) ?
    var directDefile: Bool { cacheDirect > 0.5 }
    /// Un geste sur le direct (`dy` positif : remonter, comme AppKit en défilement naturel).
    func defilerLeDirect(_ dy: Double) {
        let avant = defilementDirect
        defilementDirect.defiler(dy, cache: cacheDirect)
        if defilementDirect != avant { demarrerBoucle() }
    }
    func revenirAuDirect() { defilementDirect.revenirEnBas(); demarrerBoucle() }

    /// La réunion change (le contrôleur la pousse) : à l'arrêt du défilement, ce qu'on relit reste en place quand une phrase arrive.
    func reunionChangee(_ r: ReunionIlot?, annonce: AnnonceReunion?) {
        let avant = miseEnPageDirect().hauteur
        let changement = r != reunion || annonce != annonceReunion
        reunion = r
        annonceReunion = annonce
        let apres = miseEnPageDirect().hauteur
        if apres != avant { defilementDirect.contenuAjoute(apres - avant, cache: cacheDirect) }
        if changement { donneesChangees() }
    }

    // MARK: les annonces

    func contenuReunion(_ v: VueIlot) -> ContenuAnnonce? {
        guard let a = annonceReunion ?? derniereAnnonceReunion else { return nil }
        switch (v, a) {
        case (.reunionPropose, .propose(let app)):
            return ContenuAnnonce(glyphe: GlypheIlot(nom: "video.fill", couleur: CouleursIlot.vert, taille: 19), l1: "Noter cet appel\u{00A0}?",
                                  l2: "\(app) utilise le micro",
                                  droite: .boutons([.init(titre: "Non", etiquette: "Ne pas noter cet appel", action: .reunionRefuser),
                                                    .init(titre: "Noter", style: .noter, etiquette: "Noter cet appel", action: .reunionNoter)]))
        case (.reunionPrepare, .prepare(let etape, let progres)):
            // l'anneau se remplit à la place du symbole, le pourcentage à droite (maquette, étapes 9 et 10)
            return ContenuAnnonce(glyphe: nil, l1: "Note en préparation\u{2026}", l2: etape, droite: .meta(PreparationNote.pourcent(progres)), progres: progres)
        case (.reunionPrete, .prete(_, let titre, let duree, let sansNote)):
            let t = titre.isEmpty ? "Réunion" : titre
            return ContenuAnnonce(glyphe: GlypheIlot(nom: "checkmark.circle.fill", couleur: CouleursIlot.vert, taille: 22), l1: sansNote ? "Transcription prête" : "Note prête",
                                  l2: t + " \u{00B7} " + FormatReunion.duree(duree),
                                  droite: .boutons([.init(titre: "Ouvrir", style: .blanc, etiquette: "Ouvrir la note", action: .reunionOuvrirNote)]))
        case (.reunionMessage, .message(let texte)):
            return ContenuAnnonce(glyphe: GlypheIlot(nom: "exclamationmark.circle.fill", couleur: CouleursIlot.ambre, taille: 21), l1: texte, l2: "Notes de réunion")
        default:
            return nil
        }
    }
}

// MARK: - la réunion repliée (les ailes)

/// Le point rouge et l'onde dans l'aile gauche, le temps dans l'aile droite (en rouge ; gris en pause, l'onde s'endort).
struct ReunionAiles: View {
    @ObservedObject var m: IlotMoteur
    var g: GrilleIlot

    var body: some View {
        let v = VueIlot.reunionCompact
        let r = m.reunion ?? m.derniereReunion
        let c = g.centreAile(v, droite: false)
        let d = g.bordAile(v), l = d - g.hc - 4
        let largeur: CGFloat = 7 + 4 + 18.4
        ZStack(alignment: .topLeading) {
            HStack(spacing: 4) {
                PointReunion(enPause: r.enPause, animer: !m.reduire && !m.statique)
                Group {
                    if m.statique { EgaliseurFixe(teinte: r.enPause ? Color.white.opacity(0.4) : CouleursIlot.rouge, joue: !r.enPause) }
                    else { EgaliseurLecture(teinte: r.enPause ? Color.white.opacity(0.4) : CouleursIlot.rouge, joue: !r.enPause, animer: !m.reduire) }
                }
                .frame(width: 18.4, height: 14)
            }
            .posee(CGRect(x: c - largeur / 2, y: 0, width: largeur, height: g.barre), m.aspect(v, rang: 0), ancre: .center, .center)
            ChronoReunion(m: m, taille: 13)
                .posee(CGRect(x: d - l, y: 0, width: l, height: g.barre), m.aspect(v, rang: 1), ancre: .center, .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(r.enPause ? "Réunion en pause" : "Réunion en cours")
        .accessibilityValue(FormatIlot.chrono(r.temps(a: m.maintenant())))
    }
}

/// Le temps de la réunion (« 12:41 »), rafraîchi une fois par seconde, figé en pause.
struct ChronoReunion: View {
    @ObservedObject var m: IlotMoteur
    var taille: CGFloat
    var body: some View {
        let r = m.reunion ?? m.derniereReunion
        let couleur = r.enPause ? Color.white.opacity(0.55) : Color(hex: 0xFF6961)
        Group {
            if let depuis = r.depuis, !m.statique {
                TimelineView(.periodic(from: depuis, by: 1)) { _ in texte(r, couleur) }
            } else {
                texte(r, couleur)
            }
        }
    }
    private func texte(_ r: ReunionIlot, _ c: Color) -> some View {
        Text(FormatIlot.chrono(r.temps(a: m.maintenant()))).font(.system(size: taille, weight: .semibold).monospacedDigit()).tracking(-0.1)
            .foregroundStyle(c).lineLimit(1).minimumScaleFactor(0.75)
    }
}

/// Le point rouge qui bat doucement (Core Animation : tout tourne dans le serveur d'affichage) ; gris et immobile en pause, immobile avec
/// « Réduire les animations ».
struct PointReunion: View {
    var enPause: Bool
    var animer: Bool
    var cote: CGFloat = 7
    var body: some View {
        Group {
            if animer && !enPause { PouleReunion(couleur: NSColor(CouleursIlot.rouge)) }
            else { Circle().fill(enPause ? Color.white.opacity(0.45) : CouleursIlot.rouge) }
        }
        .frame(width: cote, height: cote)
    }
}

/// Le battement du point (opacité 1 → 0,4 → 1 en 1,4 s), dans un calque : aucune charge pour l'app.
struct PouleReunion: NSViewRepresentable {
    var couleur: NSColor
    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: .zero)
        v.wantsLayer = true
        let c = CALayer()
        c.backgroundColor = couleur.cgColor
        v.layer?.addSublayer(c)
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = 1; a.toValue = 0.4; a.duration = 0.7; a.autoreverses = true; a.repeatCount = .infinity
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        c.add(a, forKey: "pouls")
        return v
    }
    func updateNSView(_ v: NSView, context: Context) {
        guard let c = v.layer?.sublayers?.first else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        c.frame = v.bounds; c.cornerRadius = min(v.bounds.width, v.bounds.height) / 2
        c.backgroundColor = couleur.cgColor
        CATransaction.commit()
    }
}

/// La réunion dans la bulle (une alerte ou une annonce a pris l'îlot) : le point rouge et le temps.
struct PastilleReunion: View {
    @ObservedObject var m: IlotMoteur
    var body: some View {
        let r = m.reunion ?? m.derniereReunion
        HStack(spacing: 6) {
            PointReunion(enPause: r.enPause, animer: !m.reduire && !m.statique)
            ChronoReunion(m: m, taille: 12.5).fixedSize()
        }
        .padding(.leading, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(r.enPause ? "Réunion en pause" : "Réunion en cours")
    }
}

// MARK: - la carte « Réunion »

struct CarteReunion: View {
    @ObservedObject var m: IlotMoteur
    var g: GrilleIlot

    var body: some View {
        let v = VueIlot.reunionEtendu
        ZStack(alignment: .topLeading) {
            // un clic dans le vide de la carte ne la range pas (on visait un bouton) ; seulement tant qu'elle est là
            Color.clear.contentShape(Rectangle()).onTapGesture {}
                .allowsHitTesting(m.courante == v)
                .accessibilityHidden(true)
                .posee(PlanReunion.fond(g))
            EnteteReunion(m: m).posee(PlanReunion.cadreEntete(g), m.aspect(v, rang: 0), ancre: .topLeading)
            DirectReunionVue(m: m, g: g).posee(PlanReunion.direct(g), m.aspect(v, rang: 1), ancre: .top)
            PiedReunion(m: m, g: g).posee(PlanReunion.cadrePied(g), m.aspect(v, rang: 2), ancre: .bottom)
        }
        .frame(width: IlotMoteur.largeur, height: IlotMoteur.hauteurMax, alignment: .topLeading)
    }
}

/// Le point rouge, « Réunion » (ou « En pause »), le temps, l'app de l'appel ; « Centre » à droite.
struct EnteteReunion: View {
    @ObservedObject var m: IlotMoteur
    var body: some View {
        let r = m.reunion ?? m.derniereReunion
        let source = [r.app, r.microSeul ? "Micro seul" : nil].compactMap { $0 }.joined(separator: " \u{00B7} ")
        HStack(spacing: 8) {
            PointReunion(enPause: r.enPause, animer: !m.reduire && !m.statique, cote: 9).padding(.leading, 3)
            Text(r.enPause ? "En pause" : "Réunion").font(.system(size: 13.5, weight: .semibold)).foregroundStyle(.white).lineLimit(1).fixedSize()
            ChronoReunion(m: m, taille: 13.5).fixedSize()
            if !source.isEmpty {
                Text("\u{00B7} " + source).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Color.white.opacity(0.45)).lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: 8)
            PiluleCentre(titre: "Centre", symbole: "square.grid.2x2.fill", etiquette: "Aller au Centre") { m.allerA(.centre) }
        }
        .frame(height: PlanReunion.entete)
    }
}

/// Le direct : les dernières lignes, en bas de la zone ; elles glissent vers le haut quand une phrase arrive. Remonter (molette, deux
/// doigts) arrête le suivi ; « Revenir en bas » (ou redescendre) le reprend. « Ce que j'ai raté » prend la place du direct.
struct DirectReunionVue: View {
    @ObservedObject var m: IlotMoteur
    var g: GrilleIlot

    var body: some View {
        let r = m.reunion ?? m.derniereReunion
        let z = PlanReunion.direct(g)
        ZStack(alignment: .bottomLeading) {
            if r.rattrapage.ouvert {
                RattrapageVue(m: m, etat: r.rattrapage, largeur: z.width)
                    .frame(width: z.width, height: z.height, alignment: .topLeading)
                    .transition(.opacity)
            } else {
                liste(z)
                    .transition(.opacity)
            }
        }
        .frame(width: z.width, height: z.height, alignment: .bottomLeading)
        .animation(m.reduire || m.statique ? nil : .easeOut(duration: 0.22), value: r.rattrapage.ouvert)
    }

    @ViewBuilder private func liste(_ z: CGRect) -> some View {
        let p = m.miseEnPageDirect()
        let decalage = CGFloat(min(m.defilementDirect.decalage, m.cacheDirect))
        ZStack(alignment: .bottomLeading) {
            if p.elements.isEmpty {
                Text("J\u{2019}écoute\u{2026} les phrases arrivent ici.").font(Polices.texte(PlanReunion.policeTexte)).foregroundStyle(Color.white.opacity(0.45))
                    .lineLimit(1).padding(.leading, PlanReunion.colonneQui + PlanReunion.ecartQui).padding(.bottom, 4)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(p.elements, id: \.ligne.id) { e in
                        LigneDirectVue(ligne: e.ligne, largeur: z.width).frame(width: z.width, height: CGFloat(e.h), alignment: .topLeading)
                            .transition(.opacity)
                    }
                }
                .frame(width: z.width, height: CGFloat(p.hauteur), alignment: .topLeading)
                .offset(y: decalage)
                .animation(m.reduire || m.statique ? nil : .spring(response: 0.42, dampingFraction: 0.9), value: p.hauteur)
            }
        }
        .frame(width: z.width, height: z.height, alignment: .bottomLeading)
        .clipped()
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: PlanReunion.fondu / z.height), .init(color: .black, location: 1)],
                             startPoint: .top, endPoint: .bottom))
        .overlay(alignment: .bottomTrailing) {
            if !m.defilementDirect.suit, m.directDefile {
                Button { m.revenirAuDirect() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                        Text("Revenir en bas").font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.white).padding(.horizontal, 10).frame(height: 24)
                    .background(Capsule().fill(Color(white: 0.2)))
                    .contentShape(Capsule())
                }
                .buttonStyle(AppuiIlot(echelle: 0.92))
                .accessibilityLabel("Revenir aux dernières phrases")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Transcription en direct")
    }
}

/// Une ligne du direct : « Moi » (ambre) ou « Eux » (gris), discrets à gauche ; le texte en Newsreader, le sûr en blanc, le reste en
/// gris clair, « … » tant que la voix parle encore. Un point marqué : « ⚑ Point ajouté · 14:15 » en ambre.
struct LigneDirectVue: View {
    var ligne: LigneDirect
    var largeur: CGFloat

    var body: some View {
        if ligne.estPoint {
            HStack(spacing: 6) {
                Image(systemName: "flag.fill").font(.system(size: 10.5, weight: .semibold))
                Text("Point ajouté \u{00B7} " + (ligne.morceaux.first?.texte ?? "")).font(.system(size: 12, weight: .semibold)).lineLimit(1).fixedSize()
            }
            .foregroundStyle(Color(hex: 0xFFB340))
            .padding(.leading, 8).padding(.trailing, 10).frame(height: 22)
            .background(Capsule().fill(CouleursIlot.ambre.opacity(0.16)))
            .padding(.leading, PlanReunion.colonneQui + PlanReunion.ecartQui).padding(.vertical, 2)
            .accessibilityElement(children: .combine)
        } else {
            let moi = ligne.locuteur == .moi
            HStack(alignment: .firstTextBaseline, spacing: PlanReunion.ecartQui) {
                Text(moi ? "Moi" : "Eux").font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(moi ? Color(hex: 0xFFB340).opacity(0.8) : Color.white.opacity(0.4))
                    .frame(width: PlanReunion.colonneQui, alignment: .leading)
                texte.font(Polices.texte(PlanReunion.policeTexte)).lineSpacing(LigneDicteeIlot.interligne)
                    .frame(width: largeur - PlanReunion.colonneQui - PlanReunion.ecartQui, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)
            .accessibilityLabel((moi ? "Moi : " : "Eux : ") + ligne.texte)
        }
    }

    private var texte: Text {
        let blanc = Color.white.opacity(0.86), gris = Color.white.opacity(0.4)
        var t = Text("")
        for (i, mo) in ligne.morceaux.enumerated() {
            t = t + Text((i > 0 ? " " : "") + mo.texte).foregroundColor(mo.sur ? blanc : gris)
        }
        if ligne.suite || ligne.morceaux.isEmpty { t = t + Text(ligne.morceaux.isEmpty ? "\u{2026}" : " \u{2026}").foregroundColor(gris) }
        return t
    }
}

/// « Ce que j'ai raté » : le titre et « Retour au direct » ; trois lignes qui luisent pendant que le résumé se fait ; puis deux ou trois
/// puces ; ou une phrase simple si rien n'a pu être résumé.
struct RattrapageVue: View {
    @ObservedObject var m: IlotMoteur
    var etat: EtatRattrapage
    var largeur: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text("Ces 3 dernières minutes").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.white.opacity(0.5))
                Spacer(minLength: 8)
                Button { m.surAction(.reunionDirect) } label: {
                    HStack(spacing: 3) {
                        Text("Retour au direct").font(.system(size: 12.5, weight: .semibold))
                        Image(systemName: "chevron.right").font(.system(size: 9.5, weight: .bold))
                    }
                    .foregroundStyle(Color.white.opacity(0.75)).frame(height: 20).contentShape(Rectangle())
                }
                .buttonStyle(AppuiIlot(echelle: 0.94))
                .accessibilityLabel("Retour au direct")
            }
            .frame(height: 20)
            switch etat {
            case .enCours:
                VStack(alignment: .leading, spacing: 12) {
                    ForEach([0.92, 0.78, 0.64], id: \.self) { f in
                        LueurIlot(animer: !m.reduire && !m.statique).frame(width: largeur * f, height: 11)
                    }
                }
                .padding(.top, 12)
                .accessibilityLabel("Résumé en cours")
            case .pret(let puces):
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(puces.enumerated()), id: \.offset) { _, p in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Circle().fill(Color.white.opacity(0.5)).frame(width: 5, height: 5).alignmentGuide(.firstTextBaseline) { d in d[.bottom] + 4 }
                            Text(p).font(.system(size: 13.5, weight: .regular)).foregroundStyle(Color.white.opacity(0.92))
                                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, 8).padding(.leading, 2)
            case .echec(let phrase):
                Text(phrase).font(.system(size: 13.5)).foregroundStyle(Color.white.opacity(0.6)).padding(.top, 8)
            case .ferme:
                EmptyView()
            }
        }
    }
}

/// Une ligne qui luit (le résumé arrive) ; immobile avec « Réduire les animations » et dans les rendus.
struct LueurIlot: View {
    var animer: Bool
    @State private var phase = false
    var body: some View {
        Capsule().fill(Color.white.opacity(animer ? (phase ? 0.17 : 0.08) : 0.12))
            .onAppear { if animer { withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) { phase = true } } }
    }
}

/// « Ce que j'ai raté », « Ajouter un point » (« Point ajouté » un instant), pause (ou reprise), Arrêter.
struct PiedReunion: View {
    @ObservedObject var m: IlotMoteur
    var g: GrilleIlot

    var body: some View {
        let r = m.reunion ?? m.derniereReunion
        let p = PlanReunion.pied(g), c = PlanReunion.cadrePied(g)
        ZStack(alignment: .topLeading) {
            BoutonReunion(titre: PlanReunion.titreRate, symbole: "clock.arrow.circlepath", glyphe: p.glyphes, style: r.rattrapage.ouvert ? .actif : .normal,
                          etiquette: r.rattrapage.ouvert ? "Fermer le résumé des dernières minutes" : "Ce que j\u{2019}ai raté : les 3 dernières minutes") {
                m.surAction(r.rattrapage.ouvert ? .reunionDirect : .reunionRattrapage)
            }
            .frame(width: p.rate.width, height: p.rate.height).offset(x: p.rate.minX - c.minX)
            BoutonReunion(titre: r.pointFait ? PlanReunion.titrePointFait : PlanReunion.titrePoint, symbole: "flag.fill", glyphe: p.glyphes, style: r.pointFait ? .fait : .normal,
                          etiquette: "Ajouter un point à ce moment") { m.surAction(.reunionPoint) }
                .frame(width: p.point.width, height: p.point.height, alignment: .leading).offset(x: p.point.minX - c.minX)
            Button { m.surAction(r.enPause ? .reunionReprendre : .reunionPause) } label: {
                Image(systemName: r.enPause ? "play.fill" : "pause.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                    .frame(width: PlanReunion.rond, height: PlanReunion.rond)
                    .background(Circle().fill(Color.white.opacity(0.12)))
                    .contentShape(Circle())
            }
            .buttonStyle(AppuiIlot(echelle: 0.88))
            .accessibilityLabel(r.enPause ? "Reprendre la réunion" : "Mettre la réunion en pause")
            .offset(x: p.pause.minX - c.minX)
            Button { m.surAction(.reunionArreter) } label: {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous).fill(.white).frame(width: 9, height: 9)
                    Text(PlanReunion.titreArret).font(.system(size: PlanReunion.policeBouton, weight: .semibold)).foregroundStyle(.white).lineLimit(1).fixedSize()
                }
                .padding(.leading, 12).padding(.trailing, 13)
                .frame(width: p.arret.width, height: PlanReunion.pied)
                .background(Capsule().fill(CouleursIlot.rouge))
                .contentShape(Capsule())
            }
            .buttonStyle(AppuiIlot(echelle: 0.92))
            .accessibilityLabel("Arrêter la réunion et préparer la note")
            .offset(x: p.arret.minX - c.minX)
        }
        .frame(width: c.width, height: c.height, alignment: .topLeading)
    }
}

/// Un bouton de la rangée du bas : gris, blanc quand « Ce que j'ai raté » est ouvert, ambre quand le point vient d'être ajouté.
struct BoutonReunion: View {
    enum Style { case normal, actif, fait }
    var titre: String
    var symbole: String
    var glyphe: Bool
    var style: Style
    var etiquette: String
    var action: () -> Void
    @State private var survol = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: PlanReunion.espaceGlyphe) {
                if glyphe { Image(systemName: symbole).font(.system(size: 12, weight: .semibold)).frame(width: PlanReunion.glyphe) }
                Text(titre).font(.system(size: PlanReunion.policeBouton, weight: .semibold)).lineLimit(1).fixedSize()
            }
            .foregroundStyle(style == .actif ? Color.black : (style == .fait ? Color(hex: 0xFFB340) : .white))
            .padding(.leading, glyphe ? 10 : 12).padding(.trailing, 12)
            .frame(height: PlanReunion.pied)
            .background(Capsule().fill(fond))
            .contentShape(Capsule())
        }
        .buttonStyle(AppuiIlot(echelle: 0.93))
        .onHover { survol = $0 }
        .animation(.easeOut(duration: 0.15), value: style)
        .accessibilityLabel(etiquette)
    }
    private var fond: Color {
        switch style {
        case .normal: return Color.white.opacity(survol ? 0.2 : 0.12)
        case .actif: return Color.white.opacity(survol ? 0.88 : 1)
        case .fait: return CouleursIlot.ambre.opacity(0.2)
        }
    }
}

/// « Note en préparation… » : une barre blanche qui se remplit sur un fond gris. Elle avance par paliers (un lot relu, une partie
/// rédigée) : une courte animation entre deux paliers, aucune avec « Réduire les animations ».
struct BarrePreparation: View {
    var progres: Double
    var animer: Bool
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.16))
                Capsule().fill(Color.white).frame(width: max(6, g.size.width * min(1, max(0, progres))))
                    .animation(animer ? .easeOut(duration: 0.35) : nil, value: progres)
            }
        }
        .accessibilityHidden(true)
    }
}
