# Compte de démonstration des boutiques (App Store et Google Play)

Le relecteur se connecte avec une adresse et un code à six chiffres fixes :
ni SMS, ni boîte e-mail à consulter. Le compte n'a aucun droit
d'administration et n'est jamais un compte personnel.

Apple a refusé la 1.0.23 le 2 novembre 2026 en demandant « a fully set up
demo account » : le compte n'avait ni prénom, ni nom, ni date de naissance,
ni téléphone, et l'app ouvre « Compléter le profil » avant l'écran Premium.
Le script de préparation remplit désormais ce profil. Les captures jointes
par Apple montrent un compte gratuit nommé « Parieur_… » (créé par
l'inscription normale, jamais passé par le script) bloqué sur « Complete my
profile » après « Get Premium ».

## Préparer le compte

1. Sur le serveur, dans `backend/.env` : `STORE_REVIEW_ENABLED=true`,
   `STORE_REVIEW_EMAIL` et `STORE_REVIEW_OTP` (six chiffres). Les anciennes
   variables `GOOGLE_PLAY_REVIEW_*` restent lues si les nouvelles manquent.
2. Lancer `npm run review:provision` : compte actif, profil complet,
   Premium pendant deux ans. Pour l'examen Apple,
   `npm run review:provision -- --gratuit` : même compte, sans Premium, pour
   que le relecteur puisse tester l'abonnement. Le script n'affiche jamais le
   code.
3. Pendant l'examen Apple, le serveur doit accepter les achats sandbox
   (`IAP_ACCEPT_SANDBOX=true`) : le relecteur paie avec un compte de test
   Apple, et un reçu sandbox refusé fait échouer l'achat (refus 2.1). Une
   app téléchargée sur l'App Store achète toujours en production : seuls les
   builds TestFlight et l'examen passent par le sandbox, et un abonnement
   sandbox expire en quelques minutes.
4. Vérifier depuis un appareil sans session : l'adresse et le code
   connectent sans e-mail ni SMS, l'écran Premium s'ouvre sans « Compléter
   le profil », les pronostics VIP sont lisibles (sans `--gratuit`).
5. App Store Connect, **Informations de vérification de l'app > Connexion
   requise** : l'adresse dans « Nom d'utilisateur », le code dans « Mot de
   passe ». Ne pas toucher au compte pendant l'examen.

## Points de conformité

- Aucune demande de note au lancement ni pendant l'accueil (règle 5.6.3) :
  `ReviewService` ne la propose que pendant la lecture d'une fiche de match,
  après cinq ouvertures sur sept jours et trois fiches lues.
- La classification d'âge doit décrire le contenu réellement accessible : un
  pronostic sur un match est, pour Apple, une information liée aux paris en
  argent réel (« Jeux de hasard : Oui » exigé le 7 octobre et le 2 novembre
  2026). Le 11 octobre, Apple a jugé ce réglage incompatible avec un compte
  développeur individuel.
