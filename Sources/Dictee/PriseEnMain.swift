import AppKit
import AVFoundation
import Combine
import SwiftUI
import DicteeCore

/// L'état du premier lancement (maquette lucarne-app-final.html, étapes 1 à 6) : « Bonjour », puis cinq cartes, une question à la
/// fois. La touche fn (et ce que fait la touche 🌐), le micro, l'écriture dans les apps (Accessibilité), la clé Groq, un essai.
@MainActor
final class PriseEnMainModele: ObservableObject {
    enum Etape: Int, CaseIterable { case bonjour = 0, touche, micro, ecrire, cle, essai }

    @Published var etape: Etape = .bonjour
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
    /// Carte de la touche fn, une fois la touche reconnue et réglée : le double appui sert à l'essai, il ne lance pas de dictée.
    var attendDoubleAppui: Bool { etape == .touche && surveillanceOK && !globeAReglerEncore }

    /// La carte est-elle faite (sa pastille verte) ?
    func fait(_ e: Etape) -> Bool {
        switch e {
        case .bonjour: return true
        case .touche: return surveillanceOK && !globeAReglerEncore
        case .micro: return microOK
        case .ecrire: return accessibiliteOK
        case .cle: return cle != .absente && !forcerCle
        case .essai: return reussie
        }
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
        guard let e = Etape(rawValue: etape.rawValue + 1) else { return }
        etape = e
        if e == .essai { jetonFocus += 1 }
    }

