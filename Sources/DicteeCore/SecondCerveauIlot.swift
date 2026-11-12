import Foundation

// La case « Second Brain » de l'îlot (maquette design/maquettes/ilot-second-cerveau.html) : logique pure, sans interface.
// Second Brain est une autre app locale de Hugues (messages reçus, choses « à toi », personnes à relancer). Elle dépose un petit fichier
// d'état, ~/.config/second-cerveau/ilot.json ; l'îlot ne fait que le LIRE : il ne coche rien, n'écrit rien, n'envoie rien. Le contrat
// du fichier est dans docs/second-cerveau-ilot.md.
// Ce fichier contient des données personnelles : rien de ce qu'il dit n'est écrit dans le journal ni dans les rendus.

/// Ce que l'îlot sait montrer du fichier d'état de Second Brain. Le décodage est TOLÉRANT : chaque champ est optionnel, un champ du
/// mauvais type est ignoré (jamais le fichier entier), les tableaux sont bornés, les textes tronqués proprement. Un fichier absent,
/// illisible, qui n'est pas un objet JSON ou de plus de 64 Ko ne donne rien (`nil`) : la case n'existe pas.
public struct SecondCerveauIlot: Equatable, Sendable {
    // MARK: les bornes
    /// Au-delà, le fichier est refusé (une app qui s'emballe ne remplit pas la mémoire de l'îlot).
    public static let tailleMax = 64 * 1024
    /// Trois lignes au plus par partie dans le fichier gardé ; la carte en montre ce qui tient dans la hauteur du Centre (sept au plus).
    public static let lignesParPartie = 3
    /// Les longueurs gardées (en caractères) : au-delà, le texte finit par « … ».
    public static let longueurNom = 28, longueurTexte = 96, longueurResume = 80, longueurCourte = 16, longueurDate = 40, longueurLien = 1024

    /// Le nom montré (l'app s'appelait « Second cerveau », elle est devenue « Second Brain »).
    public static let nomApp = "Second Brain"
    /// Les identifiants de l'app, du plus récent au plus ancien : on cherche le premier qui est installé.
    /// (Le nom affiché est « Second Brain » ; l'identifiant reste `com.hugues.second-cerveau`, l'autre est gardé au cas où.)
    public static let identifiantsApp = ["com.hugues.second-cerveau", "com.hugues.second-brain"]
    /// Le seul schéma d'URL que l'îlot ouvre (avec un chemin de fichier existant) : un fichier piégé ne peut pas ouvrir n'importe quoi.
    public static let schemaLien = "secondbrain"

    // MARK: ce qui est lu
    public struct Compteurs: Equatable, Sendable {
        public var nouveautes: Int?, aToi: Int?, aRelancer: Int?
        public init(nouveautes: Int? = nil, aToi: Int? = nil, aRelancer: Int? = nil) { self.nouveautes = nouveautes; self.aToi = aToi; self.aRelancer = aRelancer }
    }
    public struct Message: Equatable, Sendable {
        public var id: String, nom: String?, texte: String?, heure: String?, resume: String?, lien: String?
        public init(id: String, nom: String? = nil, texte: String? = nil, heure: String? = nil, resume: String? = nil, lien: String? = nil) {
            self.id = id; self.nom = nom; self.texte = texte; self.heure = heure; self.resume = resume; self.lien = lien
        }
    }
    public struct Tache: Equatable, Sendable {
        public var id: String, texte: String, echeance: String?, lien: String?
        public init(id: String, texte: String, echeance: String? = nil, lien: String? = nil) { self.id = id; self.texte = texte; self.echeance = echeance; self.lien = lien }
    }
    public struct Relance: Equatable, Sendable {
        public var id: String, nom: String?, sujet: String?, depuis: String?, lien: String?
        public init(id: String, nom: String? = nil, sujet: String? = nil, depuis: String? = nil, lien: String? = nil) {
            self.id = id; self.nom = nom; self.sujet = sujet; self.depuis = depuis; self.lien = lien
        }
    }

    public var maj: Date?
    public var resume: String?
    public var compteurs: Compteurs
    public var messages: [Message]
    public var taches: [Tache]
    public var relances: [Relance]
    public var lien: String?

