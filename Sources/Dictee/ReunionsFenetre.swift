import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers
import DicteeCore

enum FiltreReunions { case toutes, avecActions }

/// L'état de l'onglet Réunions : la liste, la note ouverte, la recherche, les actions (copier, exporter, effacer, cocher).
@MainActor
final class ReunionsModele: ObservableObject {
    @Published var ouverte: UUID?
    @Published var requete = "" { didSet { if requete != oldValue { selection = affichees.first?.id } } }
    @Published var filtre: FiltreReunions = .toutes { didSet { if filtre != oldValue { selection = affichees.first?.id } } }
    @Published var selection: UUID?
    /// Le point de « Dit » déplié dans la note (un seul à la fois), et celui dont on écoute la phrase.
    @Published var pointOuvert: Int?
    @Published var ecoute: Int?
    private var lecteur: AVAudioPlayer?
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
        let trouvees = store.reunions.filter { ListeReunions.correspond($0, requete: requete) }
        return filtre == .avecActions ? ListeReunions.avecActions(trouvees) : trouvees
    }

    var nombreAvecActions: Int { ListeReunions.avecActions(store.reunions).count }
    var totalActions: Int { ListeReunions.totalActions(store.reunions) }

    var reunionOuverte: Reunion? { ouverte.flatMap { store.reunion(id: $0) } }

    func reinitialiser() { ouverte = nil; requete = ""; filtre = .toutes; selection = store.reunions.first?.id; jetonFocus += 1 }

    func ouvrir(_ id: UUID) {
        arreterEcoute()
        ouverte = id; selection = id; transcriptionDepliee = false; suppressionEnAttente = false; copiee = false; notionCopie = false; pointOuvert = nil
    }
    func fermerLaNote() { arreterEcoute(); ouverte = nil; suppressionEnAttente = false; pointOuvert = nil }

    func basculerPoint(_ i: Int) {
        arreterEcoute()
        pointOuvert = pointOuvert == i ? nil : i
    }

    // MARK: écouter une phrase (seulement si le son de la réunion a été gardé)

    func sonDisponible(_ r: Reunion, _ c: CitationReunion) -> Bool {
        r.sonGarde && FileManager.default.fileExists(atPath: store.fichierSon(r, c.locuteur).path)
    }

    func ecouter(_ r: Reunion, point: Int) {
        if ecoute == point { arreterEcoute(); return }
        arreterEcoute()
        guard let c = r.citation(point: point), sonDisponible(r, c), let p = try? AVAudioPlayer(contentsOf: store.fichierSon(r, c.locuteur)) else {
            Log.ecrire("réunions : son de la phrase illisible"); return
        }
        p.currentTime = c.debut
        guard p.play() else { return }
        lecteur = p; ecoute = point
        let duree = max(2, c.fin - c.debut + 1)
        DispatchQueue.main.asyncAfter(deadline: .now() + duree) { [weak self] in
            guard let self, self.lecteur === p else { return }
            self.arreterEcoute()
        }
    }

    func arreterEcoute() { lecteur?.stop(); lecteur = nil; ecoute = nil }

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
                NoteReunionVue(m: m, r: r.echeancesCalculees())
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
    /// Fenêtre étroite : les lignes perdent la colonne « durée » pour laisser la place au titre.
    @State private var etroite = false

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

            if !store.reunions.isEmpty { filtres.padding(.horizontal, DicteesFenetreVue.margeH).padding(.top, 14).padding(.bottom, 6) }

            if let libelle = controleur.libelleEnCours {
                HStack(spacing: 8) {
                    Circle().fill(Palette.accent).frame(width: 6, height: 6)
                    Text(libelle).font(Polices.commande(14)).foregroundStyle(Palette.texte2)
                    Spacer()
                }
                .padding(.horizontal, DicteesFenetreVue.margeH + 16).padding(.top, 8).padding(.bottom, 4)
                .accessibilityElement(children: .combine)
            }

            if store.reunions.isEmpty {
                vide("Aucune réunion pour l\u{2019}instant.", detail: "Appuie sur \u{2325}\u{2318}N pendant un appel : Verbe écoute ton micro et le son du Mac, puis écrit la note.")
            } else if m.affichees.isEmpty {
                vide("Aucun résultat", detail: m.filtre == .avecActions && m.requete.isEmpty ? "Plus aucune action à faire dans les notes." : "Essaie un autre mot.")
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(m.affichees) { r in
                                LigneReunion(r: r, choisie: m.selection == r.id, etroite: etroite) { m.ouvrir(r.id) } surSurvol: { m.selection = r.id }.id(r.id)
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
        .background(GeometryReader { g in Color.clear.onAppear { etroite = g.size.width < 760 }.onChange(of: g.size.width) { _, w in etroite = w < 760 } })
        .onAppear { if m.selection == nil { m.selection = m.affichees.first?.id }; m.jetonFocus += 1 }
    }

    /// « Toutes 6 » · « Avec des actions à faire 4 » · « 10 actions à faire ».
    private var filtres: some View {
        HStack(spacing: 4) {
            PuceFiltre(titre: "Toutes", nombre: store.reunions.count, actif: m.filtre == .toutes) { m.filtre = .toutes }
            PuceFiltre(titre: "Avec des actions à faire", nombre: m.nombreAvecActions, actif: m.filtre == .avecActions) { m.filtre = .avecActions }
            Spacer(minLength: 8)
            let total = m.totalActions
            (Text("\(total)").fontWeight(.medium).foregroundStyle(Palette.texte) + Text(" action\(total > 1 ? "s" : "") à faire").foregroundStyle(Palette.texte2))
                .font(Polices.commande(14)).lineLimit(1)
                .accessibilityLabel("\(total) action\(total > 1 ? "s" : "") à faire en tout")
        }
        .frame(height: 32)
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

/// Un filtre de la liste : texte, nombre en gris, pastille quand il est actif.
struct PuceFiltre: View {
    var titre: String
    var nombre: Int
    var actif: Bool
    var action: () -> Void
    @State private var survol = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(titre).font(Polices.commande(14, actif ? .medium : .regular))
                Text("\(nombre)").font(Polices.commande(14)).foregroundStyle(Palette.texte3)
            }
            .foregroundStyle(actif || survol ? Palette.texte : Palette.texte2)
            .padding(.horizontal, 12).frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 8).fill(actif ? Palette.relief : (survol ? Palette.selection : .clear)))
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .fixedSize()
        }
        .buttonStyle(.plain)
        .onHover { survol = $0 }
        .accessibilityLabel("\(titre), \(nombre)")
        .accessibilityAddTraits(actif ? .isSelected : [])
    }
}

