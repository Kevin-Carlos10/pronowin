const express = require('express');
const path = require('path');
const https = require('https');
const http  = require('http');

const app = express();
const PORT = process.env.PORT || 5000;

app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, 'views'));
app.use(express.static(path.join(__dirname, 'public')));

const site = {
  name: 'PronoWin',
  tagline: 'Des pronostics gagnants, des gains grandissants',
  year: new Date().getFullYear(),

  // Téléchargement direct : l'application n'est sur aucun store aujourd'hui.
  // Le badge « Google Play » pointerait donc sur une fiche inexistante — on
  // annonce ce qui existe, et on dit « bientôt » pour le reste.
  apkUrl: process.env.APK_URL || '/downloads/app-release.apk',
};

// URL de l'API, pour lire ce que le produit fait réellement.
const API_URL = process.env.API_URL || 'http://127.0.0.1:3000/api/v1';

/** Lecture JSON courte et sans conséquence : en cas d'échec, on n'affiche rien. */
function lireJson(chemin) {
  return new Promise((resolve) => {
    const client = API_URL.startsWith('https') ? https : http;
    const req = client.get(`${API_URL}${chemin}`, { timeout: 2500 }, (res) => {
      let corps = '';
      res.on('data', (c) => (corps += c));
      res.on('end', () => {
        try { resolve(JSON.parse(corps)); } catch { resolve(null); }
      });
    });
    req.on('error',   () => resolve(null));
    req.on('timeout', () => { req.destroy(); resolve(null); });
  });
}

/**
 * Bilan Premium réel, lu au rendu de la page.
 *
 * Le chiffre était écrit en dur : `{ value: '87', label: 'de taux de réussite
 * VIP' }`. C'est une affirmation publique, sur la page qui vend, et elle ne
 * dépendait d'aucune donnée — elle ne pouvait donc être exacte que par
 * accident. Le même défaut avait été corrigé dans l'application ; il vivait
 * encore ici, à deux endroits : la tuile du haut et la maquette Premium.
 *
 * En cas d'échec, ou sous le seuil d'échantillon du serveur, on ne remplace
 * pas par une estimation : la section disparaît. Une page qui annonce un
 * chiffre faux vaut moins qu'une page qui n'en annonce aucun.
 */
async function bilanPremium() {
  const d = await lireJson('/pronostics/bilan-premium?days=30');
  return d && d.echantillon_suffisant && d.taux_reussite !== null ? d : null;
}

/**
 * Tarifs réels, lus au rendu.
 *
 * Le site annonçait « VIP Hebdo — 2 500 F / semaine » et « VIP Mensuel —
 * 8 000 F ». Le premier plan n'existe pas, et le second coûte 6 000 F. Une
 * page de vente qui recopie un tarif finit par le recopier faux : celui-ci est
 * désormais lu sur /subscriptions/plans, qui est public.
 *
 * En cas d'échec, aucun montant n'est affiché — la formule reste présentée, le
 * prix renvoie à l'application. Un tarif faux se découvre au moment de payer.
 */
async function tarifsReels() {
  const plans = await lireJson('/subscriptions/plans');
  const par = {};
  if (Array.isArray(plans)) {
    for (const p of plans) {
      if (p && typeof p.price_fcfa === 'number' && p.price_fcfa > 0) par[p.id] = p.price_fcfa;
    }
  }
  return par;
}

/** 6000 → « 6 000 », avec une espace insécable fine. */
function fcfa(n) {
  return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
}

// Le tableau `stats` est supprimé.
//
// Il alimentait le grand chiffre de la page — et la vue le lisait **par
// position** : `stats[1].value`, collé à une légende écrite en dur, « de taux
// de réussite sur les pronostics VIP ». Or `stats[1]` n'a jamais été un taux.
// Quand le serveur publiait un bilan, la page affichait « 12 » (le nombre de
// ligues) présenté comme le taux de réussite ; sinon « 4 » (les pronostics du
// jour). Le plus grand chiffre du site était faux dans les deux cas.
//
// La section lit désormais le bilan lui-même, et disparaît quand il n'y en a
// pas — un indice positionnel ne peut plus se désaligner de sa légende.

