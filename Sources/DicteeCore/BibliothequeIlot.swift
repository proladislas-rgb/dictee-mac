import Foundation

// La Bibliothèque (maquette design/maquettes/ilot-bibliotheque.html, étapes 1 à 6) : tout ce qui est passé par l'étagère, plus, au choix,
// les fichiers téléchargés, reçus par AirDrop et les captures d'écran. L'étagère garde ses 10 fichiers récents ; la bibliothèque garde
// l'historique (500 au plus : les plus anciens non épinglés sortent). Rien n'est copié : Verbe garde seulement le chemin (et un signet,
// qui suit le fichier déplacé ou renommé). « Retirer » l'enlève de la bibliothèque seulement ; le fichier, lui, reste où il est.
// Logique pure, sans interface : ce qu'on garde, ce qu'on montre (filtres, recherche, tri, groupes par date), et la géométrie de la carte.

/// D'où vient un fichier de la bibliothèque.
public enum SourceBibliotheque: String, Codable, CaseIterable, Sendable {
    /// Posé un jour sur l'étagère (toujours montré).
    case etagere
    /// Dans le dossier Téléchargements (sans AirDrop).
    case telecharges
    /// Reçu par AirDrop (rangé par macOS dans Téléchargements).
    case airdrop
    /// Une capture d'écran, là où macOS les range.
    case captures

    /// Dans une ligne de la carte : « Étagère · 14:02 · 212 Ko ».
    public var libelle: String {
        switch self {
        case .etagere: return "Étagère"
        case .telecharges: return "Téléchargés"
        case .airdrop: return "Reçu par AirDrop"
        case .captures: return "Capture d\u{2019}écran"
        }
    }
    /// Dans « Ce que la bibliothèque montre » (fenêtre) : le nom de la source, et ce qu'elle couvre.
    public var titreReglage: String {
        switch self {
        case .etagere: return "Étagère"
        case .telecharges: return "Téléchargés"
        case .airdrop: return "Reçus par AirDrop"
        case .captures: return "Captures d\u{2019}écran"
        }
    }
    public var detailReglage: String {
        switch self {
        case .etagere: return "Tout ce que tu y as posé"
        case .telecharges: return "Dossier Téléchargements"
        case .airdrop: return "Depuis tes autres appareils"
        case .captures: return "Où qu\u{2019}elles soient rangées"
        }
    }
    /// Les sources qu'on allume ou non (l'étagère, elle, est toujours là).
    public static let optionnelles: [SourceBibliotheque] = [.telecharges, .airdrop, .captures]
}

/// La sorte d'un fichier, d'après son nom (et sa source) : jamais en l'ouvrant.
public enum SorteFichier: String, Codable, Sendable {
    case document, image, capture, autre

    static let extensionsImages: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "gif", "tif", "tiff", "bmp", "webp", "avif", "svg", "raw", "dng", "cr2", "cr3", "nef", "arw", "psd"]
    static let extensionsDocuments: Set<String> = ["pdf", "doc", "docx", "pages", "odt", "rtf", "rtfd", "txt", "md", "markdown", "xls", "xlsx", "numbers", "ods", "csv",
                                                   "ppt", "pptx", "key", "odp", "epub", "html", "htm", "json", "xml", "eml", "vcf", "ics"]

    public static func de(nom: String, source: SourceBibliotheque) -> SorteFichier {
        let ext = (nom as NSString).pathExtension.lowercased()
        if extensionsImages.contains(ext) { return source == .captures || estNomDeCapture(nom) ? .capture : .image }
        if extensionsDocuments.contains(ext) { return .document }
        return .autre
    }
    /// « Capture d’écran 2026-11-11 à 14.32.15.png », « Screenshot 2026-11-11 at 14.32.15.png » (macOS les nomme ainsi).
    public static func estNomDeCapture(_ nom: String) -> Bool {
        let n = nom.replacingOccurrences(of: "\u{2019}", with: "'").lowercased()
        return n.hasPrefix("capture d'écran") || n.hasPrefix("capture d'ecran") || n.hasPrefix("screenshot") || n.hasPrefix("screen shot")
    }
}

/// Les pastilles de filtre (maquette : Tout, Documents, Images, Captures, AirDrop, Téléchargés).
public enum FiltreBibliotheque: String, CaseIterable, Sendable {
    case tout, documents, images, captures, airdrop, telecharges