/// Une réunion sur deux lignes : jour et heure, titre, « En bref » sur une ligne, durée, ce qu'il reste à faire.
struct LigneReunion: View {
    let r: Reunion
    var choisie: Bool
    var etroite = false
    var ouvrir: () -> Void
    var surSurvol: () -> Void
    @State private var survol = false

    private static let formatHeure: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.dateFormat = "HH:mm"; return f
    }()
    private static let formatJour: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.dateFormat = "EEE d MMM"; return f
    }()

    var body: some View {
        let actif = choisie || survol
        let resume = ResumeReunion.de(r)
        HStack(spacing: etroite ? 14 : 20) {
            VStack(alignment: .leading, spacing: 0) {
                Text(Self.formatHeure.string(from: r.debut)).font(Polices.commande(14).monospacedDigit()).foregroundStyle(Palette.texte)
                Text(Self.formatJour.string(from: r.debut)).font(Polices.commande(13)).foregroundStyle(Palette.texte3).lineLimit(1)
            }
            .frame(width: 76, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.titreAffiche).font(Polices.texte(19)).foregroundStyle(Palette.texte).lineLimit(1).truncationMode(.tail)
                Text(deuxiemeLigne(resume)).font(Polices.commande(14)).foregroundStyle(resume.noteEcrite ? Palette.texte2 : Palette.texte3).lineLimit(1).truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !etroite { Text(FormatReunion.duree(r.duree)).font(Polices.commande(13)).foregroundStyle(Palette.texte3).lineLimit(1).frame(width: 56, alignment: .trailing) }
            droite(resume).frame(width: 112, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .frame(height: 68)
        .background(RoundedRectangle(cornerRadius: 10).fill(actif ? Palette.selection : .clear))
        .contentShape(Rectangle())
        .onHover { survol = $0; if $0 { surSurvol() } }
        .onTapGesture(perform: ouvrir)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(Self.formatJour.string(from: r.debut)), \(Self.formatHeure.string(from: r.debut)), \(r.titreAffiche), \(FormatReunion.duree(r.duree)), \(resume.noteEcrite ? "\(resume.aFaire) à faire" : "sans note")")
        .accessibilityAddTraits(choisie ? [.isSelected, .isButton] : .isButton)
    }

    private func deuxiemeLigne(_ resume: ResumeReunion) -> String {
        switch r.etat {
        case .prete: return resume.enBref
        case .sansNote: return "Pas encore de note pour cet enregistrement."
        default: return "Note en préparation\u{2026}"
        }
    }

    @ViewBuilder private func droite(_ resume: ResumeReunion) -> some View {
        if r.etat == .sansNote {
            Text("sans note").font(Polices.commande(14)).foregroundStyle(Palette.texte3).lineLimit(1)
        } else if r.etat != .prete {
            Text("en préparation").font(Polices.commande(14)).foregroundStyle(Palette.texte3).lineLimit(1)
        } else if resume.aFaire > 0 {
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(resume.aFaire) à faire").font(Polices.commande(14, .medium)).foregroundStyle(Palette.texte).lineLimit(1)
                if let iso = resume.premiere, let jour = Echeance.jour(iso, court: true) {
                    Text("\(resume.premiereAvant ? "avant" : "dès") \(jour)").font(Polices.commande(13)).foregroundStyle(Palette.texte3).lineLimit(1)
                }
            }
        } else {
            Text(resume.toutFait ? "tout fait" : "rien à faire").font(Polices.commande(14)).foregroundStyle(Palette.texte3).lineLimit(1)
        }
    }
}

