import AppKit
import SwiftUI
import DicteeCore

// Les annonces de l'îlot (bandeaux et alertes) et le rendez-vous déplié : ce qu'ils montrent est décrit UNE fois (`ContenuAnnonce`,
// `ContenuAgenda`), puis sert deux fois : à dessiner l'écran (IlotVues) et à mesurer sa largeur, que la forme épouse (comme la Dynamic
// Island : un « Fait » de deux mots fait une petite forme, un message long une grande ; jamais de texte collé à gauche devant du vide).

/// Ce qu'une annonce montre : [symbole] [titre / sous-titre] [à droite : rien, une heure, le temps du minuteur ou des pilules].
struct ContenuAnnonce {
    struct Bouton {
        var titre: String
        var icone: String? = nil
        var style: CapIlot.Style = .gris
        var etiquette: String? = nil
        var action: ActionIlot?
    }
    /// Une jauge de batterie (écouteur gauche, droit, étui).
    struct Jauge { var nom: String; var pourcent: Int; var etui = false }
    enum Droite {
        case rien
        case jauges([Jauge])
        case meta(String)
        /// Le temps restant du minuteur (il change chaque seconde ; mesuré sur la durée totale, le plus large).
        case temps
        case boutons([Bouton])
    }
    /// nil : la place est gardée pour la cloche qui voyage depuis l'aile.
    var glyphe: GlypheIlot?
    var l1: String
    var l2: String
    /// Une partie du sous-titre en blanc (l'heure du rappel).
    var fort: String? = nil
    var droite: Droite = .rien
    /// Le sous-titre en couleur (« Connectés » en vert).
    var couleurL2: Color? = nil
    /// À la place du symbole : des icônes du Finder (le fichier arrivé ; deux en pile pour une rafale), sur `coteSymbole` pt.
    var icones: [NSImage] = []
    var coteSymbole: CGFloat = ContenuAnnonce.cote
    /// Un nom de fichier se coupe au milieu (« Rapport-annuel…-v3.pdf » : on garde l'extension).
    var coupureL1: Text.TruncationMode = .tail
    /// Le fichier qu'on peut glisser hors du bandeau (icône et nom).
    var glisser: URL? = nil
    /// À la place du symbole : l'étoile de Claude (dessinée, en corail).
    var etoile = false
    /// Après les pilules : l'anneau qui se vide jusqu'à `fin` (« Remettre » des fichiers partis), sur `duree` secondes.
    var compte: (fin: Date, duree: TimeInterval)? = nil
    /// Après le texte : un rouet (l'envoi AirDrop attend la réponse du panneau de macOS).
    var attente = false
    static let coteCompte: CGFloat = 18, coteRouet: CGFloat = 22

    static let cote: CGFloat = 26, espace: CGFloat = 12, espaceBoutons: CGFloat = 8, espaceJauges: CGFloat = 8
    /// L'icône d'un fichier : 38 pt, presque la hauteur des deux lignes (maquette ilot-apple.html, « Téléchargé »).
    static let coteIcone: CGFloat = 38
    static let interlettreL1: CGFloat = -0.2
    static let policeMeta = Font.system(size: 13, weight: .semibold).monospacedDigit()
    static let policeTemps = Font.system(size: 15, weight: .semibold).monospacedDigit()

    var texteL2: Text {
        guard let fort, let r = l2.range(of: fort) else { return Text(l2) }
        return Text(String(l2[..<r.lowerBound])) + Text(fort).foregroundColor(.white) + Text(String(l2[r.upperBound...]))
    }
}

/// Le rendez-vous déplié : symbole, titre, plage horaire, lien ou lieu, puis la rangée d'actions.
enum ContenuAgenda {
    /// Le texte commence après le symbole (26 pt + 12).
    static let retrait: CGFloat = 38
    static func boutons(_ e: EvenementAgenda) -> [ContenuAnnonce.Bouton] {
        var b: [ContenuAnnonce.Bouton] = []
        if e.lien != nil { b.append(.init(titre: "Rejoindre", icone: "video.fill", style: .vert, action: .rendezVousRejoindre(e))) }
        b.append(.init(titre: "Noter la réunion", icone: "note.text", action: .rendezVousNoter(e)))
        return b
    }
    static func ligneLieu(_ e: EvenementAgenda) -> String { e.lien.map { ($0.host ?? "") + $0.path } ?? e.lieu ?? "" }
}

