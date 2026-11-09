import AppKit
import SwiftUI
import DicteeCore

/// Mesures de la liste : le panneau compact (style B) et la fenêtre principale partagent le même dessin.
struct MetriquesListe {
    var ligne: CGFloat
    var police: CGFloat          // texte dicté (Newsreader)
    var meta: CGFloat            // heure, app, groupes (SF Pro)
    var colonneHeure: CGFloat
    var marge: CGFloat           // marge intérieure horizontale d'une ligne
    var hauteurChamp: CGFloat
    var icone: CGFloat

    static let panneau = MetriquesListe(ligne: 36, police: 15, meta: 12, colonneHeure: 36, marge: 8, hauteurChamp: 36, icone: 28)
    static let fenetre = MetriquesListe(ligne: 48, police: 17, meta: 13, colonneHeure: 52, marge: 14, hauteurChamp: 44, icone: 32)
}

/// L'état partagé de la liste des dictées : recherche, ligne choisie, ligne dépliée. Les actions sont branchées dehors.
@MainActor
final class ModeleDictees: ObservableObject {
    @Published var requete = "" { didSet { if requete != oldValue { selection = affichees.first?.id; developpee = nil; suppressionEnAttente = nil } } }
    @Published var selection: UUID? { didSet { if selection != oldValue { suppressionEnAttente = nil } } }
    @Published var developpee: UUID?
    /// Dictée dont la suppression attend la confirmation (« Supprimer cette dictée ? »).
    @Published var suppressionEnAttente: UUID?
    /// Ligne dont l'action « copier » vient d'être faite (retour visuel d'une seconde).
    @Published var copiee: UUID?
    @Published var jetonFocus = 0
    let store: HistoriqueStore

    var surRecoller: (EntreeHistorique) -> Void = { _ in }
    var surCopier: (EntreeHistorique) -> Void = { _ in }
    var surEchap: () -> Void = {}
    var surOuvrirFenetre: () -> Void = {}
    /// L'app où « recoller » écrira (la dernière utilisée avant Verbe) ; `nil` = inconnue.
    var nomDestination: () -> String? = { nil }

    init(store: HistoriqueStore? = nil) { self.store = store ?? HistoriqueStore.shared }

    var affichees: [EntreeHistorique] { store.historique.filtrer(requete) }
    var entreeChoisie: EntreeHistorique? { affichees.first { $0.id == selection } ?? affichees.first }

    func reinitialiser() {
        requete = ""
        developpee = nil
        selection = store.historique.entrees.first?.id
        jetonFocus += 1
    }

    func deplacer(_ delta: Int) {
        let liste = affichees
        guard !liste.isEmpty else { return }
        let courant = liste.firstIndex { $0.id == entreeChoisie?.id } ?? 0
        selection = liste[Selection.deplacer(courant, de: delta, sur: liste.count)].id
    }

    func recoller(_ e: EntreeHistorique? = nil) { if let e = e ?? entreeChoisie { surRecoller(e) } }

    func copier(_ e: EntreeHistorique? = nil) {
        guard let e = e ?? entreeChoisie else { return }
        surCopier(e)
        copiee = e.id
        let id = e.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in if self?.copiee == id { self?.copiee = nil } }
    }

    func basculerDeveloppee(_ e: EntreeHistorique? = nil) {
        guard let e = e ?? entreeChoisie else { return }
        developpee = developpee == e.id ? nil : e.id
        selection = e.id
        suppressionEnAttente = nil
    }

    func demanderSuppression(_ e: EntreeHistorique) { suppressionEnAttente = e.id }
    func annulerSuppression() { suppressionEnAttente = nil }

    /// Supprime la dictée et choisit sa voisine (la suivante, sinon la précédente).
    func confirmerSuppression(_ e: EntreeHistorique) {
        let liste = affichees
        let voisine = liste.firstIndex { $0.id == e.id }.flatMap { i in liste.indices.contains(i + 1) ? liste[i + 1].id : (i > 0 ? liste[i - 1].id : nil) }
        store.supprimer(id: e.id)
        suppressionEnAttente = nil
        if developpee == e.id { developpee = nil }
        selection = voisine
    }

    /// Les commandes du champ : ↑ ↓ choisir, Entrée recoller, Échap (efface la recherche puis ferme), ⌘C copier…
    func commande(_ c: CommandeChamp) -> Bool {
        switch c {
        case .haut: deplacer(-1)
        case .bas: deplacer(1)
        case .entree: recoller()
        case .echap:
            if requete.isEmpty { surEchap() } else { requete = "" }
        case .ouvrirFenetre: surOuvrirFenetre()
        case .copier: copier()
        case .voirTout: basculerDeveloppee()
        case .focus: jetonFocus += 1
        }
        return true
    }
}

/// Champ de recherche + liste groupée par jour, avec les états vides.
struct DicteesVue: View {
    @ObservedObject var m: ModeleDictees
    @ObservedObject var store: HistoriqueStore
    var metriques: MetriquesListe = .panneau
    var invite = "Rechercher"
    var icones = true
    /// Vrai dans les rendus PNG : le champ n'a pas le focus, on dessine donc le curseur ambre à sa place.
    var curseurFactice = false

