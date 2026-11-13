import Foundation

// La lecture en cours dans l'encoche : toute la logique pure (sans interface, sans processus, sans système).
// Le programme d'aide (Resources/lecture) écrit des lignes JSON ; ici on les lit, on calcule la position, la couleur
// de la pochette, le libellé de la source, qui a la priorité sur l'encoche et quand mettre en pause pendant une dictée.

// MARK: ce qui joue

/// Ce que MediaRemote dit être en cours de lecture. `position` est exacte à l'instant `depuis` ; ensuite elle avance toute seule
/// à la `vitesse` annoncée (0 = en pause) : l'interface calcule, rien n'interroge le système en boucle.
public struct MorceauEnCours: Equatable, Sendable {
    public var titre: String
    public var artiste: String?
    public var album: String?
    /// Identifiant de l'app qui joue (com.google.Chrome, com.spotify.client…).
    public var app: String?
    public var pid: Int?
    public var joue: Bool
    /// Durée en secondes ; nil pour un direct ou quand l'app ne la donne pas.
    public var duree: Double?
    public var position: Double?
    public var depuis: Date?
    public var vitesse: Double
    /// Fichier de l'image, déposé par le programme d'aide.
    public var cheminImage: String?

    public init(titre: String, artiste: String? = nil, album: String? = nil, app: String? = nil, pid: Int? = nil, joue: Bool,
                duree: Double? = nil, position: Double? = nil, depuis: Date? = nil, vitesse: Double = 1, cheminImage: String? = nil) {
        self.titre = titre; self.artiste = artiste; self.album = album; self.app = app; self.pid = pid; self.joue = joue
        self.duree = duree; self.position = position; self.depuis = depuis; self.vitesse = vitesse; self.cheminImage = cheminImage
    }

    /// Identité du morceau : change quand on passe à un autre titre, une autre app ou une autre durée (pas quand la position bouge).
    public var cle: String { "\(app ?? "")|\(titre)|\(artiste ?? "")|\(duree.map { String(Int($0)) } ?? "direct")" }

    /// Peut-on afficher une barre de progression et la glisser ? Pas pour un direct.
    public var positionnable: Bool { (duree ?? 0) > 0 && position != nil }

    /// Position à l'instant `date`, bornée à [0, durée].
    public func positionA(_ date: Date) -> Double? {
        guard let position else { return nil }
        var p = position
        if joue, let depuis { p += max(0, date.timeIntervalSince(depuis)) * (vitesse > 0 ? vitesse : 1) }
        p = max(0, p)
        if let duree, duree > 0 { p = min(p, duree) }
        return p
    }
}

public enum EvenementLecture: Equatable, Sendable {
    /// Le programme d'aide a démarré.
    case pret
    /// Plus rien ne joue.
    case rien
    /// MediaRemote est inaccessible (future version de macOS) : la fonction se désactive.
    case echec(String)
    case etat(MorceauEnCours)
}

public enum CommandeLecture: Equatable, Sendable {
    case lecture, pause, bascule, suivant, precedent
    case position(Double)
}

public enum AideLecture {
    /// Une ligne JSON du programme d'aide -> un événement. Une ligne illisible donne nil (ignorée).
    public static func decoder(_ ligne: String) -> EvenementLecture? {
        guard let donnees = ligne.data(using: .utf8),
              let o = (try? JSONSerialization.jsonObject(with: donnees)) as? [String: Any],
              let t = o["t"] as? String else { return nil }
        switch t {
        case "pret": return .pret
        case "rien": return .rien
        case "echec": return .echec(o["raison"] as? String ?? "inconnue")
        case "etat":
            func texte(_ cle: String) -> String? { (o[cle] as? String).flatMap { $0.isEmpty ? nil : $0 } }
            func nombre(_ cle: String) -> Double? { (o[cle] as? NSNumber).map(\.doubleValue).flatMap { $0.isFinite ? $0 : nil } }
            let titre = texte("titre") ?? ""
            let app = texte("app")
            guard !titre.isEmpty || app != nil else { return .rien }
            var m = MorceauEnCours(titre: titre, artiste: texte("artiste"), album: texte("album"), app: app,
                                   pid: (o["pid"] as? NSNumber)?.intValue, joue: (o["joue"] as? Bool) ?? false,
                                   duree: nombre("duree").flatMap { $0 > 0 ? $0 : nil }, position: nombre("pos"),
                                   depuis: nombre("depuis").map { Date(timeIntervalSince1970: $0) },
                                   vitesse: nombre("vitesse") ?? 1, cheminImage: texte("image"))
            if m.titre.isEmpty { m.titre = "Lecture en cours" }
            return .etat(m)
        default: return nil
        }
    }

