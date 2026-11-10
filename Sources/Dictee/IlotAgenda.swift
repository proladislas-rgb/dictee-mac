import AppKit
import EventKit
import DicteeCore

/// Les rendez-vous des calendriers du Mac (EventKit : tout ce que l'app Calendrier affiche, Google compris s'il y est ajouté).
/// L'autorisation n'est JAMAIS demandée au lancement : seulement quand Hugues active le calendrier dans les Réglages.
/// Rien n'est enregistré par Verbe : les rendez-vous des prochaines heures sont relus quand il le faut.
@MainActor
final class AgendaSysteme {
    private let magasin = EKEventStore()
    private var observateur: NSObjectProtocol?
    /// La liste a changé (un rendez-vous ajouté, déplacé, supprimé dans Calendrier).
    var surChangement: () -> Void = {}

    enum Statut: Equatable { case nonDemande, autorise, refuse }

    var statut: Statut {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return .autorise
        case .notDetermined: return .nonDemande
        default: return .refuse   // refusé, restreint, ou accès en écriture seule (illisible)
        }
    }

    /// Demande l'accès (fenêtre du système, une seule fois). Appelé seulement quand l'interrupteur des Réglages passe à « activé ».
    func demander() async -> Bool {
        guard statut != .autorise else { return true }
        guard statut == .nonDemande else { return false }
        do { return try await magasin.requestFullAccessToEvents() } catch {
            Log.ecrire("calendrier : demande d'accès en erreur (\(error.localizedDescription))")
            return false
        }
    }

    func ecouter() {
        guard observateur == nil else { return }
        observateur = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: magasin, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.surChangement() }
        }
    }
    func arreter() {
        if let observateur { NotificationCenter.default.removeObserver(observateur) }
        observateur = nil
    }

    /// Les rendez-vous qui commencent d'ici `heures` heures (ou ont commencé il y a moins de 5 minutes). Jamais les journées entières ni les annulés.
    func prochains(heures: Double = 24, depuis maintenant: Date) -> [EvenementAgenda] {
        guard statut == .autorise else { return [] }
        let debut = maintenant.addingTimeInterval(-300), fin = maintenant.addingTimeInterval(heures * 3600)
        let predicat = magasin.predicateForEvents(withStart: debut, end: fin, calendars: nil)
        return magasin.events(matching: predicat).compactMap { e in
            guard !e.isAllDay, e.status != .canceled, e.endDate > maintenant else { return nil }
            // les rendez-vous que j'ai refusés ne comptent pas
            if let moi = e.attendees?.first(where: { $0.isCurrentUser }), moi.participantStatus == .declined { return nil }
            let lien = LienVisio.extraire(depuis: [e.url?.absoluteString, e.location, e.notes])
            let id = (e.eventIdentifier ?? e.calendarItemIdentifier) + "@" + String(Int(e.startDate.timeIntervalSince1970))
            return EvenementAgenda(id: id, titre: e.title?.isEmpty == false ? e.title! : "Sans titre", debut: e.startDate, fin: e.endDate,
                                   lieu: e.location.flatMap { $0.isEmpty ? nil : $0 }, lien: lien, toutelaJournee: false)
        }.sorted { $0.debut < $1.debut }
    }
}
