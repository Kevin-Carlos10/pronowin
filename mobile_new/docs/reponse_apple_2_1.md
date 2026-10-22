# Réponse à Apple — Guideline 2.1, Information Needed (2 octobre 2026)

Apple demande, pour un compte développeur nouveau : une vidéo de l'app sur un
vrai iPhone, et six réponses écrites. Le texte ci-dessous sert **deux fois** :
en réponse au message d'Apple, et dans le champ « Remarques » des
informations de vérification (il remplace l'ancien texte, qu'il reprend).
Il tient sous la limite de 4 000 caractères du champ « Remarques ».

## Texte à envoyer (en anglais)

```
PronoWin – information for App Review

1. Screen recording
Attached, recorded on an iPhone running the latest iOS. It starts at app launch and shows sign-up, the main features, the Premium purchase and the unlocked content, comment reporting and blocking, logout and login, and account deletion.

2. Purpose and audience
PronoWin is a football (soccer) analysis app for adult fans (18+), mainly French-speaking (interface in French and English). Match information is usually scattered across many sources; PronoWin gathers it in one place: the analyst's daily predictions with a confidence index (an opinion, not a probability of winning), lineups, injuries, head-to-head, standings, form, live scores and indicative odds. A personal bankroll logbook helps users keep a budget and review their results calmly.
PronoWin is an information service only: no real-money gaming, no wagering, no deposits or withdrawals, no prizes, and no links to or promotions for betting operators in this version.

3. How to use the app
- Sign in: tap "Continue with email", enter the demo email, then the 6-digit code given as the password (no inbox access needed). Sign in with Apple and Google are also available.
- Home: today's featured prediction. Pronos tab: all predictions; tap one for the full match analysis.
- Bankroll tab: set a budget and log a bet.
- Comments (Premium members): members can comment on a prediction; the "⋯" menu on a comment lets users report it or block its author, and blocked members are listed in Settings > Blocked members. Comments are filtered when posted and reports are reviewed within 24 hours.
- Premium: auto-renewable subscriptions via In-App Purchase (com.pronowin.premium.monthly, com.pronowin.premium.annual). Tap any locked Premium prediction, or Account > "Upgrade to Premium". Restore Purchases is on the same screen. Premium unlocks analysis content only, never betting credit.
- Account deletion: Account > Settings (gear icon) > Delete account.

4. External services
- API-Football (api-sports.io): fixtures, live scores, lineups, statistics, standings and odds data.
- Authentication: our own email one-time code (sent through Gmail SMTP), Sign in with Apple, Google Sign-In.
- Payments: Apple In-App Purchase only.
- Google Firebase: push notifications (via APNs), crash reports, performance, usage analytics, remote configuration.
- OVHcloud (Canada): server hosting.
- No AI services: statistical estimates are computed from odds and team-form data.

5. Regions
The app works the same in all regions. Only the interface language (French or English, following the device) and the local subscription price set by the App Store differ.

6. Regulated industry
PronoWin does not operate in a regulated industry: it does not offer, facilitate or advertise gambling, and no money is staked, held or transferred in the app. It publishes editorial sports analysis. As a precaution, the app is rated 18+, asks for the date of birth at sign-up, and includes a Responsible Gambling page with help resources. Football data, team names and crests are provided through our API-Football account, under its terms.

Contact: pronowin2026@gmail.com
```

## La vidéo (sur l'iPhone, en français)

Préparer :

- iPhone à jour : Réglages > Général > Mise à jour logicielle (Apple exige la
  dernière version d'iOS).
- Le build 25 installé depuis TestFlight. Les achats y sont des achats de
  test : rien n'est débité.
- Réglages > Centre de contrôle : ajouter « Enregistrement de l'écran ».
- Une adresse e-mail à laquelle tu as accès, **qui n'est ni le compte de
  démonstration ni ton compte personnel** : c'est ce compte qu'on supprimera
  à la fin de la vidéo.
- L'app déconnectée, fermée.

Enregistrer, d'une traite (3 à 6 minutes) :

1. Lancer l'enregistrement depuis l'écran d'accueil de l'iPhone, puis toucher
   l'icône PronoWin : la vidéo doit commencer au lancement.
2. **Inscription** : « Continuer avec l'e-mail », la nouvelle adresse, le
   code reçu, puis le profil (date de naissance comprise).
3. **Tour de l'app** : Accueil, onglet Pronos, ouvrir un pronostic (analyse,
   indice de confiance, onglets du match), Bankroll (fixer un budget, noter un
   pari), Tutoriels.
4. **Commentaires** : sur un pronostic, écrire un commentaire. Sur le
   commentaire d'un autre membre, menu « ⋯ » > Signaler, puis « ⋯ » >
   Bloquer. S'il n'y a aucun commentaire d'un autre membre, en écrire un
   avant, depuis un autre compte.
5. **Contenu payant** : toucher un pronostic Premium verrouillé > écran
   Premium > choisir une formule > fenêtre d'achat Apple > confirmer >
   montrer le pronostic débloqué. Montrer aussi « Restaurer mes achats ».
6. **Connexion** : se déconnecter, puis se reconnecter (avec l'e-mail, ou
   « Se connecter avec Apple »).
7. **Suppression du compte** : Compte > Paramètres (roue dentée) > Supprimer
   le compte > confirmer. Montrer le retour à l'écran de connexion.
8. Arrêter l'enregistrement.

## Où mettre quoi dans App Store Connect

1. Distribution > page 1.0.16 > « Informations utiles à la vérification » :
   remplacer le texte de « Remarques » par le texte anglais ci-dessus, joindre
   la vidéo dans « Pièce jointe », puis Enregistrer.
2. Vérification de l'app > la soumission > Messages : répondre à Apple avec le
   même texte, et joindre la vidéo.
3. Cliquer sur « Soumettre à nouveau à l'équipe de vérification des apps ».
