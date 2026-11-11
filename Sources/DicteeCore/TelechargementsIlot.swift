import Foundation

// Les fichiers qui arrivent dans le dossier Téléchargements (AirDrop y dépose aussi) : lesquels annoncer, quand, et comment le dire.
// Logique pure : voir Dictee/IlotTelechargements.swift pour la surveillance du dossier.

/// Ce qu'on sait d'un élément du dossier à un instant.
public struct EntreeDossier: Equatable, Sendable {
    public var nom: String
    /// En octets (0 pour un dossier : on suit alors sa date de modification).
    public var taille: Int64
    public var modification: Date?
    public var dossier: Bool
    public init(nom: String, taille: Int64, modification: Date? = nil, dossier: Bool = false) {
        self.nom = nom; self.taille = taille; self.modification = modification; self.dossier = dossier
    }
}

/// Quels noms sont des fichiers finis : ni caché, ni téléchargement en cours (Chrome, Safari, Firefox, Opera, Edge, outils divers).
public enum FiltreTelechargements {
    public static let extensionsEnCours: Set<String> = ["crdownload", "download", "part", "partial", "tmp", "temp", "opdownload",
                                                         "downloading", "!ut", "aria2", "filepart", "crswap"]

    public static func extensionDe(_ nom: String) -> String {
        guard let i = nom.lastIndex(of: "."), i != nom.startIndex else { return "" }
        return String(nom[nom.index(after: i)...]).lowercased()
    }
    /// Faux pour « .DS_Store », « Contrat.pdf.crdownload », « Film.mp4.download », « ~$Devis.docx » (verrou de Word)…
    public static func estFini(_ nom: String) -> Bool {
        let n = nom.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, !n.hasPrefix("."), !n.hasPrefix("~$") else { return false }
        return !extensionsEnCours.contains(extensionDe(n))
    }
    /// Le fichier final qu'un téléchargement en cours deviendra : « Contrat.pdf.part » → « Contrat.pdf » (Firefox pose ce fichier final,
    /// vide, pendant tout le téléchargement).
    public static func cible(deEnCours nom: String) -> String? {
        guard extensionsEnCours.contains(extensionDe(nom)), let i = nom.lastIndex(of: ".") else { return nil }
        let base = String(nom[..<i])
        return base.isEmpty ? nil : base
    }
}

/// La taille comme le Finder la dit, en français : « 512 octets », « 850 Ko », « 2,4 Mo », « 1,2 Go » (unités de 1 000, comme le Finder).
public enum FormatTaille {
    public static func texte(_ octets: Int64) -> String {
        let n = max(0, octets), esp = "\u{00A0}"
        if n < 1000 { return "\(n)\(esp)octet" + (n > 1 ? "s" : "") }
        let ko = (Double(n) / 1000).rounded()
        if ko < 1000 { return "\(Int(ko))\(esp)Ko" }
        let mo = (Double(n) / 100_000).rounded() / 10
        if mo < 1000 { return decimal(mo) + "\(esp)Mo" }
        return decimal((Double(n) / 100_000_000).rounded() / 10) + "\(esp)Go"
    }
    /// « 2,4 », « 2 » (jamais « 2,0 »).
    static func decimal(_ v: Double) -> String {
        let dixiemes = Int((v * 10).rounded())
        return dixiemes % 10 == 0 ? "\(dixiemes / 10)" : "\(dixiemes / 10),\(dixiemes % 10)"
    }
}

/// Repère les fichiers qui viennent d'arriver et sont FINIS (taille stable depuis `stabilite`). Rien n'est annoncé pour ce qui existait
/// au lancement. On ne relit la taille que des noms nouveaux ou encore en attente : un dossier de mille fichiers ne coûte que ses noms.
public struct VeilleTelechargements {
    /// Ce qui est déjà connu (annoncé, ou là au lancement), avec sa taille quand on l'a vu : un fichier vide qui se remplit plus tard
    /// (le fichier final que Firefox pose d'avance) redevient un candidat.
    public private(set) var connus: [String: Int64]
    /// Les nouveaux venus qu'on regarde se stabiliser : leur dernière mesure et depuis quand elle n'a pas bougé.
    public private(set) var candidats: [String: (entree: EntreeDossier, depuis: Date, premier: Date)] = [:]
    public static let stabilite: TimeInterval = 1
    /// Un candidat qui grossit encore au bout d'une demi-heure n'est plus suivi (aucune relecture sans fin).
    public static let abandon: TimeInterval = 1800

    public init(existants: [EntreeDossier]) {
        connus = Dictionary(existants.map { ($0.nom, Self.cle($0)) }, uniquingKeysWith: { a, _ in a })
    }

