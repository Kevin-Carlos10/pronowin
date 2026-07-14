require('dotenv').config();
const express      = require('express');
const cookieParser = require('cookie-parser');
const axios        = require('axios');
const crypto       = require('crypto');
const bcrypt       = require('bcryptjs');
const fs           = require('fs');
const path         = require('path');

const app     = express();
const PORT    = process.env.ADMIN_PORT ?? 4000;
const API_URL = process.env.API_URL    ?? 'http://localhost:3000/api/v1';
const PERM_HMAC_SECRET = process.env.ADMIN_PERM_SECRET ?? process.env.ADMIN_SECRET ?? 'pronowin_perm_hmac_2025';

// ─── SOUS-ADMINS : stockage local ────────────────────────────────────────────
const DATA_DIR = path.join(__dirname, 'data');
const SA_FILE  = path.join(DATA_DIR, 'sub_admins.json');
if (!fs.existsSync(DATA_DIR)) fs.mkdirSync(DATA_DIR, { recursive: true });
if (!fs.existsSync(SA_FILE))  fs.writeFileSync(SA_FILE, '[]');

function loadSubs()       { try { return JSON.parse(fs.readFileSync(SA_FILE, 'utf8')); } catch { return []; } }
function saveSubs(data)   { fs.writeFileSync(SA_FILE, JSON.stringify(data, null, 2)); }
function hashPwd(pwd)     { return bcrypt.hashSync(pwd, 12); }
function checkPwd(pwd, hash) { return bcrypt.compareSync(pwd, hash); }
// Signer les permissions avec HMAC pour empêcher la falsification côté client
function signPerms(perms) {
  const data = Buffer.from(JSON.stringify(perms)).toString('base64');
  const sig  = crypto.createHmac('sha256', PERM_HMAC_SECRET).update(data).digest('hex');
  return `${data}.${sig}`;
}
function verifyPerms(cookie) {
  try {
    const [data, sig] = (cookie ?? '').split('.');
    const expected = crypto.createHmac('sha256', PERM_HMAC_SECRET).update(data).digest('hex');
    if (sig !== expected) return [];
    return JSON.parse(Buffer.from(data, 'base64').toString());
  } catch { return []; }
}
function uid()            { return Date.now().toString(36) + Math.random().toString(36).slice(2, 7); }

// ─── BANS ─────────────────────────────────────────────────────────────────────
const BANS_FILE = path.join(DATA_DIR, 'bans.json');
if (!fs.existsSync(BANS_FILE)) fs.writeFileSync(BANS_FILE, '[]');

function loadBans()      { try { return JSON.parse(fs.readFileSync(BANS_FILE, 'utf8')); } catch { return []; } }
function saveBans(data)  { try { fs.writeFileSync(BANS_FILE, JSON.stringify(data, null, 2)); } catch {} }

/** Retourne le ban actif d'un userId (null si pas banni ou ban expiré) */
function getActiveBan(userId) {
  const bans = loadBans();
  const now  = Date.now();
  return bans.find(b =>
    b.userId === String(userId) &&
    b.active &&
    (b.expiresAt === null || new Date(b.expiresAt).getTime() > now)
  ) ?? null;
}

/** Bannir un utilisateur */
function banUser({ userId, pseudo, reason, durationDays, adminName, adminIp }) {
  const bans = loadBans();
  // Désactiver les bans précédents du même user
  bans.forEach(b => { if (b.userId === String(userId)) b.active = false; });
  const expiresAt = durationDays === 0 ? null
    : new Date(Date.now() + durationDays * 86400000).toISOString();
  const ban = {
    id:          uid(),
    userId:      String(userId),
    pseudo:      pseudo ?? String(userId),
    reason,
    durationDays: durationDays === 0 ? null : durationDays,
    expiresAt,
    active:      true,
    bannedAt:    new Date().toISOString(),
    bannedBy:    adminName,
    bannedByIp:  adminIp,
    unbannedAt:  null,
    unbannedBy:  null,
    unbanReason: null,
  };
  bans.unshift(ban);
  saveBans(bans.slice(0, 2000)); // garder 2000 entrées max
  return ban;
}

/** Débannir un utilisateur */
function unbanUser(userId, adminName, unbanReason = '') {
  const bans = loadBans();
  let found  = false;
  bans.forEach(b => {
    if (b.userId === String(userId) && b.active) {
      b.active      = false;
      b.unbannedAt  = new Date().toISOString();
      b.unbannedBy  = adminName;
      b.unbanReason = unbanReason;
      found = true;
    }
  });
  if (found) saveBans(bans);
  return found;
}

// Vérification auto-expiration des bans (toutes les 5 minutes)
setInterval(() => {
  const bans = loadBans();
  const now  = Date.now();
  let changed = false;
  bans.forEach(b => {
    if (b.active && b.expiresAt && new Date(b.expiresAt).getTime() <= now) {
      b.active     = false;
      b.unbannedAt = new Date().toISOString();
      b.unbannedBy = 'Système (expiration automatique)';
      changed = true;
    }
  });
  if (changed) {
    saveBans(bans);
    sseBroadcast('ban_expired', { ts: Date.now() });
  }
}, 5 * 60 * 1000);

// ─── PARAMÈTRES GÉNÉRAUX ─────────────────────────────────────────────────────
const SETTINGS_FILE = path.join(DATA_DIR, 'settings.json');

const DEFAULT_SETTINGS = {
  maintenanceMode:     false,
  maintenanceMessage:  'Le panel est en cours de maintenance. Revenez dans quelques instants.',
  announcementEnabled: false,
  announcementText:    '',
  announcementType:    'info',
  panelTitle:          'PronoWin Admin',
  timezone:            'Europe/Paris',
  sessionTimeoutMin:   30,
  loginMaxAttempts:    5,
  loginBlockMinutes:   15,
  updatedAt:           null,
  updatedBy:           null,
};

if (!fs.existsSync(SETTINGS_FILE)) fs.writeFileSync(SETTINGS_FILE, JSON.stringify(DEFAULT_SETTINGS, null, 2));

function loadSettings() {
  try { return { ...DEFAULT_SETTINGS, ...JSON.parse(fs.readFileSync(SETTINGS_FILE, 'utf8')) }; }
  catch { return { ...DEFAULT_SETTINGS }; }
}
function saveSettings(s) {
  try { fs.writeFileSync(SETTINGS_FILE, JSON.stringify(s, null, 2)); } catch {}
}

// ─── ACTUALITÉS : stockage local ─────────────────────────────────────────────
const NEWS_FILE = path.join(DATA_DIR, 'actualites.json');
if (!fs.existsSync(NEWS_FILE)) fs.writeFileSync(NEWS_FILE, '[]');

function loadNews()     { try { return JSON.parse(fs.readFileSync(NEWS_FILE, 'utf8')); } catch { return []; } }
function saveNews(data) { try { fs.writeFileSync(NEWS_FILE, JSON.stringify(data, null, 2)); } catch {} }
function slugify(str)   { return str.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g,'').replace(/[^a-z0-9]+/g,'-').replace(/^-|-$/g,'').slice(0,80); }

// ─── AUDIT LOG ───────────────────────────────────────────────────────────────
const LOG_FILE    = path.join(DATA_DIR, 'audit_log.json');
const LOG_MAX     = 5000;   // garder les 5000 dernières entrées
if (!fs.existsSync(LOG_FILE)) fs.writeFileSync(LOG_FILE, '[]');

function loadLogs()  { try { return JSON.parse(fs.readFileSync(LOG_FILE, 'utf8')); } catch { return []; } }
function saveLogs(l) { try { fs.writeFileSync(LOG_FILE, JSON.stringify(l)); } catch {} }

// ─── NOTIFICATIONS : historique local ────────────────────────────────────────
const NOTIF_FILE = path.join(DATA_DIR, 'notifications_history.json');
if (!fs.existsSync(NOTIF_FILE)) fs.writeFileSync(NOTIF_FILE, '[]');
function loadNotifHistory()   { try { return JSON.parse(fs.readFileSync(NOTIF_FILE, 'utf8')); } catch { return []; } }
function saveNotifHistory(d)  { try { fs.writeFileSync(NOTIF_FILE, JSON.stringify(d.slice(0, 200))); } catch {} }

// Catégories lisibles
const ACTION_LABELS = {
  login:                     { label: 'Connexion',               icon: '🔑', cat: 'auth' },
  logout:                    { label: 'Déconnexion',             icon: '🚪', cat: 'auth' },
  login_failed:              { label: 'Tentative échouée',       icon: '⚠️', cat: 'auth' },
  notification_sent:         { label: 'Notification envoyée',    icon: '📣', cat: 'notification' },
  transaction_approved:      { label: 'Dépôt approuvé',         icon: '✅', cat: 'finance' },
  transaction_rejected:      { label: 'Dépôt rejeté',           icon: '❌', cat: 'finance' },
  history_updated:           { label: 'Transaction modifiée',    icon: '📋', cat: 'finance' },
  proof_approved:            { label: 'Preuve Premium approuvée',icon: '👑', cat: 'abonnement' },
  proof_rejected:            { label: 'Preuve Premium rejetée',  icon: '🚫', cat: 'abonnement' },
  user_suspended:            { label: 'Compte suspendu',         icon: '🔴', cat: 'user' },
  user_activated:            { label: 'Compte réactivé',         icon: '🟢', cat: 'user' },
  user_premium_added:        { label: 'Premium accordé',         icon: '⭐', cat: 'user' },
  user_premium_revoked:      { label: 'Premium révoqué',         icon: '❌', cat: 'user' },
  user_notified:             { label: 'Notification envoyée',    icon: '📣', cat: 'user' },
  user_pseudo_changed:       { label: 'Pseudo modifié',          icon: '✏️', cat: 'user' },
  pronostic_published:       { label: 'Pronostic publié',        icon: '⚽', cat: 'pronostic' },
  tutorial_created:          { label: 'Tutoriel créé',           icon: '📚', cat: 'tutoriel' },
  tutorial_updated:          { label: 'Tutoriel modifié',        icon: '✏️', cat: 'tutoriel' },
  tutorial_deleted:          { label: 'Tutoriel supprimé',       icon: '🗑️', cat: 'tutoriel' },
  tutorial_premium_toggled:  { label: 'Tutoriel Premium togglé', icon: '👑', cat: 'tutoriel' },
  sub_admin_created:         { label: 'Sous-admin créé',         icon: '👤', cat: 'admin' },
  sub_admin_deleted:         { label: 'Sous-admin supprimé',     icon: '🗑️', cat: 'admin' },
  sub_admin_toggled:         { label: 'Sous-admin activé/désactivé', icon: '🔄', cat: 'admin' },
  sub_admin_perms_updated:   { label: 'Permissions modifiées',   icon: '🔐', cat: 'admin' },
  sub_admin_pwd_changed:     { label: 'Mot de passe sous-admin', icon: '🔑', cat: 'admin' },
  settings_changed:          { label: 'Paramètres modifiés',     icon: '⚙️', cat: 'admin' },
  user_banned:               { label: 'Utilisateur banni',        icon: '🚫', cat: 'user' },
  user_unbanned:             { label: 'Utilisateur débanni',      icon: '✅', cat: 'user' },
  pronostic_result_override: { label: 'Résultat corrigé',         icon: '✏️', cat: 'pronostic' },
  pronostic_result_force:    { label: 'Résultat forcé (WIN/LOSS)',icon: '⚡', cat: 'pronostic' },
  news_created:              { label: 'Actualité créée',          icon: '📰', cat: 'news' },
  news_updated:              { label: 'Actualité modifiée',       icon: '✏️', cat: 'news' },
  news_published:            { label: 'Actualité publiée',        icon: '🟢', cat: 'news' },
  news_unpublished:          { label: 'Actualité dépubliée',      icon: '🔴', cat: 'news' },
  news_pinned:               { label: 'Actualité épinglée',       icon: '📌', cat: 'news' },
  news_unpinned:             { label: 'Actualité désépinglée',    icon: '📌', cat: 'news' },
  news_deleted:              { label: 'Actualité supprimée',      icon: '🗑️', cat: 'news' },
};

function logAction(req, action, target = '', details = {}) {
  try {
    const logs = loadLogs();
    logs.unshift({
      id:        uid(),
      timestamp: new Date().toISOString(),
      action,
      target,
      details,
      adminName: req.cookies?.admin_name ?? 'Inconnu',
      adminRole: req.cookies?.admin_role ?? 'main',
      ip:        getClientIP(req),
    });
    if (logs.length > LOG_MAX) logs.splice(LOG_MAX);
    saveLogs(logs);
  } catch {}
}

// ─── SYSTÈME DE PERMISSIONS GRANULAIRES ─────────────────────────────────────
// Niveaux : 'read' < 'write' < 'delete'
// Stockage : tableau de strings "key:level" ex: ["users:write","transactions:read"]
// Rétrocompat : ancienne clé simple "users" → traité comme "users:write"

const PERM_LEVELS = ['read', 'write', 'delete'];

