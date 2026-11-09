import Foundation

/// Reconstitue une adresse mail ou web dictée : « jean point dupont arobase gmail point com » → « jean.dupont@gmail.com »,
/// « www point sillonia point fr » → « www.sillonia.fr ». Règle locale, sans IA, appliquée au texte final (après la remise au
/// propre, avant les raccourcis vocaux) : elle sert aussi quand la remise au propre n'a pas lieu (dictée courte).
///
/// - « arobase » (ou « @ » resté seul) déclenche une adresse mail ; « www » suivi de « point » une adresse web. Rien d'autre :
///   « point com » seul dans une phrase n'est jamais transformé.
/// - Avant l'arobase : lettres et chiffres épelés collés (« h 2 d e l p i t »), mots entiers, « point », « tiret »,
///   « tiret du bas » / « underscore ». Après : le domaine, qui doit finir par une extension connue (com, fr, net, org…).
/// - Aucune espace dans l'adresse, tout en minuscules, accents retirés. La ponctuation de phrase autour (virgule, point final,
///   parenthèse) reste à sa place.
/// Logique pure, vérifiée par `DicteeControles`.
public enum AdressesDictees {
    public static let extensions: Set<String> = [
        "com", "fr", "net", "org", "eu", "io", "be", "ch", "de", "es", "it", "uk", "co", "info", "biz", "me", "app", "dev", "ai", "tv",
        "ca", "us", "pro", "ci", "sn", "ma", "tn", "cm", "lu", "nl", "pt", "edu", "gov", "xyz", "online", "site", "tech", "cloud",
    ]

    // MARK: jetons

    private struct Jeton {
        var texte: String
        var apres: String     // les espaces qui suivent
    }

    private static let ponctuationDebut: Set<Character> = ["(", "«", "\"", "\u{201C}"]
    private static let ponctuationFin: Set<Character> = [".", ",", ";", ":", "!", "?", "…", ")", "»", "\"", "\u{201D}"]

    private static func decouper(_ texte: String) -> (debut: String, jetons: [Jeton]) {
        var debut = ""
        var jetons: [Jeton] = []
        var mot = "", espaces = ""
        func fermer() { if !mot.isEmpty { jetons.append(Jeton(texte: mot, apres: espaces)); mot = ""; espaces = "" } }
        for c in texte {
            if c.isWhitespace {
                if mot.isEmpty { if jetons.isEmpty { debut.append(c) } else { jetons[jetons.count - 1].apres.append(c) } } else { espaces.append(c) }
            } else {
                if !espaces.isEmpty { fermer() }
                mot.append(c)
            }
        }
        fermer()
        // « jean@gmail.com » → « jean », « @ », « gmail.com » (recollés tels quels si aucune adresse n'en sort)
        var eclates: [Jeton] = []
        for j in jetons {
            guard j.texte.contains("@"), j.texte != "@" else { eclates.append(j); continue }
            var morceaux: [String] = [], courant = ""
            for c in j.texte {
                if c == "@" { if !courant.isEmpty { morceaux.append(courant); courant = "" }; morceaux.append("@") } else { courant.append(c) }
            }
            if !courant.isEmpty { morceaux.append(courant) }
            for (i, m) in morceaux.enumerated() { eclates.append(Jeton(texte: m, apres: i == morceaux.count - 1 ? j.apres : "")) }
        }
        return (debut, eclates)
    }

    // MARK: classes de jetons

    private enum Classe: Equatable {
        case separateur(String)     // « point », « tiret », « underscore »
        case unique(String)         // une lettre ou un chiffre épelé
        case mot(String)            // un mot entier (lettres, chiffres, . _ + -)
        case arobase
        case autre
    }

    /// Le jeton sans ponctuation de phrase autour.
    private static func depouille(_ j: Jeton) -> String {
        var s = Substring(j.texte)
        while let c = s.first, ponctuationDebut.contains(c) { s = s.dropFirst() }
        while let c = s.last, ponctuationFin.contains(c) { s = s.dropLast() }
        return String(s)
    }

