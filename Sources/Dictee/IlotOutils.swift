import AppKit
import SwiftUI
import DicteeCore

// Les Outils, 2e page du Centre (maquette design/maquettes/ilot-claude-plus.html, étapes 8 à 14, validée) :
// - la page elle-même est le Centre (CentreVue, page .outils) : quatre ronds (Garder éveillé, Presse-papiers, Reformuler, Notes), le
//   panneau « Garder éveillé » (1 h, 2 h, jusqu'à l'arrêt, éteindre) et la bande « Dicter une note » ; « Modifier » y marche comme sur le
//   Centre ; on y arrive par « Outils › » dans l'en-tête du Centre, par le 2e point de page, ou en faisant défiler ;
// - les cartes des outils (ici) : le presse-papiers (les cinq dernières copies, un clic recopie, « Coller » au survol, « Tout effacer »),
//   Reformuler (la dernière dictée ou le texte choisi, « Plus pro », « Plus court », « En anglais », « Remplacer », « Copier »), Note
//   rapide (« Dicter une note » : un clic, on parle, c'est noté ; les notes avec l'heure, « Vers Notes », supprimer).
// La logique pure est dans DicteeCore/OutilsIlot.swift ; ce qui touche au système dans OutilsControleur.swift.

// MARK: - ce que les cartes montrent (poussé par le contrôleur)

/// Une copie telle que l'îlot la montre : son titre, son détail, son style d'écriture, sa miniature (lue une fois, en mémoire).
struct CopieVue: Identifiable {
    enum Style { case texte, commande, nom }
    var element: ElementCopie
    var id: UUID { element.id }
    var titre: String
    var detail: String?
    var style: Style
    var icone: NSImage?
}

/// Reformuler : d'où vient le texte, lequel, et où en est la réécriture.
struct EtatReformulation {
    enum Phase: Equatable { case attente, calcul, fait(String), echec(String) }
    var source: SourceReformulation = .derniereDictee
    /// Le texte à réécrire (nil : aucune dictée, ou rien de choisi dans l'app au premier plan).
    var texte: String?
    var etiquette = "Dernière dictée"
    var style: StyleReformulation?
    var phase: Phase = .attente
    /// Ce qui s'est passé après « Remplacer » ou « Copier » (« Copié », « Copié : colle-le à la place »).
    var remarque: String?
    var resultat: String? { if case .fait(let t) = phase { return t } else { return nil } }
}

/// Où en est l'envoi d'une note vers l'app Notes.
enum EnvoiNote: Equatable { case enCours, fait, refuse, echec }

// MARK: - pièces communes

/// Une pilule des Outils (« 1 h », « Plus pro », « Remplacer », « Coller », « Vers Notes »…). Mesurée : `largeur` sert aux essais.
struct PiluleOutil: View {
    enum Style { case gris, blanc, ambre, vert, ambreDoux }
    var titre: String
    var icone: String? = nil
    var style: Style = .gris
    var hauteur: CGFloat = 28
    var taille: CGFloat = 13
    var padding: CGFloat = 12
    var etiquette: String? = nil
    var action: () -> Void
    @State private var survol = false

    static func largeur(_ t: String, icone: String? = nil, taille: CGFloat = 13, padding: CGFloat = 12) -> CGFloat {
        2 * padding + MesureIlot.texte(t, taille, .semibold) + (icone.map { MesureIlot.symbole($0, taille - 1.5, .bold) + 4 } ?? 0)
    }
    private var fond: Color {
        switch style {
        case .gris: return Color.white.opacity(survol ? 0.22 : 0.13)
        case .blanc: return Color.white.opacity(survol ? 0.9 : 1)
        case .ambre: return CouleursIlot.ambre.opacity(survol ? 0.88 : 1)
        case .vert: return CouleursIlot.vert.opacity(0.18)
        case .ambreDoux: return CouleursIlot.ambre.opacity(0.18)
        }
    }
    private var encre: Color {
        switch style {
        case .gris: return .white
        case .blanc, .ambre: return .black
        case .vert: return Color(hex: 0x5FE08A)
        case .ambreDoux: return Color(hex: 0xFFB340)
        }
    }
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icone { Image(systemName: icone).font(.system(size: taille - 1.5, weight: .bold)) }
                Text(titre).font(.system(size: taille, weight: .semibold)).lineLimit(1).fixedSize()
            }
            .foregroundStyle(encre)
            .padding(.horizontal, padding)
            .frame(height: hauteur)
            .background(Capsule().fill(fond))
            .contentShape(Capsule())
        }
        .buttonStyle(AppuiIlot(echelle: 0.92))
        .onHover { survol = $0 }
        .animation(.easeOut(duration: 0.12), value: survol)
        .accessibilityLabel(etiquette ?? titre)
    }
}

/// L'en-tête d'une carte d'outil : « ‹ Outils », le glyphe et le titre (et un mot gris), puis à droite « Reste ouvert » ou autre chose.
struct EnteteOutil<Droite: View>: View {
    @ObservedObject var m: IlotMoteur
    var glyphe: String
    var titre: String
    var sous: String? = nil
    @ViewBuilder var droite: () -> Droite

    /// « ‹ Outils » (PiluleCentre : 8, le chevron, 4, le mot, 11).
    static var pilule: CGFloat { 8 + MesureIlot.symbole("chevron.left", 10.5, .bold) + 4 + MesureIlot.texte("Outils", 12.5, .semibold) + 11 }

    var body: some View {
        HStack(spacing: 10) {
            PiluleCentre(titre: "Outils", retour: true, etiquette: "Revenir aux outils") { m.allerA(.outils) }.frame(width: Self.pilule)
            HStack(spacing: 6) {
                Image(systemName: glyphe).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white).frame(width: 15)
                Text(titre).font(.system(size: 13.5, weight: .bold)).foregroundStyle(.white)
                if let sous { Text(sous).font(.system(size: 12, weight: .medium)).foregroundStyle(Color.white.opacity(0.45)) }
            }
            .lineLimit(1).fixedSize()
            .allowsHitTesting(false)
            Spacer(minLength: 0)
            droite()
        }
        .frame(height: 26)
    }
}

/// « Reste ouvert » (l'îlot épinglé), comme dans l'en-tête du Centre.
struct ResteOuvert: View {
    @ObservedObject var m: IlotMoteur
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "pin.fill").font(.system(size: 10, weight: .semibold))
            Text("Reste ouvert").font(.system(size: 11.5, weight: .semibold))
        }
        .foregroundStyle(Color.white.opacity(0.5))
        .opacity(m.epingle ? 1 : 0)
        .allowsHitTesting(false)
        .accessibilityHidden(!m.epingle)
    }
}

