# Version 1.0.40 (56) — chiffres VIP sur le mur Premium, autres pronostics complets

Préparée le 24 novembre 2026, après la 1.0.39 (55).

## Le mur Premium retrouve un argument chiffré

Le taux de réussite est réservé aux abonnés depuis le 23 novembre : le mur
Premium, qui s'adresse aux autres, n'avait plus de chiffre à montrer.

- La feuille d'accroche et la page d'offre affichent des chiffres réels,
  calculés par le serveur (`GET /pronostics/chiffres-vip`, en ligne depuis le
  24 novembre) : les pronostics VIP publiés en 30 jours, les compétitions
  couvertes, les pronostics VIP du jour. Des comptes, jamais un taux ; un
  chiffre trop petit pour être annoncé n'apparaît pas.
- La page d'accueil du site affiche les mêmes chiffres (déjà en ligne).

## Bande de preuve de l'accueil (abonnés)

- « 30 derniers pronostics · 18 gagnés · +12 % » ne s'était jamais affichée :
  l'app lisait `total`, le serveur envoie `total_pronostics`. Corrigé.
  Réservée aux abonnés.

## Plusieurs pronostics par match : la suite

- **Fiche du match** : chaque autre pronostic ouvert se valide dans la
  bankroll (« Valider ma sélection », avant le coup d'envoi, pas sur iPhone)
  et se partage en image, comme le principal.
- **Accueil** : les cartes annoncent « +N prono » ; quand le principal est
  VIP et verrouillé mais qu'il y a d'autres pronostics, la carte ouvre la
  fiche plutôt que l'offre.

## À faire à la publication

- **Serveur** : rien de nouveau (déjà déployé jusqu'à 9863ee6).
- **APK direct** : publier la 1.0.40.
- **Google Play** : importer l'AAB 1.0.40.
- **App Store** : le build iOS de cette révision est la 1.0.40 (56).
