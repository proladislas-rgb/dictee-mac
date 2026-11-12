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

// Dictee --comparer-precision  (repasse les sons du test de précision en turbo / large-v3 / + relecture ; réseau seulement)
if arguments.contains("--comparer-precision") {
    Task { @MainActor in exit(await ComparerPrecision.executer(arguments: arguments)) }
    RunLoop.main.run()
}

// Dictee --declencheurs [--exemples]  (combien de dictées de l'historique auraient déclenché la relecture de sens ; ni réseau ni micro)
if arguments.contains("--declencheurs") {
    exit(MainActor.assumeIsolated { MesurerRelecture.executer(arguments: arguments) })
}

// Dictee --reunion-test moi.wav eux.wav [--sortie DOSSIER] [--sans-note] [--modeles DOSSIER]  (deux pistes -> transcription, voix séparées
// sur le Mac -> note ; réseau : Groq, et le premier téléchargement du modèle de voix)
if let i = arguments.firstIndex(of: "--reunion-test") {
    guard i + 2 < arguments.count, !arguments[i + 1].hasPrefix("--"), !arguments[i + 2].hasPrefix("--") else {
        FileHandle.standardError.write(Data("Usage : Dictee --reunion-test moi.wav eux.wav [--sortie DOSSIER] [--sans-note]\n".utf8))
        exit(2)
    }
    exit(ReunionTest.executer(moi: arguments[i + 1], eux: arguments[i + 2], arguments: arguments))
}

// Dictee --voix-mesure piste-eux.wav [--verite tours.tsv] [--modeles DOSSIER]  (séparation des voix sur le Mac : temps, mémoire,
// taille du modèle, justesse ; ni micro, ni son du Mac, ni Groq ; réseau seulement pour le premier téléchargement du modèle)
if let i = arguments.firstIndex(of: "--voix-mesure") {
    guard i + 1 < arguments.count, !arguments[i + 1].hasPrefix("--") else {
        FileHandle.standardError.write(Data("Usage : Dictee --voix-mesure piste-eux.wav [--verite tours.tsv] [--modeles DOSSIER]\n".utf8))
        exit(2)
    }
    exit(MesureVoix.executer(chemin: arguments[i + 1], arguments: arguments))
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

// Dictee --rendu-lecture dossier  (l'îlot de la lecture en cours et la bulle de dictée en PNG, sans fenêtre)
if let i = arguments.firstIndex(where: { $0 == "--rendu-lecture" || $0 == "--rendu-ilot" }), i + 1 < arguments.count {
    exit(MainActor.assumeIsolated { RenduLecture.executer(dossier: arguments[i + 1]) })
}

// Dictee --ilot-essai  (essai de bout en bout de l'îlot : priorités, pastille, minuteur, rappels, calendrier simulé ; fenêtre transparente ;
// ni micro, ni clavier, ni Accessibilité, ni son, ni calendrier, ni notifications)
if arguments.contains("--ilot-essai") {
    exit(MainActor.assumeIsolated { IlotEssai.executer() })
}

// Dictee --lecture-test [secondes]  (lance le programme d'aide de la lecture en cours, affiche ce qui joue ; ni micro, ni clavier, ni Accessibilité)
if let i = arguments.firstIndex(of: "--lecture-test") {
    let secondes = (i + 1 < arguments.count ? Double(arguments[i + 1]) : nil) ?? 6
    exit(MainActor.assumeIsolated { LectureTest.executer(secondes: secondes) })
}

// Dictee --miniature-essai [identifiant]  (téléchargement et cache de la miniature YouTube ; réseau seulement)
if arguments.contains("--miniature-essai") {
    exit(MainActor.assumeIsolated { MiniatureEssai.executer(arguments: arguments) })
}

// Dictee --rendu-reunion dossier  (encoche des réunions, liste et note en PNG, sans fenêtre)
if let i = arguments.firstIndex(of: "--rendu-reunion"), i + 1 < arguments.count {
    exit(MainActor.assumeIsolated { RenduReunions.executer(dossier: arguments[i + 1]) })
}

// Dictee --rendu-journee dossier  (l'onglet Journée et ses états en PNG, sans fenêtre)
if let i = arguments.firstIndex(of: "--rendu-journee"), i + 1 < arguments.count {
    exit(MainActor.assumeIsolated { RenduJournee.executer(dossier: arguments[i + 1]) })
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

// Dictee --verifier-mise-a-jour [--version-actuelle X] [--api URL locale]  (interroge GitHub et dit ce que Verbe proposerait ; réseau seulement, n'installe rien)
if arguments.contains("--verifier-mise-a-jour") {
    Task { @MainActor in exit(await MiseAJourTest.verifier(arguments: arguments)) }
    RunLoop.main.run()
}

// Dictee --installer-mise-a-jour-test --api URL locale --app COPIE.app  (installe sur une COPIE, sans relancer ; ni micro, ni clavier)
if arguments.contains("--installer-mise-a-jour-test") {
    Task { @MainActor in exit(await MiseAJourTest.installer(arguments: arguments)) }
    RunLoop.main.run()
}

// Dictee --rendu-mise-a-jour dossier  (la ligne sous l'encoche et la ligne des Réglages en PNG, sans fenêtre)
if let i = arguments.firstIndex(of: "--rendu-mise-a-jour"), i + 1 < arguments.count {
    exit(MainActor.assumeIsolated { RenduMiseAJour.executer(dossier: arguments[i + 1]) })
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
