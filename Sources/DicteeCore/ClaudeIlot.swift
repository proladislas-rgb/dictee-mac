import Foundation

// « Claude au travail » (maquette design/maquettes/ilot-apple.html, cinq idées de plus, 1) : l'îlot montre où en est une tâche de
// Claude Code. Logique pure, sans système :
// - `JSONOrdonne` lit et réécrit un JSON en gardant l'ordre des clés et le texte des nombres (le ~/.claude/settings.json de Hugues ne
//   bouge pas d'un octet en dehors de nos crochets) ;
// - `CrochetsClaude` fusionne nos crochets dans ce fichier, sans rien écraser, et les retire ;
// - `ScriptCrochet` est le petit script shell que Claude Code appelle à chaque événement ;
// - `EvenementClaude`, `SessionClaude`, `VeilleClaude` lisent les lignes écrites par ce script et en tirent l'état de chaque session.

// MARK: - JSON ordonné

/// Un JSON qui garde l'ordre des clés et le texte exact des nombres : relu puis réécrit à la façon de `JSON.stringify(x, null, 2)` (comme
/// Claude Code écrit son settings.json), un fichier qu'on n'a pas touché ressort identique.
public enum JSONOrdonne: Equatable, Sendable {
    public struct Membre: Equatable, Sendable {
        public var cle: String
        public var valeur: JSONOrdonne
        public init(_ cle: String, _ valeur: JSONOrdonne) { self.cle = cle; self.valeur = valeur }
    }
    case objet([Membre])
    case tableau([JSONOrdonne])
    case chaine(String)
    /// Le texte du nombre tel qu'il était écrit (« 1.50 » reste « 1.50 »).
    case nombre(String)
    case booleen(Bool)
    case nul

    public struct ErreurLecture: Error, Equatable { public var position: Int }

    public subscript(cle: String) -> JSONOrdonne? {
        guard case .objet(let m) = self else { return nil }
        return m.first { $0.cle == cle }?.valeur
    }
    public var membres: [Membre]? { if case .objet(let m) = self { return m }; return nil }
    public var elements: [JSONOrdonne]? { if case .tableau(let t) = self { return t }; return nil }
    public var texte: String? { if case .chaine(let s) = self { return s }; return nil }

    /// Remplace la valeur de `cle` à sa place, ou l'ajoute à la fin ; nil la retire.
    public mutating func ecrire(_ cle: String, _ valeur: JSONOrdonne?) {
        guard case .objet(var m) = self else { return }
        if let i = m.firstIndex(where: { $0.cle == cle }) {
            if let valeur { m[i].valeur = valeur } else { m.remove(at: i) }
        } else if let valeur { m.append(Membre(cle, valeur)) }
        self = .objet(m)
    }

    // MARK: lecture

    public static func lire(_ texte: String) throws -> JSONOrdonne {
        var l = Lecteur(octets: Array(texte.utf8))
        l.blancs()
        let v = try l.valeur(profondeur: 0)
        l.blancs()
        guard l.i == l.octets.count else { throw ErreurLecture(position: l.i) }
        return v
    }

