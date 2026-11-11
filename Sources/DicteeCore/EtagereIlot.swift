import Foundation

// « L'étagère » (maquette design/maquettes/ilot-apple.html, cinq idées de plus, 2) : on glisse des fichiers sur l'encoche, ils y restent ;
// on les reprend plus tard en les glissant hors de l'îlot. Logique pure : ce qu'on garde (un signet par fichier, jamais une copie), sans
// doublon, ce qui a disparu, et quand le glisser est assez près de l'encoche pour que l'îlot s'ouvre en « Déposez ici ».

/// Un fichier posé sur l'étagère : un signet (le Mac retrouve le fichier même déplacé ou renommé), son nom et son dernier chemin connu.
/// Rien n'est copié : si le fichier est supprimé, il quitte l'étagère.
public struct ElementEtagere: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var nom: String
    public var chemin: String
    public var signet: Data
    public var ajout: Date
    public init(id: UUID = UUID(), chemin: String, signet: Data, ajout: Date) {
        self.id = id; self.chemin = chemin; self.signet = signet; self.ajout = ajout
        nom = (chemin as NSString).lastPathComponent
    }
}

/// Ce que dit un signet relu : le fichier est encore là (peut-être ailleurs, avec un signet renouvelé), ou il a disparu.
public enum SignetRelu: Equatable, Sendable {
    case present(chemin: String, signet: Data?)
    case disparu
}

/// Ce qu'un dépôt a changé : les fichiers rangés, ceux déjà sur l'étagère, et les plus anciens sortis pour faire de la place.
public struct RangementEtagere: Equatable, Sendable {
    public var ajoutes: [ElementEtagere] = []
    public var doublons = 0
    public var sortis: [ElementEtagere] = []
}

public struct EtagereIlot: Codable, Equatable, Sendable {
    /// Deux rangées de cinq dans la carte : au-delà, les plus anciens laissent leur place (ce ne sont que des signets, le fichier reste).
    public static let capacite = 10
    public private(set) var elements: [ElementEtagere] = []
    public init(elements: [ElementEtagere] = []) { self.elements = elements }

    public var estVide: Bool { elements.isEmpty }
    /// Cinq tuiles par rangée dans la carte, deux rangées au plus.
    public static let parRangee = 5
    public static func rangees(_ n: Int) -> Int { max(1, min(2, (n + parRangee - 1) / parRangee)) }

    /// Un fichier est le même s'il a le même chemin (chemins réels, sans « .. » ni « / » final).
    static func cle(_ chemin: String) -> String { (chemin as NSString).standardizingPath }

    /// Range des fichiers, dans l'ordre du dépôt, à la suite des autres. Un fichier déjà là (ou deux fois dans le même dépôt) n'est pas
    /// rangé deux fois et garde sa place. Au-delà de la capacité, les plus anciens sortent.
    @discardableResult
    public mutating func ajouter(_ nouveaux: [ElementEtagere]) -> RangementEtagere {
        var r = RangementEtagere()
        var vus = Set(elements.map { Self.cle($0.chemin) })
        for e in nouveaux {
            let k = Self.cle(e.chemin)
            if vus.contains(k) { r.doublons += 1; continue }
            vus.insert(k)
            elements.append(e); r.ajoutes.append(e)
        }
        if elements.count > Self.capacite {
            let n = elements.count - Self.capacite
            r.sortis = Array(elements.prefix(n))
            elements.removeFirst(n)
        }
        return r
    }

    @discardableResult
    public mutating func retirer(_ id: UUID) -> Bool {
        guard let i = elements.firstIndex(where: { $0.id == id }) else { return false }
        elements.remove(at: i)
        return true
    }

    public mutating func vider() { elements = [] }

    /// Des fichiers glissés HORS de l'étagère (vers Mail, le Bureau…) la quittent : on les retire et on les rend, dans l'ordre de
    /// l'étagère, pour pouvoir les « Remettre » quelques secondes.
    @discardableResult
    public mutating func retirer(ids: [UUID]) -> [ElementEtagere] {
        let l = Set(ids)
        let partis = elements.filter { l.contains($0.id) }
        elements.removeAll { l.contains($0.id) }
        return partis
    }

