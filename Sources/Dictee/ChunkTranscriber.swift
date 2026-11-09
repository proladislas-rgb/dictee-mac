import Foundation
import DicteeCore

/// Envoie chaque morceau de son à Groq dès qu'il est prêt (en parallèle) et recolle les textes dans l'ordre.
///
/// Trois mécanismes de vitesse :
///  - envoi anticipé (`anticiper`) : à la première pause de 0,3 s, le morceau en cours part déjà ; si la parole reprend, la
///    réponse est jetée, sinon elle est réutilisée au relâchement (même morceau, même son) ;
///  - requête de secours rapide : si Groq tarde (plus de 0,7 s), une seconde requête identique part et la première
///    réponse arrivée gagne ;
///  - tout ceci dans la limite du budget de requêtes (`BudgetRequetes`), le vrai morceau ayant toujours priorité.
final class ChunkTranscriber: @unchecked Sendable {
    enum Resultat {
        case texte(String)
        case echec(String)
        case delai
    }

    struct Sortie { var texte: String? ; var erreur: String?; var retentable = false }

    /// Un morceau envoyé à Groq (ou prêt à l'être, s'il est seulement anticipé).
    final class Morceau: @unchecked Sendable {
        let cle: VoiceChunker.Range
        let duree: Double
        let contexte: String?
        let envoyeLe: Double
        let anticipe: Bool
        /// Vrai si le morceau finit à une pause (ou au relâchement), faux si coupé en pleine parole.
        let finParPause: Bool
        var numero = 0
        var tache: Task<Sortie, Never>!
        var secours: Task<Sortie, Never>?
        /// Le texte reçu de Groq (premier arrivé), pour assembler le texte complet avant même le relâchement.
        var texteRecu: String?
        /// Le son codé (FLAC ou WAV) : rempli au premier besoin, partagé avec la requête de secours.
        let fichier: Task<EncodeurAudio.Fichier, Never>
        init(morceau: MorceauSon, contexte: String?, anticipe: Bool) {
            cle = morceau.cle; duree = morceau.duree; self.contexte = contexte; self.anticipe = anticipe; finParPause = !morceau.coupeForcee
            envoyeLe = ProcessInfo.processInfo.systemUptime
            let echantillons = morceau.echantillons
            fichier = Task.detached(priority: .userInitiated) { EncodeurAudio.encoder(echantillons) }
        }
    }

    /// Réglages de vitesse (modifiables pour les mesures : variables d'environnement `DICTEE_ANTICIPATION=non`, `DICTEE_SECOURS=non`).
    struct Vitesse {
        var anticipation = Settings.envoiAnticipe
        var secours = Settings.requeteDeSecours
        var seuilSecours = 0.7
    }

    /// Appelé quand la réponse d'un envoi anticipé arrive et que tous les morceaux d'avant sont revenus : voici le texte
    /// complet tel qu'il serait si la parole s'arrêtait là (la remise au propre peut déjà commencer).
    var surTexteAnticipe: (([String?]) -> Void)?

    /// Appelé quand la réponse d'un morceau (confirmé, dans l'ordre d'envoi) arrive : (numéro, texte, finit à une pause).
    var surMorceauRevenu: ((Int, String, Bool) -> Void)?

    private let lock = NSLock()
    private var morceaux: [Morceau] = []
    private var enAttente: Morceau?             // envoi anticipé en vol, pas encore confirmé
    private var dernierTexte: String?           // fin du dernier morceau déjà revenu, pour la continuité
    private let mots: [String]
    private let langue: String?
    private let groq: GroqClient
    private let vitesse: Vitesse
    private(set) var anticipesReutilises = 0
    private(set) var anticipesJetes = 0
    private(set) var secoursLances = 0

    init(groq: GroqClient = .shared, mots: [String], langue: String?, vitesse: Vitesse = Vitesse()) {
        self.groq = groq
        self.mots = mots
        self.langue = langue
        self.vitesse = vitesse
    }

    var nombreDeMorceaux: Int { lock.lock(); defer { lock.unlock() }; return morceaux.count }
    var anticipationActive: Bool { vitesse.anticipation }

