import AppKit
import SwiftUI
import DicteeCore

// Groq dans l'îlot (12/11, Hugues : « j'ai peur un jour d'arriver à mes limites sur Groq ») :
// - la jauge « Groq » de la page Outils (anneau = la part utilisée de la limite la plus serrée ; sous le rond « Reste 7 h 18 », « Reste 12 min »,
//   « Relais », « Pause 15:00 ») ; un clic dit le détail (« Il te reste 7 h 18 aujourd'hui · De dictée gratuite avec Groq (8 h par jour) ») ;
// - deux annonces, une fois chacune par passage : sous 15 % de marge, puis la limite atteinte (« Dictée gratuite en pause jusqu'à 15:00 ·
//   Le Mac écrit à ta place ») ;
// - après une dictée passée par la reconnaissance du Mac : la première fois « Dicté sur le Mac · Pas de réseau », ensuite « Mac » dans les
//   ailes seulement (discret).
// La logique est dans DicteeCore/UsageGroq.swift ; l'usage est lu par une fermeture injectable (l'essai n'en lit jamais un vrai).

/// Ce que dit un bandeau `.groq` : il choisit son symbole.
enum GenreBandeauGroq: Equatable {
    case bas, epuise, relais, attente, detail
}

extension IlotControleur {
    /// Combien de temps un bandeau de Groq reste.
    static let dureeBandeauGroq: TimeInterval = 4
    static let dureeAilesMac: TimeInterval = 2

    /// Au lancement : l'îlot suit l'usage de Groq (une notification à chaque requête et réponse, aucune minuterie).
    func demarrerGroq() {
        observateurGroq = NotificationCenter.default.addObserver(forName: .verbeUsageGroq, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.groqChange() }
        }
        moteur.groq = lireEtatGroq(maintenant())
    }
    func arreterGroq() {
        if let o = observateurGroq { NotificationCenter.default.removeObserver(o) }
        observateurGroq = nil
        reveilGroq?.cancel(); reveilGroq = nil
    }

    /// L'usage a changé (ou une pause vient de finir) : la jauge suit ; sous 15 %, puis à la limite, l'îlot le dit une fois.
    func groqChange() {
        let t = maintenant()
        let e = lireEtatGroq(t)
        moteur.groq = e
        if let a = alerteGroq.apres(e, a: t) {
            let genre: GenreBandeauGroq
            switch a { case .bas: genre = .bas; case .epuise: genre = .epuise }
            Log.ecrire("îlot : Groq « \(a.titre) »")
            moteur.annoncer(bandeau: BandeauIlot(vue: .groq, jusqua: t.addingTimeInterval(Self.dureeBandeauGroq + 1), ligne1: a.titre, ligne2: a.sousTitre, groq: genre))
        }
        // une pause en cours : on revient voir à sa fin (la jauge se vide, l'annonce suivante pourra se dire)
        reveilGroq?.cancel(); reveilGroq = nil
        let fin = [e.principal.pauseJusqua, e.secours?.pauseJusqua].compactMap { $0 }.filter { $0 > t }.min()
        if let fin {
            let item = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.groqChange() } }
            reveilGroq = item
            DispatchQueue.main.asyncAfter(deadline: .now() + max(1, fin.timeIntervalSince(t) + 1), execute: item)
        }
    }

    /// Une dictée vient de passer par la reconnaissance du Mac : le signe (bandeau la première fois, ailes ensuite). Pendant la dictée
    /// l'îlot est effacé : le moteur garde le signe jusqu'à sa fin.
    func relaisDictee(_ echec: EchecGroq) {
        let t = maintenant()
        let e = lireEtatGroq(t)
        moteur.groq = e
        switch suiviRelais.apresRelais(echec, pauseJusqua: e.pauseJusqua, a: t) {
        case .bandeau(let titre, let sousTitre):
            moteur.annoncer(bandeau: BandeauIlot(vue: .groq, jusqua: t.addingTimeInterval(Self.dureeBandeauGroq), ligne1: titre, ligne2: sousTitre, groq: .relais))
        case .ailes:
            moteur.annoncer(bandeau: BandeauIlot(vue: .dicteeMac, jusqua: t.addingTimeInterval(Self.dureeAilesMac), ligne1: "Mac", ligne2: ""))
        }
    }
    /// Groq a donné le texte d'une dictée : le prochain relais se dira en entier.
    func groqReussi() { suiviRelais.apresGroq() }

    /// La dictée aurait dû passer par le Mac, qui n'est pas prêt (la langue se télécharge) : où il en est.
    func relaisIndisponible(_ texte: String) {
        moteur.annoncer(bandeau: BandeauIlot(vue: .groq, jusqua: maintenant().addingTimeInterval(Self.dureeBandeauGroq), ligne1: "Dictée sur le Mac pas encore prête",
                                             ligne2: texte, groq: .attente))
    }

    /// Un clic sur la jauge : le détail (un geste : il passe même le Centre épinglé, qui retiendrait sinon les bandeaux).
    func detailGroq() {
        let t = maintenant()
        let e = lireEtatGroq(t)
        moteur.groq = e
        let d = TexteGroq.detail(e, a: t)
        var l2 = d.sousTitre
        if let p = lireProgressionParole() { l2 = "Le Mac télécharge le français \u{00B7} \(Int((p * 100).rounded(.down))) %" }
        if moteur.centreRetientLesBandeaux { moteur.epingle = false }
        moteur.annoncer(bandeau: BandeauIlot(vue: .groq, jusqua: t.addingTimeInterval(Self.dureeBandeauGroq + 1), ligne1: d.titre, ligne2: l2, groq: .detail))
    }
}

/// La jauge de Groq dans son rond (52 pt) : un anneau fin qui se remplit avec la part utilisée de la limite la plus serrée, et l'onde.
struct JaugeGroq: View {
    var utilise: Double
    var couleur: Color

    static func couleur(_ n: NiveauGroq) -> Color {
        switch n { case .ok: return CouleursIlot.vert; case .bas: return CouleursIlot.ambre; case .epuise: return CouleursIlot.rouge }
    }
    /// L'état sous le rond : gris quand tout va bien, ambre ou rouge sinon (lisibles sur le noir de l'îlot).
    static func encre(_ n: NiveauGroq) -> Color {
        switch n { case .ok: return CouleursIlot.encre2; case .bas: return Color(hex: 0xFFB340); case .epuise: return Color(hex: 0xFF6961) }
    }

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.12), lineWidth: 3)
            Circle().trim(from: 0, to: max(0.02, min(1, utilise)))
                .stroke(couleur, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: "waveform").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
        }
        .padding(4)
        .frame(width: PlanCentre.rond, height: PlanCentre.rond)
        .accessibilityHidden(true)
    }
}
