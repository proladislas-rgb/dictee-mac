import AppKit

/// Vérification sans toucher au clavier ni au vrai presse-papiers : `Dictee --verifier-collage`
/// Utilise un presse-papiers privé et un faux « ⌘V ». Contrôle la sauvegarde, le type confidentiel,
/// la restauration, le cas « le presse-papiers a changé », deux collages rapprochés et le champ protégé.
/// Ne touche ni au micro, ni à l'accessibilité, ni à la surveillance du clavier.
enum VerifierCollage {
    @MainActor
    static func executer() async -> Int32 {
        var echecs = 0
        func verifier(_ ok: Bool, _ nom: String) { print(ok ? "  ok   \(nom)" : "  ÉCHEC \(nom)"); if !ok { echecs += 1 } }

        let nom = NSPasteboard.Name("com.hugues.dictee.test-\(UUID().uuidString.prefix(8))")
        let presse = NSPasteboard(name: nom)
        defer { presse.releaseGlobally() }
        let html = Data("<b>riche</b>".utf8)
        func remplirOrigine() {
            presse.clearContents()
            let a = NSPasteboardItem(); a.setString("ancien", forType: .string); a.setData(html, forType: .html)
            let b = NSPasteboardItem(); b.setString("deuxième élément", forType: .string)
            presse.writeObjects([a, b])
        }
        func origineIntacte() -> Bool {
            guard let items = presse.pasteboardItems, items.count == 2 else { return false }
            return items[0].string(forType: .string) == "ancien" && items[0].data(forType: .html) == html && items[1].string(forType: .string) == "deuxième élément"
        }

        print("Collage (presse-papiers privé, faux ⌘V)")
        var envois = 0
        var vuPendantLeCollage: (texte: String?, confidentiel: Bool) = (nil, false)
        let c = Collage(presse: presse, delaiRestauration: .milliseconds(150), envoyerCommandeV: {
            envois += 1
            vuPendantLeCollage = (presse.string(forType: .string), presse.types?.contains(Collage.typeConfidentiel) ?? false)
        }, saisieSecurisee: { false })

        remplirOrigine()
        var issue = await c.ecrire("Bonjour le monde", dans: nil, permissionPoster: true)
        verifier(issue == .colle && envois == 1, "collage : ⌘V envoyé une fois")
        verifier(vuPendantLeCollage.texte == "Bonjour le monde", "pendant le collage : le texte est dans le presse-papiers")
        verifier(vuPendantLeCollage.confidentiel, "pendant le collage : marqué confidentiel (ConcealedType)")
        try? await Task.sleep(for: .milliseconds(400))
        verifier(origineIntacte(), "après le délai : tous les éléments d'origine (texte + HTML, 2 éléments) sont revenus")

        remplirOrigine()
        _ = await c.ecrire("Premier", dans: nil, permissionPoster: true)
        presse.clearContents(); presse.setString("copié entre-temps par Hugues", forType: .string)
        try? await Task.sleep(for: .milliseconds(400))
        verifier(presse.string(forType: .string) == "copié entre-temps par Hugues", "presse-papiers modifié entre-temps : pas écrasé")

        remplirOrigine()
        _ = await c.ecrire("Un", dans: nil, permissionPoster: true)
        _ = await c.ecrire("Deux", dans: nil, permissionPoster: true)
        verifier(presse.string(forType: .string) == "Deux", "deux collages rapprochés : le second est bien collé")
        try? await Task.sleep(for: .milliseconds(400))
        verifier(origineIntacte(), "deux collages rapprochés : l'original d'avant le premier revient")

        presse.clearContents()
        _ = await c.ecrire("Texte", dans: nil, permissionPoster: true)
        try? await Task.sleep(for: .milliseconds(400))
        verifier((presse.pasteboardItems ?? []).isEmpty, "presse-papiers vide au départ : il redevient vide")

        envois = 0
        let protege = Collage(presse: presse, delaiRestauration: .milliseconds(150), envoyerCommandeV: { envois += 1 }, saisieSecurisee: { true })
        remplirOrigine()
        issue = await protege.ecrire("secret copié", dans: nil, permissionPoster: true)
        verifier(issue == .champProtege && envois == 0, "champ protégé : aucun ⌘V envoyé")
        verifier(presse.string(forType: .string) == "secret copié" && !(presse.types?.contains(Collage.typeConfidentiel) ?? false), "champ protégé : texte laissé dans le presse-papiers, collable à la main")
        try? await Task.sleep(for: .milliseconds(300))
        verifier(presse.string(forType: .string) == "secret copié", "champ protégé : le texte reste (pas de restauration)")

        envois = 0
        issue = await c.ecrire("sans droit", dans: nil, permissionPoster: false)
        if case .copieSeulement = issue { verifier(envois == 0 && presse.string(forType: .string) == "sans droit", "accessibilité manquante : copie seulement") }
        else { verifier(false, "accessibilité manquante : copie seulement") }

        verifier(await c.ecrire("", dans: nil, permissionPoster: true) == .vide, "texte vide : rien")

        print(echecs == 0 ? "\nCollage : tout est bon" : "\nCollage : \(echecs) échec(s)")
        return echecs == 0 ? 0 : 1
    }
}
