import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers
import DicteeCore

/// Une réponse à « Demander » : en attente, prête (avec le passage ou la réunion qui la porte), ou impossible pour l'instant.
enum EtatReponse: Equatable {
    case attente(question: String)
    case prete(question: String, QuestionReunion.Reponse)
    case echec(question: String, String)
    var question: String {
        switch self { case .attente(let q), .prete(let q, _), .echec(let q, _): return q }
    }
}

/// L'état de l'onglet Réunions (maquette ilot-reunion.html, étapes 11 et 12) : la colonne de gauche (recherche, « Demander à mes
/// réunions », liste par jour) et la note ouverte (réécouter un moment, « Demander », copier, exporter, renommer un orateur).
@MainActor
final class ReunionsModele: ObservableObject {
    /// La réunion montrée à droite.
    @Published var ouverte: UUID?
    @Published var requete = "" { didSet { if requete != oldValue, let id = affichees.first?.id, !affichees.contains(where: { $0.id == ouverte }) { ouvrir(id) } } }
    /// La page « Demander à mes réunions » à la place de la note.
    @Published var demandeToutes = false
    /// Le passage dont la bulle joue (ou est en pause), rang dans `segments` ; la vitesse (×1, ×1,5, ×2) ; les ondes des bulles
    /// (par passage) ; « Enregistré » sur la bulle d'un extrait téléchargé ; l'export de toute la réunion (0 à 1, nil : aucun).
    @Published private(set) var ecoute: Int?
    @Published private(set) var enPause = false
    @Published private(set) var vitesse: Double = 1
    @Published private(set) var ondes: [UUID: [Float]] = [:]
    @Published private(set) var extraitEnregistre: UUID?
    @Published private(set) var exportAudio: Double?
    /// Le passage montré par une réponse (« Voir à 14:16 ») quand le son n'est pas gardé.
    @Published var repere: Int?
    /// Le défilement vers un passage (un jeton qui change à chaque demande).
    @Published var allerA: (index: Int, jeton: Int)?
    @Published var question = ""
    @Published var questionToutes = ""
    @Published var reponse: EtatReponse?
    @Published var reponseToutes: EtatReponse?
    /// Les réunions envoyées avec « Demander à mes réunions » (la réponse renvoie à l'une d'elles).
    private(set) var envoyeesToutes: [Reunion] = []
    @Published var suppressionEnAttente = false
    @Published var copiee = false
    @Published var exportee = false
    @Published var jetonFocus = 0
    @Published var jetonQuestion = 0
    private var lecteur: LecteurSon?
    private var lecteurReunion: UUID?
    private var lecteurPiste: Locuteur?
    private var extrait: ExtraitReunion?
    private var progressionSimulee: Double?
    private var ondesChargees: Set<UUID> = []
    /// Le lecteur d'un fichier son (AVAudioPlayer ; un lecteur muet dans l'essai).
    var ouvrirLecteur: (URL) -> LecteurSon? = { AVAudioPlayer.pourBulle($0) }
    private var finEcoute: DispatchWorkItem?
    private var tache: Task<Void, Never>?
    let store: ReunionStore
    /// Réécrit la note d'une réunion sans note (branché par l'app).
    var surRefaireLaNote: (UUID) -> Void = { _ in }
    /// Lance (ou arrête) une réunion.
    var surNoter: () -> Void = {}
    /// « Demander » (réseau remplaçable dans les essais et les rendus).
    var demander: (String, Reunion) async throws -> QuestionReunion.Reponse = { try await GenerationNote().demander($0, reunion: $1) }
    var demanderToutes: (String, [Reunion]) async throws -> (reponse: QuestionReunion.Reponse, envoyees: [Reunion]) = { try await GenerationNote().demander($0, reunions: $1) }
    /// Le jour d'aujourd'hui (« Aujourd'hui », « Hier » dans la colonne ; remplacé dans les rendus).
    var aujourdhui: () -> Date = { Date() }

    init(store: ReunionStore? = nil) { self.store = store ?? ReunionStore.shared }

    var affichees: [Reunion] { store.reunions.filter { ListeReunions.correspond($0, requete: requete) } }
    var reunionOuverte: Reunion? { ouverte.flatMap { store.reunion(id: $0) } }

    /// À l'arrivée sur l'onglet : la recherche vide, la note ouverte gardée (en fenêtre large, la première est ouverte si aucune ne l'est).
    func reinitialiser() {
        requete = ""; demandeToutes = false
        if reunionOuverte == nil { ouverte = nil }
        jetonFocus += 1
    }

    func ouvrir(_ id: UUID) {
        guard id != ouverte || demandeToutes else { return }
        arreterEcoute(); tache?.cancel()
        ouverte = id; demandeToutes = false; repere = nil; allerA = nil
        question = ""; reponse = nil; suppressionEnAttente = false; copiee = false; exportee = false
    }
    func fermerLaNote() { arreterEcoute(); ouverte = nil; suppressionEnAttente = false }

    func ouvrirDemandeToutes() {
        arreterEcoute()
        demandeToutes = true
        jetonQuestion += 1
    }

    func deplacer(_ delta: Int) {
        let liste = affichees
        guard !liste.isEmpty else { return }
        let courant = liste.firstIndex { $0.id == ouverte } ?? 0
        ouvrir(liste[Selection.deplacer(courant, de: delta, sur: liste.count)].id)
    }

    func commande(_ c: CommandeChamp) -> Bool {
        switch c {
        case .haut: deplacer(-1)
        case .bas: deplacer(1)
        case .entree: if let id = affichees.first?.id, !affichees.contains(where: { $0.id == ouverte }) { ouvrir(id) }
        case .echap: if !requete.isEmpty { requete = "" }
        case .focus: jetonFocus += 1
        default: break
        }
        return true
    }

    // MARK: les bulles audio (le son n'existe que si « Garder le son des réunions » est actif, ou le temps de la note)

    func sonDisponible(_ r: Reunion) -> Bool { store.sonPresent(r, .moi) || store.sonPresent(r, .eux) }
    func sonDisponible(_ r: Reunion, _ s: SegmentReunion) -> Bool { store.sonPresent(r, s.locuteur) }

    /// Un clic sur une ligne ou sur ▶︎ : le passage se joue ; sur le passage en cours : pause, puis reprise.
    func ecouter(_ r: Reunion, passage i: Int) {
        if ecoute == i, lecteur != nil { basculerPause(); return }
        jouer(r, passage: i)
    }

    /// Joue l'extrait du passage `i` (sa piste, ses bornes), depuis `fraction` de la bulle (un clic dans l'onde). Le son absent :
    /// rien ne joue, la ligne est montrée.
    func jouer(_ r: Reunion, passage i: Int, fraction: Double = 0) {
        guard r.segments.indices.contains(i) else { return }
        let s = r.segments[i]
        let url = store.fichierSon(r, s.locuteur)
        guard sonDisponible(r, s), let e = ExtraitsReunion.extrait(r, passage: i, dureeSon: LectureWAV.duree(url)) else { arreterEcoute(); repere = i; return }
        // la même piste : le même lecteur (aucun fichier rouvert d'un passage à l'autre)
        let p: LecteurSon
        if let l = lecteur, lecteurReunion == r.id, lecteurPiste == s.locuteur { p = l; p.pause() }
        else {
            lecteur?.stop()
            guard let n = ouvrirLecteur(url) else { arreterEcoute(); repere = i; return }
            p = n
        }
        p.rate = Float(vitesse)
        p.currentTime = e.position(fraction)
        guard p.play() else { arreterEcoute(); return }
        lecteur = p; lecteurReunion = r.id; lecteurPiste = s.locuteur
        extrait = e; ecoute = i; enPause = false; repere = nil
        programmerFin()
    }

