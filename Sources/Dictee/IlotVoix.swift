import AppKit
import SwiftUI
import DicteeCore

// La voix d'un rappel ou d'une note dans l'îlot (maquette design/maquettes/ilot-voix-rappel.html, demande de Hugues du 12/11 ; la logique
// pure dans DicteeCore/VoixIlot.swift).
// - fn tenue, « Voxile, rappelle-moi… » ou « Voxile, note… » reconnu dans le texte en direct : l'encoche de la dictée se range et l'îlot
//   prend la dictée. L'onde suit la voix (le vrai niveau du micro, sur des ressorts) ; dès que la commande est comprise, l'îlot grandit d'une
//   ligne et « Rappel… » (orange) ou « Note… » (jaune) arrive dessous. Les annonces qui arrivent pendant ce temps attendent, comme pendant
//   une dictée.
// - fn relâchée : l'onde se calme ; puis la carte de fin, en morphing de l'îlot : coché, titre, jour et heure, la phrase entendue (un
//   rappel) ou le titre et la note (une note), « Envoyer dans Rappels » / « Envoyer dans Notes », et « Annuler » / « Copier ».
// - Rappels : le rappel est toujours gardé dans Lucarne (il sonne ici). Il part tout seul dans l'app Rappels si Hugues l'a déjà voulu une
//   fois et que l'accès est donné (la carte dit alors « ✓ Dans Rappels ») ; sinon la carte propose le bouton, et un clic vaut le « Oui »
//   d'avant (la fenêtre de macOS la première fois). Accès refusé : « Autoriser dans Réglages » ouvre le bon volet.
// - Notes : la note est gardée dans la carte Note rapide ; « Envoyer dans Notes » passe par le même AppleScript que « Vers Notes » des Outils
//   (`envoyerNoteVersNotes`) : macOS demande l'autorisation (Automatisation) au premier clic, jamais avant.
// Rien ne tourne au repos : l'onde n'a d'horloge que pendant l'écoute. L'essai remplace l'app Rappels et l'app Notes par des faux.

// MARK: - l'état

/// La voix d'une dictée prise par l'îlot : la phase, le genre compris, l'onde, puis la carte de fin et son bouton.
@MainActor
final class EcouteVoix: ObservableObject {
    enum Phase: Equatable { case repos, ecoute, attente }
    @Published var phase: Phase = .repos
    /// Rappel ou note, dès que c'est compris (nil : pas encore) ; gardé pendant que l'écoute s'efface.
    @Published var genre: GenreVoix?
    /// L'onde : lue à chaque image par sa propre horloge (pas publiée : le niveau change 20 fois par seconde, seule l'onde le suit).
    var onde = OndeVoix()
    /// La dictée prise (son numéro) : une fin qui arrive d'une autre dictée ne touche à rien.
    var session: Int?
    /// La carte de fin (gardée pendant qu'elle s'efface : l'écran qui part garde son texte) ; ses lignes de résumé, mesurées une fois.
    @Published var carte: CarteVoix?
    var lignesResume = 0
    /// L'envoi d'un rappel vers l'app Rappels (celui d'une note se lit dans `IlotMoteur.envoisNotes`, comme dans la carte Note rapide).
    @Published var envoiRappel: EnvoiVoix = .aEnvoyer
    /// « Copier » vient d'être cliqué : « Copié ».
    @Published var copie = false
    /// Le filet de l'attente : si la dictée ne disait jamais comment elle finit, l'onde s'en irait quand même (la carte, elle, viendrait).
    var filet: DispatchWorkItem?
    /// Rendus PNG : l'instant de l'onde (horloge de l'onde) ; nil : l'horloge réelle.
    var instantFige: Double?

    /// La carte de fin est à l'écran (posé et retiré par le moteur, au changement de bandeau).
    var carteAffichee = false
    /// L'îlot tient une dictée ou sa carte : les annonces attendent (aucun son pendant qu'on parle, rien ne recouvre l'onde ni la carte),
    /// puis passent quand la carte s'en va.
    var retient: Bool { phase != .repos || carteAffichee }
    /// L'horloge de l'onde : monotone (l'essai décale l'heure murale, jamais celle-ci).
    static func horloge() -> Double { ProcessInfo.processInfo.systemUptime }
}