    public init(maj: Date? = nil, resume: String? = nil, compteurs: Compteurs = Compteurs(), messages: [Message] = [], taches: [Tache] = [],
                relances: [Relance] = [], lien: String? = nil) {
        self.maj = maj; self.resume = resume; self.compteurs = compteurs
        self.messages = messages; self.taches = taches; self.relances = relances; self.lien = lien
    }

    // MARK: le décodage

    /// Lit le contenu du fichier. nil : pas de case (rien lu, trop gros, pas du JSON, pas un objet).
    public static func decoder(_ donnees: Data?) -> SecondCerveauIlot? {
        guard let donnees, !donnees.isEmpty, donnees.count <= tailleMax,
              let racine = (try? JSONSerialization.jsonObject(with: donnees)) as? [String: Any] else { return nil }
        func lignes<T>(_ cle: String, _ fabrique: ([String: Any], String) -> T?) -> [T] {
            guard let tab = racine[cle] as? [Any] else { return [] }
            var r: [T] = []
            // on lit au plus quelques dizaines d'entrées pour en garder trois valides : un tableau de 10 000 lignes ne coûte rien
            for (i, brut) in tab.prefix(40).enumerated() {
                guard r.count < lignesParPartie, let d = brut as? [String: Any], let l = fabrique(d, identifiant(d["id"], repli: "\(cle)-\(i)")) else { continue }
                r.append(l)
            }
            return r
        }
        let c = racine["compteurs"] as? [String: Any]
        return SecondCerveauIlot(
            maj: (racine["maj"] as? String).flatMap(date),
            resume: net(racine["resume"], longueurResume),
            compteurs: Compteurs(nouveautes: entier(c?["nouveautes"]), aToi: entier(c?["aToi"]), aRelancer: entier(c?["aRelancer"])),
            messages: lignes("messages") { d, id in
                let nom = net(d["nom"], longueurNom), texte = net(d["texte"], longueurTexte)
                guard nom != nil || texte != nil else { return nil }
                return Message(id: id, nom: nom, texte: texte, heure: net(d["heure"], longueurDate), resume: net(d["resume"], longueurResume), lien: lienBrut(d["lien"]))
            },
            taches: lignes("taches") { d, id in
                guard let texte = net(d["texte"], longueurTexte) else { return nil }
                return Tache(id: id, texte: texte, echeance: net(d["echeance"], longueurDate), lien: lienBrut(d["lien"]))
            },
            relances: lignes("relances") { d, id in
                let nom = net(d["nom"], longueurNom), sujet = net(d["sujet"], longueurTexte)
                guard nom != nil || sujet != nil else { return nil }
                return Relance(id: id, nom: nom, sujet: sujet, depuis: net(d["depuis"], longueurDate), lien: lienBrut(d["lien"]))
            },
            lien: lienBrut(racine["lien"]))
    }

    /// Un texte du fichier, prêt à être montré : sur une ligne, sans caractère de contrôle ni espace en trop, tronqué proprement (à la
    /// fin d'un mot quand c'est possible) avec « … ». nil : vide ou pas du texte.
    public static func net(_ valeur: Any?, _ max: Int) -> String? {
        guard let s = valeur as? String else { return nil }
        var propre = ""
        propre.reserveCapacity(min(s.count, max * 2))
        var espace = true   // pas d'espace en tête
        for u in s.unicodeScalars.prefix(max * 4 + 8) {
            let blanc = u.properties.isWhitespace
            if blanc { if !espace { propre.unicodeScalars.append(" "); espace = true }; continue }
            if u.properties.generalCategory == .control || u.properties.generalCategory == .format { continue }
            propre.unicodeScalars.append(u); espace = false
        }
        while propre.last == " " { propre.removeLast() }
        guard !propre.isEmpty else { return nil }
        return tronquer(propre, max)
    }

    /// Coupe à `max` caractères au plus (le « … » compris), à la fin d'un mot si l'espace est assez loin.
    public static func tronquer(_ s: String, _ max: Int) -> String {
        guard s.count > max, max > 1 else { return s.count > max ? String(s.prefix(max)) : s }
        var tete = String(s.prefix(max - 1))
        if let e = tete.lastIndex(of: " "), tete.distance(from: tete.startIndex, to: e) >= (max - 1) * 3 / 5 { tete = String(tete[..<e]) }
        while let d = tete.last, " ,;:.-–—".contains(d) { tete.removeLast() }
        return tete + "\u{2026}"
    }