/// Mesures au point près avec les polices de l'îlot (Core Text, comme SwiftUI), arrondies vers le haut : un texte mesuré ne finit
/// jamais en « … ».
enum MesureIlot {
    static func texte(_ s: String, _ taille: CGFloat, _ poids: NSFont.Weight, chiffres: Bool = false, interlettre: CGFloat = 0) -> CGFloat {
        guard !s.isEmpty else { return 0 }
        let f = chiffres ? NSFont.monospacedDigitSystemFont(ofSize: taille, weight: poids) : NSFont.systemFont(ofSize: taille, weight: poids)
        return ceil((s as NSString).size(withAttributes: [.font: f, .kern: interlettre]).width) + 1
    }
    static func symbole(_ nom: String, _ taille: CGFloat, _ poids: NSFont.Weight = .semibold) -> CGFloat {
        let c = NSImage.SymbolConfiguration(pointSize: taille, weight: poids)
        return ceil(NSImage(systemSymbolName: nom, accessibilityDescription: nil)?.withSymbolConfiguration(c)?.size.width ?? taille)
    }
    /// Une pilule `CapIlot` de 32 pt.
    static func bouton(_ b: ContenuAnnonce.Bouton) -> CGFloat {
        texte(b.titre, 13.5, .semibold) + 28 + (b.icone.map { symbole($0, 13) + 6 } ?? 0)
    }
    static func boutons(_ bs: [ContenuAnnonce.Bouton], memeLargeur: Bool = false) -> CGFloat {
        guard !bs.isEmpty else { return 0 }
        let l = bs.map(bouton)
        let espaces = ContenuAnnonce.espaceBoutons * CGFloat(bs.count - 1)
        return (memeLargeur ? CGFloat(bs.count) * (l.max() ?? 0) : l.reduce(0, +)) + espaces
    }
}

extension IlotMoteur {
    var rappelVu: Rappel? { alerteVu?.rappel ?? rappelsSonnes.first ?? dernierRappel }
    var rdvVu: EvenementAgenda? { alerteVu?.evenement ?? rendezVous ?? dernierRendezVous }

