import SwiftUI
import DicteeCore

/// « Réunions » (maquette, étape 10) : le titre et son nombre de notes, puis la liste par jour à gauche et la note dans une carte à
/// droite (`ReunionsVue`, la même logique qu'avant : chercher, demander, écouter, noter).
struct ReunionsPageVue: View {
    @ObservedObject var m: ReunionsModele
    @ObservedObject var store: ReunionStore
    @ObservedObject var controleur: ReunionController

    var body: some View {
        let n = store.reunions.filter { $0.etat == .prete }.count
        VStack(alignment: .leading, spacing: 0) {
            EntetePage(petit: n == 0 ? "Toutes gardées sur ce Mac" : "\(n) note\(n > 1 ? "s" : ""), toutes sur ce Mac", titre: "Réunions") {
                PhraseEntete(texte: "Un clic sur «\u{202F}Noter la réunion\u{202F}» dans l\u{2019}encoche\u{202F}: Verbe écrit la note pour toi.")
            }
            ReunionsVue(m: m, store: store, controleur: controleur)
        }
        .padding(.horizontal, TonsBureau.margeH)
        .padding(.bottom, TonsBureau.margeBas)
    }
}
