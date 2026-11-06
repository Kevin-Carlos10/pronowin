# Version 1.0.18 (build 34) — iPhone

Mise à jour qui suit la première publication (1.0.16, build 30). La même
version est en ligne sur Android depuis le 6 octobre 2026 (Google Play et APK
du site).

## Envoi vers TestFlight

Codemagic → PronoWin → **Start new build** → workflow « iOS — envoi vers
TestFlight » → branche **`chore/panneau-admin-etats-vides-et-injections`**
(`main` ne connaît pas encore ce workflow). Le build portera le numéro 34 :
celui du `pubspec.yaml`, supérieur au dernier reçu par TestFlight.

Aucun changement côté iOS depuis le build 30 : ni `ios/`, ni dépendances
(`pubspec.lock` identique).

Codemagic construit ce qui est poussé (f2da5f8 et suivants), pas la copie de
travail : le chantier de traduction des données football, en cours et non
commité le 7 octobre, n'y est pas. Conséquence connue, comme sur Android
1.0.18 : en anglais, les sélections s'affichent en français (« Belgique »).
Ce chantier la corrige ; il partira dans la version suivante.

## Soumission — seulement après l'approbation de la 1.0.16

App Store Connect n'accepte pas de nouvelle version tant que la précédente est
en examen. Une fois la 1.0.16 approuvée :

1. Distribution → **+** à côté de « App iOS » → version **1.0.18**.
2. Section « Build » → choisir **1.0.18 (34)**.
3. Coller le texte ci-dessous dans « Nouveautés de cette version ».
4. La classification par âge reste celle acceptée (« Jeux de hasard : Oui »,
   18+) : elle est portée par l'app, pas par la version.
5. **Ajouter pour vérification**, puis soumettre.

## Nouveautés de cette version (français)

```
Nouveautés de la version 1.0.18

• Fiches équipe et joueur : effectif, stade, entraîneur, saison par compétition, absences et transferts.
• Classements enrichis : meilleurs passeurs et cartons, en plus des buteurs.
• Matchs en direct plus fiables, et une fiche du match plus claire.
• Les sélections nationales s'affichent en français.
• Accueil plus stable au chargement ; la barre des dates reste sur le jour choisi.
• Historique plus lisible : pronostics remboursés présentés comme tels, libellés en français.
• Tutoriels, profil, parrainage et compte : nombreuses finitions d'affichage.
• Les pages légales s'ouvrent sans quitter l'application.
```

## What's New (English, si la fiche anglaise existe)

```
What's new in version 1.0.18

• Team and player pages: squad, stadium, coach, season by competition, injuries and transfers.
• Richer standings: top assists and cards, in addition to top scorers.
• More reliable live matches and a clearer match page.
• Steadier home screen while loading; the date bar stays on the selected day.
• Clearer history: refunded predictions are shown as such.
• Tutorials, profile, referral and account: many display refinements.
• Legal pages open without leaving the app.
```
