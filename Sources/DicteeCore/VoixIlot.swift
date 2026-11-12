import Foundation

// La voix d'un rappel ou d'une note dans l'îlot (maquette design/maquettes/ilot-voix-rappel.html, demande de Hugues du 12/11) : pendant
// qu'on dit « Lucarne, rappelle-moi… » ou « Lucarne, note… » (fn tenue), une onde qui suit la voix et, dès que la commande est comprise,
// « Rappel… » ou « Note… » ; au relâchement, une carte qui montre ce qui a été compris (titre, jour et heure, une ligne de résumé) et
// propose de l'envoyer dans l'app Rappels ou dans l'app Notes. Tout ici est pur : aucune interface, aucun réseau, aucune horloge.

/// Ce que la voix dicte à Lucarne : un rappel (l'orange de Rappels) ou une note (le jaune de Notes).
public enum GenreVoix: String, Equatable, Sendable {
    case rappel, note
    /// Le libellé sous l'onde, dès que la commande est comprise.
    public var libelle: String { self == .rappel ? "Rappel\u{2026}" : "Note\u{2026}" }
    /// L'app d'Apple où la carte l'envoie.
    public var app: String { self == .rappel ? "Rappels" : "Notes" }
}

/// Ce que dit le texte en direct d'une dictée (la reconnaissance du Mac, pendant qu'on parle).
public enum DirectVoix: Equatable, Sendable {
    /// Pas (ou pas encore) pour Lucarne : l'encoche de la dictée reste.
    case autre
    /// Pour Lucarne : l'îlot prend la dictée (l'onde) ; le genre, dès qu'il est compris (nil : pas encore, ou un minuteur, un réveil).
    case pourLucarne(GenreVoix?)
}

extension AnalyseCommandeIlot {
    /// Le texte en direct d'une dictée fn tenue : est-elle pour Lucarne, et pour quoi ? Jugé comme la commande finale (`lucarne`) :
    /// le mot d'appel en tête, puis une virgule (on s'adresse à Lucarne) ou une demande en toutes lettres (« Lucarne rappelle-moi »).
    /// « Lucarne » seul (la suite n'est pas encore arrivée) ou « Lucarne est prête… » restent `.autre` : rien n'est pris trop tôt.
    public static func directVoix(_ texte: String, maintenant: Date, calendrier: Calendar = .current) -> DirectVoix {
        guard let appel = appelDetaille(texte) else { return .autre }
        let reste = TexteDicte.sansPolitesse(appel.reste)
        guard !reste.isEmpty else { return .autre }
        if TexteRappel.sansDeclencheur(reste) != nil { return .pourLucarne(.rappel) }
        if TexteNote.demandee(reste, interpelle: appel.interpelle) { return .pourLucarne(.note) }
        let demande = TexteRappel.estUnReveil(reste) || minuteur(reste) != nil
        guard appel.interpelle || demande || TexteRappel.commenceParUneTete(reste) else { return .autre }
        // « Lucarne, j'ai demain une livraison… » : un rappel dès que le jour ou l'heure est dit, après une tête ou une tâche
        if !demande, let r = MomentDicte.extraire(reste, maintenant: maintenant, calendrier: calendrier),
           TexteRappel.commenceParUneTete(r.reste) || TexteRappel.commenceParUnVerbe(r.reste) {
            return .pourLucarne(.rappel)
        }
        return .pourLucarne(nil)
    }
}

// MARK: - Le texte d'une note

/// « Lucarne, note : … », « Lucarne, prends une note … », « Lucarne, note que … » : ce qui suit est la note.
public enum TexteNote {
    /// Ce qui annonce une note, en tête du reste de la phrase (les plus longs d'abord). « note un rappel » est un rappel (TexteRappel le
    /// voit avant).
    static let declencheurs: [String] = [
        "prends-moi une note", "prends moi une note", "prends une note", "prend une note", "prenez une note", "prends note", "prend note",
        "crée une note", "créer une note", "crée-moi une note", "fais une note", "fais-moi une note", "ajoute une note", "écris une note",
        "nouvelle note", "une note", "note-moi", "note moi", "notez", "note",
    ]

    /// Seuls, sans virgule après le mot d'appel, ils ne suffisent pas (« Lucarne une note de 15 sur 20 », « Verbe note… » peuvent parler
    /// de Lucarne) ; les autres sont une demande en toutes lettres.
    static let ambigus: Set<String> = ["une note", "nouvelle note", "notez", "note"]

