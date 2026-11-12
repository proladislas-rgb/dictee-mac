import DicteeCore
import Foundation

/// `Verbe --voix-mesure piste-eux.wav [--verite tours.tsv] [--modeles DOSSIER]` : la vraie séparation des voix (FluidAudio, sur ce Mac)
/// sur un fichier son 16 kHz mono 16 bits, avec ses mesures : téléchargement et taille du modèle, temps, mémoire maximale du processus.
/// Avec `--verite` (une ligne par tour : début, fin, voix, texte, séparés par des tabulations — un son fabriqué dont on connaît les
/// voix), la justesse : part du temps de parole donné à la bonne voix, et part des passages de la transcription qui reçoivent le bon
/// orateur (la transcription est simulée : chaque tour coupé en phrases, heures décalées comme celles de Whisper).
/// Ni micro, ni son du Mac, ni Groq : seul le premier téléchargement du modèle passe par le réseau. `--modeles` : dossier des modèles
/// (par défaut celui de Verbe, ~/Library/Application Support/Dictee/Modeles).
enum MesureVoix {
    static func executer(chemin: String, arguments: [String]) -> Int32 {
        func option(_ nom: String) -> String? { arguments.firstIndex(of: nom).flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil } }
        let modeles = option("--modeles").map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true) } ?? SeparationVoixLocale.dossierParDefaut
        let verite = option("--verite")
        var sortie: Int32 = 0
        let fini = DispatchSemaphore(value: 0)
        Task.detached {
            sortie = await lancer(URL(fileURLWithPath: chemin), modeles: modeles, verite: verite)
            fini.signal()
        }
        fini.wait()
        Log.vider()
        return sortie
    }

    static func taille(_ dossier: URL) -> Int {
        let fm = FileManager.default
        guard let e = fm.enumerator(at: dossier, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]) else { return 0 }
        var total = 0
        for case let u as URL in e {
            let v = try? u.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey])
            if v?.isRegularFile == true { total += v?.totalFileAllocatedSize ?? 0 }
        }
        return total
    }

    private static func mo(_ octets: UInt64) -> String { String(format: "%.0f Mo", Double(octets) / 1_048_576) }

    private static func lancer(_ url: URL, modeles: URL, verite: String?) async -> Int32 {
        let avant = MemoireProcessus.empreinte()
        print("modèles : \(modeles.path)\(SeparationVoixLocale.modelePresent(modeles) ? "" : " (absents : téléchargement)")")
        let dernier = Verrouille<Int>(-1)
        do {
            let (voix, m) = try await SeparationVoixLocale.separer(url, modeles: modeles) { a in
                if case .telechargement(let p) = a {
                    let pc = Int(p * 100) / 10 * 10
                    if dernier.remplacer(pc) != pc { print("  téléchargement \(pc) %") }
                }
            }
            let apres = MemoireProcessus.empreinte()   // le séparateur et ses modèles sont déjà libérés ici
            let nVoix = Set(voix.tours.map(\.voix)).count
            print(String(format: "son : %.1f min", m.dureeSon / 60))
            print("modèle : \(m.telecharge ? "téléchargé" : "déjà là"), \(mo(UInt64(taille(SeparationVoixLocale.dossierDuModele(modeles))))) sur le disque, chargé en \(String(format: "%.1f", m.chargement)) s")
            print(String(format: "séparation : %.1f s (%.0f× plus vite que le temps réel)", m.separation, m.dureeSon / max(0.001, m.separation)))
            print("mémoire du processus : \(mo(avant.actuelle)) au départ, pointe \(mo(apres.pointe)) (dont séparation ≈ \(mo(apres.pointe &- avant.actuelle))), \(mo(apres.actuelle)) une fois fini")
            print("voix trouvées : \(nVoix), \(voix.tours.count) tours, empreintes de \(voix.empreintes.values.first?.count ?? 0) nombres")
            guard let verite else { return 0 }
            guard let texte = try? String(contentsOfFile: verite, encoding: .utf8) else { print("vérité illisible : \(verite)"); return 2 }
            let vrais: [(TourDeParole, String)] = texte.split(separator: "\n").compactMap { l in
                let c = l.split(separator: "\t", omittingEmptySubsequences: false)
                guard c.count >= 4, let d = Double(c[0]), let f = Double(c[1]) else { return nil }
                return (TourDeParole(voix: String(c[2]), debut: d, fin: f), String(c[3]))
            }
            let justesse = SeparationVoix.justesse(trouves: voix.tours, verite: vrais.map(\.0))
            print(String(format: "temps de parole donné à la bonne voix : %.1f %%", justesse * 100))
            // la transcription simulée : chaque tour coupé en phrases (comme Whisper), bornes décalées de ±0,4 s
            var generateur = SystemRandomNumberGenerator()
            var segments: [SegmentReunion] = [], vraies: [String] = []
            for (t, phrasesDuTour) in vrais {
                let phrases = FusionPistes.phrases(phrasesDuTour)
                let total = Double(max(1, phrases.reduce(0) { $0 + $1.count }))
                var d = t.debut
                for p in phrases {
                    let f = d + (t.fin - t.debut) * Double(p.count) / total
                    let decale = { (x: Double) in x + Double.random(in: -0.4...0.4, using: &generateur) }
                    segments.append(SegmentReunion(debut: max(0, decale(d)), fin: decale(f), locuteur: .eux, texte: p))
                    vraies.append(t.voix)
                    d = f
                }
            }
            let a = SeparationVoix.attribuer(segments, voix: voix)
            print(String(format: "passages de la transcription au bon orateur : %.1f %% (%d passages, %d personnes dans la note)",
                         SeparationVoix.passagesJustes(a.segments, vraies: vraies) * 100, segments.count, a.orateurs.count))
            for v in Array(Set(vraies)).sorted() {
                let siens = zip(a.segments, vraies).filter { $0.1 == v }.map { $0.0.orateur.flatMap(SeparationVoix.nomParDefaut(id:)) ?? "Eux" }
                let compte = Dictionary(grouping: siens, by: { $0 }).mapValues(\.count).sorted { $0.value > $1.value }
                print("  \(v) → " + compte.map { "\($0.key) \($0.value)" }.joined(separator: ", "))
            }
            return 0
        } catch {
            print("séparation impossible : \(error)")
            return 1
        }
    }
}
