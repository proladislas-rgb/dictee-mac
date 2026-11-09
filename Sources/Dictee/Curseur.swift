import AppKit
import ApplicationServices

/// Ce qu'on peut savoir du champ qui a le focus dans l'app cible, par l'Accessibilité.
struct ContexteChamp {
    /// Les derniers caractères avant le curseur (`""` = début du champ, `nil` = inconnu).
    var precedent: String?
    /// Rôle d'Accessibilité du champ (AXTextField, AXTextArea, AXWebArea…).
    var role: String?
    /// Titre de la fenêtre au premier plan (sert à reconnaître Gmail, Google Docs, ChatGPT… dans un navigateur).
    var titreFenetre: String?
    /// Comment `precedent` a été obtenu (journal).
    var methode = "aucune"
}

/// Lecture du champ focalisé via l'Accessibilité. Utilisé seulement depuis l'app (jamais depuis un shell :
/// l'autorisation serait demandée au Terminal). Chaque appel a un délai court : une app qui ne répond pas
/// ne doit pas retarder le collage.
enum LecteurCurseur {
    static let longueurLue = 200

    static func lire(pid: pid_t) -> ContexteChamp {
        var contexte = ContexteChamp()
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.15)

        if let fenetre = element(app, kAXFocusedWindowAttribute) {
            contexte.titreFenetre = texte(fenetre, kAXTitleAttribute)
        }
        guard let champ = element(app, kAXFocusedUIElementAttribute) else { return contexte }
        AXUIElementSetMessagingTimeout(champ, 0.15)
        contexte.role = texte(champ, kAXRoleAttribute)
        // Champ de mot de passe : on ne lit rien (et on ne colle pas non plus).
        if contexte.role == "AXSecureTextField" { return contexte }

        guard let plage = plageSelection(champ) else { return contexte }
        if plage.location == 0 { contexte.precedent = ""; contexte.methode = "AX début"; return contexte }
        let debut = max(0, plage.location - longueurLue)
        var demande = CFRange(location: debut, length: plage.location - debut)
        if let v = AXValueCreate(.cfRange, &demande) {
            var sortie: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(champ, kAXStringForRangeParameterizedAttribute as CFString, v, &sortie) == .success,
               let s = sortie as? String, !s.isEmpty {
                contexte.precedent = s; contexte.methode = "AX plage"
                return contexte
            }
        }
        if let valeur = texte(champ, kAXValueAttribute) {
            let ns = valeur as NSString
            if plage.location <= ns.length {
                contexte.precedent = ns.substring(with: NSRange(location: debut, length: plage.location - debut))
                contexte.methode = "AX valeur"
            }
        }
        return contexte
    }

    private static func element(_ source: AXUIElement, _ attribut: String) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(source, attribut as CFString, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        return (ref as! AXUIElement)
    }

    private static func texte(_ source: AXUIElement, _ attribut: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(source, attribut as CFString, &ref) == .success else { return nil }
        return ref as? String
    }

    private static func plageSelection(_ champ: AXUIElement) -> CFRange? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(champ, kAXSelectedTextRangeAttribute as CFString, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXValueGetTypeID() else { return nil }
        var plage = CFRange()
        guard AXValueGetValue(ref as! AXValue, .cfRange, &plage), plage.location != kCFNotFound, plage.location >= 0 else { return nil }
        return plage
    }
}

/// Deux lectures du champ focalisé : une à l'appui sur fn, une au relâchement. Quand le texte est prêt, on prend la plus
/// récente déjà terminée ; on n'attend la lecture du relâchement que si l'appui n'a rien donné. Comme ça, un texte de Groq
/// qui arrive tout de suite (envoi anticipé) n'attend jamais l'Accessibilité.
final class LectureChamp: @unchecked Sendable {
    private let verrou = NSLock()
    private var debut: ContexteChamp?
    private var fin: ContexteChamp?
    private var tacheFin: Task<ContexteChamp, Never>?

    func lireAuDebut(pid: pid_t) {
        Task.detached(priority: .userInitiated) { [self] in
            noterDebut(LecteurCurseur.lire(pid: pid))
        }
    }

    private func noterDebut(_ c: ContexteChamp) { verrou.lock(); debut = c; verrou.unlock() }
    private func noterFin(_ c: ContexteChamp) { verrou.lock(); fin = c; verrou.unlock() }
    private func garder(_ t: Task<ContexteChamp, Never>) { verrou.lock(); tacheFin = t; verrou.unlock() }

    func lireALaFin(pid: pid_t) {
        let t = Task.detached(priority: .userInitiated) { [self] () -> ContexteChamp in
            let c = LecteurCurseur.lire(pid: pid)
            noterFin(c)
            return c
        }
        garder(t)
    }

    private func pret() -> (ContexteChamp?, Task<ContexteChamp, Never>?, source: String) {
        verrou.lock(); defer { verrou.unlock() }
        if let fin { return (fin, nil, "relâchement") }
        if let debut { return (debut, nil, "appui") }
        return (nil, tacheFin, "relâchement")
    }

    /// Ce qu'on sait déjà du champ (lecture la plus récente terminée), sans attendre.
    func dejaConnu() -> ContexteChamp? {
        verrou.lock(); defer { verrou.unlock() }
        return fin ?? debut
    }

    /// Le champ, sans attendre si une lecture est déjà prête. `source` va au journal.
    func contexte() async -> (ContexteChamp?, source: String) {
        let (c, tache, source) = pret()
        if let c { return (c, source) }
        if let tache { return (await tache.value, source) }
        return (nil, "aucune")
    }
}