    private static func identifiant(_ v: Any?, repli: String) -> String { net(v, 64) ?? repli }
    private static func lienBrut(_ v: Any?) -> String? {
        guard let s = v as? String else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty || t.count > longueurLien ? nil : t
    }
    /// Un nombre entier du fichier (un nombre JSON, pas un booléen ni un texte), entre 0 et 9 999.
    private static func entier(_ v: Any?) -> Int? {
        guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        let d = n.doubleValue
        guard d.isFinite else { return nil }
        return Int(min(9999, max(0, d.rounded(.down))))
    }
    /// « 2026-11-12T09:15:00+01:00 » (avec ou sans fractions de seconde) ; sans fuseau, l'heure du Mac.
    public static func date(_ s: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f.date(from: s)
    }

    // MARK: ce qu'on montre

    /// Les nombres du fichier, ou, à défaut, le nombre de lignes gardées.
    public var nouveautes: Int { compteurs.nouveautes ?? messages.count }
    public var aToi: Int { compteurs.aToi ?? taches.count }
    public var aRelancer: Int { compteurs.aRelancer ?? relances.count }

    /// L'état écrit sous le bouton du Centre : ce qui compte le plus d'abord (« 3 nouveautés », « 5 à toi », « 2 à relancer »), sinon « À jour ».
    public var etat: String {
        if nouveautes > 0 { return nouveautes == 1 ? "1 nouveauté" : "\(Self.nombre(nouveautes)) nouveautés" }
        if aToi > 0 { return "\(Self.nombre(aToi)) à toi" }
        if aRelancer > 0 { return "\(Self.nombre(aRelancer)) à relancer" }
        return "À jour"
    }
    /// 1 000 et plus : « 999+ » (jamais plus large que le bouton).
    public static func nombre(_ n: Int) -> String { n > 999 ? "999+" : "\(n)" }

    /// Rien de neuf nulle part (la carte dit « Rien de neuf pour l'instant »).
    public var vide: Bool { messages.isEmpty && taches.isEmpty && relances.isEmpty }

    /// Ce que la carte montre : au plus trois lignes par partie, et ce qui tient dans la hauteur du Centre (`MesuresSecondBrain.corpsMax` :
    /// sept lignes au plus). Quand il y en a trop, la partie la plus remplie perd une ligne (la dernière en cas d'égalité), jusqu'à tenir :
    /// 3 + 3 + 3 devient 3 + 2 + 2.
    public struct Affichage: Equatable, Sendable {
        public var messages: [Message], taches: [Tache], relances: [Relance]
        public var lignes: Int { messages.count + taches.count + relances.count }
        public init(messages: [Message] = [], taches: [Tache] = [], relances: [Relance] = []) { self.messages = messages; self.taches = taches; self.relances = relances }
    }
    public var affichage: Affichage {
        var n = [messages.count, taches.count, relances.count].map { min($0, Self.lignesParPartie) }
        while MesuresSecondBrain.corps(lignes: n) > MesuresSecondBrain.corpsMax {
            let plus = n.max() ?? 0
            if let i = n.lastIndex(of: plus) { n[i] -= 1 }
        }
        return Affichage(messages: Array(messages.prefix(n[0])), taches: Array(taches.prefix(n[1])), relances: Array(relances.prefix(n[2])))
    }

    /// Les trois titres de la carte et ce qu'ils disent en dessous (« 2 à lire », « 3 sur 14 », « 2 personnes »). nil : la partie n'est pas montrée.
    public func titreMessages(_ a: Affichage) -> (titre: String, sous: String)? {
        a.messages.isEmpty ? nil : ("Messages", nouveautes > 0 ? "\(Self.nombre(nouveautes)) à lire" : "")
    }
    public func titreTaches(_ a: Affichage) -> (titre: String, sous: String)? {
        guard !a.taches.isEmpty else { return nil }
        return ("À toi", aToi > a.taches.count ? "\(a.taches.count) sur \(Self.nombre(aToi))" : "\(Self.nombre(max(aToi, a.taches.count))) à faire")
    }
    public func titreRelances(_ a: Affichage) -> (titre: String, sous: String)? {
        guard !a.relances.isEmpty else { return nil }
        let n = max(aRelancer, a.relances.count)
        return ("À relancer", n == 1 ? "1 personne" : "\(Self.nombre(n)) personnes")
    }

