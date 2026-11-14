import AppKit
import SwiftUI
import DicteeCore

// Les écrans de « Tes apps » (maquette design/maquettes/ilot-apps.html) : la liste des apps, le détail d'une app (brancher, ou branchée),
// les Nouveautés, l'aile et le bandeau. Même langue que le reste de l'îlot : pilules `PiluleCentre` (en-tête) et `PiluleOutil`, boîtes à
// 14 pt de rayon et fond blanc à 7 %, textes mesurés (Core Text) ; une ligne cliquable = un fond qui prend le clic, le contenu par-dessus
// qui n'en prend aucun, les boutons posés en frères. Les hauteurs viennent de DicteeCore (MesuresApps, EtatAppsIlot.blocs) : la forme les
// épouse.

// MARK: - les mesures (dessin, forme, essais)

@MainActor
enum PlanApps {
    static let haut = CGFloat(MesuresApps.haut), entete = CGFloat(MesuresApps.entete), bas = CGFloat(MesuresApps.bas)
    static func zone(_ g: GrilleIlot, _ v: VueIlot) -> CGRect { g.zoneCarte(v, haut: haut, bas: bas) }
    static func cadreEntete(_ g: GrilleIlot, _ v: VueIlot) -> CGRect { let z = zone(g, v); return CGRect(x: z.minX, y: z.minY, width: z.width, height: entete) }
    /// « ‹ Centre » / « ‹ Tes apps » : le mot de la pilule de retour de chaque carte (son parent fixe).
    static func motRetour(_ v: VueIlot) -> String { NavigationIlot.parentFixe(v, premiere: nil).flatMap(NavigationIlot.nom) ?? "Centre" }
    static func pointRetour(_ g: GrilleIlot, _ v: VueIlot) -> CGPoint {
        let e = cadreEntete(g, v); return CGPoint(x: e.minX + PiluleCentre.largeur(motRetour(v), retour: true) / 2, y: e.midY)
    }

    // la liste « Tes apps » : deux onglets, puis les apps de l'onglet
    static let logoListe: CGFloat = 30, retraitTexte: CGFloat = 50
    static func cadreOnglets(_ g: GrilleIlot) -> CGRect {
        let z = zone(g, .apps)
        return CGRect(x: z.minX, y: z.minY + entete + CGFloat(MesuresApps.ecartOnglets), width: z.width, height: CGFloat(MesuresApps.onglets))
    }
    /// Un onglet : 14 pt de chaque côté du nom (et 6 + 6 pour le point bleu des nouveautés non lues), 6 pt entre les deux.
    static func largeurOnglet(_ o: AppBranchee.Groupe) -> CGFloat { MesureIlot.texte(o.nom, 12.5, .semibold) + 28 + 12 }
    static let ecartOnglets: CGFloat = 6
    static func pointOnglet(_ g: GrilleIlot, _ o: AppBranchee.Groupe) -> CGPoint {
        let c = cadreOnglets(g)
        var x = c.minX
        for x0 in AppBranchee.Groupe.allCases {
            if x0 == o { return CGPoint(x: x + largeurOnglet(x0) / 2, y: c.midY) }
            x += largeurOnglet(x0) + ecartOnglets
        }
        return CGPoint(x: c.minX, y: c.midY)
    }
    static func cadreBoite(_ g: GrilleIlot, _ o: AppBranchee.Groupe) -> CGRect {
        let c = cadreOnglets(g)
        return CGRect(x: c.minX, y: c.maxY + CGFloat(MesuresApps.ecartBoite), width: c.width, height: CGFloat(MesuresApps.ligne) * CGFloat(o.apps.count))
    }
    /// La ligne d'une app, dans la page de son onglet (l'essai ouvre l'onglet avant d'y cliquer).
    static func cadreLigne(_ g: GrilleIlot, _ a: AppBranchee) -> CGRect {
        let b = cadreBoite(g, a.groupe), i = CGFloat(a.groupe.apps.firstIndex(of: a) ?? 0)
        return CGRect(x: b.minX, y: b.minY + CGFloat(MesuresApps.ligne) * i, width: b.width, height: CGFloat(MesuresApps.ligne))
    }
    /// Le bouton à droite d'une ligne (« Brancher », « ● Branché › »).
    static func largeurBouton(_ b: BoutonLigneApp) -> CGFloat {
        switch b {
        case .brancher: return MesureIlot.texte(b.titre, 12.5, .semibold) + 26
        case .enCours: return MesureIlot.texte(b.titre, 12, .semibold) + 20
        default: return 10 + 6 + 5 + MesureIlot.texte(b.titre, 12, .semibold) + 4 + MesureIlot.symbole("chevron.right", 9.5, .bold) + 9
        }
    }
    static func pointBouton(_ g: GrilleIlot, _ a: AppBranchee, _ b: BoutonLigneApp) -> CGPoint {
        let l = cadreLigne(g, a); return CGPoint(x: l.maxX - 10 - largeurBouton(b) / 2, y: l.midY)
    }
    /// La place du sous-titre d'une ligne (entre le logo et le bouton).
    static func placeSousTitre(_ g: GrilleIlot, _ b: BoutonLigneApp) -> CGFloat { zone(g, .apps).width - retraitTexte - 10 - largeurBouton(b) - 10 }
    static var largeurPiluleNouveautes: CGFloat { PiluleCentre.largeur("Nouveautés") + 10 }

