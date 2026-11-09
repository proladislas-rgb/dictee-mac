import AppKit
import SwiftUI
import UniformTypeIdentifiers
import DicteeCore

/// L'état de l'onglet Réunions : la liste, la note ouverte, la recherche, les actions (copier, exporter, effacer, cocher).
@MainActor
final class ReunionsModele: ObservableObject {
    @Published var ouverte: UUID?
    @Published var requete = "" { didSet { if requete != oldValue { selection = affichees.first?.id } } }
    @Published var selection: UUID?
    @Published var transcriptionDepliee = false
    @Published var suppressionEnAttente = false
    @Published var copiee = false
    @Published var notionCopie = false
    @Published var jetonFocus = 0
    let store: ReunionStore
    /// Réécrit la note d'une réunion sans note (branché par l'app).
    var surRefaireLaNote: (UUID) -> Void = { _ in }
    var surNoter: () -> Void = {}

    init(store: ReunionStore? = nil) { self.store = store ?? ReunionStore.shared }

    var affichees: [Reunion] {
        let mots = Historique.plier(requete).split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !mots.isEmpty else { return store.reunions }
        return store.reunions.filter { r in
            let cible = Historique.plier(([r.titreAffiche] + r.dit + r.decisions + r.actions.map(\.quoi) + r.segments.map(\.texte)).joined(separator: " "))
            return mots.allSatisfy { cible.contains($0) }
        }
    }

    /// Groupes par jour (même regroupement que l'historique des dictées).
    var groupes: [(titre: String, reunions: [Reunion])] {
        let liste = affichees
        let pseudo = liste.map { EntreeHistorique(id: $0.id, date: $0.debut, texte: $0.titreAffiche) }
        let parId = Dictionary(uniqueKeysWithValues: liste.map { ($0.id, $0) })
        return Historique.groupes(pseudo).map { g in (g.titre, g.entrees.compactMap { parId[$0.id] }) }
    }

    var reunionOuverte: Reunion? { ouverte.flatMap { store.reunion(id: $0) } }

    func reinitialiser() { ouverte = nil; requete = ""; selection = store.reunions.first?.id; jetonFocus += 1 }

    func ouvrir(_ id: UUID) {
        ouverte = id; selection = id; transcriptionDepliee = false; suppressionEnAttente = false; copiee = false; notionCopie = false
    }
    func fermerLaNote() { ouverte = nil; suppressionEnAttente = false }

    func deplacer(_ delta: Int) {
        let liste = affichees
        guard !liste.isEmpty else { return }
        let courant = liste.firstIndex { $0.id == selection } ?? 0
        selection = liste[Selection.deplacer(courant, de: delta, sur: liste.count)].id
    }

    func commande(_ c: CommandeChamp) -> Bool {
        switch c {
        case .haut: deplacer(-1)
        case .bas: deplacer(1)
        case .entree: if let id = selection ?? affichees.first?.id { ouvrir(id) }
        case .echap: if !requete.isEmpty { requete = "" }
        case .focus: jetonFocus += 1
        default: break
        }
        return true
    }

    // MARK: actions sur la note

    func titre(_ id: UUID, devient nouveau: String) {
        guard var r = store.reunion(id: id) else { return }
        let t = nouveau.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t != r.titre, !(t.isEmpty && r.titre.isEmpty) else { return }
        r.titre = t
        store.enregistrer(r)
    }

    func cocher(_ id: UUID, action: UUID) {
        guard var r = store.reunion(id: id), let i = r.actions.firstIndex(where: { $0.id == action }) else { return }
        r.actions[i].fait.toggle()
        store.enregistrer(r)
    }

    func copier(_ r: Reunion) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ReunionMarkdown.rendre(r), forType: .string)
        copiee = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.copiee = false }
    }

    /// Notion convertit du Markdown collé en blocs (titres, listes, cases à cocher) : le lien le plus simple est « copier, coller ».
    func copierPourNotion(_ r: Reunion) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ReunionMarkdown.rendre(r), forType: .string)
        notionCopie = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.notionCopie = false }
    }

    func exporterMarkdown(_ r: Reunion) {
        let panneau = NSSavePanel()
        panneau.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        let propre = r.titreAffiche.components(separatedBy: CharacterSet(charactersIn: "/:\\?%*|\"<>")).joined(separator: " ")
        panneau.nameFieldStringValue = "\(propre).md"
        panneau.title = "Exporter la note"
        panneau.begin { reponse in
            guard reponse == .OK, let url = panneau.url else { return }
            do { try ReunionMarkdown.rendre(r).write(to: url, atomically: true, encoding: .utf8) }
            catch { Log.ecrire("réunions : export impossible (\(error.localizedDescription))") }
        }
    }

    func supprimer(_ id: UUID) {
        store.supprimer(id: id)
        ouverte = nil; suppressionEnAttente = false
        selection = store.reunions.first?.id
    }
}

