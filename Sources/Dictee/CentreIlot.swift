import AppKit
import SwiftUI
import DicteeCore

// Le Centre de l'îlot (maquette design/maquettes/ilot-centre.html, validée par Hugues : « une sorte de mini-agent, multitâche ») : tout ce qui
// se règle depuis l'îlot, à la souris, sans raccourci (seule la touche fn reste, pour dicter).
// - une rangée de gros boutons ronds (cinq au plus), chacun avec son nom et son état dessous : Micro, Dictée (Mac / AirPods), Téléchargements,
//   Claude Code ; Rappel et Dernière dictée s'ajoutent par « Modifier » ;
// - deux grandes cases : Minuteur (5 · 10 · 25 min, ou le temps qui reste, pause, arrêt) et Étagère (on y lâche un fichier, on l'en reprend) ;
// - la bande « Noter la réunion » ;
// - « Modifier » (CentreModifier.swift) : retirer, ajouter, ranger en glissant ; « OK » enregistre ;
// - on y arrive sans rien deviner : bouton « Centre » au pied du déplié de toute activité (la vidéo, le minuteur, Claude, un rendez-vous),
//   points de page à droite des cartes, défilement (un geste = une carte) ; l'îlot vide s'ouvre directement dessus ;
// - un clic sur un bouton épingle l'îlot (« Reste ouvert ») : on enchaîne plusieurs réglages, un bandeau attend qu'il se range ; il se
//   range au clic ailleurs ou sur l'îlot dans la barre des menus (un clic dans son vide ne compte pas : on visait un bouton).
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

/// Les mesures du Centre (maquette, en points) : elles servent au dessin et aux essais (où cliquer). Les rangées présentes (ronds, cases,
/// bande de la réunion) dépendent de ce que le Centre montre (« Modifier ») : leur place vient de `DispositionCentre.plan`.
@MainActor
enum PlanCentre {
    static let haut = CGFloat(DispositionCentre.haut), entete = CGFloat(DispositionCentre.entete)
    static let rond: CGFloat = 52
    /// Le nom sous un rond : 11,5 pt semi-gras, serré (maquette). S'il ne tient pas dans sa place (cinq ronds : « Téléchargements »), il
    /// est écrit plus petit, mesuré, jusqu'à 9,5 pt : jamais collé à son voisin (la maquette les faisait se toucher).
    static let policeNom: CGFloat = 11.5, interlettreNom: CGFloat = -0.25, policeMin: CGFloat = 9.5
    /// Ce qui sépare deux noms (ou deux états) voisins, au moins.
    static let ecartNoms: CGFloat = 4
    /// Où sont les éléments, depuis le centre de l'encoche (x) et le haut de l'écran (y).
    static func zone(_ g: GrilleIlot) -> CGRect { g.zoneCarte(.centre, haut: haut, bas: haut) }
    static func cadreEntete(_ g: GrilleIlot) -> CGRect { let z = zone(g); return CGRect(x: z.minX, y: z.minY, width: z.width, height: entete) }
    /// Tout le corps du Centre sous la barre (son vide ne range pas l'îlot).
    static func fond(_ g: GrilleIlot) -> CGRect {
        let w = g.corps(.centre)
        return CGRect(x: -w, y: g.barre, width: 2 * w, height: g.hauteur(.centre) - g.barre)
    }
    /// Une rangée (nil : elle n'est pas montrée).
    static func cadre(_ r: DispositionCentre.Rangee, _ m: IlotMoteur, _ g: GrilleIlot? = nil) -> CGRect? {
        let g = g ?? m.grille
        let p = DispositionCentre.plan(ronds: !m.rondsCentre.isEmpty, cases: !m.disposition.cases.isEmpty, bande: m.disposition.bande)
        guard let y = p.hauts[r] else { return nil }
        let z = zone(g)
        let h: Double
        switch r { case .ronds: h = DispositionCentre.ronds; case .cases: h = DispositionCentre.cases; case .bande: h = DispositionCentre.bande }
        return CGRect(x: z.minX, y: g.barre + CGFloat(y), width: z.width, height: CGFloat(h))
    }
    static func cadreRonds(_ m: IlotMoteur, _ g: GrilleIlot? = nil) -> CGRect { cadre(.ronds, m, g) ?? .zero }
    static func cadreBande(_ m: IlotMoteur, _ g: GrilleIlot? = nil) -> CGRect { cadre(.bande, m, g) ?? .zero }
    /// Une grande case : seule, elle prend toute la largeur ; à deux, chacune la moitié (10 pt entre elles).
    static func cadreCase(_ m: IlotMoteur, _ e: ElementCentre, _ g: GrilleIlot? = nil) -> CGRect {
        guard let c = cadre(.cases, m, g) else { return .zero }
        let cs = m.disposition.cases
        guard cs.count > 1, let i = cs.firstIndex(of: e) else { return c }
        let l = (c.width - CGFloat(DispositionCentre.ecart)) / 2
        return CGRect(x: i == 0 ? c.minX : c.minX + l + CGFloat(DispositionCentre.ecart), y: c.minY, width: l, height: c.height)
    }
    /// La largeur d'une colonne de la rangée des ronds.
    static func colonne(_ m: IlotMoteur, _ g: GrilleIlot? = nil) -> CGFloat { cadreRonds(m, g).width / CGFloat(max(1, m.rondsCentre.count)) }
    /// Le centre du rond d'un élément montré.
    static func centreRond(_ m: IlotMoteur, _ e: ElementCentre, _ g: GrilleIlot? = nil) -> CGPoint {
        let r = cadreRonds(m, g), l = colonne(m, g), i = CGFloat(m.rondsCentre.firstIndex(of: e) ?? 0)
        return CGPoint(x: r.minX + l * (i + 0.5), y: r.minY + rond / 2)
    }
    /// Les places des textes d'une ligne sous les ronds (noms, ou états), et la taille de chacun : un texte court laisse de la place à son
    /// voisin long, deux voisins gardent `ecartNoms` entre eux.
    static func tailles(_ textes: [String], colonne: CGFloat, poids: NSFont.Weight, interlettre: CGFloat = 0) -> [(place: CGFloat, taille: CGFloat)] {
        let l = textes.map { Double(MesureIlot.texte($0, policeNom, poids, interlettre: interlettre)) }
        let p = DispositionCentre.largeursPermises(l, colonne: Double(colonne), ecart: Double(ecartNoms))
        return zip(textes, p).map { (CGFloat($1), police($0, place: CGFloat($1), poids: poids, interlettre: interlettre)) }
    }
    /// La taille d'un texte sous un rond, mesurée pour tenir dans `place` pt.
    static func police(_ texte: String, place: CGFloat, poids: NSFont.Weight, interlettre: CGFloat = 0) -> CGFloat {
        let l = MesureIlot.texte(texte, policeNom, poids, interlettre: interlettre)
        guard l > place, l > 0 else { return policeNom }
        // la largeur suit la taille (à 0,1 pt près, l'interlettre compris) : on réduit, puis on vérifie
        var t = max(policeMin, (policeNom * place / l * 10).rounded(.down) / 10)
        while t > policeMin, MesureIlot.texte(texte, t, poids, interlettre: interlettre) > place { t -= 0.1 }
        return t
    }
}

