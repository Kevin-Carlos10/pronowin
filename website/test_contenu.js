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

  const accueil           = await recuperer(site.address().port, '/');
  const legal             = await recuperer(site.address().port, '/mentions-legales');
  const confidentialite   = await recuperer(site.address().port, '/confidentialite');
  const suppressionCompte = await recuperer(site.address().port, '/suppression-compte');

  // Les conditions generales existent en deux versions, comme dans
  // l'application : le canal des boutiques ne publie pas l'article consacre a
  // l'activation contre l'ouverture d'un compte chez le bookmaker partenaire.
  const cgu       = await recuperer(site.address().port, '/cgu');
  const cguDirect = await recuperer(site.address().port, '/cgu?canal=direct');

  site.close();
  if (api) api.close();
  return { accueil, legal, confidentialite, suppressionCompte, cgu, cguDirect };
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
/**
 * Le site ne promet pas de comparaison de cotes.
 *
 * Le serveur n'interroge qu'un seul opérateur — `XBET_BOOKMAKER_ID = 11` dans
 * `api_football.service` — et c'est délibéré : le modèle est l'affiliation à un
 * partenaire, pas la comparaison. Le produit est cohérent avec lui-même ; c'est
 * la page qui promettait autre chose.
 *
 * Ce contrôle a d'abord été écrit comme deux chaînes interdites — « bookmakers
 * comparé » et « comparées entre bookmakers ». La promesse a survécu dans une
 * troisième formulation, « cotes comparées », aux deux endroits les plus
 * exposés : la méta-description que Google affiche et le sous-titre du hero.
 *
 * Une liste de phrases n'attrape que ce qu'on a déjà vu. Le motif vise donc la
 * notion : « comparé » à portée de « cote » ou de « bookmaker », dans un sens
 * comme dans l'autre.
 */
/**
 * Aucune promesse de gain.
 *
 * La signature disait « Des pronostics gagnants, des gains grandissants » —
 * dans le <title> que Google affiche, en titre principal de l'accueil et en
 * pied de page. Double promesse, et elle contredisait le texte au bas de la
 * même page : « aucun gain n'est garanti ».
 *
 * Promettre en gros et démentir en petit n'est pas prudent. Le lecteur lit le
 * gros, et c'est cette structure qu'un examinateur relève.
 *
 * Les mentions rétrospectives restent permises : « 12 gagnés sur 18 » énonce
 * un fait sur des paris déjà tranchés. C'est l'annonce d'un résultat futur qui
 * est interdite, pas le compte-rendu d'un résultat passé.
 */
const PROMESSES = [
  [/pronostics? gagnants?/i,     'promet des pronostics qui gagnent'],
  [/gains? grandissants?/i,      'promet des gains qui augmentent'],
  [/apprends? à gagner/i,        'promet une issue, pas une méthode'],
  [/(profit|revenus?|gains?) (assuré|garanti)/i, 'promesse de résultat'],
  [/sans risque|argent facile/i, 'nie le risque'],
];

const COMPARAISON =/(cotes?|bookmakers?)[^.<]{0,30}compar|compar[^.<]{0,30}(cotes?|bookmakers?)/i;

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

test('la fiche Play, quand elle existe, devient le seul téléchargement public', async () => {
  // L'état qui n'existe pas encore. Le jour de l'approbation, il suffira de
  // renseigner PLAY_STORE_URL — mais un basculement jamais éprouvé est un
  // basculement qui casse le jour où on en a besoin, sous la pression.
  //
  // L'enjeu dépasse l'affichage : le site est le seul endroit où Google voit
  // les deux canaux côte à côte. Le binaire Play ne peut pas montrer
  // l'affiliation — `STORE_BUILD` est une constante de compilation — mais un
  // APK du même paquet mis en avant à côté de la fiche peut se lire comme un
  // contournement.
  const avant = process.env.PLAY_STORE_URL;
  process.env.PLAY_STORE_URL =
    'https://play.google.com/store/apps/details?id=com.pronowin.app';

  try {
    const { accueil } = await rendre(API_COMPLETE);

    assert.ok(accueil.html.includes('play.google.com/store/apps/details'),
      'la fiche Play devrait être annoncée');

    assert.ok(!accueil.html.includes('Télécharger l\'APK directement'),
      'l\'APK ne doit pas être proposé sur la vitrine');
    assert.ok(!accueil.html.includes('/downloads/app-release.apk'),
      'aucun lien direct vers l\'APK ne doit être rendu');
  } finally {
    if (avant === undefined) delete process.env.PLAY_STORE_URL;
    else process.env.PLAY_STORE_URL = avant;
  }
});

