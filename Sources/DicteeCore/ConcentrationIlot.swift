import Foundation

// Les modes de Concentration de macOS dans l'îlot (maquette design/maquettes/ilot-concentration.html) : logique pure, sans interface.
//
// macOS n'offre AUCUNE interface publique pour allumer un mode de Concentration (seul l'app Raccourcis le peut, avec son action « Définir
// la concentration »), ni pour savoir lequel est allumé sans autorisation spéciale. Verbe fabrique donc ici UN raccourci, « Concentration
// Verbe » : signé sur le Mac de Hugues (`shortcuts sign`), ajouté une fois d'un clic dans Raccourcis, puis lancé avec `shortcuts run`. Il
// lit une commande (« on:<mode> », « off:<mode> », « etat ») et ne fait rien d'autre. Les preuves et les voies écartées :
// docs/concentration-ilot.md.

/// Un mode de Concentration de macOS. L'identifiant (`rawValue`) est rangé dans le fichier de Verbe : ne jamais le changer.
public enum ModeConcentration: String, CaseIterable, Codable, Sendable {
    case nePasDeranger = "ne-pas-deranger", travail, personnel, sommeil, reduire

    /// L'identifiant du mode chez macOS (relevé dans la configuration des modes de macOS 26, `ModeConfigurations.json`).
    public var identifiantSysteme: String {
        switch self {
        case .nePasDeranger: return "com.apple.donotdisturb.mode.default"
        case .travail: return "com.apple.focus.work"
        case .personnel: return "com.apple.focus.personal-time"
        case .sommeil: return "com.apple.sleep.sleep-mode"
        case .reduire: return "com.apple.focus.reduce-interruptions"
        }
    }
    /// Le nom dans l'îlot (maquette).
    public var nom: String {
        switch self {
        case .nePasDeranger: return "Ne pas déranger"
        case .travail: return "Travail"
        case .personnel: return "Personnel"
        case .sommeil: return "Sommeil"
        case .reduire: return "Réduire les interruptions"
        }
    }
    /// Sous le rond du Centre, où la place est comptée (une colonne de 70 pt).
    public var nomCourt: String { self == .reduire ? "Réduire" : nom }
    /// La couleur du mode (maquette), en 0xRRGGBB.
    public var couleur: UInt32 {
        switch self {
        case .nePasDeranger: return 0x5E5CE6
        case .travail: return 0x32B6C8
        case .personnel: return 0xB58CF6
        case .sommeil: return 0x4A8DF0
        // l'icône est un anneau de quatre couleurs : la sélection prend une teinte sobre tirée de son rose (lisible sur le noir, distincte
        // du violet de Personnel) ; le gris de la maquette faisait une plaque claire, pas une sélection
        case .reduire: return 0xC9799E
        }
    }
    /// Le symbole SF du mode ; nil : « Réduire les interruptions » a un glyphe dessiné (l'anneau de couleurs et l'étincelle, maquette).
    public var symbole: String? {
        switch self {
        case .nePasDeranger: return "moon.fill"
        case .travail: return "briefcase.fill"
        case .personnel: return "person.fill"
        case .sommeil: return "bed.double.fill"
        case .reduire: return nil
        }
    }
    /// « Réduire les interruptions » prend toute la largeur de la grille (son nom est long), sous les quatre autres.
    public var largeurPleine: Bool { self == .reduire }
    /// Les noms que macOS peut donner au mode (français et anglais, et ceux de la configuration : « Repos », « Temps pour soi »).
    public var nomsSysteme: [String] {
        switch self {
        case .nePasDeranger: return ["Ne pas déranger", "Do Not Disturb"]
        case .travail: return ["Travail", "Work"]
        case .personnel: return ["Temps pour soi", "Personnel", "Personal", "Personal Time"]
        case .sommeil: return ["Repos", "Sommeil", "Sleep"]
        case .reduire: return ["Réduire les interruptions", "Reduce Interruptions"]
        }
    }
    /// Le mode qui porte ce nom chez macOS (sans tenir compte des majuscules ni des accents), s'il y en a un.
    public static func depuisNomSysteme(_ nom: String) -> ModeConcentration? {
        let n = normaliser(nom)
        guard !n.isEmpty else { return nil }
        return allCases.first { $0.nomsSysteme.map(normaliser).contains(n) }
    }
    static func normaliser(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
            .replacingOccurrences(of: "\u{2019}", with: "'").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// La durée choisie (maquette : « 1 h », « Jusqu'à ce soir », « Jusqu'à ce que je l'arrête »).
public enum DureeConcentration: String, CaseIterable, Codable, Sendable {
    case uneHeure = "1h", ceSoir = "ce-soir", jusquALArret = "arret"

    public var libelle: String {
        switch self {
        case .uneHeure: return "1 h"
        case .ceSoir: return "Jusqu\u{2019}à ce soir"
        case .jusquALArret: return "Jusqu\u{2019}à ce que je l\u{2019}arrête"
        }
    }
    /// Sous le rond du Centre (« Travail · 1 h ») ; nil : jusqu'à l'arrêt (le nom du mode suffit).
    public var court: String? {
        switch self {
        case .uneHeure: return "1 h"
        case .ceSoir: return "ce soir"
        case .jusquALArret: return nil
        }
    }
    /// « Ce soir » : 18:00, ou 22:00 si 18:00 est passé (ou à moins de 30 min), sinon minuit. Une durée qui finirait dans moins de
    /// 30 minutes ne serait plus « ce soir » : on prend l'heure suivante (après 23:30, 30 min).
    public static let heuresDuSoir = [18, 22, 24]
    public static let margeCeSoir: TimeInterval = 30 * 60

    /// Quand le mode s'arrête (nil : jusqu'à ce que Hugues l'arrête).
    public func fin(depuis t: Date, calendrier: Calendar = .current) -> Date? {
        switch self {
        case .uneHeure: return t.addingTimeInterval(3600)
        case .jusquALArret: return nil
        case .ceSoir:
            // à l'heure de l'horloge (un jour de changement d'heure compte 23 ou 25 h : « 18 h après minuit » ne serait pas 18:00)
            let jour = calendrier.startOfDay(for: t)
            let minuit = calendrier.date(byAdding: .day, value: 1, to: jour) ?? t.addingTimeInterval(86_400)
            for h in Self.heuresDuSoir {
                let d = h >= 24 ? minuit : (calendrier.date(bySettingHour: h, minute: 0, second: 0, of: t) ?? minuit)
                if d.timeIntervalSince(t) >= Self.margeCeSoir { return d }
            }
            return t.addingTimeInterval(Self.margeCeSoir)
        }
    }
}

/// Le mode allumé par Verbe, et jusqu'à quand.
public struct EtatConcentration: Codable, Equatable, Sendable {
    public var mode: ModeConcentration
    public var duree: DureeConcentration
    public var debut: Date
    /// nil : jusqu'à ce que Hugues l'arrête.
    public var fin: Date?

    public init(mode: ModeConcentration, duree: DureeConcentration, debut: Date, calendrier: Calendar = .current) {
        // à la seconde : le fichier garde les dates à la seconde (ISO 8601), relu, l'état est le même
        let d = Date(timeIntervalSinceReferenceDate: debut.timeIntervalSinceReferenceDate.rounded(.down))
        self.mode = mode; self.duree = duree; self.debut = d
        fin = duree.fin(depuis: d, calendrier: calendrier)
    }

    /// Le temps qui reste (nil : jusqu'à l'arrêt).
    public func reste(a t: Date) -> TimeInterval? { fin.map { max(0, $0.timeIntervalSince(t)) } }
    /// La part qui reste, de 1 (tout juste allumé) à 0 (fini) : la barre de la carte. Jusqu'à l'arrêt : 1.
    public func fraction(a t: Date) -> Double {
        guard let fin else { return 1 }
        let total = fin.timeIntervalSince(debut)
        guard total > 0 else { return 0 }
        return min(1, max(0, fin.timeIntervalSince(t) / total))
    }
    public func estFini(a t: Date) -> Bool { fin.map { t >= $0 } ?? false }
    /// « +30 min » : la fin recule d'une demi-heure (jusqu'à l'arrêt : rien à reculer).
    public static let prolongation: TimeInterval = 30 * 60
    @discardableResult
    public mutating func prolonger(a t: Date) -> Bool {
        guard let f = fin else { return false }
        fin = max(f, t).addingTimeInterval(Self.prolongation)
        return true
    }
    /// « jusqu'à 15:30 », « jusqu'à l'arrêt » (la bannière, la légende de la carte).
    public func jusqua(calendrier: Calendar = .current) -> String {
        guard let fin else { return "jusqu\u{2019}à l\u{2019}arrêt" }
        let c = calendrier.dateComponents([.hour, .minute], from: fin)
        return "jusqu\u{2019}à " + String(format: "%d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
    /// « encore 42 min », « encore 1 h 05 » (arrondi à la minute du dessus : jamais « encore 0 min » avant la fin), « jusqu'à l'arrêt ».
    public func encore(a t: Date) -> String {
        guard let r = reste(a: t) else { return "jusqu\u{2019}à l\u{2019}arrêt" }
        let m = Int((r / 60).rounded(.up))
        return "encore " + (m >= 60 ? "\(m / 60) h " + String(format: "%02d", m % 60) : "\(m) min")
    }
}

/// Le dernier mode lancé (le rond du Centre le relance d'un clic, maquette étape 7).
public struct DernierConcentration: Codable, Equatable, Sendable {
    public var mode: ModeConcentration
    public var duree: DureeConcentration
    public init(mode: ModeConcentration, duree: DureeConcentration) { self.mode = mode; self.duree = duree }
}

/// Ce que Verbe garde (~/Library/Application Support/Dictee/concentration.json, 0600) : le mode allumé, le dernier lancé, et l'identifiant
/// du raccourci que Verbe a ajouté (le seul qu'il lance jamais).
public struct MemoireConcentration: Codable, Equatable, Sendable {
    public var actif: EtatConcentration?
    public var dernier: DernierConcentration?
    public var raccourci: String?
    public init(actif: EtatConcentration? = nil, dernier: DernierConcentration? = nil, raccourci: String? = nil) {
        self.actif = actif; self.dernier = dernier; self.raccourci = raccourci
    }
    /// Chaque partie se relit seule : une partie illisible (un mode d'une version plus récente) est oubliée, le reste (le raccourci
    /// surtout : sans lui, Raccourcis en ajouterait un second) est gardé. nil : pas du JSON.
    public static func depuis(_ d: Data) -> MemoireConcentration? {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(MemoireConcentration.self, from: d)
    }
    private enum Cles: String, CodingKey { case actif, dernier, raccourci }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Cles.self)
        actif = try? c.decodeIfPresent(EtatConcentration.self, forKey: .actif)
        dernier = try? c.decodeIfPresent(DernierConcentration.self, forKey: .dernier)
        raccourci = try? c.decodeIfPresent(String.self, forKey: .raccourci)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Cles.self)
        try c.encodeIfPresent(actif, forKey: .actif)
        try c.encodeIfPresent(dernier, forKey: .dernier)
        try c.encodeIfPresent(raccourci, forKey: .raccourci)
    }
    public func donnees() -> Data? {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.sortedKeys]
        return try? enc.encode(self)
    }
}