    /// Le déclencheur en tête (un mot entier seulement : « notre », « noté » ne sont pas « note »), et ce qui suit.
    static func declencheur(_ s: String) -> (mot: String, reste: Substring)? {
        let bas = s.lowercased()
        for d in declencheurs where bas.hasPrefix(d) {
            if let c = bas.dropFirst(d.count).first, c.isLetter || c == "-" || c == "'" { continue }
            return (d, s.dropFirst(d.count))
        }
        return nil
    }
    /// Une note demandée : un déclencheur sans ambiguïté, ou n'importe lequel quand on s'adresse à Lucarne (« Lucarne, note… »).
    static func demandee(_ s: String, interpelle: Bool) -> Bool {
        guard let d = declencheur(s) else { return false }
        return interpelle || !ambigus.contains(d.mot)
    }

    /// Le reste après « note : », « prends une note pour dire que »… ; nil sans déclencheur. Seuls « que » et « pour dire que » tombent
    /// (« une note de 15 sur 20 », « note sur le budget » gardent leur sens).
    static func sansDeclencheur(_ s: String) -> String? {
        guard let d = declencheur(s) else { return nil }
        var reste = String(d.reste).trimmingCharacters(in: CharacterSet(charactersIn: " ,:;.!?-"))
        for lien in ["pour dire que ", "que ", "qu'"] where reste.lowercased().hasPrefix(lien) {
            reste = String(reste.dropFirst(lien.count)); break
        }
        return reste.trimmingCharacters(in: .whitespaces)
    }

    /// La note telle qu'on l'écrit : sans « s'il te plaît », une majuscule, un point au bout.
    public static func propre(_ brut: String) -> String {
        var t = TexteDicte.sansPolitesse(TexteDicte.unifier(brut))
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-"))
        guard !t.isEmpty else { return "" }
        if let d = t.last, !".!?…".contains(d) { t += "." }
        return t.prefix(1).uppercased() + t.dropFirst()
    }
}

// MARK: - La carte de fin

/// La carte qui suit la dictée : ce que Lucarne a compris, et ce qu'on peut en faire.
public struct CarteVoix: Equatable, Sendable {
    public enum Objet: Equatable, Sendable { case rappel(UUID), note(UUID) }
    public var objet: Objet
    /// Court, sans article ni point (« Livraison », « Prix sur la première page »).
    public var titre: String
    /// « demain · 13:00 » (un rappel) ; nil pour une note.
    public var quand: String?
    /// Une ligne (un rappel) ou deux (une note) ; vide : la carte n'a pas de résumé (la note tient dans son titre).
    public var resume: String
    public var genre: GenreVoix { if case .rappel = objet { return .rappel }; return .note }
    public init(objet: Objet, titre: String, quand: String?, resume: String) {
        self.objet = objet; self.titre = titre; self.quand = quand; self.resume = resume
    }

    /// La carte d'un rappel : son texte en titre, le jour et l'heure, et la phrase telle qu'elle a été entendue (on voit ce qui a été
    /// compris, et d'où vient le titre).
    public static func rappel(id: UUID, texte: String, echeance: Date, phrase: String, maintenant: Date, calendrier: Calendar = .current) -> CarteVoix {
        let titre = ResumeVoix.titre(texte, sansArticle: true)
        let quand = ListeRappels.jour(de: echeance, maintenant: maintenant, calendrier: calendrier) + " \u{00B7} " + FormatIlot.heure(echeance, calendrier: calendrier)
        return CarteVoix(objet: .rappel(id), titre: titre, quand: quand, resume: ResumeVoix.phraseEntendue(phrase))
    }

    /// La carte d'une note : un titre court tiré de sa première idée, et la note entière dessous (sauf si elle tient dans le titre).
    public static func note(id: UUID, texte: String) -> CarteVoix {
        let titre = ResumeVoix.titre(texte)
        let corps = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        let memeChose = ResumeVoix.cle(corps) == ResumeVoix.cle(titre)
        return CarteVoix(objet: .note(id), titre: titre, quand: nil, resume: memeChose ? "" : corps)
    }
}

/// Le titre et le résumé d'une carte, tirés du texte dicté (sur le Mac, sans IA : immédiat, et rien ne part).
public enum ResumeVoix {
    public static let titreMax = 40
    /// Les mots qui coupent une idée de sa suite (« Appeler Ladislas | pour le devis ») ; seulement après deux mots au moins.
    private static let liens = [" pour ", " avec ", " parce que ", " parce qu'", " car ", " afin de ", " afin d'", " au sujet de ", " et ", " mais "]
    private static let determinants = ["le ", "la ", "les ", "l'", "un ", "une ", "des ", "du "]