/// Ce que la carte de fin demande au contrôleur.
enum ActionVoix: Equatable {
    /// « Envoyer dans Rappels / Notes » (ou « Autoriser dans Réglages »).
    case envoyer
    /// « Annuler » (un rappel) : retiré de Lucarne et de l'app Rappels.
    case annuler
    /// « Copier » (une note) : la note entière dans le presse-papiers.
    case copier
}

extension IlotMoteur {
    /// L'îlot prend la dictée : l'écoute, sans fin (elle part avec la dictée), devant ce qui était affiché.
    func montrerEcouteVoix() {
        bandeau = BandeauIlot(vue: .voixEcoute, jusqua: .distantFuture, ligne1: "", ligne2: "")
        fermer()
    }
    /// Ce que l'écoute et la carte ajoutent à leur hauteur : la ligne du libellé, le résumé (0 à 2 lignes, mesurées une fois).
    var hauteursVoix: [VueIlot: CGFloat] {
        var d: [VueIlot: CGFloat] = [:]
        if voix.genre != nil { d[.voixEcoute] = CGFloat(MesuresVoix.ligneLibelle) }
        if let c = voix.carte {
            d[.voixCarte] = CGFloat(MesuresVoix.profondeurCarte(quand: c.quand != nil, lignesResume: voix.lignesResume) - MesuresVoix.profondeurCarteMax)
        }
        return d
    }
    /// La carte de fin à montrer : ses lignes de résumé mesurées une fois (la hauteur de la forme les suit), « Copier » remis à zéro.
    func preparerCarteVoix(_ c: CarteVoix) {
        voix.carte = c; voix.copie = false
        let largeur = PlanVoix.largeurTexte(demiCamera: demiCamera)
        voix.lignesResume = c.resume.isEmpty ? 0 : min(MesuresVoix.lignesResumeMax(c.genre), MesureIlot.lignes(c.resume, PlanVoix.tailleResume, .medium, largeur: largeur))
    }
    /// Le bandeau vient de changer : la carte arrive (les annonces attendent derrière elle) ou s'en va (expirée, « Annuler », rangée) :
    /// ce qui attendait passe, au tour suivant (après ce changement, pas au milieu).
    func carteVoixChange(avant: BandeauIlot?) {
        let avantCarte = avant?.vue == .voixCarte, carte = bandeau?.vue == .voixCarte
        guard avantCarte != carte else { return }
        voix.carteAffichee = carte
        if !carte { DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.vidangerAttente() } } }
    }
    /// L'état du bouton d'envoi de la carte.
    var envoiVoix: EnvoiVoix {
        guard let c = voix.carte else { return .aEnvoyer }
        switch c.objet {
        case .rappel: return voix.envoiRappel
        case .note(let id):
            switch envoisNotes[id] {
            case .enCours?: return .enCours
            case .refuse?: return .refuse
            case .fait?: return .fait
            case nil: return notes.first { $0.id == id }?.versNotes == true ? .fait : .aEnvoyer
            }
        }
    }
}

// MARK: - le contrôleur

extension IlotControleur {
    /// La carte reste 8 s (le temps de lire et de cliquer ; la souris dessus la garde) ; un rappel envoyé la raccourcit à 2,5 s.
    static let dureeCarteVoix: TimeInterval = 8
    static let dureeApresEnvoi: TimeInterval = 2.5
    /// Le filet de l'attente : la plus longue dictée prend quelques secondes à s'écrire ; au-delà, l'onde s'en va.
    static let filetVoix: TimeInterval = 20
    static let reglagesRappels = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")!
    static let reglagesAutomatisation = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!

