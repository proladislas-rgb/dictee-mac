import AppKit
import UniformTypeIdentifiers
import SwiftUI
import DicteeCore

// « L'étagère » (maquette design/maquettes/ilot-apple.html, cinq idées de plus, 2) : on glisse des fichiers sur l'encoche, ils y restent ;
// on les reprend plus tard en les glissant hors de l'îlot. Verbe garde un SIGNET de chaque fichier (le Mac le retrouve même déplacé ou
// renommé), jamais une copie : un fichier supprimé quitte l'étagère. La logique pure est dans DicteeCore/EtagereIlot.swift ; le glisser
// lui-même (moniteur, fenêtre qui accepte les fichiers) dans IlotPanneau.swift.
// L'étagère plus rapide (maquette design/maquettes/ilot-etagere-rapide.html, validée) :
// 1. l'îlot appelle (« Glisse ici ») dès qu'un glisser de fichiers commence, n'importe où ; il s'ouvre en grand en approchant ;
// 2. deux zones : « Étagère » (la garder) et « AirDrop » (l'envoyer : le panneau AirDrop de macOS choisit l'appareil — aucune interface
//    publique ne permet de viser un appareil précis, comme « iPhone de Hugues », sans lui) ;
// 3. replié, la pile et le nombre de fichiers dans l'aile gauche ; le Centre montre les fichiers tout en haut ;
// 4. « Tout » glisse tous les fichiers d'un coup ; un fichier glissé vers une app quitte l'étagère (« Remettre » quelques secondes) ;
// 5. en option, les nouvelles captures d'écran arrivent sur l'étagère, marquées « Nouveau ».

/// L'étagère, gardée localement : ~/Library/Application Support/Dictee/etagere.json (0600, jamais dans git, jamais envoyée nulle part).
struct EtagereStore {
    var url: URL
    static var urlParDefaut: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Dictee", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("etagere.json")
    }
    func lire() -> EtagereIlot {
        guard let d = try? Data(contentsOf: url) else { return EtagereIlot() }
        if let e = EtagereIlot.depuis(d) { return e }
        Log.ecrire("étagère : fichier illisible, l'ancien est gardé en .abime")
        try? FileManager.default.moveItem(at: url, to: url.appendingPathExtension("abime"))
        return EtagereIlot()
    }
    func ecrire(_ e: EtagereIlot) {
        guard let d = e.donnees() else { return }
        try? d.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

/// Les signets des fichiers de l'étagère (pas de bac à sable : des signets ordinaires suffisent).
enum SignetsEtagere {
    /// Le chemin réel d'un fichier (liens symboliques résolus, « /private/var » compris) : un même fichier a toujours le même chemin, la
    /// règle « sans doublon » s'appuie dessus.
    static func cheminReel(_ u: URL) -> String {
        guard let r = realpath(u.path, nil) else { return (u.path as NSString).standardizingPath }
        defer { free(r) }
        return String(cString: r)
    }
    static func element(_ url: URL, a date: Date) -> ElementEtagere? {
        guard url.isFileURL, FileManager.default.fileExists(atPath: url.path),
              let d = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) else { return nil }
        return ElementEtagere(chemin: cheminReel(url), signet: d, ajout: date)
    }
    /// Où est le fichier maintenant ? Un disque externe débranché n'efface rien : le fichier reviendra avec lui (et on n'y touche pas :
    /// aucun signet résolu, aucune lecture sur un volume absent). Appelée hors du fil principal (un partage réseau injoignable peut
    /// bloquer plusieurs secondes).
    nonisolated static func relire(_ e: ElementEtagere) -> SignetRelu {
        if volumeAbsent(e.chemin) != nil { return .present(chemin: e.chemin, signet: nil) }
        var perime = false
        if let u = try? URL(resolvingBookmarkData: e.signet, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &perime),
           FileManager.default.fileExists(atPath: u.path) {
            let neuf = perime ? try? u.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) : nil
            return .present(chemin: cheminReel(u), signet: neuf)
        }
        if volumeAbsent(e.chemin) != nil { return .present(chemin: e.chemin, signet: nil) }
        return .disparu
    }
    /// L'icône du Finder, lue par les propriétés du fichier (sans AppKit : se lit hors du fil principal) ; nil sur un volume absent.
    nonisolated static func icone(_ chemin: String) -> NSImage? {
        guard volumeAbsent(chemin) == nil else { return nil }
        return (try? URL(fileURLWithPath: chemin).resourceValues(forKeys: [.effectiveIconKey]))?.effectiveIcon as? NSImage
    }
    /// L'icône du type de fichier, d'après son extension seule (aucun accès au fichier) : en attendant la vraie.
    static func iconeDuType(_ chemin: String) -> NSImage {
        let ext = (chemin as NSString).pathExtension
        return NSWorkspace.shared.icon(for: ext.isEmpty ? .data : (UTType(filenameExtension: ext) ?? .data))
    }
    /// « /Volumes/Disque/… » dont le disque n'est pas branché.
    nonisolated static func volumeAbsent(_ chemin: String) -> String? {
        let c = (chemin as NSString).pathComponents
        guard c.count > 2, c[1] == "Volumes" else { return nil }
        let racine = "/Volumes/" + c[2]
        return FileManager.default.fileExists(atPath: racine) ? nil : racine
    }
}

extension IlotControleur {
    /// Le réglage « Étagère » : la fenêtre écoute les glissers, l'accueil montre la ligne de l'étagère. Au lancement, aucun fichier
    /// n'est lu (ni signet résolu, ni icône lue sur le disque : pas de demande d'autorisation sans geste) ; les signets sont relus à
    /// l'ouverture de l'accueil ou de la carte.
    func activerEtagere(_ oui: Bool) {
        panneau.etagereActive = oui
        moteur.etagereActive = oui
        if oui { montrerEtagere() } else { moteur.montrerDepot(false) }
    }

    /// Des fichiers ont été lâchés sur l'îlot : un signet pour chacun, sans doublon. Rend le nombre de fichiers rangés. `nouveau` : ils
    /// arrivent tout seuls (des captures d'écran) ; étagère pleine, ils ne font de la place que parmi les autres arrivés tout seuls,
    /// jamais parmi les fichiers rangés à la main.
    @discardableResult
    func ranger(_ urls: [URL], nouveau: Bool = false) -> Int {
        let t = maintenant()
        let r = etagere.ajouter(urls.compactMap { SignetsEtagere.element($0, a: t) }, seuls: nouveau)
        for e in r.sortis { iconesEtagere[e.id] = nil; nouveautes.remove(e.id) }
        if nouveau { nouveautes.formUnion(r.ajoutes.map(\.id)) }
        // les fichiers viennent d'être lâchés (donc accessibles) : leur icône est lue tout de suite
        for e in r.ajoutes { iconesEtagere[e.id] = NSWorkspace.shared.icon(forFile: e.chemin) }
        sauverEtagere()
        montrerEtagere()
        // jamais de nom de fichier au journal
        Log.ecrire("étagère : \(r.ajoutes.count) rangé(s), \(r.doublons) déjà là, \(r.sortis.count) sorti(s) pour faire de la place"
                   + (r.ecartes > 0 ? ", \(r.ecartes) capture(s) non rangée(s) (étagère pleine de fichiers rangés à la main)" : ""))
        return r.ajoutes.count
    }

