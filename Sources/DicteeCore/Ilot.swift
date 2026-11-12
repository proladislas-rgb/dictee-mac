import Foundation

// L'îlot « centre d'activités » (maquette design/maquettes/ilot-activites.html) : logique pure, sans interface.
// Une seule forme noire dans l'encoche, trois tailles (minimal, compact, étendu), une règle de priorité, une pastille pour la deuxième activité.

/// Les « écrans » que l'îlot sait montrer. Chacun a une géométrie (`GeoIlot`) : la forme noire se déforme de l'un à l'autre.
public enum VueIlot: String, CaseIterable, Sendable {
    case repos
    case minuteurMinimal, minuteurCompact, minuteurEtendu, minuteurLance, minuteurFini
    case lectureCompact, lectureEtendu, lectureMinuteur
    case rappelEtendu, rappelCompact, rappelAjoute, rappelFait, rappelReporte, rappelListe
    case agendaAvant, agendaCompact, agendaEtendu, agendaDebut
    case notification, notifications
    case accueil
    /// Des écouteurs (ou une souris, un clavier) se connectent ; le chargeur est branché ; la batterie est faible.
    case appareil, batterieCharge, batterieFaible
    /// Un fichier (ou plusieurs, en rafale) vient d'arriver dans Téléchargements, AirDrop compris.
    case telecharge
    /// Le micro est coupé (micro barré rouge, « Coupé ») ; au survol, son nom et « Rouvrir » ; rouvert : un bandeau vert court.
    case microCompact, microEtendu, microOuvert
    /// Une touche de volume ou de luminosité : le haut-parleur (ou le soleil) dans l'aile gauche, une barre fine dans l'aile droite.
    case volume, luminosite
    /// Claude Code au travail (maquette design/maquettes/ilot-claude-plus.html) : l'étoile seule (rien à dire), ou l'étoile dans son
    /// anneau, « 3/7 », le nom de la tâche en cours qui défile (et un petit « 2 » si deux sessions travaillent). La carte « Claude Code » :
    /// un bloc par session (projet, état, depuis quand, la liste des tâches, « Ouvrir ») ; la session qui attend en haut. Bandeaux :
    /// « second-cerveau attend ta réponse », « Carte Dictées terminée ».
    case claudeMinimal, claudeCompact, claudeCarte, claudeAttend, claudeTermine
    /// L'étagère : pendant qu'on glisse des fichiers près de l'encoche, deux zones côte à côte, « Étagère » (la garder) et « AirDrop »
    /// (l'envoyer) ; depuis le Centre, la carte des fichiers gardés (icône, nom, glissables vers une app).
    case etagereDepot, etagere
    /// L'étagère plus rapide (maquette design/maquettes/ilot-etagere-rapide.html) : replié, la pile et le nombre de fichiers dans l'aile
    /// gauche (`etagerePile`) ; un glisser de fichiers commence n'importe où, l'îlot appelle « Glisse ici » (`etagereAppel`) ; l'envoi
    /// AirDrop (« Envoi… », « Envoyé », « Annulé ») ; des fichiers partis dans une app, avec « Remettre » quelques secondes.
    case etagerePile, etagereAppel, etagereEnvoi, etagerePartis
    /// Une capture d'écran vient d'arriver sur l'étagère (option « Captures d'écran ici ») : sa miniature, « Capture d’écran »,
    /// « Sur l’étagère » ; un clic ouvre l'étagère.
    case etagereCapture
    /// Le Centre (maquette design/maquettes/ilot-centre.html) : tout ce qui se règle depuis l'îlot, à la souris. Une rangée de gros boutons
    /// ronds (micro, micro de la dictée, téléchargements, Claude Code) et deux grandes cases (minuteur, étagère). On y passe depuis la lecture
    /// dépliée (bouton « Centre », points de page, défilement) ; l'îlot vide s'ouvre directement dessus.
    case centre
    /// Les Dictées (maquette ilot-centre.html, 3e carte) : l'ancien panneau de la barre des menus dans l'îlot. « ‹ Centre », la recherche,
    /// les dernières dictées groupées par jour (un clic copie, « Coller » au survol, le chevron déplie), et les liens vers la fenêtre.
    case dictees
    /// La 2e page du Centre, « Outils » (maquette ilot-claude-plus.html, étapes 8 à 14) : quatre gros boutons ronds (Garder éveillé,
    /// Presse-papiers, Reformuler, Notes), le panneau « Garder éveillé » (1 h, 2 h, jusqu'à l'arrêt) et la bande « Dicter une note ».
    /// Ses cartes, ouvertes d'un clic sur un rond : le presse-papiers (les cinq dernières copies), Reformuler (la dernière dictée ou le
    /// texte choisi, réécrit), Note rapide (dicter une note, les notes gardées).
    case outils, outilPressePapiers, outilReformuler, outilNote
    /// La carte « Second Brain » (maquette ilot-second-cerveau.html) : ce que l'autre app de Hugues dépose dans ~/.config/second-cerveau/ilot.json
    /// (messages, choses « à toi », relances). Elle s'ouvre d'un clic sur son bouton du Centre, qui n'existe que si le fichier existe ; elle
    /// est rangée sous le Centre (point de page du Centre allumé, un défilement y ramène).
    case secondBrain