    /// Une relance de longtemps (30 jours ou plus, ou « mois ») s'écrit en ambre.
    public static func relanceAncienne(_ depuis: String?) -> Bool {
        guard let d = depuis?.lowercased() else { return false }
        let n = Int(d.prefix { $0.isNumber }) ?? 0
        if d.contains("mois") || d.contains("ans") { return true }
        if d.contains("sem") { return n >= 4 }
        return d.contains("jour") && n >= 30
    }

    // MARK: la fraîcheur

    /// « il y a 2 min », « il y a 3 h », puis « mis à jour hier » (24 à 48 h) ; plus ancien, ou sans date : rien. Écrit seulement à
    /// l'ouverture de la carte (aucune minuterie).
    public func fraicheur(maintenant: Date) -> String? {
        guard let maj else { return nil }
        let s = maintenant.timeIntervalSince(maj)
        if s < 60 { return "à l\u{2019}instant" }          // y compris une horloge un peu en avance
        if s < 3600 { return "il y a \(Int(s / 60)) min" }
        if s < 86_400 { return "il y a \(Int(s / 3600)) h" }
        if s < 172_800 { return "mis à jour hier" }
        return nil
    }

    // MARK: ouvrir

    /// Où mène un lien du fichier. On n'ouvre que le schéma `secondbrain` ou un chemin de fichier qui existe (et qui est un document, ou
    /// un dossier), jamais autre chose (https, file:// vers un programme…).
    public struct Existence: Sendable {
        public var existe: Bool, dossier: Bool
        public init(existe: Bool, dossier: Bool = false) { self.existe = existe; self.dossier = dossier }
    }
    /// Les documents qu'un chemin de fichier peut désigner (une fiche de Second Brain est un texte).
    public static let extensionsOuvrables: Set<String> = ["md", "markdown", "txt", "rtf", "pdf", "html", "htm", "csv", "json", "png", "jpg", "jpeg", "heic"]

    public static func lienValide(_ brut: String?, existence: (String) -> Existence) -> URL? {
        guard let brut, !brut.isEmpty, brut.count <= longueurLien, !brut.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) else { return nil }
        // un schéma d'URL : seul secondbrain:// passe
        if let deuxPoints = brut.firstIndex(of: ":"), !brut.hasPrefix("/"), !brut.hasPrefix("~") {
            let schema = brut[..<deuxPoints].lowercased()
            if schema == schemaLien {
                let url = URL(string: brut) ?? brut.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed.union(.urlPathAllowed).union(CharacterSet(charactersIn: "%#"))).flatMap(URL.init(string:))
                guard let url, url.scheme?.lowercased() == schemaLien else { return nil }
                return url
            }
            if schema != "file" { return nil }
        }
        // un chemin de fichier (absolu, ~/…, ou file://…) qui existe
        var chemin = brut
        if chemin.lowercased().hasPrefix("file://") {
            guard let u = URL(string: chemin), u.isFileURL else { return nil }
            chemin = u.path
        }
        chemin = (chemin as NSString).expandingTildeInPath
        guard chemin.hasPrefix("/") else { return nil }
        chemin = (chemin as NSString).standardizingPath
        let e = existence(chemin)
        guard e.existe else { return nil }
        let ext = (chemin as NSString).pathExtension.lowercased()
        // un dossier ordinaire seulement (jamais un .app ni un paquet : l'ouvrir lancerait un programme) ; un fichier : un document
        if e.dossier { guard ext.isEmpty else { return nil } } else { guard extensionsOuvrables.contains(ext) else { return nil } }
        return URL(fileURLWithPath: chemin, isDirectory: e.dossier)
    }

    /// Où mène un clic sans lien : « Aujourd'hui » de l'app.
    public static let lienAccueil = URL(string: "secondbrain://aujourdhui")!

    /// Ce qu'un clic ouvre : le lien de la ligne, sinon le lien général, sinon l'accueil de l'app (`secondbrain://aujourdhui`) si une app
    /// sait l'ouvrir (`gestionnaire`), sinon l'app elle-même si elle est installée (`appInstallee` reçoit ses identifiants), sinon rien.
    public func aOuvrir(lienDeLaLigne: String?, existence: (String) -> Existence, gestionnaire: (URL) -> URL?, appInstallee: ([String]) -> URL?) -> URL? {
        Self.lienValide(lienDeLaLigne, existence: existence) ?? Self.lienValide(lien, existence: existence)
            ?? (gestionnaire(Self.lienAccueil) != nil ? Self.lienAccueil : appInstallee(Self.identifiantsApp))
    }
}