/// Le vide d'une carte ne la range pas (on visait un bouton) ; seulement tant qu'elle est là.
private struct FondCarteOutil: View {
    @ObservedObject var m: IlotMoteur
    var g: GrilleIlot
    var v: VueIlot
    var body: some View {
        Color.clear.contentShape(Rectangle()).onTapGesture {}
            .allowsHitTesting(m.courante == v)
            .accessibilityHidden(true)
            .posee(CGRect(x: -g.corps(v), y: g.barre, width: 2 * g.corps(v), height: max(0, g.hauteur(v) - g.barre)))
    }
}

// MARK: - la page Outils : le panneau « Garder éveillé » et la bande « Dicter une note »

/// Le panneau « Garder éveillé » (76 pt, à la place des cases du Centre) : le titre (« Éveillé jusqu'à 15:44, puis veille normale »), puis
/// « 1 h », « 2 h », « Jusqu'à l'arrêt » (la durée choisie en ambre) et « Éteindre » quand il est allumé.
struct PanneauEveil: View {
    @ObservedObject var m: IlotMoteur

    /// Le milieu de la pilule n° `i` (0 : 1 h, 1 : 2 h, 2 : jusqu'à l'arrêt, 3 : éteindre) — essais : où cliquer.
    static func pointPilule(_ i: Int, _ m: IlotMoteur) -> CGPoint {
        guard let c = PlanCentre.cadre(.cases, m, page: .outils) else { return .zero }
        let titres = DureeEveil.allCases.map(\.titre) + ["Éteindre"]
        var x = c.minX + 14
        for j in 0..<i { x += PiluleOutil.largeur(titres[j]) + 6 }
        return CGPoint(x: x + PiluleOutil.largeur(titres[min(i, titres.count - 1)]) / 2, y: c.minY + 11 + 17 + 8 + 14)
    }

    var body: some View {
        let e = m.eveil
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(0.1))
                .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous)).onTapGesture {}
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    Image(systemName: "cup.and.saucer.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(CouleursIlot.ambre).frame(width: 18, height: 17)
                    Text("\(Text(e != nil ? "Éveillé" : "Garder le Mac éveillé").fontWeight(.semibold).foregroundColor(.white))\(Text(" " + (e?.detail() ?? "combien de temps ?")).font(.system(size: 12.5, weight: .medium)).foregroundColor(Color.white.opacity(0.5)))")
                        .font(.system(size: 13.5)).lineLimit(1)
                }
                .frame(height: 17)
                .allowsHitTesting(false)
                HStack(spacing: 6) {
                    ForEach(DureeEveil.allCases, id: \.self) { d in
                        PiluleOutil(titre: d.titre, style: e?.duree == d ? .ambre : .gris,
                                    etiquette: d == .sansLimite ? "Garder éveillé jusqu\u{2019}à ce que je l\u{2019}arrête" : "Garder éveillé \(d.titre)") {
                            m.epinglerLeCentre(); m.surAction(.eveil(d))
                        }
                    }
                    if e != nil {
                        PiluleOutil(titre: "Éteindre", etiquette: "Ne plus garder le Mac éveillé") { m.epinglerLeCentre(); m.surAction(.eveil(nil)) }
                    }
                }
                .frame(height: 28)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
        }
        .allowsHitTesting(!m.editionCentre)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Garder le Mac éveillé")
    }
}

/// La bande « Dicter une note » (40 pt) : un clic ouvre la carte Note rapide ET commence l'écoute (11/11 au soir : « Maintiens fn tant
/// que cette carte est ouverte » n'était pas compris ; un clic, on parle, c'est noté).
struct BandeNoteRapide: View {
    @ObservedObject var m: IlotMoteur
    @State private var survol = false

    var body: some View {
        let ed = m.editionCentre
        Button { if !ed { m.epinglerLeCentre(); m.ouvrirOutil(.outilNote); m.surAction(.noteDicter) } } label: {
            HStack(spacing: 10) {
                Image(systemName: "mic.fill").font(.system(size: 14, weight: .semibold)).foregroundStyle(CouleursIlot.rouge).frame(width: 16)
                Text("Dicter une note").font(.system(size: 13.5, weight: .semibold)).foregroundStyle(.white).lineLimit(1).fixedSize()
                Spacer(minLength: 12)
                Text("un clic, tu parles").font(.system(size: 12, weight: .medium)).foregroundStyle(Color.white.opacity(0.5)).lineLimit(1).fixedSize()
            }
            .padding(.leading, 14).padding(.trailing, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Capsule().fill(Color.white.opacity(survol && !ed ? 0.15 : 0.1)))
            .contentShape(Capsule())
        }
        .buttonStyle(AppuiIlot(echelle: ed ? 1 : 0.97))
        .onHover { survol = $0 }
        .tremblement(ed && (m.statique || !m.reduire), amplitude: 0.45, decale: false, fige: m.statique)
        .overlay(alignment: .topLeading) {
            if ed { BadgeRetirer(nom: "Dicter une note") { m.retirerDuCentre(.noteRapide) }.offset(x: -6, y: -6) }
        }
        .accessibilityLabel("Dicter une note : un clic, puis parle ; ce que tu dis devient une note")
    }
}

/// La touche fn dessinée (un cadre, « fn »).
struct ToucheFnIlot: View {
    var hauteur: CGFloat = 17
    var body: some View {
        Text("fn").font(.system(size: hauteur >= 20 ? 11 : 10.5, weight: .bold)).foregroundStyle(Color.white.opacity(0.78))
            .padding(.horizontal, hauteur >= 20 ? 5 : 4)
            .frame(minWidth: hauteur + 4, minHeight: hauteur)
            .overlay(RoundedRectangle(cornerRadius: hauteur >= 20 ? 5 : 4, style: .continuous).strokeBorder(Color.white.opacity(0.45), lineWidth: 1.2))
            .fixedSize()
            .accessibilityLabel("la touche fn")
    }
}

// MARK: - Presse-papiers

