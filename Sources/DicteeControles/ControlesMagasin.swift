import Foundation
import DicteeCore
import Synchronization

/// Contrôles de `DossierVerbe` et `MagasinJSON` : les fichiers au format actuel (tels que les versions d'avant les ont écrits) se
/// relisent sans rien perdre, l'écriture est atomique et créée en 0600, un fichier illisible est mis de côté, un échec est tracé.
/// Tout se passe dans un dossier temporaire : jamais le vrai dossier de Voxile. Appelée depuis main.swift.
func controlesMagasins() {
    groupe("Fichiers de l'utilisateur : un seul dossier, un seul magasin")
    let maison = URL(fileURLWithPath: "/Users/essai", isDirectory: true)
    verifier(DossierVerbe.url(maison: maison).path == "/Users/essai/Library/Application Support/Dictee"
             && DossierVerbe.url("rappels.json", maison: maison).path == "/Users/essai/Library/Application Support/Dictee/rappels.json"
             && DossierVerbe.url("Reunions", dossier: true, maison: maison).hasDirectoryPath,
             "le dossier de Voxile garde son chemin d'avant (« Dictee »), rien ne déménage")
    verifier(Desinstallation.cheminsRelatifs.contains(DossierVerbe.relatif), "la désinstallation efface ce même dossier")

    let dossier = FileManager.default.temporaryDirectory.appendingPathComponent("verbe-magasins-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: dossier) }
    func ecrireBrut(_ nom: String, _ texte: String) -> URL {
        let u = dossier.appendingPathComponent(nom)
        try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        try? Data(texte.utf8).write(to: u)
        return u
    }
    func droits(_ u: URL) -> Int { ((try? FileManager.default.attributesOfItem(atPath: u.path))?[.posixPermissions] as? Int) ?? -1 }
    func date(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }
    // les fichiers tels que les versions d'avant les écrivent (mêmes clés, mêmes dates ISO 8601, notes en JSON indenté)
    let idR = UUID(uuidString: "6F1C2D3E-0000-4000-8000-000000000001")!
    let urlR = ecrireBrut("rappels.json", #"{"rappels":[{"cree":"2026-11-12T08:00:00Z","echeance":"2026-11-13T12:00:00Z","id":"6F1C2D3E-0000-4000-8000-000000000001","idApple":"x-apple-1","texte":"Appeler le garage"}]}"#)
    let rappels = MagasinJSON<ListeRappels>(url: urlR, nom: "rappels").lire()
    verifier(rappels?.rappels == [Rappel(id: idR, texte: "Appeler le garage", echeance: date("2026-11-13T12:00:00Z"), cree: date("2026-11-12T08:00:00Z"), idApple: "x-apple-1")],
             "rappels.json au format actuel : relu tel quel")
    let idN = UUID(uuidString: "6F1C2D3E-0000-4000-8000-000000000002")!
    let urlN = ecrireBrut("notes.json", "{\n  \"notes\" : [\n    {\n      \"date\" : \"2026-11-12T09:30:00Z\",\n      \"id\" : \"6F1C2D3E-0000-4000-8000-000000000002\",\n      \"texte\" : \"Acheter du pain\",\n      \"versNotes\" : true\n    }\n  ]\n}")
    verifier(MagasinJSON<ListeNotes>(url: urlN, nom: "notes").lire()?.notes == [NoteRapide(id: idN, texte: "Acheter du pain", date: date("2026-11-12T09:30:00Z"), versNotes: true)],
             "notes.json (indenté) : relu tel quel")
    let urlV = ecrireBrut("reveil.json", #"{"heure":7,"minute":30,"repousse":true,"sonnerie":"2026-11-14T06:40:00Z"}"#)
    let reveil = MagasinJSON<ReveilIlot>(url: urlV, nom: "réveil", siIllisible: .oublier).lire()
    verifier(reveil?.heure == 7 && reveil?.minute == 30 && reveil?.repousse == true && reveil?.sonnerie == date("2026-11-14T06:40:00Z"), "reveil.json : relu tel quel")
    let urlC = ecrireBrut("concentration.json", #"{"dernier":{"duree":"1h","mode":"travail"},"raccourci":"Concentration Verbe"}"#)
    verifier(MagasinJSON<MemoireConcentration>(url: urlC, nom: "concentration").lire()
             == MemoireConcentration(dernier: DernierConcentration(mode: .travail, duree: .uneHeure), raccourci: "Concentration Verbe"), "concentration.json : relu tel quel")
    let urlE = ecrireBrut("etagere.json", #"{"elements":[{"ajout":"2026-11-12T10:00:00Z","chemin":"/Users/essai/Documents/Contrat.pdf","id":"6F1C2D3E-0000-4000-8000-000000000003","nom":"Contrat.pdf","signet":"AAEC"}]}"#)
    let etagere = MagasinJSON<EtagereIlot>(url: urlE, nom: "étagère").lire()
    verifier(etagere?.elements.map(\.nom) == ["Contrat.pdf"] && etagere?.elements.first?.signet == Data([0, 1, 2]) && etagere?.elements.first?.arriveSeul == false,
             "etagere.json (signet en base 64, sans « seul ») : relu tel quel")

    // réécrits : mêmes octets que l'encodage du type (le format ne change pas), en 0600, aucun fichier temporaire laissé
    if let rappels, let etagere {
        let mR = MagasinJSON<ListeRappels>(url: urlR, nom: "rappels")
        let mE = MagasinJSON<EtagereIlot>(url: urlE, nom: "étagère")
        try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: urlR.path)
        verifier(mR.ecrire(rappels) && mE.ecrire(etagere), "réécriture : réussie")
        verifier((try? Data(contentsOf: urlR)) == rappels.donnees() && mR.lire() == rappels && mE.lire() == etagere, "réécrit puis relu : le même contenu, le même format")
        verifier(droits(urlR) == 0o600 && droits(urlE) == 0o600, "réécrit : 0600 (même un ancien fichier en 0644)")
    }
    let restes = ((try? FileManager.default.contentsOfDirectory(atPath: dossier.path)) ?? []).filter { $0.hasPrefix(".") }
    verifier(restes.isEmpty, "aucun fichier temporaire laissé à côté")

    // un nouveau fichier, dans un dossier qui n'existe pas encore : créé avec son dossier, en 0600
    let neuf = dossier.appendingPathComponent("sous/bibliotheque.json")
    let mB = MagasinJSON<BibliothequeIlot>(url: neuf, nom: "bibliothèque")
    verifier(!mB.existe && mB.lire() == nil, "pas de fichier : rien à lire (l'app part d'une valeur vide)")
    verifier(mB.ecrire(BibliothequeIlot(masques: ["/a"])) && mB.existe && droits(neuf) == 0o600 && mB.lire()?.masques == ["/a"], "nouveau fichier : dossier créé, 0600, relu")

    // un fichier illisible : gardé en .abime (à la place d'un .abime plus ancien), ou oublié (réveil) ; tracé au journal
    let lignes = Lignes()
    let tracer: @Sendable (String) -> Void = { m in lignes.m.withLock { $0.append(m) } }
    let abime = ecrireBrut("abime.json", "pas du json")
    _ = ecrireBrut("abime.json.abime", "un plus ancien")
    let mA = MagasinJSON<ListeRappels>(url: abime, nom: "rappels", journal: tracer)
    verifier(mA.lire() == nil && !mA.existe && (try? String(contentsOf: abime.appendingPathExtension("abime"), encoding: .utf8)) == "pas du json",
             "fichier illisible : mis de côté en .abime (le plus récent gardé), l'app repart d'une valeur vide")
    let oublie = ecrireBrut("oublie.json", "{]")
    let mO = MagasinJSON<ReveilIlot>(url: oublie, nom: "réveil", siIllisible: .oublier, journal: tracer)
    verifier(mO.lire() == nil && !mO.existe && !FileManager.default.fileExists(atPath: oublie.appendingPathExtension("abime").path), "réveil illisible : oublié")
    // un échec d'écriture (un fichier à la place du dossier) : faux, tracé, sans le contenu
    let bloque = ecrireBrut("bloque", "un fichier, pas un dossier").appendingPathComponent("notes.json")
    let mX = MagasinJSON<ListeNotes>(url: bloque, nom: "notes", journal: tracer)
    verifier(!mX.ecrire(ListeNotes(notes: [NoteRapide(texte: "secret", date: Date())])), "écriture impossible : faux")
    let journal = lignes.m.withLock { $0 }
    verifier(journal.count == 3 && journal[0] == "rappels : fichier illisible, l'ancien est gardé en .abime" && journal[1] == "réveil : fichier illisible, oublié"
             && journal[2].hasPrefix("notes : écriture impossible (") && !journal.joined().contains("secret"),
             "journal : les mêmes lignes qu'avant, l'échec d'écriture tracé, jamais le contenu (\(journal.last ?? "rien"))")
    // l'historique des dictées (13/11 : il gardait sa propre lecture, `try? moveItem` vers un .abime DÉJÀ là échouait en silence : le
    // fichier abîmé restait en place, écrasé par la dictée suivante, alors que le journal annonçait une copie de côté)
    let hist = ecrireBrut("historique.json", "{ pas fini")
    _ = ecrireBrut("historique.json.abime", "une panne d'avant")
    let mH = MagasinJSON<Historique>(url: hist, nom: "historique", journal: tracer)
    verifier(mH.lire() == nil && !mH.existe && (try? String(contentsOf: hist.appendingPathExtension("abime"), encoding: .utf8)) == "{ pas fini",
             "historique illisible, un .abime déjà là : le fichier abîmé est mis de côté (jamais écrasé par la dictée suivante)")
    let entree = EntreeHistorique(date: date("2026-11-13T09:00:00Z"), appNom: "Mail", texte: "Bonjour")
    verifier(mH.ecrire(Historique(entrees: [entree])) && droits(hist) == 0o600 && mH.lire()?.entrees.map(\.texte) == ["Bonjour"], "historique réécrit : 0600 d'emblée, relu")
    // un fichier qu'on ne peut pas déplacer (son dossier en lecture seule) : le journal le dit, il ne prétend pas l'avoir gardé
    let fige = dossier.appendingPathComponent("fige", isDirectory: true)
    try? FileManager.default.createDirectory(at: fige, withIntermediateDirectories: true)
    let raccourcis = fige.appendingPathComponent("raccourcis.json")
    try? Data("[{".utf8).write(to: raccourcis)
    try? FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: fige.path)
    var dit: [String] = []
    let garde = FichierIllisible.mettreDeCote(raccourcis, nom: "raccourcis.json", journal: { dit.append($0) })
    try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fige.path)
    verifier(!garde && dit.count == 1 && dit[0].hasPrefix("raccourcis.json : fichier illisible, impossible de le mettre de côté")
             && FileManager.default.fileExists(atPath: raccourcis.path), "déplacement impossible : le journal le dit (\(dit.first ?? "rien")), le fichier reste")
    // en mémoire (essais, rendus) : rien n'est lu ni écrit
    let mM = MagasinJSON<BibliothequeIlot>(url: nil, nom: "bibliothèque")
    verifier(mM.lire() == nil && !mM.ecrire(BibliothequeIlot()) && !mM.existe, "en mémoire : rien sur le disque")
}

/// Les lignes que le magasin a tracées (le journal de l'app, ici en mémoire).
private final class Lignes: Sendable { let m = Mutex<[String]>([]) }
