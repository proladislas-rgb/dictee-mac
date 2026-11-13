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
    /// Les expressions personnelles (extraites de l'historique, modifiables) et le nombre de mots / expressions appris cette semaine.
    @Published private(set) var expressions: [ExpressionPerso] = []
    @Published private(set) var apprisCetteSemaine = 0
    /// Phrase sobre sous le champ d'ajout (« déjà dans la liste »).
    @Published var message: String?
    private let persistant: Bool

    init(persistant: Bool, mots: [String] = [], raccourcis: [RaccourciVocal] = [], propositions: PropositionsMots = PropositionsMots(),
         expressions: [ExpressionPerso] = [], apprisCetteSemaine: Int = 0) {
        self.persistant = persistant
        if persistant {
            Dictionnaire.creerSiAbsent()
            self.mots = Dictionnaire.mots()
            self.raccourcis = Self.lire([RaccourciVocal].self, "raccourcis.json") ?? []
            self.propositions = Self.lire(PropositionsMots.self, "propositions.json") ?? PropositionsMots()
            rafraichirExpressions()
        } else {
            self.mots = mots; self.raccourcis = raccourcis; self.propositions = propositions
            self.expressions = expressions; self.apprisCetteSemaine = apprisCetteSemaine
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

    /// Une correction de Hugues vue après la dictée `dictee` (identifiant unique). Première fois : proposée dans Mots. La même correction dans une
    /// autre dictée : le mot est appris tout seul (ajouté à mots.txt, compté dans « appris cette semaine »).
    @discardableResult
    func noterCorrection(_ mot: String, dictee: String) -> PropositionsMots.Issue {
        let issue = propositions.noter(mot, dictee: dictee, motsConnus: mots)
        switch issue {
        case .proposee, .dejaVue: sauverPropositions()
        case .apprise:
            ajouterMot(mot)
            sauverPropositions()
            ExpressionsStore.partage.modifier { $0.noterMotAppris(mot) }
            rafraichirExpressions()
        case .ignoree: break
        }
        return issue
    }

    // MARK: expressions personnelles

    func rafraichirExpressions() {
        guard persistant else { return }
        let l = ExpressionsStore.partage.liste()
        expressions = l.expressions
        apprisCetteSemaine = l.apprisCetteSemaine()
    }

    @discardableResult
    func ajouterExpression(_ saisie: String) -> Bool {
        let t = saisie.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        var ajoutee = false
        ExpressionsStore.partage.modifier { ajoutee = $0.ajouterManuelle(t) }
        if ajoutee { message = nil } else { message = "\u{00AB}\u{00A0}\(t)\u{00A0}\u{00BB} est déjà dans tes expressions." }
        rafraichirExpressions()
        return ajoutee
    }

    func retirerExpression(_ texte: String) {
        ExpressionsStore.partage.modifier { $0.retirer(texte) }
        rafraichirExpressions()
    }

    /// Une fois par jour (au plus), sans geste : relit l'historique et met à jour les expressions fréquentes de Hugues.
    /// Rien n'est lu si l'historique a moins de 10 dictées.
    func apprendreDeLHistorique(force: Bool = false) {
        guard persistant, Settings.apprentissageDesCorrections || force else { return }
        guard force || ExpressionsStore.partage.liste().extractionDue() else { return }
        let textes = HistoriqueStore.shared.historique.entrees.prefix(3000).map(\.texte)
        guard textes.count >= 10 else { return }
        let existants = mots, exclues = ExpressionsStore.partage.liste().exclues
        let debut = ProcessInfo.processInfo.systemUptime
        Task.detached(priority: .utility) {
            // Le correcteur orthographique vit sur le fil principal : on l'interroge de là, sans bloquer la dictée.
            let extraites = ExtractionExpressions.extraire(textes: textes, existants: existants, exclues: exclues,
                                                           estConnu: { mot in DispatchQueue.main.sync { MainActor.assumeIsolated { Orthographe.estConnu(mot) } } })
            await MainActor.run {
                var nouvelles: [String] = []
                ExpressionsStore.partage.modifier { nouvelles = $0.fusionner(extraites: extraites) }
                Log.ecrire("expressions : \(extraites.count) trouvées dans \(textes.count) dictées en \(Int((ProcessInfo.processInfo.systemUptime - debut) * 1000)) ms\(nouvelles.isEmpty ? "" : ", nouvelles : " + nouvelles.map { Log.apercu($0) }.joined(separator: ", "))")
                MotsModele.partage.rafraichirExpressions()
            }
        }
    }

    // MARK: fichiers

    private static var dossier: URL {
        let d = DossierVerbe.url()
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    private static func lire<T: Decodable>(_ type: T.Type, _ nom: String) -> T? {
        let url = dossier.appendingPathComponent(nom)
        guard let d = try? Data(contentsOf: url) else { return nil }
        if let v = try? JSONDecoder().decode(type, from: d) { return v }
        // illisible : mis de côté (avant : la liste repartait vide et la prochaine écriture effaçait les raccourcis, sans un mot au journal)
        FichierIllisible.mettreDeCote(url, nom: nom, journal: { Log.ecrire($0) })
        return nil
    }
    private func ecrire<T: Encodable>(_ valeur: T, _ nom: String) {
        guard persistant else { return }
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let d = try? e.encode(valeur) else { return }
        let url = Self.dossier.appendingPathComponent(nom)
        do { try FichierPrive.ecrire(d, vers: url) }
        catch { Log.ecrire("\(nom) : enregistrement impossible (\(error.localizedDescription))") }
    }
    private func sauverMots() { if persistant { Dictionnaire.enregistrer(mots) } }
    private func sauverRaccourcis() { ecrire(raccourcis, "raccourcis.json") }
    private func sauverPropositions() { ecrire(propositions, "propositions.json") }
}
