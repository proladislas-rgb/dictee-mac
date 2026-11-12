import AppKit
import SwiftUI
import DicteeCore

// Les modes de Concentration dans l'îlot (maquette design/maquettes/ilot-concentration.html, étapes 1 à 7) : le rond « Concentration » du
// Centre, la carte des modes (« ‹ Centre », la grille des cinq modes, la légende, les durées), l'icône du mode dans l'aile gauche, la
// bannière « Travail · jusqu'à 15:30 », la carte « où en est le mode » au survol (« Arrêter », « +30 min »), « Fin de Travail ».
//
// Le système passe par `SystemeConcentration` (ConcentrationSysteme.swift) ; la logique pure par DicteeCore/ConcentrationIlot.swift.
// Énergie : aucune minuterie au repos. La fin d'une durée est UNE échéance sur l'horloge murale (`asyncAfter(wallDeadline:)`), revue à la
// sortie de veille et au lancement ; la carte du mode ne se redessine (toutes les 30 s) que pendant qu'elle est à l'écran.

/// Ce que l'îlot montre de la Concentration (poussé par le pilote).
struct AffichageConcentration: Equatable {
    var actif: EtatConcentration?
    var dernier: DernierConcentration?
    /// Un mode allumé ailleurs (Centre de contrôle) que Verbe n'a pas allumé : son nom, tel que Raccourcis le donne.
    var externe: String?
    /// Le mode choisi dans la carte, qui attend sa durée.
    var choisi: ModeConcentration?
    /// Le raccourci « Concentration Verbe » n'est pas encore ajouté (Raccourcis montre « Ajouter le raccourci »).
    var raccourciManquant = false
    /// Raccourcis travaille (un instant) : les boutons ne relancent rien.
    var occupe = false
    /// Une commande n'a pas abouti : la légende de la carte le dit.
    var message: String?
    /// Ce que dit la dernière bannière « Fin de … » (le mode, pour son icône) ; nil : une bannière d'échec.
    var finDe: ModeConcentration?

    var rond: RondConcentration { .depuis(actif: actif, dernier: dernier, externe: externe) }
    /// Le mode montré par la carte du mode, l'aile, la bulle (l'allumé, sinon le dernier : un écran qui s'efface garde son icône).
    var modeVu: ModeConcentration { actif?.mode ?? dernier?.mode ?? .nePasDeranger }
}

/// Ce que les boutons de la Concentration demandent (routé par `IlotControleur.agir`).
enum ActionConcentration: Equatable {
    /// Le rond du Centre : arrête le mode allumé, relance le dernier, sinon ouvre la carte des modes (maquette, `clicConc`).
    case rond
    /// « Changer de mode » (carte du mode) : la carte des modes.
    case changer
    case choisir(ModeConcentration)
    case duree(DureeConcentration)
    case arreter, prolonger
}

// MARK: - le pilote

/// Allume, éteint et suit les modes de Concentration. Une commande à la fois ; tout ce qui touche à Raccourcis tourne hors du fil principal.
@MainActor
final class PiloteConcentration {
    unowned let moteur: IlotMoteur
    /// Injectables : les essais remplacent le système et le fichier (jamais le vrai Raccourcis, jamais le vrai fichier).
    var systeme = SystemeConcentration.reel
    var store = ConcentrationStore(url: ConcentrationStore.urlParDefaut)
    var calendrier = Calendar.current
    /// Le dossier temporaire où le raccourci signé attend que Raccourcis le lise.
    var dossierTemporaire = FileManager.default.temporaryDirectory
    private(set) var memoire = MemoireConcentration()
    private var affichage = AffichageConcentration()
    /// L'unique échéance : la fin du mode allumé.
    private(set) var echeance: DispatchWorkItem?
    private var observateurReveilMac: NSObjectProtocol?
    /// Pendant que Raccourcis montre « Ajouter le raccourci » : les raccourcis d'avant (le nôtre sera le nouveau), le dossier du fichier, et
    /// l'écoute des changements d'app (Hugues revient de Raccourcis), retirée dès que le raccourci est là.
    /// `avant` est nil tant que le fichier se prépare : rien n'est encore reconnu comme le nôtre.
    private var importEnCours: (avant: Set<String>?, dossier: URL)?
    private var observateurApps: NSObjectProtocol?
    /// Un mode et une durée choisis avant que le raccourci soit ajouté : lancés dès qu'il l'est.
    private var enAttente: (mode: ModeConcentration, duree: DureeConcentration)?
    private var derniereLecture: Date?
    private let file = DispatchQueue(label: "verbe.concentration", qos: .userInitiated)
    /// Combien de commandes sont parties vers Raccourcis (l'essai vérifie que rien ne part au repos).
    private(set) var commandesEnvoyees = 0

    init(moteur: IlotMoteur) { self.moteur = moteur }

    private var maintenant: Date { moteur.maintenant() }

    // MARK: vie

