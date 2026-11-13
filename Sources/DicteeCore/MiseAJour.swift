import Foundation
import CryptoKit

// Mise à jour automatique de Verbe : toute la logique pure (aucun réseau, aucun disque, aucune interface).
// Le réseau, le téléchargement et l'installation sont dans le produit Dictee (MiseAJourReseau.swift, MiseAJourInstallation.swift).

// MARK: versions

/// Une version `1.2.3` comparée comme des nombres (0.2.10 > 0.2.9, 0.3 == 0.3.0). Un suffixe (`-beta`) ou tout autre
/// caractère la rend illisible : mieux vaut ne rien proposer que se tromper.
public struct VersionApp: Comparable, Hashable, CustomStringConvertible, Sendable {
    public let composantes: [Int]

    public init?(_ texte: String) {
        var t = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("v") || t.hasPrefix("V") { t.removeFirst() }
        let morceaux = t.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(morceaux.count) else { return nil }
        var valeurs: [Int] = []
        for m in morceaux {
            guard !m.isEmpty, m.count <= 6, m.allSatisfy({ $0.isASCII && $0.isNumber }), let v = Int(m) else { return nil }
            valeurs.append(v)
        }
        composantes = valeurs
    }

    public var description: String { composantes.map(String.init).joined(separator: ".") }

    private var normalisees: [Int] {
        var v = composantes
        while v.count > 1, v.last == 0 { v.removeLast() }
        return v
    }

    public static func == (a: VersionApp, b: VersionApp) -> Bool { a.normalisees == b.normalisees }
    public func hash(into h: inout Hasher) { h.combine(normalisees) }
    public static func < (a: VersionApp, b: VersionApp) -> Bool {
        let n = max(a.composantes.count, b.composantes.count)
        for i in 0..<n {
            let x = i < a.composantes.count ? a.composantes[i] : 0
            let y = i < b.composantes.count ? b.composantes[i] : 0
            if x != y { return x < y }
        }
        return false
    }
}

// MARK: adresses permises

/// Où le JSON de GitHub a le droit d'envoyer le téléchargement. En production : seulement https vers github.com et
/// ses serveurs de fichiers, et seulement dans le dépôt de Verbe. Le mode de test local autorise 127.0.0.1.
public struct PolitiqueAdresses: Sendable {
    public var hotes: Set<String>
    public var suffixes: [String]
    public var autoriserHTTPLocal: Bool
    /// Début obligatoire du chemin d'un téléchargement (le dépôt de Verbe) ; vide = pas de contrainte.
    public var prefixeChemin: String

    public init(hotes: Set<String>, suffixes: [String], autoriserHTTPLocal: Bool, prefixeChemin: String) {
        self.hotes = hotes; self.suffixes = suffixes; self.autoriserHTTPLocal = autoriserHTTPLocal; self.prefixeChemin = prefixeChemin
    }

    public static let depot = "proladislas-rgb/dictee-mac"
    public static let production = PolitiqueAdresses(hotes: ["github.com", "api.github.com"], suffixes: [".githubusercontent.com"],
                                                     autoriserHTTPLocal: false, prefixeChemin: "/\(depot)/")
    public static let local = PolitiqueAdresses(hotes: ["127.0.0.1", "localhost"], suffixes: [], autoriserHTTPLocal: true, prefixeChemin: "")

    /// Une adresse de téléchargement du DMG (ou du fichier d'empreinte).
    public func accepte(_ url: URL) -> Bool {
        accepteRedirection(url) && (prefixeChemin.isEmpty || url.path.hasPrefix(prefixeChemin))
    }

    /// Une redirection en cours de route : même contrôle d'hôte et de schéma, sans exiger le chemin du dépôt (les fichiers
    /// sont servis par objects.githubusercontent.com, qui n'a pas ce chemin).
    public func accepteRedirection(_ url: URL) -> Bool {
        guard let hote = url.host?.lowercased(), let schema = url.scheme?.lowercased(), url.user == nil, url.password == nil else { return false }
        let local = (hote == "127.0.0.1" || hote == "localhost")
        if schema == "http" { guard autoriserHTTPLocal, local else { return false } } else if schema != "https" { return false }
        return hotes.contains(hote) || suffixes.contains(where: { hote.hasSuffix($0) })
    }
}

