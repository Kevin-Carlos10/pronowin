# Version 1.0.22 (build 38)

Préparée le 11 octobre 2026 depuis la révision dadba04 (serveur déployé à la
même révision) :

- contenu Premium : ce que le serveur masque reste masqué partout, même si le
  compte local se croit Premium ; une confiance absente n'affiche plus 10 % ;
- un pronostic remboursé ne s'affiche plus « Perdu » sur l'accueil (96e5cd1) ;
- « Valider ma sélection » à la place de « Miser », sans transfert d'argent ;
  résumé Bankroll réorganisé ;
- tutoriels : en-tête compact, vidéo avant la description, objectifs,
  chapitres, quiz et exercice « value bet » fictif — à remplir dans le panneau ;
- Paramètres : sessions de cet appareil ;
- textes agrandis : bouton de sélection et boutons Telegram/WhatsApp ne
  débordent plus à 180 % sur 360 px.

Livraison : APK direct dans `/downloads` et `APK_LATEST_VERSION=1.0.22` (mise
à jour non obligatoire) ; AAB Google Play
`build/app/outputs/bundle/playRelease/app-play-release.aab` à envoyer dans la
Play Console (remplace la 1.0.20 / 1.0.21 si elles n'ont pas été envoyées) ;
iPhone par Codemagic (workflow « iOS — envoi vers TestFlight »).

App Store : la 1.0.16 a été refusée le 11 octobre (compte individuel + jeux
de hasard). Cette version garde l'onglet Bankroll : elle ne règle pas ce
refus.

## Nouveautés (Google Play, 500 caractères au plus)

```
• Nouvelle barre de navigation et textes plus lisibles.
• Fiche de match enrichie : toutes les cotes, la forme récente côte à côte, le classement à domicile et à l'extérieur.
• Tutoriels repensés : objectifs, chapitres et quiz.
• Suivi de vos sélections plus clair.
• Contenu Premium mieux protégé, pronostics remboursés correctement affichés.
• Corrections et améliorations.
```

## What's new (English)

```
• New navigation bar and more readable text.
• Richer match page: all odds, recent form side by side, home and away standings.
• Redesigned tutorials: objectives, chapters and quizzes.
• Clearer tracking of your selections.
• Better protected Premium content, refunded predictions shown correctly.
• Fixes and improvements.
```
