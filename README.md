# Voxile

App de dictée vocale native pour Mac (anciens noms : Verbe, Dictée). Tu cliques n'importe où (mail, document, barre de recherche, Terminal), tu tiens **fn**, tu parles, tu relâches : le texte propre s'écrit à l'endroit du curseur. Tout se passe dans l'encoche du MacBook. Le texte s'affiche en direct pendant que tu parles, avec ta voix qui s'anime et l'icône de l'app où le texte va s'écrire.

- **Rapide** : texte collé environ 0,4 s après le relâchement de fn (mesuré).
- **Gratuit** : la transcription passe par Whisper large v3 turbo chez Groq, avec une clé gratuite. La dictée d'Apple, faite sur le Mac, prend le relais si le réseau manque.
- **Remise au propre** : hésitations retirées, corrections dites à voix haute appliquées (« mardi, non plutôt mercredi »), et forme adaptée à l'app (requête courte dans un moteur de recherche, texte brut sans Entrée dans le Terminal, paragraphes dans un mail).
- **Natif et léger** : écrit en Swift, rien ne tourne quand on ne dicte pas.

> État : version 0.x, en construction. Mac Apple Silicon avec macOS 26 requis.

## Télécharger

1. Télécharge `Voxile-<version>.dmg` sur la [page des versions](https://github.com/proladislas-rgb/dictee-mac/releases/latest).
2. Ouvre le fichier, glisse **Voxile** sur le dossier **Applications**.
3. Ouvre Voxile depuis Applications. **La première fois, macOS refuse** : voir « Première ouverture » ci-dessous.
4. Colle ta clé Groq gratuite quand Voxile la demande ([console.groq.com](https://console.groq.com)), puis accepte les autorisations.

**Première ouverture.** Voxile n'est pas signé par un compte développeur Apple (c'est payant, le projet reste gratuit). Sur un Mac récent (macOS 15 et après), le clic droit › Ouvrir ne suffit plus. Fais ceci, une seule fois :

1. Ouvre Voxile. La fenêtre qui s'affiche propose « Placer dans la corbeille » ou « Terminé » : clique sur **Terminé** (surtout pas sur la corbeille).
2. Ouvre Réglages Système › **Confidentialité et sécurité**, descends tout en bas : clique sur **Ouvrir quand même**, puis confirme avec ton mot de passe ou Touch ID.
3. Rouvre Voxile depuis Applications.

En une commande pour les initiés : `xattr -dr com.apple.quarantine /Applications/Voxile.app`

**Touche 🌐.** Si elle ouvre les emoji (ou autre chose que « Ne rien faire »), Voxile te le dit au premier lancement et ouvre le bon volet des Réglages : Clavier › « Appuyer sur la touche 🌐 pour » › « Ne rien faire ».

**Mises à jour.** Voxile se met à jour tout seul à partir de la 0.3 : une fois par jour, il demande à GitHub s'il existe une version plus récente et, si oui, propose **Installer** dans une ligne sous l'encoche (jamais pendant une dictée ni une réunion ; « Plus tard » repousse au lendemain, « Nouveautés » montre les notes de la version). Il télécharge le fichier, contrôle sa taille, son empreinte SHA-256 et sa signature, remplace l'app puis se relance. Si une étape échoue, rien n'est remplacé. Réglages › Compte & données › **Mises à jour** : version actuelle, bouton « Rechercher », interrupteur « Vérifier automatiquement ». Depuis une version plus ancienne que la 0.3, il faut retélécharger le fichier une fois.

**Venant de Voxile (l'ancien nom) ou de Dictée.** Voxile garde le même identifiant : autorisations, historique et dictionnaire sont conservés. Une Voxile installée qui se met à jour devient Voxile toute seule ; à la main : quitte Voxile, glisse Voxile dans Applications et ouvre-la, elle met l'ancienne `Voxile.app` à la corbeille.

**Désinstaller.** Clic droit sur les guillemets dans la barre des menus › **Désinstaller Voxile…** (ou Réglages › Désinstaller). Cela efface l'historique, les mots, les raccourcis, le journal, les réglages et la clé Groq du Trousseau, puis place l'app à la corbeille (et, après confirmation, une éventuelle ancienne `Dictee.app`). Ton éventuel fichier `~/.config/groq/.env` n'est jamais touché.

## Installer depuis le code

Il faut les outils en ligne de commande d'Apple (`xcode-select --install`). Xcode n'est pas nécessaire.

```bash
git clone https://github.com/proladislas-rgb/dictee-mac.git
cd dictee-mac
mkdir -p ~/.config/groq && echo 'GROQ_API_KEY=ta_cle' > ~/.config/groq/.env   # clé gratuite sur console.groq.com
./build.sh            # fabrique et installe ~/Applications/Voxile.app
open ~/Applications/Voxile.app
```

Au premier lancement, accepte les trois autorisations : le micro, l'accessibilité (pour écrire au curseur) et la surveillance de l'entrée (pour la touche fn). Voxile guide aussi le réglage de la touche 🌐 (Clavier › « Appuyer sur la touche 🌐 pour » › « Ne rien faire »).

Une app construite sur ton Mac n'est pas mise en quarantaine : pas d'avertissement. Reçue d'une autre personne, elle suit la procédure « Première ouverture » ci-dessus.

## Utiliser

| Geste | Effet |
|---|---|
| Tenir **fn**, parler, relâcher | Dicte, puis écrit au curseur |
| Deux appuis rapides sur **fn** | Mains libres : un nouvel appui sur fn ou ✓ termine |
| **Échap** ou ✕ | Annule, rien n'est écrit |

Un petit son et une vibration du trackpad marquent le début, la fin (texte collé) et l'annulation. Réglages › **Sons** et **Vibration** les coupent séparément. La vibration ne se sent que si un doigt est posé sur le trackpad.

Les dossiers internes gardent l'ancien nom `Dictee`, pour que rien ne se perde en changeant de nom. Ton dictionnaire (noms propres, jargon) se trouve dans `~/Library/Application Support/Dictee/mots.txt`, un mot par ligne. Pour aller plus loin, `Dictee --construire-lexique` (le binaire de `.build/release`) (dans le Terminal, ni micro ni réseau) lit tes notes et tes dossiers de projets (`.md` et `.txt`) et fabrique un grand lexique local (`lexique.json`, qui ne quitte jamais ton Mac) : à chaque dictée Voxile en glisse les mots les plus probables à Whisper, corrige à l'oreille les mots du lexique qu'il a mal entendus, et te propose dans l'onglet Mots les mots que tu viens de corriger à la main. Le journal est dans `~/Library/Logs/Dictee/dictee.log`. On n'y écrit jamais tes textes en entier.

## Dans ce dépôt

| Où | Quoi |
|---|---|
| `Sources/` | Le code Swift (`Dictee` : le produit Swift de l'app, nom interne gardé ; `DicteeCore` : la logique testée, `DicteeControles` : les contrôles) |
| `build.sh` | Fabrication et installation dans `~/Applications` (`Voxile.app`) |
| `release.sh` | Fabrique `dist/Voxile-<version>.dmg` (et son `.sha256`), plus `dist/Voxile-<version>.dmg` pour que les Voxile déjà installées passent à Voxile (version lue dans `VERSION`) |
| `docs/spec-v1.md` | La spécification technique |
| `design/` | Les maquettes validées et les captures |
| `LIS-MOI-CHATGPT.md` | Le brief design (nom, logo, animations) |
| `tasks/` | Le plan et les leçons du projet |

Vérifier la logique : `swift run DicteeControles`

Publier une version (le fichier `.sha256` se joint toujours au DMG : Voxile le compare avant de se mettre à jour) :

```bash
./release.sh
gh release create v<version> dist/Voxile-<version>.dmg dist/Voxile-<version>.dmg.sha256 dist/Voxile-<version>.dmg dist/Voxile-<version>.dmg.sha256 --target main --title "Voxile <version>" --notes-file dist/notes-v<version>.md
```

Les notes de la release s'affichent dans « Nouveautés » ; le DMG doit s'appeler exactement `Voxile-<version>.dmg` (et `Voxile-<version>.dmg` pour les anciennes Voxile, tant qu'il en reste).

## Licence

MIT. Voir `LICENSE`.
