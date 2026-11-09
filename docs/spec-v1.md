# Spécification technique V1 (lots 1 à 5)

Objectif de la V1 : Hugues tient **fn**, l'encoche s'ouvre, il parle, il relâche, et le texte s'écrit **à l'endroit du curseur, dans n'importe quelle app**. Priorités dans l'ordre : vitesse, fiabilité, légèreté, simplicité.

## Machine et outils
- MacBook Air M5, macOS 26.6, 16 Go de mémoire, mode sombre.
- Swift 6.2 via les outils en ligne de commande. **Pas d'Xcode** : on construit un paquet Swift (`Package.swift`), puis un script assemble l'app.
- Aucune dépendance externe sauf nécessité absolue, et justifiée dans ce cas.
- Clé Groq : `~/.config/groq/.env` (une ligne `GROQ_API_KEY=...`). Elle ne doit jamais apparaître dans le dépôt, dans les journaux ou dans une sortie.

## Fabrication
- `build.sh` :
  1. `swift build -c release` ;
  2. assemble `Dictee.app` (`Contents/MacOS`, `Contents/Info.plist`, `Contents/Resources`) ;
  3. signe l'app ;
  4. l'installe dans `~/Applications/Dictee.app`.
- `Info.plist` :
  - `LSUIElement = true` (pas d'icône dans le Dock) ;
  - `CFBundleIdentifier = com.hugues.dictee` ;
  - `NSMicrophoneUsageDescription` et `NSSpeechRecognitionUsageDescription`, rédigés en français simple ;
  - `LSMinimumSystemVersion = 26.0`.
- **Signature stable.** Sans elle, macOS redemande les autorisations à chaque reconstruction :
  - créer **une fois** un certificat auto-signé « Dictee Dev », de type signature de code, dans le trousseau de session (openssl, puis `security import`), et signer avec ;
  - si c'est impossible sans fenêtre, se replier sur la signature ad hoc et le noter dans le journal du projet.

## Lot 1 : squelette
- L'app démarre sans fenêtre, avec temporairement une petite icône dans la barre des menus. Son menu contient : « Autorisations… », « Ouvrir le journal » et « Quitter ». Cette icône disparaîtra au lot 7, quand le panneau sortira de l'encoche.
- Au lancement, elle vérifie les autorisations et ouvre directement le bon volet des Réglages Système pour ce qui manque :
  - **micro** (`AVCaptureDevice`) ;
  - **accessibilité** (`AXIsProcessTrustedWithOptions`), nécessaire pour coller ;
  - **surveillance de l'entrée** (`CGPreflightListenEventAccess` / `CGRequestListenEventAccess`), nécessaire pour la touche fn.
- Journal horodaté dans `~/Library/Logs/Dictee/dictee.log`. Pour chaque dictée, on y note les durées : appui, relâchement, réponse Groq, collage. **Jamais le texte dicté en entier**, au plus ses 30 premiers caractères.

## Lot 2 : touche fn
- Écoute globale avec un `CGEventTap` sur `flagsChanged`, en testant `maskSecondaryFn`. L'écoute porte sur toutes les apps.
- **Fn tenue** : la dictée commence. **Fn relâchée** : la dictée finit.
  - Si fn est tenue moins de 0,25 s sans parler, c'est un appui court, ignoré.
  - Si une autre touche est pressée pendant que fn est tenue (fn+F1, fn+flèche…), la dictée est annulée en silence : c'est un raccourci du clavier, pas une dictée.
- **Deux appuis courts en moins de 0,35 s** : mode mains libres. La dictée continue sans tenir la touche. On l'arrête par un nouvel appui sur fn ou par ✓, et on l'annule avec Échap ou ✕.
- **Échap** pendant une dictée : on annule et rien n'est collé.
- **Conflit connu :**
  - sur ce Mac, `AppleFnUsageType = 2`, donc la touche 🌐/fn ouvre les emoji ;
  - **Wispr Flow** utilise aussi fn.

  Il faut soit que le tap actif avale l'appui fn pour que les emoji ne s'ouvrent pas, soit l'expliquer clairement dans le menu « Autorisations… ». Il faudra demander à Hugues de mettre « Appuyer sur 🌐 : Ne rien faire » et de couper le raccourci de Wispr pendant les essais.

## Lot 3 : son et transcription
- Capture avec `AVAudioEngine`, convertie en **16 kHz, mono, 16 bits**. Le moteur est préparé dès le lancement pour démarrer instantanément.
- **Envoi par morceaux pendant qu'il parle.** Une détection de voix simple (niveau sonore plus durée) coupe aux pauses de plus de 0,5 s. Chaque morceau part tout de suite à Groq, en parallèle. Au relâchement, on n'envoie que le dernier morceau. Les textes sont recollés **dans l'ordre**.
- **Appel Groq** :
  - adresse : `POST https://api.groq.com/openai/v1/audio/transcriptions` ;
  - paramètres : `model=whisper-large-v3-turbo`, `response_format=json`, `temperature=0` ;
  - `prompt` : les mots du dictionnaire (au lot 3, une liste dans `~/Library/Application Support/Dictee/mots.txt`, préremplie avec Ladislas, Sillonia, Ecodistrib, Abidjan, Premium CI, Wispr, Groq), suivis de la fin du morceau précédent pour garder la continuité ;
  - langue détectée automatiquement, ou `fr` si un réglage le force.

  Le fichier son est un WAV construit en mémoire. La connexion est réutilisée (une seule `URLSession`), et une requête légère la « préchauffe » dès l'appui sur fn.
- **Secours.** Si Groq échoue ou ne répond pas dans les 4 secondes, on utilise le texte de la dictée d'Apple, faite sur l'appareil (voir le lot 5), et on le note dans le journal.
- **Mode test en ligne de commande :** `Dictee --transcrire fichier.wav` affiche le texte et la durée. Il sert à vérifier sans micro.

## Lot 4 : collage au curseur
- On lit l'app au premier plan (`NSWorkspace.frontmostApplication`) au **début** de la dictée, et on recolle dans cette app.
- Le collage :
  1. sauvegarder **tous** les éléments du presse-papiers ;
  2. écrire le texte, avec le type `org.nspasteboard.ConcealedType` pour que les gestionnaires de presse-papiers ne l'enregistrent pas ;
  3. simuler ⌘V avec `CGEvent` (touche 9 plus `maskCommand`) ;
  4. remettre l'ancien presse-papiers environ 0,6 s plus tard, sauf s'il a changé entre-temps.
- **Terminaux** (`com.apple.Terminal`, `com.googlecode.iterm2`, `dev.warp.Warp-Stable`, `com.mitchellh.ghostty`, `net.kovidgoyal.kitty`, `co.zeit.hyper`, `com.microsoft.VSCode` quand le focus est dans son terminal si c'est détectable, sinon tout VS Code) : on retire tout retour à la ligne final et on remplace les retours internes par des espaces. **Jamais d'Entrée envoyé.**
- **Champ protégé** (`IsSecureEventInputEnabled()`) : on ne colle pas. Le texte reste dans le presse-papiers, et l'encoche affiche brièvement « Champ protégé, texte copié ».
- Mise en forme minimale au lot 4 : espaces en trop retirés. Si la dictée est courte et que l'app est un navigateur, on retire le point final d'une requête courte (moins de 8 mots). Le reste de la mise en forme viendra au lot 6.

## Lot 5 : l'encoche v5 en vrai
- Modèle : `design/maquettes/encoche-v5.html` (regarde-le en rendu). Les mesures sont à adapter à l'écran réel.
- **La fenêtre** :
  - `NSPanel` sans bord, `.nonactivatingPanel`, fond transparent, niveau au-dessus de la barre des menus (`.statusBar` + 1, ou `.screenSaver` si besoin) ;
  - `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]` ;
  - elle ne prend jamais le focus et laisse passer les clics, sauf sur ✕/✓ en mains libres.
- **Position** : centrée sur l'encoche de l'écran principal, calculée avec `NSScreen.auxiliaryTopLeftArea`, `auxiliaryTopRightArea` et `safeAreaInsets`. Sans encoche (écran externe), elle se colle en haut au centre.
- **Le contenu**, en SwiftUI :
  - **Bande noire**, de la hauteur de la barre des menus : l'**icône de l'app cible** à gauche (`NSRunningApplication.icon`) et **5 barres de son** vivantes à droite, alimentées par le niveau du micro ;
  - **Ruban soudé dessous** : le **texte en direct** sur une ligne. Les anciens mots s'effacent en fondu à gauche, les deux derniers restent gris tant qu'ils ne sont pas sûrs.
  - **Rien d'affiché au centre** : c'est la caméra.
  - En mains libres, **✕** et **✓** aux deux extrémités.
- **Texte en direct** : reconnaissance d'Apple **sur l'appareil**, en flux. On utilise `SpeechAnalyzer`/`SpeechTranscriber` de macOS 26 s'il est disponible, sinon `SFSpeechRecognizer` avec `requiresOnDeviceRecognition = true`, langue fr-FR. Ce texte sert seulement à l'affichage et au secours. Le texte collé est celui de Groq.
- **Mouvements** : ressorts sobres (ouverture depuis l'encoche, fermeture plus vive), en respectant « Réduire les animations ».
- **Pendant la finalisation** (environ 0,4 s), le texte du ruban se fixe en blanc. Ensuite l'encoche se referme et le texte arrive au curseur.

## Vérification par lot
- `swift build` doit passer sans avertissement grave. On teste la logique pure, sans interface : assemblage des morceaux, nettoyage pour les terminaux, encodage WAV, détection du double appui. Les tests passent par un exécutable de contrôle (`swift run DicteeControles`) ou par `swift test` s'il est disponible.
- Le mode `--transcrire` est vérifié sur un WAV généré avec `say` puis `afconvert`.
- L'app est lancée pour de vrai : on vérifie qu'elle ne plante pas et que le journal s'écrit.
- **Interdit d'ouvrir des fenêtres sur l'écran de Hugues sans le prévenir.**
- Les essais qui demandent sa voix ou ses autorisations sont **listés pour lui**, en mots simples, à la fin.
- Commit et push sur `main` (dépôt privé `proladislas-rgb/dictee-mac`) à la fin de chaque lot, avec un message en français.

## Lot 6 : remise au propre et mise en forme selon l'app
- **Appel** : `POST https://api.groq.com/openai/v1/chat/completions`, modèle `openai/gpt-oss-20b` (nom vérifié avec `GET /openai/v1/models` le 09/11 ; réglable par `defaults write com.hugues.dictee modeleNettoyage ...`), température 0,1, `reasoning_effort=low`, sortie = le texte seul. Même `URLSession` que Whisper (connexion déjà chaude).
- **Consignes** (en français, dans `RemiseAuPropre.consignes`) : retirer hésitations et bégaiements, appliquer les corrections dites, ponctuer sans reformuler ni ajouter, garder la langue parlée, garder l'orthographe du dictionnaire, commandes dites (« à la ligne », « nouveau paragraphe », « point », « virgule »…), listes quand il énumère, et surtout **ne jamais répondre** à ce qui est dicté (3 exemples dans la consigne, dont une question).
- **Forme selon l'endroit** (`RemiseAuPropre.contexte`) : terminal = une ligne brute sans point final ; navigateur + rôle d'Accessibilité `AXTextField`/`AXSearchField`/`AXComboBox` = requête courte sans point final ; Mail/Outlook = paragraphes soignés ; Messages/WhatsApp/Slack/Discord/Telegram = ton direct ; Notes/Pages/Word/Obsidian/Notion/TextEdit = paragraphes et listes à puces ; Claude/ChatGPT/Codex = texte fidèle, structuré si long ; sinon phrases propres. Dans un navigateur, le titre de la fenêtre reconnaît Gmail, Google Docs, WhatsApp Web, Slack, ChatGPT, Claude…
- **Quand l'utiliser** : plus de 6 mots, ou hésitation (euh, heu, hum, « E » isolé, mot répété), ou correction dite (« non plutôt »…), ou commande de mise en forme. Sinon le texte de Groq est collé tel quel (aucun appel).
- **Délai** : 1,2 s au plus, ensuite texte brut. Le journal note, par dictée, la mise en forme choisie, si l'IA a servi (ou pourquoi non) et sa durée.
- **Garde-fou** (`RemiseAuPropre.verifier`) : texte brut collé si la sortie est vide, commence par un préambule (« Voici… », « Bien sûr… »), fait moins de 50 % ou plus de 150 % de l'entrée, ou si moins de 70 % de ses mots viennent de la dictée (c'est ce qui bloque une réponse à une question dictée). Puis retouches sûres : traits d'union insécables et apostrophes courbes normalisés, orthographe exacte des mots de mots.txt rétablie, espace avant `? ! : ;` en français, pas de point final dans un terminal ou une recherche.
- **Réglage** : `Settings.remettreAuPropre` (UserDefaults, clé `remettreAuPropre`, activé par défaut) ; le panneau du lot 7 le montrera.
- **Essai sans micro** : `Dictee --nettoyer "texte" --app com.apple.mail [--role AXTextField] [--titre "Gmail"]` (réseau seulement).

## Espaces intelligents (après le lot 5)
- Avant de coller, on cherche le caractère juste avant le curseur (`EspacesIntelligents`, fonctions pures dans `DicteeCore`).
- **Source** : l'Accessibilité (champ focalisé, `kAXSelectedTextRangeAttribute`, puis `kAXStringForRangeParameterizedAttribute`, sinon `kAXValueAttribute`), lue au relâchement pendant que Groq travaille (aucun délai ajouté, 0,15 s au plus par appel). Repli : la dernière insertion si c'est la même app, il y a moins de 2 minutes, et qu'aucune touche n'a été tapée depuis (l'écoute du clavier compte les `keyDown`, hors fn / 🌐 et hors ⌘V interne). **Terminaux : le repli passe d'abord**, la zone de texte d'un terminal ne donne pas sûrement la position du curseur.
- **Règles** : espace ajoutée devant sauf si le caractère précédent est une espace, un retour à la ligne, le début du champ, une ouverture (`( [ { « “ ‘ ' ’ " / @`), ou si le texte dicté commence par un signe collant (`, . ; : ! ? …`). Si le texte précédent ne finit pas une phrase (pas de `.` `!` `?` `…`, pas de retour à la ligne, pas de puce de liste), la première lettre dictée passe en minuscule, sauf sigle ou mot mixte (API, iPhone), « I » anglais, mot ou expression du dictionnaire (mots.txt). Seule la première lettre est touchée.
- Le journal note la nature du caractère précédent (lettre, espace, signe… jamais le texte), la source utilisée, et si une espace / une minuscule a été appliquée.

## Écarts (ce qui a été fait autrement, et pourquoi)
- **Signature** : le certificat auto-signé « Dictee Dev » a bien été créé (openssl + trousseau dédié), mais `codesign` refuse de l'utiliser tant qu'on ne l'a pas approuvé dans une fenêtre du système (impossible sans écran). Repli retenu : signature « ad hoc » avec une **exigence désignée fixe** (`designated => identifier "com.hugues.dictee"`), qui ne change pas d'une construction à l'autre. macOS devrait donc garder les autorisations après une reconstruction. **Non vérifié en vrai** (il faut que Hugues les accorde une première fois, puis reconstruire). Si macOS les redemande, on passera par l'approbation manuelle du certificat.
- **Mode Swift** : l'app (pas la logique pure) est compilée en mode de langage Swift 5. Les rappels du tap clavier, du micro et d'AppKit arrivent sur des fils que la vérification stricte de Swift 6 ne sait pas suivre ; le code concerné est isolé et relu à la main.
- **Contrôles** : un exécutable `swift run DicteeControles` (pas de `swift test`). Ajouts : `Dictee --transcrire fichier.wav` (Groq seulement), `Dictee --verifier-collage` (presse-papiers privé, faux ⌘V), `Dictee --rendu-encoche dossier` (PNG de l'encoche, sans fenêtre). Aucun ne touche au micro, à la parole, à l'accessibilité ni au clavier. Toute option `--` inconnue quitte au lieu de lancer l'app.
- **Découpe du son** : un morceau dure au moins 2 s avant de pouvoir être coupé (les morceaux plus courts font halluciner Whisper et multiplient les requêtes, alors que la limite gratuite de Groq est d'environ 20 requêtes par minute). Bruit de fond très fort (au-dessus de -45 dBFS) : plus de coupes, tout part au relâchement (plus lent mais juste). Les phrases fantômes de Whisper (« Merci d'avoir regardé cette vidéo », sous-titres Amara…) sont retirées.
- **Continuité du prompt** : le prompt d'un morceau contient la fin du morceau précédent seulement si celui-ci est déjà revenu (les morceaux partent en parallèle, on n'attend pas).
- **Secours** : si un seul morceau échoue, tout le texte vient d'Apple (un texte à trous serait pire). Apple fait sa dictée en parallèle pendant que Groq travaille.
- **Texte en direct** : le modèle de langue français de `SpeechAnalyzer` est un composant du système que macOS télécharge au premier lancement (préparé en arrière-plan). Si indisponible : repli sur `SFSpeechRecognizer` sur l'appareil, qui demande l'autorisation « Reconnaissance vocale ».
- **Finalisation** : pas de délai artificiel de 0,4 s. Le ruban se fixe en blanc au relâchement et l'encoche se referme dès que le texte final est prêt (c'est la durée de l'appel Groq, environ 0,4 s). Gain de vitesse.
- **Ouverture de l'encoche** : en mode « tenir », retardée de 0,12 s pour qu'un appui court (annulé) ne la fasse pas clignoter. En mains libres, immédiate.
- **Fenêtre** : niveau `mainMenu + 3` (au-dessus de la barre des menus et des icônes de la barre d'état). Le contour de la caméra dessiné sur la maquette n'est pas reproduit (le vrai noir de l'encoche suffit).
- **fn avalée** : le tap actif avale les changements de la touche fn pour éviter l'ouverture des emoji. **Non vérifié** : si les emoji s'ouvrent quand même, il faut régler « Appuyer sur 🌐 : Ne rien faire » (le menu « Autorisations… » l'explique). Constante `avalerFn` dans `KeyMonitor.swift`.
- **VS Code** (et Cursor) : traité en entier comme un terminal (pas de retour à la ligne), faute de pouvoir distinguer son terminal intégré sans lire l'arbre d'accessibilité.
- **Langue** : détection automatique ; pour forcer le français : `defaults write com.hugues.dictee langue fr`.
- **Double appui fn (correctif 09/11)** : sur ce Mac (🌐 = Emoji), le système émet un keyDown pour fn / 🌐 elle-même (codes 63 et 179) ; l'écoute le prenait pour une autre touche et cassait le double appui. Ces codes sont ignorés ; une ligne de journal signale toute autre touche reçue moins de 0,5 s après le relâchement de fn. **À confirmer à l'essai réel.**
- **Espaces intelligents, non vérifiables sans l'app** : ce que l'Accessibilité renvoie dans Terminal, Chrome (le contenu des pages n'est exposé que si l'accessibilité y est activée) et les apps Electron ; le journal dira quelle source a servi. Un nom propre non listé dans mots.txt (« Paris ») passe en minuscule en milieu de phrase : à ajouter au dictionnaire.
- **Lot 6, écarts** : (1) le plancher du garde-fou descend à 25 % (au lieu de 50 %) quand la dictée contient des hésitations, des corrections ou des commandes, sinon « euh, non plutôt mercredi » serait toujours refusé ; (2) « point » seul n'est une commande qu'en fin de dictée ou devant une autre commande ; (3) la durée de 1,2 s est parfois dépassée par Groq (environ 1 essai sur 10 en ligne de commande, connexion froide) : le texte brut est alors collé, sans erreur ; (4) le rôle `AXTextField` d'une page web (champ de formulaire) est aussi traité comme une recherche ; (5) rôle d'Accessibilité, titre de fenêtre et espaces intelligents **non vérifiables sans l'app lancée** par Hugues.

## Lot 7 (design ChatGPT v3 : design/chatgpt-v3/, brief fait foi)
Tout a été vérifié **hors écran** : rendus PNG par `Dictee --rendu-icones | --rendu-encoche | --rendu-panneau | --rendu-fenetre | --rendu-premier-lancement dossier` (aucune fenêtre, aucun micro, aucun clavier) et `swift run DicteeControles` (logique pure). Le comportement réel (focus, clavier, collage) n'a **pas** été essayé : c'est à Hugues.

- **7a** : guillemets fermants dessinés en vectoriel (`Logo.swift`, un seul tracé pour l'icône, la barre des menus et la fenêtre). Icône d'app 1024 px générée par l'app elle-même puis `iconutil` dans `build.sh` (AppIcon.icns). Icône de barre des menus « template » ; pendant la capture, image non template avec un trait ambre (#E6A04A) à côté du signe ; fond anthracite au survol / panneau ouvert. Encoche : congés concaves en haut, coins arrondis, ruban d'une ligne soudé (retrait 18 pt), seule la bande s'élargit en mains libres, ressort amorti de 200 ms interruptible, fondu de stabilisation de 120 ms (le curseur ambre apparaît derrière le texte final), « Réduire les animations » = fondu de 120 ms sans expansion. Dimensions de la caméra lues sur l'écran (`auxiliaryTopLeftArea` / `auxiliaryTopRightArea`). Fermeture : bande et ruban ensemble, l'insertion ne l'attend jamais.
- **7b** : historique `~/Library/Application Support/Dictee/historique.json` (droits 0600, 500 entrées, date + app cible + texte final, texte gardé même si l'insertion échoue, marqué « Non écrite »). Panneau compact 352 × 320 (rayon 14, lignes 36, navigation 40, Newsreader embarquée, ↑↓, Entrée recolle, ⌘C ou bouton copier, ⌘E ou chevron = texte complet, Échap efface la recherche puis ferme, clic ailleurs ferme). L'app cible est mémorisée à l'ouverture ; elle n'est jamais le champ de recherche. Une dictée qui commence ferme le panneau.
- **7c** : fenêtre 960 × 640, trois onglets, `⌘,` / « Ouvrir Dictée » (menu du clic droit sur l'icône), `⌘1-3`, `⌘K`. Mots : mots.txt, raccourcis vocaux (raccourcis.json) appliqués après la remise au propre, propositions en attente d'acceptation (propositions.json ; rien ne les remplit avant le lot 8). Réglages : micro (périphérique choisi via CoreAudio), langue, remettre au propre, adapter le ton (sinon contexte « général »), secours Apple (jamais « actif » tant qu'il n'est pas prêt), ouverture au démarrage (SMAppService), effacer l'historique, clé Groq, autorisations, prise en main.
- **7d** : premier lancement en 3 étapes (geste, accès avec détection chaque seconde + clé Groq rangée dans le Trousseau, première dictée réussie = texte réellement lu dans le champ d'essai). Ne s'affiche qu'une fois (`premierLancementFait`) ; une installation déjà complète (accès accordés + clé présente) est marquée faite sans rien afficher ; relançable depuis Réglages ou le menu.

### Écarts du lot 7
- **Panneau compact** : il contient Dictées seulement ; « Mots » et « Réglages » (les deux autres mots de sa navigation) ouvrent la fenêtre principale sur l'onglet. Choix volontaire : un seul endroit pour modifier.
- **Texte complet** : par chevron et ⌘E (la planche 04 ne dit pas comment).
- **Trait dans la caméra** des planches 03 / 06 non reproduit (le noir de l'encoche suffit, déjà noté au lot 5).
- **Ruban** : il sort avec les premiers mots reconnus (pas de ruban vide pendant l'appui) ; sans reconnaissance en direct, seule la bande apparaît.
- **Retrait de l'encoche** : orderOut 0,3 s après le début du retrait (200 ms + marge).
- **Prise en main** : l'app est activée à l'ouverture (la 3e étape écrit dans son propre champ) ; le panneau est un peu plus grand (440 × 440) que le panneau compact. Si le Trousseau refuse l'écriture, la clé reste à saisir ; `~/.config/groq/.env` reste lu en repli (et seul lu par les modes en ligne de commande).
- **Hors-ligne** : aucun texte ne le promet. Le secours Apple s'appelle « Apple » et sa phrase d'état dépend de sa préparation réelle.

### À vérifier en vrai (par Hugues, app installée)
1. Clic sur les guillemets : le panneau prend bien le clavier sans désactiver l'app au premier plan ; ↑↓ ; Entrée recolle dans l'app d'avant (essayer Notes, un navigateur, Terminal : jamais d'Entrée envoyé) ; Échap et clic ailleurs ferment ; un second clic sur les guillemets ferme.
2. Le fond anthracite derrière l'icône (survol / panneau ouvert) et l'icône « template » sur barre claire et sombre ; le trait ambre pendant la capture.
3. Ressort de l'encoche (200 ms) et « Réduire les animations ».
4. La fenêtre (⌘,) : focus au clavier, menus Micro / Langue / Secours, ouverture au démarrage (le système peut demander une validation dans Réglages Système › Général › Ouverture).
5. Prise en main : Réglages › Prise en main › Revoir ; les trois accès ; saisie de la clé (Trousseau : une fenêtre d'accès au Trousseau peut apparaître après une reconstruction de l'app) ; première dictée dans le champ.
6. Un raccourci vocal (« ma signature ») dicté dans une app.

## Lot 9 : installer et désinstaller comme une vraie app
- **Version** : un seul endroit, le fichier `VERSION` (0.1.0). `build.sh` en tire `CFBundleShortVersionString` et `CFBundleVersion`. `build.sh --sortie DOSSIER` assemble dans `DOSSIER/Dictee.app` sans rien installer.
- **`release.sh`** : construit en release dans `dist/` (ignoré par git), sans toucher à `~/Applications`, puis fabrique `dist/Dictee-<version>.dmg` avec `hdiutil` seul : l'app, un raccourci vers `/Applications` (glisser-déposer) et un `Lisez-moi.txt` en français. Pas de mise en page Finder (aucune fenêtre ouverte). Signature ad hoc à exigence fixe, comme `build.sh`, faute de compte développeur Apple.
- **Emplacement** : aucun chemin d'installation n'est codé en dur ; tout part de `Bundle.main` et du dossier personnel. Lancée depuis l'image disque (volume en lecture seule) ou depuis un dossier « AppTranslocation », l'app propose de se copier dans `/Applications` (sinon `~/Applications`) et de se relancer de là (`Installation` dans `DicteeCore`, copie à côté puis remplacement atomique).
- **Désinstaller Dictée…** (menu du clic droit et Réglages) : confirmation, puis arrêt de l'ouverture au démarrage, effacement de l'élément Trousseau de la clé Groq, de `Application Support/Dictee`, `Logs/Dictee`, des préférences (`com.hugues.dictee`), des caches, puis app à la corbeille (`NSWorkspace.recycle`) et sortie directe (rien n'est réécrit après). Le journal est arrêté avant l'effacement. La liste est dans `Desinstallation` (`DicteeCore`) et vérifiée par `DicteeControles` sur un faux dossier personnel : `~/.config/groq/.env` n'y figure jamais.
- **Non vérifié en vrai** (à essayer par Hugues sur une copie, jamais sur l'app qu'il utilise) : la proposition de déplacement depuis l'image disque, la désinstallation complète (corbeille, Trousseau), l'avertissement de première ouverture sur un autre Mac.

## Vitesse, micro et langue (09/11 soir)

Banc d'essai : `Dictee --transcrire fichier.wav --temps-reel --repetitions 10 [--nettoyer-aussi] [--app com.apple.mail]` (réseau seulement, aucun micro). Le son est livré à la vitesse d'un micro, le « relâchement » a lieu à la fin du fichier, on mesure jusqu'au texte (avec `--nettoyer-aussi` : jusqu'au texte remis au propre). WAV générés par `say -v Thomas` puis `afconvert` ; « sans » = 0,05 s de silence final, « courte » = pause de 0,4 s avant le relâchement. Médianes de 10 essais (4 pour 60 s, 3 pour la remise au propre à 60 s) ; le bruit du réseau est de ±40 ms d'une série à l'autre. Interrupteurs de mesure (variables d'environnement) : `DICTEE_ENVOI=wav`, `DICTEE_ROGNAGE=non`, `DICTEE_ANTICIPATION=non`, `DICTEE_SECOURS=non`, `DICTEE_DECOUPE=ancienne`, `DICTEE_UNITES=non`, `DICTEE_LANGUE=auto|fr|en`.

### Limites Groq et budget de requêtes
Whisper large v3 turbo, plan gratuit : 20 requêtes/minute, 2 000/jour, 7 200 s d'audio/heure (minimum facturé 10 s par requête). Modèle de langue (gpt-oss-20b) : 1 000 requêtes/jour, 8 000 jetons/minute. Les en-têtes `x-ratelimit-*` ne donnent que le restant du jour (et les jetons pour le modèle de langue) ; le compte par minute est tenu localement (`BudgetRequetes`). Les requêtes « de confort » (envoi anticipé, requête de secours, remise au propre à l'avance) ne partent que s'il reste de la marge (envoi anticipé : au moins 8 requêtes libres sur 18 ; secours : au moins 4 ; remise au propre : 6 sur 10 et au moins 3 500 jetons) ; après un 429, plus aucune requête de confort pendant `retry-after`. Les vrais morceaux partent toujours.

### Ce qui est fait
- **Dernier morceau parti avant tout le reste** au relâchement (avant l'arrêt du micro et de l'interface) ; lecture du champ (Accessibilité) dès l'appui, pour que le texte n'attende jamais l'Accessibilité.
- **Rognage du silence de fin** (0,25 s gardés après le dernier son) et **envoi en FLAC** (encodeur Apple, sans perte, relu identique ; `Dictee --verifier-flac`) : 64 % du poids du WAV, 6 à 20 ms d'encodage. Les textes sont identiques à ceux du WAV. Gain de délai non mesurable sur cette liaison (dans le bruit) ; utile surtout sur une liaison montante lente. Désactivable : `defaults write com.hugues.dictee envoiFLAC -bool false`.
- **Envoi anticipé** : 0,3 s après le dernier son, le morceau en cours part déjà (même rognage, même clé) ; au relâchement, s'il n'y a eu aucun son depuis, la requête en cours est reprise telle quelle, sinon elle est jetée. Au journal : « envoi anticipé réutilisé / jeté ».
- **Requête de secours** : si la réponse tarde plus de 0,7 s après l'envoi (ou échoue sur le réseau), une seconde requête identique part et la première réponse gagne. Même principe, à 0,55 s, pour la remise au propre. Secours Apple inchangé (4 s).
- **Longues dictées** : au-delà de 8 s, une micro-pause de 0,24 s coupe ; au-delà de 12 s sans pause, coupe forcée au point le plus calme des 1,5 dernière seconde. Le point que Whisper met à la fin d'un morceau coupé en pleine parole est retiré. Une dictée de 60 s fait 5 à 7 requêtes.
- **Remise au propre en avance** : (a) à la pause d'avant le relâchement, dès que Groq a répondu, le texte entier est remis au propre ; (b) pendant les longues dictées, par « unités » de phrases (jusqu'à la dernière fin de phrase que Whisper a ponctuée dans le texte, ou à une pause) ; au relâchement, il ne reste que la queue. Les unités ne sont pas utilisées (texte entier d'un coup, comme avant) si une correction dite ou une liste pourrait courir d'une unité à l'autre, si l'endroit a changé, ou pour les courriels / notes / assistants (paragraphes décidés sur le texte entier).
- **Connexion** : une seule session, HTTP/3 (QUIC) d'après les mesures réseau du journal, réutilisée entre les requêtes ; préchauffée à l'appui sur fn (≈ 170-240 ms pour une requête à vide, 33 ms de connexion neuve, tout cela pendant que l'utilisateur parle). Le journal note pour chaque requête : protocole, connexion neuve ou réutilisée, envoi, attente, réception.
- **Journal par étape** : relâchement → dernier morceau parti (ms) ; par morceau : durée du son, FLAC/WAV et Ko, codage, réponse Groq, mesures réseau ; envoi anticipé réutilisé/jeté ; requête de secours ; remise au propre (mode, attente, travail) ; collage ; total depuis le relâchement.

### Micro (AirPods)
Bug : avec des AirPods par défaut, rien ne se passait après l'appui. Le moteur audio gardait le micro du MacBook préparé et `engine.start()` pouvait bloquer sans jamais rendre la main. Maintenant : moteur reconstruit à chaque changement du micro par défaut ou de la liste des micros (écoute CoreAudio) ; tap installé avec le format réel (jamais gardé) ; si aucun son 0,8 s après l'appui : cause au journal, moteur reconstruit, un nouvel essai ; sinon abandon propre avec « Micro indisponible ». Réglage Micro : **Automatique** (défaut : micro intégré du Mac quand un casque Bluetooth est le micro par défaut, pour éviter le mode téléphone des AirPods), **Micro du système**, ou un micro précis (AirPods compris). Le journal note le micro, son transport et les formats. **Non vérifié en vrai** (impossible sans toucher au micro depuis un shell) : le démarrage avec AirPods, l'imposition du micro intégré (`kAudioOutputUnitProperty_CurrentDevice`). Limite connue : si `engine.start()` ne rend jamais la main (file audio bloquée), la dictée est abandonnée mais la file reste bloquée.

### Langue
Whisper se trompait de langue sur les phrases courtes (« Est-ce que ça marche ? » compris comme de l'allemand). Réglage Langue : **Français** par défaut (`language=fr` envoyé à Groq), Anglais, ou Automatique. En Automatique : `verbose_json` pour lire la langue détectée ; hors de la liste (français + anglais par défaut ; `defaults write com.hugues.dictee languesAutorisees -array fr en`), le même morceau est relancé aussitôt en français (coût mesuré : +250 ms, une requête de plus). Le prompt de Whisper commence par une phrase d'ancrage dans la langue choisie (« Transcription d'une dictée en français. »), retirée du texte si Whisper la répète sur du silence.

### Mesures (relâchement de fn → texte, médiane / maximum en ms, 10 essais)
| Dictée | Avant | Après |
|---|---|---|
| 1,5 s, sans pause | 288 / 382 | 270 / 328 (dans le bruit) |
| 1,5 s, pause de 0,4 s | 293 / 417 | 129 / 195 |
| 6,8 s, sans pause | 325 / 517 | 297 / 520 (dans le bruit) |
| 6,8 s, pause de 0,4 s | 301 / 418 | 183 / 319 |
| 21 s avec ponctuation, sans pause | 432 / 646 | 414 / 696 |
| 21 s avec ponctuation, pause de 0,4 s | 459 / 641 | 245 / 2 358 (valeur isolée due au secours défectueux, corrigé ensuite) |
| 20 s d'une traite | 413 / 542 | 382 / 405 |
| 56 s d'une traite (4 essais) | 805 / 918 | 290 / 317 |
| Pause d'au moins 0,7 s avant le relâchement | 0 à 33 | 0 à 1 (l'ancienne coupe à 0,5 s faisait déjà le travail) |
| Avec remise au propre, 6,8 s, pause 0,4 s | 696 / 820 | 632 / 757 puis 862 / 1 240 (Groq lent à ce moment) |
| Avec remise au propre, 20 s d'une traite | 889 / 1 890 | 812 / 1 357 (le texte de ce WAV n'a aucune ponctuation : pas d'unité possible) |
| Avec remise au propre, 56 s d'une traite (3 essais) | 1 547 / 1 867 | 772 / 922 |
Pas à pas (6,8 s sans pause, 21 s sans pause) : rognage seul 320 / 479 ; FLAC seul 326 / 447 ; les deux 320 / 447 (avant : 325 / 432). Le texte transcrit est identique à chaque étape. Requête de secours, test avec la première requête retardée de 1,5 s : 1 965 → 1 060 ms. Langue : 3 phrases de 1 à 1,5 s (« Est-ce que ça marche ? », « Excusez-moi. », « On se voit demain. »), 10 essais chacune, français par défaut : 30 sur 30 corrects, aucune langue étrangère (la détection automatique, elle aussi, donnait 30 sur 30 avec une voix de synthèse très propre : l'erreur de Hugues vient de sa vraie voix, que les WAV de synthèse ne reproduisent pas).

### Écarté
- **Autre modèle pour la remise au propre** : seuls gpt-oss-20b, gpt-oss-120b, qwen3.8-27b et allam-2-7b sont chez Groq (pas de llama « instant »). Mesures avec la même consigne : gpt-oss-20b 0,7 à 1,3 s, gpt-oss-120b 0,3 à 1,1 s (et il garde les « euh »), qwen 0,4 à 3,4 s. Aucun n'est plus rapide ni plus fiable : gpt-oss-20b reste.
- **Remise au propre par morceau pour courriel, notes, assistants** : le découpage en paragraphes se décide sur le texte entier.
- **Pause d'anticipation plus courte que 0,3 s** : trop de requêtes jetées (les pauses de 0,2 s entre deux mots sont fréquentes).
- **Forcer HTTP/2** : URLSession choisit HTTP/3 tout seul et réutilise la connexion ; rien à gagner.
- Le gain réel de l'envoi anticipé dépend de la pause de l'utilisateur avant de relâcher : aucun en dessous de 0,3 s, jusqu'au délai de Groq (~0,3 s) à partir de ~0,65 s.

## Verbe 0.2.0 : nouveau nom, touche 🌐, sons et vibration

### Nom : Verbe (choix de Hugues, 09/11) et « Écarts »
- **Visible partout** : `CFBundleName` / `CFBundleDisplayName` = Verbe, paquet `Verbe.app`, exécutable `Contents/MacOS/Verbe`, titre de la fenêtre, menus (« Ouvrir Verbe », « Quitter Verbe », « Désinstaller Verbe… »), premier lancement, messages et alertes, DMG `Verbe-<version>.dmg` (volume « Verbe »), Lisez-moi, README, notes de version.
- **Écart voulu : l'identifiant `com.hugues.dictee` et les noms internes ne changent pas.** Les autorisations du système (micro, accessibilité, surveillance de l'entrée) sont attachées à l'identifiant et à la signature (exigence désignée `identifier "com.hugues.dictee"`), l'élément du Trousseau (service `com.hugues.dictee`, compte `groq`), les préférences (`com.hugues.dictee`), `Application Support/Dictee` (historique, mots, raccourcis), `Logs/Dictee`, le nom d'enregistrement de la fenêtre et les types `Dictee*` du code : changer l'un d'eux ferait perdre à Hugues ses autorisations, son historique ou son dictionnaire. Le produit SwiftPM s'appelle toujours `Dictee` (les modes de vérification en ligne de commande `Dictee --rendu-…` aussi) ; `build.sh` recopie le binaire sous le nom `Verbe` dans le paquet. Le dépôt GitHub garde son nom pour l'instant.
- **Même identifiant = une seule instance** : Verbe refuse de tourner en même temps que l'ancienne `Dictee.app`. Il faut quitter l'ancienne d'abord (`build.sh` ferme l'app qui tourne ; il signale une ancienne `Dictee.app` restée dans Applications).
- **Désinstallation** : elle place aussi à la corbeille une ancienne `Dictee.app` trouvée dans `/Applications` ou `~/Applications` (jamais l'app qui tourne, jamais autre chose), et la nomme dans la fenêtre de confirmation avant d'agir (`Desinstallation.anciennesApps`, vérifié par `DicteeControles`).
- **Première ouverture corrigée** : sur macOS récent, une app non notarisée n'offre plus « Ouvrir » au clic droit ; la fenêtre ne propose que « Placer dans la corbeille » et « Terminé ». Consigne écrite partout : « Terminé » (pas la corbeille), Réglages Système › Confidentialité et sécurité › tout en bas « Ouvrir quand même », rouvrir ; ou `xattr -dr com.apple.quarantine /Applications/Verbe.app`. **Non rejouée avec le DMG de cette version** (voir « À vérifier »).

### Touche 🌐 au premier lancement
- Détection : `AppleFnUsageType` du domaine `com.apple.HIToolbox` (`ToucheGlobe` dans `DicteeCore`, lecture seule par `CFPreferences`). 0 = « Ne rien faire » ; 1, 2, 3 ou clé absente (réglage d'origine du Mac) = à régler. Valeurs : 1 changer de méthode de saisie, 2 emoji, 3 dictée d'Apple (lecture d'après l'ordre du menu du volet Clavier ; la valeur 3 est celle relevée sur le Mac de Hugues le 09/11).
- Étape « Votre touche 🌐 ouvre les emoji » (le titre suit la valeur) entre les accès et la première dictée, seulement si le réglage est à faire. Bouton qui ouvre le volet Clavier (`x-apple.systempreferences:com.apple.Keyboard-Settings.extension`) et consigne « Appuyer sur la touche 🌐 pour : Ne rien faire ». Relecture chaque seconde ; dès que la valeur vaut 0, l'étape passe à l'essai : « appuyez deux fois sur fn », reconnu par le détecteur de geste (aucune dictée ne démarre pendant cet essai). « Plus tard » saute l'étape. **Aucun `defaults write`** : il ne s'applique pas sans passer par le volet (leçon du 09/11).
- Réglages : une ligne « Touche 🌐 » discrète (phrase + « Ouvrir le volet Clavier ») n'apparaît que si la valeur est ≠ 0, relue chaque seconde.
- Limite : une clé absente est comptée « à régler » ; un Mac sans touche 🌐 qui n'a jamais touché ce réglage verra la ligne tant qu'il ne l'aura pas passé à « Ne rien faire ».

### Sons et vibration (demande de Hugues)
- **Sons à nous** (`SonSynthese`, `DicteeCore`) : sinus avec enveloppe en cloche (sin²), fabriqués en mémoire au lancement et gardés prêts dans des `AVAudioPlayer` (aucun fichier son, rien de copié). Début : deux notes montantes (mi5 puis la5, 120 ms). Texte collé : une note qui descend (sol5 vers mi5, 90 ms). Annulation : un tic grave (175 → 140 Hz, 50 ms). Pic de -16 à -13 dBFS avant le volume de lecture (0,5 à 0,6) : environ -20 dBFS joués. Lecture asynchrone : rien n'attend le son.
- **Vibration** (`Retours`, `NSHapticFeedbackManager`, `performanceTime: .now`) : début `.levelChange`, texte collé deux `.alignment` à 80 ms, annulation `.generic`. **Limite matérielle : elle ne se sent que si un doigt est posé sur le trackpad Force Touch.**
- **Réglages** « Sons » et « Vibration », séparés, activés par défaut (`defaults write com.hugues.dictee sons|vibration -bool false`). Pas de « mode silencieux » sur Mac : le volume du système coupé coupe aussi les sons.
- **Moment** : mains libres, à l'ouverture de l'encoche ; mode « tenir », à 0,12 s avec l'encoche (un appui court, premier appui d'un double appui, ne fait donc ni son ni vibration). L'annulation ne sonne que si le son de début a été joué. Le son de fin part au collage réussi seulement (pas pour un champ protégé ni un texte seulement copié).
- **Le micro n'entend pas le son pour de la voix** : la détection de parole (`VoiceChunker`) ignore les premières tranches (`ignoredStartFrames` : 10, soit 0,2 s, en mains libres ; 16, soit 0,32 s, en mode « tenir »), sans toucher au bruit de fond appris ; le rognage de début garde d'autant plus de tranches avant la parole, donc une parole commencée pendant le son n'est pas rognée. Le son lui-même n'est pas retiré de l'enregistrement. Vérifié par `DicteeControles` (masque, parole conservée, durées, volume, absence de clic). **Non vérifié en vrai** : ce que le micro capte réellement du haut-parleur du Mac.

### À vérifier en vrai (par Hugues)
1. Installer depuis `Verbe-0.2.0.dmg` sur une copie : la consigne « Terminé » puis « Ouvrir quand même » sur macOS 26.
2. Quitter Dictée, ouvrir Verbe : autorisations conservées ? (le lancement au démarrage aussi).
3. Étape 🌐 : changer le réglage dans le volet Clavier, l'étape passe-t-elle seule ? le double appui d'essai ?
4. Sons : volume agréable, pas de son capté dans le texte (dicter une phrase très courte), vibration sentie doigt posé.
5. Désinstallation avec une ancienne `Dictee.app` dans Applications.

### Adresses dictées (0.2.0)
- Constat de Hugues : « h2delpit@gmail.com » dicté sortait « VepoH2LPadjamai.com ». Deux réponses : (1) `AdressesDictees` (`DicteeCore`), règle locale sans IA appliquée au texte final avant les raccourcis vocaux (`DictationController.ecrire`), donc aussi quand la remise au propre n'a pas lieu ; (2) une consigne et un exemple dans la remise au propre. Les raccourcis vocaux « mon mail » / « mon adresse mail » restent le moyen sûr pour SON adresse : ils passent en dernier, le plus long d'abord, et gardent la ponctuation autour (vérifié par `DicteeControles`).
- La règle ne se déclenche que sur « arobase » (ou « @ ») pour un mail, ou « www » + « point » pour une adresse web. Avant l'arobase : lettres et chiffres épelés (chiffres dits compris, hors « un »), mots entiers seulement juste avant l'arobase ou après un séparateur, « point », « tiret », « tiret du bas », « underscore ». Après : un domaine qui finit par une extension connue (liste dans `extensions`), sinon texte inchangé. Minuscules, accents retirés, ponctuation de phrase et retours à la ligne conservés.
- Limites : une lettre « a » seule avant l'arobase est lue comme épelée ; « point com » sans arobase ni www n'est jamais transformé ; si Whisper transcrit un autre mot que celui dicté (le cas ci-dessus), la règle ne peut pas deviner : raccourci vocal ou mot du dictionnaire.

## Filet de sécurité de l'écriture et mots collés (09/11 soir)

### Filet de sécurité (demande de Hugues)
« Lorsque la transcription se fait mais que l'écriture ne se met pas bien dans la barre où le curseur est, il faut une sorte de widget qui s'ouvre à partir de la barre d'en haut et qui me permette de copier-coller le texte. » Maquette choisie : `design/maquettes/filet-securite.html`, variante B « l'encoche reste ouverte ».
- **Détection** (logique pure `VerificationInsertion`, contrôlée par `DicteeControles`) : après le ⌘V, l'Accessibilité relit les 24 derniers caractères avant le curseur de l'app cible (`LecteurInsertion`), à 250, 400 puis 650 ms ; une seule preuve d'écriture suffit.
  - échec seulement sur une preuve : aucun élément focalisé alors qu'une fenêtre existe ; champ dont le curseur est lisible mais où le texte n'apparaît pas ; rôle qui ne peut pas recevoir de texte (bouton, texte fixe…) et rien de lisible ;
  - jamais d'alarme quand on ne peut simplement pas lire (apps sans Accessibilité, délai dépassé) ni dans un terminal (position du curseur non fiable), sauf s'il n'y a aucun élément focalisé ;
  - hors lecture : champ protégé, Accessibilité non accordée (déjà détectés), app visée disparue ou qui ne peut pas reprendre le clavier (`Collage.Issue.cibleIndisponible` : rien n'est collé ni touché dans le presse-papiers).
- **Interface** (`FiletVue`, `FiletPanneau`) : la même silhouette noire que pendant la dictée reste ouverte (icône de l'app visée à gauche, point ambre à droite, centre vide), le ruban s'agrandit et montre le texte complet en Newsreader 16 pt (2 à 4 lignes, défilable au-delà, dernière ligne qui s'efface), « Coller ici ↵ » et « Copier ⌘C » à droite sur fond #1d1d1c. « Copier » écrit « Copié » puis referme. Panneau non activant qui prend le clavier (Retour, ⌘C, Échap) ; se ferme par Échap, un clic ailleurs, ou seul après 10 s sans interaction (compte à rebours suspendu tant que la souris est dessus) ; ressort d'ouverture et de fermeture de l'encoche, fondu seul avec « Réduire les animations » ; une frappe légère du trackpad à l'apparition. « Coller ici » retente dans l'app au premier plan (jamais Verbe).
- Le texte est dans l'historique avec `insere = false` et la raison. Un nouveau départ de dictée ou l'ouverture du panneau compact ferme le filet ; pendant une dictée en cours le filet n'apparaît pas (le texte est dans l'historique).
- Menu de la barre (clic droit) : « Dernière dictée » ouvre le même filet avec le dernier texte.
- Réglage : `defaults write com.hugues.dictee filetDeSecurite -bool false` rend l'ancien bref message dans l'encoche.
- Rendus hors écran : `Dictee --rendu-filet dossier` (`design/rendus-filet/`).

### Mots collés (« à plus tard » écrit « àplus tard »)
Cause non trouvée : l'historique contient la dictée où Hugues l'a signalé (« Je veux dire, à plus tard, il va mettre à plus tard tout attaché ») et « à plus tard » y est correctement écrit ; Whisper (voix de synthèse) et la remise au propre l'écrivent correctement aussi. Ont été vérifiés et passent (contrôles) : règle des adresses, espaces intelligents, remise au propre locale, raccourcis vocaux, assemblage des morceaux, dictionnaire, typographie. Corrigé ou ajouté par précaution :
- `MotsColles` : un mot de la sortie de la petite IA qui est exactement la concaténation de 2 à 4 mots consécutifs de l'entrée est remis en mots séparés (garde-fou dans `RemiseAuPropre.verifier`, trace au journal) ;
- `TextAssembler.joindre` : pas d'espace après une apostrophe ou un trait d'union en fin de morceau (« lorsqu' » + « on »), ni devant une virgule ou un « ? » en début de morceau ;
- adresses : un « a » (verbe) devant un mot n'est plus pris pour une lettre épelée (« il a jean arobase… »).
- Journal : pour chaque dictée dont le texte final diffère du texte Groq autrement que par la ponctuation ou la casse, une ligne `texte Groq → final : "…" → "…"` (60 caractères de chaque côté, centrés sur la première différence). Seule exception à la règle des 30 caractères.

### À vérifier en vrai (par Hugues, app installée)
1. Cliquer dans une zone sans champ de texte (Finder, page web hors champ, app sans note ouverte), dicter : le filet doit s'ouvrir sous l'encoche, vibrer, et « Copier » / « Coller ici » / Échap / 10 s doivent marcher.
2. Dicter dans un champ normal (Notes, Mail, barre de recherche, Claude) : aucun filet. Si le filet s'ouvre à tort, relever l'app et la ligne « vérification de l'écriture » du journal.
3. Terminal : jamais de filet (voulu).
4. Lire le journal après quelques dictées : lignes « texte Groq → final » pour retrouver un mot collé.

## Lot 8 bis : le grand dictionnaire qui apprend (09/11 soir)

Demande de Hugues : « l'alimenter avec un dictionnaire… un tas de mots compliqués, dans différentes langues… l'entraîner », avec « toujours le plus accurate possible ». On ne réentraîne pas Whisper : on lui donne les bons mots à chaque dictée, puis on corrige à l'oreille ce qu'il a quand même mal entendu, et on apprend des corrections de Hugues.

### 1. Le lexique local
- Fichier `~/Library/Application Support/Dictee/lexique.json` (droits 0600). Il contient des noms de la vie de Hugues : **il n'entre jamais dans git**. Chaque mot : écriture, fréquence, nombre de documents, source (nom de dossier), langue (`fr`, `en`, `autre`), type (`nom`, `sigle`, `technique`).
- Construit par `Verbe --construire-lexique` (ni micro, ni réseau, ni Accessibilité ; `ConstruireLexique`, logique pure dans `ExtractionLexique`). Il lit `~/second-cerveau` (tout sauf `moi/`, jamais ouvert) et chaque dossier de projet de `~` qui contient des `.md` ou `.txt` ; sont ignorés : `node_modules`, `.git`, `.build`, `dist`, `Library`, `Downloads`, `Desktop`, environnements virtuels, dossiers cachés (`.claude`, `.superpowers`), copies de travail git, builds et journaux de projets Unity, fichiers de plus de 1 Mo, doublons exacts (empreinte SHA-256), l'app de dictée elle-même (ses notes citent des mots mal entendus en exemple). `--pourquoi mot` explique pourquoi un mot est retenu ou écarté.
- Mots gardés : noms propres (majuscule en milieu de phrase), sigles (CEE, TRA-SE-104), mots composés, jargon et mots étrangers inconnus du correcteur du Mac (NSSpellChecker, français ET anglais : un mot connu de l'un ou de l'autre est écarté), majuscule intérieure (iPhone, kWh) même si le correcteur le connaît. Écartés : mots courants, mots en capitales qui sont des mots courants (IMPORTANT), blocs de code, adresses, chemins, hexadécimaux, identifiants de code (keyDown), noms de fichiers à tirets (verif-hors-ligne), fautes d'accents de code (« recoit »), mots de moins de 5 lettres en minuscules, identifiants au hasard.
- Classement : fréquence **plafonnée à 10 apparitions par document** (un gros fichier ne peut pas écraser le reste), puis nombre de documents. Les mots de `mots.txt` passent toujours devant (source `mots.txt`). Une courte liste de mots difficiles (villes d'Afrique de l'Ouest, d'Espagne, du Portugal, d'Europe centrale, marques) vient en dernier (source `base`, `LexiqueDeBase`), débarrassée de ce que le correcteur connaît déjà.

### 2. Les mots envoyés à Whisper à chaque dictée
- `ChoixMotsPrompt` (`DicteeCore`, logique pure) remplace `TextAssembler.prompt` dans l'app. Ordre du prompt : ancre de langue, mots de `mots.txt`, mots du lexique les plus probables, fin du texte du morceau précédent.
- Note d'un mot du lexique = ln(1 + fréquence) + ½ ln(1 + documents), plus : +14 s'il est cité par le texte avant le curseur ou la dictée en cours (lu par l'Accessibilité), +12 par le titre de la fenêtre, +5 à +12 par les 20 dernières dictées de l'historique, +1,5 pour les mots de la même source qu'un mot cité, et un biais selon l'app (terminal : termes techniques ; autres apps : noms propres).
- Qui entre dans le prompt : tous les mots de `mots.txt` d'abord ; puis les mots du lexique **cités par le contexte** (texte avant le curseur, titre de la fenêtre, dictée en cours, dernières dictées), jusqu'à 60 mots ; puis seulement une dizaine de mots parmi les plus fréquents, dont deux sigles au plus. Constaté au banc d'essai : sans rien qui désigne un mot, une longue liste de mots rares ne fait pas mieux et peut nuire — Whisper en imite le style (le nom d’un outil sorti tout en capitales quand la liste contenait beaucoup de sigles) ; la version de départ (une trentaine de mots fréquents) a donc été réduite.
- Budget : 200 jetons estimés au total (Whisper en lit 224 au plus **en gardant la fin** : dépasser ferait couper l'ancre et les mots). Estimation prudente (2,3 caractères par jeton + la virgule). Le texte précédent garde toujours au moins 45 jetons (continuité de la ponctuation) et reçoit le reste du budget. Vérifié par contrôle avec de gros textes précédents et beaucoup de mots choisis. Coût mesuré : 25 ms pour un lexique de 6 000 mots (version de contrôle non optimisée), sur le fil de l'envoi, jamais sur le chemin du son.
- Réglage : `DICTEE_LEXIQUE=non` ou `defaults write com.hugues.dictee lexiquePourWhisper -bool false` revient à `mots.txt` seul. Sans `lexique.json`, comportement d'avant (au budget de jetons près).

### 3. Correction « à l'oreille » après Groq
- `CorrectionOreille` (`DicteeCore`) est appliquée à chaque morceau, dès la réponse de Groq (`ChunkTranscriber`), donc avant la remise au propre, l'envoi anticipé et le contexte du morceau suivant. Le correcteur du Mac est interrogé sur le fil principal (`Orthographe`, avec mémoire).
- Un mot est remplacé par un mot du lexique (ou de `mots.txt`, prioritaire à égalité) seulement si : le correcteur orthographique ne le connaît pas ; il a 4 lettres ou plus ; la clé phonétique française adaptée (`ClePhonetique` : ph/f, c/k/qu, ll, h muet, nasales, lettres finales muettes) est à 1 lettre au plus ; l'écriture est à 1 lettre (≤ 5 lettres), 2 (≤ 7) ou 3 (au-delà) au plus ; **un seul candidat est nettement le meilleur** (écart de coût ≥ 2 avec le second) ; ou, pour un mot d'au moins 6 lettres, une seule lettre de différence (« Vermflow » → « Vermiflow ») ; il n'est pas collé à une adresse, un chemin ou un identifiant. Deux mots séparés par une espace dont l'assemblage est exactement un mot du lexique sont réunis (« Eco verdix » → « Ecoverdix », « la Domir » → « Ladomir »), et un « l' » entendu devant un nom est repris dans le nom (« l'adomir » → « Ladomir »). Le pluriel (« Brillonias ») est respecté. La casse n'est imposée que pour les écritures qui ne se devinent pas (kWh, CEE) et les mots choisis par Hugues (y compris quand Whisper les met en capitales) ; un nom du lexique qui sort en minuscules reste en minuscules (« alloco »).
- Journal : une ligne par correction, `correction à l’oreille : "Brionia" → "Brillonia"` (60 caractères au plus de chaque côté).
- Réglage : `DICTEE_OREILLE=non` ou `defaults write com.hugues.dictee correctionALOreille -bool false`. `Verbe --oreille "texte"` montre ce que la correction ferait (aucun réseau).

### 4. Apprendre des corrections
- `SurveillanceCorrections` : après un collage réussi (hors terminal, hors champ protégé, seulement si l'app expose le champ par l'Accessibilité), la zone du champ est lue (texte écrit, 30 caractères avant, 250 après), puis relue 6 s et 15 s plus tard. `ApprentissageCorrections` (logique pure) compare les deux lectures mot à mot (plus longue suite commune) : un remplacement de 1 à 3 mots, dont les mots d'origine viennent du texte écrit et qui ressemble à l'ancien (écriture ou phonétique), donne un mot **proposé** dans « Mots » si le correcteur ne le connaît pas. Rien n'est proposé si le champ a changé de nature (moins de 70 % des mots retrouvés), si du texte a seulement été ajouté, ou pour un mot courant. Accepter une proposition l'ajoute à `mots.txt` (ce qui existait déjà) ; l'ignorer la retient pour ne plus la reproposer.
- Réglage : `DICTEE_APPRENTISSAGE=non` ou `defaults write com.hugues.dictee apprentissageDesCorrections -bool false`.

### 5. Banc d'essai chiffré (09/11 soir)
Outils : `scripts/banc-lexique.sh DOSSIER` fabrique les sons (voix de synthèse du Mac `say` : Thomas, Jacques, Amélie en français ; Samantha, Daniel, Fred, Kathy en anglais ; puis `afconvert` en 16 kHz mono) d'après `DOSSIER/phrases.json` ; `Verbe --banc-lexique DOSSIER` (réseau seulement, une requête toutes les 3,4 s pour rester sous les 20 requêtes par minute de Groq) envoie chaque phrase deux fois — **AVANT** : le prompt d'avant le lexique (`mots.txt` seul), **APRÈS** : le prompt choisi dans le lexique d'après le contexte de la phrase — puis applique la correction à l'oreille. `--reutiliser-avant` refait seulement les requêtes APRÈS ; `--banc-lexique-rejouer DOSSIER` refait la correction à l'oreille sur les textes déjà reçus (aucun réseau). Un mot du lexique est « juste » s'il est écrit exactement (majuscules et accents compris). Une correction est **fausse** si elle touche un mot déjà écrit comme dit, ou si le mot mis à la place n'a jamais été dit. Les phrases (qui contiennent des noms de la vie de Hugues) et les résultats restent dans `~/Library/Application Support/Dictee/banc*`, jamais dans git.

80 phrases en trois lots (60 en français, 20 en anglais ; 21 avec un contexte — titre de fenêtre ou texte avant le curseur ; 8 phrases de contrôle sans aucun mot du lexique, dont des noms d'Afrique que le correcteur connaît), 167 mots du lexique : noms de lieux d'Abidjan et de Côte d'Ivoire, d'Afrique de l'Ouest, du Maghreb, d'Europe centrale et du Portugal, marques et outils, sigles, un terme métier. Lot A (40 phrases) a servi à régler ; lot B (20) a servi à voir que le prompt de départ nuisait sans contexte (d'où sa réduction) ; **lot C (20 phrases) n'avait jamais été vu avant le dernier passage**. Résultats du système final :

| Mots du lexique écrits exactement | AVANT (prompt d'avant) | prompt choisi seul | correction à l'oreille seule (sur AVANT) | **APRÈS (prompt choisi + correction)** |
|---|---|---|---|---|
| Lot A, 89 mots | 33 (37,1 %) | 39 (43,8 %) | 42 (47,2 %) | **49 (55,1 %)** |
| Lot B, 41 mots | 13 (31,7 %) | 14 (34,1 %) | 21 (51,2 %) | **22 (53,7 %)** |
| Lot C, 37 mots (jamais vu) | 15 (40,5 %) | 15 (40,5 %) | 22 (59,5 %) | **19 (51,4 %)** |
| **Total, 167 mots** | 61 (36,5 %) | 68 (40,7 %) | 85 (50,9 %) | **90 (53,9 %)** |
| avec contexte, 49 mots | 36,7 % | 42,9 % | 46,9 % | **53,1 %** |
| sans contexte, 118 mots | 36,4 % | 39,8 % | 52,5 % | **54,2 %** |
| français, 128 mots | 32,0 % | 35,2 % | 47,7 % | **48,4 %** |
| anglais, 39 mots | 51,3 % | 59,0 % | 61,5 % | **71,8 %** |

**Fausses corrections : 0** sur 25 corrections appliquées (80 phrases, correction à l'oreille testée à la fois sur le texte APRÈS et sur le texte AVANT), et 0 correction sur les 8 phrases de contrôle. Ce que la correction a rattrapé : un prénom entendu en deux mots ou avec un « l' » devant, « Conto », « Markori », « Trekville », « Kurho-Go », « Wispé », « PippaDrive », « ring over »… (noms de la vie de Hugues et de ses voyages, orthographes de Whisper).
Lecture honnête :
- Les taux absolus sont bas parce que les voix de synthèse prononcent mal ces noms (un nom de projet inventé dit par Thomas ne ressemble à rien) : ce banc mesure surtout la **progression**. Sur du vrai français de Hugues, Whisper part de plus haut.
- Le gain vient surtout de la **correction à l'oreille** (+14 points seule). Le **prompt choisi** donne +4 points au total (9 mots gagnés, 2 perdus) et c'est avec un contexte qu'il sert (+6 points) ; sans contexte il ne fait presque rien (+3 points). Sur le lot C, le prompt n'a rien changé, et la correction appliquée aux textes de l'APRÈS a moins rattrapé que sur ceux de l'AVANT (3 mots d'écart sur 37 : au niveau du bruit, un prompt différent change les erreurs de Whisper).
- Whisper n'est pas déterministe d'un passage à l'autre : ±2 mots par lot.
- Ce que la correction ne peut pas faire : un nom entendu comme un autre mot qui existe (« Tito » pour TikTok, « compte » pour Qonto, « Kumasi » pour Koumassi) — c'est la règle de prudence « jamais un mot connu du correcteur » — ni un mot trop éloigné à l'oreille (« Hot » pour OAuth).
- Pas encore mesuré avec de vraies dictées de Hugues (voir ci-dessous).

### À vérifier en vrai (par Hugues, app installée)
1. Lancer une fois `Verbe --construire-lexique` dans le Terminal (ni micro ni réseau), puis regarder le fichier ; en refaire un de temps en temps (il ne se met pas à jour tout seul). Retirer à la main (ou dans le JSON) les mots qui n'ont rien à faire là.
2. Dicter en tenant fn, dans Notes ou Mail, une phrase avec un nom de ses notes mal prononcé : lire dans le journal (`~/Library/Logs/Dictee/dictee.log`) les lignes `correction à l'oreille : "…" → "…"`. Si une correction est fausse, relever la ligne.
3. Corriger un mot à la main dans les 15 secondes qui suivent une dictée (Notes, Mail, Pages ; l'app relit le champ à 6 s et à 15 s) : le mot corrigé doit apparaître dans l'onglet Mots, en proposition ; l'accepter doit l'écrire dans `mots.txt`. Dans un terminal, ou une app qui ne laisse pas lire le champ, rien ne doit apparaître (le journal dit « apprentissage impossible »).
4. Comparer 10 dictées avec `defaults write com.hugues.dictee lexiquePourWhisper -bool false` (et `correctionALOreille -bool false`) puis avec les réglages par défaut.

## Notes de réunion (09/11 soir)

Demande de Hugues : « l'enregistrement de la réunion, c'est comme Wispr Flow » (le micro **et** le son du Mac), puis la note : « selon la réunion, il y a ça qui a été dit, ça qui a été fait ». Maquette validée : `design/maquettes/reunions.html`, version A « Le carnet ». Rendus hors écran : `design/rendus-reunions/` (`Verbe --rendu-reunion DOSSIER`).

### Lancer, arrêter
- ⌥⌘N (globale, avalée par l'écoute du clavier existante) lance ou arrête ; entrée « Noter la réunion » sous la recherche du panneau compact, et dans le menu de la barre des menus (« Arrêter la réunion » pendant l'enregistrement) ; bouton dans l'onglet Réunions. Arrêt aussi par le carré de l'encoche ou « Arrêter » du ruban (au survol).
- Proposition « Noter cet appel ? » : toutes les 2 s, lecture seule des processus audio (`kAudioProcessPropertyIsRunningInput`, aucune autorisation, aucun son capté) ; liste blanche d'apps d'appel (Zoom, Teams, FaceTime, Skype, WhatsApp, Aircall, Webex, Slack, Discord, Telegram, navigateurs pour Meet) ; une proposition par appel, après 6 s d'écoute continue, jamais pendant une réunion ; « Non » ou 15 s = elle disparaît. **Jamais d'enregistrement sans clic.** Réglage : « Proposer de noter les appels ».
- Écart de nommage : l'ordre des onglets suit la maquette (Dictées, Réunions, Mots, Réglages) ; le panneau compact ne montre plus l'aide « ↑↓ choisir ↵ recoller » (quatre onglets + aide ne tiennent pas dans 352 pt ; la maquette n'en montre pas).

### Capture : deux pistes
- **Moi** = le micro, par un moteur AVAudioEngine **à lui** (`MicroReunion`), même choix de micro que la dictée (`ChoixMicro` : micro du Mac quand un casque Bluetooth est le micro par défaut). Tout appel passe par `VerbeEssayer`.
- **Eux** = le son du Mac par un *process tap* Core Audio (`SonSysteme` : `CATapDescription` mono global sauf Verbe lui-même, `AudioHardwareCreateProcessTap`, appareil agrégé privé, lecture par `AudioDeviceCreateIOProcIDWithBlock`) ; macOS 14.4+, API vérifiées dans les en-têtes du SDK (typecheck + build). Réinstallé si la sortie audio change. Si macOS refuse : le micro seul continue et la note le dit (« À savoir »). Un son du Mac resté à zéro 15 s n'est **pas** pris pour une preuve de refus : journal + phrase prudente dans la note (rien ne jouait, ou autorisation manquante).
- **Dictée pendant une réunion** : la touche fn reste possible (moteur micro séparé, aucune pause) ; l'encoche de la dictée passe devant celle de la réunion. Ce qu'on dicte étant dit à voix haute, il se retrouve aussi dans la piste Moi. Choix fait parce que c'est le plus sûr : on ne touche pas au moteur de la dictée.
- Retours : vibration légère au début (1 frappe) et à la fin (2 frappes), **sans son** (un son serait capté ou gênerait un appel).
- Pistes : `PisteReunion` (conversion 16 kHz mono, niveau, `VoiceChunker` réglé pour les réunions : coupe à une pause de 0,6 s après 10 s, micro-pause 0,24 s après 20 s, coupe forcée après 30 s ; seul le morceau en cours reste en mémoire). Pause : le dernier morceau part, l'horloge s'arrête (`HorlogeReunion`).

### Transcription au fil de l'eau
- `TranscriptionReunion` : un morceau à la fois, Whisper large v3 turbo, français par défaut, prompt avec les mots du lexique (`PreparationLexique`) + la fin du texte précédent de la même piste, correction à l'oreille. Retentée 5 fois (réseau, 429, 5xx).
- **Budget partagé avec la dictée** : requêtes via `BudgetRequetes.partage` (la réunion n'envoie que si elle laisse la marge de 8 requêtes sur 18 à la dictée ; elle attend sinon, `delaiAvantDePermettre`) ; audio via `BudgetAudio` (5 700 des 7 200 s/heure pour la réunion, 1 500 gardées pour la dictée ; Groq compte 10 s minimum par requête).
- Son brut : en mémoire seulement, jusqu'à la transcription. Réglage « Garder le son des réunions » (désactivé) : deux WAV `*-moi.wav` / `*-eux.wav` à côté de la note, droits 0600.
- Fusion (`FusionPistes`) : classement par heure, « Eux » avant « Moi » à égalité, regroupement des passages d'un même locuteur à moins de 3 s. **Écho** : sans casque, le micro entend les haut-parleurs ; chaque phrase « Moi » qui reprend ≥ 80 % de ses mots (4 mots au moins) d'un passage « Eux » qui chevauche est retirée, le reste du morceau est gardé.

### La note
- Groq `openai/gpt-oss-120b` (le plus gros modèle de `GET /openai/v1/models` le 09/11 ; `qwen/qwen3.8-27b` existe aussi ; réglage `modeleNoteReunion`). Plafond de 8 000 jetons par minute : une longue réunion est lue **par parties** de ~10 000 caractères (une note partielle chacune), puis une note finale ; `BudgetJetons` espace les appels. Réponse en JSON.
- Sections (demande de Hugues) : **Ce qui a été dit** (un point court par sujet), **Ce qui a été décidé** (décisions, choses convenues ou faites), **Ce qu'il reste à faire** (qui, quoi, quand si dit ; cases à cocher), puis **Transcription** repliée. Une section vide est omise. Titre proposé, participants entendus (+ « Moi »).
- **Sans rien inventer** : consigne explicite + garde (`GardeInvention`) : tout nom propre, nombre ou repère de temps de la note doit figurer dans la transcription (orthographe presque pareille ou même prononciation acceptée) ; sinon l'élément (ou le « qui » / « quand ») est retiré et listé au journal.
- Note impossible (réseau, quota) : la transcription est gardée, état « sans note », bouton « Refaire la note ». Réunion sans parole (ou < 3 s) : non gardée.

### Fenêtre et stockage
- Onglet **Réunions** (élément NSToolbar, comme les autres) : liste par jour (heure, titre en Newsreader, durée), recherche, « Noter la réunion ⌥⌘N », ↑↓ ↵ ; la note A : titre modifiable, date/durée, participants, sections, cases à cocher (enregistrées), transcription repliée, Copier, Exporter (Fichier Markdown…, Copier pour Notion = Markdown à coller, Airtable « plus tard »), Effacer (avec confirmation), « Gardé sur ce Mac ».
- Stockage : `~/Library/Application Support/Dictee/Reunions/` (dossier 0700, JSON + Markdown en 0600, `AAAA-MM-JJ_HHMM_id8`), jamais dans git. Une réunion restée « en cours » après un arrêt brutal passe en « sans note » au lancement, transcription gardée. « Désinstaller Verbe » efface ce dossier avec le reste.
- Permissions : micro (déjà), **« Enregistrement du son du système »** (nouvelle ; `NSAudioCaptureUsageDescription` ajouté par `build.sh`, texte du micro mis à jour). Rien d'autre (la détection d'appel est une lecture sans autorisation).

### Vérifié
- `swift run DicteeControles` : 665/665 (fusion, écho, découpe, budgets, note et garde, états de l'encoche, horloge, détection d'appel, Markdown, archive).
- Test de dialogue sans micro : `python3 scripts/dialogue-reunion.py DOSSIER [--echo]` (3 voix `say`, deux pistes alignées, 2 min 09) puis `Verbe --reunion-test DOSSIER/moi.wav DOSSIER/eux.wav [--sortie D] [--sans-note]` (réseau seulement) : 17 morceaux, 0 échec, note correcte, rien d'inventé ; avec écho à −18 dB dans la piste Moi : 20 phrases d'écho retirées, vraie voix gardée. Limite constatée : deux fois le modèle a un peu trop conclu (« livraison prioritaire à Lyon » décidé alors que c'était un souhait) — la garde ne voit que les noms, nombres et repères de temps.
- Détection d'appel testée sur les vrais processus de ce Mac (lecture seule) : l'identifiant d'Aircall est `io.aircall.workspace` (corrigé), Claude, Siri, Terminal, reconnaissance vocale : jamais de proposition ; Zoom et Teams ne sont pas installés ici (identifiants non vérifiés).
- Rendus PNG : `design/rendus-reunions/` (encoche en enregistrement, au survol, en pause, micro seul, proposition, traitement, note prête ; liste, note, transcription, sans note, effacer, vide, petite fenêtre ; panneau compact).

### À vérifier en vrai (par Hugues, app installée) — non testable depuis le shell
1. Première réunion : macOS demande « Enregistrement du son du système » (puis, si besoin, Réglages Système › Confidentialité et sécurité). Pendant un appel réel (Zoom, FaceTime…) : l'encoche montre le point ambre, la minuterie et les deux traces ; la trace du bas (Eux) bouge quand l'autre parle. Après l'arrêt : « Note prête · Ouvrir ».
2. Vérifier dans la transcription que « Eux » contient bien la voix des autres et « Moi » la sienne, avec et sans casque (sans casque : peu d'écho résiduel, quelques mots courts possibles).
3. AirPods : la réunion prend le micro intégré (comme la dictée) ; brancher/débrancher un casque en cours de réunion ne doit pas la couper (reconstruction du micro et du son du Mac, journal « réunion : »).
4. Dicter avec fn pendant une réunion : la dictée marche, la réunion continue.
5. ⌥⌘N depuis une app en plein écran ; survol de l'encoche (ruban Pause / Arrêter) ; Pause puis Reprendre.
6. « Noter cet appel ? » : s'affiche une seule fois par appel, après ~6 s, jamais pendant une réunion ; « Non » la retire.
7. Réunion d'une heure : la note se fait par parties (3-4 min après l'arrêt), quota Groq respecté (journal « en attente de budget »).
8. Export Markdown et « Copier pour Notion » (coller dans une page Notion).