    /// Ces écrans sont des bandeaux : ils s'annoncent, restent un instant, puis se retirent d'eux-mêmes.
    public var estBandeau: Bool {
        switch self {
        case .minuteurLance, .rappelAjoute, .rappelFait, .rappelReporte, .agendaAvant, .notification, .notifications,
             .appareil, .batterieCharge, .batterieFaible, .telecharge, .microOuvert, .volume, .luminosite, .claudeAttend, .claudeTermine,
             .etagereEnvoi, .etagerePartis, .etagereCapture: return true
        default: return false
        }
    }
    /// Ces écrans sont des alertes : l'îlot s'ouvre de lui-même, vibre, sonne, et attend un geste.
    public var estAlerte: Bool { self == .minuteurFini || self == .rappelEtendu || self == .agendaDebut }
    /// Volume et luminosité : un bandeau qui suit les touches du clavier (1,5 s après la dernière).
    public var estNiveau: Bool { self == .volume || self == .luminosite }
}

/// Géométrie de la forme (maquette design/maquettes/ilot-pro-A.html), sept valeurs :
/// [cou, corps, hauteur, épaule, coin bas, coin haut du corps, congé du cou].
/// - cou : demi-largeur dans la barre des menus, AU-DELÀ de la demi-caméra (jamais plus de 66 pt avec l'épaule ou le congé) ;
/// - corps : demi-largeur sous la barre, au-delà de la demi-caméra (le corps n'existe que sous la barre) ;
/// - hauteur : depuis le haut de l'écran. La table donne la profondeur SOUS la barre ; `valeurs` ajoute la vraie barre ;
/// - épaule : le creux du haut, où la forme s'évase pour rejoindre le bord de l'écran ;
/// - coin bas, coin haut du corps : coins continus (pas des arcs de cercle) ; congé : le raccord creux entre le cou et le corps.
/// Tout est exprimé depuis la vraie caméra et la vraie barre : aucune mesure de la maquette n'est copiée telle quelle.
public enum GeoIlot {
    public static let aileMax: Double = 66
    /// Ce que la rangée Minuteur ajoute sous la lecture dépliée (maquette : 208 → 262 pt de haut).
    public static let rangeeMinuteur: Double = 54
    /// Une ligne de l'accueil (42 pt) : celle de l'étagère s'ajoute en bas quand elle garde des fichiers.
    public static let ligneAccueil: Double = 42
    /// Une rangée de plus de fichiers dans la carte Étagère (tuile de 72 pt + 8 pt d'écart).
    public static let rangeeEtagere: Double = 80
    /// La ligne « Captures d'écran ici » au bas de la carte Étagère (interrupteur).
    public static let ligneCaptures: Double = 40
    /// Sous elle, quand l'option est allumée : « Vignette des captures en haut » (6 pt d'écart + une ligne).
    public static let ligneVignette: Double = 6 + 40
    /// Les écrans dont le cou droit n'est pas celui de gauche : la pile de l'étagère n'a qu'une aile, à gauche ; à droite, la caméra seule
    /// (les icônes de la barre des menus à droite de l'encoche restent dégagées). Valeur au-delà de la demi-caméra.
    public static let couDroit: [VueIlot: Double] = [.etagerePile: 0]
    /// La lecture dépliée jusqu'à ses commandes (pochette, titre, barre, boutons) : la rangée Minuteur (appui long) se pose dessous.
    public static let profondeurLecture: Double = 175
    /// Le pied de la lecture dépliée : le bouton « Centre » (30 pt) et sa marge (maquette : 12 pt dessus, 14 dessous ; ici 6 + 30 + 4,
    /// les boutons de la lecture ont déjà 7 pt de vide sous leur glyphe).
    public static let piedLecture: Double = 40
    /// Le Centre tel qu'il est la première fois : 14 de marge, l'en-tête (26), 12, la rangée des ronds (96), 10, les deux grandes cases
    /// (76), 10, la bande « Noter la réunion » (40), 14 (maquette : 331 − 33). « Modifier » l'allonge ou le raccourcit (`enPlus`,
    /// DispositionCentre.plan).
    public static let profondeurCentre: Double = 14 + 26 + 12 + 96 + 10 + 76 + 10 + 40 + 14
    /// Les Dictées à leur plus haut (la liste à sa hauteur maximale) : la table la donne, une liste plus courte la raccourcit (`enPlus`,
    /// `CarteDictees.profondeur`).
    public static let profondeurDictees: Double = CarteDictees.profondeurMax
    /// Repos d'une activité : rien sous la barre, le cou serré contre la caméra (la place de la pochette, de l'anneau, de l'heure).
    static func compact(_ cou: Double) -> [Double] { [cou, cou, 0, 6, 10, 0, 0] }
    /// Bandeau passager : cou étroit (les menus restent visibles), deux lignes sous la barre. Le corps s'ajuste à son contenu (comme la
    /// Dynamic Island) : la table donne le plus large permis, `corps(_:contenu:demiCamera:)` la largeur voulue.
    static let bandeau: [Double] = [14, 150, 72, 6, 28, 16, 10]
    static let alerte: [Double] = [14, 150, 79, 6, 30, 16, 10]
    static let table: [VueIlot: [Double]] = [
        // repos : exactement l'encoche (pas d'épaule : rien ne déborde sur la barre autour de la caméra)
        .repos: [0, 0, 0, 0, 8, 0, 0],
        .minuteurMinimal: compact(36), .minuteurCompact: compact(48), .minuteurEtendu: [48, 112, 91, 6, 30, 16, 10],
        .minuteurLance: bandeau, .minuteurFini: alerte,
        // la lecture dépliée : ses commandes, puis le pied (bouton « Centre ») ; le Centre a la même largeur (on passe de l'un à l'autre)
        .lectureCompact: compact(44), .lectureEtendu: [44, 144, profondeurLecture + piedLecture, 6, 34, 18, 10],
        // la lecture dépliée + la rangée Minuteur de l'accueil (appui long, maquette apple-acces/1-controles.html) : même largeur ; la
        // rangée prend la place du pied
        .lectureMinuteur: [44, 144, profondeurLecture + rangeeMinuteur, 6, 34, 18, 10],
        .rappelEtendu: alerte, .rappelCompact: compact(48), .rappelAjoute: bandeau,
        .rappelFait: bandeau, .rappelReporte: bandeau, .rappelListe: [14, 144, 136, 6, 34, 18, 10],
        .agendaAvant: bandeau, .agendaCompact: compact(50), .agendaEtendu: [50, 150, 130, 6, 34, 18, 10], .agendaDebut: bandeau,
        .notification: bandeau, .notifications: bandeau,
        // l'accueil, devenu la carte sous le Centre : le prochain rendez-vous, « Dire un rappel », la dernière dictée (3 lignes de 42 pt).
        // Le minuteur, le choix du micro et l'étagère sont passés dans le Centre
        .accueil: [14, 144, 10 + 3 * ligneAccueil + 12, 6, 34, 18, 10],
        // les jauges des écouteurs (anneau + nom) demandent un peu plus de hauteur qu'un bandeau ; l'énergie tient dans les ailes
        .appareil: [14, 150, 80, 6, 30, 16, 10],
        .batterieCharge: compact(60), .batterieFaible: compact(60),
        // le fichier arrivé : son icône (38 pt), son nom et « Téléchargé · 2,4 Mo », le bouton Ouvrir ; un bandeau ordinaire
        .telecharge: bandeau,
        // micro coupé : le micro barré (aile gauche) et « Coupé » (41 pt mesurés, aile droite : 60 − 8 − 4 = 48 pt) ; 60 + 6 = 66 ;
        // au survol, un petit déplié qui épouse « Micro coupé », le nom du micro et « Rouvrir » ; rouvert, « Ouvert » (44 pt) en vert
        .microCompact: compact(60), .microEtendu: bandeau, .microOuvert: compact(60),
        // volume et luminosité : le haut-parleur (aile gauche) et une barre fine de 44 pt (aile droite : 8 pt de la caméra, 8 pt du
        // cou) ; 60 + 6 = 66. La maquette dessinait 96 pt : ça déborderait sur les icônes de la barre des menus
        .volume: compact(60), .luminosite: compact(60),
        // Claude au travail : rien à dire, l'étoile seule (cou de 36 pt, comme le minuteur minimal) ; sinon l'étoile dans son anneau et
        // « 3/7 » (aile gauche, 48 pt utiles), le nom de la tâche qui défile (aile droite, 48 pt) ; 60 + 6 = 66. La carte « Claude Code » a
        // la largeur du Centre (on passe de l'un à l'autre) ; sa hauteur suit ses sessions (`enPlus`), jusqu'à celle du Centre : au-delà, elle
        // défile. Les annonces : des bandeaux qui épousent leur contenu
        .claudeMinimal: compact(36), .claudeCompact: compact(60), .claudeCarte: [14, 144, profondeurCentre, 6, 34, 18, 10],
        .claudeAttend: bandeau, .claudeTermine: bandeau,
        // l'étagère, de la largeur de l'accueil : les deux zones « Étagère » et « AirDrop » (14 + 112 + 14 pt, maquette) ; la carte :
        // l'en-tête (42 pt), une rangée de tuiles (72 pt), la ligne « Captures d'écran ici » (40 pt) ; une deuxième rangée de tuiles
        // s'ajoute (`enPlus`) au-delà de cinq fichiers
        .etagereDepot: [14, 144, 14 + 112 + 14, 6, 30, 16, 10],
        .etagere: [14, 144, 10 + 42 + 8 + 72 + 10 + ligneCaptures + 12, 6, 34, 18, 10],
        // replié, l'étagère garde des fichiers : la pile et le nombre dans l'aile GAUCHE seule (46 + épaule de 6 = 52 pt au-delà de la
        // caméra : la pile et « 10 » mesurent 39 pt, 3 pt de marge de chaque côté) ; à droite, rien que la caméra (`couDroit`)
        .etagerePile: compact(46),
        // un glisser de fichiers commence : « Glisse ici » sous la caméra, le cou serré contre elle (le congé seul dans la barre, 10 pt),
        // le corps 54 pt au-delà de la caméra (plus que la maquette, 28 : sinon le congé et le coin haut n’ont pas leur place)
        .etagereAppel: [0, 54, 38, 6, 24, 14, 10],
        // l'envoi AirDrop et les fichiers partis : des bandeaux qui épousent leur contenu
        .etagereEnvoi: bandeau, .etagerePartis: bandeau, .etagereCapture: bandeau,
        .centre: [14, 144, profondeurCentre, 6, 34, 18, 10],
        // les Dictées : la largeur du Centre (on passe de l'un à l'autre sans que la forme s'élargisse), la hauteur de la liste
        .dictees: [14, 144, profondeurDictees, 6, 34, 18, 10],
        // la page Outils et ses cartes : la largeur du Centre (on passe de l'une à l'autre) ; leur hauteur suit leur contenu (`enPlus`,
        // jamais plus haut que le Centre : au-delà, la liste des notes défile)
        .outils: [14, 144, profondeurCentre, 6, 34, 18, 10],
        .outilPressePapiers: [14, 144, profondeurCentre, 6, 34, 18, 10],
        .outilReformuler: [14, 144, profondeurCentre, 6, 34, 18, 10],
        .outilNote: [14, 144, profondeurCentre, 6, 34, 18, 10],
        .secondBrain: [14, 144, profondeurCentre, 6, 34, 18, 10],
    ]
    /// Indices des valeurs : largeurs (cou, corps, cou droit) et hauteurs (hauteur, épaule, coins, congé). À l'ouverture la largeur
    /// mène ; à la fermeture la hauteur se replie d'abord.
    public static let largeurs = [0, 1, 7]
    public static let hauteurs = [2, 3, 4, 5, 6]