    /// Le texte en direct d'une dictée fn tenue. Vrai : l'îlot l'a prise (ou la tient déjà : le genre peut arriver). Jamais par-dessus
    /// une alerte, une réunion, une autre annonce de l'encoche, ni la note dictée d'un clic (elle a sa carte).
    func voixEnDirect(session: Int, texte: String) -> Bool {
        let v = moteur.voix
        let lu = AnalyseCommandeIlot.directVoix(texte, maintenant: maintenant())
        if v.session == session, v.phase == .ecoute {
            if v.genre == nil, case .pourLucarne(let g?) = lu { v.genre = g; moteur.donneesChangees(); Log.ecrire("voix : genre compris (\(g.rawValue))") }
            return true
        }
        // ni pendant une question de macOS posée depuis le Centre (Téléchargements, captures, calendrier) : le Centre resterait ouvert
        guard v.phase == .repos, !noteParClic, moteur.alerte == nil, moteur.reunion == nil, moteur.annonceReunion == nil, !moteur.masque,
              !moteur.telechargementsAttente, !moteur.capturesAttente, !moteur.calendrierAttente,
              case .pourLucarne(let g) = lu else { return false }
        v.filet?.cancel(); v.filet = nil
        v.session = session; v.genre = g; v.onde = OndeVoix(); v.phase = .ecoute
        // l'encoche de la dictée se range juste après (le contrôleur de la dictée) : sa fermeture relit les masques (`occupationChangee`)
        moteur.montrerEcouteVoix()
        Log.ecrire("voix : l'îlot prend la dictée (\(g?.rawValue ?? "genre pas encore compris"))")
        return true
    }

    /// Le niveau du micro (vingt fois par seconde) pendant l'écoute.
    func niveauDeVoix(_ n: Float) {
        guard moteur.voix.phase == .ecoute else { return }
        moteur.voix.onde.recevoir(Double(n), a: EcouteVoix.horloge())
    }

