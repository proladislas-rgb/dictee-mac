import AppKit
import SwiftUI
import DicteeCore

/// L'onglet Dictées de la fenêtre principale : ligne d'état, recherche, groupes par jour, ligne dépliée avec ses actions,
/// aide clavier en bas. (Le panneau compact garde `DicteesVue`.)
struct DicteesFenetreVue: View {
    @ObservedObject var m: ModeleDictees
    @ObservedObject var store: HistoriqueStore
    @ObservedObject var reglages: ReglagesModele
    var curseurFactice = false
    /// La marge des pages de la fenêtre (alignée sur les titres).
    static let margeH: CGFloat = TonsBureau.margeH

    var body: some View {
        let liste = m.affichees
        VStack(spacing: 0) {
            LigneEtat(store: store, reglages: reglages)
            champ.padding(.horizontal, Self.margeH)
            if store.historique.estVide {
                vide("Aucune dictée pour l\u{2019}instant.", detail: "Maintiens fn, parle, relâche : elle apparaît ici.")
            } else if liste.isEmpty {
                vide("Aucun résultat", detail: "Essaie un autre mot, ou le nom de l\u{2019}app.")
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(Historique.groupes(liste).enumerated()), id: \.element.titre) { _, groupe in
                                EnteteJour(groupe: groupe)
                                ForEach(groupe.entrees) { e in
                                    LigneFenetre(e: e, m: m, choisie: m.entreeChoisie?.id == e.id, depliee: m.developpee == e.id).id(e.id)
                                }
                            }
                        }
                        .padding(.horizontal, Self.margeH)
                        .padding(.bottom, 12)
                    }
                    .onChange(of: m.selection) { _, id in
                        if let id { withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id) } }
                    }
                    .onChange(of: m.developpee) { _, id in
                        if let id { withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id) } }
                    }
                }
            }
            Spacer(minLength: 0)
            AideClavier()
        }
    }

    private var champ: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundStyle(Palette.texte2).frame(width: 18)
            ZStack(alignment: .leading) {
                ChampRecherche(texte: $m.requete, invite: "Rechercher dans les dictées", taille: 16, jetonFocus: m.jetonFocus, surCommande: m.commande, espaceDeplie: true)
                if curseurFactice && m.requete.isEmpty {
                    RoundedRectangle(cornerRadius: 1).fill(Palette.accent).frame(width: 2, height: 20).offset(x: -2)
                }
            }
            Touche(texte: "\u{2318} K", petit: true).opacity(0.9)
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(RoundedRectangle(cornerRadius: 10).fill(Palette.selection))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.filet, lineWidth: 1))
        .padding(.bottom, 4)
    }

    private func vide(_ titre: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titre).font(Polices.texte(18)).foregroundStyle(Palette.texte2)
            Text(detail).font(Polices.commande(14)).foregroundStyle(Palette.texte3)
        }
        .padding(.horizontal, Self.margeH + 16)
        .padding(.top, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: ligne d'état

/// « 195 dictées · 4 120 mots aujourd'hui », puis à droite le moteur, le micro réellement utilisé, la touche et la langue.
struct LigneEtat: View {
    @ObservedObject var store: HistoriqueStore
    @ObservedObject var reglages: ReglagesModele

    private static let formatNombre: NumberFormatter = {
        let f = NumberFormatter(); f.locale = Locale(identifier: "fr_FR"); f.numberStyle = .decimal; f.usesGroupingSeparator = true; return f
    }()
    private static func nombre(_ n: Int) -> String { (formatNombre.string(from: NSNumber(value: n)) ?? "\(n)").replacingOccurrences(of: "\u{202F}", with: "\u{00A0}") }

    var body: some View {
        let n = store.historique.entrees.count
        let mots = store.historique.motsLe()
        HStack(spacing: 16) {
            Text("\(Text(Self.nombre(n)).foregroundStyle(Palette.texte).fontWeight(.medium)) dictée\(n > 1 ? "s" : "") \u{00B7} \(Text(Self.nombre(mots)).foregroundStyle(Palette.texte).fontWeight(.medium)) mot\(mots > 1 ? "s" : "") aujourd\u{2019}hui")
                .lineLimit(1)
            Spacer(minLength: 8)
            ViewThatFits(in: .horizontal) {
                droite(micro: true)
                droite(micro: false)
            }
        }
        .font(Polices.commande(14))
        .foregroundStyle(Palette.texte2)
        .padding(.horizontal, DicteesFenetreVue.margeH)
        .frame(height: 48)
    }

    private func droite(micro: Bool) -> some View {
        HStack(spacing: 24) {
            if reglages.cle != .absente {
                item("checkmark", "Groq")
            } else if reglages.secoursApple {
                item("exclamationmark.circle", "Apple (secours)")
            } else {
                item("exclamationmark.circle", "Clé manquante")
            }
            if micro { item("mic", reglages.microUtilise) }
            item("keyboard", "fn \u{00B7} \(reglages.nomLangue)")
        }
        .lineLimit(1)
        .fixedSize()
    }

    private func item(_ symbole: String, _ texte: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbole).font(.system(size: 13, weight: .regular))
            Text(texte)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: groupes

/// « Aujourd'hui · lundi 9 novembre » à gauche, « 5 dictées » à droite.
struct EnteteJour: View {
    var groupe: GroupeHistorique
    private static let formatJour: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.setLocalizedDateFormatFromTemplate("EEEEdMMMM"); return f
    }()
    var body: some View {
        let relatif = groupe.titre == "Aujourd\u{2019}hui" || groupe.titre == "Hier"
        HStack {
            if relatif, let jour = groupe.jour {
                Text("\(Text(groupe.titre).foregroundStyle(Palette.texte).fontWeight(.medium)) \u{00B7} \(Self.formatJour.string(from: jour))")
            } else {
                Text(groupe.titre)
            }
            Spacer()
            Text("\(groupe.entrees.count) dictée\(groupe.entrees.count > 1 ? "s" : "")")
        }
        .font(Polices.commande(13))
        .foregroundStyle(Palette.texte2)
        .padding(.horizontal, 16)
        .padding(.top, 20).padding(.bottom, 8)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: lignes

/// L'icône de l'app cible : la vraie, sinon une pastille neutre avec l'initiale.
struct IconeAppCible: View {
    var appId: String?
    var nom: String?
    var taille: CGFloat = 24
    var body: some View {
        if let image = IconesApps.icone(appId: appId) {
            Image(nsImage: image).resizable().interpolation(.high).frame(width: taille, height: taille)
        } else {
            RoundedRectangle(cornerRadius: taille * 0.25, style: .continuous).fill(Palette.relief)
                .frame(width: taille, height: taille)
                .overlay {
                    if let initiale = nom?.first { Text(String(initiale).uppercased()).font(Polices.commande(taille * 0.5, .medium)).foregroundStyle(Palette.texte2) }
                    else { Image(systemName: "text.cursor").font(.system(size: taille * 0.45)).foregroundStyle(Palette.texte2) }
                }
        }
    }
}

struct LigneFenetre: View {
    let e: EntreeHistorique
    @ObservedObject var m: ModeleDictees
    var choisie: Bool
    var depliee: Bool
    @State private var survol = false

    private static let formatHeure: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.dateFormat = "HH:mm"; return f
    }()
    private var heure: String { Self.formatHeure.string(from: e.date) }
    private var appAffichee: String { e.insere ? (e.appNom ?? "") : "Non écrite" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                Text(heure).font(Polices.commande(14).monospacedDigit()).foregroundStyle(Palette.texte2).frame(width: 56, alignment: .leading)
                IconeAppCible(appId: e.appId, nom: e.appNom)
                if depliee {
                    Spacer(minLength: 0)
                } else {
                    Text(e.texte)
                        .font(Polices.texte(18))
                        .foregroundStyle(Palette.texte)
                        .lineLimit(1).truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text(appAffichee).font(Polices.commande(13)).foregroundStyle(Palette.texte2).lineLimit(1).frame(minWidth: 64, alignment: .trailing)
            }
            .frame(height: 52)
            if depliee { detail }
        }
        .padding(.horizontal, 16)
        .background(RoundedRectangle(cornerRadius: 10).fill(depliee || choisie ? Palette.selection : (survol ? Palette.selection.opacity(0.5) : .clear)))
        .overlay { if depliee { RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.contour, lineWidth: 1) } }
        .padding(.vertical, depliee ? 4 : 0)
        .contentShape(Rectangle())
        .onHover { survol = $0 }
        .onTapGesture { m.basculerDeveloppee(e) }
        .accessibilityElement(children: depliee ? .contain : .combine)
        .accessibilityLabel("\(heure), \(e.texte), \(appAffichee)")
        .accessibilityAddTraits(choisie ? [.isSelected, .isButton] : .isButton)
        .accessibilityAction(named: "Recoller") { m.recoller(e) }
        .accessibilityAction(named: "Copier") { m.copier(e) }
        .accessibilityAction(named: depliee ? "Réduire" : "Déplier") { m.basculerDeveloppee(e) }
    }

    /// Le texte complet, puis les actions : recoller (principale), copier, supprimer ; mots à droite.
    private var detail: some View {
        let mots = Historique.compterMots(e.texte)
        let destination = m.nomDestination()
        return VStack(alignment: .leading, spacing: 0) {
            Text(e.texte)
                .font(Polices.texte(18))
                .foregroundStyle(Palette.texte)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(.leading, 112)
                .padding(.top, -6)
            Group {
                if m.suppressionEnAttente == e.id {
                    HStack(spacing: 8) {
                        Text("Supprimer cette dictée ?").font(Polices.commande(14)).foregroundStyle(Palette.texte2).lineLimit(1)
                        BoutonCadre("Supprimer") { m.confirmerSuppression(e) }
                        BoutonCadre("Garder") { m.annulerSuppression() }
                        Spacer(minLength: 0)
                    }
                } else {
                    // Fenêtre étroite : le nombre de mots passe d'abord à la trappe, puis « Supprimer » ne garde que sa corbeille,
                    // puis « Recoller dans Mail » devient « Recoller ».
                    ViewThatFits(in: .horizontal) {
                        actions(e, destination: destination, mots: mots)
                        actions(e, destination: destination, mots: nil)
                        actions(e, destination: destination, mots: nil, corbeilleSeule: true)
                        actions(e, destination: nil, mots: nil, corbeilleSeule: true)
                    }
                }
            }
            .padding(.leading, 112).padding(.vertical, 16)
        }
    }
}

