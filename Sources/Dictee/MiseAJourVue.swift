import AppKit
import SwiftUI
import DicteeCore

// MARK: la ligne sous l'encoche

/// État d'ouverture de la ligne (la matière — version, progression, échec — vient de `MiseAJourModele`).
@MainActor
final class BandeMiseAJourModele: ObservableObject {
    @Published var ouverte = false
    var reduire = false
    var geometrie = GeometrieEncoche()
}

/// Une ligne sobre sous l'encoche, dans le style du filet de sécurité (fond noir, texte #ECE9E3) :
/// « Verbe 0.3.1 est disponible » — Nouveautés · Plus tard · Installer. Pendant l'installation, elle montre la progression.
struct MiseAJourBandeVue: View {
    @ObservedObject var m: MiseAJourModele
    @ObservedObject var bande: BandeMiseAJourModele
    var tailleFenetre: CGSize
    var surInstaller: () -> Void = {}
    var surPlusTard: () -> Void = {}
    var surNouveautes: () -> Void = {}
    var surFermer: () -> Void = {}

    /// Largeur de la bande (celle du ruban) : 140 pt de chaque côté de la caméra, comme le filet de sécurité.
    static func largeurPleine(_ g: GeometrieEncoche) -> CGFloat { g.largeur + 2 * 140 }
    static let hauteurRuban: CGFloat = 26
    private var largeurPleine: CGFloat { Self.largeurPleine(bande.geometrie) }
    private var largeurBande: CGFloat { bande.ouverte || bande.reduire ? largeurPleine : bande.geometrie.largeur }
    private var hauteurRuban: CGFloat { bande.ouverte || bande.reduire ? Self.hauteurRuban : 0 }

    var body: some View {
        let g = bande.geometrie
        let animation: Animation? = bande.reduire ? nil : .spring(duration: GeometrieEncoche.dureeMouvement, bounce: 0.1)
        ZStack(alignment: .top) {
            FormeEncoche(largeur: largeurBande, ruban: hauteurRuban, largeurRuban: largeurPleine, hauteurBande: g.hauteur, largeurCamera: g.largeur)
                .fill(Color.black)
                .frame(width: tailleFenetre.width, height: tailleFenetre.height, alignment: .top)
            bandeHaute(g)
            ruban(g)
        }
        .frame(width: tailleFenetre.width, height: tailleFenetre.height, alignment: .top)
        .opacity(bande.reduire ? (bande.ouverte ? 1 : 0) : 1)
        .animation(animation, value: bande.ouverte)
        .animation(.easeOut(duration: GeometrieEncoche.dureeFondu), value: bande.ouverte)
    }

    /// L'icône de Verbe à gauche, un petit point ambre à droite : rien au centre, c'est la caméra.
    private func bandeHaute(_ g: GeometrieEncoche) -> some View {
        HStack(spacing: 0) {
            Image(nsImage: MiseAJourBandeVue.icone).resizable().interpolation(.high).frame(width: 22, height: 22)
                .frame(width: GeometrieEncoche.aile + 50 - 14, alignment: .leading)
                .padding(.leading, 14)
            Spacer(minLength: 0).frame(width: g.largeur)
            Circle().fill(Palette.accent).frame(width: 6, height: 6)
                .frame(width: GeometrieEncoche.aile + 50 - 14, alignment: .trailing)
                .padding(.trailing, 14)
        }
        .frame(width: largeurPleine, height: g.hauteur)
        .opacity(bande.ouverte ? 1 : 0)
        .animation(.easeOut(duration: bande.ouverte ? 0.14 : 0.08), value: bande.ouverte)
        .accessibilityHidden(true)
    }

