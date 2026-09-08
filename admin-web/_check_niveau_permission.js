/**
 * Le niveau accordé est le plus élevé, partout et de la même façon.
 *
 * Les cases du formulaire cascadent : cocher « Supprimer » coche « Écrire » et
 * « Lire », et les trois partent au serveur. Un compte à qui l'interface
 * accorde tout sur les pronostics est donc enregistré ainsi :
 *
 *     ["pronostics:read", "pronostics:write", "pronostics:delete"]
 *
 * Trois implémentations lisaient ce tableau, et toutes les trois renvoyaient le
 * PREMIER niveau rencontré, donc « read » :
 *
 *   - `getPermLevel` (server.js) — l'autorisation. Mesuré : une route en
 *     `requirePerm('pronostics', 'write')` répondait 403 avec « niveau écriture
 *     requis » sur un compte à qui l'écriture ET la suppression étaient
 *     accordées. Le système de permissions granulaires ne fonctionnait au-delà
 *     de la lecture pour aucun compte enregistré depuis l'interface ;
 *   - `_getLevel` (_perm_table.ejs) — le rendu du tableau ;
 *   - `getLevelFromArray` (sub_admins.ejs) — la fenêtre d'édition, qui
 *     n'affichait donc qu'une case cochée sur trois. On cochait « Écrire », on
 *     enregistrait, le panneau annonçait « Permissions mises à jour » — ce qui
 *     était vrai — et en réouvrant, seule « Lire » était cochée. Vu de
 *     l'utilisateur : « ça dit que c'est passé mais ce n'est pas pris en
 *     compte ». Et comme le formulaire repart de l'affichage, chaque
 *     enregistrement rabaissait le compte au niveau affiché.
 *
 * La règle vit maintenant dans lib/permissions.js. Le serveur et les vues
 * l'appellent ; la fenêtre d'édition, qui tourne dans le navigateur, en garde
 * un miroir — que ce contrôle compare à l'original, cas par cas.
 *
 *   node _check_niveau_permission.js
 */
const { spawn } = require('child_process');
const bcrypt = require('bcryptjs');
const ejs  = require('ejs');
const fs   = require('fs');
const http = require('http');
const os   = require('os');
const path = require('path');
const vm   = require('vm');

const { niveauAccorde, niveauSuffisant, PERMISSIONS } = require('./lib/permissions');
const { views, opts } = require('./test_all_views.js');

let echecs = 0;
const ko = (m) => { console.log('  ✗ ' + m); echecs++; };
const ok = (m) => console.log('  ✓ ' + m);

/** Les cas qui comptent, avec ce qu'ils doivent donner. */
const CAS = [
  [['pronostics:read', 'pronostics:write', 'pronostics:delete'], 'pronostics', 'delete',
   'le cas de production : la cascade des cases enregistre les trois niveaux'],
  [['pronostics:read', 'pronostics:write'], 'pronostics', 'write',
   'lecture + écriture'],
  [['pronostics:delete', 'pronostics:read'], 'pronostics', 'delete',
   'ordre inverse dans le tableau : le résultat ne doit pas en dépendre'],
  [['pronostics:read'], 'pronostics', 'read', 'lecture seule'],
  [[], 'pronostics', null, 'aucune permission'],
  [['users:delete'], 'pronostics', null, 'une autre section ne donne rien ici'],
  [['pronostics'], 'pronostics', 'write', 'ancien format sans niveau → écriture'],
  [['pronostics:bidon'], 'pronostics', null, 'un niveau inconnu ne donne rien'],
  [['pronostics:read', 'pronostics:bidon'], 'pronostics', 'read',
   'un niveau inconnu n\'efface pas un niveau valide'],
];

console.log('\nLa règle partagée');
for (const [perms, cle, attendu, quoi] of CAS) {
  const obtenu = niveauAccorde(perms, cle);
  if (obtenu === attendu) ok(`${quoi} → ${obtenu ?? 'aucun'}`);
  else ko(`${quoi} : ${obtenu ?? 'aucun'} au lieu de ${attendu ?? 'aucun'}`);
}

