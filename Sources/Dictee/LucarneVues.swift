import SwiftUI
import DicteeCore

// La Lucarne hors de l'encoche (docs/plan-lucarne-deplacable.md, mission 3 « verre et contenu hors encoche ») : une forme de verre clair
// (SwiftUI `.glassEffect(.clear)`, sans `.interactive()` ni reflet qui suit le pointeur : rien ne tourne au repos), un voile noir qui garde
// le texte blanc lisible sur une page blanche (`VerreLucarne`), un liseré fin et une ombre douce autour. Repliée, une pilule (couchée, ou
// debout au milieu des bords) avec le contenu compact de l'activité ; dépliée, les écrans de l'encoche eux-mêmes (`IlotCalques`), mis en
// page pour la forme d'arrivée et rognés à elle (les épaules, dans la barre des menus, n'ont pas de place ici : elles restent dehors).
// Dans l'encoche, ou tenue tout près d'elle, la forme redevient noire (fondu noir ↔ verre).

// MARK: le contenu compact

/// Ce qu'une pilule repliée montre : l'activité de l'îlot (celle de la bulle dans l'encoche), un niveau, la batterie, un mot…
enum GenreCompact: Equatable {
    case activite(ActiviteIlot)
    case niveau(GenreNiveau)
    case energie(charge: Bool)
    case microOuvert, dicteeMac, pile, logo

    /// Le contenu compact d'un écran replié (rien sous la barre) ; nil pour un écran déplié. Tous les écrans repliés en ont un : un
    /// contrôle de l'essai le vérifie.
    static func de(_ v: VueIlot) -> GenreCompact? {
        guard GeoIlot.profondeur(v) == 0 else { return nil }
        switch v {
        case .repos: return .logo
        case .lectureCompact: return .activite(.lecture)
        case .minuteurMinimal, .minuteurCompact: return .activite(.minuteur)
        case .rappelCompact: return .activite(.rappel)
        case .agendaCompact: return .activite(.rendezVous)
        case .reveilCompact: return .activite(.reveil)
        case .microCompact: return .activite(.micro)
        case .claudeMinimal, .claudeCompact: return .activite(.claude)
        case .reunionCompact: return .activite(.reunion)
        case .volume: return .niveau(.volume)
        case .luminosite: return .niveau(.luminosite)
        case .batterieCharge: return .energie(charge: true)
        case .batterieFaible: return .energie(charge: false)
        case .microOuvert: return .microOuvert
        case .dicteeMac: return .dicteeMac
        case .etagerePile: return .pile
        default: return .logo
        }
    }
}

