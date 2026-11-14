import AppKit
import SwiftUI
import DicteeCore

// « Tes apps » dans l'îlot (maquette design/maquettes/ilot-apps.html ; décisions de Hugues du 13/11 au soir) : le contrôleur.
// - la façade (DicteeCore/AppsBranchees.swift) est fabriquée au démarrage ; une seule minuterie la rappelle à `prochainSondage()` ;
// - `surNouveautes` → l'aile s'allume (le logo, « 1 mail »), puis UN bandeau qui regroupe tout ce qui arrive ensemble (« 3 nouveaux
//   mails ») ; il se range seul ; « Ouvrir » ouvre la nouveauté (seule) ou la liste des Nouveautés ;
// - `surChangement` → les cartes (la liste « Tes apps », le détail d'une app, les Nouveautés) ;
// - au survol, s'il y a du neuf, l'îlot s'ouvre sur « Nouveautés » (IlotMoteur.surNouveautesSiNeuf) ;
// - brancher : Mail et Agenda d'un clic ; Notion et Airtable : « Coller » (jamais ⌘V), « Vérifier », la base (la table, la personne) ;
//   HubSpot et Stripe : la clé seule ; Shopify : l'adresse de la boutique, l'identifiant de l'app, son secret ;
// - « Tes apps » a deux onglets (« Au quotidien », « Vente ») : quatre apps au plus par page, la hauteur d'avant ;
// - débrancher : une confirmation, puis la clé est effacée.
// Rien de ce que disent les apps (objets, noms, titres) n'est écrit au journal : seulement l'app, l'état, des nombres.

/// Les gestes des cartes de « Tes apps ».
enum ActionApps {
    /// La pilule « Tes apps » du Centre, « Nouveautés » de la liste, « ‹ » passent par la navigation de l'îlot ; ceci est le reste.
    case brancher(AppBranchee)
    case detail(AppBranchee)
    case nouveautes
    case groupe(AppBranchee.Groupe)
    case coller
    case pageCle
    case valider
    case choisir(String)
    case page(Int)
    case changer(InfoApp.Genre)
    case geste(ErreurApp.Geste)
    case debrancher, annulerDebrancher, confirmerDebrancher
    case ouvrir(String)
    case ouvrirAnnonce
    case toutLu
}

// MARK: - les logos

/// Les vrais logos (décision de Hugues, 13/11) : Mail et Calendrier sont les icônes des apps installées (rien n'est gardé dans le dépôt) ;
/// Notion, Airtable, Shopify, HubSpot et Stripe, leurs marques en SVG (Resources/Logos, tracés simple-icons CC0) posées sur une tuile blanche à la taille des
/// icônes du Mac. Une marque absente : une tuile neutre avec l'initiale (comme la maquette).
@MainActor
enum LogosApps {
    private static var cache: [AppBranchee: NSImage] = [:]
    static let cheminMail = "/System/Applications/Mail.app", cheminCalendrier = "/System/Applications/Calendar.app"

    static func image(_ a: AppBranchee) -> NSImage {
        if let i = cache[a] { return i }
        let i: NSImage
        switch a {
        case .mail: i = icone(cheminMail) ?? tuile(nil, initiale: "M")
        case .agenda: i = icone(cheminCalendrier) ?? tuile(nil, initiale: "A")
        case .notion: i = bitmap(tuile(marque("notion"), initiale: "N"))
        case .airtable: i = bitmap(tuile(marque("airtable"), initiale: "A"))
        case .shopify: i = bitmap(tuile(marque("shopify"), initiale: "S"))
        case .hubspot: i = bitmap(tuile(marque("hubspot"), initiale: "H"))
        case .stripe: i = bitmap(tuile(marque("stripe"), initiale: "S"))
        }
        cache[a] = i
        return i
    }

    /// Une image de 128 px en 8 bits (le tracé SVG se dessine sinon en 16 bits flottants : rendus deux fois plus lourds, rien de plus net à 30 pt).
    private static func bitmap(_ i: NSImage) -> NSImage { LectureControleur.reduire(i, pixels: 128, rogner: false) ?? i }

