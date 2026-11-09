import AppKit
import ApplicationServices
import DicteeCore

/// Repli pour l'image de la lecture en cours : quand le navigateur n'a envoyé aucune image au système (Chrome sur YouTube), on retrouve
/// l'identifiant de la vidéo dans l'adresse de l'onglet qui joue (lue par l'Accessibilité, dans le champ d'adresse de la fenêtre dont le
/// titre est celui du média : aucune autorisation de plus) puis on télécharge la miniature publique de YouTube.
///
/// La miniature (320 × 180, environ 10 Ko) est gardée sur disque par identifiant dans ~/Library/Caches/com.hugues.dictee/miniatures
/// (0600, 40 fichiers au plus, supprimée avec le cache à la désinstallation). Jamais bloquant : tout est asynchrone, avec délais courts.
enum MiniatureLecture {
    static let dossier: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Caches/\(Desinstallation.identifiant)/miniatures", isDirectory: true)
    static let tailleMax = 400_000
    static let nombreMax = 40

    static func fichier(pour identifiant: String) -> URL { dossier.appendingPathComponent("\(identifiant).jpg") }

    /// La miniature en cache, sans réseau.
    static func enCache(_ identifiant: String) -> NSImage? {
        guard MiniatureYouTube.estIdentifiant(identifiant), let d = try? Data(contentsOf: fichier(pour: identifiant)) else { return nil }
        return image(d)
    }

    private static func image(_ donnees: Data) -> NSImage? {
        guard donnees.count > 200, donnees.count <= tailleMax, let i = NSImage(data: donnees), i.size.width >= 16, i.size.height >= 16 else { return nil }
        return i
    }

    /// Le résultat d'un chargement : d'où vient l'image (pour les essais).
    enum Origine: String { case cache, reseau }

    /// La miniature de la vidéo : le cache d'abord, sinon un téléchargement (5 s au plus), puis mise en cache. nil si rien (hors ligne,
    /// vidéo privée…) : l'appelant retombe sur l'icône de l'app.
    static func charger(identifiant: String) async -> (image: NSImage, origine: Origine)? {
        if let i = enCache(identifiant) { return (i, .cache) }
        guard let url = MiniatureYouTube.adresseMiniature(identifiant: identifiant) else { return nil }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 8
        config.httpCookieStorage = nil
        config.urlCache = nil
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }
        var requete = URLRequest(url: url)
        requete.setValue("image/jpeg", forHTTPHeaderField: "Accept")
        guard let (donnees, reponse) = try? await session.data(for: requete),
              (reponse as? HTTPURLResponse)?.statusCode == 200, let i = image(donnees) else { return nil }
        ecrire(donnees, identifiant: identifiant)
        return (i, .reseau)
    }

    private static func ecrire(_ donnees: Data, identifiant: String) {
        let fm = FileManager.default
        try? fm.createDirectory(at: dossier, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let f = fichier(pour: identifiant)
        try? donnees.write(to: f, options: .atomic)
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: f.path)
        elaguer()
    }

    /// Garde les `nombreMax` miniatures les plus récentes.
    static func elaguer() {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: dossier, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let jpg = urls.filter { $0.pathExtension == "jpg" }
        guard jpg.count > nombreMax else { return }
        let datees = jpg.map { ($0, (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
        for (u, _) in datees.sorted(by: { $0.1 > $1.1 }).dropFirst(nombreMax) { try? fm.removeItem(at: u) }
    }

    // MARK: l'adresse de l'onglet qui joue (Accessibilité)

    /// L'identifiant de la vidéo YouTube de la fenêtre du navigateur (processus `pid`) dont le titre est celui du média. Lit le champ
    /// d'adresse (un champ de texte nommé « adresse » / « address », ou le premier champ de la barre d'outils) ; sinon l'attribut
    /// AXDocument de la fenêtre. nil si la fenêtre n'est pas affichée (onglet en arrière-plan), si l'adresse est masquée ou n'est pas
    /// celle d'une vidéo : on ne devine jamais. Bloquant (quelques dizaines de ms) : à appeler hors du fil principal.
    nonisolated static func identifiantDeLOnglet(pid: Int, titreMedia: String) -> String? {
        let app = AXUIElementCreateApplication(pid_t(pid))
        AXUIElementSetMessagingTimeout(app, 0.3)
        guard let fenetres: [AXUIElement] = valeur(app, kAXWindowsAttribute) else { return nil }
        for f in fenetres.prefix(12) {
            AXUIElementSetMessagingTimeout(f, 0.3)
            guard let titre: String = valeur(f, kAXTitleAttribute), SourceLecture.fenetreMontre(titreFenetre: titre, titreMedia: titreMedia) else { continue }
            for adresse in adresses(de: f) {
                if let id = MiniatureYouTube.identifiant(adresse: adresse) { return id }
            }
        }
        return nil
    }

    nonisolated private static func valeur<T>(_ e: AXUIElement, _ attribut: String) -> T? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, attribut as CFString, &ref) == .success, let ref else { return nil }
        return ref as? T
    }

    /// Les textes qui peuvent être l'adresse de la page affichée dans une fenêtre.
    nonisolated private static func adresses(de fenetre: AXUIElement) -> [String] {
        var sortie: [String] = []
        if let doc: String = valeur(fenetre, kAXDocumentAttribute) { sortie.append(doc) }
        // parcours en largeur, borné : profondeur 8, 300 éléments
        var file: [(AXUIElement, Int, Bool)] = [(fenetre, 0, false)]
        var vus = 0
        while !file.isEmpty, vus < 300 {
            let (e, profondeur, barreOutils) = file.removeFirst()
            vus += 1
            let role: String = valeur(e, kAXRoleAttribute) ?? ""
            if role == kAXTextFieldRole as String || role == kAXComboBoxRole as String {
                let nom = ["AXDescription", kAXTitleAttribute, "AXIdentifier", kAXHelpAttribute]
                    .compactMap { (a: String) -> String? in valeur(e, a) }.joined(separator: " ").lowercased()
                let etiquette = nom.contains("adresse") || nom.contains("address") || nom.contains("omnibox") || nom.contains("url")
                if etiquette || barreOutils, let v: String = valeur(e, kAXValueAttribute) { sortie.append(v) }
                continue   // un champ n'a pas d'enfants utiles
            }
            if role == "AXWebArea" { continue }   // le contenu de la page : jamais (une adresse collée dans un champ de la page n'est pas la page)
            guard profondeur < 8, let enfants: [AXUIElement] = valeur(e, kAXChildrenAttribute) else { continue }
            let dansBarre = barreOutils || role == kAXToolbarRole as String
            for c in enfants.prefix(40) { file.append((c, profondeur + 1, dansBarre)) }
        }
        return sortie
    }
}