// MARK: la release GitHub

/// Ce que Verbe retient d'une release GitHub : la version, ses notes, le DMG et ses empreintes possibles.
public struct PropositionMiseAJour: Equatable, Sendable {
    public var version: VersionApp
    public var notes: String
    public var pageURL: URL?
    public var dmgURL: URL
    public var taille: Int
    /// Empreinte SHA-256 donnée par GitHub dans le JSON de l'asset (`digest`), si elle y est.
    public var empreinteJSON: String?
    /// Fichier `Verbe-<version>.dmg.sha256` joint à la release, s'il existe.
    public var empreinteURL: URL?

    public init(version: VersionApp, notes: String, pageURL: URL?, dmgURL: URL, taille: Int, empreinteJSON: String?, empreinteURL: URL?) {
        self.version = version; self.notes = notes; self.pageURL = pageURL; self.dmgURL = dmgURL
        self.taille = taille; self.empreinteJSON = empreinteJSON; self.empreinteURL = empreinteURL
    }

    public var nomDMG: String { NomApp.dmg(version) }
}

public enum ChoixMiseAJour {
    public static let tailleMaximale = 500_000_000

    public enum Resultat: Equatable, Sendable {
        case proposition(PropositionMiseAJour)
        case aJour
        /// Une release plus récente existe mais on ne peut pas l'installer (pas de DMG au bon nom, adresse refusée…) : rien n'est proposé.
        case inutilisable(String)
        case illisible
    }

    private struct Asset: Decodable {
        var name: String
        var size: Int?
        var digest: String?
        var browser_download_url: String
    }
    private struct Release: Decodable {
        var tag_name: String
        var html_url: String?
        var body: String?
        var draft: Bool?
        var prerelease: Bool?
        var assets: [Asset]?
    }

    /// Lit le JSON de `releases/latest` et décide. Prend l'asset `Voxile-<version>.dmg` (nom exact), jamais un autre (la release joint
    /// aussi `Verbe-<version>.dmg`, pour les Verbe 0.3.x d'avant le changement de nom).
    public static func analyser(json: Data, versionActuelle: VersionApp, politique: PolitiqueAdresses = .production) -> Resultat {
        guard let release = try? JSONDecoder().decode(Release.self, from: json) else { return .illisible }
        if release.draft == true || release.prerelease == true { return .aJour }
        guard let version = VersionApp(release.tag_name) else { return .illisible }
        guard version > versionActuelle else { return .aJour }

        let nomDMG = NomApp.dmg(version)
        let assets = release.assets ?? []
        guard let dmg = assets.first(where: { $0.name == nomDMG }) else { return .inutilisable("pas de fichier \(nomDMG) dans la release \(release.tag_name)") }
        guard let url = URL(string: dmg.browser_download_url), politique.accepte(url) else { return .inutilisable("adresse de téléchargement refusée") }
        guard let taille = dmg.size, taille > 0, taille <= tailleMaximale else { return .inutilisable("taille du fichier invalide") }
        let sha = assets.first(where: { $0.name == nomDMG + ".sha256" }).flatMap { URL(string: $0.browser_download_url) }.flatMap { politique.accepte($0) ? $0 : nil }
        return .proposition(PropositionMiseAJour(
            version: version, notes: release.body ?? "", pageURL: release.html_url.flatMap(URL.init(string:)),
            dmgURL: url, taille: taille, empreinteJSON: dmg.digest.flatMap(EmpreinteSHA256.depuisDigest), empreinteURL: sha))
    }
}

// MARK: empreintes

public enum EmpreinteSHA256 {
    /// `sha256:<64 chiffres hexadécimaux>` (champ `digest` de GitHub) -> l'empreinte en minuscules.
    public static func depuisDigest(_ digest: String) -> String? {
        let parties = digest.split(separator: ":", maxSplits: 1).map(String.init)
        guard parties.count == 2, parties[0].lowercased() == "sha256" else { return nil }
        return valide(parties[1])
    }