    private static func icone(_ chemin: String) -> NSImage? {
        // réduite une fois à 128 px (8 bits) : l'icône du système porte des représentations jusqu'à 1024 px en 16 bits, inutiles à 30 pt
        guard FileManager.default.fileExists(atPath: chemin) else { return nil }
        let i = NSWorkspace.shared.icon(forFile: chemin)
        return LectureControleur.reduire(i, pixels: 128, rogner: false) ?? i
    }

    /// Les dossiers où chercher les marques : celui de l'app, puis Resources/Logos du dépôt (essais et rendus, lancés depuis .build).
    static var dossiers: [URL] {
        let depot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Logos", isDirectory: true)
        return [Bundle.main.resourceURL?.appendingPathComponent("Logos", isDirectory: true), depot].compactMap { $0 }
    }
    static func marque(_ nom: String) -> NSImage? {
        for d in dossiers {
            let u = d.appendingPathComponent("\(nom).svg")
            if FileManager.default.fileExists(atPath: u.path), let i = NSImage(contentsOf: u), i.isValid { return i }
        }
        return nil
    }

    /// Une tuile d'app du Mac : le carré arrondi blanc occupe 80 % de la place (comme les icônes de macOS), la marque 62 % du carré.
    static func tuile(_ marque: NSImage?, initiale: String) -> NSImage {
        NSImage(size: NSSize(width: 64, height: 64), flipped: false) { r in
            let t = r.insetBy(dx: r.width * 0.1, dy: r.height * 0.1)
            let forme = NSBezierPath(roundedRect: t, xRadius: t.width * 0.225, yRadius: t.height * 0.225)
            (marque == nil ? NSColor(white: 0.3, alpha: 1) : NSColor.white).setFill()
            forme.fill()
            NSColor(white: 0, alpha: 0.12).setStroke(); forme.lineWidth = r.width / 64; forme.stroke()
            if let m = marque {
                let c = t.width * 0.62
                m.draw(in: NSRect(x: t.midX - c / 2, y: t.midY - c / 2, width: c, height: c))
            } else {
                let attributs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: t.height * 0.5, weight: .bold), .foregroundColor: NSColor.white]
                let s = NSAttributedString(string: initiale, attributes: attributs), z = s.size()
                s.draw(at: NSPoint(x: t.midX - z.width / 2, y: t.midY - z.height / 2))
            }
            return true
        }
    }
}

// MARK: - le contrôleur

extension IlotControleur {
    var apps: AppsBranchees {
        if let f = facadeApps { return f }
        let f = fabriqueApps(self)
        facadeApps = f
        f.surNouveautes = { [weak self] n in self?.nouveautesArrivees(n) }
        f.surChangement = { [weak self] in self?.appsChangees() }
        return f
    }

    /// Au démarrage : la façade, une clé laissée en route effacée, l'Agenda branché une fois si le calendrier est permis, le premier
    /// sondage.
    func demarrerApps() {
        let f = apps
        for a in AppBranchee.allCases where a.demandeUneCle { f.abandonner(a) }
        f.brancherAgendaUneFois(calendrierPermis: moteur.calendrierActif)
        appsChangees()
        programmerSondageApps()
    }

    func appsCalendrierChange() {
        guard let f = facadeApps else { return }
        f.brancherAgendaUneFois(calendrierPermis: moteur.calendrierActif)
        appsChangees()
        programmerSondageApps()
    }

    /// La façade a changé : les cartes recopient ce qu'elle dit (les champs de l'interface restent).
    func appsChangees() {
        guard let f = facadeApps else { return }
        var e = moteur.apps
        e.branchees = f.memoire.branchees
        e.etats = f.etats
        e.actuelles = f.actuelles
        e.notion = f.memoire.notion
        e.airtable = f.memoire.airtable
        e.shopify = f.memoire.shopify
        e.hubspot = f.memoire.hubspot
        e.stripe = f.memoire.stripe
        // la clé masquée : lue une fois dans le Trousseau (pas à chaque sondage), oubliée quand l'app est débranchée
        var cles: [AppBranchee: String] = [:]
        for a in AppBranchee.allCases where a.demandeUneCle && f.estBranchee(a) { cles[a] = e.cles[a] ?? f.cleMasquee(a) }
        e.cles = cles
        e.rendezVous = PlanAgenda.prochain(evenements, a: maintenant())
        e.calendrierPermis = moteur.calendrierActif
        // une nouveauté qui n'est plus là (le mail lu dans Mail) n'a plus de point bleu
        let ids = Set(e.toutes.map(\.id))
        e.nonLues = e.nonLues.intersection(ids)
        if e.nonLues.isEmpty, !e.aDesNouveautes { e.neuf = false }
        moteur.apps = e
        moteur.donneesChangees()
        programmerSondageApps()
    }