    /// « Remettre » : les fichiers partis reviennent (à la suite, sans doublon : un fichier redéposé entre-temps n'est pas compté deux
    /// fois ; mêmes signets, même identifiant).
    @discardableResult
    public mutating func remettre(_ partis: [ElementEtagere]) -> RangementEtagere { ajouter(partis) }

    /// « 1 fichier parti dans Mail », « 3 fichiers partis dans Mail » ; sans app connue : « 3 fichiers partis ».
    public static func partis(_ n: Int, app: String?) -> String {
        let debut = n == 1 ? "1 fichier parti" : "\(n) fichiers partis"
        guard let app, !app.isEmpty else { return debut }
        return debut + " dans " + app
    }

    /// Un fichier mis à la Corbeille n'est plus là pour l'utilisateur, même si son signet le retrouve encore.
    public static func estALaCorbeille(_ chemin: String) -> Bool {
        chemin.contains("/.Trash/") || chemin.contains("/.Trashes/")
    }

    /// Relit chaque signet : un fichier déplacé ou renommé suit (nouveau chemin, nouveau nom, signet renouvelé s'il était périmé) ; un
    /// fichier supprimé ou mis à la Corbeille quitte l'étagère. Deux signets qui mènent au même fichier n'en font plus qu'un.
    /// Rend les fichiers retirés.
    @discardableResult
    public mutating func relire(_ resoudre: (ElementEtagere) -> SignetRelu) -> [ElementEtagere] {
        var gardes: [ElementEtagere] = [], retires: [ElementEtagere] = []
        var vus = Set<String>()
        for var e in elements {
            switch resoudre(e) {
            case .disparu:
                retires.append(e)
            case .present(let chemin, let signet):
                if Self.estALaCorbeille(chemin) { retires.append(e); continue }
                let k = Self.cle(chemin)
                if vus.contains(k) { retires.append(e); continue }
                vus.insert(k)
                if chemin != e.chemin { e.chemin = chemin; e.nom = (chemin as NSString).lastPathComponent }
                if let signet { e.signet = signet }
                gardes.append(e)
            }
        }
        elements = gardes
        return retires
    }

    /// « 1 fichier », « 2 fichiers » ; « Vide ».
    public var resume: String { Self.resume(elements.count) }
    public static func resume(_ n: Int) -> String { n == 0 ? "Vide" : (n == 1 ? "1 fichier" : "\(n) fichiers") }
    /// Les noms, du plus récent au plus ancien (« Photo.heic, Contrat.pdf »), pour la ligne de l'accueil.
    public var apercu: String { elements.reversed().map(\.nom).joined(separator: ", ") }

    // MARK: fichier

    public func donnees() -> Data? {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return try? e.encode(self)
    }
    public static func depuis(_ d: Data) -> EtagereIlot? {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(EtagereIlot.self, from: d)
    }
}

/// Le pointeur qui glisse des fichiers est-il assez près de l'encoche pour que l'îlot s'ouvre en grand (les deux zones) ? Points depuis
/// le centre de l'encoche (x) et le haut de l'écran (y). Plus loin, l'îlot appelle seulement (« Glisse ici ») dès que le glisser commence.
public enum ApprocheEtagere {
    /// À 140 pt de l'encoche (la caméra sur la hauteur de la barre), l'îlot s'ouvre en grand (maquette ilot-etagere-rapide.html : bien
    /// avant d'atteindre l'encoche ; c'était 60 pt, il fallait viser).
    public static let distance: Double = 140
    /// Une fois ouvert, il le reste tant que le pointeur est sur la forme ouverte ou à 40 pt autour (la forme elle-même, pas son
    /// rectangle : voir `IlotMoteur.contient(_:marge:)`) : on ne la perd pas en la visant.
    public static let marge: Double = 40

