import Foundation
import DicteeCore

/// Contrôles de la note d'après l'appel (maquette design/maquettes/ilot-reunion.html, étapes 8 à 12) : la relecture de tout
/// l'enregistrement (lots, heures ramenées à la réunion, réponse de Whisper, repli sur le direct), la progression, la note par sujets
/// et sa garde, la transcription (orateur, heure à chaque nouvelle minute), les orateurs renommables, « Demander », l'export.
func controlesReunionNote() {
    func s(_ d: Double, _ f: Double, _ l: Locuteur, _ t: String) -> SegmentReunion { SegmentReunion(debut: d, fin: f, locuteur: l, texte: t) }
    var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Europe/Paris")!
    let debut = cal.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 14, minute: 2, second: 0))!

    groupe("Réunion, après l'appel : relecture de tout l'enregistrement")
    do {
        let p = [PassageParole(debut: 10, fin: 20), PassageParole(debut: 20.5, fin: 28), PassageParole(debut: 60, fin: 90), PassageParole(debut: 95, fin: 140)]
        let lots = RelectureReunion.lots(p, locuteur: .eux, duree: 300, marge: 0.3, ecartFusion: 1, dureeMax: 120)
        verifier(lots.allSatisfy { $0.locuteur == .eux && $0.duree <= 120.001 }, "chaque lot : une seule voix, deux minutes au plus (\(lots.map { Int($0.duree) }))")
        verifier(lots.first?.passages.first == PassageParole(debut: 9.7, fin: 28.3), "deux passages à moins d'une seconde n'en font qu'un, élargi de 0,3 s de chaque côté")
        let total = lots.flatMap(\.passages).reduce(0) { $0 + $1.duree }
        verifier(abs(total - (18.6 + 30.6 + 45.6)) < 0.01, "les silences entre passages ne partent pas (\(total) s de son au lieu de 130 s d'appel)")
        let long = RelectureReunion.lots([PassageParole(debut: 0, fin: 300)], locuteur: .moi, duree: 300, marge: 0)
        verifier(long.count == 3 && long.map(\.duree) == [120, 120, 60], "un monologue de 5 minutes : coupé en lots de 2 minutes")
        verifier(RelectureReunion.lots([], locuteur: .moi, duree: 10).isEmpty, "rien entendu : aucun lot")

        let lot = LotRelecture(locuteur: .eux, passages: [PassageParole(debut: 100, fin: 110), PassageParole(debut: 200, fin: 205)])
        verifier(lot.duree == 10 + LotRelecture.silence + 5, "le son d'un lot : les passages bout à bout, un court silence entre eux")
        verifier(lot.versReunion(0) == 100 && lot.versReunion(4) == 104 && lot.versReunion(10.3) == 110 && lot.versReunion(10 + LotRelecture.silence + 2) == 202,
                 "une heure du son du lot ramenée à l'heure de la réunion (le silence ajouté compte pour la fin du passage d'avant)")
        verifier(lot.versReunion(999) == 205, "au-delà du lot : sa fin")

        let json = #"{"text":" Bonjour. Merci.","segments":[{"start":0.0,"end":2.4,"text":" Bonjour, on commence ?","no_speech_prob":0.01},{"start":10.6,"end":13.0,"text":" Merci d'avoir regardé cette vidéo.","no_speech_prob":0.2},{"start":11.0,"end":14.9,"text":" Le 2 décembre, c'est bon.","no_speech_prob":0.05},{"start":3,"end":4,"text":"  ","no_speech_prob":0.9}]}"#
        let phrases = RelectureReunion.analyser(Data(json.utf8))
        verifier(phrases?.count == 4 && phrases?.first == PhraseWhisper(debut: 0, fin: 2.4, texte: "Bonjour, on commence ?", pasDeParole: 0.01), "réponse verbose_json : phrases horodatées lues")
        verifier(RelectureReunion.analyser(Data(#"{"text":"Un seul texte.","duration":3.5}"#.utf8)) == [PhraseWhisper(debut: 0, fin: 3.5, texte: "Un seul texte.")], "réponse sans phrases : une seule, tout le son")
        verifier(RelectureReunion.analyser(Data("pas du json".utf8)) == nil, "réponse illisible : nil")
        let segs = RelectureReunion.segments(phrases ?? [], lot: lot)
        verifier(segs.map(\.texte) == ["Bonjour, on commence ?", "Le 2 décembre, c'est bon."], "phrases vides et « fantômes » de Whisper retirées (\(segs.map(\.texte)))")
        verifier(segs.first?.debut == 100 && segs.last.map { $0.debut == 200.4 && abs($0.fin - 204.3) < 0.001 } == true && segs.allSatisfy { $0.locuteur == .eux }, "les passages relus portent l'heure de la réunion et la voix du lot")

        // repli : un lot en échec garde le direct, un lot relu le remplace
        let l1 = LotRelecture(locuteur: .moi, passages: [PassageParole(debut: 0, fin: 30)]), l2 = LotRelecture(locuteur: .moi, passages: [PassageParole(debut: 100, fin: 130)])
        let direct = [s(1, 10, .moi, "direct un"), s(101, 110, .moi, "direct deux"), s(400, 410, .moi, "direct hors lot")]
        let relus = [s(1, 9, .moi, "relu un")]
        let a = RelectureReunion.assembler(relus: relus, direct: direct, lots: [l1, l2], echoues: [1])
        verifier(a.map(\.texte) == ["relu un", "direct deux", "direct hors lot"], "relecture assemblée : le relu, le direct d'un lot en échec, le direct qu'aucun lot ne couvre (\(a.map(\.texte)))")
        verifier(RelectureReunion.assembler(relus: relus, direct: direct, lots: [l1, l2], echoues: []).map(\.texte) == ["relu un", "direct hors lot"], "tout relu : le direct des lots relus disparaît")
        verifier(RelectureReunion.passages(de: [s(5, 5.2, .moi, "oui"), s(8, 12, .eux, "non")], locuteur: .moi) == [PassageParole(debut: 5, fin: 6)], "« Refaire la note » : les passages retrouvés dans la transcription (une seconde au moins)")

        // les tours relus : regroupés, mais l'heure revient (pas une seule ligne de cinq minutes)
        let tours = (0..<10).map { i in s(Double(i * 10), Double(i * 10 + 9), .eux, "Phrase \(i).") }
        let g = FusionPistes.regrouper(tours, dureeMax: RelectureReunion.tourMax)
        verifier(g.count == 3 && g.allSatisfy { $0.fin - $0.debut <= RelectureReunion.tourMax }, "un long tour relu reste en lignes de 45 s au plus (\(g.count) lignes)")
        verifier(FusionPistes.regrouper([s(0, 4, .eux, "A."), SegmentReunion(debut: 5, fin: 8, locuteur: .eux, texte: "B.", orateur: "eux-2")]).count == 2, "deux orateurs d'une même piste ne sont jamais recollés")
    }

    groupe("Réunion, après l'appel : « Note en préparation… »")
    do {
        verifier(PreparationNote.progresRelecture(fait: 0, sur: 8) == 0 && PreparationNote.progresRelecture(fait: 4, sur: 8) == 0.35 && PreparationNote.progresRelecture(fait: 8, sur: 8) == PreparationNote.partRelecture,
                 "la relecture avance lot par lot jusqu'à 70 %")
        verifier(PreparationNote.progresRedaction(fait: 0, sur: 3) == 0.7 && PreparationNote.progresRedaction(fait: 3, sur: 3) < 1 && PreparationNote.progresRedaction(fait: 3, sur: 3) > 0.9,
                 "la rédaction va de 70 % à 97 % (100 % seulement quand la note est prête)")
        verifier(PreparationNote.pourcent(0.344) == "34\u{202F}%" && PreparationNote.pourcent(1.4) == "100\u{202F}%", "pourcentage à la française, borné")
        verifier(PreparationNote.etapes == [PreparationNote.relecture, PreparationNote.redaction], "deux étapes : la relecture de tout l'appel, puis le résumé")
        let a = AnnonceReunion.prepare(etape: PreparationNote.relecture, progres: 0.34)
        verifier(a.vue == .reunionPrepare && a != .prepare(etape: PreparationNote.relecture, progres: 0.5), "l'annonce porte sa progression (l'îlot se redessine quand elle avance)")
        let p = GeoIlot.valeurs(.reunionPrepare, hauteurBarre: 33), b = GeoIlot.valeurs(.reunionPrete, hauteurBarre: 33)
        verifier(p[2] > b[2] && p[2] - 33 >= 88 - 0.5, "« Note en préparation… » a la place de sa barre (88 pt sous la barre des menus)")
    }

    groupe("Réunion, la note : sujets, décisions, prochaines étapes")
    do {
        let json = """
        {"titre": "Lancement de la boutique en ligne", "en_bref": "La page d'accueil est validée, le site sort le 2 décembre.",
         "sujets": [{"titre": "Page d'accueil", "puces": [{"texte": "Claire valide la maquette", "sous": ["On garde le vert de la marque"]}, "Les avis clients passent sous les photos"]},
                    {"titre": "Date", "puces": [{"texte": "Mise en ligne le 2 décembre chez Dupont", "sous": []}]},
                    {"titre": "Vide", "puces": []}],
         "decisions": [{"quoi": "Mise en ligne le 2 décembre", "quand": "textes avant le 25"}],
         "actions": [{"qui": "Moi", "quoi": "Écrire les fiches produits", "quand": "lundi"}], "participants": ["Claire"]}
        """
        let n = NoteReunion.analyser(json)
        verifier(n?.sujets.count == 2 && n?.sujets.first?.puces == [PuceReunion(texte: "Claire valide la maquette", sous: ["On garde le vert de la marque"]), PuceReunion(texte: "Les avis clients passent sous les photos")],
                 "sujets lus : titre, puces (objet ou texte), détails ; un sujet sans puce est ignoré")
        let segments = [s(10, 20, .eux, "Bon, Claire ici, la page d'accueil me va, on garde le vert de la marque. Les avis clients sous les photos."),
                        s(30, 40, .eux, "La mise en ligne le 2 décembre, à condition d'avoir les textes avant le 25."), s(50, 55, .moi, "Je m'occupe des fiches produits lundi.")]
        let propre = GardeInvention(segments: segments).nettoyer(n ?? NoteBrute())
        verifier(propre.note.sujets.count == 1 && propre.note.sujets[0].titre == "Page d'accueil" && propre.retraits.contains { $0.contains("Dupont") },
                 "garde : une puce qui invente un nom est retirée, un sujet vidé disparaît (\(propre.retraits))")
        var r = Reunion(debut: debut, duree: 1740, segments: segments, etat: .prete)
        NoteReunion.appliquer(propre.note, a: &r, segments: segments, calendrier: cal)
        verifier(r.sujets?.count == 1 && r.dit.isEmpty && r.enBref?.hasPrefix("La page") == true && r.participants == ["Moi", "Claire"], "appliquer : sujets, phrase d'ouverture, participants")
        verifier(r.actions.first?.echeance == "2026-11-16", "prochaine étape : « lundi » devient le lundi 16 novembre")
        verifier(ArchiveReunions.decoder(ArchiveReunions.encoder(r)!) == r, "JSON aller-retour avec sujets")
        verifier(NoteReunion.consigneNote.contains("2 à 5 mots") && NoteReunion.consigneNote.contains("sous") && NoteReunion.consigneNote.contains("commence par un verbe"), "consigne : titres de sujets courts, détails, étapes qui commencent par un verbe")

        r.points = [45]
        let md = ReunionMarkdown.rendre(r, calendrier: cal)
        verifier(md.contains("## Résumé par sujet\n\n### Page d'accueil\n\n- Claire valide la maquette\n  - On garde le vert de la marque\n- Les avis clients"), "Markdown : sujets en titres, puces et détails imbriqués")
        verifier(md.contains("## Décisions\n\n- Mise en ligne le 2 décembre (textes avant le 25)") && md.contains("## Prochaines étapes\n\n- [ ] **Moi** : Écrire les fiches produits (lun. 16 nov.)"),
                 "Markdown : décisions (avec leur condition) et prochaines étapes à cocher (qui, quand en vraie date)")
        verifier(md.contains("## Points marqués pendant l'appel\n\n- 14:02, juste après") && md.contains("*Point marqué · 14:02*"), "Markdown : le point ajouté pendant l'appel, dans sa section et dans la transcription")
        verifier(md.contains("**Eux** · 14:02\nBon, Claire ici") && md.contains("**Moi**\nJe m'occupe"), "Markdown : l'orateur à chaque ligne, l'heure à la première ligne de chaque minute")
    }

    groupe("Réunion, la note : transcription et orateurs")
    do {
        var r = Reunion(debut: debut, duree: 300, participants: ["Moi"],
                        actions: [ActionReunion(qui: "Eux", quoi: "Réserver la séance")],
                        segments: [s(5, 9, .eux, "Bonjour."), s(20, 25, .moi, "Salut."), s(58, 70, .eux, "On y va."), s(61, 62, .moi, "Oui."), s(130, 140, .moi, "Merci.")])
        r.points = [59, 400]
        let e = LignesTranscription.elements(r, calendrier: cal)
        verifier(e == [.passage(index: 0, heure: "14:02"), .passage(index: 1, heure: nil), .passage(index: 2, heure: nil), .point(59), .passage(index: 3, heure: "14:03"), .passage(index: 4, heure: "14:04"), .point(400)],
                 "transcription : l'heure à la première ligne de chaque minute ; les points marqués à leur place, ceux d'après la fin en bas (\(e))")
        verifier(e.filter { if case .passage(_, let h) = $0 { return h != nil } else { return false } }.count == 3, "trois minutes différentes : trois heures affichées")
        verifier(r.orateursEntendus.map(\.nom) == ["Eux", "Moi"] && r.orateur(de: r.segments[0]).id == "eux", "orateurs : celui de chaque piste par défaut (Eux, Moi), dans l'ordre où ils parlent")
        r.renommer(orateur: "eux", en: "  Claire ")
        verifier(r.orateur(de: r.segments[0]).nom == "Claire" && r.orateur(de: r.segments[2]).nom == "Claire" && r.segments[0].orateur == nil, "renommer « Eux » en Claire : chaque passage suit (il ne garde que l'identifiant)")
        verifier(r.actions[0].qui == "Claire" && r.participants == ["Moi", "Claire"], "les prochaines étapes et participants qui portaient l'ancien nom suivent")
        verifier(ReunionMarkdown.rendre(r, calendrier: cal).contains("**Claire** · 14:02\nBonjour."), "l'export prend le nouveau nom")
        r.renommer(orateur: "eux", en: "")
        verifier(r.orateur(de: r.segments[0]).nom == "Eux", "un nom vide rend le nom de la piste")
        verifier(ArchiveReunions.decoder(ArchiveReunions.encoder(r)!) == r, "JSON aller-retour avec les orateurs")
        let ancien = #"{"id":"6F1C2C1E-0000-4000-8000-000000000002","debut":"2026-11-09T10:00:00Z","duree":10,"titre":"","participants":[],"dit":[],"decisions":[],"actions":[],"segments":[{"id":"6F1C2C1E-0000-4000-8000-000000000003","debut":1,"fin":2,"locuteur":"eux","texte":"Oui."}],"etat":"prete","avertissements":[],"sonGarde":false}"#
        let v = ArchiveReunions.decoder(Data(ancien.utf8))
        verifier(v?.sujets == nil && v?.orateurs == nil && v?.relue == nil && v.map { $0.orateur(de: $0.segments[0]).nom } == "Eux", "une ancienne réunion (sans sujets ni orateurs) se lit toujours")
        verifier(ListeReunions.correspond(r, requete: "bonjour") && !ListeReunions.correspond(r, requete: "photos"), "la recherche lit aussi la transcription")
        var avecSujets = r; avecSujets.sujets = [SujetReunion(titre: "Photos", puces: [PuceReunion(texte: "Une séance à l'atelier")])]
        verifier(ListeReunions.correspond(avecSujets, requete: "atelier photos"), "la recherche lit les sujets")
    }

    groupe("Réunion, « Demander »")
    do {
        let r = Reunion(debut: debut, duree: 900, titre: "Boutique", segments: [s(0, 5, .eux, "La page me va."), s(120, 130, .eux, "Je réserve la séance photo avant le 20."), s(200, 205, .moi, "Parfait.")])
        let m = QuestionReunion.message("Qui s'occupe des photos ?", reunion: r, calendrier: cal)
        verifier(m.contains("[2] 14:04 Eux : Je réserve la séance photo avant le 20.") && m.hasSuffix("Question : Qui s'occupe des photos ?"), "le message : la transcription numérotée (heure, orateur), puis la question")
        let court = QuestionReunion.message("photo", reunion: r, maxCaracteres: 60, calendrier: cal)
        verifier(court.contains("[2] ") && !court.contains("[1] "), "transcription trop longue : on garde les lignes qui parlent de la question, avec leur vrai numéro")
        verifier(QuestionReunion.analyser(#"{"reponse": "Inès, avant le 20.", "passage": 2}"#, passages: 3) == QuestionReunion.Reponse(texte: "Inès, avant le 20.", passage: 1), "réponse : texte et passage (numéro → rang)")
        verifier(QuestionReunion.analyser(#"{"reponse": "Oui.", "passage": 9}"#, passages: 3)?.passage == nil && QuestionReunion.analyser(#"{"reponse": "Oui.", "passage": "2"}"#, passages: 3)?.passage == 1,
                 "un numéro qui n'existe pas n'est jamais gardé ; un numéro en texte est lu")
        verifier(QuestionReunion.analyser("rien", passages: 3) == nil && QuestionReunion.analyser(#"{"reponse": ""}"#, passages: 3) == nil, "réponse vide ou illisible : nil")
        verifier(QuestionReunion.consigne.contains(QuestionReunion.rien) && QuestionReunion.consigne.contains("N'invente"), "consigne : pas d'invention, phrase exacte quand rien ne répond")
        var a = r; a.enBref = "Séance photo avant le 20."
        let (t, n) = QuestionReunion.messageToutes("Quand ?", reunions: [a, r], calendrier: cal)
        verifier(n == 2 && t.contains("[R1] Boutique") && t.contains("En bref : Séance photo") && !t.contains("Je réserve la séance"), "« Demander à mes réunions » : les notes numérotées, jamais les transcriptions")
        verifier(QuestionReunion.messageToutes("Quand ?", reunions: [a, r], maxCaracteres: 130, calendrier: cal).nombre == 1, "trop de réunions : les plus récentes d'abord, tant qu'elles tiennent")
        verifier(QuestionReunion.analyserToutes(#"{"reponse": "Le 2.", "reunion": 1}"#, nombre: 2)?.reunion == 0 && QuestionReunion.analyserToutes(#"{"reponse": "Le 2.", "reunion": 7}"#, nombre: 2)?.reunion == nil,
                 "la réponse renvoie à une réunion qui existe, sinon à aucune")
    }
}
