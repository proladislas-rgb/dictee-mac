import SwiftUI
import DicteeCore

/// Onglet Mots : le champ d'ajout, la proposition à valider en tête, puis « Noms à retenir » et « Raccourcis vocaux »
/// côte à côte (l'un sous l'autre quand la fenêtre est étroite). Ne change rien au modèle : seulement la vue.
struct MotsVue: View {
    @ObservedObject var m: MotsModele
    var marge: CGFloat = 0
    var curseurFactice = false
    @State private var nouveauMot = ""
    @State private var expression = ""
    @State private var remplacement = ""
    @State private var jetonMot = 0
    @State private var jetonRemplacement = 0
    @State private var jetonExpression = 0
    @State private var nouvelleExpression = ""
    @State private var jetonNouvelleExpression = 0
    /// En dessous de cette largeur de contenu, les deux colonnes passent en une.
    static let largeurDeuxColonnes: CGFloat = 680

    var body: some View {
        GeometryReader { g in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    champAjout
                    if let message = m.message {
                        Text(message).font(Polices.commande(13)).foregroundStyle(Palette.texte2).padding(.top, 8).padding(.leading, 4)
                            .accessibilityLabel(message)
                    }
                    ForEach(m.propositions.enAttente, id: \.self) { mot in proposition(mot) }
                    ligneApprentissage
                    if g.size.width >= Self.largeurDeuxColonnes {
                        HStack(alignment: .top, spacing: 56) {
                            noms.frame(maxWidth: .infinity, alignment: .topLeading)
                            raccourcis.frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                        .padding(.top, 28)
                    } else {
                        VStack(alignment: .leading, spacing: 28) { noms; raccourcis }.padding(.top, 28)
                    }
                    tesExpressions.padding(.top, 28)
                }
                .padding(.vertical, 20)
                .padding(.horizontal, marge)
            }
        }
    }

    // MARK: ajout d'un nom

    private var champAjout: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus").font(.system(size: 14)).foregroundStyle(Palette.texte2).frame(width: 18)
            ZStack(alignment: .leading) {
                ChampRecherche(texte: $nouveauMot, invite: "Ajouter un mot", taille: 16, jetonFocus: jetonMot) { c in
                    switch c {
                    case .entree: m.ajouterMot(nouveauMot); if m.message == nil { nouveauMot = "" }
                    case .echap: nouveauMot = ""; m.message = nil
                    default: return false
                    }
                    return true
                }
                if curseurFactice && nouveauMot.isEmpty { RoundedRectangle(cornerRadius: 1).fill(Palette.accent).frame(width: 2, height: 20).offset(x: -2) }
            }
            Touche(symbole: "return", petit: true).opacity(nouveauMot.isEmpty ? 0.6 : 1)
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(RoundedRectangle(cornerRadius: 10).fill(Palette.selection))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.filet, lineWidth: 1))
    }

    // MARK: proposition à valider

    private func proposition(_ mot: String) -> some View {
        HStack(spacing: 14) {
            Text("\(m.propositions.enAttente.count)")
                .font(Polices.commande(12, .medium)).foregroundStyle(Palette.texte)
                .frame(minWidth: 20, minHeight: 20)
                .background(Capsule().fill(Palette.relief))
            (Text("À valider : ").foregroundStyle(Palette.texte) + Text(mot).foregroundStyle(Palette.texte).fontWeight(.medium) +
             Text(" revient dans tes corrections").foregroundStyle(Palette.texte2))
                .font(Polices.commande(15)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            BoutonPlein(titre: "Ajouter", hauteur: 32) { m.accepter(mot) }.fixedSize()
            BoutonSobre(titre: "Ignorer", symbole: nil, hauteur: 32) { m.ignorer(mot) }.fixedSize()
        }
        .padding(.leading, 16).padding(.trailing, 12).padding(.vertical, 8)
        .frame(minHeight: 56)
        .background(RoundedRectangle(cornerRadius: 10).fill(Palette.selection))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.contour, lineWidth: 1))
        .padding(.top, 16)
        .accessibilityElement(children: .contain)
    }

    // MARK: noms à retenir

    private var noms: some View {
        VStack(alignment: .leading, spacing: 0) {
            EnteteSection(titre: "Noms à retenir", phrase: "Voxile les écrit toujours avec cette orthographe.", compte: m.mots.count)
            if m.mots.isEmpty {
                Text("Aucun nom pour l\u{2019}instant.").font(Polices.texte(18)).foregroundStyle(Palette.texte2).padding(.vertical, 12)
            }
            ForEach(Array(m.mots.enumerated()), id: \.element) { i, mot in
                LigneMot(mot: mot, premiere: i == 0) { m.retirerMot(mot) }
            }
        }
    }

    // MARK: apprentissage automatique et expressions

    /// « Verbe a appris 3 mots et expressions cette semaine » : sobre, sans bouton (l'apprentissage est automatique).
    private var ligneApprentissage: some View {
        let n = m.apprisCetteSemaine
        let phrase = n == 0 ? "Voxile apprend tout seul de tes dictées et de tes corrections."
                            : "Voxile a appris \(n) mot\(n > 1 ? "s" : "") et expression\(n > 1 ? "s" : "") cette semaine."
        return Text(phrase).font(Polices.commande(13)).foregroundStyle(Palette.texte2).padding(.top, 10).padding(.leading, 4)
            .accessibilityLabel(phrase)
    }

    private var tesExpressions: some View {
        VStack(alignment: .leading, spacing: 0) {
            EnteteSection(titre: "Tes expressions", phrase: "Ce que tu dis souvent. Voxile le repère tout seul dans tes dictées ; retire ce qui n\u{2019}a rien à faire ici.", compte: m.expressions.count)
            if m.expressions.isEmpty {
                Text("Pas encore d\u{2019}expression : Voxile les cherche une fois par jour dans tes dictées.").font(Polices.commande(14)).foregroundStyle(Palette.texte2).padding(.vertical, 12)
            }
            ForEach(Array(m.expressions.enumerated()), id: \.element.texte) { i, e in
                LigneExpression(e: e, premiere: i == 0) { m.retirerExpression(e.texte) }
            }
            HStack(spacing: 12) {
                champEncadre($nouvelleExpression, invite: "Ajouter une expression", jeton: jetonNouvelleExpression) { c in
                    if c == .entree { ajouterExpression(); return true }
                    return false
                }
                BoutonCadre("Ajouter", action: ajouterExpression)
            }
            .padding(.top, 12)
        }
    }

    private func ajouterExpression() {
        if m.ajouterExpression(nouvelleExpression) { nouvelleExpression = ""; jetonNouvelleExpression += 1 }
    }

    // MARK: raccourcis vocaux

    private var raccourcis: some View {
        VStack(alignment: .leading, spacing: 0) {
            EnteteSection(titre: "Raccourcis vocaux", phrase: "Dis la phrase de gauche, Voxile écrit le texte de droite.", compte: m.raccourcis.count)
            ForEach(Array(m.raccourcis.enumerated()), id: \.element.id) { i, r in
                LigneRaccourci(r: r, premiere: i == 0) { m.retirerRaccourci(r) }
            }
            ajoutRaccourci
        }
    }

    private var ajoutRaccourci: some View {
        HStack(spacing: 12) {
            champEncadre($expression, invite: "Quand je dis…", jeton: jetonExpression) { c in
                if c == .entree { jetonRemplacement += 1; return true }
                return false
            }
            .frame(width: 150)
            Image(systemName: "arrow.right").font(.system(size: 12)).foregroundStyle(Palette.texte3).frame(width: 20)
            champEncadre($remplacement, invite: "Voxile écrit…", jeton: jetonRemplacement) { c in
                if c == .entree { ajouterRaccourci(); return true }
                return false
            }
            BoutonCadre("Ajouter", action: ajouterRaccourci)
        }
        .padding(.top, 12)
    }

    private func champEncadre(_ texte: Binding<String>, invite: String, jeton: Int, surCommande: @escaping (CommandeChamp) -> Bool) -> some View {
        ChampRecherche(texte: texte, invite: invite, taille: 14, jetonFocus: jeton, surCommande: surCommande)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.contour, lineWidth: 1))
    }

    private func ajouterRaccourci() {
        if m.ajouterRaccourci(expression: expression, texte: remplacement) { expression = ""; remplacement = ""; jetonExpression += 1 }
    }
}

