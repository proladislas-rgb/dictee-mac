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
  - [ ] Plus tard : export Airtable, option « tout sur le Mac » (dictée Apple) au lieu de Groq, suppression d'écho par traitement du signal (aujourd'hui : par le texte), noms des participants Eux.
- [ ] Pistes suivantes à discuter (s'inspirer de l'idée, tout réécrire) : retouche de texte sélectionné à la voix (façon Grammarly), raccourcis tapés (façon TextExpander), historique du presse-papiers dans l'encoche (façon Paste), captures annotées (façon CleanShot X).

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
