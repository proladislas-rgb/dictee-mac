import Foundation

/// Remise au propre d'une longue dictée par « unités » pendant qu'elle se poursuit, pour qu'au relâchement il ne reste
/// que la dernière à traiter. Une unité est une suite de morceaux consécutifs qui finit par une phrase complète
/// (point, ?, !, …) à une vraie pause (jamais à une coupe forcée en pleine parole). Logique pure, testée par `DicteeControles`.
///
/// Prudence : si une correction dite ou une liste pourrait courir d'une unité à la suivante, ou si l'endroit est un
/// courriel / une note / un assistant (paragraphes décidés sur le texte entier), on ne s'en sert pas et le texte entier
/// est remis au propre d'un coup, comme avant.
public struct DecoupeEnUnites: Sendable {
    public struct Unite: Equatable, Sendable {
        public var debut: Int      // numéros de morceaux, à partir de 1, bornes comprises
        public var fin: Int
        public var brut: String
    }

    private var textes: [Int: String] = [:]
    private var pauses: [Int: Bool] = [:]
    public private(set) var unites: [Unite] = []
    private var prochain = 1
    public init() {}

    /// Numéro du premier morceau qui n'est dans aucune unité fermée.
    public var premierMorceauOuvert: Int { prochain }

    /// Un morceau est revenu de Groq. `finParPause` : il se termine à une pause (ou au relâchement), pas en pleine parole.
    /// Renvoie les unités qui viennent de se fermer.
    public mutating func recevoir(numero: Int, texte: String, finParPause: Bool) -> [Unite] {
        textes[numero] = texte
        pauses[numero] = finParPause
        var nouvelles: [Unite] = []
        var k = prochain
        while let t = textes[k] {
            if pauses[k] == true, Self.finitUnePhrase(t) {
                let brut = TextAssembler.joindre((prochain...k).map { textes[$0] })
                let u = Unite(debut: prochain, fin: k, brut: brut)
                unites.append(u); nouvelles.append(u)
                prochain = k + 1
            }
            k += 1
        }
        return nouvelles
    }

    /// Le texte des morceaux hors unités, d'après les textes de tous les morceaux (dans l'ordre, numéro 1 à n).
    public func queue(parties: [String?]) -> String {
        guard prochain <= parties.count else { return "" }
        return TextAssembler.joindre(Array(parties[(prochain - 1)...]))
    }

    public static func finitUnePhrase(_ texte: String) -> Bool {
        var t = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        while let d = t.last, "\"»”)]’'".contains(d) || d.isWhitespace { t.removeLast() }
        guard let dernier = t.last else { return false }
        return ".?!…".contains(dernier)
    }

    /// Les remises au propre par unité ne valent que là où le texte n'a pas besoin d'être vu en entier pour être mis en forme.
    public static func contexteAdapte(_ c: ContexteMiseEnForme) -> Bool {
        switch c {
        case .general, .messagerie, .terminal, .recherche: return true
        case .courriel, .notes, .assistantIA: return false
        }
    }

    /// Peut-on remettre au propre ces morceaux séparément (aucune correction ni liste ne court d'un morceau à l'autre) ?
    public static func separationSure(_ morceaux: [String]) -> Bool {
        let pleins = morceaux.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if pleins.contains(where: RemiseAuPropre.contientUneListe) { return false }
        return !pleins.dropFirst().contains(where: RemiseAuPropre.commenceParUneCorrection)
    }

    /// Recolle les morceaux remis au propre : une espace entre eux, sauf après un retour à la ligne.
    public static func assembler(_ morceaux: [String]) -> String {
        var sortie = ""
        for m in morceaux {
            let t = m.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { continue }
            if sortie.isEmpty || sortie.hasSuffix("\n") { sortie += t } else { sortie += " " + t }
        }
        return sortie
    }
}