const PERMISSIONS = [
  {
    key: 'statistiques', label: '📈 Statistiques', desc: 'Graphiques et KPIs',
    levels: { read: 'Voir les stats', write: null, delete: null },
  },
  {
    key: 'users', label: '👥 Utilisateurs', desc: 'Gérer les comptes',
    levels: { read: 'Voir les comptes', write: 'Suspendre / accorder Premium', delete: 'Supprimer des comptes' },
  },
  {
    key: 'pronostics', label: '⚽ Pronostics', desc: 'Créer et publier',
    levels: { read: 'Voir les pronostics', write: 'Créer / publier', delete: 'Supprimer' },
  },
  {
    key: 'transactions', label: '💰 Dépôts', desc: 'Valider les dépôts',
    levels: { read: 'Voir les dépôts', write: 'Approuver / rejeter', delete: null },
  },
  {
    key: 'historique', label: '📋 Historique', desc: 'Historique transactions',
    levels: { read: 'Voir l\'historique', write: 'Modifier le statut', delete: null },
  },
  {
    key: 'abonnements', label: '👑 Abonnements', desc: 'Valider les preuves Premium',
    levels: { read: 'Voir les preuves', write: 'Approuver / rejeter', delete: null },
  },
  {
    key: 'tutoriels', label: '📚 Tutoriels', desc: 'Créer et gérer',
    levels: { read: 'Voir les tutoriels', write: 'Créer / modifier', delete: 'Supprimer' },
  },
  {
    key: 'notifications', label: '📣 Notifications', desc: 'Notifications push',
    levels: { read: 'Voir l\'historique', write: 'Envoyer des notifications', delete: null },
  },
  {
    key: 'actualites', label: '📰 Actualités', desc: 'Créer et publier des articles',
    levels: { read: 'Voir les articles', write: 'Créer / modifier / publier', delete: 'Supprimer' },
  },
];

/**
 * Retourne le niveau accordé pour une clé de permission dans un tableau de perms.
 * Supporte les deux formats : "users:write" (nouveau) et "users" (rétrocompat → write).
 */
function getPermLevel(perms, key) {
  // Chercher le format nouveau "key:level"
  for (const p of perms) {
    if (typeof p !== 'string') continue;
    const [k, l] = p.split(':');
    if (k === key && PERM_LEVELS.includes(l)) return l;
  }
  // Rétrocompat : ancienne clé simple sans niveau → write
  if (perms.includes(key)) return 'write';
  return null; // pas de permission
}

/**
 * Test si un niveau accordé est suffisant pour le niveau requis.
 * Ordre : read < write < delete
 */
function permLevelOk(granted, required) {
  if (!granted) return false;
  return PERM_LEVELS.indexOf(granted) >= PERM_LEVELS.indexOf(required);
}

// ─── CSV HELPER ──────────────────────────────────────────────────────────────
/**
 * Génère un CSV à partir d'un tableau d'en-têtes et d'un tableau de lignes.
 * Chaque ligne est un tableau de valeurs (dans le même ordre que les en-têtes).
 * Gère l'échappement des virgules, guillemets et retours à la ligne.
 */
function generateCSV(headers, rows) {
  function escCell(v) {
    if (v === null || v === undefined) return '';
    const s = String(v).replace(/\r\n|\r|\n/g, ' ');
    return s.includes(',') || s.includes('"') || s.includes('\n')
      ? '"' + s.replace(/"/g, '""') + '"'
      : s;
  }
  const lines = [
    headers.map(escCell).join(','),
    ...rows.map(row => row.map(escCell).join(',')),
  ];
  return '﻿' + lines.join('\r\n'); // BOM UTF-8 pour Excel
}

/**
 * Envoie un fichier CSV en réponse HTTP.
 */
function sendCSV(res, filename, headers, rows) {
  const csv = generateCSV(headers, rows);
  res.setHeader('Content-Type', 'text/csv; charset=utf-8');
  res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
  res.send(csv);
}

// ─── SSE CLIENTS (déclaré tôt pour être accessible dans toutes les routes) ───
const sseClients = new Set();
function sseBroadcast(event, data) {
  const msg = `event: ${event}\ndata: ${JSON.stringify(data)}\n\n`;
  for (const res of sseClients) {
    try { res.write(msg); } catch { sseClients.delete(res); }
  }
}

// ─── EXPRESS SETUP ───────────────────────────────────────────────────────────
app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, 'views'));
app.use(express.urlencoded({ extended: true }));
app.use(express.json());
app.use(cookieParser());
app.use(express.static(path.join(__dirname, 'public')));

// ─── HELPERS ─────────────────────────────────────────────────────────────────
function api(token) {
  const instance = axios.create({
    baseURL: API_URL,
    headers: { Authorization: `Bearer ${token}` },
    timeout: 15000,
  });

  // Intercepteur : enrichir les messages d'erreur
  instance.interceptors.response.use(
    r => r,
    err => {
      if (err.code === 'ECONNABORTED') {
        err.friendlyMessage = 'L\'API backend ne répond pas (timeout). Vérifiez que le serveur est démarré.';
      } else if (err.code === 'ECONNREFUSED') {
        err.friendlyMessage = 'Impossible de joindre l\'API backend. Vérifiez que le serveur est démarré sur ' + API_URL;
      } else if (err.response?.status === 401) {
        err.friendlyMessage = 'Session expirée. Reconnectez-vous.';
      } else if (err.response?.status === 403) {
        err.friendlyMessage = 'Accès refusé par l\'API backend.';
      } else if (err.response?.status >= 500) {
        err.friendlyMessage = 'Erreur interne du serveur backend.';
      }
      return Promise.reject(err);
    }
  );
  return instance;
}

// Sanitisation des chaînes : suppression des tags HTML + troncature
function sanitize(str, maxLen = 500) {
  if (typeof str !== 'string') return '';
  return str.trim().replace(/<[^>]*>/g, '').slice(0, maxLen);
}

// ─── CSRF : vérification Origin/Referer sur toutes les mutations ─────────────
app.use((req, res, next) => {
  if (!['POST', 'PUT', 'DELETE', 'PATCH'].includes(req.method)) return next();
  if (req.path === '/admin/login') return next(); // page de login exemptée

  const host    = req.headers['host'] ?? '';
  const allowed = process.env.ADMIN_ORIGIN ?? `http://${host}`;
  const origin  = req.headers['origin'];
  const referer = req.headers['referer'];

  if (origin  && !origin.startsWith(allowed))  return res.status(403).send('Requête inter-origines refusée.');
  if (!origin && referer && !referer.startsWith(allowed)) return res.status(403).send('Requête inter-origines refusée.');
  next();
});

// Données communes injectées dans tous les templates via res.locals
app.use((req, res, next) => {
  const role  = req.cookies?.admin_role ?? 'main';
  let   perms = [];
  if (role === 'sub') {
    perms = verifyPerms(req.cookies?.admin_perms);
  }
  res.locals.adminRole  = role;
  res.locals.adminName  = req.cookies?.admin_name ?? 'Admin';
  res.locals.adminPerms = perms;
  res.locals.isMain     = role !== 'sub';
  res.locals.hasPerm = (key, level = 'read') => {
    if (role !== 'sub') return true;
    return permLevelOk(getPermLevel(perms, key), level);
  };
  res.locals.getPermLevel = (key) => role !== 'sub' ? 'delete' : getPermLevel(perms, key);
  // Injecter les paramètres globaux (annonce, titre…)
  const settings = loadSettings();
  res.locals.settings = settings;
  next();
});

// Middleware d'authentification
function requireAuth(req, res, next) {
  if (!req.cookies?.admin_token) return res.redirect('/admin/login');
  next();
}

// Helper : gérer les erreurs API dans les routes (évite la duplication)
function apiError(res, e, fallbackUrl) {
  const status = e.response?.status;
  if (status === 401) {
    res.clearCookie('admin_token');
    return res.redirect('/admin/login?expired=1');
  }
  const msg = e.friendlyMessage ?? e.response?.data?.message ?? e.message ?? 'Erreur inattendue.';
  if (fallbackUrl) return res.redirect(fallbackUrl + (fallbackUrl.includes('?') ? '&' : '?') + 'error=' + encodeURIComponent(msg));
  return res.status(status ?? 500).render('error', { status: status ?? 500, title: 'Erreur', message: msg, hint: null, back: '/admin/dashboard' });
}

// Middleware de permission (bloque les sous-admins non autorisés)
// requirePerm('users')          → vérifie niveau 'read' minimum
// requirePerm('users', 'write') → vérifie niveau 'write' minimum
function requirePerm(perm, level = 'read') {
  return (req, res, next) => {
    if (res.locals.isMain) return next();
    const granted = getPermLevel(res.locals.adminPerms, perm);
    if (permLevelOk(granted, level)) return next();
    const levelLabel = level === 'delete' ? 'suppression' : level === 'write' ? 'écriture' : 'lecture';
    return res.status(403).render('error', {
      status: 403, title: 'Accès refusé',
      message: `Votre compte n'a pas la permission « ${perm} » (niveau ${levelLabel} requis).`,
      hint: 'Contactez l\'administrateur principal pour obtenir les droits nécessaires.',
      back: '/admin/dashboard',
    });
  };
}

// Middleware réservé à l'admin principal (pas aux sous-admins)
function requireMain(req, res, next) {
  if (!res.locals.isMain) {
    return res.status(403).render('error', {
      message: 'Cette page est réservée à l\'administrateur principal.',
    });
  }
  next();
}

// ─── RATE LIMITING (login) ───────────────────────────────────────────────────
const LOGIN_MAX_ATTEMPTS = 5;
const LOGIN_WINDOW_MS    = 15 * 60 * 1000;   // 15 minutes de blocage
const loginAttempts      = new Map();          // ip → { count, blockedUntil }

// Nettoyer les entrées expirées toutes les heures
setInterval(() => {
  const now = Date.now();
  for (const [ip, entry] of loginAttempts) {
    if (entry.blockedUntil && entry.blockedUntil < now) loginAttempts.delete(ip);
  }
}, 3600000);

function getClientIP(req) {
  return (req.headers['x-forwarded-for'] ?? req.socket.remoteAddress ?? '0.0.0.0').split(',')[0].trim();
}

function checkRateLimit(ip) {
  const now   = Date.now();
  const entry = loginAttempts.get(ip) ?? { count: 0, blockedUntil: null };
  if (entry.blockedUntil && entry.blockedUntil > now) {
    const remainMin = Math.ceil((entry.blockedUntil - now) / 60000);
    return { blocked: true, remainMin };
  }
  return { blocked: false, entry };
}

function recordFailedAttempt(ip) {
  const now   = Date.now();
  const entry = loginAttempts.get(ip) ?? { count: 0, blockedUntil: null };
  entry.count += 1;
  if (entry.count >= LOGIN_MAX_ATTEMPTS) {
    entry.blockedUntil = now + LOGIN_WINDOW_MS;
    entry.count        = 0;
  }
  loginAttempts.set(ip, entry);
  return entry;
}

function clearAttempts(ip) {
  loginAttempts.delete(ip);
}

// ─── SESSION REFRESH (activité) ──────────────────────────────────────────────
const SESSION_TIMEOUT_MS = (parseInt(process.env.SESSION_TIMEOUT_MIN ?? '30')) * 60000;

app.use((req, res, next) => {
  // Rafraîchir le cookie d'activité sur chaque requête authentifiée (hors API badges/search)
  if (req.cookies?.admin_token && !req.path.startsWith('/admin/api/')) {
    res.cookie('admin_last_active', Date.now().toString(), {
      maxAge: SESSION_TIMEOUT_MS + 120000,
      sameSite: 'lax',
      httpOnly: false,   // lisible par le JS client pour le countdown
    });
  }
  next();
});

// ─── AUTH ─────────────────────────────────────────────────────────────────────
app.get('/admin/login', (req, res) => {
  if (req.cookies?.admin_token) return res.redirect('/admin/dashboard');
  res.render('login', {
    error: null, expired: req.query.expired === '1',
    locked: null, remaining: LOGIN_MAX_ATTEMPTS, blockedUntilMs: null, username: '',
  });
});