    // le détail : les blocs, posés les uns sous les autres
    static func cadresBlocs(_ g: GrilleIlot, _ e: EtatAppsIlot) -> [(bloc: BlocDetailApp, cadre: CGRect)] {
        let z = zone(g, .appsDetail)
        var y = z.minY + entete, avant: BlocDetailApp? = nil
        var r: [(BlocDetailApp, CGRect)] = []
        for b in e.blocs {
            y += CGFloat(EtatAppsIlot.ecart(avant: b, apres: avant))
            r.append((b, CGRect(x: z.minX, y: y, width: z.width, height: CGFloat(b.hauteur))))
            y += CGFloat(b.hauteur); avant = b
        }
        return r
    }
    static func cadreBloc(_ g: GrilleIlot, _ e: EtatAppsIlot, _ p: (BlocDetailApp) -> Bool) -> CGRect? { cadresBlocs(g, e).first { p($0.bloc) }?.cadre }
    static let largeurColler: CGFloat = PiluleOutil.largeur("Collée", icone: "checkmark", padding: 14)
    static func pointColler(_ g: GrilleIlot, _ e: EtatAppsIlot) -> CGPoint? {
        cadreBloc(g, e) { $0 == .champCle }.map { CGPoint(x: $0.maxX - largeurColler / 2, y: $0.midY) }
    }
    /// « Ouvrir la page ↗ » à droite du libellé du champ.
    static func pointPageCle(_ g: GrilleIlot, _ e: EtatAppsIlot) -> CGPoint? {
        cadreBloc(g, e) { $0 == .libelleCle }.map { CGPoint(x: $0.maxX - PiluleOutil.largeur("Ouvrir la page", icone: "arrow.up.right", taille: 12, padding: 10) / 2, y: $0.midY) }
    }
    static func pointBouton(_ g: GrilleIlot, _ e: EtatAppsIlot) -> CGPoint? { cadreBloc(g, e) { $0 == .bouton }.map { CGPoint(x: $0.midX, y: $0.midY) } }
    static func pointChoix(_ g: GrilleIlot, _ e: EtatAppsIlot, _ id: String) -> CGPoint? {
        cadreBloc(g, e) { if case .choix(let c) = $0 { return c.id == id }; return false }.map { CGPoint(x: $0.minX + 60, y: $0.midY) }
    }
    static func pointGesteErreur(_ g: GrilleIlot, _ e: EtatAppsIlot) -> CGPoint? {
        guard let (b, c) = cadresBlocs(g, e).first(where: { if case .erreur = $0.bloc { return true }; return false }), case .erreur(_, let geste) = b,
              let t = geste.titre else { return nil }
        return CGPoint(x: c.maxX - 10 - PiluleOutil.largeur(t, taille: 12, padding: 11) / 2, y: c.maxY - 8 - 13)
    }
    static let titreDebrancher = "Débrancher"
    static func pointDebrancher(_ g: GrilleIlot, _ e: EtatAppsIlot) -> CGPoint? {
        cadreBloc(g, e) { $0 == .pied }.map { CGPoint(x: $0.maxX - PiluleOutil.largeur(titreDebrancher, padding: 14) / 2, y: $0.midY) }
    }
    static func pointConfirmer(_ g: GrilleIlot, _ e: EtatAppsIlot) -> CGPoint? {
        cadreBloc(g, e) { $0 == .confirmation }.map { CGPoint(x: $0.maxX - 12 - PiluleOutil.largeur(titreDebrancher, padding: 14) / 2, y: $0.maxY - 12 - 15) }
    }
    static func pointChanger(_ g: GrilleIlot, _ e: EtatAppsIlot, _ genre: InfoApp.Genre) -> CGPoint? {
        cadreBloc(g, e) { if case .info(let i) = $0 { return i.genre == genre }; return false }
            .map { CGPoint(x: $0.maxX - 10 - PiluleOutil.largeur("Changer", taille: 12, padding: 11) / 2, y: $0.midY) }
    }

    // les Nouveautés
    static func cadresNouveautes(_ g: GrilleIlot, _ e: EtatAppsIlot) -> [(section: PlanNouveautes.Section, titre: CGRect, lignes: [CGRect])] {
        let z = zone(g, .appsNouveautes)
        var y = z.minY + entete + CGFloat(MesuresApps.ecartNouveautes)
        var r: [(PlanNouveautes.Section, CGRect, [CGRect])] = []
        for (i, s) in PlanNouveautes.sections(e.actuelles).enumerated() {
            if i > 0 { y += CGFloat(PlanNouveautes.ecart) }
            let t = CGRect(x: z.minX, y: y, width: z.width, height: CGFloat(PlanNouveautes.titre)); y += t.height
            var ls: [CGRect] = []
            for _ in s.lignes { ls.append(CGRect(x: z.minX, y: y, width: z.width, height: CGFloat(PlanNouveautes.ligne))); y += CGFloat(PlanNouveautes.ligne) }
            r.append((s, t, ls))
        }
        return r
    }
    static func pointOuvrir(_ g: GrilleIlot, _ e: EtatAppsIlot, _ id: String) -> CGPoint? {
        for (s, _, ls) in cadresNouveautes(g, e) { if let i = s.lignes.firstIndex(where: { $0.id == id }) { return CGPoint(x: ls[i].maxX - largeurOuvrir / 2 - 4, y: ls[i].midY) } }
        return nil
    }
    static var largeurOuvrir: CGFloat { PiluleOutil.largeur("Ouvrir", icone: "arrow.up.right", taille: 12, padding: 9) }
    static let titreToutLu = "Tout marquer lu"