    public var titre: String {
        switch self {
        case .tout: return "Tout"
        case .documents: return "Documents"
        case .images: return "Images"
        case .captures: return "Captures"
        case .airdrop: return "AirDrop"
        case .telecharges: return "Téléchargés"
        }
    }
    /// Images : les photos ET les captures ; Captures : les captures seules ; AirDrop, Téléchargés : par source.
    public func accepte(_ e: EntreeBibliotheque) -> Bool {
        switch self {
        case .tout: return true
        case .documents: return e.sorte == .document
        case .images: return e.sorte == .image || e.sorte == .capture
        case .captures: return e.sorte == .capture
        case .airdrop: return e.source == .airdrop
        case .telecharges: return e.source == .telecharges
        }
    }
}

/// Un fichier de la bibliothèque : un chemin (et un signet pour ceux qu'on garde), jamais une copie.
public struct EntreeBibliotheque: Codable, Equatable, Sendable, Identifiable {
    /// Stable : un UUID pour ce que l'étagère a versé, le chemin pour ce qu'une source a trouvé (gardé s'il est épinglé ensuite).
    public var id: String
    public var nom: String
    public var chemin: String
    public var signet: Data?
    public var sorte: SorteFichier
    public var source: SourceBibliotheque
    /// Quand il est arrivé (posé sur l'étagère, téléchargé, capturé).
    public var date: Date
    public var taille: Int64?
    public var epinglee: Bool

    public init(id: String? = nil, chemin: String, signet: Data? = nil, source: SourceBibliotheque, date: Date, taille: Int64? = nil, epinglee: Bool = false) {
        self.id = id ?? chemin
        self.chemin = chemin; self.signet = signet; self.source = source; self.date = date; self.taille = taille; self.epinglee = epinglee
        nom = (chemin as NSString).lastPathComponent
        sorte = SorteFichier.de(nom: nom, source: source)
    }
    /// Un fichier posé sur l'étagère, tel que la bibliothèque le garde (même signet).
    public init(etagere e: ElementEtagere, taille: Int64? = nil) {
        self.init(id: e.id.uuidString, chemin: e.chemin, signet: e.signet, source: .etagere, date: e.ajout, taille: taille)
    }
    /// Un même fichier a toujours la même clé (chemins réels, sans « .. » ni « / » final).
    public var cle: String { BibliothequeIlot.cle(chemin) }

    mutating func suivre(_ nouveau: String) {
        chemin = nouveau
        nom = (nouveau as NSString).lastPathComponent
        sorte = SorteFichier.de(nom: nom, source: source)
    }
}

/// Ce que « Retirer » a fait, pour « Annuler » : l'entrée, sa place parmi celles qu'on garde (nil : elle venait d'une source).
public struct RetraitBibliotheque: Equatable, Sendable {
    public var entree: EntreeBibliotheque
    public var place: Int?
    public init(entree: EntreeBibliotheque, place: Int?) { self.entree = entree; self.place = place }
}

/// Un groupe de la liste : « Épinglés », puis « Aujourd'hui », « Hier », « Cette semaine », « La semaine dernière », « Plus tôt ce mois-ci »,
/// puis les mois (« Octobre », « Septembre 2025 »).
public struct GroupeBibliotheque: Equatable, Sendable {
    public var titre: String
    public var epingles: Bool
    public var entrees: [EntreeBibliotheque]
}

public struct BibliothequeIlot: Codable, Equatable, Sendable {
    /// L'historique gardé : au-delà, les plus anciens non épinglés sortent (des signets seulement : les fichiers restent).
    public static let plafond = 500
    /// Les fichiers retirés d'ici qui venaient d'une source (ils ne reviennent pas à la prochaine lecture du dossier).
    public static let plafondMasques = 2000

    /// Ce que la bibliothèque garde elle-même : ce que l'étagère a versé, et ce qu'on a épinglé.
    public private(set) var entrees: [EntreeBibliotheque] = []
    /// Les clés des fichiers retirés d'ici (sources comprises), du plus ancien au plus récent.
    public private(set) var masques: [String] = []

    public init(entrees: [EntreeBibliotheque] = [], masques: [String] = []) { self.entrees = entrees; self.masques = masques }