    /// Marge du contenu tout autour du corps (la grille de l'îlot).
    public static let marge: Double = 16
    /// Le corps s'évase toujours d'au moins 38 pt au-delà du cou : en deçà, le congé et le coin haut n'ont plus la place de se dessiner
    /// (la forme deviendrait une languette).
    public static let evasementMin: Double = 38

    /// Écrans dont le corps épouse le contenu (bandeaux, alertes, rendez-vous déplié) : ni texte collé à gauche ni grand vide à droite.
    public static func ajusteAuContenu(_ v: VueIlot) -> Bool { ((v.estBandeau || v.estAlerte) && profondeur(v) > 0) || v == .agendaEtendu || v == .microEtendu }

    /// Les épaules (maquette ilot-apple.html) : dans un écran déplié, le cou s'élargit à 56 pt de chaque côté de la caméra pour montrer
    /// la batterie du Mac (à gauche) et celle des écouteurs (à droite). 56 + le congé du cou déplié (10 pt) = la limite des ailes (66 pt).
    public static let epaules: Double = 56
    public static func aEpaules(_ v: VueIlot) -> Bool {
        [.minuteurEtendu, .lectureEtendu, .lectureMinuteur, .rappelListe, .agendaEtendu, .accueil, .etagere, .centre, .dictees, .claudeCarte,
         .outils, .outilPressePapiers, .outilReformuler, .outilNote, .secondBrain].contains(v)
    }

