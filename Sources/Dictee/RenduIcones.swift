import AppKit
import SwiftUI

/// Vérification visuelle et fabrication sans fenêtre : `Dictee --rendu-icones dossier`
/// Écrit l'icône d'app (jeu AppIcon.iconset pour iconutil) et des planches PNG de contrôle : guillemets à 16, 32 et 128 px,
/// barre des menus aux états repos / survol / capture. Rien n'apparaît à l'écran ; ne touche ni au micro ni au clavier.
enum RenduIcones {
    @MainActor
    static func executer(dossier: String) -> Int32 {
        _ = NSApplication.shared
        let url = URL(fileURLWithPath: (dossier as NSString).expandingTildeInPath, isDirectory: true)
        let jeu = url.appendingPathComponent("AppIcon.iconset", isDirectory: true)
        try? FileManager.default.createDirectory(at: jeu, withIntermediateDirectories: true)

        func ecrire(_ rep: NSBitmapImageRep, _ fichier: URL) -> Bool {
            guard let png = rep.representation(using: .png, properties: [:]) else { return false }
            return (try? png.write(to: fichier)) != nil
        }
        var ok = true
        // Jeu d'icônes pour iconutil
        let tailles: [(Int, String)] = [(16, "icon_16x16"), (32, "icon_16x16@2x"), (32, "icon_32x32"), (64, "icon_32x32@2x"),
                                        (128, "icon_128x128"), (256, "icon_128x128@2x"), (256, "icon_256x256"), (512, "icon_256x256@2x"),
                                        (512, "icon_512x512"), (1024, "icon_512x512@2x")]
        for (cote, nom) in tailles {
            guard let rep = IconeApp.pixels(cote: cote), ecrire(rep, jeu.appendingPathComponent("\(nom).png")) else { ok = false; continue }
        }
        if let rep = IconeApp.pixels(cote: 1024) { ok = ecrire(rep, url.appendingPathComponent("icone-1024.png")) && ok }

        // Planche : guillemets nus à 16, 32 et 128 px, clairs sur sombre et sombres sur clair, et icône d'app à 3 tailles.
        let planche = ImageRenderer(content: PlancheLogo())
        planche.scale = 2
        if let rep = planche.nsImage.flatMap({ $0.tiffRepresentation }).flatMap({ NSBitmapImageRep(data: $0) }) {
            ok = ecrire(rep, url.appendingPathComponent("logo-equilibre.png")) && ok
        } else { ok = false }

        // Barre des menus : repos, survol, panneau ouvert, capture.
        let barre = ImageRenderer(content: PlancheBarre())
        barre.scale = 3
        if let rep = barre.nsImage.flatMap({ $0.tiffRepresentation }).flatMap({ NSBitmapImageRep(data: $0) }) {
            ok = ecrire(rep, url.appendingPathComponent("barre-des-menus.png")) && ok
        } else { ok = false }
        print(ok ? "écrit \(url.path)" : "échec du rendu des icônes")
        return ok ? 0 : 1
    }
}

private struct PlancheLogo: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .bottom, spacing: 28) {
                ForEach([16, 32, 128], id: \.self) { c in
                    VStack(spacing: 6) {
                        FormeGuillemets().fill(Color(red: 236/255, green: 233/255, blue: 227/255))
                            .frame(width: CGFloat(c), height: CGFloat(c) / Guillemets.rapport)
                        Text("\(c)").font(.system(size: 10)).foregroundStyle(.gray)
                    }
                }
                Spacer().frame(width: 20)
                ForEach([16, 32, 128], id: \.self) { c in
                    VStack(spacing: 6) {
                        FormeGuillemets().fill(Color.black)
                            .frame(width: CGFloat(c), height: CGFloat(c) / Guillemets.rapport)
                        Text("\(c)").font(.system(size: 10)).foregroundStyle(.gray)
                    }
                }
            }
            HStack(alignment: .bottom, spacing: 24) {
                ForEach([16, 32, 128, 256], id: \.self) { c in
                    if let rep = IconeApp.pixels(cote: c * 2) {
                        Image(nsImage: { let i = NSImage(size: NSSize(width: c, height: c)); i.addRepresentation(rep); return i }())
                            .resizable().frame(width: CGFloat(c), height: CGFloat(c))
                    }
                }
            }
        }
        .padding(24)
        .background(LinearGradient(stops: [.init(color: Color(red: 0.07, green: 0.07, blue: 0.07), location: 0.5),
                                           .init(color: Color(white: 0.93), location: 0.5)], startPoint: .leading, endPoint: .trailing))
    }
}

private struct PlancheBarre: View {
    private func cellule(_ nom: String, capture: Bool, fond: Bool) -> some View {
        VStack(spacing: 6) {
            Image(nsImage: IconeBarre.image(capture: capture))
                .renderingMode(capture ? .original : .template)
                .foregroundStyle(Color(red: 236/255, green: 233/255, blue: 227/255))
                .frame(width: 30, height: 22)
                .background(RoundedRectangle(cornerRadius: 5).fill(fond ? Color(red: 38/255, green: 38/255, blue: 36/255) : .clear))
            Text(nom).font(.system(size: 9)).foregroundStyle(.gray)
        }
    }
    var body: some View {
        HStack(spacing: 22) {
            cellule("repos", capture: false, fond: false)
            cellule("survol / ouvert", capture: false, fond: true)
            cellule("capture", capture: true, fond: false)
            Image(systemName: "wifi").foregroundStyle(.gray)
            Image(systemName: "battery.75percent").foregroundStyle(.gray)
        }
        .padding(16)
        .background(Color(red: 27/255, green: 27/255, blue: 26/255))
    }
}