extension ElementCentre {
    /// Le nom (sous le rond, dans « Ajouter : »).
    var nom: String {
        switch self {
        case .micro: return "Micro"
        case .dictee: return "Dictée"
        case .telechargements: return "Téléchargements"
        case .claude: return "Claude Code"
        case .rappel: return "Rappel"
        case .derniereDictee: return "Dernière dictée"
        case .reunion: return "Réunion"
        case .minuteur: return "Minuteur"
        case .etagere: return "Étagère"
        }
    }
}

extension IlotMoteur {
    /// Un élément peut-il paraître ? Le choix du micro de la dictée n'existe qu'avec des AirPods (un micro Bluetooth) branchés.
    func disponibleDansLeCentre(_ e: ElementCentre) -> Bool { e != .dictee || choixMicro != nil }
    /// Les ronds montrés, dans l'ordre (cinq au plus).
    var rondsCentre: [ElementCentre] { disposition.ronds(disponible: disponibleDansLeCentre) }
    /// L'état écrit sous un rond (« Coupé », « Allumé », « 3 sur 7 »…).
    func etatCentre(_ e: ElementCentre) -> String {
        switch e {
        case .micro: return microCoupe ? "Coupé" : "Ouvert"
        case .dictee: return choixMicro?.airpods == true ? "AirPods" : "Mac"
        case .telechargements: return telechargementsAttente ? "Un instant\u{2026}" : (telechargementsActifs ? "Allumé" : "Éteint")
        case .claude:
            if let s = claude { let t = texteClaude(s, taille: PlanCentre.policeNom); return t.isEmpty ? "Au travail" : t }
            return claudeBranche ? "Prêt" : "Brancher"
        case .rappel: return "Dire un rappel"
        case .derniereDictee: return derniereDictee != nil ? "Coller" : "Aucune"
        case .reunion, .minuteur, .etagere: return ""
        }
    }
    /// Le nom de la première carte, pour le bouton de retour du Centre (« ‹ Vidéo »).
    var nomPremiereCarte: String? {
        guard let p = cartes.first, p != .centre else { return nil }
        switch p {
        case .lectureEtendu, .lectureMinuteur: return lecture.genre == .musique ? "Musique" : "Vidéo"
        case .minuteurEtendu: return "Minuteur"
        case .microEtendu: return "Micro"
        case .claudeEtendu: return "Claude"
        case .reunionEtendu: return "Réunion"
        case .agendaEtendu: return "Rendez-vous"
        case .rappelEtendu, .rappelListe: return "Rappel"
        default: return nil
        }
    }
}