    /// La commande à écrire sur l'entrée du programme d'aide (une ligne JSON, avec retour à la ligne).
    public static func ligne(_ c: CommandeLecture) -> String {
        switch c {
        case .lecture: return "{\"cmd\":\"play\"}\n"
        case .pause: return "{\"cmd\":\"pause\"}\n"
        case .bascule: return "{\"cmd\":\"toggle\"}\n"
        case .suivant: return "{\"cmd\":\"next\"}\n"
        case .precedent: return "{\"cmd\":\"prev\"}\n"
        case .position(let s): return "{\"cmd\":\"seek\",\"pos\":\(String(format: "%.3f", max(0, s)))}\n"
        }
    }
}

// MARK: temps et barre

public enum TempsLecture {
    /// « 1:37 », « 12:05 », « 1:02:03 ».
    public static func format(_ secondes: Double) -> String {
        let s = Int(max(0, secondes.isFinite ? secondes : 0).rounded(.down))
        let h = s / 3600, m = (s % 3600) / 60, r = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, r) : String(format: "%d:%02d", m, r)
    }

    /// « −1:57 » (vrai signe moins).
    public static func restant(position: Double, duree: Double) -> String { "\u{2212}" + format(max(0, duree - position)) }

    /// Position (secondes) -> fraction de la barre, bornée à 0…1.
    public static func fraction(position: Double, duree: Double) -> Double {
        guard duree > 0 else { return 0 }
        return min(1, max(0, position / duree))
    }

    /// Fraction de la barre (0…1, hors bornes tolérée) -> position en secondes.
    public static func position(fraction: Double, duree: Double) -> Double { min(1, max(0, fraction)) * max(0, duree) }

    /// Reculer ou avancer de `delta` secondes, sans sortir de [0, durée].
    public static func saut(position: Double, delta: Double, duree: Double?) -> Double {
        let p = max(0, position + delta)
        if let duree, duree > 0 { return min(p, duree) }
        return p
    }

    /// Fraction de la barre sous la souris : x dans [0, largeur].
    public static func fractionSousSouris(x: Double, largeur: Double) -> Double {
        guard largeur > 0 else { return 0 }
        return min(1, max(0, x / largeur))
    }
}

/// La trace sonore qui sert de barre de progression : 54 barres de hauteurs fixes (0,22…1), les mêmes à chaque fois.
public enum TraceSonore {
    public static let nombreDeBarres = 54
    public static func hauteurs(_ n: Int = nombreDeBarres) -> [Double] {
        (0..<n).map { i in
            let x = Double(i)
            let h = 0.22 + 0.78 * abs(sin(x * 1.7) * cos(x * 0.43) + 0.15 * sin(x * 5.1))
            return min(1, h)
        }
    }
    /// Nombre de barres teintées pour une fraction de progression (la dernière peut être entamée : on renvoie un réel).
    public static func barresTeintees(fraction: Double, n: Int = nombreDeBarres) -> Double { min(1, max(0, fraction)) * Double(n) }
}

// MARK: la source (« Chrome · YouTube »)

public enum GenreLecture: Equatable, Sendable {
    /// Pochette ronde qui tourne.
    case musique
    /// Pochette carrée arrondie.
    case video
}

