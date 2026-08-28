/**
 * Le site n'affirme que ce que le produit fait.
 *
 * Une page vitrine est le seul endroit du projet où une phrase fausse est
 * *lue par des inconnus* avant tout contact avec le produit. Celle-ci en
 * portait treize, dont trois témoignages signés de noms et de villes.
 *
 * Ce contrôle tient deux promesses distinctes :
 *
 *  1. Aucune affirmation fabriquée ne revient — ni les chiffres inventés, ni
 *     les fonctionnalités inexistantes (combinés, basketball, tennis, dépôt
 *     et retrait de paris), ni les faux clients.
 *
 *  2. Les chiffres qui restent viennent du serveur. Le site annonçait
 *     « 8 000 FCFA » pour un abonnement qui en coûte 6 000, et un forfait
 *     hebdomadaire qui n'existe pas. Un tarif recopié finit recopié faux.
 *
 * Le test monte une fausse API : il éprouve la vraie route, y compris la
 * lecture réseau et le repli quand elle échoue.
 *
 *     node test_contenu.js
 */
const http = require('http');
const assert = require('assert');

/* ─── Fausse API ──────────────────────────────────────────────────────── */

function fausseApi(reponses) {
  const serveur = http.createServer((req, res) => {
    const chemin = req.url.split('?')[0];
    const corps = reponses[chemin];
    if (corps === undefined) { res.statusCode = 404; return res.end('{}'); }
    res.setHeader('content-type', 'application/json');
    res.end(JSON.stringify(corps));
  });
  return new Promise((r) => serveur.listen(0, '127.0.0.1', () => r(serveur)));
}

function recuperer(port, chemin) {
  return new Promise((resolve, reject) => {
    http.get({ host: '127.0.0.1', port, path: chemin }, (res) => {
      let c = '';
      res.on('data', (d) => (c += d));
      res.on('end', () => resolve({ statut: res.statusCode, html: c }));
    }).on('error', reject);
  });
}

/** Rend la page d'accueil avec l'API décrite, et rend le HTML obtenu. */
async function rendre(reponsesApi) {
  const api = reponsesApi ? await fausseApi(reponsesApi) : null;

  // Port fermé quand on veut éprouver le repli : rien n'écoute dessus.
  process.env.API_URL = api
    ? `http://127.0.0.1:${api.address().port}`
    : 'http://127.0.0.1:1';

  delete require.cache[require.resolve('./server')];
  const app = require('./server');

  const site = await new Promise((r) => {
    const s = app.listen(0, '127.0.0.1', () => r(s));
  });

  const accueil = await recuperer(site.address().port, '/');
  const legal   = await recuperer(site.address().port, '/mentions-legales');

  site.close();
  if (api) api.close();
  return { accueil, legal };
}

/* ─── Fixtures ────────────────────────────────────────────────────────── */

const API_COMPLETE = {
  '/pronostics/bilan-premium': {
    taux_reussite: 73, periode_jours: 30, echantillon_suffisant: true,
  },
  '/subscriptions/plans': [
    { id: 'free',            price_usd: 0,  price_fcfa: null },
    { id: 'premium_monthly', price_usd: 10, price_fcfa: 6000 },
    { id: 'premium_annual',  price_usd: 90, price_fcfa: 54000 },
  ],
};

// Le serveur répond, mais refuse de publier un taux : trop peu de pronostics
// tranchés. C'est l'état réel de la production aujourd'hui.
const API_SANS_TAUX = {
  '/pronostics/bilan-premium': {
    taux_reussite: 86, periode_jours: 30, echantillon_suffisant: false,
  },
  '/subscriptions/plans': API_COMPLETE['/subscriptions/plans'],
};

/* ─── Affirmations interdites ─────────────────────────────────────────── */