// MARK: onglet

struct ReunionsVue: View {
    @ObservedObject var m: ReunionsModele
    @ObservedObject var store: ReunionStore
    @ObservedObject var controleur: ReunionController
    var curseurFactice = false

    var body: some View {
        Group {
            if let r = m.reunionOuverte {
                NoteReunionVue(m: m, r: r)
            } else {
                ReunionsListeVue(m: m, store: store, controleur: controleur, curseurFactice: curseurFactice)
            }
        }
    }
}

/// « Gardé sur ce Mac » avec son cadenas : tout reste local.
struct MentionLocale: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock").font(.system(size: 12, weight: .regular))
            Text("Gardé sur ce Mac").font(Polices.commande(13))
        }
        .foregroundStyle(Palette.texte3)
        .accessibilityElement(children: .combine)
    }
}

// MARK: liste

struct ReunionsListeVue: View {
    @ObservedObject var m: ReunionsModele
    @ObservedObject var store: ReunionStore
    @ObservedObject var controleur: ReunionController
    var curseurFactice = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                champ
                BoutonPlein(titre: controleur.enregistre ? "Arrêter la réunion" : "Noter la réunion", symbole: controleur.enregistre ? "stop.fill" : "record.circle", action: m.surNoter) {
                    Touche(texte: "\u{2325}\u{2318}N", sombre: true, petit: true)
                }
                .fixedSize()
            }
            .padding(.horizontal, DicteesFenetreVue.margeH)
            .padding(.top, 8)

            if let libelle = controleur.libelleEnCours {
                HStack(spacing: 8) {
                    Circle().fill(Palette.accent).frame(width: 6, height: 6)
                    Text(libelle).font(Polices.commande(14)).foregroundStyle(Palette.texte2)
                    Spacer()
                }
                .padding(.horizontal, DicteesFenetreVue.margeH + 16).padding(.top, 14)
                .accessibilityElement(children: .combine)
            }

            if store.reunions.isEmpty {
                vide("Aucune réunion pour l\u{2019}instant.", detail: "Appuie sur \u{2325}\u{2318}N pendant un appel : Verbe écoute ton micro et le son du Mac, puis écrit la note.")
            } else if m.affichees.isEmpty {
                vide("Aucun résultat", detail: "Essaie un autre mot.")
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(m.groupes.enumerated()), id: \.offset) { _, g in
                                Text(g.titre).font(Polices.commande(13)).foregroundStyle(Palette.texte2)
                                    .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 8)
                                    .accessibilityAddTraits(.isHeader)
                                ForEach(g.reunions) { r in
                                    LigneReunion(r: r, choisie: m.selection == r.id) { m.ouvrir(r.id) } surSurvol: { m.selection = r.id }.id(r.id)
                                }
                            }
                        }
                        .padding(.horizontal, DicteesFenetreVue.margeH)
                        .padding(.bottom, 12)
                    }
                    .onChange(of: m.selection) { _, id in if let id { withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id) } } }
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 24) {
                HStack(spacing: 8) {
                    HStack(spacing: 4) { Touche(symbole: "arrow.up", petit: true); Touche(symbole: "arrow.down", petit: true) }
                    Text("choisir").font(Polices.commande(13)).foregroundStyle(Palette.texte2)
                }
                HStack(spacing: 8) {
                    Touche(symbole: "return", petit: true)
                    Text("ouvrir").font(Polices.commande(13)).foregroundStyle(Palette.texte2)
                }
                Spacer(minLength: 0)
                MentionLocale()
            }
            .lineLimit(1)
            .padding(.horizontal, DicteesFenetreVue.margeH)
            .frame(height: 48)
            .overlay(alignment: .top) { Rectangle().fill(Palette.filet).frame(height: 1) }
        }
        .onAppear { if m.selection == nil { m.selection = store.reunions.first?.id }; m.jetonFocus += 1 }
    }

    private var champ: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundStyle(Palette.texte2).frame(width: 18)
            ZStack(alignment: .leading) {
                ChampRecherche(texte: $m.requete, invite: "Rechercher dans les réunions", taille: 16, jetonFocus: m.jetonFocus, surCommande: m.commande)
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
    }

    private func vide(_ titre: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titre).font(Polices.texte(18)).foregroundStyle(Palette.texte2)
            Text(detail).font(Polices.commande(14)).foregroundStyle(Palette.texte3).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, DicteesFenetreVue.margeH + 16)
        .padding(.top, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct LigneReunion: View {
    let r: Reunion
    var choisie: Bool
    var ouvrir: () -> Void
    var surSurvol: () -> Void
    @State private var survol = false

    private static let formatHeure: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.dateFormat = "HH:mm"; return f
    }()

    var body: some View {
        let actif = choisie || survol
        HStack(spacing: 16) {
            Text(Self.formatHeure.string(from: r.debut)).font(Polices.commande(14).monospacedDigit()).foregroundStyle(Palette.texte2).frame(width: 56, alignment: .leading)
            Text(r.titreAffiche).font(Polices.texte(18)).foregroundStyle(actif ? Palette.texte : Palette.texte2)
                .lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
            if r.etat == .sansNote { Text("sans note").font(Polices.commande(12)).foregroundStyle(Palette.texte3) }
            Text(FormatReunion.duree(r.duree)).font(Polices.commande(13)).foregroundStyle(Palette.texte2).lineLimit(1).frame(minWidth: 64, alignment: .trailing)
            Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(Palette.texte3).opacity(actif ? 1 : 0)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(RoundedRectangle(cornerRadius: 10).fill(actif ? Palette.selection : .clear))
        .contentShape(Rectangle())
        .onHover { survol = $0; if $0 { surSurvol() } }
        .onTapGesture(perform: ouvrir)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(Self.formatHeure.string(from: r.debut)), \(r.titreAffiche), \(FormatReunion.duree(r.duree))")
        .accessibilityAddTraits(choisie ? [.isSelected, .isButton] : .isButton)
    }
}

// MARK: la note, version A « Le carnet »

/// Une page qui se lit de haut en bas : titre modifiable, date et participants, « Ce qui a été dit », « Ce qui a été décidé »,
/// « Ce qu'il reste à faire » (cases à cocher), puis la transcription repliée. Une section vide n'est pas montrée.
struct NoteReunionVue: View {
    @ObservedObject var m: ReunionsModele
    var r: Reunion
    @State private var titre = ""
    @FocusState private var titreFocus: Bool
    static let colonneEtiquette: CGFloat = 150
    static let largeurPage: CGFloat = 720
    /// Sous cette largeur, les étiquettes passent au-dessus de leur contenu (petite fenêtre).
    static let largeurCompacte: CGFloat = 860
    @State private var largeur: CGFloat = 1000
    private var compacte: Bool { largeur < Self.largeurCompacte }
    private var retrait: CGFloat { compacte ? 0 : Self.colonneEtiquette }

    var body: some View {
        VStack(spacing: 0) {
            barre.padding(.horizontal, DicteesFenetreVue.margeH).frame(height: 52)
            ScrollView(.vertical, showsIndicators: false) {
                page
                    .frame(maxWidth: Self.largeurPage + Self.colonneEtiquette, alignment: .leading)
                    .padding(.horizontal, DicteesFenetreVue.margeH)
                    .padding(.top, 4).padding(.bottom, 40)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack { MentionLocale(); Spacer() }
                .padding(.horizontal, DicteesFenetreVue.margeH)
                .frame(height: 48)
                .overlay(alignment: .top) { Rectangle().fill(Palette.filet).frame(height: 1) }
        }
        .background(GeometryReader { g in Color.clear.onAppear { largeur = g.size.width }.onChange(of: g.size.width) { _, w in largeur = w } })
        .onAppear { titre = r.titre }
        .onChange(of: r.id) { _, _ in titre = r.titre }
        .onChange(of: r.titre) { _, nouveau in if !titreFocus { titre = nouveau } }
        .background(Button("") { m.fermerLaNote() }.keyboardShortcut(.escape, modifiers: []).opacity(0).frame(width: 0, height: 0))
    }

    // MARK: barre d'actions

    private var barre: some View {
        HStack(spacing: 4) {
            Button { m.fermerLaNote() } label: {
                HStack(spacing: 4) { Image(systemName: "chevron.left").font(.system(size: 12, weight: .medium)); Text("Réunions").font(Polices.commande(14)) }
                    .foregroundStyle(Palette.texte2).padding(.horizontal, 8).frame(height: 32).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Retour aux réunions")
            Spacer()
            if m.suppressionEnAttente {
                Text("Effacer cette réunion ?").font(Polices.commande(14)).foregroundStyle(Palette.texte2)
                BoutonCadre("Effacer", hauteur: 32) { m.supprimer(r.id) }
                BoutonCadre("Garder", hauteur: 32) { m.suppressionEnAttente = false }
            } else {
                BoutonBarre(titre: m.copiee ? "Copié" : "Copier") { m.copier(r) }
                MenuExporter(m: m, r: r)
                BoutonBarre(titre: "Effacer", discret: true) { m.suppressionEnAttente = true }
            }
        }
    }

    // MARK: page

    private var page: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField(r.titreAffiche, text: $titre, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Polices.texte(30))
                .foregroundStyle(Palette.texte)
                .tint(Palette.accent)
                .focused($titreFocus)
                .onSubmit { m.titre(r.id, devient: titre); titreFocus = false }
                .onChange(of: titreFocus) { _, f in if !f { m.titre(r.id, devient: titre) } }
                .padding(.leading, retrait)
                .accessibilityLabel("Titre de la réunion")
            meta.padding(.leading, retrait).padding(.top, 8)

            if let a = etat { a.padding(.leading, retrait).padding(.top, 20) }

            if !r.dit.isEmpty {
                section("Ce qui a été dit") {
                    VStack(alignment: .leading, spacing: 10) { ForEach(Array(r.dit.enumerated()), id: \.offset) { _, t in paragraphe(t) } }
                }
            }
            if !r.decisions.isEmpty {
                section("Ce qui a été décidé") {
                    VStack(alignment: .leading, spacing: 10) { ForEach(Array(r.decisions.enumerated()), id: \.offset) { _, t in paragraphe(t) } }
                }
            }
            if !r.actions.isEmpty {
                section("Ce qu\u{2019}il reste à faire") {
                    VStack(alignment: .leading, spacing: 4) { ForEach(r.actions) { a in ligneAction(a) } }
                }
            }
            if !r.avertissements.isEmpty {
                section("À savoir") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(r.avertissements.enumerated()), id: \.offset) { _, t in
                            Text(t).font(Polices.commande(13)).foregroundStyle(Palette.texte3).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            if !r.segments.isEmpty {
                section("Transcription") { transcription }
            }
        }
    }

    private var meta: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(FormatReunion.jourHeure(r.debut)) \u{00B7} \(FormatReunion.duree(r.duree))").foregroundStyle(Palette.texte3)
            if !r.participants.isEmpty { Text(r.participants.joined(separator: ", ")).foregroundStyle(Palette.texte2) }
        }
        .font(Polices.commande(13))
        .lineSpacing(3)
    }

    /// L'état de la note quand elle n'est pas (encore) écrite.
    private var etat: AnyView? {
        switch r.etat {
        case .prete: return nil
        case .sansNote:
            return AnyView(HStack(spacing: 12) {
                Text("La note n\u{2019}a pas été écrite.").font(Polices.commande(14)).foregroundStyle(Palette.texte2)
                if !r.segments.isEmpty { BoutonCadre("Refaire la note", hauteur: 32) { m.surRefaireLaNote(r.id) } }
            })
        default:
            return AnyView(Text("La note est en préparation\u{2026}").font(Polices.commande(14)).foregroundStyle(Palette.texte2))
        }
    }

    private func section<Contenu: View>(_ titre: String, @ViewBuilder _ contenu: () -> Contenu) -> some View {
        let etiquette = Text(titre).font(Polices.commande(13)).foregroundStyle(Palette.texte3).lineLimit(2).accessibilityAddTraits(.isHeader)
        return Group {
            if compacte {
                VStack(alignment: .leading, spacing: 8) {
                    etiquette
                    contenu().frame(maxWidth: Self.largeurPage, alignment: .leading)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    etiquette.frame(width: Self.colonneEtiquette - 16, alignment: .leading).padding(.trailing, 16)
                    contenu().frame(maxWidth: Self.largeurPage, alignment: .leading)
                }
            }
        }
        .padding(.top, 28)
    }

    private func paragraphe(_ t: String) -> some View {
        Text(t).font(Polices.texte(18)).foregroundStyle(Palette.texte).lineSpacing(5).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
    }

    private func ligneAction(_ a: ActionReunion) -> some View {
        Button { m.cocher(r.id, action: a.id) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5).strokeBorder(a.fait ? Palette.texte : Palette.texte3, lineWidth: 1.5)
                    if a.fait {
                        RoundedRectangle(cornerRadius: 5).fill(Palette.texte)
                        Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.surface)
                    }
                }
                .frame(width: 16, height: 16)
                .alignmentGuide(.firstTextBaseline) { d in d[.bottom] - 2 }
                Text(libelle(a)).font(Polices.texte(18)).lineSpacing(5).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(a.qui.map { $0 + " : " } ?? "")\(a.quoi)\(a.quand.map { ", " + $0 } ?? "")")
        .accessibilityValue(a.fait ? "fait" : "à faire")
        .accessibilityAddTraits(.isToggle)
    }

    /// « Moi  envoyer la proposition, mercredi soir » : le prénom en clair, le reste en gris (barré de gris quand c'est fait).
    private func libelle(_ a: ActionReunion) -> AttributedString {
        var s = AttributedString()
        if let q = a.qui, !q.isEmpty {
            var x = AttributedString(q + " "); x.foregroundColor = a.fait ? Palette.texte3 : Palette.texte; s.append(x)
        }
        var quoi = AttributedString(a.quoi); quoi.foregroundColor = a.fait ? Palette.texte3 : Palette.texte2; s.append(quoi)
        if let q = a.quand, !q.isEmpty { var x = AttributedString(", " + q); x.foregroundColor = Palette.texte3; s.append(x) }
        return s
    }

    // MARK: transcription repliée

    private var transcription: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(.easeOut(duration: 0.15)) { m.transcriptionDepliee.toggle() } } label: {
                HStack(spacing: 10) {
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .medium)).rotationEffect(.degrees(m.transcriptionDepliee ? 90 : 0)).foregroundStyle(Palette.texte3)
                    Text(m.transcriptionDepliee ? "Replier" : "Afficher").font(Polices.commande(14)).foregroundStyle(Palette.texte2)
                    Text("\(FormatReunion.duree(r.duree)), \(r.voix) voix").font(Polices.commande(14)).foregroundStyle(Palette.texte3)
                }
                .frame(height: 28).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(m.transcriptionDepliee ? "Replier la transcription" : "Afficher la transcription")
            if m.transcriptionDepliee {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(r.segments) { s in
                        HStack(alignment: .top, spacing: 12) {
                            Text(FormatReunion.horloge(s.debut)).font(Polices.commande(12).monospacedDigit()).foregroundStyle(Palette.texte3).frame(width: 48, alignment: .leading).padding(.top, 2)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(s.locuteur.libelle).font(Polices.commande(12)).foregroundStyle(s.locuteur == .moi ? Palette.texte2 : Palette.texte3)
                                Text(s.texte).font(Polices.texte(16)).foregroundStyle(Palette.texte2).lineSpacing(3).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                            }
                        }
                        .padding(.vertical, 6)
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.top, 8)
            }
        }
    }
}