    public var estVide: Bool { entrees.isEmpty }
    static func cle(_ chemin: String) -> String { (chemin as NSString).standardizingPath }

    /// Range ce que l'étagère vient de recevoir. Un fichier déjà gardé revient en tête (sa date devient celle du dépôt) ; un fichier retiré
    /// d'ici puis reposé sur l'étagère reparaît. Rend les entrées sorties pour faire de la place.
    @discardableResult
    public mutating func noter(_ nouvelles: [EntreeBibliotheque]) -> [EntreeBibliotheque] {
        for n in nouvelles {
            let k = n.cle
            masques.removeAll { $0 == k }
            if let i = entrees.firstIndex(where: { $0.cle == k }) {
                entrees[i].date = max(entrees[i].date, n.date)
                if n.signet != nil { entrees[i].signet = n.signet }
                if let t = n.taille { entrees[i].taille = t }
            } else {
                entrees.append(n)
            }
        }
        return limiter()
    }

    /// Au-delà du plafond, les plus anciens non épinglés sortent.
    private mutating func limiter() -> [EntreeBibliotheque] {
        guard entrees.count > Self.plafond else { return [] }
        let enTrop = entrees.count - Self.plafond
        let sortants = entrees.enumerated().filter { !$0.element.epinglee }.sorted { $0.element.date < $1.element.date }.prefix(enTrop)
        let ids = Set(sortants.map(\.element.id))
        let sortis = entrees.filter { ids.contains($0.id) }
        entrees.removeAll { ids.contains($0.id) }
        return sortis
    }

    /// Ce que la bibliothèque montre : ce qu'elle garde, puis ce que les sources ont trouvé (sauf ce qu'elle garde déjà ou ce qu'on a
    /// retiré d'ici).
    public func fusion(_ trouves: [EntreeBibliotheque]) -> [EntreeBibliotheque] {
        var vus = Set(entrees.map(\.cle))
        let caches = Set(masques)
        var r = entrees
        for e in trouves {
            let k = e.cle
            if vus.contains(k) || caches.contains(k) { continue }
            vus.insert(k); r.append(e)
        }
        return r
    }

    /// Épingle (ou détache) un fichier. Un fichier venu d'une source devient une entrée gardée (elle reste même si la source s'éteint).
    public mutating func epingler(_ e: EntreeBibliotheque, _ oui: Bool) {
        if let i = entrees.firstIndex(where: { $0.id == e.id || $0.cle == e.cle }) { entrees[i].epinglee = oui; return }
        guard oui else { return }
        var n = e; n.epinglee = true
        entrees.append(n)
    }

    /// « Retirer » : enlève le fichier de la bibliothèque SEULEMENT (et des sources : il ne revient pas). Le fichier n'est pas touché.
    public mutating func retirer(_ e: EntreeBibliotheque) -> RetraitBibliotheque {
        let k = e.cle
        var place: Int?
        var gardee = e
        if let i = entrees.firstIndex(where: { $0.id == e.id || $0.cle == k }) { place = i; gardee = entrees.remove(at: i) }
        if !masques.contains(k) { masques.append(k) }
        if masques.count > Self.plafondMasques { masques.removeFirst(masques.count - Self.plafondMasques) }
        return RetraitBibliotheque(entree: gardee, place: place)
    }

    /// « Annuler » : le fichier retiré revient, à sa place.
    public mutating func annuler(_ r: RetraitBibliotheque) {
        let k = r.entree.cle
        masques.removeAll { $0 == k }
        guard let p = r.place, !entrees.contains(where: { $0.cle == k }) else { return }
        entrees.insert(r.entree, at: min(p, entrees.count))
    }

    /// Relit les signets : un fichier déplacé suit, un fichier supprimé ou à la Corbeille s'en va (un disque débranché n'efface rien :
    /// `resoudre` le dit présent). Rend les entrées retirées.
    @discardableResult
    public mutating func relire(_ resoudre: (EntreeBibliotheque) -> SignetRelu) -> [EntreeBibliotheque] {
        var gardes: [EntreeBibliotheque] = [], retires: [EntreeBibliotheque] = []
        var vus = Set<String>()
        for var e in entrees {
            switch resoudre(e) {
            case .disparu: retires.append(e)
            case .present(let chemin, let signet):
                if EtagereIlot.estALaCorbeille(chemin) { retires.append(e); continue }
                let k = Self.cle(chemin)
                if vus.contains(k) { retires.append(e); continue }
                vus.insert(k)
                if chemin != e.chemin { e.suivre(chemin) }
                if let signet { e.signet = signet }
                gardes.append(e)
            }
        }
        entrees = gardes
        return retires
    }

