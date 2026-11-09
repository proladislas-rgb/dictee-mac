# Dictée

App de dictée vocale native pour Mac. Tu cliques n'importe où (mail, document, barre de recherche, Terminal), tu tiens **fn**, tu parles, tu relâches : le texte propre s'écrit à l'endroit du curseur. Tout se passe dans l'encoche du MacBook. Le texte s'affiche en direct pendant que tu parles, avec ta voix qui s'anime et l'icône de l'app où le texte va s'écrire.

- **Rapide** : texte collé environ 0,4 s après le relâchement de fn (mesuré).
- **Gratuit** : la transcription passe par Whisper large v3 turbo chez Groq, avec une clé gratuite. La dictée d'Apple, faite sur le Mac, prend le relais si le réseau manque.
- **Remise au propre** : hésitations retirées, corrections dites à voix haute appliquées (« mardi, non plutôt mercredi »), et forme adaptée à l'app (requête courte dans un moteur de recherche, texte brut sans Entrée dans le Terminal, paragraphes dans un mail).
- **Natif et léger** : écrit en Swift, rien ne tourne quand on ne dicte pas.

> État : version 0.x, en construction. Mac Apple Silicon avec macOS 26 requis.

## Télécharger

1. Télécharge `Dictee-<version>.dmg` sur la [page des versions](https://github.com/proladislas-rgb/dictee-mac/releases/latest).
2. Ouvre le fichier, glisse **Dictee** sur le dossier **Applications**.
3. Ouvre Dictée depuis Applications. La première fois, fais clic droit › **Ouvrir** (voir ci-dessous).
4. Colle ta clé Groq gratuite quand Dictée la demande ([console.groq.com](https://console.groq.com)), puis accepte les autorisations.

**Première ouverture.** Dictée n'est pas signée par un compte développeur Apple (c'est payant, le projet reste gratuit). macOS affiche donc un avertissement : clic droit sur l'app › Ouvrir › Ouvrir, ou Réglages Système › Confidentialité et sécurité › « Ouvrir quand même ». Une seule fois suffit. Règle aussi Réglages Système › Clavier › « Appuyer sur 🌐 pour » sur « Ne rien faire ».

**Désinstaller.** Clic droit sur les guillemets dans la barre des menus › **Désinstaller Dictée…** (ou Réglages › Désinstaller). Cela efface l'historique, les mots, les raccourcis, le journal, les réglages et la clé Groq du Trousseau, puis place l'app à la corbeille. Ton éventuel fichier `~/.config/groq/.env` n'est jamais touché.

## Installer depuis le code

Il faut les outils en ligne de commande d'Apple (`xcode-select --install`). Xcode n'est pas nécessaire.

```bash
git clone https://github.com/proladislas-rgb/dictee-mac.git
cd dictee-mac
mkdir -p ~/.config/groq && echo 'GROQ_API_KEY=ta_cle' > ~/.config/groq/.env   # clé gratuite sur console.groq.com
./build.sh            # fabrique et installe ~/Applications/Dictee.app
open ~/Applications/Dictee.app
```

Au premier lancement, accepte les trois autorisations : le micro, l'accessibilité (pour écrire au curseur) et la surveillance de l'entrée (pour la touche fn). Dans Réglages Système › Clavier, règle « Appuyer sur 🌐 pour » sur « Ne rien faire ».

L'app n'est pas signée par un compte développeur Apple. Si tu la reçois d'une autre personne, ouvre-la la première fois par clic droit › Ouvrir.

## Utiliser

| Geste | Effet |
|---|---|
| Tenir **fn**, parler, relâcher | Dicte, puis écrit au curseur |
| Deux appuis rapides sur **fn** | Mains libres : un nouvel appui sur fn ou ✓ termine |
| **Échap** ou ✕ | Annule, rien n'est écrit |

Ton dictionnaire (noms propres, jargon) se trouve dans `~/Library/Application Support/Dictee/mots.txt`, un mot par ligne. Le journal est dans `~/Library/Logs/Dictee/dictee.log`. On n'y écrit jamais tes textes en entier.

## Dans ce dépôt

| Où | Quoi |
|---|---|
| `Sources/` | Le code Swift (`Dictee` : l'app, `DicteeCore` : la logique testée, `DicteeControles` : les contrôles) |
| `build.sh` | Fabrication et installation dans `~/Applications` |
| `release.sh` | Fabrique `dist/Dictee-<version>.dmg` (version lue dans `VERSION`) |
| `docs/spec-v1.md` | La spécification technique |
| `design/` | Les maquettes validées et les captures |
| `LIS-MOI-CHATGPT.md` | Le brief design (nom, logo, animations) |
| `tasks/` | Le plan et les leçons du projet |

Vérifier la logique : `swift run DicteeControles`

## Licence

MIT. Voir `LICENSE`.
