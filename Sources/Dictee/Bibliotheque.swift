import AppKit
import Combine
import QuickLookThumbnailing
import UniformTypeIdentifiers
import DicteeCore

// La Bibliothèque (maquette design/maquettes/ilot-bibliotheque.html, étapes 1 à 6) : tout ce qui est passé par l'étagère, plus, au choix,
// les fichiers téléchargés, reçus par AirDrop et les captures d'écran. Le même modèle sert à la carte de l'îlot (BibliothequeCarte.swift)
// et à l'onglet de la fenêtre (BibliothequeFenetre.swift). La logique pure est dans DicteeCore/BibliothequeIlot.swift.
// Confidentialité : la bibliothèque garde des signets et des chemins, JAMAIS une copie ; son fichier est en 0600 dans Application Support,
// rien ne quitte le Mac ; le journal ne note que des nombres, jamais un nom de fichier. Les dossiers des sources (Téléchargements, Bureau)
// ne sont lus qu'une fois la source allumée d'un clic (macOS demande alors l'accès, une seule fois), jamais au lancement.

/// La bibliothèque, gardée localement : ~/Library/Application Support/Dictee/bibliotheque.json (0600). `url` nil : en mémoire seulement
/// (essais, rendus), rien n'est écrit.
struct BibliothequeStore {
    var url: URL?
    static var urlParDefaut: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Dictee", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("bibliotheque.json")
    }
    static let enMemoire = BibliothequeStore(url: nil)
    var existe: Bool { url.map { FileManager.default.fileExists(atPath: $0.path) } ?? false }
    func lire() -> BibliothequeIlot {
        guard let url, let d = try? Data(contentsOf: url) else { return BibliothequeIlot() }
        if let b = BibliothequeIlot.depuis(d) { return b }
        Log.ecrire("bibliothèque : fichier illisible, l'ancien est gardé en .abime")
        try? FileManager.default.moveItem(at: url, to: url.appendingPathExtension("abime"))
        return BibliothequeIlot()
    }
    func ecrire(_ b: BibliothequeIlot) {
        guard let url, let d = b.donnees() else { return }
        try? d.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

/// Les dossiers que les sources lisent (injectables : les essais donnent des dossiers temporaires, jamais les vrais).
struct DossiersBibliotheque {
    var telechargements: URL
    var captures: URL
    static var parDefaut: DossiersBibliotheque {
        let maison = FileManager.default.homeDirectoryForCurrentUser
        // là où macOS range les captures (Réglages de Capture d'écran › Options) ; par défaut, le Bureau
        let reglage = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location").map { ($0 as NSString).expandingTildeInPath }
        let captures = reglage.flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) } ?? maison.appendingPathComponent("Desktop", isDirectory: true)
        return DossiersBibliotheque(telechargements: maison.appendingPathComponent("Downloads", isDirectory: true), captures: captures)
    }
}

/// Les sources, lues sur une file à part : une simple liste du dossier (sans sous-dossiers), les plus récents d'abord, 200 au plus par
/// source. Aucune surveillance permanente : on relit à l'ouverture de la carte ou de l'onglet.
enum SourcesBibliotheque {
    static let parSource = 200

    nonisolated static func lire(_ sources: Set<SourceBibliotheque>, dossiers: DossiersBibliotheque) -> [EntreeBibliotheque] {
        var parCle: [String: EntreeBibliotheque] = [:]
        if sources.contains(.telecharges) || sources.contains(.airdrop) {
            for (url, date, taille) in liste(dossiers.telechargements) {
                let airdrop = FichierTelecharge.estAirDrop(quarantaine: quarantaine(url))
                let s: SourceBibliotheque = airdrop ? .airdrop : .telecharges
                guard sources.contains(s) else { continue }
                let e = EntreeBibliotheque(chemin: SignetsEtagere.cheminReel(url), source: s, date: date, taille: taille)
                parCle[e.cle] = e
            }
        }
        if sources.contains(.captures) {
            for (url, date, taille) in liste(dossiers.captures) where SorteFichier.estNomDeCapture(url.lastPathComponent) {
                let e = EntreeBibliotheque(chemin: SignetsEtagere.cheminReel(url), source: .captures, date: date, taille: taille)
                guard e.sorte == .capture else { continue }
                parCle[e.cle] = e
            }
        }
        // les plus récents d'abord, 200 par source au plus
        var compte: [SourceBibliotheque: Int] = [:]
        return parCle.values.sorted { $0.date > $1.date }.filter { e in
            let n = compte[e.source, default: 0]; compte[e.source] = n + 1; return n < parSource
        }
    }

