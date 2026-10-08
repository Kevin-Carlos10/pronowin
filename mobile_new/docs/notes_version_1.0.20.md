# Version 1.0.20 (build 36)

Préparée le 8 octobre 2026 pour un essai sur iPhone par TestFlight (workflow
Codemagic « iOS — envoi vers TestFlight », branche
`chore/panneau-admin-etats-vides-et-injections`). Le numéro de build vaut un
de plus que le dernier reçu par TestFlight, jamais moins que 36.

Contenu par rapport à la 1.0.19 — une refonte inspirée d'Instagram, Threads et
Sofascore, mesurée sur des vidéos côte à côte :

- barre de navigation flottante façon Instagram : icônes seules, pleines sur
  l'onglet ouvert, pastille qui glisse (a7fa1be) ; même géométrie que Threads
  — 61 pt, à 21 pt du bord sur iPhone, marges de 21 pt — et verre dépoli
  (f79debf) ;
- textes : tailles agrandies de 20 % pour rejoindre celles de Threads, le
  réglage de taille du téléphone s'appliquant toujours par-dessus ; lettres
  resserrées comme iOS, interligne naturel (f79debf) ; graisses ramenées de
  800–900 à 700 (a7fa1be) ;
- fiche de match : tous les marchés cotés dans l'onglet Cotes, triés par
  famille ; forme récente des deux équipes ; classement Général, Domicile,
  Extérieur et Forme (9a632de, 08a81ac). Le serveur qui les sert est en
  production depuis le 8 octobre (révision 08a81ac).

## Nouveautés (Google Play, 500 caractères au plus)

```
• Nouvelle barre de navigation, plus légère et translucide.
• Textes plus grands et plus lisibles, qui suivent la taille choisie sur votre téléphone.
• Fiche de match enrichie : toutes les cotes, la forme récente des deux équipes et le classement à domicile, à l'extérieur et en forme.
• Corrections et améliorations.
```

## What's new (English)

```
• New navigation bar, lighter and translucent.
• Larger, more readable text that follows your phone's text size.
• Richer match page: all odds, both teams' recent form, and home, away and form standings.
• Fixes and improvements.
```
