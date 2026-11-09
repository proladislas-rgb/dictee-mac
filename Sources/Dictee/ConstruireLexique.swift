import AppKit
import CryptoKit
import NaturalLanguage
import DicteeCore

/// `Verbe --construire-lexique` : lit les notes et les dossiers de projets de Hugues (.md et .txt), garde les mots utiles à Whisper
/// et écrit `~/Library/Application Support/Dictee/lexique.json`. Ni micro, ni réseau, ni Accessibilité. Rien n'est écrit dans git.
///
/// Sources : ~/second-cerveau (TOUT sauf le dossier `moi/`, qui est privé et n'est jamais ouvert) et chaque dossier de projet
/// directement sous ~ qui contient des .md ou .txt. Sont ignorés : node_modules, .git, .build, dist, Library, Downloads, Desktop,
/// environnements virtuels, copies de travail git (worktrees), fichiers de plus de 1 Mo, doublons exacts.
@MainActor
enum ConstruireLexique {
    static let dossiersIgnores: Set<String> = [
        "node_modules", ".git", ".build", "dist", "library", "downloads", "desktop", ".venv", "venv", "site-packages", ".next",
        ".claude", ".superpowers", "pods", "build", "coverage", "__pycache__", "fixtures", ".swiftpm", "deriveddata", "vendor", "packages",
        "builds", "export", "logs", "bridge", "_ecarte", "temp", "tmp", "obj", "projectsettings", "usersettings",
    ]
    /// Dossiers de ~ qui ne sont pas des projets.
    static let dossiersDeLaMaisonIgnores: Set<String> = [
        "library", "downloads", "desktop", "movies", "music", "pictures", "public", "applications", "google drive", "sauvegardes",
        "sites", "documents", "unity user templates", "setup guide in-editor tutorial", "node_modules",
        // l'app de dictée elle-même : ses notes citent des mots mal entendus en exemple (« Brionia »), qui ne doivent pas devenir des mots à retenir
        "dictee-mac", "dictee-sauvegarde-2026-11-09",
    ]
    static let tailleMax = 1_000_000

    struct Bilan { var fichiers = 0; var mots = 0 }

    static func executer() -> Int32 {
        let debut = Date()
        let maison = FileManager.default.homeDirectoryForCurrentUser
        var extraction = ExtractionLexique()
        var bilans: [String: Bilan] = [:]
        var vus = Set<String>()
        var doublons = 0, tropGros = 0, illisibles = 0, document = 0

        func lire(_ racine: URL, nomSource: (URL) -> String, interdits: Set<String>) {
            let cles: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]
            guard let it = FileManager.default.enumerator(at: racine, includingPropertiesForKeys: cles, options: [.skipsHiddenFiles]) else { return }
            for cas in it {
                guard let url = cas as? URL, let v = try? url.resourceValues(forKeys: Set(cles)) else { continue }
                if v.isSymbolicLink == true { it.skipDescendants(); continue }
                if v.isDirectory == true {
                    if interdits.contains(url.lastPathComponent.lowercased()) { it.skipDescendants() }
                    continue
                }
                let ext = url.pathExtension.lowercased()
                guard v.isRegularFile == true, ext == "md" || ext == "txt" else { continue }
                guard (v.fileSize ?? 0) <= tailleMax else { tropGros += 1; continue }
                guard let donnees = try? Data(contentsOf: url), let texte = String(data: donnees, encoding: .utf8) else { illisibles += 1; continue }
                let empreinte = SHA256.hash(data: donnees).map { String(format: "%02x", $0) }.joined()
                guard vus.insert(empreinte).inserted else { doublons += 1; continue }
                document += 1
                let source = nomSource(url)
                let avant = extraction.nombreDeMots
                extraction.ajouter(texte: texte, source: source, document: document)
                bilans[source, default: Bilan()].fichiers += 1
                bilans[source, default: Bilan()].mots += extraction.nombreDeMots - avant
            }
        }

        // 1. le second cerveau, sans le dossier moi/ (privé : jamais ouvert, à aucun niveau)
        let cerveau = maison.appendingPathComponent("second-cerveau", isDirectory: true)
        lire(cerveau, nomSource: { url in
            let relatif = url.path.dropFirst(cerveau.path.count + 1).split(separator: "/")
            return relatif.count > 1 ? "second-cerveau/\(relatif[0])" : "second-cerveau"
        }, interdits: dossiersIgnores.union(["moi"]))