app.post('/admin/login', async (req, res) => {
  const ip = getClientIP(req);
  const { username, password, remember } = req.body;
  const cookieMaxAge = remember === '1' ? 30 * 24 * 3600000 : 8 * 3600000; // 30j ou 8h

  // ── Vérifier le rate limit ──
  const rl = checkRateLimit(ip);
  if (rl.blocked) {
    return res.render('login', {
      error: null, expired: false,
      locked: `Trop de tentatives. Réessayez dans ${rl.remainMin} minute${rl.remainMin > 1 ? 's' : ''}.`,
      blockedUntilMs: loginAttempts.get(ip)?.blockedUntil ?? null,
      remaining: 0, username: username ?? '',
    });
  }

  // ── 1. Sous-admins locaux ──
  const subs = loadSubs();
  const sub  = subs.find(s => s.username === username && s.isActive !== false && checkPwd(password, s.passwordHash));
  if (sub) {
    clearAttempts(ip);
    // Obtenir un token backend frais via le compte service
    let apiToken = process.env.ADMIN_API_TOKEN ?? '';
    try {
      const svcEmail = process.env.ADMIN_SERVICE_EMAIL;
      const svcPass  = process.env.ADMIN_SERVICE_PASSWORD;
      if (svcEmail && svcPass) {
        const svcRes = await axios.post(`${API_URL}/admin/login`, { email: svcEmail, password: svcPass }, { timeout: 5000 });
        apiToken = svcRes.data.token ?? apiToken;
      }
    } catch (_) { /* fallback sur ADMIN_API_TOKEN si le backend est indisponible */ }

    const perms    = JSON.stringify(sub.permissions ?? []);
    sub.lastLoginAt = new Date().toISOString();
    saveSubs(subs);
    res.cookie('admin_token',   apiToken,                              { httpOnly: true,  maxAge: cookieMaxAge, sameSite: 'lax' });
    res.cookie('admin_name',    sub.name,                              { httpOnly: true,  maxAge: cookieMaxAge, sameSite: 'lax' });
    res.cookie('admin_role',    'sub',                                 { httpOnly: true,  maxAge: cookieMaxAge, sameSite: 'lax' });
    res.cookie('admin_perms',   signPerms(sub.permissions ?? []),       { maxAge: cookieMaxAge, sameSite: 'lax' });
    res.cookie('admin_sub_id',  sub.id,                                { maxAge: cookieMaxAge, sameSite: 'lax' });
    res.cookie('admin_last_active', Date.now().toString(),             { maxAge: cookieMaxAge, sameSite: 'lax', httpOnly: false });
    req.cookies = { ...req.cookies, admin_name: sub.name, admin_role: 'sub' };
    logAction(req, 'login', `Sous-admin: ${sub.name}`, { username: sub.username });
    return res.redirect('/admin/dashboard');
  }

  // ── Vérifier si le username ressemble à un sous-admin inactif ──
  const inactiveSub = subs.find(s => s.username === username && s.isActive === false);
  if (inactiveSub) {
    recordFailedAttempt(ip);
    return res.render('login', { error: 'Ce compte est désactivé. Contactez l\'administrateur principal.', expired: false, locked: null, remaining: LOGIN_MAX_ATTEMPTS, blockedUntilMs: null, username });
  }

  // ── 2. Admin principal via l'API backend ──
  try {
    // Le formulaire envoie "username", l'API attend "email"
    const r = await axios.post(`${API_URL}/admin/login`, { email: username, password }, { timeout: 10000 });
    clearAttempts(ip);
    res.cookie('admin_token',   r.data.token,      { httpOnly: true, maxAge: cookieMaxAge, sameSite: 'lax' });
    res.cookie('admin_name',    r.data.admin.name, { httpOnly: true, maxAge: cookieMaxAge, sameSite: 'lax' });
    res.cookie('admin_role',    'main',            { httpOnly: true, maxAge: cookieMaxAge, sameSite: 'lax' });
    res.cookie('admin_last_active', Date.now().toString(), { maxAge: cookieMaxAge, sameSite: 'lax', httpOnly: false });
    res.clearCookie('admin_perms');
    res.clearCookie('admin_sub_id');
    req.cookies = { ...req.cookies, admin_name: r.data.admin.name, admin_role: 'main' };
    logAction(req, 'login', `Admin principal: ${r.data.admin.name}`);
    res.redirect('/admin/dashboard');
  } catch (e) {
    const entry     = recordFailedAttempt(ip);
    const remaining = Math.max(0, LOGIN_MAX_ATTEMPTS - (entry.count ?? 0));
    const errMsg    = e.response?.data?.message ?? 'Identifiants incorrects.';
    req.cookies = { ...req.cookies, admin_name: username, admin_role: 'unknown' };
    logAction(req, 'login_failed', `Identifiant: ${username}`, { ip });
    // Si bloqué après cet échec
    const nowBlocked = checkRateLimit(ip);
    if (nowBlocked.blocked) {
      return res.render('login', {
        error: null, expired: false,
        locked: `Trop de tentatives. Réessayez dans ${nowBlocked.remainMin} minute${nowBlocked.remainMin > 1 ? 's' : ''}.`,
        blockedUntilMs: loginAttempts.get(ip)?.blockedUntil ?? null,
        remaining: 0, username,
      });
    }
    res.render('login', { error: errMsg, expired: false, locked: null, remaining, blockedUntilMs: null, username });
  }
});

app.get('/admin/logout', (req, res) => {
  logAction(req, 'logout', req.cookies?.admin_name ?? '');
  ['admin_token','admin_name','admin_role','admin_perms','admin_sub_id','admin_last_active'].forEach(c => res.clearCookie(c));
  res.redirect('/admin/login');
});

// ─── DASHBOARD ────────────────────────────────────────────────────────────────
app.get('/admin/dashboard', requireAuth, async (req, res) => {
  const a = api(req.cookies.admin_token);
  const [statsRes, pendingRes, proofsRes] = await Promise.allSettled([
    a.get('/pronostics/admin/stats'),
    a.get('/payments/admin/pending?page=1'),
    a.get('/subscriptions/admin/proofs?page=1'),
  ]);
  if ([statsRes, pendingRes, proofsRes].some(r => r.status === 'rejected' && r.reason?.response?.status === 401)) {
    res.clearCookie('admin_token'); return res.redirect('/admin/login?expired=1');
  }

  // Données locales : bans actifs + activité récente
  const now        = Date.now();
  const allBans    = loadBans();
  const activeBans = allBans.filter(b => b.active && (!b.expiresAt || new Date(b.expiresAt).getTime() > now));
  const recentLogs = loadLogs().slice(0, 8); // 8 dernières actions

  res.render('dashboard', {
    adminName: req.cookies.admin_name ?? 'Admin',
    stats:   statsRes.status  === 'fulfilled' ? statsRes.value.data   : { totalUsers:0,premiumUsers:0,pendingTx:0,publishedToday:0 },
    pending: pendingRes.status === 'fulfilled' ? pendingRes.value.data : { data:[],total:0 },
    proofs:  proofsRes.status  === 'fulfilled' ? proofsRes.value.data  : { data:[],total:0 },
    activeBansCount: activeBans.length,
    recentBans:      activeBans.slice(0, 3),
    recentLogs,
  });
});

// ─── UTILISATEURS ─────────────────────────────────────────────────────────────
app.get('/admin/users', requireAuth, requirePerm('users'), async (req, res) => {
  const a = api(req.cookies.admin_token);
  const { search='', plan='', status='', sort_by='createdAt', sort_dir='desc', page='1',
          date_from='', date_to='', min_tx='' } = req.query;
  try {
    const [usersRes, statsRes] = await Promise.all([
      a.get('/admin/users', { params: { search, plan, status, sort_by, sort_dir, page, per_page: 20, date_from, date_to, min_tx } }),
      a.get('/admin/users/stats'),
    ]);
    const now = Date.now();
    const activeBanIds = new Set(
      loadBans().filter(b => b.active && (!b.expiresAt || new Date(b.expiresAt).getTime() > now)).map(b => b.userId)
    );
    res.render('users', {
      adminName: req.cookies.admin_name ?? 'Admin',
      data: usersRes.data.data, stats: statsRes.data, total: usersRes.data.total,
      page: parseInt(page), perPage: 20, totalPages: usersRes.data.total_pages,
      search, plan, status, sortBy: sort_by, date_from, date_to, min_tx,
      activeBanIds: [...activeBanIds],
      success: req.query.success ?? null, error: req.query.error ?? null,
    });
  } catch (e) {
    if (e.response?.status === 401) return res.redirect('/admin/login?expired=1');
    res.render('users', {
      adminName: req.cookies.admin_name ?? 'Admin',
      data: [], stats: { total:0,premium:0,active:0,suspended:0,newToday:0,newWeek:0,newMonth:0,conversion_rate:0 },
      total:0, page:1, perPage:20, totalPages:1,
      search, plan, status, sortBy: sort_by, date_from, date_to, min_tx,
      activeBanIds: [],
      success: null, error: e.response?.data?.message ?? e.message,
    });
  }
});

app.get('/admin/users/export', requireAuth, requirePerm('users'), async (req, res) => {
  const a = api(req.cookies.admin_token);
  try {
    // Essayer d'abord la route export dédiée de l'API
    try {
      const r = await a.get('/admin/users/export/csv', { params: req.query, responseType: 'text' });
      res.setHeader('Content-Type', 'text/csv; charset=utf-8');
      res.setHeader('Content-Disposition', r.headers['content-disposition'] ?? 'attachment; filename="users_export.csv"');
      return res.send(r.data);
    } catch (apiErr) {
      if (apiErr.response?.status !== 404) throw apiErr; // erreur autre que "route inexistante"
    }
    // Fallback : récupérer les données et générer le CSV nous-mêmes
    const { search='', plan='', status='', sort_by='createdAt', sort_dir='desc',
            date_from='', date_to='', min_tx='' } = req.query;
    const r = await a.get('/admin/users', { params: {
      search, plan, status, sort_by, sort_dir, date_from, date_to, min_tx,
      page: 1, per_page: 5000,
    }});
    const users = r.data.data ?? [];
    const date  = new Date().toISOString().slice(0,10);
    const headers = ['ID','Pseudo','Téléphone','Email','ID 1xBet','Plan','Statut','Inscrit le','Dernière connexion','Transactions','Jours Premium restants'];
    const rows = users.map(u => [
      u.id, u.pseudo, u.phoneNumber, u.email ?? '', u.xbetId ?? '',
      u.is_premium ? 'Premium' : 'Gratuit',
      u.isActive ? 'Actif' : 'Suspendu',
      u.createdAt ? new Date(u.createdAt).toLocaleDateString('fr-FR') : '',
      u.lastLoginAt ? new Date(u.lastLoginAt).toLocaleDateString('fr-FR') : '',
      u.transaction_count ?? 0,
      u.days_left ?? 0,
    ]);
    sendCSV(res, `users_${date}.csv`, headers, rows);
  } catch (e) { res.redirect('/admin/users?error=' + encodeURIComponent('Erreur export CSV : ' + (e.friendlyMessage ?? e.message))); }
});

app.get('/admin/users/:id', requireAuth, requirePerm('users'), async (req, res) => {
  const a = api(req.cookies.admin_token);
  try {
    const r = await a.get('/admin/users/' + req.params.id);
    res.render('user_detail', {
      adminName: req.cookies.admin_name ?? 'Admin',
      user: r.data.user, transactions: r.data.transactions,
      subscriptions: r.data.subscriptions, proofs: r.data.proofs, referrals: r.data.referrals,
      activeBan: getActiveBan(req.params.id),
      success: req.query.success ?? null, error: req.query.error ?? null,
    });
  } catch (e) {
    if (e.response?.status === 401) return res.redirect('/admin/login?expired=1');
    res.redirect('/admin/users?error=' + encodeURIComponent(e.response?.data?.message ?? e.message));
  }
});

app.post('/admin/users/:id/suspend',        requireAuth, requirePerm('users', 'write'), async (req, res) => {
  const a = api(req.cookies.admin_token);
  try {
    await a.patch('/admin/users/' + req.params.id + '/suspend', req.body);
    const isSuspend = req.body.suspend === 'true';
    logAction(req, isSuspend ? 'user_suspended' : 'user_activated', `User #${req.params.id}`, { userId: req.params.id });
    const msg = isSuspend ? 'Compte suspendu.' : 'Compte réactivé.';
    res.redirect('/admin/users/' + req.params.id + '?success=' + encodeURIComponent(msg));
  } catch (e) { res.redirect('/admin/users/' + req.params.id + '?error=' + encodeURIComponent(e.response?.data?.message ?? e.message)); }
});

app.post('/admin/users/:id/premium',        requireAuth, requirePerm('users', 'write'), async (req, res) => {
  const a = api(req.cookies.admin_token);
  try {
    await a.post('/admin/users/' + req.params.id + '/premium', req.body);
    logAction(req, 'user_premium_added', `User #${req.params.id}`, { userId: req.params.id, days: req.body.duration_days });
    res.redirect('/admin/users/' + req.params.id + '?success=' + encodeURIComponent('Premium activé !'));
  } catch (e) { res.redirect('/admin/users/' + req.params.id + '?error=' + encodeURIComponent(e.response?.data?.message ?? e.message)); }
});

app.post('/admin/users/:id/revoke-premium', requireAuth, requirePerm('users', 'write'), async (req, res) => {
  const a = api(req.cookies.admin_token);
  try {
    await a.delete('/admin/users/' + req.params.id + '/premium');
    logAction(req, 'user_premium_revoked', `User #${req.params.id}`, { userId: req.params.id });
    res.redirect('/admin/users/' + req.params.id + '?success=' + encodeURIComponent('Premium révoqué.'));
  } catch (e) { res.redirect('/admin/users/' + req.params.id + '?error=' + encodeURIComponent(e.response?.data?.message ?? e.message)); }
});

app.post('/admin/users/:id/notify', requireAuth, requirePerm('users', 'write'), async (req, res) => {
  const a = api(req.cookies.admin_token);
  try {
    await a.post('/admin/users/' + req.params.id + '/notify', req.body);
    logAction(req, 'user_notified', `User #${req.params.id}`, { userId: req.params.id, title: req.body.title });
    res.redirect('/admin/users/' + req.params.id + '?success=' + encodeURIComponent('Notification envoyée !'));
  } catch (e) { res.redirect('/admin/users/' + req.params.id + '?error=' + encodeURIComponent(e.response?.data?.message ?? e.message)); }
});

app.post('/admin/users/:id/pseudo', requireAuth, requirePerm('users', 'write'), async (req, res) => {
  const a = api(req.cookies.admin_token);
  try {
    await a.patch('/admin/users/' + req.params.id + '/pseudo', req.body);
    logAction(req, 'user_pseudo_changed', `User #${req.params.id} → ${req.body.pseudo}`, { userId: req.params.id, pseudo: req.body.pseudo });
    res.redirect('/admin/users/' + req.params.id + '?success=' + encodeURIComponent('Pseudo modifié.'));
  } catch (e) { res.redirect('/admin/users/' + req.params.id + '?error=' + encodeURIComponent(e.response?.data?.message ?? e.message)); }
});

// ─── PRONOSTICS ───────────────────────────────────────────────────────────────
app.get('/admin/pronostics', requireAuth, requirePerm('pronostics'), async (req, res) => {
  const a = api(req.cookies.admin_token);
  const competition   = req.query.competition ?? '';
  const statusFilter  = req.query.status ?? '';
  try {
    const r = await a.get('/pronostics/admin/upcoming' + (competition ? '?competition=' + competition : ''));
    res.render('pronostics', { adminName: req.cookies.admin_name ?? 'Admin', matches: r.data ?? [], competition, statusFilter, success: req.query.success === '1', error: null });
  } catch (e) {
    if (e.response?.status === 401) return res.redirect('/admin/login?expired=1');
    res.render('pronostics', { adminName: req.cookies.admin_name ?? 'Admin', matches: [], competition, statusFilter, success: false, error: e.response?.data?.message ?? e.message });
  }
});

