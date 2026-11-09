# Brief de réalisation pour Claude Code

## Résultat attendu

Réaliser l’interface de l’app de dictée à partir du panneau v3 B et des nouvelles planches. Conserver le caractère sombre, typographique et discret : presque rien à l’écran, mais une grande netteté. Le dossier présente l’app elle-même, pas une page marketing ou un tableau de bord.

Le produit doit être téléchargeable pour Mac. Une interface en technologies web peut être envisagée, mais l’architecture n’est pas arrêtée par ce design. Avant de promettre les fonctions système, valider dans le client installé les raccourcis globaux, l’écriture au curseur dans les autres apps, les permissions et l’intégration à l’encoche.

## Les surfaces

- Fenêtre principale : Dictées, Mots, Réglages ; trois liens texte en bas, aucune barre latérale.
- Panneau compact : le même langage visuel sous l’encoche, pour retrouver et recoller une dictée.
- Dictée en cours : une seule silhouette noire, avec bande étroite et ruban d’une ligne soudé en dessous.
- Barre des menus : petit logo en guillemets en haut à droite, à gauche des icônes système lorsque l’espace le permet.

## Encoche affinée

La planche `visuels/03-encoche-affinee-reference-principale.png` remplace la géométrie des planches précédentes. Affiner la hauteur, les raccords et les rayons sans changer le geste.

Au repos, seule l’encoche physique subsiste. Pendant la dictée, l’icône de destination occupe l’aile gauche et cinq traits sonores blancs occupent l’aile droite. Le centre caméra reste noir et vide ; le texte passe dessous, sur une seule ligne. Les mots incertains sont gris et deviennent blancs lorsque la transcription est finalisée. En mains libres, élargir seulement la bande pour ajouter Annuler et Valider.

En mode historique, remplacer la bande active par le panneau compact. Ne pas afficher l’icône Notes ni une onde sonore dans ce mode, même si une illustration en conserve un détail. Préserver la zone physique de la caméra sur l’écran réel ; ne pas copier ses dimensions depuis un PNG.

Le logo de la barre des menus reste monochrome. Le fond apparaît au survol ou à l’ouverture du panneau. Un fin trait ambre peut signaler la capture. Garder le même dessin et la même orientation des guillemets dans toute l’app ; les différences entre images ne sont pas des variantes à implémenter.

## Style de référence

| Rôle | Valeur |
| --- | --- |
| Fond extérieur | #0B0B0B |
| Surface | #1A1A19 |
| Sélection | #262624 |
| Texte principal | #ECE9E3 |
| Texte secondaire | #A8A59E |
| Texte discret | #88857E |
| Accent | #E6A04A |
| Encoche | #000000 |

SF Pro ou police système pour les commandes et la transcription en direct ; Newsreader pour l’historique et le contenu du dictionnaire. Accent ambre réservé au curseur et au petit indicateur d’activité. Surfaces unies, pas de halos ou dégradés. Un champ de recherche sans cadre ni grosse carte est prioritaire sur les légers effets de surface des illustrations.

Panneau B : 352 × 320 px, rayon 14 px, navigation basse 40 px, lignes 36 px. La fenêtre principale peut partir d’environ 960 × 640 px avec lignes de 44 à 48 px. Ces dernières dimensions sont des propositions à ajuster, pas des contraintes fixes.

## Interactions

Maintenir fn pour parler puis relâcher pour terminer. Deux appuis activent les mains libres. Échap annule. La croix annule et la coche valide. La dictée ne doit jamais déclencher Entrée dans le Terminal.

Dans l’historique, ↑ et ↓ changent la sélection. Entrée recolle vers la destination précédente seulement lorsqu’elle est disponible. L’app cible doit être conservée explicitement ; ne pas coller par erreur dans la recherche de l’app. Copier reste une action distincte. Prévoir une consultation du texte complet quand une ligne est tronquée.

Dans Mots, permettre l’ajout de noms et de raccourcis vocaux. Les propositions de nouveaux mots attendent une acceptation explicite. Réglages conserve le strict nécessaire. Le moteur et le secours Apple du brief initial restent à valider selon la configuration : ne pas annoncer le hors-ligne comme acquis.

## Animation

Ouverture et retrait : environ 180 à 220 ms, ressort amorti et interruptible. Stabilisation du texte : fondu de 100 à 140 ms lorsque le résultat final est prêt. Ne jamais retarder l’insertion pour attendre une animation. Avec Réduire les animations, utiliser un fondu bref sans expansion. Aucun mouvement décoratif au repos.

Le premier lancement comporte au plus trois étapes : montrer le geste, expliquer et obtenir les accès nécessaires, faire réussir une première dictée. Prévoir historique vide, absence de résultat, permission refusée, destination indisponible, secours indisponible et champ protégé. Conserver tout texte récupérable après un échec d’insertion.

## Ordre de travail

Commencer par les trois vues et leur navigation, puis intégrer le panneau compact et la barre des menus. Ajouter ensuite les états de l’encoche et leurs transitions. Vérifier enfin le clavier, la réduction des animations, les petits écrans et les cas d’échec. Le résultat doit utiliser de vrais composants adaptables ; les PNG ne doivent jamais servir de fonds d’interface fonctionnelle.

Ne pas reprendre les variantes refusées de `sources-originales/design/maquettes/panneau.html` et `panneau-v2.html`. Les prototypes existants peuvent simuler certaines actions : vérifier chaque comportement avant de le traiter comme une fonction opérationnelle.