public enum SourceLecture {
    private static let navigateurs: [String: String] = [
        "com.google.Chrome": "Chrome", "com.google.Chrome.canary": "Chrome Canary", "com.apple.Safari": "Safari", "org.mozilla.firefox": "Firefox",
        "company.thebrowser.Browser": "Arc", "com.brave.Browser": "Brave", "com.microsoft.edgemac": "Edge", "com.operasoftware.Opera": "Opera",
        "com.vivaldi.Vivaldi": "Vivaldi", "org.chromium.Chromium": "Chromium",
    ]
    private static let lecteursMusique: [String: String] = [
        "com.apple.Music": "Musique", "com.spotify.client": "Spotify", "com.tidal.desktop": "Tidal", "com.deezer.deezer-desktop": "Deezer",
        "com.qobuz.Qobuz": "Qobuz", "com.apple.iTunes": "iTunes", "com.coppertino.Vox": "Vox", "com.swinsian.Swinsian": "Swinsian",
    ]
    private static let autres: [String: String] = [
        "com.apple.podcasts": "Podcasts", "com.apple.TV": "TV", "org.videolan.vlc": "VLC", "com.apple.QuickTimePlayerX": "QuickTime Player",
        "io.mpv": "mpv", "com.colliderli.iina": "IINA", "com.apple.Safari.WebApp": "Safari",
    ]
    /// Sites de musique reconnus dans un navigateur.
    private static let sitesMusique: Set<String> = ["YouTube Music", "Spotify", "SoundCloud", "Deezer", "Apple Music", "Bandcamp", "Qobuz", "Tidal"]

    public static func estNavigateur(_ bundle: String?) -> Bool { bundle.map { navigateurs[$0] != nil } ?? false }

    /// Nom court de l'app : « Chrome » (sans « Google »), « Musique », « Spotify »… À défaut, le nom lisible donné par le système.
    public static func nomCourt(bundle: String?, nomApp: String?) -> String {
        if let bundle {
            if let n = navigateurs[bundle] ?? lecteursMusique[bundle] ?? autres[bundle] { return n }
        }
        var n = (nomApp ?? "").trimmingCharacters(in: .whitespaces)
        if n.hasPrefix("Google ") { n.removeFirst("Google ".count) }
        return n.isEmpty ? "Lecture" : n
    }

    /// « Chrome · YouTube » ; pour une app de musique « Spotify · Artiste » ; sinon le nom de l'app seul.
    /// Dans un navigateur, la deuxième partie est le site s'il est connu, sinon l'artiste ou la chaîne annoncé(e).
    public static func libelle(bundle: String?, nomApp: String?, artiste: String?, album: String?, site: String?) -> String {
        let nom = nomCourt(bundle: bundle, nomApp: nomApp)
        let complement: String?
        if estNavigateur(bundle) {
            complement = [site, artiste, album].compactMap { $0 }.first { !$0.isEmpty }
        } else {
            complement = [artiste, album].compactMap { $0 }.first { !$0.isEmpty }
        }
        guard let complement, !complement.isEmpty else { return nom }
        return "\(nom) \u{00B7} \(complement)"
    }

    /// Musique (pochette ronde qui tourne) ou vidéo (carrée arrondie).
    public static func genre(bundle: String?, album: String?, duree: Double?, site: String?) -> GenreLecture {
        if let bundle, lecteursMusique[bundle] != nil { return .musique }
        if let bundle, autres[bundle] != nil { return .video }
        if let site, sitesMusique.contains(site) { return .musique }
        if let album, !album.isEmpty, (duree ?? 0) <= 1200, !estNavigateur(bundle) || site != nil { return .musique }
        return .video
    }

    // MARK: site lu dans le titre des fenêtres du navigateur

    private static let sitesConnus: [String] = [
        "YouTube Music", "YouTube", "Netflix", "Prime Video", "Disney+", "Twitch", "Spotify", "SoundCloud", "Deezer", "Apple Music",
        "Vimeo", "Dailymotion", "Canal+", "Arte", "France.tv", "Bandcamp", "Max", "Crunchyroll", "Molotov", "Tidal",
    ]
    private static let suffixesNavigateur = ["Google Chrome", "Chrome", "Mozilla Firefox", "Firefox", "Brave", "Microsoft Edge", "Opera", "Vivaldi", "Arc", "Safari", "Chromium"]