    /// La première idée du texte, sans point final, 40 caractères au plus (coupée entre deux mots, « … »). `sansArticle` : le titre d'un
    /// rappel est un nom (« La livraison » → « Livraison ») ; celui d'une note peut être une phrase (« Le devis est validé » le reste).
    public static func titre(_ texte: String, sansArticle: Bool = false) -> String {
        var t = TexteDicte.unifier(texte)
        // la première phrase, puis la première proposition
        if let r = t.rangeOfCharacter(from: CharacterSet(charactersIn: ".!?;:\n")) { t = String(t[..<r.lowerBound]) }
        if let r = t.range(of: ",") { t = String(t[..<r.lowerBound]) }
        for lien in liens {
            guard let r = t.range(of: lien, options: .caseInsensitive) else { continue }
            let avant = String(t[..<r.lowerBound])
            if avant.split(separator: " ").count >= 2 { t = avant }
        }
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:.!?…-"))
        // « La livraison » → « Livraison », « Le prix sur la première page » → « Prix sur la première page » (un nom après l'article ;
        // jamais un nom propre ni un chiffre, et jamais quand l'article est tout le titre)
        for d in determinants where sansArticle && t.lowercased().hasPrefix(d) {
            let suite = t.dropFirst(d.count)
            if let c = suite.first, c.isLowercase { t = String(suite) }
            break
        }
        if t.count > titreMax {
            var coupe = String(t.prefix(titreMax))
            if let espace = coupe.lastIndex(of: " ") { coupe = String(coupe[..<espace]) }
            t = coupe.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-")) + "\u{2026}"
        }
        guard !t.isEmpty else { return "Note" }
        return t.prefix(1).uppercased() + t.dropFirst()
    }

    /// La phrase dite à Lucarne, sans le mot d'appel ni « s'il te plaît », une majuscule et un point : « Rappelle-moi demain à 13 h pour
    /// la livraison. »
    public static func phraseEntendue(_ phrase: String) -> String {
        let reste = AnalyseCommandeIlot.sansAppel(phrase) ?? TexteDicte.unifier(phrase)
        return TexteNote.propre(reste)
    }

    /// Pour comparer deux textes : en minuscules, sans ponctuation ni espaces en trop.
    static func cle(_ s: String) -> String {
        s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == " " }.map(String.init).joined()
            .split(separator: " ").joined(separator: " ")
    }
}

/// Où en est l'envoi d'une carte vers l'app d'Apple.
public enum EnvoiVoix: Equatable, Sendable {
    /// « Envoyer dans Rappels » : rien n'est parti.
    case aEnvoyer
    /// La fenêtre de macOS (la première fois), ou l'app Notes qui s'ouvre : « Envoi… ».
    case enCours
    /// « ✓ Dans Rappels » : il y est.
    case fait
    /// L'accès est refusé (Réglages Système) : « Autoriser dans Réglages » ouvre le bon volet.
    case refuse
    /// L'envoi a échoué sans refus (Notes trop lent ou qui ne répond pas, Rappels qui n'enregistre pas) : « Réessayer », et la carte le dit.
    case echec

    public static let tous: [EnvoiVoix] = [.aEnvoyer, .enCours, .fait, .refuse, .echec]

    public func libelle(_ g: GenreVoix) -> String {
        switch self {
        case .aEnvoyer: return "Envoyer dans \(g.app)"
        case .enCours: return "Envoi\u{2026}"
        case .fait: return "Dans \(g.app)"
        case .refuse: return "Autoriser dans Réglages"
        case .echec: return "Réessayer"
        }
    }
    /// Le message court à côté du bouton (seulement après un échec) : ce qui s'est passé, sans accuser l'autorisation.
    public func message(_ g: GenreVoix) -> String? { self == .echec ? "\(g.app) n\u{2019}a pas répondu" : nil }
    /// Tous les libellés d'un genre : le bouton garde la largeur du plus long (il ne change pas de taille sous le pointeur).
    public static func libelles(_ g: GenreVoix) -> [String] { tous.map { $0.libelle(g) } }

    /// Un rappel : il a son double dans l'app Rappels (fait), l'accès est refusé, un envoi vient d'échouer avec l'accès donné (`essaye` :
    /// on a tenté), ou rien n'est parti (pendant la fenêtre de macOS, le contrôleur montre `.enCours`).
    public static func rappel(lie: Bool, acces: AccesRappelsApple, essaye: Bool = false) -> EnvoiVoix {
        if lie { return .fait }
        if acces == .refuse { return .refuse }
        return essaye && acces == .autorise ? .echec : .aEnvoyer
    }
}