    /// Contenu d'un fichier `.sha256` : `<empreinte>  Verbe-x.dmg` (sortie de `shasum -a 256`), `<empreinte> *nom`, ou l'empreinte seule.
    /// Un nom de fichier différent de `nomFichier` rend le fichier inutilisable.
    public static func depuisFichier(_ contenu: String, nomFichier: String) -> String? {
        let lignes = contenu.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard lignes.count == 1, let ligne = lignes.first else { return nil }
        let morceaux = ligne.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard let empreinte = valide(morceaux[0]) else { return nil }
        if morceaux.count == 2 {
            var nom = morceaux[1].trimmingCharacters(in: .whitespaces)
            if nom.hasPrefix("*") { nom.removeFirst() }
            guard nom == nomFichier else { return nil }
        }
        return empreinte
    }

    private static func valide(_ texte: String) -> String? {
        let t = texte.trimmingCharacters(in: .whitespaces).lowercased()
        guard t.count == 64, t.allSatisfy({ $0.isHexDigit }) else { return nil }
        return t
    }

    /// Toutes les empreintes publiées doivent correspondre. Aucune publiée : rien à comparer (`true`), l'appelant le note au journal.
    public static func correspond(calculee: String, attendues: [String]) -> Bool {
        let c = calculee.lowercased()
        return attendues.allSatisfy { $0.lowercased() == c }
    }

    /// Calcul au fil de l'eau (téléchargement par morceaux).
    public struct Calcul {
        private var hacheur = SHA256()
        public private(set) var octets = 0
        public init() {}
        public mutating func ajouter(_ donnees: Data) { hacheur.update(data: donnees); octets += donnees.count }
        public func resultat() -> String {
            var copie = hacheur
            return copie.finalize().map { String(format: "%02x", $0) }.joined()
        }
    }

    public static func calculer(fichier: URL) throws -> String {
        let lecteur = try FileHandle(forReadingFrom: fichier)
        defer { try? lecteur.close() }
        var calcul = Calcul()
        while let morceau = try lecteur.read(upToCount: 1 << 20), !morceau.isEmpty { calcul.ajouter(morceau) }
        return calcul.resultat()
    }
}

// MARK: planification

/// Quand vérifier GitHub : une fois par jour, au plus ; jamais plus d'une fois toutes les 10 s sur demande ;
/// et jamais avant l'heure indiquée par GitHub quand la limite de requêtes (60 par heure sans jeton) est atteinte.
public enum PlanVerification {
    public static let delaiAuLancement: TimeInterval = 30
    public static let intervalle: TimeInterval = 24 * 3600
    /// Après un échec (réseau coupé), nouvelle tentative au plus toutes les 30 minutes.
    public static let delaiApresEchec: TimeInterval = 30 * 60
    public static let minimumSurDemande: TimeInterval = 10
    /// Relevé du minuteur de l'app (la veille du Mac décale les minuteurs : on compare des dates, pas des durées).
    public static let periodeDeReleve: TimeInterval = 600

    public static func doitVerifierSeul(automatique: Bool, derniereReussite: Date?, derniereTentative: Date?, pasAvant: Date?, maintenant: Date) -> Bool {
        guard automatique else { return false }
        if let pasAvant, maintenant < pasAvant { return false }
        if let t = derniereTentative, maintenant.timeIntervalSince(t) < delaiApresEchec { return false }
        guard let r = derniereReussite else { return true }
        return maintenant.timeIntervalSince(r) >= intervalle || r > maintenant.addingTimeInterval(3600)   // horloge reculée : on revérifie
    }

    public static func demandePermise(derniereTentative: Date?, pasAvant: Date?, maintenant: Date) -> Bool {
        if let pasAvant, maintenant < pasAvant { return false }
        if let t = derniereTentative, maintenant.timeIntervalSince(t) < minimumSurDemande, t <= maintenant { return false }
        return true
    }

