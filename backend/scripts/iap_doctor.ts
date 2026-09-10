/**
 * Diagnostic de configuration IAP.
 *
 *   npm run iap:doctor            → vérifie les clés Apple et Google
 *   npm run iap:doctor -- --test-notif  → demande en plus à Apple d'envoyer une
 *                                          notification de test à ton webhook
 *
 * Objectif : ne pas découvrir qu'une clé est mal collée au moment de la
 * première vraie transaction. Chaque vérification appelle réellement l'API du
 * store — une variable présente mais invalide est signalée comme telle.
 */
import 'dotenv/config';
import axios from 'axios';
import jwt from 'jsonwebtoken';
import { JWT } from 'google-auth-library';
import { IAP_PRODUCTS } from '../src/services/iap.service';

const OK   = '  \x1b[32m✓\x1b[0m';
const KO   = '  \x1b[31m✗\x1b[0m';
const WARN = '  \x1b[33m!\x1b[0m';

let failures = 0;
const fail = (msg: string, hint?: string) => {
  failures++;
  console.log(`${KO} ${msg}`);
  if (hint) console.log(`      ${hint}`);
};
const pass = (msg: string) => console.log(`${OK} ${msg}`);
const warn = (msg: string) => console.log(`${WARN} ${msg}`);

const unescape = (v: string) => v.replace(/\\n/g, '\n');

function checkPem(raw: string | undefined, label: string, marker: string): string | null {
  if (!raw) { fail(`${label} absent`); return null; }
  const key = unescape(raw);
  if (!key.includes(marker)) {
    fail(`${label} ne ressemble pas à une clé`,
      `Attendu une ligne « ${marker} ». Colle le contenu du fichier tel quel, ` +
      `avec les sauts de ligne échappés en \\n si ton .env est sur une ligne.`);
    return null;
  }
  pass(`${label} bien formée`);
  return key;
}

// ─── Apple ────────────────────────────────────────────────────────────────────
async function checkApple(sendTestNotif: boolean) {
  console.log('\n\x1b[1mApple — App Store Server API\x1b[0m');

  const keyId    = process.env.APPLE_IAP_KEY_ID;
  const issuerId = process.env.APPLE_IAP_ISSUER_ID;
  const bundleId = process.env.APPLE_BUNDLE_ID;

  if (!keyId)    fail('APPLE_IAP_KEY_ID absent');    else pass(`APPLE_IAP_KEY_ID = ${keyId}`);
  if (!issuerId) fail('APPLE_IAP_ISSUER_ID absent'); else pass(`APPLE_IAP_ISSUER_ID = ${issuerId}`);
  if (!bundleId) fail('APPLE_BUNDLE_ID absent');     else pass(`APPLE_BUNDLE_ID = ${bundleId}`);

  const key = checkPem(process.env.APPLE_IAP_PRIVATE_KEY, 'APPLE_IAP_PRIVATE_KEY', 'BEGIN PRIVATE KEY');
  if (!key || !keyId || !issuerId || !bundleId) {
    warn('Vérification en ligne ignorée : configuration incomplète.');
    return;
  }

  let token: string;
  try {
    const now = Math.floor(Date.now() / 1000);
    token = jwt.sign(
      { iss: issuerId, iat: now, exp: now + 3000, aud: 'appstoreconnect-v1', bid: bundleId },
      key, { algorithm: 'ES256', header: { alg: 'ES256', kid: keyId, typ: 'JWT' } });
    pass('JWT ES256 signé');
  } catch (e: any) {
    fail(`Signature du JWT impossible : ${e.message}`,
      'La clé doit être une clé EC (.p8 fourni par App Store Connect), pas une clé RSA.');
    return;
  }

  // `notifications/history` accepte un intervalle et répond même sans données :
  // c'est le moyen le moins intrusif de prouver que la clé est acceptée.
  const host = 'https://api.storekit.itunes.apple.com';
  try {
    await axios.post(`${host}/inApps/v1/notifications/history`,
      { startDate: Date.now() - 3600_000, endDate: Date.now() },
      { headers: { Authorization: `Bearer ${token}` }, timeout: 15000 });
    pass('Clé acceptée par Apple (production)');
  } catch (e: any) {
    const s = e.response?.status;
    if (s === 401) {
      fail('Apple refuse la clé (401)',
        'Key ID, Issuer ID ou clé .p8 incohérents. L\'Issuer ID est celui de la page ' +
        'Integrations, pas ton Team ID.');
    } else if (s === 403) {
      fail('Clé valide mais sans autorisation (403)',
        'La clé doit être générée dans Users and Access › Integrations › In-App Purchase.');
    } else if (s === 404) {
      // 404 = l'app n'a pas encore de données, la clé est pourtant acceptée.
      pass('Clé acceptée par Apple (aucune donnée pour cette app — normal avant publication)');
    } else {
      fail(`Apple : ${s ?? ''} ${e.response?.data?.errorMessage ?? e.message}`);
    }
    if (s === 401 || s === 403) return;
  }

  if (sendTestNotif) {
    try {
      const r = await axios.post(`${host}/inApps/v1/notifications/test`, {},
        { headers: { Authorization: `Bearer ${token}` }, timeout: 15000 });
      const tok = r.data?.testNotificationToken;
      pass('Notification de test demandée à Apple');
      console.log(`      Jeton : ${tok}`);
      console.log('      Apple va appeler ton URL de notification. Résultat de la livraison :');
      await new Promise(res => setTimeout(res, 6000));
      const h = await axios.get(
        `${host}/inApps/v1/notifications/test/${encodeURIComponent(tok)}`,
        { headers: { Authorization: `Bearer ${token}` }, timeout: 15000 });
      const attempt = h.data?.sendAttempts?.[0];
      if (attempt?.sendAttemptResult === 'SUCCESS') {
        pass(`Webhook joint avec succès (${attempt.sendAttemptResult})`);
      } else {
        fail(`Livraison au webhook : ${attempt?.sendAttemptResult ?? 'inconnue'}`,
          'Ton URL doit être publique en HTTPS. localhost n\'est pas joignable par Apple.');
      }
    } catch (e: any) {
      fail(`Notification de test impossible : ${e.response?.data?.errorMessage ?? e.message}`,
        'Renseigne d\'abord l\'URL dans App Store Connect › App Information › ' +
        'App Store Server Notifications (version 2).');
    }
  }
}