    private static func normaliser(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            .replacingOccurrences(of: "\u{2019}", with: "'")
    }

    /// Retire de la fin d'un titre de fenêtre le nom du navigateur (« … - Google Chrome », « … — Mozilla Firefox », « … – Google Chrome – Hugues »).
    static func sansNavigateur(_ titre: String) -> String {
        var t = titre
        for separateur in [" - ", " \u{2014} ", " \u{2013} ", " | "] {
            let morceaux = t.components(separatedBy: separateur)
            guard morceaux.count > 1 else { continue }
            // le nom du navigateur peut être suivi du nom d'un profil : on coupe au dernier suffixe connu
            if let i = morceaux.lastIndex(where: { m in suffixesNavigateur.contains { m.trimmingCharacters(in: .whitespaces).hasPrefix($0) } }), i > 0 {
                t = morceaux[..<i].joined(separator: separateur)
            }
        }
        return t
    }

    /// Le titre d'une fenêtre de navigateur est-il celui du média qui joue (« (3) Titre - YouTube - Google Chrome » pour « Titre ») ?
    /// Compare les 18 premiers caractères du média, sans accents ni casse ; faux pour un titre de média trop court pour être sûr.
    public static func fenetreMontre(titreFenetre: String, titreMedia: String) -> Bool {
        let media = normaliser(titreMedia).trimmingCharacters(in: .whitespaces)
        guard media.count >= 6 else { return false }
        return normaliser(sansNavigateur(titreFenetre)).contains(String(media.prefix(18)))
    }

    /// Le site qui joue, d'après les titres des fenêtres du navigateur : une fenêtre dont le titre contient celui du média et se termine
    /// par un site connu (« Titre - YouTube »), ou dont le titre EST un site connu (« Netflix »). nil si on ne peut pas l'affirmer
    /// (l'onglet qui joue n'est pas l'onglet affiché) : on n'invente jamais un site.
    public static func site(titresDeFenetres: [String], titreMedia: String) -> String? {
        let media = normaliser(titreMedia).trimmingCharacters(in: .whitespaces)
        for brut in titresDeFenetres {
            let titre = sansNavigateur(brut).trimmingCharacters(in: .whitespaces)
            let n = normaliser(titre)
            for site in sitesConnus {
                let s = normaliser(site)
                if n == s { return site }   // « Netflix » : le titre de l'onglet est le nom du site
                guard media.count >= 6 else { continue }
                let debut = String(media.prefix(18))
                if n.contains(debut), n.hasSuffix(" - " + s) || n.hasSuffix(" | " + s) || n.hasSuffix(" \u{2013} " + s) || n.hasSuffix(" \u{2014} " + s) { return site }
            }
        }
        return nil
    }
}

// MARK: couleur dominante de la pochette

public struct CouleurRVB: Equatable, Sendable {
    public var r: Double, g: Double, b: Double
    public init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }
    public var hexa: String { String(format: "#%02x%02x%02x", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded())) }
}

/// La teinte de la lueur, de l'onde et de la barre : `clair` (la couleur vive de la pochette) et `profond` (son partenaire : la
/// deuxième couleur de l'image si elle en a une, sinon une variante plus profonde).
public struct TeintePochette: Equatable, Sendable {
    public var clair: CouleurRVB
    public var profond: CouleurRVB
    public init(clair: CouleurRVB, profond: CouleurRVB) { self.clair = clair; self.profond = profond }
    /// Pochette sans couleur (noir et blanc, gris) ou absente : une teinte claire neutre.
    public static let neutre = TeintePochette(clair: CouleurRVB(r: 0.86, g: 0.86, b: 0.90), profond: CouleurRVB(r: 0.58, g: 0.58, b: 0.64))
}

public enum CouleurDominante {
    private static let classes = 24   // 15° chacune