    /// fn relâchée : l'onde se calme, la petite vague attend le texte (un filet la retire si rien ne vient).
    func relacherVoix() {
        let v = moteur.voix
        guard v.phase == .ecoute else { return }
        v.phase = .attente
        v.onde.relacher(a: EcouteVoix.horloge())
        let session = v.session
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.moteur.voix.session == session, self.moteur.voix.phase == .attente else { return }
                Log.ecrire("voix : rien n'est venu en \(Int(Self.filetVoix)) s, l'onde s'en va")
                self.terminerVoix()
            }
        }
        v.filet = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.filetVoix, execute: item)
    }

    /// La dictée prise par l'îlot a fini (texte collé, rien entendu, annulée…) sans carte : l'onde s'en va, ce qui attendait passe.
    /// Après une carte (ou un second appel), rien à faire.
    func finDeVoix(session: Int) {
        guard moteur.voix.session == session, moteur.voix.phase != .repos else { return }
        Log.ecrire("voix : la dictée prise par l'îlot finit sans carte (texte collé, rien entendu ou annulée)")
        terminerVoix()
    }

    private func terminerVoix() {
        let v = moteur.voix
        v.filet?.cancel(); v.filet = nil
        v.phase = .repos
        if moteur.bandeau?.vue == .voixEcoute { moteur.bandeau = nil }
        moteur.vidangerAttente()
        moteur.donneesChangees()
        occupationChangee()
    }

    /// « Voxile, rappelle-moi… » : le rappel vient d'être gardé. Il part dans l'app Rappels si Hugues l'a déjà voulu (et que l'accès est
    /// donné) ; la carte montre où il en est.
    func montrerCarteRappel(_ r: Rappel, phrase: String) {
        if PlanCarteRappel.envoyerTout(choix: reglagesCentre.choixRappelsApple(), acces: rappelsApple.acces) { creerDansRappelsApple([r], annoncer: false) }
        moteur.voix.envoiRappel = EnvoiVoix.rappel(lie: rappels.rappel(r.id)?.idApple != nil, acces: rappelsApple.acces)
        montrerCarte(CarteVoix.rappel(id: r.id, texte: r.texte, echeance: r.echeance, phrase: phrase, maintenant: maintenant()))
    }

    /// « Voxile, note… » : la note vient d'être gardée (carte Note rapide) ; la carte propose de l'envoyer dans Notes.
    func montrerCarteNote(_ n: NoteRapide) {
        montrerCarte(CarteVoix.note(id: n.id, texte: n.texte))
    }

    /// La carte remplace l'écoute (jamais les deux à la fois) ; ce qui attendait la fin de la dictée passe quand elle s'en va.
    private func montrerCarte(_ c: CarteVoix) {
        let v = moteur.voix
        v.filet?.cancel(); v.filet = nil
        moteur.preparerCarteVoix(c)
        v.phase = .repos
        if moteur.bandeau?.vue == .voixEcoute { moteur.bandeau = nil }
        annoncerTout(BandeauIlot(vue: .voixCarte, jusqua: maintenant().addingTimeInterval(Self.dureeCarteVoix), ligne1: c.titre, ligne2: ""))
        Log.ecrire("voix : carte de fin (\(c.genre.rawValue), \(moteur.envoiVoix == .fait ? "déjà dans \(c.genre.app)" : "à envoyer"))")
    }

    func agirVoix(_ a: ActionVoix) {
        guard let c = moteur.voix.carte, moteur.bandeau?.vue == .voixCarte else { return }
        switch (a, c.objet) {
        case (.envoyer, .rappel(let id)): envoyerRappel(id)
        case (.envoyer, .note(let id)):
            // refusé : le volet Automatisation ; au clic suivant (autorisé entre-temps), Notes est réessayé
            if moteur.envoiVoix == .refuse { ouvrir(Self.reglagesAutomatisation); moteur.envoisNotes[id] = nil; return }
            guard moteur.envoiVoix == .aEnvoyer else { return }
            // l'AppleScript de « Vers Notes » (Outils) : Notes peut mettre quelques secondes à s'ouvrir, la carte attend
            agirOutils(.noteVersNotes(id))
            prolongerCarte(Self.dureeCarteVoix)
        case (.annuler, .rappel(let id)):
            Log.ecrire("voix : rappel annulé depuis la carte")
            agir(.rappelAnnuler(id))
        case (.copier, .note(let id)):
            guard let n = listeNotes.note(id) else { return }
            copier(n.texte)
            moteur.voix.copie = true
            prolongerCarte(Self.dureeApresEnvoi)   // jamais moins qu'avant (un envoi vers Notes peut être en route)
            Log.ecrire("voix : note copiée (\(n.texte.count) caractères)")
        default: break
        }
    }

    /// « Envoyer dans Rappels » : ce rappel-là part (la fenêtre de macOS la première fois) ; une fois parti, le clic vaut le « Oui »
    /// d'avant (les rappels suivants partiront seuls). Refusé : le volet des Réglages (l'état est relu à chaque clic).
    private func envoyerRappel(_ id: UUID) {
        guard let r = rappels.rappel(id), r.idApple == nil, moteur.voix.envoiRappel != .enCours else { return }
        switch rappelsApple.acces {
        case .refuse:
            ouvrir(Self.reglagesRappels)
            rappelEnvoye(id)
            Log.ecrire("voix : accès à l'app Rappels refusé, le volet des Réglages est ouvert")
        case .autorise:
            creerDansRappelsApple([r], annoncer: false)
            rappelEnvoye(id)
        case .nonDemande:
            moteur.voix.envoiRappel = .enCours
            prolongerCarte(Self.dureeCarteVoix)
            rappelsApple.demander { [weak self] accorde in
                guard let self else { return }
                if accorde, let r = self.rappels.rappel(id) { self.creerDansRappelsApple([r], annoncer: false) }
                else { Log.ecrire("voix : l'app Rappels refusée dans la fenêtre de macOS, le rappel reste dans Lucarne") }
                self.rappelEnvoye(id)
            }
        }
    }
    /// Après un clic : l'état relu ; parti, c'est le « Oui » (enregistré) et la carte part 2,5 s plus tard ; sinon elle reste le temps
    /// de lire le refus.
    private func rappelEnvoye(_ id: UUID) {
        let lie = rappels.rappel(id)?.idApple != nil
        if lie { reglagesCentre.enregistrerChoixRappelsApple(.oui) }
        moteur.voix.envoiRappel = EnvoiVoix.rappel(lie: lie, acces: rappelsApple.acces)
        prolongerCarte(Self.dureeApresEnvoi, raccourcir: lie)
    }

    /// La carte reste encore `duree` secondes, jamais moins qu'avant (sauf `raccourcir` : un rappel envoyé) ; seulement si c'est elle
    /// qui est là.
    private func prolongerCarte(_ duree: TimeInterval, raccourcir: Bool = false) {
        guard let b = moteur.bandeau, b.vue == .voixCarte else { return }
        let fin = maintenant().addingTimeInterval(duree)
        moteur.bandeau?.jusqua = raccourcir ? fin : max(b.jusqua, fin)
        moteur.donneesChangees()
    }
}

