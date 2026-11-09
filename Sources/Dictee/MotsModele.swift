import Foundation
import DicteeCore

/// Ce que l'onglet Mots montre et modifie : les noms à retenir (mots.txt, envoyés à Whisper), les raccourcis vocaux
/// (raccourcis.json, appliqués après la transcription et la remise au propre) et les propositions en attente
/// (propositions.json : jamais acceptées sans un geste de Hugues).
@MainActor
final class MotsModele: ObservableObject {
    static let partage = MotsModele(persistant: true)

    @Published private(set) var mots: [String]
    @Published private(set) var raccourcis: [RaccourciVocal]
    @Published private(set) var propositions: PropositionsMots
    /// Phrase sobre sous le champ d'ajout (« déjà dans la liste »).
    @Published var message: String?
    private let persistant: Bool

    init(persistant: Bool, mots: [String] = [], raccourcis: [RaccourciVocal] = [], propositions: PropositionsMots = PropositionsMots()) {
        self.persistant = persistant
        if persistant {
            Dictionnaire.creerSiAbsent()
            self.mots = Dictionnaire.mots()
            self.raccourcis = Self.lire([RaccourciVocal].self, "raccourcis.json") ?? []
            self.propositions = Self.lire(PropositionsMots.self, "propositions.json") ?? PropositionsMots()
        } else {
            self.mots = mots; self.raccourcis = raccourcis; self.propositions = propositions
        }
    }

    // MARK: mots

    func ajouterMot(_ saisie: String) {
        switch ListeDeMots.ajouter(saisie, a: mots) {
        case .ajoute(let liste):
            mots = liste; message = nil; sauverMots()
        case .dejaPresent:
            message = "\u{00AB}\u{00A0}\(saisie.trimmingCharacters(in: .whitespaces))\u{00A0}\u{00BB} est déjà dans la liste."
        case .vide: break
        }
    }

    func retirerMot(_ mot: String) { mots = ListeDeMots.retirer(mot, de: mots); message = nil; sauverMots() }

    // MARK: raccourcis vocaux

    /// Renvoie `false` (et explique) si l'expression ou le texte est vide, ou si l'expression existe déjà.
    @discardableResult
    func ajouterRaccourci(expression: String, texte: String) -> Bool {
        let e = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !e.isEmpty, !t.isEmpty else { return false }
        if raccourcis.contains(where: { Historique.plier($0.expression) == Historique.plier(e) }) {
            message = "\u{00AB}\u{00A0}\(e)\u{00A0}\u{00BB} existe déjà comme raccourci."
            return false
        }
        raccourcis.append(RaccourciVocal(expression: e, texte: t))
        message = nil
        sauverRaccourcis()
        return true
    }

    func retirerRaccourci(_ r: RaccourciVocal) { raccourcis.removeAll { $0.id == r.id }; sauverRaccourcis() }

    // MARK: propositions (acceptation explicite)

    func accepter(_ mot: String) {
        if propositions.accepter(mot) != nil { ajouterMot(mot) }
        sauverPropositions()
    }
    func ignorer(_ mot: String) { propositions.ignorer(mot); sauverPropositions() }

    /// Pour le lot 8 (apprentissage des corrections) : propose un mot sans jamais l'ajouter.
    func proposer(_ mot: String) {
        if propositions.proposer(mot, motsConnus: mots) { sauverPropositions() }
    }

    // MARK: fichiers

    private static var dossier: URL {
        let d = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Dictee", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    private static func lire<T: Decodable>(_ type: T.Type, _ nom: String) -> T? {
        guard let d = try? Data(contentsOf: dossier.appendingPathComponent(nom)) else { return nil }
        return try? JSONDecoder().decode(type, from: d)
    }
    private func ecrire<T: Encodable>(_ valeur: T, _ nom: String) {
        guard persistant else { return }
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let d = try? e.encode(valeur) else { return }
        let url = Self.dossier.appendingPathComponent(nom)
        do {
            try d.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch { Log.ecrire("\(nom) : enregistrement impossible (\(error.localizedDescription))") }
    }
    private func sauverMots() { if persistant { Dictionnaire.enregistrer(mots) } }
    private func sauverRaccourcis() { ecrire(raccourcis, "raccourcis.json") }
    private func sauverPropositions() { ecrire(propositions, "propositions.json") }
}