    /// Distance du point à l'encoche (0 dessus).
    public static func ecart(x: Double, y: Double, demiCamera: Double, barre: Double) -> Double {
        let dx = max(0, abs(x) - demiCamera), dy = max(0, y - barre)
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Dans la barre des menus, seulement à 60 pt de la caméra : plus loin, ce sont les icônes des autres apps (on peut y glisser un
    /// fichier sans que l'îlot ne s'ouvre par-dessus).
    public static let distanceBarre: Double = 60

    /// Assez près de l'encoche pour que la zone s'ouvre.
    public static func proche(x: Double, y: Double, demiCamera: Double, barre: Double) -> Bool {
        if y < barre { return max(0, abs(x) - demiCamera) <= distanceBarre }
        return ecart(x: x, y: y, demiCamera: demiCamera, barre: barre) <= distance
    }
}

/// Les deux zones de dépôt, côte à côte sous l'encoche : « Étagère » (à gauche : la garder pour plus tard) et « AirDrop » (à droite :
/// l'envoyer). Celle sous le pointeur s'éclaire ; le lâcher va à celle-là.
public enum ZoneDepotEtagere: String, Equatable, Sendable {
    case etagere, airdrop
    /// La zone sous le pointeur (x depuis le centre de l'encoche, y depuis le haut de l'écran) : la gauche est l'étagère, la droite
    /// AirDrop. Encore dans la barre des menus (sur le cou, au-dessus des zones) : l'étagère, qu'on peut toujours défaire.
    public static func sous(x: Double, y: Double, barre: Double) -> ZoneDepotEtagere { y < barre || x < 0 ? .etagere : .airdrop }
}

/// En option (« Captures d'écran ici », éteint par défaut) : les nouvelles captures d'écran arrivent sur l'étagère. Où macOS les range,
/// et comment les reconnaître.
public enum CapturesEcran {
    /// Les débuts de nom des captures de macOS (français, anglais), quand le réglage « name » de com.apple.screencapture n'en donne pas.
    public static let prefixes = ["Capture d\u{2019}écran", "Capture d'écran", "Screenshot", "Screen Shot"]

    /// Le dossier des captures : le réglage « location » de com.apple.screencapture (« ~/Documents/ »), sinon le Bureau. `maison` : le
    /// dossier de l'utilisateur.
    public static func dossier(location: String?, maison: String) -> String {
        let bureau = (maison as NSString).appendingPathComponent("Desktop")
        guard var l = location?.trimmingCharacters(in: .whitespacesAndNewlines), !l.isEmpty else { return bureau }
        if l == "~" { l = maison } else if l.hasPrefix("~/") { l = (maison as NSString).appendingPathComponent(String(l.dropFirst(2))) }
        guard l.hasPrefix("/") else { return bureau }
        return (l as NSString).standardizingPath
    }

    /// Une capture d'écran : macOS la marque (attribut kMDItemIsScreenCapture), ou son nom commence comme celui des captures (le préfixe
    /// choisi dans les réglages, sinon ceux de macOS). Un autre fichier posé dans le même dossier (le Bureau) n'est jamais pris.
    public static func estUneCapture(nom: String, marquee: Bool, prefixe: String? = nil) -> Bool {
        guard FiltreTelechargements.estFini(nom) else { return false }
        if marquee { return true }
        let p = [prefixe].compactMap { $0 }.filter { !$0.isEmpty } + prefixes
        return p.contains { nom.hasPrefix($0) }
    }
}

/// Un glisser de FICHIERS vient-il de commencer ? Le presse-papiers du glisser (NSPasteboard « drag ») garde le dernier contenu glissé :
/// une sélection de texte qu'on étire ou une fenêtre qu'on déplace le trouveraient encore plein des fichiers d'avant. Un glisser est
/// nouveau seulement si ce presse-papiers a changé depuis que le bouton s'est enfoncé.
public struct SuiviGlisser: Equatable, Sendable {
    public private(set) var compteAuClic: Int?
    public init() {}
    /// Le bouton s'enfonce (on note le compteur du presse-papiers) ou remonte (on oublie).
    public mutating func bouton(enfonce: Bool, compte: Int) { compteAuClic = enfonce ? compte : nil }
    /// Le presse-papiers a changé depuis l'appui : quelque chose est vraiment en train d'être glissé. Sans appui vu, non.
    public func nouveau(compte: Int) -> Bool { compteAuClic.map { $0 != compte } ?? false }
}
