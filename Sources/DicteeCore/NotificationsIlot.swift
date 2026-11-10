import Foundation

/// Une notification d'une autre app, telle que l'îlot l'affiche. Rien n'est gardé : elle est montrée 4 secondes puis oubliée.
public struct NotificationRecue: Equatable, Sendable {
    public var app: String
    public var titre: String
    public var corps: String
    public var date: Date
    public init(app: String, titre: String, corps: String, date: Date) {
        self.app = app; self.titre = titre; self.corps = corps; self.date = date
    }
}

public enum LectureNotifications {
    /// Les textes visibles d'une bannière de notification, dans l'ordre où l'Accessibilité les donne. Les bannières de macOS affichent
    /// [nom de l'app], titre, texte (parfois sans le nom de l'app). Le premier texte est pris pour le nom de l'app seulement s'il en
    /// existe trois ou s'il est dans `nomsDApps`.
    public static func depuis(textes brut: [String], nomsDApps: Set<String> = [], date: Date) -> NotificationRecue? {
        var textes: [String] = []
        for t in brut {
            let s = t.trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty, textes.last != s { textes.append(s) }
        }
        // on ignore ce qui n'est qu'un bouton ou une heure (« Fermer », « maintenant », « Afficher »)
        let bruit: Set<String> = ["fermer", "close", "afficher", "show", "options", "effacer", "clear", "maintenant", "now"]
        textes.removeAll { bruit.contains($0.lowercased()) }
        guard !textes.isEmpty else { return nil }
        func limite(_ s: String, _ n: Int) -> String { s.count > n ? String(s.prefix(n)) + "\u{2026}" : s }
        if textes.count >= 3 {
            return NotificationRecue(app: textes[0], titre: limite(textes[1], 80), corps: limite(textes[2...].joined(separator: " "), 160), date: date)
        }
        if textes.count == 2 {
            if nomsDApps.contains(textes[0]) { return NotificationRecue(app: textes[0], titre: limite(textes[1], 80), corps: "", date: date) }
            return NotificationRecue(app: "", titre: limite(textes[0], 80), corps: limite(textes[1], 160), date: date)
        }
        return NotificationRecue(app: "", titre: limite(textes[0], 80), corps: "", date: date)
    }

    /// La ligne d'un groupe : « Camille · Banque · Équipe projet » (noms distincts, dans l'ordre d'arrivée, 3 au plus).
    public static func ligneDeGroupe(_ n: [NotificationRecue]) -> String {
        var vus: [String] = []
        for x in n {
            let nom = x.titre.isEmpty ? x.app : x.titre
            if !nom.isEmpty, !vus.contains(nom) { vus.append(nom) }
        }
        let tete = vus.prefix(3).joined(separator: " \u{00B7} ")
        return vus.count > 3 ? tete + " \u{2026}" : tete
    }
    public static func titreDeGroupe(_ nombre: Int) -> String { "\(nombre) nouvelles notifications" }

    /// L'ajout d'une notification à celles qui sont encore affichées : dans la fenêtre de regroupement, elle s'y fond.
    public static let fenetre: Double = 4.2
    public static func ajouter(_ nouvelle: NotificationRecue, a affichees: [NotificationRecue], maintenant: Date) -> [NotificationRecue] {
        let recentes = affichees.filter { maintenant.timeIntervalSince($0.date) <= fenetre + 4 }
        return Array((recentes + [nouvelle]).suffix(20))
    }
}