        // 2. les dossiers de projets sous ~ (une copie de travail git, dont `.git` est un fichier, n'est qu'un doublon du dépôt principal)
        let enfants = (try? FileManager.default.contentsOfDirectory(at: maison, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        var projets: [URL] = []
        for dossier in enfants.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let nom = dossier.lastPathComponent
            guard (try? dossier.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            if nom == "second-cerveau" || dossiersDeLaMaisonIgnores.contains(nom.lowercased()) { continue }
            var estDossier: ObjCBool = false
            if FileManager.default.fileExists(atPath: dossier.appendingPathComponent(".git").path, isDirectory: &estDossier), !estDossier.boolValue { continue }
            projets.append(dossier)
        }
        for p in projets { lire(p, nomSource: { _ in p.lastPathComponent }, interdits: dossiersIgnores) }

        if let i = CommandLine.arguments.firstIndex(of: "--pourquoi") {
            for m in CommandLine.arguments[(i + 1)...] { print(extraction.diagnostic(m, estConnu: { Orthographe.estConnu($0) }, variantesAvecAccents: { Orthographe.estFauteDAccents($0) })) }
            return 0
        }
        print("Sources lues :")
        for (nom, b) in bilans.sorted(by: { $0.value.mots > $1.value.mots }) { print(String(format: "  %-44@ %5d fichier(s), %8d mots", nom as NSString, b.fichiers, b.mots)) }
        print("Ignorés : \(doublons) doublon(s) exact(s), \(tropGros) fichier(s) de plus de 1 Mo, \(illisibles) illisible(s).")

        // 3. candidats utiles (mots courants écartés d'après le correcteur du Mac, français et anglais)
        var candidats = extraction.candidats(estConnu: { Orthographe.estConnu($0) }, variantesAvecAccents: { Orthographe.estFauteDAccents($0) })
        var entrees: [EntreeLexique] = candidats.map {
            EntreeLexique(mot: $0.mot, frequence: $0.frequence, documents: $0.documents, source: $0.source, langue: langue(de: $0.phrase), type: $0.type)
        }
        candidats.removeAll()
        var plies = Set(entrees.map { ClePhonetique.plier($0.mot) })

        // 4. quelques mots difficiles de base (fréquence 1, en dernier) — sans ceux que le correcteur connaît déjà
        var ajoutsDeBase = 0
        for m in LexiqueDeBase.mots {
            let p = ClePhonetique.plier(m)
            guard !plies.contains(p) else { continue }
            let parties = m.split(whereSeparator: { $0 == " " || $0 == "-" }).map(String.init)
            if parties.allSatisfy({ Orthographe.estConnu($0) }) && Orthographe.estConnu(m) { continue }
            let majuscule = m.first?.isUppercase == true
            let sigleOuMixte = m.dropFirst().contains(where: \.isUppercase)
            entrees.append(EntreeLexique(mot: m, frequence: 1, documents: 0, source: "base", langue: "autre", type: majuscule && !sigleOuMixte ? .nom : .technique))
            plies.insert(p); ajoutsDeBase += 1
        }

        // 5. les mots choisis par Hugues (mots.txt) passent toujours devant
        let choisis = Dictionnaire.mots()
        var devant: [EntreeLexique] = []
        for m in choisis {
            let p = ClePhonetique.plier(m)
            let dejaLa = entrees.first { ClePhonetique.plier($0.mot) == p }
            entrees.removeAll { ClePhonetique.plier($0.mot) == p }
            devant.append(EntreeLexique(mot: m, frequence: dejaLa?.frequence ?? 0, documents: dejaLa?.documents ?? 0, source: "mots.txt",
                                        langue: dejaLa?.langue ?? "autre", type: dejaLa?.type ?? (m.first?.isUppercase == true ? .nom : .technique)))
        }
        let lexique = Lexique(construitLe: Date(), entrees: devant + entrees)

        guard let donnees = lexique.donnees() else { print("Écriture impossible : lexique illisible"); return 1 }
        do {
            try donnees.write(to: LexiqueStore.url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: LexiqueStore.url.path)
        } catch { print("Écriture impossible : \(error.localizedDescription)"); return 1 }

        let parType = Dictionary(grouping: lexique.entrees, by: \.type).mapValues(\.count)
        print("\nLexique : \(lexique.entrees.count) mots (\(devant.count) de mots.txt, \(ajoutsDeBase) de base ; noms \(parType[.nom] ?? 0), sigles \(parType[.sigle] ?? 0), termes \(parType[.technique] ?? 0)).")
        print("Écrit dans \(LexiqueStore.url.path) (lisible par vous seul) en \(String(format: "%.1f", Date().timeIntervalSince(debut))) s.")
        print("40 premiers :")
        for (i, e) in lexique.entrees.prefix(40).enumerated() { print(String(format: "  %2d. %@  (%d, %@, %@)", i + 1, e.mot as NSString, e.frequence, e.type.rawValue as NSString, e.source as NSString)) }
        return 0
    }

    /// `fr`, `en` ou `autre`, d'après la phrase où le mot apparaît.
    static func langue(de phrase: String) -> String {
        guard phrase.count >= 12 else { return "autre" }
        let r = NLLanguageRecognizer()
        r.languageConstraints = [.french, .english]
        r.processString(phrase)
        guard let l = r.dominantLanguage, (r.languageHypotheses(withMaximum: 2)[l] ?? 0) >= 0.6 else { return "autre" }
        return l == .french ? "fr" : "en"
    }
}