// MARK: la note, version B « D'un coup d'œil »

/// Trois colonnes de largeurs différentes sur une même ligne (Dit, Décidé, À faire), à hauteur commune.
struct TroisColonnes: Layout {
    var poids: [CGFloat] = [1.2, 0.8, 1.35]
    private func largeurs(_ total: CGFloat) -> [CGFloat] {
        let somme = poids.reduce(0, +)
        return poids.map { total * $0 / somme }
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let total = proposal.width ?? 900
        let h = zip(subviews, largeurs(total)).map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }.max() ?? 0
        return CGSize(width: total, height: max(h, proposal.height ?? 0))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (v, w) in zip(subviews, largeurs(bounds.width)) {
            v.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading, proposal: ProposedViewSize(width: w, height: bounds.height))
            x += w
        }
    }
}

/// Une étiquette de date : « mer. 11 · soir » (pleine), « sans date » (cadre), « fait » (texte gris).
struct EtiquetteDate: View {
    enum Style { case pleine, sansDate, fait }
    var texte: String
    var style: Style = .pleine
    var largeur: CGFloat?
    var body: some View {
        Text(texte)
            .font(Polices.commande(13, style == .pleine ? .medium : .regular))
            .foregroundStyle(style == .pleine ? Palette.texte : Palette.texte3)
            .lineLimit(1).minimumScaleFactor(0.85)
            .padding(.horizontal, style == .fait ? 0 : 10)
            .frame(height: 26)
            .frame(width: largeur, alignment: style == .fait ? .leading : .center)
            .background { if style == .pleine { RoundedRectangle(cornerRadius: 6).fill(Palette.relief) } }
            .overlay { if style == .sansDate { RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.contour, lineWidth: 1) } }
            .fixedSize(horizontal: largeur == nil, vertical: true)
    }
}

