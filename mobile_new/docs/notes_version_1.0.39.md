# Version 1.0.39 (55) — plusieurs pronostics par match, taux réservé aux abonnés, connexion en feuille

Préparée le 24 novembre 2026, après la 1.0.38 (54).

## Plusieurs pronostics par match

- **Liste** : la carte d'un match annonce « +1 prono », « +2 pronos »… quand
  d'autres pronostics s'ajoutent au principal. Si le principal est VIP et
  verrouillé mais qu'il y en a d'autres, la carte ouvre la fiche au lieu de
  l'offre Premium : un compte gratuit y voit les pronostics gratuits.
- **Fiche du match** : une section « Autres pronostics » sous le principal.
  Chacun a son choix, sa confiance, son résultat, sa note d'analyste et sa
  cote (pas de cote sur iPhone). Un pronostic VIP reste verrouillé pour un
  compte gratuit (« Pronostic VIP — Réservé aux membres Premium », qui mène à
  l'offre) ; son résultat reste visible.
- **Serveur** : si le principal d'un match est un brouillon ou dépublié alors
  qu'un autre pronostic est publié, ce dernier devient le principal.

## Le taux de réussite, aux seuls abonnés Premium

Décision de l'utilisateur du 23 novembre 2026 (« partout », sans cadenas à
la place).

- Pour un compte gratuit ou un invité : plus de tuile « Réussite » à
  l'accueil, plus de bilan ni de courbe de réussite dans l'Historique, plus
  d'entrée « Performance » dans le Compte (la page est réservée aux abonnés).
  Le résultat de chaque pronostic reste visible.
- Déjà en place côté serveur depuis le 23 novembre : le taux ne part plus
  vers un non-abonné, ni vers le site ; le « Bilan de la semaine » ne porte
  plus que la semaine personnelle.

## Historique des paiements et reçus

- Compte > Paiements : abonnements payés ou offerts, paiements en cours,
  échoués, à vérifier ou remboursés, preuves en vérification ou refusées
  (avec le motif). Pas sur iPhone.

## Connexion en feuille « Connexion ou inscription »

D'après l'écran montré par l'utilisateur le 24 novembre 2026.

- Feuille blanche aux coins arrondis sur le bleu nuit (sombre sur noir en
  thème sombre), boutons ronds retour et fermer autour du titre.
- Carte de trois avantages réels : suivre ses équipes, alertes des matchs
  suivis, favoris sur tous ses appareils.
- Chemins en rectangles et capitales : Google, Apple (plein, iPhone
  seulement), e-mail. Consentement juste dessous, « Besoin d'aide ? » en bas.

## À faire à la publication

- **Serveur** : déployer (principal toujours publié).
- **APK direct** : publier la 1.0.39.
- **Google Play** : importer l'AAB 1.0.39.
- **App Store** : le build iOS de cette révision est la 1.0.39 (55).
