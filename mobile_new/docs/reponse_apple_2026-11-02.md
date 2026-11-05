# Réponse au refus Apple du 2 novembre 2026 (1.0.23 (50))

À envoyer depuis App Store Connect (« Répondre à l'équipe de vérification des
apps ») **avec le build iOS 1.0.33 (49)**, une fois le compte de
démonstration préparé (`backend/docs/APP_STORE_REVIEW.md`) et la
classification d'âge réglée. Rien n'est envoyé sans l'accord du titulaire du
compte.

## Le dilemme « Jeux de hasard »

- 7 octobre : le relecteur exige « Jeux de hasard : Oui ».
- 11 octobre : refus — avec ce réglage, une app ne peut venir que d'un compte
  **Organisation** (entité immatriculée, numéro D-U-N-S), pas d'un compte
  individuel.
- 2 novembre : le relecteur exige de nouveau « Oui », car l'app publie des
  pronostics, même sans cotes, ni mise, ni bankroll.

Choisir la variante A ou B avant d'envoyer.

## Réponse (EN) — variante A : « Jeux de hasard : Oui », compte individuel

```
Hello,

Thank you for your review. Build 1.0.33 (49) addresses each point.

Guideline 5.6.3
The previous build asked for a rating at app launch, from the third launch. Build 1.0.33 never asks at launch or during onboarding. The system rating prompt can only appear while the user is reading a match analysis, after at least five launches over seven days and three analyses read, and at most once every 30 days. The "Rate the app" item in Settings opens the App Store page only when the user taps it.

Guideline 2.3.6
We have updated the Age Rating: Gambling is now set to "Yes" (18+).
On October 11, App Review told us that an app with this setting cannot be distributed from an individual developer account. PronoWin publishes football analysis and predictions only: no wagering, no odds, no stakes, no deposits or withdrawals, no prizes and no links to betting operators. If an Organization account is required for this content, please tell us explicitly so that we can take the right steps.

Guideline 2.1
The demo account in App Review Information is now fully set up: complete profile and active Premium access, so every prediction and analysis is unlocked. No SMS or inbox is needed.
1. Open the app and tap "Continue with email".
2. Enter the email given in the User Name field.
3. Enter the 6-digit code given in the Password field.

Best regards,
PronoWin
```

## Variante B : compte Organisation d'abord

Ne pas resoumettre. Créer la structure juridique, obtenir le numéro D-U-N-S,
faire passer le compte développeur en Organisation (demande à Apple : l'app
et son historique sont conservés), puis régler « Jeux de hasard : Oui » et
envoyer la réponse A sans le paragraphe sur le 11 octobre.

Le message d'Apple propose aussi un rendez-vous « App Review Appointment »
(Meet with Apple, mardi et jeudi) pour en parler de vive voix avant de
choisir.