    /// Limite atteinte (403 ou 429 avec `x-ratelimit-remaining: 0` ou `Retry-After`) : l'heure avant laquelle ne rien demander.
    public static func pasAvant(statut: Int, enTetes: [String: String], maintenant: Date) -> Date? {
        guard statut == 403 || statut == 429 else { return nil }
        let h = Dictionary(uniqueKeysWithValues: enTetes.map { ($0.key.lowercased(), $0.value) })
        if let r = h["retry-after"], let s = Double(r) { return maintenant.addingTimeInterval(min(max(s, 60), 24 * 3600)) }
        if h["x-ratelimit-remaining"] == "0", let r = h["x-ratelimit-reset"], let t = Double(r) {
            let d = Date(timeIntervalSince1970: t)
            return min(max(d, maintenant.addingTimeInterval(60)), maintenant.addingTimeInterval(24 * 3600))
        }
        return maintenant.addingTimeInterval(3600)
    }
}

// MARK: proposition sous l'encoche

/// Ce que l'app est en train de faire, vu par la règle d'affichage.
public struct ContexteAffichage: Equatable, Sendable {
    public var dicteeEnCours = false
    public var reunionEnCours = false
    /// Une autre annonce occupe l'encoche : filet de sécurité, panneau compact, « Noter cet appel ? », première prise en main.
    public var autreAnnonce = false
    public var installationPossible = true
    public init(dicteeEnCours: Bool = false, reunionEnCours: Bool = false, autreAnnonce: Bool = false, installationPossible: Bool = true) {
        self.dicteeEnCours = dicteeEnCours; self.reunionEnCours = reunionEnCours
        self.autreAnnonce = autreAnnonce; self.installationPossible = installationPossible
    }
    public var occupe: Bool { dicteeEnCours || reunionEnCours || autreAnnonce }
}

/// « Plus tard » : la proposition d'une version est repoussée au lendemain (24 h). Une version plus récente est proposée tout de suite.
public struct ReportProposition: Equatable, Sendable {
    public var version: VersionApp
    public var jusqua: Date
    public init(version: VersionApp, jusqua: Date) { self.version = version; self.jusqua = jusqua }

    public static let delai: TimeInterval = 24 * 3600
    public static func plusTard(version: VersionApp, maintenant: Date) -> ReportProposition {
        ReportProposition(version: version, jusqua: maintenant.addingTimeInterval(delai))
    }
}

public enum AffichageMiseAJour {
    /// La ligne sous l'encoche peut-elle s'afficher maintenant ? Jamais pendant une dictée ni une réunion (ni sur une autre annonce),
    /// jamais si l'app ne peut pas se remplacer elle-même, jamais avant la fin d'un « Plus tard » pour cette version.
    public static func peutProposer(version: VersionApp, versionActuelle: VersionApp, contexte: ContexteAffichage, report: ReportProposition?, maintenant: Date) -> Bool {
        guard version > versionActuelle, contexte.installationPossible, !contexte.occupe else { return false }
        if let report, report.version == version, maintenant < report.jusqua, report.jusqua <= maintenant.addingTimeInterval(ReportProposition.delai + 60) { return false }
        return true
    }

    /// Le redémarrage après installation attend la fin d'une dictée ou d'une réunion.
    public static func peutRedemarrer(contexte: ContexteAffichage) -> Bool { !contexte.dicteeEnCours && !contexte.reunionEnCours }
}

// MARK: emplacement de l'app

public enum EmplacementApp {
    public enum Verdict: Equatable, Sendable {
        case possible
        case refuse(String)
    }

