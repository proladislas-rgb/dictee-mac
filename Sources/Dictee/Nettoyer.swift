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
            FileHandle.standardError.write(Data("Usage : Dictee --nettoyer \"texte\" [--app com.apple.mail] [--role AXTextField] [--titre \"Gmail\"]\n".utf8)); return 2
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
            let r = await Nettoyage.executer(texte, contexte: contexte, mots: Dictionnaire.mots(), forcer: true)
            let final = TextFormatter.prepare(r.texte, for: TextFormatter.kind(bundleID: valeur("--app")))
            print("contexte : \(contexte.rawValue)")
            print("avant    : \(texte)")
            print("après    : \(final.replacingOccurrences(of: "\n", with: "⏎\n           "))")
            print(String(format: "— %@, %.0f ms (%@)", r.utilise ? "remis au propre" : "texte brut gardé", r.duree * 1000, r.raison))
            if let refusee = r.sortieRefusee { print("IA disait : \(refusee.replacingOccurrences(of: "\n", with: "⏎"))") }
            fini.signal()
        }
        fini.wait()
        Log.vider()
        return sortie
    }
}
