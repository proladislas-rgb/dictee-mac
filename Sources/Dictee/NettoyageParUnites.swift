import Foundation
import DicteeCore

/// Lance la remise au propre de chaque unité de phrases (voir `DecoupeEnUnites`) pendant que la dictée continue.
/// Au texte final, `resultat` rassemble les unités déjà traitées et la queue ; ou rend `nil` si le découpage n'est pas
/// sûr (correction ou liste d'une unité à l'autre, endroit différent de celui du départ…) : l'appelant remet alors le
/// texte entier au propre, comme avant.
final class NettoyageParUnites: @unchecked Sendable {
    private struct Travail { var unite: DecoupeEnUnites.Unite; var contexte: ContexteMiseEnForme; var tache: Task<Nettoyage.Resultat, Never>? }

    private let verrou = NSLock()
    private var decoupe = DecoupeEnUnites()
    private var travaux: [Travail] = []
    private var queueAnticipee: (brut: String, contexte: ContexteMiseEnForme, tache: Task<Nettoyage.Resultat, Never>)?
    private let mots: [String]
    private let contexteActuel: @Sendable () -> ContexteMiseEnForme
    private let relecture: RelectureSession?

    init(mots: [String], relecture: RelectureSession? = nil, contexteActuel: @escaping @Sendable () -> ContexteMiseEnForme) {
        self.mots = mots
        self.relecture = relecture
        self.contexteActuel = contexteActuel
    }

    var nombreDUnites: Int { verrou.lock(); defer { verrou.unlock() }; return travaux.count }

    /// Un morceau est revenu de Groq (appelé depuis le fil de la requête).
    func morceauRevenu(numero: Int, texte: String, finParPause: Bool) {
        guard Settings.nettoyageParUnites, Settings.remettreAuPropre, GroqClient.shared.cleDisponible else { return }
        let contexte = contexteActuel()
        guard DecoupeEnUnites.contexteAdapte(contexte) else { return }
        let nouvelles = decouper(numero: numero, texte: texte, finParPause: finParPause)
        for u in nouvelles {
            // Pas de place dans le budget : l'unité sera traitée au relâchement avec le reste.
            let tache: Task<Nettoyage.Resultat, Never>? = BudgetRequetes.nettoyage.permet(.anticipation)
                ? lancer(u.brut, contexte: contexte) : nil
            ajouter(Travail(unite: u, contexte: contexte, tache: tache))
            Log.ecrire("remise au propre par unité : morceaux \(u.debut)–\(u.fin) (\(u.brut.split(separator: " ").count) mots) \(tache == nil ? "gardée pour la fin (budget)" : "lancée pendant la dictée")")
        }
    }

    private func decouper(numero: Int, texte: String, finParPause: Bool) -> [DecoupeEnUnites.Unite] {
        verrou.lock(); defer { verrou.unlock() }
        return decoupe.recevoir(numero: numero, texte: texte, finParPause: finParPause)
    }
    private func ajouter(_ t: Travail) { verrou.lock(); travaux.append(t); verrou.unlock() }

    private func lancer(_ brut: String, contexte: ContexteMiseEnForme) -> Task<Nettoyage.Resultat, Never> {
        let (mots, relecture) = (self.mots, self.relecture)
        return Task.detached(priority: .userInitiated) { await Nettoyage.executer(brut, contexte: contexte, mots: mots, finDeTexte: false, relecture: relecture) }
    }

