/**
 * Un sous-admin ne lit que ses propres actions.
 *
 * Le tableau de bord affichait `loadLogs().slice(0, 8)` — les huit dernières
 * actions de tout le monde, à qui que ce soit. Constaté en production : un
 * sous-admin y lisait les connexions de l'administrateur principal, la création
 * des autres comptes, et une tentative de connexion échouée avec l'adresse
 * e-mail saisie, en clair.
 *
 * Les surfaces prévues pour le journal étaient pourtant bien gardées :
 * `/admin/audit`, son export CSV et la page Sous-admins sont en `requireMain`,
 * et la barre latérale ne montrait même pas « Journal d'activité » à ce compte.
 * Le tableau de bord affichait le contenu de la page qu'on lui cachait — c'est
 * exactement pourquoi un contrôle par les permissions de route n'aurait rien vu.
 *
 * Ce contrôle démarre le vrai serveur sur un dossier de données temporaire,
 * ouvre une session de sous-admin, et lit la page telle qu'elle est servie.
 *
 *   node _check_journal_cloisonne.js
 */
const { spawn } = require('child_process');
const bcrypt = require('bcryptjs');
const fs   = require('fs');
const http = require('http');
const os   = require('os');
const path = require('path');

const PORT = 4801 + (process.pid % 200);
const MDP  = 'MotDePasseDeBanc123';
const DIR  = fs.mkdtempSync(path.join(os.tmpdir(), 'journal-'));

let echecs = 0;
const ko = (m) => { console.log('  ✗ ' + m); echecs++; };
const ok = (m) => console.log('  ✓ ' + m);

// Un journal qui contient de quoi fuiter : des actions du principal, celles
// d'un autre sous-admin, et une tentative échouée portant une adresse e-mail.
const MAINTENANT = new Date().toISOString();
fs.writeFileSync(path.join(DIR, 'audit_log.json'), JSON.stringify([
  { id: '1', timestamp: MAINTENANT, action: 'login',
    target: 'Admin principal: Super Admin', details: {},
    adminName: 'Super Admin', adminRole: 'main', ip: '10.0.0.1' },
  { id: '2', timestamp: MAINTENANT, action: 'login_failed',
    target: 'Identifiant: victime@exemple.com', details: {},
    adminName: 'victime@exemple.com', adminRole: 'unknown', ip: '10.0.0.2' },
  { id: '3', timestamp: MAINTENANT, action: 'sub_admin_created',
    target: 'Autre (autre_compte)', details: {},
    adminName: 'Super Admin', adminRole: 'main', ip: '10.0.0.1' },
  { id: '4', timestamp: MAINTENANT, action: 'pronostic_created',
    target: 'PSG - OM', details: {},
    adminName: 'Collegue', adminRole: 'sub', ip: '10.0.0.3' },
  { id: '5', timestamp: MAINTENANT, action: 'pronostic_created',
    target: 'Lyon - Nice', details: {},
    adminName: 'Compte de banc', adminRole: 'sub', ip: '10.0.0.4' },
], null, 2));

fs.writeFileSync(path.join(DIR, 'sub_admins.json'), JSON.stringify([{
  id: 'banc', name: 'Compte de banc', username: 'compte_banc',
  passwordHash: bcrypt.hashSync(MDP, 10),
  permissions: ['pronostics:read'], isActive: true,
  createdAt: MAINTENANT, lastLoginAt: null,
}]));
fs.writeFileSync(path.join(DIR, 'settings.json'), '{}');
fs.writeFileSync(path.join(DIR, 'bans.json'), '[]');
fs.writeFileSync(path.join(DIR, 'actualites.json'), '[]');

function requete(chemin, { cookies = '', corps = null } = {}) {
  return new Promise((resolve) => {
    const d = corps ? new URLSearchParams(corps).toString() : null;
    const r = http.request({
      host: '127.0.0.1', port: PORT, path: chemin, method: corps ? 'POST' : 'GET',
      headers: {
        ...(cookies ? { Cookie: cookies } : {}),
        ...(d ? { 'Content-Type': 'application/x-www-form-urlencoded',
                  'Content-Length': Buffer.byteLength(d) } : {}),
      },
    }, (p) => {
      let b = ''; p.on('data', (c) => b += c);
      p.on('end', () => resolve({ status: p.statusCode, body: b,
                                  location: p.headers.location ?? null,
                                  setCookie: p.headers['set-cookie'] ?? [] }));
    });
    r.on('error', () => resolve({ status: 0, body: '', setCookie: [] }));
    if (d) r.write(d); r.end();
  });
}
const dodo = (ms) => new Promise((r) => setTimeout(r, ms));

