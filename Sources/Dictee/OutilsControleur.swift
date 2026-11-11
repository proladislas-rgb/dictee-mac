import AppKit
import ApplicationServices
import ImageIO
import IOKit.pwr_mgt
import DicteeCore

// Ce que les Outils touchent du système (maquette ilot-claude-plus.html, étapes 8 à 14), toujours derrière une fermeture ou un pilote
// injectable : l'essai (`--ilot-essai`) remplace tout, il ne touche jamais la veille, le presse-papiers, Groq, l'Accessibilité ni Notes.
// - Garder éveillé : deux assertions d'IOKit (veille de l'écran et du système), rendues à l'échéance (un seul réveil), à l'arrêt, et
//   toujours à la fermeture de Verbe (le système les rend aussi si le processus meurt) ;
// - Presse-papiers : les cinq dernières copies EN MÉMOIRE seulement (jamais écrites sur le disque). macOS ne prévient pas quand le
//   presse-papiers change : on regarde son compteur (`changeCount`, un entier, rien n'est lu) quand l'îlot s'ouvre et quand une app passe
//   au premier plan, et on ne lit son contenu que s'il a changé. Aucune minuterie. Les copies marquées confidentielles ou passagères
//   (mots de passe, collages d'outils comme celui de Verbe) sont ignorées. Retirer « Presse-papiers » de la page Outils arrête tout ;
// - Reformuler : le même service de texte que la remise au propre des dictées (Groq, la même clé, le même client `GroqClient`) ;
// - Note rapide : ~/Library/Application Support/Dictee/notes.json (0600) ; « Vers Notes » passe par AppleScript (macOS demande une fois
//   « Verbe veut contrôler Notes », au premier clic).

// MARK: - Garder éveillé

/// Garder le Mac éveillé (le vrai : IOKit ; un faux dans l'essai).
@MainActor
protocol PiloteEveil: AnyObject {
    var actif: Bool { get }
    /// Empêche la veille de l'écran et du système ; faux si macOS a refusé.
    func garder(raison: String) -> Bool
    func rendre()
}

/// Les deux assertions d'IOKit : « pas de veille de l'écran » et « pas de veille du système » (comme `caffeinate -di`).
@MainActor
final class EveilSysteme: PiloteEveil {
    private var ecran: IOPMAssertionID = 0
    private var systeme: IOPMAssertionID = 0
    var actif: Bool { ecran != 0 || systeme != 0 }

    func garder(raison: String) -> Bool {
        if actif { return true }
        let niveau = IOPMAssertionLevel(kIOPMAssertionLevelOn)
        let r1 = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString, niveau, raison as CFString, &ecran)
        let r2 = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString, niveau, raison as CFString, &systeme)
        if r1 != kIOReturnSuccess { ecran = 0 }
        if r2 != kIOReturnSuccess { systeme = 0 }
        if r1 != kIOReturnSuccess || r2 != kIOReturnSuccess { Log.ecrire("garder éveillé : IOKit a refusé (\(r1), \(r2))") }
        return r1 == kIOReturnSuccess
    }
    func rendre() {
        if ecran != 0 { IOPMAssertionRelease(ecran); ecran = 0 }
        if systeme != 0 { IOPMAssertionRelease(systeme); systeme = 0 }
    }
}

// MARK: - Presse-papiers

/// Ce qu'une copie contient, gardé en mémoire pour la recopier.
struct ContenuCopie {
    var texte: String?
    var image: (donnees: Data, type: NSPasteboard.PasteboardType)?
    var fichiers: [URL] = []
}

/// Le presse-papiers (le vrai : NSPasteboard.general ; un faux dans l'essai).
@MainActor
protocol PilotePressePapiers: AnyObject {
    /// Le compteur de changements (lire ce nombre ne lit rien du contenu).
    var compteur: Int { get }
    /// Les types de l'élément du dessus, et ce qu'on garde : des fichiers, sinon du texte, sinon une image.
    func lire() -> (types: [String], contenu: ContenuCopie)
    func ecrire(_ c: ContenuCopie)
}

