import AppKit
import SwiftUI
import CoreServices
import DicteeCore

// « Claude au travail » (maquette design/maquettes/ilot-apple.html, cinq idées de plus, 1) : l'îlot montre où en est une tâche de
// Claude Code. Les crochets de Claude Code (branchés depuis Réglages › Îlot) appellent un petit script qui ajoute une ligne par
// événement au fichier de la session, dans ~/Library/Application Support/Dictee/claude/. Verbe surveille ce dossier par FSEvents
// (le système prévient quand un fichier change : aucun sondage), relit seulement les lignes nouvelles, et `VeilleClaude` en tire l'état.

extension CouleursIlot {
    /// Le corail de Claude (maquette : #e8835c).
    static let corail = Color(hex: 0xE8835C)
}

/// L'étoile de Claude, dessinée comme dans la maquette : six rayons arrondis qui se croisent (douze branches), sans fond.
struct EtoileClaude: View {
    var couleur: Color
    var body: some View {
        RayonsClaude().fill(couleur).accessibilityHidden(true)
    }
}

struct RayonsClaude: Shape {
    func path(in r: CGRect) -> Path {
        let s = min(r.width, r.height)
        let w = s * 0.1, h = s * 0.86
        var p = Path()
        let rayon = Path(roundedRect: CGRect(x: -w / 2, y: -h / 2, width: w, height: h), cornerRadius: w / 2)
        for k in 0..<6 {
            let t = CGAffineTransform(rotationAngle: CGFloat(k) * .pi / 6).concatenating(CGAffineTransform(translationX: r.midX, y: r.midY))
            p.addPath(rayon, transform: t)
        }
        return p
    }
}

extension IlotMoteur {
    /// La place du texte dans l'aile droite d'un compact de 60 pt : 8 pt du coin, 4 pt de la caméra.
    static let aileClaude: CGFloat = 48

    /// Le texte de l'aile droite (et de la bulle) : « 3 sur 7 » (« 12/14 » si la forme longue ne tient pas), « Attend », ou rien.
    func texteClaude(_ s: SessionClaude?, taille: CGFloat = 13) -> String {
        guard let s else { return "" }
        if s.etat == .attend { return "Attend" }
        guard let p = s.progres else { return "" }
        return MesureIlot.texte(p.texte, taille, .semibold, chiffres: true) <= Self.aileClaude ? p.texte : p.court
    }
}

/// L'étoile, pièce qui voyage : dans son anneau (aile gauche) au repos, ou seule au milieu de l'aile (rien à dire) ; dans l'en-tête de la
/// carte « Claude Code » une fois survolée (une session attend). Le petit « 2 » la suit quand deux sessions travaillent.
struct ClaudeVoyageur: View {
    @ObservedObject var m: IlotMoteur
    var g: GrilleIlot

    var body: some View {
        let p = m.ouverture(.claude)
        let a = m.aspect(FamilleIlot.claude)
        let minimal = m.resolution.principal == .claudeMinimal
        // l'étoile seule suit le cou dessiné (de l'étoile seule à l'étoile dans son anneau, elle glisse avec la forme)
        let dansLesAiles = m.courante == .claudeMinimal || m.courante == .claudeCompact
        let anneau = m.cadreAnneauClaude(g, minimal ? .claudeMinimal : .claudeCompact)
        let c: CGFloat = minimal ? (dansLesAiles ? -(g.hc + CGFloat(m.trace.cou)) / 2 : g.centreAile(.claudeMinimal, droite: false)) : anneau.midX
        let petit: CGFloat = minimal ? 15 : 10.5
        let compact = CGRect(x: c - petit / 2, y: g.barre / 2 - petit / 2, width: petit, height: petit)
        let e = PlanCarteClaude.cadreEntete(g)
        let x0 = e.minX + (m.cartes.contains(.centre) ? PlanCarteClaude.pilule + 10 : 0)
        let etendu = CGRect(x: x0, y: e.midY - 7, width: 14, height: 14)
        let (r, _) = voyageIlot(compact, etendu, p)
        let attend = (m.claude ?? m.dernierClaude)?.etat == .attend
        return ZStack(alignment: .topLeading) {
            EtoileClaude(couleur: attend && p < 0.5 ? CouleursIlot.ambre : CouleursIlot.corail)
                .posee(r, a, ancre: .center, .center)
            if m.claudeAuTravail >= 2, p < 0.5 {
                BadgeClaude(nombre: m.claudeAuTravail)
                    .posee(CGRect(x: minimal ? r.midX + 3 : anneau.maxX - 7, y: minimal ? r.minY - 6 : anneau.minY - 5, width: 16, height: 13),
                           AspectIlot(opacite: a.opacite * (1 - 2 * p), flou: 0, echelle: 1), ancre: .center, .leading)
            }
        }
    }
}