    /// Ouvre le volet Clavier des Réglages Système : c'est le seul endroit où le réglage prend effet.
    func ouvrirVoletClavier() {
        guard let url = URL(string: ToucheGlobe.adresseVoletClavier) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Un geste reconnu pendant la carte de la touche fn : seul le double appui compte. Aucune dictée ne démarre pendant cette étape (voir l'aiguillage dans `AppDelegate`).
    func noterGeste(_ action: GestureAction) {
        if action == .begin(handsFree: true) { doubleAppuiVu = true }
    }

    /// Appelé quand une dictée vient d'être collée dans notre propre champ d'essai : la réussite est vérifiée dans le champ.
    func texteInsere(_ texte: String) {
        guard etape == .essai else { return }
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

    func insertionImpossible(_ raison: String) { if etape == .essai { echecInsertion = raison } }
}

/// La carte d'accueil en verre, sous l'encoche (maquette, étapes 1 à 6). « Bonjour » d'abord, puis une carte par question : à gauche
/// une petite scène en mouvement (DicteeCore `IllustrationsAccueil`, `AccueilScenes.swift`), à droite l'étape, le titre, une phrase,
/// et l'action ou la pastille verte quand c'est fait.
struct PriseEnMainVue: View {
    @ObservedObject var m: PriseEnMainModele
    @ObservedObject var apparition: ApparitionPanneau
    var curseurFactice = false
    static let taille = CGSize(width: 680, height: 300)
    static let tailleBonjour = CGSize(width: 420, height: 300)
    @Environment(\.colorScheme) private var schema

    var body: some View {
        let bonjour = m.etape == .bonjour
        let t = bonjour ? Self.tailleBonjour : Self.taille
        Group {
            if bonjour { accueil } else { carte }
        }
        .frame(width: t.width, height: t.height)
        .background {
            // un voile coloré très doux sous le verre, comme sur la maquette (bleu en haut, vert et sable en bas)
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(LinearGradient(colors: schema == .dark ? [Color(hex: 0x1E2A3A).opacity(0.5), Color(hex: 0x1F2E26).opacity(0.4)]
                                                             : [Color(hex: 0xD9E8FB).opacity(0.55), Color(hex: 0xE4F3E9).opacity(0.45)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .verre(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .animation(.spring(duration: 0.5, bounce: 0.15), value: m.etape)
        .offset(y: apparition.visible || apparition.reduire ? 0 : -44)
        .scaleEffect(apparition.visible || apparition.reduire ? 1 : 0.94, anchor: .top)
        .opacity(apparition.visible ? 1 : 0)
        .frame(width: Self.taille.width, height: Self.taille.height + PriseEnMain.ecartHaut, alignment: .bottom)
    }

    // MARK: Bonjour

    private var accueil: some View {
        VStack(spacing: 0) {
            Image(nsImage: IconeApp.image(cote: 256)).resizable().frame(width: 96, height: 96).shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            Text("Bonjour").font(.system(size: 30, weight: .bold)).tracking(-0.6).foregroundStyle(TonsBureau.encre).padding(.top, 12)
            Text("Verbe vit dans l\u{2019}encoche de ton Mac.\nTiens fn, parle\u{202F}: le texte s\u{2019}écrit là où tu es.")
                .font(.system(size: 14.5)).lineSpacing(3).multilineTextAlignment(.center).foregroundStyle(TonsBureau.encre2).padding(.top, 8)
            Button { m.suivant() } label: {
                Text("Commencer").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 230, height: 42).background(Capsule().fill(TonsBureau.bleu)).contentShape(Capsule())
            }
            .buttonStyle(Enfonce()).padding(.top, 20)
            Text("Cinq petites étapes, deux minutes.").font(.system(size: 12.5)).foregroundStyle(TonsBureau.encre3).padding(.top, 12)
        }
        .padding(.top, 8)
    }

    // MARK: une carte

    private var carte: some View {
        let n = m.etape.rawValue
        return HStack(alignment: .top, spacing: 26) {
            IllustrationAccueil(carte: n, actif: apparition.visible)
                .frame(width: 300, height: 256)
                .background(LinearGradient(colors: Self.teinte(n, sombre: schema == .dark), startPoint: .top, endPoint: .bottom))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .id(n)
            VStack(alignment: .leading, spacing: 0) {
                points
                Text("Étape \(n) sur 5").font(.system(size: 13, weight: .semibold)).foregroundStyle(TonsBureau.orange).padding(.top, 14)
                Text(titre).font(.system(size: 26, weight: .bold)).tracking(-0.5).foregroundStyle(TonsBureau.encre).padding(.top, 2)
                Text(phrase).font(.system(size: 14.5)).lineSpacing(3).foregroundStyle(TonsBureau.encre2)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 8)
                action.padding(.top, 16)
                Spacer(minLength: 0)
                pied
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
    }

    /// La teinte douce du fond de chaque scène.
    static func teinte(_ n: Int, sombre: Bool) -> [Color] {
        let clair: [[UInt32]] = [[0xF6EBDD, 0xEBDCC8], [0xFCE9DA, 0xF7DCC7], [0xE3ECF8, 0xD5E2F3], [0xE6F2E3, 0xD6E9D2], [0xFBEEDC, 0xF4E2CB]]
        let fonce: [[UInt32]] = [[0x3A332B, 0x2C2722], [0x3B2F27, 0x2D2520], [0x27303D, 0x1F2631], [0x26332A, 0x1E2922], [0x3A3127, 0x2C2620]]
        return (sombre ? fonce : clair)[max(0, min(4, n - 1))].map { Color(hex: $0) }
    }

    private var points: some View {
        HStack(spacing: 6) {
            ForEach(1...5, id: \.self) { i in
                Capsule().fill(i == m.etape.rawValue ? TonsBureau.encre.opacity(0.62) : (i < m.etape.rawValue ? TonsBureau.vert : TonsBureau.encre.opacity(0.16)))
                    .frame(width: i == m.etape.rawValue ? 20 : 6, height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Étape \(m.etape.rawValue) sur 5")
    }

    private var titre: String {
        switch m.etape {
        case .bonjour: return "Bonjour"
        case .touche: return "La touche fn"
        case .micro: return "Le micro"
        case .ecrire: return "Écrire dans tes apps"
        case .cle: return "La clé Groq"
        case .essai: return "Essaie"
        }
    }

    private var phrase: String {
        switch m.etape {
        case .bonjour: return ""
        case .touche:
            if !m.surveillanceOK { return "Tiens fn, parle, relâche\u{202F}: le texte s\u{2019}écrit au curseur. Pour reconnaître fn, macOS demande «\u{202F}Surveillance de l\u{2019}entrée\u{202F}»." }
            if m.globeAReglerEncore { return "\(ToucheGlobe.phrase(valeur: m.globeValeur)). Pour la laisser à Verbe, choisis «\u{202F}\(ToucheGlobe.consigne)\u{202F}» dans le volet Clavier." }
            return "Tiens fn, parle, relâche\u{202F}: le texte s\u{2019}écrit au curseur. Deux appuis rapides lancent le mode mains libres."
        case .micro:
            return m.microRefuse ? "Le micro est refusé\u{202F}: à rouvrir dans Réglages Système, Confidentialité et sécurité, Micro."
                                 : "Pour t\u{2019}entendre quand tu dictes. Il n\u{2019}écoute que pendant que tu tiens fn, jamais le reste du temps."
        case .ecrire: return "macOS appelle ça «\u{202F}Accessibilité\u{202F}». Verbe s\u{2019}en sert pour poser le texte là où est ton curseur, dans n\u{2019}importe quelle app."
        case .cle: return "Groq écrit ta voix en moins d\u{2019}une seconde. Colle ta clé\u{202F}: elle est rangée dans le Trousseau du Mac."
        case .essai: return "Clique dans le champ, tiens fn, dis une phrase, relâche."
        }
    }

    /// L'action de la carte, ou sa pastille verte quand c'est fait.
    @ViewBuilder private var action: some View {
        switch m.etape {
        case .bonjour: EmptyView()
        case .touche:
            if !m.surveillanceOK { BoutonCapsule(titre: "Autoriser", hauteur: 32) { m.demander(.surveillance) } }
            else if m.globeAReglerEncore { BoutonCapsule(titre: "Ouvrir le volet Clavier", hauteur: 32) { m.ouvrirVoletClavier() } }
            else {
                VStack(alignment: .leading, spacing: 8) {
                    PastilleFaite(texte: "fn est à toi")
                    Text(m.doubleAppuiVu ? "Double appui reconnu, rien d\u{2019}autre ne s\u{2019}est ouvert." : "Essaie\u{202F}: deux appuis rapides sur fn.")
                        .font(.system(size: 12.5)).foregroundStyle(TonsBureau.encre3)
                }
            }
        case .micro:
            if m.microOK { PastilleFaite(texte: "Le micro est prêt") }
            else { BoutonCapsule(titre: m.microRefuse ? "Ouvrir les Réglages" : "Autoriser le micro", hauteur: 32) { m.demander(.micro) } }
        case .ecrire:
            if m.accessibiliteOK { PastilleFaite(texte: "Verbe peut écrire") }
            else { BoutonCapsule(titre: "Autoriser", hauteur: 32) { m.demander(.accessibilite) } }
        case .cle:
            if m.fait(.cle) { PastilleFaite(texte: "Clé enregistrée") } else { champCle }
        case .essai: essai
        }
    }

    private var champCle: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                CleSecrete(texte: $m.saisieCle, invite: "gsk_…") { m.enregistrerCle() }
                    .frame(height: 22)
                    .padding(.horizontal, 12).frame(height: 36)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(TonsBureau.carte))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                BoutonCapsule(titre: "Enregistrer", hauteur: 32) { m.enregistrerCle() }.opacity(m.saisieCle.isEmpty ? 0.5 : 1)
            }
            Text(m.avisCle ?? "Sans clé, seule la dictée du Mac écrit.").font(.system(size: 12)).foregroundStyle(m.avisCle == nil ? TonsBureau.encre3 : TonsBureau.orange)
        }
    }

    private var essai: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(TonsBureau.carte)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                ChampRecherche(texte: $m.essai, invite: "La phrase apparaîtra ici", taille: 14.5, jetonFocus: m.jetonFocus) { _ in false }
                    .padding(.horizontal, 12).frame(height: 44)
                if curseurFactice && m.essai.isEmpty { RoundedRectangle(cornerRadius: 1).fill(TonsBureau.bleu).frame(width: 2, height: 17).offset(x: 12, y: 13) }
            }
            .frame(height: 44)
            if m.reussie { PastilleFaite(texte: "Le texte est écrit. Tout est prêt.") }
            else if let echec = m.echecInsertion { Text(echec).font(.system(size: 12.5)).foregroundStyle(TonsBureau.orange) }
        }
    }

    // MARK: pied

    private var pied: some View {
        HStack {
            if !(m.etape == .essai && m.reussie) {
                Button("Passer", action: m.surPasser).buttonStyle(.plain).font(.system(size: 13, weight: .medium)).foregroundStyle(TonsBureau.encre3)
            }
            Spacer()
            switch m.etape {
            case .essai: BoutonCapsule(titre: "Terminer", hauteur: 32) { if m.reussie { m.surTerminer() } }.opacity(m.reussie ? 1 : 0.4)
            case .cle where !m.fait(.cle): Button("Plus tard") { m.suivant() }.buttonStyle(.plain).font(.system(size: 13, weight: .medium)).foregroundStyle(TonsBureau.bleu)
            default:
                BoutonCapsule(titre: "Continuer", style: m.fait(m.etape) ? .plein : .doux, hauteur: 32) { m.suivant() }
            }
        }
        .frame(height: 32)
    }
}

/// « ✓ Le micro est prêt » : la pastille verte d'une carte faite.
struct PastilleFaite: View {
    var texte: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
                .frame(width: 22, height: 22).background(Circle().fill(TonsBureau.vert))
            Text(texte).font(.system(size: 14.5, weight: .semibold)).foregroundStyle(Color(clair: 0x1F7A3A, sombre: 0x5BE584))
        }
        .padding(.leading, 6).padding(.trailing, 14).frame(height: 36)
        .background(Capsule().fill(TonsBureau.vert.opacity(0.16)))
        .accessibilityElement(children: .combine)
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

/// Le premier lancement : une carte en verre sous l'encoche (comme celle des AirPods sur l'iPhone).
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

    /// `etape` : `.cle` pour « Modifier la clé » depuis les Réglages.
    func ouvrir(etape: PriseEnMainModele.Etape = .bonjour, forcerCle: Bool = false) {
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
            // le verre suit l'apparence du Mac (clair ou sombre), comme les cartes du système
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
        abonnement = modele.$etape.dropFirst().sink { [weak self] e in if e == .essai { self?.reactiver() } }
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
