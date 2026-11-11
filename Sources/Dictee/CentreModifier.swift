import AppKit
import SwiftUI
import DicteeCore

// « Modifier » le Centre (maquette design/maquettes/ilot-centre.html, étape 9), comme sur l'iPhone : les boutons tremblent, le « – » en
// retire un, la ligne du haut (« Ajouter : ») propose ce qui n'est pas montré, on les range en les glissant, « OK » enregistre. La hauteur
// de l'îlot ne change pas en entrant dans « Modifier » : les ajouts prennent la ligne de l'en-tête. La logique (ordre, ajout, retrait,
// identifiants rangés) est dans DicteeCore/DispositionCentre.swift ; les ronds et les cases dans CentreIlot.swift.
// Aussi ici : l'en-tête du Centre, la bande « Noter la réunion », et la ligne d'avis quand une autorisation est refusée.

/// Une ligne en haut du Centre quand ce qu'on vient de demander n'a pas pu se faire.
enum AvisCentre: Equatable {
    /// macOS a refusé l'accès au dossier Téléchargements : la ligne mène à Réglages Système (un clic).
    case telechargementsRefuses
    /// Les crochets de Claude Code n'ont pas pu être écrits (settings.json illisible, ou écriture refusée) : rien n'a été changé.
    case claudeImpossible(ecriture: Bool)

    var texte: String {
        switch self {
        case .telechargementsRefuses: return "Accès refusé : ouvre Réglages Système"
        case .claudeImpossible(let ecriture): return ecriture ? "Écriture impossible : rien n\u{2019}a changé" : "settings.json illisible : rien n\u{2019}a changé"
        }
    }
    /// Un clic sur la ligne fait quelque chose (ouvrir Réglages Système).
    var cliquable: Bool { self == .telechargementsRefuses }
    static let police: CGFloat = 12
    /// Le symbole (11 pt), l'écart (5 pt), le texte, le chevron (9 pt + 4).
    var largeur: CGFloat { 11 + 5 + MesureIlot.texte(texte, Self.police, .semibold) + (cliquable ? 13 : 0) }
}

extension IlotMoteur {
    /// « Modifier » : sur le Centre ou sur sa page Outils ; l'îlot reste ouvert (épinglé) le temps de ranger.
    func commencerEditionCentre() {
        guard courante == .centre || courante == .outils, !editionCentre else { return }
        epinglerLeCentre()
        avisCentre = nil
        debutAjouts = 0
        editionCentre = true
    }
    /// « OK » (ou le Centre qui se range) : les dispositions sont enregistrées (celle du Centre et celle des Outils).
    func finirEditionCentre() {
        guard editionCentre else { return }
        editionCentre = false
        surDispositionCentre(disposition)
        surDispositionOutils(dispositionOutils)
    }
    /// La disposition de la page où vit `e` (le Centre ou les Outils).
    private func modifier(_ e: ElementCentre, _ changer: (inout DispositionCentre) -> Bool) {
        guard editionCentre else { return }
        let fait = e.page == .outils ? changer(&dispositionOutils) : changer(&disposition)
        if fait { donneesChangees() }
    }
    func retirerDuCentre(_ e: ElementCentre) { modifier(e) { $0.retirer(e) } }
    func ajouterAuCentre(_ e: ElementCentre) { modifier(e) { $0.ajouter(e, disponible: disponibleDansLeCentre) } }
    /// Range un rond (ou une case) au rang voulu parmi ceux de son genre qui sont montrés.
    func rangerDansLeCentre(_ e: ElementCentre, versRang r: Int, parmi visibles: [ElementCentre]) { modifier(e) { $0.deplacer(e, versRang: r, parmi: visibles) } }
}

/// L'en-tête du Centre : « ‹ Vidéo » (ou l'étagère, ou « Centre »), ou la ligne d'avis ; « Reste ouvert » quand l'îlot est épinglé ;
/// « Outils › » (la 2e page) ; « Dictées » ; « Modifier ». Sur la page Outils : « ‹ Centre », « Reste ouvert », « Modifier ».
/// Dans « Modifier » : « Ajouter : » et les pastilles de ce qu'on peut ajouter (celles qui tiennent, puis « +N »), et « OK ».
struct EnteteCentre: View {
    @ObservedObject var m: IlotMoteur
    var largeur: CGFloat
    var page: PageCentre = .centre

