# Version 1.0.25 (41) — suivre un match, page Actualités

Préparée le 18 octobre 2026. Android d'abord (APK direct et Google Play,
**à la place de la 1.0.24** si celle-ci n'a pas encore été envoyée dans la Play
Console) ; l'iPhone attend l'approbation de la 1.0.23 par Apple.

Elle contient tout ce qu'apportait la 1.0.24 (fiche de match au style
Sofascore, chrono à la seconde, compositions, statistiques par mi-temps,
historique Premium verrouillé, message neutre sur Google Play) — voir
`notes_version_1.0.24.md`.

## Ce qui change dans l'app

- **Suivre un match** : le marque-page « Ajouter aux favoris » devient une
  cloche « Suivre ce match », partout (fiche du match, cartes de match, cartes
  de l'accueil, bloc « Matchs suivis »). Le premier appui dit ce qu'on
  recevra : « Match suivi : tu recevras le coup d'envoi, les buts et le
  résultat. » — ou prévient si les alertes de match sont coupées dans les
  Paramètres, avec un bouton « Activer ». Un seul match avait été mis en favori
  en trente jours : les alertes de but ne touchaient presque personne.
  L'onglet « Favoris » des pronostics devient « Suivis ».
- **Informations du match** au modèle de Sofascore : tour, saison, stade,
  ville, arbitre, tirs au but — sans état du match ni « Actualisé à… »
  (0448847). « Actualisé à » disparaît de toute la fiche ; seul reste
  l'avertissement d'un relevé interrompu.
- **Page Actualités** : « Voir tout » sur l'accueil ouvre une page complète
  (jusqu'à 50 articles), filtrable — Tout, Résumés de match, Médias, PronoWin.
- **Résumés de match** : « Voir la fiche du match » ouvre le match résumé.
- **Images des médias** : l'app ne se fait plus passer pour RMC Sport ou la BBC
  (en-tête Referer) pour charger leurs images.

## Côté serveur

- `GET /actualites?limite=50` pour la page Actualités (l'accueil reste à 20).
  Un serveur plus ancien en rend vingt : la page fonctionne aussi.
- Déjà en ligne : résumés automatiques des matchs pronostiqués (85bf267),
  alertes de but, bilan de la semaine.

## Construction

```
.\tool\build.ps1 -Canal direct -ApiUrl https://pronowin.space/api/v1   # APK direct (GeniusPay)
.\tool\build.ps1 -Canal play   -ApiUrl https://pronowin.space/api/v1   # AAB Google Play (achat intégré seul)
```
