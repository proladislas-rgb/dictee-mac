# Audit de dette technique — Verbe (bientôt Lucarne)

12/11/2026 · audit en lecture seule · rien n'a été modifié dans le code.

**Base de l'audit.** Le commit `37837ed` (HEAD de `main`), lu dans un worktree à part. La copie de travail de `main` contient en plus 21 fichiers modifiés et pas encore commités : les numéros de ligne peuvent donc bouger d'environ 50 lignes d'ici la fusion. Le code a été compilé à neuf dans ce worktree (311 s en debug, 28 avertissements distincts) et `swift run DicteeControles` y a été lancé.

**Chiffres.**

| Partie | Lignes |
|---|---|
| App (`Sources/Dictee`, 120 fichiers) | 30 251 |
| Logique pure (`DicteeCore`, 61 fichiers) | 9 602 |
| Contrôles (`DicteeControles`) | 3 690 |
| Outils de dev livrés dans l'app (rendus, essais, bancs) | ≈ 5 360 |

---

## 0. En bref : les 10 constats qui comptent

| # | Gravité | Constat | Où |
|---|---|---|---|
| 1 | **Bug** | Le délai de 1,5 s du secours Apple ne coupe rien. `withTaskGroup` attend toujours `secours.value`, une tâche à part que `cancelAll()` n'annule pas. Si la reconnaissance Apple bloque, la dictée attend sans fin. C'est le piège déjà noté dans `lessons.md` le 09/11 (« Premiere »). | `DictationController.swift:261-263` |
| 2 | Haut | La cible app compile en **mode Swift 5** : le compilateur ne vérifie aucune course de données. Pour tenir, le code empile 34 `@unchecked Sendable`, 9 `nonisolated(unsafe)`, 98 `MainActor.assumeIsolated` et 24 `NSLock` faits main. Cinq avertissements signalent déjà des erreurs futures en Swift 6. | `Package.swift:17` |
| 3 | Haut | **Objets-dieu.** `IlotMoteur` : 1 389 l., environ 147 propriétés stockées, un seul `@Published rev` pour tout, et il connaît Claude, l'étagère, les Dictées et les Outils. `IlotControleur` : 808 l., 81 propriétés presque toutes publiques, étendu dans 7 fichiers, et `ActionIlot` compte environ 50 cas routés à plat. | `IlotMoteur.swift`, `IlotControleur.swift` |
| 4 | Haut | Chaque image d'animation (60 à 120 Hz) incrémente `rev`, ce qui fait réévaluer **tout l'arbre SwiftUI** de l'îlot (42 `@ObservedObject var m: IlotMoteur` dans 8 fichiers). C'est le vrai coût processeur, pas la minuterie. | `IlotMoteur.swift:219`, `:1250` |
| 5 | Moyen | **5 360 lignes d'outils de dev livrées dans l'app** : 26 options `--`, rendus PNG, `--ilot-essai`, bancs d'essai, et `ConstruireLexique`, qui parcourt le dossier personnel. Des crochets d'essai vivent aussi dans les types de production (`VueSourceFichiers.essai`, `CadenceEcran.minuterieSeulement`). | `main.swift`, `IlotEssai*.swift`, `Rendu*.swift` |
| 6 | Moyen | **Audio dupliqué.** Le choix « micro direct `EntreeHAL` ou `AVAudioEngine` », le garde-fou et le redémarrage sont écrits deux fois (dictée et réunion). La conversion en 16 kHz est copiée telle quelle. `EntreeHAL` alloue de la mémoire et appelle `dispatch` sur le fil temps réel. | `AudioCapture.swift:150-195` / `MicroReunion.swift:40-95` ; `RecordingPipeline.swift:95` / `PisteReunion.swift:129` ; `EntreeHAL.swift:85-89` |
| 7 | Moyen | **L'écoute du clavier passe par le fil principal.** Le tap `.defaultTap` en tête reçoit chaque frappe du Mac et rend sa réponse de façon synchrone sur le fil principal. Un ralenti de l'interface ralentit donc la frappe partout, ou macOS coupe le tap. `arreter()` n'invalide pas le port et il n'y a pas de `deinit`. | `KeyMonitor.swift:55-98` |
| 8 | Moyen | **Pas de jeu de composants.** Trois magasins JSON identiques, trois boutons « pilule », trois listes qui défilent, chacune avec son propre décalage, sa borne et son fondu, et 13 absorbeurs de clics recopiés. On compte aussi 149 `.white.opacity(`, 199 `.font(.system(size:` et 20 `Color(hex:)` hors des jetons. | voir § 2 |
| 9 | Moyen | **Réglages en boilerplate.** 64 membres statiques, des clés en chaînes et un triple recopiage dans `ReglagesModele`. 18 réglages de développeur n'ont aucune interface, dont 11 interrupteurs livrés allumés. Environ 140 lignes peuvent disparaître. | `Settings.swift`, `ReglagesModele.swift` |
| 10 | Moyen | **Dépôt public alourdi.** 48 Mo de rendus PNG/HTML sont suivis par git (287 fichiers) et `.git` pèse 166 Mo. Les fichiers les plus modifiés depuis le 10/11 sont aussi les plus gros, donc ceux qui créent le plus de conflits : `IlotMoteur` 24 commits, `IlotEssai` 20, `IlotControleur` 20, `IlotVues` 19. | `design/` |

