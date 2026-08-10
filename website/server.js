const express = require('express');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 5000;

app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, 'views'));
app.use(express.static(path.join(__dirname, 'public')));

const site = {
  name: 'PronoWin',
  tagline: 'Des pronostics gagnants, des gains grandissants',
  year: new Date().getFullYear(),
};

const stats = [
  { value: '12', suffix: '', label: 'ligues couvertes' },
  { value: '87', suffix: '%', label: 'de taux de réussite VIP' },
  { value: '4', suffix: '', label: 'pronostics publiés / jour' },
];

// Chapitres de fonctionnalités (style "product page" : un écran par fonctionnalité)
const productBlocks = [
  {
    icon: 'chart',
    bg: 'black',
    eyebrow: 'Pronostics',
    title: 'Analysés chaque jour.\nGagnés plus souvent.',
    text: 'Football, basketball et tennis : nos analystes publient chaque jour des pronostics avec cotes, statistiques et niveau de confiance pour chaque match.',
    photo: '/images/photo-pronostics.svg',
    stats: [
      { value: '12+', label: 'ligues couvertes' },
      { value: '4', label: 'pronostics publiés / jour' },
      { value: '3', label: 'sports couverts' },
    ],
  },
  {
    icon: 'crown',
    bg: 'white',
    eyebrow: 'VIP Premium',
    title: 'Le niveau au-dessus.\nDes combinés qui comptent.',
    text: "Débloquez les combinés à forte cote et les pronostics à haute confiance, sélectionnés parmi les meilleures opportunités du jour par notre équipe.",
    stats: [
      { value: '87%', label: 'de réussite VIP (30 jours)' },
      { value: '6.40', label: 'cote moyenne du combiné du jour' },
      { value: '24/7', label: 'accès depuis l\'application' },
    ],
  },
  {
    icon: 'wallet',
    bg: 'black',
    eyebrow: 'Paiements',
    title: 'Dépôt et retrait.\nEn quelques minutes.',
    text: 'Rechargez votre abonnement ou retirez vos gains via Orange Money, Moov Money ou MTN MoMo, avec confirmation suivie en temps réel.',
    photo: '/images/photo-paiements.svg',
    stats: [
      { value: '3', label: 'opérateurs Mobile Money' },
      { value: '2 min', label: 'délai moyen de confirmation' },
      { value: '100%', label: 'suivi depuis l\'application' },
    ],
  },
  {
    icon: 'users',
    bg: 'gray',
    eyebrow: 'Parrainage',
    title: 'Invitez vos amis.\nGagnez du VIP offert.',
    text: 'Partagez votre code de parrainage et recevez des jours d\'abonnement Premium offerts pour chaque ami qui rejoint PronoWin.',
    stats: [
      { value: '7', label: 'jours VIP offerts / filleul' },
      { value: '∞', label: 'nombre de filleuls' },
      { value: '1 clic', label: 'pour partager votre code' },
    ],
  },
];

const bigStats = [
  { value: '+50 000', label: 'pronostics publiés depuis le lancement' },
  { value: '+8 000', label: 'parieurs actifs chaque mois' },
  { value: '4,6/5', label: 'note moyenne des utilisateurs' },
];

const testimonials = [
  {
    text: "PronoWin m'aide à structurer mes paris. Les analyses sont claires et les cotes bien expliquées, même pour un débutant.",
    author: 'Kader B.',
    role: 'Parieur amateur, Ouagadougou',
  },
  {
    text: "L'abonnement VIP mensuel est vite rentabilisé. Je suis les pronostics chaque matin avant de placer mes mises.",
    author: 'Salimata O.',
    role: 'Abonnée VIP Mensuel',
  },
  {
    text: "Le support répond vite sur WhatsApp et le retrait de mes gains via Mobile Money a toujours été fluide.",
    author: 'Yacouba N.',
    role: 'Utilisateur Premium',
  },
];

const pricingPlans = [
  {
    name: 'Gratuit',
    price: '0',
    period: 'toujours',
    highlight: false,
    features: [
      "Pronostics du jour (sélection publique)",
      'Actualités et analyses des grandes ligues',
      'Statistiques de base par match',
      "Accès à la communauté et au classement",
    ],
    cta: 'Télécharger l\'app',
  },
  {
    name: 'VIP Hebdo',
    price: '2 500',
    period: '/ semaine',
    highlight: true,
    badge: 'Populaire',
    features: [
      'Tous les pronostics VIP de la semaine',
      'Combinés à forte cote',
      'Niveau de confiance détaillé par pari',
      'Support prioritaire',
    ],
    cta: 'Souscrire',
  },
  {
    name: 'VIP Mensuel',
    price: '8 000',
    period: '/ mois',
    highlight: false,
    features: [
      'Tous les avantages VIP Hebdo',
      "2 mois du prix pour l'équivalent de 4 semaines",
      'Accès prioritaire aux nouveaux tutoriels',
      'Historique complet des performances',
    ],
    cta: 'Souscrire',
  },
];

const comparisonRows = [
  { label: 'Pronostics gratuits du jour', values: [true, true, true] },
  { label: 'Pronostics VIP illimités', values: [false, true, true] },
  { label: 'Combinés à forte cote', values: [false, true, true] },
  { label: 'Niveau de confiance détaillé', values: [false, true, true] },
  { label: 'Support prioritaire', values: [false, true, true] },
  { label: 'Historique complet des performances', values: [false, false, true] },
  { label: 'Accès prioritaire aux tutoriels', values: [false, false, true] },
];

const faqs = [
  {
    q: 'Comment recevoir les pronostics gratuits ?',
    a: "Téléchargez l'application PronoWin et créez un compte avec votre numéro de téléphone. Les pronostics gratuits du jour sont visibles directement depuis l'accueil, sans abonnement.",
  },
  {
    q: "Comment souscrire à un abonnement Premium ?",
    a: "Depuis l'application, rendez-vous dans la section Abonnements, choisissez une formule (Hebdo ou Mensuel) et payez par Orange Money, Moov Money ou MTN MoMo. L'accès VIP est activé après confirmation du paiement.",
  },
  {
    q: 'Quels moyens de paiement sont acceptés ?',
    a: 'PronoWin accepte les paiements Mobile Money (Orange Money, Moov Money, MTN MoMo). Les retraits de gains suivent le même circuit.',
  },
  {
    q: 'Le taux de réussite est-il garanti ?',
    a: "Non. Le pronostic sportif comporte toujours une part d'incertitude. Nos taux affichés reflètent les performances historiques de nos analystes, pas une garantie de gain futur. Pariez de façon responsable.",
  },
  {
    q: 'Comment fonctionne le parrainage ?',
    a: "Partagez votre code personnel depuis l'application. Quand un filleul crée un compte et l'utilise, vous recevez des jours d'abonnement Premium offerts.",
  },
  {
    q: 'Puis-je annuler mon abonnement à tout moment ?',
    a: "Oui, les abonnements Hebdo et Mensuel ne sont pas reconduits automatiquement : vous choisissez de renouveler ou non à chaque échéance.",
  },
];

app.get('/', (req, res) => {
  res.render('index', { site, stats, productBlocks, bigStats, testimonials, pricingPlans, comparisonRows, faqs });
});

app.get('/mentions-legales', (req, res) => {
  res.render('legal', { site });
});

app.use((req, res) => {
  res.status(404).render('404', { site });
});

app.listen(PORT, () => {
  console.log(`PronoWin website running on http://localhost:${PORT}`);
});