/// La note : en-tête (titre modifiable, date · durée · participants), « En bref », puis Dit · Décidé · À faire côte à côte, sans
/// cartes ; un point de « Dit » s'ouvre sur la phrase exacte de la transcription. Les anciennes notes (sans « En bref » ni citations)
/// s'affichent de la même façon, sans ces éléments. En fenêtre étroite, les colonnes passent l'une sous l'autre.
struct NoteReunionVue: View {
    @ObservedObject var m: ReunionsModele
    var r: Reunion
    @State private var titre = ""
    @FocusState private var titreFocus: Bool
    /// Sous cette largeur, les trois colonnes passent l'une sous l'autre.
    static let largeurCompacte: CGFloat = 820
    @State private var largeur: CGFloat = 1000
    @State private var hauteur: CGFloat = 600
    private var compacte: Bool { largeur < Self.largeurCompacte }

    var body: some View {
        VStack(spacing: 0) {
            barre.padding(.horizontal, DicteesFenetreVue.margeH).frame(height: 48)
            ScrollView(.vertical, showsIndicators: false) {
                page
                    .padding(.horizontal, DicteesFenetreVue.margeH)
                    .padding(.top, 4).padding(.bottom, 8)
                    .frame(minHeight: hauteur, alignment: .top)
            }
            HStack { MentionLocale(); Spacer() }
                .padding(.horizontal, DicteesFenetreVue.margeH)
                .frame(height: 48)
                .overlay(alignment: .top) { Rectangle().fill(Palette.filet).frame(height: 1) }
        }
        .background(GeometryReader { g in Color.clear.onAppear { largeur = g.size.width }.onChange(of: g.size.width) { _, w in largeur = w } })
        .background(GeometryReader { g in Color.clear.onAppear { hauteur = max(0, g.size.height - 96) }.onChange(of: g.size.height) { _, h in hauteur = max(0, h - 96) } })
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
            entete
            if let a = etat { a.padding(.top, 16) }
            if let b = r.enBref?.trimmingCharacters(in: .whitespacesAndNewlines), !b.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("En bref").font(Polices.commande(13)).foregroundStyle(Palette.texte3)
                    Text(b).font(Polices.texte(21)).lineSpacing(4).foregroundStyle(Palette.texte).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
                .padding(.top, 14)
                .accessibilityElement(children: .combine)
            }
            if r.etat == .prete || !(r.dit.isEmpty && r.decisions.isEmpty && r.actions.isEmpty) { colonnes.padding(.top, 20).frame(maxHeight: .infinity) }
            else { Spacer(minLength: 0) }
            if !r.avertissements.isEmpty { avertissements.padding(.top, 12) }
            if !r.segments.isEmpty { transcription.padding(.top, 12) }
        }
    }

    private var entete: some View {
        let champ = TextField(r.titreAffiche, text: $titre, axis: .vertical)
            .textFieldStyle(.plain)
            .font(Polices.texte(28))
            .foregroundStyle(Palette.texte)
            .tint(Palette.accent)
            .focused($titreFocus)
            .onSubmit { m.titre(r.id, devient: titre); titreFocus = false }
            .onChange(of: titreFocus) { _, f in if !f { m.titre(r.id, devient: titre) } }
            .accessibilityLabel("Titre de la réunion")
        return Group {
            if compacte {
                VStack(alignment: .leading, spacing: 4) { champ; meta }
            } else {
                HStack(alignment: .lastTextBaseline, spacing: 24) { champ.frame(maxWidth: .infinity, alignment: .leading); meta.fixedSize() }
            }
        }
    }

    /// « lun. 9 nov. 2026, 14:02 · 38 min · Moi, Nathalie, Paul »
    private var meta: some View {
        var t = AttributedString("\(FormatReunion.jourHeure(r.debut)) \u{00B7} \(FormatReunion.duree(r.duree))")
        t.foregroundColor = Palette.texte2
        if !r.participants.isEmpty {
            var p = AttributedString(" \u{00B7} " + r.participants.joined(separator: ", ")); p.foregroundColor = Palette.texte
            t.append(p)
        }
        return Text(t).font(Polices.commande(14)).lineLimit(compacte ? 3 : 1).fixedSize(horizontal: false, vertical: true)
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

    // MARK: les trois colonnes

    @ViewBuilder private var colonnes: some View {
        if compacte {
            VStack(alignment: .leading, spacing: 0) {
                colonneDit.padding(.bottom, 20)
                colonneDecide.padding(.vertical, 20).overlay(alignment: .top) { Rectangle().fill(Palette.contour).frame(height: 1) }
                colonneAFaire.padding(.top, 20).overlay(alignment: .top) { Rectangle().fill(Palette.contour).frame(height: 1) }
            }
        } else {
            TroisColonnes {
                colonneDit.padding(.trailing, 24).frame(maxHeight: .infinity, alignment: .topLeading)
                colonneDecide.padding(.horizontal, 24).frame(maxHeight: .infinity, alignment: .topLeading)
                    .overlay(alignment: .leading) { Rectangle().fill(Palette.contour).frame(width: 1) }
                colonneAFaire.padding(.leading, 24).frame(maxHeight: .infinity, alignment: .topLeading)
                    .overlay(alignment: .leading) { Rectangle().fill(Palette.contour).frame(width: 1) }
            }
        }
    }

    private func entete(_ titre: String, _ compte: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(titre).font(Polices.commande(17, .medium)).foregroundStyle(Palette.texte)
            Text(compte).font(Polices.commande(15)).foregroundStyle(Palette.texte3)
        }
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func rien(_ t: String) -> some View { Text(t).font(Polices.texte(17)).foregroundStyle(Palette.texte3).padding(.vertical, 7) }

    // Dit

    private var colonneDit: some View {
        VStack(alignment: .leading, spacing: 0) {
            entete("Dit", "\(r.dit.count)")
            if r.dit.isEmpty { rien("Rien noté.") }
            ForEach(Array(r.dit.enumerated()), id: \.offset) { i, t in point(i, t) }
        }
    }

    @ViewBuilder private func point(_ i: Int, _ t: String) -> some View {
        if let c = r.citation(point: i) {
            let ouvert = m.pointOuvert == i
            VStack(alignment: .leading, spacing: 0) {
                Button { withAnimation(.easeOut(duration: 0.15)) { m.basculerPoint(i) } } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Text(t).font(Polices.texte(17)).lineSpacing(3).foregroundStyle(Palette.texte).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: ouvert ? "chevron.down" : "chevron.right").font(.system(size: 11, weight: .medium))
                            .foregroundStyle(ouvert ? Palette.texte2 : Palette.texte3).frame(width: 16, height: 24)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t)
                .accessibilityValue(ouvert ? "ouvert" : "fermé")
                .accessibilityHint("Montre la phrase de la transcription")
                if ouvert {
                    Text("\u{00AB}\u{202F}\(c.texte)\u{202F}\u{00BB}").font(Polices.texte(16)).lineSpacing(4).foregroundStyle(Palette.texte2)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled).padding(.top, 6)
                    HStack(spacing: 6) {
                        Text(c.locuteur.libelle).fontWeight(.medium).foregroundStyle(Palette.texte)
                        Text("\u{00B7} \(FormatReunion.horloge(c.debut)) dans l\u{2019}appel").foregroundStyle(Palette.texte2)
                        if m.sonDisponible(r, c) {
                            Text("\u{00B7}").foregroundStyle(Palette.texte2)
                            Button { m.ecouter(r, point: i) } label: { Text(m.ecoute == i ? "Arrêter" : "Écouter").foregroundStyle(Palette.texte) }
                                .buttonStyle(.plain).accessibilityLabel(m.ecoute == i ? "Arrêter l\u{2019}écoute" : "Écouter la phrase")
                        }
                    }
                    .font(Polices.commande(13)).padding(.top, 8)
                }
            }
            .padding(.horizontal, ouvert ? 12 : 0).padding(.vertical, ouvert ? 10 : 7)
            .background { if ouvert { RoundedRectangle(cornerRadius: 10).fill(Palette.selection).overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.contour, lineWidth: 1)) } }
            .padding(.horizontal, ouvert ? -12 : 0).padding(.vertical, ouvert ? 4 : 0)
        } else {
            Text(t).font(Polices.texte(17)).lineSpacing(3).foregroundStyle(Palette.texte).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 7)
        }
    }

    // Décidé

    private var colonneDecide: some View {
        VStack(alignment: .leading, spacing: 0) {
            entete("Décidé", "\(r.decisions.count)")
            if r.decisions.isEmpty { rien("Rien de décidé.") }
            ForEach(Array(r.decisions.enumerated()), id: \.offset) { i, t in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.texte).frame(width: 20, height: 24)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(t).font(Polices.texte(17)).lineSpacing(3).foregroundStyle(Palette.texte).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        if let e = r.echeance(decision: i) {
                            let et = Echeance.etiquette(quand: e.quand, date: e.date)
                            EtiquetteDate(texte: et.texte)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 7)
                .accessibilityElement(children: .combine)
            }
        }
    }

    // À faire

    private var colonneAFaire: some View {
        let t = ActionsReunion.triees(r.actions)
        return VStack(alignment: .leading, spacing: 0) {
            entete("À faire", t.faites.isEmpty ? "\(t.aFaire.count)" : "\(t.aFaire.count) \u{00B7} \(t.faites.count) fait")
            if r.actions.isEmpty { rien("Rien à faire.") }
            ForEach(Array(t.aFaire.enumerated()), id: \.element.id) { i, a in ligneAction(a, derniere: i == t.aFaire.count - 1 && t.faites.isEmpty) }
            ForEach(Array(t.faites.enumerated()), id: \.element.id) { i, a in ligneAction(a, derniere: i == t.faites.count - 1) }
        }
    }

    private func ligneAction(_ a: ActionReunion, derniere: Bool) -> some View {
        Button { m.cocher(r.id, action: a.id) } label: {
            HStack(alignment: .top, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5).strokeBorder(a.fait ? Palette.texte : Palette.texte3, lineWidth: 1.5)
                    if a.fait {
                        RoundedRectangle(cornerRadius: 5).fill(Palette.texte)
                        Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.surface)
                    }
                }
                .frame(width: 18, height: 18).padding(.top, 3)
                if a.fait { EtiquetteDate(texte: "fait", style: .fait, largeur: 92).padding(.top, 0) }
                else {
                    let e = Echeance.etiquette(quand: a.quand, date: a.echeance, court: true)
                    EtiquetteDate(texte: e.texte, style: e.sansDate ? .sansDate : .pleine, largeur: 92)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(a.quoi).font(Polices.texte(17)).lineSpacing(3).foregroundStyle(a.fait ? Palette.texte3 : Palette.texte).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    if let q = a.qui, !q.isEmpty { Text(q).font(Polices.commande(13)).foregroundStyle(a.fait ? Palette.texte3 : Palette.texte2) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 7)
            .overlay(alignment: .bottom) { if !derniere { Rectangle().fill(Palette.filet).frame(height: 1) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(a.qui.map { $0 + " : " } ?? "")\(a.quoi), \(Echeance.etiquette(quand: a.quand, date: a.echeance).texte)")
        .accessibilityValue(a.fait ? "fait" : "à faire")
        .accessibilityAddTraits(.isToggle)
    }

    // MARK: à savoir, transcription repliée

    private var avertissements: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(r.avertissements.enumerated()), id: \.offset) { _, t in
                Text(t).font(Polices.commande(13)).foregroundStyle(Palette.texte3).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var transcription: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(.easeOut(duration: 0.15)) { m.transcriptionDepliee.toggle() } } label: {
                HStack(spacing: 12) {
                    Text("Transcription").font(Polices.commande(15, .medium)).foregroundStyle(Palette.texte)
                    Text("\(FormatReunion.duree(r.duree)) \u{00B7} \(r.voix) voix").font(Polices.commande(15)).foregroundStyle(Palette.texte3)
                    Spacer()
                    HStack(spacing: 6) {
                        Text(m.transcriptionDepliee ? "Replier" : "Afficher").font(Polices.commande(15))
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .medium)).rotationEffect(.degrees(m.transcriptionDepliee ? 90 : 0))
                    }
                    .foregroundStyle(Palette.texte2)
                }
                .frame(height: 52).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .overlay(alignment: .top) { Rectangle().fill(Palette.contour).frame(height: 1) }
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
                .padding(.bottom, 12)
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
