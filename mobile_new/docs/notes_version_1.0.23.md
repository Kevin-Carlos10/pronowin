# Version 1.0.23 — iPhone sans pari

Préparée le 12 octobre 2026 en réponse au refus de la 1.0.16 (examen du
11 octobre) : Apple n'accepte plus d'un compte de développeur **individuel**
une application qui contient du jeu d'argent, même simulé, ou qui est déclarée
« Jeux de hasard : Oui ».

## Ce qui change sur iPhone (et seulement sur iPhone)

Un interrupteur unique, `sansPariProvider` (`lib/core/config/sans_pari.dart`),
actif sur iOS :

- plus d'onglet **Bankroll** ; un lien vers la bankroll ouvre l'accueil ;
- plus de bouton **« Valider ma sélection »** (fiche de match, cartes de
  l'accueil) ni d'encart « Ma bankroll » ;
- plus aucune **cote** : onglet Cotes, cotes en direct, cote du pronostic,
  1/N/2 des cartes, filtre par cote, historique, image de partage ;
- plus de **tutoriels de stratégie de pari** (value bet, bankroll,
  martingale, trading) ;
- textes ajustés : bandeau Premium, page d'abonnement, présentation du
  premier lancement ;
- **Performance** : plus aucun montant (mise simulée, gain, rentabilité,
  courbe de solde, gain par ligue) — restent les résultats ;
- **Paramètres** : plus d'entrée « Jeu responsable » (icône de jeton de
  casino) ;
- **conditions d'utilisation** : version iPhone (`/cgu?canal=ios`) sans
  bankroll, sans tutoriel de pari, sans section « Jeu responsable » (en ligne
  depuis le 12 octobre, ce0bab0) ;
- **politique de confidentialité** (dans l'app et sur le site) : les données
  de bankroll y sont marquées « application Android uniquement ».

Seul un build compilé depuis b154f44 ou plus récent peut être soumis (build
50, attaché le 14 octobre 2026) : le build 49 (2c0a1dd) affichait encore, dans
l'analyse statistique, « fondé sur les cotes » et « La cote de 1.34
correspond à une probabilité implicite de 75 % (marge du bookmaker incluse) ».
Le correctif passe aussi par le serveur (`?sans_cotes=1`), déployé en b154f44
le 13 octobre. Ni celui de 7bb1bc4, ni celui de ce0bab0 non plus. Le paiement GeniusPay ajouté ensuite
(4cbe5e5 et suivants) n'apparaît pas sur iPhone : la version store garde
l'achat intégré seul.

Android 1.0.23 (39) : les retraits ci-dessus ne concernent que l'iPhone.
L'APK direct apporte le paiement Mobile Money automatique par GeniusPay
(4cbe5e5, e681288 : Premium activé sans preuve à envoyer) et la
confidentialité du 13 octobre 2026. Compilé depuis 2ec93d6 avec
`tool/build.ps1` ; APK direct publiés dans `/downloads` le 14 octobre 2026
(anciens fichiers gardés en `*-1.0.22-sauvegarde-20261014-130842*`),
`APK_LATEST_VERSION=1.0.23` (mise à jour non obligatoire). AAB Google Play
`build/app/outputs/bundle/playRelease/app-play-release.aab` compilé, à envoyer
dans la Play Console (sans GeniusPay : achat intégré seul).

## À faire dans App Store Connect (par toi)

1. **Version** : renommer la version en attente (1.0.16) en **1.0.23**, puis
   choisir le build 1.0.23 envoyé par Codemagic.
2. **Classification par âge** : Jeux de hasard (Gambling) **Non** ; Jeux de
   hasard simulés **Aucun** ; le reste inchangé. Si la tranche calculée
   descend sous 18+, garder **18+** (remplacement par une tranche plus
   élevée) : les conditions d'utilisation réservent l'app aux majeurs.
3. **Captures d'écran** : les refaire depuis la 1.0.23 installée par
   TestFlight — aucune ne doit montrer la Bankroll, une cote ou le bouton de
   sélection. Dans l'ordre :
   1. l'accueil avec les pronostics du jour ;
   2. la fiche d'un match (choix de l'analyste, confiance, forme) ;
   3. l'avis du modèle statistique ;
   4. les classements ;
   5. l'historique des résultats ;
   6. la page Premium, avec ses prix.

   Celles d'un iPhone 16 Pro (1206 × 2622) sont à convertir en 1290 × 2796
   avant l'envoi. Sans captures anglaises, Apple reprend les françaises.
