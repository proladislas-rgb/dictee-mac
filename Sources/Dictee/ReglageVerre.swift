import SwiftUI
import DicteeCore

/// L'intensité du verre de la Lucarne (Réglages › Apparence) : une seule valeur, lue par la Lucarne et la dictée posée à sa place ;
/// le curseur des Réglages la change en direct (l'aperçu est immédiat, comme le curseur « Intensité du verre » de Sillonia).
/// Deux curseurs la changent : celui des Réglages (Apparence) et celui du Centre de l'îlot (13/11, Hugues : « comme le curseur de
/// luminosité du Centre de contrôle ») ; les deux lisent cette valeur, bouger l'un déplace l'autre.
@MainActor
final class ReglageVerre: ObservableObject {
    static let partage = ReglageVerre()
    @Published var intensite: Double
    /// Où la valeur est gardée (le vrai réglage ; l'essai le remplace : jamais les vrais réglages).
    var enregistrer: (Double) -> Void = { Settings.intensiteVerre = $0 }
    init(intensite: Double = Settings.intensiteVerre) { self.intensite = intensite }
    /// Une nouvelle intensité (bornée 0…1, par pas de 0,05 comme le curseur des Réglages) : l'aperçu est immédiat, la valeur gardée.
    func regler(_ v: Double) {
        let x = (min(1, max(0, v)) * 20).rounded() / 20
        guard x != intensite else { return }
        intensite = x
        enregistrer(x)
    }
}