**Ce qui va bien, honnêtement :**
- `DicteeCore` est vraiment pur et bien couvert : 2 398 contrôles passent en 3,6 s, sans réseau, sans dossier personnel ni hasard.
- La confidentialité est soignée : clé dans le Trousseau, fichiers en 0600, journal limité à 30 caractères du texte dicté.
- Toutes les API privées ont un repli.
- Au repos, presque rien ne tourne en sondage : tout réagit à des événements.
- Il n'y a aucun cycle de types entre contrôleur, moteur et vues.

---

## 1. Carte de l'architecture

### Modules

| Cible | Rôle | Remarque |
|---|---|---|
| `DicteeCore` (bibliothèque) | Logique pure : découpe de la voix, remise au propre, lexique, îlot (`Ilot`, `CentreIlot`, `DispositionCentre`, `EtagereIlot`, `ClaudeIlot`, `OutilsIlot`, `MicroIlot`, `NiveauIlot`…), réunions, mise à jour, journée. | Bonne frontière. Aucun AppKit. |
| `VerbeObjC` | `VerbeEssayer` : rattrape les `NSException` d'AVFoundation. | Petit et justifié. |
| `Dictee` (exécutable) | L'app, plus 26 modes en ligne de commande, les rendus et les essais. | Mode Swift 5. Mélange production et outillage. |
| `DicteeControles` (exécutable) | Contrôles de `DicteeCore` uniquement. | L'app n'a aucun test automatique. |

### Les plus gros fichiers (HEAD)

| Fichier | Lignes | Rôle réel |
|---|---|---|
| `DicteeControles/main.swift` | 1 918 | Contrôles du cœur |
| `DicteeControles/ControlesIlot.swift` | 1 486 | Contrôles de l'îlot (cœur) |
| `Dictee/IlotMoteur.swift` | 1 389 | État, arbitrage, horloge, survol, étagère, cartes, ressorts, géométrie |
| `Dictee/IlotEssai.swift` | 1 099 | Essai graphique (291 `attendre`) |
| `Dictee/IlotVues.swift` | 1 051 | `IlotCalques` (environ 450 l. dans une seule struct) et petites pièces |
| `Dictee/CentreIlot.swift` | 996 | Vues du Centre, `ReglagesCentre`, et un contrôleur (`agirCentre`) |
| `Dictee/IlotEtagere.swift` | 890 | Magasin, signets, contrôleur, glisser AppKit, AirDrop, vues |
| `Dictee/IlotOutils.swift` | 851 | Quatre outils dans un fichier |
| `Dictee/ReunionsFenetre.swift` | 814 | Fenêtre des réunions |
| `Dictee/IlotControleur.swift` | 808 | Routeur d'actions, sources, minuteur, rappels, agenda, notifications |
| `DicteeCore/ClaudeIlot.swift` | 757 | JSON ordonné, crochets, lecture des sessions |

### Objets-dieu et découpes naturelles

**`IlotMoteur`.** 15 types au premier niveau. Il est étendu dans 5 autres fichiers : `CentreIlot:132`, `CentreModifier:31`, `IlotClaude:38`, `IlotCarteClaude:301`, `IlotAnnonces:102`. Ses blocs :

| Lignes | Contenu |
|---|---|
| 6-210 | Types : `BandeauIlot` avec 12 charges optionnelles, `ActionIlot` avec environ 50 cas, `CourbesIlot` |
| 412-594 | Arbitrage (`donneesChangees`, 66 l.) |
| 595-666 | Horloge des contenus |
| 849-973 | Souris et survol |
| 974-1085 | Étagère |
| 1086-1206 | Cartes et défilement |
| 1207-1270 | Ressorts |
| 1271-1365 | Géométrie |

Le commentaire de la ligne 80 dit que le moteur « ne sait rien » des fonctions. C'est faux pour l'étagère, Claude et les Dictées : environ 46 mentions de Claude, 32 de l'étagère et 34 des notes.

**`IlotControleur`.** Ses blocs :
- environ 30 fermetures injectées (34-222) ;
- `agir` (522-622, 91 l.), un routeur à plat ;
- minuteur (624-664) ;
- rappels (665-711) ;
- agenda (712-765).

Deux de ses extensions vivent dans des fichiers de vues : `CentreIlot.swift:919` et `IlotEtagere.swift:87`. Il garde aussi son propre `etagere` (:178), en double de celui du moteur (:262), ce qui oblige à appeler `donneesChangees()` à la main.

**`IlotEtagere`.** Trois couches dans un seul fichier : magasin (15-86), contrôleur (87-345), AppKit/AirDrop (345-470) et vues (471-890).

**`IlotPanneau`.** Le glisser de l'étagère (398-604, environ 200 l.) est mêlé à la vie de la fenêtre.

