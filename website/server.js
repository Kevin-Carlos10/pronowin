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
 * Les montants sont affichés en dollars. Le serveur publie les deux —
 * `price_usd` et `price_fcfa` — et c'est le premier qui est lu. Aucune
 * conversion n'est faite ici : elle aurait demandé un taux de change écrit
 * en dur, qui aurait vieilli sans que personne ne s'en aperçoive.
 *
 * En cas d'échec, aucun montant n'est affiché — la formule reste présentée, le
 * prix renvoie à l'application. Un tarif faux se découvre au moment de payer.
 */
async function tarifsReels() {
  const plans = await lireJson('/subscriptions/plans');
  const par = {};
  if (Array.isArray(plans)) {
    for (const p of plans) {
      if (p && typeof p.price_usd === 'number' && p.price_usd > 0) par[p.id] = p.price_usd;
    }
  }
  return par;
}

/**
 * Version de l'APK réellement publiée, lue au rendu.
 *
 * Le bouton de téléchargement pointe sur un chemin fixe dont le contenu est
 * remplacé à chaque publication. Rien n'indiquait ce qu'il y avait derrière :
 * un fichier à jour et un fichier oublié depuis trois mois donnaient la même
 * page.
 *
 * `apkLatestVersion` est la valeur que le serveur sert déjà à l'application
 * pour déclencher la proposition de mise à jour. La lire ici plutôt que
 * l'écrire garantit que les deux ne divergeront pas.
 *
 * Illisible, on n'affiche rien : un numéro faux vaut moins que pas de numéro.
 */
async function versionApk() {
  const d = await lireJson('/config');
  const v = d && typeof d.apkLatestVersion === 'string' ? d.apkLatestVersion.trim() : '';
  return /^\d+\.\d+/.test(v) ? v : null;
}