// MARK: - les dates, en français simple

/// Les dates du fichier (`echeance`, `depuis`, `heure`) sont des dates machine (« 2026-11-14 », une ISO avec fuseau) ou null ; l'îlot les
/// écrit en français simple, au moment où la carte s'ouvre (jamais de minuterie). Un texte qui n'est pas une date (« samedi », « 22 jours »,
/// premier contrat) est gardé tel quel.
public enum DateSecondCerveau {
    public struct Texte: Equatable, Sendable {
        public var texte: String
        /// À signaler en ambre : une échéance dépassée, une relance de 30 jours ou plus.
        public var alerte: Bool
        public init(_ texte: String, alerte: Bool = false) { self.texte = texte; self.alerte = alerte }
    }
    static let jours = ["dimanche", "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi"]   // Calendar : 1 = dimanche
    static let mois = ["janv.", "févr.", "mars", "avr.", "mai", "juin", "juil.", "août", "sept.", "oct.", "nov.", "déc."]

    /// « AAAA-MM-JJ » (ou le jour d'une ISO avec fuseau) : le début de ce jour dans `calendrier`. nil : pas une date.
    public static func jour(_ s: String, calendrier: Calendar) -> Date? {
        let p = s.split(separator: "-", omittingEmptySubsequences: false)
        if p.count == 3, p[0].count == 4, p[1].count == 2, p[2].count == 2, let a = Int(p[0]), let m = Int(p[1]), let j = Int(p[2]),
           let d = calendrier.date(from: DateComponents(year: a, month: m, day: j)) {
            let c = calendrier.dateComponents([.year, .month, .day], from: d)
            return c.year == a && c.month == m && c.day == j ? d : nil   // 2026-02-31 n'est pas une date
        }
        if s.count >= 19, s.contains("T"), let d = SecondCerveauIlot.date(s) { return calendrier.startOfDay(for: d) }
        return nil
    }
    /// Combien de jours entiers de `maintenant` à `jour` (négatif : passé).
    static func ecart(_ jour: Date, maintenant: Date, calendrier: Calendar) -> Int {
        calendrier.dateComponents([.day], from: calendrier.startOfDay(for: maintenant), to: jour).day ?? 0
    }

    /// « aujourd'hui », « demain », « samedi » (dans la semaine), « le 20 » (ce mois-ci), « 3 déc. », « en retard » (passée).
    public static func echeance(_ brut: String?, maintenant: Date, calendrier: Calendar = .current) -> Texte? {
        guard let brut, !brut.isEmpty else { return nil }
        guard let j = jour(brut, calendrier: calendrier) else { return Texte(SecondCerveauIlot.tronquer(brut, SecondCerveauIlot.longueurCourte)) }
        let n = ecart(j, maintenant: maintenant, calendrier: calendrier)
        if n < 0 { return Texte("en retard", alerte: true) }
        if n == 0 { return Texte("aujourd\u{2019}hui") }
        if n == 1 { return Texte("demain") }
        if n < 7 { return Texte(jours[calendrier.component(.weekday, from: j) - 1]) }
        let c = calendrier.dateComponents([.year, .month, .day], from: j), a = calendrier.dateComponents([.year, .month], from: maintenant)
        let jourDuMois = c.day == 1 ? "1er" : "\(c.day ?? 0)"
        if c.year == a.year, c.month == a.month { return Texte("le \(jourDuMois)") }
        let m = mois[(c.month ?? 1) - 1]
        return Texte(c.year == a.year ? "le \(jourDuMois) \(m)" : "\(jourDuMois) \(m) \(c.year ?? 0)")
    }

