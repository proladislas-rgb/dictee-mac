# Plan — Lucarne déplaçable (8 places aimantées) + verre hors de l'encoche

Validé par Hugues le 12/11/2026 sur la maquette `design/maquettes/lucarne-position.html` (geste, places, ouverture vers le haut depuis un coin du bas, niveau de verre « Liquide »). Plan écrit par l'architecte le 12/11 (lecture seule) ; décisions A–F tranchées par défaut (voir §9).

## 0. Existant réutilisé
- **Appui long → rangée Minuteur, à retirer** : `DragGesture(minimumDistance: 0)` sur `IlotCalques` (IlotVues ~828) → `debutAppui`/`finAppui` (IlotMoteur ~933-959), minuterie 0,4 s `dureeAppuiLong` → `appuiLong(minuteurActif:)` (~964) ouvre `sousVue = .lectureMinuteur`. Dépendants : `VueIlot.lectureMinuteur`, `GeoIlot.rangeeMinuteur` (Ilot.swift ~76, 113), `rangeeMinuteurLecture` (IlotVues ~440), `ActionIlot.minuteurLancerSousLecture` (IlotMoteur ~86, IlotControleur ~568), `glisseLecture`/`repliDepuisRangee`/`couches`/`rang` (IlotMoteur ~593-625), `CartesIlot` (DicteeCore/CentreIlot ~18, 52), essai IlotEssai ~124-175, ControlesIlot ~415-444/1026/1201-1230, RenduLecture ~224-226/280/398. `Settings.ilotMinuteur` reste (réglage du minuteur du Centre).
- **Repère** : points, x depuis le centre de l'encoche, y depuis le haut de l'écran (`pointEcran`, `souris`, `reevaluerPointeur`, `appliquer` via `centre` et `ecran.frame.maxY`) ; dessin dans 800 × 380 (`IlotMoteur.largeur`/`hauteurMax`), `posee()` décale de `largeur/2`.
- **Pièces pures** : `RessortIlot`, `PassageIlot.viser` (constantes dans le Core), `TraceIlot.Commande`, `portee` 1,6, `poignee` 0,18, `FormeNoire` (IlotPieces ~48), `GeoIlot.valeurs`, `GrilleIlot`, `MesureIlot.texte`, `PastilleVue.contenu(a:)` (IlotVues ~713), `Retours.vibrer(.legere)`.
- **Énergie** : `CadenceEcran` ne tourne que si un ressort bouge, mais prend `NSScreen.screens.first` → faux si Lucarne vit sur un autre écran.
- **SDK 26.2** : `NSGlassEffectView` (rect arrondi seulement) ; SwiftUI `glassEffect(_:in:)` avec `Glass.clear`, `.tint`, `.interactive()`, `GlassEffectContainer`, `glassEffectUnion`, `glassEffectID`. **Choix : SwiftUI `.glassEffect(.clear, in: forme)`** (accepte notre forme).

