# Les modes de Concentration dans l'îlot

12/11/2026 · maquette validée : `design/maquettes/ilot-concentration.html` (étapes 1 à 7 ; l'étape 8, Lucarne en verre dans un coin,
attend la Lucarne déplaçable).

## Ce que Hugues voit

- Dans le Centre, un rond « Concentration » (une lune, « Désactivée »). Un clic ouvre la carte des modes : Ne pas déranger, Travail,
  Personnel, Sommeil, Réduire les interruptions, chacun avec sa couleur ; puis « 1 h », « Jusqu'à ce soir », « Jusqu'à ce que je l'arrête ».
- Le mode lancé : l'îlot se replie, la bannière dit « Travail · jusqu'à 15:30 » sur une ligne, puis l'icône du mode reste dans l'aile
  gauche (rien à droite de la caméra).
- Au survol : le mode, « encore 42 min », la barre du temps qui reste, « Arrêter », « +30 min », « Changer de mode ».
- À l'heure : « Fin de Travail ». Le rond du Centre se souvient (« Travail · 1 h ») : un clic relance. Le rond d'un mode allumé : un
  clic l'arrête.
- « Jusqu'à ce soir » : 18:00 ; 22:00 si 18:00 est à moins de 30 min ; puis minuit.

## Ce que Hugues fait une fois

Au premier clic sur un mode, l'app Raccourcis s'ouvre et propose « Ajouter le raccourci » (« Concentration Verbe »). Un clic sur
« Ajouter le raccourci », puis retour à l'îlot : la durée choisie (avant ou après) lance le mode. C'est tout : aucune autorisation de
macOS, aucun réglage. Si le raccourci est supprimé plus tard, Verbe le propose de nouveau au clic suivant.

## Comment ça marche, et pourquoi

**Allumer et éteindre : l'app Raccourcis.** macOS 26 n'a aucune interface publique pour changer de mode. Le service du système refuse
toute app qui n'a pas des droits réservés à Apple. Essai du 12/11 : un petit programme sans droits demande l'état au service privé
`DNDStateService` et reçoit une erreur XPC. Le journal de `donotdisturbd` dit : « XPC connection without any valid entitlements tried
to connect, will reject ». Seule l'action « Définir la concentration » de Raccourcis le fait.

Verbe fabrique donc UN raccourci (`RaccourciConcentration.contenu`) :
1. il nettoie l'entrée ;
2. une branche « si l'entrée est `on:<mode>` / `off:<mode>` » par mode, chacune avec UNE action « Définir la concentration » ;
3. une branche `etat` : « Concentration actuelle ».

L'action ne prend pas son mode d'une variable : il faut une branche par mode. C'est le même schéma que l'extension officielle « Focus
Modes » de Raycast (`extensions/focus-modes/src/helper-shortcut.ts`).

Le raccourci est signé sur le Mac de Hugues (`shortcuts sign --mode people-who-know-me`, 0,13 s, aucun réseau), dans un dossier
temporaire. Raccourcis l'ouvre et pose sa question. Verbe le reconnaît à son identifiant NOUVEAU dans `shortcuts list
--show-identifiers` (15 ms), relu quand Hugues change d'app ; aucune minuterie. Il ne lance ensuite QUE cet identifiant, avec
`shortcuts run <id>` et la commande sur l'entrée standard.

Les noms des paramètres sont relevés sur ce Mac (macOS 26.6, 25G72), dans `WorkflowKit` :
- `Operation(Turn),FocusModes,Enabled(1),AssertionType(Time),Time` ;
- `Turned Off (AssertionType)` ;
- les identifiants `is.workflow.actions.dnd.set` et `is.workflow.actions.dnd.getfocus`.

Les identifiants des modes viennent de la configuration de Hugues : `com.apple.focus.work`, `com.apple.focus.personal-time`,
`com.apple.sleep.sleep-mode`, `com.apple.focus.reduce-interruptions`, `com.apple.donotdisturb.mode.default`.

**La fin d'une durée : une échéance de Verbe.** Le raccourci allume le mode « jusqu'à ce que je l'arrête ». Verbe programme UNE échéance
sur l'horloge murale (`asyncAfter(wallDeadline:)`), revue à la sortie de veille et au lancement, puis l'éteint (`off:<mode>`).
Pourquoi pas « jusqu'à 15:30 » dans Raccourcis ?
- Il faudrait y transformer un texte en date, ce que personne n'a pu essayer ici : aucun raccourci n'est lancé pendant le travail.
- « +30 min » demanderait de relancer le raccourci.

Limite : si Verbe est fermé à l'heure dite, le mode reste allumé jusqu'au prochain lancement de Verbe, qui l'éteint aussitôt.

**Lire l'état.** Voies essayées :
- `INFocusStatusCenter` : ne dit que « une concentration est active, oui ou non ». Il demande aussi un droit (« Communication
  Notifications »), réservé aux apps signées avec un profil de développeur Apple. Verbe est signé « ad hoc » (`codesign --sign -`,
  build.sh).
- Les fichiers `~/Library/DoNotDisturb/DB` (Assertions.json, ModeConfigurations.json) demandent l'accès complet au disque. Essai :
  lus par un processus lancé hors du Terminal (`launchctl submit`), « Operation not permitted ». Raycast demande cet accès ; Verbe
  ne le demande pas.
- Le service privé : refusé (voir plus haut).

Choix : ce que Verbe allume, il le sait (fichier `concentration.json`, 0600). Quand la carte des modes s'ouvre et que Verbe n'a rien
allumé, le raccourci répond à `etat` (une fois par minute au plus). Le rond montre alors le mode allumé ailleurs. Cette lecture ne
touche jamais à ce que Verbe a allumé, ni à son échéance.

**Limites connues (relecture du 12/11).**
- Le raccourci répond « ok » après « Définir la concentration », même si macOS n'allume rien (un mode Travail jamais configuré dans
  Réglages, Réduire les interruptions sans Apple Intelligence). Verbe dirait alors le mode allumé. Le vérifier demanderait de lire
  « Concentration actuelle » à chaque lancement, une réponse qui n'a pas pu être essayée ici.
- Une commande coupée après 20 s (Raccourcis bloqué) est dite « pas allumé », alors que le raccourci a pu agir après coup.
- Revenir cliquer l'îlot ne fait pas passer Verbe au premier plan : le raccourci ajouté est reconnu au premier changement d'app, à
  l'ouverture de la carte ou au clic suivant sur un mode ou une durée.

**Ce qui n'est pas fait (et pourquoi).**
- « 3 notifications retenues » (maquette) : aucune interface ne les compte, et les bannières n'apparaissent pas pendant une
  concentration. Le texte dit « Les notifications reviennent ». « Changer de mode » prend la place de cette ligne.
- Le verre de Lucarne dans un coin (étape 8) : il attend la mission 3 de la Lucarne déplaçable.

## Vérifié / à vérifier en vrai

Vérifié ici, sans rien changer au Mac (aucun raccourci créé, signé dans la bibliothèque, ouvert ni lancé, aucune concentration
allumée) :
- les contrôles du cœur ;
- l'essai `--ilot-essai`, section Concentration : vrais clics, fausse app Raccourcis ;
- les rendus `ilot-33*`.

À vérifier par Hugues, la première fois :
1. Raccourcis propose bien « Ajouter le raccourci ».
2. Travail s'allume.
3. L'icône apparaît dans l'aile.
4. « Arrêter » éteint le mode.
5. Le rond montre un mode allumé depuis le Centre de contrôle (ce que « Concentration actuelle » répond n'a pas pu être essayé).
