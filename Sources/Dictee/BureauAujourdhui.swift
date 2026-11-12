import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers
import DicteeCore

/// La page « Aujourd'hui » : ses tuiles, calculées d'un coup (DicteeCore/Bureau.swift) quand la page s'ouvre et quand une dictée
/// ou une note arrive pendant qu'elle est à l'écran.
@MainActor
final class AujourdhuiModele: ObservableObject {
    @Published private(set) var tableau: TableauAujourdhui
    let store: HistoriqueStore
    let reunions: ReunionStore
    var sources: SourcesAujourdhui
    /// « Maintenant » : fixé dans les rendus PNG.
    var horloge: () -> Date
    /// Vrai tant que la page est à l'écran (onAppear / onDisappear) : page fermée, rien n'est recalculé.
    var affichee = false
    private var abonnements = Set<AnyCancellable>()

    init(store: HistoriqueStore, reunions: ReunionStore, sources: SourcesAujourdhui, horloge: @escaping () -> Date = { Date() }) {
        self.store = store; self.reunions = reunions; self.sources = sources; self.horloge = horloge
        tableau = Aujourdhui.calculer(entrees: [], reunions: [], evenements: [], rappels: [], etagere: [], maintenant: horloge())
        store.$historique.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.recalculerSiAffichee() } }.store(in: &abonnements)
        reunions.$reunions.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.recalculerSiAffichee() } }.store(in: &abonnements)
    }

    func recalculerSiAffichee() { if affichee { recalculer() } }

    func recalculer() {
        tableau = Aujourdhui.calculer(entrees: store.historique.entrees, reunions: reunions.reunions, evenements: sources.rendezVous(),
                                      rappels: sources.rappels(), etagere: sources.etagere(), maintenant: horloge())
    }
}

/// « Aujourd'hui » en tuiles (maquette, étape 7) : les mots dictés en grand avec l'anneau, le temps gagné, la prochaine réunion,
/// la dernière note, l'étagère. Chaque tuile dit où mène son clic (« Dictées › », « Journée › »…).
struct AujourdhuiVue: View {
    @ObservedObject var m: AujourdhuiModele
    @ObservedObject var controleur: ReunionController
    var ouvrir: (SousPageBureau) -> Void
    var ouvrirNote: (UUID) -> Void
    var noter: () -> Void

    var body: some View {
        let t = m.tableau
        VStack(alignment: .leading, spacing: 0) {
            EntetePage(petit: t.date, titre: "Aujourd\u{2019}hui") {
                HStack(spacing: 8) {
                    ForEach(Array(t.puces.enumerated()), id: \.offset) { _, p in
                        PastilleBureau(symbole: "bell.fill", teinte: TonsBureau.orange, texte: p.texte, valeur: p.valeur).frame(maxWidth: 260)
                    }
                }
            }
            GeometryReader { g in
                let e = TonsBureau.ecart
                let colonne = (g.size.width - 3 * e) / 4
                let rang = max(128, (g.size.height - e) / 2)
                HStack(alignment: .top, spacing: e) {
                    TuileMotsVue(t: t.mots) { ouvrir(.dictees) }
                        .frame(width: 2 * colonne + e, height: 2 * rang + e)
                    VStack(spacing: e) {
                        TuileTempsVue(t: t.temps) { ouvrir(.journee) }.frame(height: rang)
                        TuileNoteVue(note: t.note) { if let n = t.note { ouvrirNote(n.id) } else { ouvrirNote(UUID()) } }.frame(height: rang)
                    }
                    .frame(width: colonne)
                    VStack(spacing: e) {
                        TuileRendezVousVue(r: t.rendezVous, enCours: controleur.enregistre, noter: noter).frame(height: rang)
                        TuileEtagereVue(noms: t.etagere) { ouvrir(.bibliotheque) }.frame(height: rang)
                    }
                    .frame(width: colonne)
                }
            }
        }
        .padding(.horizontal, TonsBureau.margeH)
        .padding(.bottom, TonsBureau.margeBas)
        .onAppear { m.affichee = true; m.recalculer() }
        .onDisappear { m.affichee = false }
    }
}

// MARK: - les tuiles

/// « Mots dictés » : l'anneau (la part du record), le grand nombre, puis dictées et apps, moyenne, record.
struct TuileMotsVue: View {
    var t: TuileMots
    var action: () -> Void
    var body: some View {
        TuileBouton(etiquette: "Mots dictés : \(FormatJournee.nombre(t.mots)) aujourd\u{2019}hui. Voir les dictées", action: action) {
            VStack(alignment: .leading, spacing: 0) {
                EnteteTuile(symbole: "quote.opening", titre: "Mots dictés", teinte: TonsBureau.orange, lien: "Dictées")
                ViewThatFits(in: .horizontal) {
                    corps(anneau: 160)
                    corps(anneau: 120)
                }
                .frame(maxHeight: .infinity)
            }
            .padding(.horizontal, 18).padding(.vertical, 16)
        }
    }

