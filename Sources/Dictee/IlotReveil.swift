import AppKit
import IOKit.pwr_mgt
import DicteeCore

// Le réveil de l'îlot (maquette design/maquettes/ilot-bibliotheque.html, étapes 7 à 9) : réglé d'un clic dans la case Minuteur du Centre
// (onglet Réveil) ou à la voix (« réveille-moi à 9 h », même l'îlot fermé), gardé dans un fichier, il sonne comme le minuteur fini.
//
// La limite, écrite aussi dans la note du réglage : si le Mac DORT à l'heure du réveil (capot fermé, veille), Verbe ne peut pas le
// réveiller. Programmer un réveil du Mac (IOPMSchedulePowerEvent, `pmset schedule`) demande les droits d'administrateur (« Must be called
// as root ») : Verbe ne le fait pas. Le réveil sonne alors dès que le Mac se réveille, s'il n'a pas plus de 2 h de retard. Écran éteint
// mais Mac allumé (le cas de la maquette), il sonne à l'heure et rallume l'écran.

/// Le réveil gardé : ~/Library/Application Support/Dictee/reveil.json (0600, jamais dans git, jamais envoyé). Pas de réveil : pas de fichier.
typealias ReveilStore = MagasinJSON<ReveilIlot>
extension MagasinJSON where Valeur == ReveilIlot {
    init(url: URL) { self.init(url: url, nom: "réveil", siIllisible: .oublier, journal: { Log.ecrire($0) }) }
    static var urlParDefaut: URL { DossierVerbe.url("reveil.json") }
    /// Pas de réveil : pas de fichier.
    func ecrire(_ r: ReveilIlot?) {
        if let r { let _: Bool = ecrire(r) } else { effacer() }
    }
}

