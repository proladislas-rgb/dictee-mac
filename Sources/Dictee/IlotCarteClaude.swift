import AppKit
import SwiftUI
import DicteeCore

// « Claude Code en carte » (maquette design/maquettes/ilot-claude-plus.html, étapes 1 à 7, validée) :
// - replié : l'étoile dans son anneau, « 3/7 » et un petit « 2 » quand deux sessions travaillent (aile gauche) ; le NOM de la tâche en
//   cours qui défile doucement s'il est trop long (aile droite, une seule animation Core Animation, rien quand rien ne bouge) ; en ambre
//   quand une session attend une réponse ;
// - la carte « Claude Code » (bouton du Centre, ou survol quand une session attend) : un bloc par session, la session qui attend en haut
//   avec un cadre ambre et sa question, la liste des tâches (faites cochées, en cours en gras, à faire), « Ouvrir » ramène la bonne
//   fenêtre du Terminal ; la carte défile si elle dépasse la hauteur du Centre.

// MARK: - les mesures de la carte

/// Les mesures de la carte (maquette, en points) : elles servent au dessin, à la hauteur de la forme et aux essais (où cliquer).
@MainActor
enum PlanCarteClaude {
    /// 14 de marge, l'en-tête (26), 8 : la liste commence là ; elle se termine 14 pt avant le bas de la forme.
    static let haut: CGFloat = 14, entete: CGFloat = 26, ecartEntete: CGFloat = 8, bas: CGFloat = 14
    /// Un bloc : 10 au-dessus, la ligne de tête (34), [la question], [3 + 19 par tâche], 9 dessous ; 8 entre deux blocs.
    static let ligneTete: CGFloat = 34, ligneTache: CGFloat = 19, ecartBlocs: CGFloat = 8
    static let margeHaut: CGFloat = 10, margeBas: CGFloat = 9, margeGauche: CGFloat = 12, margeDroite: CGFloat = 10
    /// La question (serif 15, lignes de 20 pt, trois au plus), décalée sous le nom du projet (32 pt).
    static let policeQuestion: CGFloat = 15, ligneQuestion: CGFloat = 20, retraitQuestion: CGFloat = 32, lignesQuestion = 3
    /// La place de la liste quand la carte est à sa plus grande hauteur (celle du Centre) : au-delà, elle défile.
    static var listeMax: CGFloat { CGFloat(GeoIlot.profondeurCentre) - haut - entete - ecartEntete - bas }
    /// Sans session : une ligne.
    static let vide: CGFloat = 44

    static func zone(_ g: GrilleIlot) -> CGRect { g.zoneCarte(.claudeCarte, haut: haut, bas: bas) }
    static func cadreEntete(_ g: GrilleIlot) -> CGRect { let z = zone(g); return CGRect(x: z.minX, y: z.minY, width: z.width, height: entete) }
    static func cadreListe(_ g: GrilleIlot) -> CGRect {
        let z = zone(g)
        return CGRect(x: z.minX, y: z.minY + entete + ecartEntete, width: z.width, height: max(0, z.maxY - z.minY - entete - ecartEntete))
    }