// ─── Google ───────────────────────────────────────────────────────────────────
async function checkGoogle() {
  console.log('\n\x1b[1mGoogle Play — Android Publisher API\x1b[0m');

  const pkg   = process.env.ANDROID_PACKAGE_NAME;
  const email = process.env.GOOGLE_SA_CLIENT_EMAIL;

  if (!pkg)   fail('ANDROID_PACKAGE_NAME absent');   else pass(`ANDROID_PACKAGE_NAME = ${pkg}`);
  if (!email) fail('GOOGLE_SA_CLIENT_EMAIL absent'); else pass(`GOOGLE_SA_CLIENT_EMAIL = ${email}`);

  const key = checkPem(process.env.GOOGLE_SA_PRIVATE_KEY, 'GOOGLE_SA_PRIVATE_KEY', 'BEGIN PRIVATE KEY');
  if (!key || !pkg || !email) {
    warn('Vérification en ligne ignorée : configuration incomplète.');
    return;
  }

  const client = new JWT({
    email, key, scopes: ['https://www.googleapis.com/auth/androidpublisher'],
  });

  try {
    await client.authorize();
    pass('Jeton d\'accès obtenu pour le compte de service');
  } catch (e: any) {
    fail(`Authentification refusée : ${e.message}`,
      'Vérifie que la clé JSON correspond bien à ce compte de service.');
    return;
  }

  try {
    const r = await client.request<any>({
      url: `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/`
         + `${encodeURIComponent(pkg)}/subscriptions`,
      timeout: 15000,
    });
    const list: any[] = r.data?.subscriptions ?? [];
    pass(`Accès à l'app accordé — ${list.length} abonnement(s) déclaré(s)`);

    const declared = new Set(list.map(s => s.productId));
    for (const id of Object.keys(IAP_PRODUCTS)) {
      if (declared.has(id)) pass(`Produit présent sur Play : ${id}`);
      else fail(`Produit ABSENT de Play : ${id}`,
        'À créer dans Monetize › Subscriptions, avec exactement cet identifiant.');
    }
  } catch (e: any) {
    const s = e.response?.status;
    const m = e.response?.data?.error?.message ?? e.message;
    if (s === 401 || s === 403) {
      fail(`Accès refusé (${s}) : ${m}`,
        'Dans Play Console › Users and permissions, invite le compte de service et ' +
        'donne-lui « View financial data » + accès à cette application. ' +
        'La propagation peut prendre jusqu\'à 24 h.');
    } else if (s === 404) {
      fail(`Application introuvable : ${pkg}`,
        'ANDROID_PACKAGE_NAME doit correspondre au nom de package publié.');
    } else {
      fail(`Google Play : ${s ?? ''} ${m}`);
    }
  }
}

// ─── Webhooks ─────────────────────────────────────────────────────────────────
function checkWebhooks() {
  console.log('\n\x1b[1mURLs de notification\x1b[0m');
  const base = process.env.PUBLIC_BASE_URL;
  if (!base) {
    warn('PUBLIC_BASE_URL non défini — je ne peux pas te rappeler les URLs exactes.');
    console.log('      Ajoute PUBLIC_BASE_URL=https://ton-domaine dans .env');
    return;
  }
  if (base.startsWith('http://') || base.includes('localhost')) {
    fail(`PUBLIC_BASE_URL = ${base}`,
      'Apple et Google exigent une URL publique en HTTPS. localhost ne sera jamais appelé. ' +
      'Pour tester en local, utilise un tunnel (cloudflared, ngrok).');
  } else {
    pass(`Apple  : ${base}/api/v1/subscriptions/iap/apple-notifications`);
    pass(`Google : ${base}/api/v1/subscriptions/iap/google-notifications`);
  }
}

// ─── Produits ─────────────────────────────────────────────────────────────────
function checkProducts() {
  console.log('\n\x1b[1mProduits déclarés côté serveur\x1b[0m');
  for (const [id, p] of Object.entries(IAP_PRODUCTS)) {
    pass(`${id} — ${p.fallbackDays} jours`);
  }
  console.log('      Ces identifiants doivent être créés à l\'identique dans les deux consoles.');
}

(async () => {
  console.log('\n\x1b[1m═══ Diagnostic IAP PronoWin ═══\x1b[0m');
  console.log(`NODE_ENV = ${process.env.NODE_ENV ?? 'development'}`);
  if (process.env.IAP_ACCEPT_SANDBOX === 'true' && process.env.NODE_ENV === 'production') {
    fail('IAP_ACCEPT_SANDBOX=true en production',
      'Un compte de test Apple pourrait obtenir un Premium gratuit.');
  }

  checkProducts();
  checkWebhooks();
  await checkApple(process.argv.includes('--test-notif'));
  await checkGoogle();

  console.log(
    failures === 0
      ? '\n\x1b[32mTout est en place.\x1b[0m\n'
      : `\n\x1b[31m${failures} point(s) à corriger.\x1b[0m\n`);
  process.exit(failures === 0 ? 0 : 1);
})();
