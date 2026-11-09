# Verbe 0.3.0

## Ce qui change depuis la 0.2.2

### Notes de réunion
- **⌥⌘N** (ou « Noter la réunion » dans le panneau des guillemets) enregistre un appel sur deux pistes : ton micro (« Moi ») et le son du Mac (« Eux »). Verbe propose aussi « Noter cet appel ? » quand une app d'appel utilise le micro. Rien ne s'enregistre sans ton clic.
- **La transcription se fait pendant l'appel.** À la fin, la note arrive en quelques secondes : une ligne « En bref », puis **Dit · Décidé · À faire** côte à côte. Les échéances sont en vraies dates, et chaque point s'ouvre sur la phrase exacte, avec qui l'a dite et à quel moment.
- **Nouvel onglet Réunions** : chaque réunion avec son « En bref » et ses actions restantes. Export en Markdown, copie pour Notion.
- Tout est gardé sur ce Mac. Le son est effacé une fois transcrit.

### Précision
- **Grand dictionnaire qui apprend.** Un lexique local, construit à partir de tes notes, aide Whisper à bien écrire les noms rares. Une correction « à l'oreille » répare les noms mal entendus. Un mot que tu corriges juste après une dictée t'est proposé dans **Mots**.
- **Filet de sécurité** : si le texte n'a pas pu être écrit, l'encoche reste ouverte avec ton texte, « Coller ici » et « Copier ». Il n'y a plus de fausse alerte dans les apps web comme Claude, Slack ou les navigateurs.

### Fenêtre
- **Nouvelle fenêtre**, plus claire :
  - les onglets sont en haut ;
  - une ligne d'état indique le nombre de dictées et de mots, le moteur, le micro et la langue ;
  - les vraies icônes des apps sont sur chaque ligne ;
  - une dictée se déplie avec « Recoller dans… », « Copier » et « Supprimer » ;
  - Réglages est rangé en sections, avec une explication par réglage.
- Verbe s'ouvre comme une app depuis Applications, Spotlight ou une icône gardée dans le Dock. L'encoche reste visible par-dessus les apps en plein écran.

### Mise à jour automatique
- Une fois par jour, Verbe regarde s'il existe une nouvelle version. Si oui, une ligne sous l'encoche propose « Installer », « Plus tard » ou « Nouveautés ». Elle n'apparaît jamais pendant une dictée ou une réunion.
- **L'installation est sans risque** :
  - Verbe vérifie la taille du fichier, son empreinte SHA-256 et sa signature ;
  - il échange l'ancienne app et la nouvelle d'un seul geste, puis se relance ;
  - si une étape échoue, rien n'est remplacé.

## Installer
1. Télécharge `Verbe-0.3.0.dmg`, ouvre-le et glisse **Verbe** sur **Applications**.
2. Première ouverture : si macOS affiche « Placer dans la corbeille / Terminé », clique **Terminé**. Va ensuite dans Réglages Système › Confidentialité et sécurité › **Ouvrir quand même**, puis rouvre Verbe.
3. Colle ta clé Groq gratuite ([console.groq.com](https://console.groq.com)) et accepte les autorisations. Pour les réunions, accepte aussi « Enregistrement du son du système ».

À partir de cette version, **Verbe se met à jour tout seul**.

Il faut un Mac Apple Silicon avec macOS 26.