    /// Relit les signets (à l'ouverture de l'accueil ou de la carte) : un fichier déplacé suit, un fichier supprimé ou mis à la
    /// Corbeille s'en va. La résolution se fait sur une file à part (un partage réseau injoignable ou une clé lente ne gèlent ni l'îlot ni
    /// la dictée), puis le résultat est appliqué ici. Une seule relecture à la fois ; à l'ouverture de l'accueil (au simple survol de
    /// l'encoche), pas plus d'une toutes les 5 s. `puis` : appelé quand l'étagère est à jour.
    func relireEtagere(force: Bool = true, puis: (() -> Void)? = nil) {
        if let puis { apresRelecture.append(puis) }
        if relectureEtagere.enCours { relectureEtagere.encore = relectureEtagere.encore || force; return }
        let t = Date()
        guard force || t.timeIntervalSince(relectureEtagere.derniere) >= 5 else { finRelecture(); return }
        relectureEtagere = (true, false, t)
        // le dossier des captures a pu changer (Capture d'écran, « Options ») : relu en même temps, la surveillance suit. Seulement sur
        // un geste (la carte ouverte, un fichier ouvert) : un nouveau dossier protégé peut faire poser sa question à macOS, jamais au
        // simple survol
        if force, moteur.capturesActives { activerCaptures(true) }
        let elements = etagere.elements
        let sansIcone = Set(elements.map(\.id)).subtracting(iconesEtagere.keys)
        DispatchQueue.global(qos: .userInitiated).async {
            var relus: [UUID: SignetRelu] = [:], icones: [UUID: NSImage] = [:]
            for e in elements {
                let r = SignetsEtagere.relire(e)
                relus[e.id] = r
                if sansIcone.contains(e.id), case .present(let chemin, _) = r, let i = SignetsEtagere.icone(chemin) { icones[e.id] = i }
            }
            let resultat = (relus, icones)
            DispatchQueue.main.async { MainActor.assumeIsolated { self.appliquerRelecture(resultat.0, icones: resultat.1) } }
        }
    }
    private func finRelecture() { let l = apresRelecture; apresRelecture = []; l.forEach { $0() } }

    private func appliquerRelecture(_ relus: [UUID: SignetRelu], icones: [UUID: NSImage]) {
        let avant = etagere
        // un fichier rangé pendant la relecture n'a pas été relu : il reste tel quel
        let retires = etagere.relire { relus[$0.id] ?? .present(chemin: $0.chemin, signet: nil) }
        for (id, i) in icones { iconesEtagere[id] = i }
        for e in retires { iconesEtagere[e.id] = nil }
        if etagere != avant {
            sauverEtagere()
            if !retires.isEmpty { Log.ecrire("étagère : \(retires.count) fichier(s) disparu(s), retiré(s)") }
        }
        montrerEtagere()
        let encore = relectureEtagere.encore
        relectureEtagere.enCours = false
        if encore { relireEtagere(force: true) } else { finRelecture() }
    }

    func sauverEtagere() { etagereStore.ecrire(etagere) }

    /// Ce que l'îlot montre : le nom, le chemin, l'icône du Finder (lue une fois par fichier, hors du fil principal ; en attendant,
    /// celle du type de fichier, qui ne touche pas au disque).
    func montrerEtagere() {
        moteur.etagere = etagere.elements.map { e in
            FichierEtagere(id: e.id, nom: e.nom, url: URL(fileURLWithPath: e.chemin), icone: iconesEtagere[e.id] ?? SignetsEtagere.iconeDuType(e.chemin),
                           nouveau: nouveautes.contains(e.id))
        }
        moteur.donneesChangees()
    }

    func agirEtagere(_ action: ActionIlot) {
        switch action {
        case .etagereOuvrir(let id):
            // le chemin d'aujourd'hui (le fichier a pu être déplacé), relu hors du fil principal, puis on ouvre
            moteur.fermer()
            relireEtagere { [weak self] in
                guard let self, let e = self.etagere.elements.first(where: { $0.id == id }) else { return }
                self.ouvrir(URL(fileURLWithPath: e.chemin))
            }
        case .etagereRetirer(let id):
            if etagere.retirer(id) { iconesEtagere[id] = nil; sauverEtagere(); montrerEtagere() }
        case .etagereVider:
            etagere.vider(); iconesEtagere = [:]; nouveautes = []; sauverEtagere(); montrerEtagere()
        case .etagereSortis(let ids, let point):
            sortis(ids, en: point)
        case .etagereRemettre:
            let r = etagere.remettre(partisEnAttente)
            partisEnAttente = []
            for e in r.sortis { iconesEtagere[e.id] = nil; nouveautes.remove(e.id) }
            sauverEtagere(); montrerEtagere()
            Log.ecrire("étagère : \(r.ajoutes.count) fichier(s) remis")
            moteur.quitterBandeau()
        case .etagereCaptures:
            // le premier clic allume : macOS demande l'accès au dossier des captures à ce moment-là, jamais avant
            let oui = !moteur.capturesActives
            reglagesCentre.reglerCaptures(oui)
            moteur.capturesRefusees = false
            moteur.capturesAttente = oui
            activerCaptures(oui)
            moteur.donneesChangees()
        case .etagereCapturesReglages:
            moteur.capturesRefusees = false
            ouvrir(Self.reglagesFichiers)
        default: break
        }
    }

    // MARK: l'étagère plus rapide

