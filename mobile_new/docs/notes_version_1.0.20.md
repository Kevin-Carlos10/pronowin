# Version 1.0.20 (build 36)

Fichiers produits le 9 octobre 2026 depuis la révision 77f3b68, signés avec la
clé PronoWin, vérifiés par `tool/verifier_bundle.py` (API de production, aucune
adresse locale, permissions propres à chaque canal) :

- Google Play : `build/app/outputs/bundle/playRelease/app-play-release.aab`
  (53,6 Mo), à envoyer dans la Play Console (Production → Créer une version).
- Téléchargement direct : `build/app/outputs/flutter-apk/` —
  `app-direct-release.apk` (universel, 71 Mo), `app-arm64-v8a-direct-release.apk`
  (26,2 Mo), `app-armeabi-v7a-direct-release.apk` (24,6 Mo). Non publiés dans
  `/downloads` à ce jour.
- iPhone : build Codemagic n°27 (workflow « iOS — envoi vers TestFlight »). Le
  numéro de build iOS suit TestFlight, où la 1.0.20 avait déjà reçu les builds
  38 et 39 (révision 311a709) : celui-ci prendra le suivant.

Contenu par rapport à la 1.0.19 :

- barre de navigation façon Instagram : icônes seules, pleines sur l'onglet
  ouvert, même géométrie que Threads (61 pt, à 21 pt du bord sur iPhone),
  verre dépoli (a7fa1be, f79debf, 77f3b68) ;
- textes : tailles agrandies de 20 %, réglage du téléphone par-dessus ;
  lettres resserrées comme iOS (f79debf) ;
- fiche de match : tous les marchés cotés, forme récente, classement
  Général / Domicile / Extérieur / Forme, équipes qui ouvrent leur fiche
  (9a632de, 08a81ac, 9d3d745) ;
- « Pourquoi ce pronostic » : les barres, invisibles jusqu'ici, s'affichent ;
  critères en clair et expliqués ; vote en pourcentage ; vrais logos WhatsApp
  et Telegram (9d3d745) ;
- revue vidéo du 9 octobre : verrou et Face ID, aperçu multitâche masqué,
  confiance en pourcentages, sources nommées, suivi des mises, partage,
  contexte d'achat transmis au store (41533c2).

Serveur en production depuis le 9 octobre (révision 41533c2). Le refus strict
des achats Apple sans identifiant de compte reste désactivé
(`IAP_EXIGER_COMPTE_APPLE`) : l'activer quand cette version sera publiée.

## Nouveautés (Google Play, 500 caractères au plus)

```
• Nouvelle barre de navigation, plus légère et translucide.
• Textes plus grands et plus lisibles, qui suivent la taille choisie sur votre téléphone.
• Fiche de match enrichie : toutes les cotes, la forme récente des deux équipes, le classement à domicile et à l'extérieur.
• Analyse du pronostic plus claire, critères expliqués.
• Verrouillage Face ID et code plus fiable.
• Corrections et améliorations.
```

## What's new (English)

```
• New navigation bar, lighter and translucent.
• Larger, more readable text that follows your phone's text size.
• Richer match page: all odds, both teams' recent form, home and away standings.
• Clearer prediction analysis with explained criteria.
• More reliable Face ID and passcode lock.
• Fixes and improvements.
```