/// La réponse de l'app Notes à « Envoyer dans Notes » (AppleScript) : faite, refusée (l'autorisation Automatisation manque : erreur
/// -1743, ou -1744 quand macOS ne peut pas la demander), ou un autre échec (Notes trop lent, -1712 ; qui ne répond pas ; script refusé…).
public enum ResultatVersNotes: Equatable, Sendable {
    case fait, refuse, echec
    /// D'après le numéro d'erreur d'AppleScript (nil : le script a réussi).
    public static func depuis(erreur: Int?) -> ResultatVersNotes {
        guard let e = erreur else { return .fait }
        return e == -1743 || e == -1744 ? .refuse : .echec
    }
}

/// Le texte final d'une dictée que l'îlot a prise (l'onde, « Rappel… ») mais où aucune commande n'a été lue (Groq a perdu le mot d'appel,
/// ou la phrase parle de Lucarne) : jamais collé en silence, il reste dans l'îlot (« Je n'ai pas compris », « Copier »), comme une
/// commande Lucarne pas comprise. Une dictée normale (l'îlot ne l'a pas prise) est collée.
public enum IssueVoix: Equatable, Sendable {
    case coller, garderDansLIlot
    public static func sansCommande(priseParLIlot: Bool) -> IssueVoix { priseParLIlot ? .garderDansLIlot : .coller }
}

/// Après un rappel dicté à Lucarne : l'envoyer tout de suite dans l'app Rappels (Hugues l'a déjà voulu une fois et l'accès est donné), ou
/// laisser le bouton de la carte (rien ne part sans son clic). La carte remplace la question « Aussi dans l'app Rappels ? » : un clic sur
/// « Envoyer dans Rappels » vaut ce « Oui ».
public enum PlanCarteRappel {
    public static func envoyerTout(choix: ChoixRappelsApple?, acces: AccesRappelsApple) -> Bool { choix == .oui && acces == .autorise }
}

// MARK: - L'onde de la voix

/// L'onde de la voix (31 barres) : le niveau du micro (20 fois par seconde) part du milieu et gagne les bords, une barre plus tard à
/// chaque pas ; chaque changement lance un ressort (les mêmes que l'onde des cartes d'accueil, `NiveauxVoix`) : la barre monte avec élan,
/// rebondit un peu, redescend. Après le relâchement, l'onde se calme et une petite vague la parcourt le temps que le texte arrive.
public struct OndeVoix: Equatable, Sendable {
    public static let barres = 31
    /// Un niveau tous les 50 ms (le rythme du micro) ; une barre plus loin du milieu le reçoit un pas plus tard.
    public static let pas = 0.05
    /// Les derniers niveaux gardés (3,2 s : bien plus que les 15 pas qui séparent le milieu du bord, plus les 12 pas d'un ressort).
    static let garde = 64
    /// Plus le niveau est fort plus la barre monte ; la voix ordinaire (≈ 0,5) monte presque en haut.
    static let gain = 1.35

    /// L'instant (secondes, horloge monotone) du premier niveau ; nil : rien reçu.
    public private(set) var debut: Double?
    /// Le relâchement de fn (la petite vague commence) ; nil : on parle encore.
    public private(set) var relache: Double?
    /// Les niveaux lissés, un par pas, du pas `premier` au plus récent.
    public private(set) var niveaux: [Double] = []
    public private(set) var premier = 0

    public init() {}

    /// Un niveau du micro (0…1) à l'instant `t`. Il monte vite (70 % de l'écart d'un coup) et redescend plus doucement (30 %) : une voix,
    /// pas un crépitement. Les pas sans niveau (le micro a pris du retard) gardent le dernier.
    public mutating func recevoir(_ n: Double, a t: Double) {
        let v = min(1, max(0, n))
        guard let d = debut else { debut = t; premier = 0; niveaux = [lisse(0, v)]; return }
        let k = max(0, Int(floor((t - d) / Self.pas)))
        let fin = premier + niveaux.count - 1
        if k <= fin {
            // le même pas (ou un niveau en retard) : le plus fort des deux le garde (une syllabe brève ne se perd pas)
            let avant = niveaux.count > 1 ? niveaux[niveaux.count - 2] : 0
            niveaux[niveaux.count - 1] = max(niveaux[niveaux.count - 1], lisse(avant, v))
            return
        }
        // les pas sans niveau (le micro a pris du retard) gardent le dernier ; jamais plus que ce qu'on garde
        let dernier = niveaux.last ?? 0
        for _ in 0..<min(k - fin - 1, Self.garde) { niveaux.append(dernier) }
        niveaux.append(lisse(dernier, v))
        premier = k - niveaux.count + 1
        if niveaux.count > Self.garde { let x = niveaux.count - Self.garde; niveaux.removeFirst(x); premier += x }
    }
    private func lisse(_ avant: Double, _ v: Double) -> Double { avant + (v - avant) * (v > avant ? 0.7 : 0.3) }