// Chapitres de fonctionnalités. Chaque chiffre cité ici doit exister dans le
// produit : c'est la page qui vend, donc celle où une approximation devient un
// engagement. Les aperçus étaient écrits dans la vue, où ils affirmaient des
// faits — « 87% sur les 30 derniers jours », « Cote totale 6.40 ». Ils vivent
// ici désormais : la vue dessine, elle n'affirme plus.
const productBlocks = [
  {
    icon: 'chart',
    bg: 'black',
    eyebrow: 'Pronostics',
    title: 'Des analyses de football.\nPubliées chaque jour.',
    // « Football, basketball et tennis » : il n'existe aucune notion de sport
    // dans le schéma, ni rien hors football. Le site vendait deux sports que
    // l'application ne traite pas.
    text: "Chaque pronostic porte sa cote, les statistiques du match et un niveau de confiance exprimé en pourcentage — le même que celui affiché dans l'application.",
    photo: '/images/photo-pronostics.svg',
    stats: [
      { value: 'Cotes',   label: 'affichées par match' },
      { value: '%',       label: 'confiance chiffrée, pas un mot' },
      { value: 'Gratuit', label: 'une sélection chaque jour' },
    ],
    apercu: [
      { badge: 'green', icone: 'ball', titre: 'Real Madrid vs Barcelone', sous: 'Confiance 78 %  ·  Cote 1.72' },
      { badge: 'green', icone: 'ball', titre: 'Bayern vs Dortmund',       sous: 'Confiance 55 %  ·  Cote 2.10' },
      { badge: 'green', icone: 'ball', titre: 'Juventus vs Milan',        sous: 'Confiance 71 %  ·  Cote 1.95' },
    ],
  },
  {
    icon: 'crown',
    bg: 'white',
    eyebrow: 'Premium',
    // « Des combinés qui comptent », « 6.40 cote moyenne du combiné du jour » :
    // il n'existe aucun combiné dans le produit. La fonctionnalité était
    // inventée jusqu'à sa cote moyenne, et elle occupait le chapitre entier.
    title: 'Tous les pronostics.\nSans limite de nombre.',
    text: "L'abonnement Premium ouvre l'intégralité des pronostics publiés, les statistiques détaillées, le bilan des résultats et le suivi de bankroll, sans publicité.",
    stats: [
      { value: 'Illimité', label: 'pronostics accessibles' },
      { value: 'Bilan',    label: 'résultats déjà tranchés' },
      { value: 'Sans pub', label: "dans toute l'application" },
    ],
    apercu: [
      { badge: 'gold', icone: 'crown',  titre: 'Pronostics Premium',  sous: 'Tous ceux publiés, sans limite' },
      { badge: 'gold', icone: 'trophy', titre: 'Bilan des résultats', sous: 'Ce qui a été gagné et perdu' },
      { badge: 'dark', icone: 'shield', titre: 'Suivi de bankroll',   sous: 'Vos mises et votre solde' },
    ],
  },
  {
    icon: 'wallet',
    bg: 'black',
    eyebrow: 'Abonnement',
    // « Dépôt et retrait », « retirez vos gains », « 3 opérateurs Mobile
    // Money », « 2 min ». PronoWin ne tient aucun compte de paris : le seul
    // mouvement d'argent est le paiement de l'abonnement. Un seul opérateur est
    // actif en base (Orange Money), et le délai annoncé par le serveur lui-même
    // est « 30 minutes ouvrables ». Présenter un dépôt/retrait faisait passer
    // PronoWin pour un bookmaker, ce qu'il n'est pas.
    title: "Payez par Orange Money.\nVérifié par un humain.",
    text: "Vous réglez l'abonnement par Orange Money et joignez la preuve du transfert. Un membre de l'équipe la vérifie, puis votre accès Premium s'ouvre.",
    photo: '/images/photo-paiements.svg',
    stats: [
      { value: 'Orange Money', label: 'opérateur accepté' },
      { value: '30 min',       label: 'délai de vérification annoncé' },
      { value: 'Suivi',        label: "depuis l'application" },
    ],
    apercu: [
      { badge: 'green', icone: 'wallet', titre: 'Paiement Orange Money', sous: 'Preuve de transfert jointe' },
      { badge: 'green', icone: 'coins',  titre: 'Vérification',          sous: '30 minutes ouvrables annoncées' },
      { badge: 'dark',  icone: 'shield', titre: 'Accès Premium',         sous: "Ouvert dès l'accord" },
    ],
  },
  {
    icon: 'users',
    bg: 'gray',
    eyebrow: 'Parrainage',
    // « 7 jours VIP offerts / filleul », et une maquette annonçant « 4 filleuls
    // actifs, 28 jours VIP cumulés ». La récompense réelle est de 500 FCFA
    // (REFERRAL_COMMISSION_L1), convertibles en jours Premium ou retirables à
    // partir de 2 000 FCFA. Le site promettait une récompense d'une autre
    // nature, et plus généreuse que celle qui existe.
    title: 'Invitez vos amis.\nCumulez des gains.',
    text: "Chaque filleul qui s'inscrit avec votre code vous rapporte 500 FCFA. Vous les convertissez en jours Premium, ou vous les retirez à partir de 2 000 FCFA.",
    stats: [
      { value: '500 F',   label: 'par filleul inscrit' },
      { value: '2 000 F', label: 'retrait possible à partir de' },
      { value: 'ou VIP',  label: 'convertibles en jours Premium' },
    ],
    apercu: [
      { badge: 'green', icone: 'users', titre: 'Votre code de parrainage', sous: 'Partagé en un geste' },
      { badge: 'gold',  icone: 'crown', titre: 'Récompense',               sous: '500 FCFA par filleul inscrit' },
      { badge: 'dark',  icone: 'users', titre: 'Au choix',                 sous: 'Retrait, ou jours Premium' },
    ],
  },
];