    static var policeSerif: NSFont {
        let base = NSFont.systemFont(ofSize: policeQuestion)
        return base.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: policeQuestion) } ?? base
    }
    /// La question d'une session qui attend (texte en français si reconnu), entre guillemets ; nil : rien à citer.
    static func question(_ s: SessionClaude) -> String? {
        guard s.etat == .attend, let q = TexteClaude.question(s.question) else { return nil }
        return "«\u{202F}" + q + "\u{202F}»"
    }
    /// Le nombre de lignes de la question à la largeur `l` (mesurée, Core Text), trois au plus.
    static func lignes(_ q: String, largeur l: CGFloat) -> Int {
        let r = (q as NSString).boundingRect(with: CGSize(width: max(20, l), height: 1000), options: [.usesLineFragmentOrigin, .usesFontLeading],
                                              attributes: [.font: policeSerif])
        let h = policeSerif.ascender - policeSerif.descender + policeSerif.leading
        return min(lignesQuestion, max(1, Int((r.height / max(1, h)).rounded())))
    }
    static func largeurQuestion(_ largeurBloc: CGFloat) -> CGFloat { largeurBloc - margeGauche - margeDroite - retraitQuestion }
    /// La hauteur d'un bloc de session, pour un bloc large de `l` pt.
    static func hauteur(_ s: SessionClaude, largeur l: CGFloat) -> CGFloat {
        var h = margeHaut + ligneTete + margeBas
        if let q = question(s) { h += 5 + CGFloat(lignes(q, largeur: largeurQuestion(l))) * ligneQuestion + 3 }
        if s.etat != .termine, !s.taches.isEmpty { h += 3 + CGFloat(s.taches.count) * ligneTache }
        return h
    }
    /// La hauteur de toute la liste (sans limite).
    static func hauteurListe(_ m: IlotMoteur, largeur l: CGFloat) -> CGFloat {
        let s = m.sessionsClaude
        guard !s.isEmpty else { return vide }
        return s.map { hauteur($0, largeur: l) }.reduce(0, +) + ecartBlocs * CGFloat(s.count - 1)
    }
    /// La largeur d'un bloc : celle de la carte (comme le Centre, la place des points en moins).
    static func largeur(_ m: IlotMoteur) -> CGFloat {
        let corps = m.demiCamera + CGFloat(GeoIlot.valeurs(.claudeCarte, hauteurBarre: 0)[1])
        return 2 * corps - 2 * GrilleIlot.marge - GrilleIlot.placePoints
    }
    /// La profondeur de la carte sous la barre : l'en-tête et la liste, jusqu'à celle du Centre.
    static func profondeur(_ m: IlotMoteur) -> CGFloat {
        haut + entete + ecartEntete + min(listeMax, hauteurListe(m, largeur: largeur(m))) + bas
    }
    /// Ce que la liste a de trop : jusqu'où on peut la faire défiler.
    static func depassement(_ m: IlotMoteur) -> CGFloat { max(0, hauteurListe(m, largeur: largeur(m)) - listeMax) }
    /// Le haut du bloc n° `i` dans la liste (avant défilement), depuis le haut de la liste.
    static func hautBloc(_ i: Int, _ m: IlotMoteur) -> CGFloat {
        let l = largeur(m)
        return m.sessionsClaude.prefix(i).map { hauteur($0, largeur: l) + ecartBlocs }.reduce(0, +)
    }
    /// Le milieu du bouton « Ouvrir » du bloc n° `i` (essais : où cliquer), défilement compris.
    static func pointOuvrir(_ i: Int, _ m: IlotMoteur) -> CGPoint {
        let c = cadreListe(m.grille)
        let titre = i < m.sessionsClaude.count && m.sessionsClaude[i].etat == .termine ? "Voir" : "Ouvrir"
        let lb = MesureIlot.texte(titre, 12.5, .bold) + 26
        return CGPoint(x: c.maxX - margeDroite - lb / 2, y: c.minY + hautBloc(i, m) - m.defilementClaude + margeHaut + ligneTete / 2)
    }
    /// La pilule « ‹ Centre » : l'étoile de Claude se pose juste après, 10 pt plus loin.
    static var pilule: CGFloat { PiluleCentre.largeur("Centre", retour: true) }
    /// Le milieu de « ‹ Centre » dans l'en-tête.
    static func pointCentre(_ m: IlotMoteur) -> CGPoint { let e = cadreEntete(m.grille); return CGPoint(x: e.minX + 34, y: e.midY) }
}

// MARK: - la carte

struct CarteClaudeVue: View {
    @ObservedObject var m: IlotMoteur
    var g: GrilleIlot