// Chacune était sur la page. Le commentaire dit ce qui est vrai à la place.
const INTERDITS = [
  ['+50 000',       'la base contient 29 pronostics'],
  ['+8 000',        'la base contient 6 comptes'],
  ['4,6/5',         "l'application n'est sur aucun store : aucune note n'existe"],
  ['Kader B.',      'faux client'],
  ['Salimata O.',   'faux client'],
  ['Yacouba N.',    'faux client'],
  ['basketball',    "aucune notion de sport dans le schéma : football uniquement"],
  ['Basketball',    'idem'],
  ['tennis',        'idem'],
  ['Tennis',        'idem'],
  ['ombiné',        "aucun combiné n'existe dans le produit"],
  ['6.40',          'cote moyenne inventée pour un combiné inexistant'],
  ['Moov',          "un seul opérateur actif en base : Orange Money"],
  ['MTN',           'idem'],
  ['MoMo',          'idem'],
  ['VIP Hebdo',     "ce plan n'existe pas dans le backend"],
  ['8 000 FCFA',    "le mensuel coûte 6 000 FCFA"],
  ['2 500',         'tarif hebdomadaire inventé'],
  ['7 jours VIP',   'la récompense de parrainage est de 500 FCFA'],
  ['2 min',         "le serveur annonce « 30 minutes ouvrables »"],
  ['4 filleuls',    'compteur inventé dans une maquette'],
  ['Retrait de gains', 'PronoWin ne tient aucun compte de paris'],

  // Le service s'appelle `ai_prediction.service.ts`, mais son propre en-tête
  // dit : « Aucun modèle génératif n'intervient ici ». C'est une combinaison
  // pondérée de la cote du bookmaker et de l'écart de forme. L'application ne
  // dit jamais « IA » à l'utilisateur — elle écrit « modèle statistique
  // externe ». Le site ne doit pas promettre davantage que le produit.
  ['intelligence artificielle', 'le modèle est statistique, pas génératif'],
  [' IA ',                      'idem'],
  ['par IA',                    'idem'],
];

/**
 * Les chiffres opérationnels ne se publient pas.
 *
 * « 30 secondes » entre deux synchronisations, « 1,5 % à 5 % » de mise,
 * « 30 minutes ouvrables » de vérification : tous exacts le jour où ils ont été
 * écrits, et tous recopiés à la main depuis une constante du serveur.
 *
 * C'est ce qui les distingue de la liste ci-dessus. Ce ne sont pas des
 * inventions — ce sont des **engagements publics qui vieillissent sans bruit**.
 * Le jour où `REVIEW_DELAY_DIRECT` passe à deux heures, le serveur le dira à
 * l'utilisateur au moment de l'envoi, et cette page continuera d'annoncer
 * trente minutes. Personne ne rouvre une page de vente pour changer un réglage.
 *
 * C'est le défaut du « 87 % » sous une autre forme : une même valeur à deux
 * endroits, dont un seul est tenu à jour.
 *
 * La règle est donc : le site dit ce que le produit fait, jamais à quelle
 * cadence ni dans quelle proportion. Ces réglages restent réglables.
 */
const CHIFFRES_OPERATIONNELS = [
  [/\b30\s*(?:s\b|secondes)/,        'cadence de synchronisation — vit dans la boucle de index.ts'],
  [/1[.,]5\s*(?:[–—-]|à)?\s*\d*\s*%/, 'fourchette de mise — vit dans suggestStake()'],
  [/\d\s*%\s+du solde/,              'mise exprimée en part du solde — idem'],
  [/minutes ouvrables/,               'délai de validation — vit dans REVIEW_DELAY_DIRECT'],
  [/\b24\s*h\s*\/\s*24/,             'disponibilité de la boucle — un engagement de service'],
  [/\b500\s*F/,                      'prime de parrainage — vit dans REFERRAL_COMMISSION_L1'],
  [/\b2\s*000\s*F/,                  'seuil de retrait — vit dans REFERRAL_MIN_WITHDRAWAL'],
];

/* ─── Contrôles ───────────────────────────────────────────────────────── */

const controles = [];
const test = (nom, fn) => controles.push([nom, fn]);

test('aucun chiffre opérationnel n\'est publié', async () => {
  const { accueil } = await rendre(API_COMPLETE);
  // Sur le texte visible, balises retirées : « 1,5 – 5 % » et « du solde »
  // vivent dans deux éléments voisins, et un motif appliqué au HTML brut les
  // manque. Le banc d'injection l'a montré avant que ce commentaire existe.
  const texte = accueil.html.replace(/<[^>]*>/g, ' ');
  for (const [motif, pourquoi] of CHIFFRES_OPERATIONNELS) {
    assert.ok(!motif.test(texte),
      `${motif} publié sur la page — ${pourquoi}`);
  }
});