### Ce qui devrait passer dans `DicteeCore` (pur, testable)

- `CourbesIlot` (`IlotMoteur:187-210`), `aspect(_:rang:voyage:)` (:609-630), et `ApparitionIlot`, `AspectIlot`, `FamilleIlot`, `ExtraIlot` (:131-186).
- Les bornes de défilement (`defilerCarteClaude` :1028, `defilerNotes` :1073), qui recopient `CarteDictees.borner`, déjà dans le cœur. Avec elles, le routage de `recevoirDefilement` (:1131-1148).
- La table de largeurs de `largeurPastille` (:1285-1304).
- Le lecteur de lignes de `SurveillanceClaude.relire` (`IlotClaude:~235-258`) : décalage, reste, plafonds de 8 Mo et 1 Mo, et `effacerLesVieux`.
- `SurveillanceDossier.estUnRefus` et `codePosix` (`IlotTelechargements:~143-152`).

### Couplage

Les couches sont saines dans leur principe : le contrôleur pousse vers le moteur, le moteur remonte par des fermetures (`surAction`, `surFenetre`, `surMoniteur`), et les vues ne voient que le moteur.

Les fuites :
- les extensions du contrôleur dans des fichiers de vues ;
- un bus `Notification.Name.verbeIlotReglages` ;
- des singletons utilisés comme valeurs par défaut (`HistoriqueStore.shared`, `GroqClient.shared`, environ 40 lectures de `Settings` dans `IlotControleur`).

### Interfaces anciennes toujours en service

Rien n'est mort, mais quatre familles de fenêtres vivent à côté de l'îlot :
- `EnclochePanneau` et `EncocheVue` : l'encoche de dictée (`DictationController.swift:52`) ;
- `ReunionPanneau` (`ReunionEncoche.swift`, créé à `ReunionController.swift:19`) ;
- `PanneauCompact` (`AppDelegate.swift:19`) ;
- `FiletPanneau` (`AppDelegate.swift:20`).

`ReunionEncoche.swift` héberge en plus des pièces partagées : `ActionRuban`, `VueHebergeeSurvol`, `CurseurEnArrierePlan` (cadre privé CGS). Tout ramener dans l'îlot est **une décision de produit**, pas un nettoyage.

### Noms de fichiers en double

`CentreIlot.swift` et `NettoyageParUnites.swift` existent dans `DicteeCore` **et** dans `Dictee`. Ça marche, mais ça prête à confusion dans les recherches et les messages d'erreur.

---

## 2. Duplication et quasi-doublons

| Doublon | Occurrences | Gain estimé |
|---|---|---|
| Magasins JSON (`lire`, `ecrire`, `urlParDefaut`, `.abime`, 0600) | `RappelsStore` (`IlotControleur:10-28`), `EtagereStore` (`IlotEtagere:19-37`), `NotesStore` (`OutilsControleur:110-129`) ; en plus, 13 chemins « Library/Application Support/Dictee » écrits en dur | environ 40 l. |
| Boutons pilule | `CapIlot` (`IlotPieces:128-173`), `PiluleOutil` (`IlotOutils:47-97`), `PiluleCentre` (`CentreIlot:499-531`) | 60 à 80 l. |
| Listes qui défilent (décalage, borne, fondu) | Claude (`IlotCarteClaude:77`, `:174-185`), Notes (`IlotOutils:677`, `:770-782`), Dictées (`DicteesIlot:120-125`, `:347`) ; bornes côté moteur à `:1028` et `:1073` | 50 à 70 l. |
| Absorbeur de clics `Color.clear.contentShape(…).onTapGesture {}` | 13 fois (`CentreIlot:204/297/547`, `DicteesIlot:236`, `IlotCarteClaude:109/131/249`, `IlotOutils:147/174/595/735/764/796`) | un modificateur |
| Survol | 24 `@State survol` et 3 façons de le tenir (`@State` local, moteur `survolCopie`/`survolNote`, `dictees.survol`) | convention |
| Cycle de vie des sources `demarrer`/`arreter`/`actif` | 7 classes (Claude, Énergie, Appareils, Téléchargements, Notifications, micro, niveaux) | un protocole ; simplifie `IlotControleur:241-303` |
| Patron de travail des surveillances (file série, drapeau `arrete`, jeton `self.travail === t`) | `IlotClaude:~129`, `IlotTelechargements:45-51` | 20 à 30 l. Les mécanismes (FSEvents, DispatchSource) restent différents, et c'est voulu. |
| Ouverture du micro (`EntreeHAL` ou `AVAudioEngine`, `VerbeEssayer`, observateur de configuration) | `AudioCapture.construireMoteur` et `MicroReunion.lancer` | environ 50 l. |
| Conversion en 16 kHz mono 16 bits | `RecordingPipeline.convertir:95-116` ≡ `PisteReunion.convertir:129-147` | environ 25 l. |
| Touche « avalée, puis avaler aussi son relâchement » | `reunionAvalee`, `echapAvale`, routeur des niveaux (`KeyMonitor:25`, `:35`, `:145-157`) | environ 15 l. |
| Réglages | 38 couples get/set ; `ReglagesModele` recopie chaque réglage 3 fois (`didSet`, init `reel ? … : exemple`, notification) | environ 140 l. |
| Nombres magiques | 149 `.white.opacity(` (0,5 ×17), 199 `.font(.system(size:`, 43 `RoundedRectangle(cornerRadius:`, 20 `Color(hex:)` hors `CouleursIlot` (0x5EB0FF ×9, 0x5FE08A ×6, 0xFFB340 ×5), environ 10 constantes de ressort différentes | jetons |
| Verrous faits main | 24 `NSLock`, plus `Verrouille<T>` (`Transcrire.swift:135`), `Premiere`, `Duel` | `Mutex` (Synchronization, macOS 15+) |

