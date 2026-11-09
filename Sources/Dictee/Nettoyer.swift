import Foundation
import DicteeCore

/// Mode de vérification sans micro : `Dictee --nettoyer "texte" --app com.apple.mail [--role AXTextField] [--titre "Gmail"]`
/// Passe le texte par la même remise au propre qu'une vraie dictée (réseau seulement), affiche le résultat et la durée.
enum Nettoyer {
    static func executer(arguments: [String]) -> Int32 {
        func valeur(_ nom: String) -> String? {
            guard let i = arguments.firstIndex(of: nom), i + 1 < arguments.count else { return nil }
            return arguments[i + 1]
        }
        guard let texte = valeur("--nettoyer") else {
            FileHandle.standardError.write(Data("Usage : Dictee --nettoyer \"texte\" [--app com.apple.mail] [--role AXTextField] [--titre \"Gmail\"] [--avant \"texte avant le curseur\"] [--relecture-seule] [--expressions \"a;b\"]\n".utf8)); return 2
        }
        guard GroqClient.shared.cleDisponible else {
            FileHandle.standardError.write(Data("Clé Groq introuvable (~/.config/groq/.env)\n".utf8)); return 2
        }
        let contexte = RemiseAuPropre.contexte(bundleID: valeur("--app"), role: valeur("--role"), titreFenetre: valeur("--titre"))
        let sortie: Int32 = 0
        let fini = DispatchSemaphore(value: 0)
        Task {
            GroqClient.shared.prechauffer()
            try? await Task.sleep(for: .milliseconds(300))
            let session = RelectureSession(champ: { ContexteChamp(precedent: valeur("--avant"), role: valeur("--role"), titreFenetre: valeur("--titre")) },
                                          expressionsEnPlus: (valeur("--expressions") ?? "").split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) })
            // --relecture-seule : comme une courte dictée déjà propre (pas de remise au propre, seulement la relecture de sens si elle se déclenche)
            let r = await Nettoyage.executer(texte, contexte: contexte, mots: Dictionnaire.mots(), forcer: !arguments.contains("--relecture-seule"), relecture: session)
            let final = TextFormatter.prepare(r.texte, for: TextFormatter.kind(bundleID: valeur("--app")))
            print("contexte : \(contexte.rawValue)")
            print("avant    : \(texte)")
            print("après    : \(final.replacingOccurrences(of: "\n", with: "⏎\n           "))")
            print(String(format: "— %@, %.0f ms (%@)", r.utilise ? "remis au propre" : "texte brut gardé", r.duree * 1000, r.raison))
            if let rel = r.relecture { print("relecture : \(rel)") }
            if let refusee = r.sortieRefusee { print("IA disait : \(refusee.replacingOccurrences(of: "\n", with: "⏎"))") }
            fini.signal()
        }
        // Le correcteur orthographique vit sur le fil principal : on le laisse tourner pendant l'attente.
        while fini.wait(timeout: .now() + 0.01) == .timedOut { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        Log.vider()
        return sortie
    }
}