    var body: some View {
        let v = VueIlot.claudeCarte
        let liste = PlanCarteClaude.cadreListe(g)
        let total = PlanCarteClaude.hauteurListe(m, largeur: liste.width)
        let decale = m.defilementClaude
        ZStack(alignment: .topLeading) {
            // un clic dans le vide de la carte ne la range pas (on visait un bouton) ; seulement tant qu'elle est là
            Color.clear.contentShape(Rectangle()).onTapGesture {}
                .allowsHitTesting(m.courante == v)
                .accessibilityHidden(true)
                .posee(CGRect(x: -g.corps(v), y: g.barre, width: 2 * g.corps(v), height: max(0, g.hauteur(v) - g.barre)))
            entete.posee(PlanCarteClaude.cadreEntete(g), m.aspect(v, rang: 0), ancre: .topLeading)
            TimelineView(.periodic(from: Date(timeIntervalSinceReferenceDate: 0), by: 30)) { _ in
                let t = m.maintenant()
                VStack(alignment: .leading, spacing: PlanCarteClaude.ecartBlocs) {
                    if m.sessionsClaude.isEmpty {
                        Text("Aucune session de Claude Code en ce moment")
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(CouleursIlot.encre3).lineLimit(1)
                            .frame(maxWidth: .infinity, minHeight: PlanCarteClaude.vide, alignment: .center)
                    }
                    ForEach(m.sessionsClaude, id: \.id) { s in
                        BlocSessionClaude(s: s, a: t, largeur: liste.width, reduire: m.reduire || m.statique) { m.surAction(.claudeOuvrir(s)) }
                    }
                }
                .frame(width: liste.width, alignment: .topLeading)
                .offset(y: -decale)
            }
            .frame(width: liste.width, height: liste.height, alignment: .topLeading)
            // le vide entre deux blocs ne range pas l'îlot (un fond qui prend le clic, derrière les blocs, jamais autour d'eux)
            .background { Color.clear.contentShape(Rectangle()).onTapGesture {} }
            .clipped()
            // ni `.clipped()` ni `.mask` ne bornent les clics : sans cette forme, les blocs remontés hors de la liste prenaient les clics
            // de l'en-tête (« ‹ Centre » mort, un clic dans le vide qui rangeait l'îlot)
            .contentShape(Rectangle())
            // ce qui dépasse s'efface en bas (et en haut une fois qu'on a fait défiler) : on voit qu'il y a une suite
            .mask(FonduListe(haut: decale > 0.5, bas: total - decale > liste.height + 0.5))
            .posee(liste, m.aspect(v, rang: 1), ancre: .top)
        }
        .frame(width: IlotMoteur.largeur, height: IlotMoteur.hauteurMax, alignment: .topLeading)
    }

    private var entete: some View {
        let n = m.sessionsClaude.count
        return HStack(spacing: 10) {
            if m.cartes.contains(.centre) {
                PiluleCentre(titre: "Centre", retour: true, etiquette: "Revenir au Centre") { m.revenir() }.frame(width: PlanCarteClaude.pilule)
            }
            HStack(spacing: 6) {
                // la place de l'étoile : c'est l'étoile de l'îlot replié qui vient s'y poser (ClaudeVoyageur)
                Color.clear.frame(width: 14, height: 14)
                Text("Claude Code").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                if n > 0 {
                    Text("\u{00B7} \(n) session\(n > 1 ? "s" : "")").font(.system(size: 12.5, weight: .medium)).foregroundStyle(Color.white.opacity(0.5))
                }
            }
            .lineLimit(1).fixedSize()
            .allowsHitTesting(false)
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Image(systemName: "pin.fill").font(.system(size: 10, weight: .semibold))
                Text("Reste ouvert").font(.system(size: 11.5, weight: .semibold))
            }
            .foregroundStyle(Color.white.opacity(0.5))
            .allowsHitTesting(false)
            .opacity(m.epingle ? 1 : 0)
            .accessibilityHidden(!m.epingle)
        }
        .frame(height: PlanCarteClaude.entete)
    }
}