test('la vitrine ne nomme aucun moyen de paiement', async () => {
  // Nommer un opérateur sur la page qui vend restreint le produit dans
  // l'esprit du lecteur : Orange Money n'existe qu'en Afrique de l'Ouest et
  // du Centre, et la page s'adresse à tout le monde — avec des tarifs en
  // dollars, la combinaison devenait franchement bancale.
  //
  // Le moyen de paiement se découvre dans l'application, au moment où la
  // question se pose.
  //
  // Ce contrôle ne vise que l'accueil. Les mentions légales gardent la
  // mention, et doivent la garder : un avis légal dit comment l'argent
  // circule, et c'est ce qui rend crédible la phrase « PronoWin n'est pas un
  // établissement de paiement ».
  const { accueil } = await rendre(API_COMPLETE);

  for (const operateur of ['Orange Money', 'Mobile Money', 'Wave', 'Airtel']) {
    assert.ok(!accueil.html.includes(operateur),
      `« ${operateur} » nommé sur la vitrine — le moyen de paiement se `
      + `découvre dans l'application`);
  }
});

test('le nom de la marque n\'est pas coupé en deux', async () => {
  // `.brand` est un conteneur flex avec `gap: 8px`, prévu entre le logo et le
  // nom. Tant que « Prono » était un nœud de texte nu et « Win » un <span>,
  // flex en faisait deux éléments : l'espacement s'appliquait aussi entre les
  // deux moitiés du mot, et la marque s'affichait « Prono Win » partout.
  //
  // Rien ne le signalait — pas d'erreur, pas de test rouge, une page qui se
  // rend parfaitement en écrivant le nom de travers.
  const { accueil, legal } = await rendre(API_COMPLETE);

  for (const [nom, page] of [['accueil', accueil], ['mentions légales', legal]]) {
    assert.ok(page.html.includes('class="brand-name"'),
      `${nom} : le nom devrait être enveloppé dans un seul élément flex`);
    assert.ok(!/Prono<span>Win<\/span>/.test(page.html),
      `${nom} : « Prono » redevient un nœud de texte nu — le gap le sépare de « Win »`);
  }
});

test('aucune affirmation fabriquée ne subsiste', async () => {
  const { accueil, legal } = await rendre(API_COMPLETE);
  for (const [aiguille, pourquoi] of INTERDITS) {
    assert.ok(!accueil.html.includes(aiguille),
      `« ${aiguille} » est revenu sur l'accueil — ${pourquoi}`);
    assert.ok(!legal.html.includes(aiguille),
      `« ${aiguille} » est revenu sur les mentions légales — ${pourquoi}`);
  }
});

test('les tarifs affichés sont ceux que le serveur publie', async () => {
  const { accueil } = await rendre(API_COMPLETE);

  // Les montants sont affichés en dollars : le serveur publie `price_usd` et
  // `price_fcfa`, et c'est le premier qui est lu. Aucune conversion n'est faite
  // par le site — elle aurait demandé un taux de change écrit en dur.
  assert.ok(/>10 <span>USD/.test(accueil.html),  'le tarif mensuel du serveur (10 USD) manque');
  assert.ok(/>90 <span>USD/.test(accueil.html),  "le tarif annuel du serveur (90 USD) manque");

  // Le contre-test : les montants en francs ne doivent plus être affichés, ni
  // par une lecture restée sur `price_fcfa`, ni par une conversion maison.
  assert.ok(!/6\s000/.test(accueil.html),  'un montant en francs est affiché');
  assert.ok(!/54\s000/.test(accueil.html), 'un montant en francs est affiché');
});

test("sans tarif du serveur, aucun montant n'est inventé", async () => {
  const { accueil } = await rendre(null); // API injoignable

  assert.ok(accueil.html.includes('Voir le tarif dans l\'application'),
    'le repli sans montant devrait être affiché');
  assert.ok(!/<span>USD<\/span>/.test(accueil.html.replace(/>0 <span>USD<\/span>/, '')),
    'un montant est affiché alors que le serveur n\'a rien donné');
});

