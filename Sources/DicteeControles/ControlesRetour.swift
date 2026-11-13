import Foundation
import DicteeCore

/// Revenir en arrière dans l'îlot (13/11) : la pile de retour, où mène « ‹ », le geste deux doigts vers la droite, la fermeture d'un
/// bandeau sous un pointeur immobile.
func controlesRetourIlot() {
    groupe("Îlot : revenir en arrière (la pile)")
    var p = PileRetour()
    p.aller(depuis: nil, vers: .centre, epingle: false)
    verifier(p.estVide, "l'îlot s'ouvre sur le Centre : rien avant")
    p.aller(depuis: .centre, vers: .outils, epingle: true)
    p.aller(depuis: .outils, vers: .groq, epingle: true)
    verifier(p.vues == [.centre, .outils] && p.dernier == PasRetour(.outils, epingle: true), "Centre › Outils › détail de Groq : la pile retient Centre puis Outils (épinglé)")
    let r = p.revenir(a: .outils)
    verifier(r == PasRetour(.outils, epingle: true) && p.vues == [.centre], "retour aux Outils : rendu épinglé comme il l'était, le Centre reste dessous")
    verifier(p.revenir(a: .dictees) == nil && p.vues == [.centre], "retour vers un écran absent de la pile : la pile ne bouge pas")
    p.aller(depuis: .outils, vers: .accueil, epingle: false)
    p.aller(depuis: .accueil, vers: .centre, epingle: false)
    verifier(p.estVide, "revenir au Centre par un autre chemin (défilement, point de page) : la pile redescend jusqu'à lui")
    p.aller(depuis: .centre, vers: .centre, epingle: false)
    verifier(p.estVide, "aller vers l'écran où l'on est : rien ne s'empile")
    for i in 0..<12 { p.aller(depuis: i % 2 == 0 ? .outilNote : .outilReformuler, vers: i % 2 == 0 ? .outilReformuler : .outilNote, epingle: false) }
    verifier(p.pas.count <= PileRetour.profondeur, "la pile ne grandit jamais au-delà de \(PileRetour.profondeur) écrans (\(p.pas.count))")
    var q = PileRetour()
    var ici = VueIlot.lectureEtendu
    for v: VueIlot in [.centre, .outils, .accueil, .dictees, .etagere, .bibliotheque, .claudeCarte, .secondBrain, .concentration, .rappelListe] {
        q.aller(depuis: ici, vers: v, epingle: false); ici = v
    }
    verifier(q.pas.count == PileRetour.profondeur && q.pas.first?.vue != .lectureEtendu, "au-delà, le plus ancien s'oublie")
    q.vider()
    verifier(q.estVide, "l'îlot se range : la pile est vidée")

    groupe("Îlot : où mène « ‹ » (et le geste)")
    // les « ‹ » déjà dessinés disent où ils mènent : le geste va au même endroit, quoi que dise la pile
    verifier(NavigationIlot.retour(de: .bibliotheque, pile: [.centre, .etagere], premiere: .centre) == .etagere, "Bibliothèque : « ‹ Étagère »")
    verifier(NavigationIlot.retour(de: .etagere, pile: [.accueil], premiere: .centre) == .centre, "Étagère : « ‹ Centre », même ouverte depuis l'accueil (le bouton dit Centre)")
    for v: VueIlot in [.claudeCarte, .dictees, .outils, .secondBrain, .concentration] {
        verifier(NavigationIlot.retour(de: v, pile: [], premiere: .centre) == .centre, "\(v.rawValue) : « ‹ Centre »")
    }
    for v: VueIlot in [.outilPressePapiers, .outilReformuler, .outilNote] {
        verifier(NavigationIlot.retour(de: v, pile: [], premiere: .centre) == .outils, "\(v.rawValue) : « ‹ Outils »")
    }
    verifier(NavigationIlot.retour(de: .centre, pile: [.dictees], premiere: .lectureEtendu) == .lectureEtendu, "Centre avec une vidéo : « ‹ Vidéo »")
    verifier(NavigationIlot.retour(de: .centre, pile: [], premiere: .centre) == nil, "Centre sans activité : la racine, rien avant (le geste ne fait rien)")
    verifier(NavigationIlot.retour(de: .lectureEtendu, pile: [], premiere: .lectureEtendu) == nil, "la vidéo dépliée tout juste ouverte : rien avant")
    // le détail de Groq : là d'où il vient, la page Outils (jamais l'îlot replié)
    verifier(NavigationIlot.retour(de: .groq, pile: [.centre, .outils], premiere: .centre) == .outils, "détail de Groq ouvert depuis les Outils : retour aux Outils")
    verifier(NavigationIlot.retour(de: .groq, pile: [.centre], premiere: .centre) == .centre, "détail de Groq ouvert depuis le Centre (jauge rangée là) : retour au Centre")
    verifier(NavigationIlot.retour(de: .groq, pile: [], premiere: .centre) == .outils, "détail de Groq sans pile : les Outils (sa jauge y est)")
    verifier(NavigationIlot.retour(de: .rappelListe, pile: [.accueil], premiere: .centre) == .accueil, "les rappels ouverts depuis l'accueil : « ‹ Accueil »")
    verifier(NavigationIlot.retour(de: .rappelListe, pile: [], premiere: .centre) == .centre, "les rappels ouverts du menu : « ‹ Centre »")
    verifier(NavigationIlot.retour(de: .accueil, pile: [.centre, .outils], premiere: .centre) == .outils, "l'accueil (pas de « ‹ ») : le geste revient à la carte d'avant")
    for v: VueIlot in [.centre, .outils, .accueil, .etagere, .rappelListe] {
        verifier(!(NavigationIlot.nom(v) ?? "").isEmpty && (NavigationIlot.nom(v) ?? "").count <= 12, "« ‹ \(NavigationIlot.nom(v) ?? "?") » : un mot court")
    }

    groupe("Îlot : deux doigts vers la droite = « ‹ »")
    var b = BalayageRetour()
    verifier(!b.recevoir(doigtsX: 10, dy: 1, phase: .debut, inertie: false) && !b.recevoir(doigtsX: 20, dy: -2, phase: .suite, inertie: false),
             "30 pt vers la droite : rien encore (seuil \(Int(BalayageRetour.seuil)) pt)")
    verifier(b.recevoir(doigtsX: 12, dy: 0, phase: .suite, inertie: false) && b.avale, "42 pt vers la droite, presque à plat : retour, une fois")
    verifier(!b.recevoir(doigtsX: 80, dy: 0, phase: .suite, inertie: false) && b.avale, "le même geste continue : pas un 2e retour, la suite est avalée")
    _ = b.recevoir(doigtsX: 0, dy: 0, phase: .fin, inertie: false)
    verifier(!b.recevoir(doigtsX: 60, dy: 0, phase: .suite, inertie: true) && b.avale, "son inertie : ignorée, toujours avalée (elle ne fait pas défiler la liste)")
    verifier(!b.recevoir(doigtsX: -20, dy: 0, phase: .debut, inertie: false) && !b.recevoir(doigtsX: -60, dy: 0, phase: .suite, inertie: false) && !b.avale,
             "geste suivant, vers la gauche : rien (et plus rien d'avalé)")
    _ = b.recevoir(doigtsX: 0, dy: 0, phase: .fin, inertie: false)
    verifier(!b.recevoir(doigtsX: 8, dy: -10, phase: .debut, inertie: false) && !b.recevoir(doigtsX: 32, dy: -30, phase: .suite, inertie: false) && !b.avale,
             "un défilement vertical un peu de travers (40 pt à droite, 40 vers le haut) : jamais un retour")
    _ = b.recevoir(doigtsX: 0, dy: 0, phase: .fin, inertie: false)
    verifier(!b.recevoir(doigtsX: 50, dy: 0, phase: .aucune, inertie: false), "la molette (sans phase) : jamais un retour")
    verifier(!b.recevoir(doigtsX: 50, dy: 0, phase: .suite, inertie: true), "l'inertie d'un geste vertical : jamais un retour")

    groupe("Îlot : jamais bloqué (un bandeau sous le pointeur)")
    let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let ech = t0.addingTimeInterval(5)
    verifier(FermetureBandeau.prochainExamen(echeance: ech, maintenant: t0.addingTimeInterval(2), pointeurDessus: true, dernierGeste: t0) == ech,
             "avant son échéance : il reste, pointeur ou pas")
    verifier(FermetureBandeau.prochainExamen(echeance: ech, maintenant: ech, pointeurDessus: false, dernierGeste: t0) == nil, "échu, pointeur ailleurs : il part")
    verifier(FermetureBandeau.prochainExamen(echeance: ech, maintenant: ech, pointeurDessus: true, dernierGeste: t0) == nil,
             "échu, pointeur posé dessus sans bouger depuis le clic (5 s) : il part quand même")
    let geste = t0.addingTimeInterval(4)
    verifier(FermetureBandeau.prochainExamen(echeance: ech, maintenant: ech, pointeurDessus: true, dernierGeste: geste) == geste.addingTimeInterval(FermetureBandeau.calme),
             "échu, la souris a bougé il y a 1 s : il reste jusqu'à \(Int(FermetureBandeau.calme)) s après ce geste")
    verifier(FermetureBandeau.prochainExamen(echeance: ech, maintenant: geste.addingTimeInterval(FermetureBandeau.calme), pointeurDessus: true, dernierGeste: geste) == nil,
             "puis \(Int(FermetureBandeau.calme)) s sans geste : il part")
    // au pire : l'échéance, plus le calme après le dernier geste ; immobile, jamais plus que l'échéance
    var pire = 0.0
    for s in stride(from: 0.0, through: 20, by: 0.5) {
        let dernier = t0.addingTimeInterval(min(s, 5))
        var t = ech
        while let n = FermetureBandeau.prochainExamen(echeance: ech, maintenant: t, pointeurDessus: true, dernierGeste: dernier), n > t { t = n }
        pire = max(pire, t.timeIntervalSince(t0))
    }
    verifier(pire <= 5 + FermetureBandeau.calme + 0.001, "pointeur immobile après le dernier geste : parti au plus \(String(format: "%.0f", pire)) s après l'ouverture (échéance + \(Int(FermetureBandeau.calme)) s)")
}
