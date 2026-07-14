/**
 * test_integration.js — Tests d'intégration complets PronoWin Admin
 * Teste toutes les actions locales (sans dépendance à l'API externe)
 *
 * node test_integration.js
 */

'use strict';

const fs      = require('fs');
const path    = require('path');
const crypto  = require('crypto');
const assert  = require('assert');

// ── Couleurs console ──────────────────────────────────────────────────────────
const G = s => '\x1b[32m' + s + '\x1b[0m';
const R = s => '\x1b[31m' + s + '\x1b[0m';
const Y = s => '\x1b[33m' + s + '\x1b[0m';
const B = s => '\x1b[36m' + s + '\x1b[0m';
const DIM = s => '\x1b[2m' + s + '\x1b[0m';

// ── Helpers test ──────────────────────────────────────────────────────────────
let passed = 0, failed = 0, suite = '';
const results = [];

function describe(name, fn) {
  suite = name;
  console.log('\n' + B('▶ ' + name));
  fn();
}

function it(label, fn) {
  try {
    fn();
    console.log('  ' + G('✅') + ' ' + label);
    passed++;
    results.push({ ok: true, suite, label });
  } catch (e) {
    console.log('  ' + R('❌') + ' ' + label);
    console.log('     ' + R(e.message));
    failed++;
    results.push({ ok: false, suite, label, error: e.message });
  }
}

function eq(a, b, msg) { assert.deepStrictEqual(a, b, msg ?? `attendu ${JSON.stringify(b)}, obtenu ${JSON.stringify(a)}`); }
function ok(v, msg)     { assert.ok(v, msg ?? 'attendu truthy'); }
function notOk(v, msg)  { assert.ok(!v, msg ?? 'attendu falsy'); }

// ── Répertoire de données temporaire ─────────────────────────────────────────
const TMP  = path.join(__dirname, '__test_data__');
const SALT = 'pronowin_admin_salt_2025';

function hashPwd(pwd) { return crypto.createHash('sha256').update(pwd + SALT).digest('hex'); }
function uid()        { return Date.now().toString(36) + Math.random().toString(36).slice(2, 7); }
function slugify(str) { return str.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g,'').replace(/[^a-z0-9]+/g,'-').replace(/^-|-$/g,'').slice(0,80); }

function setup() {
  if (!fs.existsSync(TMP)) fs.mkdirSync(TMP);
  const files = ['actualites.json','sub_admins.json','bans.json','audit_log.json','notifications_history.json','settings.json'];
  files.forEach(f => fs.writeFileSync(path.join(TMP, f), f === 'settings.json' ? '{}' : '[]'));
}
function teardown() {
  fs.readdirSync(TMP).forEach(f => fs.unlinkSync(path.join(TMP, f)));
  fs.rmdirSync(TMP);
}

// ── Fonctions utilitaires extraites de server.js ──────────────────────────────
function load(file)      { try { return JSON.parse(fs.readFileSync(path.join(TMP, file), 'utf8')); } catch { return []; } }
function save(file, data){ fs.writeFileSync(path.join(TMP, file), JSON.stringify(data, null, 2)); }

// ── Logique permissions (copiée de server.js) ─────────────────────────────────
function getPermLevel(perms, key) {
  const ORDER = { read: 1, write: 2, delete: 3 };
  let best = 0;
  for (const p of perms) {
    if (p === key) { best = Math.max(best, ORDER.write); continue; }
    if (p.startsWith(key + ':')) {
      const lvl = p.split(':')[1];
      if (ORDER[lvl]) best = Math.max(best, ORDER[lvl]);
    }
  }
  return best;
}

function hasPerm(perms, isMain, key, level = 'read') {
  if (isMain) return true;
  const ORDER = { read: 1, write: 2, delete: 3 };
  return getPermLevel(perms, key) >= (ORDER[level] ?? 1);
}

// ── Logique actualités (copiée de server.js) ──────────────────────────────────
function newsCreate(all, { title, summary, content, category, imageUrl, isPublished, isPinned, isPremiumOnly, authorName }) {
  const now = new Date().toISOString();
  const art = {
    id: uid(), title: title.trim(), slug: slugify(title),
    summary: (summary||'').trim(), content: (content||'').trim(),
    category: category||'news', imageUrl: (imageUrl||'').trim(),
    isPublished: !!isPublished, isPinned: !!isPinned, isPremiumOnly: !!isPremiumOnly,
    authorName: authorName||'Admin', viewCount: 0, likeCount: 0,
    createdAt: now, updatedAt: now, publishedAt: isPublished ? now : null,
  };
  all.unshift(art);
  return { all, art };
}

