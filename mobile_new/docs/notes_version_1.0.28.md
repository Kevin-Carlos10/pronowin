# Version 1.0.28 (44) — saisie des commentaires sans tremblement

Préparée le 20 octobre 2026, à la suite de la 1.0.27 (voir
`notes_version_1.0.27.md`). Rien à déployer côté serveur.

## Ce qui change dans l'app

- **Commentaires d'un match** : signalé le 20 octobre — « quand tu cliques
  sur le champ de texte pour ouvrir le clavier, l'écran tremble deux ou trois
  fois avant de se stabiliser ». Mesuré : le champ vivait au bas de l'onglet
  Détails, sous l'en-tête repliable ; pendant que le clavier montait, la page
  défilait à chaque image pour le garder visible, et l'en-tête se repliait.
  Comme sur Instagram ou Sofascore, toucher le champ ouvre désormais une
  feuille de saisie posée au-dessus du clavier, qui monte avec lui ; la page
  derrière ne bouge plus d'un pixel. Le brouillon survit à la fermeture de la
  feuille, « Répondre » l'ouvre avec le nom de la personne, et un envoi refusé
  affiche son message dans la feuille sans effacer le texte.

## Construction

```
.\tool\build.ps1 -Canal direct -ApiUrl https://pronowin.space/api/v1   # APK direct (GeniusPay)
.\tool\build.ps1 -Canal play   -ApiUrl https://pronowin.space/api/v1   # AAB Google Play (achat intégré seul)
```
