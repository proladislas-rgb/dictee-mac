import AppKit
import DicteeCore

/// `Verbe --miniature-essai [identifiant]` : essai du téléchargement et du cache de la miniature YouTube avec une vidéo publique (par défaut
/// dQw4w9WgXcQ). Réseau seulement : ni micro, ni clavier, ni Accessibilité, ni son. La lecture de l'adresse de l'onglet (Accessibilité) n'est
/// PAS essayée ici : elle ne se teste que dans l'app installée, avec Chrome ouvert sur une vidéo.
enum MiniatureEssai {
    @MainActor
    static func executer(arguments: [String]) -> Int32 {
        _ = NSApplication.shared
        let id = arguments.firstIndex(of: "--miniature-essai").flatMap { $0 + 1 < arguments.count && !arguments[$0 + 1].hasPrefix("--") ? arguments[$0 + 1] : nil } ?? "dQw4w9WgXcQ"
        var echecs = 0
        func verifier(_ ok: Bool, _ nom: String) { print(ok ? "  ok   \(nom)" : "  ÉCHEC \(nom)"); if !ok { echecs += 1 } }
        guard MiniatureYouTube.estIdentifiant(id) else { print("identifiant invalide"); return 2 }
        let fichier = MiniatureLecture.fichier(pour: id)
        let existait = FileManager.default.fileExists(atPath: fichier.path)
        let sauvegarde = existait ? try? Data(contentsOf: fichier) : nil
        try? FileManager.default.removeItem(at: fichier)

        var resultat1: (image: NSImage, origine: MiniatureLecture.Origine)?
        var resultat2: (image: NSImage, origine: MiniatureLecture.Origine)?
        var duree1 = 0.0, duree2 = 0.0
        var fini = false
        Task {
            let t0 = Date()
            resultat1 = await MiniatureLecture.charger(identifiant: id)
            duree1 = Date().timeIntervalSince(t0)
            let t1 = Date()
            resultat2 = await MiniatureLecture.charger(identifiant: id)
            duree2 = Date().timeIntervalSince(t1)
            fini = true
        }
        let fin = Date().addingTimeInterval(20)
        while !fini, Date() < fin { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05)) }
        verifier(fini, "terminé avant le délai de 20 s")
        if let r = resultat1 {
            print("  1er appel : \(r.origine.rawValue), \(Int(r.image.size.width)) × \(Int(r.image.size.height)) pt en \(String(format: "%.2f", duree1)) s")
            verifier(r.origine == .reseau, "premier appel : téléchargé")
            verifier(r.image.size.width >= 300 && r.image.size.height >= 150, "image 320 × 180 reçue")
        } else { verifier(false, "premier appel : image reçue (réseau ?)") }
        let attributs = try? FileManager.default.attributesOfItem(atPath: fichier.path)
        let taille = (attributs?[.size] as? Int) ?? 0
        print("  fichier en cache : \(fichier.path) (\(taille) octets)")
        verifier(taille > 1000 && taille <= MiniatureLecture.tailleMax, "fichier en cache de taille raisonnable (< \(MiniatureLecture.tailleMax / 1000) Ko)")
        verifier(((attributs?[.posixPermissions] as? Int) ?? 0) == 0o600, "fichier en cache en 0600")
        if let r = resultat2 {
            print("  2e appel : \(r.origine.rawValue) en \(String(format: "%.3f", duree2)) s")
            verifier(r.origine == .cache && duree2 < 0.2, "second appel : servi par le cache disque, sans réseau")
        } else { verifier(false, "second appel : image reçue") }
        verifier(MiniatureLecture.enCache("../../etc/passwd") == nil && MiniatureLecture.enCache("court") == nil, "identifiant piégé ou invalide : jamais lu ni écrit")
        // élagage : 45 faux fichiers, il n'en reste que 40
        let faux = (0..<45).map { MiniatureLecture.dossier.appendingPathComponent("zz-essai-\($0).jpg") }
        for (i, f) in faux.enumerated() {
            try? Data(repeating: 1, count: 10).write(to: f)
            try? FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(Double(i - 100))], ofItemAtPath: f.path)
        }
        MiniatureLecture.elaguer()
        let restants = (try? FileManager.default.contentsOfDirectory(atPath: MiniatureLecture.dossier.path).filter { $0.hasSuffix(".jpg") }.count) ?? -1
        verifier(restants <= MiniatureLecture.nombreMax, "élagage : \(restants) miniature(s) gardée(s) au plus \(MiniatureLecture.nombreMax)")
        for f in faux { try? FileManager.default.removeItem(at: f) }
        // on remet le cache comme on l'a trouvé
        try? FileManager.default.removeItem(at: fichier)
        if let sauvegarde { try? sauvegarde.write(to: fichier) }
        print(echecs == 0 ? "essai terminé : tout est vert" : "essai terminé : \(echecs) échec(s)")
        return echecs == 0 ? 0 : 1
    }
}