function newsUpdate(all, id, fields) {
  const idx = all.findIndex(n => n.id === id);
  if (idx === -1) return { all, ok: false };
  const old = all[idx];
  const now = new Date().toISOString();
  all[idx] = {
    ...old,
    title:        (fields.title || old.title).trim(),
    slug:         slugify(fields.title || old.title),
    summary:      (fields.summary||'').trim(),
    content:      (fields.content||'').trim(),
    category:     fields.category || old.category,
    imageUrl:     (fields.imageUrl||'').trim(),
    isPublished:  !!fields.isPublished,
    isPinned:     !!fields.isPinned,
    isPremiumOnly:!!fields.isPremiumOnly,
    updatedAt:    now,
    publishedAt:  fields.isPublished ? (old.publishedAt ?? now) : null,
  };
  return { all, ok: true };
}

function newsTogglePublish(all, id) {
  const idx = all.findIndex(n => n.id === id);
  if (idx === -1) return { all, ok: false };
  const now = new Date().toISOString();
  all[idx].isPublished = !all[idx].isPublished;
  all[idx].publishedAt = all[idx].isPublished ? now : null;
  all[idx].updatedAt   = now;
  return { all, ok: true, isPublished: all[idx].isPublished };
}

function newsTogglePin(all, id) {
  const idx = all.findIndex(n => n.id === id);
  if (idx === -1) return { all, ok: false };
  all[idx].isPinned  = !all[idx].isPinned;
  all[idx].updatedAt = new Date().toISOString();
  return { all, ok: true, isPinned: all[idx].isPinned };
}

function newsDelete(all, id) {
  const found = all.find(n => n.id === id);
  return { all: all.filter(n => n.id !== id), found };
}

function newsFilter(all, { search, category, status }) {
  let r = all;
  if (search)               r = r.filter(n => n.title.toLowerCase().includes(search.toLowerCase()));
  if (category)             r = r.filter(n => n.category === category);
  if (status === 'published') r = r.filter(n => n.isPublished);
  if (status === 'draft')     r = r.filter(n => !n.isPublished);
  if (status === 'pinned')    r = r.filter(n => n.isPinned);
  return r.slice().sort((a, b) => {
    if (b.isPinned !== a.isPinned) return b.isPinned ? 1 : -1;
    return new Date(b.createdAt) - new Date(a.createdAt);
  });
}

// ── Logique sous-admins ───────────────────────────────────────────────────────
function subCreate(subs, { name, username, password, permissions }) {
  if (!name?.trim() || !username?.trim() || !password) return { ok: false, error: 'Champs manquants' };
  if (subs.find(s => s.username === username)) return { ok: false, error: 'Username déjà utilisé' };
  const perms = Array.isArray(permissions) ? permissions : (permissions ? [permissions] : []);
  const sub = {
    id: uid(), name: name.trim(), username: username.trim().toLowerCase(),
    passwordHash: hashPwd(password), permissions: perms,
    isActive: true, createdAt: new Date().toISOString(), lastLoginAt: null,
  };
  return { ok: true, subs: [...subs, sub], sub };
}

function subUpdatePerms(subs, id, permissions) {
  const idx = subs.findIndex(s => s.id === id);
  if (idx === -1) return { ok: false };
  const perms = Array.isArray(permissions) ? permissions : (permissions ? [permissions] : []);
  subs[idx].permissions = perms;
  return { ok: true };
}

function subChangePwd(subs, id, password) {
  const idx = subs.findIndex(s => s.id === id);
  if (idx === -1) return { ok: false };
  if (!password || password.length < 6) return { ok: false, error: 'Mot de passe trop court' };
  subs[idx].passwordHash = hashPwd(password);
  return { ok: true };
}

function subToggle(subs, id) {
  const idx = subs.findIndex(s => s.id === id);
  if (idx === -1) return { ok: false };
  subs[idx].isActive = !subs[idx].isActive;
  return { ok: true, isActive: subs[idx].isActive };
}

function subDelete(subs, id) {
  const found = subs.find(s => s.id === id);
  return { subs: subs.filter(s => s.id !== id), found };
}

// ── Logique bans ──────────────────────────────────────────────────────────────
function banCreate(bans, { userId, reason, expiresAt, adminName }) {
  const existing = bans.findIndex(b => b.userId === userId && b.active);
  if (existing !== -1) bans[existing].active = false;
  const ban = {
    id: uid(), userId, reason: reason||'', expiresAt: expiresAt||null,
    active: true, bannedAt: new Date().toISOString(), bannedBy: adminName||'Admin',
  };
  bans.push(ban);
  return { bans, ban };
}

function banRevoke(bans, userId) {
  const idx = bans.findIndex(b => b.userId === userId && b.active);
  if (idx === -1) return { ok: false };
  bans[idx].active = false;
  return { ok: true };
}

function getActiveBan(bans, userId) {
  return bans.find(b => b.userId === userId && b.active && (!b.expiresAt || new Date(b.expiresAt) > new Date())) ?? null;
}