// MARK: - la mise en page

/// Les cadres de l'écoute et de la carte (points depuis le centre de l'encoche et le haut de l'écran) : les vues et l'essai s'en servent.
@MainActor
enum PlanVoix {
    typealias M = MesuresVoix
    static let tailleTitre: CGFloat = 15, tailleQuand: CGFloat = 13.5, tailleResume: CGFloat = 13, tailleBouton: CGFloat = 13
    /// La colonne du texte de la carte : la zone, moins la case cochée et son écart.
    static func largeurTexte(demiCamera hc: CGFloat) -> CGFloat {
        2 * (hc + CGFloat(M.corpsCarte)) - 2 * GrilleIlot.marge - CGFloat(M.coche + M.ecartCoche)
    }
    static func zoneCarte(_ g: GrilleIlot) -> CGRect { g.zone(.voixCarte, haut: CGFloat(M.marge), bas: CGFloat(M.marge)) }
    static func onde(_ g: GrilleIlot) -> CGRect {
        CGRect(x: -CGFloat(M.ondeLargeur) / 2, y: g.barre + CGFloat(M.ondeHaut), width: CGFloat(M.ondeLargeur), height: CGFloat(M.ondeHauteur))
    }
    static func libelle(_ g: GrilleIlot) -> CGRect { CGRect(x: -100, y: g.barre + CGFloat(M.libelleHaut), width: 200, height: CGFloat(M.libelleHauteur)) }
    /// Le bouton d'envoi : la largeur de son plus long libellé (il ne change pas de taille quand il devient « ✓ Dans Rappels »). Mesurée
    /// une fois (la vue est réévaluée à chaque pas d'une animation).
    static let largeursEnvoi: [GenreVoix: CGFloat] = Dictionary(uniqueKeysWithValues: [GenreVoix.rappel, .note].map { g in
        (g, EnvoiVoix.libelles(g).map { MesureIlot.texte($0, tailleBouton, .semibold) }.max()! + 2 * 14 + 4)
    })
    static func largeurEnvoi(_ genre: GenreVoix) -> CGFloat { largeursEnvoi[genre] ?? 0 }
    static let largeurSecondaire = ["Annuler", "Copier", "Copié"].map { MesureIlot.texte($0, 12.5, .semibold) }.max()! + 16
    static func cadreEnvoi(_ g: GrilleIlot, genre: GenreVoix) -> CGRect {
        let z = zoneCarte(g)
        return CGRect(x: z.minX + CGFloat(M.coche + M.ecartCoche), y: z.maxY - CGFloat(M.bouton), width: largeurEnvoi(genre), height: CGFloat(M.bouton))
    }
    static func titreSecondaire(_ genre: GenreVoix, copie: Bool) -> String { genre == .rappel ? "Annuler" : (copie ? "Copié" : "Copier") }
    static func cadreSecondaire(_ g: GrilleIlot, genre: GenreVoix) -> CGRect {
        let z = zoneCarte(g)
        let l = largeurSecondaire
        return CGRect(x: z.maxX - l, y: z.maxY - CGFloat(M.bouton), width: l, height: CGFloat(M.bouton))
    }
}

// MARK: - les vues

/// L'écoute et la carte de fin (IlotCalques les appelle).
struct EcranVoix: View {
    @ObservedObject var m: IlotMoteur
    @ObservedObject var voix: EcouteVoix
    var g: GrilleIlot
    var v: VueIlot