extension LigneFenetre {
    /// Recoller (principale), Copier, Supprimer ; à droite le nombre de mots quand il y a la place.
    @ViewBuilder
    fileprivate func actions(_ e: EntreeHistorique, destination: String?, mots: Int?, corbeilleSeule: Bool = false) -> some View {
        HStack(spacing: 8) {
            BoutonPlein(titre: destination.map { "Recoller dans \($0)" } ?? "Recoller", symbole: "return", action: { m.recoller(e) }) {
                Touche(symbole: "return", sombre: true, petit: true)
            }
            .fixedSize()
            BoutonCadre(m.copiee == e.id ? "Copié" : "Copier", symbole: m.copiee == e.id ? "checkmark" : "doc.on.doc") { m.copier(e) }
                .fixedSize()
            if corbeilleSeule {
                BoutonIcone(symbole: "trash", etiquette: "Supprimer", taille: 36) { m.demanderSuppression(e) }
            } else {
                BoutonSobre(titre: "Supprimer", symbole: "trash") { m.demanderSuppression(e) }.fixedSize()
            }
            Spacer(minLength: 8)
            if let mots {
                Text("\(mots) mot\(mots > 1 ? "s" : "")").font(Polices.commande(13)).foregroundStyle(Palette.texte2).lineLimit(1).fixedSize()
            }
        }
    }
}

