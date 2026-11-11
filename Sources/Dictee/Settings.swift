import Foundation
import DicteeCore

/// Réglages simples (le panneau de réglages arrive au lot 7). Modifiables avec `defaults write com.hugues.dictee ...`.
enum Settings {
    private static let defaults = UserDefaults.standard

    /// Langue de la dictée : `fr` (par défaut), `en`, ou `auto`. La détection automatique de Whisper se trompe sur les phrases
    /// très courtes (« Est-ce que ça marche ? » compris comme de l'allemand), d'où le français par défaut.
    /// Exemple : defaults write com.hugues.dictee langue en   (`DICTEE_LANGUE=auto` pour les mesures)
    static var langueReglage: String {
        ChoixLangue.parametre(reglage: ProcessInfo.processInfo.environment["DICTEE_LANGUE"] ?? defaults.string(forKey: "langue")) ?? ChoixLangue.automatique
    }

    /// Langue envoyée à Whisper ; `nil` = détection automatique (limitée à `languesAutorisees`).
    static var langue: String? { langueReglage == ChoixLangue.automatique ? nil : langueReglage }

    /// En mode Automatique : les langues acceptées (français et anglais par défaut). Une autre langue détectée fait relancer le morceau.
    static var languesAutorisees: [String] {
        let env = ProcessInfo.processInfo.environment["DICTEE_LANGUES"].map { $0.split(separator: ",").map(String.init) }   // mesures
        let l = env ?? defaults.stringArray(forKey: "languesAutorisees") ?? []
        return l.isEmpty ? ChoixLangue.autoriseesParDefaut : l
    }

    /// Modèle de transcription : `rapide` (whisper-large-v3-turbo) ou `precis` (whisper-large-v3). Réglage « Vitesse de transcription »
    /// (Réglages › Écriture). `DICTEE_MODELE_WHISPER=rapide|precis` pour les mesures.
    /// Exemple : defaults write com.hugues.dictee modeleWhisper precis
    static var modeleWhisper: ModeleWhisper {
        get {
            if let force = modeleForce { return force }
            return ModeleWhisper.depuis(reglage: ProcessInfo.processInfo.environment["DICTEE_MODELE_WHISPER"] ?? defaults.string(forKey: "modeleWhisper")) ?? ModeleWhisper.parDefaut
        }
        set { defaults.set(newValue.rawValue, forKey: "modeleWhisper") }
    }

    /// Test de précision sur la vraie voix : nombre de dictées dont le son sera encore gardé (0 = désactivé, défaut). Activer le réglage met 50.
    /// Les sons sont gardés localement dans `test-precision/` (0600), jamais envoyés ailleurs que chez Groq comme n'importe quelle dictée.
    static var testPrecisionRestant: Int {
        get { max(0, defaults.integer(forKey: "testPrecisionRestant")) }
        set { defaults.set(max(0, newValue), forKey: "testPrecisionRestant") }
    }

    /// Imposé par un mode en ligne de commande (`--comparer-precision`) : le modèle essayé à cet instant.
    nonisolated(unsafe) static var modeleForce: ModeleWhisper?
    /// Imposé par `--comparer-precision` : temps maximal de la relecture seule (on veut voir sa qualité, pas son délai).
    nonisolated(unsafe) static var delaiRelectureForce: Double?

    /// Latences mesurées chez Hugues pour chaque modèle (affichées discrètement dans les Réglages).
    static var latences: SuiviLatence {
        get { SuiviLatence.depuis(defaults.data(forKey: "latencesWhisper")) }
        set { defaults.set(newValue.donnees(), forKey: "latencesWhisper") }
    }

    /// Délai maximal d'attente de Groq après le relâchement, avant de passer au texte de secours d'Apple.
    static let delaiGroq: Double = 4.0

