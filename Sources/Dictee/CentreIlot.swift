import AppKit
import SwiftUI
import DicteeCore

// Le Centre de l'îlot (maquette design/maquettes/ilot-centre.html, validée par Hugues : « une sorte de mini-agent, multitâche ») : tout ce qui
// se règle depuis l'îlot, à la souris, sans raccourci (seule la touche fn reste, pour dicter).
// - une rangée de gros boutons ronds, chacun avec son nom et son état dessous : Micro, Dictée (Mac / AirPods), Téléchargements, Claude Code ;
// - deux grandes cases : Minuteur (5 · 10 · 25 min, ou le temps qui reste, pause, arrêt) et Étagère (on y lâche un fichier, on l'en reprend) ;
// - on y arrive sans rien deviner : bouton « Centre » au pied de la lecture, points de page à droite des cartes, défilement (un geste = une
//   carte) ; l'îlot vide s'ouvre directement dessus ;
// - un clic sur un bouton épingle l'îlot (« Reste ouvert ») : on enchaîne plusieurs réglages ; il se range au clic ailleurs ou sur la forme.
// La pile des cartes et le défilement sont dans DicteeCore/CentreIlot.swift ; la navigation dans IlotMoteur.swift.

extension GrilleIlot {
    /// La place des points de page au bord droit des cartes (lecture, Centre, accueil) : le contenu s'arrête 12 pt plus tôt (maquette :
    /// contenu jusqu'à 28 pt du bord, points de 7 à 23 pt du bord).
    static let placePoints: CGFloat = 12
    /// La zone du contenu d'une carte : celle de l'écran, moins la place des points à droite.
    func zoneCarte(_ v: VueIlot, haut: CGFloat = 16, bas: CGFloat = 16) -> CGRect {
        var z = zone(v, haut: haut, bas: bas)
        z.size.width -= Self.placePoints
        return z
    }
}

// MARK: - le Centre

/// Les mesures du Centre (maquette, en points) : elles servent au dessin et aux essais (où cliquer).
enum PlanCentre {
    static let haut: CGFloat = 14, entete: CGFloat = 26, ronds: CGFloat = 96, cases: CGFloat = 76
    static let ecartRonds: CGFloat = 12, ecartCases: CGFloat = 10
    static let rond: CGFloat = 52
    /// Le nom sous un rond : 11,5 pt semi-gras, serré (maquette) ; sur deux lignes s'il ne tient pas dans sa colonne.
    static let policeNom: CGFloat = 11.5, interlettreNom: CGFloat = -0.25
    /// Où sont les éléments, depuis le centre de l'encoche (x) et le haut de l'écran (y).
    static func zone(_ g: GrilleIlot) -> CGRect { g.zoneCarte(.centre, haut: haut, bas: haut) }
    static func cadreEntete(_ g: GrilleIlot) -> CGRect { let z = zone(g); return CGRect(x: z.minX, y: z.minY, width: z.width, height: entete) }
    static func cadreRonds(_ g: GrilleIlot) -> CGRect { let z = zone(g); return CGRect(x: z.minX, y: z.minY + entete + ecartRonds, width: z.width, height: ronds) }
    static func cadreCases(_ g: GrilleIlot) -> CGRect {
        let z = zone(g); return CGRect(x: z.minX, y: z.minY + entete + ecartRonds + ronds + ecartCases, width: z.width, height: cases)
    }
    static func cadreCase(_ g: GrilleIlot, droite: Bool) -> CGRect {
        let c = cadreCases(g), l = (c.width - ecartCases) / 2
        return CGRect(x: droite ? c.minX + l + ecartCases : c.minX, y: c.minY, width: l, height: c.height)
    }
    /// Le centre du rond n°`i` sur `n` (colonnes de même largeur).
    static func centreRond(_ g: GrilleIlot, _ i: Int, sur n: Int) -> CGPoint {
        let r = cadreRonds(g), l = r.width / CGFloat(max(1, n))
        return CGPoint(x: r.minX + l * (CGFloat(i) + 0.5), y: r.minY + rond / 2)
    }
}