/// Bouton sans cadre (« Supprimer ») : texte et symbole discrets.
struct BoutonSobre: View {
    var titre: String
    var symbole: String?
    var hauteur: CGFloat = 36
    var action: () -> Void
    @State private var survol = false
    @FocusState private var focus: Bool
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let symbole { Image(systemName: symbole).font(.system(size: 13, weight: .regular)) }
                Text(titre).font(Polices.commande(14))
            }
            .foregroundStyle(survol ? Palette.texte : Palette.texte2)
            .padding(.horizontal, 8).frame(height: hauteur)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($focus)
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.texte3, lineWidth: 1.5).opacity(focus ? 1 : 0))
        .onHover { survol = $0 }
        .accessibilityLabel(titre)
    }
}

// MARK: aide clavier

/// ↑↓ choisir · ↵ recoller · espace déplier · ⌘C copier : tout ce qui est écrit ici marche vraiment.
struct AideClavier: View {
    var body: some View {
        HStack(spacing: 24) {
            groupe([Touche(symbole: "arrow.up", petit: true), Touche(symbole: "arrow.down", petit: true)], "choisir")
            groupe([Touche(symbole: "return", petit: true)], "recoller")
            groupe([Touche(texte: "espace", petit: true)], "déplier")
            groupe([Touche(texte: "\u{2318} C", petit: true)], "copier")
            Spacer(minLength: 0)
        }
        .lineLimit(1)
        .padding(.horizontal, DicteesFenetreVue.margeH)
        .frame(height: 48)
        .overlay(alignment: .top) { Rectangle().fill(Palette.filet).frame(height: 1) }
        .accessibilityHidden(true)
    }

    private func groupe(_ touches: [Touche], _ legende: String) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) { ForEach(touches.indices, id: \.self) { touches[$0] } }
            Text(legende).font(Polices.commande(13)).foregroundStyle(Palette.texte2)
        }
    }
}
