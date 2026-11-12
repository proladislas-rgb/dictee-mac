import SwiftUI
import DicteeCore

/// « Découvrir » (maquette, étape 8) : sept choses que fait l'encoche, chacune en petite scène qui bouge toute seule. « Essayer »
/// la fait faire à la vraie encoche, pour celles que l'app sait montrer ; les autres disent le geste.
struct DecouvrirVue: View {
    var essais: Set<Decouverte>
    var essayer: (Decouverte) -> Void
    /// La fenêtre est à l'écran : sinon les scènes s'arrêtent.
    var actif = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            EntetePage(petit: "Sept choses que fait l\u{2019}encoche", titre: "Découvrir") {
                PhraseEntete(texte: "Chaque scène bouge toute seule. «\u{202F}Essayer\u{202F}» le fait faire à la vraie encoche, juste au-dessus.")
            }
            GeometryReader { g in
                let e = TonsBureau.ecart
                let colonne = (g.size.width - 3 * e) / 4
                let rang = (g.size.height - e) / 2
                let petites = Decouverte.allCases.filter { !$0.grande }
                VStack(spacing: e) {
                    HStack(spacing: e) {
                        TuileDecouverte(d: .centre, peutEssayer: essais.contains(.centre), essayer: essayer, actif: actif).frame(width: 2 * colonne + e)
                        ForEach(petites.prefix(2), id: \.self) { d in TuileDecouverte(d: d, peutEssayer: essais.contains(d), essayer: essayer, actif: actif).frame(width: colonne) }
                    }
                    .frame(height: rang)
                    HStack(spacing: e) {
                        ForEach(petites.dropFirst(2), id: \.self) { d in TuileDecouverte(d: d, peutEssayer: essais.contains(d), essayer: essayer, actif: actif).frame(width: colonne) }
                    }
                    .frame(height: rang)
                }
            }
        }
        .padding(.horizontal, TonsBureau.margeH)
        .padding(.bottom, TonsBureau.margeBas)
    }
}

/// Une tuile : la scène en haut (ou à gauche pour la grande), le titre, « Essayer », la phrase.
struct TuileDecouverte: View {
    var d: Decouverte
    var peutEssayer: Bool
    var essayer: (Decouverte) -> Void
    var actif = true

    var body: some View {
        CarteBureau(rayon: 20) {
            Group {
                if d.grande {
                    GeometryReader { g in
                        HStack(spacing: 16) {
                            scene.frame(width: g.size.width * 0.56, height: g.size.height)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(d.titre).font(.system(size: 20, weight: .bold)).tracking(-0.4).foregroundStyle(TonsBureau.encre)
                                Text(d.phrase).font(.system(size: 13)).lineSpacing(2).foregroundStyle(TonsBureau.encre2).fixedSize(horizontal: false, vertical: true)
                                if peutEssayer {
                                    BoutonCapsule(titre: "Essayer", symbole: "play.fill", hauteur: 30) { essayer(d) }.padding(.top, 6)
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                            .padding(.trailing, 8)
                        }
                    }
                    .padding(10)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        scene
                        HStack(spacing: 6) {
                            Text(d.titre).font(.system(size: 14, weight: .semibold)).tracking(-0.15).foregroundStyle(TonsBureau.encre).lineLimit(1)
                            Spacer(minLength: 4)
                            if peutEssayer { BoutonCapsule(titre: "Essayer", style: .doux, hauteur: 24) { essayer(d) } }
                        }
                        .frame(height: 24)
                        .padding(.top, 9).padding(.horizontal, 4)
                        Text(d.phrase).font(.system(size: 12)).lineSpacing(1).foregroundStyle(TonsBureau.encre2)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                            .frame(height: 32, alignment: .topLeading)
                            .padding(.horizontal, 4).padding(.top, 2)
                    }
                    .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 12)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(d.titre) : \(d.phrase)")
    }

    private var scene: some View {
        PetiteScene(d: d, actif: actif)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LinearGradient(colors: TonsBureau.scene, startPoint: UnitPoint(x: 0.3, y: 0), endPoint: UnitPoint(x: 0.7, y: 1)))
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

/// La petite scène d'une tuile : l'encoche (noire) en haut au milieu, qui fait le geste en boucle. À 30 images par seconde au plus,
/// seulement quand la page et la fenêtre sont à l'écran ; posée sur son moment parlant avec « Réduire les animations » et dans les rendus.
struct PetiteScene: View {
    var d: Decouverte
    var actif = true
    @Environment(\.accessibilityReduceMotion) private var reduire
    @Environment(\.renduStatique) private var statique
    @State private var debut = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !actif || reduire || statique)) { ctx in
            ScenePetite(d: d, t: reduire || statique ? ScenePetite.posee(d) : ctx.date.timeIntervalSince(debut))
        }
    }
}

