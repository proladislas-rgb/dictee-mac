import AppKit
import SwiftUI
import DicteeCore

// La case « Second Brain » de l'îlot (maquette design/maquettes/ilot-second-cerveau.html, validée par Hugues) :
// - Second Brain est une autre app locale de Hugues. Elle dépose un petit fichier d'état, ~/.config/second-cerveau/ilot.json
//   (contrat : docs/second-cerveau-ilot.md). L'îlot ne fait que le LIRE : il ne coche rien, n'écrit rien, n'envoie rien ;
// - le fichier est surveillé SANS sondage : une source du système de fichiers sur son dossier (et sur lui-même quand il existe),
//   relecture coalescée. Aucune minuterie au repos ; rien ne tourne tant que le fichier ne bouge pas ;
// - la case n'existe que si le fichier existe : un rond « Second Brain » dans le Centre (ajouté une fois, « Modifier » le range ou le
//   retire) qui ouvre une carte rangée sous le Centre (pas de tuile de plus dans le Centre : Minuteur et Étagère ne descendent pas) ;
// - la carte : trois parties courtes (nouveaux messages, à toi, à relancer), sept lignes au plus ; un clic sur une ligne ouvre son lien
//   (schéma secondbrain:// ou fichier existant seulement), « Ouvrir Second Brain » le lien général, sinon l'app si elle est installée ;
// - ce que dit le fichier est personnel : jamais dans le journal, jamais dans les rendus (qui lisent un faux fichier).

// MARK: - la surveillance du fichier

/// Surveille le dossier du fichier d'état et le fichier lui-même, sans sondage : des sources du système de fichiers (le noyau prévient).
/// - le dossier prévient des créations, renommages et suppressions (une écriture « atomique » : fichier temporaire puis renommage) ;
/// - le fichier prévient des écritures sur place (que le dossier ne voit pas) ;
/// - tant que le dossier n'existe pas, on surveille son plus proche ancêtre (~/.config, puis le dossier personnel) : sa création réveille ;
/// - tous les événements d'une rafale sont fondus en une relecture, 0,3 s après le dernier ; elle ne rappelle que si le contenu a changé.
/// Tout se passe sur une file à part ; `surChangement` est appelée sur le fil principal.
final class SourceSecondBrain: @unchecked Sendable {
    static let delai: TimeInterval = 0.3
    private let file = DispatchQueue(label: "verbe.second-brain", qos: .utility)
    private var dossier: URL?
    private var lire: ((URL) -> Data?)?
    private var actif = false
    private var sourceDossier: DispatchSourceFileSystemObject?
    private var surveille: (chemin: String, inode: UInt64)?
    private var sourceFichier: DispatchSourceFileSystemObject?
    private var inodeFichier: UInt64 = 0
    private var reveil: DispatchWorkItem?
    private var dejaEnvoye = false
    private var derniere: Data?
    /// Appelée sur le fil principal : le contenu du fichier (nil : absent ou illisible), au démarrage puis à chaque changement.
    var surChangement: ((Data?) -> Void)?
    /// Combien de relectures ont eu lieu (essais : une rafale d'événements n'en fait qu'une).
    private(set) var relectures = 0

    func demarrer(dossier: URL, lire: @escaping (URL) -> Data?) {
        file.async {
            self.dossier = dossier; self.lire = lire; self.actif = true
            self.dejaEnvoye = false; self.derniere = nil
            self.relire()
        }
    }

    func arreter() {
        file.async {
            self.actif = false
            self.reveil?.cancel(); self.reveil = nil
            self.sourceDossier?.cancel(); self.sourceDossier = nil; self.surveille = nil
            self.sourceFichier?.cancel(); self.sourceFichier = nil
        }
    }

    /// Attend que la file ait fini ce qu'elle avait à faire (essais).
    func attendreLaFile() { file.sync {} }

