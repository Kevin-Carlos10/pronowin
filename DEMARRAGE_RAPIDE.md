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
