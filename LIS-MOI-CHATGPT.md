# À lire par ChatGPT : design de l'app de dictée pour Mac

## Message à coller dans ChatGPT avec ce dossier

> Tu es directeur artistique et designer produit spécialisé dans les apps Mac. Je t'envoie le dossier d'une app de dictée vocale pour Mac. Ce fichier `LIS-MOI-CHATGPT.md` explique tout ; les images sont dans `design/captures/` et les maquettes animées (à ouvrir dans un navigateur) dans `design/maquettes/`.
> Les écrans de l'encoche et du panneau sont validés : ne les redessine pas, garde-les tels quels.
> Ta mission : donner une identité à l'app. Ça veut dire le nom, le logo et l'icône, l'animation d'ouverture et le premier lancement, les petits moments animés, la palette et la typographie. Tout est détaillé dans la partie 4.
> Commence par me proposer 5 noms et 3 pistes de logo. Ensuite, quand j'en aurai choisi un, fais le reste. Pour chaque proposition, montre une image et explique en une phrase pourquoi tu as fait ce choix.

---

*La suite est le brief complet : ce qui est déjà décidé, ce qui reste à inventer et les règles à respecter.*

## 1. Le produit en une phrase

Une app pour Mac qui écrit à ta place. Tu cliques dans n'importe quel champ (un mail, un document, la barre de recherche Google, le Terminal), tu tiens la touche **fn**, tu parles et tu relâches : le texte propre s'écrit à l'endroit du curseur.

Elle est faite pour quelqu'un qui écrit presque tout en parlant, toute la journée. Les apps du même genre sont Wispr Flow et Willow Voice. On s'en inspire pour les idées, sans jamais recopier leurs dessins, leurs textes ni leur code.

## 2. Ce qui rend l'app différente

- **Rapide.** Le texte arrive en moins d'une demi-seconde après le relâchement de la touche.
- **Native Mac.** Elle est écrite en Swift, elle est légère, et rien ne tourne quand on ne dicte pas.
- **Presque invisible.** Toute l'app vit dans l'**encoche** noire du MacBook. Il n'y a pas de grande fenêtre.
- **Un dictionnaire qui apprend.** Il connaît les noms propres de l'utilisateur et en ajoute de nouveaux quand l'utilisateur corrige un mot.
- **Une mise en forme adaptée à l'endroit.** Une requête courte dans une barre de recherche, du texte brut dans le Terminal (sans jamais appuyer sur Entrée), des paragraphes et des listes dans un mail ou un document.

## 3. Ce qui est déjà décidé (ne pas remettre en cause)

### L'encoche pendant la dictée
Voir `captures/01`, `02` et `04`, ainsi que `maquettes/encoche-v5.html`, qui est animée et jouable.
- Pendant la dictée, une seule forme noire sort de l'encoche :
  - en haut, une bande avec l'**icône de l'app** où le texte va s'écrire (à gauche) et une **visualisation vivante du son** (à droite) ;
  - en dessous, soudé à la bande, un ruban d'une ligne où **le texte s'écrit en direct**.
- Les derniers mots restent gris tant qu'ils ne sont pas sûrs. Au relâchement, ils deviennent blancs et le point final s'ajoute.
- En **mains libres** (deux appuis sur fn), la bande s'élargit et affiche ✕ (annuler) à gauche et ✓ (valider) à droite.
- **Contrainte physique.** Le centre de l'encoche (environ 200 px) est la caméra : il n'y a pas d'écran à cet endroit, donc rien d'utile ne doit s'y afficher.

