/**
 * Routes « utilisateurs » — extraites de server.js.
 *
 * `server.js` faisait 2 586 lignes pour 89 routes. Le découpage suit les
 * domaines métier, pas les verbes HTTP : on cherche un écran, pas un GET.
 *
 * Ces modules reçoivent le contexte partagé (helpers, middlewares, client API)
 * plutôt que de le réimporter : il n'y a qu'une seule configuration, un seul
 * client Axios et un seul jeu de fichiers de données — les dupliquer aurait
 * créé autant d'occasions de les faire diverger.
 */
module.exports = (app, ctx) => {
  const {
    api, requireAuth, requireMain, requirePerm, logAction, sendCSV,
    loadSubs, saveSubs, empreinteSubs, saveSubsSi,
    loadSettings, saveSettings, empreinteSettings, saveSettingsSi,
    loadNews, saveNews, loadBans, saveBans, loadLogs, saveLogs,
    loadNotifHistory, saveNotifHistory, getNewsCategories,
    uid, hashPwd, checkPwd, getClientIP, ecrireJson,
    ERR_ECRITURE, ERR_CONFLIT, PERMISSIONS, DATA_DIR, LOG_MAX,
    STATS_ENDPOINTS, NEWS_DEFAULT_CATEGORIES,
    fs, path, slugify, sanitize, clampInt, sseBroadcast,
    banUser, unbanUser, getActiveBan, ACTION_LABELS,
    bansARestaurer, reconcilierBansExpires,
    SA_FILE, BANS_FILE, NEWS_FILE, LOG_FILE, NOTIF_FILE, SETTINGS_FILE,
  } = ctx;

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
        // sortDir manquait : la vue reconstruisait les liens de pagination sans
        // lui, donc un tri ascendant repassait en descendant page suivante.
        search, plan, status, sortBy: sort_by, sortDir: sort_dir, date_from, date_to, min_tx,
        activeBanIds: [...activeBanIds],
        success: req.query.success ?? null, error: req.query.error ?? null,
      });
    } catch (e) {
      if (e.response?.status === 401) return res.redirect('/admin/login?expired=1');
      res.render('users', {
        adminName: req.cookies.admin_name ?? 'Admin',
        data: [], stats: { total:0,premium:0,active:0,suspended:0,newToday:0,newWeek:0,newMonth:0,conversion_rate:0 },
        total:0, page:1, perPage:20, totalPages:1,
        search, plan, status, sortBy: sort_by, sortDir: sort_dir, date_from, date_to, min_tx,
        activeBanIds: [],
        success: null, error: e.response?.data?.message ?? e.message,
      });
    }
  });

  // ── Actions groupées sur les utilisateurs (AJAX) ──────────────────────────────
  app.patch('/admin/users/bulk/suspend', requireAuth, requirePerm('users', 'write'), async (req, res) => {
    const a = api(req.cookies.admin_token);
    try {
      const ids     = Array.isArray(req.body.user_ids) ? req.body.user_ids : [];
      const suspend = req.body.suspend === true || req.body.suspend === 'true';
      const r = await a.patch('/admin/users/bulk/suspend', { user_ids: ids, suspend, reason: req.body.reason });
      logAction(req, suspend ? 'user_bulk_suspended' : 'user_bulk_activated',
        `${ids.length} compte(s)`, { count: ids.length, userIds: ids });
      res.json({ ok: true, ...r.data });
    } catch (e) {
      res.status(e.response?.status ?? 500).json({ ok: false, message: e.response?.data?.message ?? e.message });
    }
  });

  app.post('/admin/users/bulk/notify', requireAuth, requirePerm('users', 'write'), async (req, res) => {
    const a = api(req.cookies.admin_token);
    try {
      const ids = Array.isArray(req.body.user_ids) ? req.body.user_ids : [];
      const r = await a.post('/admin/users/bulk/notify',
        { user_ids: ids, title: req.body.title, body: req.body.body });
      logAction(req, 'user_bulk_notified', `${ids.length} compte(s)`,
        { count: ids.length, title: req.body.title, sent: r.data?.sent });
      res.json({ ok: true, ...r.data });
    } catch (e) {
      res.status(e.response?.status ?? 500).json({ ok: false, message: e.response?.data?.message ?? e.message });
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

  // Cet endpoint listait les utilisateurs connectes a tout admin authentifie,
  // sans egard pour la permission « users » : un sous-admin limite aux
  // tutoriels y accedait. Le panneau protegeait les pages, pas le JSON qui les
  // alimente.
  app.get('/admin/api/users/online', requireAuth, requirePerm('users'), async (req, res) => {
    const a = api(req.cookies.admin_token);
    try {
      const r = await a.get('/admin/users/online');
      res.json(r.data);
    } catch (e) { res.status(500).json({ users: [], total: 0 }); }
  });

  // `:endpoint` était concaténé tel quel dans l'URL de l'API. Une requête vers
  // /admin/api/stats/%2e%2e%2fusers donnait `endpoint === '../users'`, soit
  // /admin/stats/../users → /admin/users : un sous-admin n'ayant que la
  // permission « statistiques » atteignait des données qu'il n'a pas le droit
  // de voir. Seuls les endpoints réellement exposés sont acceptés.

  app.get('/admin/bans', requireAuth, requirePerm('users'), async (req, res) => {
    const { filter = 'active', search = '', page = '1' } = req.query;

    // Un ban expiré ne rendait pas l'accès au compte : la minuterie ne touche
    // que le fichier local, faute de jeton. On rattrape ici, avec celui de
    // l'administrateur qui consulte la page.
    const restauration = await reconcilierBansExpires(req.cookies.admin_token)
      .catch(() => ({ restaures: [], echecs: bansARestaurer().length }));

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
      restauration,
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
      await a.patch('/admin/users/' + req.params.id + '/suspend', { suspend: true, reason });
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
      await a.patch('/admin/users/' + req.params.id + '/suspend', { suspend: false });
    } catch {}
    logAction(req, 'user_unbanned', `User #${req.params.id} (${pseudo})`, { reason: unban_reason });
    sseBroadcast('ban_update', { type: 'unbanned', userId: req.params.id, pseudo, ts: Date.now() });
    const redir = req.body.redirect_to ?? `/admin/users/${req.params.id}`;
    res.redirect(redir + (redir.includes('?') ? '&' : '?') + 'success=' + encodeURIComponent(`Utilisateur « ${pseudo} » débanni.`));
  });

  // Helper redirect avec erreur

  // ─── PARAMÈTRES GÉNÉRAUX ──────────────────────────────────────────────────────
};
