import Foundation

/// Un son gardé pour le test de précision (« Garder le son des 50 prochaines dictées ») : le texte que Verbe a écrit et le texte brut de Groq.
/// Les fichiers vivent dans `Application Support/Dictee/test-precision/` (0600, jamais dans git, effacés sur demande).
public struct EchantillonPrecision: Codable, Equatable, Sendable {
    public var numero: Int
    public var date: Date
    public var appId: String?
    public var appNom: String?
    public var modele: String
    public var langue: String?
    public var texteGroq: String
    public var texteFinal: String
    public var duree: Double
    public init(numero: Int, date: Date, appId: String?, appNom: String?, modele: String, langue: String?, texteGroq: String, texteFinal: String, duree: Double) {
        self.numero = numero; self.date = date; self.appId = appId; self.appNom = appNom; self.modele = modele; self.langue = langue
        self.texteGroq = texteGroq; self.texteFinal = texteFinal; self.duree = duree
    }
}

/// Logique pure du test de précision : combien de dictées, noms de fichiers, comparaison de deux textes.
public enum TestPrecision {
    public static let nombreDeDictees = 50

    public static func nomDeFichier(numero: Int) -> String { String(format: "dictee-%03d", numero) }

    /// Le numéro suivant d'après les noms de fichiers déjà là (`dictee-007.wav`, `dictee-007.json`…).
    public static func prochainNumero(fichiers: [String]) -> Int {
        let n = fichiers.compactMap { nom -> Int? in
            guard nom.hasPrefix("dictee-") else { return nil }
            return Int(nom.dropFirst(7).prefix(while: \.isNumber))
        }.max() ?? 0
        return n + 1
    }

    /// Restant après un son gardé (jamais négatif). 0 : le test s'arrête tout seul.
    public static func apresUnSon(restant: Int) -> Int { max(0, restant - 1) }

    /// Mots d'un texte pour comparer : sans casse, accents ni ponctuation.
    public static func mots(_ s: String) -> [String] { RemiseAuPropre.mots(s) }

    /// Deux textes sont « différents » s'ils n'ont pas les mêmes mots (la ponctuation et les majuscules seules ne comptent pas).
    public static func different(_ a: String, _ b: String) -> Bool { mots(a) != mots(b) }

    /// Les mots qui diffèrent entre `a` et `b` (ceux de `a` qui ne sont pas dans `b`, ceux de `b` qui ne sont pas dans `a`), pour la lecture du tableau.
    public static func ecarts(_ a: String, _ b: String) -> (retires: [String], ajoutes: [String]) { Relecture.ecarts(a, b) }
}