    var body: some View {
        let liste = m.affichees
        VStack(spacing: 0) {
            champ
            if store.historique.estVide {
                vide("Aucune dictée pour l\u{2019}instant.", detail: "Maintenez fn, parlez, relâchez.")
            } else if liste.isEmpty {
                vide("Aucun résultat", detail: nil)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(Historique.groupes(liste).enumerated()), id: \.element.titre) { _, groupe in
                                Text(groupe.titre)
                                    .font(Polices.commande(metriques.meta))
                                    .foregroundStyle(Palette.texte3)
                                    .padding(.leading, metriques.marge + metriques.colonneHeure + 8)
                                    .padding(.top, 12).padding(.bottom, 4)
                                    .accessibilityAddTraits(.isHeader)
                                ForEach(groupe.entrees) { e in
                                    ligne(e).id(e.id)
                                }
                            }
                        }
                    }
                    .onChange(of: m.selection) { _, id in
                        if let id { withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id) } }
                    }
                }
            }
        }
    }

    private var champ: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .regular)).foregroundStyle(Palette.texte3).frame(width: 16)
            ZStack(alignment: .leading) {
                ChampRecherche(texte: $m.requete, invite: invite, taille: metriques.meta + 1, jetonFocus: m.jetonFocus, surCommande: m.commande)
                if curseurFactice && m.requete.isEmpty {
                    RoundedRectangle(cornerRadius: 1).fill(Palette.accent).frame(width: 2, height: 16).offset(x: -2)
                }
            }
            if metriques.ligne > 40 {
                Text("\u{2318} K").font(Polices.commande(12)).foregroundStyle(Palette.texte3)
            }
        }
        .padding(.horizontal, metriques.marge)
        .frame(height: metriques.hauteurChamp)
        .background(metriques.ligne > 40 ? RoundedRectangle(cornerRadius: 8).fill(Palette.selection.opacity(0.55)) : nil)
        .padding(.bottom, metriques.ligne > 40 ? 6 : 0)
    }

    private func vide(_ titre: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titre).font(Polices.texte(metriques.police)).foregroundStyle(Palette.texte3)
            if let detail { Text(detail).font(Polices.commande(metriques.meta + 1)).foregroundStyle(Palette.texte3) }
        }
        .padding(.leading, metriques.marge + 8)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func ligne(_ e: EntreeHistorique) -> some View {
        LigneDictee(e: e, m: m, metriques: metriques, choisie: m.entreeChoisie?.id == e.id, depliee: m.developpee == e.id)
    }
}

struct LigneDictee: View {
    let e: EntreeHistorique
    @ObservedObject var m: ModeleDictees
    var metriques: MetriquesListe
    var choisie: Bool
    var depliee: Bool
    @State private var survol = false

    private static let formatHeure: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.dateFormat = "HH:mm"; return f
    }()

    var body: some View {
        let actif = choisie || survol
        HStack(alignment: depliee ? .top : .center, spacing: 8) {
            Text(Self.formatHeure.string(from: e.date))
                .font(Polices.commande(metriques.meta).monospacedDigit())
                .foregroundStyle(Palette.texte3)
                .frame(width: metriques.colonneHeure, alignment: .leading)
                .padding(.top, depliee ? 3 : 0)
            Text(e.texte)
                .font(Polices.texte(metriques.police))
                .foregroundStyle(actif ? Palette.texte : Palette.texte2)
                .lineLimit(depliee ? nil : 1)
                .lineSpacing(depliee ? 3 : 0)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: depliee)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(depliee ? "" : e.texte)
            droite(actif: actif)
        }
        .padding(.horizontal, metriques.marge)
        .padding(.vertical, depliee ? 8 : 0)
        .frame(minHeight: metriques.ligne)
        .background(RoundedRectangle(cornerRadius: 8).fill(actif ? Palette.selection : .clear))
        .contentShape(Rectangle())
        .onHover { survol = $0 }
        .onTapGesture(count: 2) { m.selection = e.id; m.recoller(e) }
        .onTapGesture { m.selection = e.id }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(Self.formatHeure.string(from: e.date)), \(e.texte)")
        .accessibilityAddTraits(choisie ? [.isSelected, .isButton] : .isButton)
        .accessibilityAction(named: "Recoller") { m.recoller(e) }
        .accessibilityAction(named: "Copier") { m.copier(e) }
    }

    @ViewBuilder
    private func droite(actif: Bool) -> some View {
        if actif {
            HStack(spacing: 0) {
                BoutonIcone(symbole: "doc.on.doc", etiquette: "Copier", retour: m.copiee == e.id, taille: metriques.icone) { m.copier(e) }
                BoutonIcone(symbole: "doc.on.clipboard", etiquette: "Recoller dans \(e.appNom ?? "l\u{2019}app précédente")", taille: metriques.icone) { m.recoller(e) }
                BoutonIcone(symbole: depliee ? "chevron.up" : "chevron.down", etiquette: depliee ? "Réduire le texte" : "Voir le texte complet", taille: metriques.icone) { m.basculerDeveloppee(e) }
            }
            .padding(.trailing, -4)
        } else {
            Text(e.insere ? (e.appNom ?? "") : "Non écrite")
                .font(Polices.commande(metriques.meta))
                .foregroundStyle(Palette.texte3)
                .lineLimit(1)
                .frame(minWidth: 48, alignment: .trailing)
        }
    }
}

struct BoutonIcone: View {
    var symbole: String
    var etiquette: String
    var retour = false
    var taille: CGFloat = 28
    var action: () -> Void
    @State private var survol = false
    var body: some View {
        Button(action: action) {
            Group {
                if retour { Text("OK").font(Polices.commande(12)) }
                else { Image(systemName: symbole).font(.system(size: 13, weight: .regular)) }
            }
            .foregroundStyle(survol || retour ? Palette.texte : Palette.texte2)
            .frame(width: taille, height: taille)
            .background(RoundedRectangle(cornerRadius: 6).fill(survol ? Color.white.opacity(0.08) : .clear))
        }
        .buttonStyle(.plain)
        .onHover { survol = $0 }
        .help(etiquette)
        .accessibilityLabel(etiquette)
    }
}