    private struct Lecteur {
        let octets: [UInt8]
        var i = 0
        init(octets: [UInt8]) { self.octets = octets }
        mutating func blancs() { while i < octets.count, [0x20, 0x09, 0x0A, 0x0D].contains(octets[i]) { i += 1 } }
        func erreur() -> ErreurLecture { ErreurLecture(position: i) }
        mutating func mot(_ m: String) -> Bool {
            let b = Array(m.utf8)
            guard i + b.count <= octets.count, Array(octets[i..<(i + b.count)]) == b else { return false }
            i += b.count; return true
        }
        mutating func valeur(profondeur: Int) throws -> JSONOrdonne {
            guard profondeur < 512, i < octets.count else { throw erreur() }
            switch octets[i] {
            case 0x7B: // {
                i += 1; blancs()
                var m: [Membre] = []
                if i < octets.count, octets[i] == 0x7D { i += 1; return .objet(m) }
                while true {
                    blancs()
                    guard i < octets.count, octets[i] == 0x22 else { throw erreur() }
                    let k = try chaine()
                    blancs()
                    guard i < octets.count, octets[i] == 0x3A else { throw erreur() }
                    i += 1; blancs()
                    m.append(Membre(k, try valeur(profondeur: profondeur + 1)))
                    blancs()
                    guard i < octets.count else { throw erreur() }
                    if octets[i] == 0x2C { i += 1; continue }
                    if octets[i] == 0x7D { i += 1; return .objet(m) }
                    throw erreur()
                }
            case 0x5B: // [
                i += 1; blancs()
                var t: [JSONOrdonne] = []
                if i < octets.count, octets[i] == 0x5D { i += 1; return .tableau(t) }
                while true {
                    blancs()
                    t.append(try valeur(profondeur: profondeur + 1))
                    blancs()
                    guard i < octets.count else { throw erreur() }
                    if octets[i] == 0x2C { i += 1; continue }
                    if octets[i] == 0x5D { i += 1; return .tableau(t) }
                    throw erreur()
                }
            case 0x22: return .chaine(try chaine())
            case 0x74: if mot("true") { return .booleen(true) }; throw erreur()
            case 0x66: if mot("false") { return .booleen(false) }; throw erreur()
            case 0x6E: if mot("null") { return .nul }; throw erreur()
            default: return .nombre(try nombre())
            }
        }
        mutating func nombre() throws -> String {
            let debut = i
            func chiffres() -> Int { let d = i; while i < octets.count, (0x30...0x39).contains(octets[i]) { i += 1 }; return i - d }
            if i < octets.count, octets[i] == 0x2D { i += 1 }
            guard chiffres() > 0 else { throw erreur() }
            if i < octets.count, octets[i] == 0x2E { i += 1; guard chiffres() > 0 else { throw erreur() } }
            if i < octets.count, octets[i] == 0x65 || octets[i] == 0x45 {
                i += 1
                if i < octets.count, octets[i] == 0x2B || octets[i] == 0x2D { i += 1 }
                guard chiffres() > 0 else { throw erreur() }
            }
            return String(decoding: octets[debut..<i], as: UTF8.self)
        }
        mutating func hex4() throws -> UInt32 {
            guard i + 4 <= octets.count, let v = UInt32(String(decoding: octets[i..<(i + 4)], as: UTF8.self), radix: 16) else { throw erreur() }
            i += 4; return v
        }
        mutating func chaine() throws -> String {
            i += 1 // le guillemet ouvrant
            var tampon: [UInt8] = []
            while i < octets.count {
                let c = octets[i]
                if c == 0x22 { i += 1; return String(decoding: tampon, as: UTF8.self) }
                if c < 0x20 { throw erreur() }
                if c != 0x5C { tampon.append(c); i += 1; continue }
                i += 1
                guard i < octets.count else { throw erreur() }
                let e = octets[i]; i += 1
                switch e {
                case 0x22, 0x5C, 0x2F: tampon.append(e)
                case 0x62: tampon.append(0x08)
                case 0x66: tampon.append(0x0C)
                case 0x6E: tampon.append(0x0A)
                case 0x72: tampon.append(0x0D)
                case 0x74: tampon.append(0x09)
                case 0x75:
                    var u = try hex4()
                    if (0xD800...0xDBFF).contains(u), i + 6 <= octets.count, octets[i] == 0x5C, octets[i + 1] == 0x75 {
                        let garde = i
                        i += 2
                        let bas = try hex4()
                        if (0xDC00...0xDFFF).contains(bas) { u = 0x10000 + ((u - 0xD800) << 10) + (bas - 0xDC00) } else { i = garde }
                    }
                    tampon.append(contentsOf: Array(String(Unicode.Scalar(u).map(Character.init) ?? "\u{FFFD}").utf8))
                default: throw erreur()
                }
            }
            throw erreur()
        }
    }

    // MARK: écriture

    /// Le texte, indenté de deux espaces comme `JSON.stringify(x, null, 2)`.
    public func texteIndente(_ retrait: String = "") -> String {
        switch self {
        case .objet(let m):
            if m.isEmpty { return "{}" }
            let r = retrait + "  "
            return "{\n" + m.map { r + Self.citer($0.cle) + ": " + $0.valeur.texteIndente(r) }.joined(separator: ",\n") + "\n" + retrait + "}"
        case .tableau(let t):
            if t.isEmpty { return "[]" }
            let r = retrait + "  "
            return "[\n" + t.map { r + $0.texteIndente(r) }.joined(separator: ",\n") + "\n" + retrait + "]"
        case .chaine(let s): return Self.citer(s)
        case .nombre(let n): return n
        case .booleen(let b): return b ? "true" : "false"
        case .nul: return "null"
        }
    }

