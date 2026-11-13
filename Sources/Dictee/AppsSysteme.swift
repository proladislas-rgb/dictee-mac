import AppKit
import Security
import DicteeCore

// Ce qui touche au vrai système pour « Tes apps » : le Trousseau (les clés Notion et Airtable), l'app Mail (AppleScript), et la façade
// construite avec eux. Les essais et contrôles ne passent JAMAIS par ici : ils donnent un coffre en mémoire, un faux Mail, un faux réseau.

/// Les clés de « Tes apps » dans le Trousseau, comme la clé Groq (même service, un compte par app). Jamais affichées ni écrites au journal.
final class TrousseauApps: CoffreCles {
    private func requete(_ app: AppBranchee) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Desinstallation.serviceTrousseau, kSecAttrAccount as String: app.rawValue]
    }

    func lire(_ app: AppBranchee) -> String? {
        guard app.demandeUneCle else { return nil }
        var q = requete(app)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var sortie: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &sortie) == errSecSuccess, let d = sortie as? Data,
              let cle = String(data: d, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !cle.isEmpty else { return nil }
        return cle
    }

    @discardableResult
    func ranger(_ cle: String, pour app: AppBranchee) -> Bool {
        guard app.demandeUneCle, let d = cle.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8), !d.isEmpty else { return false }
        SecItemDelete(requete(app) as CFDictionary)
        var q = requete(app)
        q[kSecValueData as String] = d
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        let statut = SecItemAdd(q as CFDictionary, nil)
        if statut != errSecSuccess { Log.ecrire("apps : Trousseau refuse la clé \(app.rawValue) (code \(statut))") }
        return statut == errSecSuccess
    }

    func effacer(_ app: AppBranchee) { SecItemDelete(requete(app) as CFDictionary) }

    /// La désinstallation : toutes les clés de « Tes apps ».
    static func effacerTout() {
        let t = TrousseauApps()
        for a in AppBranchee.allCases where a.demandeUneCle { t.effacer(a) }
    }
}

/// L'app Mail, par AppleScript (autorisation « Automatisation » de macOS, demandée par macOS au premier passage). Un script à la fois,
/// sur une file à part (jamais sur le fil principal) ; jamais lancé si Mail ne tourne pas (AppleScript l'ouvrirait).
final class MailAppleScript: SourceMail {
    static let identifiant = "com.apple.mail"
    private let file = DispatchQueue(label: "voxile.apps.mail", qos: .utility)

    func estOuvert() async -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.identifiant).isEmpty
    }

    func nonLus(depuisSecondes secondes: Int, max: Int) async throws(ErreurApp) -> [MessageMail] {
        let texte = ScriptMail.texte(depuisSecondes: secondes, max: max)
        let r: Result<String, ErreurApp> = await withCheckedContinuation { suite in
            file.async {
                var erreur: NSDictionary?
                let sortie = NSAppleScript(source: texte)?.executeAndReturnError(&erreur)
                if let erreur {
                    suite.resume(returning: .failure(ScriptMail.erreur(code: (erreur[NSAppleScript.errorNumber] as? Int) ?? 0)))
                } else {
                    suite.resume(returning: .success(sortie?.stringValue ?? ""))
                }
            }
        }
        return ScriptMail.analyser(try r.get(), maintenant: Date())
    }
}

extension AppsBranchees {
    /// La façade de l'app : le Trousseau, la vraie Mail, le vrai réseau, le fichier `apps.json` du dossier de Voxile, le journal.
    /// `agenda` : les rendez-vous que l'îlot lit déjà (`IlotControleur.agenda.prochains(depuis:)`).
    @MainActor
    static func reelle(agenda: @escaping @MainActor @Sendable () -> [EvenementAgenda]) -> AppsBranchees {
        AppsBranchees(magasin: MagasinJSON(url: DossierVerbe.url("apps.json"), nom: "apps", journal: { Log.ecrire($0) }),
                      coffre: TrousseauApps(), transport: TransportURLSession(), mail: MailAppleScript(), agenda: agenda,
                      heure: { FormatIlot.heure($0) }, journal: { Log.ecrire($0) })
    }
}