    /// « Remettre au propre » (hésitations, corrections dites, ponctuation, mise en forme). Activé par défaut.
    /// Exemple : defaults write com.hugues.dictee remettreAuPropre -bool false
    static var remettreAuPropre: Bool {
        get { defaults.object(forKey: "remettreAuPropre") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "remettreAuPropre") }
    }

    /// Modèle de langue de Groq pour la remise au propre (nom vérifié avec GET /openai/v1/models le 09/11).
    static var modeleNettoyage: String {
        ProcessInfo.processInfo.environment["DICTEE_MODELE_NETTOYAGE"].flatMap { $0.isEmpty ? nil : $0 }   // mesures en ligne de commande
            ?? defaults.string(forKey: "modeleNettoyage").flatMap { $0.isEmpty ? nil : $0 } ?? "openai/gpt-oss-20b"
    }

    /// Délai maximal de la remise au propre ; au-delà, le texte brut de Groq est collé.
    static let delaiNettoyage: Double = 1.2

    /// Son envoyé à Groq en FLAC (plus léger). `defaults write com.hugues.dictee envoiFLAC -bool false` revient au WAV.
    static var envoiFLAC: Bool { reglage("DICTEE_ENVOI", "envoiFLAC", defaut: true, faux: "wav") }

    /// Rognage du silence de fin de chaque morceau (0,25 s gardées). Interrupteur de mesure : `DICTEE_ROGNAGE=non`.
    static var rognageFin: Bool { reglage("DICTEE_ROGNAGE", "rognageFin", defaut: true, faux: "non") }

    /// Envoi anticipé du dernier morceau à la pause de 0,3 s. `DICTEE_ANTICIPATION=non` ou `defaults write ... envoiAnticipe -bool false`.
    static var envoiAnticipe: Bool { reglage("DICTEE_ANTICIPATION", "envoiAnticipe", defaut: true, faux: "non") }

    /// Seconde requête identique quand Groq tarde (> 0,7 s). `DICTEE_SECOURS=non` ou `defaults write ... requeteDeSecours -bool false`.
    static var requeteDeSecours: Bool { reglage("DICTEE_SECOURS", "requeteDeSecours", defaut: true, faux: "non") }

    /// Coupes des longues dictées (micro-pause après 8 s, coupe forcée après 12 s). `DICTEE_DECOUPE=ancienne` : seulement les pauses de 0,5 s.
    static var decoupeLongue: Bool { reglage("DICTEE_DECOUPE", "decoupeLongue", defaut: true, faux: "ancienne") }

    /// Remise au propre par unités de phrases pendant les longues dictées. `DICTEE_UNITES=non` pour revenir au texte entier d'un coup.
    static var nettoyageParUnites: Bool { reglage("DICTEE_UNITES", "nettoyageParUnites", defaut: true, faux: "non") }

    /// Le grand lexique local (lexique.json) choisit les mots envoyés à Whisper à chaque dictée. `DICTEE_LEXIQUE=non` (mesures) ou
    /// `defaults write com.hugues.dictee lexiquePourWhisper -bool false` pour revenir à mots.txt seul.
    static var lexiquePourWhisper: Bool { reglage("DICTEE_LEXIQUE", "lexiquePourWhisper", defaut: true, faux: "non") }

    /// Correction « à l'oreille » après Whisper (« Brionia » → « Brillonia »). `DICTEE_OREILLE=non` ou `defaults write ... correctionALOreille -bool false`.
    static var correctionALOreille: Bool { reglage("DICTEE_OREILLE", "correctionALOreille", defaut: true, faux: "non") }

    /// Apprendre des corrections de Hugues juste après une dictée (propositions dans « Mots »). `defaults write ... apprentissageDesCorrections -bool false`.
    static var apprentissageDesCorrections: Bool { reglage("DICTEE_APPRENTISSAGE", "apprentissageDesCorrections", defaut: true, faux: "non") }

    /// Relecture de sens après Whisper (corrige les mots mal entendus d'après le contexte). `DICTEE_RELECTURE=non` ou `defaults write ... relectureDeSens -bool false`.
    static var relecture: Bool { reglage("DICTEE_RELECTURE", "relectureDeSens", defaut: true, faux: "non") }

    /// Les expressions personnelles de Hugues sont données à Whisper et à la relecture. `DICTEE_EXPRESSIONS=non` ou `defaults write ... expressionsPourWhisper -bool false`.
    static var expressionsPourWhisper: Bool { reglage("DICTEE_EXPRESSIONS", "expressionsPourWhisper", defaut: true, faux: "non") }

    /// Modèle de langue de la relecture seule (texte déjà propre ou trop court pour la remise au propre).
    static var modeleRelecture: String {
        ProcessInfo.processInfo.environment["DICTEE_MODELE_RELECTURE"].flatMap { $0.isEmpty ? nil : $0 }
            ?? defaults.string(forKey: "modeleRelecture").flatMap { $0.isEmpty ? nil : $0 } ?? ModelesTexte.rapide
    }

    /// Temps maximal de la relecture seule (au-delà, le texte est collé sans elle). Mesures : `DICTEE_DELAI_RELECTURE=0.6`.
    static var delaiRelecture: Double {
        delaiRelectureForce ?? ProcessInfo.processInfo.environment["DICTEE_DELAI_RELECTURE"].flatMap { Double($0) } ?? 0.25
    }

    /// Interrupteur de vitesse : la variable d'environnement (mesures en ligne de commande) l'emporte sur le réglage.
    private static func reglage(_ variable: String, _ cle: String, defaut: Bool, faux: String) -> Bool {
        if let v = ProcessInfo.processInfo.environment[variable] { return v != faux }
        return defaults.object(forKey: cle) as? Bool ?? defaut
    }

    /// Au bout de ce délai sans réponse, la remise au propre envoie une seconde requête identique (la première réponse gagne).
    /// Mettre 99 pour la désactiver (mesures : `DICTEE_SECOURS=non`).
    static var secoursNettoyage: Double { requeteDeSecours ? 0.55 : 99 }

    /// Nombre maximal de dictées gardées dans l'historique.
    static var limiteHistorique: Int {
        let v = defaults.integer(forKey: "limiteHistorique")
        return v > 0 ? v : Historique.limiteParDefaut
    }

    /// Adapter le ton à l'app qui reçoit le texte (courriel soigné, message direct, terminal brut…). Activé par défaut.
    static var adapterLeTon: Bool {
        get { defaults.object(forKey: "adapterLeTon") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "adapterLeTon") }
    }

    /// Filet de sécurité : si le texte n'arrive pas dans le champ, l'encoche reste ouverte avec le texte à copier. Activé par défaut.
    /// Exemple : defaults write com.hugues.dictee filetDeSecurite -bool false
    static var filetDeSecurite: Bool {
        get { defaults.object(forKey: "filetDeSecurite") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "filetDeSecurite") }
    }

    /// Secours : le texte de la dictée d'Apple quand Groq ne répond pas. Activé par défaut.
    /// Petits sons au début de la dictée, au texte collé et à l'annulation. Activé par défaut (Hugues : un son grave et chaud en plus des vibrations).
    /// Exemple : defaults write com.hugues.dictee sons -bool false
    static var sons: Bool {
        get { defaults.object(forKey: "sons") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "sons") }
    }

    /// Retour haptique du trackpad (se sent seulement avec un doigt posé sur un trackpad Force Touch). Activé par défaut.
    /// Exemple : defaults write com.hugues.dictee vibration -bool false
    static var vibration: Bool {
        get { defaults.object(forKey: "vibration") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "vibration") }
    }

    static var secoursApple: Bool {
        get { defaults.object(forKey: "secoursApple") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "secoursApple") }
    }

    // MARK: Notes de réunion

    /// Garder le son brut des réunions (deux fichiers WAV, un par piste) à côté de la note. Désactivé par défaut : le son n'existe alors
    /// que le temps de la transcription, en mémoire. Exemple : defaults write com.hugues.dictee garderSonReunions -bool true
    static var garderSonReunions: Bool {
        get { defaults.object(forKey: "garderSonReunions") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "garderSonReunions") }
    }

    /// Proposer « Noter cet appel ? » quand une app d'appel utilise le micro (jamais d'enregistrement sans clic). Activé par défaut.
    static var proposerLesAppels: Bool {
        get { defaults.object(forKey: "proposerLesAppels") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "proposerLesAppels") }
    }

    /// Modèle de langue de Groq pour la note de réunion (nom vérifié avec GET /openai/v1/models le 09/11 : le plus gros disponible).
    static var modeleNoteReunion: String {
        ProcessInfo.processInfo.environment["DICTEE_MODELE_NOTE"].flatMap { $0.isEmpty ? nil : $0 }
            ?? defaults.string(forKey: "modeleNoteReunion").flatMap { $0.isEmpty ? nil : $0 } ?? "openai/gpt-oss-120b"
    }

    /// Langue choisie dans les Réglages (`fr`, `en`) ou `nil` pour la détection automatique.
    static func choisirLangue(_ code: String?) { defaults.set(code ?? "auto", forKey: "langue") }

    /// Micro choisi : `nil` = Automatique (micro intégré du Mac quand un casque Bluetooth est le micro par défaut, sinon le micro par défaut),
    /// `"systeme"` = micro du système tel quel, sinon l'identifiant CoreAudio d'un micro précis (AirPods compris). Voir `ChoixMicro`.
    static var micro: String? {
        get { defaults.string(forKey: "microUID").flatMap { $0.isEmpty ? nil : $0 } }
        set { defaults.set(newValue ?? "", forKey: "microUID") }
    }

    // MARK: Lecture en cours

    /// Afficher dans l'encoche ce qui joue sur le Mac (musique, vidéo) avec ses commandes. Activé par défaut ; coupé, le programme d'aide
    /// n'est jamais lancé. Exemple : defaults write com.hugues.dictee afficherLaLecture -bool false
    static var afficherLaLecture: Bool {
        get { defaults.object(forKey: "afficherLaLecture") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "afficherLaLecture") }
    }

    /// Mettre la lecture en pause pendant une dictée, puis la reprendre (seulement si c'est Verbe qui l'a mise en pause). Activé par défaut ;
    /// n'a d'effet que si la lecture est affichée. Exemple : defaults write com.hugues.dictee pauseLecturePendantDictee -bool false
    static var pauseLecturePendantDictee: Bool {
        get { defaults.object(forKey: "pauseLecturePendantDictee") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "pauseLecturePendantDictee") }
    }

    // MARK: Îlot (centre d'activités)

    /// Minuteur dans l'îlot (depuis l'accueil, ou en le dictant quand l'accueil est ouvert). Activé par défaut.
    static var ilotMinuteur: Bool {
        get { defaults.object(forKey: "ilotMinuteur") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "ilotMinuteur") }
    }
    /// Rappels dans l'îlot, gardés localement (Application Support/Dictee/rappels.json). Activé par défaut.
    static var ilotRappels: Bool {
        get { defaults.object(forKey: "ilotRappels") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "ilotRappels") }
    }
    /// Rendez-vous des calendriers du Mac dans l'îlot. ÉTEINT par défaut : l'autorisation n'est demandée qu'à l'activation, jamais au lancement.
    static var ilotCalendrier: Bool {
        get { defaults.object(forKey: "ilotCalendrier") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "ilotCalendrier") }
    }
    /// Notifications des autres apps dans l'îlot (lecture du Centre de notifications par l'Accessibilité). ÉTEINT par défaut : expérimental.
    static var ilotNotifications: Bool {
        get { defaults.object(forKey: "ilotNotifications") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "ilotNotifications") }
    }
    /// La batterie du Mac et des écouteurs dans l'îlot (épaules du déplié, chargeur branché, batterie faible, écouteurs connectés).
    /// ALLUMÉ par défaut : la batterie ne demande rien ; macOS demande une fois l'accès au Bluetooth pour les écouteurs.
    static var ilotEnergie: Bool {
        get { defaults.object(forKey: "ilotEnergie") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "ilotEnergie") }
    }
    /// Les fichiers qui arrivent dans Téléchargements (AirDrop compris) : un bandeau de 4 s avec « Ouvrir ».
    /// ÉTEINT par défaut : macOS demande l'accès au dossier Téléchargements, seulement quand on allume le réglage (jamais au lancement).
    static var ilotTelechargements: Bool {
        get { defaults.object(forKey: "ilotTelechargements") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "ilotTelechargements") }
    }
    /// « Micro coupé » : le raccourci coupe le micro du Mac et le rouvre, l'îlot le rappelle tant qu'il est coupé. ALLUMÉ par défaut :
    /// rien n'est demandé à macOS (couper un micro n'écoute rien).
    static var ilotMicro: Bool {
        get { defaults.object(forKey: "ilotMicro") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "ilotMicro") }
    }
    /// « Volume et luminosité dans l'îlot » : les touches du clavier s'affichent dans l'îlot au lieu de l'affichage de macOS. ALLUMÉ
    /// par défaut : rien n'est demandé à macOS (l'écoute du clavier est déjà là pour fn).
    static var ilotNiveaux: Bool {
        get { defaults.object(forKey: "ilotNiveaux") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "ilotNiveaux") }
    }
    /// L'étagère : des fichiers glissés sur l'encoche y restent (un signet, jamais une copie) ; on les reprend depuis l'accueil.
    /// ALLUMÉE par défaut. Rien n'est lu au lancement : les signets sont relus à l'ouverture de l'accueil ou de la carte (un fichier
    /// rangé depuis le Bureau, les Documents ou une clé peut alors faire demander l'accès à macOS, toujours après un geste).
    static var ilotEtagere: Bool {
        get { defaults.object(forKey: "ilotEtagere") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "ilotEtagere") }
    }
    /// « Claude au travail » : l'îlot montre où en est Claude Code (crochets branchés depuis les Réglages). ALLUMÉ par défaut : tant que
    /// les crochets ne sont pas branchés, le dossier des sessions reste vide et rien ne s'affiche.
    static var ilotClaude: Bool {
        get { defaults.object(forKey: "ilotClaude") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "ilotClaude") }
    }
    /// Le Centre de l'îlot : la bulle « Nouveau : survole l'îlot » a été montrée (une seule fois, au premier lancement).
    static var ilotBulleVue: Bool {
        get { defaults.bool(forKey: "ilotBulleVue") }
        set { defaults.set(newValue, forKey: "ilotBulleVue") }
    }
    /// Le Centre a déjà été ouvert depuis la lecture : l'aide « Fais défiler ou clique ici » ne s'affiche plus sous le bouton Centre.
    static var ilotCentreUtilise: Bool {
        get { defaults.bool(forKey: "ilotCentreUtilise") }
        set { defaults.set(newValue, forKey: "ilotCentreUtilise") }
    }
    /// Ce que le Centre de l'îlot montre, dans l'ordre (« Modifier ») : des identifiants (`ElementCentre`) ; nil = jamais modifié (la
    /// disposition par défaut). Les identifiants inconnus sont ignorés à la lecture.
    static var ilotCentreBoutons: [String]? {
        get { defaults.stringArray(forKey: "ilotCentreBoutons") }
        set { defaults.set(newValue, forKey: "ilotCentreBoutons") }
    }
    /// Pour un micro sans muet, coupé en mettant son volume d'entrée à 0 : son ancien volume, par micro (UID CoreAudio), pour le rendre.
    static var microVolumesGardes: [String: Double] {
        get { defaults.dictionary(forKey: "microVolumesGardes") as? [String: Double] ?? [:] }
        set { defaults.set(newValue, forKey: "microVolumesGardes") }
    }
    /// Le son de la fin d'un minuteur : le nom d'un son du Mac (« Pop » par défaut, celui de la dictée), ou « Aucun ».
    static var sonFinMinuteur: String {
        get { defaults.string(forKey: "sonFinMinuteur").flatMap { $0.isEmpty ? nil : $0 } ?? "Pop" }
        set { defaults.set(newValue, forKey: "sonFinMinuteur") }
    }
    static let sonsDisponibles = ["Pop", "Glass", "Ping", "Hero", "Tink", "Submarine", "Aucun"]

    // MARK: Mise à jour automatique

    /// Vérifier GitHub une fois par jour s'il existe une nouvelle version. Activé par défaut.
    /// Exemple : defaults write com.hugues.dictee verifierLesMisesAJour -bool false
    static var verifierLesMisesAJour: Bool {
        get { defaults.object(forKey: "verifierLesMisesAJour") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "verifierLesMisesAJour") }
    }

    /// Dernière vérification qui a abouti (la dernière réponse lisible de GitHub).
    static var miseAJourDerniereReussite: Date? {
        get { defaults.object(forKey: "miseAJourDerniereReussite") as? Date }
        set { defaults.set(newValue, forKey: "miseAJourDerniereReussite") }
    }

    /// Dernière tentative, réussie ou non (limite la fréquence quand le réseau manque).
    static var miseAJourDerniereTentative: Date? {
        get { defaults.object(forKey: "miseAJourDerniereTentative") as? Date }
        set { defaults.set(newValue, forKey: "miseAJourDerniereTentative") }
    }

    /// GitHub a demandé de patienter (limite de requêtes) : rien n'est demandé avant cette heure.
    static var miseAJourPasAvant: Date? {
        get { defaults.object(forKey: "miseAJourPasAvant") as? Date }
        set { defaults.set(newValue, forKey: "miseAJourPasAvant") }
    }

    /// « Plus tard » : la version repoussée et l'heure du prochain rappel.
    static var miseAJourReport: ReportProposition? {
        get {
            guard let v = defaults.string(forKey: "miseAJourReportVersion").flatMap(VersionApp.init),
                  let d = defaults.object(forKey: "miseAJourReportJusqua") as? Date else { return nil }
            return ReportProposition(version: v, jusqua: d)
        }
        set {
            defaults.set(newValue?.version.description, forKey: "miseAJourReportVersion")
            defaults.set(newValue?.jusqua, forKey: "miseAJourReportJusqua")
        }
    }

    /// Version qu'une mise à jour vient d'installer (lue au lancement suivant pour le journal, puis effacée).
    static var miseAJourInstallee: String? {
        get { defaults.string(forKey: "miseAJourInstallee") }
        set { defaults.set(newValue, forKey: "miseAJourInstallee") }
    }

    /// Le premier lancement (3 étapes) a été fait : il ne s'affiche plus tout seul.
    static var premierLancementFait: Bool {
        get { defaults.bool(forKey: "premierLancementFait") }
        set { defaults.set(newValue, forKey: "premierLancementFait") }
    }
}
