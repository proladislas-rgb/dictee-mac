import AppKit
import ApplicationServices
import DicteeCore

/// Relit, par l'Accessibilité, ce qu'il y a juste avant le curseur de l'app cible : c'est la preuve que le ⌘V a écrit.
/// Utilisé seulement depuis l'app (jamais depuis un shell). Chaque appel a un délai court.
enum LecteurInsertion {
    /// Une lecture : le focus de l'app et, si elle les expose, les caractères avant le curseur.
    static func observer(pid: pid_t, texte: String) -> ObservationChamp {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.15)
        let web = estAppWeb(pid: pid)
        if web { activerAccessibiliteWeb(app) }

        var ref: CFTypeRef?
        let erreur = AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &ref)
        switch erreur {
        case .success:
            break
        case .noValue:
            // L'app répond, mais rien n'a le focus : seulement si une fenêtre existe (sinon on ne sait pas).
            var fenetre: CFTypeRef?
            // Les apps web (Electron : Claude, Slack, Notion… ; navigateurs Chromium) n'exposent souvent aucun élément focalisé
            // même quand le texte a bien été écrit : l'absence de focus n'y prouve rien.
            if !web, AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &fenetre) == .success { return ObservationChamp(focus: .aucun) }
            return ObservationChamp(focus: .inconnu)
        default:
            return ObservationChamp(focus: .inconnu)
        }
        guard let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else { return ObservationChamp(focus: .inconnu) }
        let champ = ref as! AXUIElement
        AXUIElementSetMessagingTimeout(champ, 0.15)

        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(champ, kAXRoleAttribute as CFString, &role)
        let roleTexte = role as? String
        // Champ protégé : on ne lit rien.
        if roleTexte == "AXSecureTextField" { return ObservationChamp(focus: .inconnu) }
        return ObservationChamp(focus: .element(role: roleTexte), avantLeCurseur: avantLeCurseur(champ, texte: texte))
    }

    /// Apps construites sur un moteur web : Electron (cadre « Electron Framework » dans le paquet) ou navigateurs Chromium.
    private static var cacheWeb: [pid_t: Bool] = [:]
    private static let verrouWeb = NSLock()
    static func estAppWeb(pid: pid_t) -> Bool {
        verrouWeb.lock(); defer { verrouWeb.unlock() }
        if let v = cacheWeb[pid] { return v }
        let app = NSRunningApplication(processIdentifier: pid)
        var web = false
        if let url = app?.bundleURL {
            let cadres = url.appendingPathComponent("Contents/Frameworks")
            let noms = (try? FileManager.default.contentsOfDirectory(atPath: cadres.path)) ?? []
            web = noms.contains { $0.hasPrefix("Electron Framework") || $0.hasSuffix("Framework.framework") && $0.contains("Chrom") }
        }
        let chromium: Set<String> = ["com.google.Chrome", "com.google.Chrome.beta", "com.brave.Browser", "com.microsoft.edgemac",
                                      "company.thebrowser.Browser", "com.operasoftware.Opera", "com.vivaldi.Vivaldi"]
        if let id = app?.bundleIdentifier, chromium.contains(id) { web = true }
        cacheWeb[pid] = web
        return web
    }

    /// Demande à une app Electron d'ouvrir son arbre d'Accessibilité (AXManualAccessibility) : sans cela, le champ où l'on
    /// écrit reste souvent invisible. Pas d'AXEnhancedUserInterface (il ralentit les navigateurs et coupe leurs animations).
    static func activerAccessibiliteWeb(_ app: AXUIElement) {
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    private static func avantLeCurseur(_ champ: AXUIElement, texte: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(champ, kAXSelectedTextRangeAttribute as CFString, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXValueGetTypeID() else { return nil }
        var plage = CFRange()
        guard AXValueGetValue(ref as! AXValue, .cfRange, &plage), plage.location != kCFNotFound, plage.location >= 0 else { return nil }
        // Le curseur est à la fin de la sélection (le texte collé n'est en général pas sélectionné).
        let fin = plage.location + max(0, plage.length)
        if fin == 0 { return "" }
        let n = min(fin, VerificationInsertion.longueurALire(texte))
        var demande = CFRange(location: fin - n, length: n)
        if let v = AXValueCreate(.cfRange, &demande) {
            var sortie: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(champ, kAXStringForRangeParameterizedAttribute as CFString, v, &sortie) == .success,
               let s = sortie as? String { return s }
        }
        var valeur: CFTypeRef?
        if AXUIElementCopyAttributeValue(champ, kAXValueAttribute as CFString, &valeur) == .success, let s = valeur as? String {
            let ns = s as NSString
            if fin <= ns.length { return ns.substring(with: NSRange(location: fin - n, length: n)) }
        }
        return nil
    }

    /// Relit à 250, 400 puis 650 ms après le ⌘V ; s'arrête à la première preuve d'écriture.
    static func verifier(texte: String, pid: pid_t, genre: AppKind) async -> (VerdictInsertion, lectures: Int) {
        var verdicts: [VerdictInsertion] = []
        for delai in VerificationInsertion.delaisDeRelecture {
            try? await Task.sleep(for: .milliseconds(delai))
            let observation = await Task.detached(priority: .userInitiated) { observer(pid: pid, texte: texte) }.value
            let v = VerificationInsertion.evaluer(texte: texte, observation: observation, genre: genre)
            verdicts.append(v)
            if v == .inseree { break }
            // Rien à attendre de plus : on ne peut pas lire, ou l'app n'a aucun champ actif (déjà définitif).
            if v == .indetermine { break }
        }
        return (VerificationInsertion.conclure(verdicts), verdicts.count)
    }
}
