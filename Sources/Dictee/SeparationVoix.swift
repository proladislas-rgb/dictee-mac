import Accelerate
import CoreML
import Darwin
import DicteeCore
import FluidAudio
import Foundation

/// La séparation des voix des autres participants, après l'appel, sur la piste « Eux » (le son du Mac) : FluidAudio (pyannote
/// community-1 en CoreML : découpe, empreintes WeSpeaker, regroupement VBx), entièrement sur ce Mac. Le son ne part nulle part ;
/// le seul accès au réseau est le téléchargement des modèles, une fois, depuis Hugging Face (dépôt FluidInference/speaker-diarization-coreml),
/// rangés dans ~/Library/Application Support/Dictee/Modeles (effacés avec Verbe par « Désinstaller »). Les modèles ne sont chargés
/// que le temps d'une séparation, puis libérés ; une seule séparation à la fois (mémoire).
struct SeparationVoixAudio: Sendable {
    enum Avance: Sendable {
        /// Premier usage : téléchargement du modèle, 0 à 1.
        case telechargement(Double)
        /// La séparation elle-même, 0 à 1.
        case separation(Double)
    }

    /// Fichier son de la piste « Eux » → voix séparées. `avance` peut être appelé de n'importe quel fil.
    var separer: @Sendable (URL, @escaping @Sendable (Avance) -> Void) async throws -> VoixSeparees

    /// La vraie, sur ce Mac.
    static let surLeMac = SeparationVoixAudio { url, avance in
        try await SeparationVoixLocale.separer(url, modeles: SeparationVoixLocale.dossierParDefaut, avance: avance).voix
    }
}

enum SeparationVoixLocale {
    enum Erreur: Error, CustomStringConvertible {
        case sonIllisible
        var description: String { "son de la piste « Eux » illisible" }
    }

    /// ~/Library/Application Support/Dictee/Modeles : jamais dans git, effacé par « Désinstaller ».
    static var dossierParDefaut: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Dictee/Modeles", isDirectory: true)
    }

    /// Le dossier du modèle de séparation dans `modeles` (FluidAudio y ajoute le nom du dépôt).
    static func dossierDuModele(_ modeles: URL) -> URL { modeles.appendingPathComponent(Repo.diarizer.folderName, isDirectory: true) }

    /// Le modèle est-il déjà sur le Mac (sinon : premier usage, il se télécharge) ?
    static func modelePresent(_ modeles: URL) -> Bool {
        let d = dossierDuModele(modeles)
        return ModelNames.OfflineDiarizer.requiredModels.allSatisfy { FileManager.default.fileExists(atPath: d.appendingPathComponent($0).path) }
    }

    /// Réglages : ceux de pyannote community-1, avec des passages exclusifs (une voix à la fois : chaque phrase de la transcription
    /// va à UNE personne). La taille des lots ne change rien à la mémoire mesurée sur 20 min de son (même pointe de 1 à 32 fenêtres) :
    /// on garde celle d'origine, la plus rapide.
    static func configuration() -> OfflineDiarizerConfig {
        var c = OfflineDiarizerConfig()
        c.postProcessing.exclusiveSegments = true
        return c
    }

    /// Le moteur neuronal et le processeur, sans la carte graphique : environ 30 % de mémoire de pointe en moins qu'avec tout le Mac
    /// (≈ 500 Mo au lieu de 700 sur 20 min de son), aussi rapide, et la carte graphique reste libre pour le reste du Mac.
    static func calcul() -> MLModelConfiguration {
        let c = MLModelConfiguration()
        c.computeUnits = .cpuAndNeuralEngine
        return c
    }

    struct Mesure: Sendable {
        var telecharge: Bool
        var chargement: Double
        var separation: Double
        var dureeSon: Double
    }

    private static let file = FileUnique()

    /// Sépare les voix d'un fichier son écrit par `EcrivainWAV` (16 kHz mono 16 bits, calé sur l'heure de la réunion : les heures des
    /// tours sont des heures de réunion). Télécharge le modèle s'il manque.
    static func separer(_ url: URL, modeles: URL, avance: @escaping @Sendable (SeparationVoixAudio.Avance) -> Void) async throws -> (voix: VoixSeparees, mesure: Mesure) {
        try await file.unParUn {
            guard let source = SourceWAV(url: url) else { throw Erreur.sonIllisible }
            let telecharge = !modelePresent(modeles)
            let t0 = ProcessInfo.processInfo.systemUptime
            if telecharge { Log.ecrire("voix : premier usage, téléchargement du modèle de séparation des voix") }
            let modelesCharges = try await OfflineDiarizerModels.load(from: modeles, configuration: calcul()) { p in
                if telecharge { avance(.telechargement(p.fractionCompleted)) }
            }
            let t1 = ProcessInfo.processInfo.systemUptime
            Log.ecrire("voix : modèle \(telecharge ? "téléchargé et " : "")chargé en \(Int((t1 - t0) * 1000)) ms")
            let gestionnaire = OfflineDiarizerManager(config: configuration())
            gestionnaire.initialize(models: modelesCharges)
            avance(.separation(0))
            let resultat = try await gestionnaire.process(audioSource: source, audioLoadingSeconds: 0) { fait, total in
                avance(.separation(total > 0 ? Double(fait) / Double(total) : 0))
            }
            let t2 = ProcessInfo.processInfo.systemUptime
            let tours = resultat.segments.map { TourDeParole(voix: $0.speakerId, debut: Double($0.startTimeSeconds), fin: Double($0.endTimeSeconds)) }
            let voix = VoixSeparees(tours: tours, empreintes: resultat.speakerDatabase ?? [:])
            let duree = Double(source.sampleCount) / 16_000
            Log.ecrire("voix : \(Set(tours.map(\.voix)).count) voix, \(tours.count) tours, \(Int(duree)) s de son séparés en \(Int((t2 - t1) * 1000)) ms")
            return (voix, Mesure(telecharge: telecharge, chargement: t1 - t0, separation: t2 - t1, dureeSon: duree))
        }
    }
}

