import AppKit
import QuartzCore
import DicteeCore

extension IlotEssai {
    /// Un historique de la taille de celui de Hugues (≈ 960 dictées sur un mois, 100 caractères en moyenne, quelques très longues),
    /// en mémoire : jamais le vrai fichier.
    static func dicteesNombreuses(_ n: Int = 960, maintenant t: Date) -> [EntreeHistorique] {
        let apps = ["Terminal", "Mail", "Messages", "Notes", "Google Chrome", "Slack"]
        let phrase = "Il faut juste qu\u{2019}il l\u{2019}aide à trouver des noms pour le projet, et on regarde ça demain matin avec l\u{2019}équipe. "
        return (0 ..< n).map { i in
            let longueur = i % 37 == 0 ? 900 : 40 + (i * 53) % 160
            let texte = String(String(repeating: phrase, count: longueur / phrase.count + 1).prefix(longueur))
            return EntreeHistorique(date: t.addingTimeInterval(-Double(i) * 2_700 - 90), appId: nil, appNom: apps[i % apps.count], texte: "\(i) · " + texte)
        }
    }

    /// « Ça plante de temps en temps quand je me balade dessus » (Hugues, 12/11, carte Dictées ouverte) : de VRAIS mouvements de souris
    /// remis à la vue de l'îlot (sa zone de suivi : le survol de la forme) et à la fenêtre, de bord en bord de la carte, sur les points de
    /// page, sur le pied, hors de la forme (le vide de la fenêtre) et hors de la fenêtre, aller-retour rapides, molette en même temps. On
    /// mesure le travail du fil principal à chaque mouvement (événement + mise en page + dessin), et on vérifie que rien ne s'ouvre ni ne
    /// se ferme, que la fenêtre ne change pas de cadre et qu'aucune animation ne reste en route.
    @MainActor
    static func survolDictees(_ c: IlotControleur, verifier: (Bool, String) -> Void, attendre: (Double, () -> Bool) -> Void) {
        let m = c.moteur, d = m.dictees
        func pause(_ s: Double) { attendre(s) { true } }
        print("Le survol de la carte Dictées (vrais mouvements de souris, historique de 960 dictées)")
        let sourceAvant = d.source
        let memoire = HistoriqueStore(enMemoire: dicteesNombreuses(maintenant: c.maintenant()))
        d.source = { memoire }
        c.panneau.simulerPointeur(forme: false); m.fermer(); pause(0.8)
        m.clicForme(); pause(0.9)
        m.allerA(.dictees); pause(1.4)
        attendre(1.5) { !m.geo.allSatisfy(\.fini) }
        verifier(m.courante == .dictees && m.epingle && d.defile, "la carte Dictées ouverte, épinglée, la liste défile (\(m.courante))")
        guard let vue = c.panneau.vueEssai, let cadre0 = c.panneau.cadre else { verifier(false, "la vue de l'îlot existe"); return }

        // les zones de suivi posées par SwiftUI (NSHostingView) restent : ce sont elles qui portent les survols (`.onHover`)
        vue.updateTrackingAreas()
        let zones = vue.trackingAreas.filter { $0.owner === vue && $0.options.isSuperset(of: VueHebergeeIlot<IlotVue>.optionsVoulues) }
        verifier(!zones.isEmpty,
                 "les zones de suivi de SwiftUI sont gardées (\(vue.trackingAreas.count) zone(s) : \(vue.trackingAreas.map { $0.options.rawValue }))")
        // le parcours : la souris se promène comme une main (≈ 120 positions par seconde), de bord en bord, sur les points, sur le pied,
        // dans le vide de la fenêtre (à côté de la forme, sous elle), dehors, et revient vite
        let g = m.grille, liste = PlanDictees.cadreListe(g), pied = PlanDictees.cadrePied(g), fond = PlanDictees.fond(g)
        let n = m.cartes.count, corps = CGFloat(m.trace.corps), h = CGFloat(m.geo[2].x)
        let points = (0 ..< n).map { PointsCartes.centre($0, sur: n, corps: corps, hauteur: h, barre: g.barre) }
        var chemin: [CGPoint] = []
        func aller(_ a: CGPoint, _ b: CGPoint, _ pas: Int) { for i in 0 ... pas { let t = CGFloat(i) / CGFloat(pas); chemin.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)) } }
        for k in 0 ..< 3 {
            let y = liste.minY + 10 + CGFloat(k) * 60
            aller(CGPoint(x: fond.minX + 2, y: y), CGPoint(x: fond.maxX - 2, y: y + 30), 60)               // de bord en bord
            aller(CGPoint(x: fond.maxX - 2, y: y + 30), CGPoint(x: fond.maxX + 14, y: y + 30), 6)          // dans le vide de la fenêtre
            aller(CGPoint(x: fond.maxX + 14, y: y + 30), CGPoint(x: fond.maxX + 60, y: y + 30), 4)          // dehors
            aller(CGPoint(x: fond.maxX + 60, y: y + 30), points[k % n], 3)                                   // retour rapide, sur un point
            aller(points[0], points[n - 1], 24)                                                              // le long des points
            aller(points[n - 1], CGPoint(x: pied.minX + 30, y: pied.midY), 30)                               // jusqu'au pied
            aller(CGPoint(x: pied.minX + 30, y: pied.midY), CGPoint(x: 0, y: fond.maxY + 20), 6)            // sous la forme
            aller(CGPoint(x: 0, y: fond.maxY + 20), CGPoint(x: liste.midX, y: liste.minY + 5), 12)          // et retour dans la liste
        }
        var survolsVus = Set<UUID>()
        /// La dictée sous le point (nil : aucune, ou trop près d'un bord pour juger) ; `bord` : trop près d'un bord de ligne pour juger.
        func ligneSous(_ p: CGPoint) -> (id: UUID?, net: Bool) {
            guard liste.insetBy(dx: 0, dy: 16).contains(p) else { return (nil, !liste.insetBy(dx: -4, dy: -4).contains(p)) }
            for e in d.miseEnPage().elements {
                // le cadre de la ligne à l'écran (comme PlanDictees.cadreLigne, sans recalculer la grille à chaque ligne)
                let r = CGRect(x: liste.minX, y: liste.minY + CGFloat(e.y - d.decalage), width: liste.width, height: CGFloat(e.h))
                guard case .ligne(let x) = e.genre, r.intersects(liste) else { continue }
                // une ligne à moitié sous un bord ne prend ni clic ni survol (CarteDictees.partieCliquable)
                let entiere = r.minY >= liste.minY - 1 && r.maxY <= liste.maxY + 1
                if r.insetBy(dx: 0, dy: 3).contains(p) { return (entiere ? x.id : nil, true) }
                if r.insetBy(dx: 0, dy: -3).contains(p) { return (nil, false) }
            }
            return (nil, true)
        }
        /// Le début du texte d'une dictée (« 12 · »), « rien », ou « inconnue » (un id que l'historique de l'essai ne connaît pas).
        func nom(_ id: UUID?) -> String { id.map { d.entree($0).map { String($0.texte.prefix(4)) } ?? "inconnue" } ?? "rien" }
        var juges = 0, justes = 0, ecarts: [String] = []
        var temps: [Double] = []
        // le même travail en instructions : le temps d'horloge dépend du cœur que macOS choisit (12/11 : le même mouvement, 90 millions
        // d'instructions, prend 7 ms sur un cœur performance, 26 ms sur un cœur économe, au gré de l'ordonnanceur, de jour comme de nuit)
        var travail: [Double] = []
        var cyclesTotal = 0.0, cyclesPerf = 0.0
        var cartes = Set<String>(), cadres = Set<String>(), fermetures = 0
        var defilements = 0
        let cpu0 = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID), mur0 = CACurrentMediaTime()
        for (i, p) in chemin.enumerated() {
            let u0 = TravailProcessus.lire()
            let t0 = CACurrentMediaTime()
            c.panneau.envoyerMouvement(en: p)
            // la molette en passant sur la liste (deux doigts) : la liste défile sous le pointeur
            if i % 40 == 20, liste.contains(p) {
                c.panneau.envoyerDefilement(dy: -12, en: p, phase: 1); c.panneau.envoyerDefilement(dy: -30, en: p, phase: 2)
                c.panneau.envoyerDefilement(dy: 0, en: p, phase: 4); defilements += 1
            }
            // le travail que ce mouvement donne au fil principal : la mise en page et le dessin de la fenêtre, jusqu'au bout
            vue.layoutSubtreeIfNeeded(); vue.window?.displayIfNeeded(); CATransaction.flush()
            temps.append((CACurrentMediaTime() - t0) * 1000)
            let u1 = TravailProcessus.lire()
            travail.append(Double(u1.instructions &- u0.instructions) / 1e6)
            cyclesTotal += Double(u1.cycles &- u0.cycles); cyclesPerf += Double(u1.cyclesPerf &- u0.cyclesPerf)
            cartes.insert("\(m.courante)")
            if let f = c.panneau.cadre { cadres.insert("\(Int(f.minX)),\(Int(f.minY)),\(Int(f.width)),\(Int(f.height))") }
            if !m.fenetreOuverte { fermetures += 1 }
            pause(1.0 / 120)
            // le survol de SwiftUI suit la souris : la ligne allumée est celle qui est sous le pointeur, aucune hors de la liste
            if let s = d.survol { survolsVus.insert(s) }
            // (pas juste après un geste de molette : la liste a bougé sous un pointeur immobile, le survol suit au mouvement suivant)
            let attendu = ligneSous(p)
            if attendu.net, i % 40 != 20 {
                juges += 1
                if d.survol == attendu.id { justes += 1 } else if ecarts.count < 4 { ecarts.append("(\(Int(p.x)), \(Int(p.y))) attendu \(nom(attendu.id)) allumé \(nom(d.survol)) déc. \(Int(d.decalage))") }
            }
        }
        // l'occupation du fil principal pendant toute la promenade (fondus, dessins, événements), pas seulement à chaque mouvement
        let occupation = Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - cpu0) / 1e9 / (CACurrentMediaTime() - mur0)
        let tri = temps.sorted(), moyenne = temps.reduce(0, +) / Double(max(1, temps.count))
        let p95 = tri[min(tri.count - 1, Int(Double(tri.count) * 0.95))], pire = tri.last ?? 0
        let triT = travail.sorted(), moyenneT = travail.reduce(0, +) / Double(max(1, travail.count))
        let p95T = triT[min(triT.count - 1, Int(Double(triT.count) * 0.95))], pireT = triT.last ?? 0
        for (i, t) in temps.enumerated().sorted(by: { $0.element > $1.element }).prefix(6) {
            print(String(format: "    lent : mouvement %d en (%.0f, %.0f) : %.2f ms, %.1f M instructions%@", i, chemin[i].x, chemin[i].y, t, travail[i], i % 40 == 20 ? " (avec molette)" : ""))
        }
        print(String(format: "  mesure : %d mouvements, %d gestes de molette, fil principal occupé %.0f %% ; travail par mouvement : moyenne %.2f ms, 95 %% sous %.2f ms, pire %.2f ms",
                     chemin.count, defilements, occupation * 100, moyenne, p95, pire))
        print(String(format: "  en instructions : moyenne %.1f M, 95 %% sous %.1f M, pire %.1f M ; %.0f %% des cycles sur les cœurs performance",
                     moyenneT, p95T, pireT, cyclesTotal > 0 ? cyclesPerf / cyclesTotal * 100 : 0))
        verifier(cartes == ["dictees"] && fermetures == 0, "toute la promenade : la carte Dictées reste ouverte, jamais refermée ni rouverte (\(cartes.sorted()), \(fermetures) fermeture(s))")
        verifier(cadres.count == 1 && c.panneau.cadre == cadre0, "la fenêtre ne change pas de cadre sous la souris (\(cadres.count) cadre(s))")
        // Le travail se juge en instructions (le même sur tous les cœurs ; un cœur économe en fait ≈ 3,4 M par ms, un cœur performance
        // ≈ 12 M) ; l'horloge, avec la marge d'un cœur économe, n'attrape plus que ce qui ATTEND (disque, verrou, réponse d'un autre
        // processus), que les instructions ne voient pas. Mesuré le 12/11 (macOS 26, M5) : avant l'allègement, molette 112 M (pire 133 M),
        // survol d'une ligne à l'autre 45 M, moyenne 6,0 M, 95 % sous 42,6 M ; après : 64 M (pire 91 M), 33 M, 4,6 M, 32,7 M.
        verifier(moyenneT < 8 && p95T < 40, String(format: "le fil principal reste libre : %.1f M instructions en moyenne, %.1f M pour 95 %% des mouvements (moins de 12 ms même sur un cœur économe)", moyenneT, p95T))
        verifier(moyenne < 4, String(format: "le fil principal reste libre à l'horloge : %.2f ms en moyenne (95 %% sous %.2f ms)", moyenne, p95))
        verifier(occupation < 0.35, String(format: "pendant la promenade, le fil principal travaille %.0f %% du temps (le reste libre pour le système et les autres apps)", occupation * 100))
        verifier(pireT < 100, String(format: "aucun à-coup : le pire mouvement demande %.1f M instructions (moins de 100 M : 8 ms sur un cœur performance, 29 sur un économe)", pireT))
        verifier(pire < 40, String(format: "aucune attente : le pire mouvement prend %.2f ms à l'horloge (moins de 5 images, même sur un cœur économe)", pire))
        verifier(survolsVus.count >= 8 && juges > 200 && Double(justes) >= 0.97 * Double(juges),
                 "le survol suit la souris : \(justes) mouvements sur \(juges) allument la bonne ligne (ou aucune hors de la liste), \(survolsVus.count) lignes allumées tour à tour\(ecarts.isEmpty ? "" : ", écarts en " + ecarts.joined(separator: " "))")
        c.panneau.envoyerMouvement(en: CGPoint(x: fond.maxX + 80, y: fond.midY)); pause(0.1)
        verifier(d.survol == nil, "la souris sortie de la fenêtre : plus aucune ligne allumée")
        attendre(1.5) { m.boucleActive }
        verifier(!m.boucleActive, "la souris arrêtée : aucune animation ne reste en route (bouge encore : \(m.ceQuiBouge))")

        d.source = sourceAvant
        c.panneau.simulerPointeur(forme: false); m.fermer(); pause(0.8)
    }
}

/// Le travail du processus depuis son lancement, en instructions et en cycles (`proc_pid_rusage`) : une mesure qui ne dépend pas du cœur
/// (performance ou économe) ni de sa fréquence, contrairement au temps d'horloge.
enum TravailProcessus {
    static func lire() -> (instructions: UInt64, cycles: UInt64, cyclesPerf: UInt64) {
        var r = rusage_info_v6()
        let ok = withUnsafeMutablePointer(to: &r) { $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(getpid(), RUSAGE_INFO_V6, $0) } }
        guard ok == 0 else { return (0, 0, 0) }
        return (r.ri_instructions, r.ri_cycles, r.ri_pcycles)
    }
}
