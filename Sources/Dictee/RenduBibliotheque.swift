import AppKit
import SwiftUI
import UniformTypeIdentifiers
import DicteeCore

/// Les rendus de la Bibliothèque (`--rendu-ilot`) : les fichiers de la maquette ilot-bibliotheque.html, en mémoire (aucun fichier lu,
/// aucune source lue), avec des images dessinées ; et l'onglet « Bibliothèque » de la fenêtre.
@MainActor
enum RenduBibliotheque {
    /// Une « photo » (ciel, colline) ou une « capture » (une fenêtre claire), dessinées : jamais une vraie image de l'utilisateur.
    static func photo(_ ciel: Color, _ sol: Color, colline: Color) -> NSImage {
        let v = ZStack(alignment: .bottom) {
            LinearGradient(colors: [ciel, sol], startPoint: .top, endPoint: .bottom)
            Ellipse().fill(colline).frame(width: 260, height: 120).offset(y: 60)
        }.frame(width: 192, height: 132)
        let r = ImageRenderer(content: v); r.scale = 2
        return r.nsImage ?? NSImage()
    }
    static func capture() -> NSImage {
        let v = ZStack {
            Color(hex: 0xDCE4EE)
            RoundedRectangle(cornerRadius: 8).fill(Color.white).frame(width: 150, height: 92)
                .overlay(alignment: .topLeading) { VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) { ForEach(0..<3, id: \.self) { _ in Circle().fill(Color(hex: 0xC9C9CE)).frame(width: 6, height: 6) } }
                    RoundedRectangle(cornerRadius: 2).fill(Color(hex: 0x2B2B30)).frame(width: 90, height: 8)
                    RoundedRectangle(cornerRadius: 2).fill(Color(hex: 0xBDBDC4)).frame(width: 120, height: 5)
                    RoundedRectangle(cornerRadius: 2).fill(Color(hex: 0xBDBDC4)).frame(width: 104, height: 5)
                }.padding(10) }
        }.frame(width: 192, height: 132)
        let r = ImageRenderer(content: v); r.scale = 2
        return r.nsImage ?? NSImage()
    }

    /// La bibliothèque de la maquette : l'étagère (devis, plan, contrat, lettre), puis Téléchargés, AirDrop et une capture ; le contrat épinglé.
    static func modele(_ t0: Date) -> BibliothequeModele {
        func il(_ h: Double) -> Date { t0.addingTimeInterval(-h * 3600) }
        func e(_ id: String, _ nom: String, _ src: SourceBibliotheque, _ h: Double, _ t: Int64, ep: Bool = false) -> EntreeBibliotheque {
            EntreeBibliotheque(id: id, chemin: "/Users/exemple/" + (src == .etagere ? "Desktop/" : (src == .captures ? "Desktop/Captures d\u{2019}écran/" : "Downloads/")) + nom,
                               source: src, date: il(h), taille: t, epinglee: ep)
        }
        let gardees = [e("devis", "Devis-cuisine.pdf", .etagere, 0.5, 212_000), e("plan", "Plan-salon.jpg", .etagere, 19.9, 2_100_000),
                       e("contrat", "Contrat.pdf", .etagere, 29.5, 184_000, ep: true), e("lettre", "Lettre-banque.docx", .etagere, 30.5, 31_000)]
        let trouves = [e("cap", "Capture 14.32.png", .captures, 0.01, 1_200_000), e("chantier", "Photo-chantier.heic", .airdrop, 3.3, 3_400_000),
                       e("edf", "Facture-EDF.pdf", .telecharges, 4.9, 88_000), e("budget", "Budget-2026.xlsx", .telecharges, 29.3, 48_000),
                       e("sdb", "Devis-salle-de-bain.pdf", .airdrop, 30.1, 236_000), e("cap2", "Capture 10.05.png", .captures, 52.5, 980_000),
                       e("billet", "Billet-train-Lyon.pdf", .telecharges, 74, 96_000)]
        let m = BibliothequeModele(enMemoire: gardees, trouves: trouves, sources: Set(SourceBibliotheque.optionnelles))
        m.lireImages = false
        m.maintenant = { t0 }
        m.surEtagere = 4
        let pdf = NSWorkspace.shared.icon(for: .pdf)
        let images: [String: NSImage] = [
            "plan": photo(Color(hex: 0xEFE0C8), Color(hex: 0xC9A27A), colline: Color(hex: 0x8A6A4A)),
            "chantier": photo(Color(hex: 0x7FB4E0), Color(hex: 0xE8B07A), colline: Color(hex: 0x6E7F4A)),
            "cap": capture(), "cap2": capture()]
        for x in gardees + trouves {
            if let i = images[x.id] { m.poserImage(i, pour: x.id); m.poserImage(i, pour: x.id, vignette: true) }
            else {
                let ext = (x.nom as NSString).pathExtension
                let i = ext == "pdf" ? pdf : NSWorkspace.shared.icon(for: UTType(filenameExtension: ext) ?? .data)
                m.poserImage(i, pour: x.id)
            }
        }
        return m
    }

    /// La Bibliothèque dans la fenêtre (Aujourd'hui › Bibliothèque), en sombre.
    static func fenetre(_ b: BibliothequeModele, _ t0: Date, _ etat: BibliothequeFenetreEtat? = nil) -> some View {
        let nav = NavigationBureau(); nav.ouvrir(.bibliotheque)
        let h = HistoriqueStore(enMemoire: [])
        let d = ModeleDictees(store: h)
        let store = ReunionStore(dossier: FileManager.default.temporaryDirectory.appendingPathComponent("verbe-rendu-biblio"), lire: false)
        let r = ReunionsModele(store: store)
        return RenduBureau.fenetre(nav, sombre: true, taille: RenduBureau.taille, store: h, dictees: d,
                                   mots: MotsModele(persistant: false, mots: [], raccourcis: [], propositions: PropositionsMots()),
                                   reglages: ReglagesModele(reel: false), reunions: r, controleur: ReunionController(store: store),
                                   journee: JourneeModele(dictees: d, reunions: r), bibliotheque: b, etat: etat)
    }
}
