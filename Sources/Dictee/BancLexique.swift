import AVFoundation
import DicteeCore

/// Banc d'essai du lexique, sans micro : des phrases pièges lues par les voix de synthèse du Mac (`scripts/banc-lexique.sh`), envoyées à
/// Groq deux fois — AVANT (prompt d'avant le lexique : mots.txt seul) et APRÈS (prompt choisi dans le lexique) — puis la correction « à
/// l'oreille » est appliquée au texte d'APRÈS. On mesure la part des mots du lexique correctement écrits et on compte les fausses corrections.
///
///   Verbe --banc-lexique DOSSIER   (réseau seulement : DOSSIER/phrases.json et un fichier NN.wav par phrase ; écrit DOSSIER/resultats.json)
///   Verbe --oreille "texte"        (aucun réseau : montre ce que la correction à l'oreille ferait de ce texte)
///
/// Les phrases contiennent des noms de la vie de Hugues : elles restent dans son dossier local, jamais dans le dépôt.
@MainActor
enum BancLexique {
    struct Cas: Codable {
        var id: String
        var langue: String
        var voix: String
        var texte: String
        var mots: [String]
        var titre: String?
        var contexte: String?
    }

    struct Ligne: Codable {
        var id: String
        var langue: String
        var avec_contexte: Bool
        var attendus: [String]
        var avant: String
        var apres: String
        var final: String
        var avantJustes: Int
        var apresJustes: Int
        var finalJustes: Int
        var correctionSeuleJustes: Int
        var corrections: [String]
        var fausses: [String]
    }

    // MARK: --oreille

    static func oreille(texte: String) -> Int32 {
        let mots = Dictionnaire.mots()
        let index = IndexCorrection(motsChoisis: mots, lexique: LexiqueStore.partage.entrees())
        let r = CorrectionOreille.corriger(texte, index: index, estConnu: { Orthographe.estConnu($0) })
        print(r.texte)
        for c in r.corrections { print("  " + c.ligneDeJournal) }
        if r.corrections.isEmpty { print("  (aucune correction)") }
        return 0
    }

    // MARK: --banc-lexique

    static func executer(dossier: String, reutiliserAvant: Bool = false) async -> Int32 {
        let base = URL(fileURLWithPath: (dossier as NSString).expandingTildeInPath)
        guard let donnees = try? Data(contentsOf: base.appendingPathComponent("phrases.json")),
              let cas = try? JSONDecoder().decode([Cas].self, from: donnees) else {
            FileHandle.standardError.write(Data("Usage : Voxile --banc-lexique DOSSIER (phrases.json et NN.wav attendus)\n".utf8)); return 2
        }
        guard GroqClient.shared.cleDisponible else { FileHandle.standardError.write(Data("Clé Groq introuvable (~/.config/groq/.env)\n".utf8)); return 2 }
        let motsChoisis = Dictionnaire.mots()
        let lexique = LexiqueStore.partage.entrees()
        guard !lexique.isEmpty else { FileHandle.standardError.write(Data("Pas de lexique : lancer d\u{2019}abord Voxile --construire-lexique\n".utf8)); return 2 }
        let index = IndexCorrection(motsChoisis: motsChoisis, lexique: lexique)
        print("Banc d\u{2019}essai : \(cas.count) phrases, lexique de \(lexique.count) mots, \(motsChoisis.count) mots choisis. \(reutiliserAvant ? "Une requête" : "Deux requêtes") par phrase, une toutes les 3,4 s.")

        var lignes: [Ligne] = []
        // --reutiliser-avant : les textes AVANT d'un essai précédent sont gardés tels quels (même son, même prompt, même Whisper) ;
        // seules les requêtes APRÈS sont refaites, ce qui évite de dépenser la moitié des requêtes gratuites de Groq
        var anciensAvant: [String: String] = [:]
        if reutiliserAvant, let d = try? Data(contentsOf: base.appendingPathComponent("resultats.json")), let anciens = try? JSONDecoder().decode([Ligne].self, from: d) {
            for a in anciens { anciensAvant[a.id] = a.avant }
        }
        var derniere = Date.distantPast
        func envoyer(_ fichier: EncodeurAudio.Fichier, prompt: String, langue: String) async -> String? {
            for essai in 1...4 {
                let attente = 3.4 - Date().timeIntervalSince(derniere)
                if attente > 0 { try? await Task.sleep(for: .seconds(attente)) }
                derniere = Date()
                do { return try await GroqClient.shared.transcrire(fichier: fichier, prompt: prompt, langue: langue, etiquette: "banc") }
                catch GroqErreur.http(429) { print("  (limite atteinte, pause de 25 s, essai \(essai))"); try? await Task.sleep(for: .seconds(25)) }
                catch { print("  (échec : \(error), essai \(essai))"); try? await Task.sleep(for: .seconds(4)) }
            }
            return nil
        }

        for c in cas {
            guard let son = lire(base.appendingPathComponent("\(c.id).wav")) else { print("\(c.id) : fichier son illisible, ignoré"); continue }
            let fichier = EncodeurAudio.encoder(son, flac: true)
            let ancre = ChoixLangue.phraseAncre(langue: c.langue)
            // AVANT : le prompt d'avant le lexique (mots.txt, rien d'autre)
            let promptAvant = TextAssembler.prompt(mots: motsChoisis, contexte: nil, ancre: ancre)
            // APRÈS : mots choisis dans le lexique selon le contexte (titre de fenêtre, texte avant le curseur)
            let contexte = ContexteMots(genre: .other, titreFenetre: c.titre, texteAutour: c.contexte, recents: [], dejaDicte: nil)
            let promptApres = ChoixMotsPrompt.prompt(motsChoisis: motsChoisis, lexique: lexique, contexte: contexte, texteDavant: nil, ancre: ancre)
            let avantReutilise: String?
            if let a = anciensAvant[c.id] { avantReutilise = a } else { avantReutilise = await envoyer(fichier, prompt: promptAvant, langue: c.langue) }
            guard let avant = avantReutilise,
                  let apres = await envoyer(fichier, prompt: promptApres, langue: c.langue) else { print("\(c.id) : Groq n\u{2019}a pas répondu, ignoré"); continue }

            let l = evaluer(c, avant: avant, apres: apres, index: index)
            lignes.append(l)
            affiche(l)
        }

        if let sortie = try? JSONEncoder().encode(lignes) { try? sortie.write(to: base.appendingPathComponent("resultats.json")) }
        resume(lignes)
        return 0
    }

