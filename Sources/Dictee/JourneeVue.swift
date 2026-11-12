import AppKit
import Combine
import SwiftUI
import DicteeCore

/// Tout ce que la page affiche pour un jour, calculé une fois par `JourneeModele.recalculer()` (la logique est dans DicteeCore/Journee.swift).
struct VueJournee {
    var maintenant: Date
    var estAujourdhui: Bool
    var titre: (relatif: String?, date: String)
    var resume: ResumeJournee
    var phrase: PhraseJournee
    var moyenne: MoyenneJournees?
    var serie: Int
    var meilleure: (jour: Date, mots: Int)?
    var sept: [JourSemaine]
    var reunions: [ReunionJournee]
    var actions: [ActionJournee]
    var piedDePage: String
}

/// L'état de l'onglet Journée : le jour affiché, l'heure ouverte, la dictée dépliée. Les actions (recoller, copier, ouvrir une note,
/// cocher) passent par les modèles des autres onglets : ce sont les mêmes gestes, et la note reste synchronisée.
@MainActor
final class JourneeModele: ObservableObject {
    @Published var jour: Date { didSet { if jour != oldValue { heureOuverte = nil; depliee = nil; cochees = []; recalculer() } } }
    @Published var heureOuverte: Int? { didSet { if heureOuverte != oldValue { depliee = nil } } }
    @Published var depliee: UUID?
    @Published private(set) var cochees: Set<UUID> = []
    @Published private(set) var vue: VueJournee

    let store: HistoriqueStore
    let reunionsStore: ReunionStore
    let reunions: ReunionsModele
    let dictees: ModeleDictees
    var calendrier = Calendar.current
    /// « Maintenant » : remplacé dans les rendus PNG pour qu'ils ne changent pas d'un jour à l'autre.
    var horloge: () -> Date = { Date() }
    var surOuvrirNote: (UUID) -> Void = { _ in }
    var surOuvrirDictees: () -> Void = {}
    private var abonnements = Set<AnyCancellable>()

