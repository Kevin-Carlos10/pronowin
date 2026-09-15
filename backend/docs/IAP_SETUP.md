# Configuration de l'achat intégré (IAP)

Le code est en place. Ce qui suit ne peut être fait que depuis tes comptes
App Store Connect et Play Console.

À chaque étape, valide avec :

```bash
npm run iap:doctor
```

Le diagnostic appelle réellement les API d'Apple et de Google : une variable
présente mais erronée est signalée comme telle, avec la cause probable.

---

## Prérequis : une URL publique en HTTPS

Apple et Google **n'appellent jamais `localhost`**. Tant que le backend n'est
pas déployé derrière un domaine public, les notifications serveur ne peuvent
pas fonctionner.

Pour tester avant le déploiement, ouvre un tunnel :

```bash
cloudflared tunnel --url http://localhost:3000
```

Reporte l'URL obtenue dans `PUBLIC_BASE_URL`. Les webhooks deviennent alors :

| Store  | URL |
|--------|-----|
| Apple  | `$PUBLIC_BASE_URL/api/v1/subscriptions/iap/apple-notifications` |
| Google | `$PUBLIC_BASE_URL/api/v1/subscriptions/iap/google-notifications` |

---

## Apple

### 1. Créer les deux abonnements

App Store Connect → ton app → **Monetization › Subscriptions**.

Crée d'abord **un groupe** (ex. `PronoWin Premium`), puis les deux produits
dedans. Le groupe est ce qui permet à l'utilisateur de passer du mensuel à
l'annuel sans se réabonner ; deux groupes distincts lui feraient payer les
deux en parallèle.

| Product ID | Durée | Prix |
|---|---|---|
| `com.pronowin.premium.monthly` | 1 mois | 14,99 $ |
| `com.pronowin.premium.annual`  | 1 an   | 134,99 $ |

Apple ne propose que des paliers : il n'existe pas de 15,00 $ exact. Si tu
retiens 14,99 $ / 134,99 $, ajuste `PREMIUM_PRICE_USD_STORE_MONTHLY` et
`PREMIUM_PRICE_USD_STORE_ANNUAL` pour que les écrans d'accroche annoncent le
même montant.

Chaque abonnement exige, avant de pouvoir être soumis : un nom affiché, une
description, une capture d'écran de l'écran d'achat, et au moins un tarif.
Tant qu'ils sont en `Missing Metadata`, l'app ne les verra pas.

### 2. Générer la clé d'API

**Users and Access › Integrations › In-App Purchase** → `+`.

⚠️ Ce n'est **pas** la même page que « App Store Connect API ». Une clé
générée au mauvais endroit produit un 403.

Tu obtiens :

| Élément | Variable |
|---|---|
| Key ID | `APPLE_IAP_KEY_ID` |
| Issuer ID (en haut de la page) | `APPLE_IAP_ISSUER_ID` |
| Fichier `.p8` | `APPLE_IAP_PRIVATE_KEY` |

Le `.p8` ne se télécharge **qu'une seule fois**.

Pour l'insérer dans `.env` sur une seule ligne :

```bash
awk 'BEGIN{ORS="\\n"} {print}' AuthKey_XXXX.p8
```

Colle le résultat entre guillemets :
`APPLE_IAP_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\nMIG...\n-----END PRIVATE KEY-----"`

### 3. Déclarer le webhook

**ton app › App Information › App Store Server Notifications** → version **2**,
URL de production *et* de sandbox.

Vérifie de bout en bout — Apple envoie une vraie notification à ton serveur et
te dit si la livraison a réussi :

```bash
npm run iap:doctor -- --test-notif
```

---

## Google Play

### 4. Créer les deux abonnements

Play Console → ton app → **Monetize › Subscriptions**.

Mêmes identifiants qu'Apple. Chaque abonnement a un *base plan* qui porte la
période de facturation et le prix.

Le diagnostic vérifie leur existence et te dit lesquels manquent.

### 5. Compte de service

1. Google Cloud Console → **IAM & Admin › Service Accounts** → créer un compte
   → **Keys › Add key › JSON**.
2. Dans le JSON : `client_email` → `GOOGLE_SA_CLIENT_EMAIL`,
   `private_key` → `GOOGLE_SA_PRIVATE_KEY` (déjà échappée en `\n`, colle-la
   telle quelle entre guillemets).
3. Play Console → **Users and permissions** → inviter cet email → donner accès
   à l'application avec **View financial data, orders, and cancellation
   survey responses**.

La propagation des droits côté Google peut prendre **plusieurs heures**. Un
403 juste après l'invitation ne signifie pas que tu t'es trompé — relance le
diagnostic plus tard.

### 6. Notifications temps réel

1. Google Cloud → **Pub/Sub** → créer un topic (ex. `pronowin-rtdn`).
2. Donner à `google-play-developer-notifications@system.gserviceaccount.com`
   le rôle **Pub/Sub Publisher** sur ce topic.
3. Créer une **subscription de type Push** vers
   `$PUBLIC_BASE_URL/api/v1/subscriptions/iap/google-notifications`.
4. Play Console → **Monetize › Monetization setup › Real-time developer
   notifications** → coller le nom complet du topic → **Send test
   notification**.

---

## Sécurité des webhooks

Les deux endpoints sont publics — ils ne peuvent pas être authentifiés par
jeton, ce sont les stores qui appellent.

- **Apple** : la signature du JWS est vérifiée via la chaîne de certificats
  `x5c` du payload. Un faux message est rejeté.
- **Google** : Pub/Sub ne signe pas le corps. La protection vient d'ailleurs —
  le serveur ne croit jamais la notification sur parole, il **rejoue la
  vérification auprès de Google** avec le `purchaseToken` avant d'accorder
  quoi que ce soit. Une notification forgée ne peut donc rien débloquer.

  Pour durcir davantage, active l'authentification OIDC sur la subscription
  Pub/Sub et vérifie le jeton `Authorization` côté serveur.

---

## Tester un achat

1. **Apple** : App Store Connect › Users and Access › **Sandbox › Test
   Accounts**. Sur l'appareil, déconnecte-toi de l'App Store, lance un build
   TestFlight ou Debug, et connecte-toi avec le compte sandbox **au moment où
   l'achat le demande** — pas dans les Réglages.
2. **Google** : Play Console › Setup › **License testing** → ajouter l'adresse
   Gmail du testeur. L'app doit être publiée au moins en **test interne**, et
   installée depuis le Play Store (pas par `flutter run`), sinon le store ne
   renvoie aucun produit.

Un build store se produit avec :

```bash
flutter build appbundle --dart-define=STORE_BUILD=true
```

Sans ce drapeau, le paywall reste sur le flux Mobile Money.

En développement, `IAP_ACCEPT_SANDBOX` vaut `true` automatiquement
(`NODE_ENV !== 'production'`). En production il doit rester à `false` : sinon
n'importe quel compte de test Apple obtient un Premium gratuit.