app.get('/admin/pronostics/export', requireAuth, requirePerm('pronostics'), async (req, res) => {
  const a = api(req.cookies.admin_token);
  try {
    const competition = req.query.competition ?? '';
    const r = await a.get('/pronostics/admin/upcoming' + (competition ? '?competition=' + competition : ''));
    const matches = r.data ?? [];
    const date    = new Date().toISOString().slice(0,10);
    const headers = ['ID Match','Compétition','Équipe Domicile','Équipe Extérieur','Date match','Tip','Côte','Is Premium','Publié','Créé le'];
    const rows = matches.map(m => [
      m.id, m.competition ?? '',
      m.homeTeam ?? '', m.awayTeam ?? '',
      m.matchDate ? new Date(m.matchDate).toLocaleString('fr-FR') : '',
      m.pronostic?.tip ?? '', m.pronostic?.odds ?? '',
      m.pronostic?.is_premium ? 'Oui' : 'Non',
      m.pronostic?.published  ? 'Oui' : 'Non',
      m.pronostic?.createdAt  ? new Date(m.pronostic.createdAt).toLocaleString('fr-FR') : '',
    ]);
    sendCSV(res, `pronostics_${date}.csv`, headers, rows);
  } catch (e) { res.redirect('/admin/pronostics?error=' + encodeURIComponent('Erreur export : ' + (e.friendlyMessage ?? e.message))); }
});

// Proxy cotes → The Odds API (via backend, avec auth admin)
app.get('/admin/pronostics/edit/:matchId/odds', requireAuth, requirePerm('pronostics'), async (req, res) => {
  const a = api(req.cookies.admin_token);
  try {
    const r = await a.get('/pronostics/admin/match/' + req.params.matchId + '/odds');
    res.json(r.data);
  } catch (e) {
    res.status(e.response?.status ?? 500).json({ message: e.response?.data?.message ?? e.message });
  }
});

app.get('/admin/pronostics/edit/:matchId', requireAuth, requirePerm('pronostics'), async (req, res) => {
  const a = api(req.cookies.admin_token);
  try {
    const r = await a.get('/pronostics/admin/match/' + req.params.matchId);
    res.render('pronostic_form', { adminName: req.cookies.admin_name ?? 'Admin', match: r.data, error: null, query: req.query });
  } catch (e) {
    if (e.response?.status === 401) return res.redirect('/admin/login?expired=1');
    res.redirect('/admin/pronostics');
  }
});

app.post('/admin/pronostics/edit/:matchId', requireAuth, requirePerm('pronostics', 'write'), async (req, res) => {
  const a = api(req.cookies.admin_token);
  try {
    await a.post('/pronostics/admin/pronostic', { ...req.body, match_id: req.params.matchId, is_premium: req.body.is_premium === 'on', publish: req.body.publish === 'true' });
    logAction(req, 'pronostic_published', `Match #${req.params.matchId}`, { matchId: req.params.matchId, tip: req.body.tip, published: req.body.publish === 'true' });
    res.redirect('/admin/pronostics?success=1');
  } catch (e) {
    try {
      const r2 = await a.get('/pronostics/admin/match/' + req.params.matchId);
      res.render('pronostic_form', { adminName: req.cookies.admin_name ?? 'Admin', match: r2.data, error: e.response?.data?.message ?? 'Erreur', query: {} });
    } catch { res.redirect('/admin/pronostics'); }
  }
});

// Forcer le résultat WIN/LOSS/reset manuellement sur un pronostic
app.post('/admin/pronostics/result/:pronosticId', requireAuth, requirePerm('pronostics', 'write'), async (req, res) => {
  const a = api(req.cookies.admin_token);
  const matchId = req.body.match_id;
  try {
    const result = req.body.result === 'null' ? null : req.body.result;
    await a.patch('/pronostics/admin/pronostic/' + req.params.pronosticId + '/result', { result });
    logAction(req, 'pronostic_result_override', `Pronostic #${req.params.pronosticId}`, { result });
    res.redirect('/admin/pronostics/edit/' + matchId + '?result_success=1');
  } catch (e) {
    res.redirect('/admin/pronostics/edit/' + matchId + '?result_error=' + encodeURIComponent(e.response?.data?.message ?? e.message));
  }
});

// Route AJAX pour forcer le résultat depuis la liste des pronostics
app.post('/admin/pronostics/force-result/:pronosticId', requireAuth, requirePerm('pronostics', 'write'), async (req, res) => {
  const a = api(req.cookies.admin_token);
  try {
    const result = req.body.result === 'null' ? null : req.body.result;
    if (result !== 'WIN' && result !== 'LOSS' && result !== null) {
      return res.status(400).json({ ok: false, message: 'result doit être WIN, LOSS ou null.' });
    }
    await a.patch('/pronostics/admin/pronostic/' + req.params.pronosticId + '/result', { result });
    logAction(req, 'pronostic_result_force', `Pronostic #${req.params.pronosticId}`, { result });
    res.json({ ok: true });
  } catch (e) {
    res.status(e.response?.status ?? 500).json({ ok: false, message: e.response?.data?.message ?? e.message });
  }
});

// ─── TRANSACTIONS ─────────────────────────────────────────────────────────────
app.get('/admin/transactions', requireAuth, requirePerm('transactions'), async (req, res) => {
  const a = api(req.cookies.admin_token);
  const { search = '', method = '', type = '', page = '1' } = req.query;
  try {
    const [pendingRes, statsRes] = await Promise.allSettled([
      a.get('/payments/admin/pending', { params: { search, method, type, page, per_page: 20 } }),
      a.get('/payments/admin/stats').catch(() => ({ data: null })),
    ]);
    if (pendingRes.status === 'rejected' && pendingRes.reason?.response?.status === 401)
      return res.redirect('/admin/login?expired=1');

    const raw   = pendingRes.status === 'fulfilled' ? pendingRes.value.data : { data: [], total: 0 };
    const stats = statsRes.status  === 'fulfilled' ? statsRes.value.data   : null;

    // Stats calculées localement si l'API ne les fournit pas
    const items       = raw.data ?? [];
    const totalAmount = items.reduce((s, tx) => s + (tx.amount ?? 0), 0);
    const deposits    = items.filter(tx => tx.type === 'deposit').length;
    const withdrawals = items.filter(tx => tx.type === 'withdrawal').length;

    res.render('transactions', {
      data: raw, search, method, type,
      page: parseInt(page), totalPages: Math.max(1, Math.ceil((raw.total ?? 0) / 20)),
      apiStats: stats,
      localStats: { totalAmount, deposits, withdrawals, total: raw.total ?? 0 },
      success: req.query.success ?? null,
      error:   req.query.error   ?? null,
    });
  } catch (e) {
    if (e.response?.status === 401) return res.redirect('/admin/login?expired=1');
    res.render('transactions', {
      data: { data: [], total: 0 }, search, method, type, page: 1, totalPages: 1,
      apiStats: null, localStats: { totalAmount:0, deposits:0, withdrawals:0, total:0 },
      success: null, error: e.response?.data?.message ?? e.message,
    });
  }
});

app.post('/admin/transactions/:id', requireAuth, requirePerm('transactions', 'write'), async (req, res) => {
  const a = api(req.cookies.admin_token);
  try {
    await a.patch('/payments/admin/' + req.params.id, { status: req.body.status, admin_note: req.body.admin_note ?? null });
    const action = req.body.status === 'completed' ? 'transaction_approved' : 'transaction_rejected';
    logAction(req, action, `Transaction #${req.params.id}`, { txId: req.params.id, status: req.body.status, note: req.body.admin_note });
    sseBroadcast('action', { type: action, adminName: req.cookies.admin_name ?? 'Admin', ts: Date.now() });
    res.redirect('/admin/transactions?success=1');
  } catch (e) { res.redirect('/admin/transactions?error=' + encodeURIComponent(e.response?.data?.message ?? 'Erreur')); }
});

// ─── HISTORIQUE ───────────────────────────────────────────────────────────────
app.get('/admin/historique', requireAuth, requirePerm('historique'), async (req, res) => {
  const a = api(req.cookies.admin_token);
  const { search='', type='', status='', method='', date_from='', date_to='', page='1',
          amount_min='', amount_max='' } = req.query;
  try {
    const [histRes, statsRes] = await Promise.all([
      a.get('/admin/history', { params: { search, type, status, method, date_from, date_to, page, per_page: 20, amount_min, amount_max } }),
      a.get('/admin/history/stats'),
    ]);
    res.render('historique', {
      adminName: req.cookies.admin_name ?? 'Admin',
      data: histRes.data.data, stats: statsRes.data, total: histRes.data.total,
      page: parseInt(page), perPage: 20, totalPages: histRes.data.total_pages,
      search, type, status, method, dateFrom: date_from, dateTo: date_to, amount_min, amount_max,
      sortBy: req.query.sort_by ?? '',
      success: req.query.success ?? null, error: req.query.error ?? null,
    });
  } catch (e) {
    if (e.response?.status === 401) return res.redirect('/admin/login?expired=1');
    res.render('historique', {
      adminName: req.cookies.admin_name ?? 'Admin',
      data: [], stats: { volume_deposits:0,volume_withdrawals:0,completed_deposits:0,completed_withdrawals:0,pending_count:0,today_deposits:0,today_withdrawals:0,monthly_volume:0 },
      total:0, page:1, perPage:20, totalPages:1,
      search, type, status, method, dateFrom: date_from, dateTo: date_to, amount_min, amount_max, sortBy: '',
      success: null, error: e.response?.data?.message ?? e.message,
    });
  }
});

app.post('/admin/historique/:id', requireAuth, requirePerm('historique', 'write'), async (req, res) => {
  const a = api(req.cookies.admin_token);
  try {
    await a.patch('/admin/history/' + req.params.id, { status: req.body.status, admin_note: req.body.admin_note });
    logAction(req, 'history_updated', `Transaction #${req.params.id}`, { txId: req.params.id, status: req.body.status });
    res.redirect('/admin/historique?success=' + encodeURIComponent('Transaction mise à jour.'));
  } catch (e) { res.redirect('/admin/historique?error=' + encodeURIComponent(e.response?.data?.message ?? e.message)); }
});

app.get('/admin/historique/export', requireAuth, requirePerm('historique'), async (req, res) => {
  const a = api(req.cookies.admin_token);
  try {
    try {
      const r = await a.get('/admin/history/export/csv', { params: req.query, responseType: 'text' });
      res.setHeader('Content-Type', 'text/csv; charset=utf-8');
      res.setHeader('Content-Disposition', r.headers['content-disposition'] ?? 'attachment; filename="historique_export.csv"');
      return res.send(r.data);
    } catch (apiErr) {
      if (apiErr.response?.status !== 404) throw apiErr;
    }
    // Fallback : générer localement
    const { search='', type='', status='', method='', date_from='', date_to='',
            amount_min='', amount_max='' } = req.query;
    const r = await a.get('/admin/history', { params: {
      search, type, status, method, date_from, date_to, amount_min, amount_max,
      page: 1, per_page: 5000,
    }});
    const txs  = r.data.data ?? [];
    const date = new Date().toISOString().slice(0,10);
    const headers = ['ID','Utilisateur','Téléphone','Type','Montant (FCFA)','Méthode','Statut','ID 1xBet','N° Envoyeur','Note admin','Date création','Date traitement'];
    const rows = txs.map(tx => [
      tx.id,
      tx.user?.pseudo ?? '',
      tx.user?.phoneNumber ?? '',
      tx.type === 'deposit' ? 'Dépôt' : 'Retrait',
      tx.amount ?? 0,
      tx.paymentMethod ?? '',
      tx.status ?? '',
      tx.xbetId ?? '',
      tx.senderPhone ?? '',
      tx.adminNote ?? '',
      tx.createdAt   ? new Date(tx.createdAt).toLocaleString('fr-FR')   : '',
      tx.processedAt ? new Date(tx.processedAt).toLocaleString('fr-FR') : '',
    ]);
    sendCSV(res, `historique_${date}.csv`, headers, rows);
  } catch (e) { res.redirect('/admin/historique?error=' + encodeURIComponent('Erreur export : ' + (e.friendlyMessage ?? e.message))); }
});

// ─── ABONNEMENTS ──────────────────────────────────────────────────────────────
app.get('/admin/abonnements', requireAuth, requirePerm('abonnements'), async (req, res) => {
  const a = api(req.cookies.admin_token);
  try {
    const r = await a.get('/subscriptions/admin/proofs');
    res.render('abonnements', { adminName: req.cookies.admin_name ?? 'Admin', data: r.data, success: req.query.success === '1', error: req.query.error ?? null });
  } catch (e) {
    if (e.response?.status === 401) return res.redirect('/admin/login?expired=1');
    res.render('abonnements', { adminName: req.cookies.admin_name ?? 'Admin', data: { data:[],total:0 }, success: false, error: e.response?.data?.message ?? e.message });
  }
});

app.get('/admin/abonnements/export', requireAuth, requirePerm('abonnements'), async (req, res) => {
  const a = api(req.cookies.admin_token);
  try {
    const r    = await a.get('/subscriptions/admin/proofs', { params: { page: 1, per_page: 5000 } });
    const data = r.data.data ?? [];
    const date = new Date().toISOString().slice(0,10);
    const headers = ['ID Preuve','Utilisateur','Téléphone','Statut','Durée (jours)','Date soumission','Date traitement','Note admin'];
    const rows = data.map(p => [
      p.id,
      p.user?.pseudo ?? '',
      p.user?.phoneNumber ?? '',
      p.status ?? '',
      p.duration_days ?? '',
      p.createdAt   ? new Date(p.createdAt).toLocaleString('fr-FR')   : '',
      p.processedAt ? new Date(p.processedAt).toLocaleString('fr-FR') : '',
      p.adminNote ?? '',
    ]);
    sendCSV(res, `abonnements_${date}.csv`, headers, rows);
  } catch (e) { res.redirect('/admin/abonnements?error=' + encodeURIComponent('Erreur export : ' + (e.friendlyMessage ?? e.message))); }
});

