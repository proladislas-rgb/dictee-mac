import AppKit
import SwiftUI
import DicteeCore

// L'onglet « Bibliothèque » de la fenêtre de Verbe (maquette design/maquettes/ilot-bibliotheque.html, étape 6) : la vue complète, à côté
// de Dictées, Journée, Réunions et Mots. Les mêmes pastilles que l'îlot (avec leurs nombres), la recherche, le tri, les épinglés en haut,
// puis par date, en vignettes (QuickLook, lues hors du fil principal) ; à droite, « Ce que la bibliothèque montre » : les interrupteurs des
// sources (une autorisation macOS demandée au premier clic seulement) et ce qu'il faut savoir (rien n'est copié, « Retirer »).

/// L'état de l'onglet (à lui : l'îlot a le sien) : recherche, filtre, tri, fichiers choisis, dernier retrait.
@MainActor
final class BibliothequeFenetreEtat: ObservableObject {
    @Published var requete = "" { didSet { if requete != oldValue { retrait = nil } } }
    @Published var filtre: FiltreBibliotheque = .tout
    @Published var recents = true
    @Published var choisis: [String] = []
    @Published var retrait: RetraitBibliotheque?
    @Published var survol: String?
    @Published var jetonFocus = 0
    /// Ouvrir un fichier, le montrer dans le Finder (injectables).
    var ouvrir: (URL) -> Void = { NSWorkspace.shared.open($0) }
    var montrer: ([URL]) -> Void = { NSWorkspace.shared.activateFileViewerSelecting($0) }

    func basculer(_ id: String) { if let i = choisis.firstIndex(of: id) { choisis.remove(at: i) } else { choisis.append(id) } }

    func commande(_ c: CommandeChamp) -> Bool {
        switch c {
        case .echap: if requete.isEmpty { return false }; requete = ""; return true
        default: return false
        }
    }
}

struct BibliothequeFenetreVue: View {
    @ObservedObject var b: BibliothequeModele
    @ObservedObject var e: BibliothequeFenetreEtat
    /// Rendus PNG : ni défilement paresseux ni champ AppKit (ImageRenderer ne sait pas les dessiner).
    var statique = false
    static let largeurTuile: CGFloat = 128, hauteurVignette: CGFloat = 88, largeurCote: CGFloat = 262

    var body: some View {
        HStack(spacing: 0) {
            principal
            Rectangle().fill(Palette.filet).frame(width: 1)
            // la colonne des sources défile si la fenêtre est basse (fenêtre de 520 pt au plus petit)
            Group {
                if statique { CoteBibliotheque(b: b) } else { ScrollView(.vertical, showsIndicators: false) { CoteBibliotheque(b: b) } }
            }
            .frame(width: Self.largeurCote)
        }
        .onAppear { b.rafraichir(force: true) }
    }

    // MARK: la partie principale