    /// Une chaîne entre guillemets, échappée comme le fait JSON.stringify (le reste, accents compris, tel quel).
    public static func citer(_ s: String) -> String {
        var r = "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": r += "\\\""
            case "\\": r += "\\\\"
            case "\u{08}": r += "\\b"
            case "\u{0C}": r += "\\f"
            case "\n": r += "\\n"
            case "\r": r += "\\r"
            case "\t": r += "\\t"
            default:
                if u.value < 0x20 { r += String(format: "\\u%04x", u.value) } else { r.unicodeScalars.append(u) }
            }
        }
        return r + "\""
    }
}

// MARK: - Les crochets dans ~/.claude/settings.json

/// Brancher Verbe sur Claude Code : nos crochets (« hooks ») ajoutés au settings.json de Claude Code, une seule fois, sans rien écraser ;
/// et retirés sans toucher à ceux des autres. Tout se fait sur le texte (fonction pure) : le système ne fait que lire et écrire le fichier.
public enum CrochetsClaude {
    /// Ce qui reconnaît nos entrées : le chemin du script, dans le dossier de Verbe.
    public static let marque = "Dictee/claude-crochet.sh"
    /// Les événements écoutés : la demande envoyée (au travail), chaque outil utilisé (la liste des tâches, et la fin d'une attente),
    /// la notification (une autorisation à donner), la fin du tour (terminé), la fin de la session.
    public static let evenements: [(nom: String, filtre: String?)] = [
        ("UserPromptSubmit", nil), ("PostToolUse", "*"), ("Notification", nil), ("Stop", nil), ("SessionEnd", nil),
    ]

    public enum Erreur: Error, Equatable {
        /// Le fichier n'est pas du JSON (on ne réécrit jamais un fichier qu'on ne comprend pas).
        case illisible
        /// Le JSON n'a pas la forme attendue (la racine ou « hooks » n'est pas un objet, un événement n'est pas une liste).
        case formeInattendue
    }

    /// La commande que Claude Code lance : le chemin du script entre apostrophes (il contient « Application Support »).
    public static func commande(script: String) -> String {
        "'" + script.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func estANous(_ crochet: JSONOrdonne) -> Bool { crochet["command"]?.texte?.contains(marque) == true }
    private static func entree(_ commande: String) -> JSONOrdonne {
        .objet([.init("type", .chaine("command")), .init("command", .chaine(commande)), .init("timeout", .nombre("5"))])
    }

    private static func racine(_ texte: String?) throws -> JSONOrdonne {
        guard let texte, !texte.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .objet([]) }
        guard let r = try? JSONOrdonne.lire(texte) else { throw Erreur.illisible }
        guard r.membres != nil else { throw Erreur.formeInattendue }
        return r
    }

    /// Le texte avec nos crochets (le même texte s'ils y sont déjà). `texte` nil ou vide : le fichier n'existe pas encore.
    public static func brancher(_ texte: String?, script: String) throws -> String {
        var r = try racine(texte)
        var crochets = r["hooks"] ?? .objet([])
        guard crochets.membres != nil else { throw Erreur.formeInattendue }
        let cmd = commande(script: script)
        var change = false
        for (nom, filtre) in evenements {
            let liste = crochets[nom] ?? .tableau([])
            guard var groupes = liste.elements else { throw Erreur.formeInattendue }
            var trouve = false
            for (gi, g) in groupes.enumerated() {
                guard var hs = g["hooks"]?.elements else { continue }
                for (hi, h) in hs.enumerated() where estANous(h) {
                    trouve = true
                    // le script a changé de place (autre compte, autre dossier) : on met le chemin à jour, rien d'autre
                    if h["command"]?.texte != cmd { var h2 = h; h2.ecrire("command", .chaine(cmd)); hs[hi] = h2; change = true }
                }
                if trouve { var g2 = g; g2.ecrire("hooks", .tableau(hs)); groupes[gi] = g2; break }
            }
            if !trouve {
                var g: [JSONOrdonne.Membre] = []
                if let filtre { g.append(.init("matcher", .chaine(filtre))) }
                g.append(.init("hooks", .tableau([entree(cmd)])))
                groupes.append(.objet(g))
                change = true
            }
            crochets.ecrire(nom, .tableau(groupes))
        }
        // déjà branché : le fichier n'est pas réécrit
        if !change, let texte { return texte }
        r.ecrire("hooks", crochets)
        return r.texteIndente() + "\n"
    }

