# Version 1.0.26 (42) — badge bleu des membres Premium

Préparée le 20 octobre 2026, à la suite de la 1.0.25 (voir
`notes_version_1.0.25.md`).

## Ce qui change dans l'app

- **Badge bleu Premium**, comme le badge de vérification d'Instagram : un
  sceau bleu à coche blanche à côté du nom des membres Premium — dans les
  commentaires, le classement (podium et liste ; il remplace la petite
  couronne dorée) et sur sa propre page Compte. Lecteurs d'écran : « Membre
  Premium ».
- **Partager mon code (Parrainage)** : le bouton ouvre enfin la feuille de
  partage du téléphone (WhatsApp, SMS, Telegram…). Ses trois options ne
  faisaient que copier le texte. Le partage est ancré sur le bouton, ce
  qu'iOS exige sur iPad (page Compte aussi). Si la feuille ne s'ouvre pas, le
  message est copié et l'app le dit.
- **Actualités** : un résumé de match, sans photo, montre les deux logos et
  le score. Les photos des articles de médias reviennent (côté serveur, pour
  toutes les versions).
- **Fiche du match** : plus aucune mention d'actualisation (« toutes les
  2 minutes », « toutes les cinq minutes ») ; restent les seuls avertissements
  d'une donnée qui n'arrive plus.

## Côté serveur

- Les commentaires portent le statut Premium de leur auteur
  (`user.isPremium`, échéance comprise) : sans lui, une app plus ancienne
  n'affiche simplement pas de badge.
- Alertes des matchs suivis : mi-temps, cartons rouges, compositions
  officielles (5881c49).
- Actualités : la photo jointe au flux du média, à son adresse d'origine —
  leur CDN la sert à tous ; le relais qui usurpait le Referer était inutile.
  Résumés de match : `logo_domicile`, `logo_exterieur`, `score`.

## Construction

```
.\tool\build.ps1 -Canal direct -ApiUrl https://pronowin.space/api/v1   # APK direct (GeniusPay)
.\tool\build.ps1 -Canal play   -ApiUrl https://pronowin.space/api/v1   # AAB Google Play (achat intégré seul)
```
