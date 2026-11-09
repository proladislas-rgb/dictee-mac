import SwiftUI
import DicteeCore

/// Onglet Mots : le champ d'ajout, les noms à retenir (Newsreader), les raccourcis vocaux, les propositions en attente.
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

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                champAjout
                if let message = m.message {
                    Text(message).font(Polices.commande(13)).foregroundStyle(Palette.texte3).padding(.leading, 36).padding(.bottom, 6)
                        .accessibilityLabel(message)
                }
                titre("Noms à retenir").padding(.top, 14)
                if m.mots.isEmpty {
                    Text("Aucun nom pour l\u{2019}instant.").font(Polices.texte(17)).foregroundStyle(Palette.texte3).padding(.vertical, 8)
                }
                ForEach(m.mots, id: \.self) { mot in LigneMot(mot: mot) { m.retirerMot(mot) } }
                titre("Raccourcis vocaux").padding(.top, 26)
                ForEach(m.raccourcis) { r in LigneRaccourci(r: r) { m.retirerRaccourci(r) } }
                ajoutRaccourci
                ForEach(m.propositions.enAttente, id: \.self) { mot in proposition(mot).padding(.top, 22) }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, marge)
        }
    }

    private var champAjout: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus").font(.system(size: 14)).foregroundStyle(Palette.texte3).frame(width: 18)
            ZStack(alignment: .leading) {
                ChampRecherche(texte: $nouveauMot, invite: "Ajouter un mot", taille: 15, jetonFocus: jetonMot) { c in
                    switch c {
                    case .entree: m.ajouterMot(nouveauMot); if m.message == nil { nouveauMot = "" }
                    case .echap: nouveauMot = ""; m.message = nil
                    default: return false
                    }
                    return true
                }
                if curseurFactice && nouveauMot.isEmpty { RoundedRectangle(cornerRadius: 1).fill(Palette.accent).frame(width: 2, height: 18).offset(x: -2) }
            }
        }
        .frame(height: 44)
    }

    private var ajoutRaccourci: some View {
        HStack(spacing: 16) {
            ChampRecherche(texte: $expression, invite: "Quand je dis…", taille: 14, jetonFocus: jetonExpression) { c in
                if c == .entree { jetonRemplacement += 1; return true }
                return false
            }
            .frame(width: 190).overlay(alignment: .bottom) { Rectangle().fill(Palette.filet).frame(height: 1).offset(y: 4) }
            ChampRecherche(texte: $remplacement, invite: "écrire…", taille: 14, jetonFocus: jetonRemplacement) { c in
                if c == .entree { ajouterRaccourci(); return true }
                return false
            }
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.filet).frame(height: 1).offset(y: 4) }
            LienTexte(titre: "Ajouter") { ajouterRaccourci() }
        }
        .frame(height: 44)
    }

    private func ajouterRaccourci() {
        if m.ajouterRaccourci(expression: expression, texte: remplacement) { expression = ""; remplacement = ""; jetonExpression += 1 }
    }

    private func proposition(_ mot: String) -> some View {
        HStack(spacing: 16) {
            HStack(spacing: 5) {
                Text(mot).foregroundStyle(Palette.texte)
                Text("revient dans tes corrections").foregroundStyle(Palette.texte3)
            }
            .font(Polices.commande(14))
            Spacer()
            LienTexte(titre: "Ajouter", fort: true) { m.accepter(mot) }
            LienTexte(titre: "Ignorer") { m.ignorer(mot) }
        }
        .frame(minHeight: 36)
        .accessibilityElement(children: .combine)
    }

    private func titre(_ texte: String) -> some View {
        Text(texte).font(Polices.commande(13)).foregroundStyle(Palette.texte3).padding(.bottom, 4).accessibilityAddTraits(.isHeader)
    }
}

struct LigneMot: View {
    var mot: String
    var retirer: () -> Void
    @State private var survol = false
    var body: some View {
        HStack {
            Text(mot).font(Polices.texte(17)).foregroundStyle(Palette.texte)
            Spacer()
            BoutonIcone(symbole: "xmark", etiquette: "Retirer \u{00AB}\u{00A0}\(mot)\u{00A0}\u{00BB}", taille: 28, action: retirer).opacity(survol ? 1 : 0)
        }
        .padding(.leading, 18)
        .frame(height: 36)
        .contentShape(Rectangle())
        .onHover { survol = $0 }
    }
}

struct LigneRaccourci: View {
    var r: RaccourciVocal
    var retirer: () -> Void
    @State private var survol = false
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(r.expression).font(Polices.commande(14)).foregroundStyle(Palette.texte2).lineLimit(1).frame(width: 190, alignment: .leading)
            Text(r.texte).font(Polices.texte(17)).foregroundStyle(Palette.texte).lineLimit(1).truncationMode(.tail)
            Spacer()
            BoutonIcone(symbole: "xmark", etiquette: "Retirer le raccourci \u{00AB}\u{00A0}\(r.expression)\u{00A0}\u{00BB}", taille: 28, action: retirer).opacity(survol ? 1 : 0)
        }
        .frame(height: 40)
        .contentShape(Rectangle())
        .onHover { survol = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(r.expression) donne \(r.texte)")
    }
}