    /// Le texte sans nos crochets : les groupes et les événements que nous avons vidés disparaissent, ceux des autres restent tels quels.
    /// Le même texte s'il n'y avait rien à nous.
    public static func debrancher(_ texte: String) throws -> String {
        var r = try racine(texte)
        guard var crochets = r["hooks"], let membres = crochets.membres else { return texte }
        var change = false
        for m in membres {
            guard let groupes = m.valeur.elements else { continue }
            var gardes: [JSONOrdonne] = []
            for g in groupes {
                guard let hs = g["hooks"]?.elements, hs.contains(where: estANous) else { gardes.append(g); continue }
                change = true
                let reste = hs.filter { !estANous($0) }
                if !reste.isEmpty { var g2 = g; g2.ecrire("hooks", .tableau(reste)); gardes.append(g2) }
            }
            if gardes.count != groupes.count || change { crochets.ecrire(m.cle, gardes.isEmpty ? nil : .tableau(gardes)) }
        }
        guard change else { return texte }
        r.ecrire("hooks", (crochets.membres ?? []).isEmpty ? nil : crochets)
        return r.texteIndente() + "\n"
    }

    /// Nos crochets sont-ils tous là ?
    public static func estBranche(_ texte: String?) -> Bool {
        guard let r = try? racine(texte), let c = r["hooks"] else { return false }
        return evenements.allSatisfy { e in
            (c[e.nom]?.elements ?? []).contains { g in (g["hooks"]?.elements ?? []).contains(where: estANous) }
        }
    }
}

// MARK: - Le script appelé par Claude Code

/// Le script que Claude Code lance à chaque événement : il ajoute une ligne horodatée au fichier de la session (`<session>.jsonl` dans
/// `dossier`). Rapide (aucune dépendance, outils du système par leur chemin), muet (Claude Code lirait sa sortie), jamais bloquant
/// (toujours 0). Il n'écrit en entier que ce dont l'îlot a besoin : la liste des tâches ; pour le reste, l'événement, l'outil, le
/// dossier et le genre de notification (jamais la demande tapée ni le contenu des fichiers).
public enum ScriptCrochet {
    /// Les outils de liste de tâches, gardés en entier (leur liste fait l'avancement).
    public static let outilsDeTaches = ["TodoWrite", "TaskCreate", "TaskUpdate"]

    public static func texte(dossier: String) -> String {
        let d = "'" + dossier.replacingOccurrences(of: "'", with: "'\\''") + "'"
        return """
        #!/bin/sh
        # Verbe : « Claude au travail » dans l'îlot. Claude Code appelle ce script à chaque événement (crochets de ~/.claude/settings.json) ;
        # il ajoute une ligne au fichier de la session, puis rend la main. Muet, sans dépendance, toujours 0.
        D=\(d)
        {
          J=$(/bin/cat | /usr/bin/tr -d '\\n\\r')
          champ() { printf '%s' "$J" | /usr/bin/grep -o "\\"$1\\"[[:space:]]*:[[:space:]]*\\"[^\\"]*\\"" | /usr/bin/head -n 1 | /usr/bin/sed -e 's/^[^:]*:[[:space:]]*"//' -e 's/"$//' | /usr/bin/tr -d '\\\\'; }
          S=$(champ session_id | /usr/bin/tr -cd 'A-Za-z0-9_-' | /usr/bin/cut -c1-100)
          if [ -n "$S" ]; then
            E=$(champ hook_event_name | /usr/bin/tr -cd 'A-Za-z')
            O=$(champ tool_name | /usr/bin/tr -cd 'A-Za-z0-9_.-')
            A=$(printf '%s' "${__CFBundleIdentifier:-}" | /usr/bin/tr -cd 'A-Za-z0-9._-')
            T=$(/bin/date +%s)
            case "$O" in
              \(outilsDeTaches.joined(separator: "|"))) L="{\\"t\\":$T,\\"app\\":\\"$A\\",\\"e\\":$J}" ;;
              *) L="{\\"t\\":$T,\\"app\\":\\"$A\\",\\"e\\":{\\"hook_event_name\\":\\"$E\\",\\"tool_name\\":\\"$O\\",\\"cwd\\":\\"$(champ cwd)\\",\\"notification_type\\":\\"$(champ notification_type | /usr/bin/tr -cd 'A-Za-z_')\\"}}" ;;
            esac
            /bin/mkdir -p "$D" && printf '%s\\n' "$L" >> "$D/$S.jsonl"
          fi
        } >/dev/null 2>&1
        exit 0

        """
    }
}

