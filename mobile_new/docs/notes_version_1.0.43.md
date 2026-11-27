# Version 1.0.43 (59) — la courbe et le bilan comptent tout

Préparée le 27 novembre 2026, après la 1.0.42 (58).

## La courbe du résultat net (page Bankroll)

- Elle compte désormais les combinés et les couvertures enregistrées. Une
  mise couverte compte pour son total (mise + couverture). Le dernier point
  vaut le résultat net affiché au-dessus.
- Elle porte sur tout l'historique, pas seulement sur les cinquante dernières
  mises reçues, et suit l'ordre des règlements, pas l'ordre des mises. Le
  serveur l'envoie. Au-delà de 200 mises, seules les dernières sont tracées,
  et l'écran l'écrit : « Les 200 dernières mises sur 250 ».
- La ligne pointillée « Point de départ (0) » se trace à zéro. Elle se
  traçait à hauteur du budget, hors du cadre, par-dessus la carte voisine.
- Le compteur dit « N mises réglées », combinés compris.

## « Cette semaine »

- Les sept derniers jours se comptent d'après la date du **règlement**. Un
  pari posé il y a dix jours et gagné hier y entre.
- Le résultat de la semaine compte les combinés et les couvertures, sur tout
  l'historique.
- Une ligne « Combinés : N · Gagnés : N » s'ajoute quand un combiné a été
  réglé dans la semaine. Le taux de réussite reste celui des sélections
  simples, comme dans le bandeau.

## « Mes statistiques » et bilan (serveur, en ligne dès le déploiement)

Ces corrections valent aussi pour les versions déjà installées.

- **Profit net, misé et rentabilité** comptent les combinés et les
  couvertures. Le profit net est celui de la page Bankroll. Le taux de
  réussite, les séries, la meilleure cote et la répartition par compétition
  jugent toujours les sélections simples.
- **Évolution bankroll (30 jours)** : le solde de chaque jour vient du journal
  des mouvements. L'ancienne courbe partait du solde actuel moins les gains
  des paris réglés. Elle ignorait les mises en cours, les réinitialisations,
  les changements de budget, les combinés et les couvertures, et ne finissait
  donc pas sur le solde réel. Les jours d'avant l'ouverture de la bankroll ne
  sont plus tracés à zéro.
- `/bankroll/stats` suit les mêmes règles.

## Déjà en ligne depuis la 1.0.42

- Les alertes de couverture ont un texte revu : l'action en tête, la mise
  concernée, « avant le match » ou la minute, et pas de « quel que soit le
  résultat » quand un résultat rembourse les deux mises. La seconde alerte
  remplace la première sur le téléphone.
- Un combiné ouvert depuis une notification a un bouton retour qui remonte à
  la bankroll.

## À faire à la publication

- **Serveur** : déployer (aucune migration).
- **APK direct** : publier la 1.0.43.
- **Google Play** : importer l'AAB 1.0.43.
- **App Store** : ne pas soumettre le build iOS de cette révision, construit
  avec le volet pari (`SANS_PARI_IOS: "false"`).
