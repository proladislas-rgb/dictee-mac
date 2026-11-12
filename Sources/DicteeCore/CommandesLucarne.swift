import Foundation

// « Voxile, … » : une dictée qui COMMENCE par le nom de l'app est une commande, îlot ouvert ou fermé, dans n'importe quelle app, et n'est
// jamais collée (validé par Hugues le 11/11 ; le mot d'appel est le nom de l'app, Voxile, et lui seul depuis le 12/11 au soir : « Lucarne »
// et « Verbe » en tête sont un texte normal). Sans le nom en tête, rien ne change : une phrase d'un mail ne devient jamais une commande.
// Tout ici est pur (aucune interface, aucun réseau) : la phrase est lue sur le Mac, rien n'en part.

/// Ce qu'une dictée adressée à l'app demande.
public enum ResultatLucarne: Equatable, Sendable {
    /// La dictée ne commence pas par « Voxile » : une dictée normale.
    case aucune
    case commande(CommandeIlot)
    /// Adressée à l'app, mais rien de reconnu : « Je n'ai pas compris » et la phrase (rien n'est collé).
    case incomprise(phrase: String)
    /// Un rappel sans heure ni jour : « Il me manque l'heure » et la phrase (rien n'est collé).
    case sansHeure(phrase: String)
    /// Un rappel pour un moment déjà passé (« aujourd'hui à 9 h » dit à 14 h) : « Cette heure est passée » et la phrase. Il n'est pas
    /// ajouté (il sonnerait aussitôt, et arriverait en retard dans l'app Rappels).
    case passe(phrase: String)
    /// « Voxile, note : … » : une note (VoixIlot.swift), son texte remis au propre.
    case note(texte: String)
}

/// Le mot d'appel : « Voxile », le nom de l'app (décision de Hugues, 12/11 au soir), et ce que la transcription en fait.
public enum MotAppel {
    public static let mot = "Voxile"
    /// Sa clé phonétique (« voksil ») : « Voxil », « Voxyle », « Vauxile », « Vox île », « Vocsil » s'écrivent autrement mais
    /// se disent pareil.
    static let cle = ClePhonetique.cle(mot)

    /// Comment le mot en tête ressemble au mot d'appel.
    enum Proximite: Equatable {
        /// Il se dit comme « Voxile » (même clé phonétique).
        case meme
        /// Une lettre de la clé d'écart (« Boxile », « Voxel », « Fox île ») : une transcription ratée, PEUT-ÊTRE. On ne la prend que
        /// pour une commande complète (`AnalyseCommandeIlot.lucarne`), sinon la phrase est collée comme avant.
        case proche
    }

    /// Les mots donnés à Whisper (son `prompt`) : le mot d'appel en premier pour le PREMIER morceau d'une dictée (texte précédent vide),
    /// le seul où une commande peut commencer ; sans lui, Whisper écrit ce qu'il connaît (« Lucas » pour « Lucarne », 12/11 au soir).
    public static func motsDuPrompt(_ mots: [String], texteDavant: String?) -> [String] {
        let premier = (texteDavant ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard premier, !mots.contains(where: { ClePhonetique.plier($0) == ClePhonetique.plier(mot) }) else { return mots }
        return [mot] + mots
    }

    /// La proximité d'un mot (ou de deux mots dits d'un trait, « Vox île ») au mot d'appel ; nil s'il n'y ressemble pas. Bornée : une
    /// seule lettre d'écart sur une clé de six, et jamais un mot de moins de quatre lettres (« vox », « box » seuls ne sont pas lui).
    static func proximite(_ mot: String) -> Proximite? {
        guard ClePhonetique.plier(mot).count >= 4 else { return nil }
        let c = ClePhonetique.cle(mot)
        if c == cle { return .meme }
        return ClePhonetique.distance(c, cle, plafond: 1) <= 1 ? .proche : nil
    }
}

extension AnalyseCommandeIlot {
    /// En tête : des guillemets éventuels, un mot, puis peut-être un second mot collé par un espace seul (« Vox île »), et ce qui suit
    /// (`sep` : la ponctuation de Whisper dit si on s'adresse à l'app ou si on parle d'elle).
    private static let tete = try! NSRegularExpression(
        pattern: "^\\s*[«\"]?\\s*(?<un>[\\p{L}][\\p{L}'-]*)(?:(?<espace> )(?<deux>[\\p{L}][\\p{L}'-]*))?",
        options: [])
    private static let separateurs = CharacterSet(charactersIn: " ,.;:!?…»\"-")

    /// Le reste de la phrase après « Voxile, », ou nil si elle ne commence pas par le mot d'appel.
    public static func sansAppel(_ texte: String) -> String? { appelDetaille(texte)?.reste }