    /// « depuis 22 jours » ; hier, aujourd'hui ; « depuis 2 mois » à partir de 60 jours, « depuis 2 ans » à partir de 24 mois. Ambre dès 30 jours.
    public static func depuis(_ brut: String?, maintenant: Date, calendrier: Calendar = .current) -> Texte? {
        guard let brut, !brut.isEmpty else { return nil }
        guard let j = jour(brut, calendrier: calendrier) else { return Texte(SecondCerveauIlot.tronquer(brut, SecondCerveauIlot.longueurCourte), alerte: SecondCerveauIlot.relanceAncienne(brut)) }
        let n = -ecart(j, maintenant: maintenant, calendrier: calendrier)
        if n <= 0 { return Texte("aujourd\u{2019}hui") }
        if n == 1 { return Texte("depuis hier") }
        if n < 60 { return Texte("depuis \(n) jours", alerte: n >= 30) }
        if n < 730 { return Texte("depuis \(n / 30) mois", alerte: true) }
        return Texte("depuis \(n / 365) ans", alerte: true)
    }

    /// « 9:12 » (l'heure du Mac) pour une ISO avec fuseau ; un texte qui n'en est pas une est gardé tel quel (8 caractères au plus).
    public static func heure(_ brut: String?, calendrier: Calendar = .current) -> String? {
        guard let brut, !brut.isEmpty else { return nil }
        guard let d = SecondCerveauIlot.date(brut) else { return SecondCerveauIlot.tronquer(brut, 8) }
        let c = calendrier.dateComponents([.hour, .minute], from: d)
        return String(format: "%d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}

// MARK: - la place de la carte

/// La hauteur de la carte « Second Brain » (en points, depuis le haut sous la barre) : 14 de marge, l'en-tête (26), 8, les parties
/// (une ligne = 24 pt, 4 pt au-dessus et au-dessous, au moins la place du titre ; un filet de 1 pt entre deux), le pied (42), 14.
/// Avec sept lignes au plus, elle tient dans la hauteur du Centre (298 pt) : elle ne le dépasse jamais.
public enum MesuresSecondBrain {
    public static let haut: Double = 14, entete: Double = 26, ecartEntete: Double = 8, pied: Double = 42, bas: Double = 14
    public static let ligne: Double = 24, marge: Double = 4, vide: Double = 44
    /// Une partie : ses lignes, ou la place de son titre (le mot, et dessous « 2 à lire » : 35 pt) s'il y en a moins de deux.
    public static func hautPartie(_ n: Int) -> Double { 2 * marge + max(35, ligne * Double(n)) }
    /// Ce que le corps peut prendre au plus : la hauteur du Centre moins l'en-tête, le pied et les marges.
    public static let corpsMax: Double = GeoIlot.profondeurCentre - haut - entete - ecartEntete - pied - bas
    /// `lignes` : le nombre de lignes de chaque partie (une partie vide n'est pas montrée).
    public static func corps(lignes: [Int]) -> Double {
        let p = lignes.filter { $0 > 0 }
        return p.isEmpty ? vide : p.map(hautPartie).reduce(0, +) + Double(p.count - 1)
    }
    public static func profondeur(_ a: SecondCerveauIlot.Affichage) -> Double {
        min(GeoIlot.profondeurCentre, haut + entete + ecartEntete + corps(lignes: [a.messages.count, a.taches.count, a.relances.count]) + pied + bas)
    }
}

// MARK: - le fichier et son dossier

/// Où est le fichier d'état, et comment on le lit : au plus 64 Ko, un vrai fichier (pas un dossier, pas un tube).
public enum FichierSecondCerveau {
    /// ~/.config/second-cerveau/ilot.json
    public static func dossierParDefaut() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/second-cerveau", isDirectory: true)
    }
    public static let nom = "ilot.json"

    /// Le contenu du fichier, ou nil (absent, illisible, ce n'est pas un fichier, plus de 64 Ko). Aucune erreur remontée : la case est cachée.
    public static func lire(_ url: URL) -> Data? {
        let fd = open(url.path, O_RDONLY | O_NONBLOCK)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG, st.st_size <= off_t(SecondCerveauIlot.tailleMax) else { return nil }
        let h = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        guard let d = try? h.read(upToCount: SecondCerveauIlot.tailleMax + 1), d.count <= SecondCerveauIlot.tailleMax else { return nil }
        return d
    }

    /// Le plus proche dossier qui existe, du dossier voulu vers le haut : on y surveille l'apparition du suivant.
    public static func ancetreExistant(_ dossier: URL, existe: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> URL {
        var u = dossier
        while u.path != "/", !existe(u.path) { u = u.deletingLastPathComponent() }
        return u
    }
}