if (niveauSuffisant('delete', 'write') && niveauSuffisant('write', 'write')
    && !niveauSuffisant('read', 'write') && !niveauSuffisant(null, 'read')) {
  ok('la comparaison des niveaux respecte read < write < delete');
} else {
  ko('la comparaison des niveaux est fausse');
}

// ── Le miroir du navigateur répond comme l'original ──
console.log('\nMiroir dans la fenêtre d\'édition');
const source = fs.readFileSync(path.join(__dirname, 'views', 'sub_admins.ejs'), 'utf8');
const extrait = source.match(/function getLevelFromArray\(perms, key\)\s*\{[\s\S]*?\n  \}/);
if (!extrait) {
  ko('getLevelFromArray introuvable dans sub_admins.ejs');
} else {
  const bac = { resultat: null };
  vm.createContext(bac);
  new vm.Script(extrait[0] + '\nglobalThis.miroir = getLevelFromArray;').runInContext(bac);
  const divergences = [];
  for (const [perms, cle, , quoi] of CAS) {
    const a = niveauAccorde(perms, cle);
    const b = bac.miroir(perms, cle);
    if (a !== b) divergences.push(`${quoi} : serveur ${a ?? 'aucun'}, navigateur ${b ?? 'aucun'}`);
  }
  if (divergences.length === 0) {
    ok(`le miroir répond comme le serveur sur les ${CAS.length} cas`);
  } else {
    divergences.forEach((d) => ko(d));
  }
}

// ── Le tableau rendu coche les cases correspondantes ──
console.log('\nRendu du tableau de permissions');
(async () => {
  const cas = views.find((v) => v[1] === 'sub_admins');
  const locaux = {
    ...cas[2],
    subs: [{ ...cas[2].subs[0],
             permissions: ['pronostics:read', 'pronostics:write', 'pronostics:delete'] }],
  };
  // `_perm_table` est inclus avec les permissions du compte édité.
  const html = await ejs.renderFile(path.join(__dirname, 'views', '_perm_table.ejs'), {
    ...locaux, formId: 'modal',
    existingPerms: ['pronostics:read', 'pronostics:write', 'pronostics:delete'],
    PERMISSIONS, niveauAccorde,
  }, opts);

  const coche = (niveau) =>
    new RegExp(`value="pronostics:${niveau}"[^>]*checked`).test(html)
    || new RegExp(`checked[^>]*value="pronostics:${niveau}"`).test(html);

  for (const niveau of ['read', 'write', 'delete']) {
    if (coche(niveau)) ok(`« ${niveau} » est cochée pour un compte qui l'a`);
    else ko(`« ${niveau} » n'est pas cochée alors que le compte l'a : la fenêtre `
          + 'affiche moins que ce qui est enregistré, et l\'enregistrement suivant '
          + 'rabaissera le compte');
  }
  // Contrepartie : une section sans permission ne doit rien afficher de coché.
  if (!/value="users:read"[^>]*checked/.test(html)) {
    ok('une section non accordée reste décochée');
  } else {
    ko('une section non accordée apparaît cochée');
  }

  await autorisationReelle();
})();

/**
 * L'autorisation, mesurée sur le vrai serveur.
 *
 * Les points précédents portent sur la lecture d'un tableau. Celui-ci vérifie
 * ce qui compte : qu'une route protégée laisse passer un droit accordé.
 */
