import AppKit
import DicteeCore

// « Téléchargé » (maquette design/maquettes/ilot-apple.html, cinq idées de plus) : un fichier arrive dans Téléchargements (AirDrop y
// dépose aussi), l'îlot l'annonce 4 s avec son icône, son nom, sa taille et « Ouvrir ».
// Aucun sondage : le noyau prévient quand une entrée du dossier change (DispatchSource sur le dossier) ; on relit alors ses noms, et la
// taille des seuls nouveaux venus. Tant qu'un fichier se stabilise, UNE relecture est programmée une seconde plus tard ; un nouveau
// fichier encore vide (curl, wget, AirDrop l'écrivent sur place, sans que le dossier ne prévienne) est relu quelques fois, de plus en
// plus espacé, au plus une demi-heure ; au repos, rien.

/// Le dossier Téléchargements, surveillé sur une file à part : macOS peut demander l'accès au dossier à la première ouverture et
/// attendre la réponse (jamais sur le fil principal), et un dossier de mille fichiers se relit sans gêner l'îlot.
@MainActor
final class SourceTelechargements {
    /// Des fichiers finis viennent d'arriver.
    var surArrivee: ([FichierTelecharge]) -> Void = { _ in }
    /// L'accès au dossier a été refusé (EPERM / EACCES : refus dans la demande de macOS, ou dans Réglages Système). Un dossier absent
    /// ou illisible sur le moment n'est pas un refus : la surveillance s'arrête, le réglage reste, elle reprendra au prochain lancement.
    var surRefus: () -> Void = {}
    /// Le dossier est ouvert et lu : l'accès est accordé (la question de macOS, s'il y en avait une, a eu sa réponse).
    var surPret: () -> Void = {}
    /// La surveillance n'a pas démarré sans que ce soit un refus (dossier absent ou illisible sur le moment) : plus rien à attendre.
    var surArret: () -> Void = {}
    /// Le dossier surveillé (les essais en donnent un temporaire : jamais le vrai, qui demanderait une autorisation).
    var dossier: URL = SourceTelechargements.dossierParDefaut
    private var travail: SurveillanceDossier?

    var actif: Bool { travail != nil }

    static var dossierParDefaut: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
    }

    func demarrer() {
        guard travail == nil else { return }
        let t = SurveillanceDossier(dossier: dossier)
        travail = t
        // ce qui arrive après un arrêt (ou d'une ancienne surveillance) est ignoré
        t.surArrivee = { [weak self, weak t] l in
            DispatchQueue.main.async { MainActor.assumeIsolated { guard let self, let t, self.travail === t else { return }; self.surArrivee(l) } }
        }
        t.surPret = { [weak self, weak t] in
            DispatchQueue.main.async { MainActor.assumeIsolated { guard let self, let t, self.travail === t else { return }; self.surPret() } }
        }
        t.surEchec = { [weak self, weak t] refus in
            DispatchQueue.main.async { MainActor.assumeIsolated { guard let self, let t, self.travail === t else { return }; self.arreter(); if refus { self.surRefus() } else { self.surArret() } } }
        }
        t.demarrer()
    }

    func arreter() {
        travail?.arreter()
        travail = nil
    }
}

/// Le travail sur la file : ouvrir le dossier, écouter ses changements, relire. Tout son état ne vit que sur `file`.
private final class SurveillanceDossier: @unchecked Sendable {
    let dossier: URL
    private let file = DispatchQueue(label: "verbe.ilot.telechargements", qos: .utility)
    var surArrivee: ([FichierTelecharge]) -> Void = { _ in }
    /// L'ouverture a échoué ; vrai : c'est un refus d'accès.
    var surEchec: (_ refus: Bool) -> Void = { _ in }
    var surPret: () -> Void = {}
    private var source: DispatchSourceFileSystemObject?
    private var veille: VeilleTelechargements?
    private var relecture: DispatchWorkItem?
    private var arrete = false

    init(dossier: URL) { self.dossier = dossier }

    func demarrer() { file.async { self.ouvrir() } }

    func arreter() {
        file.async {
            self.arrete = true
            self.relecture?.cancel(); self.relecture = nil
            self.source?.cancel(); self.source = nil
            self.veille = nil
        }
    }