    /// Le reste ; `interpelle` : le mot d'appel est suivi d'une ponctuation (« Voxile, … », « Voxile. … ») ou est seul. Sans ponctuation
    /// (« Voxile est prête… », « Voxile 0.4 publiée ce soir »), la phrase PARLE de l'app : elle n'est pour elle que si elle demande
    /// quelque chose en toutes lettres (« Voxile rappelle-moi… », « Voxile minuteur… »). `proche` : le mot en tête n'est qu'une
    /// déformation possible (« Boxile », `MotAppel.Proximite.proche`).
    public static func appelDetaille(_ texte: String) -> (reste: String, interpelle: Bool, proche: Bool)? {
        let t = TexteDicte.unifier(texte)
        let ns = t as NSString
        guard let m = tete.firstMatch(in: t, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let un = ns.substring(with: m.range(withName: "un"))
        // un mot seul d'abord (« Voxile », « Voxil »), puis les deux premiers d'un trait (« Vox île », « Vox il »)
        var fin = m.range(withName: "un").upperBound
        var proximite = MotAppel.proximite(un)
        if proximite != .meme, m.range(withName: "deux").location != NSNotFound {
            let deux = ns.substring(with: m.range(withName: "deux"))
            if let p = MotAppel.proximite(un + deux), proximite == nil || p == .meme { proximite = p; fin = m.range(withName: "deux").upperBound }
        }
        guard let proximite else { return nil }
        // jamais collé à la suite d'un mot (« Voxile-moi » n'existe pas) : un séparateur ou la fin de la phrase
        let apres = ns.substring(from: fin)
        if let c = apres.unicodeScalars.first, !separateurs.contains(c) { return nil }
        let sep = String(String.UnicodeScalarView(apres.unicodeScalars.prefix { separateurs.contains($0) }))
        let reste = String(apres.dropFirst(sep.count)).trimmingCharacters(in: .whitespaces)
        return (reste, reste.isEmpty || sep.contains { ",.;:!?…".contains($0) }, proximite == .proche)
    }

    /// « Voxile, rappelle-moi d'appeler Ladislas demain à 15 h », « Voxile minuteur de 10 minutes », « Voxile, j'ai une livraison
    /// demain vers 13-14 h » : la commande, ou `.incomprise`/`.sansHeure` (la phrase n'est jamais collée), ou `.aucune` (pas pour l'app).
    /// Un mot en tête seulement proche du mot d'appel (« Boxile, … ») ne compte que pour une commande complète (un rappel avec son heure,
    /// une note, un minuteur, un réveil) : le reste est collé comme avant, rien n'est avalé par erreur.
    public static func lucarne(_ texte: String, maintenant: Date, calendrier: Calendar = .current) -> ResultatLucarne {
        guard let appel = appelDetaille(texte) else { return .aucune }
        let r = commande(appel: appel, phrase: TexteDicte.propre(texte), maintenant: maintenant, calendrier: calendrier)
        guard appel.proche else { return r }
        switch r {
        case .commande, .note: return r
        case .aucune, .incomprise, .sansHeure, .passe: return .aucune
        }
    }

    /// `phrase` : la phrase entière (rien n'est collé : « Copier » doit la rendre telle quelle, jamais coupée).
    private static func commande(appel: (reste: String, interpelle: Bool, proche: Bool), phrase: String, maintenant: Date, calendrier: Calendar) -> ResultatLucarne {
        let reste = TexteDicte.sansPolitesse(appel.reste)
        guard !reste.isEmpty else { return .incomprise(phrase: phrase) }
        if let s = minuteur(reste) { return .commande(.minuteur(secondes: s)) }
        // « crée-moi un rappel… », « rappelle-moi de… », « n'oublie pas que… » : ce qui suit est le rappel
        let declencheur = TexteRappel.sansDeclencheur(reste)
        // « Voxile, note : … » : une note (« note un rappel » est un rappel, vu juste avant)
        if declencheur == nil, TexteNote.demandee(reste, interpelle: appel.interpelle), let n = TexteNote.sansDeclencheur(reste) { let t = TexteNote.propre(n); return t.isEmpty ? .incomprise(phrase: phrase) : .note(texte: t) }
        let demande = declencheur != nil || TexteRappel.estUnReveil(reste)
        // « Voxile est prête, je te l'envoie demain » (sans virgule, sans demande) : une phrase sur l'app, collée comme les autres
        guard appel.interpelle || demande || TexteRappel.commenceParUneTete(reste) else { return .aucune }
        if let r = MomentDicte.extraire(declencheur ?? reste, maintenant: maintenant, calendrier: calendrier) {
            // sans « rappelle-moi » : il faut une tête de rappel (« j'ai… », « il faut que… ») ou une tâche (« appeler Paul… ») ; un nom et
            // une date (« Voxile : sortie demain », une ligne de liste) ne suffisent pas
            guard demande || TexteRappel.commenceParUneTete(r.reste) || TexteRappel.commenceParUnVerbe(r.reste) else { return .incomprise(phrase: phrase) }
            guard r.quand > maintenant else { return .passe(phrase: phrase) }
            return .commande(.rappel(texte: TexteRappel.propre(r.reste), quand: r.quand))
        }
        // un rappel demandé sans dire quand : on ne devine pas, on le dit
        if demande { return .sansHeure(phrase: phrase) }
        return .incomprise(phrase: phrase)
    }

    /// Une note qui ressemble à un rappel (« j'ai demain une livraison vers 13-14 h ») : le texte du rappel (« Livraison ») et son heure
    /// (demain 13:00), pour proposer « En faire un rappel · demain 13:00 » sous la note. nil sans jour ni heure.
    public static func rappelDansUneNote(_ texte: String, maintenant: Date, calendrier: Calendar = .current) -> (texte: String, quand: Date)? {
        let t = TexteDicte.sansPolitesse(TexteDicte.unifier(texte))
        let corps = TexteRappel.sansDeclencheur(t) ?? t
        guard let r = MomentDicte.extraire(corps, maintenant: maintenant, calendrier: calendrier), r.quand > maintenant else { return nil }
        return (TexteRappel.propre(r.reste), r.quand)
    }
}

// MARK: - Le texte dicté

enum TexteDicte {
    /// Apostrophes droites, espaces insécables en espaces simples, espaces doublés réduits.
    static func unifier(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "\u{2019}", with: "'").replacingOccurrences(of: "\u{00A0}", with: " ").replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\t", with: " ")
        while t.contains("  ") { t = t.replacingOccurrences(of: "  ", with: " ") }
        return t.trimmingCharacters(in: .whitespaces)
    }
    /// La phrase gardée sous « Je n'ai pas compris » : telle que dite, sans espaces en trop, ENTIÈRE (« Copier » la rend ; seul
    /// l'affichage la coupe).
    static func propre(_ s: String) -> String { unifier(s) }
    private static let politesse = try! NSRegularExpression(
        pattern: "[\\s,]*(?<![\\p{L}])(?:s'il te pla[iî]t|s'il vous pla[iî]t|stp|svp|please)(?![\\p{L}])[\\s.!?,]*", options: [.caseInsensitive])
    /// « merci » seulement tout au bout (« dire merci à Paul » garde son merci).
    private static let merciFinal = try! NSRegularExpression(pattern: "[\\s,]*(?<![\\p{L}])merci(?:\\s+beaucoup)?[\\s.!?]*$", options: [.caseInsensitive])
    /// Sans « s'il te plaît » (où qu'il soit) ni « merci » final.
    static func sansPolitesse(_ s: String) -> String {
        var t = politesse.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: " ")
        t = merciFinal.stringByReplacingMatches(in: t, range: NSRange(location: 0, length: (t as NSString).length), withTemplate: "")
        return unifier(t).trimmingCharacters(in: CharacterSet(charactersIn: " ,;:"))
    }
}