    /// Des fichiers de l'étagère ont été glissés hors d'elle et une app les a acceptés (lâchés en `point`, coordonnées de l'écran) : ils
    /// quittent l'étagère ; l'îlot se range et dit « 3 fichiers partis dans Mail · Remettre » quelques secondes (un seul réveil, celui du
    /// bandeau ; l'anneau se vide pendant ce temps). Les fichiers eux-mêmes n'ont pas bougé : l'app en a fait une copie ou une pièce jointe.
    func sortis(_ ids: [UUID], en point: NSPoint) {
        let app = appSous(point)
        // lâchés sur le panneau AirDrop : l'envoi part, les fichiers restent sur l'étagère (rien ne dit qu'ils sont arrivés)
        if app == EnvoiAirDropEtat.nom {
            let l = etagere.elements.filter { ids.contains($0.id) }
            guard !l.isEmpty else { return }
            Log.ecrire("étagère : \(l.count) fichier(s) glissé(s) vers AirDrop, gardé(s) sur l'étagère")
            moteur.fermer()
            let b = BandeauIlot(vue: .etagereEnvoi, jusqua: maintenant().addingTimeInterval(EnvoiAirDropEtat.lance.duree), ligne1: "", ligne2: "",
                                envoi: EnvoiEtagere(etat: .lance, noms: l.map(\.nom), icone: iconesEtagere[l[0].id], surEtagere: true))
            moteur.annoncer(bandeau: b)
            return
        }
        let partis = etagere.retirer(ids: ids)
        guard !partis.isEmpty else { return }
        for e in partis { nouveautes.remove(e.id) }
        partisEnAttente = partis
        sauverEtagere(); montrerEtagere()
        // jamais de nom de fichier au journal (le nom de l'app n'est pas une donnée de l'utilisateur)
        Log.ecrire("étagère : \(partis.count) fichier(s) glissé(s) vers \(app ?? "une app"), retiré(s) (Remettre possible)")
        let icones = partis.suffix(2).reversed().map { iconesEtagere[$0.id] ?? SignetsEtagere.iconeDuType($0.chemin) }
        let duree = Self.dureeRemettre
        moteur.fermer()
        moteur.annoncer(bandeau: BandeauIlot(vue: .etagerePartis, jusqua: maintenant().addingTimeInterval(duree), ligne1: EtagereIlot.partis(partis.count, app: app),
                                             ligne2: partis.count == 1 ? "Il a quitté l\u{2019}étagère" : "Ils ont quitté l\u{2019}étagère",
                                             partis: PartisEtagere(nombre: partis.count, app: app, icones: icones, duree: duree)))
    }
    /// Combien de temps « Remettre » reste proposé.
    static let dureeRemettre: TimeInterval = 5

    /// La carte Étagère a été vue, puis quittée : les captures arrivées ne sont plus « Nouveau ».
    func etagereVue() {
        guard !nouveautes.isEmpty else { return }
        nouveautes = []
        montrerEtagere()
    }

    /// Des fichiers lâchés sur « AirDrop » : le panneau AirDrop de macOS s'ouvre et choisit l'appareil (Verbe ne peut pas viser un
    /// appareil lui-même : aucune interface publique pour ça). L'îlot dit « Envoi… », puis ce que le service répond, sans jamais mentir
    /// (`EnvoiAirDropEtat`) : « Envoi lancé vers AirDrop » quand l'appareil est choisi (rien ne confirme la fin du transfert), « Annulé »
    /// si le panneau (ou l'envoi, même après le choix) est annulé, « AirDrop indisponible » s'il ne peut pas envoyer (Wi-Fi ou Bluetooth
    /// éteint). L'étagère n'est jamais touchée : rien n'y est rangé, et un fichier qui y est déjà y reste.
    func envoyerAirDrop(_ urls: [URL]) {
        let noms = urls.map(\.lastPathComponent)
        let icone = urls.first.map { NSWorkspace.shared.icon(forFile: $0.path) }
        let chemins = Set(etagere.elements.map(\.chemin))
        let surEtagere = !urls.isEmpty && urls.allSatisfy { chemins.contains(SignetsEtagere.cheminReel($0)) }
        var dernier = EnvoiEtagere.Etat.enCours
        func montrer(_ e: EnvoiEtagere.Etat) {
            let b = BandeauIlot(vue: .etagereEnvoi, jusqua: maintenant().addingTimeInterval(e.duree), ligne1: "", ligne2: "",
                                envoi: EnvoiEtagere(etat: e, noms: noms, icone: icone, surEtagere: surEtagere))
            if moteur.bandeau?.vue == .etagereEnvoi { moteur.bandeau = b; moteur.donneesChangees() } else { moteur.annoncer(bandeau: b) }
        }
        Log.ecrire("étagère : \(urls.count) fichier(s) vers AirDrop")
        // le temps de choisir l'appareil dans le panneau de macOS ; la réponse du service remplace ce bandeau
        montrer(.enCours)
        let ok = envoyerParAirDrop(urls) { [weak self] etat in
            guard let self, dernier.peutDevenir(etat) else { return }
            let avant = dernier
            dernier = etat
            switch etat {
            case .lance: Log.ecrire("étagère : AirDrop, appareil choisi, envoi lancé (la fin du transfert n'est pas connue)")
            case .annule: Log.ecrire("étagère : AirDrop annulé\(avant == .lance ? " après le choix de l'appareil" : "")")
            default: Log.ecrire("étagère : AirDrop en échec")
            }
            // la réponse remplace « Envoi… » ; une annulation après « lancé » se dit même si le bandeau est parti (l'îlot s'était trompé
            // de bonne foi : il le corrige)
            guard self.moteur.bandeau?.vue == .etagereEnvoi || (avant == .lance && etat == .annule) else { return }
            montrer(etat)
        }
        if !ok { Log.ecrire("étagère : AirDrop indisponible"); dernier = .indisponible; montrer(.indisponible) }
    }

    /// « Captures d'écran ici » : on surveille le dossier des captures (comme Téléchargements : le noyau prévient, aucun sondage). Au
    /// lancement, seulement si l'option est allumée (l'accès a alors déjà été donné).
    /// Le dossier est relu à chaque fois (réglages appliqués, étagère relue) : s'il a changé dans Capture d'écran, la surveillance passe
    /// sur le nouveau.
    func activerCaptures(_ oui: Bool) {
        moteur.capturesActives = oui
        moteur.capturesIntrouvable = false
        if oui {
            let d = dossierCaptures()
            if capturesSource.actif {
                guard capturesSource.dossier.standardizedFileURL != d.standardizedFileURL else { return }
                capturesSource.arreter()
                Log.ecrire("captures : le dossier des captures a changé, surveillance déplacée")
            }
            capturesSource.dossier = d
            capturesSource.demarrer()
        } else {
            capturesSource.arreter()
            moteur.capturesAttente = false
        }
    }
    /// Le dossier des captures est absent (disque débranché, dossier supprimé) : l'interrupteur dit ce qui est vrai (rien n'est
    /// surveillé) et la ligne dit pourquoi. Le réglage reste : au prochain lancement, ou au prochain clic, on réessaie.
    func capturesIntrouvables() {
        moteur.capturesAttente = false
        moteur.capturesActives = false
        moteur.capturesIntrouvable = true
        moteur.donneesChangees()
    }
    /// De nouveaux fichiers finis dans le dossier des captures : les captures (pas les autres fichiers du Bureau) vont sur l'étagère,
    /// marquées « Nouveau » ; la pile de l'aile compte un fichier de plus.
    func capturesArrivees(_ l: [FichierTelecharge]) {
        let urls = l.map(\.url).filter(estUneCapture)
        guard !urls.isEmpty, moteur.etagereActive else { return }
        ranger(urls, nouveau: true)
    }
    /// macOS a refusé l'accès au dossier des captures : l'interrupteur revient sur éteint, la carte dit où le rendre.
    func capturesRefusees() {
        reglagesCentre.reglerCaptures(false)
        Log.ecrire("captures : accès au dossier refusé, option éteinte")
        moteur.capturesAttente = false
        moteur.capturesActives = false
        moteur.capturesRefusees = true
        moteur.donneesChangees()
    }

    /// Le dossier des captures : celui choisi dans Capture d'écran (réglage « location » de com.apple.screencapture), sinon le Bureau.
    static func dossierCapturesParDefaut() -> URL {
        let d = UserDefaults(suiteName: "com.apple.screencapture")
        let chemin = CapturesEcran.dossier(location: d?.string(forKey: "location"), maison: FileManager.default.homeDirectoryForCurrentUser.path)
        return URL(fileURLWithPath: chemin, isDirectory: true)
    }
    /// Une capture : la marque que macOS pose dessus (attribut étendu kMDItemIsScreenCapture), ou son nom (« Capture d’écran … »).
    /// `prefixe` : le début de nom choisi dans Capture d'écran (lu dans ses réglages ; l'essai n'y touche pas et passe nil).
    nonisolated static func estUneCapture(_ u: URL, prefixe: String? = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "name")) -> Bool {
        let marquee = getxattr(u.path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0) > 0
        return CapturesEcran.estUneCapture(nom: u.lastPathComponent, marquee: marquee, prefixe: prefixe)
    }