/// Les boutons ronds du Centre, dans l'ordre (la Dictée n'existe qu'avec un micro Bluetooth branché).
enum BoutonCentre: CaseIterable { case micro, dictee, telechargements, claude }

extension IlotMoteur {
    var boutonsCentre: [BoutonCentre] { BoutonCentre.allCases.filter { $0 != .dictee || choixMicro != nil } }
    /// Le nom de la première carte, pour le bouton de retour du Centre (« ‹ Vidéo »).
    var nomPremiereCarte: String? {
        guard let p = cartes.first, p != .centre else { return nil }
        switch p {
        case .lectureEtendu, .lectureMinuteur: return lecture.genre == .musique ? "Musique" : "Vidéo"
        case .minuteurEtendu: return "Minuteur"
        case .microEtendu: return "Micro"
        case .claudeEtendu: return "Claude"
        case .agendaEtendu: return "Rendez-vous"
        case .rappelEtendu, .rappelListe: return "Rappel"
        default: return nil
        }
    }
}

struct CentreVue: View {
    @ObservedObject var m: IlotMoteur
    var g: GrilleIlot

    var body: some View {
        let v = VueIlot.centre
        ZStack(alignment: .topLeading) {
            entete.posee(PlanCentre.cadreEntete(g), m.aspect(v, rang: 0), ancre: .topLeading)
            ronds.posee(PlanCentre.cadreRonds(g), m.aspect(v, rang: 1), ancre: .top)
            CaseMinuteur(m: m).posee(PlanCentre.cadreCase(g, droite: false), m.aspect(v, rang: 2), ancre: .top)
            CaseEtagere(m: m).posee(PlanCentre.cadreCase(g, droite: true), m.aspect(v, rang: 3), ancre: .top)
        }
    }

    /// « ‹ Vidéo » (retour à la première carte), « Reste ouvert » quand l'îlot est épinglé, « Modifier ».
    private var entete: some View {
        HStack(spacing: 8) {
            if let nom = m.nomPremiereCarte, let premiere = m.cartes.first {
                PiluleCentre(titre: nom, retour: true, etiquette: "Revenir à : \(nom)") { m.allerA(premiere) }
            } else {
                Text("Centre").font(.system(size: 13.5, weight: .semibold)).foregroundStyle(CouleursIlot.encre2).padding(.leading, 2)
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Image(systemName: "pin.fill").font(.system(size: 10, weight: .semibold))
                Text("Reste ouvert").font(.system(size: 11.5, weight: .semibold))
            }
            .foregroundStyle(Color.white.opacity(0.5))
            .opacity(m.epingle ? 1 : 0)
            .animation(m.reduire || m.statique ? nil : .easeOut(duration: 0.25), value: m.epingle)
            .accessibilityHidden(!m.epingle)
            // « Modifier » (ajouter, retirer, ranger les boutons) : le geste arrive au prochain lot ; le bouton est déjà à sa place
            PiluleCentre(titre: "Modifier", etiquette: "Modifier le Centre") { m.epinglerLeCentre(); m.surModifierCentre() }
        }
        .frame(height: PlanCentre.entete)
    }

    private var ronds: some View {
        let bs = m.boutonsCentre
        let l = PlanCentre.cadreRonds(g).width / CGFloat(bs.count)
        return HStack(spacing: 0) {
            ForEach(bs, id: \.self) { b in bouton(b, colonne: l).frame(width: l, height: PlanCentre.ronds, alignment: .top) }
        }
    }

    /// Un clic sur un bouton : l'îlot reste ouvert, puis l'action (celles de l'îlot, déjà construites).
    private func agir(_ a: ActionIlot) { m.epinglerLeCentre(); m.surAction(a) }

