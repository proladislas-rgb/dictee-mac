import AppKit
import Carbon.HIToolbox
import DicteeCore

/// Écrit le texte au curseur de l'app au premier plan : presse-papiers + ⌘V simulé, puis le presse-papiers
/// d'origine est remis. Jamais d'Entrée envoyé.
@MainActor
final class Collage {
    enum Issue: Equatable {
        case colle
        /// Champ mot de passe (saisie sécurisée) : on ne colle pas, le texte reste dans le presse-papiers.
        case champProtege
        /// Le collage n'a pas pu partir (accessibilité manquante) ; le texte est resté dans le presse-papiers.
        case copieSeulement(String)
        /// L'app visée n'existe plus, ou on n'a pas pu y revenir : rien n'est collé (ni touché dans le presse-papiers).
        case cibleIndisponible(String)
        case vide
    }

    private typealias Sauvegarde = [[(NSPasteboard.PasteboardType, Data)]]

    static let typeConfidentiel = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    static let typeTransitoire = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    private let presse: NSPasteboard
    private let delaiRestauration: Duration
    /// Envoie ⌘V. Remplaçable pour tester sans toucher au clavier.
    private let envoyerCommandeV: () -> Void
    private let saisieSecurisee: () -> Bool

    /// Restauration en attente : si on recolle avant qu'elle ait eu lieu, le contenu d'origine est conservé.
    private var restauration: (sauvegarde: Sauvegarde, compteur: Int, tache: Task<Void, Never>)?

    init(presse: NSPasteboard = .general,
         delaiRestauration: Duration = .milliseconds(600),
         envoyerCommandeV: @escaping () -> Void = Collage.posterCommandeV,
         saisieSecurisee: @escaping () -> Bool = { IsSecureEventInputEnabled() }) {
        self.presse = presse
        self.delaiRestauration = delaiRestauration
        self.envoyerCommandeV = envoyerCommandeV
        self.saisieSecurisee = saisieSecurisee
    }

    /// `texte` est déjà mis en forme pour l'app cible. `cible` : l'app qui était au premier plan au début de la dictée.
    func ecrire(_ texte: String, dans cible: NSRunningApplication?, permissionPoster: Bool = Permissions.accessibiliteOK) async -> Issue {
        guard !texte.isEmpty else { return .vide }

        if saisieSecurisee() {
            // Pas de collage dans un champ protégé. Texte laissé dans le presse-papiers, de façon normale (collable à la main).
            presse.clearContents()
            presse.setString(texte, forType: .string)
            return .champProtege
        }
        guard permissionPoster else {
            presse.clearContents()
            presse.setString(texte, forType: .string)
            return .copieSeulement("accessibilité non accordée")
        }

        // 0. l'app visée : elle doit exister, et on revient dedans si l'écran a changé pendant la dictée
        if let cible {
            if cible.isTerminated { return .cibleIndisponible("l\u{2019}app visée n\u{2019}existe plus") }
            if NSWorkspace.shared.frontmostApplication?.processIdentifier != cible.processIdentifier {
                Log.ecrire("collage : l'app au premier plan a changé, retour dans \(cible.bundleIdentifier ?? "?")")
                cible.activate()
                for _ in 0..<15 {
                    try? await Task.sleep(for: .milliseconds(20))
                    if NSWorkspace.shared.frontmostApplication?.processIdentifier == cible.processIdentifier { break }
                }
                if NSWorkspace.shared.frontmostApplication?.processIdentifier != cible.processIdentifier {
                    return .cibleIndisponible("l\u{2019}app visée n\u{2019}a pas pu reprendre le clavier")
                }
            }
        }

        // 1. sauvegarder tout le presse-papiers (ou reprendre celle d'un collage précédent pas encore restauré)
        let sauvegarde: Sauvegarde
        if let attente = restauration {
            attente.tache.cancel()
            sauvegarde = attente.sauvegarde
            restauration = nil
        } else {
            sauvegarde = lireTout()
        }

        // 2. écrire le texte, marqué confidentiel pour les gestionnaires de presse-papiers
        presse.clearContents()
        presse.setString(texte, forType: .string)
        presse.setData(Data(), forType: Collage.typeConfidentiel)
        presse.setData(Data(), forType: Collage.typeTransitoire)
        let compteur = presse.changeCount

        // 4. ⌘V
        envoyerCommandeV()

        // 5. rendre l'ancien presse-papiers un peu plus tard, sauf s'il a changé entre-temps
        let tache = Task { [weak self, delaiRestauration] in
            try? await Task.sleep(for: delaiRestauration)
            guard !Task.isCancelled else { return }
            self?.restaurer(sauvegarde, siCompteur: compteur)
        }
        restauration = (sauvegarde, compteur, tache)
        return .colle
    }

    private func restaurer(_ sauvegarde: Sauvegarde, siCompteur compteur: Int) {
        restauration = nil
        guard presse.changeCount == compteur else {
            Log.ecrire("collage : le presse-papiers a changé entre-temps, on ne le touche pas")
            return
        }
        presse.clearContents()
        guard !sauvegarde.isEmpty else { return }
        let elements = sauvegarde.map { types -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in types { item.setData(data, forType: type) }
            return item
        }
        presse.writeObjects(elements)
    }

    private func lireTout() -> Sauvegarde {
        (presse.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
    }

    /// ⌘V avec une source d'événements privée (aucun mélange avec les touches physiques tenues) et une marque
    /// que l'écoute du clavier reconnaît pour ne pas se lire elle-même.
    nonisolated static func posterCommandeV() {
        guard let source = CGEventSource(stateID: .privateState) else { return }
        let toucheV = CGKeyCode(kVK_ANSI_V)
        for bas in [true, false] {
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: toucheV, keyDown: bas) else { continue }
            e.flags = .maskCommand
            e.setIntegerValueField(.eventSourceUserData, value: KeyMonitor.marqueInterne)
            e.post(tap: .cghidEventTap)
        }
    }
}