extension IlotMoteur {
    /// Les deux pièces d'un contenu compact : le symbole, l'écart, le texte (mesurés avec la vraie police ; les chiffres qui changent
    /// sont mesurés en « 0 », le plus large).
    func piecesCompactes(_ g: GenreCompact) -> (glyphe: CGFloat, espace: CGFloat, texte: CGFloat) {
        func t(_ s: String, chiffres: Bool = true) -> CGFloat {
            MesureIlot.texte(chiffres ? s.replacingOccurrences(of: "[0-9]", with: "0", options: .regularExpression) : s, 12.5, .semibold, chiffres: chiffres)
        }
        switch g {
        case .activite(let a):
            switch a {
            case .minuteur:
                let mn = minuteur ?? dernierMinuteur
                return (14, 6, MesureIlot.texte(FormatIlot.duree(mn.restant(a: maintenant())).replacingOccurrences(of: "[0-9]", with: "0", options: .regularExpression), 13, .semibold, chiffres: true))
            case .lecture: return (lecture.pochetteLarge ? 24 : 15, 7, 11)
            case .rendezVous: return (12, 6, t((rendezVous ?? dernierRendezVous).map { PlanAgenda.court($0.debut.timeIntervalSince(maintenant())) } ?? ""))
            case .rappel: return (12, 6, t(FormatIlot.heure(rappelVu?.echeance ?? maintenant())))
            case .micro: return (MesureIlot.symbole("mic.slash.fill", 12), 6, t("Coupé", chiffres: false))
            case .claude:
                let s = texteClaude(claude ?? dernierClaude, taille: 12.5)
                return (13, s.isEmpty ? 0 : 6, s.isEmpty ? 0 : t(s))
            case .reveil: return (MesureIlot.symbole("alarm", 12), 6, t((reveil ?? dernierReveil)?.libelle() ?? "10:30"))
            case .reunion: return (7, 6, t(FormatIlot.chrono((reunion ?? derniereReunion).temps(a: maintenant()))))
            case .alerte: return piecesCompactes(.logo)
            }
        case .niveau(let n): return (MesureIlot.symbole(niveauVu(n).symbole, 14), 6, t("100\u{202F}%"))
        case .energie: return (MesureIlot.symbole("bolt.fill", 14), 6, t("100\u{202F}%"))
        case .microOuvert: return (MesureIlot.symbole("mic.fill", 14), 6, t("Ouvert", chiffres: false))
        case .dicteeMac: return (MesureIlot.symbole("laptopcomputer", 14), 6, t("Mac", chiffres: false))
        case .pile:
            return (MesureIlot.symbole(PileEtagere.glyphe, PileEtagere.tailleGlyphe), PileEtagere.espace,
                    MesureIlot.texte("\(EtagereIlot.capacite)", PileEtagere.tailleNombre, .bold, chiffres: true))
        case .logo: return (ContenuCompactLucarne.hauteurLogo * Guillemets.rapport, 0, 0)
        }
    }
    /// La largeur d'un contenu compact : couché, côte à côte ; debout, l'un sous l'autre.
    func largeurCompacte(_ g: GenreCompact, debout: Bool) -> Double {
        let p = piecesCompactes(g)
        if debout { return Double(max(p.glyphe, p.texte)) }
        return Double(p.glyphe + (p.texte > 0 ? p.espace + p.texte : 0))
    }
}

/// Le contenu compact d'une activité : dans la bulle de l'encoche (couché, aligné à gauche) et dans la pilule de la Lucarne hors de
/// l'encoche (couché ou debout, centré). `ouverture` : la bulle survolée montre aussi le titre (lecture, rappel).
struct ContenuCompactLucarne: View {
    @ObservedObject var m: IlotMoteur
    var genre: GenreCompact
    var debout = false
    var ouverture: CGFloat = 0
    static let hauteurLogo: CGFloat = 13

