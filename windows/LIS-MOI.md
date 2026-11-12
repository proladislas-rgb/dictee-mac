# Verbe pour Windows

La dictée de Verbe, seule, pour un PC Windows 10 ou 11 (64 bits). Tu cliques n'importe où (mail, Word, WhatsApp, barre de recherche, terminal), tu **tiens Ctrl + ⊞** (la touche Windows), tu parles, tu relâches : le texte propre s'écrit à l'endroit du curseur.

Tout se passe dans **l'îlot**, une petite pilule noire en haut au centre de l'écran (comme la Dynamic Island de l'iPhone) :

| L'îlot | Ce qu'il montre |
|---|---|
| Au repos | un trait noir discret ; il disparaît pendant une vidéo ou un jeu en plein écran |
| Souris dessus | le geste rappelé, un bouton micro (dicter sans clavier) et ⚙ Réglages |
| Pendant que tu parles | l'icône de l'app où le texte va s'écrire, ta voix qui s'anime, le chrono |
| Après | « Écriture… » puis ✓ « Écrit » |

## Installer (2 minutes)

1. Copie `Verbe.exe` où tu veux (par exemple dans `Documents`). Rien d'autre à installer.
2. Double-clique dessus. **Windows affiche « Windows a protégé votre ordinateur »** (l'app n'est pas signée, c'est payant) : clique sur **Informations complémentaires**, puis **Exécuter quand même**. Une seule fois.
3. L'îlot s'ouvre et demande ta **clé Groq gratuite** : clique sur « Obtenir une clé gratuite » (console.groq.com › API Keys › Create API Key), copie-la, colle-la, **Enregistrer**. Verbe la vérifie, puis la garde chiffrée sur ce PC.
4. Si Windows demande l'accès au micro, accepte.

## Utiliser

| Geste | Effet |
|---|---|
| Tenir **Ctrl + ⊞**, parler, relâcher | Dicte, puis écrit au curseur |
| Toucher **Ctrl + ⊞** brièvement | Mains libres : retoucher Ctrl + ⊞ ou ✓ termine |
| **Échap** ou ✕ | Annule, rien n'est écrit |
| Souris sur l'îlot › micro orange | Dicte en mains libres, sans clavier |
| Souris sur l'îlot › ⚙ | Langue (Français, English, Auto), sons, clé Groq, Quitter |

- **Remise au propre** : les « euh » disparaissent, les corrections dites sont appliquées (« mardi, non plutôt mercredi » → « mercredi »), « à la ligne » et « nouveau paragraphe » marchent, les listes dictées (« premièrement… deuxièmement… ») deviennent des listes.
- **Selon l'app** : paragraphes dans un mail (Outlook, Gmail), ton direct dans une messagerie (WhatsApp, Teams, Slack), une seule ligne sans point final ni Entrée dans un terminal (la commande ne part jamais toute seule).
- **Rien n'est perdu** : sans réseau ou si Groq est à sa limite gratuite, l'îlot garde ta dictée et propose « Réessayer ».
- **Le presse-papiers est respecté** : ce que tu avais copié est remis après le collage, et la dictée n'entre pas dans l'historique ⊞ + V.

## Bon à savoir

- **Lancer au démarrage de Windows** (facultatif) : ⊞ + R, tape `shell:startup`, Entrée, et place un raccourci vers `Verbe.exe` dans ce dossier.
- **Quitter** : ⚙ dans l'îlot › Quitter Verbe, ou clic droit sur l'icône Verbe près de l'horloge.
- **Une app lancée en administrateur** (rare) ne reçoit pas le texte : Windows interdit à une app normale d'y écrire.
- **Le micro ne capte rien** : Paramètres › Confidentialité et sécurité › Microphone › « Autoriser les applications de bureau à accéder au microphone ». L'îlot ouvre directement ce réglage.
- **Mots à écrire exactement** (noms propres, marques) : dans `%APPDATA%\Verbe\reglages.json`, liste `Mots`, puis relance Verbe.
- **Désinstaller** : quitte Verbe, supprime `Verbe.exe` et le dossier `%APPDATA%\Verbe`.
- **Confidentialité** : le son part chez Groq pour la transcription (comme sur Mac). Le journal `%APPDATA%\Verbe\journal.txt` ne contient que des durées, jamais le texte dicté ni la clé.

## Fabriquer depuis le code (Mac ou Windows)

Il faut le SDK .NET 8. Depuis ce dossier : `./fabriquer.sh` (Mac/Linux). Le résultat : `dist/Verbe.exe`, un seul fichier autonome (≈ 65 Mo, aucun .NET à installer sur le PC). Contrôles du cœur : `dotnet run --project controles`.
