# Version 1.0.24 (40) — fiche de match au style Sofascore

Préparée le 18 octobre 2026. Android d'abord (APK direct et Google Play) ;
l'iPhone attend l'approbation de la 1.0.23 par Apple.

## Ce qui change dans l'app

- **Fiche de match** : plus de compteur d'actualisation ni de roue sous le
  score ; un discret « score non actualisé » seulement si le direct ne répond
  plus depuis 90 s (6686421).
- **Chrono à la seconde**, comme Sofascore, avec le temps additionnel ; le
  début des mi-temps est estimé quand le fournisseur ne le date pas
  (89de5e5, 2d9f86c).
- **Fil des événements** : buts avec le score du moment, cartons et leur
  motif, remplacements, VAR, séparateurs de mi-temps (868584f, bb9c8e5).
- **Compositions** : notes des joueurs sur le terrain, buts, cartons,
  capitaine, remplaçants entrés en jeu, moyenne de l'équipe (9c9a02f).
- **Statistiques par mi-temps** (Tout / 1re MT / 2e MT) quand le fournisseur
  les donne de façon cohérente (6f9409a, 89ba735).
- **Toute fiche de match est consultable**, même sans pronostic (89ba735).
- **Historique** : un pronostic Premium reste verrouillé pour un compte
  gratuit, après le match aussi (af8a2ea).
- **Compte à rebours** de l'accueil : l'effet d'iOS quand les chiffres
  changent (2fdbc70).
- **Plus de cadenas au lancement** quand aucun verrou n'est activé (9555e40).
- **Google Play** : l'abonnement n'y est pas encore en vente (pas de compte
  marchand Google depuis le Burkina Faso). L'écran Premium le dit
  sobrement — « L'abonnement Premium n'est pas encore proposé dans la version
  Google Play. » — sans prix, ni « réessayer », ni autre moyen de paiement,
  que Google interdit d'indiquer (fd4dec0). L'APK direct n'est pas concerné.
- **Paramètres** : l'interrupteur « Alertes matchs » s'intitule désormais
  « Pronostics, buts et résultats ».

## Côté serveur (déjà valable pour toutes les versions installées)

- **Alertes de but** pour les matchs suivis (favori, ou pari en cours sur le
  pronostic dans la bankroll) : « But pour Arsenal ! — Arsenal 1-0 Chelsea ·
  B. Saka 23' », « But annulé pour X », « Score mis à jour ». Le buteur n'est
  nommé que si les événements du direct correspondent au score. Aucune salve
  au redémarrage du serveur ; un coup d'envoi n'est plus annoncé deux fois.
- Le lien des alertes « coup d'envoi » et « fin de match » ouvre aussi un
  match sans pronostic (il était vide).
- Synchronisation des scores économe en quota : le direct en un appel, 15 s
  pour un match suivi, 60 s sinon (71953ff, ffbbb88, 2a73725).

## Construction

```
.\tool\build.ps1 -Canal direct -ApiUrl https://pronowin.space/api/v1   # APK direct (GeniusPay)
.\tool\build.ps1 -Canal play   -ApiUrl https://pronowin.space/api/v1   # AAB Google Play (achat intégré seul)
```