app.post('/admin/abonnements/:id', requireAuth, requirePerm('abonnements', 'write'), async (req, res) => {
  const a = api(req.cookies.admin_token);
  try {
    const approved = req.body.action === 'approve';
    await a.patch('/subscriptions/admin/proofs/' + req.params.id, { approved, admin_note: req.body.admin_note ?? null, duration_days: parseInt(req.body.duration_days ?? '30') });
    const proofAction = approved ? 'proof_approved' : 'proof_rejected';
    logAction(req, proofAction, `Preuve #${req.params.id}`, { proofId: req.params.id, days: req.body.duration_days });
    sseBroadcast('action', { type: proofAction, adminName: req.cookies.admin_name ?? 'Admin', ts: Date.now() });
    res.redirect('/admin/abonnements?success=1');
  } catch (e) { res.redirect('/admin/abonnements?error=' + encodeURIComponent(e.response?.data?.message ?? 'Erreur')); }
});

// ─── TUTORIELS ────────────────────────────────────────────────────────────────
app.get('/admin/tutoriels', requireAuth, requirePerm('tutoriels'), async (req, res) => {
  const a = api(req.cookies.admin_token);
  const { search='', category='', level='', page='1' } = req.query;
  try {
    const [listRes, statsRes] = await Promise.all([
      a.get('/admin/tutorials', { params: { search, category, level, page, per_page: 20 } }),
      a.get('/admin/tutorials/stats'),
    ]);
    res.render('tutoriels', {
      adminName: req.cookies.admin_name ?? 'Admin',
      data: listRes.data.data, stats: statsRes.data, total: listRes.data.total,
      page: parseInt(page), totalPages: listRes.data.total_pages,
      search, category, level,
      success: req.query.success ?? null, error: req.query.error ?? null,
    });
  } catch (e) {
    if (e.response?.status === 401) return res.redirect('/admin/login?expired=1');
    res.render('tutoriels', {
      adminName: req.cookies.admin_name ?? 'Admin',
      data: [], stats: { total:0,premium:0,free:0,beginner:0,intermediate:0,advanced:0 },
      total:0, page:1, totalPages:1, search, category, level,
      success: null, error: e.response?.data?.message ?? e.message,
    });
  }
});

app.post('/admin/tutoriels/seed',        requireAuth, requirePerm('tutoriels', 'write'), async (req, res) => {
  const a = api(req.cookies.admin_token);
  try {
    const r = await a.post('/admin/tutorials/seed');
    res.redirect('/admin/tutoriels?success=' + encodeURIComponent(r.data.message));
  } catch (e) { res.redirect('/admin/tutoriels?error=' + encodeURIComponent(e.response?.data?.message ?? 'Erreur')); }
});

app.get('/admin/tutoriels/new',          requireAuth, requirePerm('tutoriels', 'write'), (req, res) => {
  res.render('tutoriel_form', { adminName: req.cookies.admin_name ?? 'Admin', tutorial: null, error: null });
});

app.post('/admin/tutoriels',             requireAuth, requirePerm('tutoriels', 'write'), async (req, res) => {
  const a = api(req.cookies.admin_token);
  try {
    if (req.body.duration_seconds) req.body.duration_seconds = parseInt(req.body.duration_seconds) * 60;
    await a.post('/admin/tutorials', req.body);
    logAction(req, 'tutorial_created', req.body.title ?? 'Sans titre', { title: req.body.title });
    res.redirect('/admin/tutoriels?success=' + encodeURIComponent('Tutoriel créé avec succès !'));
  } catch (e) {
    res.render('tutoriel_form', { adminName: req.cookies.admin_name ?? 'Admin', tutorial: null, error: e.response?.data?.message ?? 'Erreur.' });
  }
});

app.get('/admin/tutoriels/:id/edit',     requireAuth, requirePerm('tutoriels', 'write'), async (req, res) => {
  const a = api(req.cookies.admin_token);
  try {
    const r = await a.get('/admin/tutorials/' + req.params.id);
    res.render('tutoriel_form', { adminName: req.cookies.admin_name ?? 'Admin', tutorial: r.data, error: null });
  } catch (e) { res.redirect('/admin/tutoriels?error=' + encodeURIComponent('Tutoriel introuvable.')); }
});

app.post('/admin/tutoriels/:id/edit',    requireAuth, requirePerm('tutoriels', 'write'), async (req, res) => {
  const a = api(req.cookies.admin_token);
  try {
    if (req.body.duration_seconds) req.body.duration_seconds = parseInt(req.body.duration_seconds) * 60;
    await a.patch('/admin/tutorials/' + req.params.id, req.body);
    logAction(req, 'tutorial_updated', req.body.title ?? `#${req.params.id}`, { id: req.params.id });
    res.redirect('/admin/tutoriels?success=' + encodeURIComponent('Tutoriel modifié !'));
  } catch (e) {
    try {
      const r2 = await a.get('/admin/tutorials/' + req.params.id);
      res.render('tutoriel_form', { adminName: req.cookies.admin_name ?? 'Admin', tutorial: r2.data, error: e.response?.data?.message ?? 'Erreur.' });
    } catch { res.redirect('/admin/tutoriels'); }
  }
});

app.post('/admin/tutoriels/:id/premium', requireAuth, requirePerm('tutoriels', 'write'), async (req, res) => {
  const a = api(req.cookies.admin_token);
  try {
    await a.patch('/admin/tutorials/' + req.params.id + '/premium');
    logAction(req, 'tutorial_premium_toggled', `Tutoriel #${req.params.id}`, { id: req.params.id });
    res.redirect('/admin/tutoriels?success=' + encodeURIComponent('Statut Premium modifié.'));
  } catch (e) { res.redirect('/admin/tutoriels?error=' + encodeURIComponent(e.response?.data?.message ?? 'Erreur')); }
});

app.post('/admin/tutoriels/:id/delete',  requireAuth, requirePerm('tutoriels', 'delete'), async (req, res) => {
  const a = api(req.cookies.admin_token);
  try {
    await a.delete('/admin/tutorials/' + req.params.id);
    logAction(req, 'tutorial_deleted', `Tutoriel #${req.params.id}`, { id: req.params.id });
    res.redirect('/admin/tutoriels?success=' + encodeURIComponent('Tutoriel supprimé.'));
  } catch (e) { res.redirect('/admin/tutoriels?error=' + encodeURIComponent(e.response?.data?.message ?? 'Erreur')); }
});

// ─── ACTUALITÉS ───────────────────────────────────────────────────────────────
const NEWS_PER_PAGE = 12;

app.get('/admin/actualites', requireAuth, requirePerm('actualites'), (req, res) => {
  let all = loadNews();
  const search   = (req.query.search   ?? '').trim();
  const category = req.query.category ?? '';
  const status   = req.query.status   ?? '';
  const page     = Math.max(1, parseInt(req.query.page) || 1);

  // Stats
  const statsObj = {
    total:     all.length,
    published: all.filter(n => n.isPublished).length,
    draft:     all.filter(n => !n.isPublished).length,
    pinned:    all.filter(n => n.isPinned).length,
    premium:   all.filter(n => n.isPremiumOnly).length,
    totalViews:all.reduce((s,n)=>s+(n.viewCount||0),0),
  };

  // Filtres
  if (search) all = all.filter(n => n.title.toLowerCase().includes(search.toLowerCase()) || (n.summary||'').toLowerCase().includes(search.toLowerCase()));
  if (category) all = all.filter(n => n.category === category);
  if (status === 'published') all = all.filter(n =>  n.isPublished);
  if (status === 'draft')     all = all.filter(n => !n.isPublished);
  if (status === 'pinned')    all = all.filter(n =>  n.isPinned);

  // Tri : épinglés d'abord, puis par date
  all = all.slice().sort((a, b) => {
    if (b.isPinned !== a.isPinned) return b.isPinned ? 1 : -1;
    return new Date(b.createdAt) - new Date(a.createdAt);
  });

  const total      = all.length;
  const totalPages = Math.max(1, Math.ceil(total / NEWS_PER_PAGE));
  const data       = all.slice((page-1)*NEWS_PER_PAGE, page*NEWS_PER_PAGE);

  res.render('actualites', {
    adminName: req.cookies.admin_name ?? 'Admin',
    adminRole: req.cookies.admin_role ?? 'sub',
    adminUsername: req.cookies.admin_username ?? '',
    data, stats: statsObj, total, page, perPage: NEWS_PER_PAGE, totalPages,
    search, category, status,
    success: req.query.success ?? null,
    error:   req.query.error   ?? null,
  });
});

app.get('/admin/actualites/new', requireAuth, requirePerm('actualites', 'write'), (req, res) => {
  res.render('actualite_form', {
    adminName: req.cookies.admin_name ?? 'Admin',
    adminRole: req.cookies.admin_role ?? 'sub',
    adminUsername: req.cookies.admin_username ?? '',
    article: null, isEdit: false,
    success: null, error: req.query.error ?? null,
  });
});

app.post('/admin/actualites', requireAuth, requirePerm('actualites', 'write'), (req, res) => {
  const { title, summary, content, category, imageUrl, sourceUrl, isPremiumOnly, isPinned } = req.body;
  if (!title?.trim()) return res.redirect('/admin/actualites/new?error=' + encodeURIComponent('Le titre est obligatoire.'));

  const now = new Date().toISOString();
  const all = loadNews();
  const article = {
    id:           uid(),
    title:        title.trim(),
    slug:         slugify(title),
    summary:      (summary || '').trim(),
    content:      (content || '').trim(),
    category:     category || 'news',
    imageUrl:     (imageUrl || '').trim(),
    sourceUrl:    (sourceUrl || '').trim(),
    isPublished:  !!req.body.isPublished,
    isPinned:     !!isPinned,
    isPremiumOnly:!!isPremiumOnly,
    authorName:   req.cookies.admin_name ?? 'Admin',
    viewCount:    0,
    likeCount:    0,
    createdAt:    now,
    updatedAt:    now,
    publishedAt:  req.body.isPublished ? now : null,
  };
  all.unshift(article);
  saveNews(all);
  logAction(req, 'news_created', article.title, { id: article.id, category: article.category });
  res.redirect('/admin/actualites?success=' + encodeURIComponent(`Article « ${article.title} » créé.`));
});

app.get('/admin/actualites/:id/edit', requireAuth, requirePerm('actualites', 'write'), (req, res) => {
  const all     = loadNews();
  const article = all.find(n => n.id === req.params.id);
  if (!article) return res.redirect('/admin/actualites?error=' + encodeURIComponent('Article introuvable.'));
  res.render('actualite_form', {
    adminName: req.cookies.admin_name ?? 'Admin',
    adminRole: req.cookies.admin_role ?? 'sub',
    adminUsername: req.cookies.admin_username ?? '',
    article, isEdit: true,
    success: req.query.success ?? null, error: req.query.error ?? null,
  });
});

app.post('/admin/actualites/:id/edit', requireAuth, requirePerm('actualites', 'write'), (req, res) => {
  const all = loadNews();
  const idx = all.findIndex(n => n.id === req.params.id);
  if (idx === -1) return res.redirect('/admin/actualites?error=' + encodeURIComponent('Article introuvable.'));
  const old = all[idx];
  const wasPublished = old.isPublished;
  const nowPublished = !!req.body.isPublished;
  const now = new Date().toISOString();
  all[idx] = {
    ...old,
    title:        (req.body.title || old.title).trim(),
    slug:         slugify(req.body.title || old.title),
    summary:      (req.body.summary || '').trim(),
    content:      (req.body.content || '').trim(),
    category:     req.body.category || old.category,
    imageUrl:     (req.body.imageUrl || '').trim(),
    isPublished:  nowPublished,
    isPinned:     !!req.body.isPinned,
    isPremiumOnly:!!req.body.isPremiumOnly,
    updatedAt:    now,
    publishedAt:  nowPublished ? (old.publishedAt ?? now) : null,
  };
  saveNews(all);
  logAction(req, 'news_updated', all[idx].title, { id: old.id });
  res.redirect('/admin/actualites/' + old.id + '/edit?success=' + encodeURIComponent('Article mis à jour.'));
});

app.post('/admin/actualites/:id/publish', requireAuth, requirePerm('actualites', 'write'), (req, res) => {
  const all = loadNews();
  const idx = all.findIndex(n => n.id === req.params.id);
  if (idx === -1) return res.redirect('/admin/actualites?error=' + encodeURIComponent('Article introuvable.'));
  const now = new Date().toISOString();
  all[idx].isPublished = !all[idx].isPublished;
  all[idx].publishedAt = all[idx].isPublished ? now : null;
  all[idx].updatedAt   = now;
  saveNews(all);
  logAction(req, all[idx].isPublished ? 'news_published' : 'news_unpublished', all[idx].title, { id: all[idx].id });
  res.redirect('/admin/actualites?success=' + encodeURIComponent(all[idx].isPublished ? 'Article publié.' : 'Article dépublié.'));
});

app.post('/admin/actualites/:id/pin', requireAuth, requirePerm('actualites', 'write'), (req, res) => {
  const all = loadNews();
  const idx = all.findIndex(n => n.id === req.params.id);
  if (idx === -1) return res.redirect('/admin/actualites?error=' + encodeURIComponent('Article introuvable.'));
  all[idx].isPinned  = !all[idx].isPinned;
  all[idx].updatedAt = new Date().toISOString();
  saveNews(all);
  logAction(req, all[idx].isPinned ? 'news_pinned' : 'news_unpinned', all[idx].title, { id: all[idx].id });
  res.redirect('/admin/actualites?success=' + encodeURIComponent(all[idx].isPinned ? 'Article épinglé.' : 'Article désépinglé.'));
});