/// Le rond « Concentration » du Centre (maquette, étapes 1 et 7).
public enum RondConcentration: Equatable, Sendable {
    /// Rien d'allumé : la lune, « Désactivée ».
    case eteint
    /// Un mode allumé par Verbe : le rond de sa couleur, son nom.
    case actif(ModeConcentration)
    /// Rien d'allumé, mais un mode a déjà servi : cerclé de sa couleur, « Travail · 1 h » ; un clic le relance.
    case dernier(DernierConcentration)
    /// Un mode allumé ailleurs (Centre de contrôle) que Verbe ne connaît pas : son nom, tel que macOS le donne.
    case autre(String)

    public static func depuis(actif: EtatConcentration?, dernier: DernierConcentration?, externe: String?) -> RondConcentration {
        if let a = actif { return .actif(a.mode) }
        if let e = externe, !e.isEmpty { return .autre(e) }
        if let d = dernier { return .dernier(d) }
        return .eteint
    }
    /// Sous le rond.
    public var etat: String {
        switch self {
        case .eteint: return "Désactivée"
        case .actif(let m): return m.nomCourt
        case .dernier(let d): return d.duree.court.map { d.mode.nomCourt + " \u{00B7} " + $0 } ?? d.mode.nomCourt
        case .autre(let n): return n
        }
    }
}

