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
The demo account in App Review Information is now fully set up. In addition, build 1.0.33 no longer asks for a name, date of birth or phone number before the subscription screen: "Get Premium" opens it directly for every account. No SMS or inbox is needed.
1. Open the app and tap "Continue with email".
2. Enter the email given in the User Name field.
3. Enter the 6-digit code given in the Password field.
The account is on the free plan so that you can test the subscriptions (com.pronowin.premium.monthly, com.pronowin.premium.annual) with your sandbox account: tap "Get Premium" on the home screen, or any locked Premium prediction. Once purchased, every Premium prediction and analysis is unlocked.

Best regards,
PronoWin
```

## Variante retenue le 5 novembre 2026 : « Non » maintenu, société en création

Choix du titulaire du compte : soumettre la 1.0.33 sans changer « Jeux de
hasard », et créer la société dans les jours qui viennent pour passer en
compte Organisation. Un nouveau refus sur la règle 2.3.6 est probable ; la
réponse le dit franchement, pour que les deux autres corrections soient
examinées.

```
Hello,

Thank you for your review. Build 1.0.33 (49) addresses guidelines 5.6.3 and 2.1.

Guideline 5.6.3
The previous build asked for a rating at app launch, from the third launch. Build 1.0.33 never asks at launch or during onboarding. The system rating prompt can only appear while the user is reading a match analysis, after at least five launches over seven days and three analyses read, and at most once every 30 days. The "Rate the app" item in Settings opens the App Store page only when the user taps it.

Guideline 2.1
The demo account in App Review Information is now fully set up. In addition, build 1.0.33 no longer asks for a name, date of birth or phone number before the subscription screen: "Get Premium" opens it directly for every account. No SMS or inbox is needed.
1. Open the app and tap "Continue with email".
2. Enter the email given in the User Name field.
3. Enter the 6-digit code given in the Password field.
The account is on the free plan so that you can test the subscriptions (com.pronowin.premium.monthly, com.pronowin.premium.annual) with your sandbox account: tap "Get Premium" on the home screen, or any locked Premium prediction. Once purchased, every Premium prediction and analysis is unlocked.

Guideline 2.3.6
We understand that predictions related to real-money betting require "Gambling" to be set to "Yes". On October 11, App Review told us that an app with this setting must be distributed by an organization, not an individual developer account. We are registering a company and will move the app to an Organization account; we will then set "Gambling" to "Yes". In the meantime, we would appreciate your review of the two changes above, and your confirmation of the steps required for this content.

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