    private func planifier() {
        reveil?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.relire() }
        reveil = w
        file.asyncAfter(deadline: .now() + Self.delai, execute: w)
    }

    private func relire() {
        guard actif, let dossier, let lire else { return }
        relectures += 1
        armer(dossier)
        let d = lire(dossier.appendingPathComponent(FichierSecondCerveau.nom))
        if dejaEnvoye, d == derniere { return }
        dejaEnvoye = true; derniere = d
        let appel = surChangement
        DispatchQueue.main.async { appel?(d) }
    }

    /// Les deux sources suivent le fichier tel qu'il est maintenant : le plus proche dossier existant, et le fichier (un nouveau fichier,
    /// donc un nouvel inode, après un renommage par-dessus).
    private func armer(_ dossier: URL) {
        let ancetre = FichierSecondCerveau.ancetreExistant(dossier).path
        var st = stat()
        let inodeAncetre = stat(ancetre, &st) == 0 ? UInt64(st.st_ino) : 0
        if sourceDossier == nil || surveille?.chemin != ancetre || surveille?.inode != inodeAncetre {
            sourceDossier?.cancel(); sourceDossier = nil
            sourceDossier = surveiller(ancetre, [.write, .delete, .rename, .link])
            surveille = sourceDossier == nil ? nil : (ancetre, inodeAncetre)
        }
        let chemin = dossier.appendingPathComponent(FichierSecondCerveau.nom).path
        if stat(chemin, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG {
            if sourceFichier == nil || inodeFichier != UInt64(st.st_ino) {
                sourceFichier?.cancel(); sourceFichier = nil
                sourceFichier = surveiller(chemin, [.write, .extend, .delete, .rename])
                inodeFichier = UInt64(st.st_ino)
            }
        } else {
            sourceFichier?.cancel(); sourceFichier = nil; inodeFichier = 0
        }
    }

    private func surveiller(_ chemin: String, _ masque: DispatchSource.FileSystemEvent) -> DispatchSourceFileSystemObject? {
        let fd = open(chemin, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let s = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: masque, queue: file)
        s.setEventHandler { [weak self] in self?.planifier() }
        s.setCancelHandler { close(fd) }
        s.resume()
        return s
    }
}

// MARK: - le contrôleur

extension IlotControleur {
    func demarrerSecondBrain() {
        secondBrainSource.demarrer(dossier: dossierSecondBrain(), lire: lireSecondBrain)
    }

    /// Le fichier a changé (ou vient d'être lu la première fois). Sans fichier valide, plus de case : si sa carte était ouverte, retour au Centre.
    func secondBrainLu(_ donnees: Data?) {
        let etat = SecondCerveauIlot.decoder(donnees)
        guard etat != moteur.secondBrain else { return }
        let avait = moteur.secondBrain != nil
        moteur.secondBrain = etat
        if etat != nil {
            if !avait { Log.ecrire("second brain : fichier d'état présent") }
            proposerSecondBrainAuCentre()
        } else {
            if avait { Log.ecrire("second brain : fichier d'état absent ou illisible, la case disparaît") }
            if moteur.courante == .secondBrain { moteur.allerA(.centre) }
        }
        moteur.donneesChangees()
    }

    /// La première fois que le fichier apparaît, son rond rejoint le Centre (s'il y a de la place : cinq ronds au plus). Ensuite, c'est
    /// « Modifier » qui décide : retiré, il ne revient pas tout seul.
    private func proposerSecondBrainAuCentre() {
        guard !reglagesCentre.secondBrainPropose(), !moteur.editionCentre else { return }
        var d = moteur.disposition
        if d.elements.contains(.secondBrain) || d.ajouter(.secondBrain, disponible: moteur.disponibleDansLeCentre) {
            moteur.disposition = d
            reglagesCentre.enregistrerDisposition(d.identifiants)
            reglagesCentre.marquerSecondBrainPropose()
            Log.ecrire("centre : \(d.identifiants.joined(separator: ", "))")
        }
    }

