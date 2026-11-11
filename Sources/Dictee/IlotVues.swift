import AppKit
import SwiftUI
import DicteeCore

// Les écrans de l'îlot (maquette design/maquettes/ilot-pro-A.html). Un seul objet noir qui change de forme :
// - ce qui existe déjà VOYAGE (la pochette, l'anneau et l'heure du minuteur, la cloche, le calendrier : une seule pièce qui grandit
//   et glisse à sa place) ;
// - ce qui est nouveau arrive APRÈS la forme (fondu, flou, zoom 0,92 → 1, un bloc toutes les 35 ms) et repart AVANT elle.
// Tout est posé sur une grille mesurée sur la vraie caméra et la vraie barre : marge de 16 pt tout autour du corps, ailes serrées
// contre la caméra. Les lignes de texte vivent dans des piles (HStack/VStack) : jamais de chevauchement, jamais de texte rogné.

/// La grille de l'îlot, mesurée sur la vraie caméra (`hc` = demi-caméra) et la vraie barre des menus.
struct GrilleIlot {
    var hc: CGFloat
    var barre: CGFloat
    /// Largeur mesurée du contenu des écrans qui l'épousent (bandeaux, alertes, rendez-vous déplié) : la forme et la grille suivent.
    var contenus: [VueIlot: CGFloat] = [:]
    /// Les épaules sont ouvertes (batterie, écouteurs) : le cou des écrans dépliés passe à 60 pt.
    var epaules = false
    /// Ce qu'un contenu variable ajoute à la hauteur d'un écran (la ligne de l'étagère dans l'accueil, une 2e rangée de fichiers).
    var enPlus: [VueIlot: CGFloat] = [:]
    /// Le pied (bouton « Centre ») ajouté sous le déplié d'une activité (`CartesIlot.piedEnPlus`) : la forme le compte, la zone du
    /// contenu non (le contenu garde sa place, le pied se pose dessous).
    var pieds: [VueIlot: CGFloat] = [:]
    static let marge = CGFloat(GeoIlot.marge)
    private func f(_ v: VueIlot) -> [Double] {
        GeoIlot.valeurs(v, hauteurBarre: Double(barre), demiCamera: Double(hc), contenu: contenus[v].map(Double.init), epaules: epaules,
                        enPlus: Double((enPlus[v] ?? 0) + (pieds[v] ?? 0)))
    }
    /// Demi-largeur du corps (sous la barre) et du cou (dans la barre), depuis le centre.
    func corps(_ v: VueIlot) -> CGFloat { hc + CGFloat(f(v)[1]) }
    func cou(_ v: VueIlot) -> CGFloat { hc + CGFloat(f(v)[0]) }
    func hauteur(_ v: VueIlot) -> CGFloat { CGFloat(f(v)[2]) }
    /// Zone du contenu d'un écran déplié : le corps sous la barre, moins la marge.
    func zone(_ v: VueIlot, haut: CGFloat = 16, bas: CGFloat = 16) -> CGRect {
        let w = corps(v)
        return CGRect(x: -w + Self.marge, y: barre + haut, width: 2 * w - 2 * Self.marge, height: hauteur(v) - barre - haut - bas - (pieds[v] ?? 0))
    }
    /// La zone d'une annonce : exactement la largeur de son contenu, centrée. Elle ne diffère de `zone` que si le contenu est plus
    /// étroit que le corps le plus serré (un « Fait » de deux mots) : le bloc est alors centré, jamais collé à gauche devant du vide.
    func zoneAnnonce(_ v: VueIlot, haut: CGFloat = 16, bas: CGFloat = 16) -> CGRect {
        let z = zone(v, haut: haut, bas: bas)
        guard let c = contenus[v], c < z.width else { return z }
        return z.insetBy(dx: ((z.width - c) / 2).rounded(), dy: 0)
    }
    /// Milieu d'une aile (entre la caméra et le cou) d'un écran compact.
    func centreAile(_ v: VueIlot, droite: Bool) -> CGFloat { let c = (hc + cou(v)) / 2; return droite ? c : -c }
    /// Bord extérieur utile d'une aile : 8 pt en deçà du cou (concentrique avec le coin).
    func bordAile(_ v: VueIlot) -> CGFloat { cou(v) - 8 }
}

enum TexteIlot {
    static let titre = Font.system(size: 16.5, weight: .semibold)
    static let l1 = Font.system(size: 17, weight: .semibold)
    static let ligne = Font.system(size: 15, weight: .semibold)
    static let l2 = Font.system(size: 12.5, weight: .medium)
    static let source = Font.system(size: 13, weight: .medium)
    static let extrait = Font.system(size: 13.5, weight: .medium)
}

extension View {
    /// Pose un élément : son cadre `r` (points depuis le centre, en haut), son aspect d'apparition, puis le décalage dans la zone de dessin.
    func posee(_ r: CGRect, _ a: AspectIlot = .visible, ancre: UnitPoint = .top, _ al: Alignment = .topLeading) -> some View {
        frame(width: max(0, r.width), height: max(0, r.height), alignment: al)
            .aspectIlot(a, ancre: ancre)
            .offset(x: IlotMoteur.largeur / 2 + r.minX, y: r.minY)
    }
}

private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat { a + (b - a) * CGFloat(t) }
private func borne(_ v: Double, _ a: Double = 0, _ b: Double = 1) -> Double { min(b, max(a, v)) }

/// Le cadre d'une pièce qui voyage, selon l'ouverture `p` (0 replié → 1 déplié, un peu plus au rebond). La descente mène, la taille
/// suit, le glissement de côté vient en dernier (maquette) : la pièce ne passe jamais sous la caméra ni hors de la forme.
func voyageIlot(_ a: CGRect, _ b: CGRect, _ p: Double) -> (cadre: CGRect, taille: Double) {
    let q = borne(p), over = max(0, p - 1)
    let ty = 1 - pow(1 - q, 3) + over
    let ts = pow(borne((q - 0.15) / 0.85), 1.1) + over
    let tx = pow(q, 1.4) + over
    return (CGRect(x: lerp(a.minX, b.minX, tx), y: lerp(a.minY, b.minY, ty), width: lerp(a.width, b.width, ts), height: lerp(a.height, b.height, ts)), ts)
}

extension LectureModele {
    /// Une miniature de vidéo (16:9) plutôt qu'une pochette carrée.
    var pochetteLarge: Bool {
        guard let i = image, i.size.height > 0 else { return false }
        return i.size.width / i.size.height > 1.3
    }
}