/// Le fondu du bas (et du haut) de la liste quand elle dépasse : 26 pt.
private struct FonduListe: View {
    var haut: Bool
    var bas: Bool
    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [haut ? .clear : .black, .black], startPoint: .top, endPoint: .bottom).frame(height: 26)
            Color.black
            LinearGradient(colors: [.black, bas ? .clear : .black], startPoint: .top, endPoint: .bottom).frame(height: 26)
        }
    }
}

/// Un bloc de session : l'anneau (ou la coche verte), le projet, l'état et depuis quand, « Ouvrir » ; la question en entier quand elle
/// attend ; la liste des tâches (faites cochées, en cours en gras, à faire).
struct BlocSessionClaude: View {
    var s: SessionClaude
    var a: Date
    var largeur: CGFloat
    var reduire: Bool
    var ouvrir: () -> Void

    private var couleur: Color {
        switch s.etat { case .attend: return CouleursIlot.ambre; case .termine: return Color(hex: 0x5FE08A); case .travaille: return CouleursIlot.corail }
    }

    var body: some View {
        let attend = s.etat == .attend, fini = s.etat == .termine
        let p = PlanCarteClaude.self
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Group {
                    if fini {
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
                            .frame(width: 22, height: 22).background(Circle().fill(CouleursIlot.vert))
                    } else {
                        AnneauIlot(taille: 22, trait: 2, couleur: attend ? CouleursIlot.ambre : CouleursIlot.corail, fraction: attend ? 1 : (s.progres?.fraction ?? 0)) {
                            EtoileClaude(couleur: attend ? CouleursIlot.ambre : CouleursIlot.corail).frame(width: 11, height: 11)
                        }
                    }
                }
                .frame(width: 22, height: 22)
                .allowsHitTesting(false)
                VStack(alignment: .leading, spacing: 1) {
                    Text(s.projet).font(.system(size: 14, weight: .bold)).foregroundStyle(.white).lineLimit(1).truncationMode(.middle)
                    let suite = TexteClaude.suite(s, a: a)
                    Text("\(Text(TexteClaude.etat(s.etat)).fontWeight(.bold).foregroundColor(couleur))\(Text(suite.isEmpty ? "" : " \u{00B7} " + suite).foregroundColor(Color.white.opacity(0.5)))")
                        .font(.system(size: 12, weight: .medium)).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .allowsHitTesting(false)
                BoutonSessionClaude(titre: fini ? "Voir" : "Ouvrir", plein: attend, etiquette: "Ouvrir la fenêtre du Terminal de \(s.projet)", action: ouvrir)
            }
            .frame(height: p.ligneTete)
            if let q = p.question(s) {
                let n = p.lignes(q, largeur: p.largeurQuestion(largeur))
                Text(q).font(.system(size: p.policeQuestion, design: .serif)).foregroundStyle(.white)
                    .lineLimit(p.lignesQuestion).truncationMode(.tail)
                    .lineSpacing(max(0, p.ligneQuestion - (p.policeSerif.ascender - p.policeSerif.descender + p.policeSerif.leading)))
                    .frame(width: p.largeurQuestion(largeur), height: CGFloat(n) * p.ligneQuestion, alignment: .topLeading)
                    .padding(.leading, p.retraitQuestion).padding(.top, 5).padding(.bottom, 3)
                    .allowsHitTesting(false)
            }
            if !fini, !s.taches.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(s.taches.enumerated()), id: \.offset) { _, t in ligne(t) }
                }
                .padding(.top, 3)
                .allowsHitTesting(false)
            }
        }
        .padding(.top, p.margeHaut).padding(.bottom, p.margeBas).padding(.leading, p.margeGauche).padding(.trailing, p.margeDroite)
        .frame(width: largeur, height: p.hauteur(s, largeur: largeur), alignment: .topLeading)
        // le fond du bloc prend le clic (un clic sur le projet ou une tâche ne range pas l'îlot) ; « Ouvrir » est posé par-dessus, en frère
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(attend ? CouleursIlot.ambre.opacity(0.12) : Color.white.opacity(0.08))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous)).onTapGesture {})
        .overlay { if attend { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(CouleursIlot.ambre.opacity(0.5), lineWidth: 1.5) } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(s.projet), \(TexteClaude.etat(s.etat))")
    }

    private func ligne(_ t: TacheClaude) -> some View {
        HStack(spacing: 8) {
            Group {
                switch t.statut {
                case .faite: Image(systemName: "checkmark").font(.system(size: 9.5, weight: .bold)).foregroundStyle(Color.white.opacity(0.5))
                case .enCours: Circle().strokeBorder(CouleursIlot.corail, lineWidth: 1.4).overlay(Circle().fill(CouleursIlot.corail).padding(2.6))
                case .aFaire: Circle().strokeBorder(Color.white.opacity(0.32), lineWidth: 1.4)
                }
            }
            .frame(width: t.statut == .faite ? 14 : 11, height: t.statut == .faite ? 14 : 11)
            .frame(width: 14, height: 14)
            Text(t.sujet).font(.system(size: 12.5, weight: t.statut == .enCours ? .bold : .medium))
                .foregroundStyle(t.statut == .enCours ? Color.white : Color.white.opacity(t.statut == .faite ? 0.38 : 0.55))
                .lineLimit(1).truncationMode(.tail)
        }
        .padding(.leading, 33)
        .frame(height: PlanCarteClaude.ligneTache, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(t.sujet)
        .accessibilityValue(t.statut == .faite ? "faite" : (t.statut == .enCours ? "en cours" : "à faire"))
    }
}