// `bigStats` et `testimonials` sont retirés.
//
// Les trois grands chiffres annonçaient « +50 000 pronostics publiés »,
// « +8 000 parieurs actifs chaque mois » et « 4,6/5 de note moyenne ». La base
// contient 29 pronostics et 6 comptes ; l'application n'est sur aucun store, si
// bien que la note n'avait même pas de source possible.
//
// Les trois témoignages étaient signés de noms et de villes — Kader B. à
// Ouagadougou, Salimata O., Yacouba N. C'est le défaut des actualités
// fabriquées déjà retirées de l'application, à ceci près qu'il est conçu pour
// convaincre : de faux clients qui recommandent le produit.

// Les deux formules qui existent, plus le gratuit. Le site vendait un « VIP
// Hebdo » : ce plan n'existe nulle part dans le backend.
const formules = [
  {
    id: 'free',
    name: 'Gratuit',
    period: 'toujours',
    highlight: false,
    features: [
      'Une sélection de pronostics chaque jour',
      'Actualités et analyses',
      'Statistiques de base par match',
      'Accès aux canaux communautaires',
    ],
    cta: "Télécharger l'app",
  },
  {
    id: 'premium_monthly',
    name: 'Premium Mensuel',
    period: '/ mois',
    highlight: true,
    badge: 'Populaire',
    features: [
      'Tous les pronostics Premium, sans limite',
      'Niveau de confiance en pourcentage',
      'Statistiques avancées et bilan',
      'Sans publicité · support prioritaire',
    ],
    cta: 'Souscrire',
  },
  {
    id: 'premium_annual',
    name: 'Premium Annuel',
    period: '/ an',
    highlight: false,
    features: [
      'Tous les avantages du mensuel',
      'Trois mois économisés sur douze',
      'Historique complet des performances',
      'Tous les tutoriels',
    ],
    cta: 'Souscrire',
  },
];