    private var principal: some View {
        let tout = b.tout
        let vus = BibliothequeIlot.filtrer(tout, filtre: e.filtre, requete: e.requete)
        let groupes = BibliothequeIlot.groupes(vus, recents: e.recents, maintenant: b.maintenant())
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text(BibliothequeIlot.compte(tout.count, etagere: b.surEtagere)).font(Polices.commande(12.5)).foregroundStyle(Palette.texte3).lineLimit(1).fixedSize()
                Spacer(minLength: 8)
                champ
                tri
            }
            .frame(height: 34)
            HStack(spacing: 6) {
                ForEach(FiltreBibliotheque.allCases, id: \.self) { f in
                    PuceFenetre(titre: f.titre, nombre: BibliothequeIlot.filtrer(tout, filtre: f, requete: "").count, choisie: e.filtre == f) { e.filtre = f }
                }
            }
            .padding(.top, 12)
            if tout.isEmpty {
                vide("Rien pour l\u{2019}instant.", "Glisse des fichiers sur l\u{2019}encoche : l\u{2019}étagère les garde, la bibliothèque s\u{2019}en souvient. Ou allume une source à droite.")
            } else if vus.isEmpty {
                vide("Aucun fichier", "Essaie un autre mot, ou une autre pastille.")
            } else {
                defilable {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(groupes, id: \.titre) { g in
                            HStack(spacing: 6) {
                                if g.epingles { Image(systemName: "pin.fill").font(.system(size: 10, weight: .semibold)).rotationEffect(.degrees(35)) }
                                Text(g.titre).font(Polices.commande(12.5, .semibold))
                            }
                            .foregroundStyle(Palette.texte2)
                            .frame(height: 30, alignment: .bottom).padding(.bottom, 7)
                            .accessibilityAddTraits(.isHeader)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.largeurTuile, maximum: Self.largeurTuile), spacing: 14, alignment: .topLeading)],
                                      alignment: .leading, spacing: 12) {
                                ForEach(g.entrees) { x in TuileBibliotheque(x: x, b: b, e: e) }
                            }
                        }
                    }
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, 6)
            }
            Spacer(minLength: 0)
            barreDuBas
        }
        .padding(.trailing, 24).padding(.top, 2)   // sous le titre de la sous-page, aligné sur sa marge
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private func defilable<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        // rendus : posé en haut d'une place qui ne grandit pas avec lui (le reste est rogné, comme sous un défilement)
        if statique { Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity).overlay(alignment: .topLeading) { c() }.clipped() } else { ScrollView(.vertical, showsIndicators: true) { c() } }
    }

    private var champ: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").font(.system(size: 12.5)).foregroundStyle(Palette.texte3)
            if statique {
                Text(e.requete.isEmpty ? "Rechercher un fichier" : e.requete).font(Polices.commande(13)).foregroundStyle(e.requete.isEmpty ? Palette.texte3 : Palette.texte)
                    .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ChampRecherche(texte: $e.requete, invite: "Rechercher un fichier", taille: 13, jetonFocus: e.jetonFocus, surCommande: e.commande)
            }
        }
        .padding(.horizontal, 10)
        .frame(width: 230, height: 30)
        .background(RoundedRectangle(cornerRadius: 8).fill(Palette.selection))
    }

    private var tri: some View {
        Menu {
            Button("Plus récents d\u{2019}abord") { e.recents = true }
            Button("Plus anciens d\u{2019}abord") { e.recents = false }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.arrow.down").font(.system(size: 11.5, weight: .semibold))
                Text(e.recents ? "Plus récents d\u{2019}abord" : "Plus anciens d\u{2019}abord").font(Polices.commande(12.5)).lineLimit(1).fixedSize()
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Palette.texte3)
            }
            .foregroundStyle(Palette.texte2)
            .padding(.horizontal, 10).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 8).fill(Palette.selection))
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .accessibilityLabel("Trier")
    }

    /// En bas : des fichiers choisis (« Glisser les 3 », « 3 choisis », « Annuler »), ou le dernier retrait (« Annuler »).
    @ViewBuilder private var barreDuBas: some View {
        if !e.choisis.isEmpty {
            let choisis = b.tout.filter { e.choisis.contains($0.id) }
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "square.stack.3d.up.fill").font(.system(size: 12, weight: .semibold))
                    Text(choisis.count > 1 ? "Glisser les \(choisis.count)" : "Glisser").font(Polices.commande(13, .semibold)).lineLimit(1).fixedSize()
                }
                .foregroundStyle(Palette.texte)
                .padding(.horizontal, 12).frame(height: 30)
                .background(Capsule().fill(CouleursIlot.bleu.opacity(0.26)))
                .overlay(Capsule().strokeBorder(Palette.bleuVif.opacity(0.6), lineWidth: 1.5))
                .overlay { if !statique { SourceGlisserFichiers(fichiers: { choisis.map { (URL(fileURLWithPath: $0.chemin), b.icone($0)) } }, surDebut: {}, surFin: { if $0 { e.choisis = [] } }) } }
                .accessibilityLabel("Glisser les fichiers choisis vers une app")
                Text(BibliothequeIlot.choisis(choisis.count)).font(Polices.commande(12.5)).foregroundStyle(Palette.texte2)
                Spacer()
                LienTexte(titre: "Afficher dans le Finder") { e.montrer(choisis.map { URL(fileURLWithPath: $0.chemin) }) }
                LienTexte(titre: "Annuler") { e.choisis = [] }
            }
            .frame(height: 48)
        } else if let r = e.retrait {
            HStack(spacing: 8) {
                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.vertDoux)
                Text(BibliothequeIlot.messageRetrait(dossier: b.dossier(r.entree))).font(Polices.commande(12.5)).foregroundStyle(Palette.texte2).lineLimit(1)
                Spacer()
                LienTexte(titre: "Annuler") { b.annuler(r); e.retrait = nil }
            }
            .frame(height: 48)
        }
    }

    private func vide(_ titre: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titre).font(Polices.texte(18)).foregroundStyle(Palette.texte2)
            Text(detail).font(Polices.commande(13.5)).foregroundStyle(Palette.texte3).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 28)
        .frame(maxWidth: 460, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Une pastille de l'onglet, avec son nombre (« Documents 7 »).
private struct PuceFenetre: View {
    var titre: String
    var nombre: Int
    var choisie: Bool
    var action: () -> Void
    @State private var survol = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(titre).font(Polices.commande(12.5, .medium))
                Text("\(nombre)").font(Polices.commande(11.5, .medium).monospacedDigit()).opacity(0.6)
            }
            .foregroundStyle(choisie ? Palette.surface : Palette.texte2)
            .padding(.horizontal, 12).frame(height: 28)
            .background(Capsule().fill(choisie ? Palette.texte : (survol ? Palette.relief : Palette.selection)))
            .overlay(Capsule().strokeBorder(choisie ? Color.clear : Palette.filet, lineWidth: 1))
            .contentShape(Capsule())
            .fixedSize()
        }
        .buttonStyle(.plain)
        .onHover { survol = $0 }
        .accessibilityLabel("\(titre), \(nombre)")
        .accessibilityAddTraits(choisie ? .isSelected : [])
    }
}