    /// Au lancement : relit le fichier ; un mode fini pendant que Verbe était fermé (ou le Mac éteint) s'éteint ; sinon son échéance.
    func demarrer() {
        memoire = store.lire()
        affichage.actif = memoire.actif; affichage.dernier = memoire.dernier
        if observateurReveilMac == nil {
            observateurReveilMac = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.verifierLaFin() }
            }
        }
        publier()
        verifierLaFin()
    }

    func arreter() {
        echeance?.cancel(); echeance = nil
        if let o = observateurReveilMac { NSWorkspace.shared.notificationCenter.removeObserver(o); observateurReveilMac = nil }
        finirLImport()
    }

    // MARK: actions

    func agir(_ a: ActionConcentration) {
        switch a {
        case .rond:
            if affichage.occupe { return }
            if let actif = affichage.actif { eteindre(actif.mode, depuis: .centre) }
            else if let d = affichage.dernier, affichage.externe == nil { allumer(d.mode, d.duree, depuis: .centre) }
            else { ouvrirLaCarte() }
        case .changer:
            ouvrirLaCarte()
        case .choisir(let mode):
            guard !affichage.occupe else { return }
            affichage.choisi = mode; affichage.message = nil
            publier()
            // le premier clic sur un mode : sans raccourci, Raccourcis propose de l'ajouter (une fois)
            if memoire.raccourci == nil { preparerLeRaccourci() }
        case .duree(let d):
            guard !affichage.occupe, let mode = affichage.choisi ?? affichage.actif?.mode else { return }
            allumer(mode, d, depuis: .carte)
        case .arreter:
            if let actif = affichage.actif, !affichage.occupe { eteindre(actif.mode, depuis: .statut) }
        case .prolonger:
            guard var actif = memoire.actif, actif.prolonger(a: maintenant) else { return }
            memoire.actif = actif; affichage.actif = actif
            store.ecrire(memoire)
            Log.ecrire("concentration : +30 min (\(actif.jusqua(calendrier: calendrier)))")
            programmerLaFin()
            publier()
        }
    }

    private func ouvrirLaCarte() {
        affichage.choisi = nil; affichage.message = nil
        publier()
        moteur.epinglerLeCentre()
        moteur.ouvrirOutil(.concentration)
        lireLEtat()
    }

    enum Origine { case centre, carte, statut, fin }

    /// Allume `mode` pour `duree`. Sans raccourci : Raccourcis propose de l'ajouter, et le mode part dès qu'il est là.
    private func allumer(_ mode: ModeConcentration, _ duree: DureeConcentration, depuis origine: Origine) {
        commande(.allumer(mode), sansRaccourci: { [weak self] in self?.enAttente = (mode, duree) }) { [weak self] ok in
            guard let self else { return }
            guard ok else { self.echec("Raccourcis n\u{2019}a pas allumé \(mode.nom)", origine: origine); return }
            let etat = EtatConcentration(mode: mode, duree: duree, debut: self.maintenant, calendrier: self.calendrier)
            self.memoire.actif = etat; self.memoire.dernier = DernierConcentration(mode: mode, duree: duree)
            self.store.ecrire(self.memoire)
            self.affichage.actif = etat; self.affichage.dernier = self.memoire.dernier
            self.affichage.choisi = nil; self.affichage.externe = nil; self.affichage.message = nil
            Log.ecrire("concentration : \(mode.rawValue) allumé (\(etat.jusqua(calendrier: self.calendrier)))")
            self.programmerLaFin()
            self.publier()
            // depuis la carte : l'îlot se replie et la bannière dit jusqu'à quand (maquette, étape 3) ; depuis le Centre, le rond suffit
            if origine == .carte {
                self.moteur.fermer()
                self.moteur.annoncer(bandeau: BandeauIlot(vue: .concentrationLance, jusqua: self.maintenant.addingTimeInterval(3),
                                                          ligne1: BanniereConcentration.lance(etat, calendrier: self.calendrier), ligne2: ""))
            }
        }
    }

    /// Éteint `mode` (« Arrêter », le rond du Centre, l'heure venue).
    private func eteindre(_ mode: ModeConcentration, depuis origine: Origine) {
        commande(.eteindre(mode), sansRaccourci: nil, proposer: origine != .fin) { [weak self] ok in
            guard let self else { return }
            guard ok else { self.echec("\(mode.nom) est resté allumé", origine: origine); return }
            self.memoire.actif = nil
            self.store.ecrire(self.memoire)
            self.affichage.actif = nil; self.affichage.externe = nil
            self.echeance?.cancel(); self.echeance = nil
            Log.ecrire("concentration : \(mode.rawValue) éteint (\(origine == .fin ? "à l'heure" : "d'un clic"))")
            self.publier()
            // « Fin de Travail » (maquette, étape 6) ; depuis le Centre, le rond qui change suffit
            guard origine != .centre else { return }
            if origine == .statut { self.moteur.fermer() }
            self.affichage.finDe = mode
            self.publier()
            self.moteur.annoncer(bandeau: BandeauIlot(vue: .concentrationFin, jusqua: self.maintenant.addingTimeInterval(4),
                                                      ligne1: BanniereConcentration.fin(mode), ligne2: BanniereConcentration.finSous))
        }
    }

    /// Une commande vers le raccourci, hors du fil principal. Sans raccourci retenu, on regarde s'il vient d'être ajouté ; sinon
    /// Raccourcis propose de l'ajouter et `sansRaccourci` garde ce qui attendait (sans lui, c'est un échec). Un échec du raccourci
    /// retenu : s'il a été supprimé, on l'oublie. Raccourcis ne s'ouvre que sur un geste de Hugues (`proposer`), jamais à l'échéance.
    /// `fin(ok)` sur le fil principal.
    private func commande(_ c: RaccourciConcentration.Commande, sansRaccourci: (() -> Void)?, proposer: Bool = true, fin: @escaping (Bool) -> Void) {
        affichage.occupe = true; publier()
        let s = systeme, retenu = memoire.raccourci, avant = importEnCours?.avant ?? nil
        commandesEnvoyees += 1
        file.async { [weak self] in
            var id = retenu
            var nouveau = false
            if id == nil, let avant, let liste = s.lister() { id = RaccourciConcentration.nouveau(dans: liste, avant: avant); nouveau = id != nil }
            guard let id else {
                DispatchQueue.main.async { MainActor.assumeIsolated {
                    guard let self else { return }
                    self.affichage.occupe = false
                    self.affichage.raccourciManquant = true
                    sansRaccourci?()
                    self.publier()
                    if proposer { self.preparerLeRaccourci() }
                    if sansRaccourci == nil { fin(false) }
                } }
                return
            }
            let reponse = s.lancer(id, c.texte)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let ok = c == .lire ? reponse != nil : reponse == RaccourciConcentration.reponseOK
            // un échec : le raccourci est-il encore là ? (supprimé par Hugues : on le proposera de nouveau)
            let disparu = !ok && (s.lister().map { !RaccourciConcentration.present(id, dans: $0) } ?? false)
            DispatchQueue.main.async { MainActor.assumeIsolated {
                guard let self else { return }
                self.affichage.occupe = false
                if nouveau { self.raccourciAjoute(id) }
                if disparu {
                    Log.ecrire("concentration : le raccourci n'est plus dans Raccourcis")
                    self.memoire.raccourci = nil; self.store.ecrire(self.memoire)
                    self.affichage.raccourciManquant = true
                }
                if !ok { Log.ecrire("concentration : « \(c.texte.prefix(3)) » sans réponse attendue de Raccourcis") }
                fin(ok)
                if disparu, proposer { self.preparerLeRaccourci() }
            } }
        }
    }

    /// Le raccourci que Hugues vient d'ajouter : retenu (le seul que Verbe lance), le fichier temporaire effacé, et ce qui attendait part.
    private func raccourciAjoute(_ id: String) {
        memoire.raccourci = id
        store.ecrire(memoire)
        affichage.raccourciManquant = false
        Log.ecrire("concentration : raccourci « \(RaccourciConcentration.nom) » ajouté")
        finirLImport()
        publier()
    }

    /// Fabrique le raccourci, le signe pour ce Mac et l'ouvre : Raccourcis montre « Ajouter le raccourci » (maquette, étape 3 : la seule
    /// question, une fois). Puis on attend que Hugues revienne (changement d'app), sans minuterie.
    private func preparerLeRaccourci() {
        guard importEnCours == nil else { return }
        let s = systeme
        let dossier = dossierTemporaire.appendingPathComponent("verbe-concentration-\(UUID().uuidString)", isDirectory: true)
        let fichier = dossier.appendingPathComponent(RaccourciConcentration.nom + ".shortcut")
        importEnCours = (avant: nil, dossier: dossier)
        affichage.raccourciManquant = true; publier()
        file.async { [weak self] in
            let avant = Set((s.lister() ?? []).map(\.identifiant))
            let ok = RaccourciConcentration.donnees().map { s.preparer($0, fichier) } ?? false
            DispatchQueue.main.async { MainActor.assumeIsolated {
                guard let self else { return }
                guard ok else {
                    Log.ecrire("concentration : raccourci impossible à préparer")
                    self.finirLImport()
                    self.affichage.message = "Raccourcis n\u{2019}a pas pu préparer le raccourci, réessaie"
                    self.publier()
                    return
                }
                self.importEnCours = (avant: avant, dossier: dossier)
                Log.ecrire("concentration : Raccourcis propose d'ajouter « \(RaccourciConcentration.nom) »")
                self.observateurApps = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.verifierLImport() }
                }
                s.ouvrir(fichier)
            } }
        }
    }

    /// Hugues a changé d'app (il revient de Raccourcis) : le raccourci est-il là ? Si oui, ce qui attendait part.
    func verifierLImport() {
        guard let avant = importEnCours?.avant ?? nil else { return }
        let s = systeme
        file.async { [weak self] in
            let id = s.lister().flatMap { RaccourciConcentration.nouveau(dans: $0, avant: avant) }
            DispatchQueue.main.async { MainActor.assumeIsolated {
                guard let self, let id, self.memoire.raccourci == nil else { return }
                self.raccourciAjoute(id)
                if let (m, d) = self.enAttente { self.enAttente = nil; self.allumer(m, d, depuis: .carte) }
            } }
        }
    }

    private func finirLImport() {
        if let o = observateurApps { NSWorkspace.shared.notificationCenter.removeObserver(o); observateurApps = nil }
        if let d = importEnCours?.dossier { try? FileManager.default.removeItem(at: d) }
        importEnCours = nil
    }

    /// Une commande qui n'a pas abouti : dite dans la légende si la carte est là, sinon dans une bannière.
    private func echec(_ titre: String, origine: Origine) {
        affichage.message = titre
        publier()
        guard moteur.courante != .concentration else { return }
        affichage.finDe = nil
        publier()
        moteur.annoncer(bandeau: BandeauIlot(vue: .concentrationFin, jusqua: maintenant.addingTimeInterval(4), ligne1: titre,
                                             ligne2: affichage.raccourciManquant ? "Le raccourci \u{00AB}\u{00A0}\(RaccourciConcentration.nom)\u{00A0}\u{00BB} manque" : "Réessaie dans un instant"))
    }

    // MARK: la fin et la lecture

    /// Le mode est-il fini ? Alors on l'éteint ; sinon on attend son échéance.
    func verifierLaFin() {
        guard let actif = memoire.actif else { return }
        if actif.estFini(a: maintenant) { eteindre(actif.mode, depuis: .fin) } else { programmerLaFin() }
    }

    /// Une seule échéance, sur l'horloge MURALE (le temps passé en veille compte) ; « jusqu'à l'arrêt » : aucune.
    private func programmerLaFin() {
        echeance?.cancel(); echeance = nil
        guard let fin = memoire.actif?.fin else { return }
        let item = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.verifierLaFin() } }
        echeance = item
        DispatchQueue.main.asyncAfter(wallDeadline: .now() + max(0.05, fin.timeIntervalSince(maintenant)), execute: item)
    }

    /// La carte des modes s'ouvre et Verbe n'a rien allumé : quel mode est allumé ailleurs (Centre de contrôle) ? Une fois par minute au
    /// plus, jamais au repos. Ce que Verbe a allumé lui-même ne dépend jamais de cette lecture (son échéance reste la sienne).
    private func lireLEtat() {
        guard memoire.actif == nil, memoire.raccourci != nil, !affichage.occupe else { return }
        if let d = derniereLecture, maintenant.timeIntervalSince(d) < 60 { return }
        derniereLecture = maintenant
        let s = systeme, id = memoire.raccourci!
        commandesEnvoyees += 1
        file.async { [weak self] in
            let reponse = s.lancer(id, RaccourciConcentration.Commande.lire.texte)
            DispatchQueue.main.async { MainActor.assumeIsolated {
                guard let self, let reponse, self.memoire.actif == nil else { return }
                switch RaccourciConcentration.lireEtat(reponse) {
                case .aucun: self.affichage.externe = nil
                case .mode(let m): self.affichage.externe = m.nom
                case .autre(let n): self.affichage.externe = n
                }
                self.publier()
            } }
        }
    }

    private func publier() {
        moteur.concentration = affichage
        moteur.donneesChangees()
    }
}