test('le grand chiffre est le taux du serveur, ou rien', async () => {
  const avec = await rendre(API_COMPLETE);
  assert.ok(avec.accueil.html.includes('mega-number'),
    'la section devrait exister quand le serveur publie un taux');
  assert.ok(/mega-number">73%/.test(avec.accueil.html),
    'le grand chiffre devrait être le taux publié (73)');

  // Le défaut historique : la vue lisait `stats[1]` par position, si bien
  // qu'elle affichait « 12 » (des ligues) sous la légende « taux de réussite ».
  const sans = await rendre(API_SANS_TAUX);
  assert.ok(!sans.accueil.html.includes('mega-number'),
    'la section devrait disparaître quand le serveur refuse de publier un taux');
  // Sur le texte visible, pas sur le HTML : l'assertion portait sur la page
  // entière, données de tracé comprises. Le jour où une icône est arrivée dont
  // les coordonnées contiennent « .86 », elle a accusé du code correct — et
  // elle aurait accusé n'importe quelle icône future au même titre.
  //
  // Ce qu'on veut interdire, c'est que le taux s'affiche. Pas que ses chiffres
  // existent quelque part dans le document.
  const texteSans = sans.accueil.html.replace(/<[^>]*>/g, ' ');
  assert.ok(!/\b86\b/.test(texteSans),
    "le taux sous-échantillonné (86) ne doit pas fuiter dans la page");
});

test('aucun lien ne mène nulle part', async () => {
  const { accueil } = await rendre(API_COMPLETE);

  // Six `href="#"` vivaient dans la page : « Se connecter » (deux fois),
  // « Nous contacter », et trois icônes de réseaux sociaux sans compte.
  const morts = accueil.html.match(/href="#"/g) || [];
  assert.strictEqual(morts.length, 0,
    `${morts.length} lien(s) pointent encore sur « # »`);

  // Un href vide passe le contrôle du « # » et ne mène pas plus loin. Les
  // icônes sociales sont filtrées sur une adresse non vide ; si ce filtre
  // saute, elles reviennent en liens creux.
  const vides = accueil.html.match(/href="\s*"/g) || [];
  assert.strictEqual(vides.length, 0,
    `${vides.length} lien(s) ont une adresse vide`);

  // Et aucune ancre ne doit viser une section supprimée.
  const ancres = [...accueil.html.matchAll(/href="#([a-zA-Z0-9_-]+)"/g)].map((m) => m[1]);
  for (const ancre of new Set(ancres)) {
    assert.ok(accueil.html.includes(`id="${ancre}"`),
      `l'ancre « #${ancre} » ne correspond à aucune section de la page`);
  }
});

test('les deux formules Premium ouvrent le même accès', async () => {
  const { accueil } = await rendre(API_COMPLETE);

  // L'API donne au mensuel et à l'annuel exactement les mêmes fonctionnalités.
  // La table réservait pourtant « Historique complet des performances » et
  // « Tous les tutoriels » à l'annuel : deux avantages inventés, sur la page
  // où l'on choisit combien payer. Les colonnes 2 et 3 doivent coïncider.
  const corps  = accueil.html.split('<tbody>')[1].split('</tbody>')[0];
  const lignes = [...corps.matchAll(/<tr>([\s\S]*?)<\/tr>/g)].map((m) => m[1]);
  assert.ok(lignes.length >= 5, 'table comparative introuvable ou vide');

  for (const ligne of lignes) {
    const cellules = [...ligne.matchAll(/<td>([\s\S]*?)<\/td>/g)].map((m) => m[1]);
    const [, , mensuel, annuel] = cellules;
    const coche = (c) => /<svg/.test(c);
    assert.strictEqual(coche(mensuel), coche(annuel),
      `« ${cellules[0].trim()} » distingue le mensuel de l'annuel, ` +
      'alors que le backend leur donne le même accès');
  }
});

test('les mentions légales décrivent le bon métier', async () => {
  const { legal } = await rendre(API_COMPLETE);

  assert.ok(legal.html.includes('ne tient aucun compte de paris'),
    'les mentions légales doivent dire que PronoWin ne tient pas de compte de paris');
  assert.ok(!legal.html.includes('réseaux sociaux indiqués en pied de page'),
    'renvoi vers des réseaux sociaux qui n\'existent pas');
});

/* ─── Exécution ───────────────────────────────────────────────────────── */

(async () => {
  let echecs = 0;
  for (const [nom, fn] of controles) {
    try {
      await fn();
      console.log(`  OK    ${nom}`);
    } catch (e) {
      echecs++;
      console.log(`  ECHEC ${nom}`);
      console.log(`        ${e.message}`);
    }
  }
  console.log(`\n${controles.length - echecs}/${controles.length} contrôles passés`);
  process.exit(echecs ? 1 : 0);
})();
