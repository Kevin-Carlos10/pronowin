/**
 * La double authentification du panneau, de l'activation à la connexion.
 *
 * Aucun second facteur n'existait : un mot de passe suffisait pour valider des
 * paiements, bannir, publier (constat A1 de l'audit du 24 septembre 2026).
 *
 * Ce contrôle démarre le vrai `server.js` face à une API simulée, avec un
 * dossier de données temporaire, et parcourt ce que ferait une personne :
 * activer, se reconnecter, se tromper, rejouer un code, utiliser un code de
 * secours, être obligée d'activer, être réinitialisée.
 *
 *   node _check_double_auth.js
 */
const { spawn } = require('child_process');
const bcrypt = require('bcryptjs');
const fs   = require('fs');
const http = require('http');
const os   = require('os');
const path = require('path');
const { codeAuPas, pasCourant } = require('./lib/deux_facteurs');

const PORT     = 4620 + (process.pid % 300);
const PORT_API = PORT + 1000;
const MDP      = 'MotDePasseDeBanc123';
const DIR      = fs.mkdtempSync(path.join(os.tmpdir(), 'admin-2fa-'));

let echecs = 0;
const ko = (m) => { console.log('  ✗ ' + m); echecs++; };
const ok = (m) => console.log('  ✓ ' + m);

const compte = (id, username) => ({
  id, name: 'Compte ' + username, username, passwordHash: bcrypt.hashSync(MDP, 10),
  permissions: ['pronostics:read'], isActive: true, createdAt: new Date().toISOString(), lastLoginAt: null,
});
fs.writeFileSync(path.join(DIR, 'sub_admins.json'), JSON.stringify([compte('s1', 'alice'), compte('s2', 'bruno')]));
fs.writeFileSync(path.join(DIR, 'settings.json'), JSON.stringify({ loginMaxAttempts: 50 }));

const api = http.createServer((req, res) => {
  let corps = '';
  req.on('data', (c) => corps += c);
  req.on('end', () => {
    res.setHeader('Content-Type', 'application/json');
    if (req.method === 'POST' && req.url === '/api/v1/admin/login') {
      const { email } = JSON.parse(corps || '{}');
      if (email !== 'principal@banc') { res.statusCode = 401; return res.end('{"message":"non"}'); }
      return res.end(JSON.stringify({ token: 'jeton-principal', admin: { id: 'a1', name: 'Principal', role: 'super_admin' } }));
    }
    res.end(JSON.stringify({ data: [], total: 0, count: 0 }));
  });
});

function requete(chemin, { methode = 'GET', cookies = '', corps = null } = {}) {
  return new Promise((resolve) => {
    const donnees = corps ? new URLSearchParams(corps).toString() : null;
    const r = http.request({
      host: '127.0.0.1', port: PORT, path: chemin, method: methode,
      headers: {
        ...(cookies ? { Cookie: cookies } : {}),
        ...(donnees ? { 'Content-Type': 'application/x-www-form-urlencoded',
          'Content-Length': Buffer.byteLength(donnees), Origin: `http://127.0.0.1:${PORT}` } : {}),
      },
    }, (res) => {
      let body = '';
      res.on('data', (c) => body += c);
      res.on('end', () => resolve({ status: res.statusCode, location: res.headers.location ?? null,
        setCookie: res.headers['set-cookie'] ?? [], body }));
    });
    r.on('error', () => resolve({ status: 0, setCookie: [], body: '' }));
    if (donnees) r.write(donnees);
    r.end();
  });
}
const cookiesDe = (r) => r.setCookie.map((c) => c.split(';')[0]).filter((c) => !/=$/.test(c)).join('; ');
const connexion = (username, password = MDP) =>
  requete('/admin/login', { methode: 'POST', corps: { username, password } });
const aSession = (r) => /admin_session=[^;]/.test(cookiesDe(r));
const attendre = (ms) => new Promise((r) => setTimeout(r, ms));

