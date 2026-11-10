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
    static let marge: CGFloat = 16
    private func f(_ v: VueIlot) -> [Double] { GeoIlot.valeurs(v, hauteurBarre: Double(barre)) }
    /// Demi-largeur du corps (sous la barre) et du cou (dans la barre), depuis le centre.
    func corps(_ v: VueIlot) -> CGFloat { hc + CGFloat(f(v)[1]) }
    func cou(_ v: VueIlot) -> CGFloat { hc + CGFloat(f(v)[0]) }
    func hauteur(_ v: VueIlot) -> CGFloat { CGFloat(f(v)[2]) }
    /// Zone du contenu d'un écran déplié : le corps sous la barre, moins la marge.
    func zone(_ v: VueIlot, haut: CGFloat = 16, bas: CGFloat = 16) -> CGRect {
        let w = corps(v)
        return CGRect(x: -w + Self.marge, y: barre + haut, width: 2 * w - 2 * Self.marge, height: hauteur(v) - barre - haut - bas)
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
            ForEach(VueIlot.allCases, id: \.self) { v in
                if m.visible(v) { ecran(v) }
            }
        }
        .frame(width: IlotMoteur.largeur, height: IlotMoteur.hauteurMax, alignment: .topLeading)
    }

    @ViewBuilder private func ecran(_ v: VueIlot) -> some View {
        switch v {
        case .repos, .lectureCompact, .minuteurMinimal, .minuteurCompact: EmptyView()
        case .lectureEtendu: LectureEtendue(m: m, lecture: m.lecture, g: g)
        case .minuteurEtendu: minuteurEtendu
        case .minuteurLance, .minuteurFini: annonceMinuteur(v)
        case .rappelCompact: heureAile(.rappelCompact, FormatIlot.heure(rappelVu?.echeance ?? m.maintenant()), CouleursIlot.jaune)
        case .rappelEtendu: rappelEtendu
        case .rappelAjoute, .rappelFait, .rappelReporte: bandeauRappel(v)
        case .rappelListe: rappelListe
        case .agendaCompact:
            TimelineView(.periodic(from: Date(timeIntervalSinceReferenceDate: 0), by: 15)) { _ in
                heureAile(.agendaCompact, rdvVu.map { PlanAgenda.dans($0.debut.timeIntervalSince(m.maintenant())).replacingOccurrences(of: "dans ", with: "") } ?? "", .white)
            }
        case .agendaEtendu: agendaEtendu
        case .agendaAvant, .agendaDebut: annonceAgenda(v)
        case .notification, .notifications: annonceNotification(v)
        case .accueil: accueil
        }
    }

    // MARK: lignes d'annonce (bandeaux et alertes)

    /// Une annonce sur une ligne : [symbole] [titre / sous-titre] [actions]. Les trois blocs arrivent l'un après l'autre.
    /// `glyphe` nil : la place est gardée pour une pièce qui voyage (la cloche, le calendrier).
    private func annonce<G: View, D: View>(_ v: VueIlot, glyphe: G?, l1: String, l2: Text, @ViewBuilder droite: () -> D) -> some View {
        let alerte = GeoIlot.profondeur(v) > 75
        let z = g.zone(v, haut: alerte ? 20 : 16, bas: alerte ? 20 : 16)
        return HStack(spacing: 12) {
            Group { if let glyphe { glyphe } else { Color.clear } }
                .frame(width: 26, height: 26).aspectIlot(m.aspect(v, rang: 0), ancre: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(l1).font(TexteIlot.l1).tracking(-0.2).foregroundStyle(.white).lineLimit(1).truncationMode(.tail)
                l2.font(TexteIlot.l2).foregroundStyle(CouleursIlot.encre2).lineLimit(1).truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .aspectIlot(m.aspect(v, rang: 1), ancre: .topLeading)
            droite().fixedSize().aspectIlot(m.aspect(v, rang: 2), ancre: .topTrailing)
        }
        .frame(width: z.width, height: z.height)
        .offset(x: IlotMoteur.largeur / 2 + z.minX, y: z.minY)
    }
    private func meta(_ s: String) -> some View {
        Text(s).font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundStyle(CouleursIlot.encre2).lineLimit(1)
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
                    Text(tempsRestant(d)).font(.system(size: 40, weight: .semibold).monospacedDigit()).tracking(-0.4)
                        .foregroundStyle(CouleursIlot.ambre).lineLimit(1).fixedSize()
                }
                .frame(width: 160, height: 48, alignment: .trailing)
                .scaleEffect(fs / 40, anchor: .topTrailing)
                .opacity(a.opacite).blur(radius: a.flou)
                .offset(x: IlotMoteur.largeur / 2 + d - 160, y: haut)
                .accessibilityLabel("Temps restant")
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

    @ViewBuilder private func annonceMinuteur(_ v: VueIlot) -> some View {
        let glyphe = GlypheIlot(nom: "timer", couleur: CouleursIlot.ambre, taille: 22)
        if v == .minuteurLance {
            let b = m.bandeauVu
            annonce(v, glyphe: glyphe, l1: b?.ligne1 ?? "Minuteur lancé", l2: Text(b?.ligne2 ?? "")) {
                tic { d in Text(tempsRestant(d)).font(.system(size: 15, weight: .semibold).monospacedDigit()).foregroundStyle(CouleursIlot.ambre) }
            }
        } else {
            annonce(v, glyphe: glyphe, l1: "Minuteur terminé", l2: Text((m.alerteVu?.libelle ?? "") + " \u{00B7} il est " + FormatIlot.heure(m.maintenant()))) {
                HStack(spacing: 8) {
                    CapIlot(titre: "Encore 5 min") { m.surAction(.minuteurRecommencer(minutes: 5)) }
                    CapIlot(titre: "OK", style: .ambre) { m.surAction(.alerteOK) }
                }
            }
        }
    }

    // MARK: rappels

    private var rappelVu: Rappel? { m.alerteVu?.rappel ?? m.rappelsSonnes.first ?? m.dernierRappel }

    /// La cloche (rappel) ou le calendrier (rendez-vous) : dans l'aile gauche au repos, à sa place dans l'annonce une fois déplié.
    private func voyageurGlyphe(_ f: FamilleIlot) -> some View {
        let p = m.ouverture(f)
        let a = m.aspect(f)
        let (vc, vx) = f.vues!
        let c = g.centreAile(vc, droite: false)
        let compact = CGRect(x: c - 13, y: g.barre / 2 - 13, width: 26, height: 26)
        let z = f == .rappel ? g.zone(vx, haut: 20, bas: 20) : g.zone(vx)
        let etendu = CGRect(x: z.minX, y: f == .rappel ? z.midY - 13 : z.minY - 2, width: 26, height: 26)
        let (r, ts) = voyageIlot(compact, etendu, p)
        let echelle = lerp(15.0 / 22.0, 1, ts)
        return Group {
            if f == .rappel {
                ClocheSecouee(taille: 22, secouer: m.courante == .rappelEtendu && !m.reduire && !m.statique)
            } else {
                GlypheIlot(nom: "calendar", couleur: CouleursIlot.rouge, taille: 22)
            }
        }
        .scaleEffect(echelle)
        .posee(r, a, ancre: .center, .center)
    }

    private var rappelEtendu: some View {
        let v = VueIlot.rappelEtendu, r = rappelVu
        let quand = r?.echeance ?? m.maintenant()
        return annonce(v, glyphe: Optional<EmptyView>.none, l1: r?.texte ?? "",
                       l2: Text("Rappel \u{00B7} ") + Text(FormatIlot.heure(quand)).foregroundColor(.white) + Text(" \u{00B7} " + ListeRappels.retard(de: quand, maintenant: m.maintenant()))) {
            HStack(spacing: 8) {
                CapIlot(titre: "Plus tard", etiquette: "Plus tard, dans 10 minutes") { if let r { m.surAction(.rappelPlusTard(r.id)) } }
                CapIlot(titre: "Fait", style: .jaune) { if let r { m.surAction(.rappelFait(r.id)) } }
            }
        }
    }

    @ViewBuilder private func bandeauRappel(_ v: VueIlot) -> some View {
        let b = m.bandeauVu
        switch v {
        case .rappelAjoute:
            annonce(v, glyphe: GlypheIlot(nom: "bell.fill", couleur: CouleursIlot.jaune, taille: 21), l1: b?.ligne1 ?? "Rappel ajouté",
                    l2: Text([b?.ligne2 ?? "", b?.meta ?? ""].filter { !$0.isEmpty }.joined(separator: " \u{00B7} "))) {
                CapIlot(titre: "Annuler") { if let id = b?.rappelId { m.surAction(.rappelAnnuler(id)) } }
            }
        case .rappelFait:
            annonce(v, glyphe: GlypheIlot(nom: "checkmark.circle.fill", couleur: CouleursIlot.vert, taille: 22), l1: b?.ligne1 ?? "Fait", l2: Text(b?.ligne2 ?? "")) { EmptyView() }
        default:
            annonce(v, glyphe: GlypheIlot(nom: "clock.arrow.circlepath", couleur: CouleursIlot.jaune, taille: 21), l1: b?.ligne1 ?? "", l2: Text(b?.ligne2 ?? "")) {
                meta(b?.meta ?? "")
            }
        }
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

    private var rdvVu: EvenementAgenda? { m.alerteVu?.evenement ?? m.rendezVous ?? m.dernierRendezVous }

    private var agendaEtendu: some View {
        let v = VueIlot.agendaEtendu, e = rdvVu
        let z = g.zone(v)
        let x = z.minX + 38, l = z.maxX - x
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
                Text(e.flatMap { $0.lien.map(adresseCourte) ?? $0.lieu } ?? "").font(TexteIlot.l2).lineLimit(1).truncationMode(.middle)
            }
            .foregroundStyle(CouleursIlot.encre2)
            .posee(CGRect(x: x, y: z.minY + 41, width: l, height: 16), m.aspect(v, rang: 2), ancre: .topLeading)
            if let e {
                HStack(spacing: 8) {
                    if visio { CapIlot(titre: "Rejoindre", icone: "video.fill", style: .vert) { m.surAction(.rendezVousRejoindre(e)) } }
                    CapIlot(titre: "Noter la réunion", icone: "note.text") { m.surAction(.rendezVousNoter(e)) }
                    Spacer(minLength: 0)
                }
                .posee(CGRect(x: x, y: z.minY + 68, width: l, height: 32), m.aspect(v, rang: 3), ancre: .topLeading)
            }
        }
    }
    private func adresseCourte(_ u: URL) -> String { (u.host ?? "") + u.path }

    @ViewBuilder private func annonceAgenda(_ v: VueIlot) -> some View {
        let e = rdvVu
        let glyphe = GlypheIlot(nom: "calendar", couleur: CouleursIlot.rouge, taille: 21)
        if v == .agendaAvant {
            let b = m.bandeauVu
            annonce(v, glyphe: glyphe, l1: b?.ligne1 ?? e?.titre ?? "", l2: Text(b?.ligne2 ?? "")) { meta(e.map { FormatIlot.heure($0.debut) } ?? "") }
        } else {
            let visio = e?.lien != nil
            annonce(v, glyphe: glyphe, l1: (e?.titre ?? "") + " commence", l2: Text("Maintenant" + (visio ? " \u{00B7} Visio" : ""))) {
                if let e, visio { CapIlot(titre: "Rejoindre", icone: "video.fill", style: .vert) { m.surAction(.rendezVousRejoindre(e)) } }
            }
        }
    }

    // MARK: notifications

    private func glypheApp(_ app: String) -> GlypheIlot {
        let a = app.lowercased()
        if a.contains("message") { return GlypheIlot(nom: "message.fill", couleur: CouleursIlot.vert, taille: 21) }
        if a.contains("mail") { return GlypheIlot(nom: "envelope.fill", couleur: CouleursIlot.bleu, taille: 20) }
        if a.contains("calend") { return GlypheIlot(nom: "calendar", couleur: CouleursIlot.rouge, taille: 21) }
        if ["slack", "teams", "discord", "whatsapp", "telegram", "signal"].contains(where: a.contains) {
            return GlypheIlot(nom: "bubble.left.and.bubble.right.fill", couleur: Color.white.opacity(0.85), taille: 19)
        }
        return GlypheIlot(nom: "app.badge.fill", couleur: Color.white.opacity(0.85), taille: 21)
    }

    @ViewBuilder private func annonceNotification(_ v: VueIlot) -> some View {
        let n = m.notifications
        if v == .notification, let x = n.last {
            annonce(v, glyphe: glypheApp(x.app), l1: x.titre.isEmpty ? x.app : x.titre, l2: Text(x.corps.isEmpty ? x.app : x.corps)) { meta("maintenant") }
        } else {
            annonce(v, glyphe: GlypheIlot(nom: "bell.badge.fill", couleur: Color.white.opacity(0.85), taille: 21),
                    l1: LectureNotifications.titreDeGroupe(max(2, n.count)), l2: Text(LectureNotifications.ligneDeGroupe(n))) { EmptyView() }
        }
    }

    // MARK: accueil

    /// L'accueil (clic sur l'îlot vide) : une liste à filets fins, une ligne par chose à faire, l'action à droite.
    private var accueil: some View {
        let v = VueIlot.accueil
        let z = g.zone(v, haut: 10, bas: 12)
        let e = m.rendezVousSuivant
        let d = m.derniereDictee
        return VStack(spacing: 0) {
            ligneAccueil(v, 0, glyphe: GlypheIlot(nom: "calendar", couleur: CouleursIlot.rouge, taille: 17),
                         titre: e?.titre ?? (m.calendrierActif ? "Rien de prévu" : "Calendrier éteint"),
                         sous: e.map { FormatIlot.heure($0.debut) + " \u{00B7} " + PlanAgenda.dans($0.debut.timeIntervalSince(m.maintenant())) } ?? (m.calendrierActif ? "Aucun rendez-vous à venir" : "Activable dans les réglages")) {
                if let e, e.lien != nil { CapIlot(titre: "Rejoindre", icone: "video.fill", style: .vert, hauteur: 28) { m.surAction(.rendezVousRejoindre(e)) } }
            }
            ligneAccueil(v, 1, glyphe: GlypheIlot(nom: "timer", couleur: CouleursIlot.ambre, taille: 17), titre: "Minuteur", sous: "Lancer un compte à rebours") {
                HStack(spacing: 6) {
                    ForEach([5, 10, 25], id: \.self) { n in
                        CapIlot(titre: "\(n) min", hauteur: 28, etiquette: "Minuteur de \(n) minutes") { m.surAction(.minuteurLancer(minutes: Double(n))) }
                    }
                }
            }
            ligneAccueil(v, 2, glyphe: GlypheIlot(nom: "bell.fill", couleur: CouleursIlot.jaune, taille: 16), titre: "Rappel", sous: "Dis \u{00AB}\u{00A0}appeler Paul à 15 h\u{00A0}\u{00BB}") {
                CapIlot(titre: "Dire un rappel", icone: "mic.fill", hauteur: 28) { m.surAction(.rappelFormulaire) }
            }
            ligneAccueil(v, 3, glyphe: GlypheIlot(nom: "quote.opening", couleur: Color.white.opacity(0.7), taille: 15),
                         titre: d?.texte ?? "Rien pour l\u{2019}instant", police: TexteIlot.extrait, couleurTitre: Color.white.opacity(0.86),
                         sous: "Dernière dictée" + (d.map { " \u{00B7} il y a " + $0.age } ?? ""), filet: false) {
                if d != nil { CapIlot(titre: "Coller", hauteur: 28, etiquette: "Coller la dernière dictée") { m.surAction(.collerLaDerniereDictee) } }
            }
            Spacer(minLength: 0)
        }
        .frame(width: z.width, height: z.height, alignment: .top)
        .offset(x: IlotMoteur.largeur / 2 + z.minX, y: z.minY)
    }

    private func ligneAccueil<G: View, D: View>(_ v: VueIlot, _ rang: Int, glyphe: G, titre: String, police: Font = TexteIlot.ligne, couleurTitre: Color = .white,
                                                sous: String, filet avecFilet: Bool = true, @ViewBuilder droite: () -> D) -> some View {
        HStack(spacing: 12) {
            glyphe.frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(titre).font(police).tracking(-0.1).foregroundStyle(couleurTitre).lineLimit(1).truncationMode(.tail)
                Text(sous).font(TexteIlot.l2).foregroundStyle(CouleursIlot.encre2).lineLimit(1).truncationMode(.tail)
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
            .accessibilityHidden(true)
        }
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
        let x = art.maxX + 14, l = w - GrilleIlot.marge - x
        let titre = lecture.morceau?.titre ?? ""
        let musique = lecture.genre == .musique
        ZStack(alignment: .topLeading) {
            TitreDefilant(texte: titre, police: TexteIlot.titre, largeur: l, defiler: !m.reduire && !m.statique)
                .id(titre)
                .transition(.opacity)
                .posee(CGRect(x: x, y: b + 31, width: l, height: 21), m.aspect(v, rang: 0), ancre: .topLeading)
            Text(lecture.sousTitre).font(TexteIlot.source).foregroundStyle(CouleursIlot.encre2).lineLimit(1).truncationMode(.tail)
                .posee(CGRect(x: x, y: b + 54, width: l, height: 17), m.aspect(v, rang: 1), ancre: .topLeading)
            BarreLecture(lecture: lecture, largeur: 2 * w - 2 * GrilleIlot.marge, teinte: teinteIlot(lecture.teinte.clair))
                .posee(CGRect(x: -w + GrilleIlot.marge, y: b + 98, width: 2 * w - 2 * GrilleIlot.marge, height: 20), m.aspect(v, rang: 2))
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
                BoutonNu(symbole: "forward.end.fill", taille: 15, discret: true, etiquette: "Suivant") { lecture.surSuivant() }
                    .posee(CGRect(x: w - GrilleIlot.marge - 40, y: b + 125, width: 40, height: 40), m.aspect(v, rang: 3), ancre: .center)
            }
        }
        .animation(m.reduire ? nil : .easeOut(duration: 0.24), value: titre)
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