// MARK: - les mesures (dessin, hauteur de la forme, essais)

@MainActor
enum PlanConcentration {
    typealias Mc = MesuresConcentration
    static func zone(_ g: GrilleIlot) -> CGRect { g.zoneCarte(.concentration, haut: CGFloat(Mc.haut), bas: CGFloat(Mc.bas)) }
    static func entete(_ g: GrilleIlot) -> CGRect { let z = zone(g); return CGRect(x: z.minX, y: z.minY, width: z.width, height: CGFloat(Mc.entete)) }
    /// Le bouton d'un mode : deux colonnes, « Réduire les interruptions » sur toute la largeur en dessous (maquette).
    static func cadre(_ mode: ModeConcentration, _ g: GrilleIlot) -> CGRect {
        let z = zone(g), e = CGFloat(Mc.ecart), h = CGFloat(Mc.bouton)
        let y0 = z.minY + CGFloat(Mc.entete + Mc.ecartEntete)
        let l = (z.width - e) / 2
        guard !mode.largeurPleine, let i = ModeConcentration.allCases.firstIndex(of: mode) else {
            return CGRect(x: z.minX, y: y0 + 2 * (h + e), width: z.width, height: h)
        }
        return CGRect(x: z.minX + CGFloat(i % 2) * (l + e), y: y0 + CGFloat(i / 2) * (h + e), width: l, height: h)
    }
    static func legende(_ g: GrilleIlot) -> CGRect {
        let z = zone(g)
        return CGRect(x: z.minX, y: z.minY + CGFloat(Mc.entete + Mc.ecartEntete + Mc.grille + Mc.ecartLegende), width: z.width, height: CGFloat(Mc.legende))
    }
    static func largeur(_ d: DureeConcentration) -> CGFloat { MesureIlot.texte(d.libelle, 12.5, .semibold) + 28 }
    static func cadre(_ d: DureeConcentration, _ g: GrilleIlot) -> CGRect {
        let l = legende(g)
        let avant = DureeConcentration.allCases.prefix { $0 != d }.map { largeur($0) + CGFloat(Mc.ecart) }.reduce(0, +)
        return CGRect(x: l.minX + avant, y: l.maxY + CGFloat(Mc.ecartDurees), width: largeur(d), height: CGFloat(Mc.duree))
    }
    /// « ‹ Centre » dans l'en-tête.
    static var largeurRetour: CGFloat { 8 + MesureIlot.symbole("chevron.left", 10.5, .bold) + 4 + MesureIlot.texte("Centre", 12.5, .semibold) + 11 }
    static func pointCentre(_ g: GrilleIlot) -> CGPoint { let e = entete(g); return CGPoint(x: e.minX + largeurRetour / 2, y: e.midY) }

