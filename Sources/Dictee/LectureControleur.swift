import AppKit
import ApplicationServices
import DicteeCore

extension Notification.Name {
    /// Un réglage de la lecture en cours a changé (Réglages) : le contrôleur relit `Settings`.
    static let verbeLectureReglages = Notification.Name("verbe.lecture.reglages")
}

/// La lecture en cours dans l'encoche : relie le programme d'aide (ce qui joue), l'îlot et la mini-miniature de la dictée (ce qu'on voit), les réglages et les
/// priorités sur l'encoche. Priorités : dictée > réunion > filet de sécurité > proposition de mise à jour > lecture (voir `PrioriteLecture`).
///
/// Pendant une dictée : si quelque chose joue, pause au début (commande `pause`) et reprise à la fin, seulement si c'est Verbe qui a mis en
/// pause (`PauseDictee`). Pendant une réunion : la lecture ne s'affiche pas et n'est jamais mise en pause automatiquement.
@MainActor
final class LectureControleur {
    let modele = LectureModele()
    let miniature: LectureMiniature
    let systeme = LecteurSysteme()

    /// Ce qui occupe l'encoche en dehors de la dictée de ce contrôleur (rempli par l'AppDelegate).
    var occupation: () -> OccupationEncoche = { OccupationEncoche() }

    private var pause = PauseDictee()
    private(set) var dicteeConfirmee = false
    /// L'îlot (centre d'activités) montre ou retire la lecture (rempli par `IlotControleur`).
    var surIlot: (Bool) -> Void = { _ in }
    /// Les priorités viennent d'être recalculées (la dictée est confirmée ou finie) : l'îlot relit ses masques.
    var surRecalcul: () -> Void = {}
    /// Un nouveau morceau (ou une nouvelle image) : l'îlot se redessine.
    var surNouveauMorceau: () -> Void = {}
    private var confirmation: DispatchWorkItem?
    private var recalcul: DispatchWorkItem?
    private(set) var affichage: AffichageLecture = .aucun
    /// Mode d'essai : fenêtres invisibles.
    var essaiInvisible = false { didSet { miniature.invisible = essaiInvisible } }
    private var cheminImage: String?
    private var appCharge: String?
    private var derniereRechercheDeSite = Date.distantPast
    private var derniereRechercheDeMiniature = Date.distantPast
    /// L'image affichée est une miniature retrouvée par nous (et non celle du système) : on l'efface au morceau suivant.
    private var imageDeSecours = false
    private var reglagesObserves: NSObjectProtocol?

    /// La dictée n'occupe l'encoche (et ne met la lecture en pause) qu'après 0,28 s : un appui court (moins de 0,25 s, le premier du double
    /// appui des mains libres) ne touche ni la lecture ni l'îlot. Pendant ce court délai, la bande de dictée recouvre déjà l'îlot.
    static let delaiConfirmation: TimeInterval = 0.28

    init() {
        miniature = LectureMiniature(modele: modele)
        modele.surReprise = { [weak self] in self?.reprendreParClic() }
        modele.surBascule = { [weak self] in self?.basculer() }
        modele.surSuivant = { [weak self] in self?.systeme.envoyer(.suivant) }
        modele.surPrecedent = { [weak self] in self?.systeme.envoyer(.precedent) }
        modele.surSaut = { [weak self] delta in self?.sauter(delta) }
        modele.surPosition = { [weak self] s in self?.aller(a: s) }
        systeme.surEvenement = { [weak self] e in self?.recevoir(e) }
        systeme.surAbandon = { [weak self] _ in self?.vider() }
    }

    // MARK: vie

