/**
 * La session du panneau est tenue par le serveur, et le navigateur ne peut
 * plus rien affirmer sur elle.
 *
 * L'audit du 24 septembre 2026 a relevé, sur les sessions en cookies :
 *
 *   S7 — `admin_sub_id` n'était ni signé ni `httpOnly`. En le changeant, un
 *        sous-admin prenait les permissions d'un collègue : un lecteur passait
 *        de 403 à 200 sur `/admin/actualites/new` ;
 *   S1 — le jeton d'API du compte de service (celui du super-administrateur)
 *        était posé dans le navigateur de chaque sous-admin ;
 *   S8 — toute connexion réussie à l'API ouvrait une session « main », même
 *        pour un compte de rôle `analyst` ;
 *   S9 — la limite de tentatives lisait la première valeur de
 *        `X-Forwarded-For`, que le client choisit : la changer à chaque essai
 *        remettait le compteur à zéro.
 *
 * Ce contrôle démarre le vrai `server.js` face à une API simulée, sur des
 * ports libres, avec `ADMIN_DATA_DIR` pointé sur un dossier temporaire :
 * aucun compte réel n'est touché.
 *
 *   node _check_session_serveur.js
 */
const { spawn } = require('child_process');
const bcrypt = require('bcryptjs');
const fs   = require('fs');
const http = require('http');
const os   = require('os');
const path = require('path');

const PORT     = 4480 + (process.pid % 300);
const PORT_API = PORT + 1000;
const MDP      = 'MotDePasseDeBanc123';
const JETON_SERVICE = 'jeton-du-compte-de-service-de-banc';
const DIR      = fs.mkdtempSync(path.join(os.tmpdir(), 'admin-session-'));

let echecs = 0;
const ko = (m) => { console.log('  ✗ ' + m); echecs++; };
const ok = (m) => console.log('  ✓ ' + m);

// ── Deux sous-admins aux droits différents ──
const compte = (id, username, permissions) => ({
  id, name: 'Compte ' + username, username,
  passwordHash: bcrypt.hashSync(MDP, 10),
  permissions, isActive: true,
  createdAt: new Date().toISOString(), lastLoginAt: null,
});
const LECTEUR   = compte('id-lecteur',   'lecteur',   ['pronostics:read']);
const REDACTEUR = compte('id-redacteur', 'redacteur', ['actualites:write']);
fs.writeFileSync(path.join(DIR, 'sub_admins.json'), JSON.stringify([LECTEUR, REDACTEUR]));
fs.writeFileSync(path.join(DIR, 'settings.json'), JSON.stringify({ loginMaxAttempts: 5 }));

// ── L'API simulée ──
//
// Elle répond à la connexion selon l'adresse, et note chaque appel reçu avec
// sa délégation : c'est ce qui permet de voir, côté API, au nom de qui le
// panneau parle.
const appelsApi = [];
const api = http.createServer((req, res) => {
  let corps = '';
  req.on('data', (c) => corps += c);
  req.on('end', () => {
    const delegation = req.headers['x-admin-acteur'] ?? null;
    let acteur = null;
    try { acteur = JSON.parse(Buffer.from(delegation.split('.')[0], 'base64url').toString()); } catch {}
    appelsApi.push({ methode: req.method, url: req.url, acteur });
    res.setHeader('Content-Type', 'application/json');
    if (req.method === 'POST' && req.url === '/api/v1/admin/login') {
      const { email } = JSON.parse(corps || '{}');
      const role = { 'principal@banc': 'super_admin', 'analyste@banc': 'analyst' }[email];
      if (!role) { res.statusCode = 401; return res.end(JSON.stringify({ message: 'Identifiants incorrects.' })); }
      return res.end(JSON.stringify({
        token: 'jeton-de-' + role, admin: { id: 'a-' + role, name: 'Nom ' + role, role },
      }));
    }
    res.end(JSON.stringify({ data: [], total: 0, count: 0 }));
  });
});

function requete(chemin, { methode = 'GET', cookies = '', corps = null, entetes = {} } = {}) {
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
        ...entetes,
      },
    }, (res) => {
      let body = '';
      res.on('data', (c) => body += c);
      res.on('end', () => resolve({
        status: res.statusCode, location: res.headers.location ?? null,
        setCookie: res.headers['set-cookie'] ?? [], body,
      }));
    });
    r.on('error', () => resolve({ status: 0, setCookie: [], body: '' }));
    if (donnees) r.write(donnees);
    r.end();
  });
}
const cookiesDe = (r) => r.setCookie.map((c) => c.split(';')[0]).filter((c) => !/=$/.test(c)).join('; ');
const connexion = (username, entetes = {}) =>
  requete('/admin/login', { methode: 'POST', corps: { username, password: MDP }, entetes });
const attendre = (ms) => new Promise((r) => setTimeout(r, ms));
const ouvert = (r) => !(r.status === 302 && (r.location ?? '').startsWith('/admin/login'));