    /// Les textes de l'interface (pas ce que disent les apps : un objet de mail peut finir en « … ») qui ne tiendraient pas à leur place,
    /// pour une zone de `W` pt (la carte à la largeur de l'îlot) : vide, rien n'est coupé. Mesures Core Text, mêmes polices que le dessin.
    static func debordements(_ e: EtatAppsIlot, largeur W: CGFloat) -> [String] {
        var r: [String] = []
        func tient(_ l: CGFloat, _ place: CGFloat, _ quoi: String) { if l > place + 0.5 { r.append("\(quoi) : \(Int(l)) pt pour \(Int(place))") } }
        func t(_ s: String, _ z: CGFloat, _ p: NSFont.Weight) -> CGFloat { MesureIlot.texte(s, z, p) }
        let retour = PiluleCentre.largeur("Centre", retour: true), retourApps = PiluleCentre.largeur("Tes apps", retour: true)
        // la liste
        tient(retour + 10 + t("Tes apps", 13.5, .bold) + 10 + largeurPiluleNouveautes, W, "en-tête de Tes apps")
        tient(AppBranchee.Groupe.allCases.map(largeurOnglet).reduce(0, +) + ecartOnglets, W, "onglets de Tes apps")
        let boite = W
        for a in AppBranchee.allCases {
            let l = e.ligne(a)
            let place = boite - retraitTexte - 10 - largeurBouton(l.bouton) - 10
            tient(t(l.sousTitre, 12, .medium), place, "ligne \(a.nom)")
            tient(t(a.nom, 13.5, .semibold), place, "nom \(a.nom)")
        }
        // le détail
        if let a = e.detail {
            let pastille = e.parcours == nil ? (e.etat(a).pastille.map { 11 + t($0.texte, 12, .semibold) } ?? 0) : 0
            tient(retourApps + 10 + 22 + 7 + t(e.titreDetail, 13.5, .bold) + 10 + pastille, W, "en-tête du détail")
            for b in e.blocs {
                switch b {
                case .libelleCle: tient(t(e.parcours?.champ?.libelle ?? "", 12.5, .semibold) + 8 + PiluleOutil.largeur("Ouvrir la page", icone: "arrow.up.right", taille: 12, padding: 10), W, "libellé de la clé")
                case .champCle:
                    // l'exemple, et la forme la plus longue d'une saisie (la clé masquée : 4 + 8 + 4 ; l'adresse d'une boutique au nom long)
                    let ch = e.parcours?.champ
                    tient(MesureIlot.texte(ch?.exemple ?? "", 13, .medium) + 24, W - 8 - largeurColler, "exemple du champ")
                    // une clé masquée (le préfixe le plus long, huit points, quatre caractères larges) ; une adresse vient de Hugues : coupée au milieu
                    if ch?.masque == true { tient(MesureIlot.texte("rk_live_\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}WWWW", 13, .medium) * 1.15 + 24, W - 8 - largeurColler, "clé collée") }
                case .aideCle:
                    if let x = e.parcours?.champ?.aide { tient(t(x.debut, 11.5, .medium) + t(x.fort, 11.5, .semibold) + t(x.fin, 11.5, .medium), W, "aide de la clé") }
                case .valide(let v): tient(MesureIlot.symbole("checkmark", 11, .bold) + 7 + t(v, 12.5, .semibold) + 24, W, "clé valide")
                case .question: tient(t(e.parcours?.question ?? "", 12.5, .semibold) + 6 + 22 + 6 + 30 + 6 + 22, W, "question")
                case .erreur(let x, let g):
                    let place = W - 20 - MesureIlot.symbole("exclamationmark.triangle.fill", 12) - 9
                    if MesureIlot.lignes(x, 12, .medium, largeur: place) > 2 { r.append("erreur sur plus de deux lignes : \(x)") }
                    if let t = g.titre { tient(PiluleOutil.largeur(t, taille: 12, padding: 11), W - 20, "geste « \(t) »") }
                case .info(let i):
                    let fin: CGFloat = i.genre == .cle ? 8 + MesureIlot.texte(i.valeur ?? "", 12, .medium) : (i.changer ? 8 + PiluleOutil.largeur("Changer", taille: 12, padding: 11) : 0)
                    // la valeur (le nom d'une base) vient de l'app : on ne mesure que le libellé
                    tient(20 + 18 + 9 + t(i.libelle, 13, .medium) + fin, W, "ligne « \(i.libelle) »")
                case .pied: tient(t(a.notePied, 11.5, .medium) + 10 + PiluleOutil.largeur(titreDebrancher, padding: 14), W, "pied du détail")
                case .confirmation:
                    tient(t("Débrancher \(a.nom)\u{00A0}?", 13.5, .bold), W - 24, "titre de la confirmation")
                    let phrase = a.demandeUneCle ? "Les nouveautés s\u{2019}arrêtent et la clé est effacée de ce Mac. Tu peux rebrancher quand tu veux."
                                                 : "Les nouveautés s\u{2019}arrêtent. Tu peux rebrancher quand tu veux."
                    if MesureIlot.lignes(phrase, 12, .medium, largeur: W - 24) > 2 { r.append("phrase de la confirmation sur plus de deux lignes") }
                case .rendezVous(let ev):
                    if let ev, ev.lien != nil { tient(MesureIlot.boutons([.init(titre: "Rejoindre", icone: "video.fill"), .init(titre: "Noter la réunion", icone: "record.circle")], memeLargeur: true), W, "boutons du rendez-vous") }
                    else if ev == nil { tient(t("Rien d\u{2019}ici 12 h dans ton calendrier", 12.5, .medium), W, "rendez-vous absent") }
                case .bouton:
                    tient(t(e.parcours?.titreBouton ?? "", 13.5, .semibold) + 40, W, "grand bouton")
                    tient(t(e.parcours?.titreEnCours ?? "", 13.5, .semibold) + 40 + 24, W, "grand bouton en attente")
                case .choix: break
                }
            }
        }
        // les Nouveautés : l'en-tête, et la fin fixe de chaque ligne (l'heure, « Ouvrir »)
        tient(retourApps + 10 + t("Nouveautés", 13.5, .bold) + 10 + PiluleCentre.largeur(titreToutLu), W, "en-tête des Nouveautés")
        tient(6 + 8 + 6 + 8 + 60 + 8 + 40 + 8 + MesureIlot.texte("00:00", 11.5, .medium, chiffres: true) + 8 + largeurOuvrir + 8, W, "ligne des Nouveautés")
        return r
    }
}

// MARK: - un logo

struct LogoApp: View {
    var app: AppBranchee
    var cote: CGFloat
    var body: some View {
        Image(nsImage: LogosApps.image(app)).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            .frame(width: cote, height: cote)
            .accessibilityHidden(true)
    }
}