    @ViewBuilder private func bouton(_ b: BoutonCentre, colonne l: CGFloat) -> some View {
        switch b {
        case .micro:
            let coupe = m.microCoupe
            TuileRonde(nom: "Micro", etat: coupe ? "Coupé" : "Ouvert", couleurEtat: coupe ? Color(hex: 0xFF6961) : CouleursIlot.encre2,
                       fond: coupe ? CouleursIlot.rouge : nil, colonne: l, reduire: m.reduire || m.statique,
                       etiquette: coupe ? "Micro coupé : le rouvrir" : "Micro ouvert : le couper") {
                Image(systemName: coupe ? "mic.slash.fill" : "mic.fill").font(.system(size: 21, weight: .semibold)).foregroundStyle(.white)
            } action: { agir(.centreMicro) }
        case .dictee:
            let airpods = m.choixMicro?.airpods ?? false
            TuileRonde(nom: "Dictée", etat: airpods ? "AirPods" : "Mac", couleurEtat: CouleursIlot.encre2, fond: nil, colonne: l,
                       reduire: m.reduire || m.statique,
                       etiquette: airpods ? "La dictée écoute les AirPods : passer au micro du Mac" : "La dictée écoute le micro du Mac : passer aux AirPods") {
                Image(systemName: airpods ? "airpodspro" : "laptopcomputer").font(.system(size: airpods ? 22 : 20, weight: .semibold)).foregroundStyle(.white)
            } action: { agir(.microChoisir(airpods: !airpods)) }
        case .telechargements:
            let on = m.telechargementsActifs
            TuileRonde(nom: "Téléchargements", etat: on ? "Allumé" : "Éteint", couleurEtat: on ? Color(hex: 0x5EB0FF) : CouleursIlot.encre2,
                       fond: on ? CouleursIlot.bleu : nil, colonne: l, reduire: m.reduire || m.statique,
                       etiquette: on ? "Téléchargements allumé : l'éteindre" : "Téléchargements éteint : l'allumer") {
                Image(systemName: "arrow.down.circle").font(.system(size: 22, weight: .semibold)).foregroundStyle(.white)
            } action: { agir(.centreTelechargements) }
        case .claude:
            let s = m.claude
            let branche = m.claudeBranche || s != nil
            let etat = s.map { m.texteClaude($0, taille: PlanCentre.policeNom).isEmpty ? "Au travail" : m.texteClaude($0, taille: PlanCentre.policeNom) } ?? (branche ? "Prêt" : "Brancher")
            TuileRonde(nom: "Claude Code", etat: etat, couleurEtat: branche ? CouleursIlot.encre2 : Color(hex: 0x5EB0FF),
                       fond: branche ? CouleursIlot.corail : nil, pointille: !branche, colonne: l, reduire: m.reduire || m.statique,
                       etiquette: s != nil ? "Claude Code, \(etat) : ouvrir" : (branche ? "Claude Code prêt" : "Brancher Claude Code")) {
                EtoileClaude(couleur: branche ? .white : Color.white.opacity(0.75)).frame(width: 21, height: 21)
            } action: { agir(.centreClaude) }
        }
    }
}

