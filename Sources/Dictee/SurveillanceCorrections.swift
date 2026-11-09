import AppKit
import ApplicationServices
import DicteeCore

/// Lecture, par l'Accessibilité, de la zone du champ où le texte vient d'être collé, pour voir plus tard si Hugues l'a corrigé.
/// Utilisé seulement depuis l'app (jamais depuis un shell : l'autorisation serait demandée au Terminal). Chaque appel a un délai court.
enum LecteurCorrection {
    struct Zone { var debut: Int; var longueur: Int }

    private static func champFocalise(pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.15)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        let champ = ref as! AXUIElement
        AXUIElementSetMessagingTimeout(champ, 0.15)
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(champ, kAXRoleAttribute as CFString, &role)
        if (role as? String) == "AXSecureTextField" { return nil }
        return champ
    }

    private static func texte(_ champ: AXUIElement, zone: Zone) -> String? {
        var demande = CFRange(location: zone.debut, length: zone.longueur)
        if let v = AXValueCreate(.cfRange, &demande) {
            var sortie: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(champ, kAXStringForRangeParameterizedAttribute as CFString, v, &sortie) == .success,
               let s = sortie as? String, !s.isEmpty { return s }
        }
        var valeur: CFTypeRef?
        if AXUIElementCopyAttributeValue(champ, kAXValueAttribute as CFString, &valeur) == .success, let s = valeur as? String {
            let ns = s as NSString
            guard ns.length <= 200_000, zone.debut < ns.length else { return nil }
            return ns.substring(with: NSRange(location: zone.debut, length: min(zone.longueur, ns.length - zone.debut)))
        }
        return nil
    }

    /// Juste après le collage : où est le texte inséré (le curseur est derrière) et ce qu'il y a autour. `nil` si l'app ne le dit pas.
    static func lireInitiale(pid: pid_t, texte inseree: String) -> (zone: Zone, contenu: String)? {
        guard let champ = champFocalise(pid: pid) else { return nil }
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(champ, kAXSelectedTextRangeAttribute as CFString, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXValueGetTypeID() else { return nil }
        var plage = CFRange()
        guard AXValueGetValue(ref as! AXValue, .cfRange, &plage), plage.location != kCFNotFound, plage.location >= 0 else { return nil }
        let fin = plage.location + max(0, plage.length)
        let longueur = (inseree as NSString).length
        guard fin >= longueur else { return nil }
        let debut = max(0, fin - longueur - 30)
        let zone = Zone(debut: debut, longueur: (fin - debut) + 250)
        guard let contenu = texte(champ, zone: zone) else { return nil }
        // la lecture doit contenir la fin du texte inséré, sinon la zone n'est pas la bonne
        guard VerificationInsertion.normaliser(contenu).contains(VerificationInsertion.queueAttendue(inseree)) else { return nil }
        return (zone, contenu)
    }

    /// Plus tard : la même zone, un peu plus longue (une correction qui rallonge le texte ne doit pas couper le dernier mot).
    static func relire(pid: pid_t, zone: Zone) -> String? {
        guard let champ = champFocalise(pid: pid) else { return nil }
        return texte(champ, zone: Zone(debut: zone.debut, longueur: zone.longueur + 150))
    }
}

/// Apprendre des corrections de Hugues : 6 s puis 15 s après un collage réussi, la zone du champ est relue et comparée à ce que l'app
/// avait écrit. Un mot remplacé par un mot qui lui ressemble (« Brionia » → « Brillonia ») est PROPOSÉ dans « Mots » ; il n'y entre
/// jamais sans le geste de Hugues. Rien n'est lu si l'app n'expose pas le champ, ni dans un terminal, ni dans un champ protégé.
@MainActor
enum SurveillanceCorrections {
    /// Identifie ce lancement de l'app : une correction lue 6 s puis 15 s après la même dictée ne compte qu'une fois.
    nonisolated static let lancement = Int(Date().timeIntervalSince1970)
    nonisolated static let delais: [Double] = [6, 9]   // 6 s après le collage, puis 15 s

    static func lancer(texte: String, cible: NSRunningApplication?, genre: AppKind, idDictee: Int) {
        guard Settings.apprentissageDesCorrections, Permissions.accessibiliteOK, genre != .terminal,
              let cible, !cible.isTerminated, cible.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        let pid = cible.processIdentifier
        Task.detached(priority: .utility) {
            guard let (zone, avant) = LecteurCorrection.lireInitiale(pid: pid, texte: texte) else {
                Log.ecrire("dictée \(idDictee) : apprentissage impossible (l\u{2019}app n\u{2019}expose pas le champ)")
                return
            }
            for delai in delais {
                try? await Task.sleep(for: .seconds(delai))
                guard let apres = LecteurCorrection.relire(pid: pid, zone: zone) else { continue }
                let mots = await MainActor.run { ApprentissageCorrections.propositions(inseree: texte, avant: avant, apres: apres, estConnu: Orthographe.estConnu) }
                for mot in mots {
                    await MainActor.run {
                        switch MotsModele.partage.noterCorrection(mot, dictee: "\(lancement)-\(idDictee)") {
                        case .proposee: Log.ecrire("dictée \(idDictee) : mot corrigé par Hugues proposé dans Mots : \"\(Log.apercu(mot))\"")
                        case .apprise: Log.ecrire("dictée \(idDictee) : la même correction revient : \"\(Log.apercu(mot))\" appris tout seul (ajouté à tes mots)")
                        case .dejaVue, .ignoree: break
                        }
                    }
                }
            }
        }
    }
}