    /// Les fichiers finis d'un dossier (ni cachés, ni en cours de téléchargement, ni sous-dossiers ; un paquet compte comme un fichier),
    /// avec la date d'arrivée dans le dossier et la taille.
    nonisolated static func liste(_ dossier: URL) -> [(URL, Date, Int64?)] {
        let cles: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .addedToDirectoryDateKey, .creationDateKey, .fileSizeKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: dossier, includingPropertiesForKeys: cles, options: [.skipsHiddenFiles]) else { return [] }
        return urls.compactMap { u in
            guard FiltreTelechargements.estFini(u.lastPathComponent), let v = try? u.resourceValues(forKeys: Set(cles)) else { return nil }
            if v.isDirectory == true, v.isPackage != true { return nil }
            let date = v.addedToDirectoryDate ?? v.creationDate ?? .distantPast
            return (u, date, v.isDirectory == true ? nil : v.fileSize.map(Int64.init))
        }
    }

    /// L'attribut de quarantaine (« 0081;6731f2a0;sharingd;… ») : sharingd = AirDrop.
    nonisolated static func quarantaine(_ url: URL) -> String? {
        let nom = "com.apple.quarantine"
        let n = getxattr(url.path, nom, nil, 0, 0, 0)
        guard n > 0 else { return nil }
        var tampon = [UInt8](repeating: 0, count: n)
        guard getxattr(url.path, nom, &tampon, n, 0, 0) == n else { return nil }
        return String(decoding: tampon, as: UTF8.self)
    }
}

/// La bibliothèque vivante : ce qu'elle garde (fichier), ce que les sources allumées ont trouvé, les icônes et vignettes (lues hors du fil
/// principal, une fois par fichier). L'îlot et la fenêtre l'observent.
@MainActor
final class BibliothequeModele: ObservableObject {
    private(set) var store: BibliothequeStore
    @Published private(set) var bib: BibliothequeIlot
    /// Ce que les sources allumées ont trouvé à la dernière lecture.
    @Published private(set) var trouves: [EntreeBibliotheque] = []
    /// Les sources optionnelles allumées (Téléchargés, AirDrop, Captures).
    @Published private(set) var sources: Set<SourceBibliotheque>
    /// Change à chaque changement de contenu (les vues gardent leur mise en page tant qu'il ne bouge pas).
    @Published private(set) var version = 0
    /// Le nombre de fichiers sur l'étagère aujourd'hui (« 10 fichiers · 4 sur l'étagère »), donné par le contrôleur.
    @Published var surEtagere = 0

    var maintenant: () -> Date = { Date() }
    var dossiers: DossiersBibliotheque = .parDefaut
    var reglerSources: (Set<SourceBibliotheque>) -> Void = { Settings.bibliothequeSources = $0 }
    /// Relit un signet (hors du fil principal) : le même que l'étagère (un disque débranché n'efface rien).
    nonisolated(unsafe) var resoudre: @Sendable (EntreeBibliotheque) -> SignetRelu = { e in
        guard let s = e.signet else { return FileManager.default.fileExists(atPath: e.chemin) || SignetsEtagere.volumeAbsent(e.chemin) != nil ? .present(chemin: e.chemin, signet: nil) : .disparu }
        return SignetsEtagere.relire(ElementEtagere(chemin: e.chemin, signet: s, ajout: e.date))
    }
    /// La lecture des dossiers des sources (hors du fil principal ; les essais l'enveloppent pour dater leurs fichiers).
    nonisolated(unsafe) var lireDossiers: @Sendable (Set<SourceBibliotheque>, DossiersBibliotheque) -> [EntreeBibliotheque] = { SourcesBibliotheque.lire($0, dossiers: $1) }
    /// Les icônes et vignettes : lues sur le disque (désactivé dans les rendus, qui donnent les leurs).
    var lireImages = true

    private var icones: [String: NSImage] = [:]
    private var vignettes: [String: NSImage] = [:]
    private var demandes = Set<String>()
    private var relecture: (enCours: Bool, encore: Bool, derniere: Date) = (false, false, .distantPast)
    private var apres: [() -> Void] = []