struct CentreVue: View {
    @ObservedObject var m: IlotMoteur
    var g: GrilleIlot
    /// Le bouton ou la case qu'on range en le glissant (« Modifier ») : où est le pointeur, et où on l'a pris (depuis le milieu de sa place).
    @State private var glisse: GlisseCentre?
    static let espace = "centre"

    var body: some View {
        let v = VueIlot.centre
        ZStack(alignment: .topLeading) {
            // un clic dans le vide du Centre (entre l'en-tête, les ronds, les cases et la bande, dans les marges) ne le range pas : on
            // visait un bouton à quelques points près ; il se range au clic ailleurs. Seulement tant qu'il est là (pas pendant son départ)
            Color.clear.contentShape(Rectangle()).onTapGesture {}
                .allowsHitTesting(m.courante == v)
                .accessibilityHidden(true)
                .posee(PlanCentre.fond(g))
            EnteteCentre(m: m, largeur: PlanCentre.cadreEntete(g).width).posee(PlanCentre.cadreEntete(g), m.aspect(v, rang: 0), ancre: .topLeading)
            if !m.rondsCentre.isEmpty { ronds.posee(PlanCentre.cadreRonds(m, g), m.aspect(v, rang: 1), ancre: .top) }
            ForEach(Array(m.disposition.cases.enumerated()), id: \.element) { i, e in
                grandeCase(e, rang: i).posee(PlanCentre.cadreCase(m, e, g), m.aspect(v, rang: 2 + i), ancre: .top)
                    .zIndex(glisse?.element == e ? 1 : 0)
            }
            if m.disposition.bande {
                BandeReunion(m: m).posee(PlanCentre.cadreBande(m, g), m.aspect(v, rang: 4), ancre: .top)
            }
        }
        .frame(width: IlotMoteur.largeur, height: IlotMoteur.hauteurMax, alignment: .topLeading)
        .coordinateSpace(name: Self.espace)
        .animation(m.reduire || m.statique ? nil : .spring(response: 0.32, dampingFraction: 0.82), value: m.disposition)
    }

    private var ronds: some View {
        let rs = m.rondsCentre
        let cadre = PlanCentre.cadreRonds(m, g)
        let l = PlanCentre.colonne(m, g)
        // les noms et les états, mesurés ensemble : un texte court laisse de la place à son voisin long
        let noms = PlanCentre.tailles(rs.map(\.nom), colonne: l, poids: .semibold, interlettre: PlanCentre.interlettreNom)
        let etats = PlanCentre.tailles(rs.map(m.etatCentre), colonne: l, poids: .medium)
        return HStack(spacing: 0) {
            ForEach(Array(rs.enumerated()), id: \.element) { i, e in
                let milieu = cadre.minX + l * (CGFloat(i) + 0.5)
                bouton(e, colonne: l, rang: i, tailles: (noms[i].taille, etats[i].taille))
                    .frame(width: l, height: CGFloat(DispositionCentre.ronds), alignment: .top)
                    .contentShape(Rectangle())
                    .offset(x: glisse.flatMap { $0.element == e ? $0.x - $0.prise - milieu : nil } ?? 0)
                    .zIndex(glisse?.element == e ? 1 : 0)
                    .gesture(ranger(e, milieu: milieu) { centre in
                        let cible = min(rs.count - 1, max(0, Int(((centre - cadre.minX) / l).rounded(.down))))
                        m.rangerDansLeCentre(e, versRang: cible, parmi: m.rondsCentre)
                    }, including: m.editionCentre ? .all : .subviews)
                    // « Modifier » : un clic sur un rond ne fait rien (il ne referme pas l'îlot non plus)
                    .gesture(TapGesture().onEnded {}, including: m.editionCentre ? .all : .subviews)
            }
        }
    }

