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

    /// Imposé par un mode en ligne de commande (`--comparer-precision`) : le modèle essayé à cet instant.
    nonisolated(unsafe) static var modeleForce: ModeleWhisper?

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