(async () => {
  const srv = spawn(process.execPath, ['server.js'], {
    cwd: __dirname,
    // Le compte de service du .env n'est pas neutralisé, et `ADMIN_API_TOKEN`
    // sert de repli. Les deux sont nécessaires, pour deux machines :
    //
    //   - sur le serveur, l'API tourne. Sans jeton valide, le tableau de bord
    //     reçoit un 401 sur ses appels et redirige vers la connexion — que ce
    //     contrôle lirait comme une session fermée. Il a échoué ainsi une fois,
    //     exactement comme le banc de révocation avant lui ;
    //   - sur une machine de développement, aucune API n'écoute : la connexion
    //     au compte de service échoue, le repli fournit un jeton, la session
    //     s'ouvre, et les appels échouent sans réponse HTTP — donc sans 401 et
    //     sans redirection. La page se rend.
    env: { ...process.env, ADMIN_PORT: String(PORT), ADMIN_DATA_DIR: DIR,
           ADMIN_API_TOKEN: 'jeton-de-banc', NODE_ENV: 'test' },
    stdio: ['ignore', 'ignore', 'pipe'],
  });
  let stderr = '';
  srv.stderr.on('data', (d) => stderr += d);
  const fin = (c) => { srv.kill(); fs.rmSync(DIR, { recursive: true, force: true }); process.exit(c); };

  for (let i = 0; i < 80; i++) { if ((await requete('/admin/login')).status) break; await dodo(250); }

  console.log('\nCloisonnement du journal d\'activité');

  const co = await requete('/admin/login', { corps: { username: 'compte_banc', password: MDP } });
  const cookies = co.setCookie.map((c) => c.split(';')[0]).join('; ');
  if (!/admin_token=[^;]/.test(cookies)) {
    ko('la session de banc ne s\'ouvre pas — le contrôle ne prouve rien'
       + (stderr ? '\n' + stderr : ''));
    return fin(1);
  }

  const page = await requete('/admin/dashboard', { cookies });
  if (page.status !== 200) {
    ko(`le tableau de bord répond ${page.status} : le contrôle ne prouve rien`);
    return fin(1);
  }

  // Ce qui ne doit pas apparaître, et pourquoi.
  const interdits = [
    ['Super Admin',          'le nom de l\'administrateur principal'],
    ['victime@exemple.com',  'une adresse e-mail issue d\'une tentative échouée'],
    ['Autre (autre_compte)', 'la création d\'un autre compte d\'administration'],
    ['Collegue',             'le nom d\'un autre sous-admin'],
    ['PSG - OM',             'l\'action d\'un autre sous-admin'],
  ];
  for (const [aiguille, quoi] of interdits) {
    if (page.body.includes(aiguille)) ko(`le tableau de bord montre ${quoi} (« ${aiguille} »)`);
    else ok(`${quoi} : absent`);
  }

  // Contrepartie indispensable : sans elle, un panneau vidé de tout passerait
  // les points précédents sans rien servir.
  if (page.body.includes('Lyon - Nice')) {
    ok('ses propres actions restent affichées');
  } else {
    ko('ses propres actions ont disparu aussi : le panneau ne sert plus à rien');
  }

  // Le bouton « Journal → » mène à une page réservée au principal.
  if (!/href="\/admin\/audit"/.test(page.body)) {
    ok('le bouton « Journal → » n\'est pas proposé');
  } else {
    const audit = await requete('/admin/audit', { cookies });
    ko(`« Journal → » est proposé alors que /admin/audit répond ${audit.status}`);
  }

  // Et la page dédiée reste fermée, quoi qu'il arrive.
  const audit = await requete('/admin/audit', { cookies });
  if (audit.status === 403) ok('/admin/audit reste refusée à un sous-admin');
  else ko(`/admin/audit répond ${audit.status} à un sous-admin`);

  const exportCsv = await requete('/admin/audit/export', { cookies });
  if (exportCsv.status === 403) ok('l\'export CSV du journal reste refusé');
  else ko(`l'export CSV répond ${exportCsv.status} à un sous-admin`);

  // « Mon activité » sur le profil : mes actions, pas celles des autres.
  const profil = await requete('/admin/profile', { cookies });
  if (profil.status === 200) {
    if (profil.body.includes('PSG - OM') || profil.body.includes('Autre (autre_compte)')) {
      ko('la page de profil montre les actions d\'autrui');
    } else {
      ok('la page de profil ne montre que ses propres actions');
    }
  } else {
    ko(`la page de profil répond ${profil.status}`);
  }

  // ── Pas de cadre vide sur le même écran ──
  //
  // Toutes les entrées d'« Accès rapides » demandent une permission d'écriture.
  // Le compte de banc n'a que `pronostics:read` : la carte s'affichait donc
  // vide, un titre et rien dessous, sans un mot pour dire pourquoi.
  // Chercher les mots seuls accusait à tort : « ACCÈS RAPIDES » titre aussi un
  // bloc de la feuille de style, présent que la carte soit rendue ou non. On
  // vise donc le titre réel de la carte.
  const titreAcces = /<h3[^>]*>[\s\S]{0,160}Accès rapides\s*<\/h3>/.test(page.body);
  const uneEntree  = /class="qa-btn"/.test(page.body);
  if (!titreAcces || uneEntree) {
    ok('la carte « Accès rapides » ne s\'affiche pas vide');
  } else {
    ko('la carte « Accès rapides » s\'affiche sans une seule entrée');
  }

  console.log(echecs === 0
    ? '\n✅ Le journal est cloisonné : chacun ne lit que ce qui le concerne\n'
    : `\n❌ ${echecs} problème(s)\n`);
  fin(echecs === 0 ? 0 : 1);
})();