(async () => {
  await new Promise((r) => api.listen(PORT_API, '127.0.0.1', r));
  const srv = spawn(process.execPath, ['server.js'], {
    cwd: __dirname,
    env: { ...process.env, ADMIN_PORT: String(PORT), ADMIN_DATA_DIR: DIR,
      API_URL: `http://127.0.0.1:${PORT_API}/api/v1`,
      ADMIN_PERM_SECRET: 'secret-de-banc', ADMIN_DELEGATION_SECRET: 'delegation-de-banc',
      ADMIN_API_TOKEN: 'jeton-de-service', ADMIN_SERVICE_EMAIL: '', ADMIN_SERVICE_PASSWORD: '',
      ADMIN_ORIGIN: `http://127.0.0.1:${PORT}`, NODE_ENV: 'test' },
    stdio: ['ignore', 'ignore', 'pipe'],
  });
  let stderr = '';
  srv.stderr.on('data', (d) => stderr += d);
  const fin = (code) => { srv.kill(); api.close(); fs.rmSync(DIR, { recursive: true, force: true }); process.exit(code); };
  for (let i = 0; i < 60; i++) { if ((await requete('/admin/login')).status) break; await attendre(250); }

  console.log('\nDouble authentification');

  // ── Activer ──
  const co = await connexion('alice');
  let ck = cookiesDe(co);
  if (!aSession(co)) { ko('la connexion d\'alice n\'ouvre pas de session' + (stderr ? '\n' + stderr : '')); return fin(1); }
  const page = await requete('/admin/profile/2fa', { cookies: ck });
  const secret = (/class="fa-secret"[^>]*>([A-Z2-7 ]+)</.exec(page.body) ?? [])[1]?.replace(/ /g, '');
  if (!secret || !/<svg/.test(page.body)) { ko('la page d\'activation ne montre ni clé ni QR code'); return fin(1); }
  ok('la page d\'activation montre la clé et le QR code');

  const faux = await requete('/admin/profile/2fa/activer', { methode: 'POST', cookies: ck, corps: { code: '000000' } });
  if (/error=/.test(faux.location ?? '')) ok('un code faux n\'active rien');
  else ko('un code faux active la double authentification');

  const pas = pasCourant();
  const active = await requete('/admin/profile/2fa/activer', {
    methode: 'POST', cookies: ck, corps: { code: codeAuPas(secret, pas) } });
  const secours = [...active.body.matchAll(/<span>([0-9a-f]{5}-[0-9a-f]{5})<\/span>/g)].map((m) => m[1]);
  if (active.status === 200 && secours.length === 8) ok('l\'activation affiche huit codes de secours, une fois');
  else ko(`activation : ${active.status}, ${secours.length} code(s) de secours`);
  const fichier = fs.readFileSync(path.join(DIR, 'double_auth.json'), 'utf8');
  if (!fichier.includes(secret) && !secours.some((c) => fichier.includes(c))) ok('ni la clé ni les codes de secours ne sont en clair sur le disque');
  else ko('double_auth.json contient la clé ou un code de secours en clair');
  await requete('/admin/logout', { cookies: ck });

  // ── Se reconnecter : le mot de passe ne suffit plus ──
  const etape = await connexion('alice');
  if (!aSession(etape) && /code-form/.test(etape.body)) ok('avec la 2FA active, le mot de passe seul n\'ouvre pas de session');
  else ko('le mot de passe seul ouvre encore une session');
  let ck2 = cookiesDe(etape);

  const mauvais = await requete('/admin/login/2fa', { methode: 'POST', cookies: ck2, corps: { code: '123456' } });
  if (!aSession(mauvais) && /Code incorrect/.test(mauvais.body)) ok('un code faux est refusé, sans session');
  else ko('un code faux ouvre une session');

  // Le code déjà utilisé à l'activation est refusé : rejeu.
  const rejeu = await requete('/admin/login/2fa', { methode: 'POST', cookies: ck2, corps: { code: codeAuPas(secret, pas) } });
  if (!aSession(rejeu)) ok('un code déjà accepté ne l\'est pas une seconde fois');
  else ko('un code déjà utilisé ouvre une session (rejeu)');

  const bon = await requete('/admin/login/2fa', { methode: 'POST', cookies: ck2, corps: { code: codeAuPas(secret, pas + 1) } });
  if (aSession(bon)) ok('le code suivant ouvre la session');
  else ko(`le bon code n'ouvre pas de session (${bon.status})`);
  await requete('/admin/logout', { cookies: cookiesDe(bon) });

  // ── Code de secours ──
  const e3 = await connexion('alice');
  const viaSecours = await requete('/admin/login/2fa', { methode: 'POST', cookies: cookiesDe(e3), corps: { code: secours[0] } });
  if (aSession(viaSecours) && /secours=1/.test(viaSecours.location ?? '')) ok('un code de secours ouvre la session, et l\'écran le signale');
  else ko('un code de secours n\'ouvre pas la session');
  await requete('/admin/logout', { cookies: cookiesDe(viaSecours) });
  const e4 = await connexion('alice');
  const secoursRejoue = await requete('/admin/login/2fa', { methode: 'POST', cookies: cookiesDe(e4), corps: { code: secours[0] } });
  if (!aSession(secoursRejoue)) ok('un code de secours ne sert qu\'une fois');
  else ko('un code de secours sert deux fois');

  // ── Obligatoire ──
  const reglages = JSON.parse(fs.readFileSync(path.join(DIR, 'settings.json'), 'utf8'));
  fs.writeFileSync(path.join(DIR, 'settings.json'), JSON.stringify({ ...reglages, exiger2fa: true }));
  const bruno = await connexion('bruno');
  const ckB = cookiesDe(bruno);
  const tableau = await requete('/admin/dashboard', { cookies: ckB });
  if (/profile\/2fa\?obligatoire=1/.test(bruno.location ?? '') && /profile\/2fa\?obligatoire=1/.test(tableau.location ?? '')) {
    ok('quand elle est obligatoire, un compte sans 2FA ne va nulle part ailleurs que sur son activation');
  } else {
    ko(`2FA obligatoire : connexion vers ${bruno.location}, tableau de bord ${tableau.status} ${tableau.location}`);
  }

  // ── Réinitialisation par l'administrateur principal ──
  fs.writeFileSync(path.join(DIR, 'settings.json'), JSON.stringify(reglages));
  const principal = await requete('/admin/login', { methode: 'POST', corps: { username: 'principal@banc', password: 'x' } });
  await requete('/admin/sub-admins/s1/2fa/reinitialiser', { methode: 'POST', cookies: cookiesDe(principal), corps: { x: '1' } });
  const apres = await connexion('alice');
  if (aSession(apres)) ok('après réinitialisation par le principal, le compte se reconnecte sans code');
  else ko('la réinitialisation n\'a pas retiré le second facteur');

  console.log(echecs === 0 ? '\n✅ Double authentification : activée, exigée, non rejouable\n' : `\n❌ ${echecs} problème(s)\n`);
  fin(echecs === 0 ? 0 : 1);
})();