// MARK: - Les événements, les sessions

/// Une tâche de la liste de Claude (TodoWrite, TaskCreate, TaskUpdate).
public struct TacheClaude: Equatable, Sendable {
    public enum Statut: String, Sendable { case aFaire, enCours, faite }
    public var id: String
    public var sujet: String
    /// La forme « en cours » (« Écrire les contrôles »), si Claude la donne.
    public var enCours: String?
    public var statut: Statut
    public init(id: String, sujet: String, enCours: String? = nil, statut: Statut = .aFaire) {
        self.id = id; self.sujet = sujet; self.enCours = enCours; self.statut = statut
    }
    static func statut(_ s: String?) -> Statut? {
        switch s {
        case "pending": return .aFaire
        case "in_progress": return .enCours
        case "completed": return .faite
        default: return nil
        }
    }
}

/// « 3 sur 7 » : les tâches faites sur le total de la dernière liste vue.
public struct ProgresClaude: Equatable, Sendable {
    public var faites: Int
    public var total: Int
    public init(faites: Int, total: Int) { self.faites = faites; self.total = total }
    public var texte: String { "\(faites) sur \(total)" }
    /// La forme courte, quand « 12 sur 14 » ne tient pas dans l'aile.
    public var court: String { "\(faites)/\(total)" }
    public var fraction: Double { total > 0 ? Double(faites) / Double(total) : 0 }
    public var complet: Bool { total > 0 && faites >= total }
}

/// Une ligne du fichier d'une session, lue.
public struct EvenementClaude: Equatable, Sendable {
    public enum Genre: Equatable, Sendable { case invite, outil, notification, arret, fin, autre }
    /// Ce qu'un outil de tâches change à la liste.
    public enum OperationTaches: Equatable, Sendable {
        case liste([TacheClaude])
        case creer(id: String?, sujet: String, enCours: String?)
        case modifier(id: String, statut: String?, sujet: String?, enCours: String?)
    }
    public var date: Date
    public var genre: Genre
    /// Le dossier de travail (le nom du projet est son dernier élément).
    public var dossier: String?
    /// L'app d'où vient la session (identifiant du Terminal, d'iTerm…), si le script l'a eu.
    public var app: String?
    public var outil: String?
    public var taches: OperationTaches?
    public var notification: String?

    public init(date: Date, genre: Genre, dossier: String? = nil, app: String? = nil, outil: String? = nil, taches: OperationTaches? = nil, notification: String? = nil) {
        self.date = date; self.genre = genre; self.dossier = dossier; self.app = app; self.outil = outil; self.taches = taches; self.notification = notification
    }

    /// Lit une ligne `{"t": 1731312345, "app": "com.apple.Terminal", "e": { …le JSON reçu par le crochet… }}`. nil : ligne abîmée.
    public static func depuis(ligne: String) -> EvenementClaude? {
        guard let d = ligne.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let e = o["e"] as? [String: Any], let t = (o["t"] as? NSNumber)?.doubleValue else { return nil }
        func texte(_ v: Any?) -> String? { (v as? String).flatMap { $0.isEmpty ? nil : $0 } }
        let genre: Genre
        switch e["hook_event_name"] as? String {
        case "UserPromptSubmit": genre = .invite
        case "PreToolUse", "PostToolUse": genre = .outil
        case "Notification": genre = .notification
        case "Stop": genre = .arret
        case "SessionEnd": genre = .fin
        default: genre = .autre
        }
        let outil = texte(e["tool_name"])
        var ev = EvenementClaude(date: Date(timeIntervalSince1970: t), genre: genre, dossier: texte(e["cwd"]), app: texte(o["app"]), outil: outil,
                                 notification: texte(e["notification_type"]))
        if genre == .outil, let outil { ev.taches = operation(outil: outil, entree: e["tool_input"] as? [String: Any], reponse: e["tool_response"]) }
        return ev
    }