    private func ouvrir() {
        guard !arrete, source == nil else { return }
        let fd = open(dossier.path, O_EVTONLY)
        guard fd >= 0 else {
            let e = errno
            Log.ecrire("téléchargements : dossier inaccessible (errno \(e)), surveillance non démarrée")
            surEchec(Self.estUnRefus(e)); return
        }
        let noms: [String]
        do { noms = try lireNoms() } catch {
            close(fd)
            let e = Self.codePosix(de: error)
            Log.ecrire("téléchargements : dossier illisible (errno \(e.map(String.init) ?? "?")), surveillance non démarrée")
            surEchec(e.map(Self.estUnRefus) ?? false); return
        }
        // ce qui est déjà là au lancement n'est jamais annoncé
        veille = VeilleTelechargements(existants: noms.compactMap(mesurer))
        let s = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: file)
        s.setEventHandler { [weak self] in self?.relire() }
        s.setCancelHandler { close(fd) }
        source = s
        s.resume()
        Log.ecrire("téléchargements : surveillance du dossier (\(noms.count) éléments déjà là)")
        surPret()
    }

    private func relire() {
        guard !arrete, var v = veille, let noms = try? lireNoms() else { return }
        let prets = v.lire(noms: noms, a: Date(), mesure: mesurer)
        veille = v
        programmer(v.prochaineRelecture)
        guard !prets.isEmpty else { return }
        surArrivee(prets.map { e in
            let url = dossier.appendingPathComponent(e.nom, isDirectory: e.dossier)
            return FichierTelecharge(url: url, taille: e.dossier ? nil : e.taille, airdrop: FichierTelecharge.estAirDrop(quarantaine: Self.quarantaine(url)))
        })
    }

    /// Une seule relecture en attente, au moment où le premier fichier en cours aura été stable une seconde.
    private func programmer(_ quand: Date?) {
        relecture?.cancel(); relecture = nil
        guard let quand else { return }
        let item = DispatchWorkItem { [weak self] in self?.relire() }
        relecture = item
        file.asyncAfter(deadline: .now() + max(0.05, quand.timeIntervalSinceNow), execute: item)
    }

    private func lireNoms() throws -> [String] { try FileManager.default.contentsOfDirectory(atPath: dossier.path) }

    /// Un vrai refus d'accès (la réponse de macOS, ou Réglages Système), pas un dossier absent ou un incident passager.
    static func estUnRefus(_ e: Int32) -> Bool { e == EPERM || e == EACCES }
    /// Le code POSIX derrière une erreur de FileManager (« Operation not permitted » = EPERM).
    static func codePosix(de erreur: Error) -> Int32? {
        let n = erreur as NSError
        if n.domain == NSPOSIXErrorDomain { return Int32(n.code) }
        if let u = n.userInfo[NSUnderlyingErrorKey] as? NSError, u.domain == NSPOSIXErrorDomain { return Int32(u.code) }
        if n.domain == NSCocoaErrorDomain, n.code == NSFileReadNoPermissionError { return EACCES }
        return nil
    }

    private func mesurer(_ nom: String) -> EntreeDossier? {
        guard let a = try? FileManager.default.attributesOfItem(atPath: dossier.appendingPathComponent(nom).path) else { return nil }
        let dossier = (a[.type] as? FileAttributeType) == .typeDirectory
        // un paquet (.app, .pages…) se lit comme un fichier dans le Finder, mais sa taille n'est pas celle du dossier : on suit sa date
        return EntreeDossier(nom: nom, taille: dossier ? 0 : ((a[.size] as? NSNumber)?.int64Value ?? 0),
                             modification: a[.modificationDate] as? Date, dossier: dossier)
    }

    /// L'attribut de quarantaine (« 0081;6731f2a0;sharingd;… ») : qui a déposé le fichier.
    static func quarantaine(_ url: URL) -> String? {
        let nom = "com.apple.quarantine"
        let n = getxattr(url.path, nom, nil, 0, 0, 0)
        guard n > 0 else { return nil }
        var tampon = [UInt8](repeating: 0, count: n)
        guard getxattr(url.path, nom, &tampon, n, 0, 0) == n else { return nil }
        return String(decoding: tampon, as: UTF8.self)
    }
}

extension IlotControleur {
    /// Les icônes du Finder des fichiers à montrer (deux au plus : celle du fichier, ou une pile pour une rafale).
    static func icones(_ fichiers: [FichierTelecharge]) -> [NSImage] {
        fichiers.suffix(2).reversed().map { NSWorkspace.shared.icon(forFile: $0.url.path) }
    }
}