    var body: some View {
        switch v {
        case .voixEcoute: ecoute
        case .voixCarte: CarteVoixVue(m: m, voix: voix, g: g)
        default: EmptyView()
        }
    }

    /// L'icône dans l'aile gauche (le micro, puis le glyphe du genre), l'onde sous la caméra, le libellé dessous.
    private var ecoute: some View {
        let v = VueIlot.voixEcoute
        let c = g.centreAile(v, droite: false)
        let genre = voix.genre
        let anime = !m.statique
        // l'ancien s'efface (0,1 s), puis le nouveau apparaît : jamais deux contenus superposés en fondu
        let part = Animation.easeOut(duration: 0.1), arrive = Animation.easeOut(duration: 0.2).delay(0.12)
        return ZStack(alignment: .topLeading) {
            ZStack {
                Image(systemName: "mic.fill").font(.system(size: 15, weight: .semibold)).foregroundStyle(CouleursIlot.ambre)
                    .opacity(genre == nil ? 1 : 0).animation(genre == nil ? arrive : part, value: genre)
                GlypheVoix(genre: genre ?? .rappel, taille: 18)
                    .opacity(genre == nil ? 0 : 1).animation(genre == nil ? part : arrive, value: genre)
            }
            .posee(CGRect(x: c - 13, y: 0, width: 26, height: g.barre), m.aspect(v, rang: 0), ancre: .center, .center)
            OndeVoixVue(voix: voix, anime: anime && voix.retient)
                .posee(PlanVoix.onde(g), m.aspect(v, rang: 1), ancre: .center)
            HStack(spacing: 6) {
                GlypheVoix(genre: genre ?? .rappel, taille: 15)
                Text(genre?.libelle ?? "").font(.system(size: 13, weight: .semibold)).tracking(-0.1).foregroundStyle(.white).lineLimit(1).fixedSize()
            }
            .frame(maxWidth: .infinity)
            .opacity(genre == nil ? 0 : 1).offset(y: genre == nil ? -4 : 0)
            .animation(anime ? arrive : nil, value: genre)
            .posee(PlanVoix.libelle(g), m.aspect(v, rang: 2), ancre: .center)
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(genre.map { "Lucarne écoute : \($0.libelle)" } ?? "Lucarne écoute")
    }
}

/// L'onde : 31 barres rondes, la hauteur suit la voix (`OndeVoix`). Sa propre horloge d'écran, seulement pendant l'écoute et l'attente :
/// seule l'onde se redessine, pas l'îlot. Les bords s'effacent.
struct OndeVoixVue: View {
    @ObservedObject var voix: EcouteVoix
    var anime: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !anime)) { _ in
            Canvas { ctx, taille in
                let t = voix.instantFige ?? EcouteVoix.horloge()
                let n = OndeVoix.barres, l: CGFloat = 3
                let pas = (taille.width - l) / CGFloat(n - 1)
                let bas: CGFloat = 3.5
                for i in 0..<n {
                    let h = bas + (taille.height - bas) * CGFloat(voix.onde.hauteur(i, a: t))
                    let r = CGRect(x: CGFloat(i) * pas, y: (taille.height - h) / 2, width: l, height: h)
                    ctx.fill(Path(roundedRect: r, cornerRadius: l / 2), with: .color(.white))
                }
            }
        }
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.16),
                                     .init(color: .black, location: 0.84), .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing))
        .accessibilityHidden(true)
    }
}

