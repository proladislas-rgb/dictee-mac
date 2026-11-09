import AppKit
import SwiftUI
import DicteeCore

/// L'état de l'encoche pour les réunions (maquette design/maquettes/reunions.html, planches 1b et 1c) : pendant l'enregistrement un
/// point ambre, la minuterie et deux traces de son (Moi en haut, Eux en dessous) ; au survol, un ruban avec Pause et Arrêter ;
/// après l'arrêt, « Note prête · Ouvrir ». Une fenêtre à part de celle de la dictée : on peut dicter pendant une réunion.
@MainActor
final class ReunionEncocheModele: ObservableObject {
    @Published var phase: PhaseReunion = .repos
    @Published var ouverte = false
    @Published var survol = false
    @Published var minuterie = "00:00"
    @Published var traceMoi: [CGFloat] = Array(repeating: 0, count: 12)
    @Published var traceEux: [CGFloat] = Array(repeating: 0, count: 12)
    /// Libellé du ruban pendant l'enregistrement (« Micro et son de l'appel », « Micro seul »).
    @Published var sources = "Micro et son de l\u{2019}appel"
    /// Libellé pendant le traitement (« Transcription… », « Note en préparation, partie 2 sur 4 »).
    @Published var traitement = "Transcription…"
    /// « Note prête » ou, si la note n'a pas pu être écrite, « Transcription prête ».
    @Published var libellePrete = "Note prête"
    var reduire = false
    var geometrie = GeometrieEncoche()

    var surArreter: () -> Void = {}
    var surPause: () -> Void = {}
    var surReprendre: () -> Void = {}
    var surOuvrir: () -> Void = {}
    var surNoter: () -> Void = {}
    var surRefuser: () -> Void = {}

    var largeurDeBase: CGFloat { ouverte || reduire ? geometrie.largeur + 2 * GeometrieEncoche.aile : geometrie.largeur }

    /// Le ruban est-il sorti ? Au survol pendant l'enregistrement ; en permanence pour la proposition, le traitement, la note prête, un message.
    var ruban: Bool {
        switch phase {
        case .repos: return false
        case .enregistrement: return survol
        case .proposition, .traitement, .prete, .message: return true
        }
    }
    var hauteurRuban: CGFloat { ruban ? GeometrieEncoche.hauteurRuban : 0 }
    var opacite: Double { reduire ? (ouverte ? 1 : 0) : 1 }

    /// Pousse une valeur dans une trace (la plus ancienne sort à gauche) : 0…1 → hauteur de barre.
    static func pousser(_ trace: inout [CGFloat], _ niveau: Float) {
        trace.removeFirst()
        trace.append(CGFloat(min(1, max(0, niveau))))
    }
}

struct ReunionEncocheVue: View {
    @ObservedObject var m: ReunionEncocheModele
    var tailleFenetre: CGSize

    var body: some View {
        let g = m.geometrie
        let animation: Animation? = m.reduire ? nil : .spring(duration: GeometrieEncoche.dureeMouvement, bounce: 0.1)
        ZStack(alignment: .top) {
            FormeEncoche(largeur: m.largeurDeBase, ruban: m.hauteurRuban, largeurRuban: m.largeurDeBase, hauteurBande: g.hauteur, largeurCamera: g.largeur)
                .fill(Color.black)
                .frame(width: tailleFenetre.width, height: tailleFenetre.height, alignment: .top)
            bande(g)
            ruban(g)
        }
        .frame(width: tailleFenetre.width, height: tailleFenetre.height, alignment: .top)
        .opacity(m.opacite)
        .animation(animation, value: m.hauteurRuban)
        .animation(animation, value: m.ouverte)
        .animation(.easeOut(duration: GeometrieEncoche.dureeFondu), value: m.opacite)
    }

    // MARK: bande (hauteur de la barre des menus)

    private func bande(_ g: GeometrieEncoche) -> some View {
        HStack(spacing: 0) {
            aileGauche.frame(width: GeometrieEncoche.aile - 14, alignment: .leading).padding(.leading, 14)
            Spacer(minLength: 0).frame(width: g.largeur)
            aileDroite.frame(width: GeometrieEncoche.aile - 8, alignment: .trailing).padding(.trailing, 8)
        }
        .frame(width: m.largeurDeBase, height: g.hauteur)
        .opacity(m.ouverte ? 1 : 0)
        .animation(.easeOut(duration: m.ouverte ? 0.14 : 0.08), value: m.ouverte)
    }

    @ViewBuilder private var aileGauche: some View {
        switch m.phase {
        case .enregistrement(let pause):
            HStack(spacing: 8) {
                Circle().fill(pause ? EncocheCouleurs.t3 : Palette.accent).frame(width: 6, height: 6)
                Text(m.minuterie).font(.system(size: 13).monospacedDigit()).foregroundStyle(pause ? EncocheCouleurs.t2 : EncocheCouleurs.t1)
            }
            .fixedSize()
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Réunion en cours, \(m.minuterie)\(pause ? ", en pause" : "")")
        case .traitement, .prete:
            Text(m.minuterie).font(.system(size: 13).monospacedDigit()).foregroundStyle(EncocheCouleurs.t3).fixedSize()
        case .proposition(let app):
            Text(app).font(.system(size: 13)).foregroundStyle(EncocheCouleurs.t1).lineLimit(1)
        default:
            Color.clear
        }
    }