    static func operation(outil: String, entree: [String: Any]?, reponse: Any?) -> OperationTaches? {
        guard let entree else { return nil }
        func texte(_ v: Any?) -> String? {
            if let s = v as? String { return s.isEmpty ? nil : s }
            if let n = v as? NSNumber { return n.stringValue }
            return nil
        }
        switch outil {
        case "TodoWrite":
            guard let l = entree["todos"] as? [[String: Any]] else { return nil }
            return .liste(l.enumerated().compactMap { i, t in
                guard let sujet = texte(t["content"]) ?? texte(t["subject"]) else { return nil }
                return TacheClaude(id: texte(t["id"]) ?? "\(i + 1)", sujet: sujet, enCours: texte(t["activeForm"]),
                                   statut: TacheClaude.statut(t["status"] as? String) ?? .aFaire)
            })
        case "TaskCreate":
            guard let sujet = texte(entree["subject"]) ?? texte(entree["description"]) else { return nil }
            return .creer(id: idCree(reponse), sujet: sujet, enCours: texte(entree["activeForm"]))
        case "TaskUpdate":
            guard let id = texte(entree["taskId"]) ?? texte(entree["id"]) else { return nil }
            return .modifier(id: id, statut: texte(entree["status"]), sujet: texte(entree["subject"]), enCours: texte(entree["activeForm"]))
        default:
            return nil
        }
    }

    /// L'identifiant donné à une tâche créée : dans la réponse (`{"task": {"id": "3"}}`, `{"id": 3}`) ou dans son texte (« Task #3 »).
    static func idCree(_ r: Any?) -> String? {
        func id(_ v: Any?) -> String? { (v as? String) ?? (v as? NSNumber)?.stringValue }
        if let d = r as? [String: Any] {
            if let t = d["task"] as? [String: Any], let i = id(t["id"]) { return i }
            if let i = id(d["id"]) ?? id(d["taskId"]) { return i }
            for v in d.values { if let s = v as? String, let i = idCree(s) { return i } }
            return nil
        }
        if let s = r as? String, let rr = s.range(of: #"#\d+"#, options: .regularExpression) { return String(s[rr].dropFirst()) }
        return nil
    }
}

/// Ce que fait une session de Claude Code.
public enum EtatClaude: Equatable, Sendable { case travaille, attend, termine }

public struct SessionClaude: Equatable, Sendable {
    public var id: String
    public var dossier: String?
    public var app: String?
    public var etat: EtatClaude
    public var taches: [TacheClaude] = []
    /// Le dernier événement reçu.
    public var derniere: Date
    public init(id: String, dossier: String? = nil, app: String? = nil, etat: EtatClaude = .travaille, taches: [TacheClaude] = [], derniere: Date) {
        self.id = id; self.dossier = dossier; self.app = app; self.etat = etat; self.taches = taches; self.derniere = derniere
    }
    /// Le nom du projet : le dernier dossier du dossier de travail.
    public var projet: String {
        guard let d = dossier, !d.isEmpty else { return "Claude Code" }
        let n = (d as NSString).lastPathComponent
        return n.isEmpty || n == "/" ? "Claude Code" : n
    }
    public var progres: ProgresClaude? {
        taches.isEmpty ? nil : ProgresClaude(faites: taches.filter { $0.statut == .faite }.count, total: taches.count)
    }
    /// La tâche en cours (sa forme « en cours » si Claude la donne).
    public var tacheEnCours: String? { taches.first { $0.statut == .enCours }.map { $0.enCours ?? $0.sujet } }
}

/// Une annonce à faire : Claude attend une réponse, ou il a fini.
public enum AnnonceClaude: Equatable, Sendable {
    case attend(SessionClaude)
    case termine(SessionClaude)
}

/// L'état de toutes les sessions, tiré des événements dans l'ordre où ils arrivent.
public struct VeilleClaude: Equatable, Sendable {
    public private(set) var sessions: [String: SessionClaude] = [:]
    /// Une session « au travail » sans nouvelle depuis 30 min est oubliée (fenêtre du Terminal fermée sans « fin de session ») ; une
    /// session qui attend une réponse, au bout de 3 h.
    public static let oubliTravail: TimeInterval = 30 * 60
    public static let oubliAttente: TimeInterval = 3 * 3600
    public init() {}