/// Un gros bouton rond du Centre (comme le Centre de contrôle de l'iPhone) : le rond de 52 pt, son nom, son état dessous. Le rond prend
/// la couleur de l'état (rouge coupé, bleu allumé, corail Claude) ; « Brancher » : un rond en pointillé.
struct TuileRonde<Glyphe: View>: View {
    var nom: String
    var etat: String
    var couleurEtat: Color
    var fond: Color?
    var pointille = false
    var colonne: CGFloat
    var reduire: Bool
    var etiquette: String
    @ViewBuilder var glyphe: () -> Glyphe
    var action: () -> Void
    @State private var survol = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                ZStack {
                    if pointille {
                        Circle().strokeBorder(Color.white.opacity(survol ? 0.6 : 0.4), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3.2]))
                    } else {
                        Circle().fill(fond ?? Color.white.opacity(0.14)).brightness(survol ? 0.08 : 0)
                    }
                    glyphe()
                }
                .frame(width: PlanCentre.rond, height: PlanCentre.rond)
                .keyframeAnimator(initialValue: 1.0, trigger: etat) { v, s in v.scaleEffect(reduire ? 1 : s) } keyframes: { _ in
                    KeyframeTrack { LinearKeyframe(0.86, duration: 0.09); SpringKeyframe(1.04, duration: 0.14); SpringKeyframe(1, duration: 0.2, spring: Spring(response: 0.3, dampingRatio: 0.7)) }
                }
                // le nom, mesuré : sur deux lignes (jamais tassé contre son voisin) s'il ne tient pas dans sa colonne
                Text(nom).font(.system(size: PlanCentre.policeNom, weight: .semibold)).tracking(PlanCentre.interlettreNom)
                    .foregroundStyle(.white).multilineTextAlignment(.center).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    .frame(width: max(10, colonne - 8))
                    .padding(.top, 7)
                Text(etat).font(.system(size: PlanCentre.policeNom, weight: .medium)).foregroundStyle(couleurEtat).lineLimit(1)
                    .contentTransition(.opacity)
                    .padding(.top, 1)
            }
            .frame(width: colonne)
            .contentShape(Rectangle())
        }
        .buttonStyle(AppuiIlot(echelle: 0.94))
        .onHover { survol = $0 }
        .animation(.easeOut(duration: 0.15), value: survol)
        .accessibilityLabel(etiquette)
        .accessibilityValue(etat)
    }
}

/// Les pilules de l'en-tête : « ‹ Vidéo », « Modifier » (26 pt, maquette).
struct PiluleCentre: View {
    var titre: String
    var retour = false
    var etiquette: String
    var action: () -> Void
    @State private var survol = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if retour { Image(systemName: "chevron.left").font(.system(size: 10.5, weight: .bold)) }
                Text(titre).font(.system(size: 12.5, weight: .semibold)).lineLimit(1).fixedSize()
            }
            .foregroundStyle(.white)
            .padding(.leading, retour ? 8 : 11).padding(.trailing, 11)
            .frame(height: 26)
            .background(Capsule().fill(Color.white.opacity(survol ? 0.2 : 0.12)))
            .contentShape(Capsule())
        }
        .buttonStyle(AppuiIlot(echelle: 0.92))
        .onHover { survol = $0 }
        .animation(.easeOut(duration: 0.12), value: survol)
        .accessibilityLabel(etiquette)
    }
}

/// Le fond d'une grande case du Centre (20 pt de rayon) ; un clic dans son vide ne referme pas l'îlot (on visait la case).
private struct FondCase: View {
    var plein: Bool
    var pointille = false
    var eclaire = false
    var body: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(eclaire ? CouleursIlot.bleu.opacity(0.22) : Color.white.opacity(plein ? 0.1 : 0))
            .overlay {
                if pointille || eclaire {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(eclaire ? 0.9 : 0.3), style: StrokeStyle(lineWidth: 1.5, dash: eclaire ? [] : [5, 4]))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .onTapGesture {}
    }
}

/// La case Minuteur : 5 · 10 · 25 min ; un minuteur qui tourne montre son temps, pause (ou reprise) et arrêt.
struct CaseMinuteur: View {
    @ObservedObject var m: IlotMoteur