struct LigneMot: View {
    var mot: String
    var premiere = false
    var retirer: () -> Void
    @State private var survol = false
    var body: some View {
        HStack {
            Text(mot).font(Polices.texte(19)).foregroundStyle(Palette.texte).lineLimit(1)
            Spacer()
            BoutonIcone(symbole: "xmark", etiquette: "Retirer \u{00AB}\u{00A0}\(mot)\u{00A0}\u{00BB}", taille: 28, action: retirer).opacity(survol ? 1 : 0)
        }
        .frame(height: 44)
        .overlay(alignment: .top) { if !premiere { Rectangle().fill(Palette.filet).frame(height: 1) } }
        .contentShape(Rectangle())
        .onHover { survol = $0 }
    }
}

struct LigneExpression: View {
    var e: ExpressionPerso
    var premiere = false
    var retirer: () -> Void
    @State private var survol = false
    var body: some View {
        HStack(spacing: 12) {
            Text(e.texte).font(Polices.texte(19)).foregroundStyle(Palette.texte).lineLimit(1)
            Spacer()
            if e.manuelle { Text("ajoutée par toi").font(Polices.commande(12)).foregroundStyle(Palette.texte3) }
            else if e.dictees > 0 { Text("\(e.dictees) dictées").font(Polices.commande(12)).foregroundStyle(Palette.texte3) }
            BoutonIcone(symbole: "xmark", etiquette: "Retirer \u{00AB}\u{00A0}\(e.texte)\u{00A0}\u{00BB}", taille: 28, action: retirer).opacity(survol ? 1 : 0)
        }
        .frame(height: 44)
        .overlay(alignment: .top) { if !premiere { Rectangle().fill(Palette.filet).frame(height: 1) } }
        .contentShape(Rectangle())
        .onHover { survol = $0 }
    }
}

struct LigneRaccourci: View {
    var r: RaccourciVocal
    var premiere = false
    var retirer: () -> Void
    @State private var survol = false
    var body: some View {
        HStack(spacing: 12) {
            Text(r.expression).font(Polices.commande(15)).foregroundStyle(Palette.texte2).lineLimit(1).frame(width: 150, alignment: .leading)
            Image(systemName: "arrow.right").font(.system(size: 12)).foregroundStyle(Palette.texte3).frame(width: 20)
            Text(r.texte).font(Polices.texte(18)).foregroundStyle(Palette.texte).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
            BoutonIcone(symbole: "xmark", etiquette: "Retirer le raccourci \u{00AB}\u{00A0}\(r.expression)\u{00A0}\u{00BB}", taille: 28, action: retirer).opacity(survol ? 1 : 0)
        }
        .frame(height: 44)
        .overlay(alignment: .top) { if !premiere { Rectangle().fill(Palette.filet).frame(height: 1) } }
        .contentShape(Rectangle())
        .onHover { survol = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(r.expression) donne \(r.texte)")
    }
}