// MARK: - Le texte du rappel

/// Le texte d'un rappel, remis au propre : « Appeler Ladislas » (pas « Appelez Ladislas »), « Livraison » (pas « j'ai une livraison »).
public enum TexteRappel {
    /// Ce qui annonce un rappel, en tête du reste de la phrase. L'ordre compte : les plus longs d'abord.
    static let declencheurs: [String] = [
        "crée-moi un rappel", "crée moi un rappel", "créé-moi un rappel", "créer moi un rappel", "créez-moi un rappel", "crée un rappel", "créer un rappel",
        "créé un rappel", "fais-moi un rappel", "fais moi un rappel", "mets-moi un rappel", "mets moi un rappel", "met-moi un rappel", "mets un rappel",
        "met un rappel", "ajoute-moi un rappel", "ajoute moi un rappel", "ajoute un rappel", "ajouter un rappel", "programme un rappel", "note un rappel",
        "un rappel", "rappel", "rappelle-moi", "rappelle moi", "rappelez-moi", "rappelez moi", "rappelles-moi", "fais-moi penser", "fais moi penser",
        "n'oublie pas", "noublie pas", "n'oubliez pas", "souviens-toi", "pense à me rappeler", "il faut me rappeler",
    ]
    /// « réveille-moi… » : une demande (un rappel « Réveil » ; l'heure n'est jamais l'après-midi sans le dire).
    static func estUnReveil(_ s: String) -> Bool {
        let bas = s.lowercased()
        return ["réveille-moi", "réveille moi", "réveillez-moi", "reveille-moi", "reveille moi"].contains { bas.hasPrefix($0) }
    }

    /// Ce qui, en tête, dit qu'on parle de soi et de ce qu'on a à faire (« j'ai une livraison », « il faut que j'appelle ») : assez pour
    /// qu'une phrase qui commence par « Voxile » lui soit adressée, même sans virgule. Jamais « c'est », « il y a » (on peut le dire
    /// de l'app).
    private static let tetesDeRappel = ["j'ai ", "j'aurai ", "je vais avoir ", "je dois ", "il faut ", "il faudrait ", "faut que ", "n'oublie ",
                                        "on a ", "nous avons ", "j'ai besoin "]
    static func commenceParUneTete(_ s: String) -> Bool {
        let bas = TexteDicte.unifier(s).lowercased()
        return tetesDeRappel.contains { bas.hasPrefix($0) }
    }
    /// Une tâche : le premier mot est un verbe connu (« appeler Paul », « appelle Paul ») ou un infinitif en « -er » (« tester »).
    static func commenceParUnVerbe(_ s: String) -> Bool {
        let t = TexteDicte.unifier(s).trimmingCharacters(in: CharacterSet(charactersIn: " ,;:.!?"))
        let premier = String(t.prefix { $0.isLetter }).lowercased()
        guard premier.count >= 3 else { return false }
        if infinitifs[premier] != nil || verbesConnus.contains(premier) { return true }
        return premier.count >= 4 && (premier.hasSuffix("er") || premier.hasSuffix("ez"))
    }
    private static let verbesConnus: Set<String> = Set(infinitifs.values)

    /// Le reste après « crée-moi un rappel pour », « rappelle-moi de », « n'oublie pas que »… ; nil s'il n'y a pas de déclencheur.
    static func sansDeclencheur(_ s: String) -> String? {
        let bas = s.lowercased()
        for d in declencheurs where bas.hasPrefix(d) {
            let suite = bas.dropFirst(d.count)
            // « rappel » doit être un mot entier (pas « rappeler », « rappelons »)
            if let c = suite.first, c.isLetter || c == "-" { continue }
            var reste = String(s.dropFirst(d.count)).trimmingCharacters(in: CharacterSet(charactersIn: " ,:;.!?"))
            for lien in ["pour ", "de ", "d'", "que ", "qu'", "à ", "a "] where reste.lowercased().hasPrefix(lien) {
                // « pour demain », « à 15 h » : le lien appartient à l'heure, il reste
                let apres = reste.dropFirst(lien.count).lowercased()
                if lien == "pour " || lien == "à " || lien == "a ", MomentDicte.commenceParUnMoment(String(apres)) { break }
                reste = String(reste.dropFirst(lien.count)); break
            }
            return reste
        }
        return nil
    }

    /// Ce qui ne dit rien en tête du rappel (« il faut que je », « j'ai une »…). Les plus longs d'abord ; `article` : un article qui suit
    /// sera retiré aussi (« j'ai une livraison » → « livraison »).
    private static let tetes: [(String, article: Bool)] = [
        ("n'oublie pas que j'ai ", true), ("n'oublie pas que ", false), ("n'oublie pas de ", false), ("n'oublie pas d'", false), ("n'oublie pas ", true),
        ("il faut que je ", false), ("il faut que j'", false), ("il faudrait que je ", false), ("il faudrait que j'", false), ("faut que je ", false),
        ("faut que j'", false), ("qu'il faut que je ", false), ("qu'il faut ", false), ("il faut ", false), ("que je dois ", false), ("je dois ", false),
        ("j'ai besoin de ", false), ("j'ai besoin d'", false), ("j'ai à ", false), ("je vais avoir ", true), ("j'aurai ", true), ("j'ai ", true),
        ("on a ", true), ("nous avons ", true), ("il y a ", true), ("y a ", true), ("c'est ", true), ("penser à ", false), ("pense à ", false),
        ("que j'ai ", true), ("que ", false), ("qu'", false), ("de ", false), ("d'", false), ("pour ", false), ("à ", false), ("je ", false), ("j'", false),
    ]
    private static let articles = ["une ", "un ", "la ", "le ", "l'", "les ", "des ", "du ", "mon ", "ma ", "mes "]

