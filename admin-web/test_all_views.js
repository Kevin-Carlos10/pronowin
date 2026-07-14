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

const SEGMENTS = [
  { key: 'all',         label: 'Tous',     icon: '👥', desc: 'Tout le monde' },
  { key: 'premium',     label: 'Premium',  icon: '👑', desc: 'Abonnés' },
  { key: 'free',        label: 'Gratuit',  icon: '🆓', desc: 'Non-abonnés' },
  { key: 'active_30',   label: 'Actifs',   icon: '🟢', desc: '< 30j' },
  { key: 'inactive_30', label: 'Inactifs', icon: '😴', desc: '> 30j' },
  { key: 'new_7',       label: 'Nouveaux', icon: '🆕', desc: '< 7j' },
];

const PERMISSIONS = [{
  key: 'users', label: 'Utilisateurs', desc: 'Gérer les comptes',
  levels: { read: 'Voir', write: 'Modifier', delete: 'Supprimer' },
}];

const ACTION_LABELS = {
  user_banned:        { label: 'Ban',         cat: 'users',    icon: '🚫' },
  notification_sent:  { label: 'Notif',       cat: 'content',  icon: '📣' },
  news_created:       { label: 'Article créé', cat: 'content', icon: '📰' },
};

const now = new Date().toISOString();

const fakeUser = {
  id: 'u1', pseudo: 'JohnDoe', phoneNumber: '0701234567', email: 'john@ex.com',
  isPremium: true, isBanned: false, isActive: true, createdAt: now,
  balance: 25000, referralCount: 3, referralEarnings: 5000,
  premiumExpiresAt: new Date(Date.now() + 86400000 * 15).toISOString(),
};

const fakeTx = {
  id: 'tx1', type: 'deposit', amount: 25000, status: 'completed',
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

const txStats = {
  volume_deposits: 850000, volume_withdrawals: 320000,
  completed_deposits: 42, completed_withdrawals: 15,
  pending_count: 3, monthly_volume: 1200000,
  today_deposits: 5, today_withdrawals: 2,
};

const userStats = {
  total: 1200, premium: 342, banned: 15, active: 980, newWeek: 45,
  suspended: 5, newToday: 3, newMonth: 120, conversion_rate: 28.5,
};

// ── Toutes les vues à tester ───────────────────────────────────────────────────
const views = [

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
    competition: '',
  }],
  ['pronostics (vide)', 'pronostics', {
    ...base, page: 'pronostics',
    matches: [], statusFilter: 'published',
    competition: 'Ligue 1',
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

  // ── Sous-admins ──
  ['sub_admins', 'sub_admins', {
    ...base, page: 'sub-admins',
    subs: [fakeSub],
    recentLogsBySub: { 'Jean Dupont': [fakeLog] },
    PERMISSIONS,
  }],
  ['sub_admins (vide)', 'sub_admins', {
    ...base, page: 'sub-admins',
    subs: [], recentLogsBySub: {}, PERMISSIONS,
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
  ['tutoriels (liste)', 'tutoriels', {
    ...base, page: 'tutoriels',
    data: [fakeTut], total: 1, page: 1, perPage: 12, totalPages: 1,
    search: '', category: '', level: '',
    stats: { total: 1, premium: 0, free: 1, beginner: 1, intermediate: 0, advanced: 0 },
  }],
  ['tutoriels (vide)', 'tutoriels', {
    ...base, page: 'tutoriels',
    data: [], total: 0, page: 1, perPage: 12, totalPages: 0,
    search: 'xyz', category: 'valuebet', level: 'advanced',
    stats: { total: 0, premium: 0, free: 0, beginner: 0, intermediate: 0, advanced: 0 },
  }],

  // ── Tutoriel form ──
  ['tutoriel_form (new)', 'tutoriel_form', {
    ...base, page: 'tutoriels', tutorial: null,
  }],
  ['tutoriel_form (edit)', 'tutoriel_form', {
    ...base, page: 'tutoriels', tutorial: fakeTut,
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

  // ── Historique ──
  ['historique (avec données)', 'historique', {
    ...base, page: 'historique',
    data: [fakeTx], total: 1, page: 1, perPage: 20, totalPages: 1,
    search: '', type: '', status: '', method: '',
    dateFrom: '', dateTo: '', amount_min: '', amount_max: '', sortBy: 'date',
    stats: txStats,
  }],
  ['historique (vide + filtres)', 'historique', {
    ...base, page: 'historique',
    data: [], total: 0, page: 1, perPage: 20, totalPages: 0,
    search: 'John', type: 'deposit', status: 'completed', method: 'orange_money',
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
    dataFiles: [
      { key: 'sub_admins',   name: 'sub_admins',   size: '4.2 Ko', count: 3 },
      { key: 'audit_log',    name: 'audit_log',     size: '18 Ko',  count: 142 },
      { key: 'notifications',name: 'notifications_history', size: '2.1 Ko', count: 9 },
      { key: 'settings',     name: 'settings',      size: '1.1 Ko', count: null },
      { key: 'bans',         name: 'bans',          size: '0.8 Ko', count: 2 },
      { key: 'actualites',   name: 'actualites',    size: '5.4 Ko', count: 7 },
    ],
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
    dataFiles: [],
  }],
];

// ── Runner ─────────────────────────────────────────────────────────────────────
const opts = { views: [path.join(__dirname, 'views')] };
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