    /// Les tailles lues après coup (une entrée reprise de l'étagère au premier lancement n'en avait pas : rien n'est lu au lancement).
    public mutating func poserTailles(_ t: [String: Int64]) {
        for i in entrees.indices where entrees[i].taille == nil { if let x = t[entrees[i].id] { entrees[i].taille = x } }
    }

    // MARK: ce qu'on montre

    /// Les fichiers qui passent le filtre et dont le nom contient tous les mots de la recherche (sans accents ni majuscules, comme les
    /// dictées).
    public static func filtrer(_ l: [EntreeBibliotheque], filtre: FiltreBibliotheque, requete: String) -> [EntreeBibliotheque] {
        let mots = Historique.plier(requete).split(whereSeparator: { $0.isWhitespace }).map(String.init)
        return l.filter { e in
            guard filtre.accepte(e) else { return false }
            guard !mots.isEmpty else { return true }
            let n = Historique.plier(e.nom)
            return mots.allSatisfy { n.contains($0) }
        }
    }

    /// Du plus récent au plus ancien (ou l'inverse), puis par nom.
    public static func trier(_ l: [EntreeBibliotheque], recents: Bool) -> [EntreeBibliotheque] {
        l.sorted { a, b in
            if a.date != b.date { return recents ? a.date > b.date : a.date < b.date }
            return a.nom.localizedStandardCompare(b.nom) == .orderedAscending
        }
    }

    /// Les épinglés en haut, puis les autres groupés par date (dans l'ordre du tri).
    public static func groupes(_ l: [EntreeBibliotheque], recents: Bool, maintenant: Date, calendrier: Calendar = .current) -> [GroupeBibliotheque] {
        var r: [GroupeBibliotheque] = []
        let ep = trier(l.filter(\.epinglee), recents: recents)
        if !ep.isEmpty { r.append(GroupeBibliotheque(titre: "Épinglés", epingles: true, entrees: ep)) }
        for e in trier(l.filter { !$0.epinglee }, recents: recents) {
            let t = tranche(e.date, maintenant: maintenant, calendrier: calendrier)
            if let d = r.last, !d.epingles, d.titre == t { r[r.count - 1].entrees.append(e) }
            else { r.append(GroupeBibliotheque(titre: t, epingles: false, entrees: [e])) }
        }
        return r
    }

    /// Le titre du groupe d'une date : « Aujourd'hui », « Hier », « Cette semaine », « La semaine dernière », « Plus tôt ce mois-ci »,
    /// puis le mois (« Octobre », avec l'année si ce n'est pas l'année en cours). Une date dans le futur (horloge) compte pour aujourd'hui.
    public static func tranche(_ d: Date, maintenant: Date, calendrier cal: Calendar = .current) -> String {
        if d >= maintenant || cal.isDate(d, inSameDayAs: maintenant) { return "Aujourd\u{2019}hui" }
        if let hier = cal.date(byAdding: .day, value: -1, to: maintenant), cal.isDate(d, inSameDayAs: hier) { return "Hier" }
        if let semaine = cal.dateInterval(of: .weekOfYear, for: maintenant) {
            if d >= semaine.start { return "Cette semaine" }
            if let avant = cal.date(byAdding: .day, value: -7, to: semaine.start), d >= avant { return "La semaine dernière" }
        }
        if cal.isDate(d, equalTo: maintenant, toGranularity: .month) { return "Plus tôt ce mois-ci" }
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.calendar = cal; f.timeZone = cal.timeZone
        f.dateFormat = cal.isDate(d, equalTo: maintenant, toGranularity: .year) ? "LLLL" : "LLLL yyyy"
        let s = f.string(from: d)
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    /// Quand, dans une ligne : « 14:32 » aujourd'hui, « hier 18:40 », « lun. 9 nov. » cette année, « 9 nov. 2025 » avant.
    public static func quand(_ d: Date, maintenant: Date, calendrier cal: Calendar = .current) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.calendar = cal; f.timeZone = cal.timeZone
        if d >= maintenant || cal.isDate(d, inSameDayAs: maintenant) { f.dateFormat = "HH:mm"; return f.string(from: d) }
        if let hier = cal.date(byAdding: .day, value: -1, to: maintenant), cal.isDate(d, inSameDayAs: hier) { f.dateFormat = "HH:mm"; return "hier " + f.string(from: d) }
        f.dateFormat = cal.isDate(d, equalTo: maintenant, toGranularity: .year) ? "EEE d MMM" : "d MMM yyyy"
        return f.string(from: d)
    }