    func basculerPause() {
        guard let p = lecteur, ecoute != nil else { return }
        if enPause { p.rate = Float(vitesse); if p.play() { enPause = false; programmerFin() } }
        else { p.pause(); enPause = true; finEcoute?.cancel(); finEcoute = nil }
    }

    /// Un clic dans l'onde : on se place à cet endroit (la lecture part si le passage ne jouait pas).
    func placer(_ r: Reunion, passage i: Int, fraction: Double) {
        guard ecoute == i, let p = lecteur, let e = extrait else { jouer(r, passage: i, fraction: fraction); return }
        p.currentTime = e.position(fraction)
        if enPause { basculerPause() } else { programmerFin() }
    }

    /// ×1 → ×1,5 → ×2 : la vitesse est gardée pour les passages suivants.
    func changerVitesse() {
        vitesse = ExtraitsReunion.vitesseSuivante(vitesse)
        lecteur?.rate = Float(vitesse)
        if !enPause { programmerFin() }
    }

    /// La part jouée de la bulle `i` (0 à 1).
    func progression(_ i: Int) -> Double {
        guard ecoute == i else { return 0 }
        if let x = progressionSimulee { return x }
        guard let p = lecteur, let e = extrait else { return 0 }
        return e.fraction(p.currentTime)
    }

    /// La fin du passage : un seul réveil, calculé sur le temps restant et la vitesse (aucune minuterie qui tourne pendant la lecture).
    private func programmerFin() {
        finEcoute?.cancel()
        guard let p = lecteur, let e = extrait else { return }
        let reste = max(0.03, (e.fin - p.currentTime) / max(0.5, Double(p.rate)))
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.lecteur === p, !self.enPause else { return }
            // le lecteur a pris du retard (disque, réveil) : on attend la vraie fin
            if p.isPlaying, p.currentTime < e.fin - 0.05 { self.programmerFin(); return }
            self.passageFini()
        }
        finEcoute = item
        DispatchQueue.main.asyncAfter(deadline: .now() + reste, execute: item)
    }

    /// Le passage est fini : on enchaîne sur le suivant dont le son est là, comme les vocaux ; sinon on s'arrête.
    private func passageFini() {
        guard let i = ecoute, let id = lecteurReunion, let r = store.reunion(id: id),
              let n = ExtraitsReunion.suivant(apres: i, dans: r, disponible: { self.store.sonPresent(r, $0) }) else { arreterEcoute(); return }
        jouer(r, passage: n)
    }

    /// Pour les rendus : une bulle en cours de lecture, à `fraction` (aucun son joué).
    func simulerEcoute(_ i: Int, fraction: Double) { ecoute = i; enPause = false; progressionSimulee = fraction }

    func arreterEcoute() {
        finEcoute?.cancel(); finEcoute = nil
        lecteur?.stop(); lecteur = nil; lecteurReunion = nil; lecteurPiste = nil
        extrait = nil; ecoute = nil; enPause = false; progressionSimulee = nil
    }

    /// La réponse renvoie à un passage : on y va, et on le rejoue si le son est là.
    func allerAuPassage(_ r: Reunion, _ i: Int) {
        allerA = (i, (allerA?.jeton ?? 0) + 1)
        if r.segments.indices.contains(i), sonDisponible(r, r.segments[i]) { if ecoute != i { jouer(r, passage: i) } }
        else { repere = i }
    }

    /// Les ondes des bulles d'une réunion, calculées une fois hors du fil principal (le vrai niveau du son de chaque passage).
    func chargerOndes(_ r: Reunion) {
        guard sonDisponible(r), !ondesChargees.contains(r.id) else { return }
        ondesChargees.insert(r.id)
        let fichiers = [Locuteur.moi: store.fichierSon(r, .moi), .eux: store.fichierSon(r, .eux)]
        Task.detached(priority: .utility) { [weak self] in
            let o = Self.ondes(r, fichiers: fichiers)
            await MainActor.run { self?.ondes.merge(o) { $1 } }
        }
    }

    /// Pour les rendus : les ondes tout de suite.
    func chargerOndesMaintenant(_ r: Reunion) {
        ondesChargees.insert(r.id)
        ondes.merge(Self.ondes(r, fichiers: [.moi: store.fichierSon(r, .moi), .eux: store.fichierSon(r, .eux)])) { $1 }
    }

    nonisolated static func ondes(_ r: Reunion, fichiers: [Locuteur: URL]) -> [UUID: [Float]] {
        var sortie: [UUID: [Float]] = [:]
        var durees: [Locuteur: Double] = [:]
        for (l, u) in fichiers where FileManager.default.fileExists(atPath: u.path) { durees[l] = LectureWAV.duree(u) }
        for i in r.segments.indices {
            let s = r.segments[i]
            guard let u = fichiers[s.locuteur], let d = durees[s.locuteur], let e = ExtraitsReunion.extrait(r, passage: i, dureeSon: d),
                  let son = LectureWAV.echantillons(u, de: e.debut, a: e.fin) else { continue }
            sortie[s.id] = ExtraitsReunion.onde(son)
        }
        return sortie
    }

    // MARK: télécharger, glisser, exporter toute la réunion (tout reste sur ce Mac)

    /// « Télécharger l'extrait » : le .m4a à l'endroit choisi (panneau d'enregistrement du Mac : aucune autorisation de dossier).
    func telechargerExtrait(_ r: Reunion, passage i: Int) {
        guard r.segments.indices.contains(i), sonDisponible(r, r.segments[i]) else { return }
        let panneau = NSSavePanel()
        panneau.allowedContentTypes = [.mpeg4Audio]
        panneau.nameFieldStringValue = ExtraitsReunion.nomFichier(r, passage: i)
        panneau.title = "Télécharger l\u{2019}extrait"
        let id = r.segments[i].id
        panneau.begin { [weak self] reponse in
            guard reponse == .OK, let url = panneau.url, let self else { return }
            MainActor.assumeIsolated {
                do {
                    let source = try self.store.fichierExtrait(r, passage: i)
                    if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
                    try FileManager.default.copyItem(at: source, to: url)
                    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                    self.extraitEnregistre = id
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in if self?.extraitEnregistre == id { self?.extraitEnregistre = nil } }
                } catch { Log.ecrire("réunions : extrait non enregistré (\(error))") }
            }
        }
    }

    /// Glisser la bulle vers une app (Finder, Mail, WhatsApp) : le .m4a, fabriqué à ce moment (quelques millisecondes).
    func fournisseurGlisser(_ r: Reunion, passage i: Int) -> NSItemProvider {
        guard r.segments.indices.contains(i), sonDisponible(r, r.segments[i]), let url = try? store.fichierExtrait(r, passage: i),
              let p = NSItemProvider(contentsOf: url) else { return NSItemProvider() }
        p.suggestedName = url.deletingPathExtension().lastPathComponent
        return p
    }

    /// « Exporter l'audio » : toute la réunion en un .m4a, la piste Moi et la piste Eux mélangées, encodé hors du fil principal.
    func exporterAudioReunion(_ r: Reunion) {
        guard sonDisponible(r), exportAudio == nil else { return }
        let panneau = NSSavePanel()
        panneau.allowedContentTypes = [.mpeg4Audio]
        panneau.nameFieldStringValue = ExtraitsReunion.nomFichierReunion(r)
        panneau.title = "Télécharger l\u{2019}audio de la réunion"
        let moi = store.fichierSon(r, .moi), eux = store.fichierSon(r, .eux)
        panneau.begin { [weak self] reponse in
            guard reponse == .OK, let url = panneau.url else { return }
            MainActor.assumeIsolated {
                self?.exportAudio = 0
                Task.detached(priority: .userInitiated) { [weak self] in
                    let t0 = ProcessInfo.processInfo.systemUptime
                    var ok = true
                    do {
                        try ExportAudio.reunion(moi: moi, eux: eux, vers: url) { p in
                            Task { @MainActor [weak self] in if let a = self?.exportAudio, a < 1 { self?.exportAudio = max(a, p * 0.99) } }
                        }
                        Log.ecrire("réunions : audio de la réunion exporté en \(Int((ProcessInfo.processInfo.systemUptime - t0) * 1000)) ms")
                    } catch { ok = false; Log.ecrire("réunions : audio de la réunion non exporté (\(error))") }
                    await MainActor.run { [weak self] in
                        self?.exportAudio = ok ? 1 : nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in if self?.exportAudio == 1 { self?.exportAudio = nil } }
                    }
                }
            }
        }
    }

    // MARK: « Demander »

    func poserQuestion(_ r: Reunion) {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, reponse != .attente(question: q) else { return }
        reponse = .attente(question: q)
        let id = r.id
        tache?.cancel()
        tache = Task { [demander] in
            let etat: EtatReponse
            do { etat = .prete(question: q, try await demander(q, r)) }
            catch is CancellationError { return }
            catch {
                Log.ecrire("réunions : « Demander » impossible (\(error))")
                etat = .echec(question: q, "Pas de réponse pour l\u{2019}instant (réseau ou limite de Groq). Réessaie dans un moment.")
            }
            guard !Task.isCancelled, self.ouverte == id else { return }
            self.reponse = etat
            if case .prete = etat { self.question = "" }
        }
    }

    func poserQuestionToutes() {
        let q = questionToutes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, reponseToutes != .attente(question: q) else { return }
        reponseToutes = .attente(question: q)
        let reunions = store.reunions.filter { $0.etat == .prete }
        tache?.cancel()
        tache = Task { [demanderToutes] in
            let etat: EtatReponse
            do {
                let (rep, envoyees) = try await demanderToutes(q, reunions)
                self.envoyeesToutes = envoyees
                etat = .prete(question: q, rep)
            }
            catch is CancellationError { return }
            catch {
                Log.ecrire("réunions : « Demander à mes réunions » impossible (\(error))")
                etat = .echec(question: q, "Pas de réponse pour l\u{2019}instant (réseau ou limite de Groq). Réessaie dans un moment.")
            }
            guard !Task.isCancelled else { return }
            self.reponseToutes = etat
            if case .prete = etat { self.questionToutes = "" }
        }
    }

    /// La réunion qui porte une réponse de « Demander à mes réunions ».
    func reunionDeReponse(_ rep: QuestionReunion.Reponse) -> Reunion? {
        rep.reunion.flatMap { envoyeesToutes.indices.contains($0) ? store.reunion(id: envoyeesToutes[$0].id) : nil }
    }

    /// Pour les rendus : une réponse déjà là.
    func poserReponseToutes(_ etat: EtatReponse, envoyees: [Reunion]) { envoyeesToutes = envoyees; reponseToutes = etat }

    // MARK: actions sur la note

    func titre(_ id: UUID, devient nouveau: String) {
        guard var r = store.reunion(id: id) else { return }
        let t = nouveau.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t != r.titre, !(t.isEmpty && r.titre.isEmpty) else { return }
        r.titre = t
        store.enregistrer(r)
    }

    func renommer(_ id: UUID, orateur: String, en nom: String) {
        guard var r = store.reunion(id: id) else { return }
        let avant = r
        r.renommer(orateur: orateur, en: nom)
        if r != avant { store.enregistrer(r); Log.ecrire("réunions : un orateur renommé") }
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

    /// Un fichier Markdown, à l'endroit choisi (le panneau d'enregistrement du Mac : aucune autorisation de dossier demandée).
    func exporterMarkdown(_ r: Reunion) {
        let panneau = NSSavePanel()
        panneau.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        let propre = r.titreAffiche.components(separatedBy: CharacterSet(charactersIn: "/:\\?%*|\"<>")).joined(separator: " ")
        panneau.nameFieldStringValue = "\(propre).md"
        panneau.title = "Exporter la note"
        panneau.begin { [weak self] reponse in
            guard reponse == .OK, let url = panneau.url else { return }
            do {
                try ReunionMarkdown.rendre(r).write(to: url, atomically: true, encoding: .utf8)
                MainActor.assumeIsolated {
                    self?.exportee = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in self?.exportee = false }
                }
            } catch { Log.ecrire("réunions : export impossible (\(error.localizedDescription))") }
        }
    }

    func supprimer(_ id: UUID) {
        arreterEcoute()
        store.supprimer(id: id)
        suppressionEnAttente = false
        ouverte = affichees.first?.id
    }
}