    /// Demi-corps (au-delà de la demi-caméra) pour un contenu de `largeur` pt : contenu + marges, borné entre le cou + 38 pt et la table.
    public static func corps(_ v: VueIlot, contenu largeur: Double, demiCamera: Double) -> Double {
        let t = table[v] ?? table[.repos]!
        return min(t[1], max(t[0] + evasementMin, (largeur / 2 + marge - demiCamera).rounded(.up)))
    }

    /// Les valeurs pour une vue (les sept de la table, puis le cou droit, égal au cou sauf pour une forme à une seule aile), la hauteur
    /// comptée depuis le haut de l'écran avec la vraie barre des menus. `contenu` : la largeur
    /// mesurée du contenu (pt) pour un écran qui s'y ajuste ; nil = le plus large de la table. `enPlus` : la hauteur qu'un contenu
    /// variable ajoute (la ligne de l'étagère dans l'accueil, une deuxième rangée de fichiers) ou retire (un Centre sans ses cases).
    public static func valeurs(_ v: VueIlot, hauteurBarre: Double, demiCamera: Double = 0, contenu: Double? = nil, epaules avecEpaules: Bool = false, enPlus: Double = 0) -> [Double] {
        var g = table[v] ?? table[.repos]!
        g[2] = max(0, g[2] + enPlus) + hauteurBarre
        if avecEpaules, aEpaules(v) { g[0] = max(g[0], epaules) }
        if let contenu, ajusteAuContenu(v) { g[1] = corps(v, contenu: contenu, demiCamera: demiCamera) }
        g.append(couDroit[v] ?? g[0])
        return g
    }
    /// Profondeur sous la barre (0 pour un repos ou un compact).
    public static func profondeur(_ v: VueIlot) -> Double { (table[v] ?? table[.repos]!)[2] }
}

