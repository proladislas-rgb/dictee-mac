import AppKit

/// L'icône réelle d'une app d'après son identifiant de paquet (NSWorkspace), gardée en mémoire : la liste des dictées
/// la réclame à chaque ligne, le disque n'est lu qu'une fois par app.
@MainActor
enum IconesApps {
    private static var memoire: [String: NSImage?] = [:]

    /// `nil` si l'app n'est pas (ou plus) installée : la vue dessine alors une pastille neutre.
    static func icone(appId: String?) -> NSImage? {
        guard let appId, !appId.isEmpty else { return nil }
        if let connue = memoire[appId] { return connue }
        var image: NSImage?
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appId) {
            image = NSWorkspace.shared.icon(forFile: url.path)
        }
        memoire[appId] = .some(image)
        return image
    }
}