/// Tous les écrans, chacun avec son horloge d'apparition ; la forme noire les rogne.
struct IlotCalques: View {
    @ObservedObject var m: IlotMoteur
    var g: GrilleIlot

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            if m.visible(FamilleIlot.lecture) { LectureVoyageurs(m: m, lecture: m.lecture, g: g) }
            if m.visible(FamilleIlot.minuteur) { voyageursMinuteur }
            if m.visible(FamilleIlot.rappel) { voyageurGlyphe(.rappel) }
            if m.visible(FamilleIlot.agenda) { voyageurGlyphe(.agenda) }
            if m.visible(FamilleIlot.micro) { voyageurGlyphe(.micro) }
            if m.visible(FamilleIlot.claude) { ClaudeVoyageur(m: m, g: g) }
            if m.epaules, m.ouvertureEpaules > 0.001 { EpaulesIlot(m: m, g: g) }
            ForEach(VueIlot.allCases, id: \.self) { v in
                if m.visible(v) { ecran(v) }
            }
            // ce qui s'ajoute aux écrans : le pied de la lecture (bouton « Centre »), les points de page, la bulle « Nouveau »
            if m.visible(ExtraIlot.pied) { PiedCarte(m: m, g: g, v: m.carteDuPied) }
            if m.visible(ExtraIlot.points) { PointsCartes(m: m, g: g) }
            if m.visible(ExtraIlot.bulle) { BulleNouveau(m: m, g: g) }
        }
        .frame(width: IlotMoteur.largeur, height: IlotMoteur.hauteurMax, alignment: .topLeading)
    }

    @ViewBuilder private func ecran(_ v: VueIlot) -> some View {
        switch v {
        case .repos, .lectureCompact, .minuteurMinimal, .minuteurCompact: EmptyView()
        case .lectureEtendu: LectureEtendue(m: m, lecture: m.lecture, g: g)
        case .lectureMinuteur: rangeeMinuteurLecture
        case .minuteurEtendu: minuteurEtendu
        case .minuteurLance, .minuteurFini, .rappelEtendu, .rappelAjoute, .rappelFait, .rappelReporte, .agendaAvant, .agendaDebut,
             .notification, .notifications:
            if let c = m.contenuAnnonce(v) { annonce(v, c) }
        case .rappelCompact: heureAile(.rappelCompact, FormatIlot.heure(m.rappelVu?.echeance ?? m.maintenant()), CouleursIlot.jaune)
        case .rappelListe: rappelListe
        case .agendaCompact:
            TimelineView(.periodic(from: Date(timeIntervalSinceReferenceDate: 0), by: 15)) { _ in
                heureAile(.agendaCompact, m.rdvVu.map { PlanAgenda.court($0.debut.timeIntervalSince(m.maintenant())) } ?? "", .white)
            }
        case .agendaEtendu: agendaEtendu
        case .accueil: accueil
        case .appareil, .telecharge: if let c = m.contenuAnnonce(v) { annonce(v, c) }
        case .batterieCharge, .batterieFaible: energieAiles(v)
        case .microCompact: heureAile(v, "Coupé", CouleursIlot.rouge).accessibilityLabel("Micro coupé")
        case .microEtendu: if let c = m.contenuAnnonce(v) { annonce(v, c) }
        case .microOuvert: microOuvert(v)
        case .volume, .luminosite: niveauAiles(v)
        case .claudeMinimal: EmptyView()
        case .claudeCompact: ClaudeAiles(m: m, g: g)
        case .claudeEtendu, .claudeAttend, .claudeTermine: if let c = m.contenuAnnonce(v) { annonce(v, c) }
        case .etagereDepot: DepotEtagere(m: m, g: g)
        case .etagere: CarteEtagere(m: m, g: g)
        case .etagerePile: PileEtagere(m: m, g: g)
        case .etagereAppel: AppelEtagere(m: m, g: g)
        case .etagereEnvoi, .etagerePartis: if let c = m.contenuAnnonce(v) { annonce(v, c) }
        case .centre: CentreVue(m: m, g: g)
        case .dictees: DicteesCarte(m: m, d: m.dictees, g: g)
        }
    }

    /// Volume et luminosité : le haut-parleur (ou le soleil) dans l'aile gauche, une barre fine dans l'aile droite qui suit la valeur
    /// sur son ressort. Le haut-parleur est calé à gauche dans la place de sa version la plus large (trois ondes) : quand les ondes
    /// changent, le corps du haut-parleur ne bouge pas.
    private func niveauAiles(_ v: VueIlot) -> some View {
        let genre: GenreNiveau = v == .volume ? .volume : .luminosite
        let n = m.niveauVu(genre)
        let c = g.centreAile(v, droite: false)
        let place = genre == .volume ? MesureIlot.symbole("speaker.wave.3.fill", 15) : 36
        let (x, l) = JaugeNiveau.barre(demiCamera: Double(g.hc), cou: Double(g.cou(v) - g.hc))
        return ZStack(alignment: .topLeading) {
            Image(systemName: n.symbole).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                .posee(CGRect(x: c - place / 2, y: 0, width: place, height: g.barre), m.aspect(v, rang: 0), ancre: .center,
                       genre == .volume ? .leading : .center)
            BarreNiveau(valeur: m.jauge(genre).x, largeur: CGFloat(l))
                .posee(CGRect(x: CGFloat(x), y: 0, width: CGFloat(l), height: g.barre), m.aspect(v, rang: 1), ancre: .leading, .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(genre == .volume ? (n.muet ? "Son coupé" : "Volume") : "Luminosité")
        .accessibilityValue(n.muet ? "" : "\(n.pourcent) %")
    }

    /// Le micro rouvert : le micro (sans barre) dans l'aile gauche, « Ouvert » dans l'aile droite, en vert, le temps d'un coup d'œil.
    private func microOuvert(_ v: VueIlot) -> some View {
        let c = g.centreAile(v, droite: false)
        return ZStack(alignment: .topLeading) {
            Image(systemName: "mic.fill").font(.system(size: 15, weight: .semibold)).foregroundStyle(CouleursIlot.vert)
                .posee(CGRect(x: c - 18, y: 0, width: 36, height: g.barre), m.aspect(v, rang: 0), ancre: .center, .center)
            heureAile(v, "Ouvert", CouleursIlot.vert)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Micro ouvert")
    }

    /// Chargeur branché, batterie faible : la pile dans l'aile gauche, le pourcentage dans l'aile droite, en vert ou en rouge.
    private func energieAiles(_ v: VueIlot) -> some View {
        let e = m.energie ?? m.bandeauVu?.energie ?? EnergieIlot(pourcent: 0, secteur: false, enCharge: false)
        let couleur = v == .batterieCharge ? CouleursIlot.vert : CouleursIlot.rouge
        let c = g.centreAile(v, droite: false)
        return ZStack(alignment: .topLeading) {
            Group {
                if v == .batterieCharge { Image(systemName: "bolt.fill").font(.system(size: 14, weight: .semibold)).foregroundStyle(couleur) }
                else { PileIlot(pourcent: e.pourcent, secteur: false, chiffres: false, echelle: 1.15) }
            }
            .posee(CGRect(x: c - 18, y: 0, width: 36, height: g.barre), m.aspect(v, rang: 0), ancre: .center, .center)
            heureAile(v, e.texte, couleur)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(v == .batterieCharge ? "En charge, \(e.pourcent) %" : "Batterie faible, \(e.pourcent) %")
    }

    // MARK: lignes d'annonce (bandeaux et alertes)

    /// Une annonce sur une ligne : [symbole] [titre / sous-titre] [actions]. Les trois blocs arrivent l'un après l'autre. La forme a
    /// la largeur de ce contenu (`IlotMoteur.largeurContenu`, même description `ContenuAnnonce`) : rien n'est tassé à gauche.
    /// Symbole nil : la place est gardée pour une pièce qui voyage (la cloche).
    private func annonce(_ v: VueIlot, _ c: ContenuAnnonce) -> some View {
        let z = g.zoneAnnonce(v, haut: v.estAlerte ? 20 : 16, bas: v.estAlerte ? 20 : 16)
        return HStack(spacing: ContenuAnnonce.espace) {
            Group {
                if !c.icones.isEmpty { IconesFichiers(icones: c.icones, cote: c.coteSymbole) }
                else if c.etoile { EtoileClaude(couleur: CouleursIlot.corail).frame(width: 21, height: 21) }
                else if let glyphe = c.glyphe { glyphe } else { Color.clear }
            }
            .frame(width: c.coteSymbole, height: c.coteSymbole)
            .glisserFichier(c.glisser, m)
            .aspectIlot(m.aspect(v, rang: 0), ancre: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(c.l1).font(TexteIlot.l1).tracking(ContenuAnnonce.interlettreL1).foregroundStyle(.white).lineLimit(1).truncationMode(c.coupureL1)
                c.texteL2.font(TexteIlot.l2).foregroundStyle(c.couleurL2 ?? CouleursIlot.encre2).lineLimit(1).truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glisserFichier(c.glisser, m)
            .aspectIlot(m.aspect(v, rang: 1), ancre: .topLeading)
            switch c.droite {
            case .rien: EmptyView()
            case .meta(let t): meta(t).fixedSize().aspectIlot(m.aspect(v, rang: 2), ancre: .topTrailing)
            case .temps:
                tic { d in Text(tempsRestant(d)).font(ContenuAnnonce.policeTemps).foregroundStyle(CouleursIlot.ambre) }
                    .fixedSize().aspectIlot(m.aspect(v, rang: 2), ancre: .topTrailing)
            case .jauges(let js):
                HStack(spacing: ContenuAnnonce.espaceJauges) {
                    ForEach(Array(js.enumerated()), id: \.offset) { _, j in JaugeIlot(jauge: j) }
                }
                .fixedSize().aspectIlot(m.aspect(v, rang: 2), ancre: .topTrailing)
            case .boutons(let bs):
                HStack(spacing: ContenuAnnonce.espaceBoutons) {
                    ForEach(Array(bs.enumerated()), id: \.offset) { _, b in
                        CapIlot(titre: b.titre, icone: b.icone, style: b.style, etiquette: b.etiquette) { if let a = b.action { m.surAction(a) } }
                    }
                }
                .fixedSize().aspectIlot(m.aspect(v, rang: 2), ancre: .topTrailing)
            }
            if c.attente {
                RouetIlot(anime: !m.reduire && !m.statique).frame(width: ContenuAnnonce.coteRouet, height: ContenuAnnonce.coteRouet)
                    .aspectIlot(m.aspect(v, rang: 2), ancre: .center)
            }
            if let k = c.compte {
                AnneauCompte(fin: k.fin, duree: k.duree, maintenant: m.maintenant)
                    .padding(.leading, ContenuAnnonce.espaceBoutons - ContenuAnnonce.espace)
                    .aspectIlot(m.aspect(v, rang: 3), ancre: .center)
            }
        }
        .frame(width: z.width, height: z.height)
        .offset(x: IlotMoteur.largeur / 2 + z.minX, y: z.minY)
    }
    private func meta(_ s: String) -> some View {
        Text(s).font(ContenuAnnonce.policeMeta).foregroundStyle(CouleursIlot.encre2).lineLimit(1)
    }
    /// Une heure ou une durée dans l'aile droite d'un compact, calée sur le bord extérieur (8 pt du coin).
    private func heureAile(_ v: VueIlot, _ s: String, _ c: Color) -> some View {
        let d = g.bordAile(v), l = d - g.hc - 4
        return Text(s).font(.system(size: 13, weight: .semibold).monospacedDigit()).tracking(-0.1).foregroundStyle(c)
            .lineLimit(1).minimumScaleFactor(0.75)
            .posee(CGRect(x: d - l, y: 0, width: l, height: g.barre), m.aspect(v, rang: 0), ancre: .center, .trailing)
    }

    // MARK: minuteur

    private var mn: MinuteurIlot { m.minuteur ?? m.dernierMinuteur }
    /// Un contenu qui se met à jour à chaque seconde du minuteur (une fois par seconde, jamais plus).
    private func tic<Contenu: View>(@ViewBuilder _ contenu: @escaping (Date) -> Contenu) -> some View {
        TimelineView(.periodic(from: m.minuteur?.echeance ?? Date(timeIntervalSinceReferenceDate: 0), by: 1)) { ctx in contenu(ctx.date) }
    }
    private func tempsRestant(_ d: Date) -> String {
        FormatIlot.duree(m.minuteur == nil ? mn.restant(a: d) : mn.restant(a: m.maintenant()))
    }

    private var cadreAnneauEtendu: CGRect {
        let w = g.corps(.minuteurEtendu)
        return CGRect(x: -w + GrilleIlot.marge, y: g.barre + 23.5, width: 44, height: 44)
    }

    /// L'anneau (aile gauche → bouton pause) et le temps restant (aile droite → gros chiffres à droite) : ils voyagent.
    private var voyageursMinuteur: some View {
        let p = m.ouverture(.minuteur)
        let a = m.aspect(FamilleIlot.minuteur)
        let c = g.centreAile(m.courante == .minuteurMinimal ? .minuteurMinimal : .minuteurCompact, droite: false)
        let anneauC = CGRect(x: c - 8.5, y: g.barre / 2 - 8.5, width: 17, height: 17)
        let (r, ts) = voyageIlot(anneauC, cadreAnneauEtendu, p)
        // le temps : 13 pt dans l'aile, 40 pt déplié ; le bord droit glisse de l'aile vers la marge du corps
        let q = borne(p, 0, 1.1)
        let ty = 1 - pow(1 - borne(q), 3) + max(0, q - 1)
        let tsT = pow(borne((q - 0.15) / 0.85), 1.1) + max(0, q - 1)
        let fs = lerp(13, 40, tsT), lh = fs * 1.2
        let dC = g.bordAile(.minuteurCompact), dX = g.corps(.minuteurEtendu) - GrilleIlot.marge
        let d = lerp(dC, dX, pow(borne(q), 1.4))
        let haut = lerp(g.barre / 2 - lh / 2, g.barre + 31, ty)
        return ZStack(alignment: .topLeading) {
            tic { _ in AnneauIlot(taille: r.width, trait: lerp(2.2, 3, borne(ts)), couleur: CouleursIlot.ambre, fraction: mn.fraction(a: m.maintenant()), enPause: mn.enPause) {} }
                .posee(r, a, ancre: .center)
            if m.courante != .minuteurMinimal {
                tic { d in
                    // VoiceOver lit « Temps restant, 6:32 » : la valeur, pas seulement le nom
                    Text(tempsRestant(d)).font(.system(size: 40, weight: .semibold).monospacedDigit()).tracking(-0.4)
                        .foregroundStyle(CouleursIlot.ambre).lineLimit(1).fixedSize()
                        .accessibilityLabel("Temps restant").accessibilityValue(tempsRestant(d))
                }
                .frame(width: 160, height: 48, alignment: .trailing)
                .scaleEffect(fs / 40, anchor: .topTrailing)
                .opacity(a.opacite).blur(radius: a.flou)
                .offset(x: IlotMoteur.largeur / 2 + d - 160, y: haut)
            }
        }
    }

    private var minuteurEtendu: some View {
        let v = VueIlot.minuteurEtendu
        let w = g.corps(v), z = g.zone(v)
        let r = cadreAnneauEtendu
        return ZStack(alignment: .topLeading) {
            tic { _ in
                Text(mn.enPause ? "En pause \u{00B7} " + FormatIlot.minutes(mn.total) : FormatIlot.minutes(mn.total) + " \u{00B7} fin à " + FormatIlot.heure(mn.heureDeFin(a: m.maintenant())))
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(CouleursIlot.encre2).lineLimit(1).truncationMode(.head)
            }
            .posee(CGRect(x: -w + 206, y: g.barre + 15, width: z.maxX - (-w + 206), height: 16), m.aspect(v, rang: 0), ancre: .topTrailing, .trailing)
            RondIlot(symbole: mn.enPause ? "play.fill" : "pause.fill", ambre: true, etiquette: mn.enPause ? "Reprendre" : "Pause") { m.surAction(.minuteurBasculer) }
                .posee(r, m.aspect(v, rang: 1), ancre: .center)
            RondIlot(symbole: "xmark", etiquette: "Arrêter le minuteur") { m.surAction(.minuteurArreter) }
                .posee(r.offsetBy(dx: 54, dy: 0), m.aspect(v, rang: 2), ancre: .center)
            CapIlot(titre: "1 min", icone: "plus", etiquette: "Ajouter une minute") { m.surAction(.minuteurPlusUneMinute) }
                .posee(CGRect(x: r.minX + 108, y: r.midY - 16, width: 86, height: 32), m.aspect(v, rang: 3), ancre: .topLeading)
        }
    }

    // MARK: rappels

    /// La cloche (rappel), le calendrier (rendez-vous) ou le micro barré : dans l'aile gauche au repos, à sa place dans l'annonce une
    /// fois déplié.
    private func voyageurGlyphe(_ f: FamilleIlot) -> some View {
        let p = m.ouverture(f)
        let a = m.aspect(f)
        let (vc, vx) = f.vues!
        let c = g.centreAile(vc, droite: false)
        let compact = CGRect(x: c - 13, y: g.barre / 2 - 13, width: 26, height: 26)
        let z = f == .rappel ? g.zoneAnnonce(vx, haut: 20, bas: 20) : (f == .micro ? g.zoneAnnonce(vx) : g.zone(vx))
        let etendu = CGRect(x: z.minX, y: f == .agenda ? z.minY - 2 : z.midY - 13, width: 26, height: 26)
        let (r, ts) = voyageIlot(compact, etendu, p)
        let echelle = lerp(15.0 / 22.0, 1, ts)
        // la cloche se secoue à chaque rappel qui SONNE (alerte), même si elle était déjà dans l'aile ; jamais au simple survol
        let sonne = m.alerte?.vue == .rappelEtendu ? m.alerte?.rappel?.id : nil
        return Group {
            if f == .rappel {
                ClocheSecouee(taille: 22, sonnerie: m.reduire || m.statique ? nil : sonne)
            } else if f == .micro {
                GlypheIlot(nom: "mic.slash.fill", couleur: CouleursIlot.rouge, taille: 22)
            } else {
                GlypheIlot(nom: GlypheIlot.calendrier, couleur: CouleursIlot.rouge, taille: 22)
            }
        }
        .scaleEffect(echelle)
        .posee(r, a, ancre: .center, .center)
    }

    private var rappelListe: some View {
        let v = VueIlot.rappelListe
        let z = g.zone(v, haut: 10, bas: 12)
        let liste = Array(m.rappelsAVenir.prefix(2))
        return VStack(spacing: 0) {
            if liste.isEmpty {
                Text("Aucun rappel pour l\u{2019}instant.").font(.system(size: 14, weight: .medium)).foregroundStyle(CouleursIlot.encre3)
                    .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                    .overlay(alignment: .bottom) { filet }
                    .aspectIlot(m.aspect(v, rang: 0), ancre: .topLeading)
            }
            ForEach(Array(liste.enumerated()), id: \.element.id) { i, r in
                LigneRappel(rappel: r) { m.surAction(.rappelFait(r.id)) }
                    .overlay(alignment: .bottom) { filet }
                    .aspectIlot(m.aspect(v, rang: i), ancre: .topLeading)
            }
            HStack(spacing: 12) {
                GlypheIlot(nom: "mic.fill", couleur: CouleursIlot.jaune, taille: 14).frame(width: 18)
                Text("Dis \u{00AB}\u{00A0}appeler Paul à 15 h\u{00A0}\u{00BB} en tenant fn").font(.system(size: 13, weight: .medium)).foregroundStyle(CouleursIlot.encre2).lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(height: 38)
            .aspectIlot(m.aspect(v, rang: 2), ancre: .topLeading)
            Spacer(minLength: 0)
        }
        .frame(width: z.width, height: z.height, alignment: .top)
        .offset(x: IlotMoteur.largeur / 2 + z.minX, y: z.minY)
    }
    private var filet: some View { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }

    // MARK: agenda

    /// Le rendez-vous déplié : le corps a la largeur de son contenu, et les actions forment une rangée de pilules de même largeur
    /// qui va jusqu'à la marge droite (comme les boutons d'une activité en direct) : plus de tiers droit vide.
    private var agendaEtendu: some View {
        let v = VueIlot.agendaEtendu, e = m.rdvVu
        let z = g.zone(v)
        let x = z.minX + ContenuAgenda.retrait, l = z.maxX - x
        let visio = e?.lien != nil
        return ZStack(alignment: .topLeading) {
            Text(e?.titre ?? "").font(TexteIlot.l1).tracking(-0.2).foregroundStyle(.white).lineLimit(1).truncationMode(.tail)
                .posee(CGRect(x: x, y: z.minY, width: l, height: 21), m.aspect(v, rang: 0), ancre: .topLeading)
            TimelineView(.periodic(from: Date(timeIntervalSinceReferenceDate: 0), by: 15)) { _ in
                Text(e.map { PlanAgenda.plage($0) + " \u{00B7} " + PlanAgenda.dans($0.debut.timeIntervalSince(m.maintenant())) } ?? "")
                    .font(TexteIlot.l2).foregroundStyle(CouleursIlot.encre2).lineLimit(1)
            }
            .posee(CGRect(x: x, y: z.minY + 23, width: l, height: 16), m.aspect(v, rang: 1), ancre: .topLeading)
            HStack(spacing: 6) {
                Image(systemName: visio ? "video.fill" : "mappin.and.ellipse").font(.system(size: 11, weight: .semibold))
                Text(e.map(ContenuAgenda.ligneLieu) ?? "").font(TexteIlot.l2).lineLimit(1).truncationMode(.middle)
            }
            .foregroundStyle(CouleursIlot.encre2)
            .posee(CGRect(x: x, y: z.minY + 41, width: l, height: 16), m.aspect(v, rang: 2), ancre: .topLeading)
            if let e {
                HStack(spacing: ContenuAnnonce.espaceBoutons) {
                    ForEach(Array(ContenuAgenda.boutons(e).enumerated()), id: \.offset) { _, b in
                        CapIlot(titre: b.titre, icone: b.icone, style: b.style, etiquette: b.etiquette, remplir: true) { if let a = b.action { m.surAction(a) } }
                    }
                }
                .posee(CGRect(x: x, y: z.minY + 68, width: l, height: 32), m.aspect(v, rang: 3), ancre: .topLeading)
            }
        }
    }

    // MARK: rangée Minuteur sous la lecture (appui long)

    /// La rangée Minuteur de l'accueil, posée sous la lecture dépliée (maquette apple-acces/1-controles.html) : un filet, puis
    /// [minuteur] Minuteur / Lancer un compte à rebours [5 min] [10 min] [25 min]. Un minuteur qui tourne déjà montre son temps.
    /// L'étagère, si elle garde des fichiers, suit en dessous (pendant une vidéo, l'accueil n'est pas atteignable : c'est son entrée).
    private var rangeeMinuteurLecture: some View {
        let v = VueIlot.lectureMinuteur
        let w = g.corps(v), l = 2 * w - 2 * GrilleIlot.marge
        let haut = g.barre + CGFloat(GeoIlot.profondeurLecture)
        let etagere = m.etagereActive && !m.etagere.isEmpty
        return ZStack(alignment: .topLeading) {
            filet.posee(CGRect(x: -w + GrilleIlot.marge, y: haut - 1, width: l, height: 1), m.aspect(v, rang: 0))
            if etagere {
                ligneEtagere(v, 2, filet: false)
                    .frame(width: l, height: 42)
                    .offset(x: IlotMoteur.largeur / 2 - w + GrilleIlot.marge, y: haut + 3 + 42)
            }
            tic { d in
                ligneAccueil(v, 1, glyphe: GlypheIlot(nom: "timer", couleur: CouleursIlot.ambre, taille: 17), titre: "Minuteur",
                             sous: m.minuteur == nil ? "Lancer un compte à rebours" : "En cours \u{00B7} " + tempsRestant(d),
                             couleurSous: m.minuteur == nil ? CouleursIlot.encre2 : CouleursIlot.ambre, filet: etagere) {
                    if let mt = m.minuteur {
                        // il tourne : pause (ou reprise) et arrêt, ronds, comme l'activité du minuteur sur l'iPhone
                        HStack(spacing: 8) {
                            BoutonRondIlot(symbole: mt.enPause ? "play.fill" : "pause.fill", couleur: CouleursIlot.ambre, fond: CouleursIlot.ambre.opacity(0.22),
                                           etiquette: mt.enPause ? "Reprendre le minuteur" : "Mettre le minuteur en pause") { m.surAction(.minuteurBasculer) }
                            BoutonRondIlot(symbole: "xmark", couleur: .white, fond: Color.white.opacity(0.14), etiquette: "Arrêter le minuteur") { m.surAction(.minuteurArreter) }
                        }
                    } else {
                        HStack(spacing: 6) {
                            ForEach([5, 10, 25], id: \.self) { n in
                                CapIlot(titre: "\(n) min", hauteur: 28, etiquette: "Minuteur de \(n) minutes") { m.surAction(.minuteurLancerSousLecture(minutes: Double(n))) }
                            }
                        }
                    }
                }
            }
            .frame(width: l, height: 42)
            .offset(x: IlotMoteur.largeur / 2 - w + GrilleIlot.marge, y: haut + 3)
        }
    }

    // MARK: accueil

    /// L'accueil, la carte sous le Centre : une liste à filets fins (le prochain rendez-vous, « Dire un rappel », la dernière dictée),
    /// l'action à droite. Le minuteur, le choix du micro et l'étagère sont dans le Centre. Les points de page sont à droite.
    private var accueil: some View {
        let v = VueIlot.accueil
        let z = g.zoneCarte(v, haut: 10, bas: 12)
        let e = m.rendezVousSuivant
        let d = m.derniereDictee
        return VStack(spacing: 0) {
            ligneAccueil(v, 0, glyphe: GlypheIlot(nom: GlypheIlot.calendrier, couleur: CouleursIlot.rouge, taille: 17),
                         titre: e?.titre ?? (m.calendrierActif ? "Rien de prévu" : "Calendrier éteint"),
                         sous: e.map { FormatIlot.heure($0.debut) + " \u{00B7} " + PlanAgenda.dans($0.debut.timeIntervalSince(m.maintenant())) } ?? (m.calendrierActif ? "Aucun rendez-vous à venir" : "Activable dans les réglages")) {
                if let e, e.lien != nil { CapIlot(titre: "Rejoindre", icone: "video.fill", style: .vert, hauteur: 28) { m.surAction(.rendezVousRejoindre(e)) } }
            }
            ligneAccueil(v, 1, glyphe: GlypheIlot(nom: "bell.fill", couleur: CouleursIlot.jaune, taille: 16), titre: "Rappel", sous: "Dis \u{00AB}\u{00A0}appeler Paul à 15 h\u{00A0}\u{00BB}") {
                CapIlot(titre: "Dire un rappel", icone: "mic.fill", hauteur: 28) { m.surAction(.rappelFormulaire) }
            }
            ligneAccueil(v, 2, glyphe: GlypheIlot(nom: "quote.opening", couleur: Color.white.opacity(0.7), taille: 15),
                         titre: d?.texte ?? "Rien pour l\u{2019}instant", police: TexteIlot.extrait, couleurTitre: Color.white.opacity(0.86),
                         sous: "Dernière dictée" + (d.map { " \u{00B7} il y a " + $0.age } ?? ""), filet: false) {
                if d != nil { CapIlot(titre: "Coller", hauteur: 28, etiquette: "Coller la dernière dictée") { m.surAction(.collerLaDerniereDictee) } }
            }
            Spacer(minLength: 0)
        }
        .frame(width: z.width, height: z.height, alignment: .top)
        .offset(x: IlotMoteur.largeur / 2 + z.minX, y: z.minY)
    }

    /// « Étagère · 2 fichiers », leurs noms (le plus récent d'abord), deux icônes en pile ; un clic ouvre la carte Étagère.
    private func ligneEtagere(_ v: VueIlot, _ rang: Int, filet avecFilet: Bool) -> some View {
        ligneAccueil(v, rang, glyphe: GlypheIlot(nom: "tray.full.fill", couleur: CouleursIlot.bleu, taille: 15),
                     titre: "Étagère \u{00B7} " + EtagereIlot.resume(m.etagere.count),
                     sous: m.etagere.reversed().map(\.nom).joined(separator: ", "), filet: avecFilet) {
            HStack(spacing: 8) {
                IconesFichiers(icones: m.etagere.suffix(2).reversed().map(\.icone), cote: 28)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(CouleursIlot.encre3)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { m.ouvrirEtagere() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { m.ouvrirEtagere() }
    }

    private func ligneAccueil<G: View, D: View>(_ v: VueIlot, _ rang: Int, glyphe: G, titre: String, police: Font = TexteIlot.ligne, couleurTitre: Color = .white,
                                                sous: String, couleurSous: Color = CouleursIlot.encre2, filet avecFilet: Bool = true, @ViewBuilder droite: () -> D) -> some View {
        HStack(spacing: 12) {
            glyphe.frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(titre).font(police).tracking(-0.1).foregroundStyle(couleurTitre).lineLimit(1).truncationMode(.tail)
                Text(sous).font(TexteIlot.l2.monospacedDigit()).foregroundStyle(couleurSous).lineLimit(1).truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            droite().fixedSize()
        }
        .frame(height: 42)
        .overlay(alignment: .bottom) { if avecFilet { filet.padding(.leading, 34) } }
        .aspectIlot(m.aspect(v, rang: rang), ancre: .top)
    }
}

// MARK: lecture

/// La pochette (aile gauche → grande pochette du déplié) et l'égaliseur (aile droite, il ne bouge pas) : les pièces de la lecture.
struct LectureVoyageurs: View {
    @ObservedObject var m: IlotMoteur
    @ObservedObject var lecture: LectureModele
    var g: GrilleIlot

    static func cadreCompact(_ g: GrilleIlot, large: Bool) -> CGRect {
        let c = g.centreAile(.lectureCompact, droite: false)
        return large ? CGRect(x: c - 14, y: g.barre / 2 - 8, width: 28, height: 16) : CGRect(x: c - 11, y: g.barre / 2 - 11, width: 22, height: 22)
    }
    static func cadreEtendu(_ g: GrilleIlot, large: Bool) -> CGRect {
        let w = g.corps(.lectureEtendu)
        return CGRect(x: -w + GrilleIlot.marge, y: g.barre + 16, width: large ? 128 : 72, height: 72)
    }

    var body: some View {
        let large = lecture.pochetteLarge
        let (r, ts) = voyageIlot(Self.cadreCompact(g, large: large), Self.cadreEtendu(g, large: large), m.ouverture(.lecture))
        let rayon = lerp(large ? 4 : 6, large ? 10 : 12, borne(ts))
        let a = m.aspect(FamilleIlot.lecture)
        let teinte = teinteIlot(lecture.teinte.clair)
        let ce = g.centreAile(.lectureCompact, droite: true)
        ZStack(alignment: .topLeading) {
            PochetteLecture(m: lecture)
                .clipShape(RoundedRectangle(cornerRadius: rayon, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: rayon, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
                .keyframeAnimator(initialValue: 1.0, trigger: lecture.pop) { v, s in v.scaleEffect(m.reduire ? 1 : s) } keyframes: { _ in
                    KeyframeTrack { LinearKeyframe(0.9, duration: 0.01); SpringKeyframe(1, duration: 0.42, spring: Spring(response: 0.42, dampingRatio: 0.78)) }
                }
                .posee(r, a, ancre: .center)
                .accessibilityHidden(true)
            Group {
                if m.statique { EgaliseurFixe(teinte: teinte, joue: lecture.joue) }
                else { EgaliseurLecture(teinte: teinte, joue: lecture.joue, animer: !m.reduire) }
            }
            .posee(CGRect(x: ce - 9.7, y: g.barre / 2 - 7, width: 19.4, height: 14), a, ancre: .center)
            // déplié, l'épaule droite montre les écouteurs : l'onde s'efface (le bouton lecture/pause dit déjà si ça joue)
            .opacity(m.ecouteurs?.niveau != nil ? 1 - m.ouvertureEpaules : 1)
            .accessibilityHidden(true)
        }
        // carré → 16:9 (la miniature arrive après l'icône de l'app) : la pochette s'élargit au lieu de sauter
        .animation(m.reduire || m.statique ? nil : .spring(response: 0.36, dampingFraction: 0.86), value: large)
    }
}

/// Ce que la lecture ajoute une fois dépliée : titre, source, barre, commandes. Arrive après la forme, un bloc toutes les 35 ms.
struct LectureEtendue: View {
    @ObservedObject var m: IlotMoteur
    @ObservedObject var lecture: LectureModele
    var g: GrilleIlot

    var body: some View {
        let v = VueIlot.lectureEtendu
        let w = g.corps(v), b = g.barre
        let art = LectureVoyageurs.cadreEtendu(g, large: lecture.pochetteLarge)
        // à droite, la place des points de page (lecture, Centre, accueil)
        let md = GrilleIlot.marge + GrilleIlot.placePoints
        let x = art.maxX + 14, l = w - md - x
        let titre = lecture.morceau?.titre ?? ""
        let musique = lecture.genre == .musique
        ZStack(alignment: .topLeading) {
            TitreDefilant(texte: titre, police: TexteIlot.titre, largeur: l, defiler: !m.reduire && !m.statique)
                .id(titre)
                .transition(.opacity)
                .posee(CGRect(x: x, y: b + 31, width: l, height: 21), m.aspect(v, rang: 0), ancre: .topLeading)
            Text(lecture.sousTitre).font(TexteIlot.source).foregroundStyle(CouleursIlot.encre2).lineLimit(1).truncationMode(.tail)
                .posee(CGRect(x: x, y: b + 54, width: l, height: 17), m.aspect(v, rang: 1), ancre: .topLeading)
            BarreLecture(lecture: lecture, largeur: 2 * w - GrilleIlot.marge - md, teinte: teinteIlot(lecture.teinte.clair))
                .posee(CGRect(x: -w + GrilleIlot.marge, y: b + 98, width: 2 * w - GrilleIlot.marge - md, height: 20), m.aspect(v, rang: 2))
            HStack(spacing: 24) {
                if musique {
                    BoutonNu(symbole: "backward.fill", taille: 20, etiquette: "Précédent") { lecture.surPrecedent() }
                } else {
                    BoutonNu(symbole: "gobackward.10", taille: 21, etiquette: "Reculer de 10 secondes") { lecture.surSaut(-10) }
                }
                BoutonNu(symbole: lecture.joue ? "pause.fill" : "play.fill", taille: 27, etiquette: lecture.joue ? "Pause" : "Lecture") { lecture.surBascule() }
                if musique {
                    BoutonNu(symbole: "forward.fill", taille: 20, etiquette: "Suivant") { lecture.surSuivant() }
                } else {
                    BoutonNu(symbole: "goforward.10", taille: 21, etiquette: "Avancer de 10 secondes") { lecture.surSaut(10) }
                }
            }
            .posee(CGRect(x: -100, y: b + 125, width: 200, height: 40), m.aspect(v, rang: 3), ancre: .top, .center)
            if !musique {
                // le glyphe (pas sa zone cliquable de 40 pt) finit sur la marge, comme le temps restant juste au-dessus
                let gs = MesureIlot.symbole("forward.end.fill", 15)
                BoutonNu(symbole: "forward.end.fill", taille: 15, discret: true, etiquette: "Suivant") { lecture.surSuivant() }
                    .posee(CGRect(x: w - md - (40 + gs) / 2, y: b + 125, width: 40, height: 40), m.aspect(v, rang: 3), ancre: .center)
            }
        }
        .animation(m.reduire ? nil : .easeOut(duration: 0.24), value: titre)
        // une miniature 16:9 qui arrive après l'icône carrée : le titre glisse au lieu de sauter de 56 pt
        .animation(m.reduire || m.statique ? nil : .spring(response: 0.36, dampingFraction: 0.86), value: lecture.pochetteLarge)
    }
}

struct LigneRappel: View {
    var rappel: Rappel
    var fait: () -> Void
    @State private var survol = false
    var body: some View {
        HStack(spacing: 12) {
            Button(action: fait) {
                Circle().strokeBorder(Color.white.opacity(survol ? 0.8 : 0.4), lineWidth: 1.6).frame(width: 18, height: 18)
                    .overlay(Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white).opacity(survol ? 1 : 0))
                    .frame(width: 18, height: 38).contentShape(Rectangle())
            }.buttonStyle(.plain).onHover { survol = $0 }.accessibilityLabel("Fait : \(rappel.texte)")
            Text(rappel.texte).font(.system(size: 14, weight: .medium)).foregroundStyle(.white).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 8)
            Text(FormatIlot.heure(rappel.echeance)).font(.system(size: 13, weight: .medium).monospacedDigit()).foregroundStyle(CouleursIlot.encre3)
        }
        .frame(height: 38)
    }
}

// MARK: pastille

/// La deuxième activité, en bulle à droite de l'îlot (comme les deux activités de la Dynamic Island) : elle sort de l'aile droite en
/// glissant (un pont liquide la retient puis casse), se pose à côté, à la même hauteur, puis montre son contenu.
struct PastilleVue: View {
    @ObservedObject var m: IlotMoteur

    var body: some View {
        let chute = CGFloat(m.pastilleChute.x), ouv = CGFloat(min(1.05, max(0, m.pastilleOuverte.x)))
        if let a = m.pastille, chute > 0.005 {
            let h = m.hauteurPastille
            let l = m.largeurPastilleActuelle(a)
            let x0 = m.xPastille(a)
            let cou = CGFloat(m.trace.cou)
            let ecart = x0 - cou
            ZStack(alignment: .topLeading) {
                if !m.reduire, ecart < 9, chute < 0.995 {
                    pont(x0: x0, l: l, h: h, cou: cou)
                }
                FormeBulle().fill(Color.black)
                    .frame(width: l, height: h)
                    .contentShape(Rectangle())
                    .onTapGesture { m.cliquerPastille() }
                    .allowsHitTesting(m.pastilleMontree)
                    .offset(x: IlotMoteur.largeur / 2 + x0, y: 0)
                    .accessibilityLabel("Autre activité")
                    .accessibilityAddTraits(.isButton)
                contenu(a, ouverture: ouv)
                    .frame(width: l, height: h, alignment: .leading)
                    .clipShape(Rectangle())
                    .opacity(m.aspectPastille.opacite)
                    .scaleEffect(a == .lecture || a == .rappel ? 1 : 1 + 0.05 * ouv, anchor: .leading)
                    .allowsHitTesting(false)
                    .offset(x: IlotMoteur.largeur / 2 + x0, y: 0)
            }
            .opacity(m.pastilleMontree ? 1 : Double(min(1, chute * 1.2)))
        }
    }

    /// Le pont liquide entre l'aile droite de l'îlot et la bulle qui en sort, flouté puis seuillé (métaballe). Seulement pendant la sortie.
    private func pont(x0: CGFloat, l: CGFloat, h: CGFloat, cou: CGFloat) -> some View {
        let ecart = x0 - cou
        let flou = ecart < 2 ? 4 : max(0.4, min(4, 4 - (ecart - 2) * 0.5))
        return Canvas { ctx, taille in
            let ox = taille.width / 2
            ctx.addFilter(.alphaThreshold(min: 0.5, color: .black))
            ctx.addFilter(.blur(radius: flou * 1.6))
            ctx.drawLayer { c in
                c.fill(Path(roundedRect: CGRect(x: ox + cou - 24, y: -14, width: 24, height: h + 14), cornerRadius: 10), with: .color(.black))
                c.fill(Path(roundedRect: CGRect(x: ox + x0, y: -14, width: l, height: h + 14), cornerRadius: 10), with: .color(.black))
            }
        }
        .frame(width: IlotMoteur.largeur, height: IlotMoteur.hauteurMax)
        .allowsHitTesting(false)
    }

    @ViewBuilder private func contenu(_ a: ActiviteIlot, ouverture: CGFloat) -> some View {
        switch a {
        case .minuteur:
            let mn = m.minuteur ?? m.dernierMinuteur
            TimelineView(.periodic(from: m.minuteur?.echeance ?? Date(timeIntervalSinceReferenceDate: 0), by: 1)) { _ in
                HStack(spacing: 6) {
                    AnneauIlot(taille: 14, trait: 2, couleur: CouleursIlot.ambre, fraction: mn.fraction(a: m.maintenant()), enPause: mn.enPause) {}
                    Text(FormatIlot.duree(mn.restant(a: m.maintenant()))).font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundStyle(CouleursIlot.ambre).lineLimit(1).fixedSize()
                }
                .padding(.leading, 10)
            }
        case .lecture:
            let large = m.lecture.pochetteLarge
            HStack(spacing: 7) {
                PochetteLecture(m: m.lecture).frame(width: large ? 24 : 15, height: large ? 13.5 : 15)
                    .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
                Group {
                    if m.statique { EgaliseurFixe(teinte: teinteIlot(m.lecture.teinte.clair), joue: m.lecture.joue, nombre: 3, largeurBarre: 2.2) }
                    else { EgaliseurPetit(teinte: teinteIlot(m.lecture.teinte.clair), joue: m.lecture.joue, animer: !m.reduire) }
                }
                .frame(width: 11, height: 10)
                Text(m.lecture.morceau?.titre ?? "").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    .frame(maxWidth: 140, alignment: .leading)
                    .opacity(Double(lisseIlot((ouverture - 0.35) / 0.5)))
            }
            .padding(.leading, 10)
        case .rendezVous:
            HStack(spacing: 6) {
                GlypheIlot(nom: GlypheIlot.calendrier, couleur: CouleursIlot.rouge, taille: 12)
                Text((m.rendezVous ?? m.dernierRendezVous).map { PlanAgenda.court($0.debut.timeIntervalSince(m.maintenant())) } ?? "")
                    .font(.system(size: 12.5, weight: .semibold).monospacedDigit()).foregroundStyle(.white).lineLimit(1).fixedSize()
            }
            .padding(.leading, 10)
        case .rappel:
            // la cloche et l'heure ; au survol, de quel rappel il s'agit
            let r = m.rappelVu
            HStack(spacing: 6) {
                GlypheIlot(nom: "bell.fill", couleur: CouleursIlot.jaune, taille: 12)
                Text(FormatIlot.heure(r?.echeance ?? m.maintenant()))
                    .font(.system(size: 12.5, weight: .semibold).monospacedDigit()).foregroundStyle(CouleursIlot.jaune).lineLimit(1).fixedSize()
                Text(r?.texte ?? "").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    .frame(maxWidth: 150, alignment: .leading)
                    .opacity(Double(lisseIlot((ouverture - 0.35) / 0.5)))
            }
            .padding(.leading, 10)
        case .micro:
            HStack(spacing: 6) {
                GlypheIlot(nom: "mic.slash.fill", couleur: CouleursIlot.rouge, taille: 12)
                Text("Coupé").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(CouleursIlot.rouge).lineLimit(1).fixedSize()
            }
            .padding(.leading, 10)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Micro coupé")
        case .claude:
            PastilleClaude(m: m)
        case .alerte:
            EmptyView()
        }
    }
}

/// La bulle : accrochée au haut de l'écran comme l'îlot (bord du haut plat), coins bas arrondis comme ceux de l'îlot replié, et à droite
/// l'épaule creuse de l'îlot (6 pt) qui la raccorde au bord de l'écran. Pas d'épaule à gauche : la fente avec l'îlot reste nette.
struct FormeBulle: Shape {
    static let epaule: CGFloat = 6
    func path(in r: CGRect) -> Path {
        let rb = min(10, r.height / 2, r.width / 2), e = Self.epaule
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY - 1))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - rb))
        p.addQuadCurve(to: CGPoint(x: r.minX + rb, y: r.maxY), control: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - rb, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.maxY - rb), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + e))
        p.addQuadCurve(to: CGPoint(x: r.maxX + e, y: r.minY), control: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX + e, y: r.minY - 1))
        p.closeSubpath()
        return p
    }
}

/// L'égaliseur de la pastille : trois barres (Core Animation).
struct EgaliseurPetit: NSViewRepresentable {
    var teinte: Color
    var joue: Bool
    var animer: Bool
    func makeNSView(context: Context) -> EgaliseurLecture.Vue { EgaliseurLecture.Vue(frame: CGRect(x: 0, y: 0, width: 11, height: 10), barres: 3, largeur: 2.2) }
    func updateNSView(_ v: EgaliseurLecture.Vue, context: Context) { v.appliquer(teinte: teinte, joue: joue, animer: animer) }
}

// MARK: racine

/// Le contenu de la fenêtre de l'îlot : la forme noire (sans liseré ; une ombre douce seulement une fois dépliée), ses écrans rognés
/// à la forme, la pastille.
struct IlotVue: View {
    @ObservedObject var m: IlotMoteur

    var body: some View {
        let _ = m.rev
        let g = m.grille
        let forme = FormeNoire(points: m.trace)
        let s = Double(min(1, max(0, (CGFloat(m.geo[2].x) - g.barre) / 70)))
        ZStack(alignment: .topLeading) {
            // la bulle passe SOUS l'îlot : elle sort de l'aile droite par-dessous, sans jamais couvrir l'onde ni l'heure de l'aile
            PastilleVue(m: m)
            // l'ombre n'existe que SOUS la barre des menus : à côté du cou, elle aurait assombri les icônes voisines
            forme.fill(Color.black)
                .shadow(color: .black.opacity(0.42 * s), radius: 10 * s, x: 0, y: 5 * s)
                .mask(alignment: .top) { Color.black.padding(.top, g.barre) }
            forme.fill(Color.black)
            IlotCalques(m: m, g: g)
                .clipShape(forme)
                .contentShape(forme)
                // clic (épingle ou relâche) et appui long de 0,4 s (sur la lecture : la rangée Minuteur), chronométrés par le moteur ;
                // l'îlot gonfle un peu sous le doigt pendant l'appui. Les boutons du contenu gardent leurs clics.
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in m.debutAppui(origine: v.startLocation, distance: hypot(v.translation.width, v.translation.height)) }
                    .onEnded { v in m.finAppui(deplace: hypot(v.translation.width, v.translation.height) > 12) })
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { m.clicForme() }
        }
        .frame(width: IlotMoteur.largeur, height: IlotMoteur.hauteurMax, alignment: .topLeading)
        .scaleEffect(m.presse ? 1.015 : 1, anchor: .top)
        .animation(m.reduire ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: m.presse)
        .offset(x: CGFloat(m.secousse.x))
        .opacity(m.cache && m.courante == .repos && m.geo.allSatisfy(\.fini) ? 0 : 1)
    }
}

