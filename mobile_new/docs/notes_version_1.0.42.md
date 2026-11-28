# Version 1.0.42 (58) — couverture complète et coupons combinés

Préparée le 27 novembre 2026, après la 1.0.41 (57).

## « J'ai couvert » : la couverture entre dans la bankroll

- La carte « Couvrir ma mise » a un bouton « J'ai couvert ». L'abonné y
  confirme ou corrige la mise placée sur l'inverse et sa cote. Elle sort du
  solde et se règle avec le match : elle gagne quand la sélection perd, et
  les deux sont remboursées ensemble.
- Une mise couverte affiche sa couverture et un résultat net qui compte les
  deux mises. La notification de résultat donne ce total.
- Une fois couverte, une mise ne reçoit plus d'alerte.

## Deux façons de couvrir

- **Gain égal** : on gagne la même chose quel que soit le résultat (comme
  avant).
- **Récupérer ma mise** : si l'inverse passe, on récupère sa mise ; si la
  sélection passe, on garde l'essentiel du gain. Exemple : 1 000 F à 2,00,
  l'inverse à 4,00 → 334 F dessus, +666 F ou +2 F.
- La notification propose les deux.

## Coupons combinés

Décisions de l'utilisateur du 27 novembre 2026 : de 2 à 10 sélections ; des
pronostics PronoWin ou des sélections libres ; une mise qui suit le barème
de la sélection la moins sûre.

- Page Bankroll › « Nouveau combiné » :
  - choisir des pronostics PronoWin à venir (le pronostic principal de chaque
    match) et ajouter des sélections libres (match, sélection, cote) ;
  - la cote totale et la mise s'affichent avant de valider. La mise est
    calculée par le serveur et verrouillée, comme pour une mise simple ; une
    sélection libre compte pour la note 1 (1,5 % du solde).
- Deux sélections du même match ne se combinent pas.
- Un pronostic VIP n'entre dans un combiné que pour un abonné.
- Règlement :
  - les pronostics PronoWin se règlent tout seuls ; l'abonné règle ses
    sélections libres (Gagnée, Perdue, Remboursée) ;
  - une sélection perdue suffit pour que le combiné perde ;
  - une sélection remboursée, ou annulée parce que le pronostic a été retiré
    ou modifié avant le coup d'envoi, compte pour une cote de 1.
- Couverture d'un combiné : quand il ne reste qu'une sélection PronoWin à
  jouer et que toutes les autres sont passées, on couvre son inverse contre
  le gain du combiné entier. Même alerte, même carte, même « J'ai couvert ».
- Le classement ne compte pas les combinés.

## Alertes plus fines (serveur, déjà en ligne au déploiement)

- **Seconde alerte** : si la couverture atteint ensuite 80 % du gain
  potentiel. Deux alertes au plus par mise.
- **Dernière heure avant le match** : une lecture des cotes toutes les dix
  minutes (au lieu de trente), quand les compositions tombent.
- **En direct** : la notification donne la minute et le score (« 63e minute,
  1-0 »).
- **Nouveaux marchés couverts** : lignes entières de buts (Plus/Moins de 2)
  et « remboursé si match nul ». La carte dit quand les deux mises sont
  remboursées ensemble (2 buts tout juste, match nul). Le « remboursé si
  match nul » se règle désormais automatiquement.

## Panneau

- En direct, le formulaire propose aussi le « remboursé si match nul ». Les
  quarts de ligne de buts (2,25) ne sont plus proposés : le règlement
  automatique ne coupe pas la mise en deux.

## À faire à la publication

- **Serveur** : déployer (migration `20261127090000_combines_couvertures`).
- **APK direct** : publier la 1.0.42.
- **Google Play** : importer l'AAB 1.0.42.
- **App Store** : ne pas soumettre le build iOS de cette révision, construit
  avec le volet pari (`SANS_PARI_IOS: "false"`).
