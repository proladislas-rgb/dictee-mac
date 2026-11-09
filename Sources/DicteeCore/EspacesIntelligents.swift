import Foundation

/// Raccord entre une dictée et ce qui précède le curseur : espace à ajouter, minuscule en milieu de phrase.
/// Fonctions pures, testées. `precedent` = les derniers caractères avant le curseur :
///  - `nil`  : on ne sait pas (rien n'est changé) ;
///  - `""`   : début du champ (rien n'est changé).
public enum EspacesIntelligents {
    /// Après ces caractères, on colle sans espace (parenthèse, crochet, guillemet ouvrant, apostrophe).
    private static let ouvrants: Set<Character> = ["(", "[", "{", "«", "“", "‘", "'", "’", "\"", "/", "@"]
    /// Un texte dicté qui commence par l'un de ces signes se colle sans espace devant.
    private static let signesCollants: Set<Character> = [",", ".", ";", ":", "!", "?", "…", ")", "]", "}", "»", "”", "%"]
    private static let finsDePhrase: Set<Character> = [".", "!", "?", "…"]
    private static let refermants: Set<Character> = [")", "]", "}", "»", "”", "’", "'", "\""]
    /// Début de ligne qui ouvre un élément de liste : ce qui suit commence une phrase.
    private static let puces: Set<Character> = ["-", "•", "*", "–", "—", "▪", "◦", "►", ">"]

    public static func adapter(_ texte: String, precedent: String?, mots: [String] = []) -> String {
        guard let precedent, !precedent.isEmpty, let premier = texte.first else { return texte }
        var sortie = texte
        if finDePhrase(precedent: precedent) == false {
            sortie = minusculeDebut(sortie, mots: mots)
        }
        if besoinEspace(precedent: precedent, premierCaractere: premier) { sortie = " " + sortie }
        return sortie
    }

    /// Faut-il une espace entre ce qui précède et le texte qui commence par `premierCaractere` ?
    public static func besoinEspace(precedent: String, premierCaractere: Character) -> Bool {
        guard let dernier = precedent.last else { return false }
        if dernier.isWhitespace || dernier.isNewline { return false }
        if ouvrants.contains(dernier) { return false }
        if premierCaractere.isWhitespace || signesCollants.contains(premierCaractere) { return false }
        return true
    }

    /// `true` : le curseur est au début d'une phrase (début de champ, de ligne, après . ! ? ou une puce).
    /// `false` : la phrase continue. `nil` : on ne sait pas.
    public static func finDePhrase(precedent: String?) -> Bool? {
        guard let precedent else { return nil }
        if precedent.isEmpty { return true }
        // Un retour à la ligne dans les espaces qui précèdent le curseur : nouvelle ligne.
        var reste = Substring(precedent)
        var retour = false
        while let c = reste.last, c.isWhitespace || c.isNewline {
            if c.isNewline { retour = true }
            reste = reste.dropLast()
        }
        if retour || reste.isEmpty { return true }
        // On saute les fermants (guillemets, parenthèses) : « Il a dit non. » + suite.
        var sansFermants = reste
        while let c = sansFermants.last, refermants.contains(c) || c.isWhitespace { sansFermants = sansFermants.dropLast() }
        guard let dernier = sansFermants.last else { return false }
        if finsDePhrase.contains(dernier) { return true }
        // Une puce de liste seule sur sa ligne : « - » (le texte qui suit est une phrase neuve).
        if puces.contains(dernier) {
            let ligne = sansFermants.split(whereSeparator: { $0.isNewline }).last ?? sansFermants
            if ligne.allSatisfy({ puces.contains($0) || $0.isWhitespace }) { return true }
        }
        return false
    }

    /// Met la première lettre en minuscule, sauf pour un sigle, un mot déjà mixte (iPhone), le « I » anglais
    /// ou un mot du dictionnaire.
    public static func minusculeDebut(_ texte: String, mots: [String]) -> String {
        guard let debut = texte.firstIndex(where: { $0.isLetter }) else { return texte }
        // Seuls des signes ouvrants peuvent précéder la première lettre ; sinon (un chiffre, par ex.) on ne touche à rien.
        guard texte[texte.startIndex..<debut].allSatisfy({ !$0.isNumber && !$0.isLetter }) else { return texte }
        let premiere = texte[debut]
        guard premiere.isUppercase else { return texte }

        let mot = texte[debut...].prefix(while: { $0.isLetter || $0.isNumber })
        let nom = String(mot)
        // Sigle ou mot mixte : une autre majuscule après la première lettre (API, iPhone → déjà minuscule, McDo…).
        if nom.dropFirst().contains(where: { $0.isUppercase }) { return texte }
        // « I » seul, « I'm », « I'll », « I've » (anglais).
        if nom == "I" { return texte }
        // Mot du dictionnaire (entrées de plusieurs mots comprises : « Premium CI »).
        let reste = texte[debut...].lowercased()
        for entree in mots {
            let e = entree.trimmingCharacters(in: .whitespaces).lowercased()
            guard !e.isEmpty, reste.hasPrefix(e) else { continue }
            let suite = reste.dropFirst(e.count).first
            if suite == nil || !(suite!.isLetter || suite!.isNumber) { return texte }
        }
        var sortie = texte
        sortie.replaceSubrange(debut...debut, with: String(premiere).lowercased())
        return sortie
    }
}

/// Mémoire de la dernière insertion : sert de repli quand l'app ne dit pas ce qu'il y a avant le curseur.
/// Le curseur est supposé suivre la dernière insertion si : même app, moins de 2 minutes, aucune touche tapée depuis.
public struct MemoireInsertion: Sendable {
    public var appId: String
    public var queue: String
    public var instant: Double
    public var frappes: Int

    public init(appId: String, queue: String, instant: Double, frappes: Int) {
        self.appId = appId; self.queue = queue; self.instant = instant; self.frappes = frappes
    }

    public static let validite: Double = 120

    /// Les 200 derniers caractères d'un texte inséré (assez pour juger la fin de phrase).
    public static func queue(de texte: String) -> String { String(texte.suffix(200)) }

    /// Ce qui précède le curseur d'après la dernière insertion, ou `nil` si elle n'est plus fiable.
    public func precedent(appId: String?, instant: Double, frappes: Int) -> String? {
        guard let appId, appId == self.appId, instant - self.instant < Self.validite, frappes == self.frappes else { return nil }
        return queue
    }
}