    /// Un clic sur une ligne de la carte (son lien) ou sur « Ouvrir Second Brain » (`lien` nil) : le lien de la ligne, sinon le lien
    /// général, sinon l'app si elle est installée, sinon rien. Seuls le schéma secondbrain:// et un document existant sont ouverts.
    func agirSecondBrain(_ lien: String?) {
        guard let sb = moteur.secondBrain else { return }
        guard let url = sb.aOuvrir(lienDeLaLigne: lien, existence: existenceSecondBrain, gestionnaire: gestionnaireSecondBrain, appInstallee: appSecondBrain) else {
            Log.ecrire("second brain : rien à ouvrir (ni lien valable ni app installée)")
            return
        }
        // pas d'adresse au journal : elle peut contenir un nom de personne ou de fiche
        Log.ecrire("second brain : ouverture demandée")
        moteur.fermer()
        ouvrir(url)
    }
}

// MARK: - les mesures de la carte

/// Les mesures de la carte (maquette, en points) : elles servent au dessin, à la hauteur de la forme et aux essais (où cliquer).
@MainActor
enum PlanSecondBrain {
    enum Partie: CaseIterable { case messages, taches, relances }
    /// Les mesures sont dans DicteeCore (`MesuresSecondBrain`, contrôlées) : 298 pt au plus, la hauteur du Centre.
    static let haut = CGFloat(MesuresSecondBrain.haut), entete = CGFloat(MesuresSecondBrain.entete), ecartEntete = CGFloat(MesuresSecondBrain.ecartEntete)
    static let pied = CGFloat(MesuresSecondBrain.pied), bas = CGFloat(MesuresSecondBrain.bas)
    static let ligne = CGFloat(MesuresSecondBrain.ligne), marge = CGFloat(MesuresSecondBrain.marge)
    /// La colonne du titre d'une partie (88 pt) et l'écart avec les lignes (10 pt).
    static let colonneTitre: CGFloat = 88, gouttiere: CGFloat = 10

    static func zone(_ g: GrilleIlot) -> CGRect { g.zoneCarte(.secondBrain, haut: haut, bas: bas) }
    static func cadreEntete(_ g: GrilleIlot) -> CGRect { let z = zone(g); return CGRect(x: z.minX, y: z.minY, width: z.width, height: entete) }
    static func hautPartie(_ n: Int) -> CGFloat { CGFloat(MesuresSecondBrain.hautPartie(n)) }
    /// Les parties montrées, avec leur nombre de lignes.
    static func parties(_ a: SecondCerveauIlot.Affichage) -> [(partie: Partie, n: Int)] {
        [(Partie.messages, a.messages.count), (.taches, a.taches.count), (.relances, a.relances.count)].filter { $0.1 > 0 }.map { (partie: $0.0, n: $0.1) }
    }
    static func corps(_ a: SecondCerveauIlot.Affichage) -> CGFloat { CGFloat(MesuresSecondBrain.corps(lignes: [a.messages.count, a.taches.count, a.relances.count])) }
    static func affichage(_ m: IlotMoteur) -> SecondCerveauIlot.Affichage {
        m.secondBrain?.affichage ?? SecondCerveauIlot.Affichage(messages: [], taches: [], relances: [])
    }
    /// La profondeur de la carte sous la barre : elle épouse ce qu'elle montre, jamais plus haute que le Centre.
    static func profondeur(_ m: IlotMoteur) -> CGFloat { CGFloat(MesuresSecondBrain.profondeur(affichage(m))) }
    static func cadreCorps(_ g: GrilleIlot, _ m: IlotMoteur) -> CGRect {
        let z = zone(g)
        return CGRect(x: z.minX, y: z.minY + entete + ecartEntete, width: z.width, height: corps(affichage(m)))
    }
    /// La ligne n° `j` de la partie `p` (essais : où cliquer).
    static func cadreLigne(_ p: Partie, _ j: Int, _ m: IlotMoteur, _ g: GrilleIlot? = nil) -> CGRect? {
        let g = g ?? m.grille
        let parties = parties(affichage(m))
        guard let k = parties.firstIndex(where: { $0.partie == p }), j < parties[k].n else { return nil }
        let c = cadreCorps(g, m)
        let avant = parties.prefix(k).map { hautPartie($0.n) + 1 }.reduce(0, +)
        return CGRect(x: c.minX + colonneTitre + gouttiere, y: c.minY + avant + marge + ligne * CGFloat(j),
                      width: c.width - colonneTitre - gouttiere, height: ligne)
    }
    static func pointLigne(_ p: Partie, _ j: Int, _ m: IlotMoteur) -> CGPoint? {
        cadreLigne(p, j, m).map { CGPoint(x: $0.minX + 30, y: $0.midY) }
    }
    /// La pilule « Ouvrir Second Brain », à droite du pied.
    static var largeurOuvrir: CGFloat { PiluleOutil.largeur("Ouvrir \(SecondCerveauIlot.nomApp)", taille: 13, padding: 14) }
    static func pointOuvrir(_ m: IlotMoteur) -> CGPoint {
        let z = zone(m.grille)
        return CGPoint(x: z.maxX - largeurOuvrir / 2, y: z.maxY - (pied - 1) / 2)
    }
    /// « ‹ Centre » dans l'en-tête.
    static func pointCentre(_ m: IlotMoteur) -> CGPoint { let e = cadreEntete(m.grille); return CGPoint(x: e.minX + 34, y: e.midY) }
}