    private func ruban(_ g: GeometrieEncoche) -> some View {
        HStack(spacing: 8) {
            texte.layoutPriority(-1)
            Spacer(minLength: 8)
            actions.fixedSize()
        }
        .padding(.horizontal, 10)
        .frame(width: largeurPleine - 2 * GeometrieEncoche.retraitRuban, height: Self.hauteurRuban)
        .padding(.top, g.hauteur)
        .frame(width: largeurPleine, alignment: .top)
        .opacity(bande.ouverte ? 1 : 0)
        .animation(.easeOut(duration: bande.ouverte ? 0.16 : 0.08), value: bande.ouverte)
        .allowsHitTesting(bande.ouverte)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var texte: some View {
        switch m.presentation {
        case .proposition(let v)?:
            Text("Verbe \(v) est disponible").font(.system(size: 12)).foregroundStyle(Palette.texte).lineLimit(1)
        case .progression(let t)?:
            Text(t).font(.system(size: 12).monospacedDigit()).foregroundStyle(Palette.texte).lineLimit(1)
        case .echec(let t)?:
            Text(t).font(.system(size: 12)).foregroundStyle(Palette.texte).lineLimit(1).truncationMode(.tail)
        case nil:
            Color.clear
        }
    }

    @ViewBuilder private var actions: some View {
        switch m.presentation {
        case .proposition?:
            HStack(spacing: 2) {
                ActionRuban(titre: "Nouveautés", action: surNouveautes)
                ActionRuban(titre: "Plus tard", action: surPlusTard)
                ActionRuban(titre: "Installer", mis: true, action: surInstaller)
            }
        case .echec?:
            HStack(spacing: 2) {
                ActionRuban(titre: "Fermer", action: surFermer)
                ActionRuban(titre: "Réessayer", mis: true, action: surInstaller)
            }
        default:
            EmptyView()
        }
    }

    /// L'icône de Verbe dessinée par l'app elle-même (la même que celle du Dock), sans dépendre du paquet de l'app.
    static let icone: NSImage = {
        if let rep = IconeApp.pixels(cote: 88) {
            let i = NSImage(size: NSSize(width: 22, height: 22)); i.addRepresentation(rep); return i
        }
        return NSImage()
    }()
}

/// La fenêtre de la ligne : un panneau sans bord qui ne prend jamais le focus, posé contre le haut de l'écran. Elle n'épouse que la
/// forme noire (pour ne pas bloquer les clics autour). Niveau sous celui de l'encoche de dictée (+3) et de l'encoche des réunions (+2).
@MainActor
final class MiseAJourPanneau {
    static let delaiSansReponse: TimeInterval = 45
    let etat = BandeMiseAJourModele()
    var surInstaller: () -> Void = {}
    var surPlusTard: () -> Void = {}
    var surNouveautes: () -> Void = {}
    var surFermer: () -> Void = {}
    /// 45 s sans que Hugues y touche : la ligne se retire (comme « Plus tard » : elle revient demain).
    var surDelaiEcoule: () -> Void = {}

    private var fenetre: PanneauSansFocus?
    private var retrait: DispatchWorkItem?
    private var minuterie: DispatchWorkItem?
    private var souris = false
    private var suspendu = false

