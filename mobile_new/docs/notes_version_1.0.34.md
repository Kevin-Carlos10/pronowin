# Version 1.0.34 (50) — une interface au niveau de Sofascore et FotMob

Préparée le 7 novembre 2026, à la suite de la 1.0.33 (en examen chez Apple
sous le build 58). Comparaison vidéo de PronoWin avec Sofascore et FotMob
(IMG_8927, IMG_8928), quatre idées reprises de 1xBet sans rien de ce qui sert
à parier, et le code promo du partenaire sur toutes les versions (décision du
titulaire du compte). Serveur déjà déployé (11e51a3) : séries, recherche
d'équipes et de joueurs, évolution au classement, `promoCode` dans `/config`.

## Ce qui change dans l'app

- **Liste des matchs compacte** : un match sans pronostic tient sur une ligne
  (heure ou « En direct », équipes et logos, score, cloche), les lignes d'une
  ligue dans un même bloc. La grande carte reste aux matchs qui ont un
  pronostic.
- **Fiche du match** : formes de cartes pendant le chargement ; « Faits
  marquants » n'apparaît plus vide ; buteurs sous chaque équipe dans
  l'en-tête ; **Séries** (victoires de suite, plus de 2,5 buts 7/10, les deux
  équipes marquent…) pour chaque équipe et leurs face-à-face ; le mieux noté
  du match a sa pastille bleue étoilée ; **évolution au classement** journée
  par journée dans l'onglet Classements.
- **Recherche** : équipes et joueurs, en plus des matchs.
- **Suivre des équipes** : l'étoile de la fiche équipe ; « Mes équipes » et
  leurs prochains matchs dans « Suivis », suggestions sans équipe suivie.
- **Fiche joueur** refaite (note de la saison, identité en cases) et
  **comparaison de deux joueurs**.
- **Logos** : un disque neutre pendant le chargement (le ballon générique
  passait pour un logo absent). **Démarrage** : le logo ne flotte plus sur
  l'accueil, 1,3 s de moins. **Accueil** : vignette « Matchs suivis » lisible.
- **Paramètres** : taille du cache affichée et images vraiment effacées ;
  rubrique « Aide » avec « Présentation de l'application » et « Aperçu
  technique » à copier pour le support.
- **Parrainage** : « Afficher mon code QR ».
- **Code promo du partenaire** (PRONOWIN2026, servi par `/config`) sur toutes
  les versions : carte sur l'accueil, bandeau dans la liste et la fiche des
  matchs, page « Code promo » (copier, étapes, ouvrir le partenaire, mention
  18+, jeu responsable). Le parcours « Premium contre code promo » reste
  réservé à l'APK direct.

## À faire à la soumission

- **App Store** : réécrire les Remarques. Elles disent « no links to or
  promotions for betting operators » : c'est faux à partir de cette version.
  Décrire le code promo tel qu'il est. Ne jamais le masquer pendant l'examen.
- **Google Play** : la déclaration « Contient des annonces » et le
  questionnaire de contenu (jeux d'argent) doivent dire la même chose.