    func demarrer() {
        reglagesObserves = NotificationCenter.default.addObserver(forName: .verbeLectureReglages, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.appliquerLesReglages() }
        }
        appliquerLesReglages()
    }

    /// Fermeture de l'app : le programme d'aide s'arrête, plus rien ne reste à l'écran.
    func arreter() {
        systeme.arreter()
        miniature.fermer()
    }

    /// L'îlot vient de se déplier : le site du navigateur et la miniature de la vidéo sont relus.
    func ilotDeplie() { chercherLeSite(); chercherLaMiniature() }

    /// Le programme d'aide n'est lancé que si « Afficher la lecture en cours » est actif.
    private func appliquerLesReglages() {
        if Settings.afficherLaLecture {
            if !systeme.actif { systeme.demarrer() }
        } else {
            systeme.arreter()
            vider()
        }
    }

    private func vider() {
        modele.morceau = nil
        modele.image = nil
        imageDeSecours = false
        cheminImage = nil
        pause = PauseDictee()
        recalculer()
    }

    // MARK: ce que dit le système

    private func recevoir(_ evenement: EvenementLecture) {
        switch evenement {
        case .pret, .echec: return
        case .rien:
            if modele.morceau != nil { vider() }
        case .etat(let m):
            confirmationCommande?.cancel(); confirmationCommande = nil
            let nouveau = m.cle != modele.morceau?.cle
            if nouveau, imageDeSecours { imageDeSecours = false; modele.image = nil }
            if m.cheminImage != cheminImage { chargerImage(m.cheminImage) }
            if m.app != appCharge { chargerApp(m) }
            if nouveau {
                modele.site = nil
                modele.pop += 1
                chercherLeSite(pour: m)
            }
            // l'image du système d'abord ; à défaut, la miniature de la vidéo ; à défaut, l'icône de l'app (dessinée par la vue)
            if nouveau { chercherLaMiniature(pour: m) }
            if m != modele.morceau { modele.morceau = m }
            if nouveau { surNouveauMorceau() }
            recalculer()
        }
    }

    private func chargerImage(_ chemin: String?) {
        cheminImage = chemin
        if let chemin, let image = NSImage(contentsOfFile: chemin) {
            modele.image = image
            imageDeSecours = false
        } else if !imageDeSecours {
            modele.image = nil
        }
        appliquerTeinte()
    }

    /// La teinte (égaliseur, lueur, trace sonore) suit l'image retenue : celle du système, la miniature, sinon l'icône de l'app.
    private func appliquerTeinte() {
        modele.imageMini = (modele.image ?? modele.iconeApp).flatMap { Self.reduire($0, pixels: 40) }
        modele.teinte = (modele.image ?? modele.iconeApp).map { Self.teinte(de: $0) } ?? .neutre
    }

    // MARK: miniature (repli quand le navigateur n'envoie aucune image)

    private func chercherLaMiniature() {
        guard let m = modele.morceau, modele.image == nil, m.cheminImage == nil, Date().timeIntervalSince(derniereRechercheDeMiniature) > 4 else { return }
        chercherLaMiniature(pour: m)
    }

    /// Chrome sur YouTube n'envoie souvent aucune image au système : on retrouve l'identifiant de la vidéo dans l'adresse de l'onglet qui
    /// joue (Accessibilité, aucune autorisation de plus), puis on prend la miniature publique (cache disque par identifiant).
    private func chercherLaMiniature(pour m: MorceauEnCours) {
        guard m.cheminImage == nil, modele.image == nil, SourceLecture.estNavigateur(m.app), Permissions.accessibiliteOK, let pid = m.pid else { return }
        derniereRechercheDeMiniature = Date()
        let cle = m.cle, titre = m.titre
        Task.detached(priority: .utility) { [self] in
            guard let id = MiniatureLecture.identifiantDeLOnglet(pid: pid, titreMedia: titre),
                  let (image, origine) = await MiniatureLecture.charger(identifiant: id) else { return }
            await MainActor.run {
                // le morceau a pu changer, ou le système envoyer enfin sa propre image, pendant ce temps
                guard modele.morceau?.cle == cle, modele.image == nil, cheminImage == nil else { return }
                modele.image = image
                imageDeSecours = true
                appliquerTeinte()
                Log.ecrire("lecture : miniature de la vidéo (\(origine.rawValue))")
            }
        }
    }

    /// Nom et icône de l'app qui joue.
    private func chargerApp(_ m: MorceauEnCours) {
        appCharge = m.app
        var app: NSRunningApplication?
        if let pid = m.pid { app = NSRunningApplication(processIdentifier: pid_t(pid)) }
        if app == nil, let id = m.app { app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first }
        modele.nomApp = app?.localizedName
        var icone = app?.icon
        if icone == nil, let id = m.app, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) { icone = NSWorkspace.shared.icon(forFile: url.path) }
        // l'icône est redessinée une fois à 256 pixels (la représentation par défaut est minuscule : floue en grand, ou en repli de la pochette)
        modele.iconeApp = icone.map { Self.reduire($0, pixels: 256, rogner: false) ?? $0 }
        appliquerTeinte()
    }

    /// L'image réduite au carré (rognage centré) avec une interpolation haute : nette à 18 pt sur un écran Retina.
    static func reduire(_ image: NSImage, pixels: Int, rogner: Bool = true) -> NSImage? {
        var proposition = NSRect(x: 0, y: 0, width: pixels, height: pixels)
        guard let cg = image.cgImage(forProposedRect: &proposition, context: nil, hints: nil),
              let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        let l = CGFloat(cg.width), h = CGFloat(cg.height), cote = rogner ? min(l, h) : max(l, h), k = CGFloat(pixels) / cote
        ctx.draw(cg, in: CGRect(x: (CGFloat(pixels) - l * k) / 2, y: (CGFloat(pixels) - h * k) / 2, width: l * k, height: h * k))
        guard let sortie = ctx.makeImage() else { return nil }
        return NSImage(cgImage: sortie, size: NSSize(width: pixels, height: pixels))
    }

    /// La couleur vive de la pochette : lue sur une copie de 24 × 24 pixels.
    static func teinte(de image: NSImage) -> TeintePochette {
        let n = 24
        var pixels = [UInt8](repeating: 0, count: n * n * 4)
        let ok = pixels.withUnsafeMutableBytes { tampon -> Bool in
            guard let ctx = CGContext(data: tampon.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                  let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))
            return true
        }
        return ok ? CouleurDominante.teinte(rgba: pixels, largeur: n, hauteur: n) : .neutre
    }

    // MARK: site (« Chrome · YouTube »)

    /// Dans un navigateur, le site se lit dans le titre des fenêtres (Accessibilité, déjà accordée pour coller) : jamais deviné.
    private func chercherLeSite() {
        guard let m = modele.morceau, Date().timeIntervalSince(derniereRechercheDeSite) > 4 else { return }
        chercherLeSite(pour: m)
    }

    private func chercherLeSite(pour m: MorceauEnCours) {
        guard SourceLecture.estNavigateur(m.app), Permissions.accessibiliteOK, let pid = m.pid else { return }
        derniereRechercheDeSite = Date()
        let cle = m.cle, titre = m.titre
        Task.detached(priority: .utility) { [self] in
            let titres = Self.titresDesFenetres(pid: pid)
            let site = SourceLecture.site(titresDeFenetres: titres, titreMedia: titre)
            await MainActor.run {
                guard modele.morceau?.cle == cle, let site, modele.site != site else { return }
                modele.site = site
            }
        }
    }

    nonisolated private static func titresDesFenetres(pid: Int) -> [String] {
        let app = AXUIElementCreateApplication(pid_t(pid))
        AXUIElementSetMessagingTimeout(app, 0.3)
        var valeur: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &valeur) == .success, let fenetres = valeur as? [AXUIElement] else { return [] }
        return fenetres.prefix(12).compactMap { f in
            AXUIElementSetMessagingTimeout(f, 0.3)
            var t: CFTypeRef?
            return AXUIElementCopyAttributeValue(f, kAXTitleAttribute as CFString, &t) == .success ? t as? String : nil
        }
    }

    // MARK: commandes de l'îlot

    /// Mise à jour immédiate de ce qu'on voit (la barre et le bouton répondent au doigt) ; l'état réel du système la remplace dans la foulée.
    /// Si le système ne dit rien (MediaRemote ne prévient que d'un changement : la commande n'a rien changé, par exemple la vidéo restée en
    /// pause après la reprise de fin de dictée), l'état deviné revient à l'état d'avant au bout de `delaiConfirmation` : jamais des barres
    /// qui bougent sur une vidéo en pause (Hugues 12/11, 23 h 47).
    private func appliquerLocalement(joue: Bool? = nil, position: Double? = nil) {
        guard var m = modele.morceau else { return }
        if let joue, joue != m.joue { attendreConfirmation(avant: m.joue, cle: m.cle) }
        let maintenant = Date()
        if let p = m.positionA(maintenant) { m.position = p; m.depuis = maintenant }
        if let joue { m.joue = joue; if joue, m.vitesse <= 0 { m.vitesse = 1 } }
        if let position { m.position = position; m.depuis = maintenant }
        modele.morceau = m
    }

    /// Combien de temps on attend que le système confirme un changement de lecture (pause, reprise) avant de revenir à son dernier état.
    static let delaiConfirmationCommande: TimeInterval = 2
    private var confirmationCommande: DispatchWorkItem?
    private func attendreConfirmation(avant: Bool, cle: String) {
        confirmationCommande?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, var m = self.modele.morceau, m.cle == cle, m.joue != avant else { return }
                Log.ecrire("lecture : le système n'a rien confirmé en \(Int(Self.delaiConfirmationCommande)) s, l'état revient à « \(avant ? "joue" : "en pause") »")
                m.joue = avant
                self.modele.morceau = m
                self.recalculer()
            }
        }
        confirmationCommande = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.delaiConfirmationCommande, execute: item)
    }

    private func basculer() {
        guard let m = modele.morceau else { return }
        systeme.envoyer(.bascule)
        appliquerLocalement(joue: !m.joue)
    }

    private func sauter(_ delta: Double) {
        guard let m = modele.morceau, let p = m.positionA(Date()) else { return }
        aller(a: TempsLecture.saut(position: p, delta: delta, duree: m.duree))
    }

    private func aller(a position: Double) {
        guard modele.morceau != nil else { return }
        systeme.envoyer(.position(position))
        appliquerLocalement(position: position)
    }

    // MARK: priorités

    /// À appeler quand quelque chose de l'encoche change (dictée, réunion, filet, mise à jour, panneau…) : regroupe les appels du même tour.
    func occupationChangee() {
        recalcul?.cancel()
        let item = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.recalculer() } }
        recalcul = item
        DispatchQueue.main.async(execute: item)
    }

    private func recalculer() {
        var o = occupation()
        o.dictee = o.dictee || dicteeConfirmee
        var voulu = PrioriteLecture.affichage(occupation: o, morceau: modele.morceau != nil, reglageAffichage: Settings.afficherLaLecture)
        // Pendant la dictée, la mini-miniature n'existe que si c'est Verbe qui a mis la lecture en pause (c'est le geste pour la reprendre),
        // qu'elle est bien en pause, et que le ruban de texte de la dictée est sorti (c'est dedans qu'elle se loge).
        if voulu == .miniature, !(pause.pauseParNous && !modele.joue && rubanDictee()) { voulu = .aucun }
        // la pilule de verre (hors de l'encoche) garde la vidéo mise en pause par la dictée, avec le signe pause : elle ne part pas
        bulleDictee(PrioriteLecture.bulleDansLaPilule(dictee: o.dictee, pauseParNous: pause.pauseParNous, joue: modele.joue, morceau: modele.morceau != nil) ? modele : nil)
        defer { surRecalcul() }
        guard voulu != affichage else { return }
        let avant = affichage
        affichage = voulu
        switch voulu {
        case .aucun:
            surIlot(false); miniature.retirer(); reserveRuban(0)
        case .ilot:
            miniature.retirer(); reserveRuban(0); surIlot(true)
        case .miniature:
            surIlot(false); reserveRuban(LectureMiniature.reserve); miniature.afficher()
        }
        if avant != voulu { Log.ecrire("lecture : affichage \(avant) → \(voulu)") }
    }

    /// Rempli par l'AppDelegate : le ruban de texte de la dictée est-il sorti ? et réserve à droite du texte du ruban (la mini-miniature s'y loge).
    var rubanDictee: () -> Bool = { false }
    var reserveRuban: (CGFloat) -> Void = { _ in }
    /// Rempli par l'AppDelegate : la lecture à montrer dans la pilule de verre de la dictée (nil : aucune).
    var bulleDictee: (LectureModele?) -> Void = { _ in }

    /// Clic sur la mini-miniature : la lecture reprend tout de suite (la dictée continue). `PauseDictee` voit alors une lecture relancée par
    /// Hugues : elle ne fera rien de plus à la fin de la dictée.
    private func reprendreParClic() {
        guard modele.morceau != nil, !modele.joue else { return }
        systeme.envoyer(.lecture)
        appliquerLocalement(joue: true)
        Log.ecrire("lecture : reprise par un clic sur la miniature pendant la dictée")
        recalculer()
    }

    // MARK: dictée

    /// La dictée commence (`true`) ou finit (`false`, relâchement ou annulation).
    func dicteeChange(enCours: Bool) {
        if enCours {
            confirmation?.cancel()
            let item = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.confirmerLaDictee() } }
            confirmation = item
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.delaiConfirmation, execute: item)
        } else {
            confirmation?.cancel()
            let etaitConfirmee = dicteeConfirmee
            dicteeConfirmee = false
            switch pause.fin(morceau: modele.morceau) {
            case .reprendre:
                systeme.envoyer(.lecture)
                appliquerLocalement(joue: true)
                modele.impulsion += 1
                Log.ecrire("lecture : reprise après la dictée")
            case .rien, .pause: break
            }
            if etaitConfirmee { recalculer() } else { bulleDictee(nil) }
        }
    }

    private func confirmerLaDictee() {
        dicteeConfirmee = true
        let reglage = Settings.pauseLecturePendantDictee && Settings.afficherLaLecture && systeme.actif
        switch pause.debut(morceau: modele.morceau, reglage: reglage, reunion: occupation().reunion) {
        case .pause:
            systeme.envoyer(.pause)
            appliquerLocalement(joue: false)
            Log.ecrire("lecture : mise en pause pour la dictée (\(modele.morceau?.app ?? "?"))")
        case .rien, .reprendre: break
        }
        recalculer()
    }
}
