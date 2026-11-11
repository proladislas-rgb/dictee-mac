import Foundation
import DicteeCore

/// Contrôles de la réunion dans l'îlot (maquette design/maquettes/ilot-reunion.html) : la réunion comme activité, ses annonces, la carte et
/// sa largeur, le direct (ordre, tours, échos, reprises, gris), son défilement, « Ce que j'ai raté », les points marqués.
func controlesReunionIlot() {
    func s(_ d: Double, _ f: Double, _ l: Locuteur, _ t: String) -> SegmentReunion { SegmentReunion(debut: d, fin: f, locuteur: l, texte: t) }

    groupe("Réunion dans l'îlot : une activité, plus un masque")
    do {
        var e = EtatIlot(); e.reunion = true
        let r = ArbitrageIlot.resoudre(e)
        verifier(r.principal == .reunionCompact && r.survol == .reunionEtendu && !r.verrou, "réunion seule : le point rouge et le temps ; au survol, la carte")
        e.minuteur = true
        verifier(ArbitrageIlot.resoudre(e).principal == .reunionCompact && ArbitrageIlot.resoudre(e).pastille == .minuteur, "réunion + minuteur : la réunion garde l'îlot, le minuteur va dans la bulle")
        e.minuteur = false; e.lecture = true
        verifier(ArbitrageIlot.resoudre(e).pastille == .lecture, "réunion + vidéo : la vidéo va dans la bulle")
        e.lecture = false; e.microCoupe = true
        verifier(ArbitrageIlot.resoudre(e).principal == .reunionCompact && ArbitrageIlot.resoudre(e).pastille == .micro, "réunion + micro coupé : le micro rouge reste visible, dans la bulle")
        var a = EtatIlot(); a.annonceReunion = .reunionPropose; a.lecture = true
        let ra = ArbitrageIlot.resoudre(a)
        verifier(ra.principal == .reunionPropose && ra.verrou && ra.survol == nil && ra.pastille == .lecture, "« Noter cet appel ? » : l'annonce a l'îlot, attend un geste, la vidéo en bulle")
        var al = EtatIlot(); al.reunion = true; al.alerte = .minuteurFini
        verifier(ArbitrageIlot.resoudre(al).principal == .minuteurFini && ArbitrageIlot.resoudre(al).pastille == .reunion, "minuteur fini pendant la réunion : l'alerte, la réunion dans la bulle")
        verifier(CartesIlot.pile(survol: .reunionEtendu) == [.reunionEtendu, .centre, .dictees, .accueil], "la carte de la réunion, puis le Centre, les Dictées, l'accueil")
        verifier(!CartesIlot.aUnPied(.reunionEtendu, pile: CartesIlot.pile(survol: .reunionEtendu)) && CartesIlot.piedEnPlus(.reunionEtendu, pile: CartesIlot.pile(survol: .reunionEtendu)) == 0,
                 "la carte de la réunion n'a pas de pied (« Centre » est dans son en-tête)")
        verifier([VueIlot.reunionPropose, .reunionPrepare, .reunionPrete, .reunionMessage].allSatisfy { $0.estAnnonceReunion && GeoIlot.ajusteAuContenu($0) && !$0.estBandeau },
                 "les annonces de la réunion épousent leur contenu, leur fin vient de la réunion (pas un bandeau passager)")
        verifier(GeoIlot.aEpaules(.reunionEtendu) && GeoIlot.valeurs(.reunionEtendu, hauteurBarre: 32)[1] == GeoIlot.valeurs(.centre, hauteurBarre: 32)[1], "la carte a la largeur du Centre (on passe de l'une à l'autre sans élargir) et ses épaules")
        for (barre, demi) in [(32.0, 100.0), (33.0, 89.5), (37.0, 92.0)] {
            for v in [VueIlot.reunionCompact, .reunionEtendu] {
                let p = TraceIlot.calculer(GeoIlot.valeurs(v, hauteurBarre: barre, demiCamera: demi, epaules: true), demiCamera: demi, barre: barre)
                verifier(p.bande <= demi + GeoIlot.aileMax + 0.001, "\(v.rawValue) (caméra \(Int(2 * demi))) : \(String(format: "%.1f", p.bande - demi)) pt de chaque côté de la caméra, ≤ 66")
            }
        }
        verifier(FormatIlot.chrono(4) == "0:04" && FormatIlot.chrono(761) == "12:41" && FormatIlot.chrono(3733) == "1:02:13", "le temps : 0:04, 12:41, 1:02:13")
        var ri = ReunionIlot(); ri.duree = 100; ri.depuis = Date(timeIntervalSince1970: 1000)
        verifier(abs(ri.temps(a: Date(timeIntervalSince1970: 1061)) - 161) < 0.001, "le temps avance depuis la reprise")
        ri.depuis = nil; ri.enPause = true
        verifier(ri.temps(a: Date(timeIntervalSince1970: 5000)) == 100, "en pause : le temps est figé")
        verifier(AnnonceReunion.propose(app: "Zoom").vue == .reunionPropose && AnnonceReunion.prete(id: UUID(), titre: "", duree: 0, sansNote: false).vue == .reunionPrete,
                 "chaque annonce a son écran")
    }

    groupe("Réunion : le direct (ordre, tours, échos, reprises)")
    do {
        // l'ordre : un long tour de « Eux » transcrit APRÈS la réponse de « Moi » qui l'a suivi
        let l = DirectReunion.lignes(moi: [s(20, 23, .moi, "D'accord, on garde le vert.")], eux: [s(2, 18, .eux, "Bon, la page d'accueil me va.")])
        verifier(l.map(\.locuteur) == [.eux, .moi], "ordre du DÉBUT des passages, pas de leur arrivée")
        // un tour coupé en deux morceaux : une seule ligne
        let t = DirectReunion.lignes(moi: [], eux: [s(0, 10, .eux, "Pour la mise en ligne, le 2 décembre"), s(10.5, 16, .eux, "c'est faisable de mon côté.")])
        verifier(t.count == 1 && t[0].texte == "Pour la mise en ligne, le 2 décembre c'est faisable de mon côté.", "un tour coupé par le découpage : une seule ligne (\(t.map(\.texte)))")
        let deux = DirectReunion.lignes(moi: [], eux: [s(0, 5, .eux, "Bonjour."), s(12, 15, .eux, "Vous m'entendez ?")])
        verifier(deux.count == 2, "plus de 3 s de silence : deux lignes")
        // la reprise de Whisper (le contexte répété en tête du morceau suivant)
        verifier(FusionPistes.sansReprise("le 2 décembre, c'est faisable de mon côté.", apres: "Pour la mise en ligne, le 2 décembre") == "le 2 décembre, c'est faisable de mon côté.",
                 "3 mots repris seulement : gardés (ça peut être voulu)")
        verifier(FusionPistes.sansReprise("Pour la mise en ligne, le 2 décembre, c'est faisable de mon côté.", apres: "Pour la mise en ligne, le 2 décembre.") == "C'est faisable de mon côté.",
                 "la phrase précédente répétée en tête : retirée, majuscule remise (\(FusionPistes.sansReprise("Pour la mise en ligne, le 2 décembre, c'est faisable de mon côté.", apres: "Pour la mise en ligne, le 2 décembre.")))")
        verifier(FusionPistes.sansReprise("à condition d'avoir tous les textes", apres: "c'est faisable à condition d'avoir tous les textes") == "", "un morceau qui n'est qu'une reprise : vide")
        verifier(FusionPistes.sansReprise("On en reparle lundi.", apres: "Je t'envoie les fiches produits lundi.") == "On en reparle lundi.", "rien de repris : intact")
        let rep = DirectReunion.lignes(moi: [], eux: [s(0, 9, .eux, "Je réserve la séance avant le 20."), s(9.5, 14, .eux, "Je réserve la séance avant le 20. Et je vous dis le jour demain.")])
        verifier(rep.count == 1 && rep[0].texte == "Je réserve la séance avant le 20. Et je vous dis le jour demain.", "reprise retirée dans le direct (\(rep.map(\.texte)))")
        let redit = DirectReunion.lignes(moi: [s(10, 13, .moi, "Oui, je m'en charge."), s(40, 43, .moi, "Oui, je m'en charge.")], eux: [s(20, 30, .eux, "Et les photos, qui s'en occupe ?")])
        verifier(redit.count == 3 && redit.last?.texte == "Oui, je m'en charge.", "la même réponse redite plus tard : gardée (seuls deux morceaux qui se suivent comptent)")
        // l'écho : « Moi » répète « Eux » (haut-parleurs)
        let eux = [s(20, 30, .eux, "Alors le prix reste le point sensible pour mon associé.")]
        let echo = [s(21, 31, .moi, "alors le prix reste le point sensible pour mon associé")]
        verifier(DirectReunion.lignes(moi: echo, eux: eux).map(\.locuteur) == [.eux], "l'écho de « Eux » dans le micro : retiré du direct")
        // l'écho ne peut pas encore être jugé : gris
        let douteux = DirectReunion.lignes(moi: echo, eux: [], attentes: [AttenteDirect(locuteur: .eux, debut: 20, fin: 30)])
        verifier(douteux.first { $0.locuteur == .moi }?.enAttente == true, "« Moi » pendant un passage de « Eux » pas encore transcrit : gris (peut-être un écho)")
        let sur = DirectReunion.lignes(moi: [s(40, 44, .moi, "Je vous envoie la proposition jeudi.")], eux: eux, attentes: [AttenteDirect(locuteur: .eux, debut: 46)])
        verifier(sur.first { $0.locuteur == .moi }?.morceaux.allSatisfy(\.sur) == true, "« Moi » loin de ce qui attend : blanc")
        // ce qui s'entend encore
        let suite = DirectReunion.lignes(moi: [], eux: [s(0, 8, .eux, "Pour la mise en ligne,")], attentes: [AttenteDirect(locuteur: .eux, debut: 9)])
        verifier(suite.count == 1 && suite[0].suite, "la voix parle encore : « … » gris au bout de sa ligne")
        let nouvelle = DirectReunion.lignes(moi: [s(0, 4, .moi, "Bonjour à tous.")], eux: [], attentes: [AttenteDirect(locuteur: .eux, debut: 6)])
        verifier(nouvelle.count == 2 && nouvelle[1].locuteur == .eux && nouvelle[1].morceaux.isEmpty && nouvelle[1].enAttente, "quelqu'un d'autre commence : une ligne grise « … »")
        let parEcho = DirectReunion.lignes(moi: [], eux: [], attentes: [AttenteDirect(locuteur: .eux, debut: 6), AttenteDirect(locuteur: .moi, debut: 6.4)])
        verifier(parEcho.map(\.locuteur) == [.eux], "le micro qui entend « Eux » (écho) n'ajoute pas de « Moi … »")
        // les points marqués, à leur place
        let pts = DirectReunion.lignes(moi: [s(0, 4, .moi, "Bonjour.")], eux: [s(10, 14, .eux, "Le 2 décembre.")], points: [8])
        verifier(pts.map { $0.estPoint } == [false, true, false] && pts[1].texte == "0:08", "« Point ajouté · 0:08 » entre les deux tours")
        verifier(DirectReunion.lignes(moi: (0..<60).map { s(Double($0 * 10), Double($0 * 10 + 4), .moi, "Phrase \($0).") }, eux: []).count <= DirectReunion.maxLignes, "le direct garde les 40 dernières lignes")
        // identité stable : la ligne qui grandit garde son id (pas de clignotement)
        let a1 = DirectReunion.lignes(moi: [], eux: [s(3, 8, .eux, "Bon,")]), a2 = DirectReunion.lignes(moi: [], eux: [s(3, 8, .eux, "Bon,"), s(8.5, 12, .eux, "ça me va.")])
        verifier(a1[0].id == a2[0].id, "une ligne qui s'allonge garde son identité")
        // la transcription finale profite des mêmes corrections
        let fin = FusionPistes.transcription(moi: [], eux: [s(0, 9, .eux, "Je réserve la séance avant le 20."), s(9.5, 14, .eux, "Je réserve la séance avant le 20. Et je vous dis le jour demain.")])
        verifier(fin.segments.count == 1 && fin.segments[0].texte == "Je réserve la séance avant le 20. Et je vous dis le jour demain.", "transcription finale : la reprise aussi retirée")
        let dm = DirectReunion.dernieresMinutes(moi: [s(10, 14, .moi, "Ancien.")], eux: [s(400, 410, .eux, "Récent.")], maintenant: 420)
        verifier(dm.map(\.texte) == ["Récent."], "« Ce que j'ai raté » : seulement les 3 dernières minutes")
    }

    groupe("Réunion : défilement du direct")
    do {
        var d = DefilementDirect()
        verifier(d.suit, "au départ : la liste suit les nouvelles phrases")
        d.contenuAjoute(40, cache: 200)
        verifier(d.suit && d.decalage == 0, "une phrase arrive pendant qu'on suit : on reste en bas")
        d.defiler(60, cache: 200)
        verifier(!d.suit && d.decalage == 60, "on remonte : la liste s'arrête")
        d.contenuAjoute(42, cache: 242)
        verifier(d.decalage == 102, "une phrase arrive pendant qu'on relit : ce qu'on lit reste en place")
        d.defiler(500, cache: 242)
        verifier(d.decalage == 242, "on ne remonte pas plus haut que le début")
        d.defiler(-1000, cache: 242)
        verifier(d.suit, "redescendu en bas : la liste suit de nouveau")
        d.defiler(30, cache: 0)
        verifier(d.suit, "tout tient dans la zone : rien ne défile")
        d.defiler(30, cache: 100); d.revenirEnBas()
        verifier(d.suit, "« Revenir en bas » : la liste suit")
    }

    groupe("Réunion : « Ce que j'ai raté » et points marqués")
    do {
        verifier(RattrapageReunion.analyser("{\"puces\": [\"Claire valide la page.\", \"- Marc : le 2 décembre.\", \"\", \"Tu envoies les fiches lundi.\", \"Une de trop.\"]}")
                    == ["Claire valide la page.", "Marc : le 2 décembre.", "Tu envoies les fiches lundi."], "trois puces au plus, vides et tirets retirés")
        verifier(RattrapageReunion.analyser("pas du json") == nil && RattrapageReunion.analyser("{\"puces\": []}") == nil, "réponse inexploitable : nil")
        let longue = String(repeating: "mot ", count: 60)
        verifier((RattrapageReunion.analyser("{\"puces\": [\"\(longue)\"]}")?.first?.count ?? 999) <= RattrapageReunion.maxCaracteres + 1, "une puce trop longue est coupée au mot")
        verifier(RattrapageReunion.message([s(0, 4, .moi, "Bonjour.")]).contains("[00:00] Moi : Bonjour."), "le message : la transcription des dernières minutes, rien d'autre")
        verifier(RattrapageReunion.consigne.contains("N'invente rien") && RattrapageReunion.fenetre == 180, "consigne sans invention, fenêtre de 3 minutes")
        var r = Reunion(debut: Date(timeIntervalSince1970: 0), duree: 60, segments: [s(2, 9, .eux, "il faut tous les textes avant le 25 novembre")])
        r.points = [12]
        let md = ReunionMarkdown.rendre(r, calendrier: { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }())
        verifier(md.contains("## Points marqués pendant l'appel") && md.contains("00:00, juste après « …les textes avant le 25 novembre »"), "un point marqué apparaît dans l'export de la note")
        let ancien = #"{"id":"6F1C2C1E-0000-4000-8000-000000000001","debut":"2026-11-09T10:00:00Z","duree":10,"titre":"","participants":[],"dit":[],"decisions":[],"actions":[],"segments":[],"etat":"prete","avertissements":[],"sonGarde":false}"#
        verifier(ArchiveReunions.decoder(Data(ancien.utf8)).map { $0.points == nil } == true, "une ancienne réunion (sans points) se lit toujours")
    }
}
