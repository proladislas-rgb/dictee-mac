# Verbe 0.2.0

L'app de dictée s'appelle maintenant **Verbe**. Tu tiens **fn**, tu parles, tu relâches : le texte propre s'écrit là où est le curseur, dans n'importe quelle app.

## Ce qui change depuis la 0.1.0
- **Nouveau nom : Verbe.** L'app, la fenêtre, les menus et le fichier d'installation changent de nom. Rien d'autre ne bouge sous le capot : tes autorisations, ton historique et ton dictionnaire sont conservés.
- **Plus rapide.** Le texte part chez Groq dès que tu fais une pause, sans attendre que tu relâches ; les longues dictées sont découpées et envoyées pendant que tu parles ; une requête de secours part si la réponse tarde. Sur nos essais (voix de synthèse, 10 essais par cas), le délai entre le relâchement et le texte passe de 293 à 129 ms (médiane) pour une phrase de 1,5 s avec une pause avant de relâcher, et de 805 à 290 ms pour une dictée de 56 s d'une traite. Sans pause avant de relâcher, le gain est faible, dans le bruit des mesures. Ces chiffres seront à confirmer avec de vraies dictées.
- **Français par défaut.** Fini les phrases courtes comprises comme de l'allemand ou une autre langue. Le réglage Langue permet de passer en anglais ou en automatique.
- **AirPods et changement de micro.** La dictée marche avec des AirPods connectés et suit les changements de micro. Nouveau réglage Micro : Automatique, Micro du système, ou un micro précis.
- **Touche 🌐 guidée.** Si ta touche 🌐 ouvre les emoji (ou autre chose que « Ne rien faire »), Verbe te le dit au premier lancement, ouvre le bon volet des Réglages et vérifie le réglage, puis te fait essayer un double appui sur fn. Une ligne discrète dans les Réglages le rappelle si besoin.
- **Adresses mail et web dictées.** « jean point dupont arobase gmail point com » s'écrit maintenant jean.dupont@gmail.com, et « www point sillonia point fr » s'écrit www.sillonia.fr : sans espace, en minuscules, lettres et chiffres épelés recollés, « tiret » et « tiret du bas » compris. C'est une règle locale (elle marche même sans la remise au propre) et la remise au propre connaît aussi la consigne. Tes raccourcis vocaux (« mon mail », « mon adresse mail »…) sont appliqués après, et la ponctuation autour (« … à mon mail, merci ») est conservée. Limite : si Whisper entend un autre nom que celui dicté, seul un raccourci vocal peut le corriger.
- **Un petit son et une vibration** marquent le début de la dictée, le texte collé et l'annulation. Les sons sont fabriqués par Verbe (rien n'est copié ailleurs). Deux réglages séparés, « Sons » et « Vibration », activés par défaut. La vibration ne se sent que si un doigt est posé sur le trackpad.
- **Installation corrigée.** Sur un Mac récent, « clic droit › Ouvrir » ne suffit plus pour une app non signée par un compte développeur Apple. Les consignes sont réécrites (voir plus bas).
- **Désinstaller Verbe…** retire aussi une éventuelle ancienne `Dictee.app` d'Applications, après confirmation.

## Installer
1. Télécharge `Verbe-0.2.0.dmg`, ouvre-le et glisse **Verbe** sur **Applications**.
2. **Première ouverture.** macOS bloque l'app une fois (elle n'est pas signée par un compte développeur Apple). La fenêtre propose « Placer dans la corbeille » ou « Terminé » : clique sur **Terminé** (surtout pas sur la corbeille). Ouvre ensuite Réglages Système › Confidentialité et sécurité, tout en bas : **Ouvrir quand même**. Rouvre Verbe.
   En une commande, pour les initiés : `xattr -dr com.apple.quarantine /Applications/Verbe.app`
3. Colle ta clé Groq gratuite ([console.groq.com](https://console.groq.com)) et accepte les autorisations.

Il faut un Mac Apple Silicon avec macOS 26.

## Si tu as la 0.1.0 (Dictée)
Ferme Dictée, ouvre Verbe, puis jette l'ancienne `Dictee.app`. Les deux ont le même identifiant, elles ne peuvent pas tourner ensemble.

## À savoir
- Version 0.x : elle évolue vite.
- Pour désinstaller : clic droit sur les guillemets de la barre des menus › Désinstaller Verbe….