    /// L'app sous un point de l'écran (là où des fichiers ont été lâchés) : la fenêtre la plus haute à cet endroit (hors Verbe), puis son
    /// propriétaire. Aucune autorisation : seul le numéro du processus est lu, jamais le titre ni le contenu des fenêtres. Une icône du
    /// Dock : pas de nom (le Dock possède la fenêtre, pas l'app de l'icône).
    static func appSous(_ p: NSPoint) -> String? {
        var dessous = 0
        for _ in 0..<4 {
            let n = NSWindow.windowNumber(at: p, belowWindowWithWindowNumber: dessous)
            guard n > 0, let infos = CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(n)) as? [[String: Any]],
                  let pid = infos.first?[kCGWindowOwnerPID as String] as? pid_t else { return nil }
            if pid != getpid() {
                let app = NSRunningApplication(processIdentifier: pid)
                return EtagereIlot.appDuLacher(bundle: app?.bundleIdentifier, nom: app?.localizedName)
            }
            dessous = n
        }
        return nil
    }
}

/// AirDrop par le service de partage de macOS (NSSharingService « sendViaAirDrop ») : c'est le panneau AirDrop de macOS qui montre les
/// appareils proches et en choisit un ; Verbe ne voit ni la liste ni le choix. Le délégué répond : appareil choisi (`didShareItems` :
/// l'envoi est LANCÉ, pas forcément fini), annulé, ou en échec (`EnvoiAirDropEtat.depuisLeService`). Après « lancé », le délégué reste
/// à l'écoute quelques minutes : une annulation de l'envoi dans le panneau se dit encore. Rien ne passe par Internet ni par un serveur
/// de Verbe : AirDrop va d'appareil à appareil.
@MainActor
final class EnvoiAirDrop: NSObject, NSSharingServiceDelegate {
    /// Les envois en cours (le service ne garde pas son délégué).
    private static var enCours: [EnvoiAirDrop] = []
    /// Combien de temps on écoute encore après « lancé » (une annulation dans le panneau).
    static let ecouteApresLancement: TimeInterval = 600
    private let fin: (EnvoiEtagere.Etat) -> Void
    private init(fin: @escaping (EnvoiEtagere.Etat) -> Void) { self.fin = fin }

    /// Faux si AirDrop ne peut pas envoyer ces fichiers (éteint, ni Wi-Fi ni Bluetooth).
    static func envoyer(_ urls: [URL], fin: @escaping (EnvoiEtagere.Etat) -> Void) -> Bool {
        guard let s = NSSharingService(named: .sendViaAirDrop), s.canPerform(withItems: urls) else { return false }
        let e = EnvoiAirDrop(fin: fin)
        enCours.append(e)
        s.delegate = e
        // le panneau AirDrop passe devant (Verbe reste une app d'arrière-plan, sans icône dans le Dock)
        NSApp.activate()
        s.perform(withItems: urls)
        return true
    }
    private func liberer() { Self.enCours.removeAll { $0 === self } }
    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        fin(.lance)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.ecouteApresLancement) { [weak self] in MainActor.assumeIsolated { self?.liberer() } }
    }
    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        let n = error as NSError
        liberer()
        fin(EnvoiAirDropEtat.depuisLeService(partage: false, domaine: n.domain, code: n.code))
    }
}

// MARK: glisser des fichiers HORS de l'étagère

/// Un glisser de fichiers qui PART de l'étagère, fait avec AppKit (`NSDraggingSession`) plutôt qu'avec `onDrag` de SwiftUI : on peut y
/// mettre plusieurs fichiers d'un coup (« Tout »), et on sait où il finit. Accepté par une app (Mail, le Finder, une conversation…) : les
/// fichiers quittent l'étagère (« Remettre » quelques secondes) ; refusé, annulé, lâché sur l'îlot ou pris en lien seulement (le Terminal
/// qui colle le chemin) : ils restent. Un clic sans glisser appelle `clic` (ouvrir le fichier, ou la carte pour « Tout ») ; VoiceOver
/// « appuie » de même. Se pose en `.overlay` de ce qu'on prend.
struct SourceFichiers: NSViewRepresentable {
    var fichiers: [FichierEtagere]
    var m: IlotMoteur?
    var clic: (() -> Void)? = nil
    var survol: ((Bool) -> Void)? = nil
    var etiquette: String

    func makeNSView(context: Context) -> VueSourceFichiers {
        let v = VueSourceFichiers()
        v.config = self
        v.setAccessibilityRole(.button)
        v.setAccessibilityLabel(etiquette)
        return v
    }
    func updateNSView(_ v: VueSourceFichiers, context: Context) { v.config = self; v.setAccessibilityLabel(etiquette) }
}

