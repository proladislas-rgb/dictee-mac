import Foundation
import DicteeCore

/// `Verbe --comparer-precision` : repasse les sons gardés par le test de précision (`test-precision/`) en turbo, en large-v3, puis large-v3 avec
/// la relecture de sens, et affiche les différences. Réseau seulement (ni micro, ni accessibilité, ni clavier). Propose d'effacer les sons à la fin.
/// Quotas Groq respectés : une dictée à la fois, attente quand la minute est chargée.
@MainActor
enum ComparerPrecision {
    struct Passage { var turbo = ""; var large = ""; var largeSans = ""; var largeRelue = ""; var relectureDit = "" }

    static func executer(arguments: [String]) async -> Int32 {
        guard GroqClient.shared.cleDisponible else { FileHandle.standardError.write(Data("Clé Groq introuvable (~/.config/groq/.env)\n".utf8)); return 2 }
        let dossier = TestPrecisionStore.dossier
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let noms = TestPrecisionStore.fichiers().filter { $0.hasSuffix(".json") }.sorted()
        let echantillons: [(EchantillonPrecision, URL)] = noms.compactMap { nom in
            guard let d = try? Data(contentsOf: dossier.appendingPathComponent(nom)), let e = try? dec.decode(EchantillonPrecision.self, from: d) else { return nil }
            return (e, dossier.appendingPathComponent(nom.replacingOccurrences(of: ".json", with: ".wav")))
        }
        guard !echantillons.isEmpty else {
            print("Aucun son dans \(dossier.path). Active d'abord « Garder le son des \(TestPrecision.nombreDeDictees) prochaines dictées » dans Réglages.")
            return 0
        }
        Settings.delaiRelectureForce = 2.5   // on juge la qualité de la relecture, pas son délai
        print("Test de précision : \(echantillons.count) dictée\(echantillons.count > 1 ? "s" : "") à repasser (turbo, large-v3, large-v3 + relecture). Une à la fois, quotas Groq respectés.\n")
        var lignes: [(EchantillonPrecision, Passage)] = []
        for (i, (meta, wav)) in echantillons.enumerated() {
            guard FileManager.default.fileExists(atPath: wav.path) else { continue }
            var p = Passage()
            for modele in [ModeleWhisper.rapide, .precis] {
                await attendre(modele)
                Settings.modeleForce = modele
                guard let essai = await Transcrire.unEssai(url: wav, tempsReel: false, nettoyage: false, bundle: meta.appId, lexique: true) else { continue }
                if modele == .rapide { p.turbo = essai.texte } else { p.large = essai.texte }
            }
            Settings.modeleForce = nil
            // la remise au propre est faite des deux côtés (avec et sans relecture) pour ne comparer que l'effet de la relecture
            let contexte = RemiseAuPropre.contexte(bundleID: meta.appId, role: nil, titreFenetre: nil)
            let mots = Dictionnaire.mots()
            await attendreNettoyage()
            let sans = await Nettoyage.executer(p.large, contexte: contexte, mots: mots, relecture: nil)
            await attendreNettoyage()
            let session = RelectureSession(champ: { nil })
            let avec = await Nettoyage.executer(p.large, contexte: contexte, mots: mots, relecture: session)
            p.largeSans = sans.texte; p.largeRelue = avec.texte; p.relectureDit = avec.relecture ?? ""
            lignes.append((meta, p))
            print("  \(i + 1)/\(echantillons.count) \(TestPrecision.nomDeFichier(numero: meta.numero)) repassée")
        }
        imprimer(lignes)
        return proposerDEffacer(dossier: dossier, nombre: echantillons.count, arguments: arguments)
    }

    private static func attendre(_ modele: ModeleWhisper) async {
        while BudgetRequetes.whisper(modele).restantMinute() < 10 { try? await Task.sleep(for: .milliseconds(500)) }
    }
    private static func attendreNettoyage() async {
        while BudgetRequetes.nettoyage.restantMinute() < 6 { try? await Task.sleep(for: .milliseconds(500)) }
    }

    private static func imprimer(_ lignes: [(EchantillonPrecision, Passage)]) {
        var differentes = 0, turboDifferent = 0, relectureAChange = 0
        print("\n=== Différences (la ponctuation et les majuscules seules ne comptent pas) ===")
        for (meta, p) in lignes {
            let ecartModeles = TestPrecision.different(p.turbo, p.large)
            let ecartRelecture = TestPrecision.different(p.largeSans, p.largeRelue)
            let ecartFinal = TestPrecision.different(meta.texteFinal, p.largeRelue)
            if ecartModeles { turboDifferent += 1 }
            if ecartRelecture { relectureAChange += 1 }
            guard ecartModeles || ecartRelecture || ecartFinal else { continue }
            differentes += 1
            print("\n#\(meta.numero) \(meta.appNom ?? meta.appId ?? "?"), \(String(format: "%.1f", meta.duree)) s")
            print("  écrit alors (\(meta.modele)) : \(meta.texteFinal)")
            print("  turbo                  : \(p.turbo)")
            print("  large-v3               : \(p.large)")
            if ecartRelecture { print("  large-v3 + relecture   : \(p.largeRelue)   [\(p.relectureDit)]") }
        }
        print("\n=== Résumé ===")
        print("\(lignes.count) dictées repassées ; \(differentes) avec une différence.")
        print("turbo ≠ large-v3 : \(turboDifferent) ; la relecture a changé le texte de large-v3 : \(relectureAChange).")
        print("Pour juger : relis les lignes ci-dessus et compte celles où large-v3 ou la relecture est plus juste que ce qui avait été écrit.")
    }

    private static func proposerDEffacer(dossier: URL, nombre: Int, arguments: [String]) -> Int32 {
        guard isatty(0) != 0 else {
            print("\nLes sons restent dans \(dossier.path). Pour les effacer : rm -r \"\(dossier.path)\"")
            return 0
        }
        print("\nEffacer les \(nombre) sons et textes gardés dans \(dossier.path) ? [o/N] ", terminator: "")
        let reponse = (readLine() ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        if reponse == "o" || reponse == "oui" {
            try? FileManager.default.removeItem(at: dossier)
            print("Sons effacés.")
        } else {
            print("Sons gardés.")
        }
        return 0
    }
}
