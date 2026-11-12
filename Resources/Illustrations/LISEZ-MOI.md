# Illustrations des cartes d'accueil

Les cartes du premier lancement (sous l'encoche) montrent chacune une petite scène animée, faite de pièces PNG transparentes
posées les unes sur les autres. Le code les lit ici, sous ces noms exacts ; rien d'autre à changer pour en mettre de nouvelles.

Le chiffre du nom est celui de la **série** (1 = la touche fn, 2 = le micro, 3 = écrire, 4 = la clé, 5 = l'essai). Les cartes,
elles, suivent l'ordre de la maquette : 1 le micro (2a, 2b), 2 écrire (3a, 3b), 3 la touche fn (1a, 1b, 1c), 4 la clé, 5 l'essai.

| Fichier | Série | Ce que montre la pièce | Toile d'origine |
|---|---|---|---|
| `1a.png` | 1 · La touche fn | le coin du clavier, touche fn (globe) au repos | 1536 × 1024 |
| `1b.png` | 1 | la touche fn seule, enfoncée (même place que dans 1a) | 1536 × 1024 |
| `1c.png` | 1 | l'index, posé sur la touche (même toile) | 1536 × 1024 |
| `2a.png` | 2 · Le micro | le micro | 1536 × 1024 |
| `2b.png` | 2 | les trois anneaux autour de la capsule du micro | 1536 × 1024 |
| `3a.png` | 3 · Écrire dans tes apps | la bulle de message, vide | 1536 × 1024 |
| `3b.png` | 3 | le curseur bleu, au milieu de la toile | 1536 × 1024 |
| `4a.png` | 4 · La clé Groq | la clé | 1536 × 1024 |
| `4b.png` | 4 | le champ en verre, vide | 1536 × 1024 |
| `4c.png` | 4 | la pastille verte cochée, au centre de la toile | 1536 × 1024 |
| `5a.png` | 5 · Essaie | l'onde orange, neuf barres séparées par du vide | 1536 × 512 |

## Remplacer une pièce

1. Garder la **même toile** que la pièce remplacée (mêmes proportions, même place des objets) : les pièces d'une carte se
   superposent telles quelles. Un PNG avec une vraie transparence, sans texte ni logo.
2. Réduire pour l'app (deux fois la taille affichée au plus) et copier ici sous son nom :

   ```sh
   cp ~/Desktop/Lucarne-illustrations/1a.png Resources/Illustrations/1a.png
   sips -Z 1024 Resources/Illustrations/1?.png     # carte 1 (vue de près)
   sips -Z 768 Resources/Illustrations/[2-5]?.png   # les autres
   ```

3. Vérifier la scène image par image, puis reconstruire l'app :

   ```sh
   # depuis la racine du dépôt (le rendu y lit Resources/Illustrations)
   swift build -c release
   .build/release/Dictee --rendu-premier-lancement design/rendus-bureau/accueil            # toutes les cartes + vidéos
   .build/release/Dictee --rendu-premier-lancement design/rendus-bureau/accueil --carte 3  # une seule vidéo (carte 3 : la touche fn)
   ./build.sh
   ```

## Comment elles bougent (`Sources/Dictee/AccueilScenes.swift`)

- **1 (touche fn)** : la caméra s'approche, l'index arrive en arc depuis le bord de la carte (sa base reste hors du cadre), la touche au
  repos de 1a est masquée par un creux sombre à la forme de 1b, puis 1b s'enfonce avec un petit écrasement ; un reflet glisse sur
  l'aluminium ; l'onde (5a) naît de la touche et monte, chaque barre sur son ressort.
- **2 (micro)** : le micro tourne de quelques degrés ; trois copies de 2b pulsent derrière lui, l'une après l'autre.
- **3 (écrire)** : la bulle flotte en légère perspective, le texte s'y écrit lettre à lettre, 3b (réduit de moitié) suit le texte puis clignote.
- **4 (clé)** : la clé arrive en tournant en 3D jusqu'au champ, tourne un peu comme dans une serrure, puis 4c éclot avec un anneau vert.
- **5 (essai)** : les neuf barres de 5a, découpées d'après les colonnes vides du PNG, parlent chacune sur son ressort.

Les positions (centre de la touche, de la capsule, du curseur, de la coche) sont écrites en fractions de la toile dans ce
fichier : une nouvelle pièce qui garde la même toile n'a besoin d'aucun changement. Une pièce absente : la carte montre un symbole
sobre à la place de toute sa scène. Les animations ne tournent que quand la carte est à l'écran ; « Réduire les animations » donne
une image posée.