    // la carte du mode (au survol de l'îlot replié)
    static func zoneStatut(_ g: GrilleIlot) -> CGRect { g.zoneCarte(.concentrationStatut, haut: CGFloat(Mc.haut), bas: CGFloat(Mc.bas)) }
    static func largeurPilule(_ t: String) -> CGFloat { PiluleOutil.largeur(t, taille: 13, padding: 14) }
    static let arreter = "Arrêter", plus = "+30 min", changer = "Changer de mode"
    /// « +30 min » à droite, « Arrêter » devant ; sans fin (jusqu'à l'arrêt), « Arrêter » seul à droite.
    static func cadreArreter(_ g: GrilleIlot, prolongeable: Bool) -> CGRect {
        let z = zoneStatut(g), l = largeurPilule(arreter)
        let x = z.maxX - l - (prolongeable ? largeurPilule(plus) + CGFloat(Mc.ecart) : 0)
        return CGRect(x: x, y: z.minY + (CGFloat(Mc.ligne) - 30) / 2, width: l, height: 30)
    }
    static func cadrePlus(_ g: GrilleIlot) -> CGRect {
        let z = zoneStatut(g), l = largeurPilule(plus)
        return CGRect(x: z.maxX - l, y: z.minY + (CGFloat(Mc.ligne) - 30) / 2, width: l, height: 30)
    }
    static func cadreBarre(_ g: GrilleIlot) -> CGRect {
        let z = zoneStatut(g)
        return CGRect(x: z.minX, y: z.minY + CGFloat(Mc.ligne + Mc.ecartBarre), width: z.width, height: CGFloat(Mc.barre))
    }
    static func cadreChanger(_ g: GrilleIlot) -> CGRect {
        let b = cadreBarre(g)
        return CGRect(x: b.minX, y: b.maxY + CGFloat(Mc.ecartChanger), width: 22 + MesureIlot.texte(changer, 13, .semibold) + 8, height: CGFloat(Mc.changer))
    }
    static func centre(_ r: CGRect) -> CGPoint { CGPoint(x: r.midX, y: r.midY) }
}

