import AppKit
import SwiftUI

/// Vérification visuelle sans fenêtre : `Dictee --rendu-encoche dossier`
/// Dessine l'encoche dans plusieurs états sur un faux bureau et écrit des PNG (rien n'apparaît à l'écran).
enum RenduEncoche {
    @MainActor
    static func executer(dossier: String) -> Int32 {
        _ = NSApplication.shared
        let url = URL(fileURLWithPath: (dossier as NSString).expandingTildeInPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let notes = NSWorkspace.shared.icon(forFile: "/System/Applications/Notes.app")

        func modele(ouverte: Bool, ruban: Bool, mainsLibres: Bool, texte: String, fige: Bool = false, message: String? = nil) -> EncocheModele {
            let m = EncocheModele()
            m.ouverte = ouverte; m.ruban = ruban; m.mainsLibres = mainsLibres; m.texte = texte; m.fige = fige; m.message = message
            m.icone = notes
            m.niveaux = [0.35, 0.7, 1.0, 0.55, 0.25]
            return m
        }
        let courte = "On se voit mercredi pour parler du devis, je t'envoie"
        let longue = "On se voit mercredi pour parler du devis, je t'envoie le lien juste après la réunion"
        let cas: [(String, EncocheModele)] = [
            ("1-ecoute", modele(ouverte: true, ruban: true, mainsLibres: false, texte: courte)),
            ("2-ecoute-long", modele(ouverte: true, ruban: true, mainsLibres: false, texte: longue)),
            ("3-mains-libres", modele(ouverte: true, ruban: true, mainsLibres: true, texte: "Je te rappelle demain matin pour confirmer")),
            ("4-finalisation", modele(ouverte: true, ruban: true, mainsLibres: false, texte: courte, fige: true)),
            ("5-message", modele(ouverte: true, ruban: true, mainsLibres: false, texte: "", message: "Champ protégé, texte copié")),
            ("6-repos", modele(ouverte: false, ruban: false, mainsLibres: false, texte: "")),
        ]
        var ok = true
        for (nom, m) in cas {
            let taille = EnclochePanneau.tailleFenetre(pour: m.geometrie)
            let scene = ZStack(alignment: .top) {
                Color(red: 27/255, green: 28/255, blue: 30/255)
                HStack { Text("Notes").bold(); Text("Fichier"); Text("Édition"); Spacer(); Text("lun. 9 nov.  18:42") }
                    .font(.system(size: 13)).foregroundStyle(Color(red: 161/255, green: 161/255, blue: 166/255))
                    .padding(.horizontal, 16).frame(height: 32)
                EncocheVue(m: m, tailleFenetre: taille)
            }
            .frame(width: taille.width, height: taille.height + 20)
            let rendu = ImageRenderer(content: scene)
            rendu.scale = 2
            guard let image = rendu.nsImage, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { print("échec du rendu \(nom)"); ok = false; continue }
            let fichier = url.appendingPathComponent("\(nom).png")
            try? png.write(to: fichier)
            print("écrit \(fichier.path) (\(rep.pixelsWide)×\(rep.pixelsHigh))")
        }
        return ok ? 0 : 1
    }
}