final class VueSourceFichiers: NSView, NSDraggingSource {
    var config: SourceFichiers?
    /// Les essais : le glisser n'est jamais remis au système (il prendrait la vraie souris) ; l'essai reçoit les fichiers et dit lui-même
    /// où le glisser finit (accepté ou non, et en quel point de l'écran).
    nonisolated(unsafe) static var essai: ((_ urls: [URL], _ fin: @escaping (_ operation: NSDragOperation, _ point: NSPoint) -> Void) -> Void)?
    private var appui: NSPoint?
    private var parti = false
    private var fin: ((NSDragOperation, NSPoint) -> Void)?

    /// Les fichiers quittent l'étagère seulement si l'app en a pris une copie (Mail, le Finder, une conversation) ; un lien seul (le
    /// Terminal ou un éditeur qui collent le chemin, un alias fait dans le Finder) les laisse où ils sont.
    static func quitteLEtagere(_ operation: NSDragOperation) -> Bool { operation.contains(.copy) }
    /// Ce qu'on propose : hors de Verbe, une copie ou un lien, jamais « générique » (que le Finder lit comme « déplacer » sur le même
    /// disque, et la Corbeille du Dock comme « jeter ») : le fichier d'origine ne bouge jamais. Dans Verbe (l'îlot lui-même) : rien.
    static func masque(_ context: NSDraggingContext) -> NSDragOperation { context == .outsideApplication ? [.copy, .link] : [] }

    override func accessibilityPerformPress() -> Bool {
        guard let c = config?.clic else { return false }
        c()
        return true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for a in trackingAreas { removeTrackingArea(a) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { config?.survol?(true) }
    override func mouseExited(with event: NSEvent) { config?.survol?(false) }
    override func mouseDown(with e: NSEvent) { appui = e.locationInWindow; parti = false }
    override func mouseDragged(with e: NSEvent) {
        guard let a = appui, !parti, let c = config, !c.fichiers.isEmpty else { return }
        let p = e.locationInWindow
        guard hypot(p.x - a.x, p.y - a.y) > 4 else { return }
        parti = true
        commencer(c, e)
    }
    override func mouseUp(with e: NSEvent) {
        defer { appui = nil; parti = false }
        if appui != nil, !parti { config?.clic?() }
    }

    private func commencer(_ c: SourceFichiers, _ e: NSEvent) {
        let m = c.m, ids = c.fichiers.map(\.id)
        MainActor.assumeIsolated { m?.glisserSortantCommence() }
        let fin: (NSDragOperation, NSPoint) -> Void = { operation, point in
            MainActor.assumeIsolated {
                m?.glisserSortantFini()
                if Self.quitteLEtagere(operation) { m?.surAction(.etagereSortis(ids, point)) }
            }
        }
        if let essai = Self.essai { essai(c.fichiers.map(\.url), fin); return }
        self.fin = fin
        let pt = convert(e.locationInWindow, from: nil)
        // une petite pile sous le pointeur (plusieurs fichiers : décalés de 6 pt, comme dans le Finder)
        let items = c.fichiers.enumerated().map { i, f -> NSDraggingItem in
            let it = NSDraggingItem(pasteboardWriter: f.url as NSURL)
            let o = CGFloat(min(i, 3)) * 6
            it.setDraggingFrame(NSRect(x: pt.x - 20 + o, y: pt.y - 20 - o, width: 40, height: 40), contents: f.icone)
            return it
        }
        let s = beginDraggingSession(with: items, event: e, source: self)
        s.animatesToStartingPositionsOnCancelOrFail = true
        s.draggingFormation = .pile
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { Self.masque(context) }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        let f = fin; fin = nil
        f?(operation, screenPoint)
    }
}

// MARK: vues

/// Une tuile de l'étagère : l'icône du Finder et le nom (coupé au milieu, l'extension reste). Dans la carte, un clic ouvre le fichier,
/// on la glisse vers une app (le fichier lui-même, comme depuis le Finder : il quitte alors l'étagère), un « × » paraît au survol pour la
/// retirer, et « Nouveau » marque une capture arrivée d'elle-même.
struct TuileEtagere: View {
    static let hauteur: CGFloat = 70, espace: CGFloat = 8, icone: CGFloat = 40
    /// Cinq tuiles sur la largeur de la zone.
    static func largeur(_ zone: CGFloat) -> CGFloat { floor((zone - CGFloat(EtagereIlot.parRangee - 1) * espace) / CGFloat(EtagereIlot.parRangee)) }

    var fichier: FichierEtagere
    var largeur: CGFloat
    /// Le moteur, prévenu quand la tuile est glissée hors de la carte (nil dans un aperçu, où les tuiles ne se prennent pas).
    var m: IlotMoteur?
    var actions = false
    var ouvrir: () -> Void = {}
    var retirer: () -> Void = {}
    @State private var survol = false

    var body: some View {
        if actions {
            contenu
                .overlay { if !(m?.statique ?? false) { SourceFichiers(fichiers: [fichier], m: m, clic: ouvrir, survol: { survol = $0 }, etiquette: fichier.nom) } }
                .overlay(alignment: .topTrailing) {
                    if survol {
                        Button(action: retirer) {
                            Image(systemName: "xmark").font(.system(size: 8.5, weight: .bold)).foregroundStyle(.white)
                                .frame(width: 18, height: 18)
                                .background(Circle().fill(Color(white: 0.32)))
                                .overlay(Circle().strokeBorder(Color.black.opacity(0.6), lineWidth: 1))
                                .contentShape(Circle())
                        }
                        .buttonStyle(AppuiIlot(echelle: 0.86))
                        .offset(x: -4, y: 2)
                        .accessibilityLabel("Retirer \(fichier.nom) de l\u{2019}étagère")
                    }
                }
                .animation(.easeOut(duration: 0.12), value: survol)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(fichier.nom + (fichier.nouveau ? ", nouveau" : ""))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { ouvrir() }
        } else {
            contenu.accessibilityElement(children: .ignore).accessibilityLabel(fichier.nom)
        }
    }

    private var contenu: some View {
        VStack(spacing: 6) {
            Image(nsImage: fichier.icone).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                .frame(width: Self.icone, height: Self.icone)
            Text(fichier.nom).font(.system(size: 11, weight: .medium)).foregroundStyle(Color.white.opacity(0.78))
                .lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: largeur - 8)
        }
        .padding(.top, 6)
        .frame(width: largeur, height: Self.hauteur, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(survol ? 0.08 : 0)))
        .overlay(alignment: .top) { if fichier.nouveau { BadgeNouveau().offset(y: -3) } }
    }
}