/// Le glyphe du genre : le rond coché de Rappels (orange), la petite page de Notes (jaune).
struct GlypheVoix: View {
    var genre: GenreVoix
    var taille: CGFloat
    var body: some View {
        Group {
            if genre == .rappel {
                Image(systemName: "checkmark.circle").font(.system(size: taille * 0.92, weight: .semibold)).foregroundStyle(CouleursIlot.ambre)
            } else {
                Canvas { ctx, s in
                    let k = s.width / 20
                    ctx.fill(Path(roundedRect: CGRect(x: 3.4 * k, y: 2.4 * k, width: 13.2 * k, height: 15.2 * k), cornerRadius: 3.2 * k), with: .color(CouleursIlot.jaune))
                    var lignes = Path()
                    for (y, x1) in [(7.2, 13.4), (10.2, 13.4), (13.2, 10.6)] { lignes.move(to: CGPoint(x: 6.6 * k, y: y * k)); lignes.addLine(to: CGPoint(x: x1 * k, y: y * k)) }
                    ctx.stroke(lignes, with: .color(.black.opacity(0.5)), style: StrokeStyle(lineWidth: 1.5 * k, lineCap: .round))
                }
            }
        }
        .frame(width: taille, height: taille)
        .accessibilityHidden(true)
    }
}

/// La carte de fin (maquette, étapes 3, 4, 6, 7) : coché, titre, jour et heure, résumé ; « Envoyer dans … » et « Annuler » / « Copier ».
struct CarteVoixVue: View {
    /// Avant toute carte (jamais affichée : la vue n'existe qu'avec une carte), pour ne rien créer à chaque évaluation.
    private static let vide = CarteVoix(objet: .note(UUID()), titre: "", quand: nil, resume: "")
    @ObservedObject var m: IlotMoteur
    @ObservedObject var voix: EcouteVoix
    var g: GrilleIlot

    var body: some View {
        let v = VueIlot.voixCarte
        let z = PlanVoix.zoneCarte(g)
        let c = voix.carte ?? Self.vide
        let colonne = CGFloat(MesuresVoix.coche + MesuresVoix.ecartCoche)
        ZStack(alignment: .topLeading) {
            // le vide de la carte ne fait rien (on visait un bouton) ; seulement tant qu'elle est là
            Color.clear.contentShape(Rectangle()).onTapGesture {}
                .allowsHitTesting(m.courante == v)
                .accessibilityHidden(true)
                .posee(CGRect(x: -g.corps(v), y: g.barre, width: 2 * g.corps(v), height: max(0, g.hauteur(v) - g.barre)))
            CocheVoix(genre: c.genre, trace: m.statique ? 1 : m.aspect(v, rang: 0).opacite)
                .posee(CGRect(x: z.minX, y: z.minY - 1, width: CGFloat(MesuresVoix.coche), height: CGFloat(MesuresVoix.coche)), m.aspect(v, rang: 0), ancre: .center)
            textes(c)
                .allowsHitTesting(false)
                .posee(CGRect(x: z.minX + colonne, y: z.minY, width: z.width - colonne, height: z.height - CGFloat(MesuresVoix.bouton)), m.aspect(v, rang: 1))
            PiluleEnvoi(etat: m.envoiVoix, genre: c.genre, anime: !m.statique) { m.surAction(.voix(.envoyer)) }
                .posee(PlanVoix.cadreEnvoi(g, genre: c.genre), m.aspect(v, rang: 2), ancre: .leading)
            BoutonDiscret(titre: PlanVoix.titreSecondaire(c.genre, copie: voix.copie)) { m.surAction(.voix(c.genre == .rappel ? .annuler : .copier)) }
                .posee(PlanVoix.cadreSecondaire(g, genre: c.genre), m.aspect(v, rang: 3), ancre: .trailing, .trailing)
        }
        .accessibilityElement(children: .contain)
    }

    private func textes(_ c: CarteVoix) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(c.titre).font(.system(size: PlanVoix.tailleTitre, weight: .semibold)).tracking(-0.2).foregroundStyle(.white).lineLimit(1)
                .frame(height: CGFloat(MesuresVoix.titre), alignment: .leading)
            if let q = c.quand {
                Text(q).font(.system(size: PlanVoix.tailleQuand, weight: .semibold).monospacedDigit()).foregroundStyle(CouleursIlot.ambre).lineLimit(1)
                    .frame(height: CGFloat(MesuresVoix.quand), alignment: .leading)
                    .padding(.top, CGFloat(MesuresVoix.ecartQuand))
            }
            if voix.lignesResume > 0 {
                Text(c.resume).font(.system(size: PlanVoix.tailleResume, weight: .medium)).foregroundStyle(Color.white.opacity(0.55))
                    .lineLimit(voix.lignesResume).truncationMode(.tail).lineSpacing(1)
                    .frame(maxWidth: .infinity, minHeight: CGFloat(MesuresVoix.ligneResume) * CGFloat(voix.lignesResume), alignment: .topLeading)
                    .padding(.top, CGFloat(MesuresVoix.ecartResume))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }
}

