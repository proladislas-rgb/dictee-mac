import AppKit
import ApplicationServices
import DicteeCore

extension Notification.Name {
    /// Un réglage de la lecture en cours a changé (Réglages) : le contrôleur relit `Settings`.
    static let verbeLectureReglages = Notification.Name("verbe.lecture.reglages")
}

/// La lecture en cours dans l'encoche : relie le programme d'aide (ce qui joue), l'îlot et la bulle (ce qu'on voit), les réglages et les
/// priorités sur l'encoche. Priorités : dictée > réunion > filet de sécurité > proposition de mise à jour > lecture (voir `PrioriteLecture`).
///
/// Pendant une dictée : si quelque chose joue, pause au début (commande `pause`) et reprise à la fin, seulement si c'est Verbe qui a mis en
/// pause (`PauseDictee`). Pendant une réunion : la lecture ne s'affiche pas et n'est jamais mise en pause automatiquement.
@MainActor
final class LectureControleur {
    let modele = LectureModele()
    let panneau: LecturePanneau
    let bulle: LectureBulle
    let systeme = LecteurSysteme()

    /// Ce qui occupe l'encoche en dehors de la dictée de ce contrôleur (rempli par l'AppDelegate).
    var occupation: () -> OccupationEncoche = { OccupationEncoche() }

    private var pause = PauseDictee()
    private var dicteeConfirmee = false
    private var confirmation: DispatchWorkItem?
    private var recalcul: DispatchWorkItem?
    private(set) var affichage: AffichageLecture = .aucun
    /// Mode d'essai : fenêtres invisibles.
    var essaiInvisible = false { didSet { panneau.invisible = essaiInvisible; bulle.invisible = essaiInvisible } }
    private var cheminImage: String?
    private var appCharge: String?
    private var derniereRechercheDeSite = Date.distantPast
    private var reglagesObserves: NSObjectProtocol?

    /// La dictée n'occupe l'encoche (et ne met la lecture en pause) qu'après 0,28 s : un appui court (moins de 0,25 s, le premier du double
    /// appui des mains libres) ne touche ni la lecture ni l'îlot. Pendant ce court délai, la bande de dictée recouvre déjà l'îlot.
    static let delaiConfirmation: TimeInterval = 0.28

    init() {
        panneau = LecturePanneau(modele: modele)
        bulle = LectureBulle(modele: modele)
        modele.surBascule = { [weak self] in self?.basculer() }
        modele.surSuivant = { [weak self] in self?.systeme.envoyer(.suivant) }
        modele.surPrecedent = { [weak self] in self?.systeme.envoyer(.precedent) }
        modele.surSaut = { [weak self] delta in self?.sauter(delta) }
        modele.surPosition = { [weak self] s in self?.aller(a: s) }
        modele.surFinGlissement = { [weak self] in self?.panneau.apresGlissement() }
        panneau.surDepliage = { [weak self] in self?.chercherLeSite() }
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
        panneau.fermer()
        bulle.fermer()
    }

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
            let nouveau = m.cle != modele.morceau?.cle
            if m.cheminImage != cheminImage { chargerImage(m.cheminImage) }
            if m.app != appCharge { chargerApp(m) }
            if nouveau {
                modele.site = nil
                modele.pop += 1
                chercherLeSite(pour: m)
            }
            if m != modele.morceau { modele.morceau = m }
            recalculer()
        }
    }

    private func chargerImage(_ chemin: String?) {
        cheminImage = chemin
        guard let chemin, let image = NSImage(contentsOfFile: chemin) else {
            modele.image = nil
            modele.teinte = .neutre
            return
        }
        modele.image = image
        modele.teinte = Self.teinte(de: image)
    }

    /// Nom et icône de l'app qui joue.
    private func chargerApp(_ m: MorceauEnCours) {
        appCharge = m.app
        var app: NSRunningApplication?
        if let pid = m.pid { app = NSRunningApplication(processIdentifier: pid_t(pid)) }
        if app == nil, let id = m.app { app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first }
        modele.nomApp = app?.localizedName
        if let icone = app?.icon { modele.iconeApp = icone }
        else if let id = m.app, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) { modele.iconeApp = NSWorkspace.shared.icon(forFile: url.path) }
        else { modele.iconeApp = nil }
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
    private func appliquerLocalement(joue: Bool? = nil, position: Double? = nil) {
        guard var m = modele.morceau else { return }
        let maintenant = Date()
        if let p = m.positionA(maintenant) { m.position = p; m.depuis = maintenant }
        if let joue { m.joue = joue; if joue, m.vitesse <= 0 { m.vitesse = 1 } }
        if let position { m.position = position; m.depuis = maintenant }
        modele.morceau = m
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
        let voulu = PrioriteLecture.affichage(occupation: o, morceau: modele.morceau != nil, reglageAffichage: Settings.afficherLaLecture)
        guard voulu != affichage else { return }
        let avant = affichage
        affichage = voulu
        switch voulu {
        case .aucun:
            panneau.retirer(); bulle.retirer()
        case .ilot:
            bulle.retirer(); panneau.afficher()
        case .bulle:
            panneau.retirer(); bulle.afficher(mainsLibres: dicteeMainsLibres())
        }
        if avant != voulu { Log.ecrire("lecture : affichage \(avant) → \(voulu)") }
    }

    /// Rempli par l'AppDelegate : la dictée en cours est-elle en mains libres (la bulle suit le bord de l'encoche) ?
    var dicteeMainsLibres: () -> Bool = { false }

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
            if etaitConfirmee { recalculer() }
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
