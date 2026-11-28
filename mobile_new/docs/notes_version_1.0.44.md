# Version 1.0.44 (60) — la fiche d'un match gagné

Préparée le 27 novembre 2026, après la 1.0.43 (59), d'après deux captures
de l'utilisateur (Werder Brême – M'gladbach 3-3, Nottingham Forest – Chelsea
3-2).

## Le bandeau « Pronostic gagnant »

- Le bandeau est animé à la première consultation d'un pronostic gagné.
  Aux consultations suivantes, l'animation ne se rejouait pas, comme prévu,
  mais restait bloquée à son point de départ :
  - la coche et « Pronostic gagnant » restaient transparents ;
  - le bandeau restait un peu rétréci ;
  - le reflet lumineux restait figé à gauche.
- Sur chaque pronostic gagné déjà consulté, la carte montrait donc une
  barre verte vide.
- Désormais, déjà célébré, le bandeau s'affiche dans son état final. Même
  chose en animations réduites, et quand un résultat est corrigé en
  « gagné » pendant que la fiche est ouverte.

## Les buteurs sous le score

- À côté de minutes longues (« 51' (pen.), 72' »), le nom du buteur se
  réduisait à « M. ... ».
- L'en-tête prend maintenant le nom le plus complet qui tient à côté des
  minutes : « M. Gibbs-White », sinon « Gibbs-White ». Les minutes restent
  entières.

## Panneau d'administration (serveur, en ligne au déploiement)

- **Formulaire de pronostic** : la traduction anglaise devient une section
  repliée près de la note analyste. Les types de pronostic utilisent les
  icônes du panneau. Sur petit écran, l'aperçu « Ce que l'abonné verra »
  passe avant le formulaire.
- **En-têtes de page** : plus compacts.
- **Tuiles de chiffres** : à la hauteur de leur contenu.
- **Séparateurs de milliers** : visibles (« 1 921 500 » et non plus
  « 1921500 »).

## À faire à la publication

- **Serveur** : déployer (aucune migration).
- **APK direct** : publier la 1.0.44.
- **Google Play** : importer l'AAB 1.0.44.
- **App Store** : ne pas soumettre le build iOS de cette révision, construit
  avec le volet pari (`SANS_PARI_IOS: "false"`).
