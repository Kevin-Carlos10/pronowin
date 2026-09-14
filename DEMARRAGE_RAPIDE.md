# PronoWin — Démarrage Rapide

## 1. Configuration initiale

### Backend
```bash
cd backend
cp .env.example .env
# Éditez .env avec vos vraies valeurs :
# - DATABASE_URL (PostgreSQL)
# - JWT_SECRET, JWT_REFRESH_SECRET
# - TWILIO_* (SMS OTP)
# - FOOTBALL_DATA_API_KEY (https://www.football-data.org/client/register — GRATUIT)
# - MOBCASH_ORANGE, MOBCASH_MOOV, MOBCASH_MTN (vos numéros réels)
# - XBET_PROMO_CODE (votre code promo 1xBet)

npm install
npx prisma migrate dev --name init
npx prisma generate
npm run dev
```

### Créer le premier admin
```bash
curl -X POST http://localhost:3000/api/v1/admin/create \
  -H "Content-Type: application/json" \
  -H "x-admin-setup-secret: VOTRE_ADMIN_SETUP_SECRET" \
  -d '{"email":"admin@pronowin.com","password":"MotDePasseSecurisé123","name":"Super Admin","role":"super_admin"}'
```

### Dashboard Admin
```bash
cd admin-web
cp .env.example .env
npm install
npm start
# Ouvrir : http://localhost:4000/admin
```

## 2. Mettre vos numéros MobCash dans l'app Flutter
Éditez : `mobile/lib/features/depot_retrait/presentation/pages/depot_retrait_page.dart`
```dart
static const _numbers = {
  'orange_money': '+226 70 XX XX XX',  // ← Votre vrai numéro
  'moov_money':   '+226 60 XX XX XX',  // ← Votre vrai numéro
  'mtn_momo':     '+226 50 XX XX XX',  // ← Votre vrai numéro
};
```

## 3. Flux opérationnel quotidien

### Pronostics
1. Dashboard → Pronostics → Choisir une ligue
2. Cliquer sur un match → Saisir le pronostic
3. Cocher "VIP" si premium → Publier
→ Apparaît instantanément dans l'app

### Dépôts/Retraits
1. L'utilisateur soumet sa demande dans l'app
2. Dashboard → Dépôts/Retraits → Liste des demandes en attente
3. Vérifier le paiement reçu sur MobCash
4. Cliquer "Confirmer" ou "Rejeter" + note
→ L'utilisateur reçoit une notification push

### Abonnements Premium
1. L'utilisateur soumet sa preuve (paiement OU compte 1xBet)
2. Dashboard → Abonnements → Vérifier la capture d'écran
3. Cliquer "Approuver" + durée (ex: 30 jours)
→ Premium activé automatiquement + notification

## 4. Flutter — Finir la configuration Firebase
```bash
cd mobile
flutter pub add firebase_core firebase_messaging
flutterfire configure --project=votre-projet-firebase
# Génère automatiquement lib/firebase_options.dart
flutter run
```

## 5. Forcer une mise a jour sur l'APK direct

L'APK telecharge depuis le site ne se met **jamais** a jour tout seul. Le
mecanisme de blocage existe et se pilote depuis le panneau
d'administration — Parametres → Mises a jour.

### Les valeurs, et ce qu'elles font

| Cle | Effet |
| --- | --- |
| `APK_LATEST_VERSION` | La derniere version publiee. Au-dessous, l'application propose la mise a jour **une fois par version**, avec un bouton « Plus tard ». |
| `APK_MIN_VERSION` | Le plancher. Au-dessous, la fenetre **bloque** : ni bouton retour, ni fermeture, et elle ne se referme pas non plus quand on lance le telechargement. |
| `APK_FORCE_UPDATE` | Bloque tout le monde, quelle que soit la version installee. A reserver a un defaut grave. |
| `APK_URL` | Le fichier a telecharger. **Vide, aucune invitation n'est affichee** — plutot qu'un bouton menant a un lien mort. |

Le canal store a ses propres cles (`APP_*`) : une release Play attend la
validation de Google pendant que l'APK est deja en ligne, donc les deux jeux de
versions divergent forcement. Les melanger enverrait la moitie des
utilisateurs vers une mise a jour inexistante.

### L'ordre, et pourquoi il n'est pas negociable

1. Construire l'APK : `.\tool\build.ps1 -Canal direct -ApiUrl https://pronowin.space/api/v1`
2. **Le mettre en ligne** dans `/var/www/pronowin/downloads/` et verifier qu'il se telecharge
3. Passer `APK_LATEST_VERSION` a la nouvelle version
4. **Seulement ensuite**, relever `APK_MIN_VERSION` si la mise a jour doit etre obligatoire

Relever le minimum avant d'avoir publie le fichier enferme tout le monde :
l'utilisateur telecharge, installe, relance — et retrouve la meme fenetre, a
chaque lancement, sans issue. Le serveur refuse desormais cette configuration
(« la version minimale exigee depasse la derniere version publiee »), mais
l'ordre reste le bon reflexe.

### Verifier avant et apres

```bash
curl -s https://pronowin.space/api/v1/config | python -m json.tool
curl -s -o /dev/null -w '%{http_code}\n' -L <APK_URL>
```

La seconde ligne compte autant que la premiere : une URL qui repond 404 avec un
blocage actif est le seul scenario qui ne se rattrape pas depuis l'application.

## 6. Deux variantes de build, et ce que ca change au quotidien

Depuis que l'application installe elle-meme ses mises a jour, le canal n'est
plus seulement un drapeau Dart : c'est une **variante Gradle**.

| Variante | Permission `REQUEST_INSTALL_PACKAGES` | Distribution |
| --- | --- | --- |
| `direct` | declaree | APK telecharge depuis le site |
| `play` | **absente** | App Bundle publie sur Google Play |

La permission autorise une application a installer un paquet. Elle est
indispensable au canal direct, qui telecharge le nouvel APK et le remet a
l'installateur du systeme. Elle est **interdite** au canal store : la politique
« Device and Network Abuse » reserve l'installation d'APK hors Play aux
boutiques d'applications, et sa presence dans un AAB n'est pas une mise a jour
refusee mais un motif de retrait.

Un `--dart-define` ne pouvait pas faire cette difference : il ne touche pas au
manifeste. D'ou `productFlavors`, et un seul `src/direct/AndroidManifest.xml`.

### Au quotidien

`flutter run` refuse desormais de demarrer sans variante :

```bash
flutter run --flavor direct
```

Les releases passent par le script, qui choisit la variante lui-meme :

```bash
.\tool\build.ps1 -Canal direct -ApiUrl https://pronowin.space/api/v1
.\tool\build.ps1 -Canal play   -ApiUrl https://pronowin.space/api/v1
```

Les artefacts portent le nom de leur variante :

    build\app\outputs\flutter-apk\app-direct-release.apk
    build\app\outputs\bundle\playRelease\app-play-release.aab

### Deux controles, deux moments

`test/canal_installation_test.dart` lit les sources : il attrape la permission
deplacee dans `src/main`, ou une variante supprimee, au moment ou c'est ecrit.

`tool/verifier_bundle.py` ouvre l'artefact produit et regarde ce qu'il contient
vraiment ; c'est lui qui attrape un build lance a la main sans `--flavor`. Le
script de build l'appelle pour les deux canaux.

Les deux sont necessaires. Un defaut qui ne vit que dans le binaire ne se voit
qu'en ouvrant le binaire ; un controle qui n'existe qu'a la fin arrive trop
tard.
