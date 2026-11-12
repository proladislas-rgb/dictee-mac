import Foundation
import DicteeCore

/// La Bibliothèque (maquette ilot-bibliotheque.html, étapes 1 à 6) : ce qu'elle garde (l'historique de l'étagère, sans doublon, plafond,
/// épinglés), les sources, « Retirer » et « Annuler », les filtres, la recherche sans accents, le tri, les groupes par date, le fichier,
/// et la géométrie de la carte.
func controlesBibliotheque(_ t0: Date) {
    var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Europe/Paris")!; cal.firstWeekday = 2
    // t0 : mardi 10 novembre 2026, 14 h 32
    func il(_ h: Double) -> Date { t0.addingTimeInterval(-h * 3600) }
    func e(_ chemin: String, _ src: SourceBibliotheque, _ h: Double, taille: Int64? = nil, id: String? = nil) -> EntreeBibliotheque {
        EntreeBibliotheque(id: id, chemin: chemin, signet: Data(chemin.utf8), source: src, date: il(h), taille: taille)
    }

    groupe("Bibliothèque : sortes, sources, filtres")
    verifier(SorteFichier.de(nom: "Devis-cuisine.pdf", source: .etagere) == .document && SorteFichier.de(nom: "Budget.XLSX", source: .telecharges) == .document,
             "PDF, XLSX (majuscules) : documents")
    verifier(SorteFichier.de(nom: "Photo-chantier.heic", source: .airdrop) == .image && SorteFichier.de(nom: "Plan.jpg", source: .etagere) == .image, "HEIC, JPG : images")
    verifier(SorteFichier.de(nom: "Capture d\u{2019}écran 2026-11-11 à 14.32.15.png", source: .etagere) == .capture
             && SorteFichier.de(nom: "Screenshot 2026-11-11 at 14.32.15.png", source: .telecharges) == .capture
             && SorteFichier.de(nom: "photo.png", source: .captures) == .capture, "captures : par leur nom (français, anglais), ou parce qu'elles viennent du dossier des captures")
    verifier(SorteFichier.de(nom: "Archive.zip", source: .telecharges) == .autre && SorteFichier.de(nom: "sans-extension", source: .etagere) == .autre, "ZIP, sans extension : autre")
    let devis = e("/u/Bureau/Devis-cuisine.pdf", .etagere, 0.5, taille: 212_000, id: "devis")
    let chantier = e("/u/Downloads/Photo-chantier.heic", .airdrop, 3.3, taille: 3_400_000)
    let edf = e("/u/Downloads/Facture-EDF.pdf", .telecharges, 4.9, taille: 88_000)
    let capture = e("/u/Bureau/Capture d\u{2019}écran 2026-11-10 à 14.20.png", .captures, 0.2, taille: 1_200_000)
    let sdb = e("/u/Downloads/Dévis-salle-de-bain.pdf", .airdrop, 30, taille: 236_000)
    let tous = [devis, chantier, edf, capture, sdb]
    func noms(_ l: [EntreeBibliotheque]) -> [String] { l.map(\.nom) }
    verifier(FiltreBibliotheque.allCases.map(\.titre) == ["Tout", "Documents", "Images", "Captures", "AirDrop", "Téléchargés"], "pastilles : Tout, Documents, Images, Captures, AirDrop, Téléchargés (maquette)")
    typealias B = BibliothequeIlot
    verifier(B.filtrer(tous, filtre: .tout, requete: "").count == 5, "Tout : tout")
    verifier(Set(noms(B.filtrer(tous, filtre: .documents, requete: ""))) == ["Devis-cuisine.pdf", "Facture-EDF.pdf", "Dévis-salle-de-bain.pdf"], "Documents : les trois PDF")
    verifier(Set(noms(B.filtrer(tous, filtre: .images, requete: ""))) == [chantier.nom, capture.nom], "Images : la photo ET la capture")
    verifier(noms(B.filtrer(tous, filtre: .captures, requete: "")) == [capture.nom], "Captures : la capture seule")
    verifier(Set(noms(B.filtrer(tous, filtre: .airdrop, requete: ""))) == [chantier.nom, sdb.nom] && noms(B.filtrer(tous, filtre: .telecharges, requete: "")) == [edf.nom],
             "AirDrop, Téléchargés : par source")
    // recherche sans accents ni majuscules (maquette, étape 3 : Documents puis « devis » → les deux devis, d'où qu'ils viennent)
    verifier(Set(noms(B.filtrer(tous, filtre: .documents, requete: "devis"))) == ["Devis-cuisine.pdf", "Dévis-salle-de-bain.pdf"], "Documents + « devis » : les deux devis (« Dévis » compris)")
    verifier(noms(B.filtrer(tous, filtre: .tout, requete: "DÉVIS cuis")) == ["Devis-cuisine.pdf"], "« DÉVIS cuis » : tous les mots, sans accents ni majuscules")
    verifier(B.filtrer(tous, filtre: .images, requete: "devis").isEmpty, "Images + « devis » : rien")
    verifier(Surlignage.plages("Dévis-salle-de-bain.pdf", requete: "devis") == [0 ..< 5], "« devis » surligné dans « Dévis-salle… » (les cinq premières lettres)")

    groupe("Bibliothèque : tri et groupes par date")
    let tri = B.trier(tous, recents: true)
    verifier(noms(tri) == [capture.nom, devis.nom, chantier.nom, edf.nom, sdb.nom], "Récents : du plus récent au plus ancien")
    verifier(noms(B.trier(tous, recents: false)) == noms(tri).reversed(), "Anciens : l'inverse")
    var epingle = devis; epingle.epinglee = true
    let gr = B.groupes([capture, epingle, chantier, edf, sdb], recents: true, maintenant: t0, calendrier: cal)
    verifier(gr.map(\.titre) == ["Épinglés", "Aujourd\u{2019}hui", "Hier"] && gr[0].epingles && gr[0].entrees.map(\.id) == ["devis"],
             "épinglés en haut, puis Aujourd'hui, Hier (\(gr.map(\.titre)))")
    verifier(gr[1].entrees.map(\.nom) == [capture.nom, chantier.nom, edf.nom], "Aujourd'hui : du plus récent au plus ancien, sans l'épinglé")
    let grA = B.groupes([capture, epingle, chantier, edf, sdb], recents: false, maintenant: t0, calendrier: cal)
    verifier(grA.map(\.titre) == ["Épinglés", "Hier", "Aujourd\u{2019}hui"], "Anciens : les épinglés restent en haut, puis Hier, Aujourd'hui")
    // mardi 10 novembre : lundi 9 = hier ; dimanche 8 = la semaine dernière ; dimanche 1er = la semaine dernière ? non : 2-8 = semaine dernière
    let lundi = cal.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 9))!
    let dim8 = cal.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 18))!
    let lun2 = cal.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 10))!
    let dim1 = cal.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 10))!
    let oct = cal.date(from: DateComponents(year: 2026, month: 10, day: 12))!
    let an = cal.date(from: DateComponents(year: 2025, month: 9, day: 3))!
    verifier(B.tranche(t0.addingTimeInterval(60), maintenant: t0, calendrier: cal) == "Aujourd\u{2019}hui", "une date dans le futur (horloge) : aujourd'hui")
    verifier(B.tranche(lundi, maintenant: t0, calendrier: cal) == "Hier", "lundi (on est mardi) : Hier")
    verifier(B.tranche(dim8, maintenant: t0, calendrier: cal) == "La semaine dernière" && B.tranche(lun2, maintenant: t0, calendrier: cal) == "La semaine dernière",
             "dimanche 8 et lundi 2 : la semaine dernière (semaines du lundi)")
    verifier(B.tranche(dim1, maintenant: t0, calendrier: cal) == "Plus tôt ce mois-ci", "dimanche 1er : plus tôt ce mois-ci")
    verifier(B.tranche(oct, maintenant: t0, calendrier: cal) == "Octobre" && B.tranche(an, maintenant: t0, calendrier: cal) == "Septembre 2025", "octobre : « Octobre » ; l'an dernier : « Septembre 2025 »")
    let jeudi = cal.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 10))!
    verifier(B.tranche(lundi, maintenant: jeudi, calendrier: cal) == "Cette semaine", "jeudi : lundi est « Cette semaine »")
    verifier(B.quand(il(0.5), maintenant: t0, calendrier: cal) == "14:02" && B.quand(lundi, maintenant: t0, calendrier: cal) == "hier 09:00", "« 14:02 », « hier 09:00 »")
    let q9 = B.quand(cal.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 9))!, maintenant: t0, calendrier: cal)
    verifier(q9 == "lun. 2 nov.", "cette année : « lun. 2 nov. » (\(q9))")
    verifier(B.quand(an, maintenant: t0, calendrier: cal) == "3 sept. 2025", "l'an dernier : « 3 sept. 2025 » (\(B.quand(an, maintenant: t0, calendrier: cal)))")
    verifier(B.detail(devis, maintenant: t0, calendrier: cal) == "Étagère \u{00B7} 14:02 \u{00B7} 212\u{00A0}Ko", "ligne : « Étagère · 14:02 · 212 Ko » (espace insécable avant l'unité) (\(B.detail(devis, maintenant: t0, calendrier: cal)))")
    verifier(B.detail(EntreeBibliotheque(chemin: "/a/b.pdf", source: .airdrop, date: t0), maintenant: t0, calendrier: cal) == "Reçu par AirDrop \u{00B7} 14:32", "sans taille : la source et la date")
    verifier(B.choisis(1) == "1 choisi" && B.choisis(3) == "3 choisis", "« 1 choisi », « 3 choisis »")
    verifier(B.compte(10, etagere: 4) == "10 fichiers \u{00B7} 4 sur l\u{2019}étagère" && B.compte(1, etagere: 0) == "1 fichier" && B.compte(0, etagere: 0) == "Aucun fichier",
             "« 10 fichiers · 4 sur l'étagère »")
    verifier(B.messageRetrait(dossier: "Téléchargements") == "Retiré d\u{2019}ici. Le fichier reste dans Téléchargements.", "pied après « Retirer » (maquette)")

    groupe("Bibliothèque : l'historique de l'étagère, les sources, épingler, retirer, annuler")
    var b = BibliothequeIlot()
    let et1 = ElementEtagere(chemin: "/u/Bureau/Contrat.pdf", signet: Data("c".utf8), ajout: il(48))
    let et2 = ElementEtagere(chemin: "/u/Bureau/Plan-salon.jpg", signet: Data("p".utf8), ajout: il(20))
    b.noter([EntreeBibliotheque(etagere: et1), EntreeBibliotheque(etagere: et2, taille: 2_100_000)])
    verifier(b.entrees.map(\.nom) == ["Contrat.pdf", "Plan-salon.jpg"] && b.entrees.allSatisfy { $0.source == .etagere } && b.entrees[0].id == et1.id.uuidString,
             "l'étagère verse ses fichiers (même identifiant, même signet, source Étagère)")
    var et1bis = et1; et1bis.ajout = il(0.1)
    b.noter([EntreeBibliotheque(etagere: et1bis)])
    verifier(b.entrees.count == 2 && b.entrees[0].date == il(0.1), "un fichier reposé sur l'étagère : pas de doublon, il revient en tête (sa date est celle du dépôt)")
    // la fusion avec les sources : sans doublon (l'entrée gardée gagne), sans ce qu'on a retiré
    let dlContrat = e("/u/Bureau/Contrat.pdf", .telecharges, 1)
    let fus = b.fusion([edf, dlContrat, chantier])
    verifier(noms(fus) == ["Contrat.pdf", "Plan-salon.jpg", "Facture-EDF.pdf", "Photo-chantier.heic"] && fus[0].source == .etagere, "fusion : gardés d'abord, puis les sources, sans doublon (l'étagère gagne)")
    // retirer un fichier d'une source : masqué, il ne revient pas ; « Annuler » le rend
    let r1 = b.retirer(edf)
    verifier(r1.place == nil && !noms(b.fusion([edf, chantier])).contains("Facture-EDF.pdf"), "« Retirer » un téléchargement : masqué, la prochaine lecture du dossier ne le ramène pas")
    b.annuler(r1)
    verifier(noms(b.fusion([edf])).contains("Facture-EDF.pdf") && b.masques.isEmpty, "« Annuler » : il revient")
    // retirer un fichier gardé : il sort, « Annuler » le remet à sa place
    let r2 = b.retirer(b.entrees[0])
    verifier(r2.place == 0 && b.entrees.map(\.nom) == ["Plan-salon.jpg"] && b.fusion([dlContrat]).isEmpty == false && !noms(b.fusion([dlContrat])).contains("Contrat.pdf"),
             "« Retirer » un fichier de l'étagère : il sort de la bibliothèque, et ne revient pas par Téléchargements")
    b.annuler(r2)
    verifier(b.entrees.map(\.nom) == ["Contrat.pdf", "Plan-salon.jpg"] && b.masques.isEmpty, "« Annuler » : il revient à sa place")
    _ = b.retirer(b.entrees[0])
    b.noter([EntreeBibliotheque(etagere: et1)])
    verifier(b.entrees.map(\.nom).contains("Contrat.pdf") && b.masques.isEmpty, "retiré d'ici puis reposé sur l'étagère : il reparaît")
    // épingler un fichier d'une source : il devient gardé (il reste même la source éteinte) ; détacher
    b.epingler(chantier, true)
    verifier(b.entrees.last?.nom == "Photo-chantier.heic" && b.entrees.last?.epinglee == true && b.entrees.last?.source == .airdrop, "épingler un fichier reçu par AirDrop : gardé, épinglé, sa source reste AirDrop")
    verifier(noms(b.fusion([])).contains("Photo-chantier.heic"), "… et il reste la source éteinte")
    b.epingler(b.entrees[1], true)
    verifier(b.entrees[1].epinglee, "épingler un fichier gardé")
    b.epingler(b.entrees[1], false)
    verifier(!b.entrees[1].epinglee, "le détacher")
    // le plafond : 500, les plus anciens non épinglés sortent (les épinglés restent, même très anciens)
    var p = BibliothequeIlot()
    var vieux = e("/u/x/0-vieux.pdf", .etagere, 10_000); vieux.epinglee = true
    p.noter([vieux])
    p.epingler(vieux, true)
    p.noter((1...BibliothequeIlot.plafond).map { e("/u/x/\($0).pdf", .etagere, Double(1000 - $0)) })
    verifier(p.entrees.count == BibliothequeIlot.plafond && p.entrees.contains { $0.nom == "0-vieux.pdf" } && !p.entrees.contains { $0.nom == "1.pdf" },
             "plafond de \(BibliothequeIlot.plafond) : le plus ancien non épinglé sort, l'épinglé (plus ancien encore) reste")
    // les signets relus : un fichier déplacé suit, un fichier supprimé ou à la Corbeille sort, deux signets du même fichier n'en font qu'un
    var rl = BibliothequeIlot()
    rl.noter([e("/u/a.pdf", .etagere, 1, id: "a"), e("/u/b.png", .etagere, 2, id: "b"), e("/u/c.txt", .etagere, 3, id: "c"), e("/u/d.txt", .etagere, 4, id: "d")])
    let retires = rl.relire { x in
        switch x.id {
        case "a": return .present(chemin: "/u/Rangé/a renommé.pdf", signet: Data("neuf".utf8))
        case "b": return .disparu
        case "c": return .present(chemin: "/u/.Trash/c.txt", signet: nil)
        default: return .present(chemin: "/u/Rangé/a renommé.pdf", signet: nil)
        }
    }
    verifier(rl.entrees.map(\.nom) == ["a renommé.pdf"] && rl.entrees[0].signet == Data("neuf".utf8) && retires.map(\.id) == ["b", "c", "d"],
             "relecture : déplacé suit (nouveau nom, signet renouvelé), supprimé ou à la Corbeille sort, doublon fusionné")
    // le fichier
    if let d = b.donnees(), let relu = BibliothequeIlot.depuis(d) { verifier(relu == b, "fichier : relu à l'identique (signets, épinglés, masques)") } else { verifier(false, "fichier : encodé") }
    verifier(BibliothequeIlot.depuis(Data("pas du json".utf8)) == nil, "fichier abîmé : refusé")

    groupe("Bibliothèque : géométrie de la carte")
    typealias C = CarteBibliotheque
    verifier(C.profondeurMax == 296, "carte au plus haut : 296 pt sous la barre (maquette : 14 + 30 + 8 + 26 + 6 + 164 + 34 + 14)")
    verifier(C.hauteurListe(lignesParGroupe: []) == C.rien && C.hauteurListe(lignesParGroupe: [1, 2]) == 2 * 20 + 3 * 36, "liste : titres de 20 pt, lignes de 36 ; vide : « Aucun fichier »")
    verifier(C.profondeur(liste: 2000) == C.profondeurMax && C.profondeur(liste: C.rien) == 14 + 70 + 42 + 34 + 14, "une longue liste défile (la carte ne dépasse pas 296) ; vide : 174 pt")
    verifier(C.borner(-5, liste: 300) == 0 && C.borner(500, liste: 300) == 300 - C.listeMax && C.borner(40, liste: 100) == 0, "défilement borné")
    for (barre, demi) in [(32.0, 100.0), (37.0, 92.0)] {
        let g = GeoIlot.valeurs(.bibliotheque, hauteurBarre: barre, demiCamera: demi, epaules: true)
        let t = TraceIlot.calculer(g, demiCamera: demi, barre: barre)
        verifier(t.bande <= demi + GeoIlot.aileMax + 0.001, "bibliothèque avec les épaules (caméra \(Int(2 * demi))) : \(Int(t.bande - demi)) pt dans la barre, ≤ 66")
        let c = GeoIlot.valeurs(.centre, hauteurBarre: barre, demiCamera: demi, epaules: true)
        let et = GeoIlot.valeurs(.etagere, hauteurBarre: barre, demiCamera: demi, epaules: true)
        verifier(g[1] == c[1] && g[1] == et[1], "même largeur que le Centre et l'étagère (on passe de l'une à l'autre sans que la forme s'élargisse)")
    }
    verifier(GeoIlot.profondeur(.etagere) == 10 + 42 + 8 + 72 + 10 + GeoIlot.ligneCaptures + 12, "carte Étagère : « Bibliothèque » est une pilule de l'en-tête, la carte garde sa hauteur (une étagère de deux rangées et ses captures tiennent dans la zone de dessin)")
}
