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
  bankroll, sans tutoriel de pari, sans section « Jeu responsable ». À
  déployer sur le site avant l'examen.

Seul un build compilé depuis le commit qui ajoute ces trois derniers points
(ou plus récent) peut être soumis.

Android (Google Play et APK direct) ne change pas.

## À faire dans App Store Connect (par toi)

1. **Version** : renommer la version en attente (1.0.16) en **1.0.23**, puis
   choisir le build 1.0.23 envoyé par Codemagic.
2. **Classification par âge** : Jeux de hasard (Gambling) **Non** ; Jeux de
   hasard simulés **Aucun** ; le reste inchangé.
3. **Captures d'écran** : les refaire depuis la 1.0.23 — aucune ne doit
   montrer la Bankroll, une cote ou le bouton de sélection.
4. **Fiche** : remplacer sous-titre, texte promotionnel, description et
   mots-clés par les textes ci-dessous (FR et EN). Vérifier aussi les noms et
   descriptions des abonnements : ni « cotes » ni « bankroll ».
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

PronoWin est un service d'information sportive. L'application ne propose aucun pari, ne contient aucun lien vers des opérateurs de paris et ne manipule aucun argent en dehors de l'abonnement.
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

PronoWin is a sports information service. The app offers no betting, contains no links to betting operators and handles no money other than the subscription.
```

### Mots-clés (100 caractères)

- FR : `pronostic,pronos,foot,football,analyse,statistiques,match,score,ligue,classement,forme,direct`
- EN : `football,soccer,predictions,analysis,stats,match,league,score,standings,live,form,lineups`

### Notes pour l'examen (EN)

```
PronoWin is a football (soccer) predictions and statistics app. Following your message of October 11, build 1.0.23 removes every feature that could be considered simulated gambling: there is no bankroll or stake tracking, no button to record a bet, no betting odds anywhere, and no betting-strategy tutorials.

The app shows our analysts' match predictions with a confidence index, team form, standings, head-to-head records, lineups, injuries and live match statistics. No bets can be placed, there are no links to betting operators, and no money is handled other than the In-App Purchase subscription, which unlocks analysis content only.

Demo account: same as in the previous submission.
```

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