// MARK: épaules, jauges, boutons ronds

/// Les épaules de l'îlot déplié (maquette ilot-apple.html) : de part et d'autre de la caméra, dans la barre des menus, la batterie du
/// Mac (à gauche) et celle des écouteurs connectés (à droite). Elles paraissent quand le cou s'est élargi et que le corps descend.
struct EpaulesIlot: View {
    @ObservedObject var m: IlotMoteur
    var g: GrilleIlot

    var body: some View {
        let a = AspectIlot(opacite: m.ouvertureEpaules, flou: 0, echelle: 1)
        let l = CGFloat(GeoIlot.epaules) - 4
        ZStack(alignment: .topLeading) {
            if let e = m.energie {
                PileIlot(pourcent: e.pourcent, secteur: e.secteur)
                .posee(CGRect(x: -g.hc - CGFloat(GeoIlot.epaules) + 2, y: 0, width: l, height: g.barre), a, ancre: .center, .center)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Batterie du Mac, \(e.pourcent) %" + (e.secteur ? ", branché" : ""))
            }
            if let c = m.ecouteurs, let n = c.niveau {
                HStack(spacing: 2.5) {
                    Image(systemName: c.symbole).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                    Text("\(n)\u{202F}%").font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundStyle(n <= 10 ? CouleursIlot.rouge : .white)
                }
                .lineLimit(1).minimumScaleFactor(0.8)
                .posee(CGRect(x: g.hc + 2, y: 0, width: l, height: g.barre), a, ancre: .center, .center)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(c.titre), \(n) %")
            }
        }
        .allowsHitTesting(false)
    }
}