/// « Ouvrir » / « Voir » d'un bloc : 28 pt ; blanc, texte noir, pour la session qui attend (maquette).
struct BoutonSessionClaude: View {
    var titre: String
    var plein: Bool
    var etiquette: String
    var action: () -> Void
    @State private var survol = false
    var body: some View {
        Button(action: action) {
            Text(titre).font(.system(size: 12.5, weight: .bold)).lineLimit(1).fixedSize()
                .foregroundStyle(plein ? Color.black : Color.white)
                .padding(.horizontal, 13).frame(height: 28)
                .background(Capsule().fill(plein ? Color.white.opacity(survol ? 0.88 : 1) : Color.white.opacity(survol ? 0.24 : 0.14)))
                .contentShape(Capsule())
        }
        .buttonStyle(AppuiIlot(echelle: 0.92))
        .onHover { survol = $0 }
        .accessibilityLabel(etiquette)
    }
}

// MARK: - l'îlot replié

extension IlotMoteur {
    /// Ce que dit l'aile droite : le nom de la tâche en cours ; « second-cerveau attend ta réponse » quand une session attend.
    func nomClaude(_ s: SessionClaude?) -> String {
        guard let s else { return "" }
        if s.etat == .attend { return s.projet + " attend ta réponse" }
        return s.nom ?? ""
    }
    /// « 3/7 » dans l'aile gauche, s'il tient à côté de l'anneau (sinon l'anneau seul, qui dit déjà la part faite).
    func avancementClaude(_ s: SessionClaude?) -> String {
        guard let s, s.etat == .travaille, let p = s.progres else { return "" }
        return MesureIlot.texte(p.court, 12.5, .bold, chiffres: true) <= IlotMoteur.aileClaude - 20 - 6 ? p.court : ""
    }
    /// L'anneau (et l'étoile dedans) dans l'aile gauche : seul, il est au milieu de l'aile ; avec « 3/7 », le groupe est centré.
    func cadreAnneauClaude(_ g: GrilleIlot, _ v: VueIlot = .claudeCompact) -> CGRect {
        // le milieu de la place utile de l'aile : de 4 pt après la caméra à 8 pt avant le bord du cou
        let c = -(g.hc + 4 + g.bordAile(v)) / 2
        let t = avancementClaude(claude ?? dernierClaude)
        let groupe = t.isEmpty ? 20 : 20 + 6 + MesureIlot.texte(t, 12.5, .bold, chiffres: true)
        return CGRect(x: c - groupe / 2, y: g.barre / 2 - 10, width: 20, height: 20)
    }
}

