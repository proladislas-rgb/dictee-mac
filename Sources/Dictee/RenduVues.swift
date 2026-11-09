import AppKit
import SwiftUI
import DicteeCore

/// Rendu hors écran des vues AppKit/SwiftUI (champs de texte compris) en PNG : une vue d'hébergement qui n'est dans
/// aucune fenêtre visible. Aucune fenêtre n'apparaît, aucun focus n'est pris ; ne touche ni au micro ni au clavier.
@MainActor
enum RenduVues {
    static func png<V: View>(_ vue: V, taille: CGSize, echelle: CGFloat = 2) -> Data? {
        let hote = NSHostingView(rootView: vue)
        hote.appearance = NSAppearance(named: .darkAqua)
        hote.frame = NSRect(origin: .zero, size: taille)
        // une fenêtre jamais affichée donne à la vue sa taille et son apparence
        let fenetre = NSWindow(contentRect: hote.frame, styleMask: [.borderless], backing: .buffered, defer: true)
        fenetre.appearance = NSAppearance(named: .darkAqua)
        fenetre.contentView = hote
        hote.layoutSubtreeIfNeeded()
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(taille.width * echelle), pixelsHigh: Int(taille.height * echelle),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = taille
        hote.cacheDisplay(in: hote.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    /// Historique d'exemple (jamais celui de l'utilisateur), dans un fichier temporaire.
    static func historiqueExemple(vide: Bool = false) -> HistoriqueStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dictee-rendu-\(UUID().uuidString).json")
        let store = HistoriqueStore(url: url)
        if vide { return store }
        let cal = Calendar.current
        func a(_ jours: Int, _ h: Int, _ m: Int) -> Date {
            cal.date(bySettingHour: h, minute: m, second: 0, of: cal.date(byAdding: .day, value: -jours, to: Date())!)!
        }
        let lignes: [(Int, Int, Int, String, String, Bool)] = [
            (1, 18, 2, "Mail", "Peux-tu m\u{2019}envoyer le récapitulatif avant jeudi ?", true),
            (1, 16, 24, "Notes", "Le rendez-vous est confirmé pour dix heures.", true),
            (0, 10, 8, "Notes", "Penser à envoyer la proposition avant jeudi.", true),
            (0, 11, 30, "Claude", "Reprends le tableau des factures, ajoute une colonne pour la date de relance et trie par montant.", true),
            (0, 13, 55, "WhatsApp", "J\u{2019}arrive dans dix minutes, commande-moi un café.", true),
            (0, 14, 12, "Mail", "Bonjour Madame Martin, suite à notre échange de ce matin, je vous transmets la proposition avec les deux options dont on a parlé.", true),
            (0, 14, 41, "Notes", "On se voit mercredi pour parler du devis.", false),
        ]
        for (j, h, m, app, texte, insere) in lignes {
            store.ajouter(EntreeHistorique(date: a(j, h, m), appId: nil, appNom: app, texte: texte, insere: insere, raison: insere ? nil : "champ protégé"))
        }
        return store
    }

    /// Faux bureau : fond, barre des menus, encoche.
    struct Bureau<Contenu: View>: View {
        var taille: CGSize
        var haut: CGFloat = 32
        var camera: CGFloat = 180
        @ViewBuilder var contenu: Contenu
        var body: some View {
            ZStack(alignment: .top) {
                Color(hex: 0x0B0B0B)
                HStack {
                    Text("Notes").bold(); Text("Fichier"); Text("Édition"); Spacer()
                    FormeGuillemets().fill(Palette.texte).frame(width: 14, height: 14 / Guillemets.rapport)
                    Image(systemName: "wifi"); Image(systemName: "battery.75percent"); Text("lun. 9 nov.  14:42")
                }
                .font(.system(size: 13)).foregroundStyle(Palette.texte2)
                .padding(.horizontal, 16).frame(height: haut)
                .frame(maxWidth: .infinity)
                .background(Color(hex: 0x141413))
                UnevenRoundedRectangle(bottomLeadingRadius: 9, bottomTrailingRadius: 9).fill(Color.black).frame(width: camera, height: haut)
                contenu.padding(.top, haut + 6)
            }
            .frame(width: taille.width, height: taille.height, alignment: .top)
        }
    }

    static func ecrire(_ donnees: Data?, _ fichier: URL) -> Bool {
        guard let donnees, (try? donnees.write(to: fichier)) != nil else { print("échec du rendu \(fichier.lastPathComponent)"); return false }
        print("écrit \(fichier.path)")
        return true
    }
}

/// `Dictee --rendu-panneau dossier` : le panneau compact (et ses états) en PNG, sans fenêtre.
enum RenduPanneau {
    @MainActor
    static func executer(dossier: String) -> Int32 {
        _ = NSApplication.shared
        Polices.enregistrer()
        print("Newsreader disponible : \(Polices.newsreaderDisponible)")
        let url = URL(fileURLWithPath: (dossier as NSString).expandingTildeInPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var ok = true

        func panneau(_ nom: String, store: HistoriqueStore, requete: String = "", developper: Bool = false, taille: CGSize = CGSize(width: 720, height: 420)) {
            let m = ModeleDictees(store: store)
            m.requete = requete
            m.selection = m.affichees.first?.id
            if developper { m.developpee = m.affichees.first { $0.texte.hasPrefix("Bonjour") }?.id; m.selection = m.developpee }
            let app = ApparitionPanneau(); app.visible = true
            let vue = RenduVues.Bureau(taille: taille) {
                PanneauVue(m: m, store: store, apparition: app, surOnglet: { _ in }, curseurFactice: true)
            }
            ok = RenduVues.ecrire(RenduVues.png(vue, taille: taille), url.appendingPathComponent("\(nom).png")) && ok
        }
        let plein = RenduVues.historiqueExemple()
        // la ligne choisie par défaut est la plus récente
        func choisir(_ s: HistoriqueStore) -> HistoriqueStore { s }
        panneau("panneau-1-historique", store: plein)
        panneau("panneau-2-texte-complet", store: plein, developper: true)
        panneau("panneau-3-recherche", store: plein, requete: "mail")
        panneau("panneau-4-aucun-resultat", store: plein, requete: "zzz")
        panneau("panneau-5-historique-vide", store: RenduVues.historiqueExemple(vide: true))
        return ok ? 0 : 1
    }
}