    public static func hsv(r: Double, g: Double, b: Double) -> (h: Double, s: Double, v: Double) {
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        var h = 0.0
        if d > 0 {
            if mx == r { h = (g - b) / d + (g < b ? 6 : 0) } else if mx == g { h = (b - r) / d + 2 } else { h = (r - g) / d + 4 }
            h *= 60
        }
        return (h, mx == 0 ? 0 : d / mx, mx)
    }

    static func rvb(h: Double, s: Double, v: Double) -> CouleurRVB {
        let hh = (h.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 60
        let i = Int(hh) % 6, f = hh - Double(Int(hh))
        let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
        switch i {
        case 0: return CouleurRVB(r: v, g: t, b: p)
        case 1: return CouleurRVB(r: q, g: v, b: p)
        case 2: return CouleurRVB(r: p, g: v, b: t)
        case 3: return CouleurRVB(r: p, g: q, b: v)
        case 4: return CouleurRVB(r: t, g: p, b: v)
        default: return CouleurRVB(r: v, g: p, b: q)
        }
    }

    private static func distanceDeTeinte(_ a: Double, _ b: Double) -> Double { let d = abs(a - b).truncatingRemainder(dividingBy: 360); return min(d, 360 - d) }

    /// `pixels` : RGBA 8 bits, `largeur × hauteur`. Les pixels vifs comptent (saturation × luminosité), les gris presque pas.
    public static func teinte(rgba pixels: [UInt8], largeur: Int, hauteur: Int) -> TeintePochette {
        let n = largeur * hauteur
        guard n > 0, pixels.count >= n * 4 else { return .neutre }
        var poids = [Double](repeating: 0, count: classes)
        var sommeS = [Double](repeating: 0, count: classes)
        var sinus = [Double](repeating: 0, count: classes), cosinus = [Double](repeating: 0, count: classes)
        var vifs = 0
        for i in 0..<n {
            let o = i * 4
            guard pixels[o + 3] >= 128 else { continue }
            let (h, s, v) = hsv(r: Double(pixels[o]) / 255, g: Double(pixels[o + 1]) / 255, b: Double(pixels[o + 2]) / 255)
            guard s >= 0.28, v >= 0.22 else { continue }   // gris, noirs et blancs délavés : pas une couleur
            vifs += 1
            let c = min(classes - 1, Int(h / (360 / Double(classes))))
            let w = s * s * v
            poids[c] += w; sommeS[c] += s * w
            sinus[c] += sin(h * .pi / 180) * w; cosinus[c] += cos(h * .pi / 180) * w
        }
        guard Double(vifs) >= Double(n) * 0.03 else { return .neutre }
        // lissage : une couleur à cheval sur deux classes voisines compte pour une seule
        var lisse = [Double](repeating: 0, count: classes)
        for c in 0..<classes { lisse[c] = poids[c] + 0.5 * (poids[(c + 1) % classes] + poids[(c + classes - 1) % classes]) }
        guard let haut = lisse.indices.max(by: { lisse[$0] < lisse[$1] }), lisse[haut] > 0 else { return .neutre }

        func teinteMoyenne(_ c: Int) -> (h: Double, s: Double) {
            var sx = 0.0, cx = 0.0, ps = 0.0, pw = 0.0
            for k in [c - 1, c, c + 1] {
                let j = (k + classes) % classes
                sx += sinus[j]; cx += cosinus[j]; ps += sommeS[j]; pw += poids[j]
            }
            let h = atan2(sx, cx) * 180 / .pi
            return ((h + 360).truncatingRemainder(dividingBy: 360), pw > 0 ? ps / pw : 0.7)
        }
        let (h1, s1) = teinteMoyenne(haut)
        // la deuxième couleur : une autre teinte (≥ 40° d'écart) qui pèse au moins un tiers de la première
        var h2: Double?
        var meilleur = 0.0
        for c in 0..<classes where lisse[c] > meilleur {
            let (hc, _) = teinteMoyenne(c)
            if distanceDeTeinte(hc, h1) >= 40, lisse[c] >= lisse[haut] * 0.33 { meilleur = lisse[c]; h2 = hc }
        }
        let clair = rvb(h: h1, s: min(0.68, max(0.5, s1 * 0.85)), v: 1)
        let profond: CouleurRVB
        if let h2 { profond = rvb(h: h2, s: 0.82, v: 1) } else { profond = rvb(h: h1 - 10, s: 0.82, v: 0.9) }
        return TeintePochette(clair: clair, profond: profond)
    }
}

// MARK: qui a la place sur l'encoche

/// Ce qui occupe l'encoche en ce moment. Priorités : dictée > réunion > filet de sécurité > proposition de mise à jour > lecture.
public struct OccupationEncoche: Equatable, Sendable {
    public var dictee = false
    public var reunion = false
    public var filet = false
    public var miseAJour = false
    /// Panneau compact, première prise en main, « Noter cet appel ? »… : une autre annonce qui occupe la place.
    public var autreAnnonce = false
    public init(dictee: Bool = false, reunion: Bool = false, filet: Bool = false, miseAJour: Bool = false, autreAnnonce: Bool = false) {
        self.dictee = dictee; self.reunion = reunion; self.filet = filet; self.miseAJour = miseAJour; self.autreAnnonce = autreAnnonce
    }
}

public enum AffichageLecture: Equatable, Sendable {
    case aucun
    /// L'îlot (au repos dans les ailes de l'encoche, déplié au survol).
    case ilot
    /// Pendant une dictée : aucune forme de la lecture, seulement une mini-miniature DANS le ruban de la dictée (cliquable : reprend la lecture).
    case miniature
}

public enum PrioriteLecture {
    public static func affichage(occupation o: OccupationEncoche, morceau: Bool, reglageAffichage: Bool) -> AffichageLecture {
        guard reglageAffichage, morceau else { return .aucun }
        // pendant une réunion, la lecture reste : la réunion a l'îlot, la vidéo passe dans la bulle (maquette ilot-reunion.html)
        if o.dictee { return .miniature }               // dictée : l'îlot s'efface ; mini-miniature dans le ruban (si Verbe a mis en pause)
        if o.filet || o.miseAJour || o.autreAnnonce { return .aucun }
        return .ilot
    }
}

extension PrioriteLecture {
    /// Hors de l'encoche, pendant une dictée (Hugues 12/11 : « comme l'iPhone, l'îlot ne disparaît jamais ») : la pilule de verre de la
    /// dictée garde la lecture que la dictée a mise en pause, sa miniature et le signe pause ; une lecture qui joue encore, ou que la dictée
    /// n'a pas mise en pause, n'y est pas.
    public static func bulleDansLaPilule(dictee: Bool, pauseParNous: Bool, joue: Bool, morceau: Bool) -> Bool { dictee && pauseParNous && !joue && morceau }
}

/// Pause automatique pendant une dictée : on met en pause au début si quelque chose joue, et on reprend à la fin SEULEMENT si c'est
/// nous qui avons mis en pause et que rien n'a changé entre-temps (même morceau, toujours en pause).
public struct PauseDictee: Equatable, Sendable {
    public enum Action: Equatable, Sendable { case rien, pause, reprendre }
    public private(set) var pauseParNous = false
    private var cle: String?
    public init() {}