    var body: some View {
        let mn = m.minuteur
        ZStack(alignment: .topLeading) {
            FondCase(plein: true)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    GlypheIlot(nom: "timer", couleur: CouleursIlot.ambre, taille: 15).frame(width: 18, height: 17)
                    Text("Minuteur").font(.system(size: 13.5, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    Spacer(minLength: 4)
                    if let mn {
                        TimelineView(.periodic(from: mn.echeance ?? Date(timeIntervalSinceReferenceDate: 0), by: 1)) { _ in
                            Text(FormatIlot.duree(mn.restant(a: m.maintenant()))).font(.system(size: 13.5, weight: .semibold).monospacedDigit())
                                .foregroundStyle(CouleursIlot.ambre).lineLimit(1).fixedSize()
                                .accessibilityLabel("Temps restant").accessibilityValue(FormatIlot.duree(mn.restant(a: m.maintenant())))
                        }
                    }
                }
                .frame(height: 17)
                if let mn {
                    HStack(spacing: 8) {
                        BoutonRondIlot(symbole: mn.enPause ? "play.fill" : "pause.fill", couleur: CouleursIlot.ambre, fond: CouleursIlot.ambre.opacity(0.22),
                                       etiquette: mn.enPause ? "Reprendre le minuteur" : "Mettre le minuteur en pause", cote: 28) { agir(.minuteurBasculer) }
                        BoutonRondIlot(symbole: "xmark", couleur: .white, fond: Color.white.opacity(0.14), etiquette: "Arrêter le minuteur", cote: 28) { agir(.minuteurArreter) }
                        Text(mn.enPause ? "En pause" : "fin à " + FormatIlot.heure(mn.heureDeFin(a: m.maintenant())))
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(Color.white.opacity(0.5)).lineLimit(1)
                    }
                    .frame(height: 28)
                } else {
                    HStack(spacing: 6) {
                        ForEach([5, 10, 25], id: \.self) { n in CapMinutes(minutes: n) { agir(.minuteurLancerDansLeCentre(minutes: Double(n))) } }
                        Text("min").font(.system(size: 12, weight: .medium)).foregroundStyle(Color.white.opacity(0.5)).padding(.leading, 3)
                    }
                    .frame(height: 28)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
        }
    }
    private func agir(_ a: ActionIlot) { m.epinglerLeCentre(); m.surAction(a) }
}

/// « 5 », « 10 », « 25 » : 44 × 28 pt (maquette).
struct CapMinutes: View {
    var minutes: Int
    var action: () -> Void
    @State private var survol = false
    static let largeur: CGFloat = 44
    var body: some View {
        Button(action: action) {
            Text("\(minutes)").font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundStyle(.white)
                .frame(width: Self.largeur, height: 28)
                .background(Capsule().fill(Color.white.opacity(survol ? 0.22 : 0.14)))
                .contentShape(Capsule())
        }
        .buttonStyle(AppuiIlot(echelle: 0.9))
        .onHover { survol = $0 }
        .accessibilityLabel("Minuteur de \(minutes) minutes")
    }
}

/// La case Étagère : « Glisse un fichier ici » ; les fichiers rangés (glissables vers une app, un clic les ouvre) ; « Lâche ici » quand
/// un fichier glissé passe sur le Centre (c'est le Centre entier qui le reçoit, la case s'éclaire).
struct CaseEtagere: View {
    @ObservedObject var m: IlotMoteur

    var body: some View {
        let f = m.etagere
        let depot = m.depot && m.depotSurvole
        let vide = f.isEmpty || !m.etagereActive
        ZStack(alignment: .topLeading) {
            FondCase(plein: !vide && !depot, pointille: vide, eclaire: depot)
            VStack(alignment: .leading, spacing: vide ? 12 : 5) {
                HStack(spacing: 7) {
                    GlypheIlot(nom: vide ? "tray" : "tray.full.fill", couleur: Color(hex: 0x5EB0FF), taille: 14).frame(width: 18, height: 17)
                    Text("Étagère").font(.system(size: 13.5, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    Spacer(minLength: 4)
                    if !vide {
                        Text("\(f.count)").font(.system(size: 12, weight: .bold).monospacedDigit()).foregroundStyle(.white)
                            .padding(.horizontal, 6).frame(minWidth: 19, minHeight: 19).background(Capsule().fill(Color.white.opacity(0.2)))
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(CouleursIlot.encre3)
                    }
                }
                .frame(height: 17)
                .contentShape(Rectangle())
                .onTapGesture { if !vide { m.epinglerLeCentre(); m.ouvrirEtagere() } }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(vide ? [] : .isButton)
                .accessibilityAction { if !vide { m.ouvrirEtagere() } }
                if depot {
                    Text("Lâche ici").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white)
                } else if !m.etagereActive {
                    HStack(spacing: 8) {
                        Text("Éteinte").font(.system(size: 12.5, weight: .medium)).foregroundStyle(Color.white.opacity(0.55))
                        CapIlot(titre: "Allumer", hauteur: 24, etiquette: "Allumer l\u{2019}étagère") { m.epinglerLeCentre(); m.surAction(.etagereAllumer) }
                    }
                    .padding(.top, -6)
                } else if f.isEmpty {
                    Text("Glisse un fichier ici").font(.system(size: 12.5, weight: .medium)).foregroundStyle(Color.white.opacity(0.55)).lineLimit(1)
                } else if f.count == 1, let un = f.first {
                    HStack(spacing: 9) {
                        icone(un, cote: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(un.nom).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white).lineLimit(1).truncationMode(.middle)
                            Text("glisse-le vers une app").font(.system(size: 11, weight: .medium)).foregroundStyle(Color.white.opacity(0.5)).lineLimit(1)
                        }
                    }
                } else {
                    // les plus récents d'abord, autant que la case en tient (28 pt + 6 d'écart) ; « +3 » pour le reste
                    HStack(spacing: 6) {
                        let montres = Array(f.reversed().prefix(4))
                        ForEach(montres) { x in icone(x, cote: 28) }
                        if f.count > montres.count {
                            Text("+\(f.count - montres.count)").font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundStyle(Color.white.opacity(0.6))
                        }
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
        }
        .animation(m.reduire || m.statique ? nil : .easeOut(duration: 0.2), value: depot)
    }

    /// L'icône d'un fichier rangé : on la glisse vers une app (le fichier lui-même), un clic l'ouvre.
    private func icone(_ x: FichierEtagere, cote: CGFloat) -> some View {
        Image(nsImage: x.icone).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            .frame(width: cote, height: cote)
            .contentShape(Rectangle())
            .onTapGesture { m.surAction(.etagereOuvrir(x.id)) }
            .glisserFichier(x.url, m)
            .accessibilityLabel(x.nom)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { m.surAction(.etagereOuvrir(x.id)) }
    }
}

// MARK: - le pied de la lecture, les points de page, la bulle « Nouveau »

/// Sous les commandes de la lecture dépliée : le bouton « Centre » (avec les petites icônes de ce qu'il contient) et, tant qu'il n'a
/// jamais servi, l'aide « Fais défiler ou clique ici ».
struct PiedLecture: View {
    @ObservedObject var m: IlotMoteur
    var g: GrilleIlot
    @State private var survol = false

    static func cadre(_ g: GrilleIlot) -> CGRect {
        let w = g.corps(.lectureEtendu)
        return CGRect(x: -w + GrilleIlot.marge, y: g.barre + CGFloat(GeoIlot.profondeurLecture) - 4, width: 2 * w - 2 * GrilleIlot.marge - GrilleIlot.placePoints, height: 30)
    }
    /// Le milieu du bouton « Centre » (essais : où cliquer) : 40 pt après le bord gauche, sur le mot « Centre ».
    static func pointBouton(_ g: GrilleIlot) -> CGPoint { let c = cadre(g); return CGPoint(x: c.minX + 50, y: c.midY) }

    var body: some View {
        HStack(spacing: 10) {
            Button { m.allerA(.centre) } label: {
                HStack(spacing: 7) {
                    Image(systemName: "switch.2").font(.system(size: 13, weight: .semibold)).frame(width: 15)
                    Text("Centre").font(.system(size: 13, weight: .semibold)).lineLimit(1).fixedSize()
                    HStack(spacing: 5) {
                        // le micro coupé se voit encore, en rouge, quand la vidéo s'est dépliée par-dessus
                        Image(systemName: m.microCoupe ? "mic.slash.fill" : "mic.fill").foregroundStyle(m.microCoupe ? CouleursIlot.rouge : Color.white.opacity(0.55))
                        Image(systemName: "tray.fill")
                        Image(systemName: "arrow.down.circle")
                    }
                    .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Color.white.opacity(0.55))
                    .padding(.leading, 1)
                }
                .foregroundStyle(.white)
                .padding(.leading, 9).padding(.trailing, 13)
                .frame(height: 30)
                .background(Capsule().fill(Color.white.opacity(survol ? 0.2 : 0.14)))
                .contentShape(Capsule())
            }
            .buttonStyle(AppuiIlot(echelle: 0.94))
            .onHover { survol = $0 }
            .accessibilityLabel("Ouvrir le Centre : micro, étagère, téléchargements, minuteur")
            .aspectIlot(m.aspect(ExtraIlot.pied, rang: 0), ancre: .leading)
            HStack(spacing: 6) {
                Image(systemName: "chevron.left").font(.system(size: 10, weight: .bold))
                Text("Fais défiler ou clique ici").font(.system(size: 12, weight: .medium)).lineLimit(1)
            }
            .foregroundStyle(Color.white.opacity(0.45))
            .opacity(m.aideCentre ? 1 : 0)
            .animation(m.reduire || m.statique ? nil : .easeOut(duration: 0.3), value: m.aideCentre)
            .aspectIlot(m.aspect(ExtraIlot.pied, rang: 1), ancre: .leading)
            .accessibilityHidden(true)
            Spacer(minLength: 0)
        }
        .posee(Self.cadre(g))
    }
}

/// Les points de page, au bord droit des cartes (lecture, Centre, accueil) : un point par carte, celui de la carte montrée en blanc ; un
/// clic sur un point y mène. Ils suivent le milieu du corps pendant que la forme change de hauteur.
struct PointsCartes: View {
    @ObservedObject var m: IlotMoteur
    var g: GrilleIlot
    static let pas: CGFloat = 16, largeur: CGFloat = 22

    /// Le centre du point n°`i` (sur `n`) pour une forme de demi-corps `corps` et de hauteur `hauteur` (essais : où cliquer).
    static func centre(_ i: Int, sur n: Int, corps: CGFloat, hauteur: CGFloat, barre: CGFloat) -> CGPoint {
        let total = CGFloat(n) * pas
        let y0 = barre + (hauteur - barre) / 2 - total / 2
        return CGPoint(x: corps - 15, y: y0 + pas * (CGFloat(i) + 0.5))
    }

    var body: some View {
        let pile = m.cartes
        let corps = CGFloat(m.trace.corps), h = CGFloat(m.geo[2].x)
        let p0 = Self.centre(0, sur: pile.count, corps: corps, hauteur: h, barre: g.barre)
        VStack(spacing: 0) {
            ForEach(Array(pile.enumerated()), id: \.offset) { _, c in
                let on = m.carteCourante == c
                Button { m.allerA(c) } label: {
                    Circle().fill(Color.white.opacity(on ? 1 : 0.3)).frame(width: 7, height: 7).scaleEffect(on ? 1.1 : 1)
                        .frame(width: Self.largeur, height: Self.pas).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Self.nom(c, m))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .animation(m.reduire || m.statique ? nil : .easeOut(duration: 0.2), value: m.carteCourante)
        .posee(CGRect(x: p0.x - Self.largeur / 2, y: p0.y - Self.pas / 2, width: Self.largeur, height: Self.pas * CGFloat(pile.count)),
               m.aspect(ExtraIlot.points), ancre: .center)
    }
    static func nom(_ c: VueIlot, _ m: IlotMoteur) -> String {
        switch c {
        case .centre: return "Le Centre"
        case .accueil: return "Rendez-vous, rappel et dernière dictée"
        default: return m.nomPremiereCarte ?? "Activité"
        }
    }
}

/// La bulle « Nouveau : survole l'îlot », sous l'îlot replié, une seule fois (premier lancement).
struct BulleNouveau: View {
    @ObservedObject var m: IlotMoteur
    var g: GrilleIlot
    static let gras = "Nouveau", suite = "\u{00A0}: survole l\u{2019}îlot"
    /// La largeur du texte (Core Text, mêmes polices) : la forme l'épouse.
    static var largeur: CGFloat { MesureIlot.texte(gras, 14, .bold) + MesureIlot.texte(suite, 14, .medium) }
    var body: some View {
        let l = Self.largeur + 4
        HStack(spacing: 0) {
            Text(Self.gras).font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
            Text(Self.suite).font(.system(size: 14, weight: .medium)).foregroundStyle(Color.white.opacity(0.8))
        }
        .lineLimit(1).fixedSize()
        .posee(CGRect(x: -l / 2, y: g.barre + (CGFloat(GeoIlot.profondeurBulle) - 20) / 2 - 1, width: l, height: 20), m.aspect(ExtraIlot.bulle), ancre: .top, .center)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - les actions du Centre

/// Ce que le Centre lit et écrit des réglages : injectable (les essais n'écrivent jamais les vrais réglages).
struct ReglagesCentre {
    var telechargements: () -> Bool = { Settings.ilotTelechargements }
    var reglerTelechargements: (Bool) -> Void = { Settings.ilotTelechargements = $0 }
    var microChoisi: () -> String? = { Settings.micro }
    var choisirMicro: (String?) -> Void = { Settings.micro = $0 }
    var bulleVue: () -> Bool = { Settings.ilotBulleVue }
    var marquerBulleVue: () -> Void = { Settings.ilotBulleVue = true }
    var centreUtilise: () -> Bool = { Settings.ilotCentreUtilise }
    var marquerCentreUtilise: () -> Void = { Settings.ilotCentreUtilise = true }
    var allumerMicro: () -> Void = { Settings.ilotMicro = true }
    var allumerClaude: () -> Void = { Settings.ilotClaude = true }
    var allumerEtagere: () -> Void = { Settings.ilotEtagere = true }
}

extension IlotControleur {
    /// Les boutons du Centre. Chacun réutilise ce qui existe (micro coupé, téléchargements, crochets de Claude, étagère) ; l'îlot reste
    /// ouvert (sauf pour aller au Terminal).
    func agirCentre(_ a: ActionIlot) {
        switch a {
        case .centreMicro:
            // « Micro coupé » éteint dans les réglages : le premier clic l'allume (rien n'est demandé à macOS pour couper un micro)
            if !micro.actif {
                reglagesCentre.allumerMicro()
                activerLeMicro(true)
                surRaccourciMicro(micro.actif ? Settings.raccourciMicro : nil)
                NotificationCenter.default.post(name: .verbeIlotReglagesRelus, object: nil)
            }
            if !basculerLeMicro() { Log.ecrire("micro coupé : le Centre n'a pas pu basculer le micro (aucun micro, ou commande refusée)") }
            moteur.donneesChangees()
        case .centreTelechargements:
            reglerTelechargements(!moteur.telechargementsActifs)
        case .centreClaude:
            // une session au travail : on la rejoint ; branché : le Terminal (ou l'app de la dernière session) ; sinon, on branche
            if let s = moteur.claude { moteur.fermer(); ramenerApp(s.app); return }
            if moteur.claudeBranche { moteur.fermer(); ramenerApp(moteur.dernierClaude?.app); return }
            do {
                try installationClaude.brancher()
                moteur.claudeBranche = true
                if !claudeSource.actif { reglagesCentre.allumerClaude(); activerClaude(true) }
                NotificationCenter.default.post(name: .verbeIlotReglagesRelus, object: nil)
            } catch let e as InstallationClaude.Echec {
                Log.ecrire("claude : branchement depuis le Centre impossible (\(e.phrase))")
            } catch {
                Log.ecrire("claude : branchement depuis le Centre impossible")
            }
            moteur.donneesChangees()
        case .etagereAllumer:
            reglagesCentre.allumerEtagere()
            activerEtagere(true)
            NotificationCenter.default.post(name: .verbeIlotReglagesRelus, object: nil)
        default: break
        }
    }
}