app.post('/admin/actualites/:id/delete', requireAuth, requirePerm('actualites', 'delete'), (req, res) => {
  let all = loadNews();
  const article = all.find(n => n.id === req.params.id);
  if (!article) return res.redirect('/admin/actualites?error=' + encodeURIComponent('Article introuvable.'));
  all = all.filter(n => n.id !== req.params.id);
  saveNews(all);
  logAction(req, 'news_deleted', article.title, { id: article.id });
  res.redirect('/admin/actualites?success=' + encodeURIComponent('Article supprimé.'));
});

// ─── SOUS-ADMINS (réservé à l'admin principal) ────────────────────────────────
app.get('/admin/sub-admins', requireAuth, requireMain, (req, res) => {
  const subs = loadSubs().map(s => ({ ...s, passwordHash: undefined }));
  // Dernières actions par sous-admin (groupées par adminName)
  const allLogs = loadLogs();
  const recentLogsBySub = {};
  for (const sub of subs) {
    recentLogsBySub[sub.name] = allLogs.filter(l => l.adminName === sub.name).slice(0, 5);
  }
  res.render('sub_admins', {
    adminName: req.cookies.admin_name ?? 'Admin',
    subs, PERMISSIONS, recentLogsBySub,
    success: req.query.success ?? null,
    error:   req.query.error   ?? null,
  });
});

// Créer un sous-admin
app.post('/admin/sub-admins', requireAuth, requireMain, (req, res) => {
  const { name, username, password, permissions } = req.body;
  if (!name || !username || !password) {
    return res.redirect('/admin/sub-admins?error=' + encodeURIComponent('Nom, identifiant et mot de passe requis.'));
  }
  const subs = loadSubs();
  if (subs.find(s => s.username === username)) {
    return res.redirect('/admin/sub-admins?error=' + encodeURIComponent(`L'identifiant « ${username} » est déjà utilisé.`));
  }
  const perms = Array.isArray(permissions) ? permissions : (permissions ? [permissions] : []);
  const newSub = {
    id:           uid(),
    name:         name.trim(),
    username:     username.trim().toLowerCase(),
    passwordHash: hashPwd(password),
    permissions:  perms,
    isActive:     true,
    createdAt:    new Date().toISOString(),
    lastLoginAt:  null,
  };
  subs.push(newSub);
  saveSubs(subs);
  logAction(req, 'sub_admin_created', `${name} (${username})`, { name, username, permissions: perms });
  res.redirect('/admin/sub-admins?success=' + encodeURIComponent(`Sous-admin « ${name} » créé avec succès.`));
});

// Modifier les permissions
app.post('/admin/sub-admins/:id/permissions', requireAuth, requireMain, (req, res) => {
  const subs = loadSubs();
  const sub  = subs.find(s => s.id === req.params.id);
  if (!sub) return res.redirect('/admin/sub-admins?error=' + encodeURIComponent('Sous-admin introuvable.'));
  const perms = Array.isArray(req.body.permissions) ? req.body.permissions : (req.body.permissions ? [req.body.permissions] : []);
  sub.permissions = perms;
  saveSubs(subs);
  logAction(req, 'sub_admin_perms_updated', sub.name, { id: sub.id, permissions: perms });
  res.redirect('/admin/sub-admins?success=' + encodeURIComponent(`Permissions de « ${sub.name} » mises à jour.`));
});

// Changer le mot de passe
app.post('/admin/sub-admins/:id/password', requireAuth, requireMain, (req, res) => {
  const subs = loadSubs();
  const sub  = subs.find(s => s.id === req.params.id);
  if (!sub) return res.redirect('/admin/sub-admins?error=' + encodeURIComponent('Sous-admin introuvable.'));
  if (!req.body.password || req.body.password.length < 6) {
    return res.redirect('/admin/sub-admins?error=' + encodeURIComponent('Le mot de passe doit faire au moins 6 caractères.'));
  }
  sub.passwordHash = hashPwd(req.body.password);
  saveSubs(subs);
  logAction(req, 'sub_admin_pwd_changed', sub.name, { id: sub.id });
  res.redirect('/admin/sub-admins?success=' + encodeURIComponent(`Mot de passe de « ${sub.name} » modifié.`));
});

// Activer / désactiver
app.post('/admin/sub-admins/:id/toggle', requireAuth, requireMain, (req, res) => {
  const subs = loadSubs();
  const sub  = subs.find(s => s.id === req.params.id);
  if (!sub) return res.redirect('/admin/sub-admins?error=' + encodeURIComponent('Sous-admin introuvable.'));
  sub.isActive = !sub.isActive;
  saveSubs(subs);
  logAction(req, 'sub_admin_toggled', sub.name, { id: sub.id, isActive: sub.isActive });
  const state = sub.isActive ? 'activé' : 'désactivé';
  res.redirect('/admin/sub-admins?success=' + encodeURIComponent(`« ${sub.name} » ${state}.`));
});

// Supprimer
app.post('/admin/sub-admins/:id/delete', requireAuth, requireMain, (req, res) => {
  let subs = loadSubs();
  const sub = subs.find(s => s.id === req.params.id);
  if (!sub) return res.redirect('/admin/sub-admins?error=' + encodeURIComponent('Sous-admin introuvable.'));
  subs = subs.filter(s => s.id !== req.params.id);
  saveSubs(subs);
  logAction(req, 'sub_admin_deleted', sub.name, { id: sub.id, username: sub.username });
  res.redirect('/admin/sub-admins?success=' + encodeURIComponent(`« ${sub.name} » supprimé.`));
});

// ─── API PUBLIQUE — Actualités (pour l'app mobile) ────────────────────────────
// Pas de requireAuth : endpoint consommé par l'app Flutter
app.get('/api/v1/actualites', (req, res) => {
  const all = loadNews();
  const published = all
    .filter(a => a.isPublished)
    .sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt))
    .slice(0, 10)
    .map(a => ({
      id:         a.id,
      titre:      a.title,
      resume:     a.summary?.slice(0, 200) ?? a.content?.slice(0, 200) ?? '',
      categorie:  a.category ?? 'news',
      emoji:      a.emoji ?? '📰',
      image_url:  a.imageUrl ?? null,
      date:       _relTimeShort(new Date(a.createdAt)),
      created_at: a.createdAt,
    }));
  res.json(published);
});

function _relTimeShort(d) {
  const diff = Date.now() - d.getTime();
  const m = Math.floor(diff / 60000);
  if (m < 60)   return m <= 1 ? "À l'instant" : `Il y a ${m} min`;
  const h = Math.floor(m / 60);
  if (h < 24)   return h === 1 ? 'Il y a 1h' : `Il y a ${h}h`;
  const days = Math.floor(h / 24);
  if (days === 1) return 'Hier';
  if (days < 7)  return `Il y a ${days}j`;
  return d.toLocaleDateString('fr-FR', { day: 'numeric', month: 'short' });
}

// ─── RECHERCHE GLOBALE ────────────────────────────────────────────────────────
app.get('/admin/api/search', requireAuth, async (req, res) => {
  const q = (req.query.q ?? '').trim();
  if (q.length < 2) return res.json({ users: [], transactions: [], pronostics: [], bans: [] });

  const a      = api(req.cookies.admin_token);
  const canU   = res.locals.hasPerm('users');
  const canTx  = res.locals.hasPerm('transactions') || res.locals.hasPerm('historique');
  const canPro = res.locals.hasPerm('pronostics');

  // Recherche locale dans les bans
  const ql   = q.toLowerCase();
  const bans = canU
    ? loadBans()
        .filter(b =>
          b.pseudo?.toLowerCase().includes(ql) ||
          b.reason?.toLowerCase().includes(ql) ||
          b.bannedBy?.toLowerCase().includes(ql)
        )
        .slice(0, 5)
    : [];

  const [usersRes, txRes, proRes] = await Promise.allSettled([
    canU   ? a.get('/admin/users',               { params: { search: q, per_page: 5, page: 1 } }) : Promise.resolve({ data: { data: [] } }),
    canTx  ? a.get('/admin/history',             { params: { search: q, per_page: 5, page: 1 } }) : Promise.resolve({ data: { data: [] } }),
    canPro ? a.get('/pronostics/admin/upcoming', { params: { search: q }                       }) : Promise.resolve({ data: [] }),
  ]);

  const users = usersRes.status === 'fulfilled' ? (usersRes.value.data.data ?? []).slice(0, 5) : [];

  // Pour chaque user retourné, indiquer s'il est banni
  const now = Date.now();
  const activeBanSet = new Set(
    loadBans()
      .filter(b => b.active && (!b.expiresAt || new Date(b.expiresAt).getTime() > now))
      .map(b => b.userId)
  );

  res.json({
    users,
    transactions: txRes.status  === 'fulfilled' ? (txRes.value.data.data                                  ?? []).slice(0, 5) : [],
    pronostics:   proRes.status === 'fulfilled' ? (Array.isArray(proRes.value.data) ? proRes.value.data    : []).slice(0, 5) : [],
    bans,
    _bannedIds: [...activeBanSet],
  });
});

// ─── BADGES LIVE ──────────────────────────────────────────────────────────────
app.get('/admin/api/badges', requireAuth, async (req, res) => {
  const a = api(req.cookies.admin_token);
  const [txRes, proofsRes] = await Promise.allSettled([
    a.get('/payments/admin/pending?page=1&per_page=1'),
    a.get('/subscriptions/admin/proofs?page=1&per_page=1'),
  ]);
  res.json({
    transactions: txRes.status     === 'fulfilled' ? (txRes.value.data.total     ?? 0) : 0,
    proofs:       proofsRes.status === 'fulfilled' ? (proofsRes.value.data.total ?? 0) : 0,
  });
});

// ─── STATISTIQUES ─────────────────────────────────────────────────────────────
app.get('/admin/statistiques', requireAuth, requirePerm('statistiques'), (req, res) => {
  res.render('statistiques', { adminName: req.cookies.admin_name ?? 'Admin' });
});

app.get('/admin/api/stats/:endpoint', requireAuth, requirePerm('statistiques'), async (req, res) => {
  const a = api(req.cookies.admin_token);
  try {
    const r = await a.get('/admin/stats/' + req.params.endpoint, { params: req.query });
    res.json(r.data);
  } catch (e) {
    if (e.response?.status === 401) return res.status(401).json({ error: 'Non autorisé' });
    res.status(500).json({ error: e.response?.data?.message ?? e.message });
  }
});

// ─── AUDIT LOG ────────────────────────────────────────────────────────────────
app.get('/admin/audit', requireAuth, requireMain, (req, res) => {
  const { action = '', admin = '', cat = '', date = '', page = '1' } = req.query;
  const perPage = 50;
  const allLogs = loadLogs();

  // Stats globales (sur tous les logs, pas filtrés)
  const catCounts   = {};
  const adminCounts = {};
  const dayCounts   = {};  // 7 derniers jours
  const now         = new Date();
  for (let i = 6; i >= 0; i--) {
    const d = new Date(now); d.setDate(d.getDate() - i);
    dayCounts[d.toISOString().slice(0, 10)] = 0;
  }
  for (const l of allLogs) {
    const c = ACTION_LABELS[l.action]?.cat ?? 'autre';
    catCounts[c]   = (catCounts[c]   || 0) + 1;
    adminCounts[l.adminName ?? '?'] = (adminCounts[l.adminName ?? '?'] || 0) + 1;
    const day = l.timestamp?.slice(0, 10);
    if (day && dayCounts[day] !== undefined) dayCounts[day]++;
  }

  let logs = [...allLogs];
  // Filtres
  if (action) logs = logs.filter(l => l.action === action);
  if (admin)  logs = logs.filter(l => l.adminName?.toLowerCase().includes(admin.toLowerCase()));
  if (cat)    logs = logs.filter(l => (ACTION_LABELS[l.action]?.cat ?? '') === cat);
  if (date)   logs = logs.filter(l => l.timestamp?.startsWith(date));

  const total      = logs.length;
  const totalPages = Math.max(1, Math.ceil(total / perPage));
  const pageNum    = Math.min(Math.max(1, parseInt(page)), totalPages);
  const data       = logs.slice((pageNum - 1) * perPage, pageNum * perPage);

  // Admins uniques pour le filtre
  const adminList = [...new Set(allLogs.map(l => l.adminName).filter(Boolean))];

  res.render('audit', {
    data, total, page: pageNum, totalPages, perPage,
    ACTION_LABELS,
    filters: { action, admin, cat, date },
    success: req.query.success ?? null,
    // Stats pour le graphique
    chartDays:    Object.keys(dayCounts),
    chartCounts:  Object.values(dayCounts),
    catCounts, adminCounts, adminList,
    totalAll: allLogs.length,
  });
});

// Export CSV
app.get('/admin/audit/export', requireAuth, requireMain, (req, res) => {
  let logs = loadLogs();
  // Appliquer les mêmes filtres que la page audit
  const { cat='', admin='', date_from='', date_to='' } = req.query;
  if (cat)       logs = logs.filter(l => (ACTION_LABELS[l.action]?.cat ?? '') === cat);
  if (admin)     logs = logs.filter(l => l.adminName?.toLowerCase().includes(admin.toLowerCase()));
  if (date_from) logs = logs.filter(l => l.timestamp >= date_from);
  if (date_to)   logs = logs.filter(l => l.timestamp <= date_to + 'T23:59:59');
  const date    = new Date().toISOString().slice(0,10);
  const headers = ['Date/Heure','Admin','Rôle','Catégorie','Action','Cible','IP','Détails'];
  const rows    = logs.map(l => [
    l.timestamp ? new Date(l.timestamp).toLocaleString('fr-FR') : '',
    l.adminName ?? '',
    l.adminRole ?? '',
    ACTION_LABELS[l.action]?.cat ?? '',
    ACTION_LABELS[l.action]?.label ?? l.action,
    l.target ?? '',
    l.ip ?? '',
    l.details ? JSON.stringify(l.details) : '',
  ]);
  sendCSV(res, `audit_log_${date}.csv`, headers, rows);
});