// MARK: - le dossier des sessions

/// Une ligne nouvelle du fichier d'une session.
struct LigneClaude {
    var session: String
    var texte: String
}

/// Le dossier où le script des crochets écrit, surveillé par FSEvents sur une file à part. Au lancement, ce qui est déjà là est relu
/// (sans rien annoncer) ; ensuite, seules les lignes ajoutées sont lues.
@MainActor
final class SourceClaude {
    /// Des lignes nouvelles ; `relecture` : c'est la lecture du lancement (rien à annoncer).
    var surLignes: ([LigneClaude], _ relecture: Bool) -> Void = { _, _ in }
    /// Le dossier surveillé (les essais en donnent un temporaire).
    var dossier: URL = InstallationClaude.parDefaut.etats
    private var travail: SurveillanceClaude?
    var actif: Bool { travail != nil }

    func demarrer() {
        guard travail == nil else { return }
        let t = SurveillanceClaude(dossier: dossier)
        travail = t
        // ce qui arrive après un arrêt (ou d'une ancienne surveillance) est ignoré
        t.surLignes = { [weak self, weak t] l, relecture in
            DispatchQueue.main.async { MainActor.assumeIsolated { guard let self, let t, self.travail === t else { return }; self.surLignes(l, relecture) } }
        }
        t.demarrer()
    }

    func arreter() {
        travail?.arreter()
        travail = nil
    }

    /// La session est finie : son fichier ne sert plus.
    func effacer(_ session: String) { travail?.effacer(session) }

    /// Efface, hors du fil principal, les fichiers de sessions sans nouvelle depuis un jour (une session jamais close : Terminal fermé,
    /// Mac éteint, ou réglage éteint pendant que Claude Code écrivait).
    nonisolated static func nettoyer(_ dossier: URL) {
        DispatchQueue.global(qos: .utility).async { SurveillanceClaude.effacerLesVieux(dossier.resolvingSymlinksInPath()) }
    }
}

/// Le travail sur la file : FSEvents sur le dossier, la position lue de chaque fichier. Tout son état ne vit que sur `file`.
private final class SurveillanceClaude: @unchecked Sendable {
    let dossier: URL
    private let file = DispatchQueue(label: "verbe.ilot.claude", qos: .utility)
    var surLignes: ([LigneClaude], Bool) -> Void = { _, _ in }
    private var flux: FSEventStreamRef?
    private var lus: [String: UInt64] = [:]
    private var restes: [String: Data] = [:]
    private var arrete = false
    /// Un fichier sans nouvelle depuis un jour est effacé au lancement (une session jamais close : Terminal fermé, Mac éteint).
    static let ageMax: TimeInterval = 86_400

    init(dossier: URL) { self.dossier = dossier.resolvingSymlinksInPath() }

    func demarrer() { file.async { self.ouvrir() } }

    func arreter() {
        file.async {
            self.arrete = true
            if let f = self.flux { FSEventStreamStop(f); FSEventStreamInvalidate(f); FSEventStreamRelease(f) }
            self.flux = nil
        }
    }

    func effacer(_ session: String) {
        file.async {
            try? FileManager.default.removeItem(at: self.dossier.appendingPathComponent(session + ".jsonl"))
            self.lus[session] = nil; self.restes[session] = nil
        }
    }

