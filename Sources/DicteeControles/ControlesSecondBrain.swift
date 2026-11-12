import Foundation
import DicteeCore

/// Contrôles de la case « Second Brain » de l'îlot : décodage tolérant du fichier d'état, bornes, textes, choix de ce qu'on montre, liens
/// qu'on accepte d'ouvrir, fraîcheur, lecture du fichier (dans un dossier temporaire, jamais le vrai ~/.config), place dans le Centre.
/// Appelée depuis main.swift (un seul appel).
func controlesSecondBrain() {
    typealias SB = SecondCerveauIlot
    let contrat = """
    { "version": 1, "maj": "2026-11-12T09:15:00+01:00",
      "resume": "Pierre t'a écrit · 3 choses demandées",
      "compteurs": { "nouveautes": 3, "aToi": 5, "aRelancer": 2 },
      "messages": [ { "id": "9ed7c1f2a7f3", "nom": "Pierre", "texte": "Pour vendredi : le plan…", "heure": "2026-11-12T09:12:00+01:00", "resume": "3 choses demandées", "lien": "secondbrain://message/9ed7c1f2a7f3" } ],
      "taches":   [ { "id": "4b0c9e11d2aa", "texte": "Répondre aux 3 questions de Pierre", "echeance": "2026-11-14", "lien": "secondbrain://chose/4b0c9e11d2aa" } ],
      "relances": [ { "id": "c3a5f0e8b1d4", "nom": "Marc", "sujet": "le devis du site", "depuis": "2026-10-21", "lien": "secondbrain://fiche/personnes/marc.md" } ],
      "lien": "secondbrain://aujourdhui" }
    """.data(using: .utf8)

    groupe("Second Brain : le contrat v1")
    let sb = SB.decoder(contrat)
    verifier(sb != nil, "le fichier du contrat se lit")
    verifier(sb?.resume == "Pierre t'a écrit · 3 choses demandées" && sb?.lien == "secondbrain://aujourdhui", "résumé et lien général")
    verifier(sb?.compteurs == SB.Compteurs(nouveautes: 3, aToi: 5, aRelancer: 2), "les trois compteurs")
    verifier(sb?.messages.count == 1 && sb?.messages[0].nom == "Pierre" && sb?.messages[0].heure == "2026-11-12T09:12:00+01:00" && sb?.messages[0].id == "9ed7c1f2a7f3" && sb?.messages[0].resume == "3 choses demandées", "un message")
    verifier(sb?.taches.first?.texte == "Répondre aux 3 questions de Pierre" && sb?.taches.first?.echeance == "2026-11-14", "une tâche")
    verifier(sb?.relances.first?.nom == "Marc" && sb?.relances.first?.depuis == "2026-10-21" && sb?.relances.first?.lien == "secondbrain://fiche/personnes/marc.md", "une relance")
    verifier(sb?.maj == SB.date("2026-11-12T08:15:00Z"), "la date de mise à jour (09:15 à +01:00 = 08:15 UTC)")
    verifier(sb?.etat == "3 nouveautés", "sous le bouton du Centre : « 3 nouveautés »")

    // le contrat final : null partout où il n'y a rien, listes vides
    let nul = SB.decoder("""
    { "version": 1, "maj": null, "resume": null, "compteurs": { "nouveautes": 0, "aToi": 0, "aRelancer": 0 },
      "messages": [ { "id": "aaaaaaaaaaaa", "nom": "Julie", "texte": null, "heure": null, "resume": null, "lien": null } ],
      "taches": [ { "id": "bbbbbbbbbbbb", "texte": "Sans date", "echeance": null, "lien": null } ],
      "relances": [], "lien": null }
    """.data(using: .utf8))
    verifier(nul?.maj == nil && nul?.resume == nil && nul?.lien == nil && nul?.messages.first?.heure == nil && nul?.messages.first?.texte == nil && nul?.taches.first?.echeance == nil, "null : les champs sont simplement absents")
    verifier(nul?.relances.isEmpty == true && nul?.messages.count == 1 && nul?.taches.count == 1 && nul?.etat == "À jour", "une liste vide, des lignes sans date : lu, « À jour »")
    verifier(nul.map { $0.affichage.relances.isEmpty && $0.titreRelances($0.affichage) == nil } == true, "liste vide : pas de partie « À relancer »")
    let toutesVides = SB.decoder("{ \"version\": 1, \"maj\": null, \"compteurs\": { \"nouveautes\": 0, \"aToi\": 0, \"aRelancer\": 0 }, \"messages\": [], \"taches\": [], \"relances\": [], \"lien\": null }".data(using: .utf8))
    verifier(toutesVides?.vide == true && toutesVides?.etat == "À jour" && toutesVides?.fraicheur(maintenant: Date()) == nil, "trois listes vides, tout à null : la case dit « Rien de neuf »")

    groupe("Second Brain : un fichier qui ne donne pas de case")
    verifier(SB.decoder(nil) == nil && SB.decoder(Data()) == nil, "absent ou vide : pas de case")
    verifier(SB.decoder("pas du json".data(using: .utf8)) == nil && SB.decoder("{ \"messages\": [".data(using: .utf8)) == nil, "illisible : pas de case")
    verifier(SB.decoder("[1, 2, 3]".data(using: .utf8)) == nil && SB.decoder("\"texte\"".data(using: .utf8)) == nil && SB.decoder("42".data(using: .utf8)) == nil, "un JSON qui n'est pas un objet : pas de case")
    var grand = "{\"resume\": \""; grand += String(repeating: "a", count: SB.tailleMax); grand += "\"}"
    verifier(SB.decoder(grand.data(using: .utf8)) == nil, "plus de 64 Ko : pas de case")
    var juste = "{\"resume\": \""; juste += String(repeating: "a", count: SB.tailleMax - 15); juste += "\"}"
    verifier(juste.utf8.count <= SB.tailleMax && SB.decoder(juste.data(using: .utf8)) != nil, "juste sous 64 Ko : lu")
    verifier(SB.decoder("{}".data(using: .utf8)) != nil && SB.decoder("{}".data(using: .utf8))?.vide == true && SB.decoder("{}".data(using: .utf8))?.etat == "À jour", "un objet vide : la case, « À jour », rien de neuf")

    groupe("Second Brain : décodage tolérant")
    let abime = """
    { "version": "un", "maj": 12, "resume": 5, "lien": ["x"],
      "compteurs": { "nouveautes": true, "aToi": "5", "aRelancer": -4 },
      "messages": "oups",
      "taches": [ 3, null, { "texte": "" }, { "id": 7, "texte": "Garder celle-ci" }, "x" ],
      "relances": [ { "nom": "Zoé", "sujet": 12, "depuis": ["a"] } ] }
    """.data(using: .utf8)
    let ab = SB.decoder(abime)
    verifier(ab != nil && ab?.maj == nil && ab?.resume == nil && ab?.lien == nil, "champs du mauvais type : ignorés, pas le fichier")
    verifier(ab?.compteurs == SB.Compteurs(nouveautes: nil, aToi: nil, aRelancer: 0), "compteurs : un booléen et un texte ignorés, un négatif devient 0")
    verifier(ab?.messages.isEmpty == true, "messages qui n'est pas un tableau : vide")
    verifier(ab?.taches.count == 1 && ab?.taches[0].texte == "Garder celle-ci" && ab?.taches[0].id == "taches-3", "tâches : les entrées abîmées sautées, la bonne gardée (identifiant numérique : remplacé)")
    verifier(ab?.relances.count == 1 && ab?.relances[0].nom == "Zoé" && ab?.relances[0].sujet == nil && ab?.relances[0].depuis == nil, "relance : le nom seul suffit")
    verifier(ab?.nouveautes == 0 && ab?.aToi == 1 && ab?.aRelancer == 0, "compteurs absents : le nombre de lignes gardées (sauf le 0 écrit)")

    var dix = "{\"messages\": ["
    dix += (1...10).map { "{\"id\":\"m\($0)\",\"nom\":\"N\($0)\",\"texte\":\"t\($0)\"}" }.joined(separator: ",")
    dix += "], \"taches\": [" + (1...10).map { "{\"texte\":\"x\($0)\"}" }.joined(separator: ",") + "], \"relances\": [" + (1...10).map { "{\"nom\":\"r\($0)\"}" }.joined(separator: ",") + "]}"
    let b = SB.decoder(dix.data(using: .utf8))
    verifier(b?.messages.count == 3 && b?.taches.count == 3 && b?.relances.count == 3, "dix lignes par tableau : trois gardées")
    verifier(b?.messages.map(\.id) == ["m1", "m2", "m3"], "les trois PREMIÈRES")
    verifier(b?.nouveautes == 3, "sans compteur, le nombre de lignes gardées")
    var vides = "{\"messages\": ["; vides += String(repeating: "{},", count: 100) + "{\"nom\":\"Seul\"}]}"
    verifier(SB.decoder(vides.data(using: .utf8))?.messages.isEmpty == true, "cent entrées vides avant la bonne : on ne lit que les quarante premières entrées")
    let fl = SB.decoder("{\"compteurs\":{\"nouveautes\":2.9,\"aToi\":100000}}".data(using: .utf8))
    verifier(fl?.compteurs.nouveautes == 2 && fl?.compteurs.aToi == 9999, "compteurs : décimal arrondi vers le bas, énorme borné")

    groupe("Second Brain : textes")
    verifier(SB.net("  Bonjour\n\n  le   monde \t", 50) == "Bonjour le monde", "retours à la ligne, tabulations et espaces en trop : une seule ligne")
    verifier(SB.net("a\u{0007}b\u{200B}c\u{202E}d", 50) == "abcd", "caractères de contrôle, invisibles et de sens inversé retirés")
    verifier(SB.net("   \n\t ", 50) == nil && SB.net(12, 50) == nil && SB.net(nil, 50) == nil, "vide ou pas du texte : rien")
    let long = SB.net("Pour vendredi : le plan, les chiffres et la liste des invités avec leurs régimes alimentaires", 40)
    verifier((long?.count ?? 99) <= 40 && long?.hasSuffix("\u{2026}") == true, "trop long : coupé à 40 caractères au plus, avec « … » (\(long ?? "nil"))")
    verifier(long?.hasSuffix(" \u{2026}") == false && !(long ?? "").dropLast().hasSuffix(","), "coupé à la fin d'un mot, sans virgule ni espace avant « … »")
    verifier(SB.net("Court", 40) == "Court", "un texte court reste tel quel")
    verifier(SB.net(String(repeating: "x", count: 500), 30)?.count == 30, "un mot de 500 lettres : coupé net à 30")
    verifier(SB.net("🙂🙂🙂🙂🙂🙂", 4)?.count == 4, "les émojis comptent un caractère")
    verifier(SB.nombre(7) == "7" && SB.nombre(999) == "999" && SB.nombre(1000) == "999+", "nombres : jamais plus de quatre caractères")

    groupe("Second Brain : ce qu'on montre")
    func lignes(_ m: Int, _ t: Int, _ r: Int) -> SB {
        SB(messages: (0..<m).map { SB.Message(id: "m\($0)", nom: "N") }, taches: (0..<t).map { SB.Tache(id: "t\($0)", texte: "x") }, relances: (0..<r).map { SB.Relance(id: "r\($0)", nom: "R") })
    }
    func compte(_ s: SB) -> [Int] { let a = s.affichage; return [a.messages.count, a.taches.count, a.relances.count] }
    verifier(compte(lignes(3, 3, 3)) == [3, 2, 2], "3 + 3 + 3 devient 3 + 2 + 2 (sept lignes)")
    verifier(compte(lignes(2, 3, 2)) == [2, 3, 2] && compte(lignes(1, 1, 1)) == [1, 1, 1] && compte(lignes(1, 1, 1)) == [1, 1, 1], "ce qui tient : tout est montré")
    verifier(compte(lignes(3, 3, 1)) == [3, 2, 1] && compte(lignes(1, 3, 3)) == [1, 3, 2] && compte(lignes(3, 3, 2)) == [3, 2, 2] && compte(lignes(3, 0, 3)) == [3, 0, 3] && compte(lignes(0, 3, 3)) == [0, 3, 3], "trop pour la hauteur du Centre : la partie la plus remplie, la dernière en cas d'égalité, perd une ligne")
    verifier((0...3).allSatisfy { m in (0...3).allSatisfy { t in (0...3).allSatisfy { r in lignes(m, t, r).affichage.lignes <= 7 && MesuresSecondBrain.corps(lignes: compte(lignes(m, t, r))) <= MesuresSecondBrain.corpsMax && lignes(m, t, r).affichage.messages.count <= 3 } } }, "jamais plus de sept lignes, jamais plus de trois par partie, toujours dans la hauteur du Centre (64 combinaisons)")
    verifier(lignes(0, 0, 0).vide && !lignes(0, 1, 0).vide, "rien du tout : « Rien de neuf »")
    let nombres = SB(compteurs: .init(nouveautes: 2, aToi: 14, aRelancer: 2), messages: [.init(id: "a", nom: "A"), .init(id: "b", nom: "B")],
                     taches: (0..<3).map { .init(id: "t\($0)", texte: "x") }, relances: [.init(id: "r", nom: "R"), .init(id: "s", nom: "S")])
    let aff = nombres.affichage
    verifier(nombres.titreMessages(aff)?.sous == "2 à lire" && nombres.titreTaches(aff)?.sous == "3 sur 14" && nombres.titreRelances(aff)?.sous == "2 personnes", "sous les titres : « 2 à lire », « 3 sur 14 », « 2 personnes » (maquette)")
    verifier(SB(taches: [.init(id: "t", texte: "x")]).titreTaches(SB(taches: [.init(id: "t", texte: "x")]).affichage)?.sous == "1 à faire" && SB(relances: [.init(id: "r", nom: "R")]).titreRelances(SB(relances: [.init(id: "r", nom: "R")]).affichage)?.sous == "1 personne", "singuliers")
    verifier(nombres.titreMessages(SB().affichage) == nil, "une partie sans ligne n'a pas de titre")
    verifier(SB(compteurs: .init(nouveautes: 1)).etat == "1 nouveauté" && SB(compteurs: .init(nouveautes: 0, aToi: 5)).etat == "5 à toi" && SB(compteurs: .init(nouveautes: 0, aToi: 0, aRelancer: 2)).etat == "2 à relancer" && SB(compteurs: .init(nouveautes: 0, aToi: 0, aRelancer: 0)).etat == "À jour", "l'état : nouveautés d'abord, puis à toi, puis à relancer, sinon « À jour »")
    verifier(SB.relanceAncienne("40 jours") && SB.relanceAncienne("2 mois") && SB.relanceAncienne("4 semaines") && !SB.relanceAncienne("22 jours") && !SB.relanceAncienne("2 semaines") && !SB.relanceAncienne(nil) && !SB.relanceAncienne("depuis longtemps"), "relance de longtemps (30 jours ou plus) : en ambre")

    groupe("Second Brain : fraîcheur (mis à jour…)")
    let t0 = SB.date("2026-11-12T09:15:00+01:00")!
    func frais(_ s: TimeInterval) -> String? { SB(maj: t0).fraicheur(maintenant: t0.addingTimeInterval(s)) }
    verifier(frais(10) == "à l\u{2019}instant" && frais(-300) == "à l\u{2019}instant", "moins d'une minute (ou horloge en avance) : à l'instant")
    verifier(frais(120) == "il y a 2 min" && frais(59 * 60) == "il y a 59 min", "minutes")
    verifier(frais(3 * 3600) == "il y a 3 h" && frais(23 * 3600 + 59 * 60) == "il y a 23 h", "heures")
    verifier(frais(24 * 3600) == "mis à jour hier" && frais(40 * 3600) == "mis à jour hier", "plus de 24 h : « mis à jour hier »")
    verifier(frais(48 * 3600) == nil && frais(30 * 86_400) == nil && SB().fraicheur(maintenant: t0) == nil, "plus de deux jours, ou sans date : rien")
    verifier(SB.date("2026-11-12T09:15:00Z") != nil && SB.date("2026-11-12T09:15:00.250+01:00") != nil && SB.date("2026-11-12T09:15:00") != nil && SB.date("hier") == nil && SB.date("") == nil, "formats de date lus (Z, fractions, sans fuseau), le reste refusé")

    groupe("Second Brain : les dates en français simple")
    var paris = Calendar(identifier: .gregorian); paris.timeZone = TimeZone(identifier: "Europe/Paris")!
    // mardi 10 novembre 2026, 14 h 32
    let mardi = paris.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 14, minute: 32))!
    func ech(_ s: String?) -> String? { DateSecondCerveau.echeance(s, maintenant: mardi, calendrier: paris)?.texte }
    verifier(ech("2026-11-10") == "aujourd\u{2019}hui" && ech("2026-11-11") == "demain", "échéance : aujourd'hui, demain")
    verifier(ech("2026-11-14") == "samedi" && ech("2026-11-12") == "jeudi" && ech("2026-11-16") == "lundi", "échéance dans la semaine : le jour (samedi, jeudi, lundi)")
    verifier(ech("2026-11-17") == "le 17" && ech("2026-11-20") == "le 20" && ech("2026-11-30") == "le 30", "échéance à plus d'une semaine, ce mois-ci : « le 20 »")
    verifier(ech("2026-12-01") == "le 1er déc." && ech("2026-12-24") == "le 24 déc." && ech("2027-01-05") == "5 janv. 2027", "autre mois : « le 1er déc. », autre année : « 5 janv. 2027 »")
    verifier(ech("2026-11-09") == "en retard" && DateSecondCerveau.echeance("2026-11-09", maintenant: mardi, calendrier: paris)?.alerte == true && DateSecondCerveau.echeance("2026-11-10", maintenant: mardi, calendrier: paris)?.alerte == false, "échéance passée : « en retard » en ambre")
    verifier(ech(nil) == nil && ech("") == nil, "échéance null : rien")
    verifier(ech("samedi") == "samedi" && ech("le 20") == "le 20" && ech("2026-02-31") == "2026-02-31" && ech("n'importe quoi de beaucoup trop long pour la colonne")?.hasSuffix("\u{2026}") == true, "pas une date : le texte tel quel (premier contrat), tronqué")
    verifier(ech("2026-11-14T00:00:00+01:00") == "samedi" && ech("2026-11-14T23:30:00+01:00") == "samedi", "une ISO avec fuseau : son jour")
    func dep(_ s: String?) -> DateSecondCerveau.Texte? { DateSecondCerveau.depuis(s, maintenant: mardi, calendrier: paris) }
    verifier(dep("2026-10-19")?.texte == "depuis 22 jours" && dep("2026-10-19")?.alerte == false, "depuis : « depuis 22 jours »")
    verifier(dep("2026-10-01")?.texte == "depuis 40 jours" && dep("2026-10-01")?.alerte == true && dep("2026-10-11")?.alerte == true && dep("2026-10-12")?.alerte == false, "depuis 30 jours et plus : en ambre (29 jours : non)")
    verifier(dep("2026-11-10")?.texte == "aujourd\u{2019}hui" && dep("2026-11-09")?.texte == "depuis hier" && dep("2026-11-20")?.texte == "aujourd\u{2019}hui", "depuis : aujourd'hui, hier, une date à venir = aujourd'hui")
    verifier(dep("2026-09-01")?.texte == "depuis 2 mois" && dep("2025-11-10")?.texte == "depuis 12 mois" && dep("2024-11-09")?.texte == "depuis 2 ans", "depuis : mois à partir de 60 jours, ans à partir de deux ans")
    verifier(dep(nil) == nil && dep("22 jours") == DateSecondCerveau.Texte("22 jours") && dep("2 mois")?.alerte == true, "depuis null : rien ; un texte (premier contrat) : tel quel, ambre si « mois »")
    func heu(_ s: String?) -> String? { DateSecondCerveau.heure(s, calendrier: paris) }
    verifier(heu("2026-11-12T09:12:00+01:00") == "9:12" && heu("2026-11-12T08:12:00Z") == "9:12" && heu("2026-11-12T14:05:30+01:00") == "14:05" && heu("2026-11-12T00:03:00+01:00") == "0:03", "heure : une ISO avec fuseau devient « 9:12 » (heure du Mac), minutes sur deux chiffres")
    verifier(heu(nil) == nil && heu("") == nil && heu("9:12") == "9:12" && (heu("hier soir")?.count ?? 99) <= 8, "heure null : rien ; un texte : tel quel (8 caractères au plus)")

    groupe("Second Brain : les liens qu'on accepte d'ouvrir")
    let fichiers: [String: SB.Existence] = ["/Users/h/Notes/plan.md": .init(existe: true), "/Users/h/Notes": .init(existe: true, dossier: true),
                                            "/Applications/Calculator.app": .init(existe: true, dossier: true), "/Users/h/run.command": .init(existe: true),
                                            "/etc/passwd": .init(existe: true), "/Users/h/Notes/image.PNG": .init(existe: true)]
    let existe: (String) -> SB.Existence = { fichiers[$0] ?? .init(existe: false) }
    func lien(_ s: String?) -> String? { SB.lienValide(s, existence: existe)?.absoluteString }
    verifier(lien("secondbrain://aujourdhui") == "secondbrain://aujourdhui" && lien("secondbrain://message/9ed7c1f2a7f3") == "secondbrain://message/9ed7c1f2a7f3" && lien("secondbrain://fiche/personnes/x.md") == "secondbrain://fiche/personnes/x.md" && lien("secondbrain://chose/t1") == "secondbrain://chose/t1", "secondbrain:// : aujourdhui, message, chose")
    verifier(lien("secondbrain://fiche/Projets/Plan 2026.md")?.hasPrefix("secondbrain://fiche/Projets/Plan") == true && lien("SecondBrain://aujourdhui") != nil, "avec des espaces (encodés), et le schéma en majuscules")
    verifier(lien("https://exemple.fr") == nil && lien("http://x") == nil && lien("javascript:alert(1)") == nil && lien("tel:0102030405") == nil && lien("x-apple.systempreferences:com.apple.preference") == nil && lien("vscode://file/x") == nil, "https, http, javascript, tel, réglages, autres schémas : refusés")
    verifier(lien("/Users/h/Notes/plan.md") == "file:///Users/h/Notes/plan.md" && lien("file:///Users/h/Notes/plan.md") != nil && lien("/Users/h/Notes/image.PNG") != nil, "un document qui existe (chemin ou file://)")
    verifier(lien("/Users/h/Notes/absent.md") == nil && lien("relatif/plan.md") == nil, "qui n'existe pas, ou chemin relatif : refusé")
    verifier(lien("/Users/h/Notes") != nil, "un dossier ordinaire qui existe : ouvert (Finder)")
    verifier(lien("/Applications/Calculator.app") == nil && lien("/Users/h/run.command") == nil && lien("/etc/passwd") == nil, "une app, un script, un fichier sans extension de document : refusés")
    verifier(lien("") == nil && lien(nil) == nil && lien("secondbrain://x\u{0000}y") == nil && lien(String(repeating: "a", count: 2000)) == nil, "vide, caractère de contrôle, trop long : refusé")
    let app = URL(fileURLWithPath: "/Applications/Second Brain.app")
    var demandes: [[String]] = []
    let trouve: ([String]) -> URL? = { demandes.append($0); return app }
    let aucune: ([String]) -> URL? = { _ in nil }
    let aucun: (URL) -> URL? = { _ in nil }
    let avecLien = SB(lien: "secondbrain://aujourdhui")
    verifier(avecLien.aOuvrir(lienDeLaLigne: "secondbrain://message/9ed7c1f2a7f3", existence: existe, gestionnaire: aucun, appInstallee: trouve)?.absoluteString == "secondbrain://message/9ed7c1f2a7f3", "une ligne avec son lien : son lien")
    verifier(avecLien.aOuvrir(lienDeLaLigne: nil, existence: existe, gestionnaire: aucun, appInstallee: trouve)?.absoluteString == "secondbrain://aujourdhui", "une ligne sans lien : le lien général")
    verifier(avecLien.aOuvrir(lienDeLaLigne: "https://piege.fr", existence: existe, gestionnaire: aucun, appInstallee: trouve)?.absoluteString == "secondbrain://aujourdhui", "un lien piégé sur la ligne : le lien général")
    verifier(demandes.isEmpty, "tant qu'un lien est valable, l'app n'est pas cherchée")
    verifier(SB().aOuvrir(lienDeLaLigne: nil, existence: existe, gestionnaire: aucun, appInstallee: trouve) == app && demandes == [["com.hugues.second-cerveau", "com.hugues.second-brain"]], "sans lien, aucune app pour secondbrain:// : l'app, en essayant les deux identifiants (celui du contrat d'abord)")
    verifier(SB(lien: "https://piege.fr").aOuvrir(lienDeLaLigne: "file:///etc/passwd", existence: existe, gestionnaire: aucun, appInstallee: trouve) == app, "deux liens piégés : l'app")
    verifier(SB().aOuvrir(lienDeLaLigne: nil, existence: existe, gestionnaire: aucun, appInstallee: aucune) == nil, "sans lien et sans app : rien")
    let appId = demandes.count
    verifier(SB().aOuvrir(lienDeLaLigne: nil, existence: existe, gestionnaire: { _ in app }, appInstallee: trouve) == SB.lienAccueil && demandes.count == appId && SB.lienAccueil.absoluteString == "secondbrain://aujourdhui",
             "sans lien, une app sait ouvrir secondbrain:// : « Aujourd'hui » (secondbrain://aujourdhui), sans chercher l'app")

    groupe("Second Brain : la lecture du fichier (dossier temporaire)")
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("verbe-controles-second-brain-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
    try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    let f = tmp.appendingPathComponent(FichierSecondCerveau.nom)
    verifier(FichierSecondCerveau.lire(f) == nil, "fichier absent : rien")
    try? contrat?.write(to: f)
    verifier(FichierSecondCerveau.lire(f) == contrat && SB.decoder(FichierSecondCerveau.lire(f)) != nil, "fichier présent : son contenu")
    try? Data(count: SB.tailleMax + 10).write(to: f)
    verifier(FichierSecondCerveau.lire(f) == nil, "plus de 64 Ko : rien (sans le lire en entier)")
    try? FileManager.default.removeItem(at: f)
    try? FileManager.default.createDirectory(at: f, withIntermediateDirectories: true)
    verifier(FichierSecondCerveau.lire(f) == nil, "un dossier à la place du fichier : rien")
    try? FileManager.default.removeItem(at: f)
    let profond = tmp.appendingPathComponent("a/b/c", isDirectory: true)
    verifier(FichierSecondCerveau.ancetreExistant(profond).path == tmp.path, "dossier absent : on surveille son plus proche ancêtre qui existe")
    verifier(FichierSecondCerveau.dossierParDefaut().path.hasSuffix("/.config/second-cerveau") && FichierSecondCerveau.nom == "ilot.json", "le chemin du contrat : ~/.config/second-cerveau/ilot.json")

    groupe("Second Brain : la place dans l'îlot")
    verifier(CartesIlot.parent(.secondBrain) == .centre && CartesIlot.parent(.centre) == nil, "la carte est rangée sous le Centre")
    verifier(!CartesIlot.aUnPied(.secondBrain, pile: CartesIlot.pile(survol: .centre)), "pas de bouton « Centre » au pied : son en-tête a « ‹ Centre »")
    verifier(CartesIlot.pile(survol: .centre) == [.centre, .outils, .accueil, .dictees] && CartesIlot.pile(survol: .dictees).last == .dictees, "la pile ne change pas : les Dictées restent en dernier")
    verifier(GeoIlot.aEpaules(.secondBrain) && !GeoIlot.ajusteAuContenu(.secondBrain) && !VueIlot.secondBrain.estBandeau && !VueIlot.secondBrain.estAlerte, "épaules comme le Centre ; ni bandeau ni alerte")
    verifier(GeoIlot.valeurs(.secondBrain, hauteurBarre: 33) == GeoIlot.valeurs(.centre, hauteurBarre: 33), "même largeur que le Centre (on passe de l'un à l'autre sans que la forme s'élargisse)")
    verifier(ElementCentre.secondBrain.rawValue == "second-brain" && ElementCentre.secondBrain.genre == .rond && ElementCentre.secondBrain.page == .centre, "l'élément « second-brain » : un rond du Centre")
    func dispo(_ sb: Bool) -> (ElementCentre) -> Bool { { $0 != .secondBrain || sb } }
    // le Centre d'avant la Concentration (12/11) : six ronds avec elle, il n'y aurait plus de place pour Second Brain
    var d = DispositionCentre(DispositionCentre.parDefaut.filter { $0 != .concentration })
    verifier(!d.elements.contains(.secondBrain) && d.aAjouter(disponible: dispo(false)).contains(.secondBrain) == false && d.aAjouter(disponible: dispo(true)).contains(.secondBrain), "proposé dans « Ajouter : » seulement quand le fichier existe")
    verifier(!d.ajouter(.secondBrain, disponible: dispo(false)) && d.ajouter(.secondBrain, disponible: dispo(true)), "ajouté seulement quand le fichier existe")
    verifier(d.ronds(disponible: dispo(true)).contains(.secondBrain) && !d.ronds(disponible: dispo(false)).contains(.secondBrain), "montré avec le fichier, caché sans (aucun vide), sans être retiré de la disposition")
    verifier(DispositionCentre(identifiants: d.identifiants).elements.contains(.secondBrain) && DispositionCentre(identifiants: ["micro", "second-brain", "inconnu"]).elements == [.micro, .secondBrain], "rangé dans les réglages et relu")
    var pleine = DispositionCentre([.micro, .dictee, .telechargements, .calendrier, .claude, .rappel])
    verifier(!pleine.ajouter(.secondBrain, disponible: dispo(true)), "six ronds déjà (DispositionCentre.maxRonds) : pas de septième")
    // la carte tient dans la hauteur du Centre, quel que soit ce qu'elle montre
    var pire = 0.0, plusBas = 999.0
    for m in 0...3 { for t in 0...3 { for r in 0...3 {
        let p = MesuresSecondBrain.profondeur(lignes(m, t, r).affichage)
        pire = max(pire, p); plusBas = min(plusBas, p)
    } } }
    verifier(pire <= GeoIlot.profondeurCentre, "la carte n'est jamais plus haute que le Centre (\(Int(pire)) pt au plus sur \(Int(GeoIlot.profondeurCentre)))")
    verifier(MesuresSecondBrain.profondeur(lignes(3, 2, 2).affichage) == GeoIlot.profondeurCentre && MesuresSecondBrain.profondeur(lignes(0, 0, 0).affichage) == 148 && plusBas == 147, "3 + 2 + 2 lignes : exactement la hauteur du Centre (298 pt) ; rien de neuf : 148 pt ; une seule ligne : 147 pt")
    // les mesures posent les trois parties les unes sous les autres sans se chevaucher
    verifier(MesuresSecondBrain.corps(lignes: [3, 2, 2]) == 80 + 56 + 56 + 2 && MesuresSecondBrain.corps(lignes: [1, 0, 1]) == 35 + 8 + 35 + 8 + 1 && MesuresSecondBrain.corps(lignes: [0, 0, 0]) == MesuresSecondBrain.vide, "hauteurs des parties (maquette : lignes de 24 pt)")
}