// MARK: - le signe

/// Le signe provisoire de Second Brain (le logo n'est pas prêt) : quatre points reliés par des traits fins (maquette).
struct SigneSecondBrain: View {
    var taille: CGFloat
    var point: Color
    var trait: Color
    var body: some View {
        Canvas { ctx, size in
            let k = size.width / 20
            func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * k, y: y * k) }
            var l = Path()
            l.move(to: p(4.4, 6.6)); l.addLine(to: p(11.6, 3.6)); l.addLine(to: p(15.8, 11)); l.addLine(to: p(7.4, 16)); l.closeSubpath()
            l.move(to: p(11.6, 3.6)); l.addLine(to: p(7.4, 16))
            ctx.stroke(l, with: .color(trait), style: StrokeStyle(lineWidth: 1.15 * k, lineCap: .round, lineJoin: .round))
            for (x, y, r) in [(4.4, 6.6, 2.1), (11.6, 3.6, 1.75), (15.8, 11.0, 2.3), (7.4, 16.0, 1.9)] {
                ctx.fill(Path(ellipseIn: CGRect(x: (x - r) * k, y: (y - r) * k, width: 2 * r * k, height: 2 * r * k)), with: .color(point))
            }
        }
        .frame(width: taille, height: taille)
        .accessibilityHidden(true)
    }
}

// MARK: - la carte

struct CarteSecondBrain: View {
    @ObservedObject var m: IlotMoteur
    var g: GrilleIlot

    var body: some View {
        let v = VueIlot.secondBrain
        let z = PlanSecondBrain.zone(g)
        let a = PlanSecondBrain.affichage(m)
        ZStack(alignment: .topLeading) {
            // un clic dans le vide de la carte ne la range pas (on visait une ligne) ; seulement tant qu'elle est là
            Color.clear.contentShape(Rectangle()).onTapGesture {}
                .allowsHitTesting(m.courante == v)
                .accessibilityHidden(true)
                .posee(CGRect(x: -g.corps(v), y: g.barre, width: 2 * g.corps(v), height: max(0, g.hauteur(v) - g.barre)))
            entete.posee(PlanSecondBrain.cadreEntete(g), m.aspect(v, rang: 0), ancre: .topLeading)
            corps(a).posee(PlanSecondBrain.cadreCorps(g, m), m.aspect(v, rang: 1), ancre: .top)
            pied.posee(CGRect(x: z.minX, y: z.maxY - PlanSecondBrain.pied, width: z.width, height: PlanSecondBrain.pied), m.aspect(v, rang: 2), ancre: .top)
        }
        .frame(width: IlotMoteur.largeur, height: IlotMoteur.hauteurMax, alignment: .topLeading)
    }