**Déjà bien factorisé :**
- `ContenuAnnonce` : un même contenu sert au dessin et à la mesure.
- Le dossier des captures réutilise `SurveillanceDossier`.
- Les touches de volume et de luminosité sont décodées dans le cœur.

Au total, on peut retirer **environ 450 à 550 lignes** par factorisation pure. Le vrai gain est ailleurs : la cohérence visuelle et le nombre d'endroits à toucher pour chaque changement.

---

## 3. Code mort et restes

Il y a peu de vrai code mort. Il a été vérifié par grep, en comptant les références hors du fichier qui le définit.

| Élément | État |
|---|---|
| `TracesDeSon` (`ReunionEncoche.swift:199`) | 0 référence : à supprimer |
| `GeoIlot.demiLargeur` (`DicteeCore/Ilot.swift:479`) | 0 référence |
| `NavigationBasse`, `LienNavigation`, `AideTouches` (`PanneauCompact.swift:11/33/57`), `BarresDeSon`, `TexteEnDirect` (`EncocheVue.swift:242/277`), `BoutonFilet` (`FiletVue.swift:148`) | 0 référence externe. Vérifier l'usage dans leur propre fichier avant de supprimer. |
| `TraceSonore` (`LectureEnCours.swift:142`), `ArbitrageIlot.etage`, `ModeleWhisper.defautSelonMesures` (:38), `BudgetJetons.restantPourReunion` (:37), `ChoixMotsPrompt.classer` (:47) | Utilisés seulement par les contrôles |
| « goutte » | Ne reste que dans des commentaires (`IlotMoteur:677/698`) et un nom de rendu (`RenduLecture:235/239`) |
| `microEtendu` | **Vivant** (`Ilot.swift:20`, `IlotAnnonces.swift:178`) |
| `ReunionEncoche`, `PanneauCompact`, `EncocheVue`, `EnclochePanneau`, `Filet*` | **Vivants** (voir § 1) |
| `--lecture-essai` cité dans `tasks/todo.md:100` | N'existe plus : c'est `--lecture-test` |
| Doc décalée | `Settings.swift:147-148` : le commentaire du secours est posé au-dessus de `sons` ; `secoursApple` (:162) n'a pas de doc |

**Réglages sans interface.** Ils sont lus en production, mais ne se changent qu'avec `defaults write` ou une variable `DICTEE_*`. Ce sont :
- `filetDeSecurite`, `envoiFLAC`, `rognageFin`, `envoiAnticipe`, `requeteDeSecours`, `decoupeLongue` ;
- `nettoyageParUnites`, `lexiquePourWhisper`, `correctionALOreille`, `apprentissageDesCorrections` ;
- `relecture`, `expressionsPourWhisper`, `modeleNettoyage`, `modeleRelecture`, `modeleNoteReunion` ;
- `delaiRelecture`, `limiteHistorique`, `languesAutorisees`.

Ces interrupteurs ont été utiles pendant les bancs d'essai. Aujourd'hui, ce sont des branches jamais exercées en sens inverse. Il faut décider lesquels garder, puis supprimer la branche « éteint » des autres. 21 variables d'environnement `DICTEE_*` sont lues en production, dont `DICTEE_RETARD_PREMIERE_REQUETE_MS` (`GroqClient.swift:140`), qui injecte un délai.

**Crochets d'essai dans les types de production :**
- `VueSourceFichiers.essai` (`IlotEtagere.swift:401`, dans le vrai chemin du glisser à :449) ;
- `CadenceEcran.minuterieSeulement` (`IlotMoteur:1374`) ;
- `Settings.modeleForce` et `Settings.delaiRelectureForce` (`Settings.swift:44/46`) ;
- `CleGroq.utiliserTrousseau` (:11).

---

## 4. Justesse et robustesse

### Concurrence

1. **Bug du secours (constat n° 1).** `DictationController.swift:261-263`. Correction : utiliser `Premiere` (déjà dans `Premiere.swift`), ou donner à `ReconnaissanceDirecte.terminer()` son propre délai. À vérifier avec une reconnaissance factice qui ne rend jamais la main.
2. **Mode Swift 5 (constat n° 2).** Les 5 avertissements de concurrence de la compilation :
   - `IlotEtagere.swift:582` et `IlotVues.swift:568` : propriétés MainActor lues dans des fermetures `Sendable` ;
   - `IlotPieces.swift:391` : `fondu` appelé hors MainActor ;
   - `IlotNotifications.swift:69` : `self` capturé dans `Task.detached` ;
   - `Nettoyer.swift:8` : fonction locale non `@Sendable`.