    private func corps(anneau: CGFloat) -> some View {
        HStack(spacing: 30) {
            AnneauMots(remplissage: t.remplissage, pourcent: t.pourcent, sous: t.sousAnneau).frame(width: anneau, height: anneau)
            VStack(alignment: .leading, spacing: 0) {
                Text(FormatJournee.nombre(t.mots)).font(.system(size: 46, weight: .bold)).tracking(-1.6).monospacedDigit()
                    .foregroundStyle(TonsBureau.encre).lineLimit(1).minimumScaleFactor(0.6)
                Text(t.mots > 1 ? "mots dictés aujourd\u{2019}hui" : "mot dicté aujourd\u{2019}hui").font(.system(size: 13.5)).foregroundStyle(TonsBureau.encre2)
                VStack(alignment: .leading, spacing: 7) {
                    ligne(fort: FormatJournee.nombre(t.dictees), reste: t.dictees > 1 ? " dictées, dans \(t.apps) app\(t.apps > 1 ? "s" : "")" : " dictée", plein: true)
                    if let moyenne = t.moyenne { ligne(debut: "Moyenne ", fort: FormatJournee.nombre(moyenne), reste: " mots par jour") }
                    if let r = t.record { ligne(debut: "Record ", fort: FormatJournee.nombre(r.mots), reste: ", " + Self.jour(r.jour)) }
                }
                .padding(.top, 14)
            }
            .fixedSize()
        }
    }

    private func ligne(debut: String = "", fort: String, reste: String, plein: Bool = false) -> some View {
        HStack(spacing: 8) {
            Circle().fill(TonsBureau.orange.opacity(plein ? 1 : 0.35)).frame(width: 6, height: 6)
            Text("\(Text(debut).foregroundStyle(TonsBureau.encre2))\(Text(fort).fontWeight(.semibold).foregroundStyle(TonsBureau.encre))\(Text(reste).foregroundStyle(TonsBureau.encre2))")
        }
        .font(.system(size: 13).monospacedDigit())
        .lineLimit(1)
    }

    /// « mardi » cette semaine, sinon « 3 nov. ».
    static func jour(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = Date().timeIntervalSince(d) < 6 * 86_400 ? "EEEE" : "d MMM"
        return f.string(from: d)
    }
}

/// L'anneau orange : la piste pâle, l'arc (bouts ronds), le pourcentage au centre.
struct AnneauMots: View {
    var remplissage: Double
    var pourcent: String?
    var sous: String
    var body: some View {
        GeometryReader { g in
            let epaisseur = g.size.width * 0.1
            ZStack {
                Circle().stroke(TonsBureau.orange.opacity(0.15), lineWidth: epaisseur)
                Circle().trim(from: 0, to: remplissage)
                    .stroke(AngularGradient(colors: [TonsBureau.orange.opacity(0.75), TonsBureau.orange], center: .center, startAngle: .degrees(0), endAngle: .degrees(360 * max(0.01, remplissage))),
                            style: StrokeStyle(lineWidth: epaisseur, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 1) {
                    if let pourcent { Text(pourcent).font(.system(size: 15, weight: .bold).monospacedDigit()).foregroundStyle(TonsBureau.orange) }
                    Text(sous).font(.system(size: 11.5, weight: .medium)).foregroundStyle(TonsBureau.encre3).multilineTextAlignment(.center)
                }
                .padding(epaisseur * 1.5)
            }
            .padding(epaisseur / 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pourcent.map { "\($0) \(sous)" } ?? sous)
    }
}

/// « Temps gagné » : les minutes en grand, puis la semaine en barres (aujourd'hui en vert plein).
struct TuileTempsVue: View {
    var t: TuileTemps
    var action: () -> Void
    var body: some View {
        let c = t.chiffre
        TuileBouton(etiquette: "Temps gagné : \(c.nombre) \(c.unite). Voir la journée", action: action) {
            VStack(alignment: .leading, spacing: 0) {
                EnteteTuile(symbole: "timer", titre: "Temps gagné", teinte: TonsBureau.vert, lien: nil, chevron: true)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(c.nombre).font(.system(size: 30, weight: .bold)).tracking(-1).monospacedDigit()
                    if !c.unite.isEmpty { Text(c.unite).font(.system(size: 15, weight: .semibold)).foregroundStyle(TonsBureau.encre2) }
                }
                .foregroundStyle(TonsBureau.encre).padding(.top, 8)
                Text("sur le clavier, aujourd\u{2019}hui").font(.system(size: 12.5)).foregroundStyle(TonsBureau.encre2).lineLimit(1)
                Spacer(minLength: 6)
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(Array(t.barres.enumerated()), id: \.offset) { i, h in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(i == t.barres.count - 1 ? TonsBureau.vert : TonsBureau.vert.opacity(0.2))
                            .frame(height: max(3, 26 * h))
                    }
                }
                .frame(height: 26, alignment: .bottom)
            }
            .padding(.horizontal, 18).padding(.vertical, 15)
        }
    }
}