/** 54000 → « 54 000 », avec une espace insécable fine. */
function montant(n) {
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
    icon: 'star',
    bg: 'white',
    eyebrow: 'Données du match',
    // Le site ne disait rien de tout cela, alors que c'est le gros du produit :
    // sept onglets sur la fiche d'un match, alimentés par API-Football.
    // Le nombre d'onglets n'est pas annoncé : certains ne s'affichent que si la
    // donnée existe pour ce match, et un compte fixe finirait par mentir.
    title: 'Tout le match.\nAvant le match.',
    text: "Compositions probables, blessures, face-à-face, classements, forme, statistiques, et les cotes de plusieurs bookmakers comparées. Ce que vous ouvriez en dix onglets tient dans une seule fiche.",
    stats: [
      { value: 'Compos',  label: 'et blessures avant le coup d\'envoi' },
      { value: 'H2H',     label: 'historique des confrontations' },
      { value: 'Cotes',   label: 'comparées entre bookmakers' },
    ],
    apercu: [
      { badge: 'green', icone: 'users',  titre: 'Compositions probables', sous: 'Titulaires et remplaçants' },
      { badge: 'green', icone: 'chart',  titre: 'Statistiques du match',  sous: 'Possession, tirs, corners' },
      { badge: 'dark',  icone: 'trophy', titre: 'Classements et forme',   sous: 'Position, série en cours' },
    ],
  },
  {
    icon: 'bell',
    bg: 'black',
    eyebrow: 'En direct',
    // La cadence exacte (une boucle adaptative dans index.ts) n'est pas
    // annoncée : elle dépend du quota de l'API et se règle sans que personne
    // ne pense à rouvrir cette page. Un intervalle affiché ici serait un
    // engagement public recopié à la main — le défaut du « 87 % ».
    title: 'Le score en direct.\nPendant que le match se joue.',
    text: "Tant qu'un match est en cours, les scores se rafraîchissent tout seuls, sans quitter l'écran. Vous êtes prévenu avant le coup d'envoi, puis au résultat.",
    stats: [
      { value: 'Direct',  label: 'les scores pendant le match' },
      { value: 'Continu', label: 'sans rien rafraîchir à la main' },
      { value: 'Alertes', label: 'avant le match et au résultat' },
    ],
    apercu: [
      { badge: 'green', icone: 'ball',  titre: 'Score en direct',       sous: 'Minute par minute' },
      { badge: 'gold',  icone: 'bell',  titre: 'Rappel avant le match', sous: 'Pour ne pas le manquer' },
      { badge: 'dark',  icone: 'check-circle', titre: 'Résultat notifié', sous: 'Dès le coup de sifflet' },
    ],
  },
  {
    icon: 'wallet',
    bg: 'white',
    eyebrow: 'Bankroll',
    // suggestStake() dans bankroll.service.ts : Kelly simplifié, palier de
    // Les pourcentages de mise vivent dans suggestStake() et se règlent là-bas.
    // Les recopier ici les figerait dans une page que personne ne relit.
    // C'est l'inverse d'une
    // martingale — la mise ne monte jamais après une perte, elle suit le solde.
    title: 'Une bankroll tenue\ncomme un professionnel.',
    text: "Vous fixez un budget. À chaque pari, l'application calcule une mise recommandée à partir de votre solde et du niveau de confiance — une fraction, jamais tout. Elle suit ensuite la cote, le gain potentiel et le profit réel.",
    stats: [
      { value: 'Mise',  label: 'calculée, pas devinée' },
      { value: 'Solde',     label: 'mis à jour à chaque pari' },
      { value: 'Profit',    label: 'calculé pari par pari' },
    ],
    apercu: [
      { badge: 'green', icone: 'wallet', titre: 'Budget et solde',    sous: 'Ce qui reste, à tout moment' },
      { badge: 'gold',  icone: 'shield', titre: 'Mise recommandée',   sous: 'Une part de votre solde, pas tout' },
      { badge: 'dark',  icone: 'coins',  titre: 'Profit par pari',    sous: 'Gagné, perdu, en attente' },
    ],
  },
  {
    icon: 'trophy',
    bg: 'black',
    eyebrow: 'Apprendre',
    // Cinq tutoriels réellement en base, trois niveaux, progression suivie
    // (mark_progress). Le classement repose sur les paris tranchés.
    title: 'On ne vous donne pas\nque des pronostics.',
    text: "Du value bet à la gestion de bankroll, des statistiques xG à la psychologie du parieur et aux handicaps asiatiques. Votre progression est enregistrée. Et un classement compare la communauté sur les paris réellement tranchés.",
    stats: [
      { value: '5',      label: 'tutoriels disponibles' },
      { value: '3',      label: 'niveaux, du débutant à l\'avancé' },
      { value: 'Suivi',  label: 'votre progression est gardée' },
    ],
    apercu: [
      { badge: 'green', icone: 'check-circle', titre: 'Comprendre le Value Bet', sous: 'Débutant' },
      { badge: 'gold',  icone: 'chart',        titre: 'Statistiques : xG et pressing', sous: 'Intermédiaire' },
      { badge: 'dark',  icone: 'trophy',       titre: 'Classement de la communauté', sous: 'Taux de réussite et badges' },
    ],
  },
  // Le chapitre « Abonnement » est retiré.
  //
  // Il détaillait la mécanique de paiement : un seul opérateur, une preuve de
  // transfert à joindre, une vérification humaine. Tout était exact — et tout
  // décrivait les limites du système sur la page censée donner envie. Un
  // visiteur qui hésite encore à télécharger n'a pas à apprendre que la
  // validation se fait à la main.
  //
  // Ces informations restent dans la FAQ, où l'on va les chercher quand on se
  // pose la question, et dans l'application au moment de payer.
  {
    icon: 'users',
    bg: 'gray',
    eyebrow: 'Parrainage',
    // Les montants ne sont plus affichés. Ils vivent dans
    // REFERRAL_COMMISSION_L1 et REFERRAL_MIN_WITHDRAWAL, et se règlent là-bas :
    // les recopier ici en ferait une promesse chiffrée, figée dans une page que
    // personne ne relit le jour où le barème change.
    //
    // Un montant précis dessert d'ailleurs l'argument. « 500 F » se compare à
    // ce que promettent les autres ; « des gains à chaque filleul » se compare
    // à rien, et l'utilisateur découvre le barème exact dans l'application,
    // au seul endroit qui le connaisse.
    title: 'Invitez vos amis.\nCumulez des gains.',
    text: "Partagez votre code : chaque filleul qui s'inscrit vous rapporte des gains. À vous de choisir — les convertir en jours Premium, ou les retirer.",
    stats: [
      { value: 'Votre code', label: 'partagé en un geste' },
      { value: 'Des gains',  label: 'à chaque filleul inscrit' },
      { value: 'Au choix',   label: 'retrait, ou jours Premium' },
    ],
    apercu: [
      { badge: 'green', icone: 'users', titre: 'Votre code de parrainage', sous: 'Partagé en un geste' },
      { badge: 'gold',  icone: 'crown', titre: 'Récompense',               sous: 'À chaque filleul inscrit' },
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
    // Le gratuit est bien plus large que ce que le site laissait croire : les
    // donnees du match (compositions, statistiques, classements, blessures,
    // cotes), le direct et la bankroll ne sont derriere aucun paywall — leurs
    // routes n'exigent qu'un compte, pas un abonnement.
    features: [
      'Une sélection de pronostics chaque jour',
      'Compositions, statistiques, classements, blessures',
      'Scores en direct et alertes de match',
      'Bankroll et mise recommandée',
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
      'Statistiques avancées',
      'Tous les tutoriels, niveaux avancés compris',
      'Sans publicité · support prioritaire',
    ],
    cta: 'Souscrire',
  },
  {
    id: 'premium_annual',
    name: 'Premium Annuel',
    period: '/ an',
    highlight: false,
    // L'API donne au mensuel et a l'annuel exactement les memes fonctionnalites.
    // La table comparative reservait pourtant « Historique complet des
    // performances » et « Tous les tutoriels » a l'annuel : deux avantages
    // inventes, sur la page ou l'on choisit combien payer.
    // 54 000 / 6 000 = neuf mois payes pour douze.
    features: [
      'Exactement le même accès que le mensuel',
      'Trois mois économisés sur douze',
      "Un seul paiement pour l'année",
      'Aucune reconduction automatique',
    ],
    cta: 'Souscrire',
  },
];

