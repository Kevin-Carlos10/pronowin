/**
 * Les exports CSV du panneau rendent ce que l'écran montre, et un tableur les
 * lit comme du texte.
 *
 * Constat A16 de l'audit du 24 septembre 2026 : l'export des utilisateurs
 * ignorait la recherche, le statut et les dates, et les cellules commençant
 * par `=` restaient des formules — dans des fichiers qui contiennent des
 * pseudos et des motifs saisis par des utilisateurs.
 *
 * Ce contrôle démarre le vrai `server.js` face à une API simulée, avec un
 * dossier de données temporaire.
 *
 *   node _check_export_csv.js
 */
const { spawn } = require('child_process');
const bcrypt = require('bcryptjs');
const fs   = require('fs');
const http = require('http');
const os   = require('os');
const path = require('path');

const PORT     = 4790 + (process.pid % 300);
const PORT_API = PORT + 1000;
const MDP      = 'MotDePasseDeBanc123';
const DIR      = fs.mkdtempSync(path.join(os.tmpdir(), 'admin-export-'));

let echecs = 0;
const ko = (m) => { console.log('  ✗ ' + m); echecs++; };
const ok = (m) => console.log('  ✓ ' + m);

fs.writeFileSync(path.join(DIR, 'sub_admins.json'), JSON.stringify([{
  id: 'id-export', name: 'Compte export', username: 'export',
  passwordHash: bcrypt.hashSync(MDP, 10), permissions: ['users:read'], isActive: true,
  createdAt: new Date().toISOString(), lastLoginAt: null,
}]));
fs.writeFileSync(path.join(DIR, 'settings.json'), '{}');
// Un ban dont le pseudo et le motif sont piégés, comme un utilisateur peut les écrire.
fs.writeFileSync(path.join(DIR, 'bans.json'), JSON.stringify([{
  id: 'b1', userId: 'u1', pseudo: '=HYPERLINK("https://exemple.invalid";"Voir")',
  reason: 'Motif "entre guillemets", avec virgule', durationDays: null, expiresAt: null,
  active: true, bannedAt: new Date().toISOString(), bannedBy: 'Banc', bannedByIp: '127.0.0.1',
}]));

const CSV_API = '﻿ID,Pseudo\n"u1","\'=1+1"\n';
const appels = [];
const api = http.createServer((req, res) => {
  appels.push(req.url);
  if (req.url.startsWith('/api/v1/admin/users/export/csv')) {
    res.setHeader('Content-Type', 'text/csv; charset=utf-8');
    res.setHeader('Content-Disposition', 'attachment; filename="pronowin_users.csv"');
    return res.end(CSV_API);
  }
  res.setHeader('Content-Type', 'application/json');
  res.end(JSON.stringify({ data: [], total: 0 }));
});

function requete(chemin, { methode = 'GET', cookies = '', corps = null } = {}) {
  return new Promise((resolve) => {
    const donnees = corps ? new URLSearchParams(corps).toString() : null;
    const r = http.request({
      host: '127.0.0.1', port: PORT, path: chemin, method: methode,
      headers: {
        ...(cookies ? { Cookie: cookies } : {}),
        ...(donnees ? {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Content-Length': Buffer.byteLength(donnees),
          Origin: `http://127.0.0.1:${PORT}`,
        } : {}),
      },
    }, (res) => {
      let body = '';
      res.on('data', (c) => body += c);
      res.on('end', () => resolve({ status: res.statusCode, headers: res.headers,
        setCookie: res.headers['set-cookie'] ?? [], body }));
    });
    r.on('error', () => resolve({ status: 0, setCookie: [], body: '', headers: {} }));
    if (donnees) r.write(donnees);
    r.end();
  });
}
const attendre = (ms) => new Promise((r) => setTimeout(r, ms));

(async () => {
  await new Promise((r) => api.listen(PORT_API, '127.0.0.1', r));
  const srv = spawn(process.execPath, ['server.js'], {
    cwd: __dirname,
    env: {
      ...process.env,
      ADMIN_PORT: String(PORT), ADMIN_DATA_DIR: DIR,
      API_URL: `http://127.0.0.1:${PORT_API}/api/v1`,
      ADMIN_PERM_SECRET: 'secret-de-banc', ADMIN_DELEGATION_SECRET: 'delegation-de-banc',
      ADMIN_API_TOKEN: 'jeton-de-banc', ADMIN_SERVICE_EMAIL: '', ADMIN_SERVICE_PASSWORD: '',
      ADMIN_ORIGIN: `http://127.0.0.1:${PORT}`, NODE_ENV: 'test',
    },
    stdio: ['ignore', 'ignore', 'pipe'],
  });
  let stderr = '';
  srv.stderr.on('data', (d) => stderr += d);
  const fin = (code) => { srv.kill(); api.close(); fs.rmSync(DIR, { recursive: true, force: true }); process.exit(code); };
  for (let i = 0; i < 60; i++) { if ((await requete('/admin/login')).status) break; await attendre(250); }

  console.log('\nExports CSV');
  const co = await requete('/admin/login', { methode: 'POST', corps: { username: 'export', password: MDP } });
  const cookies = co.setCookie.map((c) => c.split(';')[0]).join('; ');
  if (!/admin_session=[^;]/.test(cookies)) { ko('la session de banc ne s\'ouvre pas' + (stderr ? '\n' + stderr : '')); return fin(1); }

  // ── Les filtres de l'écran arrivent à l'API ──
  const exp = await requete('/admin/users/export?search=kone&status=suspended&date_from=2026-09-01&plan=premium', { cookies });
  const appel = appels.find((u) => u.startsWith('/api/v1/admin/users/export/csv')) ?? '';
  const recu = new URL('http://x' + appel).searchParams;
  if (recu.get('search') === 'kone' && recu.get('status') === 'suspended'
      && recu.get('date_from') === '2026-09-01' && recu.get('plan') === 'premium') {
    ok('l\'export des utilisateurs transmet à l\'API tous les filtres de l\'écran');
  } else {
    ko('filtres reçus par l\'API : ' + (appel || 'aucun appel'));
  }
  if (exp.status === 200 && exp.body === CSV_API) ok('le fichier de l\'API est relayé tel quel');
  else ko(`export relayé : ${exp.status}, ${JSON.stringify(exp.body.slice(0, 80))}`);
  if (!appels.some((u) => /per_page=5000/.test(u))) ok('aucun repli sur une liste de 5 000 lignes');
  else ko('le relais retombe encore sur une liste de 5 000 lignes');

  // ── Les exports produits par le panneau neutralisent les formules ──
  const bans = await requete('/admin/bans/export', { cookies });
  const ligne = bans.body.split(/\r?\n/).find((l) => l.includes('HYPERLINK')) ?? '';
  if (/(^|,)"'=HYPERLINK\(""https:\/\/exemple\.invalid"";""Voir""\)"(,|$)/.test(ligne)) {
    ok('un pseudo commençant par « = » sort en texte, guillemets doublés');
  } else {
    ko('ligne exportée : ' + JSON.stringify(ligne.slice(0, 160)));
  }
  if (/"Motif ""entre guillemets"", avec virgule"/.test(ligne)) ok('un motif avec guillemets et virgule ne décale pas les colonnes');
  else ko('motif mal échappé : ' + JSON.stringify(ligne.slice(0, 160)));

  console.log(echecs === 0 ? '\n✅ Exports CSV : fidèles à l\'écran, lus comme du texte\n' : `\n❌ ${echecs} problème(s)\n`);
  fin(echecs === 0 ? 0 : 1);
})();