/// La deuxième activité, sous la barre : elle « goutte » de l'îlot (un pont liquide qui s'étire puis casse), puis montre son contenu.
struct PastilleVue: View {
    @ObservedObject var m: IlotMoteur

    var body: some View {
        let chute = CGFloat(m.pastilleChute.x), ouv = CGFloat(min(1.05, max(0, m.pastilleOuverte.x)))
        if let a = m.pastille, chute > 0.005 {
            let b = m.geometrie.hauteur
            let y = 6 + b * chute
            let x0 = m.xPastille
            let base = m.largeurPastille(a), large = m.largeurPastilleOuverte(a)
            let l = base + (large - base) * ouv
            let h = IlotMoteur.hauteurPastille
            let ilot = m.trace
            let ecart = y - CGFloat(ilot.hauteur)
            ZStack(alignment: .topLeading) {
                if !m.reduire, ecart < 14, chute < 0.995 {
                    goutte(x0: x0, y: y, l: l, ecart: ecart, cou: CGFloat(min(ilot.bande, Double(x0 + 62))), hauteurIlot: CGFloat(ilot.hauteur))
                }
                Capsule().fill(Color.black)
                    .frame(width: l, height: h)
                    .contentShape(Capsule())
                    .onTapGesture { m.cliquerPastille() }
                    .allowsHitTesting(m.pastilleMontree)
                    .offset(x: IlotMoteur.largeur / 2 + x0, y: y)
                    .accessibilityLabel("Autre activité")
                    .accessibilityAddTraits(.isButton)
                contenu(a, ouverture: ouv)
                    .frame(width: l, height: h, alignment: .leading)
                    .clipShape(Capsule())
                    .opacity(m.aspectPastille.opacite)
                    .scaleEffect(a == .lecture ? 1 : 1 + 0.05 * ouv, anchor: .leading)
                    .allowsHitTesting(false)
                    .offset(x: IlotMoteur.largeur / 2 + x0, y: y)
            }
            .opacity(m.pastilleMontree ? 1 : Double(min(1, chute * 1.2)))
        }
    }