    static let titreOK = "OK", titreModifier = "Modifier", titreOutils = "Outils"
    /// « Outils › » : 11, le mot, 4, le chevron (10,5 pt), 9.
    static var piluleOutils: CGFloat { 11 + MesureIlot.texte(titreOutils, 12.5, .semibold) + 4 + MesureIlot.symbole("chevron.right", 10.5, .bold) + 9 }
    /// La largeur d'une pilule de l'en-tête (11 pt de chaque côté du texte).
    static func pilule(_ t: String) -> CGFloat { MesureIlot.texte(t, 12.5, .semibold) + 22 }
    static let libelleAjouter = "Ajouter :"
    /// Une pastille « + Rappel » : 8 pt, le « + » (11), 5, le nom, 11.
    static func pastille(_ e: ElementCentre) -> CGFloat { MesureIlot.texte(e.nom, 12.5, .semibold) + 35 }
    /// « +2 › » : les pastilles suivantes (le texte, 3, le chevron de 9 pt, 6 et 6 de marge).
    static func marque(_ n: Int) -> CGFloat { MesureIlot.texte("+\(n)", 12, .semibold) + 3 + 9 + 12 }
    /// « ‹ » : revenir aux premières pastilles.
    static let retour: CGFloat = 26
    /// Ce qu'on peut ajouter, la première pastille montrée, et combien tiennent dans la ligne (après « Ajouter : », avant « OK »).
    static func ajouts(_ m: IlotMoteur, largeur: CGFloat, page: PageCentre = .centre) -> (tous: [ElementCentre], debut: Int, montres: Int) {
        let tous = m.dispositionDe(page).aAjouter(disponible: m.disponibleDansLeCentre)
        let debut = m.debutAjouts < tous.count ? m.debutAjouts : 0
        let place = largeur - pilule(titreOK) - 8 - MesureIlot.texte(libelleAjouter, 12, .medium) - 6 - (debut > 0 ? retour + 6 : 0)
        let suite = tous.dropFirst(debut)
        let n = DispositionCentre.pastillesQuiTiennent(suite.map { Double(pastille($0)) }, place: Double(place), ecart: 6, marque: { Double(marque($0)) })
        // au moins une pastille, même dans une ligne trop courte
        return (tous, debut, max(n, suite.isEmpty ? 0 : 1))
    }
    /// La pilule « Dictées » (les guillemets de 10 pt et 4 pt avant le mot).
    static var piluleDictees: CGFloat { pilule("Dictées") + MesureIlot.symbole("quote.opening", 10, .bold) + 4 }
    /// La place de la ligne d'avis : tout l'en-tête sauf « Modifier » (« Reste ouvert » et « Dictées » s'effacent devant elle, le temps
    /// qu'on la lise : les Dictées restent à un point de page ou un défilement ; « Outils › » aussi s'il ne tient plus à côté).
    static func placeAvis(largeur: CGFloat) -> CGFloat { largeur - pilule(titreModifier) - 8 }
    /// « Outils › » tient-il dans l'en-tête du Centre ? Toujours, sauf à côté d'une ligne d'avis trop longue (trois écarts de 8 pt).
    static func outilsTient(_ m: IlotMoteur, largeur: CGFloat) -> Bool {
        guard let a = m.avisCentre else { return true }
        return a.largeur + piluleOutils + pilule(titreModifier) + 24 <= largeur
    }

    var body: some View {
        let ed = m.editionCentre
        HStack(spacing: 8) {
            if ed {
                ajouts
            } else if page == .outils {
                PiluleCentre(titre: "Centre", retour: true, etiquette: "Revenir au Centre") { m.allerA(.centre) }
            } else if let a = m.avisCentre {
                avis(a)
            } else if let nom = m.nomPremiereCarte, let premiere = m.cartes.first {
                PiluleCentre(titre: nom, retour: true, etiquette: "Revenir à : \(nom)") { m.allerA(premiere) }
            } else if m.miseEnPageCentre.etagereEnHaut {
                // les fichiers de l'étagère sont en haut : leur titre et leur nombre ouvrent la carte (maquette ilot-etagere-rapide.html)
                TitreEtagereCentre(m: m)
            } else {
                Text("Centre").font(.system(size: 13.5, weight: .semibold)).foregroundStyle(CouleursIlot.encre2).padding(.leading, 2)
            }
            Spacer(minLength: 0)
            if !ed, m.avisCentre == nil || page == .outils {
                HStack(spacing: 4) {
                    Image(systemName: "pin.fill").font(.system(size: 10, weight: .semibold))
                    Text("Reste ouvert").font(.system(size: 11.5, weight: .semibold))
                }
                .foregroundStyle(Color.white.opacity(0.5))
                .opacity(m.epingle ? 1 : 0)
                .animation(m.reduire || m.statique ? nil : .easeOut(duration: 0.25), value: m.epingle)
                .accessibilityHidden(!m.epingle)
            }
            // « Outils › » : toujours, sauf si la ligne d'avis (passagère) ne lui laisse pas la place, mesurée (les points de page et le
            // défilement mènent aussi aux Outils)
            if !ed, page == .centre, Self.outilsTient(m, largeur: largeur) {
                PiluleCentre(titre: Self.titreOutils, suite: true, etiquette: "Les outils : garder éveillé, presse-papiers, reformuler, notes") { m.allerA(.outils) }
            }
            if ed {
                PiluleCentre(titre: Self.titreOK, plein: true, etiquette: "Terminer : enregistrer le Centre") { m.finirEditionCentre() }
            } else {
                // les Dictées (l'ancien panneau de la barre des menus), la dernière carte de la pile
                if m.avisCentre == nil {
                    PiluleCentre(titre: "Dictées", symbole: "quote.opening", etiquette: "Les dictées : chercher, copier, coller") { m.allerA(.dictees) }
                }
                PiluleCentre(titre: Self.titreModifier, etiquette: "Modifier le Centre : ajouter, retirer, ranger les boutons") { m.commencerEditionCentre() }
            }
        }
        .frame(height: PlanCentre.entete)
    }

