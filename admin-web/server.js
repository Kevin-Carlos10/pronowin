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
// Ce secret signe le rôle et les permissions de la session. Il n'a plus de
// valeur par défaut, et le serveur refuse de démarrer sans lui.
//
// Il en avait une, écrite en clair dans ce fichier, accompagnée d'un
// avertissement dans la console. Autrement dit : la serrure existait, sa clé
// était publiée, et le serveur démarrait quand même. Un avertissement au
// démarrage n'est lu qu'une fois, le jour de l'installation.
const PERM_HMAC_SECRET = process.env.ADMIN_PERM_SECRET ?? process.env.ADMIN_SECRET ?? '';
if (!PERM_HMAC_SECRET) {
  console.error('ADMIN_PERM_SECRET (ou ADMIN_SECRET) est absent.');
  console.error('Ce secret signe le rôle et les permissions de chaque session ;');
  console.error('sans lui, un cookie forgé ouvre le panneau en administrateur principal.');
  console.error('Definissez-le dans admin-web/.env avant de demarrer.');
  process.exit(1);
}

// ─── SOUS-ADMINS : stockage local ────────────────────────────────────────────
// `ADMIN_DATA_DIR` n'existe que pour les contrôles automatiques, qui doivent
// pouvoir créer et révoquer des comptes sans toucher aux vrais. Sans lui, le
// seul banc possible écrivait dans `data/` — donc dans les comptes de la
// machine — et personne ne l'aurait mis dans `npm test`.
const DATA_DIR = process.env.ADMIN_DATA_DIR ?? path.join(__dirname, 'data');
const SA_FILE  = path.join(DATA_DIR, 'sub_admins.json');
if (!fs.existsSync(DATA_DIR)) fs.mkdirSync(DATA_DIR, { recursive: true });
if (!fs.existsSync(SA_FILE))  fs.writeFileSync(SA_FILE, '[]');

/**
 * Écrit un fichier JSON de façon atomique, et **rend le résultat**.
 *
 * Deux défauts corrigés d'un coup :
 *
 * 1. `saveSubs` n'avait aucun try/catch — un disque plein remontait en
 *    exception non gérée, donc en 500 avec trace d'appels ;
 * 2. les autres écrivains avalaient l'erreur dans un `catch {}` vide, si bien
 *    que l'admin lisait « enregistré avec succès » alors que rien n'était
 *    écrit. Annoncer un succès sans jamais regarder le résultat de l'écriture,
 *    c'est le pire des deux mondes.
 *
 * L'écriture passe par un fichier temporaire puis un renommage : sur la
 * plupart des systèmes de fichiers, `rename` est atomique. Une coupure en
 * plein milieu laisse donc l'ancien fichier intact plutôt qu'un JSON tronqué —
 * ce qui, pour `sub_admins.json`, signifierait perdre tous les comptes.
 */
function ecrireJson(fichier, donnees, espacement = 2) {
  const tmp = fichier + '.tmp';
  try {
    fs.writeFileSync(tmp, JSON.stringify(donnees, null, espacement));
    fs.renameSync(tmp, fichier);
    return { ok: true };
  } catch (e) {
    // Nettoyage du temporaire : le laisser traîner masquerait la prochaine erreur.
    try { if (fs.existsSync(tmp)) fs.unlinkSync(tmp); } catch {}
    console.error(`[admin] Échec d'écriture de ${path.basename(fichier)}:`, e.message);
    return { ok: false, erreur: e.message };
  }
}

/**
 * Empreinte d'un fichier au moment de sa lecture : date de dernière
 * modification en millisecondes, ou 0 s'il n'existe pas encore.
 */
function empreinte(fichier) {
  try { return fs.statSync(fichier).mtimeMs; } catch { return 0; }
}

/**
 * Écrit un fichier JSON **seulement s'il n'a pas bougé depuis la lecture**.
 *
 * Le motif `charger() → modifier → enregistrer()` est partout dans ce fichier,
 * et sur des fichiers JSON il n'y a pas de transaction : deux administrateurs
 * qui modifient les permissions dans la même minute produisaient une écriture
 * où le second écrasait le premier, sans avertissement et sans trace.
 *
 * Comparer la date de modification n'est pas un verrou — deux écritures
 * séparées d'une milliseconde peuvent encore se croiser. C'est une détection :
 * elle transforme une perte silencieuse en un message que l'admin peut lire et
 * auquel il peut réagir, ce qui est exactement ce qui manquait.
 */
function ecrireSiInchange(fichier, donnees, empreinteLue, espacement = 2) {
  if (empreinte(fichier) !== empreinteLue) {
    return { ok: false, conflit: true };
  }
  return ecrireJson(fichier, donnees, espacement);
}

/** Message d'erreur uniforme, à afficher à l'admin quand une écriture échoue. */
const ERR_ECRITURE = 'Enregistrement impossible : le serveur n\'a pas pu écrire ' +
  'le fichier. Rien n\'a été modifié. Vérifie l\'espace disque et les droits.';

/** Modification concurrente détectée — l'admin doit recharger et refaire. */
const ERR_CONFLIT = 'Un autre administrateur a modifié ces données pendant ' +
  'que tu les éditais. Tes changements n\'ont pas été enregistrés pour ne pas ' +
  'écraser les siens. Recharge la page et recommence.';

// ─── SESSIONS : tenues côté serveur (lib/sessions.js) ───────────────────────
const { creerMagasinSessions } = require('./lib/sessions');
const sessions = creerMagasinSessions({
  fichier: path.join(DATA_DIR, 'sessions.json'), ecrireJson,
});
/** Le seul cookie de session : un identifiant aléatoire, sans contenu. */
const COOKIE_SESSION = 'admin_session';

function loadSubs()       { try { return JSON.parse(fs.readFileSync(SA_FILE, 'utf8')); } catch { return []; } }
function saveSubs(data)   { return ecrireJson(SA_FILE, data); }

/** Empreinte du fichier des sous-admins, à capturer juste avant `loadSubs()`. */
function empreinteSubs()  { return empreinte(SA_FILE); }
/** Enregistre les sous-admins si personne d'autre ne les a touchés entre-temps. */
function saveSubsSi(data, emp) { return ecrireSiInchange(SA_FILE, data, emp); }
function hashPwd(pwd)     { return bcrypt.hashSync(pwd, 12); }
function checkPwd(pwd, hash) { return bcrypt.compareSync(pwd, hash); }

// La forme canonique d'un identifiant vit dans `lib/identifiant.js`, avec le
// détail de la panne qu'elle corrige. Elle est réexportée dans le contexte des
// routes pour que la création et la connexion appliquent la même règle.
const { normaliserIdentifiant } = require('./lib/identifiant');
const {
  acteurCourant, executerAvecActeur, signerDelegation, ENTETE_DELEGATION,
} = require('./lib/acteur');

/**
 * Le secret partagé avec le backend.
 *
 * Il signe l'identité de la personne qui agit derrière le jeton du compte de
 * service — le même pour tous les sous-administrateurs. Sans lui, le backend
 * ne peut ni attribuer une action, ni distinguer un appel venu d'ici d'un
 * appel direct fait avec un jeton lu dans un navigateur.
 *
 * La même valeur doit figurer dans `backend/.env`.
 */
const SECRET_DELEGATION = process.env.ADMIN_DELEGATION_SECRET ?? '';
if (!SECRET_DELEGATION) {
  console.error('ADMIN_DELEGATION_SECRET est absent.');
  console.error('Ce secret signe l identite de qui agit derriere le compte de service.');
  console.error('La meme valeur doit etre posee dans admin-web/.env et backend/.env.');
  process.exit(1);
}
/**
 * Le rôle de la session en cours : `main`, `sub`, ou `null` sans session.
 *
 * Il a longtemps été lu dans un cookie — d'abord en clair (`admin_role=main`
 * suffisait à devenir administrateur principal), puis signé. Il vient
 * désormais de la session tenue par le serveur (`lib/sessions.js`) : le
 * navigateur ne porte plus qu'un identifiant opaque et ne peut rien affirmer
 * sur le rôle, le nom ou le compte.
 */
function roleDeSession(req) { return req.admin?.role ?? null; }

function uid()            { return Date.now().toString(36) + Math.random().toString(36).slice(2, 7); }

// ─── BANS ─────────────────────────────────────────────────────────────────────
const BANS_FILE = path.join(DATA_DIR, 'bans.json');
if (!fs.existsSync(BANS_FILE)) fs.writeFileSync(BANS_FILE, '[]');

function loadBans()      { try { return JSON.parse(fs.readFileSync(BANS_FILE, 'utf8')); } catch { return []; } }
function saveBans(data)  { return ecrireJson(BANS_FILE, data); }

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

