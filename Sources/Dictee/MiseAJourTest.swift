import AppKit
import SwiftUI
import DicteeCore

/// Modes de vérification en ligne de commande de la mise à jour. Aucun ne touche au micro, à la parole, à l'accessibilité ni au clavier,
/// aucun ne démarre l'app ni ne relance quoi que ce soit.
enum MiseAJourTest {
    private static func valeur(_ nom: String, _ a: [String]) -> String? {
        guard let i = a.firstIndex(of: nom), i + 1 < a.count, !a[i + 1].hasPrefix("--") else { return nil }
        return a[i + 1]
    }

    private static func client(_ a: [String]) -> ClientMiseAJour? {
        let version = VersionApp(valeur("--version-actuelle", a) ?? VersionDeLApp.texte) ?? VersionApp("0.0.0")!
        var c = ClientMiseAJour(versionActuelle: version)
        if let api = valeur("--api", a) {
            guard let url = URL(string: api), PolitiqueAdresses.local.accepteRedirection(url) else {
                print("--api n\u{2019}accepte qu\u{2019}une adresse locale (127.0.0.1 ou localhost) : \(api)")
                return nil
            }
            c.urlAPI = url
            c.politique = .local
        }
        return c
    }

    private static func decrire(_ p: PropositionMiseAJour) {
        print("  version      : \(p.version)")
        print("  fichier      : \(p.nomDMG), \(p.taille) octets")
        print("  adresse      : \(p.dmgURL.absoluteString)")
        print("  empreinte    : \(p.empreinteJSON.map { "oui, dans le JSON (\($0.prefix(12))…)" } ?? "non, dans le JSON")" + (p.empreinteURL != nil ? " ; fichier .sha256 joint" : " ; pas de fichier .sha256"))
        print("  notes        : \(NotesDeVersion.blocs(p.notes).count) blocs")
    }

    /// `Verbe --verifier-mise-a-jour [--version-actuelle X] [--api http://127.0.0.1:PORT/latest.json]` : interroge l'API (réseau seulement)
    /// et affiche ce que l'app proposerait. N'installe rien.
    static func verifier(arguments a: [String]) async -> Int32 {
        guard let c = client(a) else { return 2 }
        print("Version installée : \(c.versionActuelle)")
        print("Requête           : GET \(c.urlAPI.absoluteString)  (User-Agent : Verbe-\(c.versionActuelle))")
        switch await c.chercher() {
        case .proposition(let p):
            print("Verbe proposerait : Verbe \(p.version) (Installer / Plus tard / Nouveautés)")
            decrire(p)
            return 0
        case .aJour:
            print("Verbe proposerait : rien (à jour)")
            return 0
        case .horsLigne:
            print("Verbe proposerait : rien (pas de connexion, silencieux)")
            return 0
        case .limite(let jusqua):
            print("Verbe proposerait : rien (limite de requêtes atteinte, pas avant \(jusqua))")
            return 0
        case .echec(let detail):
            print("Échec : \(detail)")
            return 1
        }
    }

    /// `Verbe --installer-mise-a-jour-test --app COPIE [--api URL locale] [--version-actuelle X]` : cherche la release (sur le serveur local de test, ou sur GitHub sans `--api`), la télécharge,
    /// la contrôle et remplace la COPIE d'app indiquée, sans relancer. Refuse de toucher à /Applications/Verbe.app, ~/Applications/Verbe.app
    /// ou à l'app qui exécute ce mode.
    static func installer(arguments a: [String]) async -> Int32 {
        guard let c = client(a) else { return 2 }
        guard let chemin = valeur("--app", a) else { print("--app manque"); return 2 }
        let cible = URL(fileURLWithPath: (chemin as NSString).expandingTildeInPath).resolvingSymlinksInPath()
        let maison = FileManager.default.homeDirectoryForCurrentUser
        let interdits = ["/Applications/Verbe.app", maison.appendingPathComponent("Applications/Verbe.app").path, Bundle.main.bundleURL.resolvingSymlinksInPath().path]
        if interdits.contains(cible.path) { print("Refusé : ce test ne remplace que des copies, jamais une app installée (\(cible.path))"); return 2 }
        func versionDe(_ app: URL) -> String { (NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))?["CFBundleShortVersionString"] as? String) ?? "illisible" }

        print("Copie à mettre à jour : \(cible.path) (version \(versionDe(cible)))")
        guard case .proposition(let p) = await c.chercher() else { print("Aucune mise à jour proposée par le serveur de test"); return 1 }
        print("Proposition : Verbe \(p.version) (\(p.taille) octets)")
        var installateur = InstallateurMiseAJour(client: c)
        installateur.echecSimuleApresEchange = a.contains("--simuler-echec-apres-echange")
        do {
            try await installateur.installer(p, appActuelle: cible) { etape in
                switch etape {
                case .telechargement(let x): if x == 0 || x >= 1 { print("  téléchargement \(Int(x * 100)) %") }
                case .verification: print("  vérification de l\u{2019}empreinte")
                case .installation: print("  installation")
                }
            }
        } catch {
            let e = error as? ErreurMiseAJour
            print("ÉCHEC : \(e?.message ?? error.localizedDescription)")
            print("  détail : \(e?.detail ?? "")")
            print("Copie après l\u{2019}échec : version \(versionDe(cible))")
            let v = await Commande.executer("/usr/bin/codesign", ["--verify", "--strict", "--deep", cible.path])
            print("Copie après l\u{2019}échec : codesign \(v.reussie ? "valide" : "INVALIDE : \(v.texte)")")
            return 1
        }
        print("Copie après la mise à jour : version \(versionDe(cible))")
        let v = await Commande.executer("/usr/bin/codesign", ["--verify", "--strict", "--deep", cible.path])
        print("Copie après la mise à jour : codesign \(v.reussie ? "valide" : "INVALIDE : \(v.texte)")")
        let restes = ((try? FileManager.default.contentsOfDirectory(atPath: cible.deletingLastPathComponent().path)) ?? []).filter { $0.hasPrefix(InstallateurMiseAJour.prefixePreparation) }
        print("Restes de préparation à côté de la copie : \(restes.count)")
        return v.reussie && versionDe(cible) == p.version.description && restes.isEmpty ? 0 : 1
    }
}

