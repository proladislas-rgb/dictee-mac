import SwiftUI
import DicteeCore

/// La Lucarne hors de l'encoche (régime libre) : sa capsule, dessinée au milieu de la zone de dessin (la fenêtre se cale sur elle et la
/// suit pendant la tenue et le vol : cette vue ne bouge pas). Mission 2 : une capsule noire ; le verre et son contenu viennent à la
/// mission 3. Levée (tenue au doigt), elle grandit de 4 % et prend une ombre.
struct LucarneLibreVue: View {
    @ObservedObject var m: IlotMoteur

    var body: some View {
        let _ = m.rev
        let forme = FormeNoire(points: TraceLucarne.calculer(m.capsuleVue))
        let leve = min(1, max(0, m.lucarne.capsule.leve.x))
        forme.fill(Color.black)
            .shadow(color: .black.opacity(0.35 * leve), radius: 12 * leve, x: 0, y: 6 * leve)
            .contentShape(forme)
            // l'appui sur la capsule : l'appui long la reprend (la vue d'hébergement suit le pointeur)
            .gesture(DragGesture(minimumDistance: 0).onChanged { _ in m.appuiSurForme() })
            .frame(width: IlotMoteur.largeur, height: IlotMoteur.hauteurMax, alignment: .topLeading)
            .scaleEffect(m.presse ? 1.015 : 1, anchor: UnitPoint(x: 0.5, y: IlotMoteur.milieuLibre / Double(IlotMoteur.hauteurMax)))
            .animation(m.reduire ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: m.presse)
            // une dictée l'efface, comme dans l'encoche (décision C du plan)
            .opacity(m.cache ? 0 : 1)
    }
}

/// L'anneau de l'appui long : sous le pointeur, il se remplit en 0,4 s (maquette lucarne-position.html), puis s'efface quand elle se
/// décolle (ou qu'on bouge avant).
struct AnneauAppuiLucarne: View {
    @ObservedObject var m: IlotMoteur

    var body: some View {
        let _ = m.rev
        if let a = m.anneauAppui {
            let d = 2 * IlotMoteur.rayonAnneau
            ZStack {
                Circle().stroke(Color.black.opacity(0.3), lineWidth: 3)
                Circle().trim(from: 0, to: a.fraction)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: .black.opacity(0.6), radius: 1)
            }
            .frame(width: d, height: d)
            .position(a.centre)
            .allowsHitTesting(false)
        }
    }
}