/**
 * Expiration des bans — deux moitiés, longtemps réduites à une seule.
 *
 * Bannir fait deux choses : écrire le ban dans `bans.json`, et suspendre le
 * compte côté API. À l'expiration, seule la première était défaite. Le panneau
 * affichait « Levé/Expiré » et `getActiveBan` renvoyait null, mais le compte
 * restait `suspended` en base — indéfiniment. Autrement dit tout ban temporaire
 * devenait permanent, sans que personne ne puisse le voir.
 *
 * La minuterie ne peut pas appeler l'API : elle n'a pas de jeton, et il
 * n'existe pas d'identifiant machine. Elle se limite donc à l'état local, et la
 * réactivation du compte est réconciliée à la première requête d'un
 * administrateur — qui, lui, porte un jeton valide. `accountRestoredAt`
 * enregistre ce qui a effectivement été fait, pour ne pas le refaire ni le
 * supposer.
 */
let _banAlerte = false;
setInterval(async () => {
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

  // Rendre l'accès aux comptes concernés. Cette moitié manquait : la minuterie
  // marquait le ban inactif localement mais laissait le compte suspendu en
  // base, ce qui rendait permanent tout ban temporaire. Elle attendait
  // jusqu'ici la visite d'un administrateur ; le compte de service permet de
  // le faire sans personne.
  const aRestaurer = bansARestaurer();
  if (aRestaurer.length) {
    const token = await jetonService();
    if (token) {
      const { restaures } = await enTantQueSysteme(() => reconcilierBansExpires(token));
      if (restaures.length) {
        console.log(`Bans expirés : ${restaures.length} compte(s) réactivé(s).`);
        sseBroadcast('ban_expired', { ts: Date.now(), restaures: restaures.length });
      }
    } else if (!_banAlerte) {
      _banAlerte = true;
      console.warn(`⚠️  ${aRestaurer.length} compte(s) dont le ban a expiré restent suspendus :`
                 + ' aucun compte de service configuré. Ils seront réactivés à la prochaine'
                 + ' ouverture de la page Bannissements par un administrateur.');
    }
  }
}, 5 * 60 * 1000);

/** Bans expirés dont le compte n'a pas encore été réactivé côté API. */
function bansARestaurer() {
  const now = Date.now();
  return loadBans().filter(b =>
    !b.active &&
    b.expiresAt &&
    new Date(b.expiresAt).getTime() <= now &&
    !b.accountRestoredAt &&
    // Un déban manuel a déjà rappelé l'API ; seule l'expiration laisse le
    // compte en suspens.
    b.unbannedBy === 'Système (expiration automatique)'
  );
}

/**
 * Rend l'accès aux comptes dont le ban a expiré.
 * Retourne { restaures, echecs } — jamais une promesse rejetée : un backend
 * injoignable ne doit pas empêcher la page de s'afficher.
 */
async function reconcilierBansExpires(token) {
  const enAttente = bansARestaurer();
  if (!enAttente.length || !token) return { restaures: [], echecs: enAttente.length ? enAttente.length : 0 };

  const a = api(token);
  const restaures = [];
  let echecs = 0;

  for (const b of enAttente) {
    try {
      await a.patch('/admin/users/' + b.userId + '/suspend', { suspend: false });
      restaures.push(b);
    } catch { echecs++; }
  }

  if (restaures.length) {
    const bans = loadBans();
    const ids  = new Set(restaures.map(b => b.id));
    const quand = new Date().toISOString();
    bans.forEach(b => { if (ids.has(b.id)) b.accountRestoredAt = quand; });
    saveBans(bans);
  }
  return { restaures, echecs };
}

// ─── PARAMÈTRES GÉNÉRAUX ─────────────────────────────────────────────────────
const SETTINGS_FILE = path.join(DATA_DIR, 'settings.json');

const DEFAULT_SETTINGS = {
  maintenanceMode:     false,
  maintenanceMessage:  '',
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

/** Entier borné, avec repli si la saisie n'est pas un nombre exploitable. */
function clampInt(raw, min, max, fallback) {
  const n = parseInt(raw, 10);
  return Number.isFinite(n) ? Math.min(max, Math.max(min, n)) : fallback;
}

/**
 * L'ancien message d'usine du mode maintenance.
 *
 * Il affirmait « Le panel est en cours de maintenance. Revenez dans quelques
 * instants. » — or ce mode n'a jamais rien bloqué : il affiche un bandeau, et
 * le blocage des utilisateurs se règle ailleurs, par Firebase Remote Config. Le
 * bandeau disait donc à des administrateurs en train d'utiliser le panneau de
 * revenir plus tard.
 *
 * Ce texte n'a jamais été écrit par personne : c'est le défaut de création du
 * fichier, et il est encore stocké en production. On le neutralise à la
 * lecture plutôt que de réécrire `settings.json`, qui est une donnée
 * d'exploitation : le fichier se nettoie de lui-même au prochain
 * enregistrement des réglages.
 */
const MESSAGE_MAINTENANCE_HERITE =
  'Le panel est en cours de maintenance. Revenez dans quelques instants.';

function loadSettings() {
  let s;
  try { s = { ...DEFAULT_SETTINGS, ...JSON.parse(fs.readFileSync(SETTINGS_FILE, 'utf8')) }; }
  catch { return { ...DEFAULT_SETTINGS }; }
  if (s.maintenanceMessage === MESSAGE_MAINTENANCE_HERITE) s.maintenanceMessage = '';
  return s;
}
function saveSettings(s) { return ecrireJson(SETTINGS_FILE, s); }

function empreinteSettings()      { return empreinte(SETTINGS_FILE); }
function saveSettingsSi(s, emp)   { return ecrireSiInchange(SETTINGS_FILE, s, emp); }

// ─── ACTUALITÉS : stockage local ─────────────────────────────────────────────
const NEWS_FILE = path.join(DATA_DIR, 'actualites.json');
if (!fs.existsSync(NEWS_FILE)) fs.writeFileSync(NEWS_FILE, '[]');

function loadNews()     { try { return JSON.parse(fs.readFileSync(NEWS_FILE, 'utf8')); } catch { return []; } }
function saveNews(data) { return ecrireJson(NEWS_FILE, data); }
const NEWS_DEFAULT_CATEGORIES = ['news', 'promo', 'update', 'tip', 'alert'];
function getNewsCategories() {
  const used = loadNews().map(n => n.category).filter(Boolean);
  return [...new Set([...NEWS_DEFAULT_CATEGORIES, ...used])].sort();
}
function slugify(str)   { return str.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g,'').replace(/[^a-z0-9]+/g,'-').replace(/^-|-$/g,'').slice(0,80); }

// ─── AUDIT LOG ───────────────────────────────────────────────────────────────
const LOG_FILE    = path.join(DATA_DIR, 'audit_log.json');
const LOG_MAX     = 5000;   // garder les 5000 dernières entrées

/**
 * `secure` sur les cookies de session.
 *
 * Sans lui, `admin_token` part en clair dès qu'une requête atteint le panneau
 * en HTTP : sur un réseau partagé, le jeton d'administration est lisible au
 * passage.
 *
 * Il était conditionné à `NODE_ENV === 'production'`. Cette variable n'est
 * définie nulle part sur le serveur — ni dans `.env`, ni dans le processus
 * pm2. Le panneau est servi en HTTPS et ses cookies partaient sans l'attribut
 * `secure`, tandis que ce commentaire expliquait pourquoi c'était prudent.
 *
 * La condition vient désormais de l'adresse déclarée du panneau : si
 * `ADMIN_ORIGIN` est en `https://`, les cookies sont `secure`. La même
 * variable dit où le panneau vit et s'il est servi en TLS — elles ne peuvent
 * plus diverger. `NODE_ENV` reste accepté pour les déploiements qui le
 * posent.
 */
const COOKIE_SECURE =
  (process.env.ADMIN_ORIGIN ?? '').startsWith('https://')
  || process.env.NODE_ENV === 'production';
if (!fs.existsSync(LOG_FILE)) fs.writeFileSync(LOG_FILE, '[]');

function loadLogs()  { try { return JSON.parse(fs.readFileSync(LOG_FILE, 'utf8')); } catch { return []; } }
function saveLogs(l) { return ecrireJson(LOG_FILE, l, 0); }

// ─── NOTIFICATIONS : historique local ────────────────────────────────────────
const NOTIF_FILE = path.join(DATA_DIR, 'notifications_history.json');
if (!fs.existsSync(NOTIF_FILE)) fs.writeFileSync(NOTIF_FILE, '[]');
function loadNotifHistory()   { try { return JSON.parse(fs.readFileSync(NOTIF_FILE, 'utf8')); } catch { return []; } }
function saveNotifHistory(d)  { return ecrireJson(NOTIF_FILE, d.slice(0, 200), 0); }

// Catégories lisibles
// `icon` porte un identifiant du sprite SVG (views/_icons.ejs), pas un emoji :
// les vues rendent <svg><use href="#ic-…"/></svg>, donc la teinte suit le thème.
const { ACTION_LABELS } = require('./lib/action_labels');