// MARK: - couleurs des orateurs (maquette : Moi en ambre, les autres en bleu, vert, rose)

enum CouleursOrateur {
    static let moi = Palette.accent
    static let autres: [Color] = [Color(clair: 0x2F7BC4, sombre: 0x86B6E6), Palette.vertDoux, Color(clair: 0xC2456A, sombre: 0xE3A6B3), Color(clair: 0x7E57C2, sombre: 0xC6B0EA)]

    static func couleur(_ o: OrateurReunion, dans r: Reunion) -> Color {
        if o.id == Locuteur.moi.rawValue { return moi }
        let autres = r.orateursEntendus.filter { $0.id != Locuteur.moi.rawValue }
        return autres.firstIndex { $0.id == o.id }.map { Self.autres[$0 % Self.autres.count] } ?? Self.autres[0]
    }

    /// La couleur d'un nom (« qui » d'une prochaine étape) : celle de l'orateur qui le porte, sinon une couleur fixe pour ce nom.
    static func couleur(nom: String, dans r: Reunion) -> Color {
        if nom == "Moi" || nom == r.orateur(id: Locuteur.moi.rawValue).nom { return moi }
        if let o = r.orateursEntendus.first(where: { $0.nom == nom }) { return couleur(o, dans: r) }
        let n = nom.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return autres[(n + 1) % autres.count]
    }
}

/// Dates de la colonne et de l'en-tête de la note.
enum DatesReunion {
    private static func format(_ f: String) -> DateFormatter {
        let d = DateFormatter(); d.locale = Locale(identifier: "fr_FR"); d.dateFormat = f; return d
    }
    private static let jourLong = format("EEEE d MMMM")
    private static let heure = format("HH:mm")

    /// « Aujourd'hui », « Hier », « Lundi 9 novembre ».
    static func groupe(_ d: Date, aujourdhui: Date = Date(), calendrier: Calendar = .current) -> String {
        if calendrier.isDate(d, inSameDayAs: aujourdhui) { return "Aujourd\u{2019}hui" }
        if let hier = calendrier.date(byAdding: .day, value: -1, to: aujourdhui), calendrier.isDate(d, inSameDayAs: hier) { return "Hier" }
        let t = jourLong.string(from: d)
        return t.prefix(1).uppercased() + t.dropFirst()
    }

    /// « 14:02 · 29 min · 4 personnes »
    static func ligne(_ r: Reunion) -> String {
        var t = "\(heure.string(from: r.debut)) \u{00B7} \(FormatReunion.duree(r.duree))"
        if r.participants.count >= 2 { t += " \u{00B7} \(r.participants.count) personnes" }
        return t
    }

    /// « Mercredi 11 novembre · 14:02 – 14:31 · 29 min »
    static func entete(_ r: Reunion) -> String {
        let j = jourLong.string(from: r.debut)
        return (j.prefix(1).uppercased() + j.dropFirst()) + " \u{00B7} \(heure.string(from: r.debut)) \u{2013} \(heure.string(from: r.debut.addingTimeInterval(r.duree))) \u{00B7} \(FormatReunion.duree(r.duree))"
    }
}

// MARK: - l'onglet

