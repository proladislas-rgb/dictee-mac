import Foundation
import DicteeCore

/// La transcription d'une réunion « au fil de l'eau » : chaque morceau de chaque piste part chez Groq (Whisper) en arrière-plan,
/// un à la fois, dans l'ordre d'arrivée. La réunion cède toujours le pas à la dictée (touche fn) :
///  - requêtes : elle n'envoie que s'il reste la marge que la dictée garde pour elle (`BudgetRequetes`, partagé) ;
///  - audio : elle n'utilise que 5 700 des 7 200 secondes par heure de Whisper (`BudgetAudio`), 1 500 sont gardées pour la dictée.
/// Quand le budget manque, elle attend (le morceau reste en mémoire) ; une erreur de réseau est retentée quelques fois.
final class TranscriptionReunion: @unchecked Sendable {
    private struct Travail { var morceau: MorceauReunion; var essais = 0 }

    private let verrou = NSLock()
    private var file: [Travail] = []
    private var enVol = 0
    private var boucle: Task<Void, Never>?
    private var annule = false
    private var dernierTexte: [Locuteur: String] = [:]
    private(set) var echecs = 0
    private(set) var recus = 0
    private(set) var cleManquante = false

    private let groq: GroqClient
    private let langue: String?
    private let prompt: @Sendable (String?) -> String
    private let correcteur: (@Sendable (String, Int) async -> String)?
    /// Un passage est transcrit (appelé sur un fil quelconque).
    var surSegment: ((SegmentReunion) -> Void)?
    /// Le nombre de morceaux encore à transcrire a changé.
    var surProgression: ((Int) -> Void)?

    init(groq: GroqClient = .shared, langue: String? = Settings.langue, correcteur: (@Sendable (String, Int) async -> String)? = PreparationLexique.correcteur()) {
        self.groq = groq
        self.langue = langue
        self.prompt = PreparationLexique.promptPour(langue: langue, genre: .other, champ: { nil }, recents: [])
        self.correcteur = correcteur
    }

    var restants: Int { verrou.lock(); defer { verrou.unlock() }; return file.count + enVol }

    func soumettre(_ m: MorceauReunion) {
        verrou.lock()
        file.append(Travail(morceau: m))
        let demarrer = boucle == nil
        if demarrer { boucle = Task.detached(priority: .utility) { [weak self] in await self?.tourner() } }
        let n = file.count + enVol
        verrou.unlock()
        surProgression?(n)
    }

    func annuler() {
        verrou.lock(); annule = true; file.removeAll(); let b = boucle; verrou.unlock()
        b?.cancel()
    }

    /// Attend que tous les morceaux soient transcrits (ou abandonnés).
    func attendreLaFin() async {
        while restants > 0 && !annule { try? await Task.sleep(for: .milliseconds(250)) }
    }

    private func suivant() -> Travail? {
        verrou.lock(); defer { verrou.unlock() }
        guard !annule, !file.isEmpty else { boucle = nil; return nil }
        enVol += 1
        return file.removeFirst()
    }

    private func tourner() async {
        while let travail = suivant() {
            await traiter(travail)
            let n = verrou.withLock { () -> Int in enVol -= 1; return file.count + enVol }
            surProgression?(n)
        }
    }

    private func traiter(_ travail: Travail) async {
        var t = travail
        let m = t.morceau
        while !Task.isCancelled {
            // La dictée d'abord : on attend que le budget de requêtes et d'audio laisse de la place.
            let attente = max(BudgetRequetes.partage.delaiAvantDePermettre(.anticipation), BudgetAudio.partage.delaiAvant(duree: m.duree))
            if attente > 0 {
                Log.ecrire("réunion : morceau \(m.locuteur.libelle) de \(Int(m.duree)) s en attente de budget (\(Int(attente)) s)")
                try? await Task.sleep(for: .seconds(min(attente, 20)))
                continue
            }
            let fichier = EncodeurAudio.encoder(m.echantillons)
            let contexte = verrou.withLock { dernierTexte[m.locuteur] }
            let debut = ProcessInfo.processInfo.systemUptime
            BudgetAudio.partage.noter(duree: m.duree)
            do {
                var texte = try await groq.transcrire(fichier: fichier, prompt: prompt(contexte), langue: langue, autorisees: Settings.languesAutorisees,
                                                      etiquette: "réunion \(m.locuteur.libelle) \(FormatReunion.horloge(m.debut))")
                if let correcteur { texte = await correcteur(texte, verrou.withLock { recus } + 1) }
                texte = texte.trimmingCharacters(in: .whitespacesAndNewlines)
                let ms = Int((ProcessInfo.processInfo.systemUptime - debut) * 1000)
                Log.ecrire("réunion : morceau \(m.locuteur.libelle) à \(FormatReunion.horloge(m.debut)), \(String(format: "%.1f", m.duree)) s -> Groq en \(ms) ms, \"\(Log.apercu(texte))\"")
                verrou.withLock { recus += 1; if !texte.isEmpty { dernierTexte[m.locuteur] = texte } }
                if !texte.isEmpty, !TextAssembler.estFantome(texte) {
                    surSegment?(SegmentReunion(debut: m.debut, fin: m.debut + m.duree, locuteur: m.locuteur, texte: texte))
                }
                return
            } catch is CancellationError {
                return
            } catch GroqErreur.pasDeCle {
                verrou.withLock { cleManquante = true; echecs += 1 }
                return
            } catch {
                t.essais += 1
                var retentable = false
                if let e = error as? GroqErreur {
                    switch e { case .reseau: retentable = true; case .http(let c): retentable = c == 429 || c >= 500; default: break }
                }
                Log.ecrire("réunion : échec Groq pour un morceau \(m.locuteur.libelle) (\(error)), essai \(t.essais)")
                if !retentable || t.essais >= 5 { verrou.withLock { echecs += 1 }; return }
                try? await Task.sleep(for: .seconds(Double([2, 5, 12, 25, 40][min(t.essais - 1, 4)])))
            }
        }
    }
}