/// L'en-tête d'une carte : « ‹ X », le logo et le titre, puis ce qui va à droite.
private struct EnteteApps<Droite: View>: View {
    @ObservedObject var m: IlotMoteur
    var v: VueIlot
    var app: AppBranchee?
    var titre: String
    @ViewBuilder var droite: () -> Droite
    var body: some View {
        let mot = PlanApps.motRetour(v)
        HStack(spacing: 10) {
            PiluleCentre(titre: mot, retour: true, etiquette: "Revenir : \(mot)") { m.revenir() }
                .frame(width: PiluleCentre.largeur(mot, retour: true))
            HStack(spacing: 7) {
                if let app { LogoApp(app: app, cote: 22) }
                Text(titre).font(.system(size: 13.5, weight: .bold)).foregroundStyle(.white).lineLimit(1).fixedSize()
            }
            .allowsHitTesting(false)
            Spacer(minLength: 0)
            droite()
        }
        .frame(height: PlanApps.entete)
    }
}

/// Le fond d'une carte : son vide ne range pas l'îlot (on visait un bouton).
private struct FondCarteApps: View {
    @ObservedObject var m: IlotMoteur
    var v: VueIlot
    var g: GrilleIlot
    var body: some View {
        Color.clear.contentShape(Rectangle()).onTapGesture {}
            .allowsHitTesting(m.courante == v)
            .accessibilityHidden(true)
            .posee(CGRect(x: -g.corps(v), y: g.barre, width: 2 * g.corps(v), height: max(0, g.hauteur(v) - g.barre)))
    }
}

// MARK: - la liste « Tes apps »

struct CarteApps: View {
    @ObservedObject var m: IlotMoteur
    var g: GrilleIlot

    var body: some View {
        let v = VueIlot.apps
        let e = m.apps
        ZStack(alignment: .topLeading) {
            FondCarteApps(m: m, v: v, g: g)
            EnteteApps(m: m, v: v, app: nil, titre: "Tes apps") {
                if e.aDesNouveautes {
                    BoutonNouveautes(nonLues: !e.nonLues.isEmpty) { m.surAction(.apps(.nouveautes)) }
                }
            }
            .posee(PlanApps.cadreEntete(g, v), m.aspect(v, rang: 0), ancre: .topLeading)
            OngletsApps(m: m, e: e)
                .posee(PlanApps.cadreOnglets(g), m.aspect(v, rang: 1), ancre: .topLeading, .leading)
            VStack(spacing: 0) {
                ForEach(Array(e.groupe.apps.enumerated()), id: \.element) { i, a in
                    if i > 0 { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1).padding(.leading, PlanApps.retraitTexte).allowsHitTesting(false) }
                    LigneTesApps(m: m, l: e.ligne(a)).frame(height: CGFloat(MesuresApps.ligne) - (i > 0 ? 1 : 0))
                }
            }
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.07)).allowsHitTesting(false))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .posee(PlanApps.cadreBoite(g, e.groupe), m.aspect(v, rang: 2), ancre: .top)
        }
        .frame(width: IlotMoteur.largeur, height: IlotMoteur.hauteurMax, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tes apps")
    }
}

/// « Au quotidien » et « Vente » : deux onglets (sept apps ne tiennent pas dans une carte). L'onglet montré est blanc ; un point bleu
/// dit qu'une app de l'autre onglet a une nouveauté non lue.
private struct OngletsApps: View {
    @ObservedObject var m: IlotMoteur
    var e: EtatAppsIlot
    var body: some View {
        HStack(spacing: PlanApps.ecartOnglets) {
            ForEach(AppBranchee.Groupe.allCases, id: \.self) { o in
                let choisi = e.groupe == o
                let nonLu = e.toutes.contains { $0.app.groupe == o && e.nonLues.contains($0.id) }
                Button { m.surAction(.apps(.groupe(o))) } label: {
                    HStack(spacing: 6) {
                        Text(o.nom).font(.system(size: 12.5, weight: .semibold)).lineLimit(1).fixedSize()
                        Circle().fill(nonLu && !choisi ? CouleursIlot.bleu : .clear).frame(width: 6, height: 6)
                    }
                    .foregroundStyle(choisi ? Color.black : Color.white.opacity(0.75))
                    .padding(.leading, 14).padding(.trailing, 8)
                    .frame(width: PlanApps.largeurOnglet(o), height: CGFloat(MesuresApps.onglets))
                    .background(Capsule().fill(choisi ? Color.white : Color.white.opacity(0.1)))
                    .contentShape(Capsule())
                }
                .buttonStyle(AppuiIlot(echelle: 0.95))
                .accessibilityLabel(o.nom + (nonLu ? ", des nouveautés non lues" : ""))
                .accessibilityAddTraits(choisi ? [.isButton, .isSelected] : .isButton)
            }
            Spacer(minLength: 0)
        }
    }
}

/// « Nouveautés » en haut à droite de « Tes apps » (un point bleu s'il y a du non lu).
private struct BoutonNouveautes: View {
    var nonLues: Bool
    var action: () -> Void
    var body: some View {
        PiluleCentre(titre: "Nouveautés", etiquette: nonLues ? "Nouveautés, dont des non lues" : "Nouveautés", action: action)
            .overlay(alignment: .topTrailing) { if nonLues { Circle().fill(CouleursIlot.bleu).frame(width: 8, height: 8).offset(x: 1, y: -1).allowsHitTesting(false) } }
            .padding(.trailing, 10)
            .frame(width: PlanApps.largeurPiluleNouveautes, alignment: .leading)
    }
}