/// Ce que dit la ligne grise de la carte, sous les modes (maquette : « Choisis un mode, puis une durée »).
public enum LegendeConcentration {
    public static func texte(actif: EtatConcentration?, choisi: ModeConcentration?, raccourciManquant: Bool, calendrier: Calendar = .current) -> String {
        if let c = choisi {
            if raccourciManquant { return "Ajoute le raccourci dans Raccourcis, puis choisis une durée" }
            if let a = actif, a.mode == c { return c.nom + " \u{00B7} " + a.jusqua(calendrier: calendrier) }
            return c.nom + " \u{00B7} pendant combien de temps\u{00A0}?"
        }
        if let a = actif { return a.mode.nom + " \u{00B7} " + a.jusqua(calendrier: calendrier) }
        return "Choisis un mode, puis une durée"
    }
}

/// Les bannières (maquette, étapes 3 et 6).
public enum BanniereConcentration {
    /// Sur une seule ligne : « Travail · jusqu'à 15:30 ».
    public static func lance(_ a: EtatConcentration, calendrier: Calendar = .current) -> String { a.mode.nom + " \u{00B7} " + a.jusqua(calendrier: calendrier) }
    /// « Fin de Travail » (« Fin de Ne pas déranger » se lit mal : « Fin du mode Ne pas déranger »).
    public static func fin(_ m: ModeConcentration) -> String { m == .nePasDeranger ? "Fin du mode Ne pas déranger" : "Fin de " + m.nom }
    /// Sous le titre : ce qui change pour de vrai (Verbe ne voit pas les notifications retenues : il ne les compte pas).
    public static let finSous = "Les notifications reviennent"
}