    /// ... en minuscules et sans accents.
    private static func nu(_ j: Jeton) -> String {
        depouille(j).lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "fr_FR"))
    }

    private static let chiffresEnLettres: [String: String] = ["zero": "0", "deux": "2", "trois": "3", "quatre": "4", "cinq": "5", "six": "6", "sept": "7", "huit": "8", "neuf": "9"]

    private static func classe(_ jetons: [Jeton], _ i: Int) -> Classe {
        let s = nu(jetons[i])
        switch s {
        case "@", "arobase", "arrobase", "arobas", "arrobas": return .arobase
        case "point", ".": return .separateur(".")
        case "tiret", "-": return .separateur("-")
        case "underscore", "souligne", "soulignement", "_": return .separateur("_")
        default: break
        }
        if let c = chiffresEnLettres[s] { return .unique(c) }
        // une lettre isolée accentuée (« à », « é ») est un mot de la phrase, pas une lettre épelée
        if s.count == 1, let c = s.first, c.isASCII, c.isLetter || c.isNumber, depouille(jetons[i]).allSatisfy({ $0.isASCII }) { return .unique(s) }
        if s.count >= 2, s.range(of: "^[a-z0-9][a-z0-9._+-]*$", options: .regularExpression) != nil { return .mot(s) }
        return .autre
    }

    private static func estTiretDuBas(_ jetons: [Jeton], finissantA i: Int) -> Bool {
        i >= 2 && nu(jetons[i]) == "bas" && nu(jetons[i - 1]) == "du" && nu(jetons[i - 2]) == "tiret"
    }
    private static func estTiretDuBas(_ jetons: [Jeton], commencantA i: Int) -> Bool {
        i + 2 < jetons.count && nu(jetons[i]) == "tiret" && nu(jetons[i + 1]) == "du" && nu(jetons[i + 2]) == "bas"
    }

    // MARK: construction

    /// Le domaine qui commence au jeton `k` : « gmail point com » → ("gmail.com", jeton suivant). Il doit finir par une extension connue.
    private static func lireDomaine(_ jetons: [Jeton], depuis k: Int) -> (domaine: String, fin: Int)? {
        var k = k
        var morceaux: [(texte: String, fin: Int)] = []
        func lireElement(_ k: inout Int) -> String? {
            guard k < jetons.count else { return nil }
            switch classe(jetons, k) {
            case .mot(let m): k += 1; return m
            case .unique:
                var lettres = ""
                while k < jetons.count, case .unique(let u) = classe(jetons, k) { lettres += u; k += 1 }
                return lettres
            default: return nil
            }
        }
        func lireEtiquette(_ k: inout Int) -> String? {
            guard var e = lireElement(&k) else { return nil }
            // « mon tiret site » : un trait d'union reste dans l'étiquette
            while k + 1 < jetons.count, classe(jetons, k) == .separateur("-") {
                var k2 = k + 1
                guard let suite = lireElement(&k2) else { break }
                e += "-" + suite; k = k2
            }
            return e
        }
        guard let premier = lireEtiquette(&k) else { return nil }
        morceaux.append((premier, k))
        while k + 1 < jetons.count, classe(jetons, k) == .separateur(".") {
            var k2 = k + 1
            guard let e = lireEtiquette(&k2) else { break }
            morceaux.append((e, k2)); k = k2
        }
        // Le domaine finit à la dernière extension connue (« … point fr point merci » : « merci » n'en fait pas partie).
        while let dernier = morceaux.last {
            let tout = morceaux.map(\.texte).joined(separator: ".")
            let pieces = tout.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            if pieces.count >= 2, pieces.allSatisfy({ !$0.isEmpty }), let ext = pieces.last, extensions.contains(ext) { return (tout, dernier.fin) }
            morceaux.removeLast()
        }
        return nil
    }

    /// L'adresse dont l'arobase est au jeton `a` : (premier jeton, jeton suivant la fin, adresse).
    private static func construireMail(_ jetons: [Jeton], arobase a: Int) -> (debut: Int, fin: Int, adresse: String)? {
        // avant l'arobase, en remontant
        var elements: [String] = []
        var dernierEstSeparateur = false
        var j = a - 1
        var debut = a
        loop: while j >= 0 {
            if estTiretDuBas(jetons, finissantA: j) {
                if elements.isEmpty || dernierEstSeparateur { break loop }
                elements.append("_"); dernierEstSeparateur = true; j -= 3; debut = j + 1; continue
            }
            switch classe(jetons, j) {
            case .separateur(let s):
                if elements.isEmpty || dernierEstSeparateur { break loop }
                elements.append(s); dernierEstSeparateur = true; j -= 1; debut = j + 1
            case .unique(let u):
                elements.append(u); dernierEstSeparateur = false; j -= 1; debut = j + 1
            case .mot(let m):
                // un mot entier seulement juste avant l'arobase ou après un séparateur : « écris à jean » ne mange pas « à »
                guard elements.isEmpty || dernierEstSeparateur else { break loop }
                elements.append(m); dernierEstSeparateur = false; j -= 1; debut = j + 1
            default: break loop
            }
        }
        // un séparateur en tête n'appartient pas à l'adresse (« …, point jean arobase ») : on le rend au texte
        while dernierEstSeparateur, !elements.isEmpty {
            let retire = elements.removeLast()
            debut += (retire == "_" && debut + 2 < a && estTiretDuBas(jetons, commencantA: debut)) ? 3 : 1
            dernierEstSeparateur = false
        }
        guard !elements.isEmpty, elements.contains(where: { $0.contains(where: { $0.isLetter || $0.isNumber }) }) else { return nil }
        let local = elements.reversed().joined()
        guard let (domaine, fin) = lireDomaine(jetons, depuis: a + 1) else { return nil }
        return (debut, fin, local + "@" + domaine)
    }

    /// « www point sillonia point fr » (ou « w w w point … »).
    private static func construireWeb(_ jetons: [Jeton], depuis i: Int) -> (fin: Int, adresse: String)? {
        var k = i
        if nu(jetons[k]) == "www" { k += 1 }
        else if k + 2 < jetons.count, (0..<3).allSatisfy({ nu(jetons[k + $0]) == "w" }) { k += 3 }
        else { return nil }
        guard k + 1 < jetons.count, classe(jetons, k) == .separateur(".") else { return nil }
        guard let (domaine, fin) = lireDomaine(jetons, depuis: k + 1) else { return nil }
        return (fin, "www." + domaine)
    }

    /// Entoure l'adresse de la ponctuation de phrase qui était collée au premier et au dernier jeton.
    private static func habiller(_ adresse: String, premier: Jeton, dernier: Jeton) -> String {
        var avant = "", apres = ""
        for c in premier.texte { if ponctuationDebut.contains(c) { avant.append(c) } else { break } }
        for c in dernier.texte.reversed() { if ponctuationFin.contains(c) { apres = String(c) + apres } else { break } }
        return avant + adresse + apres
    }

    // MARK: entrée

    public static func reconstituer(_ texte: String) -> String {
        let lower = texte.lowercased()
        guard lower.contains("arobas") || lower.contains("arrobas") || lower.contains("@") || lower.contains("www") || lower.contains("w w w") else { return texte }
        let decoupe = decouper(texte)
        var jetons = decoupe.jetons
        var changement = false
        var i = 0
        while i < jetons.count {
            if classe(jetons, i) == .arobase, let m = construireMail(jetons, arobase: i) {
                let remplacement = Jeton(texte: habiller(m.adresse, premier: jetons[m.debut], dernier: jetons[m.fin - 1]), apres: jetons[m.fin - 1].apres)
                jetons.replaceSubrange(m.debut..<m.fin, with: [remplacement])
                changement = true
                i = m.debut + 1
            } else if let w = construireWeb(jetons, depuis: i) {
                let remplacement = Jeton(texte: habiller(w.adresse, premier: jetons[i], dernier: jetons[w.fin - 1]), apres: jetons[w.fin - 1].apres)
                jetons.replaceSubrange(i..<w.fin, with: [remplacement])
                changement = true
                i += 1
            } else {
                i += 1
            }
        }
        guard changement else { return texte }
        return decoupe.debut + jetons.map { $0.texte + $0.apres }.joined()
    }
}