test('sans fiche Play, la vitrine ne propose pas l\'APK public', async () => {
  // Pendant la validation Play, l'APK est partagé dans les canaux de
  // communication choisis par PronoWin. Les badges de store ne promettent pas
  // un lien qui n'existe pas encore.
  const { accueil } = await rendre(API_COMPLETE);

  assert.ok(!/class="store-badge" download/.test(accueil.html),
    'l\'APK ne doit pas porter de badge public');
  assert.ok(!accueil.html.includes('/downloads/app-release.apk'),
    'aucun lien direct vers l\'APK ne doit être rendu');
  assert.ok(!accueil.html.includes('play.google.com/store/apps/details'),
    'aucune fiche Play ne doit être annoncée tant qu\'elle n\'existe pas');
  assert.strictEqual((accueil.html.match(/Bientôt/g) || []).length, 2,
    'les deux stores devraient être annoncés « bientôt »');
});

test('aucune promesse de gain n\'est faite', async () => {
  const { accueil, legal } = await rendre(API_COMPLETE);

  for (const [nom, page] of [['accueil', accueil], ['mentions légales', legal]]) {
    const texte = page.html.replace(/<[^>]*>/g, ' ');
    // Le titre de l'onglet vit dans une balise : le dépouillement l'emporte,
    // et c'est pourtant lui que Google affiche dans ses résultats. C'est là
    // que la signature promettait, et là que personne ne l'aurait relue.
    const titre = (page.html.match(/<title>([^<]*)<\/title>/) || [])[1] ?? '';

    for (const [motif, pourquoi] of PROMESSES) {
      assert.ok(!motif.test(texte), `${nom} : ${pourquoi}`);
      assert.ok(!motif.test(titre), `${nom}, dans le <title> : ${pourquoi}`);
    }
  }
});

test('aucune comparaison de cotes n\'est promise', async () => {
  const { accueil } = await rendre(API_COMPLETE);
  const texte = accueil.html.replace(/<[^>]*>/g, ' ');

  // La méta-description n'est pas du texte visible : elle vit dans un attribut,
  // et le retrait des balises l'emporte avec. On la contrôle à part — c'est
  // elle que Google affiche, et c'est là que la promesse avait survécu.
  const meta = (accueil.html.match(/<meta name="description" content="([^"]*)"/) || [])[1] ?? '';

  assert.ok(!COMPARAISON.test(texte),
    'comparaison de cotes promise sur la page — un seul opérateur est interrogé');
  assert.ok(!COMPARAISON.test(meta),
    'comparaison de cotes promise dans la méta-description');
});

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

test('la politique offre une suppression de compte hors application', async () => {
  const { confidentialite, suppressionCompte } = await rendre(API_COMPLETE);

  assert.strictEqual(confidentialite.statut, 200,
    'la politique de confidentialité doit être publique');
  assert.strictEqual(suppressionCompte.statut, 200,
    'la page de suppression doit être publique');
  assert.ok(confidentialite.html.includes('href="/suppression-compte"'),
    'la politique doit lier clairement la page de suppression');
  assert.ok(suppressionCompte.html.includes('PronoWin'),
    'la page de suppression doit identifier l\'application');
  assert.ok(suppressionCompte.html.includes('mailto:pronowin2026@gmail.com'),
    'la demande de suppression doit pouvoir être lancée sans connexion');
});

test('la politique distingue les pratiques de la version Google Play', async () => {
  const { confidentialite } = await rendre(API_COMPLETE);

  assert.ok(confidentialite.html.includes('Version distribuée sur Google Play'),
    'la portée de la politique Google Play doit être explicite');
  assert.ok(confidentialite.html.includes('vos données de carte bancaire'),
    'la politique doit préciser que PronoWin ne conserve pas les cartes bancaires');
  assert.ok(confidentialite.html.includes('Jeton de notification'),
    'les notifications doivent apparaître dans les données déclarées');
  assert.ok(confidentialite.html.includes('Diagnostic technique'),
    'les données Firebase techniques doivent apparaître dans les données déclarées');
});

/**
 * Les conditions generales publiees dependent du canal.
 *
 * Elles n'existaient que dans l'application. Le site n'en avait aucune page --
 * alors que c'est le lien donne depuis le paywall, la ou Apple exige des liens
 * *fonctionnels* vers les conditions d'utilisation, et la premiere page qu'un
 * examinateur ouvre apres l'URL de confidentialite.
 *
 * Les publier sur le site sans distinguer le canal aurait rendu public, pour
 * la premiere fois, l'article decrivant l'activation Premium contre
 * l'ouverture d'un compte chez un bookmaker partenaire. Le site ne nomme ce
 * partenaire nulle part, et c'est deliberе : c'est cet article qui ferait
 * classer l'application dans une categorie reservee aux organisations. La
 * version canonique est donc celle des boutiques ; la variante directe se
 * demande explicitement et ne s'indexe pas.
 */
