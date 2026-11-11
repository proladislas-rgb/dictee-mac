import AppKit
import UniformTypeIdentifiers
import SwiftUI
import DicteeCore

// « L'étagère » (maquette design/maquettes/ilot-apple.html, cinq idées de plus, 2) : on glisse des fichiers sur l'encoche, ils y restent ;
// on les reprend plus tard en les glissant hors de l'îlot. Verbe garde un SIGNET de chaque fichier (le Mac le retrouve même déplacé ou
// renommé), jamais une copie : un fichier supprimé quitte l'étagère. La logique pure est dans DicteeCore/EtagereIlot.swift ; le glisser
// lui-même (moniteur, fenêtre qui accepte les fichiers) dans IlotPanneau.swift.

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

    /// Des fichiers ont été lâchés sur l'îlot : un signet pour chacun, sans doublon. Rend le nombre de fichiers rangés.
    @discardableResult
    func ranger(_ urls: [URL]) -> Int {
        let t = maintenant()
        let r = etagere.ajouter(urls.compactMap { SignetsEtagere.element($0, a: t) })
        for e in r.sortis { iconesEtagere[e.id] = nil }
        // les fichiers viennent d'être lâchés (donc accessibles) : leur icône est lue tout de suite
        for e in r.ajoutes { iconesEtagere[e.id] = NSWorkspace.shared.icon(forFile: e.chemin) }
        sauverEtagere()
        montrerEtagere()
        // jamais de nom de fichier au journal
        Log.ecrire("étagère : \(r.ajoutes.count) rangé(s), \(r.doublons) déjà là, \(r.sortis.count) sorti(s) pour faire de la place")
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
            FichierEtagere(id: e.id, nom: e.nom, url: URL(fileURLWithPath: e.chemin), icone: iconesEtagere[e.id] ?? SignetsEtagere.iconeDuType(e.chemin))
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
            etagere.vider(); iconesEtagere = [:]; sauverEtagere(); montrerEtagere()
        default: break
        }
    }
}

// MARK: vues

/// Une tuile de l'étagère : l'icône du Finder et le nom (coupé au milieu, l'extension reste). Dans la carte, un clic ouvre le fichier,
/// on la glisse vers une app (le fichier lui-même, comme depuis le Finder), et un « × » paraît au survol pour la retirer.
struct TuileEtagere: View {
    static let hauteur: CGFloat = 70, espace: CGFloat = 8, icone: CGFloat = 40
    /// Cinq tuiles sur la largeur de la zone.
    static func largeur(_ zone: CGFloat) -> CGFloat { floor((zone - CGFloat(EtagereIlot.parRangee - 1) * espace) / CGFloat(EtagereIlot.parRangee)) }

    var fichier: FichierEtagere
    var largeur: CGFloat
    /// Le moteur, prévenu quand la tuile est glissée hors de la carte (nil dans l'accueil, où les tuiles ne se prennent pas).
    var m: IlotMoteur?
    var actions = false
    var ouvrir: () -> Void = {}
    var retirer: () -> Void = {}
    @State private var survol = false

    var body: some View {
        if actions {
            contenu
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .onTapGesture { ouvrir() }
                .glisserFichier(fichier.url, m)
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
                .onHover { survol = $0 }
                .animation(.easeOut(duration: 0.12), value: survol)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(fichier.nom)
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
    }
}

/// « Déposez ici » (maquette : cadre pointillé de 14 pt de rayon). Il s'éclaire quand le pointeur qui glisse est sur l'îlot.
struct ZoneDepot: View {
    var survolee: Bool
    var animer: Bool
    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.white.opacity(survolee ? 0.1 : 0))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(survolee ? 0.72 : 0.28), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
            .overlay {
                HStack(spacing: 7) {
                    Image(systemName: "tray.and.arrow.down.fill").font(.system(size: 14, weight: .semibold))
                    Text("Déposez ici").font(.system(size: 12.5, weight: .semibold))
                }
                .foregroundStyle(Color.white.opacity(survolee ? 0.95 : 0.55))
            }
            .scaleEffect(survolee && animer ? 1.025 : 1)
            .animation(animer ? .spring(response: 0.3, dampingFraction: 0.72) : nil, value: survolee)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Déposez ici : les fichiers restent sur l\u{2019}étagère")
    }
}

/// L'îlot pendant qu'on glisse des fichiers près de l'encoche : les trois derniers fichiers rangés, puis « Déposez ici » sur la place
/// qui reste (seul, s'il n'y a encore rien).
struct DepotEtagere: View {
    @ObservedObject var m: IlotMoteur
    var g: GrilleIlot
    var body: some View {
        let v = VueIlot.etagereDepot
        let z = g.zone(v)
        let lt = TuileEtagere.largeur(z.width)
        let derniers = Array(m.etagere.suffix(3))
        HStack(spacing: TuileEtagere.espace) {
            ForEach(Array(derniers.enumerated()), id: \.element.id) { i, f in
                TuileEtagere(fichier: f, largeur: lt).aspectIlot(m.aspect(v, rang: i), ancre: .center)
            }
            ZoneDepot(survolee: m.depotSurvole, animer: !m.reduire && !m.statique)
                .frame(height: 70)
                .aspectIlot(m.aspect(v, rang: derniers.count), ancre: .center)
        }
        .frame(width: z.width, height: z.height, alignment: .leading)
        .offset(x: IlotMoteur.largeur / 2 + z.minX, y: z.minY)
    }
}

/// La carte Étagère (depuis la case Étagère du Centre) : « ‹ Centre », l'en-tête et « Tout vider », puis les fichiers, cinq par rangée.
struct CarteEtagere: View {
    @ObservedObject var m: IlotMoteur
    var g: GrilleIlot
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
                    Text(n == 0 ? "Vide" : EtagereIlot.resume(n) + " \u{00B7} glisse-les vers une app")
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
        }
        .frame(width: z.width, height: z.height, alignment: .top)
        .offset(x: IlotMoteur.largeur / 2 + z.minX, y: z.minY)
    }
}