    var body: some View {
        switch genre {
        case .activite(let a): activite(a)
        case .niveau(let g):
            let n = m.niveauVu(g)
            pile(6) {
                Image(systemName: n.symbole).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                texte(n.muet ? "" : "\(n.pourcent)\u{202F}%", .white)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(g == .volume ? (n.muet ? "Son coupé" : "Volume, \(n.pourcent) %") : "Luminosité, \(n.pourcent) %")
        case .energie(let charge):
            let e = m.energie ?? m.bandeauVu?.energie ?? EnergieIlot(pourcent: 0, secteur: false, enCharge: false)
            let c = charge ? CouleursIlot.vert : CouleursIlot.rouge
            pile(6) {
                if charge { Image(systemName: "bolt.fill").font(.system(size: 14, weight: .semibold)).foregroundStyle(c) }
                else { PileIlot(pourcent: e.pourcent, secteur: false, chiffres: false, echelle: 1.15) }
                texte(e.texte, c)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(charge ? "En charge, \(e.pourcent) %" : "Batterie faible, \(e.pourcent) %")
        case .microOuvert:
            pile(6) { symbole("mic.fill", CouleursIlot.vert); texte("Ouvert", CouleursIlot.vert) }
                .accessibilityElement(children: .ignore).accessibilityLabel("Micro ouvert")
        case .dicteeMac:
            pile(6) { symbole("laptopcomputer", Color.white.opacity(0.85)); texte("Mac", CouleursIlot.encre2) }
                .accessibilityElement(children: .ignore).accessibilityLabel("Dicté sur le Mac")
        case .pile:
            pile(PileEtagere.espace) {
                Image(systemName: PileEtagere.glyphe).font(.system(size: PileEtagere.tailleGlyphe, weight: .semibold))
                Text("\(m.etagere.count)").font(.system(size: PileEtagere.tailleNombre, weight: .bold).monospacedDigit())
            }
            .foregroundStyle(.white).lineLimit(1).fixedSize()
            .accessibilityElement(children: .ignore).accessibilityLabel("Étagère : " + EtagereIlot.resume(m.etagere.count))
        case .logo:
            FormeGuillemets().fill(Color.white.opacity(0.92))
                .frame(width: Self.hauteurLogo * Guillemets.rapport, height: Self.hauteurLogo)
                .accessibilityLabel("Lucarne")
        }
    }

    @ViewBuilder private func activite(_ a: ActiviteIlot) -> some View {
        switch a {
        case .minuteur:
            let mn = m.minuteur ?? m.dernierMinuteur
            TimelineView(.periodic(from: m.minuteur?.echeance ?? Date(timeIntervalSinceReferenceDate: 0), by: 1)) { _ in
                pile(6) {
                    AnneauIlot(taille: 14, trait: 2, couleur: CouleursIlot.ambre, fraction: mn.fraction(a: m.maintenant()), enPause: mn.enPause) {}
                    Text(FormatIlot.duree(mn.restant(a: m.maintenant()))).font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundStyle(CouleursIlot.ambre).lineLimit(1).fixedSize()
                }
            }
        case .lecture:
            let large = m.lecture.pochetteLarge
            pile(7) {
                PochetteLecture(m: m.lecture).frame(width: large ? 24 : 15, height: large ? 13.5 : 15)
                    .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
                Group {
                    if m.statique { EgaliseurFixe(teinte: teinteIlot(m.lecture.teinte.clair), joue: m.lecture.joue, nombre: 3, largeurBarre: 2.2) }
                    else { EgaliseurPetit(teinte: teinteIlot(m.lecture.teinte.clair), joue: m.lecture.joue, animer: !m.reduire) }
                }
                .frame(width: 11, height: 10)
                if ouverture > 0.001 {
                    Text(m.lecture.morceau?.titre ?? "").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                        .frame(maxWidth: 140, alignment: .leading)
                        .opacity(Double(lisseIlot((ouverture - 0.35) / 0.5)))
                }
            }
        case .rendezVous:
            pile(6) {
                GlypheIlot(nom: GlypheIlot.calendrier, couleur: CouleursIlot.rouge, taille: 12)
                texte((m.rendezVous ?? m.dernierRendezVous).map { PlanAgenda.court($0.debut.timeIntervalSince(m.maintenant())) } ?? "", .white, chiffres: true)
            }
        case .rappel:
            // la cloche et l'heure ; dans la bulle survolée, de quel rappel il s'agit
            let r = m.rappelVu
            pile(6) {
                GlypheIlot(nom: "bell.fill", couleur: CouleursIlot.jaune, taille: 12)
                texte(FormatIlot.heure(r?.echeance ?? m.maintenant()), CouleursIlot.jaune, chiffres: true)
                if ouverture > 0.001 {
                    Text(r?.texte ?? "").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                        .frame(maxWidth: 150, alignment: .leading)
                        .opacity(Double(lisseIlot((ouverture - 0.35) / 0.5)))
                }
            }
        case .micro:
            pile(6) {
                GlypheIlot(nom: "mic.slash.fill", couleur: CouleursIlot.rouge, taille: 12)
                texte("Coupé", CouleursIlot.rouge)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Micro coupé")
        case .claude:
            let s = m.claude ?? m.dernierClaude
            let t = m.texteClaude(s, taille: 12.5)
            pile(6) {
                EtoileClaude(couleur: CouleursIlot.corail).frame(width: 13, height: 13)
                if !t.isEmpty { texte(t, CouleursIlot.corail, chiffres: true) }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(s?.etat == .attend ? "Claude attend ta réponse" : "Claude au travail")
            .accessibilityValue(t)
        case .reveil:
            let l = (m.reveil ?? m.dernierReveil)?.libelle() ?? ""
            pile(6) {
                GlypheIlot(nom: "alarm", couleur: CouleursIlot.ambre, taille: 12)
                texte(l, CouleursIlot.ambre, chiffres: true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Réveil, \(l)")
        case .reunion:
            let r = m.reunion ?? m.derniereReunion
            pile(6) {
                PointReunion(enPause: r.enPause, animer: !m.reduire && !m.statique)
                ChronoReunion(m: m, taille: 12.5).fixedSize()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(r.enPause ? "Réunion en pause" : "Réunion en cours")
        case .alerte:
            EmptyView()
        }
    }

    /// Couché : côte à côte ; debout : l'un sous l'autre, centrés.
    private func pile<C: View>(_ espace: CGFloat, @ViewBuilder _ c: () -> C) -> some View {
        let l: AnyLayout = debout ? AnyLayout(VStackLayout(spacing: 5)) : AnyLayout(HStackLayout(spacing: espace))
        return l { c() }
    }
    private func symbole(_ nom: String, _ c: Color) -> some View {
        Image(systemName: nom).font(.system(size: 14, weight: .semibold)).foregroundStyle(c)
    }
    private func texte(_ s: String, _ c: Color, chiffres: Bool = false) -> some View {
        Text(s).font(chiffres ? .system(size: 12.5, weight: .semibold).monospacedDigit() : .system(size: 12.5, weight: .semibold))
            .foregroundStyle(c).lineLimit(1).fixedSize()
    }
}

// MARK: la Lucarne libre

/// La Lucarne hors de l'encoche (régime libre), dans une zone de dessin plus grande que celle de l'encoche (`IlotMoteur.tailleLibre`) :
/// tenue ou en vol, la capsule est dessinée au milieu et la fenêtre la suit (cette vue ne bouge pas) ; posée, la vue reste fixe et la
/// forme y grandit vers l'intérieur de l'écran.
struct LucarneLibreVue: View {
    @ObservedObject var m: IlotMoteur

    var body: some View {
        let _ = m.rev
        let t = m.tailleVue
        let c = m.capsuleVue
        let forme = FormeNoire(points: TraceLucarne.calculer(c))
        let leve = min(1, max(0, m.lucarne.capsule.leve.x))
        let centre = UnitPoint(x: (Double(t.width) / 2 + c.centreX) / Double(t.width), y: c.centreY / Double(t.height))
        ZStack(alignment: .topLeading) {
            OmbreLucarne(forme: forme, deplie: m.lucarneDeplie > 0.5, leve: leve, noir: m.lucarne.capsule.fonduNoir)
            VerreLucarneVue(m: m, forme: forme, capsule: c, taille: t)
            contenu(forme: forme, taille: t)
            if let b = m.bulleLibreVue, let a = m.pastille { bulle(a, b, taille: t) }
        }
        .frame(width: t.width, height: t.height, alignment: .topLeading)
        .scaleEffect(m.presse ? 1.015 : 1, anchor: centre)
        .animation(m.reduire ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: m.presse)
        // le bourdonnement d'une alerte, comme dans l'encoche
        .offset(x: CGFloat(m.secousse.x))
        // une dictée l'efface, comme dans l'encoche (décision C du plan)
        .opacity(m.cache ? 0 : 1)
    }

    /// Le contenu rogné à la forme : le déplié (les écrans de l'encoche, posés pour la forme d'arrivée) ou le contenu compact au milieu
    /// de la pilule. L'appui sur la forme, hors des boutons (qui gardent leurs clics) : l'appui long (la vue d'hébergement suit le
    /// pointeur), relâché avant 0,4 s c'est un clic.
    private func contenu(forme: FormeNoire, taille t: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            if m.lucarneDepliee, let o = m.origineCalques {
                IlotCalques(m: m, g: m.grille).offset(x: o.x, y: o.y)
            }
            let c = m.capsuleVue
            ForEach(VueIlot.allCases, id: \.self) { v in
                if let g = GenreCompact.de(v), m.visible(v) {
                    ContenuCompactLucarne(m: m, genre: g, debout: m.lucarne.place.debout && !m.lucarneEnMain)
                        .aspectIlot(m.aspect(v, rang: 0), ancre: .center)
                        .position(x: t.width / 2 + CGFloat(c.centreX), y: CGFloat(c.centreY))
                }
            }
        }
        .frame(width: t.width, height: t.height, alignment: .topLeading)
        .clipShape(forme)
        .contentShape(forme)
        .gesture(DragGesture(minimumDistance: 0).onChanged { _ in m.appuiSurForme() })
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { m.clicForme() }
    }

    /// La bulle de la deuxième activité : une goutte de verre qui sort de la pilule, du côté de l'intérieur de l'écran.
    private func bulle(_ a: ActiviteIlot, _ b: CapsuleLucarne, taille t: CGSize) -> some View {
        let w = CGFloat(b.largeur), h = CGFloat(b.hauteur)
        return ContenuCompactLucarne(m: m, genre: .activite(a), debout: m.lucarne.place.debout)
            .opacity(m.aspectPastille.opacite)
            .frame(width: w, height: h)
            .clipShape(Capsule())
            .contentShape(Capsule())
            .onTapGesture { m.cliquerPastille() }
            .allowsHitTesting(m.pastilleMontree)
            .accessibilityLabel("Autre activité")
            .accessibilityAddTraits(.isButton)
            .position(x: t.width / 2 + CGFloat(b.centreX), y: CGFloat(b.centreY))
    }
}

/// Le verre : un verre clair dans la forme (et la goutte de la bulle, dans le même conteneur : elles se fondent l'une dans l'autre en
/// se séparant), le givre, le voile noir (lisibilité, fondu noir ↔ verre) et le liseré (le verre se voit sur une fenêtre blanche). Dans
/// les rendus PNG (ImageRenderer ne dessine ni le verre ni le givre), un faux verre : un blanc léger sous le même voile et le même liseré
/// (le rendu floute lui-même le faux écran sous la forme).
struct VerreLucarneVue: View {
    @ObservedObject var m: IlotMoteur
    var forme: FormeNoire
    var capsule: CapsuleLucarne
    var taille: CGSize

    var body: some View {
        let noir = m.lucarne.capsule.fonduNoir
        let voile = VerreLucarne.voile
        let bulle = m.bulleLibreVue
        ZStack(alignment: .topLeading) {
            if noir < 0.999 {
                if m.statique {
                    forme.fill(Color.white.opacity(0.16))
                    if let b = bulle { Capsule().fill(Color.white.opacity(0.16)).frame(width: b.largeur, height: b.hauteur).position(point(b)) }
                } else {
                    GlassEffectContainer(spacing: 14) {
                        ZStack(alignment: .topLeading) {
                            verre(capsule, forme: forme)
                            if let b = bulle { Color.clear.frame(width: b.largeur, height: b.hauteur).glassEffect(.clear, in: Capsule()).position(point(b)) }
                        }
                        .frame(width: taille.width, height: taille.height, alignment: .topLeading)
                    }
                }
            }
            // le givre : le fond flouté sous le contenu (les lettres d'une page derrière ne se mêlent plus au texte), rentré du bord
            if noir < 0.999, !m.statique {
                FormeNoire(points: TraceLucarne.calculer(VerreLucarne.givre(capsule))).fill(.ultraThinMaterial)
                if let b = bulle { Capsule().fill(.ultraThinMaterial).frame(width: max(0, b.largeur - 2 * VerreLucarne.rentreeGivre), height: max(0, b.hauteur - 2 * VerreLucarne.rentreeGivre)).position(point(b)) }
            }
            forme.fill(Color.black.opacity(voile + (1 - voile) * noir))
            if let b = bulle { Capsule().fill(Color.black.opacity(voile)).frame(width: b.largeur, height: b.hauteur).position(point(b)) }
            // le liseré : un trait clair à l'intérieur, un trait sombre très fin au bord (lisible sur blanc comme sur noir)
            Group {
                forme.stroke(Color.white.opacity(0.28), lineWidth: 1.2)
                forme.stroke(Color.black.opacity(0.22), lineWidth: 0.5)
                if let b = bulle {
                    Capsule().stroke(Color.white.opacity(0.28), lineWidth: 1.2).frame(width: b.largeur, height: b.hauteur).position(point(b))
                    Capsule().stroke(Color.black.opacity(0.22), lineWidth: 0.5).frame(width: b.largeur, height: b.hauteur).position(point(b))
                }
            }
            .opacity(1 - noir)
        }
        .frame(width: taille.width, height: taille.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private func point(_ c: CapsuleLucarne) -> CGPoint { CGPoint(x: taille.width / 2 + CGFloat(c.centreX), y: CGFloat(c.centreY)) }

    /// Le verre de la forme, posé sur le rectangle de la capsule (pas sur toute la zone de dessin : il n'échantillonne que là), avec la
    /// marge des épaules (la forme compacte de l'encoche, au décollage, déborde de 6 pt en haut).
    private func verre(_ c: CapsuleLucarne, forme: FormeNoire) -> some View {
        let marge = 8.0
        let l = c.largeur + 2 * marge, h = c.hauteur + marge
        let locale = CapsuleLucarne(x0: -c.largeur / 2, x1: c.largeur / 2, y0: marge, y1: marge + c.hauteur, s: c.s, r: c.r)
        return Color.clear
            .frame(width: l, height: h)
            .glassEffect(.clear, in: FormeNoire(points: TraceLucarne.calculer(locale)))
            .position(x: taille.width / 2 + CGFloat(c.centreX), y: CGFloat(c.y0 - marge + h / 2))
    }
}

/// L'ombre douce autour de la forme (jamais dessous : le verre la verrait), plus marquée dépliée et pendant la tenue.
struct OmbreLucarne: View {
    var forme: FormeNoire
    var deplie: Bool
    var leve: Double
    var noir: Double

    var body: some View {
        let o = deplie ? VerreLucarne.ombreDepliee : VerreLucarne.ombrePosee
        let opacite = o.opacite + 0.13 * leve, flou = o.flou + 7 * leve, y = o.y + 3 * leve
        forme.fill(Color.black)
            .blur(radius: flou)
            .offset(y: y)
            .opacity(opacite * (1 - 0.5 * noir))
            .mask {
                Rectangle().overlay { forme.fill(Color.black).blendMode(.destinationOut) }.compositingGroup()
            }
            .allowsHitTesting(false)
    }
}

/// L'anneau de l'appui long : sous le pointeur, il se remplit en 0,4 s (maquette lucarne-position.html), puis s'efface quand elle se
/// décolle (ou qu'on bouge avant).
struct AnneauAppuiLucarne: View {
    @ObservedObject var m: IlotMoteur

    var body: some View {
        let _ = m.rev
        if let a = m.anneauAppui {
            let d = 2 * IlotMoteur.rayonAnneau
            // sa propre horloge d'animation, le temps de l'appui seulement : seul l'anneau se redessine (pas l'îlot)
            TimelineView(.animation(paused: m.statique)) { _ in
                let t = ProcessInfo.processInfo.systemUptime - a.debut
                let fraction = min(1, max(0, t / GeoLucarne.dureeAppui))
                ZStack {
                    Circle().stroke(Color.black.opacity(0.3), lineWidth: 3)
                    Circle().trim(from: 0, to: fraction)
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .shadow(color: .black.opacity(0.6), radius: 1)
                }
                .frame(width: d, height: d)
                // un clic ordinaire (plus court) ne le montre jamais
                .opacity(min(1, max(0, (t - IlotMoteur.delaiAnneau) / 0.06)))
            }
            .frame(width: d, height: d)
            .position(a.centre)
            .allowsHitTesting(false)
        }
    }
}
