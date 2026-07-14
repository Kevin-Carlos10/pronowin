# PronoWin — Application Mobile de Pronostic Sportif

## Structure du projet

```
pronowin/
├── mobile/          # Application Flutter
│   └── lib/
│       ├── core/    # Thème, réseau, router, stockage, constantes
│       ├── features/
│       │   └── auth/        # ✅ Sprint 1 (complet)
│       │       ├── data/    # Models, DataSources, Repositories
│       │       ├── domain/  # Entities, UseCases, Repository interfaces
│       │       └── presentation/ # Pages, Providers, Widgets
│       └── shared/          # Widgets et utils partagés
└── backend/         # API Node.js + Express + Prisma
    ├── src/
    │   ├── controllers/     # ✅ auth.controller
    │   ├── services/        # ✅ auth.service, sms.service
    │   ├── middleware/      # ✅ auth.middleware, premium.middleware
    │   ├── routes/          # ✅ auth.routes
    │   └── utils/           # ✅ generators
    └── prisma/
        └── schema.prisma    # ✅ Schéma complet (users, otp, transactions...)
```

## Démarrage rapide

### Backend (VPS)

```bash
# 1. Installer les dépendances
cd backend && npm install

# 2. Configurer l'environnement
cp .env.example .env
# Editer .env avec vos vraies valeurs

# 3. Configurer PostgreSQL
sudo -u postgres createdb pronowin_db
sudo -u postgres createuser pronowin_user

# 4. Migrations Prisma
npx prisma migrate dev --name init
npx prisma generate

# 5. Lancer le serveur
npm run dev        # Dev avec hot reload
npm run build && npm start  # Production
```

### Mobile (Flutter)

```bash
cd mobile

# 1. Installer les dépendances
flutter pub get

# 2. Configurer l'URL du backend
# Editer lib/core/constants/app_constants.dart
# Remplacer YOUR_VPS_IP par l'adresse IP de votre VPS

# 3. Lancer l'application
flutter run              # Simulateur / Device
flutter run --release    # Mode release
flutter build apk        # Build Android APK
flutter build ipa        # Build iOS IPA
```

## API Endpoints — Sprint 1 (Auth)

| Méthode | Endpoint                | Auth | Description              |
|---------|-------------------------|------|--------------------------|
| POST    | /api/v1/auth/send-otp   | Non  | Envoyer OTP par SMS      |
| POST    | /api/v1/auth/verify-otp | Non  | Vérifier OTP + connexion |
| POST    | /api/v1/auth/refresh    | Non  | Rafraîchir access token  |
| GET     | /api/v1/auth/profile    | Oui  | Profil utilisateur       |
| POST    | /api/v1/auth/logout     | Oui  | Déconnexion              |
| GET     | /health                 | Non  | Santé de l'API           |

## Sprints suivants

- **Sprint 2** : Module Pronostics (liste, détail, filtres, cotes)
- **Sprint 3** : Module Dépôt/Retrait (CinetPay, Stripe, Crypto)
- **Sprint 4** : Abonnements Premium + Code Promo
- **Sprint 5** : Système de Parrainage
- **Sprint 6** : Tutoriels vidéo
- **Sprint 7** : Notifications Push (FCM)
- **Sprint 8** : Tests & Publication stores

## Architecture Flutter — Clean Architecture

```
Presentation (UI/Riverpod) → Domain (UseCases/Entities) → Data (API/Local)
```

- **Riverpod** pour la gestion d'état
- **Dio** pour les requêtes HTTP avec intercepteurs JWT
- **Flutter Secure Storage** pour les tokens (Keychain iOS / Keystore Android)
- **go_router** pour la navigation déclarative
- **dartz** pour Either<Failure, Success> (gestion d'erreurs fonctionnelle)