    @ViewBuilder private var aileDroite: some View {
        if case .enregistrement = m.phase {
            HStack(spacing: 8) {
                TracesDeSon(moi: m.traceMoi, eux: m.traceEux)
                BoutonBande(symbole: "stop.fill", couleur: EncocheCouleurs.t1, action: m.surArreter)
                    .accessibilityLabel("Arrêter la réunion")
            }
        } else {
            Color.clear
        }
    }

    // MARK: ruban

    private func ruban(_ g: GeometrieEncoche) -> some View {
        let largeur = m.largeurDeBase - 2 * GeometrieEncoche.retraitRuban
        return HStack(spacing: 8) {
            rubanTexte.layoutPriority(-1)
            Spacer(minLength: 8)
            rubanActions.fixedSize()
        }
        .padding(.horizontal, 8)
        .frame(width: largeur, height: GeometrieEncoche.hauteurRuban)
        .padding(.top, g.hauteur)
        .opacity(m.ruban ? 1 : 0)
        .animation(.easeOut(duration: GeometrieEncoche.dureeFondu), value: m.ruban)
        .allowsHitTesting(m.ruban)
    }

    @ViewBuilder private var rubanTexte: some View {
        let texte: String = {
            switch m.phase {
            case .enregistrement(let pause): return pause ? "En pause" : m.sources
            case .proposition: return "Noter cet appel ?"
            case .traitement: return m.traitement
            case .prete: return m.libellePrete
            case .message(let t): return t
            case .repos: return ""
            }
        }()
        Text(texte).font(.system(size: 12)).foregroundStyle(m.phase.estPrete ? EncocheCouleurs.t1 : EncocheCouleurs.t3).lineLimit(1)
    }

    @ViewBuilder private var rubanActions: some View {
        switch m.phase {
        case .enregistrement(let pause):
            HStack(spacing: 4) {
                ActionRuban(titre: pause ? "Reprendre" : "Pause", action: pause ? m.surReprendre : m.surPause)
                ActionRuban(titre: "Arrêter", touche: "\u{2325}\u{2318}N", mis: true, action: m.surArreter)
            }
        case .proposition:
            HStack(spacing: 4) {
                ActionRuban(titre: "Non", action: m.surRefuser)
                ActionRuban(titre: "Noter", touche: "\u{2325}\u{2318}N", mis: true, action: m.surNoter)
            }
        case .prete:
            ActionRuban(titre: "Ouvrir", mis: true, action: m.surOuvrir)
        default:
            EmptyView()
        }
    }
}

extension PhaseReunion {
    var estPrete: Bool { if case .prete = self { return true }; return false }
}

/// Un petit bouton du ruban : texte clair, fond gris au survol ou quand il est « mis en avant » (l'action principale).
struct ActionRuban: View {
    var titre: String
    var touche: String?
    var mis = false
    var action: () -> Void
    @State private var survol = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(titre).font(.system(size: 12))
                if let touche {
                    Text(touche).font(.system(size: 11, weight: .medium)).foregroundStyle(EncocheCouleurs.t3)
                        .padding(.horizontal, 4).overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
                }
            }
            .foregroundStyle(EncocheCouleurs.t1)
            .padding(.horizontal, 8).frame(height: 20)
            .background(RoundedRectangle(cornerRadius: 5).fill(mis || survol ? EncocheCouleurs.k3 : Color.clear))
        }
        .buttonStyle(.plain)
        .onHover { survol = $0 }
        .accessibilityLabel(titre)
    }
}

/// Deux petites traces de son : en haut le micro (Moi, blanc), en dessous le son du Mac (Eux, gris), 12 barres de 2 pt chacune.
struct TracesDeSon: View {
    var moi: [CGFloat]
    var eux: [CGFloat]
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ligne(moi, EncocheCouleurs.t1)
            ligne(eux, EncocheCouleurs.t3)
        }
        .frame(width: 36)
        .accessibilityHidden(true)
    }
    private func ligne(_ valeurs: [CGFloat], _ couleur: Color) -> some View {
        HStack(spacing: 1) {
            ForEach(0..<valeurs.count, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1).fill(couleur).frame(width: 2, height: 2 + 6 * valeurs[i])
            }
        }
        .frame(height: 8)
    }
}