/// Comment la forme passe d'un écran à l'autre : les ressorts du moteur, ici pour que les contrôles essaient exactement les mêmes.
public enum PassageIlot: Equatable, Sendable {
    case ouverture, fermeture, glissement

    /// Ouverture si la forme doit descendre, fermeture si elle doit remonter (jugé sur la hauteur affichée : une interruption compte).
    public static func de(hauteur h: Double, vers c: Double) -> PassageIlot { c > h + 1 ? .ouverture : (c < h - 1 ? .fermeture : .glissement) }

    /// Vise la géométrie `c` depuis l'état affiché des ressorts (valeur et vitesse gardées).
    /// - ouverture : la largeur mène (0,40 s / 0,80), la hauteur suit (0,48 s / 0,75) ; alerte plus vive (0,38 / 0,74 et 0,46 / 0,70) ;
    /// - fermeture : le contenu part d'abord (0,06 s), puis la forme se dégonfle sans rebond, la largeur un peu plus vite que la hauteur
    ///   (0,32 s contre 0,42 s) : à mi-course elle se resserre vers l'encoche au lieu de faire un bandeau plat sous les menus ;
    /// - glissement (même hauteur) : 0,36 s / 0,86 ; « Réduire les animations » : tout saute à sa place.
    @discardableResult
    public static func viser(_ geo: inout [RessortIlot], vers c: [Double], alerte: Bool = false, reduire: Bool = false) -> PassageIlot {
        let p = de(hauteur: geo[2].x, vers: c[2])
        if reduire {
            for i in geo.indices { geo[i].viser(c[i], reponse: 0.4, amortissement: 1); geo[i].poser() }
            return p
        }
        switch p {
        case .fermeture:
            for i in GeoIlot.hauteurs { geo[i].viser(c[i], reponse: 0.42, amortissement: 1, attente: 0.06) }
            for i in GeoIlot.largeurs { geo[i].viser(c[i], reponse: 0.32, amortissement: 1, attente: 0.06) }
        case .ouverture:
            for i in GeoIlot.largeurs { geo[i].viser(c[i], reponse: alerte ? 0.38 : 0.40, amortissement: alerte ? 0.74 : 0.80) }
            for i in GeoIlot.hauteurs { geo[i].viser(c[i], reponse: alerte ? 0.46 : 0.48, amortissement: alerte ? 0.70 : 0.75) }
        case .glissement:
            for i in geo.indices { geo[i].viser(c[i], reponse: 0.36, amortissement: 0.86) }
        }
        return p
    }
}

/// Une « activité » : ce qui peut occuper l'îlot ou la pastille.
public enum ActiviteIlot: String, Sendable, Equatable {
    case minuteur, rappel, rendezVous, lecture, alerte
    /// Le micro est coupé : l'îlot le rappelle tant qu'il l'est.
    case micro
    /// Claude Code travaille (ou attend une réponse) dans le Terminal.
    case claude
}

/// Ce qui est vrai à l'instant, pour décider qui a l'îlot et qui a la pastille.
public struct EtatIlot: Equatable, Sendable {
    public var minuteur = false            // un minuteur tourne (ou est en pause)
    public var rappelEnAttente = false     // un rappel a sonné sans réponse : la cloche reste dans l'aile
    public var rendezVousProche = false    // un rendez-vous dans 10 minutes
    public var lecture = false             // quelque chose joue
    public var microCoupe = false          // le micro du Mac est coupé (raccourci, ou Réglages Système)
    public var claude = false              // Claude Code travaille ou attend une réponse
    public var claudeAttend = false        // … il attend une réponse (il passe alors avant la lecture)
    public var claudeListe = false         // … il a quelque chose à dire : une liste de tâches (« 3/7 ») ou le nom de sa tâche
    public var etagere = false             // l'étagère (allumée) garde des fichiers : replié, la pile dans l'aile gauche
    public var alerte: VueIlot?            // minuteurFini, rappelEtendu ou agendaDebut, en cours
    public var bandeau: VueIlot?           // un bandeau passager
    public init() {}
}

public struct ResolutionIlot: Equatable, Sendable {
    /// L'écran de l'îlot, au repos (compact, bandeau, alerte, ou repos).
    public var principal: VueIlot
    /// L'écran que l'îlot prend au survol (nil : rien, l'alerte et le bandeau n'ont pas de dépliage).
    public var survol: VueIlot?
    /// Verrou : ni survol ni dépliage (alerte, bandeau).
    public var verrou: Bool
    /// L'activité qui vit dans la pastille sous l'encoche, s'il y en a une.
    public var pastille: ActiviteIlot?
    public init(principal: VueIlot, survol: VueIlot?, verrou: Bool, pastille: ActiviteIlot?) {
        self.principal = principal; self.survol = survol; self.verrou = verrou; self.pastille = pastille
    }
}