/// Les mesures des deux cartes (maquette, en points) : elles servent au dessin, à la hauteur de la forme et aux essais.
public enum MesuresConcentration {
    // la carte des modes : 14, l'en-tête (26), 12, la grille (trois rangées de 48, 8 entre elles), 12, la légende (14), 6, les durées (32), 14
    public static let haut: Double = 14, entete: Double = 26, ecartEntete: Double = 12, bouton: Double = 48, ecart: Double = 8
    public static let ecartLegende: Double = 12, legende: Double = 14, ecartDurees: Double = 6, duree: Double = 32, bas: Double = 14
    public static var grille: Double { 3 * bouton + 2 * ecart }
    public static var profondeurCarte: Double { haut + entete + ecartEntete + grille + ecartLegende + legende + ecartDurees + duree + bas }
    // la carte « où en est le mode » : 14, la ligne du haut (44), 14, la barre (6), 12, « Changer de mode » (18), 14 ; le pied « Centre » s'ajoute
    public static let ligne: Double = 44, barre: Double = 6, ecartBarre: Double = 14, ecartChanger: Double = 12, changer: Double = 18
    public static var profondeurStatut: Double { haut + ligne + ecartBarre + barre + ecartChanger + changer + bas }
    /// Les bannières : une ligne (44 pt sous la barre), et « Fin de… » sur deux lignes (56 pt).
    public static let banniere: Double = 44, banniereFin: Double = 56
    /// L'aile gauche de l'îlot replié : l'icône du mode (18 pt) dans un cou de 40 pt ; à droite, rien que la caméra.
    public static let cou: Double = 40
}