    /// Relit le dossier (`noms`) ; `mesure` donne la taille et la date d'un nom (nil : il a disparu entre-temps). Rend les fichiers finis
    /// à annoncer maintenant.
    public mutating func lire(noms: [String], a t: Date, mesure: (String) -> EntreeDossier?) -> [EntreeDossier] {
        let presents = Set(noms)
        // ce qui a disparu est oublié : un fichier supprimé puis retéléchargé sous le même nom s'annonce de nouveau
        for n in connus.keys where !presents.contains(n) { connus[n] = nil }
        for n in candidats.keys where !presents.contains(n) { candidats[n] = nil }
        let enCours = Set(noms.compactMap(FiltreTelechargements.cible(deEnCours:)))
        var prets: [EntreeDossier] = []
        for n in noms where FiltreTelechargements.estFini(n) {
            // connu (et pas vide) : rien à relire ; connu vide : rien tant qu'un téléchargement en cours va le remplacer
            if let taille = connus[n], taille != 0 || enCours.contains(n) { continue }
            guard let e = mesure(n) else { continue }
            if connus[n] != nil {
                if e.taille == 0 || e.dossier { continue }
                connus[n] = nil
            }
            if e.taille == 0, !e.dossier { connus[n] = 0; candidats[n] = nil; continue }
            if let c = candidats[n] {
                if c.entree == e {
                    if t.timeIntervalSince(c.depuis) >= Self.stabilite - 0.02 { prets.append(e); connus[n] = Self.cle(e); candidats[n] = nil }
                } else if t.timeIntervalSince(c.premier) > Self.abandon {
                    connus[n] = Self.cle(e); candidats[n] = nil
                } else {
                    candidats[n] = (e, t, c.premier)
                }
            } else {
                candidats[n] = (e, t, t)
            }
        }
        return prets.sorted { $0.nom.localizedStandardCompare($1.nom) == .orderedAscending }
    }

    /// La valeur gardée pour un nom connu : sa taille, ou -1 pour un dossier (jamais relu).
    static func cle(_ e: EntreeDossier) -> Int64 { e.dossier ? -1 : e.taille }

    /// Quand relire le dossier (le premier candidat qui aura été stable assez longtemps) ; nil : rien n'attend, aucun réveil.
    public var prochaineRelecture: Date? {
        candidats.values.map { $0.depuis.addingTimeInterval(Self.stabilite) }.min()
    }
}

/// Un fichier arrivé, prêt à annoncer.
public struct FichierTelecharge: Equatable, Sendable {
    public var url: URL
    /// nil pour un dossier.
    public var taille: Int64?
    /// Reçu par AirDrop (attribut de quarantaine posé par sharingd).
    public var airdrop: Bool
    public init(url: URL, taille: Int64?, airdrop: Bool = false) { self.url = url; self.taille = taille; self.airdrop = airdrop }
    public var nom: String { url.lastPathComponent }

    /// L'agent qui a posé l'attribut de quarantaine (« 0081;6731f2a0;sharingd;… » → « sharingd ») : sharingd = AirDrop.
    public static func estAirDrop(quarantaine: String?) -> Bool {
        guard let q = quarantaine else { return false }
        let p = q.split(separator: ";", omittingEmptySubsequences: false)
        return p.count >= 3 && p[2].trimmingCharacters(in: .whitespaces).lowercased() == "sharingd"
    }
}

/// Les fichiers arrivés en rafale (moins de `fenetre` secondes entre deux) ne font qu'un bandeau : « 3 fichiers téléchargés ».
public struct RafaleTelechargements: Equatable, Sendable {
    public private(set) var fichiers: [FichierTelecharge] = []
    public private(set) var derniere: Date?
    /// Le bandeau reste 4 s ; un fichier qui arrive pendant ce temps le rejoint (et le prolonge).
    public static let fenetre: TimeInterval = 4
    public init() {}

    /// Vrai si la rafale continue (le bandeau déjà là se met à jour), faux si c'est une nouvelle rafale.
    @discardableResult
    public mutating func ajouter(_ nouveaux: [FichierTelecharge], a t: Date) -> Bool {
        guard !nouveaux.isEmpty else { return false }
        let suite = derniere.map { t.timeIntervalSince($0) <= Self.fenetre } ?? false
        if suite {
            for f in nouveaux where !fichiers.contains(where: { $0.url == f.url }) { fichiers.append(f) }
        } else { fichiers = nouveaux }
        derniere = t
        return suite
    }

    private var tousAirDrop: Bool { !fichiers.isEmpty && fichiers.allSatisfy(\.airdrop) }
    private var tailleTotale: Int64? {
        let t = fichiers.compactMap(\.taille)
        return t.isEmpty ? nil : t.reduce(0, +)
    }
    /// « Contrat-signé.pdf » ; « 3 fichiers téléchargés » ; « 2 fichiers reçus » (AirDrop).
    public var titre: String {
        guard fichiers.count > 1 else { return fichiers.first?.nom ?? "" }
        return "\(fichiers.count) fichiers " + (tousAirDrop ? "reçus" : "téléchargés")
    }
    /// « Téléchargé · 2,4 Mo » ; « Reçu par AirDrop · 2,4 Mo » ; plusieurs : « Dans Téléchargements · 3,1 Mo », « Par AirDrop · 3,1 Mo ».
    public var sousTitre: String {
        let taille = tailleTotale.map { " \u{00B7} " + FormatTaille.texte($0) } ?? ""
        if fichiers.count > 1 { return (tousAirDrop ? "Par AirDrop" : "Dans Téléchargements") + taille }
        return (tousAirDrop ? "Reçu par AirDrop" : "Téléchargé") + taille
    }
}