public enum ArbitrageIlot {
    /// L'ordre de priorité des activités qui se partagent l'îlot : micro coupé, rendez-vous, rappel, lecture, minuteur, Claude. Le micro
    /// coupé passe avant tout : c'est ce qui gêne le plus si on l'oublie (on parle dans un appel où personne n'entend) ; la vidéo devient
    /// la bulle. Claude au travail est un fond (il passe après la vidéo et le minuteur) ; Claude qui attend une réponse passe avant la vidéo.
    public static func ordre(_ e: EtatIlot, echange: ActiviteIlot? = nil) -> [ActiviteIlot] {
        var p: [ActiviteIlot] = []
        if e.microCoupe { p.append(.micro) }
        if e.rendezVousProche { p.append(.rendezVous) }
        if e.rappelEnAttente { p.append(.rappel) }
        if e.claude, e.claudeAttend { p.append(.claude) }
        if e.lecture { p.append(.lecture) }
        if e.minuteur { p.append(.minuteur) }
        if e.claude, !e.claudeAttend { p.append(.claude) }
        if let echange, p.contains(echange) { p = [echange] + p.filter { $0 != echange } }
        return p
    }

    public static func vues(_ a: ActiviteIlot) -> (compact: VueIlot, etendu: VueIlot) {
        switch a {
        case .minuteur: return (.minuteurCompact, .minuteurEtendu)
        case .rappel: return (.rappelCompact, .rappelEtendu)
        case .rendezVous: return (.agendaCompact, .agendaEtendu)
        case .lecture: return (.lectureCompact, .lectureEtendu)
        case .micro: return (.microCompact, .microEtendu)
        case .claude: return (.claudeCompact, .claudeCarte)
        case .alerte: return (.repos, .repos)
        }
    }

    /// Ce que l'îlot prend au survol quand l'activité `a` l'occupe (ou occupe la bulle). Claude qui attend une réponse : sa carte, la
    /// session qui attend en haut ; Claude au travail : le Centre (maquette ilot-claude-plus.html, étapes 2 et 5 : la carte est à un
    /// clic, sur le bouton Claude Code).
    public static func survol(_ a: ActiviteIlot, _ e: EtatIlot) -> VueIlot {
        a == .claude && !e.claudeAttend ? .centre : vues(a).etendu
    }

    public static func resoudre(_ e: EtatIlot, echange: ActiviteIlot? = nil) -> ResolutionIlot {
        let p = ordre(e, echange: echange)
        if let a = e.alerte { return ResolutionIlot(principal: a, survol: nil, verrou: true, pastille: p.first) }
        // volume et luminosité : un coup d'œil de 1,5 s qui passe par-dessus l'activité ; la bulle ne bouge pas (pas de vidéo qui saute
        // dans la bulle et en revient à chaque touche)
        if let b = e.bandeau, b.estNiveau { return ResolutionIlot(principal: b, survol: nil, verrou: true, pastille: p.count > 1 ? p[1] : nil) }
        if let b = e.bandeau { return ResolutionIlot(principal: b, survol: nil, verrou: true, pastille: p.first) }
        if let premiere = p.first {
            let v = vues(premiere)
            // Claude sans rien à dire (ni liste, ni nom de tâche, ni question) : l'étoile seule, dans un îlot plus étroit
            let compact = premiere == .claude && !e.claudeListe && !e.claudeAttend ? VueIlot.claudeMinimal : v.compact
            return ResolutionIlot(principal: compact, survol: survol(premiere, e), verrou: false, pastille: p.count > 1 ? p[1] : nil)
        }
        // rien ne joue : l'îlot s'ouvre directement sur le Centre (au survol comme au clic) ; s'il garde des fichiers, la pile de
        // l'étagère et leur nombre dans l'aile gauche (une activité passe avant : l'étagère se voit alors au survol, dans le Centre)
        if e.etagere { return ResolutionIlot(principal: .etagerePile, survol: .centre, verrou: false, pastille: nil) }
        return ResolutionIlot(principal: .repos, survol: .centre, verrou: false, pastille: nil)
    }

    /// L'étage de la priorité (1 = le plus haut) : 1 dictée, 2 réunion, 3 alerte (minuteur fini, rappel, rendez-vous) et micro coupé,
    /// 4 lecture, 5 le reste.
    public static func etage(dictee: Bool, reunion: Bool, ecran: VueIlot) -> Int {
        if dictee { return 1 }
        if reunion { return 2 }
        switch ecran {
        case .minuteurFini, .rappelEtendu, .agendaDebut, .agendaAvant, .agendaCompact, .rappelCompact, .rappelAjoute,
             .microCompact, .microEtendu, .microOuvert: return 3
        case .lectureCompact, .lectureEtendu, .lectureMinuteur: return 4
        default: return 5
        }
    }
}

