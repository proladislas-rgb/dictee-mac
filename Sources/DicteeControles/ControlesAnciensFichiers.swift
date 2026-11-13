import Foundation
import DicteeCore

/// La Concentration retirée (13/11) : un Centre rangé avec elle se relit sans casse, et ses fichiers sont effacés (dossier d'essai, jamais
/// le vrai dossier de Voxile).
func controlesAnciensFichiers() {
    groupe("Concentration retirée : les réglages gardés se relisent proprement")
    typealias D = DispositionCentre
    verifier(ElementCentre(rawValue: "concentration") == nil && !D.parDefaut.map(\.rawValue).contains("concentration")
             && !D.nouveautes.map(\.rawValue).contains("concentration"), "l'identifiant « concentration » n'existe plus (ni par défaut, ni en nouveauté)")
    // la liste vue dans le journal de Hugues (13/11)
    let gardee = ["micro", "dictee", "telechargements", "claude", "second-brain", "concentration", "etagere", "minuteur", "reunion"]
    let d = D(identifiants: gardee)
    verifier(d.elements == [.micro, .dictee, .telechargements, .claude, .secondBrain, .etagere, .minuteur, .reunion],
             "le Centre rangé avec la Concentration : tout le reste, dans le même ordre, elle en moins (\(d.identifiants))")
    verifier(!d.identifiants.contains("concentration"), "réenregistré, l'identifiant disparu ne revient pas dans les réglages")
    let r = D.relire(identifiants: gardee, dejaProposees: ["calendrier", "concentration"])
    verifier(r.disposition == d && r.aRetenir == nil && r.ajoutees.isEmpty,
             "au lancement : rien d'ajouté, rien à réécrire (la nouveauté « concentration » déjà donnée est simplement ignorée)")
    let r2 = D.relire(identifiants: gardee, dejaProposees: ["concentration"])
    verifier(r2.disposition.elements.contains(.calendrier) && r2.aRetenir == ["calendrier", "concentration"] && r2.ajoutees == [.calendrier],
             "sans le calendrier déjà donné : il arrive une fois, l'ancienne nouveauté gardée telle quelle dans la liste retenue")
    verifier(D(identifiants: ["concentration"]) == D(), "un Centre qui ne gardait QUE la Concentration : le Centre par défaut (jamais un Centre vide par erreur)")
    verifier(D(identifiants: ["concentration", "micro"]).elements == [.micro], "la Concentration et le micro : le micro seul")
    let outils = D.relire(identifiants: ["eveil", "concentration", "groq"], dejaProposees: ["groq", "concentration"], page: .outils)
    verifier(outils.disposition.identifiants == ["eveil", "groq"] && outils.aRetenir == nil, "la page Outils l'ignore aussi")

    groupe("Concentration retirée : ses fichiers effacés au lancement")
    let fm = FileManager.default
    let dossier = fm.temporaryDirectory.appendingPathComponent("voxile-anciens-\(UUID().uuidString)", isDirectory: true)
    try? fm.createDirectory(at: dossier, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: dossier) }
    func ecrire(_ nom: String, _ texte: String) { try? Data(texte.utf8).write(to: dossier.appendingPathComponent(nom)) }
    verifier(AnciensFichiers.modeAllume(Data(#"{"actif":{"mode":"travail","duree":"1h","debut":"2026-11-13T09:00:00Z"},"raccourci":"X"}"#.utf8)) == "travail",
             "mémoire avec un mode allumé : le mode est lu")
    verifier(AnciensFichiers.modeAllume(Data(#"{"dernier":{"mode":"travail","duree":"1h"}}"#.utf8)) == nil && AnciensFichiers.modeAllume(Data("{".utf8)) == nil,
             "rien d'allumé, ou fichier abîmé : nil")
    verifier(AnciensFichiers.nettoyer(dossier: dossier) == AnciensFichiers.Bilan(), "dossier sans ancien fichier : rien d'effacé")
    ecrire("concentration.json", #"{"actif":{"mode":"sommeil","duree":"arret","debut":"2026-11-13T09:00:00Z"}}"#)
    ecrire("concentration.json.abime", "abîmé")
    ecrire("rappels.json", #"{"rappels":[]}"#)
    ecrire("historique.json", "{}")
    let b = AnciensFichiers.nettoyer(dossier: dossier, fm: fm)
    verifier(b.effaces == ["concentration.json", "concentration.json.abime"] && b.concentrationLaisseeAllumee == "sommeil",
             "concentration.json et son .abime effacés, le mode laissé allumé est dit (\(b.effaces))")
    let restants = Set((try? fm.contentsOfDirectory(atPath: dossier.path)) ?? [])
    verifier(restants == ["rappels.json", "historique.json"], "les autres fichiers de Voxile ne sont pas touchés (\(restants.sorted()))")
    verifier(AnciensFichiers.nettoyer(dossier: dossier).effaces.isEmpty, "au lancement suivant : plus rien à faire")
    // un lien : effacé lui-même, sa cible intacte et jamais lue
    let cible = dossier.appendingPathComponent("ailleurs.json")
    ecrire("ailleurs.json", #"{"actif":{"mode":"travail"}}"#)
    try? fm.createSymbolicLink(at: dossier.appendingPathComponent("concentration.json"), withDestinationURL: cible)
    let bl = AnciensFichiers.nettoyer(dossier: dossier, fm: fm)
    verifier(bl.effaces == ["concentration.json"] && bl.concentrationLaisseeAllumee == nil && fm.fileExists(atPath: cible.path),
             "concentration.json en lien : le lien effacé, sa cible ni lue ni touchée")
    // la désinstallation : tout le dossier de Voxile, donc ces fichiers aussi
    let maison = URL(fileURLWithPath: "/Users/essai", isDirectory: true)
    let ancien = DossierVerbe.url("concentration.json", maison: maison).standardizedFileURL.path
    verifier(Desinstallation.elements(maison: maison).contains { ancien.hasPrefix($0.standardizedFileURL.path + "/") },
             "« Désinstaller » efface le dossier de Voxile, qui contient concentration.json (rien à ajouter)")
}