private struct LigneTesApps: View {
    @ObservedObject var m: IlotMoteur
    var l: LigneApp
    @State private var survol = false
    private var action: ActionApps {
        switch l.bouton {
        case .brancher: return .brancher(l.app)
        default: return .detail(l.app)
        }
    }
    var body: some View {
        ZStack(alignment: .trailing) {
            Rectangle().fill(Color.white.opacity(survol ? 0.05 : 0.001)).contentShape(Rectangle())
                .onTapGesture { if l.bouton != .enCours { m.surAction(.apps(action)) } }
            HStack(spacing: 0) {
                LogoApp(app: l.app, cote: PlanApps.logoListe).padding(.leading, 10).padding(.trailing, 10)
                VStack(alignment: .leading, spacing: 1) {
                    Text(l.app.nom).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    Text(l.sousTitre).font(.system(size: 12, weight: .medium)).foregroundStyle(l.alerte ? Color(hex: 0xFFB340) : Color.white.opacity(0.5)).lineLimit(1)
                }
                Spacer(minLength: 10)
            }
            .allowsHitTesting(false)
            BoutonLigne(b: l.bouton) { if l.bouton != .enCours { m.surAction(.apps(action)) } }
                .padding(.trailing, 10)
        }
        .onHover { survol = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(l.app.nom), \(l.sousTitre)")
        .accessibilityValue(l.bouton.titre)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { if l.bouton != .enCours { m.surAction(.apps(action)) } }
    }
}

private struct BoutonLigne: View {
    var b: BoutonLigneApp
    var action: () -> Void
    @State private var survol = false
    private var couleur: Color {
        switch b {
        case .branche: return CouleursIlot.vert
        case .aRevoir: return CouleursIlot.ambre
        default: return Color.white.opacity(0.6)
        }
    }
    var body: some View {
        Button(action: action) {
            Group {
                switch b {
                case .brancher:
                    Text(b.titre).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.black).lineLimit(1).fixedSize()
                        .padding(.horizontal, 13).frame(height: 28)
                        .background(Capsule().fill(Color.white.opacity(survol ? 0.88 : 1)))
                case .enCours:
                    Text(b.titre).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.white.opacity(0.55)).lineLimit(1).fixedSize()
                        .padding(.horizontal, 10).frame(height: 28)
                default:
                    HStack(spacing: 5) {
                        Circle().fill(couleur).frame(width: 6, height: 6)
                        Text(b.titre).font(.system(size: 12, weight: .semibold)).lineLimit(1).fixedSize()
                        Image(systemName: "chevron.right").font(.system(size: 9.5, weight: .bold)).padding(.leading, -1)
                    }
                    .foregroundStyle(couleur)
                    .padding(.leading, 10).padding(.trailing, 9).frame(height: 26)
                    .background(Capsule().fill(couleur.opacity(survol ? 0.24 : 0.15)))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(AppuiIlot(echelle: 0.94))
        .onHover { survol = $0 }
        .accessibilityHidden(true)
    }
}

// MARK: - le détail d'une app

struct CarteDetailApp: View {
    @ObservedObject var m: IlotMoteur
    var g: GrilleIlot

    var body: some View {
        let v = VueIlot.appsDetail
        let e = m.apps
        let blocs = PlanApps.cadresBlocs(g, e)
        ZStack(alignment: .topLeading) {
            FondCarteApps(m: m, v: v, g: g)
            EnteteApps(m: m, v: v, app: e.detail, titre: e.titreDetail) { pastille(e) }
                .posee(PlanApps.cadreEntete(g, v), m.aspect(v, rang: 0), ancre: .topLeading)
            // les lignes d'information consécutives partagent une boîte
            ForEach(Array(groupesInfo(blocs).enumerated()), id: \.offset) { _, r in
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.07)).allowsHitTesting(false)
                    .posee(r, m.aspect(v, rang: 1), ancre: .top)
            }
            ForEach(Array(blocs.enumerated()), id: \.offset) { i, x in
                bloc(x.bloc, e).posee(x.cadre, m.aspect(v, rang: min(4, 1 + i)), ancre: .top)
            }
        }
        .frame(width: IlotMoteur.largeur, height: IlotMoteur.hauteurMax, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(e.titreDetail)
    }

    private func groupesInfo(_ blocs: [(bloc: BlocDetailApp, cadre: CGRect)]) -> [CGRect] {
        var r: [CGRect] = []
        var courant: CGRect?
        for b in blocs {
            if case .info = b.bloc { courant = courant.map { $0.union(b.cadre) } ?? b.cadre }
            else if let c = courant { r.append(c); courant = nil }
        }
        if let c = courant { r.append(c) }
        return r
    }