    /// « Ajouter : » et les pastilles. Un rond de plus quand la rangée est pleine (cinq) : la pastille est là, éteinte.
    private var ajouts: some View {
        let (tous, debut, n) = Self.ajouts(m, largeur: largeur, page: page)
        let reste = tous.count - debut - n
        return HStack(spacing: 6) {
            Text(Self.libelleAjouter).font(.system(size: 12, weight: .medium)).foregroundStyle(Color.white.opacity(0.5)).fixedSize()
            if debut > 0 {
                Button { m.debutAjouts = 0 } label: {
                    Image(systemName: "chevron.left").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                        .frame(width: Self.retour, height: 26).background(Capsule().fill(Color.white.opacity(0.14))).contentShape(Capsule())
                }
                .buttonStyle(AppuiIlot(echelle: 0.9))
                .accessibilityLabel("Revenir aux premiers à ajouter")
            }
            ForEach(Array(tous.dropFirst(debut).prefix(n)), id: \.self) { e in
                PastilleAjout(element: e, possible: m.dispositionDe(page).peutAjouter(e, disponible: m.disponibleDansLeCentre)) { m.ajouterAuCentre(e) }
            }
            if reste > 0 {
                Button { m.debutAjouts = debut + n } label: {
                    HStack(spacing: 3) {
                        Text("+\(reste)").font(.system(size: 12, weight: .semibold)).fixedSize()
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).frame(width: 9)
                    }
                    .foregroundStyle(Color.white.opacity(0.7))
                    .padding(.horizontal, 6).frame(height: 26).contentShape(Rectangle())
                }
                .buttonStyle(AppuiIlot(echelle: 0.9))
                .accessibilityLabel("\(reste) autres à ajouter : les montrer")
            }
            if tous.isEmpty {
                Text("tout est là").font(.system(size: 12, weight: .medium)).foregroundStyle(Color.white.opacity(0.35)).fixedSize()
            }
        }
    }

    @ViewBuilder private func avis(_ a: AvisCentre) -> some View {
        let ligne = HStack(spacing: 5) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10.5, weight: .semibold)).frame(width: 11)
            Text(a.texte).font(.system(size: AvisCentre.police, weight: .semibold)).lineLimit(1).fixedSize()
            if a.cliquable { Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).padding(.leading, -1) }
        }
        .foregroundStyle(CouleursIlot.ambre)
        if a.cliquable {
            Button { m.epinglerLeCentre(); m.surAction(.centreAvis) } label: { ligne.contentShape(Rectangle()) }
                .buttonStyle(AppuiIlot(echelle: 0.96))
                .accessibilityLabel("Accès à Téléchargements refusé : ouvrir Réglages Système, Fichiers et dossiers")
        } else {
            ligne.accessibilityElement(children: .combine)
        }
    }
}

/// « + Rappel » : une pastille de la ligne « Ajouter : ».
struct PastilleAjout: View {
    var element: ElementCentre
    var possible: Bool
    var action: () -> Void
    @State private var survol = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "plus").font(.system(size: 10, weight: .bold)).frame(width: 11)
                Text(element.nom).font(.system(size: 12.5, weight: .semibold)).lineLimit(1).fixedSize()
            }
            .foregroundStyle(.white)
            .padding(.leading, 8).padding(.trailing, 11)
            .frame(height: 26)
            .background(Capsule().fill(Color.white.opacity(survol && possible ? 0.22 : 0.14)))
            .contentShape(Capsule())
            .opacity(possible ? 1 : 0.4)
        }
        .buttonStyle(AppuiIlot(echelle: 0.92))
        .disabled(!possible)
        .onHover { survol = $0 }
        .accessibilityLabel(possible ? "Ajouter « \(element.nom) » au Centre" : "« \(element.nom) » : la rangée est pleine, retire d\u{2019}abord un bouton")
    }
}

