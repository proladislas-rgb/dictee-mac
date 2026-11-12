# La case « Second Brain » dans l'îlot : le fichier d'état (contrat v1)

Second Brain (l'app locale de Hugues) dépose un petit fichier d'état. L'îlot de Verbe (bientôt Lucarne) le **lit**. Il ne coche rien,
n'écrit rien, n'envoie rien : tout reste sur ce Mac. Ce document est le contrat entre les deux apps.

## Où

`~/.config/second-cerveau/ilot.json`

- Le fichier n'a pas à exister d'avance, ni son dossier : l'îlot attend leur apparition (sans minuterie, le système le prévient).
- **Pas de fichier = pas de case.** Rien ne s'affiche pour qui n'a pas l'app (l'app est open source).
- Un fichier absent, illisible, qui n'est pas un objet JSON, ou de **plus de 64 Ko** cache la case (rien ne casse). Un fichier réparé la fait
  revenir.

## Comment l'écrire

- Écrire dans un fichier temporaire du même dossier, puis le **renommer** par-dessus `ilot.json` (écriture atomique). L'îlot ne voit alors
  jamais un fichier à moitié écrit. Une écriture sur place est aussi relue, mais peut montrer un instant un fichier tronqué (la case
  disparaît puis revient).
- Réécrire à chaque changement utile ; l'îlot attend 0,3 s après la dernière modification avant de relire (une rafale = une relecture) et
  ne redessine que si le contenu a changé.
- Mettre à jour `maj` à chaque écriture.

## Le format

```json
{ "version": 1, "maj": "2026-11-12T09:15:00+01:00",
  "resume": "Pierre t'a écrit · 3 choses demandées",
  "compteurs": { "nouveautes": 3, "aToi": 5, "aRelancer": 2 },
  "messages": [ { "id": "9ed7c1f2a7f3", "nom": "Pierre", "texte": "Pour vendredi : le plan…", "heure": "2026-11-12T09:12:00+01:00", "resume": "3 choses demandées", "lien": "secondbrain://message/9ed7c1f2a7f3" } ],
  "taches":   [ { "id": "4b0c9e11d2aa", "texte": "Répondre aux 3 questions de Pierre", "echeance": "2026-11-14", "lien": "secondbrain://chose/4b0c9e11d2aa" } ],
  "relances": [ { "id": "c3a5f0e8b1d4", "nom": "Marc", "sujet": "le devis du site", "depuis": "2026-10-21", "lien": "secondbrain://fiche/personnes/marc.md" } ],
  "lien": "secondbrain://aujourdhui" }
```

- Les identifiants sont 12 caractères hexadécimaux (l'îlot ne s'en sert pas : il les lit comme n'importe quel texte).
- Les listes peuvent être vides, trois éléments au plus par liste. Tout champ sans valeur est `null` (ou absent).
- **Les dates sont des dates machine ; c'est l'îlot qui les écrit en français simple** (voir plus bas) : `echeance` et `depuis` sont des
  « AAAA-MM-JJ » (ou `null`), `heure` une ISO 8601 avec fuseau (ou `null`).

| Champ | Rôle | Montré |
|---|---|---|
| `version` | 1 aujourd'hui (ignorée si absente ; les champs inconnus sont ignorés) | non |
| `maj` | date ISO 8601 de la dernière écriture (avec fuseau de préférence) | « il y a 2 min » dans l'en-tête de la carte ; 24 à 48 h : « mis à jour hier » ; au-delà ou sans date : rien |
| `resume` | une phrase | lue par VoiceOver sur le bouton du Centre |
| `compteurs.nouveautes` | nombre de nouveautés | sous le bouton du Centre (« 3 nouveautés ») ; « 2 à lire » dans la carte |
| `compteurs.aToi` | nombre de choses « à toi » | « 5 à toi » sous le bouton (si pas de nouveauté) ; « 3 sur 5 » dans la carte |
| `compteurs.aRelancer` | nombre de personnes à relancer | « 2 à relancer » sous le bouton (en dernier) ; « 2 personnes » dans la carte |
| `messages[]` | nouveaux messages : `id`, `nom`, `texte`, `heure`, `resume`, `lien` | une ligne chacun : pastille, nom en gras, texte, heure (« 9:12 ») |
| `taches[]` | choses à faire : `id`, `texte`, `echeance`, `lien` | une ligne chacune : case dessinée (jamais cochable ici), texte, échéance |
| `relances[]` | personnes à relancer : `id`, `nom`, `sujet`, `depuis`, `lien` | une ligne chacune : nom, sujet, « depuis 22 jours » (en ambre à partir de 30 jours) |
| `lien` | lien général (« Ouvrir Second Brain » et toute ligne sans lien) | non |

Sans `compteurs`, l'îlot compte les lignes gardées.

## Les dates, en français simple

Calculées à l'ouverture de la carte, avec le calendrier et le fuseau du Mac (aucune minuterie : « demain » à minuit se corrige à
l'ouverture suivante).

| Champ | Valeur | Écrit |
|---|---|---|
| `echeance` | le jour même | « aujourd'hui » |
| | le lendemain | « demain » |
| | dans les 6 jours suivants | le jour : « samedi » |
| | plus loin, ce mois-ci | « le 20 » (« le 1er ») |
| | un autre mois, cette année | « le 3 déc. » |
| | une autre année | « 5 janv. 2027 » |
| | passée | « en retard » (en ambre) |
| `depuis` | aujourd'hui (ou à venir) | « aujourd'hui » |
| | hier | « depuis hier » |
| | 2 à 59 jours | « depuis 22 jours » (en ambre dès 30) |
| | 60 jours à 2 ans | « depuis 2 mois » (en ambre) |
| | plus | « depuis 2 ans » (en ambre) |
| `heure` | ISO avec fuseau | « 9:12 » (heure du Mac) |
| tous | `null`, absent ou vide | rien |
| tous | un texte qui n'est pas une date (« samedi », « 22 jours », « 9:12 » : le premier contrat) | le texte tel quel (16 caractères au plus ; 8 pour l'heure) |