/// Une scène à l'instant `t` : des formes simples, en ressorts (DicteeCore `Ressort`).
struct ScenePetite: View {
    var d: Decouverte
    var t: Double

    static func posee(_ d: Decouverte) -> Double {
        switch d {
        case .centre: return 2
        case .etagere: return 1.9
        case .minuteur: return 3
        case .rappels: return 3
        case .reunions: return 2.5
        case .claude: return 2.5
        case .lecture: return 2
        }
    }

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            ZStack(alignment: .top) {
                switch d {
                case .centre: centre(w)
                case .etagere: etagere(w)
                case .minuteur: minuteur(w)
                case .rappels: rappels(w)
                case .reunions: reunions(w)
                case .claude: claude(w)
                case .lecture: lecture(w)
                }
            }
            .frame(width: g.size.width, height: g.size.height, alignment: .top)
        }
        .clipped()
        .accessibilityHidden(true)
    }

    /// L'encoche : noire, coins du bas arrondis, à la largeur et à la hauteur données.
    private func encoche<C: View>(_ l: CGFloat, _ h: CGFloat, rayon: CGFloat? = nil, @ViewBuilder contenu: () -> C = { EmptyView() }) -> some View {
        UnevenRoundedRectangle(bottomLeadingRadius: rayon ?? min(18, h / 2 + 1), bottomTrailingRadius: rayon ?? min(18, h / 2 + 1), style: .continuous)
            .fill(Color.black)
            .frame(width: l, height: h)
            .overlay(alignment: .top) { contenu() }
    }

    private func boucle(_ periode: Double) -> Double { t.truncatingRemainder(dividingBy: periode) }

    // Le Centre : l'encoche se déplie en grand, ses ronds et ses cases, le pointeur monte.
    private func centre(_ w: CGFloat) -> some View {
        let s = boucle(4.2)
        let o = Ressort.allerRetour(0, 1, t: s, aller: 0.4, retour: 3.4, duree: 0.6, rebond: 0.2)
        let vu = Ressort.allerRetour(0, 1, t: s, aller: 0.9, retour: 3.25, duree: 0.4)
        return ZStack(alignment: .top) {
            encoche(44 + 132 * o, 11 + 85 * o) {
                VStack(spacing: 7) {
                    HStack(spacing: 9) {
                        ForEach(0..<5, id: \.self) { i in
                            Circle().fill(i == 1 ? CouleursScene.bleu : (i == 3 ? CouleursScene.corail : Color.white.opacity(0.2))).frame(width: 18, height: 18)
                        }
                    }
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.12))
                        RoundedRectangle(cornerRadius: 7).strokeBorder(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    }
                    .frame(height: 22)
                    Capsule().fill(Color.white.opacity(0.12)).frame(height: 13)
                        .overlay(alignment: .leading) { Circle().fill(CouleursScene.rouge).frame(width: 6, height: 6).padding(.leading, 5) }
                }
                .frame(width: 140).padding(.top, 10).opacity(vu).offset(y: -4 * (1 - vu))
            }
            Image(systemName: "cursorarrow").font(.system(size: 13)).foregroundStyle(.black).shadow(color: .white, radius: 0.5)
                .offset(x: 30 + 30 * (1 - o), y: 30 - 20 * o + 30 * (1 - o))
        }
    }

    // L'étagère : un document glisse vers l'encoche, les zones s'ouvrent, il y reste.
    private func etagere(_ w: CGFloat) -> some View {
        let s = boucle(3.6)
        let va = Ressort.de(0, vers: 1, t: s, depart: 0.3, duree: 1.2)
        let o = Ressort.allerRetour(0, 1, t: s, aller: 1.0, retour: 2.3, duree: 0.45, rebond: 0.2)
        let pose = Ressort.de(0, vers: 1, t: s, depart: 2.3, duree: 0.4)
        let fin = Ressort.de(1, vers: 0, t: s, depart: 3.2, duree: 0.3)
        return ZStack(alignment: .top) {
            encoche(44 + 68 * o + 28 * pose * (1 - o), 11 + 25 * o) {
                HStack(spacing: 4) {
                    ForEach(0..<2, id: \.self) { _ in RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 2])).frame(width: 46, height: 20) }
                }
                .padding(.top, 9).opacity(o)
            }
            .overlay(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 1.5).strokeBorder(.white, lineWidth: 1).frame(width: 8, height: 6).padding(.leading, 7).padding(.top, 2.5).opacity(pose * (1 - o) * fin)
            }
            DocumentMini().scaleEffect(1 - 0.6 * va).offset(x: -34 * (1 - va), y: 60 - 50 * va).opacity(min(1, s * 4) * (1 - Ressort.valeur(s - 1.6, duree: 0.3)))
        }
    }

    // Le minuteur : trois durées, la deuxième choisie, puis l'anneau et le temps dans l'encoche.
    private func minuteur(_ w: CGFloat) -> some View {
        let s = boucle(4)
        let o = Ressort.allerRetour(0, 1, t: s, aller: 0.25, retour: 1.6, duree: 0.45, rebond: 0.2)
        let choisi = s > 1.1
        let compte = Ressort.de(0, vers: 1, t: s, depart: 1.8, duree: 0.4)
        return encoche(44 + 80 * o + 56 * compte * (1 - o), 11 + 23 * o) {
            ZStack(alignment: .top) {
                HStack(spacing: 4) {
                    ForEach(["5", "10", "25"], id: \.self) { m in
                        Text(m).font(.system(size: 8, weight: .bold)).foregroundStyle(m == "10" && choisi ? .black : .white)
                            .frame(width: 30, height: 15).background(Capsule().fill(m == "10" && choisi ? CouleursScene.ambre : Color.white.opacity(0.16)))
                    }
                }
                .padding(.top, 13).opacity(o)
                HStack {
                    Circle().trim(from: 0, to: 0.8 - 0.1 * max(0, s - 1.8) / 2.2).stroke(CouleursScene.ambre, lineWidth: 1.6).rotationEffect(.degrees(-90)).frame(width: 7, height: 7)
                    Spacer()
                    Text("9:5\(8 - min(2, Int(max(0, s - 1.8))))").font(.system(size: 7.5, weight: .bold).monospacedDigit()).foregroundStyle(CouleursScene.ambre)
                }
                .padding(.horizontal, 6).padding(.top, 2).opacity(compte * (1 - o))
            }
        }
    }

    // Les rappels à la voix : la phrase dite, puis le bandeau « Demain 9:00 ».
    private func rappels(_ w: CGFloat) -> some View {
        let s = boucle(4.6)
        let ecoute = Ressort.allerRetour(0, 1, t: s, aller: 0.2, retour: 2.1, duree: 0.4)
        let dit = Ressort.allerRetour(0, 1, t: s, aller: 0.6, retour: 2.1, duree: 0.5)
        let b = Ressort.allerRetour(0, 1, t: s, aller: 2.4, retour: 4.1, duree: 0.5, rebond: 0.2)
        return ZStack(alignment: .top) {
            encoche(44 + 52 * ecoute + 120 * b * (1 - ecoute), 11 + 19 * b) {
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 1.5) {
                        ForEach(0..<4, id: \.self) { i in Capsule().fill(CouleursScene.egaliseur).frame(width: 1.6, height: 3 + 4 * abs(sin(t * 6 + Double(i)))) }
                    }
                    .padding(.leading, 8).padding(.top, 2).opacity(ecoute)
                    HStack(spacing: 5) {
                        Image(systemName: "bell.fill").font(.system(size: 7)).foregroundStyle(CouleursScene.jaune).frame(width: 15, height: 15).background(Circle().fill(CouleursScene.jaune.opacity(0.22)))
                        Text("Demain 9:00").font(.system(size: 7.5, weight: .bold)).foregroundStyle(.white)
                        Text("Appeler le garage").font(.system(size: 7.5, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
                    }
                    .fixedSize().padding(.leading, 9).padding(.top, 7.5).opacity(b)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("«\u{202F}rappelle-moi demain à 9 h\u{202F}»").font(.system(size: 10.5, design: .serif).italic()).foregroundStyle(TonsBureau.encre2).fixedSize()
                .offset(y: 22 + 4 * (1 - dit)).opacity(dit)
        }
    }

    // Les réunions : l'enregistrement dans l'encoche, la note qui s'écrit dessous.
    private func reunions(_ w: CGFloat) -> some View {
        let s = boucle(4)
        return ZStack(alignment: .top) {
            encoche(96, 11) {
                HStack {
                    Circle().fill(CouleursScene.rouge).frame(width: 5, height: 5).opacity(0.6 + 0.4 * cos(t * 5.2))
                    Spacer()
                    Text("12:0\(4 + Int(s) % 6)").font(.system(size: 7.5, weight: .bold).monospacedDigit()).foregroundStyle(.white)
                }
                .padding(.horizontal, 7).padding(.top, 2)
            }
            FeuilleMini {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(0..<3, id: \.self) { i in
                        let v = Ressort.allerRetour(0, 1, t: s, aller: 0.3 + 0.7 * Double(i), retour: 3.5, duree: 0.45)
                        HStack(spacing: 5) {
                            Capsule().fill([CouleursScene.corail, CouleursScene.voixBleue, CouleursScene.voixVerte][i]).frame(width: 12, height: 3)
                            Capsule().fill(CouleursScene.ligne).frame(width: [62, 52, 70][i], height: 3)
                        }
                        .opacity(v).offset(y: 3 * (1 - v))
                    }
                }
            }
            .padding(.horizontal, 24).padding(.top, 18)
        }
    }

    // Claude Code : la session qui avance, sa barre qui se remplit.
    private func claude(_ w: CGFloat) -> some View {
        let s = boucle(4)
        let barre = Ressort.de(0.12, vers: 0.96, t: s, depart: 0.2, duree: 3)
        return ZStack(alignment: .top) {
            encoche(96, 11) {
                HStack {
                    Image(systemName: "asterisk").font(.system(size: 7, weight: .bold)).foregroundStyle(CouleursScene.corail).rotationEffect(.degrees(t * 90))
                    Spacer()
                    Text("\(3 + Int(barre * 4.2))/7").font(.system(size: 7.5, weight: .bold).monospacedDigit()).foregroundStyle(.white)
                }
                .padding(.horizontal, 7).padding(.top, 1.5)
            }
            FeuilleMini {
                VStack(alignment: .leading, spacing: 7) {
                    Text("boutique \u{00B7} écrit les tests").font(.system(size: 8.5, weight: .semibold)).foregroundStyle(CouleursScene.encre).lineLimit(1)
                    GeometryReader { g in
                        Capsule().fill(CouleursScene.piste).overlay(alignment: .leading) { Capsule().fill(CouleursScene.corail).frame(width: g.size.width * barre) }
                    }
                    .frame(height: 3)
                }
            }
            .frame(height: 34)
            .padding(.horizontal, 22).padding(.top, 20)
        }
    }

    // La lecture : la pochette et l'égaliseur dans l'encoche, qui se déplie sur le titre et les commandes.
    private func lecture(_ w: CGFloat) -> some View {
        let s = boucle(4.4)
        let o = Ressort.allerRetour(0, 1, t: s, aller: 0.8, retour: 3.4, duree: 0.55, rebond: 0.2)
        return encoche(110 + 60 * o, 13 + 47 * o) {
            ZStack(alignment: .topLeading) {
                HStack {
                    RoundedRectangle(cornerRadius: 2).fill(LinearGradient(colors: [CouleursScene.pochetteHaut, CouleursScene.pochetteBas], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 9, height: 9)
                    Spacer()
                    HStack(spacing: 1.5) {
                        ForEach(0..<4, id: \.self) { i in Capsule().fill(CouleursScene.egaliseur).frame(width: 1.6, height: 3 + 4 * abs(sin(t * 5 + Double(i) * 1.3))) }
                    }
                }
                .padding(.horizontal, 7).padding(.top, 2).opacity(1 - o)
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 6).fill(LinearGradient(colors: [CouleursScene.pochetteHaut, CouleursScene.pochetteBas], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 4) {
                        Capsule().fill(Color.white.opacity(0.85)).frame(width: 58, height: 4)
                        Capsule().fill(Color.white.opacity(0.4)).frame(width: 40, height: 3)
                        HStack(spacing: 9) {
                            Image(systemName: "backward.fill"); Image(systemName: "pause.fill"); Image(systemName: "forward.fill")
                        }
                        .font(.system(size: 7)).foregroundStyle(.white)
                    }
                }
                .padding(.leading, 12).padding(.top, 13).opacity(o)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Les couleurs des petites scènes : celles de l'encoche (toujours sombre) et des objets qu'elle montre, les mêmes en clair et en sombre.
enum CouleursScene {
    static let bleu = Color(hex: 0x0A84FF), corail = Color(hex: 0xE8835C), rouge = Color(hex: 0xFF453A), ambre = Color(hex: 0xFF9F0A)
    static let egaliseur = Color(hex: 0xFFAB3D), jaune = Color(hex: 0xFFD60A), pdf = Color(hex: 0xE5484D)
    static let voixBleue = Color(hex: 0x6E8FBF), voixVerte = Color(hex: 0x6EA77A)
    static let encre = Color(hex: 0x1D1D1F), ligne = Color(hex: 0xD6D8DE), piste = Color(hex: 0xECECF0)
    static let pochetteHaut = Color(hex: 0xF2841C), pochetteBas = Color(hex: 0xE8455C)
}

/// Un petit document (PDF) pour la scène de l'étagère.
struct DocumentMini: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 2.5).fill(.white).frame(width: 18, height: 23)
            .overlay(alignment: .bottom) { Text("PDF").font(.system(size: 5, weight: .heavy)).foregroundStyle(.white).padding(.horizontal, 2).background(CouleursScene.pdf).padding(.bottom, 4) }
            .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
    }
}

/// Une petite fenêtre blanche (la note, la session) sous l'encoche.
struct FeuilleMini<C: View>: View {
    @ViewBuilder var contenu: C
    var body: some View {
        contenu
            .padding(.horizontal, 9).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 6).fill(.white).shadow(color: Color(red: 20/255, green: 30/255, blue: 50/255).opacity(0.3), radius: 5, y: 4))
    }
}