/// « Prochaine réunion » : le prochain rendez-vous du calendrier et « Noter ». Sans rendez-vous, « Noter » reste là (un appel imprévu).
/// La tuile n'est pas un bouton : seul « Noter » (ou « Arrêter ») se clique.
struct TuileRendezVousVue: View {
    var r: TuileRendezVous?
    var enCours: Bool
    var noter: () -> Void
    var body: some View {
        CarteBureau {
            VStack(alignment: .leading, spacing: 0) {
                EnteteTuile(symbole: "video", titre: enCours ? "Réunion en cours" : "Prochaine réunion", titreCourt: enCours ? "En cours" : "Réunion", teinte: TonsBureau.bleu, lien: nil)
                if let r {
                    Text(r.heure).font(.system(size: 30, weight: .bold)).tracking(-1).monospacedDigit().foregroundStyle(TonsBureau.encre).padding(.top, 8)
                    Text(r.titre).font(.system(size: 13, weight: .semibold)).foregroundStyle(TonsBureau.encre).lineLimit(1)
                    Text(r.quand).font(.system(size: 12.5)).foregroundStyle(TonsBureau.encre2).lineLimit(1)
                } else {
                    Text("Rien au calendrier").font(.system(size: 15, weight: .semibold)).foregroundStyle(TonsBureau.encre).padding(.top, 10)
                    Text("Un appel imprévu\u{202F}? Verbe le note aussi.").font(.system(size: 12.5)).foregroundStyle(TonsBureau.encre2)
                        .fixedSize(horizontal: false, vertical: true).padding(.top, 2)
                }
                Spacer(minLength: 6)
                HStack {
                    Spacer()
                    BoutonCapsule(titre: enCours ? "Arrêter" : "Noter", symbole: enCours ? "stop.fill" : "circle.fill", action: noter)
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 15)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// « Dernière note » : la phrase « En bref » en police à empattements, et d'où elle vient.
struct TuileNoteVue: View {
    var note: TuileNote?
    var action: () -> Void
    var body: some View {
        TuileBouton(etiquette: note.map { "Dernière note : \($0.extrait). Ouvrir" } ?? "Réunions", action: action) {
            VStack(alignment: .leading, spacing: 0) {
                EnteteTuile(symbole: "doc.text", titre: "Dernière note", teinte: TonsBureau.jaune, lien: nil, chevron: true)
                if let note {
                    Text(note.extrait).font(.system(size: 15.5, design: .serif)).lineSpacing(3).foregroundStyle(TonsBureau.encre)
                        .lineLimit(3).padding(.top, 8)
                    Spacer(minLength: 4)
                    Text(note.meta).font(.system(size: 12)).foregroundStyle(TonsBureau.encre3).lineLimit(1)
                } else {
                    Text("Aucune note pour l\u{2019}instant.").font(.system(size: 15, design: .serif)).foregroundStyle(TonsBureau.encre2).padding(.top, 8)
                    Spacer(minLength: 4)
                    Text("Elle arrive ici après un appel noté.").font(.system(size: 12)).foregroundStyle(TonsBureau.encre3)
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 15)
        }
    }
}

/// « Sur l'étagère » : les icônes des fichiers en éventail, leurs noms dessous.
struct TuileEtagereVue: View {
    var noms: [String]
    var action: () -> Void
    var body: some View {
        TuileBouton(etiquette: noms.isEmpty ? "Étagère vide. Ouvrir la bibliothèque" : "Sur l\u{2019}étagère : \(noms.joined(separator: ", ")). Ouvrir la bibliothèque", action: action) {
            VStack(alignment: .leading, spacing: 0) {
                EnteteTuile(symbole: "tray", titre: "Sur l\u{2019}étagère", teinte: TonsBureau.sarcelle, lien: nil, chevron: true)
                if noms.isEmpty {
                    Text("Glisse un fichier sur l\u{2019}encoche\u{202F}: il t\u{2019}attend ici.").font(.system(size: 12.5)).foregroundStyle(TonsBureau.encre2)
                        .fixedSize(horizontal: false, vertical: true).padding(.top, 10)
                    Spacer(minLength: 0)
                } else {
                    ZStack(alignment: .bottomLeading) {
                        ForEach(Array(noms.prefix(3).enumerated().reversed()), id: \.offset) { i, nom in
                            Image(nsImage: Self.icone(nom)).resizable().interpolation(.high).frame(width: 52, height: 52)
                                .shadow(color: .black.opacity(0.15), radius: 3, y: 2)
                                .rotationEffect(.degrees([-8, 2, 9][i]))
                                .offset(x: CGFloat(i) * 40, y: 0)
                                .zIndex(i == 1 ? 2 : 1)
                        }
                    }
                    .frame(height: 58, alignment: .bottomLeading).padding(.top, 10).padding(.leading, 2)
                    Spacer(minLength: 4)
                    Text(noms.map { ($0 as NSString).deletingPathExtension }.joined(separator: ", ")).font(.system(size: 12)).foregroundStyle(TonsBureau.encre3)
                        .lineLimit(1).truncationMode(.tail)
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 15)
        }
    }

    /// L'icône du type de fichier (d'après son extension : rien n'est lu sur le disque).
    static func icone(_ nom: String) -> NSImage {
        let ext = (nom as NSString).pathExtension
        return NSWorkspace.shared.icon(for: UTType(filenameExtension: ext) ?? .data)
    }
}
