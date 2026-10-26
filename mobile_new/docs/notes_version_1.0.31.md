# Version 1.0.31 (47) — la page Historique refaite

Préparée le 25 octobre 2026, à la suite de la 1.0.30 (voir
`notes_version_1.0.30.md`). Rien à déployer côté serveur.

## Ce qui change dans l'app

- **Un bilan juste.** La réussite porte sur les seuls pronostics gagnés et
  perdus, et ne s'affiche qu'à partir de dix (le seuil du serveur). Elle
  divisait par tous les pronostics, remboursés compris, et la légende
  comptait les remboursés comme des défaites. Les remboursés ont désormais
  leur part dans la barre et la légende.
- **Série en cours et meilleure série** sur la période ; un remboursé ne
  coupe pas une série.
- **Réussite des gratuits et des Premium**, chacune dès dix pronostics
  gagnés ou perdus, et un filtre Tous les pronostics / Gratuits / Premium.
- **Filtres** : Tous, Gagnés, Perdus, Remboursés. Le filtre « En attente »
  était toujours vide — le serveur n'envoie que des pronostics réglés.
- **La liste par jour**, au modèle de Sofascore : « Aujourd'hui », « Hier »,
  « Samedi 18 octobre », avec le bilan du jour (une pastille par pronostic,
  gagnés sur gagnés ou perdus). Chaque ligne montre les deux équipes l'une
  sous l'autre, leur logo et leur score (le vainqueur en gras), la
  compétition et l'heure, le pronostic, et le résultat à droite. Un
  pronostic Premium ouvert à l'abonné porte un badge.
- **Une ligne ouvre la fiche du match** ; verrouillée (Premium, non abonné),
  elle mène à l'offre, comme avant.
- **Le retour fonctionne depuis la notification « Bilan de la semaine »**,
  qui ouvre la page seule : il mène à l'accueil.
- Tirer vers le bas actualise ; « Réessayer » en cas d'erreur ; sur iPhone,
  l'export CSV n'a plus de colonne « Cote ».

## Construction

```
.\tool\build.ps1 -Canal direct -ApiUrl https://pronowin.space/api/v1   # APK direct (GeniusPay)
.\tool\build.ps1 -Canal play   -ApiUrl https://pronowin.space/api/v1   # AAB Google Play (achat intégré seul)
```
