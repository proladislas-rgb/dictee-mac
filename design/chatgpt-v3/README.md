# Dictée Mac — dossier pour Claude Code

Ce dossier réunit le design de l’app, l’encoche affinée, le logo et les références HTML. Il sert à réaliser une app de dictée téléchargeable pour Mac dans le style du panneau v3 B.

## Commencer ici

1. Lire `BRIEF-POUR-CLAUDE-CODE.md`.
2. Ouvrir `document/Dictee-Mac-design-Claude-Code.docx` : document complet, version 3.
3. Examiner `visuels/01-app-dictees.png`, `02-app-mots-reglages.png` et surtout `03-encoche-affinee-reference-principale.png`.
4. Ouvrir `references-html/panneau-v3-B.html` : référence exacte de style. Le fichier C sert pour la navigation clavier et le fichier encoche-v5 pour comprendre le geste.

## Références prioritaires

Le brief de ce dossier fixe les règles et résout les divergences entre les images. Les valeurs graphiques viennent du panneau B. La nouvelle planche 03 fixe l’évolution de l’encoche. Les images sont des intentions visuelles, pas des mesures ni des composants prêts à intégrer.

Les vues 04 et 06 expliquent le contexte et les états ; leur ancienne géométrie d’encoche est remplacée par la vue 03. La vue 07 conserve la proposition d’ensemble précédente, pour contexte uniquement.

## Contenu

- `document/` : document révisé, avec les visuels et les consignes d’interaction.
- `visuels/` : sept planches PNG en résolution d’origine.
- `references-html/` : les trois maquettes utiles et l’icône Notes nécessaire à leur mise en scène.
- `sources-originales/` : copie complète du ZIP fourni au départ, pour traçabilité. Ce dossier contient aussi des pistes refusées, qui ne sont pas à reproduire.
- `MANIFESTE.json` : inventaire et empreintes SHA-256 des fichiers.

Les maquettes HTML sont des prototypes de référence, pas l’app finale. Elles peuvent utiliser une police chargée depuis Google Fonts. Le ZIP ne contient ni vidéo ni animation exportée : les mouvements sont décrits dans le document, illustrés par des états successifs et partiellement démontrés dans les HTML d’origine.

Les dossiers docs/ et tasks/ cités dans le README d’origine n’étaient pas présents dans le ZIP fourni. Ne pas supposer qu’ils existent.
