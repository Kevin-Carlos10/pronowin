/**
 * La page « Télécharger » (11 novembre 2026).
 *
 * Elle n'est pas listée : la vitrine publique ne propose pas l'APK tant que
 * la fiche Google Play n'est pas validée. Ce contrôle tient cette promesse —
 * page non indexée, absente de l'accueil et du plan du site — et vérifie ce
 * qu'elle apporte : le code de parrainage du lien, les fichiers servis par
 * `/config` (ceux que la mise à jour intégrée installe), et Google Play seul
 * dès que sa fiche existe.
 *
 *     node test_telecharger.js
 */
const http = require('http');
const assert = require('assert');

const CONFIG = {
  apkLatestVersion: '1.0.36',
  apkUrl: 'https://pronowin.space/downloads/app-release.apk',
  apkUrls: {
    'arm64-v8a': 'https://pronowin.space/downloads/app-release-arm64-v8a.apk',
    'armeabi-v7a': 'https://pronowin.space/downloads/app-release-armeabi-v7a.apk',
    'x86_64': 'https://pronowin.space/downloads/app-release-x86_64.apk',
  },
};

function fausseApi() {
  const serveur = http.createServer((req, res) => {
    if (req.url.split('?')[0] !== '/config') { res.statusCode = 404; return res.end('{}'); }
    res.setHeader('content-type', 'application/json');
    res.end(JSON.stringify(CONFIG));
  });
  return new Promise((r) => serveur.listen(0, '127.0.0.1', () => r(serveur)));
}

function recuperer(port, chemin) {
  return new Promise((resolve, reject) => {
    http.get({ host: '127.0.0.1', port, path: chemin }, (res) => {
      let c = '';
      res.on('data', (d) => (c += d));
      res.on('end', () => resolve({ statut: res.statusCode, entetes: res.headers, html: c }));
    }).on('error', reject);
  });
}

/** Monte le site (avec l'environnement donné) et récupère les pages. */
async function monter(env, chemins) {
  const api = await fausseApi();
  const avant = { ...process.env };
  Object.assign(process.env, { API_URL: `http://127.0.0.1:${api.address().port}`, ...env });
  delete require.cache[require.resolve('./server')];
  const app = require('./server');
  const site = await new Promise((r) => { const s = app.listen(0, '127.0.0.1', () => r(s)); });
  const pages = {};
  for (const [nom, chemin] of Object.entries(chemins)) pages[nom] = await recuperer(site.address().port, chemin);
  site.close(); api.close();
  for (const k of Object.keys(process.env)) if (!(k in avant)) delete process.env[k];
  Object.assign(process.env, avant);
  return pages;
}

const tests = [];
const test = (nom, f) => tests.push([nom, f]);

test('la page répond, non indexée, et ne figure nulle part dans la vitrine', async () => {
  const p = await monter({ PLAY_STORE_URL: '' }, {
    page: '/telecharger', accueil: '/', robots: '/robots.txt', plan: '/sitemap.xml',
  });
  assert.strictEqual(p.page.statut, 200);
  assert.ok(/name="robots"[^>]*noindex/.test(p.page.html), 'la page doit porter noindex');
  assert.match(String(p.page.entetes['x-robots-tag']), /noindex/);
  assert.ok(!p.accueil.html.includes('/telecharger'), "l'accueil ne renvoie pas vers la page");
  assert.ok(!p.accueil.html.includes('.apk'), "l'accueil ne propose toujours aucun APK");
  assert.ok(p.robots.html.includes('Disallow: /telecharger'), 'robots.txt doit l\'exclure');
  assert.ok(!p.plan.html.includes('/telecharger'), 'le plan du site ne la liste pas');
});

test('les fichiers et la version viennent de /config', async () => {
  const { page } = await monter({ PLAY_STORE_URL: '' }, { page: '/telecharger' });
  assert.ok(page.html.includes(`href="${CONFIG.apkUrl}"`), "l'APK complet est proposé");
  for (const url of Object.values(CONFIG.apkUrls)) assert.ok(page.html.includes(url), url);
  assert.ok(page.html.includes('version 1.0.36'));
  assert.ok(page.html.includes('Installer des applis inconnues'), 'les étapes d\'installation');
});

test('le code de parrainage du lien s\'affiche, en majuscules', async () => {
  const { page } = await monter({}, { page: '/telecharger?parrain=awa226' });
  assert.ok(page.html.includes('Un ami t\'invite sur PronoWin'));
  assert.ok(page.html.includes('>AWA226<'), 'le code, en majuscules');
});

test('un code fantaisiste n\'entre pas dans la page', async () => {
  const { page } = await monter({}, { page: '/telecharger?parrain=%3Cscript%3Ealert(1)%3C%2Fscript%3E' });
  assert.strictEqual(page.statut, 200);
  assert.ok(!page.html.includes('<script>alert'), 'aucune balise injectée');
  assert.ok(!page.html.includes('Un ami t\'invite'), 'pas d\'invitation sans code valide');
});

test('les anciens liens de parrainage (/?parrain=) mènent à la page, le code avec eux', async () => {
  const { accueil, sans } = await monter({}, { accueil: '/?parrain=1a639b', sans: '/' });
  assert.strictEqual(accueil.statut, 302);
  assert.strictEqual(accueil.entetes.location, '/telecharger?parrain=1A639B');
  assert.strictEqual(sans.statut, 200, "sans code, l'accueil s'affiche");
});

test('fiche Google Play en ligne : Android n\'est plus envoyé que vers Play', async () => {
  const { page } = await monter({ PLAY_STORE_URL: 'https://play.google.com/store/apps/details?id=com.pronowin.app' },
    { page: '/telecharger' });
  assert.ok(page.html.includes('Télécharger sur Google Play'));
  assert.ok(!page.html.includes('.apk'), "plus aucun APK proposé à côté de la fiche Play");
});

test('fiche App Store absente : l\'iPhone est annoncé « bientôt », sans lien mort', async () => {
  const { page } = await monter({ APP_STORE_URL: '' }, { page: '/telecharger' });
  assert.ok(page.html.includes("PronoWin arrive bientôt sur l'App Store."));
  assert.ok(!page.html.includes('apps.apple.com'));
});

test('la page ne promet aucun gain', async () => {
  const { page } = await monter({}, { page: '/telecharger?parrain=AWA226' });
  const texte = page.html.replace(/<[^>]+>/g, ' ');
  for (const mot of ['gagner', 'gains', 'commission', 'FCFA']) {
    assert.ok(!texte.includes(mot), `« ${mot} » sur la page de téléchargement`);
  }
});

(async () => {
  let echecs = 0;
  for (const [nom, f] of tests) {
    try { await f(); console.log(`OK : ${nom}`); }
    catch (e) { echecs++; console.error(`ÉCHEC : ${nom}\n  ${e.message}`); }
  }
  if (echecs) { console.error(`\n${echecs} échec(s)`); process.exit(1); }
  console.log(`\n${tests.length} contrôles de la page de téléchargement`);
})();