    init(dictees: ModeleDictees, reunions: ReunionsModele, horloge: @escaping () -> Date = { Date() }, calendrier: Calendar = .current) {
        self.dictees = dictees; self.reunions = reunions; self.store = dictees.store; self.reunionsStore = reunions.store
        self.horloge = horloge; self.calendrier = calendrier
        let debut = calendrier.startOfDay(for: horloge())
        jour = debut
        vue = JourneeModele.calculer(jour: debut, entrees: dictees.store.historique.entrees, reunions: reunions.store.reunions, cochees: [], maintenant: horloge(), calendrier: calendrier)
        // Une dictée de plus, une note qui change, une action cochée dans la note : la page se met à jour.
        // Seulement si la page est À L'ÉCRAN : pendant une réunion, la note change à chaque phrase et le calcul relit tout l'historique
        // (~0,2 s) ; page fermée, on note juste qu'il faudra recalculer en l'ouvrant.
        store.$historique.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.recalculerSiAffichee() } }.store(in: &abonnements)
        reunionsStore.$reunions.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.recalculerSiAffichee() } }.store(in: &abonnements)
    }

    static func calculer(jour: Date, entrees: [EntreeHistorique], reunions: [Reunion], cochees: Set<UUID>, maintenant: Date, calendrier: Calendar) -> VueJournee {
        let resume = Journee.resume(jour: jour, entrees: entrees, calendrier: calendrier)
        let moyenne = Journee.moyenne(avant: jour, entrees: entrees, calendrier: calendrier)
        let meilleureAvant = Journee.meilleure(entrees: entrees, avant: jour, calendrier: calendrier)?.mots
        return VueJournee(
            maintenant: maintenant, estAujourdhui: calendrier.isDate(jour, inSameDayAs: maintenant),
            titre: Journee.titreJour(jour, maintenant: maintenant, calendrier: calendrier),
            resume: resume,
            phrase: Journee.phrase(resume, moyenne: moyenne, meilleurAvant: meilleureAvant, maintenant: maintenant, calendrier: calendrier),
            moyenne: moyenne,
            serie: Journee.serie(jusquA: jour, entrees: entrees, maintenant: maintenant, calendrier: calendrier),
            meilleure: Journee.meilleure(entrees: entrees, calendrier: calendrier),
            sept: Journee.septJours(jusquA: jour, entrees: entrees, maintenant: maintenant, calendrier: calendrier),
            reunions: Journee.reunions(jour: jour, reunions: reunions, calendrier: calendrier),
            actions: Journee.actions(jour: jour, reunions: reunions, aussi: cochees, maintenant: maintenant, calendrier: calendrier),
            piedDePage: Journee.piedDePage(sansDuree: resume.sansDuree))
    }

    /// La page est à l'écran (onAppear / onDisappear de JourneeVue).
    var affichee = false
    func recalculerSiAffichee() { if affichee { recalculer() } }

    func recalculer() {
        vue = Self.calculer(jour: jour, entrees: store.historique.entrees, reunions: reunionsStore.reunions, cochees: cochees, maintenant: horloge(), calendrier: calendrier)
        // l'heure ouverte n'existe plus (dictée supprimée ailleurs) : on referme
        if let h = heureOuverte, vue.resume.motsParHeure[h] == 0 { heureOuverte = nil }
    }

    /// À l'ouverture de la fenêtre sur cet onglet : aujourd'hui, rien d'ouvert.
    func reinitialiser() {
        let debut = calendrier.startOfDay(for: horloge())
        heureOuverte = nil; depliee = nil; cochees = []
        if jour != debut { jour = debut } else { recalculer() }
    }

    var peutAllerAuJourSuivant: Bool { jour < calendrier.startOfDay(for: horloge()) }

    func jourPrecedent() { if let d = calendrier.date(byAdding: .day, value: -1, to: jour) { jour = d } }
    func jourSuivant() { if peutAllerAuJourSuivant, let d = calendrier.date(byAdding: .day, value: 1, to: jour) { jour = d } }
    func aller(a d: Date) { jour = calendrier.startOfDay(for: d) }

    func basculerHeure(_ h: Int) {
        guard vue.resume.motsParHeure.indices.contains(h), vue.resume.motsParHeure[h] > 0 else { return }
        heureOuverte = heureOuverte == h ? nil : h
    }
    func fermerHeure() { heureOuverte = nil }

    /// ← → : d'une heure à l'autre quand une heure est ouverte, sinon d'un jour à l'autre.
    func gauche() { if let h = heureOuverte { if let v = Journee.heureVoisine(motsParHeure: vue.resume.motsParHeure, depuis: h, delta: -1) { heureOuverte = v } } else { jourPrecedent() } }
    func droite() { if let h = heureOuverte { if let v = Journee.heureVoisine(motsParHeure: vue.resume.motsParHeure, depuis: h, delta: 1) { heureOuverte = v } } else { jourSuivant() } }
    /// Échap : referme l'heure ouverte (sans effet sinon).
    func echap() { heureOuverte = nil }

    var dicteesOuvertes: [EntreeHistorique] {
        guard let h = heureOuverte else { return [] }
        return Journee.dictees(jour: jour, heure: h, entrees: store.historique.entrees, calendrier: calendrier)
    }

    func basculerDepliee(_ e: EntreeHistorique) { depliee = depliee == e.id ? nil : e.id }

    func cocher(_ a: ActionJournee) {
        reunions.cocher(a.reunion, action: a.id)
        if cochees.contains(a.id) { cochees.remove(a.id) } else { cochees.insert(a.id) }
        // `recalculer` suit le changement du magasin des réunions
    }

    func ouvrirNote(_ id: UUID) { surOuvrirNote(id) }
}

// MARK: page

struct JourneeVue: View {
    @ObservedObject var m: JourneeModele
    @State private var largeur: CGFloat = 960
    static let margeH: CGFloat = DicteesFenetreVue.margeH

    private var compacte: Bool { largeur < 820 }