    var estOuverte: Bool { etat.ouverte }
    private var reduire: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    func afficher(modele: MiseAJourModele) {
        retrait?.cancel()
        guard let ecran = NSScreen.screens.first else { return }
        if etat.ouverte, fenetre?.isVisible == true { redemarrerMinuterie(modele); return }
        let (g, centre) = GeometrieEncoche.mesurer(ecran)
        etat.geometrie = g
        etat.reduire = reduire
        let marge = FormeEncoche.congeHaut.width + 4
        let taille = CGSize(width: ceil(MiseAJourBandeVue.largeurPleine(g) + 2 * marge), height: g.hauteur + MiseAJourBandeVue.hauteurRuban + 8)
        let cadre = NSRect(x: centre - taille.width / 2, y: ecran.frame.maxY - taille.height, width: taille.width, height: taille.height)
        if fenetre == nil {
            let f = PanneauSansFocus(contentRect: cadre, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            f.isOpaque = false
            f.backgroundColor = .clear
            f.hasShadow = false
            f.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
            f.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            f.hidesOnDeactivate = false
            f.isMovable = false
            f.becomesKeyOnlyIfNeeded = true
            f.animationBehavior = .none
            f.appearance = NSAppearance(named: .darkAqua)
            fenetre = f
        }
        guard let f = fenetre else { return }
        f.setFrame(cadre, display: false)
        let vue = VueHebergeeSurvol(rootView: MiseAJourBandeVue(m: modele, bande: etat, tailleFenetre: taille,
                                                                surInstaller: { [weak self] in self?.surInstaller() },
                                                                surPlusTard: { [weak self] in self?.surPlusTard() },
                                                                surNouveautes: { [weak self] in self?.surNouveautes() },
                                                                surFermer: { [weak self] in self?.surFermer() }))
        vue.frame = NSRect(origin: .zero, size: taille)
        vue.surSurvol = { [weak self] dedans in
            guard let self else { return }
            self.souris = dedans
            if dedans { self.minuterie?.cancel() } else { self.redemarrerMinuterie(modele) }
        }
        f.contentView = vue
        f.ignoresMouseEvents = false
        f.orderFrontRegardless()
        etat.ouverte = false
        withAnimation(reduire ? nil : .spring(duration: GeometrieEncoche.dureeMouvement, bounce: 0.12)) { etat.ouverte = true }
        suspendu = false
        redemarrerMinuterie(modele)
        Log.ecrire("mise à jour : proposition affichée sous l'encoche")
    }

    func fermer(animee: Bool = true) {
        minuterie?.cancel()
        souris = false
        guard etat.ouverte || fenetre?.isVisible == true else { return }
        if animee, !reduire {
            withAnimation(.spring(duration: GeometrieEncoche.dureeMouvement, bounce: 0)) { etat.ouverte = false }
            let item = DispatchWorkItem { [weak self] in
                guard let self, !self.etat.ouverte else { return }
                self.fenetre?.orderOut(nil)
            }
            retrait = item
            DispatchQueue.main.asyncAfter(deadline: .now() + GeometrieEncoche.dureeMouvement + 0.1, execute: item)
        } else {
            etat.ouverte = false
            fenetre?.orderOut(nil)
        }
    }

    /// Pendant qu'on lit les notes, la ligne ne se retire pas toute seule.
    func suspendreLeDelai() { suspendu = true; minuterie?.cancel() }

    func annulerLeRetrait() { minuterie?.cancel() }

    func fermerSeulApres(_ secondes: TimeInterval, _ action: @escaping () -> Void) {
        minuterie?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.fermer(); action() }
        }
        minuterie = item
        DispatchQueue.main.asyncAfter(deadline: .now() + secondes, execute: item)
    }

    /// Le compte à rebours ne court que pour la proposition (pas pendant une installation) et jamais tant que la souris est dessus.
    private func redemarrerMinuterie(_ modele: MiseAJourModele) {
        minuterie?.cancel()
        guard !souris, !suspendu, case .proposition? = modele.presentation else { return }
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.etat.ouverte, !self.souris else { return }
                self.surDelaiEcoule()
            }
        }
        minuterie = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.delaiSansReponse, execute: item)
    }
}

// MARK: les notes de version

/// Une petite fenêtre lisible avec les notes de la release (titres, puces, paragraphes ; rien de cliquable) et un bouton Installer.
@MainActor
final class NotesDeVersionFenetre: NSObject, NSWindowDelegate {
    private var fenetre: NSWindow?
    var surInstaller: () -> Void = {}

    func afficher(_ p: PropositionMiseAJour, peutInstaller: Bool) {
        let vue = NotesDeVersionVue(version: p.version.description, blocs: NotesDeVersion.blocs(p.notes), pageURL: p.pageURL, peutInstaller: peutInstaller,
                                    surInstaller: { [weak self] in self?.surInstaller() }, surFermer: { [weak self] in self?.fermer() })
        if fenetre == nil {
            let f = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 440), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            f.title = "Nouveautés"
            f.isReleasedWhenClosed = false
            f.appearance = NSAppearance(named: .darkAqua)
            f.backgroundColor = NSColor(srgbRed: 26/255, green: 26/255, blue: 25/255, alpha: 1)
            f.delegate = self
            f.center()
            fenetre = f
        }
        fenetre?.contentView = NSHostingView(rootView: vue)
        NSApp.activate(ignoringOtherApps: true)
        fenetre?.makeKeyAndOrderFront(nil)
    }

    func fermer() { fenetre?.orderOut(nil) }
}