// Mensuel et annuel ouvrent le meme produit : leurs deux colonnes sont donc
// identiques, et c'est voulu. Un ecart entre elles serait une promesse que le
// backend ne tient pas (cf. le controle « les deux formules Premium ouvrent
// le meme acces »).
const comparisonRows = [
  { label: 'Sélection de pronostics gratuits',      values: [true,  true,  true] },
  { label: 'Compositions, blessures, classements',  values: [true,  true,  true] },
  { label: 'Statistiques et face-à-face du match',  values: [true,  true,  true] },
  { label: 'Scores en direct et alertes',           values: [true,  true,  true] },
  { label: 'Bankroll et mise recommandée',          values: [true,  true,  true] },
  { label: 'Pronostics Premium illimités',          values: [false, true,  true] },
  { label: 'Statistiques avancées',                 values: [false, true,  true] },
  { label: 'Tous les tutoriels, avancés compris',   values: [false, true,  true] },
  { label: 'Sans publicité',                        values: [false, true,  true] },
  { label: 'Support prioritaire',                   values: [false, true,  true] },
];

const faqs = [
  {
    q: 'Comment recevoir les pronostics gratuits ?',
    a: "Téléchargez l'application PronoWin et créez un compte avec votre numéro de téléphone. Une sélection de pronostics est visible depuis l'accueil, sans abonnement.",
  },
  {
    q: 'Comment souscrire à un abonnement Premium ?',
    a: "Depuis l'application, rendez-vous dans Abonnements et choisissez la formule mensuelle ou annuelle. Les moyens de paiement disponibles vous sont proposés à cette étape, et votre accès s'ouvre une fois le règlement vérifié.",
  },
  {
    // La question « quels moyens de paiement sont acceptés ? » est retirée :
    // nommer un opérateur sur la vitrine restreint le produit avant même le
    // téléchargement. Ce qu'elle portait d'essentiel — PronoWin n'encaisse
    // aucune mise — rejoint la question ci-dessous, qui en est le vrai
    // domicile : c'est une clarification sur le métier, pas sur la caisse.
    q: 'PronoWin est-il un site de paris ?',
    a: "Non. PronoWin publie des analyses et des pronostics de football, et n'encaisse aucune mise : l'application ne tient aucun compte de paris. Les paris se placent chez un opérateur agréé, sous votre seule responsabilité.",
  },
  {
    q: 'Le taux de réussite est-il garanti ?',
    a: "Non. Le pronostic sportif comporte toujours une part d'incertitude. Les taux affichés reflètent des résultats passés, déjà tranchés, et ne garantissent aucun gain futur. Pariez de façon responsable.",
  },
  {
    q: 'Comment fonctionne le parrainage ?',
    // Le barème vit dans REFERRAL_COMMISSION_L1 et REFERRAL_MIN_WITHDRAWAL.
    // L'application l'affiche à l'utilisateur, qui le voit donc à jour ; le
    // recopier ici en ferait une seconde source, muette au premier changement.
    a: "Partagez votre code personnel depuis l'application. Chaque filleul qui s'inscrit avec ce code vous rapporte des gains, que vous convertissez en jours Premium ou que vous retirez. Le barème et le seuil de retrait sont affichés dans l'application.",
  },
  {
    q: 'Puis-je annuler mon abonnement à tout moment ?',
    a: "Oui. Les abonnements ne sont pas reconduits automatiquement : à chaque échéance, vous choisissez de renouveler ou non.",
  },
];

app.get('/', async (req, res) => {
  const [bilan, tarifs, versionApp] = await Promise.all([
    bilanPremium(), tarifsReels(), versionApk(),
  ]);

  // Le prix reste `null` quand l'API n'a rien donné : la vue affiche alors la
  // formule sans montant plutôt qu'un montant erroné.
  const pricingPlans = formules.map((f) => ({
    ...f,
    price: f.id === 'free' ? '0' : (tarifs[f.id] ? montant(tarifs[f.id]) : null),
  }));

  res.render('index', {
    site, bilan, productBlocks,
    pricingPlans, comparisonRows, faqs, versionApp,
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