/// Les mesures de la carte Presse-papiers (maquette) : en-tête, cinq lignes de 40 pt, le pied « Rien ne quitte ce Mac · Tout effacer ».
@MainActor
enum PlanPressePapiers {
    static let haut: CGFloat = 14, entete: CGFloat = 26, ecart: CGFloat = 6, ligne: CGFloat = 40, vide: CGFloat = 44, pied: CGFloat = 34, bas: CGFloat = 10
    static func zone(_ g: GrilleIlot) -> CGRect { g.zoneCarte(.outilPressePapiers, haut: haut, bas: bas) }
    static func profondeur(_ m: IlotMoteur) -> CGFloat {
        haut + entete + ecart + (m.copies.isEmpty ? vide : ligne * CGFloat(m.copies.count)) + pied + bas
    }
    static func cadreLigne(_ i: Int, _ g: GrilleIlot) -> CGRect {
        let z = zone(g)
        return CGRect(x: z.minX, y: z.minY + entete + ecart + ligne * CGFloat(i), width: z.width, height: ligne)
    }
    /// Le milieu d'une ligne (sur son texte) et celui de « Coller » (au bout de la ligne) — essais : où cliquer.
    static func pointLigne(_ i: Int, _ m: IlotMoteur) -> CGPoint { let r = cadreLigne(i, m.grille); return CGPoint(x: r.minX + 120, y: r.midY) }
    static func pointColler(_ i: Int, _ m: IlotMoteur) -> CGPoint {
        let r = cadreLigne(i, m.grille), l = PiluleOutil.largeur("Coller", taille: 12, padding: 10)
        return CGPoint(x: r.maxX - 6 - l / 2, y: r.midY)
    }
    static func pointToutEffacer(_ m: IlotMoteur) -> CGPoint {
        let z = zone(m.grille), l = MesureIlot.texte("Tout effacer", 12.5, .medium)
        return CGPoint(x: z.maxX - 8 - l / 2, y: z.maxY - pied / 2 + 2)
    }
}

struct CartePressePapiers: View {
    @ObservedObject var m: IlotMoteur
    var g: GrilleIlot

    var body: some View {
        let v = VueIlot.outilPressePapiers
        let z = PlanPressePapiers.zone(g)
        ZStack(alignment: .topLeading) {
            FondCarteOutil(m: m, g: g, v: v)
            EnteteOutil(m: m, glyphe: "list.clipboard", titre: "Presse-papiers", sous: m.copies.isEmpty ? nil : (m.copies.count == 1 ? "le dernier" : "\(m.copies.count) derniers")) {
                ResteOuvert(m: m)
            }
            .posee(CGRect(x: z.minX, y: z.minY, width: z.width, height: PlanPressePapiers.entete), m.aspect(v, rang: 0), ancre: .topLeading)
            Group {
                if m.copies.isEmpty {
                    Text("Copie un texte, une image ou un fichier : il apparaîtra ici")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(CouleursIlot.encre3).lineLimit(1).minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)
                } else {
                    TimelineView(.periodic(from: Date(timeIntervalSinceReferenceDate: 0), by: 30)) { _ in
                        let t = m.maintenant()
                        VStack(spacing: 0) {
                            ForEach(m.copies) { c in LigneCopie(m: m, c: c, a: t).frame(height: PlanPressePapiers.ligne) }
                        }
                    }
                }
            }
            .posee(CGRect(x: z.minX, y: z.minY + PlanPressePapiers.entete + PlanPressePapiers.ecart, width: z.width,
                          height: m.copies.isEmpty ? PlanPressePapiers.vide : PlanPressePapiers.ligne * CGFloat(m.copies.count)), m.aspect(v, rang: 1), ancre: .top)
            pied.posee(CGRect(x: z.minX, y: z.maxY - PlanPressePapiers.pied, width: z.width, height: PlanPressePapiers.pied), m.aspect(v, rang: 2), ancre: .top)
        }
        .frame(width: IlotMoteur.largeur, height: IlotMoteur.hauteurMax, alignment: .topLeading)
    }

    private var pied: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1).padding(.top, 4).allowsHitTesting(false)
            HStack(spacing: 7) {
                Group {
                    Image(systemName: "lock.fill").font(.system(size: 10.5, weight: .semibold))
                    Text("Rien ne quitte ce Mac").font(.system(size: 12, weight: .medium))
                }
                .allowsHitTesting(false)
                Spacer(minLength: 0)
                if !m.copies.isEmpty {
                    Button { m.epinglerLeCentre(); m.surAction(.copiesEffacer) } label: {
                        Text("Tout effacer").font(.system(size: 12.5, weight: .medium)).foregroundStyle(Color.white.opacity(0.6))
                            .padding(.vertical, 6).contentShape(Rectangle())
                    }
                    .buttonStyle(AppuiIlot(echelle: 0.95))
                    .accessibilityLabel("Tout effacer : oublier les copies gardées par Voxile")
                }
            }
            .foregroundStyle(Color.white.opacity(0.4))
            .padding(.horizontal, 8)
            .frame(maxHeight: .infinity)
        }
    }
}

/// Une ligne du presse-papiers : l'icône (« Aa », « >_ », la miniature, l'icône du fichier), le texte, depuis quand ; « Coller » au
/// survol ; « Copié » (ou « Collé ») juste après un clic. Un clic sur la ligne recopie.
struct LigneCopie: View {
    @ObservedObject var m: IlotMoteur
    var c: CopieVue
    var a: Date

