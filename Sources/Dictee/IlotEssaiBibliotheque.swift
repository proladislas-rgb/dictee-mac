import AppKit
import DicteeCore

extension IlotEssai {
    /// La Bibliothèque (maquette ilot-bibliotheque.html, étapes 1 à 6) : la ligne « Bibliothèque · Tout voir » de la carte Étagère, la
    /// carte (filtre, recherche au clavier pris SEULEMENT pendant la saisie, tri, épingler, retirer + Annuler, plusieurs choisis, ouvrir un
    /// fichier, défilement de la liste), les sources (dossiers TEMPORAIRES : jamais Téléchargements ni le Bureau), le fichier 0600, « En
    /// grand ». De VRAIS clics, de vraies touches et de vrais défilements remis à la fenêtre invisible ; aucun fichier n'est copié ni
    /// déplacé, aucune ouverture réelle (capturée), rien n'est écrit hors du dossier temporaire.
    @MainActor
    static func bibliotheque(_ c: IlotControleur, dossier: URL, verifier: (Bool, String) -> Void, attendre: (Double, () -> Bool) -> Void,
                             fenetres: () -> [Onglet], relancer: () -> IlotControleur) {
        let m = c.moteur, b = m.bibliotheque, mo = c.bibliotheque
        // les fichiers ouverts : capturés ici (jamais une ouverture réelle) ; rendu à la fin
        var ouvertsIci: [URL] = []
        let ouvrirAvant = c.ouvrir
        c.ouvrir = { ouvertsIci.append($0) }
        defer { c.ouvrir = ouvrirAvant }
        func ouverts() -> [URL] { ouvertsIci }
        let barre = Double(m.geometrie.hauteur), hc = Double(m.demiCamera)
        let fm = FileManager.default
        func pause(_ s: Double) { attendre(s) { true } }
        func clic(_ p: CGPoint, _ apres: Double = 0.5) {
            c.panneau.envoyerSouris(.leftMouseDown, en: p); pause(0.06); c.panneau.envoyerSouris(.leftMouseUp, en: p); pause(apres)
        }
        func refermer() { c.panneau.simulerPointeur(forme: false); m.fermer(); pause(0.8) }
        func poseeSurLaCible() { attendre(1.5) { !m.geo.allSatisfy(\.fini) } }
        func ligne(_ nom: String) -> EntreeBibliotheque? { b.miseEnPage().affichees.first { $0.nom == nom } }
        /// Fait défiler la liste pour que la ligne soit à l'écran (comme la molette), puis la « survole ».
        func viser(_ nom: String) -> EntreeBibliotheque? {
            guard let x = ligne(nom), let e = b.miseEnPage().elements.first(where: { $0.id == x.id }) else { return nil }
            if PlanBibliotheque.cadreLigne(x.id, m) == nil { b.decalage = CarteBibliotheque.borner(e.y - 40, liste: b.miseEnPage().hauteur) }
            b.survol = x.id; pause(0.15)
            return x
        }
        let ouvertsAvant = ouverts().count

        print("La Bibliothèque")
        // des fichiers de la maquette, dans des dossiers temporaires (des octets quelconques : rien n'est ouvert pour de vrai)
        let rayon = dossier.appendingPathComponent("Rayon-bibliotheque", isDirectory: true)
        let dl = mo.dossiers.telechargements, cap = mo.dossiers.captures
        for d in [rayon, dl, cap] { try? fm.createDirectory(at: d, withIntermediateDirectories: true) }
        func fichier(_ d: URL, _ nom: String, _ octets: Int, il heures: Double = 0, airdrop: Bool = false) -> URL {
            let u = d.appendingPathComponent(nom)
            fm.createFile(atPath: u.path, contents: Data(repeating: 0x7A, count: octets))
            if heures > 0 { try? fm.setAttributes([.creationDate: Date().addingTimeInterval(-heures * 3600)], ofItemAtPath: u.path) }
            if airdrop { let q = "0081;6731f2a0;sharingd;"; _ = setxattr(u.path, "com.apple.quarantine", q, q.utf8.count, 0, 0) }
            return u
        }
        let devis = fichier(rayon, "Devis-cuisine.pdf", 212_000), plan = fichier(rayon, "Plan-salon.jpg", 2_100), contrat = fichier(rayon, "Contrat.pdf", 184_000)
        let lettre = fichier(rayon, "Lettre-banque.docx", 31_000)
        _ = fichier(dl, "Facture-EDF.pdf", 88_000, il: 5); _ = fichier(dl, "Budget-2026.xlsx", 48_000, il: 30); _ = fichier(dl, "Billet-train-Lyon.pdf", 96_000, il: 100)
        _ = fichier(dl, "Photo-chantier.heic", 3_400, il: 3, airdrop: true); _ = fichier(dl, "Devis-salle-de-bain.pdf", 236_000, il: 50, airdrop: true)
        _ = fichier(dl, "Film.mp4.crdownload", 10)
        let capture = fichier(cap, "Capture d\u{2019}écran 2026-11-11 à 14.32.15.png", 1_200, il: 0.2)
        _ = fichier(cap, "Notes du Bureau.txt", 20)

        // --- l'étagère reçoit quatre fichiers : la bibliothèque les garde (fichier 0600, des signets, aucune copie)
        refermer()
        // le Centre tel qu'il est la première fois (l'essai de « Modifier » l'a changé), sa case Étagère comprise
        m.disposition = DispositionCentre()
        c.etagere.vider(); c.sauverEtagere(); c.activerEtagere(true)
        // la bibliothèque repart de zéro (les sections d'avant ont rangé d'autres fichiers sur l'étagère, qu'elle a gardés)
        mo.remplacer(BibliothequeIlot())
        c.ranger([devis, plan, contrat, lettre]); pause(0.3)
        verifier(mo.bib.entrees.count == 4 && mo.bib.entrees.allSatisfy { $0.source == .etagere && $0.signet != nil }, "l'étagère range 4 fichiers : la bibliothèque les garde aussi (signets, source Étagère)")
        let droits = mo.store.url.flatMap { try? fm.attributesOfItem(atPath: $0.path)[.posixPermissions] as? Int } ?? -1
        verifier(droits == 0o600, "bibliotheque.json écrit en 0600 (\(String(droits, radix: 8)))")
        verifier([devis, plan, contrat, lettre].allSatisfy { fm.fileExists(atPath: $0.path) } && (try? fm.contentsOfDirectory(atPath: rayon.path).count) == 4,
                 "rien n'est copié ni déplacé : les 4 fichiers sont où ils étaient, seuls")
        let texte = mo.store.url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        verifier(texte.contains("Devis-cuisine.pdf") && !texte.contains("zzzzzzzz"), "le fichier garde des chemins et des signets, jamais le contenu des fichiers")

        // --- étape 1 : le Centre, un vrai clic sur la case Étagère ; en bas, « Bibliothèque · Tout voir »
        m.clicForme(); pause(0.9)
        let ce = PlanCentre.cadreCase(m, .etagere)
        clic(CGPoint(x: ce.minX + 60, y: ce.minY + 11 + 8), 0.9)
        verifier(m.courante == .etagere, "vrai clic sur la case Étagère : la carte Étagère (\(m.courante))")
        poseeSurLaCible()
        let hEt = barre + GeoIlot.profondeur(.etagere)
        verifier(abs(m.geo[2].x - hEt) < 0.5, "carte Étagère avec sa ligne « Bibliothèque » : \(Int(m.geo[2].x)) pt (attendu \(Int(hEt))), les tuiles toujours là (\(m.etagere.count))")
        let ze = m.grille.zone(.etagere, haut: 10, bas: 12)
        clic(CGPoint(x: ze.midX, y: ze.maxY - 24), 0.9)
        verifier(m.courante == .bibliotheque && m.epingle, "étape 2 : vrai clic sur « Bibliothèque · Tout voir » : la carte Bibliothèque, qui reste ouverte (\(m.courante))")
        attendre(1.0) { b.miseEnPage().affichees.count < 4 }
        poseeSurLaCible()
        let p0 = b.miseEnPage()
        verifier(p0.affichees.count == 4 && p0.elements.first.map { if case .groupe(let t, _) = $0.genre { return t == "Aujourd\u{2019}hui" }; return false } == true,
                 "sources éteintes : les 4 fichiers de l'étagère, sous « Aujourd'hui »")
        let h0 = barre + CarteBibliotheque.profondeur(liste: p0.hauteur)
        verifier(abs(m.geo[2].x - h0) < 0.5, "l'îlot épouse la liste (\(Int(m.geo[2].x)) pt, attendu \(Int(h0)))")
        verifier(m.trace.bande <= hc + GeoIlot.aileMax + 0.01, "Bibliothèque : \(String(format: "%.1f", m.trace.bande - hc)) pt dans la barre de chaque côté (≤ 66)")
        if let f = c.panneau.cadre { verifier(Double(f.height) >= m.trace.hauteur && Double(f.width) >= 2 * m.trace.corps, "la fenêtre couvre la carte") }
        attendre(1.5) { m.boucleActive }
        verifier(!m.boucleActive, "Bibliothèque posée : aucune boucle d'animation (bouge encore : \(m.ceQuiBouge))")
        verifier(!c.panneau.clavierPris && !b.rechercheActive, "arrivée sur la carte : le clavier reste à l'app au premier plan")
        // ce qui doit tenir : l'en-tête, les six pastilles, le pied
        let ent = PlanBibliotheque.cadreEntete(m.grille), puces = PlanBibliotheque.cadrePuces(m.grille), pied = PlanBibliotheque.cadrePied(m.grille)
        verifier(PlanBibliotheque.largeurRetour + 8 + 140 + 8 + PlanBibliotheque.largeurTri <= ent.width, "en-tête : « ‹ Étagère », au moins 140 pt de champ, « Récents » (\(Int(ent.width)) pt)")
        let tp = PlanBibliotheque.taillePuces(puces.width)
        verifier(PlanBibliotheque.largeurPuces(tp) <= puces.width && tp >= 11.5, "six pastilles mesurées : \(Int(PlanBibliotheque.largeurPuces(tp))) pt à \(tp) pt de texte, tiennent dans \(Int(puces.width))")
        verifier(PlanBibliotheque.largeurPiedNote <= pied.width, "pied « Rien n'est copié… En grand » : \(Int(PlanBibliotheque.largeurPiedNote)) pt mesurés, tiennent dans \(Int(pied.width))")

        // --- les sources : allumées d'un clic (l'interrupteur de la fenêtre), leurs dossiers lus hors du fil principal
        for s in SourceBibliotheque.optionnelles { mo.allumer(s, true) }
        attendre(2.0) { b.miseEnPage().affichees.count < 9 }
        let tous = b.miseEnPage().affichees
        verifier(tous.count == 10, "Téléchargés, AirDrop, Captures allumés : 4 + 5 + 1 fichiers (\(tous.count)) ; un téléchargement en cours et un texte du dossier des captures ignorés")
        verifier(ligne("Photo-chantier.heic")?.source == .airdrop && ligne("Facture-EDF.pdf")?.source == .telecharges && ligne(capture.lastPathComponent)?.sorte == .capture,
                 "AirDrop reconnu (quarantaine de sharingd), téléchargé, capture")
        verifier(b.defile, "dix fichiers : la liste défile dans la carte")
        poseeSurLaCible()
        verifier(abs(m.geo[2].x - (barre + CarteBibliotheque.profondeurMax)) < 0.5, "la carte à son plus haut (\(Int(m.geo[2].x)) pt)")

        // --- étape 3 : un filtre (vrai clic sur « Documents »), une recherche (vrai clic dans le champ, vraies touches)
        clic(PlanBibliotheque.pointPuce(.documents, m.grille), 0.4)
        verifier(b.filtre == .documents && b.miseEnPage().affichees.allSatisfy { $0.sorte == .document }, "vrai clic sur « Documents » : les documents seuls (\(b.miseEnPage().affichees.count))")
        clic(PlanBibliotheque.pointChamp(m.grille), 0.4)
        verifier(b.rechercheActive && c.panneau.clavierPris && !c.panneau.estCle, "vrai clic dans « Rechercher un fichier » : le champ prend le clavier (essai : jamais la vraie fenêtre clé)")
        attendre(1.0) { !c.panneau.champAuPremierPlan }
        verifier(c.panneau.champAuPremierPlan, "le vrai champ de texte est posé, premier répondant")
        c.panneau.envoyerTouches("dévis"); pause(0.5)
        let trouves = b.miseEnPage().affichees.map(\.nom)
        verifier(b.requete == "dévis" && Set(trouves) == ["Devis-cuisine.pdf", "Devis-salle-de-bain.pdf"],
                 "vraies touches « dévis » : les deux devis, d'où qu'ils viennent (sans accents) (\(trouves))")
        poseeSurLaCible()
        verifier(m.geo[2].x < barre + CarteBibliotheque.profondeurMax - 40, "l'îlot se resserre autour des deux devis (\(Int(m.geo[2].x)) pt)")
        c.panneau.envoyerTouche(code: 53, caractere: "\u{1b}"); pause(0.3)
        verifier(b.requete.isEmpty && b.rechercheActive, "Échap : la recherche s'efface, le champ garde le clavier")
        c.panneau.envoyerTouche(code: 53, caractere: "\u{1b}"); pause(0.3)
        verifier(!b.rechercheActive && !c.panneau.clavierPris && m.courante == .bibliotheque, "Échap encore : le clavier est rendu, la carte reste")
        clic(PlanBibliotheque.pointPuce(.tout, m.grille), 0.4)
        verifier(b.filtre == .tout, "vrai clic sur « Tout »")
        // le tri
        clic(PlanBibliotheque.pointTri(m.grille), 0.3)
        let anciens = b.miseEnPage().affichees
        verifier(!b.recents && anciens.first?.nom == "Billet-train-Lyon.pdf", "vrai clic sur « Récents » : « Anciens », le plus ancien en tête (\(anciens.first?.nom ?? "?"))")
        clic(PlanBibliotheque.pointTri(m.grille), 0.3)
        verifier(b.recents && b.miseEnPage().affichees.first?.source == .etagere, "et de nouveau « Récents » : les fichiers rangés à l'instant sur l'étagère en tête")

        // --- étape 4 : épingler (survol, vrai clic sur la punaise), retirer (vrai clic sur « Retirer »), « Annuler »
        guard let pl = viser("Plan-salon.jpg") else { verifier(false, "Plan-salon.jpg dans la liste"); return }
        if let p = PlanBibliotheque.pointPunaise(pl.id, m) { clic(p, 0.4) } else { verifier(false, "la ligne Plan-salon.jpg est à l'écran") }
        let pe = b.miseEnPage()
        verifier(mo.bib.entrees.first { $0.nom == "Plan-salon.jpg" }?.epinglee == true && pe.affichees.first?.nom == "Plan-salon.jpg"
                 && { if case .groupe(let t, let ep) = pe.elements[0].genre { return ep && t == "Épinglés" }; return false }(),
                 "vrai clic sur la punaise : Plan-salon.jpg épinglé, tout en haut sous « Épinglés »")
        b.decalage = 0
        guard let lc = viser(capture.lastPathComponent) else { verifier(false, "la capture dans la liste"); return }
        if let p = PlanBibliotheque.pointRetirer(lc.id, m) { clic(p, 0.4) } else { verifier(false, "la ligne de la capture est à l'écran") }
        verifier(ligne(capture.lastPathComponent) == nil && b.retrait?.entree.nom == capture.lastPathComponent && fm.fileExists(atPath: capture.path),
                 "vrai clic sur « Retirer » : la capture quitte la bibliothèque ; le fichier, lui, est toujours là")
        verifier(mo.dossier(lc) == "Captures", "le pied le dit : « Retiré d'ici. Le fichier reste dans Captures. » (\(mo.dossier(lc)))")
        clic(PlanBibliotheque.pointLienPied("Annuler", symbole: false, m.grille), 0.4)
        verifier(ligne(capture.lastPathComponent) != nil && b.retrait == nil, "vrai clic sur « Annuler » : elle revient")
        _ = viser(capture.lastPathComponent)
        if let p = PlanBibliotheque.pointRetirer(lc.id, m) { clic(p, 0.4) }
        mo.rafraichir(force: true); pause(0.8)
        verifier(ligne(capture.lastPathComponent) == nil, "retirée de nouveau : la relecture du dossier des captures ne la ramène pas")
        let relu = relancer().bibliotheque
        verifier(relu.bib.entrees.first { $0.nom == "Plan-salon.jpg" }?.epinglee == true && relu.bib.masques.count == 1, "après relance : l'épinglé et le retrait sont relus depuis le fichier")

        // --- étape 5 : plusieurs à la fois (vrais clics sur les petits ronds), « Glisser les 3 »
        b.survol = nil
        for nom in ["Devis-cuisine.pdf", "Plan-salon.jpg", "Contrat.pdf"] {
            guard let x = viser(nom) else { verifier(false, "\(nom) dans la liste"); continue }
            if let p = PlanBibliotheque.pointRond(x.id, m) { clic(p, 0.25) } else { verifier(false, "le rond de \(nom) est à l'écran") }
        }
        verifier(b.choisis.count == 3 && Set(b.fichiersChoisis.map(\.nom)) == ["Devis-cuisine.pdf", "Plan-salon.jpg", "Contrat.pdf"], "trois vrais clics sur les ronds : 3 choisis (\(b.choisis.count))")
        let elements = VueGlisserFichiers.elements(b.fichiersChoisis.map { (URL(fileURLWithPath: $0.chemin), mo.icone($0)) }, dans: NSRect(x: 0, y: 0, width: 100, height: 26))
        let urls = elements.compactMap { ($0.item as? NSURL) as URL? }
        verifier(elements.count == 3 && urls.allSatisfy(\.isFileURL) && Set(urls.map(\.lastPathComponent)) == ["Devis-cuisine.pdf", "Plan-salon.jpg", "Contrat.pdf"],
                 "« Glisser les 3 » prépare trois éléments (un par fichier : Mail en fait 3 pièces jointes)")
        // pendant un choix, un clic sur une ligne choisit (il n'ouvre rien)
        if let x = viser("Lettre-banque.docx"), let p = PlanBibliotheque.pointNom(x.id, m) { clic(p, 0.3) }
        verifier(b.choisis.count == 4 && ouverts().count == ouvertsAvant, "pendant un choix, un clic sur une ligne la choisit aussi (rien n'est ouvert)")
        b.glisserFini(depose: true)
        verifier(b.choisis.isEmpty && mo.bib.entrees.count >= 4, "glissés et déposés : le choix se vide, les fichiers restent dans la bibliothèque")
        if let x = viser("Contrat.pdf"), let p = PlanBibliotheque.pointRond(x.id, m) { clic(p, 0.25) }
        clic(PlanBibliotheque.pointLienPied("Annuler", symbole: false, m.grille), 0.3)
        verifier(b.choisis.isEmpty, "vrai clic sur « Annuler » du pied : plus rien n'est choisi")

        // --- la liste défile sous la molette (vrais défilements) ; ailleurs, la carte ne change pas
        b.decalage = 0; pause(0.1)
        let liste = PlanBibliotheque.cadreListe(m.grille)
        let surListe = CGPoint(x: liste.midX - 30, y: liste.midY)
        c.panneau.envoyerDefilement(dy: -12, en: surListe, phase: 1); pause(0.02)
        c.panneau.envoyerDefilement(dy: -18, en: surListe, phase: 2); pause(0.02)
        c.panneau.envoyerDefilement(dy: 0, en: surListe, phase: 4); pause(0.3)
        verifier(abs(b.decalage - 30) < 0.5 && m.courante == .bibliotheque, "deux doigts sur la liste : elle défile de 30 pt, la carte reste (\(Int(b.decalage)))")
        c.panneau.envoyerDefilement(dy: -2000, en: surListe, phase: 1); pause(0.02); c.panneau.envoyerDefilement(dy: 0, en: surListe, phase: 4); pause(0.3)
        verifier(abs(b.decalage - (b.miseEnPage().hauteur - Double(liste.height))) < 0.5, "jusqu'au bout : la dernière ligne entière")
        let surPied = CGPoint(x: pied.midX, y: pied.midY)
        c.panneau.envoyerDefilement(dy: -20, en: surPied, phase: 1); pause(0.02); c.panneau.envoyerDefilement(dy: 0, en: surPied, phase: 4); pause(0.5)
        verifier(m.courante == .bibliotheque, "un geste sur le pied : la carte ne change pas (« ‹ Étagère » pour revenir)")
        b.decalage = 0; pause(0.2)

        // --- quitter la carte rend le clavier ; « ‹ Étagère » ; une dictée qui commence
        clic(PlanBibliotheque.pointChamp(m.grille), 0.4)
        verifier(c.panneau.clavierPris, "le champ a de nouveau le clavier")
        clic(PlanBibliotheque.pointRetour(m.grille), 0.7)
        verifier(m.courante == .etagere && !b.rechercheActive && !c.panneau.clavierPris, "vrai clic sur « ‹ Étagère » : la carte Étagère, le clavier rendu (\(m.courante))")
        m.ouvrirBibliotheque(); pause(0.8)
        clic(PlanBibliotheque.pointChamp(m.grille), 0.4)
        var occ = OccupationEncoche(); c.occupation = { occ }
        occ.dictee = true; c.occupationChangee(); pause(0.3)
        verifier(!b.rechercheActive && !c.panneau.clavierPris && m.cache, "une dictée commence pendant la recherche : l'îlot s'efface et rend le clavier (le texte ira dans l'app)")
        occ.dictee = false; c.occupationChangee(); c.occupation = { OccupationEncoche() }; pause(0.8)

        // --- un bandeau pendant que la carte est ouverte attend qu'elle se range
        c.panneau.simulerPointeur(forme: true); pause(1.0)
        m.ouvrirEtagere(); pause(0.4); m.ouvrirBibliotheque(); pause(0.8)
        m.annoncer(bandeau: BandeauIlot(vue: .appareil, jusqua: c.maintenant().addingTimeInterval(3.5), ligne1: "AirPods Pro", ligne2: "",
                                        appareil: AppareilIlot(nom: "AirPods Pro", genre: .ecouteurs, gauche: 80, droit: 78, etui: 45)))
        pause(0.4)
        verifier(m.courante == .bibliotheque && m.bandeau == nil, "« AirPods connectés » pendant la Bibliothèque : elle reste, le bandeau attend")

        // --- un clic sur une ligne ouvre le fichier (capturé), l'îlot se range
        b.decalage = 0
        poseeSurLaCible(); attendre(1.0) { m.boucleActive }
        let courantAvant = m.courante
        let nOuverts = ouverts().count
        if let x = viser("Devis-cuisine.pdf"), let p = PlanBibliotheque.pointNom(x.id, m) { clic(p, 0.1) } else { print("  (Devis-cuisine.pdf hors de la liste : \(b.miseEnPage().affichees.map(\.nom)))") }
        // le fichier s'ouvre une fois son signet relu (hors du fil principal) : on l'attend, 3 s au plus
        for _ in 0..<30 where ouverts().count == nOuverts { pause(0.1) }
        verifier(ouverts().last.map { SignetsEtagere.cheminReel($0) } == SignetsEtagere.cheminReel(devis) && m.courante != .bibliotheque,
                 "vrai clic sur une ligne : le fichier est ouvert (capturé, jamais réel), l'îlot se range (\(ouverts().last?.lastPathComponent ?? "rien"), \(courantAvant) → \(m.courante))")
        attendre(5.0) { m.bandeau != nil || m.courante == .appareil }; c.panneau.simulerPointeur(forme: false); pause(1.0)
        verifier(b.requete.isEmpty && b.choisis.isEmpty && b.decalage == 0, "l'îlot rangé : la carte repart de zéro")

        // --- un fichier supprimé quitte la bibliothèque à l'ouverture
        try? fm.removeItem(at: lettre)
        m.clicForme(); pause(0.6); m.ouvrirEtagere(); pause(0.4); m.ouvrirBibliotheque()
        attendre(1.5) { ligne("Lettre-banque.docx") != nil }
        verifier(ligne("Lettre-banque.docx") == nil && !mo.bib.entrees.contains { $0.nom == "Lettre-banque.docx" }, "un fichier supprimé : il quitte la bibliothèque à l'ouverture de la carte")

        // --- « En grand » : l'onglet Bibliothèque de la fenêtre, l'îlot se range
        poseeSurLaCible(); attendre(1.0) { m.boucleActive }
        clic(PlanBibliotheque.pointLienPied("En grand", symbole: true, m.grille), 0.6)
        verifier(fenetres().last == .bibliotheque && m.courante != .bibliotheque, "vrai clic sur « En grand » : la fenêtre de Verbe sur l'onglet Bibliothèque, l'îlot se range (\(fenetres().last.map(\.rawValue) ?? "rien"), \(m.courante))")
        refermer()

        // --- l'étagère vide, la bibliothèque pleine : la case du Centre ouvre quand même la carte (et sa ligne)
        c.agir(.etagereVider); pause(0.3)
        m.clicForme(); pause(0.9)
        clic(CGPoint(x: ce.minX + 60, y: ce.minY + 11 + 8), 0.9)
        verifier(m.courante == .etagere && m.etagere.isEmpty && mo.bib.entrees.count >= 3, "étagère vidée (la bibliothèque garde tout) : la case Étagère ouvre la carte, et sa ligne « Bibliothèque »")
        refermer()

        // --- « Réduire les animations » : la carte est posée tout de suite
        m.reduire = true
        m.clicForme(); pause(0.6); m.ouvrirEtagere(); pause(0.3); m.ouvrirBibliotheque(); pause(0.05)
        verifier(m.geo.allSatisfy(\.fini) && m.courante == .bibliotheque, "Réduire les animations : la Bibliothèque est posée tout de suite")
        m.reduire = false
        refermer()
        attendre(1.3) { m.boucleActive }
        verifier(!m.boucleActive, "refermé : aucune boucle d'animation")
        for s in SourceBibliotheque.optionnelles { mo.allumer(s, false) }
    }
}