    /// La ligne sous le nom : « Étagère · 14:02 · 212 Ko ».
    public static func detail(_ e: EntreeBibliotheque, maintenant: Date, calendrier: Calendar = .current) -> String {
        var l = [e.source.libelle, quand(e.date, maintenant: maintenant, calendrier: calendrier)]
        if let t = e.taille { l.append(FormatTaille.texte(t)) }
        return l.joined(separator: " \u{00B7} ")
    }

    /// Le pied après « Retirer » : « Retiré d'ici. Le fichier reste dans Téléchargements. »
    public static func messageRetrait(dossier: String) -> String { "Retiré d\u{2019}ici. Le fichier reste dans \(dossier)." }
    /// « 3 choisis », « 1 choisi ».
    public static func choisis(_ n: Int) -> String { n > 1 ? "\(n) choisis" : "\(n) choisi" }
    /// « 10 fichiers · 4 sur l'étagère ».
    public static func compte(_ n: Int, etagere: Int) -> String {
        let f = n == 0 ? "Aucun fichier" : (n == 1 ? "1 fichier" : "\(n) fichiers")
        return etagere > 0 ? f + " \u{00B7} \(etagere) sur l\u{2019}étagère" : f
    }

    // MARK: fichier

    public func donnees() -> Data? {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return try? e.encode(self)
    }
    public static func depuis(_ d: Data) -> BibliothequeIlot? {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(BibliothequeIlot.self, from: d)
    }
}

/// La carte « Bibliothèque » de l'îlot (maquette, étapes 2 à 5), en points : 14 de marge, l'en-tête (« ‹ Étagère », la recherche, le
/// tri : 30), 8, les pastilles (26), 6, la liste (164 au plus, elle défile au-delà), le pied (un filet, 4 + 30), 14. La carte épouse sa
/// liste : de ~176 pt sous la barre (« Aucun fichier ») à 296.
public enum CarteBibliotheque {
    public static let marge: Double = 14
    public static let entete: Double = 30
    public static let ecartPuces: Double = 8
    public static let puces: Double = 26
    public static let ecart: Double = 6
    public static let pied: Double = 4 + 30
    public static let listeMax: Double = 164
    /// Le titre d'un groupe (« Épinglés », « Aujourd'hui ») et une ligne (icône, nom, d'où il vient · date · taille).
    public static let titreGroupe: Double = 20
    public static let ligne: Double = 36
    /// « Aucun fichier ».
    public static let rien: Double = 42
    public static let profondeurMax = marge + entete + ecartPuces + puces + ecart + listeMax + pied + marge
    /// Le haut de la liste, depuis le haut de la zone de la carte.
    public static let hautListe = entete + ecartPuces + puces + ecart

    /// La hauteur de toute la liste (titres des groupes et lignes) ; vide : « Aucun fichier ».
    public static func hauteurListe(lignesParGroupe: [Int]) -> Double {
        let n = lignesParGroupe.reduce(0, +)
        guard n > 0 else { return rien }
        return Double(lignesParGroupe.filter { $0 > 0 }.count) * titreGroupe + Double(n) * ligne
    }
    /// La profondeur sous la barre pour une liste de `liste` points (bornée à `listeMax`, la liste défile au-delà).
    public static func profondeur(liste: Double) -> Double { marge + hautListe + min(max(0, liste), listeMax) + pied + marge }
    /// Le défilement de la liste, borné : 0 en haut, la hauteur cachée en bas.
    public static func borner(_ decalage: Double, liste: Double) -> Double { min(max(0, liste - listeMax), max(0, decalage)) }
}