(async () => {
  await new Promise((r) => api.listen(PORT_API, '127.0.0.1', r));
  const srv = spawn(process.execPath, ['server.js'], {
    cwd: __dirname,
    env: {
      ...process.env,
      ADMIN_PORT: String(PORT), ADMIN_DATA_DIR: DIR,
      API_URL: `http://127.0.0.1:${PORT_API}/api/v1`,
      ADMIN_PERM_SECRET: 'secret-de-banc-non-publie',
      ADMIN_DELEGATION_SECRET: 'delegation-de-banc',
      ADMIN_API_TOKEN: JETON_SERVICE,
      ADMIN_SERVICE_EMAIL: '', ADMIN_SERVICE_PASSWORD: '',
      ADMIN_ORIGIN: `http://127.0.0.1:${PORT}`, NODE_ENV: 'test',
    },
    stdio: ['ignore', 'ignore', 'pipe'],
  });
  let stderr = '';
  srv.stderr.on('data', (d) => stderr += d);
  const fin = (code) => {
    srv.kill(); api.close();
    fs.rmSync(DIR, { recursive: true, force: true });
    process.exit(code);
  };
  for (let i = 0; i < 60; i++) {
    if ((await requete('/admin/login')).status) break;
    await attendre(250);
  }

  console.log('\nSessions tenues par le serveur');

  // ── S1 : le jeton d'API ne quitte plus le serveur ──
  const coL = await connexion('lecteur');
  const ckL = cookiesDe(coL);
  if (!/admin_session=[^;]/.test(ckL)) {
    ko('la connexion du lecteur n\'ouvre pas de session — le contrôle ne prouve rien'
       + (stderr ? '\n' + stderr : ''));
    return fin(1);
  }
  const poses = coL.setCookie.join('\n');
  if (!poses.includes(JETON_SERVICE)) ok('le jeton du compte de service n\'est pas envoyé au navigateur');
  else ko('le jeton du compte de service est posé dans un cookie du sous-admin (S1)');
  const herites = ['admin_token', 'admin_name', 'admin_role', 'admin_perms', 'admin_sub_id']
    .filter((n) => new RegExp('(^|\\n)' + n + '=[^;]').test(poses));
  if (herites.length === 0) ok('aucun cookie ne décrit plus l\'identité, le rôle ou les droits');
  else ko('la connexion pose encore : ' + herites.join(', '));

  // ── S7 : l'identité ne se substitue pas ──
  const cible = '/admin/actualites/new';
  const refuse = await requete(cible, { cookies: ckL });
  const substitue = await requete(cible, {
    cookies: ckL + '; admin_sub_id=' + REDACTEUR.id + '; admin_name=' + encodeURIComponent(REDACTEUR.name),
  });
  const coR = await connexion('redacteur');
  const accorde = await requete(cible, { cookies: cookiesDe(coR) });
  if (refuse.status !== 403 || accorde.status !== 200) {
    ko(`le point de départ ne tient pas (lecteur ${refuse.status}, rédacteur ${accorde.status}) : `
     + 'le contrôle de substitution ne prouve rien');
  } else if (substitue.status === 403) {
    ok('un identifiant de collègue ajouté aux cookies ne donne pas ses droits (S7)');
  } else {
    ko(`le lecteur obtient ${substitue.status} sur ${cible} en ajoutant admin_sub_id=${REDACTEUR.id} (S7)`);
  }

  // ── L'API sait au nom de qui le panneau parle ──
  appelsApi.length = 0;
  await requete('/admin/dashboard', { cookies: ckL + '; admin_sub_id=' + REDACTEUR.id });
  const delegues = appelsApi.filter((a) => a.acteur);
  if (delegues.length && delegues.every((a) => a.acteur.id === LECTEUR.id)) {
    ok('chaque appel à l\'API est délégué au nom du lecteur, pas du collègue désigné par cookie');
  } else {
    ko('délégations reçues par l\'API : ' + JSON.stringify(appelsApi.map((a) => a.acteur && a.acteur.id)));
  }
  if (appelsApi.every((a) => a.acteur)) ok('aucun appel à l\'API ne part sans délégation');
  else ko('des appels partent sans délégation : ' + appelsApi.filter((a) => !a.acteur).map((a) => a.url).join(', '));
  // Le lecteur n'a ni « transactions » ni « abonnements » : le tableau de bord
  // ne doit pas demander en son nom ce que l'API lui refuserait.
  const horsDroits = appelsApi.filter((a) => /payments\/admin\/pending|subscriptions\/admin\/proofs/.test(a.url));
  if (horsDroits.length === 0) ok('le tableau de bord ne demande pas versements et preuves sans le droit de les voir');
  else ko('le tableau de bord demande au nom du lecteur : ' + horsDroits.map((a) => a.url).join(', '));

  // ── Le journal nomme la session, pas le cookie ──
  await requete('/admin/logout', { cookies: ckL + '; admin_name=Intrus' });
  const journal = JSON.parse(fs.readFileSync(path.join(DIR, 'audit_log.json'), 'utf8'));
  const sortie = journal.find((l) => l.action === 'logout');
  if (sortie && sortie.adminName === LECTEUR.name && sortie.adminId === LECTEUR.id) {
    ok('le journal attribue l\'action au compte de la session, identifiant compris');
  } else {
    ko('entrée de journal : ' + JSON.stringify(sortie && { nom: sortie.adminName, id: sortie.adminId }));
  }
  if (!ouvert(await requete('/admin/profile', { cookies: ckL }))) ok('la déconnexion ferme la session côté serveur');
  else ko('la session reste ouverte après la déconnexion');

  // ── Le fichier ne permet pas de rouvrir une session ──
  const idSession = /admin_session=([^;]+)/.exec(cookiesDe(coR))[1];
  const fichier = fs.readFileSync(path.join(DIR, 'sessions.json'), 'utf8');
  if (!fichier.includes(idSession) && !fichier.includes(decodeURIComponent(idSession))) {
    ok('sessions.json ne contient que l\'empreinte des identifiants');
  } else {
    ko('sessions.json contient l\'identifiant de session en clair');
  }

  // ── S8 : seul un super-administrateur est principal ──
  const coP = await requete('/admin/login', { methode: 'POST', corps: { username: 'principal@banc', password: 'x' } });
  if (ouvert(await requete('/admin/sub-admins', { cookies: cookiesDe(coP) }))
      && (await requete('/admin/sub-admins', { cookies: cookiesDe(coP) })).status === 200) {
    ok('un super-administrateur de l\'API ouvre une session principale');
  } else {
    ko('le super-administrateur n\'obtient pas la page des sous-admins — la suite ne prouve rien');
  }
  const coA = await requete('/admin/login', { methode: 'POST', corps: { username: 'analyste@banc', password: 'x' } });
  if (!/admin_session=[^;]/.test(cookiesDe(coA)) && /super-administrateur/.test(coA.body)) {
    ok('un compte « analyst » de l\'API n\'ouvre pas de session, et l\'écran dit pourquoi (S8)');
  } else {
    ko('un compte « analyst » de l\'API ouvre une session dans le panneau (S8)');
  }

  // ── Changer un mot de passe ferme les sessions ouvertes ──
  const coR2 = await connexion('redacteur');
  const ckR2 = cookiesDe(coR2);
  const avant = await requete(cible, { cookies: ckR2 });
  await requete('/admin/sub-admins/' + REDACTEUR.id + '/password', {
    methode: 'POST', cookies: cookiesDe(coP), corps: { password: 'NouveauMotDePasse1' },
  });
  const apres = await requete(cible, { cookies: ckR2 });
  if (avant.status === 200 && !ouvert(apres)) {
    ok('changer le mot de passe d\'un sous-admin ferme sa session en cours');
  } else {
    ko(`session du rédacteur : ${avant.status} avant, ${apres.status} après le changement de mot de passe`);
  }

  // ── S9 : la limite de tentatives ne se contourne pas par l'en-tête ──
  //
  // nginx est réglé en `$proxy_add_x_forwarded_for` : il ajoute l'adresse
  // réelle à la fin de ce que le client envoie. On reproduit exactement ce
  // qu'il transmet — une valeur choisie par le client, puis l'adresse réelle.
  const essai = (i) => requete('/admin/login', {
    methode: 'POST', corps: { username: 'inconnu@banc', password: 'faux' },
    entetes: { 'X-Forwarded-For': `10.9.${i}.${i}, 203.0.113.77` },
  });
  for (let i = 1; i <= 5; i++) await essai(i);
  const sixieme = await essai(6);
  if (/Trop de tentatives/.test(sixieme.body)) {
    ok('changer X-Forwarded-For à chaque essai ne remet pas le compteur à zéro (S9)');
  } else {
    ko('après 5 échecs, un sixième essai avec un autre X-Forwarded-For est encore accepté (S9)');
  }
  // Contrepartie : une autre adresse réelle n'est pas bloquée — sans quoi un
  // serveur qui bloquerait tout le monde passerait le point précédent.
  const autre = await requete('/admin/login', {
    methode: 'POST', corps: { username: 'inconnu@banc', password: 'faux' },
    entetes: { 'X-Forwarded-For': '10.9.9.9, 198.51.100.4' },
  });
  if (!/Trop de tentatives/.test(autre.body)) ok('une autre adresse réelle n\'est pas bloquée');
  else ko('une adresse réelle différente est bloquée aussi : le blocage n\'est plus par client');

  console.log(echecs === 0
    ? '\n✅ Sessions : identité, rôle et jeton tenus par le serveur\n'
    : `\n❌ ${echecs} problème(s)\n`);
  fin(echecs === 0 ? 0 : 1);
})();