/// Le raccourci « Concentration Verbe » : ce qu'il contient, les commandes qu'il comprend, et la lecture de ce que Raccourcis répond.
public enum RaccourciConcentration {
    /// Son nom dans l'app Raccourcis : Raccourcis nomme un raccourci importé d'après son fichier (« Concentration Verbe.shortcut »).
    public static let nom = "Concentration Verbe"
    public static let reponseOK = "ok", reponseInconnue = "inconnu"

    public enum Commande: Equatable, Sendable {
        case allumer(ModeConcentration), eteindre(ModeConcentration), lire
        /// Ce que le raccourci reçoit (une ligne).
        public var texte: String {
            switch self {
            case .allumer(let m): return "on:" + m.identifiantSysteme
            case .eteindre(let m): return "off:" + m.identifiantSysteme
            case .lire: return "etat"
            }
        }
    }

    /// Le raccourci, en liste de propriétés : l'entrée nettoyée (espaces, retour à la ligne), puis une branche « si l'entrée est … » par
    /// commande, chacune avec UNE action et sa réponse. « Définir la concentration » ne prend pas son mode d'une variable (un mode est un
    /// objet, pas un nom) : une branche par mode, comme le fait l'extension « Focus Modes » de Raycast. Ne pas déranger est le mode par
    /// défaut de l'action : on le choisit en ne nommant aucun mode. Allumé « jusqu'à ce que je l'arrête » (l'arrêt est le choix par défaut
    /// de l'action) : c'est Verbe qui l'éteint à l'heure dite (une échéance) ; voir docs/concentration-ilot.md.
    public static func contenu(uuid: () -> String = { UUID().uuidString }) -> [String: Any] {
        let entree = uuid()
        func action(_ id: String, _ p: [String: Any]) -> [String: Any] { ["WFWorkflowActionIdentifier": id, "WFWorkflowActionParameters": p] }
        func texte(_ s: String, attache: [String: Any]? = nil) -> [String: Any] {
            ["WFSerializationType": "WFTextTokenString",
             "Value": ["string": attache == nil ? s : "\u{FFFC}", "attachmentsByRange": attache.map { ["{0, 1}": $0] } ?? [String: Any]()]]
        }
        func repondre(_ s: String) -> [String: Any] { action("is.workflow.actions.output", ["WFOutput": texte(s)]) }
        func si(_ valeur: String, _ corps: [[String: Any]]) -> [[String: Any]] {
            let groupe = uuid()
            return [action("is.workflow.actions.conditional", [
                        "GroupingIdentifier": groupe, "WFControlFlowMode": 0, "WFCondition": 4, "WFConditionalActionString": valeur,
                        "WFInput": ["Type": "Variable", "Variable": ["WFSerializationType": "WFTextTokenAttachment",
                                                                    "Value": ["Type": "ActionOutput", "OutputName": "Updated Text", "OutputUUID": entree]]]])]
                + corps
                + [action("is.workflow.actions.conditional", ["GroupingIdentifier": groupe, "WFControlFlowMode": 1]),
                   action("is.workflow.actions.conditional", ["GroupingIdentifier": groupe, "WFControlFlowMode": 2])]
        }
        func definir(_ m: ModeConcentration, _ allume: Bool) -> [String: Any] {
            var p: [String: Any] = ["Enabled": allume ? 1 : 0]
            if m != .nePasDeranger { p["FocusModes"] = ["Identifier": m.identifiantSysteme, "DisplayString": m.nom] }
            return action("is.workflow.actions.dnd.set", p)
        }
        var actions: [[String: Any]] = [
            action("is.workflow.actions.text.trimwhitespace", [
                "UUID": entree,
                "WFInput": ["WFSerializationType": "WFTextTokenString", "Value": ["string": "\u{FFFC}", "attachmentsByRange": ["{0, 1}": ["Type": "ExtensionInput"]]]]])
        ]
        for m in ModeConcentration.allCases {
            actions += si(Commande.allumer(m).texte, [definir(m, true), repondre(reponseOK)])
            actions += si(Commande.eteindre(m).texte, [definir(m, false), repondre(reponseOK)])
        }
        // « etat » : la concentration en cours (rien si aucune), telle que Raccourcis l'écrit (son nom)
        let lu = uuid()
        actions += si(Commande.lire.texte, [action("is.workflow.actions.dnd.getfocus", ["UUID": lu]),
                                           action("is.workflow.actions.output", ["WFOutput": texte("", attache: ["Type": "ActionOutput", "OutputName": "Current Focus", "OutputUUID": lu])])])
        actions.append(repondre(reponseInconnue))
        return [
            "WFWorkflowClientVersion": "2607.0.4",
            "WFWorkflowMinimumClientVersion": 900,
            "WFWorkflowMinimumClientVersionString": "900",
            "WFWorkflowIcon": ["WFWorkflowIconStartColor": 1440408063, "WFWorkflowIconGlyphNumber": 59511],
            "WFWorkflowImportQuestions": [Any](),
            "WFWorkflowTypes": [Any](),
            "WFQuickActionSurfaces": [Any](),
            "WFWorkflowHasShortcutInputVariables": true,
            "WFWorkflowInputContentItemClasses": ["WFStringContentItem", "WFGenericFileContentItem"],
            "WFWorkflowOutputContentItemClasses": ["WFStringContentItem"],
            "WFWorkflowActions": actions,
        ]
    }

