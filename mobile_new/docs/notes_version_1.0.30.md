# Version 1.0.30 (46) — le Premium n'est plus oublié

Préparée le 24 octobre 2026, à la suite de la 1.0.29 (voir
`notes_version_1.0.29.md`). Côté serveur : « Bienvenue Premium ! » et
« Premium activé ! » partent avec le type `premium` (à déployer).

## Ce qui change dans l'app

- **Le statut Premium n'est plus oublié.** Signalé le 24 octobre :
  « l'application oublie souvent que tel compte connecté est Premium et
  affiche la carte Premium ». Deux causes :
  - le profil n'était lu qu'au démarrage, une seule fois. Réseau lent ou
    coupé à ce moment-là, le compte restait inconnu jusqu'au lancement
    suivant : l'app le croyait gratuit, et proposait Premium à un abonné ;
  - un Premium accordé pendant la session (preuve validée, paiement Mobile
    Money, geste de l'équipe) n'apparaissait qu'au redémarrage.
- Désormais :
  - le dernier profil connu est gardé sur l'appareil, dans le stockage
    sécurisé, avec les jetons. Au démarrage, il s'affiche tout de suite,
    Premium compris, même sans réseau, puis la réponse du serveur
    l'emporte. La déconnexion l'efface ;
  - le profil est relu au retour dans l'application (une fois par minute au
    plus), au retour du réseau, et à la réception d'une notification
    Premium (« Bienvenue Premium ! », « Premium activé ! », « Ton Premium
    expire… ») ;
  - une erreur de réseau ne retire jamais le Premium affiché ; seule une
    session refusée par le serveur ramène à l'état invité.

## Construction

```
.\tool\build.ps1 -Canal direct -ApiUrl https://pronowin.space/api/v1   # APK direct (GeniusPay)
.\tool\build.ps1 -Canal play   -ApiUrl https://pronowin.space/api/v1   # AAB Google Play (achat intégré seul)
```
