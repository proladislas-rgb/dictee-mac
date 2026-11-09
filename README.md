# Verbe

App de dictée vocale native pour Mac (ancien nom : Dictée). Tu cliques n'importe où (mail, document, barre de recherche, Terminal), tu tiens **fn**, tu parles, tu relâches : le texte propre s'écrit à l'endroit du curseur. Tout se passe dans l'encoche du MacBook. Le texte s'affiche en direct pendant que tu parles, avec ta voix qui s'anime et l'icône de l'app où le texte va s'écrire.

- **Rapide** : texte collé environ 0,4 s après le relâchement de fn (mesuré).
- **Gratuit** : la transcription passe par Whisper large v3 turbo chez Groq, avec une clé gratuite. La dictée d'Apple, faite sur le Mac, prend le relais si le réseau manque.
- **Remise au propre** : hésitations retirées, corrections dites à voix haute appliquées (« mardi, non plutôt mercredi »), et forme adaptée à l'app (requête courte dans un moteur de recherche, texte brut sans Entrée dans le Terminal, paragraphes dans un mail).
- **Natif et léger** : écrit en Swift, rien ne tourne quand on ne dicte pas.

> État : version 0.x, en construction. Mac Apple Silicon avec macOS 26 requis.

## Télécharger

1. Télécharge `Verbe-<version>.dmg` sur la [page des versions](https://github.com/proladislas-rgb/dictee-mac/releases/latest).
2. Ouvre le fichier, glisse **Verbe** sur le dossier **Applications**.
3. Ouvre Verbe depuis Applications. **La première fois, macOS refuse** : voir « Première ouverture » ci-dessous.
4. Colle ta clé Groq gratuite quand Verbe la demande ([console.groq.com](https://console.groq.com)), puis accepte les autorisations.

**Première ouverture.** Verbe n'est pas signé par un compte développeur Apple (c'est payant, le projet reste gratuit). Sur un Mac récent (macOS 15 et après), le clic droit › Ouvrir ne suffit plus. Fais ceci, une seule fois :

1. Ouvre Verbe. La fenêtre qui s'affiche propose « Placer dans la corbeille » ou « Terminé » : clique sur **Terminé** (surtout pas sur la corbeille).
2. Ouvre Réglages Système › **Confidentialité et sécurité**, descends tout en bas : clique sur **Ouvrir quand même**, puis confirme avec ton mot de passe ou Touch ID.
3. Rouvre Verbe depuis Applications.

En une commande pour les initiés : `xattr -dr com.apple.quarantine /Applications/Verbe.app`

**Touche 🌐.** Si elle ouvre les emoji (ou autre chose que « Ne rien faire »), Verbe te le dit au premier lancement et ouvre le bon volet des Réglages : Clavier › « Appuyer sur la touche 🌐 pour » › « Ne rien faire ».

**Venant de la version 0.1.0 (Dictée).** Verbe garde le même identifiant : autorisations, historique et dictionnaire sont conservés. Ferme Dictée, ouvre Verbe, puis jette l'ancienne `Dictee.app`.

**Désinstaller.** Clic droit sur les guillemets dans la barre des menus › **Désinstaller Verbe…** (ou Réglages › Désinstaller). Cela efface l'historique, les mots, les raccourcis, le journal, les réglages et la clé Groq du Trousseau, puis place l'app à la corbeille (et, après confirmation, une éventuelle ancienne `Dictee.app`). Ton éventuel fichier `~/.config/groq/.env` n'est jamais touché.

## Installer depuis le code

Il faut les outils en ligne de commande d'Apple (`xcode-select --install`). Xcode n'est pas nécessaire.

```bash
git clone https://github.com/proladislas-rgb/dictee-mac.git
cd dictee-mac
mkdir -p ~/.config/groq && echo 'GROQ_API_KEY=ta_cle' > ~/.config/groq/.env   # clé gratuite sur console.groq.com
./build.sh            # fabrique et installe ~/Applications/Verbe.app
open ~/Applications/Verbe.app
```

Au premier lancement, accepte les trois autorisations : le micro, l'accessibilité (pour écrire au curseur) et la surveillance de l'entrée (pour la touche fn). Verbe guide aussi le réglage de la touche 🌐 (Clavier › « Appuyer sur la touche 🌐 pour » › « Ne rien faire »).

Une app construite sur ton Mac n'est pas mise en quarantaine : pas d'avertissement. Reçue d'une autre personne, elle suit la procédure « Première ouverture » ci-dessus.

## Utiliser

| Geste | Effet |
|---|---|
| Tenir **fn**, parler, relâcher | Dicte, puis écrit au curseur |
| Deux appuis rapides sur **fn** | Mains libres : un nouvel appui sur fn ou ✓ termine |
| **Échap** ou ✕ | Annule, rien n'est écrit |

Un petit son et une vibration du trackpad marquent le début, la fin (texte collé) et l'annulation. Réglages › **Sons** et **Vibration** les coupent séparément. La vibration ne se sent que si un doigt est posé sur le trackpad.

Les dossiers internes gardent l'ancien nom `Dictee`, pour que rien ne se perde en changeant de nom. Ton dictionnaire (noms propres, jargon) se trouve dans `~/Library/Application Support/Dictee/mots.txt`, un mot par ligne. Pour aller plus loin, `Verbe --construire-lexique` (dans le Terminal, ni micro ni réseau) lit tes notes et tes dossiers de projets (`.md` et `.txt`) et fabrique un grand lexique local (`lexique.json`, qui ne quitte jamais ton Mac) : à chaque dictée Verbe en glisse les mots les plus probables à Whisper, corrige à l'oreille les mots du lexique qu'il a mal entendus, et te propose dans l'onglet Mots les mots que tu viens de corriger à la main. Le journal est dans `~/Library/Logs/Dictee/dictee.log`. On n'y écrit jamais tes textes en entier.

## Dans ce dépôt

| Où | Quoi |
|---|---|
| `Sources/` | Le code Swift (`Dictee` : le produit Swift de l'app, nom interne gardé ; `DicteeCore` : la logique testée, `DicteeControles` : les contrôles) |
| `build.sh` | Fabrication et installation dans `~/Applications` (`Verbe.app`) |
| `release.sh` | Fabrique `dist/Verbe-<version>.dmg` (version lue dans `VERSION`) |
| `docs/spec-v1.md` | La spécification technique |
| `design/` | Les maquettes validées et les captures |
| `LIS-MOI-CHATGPT.md` | Le brief design (nom, logo, animations) |
| `tasks/` | Le plan et les leçons du projet |

Vérifier la logique : `swift run DicteeControles`

## Licence

MIT. Voir `LICENSE`.