    var body: some View {
        let v = m.vue
        let ouverte = m.heureOuverte
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    navigation(v)
                    if ouverte == nil {
                        phrase(v)
                    }
                    if v.resume.mots > 0 {
                        CourbeHeures(resume: v.resume, heureOuverte: ouverte, surChoix: { m.basculerHeure($0) })
                            .padding(.top, ouverte == nil ? 22 : 18)
                    }
                    if let h = ouverte {
                        heureOuverte(v, h)
                    } else {
                        colonnes(v).padding(.top, v.resume.mots > 0 ? 22 : 30)
                        semaine(v).padding(.top, 32)
                    }
                }
                .padding(.horizontal, Self.margeH)
                .padding(.top, 24).padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { m.fermerHeure() }   // un clic ailleurs referme l'heure (les boutons et les lignes gardent leurs clics)
            }
            pied(v, ouverte: ouverte != nil)
        }
        .background(GeometryReader { g in Color.clear.onAppear { largeur = g.size.width }.onChange(of: g.size.width) { _, w in largeur = w } })
        .background(
            Group {
                Button("") { m.echap() }.keyboardShortcut(.escape, modifiers: [])
                Button("") { m.gauche() }.keyboardShortcut(.leftArrow, modifiers: [])
                Button("") { m.droite() }.keyboardShortcut(.rightArrow, modifiers: [])
            }.opacity(0).frame(width: 0, height: 0)
        )
        .onAppear { m.affichee = true; m.recalculer() }
        .onDisappear { m.affichee = false; m.heureOuverte = nil }
    }

    // MARK: navigation par jour

    private func navigation(_ v: VueJournee) -> some View {
        HStack(spacing: 8) {
            FlecheJour(symbole: "chevron.left", etiquette: "Jour précédent", active: true) { m.jourPrecedent() }
            (Text(v.titre.relatif ?? v.titre.date).foregroundStyle(Palette.texte).fontWeight(.medium)
             + Text(v.titre.relatif != nil ? " \u{00B7} \(v.titre.date)" : "").foregroundStyle(Palette.texte2))
                .font(Polices.commande(14))
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            FlecheJour(symbole: "chevron.right", etiquette: "Jour suivant", active: m.peutAllerAuJourSuivant) { m.jourSuivant() }
            Spacer(minLength: 8)
            if !v.estAujourdhui {
                BoutonSobre(titre: "Revenir à aujourd\u{2019}hui", hauteur: 28) { m.reinitialiser() }.fixedSize()
            }
        }
        .frame(height: 28)
    }

    // MARK: la phrase

    private func phrase(_ v: VueJournee) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(v.phrase.texte)
                .font(Polices.texte(compacte ? 24 : 27))
                .lineSpacing(compacte ? 5 : 6)
                .foregroundStyle(Palette.texte)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 880, alignment: .leading)
                .textSelection(.enabled)
            if v.resume.mots == 0 {
                LienJournee(titre: "Aller aux dictées") { m.surOuvrirDictees() }
            }
        }
        .padding(.top, 10)
    }

    // MARK: l'heure ouverte (C2)

    private func heureOuverte(_ v: VueJournee, _ h: Int) -> some View {
        let liste = m.dicteesOuvertes
        let mots = v.resume.motsParHeure[h]
        let n = v.resume.dicteesParHeure[h]
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(FormatJournee.heure(h)) à \(FormatJournee.heure(h + 1)) \u{00B7} \(n) dictée\(n > 1 ? "s" : "")")
                    .font(Polices.commande(15, .medium)).foregroundStyle(Palette.texte)
                Spacer(minLength: 12)
                Text("\(FormatJournee.mots(mots))\(v.resume.heurePic == h ? " \u{00B7} ton meilleur moment de la journée" : "")")
                    .font(Polices.commande(13)).foregroundStyle(Palette.texte2).lineLimit(1)
            }
            .padding(.top, 14)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(liste) { e in LigneHeure(e: e, m: m, depliee: m.depliee == e.id) }
            }
            .padding(.horizontal, -16)
            .padding(.top, 8)
        }
    }

    // MARK: trois colonnes (B2) : où tu as écrit · réunions · à faire

    private func colonnes(_ v: VueJournee) -> some View {
        let apps = colonneApps(v), reunions = colonneReunions(v), actions = colonneActions(v)
        return Group {
            if compacte {
                VStack(alignment: .leading, spacing: 28) { apps; reunions; actions }
            } else {
                ColonnesJournee(poids: [0.95, 1.1, 1.15], ecart: 36) { apps; reunions; actions }
            }
        }
    }

    private func colonneApps(_ v: VueJournee) -> some View {
        let apps = Array(v.resume.apps.prefix(5))
        let plus = v.resume.apps.count - apps.count
        let maxMots = max(1, apps.first?.mots ?? 1)
        return VStack(alignment: .leading, spacing: 0) {
            EnteteColonne(titre: "Où tu as écrit")
            if apps.isEmpty { Rien(texte: v.resume.mots == 0 ? "Aucune dictée." : "Aucune dictée écrite dans une app.") }
            ForEach(Array(apps.enumerated()), id: \.offset) { _, a in
                HStack(spacing: 12) {
                    IconeAppCible(appId: a.appId, nom: a.nom, taille: 20)
                    VStack(spacing: 0) {
                        HStack {
                            Text(a.nom).font(Polices.commande(14)).foregroundStyle(Palette.texte).lineLimit(1)
                            Spacer(minLength: 8)
                            Text(FormatJournee.nombre(a.mots)).font(Polices.commande(13)).foregroundStyle(Palette.texte2)
                        }
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Palette.relief)
                                Capsule().fill(Palette.texte2).frame(width: max(3, g.size.width * CGFloat(a.mots) / CGFloat(maxMots)))
                            }
                        }
                        .frame(height: 3).padding(.top, 6)
                    }
                }
                .frame(height: 40)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(a.nom), \(FormatJournee.mots(a.mots))")
            }
            if plus > 0 { Text("+ \(plus) autre\(plus > 1 ? "s" : "")").font(Polices.commande(13)).foregroundStyle(Palette.texte3).padding(.top, 6) }
        }
    }

    private func colonneReunions(_ v: VueJournee) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            EnteteColonne(titre: "Réunions", compte: v.reunions.isEmpty ? nil : v.reunions.count)
            if v.reunions.isEmpty { Rien(texte: v.estAujourdhui ? "Pas de réunion notée aujourd\u{2019}hui." : "Pas de réunion notée ce jour-là.") }
            ForEach(Array(v.reunions.enumerated()), id: \.element.id) { i, r in
                LigneReunionJour(r: r, derniere: i == v.reunions.count - 1) { m.ouvrirNote(r.id) }
            }
        }
    }

    private func colonneActions(_ v: VueJournee) -> some View {
        let affichees = Array(v.actions.prefix(5))
        let reste = v.actions.count - affichees.count
        let aFaire = v.actions.filter { !$0.fait }.count
        return VStack(alignment: .leading, spacing: 0) {
            EnteteColonne(titre: "À faire", compte: v.actions.isEmpty ? nil : aFaire)
            if v.actions.isEmpty { Rien(texte: v.reunions.isEmpty ? "Rien à faire." : "Plus rien à faire dans ces notes.") }
            ForEach(affichees) { a in LigneActionJour(a: a) { m.cocher(a) } }
            if reste > 0 { Text("+ \(reste) autre\(reste > 1 ? "s" : "") dans les notes").font(Polices.commande(13)).foregroundStyle(Palette.texte3).padding(.top, 6) }
        }
    }

    // MARK: les 7 derniers jours, série, meilleure journée, moyenne

    private func semaine(_ v: VueJournee) -> some View {
        let sept = v.sept
        let maxMots = max(1, sept.map(\.mots).max() ?? 1, Int((v.moyenne?.mots ?? 0).rounded()))
        let barres = VStack(alignment: .leading, spacing: 0) {
            EnteteColonne(titre: "Les 7 derniers jours")
            VStack(spacing: 6) {
                ZStack(alignment: .bottom) {
                    HStack(alignment: .bottom, spacing: 8) {
                        ForEach(Array(sept.enumerated()), id: \.offset) { i, j in
                            Button { m.aller(a: j.jour) } label: {
                                RoundedRectangle(cornerRadius: 3).fill(i == sept.count - 1 ? Palette.texte : Palette.relief)
                                    .frame(height: max(2, 100 * CGFloat(j.mots) / CGFloat(maxMots)))
                                    .frame(maxWidth: .infinity, maxHeight: 100, alignment: .bottom)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(j.etiquette) \(FormatJournee.mots(j.mots))")
                        }
                    }
                    if let moy = v.moyenne, moy.mots > 0 {
                        // la moyenne des 14 derniers jours actifs : un trait en pointillé à sa hauteur
                        GeometryReader { g in
                            Path { p in
                                let y = 100 - 100 * CGFloat(moy.mots) / CGFloat(maxMots)
                                p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: g.size.width, y: y))
                            }
                            .stroke(Palette.texte3, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        }
                        .allowsHitTesting(false)
                    }
                }
                .frame(height: 100)
                HStack(spacing: 8) {
                    ForEach(Array(sept.enumerated()), id: \.offset) { i, j in
                        Text(j.etiquette).font(Polices.commande(12)).foregroundStyle(i == sept.count - 1 ? Palette.texte : Palette.texte3)
                            .frame(maxWidth: .infinity)
                    }
                }
                .accessibilityHidden(true)
            }
            .padding(.top, 14)
        }
        let faits = VStack(alignment: .leading, spacing: 0) {
            fait("Série", v.serie > 0 ? "\(v.serie) jour\(v.serie > 1 ? "s" : "")\(v.serie > 1 ? " de suite" : "")" : "\u{2014}")
            fait("Meilleure journée", v.meilleure.map { "\(Self.formatJourCourt.string(from: $0.jour)) \u{00B7} \(FormatJournee.nombre($0.mots))" } ?? "\u{2014}")
            fait("Moyenne", v.moyenne.map { "\(FormatJournee.nombre(Int($0.mots.rounded()))) mots" } ?? "\u{2014}", aide: v.moyenne.map { "Sur les \($0.jours) derniers jours où tu as dicté, sans compter celui-ci." })
        }
        return Group {
            if compacte {
                VStack(alignment: .leading, spacing: 24) { barres; faits }
            } else {
                HStack(alignment: .top, spacing: 64) {
                    barres.frame(maxWidth: .infinity, alignment: .leading)
                    faits.frame(width: 300).padding(.top, 36)
                }
            }
        }
    }

    private static let formatJourCourt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.dateFormat = "EEE d MMM"; return f
    }()

    private func fait(_ titre: String, _ valeur: String, aide: String? = nil) -> some View {
        HStack(spacing: 12) {
            Text(titre).foregroundStyle(Palette.texte2)
            Spacer(minLength: 8)
            Text(valeur).foregroundStyle(Palette.texte).fontWeight(.medium).lineLimit(1)
        }
        .font(Polices.commande(14))
        .padding(.vertical, 8)
        .overlay(alignment: .top) { Rectangle().fill(Palette.filet).frame(height: 1) }
        .help(aide ?? "")
        .accessibilityElement(children: .combine)
    }

    // MARK: pied de page

    private func pied(_ v: VueJournee, ouverte: Bool) -> some View {
        HStack(spacing: 24) {
            if ouverte {
                HStack(spacing: 8) {
                    HStack(spacing: 4) { Touche(symbole: "arrow.left", petit: true); Touche(symbole: "arrow.right", petit: true) }
                    Text("changer d\u{2019}heure").font(Polices.commande(13)).foregroundStyle(Palette.texte2)
                }
                HStack(spacing: 8) {
                    Touche(texte: "esc", petit: true)
                    Text("revenir à la journée").font(Polices.commande(13)).foregroundStyle(Palette.texte2)
                }
                Spacer(minLength: 0)
            } else {
                Text(v.piedDePage).font(Polices.commande(12)).foregroundStyle(Palette.texte3).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
        .lineLimit(2)
        .padding(.horizontal, Self.margeH)
        .frame(minHeight: 48)
        .padding(.vertical, 4)
        .overlay(alignment: .top) { Rectangle().fill(Palette.filet).frame(height: 1) }
    }
}

// MARK: petites pièces

/// ‹ et › de la navigation par jour.
struct FlecheJour: View {
    var symbole: String
    var etiquette: String
    var active: Bool
    var action: () -> Void
    @State private var survol = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbole).font(.system(size: 12, weight: .medium))
                .foregroundStyle(active ? (survol ? Palette.texte : Palette.texte2) : Palette.texte3.opacity(0.4))
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 6).fill(survol && active ? Palette.selection : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!active)
        .onHover { survol = $0 }
        .accessibilityLabel(etiquette)
    }
}