    /// fn relâchée à `t` : la voix s'éteint (des niveaux nuls arrivent), la petite vague prend le relais.
    public mutating func relacher(a t: Double) {
        guard relache == nil else { return }
        relache = t
    }

    /// Le niveau lissé au pas `k` (0 avant le premier, le dernier connu après ; après le relâchement, 0).
    func niveau(_ k: Int) -> Double {
        guard !niveaux.isEmpty, k >= premier else { return 0 }
        if let r = relache, let d = debut, Double(k) * Self.pas >= r - d { return 0 }
        return niveaux[min(niveaux.count - 1, k - premier)]
    }

    /// La hauteur de la barre (0…1) à l'instant `t`. Plus haute au milieu (une cloche), un léger frémissement propre à chaque barre.
    public func hauteur(_ barre: Int, a t: Double) -> Double {
        let milieu = Double(Self.barres - 1) / 2
        let d = abs(Double(barre) - milieu)
        let profil = 0.3 + 0.7 * exp(-d * d / (2 * 6.5 * 6.5))
        let retard = Int(d.rounded())
        var voix = 0.0
        if let debut {
            voix = NiveauxVoix.valeur(t: t - debut, pas: Self.pas) { k in
                profil * self.niveau(k - retard) * (0.82 + 0.18 * NiveauxVoix.bruit(barre, k))
            }
        }
        // la petite vague d'après le relâchement : elle arrive en 0,3 s, va du milieu vers les bords
        var vague = 0.0
        if let r = relache {
            let arrivee = min(1, max(0, (t - r) / 0.3))
            let s = max(0, sin((t - r) * 7 - d * 0.5))
            vague = arrivee * 0.34 * s * s
        }
        return min(1, max(0, max(voix * Self.gain, vague)))
    }
}

// MARK: - Les mesures

/// Les mesures de l'écoute et de la carte (maquette : 1 px = 1 pt). Les largeurs sont comptées au-delà de la demi-caméra (GeoIlot).
public enum MesuresVoix {
    /// L'icône (micro, puis le glyphe du genre) dans l'aile gauche : cou de 40 pt (+ 6 d'épaule = 46 pt dans la barre, sous les 66).
    public static let cou: Double = 40
    /// Le corps de l'écoute : l'onde (189 pt) au milieu, avec de l'air ; 40 pt au moins au-delà du cou et de son congé (sinon une
    /// languette). La maquette dessinait 75 pt : ça ne laissait pas au congé et au coin haut la place de se dessiner.
    public static let corps: Double = 90
    /// L'onde : 10 pt sous la barre, 30 pt de haut, 8 pt dessous.
    public static let ondeHaut: Double = 10, ondeHauteur: Double = 30, ondeLargeur: Double = 189
    public static let profondeurOnde: Double = ondeHaut + ondeHauteur + 8
    /// Le libellé (« Rappel… ») : une ligne de plus sous l'onde.
    public static let ligneLibelle: Double = 24
    public static let libelleHaut: Double = 46, libelleHauteur: Double = 17
    /// La carte : la largeur de la carte Centre (on passe de l'une à l'autre sans élargir la forme).
    public static let corpsCarte: Double = 142
    public static let marge: Double = 14
    public static let coche: Double = 24, ecartCoche: Double = 12
    public static let titre: Double = 19, quand: Double = 17, ecartQuand: Double = 1
    public static let ligneResume: Double = 17, ecartResume: Double = 3
    public static let ecartBoutons: Double = 12, bouton: Double = 30
    /// Un rappel : une ligne de résumé ; une note : deux.
    public static func lignesResumeMax(_ g: GenreVoix) -> Int { g == .rappel ? 1 : 2 }

    /// La hauteur sous la barre d'une carte : marge, titre, jour et heure (un rappel), résumé (0 à 2 lignes), boutons, marge.
    public static func profondeurCarte(quand: Bool, lignesResume n: Int) -> Double {
        marge + titre + (quand ? ecartQuand + self.quand : 0) + (n > 0 ? ecartResume + Double(n) * ligneResume : 0) + ecartBoutons + bouton + marge
    }
    /// La carte la plus haute : celle de la table (un rappel avec sa ligne de résumé ; une note à deux lignes fait 1 pt de moins).
    public static let profondeurCarteMax: Double = max(profondeurCarte(quand: true, lignesResume: 1), profondeurCarte(quand: false, lignesResume: 2))
}
