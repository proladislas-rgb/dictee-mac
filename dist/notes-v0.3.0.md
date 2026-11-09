# Verbe 0.3.0

## Ce qui change
- **Mise à jour automatique.** Une fois par jour, Verbe demande à GitHub s'il existe une nouvelle version. Si oui, une ligne sobre sous l'encoche propose « Installer », « Plus tard » (rappel le lendemain) ou « Nouveautés ». Elle n'apparaît jamais pendant une dictée ni une réunion.
- **Installation sans risque.** Verbe télécharge le fichier, contrôle sa taille, son empreinte SHA-256 et sa signature, prépare la nouvelle app à côté de l'ancienne, puis les échange d'un seul geste et se relance. Si une étape échoue, rien n'est remplacé.
- **Réglages › Compte & données › Mises à jour** : version actuelle, bouton « Rechercher », interrupteur « Vérifier automatiquement » (activé par défaut). Le menu des guillemets a aussi « Rechercher les mises à jour… ».
- Depuis cette version, chaque release publie un fichier `Verbe-<version>.dmg.sha256` à côté du DMG.

## Installer
Si tu as une version plus ancienne que la 0.3, télécharge `Verbe-0.3.0.dmg` une dernière fois, ouvre-le et glisse **Verbe** sur **Applications**. Ensuite Verbe se met à jour tout seul.

Il faut un Mac Apple Silicon avec macOS 26.