/// Un lien discret : texte et chevron.
struct LienJournee: View {
    var titre: String
    var action: () -> Void
    @State private var survol = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(titre).font(Polices.commande(14))
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(survol ? Palette.texte : Palette.texte2)
            .frame(height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { survol = $0 }
        .accessibilityLabel(titre)
    }
}

/// « Où tu as écrit », « Réunions 2 » : titre, nombre en gris, filet dessous.
struct EnteteColonne: View {
    var titre: String
    var compte: Int?
    var body: some View {
        HStack(spacing: 6) {
            Text(titre).font(Polices.commande(15, .medium)).foregroundStyle(Palette.texte)
            if let compte { Text("\(compte)").font(Polices.commande(15)).foregroundStyle(Palette.texte3) }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 6)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.contour).frame(height: 1) }
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

struct Rien: View {
    var texte: String
    var body: some View {
        Text(texte).font(Polices.commande(14)).foregroundStyle(Palette.texte3).padding(.top, 8).fixedSize(horizontal: false, vertical: true)
    }
}

/// Une réunion du jour : titre, « 9 h 15 · 32 min · 2 actions à faire sur 3 », son « En bref » sur une ligne. Un clic ouvre la note.
struct LigneReunionJour: View {
    var r: ReunionJournee
    var derniere: Bool
    var ouvrir: () -> Void
    @State private var survol = false
    var body: some View {
        Button(action: ouvrir) {
            VStack(alignment: .leading, spacing: 2) {
                Text(r.titre).font(Polices.commande(15)).foregroundStyle(Palette.texte).lineLimit(1)
                Text([r.heure, r.duree, r.actions].compactMap { $0 }.joined(separator: " \u{00B7} "))
                    .font(Polices.commande(13)).foregroundStyle(survol ? Palette.texte : Palette.texte2).lineLimit(1)
                if r.noteEcrite, !r.enBref.isEmpty {
                    Text(r.enBref).font(Polices.texte(16)).foregroundStyle(Palette.texte2).lineLimit(1).truncationMode(.tail).padding(.top, 4)
                } else if !r.noteEcrite {
                    Text("Pas encore de note.").font(Polices.commande(13)).foregroundStyle(Palette.texte3).padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
            .overlay(alignment: .bottom) { if !derniere { Rectangle().fill(Palette.filet).frame(height: 1) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { survol = $0 }
        .help(r.enBref)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(r.titre), \(r.heure), \(r.duree)\(r.actions.map { ", " + $0 } ?? ""). \(r.enBref)")
        .accessibilityHint("Ouvre la note")
        .accessibilityAddTraits(.isButton)
    }
}

/// Une action à faire : case, texte, échéance. Se coche ici comme dans la note (même donnée).
struct LigneActionJour: View {
    var a: ActionJournee
    var cocher: () -> Void
    var body: some View {
        Button(action: cocher) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5).strokeBorder(a.fait ? Palette.texte : Palette.texte3, lineWidth: 1.5)
                    if a.fait {
                        RoundedRectangle(cornerRadius: 5).fill(Palette.texte)
                        Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.surface)
                    }
                }
                .frame(width: 16, height: 16).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
                Text(a.quoi).font(Polices.commande(14)).foregroundStyle(a.fait ? Palette.texte3 : Palette.texte)
                    .strikethrough(a.fait, color: Palette.texte3)
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(a.fait ? "fait" : a.etiquette).font(Polices.commande(13, a.urgente ? .medium : .regular))
                    .foregroundStyle(a.urgente ? Palette.texte : Palette.texte3).lineLimit(1).fixedSize()
            }
            .padding(.vertical, 9)
            .frame(minHeight: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(a.qui.map { $0 + " : " } ?? "")\(a.quoi), \(a.etiquette)")
        .accessibilityValue(a.fait ? "fait" : "à faire")
        .accessibilityAddTraits(.isToggle)
    }
}

/// Trois colonnes de largeurs proportionnelles, avec un écart, alignées en haut.
struct ColonnesJournee: Layout {
    var poids: [CGFloat]
    var ecart: CGFloat
    private func largeurs(_ total: CGFloat, _ n: Int) -> [CGFloat] {
        let libre = max(0, total - ecart * CGFloat(max(0, n - 1)))
        let somme = poids.prefix(n).reduce(0, +)
        return poids.prefix(n).map { libre * $0 / somme }
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let total = proposal.width ?? 900
        let h = zip(subviews, largeurs(total, subviews.count)).map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }.max() ?? 0
        return CGSize(width: total, height: h)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (v, w) in zip(subviews, largeurs(bounds.width, subviews.count)) {
            v.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading, proposal: ProposedViewSize(width: w, height: nil))
            x += w + ecart
        }
    }
}