// Vider le journal (admin principal uniquement)
app.post('/admin/audit/clear', requireAuth, requireMain, (req, res) => {
  saveLogs([]);
  logAction(req, 'login', 'Journal d\'activité vidé', {});  // ironique mais utile
  res.redirect('/admin/audit?success=' + encodeURIComponent('Journal vidé.'));
});

// ─── PROFIL ADMIN ─────────────────────────────────────────────────────────────
app.get('/admin/profile', requireAuth, (req, res) => {
  const role      = res.locals.adminRole;
  const subId     = req.cookies?.admin_sub_id ?? null;
  const sub       = subId ? loadSubs().find(s => s.id === subId) : null;
  const adminName = req.cookies?.admin_name ?? '';

  const allMyLogs  = loadLogs().filter(l => l.adminName === adminName);
  const lastLogins = allMyLogs.filter(l => l.action === 'login').slice(0, 10);
  const recentActivity = allMyLogs.filter(l => l.action !== 'login').slice(0, 8);

  // Stats personnelles
  const now       = Date.now();
  const today     = new Date().toISOString().slice(0, 10);
  const weekAgo   = new Date(now - 7 * 86400000).toISOString();
  const statsMe   = {
    total:   allMyLogs.length,
    today:   allMyLogs.filter(l => l.timestamp?.startsWith(today)).length,
    week:    allMyLogs.filter(l => l.timestamp >= weekAgo).length,
    logins:  lastLogins.length,
  };

  res.render('profile', {
    adminName,
    adminRole: role,
    adminPerms: res.locals.adminPerms,
    isMain: res.locals.isMain,
    sub: sub ? { ...sub, passwordHash: undefined } : null,
    lastLogins,
    recentActivity,
    statsMe,
    currentIp: getClientIP(req),
    PERMISSIONS,
    ACTION_LABELS,
    success: req.query.success ?? null,
    error:   req.query.error   ?? null,
  });
});

// Changer son propre mot de passe
app.post('/admin/profile/password', requireAuth, async (req, res) => {
  const { current_password, new_password, confirm_password } = req.body;

  if (!new_password || new_password.length < 6) {
    return res.redirect('/admin/profile?error=' + encodeURIComponent('Le nouveau mot de passe doit faire au moins 6 caractères.'));
  }
  if (new_password !== confirm_password) {
    return res.redirect('/admin/profile?error=' + encodeURIComponent('Les mots de passe ne correspondent pas.'));
  }

  const role  = res.locals.adminRole;
  const subId = req.cookies?.admin_sub_id ?? null;

  if (role === 'sub' && subId) {
    // Sous-admin : vérifier l'ancien mot de passe localement
    const subs = loadSubs();
    const sub  = subs.find(s => s.id === subId);
    if (!sub) return res.redirect('/admin/profile?error=' + encodeURIComponent('Compte introuvable.'));
    if (!checkPwd(current_password, sub.passwordHash)) {
      return res.redirect('/admin/profile?error=' + encodeURIComponent('Mot de passe actuel incorrect.'));
    }
    sub.passwordHash = hashPwd(new_password);
    saveSubs(subs);
    logAction(req, 'sub_admin_pwd_changed', `Autoprofil: ${sub.name}`, { id: sub.id });
    return res.redirect('/admin/profile?success=' + encodeURIComponent('Mot de passe modifié avec succès.'));
  }

  // Admin principal : passer par l'API backend
  try {
    const a = api(req.cookies.admin_token);
    await a.patch('/admin/profile/password', { current_password, new_password });
    logAction(req, 'sub_admin_pwd_changed', 'Autoprofil admin principal', {});
    res.redirect('/admin/profile?success=' + encodeURIComponent('Mot de passe modifié avec succès.'));
  } catch (e) {
    res.redirect('/admin/profile?error=' + encodeURIComponent(e.response?.data?.message ?? 'Erreur lors du changement de mot de passe.'));
  }
});

// ─── NOTIFICATIONS PUSH EN MASSE ─────────────────────────────────────────────
const SEGMENTS = [
  { key: 'all',            label: 'Tous les utilisateurs',       icon: '👥', desc: 'Tout le monde' },
  { key: 'premium',        label: 'Membres Premium uniquement',  icon: '👑', desc: 'Abonnés actifs' },
  { key: 'free',           label: 'Membres Gratuits uniquement', icon: '🆓', desc: 'Non-abonnés' },
  { key: 'active_30',      label: 'Actifs ce mois',              icon: '🟢', desc: 'Connexion < 30j' },
  { key: 'inactive_30',    label: 'Inactifs (> 30 jours)',       icon: '😴', desc: 'Connexion > 30j' },
  { key: 'new_7',          label: 'Nouveaux inscrits (7j)',       icon: '🆕', desc: 'Inscription < 7j' },
];

app.get('/admin/notifications', requireAuth, requirePerm('notifications'), (req, res) => {
  const allHistory = loadNotifHistory();
  const searchH    = (req.query.search_history ?? '').trim().toLowerCase();
  const history    = searchH
    ? allHistory.filter(h => h.title.toLowerCase().includes(searchH) || h.body.toLowerCase().includes(searchH))
    : allHistory;

  const now       = Date.now();
  const msWeek    = 7  * 24 * 3600 * 1000;
  const msMonth   = 30 * 24 * 3600 * 1000;
  const histStats = {
    total:      allHistory.length,
    totalSent:  allHistory.reduce((s, h) => s + (h.sent ?? 0), 0),
    thisWeek:   allHistory.filter(h => now - new Date(h.sentAt).getTime() < msWeek).length,
    thisMonth:  allHistory.filter(h => now - new Date(h.sentAt).getTime() < msMonth).length,
  };

  res.render('notifications', {
    SEGMENTS, history, histStats, searchH,
    success: req.query.success ?? null,
    error:   req.query.error   ?? null,
  });
});

// Supprimer une entrée de l'historique
app.post('/admin/notifications/history/:idx/delete', requireAuth, requirePerm('notifications', 'write'), (req, res) => {
  const idx  = parseInt(req.params.idx);
  const hist = loadNotifHistory();
  if (idx >= 0 && idx < hist.length) hist.splice(idx, 1);
  saveNotifHistory(hist);
  res.redirect('/admin/notifications?success=' + encodeURIComponent('Entrée supprimée.'));
});

// Aperçu : compter les destinataires avant envoi
app.get('/admin/api/notifications/preview', requireAuth, requirePerm('notifications'), async (req, res) => {
  const segment = req.query.segment ?? 'all';
  const a = api(req.cookies.admin_token);
  try {
    const r = await a.get('/admin/notifications/preview', { params: { segment } });
    res.json({ count: r.data.count ?? r.data.total ?? 0 });
  } catch {
    // Fallback : estimer depuis les stats users
    try {
      const s = await a.get('/admin/users/stats');
      const d = s.data;
      const estimates = {
        all:         d.total         ?? '—',
        premium:     d.premium       ?? '—',
        free:        (d.total - d.premium) || '—',
        active_30:   d.active        ?? '—',
        inactive_30: '—',
        new_7:       d.newWeek       ?? '—',
      };
      res.json({ count: estimates[segment] ?? '—', estimated: true });
    } catch { res.json({ count: '—', estimated: true }); }
  }
});

// Envoi
app.post('/admin/notifications/send', requireAuth, requirePerm('notifications', 'write'), async (req, res) => {
  const { title, body, segment = 'all', data_url = '', image_url = '' } = req.body;

  if (!title?.trim() || !body?.trim()) {
    return res.redirect('/admin/notifications?error=' + encodeURIComponent('Le titre et le message sont obligatoires.'));
  }
  if (title.length > 100) {
    return res.redirect('/admin/notifications?error=' + encodeURIComponent('Le titre ne doit pas dépasser 100 caractères.'));
  }
  if (body.length > 300) {
    return res.redirect('/admin/notifications?error=' + encodeURIComponent('Le message ne doit pas dépasser 300 caractères.'));
  }

  const a = api(req.cookies.admin_token);
  try {
    const r = await a.post('/admin/notifications/send', {
      title: title.trim(),
      body:  body.trim(),
      segment,
      ...(data_url  ? { data: { url: data_url } }  : {}),
      ...(image_url ? { image: image_url }          : {}),
    });

    const sent    = r.data.sent ?? r.data.count ?? 0;
    const segMeta = SEGMENTS.find(s => s.key === segment) ?? { label: segment };

    // Historique local
    const history = loadNotifHistory();
    history.unshift({
      id:        uid(),
      title:     title.trim(),
      body:      body.trim(),
      segment,
      segLabel:  segMeta.label,
      sent,
      adminName: req.cookies?.admin_name ?? 'Admin',
      sentAt:    new Date().toISOString(),
    });
    saveNotifHistory(history);

    logAction(req, 'notification_sent', `"${title.trim()}" → ${segMeta.label}`, { title, segment, sent });

    res.redirect('/admin/notifications?success=' + encodeURIComponent(`✅ Notification envoyée à ${sent.toLocaleString('fr-FR')} utilisateurs.`));
  } catch (e) {
    res.redirect('/admin/notifications?error=' + encodeURIComponent(e.response?.data?.message ?? 'Erreur lors de l\'envoi.'));
  }
});

// ─── REDIRECTIONS ─────────────────────────────────────────────────────────────
app.get('/',      (req, res) => res.redirect('/admin/dashboard'));
app.get('/admin', (req, res) => res.redirect('/admin/dashboard'));

// ─── BANS ─────────────────────────────────────────────────────────────────────
app.get('/admin/bans', requireAuth, requirePerm('users'), (req, res) => {
  const { filter = 'active', search = '', page = '1' } = req.query;
  let bans = loadBans();
  const now = Date.now();

  // Filtrer
  if (filter === 'active') {
    bans = bans.filter(b => b.active && (b.expiresAt === null || new Date(b.expiresAt).getTime() > now));
  } else if (filter === 'expired') {
    bans = bans.filter(b => !b.active || (b.expiresAt && new Date(b.expiresAt).getTime() <= now));
  }
  if (search) {
    const q = search.toLowerCase();
    bans = bans.filter(b =>
      b.pseudo?.toLowerCase().includes(q) ||
      b.reason?.toLowerCase().includes(q) ||
      b.bannedBy?.toLowerCase().includes(q)
    );
  }

  // Pagination
  const perPage    = 20;
  const total      = bans.length;
  const totalPages = Math.max(1, Math.ceil(total / perPage));
  const pg         = Math.min(Math.max(1, parseInt(page)), totalPages);
  const paginated  = bans.slice((pg - 1) * perPage, pg * perPage);

  // Stats
  const allBans    = loadBans();
  const activeBans = allBans.filter(b => b.active && (b.expiresAt === null || new Date(b.expiresAt).getTime() > now));

  const in7days = now + 7 * 24 * 60 * 60 * 1000;
  res.render('bans', {
    bans: paginated, total, page: pg, perPage, totalPages,
    filter, search,
    stats: {
      active:       activeBans.length,
      permanent:    activeBans.filter(b => b.expiresAt === null).length,
      temporary:    activeBans.filter(b => b.expiresAt !== null).length,
      total:        allBans.length,
      expiringSoon: activeBans.filter(b => b.expiresAt && new Date(b.expiresAt).getTime() <= in7days).length,
      today:        allBans.filter(b => b.bannedAt && (now - new Date(b.bannedAt).getTime()) < 86400000).length,
    },
    settings: loadSettings(),
    success: req.query.success ?? null,
    error:   req.query.error   ?? null,
  });
});

// Export CSV bans
app.get('/admin/bans/export', requireAuth, requirePerm('users'), (req, res) => {
  const bans = loadBans();
  const headers = ['ID', 'UserId', 'Pseudo', 'Raison', 'Durée (jours)', 'Banni le', 'Expire le', 'Statut', 'Banni par', 'Débanni le', 'Débanni par', 'Note débannissement'];
  const rows = bans.map(b => [
    b.id, b.userId, b.pseudo, b.reason,
    b.durationDays ?? 'Permanent',
    b.bannedAt ? new Date(b.bannedAt).toLocaleString('fr-FR') : '',
    b.expiresAt ? new Date(b.expiresAt).toLocaleString('fr-FR') : 'Permanent',
    b.active ? 'Actif' : 'Levé/Expiré',
    b.bannedBy ?? '',
    b.unbannedAt ? new Date(b.unbannedAt).toLocaleString('fr-FR') : '',
    b.unbannedBy ?? '',
    b.unbanReason ?? '',
  ]);
  sendCSV(res, `bans_${new Date().toISOString().slice(0,10)}.csv`, headers, rows);
});

// API : vérifier si un user est banni (utilisé par la fiche user)
app.get('/admin/api/bans/:userId', requireAuth, requirePerm('users'), (req, res) => {
  const ban = getActiveBan(req.params.userId);
  res.json({ banned: !!ban, ban: ban ?? null });
});

// Bannir un utilisateur
app.post('/admin/users/:id/ban', requireAuth, requirePerm('users', 'write'), async (req, res) => {
  const { reason, duration_days, pseudo } = req.body;
  if (!reason?.trim()) {
    return res.redirect(back(req, 'Une raison est obligatoire pour bannir un utilisateur.', true));
  }
  const dur = parseInt(duration_days ?? '7');
  const ban = banUser({
    userId:      req.params.id,
    pseudo:      sanitize(pseudo ?? req.params.id, 60),
    reason:      sanitize(reason, 500),
    durationDays: isNaN(dur) ? 7 : dur,
    adminName:   req.cookies?.admin_name ?? 'Admin',
    adminIp:     getClientIP(req),
  });
  // Notifier le backend (suspension du compte)
  try {
    const a = api(req.cookies.admin_token);
    await a.patch('/admin/users/' + req.params.id + '/suspend', { suspended: true });
  } catch { /* le backend peut ne pas avoir cette route */ }
  logAction(req, 'user_banned', `User #${req.params.id} (${pseudo})`, { reason, durationDays: dur, banId: ban.id });
  sseBroadcast('ban_update', { type: 'banned', userId: req.params.id, pseudo, ts: Date.now() });
  const redir = req.body.redirect_to ?? `/admin/users/${req.params.id}`;
  res.redirect(redir + (redir.includes('?') ? '&' : '?') + 'success=' + encodeURIComponent(`Utilisateur « ${pseudo} » banni avec succès.`));
});