    /// Le fichier à signer (liste de propriétés binaire).
    public static func donnees(uuid: () -> String = { UUID().uuidString }) -> Data? {
        try? PropertyListSerialization.data(fromPropertyList: contenu(uuid: uuid), format: .binary, options: 0)
    }

    /// Un raccourci de la bibliothèque de Hugues, tel que `shortcuts list --show-identifiers` l'écrit : « Nom (IDENTIFIANT) ».
    public struct Installe: Equatable, Sendable {
        public var nom: String
        public var identifiant: String
        public init(nom: String, identifiant: String) { self.nom = nom; self.identifiant = identifiant }
    }
    public static func lireListe(_ sortie: String) -> [Installe] {
        sortie.split(whereSeparator: \.isNewline).compactMap { ligne in
            let l = ligne.trimmingCharacters(in: .whitespaces)
            guard l.hasSuffix(")"), let ouvre = l.range(of: " (", options: .backwards) else { return nil }
            let id = String(l[ouvre.upperBound..<l.index(before: l.endIndex)])
            guard id.count == 36, UUID(uuidString: id) != nil else { return nil }
            return Installe(nom: String(l[..<ouvre.lowerBound]), identifiant: id.uppercased())
        }
    }
    /// Le raccourci que Verbe vient d'ajouter : un identifiant qui n'était pas là avant l'import (`avant`), au nom de « Concentration
    /// Verbe » (ou « Concentration Verbe 2 » si Hugues en avait déjà un). Jamais un raccourci qui existait déjà : Verbe ne lance que le sien.
    public static func nouveau(dans liste: [Installe], avant: Set<String>) -> String? {
        liste.last { i in
            guard !avant.contains(i.identifiant) else { return false }
            // « Concentration Verbe », ou « Concentration Verbe 2 » (le numéro que Raccourcis ajoute) ; jamais « … copie »
            if i.nom == nom { return true }
            guard i.nom.hasPrefix(nom + " ") else { return false }
            let suite = i.nom.dropFirst(nom.count + 1)
            return !suite.isEmpty && suite.allSatisfy(\.isNumber)
        }?.identifiant
    }
    /// Le raccourci retenu est-il toujours là ?
    public static func present(_ identifiant: String, dans liste: [Installe]) -> Bool {
        liste.contains { $0.identifiant.caseInsensitiveCompare(identifiant) == .orderedSame }
    }

    /// Ce que répond « etat » : rien (aucune concentration), un mode connu, ou un autre (un mode créé par Hugues).
    public enum Lu: Equatable, Sendable { case aucun, mode(ModeConcentration), autre(String) }
    public static func lireEtat(_ sortie: String) -> Lu {
        let s = sortie.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return .aucun }
        return ModeConcentration.depuisNomSysteme(s).map(Lu.mode) ?? .autre(String(s.prefix(40)))
    }
}
