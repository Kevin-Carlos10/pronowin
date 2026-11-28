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
- **La note de la boutique n'est plus demandée au lancement** (refus Apple
  du 2 novembre 2026, règle 5.6.3). L'ancienne version la demandait à
  l'ouverture de l'app dès la troisième fois. Elle n'est plus proposée que
  pendant la lecture d'une fiche de match (30 secondes), après cinq
  ouvertures sur sept jours au moins et trois fiches lues, puis pas avant
  trente jours. « Noter l'application » dans les Paramètres ne change pas.
- **App Store et Google Play : l'écran Premium s'ouvre directement**, sans
  « Compléter le profil » (prénom, nom, date de naissance, téléphone). Le
  relecteur d'Apple, venu tester l'abonnement, était bloqué sur ce
  formulaire, et un achat intégré n'a besoin d'aucune de ces informations
  (règle 5.1.1). L'APK direct le garde avant le paiement Mobile Money.
- « (facultatif) » traduit sur l'écran de profil en anglais.

## Refus Apple du 2 novembre 2026 (1.0.23 (50), examinée sur iPad Air)

1. **5.6.3** — note demandée au lancement : corrigé dans cette version.
2. **2.3.6** — « Jeux de hasard » doit passer à **Oui** : réglage de la
   classification d'âge dans App Store Connect, à faire par le titulaire du
   compte. Le 11 octobre, Apple a refusé ce réglage pour un compte
   individuel : décision à prendre (voir `reponse_apple_2026-11-02.md`).
3. **2.1** — « a fully set up demo account » : le compte de démonstration
   n'avait pas de profil complet, et l'app ouvre « Compléter le profil » avant
   l'écran Premium. Le script `npm run review:provision` le remplit désormais
   (`backend/docs/APP_STORE_REVIEW.md`), à lancer sur le serveur.

Pour soumettre, la version App Store « 1.0.23 » est à renommer « 1.0.33 »
et le build iOS 1.0.33 (49) à choisir.

## Construction

```
.\tool\build.ps1 -Canal direct -ApiUrl https://pronowin.space/api/v1   # APK direct (GeniusPay)
.\tool\build.ps1 -Canal play   -ApiUrl https://pronowin.space/api/v1   # AAB Google Play
```