function logAction(req, action, target = '', details = {}) {
  try {
    const logs = loadLogs();
    const role = roleDeSession(req);
    logs.unshift({
      id:        uid(),
      timestamp: new Date().toISOString(),
      action,
      target,
      details,
      // Le nom venait du cookie `admin_name`, que le navigateur pouvait
      // réécrire : le journal attribuait l'action à qui l'on voulait. Il vient
      // maintenant de la session tenue par le serveur, et l'identifiant du
      // compte l'accompagne — deux sous-admins peuvent porter le même nom.
      adminName: req.admin?.nom ?? 'Inconnu',
      adminId:   role === 'main' ? 'main' : (req.admin?.subId ?? null),
      // Le défaut était « main » : une session sans rôle lisible était
      // journalisée comme administrateur principal.
      adminRole: role ?? 'inconnu',
      ip:        getClientIP(req),
    });
    if (logs.length > LOG_MAX) logs.splice(LOG_MAX);
    saveLogs(logs);
  } catch (e) {
    // Le journal est la trace de responsabilite du panneau : une entree perdue
    // en silence, c'est une action administrative sans preuve. On ne peut pas
    // interrompre l'action pour autant, mais on le signale.
    console.error("[admin] Échec d'écriture du journal d'audit :", e.message);
  }
}

/**
 * Ce que cette session a le droit de lire du journal d'activité.
 *
 * Le tableau de bord affichait `loadLogs().slice(0, 8)` — les huit dernières
 * actions de tout le monde, à qui que ce soit. Un sous-admin y lisait donc les
 * connexions de l'administrateur principal, la création des autres comptes, et
 * jusqu'aux tentatives échouées, qui portent l'identifiant saisi : une adresse
 * e-mail s'y affichait en clair.
 *
 * Rien ne l'avait signalé parce que les surfaces prévues pour ça sont bien
 * gardées : `/admin/audit`, son export CSV et la page Sous-admins sont tous en
 * `requireMain`. La barre latérale ne montrait même pas « Journal d'activité »
 * à ce compte. Le tableau de bord affichait le contenu de la page qu'on lui
 * cachait.
 *
 * La comparaison porte sur le rôle *et* le nom : filtrer sur le seul nom
 * laisserait un sous-admin nommé « Super Admin » lire les entrées de
 * l'administrateur principal.
 */
function journalVisiblePar(logs, req) {
  if (roleDeSession(req) === 'main') return logs;
  return logs.filter((l) => estMoi(l, req));
}

/**
 * Cette entrée est-elle une action de la personne connectée ?
 *
 * Distinct de `journalVisiblePar`, qui répond à « qu'ai-je le droit de lire ».
 * Les deux coïncident pour un sous-admin, pas pour l'administrateur principal :
 * il a le droit de tout lire, mais sa page de profil doit montrer ses actions à
 * lui. Les confondre lui aurait affiché le journal complet sous le titre
 * « Mon activité ».
 *
 * Le rôle entre dans la comparaison : sur le seul nom, un sous-admin appelé
 * « Super Admin » se verrait attribuer les actions de l'administrateur
 * principal — et les lirait.
 */
function estMoi(l, req) {
  const role = roleDeSession(req) ?? 'inconnu';
  if ((l.adminRole ?? 'main') !== role) return false;
  // Les entrées écrites depuis les sessions serveur portent l'identifiant du
  // compte : c'est lui qui tranche. Le nom ne sert qu'aux entrées plus
  // anciennes, qui n'avaient que lui.
  if (l.adminId) {
    return l.adminId === (role === 'main' ? 'main' : req.admin?.subId);
  }
  return l.adminName === (req.admin?.nom ?? '');
}

// ─── SYSTÈME DE PERMISSIONS GRANULAIRES ─────────────────────────────────────
// Le catalogue vit dans lib/permissions.js : le banc d'essai des vues en
// gardait sa propre copie, réduite à une entrée sans icône, et rendait donc
// « 42/42 vues OK » en n'exerçant qu'un libellé sur dix.
const { PERM_LEVELS, PERMISSIONS, niveauAccorde, niveauSuffisant } =
  require('./lib/permissions');

// La lecture d'un niveau accorde et sa comparaison vivent dans
// lib/permissions.js, avec le detail de la panne qu'elles corrigent : les deux
// implementations qui etaient ici renvoyaient le PREMIER niveau trouve, donc
// « read » pour un compte a qui l'interface avait tout accorde. Ces deux alias
// gardent les noms employes par les 64 appels de `requirePerm` et par les vues.
const getPermLevel = niveauAccorde;
const permLevelOk  = niveauSuffisant;

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
/**
 * Diffusion SSE, filtrable par destinataire.
 *
 * La charge etait identique pour tout le monde : un sous-admin sans permission
 * « transactions » recevait quand meme `tx_pending` par ce canal, ce qui
 * annulait le filtrage applique sur /admin/api/badges. `adapter` recoit les
 * permissions du client et renvoie la charge qui lui revient.
 */
function sseBroadcast(event, data, adapter = null) {
  const brut = `event: ${event}
data: ${JSON.stringify(data)}

`;
  for (const client of sseClients) {
    const res = client.res ?? client;
    let msg = brut;
    if (adapter) {
      const propre = adapter(client.perms ?? null);
      if (propre === null) continue;
      msg = `event: ${event}
data: ${JSON.stringify(propre)}

`;
    }
    try { res.write(msg); } catch { sseClients.delete(client); }
  }
}

/** Ne garde d'un lot de KPI que ce que ces permissions autorisent. */
function kpisPour(perms, kpis) {
  const peut = cle => perms === null
    || perms.some(p => typeof p === 'string' && p.split(':')[0] === cle);
  return {
    users_total:    peut('users')        ? kpis.users_total    : null,
    tx_pending:     peut('transactions') ? kpis.tx_pending     : null,
    proofs_pending: peut('abonnements')  ? kpis.proofs_pending : null,
    ts: kpis.ts,
  };
}

// ─── EXPRESS SETUP ───────────────────────────────────────────────────────────
app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, 'views'));
app.use(express.urlencoded({ extended: true }));
app.use(express.json());
app.use(cookieParser());
app.use(express.static(path.join(__dirname, 'public')));

// Chart.js servi localement plutôt que depuis un CDN : hors ligne ou CDN
// bloqué, `Chart` restait indéfini et toute la page Statistiques était vide.
// Servi depuis node_modules et non recopié dans public/ : la version reste
// celle de package.json, sans risque de dérive.
app.use('/vendor/chart.js', express.static(
  path.join(__dirname, 'node_modules/chart.js/dist'), { maxAge: '30d', immutable: true }));
app.use('/admin/vendor/chart.js', express.static(
  path.join(__dirname, 'node_modules/chart.js/dist'), { maxAge: '30d', immutable: true }));

// ─── HELPERS ─────────────────────────────────────────────────────────────────
/**
 * Un client vers l'API du backend, qui dit qui agit.
 *
 * L'en-tête de délégation est ajouté ici, une fois, plutôt qu'aux
 * soixante-trois endroits qui appellent cette fabrique. L'acteur vient du
 * contexte de la requête en cours (`lib/acteur.js`), pas d'un paramètre : ces
 * soixante-trois appels n'ont pas eu à changer.
 */