extension IlotMoteur {
    /// Les bannières de la Concentration épousent leur contenu : [icône] « Travail · jusqu'à 15:30 » ; [icône] « Fin de Travail » et sa
    /// ligne. nil : un autre écran.
    func largeurConcentration(_ v: VueIlot) -> CGFloat? {
        switch v {
        case .concentrationLance: return 24 + 9 + MesureIlot.texte(bandeauVu?.ligne1 ?? "", 13.5, .semibold)
        case .concentrationFin:
            return 30 + 10 + max(MesureIlot.texte(bandeauVu?.ligne1 ?? "", 13.5, .semibold), MesureIlot.texte(bandeauVu?.ligne2 ?? "", 12.5, .medium))
        default: return nil
        }
    }
}

// MARK: - les glyphes

/// Le glyphe d'un mode : son symbole SF, ou, pour « Réduire les interruptions », l'anneau de quatre couleurs douces et l'étincelle (maquette).
struct GlypheConcentration: View {
    var mode: ModeConcentration?
    var taille: CGFloat
    var couleur: Color = .white
    var body: some View {
        Group {
            if let mode, mode.symbole == nil {
                Canvas { ctx, size in
                    let k = size.width / 24
                    func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * k, y: y * k) }
                    for (a0, a1, c) in [(-85.0, -10.0, 0xFF9F0A), (5, 80, 0xFF6482), (95, 170, 0xBF8BF5), (185, 260, 0x5AA9FF)] as [(Double, Double, UInt32)] {
                        var arc = Path()
                        arc.addArc(center: p(12, 12), radius: 10 * k, startAngle: .degrees(a0), endAngle: .degrees(a1), clockwise: false)
                        ctx.stroke(arc, with: .color(Color(hex: c)), style: StrokeStyle(lineWidth: 1.9 * k, lineCap: .round))
                    }
                    var e = Path()
                    e.move(to: p(12, 6.4)); e.addQuadCurve(to: p(17.6, 12), control: p(12.6, 11.4))
                    e.addQuadCurve(to: p(12, 17.6), control: p(12.6, 12.6)); e.addQuadCurve(to: p(6.4, 12), control: p(11.4, 12.6))
                    e.addQuadCurve(to: p(12, 6.4), control: p(11.4, 11.4)); e.closeSubpath()
                    ctx.fill(e, with: .color(couleur))
                }
            } else {
                Image(systemName: mode?.symbole ?? "moon.fill").font(.system(size: taille * 0.8, weight: .semibold)).foregroundStyle(couleur)
            }
        }
        .frame(width: taille, height: taille)
        .accessibilityHidden(true)
    }
}

extension ModeConcentration {
    var teinte: Color { Color(hex: couleur) }
}

// MARK: - les écrans

/// Les écrans de la Concentration dans l'îlot (IlotCalques les appelle).
struct EcranConcentration: View {
    @ObservedObject var m: IlotMoteur
    var g: GrilleIlot
    var v: VueIlot

    var body: some View {
        switch v {
        case .concentrationCompact: aile(v)
        case .concentrationLance: ZStack(alignment: .topLeading) { aile(v); banniere }
        case .concentrationFin: fin
        case .concentrationStatut: CarteStatutConcentration(m: m, g: g)
        case .concentration: CarteModesConcentration(m: m, g: g)
        default: EmptyView()
        }
    }