/// « Nouveau » sur une capture arrivée d'elle-même (maquette, étape 9) : une petite pilule bleue.
struct BadgeNouveau: View {
    static let texte = "Nouveau"
    var body: some View {
        Text(Self.texte).font(.system(size: 9, weight: .bold)).foregroundStyle(.white).lineLimit(1).fixedSize()
            .padding(.horizontal, 5).frame(height: 14)
            .background(Capsule().fill(CouleursIlot.bleu))
            .overlay(Capsule().strokeBorder(Color.black.opacity(0.7), lineWidth: 1))
            .accessibilityHidden(true)
    }
}

/// Le symbole d'AirDrop (le système n'en a pas) : trois arcs ouverts vers le bas autour d'un point, dessinés au trait comme la maquette.
struct GlypheAirDrop: View {
    var couleur: Color
    var taille: CGFloat
    var body: some View {
        Canvas { c, s in
            let k = s.width / 24, centre = CGPoint(x: 12 * k, y: 12 * k)
            for r in [3.2, 6.4, 9.6] {
                var p = Path()
                p.addRelativeArc(center: centre, radius: r * k, startAngle: .degrees(135), delta: .degrees(270))
                c.stroke(p, with: .color(couleur), style: StrokeStyle(lineWidth: 1.9 * k, lineCap: .round))
            }
            c.fill(Path(ellipseIn: CGRect(x: centre.x - 1.5 * k, y: centre.y - 1.5 * k, width: 3 * k, height: 3 * k)), with: .color(couleur))
        }
        .frame(width: taille, height: taille)
        .accessibilityHidden(true)
    }
}

/// Replié, l'étagère garde des fichiers (maquette, étape 3) : la pile et le nombre dans l'aile GAUCHE (la seule : à droite, rien que la
/// caméra). Le nombre grossit un instant quand un fichier arrive (pas avec « Réduire les animations »).
struct PileEtagere: View {
    @ObservedObject var m: IlotMoteur
    var g: GrilleIlot
    static let glyphe = "rectangle.stack.fill", tailleGlyphe: CGFloat = 12.5, tailleNombre: CGFloat = 13, espace: CGFloat = 4
    /// La pile et le nombre, mesurés (« 10 », le plus large) : ils tiennent dans l'aile, 3 pt de marge de chaque côté.
    static var largeur: CGFloat {
        MesureIlot.symbole(glyphe, tailleGlyphe) + espace + MesureIlot.texte("\(EtagereIlot.capacite)", tailleNombre, .bold, chiffres: true)
    }
    var body: some View {
        let v = VueIlot.etagerePile
        let n = m.etagere.count
        let gauche = -g.cou(v), l = g.cou(v) - g.hc
        HStack(spacing: Self.espace) {
            Image(systemName: Self.glyphe).font(.system(size: Self.tailleGlyphe, weight: .semibold))
            Text("\(n)").font(.system(size: Self.tailleNombre, weight: .bold).monospacedDigit())
                .contentTransition(.numericText())
                .keyframeAnimator(initialValue: 1.0, trigger: n) { t, e in t.scaleEffect(m.reduire || m.statique ? 1 : e) } keyframes: { _ in
                    KeyframeTrack { SpringKeyframe(1.45, duration: 0.14); SpringKeyframe(1, duration: 0.3, spring: Spring(response: 0.3, dampingRatio: 0.6)) }
                }
        }
        .foregroundStyle(.white)
        .lineLimit(1).fixedSize()
        .posee(CGRect(x: gauche + 3, y: 0, width: l - 6, height: g.barre), m.aspect(v, rang: 0), ancre: .center, .center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Étagère : " + EtagereIlot.resume(n))
    }
}

/// Un glisser de fichiers vient de commencer, n'importe où (maquette, étape 1) : l'îlot s'étire un peu et dit « Glisse ici », avec une
/// flèche qui monte (immobile avec « Réduire les animations » ; elle n'existe que pendant le glisser).
struct AppelEtagere: View {
    @ObservedObject var m: IlotMoteur
    var g: GrilleIlot
    static let texte = "Glisse ici"
    var body: some View {
        let v = VueIlot.etagereAppel
        let z = g.zone(v, haut: 8, bas: 8)
        let anime = !m.reduire && !m.statique
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(CouleursIlot.bleu.opacity(0.26))
                Group {
                    if anime {
                        fleche.phaseAnimator([0.0, -2.5]) { f, dy in f.offset(y: dy) } animation: { _ in .easeInOut(duration: 0.55) }
                    } else { fleche }
                }
            }
            .frame(width: 22, height: 22)
            Text(Self.texte).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(1).fixedSize()
        }
        .posee(z, m.aspect(v, rang: 0), ancre: .top, .center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Glisse ici : l\u{2019}étagère ou AirDrop")
    }
    private var fleche: some View { Image(systemName: "arrow.up").font(.system(size: 11, weight: .bold)).foregroundStyle(Color(hex: 0x5EB0FF)) }
}

/// Une des deux zones de dépôt (cadre pointillé de 20 pt de rayon) : son symbole, son nom, ce qu'elle fait ; elle s'éclaire quand le
/// pointeur qui glisse est dessus.
struct ZoneDepotVue<Glyphe: View>: View {
    var titre: String
    var sous: String
    var survolee: Bool
    var animer: Bool
    @ViewBuilder var glyphe: () -> Glyphe
    var body: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(survolee ? CouleursIlot.bleu.opacity(0.24) : Color.white.opacity(0.03))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(survolee ? 0.62 : 0.28), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
            .overlay {
                VStack(spacing: 0) {
                    glyphe().frame(height: 28)
                    Text(titre).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).lineLimit(1).padding(.top, 9)
                    Text(sous).font(.system(size: 12.5, weight: .medium)).foregroundStyle(survolee ? Color.white.opacity(0.85) : CouleursIlot.encre2)
                        .lineLimit(1).minimumScaleFactor(0.85).padding(.top, 2).padding(.horizontal, 8)
                }
            }
            .scaleEffect(survolee && animer ? 1.02 : 1)
            .animation(animer ? .spring(response: 0.3, dampingFraction: 0.72) : nil, value: survolee)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(titre + " : " + sous)
    }
}

