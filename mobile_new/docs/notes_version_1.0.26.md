# Version 1.0.26 (42) — badge bleu des membres Premium

Préparée le 20 octobre 2026, à la suite de la 1.0.25 (voir
`notes_version_1.0.25.md`).

## Ce qui change dans l'app

- **Badge bleu Premium**, comme le badge de vérification d'Instagram : un
  sceau bleu à coche blanche à côté du nom des membres Premium — dans les
  commentaires, le classement (podium et liste ; il remplace la petite
  couronne dorée) et sur sa propre page Compte. Lecteurs d'écran : « Membre
  Premium ».

## Côté serveur

- Les commentaires portent le statut Premium de leur auteur
  (`user.isPremium`, échéance comprise) : sans lui, une app plus ancienne
  n'affiche simplement pas de badge.
- Alertes des matchs suivis : mi-temps, cartons rouges, compositions
  officielles (5881c49).

## Construction

```
.\tool\build.ps1 -Canal direct -ApiUrl https://pronowin.space/api/v1   # APK direct (GeniusPay)
.\tool\build.ps1 -Canal play   -ApiUrl https://pronowin.space/api/v1   # AAB Google Play (achat intégré seul)
```
