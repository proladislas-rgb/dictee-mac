import AppKit
import DicteeCore

// Les rendus de la voix d'un rappel ou d'une note (maquette ilot-voix-rappel.html) : dans l'encoche (`--rendu-ilot`, ilot-34*) et dans le
// verre de la Lucarne (`--rendu-lucarne`, lucarne-ecran-voix-*, par le catalogue de la Lucarne). Des exemples génériques (dépôt public).

@MainActor
enum RenduVoix {
    /// Une voix factice : des syllabes, des mots plus ou moins forts, une petite pause (l'enveloppe de la maquette), 0…1.
    static func voixFactice(_ t: Double) -> Double {
        let syllabe = abs(sin(t * 9.6 + 1.7 * sin(t * 2.3)))
        let mot = 0.62 + 0.38 * sin(t * 2.1 + 0.4) * sin(t * 0.9 + 1)
        return min(1, max(0, (0.18 + 0.82 * pow(syllabe, 0.75)) * mot * 0.85))
    }

    /// L'écoute posée sur le moteur : 3 s de voix factice dans l'onde, l'onde figée à cet instant (relâchée : 0,6 s plus tard).
    static func poserEcoute(_ m: IlotMoteur, genre: GenreVoix?, relachee: Bool = false) {
        var o = OndeVoix()
        let fin = 3.0
        for k in 0...Int(fin / OndeVoix.pas) { o.recevoir(voixFactice(Double(k) * OndeVoix.pas), a: Double(k) * OndeVoix.pas) }
        if relachee { o.relacher(a: fin) }
        m.voix.onde = o
        m.voix.instantFige = relachee ? fin + 0.6 : fin
        m.voix.genre = genre
        m.montrerEcouteVoix()
    }

    static let idRappel = UUID(), idNote = UUID()
    static let noteExemple = "Montrer le prix dès la première page, avec trois exemples de clients."

    /// La carte d'un rappel (« demain · 13:00 » vu à 14:32 la veille) ou de la note de la maquette, et l'état de son bouton.
    static func poserCarte(_ m: IlotMoteur, _ genre: GenreVoix, t0: Date, envoi: EnvoiVoix = .aEnvoyer, copie: Bool = false) {
        if genre == .rappel {
            let demain13 = Calendar.current.date(bySettingHour: 13, minute: 0, second: 0, of: t0.addingTimeInterval(86_400))!
            m.preparerCarteVoix(CarteVoix.rappel(id: idRappel, texte: "La livraison", echeance: demain13,
                                                 phrase: "Lucarne, rappelle-moi demain à 13 h pour la livraison.", maintenant: t0))
            m.voix.envoiRappel = envoi
        } else {
            m.notes = [NoteRapide(id: idNote, texte: noteExemple, date: t0)]
            switch envoi {
            case .enCours: m.envoisNotes[idNote] = .enCours
            case .fait: m.envoisNotes[idNote] = .fait
            case .refuse: m.envoisNotes[idNote] = .refuse
            case .echec: m.envoisNotes[idNote] = .echec
            case .aEnvoyer: m.envoisNotes[idNote] = nil
            }
            m.preparerCarteVoix(CarteVoix.note(id: idNote, texte: noteExemple))
        }
        m.voix.copie = copie
        m.bandeau = BandeauIlot(vue: .voixCarte, jusqua: t0.addingTimeInterval(60), ligne1: m.voix.carte?.titre ?? "", ligne2: "")
    }

    /// Une scène des rendus de l'encoche : son nom, la hauteur du bureau sous la barre, clair ou sombre, l'état posé, et (images à
    /// mi-course) le changement suivi de la durée écoulée.
    struct Scene {
        var nom: String
        var hauteur: CGFloat
        var clair = true
        var poser: (IlotMoteur) -> Void
        var ensuite: (changer: (IlotMoteur) -> Void, t: Double)?
    }