struct ReunionsVue: View {
    @ObservedObject var m: ReunionsModele
    @ObservedObject var store: ReunionStore
    @ObservedObject var controleur: ReunionController
    var curseurFactice = false
    static let largeurColonne: CGFloat = 262
    /// Sous cette largeur, la colonne et la note ne tiennent plus côte à côte : l'une ou l'autre.
    static let largeurEtroite: CGFloat = 720
    /// 0 au départ : la vue étroite d'abord, la large dès que la largeur est connue (elle seule ouvre d'office la première note).
    @State private var largeur: CGFloat = 0

    var body: some View {
        Group {
            if largeur < Self.largeurEtroite {
                if m.demandeToutes { DemandeToutesVue(m: m, retour: true) }
                else if let r = m.reunionOuverte { NoteReunionVue(m: m, r: r.echeancesCalculees(), retour: true) }
                else { colonne.frame(maxWidth: .infinity) }
            } else {
                // maquette lucarne-app-final.html (étape 10) : la liste à gauche, la note dans une carte à droite
                HStack(spacing: 16) {
                    colonne.frame(width: Self.largeurColonne)
                    CarteBureau { principal.frame(maxWidth: .infinity, maxHeight: .infinity) }
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .onAppear { if m.reunionOuverte == nil { m.ouverte = store.reunions.first?.id } }
            }
        }
        .background(GeometryReader { g in Color.clear.onAppear { largeur = g.size.width }.onChange(of: g.size.width) { _, w in largeur = w } })
    }

    private var colonne: some View { ColonneReunions(m: m, store: store, controleur: controleur, curseurFactice: curseurFactice, etroite: largeur < Self.largeurEtroite) }

    @ViewBuilder private var principal: some View {
        if m.demandeToutes { DemandeToutesVue(m: m, retour: false) }
        else if let r = m.reunionOuverte { NoteReunionVue(m: m, r: r.echeancesCalculees(), retour: false).id(r.id) }
        else { vide }
    }

    private var vide: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.reunions.isEmpty ? "Aucune réunion pour l\u{2019}instant." : "Choisis une réunion.").font(Polices.texte(22)).foregroundStyle(Palette.texte2)
            if store.reunions.isEmpty {
                Text("Pendant un appel, Voxile propose « Noter cet appel ? » dans l\u{2019}îlot. Il écoute ton micro et le son du Mac, puis écrit la note.")
                    .font(Polices.commande(13.5)).foregroundStyle(Palette.texte3).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: 460, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// « Gardé sur ce Mac » avec son cadenas : tout reste local.
struct MentionLocale: View {
    var taille: CGFloat = 13
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock").font(.system(size: taille - 1, weight: .regular))
            Text("Gardé sur ce Mac").font(Polices.commande(taille))
        }
        .foregroundStyle(Palette.texte3)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - la colonne de gauche

struct ColonneReunions: View {
    @ObservedObject var m: ReunionsModele
    @ObservedObject var store: ReunionStore
    @ObservedObject var controleur: ReunionController
    var curseurFactice = false
    var etroite = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            champ
            RangeeColonne(icone: "bubble.left", titre: "Demander à mes réunions", choisie: m.demandeToutes) { m.ouvrirDemandeToutes() }
                .padding(.top, 8)
            RangeeColonne(icone: controleur.enregistre ? "stop.circle" : "record.circle", titre: controleur.enregistre ? "Arrêter la réunion" : "Noter la réunion",
                          teinte: controleur.enregistre ? Color(clair: 0xD70015, sombre: 0xFF6961) : nil, choisie: false) { m.surNoter() }
            if let libelle = controleur.libelleEnCours {
                HStack(spacing: 7) {
                    Circle().fill(Palette.accent).frame(width: 6, height: 6)
                    Text(libelle).font(Polices.commande(12)).foregroundStyle(Palette.texte2).lineLimit(1)
                }
                .padding(.horizontal, 9).padding(.top, 6)
                .accessibilityElement(children: .combine)
            }
            if store.reunions.isEmpty {
                Text("Aucune réunion pour l\u{2019}instant.").font(Polices.commande(12.5)).foregroundStyle(Palette.texte3).padding(.horizontal, 9).padding(.top, 16)
            } else if m.affichees.isEmpty {
                Text("Aucun résultat").font(Polices.commande(12.5)).foregroundStyle(Palette.texte3).padding(.horizontal, 9).padding(.top, 16)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(groupes, id: \.titre) { g in
                                Text(g.titre).font(Polices.commande(11, .semibold)).foregroundStyle(Palette.texte3)
                                    .padding(.leading, 8).padding(.top, 14).padding(.bottom, 4)
                                    .accessibilityAddTraits(.isHeader)
                                ForEach(g.reunions) { r in
                                    LigneColonne(r: r, choisie: !m.demandeToutes && m.ouverte == r.id) { m.ouvrir(r.id) }.id(r.id)
                                }
                            }
                        }
                        .padding(.bottom, 8)
                    }
                    .onChange(of: m.ouverte) { _, id in if let id { withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id) } } }
                }
            }
            Spacer(minLength: 0)
            MentionLocale(taille: 12).padding(.horizontal, 9).frame(height: 36)
        }
        .padding(.top, 2)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var groupes: [(titre: String, reunions: [Reunion])] {
        var sortie: [(titre: String, reunions: [Reunion])] = []
        for r in m.affichees {
            let t = DatesReunion.groupe(r.debut, aujourdhui: m.aujourdhui())
            if sortie.last?.titre == t { sortie[sortie.count - 1].reunions.append(r) } else { sortie.append((t, [r])) }
        }
        return sortie
    }

    private var champ: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.texte3)
            ZStack(alignment: .leading) {
                ChampRecherche(texte: $m.requete, invite: "Rechercher dans les réunions", taille: 12.5, jetonFocus: m.jetonFocus, surCommande: m.commande)
                if curseurFactice && m.requete.isEmpty && !etroite {
                    RoundedRectangle(cornerRadius: 1).fill(Palette.accent).frame(width: 1.5, height: 15).offset(x: -1)
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 9).fill(Palette.voile(0.06)))
    }
}

/// « Demander à mes réunions », « Noter la réunion » : une rangée de la colonne.
struct RangeeColonne: View {
    var icone: String
    var titre: String
    var teinte: Color? = nil
    var choisie: Bool
    var action: () -> Void
    @State private var survol = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icone).font(.system(size: 13, weight: .medium)).frame(width: 16)
                    .foregroundStyle(teinte ?? (choisie ? Palette.texte : Palette.texte2))
                Text(titre).font(Polices.commande(12.5, .medium)).foregroundStyle(choisie || survol ? Palette.texte : Palette.texte2).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 8).fill(Palette.voile(choisie ? 0.08 : (survol ? 0.04 : 0))))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { survol = $0 }
        .accessibilityAddTraits(choisie ? [.isSelected] : [])
    }
}

/// Une réunion dans la colonne : le titre, puis « 14:02 · 29 min · 4 personnes ».
struct LigneColonne: View {
    let r: Reunion
    var choisie: Bool
    var ouvrir: () -> Void
    @State private var survol = false
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(r.titreAffiche).font(Polices.commande(13.5, .semibold)).foregroundStyle(Palette.texte).lineLimit(1).truncationMode(.tail)
            Text(sousTitre).font(Polices.commande(12)).foregroundStyle(Palette.texte3).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background {
            // la réunion ouverte : une petite carte, comme sur la maquette ; le survol, un voile léger
            if choisie { CarteBureau(rayon: 14) { Color.clear } } else { RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.voile(survol ? 0.04 : 0)) }
        }
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onHover { survol = $0 }
        .onTapGesture(perform: ouvrir)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(choisie ? [.isSelected, .isButton] : .isButton)
    }
    private var sousTitre: String {
        switch r.etat {
        case .prete: return DatesReunion.ligne(r)
        case .sansNote: return DatesReunion.ligne(r) + " \u{00B7} sans note"
        default: return "En préparation\u{2026}"
        }
    }
}

