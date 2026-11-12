import Foundation
import DicteeCore

/// Contrôles des bulles audio de la transcription (les « vocaux ») : bornes de chaque extrait (piste, marges, voisins), passage
/// suivant, vitesse, durée, noms de fichier, onde, mélange des deux pistes ; le direct de l'îlot qui ne se recalcule que s'il change ;
/// le budget d'audio réservé d'un seul geste (relecture en parallèle).
func controlesExtraitsReunion() {
    var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Europe/Paris")!
    let debut = cal.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 14, minute: 2, second: 10))!
    func s(_ d: Double, _ f: Double, _ l: Locuteur, _ o: String? = nil) -> SegmentReunion { SegmentReunion(debut: d, fin: f, locuteur: l, texte: "texte", orateur: o) }

    groupe("Bulles audio : l'extrait de chaque passage")
    do {
        var r = Reunion(debut: debut, duree: 300)
        r.segments = [s(10, 20, .eux, "p1"), s(20.2, 30, .eux, "p2"), s(25, 29, .moi), s(40, 50, .eux, "p1"), s(170, 182, .moi)]
        r.orateurs = [OrateurReunion(id: "p1", nom: "Personne 1", piste: .eux), OrateurReunion(id: "p2", nom: "Personne 2", piste: .eux)]
        let e0 = ExtraitsReunion.extrait(r, passage: 0)
        verifier(e0?.piste == .eux && abs((e0?.debut ?? 0) - 9.85) < 1e-9, "un passage « Eux » se joue dans la piste du son du Mac, 0,15 s avant son heure (Whisper coupe au ras du mot)")
        verifier(abs((e0?.fin ?? 0) - 20.1) < 1e-9, "sa fin s'arrête au milieu du silence avant la voix suivante de la même piste (20,1 s), pas 0,35 s plus loin (\(e0?.fin ?? 0))")
        let e1 = ExtraitsReunion.extrait(r, passage: 1)
        verifier(abs((e1?.debut ?? 0) - 20.1) < 1e-9 && abs((e1?.fin ?? 0) - 30.35) < 1e-9, "Personne 2 commence au milieu du silence, finit 0,35 s après (\(e1.map { "\($0.debut)–\($0.fin)" } ?? "-"))")
        let e2 = ExtraitsReunion.extrait(r, passage: 2)
        verifier(e2?.piste == .moi && abs((e2?.debut ?? 0) - 24.85) < 1e-9 && abs((e2?.fin ?? 0) - 29.35) < 1e-9, "« Moi » se joue dans la piste du micro ; la voix des autres sur l'autre piste ne la raccourcit pas")
        verifier(ExtraitsReunion.extrait(r, passage: 4, dureeSon: 180)?.fin == 180, "jamais au-delà de la fin du fichier son")
        verifier(ExtraitsReunion.extrait(r, passage: 4, dureeSon: 100) == nil, "un passage après la fin du fichier (son coupé) : rien à jouer")
        verifier(ExtraitsReunion.extrait(r, passage: 9) == nil, "un passage qui n'existe pas : rien")
        var debutReunion = Reunion(duree: 10); debutReunion.segments = [s(0.05, 3, .moi)]
        verifier(ExtraitsReunion.extrait(debutReunion, passage: 0)?.debut == 0, "au tout début de la réunion : pas avant 0")
        let e = ExtraitReunion(passage: 0, piste: .eux, debut: 10, fin: 20)
        verifier(e.position(0.25) == 12.5 && e.position(-1) == 10 && e.position(3) == 20 && e.fraction(15) == 0.5 && e.fraction(25) == 1, "un clic dans l'onde : la bonne seconde du fichier ; la part jouée bornée de 0 à 1")

        verifier(ExtraitsReunion.suivant(apres: 0, dans: r, disponible: { _ in true }) == 1, "la lecture enchaîne sur le passage suivant")
        verifier(ExtraitsReunion.suivant(apres: 1, dans: r, disponible: { $0 == .eux }) == 3, "son « Moi » effacé : on saute ses passages")
        verifier(ExtraitsReunion.suivant(apres: 4, dans: r, disponible: { _ in true }) == nil, "le dernier passage : on s'arrête")

        verifier(ExtraitsReunion.vitesseSuivante(1) == 1.5 && ExtraitsReunion.vitesseSuivante(1.5) == 2 && ExtraitsReunion.vitesseSuivante(2) == 1 && ExtraitsReunion.vitesseSuivante(3) == 1,
                 "vitesse : ×1 → ×1,5 → ×2 → ×1")
        verifier(ExtraitsReunion.libelleVitesse(1) == "1\u{00D7}" && ExtraitsReunion.libelleVitesse(1.5) == "1,5\u{00D7}" && ExtraitsReunion.libelleVitesse(2) == "2\u{00D7}", "« 1× », « 1,5× », « 2× »")
        verifier(ExtraitsReunion.duree(7.4) == "0:07" && ExtraitsReunion.duree(62) == "1:02" && ExtraitsReunion.duree(3735) == "1:02:15", "durées comme une bulle de vocal : 0:07, 1:02, 1:02:15")

        r.titre = "Point / Dupont : devis"
        let n = ExtraitsReunion.nomFichier(r, passage: 1, calendrier: cal)
        verifier(n == "Réunion \u{2013} Personne 2 \u{2013} 14h02.m4a", "nom de l'extrait : « \(n) »")
        r.renommer(orateur: "p2", en: "Claire")
        verifier(ExtraitsReunion.nomFichier(r, passage: 1, calendrier: cal) == "Réunion \u{2013} Claire \u{2013} 14h02.m4a", "renommée : le fichier porte le nouveau nom")
        verifier(ExtraitsReunion.nomFichier(r, passage: 4, calendrier: cal) == "Réunion \u{2013} Moi \u{2013} 14h05.m4a", "l'heure du passage (14h02 + 170 s = 14h05)")
        verifier(ExtraitsReunion.nomFichierReunion(r, calendrier: cal) == "Réunion \u{2013} Point Dupont devis \u{2013} 14h02.m4a", "toute la réunion : son titre, sans « / » ni « : »")
        verifier(ExtraitsReunion.propre(String(repeating: "a", count: 200)).count == 80, "un nom trop long est coupé")
    }

    groupe("Bulles audio : l'onde et le mélange des pistes")
    do {
        var son = [Int16](repeating: 0, count: 16_000)
        for i in 8_000..<12_000 { son[i] = i % 2 == 0 ? 12_000 : -12_000 }
        let o = ExtraitsReunion.onde(son, barres: 4)
        verifier(o.count == 4 && o[0] == 0.12 && o[1] == 0.12 && abs(o[2] - 1) < 1e-5 && o[3] == 0.12, "l'onde suit le vrai niveau : la tranche qui parle est haute, le silence au plancher (\(o))")
        let doux = ExtraitsReunion.onde(son.map { $0 / 20 }, barres: 4)
        verifier(abs(doux[2] - 1) < 1e-5, "un passage dit doucement a aussi une onde lisible (rapportée à sa tranche la plus forte)")
        verifier(ExtraitsReunion.onde([], barres: 5) == Array(repeating: 0.12, count: 5) && ExtraitsReunion.onde(son, barres: 0).isEmpty, "son vide : onde plate ; zéro barre : rien")
        verifier(ExtraitsReunion.onde(son).count == ExtraitsReunion.barres, "36 barres par défaut")
        verifier(ExtraitsReunion.mixer([100, 30_000, -30_000], [50, 10_000, -10_000, 7]) == [150, 32_767, -32_768, 7], "mélange : somme saturée, longueur de la plus longue piste")
    }

    groupe("Réunion optimisée : le direct ne se recalcule que s'il change, l'audio se réserve d'un geste")
    do {
        let a = EntreesDirect(version: 3, attentes: [AttenteDirect(locuteur: .eux, debut: 12)], points: 0)
        verifier(a == EntreesDirect(version: 3, attentes: [AttenteDirect(locuteur: .eux, debut: 12)], points: 0), "rien de neuf : mêmes entrées, pas de recalcul")
        verifier(a != EntreesDirect(version: 4, attentes: a.attentes, points: 0) && a != EntreesDirect(version: 3, attentes: [], points: 0) && a != EntreesDirect(version: 3, attentes: a.attentes, points: 1),
                 "un passage, une parole qui commence ou finit, un point marqué : recalcul")
        let b = BudgetAudio(limiteHeure: 100, reserveDictee: 20)
        verifier(b.reserver(duree: 50, a: 0) == 0 && b.reserver(duree: 25, a: 0) == 0, "deux lots réservent leur audio (75 s sur 80)")
        verifier(b.reserver(duree: 10, a: 1) > 0 && abs(b.utilise(a: 1) - 75) < 1e-9, "le troisième doit attendre, et rien n'est réservé pour lui (\(b.utilise(a: 1)) s)")
        verifier(b.reserver(duree: 10, a: 3_601) == 0, "une heure plus tard : la place est revenue")
    }
}