### Le panneau (historique, mots, réglages)
**Le style validé par l'utilisateur (« fais-le comme ça ») :** `captures/03` et `maquettes/panneau-v3-B.html`.
- Le texte dicté est écrit dans une police de livre (Newsreader), l'heure est dans la marge, il n'y a aucun cadre, et la seule couleur est un curseur ambre dans les champs.
- Le panneau descend de l'encoche et se pilote au clavier comme un lanceur : ↑↓ pour choisir, Entrée pour recoller. Ce comportement vient de `maquettes/panneau-v3-C.html`.
- Il a trois écrans :
  - **Dictées** : une ligne par dictée, avec l'heure, le texte et l'app ;
  - **Mots** : les noms à toujours bien écrire, les raccourcis dits à voix haute (« mon mail » écrit l'adresse) et les mots proposés automatiquement ;
  - **Réglages** : le strict nécessaire.

### Les goûts de l'utilisateur
- **Mode sombre.**
- **« Presque rien à l'écran, mais d'une grande netteté. »** Sa référence est la toute petite pastille de Wispr Flow pendant la dictée. Il la trouve « hyper impressionnante » parce que « c'est rien ».
- **Il a refusé :**
  - tout ce qui est « trop gros », bavard ou décoratif ;
  - tout ce qui « fait IA » : fond beige avec cartes, dégradés violets, lueurs, verre partout, pilules et bulles partout, petits titres en MAJUSCULES espacées, emoji, chiffres décoratifs. Les versions refusées sont dans `maquettes/panneau.html` et `maquettes/panneau-v2.html`, à regarder pour savoir quoi éviter.
- **Il a aimé :** le style du panneau B (texte dicté en police de livre, curseur ambre), le noir pur de l'encoche, une seule forme, le pilotage au clavier, le texte en direct.

## 4. Ce qu'on te demande d'inventer

1. **Un nom** : court, facile à dire à voix haute, disponible si possible (vérifie au moins qu'aucune app de dictée connue ne le porte), en français ou en anglais. Propose 5 noms, chacun avec une phrase qui explique l'idée.
2. **Le logo et l'icône de l'app.**
   - **Icône de l'app** (Dock, Finder, Launchpad) : la forme carrée arrondie des icônes macOS, livrée en 1024 × 1024 px. Elle doit rester lisible en 32 px et en 16 px.
   - **Icône de la barre des menus** : un dessin monochrome au trait, de 16 à 18 px de haut, qui marche sur fond clair comme sur fond sombre.
   - **Logo** : le nom écrit (le logotype) et le symbole seul. Une version claire et une version sombre.
   - **À éviter :** le micro générique, l'onde sonore cliché, l'étincelle « IA », les dégradés violets et les effets brillants.
   - **Une piste à creuser** (ce n'est pas une obligation) : l'encoche noire qui « parle », c'est-à-dire la forme de l'encoche qui s'ouvre quand on dicte.
3. **L'animation d'ouverture et le premier lancement**, la partie la plus importante. C'est ce que voit quelqu'un qui installe l'app pour la première fois, par exemple un ami à qui on l'envoie. En trois écrans au plus, elle doit :
   - montrer le geste (tenir fn, parler, relâcher) ;
   - demander les deux autorisations du Mac (le micro, et l'accessibilité pour écrire au curseur) en expliquant simplement pourquoi ;
   - faire faire un premier essai réussi.

   L'animation doit naître de l'encoche, comme le reste de l'app.
4. **Les petits moments** :
   - le son ou l'animation de début et de fin de dictée ;
   - l'état « texte collé » ;
   - l'état d'erreur (pas de réseau : la dictée d'Apple prend le relais, il faut le dire sobrement) ;
   - l'état « champ protégé » (mot de passe : le Mac interdit d'y écrire).
5. **Une palette et une typographie** cohérentes avec le noir de l'encoche, avec **une seule** couleur d'accent, et seulement si elle sert à quelque chose.

## 5. Règles de fabrication

- **Les codes d'Apple (macOS) :**
  - police système SF Pro, sauf si un choix de caractère est vraiment justifié ;
  - mouvements à ressort, interruptibles, qui partent de l'encoche ;
  - respect du réglage « réduire les animations ».
- **Méthode « Unslop »** (github.com/heydamir/unslop) :
  - un seul moment riche par écran, tout le reste calme ;
  - une seule couleur d'accent ;
  - espacements sur une grille de 4 px ;
  - aucun signe « IA ».
- **Aucun élément recopié** de Wispr Flow, Willow Voice ou d'une autre app : ni dessin, ni icône, ni texte, ni animation.
- **Livrables souhaités** : des images des écrans, et si possible des maquettes HTML animées comme celles de ce dossier, plus une page qui résume le nom, l'icône, la palette, la typographie et les animations.

## 6. Contenu du dossier

| Fichier | Ce que c'est |
|---|---|
| `captures/01-encoche-dictee.png` | L'encoche pendant la dictée (validée) |
| `captures/02-encoche-mains-libres.png` | L'encoche en mains libres, avec ✕ et ✓ (validée) |
| `captures/03-panneau-dictees-mots-reglages.png` | Le panneau, ses trois écrans : **le style validé** |
| `captures/04-encoche-scene-complete.png` | La scène entière : barre des menus, encoche, fenêtre Notes |
| `maquettes/encoche-v5.html` | L'encoche animée : touche D tenue pour dicter, deux appuis pour les mains libres |
| `maquettes/panneau-v3-B.html` | Le panneau dans le **style validé** |
| `maquettes/panneau-v3-C.html` | Le comportement du panneau : il sort de l'encoche et se pilote au clavier |
| `maquettes/pastilles.html` | Premières pistes de pastille (la B, l'encoche, a été choisie) |
| `maquettes/encoche-v4-*.html`, `panneau-v3-A.html` | Pistes intermédiaires non retenues |
| `maquettes/panneau.html`, `panneau-v2.html` | **Refusées** (« trop IA », « trop gros ») : exemples de ce qu'il ne faut pas faire |

Les fichiers HTML s'ouvrent dans n'importe quel navigateur. Les chemins de ce tableau sont relatifs au dossier `design/`. `notes.png` est l'icône de l'app Notes d'Apple, utilisée seulement pour la mise en scène.