/// L'îlot ouvert en grand pendant qu'on glisse des fichiers près de l'encoche (maquette, étape 2) : « Étagère » à gauche (la garder ;
/// le nombre de fichiers déjà gardés dans son coin), « AirDrop » à droite (l'envoyer). Lâché sur « Étagère » : « Rangé » (étape 3).
struct DepotEtagere: View {
    @ObservedObject var m: IlotMoteur
    var g: GrilleIlot
    static let sousEtagere = "La garder pour plus tard", sousAirDrop = "Envoyer à un appareil proche"
    /// Les deux zones, depuis le centre de l'encoche (essais : où viser).
    static func cadres(_ g: GrilleIlot) -> (etagere: CGRect, airdrop: CGRect) {
        let z = g.zone(.etagereDepot, haut: 14, bas: 14)
        let l = (z.width - 12) / 2
        return (CGRect(x: z.minX, y: z.minY, width: l, height: z.height), CGRect(x: z.maxX - l, y: z.minY, width: l, height: z.height))
    }
    var body: some View {
        let v = VueIlot.etagereDepot
        let (ce, ca) = Self.cadres(g)
        let animer = !m.reduire && !m.statique
        let n = m.etagere.count
        ZStack(alignment: .topLeading) {
            Group {
                if m.depotRange {
                    rangé(n)
                } else {
                    ZoneDepotVue(titre: "Étagère", sous: Self.sousEtagere, survolee: m.depotZone == .etagere, animer: animer) {
                        Image(systemName: "tray").font(.system(size: 23, weight: .medium)).foregroundStyle(Color(hex: 0x5EB0FF))
                    }
                    .overlay(alignment: .topTrailing) {
                        if n > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: PileEtagere.glyphe).font(.system(size: 9.5, weight: .semibold))
                                Text("\(n)").font(.system(size: 11, weight: .bold).monospacedDigit())
                            }
                            .foregroundStyle(Color.white.opacity(0.5)).padding(.top, 10).padding(.trailing, 13)
                            .accessibilityHidden(true)
                        }
                    }
                }
            }
            .posee(ce, m.aspect(v, rang: 0), ancre: .center)
            ZoneDepotVue(titre: "AirDrop", sous: Self.sousAirDrop, survolee: m.depotZone == .airdrop && !m.depotRange, animer: animer) {
                GlypheAirDrop(couleur: Color(hex: 0x5EB0FF), taille: 28)
            }
            .opacity(m.depotRange ? 0.35 : 1)
            .posee(ca, m.aspect(v, rang: 1), ancre: .center)
        }
        .frame(width: IlotMoteur.largeur, height: IlotMoteur.hauteurMax, alignment: .topLeading)
    }
    private func rangé(_ n: Int) -> some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(CouleursIlot.vert.opacity(0.14))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(CouleursIlot.vert.opacity(0.5), lineWidth: 1.5))
            .overlay {
                VStack(spacing: 0) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 24, weight: .semibold)).foregroundStyle(CouleursIlot.vert).frame(height: 28)
                    Text("Rangé").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).padding(.top, 9)
                    Text(EtagereIlot.resume(n) + " sur l\u{2019}étagère").font(.system(size: 12.5, weight: .medium)).foregroundStyle(CouleursIlot.encre2)
                        .lineLimit(1).padding(.top, 2)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Rangé : " + EtagereIlot.resume(n) + " sur l\u{2019}étagère")
    }
}

/// La carte Étagère (depuis le Centre) : « ‹ Centre », l'en-tête et « Tout vider », les fichiers (cinq par rangée), puis l'option
/// « Captures d'écran ici ».
struct CarteEtagere: View {
    @ObservedObject var m: IlotMoteur
    var g: GrilleIlot
    /// La ligne « Captures d'écran ici », depuis le centre de l'encoche (essais : où cliquer).
    static func cadreCaptures(_ g: GrilleIlot) -> CGRect {
        let z = g.zone(.etagere, haut: 10, bas: 12)
        return CGRect(x: z.minX, y: z.maxY - CGFloat(GeoIlot.ligneCaptures), width: z.width, height: CGFloat(GeoIlot.ligneCaptures))
    }
    var body: some View {
        let v = VueIlot.etagere
        let z = g.zone(v, haut: 10, bas: 12)
        let lt = TuileEtagere.largeur(z.width)
        let n = m.etagere.count
        let rangees = stride(from: 0, to: n, by: EtagereIlot.parRangee).map { Array(m.etagere[$0..<min(n, $0 + EtagereIlot.parRangee)]) }
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                if m.cartes.contains(.centre) { PiluleCentre(titre: "Centre", retour: true, etiquette: "Revenir au Centre") { m.allerA(.centre) } }
                GlypheIlot(nom: "tray.full.fill", couleur: CouleursIlot.bleu, taille: 16).frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Étagère").font(TexteIlot.ligne).tracking(-0.1).foregroundStyle(.white).lineLimit(1)
                    Text(n == 0 ? "Vide" : EtagereIlot.resume(n) + " \u{00B7} glisse-" + (n > 1 ? "les" : "le") + " vers une app")
                        .font(TexteIlot.l2).foregroundStyle(CouleursIlot.encre2).lineLimit(1).truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if n > 0 { CapIlot(titre: "Tout vider", hauteur: 28, etiquette: "Vider l\u{2019}étagère") { m.surAction(.etagereVider) }.fixedSize() }
            }
            .frame(height: 42)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1).padding(.leading, 34) }
            .aspectIlot(m.aspect(v, rang: 0), ancre: .top)
            if n == 0 {
                Text("Glisse des fichiers sur l\u{2019}encoche : ils t\u{2019}attendront ici.")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(CouleursIlot.encre3).lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: TuileEtagere.hauteur, alignment: .center)
                    .padding(.top, 8)
                    .aspectIlot(m.aspect(v, rang: 1), ancre: .top)
            } else {
                VStack(alignment: .leading, spacing: TuileEtagere.espace) {
                    ForEach(Array(rangees.enumerated()), id: \.offset) { r, rangee in
                        HStack(spacing: TuileEtagere.espace) {
                            ForEach(rangee) { f in
                                TuileEtagere(fichier: f, largeur: lt, m: m, actions: true,
                                             ouvrir: { m.surAction(.etagereOuvrir(f.id)) }, retirer: { m.surAction(.etagereRetirer(f.id)) })
                            }
                        }
                        .aspectIlot(m.aspect(v, rang: 1 + r), ancre: .top)
                    }
                }
                .padding(.top, 8)
            }
            Spacer(minLength: 0)
            LigneCaptures(m: m).frame(height: CGFloat(GeoIlot.ligneCaptures)).aspectIlot(m.aspect(v, rang: 3), ancre: .top)
        }
        .frame(width: z.width, height: z.height, alignment: .top)
        .offset(x: IlotMoteur.largeur / 2 + z.minX, y: z.minY)
    }
}