/// `Dictee --rendu-mise-a-jour dossier` : la ligne sous l'encoche (proposition, téléchargement, installation, échec) et la ligne des
/// Réglages en PNG, sans fenêtre.
enum RenduMiseAJour {
    @MainActor
    static func executer(dossier: String) -> Int32 {
        _ = NSApplication.shared
        Polices.enregistrer()
        let url = URL(fileURLWithPath: (dossier as NSString).expandingTildeInPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var ok = true
        let g = GeometrieEncoche()   // caméra fictive 200 × 32 pt, comme les maquettes

        func bande(_ nom: String, _ m: MiseAJourModele) {
            let etat = BandeMiseAJourModele()
            etat.geometrie = g; etat.ouverte = true
            let marge = FormeEncoche.congeHaut.width + 4
            let taille = CGSize(width: ceil(MiseAJourBandeVue.largeurPleine(g) + 2 * marge), height: g.hauteur + MiseAJourBandeVue.hauteurRuban + 8)
            let scene = CGSize(width: 720, height: 150)
            let vue = RenduVues.Bureau(taille: scene, haut: g.hauteur, camera: g.largeur) {
                EmptyView()
            }
            .overlay(alignment: .top) { MiseAJourBandeVue(m: m, bande: etat, tailleFenetre: taille).frame(width: taille.width, height: taille.height) }
            ok = RenduVues.ecrire(RenduVues.png(vue, taille: scene), url.appendingPathComponent("\(nom).png")) && ok
        }
        bande("bande-1-proposition", MiseAJourModele.exemple(disponible: "0.3.1"))
        bande("bande-2-telechargement", MiseAJourModele.exemple(.telechargement(0.42), disponible: "0.3.1"))
        bande("bande-3-installation", MiseAJourModele.exemple(.installation, disponible: "0.3.1"))
        bande("bande-4-relance", MiseAJourModele.exemple(.attenteRedemarrage, disponible: "0.3.1"))
        bande("bande-5-echec", MiseAJourModele.exemple(disponible: "0.3.1", echec: "Mise à jour impossible. Rien n\u{2019}a été changé."))

        // Réglages : section « Compte & données » dans la fenêtre
        let exemple = RenduVues.historiqueExemple()
        let storeReunions = ReunionStore(dossier: FileManager.default.temporaryDirectory.appendingPathComponent("dictee-rendu-reunions"), lire: false)
        let controleur = ReunionController(store: storeReunions)
        let reunions = ReunionsModele(store: storeReunions)
        let taille = CGSize(width: 1180, height: 1000)
        func reglages(_ nom: String, _ maj: MiseAJourModele, taille: CGSize = taille) {
            let nav = NavigationFenetre(); nav.onglet = .reglages
            let d = ModeleDictees(store: exemple)
            let r = ReglagesModele(reel: false, maj: maj)
            let vue = RenduFenetre.Cadre(taille: taille) {
                FenetreVue(nav: nav, dictees: d, store: exemple, mots: MotsModele(persistant: false, mots: [], raccourcis: [], propositions: PropositionsMots()),
                           reglages: r, reunions: reunions, controleur: controleur, curseurFactice: true)
            }
            ok = RenduVues.ecrire(RenduVues.png(vue, taille: taille), url.appendingPathComponent("\(nom).png")) && ok
        }
        reglages("reglages-1-a-jour", MiseAJourModele.exemple())
        reglages("reglages-2-disponible", MiseAJourModele.exemple(disponible: "0.3.1"))
        reglages("reglages-3-telechargement", MiseAJourModele.exemple(.telechargement(0.42), disponible: "0.3.1"))
        reglages("reglages-4-depuis-image-disque", MiseAJourModele.exemple(disponible: "0.3.1", refus: "Verbe tourne depuis l\u{2019}image disque. Glisse-le dans Applications, puis rouvre-le."))
        reglages("reglages-5-hors-ligne", MiseAJourModele.exemple(message: "Impossible de vérifier : pas de connexion à GitHub.", automatique: false))
        reglages("reglages-6-petite", MiseAJourModele.exemple(disponible: "0.3.1"), taille: CGSize(width: 700, height: 1500))

        // Notes de version
        let m = MiseAJourModele.exemple(disponible: "0.3.1")
        if let p = m.disponible {
            let vue = NotesDeVersionVue(version: p.version.description, blocs: NotesDeVersion.blocs(p.notes), pageURL: URL(string: "https://github.com"), peutInstaller: true)
            ok = RenduVues.ecrire(RenduVues.png(vue, taille: CGSize(width: 460, height: 440)), url.appendingPathComponent("notes-de-version.png")) && ok
        }
        return ok ? 0 : 1
    }
}