/// Une jauge de batterie : l'anneau, le pourcentage dedans, le nom dessous (écouteur gauche, droit, étui).
struct JaugeIlot: View {
    var jauge: ContenuAnnonce.Jauge
    static let largeur: CGFloat = 40
    var body: some View {
        let couleur = jauge.etui ? Color.white : (jauge.pourcent <= 20 ? CouleursIlot.rouge : CouleursIlot.vert)
        VStack(spacing: 3) {
            ZStack {
                Circle().stroke(couleur.opacity(0.26), lineWidth: 3)
                Circle().trim(from: 0, to: CGFloat(jauge.pourcent) / 100)
                    .stroke(couleur, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))
                Text("\(jauge.pourcent)").font(.system(size: 11, weight: .semibold).monospacedDigit()).foregroundStyle(.white)
            }
            .frame(width: 29, height: 29)
            Text(jauge.nom).font(.system(size: 10.5, weight: .medium)).foregroundStyle(CouleursIlot.encre2).lineLimit(1).fixedSize()
        }
        .frame(width: Self.largeur)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(jauge.nom), \(jauge.pourcent) %")
    }
}

/// Un bouton rond de 32 pt (pause, arrêt) : symbole coloré sur un fond teinté, réduit à 90 % pendant l'appui.
struct BoutonRondIlot: View {
    var symbole: String
    var couleur: Color
    var fond: Color
    var etiquette: String
    /// 32 pt ; 28 dans la case Minuteur du Centre.
    var cote: CGFloat = 32
    var action: () -> Void
    @State private var survol = false
    private struct Style: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label.scaleEffect(configuration.isPressed ? 0.9 : 1)
                .animation(.spring(duration: 0.18, bounce: 0.2), value: configuration.isPressed)
        }
    }
    var body: some View {
        Button(action: action) {
            Image(systemName: symbole).font(.system(size: cote >= 32 ? 12 : 11, weight: .bold)).foregroundStyle(couleur)
                .frame(width: cote, height: cote)
                .background(Circle().fill(fond).brightness(survol ? 0.08 : 0))
                .contentShape(Circle())
        }
        .buttonStyle(Style())
        .onHover { survol = $0 }
        .accessibilityLabel(etiquette)
    }
}