    /// Compare les textes reçus de Whisper (AVANT et APRÈS) à ce qui a été dit, avant et après la correction à l'oreille.
    static func evaluer(_ c: Cas, avant: String, apres: String, index: IndexCorrection) -> Ligne {
        let corrigeApres = CorrectionOreille.corriger(apres, index: index, estConnu: { Orthographe.estConnu($0) })
        let corrigeAvant = CorrectionOreille.corriger(avant, index: index, estConnu: { Orthographe.estConnu($0) })
        let dits = Set(ApprentissageCorrections.mots(c.texte).map { $0.lowercased() })
        let ditsExacts = Set(ApprentissageCorrections.mots(c.texte))
        var fausses: [String] = []
        for corr in corrigeApres.corrections + corrigeAvant.corrections {
            let originaux = ApprentissageCorrections.mots(corr.original), remplaces = ApprentissageCorrections.mots(corr.remplacement)
            // fausse : le mot d'origine était déjà écrit comme dit, ou le remplaçant (à la casse près) n'a jamais été dit
            if originaux.allSatisfy({ ditsExacts.contains($0) }) || !remplaces.allSatisfy({ dits.contains($0.lowercased()) }) {
                fausses.append(corr.original + " \u{2192} " + corr.remplacement)
            }
        }
        return Ligne(id: c.id, langue: c.langue, avec_contexte: c.contexte != nil || c.titre != nil, attendus: c.mots, avant: avant, apres: apres, final: corrigeApres.texte,
                     avantJustes: justes(c.mots, dans: avant), apresJustes: justes(c.mots, dans: apres), finalJustes: justes(c.mots, dans: corrigeApres.texte),
                     correctionSeuleJustes: justes(c.mots, dans: corrigeAvant.texte),
                     corrections: corrigeApres.corrections.map { $0.original + " \u{2192} " + $0.remplacement }, fausses: fausses)
    }

    static func affiche(_ l: Ligne) {
        let n = l.attendus.count
        print("\(l.id) [\(l.langue)\(l.avec_contexte ? "+ctx" : "")] \(l.avantJustes)/\(n) avant, \(l.apresJustes)/\(n) prompt, \(l.finalJustes)/\(n) prompt+oreille, \(l.correctionSeuleJustes)/\(n) oreille seule\(l.fausses.isEmpty ? "" : "  FAUSSES : \(l.fausses.joined(separator: " ; "))")")
    }