// Débannir un utilisateur
app.post('/admin/users/:id/unban', requireAuth, requirePerm('users', 'write'), async (req, res) => {
  const { pseudo, unban_reason } = req.body;
  unbanUser(req.params.id, req.cookies?.admin_name ?? 'Admin', sanitize(unban_reason ?? '', 500));
  // Réactiver le compte côté backend
  try {
    const a = api(req.cookies.admin_token);
    await a.patch('/admin/users/' + req.params.id + '/suspend', { suspended: false });
  } catch {}
  logAction(req, 'user_unbanned', `User #${req.params.id} (${pseudo})`, { reason: unban_reason });
  sseBroadcast('ban_update', { type: 'unbanned', userId: req.params.id, pseudo, ts: Date.now() });
  const redir = req.body.redirect_to ?? `/admin/users/${req.params.id}`;
  res.redirect(redir + (redir.includes('?') ? '&' : '?') + 'success=' + encodeURIComponent(`Utilisateur « ${pseudo} » débanni.`));
});

// Helper redirect avec erreur
function back(req, msg, isError = false) {
  const ref = req.headers.referer ?? '/admin/dashboard';
  return ref + (ref.includes('?') ? '&' : '?') + (isError ? 'error' : 'success') + '=' + encodeURIComponent(msg);
}

// ─── PARAMÈTRES GÉNÉRAUX ──────────────────────────────────────────────────────
app.get('/admin/settings', requireAuth, requireMain, (req, res) => {
  // Infos système pour l'affichage
  const dataFiles = [
    { key: 'sub_admins',     file: SA_FILE,       label: 'Sous-admins' },
    { key: 'audit_log',      file: LOG_FILE,       label: 'Journal d\'audit' },
    { key: 'notifications',  file: NOTIF_FILE,     label: 'Notifs historique' },
    { key: 'bans',           file: BANS_FILE,      label: 'Bannissements' },
    { key: 'actualites',     file: NEWS_FILE,      label: 'Actualités' },
    { key: 'settings',       file: SETTINGS_FILE,  label: 'Paramètres' },
  ].map(f => {
    try {
      const stat = fs.statSync(f.file);
      const data = JSON.parse(fs.readFileSync(f.file, 'utf8'));
      const count = Array.isArray(data) ? data.length : null;
      return { ...f, size: (stat.size / 1024).toFixed(1) + ' Ko', count, exists: true };
    } catch { return { ...f, size: '—', count: null, exists: false }; }
  });

  const sysInfo = {
    nodeVersion:  process.version,
    uptime:       Math.floor(process.uptime() / 60) + ' min',
    memMb:        (process.memoryUsage().rss / 1024 / 1024).toFixed(1) + ' Mo',
    port:         process.env.ADMIN_PORT ?? 4000,
    env:          process.env.NODE_ENV ?? 'development',
  };

  res.render('settings', {
    settings: loadSettings(),
    dataFiles, sysInfo,
    success:  req.query.success ?? null,
    error:    req.query.error   ?? null,
  });
});

// Sauvegarder la section maintenance
app.post('/admin/settings/maintenance', requireAuth, requireMain, (req, res) => {
  const s = loadSettings();
  s.maintenanceMode    = req.body.maintenanceMode === '1';
  s.maintenanceMessage = sanitize(req.body.maintenanceMessage ?? '', 500);
  s.updatedAt = new Date().toISOString();
  s.updatedBy = req.cookies?.admin_name ?? 'Admin';
  saveSettings(s);
  logAction(req, 'settings_changed', 'maintenance', { mode: s.maintenanceMode });
  res.redirect('/admin/settings?success=' + encodeURIComponent('Paramètres de maintenance sauvegardés.'));
});

// Sauvegarder l'annonce globale
app.post('/admin/settings/announcement', requireAuth, requireMain, (req, res) => {
  const s = loadSettings();
  s.announcementEnabled = req.body.announcementEnabled === '1';
  s.announcementText    = sanitize(req.body.announcementText ?? '', 300);
  s.announcementType    = ['info','warning','danger'].includes(req.body.announcementType) ? req.body.announcementType : 'info';
  s.updatedAt = new Date().toISOString();
  s.updatedBy = req.cookies?.admin_name ?? 'Admin';
  saveSettings(s);
  logAction(req, 'settings_changed', 'announcement', { enabled: s.announcementEnabled, text: s.announcementText });
  res.redirect('/admin/settings?success=' + encodeURIComponent('Annonce globale mise à jour.'));
});

// Sauvegarder apparence + sécurité
app.post('/admin/settings/general', requireAuth, requireMain, (req, res) => {
  const s = loadSettings();
  s.panelTitle        = sanitize(req.body.panelTitle ?? 'PronoWin Admin', 60);
  s.timezone          = sanitize(req.body.timezone   ?? 'Europe/Paris',   50);
  s.sessionTimeoutMin = Math.min(480, Math.max(5,  parseInt(req.body.sessionTimeoutMin ?? '30')));
  s.loginMaxAttempts  = Math.min(20,  Math.max(1,  parseInt(req.body.loginMaxAttempts  ?? '5')));
  s.loginBlockMinutes = Math.min(120, Math.max(1,  parseInt(req.body.loginBlockMinutes ?? '15')));
  s.updatedAt = new Date().toISOString();
  s.updatedBy = req.cookies?.admin_name ?? 'Admin';
  saveSettings(s);
  logAction(req, 'settings_changed', 'general', { panelTitle: s.panelTitle });
  res.redirect('/admin/settings?success=' + encodeURIComponent('Paramètres généraux sauvegardés.'));
});

// Télécharger une sauvegarde ZIP des données admin
app.get('/admin/settings/backup', requireAuth, requireMain, (req, res) => {
  try {
    const files = [SA_FILE, LOG_FILE, NOTIF_FILE, SETTINGS_FILE, BANS_FILE, NEWS_FILE];
    const date  = new Date().toISOString().slice(0, 10);
    // Archive ZIP manuelle (format ZIP minimal sans dépendance)
    // On génère un tar.json : un objet JSON avec les fichiers encodés en base64
    const backup = {};
    for (const f of files) {
      if (fs.existsSync(f)) {
        backup[path.basename(f)] = fs.readFileSync(f, 'utf8');
      }
    }
    backup._meta = { createdAt: new Date().toISOString(), version: '1.0', files: Object.keys(backup) };
    const json = JSON.stringify(backup, null, 2);
    res.setHeader('Content-Type', 'application/json');
    res.setHeader('Content-Disposition', `attachment; filename="pronowin_admin_backup_${date}.json"`);
    res.send(json);
    logAction(req, 'settings_changed', 'backup_downloaded', {});
  } catch (e) {
    res.redirect('/admin/settings?error=' + encodeURIComponent('Erreur lors de la sauvegarde : ' + e.message));
  }
});

// Restaurer depuis un fichier backup JSON
app.post('/admin/settings/restore', requireAuth, requireMain, (req, res) => {
  try {
    const raw = req.body.backup_json;
    if (!raw) return res.redirect('/admin/settings?error=' + encodeURIComponent('Aucun fichier fourni.'));
    const backup = JSON.parse(raw);
    const allowed = ['sub_admins.json', 'audit_log.json', 'notifications_history.json', 'settings.json', 'bans.json', 'actualites.json'];
    let restored  = 0;
    for (const [filename, content] of Object.entries(backup)) {
      if (!allowed.includes(filename)) continue;
      // Valider que c'est bien du JSON valide
      JSON.parse(content);
      fs.writeFileSync(path.join(DATA_DIR, filename), content, 'utf8');
      restored++;
    }
    logAction(req, 'settings_changed', 'restore', { files: restored });
    res.redirect('/admin/settings?success=' + encodeURIComponent(`Restauration réussie : ${restored} fichier(s) restauré(s). Rechargez le serveur si nécessaire.`));
  } catch (e) {
    res.redirect('/admin/settings?error=' + encodeURIComponent('Erreur lors de la restauration : ' + e.message));
  }
});

// ─── DANGER ZONE ──────────────────────────────────────────────────────────────
app.post('/admin/settings/clear-logs', requireAuth, requireMain, (req, res) => {
  saveLogs([]);
  logAction(req, 'settings_changed', 'clear_logs', {});
  res.redirect('/admin/settings?success=' + encodeURIComponent('Journal d\'audit effacé.'));
});

app.post('/admin/settings/clear-notifs', requireAuth, requireMain, (req, res) => {
  saveNotifHistory([]);
  logAction(req, 'settings_changed', 'clear_notifs', {});
  res.redirect('/admin/settings?success=' + encodeURIComponent('Historique notifications effacé.'));
});

app.post('/admin/settings/clear-actualites', requireAuth, requireMain, (req, res) => {
  saveNews([]);
  logAction(req, 'settings_changed', 'clear_actualites', {});
  res.redirect('/admin/settings?success=' + encodeURIComponent('Toutes les actualités supprimées.'));
});

// ─── SSE — doit être AVANT le handler 404 ─────────────────────────────────────
// Endpoint SSE — maintient la connexion ouverte
app.get('/admin/api/live', requireAuth, (req, res) => {
  res.setHeader('Content-Type',  'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection',    'keep-alive');
  res.setHeader('X-Accel-Buffering', 'no');
  res.flushHeaders();
  res.write('event: connected\ndata: {"ok":true}\n\n');
  sseClients.add(res);
  fetchLiveKPIs(req.cookies.admin_token).then(kpis => {
    if (kpis) { try { res.write(`event: kpis\ndata: ${JSON.stringify(kpis)}\n\n`); } catch {} }
  });
  req.on('close', () => sseClients.delete(res));
});

// ─── 404 ──────────────────────────────────────────────────────────────────────
app.use((req, res) => {
  const isApi = req.path.startsWith('/admin/api/');
  if (isApi) return res.status(404).json({ error: 'Route introuvable.' });
  res.status(404).render('error', {
    status:  404,
    title:   'Page introuvable',
    message: `La page « ${req.path} » n'existe pas.`,
    hint:    'Vérifiez l\'URL ou revenez au dashboard.',
    back:    '/admin/dashboard',
  });
});

// ─── GESTIONNAIRE D'ERREURS GLOBAL ────────────────────────────────────────────
// eslint-disable-next-line no-unused-vars
app.use((err, req, res, _next) => {
  console.error('[ERROR]', req.method, req.path, err.message ?? err);

  const isApi = req.path.startsWith('/admin/api/');
  if (isApi) return res.status(500).json({ error: 'Erreur serveur interne.' });

  // Erreur de token expiré
  if (err.response?.status === 401) {
    res.clearCookie('admin_token');
    return res.redirect('/admin/login?expired=1');
  }

  res.status(500).render('error', {
    status:  500,
    title:   'Erreur serveur',
    message: process.env.NODE_ENV === 'development'
      ? (err.message ?? 'Erreur interne.')
      : 'Une erreur inattendue s\'est produite.',
    hint:    'Si le problème persiste, contactez le support technique.',
    back:    req.headers.referer ?? '/admin/dashboard',
  });
});

// ─── SSE : TEMPS RÉEL ─────────────────────────────────────────────────────────
// Fetch des KPIs live (appelé toutes les 10s par le timer interne)
async function fetchLiveKPIs(token) {
  try {
    const a = api(token);
    const [usersRes, txRes, proofsRes] = await Promise.allSettled([
      a.get('/admin/users?page=1&per_page=1'),
      a.get('/payments/admin/pending?page=1&per_page=1'),
      a.get('/subscriptions/admin/proofs?page=1&per_page=1'),
    ]);
    return {
      users_total:       usersRes.status   === 'fulfilled' ? (usersRes.value.data.total    ?? 0) : null,
      tx_pending:        txRes.status      === 'fulfilled' ? (txRes.value.data.total       ?? 0) : null,
      proofs_pending:    proofsRes.status  === 'fulfilled' ? (proofsRes.value.data.total   ?? 0) : null,
      ts: Date.now(),
    };
  } catch { return null; }
}

// Timer interne : push KPIs toutes les 10 secondes si au moins 1 client connecté
// On utilise le token de l'admin principal (ADMIN_API_TOKEN) pour les appels périodiques
setInterval(async () => {
  if (sseClients.size === 0) return;
  const token = process.env.ADMIN_API_TOKEN ?? '';
  const kpis  = await fetchLiveKPIs(token);
  if (kpis) sseBroadcast('kpis', kpis);
}, 10000);

// Ping SSE toutes les 30s pour garder la connexion vivante (anti-timeout proxy)
setInterval(() => {
  if (sseClients.size === 0) return;
  const msg = ': ping\n\n';
  for (const res of sseClients) {
    try { res.write(msg); } catch { sseClients.delete(res); }
  }
}, 30000);

// Exposer sseBroadcast pour les routes (broadcast après chaque action mutante)
app.locals.sseBroadcast = sseBroadcast;

// ─── DÉMARRAGE ────────────────────────────────────────────────────────────────
app.listen(PORT, () => {
  console.log(`\n🖥️  PronoWin Admin — http://localhost:${PORT}/admin`);
  console.log(`📡 dashboard | users | pronostics | transactions | historique | abonnements | tutoriels | sub-admins | audit | notifications\n`);
});