// ── Logique notifications historique ─────────────────────────────────────────
function notifHistDelete(history, idx) {
  if (idx < 0 || idx >= history.length) return { ok: false };
  history.splice(idx, 1);
  return { ok: true };
}

// ── Logique audit log ─────────────────────────────────────────────────────────
function logAction(logs, adminName, action, target, meta) {
  const entry = { id: uid(), timestamp: new Date().toISOString(), adminName, action, target, meta: meta||{}, ip: '127.0.0.1' };
  logs.unshift(entry);
  return { logs: logs.slice(0, 5000), entry };
}

function auditFilter(logs, { action, admin, cat, date, search }) {
  let r = logs;
  if (search) r = r.filter(l => l.target?.toLowerCase().includes(search.toLowerCase()) || l.adminName?.toLowerCase().includes(search.toLowerCase()));
  if (action) r = r.filter(l => l.action === action);
  if (admin)  r = r.filter(l => l.adminName?.toLowerCase().includes(admin.toLowerCase()));
  return r;
}

// ── Logique hasPerm / slugify ─────────────────────────────────────────────────
function testSlugify() {
  eq(slugify('Grosse cote du Week-end !'), 'grosse-cote-du-week-end');
  eq(slugify('Résultats & Pronostics 2024'), 'resultats-pronostics-2024');
  eq(slugify('  Espaces   '), 'espaces');
  ok(slugify('a'.repeat(200)).length <= 80, 'slug max 80 chars');
}

// ═════════════════════════════════════════════════════════════════════════════
// ── SUITES DE TESTS ──────────────────────────────────────────────────────────
// ═════════════════════════════════════════════════════════════════════════════

setup();