    /// Lit un événement de la session `id`. Rend l'annonce à faire (à ignorer pendant la relecture du lancement).
    @discardableResult
    public mutating func lire(_ e: EvenementClaude, session id: String) -> AnnonceClaude? {
        // les sessions finies depuis plus d'un jour ne servent plus
        sessions = sessions.filter { $0.value.derniere > e.date.addingTimeInterval(-86_400) || $0.key == id }
        if e.genre == .fin { sessions[id] = nil; return nil }
        var s = sessions[id] ?? SessionClaude(id: id, etat: .termine, derniere: e.date)
        if let d = e.dossier { s.dossier = d }
        if let a = e.app { s.app = a }
        s.derniere = max(s.derniere, e.date)
        var annonce: AnnonceClaude?
        switch e.genre {
        case .invite:
            // une nouvelle demande : au travail ; une liste toute faite appartient à la demande d'avant
            s.etat = .travaille
            if s.progres?.complet == true { s.taches = [] }
        case .outil:
            s.etat = .travaille
            if let op = e.taches { appliquer(op, a: &s) }
        case .notification:
            // « Claude attend ta réponse » : une autorisation à donner, une question posée (ou une version sans genre de notification) ;
            // jamais le rappel d'inactivité qui suit la fin d'un tour (« waiting for your input ») ni l'avis de connexion réussie
            if Self.attenteReelle(e.notification), s.etat != .termine, s.etat != .attend {
                s.etat = .attend
                annonce = .attend(s)
            }
        case .arret:
            if s.etat != .termine { s.etat = .termine; annonce = .termine(s) }
        case .fin, .autre:
            break
        }
        sessions[id] = s
        return annonce
    }

    private func appliquer(_ op: EvenementClaude.OperationTaches, a s: inout SessionClaude) {
        switch op {
        case .liste(let l):
            s.taches = l
        case .creer(let id, let sujet, let enCours):
            let i = id ?? "\((s.taches.compactMap { Int($0.id) }.max() ?? 0) + 1)"
            if let k = s.taches.firstIndex(where: { $0.id == i }) { s.taches[k].sujet = sujet; s.taches[k].enCours = enCours }
            else { s.taches.append(TacheClaude(id: i, sujet: sujet, enCours: enCours)) }
        case .modifier(let id, let statut, let sujet, let enCours):
            guard let k = s.taches.firstIndex(where: { $0.id == id }) else { return }
            if statut == "deleted" { s.taches.remove(at: k); return }
            if let st = TacheClaude.statut(statut) { s.taches[k].statut = st }
            if let sujet { s.taches[k].sujet = sujet }
            if let enCours { s.taches[k].enCours = enCours }
        }
    }

    public mutating func oublier(session id: String) { sessions[id] = nil }

    /// Les notifications qui veulent dire « à toi » : une autorisation (permission_prompt), une question (elicitation_dialog), ou une
    /// notification sans genre (versions de Claude Code d'avant ce champ).
    public static func attenteReelle(_ genre: String?) -> Bool {
        guard let genre else { return true }
        return genre == "permission_prompt" || genre == "elicitation_dialog"
    }

    private static func vivante(_ s: SessionClaude, a t: Date) -> Bool {
        switch s.etat {
        case .travaille: return t.timeIntervalSince(s.derniere) < oubliTravail
        case .attend: return t.timeIntervalSince(s.derniere) < oubliAttente
        case .termine: return false
        }
    }

    /// La session que l'îlot montre : celle qui attend une réponse d'abord, puis celle qui travaille ; la plus récente.
    public func principale(a t: Date) -> SessionClaude? {
        sessions.values.filter { Self.vivante($0, a: t) }
            .max { a, b in
                let pa = a.etat == .attend ? 1 : 0, pb = b.etat == .attend ? 1 : 0
                return pa != pb ? pa < pb : (a.derniere, a.id) < (b.derniere, b.id)
            }
    }

    /// Quand une session montrée sera oubliée faute de nouvelles (un seul réveil, pas de minuterie qui tourne).
    public func prochainOubli(a t: Date) -> Date? {
        sessions.values.filter { Self.vivante($0, a: t) }
            .map { $0.derniere.addingTimeInterval($0.etat == .attend ? Self.oubliAttente : Self.oubliTravail) }.min()
    }

    /// L'app de terminal que Hugues regarde déjà : rien à annoncer. `app` : l'app de la session (nil si le script ne l'a pas eue : on
    /// compare alors aux terminaux connus).
    public static let terminaux: Set<String> = ["com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.mitchellh.ghostty",
                                                 "net.kovidgoyal.kitty", "com.github.wez.wezterm", "org.alacritty", "com.microsoft.VSCode"]
    public static func dejaSousLesYeux(app: String?, premierPlan: String?) -> Bool {
        guard let p = premierPlan else { return false }
        if let app { return app == p }
        return terminaux.contains(p)
    }
}