    /// L'icône du mode dans l'aile gauche (18 pt, sa couleur) ; à droite, rien que la caméra (maquette, étapes 3 et 4).
    private func aile(_ v: VueIlot) -> some View {
        let mode = m.concentration.modeVu
        let c = g.centreAile(v, droite: false)
        return GlypheConcentration(mode: mode, taille: 18, couleur: mode.teinte)
            .posee(CGRect(x: c - 13, y: 0, width: 26, height: g.barre), m.aspect(v, rang: 0), ancre: .center, .center)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Concentration \(mode.nom)")
            .accessibilityValue(m.concentration.actif.map { $0.encore(a: m.maintenant()) } ?? "")
    }

    /// « Travail · jusqu'à 15:30 », sur une seule ligne, l'icône dans un carré de sa couleur (maquette, étape 3).
    private var banniere: some View {
        let v = VueIlot.concentrationLance
        let mode = m.concentration.modeVu
        let z = g.zoneAnnonce(v, haut: 10, bas: 10)
        return HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(mode.teinte)
                .overlay { GlypheConcentration(mode: mode, taille: 15) }
                .frame(width: 24, height: 24)
                .aspectIlot(m.aspect(v, rang: 1), ancre: .center)
            Text(m.bandeauVu?.ligne1 ?? "").font(.system(size: 13.5, weight: .semibold).monospacedDigit()).tracking(-0.1).foregroundStyle(.white)
                .lineLimit(1).fixedSize()
                .aspectIlot(m.aspect(v, rang: 2), ancre: .leading)
        }
        .frame(width: z.width, height: z.height)
        .offset(x: IlotMoteur.largeur / 2 + z.minX, y: z.minY)
        .accessibilityElement(children: .combine)
    }

    /// « Fin de Travail », « Les notifications reviennent » (maquette, étape 6 ; Verbe ne compte pas les notifications retenues : il ne
    /// les voit pas). Une commande qui n'a pas abouti se dit au même endroit, avec un point d'exclamation.
    private var fin: some View {
        let v = VueIlot.concentrationFin
        let z = g.zoneAnnonce(v, haut: 10, bas: 10)
        let b = m.bandeauVu
        let finDe = m.concentration.finDe
        return HStack(spacing: 10) {
            Circle().fill(Color.white.opacity(0.18))
                .overlay {
                    if let finDe { GlypheConcentration(mode: finDe, taille: 15) }
                    else { Image(systemName: "exclamationmark").font(.system(size: 14, weight: .bold)).foregroundStyle(CouleursIlot.ambre) }
                }
                .frame(width: 30, height: 30)
                .aspectIlot(m.aspect(v, rang: 0), ancre: .center)
            VStack(alignment: .leading, spacing: 1) {
                Text(b?.ligne1 ?? "").font(.system(size: 13.5, weight: .semibold)).tracking(-0.1).foregroundStyle(.white).lineLimit(1)
                Text(b?.ligne2 ?? "").font(.system(size: 12.5, weight: .medium)).foregroundStyle(Color.white.opacity(0.55)).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .aspectIlot(m.aspect(v, rang: 1), ancre: .topLeading)
        }
        .frame(width: z.width, height: z.height)
        .offset(x: IlotMoteur.largeur / 2 + z.minX, y: z.minY)
        .accessibilityElement(children: .combine)
    }
}

/// Le vide d'une carte ne la range pas (on visait un bouton) ; seulement tant qu'elle est là.
private struct FondCarteConcentration: View {
    @ObservedObject var m: IlotMoteur
    var g: GrilleIlot
    var v: VueIlot
    var body: some View {
        Color.clear.contentShape(Rectangle()).onTapGesture {}
            .allowsHitTesting(m.courante == v)
            .accessibilityHidden(true)
            .posee(CGRect(x: -g.corps(v), y: g.barre, width: 2 * g.corps(v), height: max(0, g.hauteur(v) - g.barre)))
    }
}

/// La carte des modes (maquette, étape 2) : « ‹ Centre » et « Concentration », un gros bouton par mode (son icône dans un rond de sa
/// couleur), la légende, puis les durées.
struct CarteModesConcentration: View {
    @ObservedObject var m: IlotMoteur
    var g: GrilleIlot

    var body: some View {
        let v = VueIlot.concentration
        let a = m.concentration
        ZStack(alignment: .topLeading) {
            FondCarteConcentration(m: m, g: g, v: v)
            HStack(spacing: 10) {
                PiluleCentre(titre: "Centre", retour: true, etiquette: "Revenir au Centre") { m.allerA(.centre) }.frame(width: PlanConcentration.largeurRetour)
                Text("Concentration").font(.system(size: 15, weight: .semibold)).tracking(-0.2).foregroundStyle(.white).lineLimit(1).fixedSize()
                    .allowsHitTesting(false)
                Spacer(minLength: 0)
                ResteOuvert(m: m)
            }
            .posee(PlanConcentration.entete(g), m.aspect(v, rang: 0), ancre: .topLeading)
            ForEach(Array(ModeConcentration.allCases.enumerated()), id: \.element) { i, mode in
                BoutonModeConcentration(mode: mode, choisi: a.choisi == mode, allume: a.actif?.mode == mode) { m.surAction(.concentration(.choisir(mode))) }
                    .posee(PlanConcentration.cadre(mode, g), m.aspect(v, rang: 1 + i / 2), ancre: .top)
            }
            Text(legende(a)).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(a.message != nil ? Color(hex: 0xFFB340) : Color.white.opacity(0.5))
                .lineLimit(1).truncationMode(.tail)
                .allowsHitTesting(false)
                .posee(PlanConcentration.legende(g), m.aspect(v, rang: 4), ancre: .topLeading)
            ForEach(DureeConcentration.allCases, id: \.self) { d in
                let possible = a.choisi != nil || a.actif != nil
                PiluleDureeConcentration(titre: d.libelle, eteinte: !possible, choisie: a.choisi == nil && a.actif?.duree == d) {
                    if possible { m.surAction(.concentration(.duree(d))) }
                }
                .posee(PlanConcentration.cadre(d, g), m.aspect(v, rang: 4), ancre: .top)
            }
        }
        .frame(width: IlotMoteur.largeur, height: IlotMoteur.hauteurMax, alignment: .topLeading)
    }

