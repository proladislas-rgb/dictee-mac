import SwiftUI
import DicteeCore

/// L'intensité du verre de la Lucarne (Réglages › Apparence) : une seule valeur, lue par la Lucarne et la dictée posée à sa place ;
/// le curseur des Réglages la change en direct (l'aperçu est immédiat, comme le curseur « Intensité du verre » de Sillonia).
@MainActor
final class ReglageVerre: ObservableObject {
    static let partage = ReglageVerre()
    @Published var intensite: Double
    init(intensite: Double = Settings.intensiteVerre) { self.intensite = intensite }
}