struct NotesDeVersionVue: View {
    var version: String
    var blocs: [NotesDeVersion.Bloc]
    var pageURL: URL?
    var peutInstaller: Bool
    var surInstaller: () -> Void = {}
    var surFermer: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Verbe \(version)").font(Polices.commande(20, .medium)).foregroundStyle(Palette.texte).padding(.bottom, 14)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 10) {
                    if blocs.isEmpty {
                        Text("Cette version n\u{2019}a pas de notes.").font(Polices.commande(14)).foregroundStyle(Palette.texte2)
                    }
                    ForEach(Array(blocs.enumerated()), id: \.offset) { _, b in
                        switch b {
                        case .titre(let t):
                            Text(t).font(Polices.commande(15, .medium)).foregroundStyle(Palette.texte).padding(.top, 6)
                        case .puce(let t):
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("\u{2022}").foregroundStyle(Palette.texte3)
                                Text(t).fixedSize(horizontal: false, vertical: true)
                            }
                            .font(Polices.commande(14)).foregroundStyle(Palette.texte)
                        case .paragraphe(let t):
                            Text(t).font(Polices.commande(14)).foregroundStyle(Palette.texte2).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)
            HStack(spacing: 12) {
                if let pageURL { LienTexte(titre: "Voir sur GitHub") { NSWorkspace.shared.open(pageURL) } }
                Spacer()
                BoutonCadre("Fermer", action: surFermer)
                if peutInstaller { BoutonCadre("Installer", action: surInstaller) }
            }
            .padding(.top, 16)
        }
        .padding(24)
        .frame(width: 460, height: 440, alignment: .topLeading)
        .background(Palette.surface)
    }
}

// MARK: Réglages › Compte & données

/// Les lignes « Mises à jour » : l'état, un bouton Rechercher, la ligne de la version disponible, l'interrupteur automatique.
struct LignesMiseAJour: View {
    @ObservedObject var m: MiseAJourModele

    private var quand: String {
        guard let d = m.verifieeLe else { return "Pas encore vérifiée." }
        let cal = Calendar.current
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = cal.isDateInToday(d) ? "HH:mm" : (cal.isDateInYesterday(d) ? "HH:mm" : "d MMM, HH:mm")
        let jour = cal.isDateInToday(d) ? "aujourd\u{2019}hui à " : (cal.isDateInYesterday(d) ? "hier à " : "le ")
        return "Vérifiée \(jour)\(f.string(from: d))."
    }

    private var note: String {
        "Version \(m.versionActuelle). \(m.message ?? quand)"
    }

    var body: some View {
        LigneReglage(libelle: "Mises à jour", note: note) {
            etat
            BoutonCadre(m.activite == .verification ? "Recherche…" : "Rechercher", action: m.surRechercher)
                .opacity(m.peutRechercher ? 1 : 0.4).disabled(!m.peutRechercher)
        }
        if let d = m.disponible {
            LigneReglage(libelle: "Verbe \(d.version) est disponible", note: m.refusInstallation ?? "Verbe se remplace puis se relance, en quelques secondes.") {
                if m.activite == .repos {
                    LienTexte(titre: "Nouveautés", action: m.surNouveautes)
                    if m.refusInstallation == nil { BoutonCadre("Installer", action: m.surInstaller) }
                } else {
                    Text(progression)
                }
            }
        }
        LigneReglage(libelle: "Vérifier automatiquement", note: "Une fois par jour, Verbe demande à GitHub s\u{2019}il existe une nouvelle version.") {
            Interrupteur(actif: $m.automatique, etiquette: "Vérifier automatiquement")
        }
    }

    @ViewBuilder private var etat: some View {
        switch m.activite {
        case .verification: Text("Vérification…")
        case .telechargement, .controle, .installation, .attenteRedemarrage: EmptyView()   // la ligne « Verbe X est disponible » dessous montre la progression
        case .repos:
            // Quand une version attend, la ligne juste dessous le dit (avec Installer) : pas de répétition ici.
            if m.disponible == nil, m.verifieeLe != nil { Etat(texte: "À jour") }
        }
    }

    private var progression: String {
        switch m.activite {
        case .telechargement(let x): return "Téléchargement \(Int((x * 100).rounded())) %"
        case .controle: return "Vérification…"
        case .installation: return "Installation…"
        case .attenteRedemarrage: return "Relance…"
        default: return ""
        }
    }
}
