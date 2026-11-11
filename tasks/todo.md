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
- [x] Vérifié sans rien montrer à l'écran : `Verbe --lecture-essai` (18 contrôles verts avec une source de test à volume 0), `Verbe --lecture-test`, rendus `Verbe --rendu-lecture` → `design/rendus-lecture/`.
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