const comparisonRows = [
  { label: 'Pronostics gratuits du jour',         values: [true,  true,  true] },
  { label: 'Pronostics Premium illimités',        values: [false, true,  true] },
  { label: 'Niveau de confiance en pourcentage',  values: [false, true,  true] },
  { label: 'Statistiques avancées',               values: [false, true,  true] },
  { label: 'Sans publicité',                      values: [false, true,  true] },
  { label: 'Support prioritaire',                 values: [false, true,  true] },
  { label: 'Historique complet des performances', values: [false, false, true] },
  { label: 'Tous les tutoriels',                  values: [false, false, true] },
];

const faqs = [
  {
    q: 'Comment recevoir les pronostics gratuits ?',
    a: "Téléchargez l'application PronoWin et créez un compte avec votre numéro de téléphone. Une sélection de pronostics est visible depuis l'accueil, sans abonnement.",
  },
  {
    q: 'Comment souscrire à un abonnement Premium ?',
    a: "Depuis l'application, rendez-vous dans Abonnements, choisissez la formule mensuelle ou annuelle, payez par Orange Money et joignez la preuve du transfert. L'accès s'ouvre après vérification, annoncée sous 30 minutes ouvrables.",
  },
  {
    q: 'Quels moyens de paiement sont acceptés ?',
    a: "Orange Money. Ce paiement règle l'abonnement à PronoWin : l'application ne tient pas de compte de paris et n'encaisse aucune mise.",
  },
  {
    q: 'PronoWin est-il un site de paris ?',
    a: "Non. PronoWin publie des analyses et des pronostics de football. Les paris se placent chez un opérateur agréé, sous votre seule responsabilité.",
  },
  {
    q: 'Le taux de réussite est-il garanti ?',
    a: "Non. Le pronostic sportif comporte toujours une part d'incertitude. Les taux affichés reflètent des résultats passés, déjà tranchés, et ne garantissent aucun gain futur. Pariez de façon responsable.",
  },
  {
    q: 'Comment fonctionne le parrainage ?',
    a: "Partagez votre code personnel depuis l'application. Chaque filleul qui s'inscrit avec ce code vous rapporte 500 FCFA, que vous convertissez en jours Premium ou retirez à partir de 2 000 FCFA.",
  },
  {
    q: 'Puis-je annuler mon abonnement à tout moment ?',
    a: "Oui. Les abonnements ne sont pas reconduits automatiquement : à chaque échéance, vous choisissez de renouveler ou non.",
  },
];

app.get('/', async (req, res) => {
  const [bilan, tarifs] = await Promise.all([bilanPremium(), tarifsReels()]);

  // Le prix reste `null` quand l'API n'a rien donné : la vue affiche alors la
  // formule sans montant plutôt qu'un montant erroné.
  const pricingPlans = formules.map((f) => ({
    ...f,
    price: f.id === 'free' ? '0' : (tarifs[f.id] ? fcfa(tarifs[f.id]) : null),
  }));

  res.render('index', {
    site, bilan, productBlocks,
    pricingPlans, comparisonRows, faqs,
  });
});

app.get('/mentions-legales', (req, res) => {
  res.render('legal', { site });
});

app.use((req, res) => {
  res.status(404).render('404', { site });
});

// Le serveur ne démarre que si ce fichier est lancé directement. Sans ce
// garde, `require('./server')` depuis le test ouvrirait un port et laisserait
// le processus vivant — un test qui ne rend jamais la main.
if (require.main === module) {
  app.listen(PORT, () => {
    console.log(`PronoWin website running on http://localhost:${PORT}`);
  });
}

module.exports = app;
