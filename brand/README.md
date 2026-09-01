# Marque PronoWin

Trois pièces, trois sources :

| Source | Ce que c'est |
|---|---|
| `logo-pronowin.svg` | l'**emblème** — trophée blanc au « P » sur fond orange |
| `logotype-pronowin-*.svg` | le **logotype** — le mot « PronoWin » |
| `profil-pronowin-*.svg` | l'**assemblage** — emblème + mot, carré, pour une photo de profil |

Tous les PNG en dérivent. Ne les retouchez pas à la main, régénérez :

```
cd brand && npm install && npm run tout
```

`npm run tout` reconstruit tout depuis zéro, police intermédiaire comprise.
Les étapes séparément : `npm run logotype`, `npm run profil`, `npm run rendre`,
`npm run verifier`. Le contrôle accepte un sujet :
`node verifier.js pronowin-telegram-512.png`.

## L'emblème

Le trophée blanc portant un « P » sur fond orange **existait déjà** : c'est
l'icône de l'application Android, et la pastille « P » du site en dérive.
L'emblème la reprend au lieu d'en proposer une autre — une marque qu'il faut
réapprendre à chaque support n'en est pas une.

Deux réglages que le fichier source ne laisse pas deviner :

- **Le trophée est remonté de 13 px.** Il s'étend de y=150 à y=388 : son centre
  tombait sous celui du carré. Invisible sur un carré, net dès que Telegram
  recadre en cercle.
- **Le « P » est agrandi de 14 %.** À 40 px — sa taille dans une liste de
  discussions, là où il est vu cent fois pour une fois en grand — son
  contre-poinçon se refermait et la lettre devenait une tache.

## Le logotype

**Les lettres sont des tracés, pas du texte.** Le site compose la marque avec
une pile de polices système (`-apple-system, SF Pro Display, Helvetica Neue,
Arial`) : un logo qui s'appuie là-dessus se rend différemment sur chaque
machine, et ne le dit pas. Ici, aucune police n'est nécessaire pour l'afficher.

La coupure de couleur « Prono » / « Win » reprend celle du site
(`.brand span { color: var(--accent) }`).

### Police et licence

**Inter Bold**, sous SIL Open Font License 1.1, qui autorise l'usage des
contours dans un logo. C'est le point à ne pas escamoter : Arial et Segoe UI —
les deux polices vers lesquelles la pile du site retombe sous Windows — sont
sous licence Monotype/Microsoft. Les intégrer à une marque destinée à être
déposée poserait un problème que personne ne découvrirait avant le dépôt.

`@fontsource/inter` ne livre que du WOFF ; `opentype.js` ne lit que le TTF.
`woff2ttf.js` fait la conversion — un WOFF n'est qu'un conteneur de tables
compressées en zlib. Le WOFF2, lui, est refusé explicitement : il demande
Brotli **et** une transformation des tables `glyf`/`loca`, et produire une
police à moitié convertie serait pire que refuser.

`logotype.js` compose ensuite lettre par lettre plutôt que par `getPaths()` :
opentype.js ne sait pas lire la fonctionnalité `ccmp` d'Inter et lève une
exception. Pour huit lettres latines sans ligature ni diacritique, `ccmp`
n'aurait rien substitué — on ne perd rien, et la position de chaque lettre
devient explicite.

## L'assemblage — la photo de profil

**C'est ce qu'il faut mettre en photo de canal Telegram, pas le logotype.**

Telegram recadre la photo d'un canal **en cercle**. Le logotype seul est large
et plat : le disque en coupe les deux bouts, et il n'en reste que « Pro ».
L'assemblage empile l'emblème et le mot dans un carré dont le contenu tient
dans le disque inscrit.

Le trophée y est **relu depuis `logo-pronowin.svg`**, pas recopié. Deux copies
d'un même dessin finissent par diverger, et celle que personne ne regarde est
celle qui se périme. L'extraction se valide : si l'emblème change de structure,
`lockup.js` s'arrête au lieu de produire un assemblage amputé d'une anse.

