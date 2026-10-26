# Version 1.0.32 (48) — notification lue, article et vote dans la fiche

Préparée le 25 octobre 2026, à la suite de la 1.0.31 (voir
`notes_version_1.0.31.md`). Côté serveur : la push porte l'identifiant de
la notification enregistrée (`notification_id`), à déployer — sans effet sur
les versions déjà installées, qui l'ignorent.

## Ce qui change dans l'app

- **Une notification ouverte depuis l'écran du téléphone est marquée lue.**
  Seul le toucher dans la liste de l'application le faisait : le compteur
  rouge restait allumé pour des notifications déjà ouvertes, et la part
  « lue » de la carte Engagement du panneau était sous-estimée (14 % sur la
  semaine du 18 octobre). Cela vaut pour une notification touchée app
  fermée, app en arrière-plan, ou reçue app ouverte (notification locale
  sur Android).
- Une notification reçue app ouverte prend, dans la liste, l'identifiant du
  serveur : la marquer lue depuis la liste atteint la bonne.
- Les campagnes du panneau (envoi par segment) ne portent pas d'identifiant
  par personne : elles restent marquées lues depuis la liste seulement.

## La fiche du match

- **L'avant-match et le résumé dans la fiche** (26 octobre 2026), sous le
  pronostic : avant le match l'avant-match, après le résumé — étiquette,
  titre, premier paragraphe sur deux lignes. Un toucher ouvre l'article,
  qui ne renvoie alors pas à la fiche. Le serveur en écrit plus de cent par
  semaine ; on ne les trouvait que dans la page Actus.
- **« Qui va gagner ? », le vote des fans**, comme sur Sofascore : avant
  le coup d'envoi, trois choix (domicile, nul, extérieur) ; une fois voté,
  la répartition, son vote en évidence, modifiable jusqu'au coup
  d'envoi. Le match commencé, les votes sont clos et la répartition reste
  visible. Un invité est emmené s'inscrire. Ni mise ni cote : la carte
  s'affiche aussi sur iPhone. Côté serveur : table `votes_match`,
  `GET /pronostics/:id/votes`, `POST /pronostics/:id/vote`, et
  `GET /pronostics/:id/articles` — à déployer.

## Construction

```
.\tool\build.ps1 -Canal direct -ApiUrl https://pronowin.space/api/v1   # APK direct (GeniusPay)
.\tool\build.ps1 -Canal play   -ApiUrl https://pronowin.space/api/v1   # AAB Google Play (achat intégré seul)
```