    /// Verbe peut-il se remplacer là où il est ? Non depuis l'image disque, un volume en lecture seule, un dossier « translocalisé »
    /// par macOS, ou un dossier où l'on ne peut pas écrire.
    public static func evaluer(chemin: String, volumeEnLectureSeule: Bool, dossierEcrivable: Bool) -> Verdict {
        guard chemin.hasSuffix(".app") else { return .refuse("Voxile ne tourne pas depuis une app installée.") }
        if chemin.contains("/AppTranslocation/") { return .refuse("Voxile tourne depuis un dossier temporaire de macOS. Place-le dans Applications, puis rouvre-le.") }
        if chemin.hasPrefix("/Volumes/"), volumeEnLectureSeule { return .refuse("Voxile tourne depuis l\u{2019}image disque. Glisse-le dans Applications, puis rouvre-le.") }
        if volumeEnLectureSeule { return .refuse("Le dossier de Voxile est en lecture seule.") }
        if !dossierEcrivable { return .refuse("Le dossier de Voxile n\u{2019}est pas modifiable. Télécharge la nouvelle version à la main.") }
        return .possible
    }
}

// MARK: contrôle de l'app téléchargée

public enum ControleApp {
    /// Sortie de `codesign -dvv` (envoyée sur la sortie d'erreur) -> la ligne `Identifier=…`.
    public static func identifiant(sortieCodesign: String) -> String? {
        for ligne in sortieCodesign.split(whereSeparator: \.isNewline) where ligne.hasPrefix("Identifier=") {
            return String(ligne.dropFirst("Identifier=".count))
        }
        return nil
    }

    /// L'app trouvée dans le DMG est-elle bien Verbe, dans la version annoncée ? Renvoie la raison du refus, ou `nil`.
    public static func refus(identifiantAttendu: String, identifiantSignature: String?, identifiantPlist: String?,
                             versionAttendue: VersionApp, versionPlist: String?) -> String? {
        guard let identifiantSignature else { return "signature illisible" }
        guard identifiantSignature == identifiantAttendu else { return "identifiant de signature inattendu (\(identifiantSignature))" }
        guard identifiantPlist == identifiantAttendu else { return "identifiant de l\u{2019}app inattendu (\(identifiantPlist ?? "absent"))" }
        guard let versionPlist, let lue = VersionApp(versionPlist) else { return "version de l\u{2019}app illisible" }
        guard lue == versionAttendue else { return "version \(lue) au lieu de \(versionAttendue)" }
        return nil
    }
}

// MARK: notes de version

/// Les notes d'une release (Markdown) réduites à ce qu'une petite vue sait montrer : titres, puces, paragraphes. Rien de cliquable,
/// rien de HTML : le texte vient du réseau.
public enum NotesDeVersion {
    public enum Bloc: Equatable, Sendable {
        case titre(String)
        case puce(String)
        case paragraphe(String)
    }

    public static let longueurMaximale = 8000

    public static func blocs(_ markdown: String) -> [Bloc] {
        var resultat: [Bloc] = []
        var premier = true
        for brute in String(markdown.prefix(longueurMaximale)).split(omittingEmptySubsequences: true, whereSeparator: \.isNewline) {
            let ligne = brute.trimmingCharacters(in: .whitespaces)
            if ligne.isEmpty { continue }
            if ligne.hasPrefix("#") {
                let titre = nettoyer(String(ligne.drop(while: { $0 == "#" })))
                // le premier titre répète « Verbe x.y.z » : la vue a déjà le sien
                if premier && ligne.hasPrefix("# ") { premier = false; continue }
                if !titre.isEmpty { resultat.append(.titre(titre)) }
            } else if ligne.hasPrefix("- ") || ligne.hasPrefix("* ") || ligne.hasPrefix("• ") {
                let texte = nettoyer(String(ligne.dropFirst(2)))
                if !texte.isEmpty { resultat.append(.puce(texte)) }
            } else {
                let texte = nettoyer(ligne)
                if !texte.isEmpty { resultat.append(.paragraphe(texte)) }
            }
            premier = false
        }
        return resultat
    }

    /// Retire les balises HTML, les images, les adresses des liens (le texte du lien reste) et les marques de gras / code.
    static func nettoyer(_ texte: String) -> String {
        var t = texte.trimmingCharacters(in: .whitespaces)
        t = t.replacingOccurrences(of: #"!\[[^\]]*\]\([^)]*\)"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: #"<[^>]*>"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "__", with: "").replacingOccurrences(of: "`", with: "")
        return t.trimmingCharacters(in: .whitespaces)
    }
}
