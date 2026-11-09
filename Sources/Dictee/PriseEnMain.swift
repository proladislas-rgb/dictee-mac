import AppKit
import AVFoundation
import Combine
import SwiftUI
import DicteeCore

/// L'état du premier lancement : le geste, les accès, la touche 🌐 (seulement si elle fait autre chose que « Ne rien faire »)
/// et une première dictée réussie.
@MainActor
final class PriseEnMainModele: ObservableObject {
    enum Etape: Int { case geste = 1, acces, globe, premiere }

    @Published var etape: Etape = .geste
    @Published private(set) var microOK = false
    @Published private(set) var microRefuse = false
    @Published private(set) var accessibiliteOK = false
    @Published private(set) var surveillanceOK = false
    @Published private(set) var cle: CleGroq.Etat = .absente
    /// Réglage « Appuyer sur 🌐 pour » (`AppleFnUsageType`) ; `nil` = clé absente (réglage d'origine, qui fait quelque chose).
    @Published private(set) var globeValeur: Int?
    /// Le double appui d'essai a été reconnu (étape de la touche 🌐).
    @Published private(set) var doubleAppuiVu = false
    /// Même si une clé existe, montrer le champ (« Modifier » dans les Réglages).
    @Published var forcerCle = false
    @Published var saisieCle = ""
    @Published var avisCle: String?
    /// Texte du champ d'essai de la dernière étape.
    @Published var essai = ""
    /// Vrai quand un texte dicté a réellement été inséré dans le champ d'essai.
    @Published private(set) var reussie = false
    @Published private(set) var echecInsertion: String?
    @Published var jetonFocus = 0
    private let reel: Bool

    var surTerminer: () -> Void = {}
    var surPasser: () -> Void = {}

    var globeAReglerEncore: Bool { ToucheGlobe.doitEtreReglee(valeur: globeValeur) }
    /// Pendant l'étape 🌐, une fois la touche réglée : le double appui sert à l'essai, il ne lance pas de dictée.
    var attendDoubleAppui: Bool { etape == .globe && !globeAReglerEncore }

    /// Les étapes montrées : celle de la touche 🌐 n'existe que si elle est à régler (ou si on y est déjà).
    var etapesMontrees: [Etape] {
        [.geste, .acces] + (etape == .globe || globeAReglerEncore ? [.globe] : []) + [.premiere]
    }

    var accesCompletsOK: Bool { microOK && accessibiliteOK && surveillanceOK }
    var accesManquants: String {
        var m: [String] = []
        if !microOK { m.append("le micro") }
        if !accessibiliteOK { m.append("l\u{2019}accessibilité") }
        if !surveillanceOK { m.append("la surveillance de l\u{2019}entrée") }
        return m.isEmpty ? "" : "Il manque " + m.joined(separator: ", ") + "."
    }

    /// `reel = false` : valeurs d'exemple, aucun accès au système (rendus PNG).
    init(reel: Bool = true, micro: Bool = false, accessibilite: Bool = false, surveillance: Bool = false, cle: CleGroq.Etat = .absente, globe: Int? = 0) {
        self.reel = reel
        microOK = micro; accessibiliteOK = accessibilite; surveillanceOK = surveillance; self.cle = cle; globeValeur = globe
        if reel { rafraichir() }
    }

    /// Relit les autorisations (détection automatique : appelé chaque seconde tant que la fenêtre est là).
    func rafraichir() {
        guard reel else { return }
        microOK = Permissions.microOK
        microRefuse = Permissions.microStatut == .denied || Permissions.microStatut == .restricted
        accessibiliteOK = Permissions.accessibiliteOK
        surveillanceOK = Permissions.surveillanceOK
        cle = CleGroq.etat
        globeValeur = ToucheGlobe.lire()
    }

    func demander(_ volet: Permissions.Volet) {
        Task { @MainActor in
            await Permissions.demander(volet)
            rafraichir()
        }
    }