    /// Les verbes d'un rappel, conjugués comme on les dicte (« appelle Paul », « appelez Paul », « j'appelle Paul »), vers l'infinitif.
    static let infinitifs: [String: String] = {
        var d: [String: String] = [:]
        let formes: [(String, [String])] = [
            ("appeler", ["appelle", "appelles", "appelez", "appelons"]), ("rappeler", ["rappelle", "rappelles", "rappelez"]),
            ("acheter", ["achète", "achete", "achètes", "achetez"]), ("envoyer", ["envoie", "envoies", "envoyez"]),
            ("prendre", ["prends", "prenez"]), ("reprendre", ["reprends", "reprenez"]), ("faire", ["fais", "faites"]),
            ("aller", ["va", "vas", "vais", "allez"]), ("passer", ["passe", "passes", "passez"]), ("réserver", ["réserve", "reserve", "réservez"]),
            ("payer", ["paie", "paye", "payez"]), ("sortir", ["sors", "sortez"]), ("mettre", ["mets", "mettez"]),
            ("écrire", ["écris", "ecris", "écrivez"]), ("répondre", ["réponds", "repond", "répondez"]), ("vérifier", ["vérifie", "verifie", "vérifiez"]),
            ("préparer", ["prépare", "prepare", "préparez"]), ("récupérer", ["récupère", "recupere", "récupérez"]), ("relancer", ["relance", "relancez"]),
            ("contacter", ["contacte", "contactez"]), ("confirmer", ["confirme", "confirmez"]), ("télécharger", ["télécharge", "téléchargez"]),
            ("imprimer", ["imprime", "imprimez"]), ("ranger", ["rangez"]), ("nettoyer", ["nettoie", "nettoyez"]), ("lire", ["lis", "lisez"]),
            ("dire", ["dis", "dites"]), ("finir", ["finis", "finissez"]), ("rendre", ["rends"]), ("donner", ["donne", "donnez"]),
            ("demander", ["demande", "demandez"]), ("regarder", ["regarde", "regardez"]), ("écouter", ["écoute", "écoutez"]), ("manger", ["mange", "mangez"]),
            ("boire", ["bois", "buvez"]), ("arroser", ["arrose", "arrosez"]), ("fermer", ["fermez"]), ("ouvrir", ["ouvre", "ouvrez"]),
            ("commander", ["commandez"]), ("annuler", ["annule", "annulez"]), ("signer", ["signez"]), ("déposer", ["dépose", "déposez"]),
            ("chercher", ["cherche", "cherchez"]), ("amener", ["amène", "amenez"]), ("ramener", ["ramène", "ramenez"]), ("apporter", ["apporte", "apportez"]),
            ("partir", ["pars", "partez"]), ("venir", ["viens", "venez"]), ("voir", ["vois", "voyez"]), ("noter", ["notez"]),
            ("valider", ["valide", "validez"]), ("relire", ["relis", "relisez"]), ("souhaiter", ["souhaite", "souhaitez"]),
            ("décaler", ["décale", "décalez"]), ("prévenir", ["préviens", "prévenez"]), ("joindre", ["joins", "joignez"]),
            ("transférer", ["transfère", "transférez"]), ("facturer", ["facturez"]), ("recharger", ["rechargez"]), ("laver", ["lavez"]), ("emmener", ["emmène", "emmenez"]), ("déplacer", ["déplace", "déplacez"]), ("éteindre", ["éteins", "éteignez"]),
        ]
        for (inf, fs) in formes { for f in fs { d[f] = inf } }
        return d
    }()
    /// Des mots en « -ez » qui ne sont pas des verbes : jamais changés en « -er ».
    private static let pasDesVerbes: Set<String> = ["chez", "assez", "nez", "rez", "lez"]

    /// Le premier mot à l'infinitif s'il est un verbe conjugué connu (ou un « -ez » de politesse : « Appelez » → « Appeler »).
    static func infinitif(_ mot: String) -> String? {
        let bas = mot.lowercased()
        if let i = infinitifs[bas] { return i }
        if bas.count >= 5, bas.hasSuffix("ez"), !pasDesVerbes.contains(bas), bas.allSatisfy({ $0.isLetter }) { return String(bas.dropLast(2)) + "er" }
        return nil
    }

    /// Le texte du rappel tel qu'on l'écrirait : sans « que », « j'ai une », « s'il te plaît », le verbe à l'infinitif, une majuscule.
    public static func propre(_ brut: String) -> String {
        var t = TexteDicte.sansPolitesse(TexteDicte.unifier(brut))
        t = nettoyerBords(t)
        // les têtes vides (« il faut que je », « j'ai une ») tombent, autant qu'il y en a
        var change = true
        while change {
            change = false
            for (tete, article) in tetes where t.lowercased().hasPrefix(tete) && t.count > tete.count {
                t = String(t.dropFirst(tete.count))
                if article { for a in articles where t.lowercased().hasPrefix(a) && t.count > a.count { t = String(t.dropFirst(a.count)); break } }
                t = nettoyerBords(t)
                change = true
                break
            }
        }
        // le verbe : « appelez Ladislas » → « appeler Ladislas » ; suivi de « de » c'est un nom (« Demande de devis », « Passe de ski » ;
        // « du », « des » sont des articles : « achète du pain »),
        // sauf la forme en « -ez », toujours un verbe
        let espace = t.firstIndex(of: " ") ?? t.endIndex
        let premier = String(t[..<espace])
        let second = t[espace...].trimmingCharacters(in: .whitespaces).lowercased()
        let complement = ["de ", "d'"].contains { second.hasPrefix($0) }
        if let inf = infinitif(premier), !complement || premier.lowercased().hasSuffix("ez") { t = inf + t[espace...] }
        t = nettoyerBords(t)
        // « réveille-moi à 7 h » : il n'y a pas (encore) de réveil sur main, c'est un rappel « Réveil »
        if ["réveille-moi", "réveille moi", "réveillez-moi", "reveille-moi", "reveille moi"].contains(t.lowercased()) { t = "Réveil" }
        guard !t.isEmpty else { return "Rappel" }
        if t.count > 120 { t = String(t.prefix(119)) + "\u{2026}" }
        return t.prefix(1).uppercased() + t.dropFirst()
    }

