# Leçons — dictée Mac

Format : [date] | ce qui a mal tourné | règle pour l'éviter

[2026-11-09] | Maquette du panneau jugée « beaucoup trop IA » : j'ai appliqué Unslop de mémoire (fond beige, 3 cartes égales côte à côte, onglets en pilule, étiquettes en majuscules, puces, ligne de stats, point vert « prêt ») sans relire le kit de Hugues | Avant toute maquette : lire les vraies règles des 4 dépôts du kit (Unslop signs/tokens, Impeccable craft-floor + ios, Emil apple-design), et pour une app Mac suivre les codes natifs (couleurs système, mode sombre de Hugues, fenêtre Réglages standard)

[2026-11-09] | Pendant la construction, un binaire lancé depuis le shell a déclenché chez Hugues une demande d'autorisation micro au nom de « Terminal » (avec « Quitter et rouvrir », qui aurait tué la session Claude Code) | Ne jamais lancer depuis le shell un binaire qui touche au micro, à la parole, à l'accessibilité ou au clavier : tester via `open ~/Applications/Dictee.app` (autorisations au nom de l'app), et prévenir Hugues avant

[2026-11-09] | Cause réelle de l'incident ci-dessus : un `sed -i` sans `''` (macOS) a fait échouer ma chaîne de commandes, puis j'ai lancé quand même l'ancien binaire avec un option qu'il ne connaissait pas : il a démarré comme la vraie app (demande de micro au nom du Terminal) | Sur macOS : `sed -i ''`. Ne jamais enchaîner « modifier && compiler ; lancer » : lancer seulement si la compilation a réussi. L'app quitte maintenant sur toute option `--` inconnue au lieu de démarrer.