/// Le compact : l'anneau autour de l'étoile, « 3/7 » (aile gauche, corail) ; le nom de la tâche qui défile (aile droite).
struct ClaudeAiles: View {
    @ObservedObject var m: IlotMoteur
    var g: GrilleIlot

    var body: some View {
        let v = VueIlot.claudeCompact
        let s = m.claude ?? m.dernierClaude
        let attend = s?.etat == .attend
        let r = m.cadreAnneauClaude(g)
        let t = m.avancementClaude(s)
        let nom = m.nomClaude(s)
        let d0 = g.hc + 4, l = g.bordAile(v) - d0
        return ZStack(alignment: .topLeading) {
            AnneauIlot(taille: 20, trait: 2, couleur: attend ? CouleursIlot.ambre : CouleursIlot.corail,
                       fraction: attend ? 1 : (s?.progres?.fraction ?? 0)) {}
                .posee(r, m.aspect(v, rang: 0), ancre: .center)
            if !t.isEmpty {
                Text(t).font(.system(size: 12.5, weight: .bold).monospacedDigit()).tracking(-0.2).foregroundStyle(CouleursIlot.corail)
                    .lineLimit(1).fixedSize()
                    .posee(CGRect(x: r.maxX + 6, y: 0, width: 30, height: g.barre), m.aspect(v, rang: 0), ancre: .leading, .leading)
            }
            Group {
                if m.statique || m.reduire {
                    TexteFixeClaude(texte: nom, ambre: attend, largeur: l)
                } else {
                    DefilantClaude(texte: nom, ambre: attend, largeur: l)
                }
            }
            .frame(width: l, height: 17)
            .posee(CGRect(x: d0, y: (g.barre - 17) / 2, width: l, height: 17), m.aspect(v, rang: 1), ancre: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(attend ? "\(s?.projet ?? "Claude") attend ta réponse" : "Claude au travail")
        .accessibilityValue([nom, s?.progres.map { "\($0.faites) tâches sur \($0.total)" } ?? ""].filter { !$0.isEmpty }.joined(separator: ", "))
    }
}

/// Le petit « 2 » sur l'anneau (deux sessions au travail) : blanc, cerné de noir (maquette).
struct BadgeClaude: View {
    var nombre: Int
    var body: some View {
        Text("\(nombre)").font(.system(size: 9.5, weight: .heavy).monospacedDigit()).foregroundStyle(.black)
            .padding(.horizontal, 3).frame(minWidth: 13, minHeight: 13)
            .background(Capsule().fill(Color.white))
            .background(Capsule().fill(Color.black).padding(-1.5))
            .fixedSize()
            .accessibilityLabel("\(nombre) sessions au travail")
    }
}

/// Le nom immobile (rendus PNG, « Réduire les animations ») : coupé par un fondu à droite s'il est trop long.
struct TexteFixeClaude: View {
    var texte: String
    var ambre: Bool
    var largeur: CGFloat
    var body: some View {
        let trop = MesureIlot.texte(texte, 12.5, .semibold) > largeur
        Text(texte).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(ambre ? Color(hex: 0xFFB340) : .white)
            .lineLimit(1).fixedSize()
            .frame(width: largeur, alignment: .leading)
            .clipped()
            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: trop ? 1 - 10 / max(1, largeur) : 1),
                                         .init(color: trop ? .clear : .black, location: 1)], startPoint: .leading, endPoint: .trailing))
    }
}

/// Le nom qui défile : UNE animation Core Animation (le texte deux fois, 22 pt d'écart, glisse d'une longueur après un temps d'arrêt),
/// jouée par le serveur d'affichage : l'app ne dessine rien pendant qu'il défile. Deux passages à chaque nouveau nom, puis il s'arrête
/// sur son début, comme dans la Dynamic Island : Claude travaille des heures, et une animation sans fin aurait tenu l'écran à sa pleine
/// fréquence tout ce temps (la maquette boucle sans fin). Un nom qui tient ne bouge pas. Fondus aux deux bords (3 pt à gauche, 10 à droite).
struct DefilantClaude: NSViewRepresentable {
    var texte: String
    var ambre: Bool
    var largeur: CGFloat
    /// ~22 pt/s, l'arrêt compris (maquette : 11 s pour un nom de ~240 pt).
    static let vitesse: CGFloat = 22, ecart: CGFloat = 22, arret = 0.14
    /// Combien de passages pour un même nom.
    static let passages: Float = 2