/// Une vignette : l'aperçu QuickLook (l'icône en attendant), la punaise d'un épinglé, le nom et « d'où il vient · date · taille ». Un clic la
/// choisit (on glisse ensuite les fichiers choisis ensemble), un double-clic l'ouvre, on la glisse vers une app ; au survol, la punaise et
/// « Retirer » ; le menu contextuel a tout.
struct TuileBibliotheque: View {
    let x: EntreeBibliotheque
    @ObservedObject var b: BibliothequeModele
    @ObservedObject var e: BibliothequeFenetreEtat
    @State private var survol = false

    var body: some View {
        let choisie = e.choisis.contains(x.id)
        let l = BibliothequeFenetreVue.largeurTuile, h = BibliothequeFenetreVue.hauteurVignette
        VStack(alignment: .leading, spacing: 0) {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.selection)
                .frame(width: l, height: h)
                .overlay {
                    if let v = b.vignette(x), x.sorte == .image || x.sorte == .capture {
                        Image(nsImage: v).resizable().interpolation(.high).aspectRatio(contentMode: .fill).frame(width: l, height: h).clipped()
                    } else {
                        Image(nsImage: b.vignette(x) ?? b.icone(x)).resizable().interpolation(.high).aspectRatio(contentMode: .fit).frame(width: 56, height: 56)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(choisie ? Palette.bleuVif : .clear, lineWidth: 2))
                .overlay(alignment: .topTrailing) {
                    if survol {
                        HStack(spacing: 4) {
                            rond(x.epinglee ? "pin.slash.fill" : "pin.fill", x.epinglee ? "Détacher" : "Épingler") { b.epingler(x, !x.epinglee) }
                            rond("xmark", "Retirer de la bibliothèque") { e.retrait = b.retirer(x); e.choisis.removeAll { $0 == x.id } }
                        }
                        .padding(6)
                    } else if x.epinglee {
                        Image(systemName: "pin.fill").font(.system(size: 10.5, weight: .semibold)).rotationEffect(.degrees(35)).foregroundStyle(.white)
                            .frame(width: 22, height: 22).background(Circle().fill(Color.black.opacity(0.55))).padding(6)
                            .accessibilityLabel("Épinglé")
                    }
                }
                .overlay(alignment: .topLeading) {
                    if choisie {
                        Image(systemName: "checkmark").font(.system(size: 9.5, weight: .heavy)).foregroundStyle(.white)
                            .frame(width: 20, height: 20).background(Circle().fill(CouleursIlot.bleu)).overlay(Circle().strokeBorder(Palette.surface, lineWidth: 1.5))
                            .padding(6)
                    }
                }
            Text(x.nom).font(Polices.commande(12.5, .semibold)).foregroundStyle(Palette.texte).lineLimit(1).truncationMode(.middle).padding(.top, 6)
            Text(BibliothequeIlot.detail(x, maintenant: b.maintenant())).font(Polices.commande(11)).foregroundStyle(Palette.texte3).lineLimit(1).truncationMode(.tail)
        }
        .frame(width: l, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { survol = $0 }
        .gesture(TapGesture(count: 2).onEnded { e.ouvrir(URL(fileURLWithPath: x.chemin)) }.exclusively(before: TapGesture().onEnded { e.basculer(x.id) }))
        .onDrag { NSItemProvider(contentsOf: URL(fileURLWithPath: x.chemin)) ?? NSItemProvider() }
        .contextMenu {
            Button("Ouvrir") { e.ouvrir(URL(fileURLWithPath: x.chemin)) }
            Button("Afficher dans le Finder") { e.montrer([URL(fileURLWithPath: x.chemin)]) }
            Divider()
            Button(x.epinglee ? "Détacher" : "Épingler en haut") { b.epingler(x, !x.epinglee) }
            Button("Retirer de la bibliothèque") { e.retrait = b.retirer(x); e.choisis.removeAll { $0 == x.id } }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(x.nom), \(BibliothequeIlot.detail(x, maintenant: b.maintenant()))\(x.epinglee ? ", épinglé" : "")\(choisie ? ", choisi" : "")")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Ouvrir") { e.ouvrir(URL(fileURLWithPath: x.chemin)) }
        .accessibilityAction(named: choisie ? "Ne plus choisir" : "Choisir") { e.basculer(x.id) }
    }

    private func rond(_ symbole: String, _ etiquette: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbole).font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                .frame(width: 22, height: 22).background(Circle().fill(Color.black.opacity(0.62)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(etiquette)
    }
}

/// « Ce que la bibliothèque montre » : l'étagère (toujours), puis les sources qu'on allume, et ce qu'il faut savoir.
struct CoteBibliotheque: View {
    @ObservedObject var b: BibliothequeModele
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Ce que la bibliothèque montre").font(Polices.commande(13, .semibold)).foregroundStyle(Palette.texte)
            Text("L\u{2019}étagère, plus les sources que tu allumes.").font(Polices.commande(12)).foregroundStyle(Palette.texte3).padding(.top, 3)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                ForEach(SourceBibliotheque.allCases, id: \.self) { s in ligne(s) }
            }
            .padding(.top, 8)
            VStack(alignment: .leading, spacing: 7) {
                Text("\(Text("Rien n\u{2019}est copié.").bold().foregroundStyle(Palette.texte)) Voxile garde seulement le chemin de chaque fichier.")
                Text("\(Text("« Retirer »").bold().foregroundStyle(Palette.texte)) l\u{2019}enlève d\u{2019}ici ; le fichier, lui, reste où il est.")
                Text("Glisse un fichier vers une app. Choisis-en plusieurs pour les glisser ensemble.")
            }
            .font(Polices.commande(12)).foregroundStyle(Palette.texte2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12).padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Palette.selection))
            .padding(.top, 16)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18).padding(.vertical, 20)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Palette.voile(0.03))
    }

    private func ligne(_ s: SourceBibliotheque) -> some View {
        HStack(spacing: 10) {
            Image(systemName: LigneBibliothequeIlot.symbole(s)).font(.system(size: 15)).foregroundStyle(Palette.texte2).frame(width: 20)
            VStack(alignment: .leading, spacing: 0) {
                Text(s.titreReglage).font(Polices.commande(13, .semibold)).foregroundStyle(Palette.texte).lineLimit(1)
                Text(s.detailReglage).font(Polices.commande(11.5)).foregroundStyle(Palette.texte3).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if s == .etagere {
                Text("toujours").font(Polices.commande(11.5)).foregroundStyle(Palette.texte3)
            } else {
                Interrupteur(actif: .constant(b.sources.contains(s)), etiquette: "Montrer : \(s.titreReglage)") { b.allumer(s, $0) }
            }
        }
        .padding(.vertical, 6)
        .frame(minHeight: 48)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.filet).frame(height: 1) }
    }
}
