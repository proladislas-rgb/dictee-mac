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
    private var contigus = 0      // morceaux reçus sans trou depuis le n° 1
    private var consomme = 0      // caractères du texte recollé déjà rangés dans des unités
    public init() {}

    /// Un morceau est revenu de Groq. `finParPause` : il se termine à une pause (ou au relâchement), pas en pleine parole.
    /// Renvoie les unités qui viennent de se fermer.
    ///  - À une pause : si le texte restant finit une phrase, tout le reste forme une unité.
    ///  - Coupe en pleine parole (dictée d'une traite) : le morceau finit au milieu d'une phrase ; on ferme l'unité à la dernière fin de phrase
    ///    que Whisper a ponctuée DANS le texte (au moins 7 mots avant), le bout de phrase qui suit reste pour le morceau suivant.
    public mutating func recevoir(numero: Int, texte: String, finParPause: Bool) -> [Unite] {
        textes[numero] = texte
        pauses[numero] = finParPause
        var nouvelles: [Unite] = []
        while let _ = textes[contigus + 1] {
            contigus += 1
            let tout = TextAssembler.joindre((1...contigus).map { textes[$0] })
            let reste = Self.apres(tout, consomme)
            var coupe: Int?   // nombre de caractères de `reste` à ranger dans l'unité
            if pauses[contigus] == true {
                if Self.finitUnePhrase(reste) { coupe = reste.count }
            } else if let c = Self.derniereFinDePhrase(reste), RemiseAuPropre.mots(String(reste.prefix(c))).count >= Self.motsMini {
                coupe = c
            }
            if let coupe {
                let brut = String(reste.prefix(coupe)).trimmingCharacters(in: .whitespacesAndNewlines)
                let u = Unite(debut: unites.last.map { $0.fin } ?? 1, fin: contigus, brut: brut)
                unites.append(u); nouvelles.append(u)
                consomme += (tout.count - consomme) - (reste.count - coupe)
            }
        }
        return nouvelles
    }

    /// Le texte des morceaux hors unités, d'après les textes de tous les morceaux (dans l'ordre, numéro 1 à n).
    public func queue(parties: [String?]) -> String {
        Self.apres(TextAssembler.joindre(parties), consomme).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static let motsMini = 7

    private static func apres(_ texte: String, _ n: Int) -> String {
        String(texte.dropFirst(min(n, texte.count))).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Position (en caractères, fin comprise) de la dernière fin de phrase DANS le texte : « . ? ! … » suivi d'une espace puis d'une
    /// majuscule, après un mot d'au moins 3 lettres (pas « M. Dupont », pas « 3. »). `nil` s'il n'y en a pas avant la toute fin.
    public static func derniereFinDePhrase(_ texte: String) -> Int? {
        let c = Array(texte)
        guard c.count > 4 else { return nil }
        var i = c.count - 2
        while i >= 3 {
            if ".?!…".contains(c[i]), c[i + 1].isWhitespace {
                var j = i + 1
                while j < c.count, c[j].isWhitespace { j += 1 }
                let k = c[i - 1] == " " ? i - 1 : i   // « monde ? » : l'espace française avant ? ! : ;
                if j < c.count, c[j].isUppercase, k >= 3, c[(k - 3)..<k].allSatisfy({ $0.isLetter }) { return i + 1 }
            }
            i -= 1
        }
        return nil
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