    private func ouvrir() {
        guard !arrete, flux == nil else { return }
        try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        // les vieux fichiers d'abord, puis tout ce qui reste est relu sans rien annoncer
        Self.effacerLesVieux(dossier)
        // le flux retient la surveillance (retain/release) : un rappel déjà en file derrière l'arrêt trouve toujours un objet vivant ; le
        // flux la relâche quand il est libéré (`arreter`)
        var ctx = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                       retain: { info in
                                           guard let info else { return nil }
                                           _ = Unmanaged<SurveillanceClaude>.fromOpaque(info).retain()
                                           return info
                                       },
                                       release: { info in
                                           guard let info else { return }
                                           Unmanaged<SurveillanceClaude>.fromOpaque(info).release()
                                       },
                                       copyDescription: nil)
        let rappel: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<SurveillanceClaude>.fromOpaque(info).takeUnretainedValue().relire(relecture: false)
        }
        let drapeaux = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        guard let f = FSEventStreamCreate(nil, rappel, &ctx, [dossier.path] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.1, drapeaux) else {
            Log.ecrire("claude : surveillance du dossier impossible (FSEvents)")
            return
        }
        FSEventStreamSetDispatchQueue(f, file)
        FSEventStreamStart(f)
        flux = f
        relire(relecture: true)
        Log.ecrire("claude : surveillance du dossier des sessions (\(lus.count) déjà là)")
    }

    private func fichiers() -> [(String, URL)] { Self.fichiers(dossier) }
    static func fichiers(_ dossier: URL) -> [(String, URL)] {
        let l = (try? FileManager.default.contentsOfDirectory(at: dossier, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])) ?? []
        return l.filter { $0.pathExtension == "jsonl" }.map { ($0.deletingPathExtension().lastPathComponent, $0) }
    }
    static func effacerLesVieux(_ dossier: URL) {
        for (_, url) in fichiers(dossier) {
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if Date().timeIntervalSince(date) > ageMax { try? FileManager.default.removeItem(at: url) }
        }
    }

    /// Relit les lignes ajoutées depuis la dernière fois (seulement les lignes complètes : la fin d'une ligne en cours d'écriture attend).
    private func relire(relecture: Bool) {
        guard !arrete else { return }
        var nouvelles: [LigneClaude] = []
        let presents = fichiers()
        let noms = Set(presents.map(\.0))
        for n in lus.keys where !noms.contains(n) { lus[n] = nil; restes[n] = nil }
        for (nom, url) in presents.sorted(by: { $0.0 < $1.0 }) {
            let taille = UInt64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            var depuis = lus[nom] ?? 0
            if taille < depuis { depuis = 0; restes[nom] = nil }   // le fichier a été vidé ou remplacé
            guard taille > depuis, let h = try? FileHandle(forReadingFrom: url) else { lus[nom] = depuis; continue }
            defer { try? h.close() }
            try? h.seek(toOffset: depuis)
            let d = (try? h.read(upToCount: Int(min(taille - depuis, 8_000_000)))) ?? Data()
            lus[nom] = depuis + UInt64(d.count)
            var tampon = (restes[nom] ?? Data()) + d
            if let fin = tampon.lastIndex(of: 0x0A) {
                let complet = tampon[tampon.startIndex...fin]
                tampon = Data(tampon[(fin + 1)...])
                for l in complet.split(separator: 0x0A) where !l.isEmpty {
                    nouvelles.append(LigneClaude(session: nom, texte: String(decoding: l, as: UTF8.self)))
                }
            }
            restes[nom] = tampon.count > 1_000_000 ? nil : tampon
        }
        if !nouvelles.isEmpty || relecture { surLignes(nouvelles, relecture) }
    }
}

// MARK: - brancher Claude Code