3. **FSEvents sans retenue.** `IlotClaude.swift:184` passe `passUnretained` avec `retain: nil, release: nil`. `SourceClaude.arreter()` (:133-136) lâche la dernière référence et l'arrêt du flux se fait plus tard, en `file.async` (:164-169). Un rappel déjà en file derrière l'arrêt peut alors lire un objet libéré. La fenêtre est minuscule et le cas n'a pas été reproduit. Correction : passer des fonctions `retain`/`release` dans le contexte.
4. **`KeyMonitor`.**
   - `arreter()` n'appelle pas `CFMachPortInvalidate`, et le type n'a pas de `deinit` : un pointeur pendouillerait si l'objet était libéré.
   - Aujourd'hui, l'objet vit autant que l'app (`AppDelegate:17`).
   - `Log.ecrire` est appelé dans le rappel du tap, sur `keyDown` (:141).
   - Chaque frappe du Mac passe par `MainActor.assumeIsolated` (:65). Si le fil principal se fige, macOS coupe le tap (`tapDisabledByTimeout`, rattrapé à :109) et la frappe est ralentie partout.
5. **`EntreeHAL`** (`EntreeHAL.swift:85-89`). Sur le fil temps réel, le code alloue un `AVAudioPCMBuffer` et appelle `DispatchQueue.async` à chaque tampon. C'est interdit en temps réel, avec un risque de craquements sous charge. `surTampon` est écrit dans `demarrer` sans passer par la file `livraison` (course bénigne). Correction : une réserve de tampons préparée à l'avance, ou une file circulaire sans verrou.
6. **Pointeurs non retenus « vivants tant que l'app vit ».** `IlotEnergie.swift:20`, `IlotNotifications.swift:42`. C'est correct aujourd'hui, mais fragile. L'observateur AX des notifications ne suit pas le redémarrage du Centre de notifications : son `pid` peut devenir périmé.

### Énergie au repos

| Source | Quand | Verdict |
|---|---|---|
| Boucle d'animation `CADisplayLink` (60/120 Hz) | Seulement pendant qu'un ressort bouge ; s'arrête quand tout est posé (`IlotMoteur:1228-1250`) | Bon. La `Timer` à 60 Hz (:1382) ne sert qu'à l'essai. Le coût réel est la réévaluation de tout l'arbre par `rev`. |
| `Timer` toutes les 2 s des autorisations (`AppDelegate:140`) | Tant qu'une autorisation manque | Acceptable |
| `Timer` toutes les 2 s de la bande de mise à jour (`MiseAJourControleur:215`) | **Tant qu'une version attend**, ce qui peut durer des jours | À remplacer par des événements (fin de dictée ou de réunion), ou au moins espacer et ajouter `tolerance` |
| `Timer.publish` toutes les 1 s et 5 s (`ReglagesVue:33`, `FenetreVue:50`) | Fenêtre ouverte | Acceptable |
| Moniteur global de la souris (`IlotPanneau:430`) | **Tant que l'étagère est allumée** : reçoit chaque clic et chaque glisser du système | À mesurer. Coût par événement limité (0,05 s, `changeCount`) |
| `TimelineView` toutes les 1 s, 0,25 s et 15 s | Contenu à l'écran | Bon |

Aucune `Timer` n'a de `tolerance`. Il n'y a aucun vrai sondage au repos quand tout est accordé : c'est un bon résultat.

### Retours forcés et gestion des erreurs

- Les `!` sont presque tous sur des constantes sûres : URL littérales, `AVAudioFormat` 16 kHz, `CGEventType(rawValue: 14)!`.
- Les `as! AXUIElement` (`OutilsControleur:445/457`, `SurveillanceCorrections:16/47`, `LecteurInsertion:31/73`, `Curseur:62/76`) sont justes en pratique, car Core Foundation rend toujours ce type. Les rassembler dans un petit utilitaire AX éviterait 8 copies.
- `try?` est utilisé partout pour l'écriture des fichiers, souvent sans trace au journal : `EtagereStore`, `NotesStore`, `RappelsStore`. Une écriture ratée est donc silencieuse.

### API privées et leurs replis

| API | Où | Repli |
|---|---|---|
| DisplayServices (luminosité, `dlopen`) | `IlotNiveaux.swift:211` | Trace au journal ; les touches restent à macOS |
| CGS `SetsCursorInBackground` | `ReunionEncoche.swift:249` | Trace ; curseur de l'app de dessous |
| MultitouchSupport (vibration du trackpad) | `ActionneurTrackpad.swift:45` | Pas de vibration |
| IOBluetooth KVC `batteryPercent*` | `IlotEnergie.swift:139` | Vérifié par `responds(to:)` |
| Core Audio process tap | `SonSysteme.swift` | Réunion avec le micro seul |