    /// `--banc-lexique-rejouer DOSSIER` : refait seulement la correction à l'oreille sur les textes déjà reçus de Whisper (aucun réseau).
    static func rejouer(dossier: String) -> Int32 {
        let base = URL(fileURLWithPath: (dossier as NSString).expandingTildeInPath)
        guard let d1 = try? Data(contentsOf: base.appendingPathComponent("phrases.json")), let cas = try? JSONDecoder().decode([Cas].self, from: d1),
              let d2 = try? Data(contentsOf: base.appendingPathComponent("resultats.json")), let anciens = try? JSONDecoder().decode([Ligne].self, from: d2) else {
            FileHandle.standardError.write(Data("Usage : Voxile --banc-lexique-rejouer DOSSIER (phrases.json et resultats.json attendus)\n".utf8)); return 2
        }
        let index = IndexCorrection(motsChoisis: Dictionnaire.mots(), lexique: LexiqueStore.partage.entrees())
        var lignes: [Ligne] = []
        for a in anciens {
            guard let c = cas.first(where: { $0.id == a.id }) else { continue }
            let l = evaluer(c, avant: a.avant, apres: a.apres, index: index)
            lignes.append(l); affiche(l)
            if !l.corrections.isEmpty { print("      corrections : \(l.corrections.joined(separator: " ; "))") }
        }
        resume(lignes)
        return 0
    }

    /// Combien de mots attendus sont écrits exactement (majuscules et accents compris) dans le texte.
    static func justes(_ attendus: [String], dans texte: String) -> Int {
        let sac = " " + ApprentissageCorrections.mots(texte).joined(separator: " ") + " "
        return attendus.filter { m in sac.contains(" " + ApprentissageCorrections.mots(m).joined(separator: " ") + " ") }.count
    }

    static func resume(_ l: [Ligne]) {
        func taux(_ lignes: [Ligne], _ f: (Ligne) -> Int) -> String {
            let total = lignes.reduce(0) { $0 + $1.attendus.count }
            guard total > 0 else { return "n/a" }
            let ok = lignes.reduce(0) { $0 + f($1) }
            return String(format: "%d/%d = %.1f %%", ok, total, Double(ok) / Double(total) * 100)
        }
        func bloc(_ nom: String, _ lignes: [Ligne]) {
            print("\(nom) (\(lignes.count) phrases, \(lignes.reduce(0) { $0 + $1.attendus.count }) mots du lexique) :")
            print("  AVANT (prompt d\u{2019}avant, mots.txt seul)      : \(taux(lignes) { $0.avantJustes })")
            print("  prompt choisi seul                          : \(taux(lignes) { $0.apresJustes })")
            print("  correction à l\u{2019}oreille seule (sur AVANT)   : \(taux(lignes) { $0.correctionSeuleJustes })")
            print("  APRÈS (prompt choisi + correction à l\u{2019}oreille) : \(taux(lignes) { $0.finalJustes })")
        }
        print("\n=== Résultats ===")
        bloc("Toutes", l)
        bloc("Sans contexte", l.filter { !$0.avec_contexte })
        bloc("Avec contexte (titre de fenêtre, texte autour)", l.filter { $0.avec_contexte })
        for langue in ["fr", "en"] { bloc("Langue \(langue)", l.filter { $0.langue == langue }) }
        let corr = l.reduce(0) { $0 + $1.corrections.count }, fausses = l.reduce(0) { $0 + $1.fausses.count }
        print("Corrections à l\u{2019}oreille appliquées : \(corr) (sur le texte d\u{2019}APRÈS) ; FAUSSES corrections (APRÈS et correction seule) : \(fausses)")
        for x in l where !x.fausses.isEmpty { print("  \(x.id) : \(x.fausses.joined(separator: " ; "))") }
    }

    /// Le son d'un fichier WAV 16 kHz mono 16 bits (produit par afconvert).
    static func lire(_ url: URL) -> [Int16]? {
        guard let f = try? AVAudioFile(forReading: url, commonFormat: .pcmFormatInt16, interleaved: true), f.processingFormat.sampleRate == 16_000, f.processingFormat.channelCount == 1,
              let tampon = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length)), (try? f.read(into: tampon)) != nil,
              let canal = tampon.int16ChannelData else { return nil }
        return Array(UnsafeBufferPointer(start: canal[0], count: Int(tampon.frameLength)))
    }
}