/// Une vue d'hébergement qui accepte le premier clic et dit quand la souris entre ou sort (le ruban d'actions sort au survol).
final class VueHebergeeSurvol<Contenu: View>: NSHostingView<Contenu> {
    var surSurvol: ((Bool) -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for a in trackingAreas { removeTrackingArea(a) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }
    // Au-dessus de l'encoche, toujours la flèche : sans cela, la fenêtre de dessous (Terminal, éditeur) garde son curseur
    // de texte (le « I » de sélection), car ce panneau ne devient jamais la fenêtre active.
    override func mouseEntered(with event: NSEvent) { NSCursor.arrow.set(); surSurvol?(true) }
    override func mouseMoved(with event: NSEvent) { NSCursor.arrow.set() }
    override func cursorUpdate(with event: NSEvent) { NSCursor.arrow.set() }
    override func mouseExited(with event: NSEvent) { surSurvol?(false) }
}

/// La fenêtre de l'encoche des réunions. Elle n'épouse que la forme noire (bande, puis bande et ruban) pour ne jamais bloquer les
/// clics autour (menus de l'app au premier plan, onglets). Elle ne prend jamais le focus.
@MainActor
final class ReunionPanneau {
    let modele = ReunionEncocheModele()
    private var fenetre: PanneauSansFocus?
    private var vue: VueHebergeeSurvol<ReunionEncocheVue>?
    private var retrait: DispatchWorkItem?
    private var sortieDuSurvol: DispatchWorkItem?
    private var centre: CGFloat = 0
    private var ecran: NSScreen?

    private var reduire: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private var margeLaterale: CGFloat { FormeEncoche.congeHaut.width + 4 }

    private func taille(rubanSorti: Bool) -> CGSize {
        let g = modele.geometrie
        let largeur = g.largeur + 2 * GeometrieEncoche.aile + 2 * margeLaterale
        return CGSize(width: ceil(largeur), height: g.hauteur + (rubanSorti ? GeometrieEncoche.hauteurRuban + 6 : 0) + 2)
    }

    /// Montre l'encoche dans la phase donnée (déjà posée dans `modele.phase`).
    func afficher() {
        retrait?.cancel()
        guard let ecran = NSScreen.screens.first else { return }
        self.ecran = ecran
        let (g, c) = GeometrieEncoche.mesurer(ecran)
        modele.geometrie = g
        modele.reduire = reduire
        centre = c
        let t = taille(rubanSorti: modele.ruban)
        let cadre = NSRect(x: centre - t.width / 2, y: ecran.frame.maxY - t.height, width: t.width, height: t.height)
        if fenetre == nil {
            let f = PanneauSansFocus(contentRect: cadre, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            f.isOpaque = false
            f.backgroundColor = .clear
            f.hasShadow = false
            // sous l'encoche de la dictée (+3) : dicter pendant une réunion recouvre brièvement celle-ci
            f.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
            f.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            f.hidesOnDeactivate = false
            f.isMovable = false
            f.becomesKeyOnlyIfNeeded = true
            f.animationBehavior = .none
            fenetre = f
        }
        guard let f = fenetre else { return }
        f.setFrame(cadre, display: false)
        // La vue a toujours la plus grande taille (ruban sorti) : seul le cadre de la fenêtre change, la forme noire se dessine en haut.
        let grande = taille(rubanSorti: true)
        let v = VueHebergeeSurvol(rootView: ReunionEncocheVue(m: modele, tailleFenetre: grande))
        v.frame = NSRect(origin: .zero, size: grande)
        v.autoresizingMask = []
        v.surSurvol = { [weak self] dedans in self?.survol(dedans) }
        vue = v
        let conteneur = NSView(frame: NSRect(origin: .zero, size: t))
        conteneur.addSubview(v)
        v.frame.origin = CGPoint(x: 0, y: t.height - grande.height)
        f.contentView = conteneur
        f.ignoresMouseEvents = false
        f.orderFrontRegardless()
        modele.ouverte = false
        withAnimation(reduire ? nil : .spring(duration: GeometrieEncoche.dureeMouvement, bounce: 0.12)) { modele.ouverte = true }
    }

    /// À appeler quand la phase change : ajuste la hauteur de la fenêtre (ruban sorti ou non).
    func ajuster() {
        guard let f = fenetre, f.isVisible, let ecran else { return }
        let t = taille(rubanSorti: modele.ruban)
        f.setFrame(NSRect(x: centre - t.width / 2, y: ecran.frame.maxY - t.height, width: t.width, height: t.height), display: true)
        if let v = vue, let c = f.contentView { c.frame.size = t; v.frame.origin = CGPoint(x: 0, y: t.height - v.frame.height) }
    }

    func masquer() {
        retrait?.cancel()
        sortieDuSurvol?.cancel()
        modele.survol = false
        withAnimation(reduire ? nil : .spring(duration: GeometrieEncoche.dureeMouvement, bounce: 0)) { modele.ouverte = false }
        let item = DispatchWorkItem { [weak self] in
            guard let self, !self.modele.ouverte else { return }
            self.fenetre?.orderOut(nil)
        }
        retrait = item
        DispatchQueue.main.asyncAfter(deadline: .now() + GeometrieEncoche.dureeMouvement + 0.1, execute: item)
    }

    private func survol(_ dedans: Bool) {
        sortieDuSurvol?.cancel()
        if dedans {
            guard case .enregistrement = modele.phase else { return }
            modele.survol = true
            ajuster()
        } else {
            let item = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.modele.survol = false
                self.ajuster()
            }
            sortieDuSurvol = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: item)
        }
    }
}