    var body: some View {
        let survol = m.survolCopie == c.id
        let faite = m.copieFaite?.id == c.id ? m.copieFaite?.mot : nil
        // la ligne entière recopie (un clic) ; « Coller » est un bouton posé PAR-DESSUS la ligne (un frère, jamais un bouton dans une vue
        // qui a son propre geste : sur le Mac, le clic n'y arrivait pas) ; le texte et l'icône ne prennent aucun clic
        ZStack(alignment: .trailing) {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(survol ? 0.1 : 0.001))
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .onTapGesture { m.epinglerLeCentre(); m.surAction(.copieRecopier(c.id)) }
            HStack(spacing: 10) {
                icone.frame(width: 40, height: 28).background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.08)))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                titre.frame(maxWidth: .infinity, alignment: .leading)
                Group {
                    if let faite {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                            Text(faite).font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(Color(hex: 0x5FE08A))
                        .padding(.leading, 7).padding(.trailing, 9).frame(height: 24)
                        .background(Capsule().fill(CouleursIlot.vert.opacity(0.18)))
                    } else if !survol {
                        Text(LecturePressePapiers.age(a.timeIntervalSince(c.element.date))).font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.42)).lineLimit(1).fixedSize()
                            .frame(minWidth: 42, alignment: .trailing).padding(.trailing, 4)
                    } else {
                        Color.clear.frame(width: PiluleOutil.largeur("Coller", taille: 12, padding: 10), height: 24)
                    }
                }
                .fixedSize()
            }
            .padding(.horizontal, 6)
            .allowsHitTesting(false)
            if survol, faite == nil {
                PiluleOutil(titre: "Coller", hauteur: 24, taille: 12, padding: 10, etiquette: "Coller dans l\u{2019}app d\u{2019}où tu viens") {
                    m.epinglerLeCentre(); m.surAction(.copieColler(c.id))
                }
                .padding(.trailing, 6)
            }
        }
        .frame(maxHeight: .infinity)
        .onHover { dedans in if dedans { m.survolCopie = c.id } else if m.survolCopie == c.id { m.survolCopie = nil } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(c.titre)\(c.detail.map { ", " + $0 } ?? "")")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Recopier") { m.surAction(.copieRecopier(c.id)) }
        .accessibilityAction(named: "Coller") { m.surAction(.copieColler(c.id)) }
    }

    @ViewBuilder private var icone: some View {
        switch c.element.genre {
        case .texte:
            if c.style == .commande {
                Text(">_").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(Color.white.opacity(0.6))
            } else {
                Text("Aa").font(.system(size: 12, weight: .bold)).foregroundStyle(Color.white.opacity(0.6))
            }
        case .image:
            if let i = c.icone {
                Color.clear.overlay(Image(nsImage: i).resizable().interpolation(.high).aspectRatio(contentMode: .fill)).clipped()
            } else {
                Image(systemName: "photo").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.white.opacity(0.6))
            }
        case .fichiers:
            if let i = c.icone {
                Image(nsImage: i).resizable().interpolation(.high).aspectRatio(contentMode: .fit).frame(width: 24, height: 24)
            } else {
                Image(systemName: "doc").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.white.opacity(0.6))
            }
        }
    }

    @ViewBuilder private var titre: some View {
        switch c.style {
        case .texte:
            Text(c.titre).font(.system(size: 15, design: .serif)).foregroundStyle(Color.white.opacity(0.82)).lineLimit(1).truncationMode(.tail)
        case .commande:
            Text(c.titre).font(.system(size: 12.5, weight: .regular, design: .monospaced)).foregroundStyle(Color.white.opacity(0.82)).lineLimit(1).truncationMode(.tail)
        case .nom:
            HStack(spacing: 6) {
                Text(c.titre).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1).truncationMode(.middle)
                if let d = c.detail { Text(d).font(.system(size: 12, weight: .medium)).foregroundStyle(Color.white.opacity(0.45)).lineLimit(1).fixedSize() }
            }
        }
    }
}

// MARK: - Reformuler

/// Les mesures de la carte Reformuler : en-tête (et le choix de la source), le texte de départ, les trois réécritures, le résultat.
@MainActor
enum PlanReformuler {
    static let haut: CGFloat = 14, entete: CGFloat = 26, ecart: CGFloat = 10, boutons: CGFloat = 30, bas: CGFloat = 14
    /// Le texte de départ : l'étiquette (15) puis une ou deux lignes de 20 pt (serif 15), 8 au-dessus, 9 dessous.
    static let policeSource: CGFloat = 15, ligneSource: CGFloat = 20
    /// Le résultat : serif 15,5 en lignes de 21 pt, trois au plus (la carte ne dépasse pas la hauteur du Centre), puis « Remplacer »,
    /// « Copier » (26 pt).
    static let policeResultat: CGFloat = 15.5, ligneResultat: CGFloat = 21, lignesResultat = 3, actions: CGFloat = 26
    static func zone(_ g: GrilleIlot) -> CGRect { g.zoneCarte(.outilReformuler, haut: haut, bas: bas) }

    static func serif(_ taille: CGFloat) -> NSFont {
        let base = NSFont.systemFont(ofSize: taille)
        return base.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: taille) } ?? base
    }
    /// Le nombre de lignes d'un texte à la largeur `l` (mesuré, Core Text), `max` au plus.
    static func lignes(_ t: String, police: NSFont, largeur l: CGFloat, max: Int) -> Int {
        let r = (t as NSString).boundingRect(with: CGSize(width: Swift.max(20, l), height: 4000), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: police])
        let h = police.ascender - police.descender + police.leading
        return Swift.min(max, Swift.max(1, Int((r.height / Swift.max(1, h)).rounded())))
    }
    /// La largeur du contenu (celle du Centre, les points en moins), sans passer par la grille (qui dépend de la hauteur de la carte).
    static func largeur(_ m: IlotMoteur) -> CGFloat {
        2 * (m.demiCamera + CGFloat(GeoIlot.valeurs(.outilReformuler, hauteurBarre: 0)[1])) - 2 * GrilleIlot.marge - GrilleIlot.placePoints
    }
    static func lignesSource(_ m: IlotMoteur) -> Int {
        let r = m.reformulation
        let max = r.phase == .attente ? 2 : 1
        return lignes(r.texte ?? texteVide(r.source), police: serif(policeSource), largeur: largeur(m) - 24, max: max)
    }
    static func texteVide(_ s: SourceReformulation) -> String {
        s == .derniereDictee ? "Aucune dictée pour l\u{2019}instant : dicte avec fn, elle apparaîtra ici." : "Choisis un texte dans n\u{2019}importe quelle app : il apparaîtra ici."
    }
    static func hauteurSource(_ m: IlotMoteur) -> CGFloat { 8 + 15 + 2 + CGFloat(lignesSource(m)) * ligneSource + 9 }
    static func lignesResultat(_ m: IlotMoteur) -> Int {
        guard let t = m.reformulation.resultat else { return 0 }
        return lignes(t, police: serif(policeResultat), largeur: largeur(m) - 24, max: lignesResultat)
    }
    static func hauteurResultat(_ m: IlotMoteur) -> CGFloat {
        switch m.reformulation.phase {
        case .attente: return 0
        case .calcul, .echec: return 42
        case .fait: return 10 + CGFloat(lignesResultat(m)) * ligneResultat + 9 + actions + 10
        }
    }
    static func profondeur(_ m: IlotMoteur) -> CGFloat {
        let r = hauteurResultat(m)
        return haut + entete + ecart + hauteurSource(m) + ecart + boutons + (r > 0 ? ecart + r : 0) + bas
    }
    static func cadreSource(_ m: IlotMoteur, _ g: GrilleIlot) -> CGRect {
        let z = zone(g)
        return CGRect(x: z.minX, y: z.minY + entete + ecart, width: z.width, height: hauteurSource(m))
    }
    static func cadreBoutons(_ m: IlotMoteur, _ g: GrilleIlot) -> CGRect {
        let s = cadreSource(m, g)
        return CGRect(x: s.minX, y: s.maxY + ecart, width: s.width, height: boutons)
    }
    static func cadreResultat(_ m: IlotMoteur, _ g: GrilleIlot) -> CGRect {
        let b = cadreBoutons(m, g)
        return CGRect(x: b.minX, y: b.maxY + ecart, width: b.width, height: hauteurResultat(m))
    }
    /// Essais : où cliquer. Les réécritures (« Plus pro »…), « Remplacer » et « Copier », la source (« Dernière dictée », « Texte choisi »).
    static func pointStyle(_ s: StyleReformulation, _ m: IlotMoteur) -> CGPoint {
        let b = cadreBoutons(m, m.grille)
        var x = b.minX
        for t in StyleReformulation.allCases {
            let l = PiluleOutil.largeur(t.titre, padding: 14)
            if t == s { return CGPoint(x: x + l / 2, y: b.midY) }
            x += l + 8
        }
        return .zero
    }
    static func pointAction(_ remplacer: Bool, _ m: IlotMoteur) -> CGPoint {
        let r = cadreResultat(m, m.grille)
        let lr = PiluleOutil.largeur("Remplacer", taille: 12.5, padding: 11), lc = PiluleOutil.largeur("Copier", taille: 12.5, padding: 11)
        let x = r.minX + 12 + (remplacer ? lr / 2 : lr + 8 + lc / 2)
        return CGPoint(x: x, y: r.maxY - 10 - actions / 2)
    }
    static let segments = ["Dernière dictée", "Texte choisi"]
    static func largeurSegment(_ t: String) -> CGFloat { MesureIlot.texte(t, 12, .semibold) + 20 }
    static func pointSource(_ s: SourceReformulation, _ m: IlotMoteur) -> CGPoint {
        let z = zone(m.grille)
        let l0 = largeurSegment(segments[0]), l1 = largeurSegment(segments[1])
        let droite = z.maxX - 2
        let x = s == .selection ? droite - l1 / 2 : droite - l1 - l0 / 2
        return CGPoint(x: x, y: z.minY + entete / 2)
    }
}

