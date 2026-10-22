# Version 1.0.29 (45) — avant-matchs à part, bulle de la cloche, résumé prêt

Préparée le 22 octobre 2026, à la suite de la 1.0.28 (voir
`notes_version_1.0.28.md`). Côté serveur : la notification « Le résumé est
prêt » (`resumes_match.service.ts`), à déployer ; les avant-matchs sont en
ligne depuis le 22 octobre (`avant_matchs.service.ts`).

## Ce qui change dans l'app

- **Page Actus** : un onglet **Avant-matchs**, à part des **Résumés**. Les
  avant-matchs s'écrivent seuls la veille des matchs pronostiqués et des
  grandes compétitions (classement, forme, face-à-face, absents) ; les
  versions 1.0.25 à 1.0.28 les rangeaient avec les résumés.
- **Étiquette** sur chaque article de match : « Avant-match · Premier League »
  (pastille bleue, calendrier) ou « Résumé · Ligue 1 » (pastille verte,
  ballon), à la place de « PronoWin ». Le titre d'un avant-match perd son
  préfixe « Avant-match : », que l'étiquette dit déjà. Le visuel d'un
  avant-match : les deux logos et « VS ».
- **« Le résumé est prêt »** : la notification envoyée à ceux qui suivent un
  match ouvre directement son résumé (`/actualites/article?id=…`). Les
  versions précédentes ouvrent la page Actus, où le résumé d'un match suivi
  passe en tête. Un résumé qui a quitté le fil : la page Actus.
- **Bulle de la cloche** : la première fiche de match ouverte (pas terminé,
  pas déjà suivi) présente la cloche — « Sois alerté des buts, de la
  mi-temps et du résumé. » avec un bouton « Suivre ». Une seule fois par
  appareil ; le premier toucher ailleurs la ferme. Elle tient dans l'en-tête,
  sans cacher la barre d'onglets, même texte agrandi. Les alertes des matchs
  suivis ne touchaient que quatre personnes.

## Construction

```
.\tool\build.ps1 -Canal direct -ApiUrl https://pronowin.space/api/v1   # APK direct (GeniusPay)
.\tool\build.ps1 -Canal play   -ApiUrl https://pronowin.space/api/v1   # AAB Google Play (achat intégré seul)
```