    func enregistrerCle() {
        let saisie = saisieCle
        guard CleGroq.vraisemblable(saisie) else { avisCle = "Cette clé ne ressemble pas à une clé Groq."; return }
        if CleGroq.enregistrer(saisie) {
            GroqClient.shared.recharger()
            saisieCle = ""; forcerCle = false; avisCle = nil
            rafraichir()
        } else {
            avisCle = "Le Trousseau a refusé l\u{2019}enregistrement."
        }
    }

    func suivant() {
        var n = etape.rawValue + 1
        if Etape(rawValue: n) == .globe, !globeAReglerEncore { n += 1 }   // déjà sur « Ne rien faire » : rien à guider
        if let e = Etape(rawValue: n) { etape = e; if e == .premiere { jetonFocus += 1 } }
    }

    /// Ouvre le volet Clavier des Réglages Système : c'est le seul endroit où le réglage prend effet.
    func ouvrirVoletClavier() {
        guard let url = URL(string: ToucheGlobe.adresseVoletClavier) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Un geste reconnu pendant l'étape 🌐 : seul le double appui compte. Aucune dictée ne démarre pendant cette étape (voir l'aiguillage dans `AppDelegate`).
    func noterGeste(_ action: GestureAction) {
        if action == .begin(handsFree: true) { doubleAppuiVu = true }
    }

    /// Appelé quand une dictée vient d'être collée dans notre propre champ d'essai : la réussite est vérifiée dans le champ.
    func texteInsere(_ texte: String) {
        guard etape == .premiere else { return }
        // le collage est asynchrone côté champ : on laisse un instant avant de lire ce qu'il contient
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self else { return }
            let attendu = texte.trimmingCharacters(in: .whitespacesAndNewlines)
            if !attendu.isEmpty, self.essai.contains(attendu.prefix(max(1, min(12, attendu.count)))) {
                self.reussie = true; self.echecInsertion = nil
            } else {
                self.echecInsertion = "Le texte n\u{2019}est pas arrivé dans le champ."
            }
        }
    }

    /// Rendus PNG seulement : poser des états qui viennent normalement du système ou d'une vraie dictée.
    func setEtatPourRendu(refuse: Bool, reussie: Bool, echec: String?, doubleAppuiVu: Bool = false) {
        microRefuse = refuse; self.reussie = reussie; echecInsertion = echec; self.doubleAppuiVu = doubleAppuiVu
    }

    func insertionImpossible(_ raison: String) { if etape == .premiere { echecInsertion = raison } }
}

struct PriseEnMainVue: View {
    @ObservedObject var m: PriseEnMainModele
    @ObservedObject var apparition: ApparitionPanneau
    var curseurFactice = false
    static let taille = CGSize(width: 440, height: 440)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\((m.etapesMontrees.firstIndex(of: m.etape) ?? 0) + 1) sur \(m.etapesMontrees.count)").font(Polices.commande(12)).foregroundStyle(Palette.texte3).padding(.bottom, 14)
            Group {
                switch m.etape {
                case .geste: geste
                case .acces: acces
                case .globe: globe
                case .premiere: premiere
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            pied
        }
        .padding(24)
        .frame(width: Self.taille.width, height: Self.taille.height)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        .offset(y: apparition.visible || apparition.reduire ? 0 : -44)
        .scaleEffect(apparition.visible || apparition.reduire ? 1 : 0.97, anchor: .top)
        .opacity(apparition.visible ? 1 : 0)
        .frame(width: Self.taille.width, height: Self.taille.height + PriseEnMain.ecartHaut, alignment: .bottom)
    }

    // MARK: étape 1