/// Le son d'un fichier `EcrivainWAV` lu pour FluidAudio sans le charger en mémoire (fichier projeté, converti morceau par morceau en
/// Float). La taille du fichier fait foi, comme pour `LectureWAV` : un fichier resté sans en-tête complet (arrêt brutal) se lit aussi.
struct SourceWAV: AudioSampleSource {
    private let donnees: Data
    let sampleCount: Int

    init?(url: URL) {
        guard let d = try? Data(contentsOf: url, options: .alwaysMapped), d.count >= LectureWAV.entete else { return nil }
        donnees = d
        sampleCount = (d.count - LectureWAV.entete) / 2
    }

    func copySamples(into destination: UnsafeMutablePointer<Float>, offset: Int, count: Int) throws {
        let n = max(0, min(count, sampleCount - offset))
        if n < count { destination.advanced(by: max(0, n)).update(repeating: 0, count: count - max(0, n)) }
        guard n > 0 else { return }
        donnees.withUnsafeBytes { brut in
            let entiers = brut.baseAddress!.advanced(by: LectureWAV.entete + offset * 2).assumingMemoryBound(to: Int16.self)
            vDSP_vflt16(entiers, 1, destination, 1, vDSP_Length(n))
            var echelle: Float = 1 / 32_768
            vDSP_vsmul(destination, 1, &echelle, destination, 1, vDSP_Length(n))
        }
    }
}

/// Une seule séparation à la fois (deux réunions préparées en même temps, « Refaire la note » pendant une note) : la suivante attend.
private actor FileUnique {
    private var occupe = false
    private var attente: [CheckedContinuation<Void, Never>] = []

    func unParUn<T: Sendable>(_ travail: @Sendable () async throws -> T) async throws -> T {
        if occupe { await withCheckedContinuation { attente.append($0) } }
        occupe = true
        defer {
            if attente.isEmpty { occupe = false } else { attente.removeFirst().resume() }
        }
        return try await travail()
    }
}

/// La mémoire du processus (empreinte physique, comme le Moniteur d'activité) : actuelle et maximale depuis le lancement.
enum MemoireProcessus {
    static func empreinte() -> (actuelle: UInt64, pointe: UInt64) {
        var info = task_vm_info_data_t()
        var n = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let r = withUnsafeMutablePointer(to: &info) { p in
            p.withMemoryRebound(to: integer_t.self, capacity: Int(n)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &n) }
        }
        guard r == KERN_SUCCESS else { return (0, 0) }
        return (info.phys_footprint, UInt64(max(0, info.ledger_phys_footprint_peak)))
    }
}