/// Un bouton de la barre d'actions : texte seul, fond discret au survol.
struct BoutonBarre: View {
    var titre: String
    var discret = false
    var action: () -> Void
    @State private var survol = false
    var body: some View {
        Button(action: action) {
            Text(titre).font(Polices.commande(14))
                .foregroundStyle(discret && !survol ? Palette.texte3 : (survol ? Palette.texte : Palette.texte2))
                .padding(.horizontal, 10).frame(height: 32)
                .background(RoundedRectangle(cornerRadius: 6).fill(survol ? Palette.selection : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { survol = $0 }
        .accessibilityLabel(titre)
    }
}

/// « Exporter ⌄ » : fichier Markdown, copie pour Notion (qui convertit le Markdown collé), Airtable plus tard.
struct MenuExporter: View {
    @ObservedObject var m: ReunionsModele
    var r: Reunion
    @State private var survol = false
    var body: some View {
        Button(action: ouvrir) {
            HStack(spacing: 6) {
                Text(m.notionCopie ? "Copié pour Notion" : "Exporter").font(Polices.commande(14))
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(survol ? Palette.texte : Palette.texte2)
            .padding(.horizontal, 10).frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 6).fill(survol ? Palette.selection : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { survol = $0 }
        .accessibilityLabel("Exporter")
    }

    private func ouvrir() {
        let menu = NSMenu()
        func item(_ titre: String, _ detail: String?, actif: Bool = true, _ action: @escaping () -> Void) {
            let a = ActionMenu(action)
            let it = NSMenuItem(title: titre + (detail.map { "   \($0)" } ?? ""), action: actif ? #selector(ActionMenu.lancer) : nil, keyEquivalent: "")
            it.target = a; it.representedObject = a; it.isEnabled = actif
            menu.addItem(it)
        }
        item("Fichier Markdown…", ".md") { m.exporterMarkdown(r) }
        item("Copier pour Notion", "à coller dans une page") { m.copierPourNotion(r) }
        item("Airtable", "plus tard", actif: false) {}
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}
