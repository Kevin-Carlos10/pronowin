/**
 * Désactiver, supprimer, ou retirer ses droits à un sous-admin doit agir sur
 * la session ouverte, pas seulement sur la prochaine connexion.
 *
 * Les cookies portaient à eux seuls l'identité, le rôle et les permissions,
 * signés une fois à la connexion et jamais relus. Mesuré sur le serveur réel,
 * avant correction :
 *
 *     désactivé       : 200 → TRAVAILLE ENCORE
 *     supprimé        : 200 → TRAVAILLE ENCORE
 *     droits retirés  : 200 → ACCÈS CONSERVÉ
 *
 * Ces trois boutons sont les seuls moyens de reprendre un accès. Ils
 * annonçaient une révocation qui n'avait pas lieu — et la page affichait
 * « Inactif » à côté du compte pendant qu'il continuait de travailler. C'est
 * pire que de ne pas les avoir : on croit l'accès coupé, et on passe à autre
 * chose. Avec « Se souvenir de moi », le sursis durait 30 jours.
 *
 * Rien dans les tests ne pouvait le voir : les vues se rendaient, le compte
 * s'affichait bien comme désactivé, les permissions étaient bien enregistrées.
 * Il fallait ouvrir une session, la révoquer, et regarder ce qu'elle ouvrait
 * encore. C'est ce que fait ce contrôle.
 *
 * Il démarre le vrai `server.js` sur un port libre, avec `ADMIN_DATA_DIR`
 * pointé sur un dossier temporaire : aucun compte réel n'est touché.
 *
 *   node _check_session_revoquee.js
 */
const { spawn } = require('child_process');
const bcrypt = require('bcryptjs');
const fs   = require('fs');
const http = require('http');
const os   = require('os');
const path = require('path');

const PORT = 4177 + (process.pid % 300);
const MDP  = 'MotDePasseDeBanc123';
const DIR  = fs.mkdtempSync(path.join(os.tmpdir(), 'admin-banc-'));

let echecs = 0;
const ko = (m) => { console.log('  ✗ ' + m); echecs++; };
const ok = (m) => console.log('  ✓ ' + m);

const SA = path.join(DIR, 'sub_admins.json');
const lire   = () => JSON.parse(fs.readFileSync(SA, 'utf8'));
const ecrire = (d) => fs.writeFileSync(SA, JSON.stringify(d, null, 2));

const compteDeBanc = (permissions) => ({
  id: 'banc', name: 'Compte de banc', username: 'compte_banc',
  passwordHash: bcrypt.hashSync(MDP, 10),
  permissions, isActive: true,
  createdAt: new Date().toISOString(), lastLoginAt: null,
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
        } : {}),
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

const attendre = (ms) => new Promise((r) => setTimeout(r, ms));
/** Une session vivante ouvre la page ; une session révoquée part vers /admin/login. */
const ouvert = (r) => !(r.status === 302 && (r.location ?? '').startsWith('/admin/login'));