struct CarteReformuler: View {
    @ObservedObject var m: IlotMoteur
    var g: GrilleIlot

    var body: some View {
        let v = VueIlot.outilReformuler
        let z = PlanReformuler.zone(g)
        let r = m.reformulation
        ZStack(alignment: .topLeading) {
            FondCarteOutil(m: m, g: g, v: v)
            EnteteOutil(m: m, glyphe: "pencil.line", titre: "Reformuler") { segments }
                .posee(CGRect(x: z.minX, y: z.minY, width: z.width, height: PlanReformuler.entete), m.aspect(v, rang: 0), ancre: .topLeading)
            source.posee(PlanReformuler.cadreSource(m, g), m.aspect(v, rang: 1), ancre: .top)
            HStack(spacing: 8) {
                ForEach(StyleReformulation.allCases, id: \.self) { s in
                    PiluleOutil(titre: s.titre, style: r.style == s ? .blanc : .gris, hauteur: PlanReformuler.boutons, padding: 14,
                                etiquette: "Réécrire : \(s.titre.lowercased())") {
                        // jamais `.disabled` : un bouton éteint laisse passer le clic jusqu'à l'îlot, qui se rangeait ; ici il ne fait rien
                        m.epinglerLeCentre(); if r.texte != nil, r.phase != .calcul { m.surAction(.reformuler(s)) }
                    }
                    .opacity(r.texte == nil ? 0.4 : 1)
                }
                Spacer(minLength: 0)
            }
            .posee(PlanReformuler.cadreBoutons(m, g), m.aspect(v, rang: 2), ancre: .top)
            if r.phase != .attente {
                resultat.posee(PlanReformuler.cadreResultat(m, g), m.aspect(v, rang: 3), ancre: .top)
                    .transition(.opacity)
            }
        }
        .frame(width: IlotMoteur.largeur, height: IlotMoteur.hauteurMax, alignment: .topLeading)
        .animation(m.reduire || m.statique ? nil : .easeOut(duration: 0.2), value: r.phase)
    }

    /// « Dernière dictée » | « Texte choisi » (maquette : un sélecteur à deux segments).
    private var segments: some View {
        HStack(spacing: 0) {
            ForEach([SourceReformulation.derniereDictee, .selection], id: \.self) { s in
                let on = m.reformulation.source == s
                Button { m.epinglerLeCentre(); m.surAction(.reformulationSource(s)) } label: {
                    Text(s == .derniereDictee ? PlanReformuler.segments[0] : PlanReformuler.segments[1]).font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(on ? Color.white : Color.white.opacity(0.6)).lineLimit(1).fixedSize()
                        .padding(.horizontal, 10).frame(height: 22)
                        .background(Capsule().fill(Color.white.opacity(on ? 0.2 : 0)))
                        .contentShape(Capsule())
                }
                .buttonStyle(AppuiIlot(echelle: 0.95))
                .accessibilityLabel(s == .derniereDictee ? "Reformuler la dernière dictée" : "Reformuler le texte choisi dans l\u{2019}app")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.white.opacity(0.1)))
    }

    private var source: some View {
        let r = m.reformulation
        let n = PlanReformuler.lignesSource(m)
        return VStack(alignment: .leading, spacing: 2) {
            Text(r.etiquette).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Color.white.opacity(0.42)).lineLimit(1).frame(height: 15)
            Text(r.texte ?? PlanReformuler.texteVide(r.source)).font(.system(size: PlanReformuler.policeSource, design: .serif))
                .foregroundStyle(Color.white.opacity(r.texte == nil ? 0.4 : 0.72)).lineLimit(n).truncationMode(.tail)
                .frame(height: CGFloat(n) * PlanReformuler.ligneSource, alignment: .topLeading)
        }
        .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 9)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.07)))
        .allowsHitTesting(false)
    }

    @ViewBuilder private var resultat: some View {
        let r = m.reformulation
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.1))
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous)).onTapGesture {}
            switch r.phase {
            case .attente: EmptyView()
            case .calcul:
                HStack(spacing: 8) {
                    TroisPoints(anime: !(m.reduire || m.statique))
                    Text("Voxile réécrit\u{2026}").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.white.opacity(0.6))
                }
                .padding(.horizontal, 12).frame(maxHeight: .infinity)
                .allowsHitTesting(false)
            case .echec(let pourquoi):
                HStack(spacing: 7) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11, weight: .semibold))
                    Text(pourquoi).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                }
                .foregroundStyle(CouleursIlot.ambre)
                .padding(.horizontal, 12).frame(maxHeight: .infinity)
                .allowsHitTesting(false)
            case .fait(let t):
                let n = PlanReformuler.lignesResultat(m)
                VStack(alignment: .leading, spacing: 9) {
                    Text(t).font(.system(size: PlanReformuler.policeResultat, design: .serif)).foregroundStyle(.white)
                        .lineLimit(n).truncationMode(.tail)
                        .lineSpacing(max(0, PlanReformuler.ligneResultat - lignePolice(PlanReformuler.policeResultat)))
                        .frame(height: CGFloat(n) * PlanReformuler.ligneResultat, alignment: .topLeading)
                        .allowsHitTesting(false)
                        .accessibilityLabel(t)
                    HStack(spacing: 8) {
                        PiluleOutil(titre: "Remplacer", style: .blanc, hauteur: PlanReformuler.actions, taille: 12.5, padding: 11,
                                    etiquette: r.source == .selection ? "Remplacer le texte choisi" : "Remplacer la dernière dictée") {
                            m.epinglerLeCentre(); m.surAction(.reformulationRemplacer)
                        }
                        PiluleOutil(titre: r.remarque == "Copié" ? "Copié" : "Copier", icone: r.remarque == "Copié" ? "checkmark" : nil, hauteur: PlanReformuler.actions,
                                    taille: 12.5, padding: 11, etiquette: "Copier le texte réécrit") {
                            m.epinglerLeCentre(); m.surAction(.reformulationCopier)
                        }
                        Spacer(minLength: 6)
                        Text(r.remarque.flatMap { $0 == "Copié" ? nil : $0 } ?? ((r.style?.titre ?? "") + " \u{00B7} " + (r.source == .selection ? "remplace le texte choisi" : "remplace la dernière dictée")))
                            .font(.system(size: 11.5, weight: .medium)).foregroundStyle(Color.white.opacity(0.4)).lineLimit(1).truncationMode(.head)
                            .allowsHitTesting(false)
                    }
                    .frame(height: PlanReformuler.actions)
                }
                .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 10)
            }
        }
    }
    private func lignePolice(_ taille: CGFloat) -> CGFloat { let f = PlanReformuler.serif(taille); return f.ascender - f.descender + f.leading }
}