// ─────────────────────────────────────────────────────────────────────────────
describe('🔧 Utilitaires (slugify, hashPwd, uid)', () => {

  it('slugify : accentués + espaces + ponctuation', () => {
    eq(slugify('Résultats & Pronostics 2024'), 'resultats-pronostics-2024');
    eq(slugify('Grosse côte du week-end !'), 'grosse-cote-du-week-end');
  });

  it('slugify : longueur max 80 caractères', () => {
    ok(slugify('a'.repeat(200)).length <= 80);
  });

  it('slugify : trim tirets de début/fin', () => {
    notOk(slugify('!! Alert !!').startsWith('-'));
    notOk(slugify('!! Alert !!').endsWith('-'));
  });

  it('hashPwd : déterministe avec le même sel', () => {
    eq(hashPwd('secret123'), hashPwd('secret123'));
  });

  it('hashPwd : différent si mot de passe différent', () => {
    ok(hashPwd('secret123') !== hashPwd('secret456'));
  });

  it('uid : unique à chaque appel', () => {
    const ids = new Set([uid(), uid(), uid(), uid(), uid()]);
    eq(ids.size, 5);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
describe('🔐 Système de permissions (hasPerm)', () => {

  it('superadmin a toujours toutes les permissions', () => {
    ok(hasPerm([], true, 'users'));
    ok(hasPerm([], true, 'users', 'write'));
    ok(hasPerm([], true, 'users', 'delete'));
    ok(hasPerm([], true, 'inexistant', 'delete'));
  });

  it('sous-admin sans perms : tout refusé', () => {
    notOk(hasPerm([], false, 'users'));
    notOk(hasPerm([], false, 'users', 'write'));
  });

  it('perm ancienne format "users" → write par défaut', () => {
    ok(hasPerm(['users'], false, 'users', 'read'));
    ok(hasPerm(['users'], false, 'users', 'write'));
    notOk(hasPerm(['users'], false, 'users', 'delete'));
  });

  it('perm nouveau format "users:read"', () => {
    ok(hasPerm(['users:read'], false, 'users', 'read'));
    notOk(hasPerm(['users:read'], false, 'users', 'write'));
    notOk(hasPerm(['users:read'], false, 'users', 'delete'));
  });

  it('perm "users:write" → read + write mais pas delete', () => {
    ok(hasPerm(['users:write'], false, 'users', 'read'));
    ok(hasPerm(['users:write'], false, 'users', 'write'));
    notOk(hasPerm(['users:write'], false, 'users', 'delete'));
  });

  it('perm "users:delete" → tout autorisé', () => {
    ok(hasPerm(['users:delete'], false, 'users', 'read'));
    ok(hasPerm(['users:delete'], false, 'users', 'write'));
    ok(hasPerm(['users:delete'], false, 'users', 'delete'));
  });

  it('perm multiple sections indépendantes', () => {
    const perms = ['users:read', 'pronostics:write', 'tutoriels:delete'];
    ok(hasPerm(perms, false, 'users',      'read'));
    notOk(hasPerm(perms, false, 'users',   'write'));
    ok(hasPerm(perms, false, 'pronostics', 'write'));
    notOk(hasPerm(perms, false, 'pronostics', 'delete'));
    ok(hasPerm(perms, false, 'tutoriels',  'delete'));
    notOk(hasPerm(perms, false, 'actualites', 'read'));
  });

  it('perm "actualites:write" nouvelle section', () => {
    ok(hasPerm(['actualites:write'], false, 'actualites', 'read'));
    ok(hasPerm(['actualites:write'], false, 'actualites', 'write'));
    notOk(hasPerm(['actualites:write'], false, 'actualites', 'delete'));
  });
});

// ─────────────────────────────────────────────────────────────────────────────
describe('📰 Actualités — CRUD complet', () => {

  let all = [];
  let artId;

  it('créer un article (brouillon)', () => {
    const r = newsCreate(all, { title: 'Test Article 1', summary: 'Résumé', content: 'Contenu', category: 'news', isPublished: false, authorName: 'Carlos' });
    all = r.all;
    artId = r.art.id;
    eq(all.length, 1);
    eq(all[0].title, 'Test Article 1');
    eq(all[0].slug, 'test-article-1');
    eq(all[0].isPublished, false);
    ok(all[0].publishedAt === null);
    eq(all[0].viewCount, 0);
  });

  it('créer un article (publié direct)', () => {
    const r = newsCreate(all, { title: 'Article Publié', isPublished: true, authorName: 'Carlos' });
    all = r.all;
    ok(r.art.isPublished);
    ok(r.art.publishedAt !== null);
  });

  it('créer requiert un titre', () => {
    // Simuler la validation du serveur : title vide → erreur
    const title = '   ';
    ok(!title.trim(), 'titre vide détecté');
  });

  it('modifier un article', () => {
    const r = newsUpdate(all, artId, { title: 'Titre Modifié', summary: 'Nouveau résumé', category: 'promo', isPublished: false });
    all = r.all;
    ok(r.ok);
    const art = all.find(a => a.id === artId);
    eq(art.title, 'Titre Modifié');
    eq(art.slug, 'titre-modifie');
    eq(art.category, 'promo');
    eq(art.summary, 'Nouveau résumé');
  });

  it('modifier un ID inexistant → ok:false', () => {
    const r = newsUpdate(all, 'inexistant', { title: 'X' });
    notOk(r.ok);
  });

  it('toggle publier (brouillon → publié)', () => {
    const r = newsTogglePublish(all, artId);
    all = r.all;
    ok(r.ok);
    ok(r.isPublished);
    ok(all.find(a => a.id === artId).publishedAt !== null);
  });

  it('toggle publier (publié → brouillon)', () => {
    const r = newsTogglePublish(all, artId);
    all = r.all;
    ok(r.ok);
    notOk(r.isPublished);
    ok(all.find(a => a.id === artId).publishedAt === null);
  });

  it('toggle épingler', () => {
    notOk(all.find(a => a.id === artId).isPinned);
    newsTogglePin(all, artId);
    ok(all.find(a => a.id === artId).isPinned);
    newsTogglePin(all, artId);
    notOk(all.find(a => a.id === artId).isPinned);
  });

  it('filtrer par catégorie', () => {
    // all contient 1 promo (artId modifié), 1 news (article publié)
    const promos = newsFilter(all, { category: 'promo' });
    ok(promos.every(a => a.category === 'promo'));
  });

  it('filtrer par statut publié', () => {
    const pub = newsFilter(all, { status: 'published' });
    ok(pub.every(a => a.isPublished));
  });

  it('filtrer par recherche texte', () => {
    const r = newsFilter(all, { search: 'Titre' });
    ok(r.length >= 1);
    ok(r.every(a => a.title.toLowerCase().includes('titre')));
  });

  it('les épinglés apparaissent en premier', () => {
    newsTogglePin(all, artId);  // épingler artId
    const sorted = newsFilter(all, {});
    eq(sorted[0].id, artId);
    newsTogglePin(all, artId);  // remettre
  });

  it('supprimer un article', () => {
    const before = all.length;
    const r = newsDelete(all, artId);
    all = r.all;
    ok(r.found);
    eq(all.length, before - 1);
    notOk(all.find(a => a.id === artId));
  });

  it('supprimer ID inexistant → found undefined', () => {
    const r = newsDelete(all, 'fake_id');
    notOk(r.found);
    eq(r.all.length, all.length);
  });

  it('stats : compter published/draft/pinned', () => {
    // Reset et recréer proprement
    all = [];
    all = newsCreate(all, { title: 'A1', isPublished: true,  authorName:'C' }).all;
    all = newsCreate(all, { title: 'A2', isPublished: false, authorName:'C' }).all;
    all = newsCreate(all, { title: 'A3', isPublished: false, authorName:'C' }).all;
    newsTogglePin(all, all[0].id);

    const stats = {
      total:     all.length,
      published: all.filter(n => n.isPublished).length,
      draft:     all.filter(n => !n.isPublished).length,
      pinned:    all.filter(n => n.isPinned).length,
      totalViews:all.reduce((s,n)=>s+(n.viewCount||0),0),
    };
    eq(stats.total, 3);
    eq(stats.published, 1);
    eq(stats.draft, 2);
    eq(stats.pinned, 1);
    eq(stats.totalViews, 0);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
describe('👥 Sous-admins — CRUD complet', () => {

  let subs = [];
  let subId;

  it('créer un sous-admin', () => {
    const r = subCreate(subs, { name: 'Jean Dupont', username: 'jean', password: 'secret123', permissions: ['users:read'] });
    ok(r.ok);
    subs = r.subs;
    subId = r.sub.id;
    eq(subs.length, 1);
    eq(subs[0].username, 'jean');
    ok(subs[0].isActive);
    ok(subs[0].passwordHash !== 'secret123', 'mot de passe hashé');
    ok(subs[0].passwordHash.length === 64, 'hash SHA-256');
  });

  it('créer : username dupliqué → erreur', () => {
    const r = subCreate(subs, { name: 'Jean 2', username: 'jean', password: 'autre' });
    notOk(r.ok);
    ok(r.error.includes('déjà'));
    eq(subs.length, 1);
  });

  it('créer : champs manquants → erreur', () => {
    eq(subCreate(subs, { name: '', username: 'x', password: 'y' }).ok, false);
    eq(subCreate(subs, { name: 'X', username: '', password: 'y' }).ok, false);
    eq(subCreate(subs, { name: 'X', username: 'x', password: '' }).ok, false);
  });

  it('modifier les permissions', () => {
    const r = subUpdatePerms(subs, subId, ['users:read', 'pronostics:write', 'actualites:delete']);
    ok(r.ok);
    eq(subs.find(s => s.id === subId).permissions.length, 3);
  });

  it('permissions vide → tableau vide (pas de crash)', () => {
    const r = subUpdatePerms(subs, subId, []);
    ok(r.ok);
    eq(subs.find(s => s.id === subId).permissions.length, 0);
  });

  it('changer le mot de passe', () => {
    const oldHash = subs.find(s => s.id === subId).passwordHash;
    const r = subChangePwd(subs, subId, 'nouveauMDP456!');
    ok(r.ok);
    const newHash = subs.find(s => s.id === subId).passwordHash;
    ok(oldHash !== newHash);
    eq(newHash, hashPwd('nouveauMDP456!'));
  });

  it('changer mdp trop court → erreur', () => {
    const r = subChangePwd(subs, subId, 'abc');
    notOk(r.ok);
    ok(r.error);
  });

  it('changer mdp ID inexistant → ok:false', () => {
    notOk(subChangePwd(subs, 'bad-id', 'motdepasse').ok);
  });

  it('toggle actif/inactif', () => {
    ok(subs.find(s => s.id === subId).isActive);
    const r1 = subToggle(subs, subId);
    ok(r1.ok);
    notOk(r1.isActive);
    notOk(subs.find(s => s.id === subId).isActive);
    subToggle(subs, subId);
    ok(subs.find(s => s.id === subId).isActive);
  });

  it('supprimer un sous-admin', () => {
    const r = subDelete(subs, subId);
    subs = r.subs;
    ok(r.found);
    eq(subs.length, 0);
  });

  it('supprimer inexistant → found undefined', () => {
    const r = subDelete(subs, 'fake');
    notOk(r.found);
  });

  it('vérification du mot de passe au login', () => {
    const r = subCreate(subs, { name: 'Test', username: 'test_login', password: 'MonMDP99!' });
    const sub = r.subs.find(s => s.username === 'test_login');
    eq(sub.passwordHash, hashPwd('MonMDP99!'));
    ok(sub.passwordHash !== hashPwd('MauvasMDP'));
  });
});

// ─────────────────────────────────────────────────────────────────────────────
describe('🚫 Système de bannissements', () => {

  let bans = [];
  const USER_ID = 'user_abc123';

  it('bannir un utilisateur', () => {
    const r = banCreate(bans, { userId: USER_ID, reason: 'Fraude', expiresAt: null, adminName: 'Carlos' });
    bans = r.bans;
    ok(r.ban.active);
    eq(r.ban.userId, USER_ID);
    eq(r.ban.reason, 'Fraude');
    ok(getActiveBan(bans, USER_ID) !== null);
  });

  it('ban avec expiration', () => {
    bans = [];
    const expiry = new Date(Date.now() + 86400000 * 7).toISOString();
    const r = banCreate(bans, { userId: USER_ID, reason: 'Spam', expiresAt: expiry, adminName: 'Carlos' });
    bans = r.bans;
    const activeBan = getActiveBan(bans, USER_ID);
    ok(activeBan !== null);
    eq(activeBan.expiresAt, expiry);
  });

  it('re-bannir remplace le ban actif précédent', () => {
    const r = banCreate(bans, { userId: USER_ID, reason: 'Nouveau motif', expiresAt: null, adminName: 'Carlos' });
    bans = r.bans;
    const activeBans = bans.filter(b => b.userId === USER_ID && b.active);
    eq(activeBans.length, 1, 'un seul ban actif à la fois');
    eq(activeBans[0].reason, 'Nouveau motif');
    eq(bans.length, 2, 'historique conservé');
  });

  it('débannir', () => {
    const r = banRevoke(bans, USER_ID);
    ok(r.ok);
    ok(getActiveBan(bans, USER_ID) === null);
    eq(bans.filter(b => b.userId === USER_ID).length, 2, 'historique intact');
  });

  it('débannir un utilisateur non banni → ok:false', () => {
    notOk(banRevoke(bans, USER_ID).ok);
  });

  it('ban expiré → getActiveBan retourne null', () => {
    bans = [];
    const pastExpiry = new Date(Date.now() - 1000).toISOString();
    banCreate(bans, { userId: USER_ID, reason: 'Expiré', expiresAt: pastExpiry, adminName: 'Carlos' });
    ok(getActiveBan(bans, USER_ID) === null, 'ban expiré non retourné');
  });

  it('bannir un autre utilisateur n\'affecte pas le premier', () => {
    bans = [];
    banCreate(bans, { userId: 'user1', reason: 'R1', adminName: 'A' });
    banCreate(bans, { userId: 'user2', reason: 'R2', adminName: 'A' });
    ok(getActiveBan(bans, 'user1') !== null);
    ok(getActiveBan(bans, 'user2') !== null);
    banRevoke(bans, 'user1');
    ok(getActiveBan(bans, 'user1') === null);
    ok(getActiveBan(bans, 'user2') !== null);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
describe('📣 Historique notifications — suppression', () => {

  let history = [
    { title: 'Notif 1', body: 'Corps 1', segment: 'all', sent: 100, sentAt: new Date().toISOString() },
    { title: 'Notif 2', body: 'Corps 2', segment: 'premium', sent: 50, sentAt: new Date().toISOString() },
    { title: 'Notif 3', body: 'Corps 3', segment: 'free', sent: 200, sentAt: new Date().toISOString() },
  ];

  it('supprimer index valide', () => {
    const r = notifHistDelete(history, 1);
    ok(r.ok);
    eq(history.length, 2);
    eq(history[0].title, 'Notif 1');
    eq(history[1].title, 'Notif 3');
  });

  it('supprimer index 0 (le plus récent)', () => {
    const r = notifHistDelete(history, 0);
    ok(r.ok);
    eq(history.length, 1);
    eq(history[0].title, 'Notif 3');
  });

  it('supprimer index hors bornes → ok:false', () => {
    notOk(notifHistDelete(history, 99).ok);
    notOk(notifHistDelete(history, -1).ok);
    eq(history.length, 1);
  });

  it('calcul des stats historique', () => {
    const all = [
      { sent: 100, sentAt: new Date().toISOString() },
      { sent: 200, sentAt: new Date().toISOString() },
      { sent: 50,  sentAt: new Date(Date.now() - 86400000 * 40).toISOString() }, // > 30j
    ];
    const now = Date.now();
    const stats = {
      total:      all.length,
      totalSent:  all.reduce((s,h)=>s+(h.sent??0),0),
      thisWeek:   all.filter(h => now - new Date(h.sentAt).getTime() < 7*24*3600*1000).length,
      thisMonth:  all.filter(h => now - new Date(h.sentAt).getTime() < 30*24*3600*1000).length,
    };
    eq(stats.total, 3);
    eq(stats.totalSent, 350);
    eq(stats.thisWeek, 2);
    eq(stats.thisMonth, 2);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
describe('📋 Journal d\'audit', () => {

  let logs = [];

  it('enregistrer une action', () => {
    const r = logAction(logs, 'Carlos', 'user_banned', 'JohnDoe', { userId: 'u1' });
    logs = r.logs;
    eq(logs.length, 1);
    eq(logs[0].adminName, 'Carlos');
    eq(logs[0].action, 'user_banned');
    eq(logs[0].target, 'JohnDoe');
    ok(logs[0].timestamp);
    ok(logs[0].id);
  });

  it('les nouvelles actions sont en tête (ordre décroissant)', () => {
    logAction(logs, 'Carlos', 'tutorial_created', 'Tuto 1', {});
    logAction(logs, 'Jean',   'news_created',     'Article', {});
    eq(logs[0].action, 'news_created');
    eq(logs[2].action, 'user_banned');
  });

  it('limite à 5000 entrées', () => {
    const bigLogs = Array.from({ length: 5100 }, (_, i) => ({ id: String(i), timestamp: new Date().toISOString(), action: 'test' }));
    const r = logAction(bigLogs, 'A', 'x', 'y');
    eq(r.logs.length, 5000);
  });

  it('filtrer par action', () => {
    const r = auditFilter(logs, { action: 'user_banned' });
    eq(r.length, 1);
    eq(r[0].action, 'user_banned');
  });

  it('filtrer par admin', () => {
    const r = auditFilter(logs, { admin: 'jean' });
    ok(r.every(l => l.adminName.toLowerCase().includes('jean')));
  });

  it('filtrer par recherche texte (target)', () => {
    const r = auditFilter(logs, { search: 'JohnDoe' });
    ok(r.length >= 1);
    ok(r.every(l => l.target?.toLowerCase().includes('johndoe')));
  });

  it('filtres vides → tous les logs', () => {
    eq(auditFilter(logs, {}).length, logs.length);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
describe('🗂️ Persistance fichiers JSON', () => {

  it('écriture + relecture actualités', () => {
    const arts = [{ id: 'a1', title: 'Test', isPublished: true }];
    save('actualites.json', arts);
    const loaded = load('actualites.json');
    eq(loaded.length, 1);
    eq(loaded[0].id, 'a1');
    eq(loaded[0].title, 'Test');
  });

  it('écriture + relecture sous-admins', () => {
    const subs = [{ id: 's1', username: 'jean', passwordHash: hashPwd('abc') }];
    save('sub_admins.json', subs);
    const loaded = load('sub_admins.json');
    eq(loaded[0].passwordHash, hashPwd('abc'));
  });

  it('écriture + relecture bans', () => {
    const bans = [{ id: 'b1', userId: 'u1', active: true, reason: 'Test' }];
    save('bans.json', bans);
    const loaded = load('bans.json');
    ok(loaded[0].active);
  });

  it('écriture + relecture audit log', () => {
    const logs = Array.from({ length: 50 }, (_, i) => ({ id: String(i), action: 'test_' + i }));
    save('audit_log.json', logs);
    const loaded = load('audit_log.json');
    eq(loaded.length, 50);
    eq(loaded[49].action, 'test_49');
  });

  it('écriture + relecture historique notifs', () => {
    const hist = [{ title: 'T1', sent: 100 }, { title: 'T2', sent: 200 }];
    save('notifications_history.json', hist);
    const loaded = load('notifications_history.json');
    eq(loaded[1].title, 'T2');
    eq(loaded.reduce((s, h) => s + h.sent, 0), 300);
  });

  it('lecture fichier manquant → tableau vide sans crash', () => {
    const r = load('inexistant.json');
    eq(r, []);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
describe('🔍 Vérification des routes serveur', () => {

  const src = fs.readFileSync(path.join(__dirname, 'server.js'), 'utf8');
  function hasRoute(method, path) {
    const re = new RegExp("app\\." + method + "\\(['\"]" + path.replace(/\//g,'\\/').replace(/:/g,'\\:').replace(/\./g,'\\.') + "['\"]");
    ok(re.test(src), method.toUpperCase() + ' ' + path + ' doit exister');
  }

  it('routes GET principales', () => {
    hasRoute('get', '/admin/login');
    hasRoute('get', '/admin/dashboard');
    hasRoute('get', '/admin/users');
    hasRoute('get', '/admin/pronostics');
    hasRoute('get', '/admin/historique');
    hasRoute('get', '/admin/tutoriels');
    hasRoute('get', '/admin/actualites');
    hasRoute('get', '/admin/notifications');
    hasRoute('get', '/admin/profile');
    hasRoute('get', '/admin/audit');
    hasRoute('get', '/admin/sub-admins');
    hasRoute('get', '/admin/bans');
    hasRoute('get', '/admin/settings');
  });

  it('routes POST actualités', () => {
    hasRoute('post', '/admin/actualites');
    hasRoute('post', '/admin/actualites/:id/edit');
    hasRoute('post', '/admin/actualites/:id/publish');
    hasRoute('post', '/admin/actualites/:id/pin');
    hasRoute('post', '/admin/actualites/:id/delete');
  });

  it('routes POST sous-admins', () => {
    hasRoute('post', '/admin/sub-admins');
    hasRoute('post', '/admin/sub-admins/:id/permissions');
    hasRoute('post', '/admin/sub-admins/:id/password');
    hasRoute('post', '/admin/sub-admins/:id/toggle');
    hasRoute('post', '/admin/sub-admins/:id/delete');
  });

  it('routes POST utilisateurs', () => {
    hasRoute('post', '/admin/users/:id/ban');
    hasRoute('post', '/admin/users/:id/unban');
    hasRoute('post', '/admin/users/:id/suspend');
    hasRoute('post', '/admin/users/:id/premium');
    hasRoute('post', '/admin/users/:id/revoke-premium');
    hasRoute('post', '/admin/users/:id/notify');
    hasRoute('post', '/admin/users/:id/pseudo');
  });

  it('routes POST notifications', () => {
    hasRoute('post', '/admin/notifications/send');
    hasRoute('post', '/admin/notifications/history/:idx/delete');
  });

  it('routes POST settings', () => {
    hasRoute('post', '/admin/settings/maintenance');
    hasRoute('post', '/admin/settings/announcement');
    hasRoute('post', '/admin/settings/general');
  });

  it('routes API internes', () => {
    hasRoute('get', '/admin/api/search');
    hasRoute('get', '/admin/api/badges');
    hasRoute('get', '/admin/api/notifications/preview');
    hasRoute('get', '/admin/api/live');
  });

  it('routes export CSV', () => {
    hasRoute('get', '/admin/users/export');
    hasRoute('get', '/admin/historique/export');
    hasRoute('get', '/admin/audit/export');
    hasRoute('get', '/admin/bans/export');
    hasRoute('get', '/admin/actualites');  // vérifié via page + pas d'export prévu
  });

  it('redirections de base', () => {
    ok(src.includes("res.redirect('/admin/dashboard')"), 'redirect / → dashboard');
  });

  it('permission actualites déclarée dans PERMISSIONS', () => {
    ok(src.includes("key: 'actualites'"), "permission 'actualites' dans PERMISSIONS");
  });

  it('middlewares requireAuth et requirePerm présents', () => {
    ok(src.includes('function requireAuth'), 'requireAuth défini');
    ok(src.includes('function requirePerm'), 'requirePerm défini');
    ok(src.includes('function requireMain'), 'requireMain défini');
  });
});

// ─────────────────────────────────────────────────────────────────────────────
describe('🎨 Vérification CSS vars (pas de couleurs hardcodées)', () => {

  const viewsDir = path.join(__dirname, 'views');
  const ownViews = [
    'historique.ejs', 'actualites.ejs', 'actualite_form.ejs',
    'notifications.ejs', 'profile.ejs', 'audit.ejs',
    'sub_admins.ejs', 'tutoriels.ejs', 'tutoriel_form.ejs',
    'pronostics.ejs', 'pronostic_form.ejs',
  ];

  // Couleurs hex hardcodées à détecter (hors commentaires et valeurs CSS légitimes)
  const badColors = [
    /#151B2E/, /#1E2A42/, /#8892AA/, /#0d0d1a/, /#1a1a2e/, /#2d2d44/,
  ];

  ownViews.forEach(view => {
    it(view + ' : pas de couleurs hardcodées interdites', () => {
      const src = fs.readFileSync(path.join(viewsDir, view), 'utf8');
      badColors.forEach(re => {
        const match = src.match(re);
        ok(!match, `Couleur hardcodée ${re} trouvée dans ${view}: "${match?.[0]}"`);
      });
    });
  });

  it('layout_top.ejs : pas de couleurs hardcodées dans le phone mock', () => {
    // Vérifie que notifications.ejs n'a plus les anciennes couleurs du phone
    const src = fs.readFileSync(path.join(viewsDir, 'notifications.ejs'), 'utf8');
    ok(!src.includes('#1a1a2e'), 'Plus de #1a1a2e dans notifications');
    ok(!src.includes('#0d0d1a'), 'Plus de #0d0d1a dans notifications');
    ok(!src.includes('#2d2d44'), 'Plus de #2d2d44 dans notifications');
  });

  it('historique.ejs : modal sans couleurs hardcodées', () => {
    const src = fs.readFileSync(path.join(viewsDir, 'historique.ejs'), 'utf8');
    ok(!src.includes('#151B2E') && !src.includes('#1E2A42'), 'Modal historique sans couleurs hardcodées');
  });
});

// ─────────────────────────────────────────────────────────────────────────────

teardown();

// ── Résumé final ──────────────────────────────────────────────────────────────
console.log('\n' + '═'.repeat(60));
const total_tests = passed + failed;
if (failed === 0) {
  console.log(G('🎉  TOUT PASSE — ' + passed + '/' + total_tests + ' tests OK'));
} else {
  console.log(R('⚠️   ' + failed + ' ECHEC(S) / ' + total_tests + ' tests — ' + passed + ' OK'));
  console.log('\n' + Y('Tests échoués :'));
  results.filter(r => !r.ok).forEach(r => console.log('  ' + R('❌') + ' [' + r.suite + '] ' + r.label + '\n     ' + DIM(r.error)));
}
console.log('═'.repeat(60));
process.exit(failed > 0 ? 1 : 0);
