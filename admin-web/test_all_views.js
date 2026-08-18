/**
 * Test EJS compilation — toutes les vues du panel admin
 * node test_all_views.js
 */
const ejs  = require('ejs');
const path = require('path');

const base = {
  isMain: true,
  adminName: 'Carlos', adminRole: 'superadmin', adminUsername: 'carlos',
  hasPerm: () => true,
  relTime: () => 'il y a 5min',
  success: null, error: null,
};

// Les `icon:` doivent rester des identifiants du sprite (views/_icons.ejs),
// comme dans server.js : les vues les injectent dans <use href="#ic-...">.
// _check_icons.js vérifie que ces valeurs correspondent bien à un symbole.
const SEGMENTS = [
  { key: 'all',         label: 'Tous',     icon: 'users',   desc: 'Tout le monde' },
  { key: 'premium',     label: 'Premium',  icon: 'crown',   desc: 'Abonnés' },
  { key: 'free',        label: 'Gratuit',  icon: 'user',    desc: 'Non-abonnés' },
  { key: 'active_30',   label: 'Actifs',   icon: 'dot',     desc: '< 30j' },
  { key: 'inactive_30', label: 'Inactifs', icon: 'sleep',   desc: '> 30j' },
  { key: 'new_7',       label: 'Nouveaux', icon: 'sparkle', desc: '< 7j' },
];

// Le vrai catalogue, pas une copie : le stub local n'avait qu'une entrée et pas
// de clé `icon`, si bien que neuf libellés sur dix n'étaient jamais rendus.
const { PERMISSIONS } = require('./lib/permissions');

const { ACTION_LABELS } = require('./lib/action_labels');

const TUT_CATEGORIES = ['bases', 'valuebet', 'bankroll', 'strategie'];
const TUT_LEVELS     = ['beginner', 'intermediate', 'advanced'];

const now = new Date().toISOString();

const fakeUser = {
  id: 'u1', pseudo: 'JohnDoe', phoneNumber: '0701234567', email: 'john@ex.com',
  isPremium: true, isBanned: false, isActive: true, createdAt: now,
  balance: 25000, referralCount: 3, referralEarnings: 5000,
  premiumExpiresAt: new Date(Date.now() + 86400000 * 15).toISOString(),
};

const fakeTx = {
  id: 'tx1', type: 'withdrawal', amount: 25000, status: 'completed',
  paymentMethod: 'orange_money', xbetId: 'XB123', senderPhone: '070',
  adminNote: 'OK', createdAt: now, processedAt: now,
  user: { id: 'u1', pseudo: 'JohnDoe', phoneNumber: '070' },
};

const fakeLog = {
  id: 'l1', timestamp: now, adminName: 'Carlos', adminUsername: 'carlos',
  action: 'user_banned', target: 'JohnDoe', meta: {}, ip: '127.0.0.1',
};

const fakePro = {
  id: 'm1', matchId: 'm1', homeTeam: 'PSG', awayTeam: 'OM',
  homeLogoUrl: '', awayLogoUrl: '', league: 'Ligue 1', matchDate: now,
  tip: '1', odds: 1.85, stars: 4, label: 'Victoire PSG',
  is_published: true, isPremium: false, type: 'winner',
  pronostic: { tip: '1', odds: 1.85, stars: 4, label: 'V PSG', isPremium: false, type: 'winner', is_published: true },
  createdAt: now, updatedAt: now,
};

const fakeTut = {
  id: 't1', title: 'Tuto 1', authorName: 'Expert', category: 'valuebet',
  level: 'beginner', durationSeconds: 600, thumbnailUrl: '', videoUrl: '',
  isPremium: false, viewCount: 120, rating: 4.2, ratingCount: 15,
  description: 'Description.', createdAt: now, updatedAt: now,
};

const fakeSub = {
  id: 's1', name: 'Jean Dupont', username: 'jean', isActive: true,
  createdAt: now, lastLoginAt: now, permissions: ['users:read'],
};

const fakeArt = {
  id: 'a1', title: 'Test article', slug: 'test-article', summary: 'Résumé',
  content: '<p>Contenu</p>', category: 'news', imageUrl: '',
  isPublished: true, isPinned: false, isPremiumOnly: false,
  authorName: 'Carlos', viewCount: 42, likeCount: 5,
  createdAt: now, updatedAt: now, publishedAt: now,
};

const notifHistory = [{
  title: 'Test notif', body: 'Contenu test', segment: 'all',
  segLabel: 'Tous', sent: 500, adminName: 'Carlos', sentAt: now,
}];
const histStats = { total: 1, totalSent: 500, thisWeek: 1, thisMonth: 1 };

