import AVFoundation
import Darwin
import DicteeCore
import Foundation

/// `Verbe --reunion-mesure moi.wav eux.wav [--sortie DOSSIER]` : ce que coûte une réunion PENDANT l'appel, sans micro, sans son du
/// Mac, sans réseau. Les deux fichiers (16 kHz mono) sont donnés aux vraies pistes comme le feraient le micro et le son du Mac
/// (tampons de 100 ms en 48 kHz stéréo flottant), avec l'écriture du son sur le disque et le découpage aux pauses ; la transcription
/// est remplacée par un texte factice qui arrive 1,5 s après chaque morceau. Mesures :
/// - processeur des pistes (conversion, niveaux, découpe, écriture) par minute d'appel → part d'un cœur en continu ;
/// - le direct de l'îlot (`DirectReunion.lignes`) : recalculé chaque seconde (avant) ou seulement quand quelque chose a changé ;
/// - mémoire du processus (pointe) pendant l'appel simulé.
enum MesureReunion {
    static func executer(moi: String, eux: String, arguments: [String]) -> Int32 {
        let sortie = arguments.firstIndex(of: "--sortie").flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil } ?? ".build/reunion-mesure"
        let dossier = URL(fileURLWithPath: (sortie as NSString).expandingTildeInPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        defer { for l in ["moi", "eux"] { try? FileManager.default.removeItem(at: dossier.appendingPathComponent("son-\(l).wav")) } }
        guard let sonMoi = lire(moi), let sonEux = lire(eux) else { print("fichier son illisible"); return 2 }
        let memoireDepart = MemoireProcessus.empreinte().actuelle
        let duree = Double(max(sonMoi.count, sonEux.count)) / 16_000
        print(String(format: "appel simulé : %.1f min, deux pistes", duree / 60))

        // les pistes, comme pendant un vrai appel
        let verrou = NSLock()
        var morceaux: [MorceauReunion] = []
        var t = 0.0
        let pistes = [Locuteur.moi, .eux].map { l -> PisteReunion in
            let p = PisteReunion(locuteur: l, fichierSon: dossier.appendingPathComponent("son-\(l.rawValue).wav"))
            p.horloge = { t }
            p.surMorceau = { m in verrou.lock(); morceaux.append(m); verrou.unlock() }
            return p
        }
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: false)!
        let pas = 1_600   // 100 ms à 16 kHz
        var cpuPistes = 0.0, cpuDirectAvant = 0.0, cpuDirectApres = 0.0
        var calculsAvant = 0, calculsApres = 0
        var segments: [Locuteur: [SegmentReunion]] = [.moi: [], .eux: []]
        var enAttente: [(arrivee: Double, m: MorceauReunion)] = []
        var version = 0
        var derniere: EntreesDirect?
        var prochaineSeconde = 1.0
        var debut = 0
        let phrases = ["Les machines arrivent à Lyon mardi, puis à Bordeaux jeudi matin.", "Je pense qu'il faut prévenir les clients au moins deux jours avant.",
                       "D'accord, c'est noté.", "On relance vendredi si on n'a pas de réponse.", "Le budget total reste autour de quarante-deux mille euros."]
        while debut < max(sonMoi.count, sonEux.count) {
            t = Double(debut + pas) / 16_000
            for (k, son) in [sonMoi, sonEux].enumerated() {
                guard let b = tampon(son, debut: debut, pas: pas, format: format) else { continue }
                let c0 = cpu()
                pistes[k].traiter(b)
                cpuPistes += cpu() - c0
            }
            debut += pas
            // les morceaux coupés « partent » et reviennent transcrits 1,5 s plus tard
            verrou.lock(); let nouveaux = morceaux; morceaux = []; verrou.unlock()
            for m in nouveaux { enAttente.append((t + 1.5, m)); version += 1 }
            while let i = enAttente.firstIndex(where: { $0.arrivee <= t }) {
                let m = enAttente.remove(at: i).m
                let n = Int(m.duree / 4) + 1
                let texte = (0..<n).map { phrases[($0 + segments[m.locuteur]!.count) % phrases.count] }.joined(separator: " ")
                segments[m.locuteur]!.append(SegmentReunion(debut: m.debut, fin: m.debut + m.duree, locuteur: m.locuteur, texte: texte))
                version += 1
            }
            // la minuterie d'une seconde du contrôleur
            if t >= prochaineSeconde {
                prochaineSeconde += 1
                let attentes = enAttente.map { AttenteDirect(locuteur: $0.m.locuteur, debut: $0.m.debut, fin: $0.m.debut + $0.m.duree) } + pistes.compactMap { $0.parole() }
                let c0 = cpu()
                _ = DirectReunion.lignes(moi: segments[.moi]!, eux: segments[.eux]!, attentes: attentes)
                cpuDirectAvant += cpu() - c0; calculsAvant += 1
                let e = EntreesDirect(version: version, attentes: attentes, points: 0)
                if e != derniere {
                    let c1 = cpu()
                    _ = DirectReunion.lignes(moi: segments[.moi]!, eux: segments[.eux]!, attentes: attentes)
                    cpuDirectApres += cpu() - c1; calculsApres += 1
                    derniere = e
                }
            }
        }
        for p in pistes { p.terminer() }
        let pointe = MemoireProcessus.empreinte().pointe
        let entree = UInt64((sonMoi.count + sonEux.count) * 2)
        let minutes = duree / 60
        print(String(format: "pistes (conversion, niveaux, découpe, écriture du son) : %.0f ms de processeur par minute d'appel = %.2f %% d'un cœur", cpuPistes * 1000 / minutes, cpuPistes / duree * 100))
        print(String(format: "direct de l'îlot, recalculé chaque seconde : %d calculs, %.0f ms de processeur par minute (%.2f %% d'un cœur), %.2f ms par calcul en moyenne",
                     calculsAvant, cpuDirectAvant * 1000 / minutes, cpuDirectAvant / duree * 100, cpuDirectAvant / Double(max(1, calculsAvant)) * 1000))
        print(String(format: "direct de l'îlot, seulement quand il change : %d calculs, %.0f ms de processeur par minute (%.2f %% d'un cœur)",
                     calculsApres, cpuDirectApres * 1000 / minutes, cpuDirectApres / duree * 100))
        print("passages : \(segments[.moi]!.count) Moi, \(segments[.eux]!.count) Eux")
        print("mémoire : \(memoireDepart / 1_048_576) Mo au départ, pointe \(pointe / 1_048_576) Mo (dont \((entree) / 1_048_576) Mo de son d'essai chargé)")
        return 0
    }

    private static func lire(_ chemin: String) -> [Int16]? {
        let url = URL(fileURLWithPath: (chemin as NSString).expandingTildeInPath)
        return LectureWAV.echantillons(url, de: 0, a: LectureWAV.duree(url))
    }

    /// 100 ms de son en 48 kHz stéréo flottant (le format du son du Mac), fabriqué à partir de la piste 16 kHz.
    private static func tampon(_ son: [Int16], debut: Int, pas: Int, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard debut < son.count, let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(pas * 3)), let d = b.floatChannelData else { return nil }
        let n = min(pas, son.count - debut)
        for i in 0..<n {
            let x = Float(son[debut + i]) / 32_768
            for k in 0..<3 { d[0][i * 3 + k] = x; d[1][i * 3 + k] = x }
        }
        b.frameLength = AVAudioFrameCount(n * 3)
        return b
    }

    /// Le temps de processeur du fil courant, en secondes.
    private static func cpu() -> Double {
        var ts = timespec()
        clock_gettime(CLOCK_THREAD_CPUTIME_ID, &ts)
        return Double(ts.tv_sec) + Double(ts.tv_nsec) / 1e9
    }
}