La mise en page est vérifiée, pas supposée : le script calcule la distance du
coin le plus éloigné au centre et **refuse de produire** au-delà de 86 % du
rayon. Aujourd'hui : 81,8 %.

À 40 px, le mot se referme et seul le trophée reste lisible. C'est le compromis
normal d'un assemblage — celui de PronoVision se comporte pareil : la photo de
profil est vue en grand sur la fiche du canal, et en silhouette dans la liste.

## L'icône de notification

`ic_notification.svg` et les cinq PNG de `mobile_new/.../res/drawable-*` sont
générés par `notification.js`, depuis les mêmes tracés que l'emblème.

Elle est **blanche sur transparent, le « P » percé**. Depuis Android 5, la
petite icône d'une notification est rendue en silhouette : le système ne garde
que le canal alpha et repeint la forme. Une icône de lanceur, dont le fond
orange est opaque, y devient un carré blanc uni — et le « P », s'il était
peint, disparaîtrait dans la masse.

Les notifications portaient jusqu'ici **le logo de Flutter** : `ic_launcher.png`
était resté le fichier par défaut du jour de création du projet, et deux
réglages pointaient dessus.

## Le visuel de mise en avant Google Play

`feature-graphic.js` produit `feature-graphic-1024x500.png` — dimensions
imposées, **sans canal alpha** (Play refuse la transparence sur ce visuel), et
le dessin tient dans 86 % de la largeur parce que Play rogne les bords selon la
surface d'affichage. Le script refuse de produire au-delà.

Il relit l'emblème **et** le logotype. Attention à un piège rencontré : les
tracés du logotype sortent d'opentype.js en coordonnées de police — ligne de
base à zéro — et c'est le `translate` du groupe qui les pose dans la boîte.
Extraire les tracés sans ce `transform` donne un mot flottant au-dessus de sa
place, et rien ne le signale sinon l'œil. Le script l'extrait et le valide.

## Les deux palettes

Elles divergent, et divergent toujours dans le code :

| Source | Orange | Clair | Profond |
|---|---|---|---|
| `mobile_new/lib/core/theme` | `#E8541A` | `#F5A623` | — |
| `website/public/css/style.css` | `#F2632A` | `#F2B705` | `#D9451F` |

Le dégradé de l'emblème les traverse (`#F5A623 → #E8541A → #D9451F`) et le
logotype utilise `#E8541A`. À unifier un jour dans le code — deux orange qui se
ressemblent sans être identiques finiront par se retrouver côte à côte, une
capture d'application posée sur le site par exemple.

## Quel fichier pour quoi

### Emblème

| Fichier | Usage |
|---|---|
| `pronowin-telegram-512.png` | avatar carré sans texte (emblème seul) |
| `pronowin-telegram-1024.png` | idem, plus grand |
| `logo-pronowin-512.png` | icône d'application, favicon |
| `logo-pronowin-1024.png` | fiche Play Store (512 exigé, 1024 utile) |

Les variantes `telegram-*` sont **à fond perdu**, sans coins arrondis :
Telegram recadre en cercle, où un arrondi serait rogné et laisserait un liseré
transparent visible sur fond clair. Les variantes `logo-*` gardent l'arrondi
(rayon 112 sur 512).

### Assemblage (photo de profil)

| Fichier | Usage |
|---|---|
| `profil-pronowin-sombre-512.png` | **photo du canal Telegram** — fond bleu-nuit |
| `profil-pronowin-orange-512.png` | même chose, fond orange plein |
| `profil-pronowin-*-1024.png` | si la plateforme accepte plus grand |

### Logotype

| Fichier | Usage |
|---|---|
| `logotype-pronowin-fond-*.png` | bandeau sur fond bleu-nuit, prêt à poser |
| `logotype-pronowin-clair-*.png` | transparent, **sur fond sombre** |
| `logotype-pronowin-noir-*.png` | transparent, **sur fond clair** |

### Contrôles

| Fichier | Ce qu'il montre |
|---|---|
| `apercu-cercle-*.png` | le recadrage circulaire de Telegram |
| `planche-*.png` | la lisibilité en 160 / 80 / 40 px |

Un logo se juge là où il sera vu, pas dans son fichier source.