    /// Lance l'envoi d'un morceau. Ne bloque pas (appelé depuis le fil audio ou le fil principal).
    /// Si ce morceau est exactement celui déjà envoyé à l'avance, la requête en cours est reprise telle quelle.
    func envoyer(_ son: MorceauSon) {
        lock.lock(); defer { lock.unlock() }
        if let a = enAttente {
            enAttente = nil
            if a.cle == son.cle {
                a.numero = morceaux.count + 1
                morceaux.append(a)
                anticipesReutilises += 1
                let avance = Int((ProcessInfo.processInfo.systemUptime - a.envoyeLe) * 1000)
                Log.ecrire("morceau \(a.numero) : envoi anticipé réutilisé (parti \(avance) ms plus tôt)")
                if let t = a.texteRecu { surMorceauRevenu?(a.numero, t, a.finParPause) }
                return
            }
            a.tache.cancel(); a.secours?.cancel()
            anticipesJetes += 1
            Log.ecrire("envoi anticipé jeté : la parole a repris")
        }
        let m = Morceau(morceau: son, contexte: dernierTexte, anticipe: false)
        m.numero = morceaux.count + 1
        m.tache = lancerRequete(m)
        morceaux.append(m)
    }

    /// Envoi anticipé : à la pause, le morceau part déjà, sans être compté. Rien ne part si le budget de requêtes est bas.
    func anticiper(_ son: MorceauSon) {
        guard vitesse.anticipation else { return }
        lock.lock(); defer { lock.unlock() }
        if let a = enAttente {
            if a.cle == son.cle { return }
            a.tache.cancel(); a.secours?.cancel()
            anticipesJetes += 1
            Log.ecrire("envoi anticipé jeté : la parole a repris")
            enAttente = nil
        }
        guard BudgetRequetes.partage.permet(.anticipation) else {
            Log.ecrire("envoi anticipé non fait : budget de requêtes bas (\(BudgetRequetes.partage.restantMinute()) restantes cette minute)")
            return
        }
        let m = Morceau(morceau: son, contexte: dernierTexte, anticipe: true)
        m.numero = morceaux.count + 1
        m.tache = lancerRequete(m)
        enAttente = m
    }

    /// La requête Whisper d'un morceau : codage du son, envoi, journal. Sert aussi à la requête de secours.
    private func lancerRequete(_ m: Morceau, secours: Bool = false) -> Task<Sortie, Never> {
        let (groq, mots, langue) = (self.groq, self.mots, self.langue)
        return Task { [weak self] () -> Sortie in
            guard self != nil else { return Sortie(texte: nil, erreur: "annulé") }
            let prompt = TextAssembler.prompt(mots: mots, contexte: m.contexte)
            let t0 = ProcessInfo.processInfo.systemUptime
            let fichier = await m.fichier.value
            let codage = Int((ProcessInfo.processInfo.systemUptime - t0) * 1000)
            let debut = ProcessInfo.processInfo.systemUptime
            let nom = "morceau \(m.numero)\(secours ? " (secours)" : m.anticipe ? " (anticipé)" : "")"
            do {
                var texte = try await groq.transcrire(fichier: fichier, prompt: prompt, langue: langue, etiquette: nom)
                let ms = Int((ProcessInfo.processInfo.systemUptime - debut) * 1000)
                // Coupé en pleine parole : le point que Whisper met à la fin du morceau n'existe pas dans la phrase.
                if !m.finParPause { texte = TextAssembler.sansPonctuationDeCoupe(texte) }
                Log.ecrire("\(nom) : \(String(format: "%.1f", m.duree)) s de son, \(fichier.nom.hasSuffix("flac") ? "FLAC" : "WAV") \(fichier.donnees.count / 1024) Ko (codage \(codage) ms) -> Groq en \(ms) ms, \"\(Log.apercu(texte))\"")
                self?.noterTexte(texte)
                self?.apresReponse(m, texte: texte)
                return Sortie(texte: texte, erreur: nil)
            } catch is CancellationError {
                return Sortie(texte: nil, erreur: "annulé")
            } catch {
                Log.ecrire("\(nom) : échec Groq (\(error))")
                var retentable = false
                if let e = error as? GroqErreur {
                    switch e { case .reseau: retentable = true; case .http(let c): retentable = c >= 500; default: break }
                }
                return Sortie(texte: nil, erreur: "\(error)", retentable: retentable)
            }
        }
    }

    /// Les textes reçus de tous les morceaux confirmés, dans l'ordre (nil : pas encore revenu).
    func textes() -> [String?] { lock.lock(); defer { lock.unlock() }; return morceaux.map { $0.texteRecu } }

    private func tousLesMorceaux() -> [Morceau] {
        lock.lock(); defer { lock.unlock() }
        let tous = morceaux + (enAttente.map { [$0] } ?? [])
        enAttente = nil
        return tous
    }

    private func copieDesMorceaux() -> [Morceau] { lock.lock(); defer { lock.unlock() }; return morceaux }

