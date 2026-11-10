import Foundation

/// Un rendez-vous lu dans les calendriers du Mac (EventKit : tout ce que Calendrier affiche, Google compris si le compte y est ajouté).
/// Rien n'est gardé : Verbe relit les prochaines heures, il n'enregistre aucun rendez-vous.
public struct EvenementAgenda: Equatable, Identifiable, Sendable {
    public var id: String
    public var titre: String
    public var debut: Date
    public var fin: Date
    public var lieu: String?
    public var lien: URL?
    public var toutelaJournee: Bool
    public init(id: String, titre: String, debut: Date, fin: Date, lieu: String? = nil, lien: URL? = nil, toutelaJournee: Bool = false) {
        self.id = id; self.titre = titre; self.debut = debut; self.fin = fin; self.lieu = lieu; self.lien = lien; self.toutelaJournee = toutelaJournee
    }
}

/// Le lien de visioconférence d'un rendez-vous. On ne retient que des adresses https vers des services connus : jamais une adresse
/// quelconque trouvée dans le texte d'une invitation (un clic sur « Rejoindre » ouvre ce lien).
public enum LienVisio {
    static let hotes: [String] = [
        "meet.google.com", "zoom.us", "teams.microsoft.com", "teams.live.com", "whereby.com", "webex.com", "around.co",
        "facetime.apple.com", "meet.jit.si", "gotomeeting.com", "bluejeans.com", "slack.com", "discord.gg", "skype.com", "chime.aws",
    ]
    public static func estAutorise(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let hote = url.host?.lowercased() else { return false }
        return hotes.contains { hote == $0 || hote.hasSuffix("." + $0) }
    }
    /// Le premier lien autorisé trouvé dans les textes (adresse du rendez-vous, lieu, notes), dans cet ordre.
    public static func extraire(depuis textes: [String?]) -> URL? {
        for texte in textes.compactMap({ $0 }) {
            for mot in texte.split(whereSeparator: { " \n\t\r<>\"'()[]".contains($0) }) {
                var s = String(mot)
                while let dernier = s.last, ".,;:!?".contains(dernier) { s.removeLast() }
                guard s.lowercased().hasPrefix("https://"), let url = URL(string: s), estAutorise(url) else { continue }
                return url
            }
        }
        return nil
    }
    /// Le nom du service, pour « Visio » : jamais l'adresse entière si elle est longue.
    public static func nom(_ url: URL) -> String { url.host?.replacingOccurrences(of: "www.", with: "") ?? "Visio" }
}

/// Quand l'îlot parle d'un rendez-vous : 10 minutes avant (bandeau « Dans 10 min », puis compte à rebours dans l'aile), au début (alerte).
public enum PlanAgenda {
    public static let avance: Double = 600
    /// À partir de quand l'alerte « commence » est encore utile (au-delà, on ne réveille plus personne pour un rendez-vous déjà commencé).
    public static let toleranceDebut: Double = 120

    /// Le prochain rendez-vous (pas une journée entière) qui n'est pas fini.
    public static func prochain(_ evenements: [EvenementAgenda], a maintenant: Date) -> EvenementAgenda? {
        evenements.filter { !$0.toutelaJournee && $0.fin > maintenant && $0.debut > maintenant.addingTimeInterval(-toleranceDebut) }
            .min { $0.debut < $1.debut }
    }
    public enum Etape: Equatable, Sendable {
        case loin(dans: Double)        // pas encore dans la fenêtre des 10 minutes : secondes avant qu'on s'en occupe
        case avant(Double)             // dans les 10 minutes : secondes avant le début
        case debut                     // il vient de commencer
        case passe
    }
    public static func etape(_ e: EvenementAgenda, a maintenant: Date) -> Etape {
        let avantDebut = e.debut.timeIntervalSince(maintenant)
        if avantDebut > avance { return .loin(dans: avantDebut - avance) }
        if avantDebut > 0 { return .avant(avantDebut) }
        if -avantDebut <= toleranceDebut { return .debut }
        return .passe
    }
    /// « dans 10 min », « dans 1 min », « maintenant ».
    public static func dans(_ secondes: Double) -> String {
        if secondes <= 30 { return "maintenant" }
        return "dans \(max(1, Int((secondes / 60).rounded(.up)))) min"
    }
    /// « 14:42 – 15:15 ».
    public static func plage(_ e: EvenementAgenda, calendrier: Calendar = .current) -> String {
        FormatIlot.heure(e.debut, calendrier: calendrier) + " \u{2013} " + FormatIlot.heure(e.fin, calendrier: calendrier)
    }
}