    /// Ranger en glissant (« Modifier ») : la pièce suit le pointeur ; quand son milieu passe sur une autre place, elle la prend.
    private func ranger(_ e: ElementCentre, milieu: CGFloat, viser: @escaping (CGFloat) -> Void) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(Self.espace))
            .onChanged { v in
                let x = v.location.x - IlotMoteur.largeur / 2
                if glisse?.element != e { glisse = GlisseCentre(element: e, prise: v.startLocation.x - IlotMoteur.largeur / 2 - milieu, x: x) }
                else { glisse?.x = x }
                if let gl = glisse { viser(gl.x - gl.prise) }
            }
            .onEnded { _ in
                if m.reduire || m.statique { glisse = nil } else { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { glisse = nil } }
            }
    }

    @ViewBuilder private func grandeCase(_ e: ElementCentre, rang: Int) -> some View {
        let ed = m.editionCentre
        let cs = m.disposition.cases
        let c = PlanCentre.cadreCase(m, e, g)
        let rangee = PlanCentre.cadre(.cases, m, g) ?? c
        Group {
            switch e {
            case .minuteur: CaseMinuteur(m: m)
            default: CaseEtagere(m: m)
            }
        }
        .allowsHitTesting(!ed)
        .overlay { if ed { Color.clear.contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous)).onTapGesture {} } }
        .tremblement(ed && (m.statique || !m.reduire), amplitude: 1.4, decale: rang % 2 == 1, fige: m.statique)
        .overlay(alignment: .topLeading) {
            if ed { BadgeRetirer(nom: e.nom) { m.retirerDuCentre(e) }.offset(x: -6, y: -6) }
        }
        .offset(x: glisse.flatMap { $0.element == e ? $0.x - $0.prise - c.midX : nil } ?? 0)
        .gesture(ranger(e, milieu: c.midX) { centre in
            guard cs.count > 1 else { return }
            m.rangerDansLeCentre(e, versRang: centre > rangee.midX ? 1 : 0, parmi: m.disposition.cases)
        }, including: ed ? .all : .subviews)
    }

    /// Un clic sur un bouton : l'îlot reste ouvert, puis l'action (celles de l'îlot, déjà construites).
    private func agir(_ a: ActionIlot) { m.epinglerLeCentre(); m.surAction(a) }

    @ViewBuilder private func bouton(_ e: ElementCentre, colonne l: CGFloat, rang: Int, tailles t: (nom: CGFloat, etat: CGFloat)) -> some View {
        let ed = m.editionCentre
        let etat = m.etatCentre(e)
        let fige = m.reduire || m.statique
        let retirer: (() -> Void)? = ed ? { m.retirerDuCentre(e) } : nil
        switch e {
        case .micro:
            let coupe = m.microCoupe
            TuileRonde(nom: e.nom, etat: etat, couleurEtat: coupe ? Color(hex: 0xFF6961) : CouleursIlot.encre2,
                       fond: coupe ? CouleursIlot.rouge : nil, colonne: l, tailleNom: t.nom, tailleEtat: t.etat, reduire: fige, edition: ed, rang: rang, statique: m.statique, retirer: retirer,
                       etiquette: coupe ? "Micro coupé : le rouvrir" : "Micro ouvert : le couper") {
                Image(systemName: coupe ? "mic.slash.fill" : "mic.fill").font(.system(size: 21, weight: .semibold)).foregroundStyle(.white)
            } action: { agir(.centreMicro) }
        case .dictee:
            let airpods = m.choixMicro?.airpods ?? false
            TuileRonde(nom: e.nom, etat: etat, couleurEtat: CouleursIlot.encre2, fond: nil, colonne: l, tailleNom: t.nom, tailleEtat: t.etat,
                       reduire: fige, edition: ed, rang: rang, statique: m.statique, retirer: retirer,
                       etiquette: airpods ? "La dictée écoute les AirPods : passer au micro du Mac" : "La dictée écoute le micro du Mac : passer aux AirPods") {
                Image(systemName: airpods ? "airpodspro" : "laptopcomputer").font(.system(size: airpods ? 22 : 20, weight: .semibold)).foregroundStyle(.white)
            } action: { agir(.microChoisir(airpods: !airpods)) }
        case .telechargements:
            let on = m.telechargementsActifs, attente = m.telechargementsAttente
            TuileRonde(nom: e.nom, etat: etat,
                       couleurEtat: on && !attente ? Color(hex: 0x5EB0FF) : CouleursIlot.encre2,
                       fond: on && !attente ? CouleursIlot.bleu : nil, anneau: attente, colonne: l, tailleNom: t.nom, tailleEtat: t.etat, reduire: fige, edition: ed, rang: rang,
                       statique: m.statique, retirer: retirer,
                       etiquette: attente ? "Téléchargements : macOS demande l\u{2019}accès" : (on ? "Téléchargements allumé : l'éteindre" : "Téléchargements éteint : l'allumer")) {
                Image(systemName: "arrow.down.circle").font(.system(size: 22, weight: .semibold)).foregroundStyle(.white)
            } action: { agir(.centreTelechargements) }
        case .claude:
            let s = m.claude
            let branche = m.claudeBranche || s != nil
            TuileRonde(nom: e.nom, etat: etat, couleurEtat: branche ? CouleursIlot.encre2 : Color(hex: 0x5EB0FF),
                       fond: branche ? CouleursIlot.corail : nil, pointille: !branche, colonne: l, tailleNom: t.nom, tailleEtat: t.etat, reduire: fige, edition: ed, rang: rang,
                       statique: m.statique, retirer: retirer,
                       etiquette: s != nil ? "Claude Code, \(etat) : ouvrir" : (branche ? "Claude Code prêt" : "Brancher Claude Code")) {
                EtoileClaude(couleur: branche ? .white : Color.white.opacity(0.75)).frame(width: 21, height: 21)
            } action: { agir(.centreClaude) }
        case .rappel:
            TuileRonde(nom: e.nom, etat: etat, couleurEtat: CouleursIlot.encre2, fond: nil, colonne: l, tailleNom: t.nom, tailleEtat: t.etat, reduire: fige, edition: ed,
                       rang: rang, statique: m.statique, retirer: retirer, etiquette: "Dire un rappel") {
                Image(systemName: "bell.fill").font(.system(size: 20, weight: .semibold)).foregroundStyle(CouleursIlot.jaune)
            } action: { agir(.rappelFormulaire) }
        case .derniereDictee:
            let la = m.derniereDictee != nil
            TuileRonde(nom: e.nom, etat: etat, couleurEtat: la ? Color(hex: 0x5EB0FF) : CouleursIlot.encre3, fond: nil, colonne: l, tailleNom: t.nom, tailleEtat: t.etat,
                       reduire: fige, edition: ed, rang: rang, statique: m.statique, retirer: retirer,
                       etiquette: la ? "Coller la dernière dictée" : "Aucune dictée à coller") {
                Image(systemName: "quote.opening").font(.system(size: 19, weight: .bold)).foregroundStyle(.white.opacity(la ? 1 : 0.5))
            } action: { if la { agir(.collerLaDerniereDictee) } }
        case .reunion, .minuteur, .etagere:
            EmptyView()
        }
    }
}