    @ViewBuilder private func pastille(_ e: EtatAppsIlot) -> some View {
        if e.parcours == nil, let a = e.detail, let p = e.etat(a).pastille {
            let c: Color = p.ton == .vert ? CouleursIlot.vert : (p.ton == .ambre ? CouleursIlot.ambre : Color.white.opacity(0.55))
            HStack(spacing: 5) {
                Circle().fill(c).frame(width: 6, height: 6)
                Text(p.texte).font(.system(size: 12, weight: .semibold)).lineLimit(1).fixedSize()
            }
            .foregroundStyle(c)
            .allowsHitTesting(false)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder private func bloc(_ b: BlocDetailApp, _ e: EtatAppsIlot) -> some View {
        let app = e.parcours?.app ?? e.detail ?? .notion
        let champ = e.parcours?.champ
        switch b {
        case .libelleCle:
            HStack(spacing: 8) {
                Text(champ?.libelle ?? "").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Color.white.opacity(0.6)).lineLimit(1).allowsHitTesting(false)
                Spacer(minLength: 0)
                PiluleOutil(titre: "Ouvrir la page", icone: "arrow.up.right", hauteur: 24, taille: 12, padding: 10,
                            etiquette: "Ouvrir la page où créer la clé, dans le navigateur") { m.surAction(.apps(.pageCle)) }
            }
        case .champCle:
            let saisie = e.parcours?.saisie
            HStack(spacing: 8) {
                Text(e.parcours?.saisieMontree ?? champ?.exemple ?? "")
                    .font(.system(size: 13, weight: .medium, design: champ?.masque == false ? .default : .monospaced))
                    .foregroundStyle(saisie == nil ? Color.white.opacity(0.35) : .white).lineLimit(1).truncationMode(.middle)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.white.opacity(0.08)))
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Color.white.opacity(saisie == nil ? 0.12 : 0.35), lineWidth: 1))
                    .allowsHitTesting(false)
                    .accessibilityLabel(saisie == nil ? "Rien de collé : \(champ?.libelle ?? "")" : (champ?.masque == false ? "Collé : \(e.parcours?.saisieMontree ?? "")" : "Clé collée"))
                PiluleOutil(titre: saisie == nil ? "Coller" : "Collée", icone: saisie == nil ? "doc.on.clipboard" : "checkmark", hauteur: 36, taille: 13, padding: 14,
                            etiquette: "Coller ce qui est copié : \(champ?.libelle ?? "la clé")") { m.surAction(.apps(.coller)) }
                    .frame(width: PlanApps.largeurColler)
            }
        case .aideCle:
            let a = champ?.aide ?? (debut: "", fort: "", fin: "")
            Text("\(a.debut)\(Text(a.fort).foregroundColor(.white).fontWeight(.semibold))\(a.fin)")
                .font(.system(size: 11.5, weight: .medium)).foregroundStyle(Color.white.opacity(0.5)).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .allowsHitTesting(false)
        case .valide(let s):
            HStack(spacing: 7) {
                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                Text(s).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color(hex: 0x5FE08A))
            .padding(.horizontal, 12)
            .frame(maxHeight: .infinity)
            .background(Capsule().fill(CouleursIlot.vert.opacity(0.14)))
            .allowsHitTesting(false)
        case .question:
            HStack(spacing: 6) {
                Text(e.parcours?.question ?? "").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Color.white.opacity(0.6)).lineLimit(1).allowsHitTesting(false)
                Spacer(minLength: 0)
                if let p = e.parcours, p.pages > 1 {
                    BoutonPage(symbole: "chevron.left", actif: p.pageMontree > 0, etiquette: "Page précédente") { m.surAction(.apps(.page(-1))) }
                    Text("\(p.pageMontree + 1)/\(p.pages)").font(.system(size: 11.5, weight: .semibold).monospacedDigit()).foregroundStyle(Color.white.opacity(0.5)).fixedSize()
                    BoutonPage(symbole: "chevron.right", actif: p.pageMontree < p.pages - 1, etiquette: "Page suivante") { m.surAction(.apps(.page(1))) }
                }
            }
        case .choix(let c):
            LigneChoix(m: m, choix: c, choisi: e.parcours?.selection == c.id)
        case .erreur(let texte, let geste):
            // la phrase sur deux lignes au plus ; son geste dessous, à droite (« Réessayer », « Ouvrir les Réglages »)
            VStack(alignment: .trailing, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 12, weight: .semibold)).foregroundStyle(CouleursIlot.ambre)
                    Text(texte).font(.system(size: 12, weight: .medium)).foregroundStyle(Color(hex: 0xFFD08A)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .allowsHitTesting(false)
                if let t = geste.titre {
                    PiluleOutil(titre: t, style: .ambre, hauteur: 26, taille: 12, padding: 11, etiquette: t) { m.surAction(.apps(.geste(geste))) }
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(maxHeight: .infinity, alignment: .center)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(CouleursIlot.ambre.opacity(0.13)).allowsHitTesting(false))
        case .bouton:
            GrandBoutonApps(titre: e.occupe ? (e.parcours?.titreEnCours ?? "") : (e.parcours?.titreBouton ?? ""),
                            actif: e.parcours?.boutonActif == true && !e.occupe, attente: e.occupe) { m.surAction(.apps(.valider)) }
        case .info(let i):
            LigneInfo(m: m, i: i)
        case .rendezVous(let ev):
            if let ev {
                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        GlypheIlot(nom: GlypheIlot.calendrier, couleur: CouleursIlot.rouge, taille: 21).frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ev.titre).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                            Text(PlanAgenda.plage(ev) + (ev.lien.map { " \u{00B7} " + LienVisio.service($0) } ?? ev.lieu.map { " \u{00B7} " + $0 } ?? ""))
                                .font(.system(size: 12, weight: .medium)).foregroundStyle(Color.white.opacity(0.55)).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(height: 44)
                    .allowsHitTesting(false)
                    HStack(spacing: 8) {
                        if ev.lien != nil {
                            CapIlot(titre: "Rejoindre", icone: "video.fill", style: .vert, etiquette: "Rejoindre la visio", remplir: true) { m.surAction(.rendezVousRejoindre(ev)) }
                        }
                        CapIlot(titre: "Noter la réunion", icone: "record.circle", remplir: true) { m.surAction(.rendezVousNoter(ev)) }
                    }
                }
            } else {
                Text("Rien d\u{2019}ici 12 h dans ton calendrier").font(.system(size: 12.5, weight: .medium)).foregroundStyle(Color.white.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).padding(.leading, 2)
                    .allowsHitTesting(false)
            }
        case .pied:
            HStack(spacing: 10) {
                Text(app.notePied).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Color.white.opacity(0.45)).lineLimit(1).allowsHitTesting(false)
                Spacer(minLength: 0)
                BoutonRouge(titre: PlanApps.titreDebrancher, plein: false, etiquette: "Débrancher \(app.nom)") { m.surAction(.apps(.debrancher)) }
            }
        case .confirmation:
            VStack(alignment: .leading, spacing: 4) {
                Text("Débrancher \(app.nom)\u{00A0}?").font(.system(size: 13.5, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                Text(app.demandeUneCle ? "Les nouveautés s\u{2019}arrêtent et la clé est effacée de ce Mac. Tu peux rebrancher quand tu veux."
                                       : "Les nouveautés s\u{2019}arrêtent. Tu peux rebrancher quand tu veux.")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Color.white.opacity(0.6)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    PiluleOutil(titre: "Annuler", hauteur: 30, taille: 13, padding: 14, etiquette: "Annuler : garder \(app.nom) branché") { m.surAction(.apps(.annulerDebrancher)) }
                    BoutonRouge(titre: PlanApps.titreDebrancher, plein: true, etiquette: "Débrancher \(app.nom) et effacer sa clé") { m.surAction(.apps(.confirmerDebrancher)) }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(CouleursIlot.rouge.opacity(0.14)).allowsHitTesting(false))
        }
    }
}