    private var geste: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 10) { Text("Maintenez"); ToucheFn().scaleEffect(1.25).padding(.leading, 4); Text(".") .padding(.leading, -8) }
                Text("Parlez.")
                HStack(spacing: 4) {
                    Text("Relâchez.")
                    RoundedRectangle(cornerRadius: 1).fill(Palette.accent).frame(width: 2, height: 26).opacity(curseurFactice ? 1 : 1)
                }
            }
            .font(Polices.texte(30)).foregroundStyle(Palette.texte)
            .accessibilityElement(children: .ignore).accessibilityLabel("Maintenez fn. Parlez. Relâchez.")
            Text("Le texte s\u{2019}écrit là où se trouve le curseur, dans n\u{2019}importe quelle app. Deux appuis sur fn lancent le mode mains libres.")
                .font(Polices.commande(13)).foregroundStyle(Palette.texte2).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: étape 2

    private var acces: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Trois accès à accorder").font(Polices.texte(22)).foregroundStyle(Palette.texte).padding(.bottom, 6)
            Text("Le micro n\u{2019}écoute que pendant que fn est tenue.").font(Polices.commande(13)).foregroundStyle(Palette.texte2).padding(.bottom, 10)
            ligneAcces("Micro", "Pour entendre la voix.", ok: m.microOK, refuse: m.microRefuse, volet: .micro)
            ligneAcces("Accessibilité", "Pour écrire le texte là où est le curseur.", ok: m.accessibiliteOK, refuse: false, volet: .accessibilite)
            ligneAcces("Surveillance de l\u{2019}entrée", "Pour reconnaître la touche fn.", ok: m.surveillanceOK, refuse: false, volet: .surveillance)
            if m.cle == .absente || m.forcerCle { cle.padding(.top, 10) }
            Spacer(minLength: 0)
        }
    }

    private func ligneAcces(_ titre: String, _ detail: String, ok: Bool, refuse: Bool, volet: Permissions.Volet) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(titre).font(Polices.commande(14)).foregroundStyle(Palette.texte)
                Text(refuse ? "Refusé : à rouvrir dans les Réglages Système." : detail).font(Polices.commande(12)).foregroundStyle(Palette.texte3)
            }
            Spacer(minLength: 8)
            if ok {
                HStack(spacing: 6) { Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)); Text("Accordé") }
                    .font(Polices.commande(13)).foregroundStyle(Palette.texte2)
            } else {
                LienTexte(titre: refuse ? "Ouvrir les Réglages" : "Autoriser", fort: true) { m.demander(volet) }
            }
        }
          .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityValue(ok ? "accordé" : "non accordé")
    }

    private var cle: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Clé Groq").font(Polices.commande(14)).foregroundStyle(Palette.texte)
            HStack(spacing: 12) {
                CleSecrete(texte: $m.saisieCle, invite: "Collez la clé ici") { m.enregistrerCle() }
                    .frame(height: 24)
                    .overlay(alignment: .bottom) { Rectangle().fill(Palette.filet).frame(height: 1).offset(y: 3) }
                LienTexte(titre: "Enregistrer", fort: !m.saisieCle.isEmpty) { m.enregistrerCle() }
            }
            Text(m.avisCle ?? "Rangée dans le Trousseau. Sans clé, seule la dictée d\u{2019}Apple écrit.")
                .font(Polices.commande(12)).foregroundStyle(Palette.texte3).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: étape 🌐

    private var globe: some View {
        VStack(alignment: .leading, spacing: 12) {
            if m.globeAReglerEncore {
                Text(ToucheGlobe.phrase(valeur: m.globeValeur)).font(Polices.texte(22)).foregroundStyle(Palette.texte)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Elle se déclenche en même temps que fn : le double appui de Verbe ouvrirait aussi cette action.")
                    .font(Polices.commande(13)).foregroundStyle(Palette.texte2).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Dans le volet Clavier, choisissez :").font(Polices.commande(13)).foregroundStyle(Palette.texte2)
                    Text("\u{00AB}\u{202F}\(ToucheGlobe.consigne)\u{202F}\u{00BB}").font(Polices.texte(16)).foregroundStyle(Palette.texte)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 4)
                LienTexte(titre: "Ouvrir le volet Clavier", fort: true) { m.ouvrirVoletClavier() }.padding(.top, 4)
                Text("Cette étape se termine toute seule dès que le réglage est changé.").font(Polices.commande(12)).foregroundStyle(Palette.texte3)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Votre touche 🌐 est réglée").font(Polices.texte(22)).foregroundStyle(Palette.texte)
                Text("Essayez : appuyez deux fois, vite, sur fn. Rien d\u{2019}autre ne doit s\u{2019}ouvrir.")
                    .font(Polices.commande(13)).foregroundStyle(Palette.texte2).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    ToucheFn()
                    ToucheFn()
                }
                .padding(.vertical, 8)
                if m.doubleAppuiVu {
                    HStack(spacing: 6) { Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)); Text("Double appui reconnu.") }
                        .font(Polices.commande(13)).foregroundStyle(Palette.texte)
                } else {
                    Text("En attente du double appui.").font(Polices.commande(13)).foregroundStyle(Palette.texte3)
                }
            }
        }
    }

    // MARK: dernière étape

    private var premiere: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Une première dictée").font(Polices.texte(22)).foregroundStyle(Palette.texte)
            Text("Cliquez dans le champ, maintenez fn, dites une phrase, relâchez.").font(Polices.commande(13)).foregroundStyle(Palette.texte2)
                .fixedSize(horizontal: false, vertical: true)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8).fill(Palette.selection.opacity(0.55))
                ChampRecherche(texte: $m.essai, invite: "La phrase apparaîtra ici", taille: 15, jetonFocus: m.jetonFocus) { _ in false }
                    .padding(.horizontal, 12).frame(height: 56)
                if curseurFactice && m.essai.isEmpty { RoundedRectangle(cornerRadius: 1).fill(Palette.accent).frame(width: 2, height: 17).offset(x: 10, y: 19) }
            }
            .frame(height: 56)
            if m.reussie {
                Text("Le texte est écrit. Verbe est prêt.").font(Polices.commande(13)).foregroundStyle(Palette.texte)
            } else if let echec = m.echecInsertion {
                Text(echec).font(Polices.commande(13)).foregroundStyle(Palette.texte2)
            } else {
                Text("En attente de la dictée.").font(Polices.commande(13)).foregroundStyle(Palette.texte3)
            }
        }
    }

    // MARK: pied

    private var pied: some View {
        HStack {
            if m.etape != .premiere || !m.reussie { LienTexte(titre: "Passer", action: m.surPasser) }
            Spacer()
            switch m.etape {
            case .geste: LienTexte(titre: "Continuer", fort: true) { m.suivant() }
            case .acces:
                if !m.accesCompletsOK { Text(m.accesManquants).font(Polices.commande(12)).foregroundStyle(Palette.texte3).padding(.trailing, 12) }
                LienTexte(titre: "Continuer", fort: m.accesCompletsOK) { if m.accesCompletsOK { m.suivant() } }.opacity(m.accesCompletsOK ? 1 : 0.35)
            case .globe:
                if m.globeAReglerEncore { LienTexte(titre: "Plus tard") { m.suivant() } }
                else { LienTexte(titre: "Continuer", fort: m.doubleAppuiVu) { m.suivant() } }
            case .premiere: LienTexte(titre: "Terminer", fort: m.reussie) { if m.reussie { m.surTerminer() } }.opacity(m.reussie ? 1 : 0.35)
            }
        }
        .frame(height: 28)
    }
}