    /// Début de la dictée. Jamais pendant une réunion (la lecture n'est pas touchée), jamais si le réglage est coupé.
    public mutating func debut(morceau: MorceauEnCours?, reglage: Bool, reunion: Bool) -> Action {
        guard !pauseParNous, reglage, !reunion, let morceau, morceau.joue else { return .rien }
        pauseParNous = true
        cle = morceau.cle
        return .pause
    }

    /// Fin de la dictée (relâchement ou annulation).
    public mutating func fin(morceau: MorceauEnCours?) -> Action {
        guard pauseParNous else { return .rien }
        defer { pauseParNous = false; cle = nil }
        guard let morceau, morceau.cle == cle, !morceau.joue else { return .rien }
        return .reprendre
    }
}

// MARK: le programme d'aide : relance

/// Relance du programme d'aide quand il meurt : délai croissant (1, 2, 4, 8, 16, 32, 60 s), compteur remis à zéro après 30 s de vie ;
/// au bout de 6 échecs de suite ou si MediaRemote est déclaré inaccessible, on abandonne en silence (une ligne au journal).
public struct PlanRelanceAide: Equatable, Sendable {
    public enum Decision: Equatable, Sendable {
        case relancer(apres: TimeInterval)
        case abandonner(raison: String)
    }
    public static let echecsMax = 6
    public static let vieSaine: TimeInterval = 30
    public private(set) var echecs = 0
    public init() {}