// MARK: compte à rebours, attente

/// L'anneau de « Remettre » (maquette : 16 pt, il se vide) : il part de ce qui reste jusqu'à `fin` et se vide d'un trait, sur une
/// animation de SwiftUI (aucune minuterie : rien ne tourne une fois le bandeau parti). Si la fin recule (la souris sur l'îlot retient le
/// bandeau), il repart de là.
struct AnneauCompte: View {
    var fin: Date
    var duree: TimeInterval
    var maintenant: () -> Date
    @State private var reste: Double
    init(fin: Date, duree: TimeInterval, maintenant: @escaping () -> Date) {
        self.fin = fin; self.duree = duree; self.maintenant = maintenant
        _reste = State(initialValue: AnneauCompte.part(fin: fin, duree: duree, a: maintenant()))
    }
    static func part(fin: Date, duree: TimeInterval, a t: Date) -> Double { duree > 0 ? min(1, max(0, fin.timeIntervalSince(t) / duree)) : 0 }
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.2), lineWidth: 2.4)
            Circle().trim(from: 0, to: reste).stroke(Color.white.opacity(0.78), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(1.2)
        .frame(width: ContenuAnnonce.coteCompte, height: ContenuAnnonce.coteCompte)
        .onAppear { vider() }
        .onChange(of: fin) { vider() }
        .accessibilityHidden(true)
    }
    private func vider() {
        let r = max(0, fin.timeIntervalSince(maintenant()))
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { reste = AnneauCompte.part(fin: fin, duree: duree, a: maintenant()) }
        guard r > 0 else { return }
        DispatchQueue.main.async { withAnimation(.linear(duration: r)) { reste = 0 } }
    }
}