private struct BoutonPage: View {
    var symbole: String
    var actif: Bool
    var etiquette: String
    var action: () -> Void
    var body: some View {
        Button(action: { if actif { action() } }) {
            Image(systemName: symbole).font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.white.opacity(actif ? 0.9 : 0.3))
                .frame(width: 22, height: 20).background(Capsule().fill(Color.white.opacity(0.1))).contentShape(Capsule())
        }
        .buttonStyle(AppuiIlot(echelle: 0.9))
        .accessibilityLabel(etiquette)
    }
}

private struct LigneChoix: View {
    @ObservedObject var m: IlotMoteur
    var choix: ChoixApp
    var choisi: Bool
    @State private var survol = false
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(choisi ? CouleursIlot.bleu.opacity(0.22) : Color.white.opacity(survol ? 0.11 : 0.07))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(choisi ? CouleursIlot.bleu.opacity(0.9) : .clear, lineWidth: 1.2))
                .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .onTapGesture { m.surAction(.apps(.choisir(choix.id))) }
            HStack(spacing: 10) {
                ZStack {
                    Circle().strokeBorder(Color.white.opacity(choisi ? 0 : 0.45), lineWidth: 1.5)
                    if choisi { Circle().fill(CouleursIlot.bleu); Image(systemName: "checkmark").font(.system(size: 8.5, weight: .heavy)).foregroundStyle(.white) }
                }
                .frame(width: 16, height: 16)
                Text(choix.nom).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .allowsHitTesting(false)
        }
        .onHover { survol = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(choix.nom)
        .accessibilityAddTraits(choisi ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { m.surAction(.apps(.choisir(choix.id))) }
    }
}

private struct LigneInfo: View {
    @ObservedObject var m: IlotMoteur
    var i: InfoApp
    private var symbole: String {
        switch i.genre {
        case .suit: return "list.bullet.rectangle"
        case .base: return "tray"
        case .personne: return "person"
        case .cle: return "key"
        case .etat: return "macwindow"
        case .compte: return "building.2"
        }
    }
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbole).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.white.opacity(0.55)).frame(width: 18)
            if i.genre == .cle {
                Text(i.libelle).font(.system(size: 13, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                Spacer(minLength: 8)
                Text(i.valeur ?? "").font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(Color.white.opacity(0.45)).lineLimit(1).fixedSize()
            } else {
                Text("\(i.libelle)\(Text(i.valeur ?? "").fontWeight(.bold))")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                Spacer(minLength: 8)
                if i.changer {
                    PiluleOutil(titre: "Changer", hauteur: 24, taille: 12, padding: 11,
                                etiquette: i.genre == .personne ? "Changer la personne suivie" : "Changer ce qui est suivi") { m.surAction(.apps(.changer(i.genre))) }
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(maxHeight: .infinity)
    }
}

/// Le grand bouton du parcours (34 pt, toute la largeur) : blanc s'il est utilisable ; grisé sinon (un clic n'y fait rien, il ne range
/// pas l'îlot : jamais `.disabled`) ; un rouet pendant la vérification.
private struct GrandBoutonApps: View {
    var titre: String
    var actif: Bool
    var attente: Bool
    var action: () -> Void
    @State private var survol = false
    var body: some View {
        Button(action: { if actif { action() } }) {
            HStack(spacing: 8) {
                if attente { ProgressView().controlSize(.small).tint(.white) }
                Text(titre).font(.system(size: 13.5, weight: .semibold)).lineLimit(1).fixedSize()
            }
            .foregroundStyle(actif ? Color.black : Color.white.opacity(0.4))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Capsule().fill(actif ? Color.white.opacity(survol ? 0.88 : 1) : Color.white.opacity(0.1)))
            .contentShape(Capsule())
        }
        .buttonStyle(AppuiIlot(echelle: 0.97))
        .onHover { survol = $0 }
        .accessibilityLabel(titre)
    }
}

/// « Débrancher » : rouge doux dans le pied, rouge plein dans la confirmation.
private struct BoutonRouge: View {
    var titre: String
    var plein: Bool
    var etiquette: String
    var action: () -> Void
    @State private var survol = false
    var body: some View {
        Button(action: action) {
            Text(titre).font(.system(size: 13, weight: .semibold)).lineLimit(1).fixedSize()
                .foregroundStyle(plein ? Color.white : Color(hex: 0xFF6961))
                .padding(.horizontal, 14).frame(height: 30)
                .background(Capsule().fill(plein ? CouleursIlot.rouge.opacity(survol ? 0.88 : 1) : CouleursIlot.rouge.opacity(survol ? 0.26 : 0.18)))
                .contentShape(Capsule())
        }
        .buttonStyle(AppuiIlot(echelle: 0.94))
        .onHover { survol = $0 }
        .accessibilityLabel(etiquette)
    }
}

// MARK: - les Nouveautés

struct CarteNouveautes: View {
    @ObservedObject var m: IlotMoteur
    var g: GrilleIlot

    var body: some View {
        let v = VueIlot.appsNouveautes
        let e = m.apps
        let z = PlanApps.zone(g, v)
        let cadres = PlanApps.cadresNouveautes(g, e)
        ZStack(alignment: .topLeading) {
            FondCarteApps(m: m, v: v, g: g)
            EnteteApps(m: m, v: v, app: nil, titre: "Nouveautés") {
                if !e.nonLues.isEmpty {
                    PiluleCentre(titre: PlanApps.titreToutLu, etiquette: "Tout marquer comme lu") { m.surAction(.apps(.toutLu)) }
                        .frame(width: PiluleCentre.largeur(PlanApps.titreToutLu))
                }
            }
            .posee(PlanApps.cadreEntete(g, v), m.aspect(v, rang: 0), ancre: .topLeading)
            if cadres.isEmpty {
                VStack(spacing: 10) {
                    Text(e.branchees.isEmpty ? "Aucune app branchée pour l\u{2019}instant" : "Rien de nouveau pour l\u{2019}instant")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(CouleursIlot.encre3).lineLimit(1)
                    PiluleOutil(titre: "Tes apps", icone: "square.grid.2x2", hauteur: 28, taille: 12.5, padding: 12, etiquette: "Voir Tes apps") { m.revenir() }
                }
                .posee(CGRect(x: z.minX, y: z.minY + PlanApps.entete + CGFloat(MesuresApps.ecartNouveautes), width: z.width, height: CGFloat(PlanNouveautes.corpsVide)),
                       m.aspect(v, rang: 1), ancre: .top, .center)
            }
            ForEach(Array(cadres.enumerated()), id: \.offset) { k, s in
                TitreSection(s: s.section).posee(s.titre, m.aspect(v, rang: min(4, 1 + k)), ancre: .topLeading)
                ForEach(Array(s.section.lignes.enumerated()), id: \.element.id) { j, x in
                    LigneNouveaute(m: m, x: x, nonLue: e.nonLues.contains(x.id))
                        .posee(s.lignes[j], m.aspect(v, rang: min(4, 1 + k)), ancre: .top)
                }
            }
        }
        .frame(width: IlotMoteur.largeur, height: IlotMoteur.hauteurMax, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Nouveautés")
    }
}

private struct TitreSection: View {
    var s: PlanNouveautes.Section
    var body: some View {
        HStack(spacing: 6) {
            LogoApp(app: s.app, cote: 15)
            Text(s.app.nom).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Color.white.opacity(0.55)).lineLimit(1).fixedSize()
            Spacer(minLength: 0)
            if s.cachees > 0 { Text("+\(s.cachees)").font(.system(size: 11, weight: .semibold).monospacedDigit()).foregroundStyle(Color.white.opacity(0.4)).fixedSize() }
        }
        .padding(.horizontal, 4)
        .frame(maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }
}

private struct LigneNouveaute: View {
    @ObservedObject var m: IlotMoteur
    var x: Nouveaute
    var nonLue: Bool
    @State private var survol = false
    var body: some View {
        let heure = FormatIlot.heure(x.date)
        ZStack(alignment: .trailing) {
            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(survol ? 0.09 : 0.001))
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .onTapGesture { m.surAction(.apps(.ouvrir(x.id))) }
            HStack(spacing: 8) {
                Circle().fill(nonLue ? CouleursIlot.bleu : .clear).frame(width: 6, height: 6)
                Text(x.titre).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1).truncationMode(.tail)
                    .frame(width: min(MesureIlot.texte(x.titre, 13, .semibold), 150), alignment: .leading)
                Text(x.sousTitre).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Color.white.opacity(0.5)).lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(heure).font(.system(size: 11.5, weight: .medium).monospacedDigit()).foregroundStyle(Color.white.opacity(0.4)).fixedSize()
                Color.clear.frame(width: PlanApps.largeurOuvrir)
            }
            .padding(.leading, 6).padding(.trailing, 4)
            .allowsHitTesting(false)
            PiluleOutil(titre: "Ouvrir", icone: "arrow.up.right", style: survol ? .blanc : .gris, hauteur: 22, taille: 12, padding: 9,
                        etiquette: "Ouvrir dans \(x.app.nom)") { m.surAction(.apps(.ouvrir(x.id))) }
                .padding(.trailing, 4)
        }
        .onHover { survol = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(x.app.nom) : \(x.titre), \(x.sousTitre), \(heure)\(nonLue ? ", non lu" : "")")
    }
}