// Versements de gains de parrainage : les compteurs de dépôts ont disparu
// avec le portefeuille dépôt/retrait.
const txStats = {
  total_withdrawals: 57, completed_withdrawals: 15, rejected_withdrawals: 4,
  volume_withdrawals: 320000, pending_count: 3, pending_volume: 45000,
  today_withdrawals: 2, monthly_volume: 1200000,
};

const userStats = {
  total: 1200, premium: 342, banned: 15, active: 980, newWeek: 45,
  suspended: 5, newToday: 3, newMonth: 120, conversion_rate: 28.5,
};

// ── Toutes les vues à tester ───────────────────────────────────────────────────
const views = [

  // ── Connexion ──
  // La page la plus exposée du panel — le seul écran atteignable sans compte —
  // n'avait aucun cas de test. Ses quatre états se dessinent différemment :
  // formulaire nu, échec avec jauge de tentatives, session expirée, blocage.
  ['login (nominal)', 'login', {
    error: null, expired: false, locked: null,
    remaining: 5, maxAttempts: 5, blockedUntilMs: null, username: '',
  }],
  ['login (session expirée)', 'login', {
    error: null, expired: true, locked: null,
    remaining: 5, maxAttempts: 5, blockedUntilMs: null, username: '',
  }],
  ['login (échec, jauge)', 'login', {
    error: 'Identifiants incorrects.', expired: false, locked: null,
    remaining: 2, maxAttempts: 5, blockedUntilMs: null, username: 'carlos',
  }],
  ['login (bloqué)', 'login', {
    error: null, expired: false,
    locked: 'Trop de tentatives. Réessayez dans 12 minutes.',
    remaining: 0, maxAttempts: 5, blockedUntilMs: Date.now() + 12 * 60000, username: 'carlos',
  }],

  // ── Dashboard ──
  ['dashboard', 'dashboard', {
    ...base, page: 'dashboard',
    stats: { totalUsers: 1200, premiumUsers: 342, activeToday: 87, pendingTx: 5, todayDeposits: 12, todayWithdrawals: 3, totalRevenue: 850000, monthRevenue: 120000, newUsersWeek: 45 },
    pending: { data: [fakeTx], total: 5 },
    proofs:  { data: [], total: 0 },
    activeBansCount: 2,
    recentBans: [],
    recentLogs: [fakeLog],
  }],

  // ── Utilisateurs ──
  ['users (liste)', 'users', {
    ...base, page: 'users',
    data: [fakeUser], stats: userStats,
    total: 1200, page: 1, perPage: 20, totalPages: 60,
    search: '', plan: '', status: '', sortBy: 'createdAt',
    date_from: '', date_to: '', min_tx: '',
    activeBanIds: [],
  }],
  ['users (vide + filtres)', 'users', {
    ...base, page: 'users',
    data: [], stats: userStats,
    total: 0, page: 1, perPage: 20, totalPages: 0,
    search: 'xyz', plan: 'premium', status: 'active', sortBy: 'createdAt',
    date_from: '2024-01-01', date_to: '2024-12-31', min_tx: '5',
    activeBanIds: [],
  }],

  // ── Détail utilisateur ──
  ['user_detail (normal)', 'user_detail', {
    ...base, page: 'users',
    user: fakeUser,
    transactions: [fakeTx],
    subscriptions: [],
    proofs: [],
    referrals: [],
    activeBan: null,
  }],
  ['user_detail (banni)', 'user_detail', {
    ...base, page: 'users',
    user: { ...fakeUser, isBanned: true },
    transactions: [],
    subscriptions: [],
    proofs: [],
    referrals: [],
    activeBan: { reason: 'Fraude', bannedAt: now, bannedBy: 'Carlos', expiresAt: null, active: true, userId: 'u1' },
  }],

  // ── Pronostics ──
  ['pronostics (liste)', 'pronostics', {
    ...base, page: 'pronostics',
    matches: [fakePro], statusFilter: '',
    competition: '', totalMatchs: 3197,
    // Deux « Serie A » : le sélecteur doit les distinguer par le pays, et
    // retomber sur le code quand l'API ne l'a pas fourni.
    visibleLeagues: [
      { leagueCode: 'SA',      league: 'Serie A',        leagueCountry: 'Italy',  isVisible: true },
      { leagueCode: 'AF_71',   league: 'Serie A',        leagueCountry: null,     isVisible: true },
      { leagueCode: 'PL',      league: 'Premier League', leagueCountry: 'England', isVisible: true },
    ],
  }],
  ['pronostics (vide)', 'pronostics', {
    ...base, page: 'pronostics',
    matches: [], statusFilter: 'published',
    competition: 'Ligue 1',
  }],

  // Confirmation après publication, puis après enregistrement d'un brouillon.
  // Les deux redirigeaient au même endroit et annonçaient « publié ».
  ['pronostics (publié)', 'pronostics', {
    ...base, page: 'pronostics',
    matches: [fakePro], statusFilter: '', competition: '', success: true,
    flash: { ok: 'publie', match: 'Sevilla – Rayo Vallecano', tip: 'Plus de 0.5' },
  }],
  ['pronostics (brouillon)', 'pronostics', {
    ...base, page: 'pronostics',
    matches: [fakePro], statusFilter: '', competition: '', success: false,
    flash: { ok: 'brouillon', match: "L'Équipe A – Équipe B", tip: 'Moins de 2.5' },
  }],

  // ── Pronostic form ──
  ['pronostic_form (edit)', 'pronostic_form', {
    ...base, page: 'pronostics',
    match: fakePro,
  }],
  ['pronostic_form (sans prono)', 'pronostic_form', {
    ...base, page: 'pronostics',
    match: { ...fakePro, pronostic: null },
  }],

  // ── Abonnements / Preuves Premium ──
  ['abonnements (2 preuves)', 'abonnements', {
    ...base, page: 'abonnements', success: false,
    data: { total: 2, promo_code: 'PRONOWIN2025', data: [
      { id:'p1', type:'payment_screenshot', amount:15000, senderPhone:'+22670000001',
        screenshotUrl:'https://x/a.jpg', planId:'premium_monthly',
        createdAt: new Date(Date.now() - 5*3600e3).toISOString(),
        user:{ pseudo:'Parieur_NV8VJ', phoneNumber:'+22670000001' } },
      // 4 jours d'attente : doit ressortir en rouge et passer en tête de file.
      { id:'p2', type:'xbet_account_screenshot', amount:10500, senderPhone:'+22670000002',
        platform:'1xbet', xbetId:'1XB99881', screenshotUrl:null, paymentScreenshotUrl:null,
        planId:'premium_annual',
        createdAt: new Date(Date.now() - 4*86400e3).toISOString(),
        user:{ pseudo:'Parieur_5TQQC', phoneNumber:'+22670000002' } },
    ]},
  }],
  ['abonnements (file vide)', 'abonnements', {
    ...base, page: 'abonnements', success: false, data: { total: 0, data: [] },
  }],
  // Les écrans que l'admin voit le plus souvent — file vide expliquée, et
  // l'historique des décisions, qui n'existait pas du tout auparavant.
  ['abonnements (vide — rien jamais soumis)', 'abonnements', {
    ...base, page: 'abonnements', success: false, data: { total: 0, data: [] },
    statut: 'pending', recherche: '',
    contexte: { en_attente:0, approuvees:0, rejetees:0, total:0, revenu_approuve:0,
                derniere_decision:null, delai_moyen_h:null, delai_echantillon:0 },
  }],
  ['abonnements (vide — tout traité)', 'abonnements', {
    ...base, page: 'abonnements', success: false, data: { total: 0, data: [] },
    statut: 'pending', recherche: '',
    contexte: { en_attente:0, approuvees:14, rejetees:3, total:17, revenu_approuve:210000,
                derniere_decision: new Date(Date.now() - 2*3600e3).toISOString(),
                delai_moyen_h:4.2, delai_echantillon:17 },
  }],
  ['abonnements (recherche infructueuse)', 'abonnements', {
    ...base, page: 'abonnements', success: false, data: { total: 0, data: [] },
    statut: 'approved', recherche: 'Zoubida',
    contexte: { en_attente:2, approuvees:14, rejetees:3, total:19, revenu_approuve:210000,
                derniere_decision: new Date().toISOString(), delai_moyen_h:4.2, delai_echantillon:17 },
  }],
  // Produit croise statut x contexte. Le cas « onglet historique + contexte
  // absent » manquait, et c'est exactement celui qui a plante en production :
  // l'API tournait encore sans les compteurs, la vue les lisait sans garde.
  ...['pending', 'approved', 'rejected', 'all'].flatMap(st => [
    [`abonnements (${st} — sans contexte)`, 'abonnements', {
      ...base, page: 'abonnements', success: false,
      data: { total: 0, data: [] }, statut: st, recherche: '', contexte: null,
    }],
    [`abonnements (${st} — recherche vide, sans contexte)`, 'abonnements', {
      ...base, page: 'abonnements', success: false,
      data: { total: 0, data: [] }, statut: st, recherche: 'Zoubida', contexte: null,
    }],
  ]),
  ['abonnements (historique)', 'abonnements', {
    ...base, page: 'abonnements', success: false,
    statut: 'all', recherche: '',
    contexte: { en_attente:1, approuvees:2, rejetees:1, total:4, revenu_approuve:25500,
                derniere_decision: new Date(Date.now() - 3600e3).toISOString(),
                delai_moyen_h:0.4, delai_echantillon:3 },
    data: { total: 3, promo_code: 'PRONOWIN2025', data: [
      { id:'h1', type:'payment_screenshot', status:'approved', amount:15000,
        screenshotUrl:'https://x/a.jpg', adminNote:'Reçu sur MobCash, OK.',
        createdAt: new Date(Date.now() - 26*3600e3).toISOString(),
        reviewedAt: new Date(Date.now() - 2*3600e3).toISOString(),
        user:{ pseudo:'Parieur_NV8VJ', phoneNumber:'+22670000001' } },
      { id:'h2', type:'xbet_account_screenshot', status:'rejected', amount:10500,
        screenshotUrl:null, adminNote:null,
        createdAt: new Date(Date.now() - 5*3600e3).toISOString(),
        reviewedAt: new Date(Date.now() - 4.5*3600e3).toISOString(),
        user:{ pseudo:'Parieur_5TQQC', phoneNumber:'+22670000002' } },
      // Sans date de revue : la colonne doit rester lisible, pas afficher NaN.
      { id:'h3', type:'payment_screenshot', status:'approved', amount:null,
        screenshotUrl:'https://x/c.jpg', adminNote:'Régularisation manuelle.',
        createdAt: new Date(Date.now() - 90*3600e3).toISOString(), reviewedAt:null,
        user:{ pseudo:'Parieur_ZZZ', phoneNumber:null } },
    ]},
  }],

  // ── Bankroll ──
  ['bankroll (avec données)', 'bankroll', {
    ...base, page: 'bankroll',
    data: [
      { user_id:'u1', pseudo:'Parieur_9CSPX', phone_number:'+198494909', email:null,
        total_budget:1000000, current_balance:1000000, currency:'XOF',
        total_bets:0, pending_bets:0, wins:0, losses:0, win_rate:null,
        total_profit:0, roi:null, created_at:now },
      { user_id:'u2', pseudo:'Parieur_NV8VJ', phone_number:null, email:'a@b.c',
        total_budget:1000000, current_balance:921500, currency:'XOF',
        total_bets:2, pending_bets:1, wins:0, losses:2, win_rate:0,
        total_profit:-78500, roi:-100, created_at:now },
    ],
    stats: { bankrolls:2, total_budget:2000000, total_balance:1921500, total_bets:2,
             pending_bets:1, wins:0, losses:2, win_rate:0, total_profit:-78500, roi:-100 },
    total:2, page:1, per_page:20, total_pages:1, search:'', sortBy:'currentBalance', sortDir:'desc',
  }],
  ['bankroll (vide)', 'bankroll', {
    ...base, page: 'bankroll', data: [], stats: null,
    total:0, page:1, per_page:20, total_pages:0, search:'', sortBy:'currentBalance', sortDir:'desc',
  }],
  ['bankroll (stats indispo)', 'bankroll', {
    ...base, page: 'bankroll', data: [], stats: null, error: 'Export impossible',
    total:0, page:1, per_page:20, total_pages:0, search:'zz', sortBy:'currentBalance', sortDir:'desc',
  }],

  // ── Statistiques (page entièrement pilotée en JS : rien d'autre à injecter) ──
  ['statistiques', 'statistiques', { ...base, page: 'statistiques' }],

  // ── Ligues ──
  ['leagues (mixte)', 'leagues', {
    ...base, page: 'leagues',
    leagues: [
      { leagueCode: 'BL1',    league: 'Bundesliga',            leagueLogo: 'https://x/bl1.png', isVisible: true,  matchCount: 61, upcomingCount: 9 },
      { leagueCode: 'PD',     league: 'La Liga',               leagueLogo: null,                isVisible: true,  matchCount: 58, upcomingCount: 10 },
      { leagueCode: 'AF_262', league: 'Liga MX',               leagueLogo: 'https://x/mx.png',  isVisible: false, matchCount: 74, upcomingCount: 12 },
      // Hors saison : beaucoup d'historique, plus rien à venir.
      { leagueCode: 'AF_253', league: 'Major League Soccer',   leagueLogo: null,                isVisible: false, matchCount: 120, upcomingCount: 0 },
      // Ligue configurée sans match dans la fenêtre de 60 j.
      { leagueCode: 'AF_999', league: 'Coupe test',            leagueLogo: null,                isVisible: false },
    ],
  }],
  ['leagues (vide)', 'leagues', { ...base, page: 'leagues', leagues: [] }],
  ['leagues (erreur API)', 'leagues', { ...base, page: 'leagues', leagues: [], error: 'Backend injoignable' }],

  // ── Sous-admins ──
  ['sub_admins', 'sub_admins', {
    ...base, page: 'sub-admins',
    subs: [fakeSub],
    recentLogsBySub: { 'Jean Dupont': [fakeLog] },
    PERMISSIONS, ACTION_LABELS,
  }],
  ['sub_admins (vide)', 'sub_admins', {
    ...base, page: 'sub-admins',
    subs: [], recentLogsBySub: {}, PERMISSIONS, ACTION_LABELS,
  }],
  // Noms hostiles. L'apostrophe est le cas courant (N'Diaye, L'Hermitte) et
  // cassait les trois boutons de la carte ; « </script> » sortait du bloc
  // JavaScript. Les deux passaient inapercus : la vue rendait sans erreur.
  ['sub_admins (noms hostiles)', 'sub_admins', {
    ...base, page: 'sub-admins', PERMISSIONS, ACTION_LABELS,
    subs: [
      { id:'h1', name:"N'Diaye", username:'ndiaye', isActive:true,
        permissions:['pronostics:read'], createdAt:new Date().toISOString(), lastLoginAt:null },
      { id:'h2', name:'X</script><b>injecte</b>', username:'x', isActive:false,
        permissions:[], createdAt:new Date().toISOString(), lastLoginAt:null },
      { id:'h3', name:'Guillemets " et \ antislash', username:'g', isActive:true,
        permissions:['users:delete'], createdAt:new Date().toISOString(), lastLoginAt:null },
    ],
    recentLogsBySub: {},
  }],
  // Catalogue d'actions : la vue en tenait une copie de 9 entrees sur 43, et
  // « logout » s'affichait en anglais brut.
  ['sub_admins (journal traduit)', 'sub_admins', {
    ...base, page: 'sub-admins', PERMISSIONS, ACTION_LABELS,
    subs: [fakeSub],
    recentLogsBySub: { 'Jean Dupont': [
      { action:'logout',            target:'Jean Dupont', timestamp:new Date().toISOString() },
      { action:'proof_approved',    target:'Preuve #42',  timestamp:new Date().toISOString() },
      { action:'action_inconnue_x', target:'',            timestamp:new Date().toISOString() },
    ] },
  }],

  // ── Audit ──
  ['audit (avec données)', 'audit', {
    ...base, page: 'audit',
    data: [fakeLog], total: 1, page: 1, perPage: 30, totalPages: 1,
    ACTION_LABELS,
    filters: { action: '', admin: '', cat: '', date: '' },
    chartDays: ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'],
    chartCounts: [3, 5, 2, 8, 1, 4, 6],
    catCounts: { user_banned: 2, notification_sent: 1 },
    adminCounts: { Carlos: 3 },
    adminList: ['Carlos'],
    totalAll: 10,
  }],
  ['audit (filtré)', 'audit', {
    ...base, page: 'audit',
    data: [], total: 0, page: 1, perPage: 30, totalPages: 0,
    ACTION_LABELS,
    filters: { action: 'user_banned', admin: 'Carlos', cat: 'users', date: '2024-01-01' },
    chartDays: [], chartCounts: [],
    catCounts: {}, adminCounts: {}, adminList: ['Carlos'], totalAll: 0,
  }],

  // ── Tutoriels ──
  // categories/levels viennent de fetchTutorialCategories/Levels côté serveur ;
  // les 6 res.render() réels les passent toujours, y compris sur le chemin d'erreur.
  ['tutoriels (liste)', 'tutoriels', {
    ...base, page: 'tutoriels',
    data: [fakeTut], total: 1, page: 1, perPage: 12, totalPages: 1,
    search: '', category: '', level: '', categories: TUT_CATEGORIES, levels: TUT_LEVELS,
    stats: { total: 1, premium: 0, free: 1, beginner: 1, intermediate: 0, advanced: 0 },
  }],
  ['tutoriels (vide)', 'tutoriels', {
    ...base, page: 'tutoriels',
    data: [], total: 0, page: 1, perPage: 12, totalPages: 0,
    search: 'xyz', category: 'valuebet', level: 'advanced',
    categories: TUT_CATEGORIES, levels: TUT_LEVELS,
    stats: { total: 0, premium: 0, free: 0, beginner: 0, intermediate: 0, advanced: 0 },
  }],

  // ── Tutoriel form ──
  ['tutoriel_form (new)', 'tutoriel_form', {
    ...base, page: 'tutoriels', tutorial: null,
    categories: TUT_CATEGORIES, levels: TUT_LEVELS,
  }],
  ['tutoriel_form (edit)', 'tutoriel_form', {
    ...base, page: 'tutoriels', tutorial: fakeTut,
    categories: TUT_CATEGORIES, levels: TUT_LEVELS,
  }],

  // ── Profil ──
  ['profile (superadmin)', 'profile', {
    ...base, page: 'profile',
    adminPerms: [],
    sub: null,
    lastLogins: [fakeLog],
    recentActivity: [fakeLog],
    statsMe: { total: 42, week: 5, today: 1, logins: 3 },
    currentIp: '127.0.0.1',
    PERMISSIONS,
    ACTION_LABELS,
  }],
  ['profile (sub-admin)', 'profile', {
    ...base, page: 'profile', isMain: false, adminRole: 'sub',
    adminPerms: ['users:read'],
    sub: fakeSub,
    lastLogins: [],
    recentActivity: [],
    statsMe: { total: 5, week: 2, today: 0, logins: 1 },
    currentIp: '192.168.1.1',
    PERMISSIONS,
    ACTION_LABELS,
  }],

  // ── Versements en attente ──
  // Écran d'argent : un administrateur y déclenche le paiement d'un parrain.
  // Il n'avait aucun cas de test.
  ['transactions (en attente)', 'transactions', {
    ...base, page: 'transactions',
    data: { data: [{ ...fakeTx, status: 'pending', processedAt: null }], total: 1 },
    search: '', method: '', methods: ['orange_money', 'moov_money', 'mtn_momo'],
    page: 1, totalPages: 1,
    localStats: { totalAmount: 25000, total: 1 },
  }],
  ['transactions (vide + filtre)', 'transactions', {
    ...base, page: 'transactions',
    data: { data: [], total: 0 },
    search: 'John', method: 'orange_money', methods: ['orange_money'],
    page: 1, totalPages: 1,
    localStats: { totalAmount: 0, total: 0 },
  }],
  // File vide SANS filtre : le cas que voit un administrateur au quotidien, et
  // le seul qui manquait. Une page vide sans explication se lit comme une page
  // en panne ; les trois branches ci-dessous sont les trois diagnostics.
  ...[
    ['aucun gain',    { parrains_avec_gains: 0, parrains_eligibles: 0, total_gains: 0,     seuil_retrait: 2000 }],
    ['sous le seuil', { parrains_avec_gains: 3, parrains_eligibles: 0, total_gains: 1750,  seuil_retrait: 2000 }],
    ['eligibles',     { parrains_avec_gains: 5, parrains_eligibles: 2, total_gains: 12400, seuil_retrait: 2000 }],
    ['contexte absent', null],
  ].map(([nom, contexte]) => [`transactions (vide — ${nom})`, 'transactions', {
    ...base, page: 'transactions',
    data: { data: [], total: 0 },
    contexte,
    search: '', method: '', methods: ['orange_money'],
    page: 1, totalPages: 1,
    localStats: { totalAmount: 0, total: 0 },
  }]),

  // ── Méthodes de paiement ──
  ['paiements (liste)', 'paiements', {
    ...base, page: 'paiements',
    methodes: [
      { id: 'a1', key: 'orange_money', label: 'Orange Money', phone: '22645568158', isActive: true,  sortOrder: 0 },
      { id: 'a2', key: 'moov_money',   label: 'Moov Money',   phone: '22660012181', isActive: false, sortOrder: 1 },
    ],
    erreur: null,
  }],
  ['paiements (vide)', 'paiements', {
    ...base, page: 'paiements', methodes: [], erreur: null,
  }],
  ['paiements (API muette)', 'paiements', {
    ...base, page: 'paiements', methodes: null, erreur: 'connect ECONNREFUSED',
  }],

  // ── Historique ──
  ['historique (avec données)', 'historique', {
    ...base, page: 'historique',
    data: [fakeTx], total: 1, page: 1, perPage: 20, totalPages: 1,
    search: '', status: '', method: '',
    dateFrom: '', dateTo: '', amount_min: '', amount_max: '', sortBy: 'date',
    stats: txStats,
  }],
  ['historique (vide + filtres)', 'historique', {
    ...base, page: 'historique',
    data: [], total: 0, page: 1, perPage: 20, totalPages: 0,
    search: 'John', status: 'completed', method: 'orange_money',
    dateFrom: '2024-01-01', dateTo: '2024-12-31', amount_min: '1000', amount_max: '50000', sortBy: 'amount',
    stats: txStats,
  }],

  // ── Actualités ──
  ['actualites (liste)', 'actualites', {
    ...base, page: 'actualites',
    data: [fakeArt], total: 1, page: 1, perPage: 12, totalPages: 1,
    search: '', category: '', status: '',
    stats: { total: 1, published: 1, draft: 0, pinned: 0, premium: 0, totalViews: 42 },
  }],
  ['actualites (vide)', 'actualites', {
    ...base, page: 'actualites',
    data: [], total: 0, page: 1, perPage: 12, totalPages: 0,
    search: 'xyz', category: 'promo', status: 'published',
    stats: { total: 0, published: 0, draft: 0, pinned: 0, premium: 0, totalViews: 0 },
  }],
  ['actualite_form (new)', 'actualite_form', {
    ...base, page: 'actualites', article: null, isEdit: false,
  }],
  ['actualite_form (edit)', 'actualite_form', {
    ...base, page: 'actualites', article: fakeArt, isEdit: true,
  }],

  // ── Notifications ──
  ['notifications (avec historique)', 'notifications', {
    ...base, page: 'notifications',
    SEGMENTS, history: notifHistory, histStats, searchH: '',
  }],
  ['notifications (vide)', 'notifications', {
    ...base, page: 'notifications',
    SEGMENTS, history: [],
    histStats: { total: 0, totalSent: 0, thisWeek: 0, thisMonth: 0 },
    searchH: '',
  }],
  ['notifications (recherche)', 'notifications', {
    ...base, page: 'notifications',
    SEGMENTS, history: notifHistory, histStats, searchH: 'test',
  }],

  // ── Bannissements ──
  ['bans (actifs)', 'bans', {
    ...base, page: 'bans',
    bans: [
      { id: 'b1', userId: 'u1', pseudo: 'TricheUser', reason: 'Fraude avérée', durationDays: 30,
        bannedAt: new Date(Date.now()-86400000*3).toISOString(), bannedBy: 'Carlos',
        bannedIp: '127.0.0.1', expiresAt: new Date(Date.now()+86400000*27).toISOString(),
        active: true, unbannedAt: null, unbannedBy: null, unbanReason: null },
      { id: 'b2', userId: 'u2', pseudo: 'SpamBot', reason: 'Spam', durationDays: 0,
        bannedAt: new Date(Date.now()-86400000*10).toISOString(), bannedBy: 'Carlos',
        bannedIp: '127.0.0.1', expiresAt: null,
        active: true, unbannedAt: null, unbannedBy: null, unbanReason: null },
    ],
    total: 2, page: 1, perPage: 20, totalPages: 1,
    filter: 'active', search: '',
    stats: { active: 2, permanent: 1, temporary: 1, total: 5, expiringSoon: 0, today: 0 },
  }],
  ['bans (expiré + levé)', 'bans', {
    ...base, page: 'bans',
    bans: [
      { id: 'b3', userId: 'u3', pseudo: 'OldBan', reason: 'Test', durationDays: 1,
        bannedAt: new Date(Date.now()-86400000*5).toISOString(), bannedBy: 'Carlos',
        bannedIp: '127.0.0.1', expiresAt: new Date(Date.now()-86400000*4).toISOString(),
        active: false, unbannedAt: new Date(Date.now()-86400000*4).toISOString(),
        unbannedBy: 'Carlos', unbanReason: 'Levé manuellement' },
    ],
    total: 1, page: 1, perPage: 20, totalPages: 1,
    filter: 'expired', search: '',
    stats: { active: 2, permanent: 1, temporary: 1, total: 5, expiringSoon: 1, today: 1 },
  }],
  ['bans (vide + recherche)', 'bans', {
    ...base, page: 'bans',
    bans: [], total: 0, page: 1, perPage: 20, totalPages: 0,
    filter: 'all', search: 'xyz',
    stats: { active: 0, permanent: 0, temporary: 0, total: 0, expiringSoon: 0, today: 0 },
  }],

  // ── Paramètres ──
  ['settings (complet)', 'settings', {
    ...base, page: 'settings',
    settings: {
      maintenanceMode: false, maintenanceMessage: 'Maintenance en cours.',
      announcementEnabled: true, announcementText: 'Mise à jour ce soir.', announcementType: 'info',
      panelTitle: 'PronoWin Admin', timezone: 'Europe/Paris',
      sessionTimeoutMin: 60, loginMaxAttempts: 5, loginBlockMinutes: 15,
      updatedAt: new Date().toISOString(), updatedBy: 'Carlos',
    },
    sysInfo: { nodeVersion: 'v20.0.0', port: 4000, env: 'development', uptime: '2h 34min', memMb: '128 MB' },
    appConfig: {
      valeurs: {
        APP_MIN_VERSION: '1.0.0', APP_LATEST_VERSION: '1.2.0', APP_FORCE_UPDATE: 'false',
        APK_MIN_VERSION: '1.0.0', APK_LATEST_VERSION: '1.3.1', APK_FORCE_UPDATE: 'true',
        APK_URL: 'https://pronowin.com/telecharger/pronowin.apk',
        APP_UPDATE_MESSAGE: 'Nouvelle version disponible.',
      },
      origine: {
        APP_MIN_VERSION: 'env', APP_LATEST_VERSION: 'base', APP_FORCE_UPDATE: 'env',
        APK_MIN_VERSION: 'base', APK_LATEST_VERSION: 'base', APK_FORCE_UPDATE: 'base',
        APK_URL: 'base', APP_UPDATE_MESSAGE: 'env',
      },
    }, appConfigErr: null,
    dataFiles: [
      { key: 'sub_admins',   name: 'sub_admins',   size: '4.2 Ko', count: 3 },
      { key: 'audit_log',    name: 'audit_log',     size: '18 Ko',  count: 142 },
      { key: 'notifications',name: 'notifications_history', size: '2.1 Ko', count: 9 },
      { key: 'settings',     name: 'settings',      size: '1.1 Ko', count: null },
      { key: 'bans',         name: 'bans',          size: '0.8 Ko', count: 2 },
      { key: 'actualites',   name: 'actualites',    size: '5.4 Ko', count: 7 },
    ],
  }],
  ['settings (panneau non redémarré)', 'settings', {
    ...base, page: 'settings',
    settings: {
      maintenanceMode: false, maintenanceMessage: '',
      announcementEnabled: false, announcementText: '', announcementType: 'info',
      panelTitle: 'PronoWin Admin', timezone: 'Europe/Paris',
      sessionTimeoutMin: 60, loginMaxAttempts: 5, loginBlockMinutes: 15,
      updatedAt: null, updatedBy: null,
    },
    sysInfo: { nodeVersion: 'v20.0.0', port: 4000, env: 'development', uptime: '18h', memMb: '65 MB' },
    dataFiles: [],
    // `appConfig` volontairement absent : c'est l'ancienne route en mémoire.
  }],

  ['settings (maintenance active)', 'settings', {
    ...base, page: 'settings',
    settings: {
      maintenanceMode: true, maintenanceMessage: 'Panel fermé.',
      announcementEnabled: false, announcementText: '', announcementType: 'warning',
      panelTitle: 'PronoWin Admin', timezone: 'Africa/Abidjan',
      sessionTimeoutMin: 30, loginMaxAttempts: 3, loginBlockMinutes: 30,
      updatedAt: null, updatedBy: null,
    },
    sysInfo: { nodeVersion: 'v18.16.0', port: 4000, env: 'production', uptime: '5j 12h', memMb: '256 MB' },
    // API injoignable : la section doit se dégrader, pas faire tomber la page.
    appConfig: null, appConfigErr: 'connect ECONNREFUSED 127.0.0.1:3000',
    dataFiles: [],
  }],
];

// ── Runner ─────────────────────────────────────────────────────────────────────
const opts = { views: [path.join(__dirname, 'views')] };
// Réutilisable comme module : le banc de prévisualisation sert les mêmes cas,
// ce qui évite d'entretenir deux jeux de données divergents.
if (require.main !== module) { module.exports = { views, opts }; return; }

let ok = 0, fail = 0;
const total = views.length;

views.forEach(([label, view, locals]) => {
  ejs.renderFile('views/' + view + '.ejs', locals, opts, (err, html) => {
    if (err) {
      const lines = err.message.split('\n').slice(0, 4).join(' | ');
      console.error('❌  [' + label + ']\n    ' + lines);
      fail++;
    } else {
      console.log('✅  [' + label + '] – ' + html.split('\n').length + ' lignes');
      ok++;
    }
    if (ok + fail === total) {
      console.log('\n' + '═'.repeat(58));
      if (fail === 0) {
        console.log('🎉  TOUT PASSE — ' + ok + '/' + total + ' vues OK');
      } else {
        console.log('⚠️   ' + fail + ' ECHEC(S) / ' + total + ' — ' + ok + ' OK');
      }
      console.log('═'.repeat(58));
      process.exit(fail > 0 ? 1 : 0);
    }
  });
});
