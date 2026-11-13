import Foundation

// Mail et Agenda dans « Tes apps » : les apps du Mac, sans aucune clé.
//
// Mail : on passe par l'app Mail (le compte Gmail de Hugues y est), par AppleScript, avec l'autorisation « Automatisation » de macOS.
// On ne lit que les mails NON LUS de la boîte de réception arrivés depuis peu : identifiant, expéditeur, objet, date. Jamais le contenu.
// Ce fichier écrit le script et lit sa sortie (logique pure) ; l'exécution est dans l'app (AppsSysteme.swift), jamais dans les contrôles.
//
// Agenda : Voxile lit déjà le calendrier (EventKit, IlotAgenda.swift). On réutilise ses `EvenementAgenda` et `PlanAgenda.prochain` :
// rien n'est relu deux fois, rien n'est dupliqué.

/// Un mail non lu, tel que le script le rend.
public struct MessageMail: Equatable, Sendable {
    /// Le `Message-ID` (sans chevrons) : la clé du dédoublonnage et l'adresse `message://` qui l'ouvre dans Mail.
    public var id: String
    public var expediteur: String
    public var objet: String
    public var recu: Date
    public init(id: String, expediteur: String, objet: String, recu: Date) { self.id = id; self.expediteur = expediteur; self.objet = objet; self.recu = recu }
}

/// Ce qui lit Mail. Le vrai pilote l'app Mail ; les contrôles en donnent un faux (jamais la vraie Mail).
public protocol SourceMail: Sendable {
    /// Mail tourne (sinon on ne le sonde pas : AppleScript le lancerait).
    func estOuvert() async -> Bool
    /// Les non lus de la boîte de réception arrivés dans les `secondes` dernières secondes (`max` au plus).
    func nonLus(depuisSecondes secondes: Int, max: Int) async throws(ErreurApp) -> [MessageMail]
}

public enum ScriptMail {
    /// Les séparateurs de la sortie : des caractères de contrôle, qui n'existent ni dans un objet ni dans une adresse (retirés au besoin).
    static let champ = "\u{1F}", fiche = "\u{1E}"
    /// La première fois : les non lus des 2 derniers jours ; ensuite, depuis le dernier passage (et une marge).
    public static let fenetreInitiale = 2 * 86_400
    public static let marge = 120
    /// Jamais plus de 30 mails lus d'un coup (le script reste court même avec une boîte pleine).
    public static let maximum = 30
    /// Mail occupé (synchronisation d'une grosse boîte) : on abandonne au bout de 15 s plutôt que d'attendre les 2 min d'AppleScript.
    public static let delai = 15

    /// Le script. Les dates sont rendues en secondes avant l'instant du script (jamais une date écrite : son format dépend de la langue
    /// du Mac). `current date` est appelé hors du bloc `tell` (pas un ordre envoyé à Mail).
    public static func texte(depuisSecondes s: Int, max: Int = maximum) -> String {
        """
        set maintenant to current date
        set seuil to maintenant - \(Swift.max(60, s))
        set sortie to ""
        with timeout of \(delai) seconds
        tell application "Mail"
            set nonlus to (messages of inbox whose read status is false and date received > seuil)
            set n to 0
            repeat with m in nonlus
                set n to n + 1
                if n > \(Swift.max(1, max)) then exit repeat
                set sortie to sortie & (message id of m) & (character id 31) & (sender of m) & (character id 31) & (subject of m) & (character id 31) & (((date received of m) - maintenant) as integer) & (character id 30)
            end repeat
        end tell
        end timeout
        return sortie
        """
    }

    /// Lit la sortie du script. Une fiche mal formée (champ manquant, date illisible) est ignorée ; les plus récents d'abord.
    public static func analyser(_ sortie: String, maintenant: Date) -> [MessageMail] {
        sortie.components(separatedBy: fiche).compactMap { f in
            let c = f.components(separatedBy: champ)
            guard c.count == 4 else { return nil }
            let id = c[0].trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
            guard !id.isEmpty, let ecart = Int(c[3].trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
            return MessageMail(id: id, expediteur: nomExpediteur(c[1]), objet: Nouveaute.ligne(c[2]), recu: maintenant.addingTimeInterval(TimeInterval(ecart)))
        }.sorted { $0.recu > $1.recu }
    }

    /// « Camille Martin <camille@exemple.fr> » → « Camille Martin » ; « "Martin, Camille" <…> » → « Martin, Camille » ; une adresse
    /// seule reste l'adresse.
    public static func nomExpediteur(_ brut: String) -> String {
        let s = brut.trimmingCharacters(in: .whitespacesAndNewlines)
        if let i = s.firstIndex(of: "<"), i > s.startIndex {
            let nom = s[..<i].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !nom.isEmpty { return Nouveaute.ligne(nom, max: 60) }
        }
        return Nouveaute.ligne(s.trimmingCharacters(in: CharacterSet(charactersIn: "<>")), max: 60)
    }

    /// L'erreur d'AppleScript (`NSAppleScriptErrorNumber`) en erreur dite : -1743 (Automatisation refusée), -600 (Mail fermé), -1712
    /// (trop long), autre.
    public static func erreur(code: Int) -> ErreurApp {
        switch code {
        case -1743, -1744: return .autorisationMail
        case -600, -609: return .mailFerme
        default: return .mail(code)
        }
    }

    public static func nouveaute(_ m: MessageMail) -> Nouveaute {
        Nouveaute(id: "mail:\(m.id)", app: .mail, titre: m.expediteur.isEmpty ? "Sans expéditeur" : m.expediteur,
                  sousTitre: m.objet.isEmpty ? "(sans objet)" : m.objet, date: m.recu, action: .messageMail(id: m.id))
    }
}

public enum AgendaApps {
    /// On n'annonce que le prochain rendez-vous des 12 prochaines heures (le bandeau « Dans 10 min » de l'îlot fait déjà le reste).
    public static let horizon: TimeInterval = 12 * 3600

    /// Le prochain rendez-vous (`PlanAgenda.prochain`, la même règle que l'îlot), en nouveauté ; nil : rien d'ici 12 h.
    public static func nouveaute(_ evenements: [EvenementAgenda], maintenant: Date, heure: (Date) -> String) -> Nouveaute? {
        guard let e = PlanAgenda.prochain(evenements, a: maintenant), e.debut.timeIntervalSince(maintenant) <= horizon else { return nil }
        var sous = heure(e.debut)
        if let l = e.lien { sous += " \u{00B7} " + LienVisio.service(l) } else if let lieu = e.lieu { sous += " \u{00B7} " + Nouveaute.ligne(lieu, max: 40) }
        // l'identifiant d'un rendez-vous contient déjà son heure de début : déplacé, c'est une autre nouveauté
        return Nouveaute(id: "agenda:\(e.id)", app: .agenda, titre: Nouveaute.ligne(e.titre), sousTitre: sous, date: e.debut,
                         action: e.lien.map { .adresse($0) } ?? .rendezVous(id: e.id))
    }
}