    final class Vue: NSView {
        /// La bande qui glisse (lue par l'essai : deux passages, pas une boucle sans fin).
        let bande = CALayer()
        private let t1 = CATextLayer(), t2 = CATextLayer()
        private let fondu = CAGradientLayer()
        private var dernier: (String, Bool, CGFloat)?
        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.masksToBounds = true
            for t in [t1, t2] { t.alignmentMode = .left; t.truncationMode = .none; bande.addSublayer(t) }
            layer?.addSublayer(bande)
            fondu.startPoint = CGPoint(x: 0, y: 0.5); fondu.endPoint = CGPoint(x: 1, y: 0.5)
            layer?.mask = fondu
        }
        required init?(coder: NSCoder) { fatalError() }
        override var isFlipped: Bool { true }
        override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); dernier = nil; needsLayout = true }
        override func layout() { super.layout(); if let d = dernier { dernier = nil; appliquer(d.0, ambre: d.1, largeur: d.2) } }

        func appliquer(_ texte: String, ambre: Bool, largeur: CGFloat) {
            if let d = dernier, d.0 == texte, d.1 == ambre, d.2 == largeur { return }
            dernier = (texte, ambre, largeur)
            let echelle = window?.backingScaleFactor ?? 2
            let police = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
            let couleur = ambre ? NSColor(red: 1, green: 0.702, blue: 0.251, alpha: 1) : NSColor.white
            let attr = NSAttributedString(string: texte, attributes: [.font: police, .foregroundColor: couleur])
            let l = MesureIlot.texte(texte, 12.5, .semibold)
            let h = bounds.height > 0 ? bounds.height : 17
            CATransaction.begin(); CATransaction.setDisableActions(true)
            bande.removeAllAnimations()
            let defile = l > largeur + 0.5
            for (i, t) in [t1, t2].enumerated() {
                t.string = attr
                t.contentsScale = echelle
                t.frame = CGRect(x: CGFloat(i) * (l + DefilantClaude.ecart), y: (h - 16) / 2, width: l + 2, height: 16)
                t.isHidden = i == 1 && !defile
            }
            bande.frame = CGRect(x: 0, y: 0, width: 2 * l + DefilantClaude.ecart + 4, height: h)
            let fg = 3 / max(1, largeur), fd = 10 / max(1, largeur)
            fondu.frame = CGRect(x: 0, y: 0, width: largeur, height: h)
            fondu.colors = defile ? [NSColor.clear.cgColor, NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
                                  : [NSColor.black.cgColor, NSColor.black.cgColor]
            fondu.locations = defile ? [0, NSNumber(value: Double(fg)), NSNumber(value: Double(1 - fd)), 1] : [0, 1]
            CATransaction.commit()
            guard defile else { return }
            let pas = l + DefilantClaude.ecart
            let a = CAKeyframeAnimation(keyPath: "transform.translation.x")
            a.values = [0, 0, -pas]
            a.keyTimes = [0, NSNumber(value: DefilantClaude.arret), 1]
            a.duration = Double(pas / DefilantClaude.vitesse) / (1 - DefilantClaude.arret)
            // fini, l'animation est retirée : la bande revient à 0, le premier nom à sa place (même image que la fin du passage)
            a.repeatCount = DefilantClaude.passages
            bande.add(a, forKey: "defil")
        }
    }
    func makeNSView(context: Context) -> Vue { Vue(frame: CGRect(x: 0, y: 0, width: largeur, height: 17)) }
    func updateNSView(_ v: Vue, context: Context) { v.appliquer(texte, ambre: ambre, largeur: largeur) }
}