/// Le rouet de l'envoi AirDrop : un arc bleu qui tourne tant que le panneau de macOS attend (immobile avec « Réduire les animations »
/// et dans les rendus).
struct RouetIlot: View {
    var anime: Bool
    @State private var angle = 0.0
    var body: some View {
        Circle().trim(from: 0, to: 0.72).stroke(Color(hex: 0x5EB0FF), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
            .padding(2)
            .rotationEffect(.degrees(angle - 90))
            .onAppear { if anime { withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { angle = 360 } } }
            .accessibilityLabel("Envoi en cours")
    }
}

// MARK: fichiers (bandeau Téléchargé)

/// Les icônes du Finder d'un bandeau « Téléchargé » : celle du fichier ; pour une rafale, la deuxième dépasse derrière, un peu penchée
/// (une pile, comme sur le Bureau).
struct IconesFichiers: View {
    var icones: [NSImage]
    var cote: CGFloat
    var body: some View {
        ZStack {
            if icones.count > 1 {
                Image(nsImage: icones[1]).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    .frame(width: cote * 0.86, height: cote * 0.86)
                    .rotationEffect(.degrees(-9)).offset(x: -cote * 0.12, y: -cote * 0.04).opacity(0.75)
            }
            if let i = icones.first {
                Image(nsImage: i).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    .frame(width: icones.count > 1 ? cote * 0.9 : cote, height: icones.count > 1 ? cote * 0.9 : cote)
                    .offset(x: icones.count > 1 ? cote * 0.06 : 0, y: icones.count > 1 ? cote * 0.04 : 0)
            }
        }
        .frame(width: cote, height: cote)
        .accessibilityHidden(true)
    }
}

extension View {
    /// Le fichier se glisse hors de l'îlot (vers le Bureau, un mail, une conversation) : l'URL du fichier, comme depuis le Finder. Le
    /// moteur le sait (`glisserSortantCommence`) : la vue source reste à l'écran jusqu'au relâchement, et l'îlot ne s'ouvre pas en zone
    /// de dépôt sous ce glisser-là.
    @ViewBuilder func glisserFichier(_ url: URL?, _ m: IlotMoteur?) -> some View {
        if let url {
            onDrag {
                MainActor.assumeIsolated { m?.glisserSortantCommence() }
                return NSItemProvider(contentsOf: url) ?? NSItemProvider(object: url as NSURL)
            }
        } else { self }
    }
}

/// La pile de l'îlot, dessinée comme celle de l'iPhone : un corps gris, le niveau qui le remplit (blanc ; vert sur le secteur ; rouge à
/// 20 % et moins), le pourcentage DÉCOUPÉ dedans (on voit le noir de l'îlot à travers), un petit éclair à côté quand elle est branchée.
/// 26 × 12 pt (34 avec l'éclair) : « 100 » tient toujours, plus jamais de « 100… ».
struct PileIlot: View {
    var pourcent: Int
    var secteur: Bool
    var chiffres = true
    var echelle: CGFloat = 1
    var body: some View {
        let p = CGFloat(min(100, max(0, pourcent))) / 100
        let couleur = secteur ? CouleursIlot.vert : (pourcent <= 20 ? CouleursIlot.rouge : Color.white)
        HStack(spacing: 1.5 * echelle) {
            HStack(spacing: 1 * echelle) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3.6 * echelle, style: .continuous).fill(Color.white.opacity(chiffres ? 0.32 : 0))
                    RoundedRectangle(cornerRadius: 3.6 * echelle, style: .continuous)
                        .strokeBorder(Color.white.opacity(chiffres ? 0 : 0.45), lineWidth: 1 * echelle)
                    // le niveau : rogné par le corps (coins nets à gauche, coupe droite)
                    Rectangle().fill(couleur).frame(width: (chiffres ? 24 : 20) * echelle * p)
                        .padding(chiffres ? 0 : 2 * echelle)
                        .clipShape(RoundedRectangle(cornerRadius: (chiffres ? 3.6 : 2) * echelle, style: .continuous))
                    if chiffres {
                        Text("\(pourcent)").font(.system(size: 9.5 * echelle, weight: .heavy).monospacedDigit())
                            .frame(maxWidth: .infinity)
                            .blendMode(.destinationOut)
                    }
                }
                .frame(width: 24 * echelle, height: 12 * echelle)
                .compositingGroup()
                RoundedRectangle(cornerRadius: 0.8 * echelle).fill(Color.white.opacity(0.38)).frame(width: 1.6 * echelle, height: 4.5 * echelle)
            }
            if secteur { Image(systemName: "bolt.fill").font(.system(size: 8.5 * echelle, weight: .bold)).foregroundStyle(CouleursIlot.vert) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Batterie \(pourcent) %" + (secteur ? ", branchée" : ""))
    }
}
