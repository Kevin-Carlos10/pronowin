# Guide de configuration Google Play Console - PronoWin

Ce guide indique quoi choisir ou renseigner dans Google Play Console pour la
version Play Store de PronoWin.

La version Play est une application d'information et d'analyse sportive :
elle ne doit contenir ni bookmaker, ni lien d'affiliation, ni Mobile Money,
ni depot, ni retrait, ni paiement externe.

Derniere verification : 5 septembre 2026.

## Etat actuel

Ces declarations sont deja remplies et enregistrees dans la console :

- Regles de confidentialite
- Informations de connexion par OTP e-mail
- Annonces : aucune
- Classification du contenu
- Cible : 18 ans et plus
- Securite des donnees
- Applications gouvernementales : non
- Fonctionnalites financieres : aucune case cochee (voir la section dediee —
  cocher « recompenses et fidelite » a fait refuser l'application)
- Sante : aucune fonctionnalite de sante
- Identifiant publicitaire : non

Il reste a terminer :

1. La categorie et les coordonnees.
2. La fiche Play Store principale et ses visuels.
3. Le test ferme avant toute demande de production.

## 1. Categorie et coordonnees

Chemin : `Accroitre le nombre d'utilisateurs > Presence sur le Play Store >
Parametres de la fiche Play Store`.

### Categorie

| Champ | Valeur |
| --- | --- |
| Application ou jeu | `Appli` |
| Categorie | `Sports` |
| Tags | Facultatif. Ajouter uniquement des tags exacts proposes par Google, par exemple `Football` ou `Sports`. |

### Coordonnees visibles sur Google Play

| Champ | Valeur |
| --- | --- |
| Adresse e-mail | `pronowin2026@gmail.com` |
| Site Web | `https://pronowin.space` |
| Numero de telephone | Laisser vide sauf si un numero de support officiel doit etre affiche publiquement et est releve regulierement. |

Le marketing externe peut rester actif seulement si la promotion de PronoWin
hors du Play Store est souhaitee. Ce choix n'a pas d'incidence sur la
conformite.

## 2. Fiche Play Store principale

Chemin : `Accroitre le nombre d'utilisateurs > Presence sur le Play Store >
Fiches Play Store > Fiche Play Store principale`.

### Informations a remplir

| Champ | Texte a utiliser |
| --- | --- |
| Langue | `Francais (France) - fr-FR` |
| Nom | `PronoWin` |
| Description courte | `Analyses, statistiques et pronostics de football pour suivre vos matchs.` |

La description courte est sous la limite de 80 caracteres et ne promet pas
de gain.

### Description complete a coller

```text
PronoWin est une application d'information et d'analyse consacree au football.

Suivez les matchs, consultez des statistiques et decouvrez des pronostics etablis a partir des informations sportives disponibles. L'application aide les passionnes de football a mieux suivre les competitions et a organiser leurs analyses personnelles.

Avec PronoWin, vous pouvez :
- consulter les matchs et les informations associees ;
- suivre des statistiques et des analyses sportives ;
- enregistrer et retrouver vos pronostics ;
- lire des actualites et des tutoriels ;
- recevoir des notifications utiles ;
- personnaliser votre profil et vos preferences ;
- acceder a des fonctionnalites Premium via les achats integres Google Play.

PronoWin est reserve aux personnes de 18 ans et plus. Les informations et pronostics proposes sont fournis a titre informatif et educatif. PronoWin n'est pas un operateur de jeux d'argent : l'application ne permet ni de placer un pari, ni de faire un depot, ni d'effectuer un retrait d'argent reel.

Vos donnees et votre compte peuvent etre geres depuis l'application. Retrouvez nos regles de confidentialite sur https://pronowin.space/confidentialite.
```

Ne pas ajouter a la fiche :

- de promesse de resultat, de gain ou de rentabilite ;
- de nom, lien, code ou promotion de bookmaker ;
- de prix promotionnel, de classement ou de formule comme « numero 1 » ;
- de fonctionnalite absente du build envoye a Google.

## 3. Visuels a preparer

Les visuels doivent montrer la vraie application Play. Ne pas montrer le
tableau d'administration, un bookmaker, Mobile Money ou un paiement externe.

| Element | Exigence |
| --- | --- |
| Icone Play Store | PNG 32 bits avec transparence, `512 x 512 px`, maximum 1 Mo |
| Banniere promotionnelle | JPEG ou PNG 24 bits sans transparence, `1024 x 500 px` |
| Captures mobile | Minimum 2. Recommande : 4 captures verticales reelles de `1080 x 1920 px` ou plus |

Ordre recommande :

1. Accueil : matchs, analyses ou pronostics.
2. Detail d'un match : statistiques et analyse.
3. Historique ou suivi personnel des pronostics.
4. Tutoriels, actualites ou ecran Premium Google Play.

Texte possible dans la banniere :

```text
Analyses et statistiques football
```

Eviter « gagner », « pari », « jackpot », les prix, les reductions et les
logos de services tiers. Les captures doivent etre nettes et montrer
l'interface reelle.

## 4. Declarations de contenu

Ces reponses correspondent au build Play actuel. Les garder ainsi si Google
demande une nouvelle verification.

### Regles de confidentialite

| Question | Reponse |
| --- | --- |
| URL des regles | `https://pronowin.space/confidentialite` |
| Suppression de compte | `https://pronowin.space/suppression-compte` |

### Informations de connexion

| Question | Reponse |
| --- | --- |
| Certaines fonctions sont-elles limitees par connexion ? | `Oui` |
| Methode de connexion | Adresse e-mail suivie d'un code OTP a usage unique envoye par e-mail |
| Mot de passe | Aucun mot de passe n'est demande |
| Instructions pour Google | Saisir l'e-mail de test deja autorise, recuperer le code OTP, le renseigner, puis acceder aux fonctions Premium de test |

Ne pas retirer les instructions de connexion deja enregistrees. Elles doivent
rester valables le jour de l'examen Google.

### Annonces

| Question | Reponse |
| --- | --- |
| L'application contient-elle des annonces ? | `Non` |

Si AdMob, une regie publicitaire ou une publicite tierce est ajoutee, modifier
cette declaration avant l'envoi d'une nouvelle version.

### Cible et contenu

| Question | Reponse |
| --- | --- |
| Tranche d'age ciblee | `18 ans et plus` |
| L'application est-elle destinee aux mineurs ? | `Non` |

### Classification du contenu

| Sujet | Reponse |
| --- | --- |
| Interactions entre utilisateurs | `Oui`, car les commentaires permettent des interactions |
| Contenu accessible en ligne | `Oui`, pour les matchs, analyses, actualites et tutoriels |
| Achats integres | `Oui`, pour Premium via Google Play |
| Violence, contenu adulte, drogue, jeux d'argent | `Non` pour la version Play |
| Partage de position avec d'autres utilisateurs | `Non` |

### Applications gouvernementales

| Question | Reponse |
| --- | --- |
| L'application est-elle gouvernementale ? | `Non` |

### Fonctionnalites financieres

**Ne cocher AUCUNE case de cette section.** Descendre jusqu'en bas de la page
pour verifier qu'aucune case n'est cochee, puis `Suivant`.

| Question | Reponse |
| --- | --- |
| Recompenses, points, programmes de fidelite et autres avantages | **Ne pas cocher** |
| Acheter maintenant payer plus tard | Ne pas cocher |
| Pret, banque, portefeuille, transfert d'argent, investissement, assurance, crypto | Ne pas cocher |

#### Pourquoi — l'app a ete refusee pour ca le 8 septembre 2026

Une version precedente de ce guide disait de cocher « Programmes de
recompenses, points et fidelite ». C'etait la seule case cochee de la section,
et elle a suffi a faire refuser l'application :

> Violation des exigences de Play Console. Certains types d'applis ne peuvent
> etre distribuees que par des organisations. Vous avez selectionne une
> categorie d'applis ou declare que votre appli offre certaines
> fonctionnalites, ce qui exige que vous soumettiez votre appli par le biais
> d'un compte organisationnel.

Depuis le 31 aout 2024, un compte developpeur personnel ne peut pas publier une
application qui declare fournir des services financiers. Or cette case vit dans
la rubrique **« Contrats d'achat »**, aux cotes de « Acheter maintenant, payer
plus tard » : c'est une famille de credit a la consommation. La cocher declare
que le programme de recompenses est un **produit financier**, pas une promotion
interne.

#### Pourquoi « aucune » est la reponse exacte, et non un contournement

Ce que la version publiee sur Play fait reellement, verifiable dans le code :

- `retrait_parrainage_page.dart` ne rend, sur le canal store, que l'onglet
  « Credit Premium ». Le titre de l'ecran est « Convertir mes recompenses », pas
  « Retirer ». Aucun versement en argent n'existe dans cette version ;
- `recompense_premium.dart` convertit les recompenses en **jours d'abonnement**.
  Il n'y a ni solde retirable, ni valeur transferable, ni conversion en
  monnaie ;
- l'abonnement se vend par Play Billing, ce qui est un achat integre ordinaire
  et non une fonctionnalite financiere ;
- l'application ne permet ni de placer un pari, ni de deposer, ni de retirer.

Une recompense qui ne s'echange que contre du temps d'abonnement dans
l'application est un avoir promotionnel, comme une prolongation d'essai.

**Si le versement en argent est un jour ouvert sur le canal store**, cette
reponse devient fausse : il faudra alors declarer la fonctionnalite ET passer
le compte en organisation. Les deux vont ensemble, et l'un sans l'autre fait
refuser l'application.

### Sante et identifiant publicitaire

| Question | Reponse |
| --- | --- |
| L'application offre-t-elle des fonctionnalites de sante ? | `Non` |
| L'application utilise-t-elle l'identifiant publicitaire Android ? | `Non` |

## 5. Securite des donnees

La declaration est deja remplie. Ne la modifier que si le code change.

| Question | Reponse |
| --- | --- |
| Donnees chiffrees lors du transfert ? | `Oui` |
| Donnees partagees avec des tiers ? | `Non` dans l'etat actuel |
| Suppression de compte | `Oui`, via `https://pronowin.space/suppression-compte` |

### Donnees recueillies declarees

| Categorie | Type | Finalite | Obligatoire ? |
| --- | --- | --- | --- |
| Informations personnelles | Nom, e-mail, ID utilisateur, telephone, autres infos de profil | Fonctionnalite et gestion du compte | E-mail et ID : oui ; le reste selon la saisie |
| Infos financieres | Historique des achats integres | Fonctionnalite et gestion du compte | Optionnel |
| Emplacement | Position approximative | Analytique et fiabilite technique | Oui |
| Photos et videos | Photos de profil | Fonctionnalite | Optionnel |
| Activite dans l'app | Interactions, contenu utilisateur, autres actions | Fonctionnalite et analytique selon le type | Selon le type |
| Infos et performances | Journaux de plantage, diagnostics, autres donnees de performance | Analytique | Oui |
| ID de l'appareil | ID de l'appareil ou autres ID | Fonctionnalite, analytique et communications techniques | Oui |

Firebase sert aux diagnostics et a la performance. Revoir la declaration avant
d'ajouter une regie, un outil marketing ou un service d'analytique
supplementaire.

## 6. Enregistrer et envoyer les modifications

Quand la categorie, les coordonnees et la fiche principale sont terminees :

1. Ouvrir `Vue d'ensemble de la publication`.
2. Verifier que chaque ligne correspond bien a PronoWin.
3. Verifier qu'aucun changement inattendu n'apparait.
4. Lorsque le bouton est actif, choisir `Envoyer l'application pour examen`.

L'envoi des declarations pour examen ne publie pas encore l'application en
production. La production reste bloquee tant que le test ferme obligatoire n'a
pas ete accompli.

## 7. Fichier Android pour Google Play

Google Play attend un Android App Bundle (`.aab`), pas l'APK direct.

```powershell
cd C:\xampp\htdocs\PronoWin\mobile_new
.\tool\build.ps1 -Canal play -ApiUrl https://pronowin.space/api/v1
```

Fichier attendu :

```text
C:\xampp\htdocs\PronoWin\mobile_new\build\app\outputs\bundle\release\app-release.aab
```

Avant chaque nouvel envoi, verifier que le `versionCode` Android augmente.
Google Play refusera une version ayant le meme code. Le numero se change a un
seul endroit, `mobile_new/pubspec.yaml` : `version: 1.0.7+8`, ou `8` est le
`versionCode`.

### Signature : quelle cle est quoi

Il existe deux modeles de signature, et la difference change ce qui arrive en
cas de perte de fichier.

| | Detenteur de la cle de signature | Perte du `.jks` local |
| --- | --- | --- |
| **Play App Signing** — obligatoire pour toute application creee apres aout 2021 | **Google** | recuperable |
| Ancien modele | le developpeur | irreversible |

PronoWin a ete creee en 2026 : **Play App Signing s'applique**, sans option
pour s'en passer.

Donc `C:\Users\1\pronowin-release.jks` **n'est pas** la cle de signature de
l'application. C'est la **cle de televersement** : elle sert uniquement a
prouver a Google que l'envoi vient bien de nous. Google re-signe ensuite l'AAB
avec la vraie cle de signature, qu'il a generee et qu'il conserve.

Sa partie privee n'a jamais quitte la machine. Google n'en detient que le
certificat public, extrait du premier AAB televerse.

**En cas de perte** : generer une nouvelle cle et demander une reinitialisation
de la cle de televersement au support Play. Google remplace le certificat
enregistre. Compter quelques jours.

Ce n'est donc pas une perte definitive — mais quelques jours sans pouvoir
televerser tombent tres mal au milieu des 14 jours de test ferme, pendant
lesquels on veut pouvoir pousser une correction. Une copie du `.jks` sur un
support externe ou dans un gestionnaire de mots de passe suffit.

### Verifier quelle cle la console a enregistree

Console : **Test et publication → Configuration → Integrite de l'application**.
Deux entrees doivent apparaitre, « Cle de signature de l'application » et
« Cle de televersement », chacune avec son certificat.

Pour comparer avec le fichier local, dans un terminal — le mot de passe est
demande de facon interactive, il ne passe donc pas par l'historique du shell :

```powershell
keytool -list -v -keystore "C:\Users\1\pronowin-release.jks"
```

L'empreinte SHA-256 affichee doit correspondre a celle de la « cle de
televersement » dans la console.

`mobile_new/android/key.properties` porte le chemin du keystore et les mots de
passe. Il est dans `.gitignore` et doit y rester. Sans lui, le build bascule
sur la cle de debogage — `build.gradle.kts` refuse explicitement de produire un
tel artefact, parce qu'il s'installe et se lance normalement mais que Google
Play le rejette.

## 8. Test ferme obligatoire avant la production

Pour un compte developpeur personnel recent, Google demande actuellement :

1. Terminer la configuration de l'application.
2. Creer une version de **test ferme** et y televerser le fichier `.aab`.
3. Ajouter au moins **12 testeurs** avec leurs comptes Google.
4. Les 12 testeurs doivent accepter le programme et rester inscrits pendant au
   moins **14 jours consecutifs**.
5. A la fin des 14 jours, demander l'acces a la production dans le tableau de
   bord et repondre aux questions sur le test effectue.

Un test interne est utile pour verifier rapidement le build, mais ne remplace
pas le test ferme de 12 testeurs pendant 14 jours.

## Verification avant toute soumission

- [ ] Le fichier envoye est `app-release.aab`, construit avec `-Canal play`.
- [ ] Le build Play ne montre ni bookmaker, ni Mobile Money, ni affiliation.
- [ ] Les achats Premium passent par Google Play Billing.
- [ ] L'e-mail et le site de support sont accessibles.
- [ ] Les pages de confidentialite et de suppression de compte sont en ligne.
- [ ] Les captures montrent seulement la vraie application Play.
- [ ] Les instructions OTP de Google fonctionnent encore.
- [ ] Les declarations de donnees correspondent au build soumis.
- [ ] Le test ferme sera lance avant toute demande de production.

## Sources officielles Google Play

- [Configurer une application et sa fiche Play Store](https://support.google.com/googleplay/android-developer/answer/9859152?hl=en)
- [Preparer l'application depuis le tableau de bord](https://support.google.com/googleplay/android-developer/answer/9859454?hl=en)
- [Securite des donnees](https://support.google.com/googleplay/android-developer/answer/10787469?hl=en-EN)
- [Exigences de test ferme pour un compte personnel](https://support.google.com/googleplay/android-developer/answer/14151465?hl=en-GB)
- [Assets de la fiche Play Store](https://support.google.com/googleplay/android-developer/answer/9866151?hl=en)
- [Bonnes pratiques de la fiche Play Store](https://support.google.com/googleplay/android-developer/answer/13393723?hl=en)