    /// Une seule minuterie, à la date que donne la façade (aucune quand rien n'est branché ou que tout attend un geste).
    func programmerSondageApps() {
        reveilApps?.cancel(); reveilApps = nil
        guard let f = facadeApps, !sondageAppsEnCours, let d = f.prochainSondage() else { return }
        let attente = max(0.05, d.timeIntervalSince(maintenant()))
        let item = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.sonderApps() } }
        reveilApps = item
        DispatchQueue.main.asyncAfter(deadline: .now() + attente, execute: item)
    }

    func sonderApps(force: Bool = false) {
        guard let f = facadeApps, !sondageAppsEnCours else { return }
        sondageAppsEnCours = true
        Task { @MainActor [weak self] in
            await f.sonder(force: force)
            self?.sondageAppsEnCours = false
            self?.programmerSondageApps()
        }
    }

    /// Du nouveau : l'aile, puis le bandeau ; ce qui arrive pendant qu'ils sont là les rejoint. La liste ouverte sous les yeux : seulement
    /// les points bleus.
    func nouveautesArrivees(_ n: [Nouveaute]) {
        guard !n.isEmpty else { return }
        moteur.apps.nonLues.formUnion(n.map(\.id))
        Log.ecrire("apps : \(n.count) nouveauté\(n.count > 1 ? "s" : "") (\(Set(n.map(\.app.rawValue)).sorted().joined(separator: ", ")))")
        if moteur.fenetreOuverte, moteur.courante == .appsNouveautes { moteur.donneesChangees(); return }
        moteur.apps.neuf = true
        if moteur.regrouperApps(n) { return }
        moteur.annoncer(bandeau: BandeauIlot(vue: .appsAile, jusqua: maintenant().addingTimeInterval(IlotMoteur.dureeAileApps), ligne1: "", ligne2: "",
                                             apps: AnnonceApps(n)))
    }

    // MARK: les gestes

    func agirApps(_ action: ActionApps) {
        let f = apps
        switch action {
        case .brancher(let a): brancherApp(a)
        case .detail(let a):
            moteur.apps.detail = a; moteur.apps.confirmation = false
            moteur.apps.groupe = a.groupe
            // le détail d'une app branchée : ce qu'elle suit (un « Changer » laissé en route est oublié)
            if f.estBranchee(a), moteur.apps.parcours?.app == a { moteur.apps.parcours = nil }
            ouvrirCarteApps(.appsDetail)
            // Mail arrêté par un refus (l'autorisation donnée depuis, dans Réglages) : ouvrir son détail est le geste qui réessaie
            if a == .mail, let e = f.etats[.mail]?.erreur, e.demandeUnGeste { sonderMaintenant(.mail) }
        case .nouveautes: ouvrirCarteApps(.appsNouveautes)
        case .groupe(let o):
            guard moteur.apps.groupe != o else { return }
            moteur.apps.groupe = o; moteur.donneesChangees()
        case .coller: collerCle()
        case .pageCle:
            if let p = moteur.apps.parcours, let u = p.champ?.page { ouvrir(u); Log.ecrire("apps : page de la clé \(p.app.rawValue) ouverte") }
        case .valider: validerParcours()
        case .choisir(let id):
            guard var p = moteur.apps.parcours else { return }
            p.selection = id; p.baseSansRien = false
            moteur.apps.parcours = p; moteur.donneesChangees()
        case .page(let pas):
            guard var p = moteur.apps.parcours else { return }
            p.page = min(max(0, p.pageMontree + pas), p.pages - 1)
            moteur.apps.parcours = p; moteur.donneesChangees()
        case .changer(let genre): changerReglage(genre)
        case .geste(let g): gesteErreur(g)
        case .debrancher: moteur.apps.confirmation = true; moteur.donneesChangees()
        case .annulerDebrancher: moteur.apps.confirmation = false; moteur.donneesChangees()
        case .confirmerDebrancher:
            guard let a = moteur.apps.detail else { return }
            moteur.apps.confirmation = false
            moteur.apps.parcours = nil
            f.debrancher(a)
            moteur.apps.detail = nil
            // retour à la liste « Tes apps » (l'app y redevient « Brancher »)
            moteur.revenir()
        case .ouvrir(let id):
            guard let x = moteur.apps.toutes.first(where: { $0.id == id }) else { return }
            ouvrirNouveaute(x)
        case .ouvrirAnnonce:
            guard let a = moteur.bandeauVu?.apps else { return }
            if let x = a.seule { moteur.bandeau = nil; ouvrirNouveaute(x) }
            else { moteur.bandeau = nil; moteur.donneesChangees(); ouvrirCarteApps(.appsNouveautes) }
        case .toutLu:
            moteur.apps.nonLues = []; moteur.donneesChangees()
        }
    }

    /// Ouvre une carte de « Tes apps » (elle reste ouverte comme le Centre ; « ‹ » ramène d'où l'on vient).
    func ouvrirCarteApps(_ v: VueIlot) {
        if v == .appsDetail, let a = moteur.apps.detail, a == .agenda { moteur.apps.rendezVous = PlanAgenda.prochain(evenements, a: maintenant()) }
        moteur.ouvrirOutil(v)
    }

    private func brancherApp(_ a: AppBranchee) {
        let f = apps
        moteur.apps.confirmation = false
        switch a {
        case .mail, .agenda:
            if a == .agenda, !moteur.calendrierActif { basculerLeCalendrier() }
            f.brancher(a)
            moteur.apps.detail = a
            // Mail : le premier sondage pose la question de macOS (Automatisation) ; on le fait tout de suite, d'un geste
            sonderMaintenant(a)
            moteur.donneesChangees()
        case .notion, .airtable, .shopify, .hubspot, .stripe:
            // un autre branchement laissé en route : sa clé ne reste pas
            if let p = moteur.apps.parcours, p.app != a { f.abandonner(p.app) }
            if moteur.apps.parcours?.app != a { moteur.apps.parcours = ParcoursApp(app: a) }
            moteur.apps.detail = a
            moteur.apps.groupe = a.groupe
            ouvrirCarteApps(.appsDetail)
        }
    }

    private func sonderMaintenant(_ a: AppBranchee) {
        let f = apps
        moteur.apps.occupe = true
        Task { @MainActor [weak self] in
            _ = await f.reessayer(a)
            self?.moteur.apps.occupe = false
            self?.appsChangees()
        }
    }

    private func collerCle() {
        guard var p = moteur.apps.parcours, p.estChamp else { return }
        let texte = (lireCleCollee() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        p.erreur = nil
        if texte.isEmpty { p.presseVide = true; p.saisie = nil } else { p.presseVide = false; p.saisie = texte }
        moteur.apps.parcours = p
        moteur.donneesChangees()
    }

    /// Le grand bouton du parcours : vérifier la clé, suivre la base (puis la table, ou la personne).
    private func validerParcours() {
        guard let p = moteur.apps.parcours, p.boutonActif, !moteur.apps.occupe else { return }
        let f = apps
        moteur.apps.occupe = true
        moteur.donneesChangees()
        Task { @MainActor [weak self] in
            guard let self else { return }
            var q = p
            q.erreur = nil
            // la liste n'avait pas pu être lue : « Réessayer » la relit
            if p.relireLaListe {
                let r: Result<[ChoixApp], ErreurApp>
                switch p.etape {
                case .bases: r = p.app == .notion ? await f.basesNotion() : await f.basesAirtable()
                case .personnes: r = await f.personnesNotion()
                case .tables, .cle, .boutique, .identifiant:
                    switch await f.tablesAirtable(base: p.base?.id ?? "") {
                    case .failure(let e): r = .failure(e)
                    case .success(let t): q.tables = t; r = .success([])
                    }
                }
                switch r {
                case .failure(let e): q.erreur = e
                case .success(let c): if p.etape != .tables { q.choix = c }; q.page = 0; q.selection = q.options.count == 1 ? q.options[0].id : nil
                }
                self.moteur.apps.occupe = false
                if self.moteur.apps.parcours?.app == q.app { self.moteur.apps.parcours = q }
                self.moteur.donneesChangees()
                return
            }
            switch p.etape {
            case .boutique:
                // l'adresse : lue ici (rien n'est envoyé) ; la boutique se vérifie avec la clé
                if let b = ClientShopify.boutique(depuis: p.saisie ?? "") { q.boutique = b; q.etape = .identifiant; q.saisie = nil }
                else { q.erreur = .introuvable(.shopify) }
            case .identifiant:
                if p.jetonShopify {
                    // un ancien jeton d'app de l'admin : vérifié tout de suite, pas de secret
                    switch await f.enregistrerShopify(boutique: p.boutique ?? "", identifiant: p.saisie ?? "", secret: nil) {
                    case .failure(let e): q.erreur = e; Self.reculerShopify(&q, e)
                    case .success: self.finirParcours(.shopify); return
                    }
                } else if ClientShopify.identifiantVraisemblable(p.saisie ?? "") {
                    q.identifiant = p.saisie; q.saisie = nil; q.etape = .cle
                } else { q.erreur = .cleRefusee(.shopify) }
            case .cle where p.app == .shopify:
                switch await f.enregistrerShopify(boutique: p.boutique ?? "", identifiant: p.identifiant ?? "", secret: p.saisie) {
                case .failure(let e): q.erreur = e; Self.reculerShopify(&q, e)
                case .success: self.finirParcours(.shopify); return
                }
            case .cle where p.app == .hubspot || p.app == .stripe:
                // rien à choisir : la clé vérifiée branche l'app
                switch await f.enregistrerCle(p.saisie ?? "", pour: p.app) {
                case .failure(let e): q.erreur = e
                case .success: self.finirParcours(p.app); return
                }
            case .cle:
                switch await f.enregistrerCle(p.saisie ?? "", pour: p.app) {
                case .failure(let e): q.erreur = e
                case .success(let compte):
                    q.compte = compte; q.saisie = nil
                    let bases = p.app == .notion ? await f.basesNotion() : await f.basesAirtable()
                    switch bases {
                    case .failure(let e): q.erreur = e; q.etape = .bases
                    case .success(let b): q.etape = .bases; q.choix = b; q.selection = b.count == 1 ? b[0].id : nil; q.page = 0
                    }
                }
            case .bases:
                guard let id = p.selection, let base = p.choix.first(where: { $0.id == id }) else { break }
                if p.app == .notion {
                    switch await f.choisirBaseNotion(id) {
                    case .failure(let e): q.erreur = e
                    case .success(let r):
                        if r.proprietePersonne != nil {
                            switch await f.personnesNotion() {
                            case .failure(let e): q.erreur = e
                            case .success(let gens):
                                q.etape = .personnes; q.choix = gens; q.selection = nil; q.page = 0
                            }
                        } else if !r.complet {
                            q.baseSansRien = true
                            f.abandonner(.notion)
                        } else { self.finirParcours(.notion); return }
                    }
                } else {
                    switch await f.tablesAirtable(base: id) {
                    case .failure(let e): q.erreur = e
                    case .success(let t):
                        if t.count == 1 { f.choisirTableAirtable(base: base, table: t[0]); self.finirParcours(.airtable); return }
                        q.base = base; q.etape = .tables; q.tables = t; q.selection = nil; q.page = 0
                    }
                }
            case .tables:
                guard let id = p.selection, let base = p.base, let t = p.tables.first(where: { $0.id == id }) else { break }
                f.choisirTableAirtable(base: base, table: t)
                self.finirParcours(.airtable); return
            case .personnes:
                let nom = p.selection.flatMap { id in p.choix.first { $0.id == id }?.nom }
                f.choisirPersonneNotion(p.selection, nom: nom)
                if f.memoire.notion?.complet == true { self.finirParcours(.notion); return }
                q.baseSansRien = true
            }
            self.moteur.apps.occupe = false
            if self.moteur.apps.parcours?.app == q.app { self.moteur.apps.parcours = q }
            self.moteur.donneesChangees()
        }
    }

    /// Shopify refuse : on revient à ce qu'il faut recoller (l'identifiant et le secret vont ensemble ; une boutique introuvable se
    /// redonne), l'erreur dite au-dessus du champ.
    static func reculerShopify(_ q: inout ParcoursApp, _ e: ErreurApp) {
        switch e {
        case .cleRefusee(.shopify): q.etape = .identifiant; q.identifiant = nil; q.saisie = nil
        case .introuvable(.shopify): q.etape = .boutique; q.boutique = nil; q.identifiant = nil; q.saisie = nil
        default: break
        }
    }

    /// Le branchement est fini : le détail de l'app branchée, et un premier sondage.
    private func finirParcours(_ a: AppBranchee) {
        moteur.apps.occupe = false
        moteur.apps.parcours = nil
        moteur.apps.detail = a
        moteur.apps.cles[a] = nil   // une nouvelle clé a pu être collée : relue
        appsChangees()
        sonderMaintenant(a)
    }

    /// « Changer » la base (ou la personne) d'une app branchée : le parcours reprend au choix, la clé gardée.
    private func changerReglage(_ genre: InfoApp.Genre) {
        guard let a = moteur.apps.detail, a == .notion || a == .airtable, !moteur.apps.occupe else { return }
        let f = apps
        moteur.apps.occupe = true
        moteur.donneesChangees()
        Task { @MainActor [weak self] in
            guard let self else { return }
            var p = ParcoursApp(app: a, etape: .bases)
            if genre == .personne, a == .notion {
                p.etape = .personnes
                switch await f.personnesNotion() {
                case .failure(let e): p.erreur = e
                case .success(let gens): p.choix = gens; p.selection = f.memoire.notion?.personneId
                }
            } else {
                switch a == .notion ? await f.basesNotion() : await f.basesAirtable() {
                case .failure(let e): p.erreur = e
                case .success(let b): p.choix = b; p.selection = a == .notion ? f.memoire.notion?.baseId : f.memoire.airtable?.baseId
                }
            }
            self.moteur.apps.occupe = false
            self.moteur.apps.parcours = p
            self.moteur.donneesChangees()
        }
    }

    private func gesteErreur(_ g: ErreurApp.Geste) {
        guard let a = moteur.apps.parcours?.app ?? moteur.apps.detail else { return }
        switch g {
        case .reessayer:
            if var p = moteur.apps.parcours, p.app == a {
                // l'étape en cours se rejoue (la clé gardée, ou la liste relue)
                p.erreur = nil; moteur.apps.parcours = p
                if p.etape == .cle || p.boutonActif { validerParcours() } else { changerReglage(p.etape == .personnes ? .personne : .base) }
            } else { sonderMaintenant(a) }
        case .autreCle:
            var p = ParcoursApp(app: a)
            // Shopify : la boutique est connue (une clé refusée ne change pas d'adresse), on reprend à l'identifiant ; mais une boutique
            // introuvable se redonne
            if a == .shopify, let b = apps.memoire.shopify?.boutique, apps.etats[.shopify]?.erreur != .introuvable(.shopify) {
                p.boutique = b; p.etape = .identifiant
            }
            moteur.apps.parcours = p
            moteur.donneesChangees()
        case .choisirBase: changerReglage(.base)
        case .reglagesMail:
            if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") { ouvrir(u) }
            Log.ecrire("apps : Réglages Système (Automatisation) ouverts")
        case .aucun: break
        }
    }

    /// Ouvre une nouveauté dans son app (le mail dans Mail, la page Notion, la fiche Airtable, le lien du rendez-vous ou le Calendrier).
    private func ouvrirNouveaute(_ x: Nouveaute) {
        moteur.apps.nonLues.remove(x.id)
        if let u = x.action.adresse { ouvrir(u) }
        else { ouvrir(URL(fileURLWithPath: LogosApps.cheminCalendrier)) }
        Log.ecrire("apps : nouveauté \(x.app.rawValue) ouverte")
        moteur.fermer()
    }
}