    /// Sans ponctuation ni petits mots orphelins aux bords (« Livraison vers », « appeler Paul , »).
    static func nettoyerBords(_ s: String) -> String {
        var t = s
        // une virgule ou un point laissés par une heure retirée au milieu (« appeler Paul , ce soir ») ; les espaces avant la ponctuation
        for (a, b) in [(" ,", ","), (" .", "."), (",,", ","), (", ,", ","), ("( )", ""), ("()", "")] { while t.contains(a) { t = t.replacingOccurrences(of: a, with: b) } }
        while t.contains("  ") { t = t.replacingOccurrences(of: "  ", with: " ") }
        let ponctuation = CharacterSet(charactersIn: " ,;:.!?…-–—\"«»()")
        let orphelins = ["à", "a", "vers", "pour", "de", "d'", "le", "la", "les", "entre", "et", "dès", "des", "avant", "ce", "cet", "cette", "au", "aux", "du",
                         "prochain", "prochaine", "sur", "en", "par", "dans", "ou", "alors", "donc", "bon", "euh", "hein"]
        var avant = ""
        while avant != t {
            avant = t
            t = t.trimmingCharacters(in: ponctuation)
            let bas = t.lowercased()
            for o in orphelins {
                if bas.hasSuffix(" " + o) { t = String(t.dropLast(o.count + 1)); break }
                if bas == o { t = ""; break }
            }
            for o in ["euh ", "bon ", "alors ", "donc ", "et "] where t.lowercased().hasPrefix(o) { t = String(t.dropFirst(o.count)); break }
        }
        return t
    }
}

// MARK: - Le jour et l'heure dits

/// Le jour et l'heure trouvés n'importe où dans une phrase dictée (« j'ai demain une livraison vers 13-14 h »), et la phrase sans eux.
public enum MomentDicte {
    /// Une heure en chiffres ou en lettres (les plus longs d'abord : « dix-sept » avant « dix »).
    static let motsHeures: [String: Int] = [
        "une": 1, "un": 1, "deux": 2, "trois": 3, "quatre": 4, "cinq": 5, "six": 6, "sept": 7, "huit": 8, "neuf": 9, "dix": 10, "onze": 11, "douze": 12,
        "treize": 13, "quatorze": 14, "quinze": 15, "seize": 16, "dix-sept": 17, "dix sept": 17, "dix-huit": 18, "dix huit": 18, "dix-neuf": 19,
        "dix neuf": 19, "vingt": 20, "vingt et une": 21, "vingt-et-une": 21, "vingt-deux": 22, "vingt deux": 22, "vingt-trois": 23, "vingt trois": 23,
    ]
    private static var nb: String {
        let mots = motsHeures.keys.sorted { $0.count > $1.count }.map { NSRegularExpression.escapedPattern(for: $0) }
        return "(?:\\d{1,2}|" + mots.joined(separator: "|") + ")"
    }
    /// « h » ou « heure(s) » (jamais le début d'un mot : « 13 hommes »), ou « : » (« 13:30 »).
    private static let unite = "(?:h(?![\\p{L}])|heures?(?![\\p{L}]))"
    private static let prep = "(?:(?<prep>vers|à|a|pour|dès|avant|après|apres|autour de|aux alentours de|sur les coups de|entre|de)\\s+)?"
    private static let fraction = "(?:\\s+(?<frac>et\\s+demie?|et\\s+quart|moins\\s+le\\s+quart))?"
    private static let periode = "(?:\\s+(?<per>du\\s+matin|de\\s+l'apr[eè]s-midi|de\\s+l'apr[eè]s\\s+midi|de\\s+l'aprem|du\\s+soir))?"
    private static let periodeJour = "(?:\\s+(?<pj>matin|midi|soir|apr[eè]s-midi|apr[eè]s\\s+midi|aprem))?"