// MARK: - la note

struct NoteReunionVue: View {
    @ObservedObject var m: ReunionsModele
    var r: Reunion
    /// Fenêtre étroite : un bouton « ‹ Réunions » ramène à la liste.
    var retour: Bool
    @State private var titre = ""
    @FocusState private var titreFocus: Bool
    @State private var largeur: CGFloat = 900
    @State private var renomme: String?
    @State private var nouveauNom = ""
    @FocusState private var nomFocus: Bool
    /// Sous cette largeur utile, Décisions et Prochaines étapes passent sous le résumé.
    static let largeurDeuxColonnes: CGFloat = 640
    private var deuxColonnes: Bool { min(780, largeur - 80) >= Self.largeurDeuxColonnes }

    var body: some View {
        VStack(spacing: 0) {
            barre.padding(.horizontal, 16).frame(height: 44)
            ZStack(alignment: .bottom) {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        page.frame(maxWidth: 780).frame(maxWidth: .infinity)
                            .padding(.horizontal, 40).padding(.top, 14).padding(.bottom, 200)
                    }
                    .onChange(of: m.allerA?.jeton) { _, _ in
                        guard let a = m.allerA, r.segments.indices.contains(a.index) else { return }
                        // « Réduire les animations » : on saute au moment, sans glisser
                        withAnimation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .easeInOut(duration: 0.35)) {
                            proxy.scrollTo(r.segments[a.index].id, anchor: UnitPoint(x: 0.5, y: 0.3))
                        }
                    }
                }
                ChampDemander(m: m, texte: $m.question, invite: "Demander quelque chose sur cette réunion", etat: m.reponse, largeur: largeur,
                              surEnvoyer: { m.poserQuestion(r) }) { rep in lienReponse(rep) }
            }
        }
        .background(GeometryReader { g in Color.clear.onAppear { largeur = g.size.width }.onChange(of: g.size.width) { _, w in largeur = w } })
        .onAppear { titre = r.titre }
        .onChange(of: r.titre) { _, nouveau in if !titreFocus { titre = nouveau } }
        .onDisappear { m.arreterEcoute() }
        .background { if retour { Button("") { m.fermerLaNote() }.keyboardShortcut(.escape, modifiers: []).opacity(0).frame(width: 0, height: 0) } }
    }

    // MARK: barre

    private var barre: some View {
        HStack(spacing: 6) {
            if retour {
                Button { m.fermerLaNote() } label: {
                    HStack(spacing: 4) { Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold)); Text("Réunions").font(Polices.commande(13)) }
                        .foregroundStyle(Palette.texte2).padding(.horizontal, 6).frame(height: 28).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            if m.suppressionEnAttente {
                Text("Effacer cette réunion ?").font(Polices.commande(12.5)).foregroundStyle(Palette.texte2)
                BoutonNote(titre: "Effacer") { m.supprimer(r.id) }
                BoutonNote(titre: "Garder") { m.suppressionEnAttente = false }
            } else {
                BoutonNote(titre: m.copiee ? "Copiée" : "Copier", icone: m.copiee ? "checkmark" : nil, fait: m.copiee) { m.copier(r) }
                BoutonNote(titre: m.exportee ? "Enregistrée" : "Exporter", icone: m.exportee ? "checkmark" : "arrow.down.circle", fait: m.exportee) { m.exporterMarkdown(r) }
                if m.sonDisponible(r) {
                    let a = m.exportAudio
                    BoutonNote(titre: a == 1 ? "Audio enregistré" : (a != nil ? "Audio \(PreparationNote.pourcent(a ?? 0))" : "Télécharger l\u{2019}audio"),
                               icone: a == 1 ? "checkmark" : "arrow.down.to.line", fait: a == 1) { m.exporterAudioReunion(r) }
                        .help("Télécharger toute la réunion en un fichier audio (.m4a), ta voix et celle des autres mélangées ; rien ne quitte ce Mac")
                }
                BoutonNote(titre: "Effacer", discret: true) { m.suppressionEnAttente = true }
            }
        }
    }

    // MARK: page

    private var page: some View {
        VStack(alignment: .leading, spacing: 0) {
            if deuxColonnes {
                HStack(alignment: .top, spacing: 34) {
                    gauche.frame(maxWidth: .infinity, alignment: .leading)
                    droite.frame(width: 290)
                }
            } else {
                gauche
                droite.padding(.top, 20)
            }
            if !r.avertissements.isEmpty { avertissements.padding(.top, 22) }
            if !r.segments.isEmpty { transcription.padding(.top, 30) }
        }
    }

    private var gauche: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField(r.titreAffiche, text: $titre, axis: .vertical)
                .textFieldStyle(.plain).font(Polices.texte(29)).foregroundStyle(Palette.texte).tint(Palette.accent)
                .focused($titreFocus)
                .onSubmit { m.titre(r.id, devient: titre); titreFocus = false }
                .onChange(of: titreFocus) { _, f in if !f { m.titre(r.id, devient: titre) } }
                .accessibilityLabel("Titre de la réunion")
            meta.padding(.top, 8)
            if let b = r.enBref?.trimmingCharacters(in: .whitespacesAndNewlines), !b.isEmpty {
                Text(b).font(Polices.texte(16)).lineSpacing(4.5).foregroundStyle(Palette.texte).fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled).padding(.top, 16).frame(maxWidth: 700, alignment: .leading)
            }
            if let e = etat { e.padding(.top, 16) }
            resume
        }
    }

    /// La date, l'heure, la durée, puis les orateurs avec leur couleur (un clic : renommer, une fois pour toutes).
    private var meta: some View {
        FlowLigne(espaceH: 14, espaceV: 6) {
            Text(DatesReunion.entete(r)).font(Polices.commande(12.5)).foregroundStyle(Palette.texte3)
            ForEach(r.orateursEntendus) { o in
                if renomme == o.id {
                    TextField("", text: $nouveauNom)
                        .textFieldStyle(.plain).font(Polices.commande(12.5)).foregroundStyle(Palette.texte).frame(width: 110)
                        .focused($nomFocus)
                        .onSubmit { valider(o) }
                        .onChange(of: nomFocus) { _, f in if !f, renomme == o.id { valider(o) } }
                        .onAppear { nomFocus = true }
                } else {
                    Button { nouveauNom = SeparationVoix.estNomParDefaut(o.nom) ? "" : o.nom; renomme = o.id } label: {
                        HStack(spacing: 5) {
                            Circle().fill(CouleursOrateur.couleur(o, dans: r)).frame(width: 7, height: 7)
                            Text(o.nom).font(Polices.commande(12.5)).foregroundStyle(Palette.texte2)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Renommer \(o.nom) dans toute la réunion")
                    .accessibilityLabel("\(o.nom), renommer")
                }
            }
        }
    }

    private func valider(_ o: OrateurReunion) {
        m.renommer(r.id, orateur: o.id, en: nouveauNom)
        renomme = nil
    }

    private var etat: AnyView? {
        switch r.etat {
        case .prete:
            // une partie de l'appel n'a pas pu être relue (réseau, limite) : le son est gardé quelques jours pour réessayer
            guard r.relue == false, m.sonDisponible(r) else { return nil }
            return AnyView(HStack(spacing: 12) {
                Text("Une partie de l\u{2019}appel n\u{2019}a pas pu être relue.").font(Polices.commande(13.5)).foregroundStyle(Palette.texte2)
                BoutonNote(titre: "Refaire la note") { m.surRefaireLaNote(r.id) }
            })
        case .sansNote:
            // la transcription, ou à défaut le son de l'appel (Verbe fermé pendant l'appel, relecture impossible), suffit à réessayer
            return AnyView(HStack(spacing: 12) {
                Text("La note n\u{2019}a pas été écrite.").font(Polices.commande(13.5)).foregroundStyle(Palette.texte2)
                if !r.segments.isEmpty || m.sonDisponible(r) { BoutonNote(titre: "Refaire la note") { m.surRefaireLaNote(r.id) } }
            })
        default:
            return AnyView(Text("La note est en préparation\u{2026}").font(Polices.commande(13.5)).foregroundStyle(Palette.texte2))
        }
    }

    // MARK: résumé par sujet

    @ViewBuilder private var resume: some View {
        let sujets = r.sujets ?? (r.dit.isEmpty ? [] : [SujetReunion(titre: "", puces: r.dit.map { PuceReunion(texte: $0) })])
        let points = (r.points ?? []).sorted()
        if !sujets.isEmpty || !points.isEmpty {
            Entete(texte: "Résumé par sujet").padding(.top, 22)
            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(sujets.enumerated()), id: \.offset) { _, s in
                    VStack(alignment: .leading, spacing: 0) {
                        if !s.titre.isEmpty {
                            Text(s.titre).font(Polices.commande(14.5, .semibold)).foregroundStyle(Palette.texte).accessibilityAddTraits(.isHeader)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(Array(s.puces.enumerated()), id: \.offset) { _, p in
                                Puce(texte: p.texte, niveau: 0)
                                ForEach(Array(p.sous.enumerated()), id: \.offset) { _, x in Puce(texte: x, niveau: 1).padding(.leading, 14) }
                            }
                        }
                        .padding(.top, s.titre.isEmpty ? 0 : 6)
                    }
                }
                if !points.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Point\(points.count > 1 ? "s" : "") marqué\(points.count > 1 ? "s" : "") pendant l\u{2019}appel").font(Polices.commande(14.5, .semibold)).foregroundStyle(Palette.texte)
                        ForEach(points, id: \.self) { t in
                            Button { allerAuPoint(t) } label: {
                                HStack(alignment: .firstTextBaseline, spacing: 7) {
                                    Image(systemName: "flag.fill").font(.system(size: 11, weight: .semibold))
                                    Text(FormatReunion.heure(r.debut.addingTimeInterval(t)) + " \u{00B7} " + String(ReunionMarkdown.avant(t, dans: r.segments).dropFirst(2)))
                                        .font(Polices.commande(12.5, .semibold)).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                                }
                                .foregroundStyle(Palette.orangeVif).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func allerAuPoint(_ t: Double) {
        guard let i = r.segments.lastIndex(where: { $0.debut <= t }) ?? r.segments.indices.first else { return }
        m.allerAuPassage(r, i)
    }

    // MARK: Décisions, Prochaines étapes

    @ViewBuilder private var droite: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !r.decisions.isEmpty {
                Boite(titre: "Décisions") {
                    ForEach(Array(r.decisions.enumerated()), id: \.offset) { i, d in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.vertDoux).frame(width: 14, height: 18)
                            Text("\(Text(d).foregroundColor(Palette.texte))\(Text(r.echeance(decision: i).map { " \u{00B7} \($0.quand)" } ?? "").foregroundColor(Palette.texte3))")
                                .font(Polices.commande(13)).lineSpacing(2).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        }
                        .padding(.vertical, 5)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            if !r.actions.isEmpty {
                Boite(titre: "Prochaines étapes") {
                    ForEach(Array(r.actions.enumerated()), id: \.element.id) { i, a in etape(a).overlay(alignment: .top) { if i > 0 { Rectangle().fill(Palette.filet).frame(height: 1) } } }
                }
            }
        }
    }

    private func etape(_ a: ActionReunion) -> some View {
        let e = Echeance.etiquette(quand: a.quand, date: a.echeance)
        return Button { m.cocher(r.id, action: a.id) } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    if let q = a.qui, !q.isEmpty {
                        let c = CouleursOrateur.couleur(nom: q, dans: r)
                        HStack(spacing: 6) { Circle().fill(c).frame(width: 7, height: 7); Text(q).font(Polices.commande(12, .semibold)).foregroundStyle(c) }
                    }
                    Spacer(minLength: 0)
                    if !e.sansDate {
                        Text(e.texte).font(Polices.commande(11.5, .semibold)).foregroundStyle(Palette.texte2).lineLimit(1)
                            .padding(.horizontal, 7).padding(.vertical, 1).background(RoundedRectangle(cornerRadius: 6).fill(Palette.voile(0.07)))
                    }
                }
                HStack(alignment: .top, spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 4).strokeBorder(a.fait ? Palette.texte2 : Palette.texte3, lineWidth: 1.4)
                        if a.fait { Image(systemName: "checkmark").font(.system(size: 8.5, weight: .heavy)).foregroundStyle(Palette.texte2) }
                    }
                    .frame(width: 14, height: 14).padding(.top, 2)
                    Text(a.quoi).font(Polices.commande(13)).lineSpacing(2).foregroundStyle(a.fait ? Palette.texte3 : Palette.texte)
                        .strikethrough(a.fait, color: Palette.texte3).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(a.qui.map { $0 + " : " } ?? "")\(a.quoi)\(e.sansDate ? "" : ", " + e.texte)")
        .accessibilityValue(a.fait ? "fait" : "à faire")
        .accessibilityAddTraits(.isToggle)
    }

    private var avertissements: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(r.avertissements.enumerated()), id: \.offset) { _, t in
                Text(t).font(Polices.commande(12.5)).foregroundStyle(Palette.texte3).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: transcription

    private var transcription: some View {
        let son = m.sonDisponible(r)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Entete(texte: "Transcription").padding(.bottom, 0)
                Spacer()
                Text(son ? "Chaque passage se réécoute, se télécharge, se glisse vers une app" : "Audio effacé \u{00B7} pour le garder : Réglages \u{203A} Garder le son des réunions")
                    .font(Polices.commande(12)).foregroundStyle(Palette.texte3).lineLimit(1)
            }
            ForEach(Array(LignesTranscription.elements(r).enumerated()), id: \.offset) { _, e in
                switch e {
                case .point(let t):
                    HStack(spacing: 7) {
                        Image(systemName: "flag.fill").font(.system(size: 10, weight: .semibold))
                        Text("Point marqué \u{00B7} " + FormatReunion.heure(r.debut.addingTimeInterval(t))).font(Polices.commande(12, .semibold)).fixedSize()
                        Rectangle().fill(Palette.orangeVif.opacity(0.3)).frame(height: 1)
                    }
                    .foregroundStyle(Palette.orangeVif)
                    .padding(.top, 10).padding(.bottom, 4)
                    .accessibilityElement(children: .combine)
                case .passage(let i, let heure):
                    LigneTranscriptionVue(m: m, r: r, index: i, heure: heure, son: son && m.sonDisponible(r, r.segments[i])).id(r.segments[i].id)
                }
            }
        }
        .padding(.top, 20)
        .overlay(alignment: .top) { Rectangle().fill(Palette.filet).frame(height: 1) }
        .onAppear { m.chargerOndes(r) }
        .onChange(of: r.id) { _, _ in m.chargerOndes(r) }
    }

    // MARK: la réponse renvoie au moment

    @ViewBuilder private func lienReponse(_ rep: QuestionReunion.Reponse) -> some View {
        if let i = rep.passage, r.segments.indices.contains(i) {
            let h = FormatReunion.heure(r.debut.addingTimeInterval(r.segments[i].debut))
            let son = m.sonDisponible(r, r.segments[i])
            Button { m.allerAuPassage(r, i) } label: {
                HStack(spacing: 4) {
                    Image(systemName: son ? "play.fill" : "text.quote").font(.system(size: 9.5, weight: .bold))
                    Text(son ? "Écouter à \(h)" : "Voir à \(h)").font(Polices.commande(12.5, .semibold))
                    Image(systemName: "chevron.right").font(.system(size: 9.5, weight: .bold))
                }
                .foregroundStyle(Palette.accent).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

/// Une ligne de la transcription : l'orateur (et l'heure sur la première ligne de chaque minute), le texte, puis sa bulle audio
/// (comme un vocal). Un clic sur le texte joue la bulle (ou la met en pause).
struct LigneTranscriptionVue: View {
    @ObservedObject var m: ReunionsModele
    var r: Reunion
    var index: Int
    var heure: String?
    var son: Bool
    @State private var survol = false

    var body: some View {
        let s = r.segments[index]
        let o = r.orateur(de: s)
        let actif = m.ecoute == index
        let repere = m.repere == index
        VStack(alignment: .leading, spacing: 7) {
            Button { m.ecouter(r, passage: index) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(o.nom).font(Polices.commande(12.5, .semibold)).foregroundStyle(CouleursOrateur.couleur(o, dans: r))
                        if let heure { Text(heure).font(Polices.commande(12.5, .medium).monospacedDigit()).foregroundStyle(Palette.texte3) }
                        Spacer(minLength: 0)
                    }
                    Text(s.texte).font(Polices.texte(15)).lineSpacing(4).foregroundStyle(Palette.texte).multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint(son ? (actif ? "Met en pause" : "Réécoute ce moment") : "")
            BulleAudio(m: m, r: r, index: index, son: son, couleur: CouleursOrateur.couleur(o, dans: r))
        }
        .padding(.horizontal, 10).padding(.top, 7).padding(.bottom, 9)
        .background(RoundedRectangle(cornerRadius: 10).fill(actif || repere ? Palette.accent.opacity(0.10) : Palette.voile(survol && son ? 0.035 : 0)))
        .padding(.horizontal, -10).padding(.top, 4)
        .onHover { survol = $0 }
    }
}

/// La bulle audio d'un passage, façon vocal : ▶︎ / ❚❚, l'onde du vrai son (la part jouée en couleur, un clic s'y place), la durée
/// (le temps écoulé pendant la lecture), la vitesse, « Télécharger l'extrait ». La bulle entière se glisse vers une app comme un
/// fichier .m4a. Le son effacé (réglage « Garder le son des réunions » éteint, ou délai passé) : la bulle est grise, « audio effacé ».
struct BulleAudio: View {
    @ObservedObject var m: ReunionsModele
    var r: Reunion
    var index: Int
    var son: Bool
    var couleur: Color
    static let largeurOnde: CGFloat = 150

    var body: some View {
        let s = r.segments[index]
        let actif = m.ecoute == index
        let joue = actif && !m.enPause
        let e = ExtraitsReunion.extrait(r, passage: index)
        let duree = e?.duree ?? max(0, s.fin - s.debut)
        HStack(spacing: 9) {
            if son {
                Button { m.ecouter(r, passage: index) } label: {
                    ZStack {
                        Circle().fill(couleur)
                        Image(systemName: joue ? "pause.fill" : "play.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.surface)
                            .offset(x: joue ? 0 : 1)
                    }
                    .frame(width: 26, height: 26).contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(joue ? "Pause" : "Lire l\u{2019}extrait")
                Group {
                    if joue {
                        TimelineView(.periodic(from: .now, by: 0.1)) { _ in onde(progression: m.progression(index)) }
                    } else {
                        onde(progression: actif ? m.progression(index) : 0)
                    }
                }
                .frame(width: Self.largeurOnde, height: 22)
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { v in m.placer(r, passage: index, fraction: Double(v.location.x / Self.largeurOnde)) })
                .accessibilityLabel("Onde de l\u{2019}extrait, cliquer pour se placer")
                Group {
                    if joue {
                        TimelineView(.periodic(from: .now, by: 0.5)) { _ in temps(duree * m.progression(index)) }
                    } else { temps(actif ? duree * m.progression(index) : duree) }
                }
                if actif {
                    Button { m.changerVitesse() } label: {
                        Text(ExtraitsReunion.libelleVitesse(m.vitesse)).font(Polices.commande(11.5, .semibold).monospacedDigit())
                            .foregroundStyle(Palette.texte).padding(.horizontal, 7).frame(height: 20)
                            .background(Capsule().fill(Palette.voile(0.12)))
                    }
                    .buttonStyle(.plain)
                    .help("Vitesse de lecture")
                    .accessibilityLabel("Vitesse \(ExtraitsReunion.libelleVitesse(m.vitesse))")
                }
                Button { m.telechargerExtrait(r, passage: index) } label: {
                    Image(systemName: m.extraitEnregistre == s.id ? "checkmark" : "arrow.down.to.line")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(m.extraitEnregistre == s.id ? Palette.vertDoux : Palette.texte2)
                        .frame(width: 22, height: 22).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Télécharger l\u{2019}extrait (.m4a)")
                .accessibilityLabel("Télécharger l\u{2019}extrait")
            } else {
                ZStack {
                    Circle().fill(Palette.voile(0.08))
                    Image(systemName: "play.slash.fill").font(.system(size: 9.5, weight: .bold)).foregroundStyle(Palette.texte3)
                }
                .frame(width: 26, height: 26)
                Canvas { ctx, taille in Self.barres(ctx, taille, Array(repeating: 0.16, count: ExtraitsReunion.barres), joue: 0, couleur: Palette.texte3.opacity(0.5), reste: Palette.texte3.opacity(0.5)) }
                    .frame(width: Self.largeurOnde, height: 22)
                Text("audio effacé").font(Polices.commande(11.5)).foregroundStyle(Palette.texte3)
            }
        }
        .padding(.leading, 4).padding(.trailing, 8).frame(height: 34)
        .background(Capsule().fill(Palette.voile(son ? 0.06 : 0.03)))
        .onDrag { son ? m.fournisseurGlisser(r, passage: index) : NSItemProvider() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(son ? "Extrait audio, \(ExtraitsReunion.duree(duree))" : "Audio effacé")
    }

    private func temps(_ t: Double) -> some View {
        Text(ExtraitsReunion.duree(t)).font(Polices.commande(11.5, .medium).monospacedDigit()).foregroundStyle(Palette.texte2).frame(minWidth: 30, alignment: .leading)
    }

    private func onde(progression: Double) -> some View {
        let hauteurs = m.ondes[r.segments[index].id] ?? Array(repeating: 0.16, count: ExtraitsReunion.barres)
        return Canvas { ctx, taille in Self.barres(ctx, taille, hauteurs, joue: progression, couleur: couleur, reste: Palette.voile(0.32)) }
    }

    /// Les barres de l'onde : la part jouée dans la couleur de l'orateur.
    static func barres(_ ctx: GraphicsContext, _ taille: CGSize, _ h: [Float], joue: Double, couleur: Color, reste: Color) {
        let n = max(1, h.count)
        let pas = taille.width / CGFloat(n), l = max(1.5, pas * 0.55)
        for (i, v) in h.enumerated() {
            let hauteur = max(2.5, CGFloat(v) * taille.height)
            let x = CGFloat(i) * pas + (pas - l) / 2
            let rect = CGRect(x: x, y: (taille.height - hauteur) / 2, width: l, height: hauteur)
            let fait = (CGFloat(i) + 0.5) / CGFloat(n) <= CGFloat(joue)
            ctx.fill(Path(roundedRect: rect, cornerRadius: l / 2), with: .color(fait ? couleur : reste))
        }
    }
}

/// Le champ « Demander » en bas de page, avec la réponse au-dessus (fond qui s'efface vers le haut).
struct ChampDemander<Lien: View>: View {
    @ObservedObject var m: ReunionsModele
    @Binding var texte: String
    var invite: String
    var etat: EtatReponse?
    var largeur: CGFloat
    var surEnvoyer: () -> Void
    @ViewBuilder var lien: (QuestionReunion.Reponse) -> Lien
    @State private var actif = false

    var body: some View {
        let marge = max(32, (largeur - 620) / 2)
        VStack(spacing: 8) {
            if let etat { carte(etat) }
            HStack(spacing: 9) {
                Image(systemName: "bubble.left").font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.texte3)
                ChampRecherche(texte: $texte, invite: invite, taille: 14, jetonFocus: m.jetonQuestion, surCommande: { c in
                    if c == .entree { surEnvoyer(); return true }
                    if c == .echap { texte = ""; return true }
                    return false
                }, focusAuMontage: false, surFocus: { f in actif = f })
                Button(action: surEnvoyer) {
                    ZStack {
                        Circle().fill(texte.isEmpty ? Palette.voile(0.1) : Palette.texte)
                        Image(systemName: "arrow.up").font(.system(size: 13, weight: .bold)).foregroundStyle(texte.isEmpty ? Palette.texte3 : Palette.surface)
                    }
                    .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Envoyer la question")
            }
            .padding(.leading, 15).padding(.trailing, 6)
            .frame(height: 44)
            .background(Capsule().fill(Palette.selection))
            .overlay(Capsule().strokeBorder(actif ? Palette.accent.opacity(0.6) : Palette.voile(0.1), lineWidth: actif ? 1.5 : 0.5))
            .shadow(color: Palette.ombre, radius: 17, y: 12)
        }
        .padding(.horizontal, marge).padding(.top, 30).padding(.bottom, 14)
        .background(LinearGradient(stops: [.init(color: TonsBureau.carte.opacity(0), location: 0), .init(color: TonsBureau.carte, location: 0.32)], startPoint: .top, endPoint: .bottom).allowsHitTesting(false))
    }

    private func carte(_ e: EtatReponse) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(e.question).font(Polices.commande(12, .semibold)).foregroundStyle(Palette.texte3).lineLimit(2)
            switch e {
            case .attente:
                HStack(spacing: 4) { ForEach(0..<3, id: \.self) { _ in Circle().fill(Palette.texte3).frame(width: 6, height: 6) } }.padding(.top, 8)
                    .accessibilityLabel("Réponse en cours")
            case .prete(_, let rep):
                Text(rep.texte).font(Polices.texte(15)).lineSpacing(3).foregroundStyle(Palette.texte).fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled).padding(.top, 4)
                lien(rep).padding(.top, 6)
            case .echec(_, let t):
                Text(t).font(Polices.commande(13)).foregroundStyle(Palette.texte2).fixedSize(horizontal: false, vertical: true).padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 15).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16).fill(Palette.relief))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.voile(0.08), lineWidth: 0.5))
        .shadow(color: Palette.ombre, radius: 15, y: 10)
    }
}