/// Le bouton ou la case qu'on range en glissant.
struct GlisseCentre: Equatable {
    var element: ElementCentre
    /// Où on l'a pris, depuis le milieu de sa place (il ne saute pas sous le pointeur).
    var prise: CGFloat
    /// Le pointeur (x depuis le centre de l'encoche).
    var x: CGFloat
}

/// Un gros bouton rond du Centre (comme le Centre de contrôle de l'iPhone) : le rond de 52 pt, son nom, son état dessous. Le rond prend
/// la couleur de l'état (rouge coupé, bleu allumé, corail Claude) ; « Brancher » : un rond en pointillé ; « Un instant… » : un anneau bleu.
/// « Modifier » : le rond tremble, un « – » le retire, un clic dessus ne fait rien (on le range en le glissant).
struct TuileRonde<Glyphe: View>: View {
    var nom: String
    var etat: String
    var couleurEtat: Color
    var fond: Color?
    var pointille = false
    var anneau = false
    var colonne: CGFloat
    /// Les tailles du nom et de l'état, mesurées avec les voisins (`PlanCentre.tailles`).
    var tailleNom = PlanCentre.policeNom
    var tailleEtat = PlanCentre.policeNom
    var reduire: Bool
    var edition = false
    var rang = 0
    var statique = false
    var retirer: (() -> Void)?
    var etiquette: String
    @ViewBuilder var glyphe: () -> Glyphe
    var action: () -> Void
    @State private var survol = false

    var body: some View {
        // « Modifier » : plus un bouton (un clic ne fait rien, le glisser du Centre range le rond), seul le « – » répond
        Group {
            if edition {
                contenu
            } else {
                Button(action: action) { contenu }
                    .buttonStyle(AppuiIlot(echelle: 0.94))
                    .onHover { survol = $0 }
                    .animation(.easeOut(duration: 0.15), value: survol)
            }
        }
        .accessibilityElement(children: edition ? .contain : .combine)
        .accessibilityLabel(etiquette)
        .accessibilityValue(etat)
    }