/// Brancher (et débrancher) Verbe sur Claude Code : écrire le script, fusionner nos crochets dans settings.json (`CrochetsClaude`), avec
/// une sauvegarde à côté avant d'écrire et une écriture atomique. Les chemins sont injectables : les essais n'utilisent jamais ~/.claude.
struct InstallationClaude {
    /// Le settings.json de Claude Code.
    var reglages: URL
    /// Le dossier de Verbe (~/Library/Application Support/Dictee) : le script et le dossier des sessions.
    var dossierVerbe: URL
    var script: URL { dossierVerbe.appendingPathComponent("claude-crochet.sh") }
    var etats: URL { dossierVerbe.appendingPathComponent("claude", isDirectory: true) }
    var sauvegarde: URL { reglages.appendingPathExtension("verbe-sauvegarde") }

    static var parDefaut: InstallationClaude {
        let maison = FileManager.default.homeDirectoryForCurrentUser
        return InstallationClaude(reglages: maison.appendingPathComponent(".claude/settings.json"),
                                  dossierVerbe: DossierVerbe.url(maison: maison))
    }

    enum Echec: Error {
        case illisible, inaccessible, forme, ecriture(String)
        var phrase: String {
            switch self {
            case .illisible: return "Le fichier ~/.claude/settings.json n\u{2019}est pas du JSON valide : rien n\u{2019}a été changé."
            case .inaccessible: return "Le fichier ~/.claude/settings.json n\u{2019}a pas pu être lu (droits, encodage, lien cassé) : rien n\u{2019}a été changé."
            case .forme: return "Les crochets de ~/.claude/settings.json ont une forme inattendue : rien n\u{2019}a été changé."
            case .ecriture(let m): return "Écriture impossible (\(m)) : rien n\u{2019}a été changé."
            }
        }
    }

    /// Le vrai fichier (si settings.json est un lien, celui qu'il désigne : le lien reste en place).
    private var cible: URL { reglages.resolvingSymlinksInPath() }
    /// Le contenu de settings.json ; nil : il n'existe pas. Un fichier présent mais illisible (droits refusés, octets qui ne sont pas de
    /// l'UTF-8, lien cassé) n'est JAMAIS pris pour un fichier absent : on refuse (`Echec.inaccessible`), sinon il serait remplacé par
    /// nos seuls crochets, sans copie.
    private func lire() throws -> String? {
        let fm = FileManager.default
        // le fichier, ou le lien lui-même (sans le suivre : un lien cassé existe, mais ne mène nulle part)
        let present = fm.fileExists(atPath: cible.path) || (try? fm.attributesOfItem(atPath: reglages.path)) != nil
        guard present else { return nil }
        guard let texte = try? String(contentsOf: cible, encoding: .utf8) else {
            Log.ecrire("claude : settings.json présent mais illisible, rien n'est écrit")
            throw Echec.inaccessible
        }
        return texte
    }

    /// Faux aussi pour un settings.json illisible (on ne sait pas : « Brancher » le dira sans rien écrire).
    var estBranche: Bool { CrochetsClaude.estBranche((try? lire()) ?? nil) }