/// Le rond de la carte : vert coché (un rappel, la coche se trace à l'arrivée), jaune avec la page (une note).
struct CocheVoix: View {
    var genre: GenreVoix
    var trace: Double
    var body: some View {
        ZStack {
            Circle().fill(genre == .rappel ? CouleursIlot.vert : CouleursIlot.jaune)
            if genre == .rappel {
                Path { p in p.move(to: CGPoint(x: 7.2, y: 12.6)); p.addLine(to: CGPoint(x: 10.4, y: 15.6)); p.addLine(to: CGPoint(x: 16.6, y: 8.8)) }
                    .trim(from: 0, to: CGFloat(min(1, max(0, trace * trace))))
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
            } else {
                Canvas { ctx, s in
                    var lignes = Path()
                    for (y, x1) in [(8.6, 15.6), (12.0, 15.6), (15.4, 12.6)] { lignes.move(to: CGPoint(x: 8.4, y: y)); lignes.addLine(to: CGPoint(x: x1, y: y)) }
                    ctx.stroke(lignes, with: .color(Color(hex: 0x2B2200)), style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
                }
            }
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }
}

/// « Envoyer dans Rappels » (blanc) → « ✓ Dans Rappels » (vert) : le fond change de couleur, l'ancien libellé s'efface PUIS le nouveau
/// apparaît ; la largeur ne bouge pas (celle du plus long libellé).
struct PiluleEnvoi: View {
    var etat: EnvoiVoix
    var genre: GenreVoix
    var anime: Bool
    var action: () -> Void
    @State private var survol = false

    private var fond: Color {
        switch etat {
        case .aEnvoyer: return Color.white.opacity(survol ? 0.9 : 1)
        case .enCours: return Color.white.opacity(0.55)
        case .fait: return CouleursIlot.vert.opacity(0.2)
        case .refuse: return Color.white.opacity(survol ? 0.22 : 0.14)
        }
    }

    var body: some View {
        let part = Animation.easeOut(duration: 0.1), arrive = Animation.easeOut(duration: 0.2).delay(0.14)
        Button(action: action) {
            ZStack {
                ForEach([EnvoiVoix.aEnvoyer, .enCours, .fait, .refuse], id: \.self) { e in
                    libelle(e).opacity(e == etat ? 1 : 0).animation(anime ? (e == etat ? arrive : part) : nil, value: etat)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Capsule().fill(fond).animation(anime ? .easeOut(duration: 0.22).delay(0.1) : nil, value: etat))
            .contentShape(Capsule())
        }
        .buttonStyle(AppuiIlot(echelle: 0.96))
        .onHover { survol = $0 }
        .accessibilityLabel(etat.libelle(genre))
    }

    @ViewBuilder private func libelle(_ e: EnvoiVoix) -> some View {
        HStack(spacing: 6) {
            if e == .fait { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)) }
            Text(e.libelle(genre)).font(.system(size: PlanVoix.tailleBouton, weight: .semibold)).lineLimit(1).fixedSize()
        }
        .foregroundStyle(e == .fait ? Color(hex: 0x5FE08A) : (e == .refuse ? Color.white : Color.black))
    }
}

/// « Annuler », « Copier » : discret (gris), blanc au survol.
struct BoutonDiscret: View {
    var titre: String
    var action: () -> Void
    @State private var survol = false
    var body: some View {
        Button(action: action) {
            Text(titre).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Color.white.opacity(survol ? 1 : 0.55)).lineLimit(1).fixedSize()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(AppuiIlot(echelle: 0.96))
        .onHover { survol = $0 }
        .accessibilityLabel(titre)
    }
}
