/**
 * Routes « contenu » — extraites de server.js.
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
    SA_FILE, BANS_FILE, NEWS_FILE, LOG_FILE, NOTIF_FILE, SETTINGS_FILE,
    SEGMENTS, back, fetchTutorialCategories, fetchTutorialLevels,
  } = ctx;

  app.get('/admin/tutoriels', requireAuth, requirePerm('tutoriels'), async (req, res) => {
    const a = api(req.cookies.admin_token);
    const { search='', category='', level='', page='1' } = req.query;
    try {
      const [listRes, statsRes, categories, levels] = await Promise.all([
        a.get('/admin/tutorials', { params: { search, category, level, page, per_page: 20 } }),
        a.get('/admin/tutorials/stats'),
        fetchTutorialCategories(a),
        fetchTutorialLevels(a),
      ]);
      res.render('tutoriels', {
        adminName: req.cookies.admin_name ?? 'Admin',
        data: listRes.data.data, stats: statsRes.data, total: listRes.data.total,
        page: parseInt(page), totalPages: listRes.data.total_pages,
        search, category, level, categories, levels,
        success: req.query.success ?? null, error: req.query.error ?? null,
      });
    } catch (e) {
      if (e.response?.status === 401) return res.redirect('/admin/login?expired=1');
      res.render('tutoriels', {
        adminName: req.cookies.admin_name ?? 'Admin',
        data: [], stats: { total:0,premium:0,free:0,beginner:0,intermediate:0,advanced:0 },
        total:0, page:1, totalPages:1, search, category, level, categories: [], levels: [],
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

  app.get('/admin/tutoriels/new',          requireAuth, requirePerm('tutoriels', 'write'), async (req, res) => {
    const a = api(req.cookies.admin_token);
    res.render('tutoriel_form', {
      adminName: req.cookies.admin_name ?? 'Admin', tutorial: null, error: null,
      categories: await fetchTutorialCategories(a), levels: await fetchTutorialLevels(a),
    });
  });

  app.post('/admin/tutoriels',             requireAuth, requirePerm('tutoriels', 'write'), async (req, res) => {
    const a = api(req.cookies.admin_token);
    try {
      if (req.body.duration_seconds) req.body.duration_seconds = parseInt(req.body.duration_seconds) * 60;
      await a.post('/admin/tutorials', req.body);
      logAction(req, 'tutorial_created', req.body.title ?? 'Sans titre', { title: req.body.title });
      res.redirect('/admin/tutoriels?success=' + encodeURIComponent('Tutoriel créé avec succès !'));
    } catch (e) {
      res.render('tutoriel_form', {
        adminName: req.cookies.admin_name ?? 'Admin', tutorial: null, error: e.response?.data?.message ?? 'Erreur.',
        categories: await fetchTutorialCategories(a), levels: await fetchTutorialLevels(a),
      });
    }
  });

  app.get('/admin/tutoriels/:id/edit',     requireAuth, requirePerm('tutoriels', 'write'), async (req, res) => {
    const a = api(req.cookies.admin_token);
    try {
      const [r, categories, levels] = await Promise.all([
        a.get('/admin/tutorials/' + req.params.id),
        fetchTutorialCategories(a),
        fetchTutorialLevels(a),
      ]);
      res.render('tutoriel_form', { adminName: req.cookies.admin_name ?? 'Admin', tutorial: r.data, error: null, categories, levels });
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
        const [r2, categories, levels] = await Promise.all([
          a.get('/admin/tutorials/' + req.params.id),
          fetchTutorialCategories(a),
          fetchTutorialLevels(a),
        ]);
        res.render('tutoriel_form', { adminName: req.cookies.admin_name ?? 'Admin', tutorial: r2.data, error: e.response?.data?.message ?? 'Erreur.', categories, levels });
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
      search, category, status, categories: getNewsCategories(),
      success: req.query.success ?? null,
      error:   req.query.error   ?? null,
    });
  });

  app.get('/admin/actualites/new', requireAuth, requirePerm('actualites', 'write'), (req, res) => {
    res.render('actualite_form', {
      adminName: req.cookies.admin_name ?? 'Admin',
      adminRole: req.cookies.admin_role ?? 'sub',
      adminUsername: req.cookies.admin_username ?? '',
      article: null, isEdit: false, categories: getNewsCategories(),
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
      article, isEdit: true, categories: getNewsCategories(),
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
    // `target_user` était saisi par le formulaire puis jeté ici : le mode
    // « utilisateur spécifique » n'a donc jamais pu fonctionner.
    const { title, body, segment = 'all', data_url = '', image_url = '', target_user = '' } = req.body;

    if (!title?.trim() || !body?.trim()) {
      return res.redirect('/admin/notifications?error=' + encodeURIComponent('Le titre et le message sont obligatoires.'));
    }
    if (title.length > 100) {
      return res.redirect('/admin/notifications?error=' + encodeURIComponent('Le titre ne doit pas dépasser 100 caractères.'));
    }
    if (body.length > 300) {
      return res.redirect('/admin/notifications?error=' + encodeURIComponent('Le message ne doit pas dépasser 300 caractères.'));
    }
    if (segment === 'user' && !target_user.trim()) {
      return res.redirect('/admin/notifications?error=' + encodeURIComponent(
        "Indiquez le pseudo, l'email ou le numéro du destinataire."));
    }

    const a = api(req.cookies.admin_token);
    try {
      const r = await a.post('/admin/notifications/send', {
        title: title.trim(),
        body:  body.trim(),
        segment,
        ...(segment === 'user' ? { target_user: target_user.trim() } : {}),
        ...(data_url  ? { data: { url: data_url } }  : {}),
        ...(image_url ? { image: image_url }          : {}),
      });

      const sent    = r.data.sent ?? r.data.count ?? 0;
      const segMeta = segment === 'user'
        ? { label: 'Utilisateur : ' + (r.data.target ?? target_user.trim()) }
        : (SEGMENTS.find(s => s.key === segment) ?? { label: segment });

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

      // Un « envoyée à 0 utilisateurs » annoncé comme un succès laisserait
      // croire que tout va bien alors que personne n'a rien reçu.
      const message = sent === 0
        ? "Aucun destinataire joignable : personne n'a reçu la notification."
        : segment === 'user'
          ? `Notification envoyée à ${r.data.target ?? target_user.trim()}.`
          : `Notification envoyée à ${sent.toLocaleString('fr-FR')} utilisateur${sent > 1 ? 's' : ''}.`;
      res.redirect('/admin/notifications?' + (sent === 0 ? 'error=' : 'success=') + encodeURIComponent(message));
    } catch (e) {
      res.redirect('/admin/notifications?error=' + encodeURIComponent(e.response?.data?.message ?? 'Erreur lors de l\'envoi.'));
    }
  });

  // ─── REDIRECTIONS ─────────────────────────────────────────────────────────────
};