    /// Ce que montre une annonce (nil si l'écran n'en est pas une).
    func contenuAnnonce(_ v: VueIlot) -> ContenuAnnonce? {
        let b = bandeauVu
        switch v {
        case .minuteurLance:
            return ContenuAnnonce(glyphe: GlypheIlot(nom: "timer", couleur: CouleursIlot.ambre, taille: 22),
                                  l1: b?.ligne1 ?? "Minuteur lancé", l2: b?.ligne2 ?? "", droite: .temps)
        case .minuteurFini:
            return ContenuAnnonce(glyphe: GlypheIlot(nom: "timer", couleur: CouleursIlot.ambre, taille: 22), l1: "Minuteur terminé",
                                  l2: (alerteVu?.libelle ?? "") + " \u{00B7} il est " + FormatIlot.heure(maintenant()),
                                  droite: .boutons([.init(titre: "Encore 5 min", action: .minuteurRecommencer(minutes: 5)),
                                                    .init(titre: "OK", style: .ambre, action: .alerteOK)]))
        case .rappelEtendu:
            let r = rappelVu, quand = r?.echeance ?? maintenant(), heure = FormatIlot.heure(quand)
            return ContenuAnnonce(glyphe: nil, l1: r?.texte ?? "",
                                  l2: "Rappel \u{00B7} " + heure + " \u{00B7} " + ListeRappels.retard(de: quand, maintenant: maintenant()), fort: heure,
                                  droite: .boutons([.init(titre: "Plus tard", etiquette: "Plus tard, dans 10 minutes", action: r.map { .rappelPlusTard($0.id) }),
                                                    .init(titre: "Fait", style: .jaune, action: r.map { .rappelFait($0.id) })]))
        case .rappelAjoute:
            return ContenuAnnonce(glyphe: GlypheIlot(nom: "bell.fill", couleur: CouleursIlot.jaune, taille: 21), l1: b?.ligne1 ?? "Rappel ajouté",
                                  l2: [b?.ligne2 ?? "", b?.meta ?? ""].filter { !$0.isEmpty }.joined(separator: " \u{00B7} "),
                                  droite: .boutons([.init(titre: "Annuler", action: b?.rappelId.map { .rappelAnnuler($0) })]))
        case .rappelFait:
            return ContenuAnnonce(glyphe: GlypheIlot(nom: "checkmark.circle.fill", couleur: CouleursIlot.vert, taille: 22), l1: b?.ligne1 ?? "Fait", l2: b?.ligne2 ?? "")
        case .rappelReporte:
            return ContenuAnnonce(glyphe: GlypheIlot(nom: "clock.arrow.circlepath", couleur: CouleursIlot.jaune, taille: 21), l1: b?.ligne1 ?? "",
                                  l2: b?.ligne2 ?? "", droite: (b?.meta ?? "").isEmpty ? .rien : .meta(b!.meta))
        case .agendaAvant:
            let e = rdvVu
            return ContenuAnnonce(glyphe: GlypheIlot(nom: GlypheIlot.calendrier, couleur: CouleursIlot.rouge, taille: 21), l1: b?.ligne1 ?? e?.titre ?? "",
                                  l2: b?.ligne2 ?? "", droite: e.map { .meta(FormatIlot.heure($0.debut)) } ?? .rien)
        case .agendaDebut:
            let e = rdvVu, visio = e?.lien != nil
            return ContenuAnnonce(glyphe: GlypheIlot(nom: GlypheIlot.calendrier, couleur: CouleursIlot.rouge, taille: 21),
                                  l1: (e?.titre ?? "") + " commence", l2: "Maintenant" + (visio ? " \u{00B7} Visio" : ""),
                                  droite: e.flatMap { e in visio ? .boutons([.init(titre: "Rejoindre", icone: "video.fill", style: .vert, action: .rendezVousRejoindre(e))]) : nil } ?? .rien)
        case .notification:
            guard let x = notifications.last else { return nil }
            return ContenuAnnonce(glyphe: Self.glypheApp(x.app), l1: x.titre.isEmpty ? x.app : x.titre, l2: x.corps.isEmpty ? x.app : x.corps, droite: .meta("maintenant"))
        case .notifications:
            return ContenuAnnonce(glyphe: GlypheIlot(nom: "bell.badge.fill", couleur: Color.white.opacity(0.85), taille: 21),
                                  l1: LectureNotifications.titreDeGroupe(max(2, notifications.count)), l2: LectureNotifications.ligneDeGroupe(notifications))
        case .appareil:
            guard let a = b?.appareil else { return nil }
            var js: [ContenuAnnonce.Jauge] = []
            if let g = a.gauche { js.append(.init(nom: "Gauche", pourcent: g)) }
            if let d = a.droit { js.append(.init(nom: "Droit", pourcent: d)) }
            if let e = a.etui { js.append(.init(nom: "Étui", pourcent: e, etui: true)) }
            if js.isEmpty, let u = a.unique { js.append(.init(nom: "Batterie", pourcent: u)) }
            let accord: String
            switch a.genre { case .ecouteurs: accord = "Connectés"; case .souris: accord = "Connectée"; default: accord = "Connecté" }
            return ContenuAnnonce(glyphe: GlypheIlot(nom: a.symbole, couleur: .white, taille: 22), l1: a.titre, l2: accord,
                                  droite: .jauges(js), couleurL2: CouleursIlot.vert)
        case .telecharge:
            guard let d = b?.telechargement, let premier = d.rafale.fichiers.first else { return nil }
            let seul = d.rafale.fichiers.count == 1
            return ContenuAnnonce(glyphe: nil, l1: d.rafale.titre, l2: d.rafale.sousTitre,
                                  droite: .boutons([.init(titre: seul ? "Ouvrir" : "Afficher", etiquette: seul ? "Ouvrir \(premier.nom)" : "Afficher dans le Finder",
                                                          action: .fichiersOuvrir(d.urls))]),
                                  icones: d.icones, coteSymbole: ContenuAnnonce.coteIcone, coupureL1: seul ? .middle : .tail, glisser: seul ? premier.url : nil)
        case .claudeEtendu:
            // l'étoile voyage depuis l'aile gauche (sa place est gardée) ; le projet, puis où en est la tâche
            let s = claude ?? dernierClaude
            return ContenuAnnonce(glyphe: nil, l1: s?.projet ?? "Claude Code", l2: Self.ligneClaude(s),
                                  droite: .boutons([.init(titre: "Ouvrir", etiquette: "Revenir à Claude Code", action: .claudeOuvrir(s?.app))]))
        case .claudeAttend:
            let s = b?.claude
            return ContenuAnnonce(glyphe: nil, l1: b?.ligne1 ?? "Claude attend ta réponse", l2: b?.ligne2 ?? s?.projet ?? "",
                                  droite: .boutons([.init(titre: "Ouvrir", etiquette: "Revenir à Claude Code", action: .claudeOuvrir(s?.app))]), etoile: true)
        case .claudeTermine:
            let s = b?.claude
            return ContenuAnnonce(glyphe: GlypheIlot(nom: "checkmark.circle.fill", couleur: CouleursIlot.vert, taille: 22), l1: b?.ligne1 ?? "Terminé",
                                  l2: b?.ligne2 ?? s?.projet ?? "",
                                  droite: .boutons([.init(titre: "Ouvrir", etiquette: "Revenir à Claude Code", action: .claudeOuvrir(s?.app))]))
        case .microEtendu:
            // le micro barré voyage depuis l'aile gauche (sa place est gardée) ; le nom du micro peut être long : coupé au bout
            return ContenuAnnonce(glyphe: nil, l1: "Micro coupé", l2: nomMicro ?? "Micro du Mac",
                                  droite: .boutons([.init(titre: "Rouvrir", icone: "mic.fill", etiquette: "Rouvrir le micro", action: .microRouvrir)]))
        case .etagerePartis:
            // « 3 fichiers partis dans Mail », « Remettre » et l'anneau qui se vide (maquette ilot-etagere-rapide.html, étapes 7 et 8)
            guard let b, let p = b.partis else { return nil }
            return ContenuAnnonce(glyphe: nil, l1: b.ligne1, l2: b.ligne2,
                                  droite: .boutons([.init(titre: "Remettre", etiquette: "Remettre " + (p.nombre == 1 ? "le fichier" : "les fichiers") + " sur l\u{2019}étagère",
                                                          action: .etagereRemettre)]),
                                  icones: p.icones, coteSymbole: 30, compte: (b.jusqua, p.duree))
        case .etagereEnvoi:
            // l'envoi AirDrop (étapes 4 et 5) : c'est le panneau de macOS qui choisit l'appareil ; l'îlot dit ce que le service répond
            guard let e = b?.envoi else { return nil }
            let quoi = e.noms.count == 1 ? e.noms[0] : "\(e.noms.count) fichiers"
            switch e.etat {
            case .enCours:
                return ContenuAnnonce(glyphe: GlypheIlot(nom: "doc.fill", couleur: .white, taille: 20), l1: "Envoi AirDrop\u{2026}",
                                      l2: quoi + " \u{00B7} choisis l\u{2019}appareil", icones: e.icone.map { [$0] } ?? [], coteSymbole: ContenuAnnonce.coteIcone,
                                      attente: true)
            case .envoye:
                return ContenuAnnonce(glyphe: GlypheIlot(nom: "checkmark.circle.fill", couleur: CouleursIlot.vert, taille: 22), l1: "Envoyé",
                                      l2: quoi + " \u{00B7} AirDrop")
            case .annule:
                return ContenuAnnonce(glyphe: GlypheIlot(nom: "xmark.circle.fill", couleur: Color.white.opacity(0.55), taille: 22), l1: "Annulé",
                                      l2: "Rien n\u{2019}a été envoyé")
            case .indisponible:
                return ContenuAnnonce(glyphe: GlypheIlot(nom: "exclamationmark.circle.fill", couleur: CouleursIlot.ambre, taille: 22), l1: "AirDrop indisponible",
                                      l2: "Allume le Wi-Fi et le Bluetooth")
            }
        default:
            return nil
        }
    }