/// « Demander à mes réunions » : une question sur toutes les notes ; la réponse renvoie à la réunion qui la porte.
struct DemandeToutesVue: View {
    @ObservedObject var m: ReunionsModele
    var retour: Bool
    @State private var largeur: CGFloat = 900
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if retour {
                    Button { m.demandeToutes = false } label: {
                        HStack(spacing: 4) { Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold)); Text("Réunions").font(Polices.commande(13)) }
                            .foregroundStyle(Palette.texte2).frame(height: 28).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 16).frame(height: 44)
            ZStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Demander à mes réunions").font(Polices.texte(29)).foregroundStyle(Palette.texte)
                    Text("Une question sur toutes tes notes : qui a promis quoi, une date, un chiffre. Seules les notes partent au service de Groq, pas le son.")
                        .font(Polices.commande(13)).foregroundStyle(Palette.texte3).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 620, alignment: .leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 40).padding(.top, 14)
                ChampDemander(m: m, texte: $m.questionToutes, invite: "Demander à toutes mes réunions", etat: m.reponseToutes, largeur: largeur,
                              surEnvoyer: { m.poserQuestionToutes() }) { rep in
                    if let r = m.reunionDeReponse(rep) {
                        Button { m.ouvrir(r.id) } label: {
                            HStack(spacing: 4) {
                                Text("Ouvrir \u{00B7} \(r.titreAffiche)").font(Polices.commande(12.5, .semibold)).lineLimit(1)
                                Image(systemName: "chevron.right").font(.system(size: 9.5, weight: .bold))
                            }
                            .foregroundStyle(Palette.accent).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .background(GeometryReader { g in Color.clear.onAppear { largeur = g.size.width }.onChange(of: g.size.width) { _, w in largeur = w } })
    }
}

// MARK: - petites pièces

/// Un en-tête de section (« Résumé par sujet », « Décisions ») : 12 pt, gris.
struct Entete: View {
    var texte: String
    var body: some View {
        Text(texte).font(Polices.commande(12, .semibold)).tracking(0.24).foregroundStyle(Palette.texte3).padding(.bottom, 10).accessibilityAddTraits(.isHeader)
    }
}

/// Une puce du résumé : un rond plein (niveau 0) ou un rond vide plus petit, plus gris (niveau 1).
struct Puce: View {
    var texte: String
    var niveau: Int
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Circle().fill(niveau == 0 ? Palette.texte3 : .clear).overlay(Circle().strokeBorder(Palette.texte3, lineWidth: niveau == 0 ? 0 : 1))
                .frame(width: 4.5, height: 4.5).offset(x: 2, y: -3.5).frame(width: 14, alignment: .leading)
            Text(texte).font(Polices.commande(niveau == 0 ? 13.5 : 13)).lineSpacing(niveau == 0 ? 3.5 : 2.5).foregroundStyle(niveau == 0 ? Palette.texte : Palette.texte2)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }
    }
}

