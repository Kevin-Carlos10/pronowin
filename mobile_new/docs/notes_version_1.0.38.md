# Version 1.0.38 (54) — Mobile Money dans Google Play, nouvel écran de connexion

Préparée le 23 novembre 2026, après la 1.0.37 (53).

## Google Play : le paiement Mobile Money dans l'application

Décision expresse de l'utilisateur, le 23 novembre 2026, risque accepté.

- **Le constat** : aucun compte marchand Google n'est possible depuis le
  Burkina Faso, donc la Play Console n'a rien à vendre. Depuis la 1.0.32, la
  version Play renvoyait vers la page de paiement du site.
- **Désormais**, elle propose le paiement Premium comme l'APK : GeniusPay
  (Mobile Money, activation immédiate), ou un transfert avec envoi de la
  preuve. Les prix affichés sont ceux du Mobile Money.
- **Ce qui ne change pas** : le parcours « code promo » (compte partenaire
  1xBet) reste réservé à l'APK. L'iPhone garde l'achat intégré d'Apple, seul.
- **Profil complet demandé avant de payer**, comme sur l'APK : le serveur
  l'exige pour GeniusPay et pour les preuves.
- **Risque** : Google exige sa propre facturation pour un abonnement. Il peut
  refuser la mise à jour, retirer l'application, voire suspendre le compte
  développeur après des violations répétées.
- **Textes légaux** : CGU et confidentialité, dans l'app et sur le site,
  décrivent désormais trois versions (iPhone, Google Play, APK). Révision
  datée du 23 novembre 2026.

## Renouveler en un geste

- Les rappels d'échéance (J-7, J-3, J-1) et les relances après expiration
  mènent droit à l'étape de paiement de la formule de l'abonné (mensuelle ou
  annuelle) : il ne reste qu'à toucher « Payer ». Le bouton « Renouveler »
  du Compte fait de même. Lien `/compte/activer-premium?renouveler=…` (les
  versions précédentes ouvrent l'offre, comme avant).
- Plus de rappel « renouvelle » pour un abonnement App Store ou Google Play,
  que la boutique renouvelle elle-même (côté serveur).

## Écran de connexion refait

- **Bandeau** : un grand bandeau orange, avec le nom, une accroche et une
  petite scène (l'icône, « EN DIRECT », un score, une alerte, le classement).
  Il se replie quand le clavier s'ouvre.
- **Boutons** : chemins de connexion en pilules, « ou » avant l'e-mail,
  « Sans mot de passe », « Besoin d'aide ? » (e-mail au support).
- **Code reçu par e-mail** : « Modifier l'adresse », compte à rebours en
  minutes, conseil si rien n'arrive (spams).
- **Largeur** : limitée sur iPad.
- **Correction** : quitter l'écran du code levait une erreur (champ libéré
  deux fois).

## À faire à la publication

- **Serveur et site** : déployer, pour les CGU et la confidentialité du
  23 novembre.
- **Google Play** : importer l'AAB 1.0.38. Dans la Play Console, mettre à
  jour la **sécurité des données** : nom, e-mail, téléphone et historique
  d'achat, collectés pour le paiement et transmis à GeniusPay. Pas de
  déclaration « achats via Google Play ».
- **APK direct** : publier la 1.0.38 (nouvel écran de connexion).
- **App Store** : rien de nouveau pour le paiement. Le build iOS de cette
  révision a le nouvel écran de connexion.