/// « Verbe réécrit… » : trois points qui battent (une horloge d'écran seulement pendant la réécriture ; figés dans un rendu).
struct TroisPoints: View {
    var anime: Bool
    var body: some View {
        if anime {
            TimelineView(.animation) { ctx in points(ctx.date.timeIntervalSinceReferenceDate) }
        } else { points(0) }
    }
    private func points(_ t: Double) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle().fill(Color.white.opacity(0.7)).frame(width: 6, height: 6)
                    .opacity(anime ? 0.45 + 0.55 * (0.5 + 0.5 * cos(2 * .pi * (t / 0.9 - Double(i) * 0.17))) : 0.7)
            }
        }
    }
}

// MARK: - Note rapide

/// Les mesures de la carte Note rapide : en-tête, la zone « Dicter une note », l'étiquette « Notes », la liste (lignes de 32 pt, quatre
/// visibles au plus : au-delà, elle défile).
@MainActor
enum PlanNote {
    static let haut: CGFloat = 14, entete: CGFloat = 26, ecart: CGFloat = 10, zoneDictee: CGFloat = 64, etiquette: CGFloat = 16, ecartListe: CGFloat = 4
    static let ligne: CGFloat = 32, lignesMax = 4, bas: CGFloat = 12
    static var listeMax: CGFloat { ligne * CGFloat(lignesMax) }
    static func zone(_ g: GrilleIlot) -> CGRect { g.zoneCarte(.outilNote, haut: haut, bas: bas) }
    static func hauteurListe(_ m: IlotMoteur) -> CGFloat { ligne * CGFloat(max(1, m.notes.count) + (m.suggestionVisible ? 1 : 0)) }
    /// La rangée d'une note dans la liste : la suggestion « En faire un rappel » prend la rangée sous la première note.
    static func rang(_ i: Int, _ m: IlotMoteur) -> Int { i == 0 || !m.suggestionVisible ? i : i + 1 }
    /// Essais : « En faire un rappel » sous la première note.
    static func pointSuggestion(_ m: IlotMoteur) -> CGPoint {
        let l = cadreListe(m, m.grille)
        return CGPoint(x: l.minX + 46 + LigneSuggestion.largeurPilule(m) / 2, y: l.minY + ligne * 1.5 - m.defilementNotes)
    }
    /// Essais : le bouton « Dicter une note » (toute la zone), puis « Terminé » pendant l'écoute.
    static func pointDicter(_ m: IlotMoteur) -> CGPoint { let c = cadreZone(m.grille); return CGPoint(x: c.midX, y: c.midY) }
    static func pointTermine(_ m: IlotMoteur) -> CGPoint {
        let c = cadreZone(m.grille)
        return CGPoint(x: c.maxX - 14 - PiluleOutil.largeur("Terminé", icone: "checkmark", taille: 13, padding: 14) / 2, y: c.midY)
    }
    static func profondeur(_ m: IlotMoteur) -> CGFloat {
        haut + entete + ecart + zoneDictee + ecart + etiquette + ecartListe + min(listeMax, hauteurListe(m)) + bas
    }
    static func depassement(_ m: IlotMoteur) -> CGFloat { max(0, hauteurListe(m) - listeMax) }
    static func cadreZone(_ g: GrilleIlot) -> CGRect { let z = zone(g); return CGRect(x: z.minX, y: z.minY + entete + ecart, width: z.width, height: zoneDictee) }
    static func cadreListe(_ m: IlotMoteur, _ g: GrilleIlot) -> CGRect {
        let c = cadreZone(g)
        return CGRect(x: c.minX, y: c.maxY + ecart + etiquette + ecartListe, width: c.width, height: min(listeMax, hauteurListe(m)))
    }
    /// Essais : « Vers Notes » et « × » d'une note (au survol), défilement compris.
    static func pointVersNotes(_ i: Int, _ m: IlotMoteur) -> CGPoint {
        let l = cadreListe(m, m.grille)
        // le « × » n'est là qu'au survol de la ligne
        let croix = i < m.notes.count && m.survolNote == m.notes[i].id
        let lx: CGFloat = croix ? 20 + 2 + 4 : 0, lv = PiluleOutil.largeur("Vers Notes", icone: "arrow.up.forward", taille: 12, padding: 10)
        return CGPoint(x: l.maxX - 4 - lx - lv / 2, y: l.minY + ligne * (CGFloat(rang(i, m)) + 0.5) - m.defilementNotes)
    }
    static func pointSupprimer(_ i: Int, _ m: IlotMoteur) -> CGPoint {
        let l = cadreListe(m, m.grille)
        return CGPoint(x: l.maxX - 4 - 10, y: l.minY + ligne * (CGFloat(rang(i, m)) + 0.5) - m.defilementNotes)
    }
}

struct CarteNote: View {
    @ObservedObject var m: IlotMoteur
    var g: GrilleIlot

