import Foundation
import DicteeCore

/// Les réunions gardées sur ce Mac : ~/Library/Application Support/Dictee/Reunions/ (un JSON et un Markdown par réunion, et
/// éventuellement le son brut si « Garder le son des réunions » est actif). Dossier en 0700, fichiers en 0600, jamais dans git.
@MainActor
final class ReunionStore: ObservableObject {
    static let shared = ReunionStore()

    @Published private(set) var reunions: [Reunion] = []
    let dossier: URL
    private let file = DispatchQueue(label: "dictee.reunions.fichiers")

    static var dossierParDefaut: URL {
        DossierVerbe.url("Reunions", dossier: true)
    }

    /// `lire = false` : aucun accès au disque (rendus PNG avec des réunions d'exemple). `maintenant` : l'heure du lancement (le son
    /// gardé pour réessayer qui a dépassé son délai est effacé).
    init(dossier: URL? = nil, lire: Bool = true, maintenant: Date = Date()) {
        self.dossier = dossier ?? Self.dossierParDefaut
        guard lire else { return }
        try? FileManager.default.createDirectory(at: self.dossier, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // les extraits d'un glisser-déposer ne survivent pas à la session
        effacerTousLesExtraits()
        var trouvees: [Reunion] = []
        for url in (try? FileManager.default.contentsOfDirectory(at: self.dossier, includingPropertiesForKeys: nil)) ?? [] where url.pathExtension == "json" {
            guard let donnees = try? Data(contentsOf: url), let r = ArchiveReunions.decoder(donnees) else {
                Log.ecrire("réunions : fichier illisible \(url.lastPathComponent), laissé tel quel"); continue
            }
            let reprise = ArchiveReunions.reprendreApresArret(r)   // personne ne mène plus une réunion « en cours » au lancement
            if reprise != r { ecrire(reprise) }
            trouvees.append(reprise)
        }
        reunions = trouvees.sorted { $0.debut > $1.debut }
        for r in reunions where ArchiveReunions.sonPerime(r, maintenant: maintenant) && (sonPresent(r, .moi) || sonPresent(r, .eux)) {
            for u in [fichierSon(r, .moi), fichierSon(r, .eux)] { try? FileManager.default.removeItem(at: u) }
            effacerExtraits(r)
            Log.ecrire("réunions : son gardé pour réessayer effacé (plus de \(ArchiveReunions.joursSonEnAttente) jours)")
        }
    }

    /// Attend que les fichiers confiés à la file soient écrits (Verbe se ferme).
    func attendreEcritures() { file.sync {} }

    /// Ajoute ou met à jour une réunion, et réécrit ses fichiers.
    func enregistrer(_ r: Reunion) {
        if let i = reunions.firstIndex(where: { $0.id == r.id }) { reunions[i] = r } else { reunions.append(r) }
        reunions.sort { $0.debut > $1.debut }
        ecrire(r)
    }

    func reunion(id: UUID) -> Reunion? { reunions.first { $0.id == id } }

    /// Efface la réunion : note, transcription et son éventuel.
    func supprimer(id: UUID) {
        guard let r = reunion(id: id) else { return }
        reunions.removeAll { $0.id == id }
        effacerExtraits(r)
        let base = ArchiveReunions.nomDeBase(r), dossier = dossier
        file.async {
            let fm = FileManager.default
            for nom in ["\(base).json", "\(base).md", "\(base)-moi.wav", "\(base)-eux.wav"] { try? fm.removeItem(at: dossier.appendingPathComponent(nom)) }
        }
        Log.ecrire("réunions : une réunion effacée")
    }

    /// Les fichiers du son d'une réunion : écrits pendant l'appel (0600, hors de Time Machine si le réglage « Garder le son » est
    /// éteint), gardés le temps de la relecture et de la note, puis effacés sauf si « Garder le son des réunions » est actif. Une
    /// relecture incomplète ou une note pas écrite les garde `ArchiveReunions.joursSonEnAttente` jours, pour « Refaire la note ».
    func fichierSon(_ r: Reunion, _ l: Locuteur) -> URL {
        dossier.appendingPathComponent("\(ArchiveReunions.nomDeBase(r))-\(l.rawValue).wav")
    }

    func sonPresent(_ r: Reunion, _ l: Locuteur) -> Bool { FileManager.default.fileExists(atPath: fichierSon(r, l).path) }

    /// Efface le son d'une réunion (la note est faite, le réglage ne demande pas de le garder).
    func effacerSon(_ r: Reunion) {
        let urls = [fichierSon(r, .moi), fichierSon(r, .eux)]
        effacerExtraits(r)   // les extraits n'existent que tant que le son de la réunion est gardé
        file.async { for u in urls { try? FileManager.default.removeItem(at: u) } }
        Log.ecrire("réunions : son de la réunion effacé (note prête, tout l'appel relu)")
    }

    private func ecrire(_ r: Reunion) {
        guard let json = ArchiveReunions.encoder(r) else { return }
        let md = ReunionMarkdown.rendre(r).data(using: .utf8) ?? Data()
        let base = ArchiveReunions.nomDeBase(r), dossier = dossier
        file.async {
            let fm = FileManager.default
            try? fm.createDirectory(at: dossier, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            for (nom, donnees) in [("\(base).json", json), ("\(base).md", md)] {
                let url = dossier.appendingPathComponent(nom)
                do { try FichierPrive.ecrire(donnees, vers: url) }
                catch { Log.ecrire("réunions : enregistrement impossible (\(error.localizedDescription))") }
            }
        }
    }
}