    private var entete: some View {
        // la fraîcheur se calcule à l'ouverture de la carte (jamais de minuterie) : « il y a 2 min », « mis à jour hier », ou rien
        let fraicheur = m.secondBrain?.fraicheur(maintenant: m.maintenant())
        return HStack(spacing: 10) {
            PiluleCentre(titre: "Centre", retour: true, etiquette: "Revenir au Centre") { m.revenir() }.frame(width: PlanCarteClaude.pilule)
            HStack(spacing: 6) {
                SigneSecondBrain(taille: 15, point: .white, trait: Color.white.opacity(0.5))
                Text(SecondCerveauIlot.nomApp).font(.system(size: 13.5, weight: .bold)).foregroundStyle(.white)
                if let fraicheur { Text("\u{00B7} " + fraicheur).font(.system(size: 12, weight: .medium)).foregroundStyle(Color.white.opacity(0.45)) }
            }
            .lineLimit(1).fixedSize()
            .allowsHitTesting(false)
            Spacer(minLength: 0)
            ResteOuvert(m: m)
        }
        .frame(height: PlanSecondBrain.entete)
    }

    @ViewBuilder private func corps(_ a: SecondCerveauIlot.Affichage) -> some View {
        let sb = m.secondBrain
        let parties = PlanSecondBrain.parties(a)
        if parties.isEmpty {
            Text("Rien de neuf pour l\u{2019}instant")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(CouleursIlot.encre3).lineLimit(1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(parties.enumerated()), id: \.offset) { k, p in
                    if k > 0 { Rectangle().fill(Color.white.opacity(0.09)).frame(height: 1).allowsHitTesting(false) }
                    HStack(alignment: .top, spacing: PlanSecondBrain.gouttiere) {
                        titre(p.partie, sb, a).frame(width: PlanSecondBrain.colonneTitre, alignment: .topLeading)
                        VStack(spacing: 0) { lignes(p.partie, a) }
                    }
                    .padding(.vertical, PlanSecondBrain.marge)
                    .frame(height: PlanSecondBrain.hautPartie(p.n), alignment: .top)
                }
            }
        }
    }

    /// Le titre d'une partie et ce qu'il dit en dessous (« 2 à lire »).
    private func titre(_ p: PlanSecondBrain.Partie, _ sb: SecondCerveauIlot?, _ a: SecondCerveauIlot.Affichage) -> some View {
        let t: (titre: String, sous: String)? = {
            switch p {
            case .messages: return sb?.titreMessages(a)
            case .taches: return sb?.titreTaches(a)
            case .relances: return sb?.titreRelances(a)
            }
        }()
        return VStack(alignment: .leading, spacing: 2) {
            Text(t?.titre ?? "").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.white.opacity(0.6)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            if let s = t?.sous, !s.isEmpty { Text(s).font(.system(size: 11, weight: .medium)).foregroundStyle(Color.white.opacity(0.36)).lineLimit(1) }
        }
        .padding(.leading, 2).padding(.top, 4)
        .allowsHitTesting(false)
    }

    @ViewBuilder private func lignes(_ p: PlanSecondBrain.Partie, _ a: SecondCerveauIlot.Affichage) -> some View {
        // les dates du fichier (AAAA-MM-JJ, ISO) s'écrivent en français simple à l'ouverture de la carte : « demain », « le 20 », « depuis 22 jours »
        let t = m.maintenant(), cal = Calendar.current
        switch p {
        case .messages:
            ForEach(Array(a.messages.enumerated()), id: \.offset) { _, msg in
                LigneSecondBrain(m: m, lien: msg.lien, etiquette: [msg.nom, msg.texte ?? msg.resume, DateSecondCerveau.heure(msg.heure, calendrier: cal)].compactMap { $0 }.joined(separator: ", ")) {
                    Circle().fill(Color.white).frame(width: 6, height: 6)
                    nomEtTexte(nom: msg.nom, texte: msg.texte ?? msg.resume, blanc: false)
                    if let h = DateSecondCerveau.heure(msg.heure, calendrier: cal) { fin(h, ambre: false) }
                }
            }
        case .taches:
            ForEach(Array(a.taches.enumerated()), id: \.offset) { _, tache in
                LigneSecondBrain(m: m, lien: tache.lien, etiquette: [tache.texte, DateSecondCerveau.echeance(tache.echeance, maintenant: t, calendrier: cal)?.texte].compactMap { $0 }.joined(separator: ", ")) {
                    // la case est un dessin : l'îlot ne coche rien (cela se fait dans Second Brain)
                    RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Color.white.opacity(0.4), lineWidth: 1.4).frame(width: 13, height: 13)
                    Text(tache.texte).font(.system(size: 13, weight: .medium)).foregroundStyle(.white).lineLimit(1).truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let e = DateSecondCerveau.echeance(tache.echeance, maintenant: t, calendrier: cal) { fin(e.texte, ambre: e.alerte) }
                }
            }
        case .relances:
            ForEach(Array(a.relances.enumerated()), id: \.offset) { _, r in
                LigneSecondBrain(m: m, lien: r.lien, etiquette: [r.nom, r.sujet, DateSecondCerveau.depuis(r.depuis, maintenant: t, calendrier: cal)?.texte].compactMap { $0 }.joined(separator: ", ")) {
                    nomEtTexte(nom: r.nom, texte: r.sujet, blanc: false)
                    if let d = DateSecondCerveau.depuis(r.depuis, maintenant: t, calendrier: cal) { fin(d.texte, ambre: d.alerte) }
                }
            }
        }
    }

    /// Le nom en gras (sa largeur mesurée, bornée : il ne mange pas le texte), puis le texte en gris qui prend la place restante.
    @ViewBuilder private func nomEtTexte(nom: String?, texte: String?, blanc: Bool) -> some View {
        if let nom {
            Text(nom).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1).truncationMode(.tail)
                .frame(width: min(MesureIlot.texte(nom, 13, .semibold), 120), alignment: .leading)
        }
        Text(texte ?? "").font(.system(size: 13, weight: .medium)).foregroundStyle(Color.white.opacity(blanc ? 1 : 0.55)).lineLimit(1).truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Ce qui est tout à droite d'une ligne (l'heure, l'échéance, depuis quand) : sa largeur mesurée.
    private func fin(_ t: String, ambre: Bool) -> some View {
        Text(t).font(.system(size: 11.5, weight: ambre ? .semibold : .medium).monospacedDigit())
            .foregroundStyle(ambre ? Color(hex: 0xFFB340) : Color.white.opacity(0.4)).lineLimit(1)
            .frame(width: min(MesureIlot.texte(t, 11.5, ambre ? .semibold : .medium, chiffres: true), 90), alignment: .trailing)
    }

    private var pied: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1).allowsHitTesting(false)
            HStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill").font(.system(size: 10.5, weight: .semibold))
                    Text("Lu sur ce Mac seulement").font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(Color.white.opacity(0.5))
                .allowsHitTesting(false)
                Spacer(minLength: 0)
                PiluleOutil(titre: "Ouvrir \(SecondCerveauIlot.nomApp)", style: .blanc, hauteur: 28, taille: 13, padding: 14,
                            etiquette: "Ouvrir \(SecondCerveauIlot.nomApp)") { m.surAction(.secondBrainOuvrir(nil)) }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

/// Une ligne de la carte : un fond qui prend le clic (et s'éclaire au survol), le contenu par-dessus qui n'en prend aucun.
struct LigneSecondBrain<Contenu: View>: View {
    @ObservedObject var m: IlotMoteur
    var lien: String?
    var etiquette: String
    @ViewBuilder var contenu: () -> Contenu
    @State private var survol = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(survol ? 0.1 : 0.001))
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .onTapGesture { m.surAction(.secondBrainOuvrir(lien)) }
            HStack(spacing: 8, content: contenu)
                .padding(.horizontal, 8)
                .allowsHitTesting(false)
        }
        .frame(height: PlanSecondBrain.ligne)
        .onHover { survol = $0 }
        .animation(.easeOut(duration: 0.12), value: survol)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(etiquette)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Ouvrir dans \(SecondCerveauIlot.nomApp)") { m.surAction(.secondBrainOuvrir(lien)) }
    }
}
