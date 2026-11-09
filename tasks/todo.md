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
- [ ] Lot 8 — Dictionnaire qui apprend (corrections, Contacts), ouverture au démarrage.
- [ ] Lot 9 — Vraie app à installer / désinstaller (demande de Hugues 09/11 : « je peux pas l'ajouter comme une app que je télécharge, je la supprime ») :
  fichier d'installation Dictee.dmg (glisser dans Applications), icône provisoire en attendant le logo ChatGPT, premier lancement qui demande la clé Groq (rangée dans le Trousseau) et les autorisations,
  menu « Désinstaller Dictée… » qui efface aussi réglages, historique, journal et clé ; versions publiées sur GitHub (Releases). Pas de compte Apple payant (décision de Hugues 09/11) : signature ad hoc stable, mode d'emploi « clic droit › Ouvrir » pour un ami.
- [x] Passage en open source (Hugues 09/11) : sortir docs/etude-apps.md du dépôt (copie dans le second cerveau), remplacer le mail perso des maquettes, licence MIT, historique repris à neuf (sauvegarde locale de l'ancien), dépôt passé en public.
- [ ] Lot 8 bis — « Entraînement » (demande de Hugues 09/11 : « l'alimenter avec un dictionnaire… un tas de mots compliqués, dans différentes langues ») :
  grand lexique local (milliers de mots) construit depuis les sources de Hugues ; à chaque dictée, ~50 mots les plus probables envoyés à Whisper (limite ≈ 224 jetons) ;
  correction phonétique après Groq (« Sionia » → « Sillonia ») sur tout le lexique ; banc d'essai mesuré (phrases difficiles FR/EN/autres langues, voix de synthèse + vraies dictées) avant/après.
Chaque lot : construit, essayé pour de vrai sur le Mac, poussé sur GitHub.

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
