/**
 * Deux origines sont identiques, ou elles ne le sont pas.
 *
 * La protection inter-origines comparait avec `startsWith` :
 *
 *     if (origin && !origin.startsWith(allowed)) …
 *
 * `https://pronowin.space.exemple.com` commence par `https://pronowin.space`.
 * Un domaine appartenant à n'importe qui passait donc le contrôle — et la même
 * erreur portait sur le `Referer`, où la comparaison se faisait en plus sur
 * une adresse complète au lieu de son origine.
 *
 * ── Ce que ce banc mesure, et ce qu'il ne mesure pas ───────────────────────
 *
 * Il envoie de vraies requêtes au serveur et lit ce qu'il répond. Il n'établit
 * pas pour autant qu'une attaque CSRF était possible : les cookies de session
 * portent tous `SameSite=Lax`, ce qui empêche déjà un navigateur de les
 * joindre à une requête POST venue d'un autre site. Ce contrôle-ci garde la
 * seconde ligne — celle qui annonçait une vérification qu'elle ne faisait pas.
 *
 *   node _check_origine.js
 */
const { spawn } = require('child_process');
const fs   = require('fs');
const http = require('http');
const os   = require('os');
const path = require('path');

const PORT = 4771;
const ORIGINE = 'https://pronowin.space';
const DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'pw-origine-'));

const echecs = [];
const ok = (m) => console.log('  ✓ ' + m);
const ko = (m) => { echecs.push(m); console.log('  ✗ ' + m); };

const dodo = (ms) => new Promise((r) => setTimeout(r, ms));

/** POST vers le panneau, avec les en-têtes demandés. */
function poster(entetes) {
  return new Promise((resolve) => {
    const corps = 'x=1';
    const req = http.request({
      host: '127.0.0.1', port: PORT, path: '/admin/sub-admins/creer',
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Content-Length': Buffer.byteLength(corps),
        ...entetes,
      },
    }, (res) => {
      let data = '';
      res.on('data', (d) => data += d);
      res.on('end', () => resolve({ statut: res.statusCode, corps: data }));
    });
    req.on('error', () => resolve({ statut: 0, corps: '' }));
    req.write(corps);
    req.end();
  });
}

/** Le contrôle d'origine a-t-il refusé cette requête ? */
const refusee = (r) => r.statut === 403 && /origine|inter-origines/i.test(r.corps);

(async () => {
  fs.writeFileSync(path.join(DIR, 'sub_admins.json'), '[]');
  fs.writeFileSync(path.join(DIR, 'settings.json'), '{}');

  const srv = spawn(process.execPath, ['server.js'], {
    cwd: __dirname,
    env: {
      ...process.env,
      ADMIN_PORT: String(PORT),
      ADMIN_DATA_DIR: DIR,
      ADMIN_ORIGIN: ORIGINE,
      ADMIN_PERM_SECRET: 'secret-de-banc-non-publie',
      ADMIN_DELEGATION_SECRET: 'delegation-de-banc',
      ADMIN_API_TOKEN: 'jeton-de-banc',
      ADMIN_SERVICE_EMAIL: '', ADMIN_SERVICE_PASSWORD: '',
    },
    stdio: ['ignore', 'ignore', 'pipe'],
  });
  let stderr = '';
  srv.stderr.on('data', (d) => stderr += d);

  // Attendre que le serveur réponde.
  for (let i = 0; i < 80; i++) {
    const r = await poster({ Origin: ORIGINE });
    if (r.statut) break;
    await dodo(250);
  }

  try {
    // ── Le défaut : un domaine qui commence pareil ──
    for (const usurpee of [
      ORIGINE + '.exemple.com',
      ORIGINE + '-autre.fr',
      'https://pronowin.space.attaquant.io',
    ]) {
      if (refusee(await poster({ Origin: usurpee }))) {
        ok(`origine refusée : ${usurpee}`);
      } else {
        ko(`origine acceptée alors qu'elle est étrangère : ${usurpee}`);
      }
    }

    // ── Contrepartie : la vraie origine passe ──
    //
    // Sans elle, un serveur qui refuserait tout passerait les contrôles
    // ci-dessus sans rien prouver — et le panneau serait inutilisable.
    if (!refusee(await poster({ Origin: ORIGINE }))) {
      ok('la véritable origine est acceptée');
    } else {
      ko('la véritable origine est refusée : le panneau ne fonctionnerait plus');
    }

    // ── Le Referer suit la même règle ──
    if (refusee(await poster({ Referer: ORIGINE + '.exemple.com/admin/x' }))) {
      ok('referer d\'un domaine étranger refusé');
    } else {
      ko('un referer étranger passe : la comparaison porte sur le préfixe');
    }

    if (!refusee(await poster({ Referer: ORIGINE + '/admin/sub-admins' }))) {
      ok('referer de la véritable origine accepté');
    } else {
      ko('le referer légitime est refusé');
    }

    // ── Ni l'un ni l'autre : on refuse ──
    if (refusee(await poster({}))) {
      ok('sans Origin ni Referer, la requête est refusée');
    } else {
      ko('une requête sans provenance vérifiable est acceptée');
    }

    // ── Les cookies de session portent « secure » ──
    //
    // `COOKIE_SECURE` dépendait de `NODE_ENV === 'production'`, une variable
    // définie nulle part sur le serveur — ni dans `.env`, ni dans le processus
    // pm2. Le panneau est servi en HTTPS et ses cookies partaient sans cet
    // attribut. Il se déduit désormais de `ADMIN_ORIGIN`, qui est en https ici.
    const source = fs.readFileSync(path.join(__dirname, 'server.js'), 'utf8');
    const decl = source.slice(source.indexOf('const COOKIE_SECURE'),
                              source.indexOf('const COOKIE_SECURE') + 200);
    if (decl.includes('ADMIN_ORIGIN')) {
      ok('« secure » se déduit de l\'adresse déclarée du panneau');
    } else {
      ko('« secure » dépend de nouveau d\'une variable que personne ne pose');
    }
  } finally {
    srv.kill();
  }

  if (stderr.trim()) console.log('  (stderr) ' + stderr.trim().slice(0, 200));
  try { fs.rmSync(DIR, { recursive: true, force: true }); } catch { /* sans gravité */ }

  console.log(echecs.length
    ? `\n❌ ${echecs.length} problème(s)\n`
    : '\n✅ Origine : la comparaison est exacte\n');
  process.exit(echecs.length ? 1 : 0);
})();
