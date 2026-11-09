import AppKit
import SwiftUI

/// Vérification visuelle sans fenêtre : `Dictee --rendu-encoche dossier`
/// Dessine l'encoche dans ses états sur un faux bureau et écrit des PNG (rien n'apparaît à l'écran).
/// Les dimensions de la caméra viennent de l'écran réel quand il en a une (sinon 200 × 32 pt).
enum RenduEncoche {
    @MainActor
    static func executer(dossier: String) -> Int32 {
        _ = NSApplication.shared
        let url = URL(fileURLWithPath: (dossier as NSString).expandingTildeInPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let notes = NSWorkspace.shared.icon(forFile: "/System/Applications/Notes.app")
        let geometrie = NSScreen.screens.first.map { GeometrieEncoche.mesurer($0).0 } ?? GeometrieEncoche()
        print("caméra : \(Int(geometrie.largeur)) × \(Int(geometrie.hauteur)) pt")

        func modele(ouverte: Bool, ruban: Bool, mainsLibres: Bool, texte: String, fige: Bool = false, message: String? = nil, niveaux: [CGFloat] = [0.35, 0.7, 1.0, 0.55, 0.25]) -> EncocheModele {
            let m = EncocheModele()
            m.geometrie = geometrie
            m.ouverte = ouverte; m.ruban = ruban; m.mainsLibres = mainsLibres; m.texte = texte; m.fige = fige; m.message = message
            m.icone = notes
            m.niveaux = niveaux
            return m
        }
        let courte = "On se voit mercredi pour parler du devis, je t'envoie"
        let longue = "On se voit mercredi pour parler du devis, je t'envoie le lien juste après la réunion"
        let calmes: [CGFloat] = Array(repeating: 0, count: 5)
        let cas: [(String, String, EncocheModele)] = [
            ("1-appui", "Appui", modele(ouverte: true, ruban: false, mainsLibres: false, texte: "")),
            ("2-parole", "Parole", modele(ouverte: true, ruban: true, mainsLibres: false, texte: "On se voit mercredi pour parler du devis")),
            ("3-relachement", "Relâchement", modele(ouverte: true, ruban: true, mainsLibres: false, texte: "On se voit mercredi pour parler du devis.", fige: true, niveaux: calmes)),
            ("4-mains-libres", "Mains libres", modele(ouverte: true, ruban: true, mainsLibres: true, texte: "Je te rappelle demain matin pour confirmer", niveaux: calmes)),
            ("5-long", "Texte long", modele(ouverte: true, ruban: true, mainsLibres: false, texte: longue)),
            ("6-message", "Message", modele(ouverte: true, ruban: true, mainsLibres: false, texte: "", message: "Écriture impossible ici, texte copié")),
            ("7-repos", "Repos", modele(ouverte: false, ruban: false, mainsLibres: false, texte: "")),
        ]
        _ = courte

        func scene(_ nom: String, _ m: EncocheModele) -> some View {
            let taille = EnclochePanneau.tailleFenetre(pour: m.geometrie)
            return HStack(alignment: .top, spacing: 12) {
                Text(nom).font(.system(size: 12)).foregroundStyle(Color(white: 0.6)).frame(width: 80, alignment: .leading).padding(.top, 8)
                ZStack(alignment: .top) {
                    Color(red: 27/255, green: 28/255, blue: 30/255)
                    HStack { Text("Notes").bold(); Text("Fichier"); Text("Édition"); Spacer(); Text("lun. 9 nov.  14:42") }
                        .font(.system(size: 13)).foregroundStyle(Color(red: 161/255, green: 161/255, blue: 166/255))
                        .padding(.horizontal, 16).frame(height: m.geometrie.hauteur)
                    EncocheVue(m: m, tailleFenetre: taille)
                }
                .frame(width: 760, height: taille.height + 8)
            }
        }
        var ok = true
        func ecrire<V: View>(_ vue: V, _ nom: String) {
            let rendu = ImageRenderer(content: vue)
            rendu.scale = 2
            guard let image = rendu.nsImage, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { print("échec du rendu \(nom)"); ok = false; return }
            let fichier = url.appendingPathComponent("\(nom).png")
            try? png.write(to: fichier)
            print("écrit \(fichier.path) (\(rep.pixelsWide)×\(rep.pixelsHigh))")
        }
        ecrire(VStack(spacing: 6) { ForEach(0..<4, id: \.self) { i in scene(cas[i].1, cas[i].2) } }
            .padding(10).background(Color(red: 20/255, green: 20/255, blue: 21/255)), "encoche-4-etats")
        ecrire(VStack(spacing: 6) { ForEach(4..<7, id: \.self) { i in scene(cas[i].1, cas[i].2) } }
            .padding(10).background(Color(red: 20/255, green: 20/255, blue: 21/255)), "encoche-autres-etats")
        return ok ? 0 : 1
    }
}