// MARK: les dictées d'une heure

/// Une dictée de l'heure ouverte : heure, icône de l'app, texte ; à droite « Mail · 58 mots ». Un clic la déplie avec Recoller et Copier,
/// les mêmes que dans l'onglet Dictées.
struct LigneHeure: View {
    let e: EntreeHistorique
    @ObservedObject var m: JourneeModele
    var depliee: Bool
    @State private var survol = false

    private static let formatHeure: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.dateFormat = "HH:mm"; return f
    }()

    var body: some View {
        let mots = Historique.compterMots(e.texte)
        let meta = [e.insere ? e.appNom : "Non écrite", FormatJournee.mots(mots)].compactMap { $0 }.joined(separator: " \u{00B7} ")
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                Text(Self.formatHeure.string(from: e.date)).font(Polices.commande(14).monospacedDigit()).foregroundStyle(Palette.texte2).frame(width: 56, alignment: .leading)
                IconeAppCible(appId: e.appId, nom: e.appNom)
                if depliee { Spacer(minLength: 0) } else {
                    Text(e.texte).font(Polices.texte(18)).foregroundStyle(Palette.texte).lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
                }
                Text(meta).font(Polices.commande(13)).foregroundStyle(Palette.texte2).lineLimit(1).fixedSize()
            }
            .frame(height: 52)
            if depliee { detail }
        }
        .padding(.horizontal, 16)
        .background(RoundedRectangle(cornerRadius: 10).fill(depliee ? Palette.selection : (survol ? Palette.selection.opacity(0.5) : .clear)))
        .overlay { if depliee { RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.contour, lineWidth: 1) } }
        .padding(.vertical, depliee ? 4 : 0)
        .contentShape(Rectangle())
        .onHover { survol = $0 }
        .onTapGesture { m.basculerDepliee(e) }
        .accessibilityElement(children: depliee ? .contain : .combine)
        .accessibilityLabel("\(Self.formatHeure.string(from: e.date)), \(e.texte), \(meta)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Recoller") { m.dictees.recoller(e) }
        .accessibilityAction(named: "Copier") { m.dictees.copier(e) }
        .accessibilityAction(named: depliee ? "Réduire" : "Déplier") { m.basculerDepliee(e) }
    }

    private var detail: some View {
        let destination = m.dictees.nomDestination()
        return VStack(alignment: .leading, spacing: 0) {
            Text(e.texte).font(Polices.texte(18)).foregroundStyle(Palette.texte).lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                .padding(.leading, 96).padding(.top, -6)
            ViewThatFits(in: .horizontal) {
                actions(destination: destination)
                actions(destination: nil)
            }
            .padding(.leading, 96).padding(.vertical, 16)
        }
    }

    private func actions(destination: String?) -> some View {
        HStack(spacing: 8) {
            BoutonPlein(titre: destination.map { "Recoller dans \($0)" } ?? "Recoller", symbole: "return", action: { m.dictees.recoller(e) }) {
                Touche(symbole: "return", sombre: true, petit: true)
            }
            .fixedSize()
            BoutonCadre(m.dictees.copiee == e.id ? "Copié" : "Copier", symbole: m.dictees.copiee == e.id ? "checkmark" : "doc.on.doc") { m.dictees.copier(e) }
                .fixedSize()
            Spacer(minLength: 0)
        }
    }
}

