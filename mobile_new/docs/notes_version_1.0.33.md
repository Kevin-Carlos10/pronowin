# Version 1.0.33 (49) — choisir ses alertes pour chaque match

Préparée le 27 octobre 2026, à la suite de la 1.0.32 (voir
`notes_version_1.0.32.md`). Côté serveur, à déployer : la colonne
`user_favorite_matches.alertes` (migration `20261027090000_alertes_suivi`,
toutes les alertes par défaut, suivis existants compris), les routes
`GET`/`PUT /favorites/:id/alertes`, et le tri des envois par catégorie.

## Ce qui change dans l'app

- **Les alertes au choix, match par match**, comme sur Sofascore. Suivre un
  match envoyait tout : coup d'envoi, compositions, buts, cartons rouges,
  mi-temps, fin du match, résumé — 145 alertes de but pour 8 lues sur la
  semaine du 19 octobre. Le match suivi, la cloche de sa fiche ouvre
  « Alertes pour ce match » : un interrupteur par alerte, trois raccourcis
  (« Tout », « Buts seulement », « Résultat seulement »), et « Ne plus
  suivre ce match ». Chaque choix est enregistré aussitôt ; refusé, il
  revient tel qu'avant avec un message. Aucune alerte : le match reste
  suivi, sans notification. Les alertes de match coupées dans les
  Paramètres : la feuille le dit.
- Un match pas encore suivi : la cloche le suit, avec toutes les alertes.

## Construction

```
.\tool\build.ps1 -Canal direct -ApiUrl https://pronowin.space/api/v1   # APK direct (GeniusPay)
.\tool\build.ps1 -Canal play   -ApiUrl https://pronowin.space/api/v1   # AAB Google Play
```