/// Champ pour la clé : les caractères restent masqués.
struct CleSecrete: NSViewRepresentable {
    @Binding var texte: String
    var invite: String
    var surEntree: () -> Void

    func makeCoordinator() -> Coordinateur { Coordinateur(self) }
    func makeNSView(context: Context) -> NSSecureTextField {
        let c = NSSecureTextField()
        c.isBordered = false; c.drawsBackground = false; c.focusRingType = .none
        c.font = .systemFont(ofSize: 14); c.textColor = Palette.nsTexte
        c.placeholderAttributedString = NSAttributedString(string: invite, attributes: [.foregroundColor: Palette.nsTexte3, .font: NSFont.systemFont(ofSize: 14)])
        c.delegate = context.coordinator
        return c
    }
    func updateNSView(_ c: NSSecureTextField, context: Context) {
        context.coordinator.parent = self
        if c.stringValue != texte { c.stringValue = texte }
    }
    @MainActor final class Coordinateur: NSObject, NSTextFieldDelegate {
        var parent: CleSecrete
        init(_ p: CleSecrete) { parent = p }
        func controlTextDidChange(_ n: Notification) { if let c = n.object as? NSTextField, parent.texte != c.stringValue { parent.texte = c.stringValue } }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy s: Selector) -> Bool {
            if s == #selector(NSResponder.insertNewline(_:)) { parent.surEntree(); return true }
            return false
        }
    }
}

