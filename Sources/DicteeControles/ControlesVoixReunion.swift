import Foundation
import DicteeCore

/// Contrôles des voix séparées (diarisation sur le Mac, FluidAudio) : les tours de parole posés sur les passages de la transcription,
/// les voix minuscules fondues, le repli sur « Eux », le renommage dans toute la note, l'empreinte gardée, la progression.
func controlesVoixReunion() {
    func s(_ d: Double, _ f: Double, _ l: Locuteur = .eux, _ t: String = "texte") -> SegmentReunion { SegmentReunion(debut: d, fin: f, locuteur: l, texte: t) }
    func t(_ v: String, _ d: Double, _ f: Double) -> TourDeParole { TourDeParole(voix: v, debut: d, fin: f) }

    groupe("Voix séparées : les tours de parole posés sur la transcription")
    do {
        let segs = [s(0, 4, .eux, "Bonjour à tous."), s(4.5, 9, .moi, "Salut."), s(9.2, 15, .eux, "Les machines arrivent mardi."),
                    s(15.3, 20, .eux, "D'accord, c'est noté."), s(21, 26, .eux, "On relance vendredi.")]
        let voix = VoixSeparees(tours: [t("S7", 0.3, 4.1), t("S2", 9.0, 15.1), t("S7", 15.4, 19.8), t("S2", 21.2, 25.5)],
                                empreintes: ["S7": [1, 0, 0], "S2": [0, 1, 0]])
        let a = SeparationVoix.attribuer(segs, voix: voix)
        verifier(a.segments.map(\.orateur) == ["p1", nil, "p2", "p1", "p2"], "chaque passage « Eux » prend la voix qui le recouvre ; « Moi » n'est pas touché (\(a.segments.map { $0.orateur ?? "-" }))")
        verifier(a.orateurs.map(\.nom) == ["Personne 1", "Personne 2"] && a.orateurs.allSatisfy { $0.piste == .eux }, "les voix numérotées dans l'ordre où elles parlent (S7 parle d'abord : Personne 1)")
        verifier(a.orateurs.first?.empreinte == [1, 0, 0] && a.orateurs.last?.empreinte == [0, 1, 0], "l'empreinte de chaque voix est gardée avec son orateur")
        verifier(a.segments.map(\.texte) == segs.map(\.texte) && a.segments.map(\.debut) == segs.map(\.debut), "le texte et les heures ne changent pas")

        // un passage à cheval sur deux voix : la plus longue gagne
        let cheval = SeparationVoix.attribuer([s(0, 10), s(10, 20), s(20, 22)], voix: VoixSeparees(tours: [t("A", 0, 3), t("B", 3, 12), t("A", 12, 22)]))
        verifier(cheval.segments.map(\.orateur) == ["p1", "p2", "p2"], "un passage à cheval sur deux voix va à celle qui le recouvre le plus (\(cheval.segments.map { $0.orateur ?? "-" }))")

        // les horodatages de Whisper et du séparateur ne coïncident pas : un passage entre deux tours prend le plus proche
        let proche = SeparationVoix.attribuer([s(0, 5), s(6.0, 6.6), s(10, 15), s(40, 42)], voix: VoixSeparees(tours: [t("A", 0, 5), t("B", 7, 15)]))
        verifier(proche.segments.map(\.orateur) == ["p1", "p2", "p2", nil], "aucun recouvrement : le tour le plus proche à 1,5 s près ; au-delà, « Eux » (\(proche.segments.map { $0.orateur ?? "-" }))")

        // une voix minuscule (un rire, un bout de voix déformée) est fondue dans une vraie voix
        let petite = SeparationVoix.attribuer([s(0, 10), s(10, 11), s(11, 20), s(20, 30)],
                                              voix: VoixSeparees(tours: [t("A", 0, 10), t("Z", 10, 11), t("B", 11, 20), t("A", 20, 30)]))
        verifier(petite.orateurs.count == 2 && !petite.segments.contains { $0.orateur == "p3" }, "une voix de moins de 3 s en tout n'en fait pas une personne de plus (\(petite.orateurs.map(\.nom)))")
        verifier(petite.segments[1].orateur != nil, "son passage va à une vraie voix (la plus proche)")

        // repli
        let une = SeparationVoix.attribuer([s(0, 10), s(12, 20)], voix: VoixSeparees(tours: [t("A", 0, 20)]))
        verifier(!une.separees && une.segments.allSatisfy { $0.orateur == nil }, "une seule voix trouvée : « Eux », comme avant")
        let vide = SeparationVoix.attribuer([s(0, 10)], voix: VoixSeparees(tours: []))
        verifier(!vide.separees && vide.segments.first?.orateur == nil, "aucun tour (son muet) : « Eux »")
        var deja = s(0, 10); deja.orateur = "p4"
        verifier(SeparationVoix.attribuer([deja], voix: VoixSeparees(tours: [])).segments.first?.orateur == nil, "« Refaire la note » sans voix : l'ancien orateur ne reste pas collé")
        let moiSeul = SeparationVoix.attribuer([s(0, 5, .moi), s(6, 9, .moi)], voix: VoixSeparees(tours: [t("A", 0, 5), t("B", 6, 9)]))
        verifier(!moiSeul.separees && moiSeul.segments.allSatisfy { $0.orateur == nil }, "la piste « Moi » n'est jamais séparée")
    }

    groupe("Voix séparées : noms, renommage dans toute la note")
    do {
        verifier(SeparationVoix.rang(id: "p3") == 3 && SeparationVoix.rang(id: "eux") == nil && SeparationVoix.rang(id: "p") == nil && SeparationVoix.rang(id: "p0") == nil, "« p3 » est la 3e voix ; « eux », « p », « p0 » n'en sont pas")
        verifier(SeparationVoix.estNomParDefaut("Personne 2") && SeparationVoix.estNomParDefaut("Eux") && !SeparationVoix.estNomParDefaut("Claire") && !SeparationVoix.estNomParDefaut("Personne"),
                 "« Personne 2 » et « Eux » sont des noms donnés par Verbe, pas « Claire »")
        var r = Reunion(duree: 60)
        r.segments = [s(0, 5, .moi, "On commence ?"), SegmentReunion(debut: 5, fin: 9, locuteur: .eux, texte: "Oui.", orateur: "p1"),
                      SegmentReunion(debut: 9, fin: 14, locuteur: .eux, texte: "Je vous envoie le devis.", orateur: "p2"),
                      SegmentReunion(debut: 14, fin: 18, locuteur: .eux, texte: "Merci.", orateur: "p12")]
        r.orateurs = [OrateurReunion(id: "p1", nom: "Personne 1", piste: .eux), OrateurReunion(id: "p2", nom: "Personne 2", piste: .eux, empreinte: [0.5, 0.5])]
        verifier(r.orateur(id: "p12").nom == "Personne 12", "une voix sans fiche s'appelle quand même « Personne 12 »")
        r.enBref = "Personne 2 envoie le devis, Personne 12 remercie."
        r.sujets = [SujetReunion(titre: "Devis de Personne 2", puces: [PuceReunion(texte: "Personne 2 l'envoie demain.", sous: ["Personne 1 est d'accord."])])]
        r.decisions = ["Devis validé par Personne 2"]
        r.actions = [ActionReunion(qui: "Personne 2", quoi: "Envoyer le devis (Personne 2)"), ActionReunion(qui: "Moi", quoi: "Relire")]
        r.participants = ["Moi"]
        r.renommer(orateur: "p2", en: "  Claire ")
        verifier(r.orateur(de: r.segments[2]).nom == "Claire" && r.orateur(de: r.segments[1]).nom == "Personne 1", "renommer « Personne 2 » : ses passages suivent, pas ceux des autres")
        verifier(r.enBref == "Claire envoie le devis, Personne 12 remercie." && r.sujets?.first?.titre == "Devis de Claire"
                 && r.sujets?.first?.puces.first?.texte == "Claire l'envoie demain." && r.decisions == ["Devis validé par Claire"],
                 "le nouveau nom partout dans la note, mot entier (« Personne 12 » n'est pas touché) : \(r.enBref ?? "")")
        verifier(r.actions.first?.qui == "Claire" && r.actions.first?.quoi == "Envoyer le devis (Claire)" && r.actions.last?.qui == "Moi", "les prochaines étapes suivent")
        verifier(r.participants.contains("Claire"), "« Claire » rejoint les participants")
        verifier(r.orateurs?.first { $0.id == "p2" }?.empreinte == [0.5, 0.5], "l'empreinte reste attachée à la voix renommée")
        verifier(ReunionMarkdown.rendre(r).contains("**Claire**") && !ReunionMarkdown.rendre(r).contains("**Personne 2**"), "l'export Markdown porte le nouveau nom")
        r.renommer(orateur: "p2", en: "")
        verifier(r.orateur(id: "p2").nom == "Personne 2" && r.enBref?.hasPrefix("Personne 2 envoie") == true, "un nom vide rend « Personne 2 », dans toute la note")
        var e = Reunion(duree: 60)
        e.segments = [s(0, 5, .eux, "Eux aussi viennent.")]
        e.enBref = "Eux aussi viennent jeudi."
        e.renommer(orateur: "eux", en: "Paul")
        verifier(e.enBref == "Eux aussi viennent jeudi." && e.orateur(id: "eux").nom == "Paul", "renommer « Eux » ne touche pas le mot « Eux » dans le texte")
        verifier(NomDansLeTexte.remplacer("Personne 1", par: "Léa", dans: "Personne 1, Personne 10 et Personne 1.") == "Léa, Personne 10 et Léa.", "remplacement en mot entier seulement")

        // ce que lit la rédaction de la note
        let lignes = DecoupeReunion.texte(r.segments)
        verifier(lignes.contains("] Personne 1 : Oui.") && lignes.contains("] Personne 2 : Je vous envoie") && lignes.contains("] Moi : On commence"),
                 "la rédaction lit « Personne 1 », « Personne 2 » (jamais le nom donné ensuite)")
        verifier(DecoupeReunion.nomsDesVoix(r.segments) == ["Personne 1", "Personne 2", "Personne 12"], "les noms des voix présentes, pour la garde contre l'invention")
        let garde = GardeInvention(segments: r.segments, motsConnus: DecoupeReunion.nomsDesVoix(r.segments))
        let n = garde.nettoyer(NoteBrute(titre: "", dit: [], decisions: [], actions: [ActionReunion(qui: "Personne 2", quoi: "Envoyer le devis")], participants: []))
        verifier(n.note.actions.first?.qui == "Personne 2", "« qui » : « Personne 2 » est accepté par la garde (\(n.retraits))")
        var avant = r; avant.orateurs = [OrateurReunion(id: "p1", nom: "Personne 1", piste: .eux)]
        var actuelle = avant; actuelle.renommer(orateur: "p1", en: "Marc")
        let gardee = ArchiveReunions.garderLesModifications(de: actuelle, depuis: avant, dans: avant)
        verifier(gardee.orateur(id: "p1").nom == "Marc", "renommée pendant la préparation de la note : le nom est gardé")
    }

    groupe("Voix séparées : empreintes (voix connue, pour plus tard)")
    do {
        verifier(abs(SeparationVoix.ressemblance([1, 0], [1, 0]) - 1) < 1e-9 && abs(SeparationVoix.ressemblance([1, 0], [0, 1])) < 1e-9
                 && SeparationVoix.ressemblance([1], [1, 2]) == 0 && SeparationVoix.ressemblance([0, 0], [1, 0]) == 0, "ressemblance : cosinus, 0 si incomparables")
        let connues = [VoixConnue(nom: "Claire", empreinte: [1, 0, 0]), VoixConnue(nom: "Marc", empreinte: [0, 1, 0])]
        verifier(SeparationVoix.reconnaitre([0.9, 0.1, 0], parmi: connues)?.nom == "Claire" && SeparationVoix.reconnaitre([0.5, 0.5, 0.7], parmi: connues) == nil,
                 "une voix proche est reconnue ; une voix entre deux, pas")
        let o = OrateurReunion(id: "p1", nom: "Personne 1", piste: .eux, empreinte: [0.25, -1])
        let json = try? JSONEncoder().encode(o)
        verifier(json.flatMap { try? JSONDecoder().decode(OrateurReunion.self, from: $0) } == o, "l'empreinte s'enregistre avec la réunion")
        let ancien = #"{"id":"eux","nom":"Claire","piste":"eux"}"#
        verifier((try? JSONDecoder().decode(OrateurReunion.self, from: Data(ancien.utf8)))?.empreinte == nil, "les notes d'avant se lisent toujours (sans empreinte)")
    }

    groupe("Voix séparées : mesure de justesse (son fabriqué)")
    do {
        let verite = [t("Thomas", 0, 10), t("Amélie", 10, 20), t("Thomas", 20, 30)]
        verifier(abs(SeparationVoix.justesse(trouves: [t("S1", 0, 10), t("S2", 10, 20), t("S1", 20, 30)], verite: verite) - 1) < 1e-9, "tout juste : 100 %")
        verifier(abs(SeparationVoix.justesse(trouves: [t("S1", 0, 30)], verite: verite) - 2.0 / 3) < 1e-9, "une seule voix trouvée pour deux : 2/3")
        verifier(abs(SeparationVoix.justesse(trouves: [t("S1", 0, 10), t("S2", 10, 20)], verite: verite) - 2.0 / 3) < 1e-9, "un tour manqué compte comme faux")
        let segs = [SegmentReunion(debut: 0, fin: 1, locuteur: .eux, texte: "a", orateur: "p1"), SegmentReunion(debut: 1, fin: 2, locuteur: .eux, texte: "b", orateur: "p2"),
                    SegmentReunion(debut: 2, fin: 3, locuteur: .eux, texte: "c", orateur: "p1"), SegmentReunion(debut: 3, fin: 4, locuteur: .eux, texte: "d")]
        verifier(SeparationVoix.passagesJustes(segs, vraies: ["T", "A", "T", "T"]) == 0.75, "passages au bon orateur : 3 sur 4 (celui resté « Eux » est faux)")
    }

    groupe("Voix séparées : la progression de la note (relecture et voix en même temps)")
    do {
        var a = AvancementNote(separation: true)
        verifier(a.progres == 0 && a.etape == PreparationNote.relecture, "au départ : relecture, 0")
        a.telechargement(0.5)
        verifier(a.etape == PreparationNote.telechargementVoix, "premier usage : le téléchargement du modèle se voit (\(a.etape))")
        let p1 = a.progres
        a.relecture = 0.5
        a.separation(0)
        verifier(a.etape == PreparationNote.relecture && a.progres >= p1, "téléchargement fini : retour à la relecture, la barre ne recule pas")
        a.relectureFinie = true
        verifier(a.etape == PreparationNote.voix, "relecture finie, voix pas encore : « Séparation des voix »")
        a.separation(1); a.voixFinie = true
        verifier(abs(a.progres - PreparationNote.partRelecture) < 1e-9 && a.etape == PreparationNote.redaction, "les deux finies : \(PreparationNote.pourcent(PreparationNote.partRelecture)), la rédaction prend la suite")
        var sans = AvancementNote(separation: false)
        sans.relecture = 0.5
        verifier(abs(sans.progres - PreparationNote.partRelecture * 0.5) < 1e-9 && sans.etape == PreparationNote.relecture, "sans séparation (micro seul) : la relecture seule fait la barre")
        verifier(PreparationNote.etapes.contains(PreparationNote.voix) && PreparationNote.etapes.contains(PreparationNote.telechargementVoix), "les étapes nouvelles comptent dans la largeur de l'annonce")
    }
}
