import Foundation

/// « ma signature » dit à voix haute → « Hugues-Henri Delpit » écrit. Appliqué après la transcription et la remise au propre.
public struct RaccourciVocal: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var expression: String
    public var texte: String
    public init(id: UUID = UUID(), expression: String, texte: String) { self.id = id; self.expression = expression; self.texte = texte }
}

public enum RaccourcisVocaux {
    /// Remplace chaque expression trouvée (mots entiers, sans tenir compte des majuscules ni des accents). Les plus longues
    /// d'abord. Si la dictée n'est que l'expression (suivie ou non d'un point), le texte est écrit tel quel, sans point final.
    public static func appliquer(_ texte: String, raccourcis: [RaccourciVocal]) -> String {
        let actifs = raccourcis.filter { !normaliser($0.expression).isEmpty && !$0.texte.isEmpty }
            .sorted { normaliser($0.expression).count > normaliser($1.expression).count }
        guard !actifs.isEmpty, !texte.isEmpty else { return texte }

        // apostrophes courbes → droites : même nombre de caractères, les positions restent alignées
        let origine = Array(texte)
        let travail = Array(texte.replacingOccurrences(of: "\u{2019}", with: "'"))
        var sortie = ""
        var i = 0
        var remplacements = 0
        var dernier = ""
        var seul = true
        while i < travail.count {
            let debutDeMot = i == 0 || !estLettre(travail[i - 1])
            if debutDeMot, estLettre(travail[i]) {
                let reste = String(travail[i...])
                var trouve = false
                for r in actifs {
                    let expr = normaliser(r.expression)
                    guard let plage = reste.range(of: expr, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) else { continue }
                    let n = reste.distance(from: reste.startIndex, to: plage.upperBound)
                    guard i + n >= travail.count || !estLettre(travail[i + n]) else { continue }
                    sortie += r.texte
                    dernier = r.texte
                    i += n
                    remplacements += 1
                    trouve = true
                    break
                }
                if trouve { continue }
                // sauter le mot entier : on ne cherche qu'aux débuts de mots
                var j = i
                while j < travail.count, estLettre(travail[j]) { j += 1 }
                sortie += String(origine[i..<j])
                seul = false
                i = j
            } else {
                if !(travail[i].isWhitespace || ".,;:!?…".contains(travail[i])) { seul = false }
                sortie.append(origine[i])
                i += 1
            }
        }
        guard remplacements > 0 else { return texte }
        // Une dictée réduite à un raccourci (+ ponctuation) : le texte exact, sans point final.
        if remplacements == 1, seul { return dernier }
        return sortie
    }

    static func normaliser(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{2019}", with: "'")
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func estLettre(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "'" || c == "-" }
}

/// Liste des noms à retenir (mots.txt) : ajout sans doublon, suppression, comparés sans casse ni accents.
public enum ListeDeMots {
    public enum Resultat: Equatable, Sendable { case ajoute([String]), dejaPresent, vide }

    public static func ajouter(_ mot: String, a liste: [String]) -> Resultat {
        let propre = mot.trimmingCharacters(in: .whitespacesAndNewlines).split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !propre.isEmpty else { return .vide }
        let cle = Historique.plier(propre)
        if liste.contains(where: { Historique.plier($0) == cle }) { return .dejaPresent }
        return .ajoute(liste + [propre])
    }

    public static func retirer(_ mot: String, de liste: [String]) -> [String] {
        let cle = Historique.plier(mot)
        return liste.filter { Historique.plier($0) != cle }
    }
}

/// Mots proposés d'après les corrections de Hugues : ils attendent toujours une acceptation explicite, jamais ajoutés tout seuls.
public struct PropositionsMots: Codable, Equatable, Sendable {
    public private(set) var enAttente: [String] = []
    /// Mots refusés : on ne les repropose pas.
    public private(set) var ignores: [String] = []
    /// Combien de dictées différentes ont vu corriger ce mot (par mot plié) : au deuxième retour de la même correction, le mot est appris tout seul.
    public private(set) var vus: [String: Int] = [:]
    private var derniereDictee: [String: String] = [:]

    public init() {}

    private enum CodingKeys: String, CodingKey { case enAttente, ignores, vus, derniereDictee }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enAttente = try c.decodeIfPresent([String].self, forKey: .enAttente) ?? []
        ignores = try c.decodeIfPresent([String].self, forKey: .ignores) ?? []
        vus = try c.decodeIfPresent([String: Int].self, forKey: .vus) ?? [:]
        derniereDictee = try c.decodeIfPresent([String: String].self, forKey: .derniereDictee) ?? [:]
    }

    public enum Issue: Equatable, Sendable {
        /// Déjà connu, déjà refusé, ou vide.
        case ignoree
        /// Première fois : proposé dans Mots.
        case proposee
        /// Même dictée, ou deuxième fois pas encore atteinte : rien de plus.
        case dejaVue
        /// La même correction revient dans une autre dictée : le mot est appris tout seul (à ajouter à mots.txt par l'appelant).
        case apprise
    }

    /// Une correction vue dans la dictée `dictee` (un identifiant unique par dictée : lue deux fois, elle ne compte qu'une fois).
    /// Au `seuil`-ième retour dans des dictées différentes, le mot sort de la liste d'attente et doit être ajouté par l'appelant.
    public mutating func noter(_ mot: String, dictee: String, motsConnus: [String], seuil: Int = 2) -> Issue {
        let propre = mot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !propre.isEmpty else { return .ignoree }
        let cle = Historique.plier(propre)
        if (motsConnus + ignores).contains(where: { Historique.plier($0) == cle }) { return .ignoree }
        if enAttente.contains(where: { Historique.plier($0) == cle }) {
            if derniereDictee[cle] == dictee { return .dejaVue }
            let n = (vus[cle] ?? 1) + 1
            derniereDictee[cle] = dictee
            if n >= seuil {
                enAttente.removeAll { Historique.plier($0) == cle }
                vus[cle] = nil; derniereDictee[cle] = nil
                return .apprise
            }
            vus[cle] = n
            return .dejaVue
        }
        enAttente.append(propre)
        vus[cle] = 1; derniereDictee[cle] = dictee
        return .proposee
    }

    /// Propose un mot, sauf s'il est déjà connu, déjà en attente ou déjà refusé. Renvoie `true` si la proposition est nouvelle.
    @discardableResult
    public mutating func proposer(_ mot: String, motsConnus: [String]) -> Bool {
        let propre = mot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !propre.isEmpty else { return false }
        let cle = Historique.plier(propre)
        let deja = (motsConnus + enAttente + ignores).contains { Historique.plier($0) == cle }
        guard !deja else { return false }
        enAttente.append(propre)
        return true
    }

    /// Retire la proposition (le mot est ajouté à la liste par l'appelant) et la renvoie.
    @discardableResult
    public mutating func accepter(_ mot: String) -> String? {
        guard let i = enAttente.firstIndex(of: mot) else { return nil }
        return enAttente.remove(at: i)
    }

    public mutating func ignorer(_ mot: String) {
        guard let i = enAttente.firstIndex(of: mot) else { return }
        ignores.append(enAttente.remove(at: i))
    }
}