    static func glypheApp(_ app: String) -> GlypheIlot {
        let a = app.lowercased()
        if a.contains("message") { return GlypheIlot(nom: "message.fill", couleur: CouleursIlot.vert, taille: 21) }
        if a.contains("mail") { return GlypheIlot(nom: "envelope.fill", couleur: CouleursIlot.bleu, taille: 20) }
        if a.contains("calend") { return GlypheIlot(nom: GlypheIlot.calendrier, couleur: CouleursIlot.rouge, taille: 21) }
        if ["slack", "teams", "discord", "whatsapp", "telegram", "signal"].contains(where: a.contains) {
            return GlypheIlot(nom: "bubble.left.and.bubble.right.fill", couleur: Color.white.opacity(0.85), taille: 19)
        }
        return GlypheIlot(nom: "app.badge.fill", couleur: Color.white.opacity(0.85), taille: 21)
    }

    /// La largeur du contenu (sans les marges) d'un écran qui l'épouse : c'est elle qui donne sa largeur à la forme.
    func largeurContenu(_ v: VueIlot) -> CGFloat? {
        if v == .agendaEtendu {
            guard let e = rdvVu else { return nil }
            // la plage est mesurée avec « dans 10 min », sa forme la plus longue dans la fenêtre des 10 minutes
            let textes = max(MesureIlot.texte(e.titre, 17, .semibold, interlettre: -0.2),
                             MesureIlot.texte(PlanAgenda.plage(e) + " \u{00B7} dans 10 min", 12.5, .medium),
                             MesureIlot.symbole("video.fill", 11) + 6 + MesureIlot.texte(ContenuAgenda.ligneLieu(e), 12.5, .medium))
            return ContenuAgenda.retrait + max(textes, MesureIlot.boutons(ContenuAgenda.boutons(e), memeLargeur: true))
        }
        guard let c = contenuAnnonce(v) else { return nil }
        let textes = max(MesureIlot.texte(c.l1, 17, .semibold, interlettre: ContenuAnnonce.interlettreL1), MesureIlot.texte(c.l2, 12.5, .medium))
        var l = c.coteSymbole + ContenuAnnonce.espace + textes
        switch c.droite {
        case .rien: break
        case .meta(let t): l += ContenuAnnonce.espace + MesureIlot.texte(t, 13, .semibold, chiffres: true)
        case .temps:
            let mn = minuteur ?? dernierMinuteur
            l += ContenuAnnonce.espace + MesureIlot.texte(FormatIlot.duree(mn.total), 15, .semibold, chiffres: true)
        case .boutons(let bs): l += ContenuAnnonce.espace + MesureIlot.boutons(bs)
        case .jauges(let js): l += ContenuAnnonce.espace + CGFloat(js.count) * JaugeIlot.largeur + ContenuAnnonce.espaceJauges * CGFloat(max(0, js.count - 1))
        }
        if c.compte != nil { l += ContenuAnnonce.espaceBoutons + ContenuAnnonce.coteCompte }
        if c.attente { l += ContenuAnnonce.espace + ContenuAnnonce.coteRouet }
        return l
    }
}
