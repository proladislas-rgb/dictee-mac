import AppKit

let arguments = CommandLine.arguments

// Modes de vérification en ligne de commande. Aucun ne touche au micro, à la reconnaissance vocale,
// à l'accessibilité ni à la surveillance du clavier (sinon macOS attribuerait ces autorisations au Terminal).

CleGroq.utiliserTrousseau = false   // les modes en ligne de commande ne lisent que ~/.config/groq/.env

// Dictee --transcrire fichier.wav  (Groq seulement)
if let i = arguments.firstIndex(of: "--transcrire") {
    guard i + 1 < arguments.count else {
        FileHandle.standardError.write(Data("Usage : Dictee --transcrire fichier.wav\n".utf8))
        exit(2)
    }
    exit(Transcrire.executer(chemin: arguments[i + 1], arguments: arguments))
}

// Dictee --nettoyer "texte" --app com.apple.mail  (remise au propre, réseau seulement)
if arguments.contains("--nettoyer") {
    exit(Nettoyer.executer(arguments: arguments))
}

// Dictee --verifier-flac  (encodage FLAC sans perte, taille et durée ; ni micro ni réseau)
if arguments.contains("--verifier-flac") {
    exit(VerifierFLAC.executer())
}

// Dictee --verifier-collage  (presse-papiers privé, faux ⌘V)
if arguments.contains("--verifier-collage") {
    Task { @MainActor in exit(await VerifierCollage.executer()) }
    RunLoop.main.run()
}

// Dictee --rendu-encoche dossier  (dessine l'encoche en PNG, sans fenêtre)
if let i = arguments.firstIndex(of: "--rendu-encoche"), i + 1 < arguments.count {
    exit(MainActor.assumeIsolated { RenduEncoche.executer(dossier: arguments[i + 1]) })
}

// Dictee --rendu-icones dossier  (icône d'app + planches de contrôle en PNG, sans fenêtre)
if let i = arguments.firstIndex(of: "--rendu-icones"), i + 1 < arguments.count {
    exit(MainActor.assumeIsolated { RenduIcones.executer(dossier: arguments[i + 1]) })
}

// Dictee --rendu-panneau dossier  (panneau compact et ses états en PNG, sans fenêtre)
if let i = arguments.firstIndex(of: "--rendu-panneau"), i + 1 < arguments.count {
    exit(MainActor.assumeIsolated { RenduPanneau.executer(dossier: arguments[i + 1]) })
}

// Dictee --rendu-filet dossier  (filet de sécurité de l'écriture en PNG, sans fenêtre)
if let i = arguments.firstIndex(of: "--rendu-filet"), i + 1 < arguments.count {
    exit(MainActor.assumeIsolated { RenduFilet.executer(dossier: arguments[i + 1]) })
}

// Dictee --rendu-fenetre dossier  (fenêtre principale et ses états en PNG, sans fenêtre)
if let i = arguments.firstIndex(of: "--rendu-fenetre"), i + 1 < arguments.count {
    exit(MainActor.assumeIsolated { RenduFenetre.executer(dossier: arguments[i + 1]) })
}

// Dictee --rendu-premier-lancement dossier  (les trois étapes en PNG, sans fenêtre)
if let i = arguments.firstIndex(of: "--rendu-premier-lancement"), i + 1 < arguments.count {
    exit(MainActor.assumeIsolated { RenduPremierLancement.executer(dossier: arguments[i + 1]) })
}

// Dictee --construire-lexique  (lit les notes de Hugues, écrit lexique.json ; ni micro, ni réseau, ni Accessibilité)
if arguments.contains("--construire-lexique") {
    exit(MainActor.assumeIsolated { ConstruireLexique.executer() })
}

// Dictee --oreille "texte"  (ce que la correction à l'oreille ferait du texte ; aucun réseau)
if let i = arguments.firstIndex(of: "--oreille"), i + 1 < arguments.count {
    exit(MainActor.assumeIsolated { BancLexique.oreille(texte: arguments[i + 1]) })
}

// Dictee --banc-lexique-rejouer dossier  (refait la correction à l'oreille sur les textes déjà reçus ; aucun réseau)
if let i = arguments.firstIndex(of: "--banc-lexique-rejouer"), i + 1 < arguments.count {
    exit(MainActor.assumeIsolated { BancLexique.rejouer(dossier: arguments[i + 1]) })
}

// Dictee --banc-lexique dossier  (phrases de synthèse avant/après le lexique ; réseau seulement)
if let i = arguments.firstIndex(of: "--banc-lexique"), i + 1 < arguments.count {
    let reutiliser = arguments.contains("--reutiliser-avant")
    Task { @MainActor in exit(await BancLexique.executer(dossier: arguments[i + 1], reutiliserAvant: reutiliser)) }
    RunLoop.main.run()
}

// Une option inconnue ne doit jamais lancer la vraie app depuis un shell.
let connues: Set<String> = ["--sans-interface"]
if let inconnue = arguments.dropFirst().first(where: { $0.hasPrefix("--") && !connues.contains($0) && !$0.hasPrefix("--duree=") && !$0.hasPrefix("--verifier-parole=") }) {
    FileHandle.standardError.write(Data("Option inconnue : \(inconnue)\n".utf8))
    exit(2)
}

let options = Options(arguments)
let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate(options: options) }
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