extension IlotControleur {
    /// Au lancement : le réveil gardé reprend ; passé pendant que Verbe était fermé (ou le Mac éteint), il sonne tout de suite s'il a moins
    /// de 2 h de retard, sinon il est oublié. Le réveil du Mac (sortie de veille) relit l'heure : l'échéance a pu passer pendant la veille.
    func demarrerLeReveil() {
        if observateurReveilMac == nil {
            observateurReveilMac = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.verifierLeReveil() }
            }
        }
        reveil = reveilStore.lire()
        moteur.reveil = reveil
        if let r = reveil { Log.ecrire("réveil : relu au lancement (\(r.libelle()))") }
        moteur.donneesChangees()
        verifierLeReveil()
    }

    /// Règle le réveil à la prochaine `heure:minute`. À la voix : le bandeau « Réveil réglé · 9:00 » (rien n'a été collé), avec « Annuler ».
    /// D'un clic dans le Centre : le Centre reste ouvert, la case montre l'heure choisie (ambre) et « demain ». `texteDicte` : la phrase
    /// dictée l'îlot fermé, gardée dans le bandeau (jamais dans le fichier) pour que « Annuler » la recolle.
    func reglerLeReveil(heure: Int, minute: Int, aLaVoix: Bool, texteDicte: String? = nil) {
        if !reglagesCentre.minuteurActif() {
            // le minuteur éteint dans les réglages : le clic l'allume (comme « 5 », « 10 », « 25 »), sinon la case ne ferait rien
            reglagesCentre.allumerMinuteur()
            Log.ecrire("minuteur : allumé depuis le Centre (réveil)")
            NotificationCenter.default.post(name: .verbeIlotReglagesRelus, object: nil)
        }
        let t = maintenant()
        let r = ReveilIlot(heure: heure, minute: minute, apres: t)
        reveil = r
        reveilStore.ecrire(r)
        moteur.reveil = r
        moteur.reveilAutre = nil
        Log.ecrire("réveil : réglé à \(r.libelle()) (\(aLaVoix ? "à la voix" : "depuis le Centre"))")
        if aLaVoix {
            var b = BandeauIlot(vue: .reveilRegle, jusqua: t.addingTimeInterval(3), ligne1: "Réveil réglé \u{00B7} " + r.libelle(),
                                ligne2: r.ligneReglee(maintenant: t))
            b.texteDicte = texteDicte
            moteur.annoncer(bandeau: b)
        } else {
            moteur.donneesChangees()
        }
        programmerLeReveil()
    }

    func annulerLeReveil() {
        guard reveil != nil else { return }
        reveil = nil
        reveilStore.ecrire(nil)
        moteur.reveil = nil
        moteur.reveilAutre = nil
        echeanceReveil?.cancel(); echeanceReveil = nil
        Log.ecrire("réveil : annulé")
        moteur.donneesChangees()
    }

    func agirReveil(_ a: ActionIlot) {
        switch a {
        case .reveilRegler(let h, let mn, let basculer):
            // un clic sur la pastille de l'heure déjà choisie l'annule (maquette : la pastille ambre se rallume en gris) ; « OK » d'« Autre… »
            // (basculer: false) règle toujours, même sur l'heure déjà réglée
            if basculer, let r = reveil, !r.repousse, r.heure == h, r.minute == mn { annulerLeReveil() } else { reglerLeReveil(heure: h, minute: mn, aLaVoix: false) }
        case .reveilAnnuler:
            annulerLeReveil()
            if moteur.bandeau?.vue == .reveilRegle {
                // dicté l'îlot fermé : la phrase n'était peut-être pas pour Verbe (« réveille-moi à 7 h », écrit à quelqu'un) ; elle est recollée
                let texte = moteur.bandeau?.texteDicte
                moteur.quitterBandeau()
                if let texte, !texte.isEmpty { surColler(texte); Log.ecrire("réveil : annulé, la dictée est recollée") }
            }
        case .reveilEncore:
            // « Encore 10 min » : il sonnera de nouveau dans 10 minutes ; replié, l'aile montre l'heure de cette nouvelle sonnerie
            let t = maintenant()
            var r = reveil ?? moteur.dernierReveil ?? ReveilIlot(heure: 0, minute: 0, apres: t)
            r.repousser(a: t)
            reveil = r
            reveilStore.ecrire(r)
            moteur.reveil = r
            Log.ecrire("réveil : encore 10 min")
            moteur.quitterAlerte()
            programmerLeReveil()
        case .reveilOK:
            moteur.quitterAlerte()
        default: break
        }
    }

    /// Une seule échéance, sur l'horloge MURALE (`wallDeadline`) : le temps passé en veille compte (l'horloge du système, elle, s'arrête
    /// pendant la veille et le réveil sonnerait en retard d'autant).
    func programmerLeReveil() {
        echeanceReveil?.cancel(); echeanceReveil = nil
        guard let r = reveil else { return }
        let item = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.verifierLeReveil() } }
        echeanceReveil = item
        DispatchQueue.main.asyncAfter(wallDeadline: .now() + max(0.05, r.sonnerie.timeIntervalSince(maintenant())), execute: item)
    }

    /// « Minuteur et réveil » éteint dans Réglages › Îlot : le réveil réglé est annulé (l'aile se vide, rien ne sonnera). Relu aussi au
    /// lancement et à l'échéance (`verifierLeReveil`).
    func appliquerLeReglageDuReveil() {
        if !reglagesCentre.minuteurActif(), reveil != nil {
            Log.ecrire("réveil : « Minuteur et réveil » éteint, le réveil est annulé")
            annulerLeReveil()
        }
    }

    /// Il est l'heure ? Alors il sonne (une fois) ; trop en retard, il est oublié ; sinon on attend son échéance. Le réglage éteint : il
    /// ne sonne jamais (annulé).
    func verifierLeReveil() {
        guard reveil != nil else { return }
        appliquerLeReglageDuReveil()
        guard let r = reveil else { return }
        let t = maintenant()
        guard r.du(a: t) else { programmerLeReveil(); return }
        reveil = nil
        reveilStore.ecrire(nil)
        moteur.reveil = nil
        echeanceReveil?.cancel(); echeanceReveil = nil
        if r.perime(a: t) {
            Log.ecrire("réveil : \(r.libelle()) passé depuis plus de 2 h (Mac endormi ou Voxile fermé), oublié")
            moteur.donneesChangees()
            return
        }
        Log.ecrire("réveil : sonne (\(r.libelle()))")
        // l'écran éteint (Mac allumé) se rallume, comme sur la maquette ; jamais pendant un essai (injectable)
        allumerEcran()
        moteur.fermer()
        moteur.annoncer(alerte: AlerteIlot(vue: .reveilFini, jusqua: nil, libelle: r.libelle()))
        moteur.donneesChangees()
    }

    /// Rallume l'écran (une activité déclarée, comme un geste de l'utilisateur) : aucun droit particulier. Le Mac, lui, doit être éveillé.
    static func declarerActivite() {
        var id: IOPMAssertionID = 0
        let r = IOPMAssertionDeclareUserActivity("Voxile : réveil" as CFString, kIOPMUserActiveLocal, &id)
        if r != kIOReturnSuccess { Log.ecrire("réveil : écran non rallumé (\(r))") }
    }
}