    init(store: BibliothequeStore = BibliothequeStore(url: BibliothequeStore.urlParDefaut), sources: Set<SourceBibliotheque> = Settings.bibliothequeSources) {
        self.store = store
        bib = store.lire()
        self.sources = sources
    }
    /// En mémoire (essais, rendus) : rien n'est écrit, aucune source n'est lue.
    convenience init(enMemoire entrees: [EntreeBibliotheque], trouves: [EntreeBibliotheque] = [], sources: Set<SourceBibliotheque> = []) {
        self.init(store: .enMemoire, sources: sources)
        bib = BibliothequeIlot(entrees: entrees)
        self.trouves = trouves
    }

    // MARK: ce qu'on montre

    /// Tout ce que la bibliothèque montre : ce qu'elle garde, puis ce que les sources allumées ont trouvé.
    var tout: [EntreeBibliotheque] { bib.fusion(trouves.filter { sources.contains($0.source) }) }
    func entree(_ id: String) -> EntreeBibliotheque? { tout.first { $0.id == id } }

    /// L'icône d'un fichier : une vignette pour les images et les captures, l'icône du Finder sinon (en attendant : celle du type).
    func icone(_ e: EntreeBibliotheque) -> NSImage {
        if let i = icones[e.id] { return i }
        charger(e, cote: 64, vers: \.icones, vignette: e.sorte == .image || e.sorte == .capture)
        return SignetsEtagere.iconeDuType(e.chemin)
    }
    /// La vignette QuickLook de l'onglet de la fenêtre (128 × 88 pt) ; en attendant, l'icône.
    func vignette(_ e: EntreeBibliotheque) -> NSImage? {
        if let v = vignettes[e.id] { return v }
        charger(e, cote: 256, vers: \.vignettes, vignette: true)
        return nil
    }
    /// Les rendus donnent leurs images (aucune lecture du disque).
    func poserImage(_ i: NSImage, pour id: String, vignette: Bool = false) {
        if vignette { vignettes[id] = i } else { icones[id] = i }
    }