    func brancher() throws {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: etats, withIntermediateDirectories: true)
            try Data(ScriptCrochet.texte(dossier: etats.path).utf8).write(to: script, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        } catch { throw Echec.ecriture(error.localizedDescription) }
        try reecrire { try CrochetsClaude.brancher($0, script: script.path) }
    }

    /// Une nouvelle version de Verbe peut changer le script (ici : le message des notifications et le titre de la session en plus).
    /// Branché (nos crochets sont dans settings.json, qu'on ne fait que lire), le script est remplacé s'il diffère ou manque, l'ancien
    /// gardé à côté (`claude-crochet.sh.verbe-sauvegarde`), par une écriture atomique. Débranché : rien. Rend vrai s'il a été écrit.
    @discardableResult
    func mettreAJourLeScript() -> Bool {
        let fm = FileManager.default
        let voulu = ScriptCrochet.texte(dossier: etats.path)
        let actuel = try? String(contentsOf: script, encoding: .utf8)
        guard actuel != voulu, estBranche else { return false }
        do {
            if let actuel { try Data(actuel.utf8).write(to: script.appendingPathExtension("verbe-sauvegarde"), options: .atomic) }
            try fm.createDirectory(at: etats, withIntermediateDirectories: true)
            try Data(voulu.utf8).write(to: script, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
            Log.ecrire("claude : script des crochets mis à jour (l'ancien gardé à côté)")
            return true
        } catch {
            Log.ecrire("claude : mise à jour du script impossible (\(error.localizedDescription))")
            return false
        }
    }

    /// Retire nos crochets ; le script reste (une session déjà ouverte peut encore l'appeler : il ne fait rien de mal).
    func debrancher() throws {
        guard try lire() != nil else { return }
        try reecrire { try CrochetsClaude.debrancher($0 ?? "") }
    }

    private func reecrire(_ transformer: (String?) throws -> String) throws {
        let fm = FileManager.default
        let avant = try lire()
        let apres: String
        do { apres = try transformer(avant) } catch CrochetsClaude.Erreur.illisible { throw Echec.illisible } catch { throw Echec.forme }
        guard apres != avant else { return }
        let f = cible
        do {
            try fm.createDirectory(at: f.deletingLastPathComponent(), withIntermediateDirectories: true)
            var droits: Any?
            if let avant {
                // la copie d'avant, à côté (remplace la précédente)
                try Data(avant.utf8).write(to: sauvegarde, options: .atomic)
                droits = try? fm.attributesOfItem(atPath: f.path)[.posixPermissions]
            }
            try Data(apres.utf8).write(to: f, options: .atomic)
            if let droits { try? fm.setAttributes([.posixPermissions: droits], ofItemAtPath: f.path) }
        } catch { throw Echec.ecriture(error.localizedDescription) }
        Log.ecrire("claude : crochets \(CrochetsClaude.estBranche(apres) ? "branchés" : "débranchés") dans settings.json")
    }
}

// MARK: - le contrôleur

extension IlotControleur {
    /// Le réglage « Claude au travail » : on surveille le dossier des sessions (le système prévient) ; éteint, on n'écoute plus et
    /// l'îlot oublie Claude.
    func activerClaude(_ oui: Bool) {
        if oui {
            guard !claudeSource.actif else { return }
            veilleClaude = VeilleClaude()
            claudeSource.demarrer()
        } else {
            // éteint (ou Verbe lancé réglage éteint) : les fichiers de plus d'un jour sont quand même effacés, une fois par lancement
            if !claudeNettoye { claudeNettoye = true; SourceClaude.nettoyer(claudeSource.dossier) }
            guard claudeSource.actif || moteur.claude != nil else { return }
            claudeSource.arreter()
            veilleClaude = VeilleClaude()
            reveilClaude?.cancel(); reveilClaude = nil
            moteur.claude = nil; moteur.sessionsClaude = []; moteur.claudeAuTravail = 0
            if [.claudeAttend, .claudeTermine].contains(moteur.bandeau?.vue) { moteur.bandeau = nil }
            moteur.donneesChangees()
        }
    }

    /// Des lignes nouvelles : l'état de chaque session, et les annonces (sauf à la relecture du lancement, et sauf si le Terminal est
    /// déjà au premier plan : Hugues regarde déjà).
    func lignesClaude(_ lignes: [LigneClaude], relecture: Bool) {
        var annonce: AnnonceClaude?
        for l in lignes {
            guard let e = EvenementClaude.depuis(ligne: l.texte) else { continue }
            // une session sans app d'origine (claude -p lancé par launchd, cron, un SDK) : personne ne la regarde, l'îlot l'ignore
            guard VeilleClaude.estSuivie(e) else { if e.genre == .fin { claudeSource.effacer(l.session) }; continue }
            let a = veilleClaude.lire(e, session: l.session)
            if e.genre == .fin { claudeSource.effacer(l.session) }
            if !relecture, let a { annonce = a }
        }
        majClaude()
        guard let annonce else { return }
        switch annonce {
        case .attend(let s):
            guard !VeilleClaude.dejaSousLesYeux(app: s.app, premierPlan: appAuPremierPlan()) else { return }
            // « second-cerveau attend ta réponse », les premiers mots de la question (sinon « Claude attend ta réponse »), « Ouvrir »
            moteur.annoncer(bandeau: BandeauIlot(vue: .claudeAttend, jusqua: maintenant().addingTimeInterval(4.5), ligne1: s.projet + " attend ta réponse",
                                                 ligne2: TexteClaude.premiersMots(s.question) ?? "Claude attend ta réponse", claude: s))
        case .termine(let s):
            guard !VeilleClaude.dejaSousLesYeux(app: s.app, premierPlan: appAuPremierPlan()) else { return }
            // « Carte Dictées terminée », « dictee-mac · 42 min · 7 tâches sur 7 », « Voir »
            moteur.annoncer(bandeau: BandeauIlot(vue: .claudeTermine, jusqua: maintenant().addingTimeInterval(3.5), ligne1: TexteClaude.fin(s),
                                                 ligne2: TexteClaude.ligneFin(s, a: maintenant()), claude: s))
        }
    }