4. **Fiche** : remplacer sous-titre, texte promotionnel, description et
   mots-clés par les textes ci-dessous (FR et EN). Vérifier aussi les noms et
   descriptions des abonnements : ni « cotes » ni « bankroll ». Si un contrat
   de licence (CLUF) personnalisé est renseigné dans les informations de
   l'app, son lien doit pointer vers `https://pronowin.space/cgu?canal=ios`.
   **URL marketing et URL d'assistance** : plus l'accueil du site, qui mène
   depuis le 13 octobre 2026 à la page de paiement Mobile Money
   (`/premium`) — Apple interdit qu'une app ou ses métadonnées renvoient
   vers un achat hors boutique. URL d'assistance :
   `https://pronowin.space/mentions-legales` ; URL marketing : vide.
5. **Notes pour l'examen** : remplacer par le texte ci-dessous.
6. **Répondre** au message d'Apple (texte ci-dessous), puis **Soumettre à
   nouveau**.

Ne rien resoumettre tant que les six points ne sont pas faits : Apple a
signalé un « examen prolongé » en cas de nouvelle soumission sans correction.

### Sous-titre (30 caractères)

- FR : `Pronostics & stats de foot`
- EN : `Football predictions & stats`

### Texte promotionnel

- FR : Les pronostics foot du jour, analysés match par match : forme des
  équipes, classements, face-à-face et statistiques en direct.
- EN : Today's football predictions, analysed match by match: team form,
  standings, head-to-head and live statistics.

### Description — FR

```
PronoWin t'aide à comprendre le football par les chiffres : des pronostics analysés match par match, des statistiques claires et une fiche complète pour chaque rencontre.

PRONOSTICS
• Chaque jour, les pronostics de nos analystes sur les grands championnats européens et la Ligue des champions
• Pour chaque match : le choix de l'analyste et son indice de confiance (son appréciation, pas une garantie)
• Un historique complet des résultats

FICHE DE MATCH
• Forme récente des deux équipes, classements général, à domicile et à l'extérieur
• Face-à-face, compositions, blessures, statistiques et événements en direct
• L'avis d'un modèle statistique, critère par critère

APPRENDRE
• Des tutoriels vidéo pour lire un match et comprendre les statistiques

PREMIUM
• Pronostics VIP, analyses détaillées et espace communauté, par abonnement mensuel ou annuel

ABONNEMENT
PronoWin Premium est un abonnement à renouvellement automatique, mensuel ou annuel. Le paiement est débité sur ton compte Apple à la confirmation de l'achat. L'abonnement se renouvelle automatiquement, sauf résiliation au moins 24 heures avant la fin de la période en cours, depuis les réglages de ton compte App Store.

PronoWin est un service d'information sportive. L'application ne propose aucun pari, ne contient aucun lien vers des opérateurs de paris et ne manipule aucun argent en dehors de l'abonnement.

Conditions d'utilisation : https://pronowin.space/cgu?canal=ios&app=1
Confidentialité : https://pronowin.space/confidentialite?app=1
```

### Description — EN

```
PronoWin helps you understand football through numbers: predictions analysed match by match, clear statistics and a complete page for every fixture.

PREDICTIONS
• Every day, our analysts' predictions for the major European leagues and the Champions League
• For every match: the analyst's pick and confidence index (their own judgement, not a guarantee)
• A complete history of results

MATCH PAGE
• Both teams' recent form, overall, home and away standings
• Head-to-head, lineups, injuries, live statistics and events
• A statistical model's view, criterion by criterion

LEARN
• Video tutorials to read a match and understand the statistics

PREMIUM
• VIP predictions, detailed analysis and a community space, with a monthly or annual subscription

SUBSCRIPTION
PronoWin Premium is an auto-renewable subscription, monthly or annual. Payment is charged to your Apple Account when you confirm the purchase. The subscription renews automatically unless cancelled at least 24 hours before the end of the current period, in your App Store account settings.

PronoWin is a sports information service. The app offers no betting, contains no links to betting operators and handles no money other than the subscription.

Terms of use: https://pronowin.space/cgu?canal=ios&app=1
Privacy: https://pronowin.space/confidentialite?app=1
```

### Mots-clés (100 caractères)

- FR : `pronostic,pronos,foot,football,analyse,statistiques,match,score,ligue,classement,forme,direct`
- EN : `football,soccer,predictions,analysis,stats,match,league,score,standings,live,form,lineups`

### Notes pour l'examen (EN)