    private static func re(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p, options: [.caseInsensitive]) }

    /// « dans 20 minutes », « dans une heure », « dans 1 h 30 », « dans une demi-heure ».
    private static let relatif = re("\\bdans\\s+(?:(?<demi>une\\s+demi-heure|une\\s+demie?\\s+heure)|(?<quart>un\\s+quart\\s+d'heure)|(?<tq>trois\\s+quarts\\s+d'heure)|(?<n>\\d{1,3}|" +
                                    (AnalyseCommandeIlot.motsNombres.keys.sorted { $0.count > $1.count }.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")) +
                                    ")\\s*(?<u>minutes?|min|mn|heures?|h)(?![\\p{L}])(?:\\s*(?:et\\s+)?(?<suite>demie|\\d{1,2}))?)")
    /// Jamais un nombre collé à un mot, à un chiffre ou à une barre (« 13/11 » est une date, pas « 11 h »).
    private static let pasColle = "(?<![\\p{L}\\p{N}/])"
    /// « 13-14 h », « 13 h - 14 h », « entre 13 et 14 heures », « de 13 h à 14 h », « 13 14 h » (Whisper perd souvent le tiret) : la
    /// première heure compte. Ni « / » ni « , » entre les deux (« le 13/11 à 14 h », « ligne 13, 14 h ») ; deux nombres séparés d'un
    /// simple espace ne sont une plage que s'ils se suivent de près (1 à 3 h d'écart).
    private static let plage = re(pasColle + prep + "(?<h>" + nb + ")\\s*(?:(?<u1>" + unite + ")\\s*(?<m>\\d{2})?)?(?:\\s*(?:[-–]|\\s(?:à|a|ou|et)\\s)\\s*|(?<esp>\\s+))(?<h2>" + nb + ")\\s*" + unite + "(?:\\s*\\d{2})?" + periode)
    /// « à 15 h », « 15h30 », « 9 h 30 », « à 3 heures de l'après-midi », « vers 8 h du soir ».
    private static let heure = re(pasColle + prep + "(?<h>" + nb + ")\\s*" + unite + "(?:\\s*(?<m>\\d{1,2})(?![\\p{L}\\p{N}]))?" + fraction + periode)
    /// « 15:30 ».
    private static let deuxPoints = re(pasColle + prep + "(?<h>\\d{1,2}):(?<m>\\d{2})(?![\\p{N}])" + periode)
    /// « midi », « minuit », « midi et demi ».
    private static let midi = re("(?<![\\p{L}-])" + prep + "(?<mm>midi|minuit)(?:\\s+(?<frac>et\\s+demie?|et\\s+quart))?(?![\\p{L}])")
    /// « demain », « après-demain », « aujourd'hui », « ce soir », « lundi (prochain) », « le 20 novembre », avec « matin / soir ».
    private static let jour = re("(?<![\\p{L}])(?:(?:pour|d'ici|dès|à partir de|a partir de)\\s+)?(?:(?<ad>apr[eè]s[- ]demain)|(?<dem>demain)|(?<auj>aujourd'hui)|(?<ce>ce\\s+(?:soir|matin|midi)|cet\\s+apr[eè]s-midi|cet\\s+aprem|cette\\s+nuit)|(?:(?:ce|le)\\s+)?(?<js>lundi|mardi|mercredi|jeudi|vendredi|samedi|dimanche)(?:\\s+prochain)?|(?:le\\s+)?(?<dm>\\d{1,2}|1er|premier)\\s+(?<mois>janvier|février|fevrier|mars|avril|mai|juin|juillet|août|aout|septembre|octobre|novembre|décembre|decembre)|(?:le\\s+)?(?<![\\p{N}/])(?<jj>\\d{1,2})/(?<mm>\\d{1,2})(?:/(?<an>\\d{4}|\\d{2}))?(?![\\p{N}/]))" + periodeJour + "(?![\\p{L}])")

    private static let jours = ["dimanche": 1, "lundi": 2, "mardi": 3, "mercredi": 4, "jeudi": 5, "vendredi": 6, "samedi": 7]
    private static let mois = ["janvier": 1, "février": 2, "fevrier": 2, "mars": 3, "avril": 4, "mai": 5, "juin": 6, "juillet": 7, "août": 8, "aout": 8,
                               "septembre": 9, "octobre": 10, "novembre": 11, "décembre": 12, "decembre": 12]

    /// Entre minuit et 4 h, on vit encore la veille : « demain » est le jour qui commence (dit à 0 h 30, « demain 13 h » veut dire ce
    /// midi-là, pas le lendemain). L'îlot nomme alors le jour (« jeudi 12 ») au lieu de « demain », pour qu'aucun doute ne reste.
    public static func estLaNuit(_ d: Date, calendrier cal: Calendar = .current) -> Bool { cal.component(.hour, from: d) < 4 }
    /// Le premier instant du jour que « demain » désigne, dit à `maintenant`.
    public static func demain(_ maintenant: Date, calendrier cal: Calendar = .current) -> Date {
        let j = cal.startOfDay(for: maintenant)
        return estLaNuit(maintenant, calendrier: cal) ? j : (cal.date(byAdding: .day, value: 1, to: j) ?? j)
    }

    /// Le texte commence-t-il par un jour ou une heure (« demain… », « 15 h… ») ? Sert à garder « pour » devant « pour demain ».
    static func commenceParUnMoment(_ s: String) -> Bool {
        let ns = s as NSString
        for r in [jour, plage, heure, deuxPoints, midi, relatif] {
            if let m = r.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)), m.range.location == 0 { return true }
        }
        return false
    }

    private static func valeur(_ s: String) -> Int? {
        let b = s.lowercased().replacingOccurrences(of: "  ", with: " ")
        return Int(b) ?? motsHeures[b]
    }

    /// Le moment dit dans la phrase, et la phrase sans lui. nil si la phrase ne dit ni jour ni heure.
    public static func extraire(_ texte: String, maintenant: Date, calendrier cal: Calendar = .current) -> (quand: Date, reste: String)? {
        let t = TexteDicte.unifier(texte)
        let ns = t as NSString
        let tout = NSRange(location: 0, length: ns.length)
        var retires: [NSRange] = []
        func libre(_ r: NSRange) -> Bool { !retires.contains { NSIntersectionRange($0, r).length > 0 } }
        func groupe(_ m: NSTextCheckingResult, _ nom: String) -> String? {
            let r = m.range(withName: nom)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }

        // « dans 20 minutes » : l'heure exacte, rien d'autre à chercher
        if let m = relatif.firstMatch(in: t, range: tout) {
            var secondes: Double?
            if groupe(m, "demi") != nil { secondes = 1800 }
            else if groupe(m, "quart") != nil { secondes = 900 }
            else if groupe(m, "tq") != nil { secondes = 2700 }
            else if let n = groupe(m, "n"), let u = groupe(m, "u")?.lowercased() {
                let v = Double(n) ?? AnalyseCommandeIlot.motsNombres[n.lowercased()] ?? 0
                if u.hasPrefix("h") {
                    secondes = v * 3600
                    if let suite = groupe(m, "suite")?.lowercased() { secondes! += suite.hasPrefix("demi") ? 1800 : (Double(suite) ?? 0) * 60 }
                } else { secondes = v * 60 }
            }
            if let s = secondes, s >= 60, s <= 7 * 24 * 3600 {
                retires.append(m.range)
                return (maintenant.addingTimeInterval(s), reste(ns, sans: retires))
            }
        }

        // le jour
        var jourVu: Date?
        var periodeDuJour: String?
        if let m = jour.firstMatch(in: t, range: tout) {
            let debutDuJour = cal.startOfDay(for: maintenant)
            // la nuit (0 h – 4 h), « demain », « après-demain », « vendredi » se comptent depuis la veille, le jour qu'on vit encore
            let veille = estLaNuit(maintenant, calendrier: cal) ? (cal.date(byAdding: .day, value: -1, to: debutDuJour) ?? debutDuJour) : debutDuJour
            if groupe(m, "ad") != nil { jourVu = cal.date(byAdding: .day, value: 2, to: veille) }
            else if groupe(m, "dem") != nil { jourVu = cal.date(byAdding: .day, value: 1, to: veille) }
            else if groupe(m, "auj") != nil { jourVu = debutDuJour }
            else if let ce = groupe(m, "ce")?.lowercased() {
                jourVu = debutDuJour
                periodeDuJour = ce.contains("nuit") ? "nuit" : ce.contains("soir") ? "soir" : ce.contains("matin") ? "matin" : ce.contains("midi") && !ce.contains("apr") ? "midi" : "aprem"
            } else if let js = groupe(m, "js")?.lowercased(), let numero = jours[js] {
                // le prochain de ce nom, jamais aujourd'hui (« lundi », dit un lundi, c'est le suivant)
                var d = cal.date(byAdding: .day, value: 1, to: veille) ?? veille
                while cal.component(.weekday, from: d) != numero { d = cal.date(byAdding: .day, value: 1, to: d) ?? d }
                jourVu = d
            } else if let dm = groupe(m, "dm")?.lowercased(), let mo = groupe(m, "mois").flatMap({ mois[$0.lowercased()] }) {
                let jourDuMois = dm == "1er" || dm == "premier" ? 1 : (Int(dm) ?? 0)
                if (1...31).contains(jourDuMois) {
                    var c = cal.dateComponents([.year], from: maintenant); c.month = mo; c.day = jourDuMois
                    if var d = cal.date(from: c) {
                        if d < debutDuJour { d = cal.date(byAdding: .year, value: 1, to: d) ?? d }
                        jourVu = d
                    }
                }
            } else if let jj = groupe(m, "jj").flatMap({ Int($0) }), let mm = groupe(m, "mm").flatMap({ Int($0) }), (1...31).contains(jj), (1...12).contains(mm) {
                // « le 13/11 », « 13/11/2026 » : jour puis mois (l'ordre français)
                var c = cal.dateComponents([.year], from: maintenant); c.month = mm; c.day = jj
                if let an = groupe(m, "an").flatMap({ Int($0) }) { c.year = an < 100 ? 2000 + an : an }
                if var d = cal.date(from: c), cal.component(.day, from: d) == jj {
                    if groupe(m, "an") == nil, d < debutDuJour { d = cal.date(byAdding: .year, value: 1, to: d) ?? d }
                    jourVu = d
                }
            }
            if let pj = groupe(m, "pj")?.lowercased() {
                periodeDuJour = pj.hasPrefix("mat") ? "matin" : pj == "midi" ? "midi" : pj == "soir" ? "soir" : "aprem"
            }
            if jourVu != nil { retires.append(m.range) }
        }

        // l'heure (la première dite)
        var h: Int?, mn = 0
        var periodeHeure: String?
        for r in [plage, deuxPoints, heure] where h == nil {
            for m in r.matches(in: t, range: tout) where libre(m.range) {
                guard let hs = groupe(m, "h"), let v = valeur(hs), (0...23).contains(v) else { continue }
                if Int(hs) == nil, groupe(m, "prep") == nil { continue }
                // « 13 14 h » : une plage seulement si la 2e heure suit de près la 1re (sinon « ligne 13 14 h » : l'heure seule, plus loin)
                if groupe(m, "esp") != nil {
                    guard groupe(m, "u1") == nil, let h2 = groupe(m, "h2").flatMap(valeur), (1...3).contains(h2 - v) else { continue }
                }
                var minutes = groupe(m, "m").flatMap { Int($0) } ?? 0
                guard (0...59).contains(minutes) else { continue }
                if let f = groupe(m, "frac")?.lowercased() {
                    if f.contains("demi") { minutes = 30 } else if f.contains("moins") { minutes = 45 } else { minutes = 15 }
                }
                var heureDite = v
                if let f = groupe(m, "frac")?.lowercased(), f.contains("moins") { heureDite = (v + 23) % 24 }
                h = heureDite; mn = minutes
                periodeHeure = groupe(m, "per")?.lowercased()
                retires.append(m.range)
                break
            }
        }
        if h == nil, let m = midi.firstMatch(in: t, range: tout), libre(m.range) {
            h = groupe(m, "mm")?.lowercased() == "minuit" ? 0 : 12
            if let f = groupe(m, "frac")?.lowercased() { mn = f.contains("demi") ? 30 : 15 }
            retires.append(m.range)
        }

        guard jourVu != nil || h != nil else { return nil }
        // l'après-midi, le soir : « 8 h » devient 20 h ; sans rien, « à 3 h » se dit pour 15 h (personne ne se fait rappeler à 3 h du matin
        // sans le dire) ; mais 5 h, 6 h, c'est le matin (« le train de 6 h 30 »), et un réveil n'est jamais l'après-midi
        let moment = periodeHeure.map { $0.contains("matin") ? "matin" : $0.contains("soir") ? "soir" : "aprem" } ?? periodeDuJour
        let reveil = t.lowercased().contains("réveill") || t.lowercased().contains("reveill")
        var lendemain = false
        if var heure = h {
            if moment == "nuit" {
                // « cette nuit à 11 h » : 23 h ; « cette nuit à 2 h » : la nuit qui vient, donc après minuit
                if (7...11).contains(heure) { heure += 12 } else if heure < 7, !estLaNuit(maintenant, calendrier: cal) { lendemain = true }
            } else if heure < 12, moment == "soir" || moment == "aprem" { heure += 12 }
            else if (1...4).contains(heure), moment == nil, !reveil { heure += 12 }
            h = heure
        }
        let heureFinale: Int, minuteFinale: Int
        if let heure = h { heureFinale = heure; minuteFinale = mn }
        else {
            switch moment {
            case "nuit": heureFinale = 23
            case "soir": heureFinale = 19
            case "aprem": heureFinale = 14
            case "midi": heureFinale = 12
            default: heureFinale = 9
            }
            minuteFinale = 0
        }
        let base = jourVu ?? cal.startOfDay(for: maintenant)
        var c = cal.dateComponents([.year, .month, .day], from: base)
        c.hour = heureFinale; c.minute = minuteFinale; c.second = 0
        guard var quand = cal.date(from: c) else { return nil }
        // une heure seule, déjà passée aujourd'hui : demain
        if lendemain || (jourVu == nil && quand <= maintenant) { quand = cal.date(byAdding: .day, value: 1, to: quand) ?? quand }
        return (quand, reste(ns, sans: retires))
    }

    private static func reste(_ ns: NSString, sans plages: [NSRange]) -> String {
        var r = ns as String
        for p in plages.sorted(by: { $0.location > $1.location }) {
            r = (r as NSString).replacingCharacters(in: p, with: " ")
        }
        return TexteRappel.nettoyerBords(TexteDicte.unifier(r))
    }
}