    public static func delai(apresEchecs n: Int) -> TimeInterval { min(60, pow(2, Double(max(0, n - 1)))) }

    /// Le processus s'est arrêté (`dureeDeVie` en secondes). `echecMediaRemote` : il a lui-même annoncé que MediaRemote est inaccessible.
    public mutating func processusArrete(dureeDeVie: TimeInterval, echecMediaRemote: Bool) -> Decision {
        if echecMediaRemote { return .abandonner(raison: "MediaRemote inaccessible sur cette version de macOS") }
        if dureeDeVie >= Self.vieSaine { echecs = 0 }
        echecs += 1
        if echecs > Self.echecsMax { return .abandonner(raison: "le programme d'aide s'arrête sans cesse") }
        return .relancer(apres: Self.delai(apresEchecs: echecs))
    }

    public mutating func reinitialiser() { echecs = 0 }
}

// MARK: miniature d'une vidéo YouTube (repli quand le navigateur ne donne aucune image)

public enum MiniatureYouTube {
    /// Un identifiant de vidéo YouTube : 11 caractères parmi lettres, chiffres, « _ » et « - ». Tout le reste est refusé (l'identifiant
    /// sert à fabriquer une adresse et un nom de fichier : jamais autre chose).
    public static func estIdentifiant(_ s: String) -> Bool {
        s.utf8.count == 11 && s.utf8.allSatisfy { ($0 >= 48 && $0 <= 57) || ($0 >= 65 && $0 <= 90) || ($0 >= 97 && $0 <= 122) || $0 == 95 || $0 == 45 }
    }

    /// L'identifiant de la vidéo d'une adresse, telle qu'un navigateur l'affiche (avec ou sans « https:// » ni « www. ») :
    /// youtube.com/watch?v=ID (autres paramètres permis, dans n'importe quel ordre), youtu.be/ID, /shorts/ID, /embed/ID, /live/ID,
    /// music.youtube.com et m.youtube.com. nil pour tout le reste (page d'accueil, liste de lecture sans vidéo, autre site).
    public static func identifiant(adresse brute: String) -> String? {
        var s = brute.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, s.count < 2048, !s.contains(" ") else { return nil }
        if !s.contains("://") { s = "https://" + s }
        guard let u = URLComponents(string: s), let hote = u.host?.lowercased(), u.scheme == "https" || u.scheme == "http" else { return nil }
        let chemin = u.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        if hote == "youtu.be" {
            return chemin.first.flatMap { estIdentifiant($0) ? $0 : nil }
        }
        guard hote == "youtube.com" || hote.hasSuffix(".youtube.com") else { return nil }
        if chemin.first == "watch" {
            return u.queryItems?.first(where: { $0.name == "v" })?.value.flatMap { estIdentifiant($0) ? $0 : nil }
        }
        if chemin.count >= 2, ["shorts", "embed", "live", "v"].contains(chemin[0]) { return estIdentifiant(chemin[1]) ? chemin[1] : nil }
        return nil
    }

    /// L'adresse de la miniature publique (320 × 180, la taille « mqdefault » : environ 10 Ko).
    public static func adresseMiniature(identifiant: String) -> URL? {
        estIdentifiant(identifiant) ? URL(string: "https://i.ytimg.com/vi/\(identifiant)/mqdefault.jpg") : nil
    }
}