    private func charger(_ e: EntreeBibliotheque, cote: CGFloat, vers cle: ReferenceWritableKeyPath<BibliothequeModele, [String: NSImage]>, vignette: Bool) {
        let marque = "\(cote):\(e.id)"
        guard lireImages, !demandes.contains(marque), SignetsEtagere.volumeAbsent(e.chemin) == nil else { return }
        demandes.insert(marque)
        let id = e.id, url = URL(fileURLWithPath: e.chemin)
        let poser: @Sendable (NSImage?) -> Void = { [weak self] image in
            DispatchQueue.main.async { MainActor.assumeIsolated {
                guard let self, let image else { return }
                self[keyPath: cle][id] = image
                self.version += 1
            } }
        }
        guard vignette else {
            DispatchQueue.global(qos: .utility).async { poser(SignetsEtagere.icone(url.path)) }
            return
        }
        let q = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: cote, height: cote), scale: 2, representationTypes: .all)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: q) { rep, _ in
            if let rep { poser(rep.nsImage) } else { poser(SignetsEtagere.icone(url.path)) }
        }
    }

    /// Le dossier où le fichier reste (« Téléchargements », « Bureau ») : pour « Retiré d'ici. Le fichier reste dans … ».
    func dossier(_ e: EntreeBibliotheque) -> String {
        let parent = (e.chemin as NSString).deletingLastPathComponent
        return FileManager.default.displayName(atPath: parent)
    }

    // MARK: ce qui change

    private func change(sauver: Bool = true) {
        version += 1
        if sauver { store.ecrire(bib) }
    }

    /// Essais seulement : repartir d'une bibliothèque donnée (dans le dossier temporaire de l'essai).
    func remplacer(_ b: BibliothequeIlot) { bib = b; trouves = []; icones = [:]; vignettes = [:]; demandes = []; change() }

    /// L'étagère vient de recevoir des fichiers : la bibliothèque les garde (même signet). `tailles` : lire leur taille (les fichiers
    /// viennent d'être lâchés, donc accessibles) ; jamais au lancement (aucun accès au disque sans geste).
    func noterEtagere(_ elements: [ElementEtagere], tailles: Bool = true) {
        guard !elements.isEmpty else { return }
        let nouvelles = elements.map { e -> EntreeBibliotheque in
            let t = tailles ? (try? FileManager.default.attributesOfItem(atPath: e.chemin)[.size] as? NSNumber)?.int64Value : nil
            return EntreeBibliotheque(etagere: e, taille: t)
        }
        let sortis = bib.noter(nouvelles)
        for s in sortis { icones[s.id] = nil; vignettes[s.id] = nil }
        change()
        Log.ecrire("bibliothèque : \(nouvelles.count) noté(s) depuis l'étagère, \(sortis.count) sorti(s) (plafond)")
    }

    /// Première ouverture : la bibliothèque n'a jamais été écrite, elle reprend ce qui est déjà sur l'étagère.
    func reprendreEtagere(_ elements: [ElementEtagere]) {
        guard store.url != nil, !store.existe, bib.estVide, !elements.isEmpty else { return }
        noterEtagere(elements, tailles: false)
    }

    /// Un fichier venu d'une source et épinglé devient une entrée gardée : il reçoit un signet (il suivra le fichier déplacé).
    func epingler(_ e: EntreeBibliotheque, _ oui: Bool) {
        var x = e
        if oui, x.signet == nil, store.url != nil {
            x.signet = try? URL(fileURLWithPath: x.chemin).bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        }
        bib.epingler(x, oui); change()
    }
    @discardableResult
    func retirer(_ e: EntreeBibliotheque) -> RetraitBibliotheque {
        let r = bib.retirer(e); change()
        return r
    }
    func annuler(_ r: RetraitBibliotheque) { bib.annuler(r); change() }

    /// Allume ou éteint une source (interrupteur de la fenêtre). Allumée, son dossier est lu tout de suite : c'est à ce clic, et à lui
    /// seul, que macOS pose sa question d'accès (une fois).
    func allumer(_ s: SourceBibliotheque, _ oui: Bool) {
        guard s != .etagere else { return }
        if oui { sources.insert(s) } else { sources.remove(s) }
        reglerSources(sources)
        version += 1
        Log.ecrire("bibliothèque : source \(s.rawValue) \(oui ? "allumée" : "éteinte")")
        if oui { rafraichir(force: true) }
    }

    /// Relit les signets (un fichier déplacé suit, un fichier supprimé s'en va) et les dossiers des sources allumées, sur une file à part ;
    /// puis applique le résultat ici. Pas plus d'une relecture toutes les 5 s sans `force` ; une seule à la fois.
    func rafraichir(force: Bool = false, puis: (() -> Void)? = nil) {
        if let puis { apres.append(puis) }
        // en mémoire (rendus) : rien à relire, aucun dossier à lire
        guard store.url != nil else { fini(); return }
        if relecture.enCours { relecture.encore = relecture.encore || force; return }
        let t = Date()
        guard force || t.timeIntervalSince(relecture.derniere) >= 5 else { fini(); return }
        relecture = (true, false, t)
        let gardees = bib.entrees, sources = self.sources, dossiers = self.dossiers, resoudre = self.resoudre, lireDossiers = self.lireDossiers
        DispatchQueue.global(qos: .userInitiated).async {
            var relus: [String: SignetRelu] = [:], tailles: [String: Int64] = [:]
            for e in gardees {
                let r = resoudre(e)
                relus[e.id] = r
                if e.taille == nil, case .present(let chemin, _) = r, SignetsEtagere.volumeAbsent(chemin) == nil,
                   let t = (try? FileManager.default.attributesOfItem(atPath: chemin)[.size] as? NSNumber)?.int64Value { tailles[e.id] = t }
            }
            let trouves = lireDossiers(sources, dossiers)
            let r = (relus, trouves, tailles)
            DispatchQueue.main.async { MainActor.assumeIsolated { self.appliquer(r.0, trouves: r.1, tailles: r.2) } }
        }
    }

    private func appliquer(_ relus: [String: SignetRelu], trouves t: [EntreeBibliotheque]?, tailles: [String: Int64]) {
        let avant = bib
        let retires = bib.relire { relus[$0.id] ?? .present(chemin: $0.chemin, signet: nil) }
        bib.poserTailles(tailles)
        for e in retires { icones[e.id] = nil; vignettes[e.id] = nil }
        if let t { trouves = t }
        change(sauver: bib != avant)
        if !retires.isEmpty { Log.ecrire("bibliothèque : \(retires.count) fichier(s) disparu(s), retiré(s)") }
        let encore = relecture.encore
        relecture.enCours = false
        if encore { rafraichir(force: true) } else { fini() }
    }
    private func fini() { let l = apres; apres = []; l.forEach { $0() } }
}