extension AnalyseCommandeIlot {
    /// Les nombres en lettres d'une durée (« dans vingt minutes »).
    static let motsNombres: [String: Double] = [
        "un": 1, "une": 1, "deux": 2, "trois": 3, "quatre": 4, "cinq": 5, "six": 6, "sept": 7, "huit": 8, "neuf": 9, "dix": 10,
        "onze": 11, "douze": 12, "treize": 13, "quatorze": 14, "quinze": 15, "seize": 16, "vingt": 20, "trente": 30, "quarante": 40,
        "cinquante": 50, "soixante": 60, "quarante-cinq": 45, "vingt-cinq": 25, "quarante cinq": 45, "vingt cinq": 25,
        "dix-sept": 17, "dix-huit": 18, "dix-neuf": 19, "trente-cinq": 35, "cinquante-cinq": 55,
    ]
}

// MARK: - La note dictée au clic : fin au silence

/// La note dictée d'un clic s'arrête toute seule après un silence de 2 s, une fois que Hugues a parlé (ou après 8 s sans un mot, ou au bout
/// de 2 minutes). Le niveau vient du micro (0…1, -60 dB → 0, -15 dB → 1) ; le seuil de la voix suit le bruit de fond (+10 dB, entre -45 et
/// -35 dB, comme le découpage de la dictée), et le tout début (le petit son de départ, capté par le micro) ne compte pas.
public struct FinDeNote: Equatable, Sendable {
    public static let silence: Double = 2
    public static let sansParole: Double = 8
    public static let maximum: Double = 120
    public static let ignore: Double = 0.4
    public enum Raison: Equatable, Sendable { case silence, rienEntendu, tropLong }

