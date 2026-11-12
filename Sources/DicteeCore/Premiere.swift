import Foundation

/// « Le premier arrivé gagne » sans attendre les perdants : une valeur donnée une seule fois, attendue par un seul appelant.
/// (`withTaskGroup` attend tous ses enfants avant de rendre la main, même annulés, quand l'un d'eux attend une autre tâche :
/// une course faite avec lui reste donc aussi lente que la plus lente des deux.)
public final class Premiere<T: Sendable>: @unchecked Sendable {
    private let verrou = NSLock()
    private var continuation: CheckedContinuation<T?, Never>?
    private var fait = false
    private var valeur: T?

    public init() {}

    /// Donne la valeur ; les appels suivants sont ignorés.
    public func resoudre(_ v: T?) {
        verrou.lock()
        if fait { verrou.unlock(); return }
        fait = true; valeur = v
        let c = continuation; continuation = nil
        verrou.unlock()
        c?.resume(returning: v)
    }

    public func attendre() async -> T? {
        await withCheckedContinuation { (c: CheckedContinuation<T?, Never>) in
            verrou.lock()
            if fait { verrou.unlock(); c.resume(returning: valeur) } else { continuation = c; verrou.unlock() }
        }
    }

    /// La valeur de `operation` si elle arrive avant `secondes`, sinon `parDefaut`, sans jamais attendre `operation` au-delà du délai
    /// (elle continue seule, sa valeur est ignorée) : même une opération qui ne rend jamais la main ni ne répond à l'annulation.
    public static func avantDelai(_ secondes: Double, parDefaut: T, _ operation: @escaping @Sendable () async -> T) async -> T {
        let course = Premiere<T>()
        let travail = Task { course.resoudre(await operation()) }
        let minuterie = Task {
            try? await Task.sleep(for: .seconds(secondes))
            course.resoudre(parDefaut)
        }
        let v = await course.attendre() ?? parDefaut
        travail.cancel(); minuterie.cancel()
        return v
    }
}
