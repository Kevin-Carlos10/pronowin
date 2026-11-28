# Version 1.0.41 (57) — alerte de couverture

Préparée le 27 novembre 2026, après la 1.0.40 (56).

## Couvrir sa mise quand les cotes bougent

Quand une sélection validée dans la bankroll est encore ouverte et que la
cote de l'évènement inverse monte assez, miser dessus garantit un gain quel
que soit le résultat. PronoWin le calcule et prévient.

- **Validation d'une sélection** : un champ facultatif « Cote obtenue », la
  cote à laquelle l'abonné a réellement misé. Sans lui, le calcul part de la
  cote recommandée.
- **Notification** (serveur, en ligne depuis le 26 novembre) : dès que la
  mise sur l'inverse garantit au moins le seuil choisi du gain potentiel, une
  notification dit combien miser et sur quoi. Une seule par mise. Lecture en
  direct toutes les 2 min, et avant le match toutes les 30 min dans les
  6 dernières heures. Elle part déjà vers les versions installées ; la 1.0.41
  la range avec les notifications de match.
- **Fiche du match** : carte « Couvrir ma mise » pour chaque sélection
  ouverte : l'inverse et sa cote du moment, la mise à placer, le gain garanti
  et sa part du gain potentiel. L'abonné peut saisir la cote qu'on lui
  propose : le calcul se refait sur place.
- **Réglages › Notifications** : section « Bankroll » avec l'interrupteur
  « Alerte de couverture » et le seuil (30, 50 ou 70 %, 50 % par défaut).

Marchés couverts : résultat ↔ double chance inverse, Plus ↔ Moins de N,5
buts, les deux équipes marquent oui ↔ non. Pas de couverture pour le score
exact, les handicaps et les lignes entières (un remboursement est possible).

## iPhone

- Le volet pari (cotes, bankroll, alerte de couverture) revient sur iPhone
  par un interrupteur de compilation : `SANS_PARI_IOS` vaut `"false"` dans
  `codemagic.yaml`. Le paiement iPhone reste l'achat intégré seul.
- **Avant toute soumission à Apple** : remettre `SANS_PARI_IOS: "true"`.

## À faire à la publication

- **Serveur** : rien de nouveau (déjà déployé jusqu'à 09bbebb).
- **APK direct** : publier la 1.0.41.
- **Google Play** : importer l'AAB 1.0.41.
- **App Store** : ne pas soumettre le build iOS de cette révision, construit
  avec le volet pari.