/// Une boîte de la colonne de droite (fond relevé, coins de 14 pt).
struct Boite<Contenu: View>: View {
    var titre: String
    @ViewBuilder var contenu: Contenu
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Entete(texte: titre)
            contenu
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.top, 13).padding(.bottom, 12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Palette.selection))
    }
}

/// Un bouton de la barre de la note (« Copier », « Exporter ») : capsule discrète, vert une fois fait.
struct BoutonNote: View {
    var titre: String
    var icone: String? = nil
    var fait = false
    var discret = false
    var action: () -> Void
    @State private var survol = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icone { Image(systemName: icone).font(.system(size: 11.5, weight: .semibold)) }
                Text(titre).font(Polices.commande(12.5, .semibold)).lineLimit(1)
            }
            .foregroundStyle(fait ? Palette.vertDoux : (discret && !survol ? Palette.texte3 : Palette.texte))
            .padding(.leading, icone == nil ? 12 : 10).padding(.trailing, 12).frame(height: 28)
            .background(Capsule().fill(Palette.voile(discret ? (survol ? 0.07 : 0) : (survol ? 0.12 : 0.07))))
            .contentShape(Capsule())
            .fixedSize()
        }
        .buttonStyle(.plain)
        .onHover { survol = $0 }
        .accessibilityLabel(titre)
    }
}

/// Des éléments posés en ligne, qui passent à la ligne suivante quand la place manque.
struct FlowLigne: Layout {
    var espaceH: CGFloat
    var espaceV: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 600
        var x: CGFloat = 0, y: CGFloat = 0, ligne: CGFloat = 0, large: CGFloat = 0
        for v in subviews {
            let t = v.sizeThatFits(.unspecified)
            if x > 0, x + t.width > w { y += ligne + espaceV; x = 0; ligne = 0 }
            x += t.width + espaceH; ligne = max(ligne, t.height); large = max(large, x - espaceH)
        }
        return CGSize(width: min(w, large), height: y + ligne)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, ligne: CGFloat = 0
        for v in subviews {
            let t = v.sizeThatFits(.unspecified)
            if x > bounds.minX, x + t.width > bounds.maxX { y += ligne + espaceV; x = bounds.minX; ligne = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(t))
            x += t.width + espaceH; ligne = max(ligne, t.height)
        }
    }
}