    /// 34 · la voix (maquette, étapes 1 à 7) : l'onde, « Rappel… », l'attente, la carte du rappel, « ✓ Dans Rappels », la note, « ✓ Dans
    /// Notes », le refus ; le morphing de l'écoute vers la carte à mi-course ; le fond sombre ; les épaules (batterie, écouteurs).
    static func scenes(t0: Date) -> [Scene] {
        let batterie = EnergieIlot(pourcent: 64, secteur: false, enCharge: false)
        let airpods = AppareilIlot(nom: "AirPods Pro", genre: .ecouteurs, gauche: 80, droit: 78, etui: 45)
        func epaules(_ m: IlotMoteur) { m.energie = batterie; m.ecouteurs = airpods }
        return [
            Scene(nom: "ilot-34a-voix-1-l-onde-suit-la-voix", hauteur: 70) { poserEcoute($0, genre: nil) },
            Scene(nom: "ilot-34b-voix-2-rappel-compris", hauteur: 95) { poserEcoute($0, genre: .rappel) },
            Scene(nom: "ilot-34c-voix-fn-relachee-l-onde-se-calme", hauteur: 95) { poserEcoute($0, genre: .rappel, relachee: true) },
            Scene(nom: "ilot-34d-voix-morphing-vers-la-carte-120ms", hauteur: 160, poser: { epaules($0); poserEcoute($0, genre: .rappel, relachee: true) },
                  ensuite: ({ poserCarte($0, .rappel, t0: t0) }, 0.12)),
            Scene(nom: "ilot-34e-voix-morphing-vers-la-carte-260ms", hauteur: 160, poser: { epaules($0); poserEcoute($0, genre: .rappel, relachee: true) },
                  ensuite: ({ poserCarte($0, .rappel, t0: t0) }, 0.26)),
            Scene(nom: "ilot-34f-voix-3-carte-du-rappel", hauteur: 160) { epaules($0); poserCarte($0, .rappel, t0: t0) },
            Scene(nom: "ilot-34g-voix-4-dans-rappels", hauteur: 160) { epaules($0); poserCarte($0, .rappel, t0: t0, envoi: .fait) },
            Scene(nom: "ilot-34h-voix-rappels-acces-refuse", hauteur: 160) { epaules($0); poserCarte($0, .rappel, t0: t0, envoi: .refuse) },
            Scene(nom: "ilot-34i-voix-5-note-comprise", hauteur: 95) { poserEcoute($0, genre: .note) },
            Scene(nom: "ilot-34j-voix-6-carte-de-la-note", hauteur: 160) { epaules($0); poserCarte($0, .note, t0: t0) },
            Scene(nom: "ilot-34k-voix-7-dans-notes-et-copie", hauteur: 160) { epaules($0); poserCarte($0, .note, t0: t0, envoi: .fait, copie: true) },
            Scene(nom: "ilot-34l-voix-envoi-en-cours", hauteur: 160) { poserCarte($0, .note, t0: t0, envoi: .enCours) },
            Scene(nom: "ilot-34m-voix-carte-du-rappel-sombre", hauteur: 160, clair: false) { epaules($0); poserCarte($0, .rappel, t0: t0) },
            Scene(nom: "ilot-34n-voix-rappel-compris-sombre", hauteur: 95, clair: false) { poserEcoute($0, genre: .rappel) },
            Scene(nom: "ilot-34o-voix-notes-n-a-pas-repondu-reessayer", hauteur: 160) { epaules($0); poserCarte($0, .note, t0: t0, envoi: .echec) },
        ]
    }

    /// Les écrans de la voix dans le verre de la Lucarne (le catalogue les pose ; `--rendu-lucarne` les dessine) : nom du catalogue, nom
    /// du fichier, place (maquette, étapes 8 et 9 : un coin du haut, un coin du bas au-dessus du Dock).
    static let lucarne: [(String, String, PlaceLucarne)] = [
        ("voix : l'onde et « Rappel… »", "voix-onde-rappel", .hautDroite), ("voix : la carte du rappel", "voix-carte-rappel", .hautDroite),
        ("voix : l'onde et « Note… »", "voix-onde-note", .basDroite), ("voix : la carte de la note envoyée", "voix-carte-note", .basDroite),
    ]
}

/// Les écrans de la voix pour le catalogue de la Lucarne (l'essai les pose depuis chaque place et vérifie que rien n'est coupé).
@MainActor
enum CatalogueVoix {
    static func ecrans(t0: Date) -> [CatalogueLucarne.Ecran] {
        [
            CatalogueLucarne.Ecran(nom: "voix : l'onde et « Rappel… »", vue: .voixEcoute) { RenduVoix.poserEcoute($0, genre: .rappel) },
            CatalogueLucarne.Ecran(nom: "voix : la carte du rappel", vue: .voixCarte) { RenduVoix.poserCarte($0, .rappel, t0: t0) },
            CatalogueLucarne.Ecran(nom: "voix : l'onde et « Note… »", vue: .voixEcoute) { RenduVoix.poserEcoute($0, genre: .note) },
            CatalogueLucarne.Ecran(nom: "voix : la carte de la note envoyée", vue: .voixCarte) { RenduVoix.poserCarte($0, .note, t0: t0, envoi: .fait) },
        ]
    }
}
