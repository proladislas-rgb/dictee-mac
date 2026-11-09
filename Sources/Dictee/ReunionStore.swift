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
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Dictee/Reunions", isDirectory: true)
    }

    /// `lire = false` : aucun accès au disque (rendus PNG avec des réunions d'exemple).
    init(dossier: URL? = nil, lire: Bool = true) {
        self.dossier = dossier ?? Self.dossierParDefaut
        guard lire else { return }
        try? FileManager.default.createDirectory(at: self.dossier, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
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
    }

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
        let base = ArchiveReunions.nomDeBase(r), dossier = dossier
        file.async {
            let fm = FileManager.default
            for nom in ["\(base).json", "\(base).md", "\(base)-moi.wav", "\(base)-eux.wav"] { try? fm.removeItem(at: dossier.appendingPathComponent(nom)) }
        }
        Log.ecrire("réunions : une réunion effacée")
    }

    /// Les fichiers du son brut d'une réunion en cours (réglage « Garder le son des réunions »).
    func fichierSon(_ r: Reunion, _ l: Locuteur) -> URL {
        dossier.appendingPathComponent("\(ArchiveReunions.nomDeBase(r))-\(l.rawValue).wav")
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
                do {
                    try donnees.write(to: url, options: .atomic)
                    try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                } catch { Log.ecrire("réunions : enregistrement impossible (\(error.localizedDescription))") }
            }
        }
    }
}