/// Un ressort amorti (comme celui de la maquette) : part toujours de la valeur affichée et garde sa vitesse, donc interruptible.
/// `reponse` en secondes ; `amortissement` 1 = sans rebond. Une cible peut attendre (`viser(..., attente:)`) : pendant l'attente, le ressort
/// continue vers l'ancienne cible (la maquette fait partir la largeur avant la hauteur à l'ouverture, et l'inverse à la fermeture).
public struct RessortIlot: Equatable, Sendable {
    public var x: Double
    public var v: Double = 0
    public var cible: Double
    public var reponse: Double
    public var amortissement: Double
    public private(set) var attente: Double = 0
    private var cibleFuture: Double?
    private var reponseFuture = 0.0, amortissementFuture = 1.0
    public init(_ valeur: Double, reponse: Double, amortissement: Double) {
        x = valeur; cible = valeur; self.reponse = reponse; self.amortissement = amortissement
    }
    public mutating func regler(reponse: Double, amortissement: Double) { self.reponse = reponse; self.amortissement = amortissement }
    /// La cible où le ressort finira (celle qui attend, sinon la cible courante).
    public var cibleFinale: Double { cibleFuture ?? cible }
    /// Nouvelle cible, tout de suite ou après `attente` secondes. Valeur et vitesse sont gardées : jamais de saut.
    public mutating func viser(_ c: Double, reponse r: Double, amortissement z: Double, attente a: Double = 0) {
        if a > 0 { cibleFuture = c; reponseFuture = r; amortissementFuture = z; attente = a; return }
        cibleFuture = nil; attente = 0; cible = c; reponse = r; amortissement = z
    }
    private mutating func simuler(_ dt: Double) {
        guard dt > 0 else { return }
        let w = 2 * Double.pi / reponse, k = w * w, c = 2 * amortissement * w
        let n = max(1, Int((dt * 240).rounded(.up))), h = dt / Double(n)
        for _ in 0..<n { let a = k * (cible - x) - c * v; v += a * h; x += v * h }
    }
    private mutating func prendreLaCibleFuture() {
        if let c = cibleFuture { cible = c; reponse = reponseFuture; amortissement = amortissementFuture }
        cibleFuture = nil; attente = 0
    }
    public mutating func avancer(_ dt: Double) {
        var dt = dt
        if cibleFuture != nil {
            if dt < attente { attente -= dt; simuler(dt); return }
            simuler(attente); dt -= attente
            prendreLaCibleFuture()
        }
        simuler(dt)
    }
    /// Posé : à moins d'un centième de point (ou de pour cent) de sa cible, pratiquement immobile, et plus rien n'attend.
    public var fini: Bool { cibleFuture == nil && abs(cible - x) < 0.01 && abs(v) < 0.05 }
    public mutating func poser() { prendreLaCibleFuture(); x = cible; v = 0 }
}

/// La forme noire : le chemin de la maquette (fonctions `calculer` et `chemin` de ilot-pro-A.html), en points. Origine = centre de
/// l'encoche, y = haut de l'écran. Coins continus : chaque coin s'étend sur 1,6 fois son rayon, poignées à 0,18 de cette portée (courbure
/// nulle aux deux bouts, comme les coins d'Apple, et non un quart de cercle).
public enum TraceIlot {
    public enum Commande: Equatable, Sendable {
        case deplacer(Double, Double)
        case ligne(Double, Double)
        case quad(Double, Double, Double, Double)                         // contrôle, point
        case cubique(Double, Double, Double, Double, Double, Double)     // contrôle 1, contrôle 2, point
    }

    public struct Points: Equatable, Sendable {
        public var commandes: [Commande]
        /// Plus grande demi-largeur dans la hauteur de la barre (cou + épaule ou congé) : jamais plus que les ailes.
        public var bande: Double
        /// Demi-largeur du cou lui-même, à droite (le bord droit de l'îlot sous l'épaule, là où s'aligne la pastille).
        public var cou: Double
        /// Demi-largeur du corps sous la barre.
        public var corps: Double
        public var hauteur: Double
        /// Le cou à gauche (différent du droit pour une forme à une seule aile, la pile de l'étagère), et la largeur dans la barre de
        /// chaque côté.
        public var couGauche: Double = 0
        public var bandeGauche: Double = 0
        public var bandeDroite: Double = 0
        public var corpsGauche: Double = 0
        public var corpsDroit: Double = 0
        /// Jusqu'où va la forme de chaque côté (dans la barre ou dessous) : le rectangle de la fenêtre n'en prend pas plus.
        public var gauche: Double { max(corpsGauche, bandeGauche) }
        public var droite: Double { max(corpsDroit, bandeDroite) }
        /// Largeur dans la barre (gauche, droite) et largeur du bas (gauche, droite).
        public var xGauche: Double { -bande }
        public var xDroite: Double { bande }
        public var basGauche: Double { -corps }
        public var basDroite: Double { corps }
    }

    public static let portee = 1.6, poignee = 0.18

