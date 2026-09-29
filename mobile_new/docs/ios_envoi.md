# Envoyer l'app iOS vers App Store Connect

Le workflow Codemagic **`ios-app-store`** (« iOS — envoi vers TestFlight »)
construit le paquet signé et l'envoie à TestFlight. La soumission à l'examen
d'Apple reste un geste manuel dans App Store Connect.

Ce qu'il construit : le canal store (`STORE_BUILD=true`) — abonnement par
achat intégré uniquement, ni Mobile Money ni bookmakers, comme l'exige la
règle 3.1.1 d'Apple.

## Une fois pour toutes

1. **Le dépôt sur GitHub, relié à Codemagic.** Codemagic construit ce que
   contient le dépôt distant, pas ce poste.

2. **Une clé API App Store Connect.**
   App Store Connect → Utilisateurs et accès → Intégrations → App Store
   Connect API → générer une clé, accès **Gestionnaire d'app**. Télécharger le
   `.p8` (une seule fois possible), noter l'**Issuer ID** et le **Key ID**.
   Dans Codemagic : Team settings → Integrations → Developer Portal → ajouter
   la clé sous le nom exact **`PronoWin App Store Connect`**.
   Codemagic s'en sert pour créer le certificat de distribution et le profil
   App Store : aucun fichier de signature ne passe par ce poste ni par le dépôt.

3. **Les notifications push.**
   - developer.apple.com → Certificates, IDs & Profiles → Identifiers →
     `com.pronowin.app` → cocher **Push Notifications** → Save. Sans elle, le
     profil ne contient pas la capacité déclarée par l'app, et la signature
     échoue.
   - Keys → **+** → Apple Push Notifications service (APNs) → télécharger le
     `.p8`. Console Firebase → Paramètres du projet → Cloud Messaging → app iOS
     → **Clé d'authentification APNs** : la déposer, avec son Key ID et
     l'identifiant d'équipe `FCK95AP299`. Sans elle, Firebase n'a aucun moyen
     de joindre un iPhone.

4. **`APP_STORE_APPLE_ID` dans `codemagic.yaml`.** C'est l'« Identifiant
   Apple » numérique de l'app : App Store Connect → PronoWin → Informations
   sur l'app. Le workflow s'en sert pour numéroter les builds et s'arrête
   d'emblée s'il manque.

## À chaque envoi

Codemagic → PronoWin → **Start new build** → workflow « iOS — envoi vers
TestFlight » → branche `main`.

Le numéro de build vaut un de plus que le dernier reçu par TestFlight, jamais
moins que celui du `pubspec.yaml`. Le build apparaît dans TestFlight après le
traitement d'Apple (quinze à trente minutes), prêt pour les testeurs internes.

## Avant la première soumission à l'examen

- **Numéro de version** : App Store Connect a créé la version « 1.0 ». La
  renommer comme celle du paquet (`version:` du `pubspec.yaml`, 1.0.16 à ce
  jour), sinon le build ne peut pas lui être associé.
- **Abonnements** : `com.pronowin.premium.monthly` et
  `com.pronowin.premium.annual`, dans un même groupe, orthographiés
  exactement ainsi.
- **Confidentialité de l'app** : déclarer ce qui est collecté — adresse
  e-mail et identifiant de compte, achats, données d'usage (Firebase
  Analytics, sans identifiant publicitaire), diagnostics (Crashlytics).
- **Classification par âge** : répondre honnêtement à la partie « jeux
  d'argent » ; une app de pronostics est classée au moins 17+.
- **Note pour l'examen** : pronostics sportifs et suivi de mises, sans pari
  en argent réel ni lien vers un bookmaker dans cette version. Fournir un
  compte de démonstration : le serveur connaît déjà un compte d'examen à code
  fixe (variables `GOOGLE_PLAY_REVIEW_*` de `backend/.env`), réutilisable pour
  Apple.
- **Statut de commerçant** (Business) : obligatoire pour une diffusion dans
  l'Union européenne.