/// « Captures d'écran ici » (maquette, étape 9) : un interrupteur, éteint par défaut. Allumé, les nouvelles captures arrivent sur
/// l'étagère, marquées « Nouveau » (elles restent là où macOS les range). Au premier clic, macOS demande l'accès au dossier.
struct LigneCaptures: View {
    @ObservedObject var m: IlotMoteur
    static let titre = "Captures d\u{2019}écran ici"
    var body: some View {
        let sous: String = m.capturesAttente ? "Un instant\u{2026}" : (m.capturesRefusees ? "Accès refusé : ouvrir Réglages Système" :
            (m.capturesIntrouvable ? "Dossier des captures introuvable" :
            (m.capturesActives ? "Les nouvelles arrivent sur l\u{2019}étagère" : "Les nouvelles arriveront sur l\u{2019}étagère")))
        HStack(spacing: 10) {
            Image(systemName: "viewfinder").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.white.opacity(0.8)).frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(Self.titre).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                Text(sous).font(.system(size: 11, weight: .medium)).foregroundStyle(m.capturesRefusees || m.capturesIntrouvable ? Color(hex: 0xFF6961) : CouleursIlot.encre3).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { if m.capturesRefusees { m.surAction(.etagereCapturesReglages) } }
            InterrupteurIlot(actif: m.capturesActives || m.capturesAttente, animer: !m.reduire && !m.statique, etiquette: Self.titre) {
                m.surAction(.etagereCaptures)
            }
        }
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.08)))
    }
}

/// Un interrupteur comme ceux de macOS (38 × 22 pt), vert allumé.
struct InterrupteurIlot: View {
    var actif: Bool
    var animer: Bool
    var etiquette: String
    var action: () -> Void
    static let largeur: CGFloat = 38, hauteur: CGFloat = 22
    var body: some View {
        Button(action: action) {
            Capsule().fill(actif ? CouleursIlot.vert : Color.white.opacity(0.22))
                .overlay(alignment: actif ? .trailing : .leading) { Circle().fill(.white).padding(2).shadow(color: .black.opacity(0.25), radius: 1, y: 0.5) }
                .frame(width: Self.largeur, height: Self.hauteur)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(animer ? .spring(response: 0.28, dampingFraction: 0.8) : nil, value: actif)
        .accessibilityLabel(etiquette)
        .accessibilityValue(actif ? "Allumé" : "Éteint")
        .accessibilityAddTraits(.isToggle)
    }
}

/// En haut du Centre, quand l'étagère garde des fichiers (maquette, étape 6) : « Tout » (une poignée qui glisse tous les fichiers d'un
/// coup), les trois derniers rangés (glissables, un clic les ouvre), « +N » pour les autres, et le chevron qui ouvre la carte Étagère.
/// Un fichier glissé dessus depuis une autre app l'éclaire : on peut l'y lâcher.
struct RangeeEtagere: View {
    @ObservedObject var m: IlotMoteur
    var largeur: CGFloat
    static let tout: CGFloat = 54, separateur: CGFloat = 17, chevron: CGFloat = 26, marge: CGFloat = 8, montres = 3
    /// La largeur d'un fichier montré : ce qui reste, en trois (moins « +N » s'il en reste).
    static func largeurFichier(_ largeur: CGFloat, reste: Bool) -> CGFloat {
        floor((largeur - 2 * marge - tout - separateur - chevron - (reste ? 30 : 0)) / CGFloat(montres))
    }
    /// Où sont « Tout », le n-ième fichier montré et le chevron, depuis le bord gauche de la rangée (essais : où cliquer).
    static func xTout() -> CGFloat { marge + tout / 2 }
    static func xFichier(_ i: Int, largeur: CGFloat, reste: Bool) -> CGFloat {
        marge + tout + separateur + largeurFichier(largeur, reste: reste) * (CGFloat(i) + 0.5)
    }
    static func xChevron(_ largeur: CGFloat) -> CGFloat { largeur - marge - chevron / 2 }

    @State private var survolTout = false

    var body: some View {
        let f = m.etagere
        let montres = Array(f.suffix(Self.montres))
        let reste = f.count - montres.count
        let lf = Self.largeurFichier(largeur, reste: reste > 0)
        let depot = m.depot && m.depotSurvole
        HStack(spacing: 0) {
            VStack(spacing: 3) {
                Image(systemName: PileEtagere.glyphe).font(.system(size: 14, weight: .semibold))
                Text("Tout").font(.system(size: 11, weight: .semibold)).lineLimit(1).fixedSize()
            }
            .foregroundStyle(.white)
            .frame(width: Self.tout, height: 46)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(survolTout ? CouleursIlot.bleu.opacity(0.32) : Color.white.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(CouleursIlot.bleu.opacity(survolTout ? 0.9 : 0), lineWidth: 1.5))
            // un clic (sans glisser) ouvre la carte Étagère, comme le chevron : « Tout » n'est jamais un bouton qui ne fait rien
            .overlay { if !m.statique { SourceFichiers(fichiers: f, m: m, clic: { m.epinglerLeCentre(); m.ouvrirEtagere() }, survol: { survolTout = $0 },
                                                       etiquette: "Glisser les \(EtagereIlot.resume(f.count)) d\u{2019}un coup, ou ouvrir l\u{2019}étagère") } }
            .animation(.easeOut(duration: 0.12), value: survolTout)
            Rectangle().fill(Color.white.opacity(0.14)).frame(width: 1, height: 34).padding(.horizontal, (Self.separateur - 1) / 2)
            ForEach(montres) { x in
                VStack(spacing: 4) {
                    Image(nsImage: x.icone).resizable().interpolation(.high).aspectRatio(contentMode: .fit).frame(width: 28, height: 28)
                    Text(x.nom).font(.system(size: 11, weight: .medium)).foregroundStyle(Color.white.opacity(0.8))
                        .lineLimit(1).truncationMode(.middle).frame(maxWidth: lf - 6)
                }
                .frame(width: lf, height: 52)
                .overlay(alignment: .top) { if x.nouveau { BadgeNouveau().offset(y: -5) } }
                .overlay { if !m.statique { SourceFichiers(fichiers: [x], m: m, clic: { m.surAction(.etagereOuvrir(x.id)) }, etiquette: x.nom) } }
            }
            if reste > 0 {
                Text("+\(reste)").font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundStyle(Color.white.opacity(0.6))
                    .frame(width: 30)
            }
            Spacer(minLength: 0)
            Button { m.epinglerLeCentre(); m.ouvrirEtagere() } label: {
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.white.opacity(0.6))
                    .frame(width: Self.chevron, height: 46).contentShape(Rectangle())
            }
            .buttonStyle(AppuiIlot(echelle: 0.88))
            .accessibilityLabel("Ouvrir l\u{2019}étagère")
        }
        .padding(.horizontal, Self.marge)
        .frame(width: largeur, height: CGFloat(DispositionCentre.rangeeEtagere))
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(depot ? CouleursIlot.bleu.opacity(0.22) : Color.white.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(depot ? 0.85 : 0), lineWidth: 1.5))
        .animation(m.reduire || m.statique ? nil : .easeOut(duration: 0.2), value: depot)
    }
}