    /// La session montrée, et un seul réveil : le moment où elle sera oubliée faute de nouvelles.
    func majClaude() {
        let t = maintenant()
        let s = veilleClaude.principale(a: t)
        let carte = veilleClaude.pourLaCarte(a: t), n = veilleClaude.auTravail(a: t)
        if s != moteur.claude || carte != moteur.sessionsClaude || n != moteur.claudeAuTravail {
            moteur.claude = s; moteur.sessionsClaude = carte; moteur.claudeAuTravail = n
            moteur.donneesChangees()
        }
        reveilClaude?.cancel(); reveilClaude = nil
        guard let quand = veilleClaude.prochainOubli(a: t) else { return }
        let item = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.majClaude() } }
        reveilClaude = item
        DispatchQueue.main.asyncAfter(deadline: .now() + max(1, quand.timeIntervalSince(t) + 0.5), execute: item)
    }

    /// Ramène la fenêtre du Terminal où tourne la session : les fenêtres de l'app sont lues par l'Accessibilité (que Verbe a déjà, pour
    /// la dictée : aucune autorisation de plus ; pas d'AppleScript, qui demanderait à « contrôler le Terminal »), `FenetresClaude.choisir`
    /// prend la bonne (titre de la session, dossier, nom du projet), elle passe devant ; puis l'app est ramenée comme d'un clic sur son
    /// icône du Dock (une app d'arrière-plan comme Verbe ne peut pas toujours en activer une autre directement). Sans Accessibilité, ou
    /// si aucune fenêtre ne ressemble à la session : l'app seule, sur sa dernière fenêtre.
    static func ramener(_ s: SessionClaude?) {
        let id = s?.app ?? "com.apple.Terminal"
        if let s, AXIsProcessTrusted(), let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first {
            let ax = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(ax, 0.3)
            var v: CFTypeRef?
            if AXUIElementCopyAttributeValue(ax, kAXWindowsAttribute as CFString, &v) == .success, let fenetres = v as? [AXUIElement] {
                func texte(_ f: AXUIElement, _ attr: String) -> String? {
                    var r: CFTypeRef?
                    guard AXUIElementCopyAttributeValue(f, attr as CFString, &r) == .success else { return nil }
                    if let t = r as? String { return t }
                    if let u = r as? URL { return u.absoluteString }
                    return nil
                }
                let lues = fenetres.prefix(40).map { FenetresClaude.Fenetre(titre: texte($0, kAXTitleAttribute) ?? "", document: texte($0, kAXDocumentAttribute)) }
                if let i = FenetresClaude.choisir(Array(lues), session: s) {
                    let f = fenetres[i]
                    var mini: CFTypeRef?
                    if AXUIElementCopyAttributeValue(f, kAXMinimizedAttribute as CFString, &mini) == .success, (mini as? Bool) == true {
                        AXUIElementSetAttributeValue(f, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                    }
                    AXUIElementSetAttributeValue(f, kAXMainAttribute as CFString, kCFBooleanTrue)
                    AXUIElementPerformAction(f, kAXRaiseAction as CFString)
                    Log.ecrire("claude : fenêtre de la session ramenée (\(i + 1) sur \(lues.count))")
                } else {
                    Log.ecrire("claude : aucune fenêtre ne ressemble à la session, l'app seule est ramenée")
                }
            }
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config)
    }
}