// MARK: - l'aile, et le bandeau

/// L'aile : le logo de l'app à gauche, « 1 mail » (ou le nombre seul, s'il ne tient pas) à droite.
struct AileApps: View {
    @ObservedObject var m: IlotMoteur
    var g: GrilleIlot
    static func texte(_ a: AnnonceApps, place: CGFloat) -> String {
        a.aile.first { MesureIlot.texte($0, 13, .semibold, chiffres: true) <= place } ?? a.aile.last ?? ""
    }
    var body: some View {
        let v = VueIlot.appsAile
        let a = m.bandeauVu?.apps ?? AnnonceApps([])
        let c = g.centreAile(v, droite: false)
        let d = g.bordAile(v), l = d - g.hc - 4
        let t = Self.texte(a, place: l)
        ZStack(alignment: .topLeading) {
            Group {
                if let app = a.apps.first { LogoApp(app: app, cote: 19) } else { Color.clear }
            }
            .posee(CGRect(x: c - 12, y: 0, width: 24, height: g.barre), m.aspect(v, rang: 0), ancre: .center, .center)
            Text(t).font(.system(size: 13, weight: .semibold).monospacedDigit()).tracking(-0.1).foregroundStyle(.white).lineLimit(1)
                .posee(CGRect(x: d - l, y: 0, width: l, height: g.barre), m.aspect(v, rang: 1), ancre: .center, .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tes apps : \(a.titre)")
    }
}

extension IlotMoteur {
    /// Le bandeau de « Tes apps » : le logo (deux en pile pour plusieurs apps), qui et quoi, « Ouvrir ».
    func contenuAnnonceApps() -> ContenuAnnonce? {
        guard let a = bandeauVu?.apps, !a.elements.isEmpty else { return nil }
        // un seul logo (deux icônes d'app en pile se lisaient comme une tache) : celui de la nouveauté la plus récente
        let logos = a.elements.first.map { [LogosApps.image($0.app)] } ?? []
        return ContenuAnnonce(glyphe: nil, l1: a.titre, l2: a.sousTitre,
                              droite: .boutons([.init(titre: "Ouvrir", style: .blanc,
                                                      etiquette: a.ouvreLaListe ? "Voir les nouveautés" : "Ouvrir dans \(a.seule?.app.nom ?? "l\u{2019}app")",
                                                      action: .apps(.ouvrirAnnonce))]),
                              icones: Array(logos), coteSymbole: 30)
    }
}