    private func apresReponse(_ m: Morceau, texte: String) {
        lock.lock()
        if m.texteRecu == nil { m.texteRecu = texte }
        let enVol = m === enAttente
        let confirme = morceaux.contains { $0 === m }
        let parties = morceaux.map { $0.texteRecu } + [texte]
        let rappelAnticipe = surTexteAnticipe, rappelMorceau = surMorceauRevenu
        let numero = m.numero
        lock.unlock()
        if confirme { rappelMorceau?(numero, texte, m.finParPause) }
        if enVol, let rappelAnticipe, parties.allSatisfy({ $0 != nil }) { rappelAnticipe(parties) }
    }

    private func noterTexte(_ texte: String) {
        lock.lock(); dernierTexte = texte; lock.unlock()
    }

    func annuler() {
        let tous = tousLesMorceaux()
        for m in tous { m.tache.cancel(); m.secours?.cancel() }
    }

    private func texteDejaRecu(_ m: Morceau) -> Bool { lock.lock(); defer { lock.unlock() }; return m.texteRecu != nil }

    private func demarrerSecours(_ m: Morceau) -> Task<Sortie, Never> {
        lock.lock(); defer { lock.unlock() }
        if m.secours == nil { m.secours = lancerRequete(m, secours: true); secoursLances += 1 }
        return m.secours!
    }

    private func retirerEnAttente() -> Morceau? {
        lock.lock(); defer { lock.unlock() }
        let reste = enAttente; enAttente = nil
        return reste
    }

    /// La réponse d'un morceau. Après le relâchement, si elle tarde plus de `seuilSecours` (ou échoue pour une raison
    /// de réseau), une seconde requête identique part, dans la limite du budget : la première réponse arrivée gagne.
    private func valeur(de m: Morceau) async -> Sortie {
        let premier = m.tache!
        guard vitesse.secours, !texteDejaRecu(m) else { return await premier.value }
        let attente = m.envoyeLe + vitesse.seuilSecours - ProcessInfo.processInfo.systemUptime
        if attente > 0 {
            let fini: Sortie? = await withTaskGroup(of: Sortie?.self) { g in
                g.addTask { await premier.value }
                g.addTask { try? await Task.sleep(for: .seconds(attente)); return nil }
                let premier = await g.next() ?? nil
                g.cancelAll()
                return premier
            }
            if let fini, fini.erreur == nil || !fini.retentable { return fini }
        }
        // Soit la réponse tarde, soit la première requête a échoué sur le réseau.
        if premier.isCancelled { return await premier.value }
        guard BudgetRequetes.partage.permet(.secours) else { return await premier.value }
        let second = demarrerSecours(m)
        let apres = Int((ProcessInfo.processInfo.systemUptime - m.envoyeLe) * 1000)
        Log.ecrire("morceau \(m.numero) : réponse attendue depuis \(apres) ms, requête de secours lancée")
        let gagnant: Sortie = await withTaskGroup(of: (Bool, Sortie).self) { g in
            g.addTask { (false, await premier.value) }
            g.addTask { (true, await second.value) }
            var derniere = Sortie(texte: nil, erreur: "aucune réponse")
            for await (estSecours, s) in g {
                if s.texte != nil {
                    Log.ecrire("morceau \(m.numero) : \(estSecours ? "la requête de secours" : "la première requête") a répondu la première")
                    return s
                }
                derniere = s
            }
            return derniere
        }
        premier.cancel(); second.cancel()
        return gagnant
    }

    /// Attend tous les morceaux, au plus `delai` secondes. Un morceau en échec fait échouer le tout :
    /// un texte à trous serait pire qu'un texte de secours complet.
    func resultat(delai: Double) async -> Resultat {
        let liste = copieDesMorceaux()
        if liste.isEmpty { return .texte("") }
        let course = await withTaskGroup(of: Resultat.self) { groupe -> Resultat in
            groupe.addTask { [self] in
                var parties: [String?] = []
                for m in liste {
                    let s = await valeur(de: m)
                    if let e = s.erreur { return .echec(e) }
                    parties.append(s.texte)
                }
                return .texte(TextAssembler.joindre(parties))
            }
            groupe.addTask {
                try? await Task.sleep(for: .seconds(delai))
                return .delai
            }
            let premier = await groupe.next() ?? .delai
            groupe.cancelAll()
            return premier
        }
        if case .texte = course {} else { annuler() }
        // L'envoi anticipé en vol qui n'a pas servi est abandonné.
        if let reste = retirerEnAttente() { reste.tache.cancel(); reste.secours?.cancel() }
        return course
    }
}