Tous ont un repli et une trace au journal, ce qui est exemplaire. Ils peuvent casser à chaque mise à jour de macOS. Il faudrait les rassembler dans un dossier `Systeme/Prive/` pour savoir quoi tester après chaque mise à jour.

### Avertissements de compilation (28 distincts)

- 15 sont `Text + Text`, déprécié dans macOS 26 : `DicteesFenetre:96/97/148`, `IlotAnnonces:61`, `IlotCarteClaude:220`, `IlotOutils:179`, `JourneeVue:181`, `MotsVue:81`, `ReunionsFenetre:261`…
- 5 concernent la concurrence (voir plus haut).
- 1 est `var copie` (`DicteeCore/MiseAJour.swift:194`).
- 1 est un transtypage inutile (`ChampRecherche.swift:34`).

---

## 5. Confidentialité et sécurité

| Sujet | Constat | Avis |
|---|---|---|
| Clé Groq | Trousseau (`kSecAttrAccessibleWhenUnlocked`), repli sur `~/.config/groq/.env` ; jamais au journal | Bon |
| Journal `~/Library/Logs/Dictee/dictee.log` | 30 caractères du texte dicté au plus (`Log.apercu`), plus une ligne de comparaison de 60 caractères ; rotation à 1 Mo ; créé avec les droits par défaut (0644, dans un `~/Library` en 0700) | Correct. Le passer en 0600 ne coûte rien. |
| Données dans `Application Support/Dictee` | historique, réunions (dossier 0700, fichiers 0600), étagère, notes, rappels, lexique, expressions, test de précision, `claude/` | Écrits en `.atomic` **puis** passés en 0600 : entre les deux, le fichier existe brièvement en 0644. Créer directement en 0600. `claude/` est créé sans 0700. |
| Crochet Claude Code | Verbe réécrit `~/.claude/settings.json` (copie de sauvegarde, écriture atomique, droits conservés) et installe `claude-crochet.sh` (0755). Le script garde **le contenu complet** des outils de tâches (`TodoWrite`…) et 300 caractères des notifications. | Prudent. Documenter dans l'app ce qui est gardé et purger régulièrement (`effacerLesVieux` existe). |
| Notifications des autres apps | Lues par Accessibilité, montrées 4 s, jamais gardées, jamais au journal | Bon |
| Réseau | Groq (transcription, remise au propre, note de réunion, reformulation), GitHub Releases (mise à jour, `GardeRedirections`), miniatures de lecture (`MiniatureLecture`, session éphémère) | Bon. Les sessions éphémères sont un bon choix. |
| AppleScript (Notes) | HTML échappé, puis `\` et `"` protégés (`OutilsControleur:473-475`) | Correct |
| Outils de dev livrés | `ConstruireLexique` parcourt le dossier personnel ; `--installer-mise-a-jour-test` ; injection de délai par variable d'environnement | Surface inutile dans l'app livrée (voir le plan, étape 6) |

---

## 6. Tests

| Suite | Couverture | Durée | Fiabilité |
|---|---|---|---|
| `swift run DicteeControles` | `DicteeCore` : 63 groupes, 2 398 contrôles, **tous passent** | 3,6 s | Déterministe (fuseau et locale fixés, dossiers temporaires, sans réseau). **Sauf** `main.swift:995-1002` : `ms < 150` et `ms2 < 400` mesurés sur un build debug, qui peuvent échouer sous charge (par exemple pendant les builds parallèles). |
| `Verbe --ilot-essai` | L'îlot réel : vraie `NSPanel`, vrais ressorts, faux sons, Groq, AirDrop, Finder et écran. Environ 670 vérifications. | **Environ 5 min** : 328 `attendre(…)`, environ 303 s d'attente fixe, dont 250 s dans `IlotEssai.swift` | Demande une session graphique et dépend de l'écran (encoche ou non) et de l'horloge réelle (délais de survol de 0,28 s et 0,45 s). Peut échouer sous charge. |
| Couche app | `DictationController`, `GroqClient`, `AudioCapture`, `Settings`, `ReglagesModele`, `AppDelegate` | — | **Aucun test automatique** |

**Trous dans le cœur :** `MotsDuQuotidien` n'a aucun test direct. `BudgetJetons`, `BudgetAudio`, `WAV`, `SuiviLatence` et la partie presse-papiers d'`OutilsIlot` ne sont touchés que par 1 à 4 contrôles.

**Le plus rentable :**
1. remplacer les attentes fixes de l'essai par `attendre(tant:)` (sortie dès que la condition est vraie) ;
2. sortir dans le cœur la logique listée au § 1, avec des tests ;
3. ajouter un test du secours qui ne rend jamais la main (constat n° 1).

---

## 7. Plan de refactorisation

**Conditions préalables.**
- Le plan commence **après la fusion de toutes les branches en cours** (`bibliotheque`, `correctif-captures`, `claude-outils`, `etagere-rapide`, `reunions-wispr`, `correctif-clics`).
- Une seule personne refactorise à la fois, et aucun chantier de fonction ne tourne en parallèle sur les fichiers de l'îlot.
- Chaque étape fait un commit, et le comportement reste identique, sauf l'étape 1, qui corrige un bug et se fait dans un commit séparé.