test('les CGU ne publient l\'article partenaire que pour le canal direct', async () => {
  const { cgu, cguDirect } = await rendre(API_COMPLETE);

  assert.strictEqual(cgu.statut, 200, '/cgu doit repondre');
  assert.strictEqual(cguDirect.statut, 200, '/cgu?canal=direct doit repondre');

  const numeros = (page) =>
    [...page.html.matchAll(/<h2>(\d+)\. /g)].map((m) => Number(m[1]));

  for (const mot of ['1xBet', 'code promotionnel', 'bookmaker partenaire']) {
    assert.ok(!cgu.html.includes(mot),
      `/cgu publie « ${mot} » : cet article ne concerne pas la version des boutiques`);
  }

  // Contrepartie : sans elle, une page vide -- ou un canal ignore -- passerait
  // le controle ci-dessus sans que rien ne bronche.
  assert.ok(cguDirect.html.includes('1xBet'),
    "/cgu?canal=direct doit decrire l'activation partenaire, faute de quoi les "
    + 'utilisateurs du telechargement direct n\'ont pas leurs conditions');

  const nStore = numeros(cgu).length;
  const nDirect = numeros(cguDirect).length;
  assert.strictEqual(nDirect, nStore + 1,
    `le canal direct doit publier exactement un article de plus : ${nStore} contre ${nDirect}`);

  assert.ok(/name="robots"[^>]*noindex/.test(cguDirect.html),
    '/cgu?canal=direct doit porter noindex : le site public ne mentionne pas le partenaire');
  assert.ok(!/name="robots"[^>]*noindex/.test(cgu.html),
    "/cgu doit rester indexable : c'est la page que l'on cite");

  // Le numero vient du rang, pas d'une chaine ecrite a la main. Retirer un
  // article ne doit pas laisser de trou -- un contrat dont l'article 8 manque
  // se lit comme un contrat tronque.
  for (const [nom, page] of [['/cgu', cgu], ['/cgu?canal=direct', cguDirect]]) {
    const nums = numeros(page);
    assert.ok(nums.length > 10, `${nom} : ${nums.length} articles seulement`);
    assert.deepStrictEqual(nums, nums.map((_, i) => i + 1),
      `${nom} : numerotation discontinue -- ${nums.join(', ')}`);
  }
});

/**
 * Un document juridique n'echappe pas aux regles du site.
 *
 * Les CGU annonçaient « analyse par intelligence artificielle » alors que le
 * service lui-meme ecrit dans son en-tete : « Aucun modele generatif
 * n'intervient ici ». L'application ne dit jamais « IA » a l'utilisateur, et
 * le site refusait deja le mot -- les conditions generales etaient le seul
 * texte du produit a le promettre, et c'est celui qu'on cite en cas de litige.
 *
 * Elles annonçaient aussi une verification « sous 24 heures ouvrees », delai
 * qui vit dans un reglage du serveur que le paywall lit et affiche. Meme
 * defaut que le « 87 % » : une valeur a deux endroits, dont un seul suit.
 */
test('les CGU respectent les regles appliquees au reste du site', async () => {
  const { cgu, cguDirect } = await rendre(API_COMPLETE);

  for (const [nom, page] of [['/cgu', cgu], ['/cgu?canal=direct', cguDirect]]) {
    const texte = page.html.replace(/<[^>]*>/g, ' ');

    for (const [motif, pourquoi] of PROMESSES) {
      assert.ok(!motif.test(texte), `${nom} : ${pourquoi}`);
    }
    for (const [motif, pourquoi] of CHIFFRES_OPERATIONNELS) {
      assert.ok(!motif.test(texte), `${nom} : ${pourquoi}`);
    }
    for (const [phrase, pourquoi] of INTERDITS) {
      assert.ok(!texte.includes(phrase),
        `${nom} publie « ${phrase} » -- ${pourquoi}`);
    }
  }
});

test('aucune page publique ne publie de texte de remplissage', async () => {
  const pages = await rendre(API_COMPLETE);

  // La page des mentions legales en portait deux, dont une consigne adressee
  // au developpeur : « Contenu a completer avec vos informations d'editeur ».
  // Elle se rendait parfaitement, donc aucun controle ne la regardait — et
  // c'est la page qu'un examinateur Google ouvre juste apres l'URL de
  // confidentialite.
  const marqueurs = [
    'a renseigner', 'a completer', 'a remplir',
    'lorem ipsum', 'TODO', 'FIXME', 'XXX',
  ];

  for (const [nom, page] of Object.entries(pages)) {
    if (!page || typeof page.html !== 'string') continue;
    // Les commentaires EJS ne sont pas rendus ; on lit bien la sortie.
    const nu = page.html
      .normalize('NFD').replace(/[̀-ͯ]/g, '')   // sans accents
      .toLowerCase();
    for (const m of marqueurs) {
      assert.ok(!nu.includes(m.toLowerCase()),
        `la page « ${nom} » publie « ${m} » : un texte de remplissage visible du public`);
    }
  }
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