// MARK: la courbe des heures

struct GeometrieCourbe {
    var gauche: CGFloat, tranche: CGFloat, base: CGFloat, haut: CGFloat, ymax: CGFloat
    func x(_ i: CGFloat) -> CGFloat { gauche + i * tranche }
    func y(_ mots: Int) -> CGFloat { base - CGFloat(mots) / ymax * (base - haut) }
}

/// Une seule courbe : les mots dictés heure par heure, grise, avec un point ambre sur le pic (ou sur l'heure ouverte / survolée).
/// Chaque heure où l'on a dicté est un bouton : un clic ouvre la liste de ses dictées.
struct CourbeHeures: View {
    var resume: ResumeJournee
    var heureOuverte: Int?
    var surChoix: (Int) -> Void
    @State private var survol: Int?

    static let gauche: CGFloat = 36, droite: CGFloat = 24

    var body: some View {
        let ouverte = heureOuverte != nil
        let hauteur: CGFloat = ouverte ? 150 : 160
        let base = hauteur - 44            // la ligne du zéro
        let haut = base - (ouverte ? 88 : 96)
        let plage = Journee.plageHeures(motsParHeure: resume.motsParHeure)
        let tranches = max(1, plage.fin - plage.debut)
        let pic = max(1, resume.motsParHeure.max() ?? 1)
        let ymax = CGFloat(pic) * 1.33
        let focus = heureOuverte ?? survol ?? resume.heurePic
        GeometryReader { g in
            let largeur = g.size.width
            let utile = max(1, largeur - Self.gauche - Self.droite)
            let tranche = utile / CGFloat(tranches)
            let geo = GeometrieCourbe(gauche: Self.gauche, tranche: tranche, base: base, haut: haut, ymax: ymax)
            let x = geo.x, y = geo.y
            let valeurs = (plage.debut..<plage.fin).map { resume.motsParHeure[$0] }
            // points : bord gauche, centre de chaque heure, bord droit
            let points: [CGPoint] = [CGPoint(x: x(0), y: y(valeurs.first ?? 0))]
                + valeurs.enumerated().map { CGPoint(x: x(CGFloat($0.offset) + 0.5), y: y($0.element)) }
                + [CGPoint(x: x(CGFloat(tranches)), y: y(valeurs.last ?? 0))]
            let courbe = Self.chemin(points, base: base, haut: haut)
            ZStack(alignment: .topLeading) {
                // lignes repères
                Path { p in p.move(to: CGPoint(x: Self.gauche, y: base)); p.addLine(to: CGPoint(x: largeur - Self.droite, y: base)) }
                    .stroke(Palette.contour, lineWidth: 1)
                if let repere = Journee.ligneRepere(pic: pic) {
                    let yr = y(repere)
                    Path { p in p.move(to: CGPoint(x: Self.gauche, y: yr)); p.addLine(to: CGPoint(x: largeur - Self.droite, y: yr)) }
                        .stroke(Palette.filet.opacity(0.75), lineWidth: 1)
                    Text(FormatJournee.nombre(repere)).font(Polices.commande(12)).foregroundStyle(Palette.texte3).position(x: 14, y: yr)
                }
                Text("0").font(Polices.commande(12)).foregroundStyle(Palette.texte3).position(x: 6, y: base)
                // heure ouverte ou survolée
                if let h = heureOuverte, (plage.debut..<plage.fin).contains(h) {
                    RoundedRectangle(cornerRadius: 4).fill(Palette.texte.opacity(0.07))
                        .frame(width: tranche, height: base - haut + 4).position(x: x(CGFloat(h - plage.debut) + 0.5), y: (haut - 4 + base) / 2)
                } else if let h = survol, (plage.debut..<plage.fin).contains(h) {
                    RoundedRectangle(cornerRadius: 4).fill(Palette.texte.opacity(0.04))
                        .frame(width: tranche, height: base - haut + 4).position(x: x(CGFloat(h - plage.debut) + 0.5), y: (haut - 4 + base) / 2)
                }
                // la courbe : remplissage très léger puis trait gris
                courbe.fill(Palette.texte.opacity(0.06))
                Self.trait(points, base: base, haut: haut).stroke(Palette.texte2, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                // point ambre et son étiquette
                if let f = focus, (plage.debut..<plage.fin).contains(f), resume.motsParHeure[f] > 0 {
                    let cx = x(CGFloat(f - plage.debut) + 0.5), cy = y(resume.motsParHeure[f])
                    Circle().fill(Palette.accent).frame(width: 10, height: 10).position(x: cx, y: cy)
                    Text("\(FormatJournee.heure(f)) \u{00B7} \(FormatJournee.mots(resume.motsParHeure[f]))")
                        .font(Polices.commande(13)).foregroundStyle(Palette.texte).fixedSize()
                        .position(x: min(max(cx, 70), largeur - 70), y: max(10, cy - 14))
                }
                // graduations des heures
                ForEach(Array(stride(from: plage.debut, through: plage.fin, by: tranches > 14 ? 4 : 2)), id: \.self) { h in
                    Text(FormatJournee.heure(h)).font(Polices.commande(12)).foregroundStyle(Palette.texte3).fixedSize()
                        .position(x: x(CGFloat(h - plage.debut)), y: base + 18)
                }
                // une zone cliquable par heure où l'on a dicté
                HStack(spacing: 0) {
                    ForEach(plage.debut..<plage.fin, id: \.self) { h in
                        let mots = resume.motsParHeure[h], n = resume.dicteesParHeure[h]
                        Button { surChoix(h) } label: { Color.clear.contentShape(Rectangle()) }
                            .buttonStyle(.plain)
                            .disabled(mots == 0)
                            .onHover { dedans in if dedans, mots > 0 { survol = h } else if survol == h { survol = nil } }
                            .accessibilityLabel("\(FormatJournee.heure(h)), \(FormatJournee.mots(mots)), \(n) dictée\(n > 1 ? "s" : "")")
                            .accessibilityHint("Montre les dictées de cette heure")
                            .accessibilityHidden(mots == 0)
                    }
                }
                .frame(width: utile, height: base - haut + 4)
                .offset(x: Self.gauche, y: haut - 4)
            }
        }
        .frame(height: hauteur)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Mots dictés par heure")
    }

    /// Courbe lissée (Catmull-Rom), sans jamais passer sous le zéro ni au-dessus du haut.
    static func trait(_ pts: [CGPoint], base: CGFloat, haut: CGFloat) -> Path {
        var p = Path()
        guard pts.count > 1 else { return p }
        p.move(to: pts[0])
        for i in 0..<(pts.count - 1) {
            let p0 = pts[max(0, i - 1)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[min(pts.count - 1, i + 2)]
            func borne(_ v: CGFloat) -> CGFloat { min(base, max(haut - 6, v)) }
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: borne(p1.y + (p2.y - p0.y) / 6))
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: borne(p2.y - (p3.y - p1.y) / 6))
            p.addCurve(to: p2, control1: c1, control2: c2)
        }
        return p
    }

    static func chemin(_ pts: [CGPoint], base: CGFloat, haut: CGFloat) -> Path {
        var p = trait(pts, base: base, haut: haut)
        guard let premier = pts.first, let dernier = pts.last else { return p }
        p.addLine(to: CGPoint(x: dernier.x, y: base)); p.addLine(to: CGPoint(x: premier.x, y: base)); p.closeSubpath()
        return p
    }
}