    private func legende(_ a: AffichageConcentration) -> String {
        if a.occupe { return "Un instant\u{2026}" }
        if let msg = a.message { return msg }
        return LegendeConcentration.texte(actif: a.actif, choisi: a.choisi, raccourciManquant: a.raccourciManquant, calendrier: .current)
    }
}

/// Un bouton de mode (48 pt) : l'icône dans un rond de sa couleur, le nom. Choisi : teinté et cerclé de sa couleur ; allumé : plein.
struct BoutonModeConcentration: View {
    var mode: ModeConcentration
    var choisi: Bool
    var allume: Bool
    var action: () -> Void
    @State private var survol = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Circle().fill(allume ? Color.white.opacity(0.28) : (mode.largeurPleine ? Color.white.opacity(0.16) : mode.teinte))
                    .overlay { GlypheConcentration(mode: mode, taille: 18) }
                    .frame(width: 32, height: 32)
                Text(mode.nom).font(.system(size: 13, weight: .semibold)).tracking(-0.1).foregroundStyle(.white).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.leading, 8).padding(.trailing, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(fond))
            .overlay { if choisi && !allume { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(mode.teinte, lineWidth: 1.5) } }
            .brightness(survol && !allume ? 0.06 : 0)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(AppuiIlot(echelle: 0.97))
        .onHover { survol = $0 }
        .accessibilityLabel(mode.nom)
        .accessibilityValue(allume ? "allumé" : (choisi ? "choisi" : ""))
    }
    private var fond: Color { allume ? mode.teinte : (choisi ? mode.teinte.opacity(0.3) : Color.white.opacity(0.1)) }
}

/// Une durée (32 pt) : grise ; éteinte (aucun mode choisi) à 40 % ; celle du mode allumé, blanche.
struct PiluleDureeConcentration: View {
    var titre: String
    var eteinte: Bool
    var choisie: Bool
    var action: () -> Void
    @State private var survol = false
    var body: some View {
        // pas de `.disabled` (le clic passerait au geste de l'îlot, qui se range) : éteinte, l'action ne fait rien
        Button(action: action) {
            Text(titre).font(.system(size: 12.5, weight: .semibold)).lineLimit(1).fixedSize()
                .foregroundStyle(choisie ? Color.black : Color.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Capsule().fill(choisie ? Color.white : Color.white.opacity(survol && !eteinte ? 0.2 : 0.12)))
                .opacity(eteinte ? 0.4 : 1)
                .contentShape(Capsule())
        }
        .buttonStyle(AppuiIlot(echelle: 0.94))
        .onHover { survol = $0 }
        .accessibilityLabel(titre)
        .accessibilityHint(eteinte ? "Choisis d\u{2019}abord un mode" : "")
    }
}

/// Où en est le mode (maquette, étape 5) : l'icône, le nom et « encore 42 min », « Arrêter » et « +30 min », la barre du temps qui reste,
/// « Changer de mode ». Le pied « Centre » est dessiné par l'îlot (le chemin vers le Centre se voit toujours).
struct CarteStatutConcentration: View {
    @ObservedObject var m: IlotMoteur
    var g: GrilleIlot

