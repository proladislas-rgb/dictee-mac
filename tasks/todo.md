# App de dictée Mac — todo

Hugues a sauté les questions de conception le 2026-11-09 (« dis-moi ce dont t'as besoin et on y go »).
Les choix par défaut ci-dessous sont ceux de Claude, Hugues peut les changer.

## Priorités de Hugues (2026-11-09)
Le plus rapide possible, le plus optimisé, le plus simple d'utilisation.

## Choix par défaut (Claude)
- App native Swift (SwiftUI + AppKit), icône dans la barre des menus, construite sans Xcode (Swift 6.2 des outils en ligne de commande).
- Garder une touche enfoncée (Fn par défaut), parler, relâcher : le texte s'écrit là où est le curseur, dans n'importe quelle app.
- Transcription : Groq, Whisper large v3 turbo (clé gratuite). Secours : dictée d'Apple intégrée au Mac.
- Remise au propre (ponctuation, « euh » retirés, corrections dites à voix haute) : petit modèle de langue gratuit chez Groq.
- Français + anglais, historique consultable.
- Dictionnaire intégré qui apprend tout seul (demande de Hugues) : mots envoyés à Whisper à chaque dictée, ajout automatique quand Hugues corrige un mot juste après une dictée, import des noms des Contacts.

## Exigences de Hugues (2026-11-09 soir)
- Le texte s'écrit directement là où est le curseur (là où il a cliqué), dans TOUTES les apps : Terminal, barre de recherche Google, documents, mails…
- Mise en forme selon l'endroit : barre de recherche = courte requête sans point final ; Terminal = texte brut, JAMAIS de retour à la ligne final (sinon la commande partirait toute seule) ; Mail/Docs/Notes = paragraphes, listes à puces quand il énumère, « à la ligne » / « nouveau paragraphe » dits à voix haute ; collage en texte riche là où l'app l'accepte.
- Encoche pendant la dictée : texte en direct (aperçu par la dictée Apple, version finale Groq au relâchement), visualisation du son, icône de l'app cible, ✕/✓ en mains libres.

## Design validé (2026-11-09)
- Encoche de dictée : `design/maquettes/encoche-v5.html` (mélange A+C : bande icône d'app + son, ruban de texte en direct soudé dessous ; ✕/✓ en mains libres ; rien au centre = caméra).
- Panneau : STYLE de `design/maquettes/panneau-v3-B.html` (texte dicté en Newsreader, heure en marge, aucun cadre, curseur ambre) — « fais-le comme ça » — en gardant toute la STRUCTURE de l'encoche (le panneau sort de l'encoche, clavier d'abord, cf. panneau-v3-C.html).
- Toujours : commit + push sur GitHub (proladislas-rgb/dictee-mac, privé) à chaque avancée.

## Plan de construction (V1 → V3)
Technique : Swift 6.2 (outils en ligne de commande, pas d'Xcode), paquet Swift + script qui fabrique `Dictee.app`, macOS 26, Apple M5.
- [x] Lot 1 — Squelette : app sans icône Dock, script `build.sh` → Dictee.app signée localement ; écran d'autorisations (micro, accessibilité, surveillance du clavier).
- [x] Lot 2 — Touche fn : tenir = dicter, relâcher = fin, deux appuis = mains libres, Échap = annuler (écoute globale du clavier).
- [x] Lot 3 — Son + Groq : enregistrement 16 kHz mono, envoi par morceaux aux pauses, Whisper large v3 turbo avec le dictionnaire ; dictée Apple si Groq ne répond pas.
- [x] Lot 4 — Collage au curseur : presse-papiers + ⌘V simulé, presse-papiers rendu après, Terminal sans retour à la ligne, champ mot de passe signalé.
- [x] Lot 5 — Encoche v5 en vrai : panneau noir au-dessus de tout, icône de l'app cible, son vivant, texte en direct (dictée Apple sur l'appareil), ✕/✓.
- [x] Lot 6 — Remise au propre + mise en forme selon l'app (petite IA gratuite de Groq : openai/gpt-oss-20b, 1,2 s maximum, garde-fou). Essai réel par Hugues à faire.
- [x] Lot 7 — REPRIS (7a-7d faits le 09/11 ; reste l'essai réel par Hugues : voir « À vérifier en vrai » dans docs/spec-v1.md) selon le design ChatGPT v3 (design/chatgpt-v3/, reçu le 09/11 : « Et tiens avant de faire n'importe quoi ») :
  [x] 7a logo guillemets vectoriel (icône d'app, icône de barre des menus monochrome + trait ambre pendant la capture) et encoche affinée (planches 03 et 06, temps 180-220 ms, fondu 100-140 ms) ;
  [x] 7b panneau compact sous l'encoche (clic sur les guillemets ; style panneau-v3-B ; ↑↓, Entrée recolle dans l'app précédente, copier) + historique enregistré ;
  [x] 7c fenêtre principale Dictées / Mots / Réglages (planches 01-02), raccourcis vocaux ;
  [x] 7d premier lancement en 3 étapes + états vides et d'échec.
- [ ] (ancien) Lot 7 — Panneau (style B, sorti de l'encoche) : dictées, mots, réglages ; historique enregistré sur le Mac.
- [x] Lot 8 — Dictionnaire qui apprend : corrections proposées dans Mots (fait avec le Lot 8 bis), ouverture au démarrage (faite au Lot 7c) ; import des Contacts non fait (autorisation Contacts à demander, décision de Hugues).
- [x] Lot 9 (fait le 09/11 ; essais réels en attente de Hugues, voir spec) — Vraie app à installer / désinstaller (demande de Hugues 09/11 : « je peux pas l'ajouter comme une app que je télécharge, je la supprime ») :
  fichier d'installation Dictee.dmg (glisser dans Applications), icône provisoire en attendant le logo ChatGPT, premier lancement qui demande la clé Groq (rangée dans le Trousseau) et les autorisations,
  menu « Désinstaller Dictée… » qui efface aussi réglages, historique, journal et clé ; versions publiées sur GitHub (Releases). Pas de compte Apple payant (décision de Hugues 09/11) : signature ad hoc stable, mode d'emploi « clic droit › Ouvrir » pour un ami.
- [x] Passage en open source (Hugues 09/11) : sortir docs/etude-apps.md du dépôt (copie dans le second cerveau), remplacer le mail perso des maquettes, licence MIT, historique repris à neuf (sauvegarde locale de l'ancien), dépôt passé en public.
- [x] Lot 8 bis — « Entraînement » (demande de Hugues 09/11 : « l'alimenter avec un dictionnaire… un tas de mots compliqués, dans différentes langues »), fait le 09/11 soir, détail et chiffres dans docs/spec-v1.md (« Lot 8 bis ») :
  [x] 1. lexique local `lexique.json` (jamais dans git) construit par `Verbe --construire-lexique` depuis second-cerveau (sans moi/) et les dossiers de projets ;
  [x] 2. choix des mots pour Whisper à chaque dictée (`ChoixMotsPrompt` : mots.txt devant, puis lexique selon app, titre, texte autour du curseur, historique ; budget 200 jetons) ;
  [x] 3. correction « à l'oreille » après Groq (`CorrectionOreille`, `ClePhonetique`, journalisée) ;
  [x] 4. apprentissage des corrections (`SurveillanceCorrections` : relecture du champ 6 s et 15 s après le collage, propositions dans Mots) ;
  [x] 5. banc d'essai chiffré avant/après (`Verbe --banc-lexique`, `scripts/banc-lexique.sh`, 80 phrases de synthèse en 3 lots : mots du lexique justes 36,5 % → 53,9 %, 0 fausse correction) ;
  [ ] Hugues : essayer en vrai (voir « À vérifier en vrai » du Lot 8 bis dans la spec) ; relancer `Verbe --construire-lexique` de temps en temps (le lexique ne se met pas à jour tout seul).
Chaque lot : construit, essayé pour de vrai sur le Mac, poussé sur GitHub.

## Nom
- 2026-11-09 : l'app s'appelle **Verbe** (choix de Hugues). Garder l'identifiant com.hugues.dictee (autorisations et réglages conservés).
- [x] Premier lancement : détecter la touche 🌐 (AppleFnUsageType ≠ 0), étape guidée avec bouton vers le volet Clavier (pas de defaults write : il ne s'applique pas), relecture chaque seconde, double appui d'essai, ligne discrète dans Réglages (fait le 09/11 ; à vérifier en vrai par Hugues).
- [x] Renommage en Verbe (app, textes, DMG, README, notes, première ouverture corrigée) → version 0.2.0 : `dist/Verbe-0.2.0.dmg` fabriqué et vérifié le 09/11 (identifiant et dossiers internes gardés, voir spec « Écarts »). Aussi dans la 0.2.0 : sons + vibration (réglages séparés), adresses mail/web dictées reconstituées.
- [ ] Publication de la 0.2.0 par Hugues : `gh release create v0.2.0 dist/Verbe-0.2.0.dmg --target main --title "Verbe 0.2.0" --notes-file dist/notes-v0.2.0.md` ; puis réinstallation propre chez lui depuis le DMG (quitter Dictée d'abord) et les 5 points « À vérifier en vrai » de la spec (section Verbe 0.2.0).

## Après Verbe 0.2.0 (décidé le 09/11)
- [x] Notes de réunion DANS Verbe (09/11 soir) : ⌥⌘N, micro (Moi) + son du Mac (Eux, process tap), transcription au fil de l'eau avec budgets partagés, note « dit / décidé / reste à faire » sans invention, onglet Réunions (maquette A), export Markdown, stockage local 0600, proposition « Noter cet appel ? ». Détail et « À vérifier en vrai » : docs/spec-v1.md (« Notes de réunion »).
  - [ ] Hugues : essayer en vrai (autorisation « Enregistrement du son du système », appel réel, AirPods, dictée fn pendant une réunion) — 8 points dans la spec.
  - [x] Présentation v2 (09/11 soir, `reunions-v2`) : liste commune + note B « D'un coup d'œil », « En bref », citations exactes avec heure, échéances en dates réelles, souhait ≠ décision (docs/spec-v1.md, « Présentation v2 »). À vérifier en vrai : « Écouter » (axe de temps des WAV après une pause), qui parle (Moi / Eux seulement).
  - [ ] Plus tard : export Airtable, option « tout sur le Mac » (dictée Apple) au lieu de Groq, suppression d'écho par traitement du signal (aujourd'hui : par le texte), noms des participants Eux.
- [ ] Pistes suivantes à discuter (s'inspirer de l'idée, tout réécrire) : retouche de texte sélectionné à la voix (façon Grammarly), raccourcis tapés (façon TextExpander), historique du presse-papiers dans l'encoche (façon Paste), captures annotées (façon CleanShot X).

## Ordre décidé par Hugues (09/11 soir)
1. Finir Verbe : onglet Journée → 0.3.1 (mise à jour automatique) — onglet Journée CONSTRUIT le 09/11 soir (voir ci-dessous) ; reste la 0.3.1
2. Barre d'outils de l'encoche façon Dynamic Island : la lecture en cours est CONSTRUITE (09/11 nuit, voir ci-dessous) ; reste à l'essayer en vrai
3. CRM WhatsApp de terrain : plus tard, sans se presser

## Résumé de la journée — onglet Journée (09/11 soir)
Choix de Hugues : « C1 avec un mélange du B2 et avec les fonctionnalités du C2 » (maquette `design/maquettes/journee.html`).
- [x] Logique pure `DicteeCore/Journee.swift` : agrégation par heure et par app, moyenne des 14 derniers jours actifs, série, meilleure journée, 7 jours, temps gagné (mots ÷ 40 par min − parole), phrase-bilan par règles (grosse / belle / dans la moyenne / record / calme / en cours / week-end / premier jour / peu de recul / sans dictée), réunions et actions du jour ; 890 contrôles verts.
- [x] `EntreeHistorique.dureeParole` (facultative, anciennes dictées = 0, dit dans le pied de page) enregistrée par `RecordingPipeline.dureeParole` ; limite de l'historique 500 → 3 000.
- [x] Onglet « Journée » (entre Dictées et Réunions) : navigation par jour, phrase en grand, courbe des heures, 3 colonnes (apps avec vraies icônes, réunions + En bref → ouvre la note, À faire cochable et synchronisé), 7 derniers jours + série / meilleure journée / moyenne, pied de page ; clic sur une heure = ses dictées (Recoller / Copier), ← → Échap ; états sans dictée, premier jour, week-end, fenêtre étroite.
- [x] Rendus `design/rendus-journee/` (`Verbe --rendu-journee`), spec dans docs/spec-v1.md (« Résumé de la journée »).
- [ ] Hugues : essayer en vrai (clics, ← →, Échap, cocher une action puis ouvrir la note, durée de parole dans historique.json) — 4 points dans la spec.
- Écarts avec la maquette : les 7 derniers jours sont sous les trois colonnes (ça ne tient plus dans 770 px avec les En bref et 5 actions, la page défile) ; ⌘2 = Journée, Réunions passe en ⌘3 ; « Journée » apparaît aussi dans la navigation du panneau compact.

## Îlot centre d'activités (10/11, branche `ilot-activites`)
Maquette validée en entier par Hugues : `design/maquettes/ilot-activites.html`. Détail, mesures, écarts et « À vérifier en vrai » : docs/spec-v1.md (« Îlot centre d'activités »).
- [x] Lot 1 socle : un seul îlot, trois tailles, priorités, pastille (survol = déplie, clic = échange), la lecture entre dans le système commun, dictée et réunion passent devant tout.
- [x] Lot 2 minuteur (accueil, étendu, pause / +1 min / arrêt, fin = alerte + son réglable + vibration) ; commande dictée « minuteur 10 minutes » seulement si l'accueil de l'îlot est ouvert au début de la dictée.
- [x] Lot 3 rappels locaux et persistants (Fait, Plus tard 10 min, la cloche reste dans l'aile).
- [x] Lot 4 calendrier EventKit (autorisation demandée seulement à l'activation du réglage), 10 min avant / début / étendu avec Rejoindre et Noter la réunion.
- [x] Lot 5 accueil (clic sur l'îlot vide : 4 tuiles).
- [x] Lot 6 notifications : interface + source par l'Accessibilité sur le Centre de notifications, ÉTEINTE par défaut (expérimental, non testable depuis le shell).
- [x] Lot 7 Réglages › Îlot.
- [ ] Hugues : installer et essayer (10 points dans la spec) ; décider si les notifications restent en « expérimental ».
- Limites assumées : le champ « Dire ou écrire » du rappel est vocal seulement (le panneau ne prend jamais le focus) ; réunion et dictée gardent leur encoche (pas dessinées dans l'îlot) ; pas de commande vocale de rappel hors accueil ouvert.

## Lecture en cours dans l'encoche (09/11 nuit, après la 0.3.1)
Maquette validée par Hugues (« c'est très bien, moi j'adore ») : `design/maquettes/lecture-encoche-v3.html` (A + C). Une partie de Verbe, même encoche. Détail, mesures et « À vérifier en vrai » : docs/spec-v1.md (« Lecture en cours dans l'encoche »).
- [x] Source : module natif `Resources/lecture/verbe-lecture.m` (MediaRemote, arm64e + arm64) chargé par `/usr/bin/perl` (`lanceur.pl`), lignes JSON, notifications seulement (0,00 s de processeur en 30 s), commandes lecture / pause / bascule / suivant / précédent / position ; relancé avec délai croissant, abandon silencieux si MediaRemote disparaît ; fabriqué par `build.sh`.
- [x] Logique pure `DicteeCore/LectureEnCours.swift` (lignes JSON, position, temps, trace sonore, libellé de source, site lu dans les titres de fenêtres, couleur dominante, priorités, pause / reprise, relance) : contrôles dans DicteeControles (977 verts au total).
- [x] Îlot (repos : pochette ronde qui tourne ou carrée + onde teintée ; déplié 600 × 228 : trace sonore glissable, ±10 s, lecture-pause, suivant, lueur), bulle pendant la dictée, ressort interruptible, « Réduire les animations », jamais le focus, visible en plein écran ; priorités dictée > réunion > filet > mise à jour > lecture ; pause pendant la dictée et reprise seulement si c'est Verbe qui a mis en pause.
- [x] Réglages › « Lecture en cours » : « Afficher la lecture en cours » + « Mettre en pause pendant la dictée » (activés par défaut).
- [x] Vérifié sans rien montrer à l'écran : `Verbe --lecture-essai` (depuis fondu dans `--ilot-essai` ; 18 contrôles verts avec une source de test à volume 0), `Verbe --lecture-test`, rendus `Verbe --rendu-lecture` → `design/rendus-lecture/`.
- [ ] Hugues : essayer en vrai (YouTube et Netflix dans Chrome, Spotify, pause pendant la dictée, plein écran) — 6 points dans la spec. Le site « YouTube » vient de l'Accessibilité (titre des fenêtres) : non testable depuis le shell.
- [ ] Publication : à décider avec Hugues (README à compléter : la lecture passe par un module chargé par perl, MediaRemote étant fermé aux apps tierces depuis macOS 15.4 ; une future version de macOS peut le couper, la fonction se désactive alors toute seule).

## Étapes
- [x] 1. Étude des deux apps installées avec REA (observer, ne rien copier) (rapport gardé hors du dépôt public)
- [ ] 2. Maquette des écrans → pastille : 3 versions (A fil, B encoche, C curseur) dans ~/Desktop/Dictee-maquettes/pastilles.html, CHOIX DE HUGUES = B l.encoche ; panneau v1 refusé (« trop IA ») → v2 refusé (« trop gros ») → 3 pistes compactes v3-A instrument, v3-B page écrite, v3-C encoche dans ~/Desktop/Dictee-maquettes/, C CHOISI ; encoches de dictée v4 A/B/C prêtes, attente choix
- [ ] 3. Conception courte + plan
- [ ] 4. V1 : touche → enregistrement → Groq → texte collé au curseur
- [ ] 5. Remise au propre, dictionnaire, historique, secours Apple
- [ ] 6. Essai réel par Hugues

## Besoins côté Hugues
- [x] Clé API Groq dans ~/.config/groq/.env (testée 2026-11-09 : 0,45 s pour une phrase, dictionnaire via le champ prompt efficace)
- [ ] Accepter les autorisations micro + accessibilité au premier lancement

## Vitesse, micro, langue (09/11 soir) — fait, à confirmer par les vraies dictées de Hugues
- [x] Envoi anticipé, rognage + FLAC, requête de secours, découpe des longues dictées, remise au propre en avance / par unités, connexion, journal par étape (voir « Vitesse, micro et langue » dans docs/spec-v1.md)
- [x] Micro : moteur reconstruit au changement de micro, garde-fou 0,8 s, réglage Automatique (AirPods)
- [x] Langue : français par défaut, rejet des langues hors liste en Automatique, phrase d'ancrage
- [ ] Hugues : installer, essayer avec les AirPods connectés, dicter vite après une pause de ~0,5 s, dicter 30 s d'une traite, lire le journal (« envoi anticipé réutilisé / jeté », « remise au propre par unités »)

## Filet de sécurité et mots collés (09/11 soir)
- [x] Vibration du trackpad en arrière-plan + sons désactivés par défaut (commit séparé).
- [x] Détection d'échec d'insertion (logique pure `VerificationInsertion`, 29 contrôles), relecture AX à 250/400/650 ms, cible disparue ou non reprise.
- [x] Filet de sécurité : maquette B (design/maquettes/filet-securite.html), `FiletVue` + `FiletPanneau`, rendus design/rendus-filet/, entrée « Dernière dictée » du menu, réglage `filetDeSecurite`.
- [x] Mots collés : suspects testés (aucun ne reproduit « à plus tard » collé), garde-fou `MotsColles`, jonction des morceaux, « a » devant une adresse, ligne de journal « texte Groq → final ».
- [ ] Hugues : essayer le filet en vrai (voir « À vérifier en vrai » à la fin de docs/spec-v1.md) ; si un mot collé réapparaît, relever la ligne « texte Groq → final » du journal.
- [ ] Les contrôles SonSynthese et tasks/lessons.md modifiés par quelqu'un d'autre pendant ce travail ne sont pas dans mon commit.

## Mise à jour automatique (09/11 soir, Verbe 0.3.0)
- [x] Vérification quotidienne de GitHub (releases/latest, sans jeton, limites respectées, hors ligne silencieux), comparaison de versions, choix de l'asset `Verbe-<version>.dmg`.
- [x] Ligne sous l'encoche (Nouveautés / Plus tard / Installer), jamais pendant une dictée ni une réunion ; « Plus tard » = lendemain ; notes de version lisibles.
- [x] Installation : téléchargement, taille + SHA-256 (digest GitHub et fichier `.sha256`), signature, montage en lecture seule, copie à côté, échange atomique avec retour en arrière, quarantaine retirée, relance. Rien n'est remplacé si une étape échoue.
- [x] Réglages › Compte & données › Mises à jour (version, À jour / disponible, Rechercher, Vérifier automatiquement) et entrée « Rechercher les mises à jour… » du menu.
- [x] `release.sh` : fichier `.sha256`, `--version` / `--sortie` pour les faux DMG de test ; logique pure testée dans DicteeControles ; modes `--verifier-mise-a-jour`, `--installer-mise-a-jour-test`, `--rendu-mise-a-jour`.
- [ ] Publication de la 0.3.0 par Hugues : `./release.sh` puis `gh release create v0.3.0 dist/Verbe-0.3.0.dmg dist/Verbe-0.3.0.dmg.sha256 --target main --title "Verbe 0.3.0" --notes-file dist/notes-v0.3.0.md` ; la mise à jour se verra à la 0.3.1 (publier une 0.3.1 de test, ou la prochaine vraie version, et essayer depuis la 0.3.0 installée : voir « À vérifier en vrai » de la section « Mise à jour automatique » de docs/spec-v1.md).

## Précision de la transcription (10/11, branche `precision`)
Demande de Hugues : mieux transcrire (« un peu meilleurs sur la transcription » chez Wispr Flow), sans rien perdre en fluidité ; choix turbo / précis visible ; apprentissage automatique.
- [x] 1. Modèle Whisper réglable (Rapide turbo / Précis large-v3), défaut **Précis** (justesse 91,9 % contre 86,2 %, latence dans le bruit, quota gratuit à part), repli turbo sur 429 / panne et requête de secours en turbo, budget de requêtes par modèle, latences mesurées affichées dans Réglages (docs/spec-v1.md, « Précision de la transcription »).
- [x] 2. Relecture de sens (qwen3.8-27b sans raisonnement, ≤ 250 ms, ou fusionnée à la remise au propre), garde-fou strict, journal ; modèles de langue de secours (gpt-oss-20b était à sec : 200 000 jetons par jour) ; `--declencheurs` mesure le taux de déclenchement (15 %).
- [x] 3. Expressions personnelles automatiques (une fois par jour depuis l'historique, onglet Mots › Tes expressions, prompt Whisper dans 45 jetons) + corrections apprises seules à la 2e occurrence + ligne « appris cette semaine ».
- [x] 4. Test sur la vraie voix : réglage « Garder le son des 50 prochaines dictées… » (désactivé), `Verbe --comparer-precision`.
- [ ] Hugues : activer le test de précision et dicter 50 dictées, puis lancer `Verbe --comparer-precision` ; essayer en vrai (5 points « À vérifier en vrai » de la spec).
- [ ] À surveiller : la remise au propre coûte ~1 000 jetons par dictée (200 000 par jour et par gpt-oss) ; raccourcir la consigne ou garder qwen en 3e secours si les 429 reviennent.

## Îlot Apple Pro (10/11 soir)
Hugues : « il déconne, c'est horrible », « je retrouve pas du tout l'expérience Dynamic Island ». Cible au pixel et à la milliseconde : `design/maquettes/ilot-pro-A.html` (gagnante du jury) + greffes de B (cou étroit, accueil en liste, mini-miniature 16:9 dans l'aile, rappel titre puis heure, fond clair dans les rendus).
- [x] 1. Forme (DicteeCore) : 7 valeurs comme la maquette (cou, corps, hauteur, épaule, coin bas, coin haut du corps, congé), coins continus (portée 1,6 r, poignées 0,18), corps qui s'élargit dès qu'il existe sous la barre (plus de couplage largeur/hauteur tardif), ressorts avec attente (largeur puis hauteur à l'ouverture, hauteur puis largeur à la fermeture).
- [x] 2. Moteur : ressorts de la maquette (ouverture 0,40/0,80 et 0,48/0,75, alerte 0,38/0,74 et 0,46/0,70, fermeture hauteur 0,42 s et largeur 0,32 s, sans rebond), horloge d'animation pour le contenu (arrive 0,12 s après la forme, 35 ms par bloc ; part avant la forme), boucle calée sur l'écran (CADisplayLink), « Réduire les animations » lu en direct (fondu 0,15 s).
- [x] 3. Contenu : un arbre par activité sur une grille (marge 16 pt, mesurée sur la vraie caméra), la pochette et l'anneau du minuteur voyagent ; titre + source, barre fine teintée, boutons nus centrés ; égaliseur 5 barres (Core Animation) ; suppression des étiquettes, du liseré, des lueurs, des tuiles colorées et des disques.
- [x] 4. Pastille qui « goutte » sous la barre (métaballe pendant la chute), accueil en liste à filets fins.
- [x] 5. Contrôles : `swift build -c release`, `swift run DicteeControles`, rendus (titre très long, 16:9, carré, sans image, caméras 179 et 200, fond clair et sombre, mi-course), `--ilot-essai`.
  → 1 310 contrôles verts, `--ilot-essai` 58/58, 52 rendus dans design/rendus-ilot (5 Mo). Écarts voulus avec A : fermeture d'un seul tenant (pas de bandeau plat), cou de la lecture = cou du repos (caméra + 44), pastille plus grande (13 pt), boutons « +1 min » et « suivant » gardés.
- [x] Le vide de la fenêtre (à côté du cou, marge du compact) laisse passer les clics vers les menus.
- [ ] Hugues : essayer en vrai (point 11 de « À vérifier en vrai » de la section Îlot de docs/spec-v1.md). Non vérifié d'ici : le rendu animé réel à l'écran, le passage des clics à travers la fenêtre, le pont liquide de la pastille en mouvement.
- [ ] Plus tard (non fait) : retirer une lecture en pause depuis longtemps ; survol filtré selon la vitesse de la souris.

### Revue de l'îlot Apple Pro (10/11, nuit)
- [x] Bandeaux et alertes : le corps épouse le contenu (mesuré), « Fait » centré, plus de vide à droite (`GeoIlot.corps`, `IlotAnnonces.swift`).
- [x] Rendez-vous déplié : corps à la largeur du contenu, pilules de même largeur jusqu'à la marge.
- [x] VoiceOver : le temps restant du minuteur est lu avec sa valeur.
- [x] Détails : pastille alignée à droite sur le cou (rappel : titre au survol), calendrier au trait, « suivant » sur la marge, fermeture largeur devant, ressorts partagés moteur/contrôles (`PassageIlot`), aile du rendez-vous « 1 min » au lieu de « maintenant », titre défilant ≤ 20 s, cloche qui se resecoue, saut 16:9 animé, pictogramme sans image à l'échelle, ombre sous la barre seulement, heure morte de l'accueil retirée, spec remise d'accord.
- [ ] Non fait : `minuteurMinimal` reste un écran sans arbitrage (le retirer touche l'énumération et les rendus, sans gain visible) ; la mi-fermeture reste un bandeau bas (la cible compacte fait elle-même 2 × (caméra / 2 + 44) pt de large).

## Plus tard — idées de l'îlot (Hugues 10/11 soir : « on fera ça plus tard, il y a déjà des choses dessus »)
- [ ] « Garder éveillé » ☕ dans l'îlot : 5e tuile de l'accueil (2 h / 4 h / ∞), tasse + temps restant dans l'aile, écran fermé compris (`pmset disablesleep` via règle sudoers limitée, `displaysleepnow` à la fermeture) ; veille TOUJOURS rendue si Verbe quitte ou plante ; option « tant que Claude ou Codex travaille ». Inspiration : LidAwake (sans licence → tout réécrire).
- [ ] Réveils et minuteurs de l'app Horloge d'Apple affichés dans l'îlot (lecture seule, base `group.com.apple.mobiletimerd/local.sqlite`, non officiel).
- [ ] Commande dictée « réveil / minuteur / réveille-moi à 9 h » (aujourd'hui seules les durées sont comprises) ; idéalement créer le vrai réveil dans Horloge via Raccourcis (à vérifier).
- Maquette d'abord (tasse + réveil + phrase), puis construction.

## Minuteur pendant une lecture — « La bulle » (11/11, reprise de Hugues = go sur la recommandation)
Maquette : `design/maquettes/apple-acces/1-controles.html`. Hugues ne trouvait pas les minuteurs : l'accueil ne s'ouvre que sur l'îlot vide.
- [x] 1. Cœur : écran `lectureMinuteur` (lecture dépliée + 54 pt de rangée Minuteur), même largeur que `lectureEtendu`.
- [x] 2. Moteur : appui long 0,4 s sur la lecture → rangée ; la lecture déjà dépliée ne s'efface pas (seule la rangée arrive) ; la pochette ne bouge pas.
- [x] 3. Vue : rangée de l'accueil (5 / 10 / 25 min, « En cours · 4:12 » si un minuteur tourne) ; l'îlot gonfle sous le doigt.
- [x] 4. Clic sur une durée : l'îlot se replie, le minuteur part dans la pastille (pas de bandeau).
- [x] 5. « minuteur 10 minutes » dicté pendant que la lecture est dépliée.
- [x] 6. Titre qui défile : fondu à gauche pendant le défilement (coupé net : « OUPLE FAIT… »).
- [x] 7. Contrôles + essai + rendus, relecture par un agent (3 défauts corrigés : bond de la pochette au repli, appui resté en plan pendant une dictée, appui long pointeur parti ; + action VoiceOver), installation dans /Applications, push.
  → 1 369 contrôles, `--ilot-essai` 77/77 (vrais clics : court, appui long, « 25 min »), rendus `ilot-1n*`.
- [ ] Hugues : essayer en vrai (garder le clic sur l'îlot pendant une vidéo). Non vérifié d'ici : le geste avec un vrai trackpad, le fondu du titre en mouvement.

## Îlot « à la Apple » (11/11, go de Hugues : « c'est très bien, on va partir sur ça ») — maquette design/maquettes/ilot-apple.html
- [x] 1. Bulle à côté : la pastille quitte le dessous de la barre et se pose À DROITE de l'îlot, même hauteur, accrochée au haut de l'écran (fente de 11 pt), elle sort de l'îlot en glissant (pont liquide horizontal) ; survol : elle s'ouvre vers la droite ; clic = échange
- [x] 2. Épaules au survol : dès qu'un écran est déplié (cou porté à 60 pt), batterie du Mac à gauche, AirPods à droite (l'onde de la lecture laisse la place s'ils sont là) ; minuteur de la lecture dépliée : pause + arrêt ronds
- [x] 3. AirPods (ou souris, clavier) qui se connectent : bandeau 3 s, nom, « Connectés », jauges gauche / droit / étui (IOBluetooth, sélecteurs batteryPercent*, non documentés)
- [x] 4. Énergie : chargeur branché = « En charge » + 33 % vert 3 s ; batterie 20 % puis 10 % = « Faible » rouge, une fois par seuil (IOPowerSources, notification, pas de sondage)
- [x] 5. Réglage « Batterie et appareils » (Réglages › Îlot), NSBluetoothAlwaysUsageDescription dans l'Info.plist
- [x] 6. Contrôles (géométrie, bulle, épaules), essai îlot, rendus comparés à la maquette, relecture par un agent, installation, push
- [ ] Hugues : essayer en vrai (bulle à côté pendant une vidéo + minuteur, survol = batterie et AirPods, brancher le chargeur, connecter les AirPods ; macOS demande une fois le Bluetooth). Non vérifié d'ici : la batterie de vrais AirPods (méthodes non documentées).

## Les 5 idées en plus, à la suite (11/11, Hugues : « fais les 5 à la suite… pouvoir scroller… optimisé, fluide, cohérent avec l'UX de mon Mac »)
MAQUETTE D'ABORD (Hugues montre la maquette concept 3 « Spotlight » : « les propos de cette maquette sont excellents ») : `design/maquettes/ilot-cinq.html`, les 5 à la suite sur une page qui défile, chacune jouée étape par étape sur un vrai écran ; construction dans Verbe après son choix.
Ancienne lecture (gardée si Hugues la confirme) : l'îlot ouvert devient une pile de cartes qu'on fait défiler à deux doigts (trackpad), comme une pile de widgets, points de page à droite ; le contenu suit le doigt, puis se cale avec un ressort.
- [ ] A. Pile de cartes : défilement à deux doigts sur l'îlot ouvert (accueil, activité, nouvelles cartes), points de page, élastique aux bouts, « Réduire les animations » respecté
- [x] B. Téléchargé : un fichier qui arrive dans Téléchargements (AirDrop compris) → bandeau 4 s (icône, nom, taille, « Ouvrir ») ; carte des derniers téléchargements (glisser vers une app)
- [x] C. Claude au travail : crochets de Claude Code (~/.claude/settings.json, fusion sans rien écraser) → fichier d'état → l'îlot montre la tâche, « 3 sur 7 », « Terminé », « Attend ta réponse »
- [x] D. Micro coupé : raccourci global (réglable), micro d'entrée coupé (CoreAudio), activité rouge dans l'îlot tant que c'est coupé ; la dictée fn le rouvre le temps de dicter
- [x] E. Volume et luminosité : les touches du clavier s'affichent dans l'îlot (barre) à la place de l'affichage du système
- [x] F. Étagère : glisser des fichiers sur l'encoche → ils y restent (carte Étagère), on les reprend en les glissant
- [x] Pour chacun : contrôles, essai, rendus, relecture, installation, push (équipe : 65f702a f5e0951 84ba865 f8d243f e7da86f, relecture bbf4bda ; installé 11/11 14 h)
- [ ] Hugues : essayer en vrai (⌃⌥M, touches volume/luminosité, Réglages › Téléchargements à allumer, « Brancher Claude Code », glisser un fichier sur l'encoche). Non vérifiés d'ici : vrais gestes clavier/souris.
- [x] (Hugues 11/11 ~11 h, capture) Épaule batterie : « 100… » tronqué et l'icône verte avec éclair « pas dingue » → pile dessinée façon iPhone : le pourcentage DANS la pile (chiffres découpés), remplissage blanc / vert en charge / rouge ≤ 20 %, petit éclair à côté si branché ; ~34 pt, plus jamais tronqué. À faire APRÈS l'équipe (elle travaille sur main, ne pas compiler en même temps).
- [x] (11/11 12 h 20) Micro avec AirPods : micro du Mac ouvert directement (EntreeHAL, d109a59), correctif installé seul (sur dcc62db). VÉRIFIÉ par Hugues à 12 h 57 (« ça marche, très agréable »), premier son en 48 ms. Était : À VÉRIFIER dans le journal à la prochaine dictée avec AirPods (« micro direct « Micro MacBook Air » » puis « premier son »).
- [ ] Même défaut possible dans les notes de réunion (MicroReunion.swift impose aussi un micro via AVAudioEngine) : passer à EntreeHAL
- [x] (Hugues 11/11 : « je veux que les deux soient possibles ») Micro du Mac OU des AirPods : déjà dans Réglages › Micro ; ajouter un choix rapide dans l'îlot quand des AirPods sont connectés (ligne « Micro : Mac / AirPods » dans l'accueil et touche sur l'épaule AirPods), après l'équipe

## Centre dans l'îlot (11/11 ~14 h 30, Hugues : « ça marche pas du tout… plus clair, plus utilisable, plus simple » ; « il faudrait que tout soit disponible depuis le Dynamic Island, juste je garde la touche fn pour la dictée » ; « je peux pas slider »)
- [ ] Maquette animée design/maquettes/ilot-centre.html (en cours) : survol → lecteur ; passage au Centre par points cliquables / onglet visible (défilement en bonus) ; tuiles façon Centre de contrôle (Micro coupé, Micro Mac/AirPods, Minuteur, Étagère, Téléchargements, Claude) ; plusieurs actions d'affilée sans que l'îlot se ferme ; « Modifier » pour ajouter/retirer des tuiles ; AUCUN raccourci clavier sauf fn
- [ ] Après validation : construire, retirer ⌃⌥M (ou l'éteindre par défaut), autorisations demandées au premier clic dans l'îlot
- [ ] (Hugues 11/11 14 h 45, capture du panneau ❞) Le panneau de la barre des menus DANS l'îlot : bouton « Noter la réunion » dans le Centre + 3e carte « Dictées » (recherche, dernières dictées, clic = copier, Coller, déplier, liens Journée/Réunions/Mots/Réglages) ; l'icône ❞ de la barre disparaît. Maquette (ilot-centre.html, 13 étapes) VALIDÉE (« dingue, c'est parfait ») ; construction juste après l'équipe du Centre.

## Ensuite : grande passe de qualité (Hugues 11/11 : « une optimisation de tout pour que tout soit vraiment parfait, qu'il n'y ait jamais de bug, clean, que ça respecte la confidentialité des gens »)
- [ ] Audit complet (équipe) : bugs, performances/batterie, mémoire, plantages, confidentialité (ce qui est lu, gardé, envoyé : Groq, journaux, historique, crochets Claude, signets étagère, quarantaine Téléchargements), sécurité, simplicité de l'interface ; corrections ; puis publication d'une version
- [x] (11/11 17 h 45) Clics/défilement volés sous l'îlot (Chrome) : correctif installé (branche correctif-clics, depuis e1af186) ; À FUSIONNER dans main après l'équipe Dictées
- [ ] (Hugues 11/11 ~18 h : « c'est pas mal. C'est parti ») Étagère plus rapide, maquette design/maquettes/ilot-etagere-rapide.html : cible « Glisse ici » dès le début du glisser, deux zones Étagère / AirDrop, compteur dans l'aile, fichiers en haut du Centre au survol, « Tout » + Remettre, option captures d'écran. À construire après l'équipe Dictées.
- [ ] (Hugues 11/11 ~18 h 30 : « c'est excellent… je valide tout ») Maquette design/maquettes/ilot-claude-plus.html : A) Claude (nom de tâche dans l'îlot replié, badge sessions, carte Claude par session avec liste cochée, bandeau question, « Terminé » détaillé) ; B) page « Outils » du Centre : Garder éveillé, Presse-papiers (5 derniers, local), Reformuler (Plus pro / Plus court / En anglais, Remplacer), Note rapide (fn, Vers Notes). Corriger au passage : épaules du déplié ≤ 66 pt (56 + congé 10). À construire après l'étagère.
- [x] (11/11 soir) INTÉGRATION faite dans main (sans pousser ni installer) : etagere-rapide puis claude-outils fusionnées ; pile activité → Centre → Outils → accueil → Dictées ; en-tête du Centre : « Outils › », « Dictées », « Modifier », l'épingle seule si « Reste ouvert » ne tient pas ; géométrie : cou droit (une aile) ET borne des 66 pt. Reste : l'ONGLET du Terminal pour « Ouvrir » (ligne plus bas), installer après validation.
- (11/11 18 h 15, Hugues : « bombarder à fond ») EN PARALLÈLE : équipe Dictées (main), workflow verbe-etagere-claude (copies wt-etagere / branche etagere-rapide et wt-claude / branche claude-outils dans le scratchpad). Puis INTÉGRATION : fusionner correctif-clics, etagere-rapide, claude-outils dans main, résoudre, tout revérifier, installer.
- [ ] (Hugues 11/11 ~18 h 45 : « c'est lourd à mort… tout est bien ») Maquette design/maquettes/ilot-bibliotheque.html : Bibliothèque (carte + onglet de la fenêtre), Réveil, bouton Calendrier + Rejoindre. Équipe lancée en parallèle (copie wt-biblio, branche bibliotheque). Rappel de Hugues : ne RIEN retirer du Centre en intégrant (il a cru que des choses avaient disparu) : le Centre final réunit tout.
- [ ] (Hugues 11/11 18 h 42 : « les rappels… ça ne marche pas… tout optimisé, clean à la Apple ») Le rappel « Appelez Ladislas » (demain 15 h) EST bien enregistré dans Verbe, mais seulement dans Verbe : rien dans l'app Rappels ni sur l'iPhone, et « Appelez » au lieu de « Appeler ». À faire dans la passe de qualité : rappels synchronisés avec l'app Rappels d'Apple (EventKit, autorisation au premier rappel, liste « Verbe » ou liste par défaut), visibles sur l'iPhone ; texte du rappel remis à l'infinitif ; confirmation visible dans l'îlot (« Rappel ajouté · demain 15:00 »).
- [ ] (Hugues 11/11 ~18 h 50 : « il faut que je fasse appel à un mot précisément ou pas ? ») Commandes dictées plus naturelles : aujourd'hui seulement si l'îlot est ouvert au début de la dictée + phrase qui commence par « rappelle-moi » / « minuteur » (ou « Dire un rappel » puis la phrase seule). Proposé : « Verbe, … » en tête de phrase marche PARTOUT (îlot fermé, n'importe quelle app) ; tournures naturelles (« crée-moi un rappel », « mets un rappel », « ajoute un rappel », « réveille-moi », « minuteur de 10 min ») ; sans « Verbe », seulement îlot ouvert (pour ne jamais transformer une phrase d'un mail en rappel). VALIDÉ par Hugues (« ça c'est bien ça »), à faire dans la passe de qualité.
- [x] (12/11, branche second-cerveau-ilot, À INTÉGRER dans main : FAIT, voir docs/second-cerveau-ilot.md) Une case « Second Brain » dans l'îlot (l'app a été renommée ; ancien texte : « Second cerveau ») (au lieu de son icône cerveau dans la barre des menus) : aperçu (« Pierre t'a écrit · 3 choses demandées », nombre de choses « à toi » aujourd'hui, prochaine relance) + clic qui ouvre l'app. Côté Verbe : prévoir un emplacement pour une app locale tierce, lecture d'un fichier d'état (ex. ~/.config/second-cerveau/ilot.json). RIEN maintenant ; prévenir Hugues / OU-J-EN-SUIS quand l'îlot pourra l'accueillir (après intégration + passe de qualité). Maquette design/maquettes/ilot-second-cerveau.html VALIDÉE par Hugues (« très bien, c'est très bien »). À la construction : case plus compacte ou page à part pour ne pas pousser Minuteur/Étagère sous le pli.
- [ ] (11/11 soir) NOUVEAU NOM : « Lucarne » (Hugues : « choisis le nom le plus cohérent, le plus simple, le plus agréable… comme Apple, Microsoft » ; Dictora écarté : pris sur l'App Store + Dictura, app de dictée au même geste). Aucune app ni marque logicielle « Lucarne » trouvée en ligne ; vérification officielle EUIPO / INPI (classes 9 et 42) À FAIRE avant l'annonce. Adresses libres : getlucarne.app, getlucarne.com, lucarne-app.fr. Renommage à faire après l'intégration : nom de l'app, Info.plist (CFBundleName/Display), textes, README, dépôt GitHub (renommer ou garder dictee-mac ?), DMG, vidéo.
  - [ ] (12/11 matin) « Lucarne » EST ORANGE-ROUGE : un éditeur photo Mac (lucarneapp.com) et un outil GitHub pour Claude Code (tuchg/Lucarne, 344 étoiles) portent ce nom. Nouvelle recherche faite (180 noms vérifiés à deux chercheurs) → page `~/Desktop/📁 Projets/Verbe/Verbe-nom/noms-v2.html` : Luette (favori, tout libre), Canif (orange), Javeau, Vasistas, Dictile, Inis. EN ATTENTE du choix de Hugues ; ensuite marques (liens dans la page) et essai du nom à la dictée, puis renommage.
- [ ] (11/11 soir) ICÔNE choisie par Hugues : bonus « Lucarne » (l'île vue à travers une petite fenêtre arrondie), ~/Desktop/Verbe-icone/v2/svg/l-lucarne-{light,dark}.svg et png 1024. À intégrer au renommage (AppIcon.icns, variantes claire/sombre macOS 26).
- [ ] (Hugues 11/11 19 h 27, capture du minuteur déplié) « il faudrait que je puisse revenir directement à ce qui était affiché précédemment… sur le Centre » : l'îlot se rouvre sur la DERNIÈRE carte quittée (Centre, Dictées…) pendant ~10 min, avec « ‹ Minuteur / Vidéo » pour revenir à l'activité ; au-delà, il rouvre l'activité. À faire à l'intégration.
- [ ] (Session Second cerveau, 11/11 19 h 20) ÉNERGIE : Verbe au repos mesuré à 6,4 % de CPU en moyenne (pointes 19,6 %), impact énergie 6,4, ~108 Mo, Deezer ouvert, pas de dictée. Viser ~0 % au repos : traquer ce qui tourne en continu (lien d'écran / boucle à 60 Hz, onde de la musique îlot replié, sondages, moniteurs souris/trackpad, minuteries), animations seulement îlot visible et déplié, minuteries coalescées. Priorité de la passe de qualité (Hugues a déjà désinstallé un outil pour ~2 s de CPU / 5 s).
- [ ] Vidéo promo v2 (Lucarne, icône bonus Lucarne) MISE EN PAUSE le 11/11 ~19 h 40 à la demande de Hugues (RAM chargée) : travail gardé dans ~/Desktop/Verbe-promo/v2/ (film, marque, outils, projets) ; reprendre plus tard avec un nouvel agent qui part de là.
- [ ] (Hugues 11/11 20 h 30 : « l'interface de réunion… c'est horrible… le Dynamic Island n'est plus utilisable, la transcription est à chier… fais la même chose que Wispr Flow ») Refonte des réunions façon Wispr Notetaker : maquette design/maquettes/ilot-reunion.html en cours (îlot utilisable pendant la réunion, transcription en direct propre, « Ce que j'ai raté », note après : résumé par sujets, décisions, prochaines étapes par personne, transcription retravaillée avec noms et heures, « Demander »). Construction après validation.
- [x] (11/11 20 h 35, installé 9bc4a72) Énergie 1re passe : appels détectés par notification audio (plus de sondage 2 s), surveillance des autorisations arrêtée quand tout est accordé, Journée recalculée seulement à l'écran ; micro de réunion direct (AirPods). Mesure : 6,4 % → 2,5 % moyen au repos (pointe 9 %). Reste à trouver (passe de qualité).
- [ ] (11/11 ~21 h) Maquette ilot-reunion.html VALIDÉE (« très bien pour ce visuel ») : équipe lancée (copie wt-reunion, branche reunions-wispr). Séparation des voix : question posée à Hugues (recommandé : FluidAudio, local, gratuit).
- [ ] (Hugues 11/11 ~21 h 15 : « oui pars sur FluidAudio ») Séparation des voix des réunions avec FluidAudio (Swift, CoreML, sur le Mac) : seulement APRÈS la réunion pendant « Note en préparation » ; modèles téléchargés au premier usage (pas dans l'app) ; mesurer temps et mémoire sur une réunion de 30 min ; orateurs renommables. À faire par un développeur après l'équipe Réunions (même branche).
- [ ] GitHub à remettre à jour après intégration + renommage Lucarne : README (ce que fait l'app, captures, vidéo promo intégrée), nouvelle version publiée (DMG), vidéo en pièce jointe de la version ou intégrée au README (fichier ≤ 100 Mo, sinon via la version).
- [ ] (Hugues 11/11 ~21 h 20) MANUEL VISUEL simple pour les utilisateurs de Lucarne : une page par geste (dicter avec fn, l'îlot, le Centre, Dictées, Claude, étagère/AirDrop, bibliothèque, outils, réveil/visio, réunions, réglages, confidentialité), captures RÉELLES de l'app finale (rendus --rendu-ilot), phrases courtes ; en HTML (docs/manuel, lié depuis le README et ouvert depuis l'app « Aide ») + PDF. À faire après intégration + renommage, avec la mise à jour GitHub.
- [ ] (Hugues 11/11 ~21 h 30 : « quand j'ouvre la notif Claude a fini, ça ouvre souvent la mauvaise conversation ») Hugues a PLUSIEURS ONGLETS dans UNE fenêtre du Terminal (titres « ✳ <titre de session> — … • claude ») : « Ouvrir / Voir » doit choisir le bon ONGLET (Accessibilité : AXTabGroup → bouton d'onglet dont le titre contient le titre de la session, AXPress), pas seulement la fenêtre. La branche claude-outils (f265f74) choisit la bonne fenêtre par titre : compléter par l'onglet à l'intégration ; essai avec un Terminal factice.

## Claude Code en carte (11/11, maquette design/maquettes/ilot-claude-plus.html étapes 1 à 7, « je valide tout ») — branche claude-outils
- [x] Replié : l'étoile dans son anneau, « 3/7 » (anneau seul si « 12/14 » ne tient pas), petit « 2 » quand deux sessions travaillent, le NOM de la tâche « in_progress » (sinon le titre de session de Claude Code) qui défile (une animation Core Animation, rien quand le nom tient) ; ambre « second-cerveau attend ta réponse » quand une session attend
- [x] Bouton Claude du Centre : « 2 au travail » / « Attend » / « Prêt » (« Brancher » tant que non branché) ; un clic ouvre la carte « Claude Code »
- [x] Carte : un bloc par session (projet, état, depuis, « 3 sur 7 », tâches cochées / en cours en gras / à faire), « Ouvrir » ramène la bonne fenêtre du Terminal (Accessibilité déjà accordée, pas d'AppleScript), défile au-delà de la hauteur du Centre, la session qui attend en haut (cadre ambre, question) ; survol = carte quand une session attend
- [x] Bandeaux : « <projet> attend ta réponse » + premiers mots du message de notification (traduit si connu) + « Ouvrir » ; « <titre> terminée » + « projet · 42 min · 7 tâches sur 7 » + « Voir » (fenêtre du Terminal)
- [x] Script des crochets : + message (Notification) + session_title (UserPromptSubmit), jamais « prompt » ; remplacé tout seul au lancement si branché (ancien gardé en .verbe-sauvegarde), settings.json non touché
- [x] Épaules : borne dans TraceIlot (cou cède au congé : 66 pt au plus, même pendant les passages ; mesuré 66,83 sans la borne)
- [ ] Hugues : essayer en vrai (deux Terminaux avec Claude, une autorisation demandée, « Ouvrir » sur la bonne fenêtre). Non vérifié d'ici : la lecture réelle des fenêtres du Terminal par l'Accessibilité (titre, document) et le défilement à l'écran.
- (11/11 ~22 h 30) Réunions : Hugues ne veut pas forcément d'un modèle Whisper sur son Mac → on GARDE Groq pour la transcription des réunions ; Whisper local seulement en option plus tard si les limites de Groq gênent. FluidAudio (séparation des voix, petits modèles) reste prévu.
- [x] (Hugues 12/11 00:16) « Captures d'écran ici » allumé, aucune capture sur l'étagère : les captures GLISSÉES depuis la vignette flottante (dans le Terminal) ne vont jamais dans le dossier des captures, macOS les laisse dans …/T/TemporaryItems/NSIRD_screencaptureui_X/. Ce dossier temporaire est maintenant surveillé aussi (sans autorisation) ; glisser annulé = la copie du dossier des captures remplace la glissée. Branche correctif-captures.
- [ ] (12/11) Second Brain dans l'îlot, reste à faire (maquette ilot-second-cerveau.html) : aile gauche (signe + badge) et bulle pendant une vidéo, bandeau « Camille t'a écrit », page « D'où viennent ces infos » avec ses trois interrupteurs ; à décider avec Hugues après l'avoir vu en vrai (fait : rond dans le Centre + carte rangée sous le Centre, pour ne pas pousser Minuteur et Étagère).
- [ ] (11/11 23 h 30, Hugues) Équipe « simplicité » lancée sur main (workflow verbe-simplicite) : AirDrop honnête (« Envoi lancé », « Annulé »), micro coupé = fn ne rouvre plus en douce (« Rouvrir et dicter »), note rapide au clic (+ « En faire un rappel »), « Lucarne, … » partout + rappels naturels (« livraison demain vers 13-14 h »), rappels dans l'app Rappels, aide au survol des boutons. La vidéo v4 et la future app Lucarne doivent rester COHÉRENTES avec ces corrections (consignes envoyées à l'agent vidéo).
  - [x] (12/11) AirDrop honnête : didShareItems = appareil choisi, jamais la fin du transfert → « Envoi lancé vers AirDrop » (flèche bleue, pas de coche) ; annulation (même après le choix) → « Annulé » ; un fichier envoyé par AirDrop reste sur l'étagère (aussi glissé depuis l'étagère sur le panneau AirDrop, extension com.apple.share.AirDrop.send) ; lâcher en passant (< 0,4 s) → étagère.
  - [x] (12/11) Micro coupé = coupé : fn sur un micro coupé ne démarre rien (aucun son capté, aucun son joué), bandeau « Micro coupé · Rien n'a été enregistré » + « Rouvrir et dicter » (6 s, s'affiche même sur le Centre épinglé) ; dictée sur un AUTRE micro ouvert : elle part, puis « Le micro des AirPods est coupé · Verbe dicte avec le micro du Mac » (une fois par coupure) ; texte du réglage mis à jour.
  - [x] (12/11) Aide au survol : une phrase par bouton rond et par case du Centre et des Outils (ElementCentre.aide), bulle sobre après 0,5 s, sous le rond ou au-dessus de la case/bande, ne prend aucun clic, part au clic et pendant « Modifier » ; « Noter la réunion » n'en a pas (elle le dit déjà en toutes lettres). Rendus ilot-19h/19i, 24h/24s, 26a–26g.
  - [ ] Hugues : essayer en vrai (annuler le panneau AirDrop, fn micro coupé, survoler les boutons). Non vérifié d'ici : le survol par un vrai pointeur (les événements fabriqués n'atteignent pas onHover : survol posé à la main dans l'essai), la réponse réelle du panneau AirDrop.
  - [x] (12/11, 2e agent) Note rapide au clic : « Dicter une note » (grand bouton de la carte, et la bande de la page Outils) commence l'écoute dans la carte, sans encoche de dictée (« J'écoute… », le rond qui suit la voix, le texte en direct, « Terminé ») ; 2 s de silence après la voix l'arrêtent (8 s sans un mot, 2 min au plus) ; « J'écris la note… » ; jamais collée ; « Je n'ai rien entendu, réessaie » ; fn reste possible carte ouverte (la page Outils ne transforme plus fn en note). Une note qui dit un jour ou une heure propose « En faire un rappel · demain 13:00 » dessous (un clic). Rendus 25l–25p.
  - [x] (12/11) « Lucarne, … » (et « Verbe, … », « Lucarnes », « L'ucarne », « Lu carne », « La carne ») en tête de dictée = commande, îlot ouvert ou fermé, jamais collée ; rappels naturels (crée-moi / mets / ajoute un rappel, rappelle-moi, n'oublie pas que, fais-moi penser à, j'ai une livraison demain vers 13-14 h → « Livraison » demain 13:00 ; demain, après-demain, lundi, ce soir, demain matin, le 20 novembre, midi et demi, dans 20 min, 13-14 h, entre 13 et 14 h) ; texte à l'infinitif (« Appeler Ladislas ») ; minuteur ; « réveille-moi à 7 h » = rappel « Réveil » (pas de réveil sur main) ; rien de reconnu → « Je n'ai pas compris » + la phrase + « Copier » ; rappel sans heure → « Il me manque l'heure ». Sans le mot d'appel : comportement inchangé. près de 80 contrôles de phrases et de pièges (DicteeControles, ControlesLucarne.swift). Rendus 27a–27d.
  - [x] (12/11) Rappels aussi dans l'app Rappels (EventKit, liste par défaut, échéance + alarme à l'heure) : question dans l'îlot au premier rappel (« Aussi dans l'app Rappels ? » Non / Oui), fenêtre de macOS seulement après « Oui » ; « Non » ou refus : « Tes rappels restent ici », dit une fois ; « Fait » coche là-bas, « Annuler » supprime, « Plus tard » déplace ; coché sur l'iPhone avant l'heure → ne sonne pas sur le Mac ; un seul double par rappel. NSRemindersFullAccessUsageDescription dans build.sh. Rendus 27e–27g.
  - [x] (12/11 ~3 h 30) Relecture simplicité (11 points, tous corrigés) : une phrase SUR Lucarne sans virgule ni demande (« Lucarne est prête, je te l'envoie demain ») est collée, plus jamais un rappel ; sans « rappelle-moi », il faut « j'ai / il faut que… » ou une tâche (« appeler Paul ») ; après minuit « demain » = le jour qui commence et l'îlot nomme le jour (« vendredi 13 ») ; 5 h / 6 h = le matin, un réveil jamais l'après-midi ; « 13/11 à 14 h » et « 13 14 h » lus juste ; « Lucarne, … » lu sur le texte de Groq AVANT la remise au propre (une commande ne part plus à l'IA) ; « Copier » rend la phrase entière ; la note au clic liée à SA dictée (un texte en retard devient une note, jamais jeté) ; glissé sur le panneau AirDrop = « Glissé vers AirDrop » ; heure passée = « Cette heure est passée » (rien d'ajouté) ; « Rouvrir et dicter » → « Rouvrir le micro » (il ne lançait pas de dictée) ; double de l'app Rappels retrouvé aussi par son identifiant externe. Rendus 24t, 27b, 27h, 27i.
  - [ ] Hugues : essayer en vrai. NON vérifié d'ici : la vraie fenêtre d'autorisation des Rappels et l'arrivée sur l'iPhone (EventKit jamais appelé par l'essai) ; la vraie dictée au clic (micro, texte en direct, silence de 2 s avec SA voix et SON bruit de fond ; seuil = fond + 10 dB) ; comment Whisper transcrit « Lucarne » en tête de phrase (pas ajouté à l'invite de Whisper : à mesurer d'abord, cf. l'item FIABILITÉ). À trancher : le Mac sonnera DEUX fois pour un rappel synchronisé (l'îlot + la notification de l'app Rappels) ; l'iPhone une fois.
    Plan (12/11, 2e agent) :
    1. DicteeCore/CommandesLucarne.swift : mot d'appel (« Lucarne », « Verbe », variantes mal transcrites) ; dates et heures n'importe où dans la phrase (demain, lundi, ce soir, 13-14 h → 13:00, midi, dans 20 min…) ; texte du rappel à l'infinitif et sans « j'ai une » ; minuteur ; « Je n'ai pas compris » ; suggestion de rappel dans une note ; fin de note au silence (2 s) ; plan de l'app Rappels (demander une fois, refus dit une fois).
    2. Contrôles : phrases réelles + pièges (« Lucarne est une fenêtre », mail sans mot d'appel).
    3. Note rapide au clic : « Dicter une note » démarre l'écoute dans la carte (« J'écoute… », niveau, texte en direct, « Terminé »), sans encoche de dictée ; fn en bonus ; « En faire un rappel · demain 13:00 » sous la note.
    4. Rappels dans l'app Rappels (EventKit, injectable) : question dans l'îlot au premier rappel, création / coche / suppression / report, pas de doublon.
    5. Essai de l'îlot (2 fois), rendus regardés, commit.
- [ ] Intégrer la branche bibliotheque (Bibliothèque, Réveil, Calendrier ; terminée et relue 12/11 ~0 h) dans main APRÈS l'équipe simplicité (qui travaille sur main), puis reunions-wispr quand elle sera finie.
- [ ] (Hugues 12/11 ~0 h : « c'est bien les commandes vocales, mais si ça ne marche pas, aucun intérêt ») FIABILITÉ des commandes « Lucarne, … » avant tout : le mot d'appel doit être reconnu même mal transcrit (« Lucarnes », « l'ucarne », « Lu carne », « La carne », « Verbe »…), « Lucarne » ajouté au lexique / à l'invite de Whisper ; banc de phrases RÉELLES dictées par Hugues (transcriptions Groq gardées) avec taux de réussite mesuré ; jamais d'échec silencieux (« Je n'ai pas compris : … » + la phrase, rien collé) ; confirmation visible et « Annuler ». À vérifier après l'équipe simplicité, avant de lui dire que c'est prêt.
- [ ] (12/11 00 h 12, capture de Hugues) AirDrop a encore affiché « Envoyé · Capture d'écran … · AirDrop » sans envoi voulu : vérifier que la correction de l'équipe simplicité couvre ce cas (glisser la vignette d'une capture d'écran vers le haut → zone AirDrop par accident ?) ; la zone AirDrop doit exiger un vrai survol (≥ 0,4 s) et ne jamais afficher « Envoyé ».
  → FAIT (12/11, équipe simplicité, sur main) : plus jamais « Envoyé » (« Envoi lancé vers AirDrop », « Annulé » même après le choix de l'appareil) ; un lâcher sur AirDrop éclairée depuis moins de 0,4 s va sur l'étagère (essai : « lâché sur AirDrop sans s'y arrêter »). Non vérifié d'ici : ce que le vrai panneau AirDrop de macOS 26 répond quand on l'annule (rien ne peut l'appeler sans l'ouvrir à l'écran).
- [ ] (Hugues 12/11) Lucarne DÉPLAÇABLE : en haut (encoche), EN BAS (pilule au-dessus du Dock, dépliée vers le haut) ou SUR LE CÔTÉ GAUCHE (dépliée vers la droite) ; utile aussi sans encoche / écran externe. Maquette animée d'abord, puis construction ; la vidéo v5 en montre un aperçu.
- [ ] (Hugues 12/11 ~0 h 30) DÉPLACER la Lucarne soi-même : appui long (~0,5 s) puis glisser vers un bord (haut/encoche, bas, gauche, droite ?), zones d'accroche, pose au ressort ; règle anti-conflit : appui long SANS bouger = action actuelle (rangée Minuteur), appui long PUIS mouvement > 12 pt = déplacement. Hors encoche : Liquid Glass macOS 26 (réglage Verre · Noir). Fluidité niveau pilule Wispr Flow. Maquette lucarne-position.html en cours.
- [ ] (Hugues 12/11) AUDIT complet du code par un agent Opus (lecture seule pendant que les équipes travaillent) → docs/audit-dette-technique.md + ~/Desktop/Lucarne-audit/audit.html ; puis REFACTOR par petites étapes sans changer le comportement, APRÈS fusion de toutes les branches.
- [ ] Branche reunions-wispr TERMINÉE (12/11 ~1 h) : à intégrer avec bibliotheque et correctif-captures après l'équipe simplicité ; puis FluidAudio (séparation des voix).
- [ ] (Hugues 12/11) VIDÉO FINALE EN DERNIER : une fois tout fini (Liquid Glass, déplacement, nettoyage, renommage), refaire la vidéo complète avec tout ce qui est réellement dans l'app ; la v5 en cours sert d'étape intermédiaire.

## Lucarne déplaçable — VALIDÉ par Hugues le 12/11 (maquette design/maquettes/lucarne-position.html, 7ba10b4)
- Appui long 0,4 s directement sur Lucarne (même dans l'encoche) → se décolle ; suit le pointeur 1:1 ; 8 places aimantées (haut G/milieu=encoche/D, côtés milieu G/D, bas G/milieu/D) ; lancer possible ; retour aimanté dans l'encoche = noire.
- Aucun réglage ; l'appui long ne sert plus au minuteur.
- Hors encoche : vrai Liquid Glass macOS 26 (NSGlassEffectView, présent dans le SDK) ; Hugues veut un verre accentué (niveau à choisir sur la maquette).
- À corriger en construisant : gris translucide au retour, Centre/bannière au-dessus de la ligne du Dock depuis un coin bas.
- 12/11 01:21 : ouverture vers le haut au-dessus du Dock depuis un coin bas VALIDÉE (« très bien ») ; il veut ENCORE plus Liquid Glass → niveau « Liquide » (variante clear iOS 26, NSGlassEffectView style .clear dans l'app).
- 12/11 : niveau « Liquide » (65be977) accepté (« si c'est pas possible, c'est très bien ») → dans l'app : NSGlassEffectView style .clear, le plus liquide possible, lisibilité gardée.
- [x] (12/11 soir) Mission 4 « Bords et nettoyage » (branche `lucarne-bords`, poussée, non fusionnée) : Dock réel (gauche, droite, masqué ; relu seulement quand il change), plusieurs écrans (glisser de l'un à l'autre, une place par écran, débranché → principal), plein écran (décision D), sans encoche (décision A), VoiceOver « Déplacer vers… », encoche qui n'attire plus qu'à ~150 pt, code mort `.lectureMinuteur` retiré. Détail : docs/plan-lucarne-deplacable.md, « État mission 4 ».
  - [ ] Hugues, une fois installée : une app en plein écran (la Lucarne ne bouge pas), un second écran (la glisser dessus, le débrancher), VoiceOver (actions « Déplacer vers… »).
- [ ] (Plus tard, idée Hugues 12/11 relayée par la session Second Brain) ÉCOSYSTÈME Sillonia · Second Brain · Lucarne « comme Apple » : au début d'un appel (Meet, WhatsApp, Aircall) l'îlot PROPOSE « Prendre des notes ? » (jamais sans accord), résumé de fin vers la fiche Second Brain / Sillonia / Airtable ; dictée envoyable à Second Brain. Note : ~/second-cerveau/idees/ecosysteme-sillonia-second-brain-lucarne.md. RIEN maintenant.
- 12/11 : App de bureau — Hugues préfère B et C, « la C elle est très bien » → base C (îlot d'abord, petite fenêtre en verre sortie de l'encoche) + greffes de B (Aujourd'hui en tuiles, illustrations du premier lancement, bouton soleil/lune) → design/maquettes/lucarne-app-final.html (en cours).

## NUIT DU 12/11 (Hugues dort, autonomie totale ; « je veux la vidéo au réveil »)
1. Installer installe-12nov (captures + glisser + Second Brain + micro coupé 85f01ff) après essai vert.
2. Vidéo finale (agent vidéo) : RETOURS-POUR-LA-FINALE.md, nom en variable, 3 musiques, 120/60 i/s.
3. Fin de la simplicité → intégration complète dans main : simplicité, installe-12nov, bibliotheque, reunions-wispr (+voix-reunions), groq-relais, lucarne-place → vérif + install + push.
4. Lucarne déplaçable missions 2-4 (équipe + relecteurs) sur main intégré.
5. Nouveaux noms (agent Fable) → page à ouvrir au réveil ; rien renommé sans Hugues.
6. Au réveil : PDF de synthèse sur le Bureau + OU-J-EN-SUIS.md.
- [ ] (Hugues 12/11 nuit, après test) RAPPEL : ne marche pas dans la version installée (la simplicité, avec Rappels Apple, n'est pas encore installée → vérifier en VRAI après intégration). « Dicter la note » marche. À AJOUTER : pendant la dictée d'une note ou d'un rappel, une ANIMATION de voix enregistrée dans l'îlot (onde vivante), pas seulement la musique mise en pause ; à la fin du rappel, une carte : case cochée, titre, date/heure, note résumée, bouton « Envoyer » (Rappels / Partager) ; même chose pour la note dictée. Aussi dans la vidéo (transmis à l'agent vidéo).
- [ ] (Hugues 12/11 nuit) RÉUNIONS : optimiser à fond + bulles audio façon WhatsApp à côté de chaque passage transcrit (lecture, onde, vitesse, « Télécharger l'extrait » .m4a, glisser vers une app, export de toute la réunion), rétention respectée → confié à l'équipe voix-reunions.
- [ ] (Hugues 12/11 nuit) CONCENTRATION dans l'îlot : rond « Concentration », grille des modes + durée, mode affiché dans l'aile, notifications retenues ; via un raccourci de l'app Raccourcis → maquette ilot-concentration.html en cours ; aussi dans la vidéo.
- [x] INTÉGRATION (note, FAIT 12/11 à l'intégration dans main) : conflit de noms de rendus — Groq ilot-27a…27j → ilot-29a…29j ; Second Brain → ilot-28a…28f ; Bibliothèque ilot-25a…25j → ilot-30a…30j ; Réveil et Calendrier ilot-26a…26n → ilot-31a…31n ; vignette des captures ilot-24s → ilot-24u (ilot-24*…27* de main gardés). Groq : limites gratuites vérifiées 12/11 = 20 req/min, 2 000/jour, 7 200 s/h, 28 800 s/jour (480 min) par modèle ; minimum facturé 10 s/requête.
- [ ] (Hugues 12/11 ~04:00) NOM : si les agents Fable finissent pendant qu'il dort, JE choisis le plus pertinent (le plus Apple / Revolut, révolutionnaire) et la vidéo finale le porte. Le RENOMMAGE de l'app, l'icône et le manuel se font APRÈS, avec lui réveillé.
- [x] (Hugues 12/11 00:16) « Captures d'écran ici » allumé, aucune capture sur l'étagère : les captures GLISSÉES depuis la vignette flottante (dans le Terminal) ne vont jamais dans le dossier des captures, macOS les laisse dans …/T/TemporaryItems/NSIRD_screencaptureui_X/. Ce dossier temporaire est maintenant surveillé aussi (sans autorisation) ; glisser annulé = la copie du dossier des captures remplace la glissée. Branche correctif-captures.
- [ ] (Hugues 12/11 ~04:15) Si le NOM change : lancer en parallèle des propositions d'ICÔNE adaptée (Hugues choisit au réveil) ; la vidéo finale suit son choix (nom + icône en variables, re-rendu rapide).
- [ ] (12/11) Second Brain dans l'îlot, reste à faire (maquette ilot-second-cerveau.html) : aile gauche (signe + badge) et bulle pendant une vidéo, bandeau « Camille t'a écrit », page « D'où viennent ces infos » avec ses trois interrupteurs ; à décider avec Hugues après l'avoir vu en vrai (fait : rond dans le Centre + carte rangée sous le Centre, pour ne pas pousser Minuteur et Étagère).

## La Bibliothèque (branche bibliotheque, 11/11 soir) — maquette design/maquettes/ilot-bibliotheque.html, étapes 1 à 6 (validée : « c'est lourd à mort… tout est bien »)
Rien n'est retiré du Centre ni de l'étagère : on AJOUTE.
- [x] 1. DicteeCore/BibliothequeIlot.swift : entrées (signet, nom, sorte, source, date, taille, épinglée), fusion avec les sources, filtres, recherche sans accents, tri, groupes par date, retrait (bibliothèque seulement) + annulation, plafond 500 (les plus anciens non épinglés sortent) ; géométrie de la carte ; contrôles
- [x] 2. App : BibliothequeModele (fichier 0600 dans Application Support, signets relus hors du fil principal), sources isolées Téléchargés / AirDrop / Captures (éteintes par défaut, Settings), l'étagère y verse tout ce qu'elle range
- [x] 3. Îlot : ligne « Bibliothèque · Tout voir » sous la carte Étagère ; carte Bibliothèque (‹ Étagère, recherche au clavier pris seulement pendant la saisie, Récents/Anciens, pastilles, épinglés, groupes, épingler / retirer + Annuler, plusieurs choisis + « Glisser les N », pied + « En grand »)
- [x] 4. Fenêtre : onglet « Bibliothèque » (avant Réglages) : vignettes QuickLook hors du fil principal, filtres, recherche, tri, épinglés, colonne « Ce que la bibliothèque montre » (interrupteurs des sources)
- [x] 5. Essai à vrais clics (IlotEssaiBibliotheque), rendus 25* (renommés ilot-30* à l’intégration), comparaison à la maquette, commits
  → 2 138 contrôles, `--ilot-essai` tout vert (515 vérifications dont la section Bibliothèque à vrais clics, touches et défilements), rendus 25a-25j (aujourd’hui ilot-30a-30j) (+ 22e/22f/22g/23m, la ligne « Bibliothèque » ajoutée à la carte Étagère).
- [ ] Hugues : essayer en vrai (glisser plusieurs fichiers vers Mail avec « Glisser les 3 » ; allumer Téléchargés/Captures dans l'onglet : macOS demande l'accès une fois). Non vérifié d'ici : le vrai glisser vers une autre app (l'essai ne fait que préparer les 3 éléments), les vignettes QuickLook de vrais fichiers, la question d'accès de macOS.

## Le Réveil et le Calendrier (branche bibliotheque, 11/11 soir) — même maquette, étapes 7 à 13
Rien n'est retiré du Centre : on AJOUTE (un onglet Réveil dans la case Minuteur, un 6e rond Calendrier).
- [x] 1. DicteeCore : ReveilIlot (heure, prochaine sonnerie, « Encore 10 min », fichier JSON), commande dictée « réveille-moi à 9 h » / « réveil à 7 h 30 » (stricte : la phrase entière), vues reveilCompact / reveilRegle / reveilFini, activité .reveil, ElementCentre.calendrier, six ronds, noms sur deux lignes mesurés
- [x] 2. App : réveil gardé dans Application Support (0600), une seule échéance sur l'horloge murale (la veille compte), relu au réveil du Mac ; pas de réveil du Mac endormi (IOPMSchedulePowerEvent exige root) : limite écrite dans la note du réglage ; écran rallumé (activité déclarée) au moment de sonner, injectable
- [x] 3. Centre : sélecteur « Minuteur · Réveil », 7:00 · 8:00 · 9:00 · Autre… (− / + par 15 min, OK), « demain » ; cases 1,16 / 0,84 (maquette) ; rond Calendrier (Éteint → clic → macOS demande une fois → Allumé ; refusé : « Accès refusé » + ligne vers Réglages Système)
- [x] 4. Alerte de début d'un rendez-vous : « Rejoindre » ET « Noter la réunion » (maquette, 2e ligne) ; nom du service (Google Meet, Zoom, Teams)
- [x] 5. Contrôles, essai à vrais clics (IlotEssaiReveil), rendus 26* (renommés ilot-31* à l’intégration), comparaison à la maquette, commit
  → contrôles et `--ilot-essai` tout verts (68 vérifications de plus pour le Réveil et le Calendrier, à vrais clics), rendus 26a-26n (aujourd’hui ilot-31a-31n) ; le calendrier s'ajoute UNE fois à un Centre déjà rangé (« Modifier »), retiré ensuite il ne revient pas.
- [ ] Hugues : essayer en vrai (onglet Réveil, « réveille-moi à 9 h » îlot fermé, rond Calendrier : macOS demande une fois, un vrai rendez-vous Meet/Zoom). Non vérifié d'ici : la vraie question de macOS pour les calendriers, le vrai son et l'écran rallumé au réveil, un réveil pendant la veille du Mac (il ne PEUT pas réveiller le Mac : root).
- [x] 6. Relecture (5 défauts corrigés, 1 écarté) : le panneau ❞ garde ses 5 mots (les 6 ne tiennent pas dans 352 pt, contrôle de largeur dans `--rendu-panneau`) ; le calendrier d'un Centre jamais rangé est retenu comme donné (retiré, il ne revient plus) ; « OK » d'« Autre… » règle toujours (n'annule plus l'heure déjà réglée) et un réveil annulé ferme − / + / OK ; « Minuteur et réveil » éteint annule le réveil (et il ne sonne jamais) ; îlot fermé, seuls les ORDRES (« réveille-moi », « mets un réveil ») règlent un réveil, et « Annuler » recolle la phrase dictée. Écarté : la case s'ouvre sur l'onglet Réveil au survol de l'aile du réveil (voulu, comme l'aile du minuteur ouvre l'onglet Minuteur ; « Minuteur » à un clic).

## Limites de Groq et relais sur le Mac (12/11, branche groq-relais) — Hugues : « j'ai peur un jour d'arriver à mes limites sur Groq » (pas de Whisper local)
Limites gratuites relevées sur console.groq.com/docs/rate-limits (12/11) : whisper-large-v3 ET whisper-large-v3-turbo, chacun 20 req/min,
2 000 req/jour, 7 200 s d'audio/heure (ASH), 28 800 s/jour (ASD = 480 min). En-têtes : x-ratelimit-limit/remaining/reset-requests (= par
JOUR), -tokens (par minute, rien pour l'audio), retry-after sur 429. Facturé 10 s au moins par requête (docs/speech-to-text).
- [x] DicteeCore/UsageGroq.swift : compteur (envois audio 24 h, marge lue dans les en-têtes, pause d'une 429 et sa cause lue dans le corps), bilan, niveau (ok / bas < 15 % / épuisé), phrases, annonces (une fois par passage), décision du relais et signe
- [x] Contrôles DicteeControles (horloge injectée, aucun réseau)
- [x] App : GroqClient compte chaque requête (durée du son) et lit les en-têtes ; fichier local ~/Library/Application Support/Dictee/groq-usage.json (0600)
- [x] Réglages : « Groq aujourd'hui : 42 min sur 480 · tout va bien » ; progression du téléchargement de la langue du Mac
- [x] Îlot : rond « Groq » (jauge en anneau) sur la page Outils, détail au clic ; annonces < 15 % et limite atteinte ; signe « Mac » dans les ailes après une dictée passée par le Mac
- [x] Relais : texte d'Apple corrigé à l'oreille (lexique) + mots du lexique donnés à SpeechAnalyzer (AnalysisContext) ; la dictée suivante retente Groq
- [x] Vérif : build release, DicteeControles, --ilot-essai, rendus regardés, essai du relais sur un fichier `say`
- Relais mesuré sur des fichiers `say` (voix Thomas, `--relais-essai … --reserver`) : 92 % et 95 % de mots justes (le seul écart : « 15h » pour « quinze heures »), 81 % avec trois noms propres (le lexique a corrigé Ladislas et Sillonia, pas « Lucarne » ni « Groq ») ; la voix Jacques ne vaut rien (50 %).
- [ ] Hugues : essayer en vrai (couper le Wi-Fi, dicter : « Dicté sur le Mac · Pas de réseau », puis « Mac » dans les ailes ; la jauge des Outils ; la ligne des Réglages). Non vérifié d'ici : une vraie 429 de Groq (corps et en-têtes réels), la vraie dictée au micro par le relais, le téléchargement réel de la langue (déjà installée chez Hugues).

## Lucarne déplaçable — sondes (12/11, lecture seule, branche lucarne-place)
- Plan : docs/plan-lucarne-deplacable.md. MISSION 1 (modèle pur) faite : Sources/DicteeCore/PlaceLucarne.swift + Sources/DicteeControles/ControlesPlacesLucarne.swift (renommé à l’intégration : ControlesLucarne.swift et IlotEssaiLucarne.swift existent déjà sur main pour « Lucarne, … » ; l’essai des places s’appellera IlotEssaiPlacesLucarne.swift) (321 contrôles, 12 groupes « Lucarne : … »).
- Dock (`defaults read com.apple.dock`) : `orientation` = bottom ; `autohide` = clé absente (donc faux) ; `tilesize` = 56 ; `largesize` = 16 ; `magnification` = 0.
- Écran du MacBook Air (script Swift sans fenêtre, NSScreen) : `frame` = (0, 0, 1470, 956) ; `visibleFrame` = (0, 70, 1470, 853) ; échelle 2 ; `safeAreaInsets.top` = 32 ; `auxiliaryTopLeftArea` = (0, 924, 646, 32), `auxiliaryTopRightArea` = (825, 924, 645, 32).
- Déductions pour `EcranLucarne` : barre des menus = 956 − (70 + 853) = 33 pt ; caméra = 825 − 646 = 179 pt (demi-caméra 89,5), centre de l'encoche à x = 735,5 depuis le bord gauche (le milieu de l'écran est 735) ; Dock en bas = `visibleFrame.minY` = 70 pt = tilesize 56 + 14 (`EcranLucarne.epaisseurDock(tailleIcone:)`) ; aucun retrait à gauche ni à droite.
- Largeur du Dock : toujours aucune API publique → `dockLargeur` reste nil côté contrôleur tant qu'on ne l'estime pas (les coins du bas passent alors AU-DESSUS du Dock).
- Écarts au plan (mission 1) : constante `tenue` 1,04 renommée `echelleTenue` (collision avec la fonction `tenue(...)`) ; `MemoirePlaces.place(pour:)` sans paramètre `encoche:` (la place par défaut est la même, c'est `EcranLucarne` qui sait ce que « encoche » veut dire sans caméra) ; ailes compactes de l'encoche = 44 pt (celles de `VueIlot.lectureCompact`, tracé identique vérifié) au lieu des 43 de la maquette ; `RessortsCapsule` porte aussi l'écart de prise (decalX/decalY) ; `GeoLucarne.placeLachee` (aimant → encoche, > 350 pt/s → direction, sinon la plus proche) et `GesteLucarne.interrompre()` ajoutés.
- [ ] voix-reunions PRÊTE (599350e + cda43b7 : voix séparées FluidAudio, bulles audio façon WhatsApp, export .m4a, Arrêter→Note 20 s→14 s) → fusionner après l'intégrateur. À DÉCIDER par Hugues : « Garder le son des réunions » est ÉTEINT par défaut → bulles grises « audio effacé » ; l'allumer pour les écouter.

## Retours de Hugues du 12/11 03:52 (branche installe-12nov)
- [x] « Ça plante de temps en temps quand je me balade dessus » (carte Dictées) : survols SwiftUI coupés par la vue d'hébergement (zones de suivi retirées, `super` jamais appelé), puis fondus de survol coûteux ; corrigé, essai `--ilot-essai --seulement=survol` (vrais mouvements, 960 dictées). À regarder en vrai par Hugues : « Coller » et le fond de la ligne suivent la souris.
- [x] Téléchargements « dossier inaccessible (errno 13) » à 03:52:34 : c'était l'essai d'une autre équipe (l'app installée a l'accès, TCC autorisé, signature à exigence fixe déjà stable) ; tous les modes de vérification écrivent leur journal à part.
- [x] « Remettre » après un glisser : une croix (✕) qui ferme tout de suite, l'anneau discret autour.
- [x] (12/11 ~05:30) NOM CHOISI par moi (délégation de Hugues : « le plus Apple / Revolut ») : **Voxile** (vox + isle / voix + île = l'îlot qui écoute). Vérifié : 0 app Mac/iOS FR+US, GitHub 6 dépôts à 0 étoile, voxile.app/.io/.fr libres (RDAP/whois 12/11), .com pris (en vente). Alternatives sur la page noms-v2.html (favori de l'agent : Luette). Renommage de l'app = AVEC Hugues réveillé. Icônes « Voxile » lancées (il choisit).

## Réunions façon Wispr Flow — l'îlot pendant la réunion (branche reunions-wispr, maquette design/maquettes/ilot-reunion.html étapes 1 à 7, « très bien pour ce visuel »)
- [x] Cœur : la réunion devient une activité de l'îlot (plus de `cache`) : compact (point rouge + onde / durée), carte « Réunion », annonces (Noter cet appel ?, Note en préparation, Note prête, message) ; pile de cartes ; lecture plus masquée pendant une réunion
- [x] Direct propre (DicteeCore/DirectReunion) : ordre chronologique, tours de parole fusionnés, reprises de Whisper retirées, échos retirés en direct (gris tant que l'écho n'est pas jugé), « … » gris pendant qu'on parle
- [x] « Ce que j'ai raté » (3 dernières minutes, même service que la note, 2–3 puces), « Ajouter un point » (gardé dans la réunion), Pause / Reprendre, Arrêter, Centre
- [x] Plus de fenêtre ReunionEncoche : l'îlot la remplace (avec et sans encoche) ; menu « Noter / Arrêter la réunion » gardé
- [x] Contrôles, essai de l'îlot (réunion factice, vrais clics), rendus comparés à la maquette, commits
- [ ] Hugues : essayer en vrai (un appel Zoom/Meet : « Noter cet appel ? », la carte au survol, le direct, « Ce que j'ai raté », un point, pause, Arrêter). Non vérifiés d'ici : le vrai micro et le son du Mac, la qualité réelle du direct (chaque morceau fait 10 à 30 s : le texte arrive par blocs, le « … » gris dit qu'on parle), la réponse réelle de Groq pour « Ce que j'ai raté ».
- [ ] Suite (autres équipes de la branche) : après l'appel, retravailler TOUT l'enregistrement (noms, texte propre), la note par sujets, « Demander » ; « Note en préparation » avec une vraie progression.

## Réunions façon Wispr Flow — la note après l'appel (maquette ilot-reunion.html étapes 8 à 12)
- [x] Son : les deux pistes toujours écrites sur le Mac (WAV 0600, calées sur l'heure de la réunion) jusqu'à la note, puis effacées sauf « Garder le son des réunions »
- [x] Relecture : tout l'enregistrement retranscrit par whisper-large-v3 (horodatages, lots de passages de parole), repli sur le direct pour un lot en échec ; progression dans l'îlot (« Note en préparation… » + % + barre de la maquette)
- [x] Note au format de la maquette : phrase d'ouverture, résumé par sujets (titres + puces imbriquées), Décisions, Prochaines étapes (qui, quand, case), points marqués, transcription (orateur + heure à la 1re ligne de chaque minute, clic = réécouter)
- [x] Orateurs : « Moi / Eux » pour l'instant, un orateur par segment, renommable une fois pour toutes (structure prête pour la séparation des voix)
- [x] « Demander » sur la réunion (réponse liée au moment) et « Demander à mes réunions » ; Copier / Exporter (Markdown)
- [x] Onglet Réunions refait : colonne de gauche (recherche, Demander à mes réunions, liste par jour) + la note
- [x] Contrôles, essai de bout en bout sans réseau ni micro (relecture et note factices), rendus comparés à la maquette, commit
- [ ] Hugues : essayer en vrai (5 points « À vérifier en vrai » de la section « la note après l'appel » de docs/spec-v1.md). Non vérifiés d'ici : la vraie réponse de Groq (relecture, note par sujets, « Demander »), le son réel réécouté, la durée réelle du traitement.
- [ ] Suite : séparation des voix (« Qui parle », les noms de chacun) ; décider si le son doit être écrit compressé pendant l'appel (≈ 115 Mo par heure et par piste aujourd'hui, effacé à la fin).

### Relecture Réunions (9 points de l'équipe, 12/11)
- [x] Grave : le son de l'appel n'est plus effacé quand la relecture échoue (réunion gardée « sans note », son gardé 7 jours, « Refaire la note » le relit) ; effacé seulement note prête ET tout l'appel relu
- [x] ⌘Q pendant l'appel : sources coupées, son fermé, passages de parole enregistrés (aussi toutes les 5 s) ; « Refaire la note » dès que le son est là ; son gardé pour réessayer effacé au lancement après 7 jours
- [x] Son temporaire hors de Time Machine ; écriture du WAV sur une file à part (plus rien sur le fil temps réel)
- [x] À l'arrêt : les morceaux du direct pas encore partis ne partent plus (la relecture les reprend) ; relecture sur le modèle précis seulement (plus de secours turbo pris à la dictée)
- [x] Réunion effacée ou renommée pendant l'enregistrement / la préparation : rien n'est recréé, le titre et les orateurs changés sont gardés
- [x] « Ce que j'ai raté » : seulement les 3 dernières minutes d'un long tour ; puces mesurées à la vraie police, coupées à un mot entier
- [x] Contrôles (2 282), essai de l'îlot (section « le son gardé tant qu'il peut servir »), rendus comparés (nouveau : reunions-14-pas-entierement-relue)

## Voix séparées dans les notes de réunion (FluidAudio, 12/11) — branche voix-reunions
Accord de Hugues : « oui part sur FluidAudio ». La transcription reste chez Groq ; seule la séparation des voix est faite sur le Mac.
- [x] FluidAudio 0.18.2 (version exacte), seul le module « Diarizer » (ni synthèse vocale, ni normalisation de texte) ; pipeline
      hors ligne pyannote community-1 (découpe + empreintes WeSpeaker + regroupement VBx), passages exclusifs, moteur neuronal + processeur.
- [x] Logique pure (DicteeCore/VoixReunion.swift) : tours de parole → « Personne 1, 2… » sur les passages « Eux » (chevauchement,
      tour le plus proche à 1,5 s près, voix de moins de 3 s fondues, moins de 2 voix = repli « Eux ») ; renommage dans toute la note
      (passages, en bref, sujets, décisions, étapes, participants, export) ; empreinte de voix gardée avec l'orateur + `reconnaitre`
      (structure pour « voix connue », pas encore branchée) ; progression (relecture et voix en parallèle, téléchargement visible).
- [x] App (Dictee/SeparationVoix.swift) : modèle dans ~/Library/Application Support/Dictee/Modeles (téléchargé au premier usage
      depuis Hugging Face, effacé par « Désinstaller »), chargé le temps d'une séparation, une à la fois, WAV « Eux » lu sans tout
      charger ; branchée dans la préparation de la note (pendant la relecture) et « Refaire la note » ; repli « Eux » + avertissement.
- [x] La rédaction de la note lit « Personne 1 : … » ; la garde contre l'invention accepte « Personne 2 » dans « qui ».
- [x] Contrôles (2 325 verts) + essai `--ilot-essai` « voix séparées » (séparation, relecture et rédaction factices, ni micro ni son).
- [x] `Verbe --voix-mesure piste.wav [--verite tours.tsv] [--modeles DOSSIER]` ; `--reunion-test … [--modeles DOSSIER]` sépare aussi.

### Mesures (12/11, MacBook Air M5 16 Go, d'autres équipes compilaient en même temps : temps à ±40 %)
Son de test fabriqué (`say` : Thomas, Amélie, Jacques ; tours de 1 à 4 phrases, silences de 0,25 à 1,2 s ; aucune vraie réunion).
- Taille de Verbe.app (`./build.sh --sans-installer`) : 17,8 Mo → 25,4 Mo (+7,6 Mo, tout dans l'exécutable : 17,5 → 25,2 Mo).
  Compressée (zip, ≈ ce qu'on télécharge) : 4,9 Mo → 7,3 Mo (+2,4 Mo). Piste : `strip -x` de l'exécutable ferait 7,6 Mo (avant) /
  12,5 Mo (après) — non fait (build.sh pas touché, les rapports de plantage perdraient des noms).
- Modèle téléchargé une fois : 21-22 Mo sur le disque (4 modèles CoreML + paramètres). Téléchargement : 14 s, une autre fois 134 s
  (Hugging Face lent, une reprise après délai dépassé). Chargement ensuite : 0,1 s.
- 20 min de son « Eux », 3 voix : séparation en 5,5 à 8,5 s (140 à 220× plus vite que le temps réel) ; mémoire de pointe du processus
  ≈ 500 Mo pendant ces quelques secondes (≈ 700 Mo si on laisse aussi la carte graphique : d'où le moteur neuronal + processeur ;
  la taille des lots ne change rien), puis 46 Mo une fois les modèles libérés. 3 min : 2,6 s.
  (Une première série avait donné ≈ 250-300 Mo de pointe ; les séries suivantes ≈ 500 Mo, sans changement de code expliquant l'écart.)
- Justesse sur 20 min : 3 voix trouvées sur 3 ; 91,3 % du temps de parole à la bonne voix ; 93,4 % des passages de la transcription au
  bon orateur (347 passages simulés). Amélie (voix de femme) presque parfaite (111/114) ; Thomas/Jacques (deux voix d'homme de
  synthèse) confondus sur 19 passages de Jacques sur 116. Sur 3 min : 94,4 % / 98 %.
- Bout en bout (`--reunion-test`, vraie relecture Groq + vraie séparation, 3 min, 3 voix + Moi) : 24 passages « Eux » relus, tous
  au bon orateur (Amélie → Personne 1, Thomas → Personne 2, Jacques → Personne 3) ; la note dit « Personne 2 : Envoyer le contact… ».

### Pas fait / à faire
- [ ] Hugues : essayer en vrai (un appel à 2-3 personnes ; regarder la progression « Téléchargement du modèle de voix » la 1re fois).
- [ ] Reconnaître une voix déjà nommée d'une réunion à l'autre (empreintes gardées, `SeparationVoix.reconnaitre` prêt, rien de branché).
- [ ] Renommer d'un clic sur le nom dans une ligne de la transcription (aujourd'hui : clic sur « Personne 1 » dans l'en-tête de la note).
- [ ] La transcription du direct pendant l'appel reste « Moi / Eux » (la séparation se fait après l'appel).

## Bulles audio (« vocaux ») + réunion optimisée (12/11) — branche voix-reunions
Demande de Hugues : « optimise à fond la réunion. Et pour les vocaux, dans la transcription, comme sur la maquette : la possibilité de
télécharger directement les bouts où les gens parlent, comme WhatsApp, à côté de ce qui a été transcrit. »
- [x] Une bulle par passage sous le texte : ▶︎/❚❚ dans la couleur de l'orateur, onde du vrai son (36 barres, la part jouée en
      couleur, un clic s'y place), durée (temps écoulé pendant la lecture), vitesse ×1 / ×1,5 / ×2, « Télécharger l'extrait ».
      L'extrait exact : la bonne piste (micro pour « Moi », son du Mac pour les autres), 0,15 s avant / 0,35 s après les heures de
      Whisper sans mordre sur la voix voisine de la même piste ; la lecture enchaîne sur le passage suivant. Un clic sur le texte joue.
- [x] Télécharger : .m4a AAC 16 kHz 32 kbit/s, « Réunion – Personne 2 – 14h05.m4a », panneau d'enregistrement du Mac ; la bulle se
      glisse vers Finder / Mail / WhatsApp comme un fichier ; bouton « Audio » : toute la réunion, Moi + Eux mélangés, encodée par blocs.
- [x] Rétention : bulles seulement si le son est gardé (réglage « Garder le son des réunions », ou les 7 jours d'attente) ; sinon
      bulle grise « audio effacé ». Extraits de glisser-déposer dans Reunions/.extraits (0700/0600), effacés avec le son, avec la
      réunion et à chaque lancement. Fichiers exportés en 0600. Aucun réseau.
- [x] Optimisations : relecture 3 lots à la fois (audio réservé d'un seul geste), séparation des voix sur les seuls passages de
      parole + fenêtres tous les 3,5 s, direct de l'îlot recalculé seulement s'il change.

### Mesures avant / après (MacBook Air M5 ; d'autres équipes compilaient : charge 4 à 25, voir chaque ligne)
- Arrêter → note prête (`--reunion-test`, appel fabriqué de 8 min, 3 voix + Moi, vrai Groq) : avant 23 s = relecture 10,3 s
  (6 lots l'un après l'autre) en parallèle de la séparation (7,4 s de chargement sous charge + 4,6 s), puis note 11 s.
  Après relecture en parallèle : relecture 5,0 s, mais la séparation devenait le goulet (charge 25). Voir la ligne « après tout ».
- Séparation des voix, appel fabriqué de 20 min où « Eux » parle environ 60 % du temps (charge 8) : avant 10,4 à 13,9 s (tout le
  fichier, fenêtres tous les 2 s) ; après 3,5 à 4,4 s (seulement les passages de parole, fenêtres tous les 3,5 s). Justesse : 98,6 %
  → 96,7 % des passages au bon orateur (le fait de n'analyser que les passages coûte 2 points ; le pas de 3,5 s ne coûte rien).
  Mémoire de pointe pendant la séparation inchangée (≈ 490-500 Mo quelques secondes, puis ≈ 40 Mo).
- Pendant l'appel (`--reunion-mesure`, 20 min, deux pistes, sans micro ni réseau) : pistes (conversion, niveaux, découpe, écriture
  du son) 39 ms de processeur par minute = 0,06 % d'un cœur (rien à gagner) ; direct de l'îlot recalculé chaque seconde : 0,83 %
  d'un cœur, et ça grandit avec la longueur de l'appel (il relit toute la transcription) → seulement quand il change : 0,14 %
  (1 205 calculs → 204). Mémoire ajoutée par l'enregistrement : ≈ 8 Mo (pointe 113 Mo dont 51 Mo de son d'essai chargé).
- Déjà en place, vérifié : envoi Groq au fil de l'eau pendant l'appel, morceaux pas encore partis abandonnés à l'arrêt, séparation
  lancée dès l'arrêt en parallèle de la relecture, une seule minuterie (1 s) pendant l'enregistrement, aucune au repos.
- [x] (12/11 matin) INTÉGRATION dans main (intégrateur) : correctif-captures, second-cerveau-ilot, bibliotheque, groq-relais, lucarne-place (modèle pur), installe-12nov, voix-reunions (+ reunions-wispr). Rendus renommés : Second Brain 28*, Groq 29*, Bibliothèque 30*, Réveil/Calendrier 31*, Réunion 32*, vignette 24u, croix 24v. Carte Étagère : « Bibliothèque » devient une pilule d'en-tête (la ligne du bas faisait déborder la zone de dessin avec les captures). Contrôles 3561/3561 ; --ilot-essai ×2 : 1173 vertes, 1 échec (ressort de la hauteur pas tout à fait posé 0,8 s après le dépliage de la lecture).
  - [ ] À trancher (Hugues) : « Lucarne, réveille-moi à 7 h » fait toujours un RAPPEL « Réveil » (simplicité), alors que « réveille-moi à 7 h » îlot fermé règle le vrai RÉVEIL (bibliotheque) ; le cas `.reveil` est prêt dans commandeLucarne.
  - [ ] À trancher (Hugues) : la Bibliothèque s'ouvre d'une pilule dans l'en-tête de la carte Étagère (maquette : ligne en bas) ; voir ilot-22f / ilot-30a.
  - [ ] Essai : « îlot déplié et posé : plus de boucle » échoue depuis la fusion (247,0006 → 247 à 0,8 s, vitesse encore ≥ 0,05) ; cibles stables (sondé), cause non trouvée.

## 12/11 matin — après l'intégration (main 57d66a2)
- [ ] Essai `--ilot-essai` : 2 échecs relevés pendant que la vidéo se rendait (charge processeur), à refaire Mac au calme :
  1. « îlot déplié et posé : plus de boucle » : geo[2] encore à 247,0016 → 247 au bout de 0,8 s (dt plafonné à 50 ms ⇒ la charge ralentit le ressort ?) ;
  2. « le survol suit la souris » : 225/355 (09:19, sous charge), alors que l'intégrateur l'avait vert. Écarts « attendu rien allumé rien » ⇒ `d.survol` pointe une entrée que `d.entree` ne trouve pas (id périmé ?) à creuser si ça se reproduit.
- [ ] Vidéo : 3 défauts envoyés au correcteur (fondu superposé Centre → Concentration, légendes qui se chevauchent vers 41 s, rectangle blanc bas-gauche) ; prochain rendu complet = avec l'icône choisie par Hugues.

## 12/11 fin de matinée — les deux échecs de `--ilot-essai` (97374b3, be6ea24 ; PAS poussé : essai pas vert)
- [x] « le survol suit la souris » (229/355) : CAUSE PROUVÉE. Quand la liste défile sous le pointeur, SwiftUI relit la VRAIE souris
      (`mouseLocationOutsideOfEventStream`). Celle de Hugues était posée sous l'encoche (957, 803 : dans la vue de 800 × 380 de l'îlot) ;
      à 8 h elle était loin. Preuve (même binaire, méthode permutée le temps du diagnostic) : vraie souris 229/355, lue loin 355/355,
      qui suit 355/355 ; fil principal 21-28 % → 11 %. Correctif : `PanneauIlot.pointeurEssai` (essais seulement). Les « attendu rien
      allumé rien » des essais complets : une ligne de l'ancienne source restait survolée (changer `DicteesIlot.source` ne redessinait
      pas) → corrigé. Hugues ne le vit pas dans l'app : la vraie souris y est celle des événements.
- [x] « îlot déplié et posé : plus de boucle » : le ressort ne met PAS plus longtemps (même trajet 32 → 247 pt, 62-63 pas, 1,05 s
      d'animation, aucune image perdue). La boucle démarre après que SwiftUI a construit la carte (dans le setFrame : 19 ms au calme,
      34-44 ms Mac occupé) ; le contrôle tombait à ≈ 1,08 s : 10 ms de marge (déjà raté à 3 h 34, avant les fusions). L'essai attend la
      fin de la boucle, 0,25 s au plus (posé 9 et 14 ms plus tard). Écarté par mesure : `sizingOptions` de NSHostingView (19 ms aussi
      par défaut une fois le Mac calme), le setFrame lui-même (0,3 ms seul).
- [x] « aucun à-coup » : CAUSE PROUVÉE (12/11 après-midi). Ni l'écran (vert et rouge écran éteint comme allumé), ni la souris :
      le même mouvement fait TOUJOURS le même travail (90 M d'instructions ±1 %, `proc_pid_rusage`), mais macOS le place tantôt
      sur un cœur performance (4,2 GHz : 7 ms), tantôt sur un cœur économe (1,7 GHz : 26 ms). Deux vrais coûts trouvés en chemin
      (profil `sample`) et allégés : chaque événement de molette recalculait `grille` → `hauteursEnPlus` → ~80 mesures Core Text des
      noms du Centre (mémoire dans `PlanCentre.tailles`) ; toutes les lignes observaient la carte (lignes Equatable, état en valeurs).
      Pas de molette 112 → 64 M d'instructions (−42 %), survol d'une ligne à l'autre 45 → 33 M. Le contrôle juge maintenant le travail
      en instructions (pire < 100 M, moyenne < 8 M, 95 % < 40 M : avant l'allègement 133 / 6,0 / 42,6 auraient échoué) et l'horloge
      seulement pour l'attente (pire < 40 ms, moyenne < 4 ms) ; l'essai affiche la part des cycles sur les cœurs performance.
- Contrôles 3561/3561. Essai complet (avec le correctif du survol, avant celui du ressort) : 1 échec (le ressort), survol 355/355,
  pire 24,67 ms. Les deux essais complets verts restent à faire avant `git push origin main`.

## 12/11 vers 11 h 30 — Lucarne déplaçable, mission 2
- [x] Geste et fenêtre, capsule noire : branche `lucarne-geste` (b42434f, a7cfa5f), poussée, NON fusionnée, worktree ~/dictee-mac-lucarne2. 3564/3564 ; section places de l'essai verte 3 fois ; essai complet = seulement les 2 échecs connus de main (avant les correctifs 97374b3 / be6ea24).
- [ ] Relecture indépendante (opus) sur `git diff main...lucarne-geste` : pas terminée, à relancer AVANT la fusion.
- [ ] Ne PAS livrer la branche seule : hors de l'encoche, la capsule est noire et muette (pas d'alerte visible) jusqu'à la mission 3 (verre, contenu, bannières depuis la place).
- [ ] Fusion : conflits attendus dans IlotMoteur (tousLesRessorts → ilotPose + lucarnePosee, appuiSurForme) avec les correctifs de l'essai.
- [ ] À montrer à Hugues : lâchée au milieu de l'écran (jusqu'à ~450 pt sous l'encoche), la Lucarne retourne dans l'encoche (place la plus proche).

- [x] (12/11 11 h 45) Nom VOXILE confirmé par Hugues. À faire : renommage (app, textes, manuel, README, dépôt) en gardant l identifiant com.hugues.dictee (autorisations macOS).

## Plus tard (idée de Hugues, 12/11 15 h) — après tout le reste
- Synchroniser avec l iPhone : notifications sur le téléphone (« dans 5 minutes, tu as un rappel »…). Second chantier, à ouvrir seulement quand tout ce qui est décidé est fini et la vidéo faite.

## Concentration dans l'îlot (12/11) — branche concentration-ilot (worktree ~/dictee-mac-concentration)
Demande de Hugues : choisir depuis l'îlot un mode de Concentration (Ne pas déranger, Travail, Personnel, Sommeil, Réduire les
interruptions) et une durée (1 h, jusqu'à ce soir, jusqu'à l'arrêt), voir le mode actif dans l'îlot, l'arrêter d'un clic.
Maquette validée : design/maquettes/ilot-concentration.html (étapes 1 à 7 ; l'étape 8, Lucarne en verre dans un coin, attend la
mission 3 de la Lucarne déplaçable, pas sur main).
- [x] Recherche : allumer (Raccourcis : action « Définir la concentration », `shortcuts run`), lire (INFocusStatusCenter, fichiers de
      ~/Library/DoNotDisturb, service privé, raccourci « Concentration actuelle ») ; preuves sans rien changer au système
- [x] DicteeCore/ConcentrationIlot.swift : modes, durées, état, textes, raccourci (plist), commandes, lecture de `shortcuts list` ; contrôles
- [x] Dictee/ConcentrationSysteme.swift : la couche système injectable (lister, signer, ouvrir, lancer) + le faux des essais
- [x] Dictee/IlotConcentration.swift : contrôleur (raccourci guidé au premier clic, fin de durée = un seul réveil), rond du Centre,
      carte des modes, carte « où en est le mode », aile, bannières ; accroches d'une ligne ailleurs
- [ ] Essai `--ilot-essai` section Concentration (vrais NSEvent, fausse couche) ; rendus ilot-33* ; relecture opus ; commits, push
## 12/11 après-midi — App de bureau (fenêtre principale) d'après lucarne-app-final.html — branche app-bureau (~/dictee-mac-bureau)
- [x] DicteeCore `Bureau.swift` : apparence (clair/sombre/auto, soleil/lune), tuiles d'Aujourd'hui (anneau = part du record, temps gagné,
      prochain rendez-vous, dernière note, rappels, étagère), catalogue Découvrir, calques des illustrations, ressort en temps, barres de
      l'onde ; 39 contrôles purs (3600/3600).
- [x] Palette adaptative (clair/sombre) pour les pages reprises ; interrupteur natif (vert) ; les panneaux de l'encoche restent darkAqua.
- [x] Fenêtre 900 × 560 (min 820 × 520) : barre d'onglets en verre (Aujourd'hui · Découvrir · Réunions · Réglages) centrée sur les feux
      (26 pt, vérifié), soleil/lune. Sous-pages : Aujourd'hui › Dictées / Ta journée / Bibliothèque ; Réglages › Dictée / Mots / Ce
      qu'elle montre / Confidentialité. Les destinations de l'îlot (`Onglet`) y mènent toutes.
- [x] Cartes d'accueil en verre : Bonjour + 5 cartes (fn, micro, écrire, clé, essai), scènes animées en ressorts depuis les 11 PNG de
      Hugues (Resources/Illustrations, LISEZ-MOI.md), vidéos de contrôle `--rendu-premier-lancement` (design/rendus-bureau/accueil).
- [x] Rendus `--rendu-fenetre` : 14 écrans × clair/sombre dans design/rendus-bureau (hors git).
- [x] Retrait : FenetreVue, ReglagesVue, RenduFenetre, ChoixReglage, LigneReglage.
- [x] Relecture opus (16 points) : ordre des cartes de la maquette + « Plus tard », contraste du texte en clair, Réglages qui défile
      jusqu'aux mises à jour, Aujourd'hui recalculé chaque minute et plus du tout fenêtre cachée, un seul accès au calendrier, « Essayer »
      seulement fonction allumée, minuteries arrêtées fenêtre fermée, bande du haut qui déplace la fenêtre, ménage.
- [ ] À vérifier par Hugues dans l'app (impossible sans fenêtre visible) : clic sur les 4 onglets et le soleil, déplacer la fenêtre par
      la bande du haut, le verre réel, les interrupteurs verts.
- [ ] À trancher : « Essayer » du Centre, des Réunions et de la Lecture ; « Changer sa place » (Lucarne déplaçable pas dans main) ;
      le doigt 1c (vidéo accueil-3-anime.mp4).

## Voix et rappel dans l'îlot (12/11 soir) — branche voix-rappel (worktree ~/dictee-mac-voix)
Demande de Hugues : quand il dicte une note ou un rappel, une onde de voix vivante ; à la fin une carte (coché, date, titre, petit
résumé) qui propose de l'envoyer dans Rappels ou dans Notes. Maquette : design/maquettes/ilot-voix-rappel.html (9 étapes).
- [x] DicteeCore/VoixIlot.swift : genre en direct (« Lucarne, rappelle-moi… » / « Lucarne, note… »), commande note, titre, résumé,
      date, état d'envoi, onde (niveaux réels du micro sur les ressorts de NiveauxVoix), mesures ; contrôles purs
- [x] Dictee/IlotVoix.swift : l'écoute (onde + libellé), la carte de fin, Envoyer / Annuler / Copier ; accroches d'une ligne ailleurs
- [x] Rappels : la carte remplace « Rappel ajouté » pour « Lucarne, … » ; « ✓ Dans Rappels » si déjà parti, sinon le bouton (un clic =
      la réponse « Oui » d'avant) ; Notes : l'AppleScript existant (« Vers Notes » des Outils), autorisation au premier clic
- [x] Essai `--ilot-essai` (section voix, vrais clics, faux Rappels et fausses Notes), rendus ilot-34* et lucarne-ecran-voix-*
- [x] Relecture opus, commits, push (pas de fusion)
- Résultats : 3914/3914 contrôles ; `--ilot-essai` complet (release) tout vert, 1337 ok ; section voix 38 ok (3 fois verte) ; 19 écrans × 6 places
  de la Lucarne en verre verts ; `defaults read Dictee` vide. Rendus : design/rendus-ilot/ilot-34*, design/rendus-lucarne/lucarne-ecran-voix-*.
- [ ] À vérifier par Hugues dans l'app (impossible dans l'essai : vrai micro, vraie reconnaissance en direct) : fn tenue + « Lucarne,
      rappelle-moi demain à 13 h… » → l'encoche se range, l'onde suit la voix ; 1er « Envoyer dans Rappels » (fenêtre de macOS) ;
      1er « Envoyer dans Notes » (autorisation Automatisation pour Notes).
- [ ] À trancher : « Modifier » de la maquette remplacé par « Annuler » (pas d'éditeur de rappel dans l'îlot) ; le titre et le résumé
      sont tirés du texte sur le Mac (sans IA) ; mains libres : l'encoche garde ✕ ✓, seule la carte de fin vient.
- [x] (12/11 soir, après la fusion de314ea) Les deux points laissés : Notes lent ou en échec sans refus → « Réessayer » et « Notes n'a pas
      répondu » (seuls -1743/-1744 donnent « Autoriser dans Réglages ») ; dictée prise par l'îlot sans commande lue → jamais collée, « Je
      n'ai pas compris » et la phrase avec « Copier » (même arrivée après le filet de 20 s). 3920/3920 contrôles, essai complet vert (1342).

## Mot d'appel « Voxile » + verre vraiment transparent (12/11 soir) — branche verre-transparent (worktree ~/dictee-mac-verre2)
Retours de Hugues (20 h 50, sur a8a2aad installé) : « Lucarne, rappelle-moi demain à 13 h… » collé dans le Terminal (journal : Groq a
écrit « Lucas, rappelle-moi… ») ; puis décision : « il faut l'appeler par le nom de l'application » → le mot d'appel est VOXILE, et lui seul.
Et le verre : « vraiment beaucoup plus transparent ».
- [x] Mot d'appel : « Voxile » seul (Lucarne et Verbe = texte normal) ; graphies qui se disent pareil (clé phonétique) = le mot ;
      à une lettre de clé (« Boxile », « Voxel », « Fox île ») = seulement pour une commande complète, sinon collé.
- [x] Biais : « Voxile » en tête du prompt de Whisper (premier morceau) et dans les mots de SpeechAnalyzer (contextualStrings).
- [x] Mesures `say` → Groq (`--transcrire`) : sans biais « Voxil, … » (3 voix sur 3), avec biais « Voxile, … » (3/3).
- [x] Textes qui apprennent le mot d'appel : Découvrir (tuile Rappels, scène animée).
- [x] Essai : section Lucarne (Lucarne n'est plus un mot d'appel, « Voxil » l'est) ; contrôles purs.
- [x] Verre : une capture du vrai verre (sonde jetable, design/rendus-lucarne/verre-reel-sonde.png) : le `.clear` de macOS est un dépoli
      gris qui efface la page derrière. Voile 0 ; couche du verre système claire et atténuée (0,35 pilule, 0,6 Centre et cartes) ; liseré
      plus marqué ; halo plus dense ; faux verres calés sur la capture (Terre, page blanche, vidéo + Bloc-notes) ; essai « forme jamais
      noire, aucune couche opaque sous le contenu » sur 20 écrans × 6 places (au plus 18 % couvert ; un voile de 0,95 le fait échouer).
- [ ] À juger par Hugues sur l'app installée : la pilule à 0,35, le Centre à 0,6 (juste milieu) ; les libellés gris du Centre restent
      faibles sur une page blanche pleine de texte.
- [x] Relecture opus appliquée : deux mots d'un trait seulement s'ils se disent exactement « Voxile » ; un mot proche seulement suivi d'une
      ponctuation ET d'une demande en toutes lettres (« Voici le rappel… », « Faux cils : … » restent collés) ; « Voxile » dans le prompt de
      la dictée seulement ; séparateurs comme avant (tiret long, guillemet fermant), NFC ; essai du verre : message à part si le rendu échoue.
      Refusé, noté : un premier morceau réduit à « Voxile » n'est pas filtré comme fantôme (il casserait « Voxile, » + pause + demande).
- [x] Vérifié : build release ; 3966/3966 contrôles ; `--ilot-essai` complet tout vert (1376 ok) ; `defaults read Dictee` vide.
      Noté : « aucun à-coup » (survol des Dictées, molette) oscille autour de 100 M instructions, AUSSI sur main a8a2aad (108,0 M mesuré
      dans la même série) : pas une régression de la branche.
- [x] Push de la branche (pas de fusion, pas d'installation).

## Ménage rapide, gains rapides de docs/audit-dette-technique.md § 7 (12/11 soir) : branche menage-rapide (worktree ~/dictee-mac-menage)
Arrêté après l'étape 1 sur demande (nouvelles demandes de Hugues, dont le renommage en Voxile, qui touchent beaucoup de fichiers).
- [x] 0. Point de départ (main 9fcc1dc, hors git dans le scratchpad `menage-ref/`) : build release à neuf en 175 s, **27 avertissements
      distincts**, tous dans nos sources (13 `Text + Text`, 9 de concurrence, `NSText?` inutile, `var copie`, `echec` en tuple) ;
      3972/3972 contrôles ; rendus de référence ilot (286), lucarne (60), encoche, reunion, journee, panneau, filet, fenetre (38),
      premier-lancement (33, dont des MP4 : 311 s), mise-a-jour, icones ; binaire de référence gardé (`Dictee-ref`).
      Pas d'étiquette `avant-refactor` (la référence est le commit 9fcc1dc). Essai complet pas chronométré (arrêt demandé avant).
      Noté : les rendus ne sont pas identiques au bit près d'une passe à l'autre avec LE MÊME binaire (bureau-19 mises à jour,
      2 lucarne sombres, et parfois quelques pixels d'écart 1/255 sur d'autres) : comparer avec une 2e passe de référence.
- [x] 1. Bug du secours Apple (692192b) : `Premiere` passe dans DicteeCore, `RelaisDictee.texteDuMac` (1,5 s) remplace le
      `withTaskGroup` de `DictationController.utiliserLeSecours`. Contrôle avec une reconnaissance factice qui ne rend jamais la main :
      la dictée rend la main en 1,51 s ; reconnaissance rapide : 0,06 s. Filet : build release sans nouvel avertissement (les mêmes 27) ;
      3975/3975 contrôles ; rendus ilot et lucarne identiques à la référence (2e passe : 0 écart ; 1re passe : 1 à 2 673 pixels à 1/255,
      bruit vérifié en relançant le binaire de référence 3 fois) ; les autres rendus identiques ; `defaults read Dictee` vide.
      Pas d'essai complet (aucune section de l'essai ne passe par le relais ; demandé de s'arrêter). Pas fait non plus : prouver que le
      contrôle échoue avec l'ancien code (le mécanisme est celui de la leçon du 09/11).
- [x] 2. Zéro avertissement (les 27 ci-dessus, dont IlotNotifications:69, Nettoyer:8, ReunionsFenetre:222/300, IlotEtagere:702,
      IlotVues:617, IlotPieces:397, Transcrire:128), sans `@unchecked` ni `nonisolated(unsafe)` nouveaux. Reprise le 13/11 sur la
      branche `menage-2` (worktree ~/dictee-mac-menage2, depuis main a8a3cc5) : build release à neuf de a8a3cc5 = 27 avertissements
      distincts (les mêmes), après = **0** ; 3993/3993 contrôles. `Text + Text` → `Text("\(Text(…))…")` (13), `keyframeAnimator` lit
      des valeurs prises dans `body` (2), `fondu` `nonisolated`, `[weak self]` sur les `MainActor.run` (2), `let ok`, `@Sendable func
      valeur`, `.echec(let message, let detail)` (même sortie), `currentEditor()` sans transtypage, `hacheur.finalize()`.
- [x] 3. Vrai code mort (§ 3 de l'audit), vérifié par grep dans tout le dépôt avant chaque suppression ; corriger la doc de
      `Settings` (secours) et `--lecture-essai` → `--lecture-test` dans ce fichier. Fait (grep sur tout le dépôt et sur toutes les
      branches non fusionnées : aucune n'ajoute d'appel) : retirés `GeoIlot.demiLargeur`, `AideTouches` (0 appel, même dans son fichier),
      `TraceSonore`, `ArbitrageIlot.etage`, `ModeleWhisper.defautSelonMesures` + `seuilLatenceMs` (appelés seulement par les contrôles :
      8 contrôles retirés, 2 messages raccourcis, 3993 → 3985, rien d'autre ne change). `TracesDeSon` n'existait déjà plus.
      Gardés : `NavigationBasse`, `LienNavigation`, `BarresDeSon`, `TexteEnDirect`, `BoutonFilet` (appelés) ; `ChoixMotsPrompt.classer`
      et `BudgetReunion.restantPourReunion` (une ligne chacun, porte d'entrée des contrôles vers une logique vivante : `notes`, le
      budget) ; « goutte » (commentaires). Doc du secours posée sur `secoursApple` ; `--lecture-essai` (ligne 100) : fondu dans
      `--ilot-essai` (7c2a74e), pas renommé `--lecture-test` (qui existe déjà à côté) ; spec-v1 ne cite plus la fonction retirée.
- [x] 4. Durées de vie : FSEvents de `SurveillanceClaude` (IlotClaude.swift, `retain: nil` aujourd'hui), `KeyMonitor`
      (`CFMachPortInvalidate` + `isolated deinit`, `Log.ecrire` hors du rappel du tap), `tolerance` sur les `Timer` de l'app
      (AppDelegate, MiseAJourControleur ×2, PriseEnMain, IlotLucarne, ReunionController ; pas la minuterie d'animation de l'essai).
      Fait : le flux FSEvents retient la surveillance (`retain`/`release` dans le contexte) ; `KeyMonitor.arreter()` invalide le port,
      `isolated deinit` l'appelle, les 2 lignes de journal du rappel partent après lui (`noterApres`) ; tolérances : autorisations 0,5 s,
      relevé des mises à jour 60 s (période 600 s), bande de mise à jour 0,5 s, prise en main 0,2 s, fin de note 0,05 s ;
      ReunionController l'avait déjà (0,3 s). Build sans avertissement, 3985/3985. Essai jetable (non commité) : 20 branchements /
      débranchements de `SourceClaude` pendant qu'un écrivain ajoute une ligne toutes les 2 ms, 3 fois : aucun plantage, la
      surveillance livre encore après (≈ 1 180 lignes reçues après le dernier branchement), journal temporaire seulement.
- [x] 5. `DossierVerbe.url(_:)` (≈ 20 chemins « Library/Application Support/Dictee » écrits en dur) ; `MagasinJSON<T>` dans DicteeCore
      pour Rappels, Étagère, Notes, Bibliothèque, Concentration, Réveil (même format : chaque type garde ses `depuis`/`donnees`),
      écriture atomique créée directement en 0600, échec tracé ; journal en 0600 ; contrôle qui relit un fichier au format actuel.
      Fait (DicteeCore/MagasinJSON.swift) : `DossierVerbe` (`url`, `preparer` quand le dossier doit exister, `relatif` repris par la
      désinstallation) remplace les 17 chemins écrits en dur ; `MagasinJSON<Valeur: FichierJSON>` + `FichierPrive.ecrire` (fichier
      temporaire ouvert en 0600 puis renommé) ; les 6 magasins deviennent des `typealias` (mêmes noms, mêmes noms de fichiers, mêmes
      lignes au journal). Écarts voulus, invisibles : le dossier est créé à la première écriture (plus à la simple lecture du chemin) ;
      un 2e fichier illisible remplace le `.abime` précédent pour les 6 (avant : seule la Concentration ; les autres laissaient le
      fichier abîmé en place, écrasé à l'écriture suivante) ; une écriture ratée laisse une ligne au journal. Journal : créé en 0600,
      un ancien 0644 y est ramené à la première ligne, `dictee.log.1` aussi. Contrôles : 19 nouveaux (fichiers au format actuel écrits
      à la main pour rappels, notes indentées, réveil, concentration, étagère, relus tels quels ; réécrits = mêmes octets, 0600 ;
      `.abime`, oubli, échec tracé sans le contenu, en mémoire), 4003/4003. Laissés : l'historique, l'usage Groq, le lexique, les
      expressions et les réunions gardent leur propre écriture (pas dans la liste ; à faire au même modèle).
- [x] Essai complet `--ilot-essai` (au moins après les étapes 4 et 5), sous le verrou du scratchpad. Fait le 13/11 sur 662e291
      (écran allumé tout du long, charge ≈ 2,5) : **1394 ok, 0 échec, 1053 s**. Sections : `places` 115 ok, `dictee` 8, `reveil` 82,
      `concentration` 59, toutes vertes ; `bibliotheque` : 11 échecs en cascade au 1er passage (vrais clics, à partir de « Retirer »),
      puis verte 2 fois sur 2 avec le nouveau binaire ET 2 fois sur 2 avec celui de main (bruit, pas le ménage). Rendus contre le
      binaire de main a8a3cc5 : îlot 286/286, journée 11/11, réunions 18/18 identiques au pixel ; fenêtre 56/62, les 6 autres sont
      les Réglages, qui affichent l'heure de la dernière vérification (« Vérifiée aujourd'hui à 10:40 » / « 10:41 », vu à l'œil) :
      ils diffèrent aussi entre deux passes du binaire de main. `defaults read Dictee` : absent. Branche poussée, NON fusionnée.

## Retours de Hugues du 12/11, 23 h 30 (sur main 9fcc1dc) : branche retours-23h (worktree ~/dictee-mac-retours, depuis texte-groq e33ff77)
Un commit par point, poussé, NON fusionné, NON installé.
- [x] 1. Dictée à la place de la Lucarne invisible : cause NON reproduite (câblée comme l'app, vidéo en cours, 4 places, fenêtres
      visibles : la pilule reste là ; chez Hugues, la fenêtre de la dictée était bien posée à la place de la Lucarne). Le journal dit
      maintenant où la dictée s'affiche et qui la range (fichier:ligne) ; filet qui remet la fenêtre devant ; la vidéo mise en pause
      par la dictée reste dans la pilule (miniature + pause) ; texte rogné à la pilule. Essai `DICTEE_ESSAI_SEUL=dictee`.
- [ ] 1bis. Hugues : dicter avec la Lucarne en haut à droite, une vidéo en cours ; si rien ne s'affiche, envoyer les lignes
      « dictée : affichée… / rangée (…) / fenêtre absente… » du journal (elles diront la cause).
- [x] 2. Journal : les lignes 10 h-14 h étaient ses vraies dictées (vérifié) ; les lignes d'essais s'arrêtent à 7 h 15 (5313a89).
      Verrou de plus : hors d'un .app, journal toujours à part.
- [x] 3. App de bureau : tuiles bornées (150-196 / 190-250 pt), page qui défile si trop basse, 760 pt sans troncature ; rendus
      bureau-20 à 23 (hors git) à 760×600, 900×920, 1200×900.
- [x] 4. Miniature de capture à ses proportions (38 pt de haut, ≤ 64 de large, 192 px), coins de 6 pt ; ilot-14e/14f, lucarne-ecran-capture.
- [x] 5. Son des réunions gardé par défaut (Hugues n'avait jamais touché le réglage) ; « Télécharger l'audio » (toute la réunion),
      flèche par passage (existait). Les anciennes réunions n'ont plus leur son.
- [x] 6. Voxile partout (Voxile.app, icône n° 6, textes, README) ; Verbe.app se renomme seule ; Voxile range l'ancienne Verbe.app ;
      release.sh fait Voxile-x.dmg + Verbe-x.dmg (passage pour les Verbe 0.3.x). Gardés : com.hugues.dictee, « Concentration Verbe ».
- [ ] 6bis. Avant la prochaine release : monter VERSION (> 0.3.2) sinon les Verbe installées ne verront pas la mise à jour ; joindre
      les 4 fichiers de release.sh.
- [x] 7. Curseur « Verre » au bas du Centre (Lucarne en verre seulement), synchronisé avec les Réglages ; essai `DICTEE_ESSAI_SEUL=verre`.
- [x] 8. Barres de la lecture en pause : état deviné « joue » jamais corrigé (revient après 2 s sans confirmation du système) et barres
      qui lisaient un état ancien (observent la lecture) ; essai qui échouait avant correction.
- [ ] Hugues : vérifier dans l'app (impossible dans l'essai) : (1) la pilule pendant fn en haut à droite avec une vidéo ; (6) l'icône,
      le nom dans la barre des menus, que les autorisations (micro, accessibilité, surveillance de l'entrée) tiennent après le
      renommage ; (7) le curseur Verre en vrai verre (le rendu ne dessine pas le vrai verre) ; (8) une vidéo YouTube mise en pause
      puis l'îlot déplacé ; (5) une réunion : télécharger un passage et toute la réunion.
- Vérifications (13/11 nuit) : build release sans avertissement nouveau ; 3992/3992 contrôles ; sections d'essai `dictee`, `verre`,
  `places` vertes (places deux fois) ; `defaults read Dictee` vide. Essai complet n° 1 (vers 1 h) : 1393 ok, 1 échec (« alerte du
  minuteur en haut à droite… boucle secousse », ressort du bourdonnement ; la section seule est verte). Essai complet n° 2 (vers 2 h) :
  écran éteint/rallumé (pmset) puis « En faire un rappel » à 2 h du matin (« demain » = aujourd'hui avant l'aube) : l'alerte du rappel
  reste et 58 échecs en cascade dans des sections non touchées. À relancer de jour avant la fusion.

## 13/11, 11 h : fenêtre qui déborde, vraie app dans le Dock, Quitter depuis l'îlot (branche `bureau-dock`, poussée, non fusionnée)
- [x] 1. Fenêtre de bureau : cause = NSHostingView (sizingOptions par défaut, `.intrinsicContentSize`) qui faisait grandir la
      fenêtre jusqu'à la taille idéale de la page (réunion longue ~1 480 pt, Découvrir ~1 580 pt), sous le bas de l'écran.
      `sizingOptions = []` + fenêtre bornée à l'écran visible à l'ouverture et quand les écrans changent (`CadreFenetre`).
      Contrôle dans `--rendu-fenetre` sur la VRAIE fenêtre (900×847, 760×600, 1200×900, 4 onglets, réunion de 48 passages) :
      6 échecs avant, 0 après ; images `design/rendus-bureau/taille-*.png` (hors git). `DICTEE_RENDU_SEUL=taille` pour lui seul.
- [x] 2. App normale fenêtre ouverte (Dock, menu, ⌘Q), arrière-plan fermée ; arrière-plan aussi quand la fenêtre est sur un autre
      bureau / derrière une app plein écran (pour l'îlot) ; fenêtre ouverte au lancement d'un clic (pas à l'ouverture de session, ni
      au premier lancement, ni à une relance par Voxile : `open --env VOXILE_RELANCE=1`). Règle `PresenceDock` (DicteeCore).
- [x] 3. « Quitter Voxile » (discret, symbole marche/arrêt) dans l'en-tête de la page Outils, à côté de « ‹ Centre » ; même sortie
      que ⌘Q. Essai : vrai clic → sortie demandée (capturée), clic à côté → rien. `DICTEE_ESSAI_SEUL=outils` ajouté.
- [ ] Hugues, une fois installée : (a) Réunions, une longue réunion : défiler jusqu'au dernier passage, champ « Demander » visible ;
      (b) fenêtre ouverte : icône + point dans le Dock, ⌘Q, clic droit › Quitter ; fermée : l'icône part ; épingler l'icône, Voxile
      quittée, un clic dessus : la fenêtre s'ouvre ; (c) PLEIN ÉCRAN : fenêtre FERMÉE puis Terminal en plein écran, dicter (fn) :
      l'îlot doit être là ; puis fenêtre OUVERTE, aller sur le Terminal en plein écran, dicter : l'îlot doit être là aussi (sinon
      envoyer les lignes « Dock : … » du journal) ; (d) Centre › Outils › « Quitter Voxile ».
- Vérifications (13/11, midi) : build release sans avertissement ; 4 018/4 018 contrôles ; `--rendu-fenetre` vert (clics + taille) ;
  section `outils` verte ; essai complet n° 1 (11 h 44, écran éteint 11 h 44-11 h 57) : 55 échecs EN CASCADE dès « En faire un
  rappel » (une alerte de rappel d'une section d'avant sonne : « rappelEtendu »), déjà vu la nuit ; le binaire de main, juste après,
  vert ; essai complet n° 2 de la branche (12 h 28-12 h 46, écran allumé) : 1 397 ok, tout vert. Dette : ce rappel qui sonne selon
  l'heure dans l'essai complet (à chercher dans le grand audit) ; `defaults read Dictee` vide.
