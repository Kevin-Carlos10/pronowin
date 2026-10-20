# Version 1.0.27 (43) — Actus au style FotMob

Préparée le 20 octobre 2026, à la suite de la 1.0.26 (voir
`notes_version_1.0.26.md`). Rien à déployer côté serveur : elle lit ce que le
serveur sert déjà (`/actualites?limite=50`, logos et score des résumés).

## Ce qui change dans l'app

- **Page Actus**, au modèle de FotMob (vidéo du 17 octobre 2026, 1:44-2:45) :
  grand titre, onglets texte qu'on fait glisser — Pour toi, Plus récent,
  Résumés, Médias (PronoWin s'il y a des articles de la rédaction). « Pour
  toi » ouvre sur « Tendance » : une grande carte photo, puis des lignes
  (vignette à gauche, titre à droite), et « Plus récent » en grandes cartes.
  Les résumés des matchs qu'on suit passent en tête. Pendant le chargement,
  la forme de la page en gris qui scintille ; les photos arrivent en fondu ;
  les articles entrent en cascade. Tirer vers le bas actualise.
- **Page article** : la photo (ou, pour un résumé, les logos et le score) en
  pleine largeur sous la barre d'état ; deux boutons ronds flous, retour et
  partage, fixes pendant la lecture ; titre en gras, source et date ; le
  texte. Un résumé mène à la fiche du match, un titre de média à l'article
  d'origine (« Lire l'article sur RMC Sport »). Ouverture en glissant depuis
  la droite, comme FotMob.
- **Accueil** : un article s'ouvre dans sa page, et non plus dans une feuille
  en bas d'écran ; « Voir tout » mène à la page Actus.
- **Compte** : raccourci « Actualités » (section Mon activité), avec le nombre
  d'articles pas encore ouverts.
- Les dates des articles (« Il y a 2 h ») suivent la langue de l'application.

## Construction

```
.\tool\build.ps1 -Canal direct -ApiUrl https://pronowin.space/api/v1   # APK direct (GeniusPay)
.\tool\build.ps1 -Canal play   -ApiUrl https://pronowin.space/api/v1   # AAB Google Play (achat intégré seul)
```
