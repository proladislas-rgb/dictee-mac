import AppKit
import DicteeCore

/// Un faux Mail pour l'essai (jamais la vraie Mail) : ouvert, une liste de non lus, ou une erreur d'AppleScript.
final class MailEssai: SourceMail, @unchecked Sendable {
    private let verrou = NSLock()
    private var _messages: [MessageMail] = [], _erreur: ErreurApp?
    var messages: [MessageMail] { get { verrou.withLock { _messages } } set { verrou.withLock { _messages = newValue } } }
    var erreur: ErreurApp? { get { verrou.withLock { _erreur } } set { verrou.withLock { _erreur = newValue } } }
    func estOuvert() async -> Bool { true }
    func nonLus(depuisSecondes s: Int, max: Int) async throws(ErreurApp) -> [MessageMail] {
        let (e, m) = verrou.withLock { (_erreur, _messages) }
        if let e { throw e }
        return Array(m.prefix(max))
    }
}

/// Un faux réseau pour l'essai (jamais les vrais Notion et Airtable) : une réponse par début d'adresse ; une clé « faux » est refusée.
final class ReseauEssai: TransportHTTP, @unchecked Sendable {
    private let verrou = NSLock()
    private var routes: [(String, String)] = []
    private var _requetes = 0
    var requetes: Int { verrou.withLock { _requetes } }
    func repondre(_ motif: String, _ corps: String) { verrou.withLock { routes.insert((motif, corps), at: 0) } }
    func envoyer(_ requete: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let cle = (requete.httpMethod ?? "GET") + " " + (requete.url?.absoluteString ?? "")
        let auth = requete.value(forHTTPHeaderField: "Authorization") ?? ""
        let (statut, corps): (Int, String) = verrou.withLock {
            _requetes += 1
            if auth.contains("faux") { return (401, #"{"code":"unauthorized"}"#) }
            return routes.first { cle.contains($0.0) }.map { (200, $0.1) } ?? (404, #"{"code":"object_not_found"}"#)
        }
        let h = HTTPURLResponse(url: requete.url!, statusCode: statut, httpVersion: "HTTP/1.1", headerFields: ["Date": "Fri, 13 Nov 2026 09:31:00 GMT"])!
        return (Data(corps.utf8), h)
    }
}

extension IlotEssai {
    /// « Tes apps » (13/11) : de VRAIS clics remis à la fenêtre invisible de l'essai. Ouvrir « Tes apps » depuis la pilule du Centre,
    /// brancher Mail (autorisation refusée puis donnée), Notion (une clé fausse, puis une bonne, la base, la personne), Airtable (la
    /// base, la table) ; une nouveauté îlot fermé (l'aile, puis UN bandeau qui regroupe, « Ouvrir ») ; la liste des Nouveautés ; le survol
    /// qui s'y ouvre ; « ‹ » et deux doigts vers la droite ; débrancher (confirmation, clé effacée). À chaque écran : la forme a la hauteur
    /// de ce qu'elle montre, et aucun texte de l'interface n'est coupé, à la plus petite caméra (179 pt) comme à la plus grande (200 pt).
    /// Faux Mail, faux réseau, coffre en mémoire, fichier dans le dossier de l'essai : jamais la vraie Mail, Notion, Airtable ni le Trousseau.
    @MainActor
    static func apps(_ c: IlotControleur, dossier: URL, verifier: (Bool, String) -> Void, attendre: (Double, () -> Bool) -> Void) {
        let m = c.moteur
        // ses propres ouvertures capturées (une section d'avant a pu remplacer celles de l'essai), rendues à la fin
        var ouverts: [URL] = []
        let ouvrirAvant = c.ouvrir
        c.ouvrir = { ouverts.append($0) }
        defer { c.ouvrir = ouvrirAvant }
        func liens() -> [URL] { ouverts }
        func pause(_ s: Double) { attendre(s) { true } }
        func clic(_ p: CGPoint?, _ apres: Double = 0.7) {
            guard let p else { verifier(false, "point de clic introuvable"); return }
            c.panneau.envoyerSouris(.leftMouseDown, en: p); pause(0.06); c.panneau.envoyerSouris(.leftMouseUp, en: p); pause(apres)
        }
        func attendreSondage() { attendre(5) { c.sondageAppsEnCours || m.apps.occupe } }
        func posee() { attendre(1.5) { abs(m.geo[2].x - m.geo[2].cibleFinale) > 0.05 } }
        /// La forme a la hauteur de ce que la carte montre, et aucun texte n'est coupé aux deux caméras.
        func controlerEcran(_ quoi: String) {
            posee()
            verifier(abs(m.geo[2].cibleFinale - Double(m.grille.hauteur(m.courante))) < 0.5 && m.geo[2].cibleFinale <= Double(m.geometrie.hauteur) + MesuresApps.profondeurMax + 0.5,
                     "\(quoi) : la forme a la hauteur de la carte (\(Int(m.geo[2].cibleFinale)) pt)")
            for cam in [179.0, 200.0] {
                let w = 2 * (CGFloat(cam) / 2 + 144) - 2 * GrilleIlot.marge - GrilleIlot.placePoints
                let d = PlanApps.debordements(m.apps, largeur: w)
                verifier(d.isEmpty, "\(quoi), caméra \(Int(cam)) : aucun texte coupé\(d.isEmpty ? "" : " (\(d.joined(separator: " ; ")))")")
            }
        }

        print("Tes apps : brancher, nouveautés, survol, retour, débrancher (faux Mail, faux réseau, coffre en mémoire)")
        c.lecture.modele.morceau = nil; c.lecture.surIlot(false)
        m.fermer(); c.panneau.simulerPointeur(forme: false); pause(0.8)
        attendre(IlotEssai.sousCharge(6)) { m.bandeau != nil }

        // --- la façade de l'essai
        let mail = MailEssai(), reseau = ReseauEssai(), coffre = CoffreEnMemoire()
        let fichier = dossier.appendingPathComponent("apps.json")
        var journal: [String] = []
        let base = c.maintenant()
        let jour = ReponseHTTP.jour(base)
        c.fabriqueApps = { c in
            AppsBranchees(magasin: MagasinJSON(url: fichier, nom: "apps", journal: { Log.ecrire($0) }), coffre: coffre, transport: reseau, mail: mail,
                          agenda: { [weak c] in c?.evenements ?? [] }, horloge: { [weak c] in c?.maintenant() ?? Date() }, heure: { FormatIlot.heure($0) },
                          journal: { journal.append($0); Log.ecrire($0) },
                          espacementNotion: EspacementRequetes(ecart: 0), espacementAirtable: EspacementRequetes(ecart: 0))
        }
        c.facadeApps = nil
        var presse: String? = nil
        c.lireCleCollee = { presse }
        c.injecterEvenements([EvenementAgenda(id: "essai-rdv", titre: "Point client", debut: base.addingTimeInterval(2 * 3600), fin: base.addingTimeInterval(2 * 3600 + 1800),
                                              lien: URL(string: "https://meet.exemple.fr/abc-defg-hij"))])
        let calendrierAvant = m.calendrierActif
        defer { m.calendrierActif = calendrierAvant; m.donneesChangees() }
        m.calendrierActif = true
        mail.erreur = .autorisationMail
        c.demarrerApps()
        attendreSondage(); pause(0.3)
        verifier(c.apps.estBranchee(.agenda) && !c.apps.estBranchee(.mail) && c.apps.memoire.agendaPropose == true,
                 "le calendrier permis : l'Agenda est branché d'office, une fois (rien à brancher)")

        // --- 1. « Tes apps » depuis la pilule du Centre (vrai clic)
        m.clicForme(); pause(0.9)
        let ent = PlanCentre.cadreEntete(m.grille)
        let f = EnteteCentre.formes(m, largeur: ent.width)
        verifier(m.courante == .centre && f.apps && EnteteCentre.largeurOccupee(m, largeur: ent.width) <= ent.width,
                 "le Centre : la pilule « Tes apps » avec son nom, toute la ligne tient (\(Int(EnteteCentre.largeurOccupee(m, largeur: ent.width))) pt pour \(Int(ent.width)))")
        // la ligne la plus chargée (« ‹ Rendez-vous », l'étagère en haut…) aux deux caméras : rien ne dépasse, jamais un mot coupé
        for cam in [179.0, 200.0] {
            let w = 2 * (CGFloat(cam) / 2 + 144) - 2 * GrilleIlot.marge - GrilleIlot.placePoints
            let gauches = ["Vidéo", "Musique", "Minuteur", "Micro", "Claude", "Réunion", "Rendez-vous", "Rappel"].map { PiluleCentre.largeur($0, retour: true) }
                + [MesureIlot.texte("Centre", 13.5, .semibold) + 2, 120]
            let pire = gauches.map { g -> CGFloat in
                let fo = EnteteCentre.formes(gauche: g, largeur: w)
                return EnteteCentre.largeurFixe(gauche: g) + EnteteCentre.piluleDicteesForme(entiere: fo.dictees) + EnteteCentre.piluleApps(entiere: fo.apps)
            }.max() ?? 0
            verifier(pire <= w, "en-tête du Centre le plus chargé, caméra \(Int(cam)) : \(Int(pire)) pt pour \(Int(w)), formes courtes mesurées")
        }
        clic(EnteteCentre.centrePilule(.apps, m, entete: ent), 0.9)
        verifier(m.courante == .apps && m.epingle && m.nomRetour == "Centre", "vrai clic sur « Tes apps » : la liste, « ‹ Centre » (\(m.courante))")
        verifier(m.apps.ligne(.agenda).bouton == .branche && m.apps.ligne(.mail).bouton == .brancher && m.apps.ligne(.notion).bouton == .brancher,
                 "Agenda « Branché », Mail et Notion « Brancher » (maquette, étape 1)")
        controlerEcran("Tes apps")

        // --- 2. Mail : macOS refuse d'abord (Automatisation), puis accepte
        clic(PlanApps.pointBouton(m.grille, .mail, .brancher), 0.6)
        attendre(3) { m.apps.occupe }
        verifier(c.apps.estBranchee(.mail) && m.apps.ligne(.mail).bouton == .aRevoir && m.apps.ligne(.mail).alerte,
                 "Mail branché, l'autorisation refusée : « À revoir », « \(m.apps.ligne(.mail).sousTitre) »")
        clic(PlanApps.pointBouton(m.grille, .mail, .aRevoir), 0.9)
        attendre(3) { m.apps.occupe }
        verifier(m.courante == .appsDetail && m.apps.detail == .mail && m.apps.blocs.contains { if case .erreur(_, .reglagesMail) = $0 { return true }; return false },
                 "le détail de Mail : l'erreur dite en entier, avec « Ouvrir les Réglages »")
        controlerEcran("détail de Mail (erreur)")
        let avant = liens().count
        clic(PlanApps.pointGesteErreur(m.grille, m.apps), 0.6)
        verifier(liens().count == avant + 1 && liens().last?.absoluteString.hasPrefix("x-apple.systempreferences:") == true, "« Ouvrir les Réglages » : Confidentialité › Automatisation")
        // l'autorisation donnée : ouvrir le détail réessaie (un geste) ; le premier passage est silencieux (rien d'ancien n'est annoncé)
        mail.erreur = nil
        mail.messages = [MessageMail(id: "ancien-1@exemple.fr", expediteur: "Atelier Nord", objet: "Facture de novembre", recu: base.addingTimeInterval(-1800))]
        clic(PlanApps.pointRetour(m.grille, .appsDetail), 0.8)
        verifier(m.courante == .apps, "vrai clic sur « ‹ Tes apps » : la liste (\(m.courante))")
        clic(PlanApps.pointBouton(m.grille, .mail, .aRevoir), 0.9)
        attendre(3) { m.apps.occupe || c.sondageAppsEnCours }
        pause(0.3)
        verifier(m.apps.etat(.mail).dateAJour != nil && m.bandeau == nil && m.apps.nonLues.isEmpty,
                 "Mail lu : « Branché », le mail déjà là n'est pas annoncé (premier passage)")
        controlerEcran("détail de Mail")

        // --- 3. Notion : une clé fausse, puis une bonne ; la base ; la personne
        reseau.repondre("GET https://api.notion.com/v1/users/me", #"{"object":"user","id":"9a1b","type":"bot","name":"Voxile","bot":{"workspace_name":"Espace Essai"}}"#)
        reseau.repondre("POST https://api.notion.com/v1/search", #"{"object":"list","results":[{"object":"database","id":"0f0e0d0c-1111-4222-8333-444455556666","title":[{"plain_text":"Tâches de l'équipe"}]},{"object":"database","id":"aaaabbbb-1111-4222-8333-444455556666","title":[{"plain_text":"Idées"}]}],"has_more":false}"#)
        reseau.repondre("GET https://api.notion.com/v1/databases/0f0e0d0c", #"{"object":"database","id":"0f0e0d0c-1111-4222-8333-444455556666","title":[{"plain_text":"Tâches de l'équipe"}],"properties":{"Nom":{"id":"title","type":"title","title":{}},"Échéance":{"id":"a1","type":"date","date":{}},"Assigné à":{"id":"b1","type":"people","people":{}}}}"#)
        reseau.repondre("GET https://api.notion.com/v1/users?", #"{"object":"list","results":[{"object":"user","id":"11111111-2222-4333-8444-555555555555","type":"person","name":"Camille Essai"},{"object":"user","id":"b0b","type":"bot","name":"Voxile"}]}"#)
        reseau.repondre("POST https://api.notion.com/v1/databases/0f0e0d0c-1111-4222-8333-444455556666/query", #"{"object":"list","results":[],"has_more":false}"#)
        clic(PlanApps.pointRetour(m.grille, .appsDetail), 0.8)
        clic(PlanApps.pointBouton(m.grille, .notion, .brancher), 0.9)
        verifier(m.courante == .appsDetail && m.apps.parcours?.etape == .cle && m.apps.parcours?.boutonActif == false, "Brancher Notion : la clé à coller, « Vérifier la clé » grisé")
        controlerEcran("Brancher Notion (clé vide)")
        let requetesAvant = reseau.requetes
        clic(PlanApps.pointBouton(m.grille, m.apps), 0.5)
        verifier(reseau.requetes == requetesAvant && m.courante == .appsDetail && m.fenetreOuverte, "« Vérifier » grisé : un clic ne fait rien (aucune requête, l'îlot reste)")
        presse = nil
        clic(PlanApps.pointColler(m.grille, m.apps), 0.5)
        verifier(m.apps.parcours?.presseVide == true && m.apps.blocs.contains { if case .erreur = $0 { return true }; return false }, "« Coller », presse-papiers vide : dit, rien d'inventé")
        let cleFausse = "ntn_fauxfauxfauxfauxfauxfauxfauxfaux12", cleBonne = "ntn_essaiEssaiEssaiEssaiEssaiEssaiK7Rm"
        presse = cleFausse
        clic(PlanApps.pointColler(m.grille, m.apps), 0.5)
        verifier(m.apps.parcours?.saisie == cleFausse && m.apps.parcours?.boutonActif == true, "« Coller » (un bouton, jamais ⌘V) : la clé collée, montrée masquée")
        controlerEcran("Brancher Notion (clé collée)")
        clic(PlanApps.pointBouton(m.grille, m.apps), 0.3)
        attendre(5) { m.apps.occupe }
        verifier(m.apps.parcours?.erreur == .cleRefusee(.notion) && coffre.lire(.notion) == nil && !c.apps.estBranchee(.notion),
                 "clé fausse : « \(ErreurApp.cleRefusee(.notion).texte) », rien n'est rangé")
        controlerEcran("Brancher Notion (clé refusée)")
        presse = cleBonne
        clic(PlanApps.pointColler(m.grille, m.apps), 0.5)
        clic(PlanApps.pointBouton(m.grille, m.apps), 0.3)
        attendre(5) { m.apps.occupe }
        verifier(m.apps.parcours?.etape == .bases && m.apps.parcours?.choix.count == 2 && coffre.lire(.notion) == cleBonne && m.apps.parcours?.saisie == nil,
                 "bonne clé : vérifiée, rangée dans le coffre, les deux bases proposées (la clé ne reste plus dans l'interface)")
        controlerEcran("Brancher Notion (bases)")
        clic(PlanApps.pointChoix(m.grille, m.apps, "0f0e0d0c-1111-4222-8333-444455556666"), 0.5)
        clic(PlanApps.pointBouton(m.grille, m.apps), 0.3)
        attendre(5) { m.apps.occupe }
        verifier(m.apps.parcours?.etape == .personnes && m.apps.parcours?.choix.count == 1, "la base a « Assigné à » : qui es-tu dans Notion ? (une personne, pas l'intégration)")
        controlerEcran("Brancher Notion (personne)")
        clic(PlanApps.pointChoix(m.grille, m.apps, "11111111-2222-4333-8444-555555555555"), 0.5)
        clic(PlanApps.pointBouton(m.grille, m.apps), 0.3)
        attendre(5) { m.apps.occupe || c.sondageAppsEnCours }
        pause(0.3)
        verifier(c.apps.estBranchee(.notion) && m.apps.parcours == nil && m.apps.detail == .notion && m.apps.notion?.personneNom == "Camille Essai"
                 && m.apps.blocs.contains { if case .info(let i) = $0 { return i.genre == .cle && i.valeur == ClePartielle.masque(cleBonne) }; return false },
                 "Notion branché : sa base, « Assignées à : Camille Essai », la clé masquée")
        controlerEcran("détail de Notion")

        // --- 4. Airtable : le jeton, la base (une seule : choisie d'office), la table
        reseau.repondre("GET https://api.airtable.com/v0/meta/whoami", #"{"id":"usrEssai0000001","scopes":["data.records:read","schema.bases:read"]}"#)
        reseau.repondre("GET https://api.airtable.com/v0/meta/bases", #"{"bases":[{"id":"appEssai00000001","name":"Suivi des chantiers","permissionLevel":"create"}]}"#)
        reseau.repondre("GET https://api.airtable.com/v0/meta/bases/appEssai00000001/tables", #"{"tables":[{"id":"tblEssai00000001","name":"Chantiers","primaryFieldId":"fldNom000000001","fields":[{"id":"fldNom000000001","name":"Nom","type":"singleLineText"},{"id":"fldModif00000001","name":"Dernière modification","type":"lastModifiedTime"}]},{"id":"tblEssai00000002","name":"Notes","primaryFieldId":"fldTitre0000001","fields":[{"id":"fldTitre0000001","name":"Titre","type":"multilineText"}]}]}"#)
        reseau.repondre("GET https://api.airtable.com/v0/appEssai00000001/tblEssai00000001?", #"{"records":[]}"#)
        clic(PlanApps.pointRetour(m.grille, .appsDetail), 0.8)
        clic(PlanApps.pointBouton(m.grille, .airtable, .brancher), 0.9)
        presse = "patEssai00000001.essaiessaiessaiessaiessaiessai9fQz"
        clic(PlanApps.pointColler(m.grille, m.apps), 0.5)
        clic(PlanApps.pointBouton(m.grille, m.apps), 0.3)
        attendre(5) { m.apps.occupe }
        verifier(m.apps.parcours?.etape == .bases && m.apps.parcours?.selection == "appEssai00000001", "jeton vérifié : la seule base est déjà choisie")
        clic(PlanApps.pointBouton(m.grille, m.apps), 0.3)
        attendre(5) { m.apps.occupe }
        verifier(m.apps.parcours?.etape == .tables && m.apps.parcours?.tables.count == 2, "deux tables : laquelle suivre ?")
        controlerEcran("Brancher Airtable (tables)")
        clic(PlanApps.pointChoix(m.grille, m.apps, "tblEssai00000001"), 0.5)
        clic(PlanApps.pointBouton(m.grille, m.apps), 0.3)
        attendre(5) { m.apps.occupe || c.sondageAppsEnCours }
        pause(0.3)
        verifier(c.apps.estBranchee(.airtable) && m.apps.airtable?.tableNom == "Chantiers" && m.apps.detail == .airtable, "Airtable branché : « Suivi des chantiers › Chantiers »")
        controlerEcran("détail d'Airtable")
        clic(PlanApps.pointRetour(m.grille, .appsDetail), 0.8)
        verifier(AppBranchee.allCases.allSatisfy { m.apps.ligne($0).bouton == .branche }, "les quatre apps « Branché » (maquette, étape 4)")
        controlerEcran("Tes apps, tout branché")

        // --- 5. une nouveauté îlot fermé : l'aile, puis UN bandeau ; ce qui arrive pendant le bandeau le rejoint
        m.fermer(); c.panneau.simulerPointeur(forme: false); pause(1.0)
        attendre(4) { c.sondageAppsEnCours }
        mail.messages.insert(MessageMail(id: "neuf-1@exemple.fr", expediteur: "Camille Roche", objet: "Devis cuisine, version 2", recu: c.maintenant()), at: 0)
        mail.messages.insert(MessageMail(id: "neuf-2@exemple.fr", expediteur: "Bureau d'études", objet: "Plans modifiés", recu: c.maintenant()), at: 0)
        c.sonderApps(force: true)
        attendre(3) { m.courante != .appsAile }
        verifier(m.courante == .appsAile && m.bandeau?.apps?.elements.count == 2, "deux mails : l'aile s'allume d'abord (\(m.courante))")
        let place = m.grille.bordAile(.appsAile) - m.grille.hc - 4
        let motAile = AileApps.texte(m.bandeau?.apps ?? AnnonceApps([]), place: place)
        verifier(motAile == "2 mails" && MesureIlot.texte(motAile, 13, .semibold, chiffres: true) <= place, "l'aile dit « \(motAile) », mesuré dans l'aile (\(Int(place)) pt)")
        attendre(IlotMoteur.dureeAileApps + 1.5) { m.courante != .appsBandeau }
        verifier(m.courante == .appsBandeau && m.bandeau?.apps?.titre == "2 nouveaux mails", "puis un seul bandeau : « \(m.bandeau?.apps?.titre ?? "?") »")
        reseau.repondre("POST https://api.notion.com/v1/databases/0f0e0d0c-1111-4222-8333-444455556666/query",
                        #"{"object":"list","results":[{"object":"page","id":"22222222-3333-4444-8555-666666666666","url":"https://www.notion.so/Page-22222222333344448555666666666666","archived":false,"last_edited_time":"2026-11-13T09:00:00.000Z","properties":{"Échéance":{"type":"date","date":{"start":"\#(jour)","end":null}},"Nom":{"type":"title","title":[{"plain_text":"Rappeler le menuisier"}]}}}],"has_more":false}"#)
        attendre(4) { c.sondageAppsEnCours }
        c.sonderApps(force: true)
        attendre(3) { m.bandeau?.apps?.elements.count != 3 }
        verifier(m.courante == .appsBandeau && m.bandeau?.apps?.titre == "3 nouveautés" && m.bandeau?.apps?.sousTitre == "2 mails, 1 tâche",
                 "une tâche arrive pendant le bandeau : elle le rejoint, « 3 nouveautés · 2 mails, 1 tâche », jamais une rafale")
        posee()
        if let lc = m.contenus[.appsBandeau] {
            // la forme épouse le contenu mesuré (le corps le plus serré peut être plus large : le contenu y est centré)
            let z = m.grille.zone(.appsBandeau)
            verifier(lc <= z.width + 0.5, "le bandeau épouse son contenu (\(Int(lc)) pt pour \(Int(z.width)))")
        }
        // « Ouvrir » (vrai clic) : plusieurs nouveautés, la liste
        let za = m.grille.zoneAnnonce(.appsBandeau)
        let lo = MesureIlot.bouton(.init(titre: "Ouvrir", style: .blanc))
        clic(CGPoint(x: za.maxX - lo / 2, y: za.midY), 0.9)
        verifier(m.courante == .appsNouveautes && m.bandeau == nil && !m.apps.neuf, "« Ouvrir » sur plusieurs nouveautés : la liste des Nouveautés (\(m.courante))")
        let sections = PlanNouveautes.sections(m.apps.actuelles)
        verifier(sections.map(\.app) == [.mail, .agenda, .notion] && m.apps.nonLues.count == 3, "rangée par app : Mail, Agenda, Notion ; trois non lues (\(sections.map(\.app.rawValue)))")
        controlerEcran("Nouveautés")
        clic(PlanApps.pointOuvrir(m.grille, m.apps, "mail:neuf-1@exemple.fr"), 0.6)
        verifier(liens().last?.absoluteString.hasPrefix("message://%3Cneuf-1@exemple.fr%3E") == true && !m.apps.nonLues.contains("mail:neuf-1@exemple.fr") && !m.fenetreOuverte,
                 "« Ouvrir » sur un mail : il s'ouvre dans Mail, il n'est plus « non lu », l'îlot se range")

        // --- 6. une seule nouveauté : « Ouvrir » l'ouvre directement ; au survol, l'îlot s'ouvre sur les Nouveautés
        pause(0.6)
        attendre(4) { c.sondageAppsEnCours }
        mail.messages.insert(MessageMail(id: "neuf-3@exemple.fr", expediteur: "Mairie", objet: "Permis accordé", recu: c.maintenant()), at: 0)
        c.sonderApps(force: true)
        attendre(IlotMoteur.dureeAileApps + 3) { m.courante != .appsBandeau }
        verifier(m.bandeau?.apps?.titre == "Mairie" && m.bandeau?.apps?.sousTitre == "Permis accordé \u{00B7} Mail", "un seul mail : « Mairie · Permis accordé · Mail »")
        // pas touché : il se range seul
        attendre(IlotMoteur.dureeBandeauApps + IlotEssai.sousCharge(2)) { m.bandeau != nil }
        verifier(m.bandeau == nil && m.apps.neuf, "le bandeau se range seul ; le neuf reste pour le survol")
        c.panneau.simulerPointeur(forme: true); pause(0.9)
        verifier(m.courante == .appsNouveautes && !m.apps.neuf, "survol avec du neuf : l'îlot s'ouvre sur les Nouveautés (\(m.courante))")
        clic(PlanApps.pointRetour(m.grille, .appsNouveautes), 0.8)
        verifier(m.courante == .apps, "« ‹ Tes apps » : la liste (\(m.courante))")
        // deux doigts vers la droite : comme « ‹ Centre »
        let droite = c.panneau.signeDoigtsVersLaDroite()
        let milieu = CGPoint(x: 0, y: m.geometrie.hauteur + 120)
        for (i, dx) in [8, 16, 20, 20].enumerated() { c.panneau.envoyerDefilement(dy: 0, dx: Int32(dx) * droite, en: milieu, phase: i == 0 ? 1 : 2); pause(0.016) }
        c.panneau.envoyerDefilement(dy: 0, en: milieu, phase: 4); pause(0.7)
        verifier(m.courante == .centre, "deux doigts vers la droite sur « Tes apps » : le Centre (\(m.courante))")
        m.fermer(); c.panneau.simulerPointeur(forme: false); pause(0.9)
        c.panneau.simulerPointeur(forme: true); pause(0.9)
        verifier(m.courante == .centre, "survol sans neuf : le Centre, comme d'habitude (\(m.courante))")

        // --- 7. débrancher Airtable : une confirmation, puis la clé effacée
        clic(EnteteCentre.centrePilule(.apps, m, entete: PlanCentre.cadreEntete(m.grille)), 0.9)
        clic(PlanApps.pointBouton(m.grille, .airtable, .branche), 0.9)
        verifier(m.courante == .appsDetail && m.apps.detail == .airtable, "le détail d'Airtable (maquette, étape 9)")
        clic(PlanApps.pointDebrancher(m.grille, m.apps), 0.7)
        verifier(m.apps.confirmation && c.apps.estBranchee(.airtable), "« Débrancher » : une confirmation d'abord, rien n'est encore effacé")
        controlerEcran("confirmation")
        clic(PlanApps.pointConfirmer(m.grille, m.apps), 0.9)
        verifier(!c.apps.estBranchee(.airtable) && coffre.lire(.airtable) == nil && m.courante == .apps && m.apps.ligne(.airtable).bouton == .brancher,
                 "confirmé : Airtable débranché, son jeton effacé, retour à la liste (« Brancher »)")

        // --- jamais une clé dans le fichier ni au journal
        let texte = (try? String(contentsOf: fichier, encoding: .utf8)) ?? ""
        verifier(!texte.isEmpty && !texte.contains(cleBonne) && !texte.contains("patEssai") && journal.allSatisfy { !$0.contains("ntn_") && !$0.contains("patEssai") },
                 "apps.json et le journal : aucune clé (\(journal.count) lignes)")
        verifier(!journal.contains { $0.contains("Camille") || $0.contains("Mairie") || $0.contains("Devis") }, "le journal : ni nom ni objet")
        m.fermer(); c.panneau.simulerPointeur(forme: false); pause(0.8)
        c.reveilApps?.cancel(); c.reveilApps = nil
        c.facadeApps = nil
        m.apps = EtatAppsIlot(); m.donneesChangees()
    }
}

extension EtatApp {
    /// L'heure du dernier passage réussi (essais).
    var dateAJour: Date? { if case .aJour(let d) = self { return d }; return nil }
}