(async () => {
  ecrire([compteDeBanc(['pronostics:read', 'pronostics:write'])]);
  fs.writeFileSync(path.join(DIR, 'settings.json'), '{}');

  const srv = spawn(process.execPath, ['server.js'], {
    cwd: __dirname,
    env: {
      ...process.env,
      ADMIN_PORT: String(PORT), ADMIN_DATA_DIR: DIR,
      ADMIN_API_TOKEN: 'jeton-de-banc',
      ADMIN_SERVICE_EMAIL: '', ADMIN_SERVICE_PASSWORD: '',
      NODE_ENV: 'test',
    },
    stdio: ['ignore', 'ignore', 'pipe'],
  });
  let stderr = '';
  srv.stderr.on('data', (d) => stderr += d);

  const fin = (code) => {
    srv.kill();
    fs.rmSync(DIR, { recursive: true, force: true });
    process.exit(code);
  };

  for (let i = 0; i < 60; i++) {
    if ((await requete('/admin/login')).status) break;
    await attendre(250);
  }

  console.log('\nRévocation d\'une session de sous-admin');

  const co = await requete('/admin/login', {
    methode: 'POST', corps: { username: 'compte_banc', password: MDP },
  });
  const cookies = co.setCookie.map((c) => c.split(';')[0]).join('; ');
  if (!/admin_token=[^;]/.test(cookies)) {
    ko('la connexion de banc n\'ouvre pas de session — le contrôle ne prouve rien'
       + (stderr ? '\n' + stderr : ''));
    return fin(1);
  }

  // ── 0. Une session vide ne doit pas s'ouvrir ──
  //
  // Sans jeton d'API, `admin_token` était posé à la chaîne vide, que
  // `requireAuth` traite comme une absence de session : le sous-admin repartait
  // au formulaire à la page suivante, sans message, après un « Connexion
  // réussie » au journal. Vu de lui, les bons identifiants ramenaient au
  // formulaire. C'est l'état dans lequel était la production : le mot de passe
  // du compte de service ne correspondait plus.
  const sansJeton = await requeteSurServeurSansJeton();
  if (sansJeton.refuse) {
    ok('sans jeton d\'API, la connexion est refusée avec un message');
  } else {
    ko('sans jeton d\'API, la connexion pose un cookie vide : le sous-admin est '
     + 'renvoyé au formulaire sans savoir pourquoi, et le journal note une réussite');
  }

  // Deux cibles, pour deux questions différentes.
  //
  // `VIVANT` sert à demander « cette session est-elle encore ouverte ? ». Elle
  // ne doit toucher à rien d'autre : `/admin/sub-admins` lit des fichiers
  // locaux et ne parle pas à l'API. Une session vivante y reçoit 403
  // (`requireMain` — un sous-admin n'y a pas sa place) ou 200 pour l'admin
  // principal ; une session révoquée reçoit une redirection vers la connexion.
  //
  // La première version de ce banc interrogeait `/admin/pronostics`, qui appelle
  // l'API. Avec le jeton factice du banc, l'API répond 401 et le panneau
  // redirige vers `/admin/login?expired=1` — que le banc lisait comme une
  // révocation. Sur la machine de développement, où l'API n'écoute pas, l'appel
  // échouait sans réponse HTTP, aucune redirection n'avait lieu, et le contrôle
  // passait pour une raison qui n'était pas celle qu'il croyait vérifier. Il
  // n'a montré la différence qu'une fois lancé sur le serveur, où l'API tourne.
  const VIVANT = '/admin/sub-admins';
  // `CIBLE` sert à la seule question de permission : `requirePerm` répond 403
  // avant tout appel à l'API, donc ce point-là ne dépend pas de son état.
  const CIBLE = '/admin/pronostics';

  // Sans ce premier point, un serveur qui refuserait tout passerait les trois
  // suivants sans rien garantir.
  if (ouvert(await requete(VIVANT, { cookies }))) ok('une session valide ouvre la page');
  else ko('une session valide est refusée — le reste du contrôle ne veut rien dire');

  // ── 1. Désactivation ──
  let subs = lire(); subs.find((s) => s.id === 'banc').isActive = false; ecrire(subs);
  const desactive = await requete(VIVANT, { cookies });
  if (!ouvert(desactive)) ok('un compte désactivé perd sa session en cours');
  else ko('un compte désactivé continue de travailler : le bouton « Désactiver » '
        + 'ne bloque que la prochaine connexion');
  if ((desactive.location ?? '').includes('fin=desactive')) {
    ok('l\'écran de connexion annonce la désactivation, pas une expiration');
  } else {
    ko('la raison affichée est « session expirée » : elle envoie réessayer une '
     + 'connexion qui ne peut pas aboutir');
  }

  // ── 2. Suppression ──
  ecrire(lire().filter((s) => s.id !== 'banc'));
  const supprime = await requete(VIVANT, { cookies });
  if (!ouvert(supprime)) ok('un compte supprimé perd sa session en cours');
  else ko('un compte supprimé travaille encore — jusqu\'à 30 jours avec '
        + '« Se souvenir de moi »');

  // ── 3. Permissions retirées ──
  ecrire([{ ...compteDeBanc([]), passwordHash: lireHashOuNeuf() }]);
  const retire = await requete(CIBLE, { cookies });
  if (retire.status === 403) ok('les droits retirés s\'appliquent à la session en cours');
  else ko(`droits retirés : la page répond ${retire.status} au lieu de 403 — le `
        + 'cookie signé à la connexion décide encore');

  // ── 4. Pas de boucle sur la page de connexion ──
  //
  // La révocation renvoie vers /admin/login, seul chemin où elle ne s'applique
  // pas — sinon il se révoquerait lui-même. Mais /admin/login renvoyait vers le
  // tableau de bord dès qu'un cookie `admin_token` traînait, sans regarder à
  // quoi il correspondait : le tableau de bord révoquait, renvoyait ici, qui
  // renvoyait là. On n'en sortait qu'en vidant ses cookies à la main.
  //
  // Le compte est ici toujours actif (étape 3 l'a recréé sans droits) : il faut
  // le retirer pour que la session soit vraiment révoquée, sans quoi ce point
  // testerait une session valide et passerait pour de mauvaises raisons.
  ecrire([]);
  const page = await requete('/admin/login', { cookies });
  if (page.status === 200) ok('la page de connexion reste joignable avec des cookies révoqués');
  else ko(`la page de connexion répond ${page.status} vers ${page.location} : une `
        + 'session révoquée y est renvoyée, et s\'y fait révoquer à nouveau — boucle');

  // Et l'inverse : une session valide doit toujours être renvoyée au tableau de
  // bord. Sans ce point, un serveur qui aurait simplement supprimé la
  // redirection passerait le précédent.
  ecrire([compteDeBanc(['pronostics:read'])]);
  const co2 = await requete('/admin/login', {
    methode: 'POST', corps: { username: 'compte_banc', password: MDP },
  });
  const cookies2 = co2.setCookie.map((c) => c.split(';')[0]).join('; ');
  const rebond = await requete('/admin/login', { cookies: cookies2 });
  if (rebond.status === 302 && (rebond.location ?? '').includes('/admin/dashboard')) {
    ok('une session valide est toujours renvoyée au tableau de bord');
  } else {
    ko(`une session valide reçoit ${rebond.status} sur /admin/login : la page de `
     + 'connexion se réaffiche à quelqu\'un déjà connecté');
  }

  // ── 5. Inactivité, appliquée par le serveur ──
  //
  // « Session (min) » n'était appliquée que par une minuterie JavaScript dans
  // la page ouverte, qui repartait de zéro à chaque chargement : onglet fermé,
  // retour le lendemain, session toujours ouverte. On simule ici le retour
  // d'un navigateur dont le cookie d'activité est vieux — c'est exactement ce
  // qu'envoie un onglet resté fermé.
  const vieux = cookies2.replace(/admin_last_active=\d+/,
    'admin_last_active=' + (Date.now() - 31 * 60000));
  const apresInactivite = await requete(VIVANT, { cookies: vieux });
  if (!ouvert(apresInactivite)) {
    ok('une session inactive au-delà du délai réglé est fermée par le serveur');
  } else {
    ko(`31 min d'inactivité : la page répond ${apresInactivite.status}. Le `
     + 'réglage « Session (min) » ne tient qu\'à une minuterie dans la page, '
     + 'remise à zéro à chaque chargement.');
  }

  // Et le complément : une session active ne doit pas être fermée. Sans ce
  // point, un serveur qui déconnecterait tout le monde passerait le précédent.
  const frais = cookies2.replace(/admin_last_active=\d+/,
    'admin_last_active=' + Date.now());
  if (ouvert(await requete(VIVANT, { cookies: frais }))) {
    ok('une session active n\'est pas fermée');
  } else {
    ko('une session active est fermée : le délai d\'inactivité se déclenche à tort');
  }

  // ── 5 bis. L'admin principal n'est pas un sous-admin ──
  //
  // La revalidation cherche le compte dans `sub_admins.json`, où l'admin
  // principal ne figure pas : le rattacher à cette règle par inadvertance le
  // déconnecterait à chaque requête, c'est-à-dire fermerait le panneau à tout
  // le monde. Ce point le vérifie explicitement.
  const cookiesMain = 'admin_token=jeton-de-banc; admin_role=main; admin_name=Principal; '
                    + 'admin_last_active=' + Date.now();
  if (ouvert(await requete(VIVANT, { cookies: cookiesMain }))) {
    ok('la session de l\'admin principal n\'est pas révoquée');
  } else {
    ko('l\'admin principal est déconnecté par la revalidation : il n\'a pas de '
     + 'ligne dans sub_admins.json et n\'a pas à en avoir');
  }

  // ── 6. L'activité réelle doit reposer le jalon ──
  //
  // Le serveur ne rafraîchissait `admin_last_active` que sur un chargement de
  // page. Quelqu'un qui remplit un long formulaire ne charge rien : le délai
  // d'inactivité l'aurait déconnecté en cliquant sur « Enregistrer », sa saisie
  // perdue. C'est le risque introduit par le point 5, pas un défaut d'origine —
  // et il ne se voit pas dans une requête HTTP, seulement dans le script.
  const layout = fs.readFileSync(path.join(__dirname, 'views', 'layout_bottom.ejs'), 'utf8');
  if (/function marquerActivite\(\)[\s\S]{0,400}document\.cookie\s*=\s*'admin_last_active=/.test(layout)
      && /function onActivity\(\)[\s\S]{0,300}marquerActivite\(\)/.test(layout)) {
    ok('l\'activité dans la page repose le jalon d\'inactivité');
  } else {
    ko('rien ne repose `admin_last_active` sur l\'activité : un long formulaire '
     + 'sera perdu à l\'enregistrement');
  }

  console.log(echecs === 0
    ? '\n✅ Révocation de session : effective sur les sessions ouvertes\n'
    : `\n❌ ${echecs} problème(s)\n`);
  fin(echecs === 0 ? 0 : 1);
})();