async function autorisationReelle() {
  const PORT = 4611 + (process.pid % 120);
  const MDP  = 'MotDePasseDeBanc123';
  const DIR  = fs.mkdtempSync(path.join(os.tmpdir(), 'niveau-'));

  fs.writeFileSync(path.join(DIR, 'sub_admins.json'), JSON.stringify([{
    id: 'banc', name: 'Compte de banc', username: 'compte_banc',
    passwordHash: bcrypt.hashSync(MDP, 10),
    permissions: ['pronostics:read', 'pronostics:write', 'pronostics:delete'],
    isActive: true, createdAt: new Date().toISOString(), lastLoginAt: null,
  }]));
  fs.writeFileSync(path.join(DIR, 'settings.json'), '{}');

  const requete = (chemin, cookies, corps) => new Promise((res) => {
    const d = corps ? new URLSearchParams(corps).toString() : null;
    const r = http.request({
      host: '127.0.0.1', port: PORT, path: chemin, method: corps ? 'POST' : 'GET',
      headers: {
        // Sans Origin, le contrôle CSRF refuse la mutation avec un 403 — que la
        // première version de ce banc attribuait aux permissions. Un 403 ne dit
        // pas de lui-même d'où il vient.
        Origin: 'http://127.0.0.1:' + PORT,
        ...(cookies ? { Cookie: cookies } : {}),
        ...(d ? { 'Content-Type': 'application/x-www-form-urlencoded',
                  'Content-Length': Buffer.byteLength(d) } : {}),
      },
    }, (p) => { let b = ''; p.on('data', (c) => b += c);
                p.on('end', () => res({ status: p.statusCode, body: b,
                                        setCookie: p.headers['set-cookie'] ?? [] })); });
    r.on('error', () => res({ status: 0, body: '', setCookie: [] }));
    if (d) r.write(d); r.end();
  });
  const dodo = (ms) => new Promise((r) => setTimeout(r, ms));

  const srv = spawn(process.execPath, ['server.js'], {
    cwd: __dirname,
    env: { ...process.env, ADMIN_PORT: String(PORT), ADMIN_DATA_DIR: DIR,
           ADMIN_API_TOKEN: 'jeton-de-banc', NODE_ENV: 'test' },
    stdio: 'ignore',
  });
  const fin = (c) => { srv.kill(); fs.rmSync(DIR, { recursive: true, force: true }); process.exit(c); };
  for (let i = 0; i < 80; i++) { if ((await requete('/admin/login')).status) break; await dodo(250); }

  console.log('\nAutorisation sur le serveur');
  const co = await requete('/admin/login', '', { username: 'compte_banc', password: MDP });
  const ck = co.setCookie.map((c) => c.split(';')[0]).join('; ');
  if (!/admin_token=[^;]/.test(ck)) {
    ko('la session de banc ne s\'ouvre pas — ce point ne prouve rien');
    return fin(1);
  }

  const ecrire = await requete('/admin/pronostics/edit/match-de-banc', ck,
    { prediction_label: 'test' });
  const refusePerm = ecrire.status === 403 && /niveau écriture requis/.test(ecrire.body);
  if (!refusePerm) {
    ok('une route « écriture » accepte un compte à qui l\'écriture est accordée');
  } else {
    ko('une route « écriture » refuse un compte à qui l\'écriture est accordée : '
     + 'les permissions granulaires ne dépassent pas la lecture');
  }

  // Contrepartie : le refus doit continuer de fonctionner pour qui n'a rien.
  fs.writeFileSync(path.join(DIR, 'sub_admins.json'), JSON.stringify([{
    id: 'banc2', name: 'Lecteur', username: 'lecteur',
    passwordHash: bcrypt.hashSync(MDP, 10),
    permissions: ['pronostics:read'], isActive: true,
    createdAt: new Date().toISOString(), lastLoginAt: null,
  }]));
  const co2 = await requete('/admin/login', '', { username: 'lecteur', password: MDP });
  const ck2 = co2.setCookie.map((c) => c.split(';')[0]).join('; ');
  const refus = await requete('/admin/pronostics/edit/match-de-banc', ck2,
    { prediction_label: 'test' });
  if (refus.status === 403) {
    ok('un compte en lecture seule reste refusé en écriture');
  } else {
    ko(`un compte en lecture seule écrit quand même (${refus.status}) : la `
     + 'correction a ouvert plus que nécessaire');
  }

  console.log(echecs === 0
    ? '\n✅ Le niveau accordé est lu de la même façon partout\n'
    : `\n❌ ${echecs} problème(s)\n`);
  fin(echecs === 0 ? 0 : 1);
}