    /// Le pont liquide : la bande droite de l'îlot et la pastille, floutées puis seuillées (métaballe). Seulement pendant la chute.
    private func goutte(x0: CGFloat, y: CGFloat, l: CGFloat, ecart: CGFloat, cou: CGFloat, hauteurIlot: CGFloat) -> some View {
        let flou = ecart < 3 ? 5 : max(0.4, min(5, 5 - (ecart - 3) * 0.55))
        return Canvas { ctx, taille in
            let ox = taille.width / 2
            ctx.addFilter(.alphaThreshold(min: 0.5, color: .black))
            ctx.addFilter(.blur(radius: flou * 1.6))
            ctx.drawLayer { c in
                let gauche = x0 - 6
                c.fill(Path(roundedRect: CGRect(x: ox + gauche, y: -14, width: max(0, cou - gauche), height: hauteurIlot + 14), cornerRadius: 10), with: .color(.black))
                c.fill(Path(roundedRect: CGRect(x: ox + x0 + 1, y: y + 1, width: l - 2, height: IlotMoteur.hauteurPastille - 2), cornerRadius: 12), with: .color(.black))
            }
        }
        .frame(width: IlotMoteur.largeur, height: IlotMoteur.hauteurMax)
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
                GlypheIlot(nom: "calendar", couleur: CouleursIlot.rouge, taille: 12)
                Text((m.rendezVous ?? m.dernierRendezVous).map { PlanAgenda.dans($0.debut.timeIntervalSince(m.maintenant())).replacingOccurrences(of: "dans ", with: "") } ?? "")
                    .font(.system(size: 12.5, weight: .semibold).monospacedDigit()).foregroundStyle(.white).lineLimit(1).fixedSize()
            }
            .padding(.leading, 10)
        case .rappel:
            HStack(spacing: 6) {
                GlypheIlot(nom: "bell.fill", couleur: CouleursIlot.jaune, taille: 12)
                Text(FormatIlot.heure((m.rappelsSonnes.first ?? m.dernierRappel)?.echeance ?? m.maintenant()))
                    .font(.system(size: 12.5, weight: .semibold).monospacedDigit()).foregroundStyle(CouleursIlot.jaune).lineLimit(1).fixedSize()
            }
            .padding(.leading, 10)
        case .alerte:
            EmptyView()
        }
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
        let g = GrilleIlot(hc: m.demiCamera, barre: m.geometrie.hauteur)
        let forme = FormeNoire(points: m.trace)
        let s = Double(min(1, max(0, (CGFloat(m.geo[2].x) - g.barre) / 70)))
        ZStack(alignment: .topLeading) {
            forme.fill(Color.black)
                .shadow(color: .black.opacity(0.42 * s), radius: 10 * s, x: 0, y: 5 * s)
            IlotCalques(m: m, g: g)
                .clipShape(forme)
                .contentShape(forme)
                .onTapGesture { m.clicForme() }
            PastilleVue(m: m)
        }
        .frame(width: IlotMoteur.largeur, height: IlotMoteur.hauteurMax, alignment: .topLeading)
        .offset(x: CGFloat(m.secousse.x))
        .opacity(m.cache && m.courante == .repos && m.geo.allSatisfy(\.fini) ? 0 : 1)
    }
}