    var body: some View {
        let v = VueIlot.outilNote
        let z = PlanNote.zone(g)
        let liste = PlanNote.cadreListe(m, g)
        let total = PlanNote.hauteurListe(m), decale = m.defilementNotes
        ZStack(alignment: .topLeading) {
            FondCarteOutil(m: m, g: g, v: v)
            EnteteOutil(m: m, glyphe: "note.text", titre: "Note rapide") { ResteOuvert(m: m) }
                .posee(CGRect(x: z.minX, y: z.minY, width: z.width, height: PlanNote.entete), m.aspect(v, rang: 0), ancre: .topLeading)
            zoneDictee.posee(PlanNote.cadreZone(g), m.aspect(v, rang: 1), ancre: .top)
            HStack {
                Text("Notes").font(.system(size: 11.5, weight: .semibold))
                Spacer()
                Text(m.notes.isEmpty ? "gardées sur ce Mac" : "\(m.notes.count) \u{00B7} gardées sur ce Mac").font(.system(size: 11.5, weight: .medium))
            }
            .foregroundStyle(Color.white.opacity(0.42))
            .padding(.horizontal, 8)
            .allowsHitTesting(false)
            .posee(CGRect(x: z.minX, y: PlanNote.cadreZone(g).maxY + PlanNote.ecart, width: z.width, height: PlanNote.etiquette), m.aspect(v, rang: 2), ancre: .top)
            TimelineView(.periodic(from: Date(timeIntervalSinceReferenceDate: 0), by: 60)) { _ in
                let t = m.maintenant()
                VStack(spacing: 0) {
                    if m.notes.isEmpty {
                        Text("Aucune note pour l\u{2019}instant").font(.system(size: 13, weight: .medium)).foregroundStyle(CouleursIlot.encre3)
                            .frame(maxWidth: .infinity, minHeight: PlanNote.ligne)
                            .allowsHitTesting(false)
                    }
                    ForEach(m.notes) { n in
                        LigneNote(m: m, n: n, a: t).frame(height: PlanNote.ligne)
                        if n.id == m.notes.first?.id, m.suggestionVisible { LigneSuggestion(m: m, a: t).frame(height: PlanNote.ligne) }
                    }
                }
                .frame(width: liste.width, alignment: .topLeading)
                .offset(y: -decale)
            }
            .frame(width: liste.width, height: liste.height, alignment: .topLeading)
            // « Aucune note » (qui ne prend aucun clic) ne range pas l'îlot
            .background { Color.clear.contentShape(Rectangle()).onTapGesture {} }
            .clipped()
            // ni `.clipped()` ni `.mask` ne bornent les clics : sans cette forme, les lignes remontées hors de la liste couvraient
            // l'en-tête (« ‹ Outils » ne répondait plus au-delà de huit notes défilées)
            .contentShape(Rectangle())
            .mask(FonduNotes(haut: decale > 0.5, bas: total - decale > liste.height + 0.5))
            .posee(liste, m.aspect(v, rang: 3), ancre: .top)
        }
        .frame(width: IlotMoteur.largeur, height: IlotMoteur.hauteurMax, alignment: .topLeading)
    }

    /// « Dicter une note » : un grand bouton (un clic, l'écoute commence) ; pendant l'écoute, le niveau, le texte en direct et
    /// « Terminé » (un silence de 2 s arrête aussi) ; puis « J'écris la note… ». fn reste possible, carte ouverte.
    private var zoneDictee: some View { ZoneDicteeNote(m: m, ecoute: m.ecouteNote) }
}

struct ZoneDicteeNote: View {
    @ObservedObject var m: IlotMoteur
    @ObservedObject var ecoute: EcouteNote
    @State private var survol = false
    private static let forme = RoundedRectangle(cornerRadius: 20, style: .continuous)

    var body: some View {
        switch ecoute.phase {
        case .repos: bouton
        case .ecoute, .ecriture: enCours
        }
    }

    private var bouton: some View {
        Button { m.epinglerLeCentre(); m.surAction(.noteDicter) } label: {
            HStack(spacing: 12) {
                Image(systemName: "mic.fill").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 42, height: 42).background(Circle().fill(CouleursIlot.rouge.opacity(survol ? 1 : 0.88)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dicter une note").font(.system(size: 14.5, weight: .bold)).foregroundStyle(.white)
                    Text(ecoute.message ?? "Clique et parle, je m\u{2019}arrête quand tu te tais").font(.system(size: 12, weight: .medium))
                        .foregroundStyle(ecoute.message != nil ? Color(hex: 0xFFB340) : Color.white.opacity(0.5))
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.leading, 12).padding(.trailing, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Self.forme.fill(Color.white.opacity(survol ? 0.14 : 0.09)))
            .contentShape(Self.forme)
        }
        .buttonStyle(AppuiIlot(echelle: 0.98))
        .onHover { survol = $0 }
        .accessibilityLabel("Dicter une note")
        .accessibilityHint("Un clic, puis parle : la note s\u{2019}écrit quand tu te tais ou quand tu cliques Terminé")
    }

    /// Pendant l'écoute : le rond rouge respire avec la voix, « J'écoute… », le texte en direct (la fin, si c'est long), « Terminé ».
    private var enCours: some View {
        let ecrit = ecoute.phase == .ecriture
        let n = CGFloat(min(1, max(0, ecoute.niveau)))
        return ZStack(alignment: .trailing) {
            // le fond prend les clics (l'îlot ne se range pas) ; le texte n'en prend aucun ; « Terminé » est posé à côté, en frère
            Self.forme.fill(Color.white.opacity(0.09)).contentShape(Self.forme).onTapGesture {}
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(CouleursIlot.rouge.opacity(ecrit ? 0 : 0.28)).scaleEffect(1 + 0.42 * n)
                    Circle().fill(ecrit ? Color.white.opacity(0.14) : CouleursIlot.rouge)
                    if ecrit { RouetIlot(anime: !m.reduire && !m.statique).frame(width: 20, height: 20) }
                    else { Image(systemName: "mic.fill").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white) }
                }
                .frame(width: 42, height: 42)
                .animation(m.statique || m.reduire ? nil : .easeOut(duration: 0.12), value: n)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ecrit ? "J\u{2019}écris la note\u{2026}" : "J\u{2019}écoute\u{2026}").font(.system(size: 14.5, weight: .bold)).foregroundStyle(.white)
                    Text(ecoute.texte.isEmpty ? (ecrit ? "Un instant" : "Parle, je m\u{2019}arrête après 2 s de silence") : ecoute.texte)
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Color.white.opacity(ecoute.texte.isEmpty ? 0.5 : 0.85))
                        .truncationMode(.head)
                }
                .lineLimit(1)
                Spacer(minLength: ecrit ? 0 : PiluleOutil.largeur("Terminé", icone: "checkmark", taille: 13, padding: 14) + 10)
            }
            .padding(.leading, 12).padding(.trailing, 14)
            .allowsHitTesting(false)
            if !ecrit {
                PiluleOutil(titre: "Terminé", icone: "checkmark", style: .blanc, hauteur: 30, taille: 13, padding: 14, etiquette: "Terminé : écrire la note") {
                    m.surAction(.noteTerminer)
                }
                .padding(.trailing, 14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(ecrit ? "J\u{2019}écris la note" : "J\u{2019}écoute")
        .accessibilityValue(ecoute.texte)
    }
}