    private var contenu: some View {
        VStack(spacing: 0) {
            ZStack {
                if pointille {
                    Circle().strokeBorder(Color.white.opacity(survol ? 0.6 : 0.4), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3.2]))
                } else {
                    Circle().fill(fond ?? Color.white.opacity(0.14)).brightness(survol && !edition ? 0.08 : 0)
                }
                if anneau { Circle().strokeBorder(CouleursIlot.bleu, lineWidth: 2) }
                glyphe()
            }
            .frame(width: PlanCentre.rond, height: PlanCentre.rond)
            .keyframeAnimator(initialValue: 1.0, trigger: etat) { v, s in v.scaleEffect(reduire ? 1 : s) } keyframes: { _ in
                KeyframeTrack { LinearKeyframe(0.86, duration: 0.09); SpringKeyframe(1.04, duration: 0.14); SpringKeyframe(1, duration: 0.2, spring: Spring(response: 0.3, dampingRatio: 0.7)) }
            }
            .overlay(alignment: .topLeading) {
                if edition, let retirer { BadgeRetirer(nom: nom, action: retirer).offset(x: -5, y: -5) }
            }
            .tremblement(edition && (statique || !reduire), amplitude: 1.4, decale: rang % 2 == 1, fige: statique)
            // le nom et l'état, mesurés : plus petits s'ils ne tiennent pas dans la colonne (jamais tassés contre le voisin)
            Text(nom).font(.system(size: tailleNom, weight: .semibold)).tracking(PlanCentre.interlettreNom)
                .foregroundStyle(.white).lineLimit(1).fixedSize()
                .padding(.top, 7)
            Text(etat).font(.system(size: tailleEtat, weight: .medium)).foregroundStyle(couleurEtat)
                .lineLimit(1).fixedSize()
                .contentTransition(.opacity)
                .padding(.top, 1)
        }
        .frame(width: colonne)
        .contentShape(Rectangle())
    }
}

/// Le « – » de « Modifier » (20 pt, gris, cerné de noir comme sur l'iPhone) : retire le bouton ou la case du Centre.
struct BadgeRetirer: View {
    var nom: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "minus").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color(hex: 0x5A5A5F)))
                .background(Circle().fill(Color.black).padding(-2))
                .contentShape(Circle().inset(by: -3))
        }
        .buttonStyle(AppuiIlot(echelle: 0.85))
        .accessibilityLabel("Retirer « \(nom) » du Centre")
    }
}

/// Les pilules de l'en-tête : « ‹ Vidéo », « Modifier » (26 pt, maquette).
struct PiluleCentre: View {
    var titre: String
    var retour = false
    /// Un glyphe avant le titre (les guillemets de « Dictées »).
    var symbole: String? = nil
    /// « OK » de « Modifier » : blanche, texte noir (maquette).
    var plein = false
    var etiquette: String
    var action: () -> Void
    @State private var survol = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if retour { Image(systemName: "chevron.left").font(.system(size: 10.5, weight: .bold)) }
                if let symbole { Image(systemName: symbole).font(.system(size: 10, weight: .bold)) }
                Text(titre).font(.system(size: 12.5, weight: .semibold)).lineLimit(1).fixedSize()
            }
            .foregroundStyle(plein ? .black : .white)
            .padding(.leading, retour ? 8 : 11).padding(.trailing, 11)
            .frame(height: 26)
            .background(Capsule().fill(plein ? Color.white.opacity(survol ? 0.88 : 1) : Color.white.opacity(survol ? 0.2 : 0.12)))
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

// MARK: - le pied des dépliés, les points de page, la bulle « Nouveau »

/// Sous le déplié d'une activité (la vidéo, le minuteur, Claude, un rendez-vous, un rappel) : le bouton « Centre » (avec les petites
/// icônes de ce qu'il contient, le micro en rouge s'il est coupé), le bouton « Dictées » (maquette, étape 2 : l'ancien panneau de la
/// barre des menus) s'il tient, et, tant que le Centre n'a jamais servi et s'il y a la place, l'aide « ou fais défiler ». Il est posé en
/// bas de la forme : 30 pt, 14 pt sous lui (la lecture l'a dans sa géométrie, les autres dépliés l'ajoutent sous leur contenu,
/// `CartesIlot.piedEnPlus`).
struct PiedCarte: View {
    @ObservedObject var m: IlotMoteur
    var g: GrilleIlot
    /// La carte qui le porte.
    var v: VueIlot
    @State private var survol = false