```
PronoWin – information for App Review (version 1.0.23)

1. What changed since the rejection of October 11
Build 1.0.23 removes every feature that could be considered simulated gambling: there is no bankroll or stake tracking, no button to record a bet, no betting odds anywhere in the app, and no betting-strategy tutorials. The screen recording attached to the previous submission showed those features; it has been removed.

2. Purpose and audience
PronoWin is a football (soccer) analysis app for adult fans (18+), mainly French-speaking (interface in French and English). It gathers match information in one place: the analyst's daily predictions with a confidence index (an opinion, not a probability of winning), lineups, injuries, head-to-head records, standings, team form and live scores.
PronoWin is an information service only: no real-money gaming, no wagering, no odds, no deposits or withdrawals, no prizes, and no links to or promotions for betting operators.

3. How to use the app
- Sign in: tap "Continue with email", enter the demo email, then the 6-digit code given as the password (no inbox access needed). Sign in with Apple and Google are also available.
- Home: today's featured prediction. Pronos tab: all predictions; tap one for the full match analysis.
- Comments (Premium members): members can comment on a prediction; the "⋯" menu on a comment lets users report it or block its author, and blocked members are listed in Settings > Blocked members. Comments are filtered when posted and reports are reviewed within 24 hours.
- Premium: auto-renewable subscriptions via In-App Purchase (com.pronowin.premium.monthly, com.pronowin.premium.annual). Tap any locked Premium prediction, or Account > "Upgrade to Premium" ("Passer à Premium" in French). Restore Purchases is on the same screen. Premium unlocks analysis content only.
- Account deletion: Account > Settings (gear icon) > Delete account.

4. External services
- API-Football (api-sports.io): fixtures, live scores, lineups, statistics and standings.
- Authentication: our own email one-time code, Sign in with Apple, Google Sign-In.
- Payments in this app: Apple In-App Purchase only.
- Google Firebase: push notifications (via APNs), crash reports, performance, usage analytics, remote configuration.
- OVHcloud (Canada): server hosting.
- No AI services: statistical estimates are computed from football data.

5. Regions
The app works the same in all regions. Only the interface language (French or English, following the device) and the local subscription price set by the App Store differ.

6. Regulated industry
PronoWin does not operate in a regulated industry: it does not offer, facilitate or advertise gambling, and no money is staked, held or transferred in the app. It publishes editorial sports analysis. The app is rated 18+ and asks for the date of birth at sign-up. Football data, team names and crests are provided through our API-Football account, under its terms.

Contact: pronowin2026@gmail.com

Note on the In-App Purchases: the review screenshot and review notes attached to com.pronowin.premium.monthly and com.pronowin.premium.annual were written for an earlier version and still mention bankroll tracking; they could not be updated in their current state. That feature no longer exists in 1.0.23: Premium unlocks VIP predictions, detailed analysis and the community space.
```

Les informations de vérification des deux abonnements (capture « PronoWin
PRO » avec « suivi bankroll », note citant la bankroll) ne sont pas
modifiables dans leur état actuel (13 octobre 2026) : la dernière note
ci-dessus le signale à l'examinateur. À corriger dès qu'App Store Connect le
permet.

Les champs « Nom d'utilisateur » et « Mot de passe » du compte de
démonstration ne changent pas.

**Pièce jointe** : retirer la vidéo `PronoWin_video_Apple.mp4` de la 1.0.16 —
elle montre la Bankroll et les cotes, que la 1.0.23 n'a plus.

### Réponse à Apple (EN)

```
Hello,

Thank you for your review. We have addressed the issue in a new build, PronoWin 1.0.23:

- We removed every feature that could be considered simulated gambling: the bankroll and stake-tracking section, the button to record a selection, all betting odds, and the betting-strategy tutorials.
- PronoWin is now strictly a football information app: match predictions with a confidence index, team form, standings, head-to-head records, lineups and live statistics. No bets can be placed, there are no links to betting operators, and no money is handled other than the In-App Purchase subscription for analysis content.
- We updated the age rating to Gambling: No and Simulated Gambling: None. On October 7, a reviewer asked us to answer Yes because our predictions relate to sports betting; as the app no longer contains any wagering, odds or betting content, we believe No is now accurate. If you still consider that an element of the app falls under gambling, please tell us which one and we will address it.
- We also updated the description, keywords and screenshots to remove any reference to betting, odds or bankroll.

Thank you,
Kevin Zouri
```

## Après l'approbation

L'application iPhone transmet l'identifiant de compte lors d'un achat (depuis
41533c2) : une fois la 1.0.23 en ligne, le refus strict des achats Apple sans
identifiant pourra être activé sur le serveur (`IAP_EXIGER_COMPTE_APPLE=true`).
