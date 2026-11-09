import AppKit
import SwiftUI
import DicteeCore

/// `Dictee --rendu-journee dossier` : l'onglet Journée (chargée, calme, heure ouverte, étroite, premier jour, week-end, sans dictée) en PNG,
/// sans fenêtre, ni micro, ni clavier. Les données sont des exemples écrits ici (jamais l'historique de l'utilisateur) ; « maintenant »
/// est fixé au lundi 9 novembre 2026, 18 h 30, pour que les rendus soient les mêmes d'un jour à l'autre.
enum RenduJournee {
    static let cal = Calendar.current

    static func date(_ jour: Int, _ mois: Int = 11, _ h: Int = 12, _ m: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: mois, day: jour, hour: h, minute: m))!
    }
    static let maintenant = date(9, 11, 18, 30)

    // MARK: exemples

    static let apps: [String: String] = [
        "Mail": "com.apple.mail", "Claude": "com.anthropic.claudefordesktop", "Messages": "com.apple.MobileSMS",
        "WhatsApp": "net.whatsapp.WhatsApp", "Notes": "com.apple.Notes",
    ]
    static let debuts: [String: [String]] = [
        "Mail": ["Bonjour Anaïs, je te renvoie le devis avec la remise dont on a parlé.", "Merci pour votre retour, je vous envoie le récapitulatif avant jeudi.",
                 "Je vous confirme le rendez-vous de jeudi à dix heures.", "Bonjour Madame Martin, suite à notre échange de ce matin, je vous transmets la proposition."],
        "Claude": ["Reprends le tableau des factures, ajoute une colonne pour la date de relance et trie par montant.", "Résume-moi ce document en cinq points, sans jargon.",
                   "Écris-moi une relance polie pour un client qui n'a pas répondu."],
        "Messages": ["Je suis en route, j'arrive dans quinze minutes.", "On se voit mercredi pour parler du devis et du planning."],
        "WhatsApp": ["J'arrive dans dix minutes, commande-moi un café.", "Tu peux me rappeler quand tu as une minute ?"],
        "Notes": ["Penser à envoyer la proposition avant jeudi.", "Idée : proposer deux options chiffrées au lieu d'une seule."],
    ]
    static let suites = [
        "Je reste disponible demain pour en discuter et ajuster le calendrier si besoin.", "Dis-moi si cela te convient et je prépare la suite avec les délais et les conditions.",
        "Le point important est de garder la même base pour les deux options, afin de pouvoir comparer simplement.", "Je t'envoie le détail dans la journée avec les pièces jointes dont on a parlé.",
        "Si tu préfères, on peut aussi en parler de vive voix en fin de semaine, quand tout le monde aura relu.",
    ]

    /// Un texte de `mots` mots exactement, qui commence par `debut`.
    static func texte(_ debut: String, mots: Int) -> String {
        var m = debut.split(separator: " ").map(String.init)
        var i = 0
        while m.count < mots { m += suites[i % suites.count].split(separator: " ").map(String.init); i += 1 }
        m = Array(m.prefix(max(1, mots)))
        var t = m.joined(separator: " ")
        if let dernier = t.last, !".!?".contains(dernier) { t = t.trimmingCharacters(in: CharacterSet(charactersIn: ",;:")) + "." }
        return t
    }

    /// Une dictée : le temps de parole est de 2,9 mots par seconde.
    static func entree(_ jour: Int, _ mois: Int = 11, _ h: Int, _ min: Int, _ app: String, _ mots: Int, debut: Int = 0, insere: Bool = true) -> EntreeHistorique {
        let choix = debuts[app] ?? ["Bonjour."]
        return EntreeHistorique(date: date(jour, mois, h, min), appId: apps[app], appNom: app, texte: texte(choix[debut % choix.count], mots: mots),
                                insere: insere, dureeParole: Double(mots) / 2.9)
    }

    /// Les 4 120 mots d'aujourd'hui (pic de 700 mots à 10 h), répartis comme la maquette (Mail 1 480, Claude 1 150, Messages 640, WhatsApp 480, Notes 370).
    static func aujourdhui() -> [EntreeHistorique] {
        var e: [EntreeHistorique] = []
        // 10 h : onze dictées, 700 mots
        let dix: [(Int, String, Int)] = [(2, "Mail", 58), (8, "Notes", 7), (15, "Claude", 94), (21, "Mail", 63), (34, "Messages", 11), (41, "Claude", 62),
                                         (44, "Mail", 110), (49, "Claude", 95), (52, "Mail", 82), (55, "Notes", 60), (58, "Messages", 58)]
        for (i, d) in dix.enumerated() { e.append(entree(9, 11, 10, d.0, d.1, d.2, debut: [0, 0, 0, 1, 1, 1, 3, 2, 2, 1, 0][i])) }
        let autres: [Int: [(String, Int)]] = [
            8: [("Mail", 150)], 9: [("Mail", 200), ("Notes", 120), ("Claude", 100)], 11: [("Mail", 260), ("Claude", 200), ("Messages", 100)],
            12: [("WhatsApp", 90)], 13: [("Messages", 130), ("WhatsApp", 100)], 14: [("Mail", 200), ("Claude", 220), ("Messages", 100)],
            15: [("Mail", 150), ("Claude", 170), ("Notes", 100), ("WhatsApp", 50)], 16: [("Mail", 107), ("Claude", 109), ("Messages", 141), ("WhatsApp", 100), ("Notes", 43)],
            17: [("Mail", 100), ("Claude", 100), ("Messages", 100), ("WhatsApp", 140), ("Notes", 40)],
        ]
        for (h, liste) in autres.sorted(by: { $0.key < $1.key }) {
            var minute = 3
            for (k, (app, mots)) in liste.enumerated() {
                var reste = mots
                while reste > 0 {
                    let n = min(reste, 90)
                    e.append(entree(9, 11, h, minute % 60, app, n, debut: k + minute)); reste -= n; minute += 9
                }
            }
        }
        return e
    }

    /// Un jour passé : `mots` répartis sur trois dictées (9 h, 11 h, 15 h).
    static func jourPasse(_ jour: Int, _ mois: Int = 11, mots: Int, app: String = "Mail") -> [EntreeHistorique] {
        let parts = [mots * 4 / 10, mots * 35 / 100]
        let rest = mots - parts[0] - parts[1]
        return [entree(jour, mois, 9, 12, app, max(1, parts[0])), entree(jour, mois, 11, 40, app, max(1, parts[1]), debut: 1), entree(jour, mois, 15, 5, app, max(1, rest), debut: 2)]
    }

    /// Les jours d'avant : 14 jours actifs de moyenne 2 980 mots, série de 11 jours, meilleure journée jeudi 5 novembre (4 640).
    static func joursAvant(sauf: Set<Int> = []) -> [EntreeHistorique] {
        let jours: [(Int, Int, Int)] = [(8, 11, 100), (7, 11, 640), (6, 11, 2_600), (5, 11, 4_640), (4, 11, 3_300), (3, 11, 2_850), (2, 11, 3_600), (1, 11, 1_500),
                                        (31, 10, 800), (30, 10, 3_900), (28, 10, 4_500), (27, 10, 4_400), (26, 10, 4_500), (25, 10, 4_390)]
        return jours.filter { !($0.1 == 11 && sauf.contains($0.0)) }.flatMap { jourPasse($0.0, $0.1, mots: $0.2, app: $0.2 > 3_000 ? "Mail" : "Claude") }
    }

    @MainActor static func store(_ entrees: [EntreeHistorique]) -> HistoriqueStore {
        let s = HistoriqueStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("dictee-rendu-journee-\(UUID().uuidString).json"))
        for e in entrees { s.ajouter(e) }
        return s
    }

    @MainActor static func reunionsStore(_ reunions: [Reunion]) -> ReunionStore {
        let s = ReunionStore(dossier: FileManager.default.temporaryDirectory.appendingPathComponent("dictee-rendu-journee-reunions-\(UUID().uuidString)"), lire: false)
        for r in reunions { s.enregistrer(r) }
        return s
    }

    static func reunionsAujourdhui() -> [Reunion] {
        let brume = Reunion(debut: date(9, 11, 9, 15), duree: 32 * 60, titre: "Point devis Brume", participants: ["Anaïs Morel"], dit: ["Brume valide les deux options."],
                            decisions: ["Brume signe vendredi au plus tard."],
                            actions: [ActionReunion(quoi: "Envoyer la proposition chiffrée", quand: "demain", echeance: "2026-11-10"),
                                      ActionReunion(quoi: "Relancer Brume pour signer", quand: "demain", echeance: "2026-11-10"),
                                      ActionReunion(quoi: "Faire valider le devis par Anaïs", fait: true, echeance: "2026-11-09")],
                            etat: .prete, enBref: "Brume valide les deux options, décision attendue vendredi.")
        let planning = Reunion(debut: date(9, 11, 15, 30), duree: 48 * 60, titre: "Revue du planning", dit: ["Novembre tient."],
                               actions: [ActionReunion(quoi: "Mettre à jour le planning", quand: "jeudi", echeance: "2026-11-12"),
                                         ActionReunion(quoi: "Valider le budget d\u{2019}hiver", quand: "vendredi", echeance: "2026-11-13"),
                                         ActionReunion(quoi: "Réserver la salle du 20", quand: "lundi", echeance: "2026-11-16"),
                                         ActionReunion(quoi: "Prévenir l\u{2019}équipe du décalage", fait: true, echeance: "2026-11-09")],
                               etat: .prete, enBref: "Novembre tient, la salle du 20 reste à réserver.")
        return [brume, planning]
    }

    // MARK: rendu

    @MainActor
    static func executer(dossier: String) -> Int32 {
        _ = NSApplication.shared
        Polices.enregistrer()
        print("Newsreader disponible : \(Polices.newsreaderDisponible)")
        let url = URL(fileURLWithPath: (dossier as NSString).expandingTildeInPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var ok = true
        let grande = CGSize(width: 1190, height: 850)   // fenêtre de 1 110 × 770, comme la maquette

        func rendre(_ nom: String, historique: [EntreeHistorique], reunions: [Reunion] = [], jour: Date? = nil, heure: Int? = nil, depliee: Int? = nil,
                    maintenant: Date = RenduJournee.maintenant, taille: CGSize = grande, titre: String? = nil) {
            let h = store(historique), r = reunionsStore(reunions)
            let d = ModeleDictees(store: h); d.nomDestination = { "Mail" }
            let rm = ReunionsModele(store: r)
            let m = JourneeModele(dictees: d, reunions: rm, horloge: { maintenant })
            if let jour { m.jour = m.calendrier.startOfDay(for: jour) }
            if let heure { m.heureOuverte = heure }
            if let depliee { let l = m.dicteesOuvertes; if l.indices.contains(depliee) { m.depliee = l[depliee].id } }
            let nav = NavigationFenetre(); nav.onglet = .journee
            let mots = MotsModele(persistant: false, mots: [], raccourcis: [], propositions: { var p = PropositionsMots(); _ = p.proposer("Brume", motsConnus: []); return p }())
            let barre = AnyView(HStack(spacing: 0) { BarreOngletsVue(nav: nav, mots: mots).padding(.leading, 68); Spacer(); BarreReglagesVue(nav: nav).padding(.trailing, 20) })
            let vue = RenduFenetre.Cadre(taille: taille, barre: barre) {
                FenetreVue(nav: nav, dictees: d, store: h, mots: mots, reglages: ReglagesModele(reel: false), reunions: rm,
                           controleur: ReunionController(store: r), journee: m, curseurFactice: true)
            }
            print("\(nom) : \(m.vue.phrase.cas.rawValue) — \(m.vue.phrase.texte)")
            ok = RenduVues.ecrire(RenduVues.png(vue, taille: taille), url.appendingPathComponent("\(nom).png")) && ok
        }

        let chargee = joursAvant() + aujourdhui()
        rendre("journee-1-chargee", historique: chargee, reunions: reunionsAujourdhui())
        rendre("journee-1b-chargee-page-entiere", historique: chargee, reunions: reunionsAujourdhui(), taille: CGSize(width: 1190, height: 1130))
        // journée calme : vendredi 6 novembre, 420 mots seulement (les autres jours comme avant)
        let calme = joursAvant(sauf: [6]) + jourPasse(6, mots: 420, app: "Notes") + aujourdhui()
        rendre("journee-2-calme", historique: calme, jour: date(6))
        rendre("journee-3-heure-ouverte", historique: chargee, reunions: reunionsAujourdhui(), heure: 10)
        rendre("journee-3b-heure-ouverte-depliee", historique: chargee, reunions: reunionsAujourdhui(), heure: 10, depliee: 2)
        rendre("journee-4-etroite", historique: chargee, reunions: reunionsAujourdhui(), taille: CGSize(width: 780, height: 1500))
        rendre("journee-4b-etroite-heure-ouverte", historique: chargee, reunions: reunionsAujourdhui(), heure: 10, taille: CGSize(width: 780, height: 1000))
        rendre("journee-5-premier-jour", historique: aujourdhui(), reunions: [])
        rendre("journee-6-weekend", historique: chargee, jour: date(7))
        rendre("journee-7-sans-dictee", historique: joursAvant(), reunions: [],
               maintenant: date(10, 11, 8, 30))
        rendre("journee-8-fenetre-par-defaut", historique: chargee, reunions: reunionsAujourdhui(), taille: CGSize(width: 1040, height: 720))
        return ok ? 0 : 1
    }
}