@MainActor
final class PressePapiersSysteme: PilotePressePapiers {
    private let presse = NSPasteboard.general
    var compteur: Int { presse.changeCount }

    func lire() -> (types: [String], contenu: ContenuCopie) {
        let types = (presse.types ?? []).map(\.rawValue)
        var c = ContenuCopie()
        // les marques « ne pas garder » d'abord : on ne lit rien d'autre
        guard !LecturePressePapiers.ignorer(types: types) else { return (types, c) }
        if let urls = presse.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            c.fichiers = urls
        } else if let t = presse.string(forType: .string), !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            c.texte = t
        } else {
            for type in [NSPasteboard.PasteboardType.png, .tiff] {
                if let d = presse.data(forType: type) { c.image = (d, type); break }
            }
        }
        return (types, c)
    }
    func ecrire(_ c: ContenuCopie) {
        presse.clearContents()
        if !c.fichiers.isEmpty { presse.writeObjects(c.fichiers as [NSURL]) }
        else if let t = c.texte { presse.setString(t, forType: .string) }
        else if let i = c.image { presse.setData(i.donnees, forType: i.type) }
    }
}

// MARK: - Note rapide

/// Les notes rapides : ~/Library/Application Support/Dictee/notes.json (0600, jamais dans git, jamais envoyées nulle part).
struct NotesStore {
    var url: URL
    static var urlParDefaut: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Dictee", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("notes.json")
    }
    func lire() -> ListeNotes {
        guard let d = try? Data(contentsOf: url) else { return ListeNotes() }
        if let l = ListeNotes.depuis(d) { return l }
        Log.ecrire("notes : fichier illisible, l'ancien est gardé en .abime")
        try? FileManager.default.moveItem(at: url, to: url.appendingPathExtension("abime"))
        return ListeNotes()
    }
    func ecrire(_ l: ListeNotes) {
        guard let d = l.donnees() else { return }
        try? d.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

extension IlotControleur {
    // MARK: Outils : mise en route

    /// Au lancement : la page Outils telle qu'elle a été rangée, les notes, et le regard sur le presse-papiers quand une app passe au
    /// premier plan (une notification de macOS, aucune minuterie).
    func demarrerLesOutils() {
        moteur.dispositionOutils = DispositionCentre(identifiants: reglagesCentre.dispositionOutils(), page: .outils)
        moteur.notes = listeNotes.notes
        observateurApps = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.verifierPressePapiers() }
        }
    }
    /// À la fermeture de Verbe : le Mac n'est plus gardé éveillé, l'historique du presse-papiers est oublié.
    func arreterLesOutils() {
        if let o = observateurApps { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        observateurApps = nil
        arreterEveil(journal: "arrêt de Verbe")
        historiqueCopies.vider(); contenusCopies = [:]
    }

    /// Les actions des Outils.
    func agirOutils(_ a: ActionIlot) {
        switch a {
        case .eveil(let d): if let d { garderEveille(d) } else { arreterEveil(journal: "éteint depuis l'îlot") }
        case .copieRecopier(let id): recopier(id, coller: false)
        case .copieColler(let id): recopier(id, coller: true)
        case .copiesEffacer:
            historiqueCopies.vider(); contenusCopies = [:]
            moteur.copies = []; moteur.copieFaite = nil
            Log.ecrire("presse-papiers : historique effacé")
            moteur.donneesChangees()
        case .reformulationSource(let s): choisirSource(s)
        case .reformuler(let s): reformuler(s)
        case .reformulationRemplacer: remplacerReformulation()
        case .reformulationCopier:
            guard let t = moteur.reformulation.resultat else { return }
            pressePapiers.ecrire(ContenuCopie(texte: t))
            moteur.reformulation.remarque = "Copié"
        case .noteVersNotes(let id): envoyerVersNotes(id)
        case .noteSupprimer(let id):
            guard listeNotes.supprimer(id) else { return }
            notesStore.ecrire(listeNotes)
            moteur.notes = listeNotes.notes
            if moteur.noteNeuve == id { moteur.noteNeuve = nil }
            moteur.survolNote = nil
            moteur.donneesChangees()
        default: break
        }
    }

    // MARK: Garder éveillé

    func garderEveille(_ d: DureeEveil) {
        let t = maintenant()
        guard eveilPilote.actif || eveilPilote.garder(raison: "Verbe : garder le Mac éveillé (\(d.titre))") else {
            moteur.eveil = nil; moteur.donneesChangees(); return
        }
        let e = EveilIlot(duree: d, depuis: t)
        moteur.eveil = e
        moteur.panneauEveil = true
        Log.ecrire("garder éveillé : \(d.titre)")
        // un seul réveil, à l'échéance, sur l'horloge murale (le Mac peut dormir capot fermé : au réveil, l'échéance passée est vue)
        reveilEveil?.cancel(); reveilEveil = nil
        if let fin = e.echeance {
            let item = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.verifierEcheanceEveil() } }
            reveilEveil = item
            DispatchQueue.main.asyncAfter(wallDeadline: .now() + max(0, fin.timeIntervalSince(t)), execute: item)
        }
        moteur.donneesChangees()
    }
    /// Le réveil de l'échéance (et l'essai, qui avance l'heure) : la veille redevient normale si l'heure est passée.
    func verifierEcheanceEveil() {
        guard let e = moteur.eveil else { return }
        if e.fini(a: maintenant()) { arreterEveil(journal: "échéance") }
        else if let fin = e.echeance {
            // réveillé trop tôt (horloge changée) : on reprogramme, toujours un seul réveil
            let item = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.verifierEcheanceEveil() } }
            reveilEveil = item
            DispatchQueue.main.asyncAfter(wallDeadline: .now() + max(1, fin.timeIntervalSince(maintenant())), execute: item)
        }
    }
    func arreterEveil(journal: String) {
        reveilEveil?.cancel(); reveilEveil = nil
        let etait = moteur.eveil != nil || eveilPilote.actif
        eveilPilote.rendre()
        moteur.eveil = nil
        if etait { Log.ecrire("garder éveillé : rendu (\(journal))"); moteur.donneesChangees() }
    }

    // MARK: Presse-papiers

    /// Le presse-papiers a-t-il changé ? On lit son compteur ; s'il a bougé, son contenu (une fois). Seulement si l'outil est sur la page
    /// Outils. Appelé quand l'îlot s'ouvre et quand une app passe au premier plan.
    func verifierPressePapiers() {
        guard moteur.dispositionOutils.elements.contains(.pressePapiers) else {
            if !historiqueCopies.elements.isEmpty { historiqueCopies.vider(); contenusCopies = [:]; moteur.copies = []; moteur.donneesChangees() }
            compteurPressePapiers = nil
            return
        }
        let n = pressePapiers.compteur
        guard n != compteurPressePapiers else { return }
        compteurPressePapiers = n
        let (types, c) = pressePapiers.lire()
        guard !LecturePressePapiers.ignorer(types: types) else { return }
        let t = maintenant()
        let element: ElementCopie
        if !c.fichiers.isEmpty {
            element = ElementCopie(genre: .fichiers(c.fichiers.map(\.lastPathComponent)), date: t, empreinte: "f:" + c.fichiers.map(\.path).joined(separator: "\n"))
        } else if let s = c.texte {
            guard s.count <= LecturePressePapiers.texteMax else { return }
            element = ElementCopie(genre: .texte(s), date: t, empreinte: "t:" + s)
        } else if let i = c.image {
            guard i.donnees.count <= LecturePressePapiers.imageMax, let dim = Self.dimensions(i.donnees) else { return }
            var h = Hasher(); h.combine(i.donnees)
            element = ElementCopie(genre: .image(largeur: dim.0, hauteur: dim.1), date: t, empreinte: "i:\(i.donnees.count):\(h.finalize())")
        } else { return }
        if historiqueCopies.ajouter(element) {
            if let garde = historiqueCopies.elements.first, garde.id == element.id { contenusCopies[element.id] = c }
            // ce qui est sorti de la liste est oublié (images comprises)
            let ids = Set(historiqueCopies.elements.map(\.id))
            contenusCopies = contenusCopies.filter { ids.contains($0.key) }
            moteur.copies = historiqueCopies.elements.map { vueCopie($0) }
            // la carte suit sa liste (une ligne de plus, c'est 40 pt de plus) : sans ce recalcul, les nouvelles lignes restaient sous la forme
            moteur.donneesChangees()
        }
    }

    /// Ce que l'îlot montre d'une copie (la miniature et l'icône sont lues ici, une fois).
    private func vueCopie(_ e: ElementCopie) -> CopieVue {
        if let deja = moteur.copies.first(where: { $0.id == e.id }) { var d = deja; d.element = e; return d }
        let c = contenusCopies[e.id]
        switch e.genre {
        case .texte(let s):
            let commande = LecturePressePapiers.estCommande(s)
            return CopieVue(element: e, titre: LecturePressePapiers.apercu(s), detail: nil, style: commande ? .commande : .texte, icone: nil)
        case .image(let l, let h):
            return CopieVue(element: e, titre: "Image", detail: LecturePressePapiers.dimensions(l, h), style: .nom, icone: c?.image.flatMap { Self.miniature($0.donnees) })
        case .fichiers(let noms):
            let urls = c?.fichiers ?? []
            let titre = noms.count == 1 ? (noms.first ?? "") : "\(noms.first ?? "") et \(noms.count - 1) autre\(noms.count > 2 ? "s" : "")"
            var detail: String?
            if urls.count == 1, let t = (try? urls[0].resourceValues(forKeys: [.fileSizeKey]))?.fileSize { detail = LecturePressePapiers.taille(Int64(t)) }
            else if urls.count > 1 { detail = "\(urls.count) fichiers" }
            return CopieVue(element: e, titre: titre, detail: detail, style: .nom, icone: urls.first.map { NSWorkspace.shared.icon(forFile: $0.path) })
        }
    }

    /// Un clic sur une ligne : la copie revient dans le presse-papiers (« Copié ») ; « Coller » : elle y revient et part dans l'app
    /// d'où l'on vient (⌘V), l'îlot se range.
    private func recopier(_ id: UUID, coller: Bool) {
        guard let c = contenusCopies[id] else { return }
        pressePapiers.ecrire(c)
        // c'est nous qui venons d'écrire : pas une nouvelle copie (la ligne reste à sa place)
        compteurPressePapiers = pressePapiers.compteur
        moteur.copieFaite = (id, coller ? "Collé" : "Copié")
        finCopieFaite?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.moteur.copieFaite?.id == id { self.moteur.copieFaite = nil }
                if coller {
                    self.moteur.fermer()
                    if !self.surCommandeV() { Log.ecrire("presse-papiers : recopié, collage impossible (accessibilité)") }
                }
            }
        }
        finCopieFaite = item
        DispatchQueue.main.asyncAfter(deadline: .now() + (coller ? 0.45 : 1.3), execute: item)
    }

    static func dimensions(_ d: Data) -> (Int, Int)? {
        guard let s = CGImageSourceCreateWithData(d as CFData, nil), let p = CGImageSourceCopyPropertiesAtIndex(s, 0, nil) as? [CFString: Any],
              let l = p[kCGImagePropertyPixelWidth] as? Int, let h = p[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (l, h)
    }
    /// Une miniature de 120 px au plus (la ligne fait 40 × 28 pt) : l'image elle-même n'est jamais décodée en entier pour l'îlot.
    static func miniature(_ d: Data) -> NSImage? {
        guard let s = CGImageSourceCreateWithData(d as CFData, nil),
              let i = CGImageSourceCreateThumbnailAtIndex(s, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 120,
                                                                 kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
        return NSImage(cgImage: i, size: NSSize(width: i.width, height: i.height))
    }

    // MARK: Reformuler

    /// La carte s'ouvre (ou on change de source) : le texte de départ, relu (la dernière dictée, ou ce qui est choisi dans l'app au
    /// premier plan, lu par l'Accessibilité déjà accordée).
    func relireSourceReformulation() {
        var r = moteur.reformulation
        let avant = r.texte
        switch r.source {
        case .derniereDictee:
            let d = lireDerniereDictee()
            r.texte = d.map { $0.texte.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
            r.etiquette = ReformulationIlot.etiquette(.derniereDictee, app: d == nil ? nil : lireAppDerniereDictee(), date: d?.date)
        case .selection:
            let s = lireSelection()
            r.texte = s.map { $0.texte.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
            r.etiquette = ReformulationIlot.etiquette(.selection, app: s?.app, date: nil)
        }
        // un autre texte : la réécriture d'avant ne vaut plus
        if r.texte != avant { r.phase = .attente; r.style = nil; r.remarque = nil; jetonReformulation += 1 }
        moteur.reformulation = r
        moteur.donneesChangees()
    }
    private func choisirSource(_ s: SourceReformulation) {
        guard moteur.reformulation.source != s else { relireSourceReformulation(); return }
        moteur.reformulation.source = s
        relireSourceReformulation()
    }
    private func reformuler(_ s: StyleReformulation) {
        guard let texte = moteur.reformulation.texte, moteur.reformulation.phase != .calcul else { return }
        jetonReformulation += 1
        let jeton = jetonReformulation
        moteur.reformulation.style = s
        moteur.reformulation.phase = .calcul
        moteur.reformulation.remarque = nil
        moteur.donneesChangees()
        Log.ecrire("reformuler : \(s.titre.lowercased()) (\(texte.count) caractères)")
        let f = reformulerTexte
        Task { @MainActor [weak self] in
            let phase: EtatReformulation.Phase
            do {
                let sortie = try await f(texte, s)
                if let t = ReformulationIlot.nettoyer(sortie, entree: texte) { phase = .fait(t) }
                else { phase = .echec("Réponse inutilisable : réessaie") }
            } catch GroqErreur.pasDeCle {
                phase = .echec("Pas de clé Groq : voir Réglages")
            } catch {
                Log.ecrire("reformuler : échec (\(error))")
                phase = .echec("Pas de réponse : réessaie")
            }
            guard let self, self.jetonReformulation == jeton else { return }
            self.moteur.reformulation.phase = phase
            self.moteur.donneesChangees()
        }
    }
    /// « Remplacer » : le texte choisi est encore sélectionné dans l'app (l'îlot ne prend jamais le focus) : on colle par-dessus, comme
    /// le collage des dictées. La dernière dictée : on la sélectionne d'abord dans le champ de l'app (Accessibilité), on vérifie que
    /// c'est bien elle, puis on colle ; si ce n'est pas possible, le texte réécrit est copié et la carte le dit.
    private func remplacerReformulation() {
        let r = moteur.reformulation
        guard let t = r.resultat, let ancien = r.texte else { return }
        if r.source == .derniereDictee, !selectionnerDansLApp(ancien) {
            pressePapiers.ecrire(ContenuCopie(texte: t))
            moteur.reformulation.remarque = "Copié : colle-le à la place"
            Log.ecrire("reformuler : dernière dictée introuvable dans le champ, texte copié")
            return
        }
        moteur.fermer()
        surColler(t)
        Log.ecrire("reformuler : remplacé (\(r.source == .selection ? "texte choisi" : "dernière dictée"))")
    }

    // MARK: Note rapide

    /// Une dictée faite pendant que la carte Note rapide était ouverte : elle devient une note (pas collée dans l'app), en haut de la
    /// liste ; l'îlot se rouvre dessus une fois l'encoche de la dictée rangée.
    func ajouterNote(_ texte: String) -> Bool {
        guard let n = listeNotes.ajouter(texte, date: maintenant()) else { return false }
        notesStore.ecrire(listeNotes)
        moteur.notes = listeNotes.notes
        moteur.noteNeuve = n.id
        Log.ecrire("note rapide : ajoutée (\(n.texte.count) caractères)")
        if moteur.cache { noteAOuvrir = true } else { moteur.ouvrirOutil(.outilNote) }
        return true
    }
    private func envoyerVersNotes(_ id: UUID) {
        guard let n = listeNotes.note(id), moteur.envoisNotes[id] != .enCours else { return }
        moteur.envoisNotes[id] = .enCours
        envoyerNoteVersNotes(ListeNotes.html(n.texte)) { [weak self] ok in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.moteur.envoisNotes[id] = ok ? .fait : .refuse
                if ok { self.listeNotes.marquerVersNotes(id); self.notesStore.ecrire(self.listeNotes); self.moteur.notes = self.listeNotes.notes }
                Log.ecrire("note rapide : vers Notes \(ok ? "faite" : "refusée ou impossible")")
                self.moteur.donneesChangees()
            }
        }
    }

    // MARK: les vrais (le système)

    /// Ce qui est choisi dans l'app au premier plan, lu par l'Accessibilité (déjà accordée pour la dictée) : rien n'est demandé.
    static func lireSelectionSysteme() -> (texte: String, app: String?)? {
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier != Bundle.main.bundleIdentifier else { return nil }
        let a = AXUIElementCreateApplication(app.processIdentifier)
        var focus: CFTypeRef?
        guard AXUIElementCopyAttributeValue(a, kAXFocusedUIElementAttribute as CFString, &focus) == .success, let f = focus else { return nil }
        var sel: CFTypeRef?
        guard AXUIElementCopyAttributeValue(f as! AXUIElement, kAXSelectedTextAttribute as CFString, &sel) == .success, let t = sel as? String,
              !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return (t, app.localizedName)
    }

    /// Sélectionne, dans le champ focalisé de l'app au premier plan, la dernière occurrence de `texte` (la dernière dictée), puis vérifie
    /// en relisant la sélection. Faux si le champ ne se laisse pas lire ou sélectionner (apps web, champ changé…).
    static func selectionnerSysteme(_ texte: String) -> Bool {
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier != Bundle.main.bundleIdentifier else { return false }
        let a = AXUIElementCreateApplication(app.processIdentifier)
        var focus: CFTypeRef?
        guard AXUIElementCopyAttributeValue(a, kAXFocusedUIElementAttribute as CFString, &focus) == .success, let f = focus else { return false }
        let champ = f as! AXUIElement
        var valeur: CFTypeRef?
        guard AXUIElementCopyAttributeValue(champ, kAXValueAttribute as CFString, &valeur) == .success, let tout = valeur as? String else { return false }
        let r = (tout as NSString).range(of: texte, options: .backwards)
        guard r.location != NSNotFound else { return false }
        var plage = CFRange(location: r.location, length: r.length)
        guard let v = AXValueCreate(.cfRange, &plage), AXUIElementSetAttributeValue(champ, kAXSelectedTextRangeAttribute as CFString, v) == .success else { return false }
        var relu: CFTypeRef?
        return AXUIElementCopyAttributeValue(champ, kAXSelectedTextAttribute as CFString, &relu) == .success && (relu as? String) == texte
    }

    /// Crée la note dans l'app Notes (AppleScript, sur une file à part : Notes peut mettre quelques secondes à s'ouvrir). Le texte est déjà
    /// du HTML échappé ; seules les barres obliques inverses restent à protéger pour la chaîne AppleScript.
    nonisolated static func versNotesSysteme(_ html: String, fini: @escaping @Sendable (Bool) -> Void) {
        let corps = html.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let source = "tell application \"Notes\" to make new note with properties {body:\"\(corps)\"}"
        DispatchQueue.global(qos: .userInitiated).async {
            var erreur: NSDictionary?
            let ok = NSAppleScript(source: source)?.executeAndReturnError(&erreur) != nil
            if let n = erreur?[NSAppleScript.errorNumber] as? Int { Log.ecrire("note rapide : AppleScript a répondu \(n)\(n == -1743 ? " (non autorisé : Réglages Système › Confidentialité › Automatisation)" : "")") }
            DispatchQueue.main.async { fini(ok) }
        }
    }
}