**Vérification commune à chaque étape (« le filet »).**
1. `swift build` sans nouvel avertissement.
2. `swift run DicteeControles` : 2 398/2 398 ou plus.
3. `Verbe --ilot-essai` : toutes les vérifications passent.
4. Rendus `--rendu-ilot` et `--rendu-lecture` comparés pixel à pixel avec la référence prise à l'étape 0.
5. Pour l'audio : une vraie dictée avec et sans AirPods, et `--transcrire` sur un WAV de référence.

**Tailles.** S : moins de 150 lignes touchées, moins d'une heure. M : 150 à 600 lignes. L : plus de 600 lignes ou plusieurs sessions.

### Gains rapides

| # | Étape | Fichiers | Risque | Vérification | Taille |
|---|---|---|---|---|---|
| 0 | **Point de départ.** Étiquette `avant-refactor`, liste des avertissements, rendus de référence dans un dossier hors git, chronométrage de l'essai | — | nul | — | S |
| 1 | **Corriger le délai du secours** (bug) avec `Premiere`. Ajouter une reconnaissance factice qui ne rend jamais la main. | `DictationController.swift:256-282` | faible | La dictée rend la main en 1,5 s, plus le filet | S |
| 2 | **Zéro avertissement.** `Text` par interpolation (15), `let copie`, transtypage inutile, les 5 avertissements de concurrence | 12 fichiers listés au § 4 | faible | Build sans avertissement, plus les rendus | S |
| 3 | **Supprimer le vrai code mort** : `TracesDeSon`, `GeoIlot.demiLargeur`, les 6 vues sans référence (après vérification dans leur propre fichier), les fonctions du cœur utilisées seulement par les tests (ou les marquer). Corriger `todo.md:100` et la doc de `Settings:147`. | § 3 | faible | Filet | S |
| 4 | **Durées de vie sûres** : `retain`/`release` dans le contexte FSEvents, `CFMachPortInvalidate` et `deinit` dans `KeyMonitor`, sortir `Log.ecrire` du rappel du tap, `tolerance` sur les `Timer` | `IlotClaude.swift`, `KeyMonitor.swift`, `MiseAJourControleur.swift`, `AppDelegate.swift` | faible | Filet, plus brancher et débrancher Claude 20 fois en écrivant des événements | S |
| 5 | **Un seul dossier, un seul magasin.** `DossierVerbe.url(_:)` remplace les 13 chemins écrits en dur. `MagasinJSON<T>` (lecture, `.abime`, écriture atomique **créée directement en 0600**, trace des échecs) remplace `RappelsStore`, `EtagereStore` et `NotesStore`. Le journal passe en 0600. | `IlotControleur.swift:10-28`, `IlotEtagere.swift:19-37`, `OutilsControleur.swift:110-129`, `Log.swift`, plus les autres stores | faible | Filet, plus contrôles du cœur sur un dossier temporaire | S-M |

### Structure