function api(token) {
  const acteur = acteurCourant();
  const instance = axios.create({
    baseURL: API_URL,
    headers: {
      Authorization: `Bearer ${token}`,
      // Hors requête — une tâche de fond, un script — il n'y a personne à
      // déclarer. Le backend refusera alors toute écriture, ce qui est la
      // réponse correcte : une écriture sans auteur ne doit pas avoir lieu.
      ...(acteur
        ? { [ENTETE_DELEGATION]: signerDelegation(acteur, SECRET_DELEGATION) }
        : {}),
    },
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

/**
 * L'origine d'une adresse, ou `null` si elle ne s'analyse pas.
 *
 * `new URL(...).origin` rend « schéma://hôte:port » et rien d'autre : c'est
 * exactement l'unité que deux origines doivent partager pour être la même.
 */
function origineDe(valeur) {
  try { return new URL(valeur).origin; } catch { return null; }
}

// ─── CSRF : vérification Origin/Referer sur toutes les mutations ─────────────
//
// La comparaison se faisait avec `startsWith` :
//
//     if (origin && !origin.startsWith(allowed)) …
//
// `https://pronowin.space.exemple.com` commence par `https://pronowin.space`.
// Un domaine appartenant à n'importe qui passait donc le contrôle, et la même
// erreur portait sur le `Referer`, où la comparaison portait en plus sur une
// adresse complète et non sur son origine.
//
// Deux origines sont identiques ou ne le sont pas : il n'y a pas de préfixe
// qui vaille.
app.use((req, res, next) => {
  if (!['POST', 'PUT', 'DELETE', 'PATCH'].includes(req.method)) return next();
  if (req.path === '/admin/login') return next(); // page de login exemptée

  // Sans `ADMIN_ORIGIN`, on retombe sur l'hôte de la requête — commodité de
  // développement, où le panneau tourne en http://localhost. En production la
  // variable est posée, et c'est elle qui fait autorité.
  const host    = req.headers['host'] ?? '';
  const attendue = origineDe(process.env.ADMIN_ORIGIN ?? `http://${host}`);
  const origin  = req.headers['origin'];
  const referer = req.headers['referer'];

  // Une origine attendue illisible ne peut rien autoriser. Refuser est la
  // seule suite correcte : laisser passer reviendrait à supprimer le contrôle
  // le jour d'une faute de frappe dans une variable d'environnement.
  if (!attendue) return res.status(403).send('Requête refusée (origine attendue illisible).');

  if (origin && origineDe(origin) !== attendue) {
    return res.status(403).send('Requête inter-origines refusée.');
  }
  if (!origin && referer && origineDe(referer) !== attendue) {
    return res.status(403).send('Requête inter-origines refusée.');
  }
  // Fail-closed : si Origin ET Referer sont tous les deux absents, on ne peut pas
  // vérifier la provenance de la requête — on la refuse plutôt que de la laisser passer.
  if (!origin && !referer) return res.status(403).send('Requête refusée (origine indéterminable).');
  next();
});

/**
 * Chemins où la session ne doit pas être revalidée.
 *
 * `/admin/login` et `/admin/logout` doivent rester joignables avec des cookies
 * périmés — sans quoi une session révoquée redirigerait vers la page de
 * connexion, qui la révoquerait à nouveau : une boucle.
 */
const CHEMINS_SANS_REVALIDATION = new Set(['/admin/login', '/admin/logout']);

/**
 * La session portée par ces cookies désigne-t-elle encore un accès existant ?
 *
 * Même règle que la revalidation ci-dessous, mais sans effet de bord : la page
 * de connexion s'en sert pour décider si elle peut renvoyer vers le tableau de
 * bord, plutôt que de se fier à la seule présence d'un cookie.
 */
function sessionEncoreValable(req) {
  if (!req.admin?.session) return false;
  if (roleDeSession(req) === 'main') return true;
  const compte = loadSubs().find(s => s.id === req.admin.subId);
  return !!compte && compte.isActive !== false;
}

/**
 * Les cookies qui portaient la session avant `lib/sessions.js`.
 *
 * Ils ne sont plus jamais lus. On les efface quand un navigateur les renvoie —
 * une session ouverte avant la mise à jour se retrouve ainsi à l'écran de
 * connexion, une fois — et surtout on les retire de `req.cookies` avant toute
 * autre lecture : aucune valeur posée par le client sous ces noms ne peut
 * atteindre le code qui suit.
 */
const COOKIES_HERITES = ['admin_token', 'admin_name', 'admin_role', 'admin_perms', 'admin_sub_id'];

/** Ouvre une session serveur et pose son identifiant dans le navigateur. */
function ouvrirSession(req, res, { role, subId = null, nom, jeton = null, dureeMs }) {
  // Une session déjà ouverte dans ce navigateur est remplacée, pas empilée.
  if (req.admin?.session) sessions.fermer(req.admin.session);
  const { id, session } = sessions.ouvrir({ role, subId, nom, jeton, dureeMs });
  const commun = { maxAge: dureeMs, secure: COOKIE_SECURE, sameSite: 'lax' };
  res.cookie(COOKIE_SESSION, id, { ...commun, httpOnly: true });
  res.cookie('admin_last_active', Date.now().toString(), { ...commun, httpOnly: false });
  req.admin = { session, role, nom, subId, jeton };
  return session;
}

/** Ferme la session en cours et efface ses cookies. */
function terminerSession(req, res) {
  if (req.admin?.session) sessions.fermer(req.admin.session);
  res.clearCookie(COOKIE_SESSION);
  res.clearCookie('admin_last_active');
  req.admin = { session: null, role: null, nom: null, subId: null, jeton: null };
}

/**
 * Rattache la requête à sa session serveur.
 *
 * `req.admin` est désormais la seule source de l'identité : rôle, nom, compte
 * et jeton d'API. Le jeton d'un sous-admin n'est d'ailleurs même pas dans sa
 * session : c'est celui du compte de service, qui ne quitte jamais ce
 * processus.
 */
app.use(async (req, res, next) => {
  try {
    for (const c of COOKIES_HERITES) {
      if (req.cookies && c in req.cookies) {
        delete req.cookies[c];
        res.clearCookie(c);
      }
    }
    const session = sessions.lire(req.cookies?.[COOKIE_SESSION]);
    if (!session && req.cookies?.[COOKIE_SESSION]) res.clearCookie(COOKIE_SESSION);
    req.admin = {
      session,
      role:  session?.role  ?? null,
      nom:   session?.nom   ?? null,
      subId: session?.subId ?? null,
      jeton: null,
    };
    if (session) {
      req.admin.jeton = session.role === 'sub' ? await jetonService() : session.jeton;
    }
    next();
  } catch (e) { next(e); }
});

// Données communes injectées dans tous les templates via res.locals
app.use((req, res, next) => {
  // Le rôle vient de la session tenue par ce serveur, jamais du client.
  const role = roleDeSession(req);

  // ── Inactivité ──
  //
  // « Session (min) », dans Paramètres → Sécurité connexion, n'était appliquée
  // que par une minuterie JavaScript dans la page ouverte. Elle repartait de
  // zéro à chaque chargement : on fermait l'onglet, on revenait le lendemain,
  // la session était toujours ouverte — jusqu'à 8 heures, ou 30 jours si
  // « Se souvenir de moi » était coché. Le réglage s'affichait pourtant comme
  // un indicateur de sécurité sur la page Paramètres.
  //
  // Le cookie `admin_last_active` existait déjà pour porter cette date d'une
  // page à l'autre, et le script définissait même de quoi le lire — sans
  // jamais s'en servir pour décider. Le serveur ne le regardait pas non plus.
  //
  // Il est modifiable depuis les outils du navigateur (`httpOnly:false`, pour
  // le compte à rebours affiché). Cela ne protège donc pas de quelqu'un qui
  // veut prolonger sa propre session, mais du cas réel : un panneau
  // d'administration laissé ouvert sur un poste partagé.
  const derniereActivite = Number(req.cookies?.admin_last_active);
  if (req.admin.session
      && !CHEMINS_SANS_REVALIDATION.has(req.path)
      && Number.isFinite(derniereActivite)
      && Date.now() - derniereActivite > (loadSettings().sessionTimeoutMin ?? 30) * 60000) {
    terminerSession(req, res);
    if (req.path.startsWith('/admin/api/')) {
      return res.status(401).json({ error: 'Session expirée.' });
    }
    return res.redirect('/admin/login?expired=1');
  }

  let   perms = [];
  if (role === 'sub') {
    // ── Revalider la session contre le fichier des comptes ──
    //
    // Les cookies de session portaient à eux seuls l'identité, le rôle et les
    // permissions, signés une fois à la connexion et jamais relus ensuite. Trois
    // conséquences, mesurées sur le serveur réel :
    //
    //   - « Désactiver » un sous-admin ne fermait pas sa session : il continuait
    //     à travailler. Le bouton bloquait la prochaine connexion, pas celle en
    //     cours — et la page affichait « Inactif » pendant ce temps ;
    //   - le supprimer non plus : un compte qui n'existait plus ouvrait encore
    //     les pages, avec ses droits, jusqu'à l'expiration du cookie — 30 jours
    //     si « Se souvenir de moi » était coché ;
    //   - lui retirer ses permissions ne s'appliquait pas davantage : le cookie
    //     signé gardait celles d'avant.
    //
    // Ces trois boutons sont les seuls moyens de reprendre un accès. Ils
    // annonçaient une révocation qui n'avait pas lieu, ce qui est pire que de
    // ne pas les avoir : on croit l'accès coupé et on passe à autre chose.
    //
    // Les permissions sont relues dans le fichier à chaque requête : le
    // fichier est la seule source qu'un administrateur peut corriger. Le
    // compte, lui, vient de la session serveur — il était lu dans un cookie
    // `admin_sub_id` que le navigateur pouvait réécrire, ce qui donnait les
    // droits de n'importe quel collègue dont on connaissait l'identifiant.
    if (!CHEMINS_SANS_REVALIDATION.has(req.path)) {
      const compte = loadSubs().find(s => s.id === req.admin.subId);
      // Fermeture par défaut : un compte introuvable ne prouve plus rien.
      if (!compte || compte.isActive === false) {
        terminerSession(req, res);
        // Une réponse JSON pour les appels de fond : les rediriger vers une page
        // HTML ferait afficher du HTML dans un compteur de badges.
        if (req.path.startsWith('/admin/api/')) {
          return res.status(401).json({ error: 'Session révoquée.' });
        }
        return res.redirect('/admin/login?fin=' + (compte ? 'desactive' : 'inconnu'));
      }
      perms = compte.permissions ?? [];
    }
  }
  // « Différent de sub » valait « main ». Un rôle absent ou illisible passait
  // donc pour l'administrateur principal — le défaut symétrique de celui du
  // cookie, au même endroit. C'est désormais « main » qu'il faut être.
  res.locals.sessionValide = role !== null;
  res.locals.adminRole  = role ?? 'inconnu';
  res.locals.adminName  = req.admin.nom ?? 'Admin';
  res.locals.adminPerms = perms;
  res.locals.isMain     = role === 'main';
  res.locals.hasPerm = (key, level = 'read') => {
    if (role === 'main') return true;
    return permLevelOk(getPermLevel(perms, key), level);
  };
  res.locals.getPermLevel = (key) => role === 'main' ? 'delete' : getPermLevel(perms, key);
  // Pour les vues qui lisent les permissions d'un AUTRE compte que la session
  // en cours — la fenetre d'edition des sous-admins. `_perm_table.ejs` en
  // gardait sa propre copie, qui renvoyait le premier niveau au lieu du plus
  // eleve : la fenetre n'affichait qu'une case cochee sur trois.
  res.locals.niveauAccorde = niveauAccorde;
  // Injecter les paramètres globaux (annonce, titre…)
  const settings = loadSettings();
  res.locals.settings = settings;

  // ── Qui agit, pour toute la suite de la requête ──
  //
  // Posé ici, et pas plus tôt : le rôle et les permissions viennent d'être
  // établis juste au-dessus, à partir du cookie signé et du fichier des
  // comptes. Les poser avant reviendrait à déclarer une identité qu'on n'a pas
  // encore vérifiée.
  executerAvecActeur({
    id:    role === 'main' ? 'main' : (req.admin.subId ?? 'inconnu'),
    nom:   res.locals.adminName,
    role:  role === 'main' ? 'main' : 'sub',
    perms: role === 'main' ? [] : perms,
  }, next);
});

// Middleware d'authentification
function requireAuth(req, res, next) {
  // Une session n'existe que si ce serveur l'a ouverte : aucun cookie posé par
  // le client ne peut en tenir lieu.
  if (!req.admin?.session || !res.locals.sessionValide) return res.redirect('/admin/login');
  // Sans jeton d'API, chaque page se solderait par un 401 sans explication.
  if (!req.admin.jeton) {
    return res.status(503).render('error', {
      status: 503, title: 'API injoignable',
      message: 'Le panneau n\'obtient plus de jeton du compte de service.',
      hint: 'Vérifiez ADMIN_SERVICE_EMAIL et ADMIN_SERVICE_PASSWORD dans admin-web/.env.',
      back: '/admin/login',
    });
  }
  next();
}

/**
 * L'API a refusé le jeton de cette session.
 *
 * Pour l'administrateur principal, c'est la fin de sa session : son jeton lui
 * est propre et a expiré. Pour un sous-admin, c'est le jeton du compte de
 * service qui ne vaut plus : on l'oublie pour en redemander un à la requête
 * suivante, et la session se ferme — elle ne repose sur rien de valide.
 */
function jetonRefuse(req, res) {
  if (roleDeSession(req) === 'sub') _jetonService = null;
  terminerSession(req, res);
}

// Helper : gérer les erreurs API dans les routes (évite la duplication)
function apiError(res, e, fallbackUrl) {
  const status = e.response?.status;
  if (status === 401) {
    jetonRefuse(res.req, res);
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

/**
 * Applique le fuseau horaire choisi dans les Paramètres.
 *
 * Le réglage était enregistré, réaffiché à lui-même dans la page… et appliqué
 * nulle part : les 94 formatages de date du panneau utilisaient tous le fuseau
 * du serveur. Le changer ne changeait rien, sans que rien ne le dise.
 *
 * `process.env.TZ` agit sur toutes les dates formatées ensuite, ce qui évite de
 * passer une option `timeZone` à chaque appel. Vérifié à chaud sur cette
 * plateforme avant d'être retenu.
 */
function appliquerFuseau() {
  const tz = loadSettings().timezone;
  if (!tz) return;
  try {
    // Un fuseau invalide ferait échouer tout formatage ultérieur : on le teste
    // avant de l'appliquer.
    new Date().toLocaleString('fr-FR', { timeZone: tz });
    process.env.TZ = tz;
  } catch {
    console.warn(`[admin] Fuseau horaire « ${tz} » inconnu — réglage ignoré.`);
  }
}
appliquerFuseau();

// ─── RATE LIMITING (login) ───────────────────────────────────────────────────
function getLoginMaxAttempts() { return loadSettings().loginMaxAttempts ?? 5; }
function getLoginWindowMs()    { return (loadSettings().loginBlockMinutes ?? 15) * 60000; }
const loginAttempts      = new Map();          // ip → { count, blockedUntil }

// Nettoyer les entrées expirées toutes les heures
setInterval(() => {
  const now = Date.now();
  for (const [ip, entry] of loginAttempts) {
    if (entry.blockedUntil && entry.blockedUntil < now) loginAttempts.delete(ip);
  }
}, 3600000);

/**
 * L'adresse du client, telle que nginx l'a vue.
 *
 * Elle était lue dans la **première** valeur de `X-Forwarded-For`. Or nginx
 * est réglé en `$proxy_add_x_forwarded_for` : il ajoute l'adresse réelle à la
 * fin de ce que le client a envoyé. La première valeur était donc choisie par
 * le client — en la changeant à chaque essai, on remettait le compteur de
 * tentatives à zéro, et la protection contre la force brute du formulaire de
 * connexion ne protégeait de rien (vérifié sur la configuration nginx de
 * production le 24 septembre 2026, constat S9).
 *
 * `trust proxy: 'loopback'` fait lire à Express la valeur ajoutée par le
 * proxy local, et seulement quand la connexion vient bien de lui : un appel
 * direct au port du panneau garde l'adresse de sa socket, quel que soit
 * l'en-tête.
 */
app.set('trust proxy', 'loopback');
function getClientIP(req) {
  return req.ip ?? req.socket?.remoteAddress ?? '0.0.0.0';
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
  if (entry.count >= getLoginMaxAttempts()) {
    entry.blockedUntil = now + getLoginWindowMs();
    entry.count        = 0;
  }
  loginAttempts.set(ip, entry);
  return entry;
}

function clearAttempts(ip) {
  loginAttempts.delete(ip);
}

// ─── SESSION REFRESH (activité) ──────────────────────────────────────────────
app.use((req, res, next) => {
  // Rafraîchir le cookie d'activité sur chaque requête authentifiée (hors API badges/search)
  if (req.admin?.session && !req.path.startsWith('/admin/api/')) {
    const sessionTimeoutMs = (loadSettings().sessionTimeoutMin ?? 30) * 60000;
    res.cookie('admin_last_active', Date.now().toString(), {
      maxAge: sessionTimeoutMs + 120000,
      secure: COOKIE_SECURE,
      sameSite: 'lax',
      httpOnly: false,   // lisible par le JS client pour le countdown
    });
  }
  next();
});

// ─── AUTH ─────────────────────────────────────────────────────────────────────
app.get('/admin/login', (req, res) => {
  // Ne renvoyer vers le tableau de bord qu'une session que le tableau de bord
  // acceptera. La présence du seul cookie `admin_token` suffisait : un
  // sous-admin révoqué dont le navigateur gardait ce cookie était renvoyé vers
  // le tableau de bord, qui le renvoyait ici, qui le renvoyait là — une boucle
  // de redirections dont on ne sort qu'en vidant ses cookies à la main.
  // `/admin/login` est justement le chemin où la revalidation ne s'applique
  // pas, pour ne pas boucler ; c'est donc ici que la vérification doit se
  // refaire.
  if (sessionEncoreValable(req)) {
    return res.redirect('/admin/dashboard');
  }
  // Une seule lecture : `getLoginMaxAttempts` relit settings.json à chaque appel.
  const maxTentatives = getLoginMaxAttempts();
  // Une session peut finir de trois façons, et les confondre envoie chercher au
  // mauvais endroit : « session expirée » sur un compte désactivé fait
  // recommencer indéfiniment une connexion qui ne peut pas aboutir.
  const MOTIFS = {
    desactive: 'Ce compte a été désactivé. Contactez l\'administrateur principal.',
    inconnu:   'Ce compte n\'existe plus. Contactez l\'administrateur principal.',
  };
  const motif = MOTIFS[req.query.fin] ?? null;
  res.render('login', {
    error: null, expired: req.query.expired === '1' || motif !== null, motif,
    locked: null, remaining: maxTentatives, maxAttempts: maxTentatives, blockedUntilMs: null, username: '',
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
      remaining: 0, maxAttempts: getLoginMaxAttempts(), username: username ?? '',
    });
  }

  // ── 1. Sous-admins locaux ──
  const empSubs = empreinteSubs();
  const subs = loadSubs();
  // Comparaison sur la forme canonique, la même qu'à la création : sans elle,
  // « Lonfo_lookman » ne retrouvait pas le compte qu'il avait lui-même créé.
  const saisi = normaliserIdentifiant(username);
  const sub  = subs.find(s => normaliserIdentifiant(s.username) === saisi && s.isActive !== false && checkPwd(password, s.passwordHash));
  if (sub) {
    clearAttempts(ip);
    // Le jeton du compte de service reste dans ce processus : la session du
    // sous-admin n'en porte pas, et son navigateur encore moins. On vérifie
    // seulement qu'il est disponible — une session ouverte sans lui ne
    // montrerait que des pages vides.
    const apiToken = await jetonService({ forcer: true });

    // ── Refuser une session qu'on sait vide ──
    //
    // Sans jeton d'API, `admin_token` était posé à la chaîne vide. Or
    // `requireAuth` la traite comme une absence de session : le sous-admin
    // était renvoyé à l'écran de connexion à la page suivante, sans message,
    // après un « Connexion réussie » enregistré au journal. Vu de lui, taper
    // les bons identifiants ramenait au formulaire — indistinguable d'un mot de
    // passe faux, et introuvable dans le journal, qui affichait une réussite.
    //
    // C'est arrivé en production : `ADMIN_SERVICE_PASSWORD` ne correspondait
    // plus au compte `admin@pronowin.com` et `ADMIN_API_TOKEN` n'était pas
    // renseigné. L'admin principal, lui, continuait d'entrer normalement — il
    // obtient son jeton de sa propre authentification — donc rien ne signalait
    // la panne côté panneau.
    //
    // Une session vide ne s'ouvre plus, et l'écran dit ce qui manque.
    if (!apiToken) {
      logAction(req, 'login_failed',
        `Sous-admin: ${sub.name} — compte de service API invalide`,
        { username: sub.username, cause: 'api_token_absent' });
      console.error('[admin] Connexion de sous-admin refusée : aucun jeton d\'API. '
        + 'Vérifiez ADMIN_SERVICE_EMAIL / ADMIN_SERVICE_PASSWORD, ou ADMIN_API_TOKEN.');
      return res.render('login', {
        error: 'Le panneau n\'est pas relié à l\'API : le compte de service est '
             + 'refusé. Vos identifiants sont bons — c\'est la configuration du '
             + 'serveur qui bloque. Prévenez l\'administrateur principal.',
        expired: false, locked: null, remaining: getLoginMaxAttempts(),
        maxAttempts: getLoginMaxAttempts(), blockedUntilMs: null, username,
      });
    }

    sub.lastLoginAt = new Date().toISOString();
    // Ecriture gardee : sans empreinte, l'enregistrement de la date de
    // connexion ecrasait une modification de permissions faite entre-temps.
    saveSubsSi(subs, empSubs);
    ouvrirSession(req, res, { role: 'sub', subId: sub.id, nom: sub.name, dureeMs: cookieMaxAge });
    logAction(req, 'login', `Sous-admin: ${sub.name}`, { username: sub.username });
    return res.redirect('/admin/dashboard');
  }

  // ── Vérifier si le username ressemble à un sous-admin inactif ──
  const inactiveSub = subs.find(s => normaliserIdentifiant(s.username) === saisi && s.isActive === false);
  if (inactiveSub) {
    recordFailedAttempt(ip);
    return res.render('login', { error: 'Ce compte est désactivé. Contactez l\'administrateur principal.', expired: false, locked: null, remaining: getLoginMaxAttempts(), maxAttempts: getLoginMaxAttempts(), blockedUntilMs: null, username });
  }

  // ── 2. Admin principal via l'API backend ──
  try {
    // Le formulaire envoie "username", l'API attend "email"
    const r = await axios.post(`${API_URL}/admin/login`, { email: username, password }, { timeout: 10000 });

    // ── Seul un super-administrateur de l'API est « principal » ici ──
    //
    // Toute connexion réussie à l'API ouvrait une session « main », quel que
    // soit le rôle renvoyé. Un compte créé pour un analyste — rôle `analyst`
    // côté API — recevait donc tous les droits du panneau, gestion des
    // sous-admins et réglages compris (constat S8). Le panneau n'a pas de rôle
    // intermédiaire à lui donner : on refuse, en le disant.
    if (r.data?.admin?.role !== 'super_admin') {
      recordFailedAttempt(ip);
      req.admin = { ...req.admin, nom: r.data?.admin?.name ?? username, role: null };
      logAction(req, 'login_failed', `Identifiant: ${username}`,
        { ip, cause: 'role_api_' + (r.data?.admin?.role ?? 'inconnu') });
      return res.render('login', {
        error: 'Ce compte existe côté API mais n\'a pas le rôle super-administrateur : '
             + 'le panneau ne lui ouvre pas de session. Demandez un compte de sous-admin.',
        expired: false, locked: null, remaining: getLoginMaxAttempts(),
        maxAttempts: getLoginMaxAttempts(), blockedUntilMs: null, username,
      });
    }

    clearAttempts(ip);
    ouvrirSession(req, res, {
      role: 'main', nom: r.data.admin.name, jeton: r.data.token,
      // Le jeton d'API de l'administrateur expire en 8 heures : une session
      // plus longue ne ferait que durer sur un jeton mort.
      dureeMs: Math.min(cookieMaxAge, 8 * 3600000),
    });
    logAction(req, 'login', `Admin principal: ${r.data.admin.name}`);
    res.redirect('/admin/dashboard');
  } catch (e) {
    const entry     = recordFailedAttempt(ip);
    const remaining = Math.max(0, getLoginMaxAttempts() - (entry.count ?? 0));
    const errMsg    = e.response?.data?.message ?? 'Identifiants incorrects.';
    req.admin = { ...req.admin, nom: username, role: null };
    logAction(req, 'login_failed', `Identifiant: ${username}`, { ip });
    // Si bloqué après cet échec
    const nowBlocked = checkRateLimit(ip);
    if (nowBlocked.blocked) {
      return res.render('login', {
        error: null, expired: false,
        locked: `Trop de tentatives. Réessayez dans ${nowBlocked.remainMin} minute${nowBlocked.remainMin > 1 ? 's' : ''}.`,
        blockedUntilMs: loginAttempts.get(ip)?.blockedUntil ?? null,
        remaining: 0, maxAttempts: getLoginMaxAttempts(), username,
      });
    }
    res.render('login', { error: errMsg, expired: false, locked: null, remaining, maxAttempts: getLoginMaxAttempts(), blockedUntilMs: null, username });
  }
});

app.get('/admin/logout', (req, res) => {
  if (req.admin?.session) logAction(req, 'logout', req.admin.nom ?? '');
  terminerSession(req, res);
  res.redirect('/admin/login');
});

// ─── DASHBOARD ────────────────────────────────────────────────────────────────
app.get('/admin/dashboard', requireAuth, async (req, res) => {
  const a = api(req.admin.jeton);
  // La file de travail montrait à tout sous-admin les versements et les
  // preuves en attente, quelles que soient ses permissions — ce que les badges
  // filtraient déjà. L'API refuse désormais ces lectures à qui n'a pas le
  // droit : on ne les demande donc qu'au nom de qui l'a.
  const voitTx  = res.locals.hasPerm('transactions');
  const voitAbo = res.locals.hasPerm('abonnements');
  const vide    = Promise.resolve({ data: { data: [], total: 0 } });
  const [statsRes, pendingRes, proofsRes, onlineRes] = await Promise.allSettled([
    a.get('/pronostics/admin/stats'),
    voitTx  ? a.get('/payments/admin/pending?page=1')     : vide,
    voitAbo ? a.get('/subscriptions/admin/proofs?page=1') : vide,
    a.get('/admin/stats/online'),  // non caché — toujours frais
  ]);
  if ([statsRes, pendingRes, proofsRes].some(r => r.status === 'rejected' && r.reason?.response?.status === 401)) {
    jetonRefuse(req, res); return res.redirect('/admin/login?expired=1');
  }

  const now        = Date.now();
  const allBans    = loadBans();
  const activeBans = allBans.filter(b => b.active && (!b.expiresAt || new Date(b.expiresAt).getTime() > now));
  const recentLogs = journalVisiblePar(loadLogs(), req).slice(0, 8);

  const baseStats  = statsRes.status === 'fulfilled' ? statsRes.value.data : { totalUsers:0, premiumUsers:0, pendingTx:0, publishedToday:0 };
  const activeUsers = onlineRes.status === 'fulfilled' ? (onlineRes.value.data.count ?? 0) : 0;

  const pending = pendingRes.status === 'fulfilled' ? pendingRes.value.data : { data:[], total:0 };
  const proofs  = proofsRes.status  === 'fulfilled' ? proofsRes.value.data  : { data:[], total:0 };

  /**
   * File de travail.
   *
   * Le tableau de bord montrait des compteurs : combien d'utilisateurs, combien
   * de pronostics. Un compteur ne dit pas quoi faire. Ces entrees sont les
   * seules choses qui attendent une action, avec leur anciennete — une preuve
   * qui patiente depuis trois jours, c'est un client qui a paye et qui attend.
   * L'ordre est celui de l'urgence, et la liste vide est un etat legitime.
   */
  const heures = iso => iso ? Math.floor((now - new Date(iso).getTime()) / 3600000) : 0;
  const plusVieux = lignes => lignes.reduce((v, l) => Math.max(v, heures(l.createdAt)), 0);
  const age = h => h >= 48 ? `depuis ${Math.floor(h / 24)} jours`
                 : h >= 24 ? 'depuis plus de 24 h'
                 : h >= 1  ? `depuis ${h} h` : "à l'instant";

  const file = [];
  if (proofs.total > 0) {
    const h = plusVieux(proofs.data ?? []);
    file.push({ cle:'proofs', urgence: h >= 24 ? 'haute' : 'normale', icone:'crown',
      titre: `${proofs.total} preuve${proofs.total > 1 ? 's' : ''} Premium à valider`,
      detail: `La plus ancienne attend ${age(h)}. Chacune est un abonnement payé qui n'est pas encore actif.`,
      action:'Valider', lien:'/admin/abonnements' });
  }
  if (pending.total > 0) {
    const h = plusVieux(pending.data ?? []);
    file.push({ cle:'versements', urgence: h >= 48 ? 'haute' : 'normale', icone:'money',
      titre: `${pending.total} versement${pending.total > 1 ? 's' : ''} de parrainage à effectuer`,
      detail: `Le plus ancien attend ${age(h)}. L'argent n'a pas encore été envoyé au parrain.`,
      action:'Traiter', lien:'/admin/transactions' });
  }
  const aRestaurer = bansARestaurer();
  if (aRestaurer.length) {
    file.push({ cle:'bans', urgence:'haute', icone:'ban',
      titre: `${aRestaurer.length} compte${aRestaurer.length > 1 ? 's' : ''} encore suspendu${aRestaurer.length > 1 ? 's' : ''} après expiration du ban`,
      detail: "Le bannissement a pris fin mais l'accès n'a pas été rendu. Ouvrir la page suffit à le rétablir.",
      action:'Rétablir', lien:'/admin/bans' });
  }
  // Deux situations opposées, longtemps confondues sous le même message.
  //
  // Le repli côté serveur exige `isPremium: false`. Si tout ce qui est publié
  // aujourd'hui est premium, il ne trouve rien : `/daily-free` répond 404 et le
  // visiteur non abonné ne voit **aucun** pronostic. L'alerte annonçait pourtant
  // que « l'application choisit alors le premier par ordre d'heure » — une
  // phrase rassurante, fausse exactement dans le cas grave.
  if ((baseStats.publiablesAujourdhui ?? 0) > 0 && (baseStats.vitrineDuJour ?? 0) === 0) {
    const gratuits = baseStats.gratuitsAujourdhui ?? 0;
    file.push(gratuits === 0
      ? { cle:'vitrine', urgence:'haute', icone:'star',
          titre: "Vitrine vide : aucun pronostic gratuit aujourd'hui",
          detail: `${baseStats.publiablesAujourdhui} pronostic(s) publié(s), tous premium. `
                + "Un visiteur non abonné n'en voit donc aucun — l'accueil n'a rien "
                + "à lui montrer. Rendez-en un gratuit pour ouvrir la vitrine.",
          action:'Ouvrir la vitrine', lien:'/admin/pronostics' }
      : { cle:'vitrine', urgence:'normale', icone:'star',
          titre: "Aucun pronostic gratuit désigné pour aujourd'hui",
          detail: `L'application affiche alors le premier des ${gratuits} pronostic(s) `
                + "gratuit(s), par ordre d'heure de match : c'est un tri qui décide de votre vitrine.",
          action:'Choisir', lien:'/admin/pronostics' });
  }

  res.render('dashboard', {
    adminName: req.admin.nom ?? 'Admin',
    stats:   { ...baseStats, activeUsers },
    pending, proofs,
    activeBansCount: activeBans.length,
    recentBans:      activeBans.slice(0, 3),
    recentLogs,
    file,
  });
});

// ─── UTILISATEURS ─────────────────────────────────────────────────────────────
app.get('/admin/api/search', requireAuth, async (req, res) => {
  const q = (req.query.q ?? '').trim();
  if (q.length < 2) return res.json({ users: [], transactions: [], pronostics: [], bans: [] });

  const a      = api(req.admin.jeton);
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
    // Le reste de la reponse est filtre par permission ; cette liste ne l'etait
    // pas et divulguait tous les identifiants bannis.
    _bannedIds: canU ? [...activeBanSet] : [],
  });
});

// ─── BADGES LIVE ──────────────────────────────────────────────────────────────
app.get('/admin/api/badges', requireAuth, async (req, res) => {
  // Ces compteurs renseignaient sur les versements et les preuves en attente
  // quelles que soient les permissions : un sous-admin cantonne aux tutoriels
  // apprenait combien d'argent attendait d'etre verse. On ne compte desormais
  // que ce qu'il a le droit de consulter.
  const a       = api(req.admin.jeton);
  const voitTx  = res.locals.hasPerm('transactions');
  const voitAbo = res.locals.hasPerm('abonnements');
  const [txRes, proofsRes] = await Promise.allSettled([
    voitTx  ? a.get('/payments/admin/pending?page=1&per_page=1')     : Promise.resolve(null),
    voitAbo ? a.get('/subscriptions/admin/proofs?page=1&per_page=1') : Promise.resolve(null),
  ]);
  res.json({
    transactions: (voitTx  && txRes.status     === 'fulfilled' && txRes.value)     ? (txRes.value.data.total     ?? 0) : 0,
    proofs:       (voitAbo && proofsRes.status === 'fulfilled' && proofsRes.value) ? (proofsRes.value.data.total ?? 0) : 0,
  });
});

// ─── STATISTIQUES ─────────────────────────────────────────────────────────────
app.get('/',      (req, res) => res.redirect('/admin/dashboard'));
app.get('/admin', (req, res) => res.redirect('/admin/dashboard'));

// ─── BANS ─────────────────────────────────────────────────────────────────────
app.get('/admin/api/live', requireAuth, (req, res) => {
  res.setHeader('Content-Type',  'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection',    'keep-alive');
  res.setHeader('X-Accel-Buffering', 'no');
  res.flushHeaders();
  res.write('event: connected\ndata: {"ok":true}\n\n');
  // Les permissions accompagnent le client : la diffusion doit pouvoir filtrer.
  const client = { res, perms: res.locals.isMain ? null : (res.locals.adminPerms ?? []) };
  sseClients.add(client);
  fetchLiveKPIs(req.admin.jeton).then(kpis => {
    if (kpis) { try { res.write(`event: kpis\ndata: ${JSON.stringify(kpisPour(client.perms, kpis))}\n\n`); } catch {} }
  });
  req.on('close', () => sseClients.delete(client));
});

// ─── GESTIONNAIRE D'ERREURS GLOBAL ────────────────────────────────────────────
// eslint-disable-next-line no-unused-vars
app.use((err, req, res, _next) => {
  console.error('[ERROR]', req.method, req.path, err.message ?? err);

  const isApi = req.path.startsWith('/admin/api/');
  if (isApi) return res.status(500).json({ error: 'Erreur serveur interne.' });

  // Erreur de token expiré
  if (err.response?.status === 401) {
    jetonRefuse(req, res);
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

/**
 * L'auteur déclaré des tâches de fond du panneau.
 *
 * L'API exige désormais une délégation signée sur toute requête, lecture
 * comprise : le jeton ne quitte plus ce processus, donc un appel sans
 * délégation ne peut venir que d'ailleurs. Les minuteries — levée des bans
 * expirés, KPI temps réel — n'ont pas de requête et donc personne derrière
 * elles ; elles s'annoncent sous ce nom, qui se lit tel quel dans les
 * journaux de l'API.
 *
 * La levée des bans expirés écrivait déjà sans délégation, et l'API la
 * refusait depuis que la délégation est exigée sur les écritures : les
 * comptes restaient suspendus jusqu'à la visite d'un administrateur.
 */
const ACTEUR_SYSTEME = { id: 'systeme', nom: 'Tâche automatique du panneau', role: 'main', perms: [] };
function enTantQueSysteme(travail) {
  return new Promise((resolve, reject) => {
    executerAvecActeur(ACTEUR_SYSTEME, () => { Promise.resolve().then(travail).then(resolve, reject); });
  });
}

/**
 * Jeton d'API pour les tâches de fond.
 *
 * Les tâches périodiques n'ont pas de requête, donc pas de session : elles
 * lisaient `ADMIN_API_TOKEN`, une variable qui n'est pas définie. Le jeton
 * partait donc vide, l'API répondait 401, et comme les appels sont groupés dans
 * un `Promise.allSettled`, l'échec devenait un objet rempli de `null` diffusé
 * toutes les dix secondes. Les compteurs du tableau de bord ne se sont jamais
 * rafraîchis, sans le moindre message.
 *
 * Le compte de service existe pourtant déjà : `ADMIN_SERVICE_EMAIL` et
 * `ADMIN_SERVICE_PASSWORD` servent à la connexion des sous-admins. On s'en sert
 * ici aussi, avec un cache — se reconnecter toutes les dix secondes serait
 * absurde — et un repli sur `ADMIN_API_TOKEN` s'il est renseigné.
 */
let _jetonService  = null;
let _jetonExpireLe = 0;

async function jetonService({ forcer = false } = {}) {
  if (!forcer && _jetonService && Date.now() < _jetonExpireLe) return _jetonService;

  const email = process.env.ADMIN_SERVICE_EMAIL;
  const pass  = process.env.ADMIN_SERVICE_PASSWORD;
  if (email && pass) {
    try {
      const r = await axios.post(`${API_URL}/admin/login`, { email, password: pass }, { timeout: 5000 });
      if (r.data?.token) {
        _jetonService  = r.data.token;
        // Renouvellement bien avant l'expiration réelle du jeton.
        _jetonExpireLe = Date.now() + 30 * 60 * 1000;
        return _jetonService;
      }
    } catch { /* on retombe sur la variable d'environnement ci-dessous */ }
  }
  const repli = process.env.ADMIN_API_TOKEN ?? '';
  return repli || null;
}

/** Vrai si aucune identité de service n'est configurée. */
function serviceConfigure() {
  return !!((process.env.ADMIN_SERVICE_EMAIL && process.env.ADMIN_SERVICE_PASSWORD)
            || process.env.ADMIN_API_TOKEN);
}

/**
 * Contrôle du compte de service au démarrage.
 *
 * Ce compte conditionne trois choses : les KPI temps réel, la réactivation des
 * bans expirés, et le jeton d'API remis aux sous-admins à la connexion. Quand
 * il échoue, tout cela cesse en silence — un sous-admin reçoit un jeton vide et
 * chacune de ses pages se solde par un 401, sans que rien n'explique pourquoi.
 * On le vérifie donc une fois au démarrage, et on le dit franchement.
 */
setTimeout(async () => {
  if (!serviceConfigure()) {
    console.warn('\n  Aucun compte de service configure (ADMIN_SERVICE_EMAIL / ADMIN_SERVICE_PASSWORD).');
    console.warn('   Consequences : KPI temps reel inactifs, bans expires non leves cote API,');
    console.warn('   et les sous-admins recoivent un jeton vide : leurs pages de donnees seront vides.\n');
    return;
  }
  const t = await jetonService({ forcer: true });
  if (t) {
    console.log('Compte de service operationnel : KPI temps reel et levee des bans actifs.');
  } else {
    console.warn('\n  Le compte de service est configure mais l\'authentification echoue.');
    console.warn(`   Verifiez ADMIN_SERVICE_EMAIL (${process.env.ADMIN_SERVICE_EMAIL}) : il doit`);
    console.warn('   correspondre a un compte admin existant et actif cote API.');
    console.warn('   Sans cela : pas de KPI temps reel, les bans expires restent suspendus,');
    console.warn('   et les sous-admins n\'auront aucune donnee.\n');
  }
}, 3000);

// Timer interne : push KPIs toutes les 10 secondes si au moins 1 client connecté
// On utilise le token de l'admin principal (ADMIN_API_TOKEN) pour les appels périodiques
let _kpiAlerte = false;
setInterval(async () => {
  if (sseClients.size === 0) return;
  const token = await jetonService();
  if (!token) {
    if (!_kpiAlerte) {
      _kpiAlerte = true;
      console.warn('⚠️  KPI temps réel désactivés : ni ADMIN_SERVICE_EMAIL/PASSWORD ni ADMIN_API_TOKEN.');
    }
    return;
  }
  let kpis = await enTantQueSysteme(() => fetchLiveKPIs(token));
  // Tout à null = jeton refusé. On le renouvelle une fois avant d'abandonner,
  // plutôt que de diffuser des valeurs vides comme avant.
  if (kpis && kpis.users_total === null && kpis.tx_pending === null && kpis.proofs_pending === null) {
    const frais = await jetonService({ forcer: true });
    kpis = frais ? await enTantQueSysteme(() => fetchLiveKPIs(frais)) : null;
  }
  if (kpis && (kpis.users_total !== null || kpis.tx_pending !== null || kpis.proofs_pending !== null)) {
    sseBroadcast('kpis', kpis, perms => kpisPour(perms, kpis));
  }
}, 10000);

// Ping SSE toutes les 30s pour garder la connexion vivante (anti-timeout proxy)
setInterval(() => {
  if (sseClients.size === 0) return;
  const msg = ': ping\n\n';
  for (const client of sseClients) {
    const res = client.res ?? client;
    try { res.write(msg); } catch { sseClients.delete(client); }
  }
}, 30000);

// Exposer sseBroadcast pour les routes (broadcast après chaque action mutante)
app.locals.sseBroadcast = sseBroadcast;

// ─── DÉMARRAGE ────────────────────────────────────────────────────────────────

// ─── Éléments partagés entre modules de routes ───────────────────────────────
// Remontés ici parce qu'ils traversent les frontières de modules : les
// dupliquer aurait laissé deux versions vivre côte à côte, dont deux listes
// blanches de sécurité (STATS_ENDPOINTS) susceptibles de diverger.

const STATS_ENDPOINTS = new Set([
  'dashboard', 'revenue', 'users', 'top-users', 'signups', 'pronostics',
  'online', 'monthly', 'leagues',
]);

function back(req, msg, isError = false) {
  const ref = req.headers.referer ?? '/admin/dashboard';
  return ref + (ref.includes('?') ? '&' : '?') + (isError ? 'error' : 'success') + '=' + encodeURIComponent(msg);
}

const SEGMENTS = [
  { key: 'all',            label: 'Tous les utilisateurs',       icon: 'users', desc: 'Tout le monde' },
  { key: 'premium',        label: 'Membres Premium uniquement',  icon: 'crown', desc: 'Abonnement non expiré' },
  { key: 'free',           label: 'Membres Gratuits uniquement', icon: 'user', desc: 'Non-abonnés' },
  { key: 'active_30',      label: 'Actifs ce mois',              icon: 'dot', desc: 'Vus < 30j' },
  { key: 'inactive_30',    label: 'Inactifs (> 30 jours)',       icon: 'sleep', desc: 'Vus > 30j' },
  { key: 'new_7',          label: 'Nouveaux inscrits (7j)',       icon: 'sparkle', desc: 'Inscription < 7j' },
];

async function fetchTutorialCategories(a) {
  try {
    const r = await a.get('/admin/tutorials/categories');
    return r.data;
  } catch (_) {
    return ['valuebet', 'bankroll', 'analyse', 'strategie', 'psychologie'];
  }
}

async function fetchTutorialLevels(a) {
  try {
    const r = await a.get('/admin/tutorials/levels');
    return r.data;
  } catch (_) {
    return ['beginner', 'intermediate', 'advanced'];
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MONTAGE DES MODULES DE ROUTES
// ═══════════════════════════════════════════════════════════════════════════
//
// Ce fichier faisait 2 586 lignes pour 89 routes. Les 80 routes métier vivent
// désormais dans `routes/`, regroupées par domaine — on cherche un écran, pas
// un verbe HTTP. Restent ici : la configuration, les middlewares, les
// helpers partagés, et les 9 routes de tronc (connexion, tableau de bord,
// recherche globale, badges).
//
// Le contexte est passé explicitement plutôt que réimporté par chaque module :
// il n'y a qu'une configuration, qu'un client Axios et qu'un jeu de fichiers
// de données. Les dupliquer aurait créé autant d'occasions de les faire
// diverger — à commencer par STATS_ENDPOINTS, qui est une liste blanche de
// sécurité.
const contexteRoutes = {
  api, requireAuth, requireMain, requirePerm, logAction, sendCSV,
  loadSubs, saveSubs, empreinteSubs, saveSubsSi,
  loadSettings, saveSettings, empreinteSettings, saveSettingsSi,
  loadNews, saveNews, loadBans, saveBans, loadLogs, saveLogs,
  loadNotifHistory, saveNotifHistory, getNewsCategories,
  uid, hashPwd, checkPwd, normaliserIdentifiant, journalVisiblePar, estMoi,
  getClientIP, ecrireJson, sessions,
  ERR_ECRITURE, ERR_CONFLIT, PERMISSIONS, DATA_DIR, LOG_MAX,
  STATS_ENDPOINTS, NEWS_DEFAULT_CATEGORIES,
  fs, path, slugify, sanitize, clampInt, sseBroadcast,
  banUser, unbanUser, getActiveBan, ACTION_LABELS, appliquerFuseau,
  bansARestaurer, reconcilierBansExpires,
  SA_FILE, BANS_FILE, NEWS_FILE, LOG_FILE, NOTIF_FILE, SETTINGS_FILE,
  SEGMENTS, back, fetchTutorialCategories, fetchTutorialLevels,
};

for (const domaine of ['utilisateurs', 'catalogue', 'contenu', 'finance', 'exploitation']) {
  require('./routes/' + domaine)(app, contexteRoutes);
}

// Le 404 doit rester déclaré APRÈS toutes les routes, sinon il les intercepte.

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

app.listen(PORT, () => {
  console.log(`\n🖥️  PronoWin Admin — http://localhost:${PORT}/admin`);
  console.log(`📡 dashboard | users | pronostics | transactions | historique | abonnements | tutoriels | sub-admins | audit | notifications\n`);
});
