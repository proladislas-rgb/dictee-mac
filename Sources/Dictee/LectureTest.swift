import AppKit
import DicteeCore

/// `Verbe --lecture-test [secondes]` : lance le programme d'aide de la lecture en cours (depuis l'app assemblée), affiche les événements
/// reçus (titre coupé à 30 caractères), puis l'arrête proprement. Ni micro, ni clavier, ni Accessibilité, ni son.
enum LectureTest {
    @MainActor
    static func executer(secondes: Double) -> Int32 {
        guard LecteurSysteme.fichiers != nil else {
            print("programme d'aide introuvable : lancer depuis l'app assemblée (.build/Voxile.app/Contents/MacOS/Voxile)")
            return 1
        }
        let systeme = LecteurSysteme()
        var evenements = 0
        systeme.surEvenement = { e in
            evenements += 1
            switch e {
            case .pret: print("prêt")
            case .rien: print("rien ne joue")
            case .echec(let r): print("échec : \(r)")
            case .etat(let m):
                print("état : « \(String(m.titre.prefix(30))) » app=\(m.app ?? "-") joue=\(m.joue) durée=\(m.duree.map { String(Int($0)) } ?? "direct") position=\(m.position.map { String(Int($0)) } ?? "-") image=\(m.cheminImage == nil ? "non" : "oui") clé=\(m.cle.count) car.")
            }
        }
        systeme.surAbandon = { r in print("abandon : \(r)") }
        systeme.demarrer()
        let fin = Date().addingTimeInterval(secondes)
        while Date() < fin { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.1)) }
        systeme.arreter()
        print("arrêté après \(Int(secondes)) s, \(evenements) événement(s)")
        return 0
    }
}