## Ce qui est toléré

- **Chaque champ est optionnel.** Un champ du mauvais type est ignoré (jamais le fichier entier). Une ligne sans le texte qu'il lui faut
  (message : `nom` ou `texte` ; tâche : `texte` ; relance : `nom` ou `sujet`) est sautée. Un `id` absent est remplacé.
- **Tableaux bornés** : les 3 premières lignes valables de chaque tableau sont gardées (les 40 premières entrées sont examinées). La carte
  montre **7 lignes au plus** en tout (c'est ce qui tient dans la hauteur du Centre) : 3 + 3 + 3 devient 3 + 2 + 2.
- **Textes nettoyés et tronqués** : sur une seule ligne, sans caractère de contrôle ni invisible, coupés à la fin d'un mot avec « … »
  (nom 28 caractères, texte 96, résumé 80 ; une date, 40 avant d'être écrite en français).
- **Compteurs** : entiers de 0 à 9 999 (un booléen, un texte, un négatif ne comptent pas ; un décimal est arrondi vers le bas).

## Les liens

`lien` (général ou d'une ligne) est ouvert d'un clic sur la ligne, ou sur « Ouvrir Second Brain » (lien général) :

- `secondbrain://aujourdhui`, `secondbrain://fiche/<chemin>`, `secondbrain://message/<id>`, `secondbrain://chose/<id>` (le schéma
  `secondbrain` seulement ; des espaces non encodés sont acceptés) ;
- ou un **chemin de fichier qui existe** (`/Users/…/Plan.md`, `~/…`, `file:///…`) : un document (`md`, `markdown`, `txt`, `rtf`, `pdf`,
  `html`, `htm`, `csv`, `json`, `png`, `jpg`, `jpeg`, `heic`) ou un dossier ordinaire (jamais une app, un paquet ou un script) ;
- **tout le reste est refusé** (https, javascript, tel, autres schémas, chemin qui n'existe pas) : un fichier piégé ne peut rien ouvrir
  d'autre. Une ligne dont le lien est refusé retombe sur le lien général ;
- sans lien valable (ni sur la ligne, ni général) : « Aujourd'hui » de l'app, `secondbrain://aujourdhui`, si une app sait ouvrir ce
  schéma (`NSWorkspace.urlForApplication(toOpen:)`) ; sinon l'app elle-même si elle est installée (identifiants essayés dans l'ordre :
  `com.hugues.second-cerveau`, le bundle id final, puis `com.hugues.second-brain`, au cas où), sinon rien.

Après une ouverture, l'îlot se range.

## Où ça s'affiche

- Un rond **Second Brain** dans le Centre, avec l'état dessous (« 3 nouveautés »). Il est ajouté une seule fois, la première fois que le
  fichier apparaît (s'il y a de la place : cinq ronds au plus) ; « Modifier » le range ou le retire, et il ne revient pas tout seul.
  Sans fichier, le rond est caché (il n'est pas retiré de la disposition).
- Un clic sur le rond ouvre la **carte Second Brain**, rangée sous le Centre (« ‹ Centre » y ramène, un défilement aussi) : trois
  parties (nouveaux messages, à toi, à relancer), « Lu sur ce Mac seulement » et « Ouvrir Second Brain ». Elle épouse ses lignes
  (148 à 298 pt sous la barre) et n'est jamais plus haute que le Centre : le Minuteur et l'Étagère ne bougent pas.

## Vie privée

Le contenu du fichier n'est jamais écrit dans le journal de Verbe (seulement « fichier présent / absent » et « ouverture demandée »), jamais
dans les rendus ni les essais (qui lisent un faux fichier dans un dossier temporaire). L'îlot ne l'envoie nulle part.

## Pour le code

- Logique pure (décodage, choix des lignes, textes, liens, fraîcheur, hauteur) : `Sources/DicteeCore/SecondCerveauIlot.swift`
  (contrôles : `Sources/DicteeControles/ControlesSecondBrain.swift`).
- Surveillance sans sondage, contrôleur, carte : `Sources/Dictee/IlotSecondBrain.swift` (essai : `IlotEssaiSecondBrain.swift`).
- La surveillance : une source du système de fichiers (`DispatchSource`) sur le dossier (ou son plus proche ancêtre qui existe, tant qu'il
  n'existe pas), une autre sur le fichier ; relecture coalescée (0,3 s). Aucune minuterie : au repos, aucune relecture.