/// « Étagère 3 › » dans l'en-tête du Centre, quand les fichiers sont en haut : un clic ouvre la carte Étagère.
struct TitreEtagereCentre: View {
    @ObservedObject var m: IlotMoteur
    @State private var survol = false
    var body: some View {
        Button { m.epinglerLeCentre(); m.ouvrirEtagere() } label: {
            HStack(spacing: 7) {
                Image(systemName: "tray").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color(hex: 0x5EB0FF))
                Text("Étagère").font(.system(size: 13.5, weight: .semibold)).foregroundStyle(.white).lineLimit(1).fixedSize()
                Text("\(m.etagere.count)").font(.system(size: 11.5, weight: .bold).monospacedDigit()).foregroundStyle(.white)
                    .padding(.horizontal, 5).frame(minWidth: 18, minHeight: 18).background(Capsule().fill(Color.white.opacity(0.2)))
                Image(systemName: "chevron.right").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Color.white.opacity(0.5))
            }
            .padding(.horizontal, 4).frame(height: 26)
            .background(Capsule().fill(Color.white.opacity(survol ? 0.1 : 0)))
            .contentShape(Capsule())
        }
        .buttonStyle(AppuiIlot(echelle: 0.95))
        .onHover { survol = $0 }
        .accessibilityLabel("Étagère, \(EtagereIlot.resume(m.etagere.count)) : l\u{2019}ouvrir")
    }
}

/// La bande « Noter la réunion » (maquette : 40 pt, toute la largeur) : Verbe écrit tout ce qui se dit. Pendant la réunion l'îlot
/// s'efface (comme pendant une dictée) : on l'arrête par ⌥⌘N ou la fenêtre Réunions, comme avant.
struct BandeReunion: View {
    @ObservedObject var m: IlotMoteur
    @State private var survol = false
    static let titre = "Noter la réunion", sousTitre = "Verbe écrit tout ce qui se dit"
    /// Le point (16), 10, le titre, au moins 12, le sous-titre ; 14 et 16 de marge.
    static var largeurUtile: CGFloat { 14 + 16 + 10 + MesureIlot.texte(titre, 13.5, .semibold) + 12 + MesureIlot.texte(sousTitre, 12, .medium) + 16 }

    var body: some View {
        let ed = m.editionCentre
        Button { if !ed { m.epinglerLeCentre(); m.surAction(.centreReunion) } } label: {
            HStack(spacing: 10) {
                Circle().strokeBorder(CouleursIlot.rouge, lineWidth: 1.8)
                    .overlay(Circle().fill(CouleursIlot.rouge).padding(4.2))
                    .frame(width: 16, height: 16)
                Text(Self.titre).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(.white).lineLimit(1).fixedSize()
                Spacer(minLength: 12)
                Text(Self.sousTitre).font(.system(size: 12, weight: .medium)).foregroundStyle(Color.white.opacity(0.5)).lineLimit(1).fixedSize()
            }
            .padding(.leading, 14).padding(.trailing, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Capsule().fill(Color.white.opacity(survol && !ed ? 0.15 : 0.1)))
            .contentShape(Capsule())
        }
        .buttonStyle(AppuiIlot(echelle: ed ? 1 : 0.97))
        .onHover { survol = $0 }
        .tremblement(ed && (m.statique || !m.reduire), amplitude: 0.45, decale: false, fige: m.statique)
        .overlay(alignment: .topLeading) {
            if ed { BadgeRetirer(nom: "Noter la réunion") { m.retirerDuCentre(.reunion) }.offset(x: -6, y: -6) }
        }
        .accessibilityLabel("Noter la réunion : Verbe écrit tout ce qui se dit")
    }
}

/// Le tremblement de « Modifier » (maquette : ±1,4° en 0,26 s, aller-retour ; deux voisins en opposition). Il n'existe que pendant
/// « Modifier » (une horloge d'écran, en pause le reste du temps) ; « Réduire les animations » : pas de tremblement, juste les « – ».
/// Dans un rendu figé : une inclinaison fixe, pour qu'on voie l'état.
struct TremblementIlot: ViewModifier {
    var actif: Bool
    var amplitude: Double
    var decale: Bool
    var fige: Bool
    static let periode: Double = 0.52

    func body(content: Content) -> some View {
        if !actif {
            content
        } else if fige {
            content.rotationEffect(.degrees(decale ? amplitude : -amplitude))
        } else {
            TimelineView(.animation) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                content.rotationEffect(.degrees(amplitude * sin(2 * .pi * t / Self.periode + (decale ? .pi : 0))))
            }
        }
    }
}

extension View {
    func tremblement(_ actif: Bool, amplitude: Double, decale: Bool, fige: Bool) -> some View {
        modifier(TremblementIlot(actif: actif, amplitude: amplitude, decale: decale, fige: fige))
    }
}