/// Le premier lancement : un panneau sous l'encoche, même surface sombre que le panneau compact.
@MainActor
final class PriseEnMain {
    static let ecartHaut: CGFloat = 36
    let modele = PriseEnMainModele()
    let apparition = ApparitionPanneau()
    private var fenetre: PanneauClavier?
    private var minuteur: Timer?
    private var abonnement: AnyCancellable?
    var surFin: () -> Void = {}
    /// Appelé quand la fenêtre apparaît ou disparaît (la lecture en cours s'efface pendant la prise en main).
    var surChangementEtat: () -> Void = {}

    var estOuvert: Bool { fenetre?.isVisible == true }

    /// `etape` : 2 pour « Modifier la clé » depuis les Réglages.
    func ouvrir(etape: PriseEnMainModele.Etape = .geste, forcerCle: Bool = false) {
        guard let ecran = NSScreen.screens.first else { return }
        modele.etape = etape
        modele.forcerCle = forcerCle
        modele.rafraichir()
        modele.surPasser = { [weak self] in self?.fermer(fait: true) }
        modele.surTerminer = { [weak self] in self?.fermer(fait: true) }
        apparition.reduire = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        let (g, centre) = GeometrieEncoche.mesurer(ecran)
        let taille = CGSize(width: PriseEnMainVue.taille.width, height: PriseEnMainVue.taille.height + Self.ecartHaut)
        let cadre = NSRect(x: centre - taille.width / 2, y: ecran.frame.maxY - g.hauteur - taille.height, width: taille.width, height: taille.height)
        if fenetre == nil {
            let f = PanneauClavier(contentRect: cadre, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            f.isOpaque = false; f.backgroundColor = .clear; f.hasShadow = false
            f.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
            f.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            f.hidesOnDeactivate = false; f.isMovable = false; f.animationBehavior = .none
            f.appearance = NSAppearance(named: .darkAqua)
            let vue = NSHostingView(rootView: PriseEnMainVue(m: modele, apparition: apparition))
            vue.frame = NSRect(origin: .zero, size: taille)
            f.contentView = vue
            fenetre = f
        }
        guard let f = fenetre else { return }
        f.setFrame(cadre, display: false)
        // L'app est activée : la dernière étape écrit dans le champ d'essai de ce panneau, pas dans une autre app.
        NSApp.activate(ignoringOtherApps: true)
        f.orderFrontRegardless()
        f.makeKey()
        withAnimation(apparition.reduire ? .easeOut(duration: GeometrieEncoche.dureeFondu) : .spring(duration: GeometrieEncoche.dureeMouvement, bounce: 0.1)) { apparition.visible = true }
        abonnement = modele.$etape.dropFirst().sink { [weak self] e in if e == .premiere { self?.reactiver() } }
        minuteur?.invalidate()
        minuteur = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.modele.rafraichir() }
        }
        Log.ecrire("prise en main ouverte (étape \(etape.rawValue))")
        surChangementEtat()
    }

    /// À l'entrée de la dernière étape, ou au clic dans le champ : l'app redevient active pour que ⌘V arrive dans le champ.
    func reactiver() { NSApp.activate(ignoringOtherApps: true); fenetre?.makeKey() }

    func fermer(fait: Bool) {
        minuteur?.invalidate(); minuteur = nil
        if fait { Settings.premierLancementFait = true }
        let f = fenetre
        withAnimation(apparition.reduire ? .easeOut(duration: GeometrieEncoche.dureeFondu) : .spring(duration: GeometrieEncoche.dureeMouvement, bounce: 0)) { apparition.visible = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + GeometrieEncoche.dureeMouvement + 0.08) { [weak self] in
            guard let self, !self.apparition.visible else { return }
            f?.orderOut(nil)
            self.surChangementEtat()
        }
        Log.ecrire("prise en main fermée (fait = \(fait))")
        surFin()
    }
}