    /// `g` : les valeurs de `GeoIlot.valeurs` (sept, ou huit avec le cou droit) ; `demiCamera` : la moitié de la vraie caméra ; `barre` :
    /// la hauteur de la barre. Chaque côté est calculé avec son propre cou (une forme symétrique donne les deux mêmes côtés).
    public static func calculer(_ g: [Double], demiCamera: Double, barre: Double) -> Points {
        let bw = demiCamera + max(0, g[1]), h = max(1, g[2])
        let rs = max(0, g[3]), rb = max(0, g[4]), rt = max(0, g[5]), f = max(0, g[6])
        let B = barre
        let sousBarre = max(0, h - B)
        // dans la barre des menus, jamais plus de 66 pt de chaque côté de la caméra (cou + max(épaule, congé)), même pendant un passage :
        // de l'îlot replié (cou 60, sans congé) à un écran déplié (cou 56, congé 10), ou quand le ressort du cou dépasse sa cible, le cou
        // cède la place au congé qui grandit. Au repos, les tables tiennent déjà dans les 66 pt : rien ne change
        let congeMax = max(0, min(f, B - rs - 2, sousBarre * 0.6))
        // chaque côté avec son propre cou (le cou droit, 8e valeur, pour la forme à une aile de l'étagère), bornés tous les deux
        let borne = demiCamera + GeoIlot.aileMax - max(rs, congeMax)
        let ng = min(demiCamera + max(0, g[0]), borne), nd = min(demiCamera + max(0, g.count > 7 ? g[7] : g[0]), borne)
        // le corps s'élargit dès qu'il existe sous la barre (pas de languette qui tombe avant de s'ouvrir)
        let u = min(sousBarre, 40) / 40
        let e = 1 - pow(1 - u, 2.5)
        // un côté : son cou `n`, l'évasement du corps `d`, sa largeur `W`, le congé, le coin haut et le coin bas qui y tiennent
        func cote(_ n: Double) -> (n: Double, d: Double, W: Double, fe: Double, rte: Double, rbe: Double) {
            let d = max(0, bw - n) * e
            let W = n + d
            let fe = max(0, min(f, d * 0.45, B - rs - 2, sousBarre * 0.6))
            let rte = max(0, min(rt, (d - fe) / portee, sousBarre / 3.2))
            let lam = min(1, d / 6)
            let dispo = (1 - lam) * (h - rs) + lam * (h - B - portee * rte)
            let rbe = max(0, min(rb, dispo / portee, W / portee))
            return (n, d, W, fe, rte, rbe)
        }
        let L = cote(ng), D = cote(nd)
        let a1 = portee * L.rte, c1 = poignee * a1, a2 = portee * L.rbe, c2 = poignee * a2
        let b1 = portee * D.rte, d1 = poignee * b1, b2 = portee * D.rbe, d2 = poignee * b2
        var c: [Commande] = []
        c.append(.deplacer(-L.n - rs, -1)); c.append(.ligne(-L.n - rs, 0)); c.append(.quad(-L.n, 0, -L.n, rs))
        if L.d > 0.5 {
            c.append(.ligne(-L.n, B - L.fe)); c.append(.quad(-L.n, B, -L.n - L.fe, B))
            c.append(.ligne(-L.W + a1, B)); c.append(.cubique(-L.W + c1, B, -L.W, B + c1, -L.W, B + a1))
        }
        c.append(.ligne(-L.W, h - a2)); c.append(.cubique(-L.W, h - c2, -L.W + c2, h, -L.W + a2, h))
        c.append(.ligne(D.W - b2, h)); c.append(.cubique(D.W - d2, h, D.W, h - d2, D.W, h - b2))
        if D.d > 0.5 {
            c.append(.ligne(D.W, B + b1)); c.append(.cubique(D.W, B + d1, D.W - d1, B, D.W - b1, B))
            c.append(.ligne(D.n + D.fe, B)); c.append(.quad(D.n, B, D.n, B - D.fe))
        }
        c.append(.ligne(D.n, rs)); c.append(.quad(D.n, 0, D.n + rs, 0)); c.append(.ligne(D.n + rs, -1))
        return Points(commandes: c, bande: max(L.n + rs, L.n + L.fe, D.n + rs, D.n + D.fe), cou: D.n, corps: max(L.W, D.W), hauteur: h,
                      couGauche: L.n, bandeGauche: max(L.n + rs, L.n + L.fe), bandeDroite: max(D.n + rs, D.n + D.fe), corpsGauche: L.W, corpsDroit: D.W)
    }

    /// Plus grande demi-largeur de la forme à la hauteur `y` (pour vérifier que rien ne dépasse dans la barre des menus).
    public static func demiLargeur(_ p: Points, y: Double, barre: Double) -> (gauche: Double, droite: Double) {
        y < barre - 0.01 ? (p.xGauche, p.xDroite) : (p.basGauche, p.basDroite)
    }
}

public enum FormatIlot {
    /// « 10:00 », « 0:42 » : minutes et secondes, arrondi vers le haut (un compte à rebours à 0:00,2 montre 0:01).
    public static func duree(_ secondes: Double) -> String {
        let s = Int(max(0, secondes - 0.001).rounded(.up))
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }
    /// « 14:42 » en heure locale.
    public static func heure(_ date: Date, calendrier: Calendar = .current) -> String {
        let c = calendrier.dateComponents([.hour, .minute], from: date)
        return String(format: "%d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
    /// « 5 min », « 1 h 30 ».
    public static func minutes(_ secondes: Double) -> String {
        let m = Int((secondes / 60).rounded())
        if m >= 60 { return m % 60 == 0 ? "\(m / 60) h" : "\(m / 60) h \(String(format: "%02d", m % 60))" }
        return "\(m) min"
    }
}