## 1. Architecture
- **Régime encoche** (place `encoche` + écran avec caméra) : RIEN ne change (geo 8 ressorts, `TraceIlot.calculer`, `FormeNoire` noire, 66 pt, épaules, bulle).
- **Régime libre** (autres places, ou écran sans encoche) : capsule (x0, x1, y0, y1, s, r) comme `capsule()` de la maquette, `s < 0` = épaules (forme compacte de l'encoche au décollage/retour). 6 ressorts (cx, cy, hw, hh, s, r) + « noir » (0 verre / 1 noir) + « levé » (échelle 1,04 + ombre). Un lancer garde `cx.v`/`cy.v`. Les `geo` restent visés (calcul pur) ; en libre `lien = false` (contenu en fondu).
- **Contenu libre** — replié : pilule de verre avec le contenu compact de la bulle (extraire `PastilleVue.contenu` → `ContenuCompactLucarne(activite:, axe:)`), largeur `largeurPastille(a)`, couchée 36 pt de haut, debout largeur mesurée 40…66 pt. Déplié : `IlotCalques` inchangé, décalé de `decalageContenu = (capsule.midX, capsule.y0 − barre)`, rogné à la capsule (2·grille.corps(v) × grille.hauteur(v) − barre), épaules masquées ; tests de position purs (`PlanCentre.fond`, `PlanDictees.cadreListe`, `ZoneDepotEtagere.sous`) reçoivent `p − decalageContenu`.
- **Fenêtre libre** : au repos, cadre serré sur la capsule visée (marges 2/6, 18/30 ouverte, comme `fenetreVoulue`), grandit tout de suite, rétrécit 0,65 s après. Tenue/vol : taille fixe, seule l'origine suit (`setFrameOrigin`) — pas de réévaluation SwiftUI à chaque image.
- **Mémoire** : `MemoirePlaces` (Codable), une place par écran (clé UUID `CGDisplayCreateUUIDFromDisplayID`) + écran choisi ; fermetures injectables (modèle `reglagesCentre`), l'essai ne touche jamais les vrais defaults. Clés `Settings.lucarnePlaces`, `Settings.lucarneEcran`. Aucun réglage « Position » dans l'interface.

## 2. Modèle pur — `Sources/DicteeCore/PlaceLucarne.swift` (nouveau)
- `PlaceLucarne` : `encoche, hautGauche, hautDroite, gauche, droite, basGauche, basMilieu, basDroite` (String, Codable) ; `ancre` (0/½/1), `debout` (gauche/droite).
- `CapsuleLucarne` : x0, x1, y0, y1, s, r.
- `EcranLucarne` : cadre (AppKit global), largeur, hauteur, barre, `demiCamera: Double?` (nil = pas d'encoche), centreX encoche, retraits visibleFrame (g, d, bas), Dock (`dockCote` bas/gauche/droite, `dockMasque`, `dockLargeur: Double?`, `dockEpaisseur`).
- `GeoLucarne` (constantes de la maquette) : marge 10 ; places du haut à `barre + 8` ; pilule tenue 120 × 36 ; debout 40 × 112 ; tenue 1,04 ; `dureeAppui` 0,4 ; `toleranceAppui` 6 pt ; `seuilLancer` 350 pt/s ; projection 0,5 s ; tolérances de direction 30° puis 60° ; `seuilAimant` 0,45 ; `aimant(x,y) = clamp(1 − (hypot(x/2, y − barre/2) − 40)/110)`, 0 sans encoche.
  - `replie(place, ecran, taille)`, `grand(place, ecran, largeur, hauteur, rayon)` (vers l'intérieur depuis l'ancre, dans la zone utile, jamais sur le Dock ; depuis un coin du bas : monte au-dessus de la ligne du Dock — validé), `plusProche(x, y, ecran, sauf:)`, `viseLancer(cx, cy, vx, vy, ecran)` (jamais l'encoche), `tenue(pointeur, decalage, ecran) -> (cx, cy, pres)` (= `colle()` maquette), `tailleCompacte(contenu:, debout:)`.
  - Dock : coins du bas centrés sur la ligne du Dock seulement si `dockLargeur` connue et place suffisante, sinon au-dessus ; Dock à gauche/droite : places de ce côté décalées ; Dock masqué : places du bas au-dessus de `dockEpaisseur` (notre niveau `mainMenu + 2` volerait ses clics).
- `TraceLucarne.calculer(_ c) -> TraceIlot.Points` (commandes de `capsule()`, même portée/poignée ; dans DicteeCore car l'init de `Points` n'est pas public ; dessiné par `FormeNoire`).
- `RessortsCapsule` : 6 ressorts + noir + levé ; `viser(_:passage:vitesse:reduire:)`, `avancer`, `poser`, `fini`. `PassageLucarne` : ouverture 0,46/0,8 ; fermeture 0,38/1 attente 0,06 ; atterrissage 0,5/0,8 (hw/hh 0,3/0,9) ; aspiration 0,36/0,9 (s/r 0,26/1) ; forme tenue 0,28/0,86 ; levé 0,26/0,7 ; reposé 0,4/0,9 ; noir↔verre 0,14 s / 0,3 s. Réduire les animations : tout posé.
- `GesteLucarne` (machine d'états, on lui donne l'heure) : `appuyer(p,t)`, `bouger(p,t)`, `echeance(t)` (→ `.decolle` à t0+0,4), `relacher(p,t)`. > 6 pt avant 0,4 s → `.annule` (ni clic ni déplacement) ; relâché < 0,4 s sans bouger → `.clic` ; décollée → `.lacher(vx, vy)` (vitesse sur les 100 dernières ms ; 0 si dernier mouvement > 80 ms).
- `MemoirePlaces` : `place(pour uuid:, encoche:)`, défaut `encoche` ; sans encoche, `encoche` = pilule de verre en haut au milieu.

## 3. Par fichier
- **IlotMoteur.swift** (friction) : seulement `var lucarne = EtatLucarne()` + points d'accroche ; logique dans **`Sources/Dictee/LucarneMoteur.swift`** (extension). Accroches : `afficher(v)` (libre : `grand()`/`replie()`, `lien=false`) ; `avancer(dt)`, `poser()`, `tousLesRessorts` incluent la capsule ; `trace`, `contient`, `rectCible`, `rectActuel`, `fenetreVoulue`, `rectPastille` : branche libre ; `debutAppui` annule `intention` et démarre le geste, l'échéance appelle `decoller()` au lieu de `appuiLong()` ; `presse`/`appuyer` servent l'anneau sur toutes les vues ; `donneesChangees` branche `cache` : si tenue → `lacher(v=0)`.
  - `decoller()` : range Centre/carte, régime libre avec capsule prise sur la forme actuelle (s = −6), lève, vibre une fois (injectable). `suivre(p)` : `GeoLucarne.tenue` ; près de l'encoche → forme d'encoche noire, sinon pilule verre. `lacher(v)` : choisit la place, `RessortsCapsule.viser` en gardant la vitesse, mémorise, fin d'aspiration → régime encoche.
- **IlotPanneau.swift** (friction) : `EcranLucarne` courant + `ecrans: () -> [EcranLucarne]` injectable ; `mesurer`/`recaler` reposent à la place mémorisée sans animation (écran disparu → principal) ; `appliquer(r)` en libre ; `setFrameOrigin` à chaque image seulement en tenue/vol ; `pointEcran(_:)` → `point(_:sur:)` multi-écrans ; `approcher`, `procheEncoche`, zone étagère : distance à la capsule, point converti en coordonnées du contenu ; `envoyerSouris` généralisé + `.leftMouseDragged` ; `CadenceEcran.demarrer(ecran:)`.
- **VueHebergeeIlot** : surcharges `mouseDown/mouseDragged/mouseUp` qui retiennent le point GLOBAL (`cgEvent.location`) avant `super` et le passent au panneau. Jamais `NSEvent.mouseLocation`, jamais la translation du DragGesture. Le DragGesture ne dit plus que « appui sur la forme hors bouton » ; les boutons gardent leurs clics.
- **IlotVues.swift** (`IlotVue.body`) : `if m.lucarne.libre { LucarneLibreVue(m) } else { existant }` ; extraire `PastilleVue.contenu`. Nouvelle vue dans **`Sources/Dictee/LucarneVues.swift`**.
- **IlotControleur.swift** : brancher mémoire, `lireDock` (prefs `com.apple.dock` : orientation, autohide, tilesize), `NSScreen` → `EcranLucarne`. Rien d'autre.
- Nouveaux : `Sources/Dictee/LucarneEcrans.swift`, `Sources/DicteeControles/ControlesPlacesLucarne.swift`, `Sources/Dictee/IlotEssaiPlacesLucarne.swift` (appel d'une ligne depuis `IlotEssai.executer`).

## 4. Verre
```swift
let forme = FormeNoire(points: TraceLucarne.calculer(capsuleLocale))
ZStack {
  Color.clear.glassEffect(.clear.tint(.black.opacity(voile)), in: forme)
     .overlay(forme.stroke(.black.opacity(0.18), lineWidth: 0.5))   // verre visible sur fond blanc
  forme.fill(.black).opacity(noir)                                   // fondu noir ↔ verre
  contenu.clipShape(forme)
}.shadow(levé).scaleEffect(1 + 0.04·levé)
```
- Encoche : branche actuelle intacte. Bulle hors encoche : goutte de verre dans `GlassEffectContainer` + `glassEffectUnion` (le pont `Canvas` reste pour l'encoche).
- Lisibilité v1 : texte blanc (`CouleursIlot`) + voile léger (~0,12 pilule, ~0,25 Centre/cartes), à régler sur fond blanc ET noir. Pas de lecture de luminosité du fond (demanderait l'enregistrement d'écran : exclu).
- Rendus PNG : ImageRenderer ne dessine pas le verre → faux verre (blanc 25 %, liseré, ombre).
- Pas d'`.interactive()` ni de reflet qui suit le pointeur (boucle au survol interdite).

## 5. Événements
- Appui : `mouseDown` sur la forme hors bouton → geste + annule l'intention de survol ; anneau sous le pointeur, boucle seulement pendant ces 0,4 s ; un seul réveil (`DispatchWorkItem`).
- Glisser : pas de moniteur global (AppKit envoie `leftMouseDragged/Up` à la vue de l'appui, même hors fenêtre) ; garde-fou relâchement perdu via `boutonEnfonce()` injectable → lâcher à la place la plus proche.
- Clics traversants : `laisserPasser`/`souris` gardés, `contient()` connaît la capsule.
- Dictée/réunion (`cache`) pendant la tenue : geste annulé, retombe à sa place la plus proche.

## 6. Tests
- **ControlesLucarne** (3 faux écrans : MacBook encoche Dock bas 600 pt ; 2560×1440 sans encoche ; Dock à gauche + Dock masqué) : 8 places dans la zone utile, jamais sur le Dock ni dans la barre (y0 ≥ barre+8) ; coins bas à côté/au-dessus du Dock selon `dockLargeur` ; sans encoche : ni aimant ni place noire ; `plusProche` sur les 8 centres + points intermédiaires ; `viseLancer` 8 directions, jamais l'encoche, < 350 pt/s → plus proche ; aimant seuil 0,45, 0 au-delà ~150 pt ; `grand` depuis basGauche au-dessus de la ligne du Dock, depuis hautDroite ancre fixe, toujours dans l'écran ; `TraceLucarne` fermé, boîte = capsule, épaules si s<0 ; `RessortsCapsule` convergence, vitesse gardée, reduire pose, `fini` ; `GesteLucarne` 5 pt continue, 7 pt avant 0,4 s annulé, 0,3 s clic, 0,4 s décollée, vitesse 100 ms, 80 ms → 0 ; `MemoirePlaces` JSON, écran inconnu, sans encoche ; tests 66 pt inchangés.
- **IlotEssaiLucarne** (fenêtre invisible, faux écrans, mémoire et vibration injectées, vrais NSEvent) : appui 0,5 s + déplacements + relâchement (suit à 1 pt, place la plus proche, mémoire factice écrite) ; 10 pt à 0,2 s → rien ; appui long dans l'encoche Centre ouvert → replie puis décolle ; lancer 800 pt/s vers le bas → basMilieu ; glisser vers l'encoche → régime encoche, noire, cou ≤ 66 pt ; survol hautDroite → Centre vers l'intérieur ; survol basGauche → au-dessus de la ligne du Dock ; bannière à gauche sort de la place ; posée au repos → `!m.boucleActive`, fenêtre serrée, coin hors capsule `contient == false` ; Réduire les animations ; faux changement d'écran (Dock à gauche, résolution, débranché) ; dictée pendant la tenue. Section 124-175 remplacée par « appui long sur la lecture : elle se décolle ».
- **Rendus** `lucarne-*` (chaque place repliée, tenue, Centre depuis basGauche, bannière depuis droite ; fond clair et sombre ; taille des PNG contrôlée).

## 7. Missions (relecteur après chacune ; build + DicteeControles + --ilot-essai verts + aucune boucle au repos)
1. **Modèle pur** (fichiers nouveaux seulement) : PlaceLucarne.swift + ControlesPlacesLucarne.swift ; sonde en lecture seule des prefs du Dock et de `visibleFrame` (documentée dans tasks/todo).
2. **Geste et fenêtre** (capsule noire) — après le commit de l'équipe simplicité : EtatLucarne, LucarneMoteur.swift, accroches IlotMoteur/IlotPanneau, appui long débranché du minuteur, anneau, décollage, suivi, lâcher/lancer, aimant/retour, mémoire par écran, CadenceEcran par écran, essais du geste.
3. **Verre et contenu hors encoche** : LucarneVues.swift (verre .clear, fondu noir↔verre, liseré, ombre), pilule couchée/debout, dépliés vers l'intérieur, bannières/alertes depuis la place, goutte de la bulle, épaules masquées, zones étagère, rendus faux verre, essais survol/bannière/clics traversants. Sonde visuelle du vrai verre derrière un NSPanel non opaque (fenêtre jetable : prévenir Hugues avant).
4. **Bords et nettoyage** : Dock masqué/gauche/droite, plein écran, résolution, multi-écrans (glisser de l'un à l'autre), sans encoche ; actions VoiceOver « Déplacer vers… » ; suppression du code mort `.lectureMinuteur` ; tasks/todo + lessons.

## 8. Risques
- Conflits : IlotMoteur (`donneesChangees`, `oublierAide`), IlotPanneau (`approcher`, `deposer`, `airDropEclaire`), IlotVues (`microFn`), IlotEssai, ControlesIlot, RenduLecture, EtagereIlot → logique dans les fichiers nouveaux, accroches d'une ligne ailleurs.
- Verre : vérifier qu'il échantillonne derrière une fenêtre transparente et qu'un fondu d'opacité ne clignote pas (repli : `glassEffectTransition(.materialize)` / `Glass.identity`) ; coût GPU au-dessus d'une vidéo à mesurer (Moniteur d'activité, repos et glisser).
- `rev` réévalue tout l'arbre : pendant la tenue on déplace la fenêtre, pas la vue.
- Dock : largeur sans API publique → repli au-dessus de la ligne ; Dock masqué → rester au-dessus de sa hauteur d'apparition.
- Plein écran/Spaces : `canJoinAllSpaces` + `fullScreenAuxiliary` ; mesurer `visibleFrame` dans un Space plein écran.
- Multi-écrans : toujours `cgEvent.location` puis l'écran sous le pointeur.
- Encoche ↔ libre avec Centre ouvert : replier d'abord (comme la maquette).

## 9. Décisions (tranchées par défaut, Hugues peut revenir dessus)
- A. Écran sans encoche : la place du haut au milieu = pilule de verre sous la barre, visible même vide.
- B. Lucarne vide hors encoche : petite pilule avec le logo.
- C. Pendant une dictée hors encoche : elle s'efface comme aujourd'hui (v1).
- D. Plein écran : elle reste à sa place.
- E. Texte sur le verre : blanc + voile léger (v1).
- F. Pilule debout : largeur mesurée 40…66 pt.

## Exigence transversale (Hugues, 12/11 nuit)
TOUT ce qui existe dans l'îlot doit marcher en verre « Liquide » depuis les 4 coins (et les autres places) : Centre, cartes (Claude, Outils, Second Brain, Concentration, Dictées, Étagère), annonces (captures, rappel avec carte de confirmation, téléchargé, AirDrop), alertes (minuteur, rappel), réunion en cours, onde de voix de la dictée/note. Chaque essai de mission 3-4 parcourt ces écrans depuis hautGauche, hautDroite, basGauche, basDroite (+ gauche/droite) : rien de coupé, ouverture vers l'intérieur, lisible sur fond clair et sombre.

> Intégration (12/11) : `ControlesLucarne.swift` et `IlotEssaiLucarne.swift` existent déjà sur main pour les commandes « Lucarne, … ». Les contrôles des places sont donc dans `ControlesPlacesLucarne.swift` (`controlesPlacesLucarne()`), et l'essai des places devra s'appeler `IlotEssaiPlacesLucarne.swift`.

## État mission 2 (12/11, branche `lucarne-geste`, poussée, NON fusionnée)
**Fait** (commit b42434f) :
- Appui long 0,4 s sur la forme, même dans l'encoche (anneau sous le pointeur, boucle seulement pendant ces 0,4 s, un seul réveil) → décollage (Centre/carte rangés d'abord, capsule prise sur la forme actuelle via `CapsuleLucarne.encoche`, levée 1,04 + ombre, une vibration injectable). L'appui long n'ouvre plus la rangée Minuteur (`appuiLong` gardé, appelé seulement par les rendus, retiré en mission 4).
- Événements : `VueHebergeeIlot.mouseDown/Dragged/Up` → `IlotPanneau.bouton(_:)` lit `cgEvent.location` → `IlotMoteur.sourisBas/Glisse/Haut`. Constat : le DragGesture SwiftUI est appelé AVANT le mouseDown de la vue d'hébergement → `formeAppuyee()` pose `lucarne.surForme`, effacé en fin d'événement ; les deux ordres sont gérés. La miniature de capture (`SourceFichiers`) a maintenant son propre `clic: { m.clicForme() }` (le geste de la forme ne clique plus pour les vues AppKit).
- Tenue au point près (`GeoLucarne.tenue`), forme de l'encoche noire près de l'encoche, pilule ailleurs ; lâcher (plus proche) / lancer (> 350 pt/s, élan gardé) / aspiration → régime encoche sans saut (tracés identiques, contrôle « quitter l'encoche et y revenir sans saut »).
- Fenêtre libre centrée sur la capsule (`origineVue`, `fenetreLibre`, `appliquer` généralisé à `r.maxY`) ; tenue/vol : `deplacerLibre` = `setFrameOrigin` seul, aucune réévaluation SwiftUI (vérifié : `rev` inchangé) ; posée : resserrée à 2 pt tout de suite (capsule posée exactement : AppKit arrondit les cadres vers l'extérieur).
- Mémoire par écran (`SystemeLucarne` injectable, `Settings.lucarnePlaces`, UUID CoreGraphics), reposée sans animation à `mesurer`/`recaler` ; Dock lu dans `com.apple.dock` (lecture seule) ; `CadenceEcran.ecran`.
- Garde-fou du relâchement perdu (0,25 s, seulement pendant la tenue) ; dictée/réunion (`cache`) pendant l'appui ou la tenue : geste arrêté, retombe à la place la plus proche, effacée le temps de la dictée.
- Fichiers : LucarneMoteur.swift, LucarneEcrans.swift, LucarneVues.swift, IlotEssaiPlacesLucarne.swift (`DICTEE_ESSAI_SEUL=places`) ; accroches dans IlotMoteur, IlotPanneau, IlotVues, IlotEssai.
- Vérifs : build release OK ; DicteeControles 3564/3564 ; `--ilot-essai` complet 1202 ok, 2 échecs = les deux connus de l'autre équipe (« îlot déplié et posé : plus de boucle », « le survol suit la souris ») ; section places 3 fois verte.

**Limites voulues de la mission 2** (à faire en mission 3) : hors de l'encoche la capsule est noire et VIDE : pas de survol qui ouvre, pas de clic, pas d'alerte/bannière visible, pas de bulle, pas de zones de dépôt (bloqués dans `IlotPanneau.pointeur` / `glisser` / `glisserSurLIlot` et `traiter(.clic)`). Ne pas livrer la branche seule à Hugues : une alerte arrivée pendant que la Lucarne est hors de l'encoche ne se voit pas.

**Écarts au plan** : pas de pointillés des 8 places pendant la tenue (fenêtre serrée sur la capsule) ; écran sans encoche : régime encoche gardé tant que la place est `encoche` (la pilule visible même vide, décision A, attend la mission 4) ; `IlotControleur` non touché (le système passe par `SystemeLucarne` dans `EtatLucarne`) ; une seule clé de réglage (`lucarnePlaces`, l'écran choisi est dans `MemoirePlaces`).

**Suite (mission 3)** : contenu et verre dans `LucarneLibreVue` (pilule couchée/debout, dépliés vers l'intérieur via `GeoLucarne.grand`, `decalageContenu`), puis lever les blocages ci-dessus ; essais survol/bannière/clics traversants depuis les coins. Mission 4 : multi-écrans (glisser d'un écran à l'autre, `point(_:sur:)`), Dock masqué/gauche/droite réels, plein écran, VoiceOver « Déplacer vers… », retrait de `.lectureMinuteur`/`appuiLong`.