    var body: some View {
        let v = VueIlot.concentrationStatut
        let a = m.concentration
        let mode = a.modeVu
        let z = PlanConcentration.zoneStatut(g)
        let prolongeable = a.actif?.fin != nil
        let arreter = PlanConcentration.cadreArreter(g, prolongeable: prolongeable)
        ZStack(alignment: .topLeading) {
            FondCarteConcentration(m: m, g: g, v: v)
            // « encore 42 min » et la barre changent avec le temps : redessinés toutes les 30 s, et seulement pendant que la carte est là
            TimelineView(.periodic(from: Date(timeIntervalSinceReferenceDate: 0), by: 30)) { _ in
                let t = m.maintenant()
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 13, style: .continuous).fill(mode.teinte)
                            .overlay { GlypheConcentration(mode: mode, taille: 24) }
                            .frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mode.nom).font(.system(size: 15, weight: .semibold)).tracking(-0.2).foregroundStyle(.white).lineLimit(1)
                            Text(a.actif?.encore(a: t) ?? "").font(.system(size: 12.5, weight: .medium).monospacedDigit()).foregroundStyle(Color.white.opacity(0.55)).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(width: max(0, arreter.minX - z.minX - 8), height: CGFloat(MesuresConcentration.ligne), alignment: .leading)
                    .allowsHitTesting(false)
                    .posee(CGRect(x: z.minX, y: z.minY, width: max(0, arreter.minX - z.minX - 8), height: CGFloat(MesuresConcentration.ligne)), m.aspect(v, rang: 0), ancre: .topLeading)
                    let b = PlanConcentration.cadreBarre(g)
                    Capsule().fill(Color.white.opacity(0.16))
                        .overlay(alignment: .leading) { Capsule().fill(mode.teinte).frame(width: b.width * CGFloat(a.actif?.fraction(a: t) ?? 1)) }
                        .allowsHitTesting(false)
                        .posee(b, m.aspect(v, rang: 1), ancre: .topLeading)
                }
            }
            .accessibilityElement(children: .combine)
            PiluleOutil(titre: PlanConcentration.arreter, hauteur: 30, taille: 13, padding: 14, etiquette: "Arrêter \(mode.nom)") {
                m.surAction(.concentration(.arreter))
            }
            .posee(arreter, m.aspect(v, rang: 0), ancre: .center)
            if prolongeable {
                PiluleOutil(titre: PlanConcentration.plus, hauteur: 30, taille: 13, padding: 14, etiquette: "Encore 30 minutes") { m.surAction(.concentration(.prolonger)) }
                    .posee(PlanConcentration.cadrePlus(g), m.aspect(v, rang: 0), ancre: .center)
            }
            BoutonChangerConcentration { m.surAction(.concentration(.changer)) }
                .posee(PlanConcentration.cadreChanger(g), m.aspect(v, rang: 2), ancre: .topLeading)
        }
        .frame(width: IlotMoteur.largeur, height: IlotMoteur.hauteurMax, alignment: .topLeading)
    }
}

/// « Changer de mode » : la grille des modes (à la place de « 3 notifications retenues » de la maquette, que Verbe ne peut pas voir).
private struct BoutonChangerConcentration: View {
    var action: () -> Void
    @State private var survol = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "square.grid.2x2.fill").font(.system(size: 12, weight: .semibold)).frame(width: 14)
                Text(PlanConcentration.changer).font(.system(size: 13, weight: .semibold)).lineLimit(1).fixedSize()
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color.white.opacity(survol ? 1 : 0.82))
            .contentShape(Rectangle())
        }
        .buttonStyle(AppuiIlot(echelle: 0.96))
        .onHover { survol = $0 }
        .accessibilityLabel("Changer de mode de concentration")
    }
}

/// Le rond « Concentration » du Centre (maquette, étapes 1 et 7) : la lune et « Désactivée » ; le mode allumé, de sa couleur ; le dernier,
/// cerclé de sa couleur (un clic le relance) ; un mode allumé ailleurs, son nom.
struct TuileConcentration: View {
    @ObservedObject var m: IlotMoteur
    var nom: String
    var nomAffiche: String
    var etat: String
    var colonne: CGFloat
    var tailles: (nom: CGFloat, etat: CGFloat)
    var edition: Bool
    var rang: Int
    var retirer: (() -> Void)?

    var body: some View {
        let a = m.concentration
        let r = a.rond
        let fige = m.reduire || m.statique
        let style: (fond: Color?, anneau: Bool, couleurAnneau: Color, encre: Color, glyphe: Color, mode: ModeConcentration?, etiquette: String) = {
            switch r {
            case .eteint:
                return (nil, false, .clear, CouleursIlot.encre2, .white, nil, "Concentration désactivée : choisir un mode")
            case .actif(let mo):
                return (mo.teinte, false, .clear, Color.white.opacity(0.85), .white, mo, "Concentration \(mo.nom) allumée : l\u{2019}arrêter")
            case .dernier(let d):
                return (d.mode.teinte.opacity(0.3), true, d.mode.teinte, Color.white.opacity(0.8), d.mode.teinte, d.mode, "Relancer \(r.etat)")
            case .autre(let n):
                return (ModeConcentration.nePasDeranger.teinte, false, .clear, Color.white.opacity(0.85), .white, nil, "\(n) allumé dans macOS : choisir un mode")
            }
        }()
        TuileRonde(nom: nom, nomAffiche: nomAffiche, etat: a.occupe ? "Un instant\u{2026}" : etat, couleurEtat: style.encre, fond: style.fond,
                   anneau: style.anneau, couleurAnneau: style.couleurAnneau, declencheur: "\(r)", colonne: colonne, tailleNom: tailles.nom, tailleEtat: tailles.etat,
                   reduire: fige, edition: edition, rang: rang, statique: m.statique, retirer: retirer, etiquette: style.etiquette) {
            GlypheConcentration(mode: style.mode, taille: 24, couleur: style.glyphe)
        } action: { m.epinglerLeCentre(); m.surAction(.concentration(.rond)) }
    }
}

/// La Concentration dans la bulle (une vidéo a l'îlot) : l'icône du mode, de sa couleur.
struct PastilleConcentration: View {
    @ObservedObject var m: IlotMoteur
    var body: some View {
        let mode = m.concentration.modeVu
        GlypheConcentration(mode: mode, taille: 13, couleur: mode.teinte)
            .padding(.leading, 10)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Concentration \(mode.nom)")
    }
}