/** Le hash n'a pas besoin d'être le même : la session testée est déjà ouverte. */
function lireHashOuNeuf() { return bcrypt.hashSync(MDP, 10); }

/**
 * Démarre une seconde instance privée de jeton d'API — l'état exact où était la
 * production — et tente une connexion de sous-admin.
 *
 * Une instance à part : le jeton se lit dans l'environnement au démarrage, on ne
 * peut donc pas le retirer au serveur déjà lancé.
 */
function requeteSurServeurSansJeton() {
  const PORT2 = PORT + 1;
  return new Promise((resolve) => {
    const srv2 = spawn(process.execPath, ['server.js'], {
      cwd: __dirname,
      env: {
        ...process.env,
        ADMIN_PORT: String(PORT2), ADMIN_DATA_DIR: DIR,
        ADMIN_API_TOKEN: '',
        ADMIN_SERVICE_EMAIL: '', ADMIN_SERVICE_PASSWORD: '',
        NODE_ENV: 'test',
      },
      stdio: ['ignore', 'ignore', 'ignore'],
    });

    const poster = () => new Promise((res2) => {
      const corps = new URLSearchParams(
        { username: 'compte_banc', password: MDP }).toString();
      const r = http.request({
        host: '127.0.0.1', port: PORT2, path: '/admin/login', method: 'POST',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Content-Length': Buffer.byteLength(corps),
        },
      }, (rep) => {
        let body = '';
        rep.on('data', (c) => body += c);
        rep.on('end', () => res2({
          status: rep.statusCode,
          setCookie: rep.headers['set-cookie'] ?? [],
          body,
        }));
      });
      r.on('error', () => res2(null));
      r.write(corps); r.end();
    });

    (async () => {
      for (let i = 0; i < 60; i++) {
        const rep = await poster();
        if (rep) {
          srv2.kill();
          // Refusé = pas de cookie de session posé, et une page qui explique.
          const cookie = (rep.setCookie.find(c => c.startsWith('admin_token=')) ?? '');
          const poseUnJetonVide = /^admin_token=(;|$)/.test(cookie);
          resolve({
            refuse: rep.status === 200
                 && !poseUnJetonVide
                 && !rep.setCookie.some(c => c.startsWith('admin_token=')),
          });
          return;
        }
        await attendre(250);
      }
      srv2.kill();
      resolve({ refuse: false });
    })();
  });
}