    static func cadre(_ g: GrilleIlot, _ v: VueIlot) -> CGRect {
        let w = g.corps(v)
        return CGRect(x: -w + GrilleIlot.marge, y: g.hauteur(v) - 44, width: 2 * w - 2 * GrilleIlot.marge - GrilleIlot.placePoints, height: 30)
    }
    /// Le milieu du bouton « Centre » (essais : où cliquer) : 50 pt après le bord gauche, sur le mot « Centre ».
    static func pointBouton(_ g: GrilleIlot, _ v: VueIlot = .lectureEtendu) -> CGPoint { let c = cadre(g, v); return CGPoint(x: c.minX + 50, y: c.midY) }
    /// Le milieu du bouton « Dictées » (essais).
    static func pointDictees(_ g: GrilleIlot, _ v: VueIlot = .lectureEtendu) -> CGPoint {
        let c = cadre(g, v); return CGPoint(x: c.minX + largeurBouton + 10 + largeurDictees / 2, y: c.midY)
    }
    static let aide = "ou fais défiler"
    /// Le bouton, mesuré (Core Text, mêmes polices) : 9 + glyphe 15 + 7 + « Centre » + 7 + 1 + trois petites icônes (5 pt entre) + 13.
    static var largeurBouton: CGFloat {
        let icones = ["mic.slash.fill", "tray.fill", "arrow.down.circle"].map { MesureIlot.symbole($0, 10.5) }.reduce(0, +) + 10
        return 9 + 15 + 7 + MesureIlot.texte("Centre", 13, .semibold) + 7 + 1 + icones + 13
    }
    /// Le bouton « Dictées », mesuré : 9 + glyphe 15 + 7 + « Dictées » + 13.
    static var largeurDictees: CGFloat { 9 + 15 + 7 + MesureIlot.texte("Dictées", 13, .semibold) + 13 }
    /// Le bouton « Dictées » tient-il à côté du bouton « Centre » ? (Sinon : la pilule « Dictées » du Centre y mène.)
    static func dicteesTient(_ g: GrilleIlot, _ v: VueIlot) -> Bool { largeurBouton + 10 + largeurDictees <= cadre(g, v).width }
    /// L'aide « ⌄ ou fais défiler », mesurée ; elle ne paraît que si elle tient à côté des boutons (pas sous un Claude étroit).
    static var largeurAide: CGFloat { MesureIlot.symbole("chevron.down", 10) + 6 + MesureIlot.texte(aide, 12, .medium) }
    static func aideTient(_ g: GrilleIlot, _ v: VueIlot) -> Bool {
        largeurBouton + 10 + (dicteesTient(g, v) ? largeurDictees + 10 : 0) + largeurAide <= cadre(g, v).width
    }

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
            if Self.dicteesTient(g, v) {
                BoutonPiedDictees { m.allerA(.dictees) }
                    .aspectIlot(m.aspect(ExtraIlot.pied, rang: 1), ancre: .leading)
            }
            HStack(spacing: 6) {
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                Text(Self.aide).font(.system(size: 12, weight: .medium)).lineLimit(1).fixedSize()
            }
            .foregroundStyle(Color.white.opacity(0.45))
            .opacity(m.aideCentre && Self.aideTient(g, v) ? 1 : 0)
            .animation(m.reduire || m.statique ? nil : .easeOut(duration: 0.3), value: m.aideCentre)
            .aspectIlot(m.aspect(ExtraIlot.pied, rang: 2), ancre: .leading)
            .accessibilityHidden(true)
            Spacer(minLength: 0)
        }
        .posee(Self.cadre(g, v))
    }
}

/// Le bouton « Dictées » du pied : les guillemets de Verbe et « Dictées » (30 pt, comme « Centre »).
struct BoutonPiedDictees: View {
    var action: () -> Void
    @State private var survol = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: "quote.opening").font(.system(size: 12, weight: .bold)).frame(width: 15)
                Text("Dictées").font(.system(size: 13, weight: .semibold)).lineLimit(1).fixedSize()
            }
            .foregroundStyle(.white)
            .padding(.leading, 9).padding(.trailing, 13)
            .frame(height: 30)
            .background(Capsule().fill(Color.white.opacity(survol ? 0.2 : 0.14)))
            .contentShape(Capsule())
        }
        .buttonStyle(AppuiIlot(echelle: 0.94))
        .onHover { survol = $0 }
        .accessibilityLabel("Ouvrir les dictées : chercher, copier, coller")
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
        case .dictees: return "Les dictées"
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
    /// Ce que le Centre montre (« Modifier ») : les identifiants, dans l'ordre ; nil = jamais modifié.
    var disposition: () -> [String]? = { Settings.ilotCentreBoutons }
    var enregistrerDisposition: ([String]) -> Void = { Settings.ilotCentreBoutons = $0 }
    /// Le minuteur (Réglages › Îlot) : éteint, un clic sur « 5 », « 10 » ou « 25 » dans le Centre l'allume, puis lance le minuteur.
    var minuteurActif: () -> Bool = { Settings.ilotMinuteur }
    var allumerMinuteur: () -> Void = { Settings.ilotMinuteur = true }
}

extension IlotControleur {
    /// Le volet de Réglages Système où l'on rend l'accès à Téléchargements (Confidentialité et sécurité › Fichiers et dossiers).
    static let reglagesFichiers = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")!