    /// La queue (morceaux après la dernière unité) connue à la pause d'avant le relâchement : sa remise au propre part déjà.
    /// `parties` : textes de tous les morceaux, y compris le dernier envoyé à l'avance. Renvoie faux si rien n'a été fait.
    @discardableResult
    func anticiperQueue(parties: [String?]) -> Bool {
        guard Settings.remettreAuPropre, GroqClient.shared.cleDisponible, BudgetRequetes.nettoyage.permet(.anticipation) else { return false }
        let (queue, contexte): (String, ContexteMiseEnForme) = {
            verrou.lock(); defer { verrou.unlock() }
            return (decoupe.queue(parties: parties), contexteActuel())
        }()
        guard !queue.isEmpty, RemiseAuPropre.analyser(queue).utile, DecoupeEnUnites.contexteAdapte(contexte) else { return false }
        verrou.lock()
        if let q = queueAnticipee {
            if q.brut == queue && q.contexte == contexte { verrou.unlock(); return true }
            q.tache.cancel()
        }
        queueAnticipee = (queue, contexte, lancer(queue, contexte: contexte))
        verrou.unlock()
        Log.ecrire("remise au propre de la queue lancée à l'avance (pause en cours)")
        return true
    }

    /// Texte final remis au propre à partir des unités, ou `nil` si le découpage n'est pas utilisable. `parties` : textes de tous
    /// les morceaux dans l'ordre. `contexte` : l'endroit connu au relâchement (doit être celui du départ des unités).
    func resultat(parties: [String?], contexte: ContexteMiseEnForme) async -> Nettoyage.Resultat? {
        let (travaux, queue, anticipee) = etat(parties: parties)
        guard !travaux.isEmpty, DecoupeEnUnites.contexteAdapte(contexte) else { annulerTout(); return nil }
        guard travaux.allSatisfy({ $0.contexte == contexte }) else { annulerTout(); Log.ecrire("unités jetées : l'endroit a changé"); return nil }
        let pieces = travaux.map { $0.unite.brut } + (queue.isEmpty ? [] : [queue])
        guard DecoupeEnUnites.separationSure(pieces) else { annulerTout(); Log.ecrire("unités jetées : correction ou liste entre deux morceaux"); return nil }

        let debut = ProcessInfo.processInfo.systemUptime
        let (mots, relecture) = (self.mots, self.relecture)
        // Chaque pièce : déjà lancée, ou lancée maintenant (en parallèle avec les autres).
        var taches = travaux.map { $0.tache ?? lancer($0.unite.brut, contexte: contexte) }
        if !queue.isEmpty {
            if let a = anticipee, a.brut == queue, a.contexte == contexte { taches.append(a.tache) }
            else { anticipee?.tache.cancel(); taches.append(Task.detached(priority: .userInitiated) { await Nettoyage.executer(queue, contexte: contexte, mots: mots, finDeTexte: false, relecture: relecture) }) }
        }
        var resultats: [Nettoyage.Resultat] = []
        for t in taches { resultats.append(await t.value) }
        var texte = DecoupeEnUnites.assembler(resultats.map(\.texte))
        if contexte == .terminal || contexte == .recherche { texte = TextFormatter.sansPointFinal(texte) }
        let utilise = resultats.filter(\.utilise).count
        let attente = ProcessInfo.processInfo.systemUptime - debut
        return Nettoyage.Resultat(texte: texte, utilise: utilise > 0,
                                  raison: utilise > 0 ? "ok" : "inutile (aucune partie à corriger)",
                                  duree: attente, sortieRefusee: nil)
            .avecDetail("par \(pieces.count) partie(s) dont \(travaux.filter { $0.tache != nil }.count) lancée(s) pendant la dictée")
    }

    private func etat(parties: [String?]) -> ([Travail], String, (brut: String, contexte: ContexteMiseEnForme, tache: Task<Nettoyage.Resultat, Never>)?) {
        verrou.lock(); defer { verrou.unlock() }
        return (travaux, decoupe.queue(parties: parties), queueAnticipee)
    }

    func annulerTout() {
        verrou.lock()
        let t = travaux.compactMap(\.tache) + (queueAnticipee.map { [$0.tache] } ?? [])
        verrou.unlock()
        t.forEach { $0.cancel() }
    }
}

private extension Nettoyage.Resultat {
    func avecDetail(_ detail: String) -> Nettoyage.Resultat {
        var r = self
        r.raison = r.raison + " (" + detail + ")"
        return r
    }
}