| # | Étape | Fichiers | Risque | Vérification | Taille |
|---|---|---|---|---|---|
| 6 | **Sortir l'outillage de l'app.** Cible bibliothèque `VerbeApp` (le code actuel de `Dictee`), exécutable `Dictee`, réduit à `main` et `AppDelegate`, exécutable `VerbeOutils` (26 modes `--`, `Rendu*`, `IlotEssai*`, bancs). `build.sh:55` appelle `VerbeOutils --rendu-icones`. Les crochets d'essai deviennent des injections dans les initialiseurs. | `Package.swift`, `main.swift`, `build.sh`, environ 25 fichiers déplacés | moyen (visibilité `internal` vers `public`/`package`) | Filet, plus taille du binaire avant et après, plus `release.sh` à blanc | M |
| 7 | **Découper les gros fichiers, sans toucher à la logique** (`git mv` et extensions uniquement) : `IlotMoteur` en `IlotTypes`, `IlotGeometrie`, `IlotAnimation`, `IlotMoteur+Etagere`, `IlotMoteur+Cartes` ; les extensions du contrôleur sortent de `CentreIlot.swift:919` et `IlotEtagere.swift:87` ; `IlotEtagere` en 3 fichiers ; `IlotOutils` en un fichier par outil ; `IlotCalques` en un fichier par famille d'écran ; `IlotPanneau` sépare son glisser. Renommer les doublons `CentreIlot.swift` et `NettoyageParUnites.swift` de l'app. | Les 7 gros fichiers | faible (mécanique) | Filet ; le `git diff` ne doit montrer que des déplacements (`--color-moved`) | M |
| 8 | **Logique pure vers `DicteeCore`, avec contrôles** : `CourbesIlot`, `aspect`, familles, bornes et routage du défilement, table `largeurPastille`, lecteur de lignes Claude, `estUnRefus` | voir § 1 | faible | Nouveaux contrôles, plus le filet | M |
| 9 | **Jetons et composants** : `CouleursIlot` complété, `RayonsIlot`, `PolicesIlot`, `RessortsIlot` ; `BoutonPilule` unique ; `ListeDefilante` (décalage, borne, fondu) ; modificateur `.absorberLesClics()` ; une seule convention de survol | `IlotPieces`, `IlotOutils`, `CentreIlot`, `IlotCarteClaude`, `DicteesIlot`, `IlotVues` | moyen (rendus) | Rendus comparés pixel à pixel | M |
| 10 | **Audio partagé** : `OuvertureMicro` (décision, `EntreeHAL` ou moteur, garde-fou, observateur) utilisé par `AudioCapture` et `MicroReunion` ; `Convertisseur16k` utilisé par `RecordingPipeline` et `PisteReunion` ; tampons préparés à l'avance dans `EntreeHAL` | 5 fichiers audio | **élevé** | `--transcrire` sur un WAV de référence (sortie identique), plus des essais à la main : AirPods mis et retirés pendant une dictée, dictée pendant une réunion | M |
| 11 | **Réglages typés** : `@Reglage("cle", defaut:)`, un enum de clés, un helper de liaison dans `ReglagesModele`. Décider quels réglages de développeur garder, et supprimer les branches mortes des autres. | `Settings.swift`, `ReglagesModele.swift` | moyen | Lecture des `defaults` existants inchangée (contrôle sur une suite `UserDefaults` à part) | M |
| 12 | **Un état par fonction** : sous-modèles `@Observable` (Claude, Étagère, Outils, Niveaux) au lieu du seul `rev` ; `ActionIlot` en enums imbriqués, chaque sous-contrôleur ayant son propre `switch` (Minuteur, Rappels, Agenda, Centre, Étagère, Outils) ; supprimer l'état `etagere` en double | `IlotMoteur`, `IlotControleur`, vues | **élevé** | Filet, plus Instruments (processeur pendant une ouverture et une fermeture : on attend nettement moins d'évaluations de `body`) | L |
| 13 | **Swift 6, fichier par fichier** : `Mutex` à la place de `NSLock` et `Verrouille`, puis retrait des `@unchecked Sendable` qui deviennent inutiles, puis bascule de la cible en `.v6` | Tout `Dictee` | moyen | Filet, plus Thread Sanitizer sur `--transcrire` et sur l'essai | L |
| 14 | **Dépôt** : `design/rendus-*` hors de git (`.gitignore`, rendus en pièces de version ou régénérés à la demande). Réécrire l'historique (166 Mo) est **une décision de Hugues** (dépôt public, clones existants). | `design/`, `.gitignore` | faible | `du -sh .git` | S |
| 15 | **Essai plus rapide et plus stable** : `attendre(tant:)` partout où c'est possible, et rendre l'horloge injectable dans `IlotMoteur` | `IlotEssai*.swift` | faible | Durée de l'essai (objectif : moins de 90 s), 5 passages de suite | M |
| — | **Décision de produit, pas une refactorisation :** fondre l'encoche de dictée, l'encoche de réunion, le panneau compact et le filet dans l'îlot | — | — | — | — |

---

## 8. Conventions à adopter

1. **Un fichier = une responsabilité, et moins de 500 lignes.** Une extension d'un contrôleur ne va jamais dans un fichier de vues.
2. **Le moteur ne connaît pas les fonctions.** Chaque fonction (Claude, Étagère, Outils…) a son sous-état et son sous-contrôleur. `ActionIlot` se ramifie par fonction.
3. **Toute logique sans AppKit va dans `DicteeCore`, avec un contrôle.** Une règle qui se teste sans écran n'a rien à faire dans l'app.
4. **Pas de nombre magique dans les vues** : couleurs, rayons, polices et ressorts passent par les jetons de l'îlot.
5. **Un composant partagé avant le 2e copier-coller** : pilule, liste qui défile, absorbeur de clics, carte.
6. **Fichiers de l'utilisateur** : toujours via `DossierVerbe` et `MagasinJSON`, créés en 0600 et dossiers en 0700, échec tracé au journal (sans contenu).
7. **Concurrence** : pas de nouveau `@unchecked Sendable` ni `nonisolated(unsafe)` sans un commentaire qui prouve la sûreté ; `Mutex` plutôt que `NSLock` ; une course « premier arrivé » passe toujours par `Premiere`, jamais par `withTaskGroup` sur une tâche à part ; contexte C = `retain`/`release`, ou durée de vie écrite noir sur blanc.
8. **Rappels temps réel et tap clavier** : aucune allocation, aucun journal, aucun travail lourd ; on copie et on renvoie ailleurs.
9. **Aucun crochet d'essai dans les types de production** : on injecte par l'initialiseur ; l'outillage vit dans `VerbeOutils`.
10. **Réglages** : un `@Reglage` avec sa clé dans l'enum ; un interrupteur de développeur a une date d'expiration dans son commentaire.
11. **Zéro avertissement** : un build qui avertit n'est pas fini.
12. **Rendus** : générés hors git ; seules les maquettes validées sont commitées.