    /// Les boutons du Centre. Chacun réutilise ce qui existe (micro coupé, téléchargements, crochets de Claude, étagère, réunion) ; l'îlot
    /// reste ouvert (sauf pour aller au Terminal ou noter une réunion). Les autorisations se demandent ici, au premier clic, jamais avant.
    func agirCentre(_ a: ActionIlot) {
        switch a {
        case .centreMicro:
            couperOuRouvrirLeMicro(depuis: "le Centre")
        case .centreTelechargements:
            // allumer : macOS pose sa question à la première lecture du dossier (« Un instant… » jusqu'à la réponse) ; refusé, le bouton
            // revient sur « Éteint » et une ligne mène à Réglages Système
            moteur.avisCentre = nil
            telechargementsDemandesDuCentre = !moteur.telechargementsActifs
            reglerTelechargements(!moteur.telechargementsActifs)
        case .centreAvis:
            if moteur.avisCentre == .telechargementsRefuses { ouvrir(Self.reglagesFichiers) }
            moteur.avisCentre = nil
        case .centreClaude:
            // une session au travail : on la rejoint ; branché : le Terminal (ou l'app de la dernière session) ; sinon, on branche (les
            // crochets s'écrivent dans ~/.claude/settings.json, l'ancien gardé à côté en .verbe-sauvegarde, comme le bouton des Réglages)
            if let s = moteur.claude { moteur.fermer(); ramenerApp(s.app); return }
            if moteur.claudeBranche { moteur.fermer(); ramenerApp(moteur.dernierClaude?.app); return }
            moteur.avisCentre = nil
            do {
                try installationClaude.brancher()
                moteur.claudeBranche = true
                if !claudeSource.actif { reglagesCentre.allumerClaude(); activerClaude(true) }
                NotificationCenter.default.post(name: .verbeIlotReglagesRelus, object: nil)
            } catch let e as InstallationClaude.Echec {
                Log.ecrire("claude : branchement depuis le Centre impossible (\(e.phrase))")
                if case .ecriture = e { moteur.avisCentre = .claudeImpossible(ecriture: true) } else { moteur.avisCentre = .claudeImpossible(ecriture: false) }
            } catch {
                Log.ecrire("claude : branchement depuis le Centre impossible")
                moteur.avisCentre = .claudeImpossible(ecriture: true)
            }
            moteur.donneesChangees()
        case .centreReunion:
            moteur.fermer()
            surNoter(nil)
        case .etagereAllumer:
            reglagesCentre.allumerEtagere()
            activerEtagere(true)
            NotificationCenter.default.post(name: .verbeIlotReglagesRelus, object: nil)
        default: break
        }
    }

    /// Coupe le micro du Mac, ou le rouvre : le bouton Micro du Centre, et l'entrée du menu de Verbe (barre des menus), seul chemin
    /// quand l'îlot n'a pas d'encoche où s'ouvrir (écran externe, MacBook fermé). « Micro coupé » éteint dans les réglages : il s'allume
    /// d'abord (rien n'est demandé à macOS pour couper un micro).
    func couperOuRouvrirLeMicro(depuis origine: String) {
        if !micro.actif {
            reglagesCentre.allumerMicro()
            activerLeMicro(true)
            NotificationCenter.default.post(name: .verbeIlotReglagesRelus, object: nil)
        }
        if !basculerLeMicro() { Log.ecrire("micro coupé : \(origine) n'a pas pu basculer le micro (aucun micro, ou commande refusée)") }
        moteur.donneesChangees()
    }
    /// Le titre de l'entrée du menu de Verbe : ce qu'un clic fera.
    var titreMenuMicro: String { moteur.microCoupe ? "Rouvrir le micro" : "Couper le micro" }

    /// macOS a refusé l'accès au dossier Téléchargements (à la demande, ou plus tard dans Réglages Système) : le réglage s'éteint, le
    /// bouton du Centre revient sur « Éteint » et la ligne d'avis dit où le rendre. Demandé depuis le Centre, l'avis est posé même si
    /// le Centre s'est rangé entre-temps : il attend sa prochaine ouverture.
    func telechargementsRefuses() {
        let depuisLeCentre = moteur.centreOuvert || telechargementsDemandesDuCentre
        telechargementsDemandesDuCentre = false
        reglagesCentre.reglerTelechargements(false)
        Log.ecrire("téléchargements : accès au dossier refusé, réglage éteint")
        NotificationCenter.default.post(name: .verbeIlotReglagesRelus, object: nil)
        moteur.telechargementsActifs = false
        moteur.telechargementsAttente = false
        if depuisLeCentre { moteur.avisCentre = .telechargementsRefuses }
        moteur.donneesChangees()
    }
}