/// Sous la note qui vient d'arriver, quand elle dit un jour ou une heure : « En faire un rappel · demain 13:00 » (un clic).
struct LigneSuggestion: View {
    @ObservedObject var m: IlotMoteur
    var a: Date

    static func libelle(_ m: IlotMoteur) -> String {
        guard let s = m.suggestionRappel else { return "En faire un rappel" }
        return "En faire un rappel \u{00B7} " + ListeRappels.jour(de: s.quand, maintenant: m.maintenant()) + " " + FormatIlot.heure(s.quand)
    }
    static func largeurPilule(_ m: IlotMoteur) -> CGFloat { PiluleOutil.largeur(libelle(m), icone: "bell.fill", taille: 12, padding: 10) }

    var body: some View {
        ZStack(alignment: .leading) {
            Color.clear.contentShape(Rectangle()).onTapGesture {}
            HStack(spacing: 6) {
                Image(systemName: "arrow.turn.down.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.white.opacity(0.35))
                    .frame(width: 32, alignment: .trailing)
                    .allowsHitTesting(false)
                if let s = m.suggestionRappel {
                    PiluleOutil(titre: Self.libelle(m), icone: "bell.fill", style: .ambreDoux, hauteur: 24, taille: 12, padding: 10,
                                etiquette: "Faire de cette note un rappel : " + s.texte + ", " + Self.libelle(m)) {
                        m.epinglerLeCentre(); m.surAction(.noteEnRappel(s.note))
                    }
                }
            }
            .padding(.leading, 8)
        }
    }
}

private struct FonduNotes: View {
    var haut: Bool
    var bas: Bool
    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [haut ? .clear : .black, .black], startPoint: .top, endPoint: .bottom).frame(height: 18)
            Color.black
            LinearGradient(colors: [.black, bas ? .clear : .black], startPoint: .top, endPoint: .bottom).frame(height: 18)
        }
    }
}

/// Une note : l'heure, le texte ; au survol (et pour la note qui vient d'arriver) « Vers Notes » et « × » ; envoyée : « Dans Notes ».
struct LigneNote: View {
    @ObservedObject var m: IlotMoteur
    var n: NoteRapide
    var a: Date

    var body: some View {
        let survol = m.survolNote == n.id, neuve = m.noteNeuve == n.id
        let envoi = m.envoisNotes[n.id]
        ZStack {
        // le fond de la ligne prend les clics (pour que l'îlot ne se range pas) ; l'heure et le texte n'en prennent aucun ; les boutons
        // sont des frères posés dessus, jamais dans une vue qui a son propre geste
        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(survol ? 0.1 : (neuve ? 0.08 : 0.001)))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .onTapGesture {}
        HStack(spacing: 8) {
            Group {
                Text(ListeNotes.quand(n.date, maintenant: a)).font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.42)).lineLimit(1).frame(width: 38, alignment: .leading)
                Text(n.texte).font(.system(size: 15, design: .serif)).foregroundStyle(Color.white.opacity(survol || neuve ? 1 : 0.78))
                    .lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
            }
            .allowsHitTesting(false)
            HStack(spacing: 4) {
                if envoi == .fait || (n.versNotes && envoi == nil && (survol || neuve)) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                        Text("Dans Notes").font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Color(hex: 0x5FE08A))
                    .padding(.leading, 7).padding(.trailing, 9).frame(height: 24)
                    .background(Capsule().fill(CouleursIlot.vert.opacity(0.18)))
                    .allowsHitTesting(false)
                } else if envoi == .refuse {
                    Text("Notes refuse").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color(hex: 0xFFB340))
                        .padding(.horizontal, 9).frame(height: 24).background(Capsule().fill(CouleursIlot.ambre.opacity(0.18)))
                        .allowsHitTesting(false)
                        .accessibilityLabel("L\u{2019}app Notes a refusé : autorise Voxile dans Réglages Système, Confidentialité, Automatisation")
                } else if envoi == .echec {
                    // Notes n'a pas répondu (trop lent, fermé…) sans refuser : on peut réessayer
                    PiluleOutil(titre: "Réessayer", icone: "arrow.clockwise", hauteur: 24, taille: 12, padding: 10, etiquette: "Notes n\u{2019}a pas répondu : réessayer") {
                        m.epinglerLeCentre(); m.surAction(.noteVersNotes(n.id))
                    }
                } else if envoi == .enCours {
                    Text("Envoi\u{2026}").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.white.opacity(0.6)).padding(.horizontal, 9)
                        .allowsHitTesting(false)
                } else if survol || neuve {
                    PiluleOutil(titre: "Vers Notes", icone: "arrow.up.forward", hauteur: 24, taille: 12, padding: 10, etiquette: "Envoyer cette note dans l\u{2019}app Notes") {
                        m.epinglerLeCentre(); m.surAction(.noteVersNotes(n.id))
                    }
                } else if n.versNotes {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Color(hex: 0x5FE08A).opacity(0.8))
                        .allowsHitTesting(false)
                        .accessibilityLabel("Déjà dans Notes")
                }
                if survol {
                    Button { m.epinglerLeCentre(); m.surAction(.noteSupprimer(n.id)) } label: {
                        Image(systemName: "xmark").font(.system(size: 9.5, weight: .bold)).foregroundStyle(Color.white.opacity(0.75))
                            .frame(width: 20, height: 20).background(Circle().fill(Color.white.opacity(0.14))).contentShape(Circle())
                    }
                    .buttonStyle(AppuiIlot(echelle: 0.88))
                    .padding(.leading, 2)
                    .accessibilityLabel("Supprimer cette note")
                }
            }
            .fixedSize()
        }
        .padding(.leading, 8).padding(.trailing, 4)
        }
        .frame(maxHeight: .infinity)
        .onHover { dedans in if dedans { m.survolNote = n.id } else if m.survolNote == n.id { m.survolNote = nil } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Note de \(ListeNotes.quand(n.date, maintenant: a)) : \(n.texte)")
    }
}