    public let debut: Date
    public private(set) var fond: Float = 0.2
    public private(set) var aParle = false
    public private(set) var derniereVoix: Date?
    private var fondVu = false

    public init(debut: Date) { self.debut = debut }

    /// Le seuil de la voix (+10 dB sur le fond, entre -45 et -35 dB).
    public var seuil: Float { min(Float(25) / 45, max(Float(15) / 45, fond + Float(10) / 45)) }

    public mutating func niveau(_ n: Float, a t: Date) {
        guard t.timeIntervalSince(debut) >= Self.ignore else { return }
        if !fondVu { fond = n; fondVu = true }
        if n < fond { fond = n } else if n < seuil { fond += (n - fond) * 0.02 }
        if n >= seuil { aParle = true; derniereVoix = t }
    }

    /// Faut-il s'arrêter à `t` ? nil : on écoute encore.
    public func fin(a t: Date) -> Raison? {
        if t.timeIntervalSince(debut) >= Self.maximum { return .tropLong }
        if let v = derniereVoix { return t.timeIntervalSince(v) >= Self.silence ? .silence : nil }
        return t.timeIntervalSince(debut) >= Self.sansParole ? .rienEntendu : nil
    }
}

// MARK: - L'app Rappels d'Apple

/// Où en est l'accès à l'app Rappels (EventKit), vu par Lucarne.
public enum AccesRappelsApple: Equatable, Sendable { case nonDemande, autorise, refuse }
/// Ce que Hugues a répondu dans l'îlot à « Aussi dans l'app Rappels ? » (nil : jamais demandé).
public enum ChoixRappelsApple: String, Equatable, Sendable { case oui, non }

/// Que faire après un rappel ajouté dans Lucarne. L'autorisation se demande UNE fois, au premier rappel, depuis l'îlot ; un refus (dans
/// l'îlot ou dans la fenêtre de macOS) est dit une fois, puis plus jamais.
public enum PlanRappelsApple {
    public enum Etape: Equatable, Sendable {
        /// Le mettre aussi dans l'app Rappels.
        case creer
        /// Poser la question dans l'îlot (« Aussi dans l'app Rappels ? »).
        case demander
        /// L'accès est refusé dans Réglages Système et rien n'a encore été dit : le dire une fois (« Tes rappels restent ici »).
        case direRefus
        case rien
    }
    public static func apresAjout(choix: ChoixRappelsApple?, acces: AccesRappelsApple) -> Etape {
        switch (choix, acces) {
        case (.non?, _): return .rien
        case (_, .autorise): return .creer
        case (nil, .nonDemande), (.oui?, .nonDemande): return .demander
        case (nil, .refuse): return .direRefus
        case (.oui?, .refuse): return .rien
        }
    }
}
