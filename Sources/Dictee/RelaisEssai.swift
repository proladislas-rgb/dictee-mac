import AVFoundation
import DicteeCore

/// `Dictee --relais-essai fichier.wav ["texte attendu"]` : ce que le relais sur le Mac écrirait pour ce son, sans Groq. Le fichier est lu
/// comme le micro le ferait (mêmes tampons, même AnalyseurDirect, mêmes mots du lexique), puis le texte passe par la correction à l'oreille
/// et la mise en forme locales. Aucun réseau, aucun micro ; la langue doit DÉJÀ être installée sur le Mac (rien n'est téléchargé, aucune
/// autorisation n'est demandée : SpeechAnalyzer sur l'appareil n'en demande pas, le repli classique, qui en demande une, n'est jamais pris).
enum RelaisEssai {
    @MainActor
    static func executer(chemin: String, attendu: String?, reserver: Bool) async -> Int32 {
        let r = await essayer(chemin: chemin, attendu: attendu, reserver: reserver)
        if reserver { await PrechauffageParole.liberer() }
        return r
    }

    @MainActor
    private static func essayer(chemin: String, attendu: String?, reserver: Bool) async -> Int32 {
        if let raison = await PrechauffageParole.preparerSansDemander(reserver: reserver) {
            print("relais sur le Mac indisponible : \(raison)"); return 1
        }
        let mots = PrechauffageParole.motsContexte()
        guard let direct = PrechauffageParole.creer(mots: mots) else { print("reconnaissance du Mac non prête"); return 1 }
        guard let fichier = try? AVAudioFile(forReading: URL(fileURLWithPath: chemin)) else { print("fichier illisible : \(chemin)"); return 2 }
        let duree = Double(fichier.length) / fichier.processingFormat.sampleRate
        let t0 = ProcessInfo.processInfo.systemUptime
        while fichier.framePosition < fichier.length {
            guard let tampon = AVAudioPCMBuffer(pcmFormat: fichier.processingFormat, frameCapacity: 4096) else { break }
            do { try fichier.read(into: tampon, frameCount: 4096) } catch { break }
            if tampon.frameLength == 0 { break }
            direct.alimenter(tampon)
        }
        let brut = await direct.terminer()
        let ms = Int((ProcessInfo.processInfo.systemUptime - t0) * 1000)
        let corrige = await PreparationLexique.correcteur()(brut, 0)
        let final = TextFormatter.prepare(AdressesDictees.reconstituer(corrige), for: TextFormatter.kind(bundleID: "com.apple.Notes"))
        print("son : \(String(format: "%.1f", duree)) s, reconnu en \(ms) ms sur le Mac (\(mots.count) mots du lexique donnés)")
        print("brut du Mac : \(brut)")
        print("après lexique et mise en forme : \(final)")
        if let attendu {
            let j = justesse(final, attendu)
            print("attendu : \(attendu)")
            print("mots justes : \(j.justes)/\(j.total) (\(j.total == 0 ? 0 : 100 * j.justes / j.total) %)")
        }
        return brut.isEmpty ? 1 : 0
    }

    /// Mots de l'attendu retrouvés dans l'ordre (plus longue sous-suite commune), sans casse, accents ni ponctuation.
    static func justesse(_ texte: String, _ attendu: String) -> (justes: Int, total: Int) {
        func mots(_ s: String) -> [String] {
            s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
                .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        }
        let a = mots(texte), b = mots(attendu)
        guard !a.isEmpty, !b.isEmpty else { return (0, b.count) }
        var t = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 1...a.count { for j in 1...b.count { t[i][j] = a[i - 1] == b[j - 1] ? t[i - 1][j - 1] + 1 : max(t[i - 1][j], t[i][j - 1]) } }
        return (t[a.count][b.count], b.count)
    }
}
