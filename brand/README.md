# Marque PronoWin

`logo-pronowin.svg` est la source. Tous les PNG en sont dérivés — ne les
retouchez pas à la main, régénérez-les :

```
node brand/rendre.js      # produit les PNG
node brand/verifier.js    # planche de contrôle : cercle + 160/80/40 px
```

## Ce que le logo reprend

Le trophée blanc portant un « P » sur fond orange **existait déjà** : c'est
l'icône de l'application Android, et la pastille « P » du site en dérive. Le
logo la reprend au lieu d'en proposer une autre — une marque qu'il faut
réapprendre à chaque support n'en est pas une.

Aucune police n'est utilisée : le « P » est un tracé. Un rendu qui dépend
d'une police installée produit un logo différent sur chaque machine, et se
dégrade en silence.

## Les deux palettes

Elles divergeaient, et divergent toujours dans le code :

| Source | Orange | Clair | Profond |
|---|---|---|---|
| `mobile_new/lib/core/theme` | `#E8541A` | `#F5A623` | — |
| `website/public/css/style.css` | `#F2632A` | `#F2B705` | `#D9451F` |

Le dégradé du logo les traverse : `#F5A623 → #E8541A → #D9451F`. À unifier un
jour dans le code — deux orange qui se ressemblent sans être identiques finiront
par se voir côte à côte.

## Quel fichier pour quoi

| Fichier | Usage |
|---|---|
| `pronowin-telegram-512.png` | photo du canal Telegram |
| `pronowin-telegram-1024.png` | idem, si Telegram accepte plus grand |
| `logo-pronowin-512.png` | icône d'application, favicon, stores |
| `logo-pronowin-1024.png` | fiche Play Store (512 exigé, 1024 utile) |
| `apercu-cercle-512.png` | contrôle : le recadrage circulaire de Telegram |
| `planche-controle.png` | contrôle : lisibilité en 160 / 80 / 40 px |

Les variantes `telegram-*` sont **à fond perdu**, sans coins arrondis :
Telegram recadre en cercle, où un arrondi serait rogné et laisserait un liseré
transparent visible sur fond clair. Les variantes `logo-*` gardent l'arrondi
(rayon 112 sur 512), pour les usages où le carré reste carré.

## Deux réglages non évidents

- **Le trophée est remonté de 13 px.** Il s'étend de y=150 à y=388 : son centre
  tombait sous celui du carré. Invisible sur un carré, net dès le recadrage en
  cercle.
- **Le « P » est agrandi de 14 %.** À 40 px — sa taille dans une liste de
  discussions, là où il est vu cent fois pour une fois en grand — son
  contre-poinçon se refermait et la lettre devenait une tache.
