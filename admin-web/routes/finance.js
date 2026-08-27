/**
 * Routes « finance » — extraites de server.js.
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
  } = ctx;

  app.get('/admin/bankroll/export', requireAuth, requirePerm('bankroll'), async (req, res) => {
    const a = api(req.cookies.admin_token);
    const search  = (req.query.search  ?? '').trim();
    const sortBy  = req.query.sort_by  ?? 'currentBalance';
    const sortDir = req.query.sort_dir ?? 'desc';
    try {
      // per_page élevé mais borné : un export ne doit pas pouvoir vider la base
      // en une requête ni bloquer le process (leçon de l'export utilisateurs).
      const r = await a.get('/bankroll/admin/list', { params: {
        page: 1, per_page: 1000, ...(search ? { search } : {}), sort_by: sortBy, sort_dir: sortDir,
      }});
      const rows = (r.data.data ?? []).map(b => [
        b.pseudo, b.phone_number ?? '', b.email ?? '',
        Math.round(b.total_budget), Math.round(b.current_balance), b.currency,
        b.total_bets, b.pending_bets, b.wins, b.losses,
        b.win_rate ?? '', Math.round(b.total_profit), b.roi ?? '',
        b.created_at ? new Date(b.created_at).toISOString().slice(0, 10) : '',
      ]);
      logAction(req, 'bankroll_exported', `${rows.length} ligne(s)`, { count: rows.length, search });
      sendCSV(res, `bankrolls_${new Date().toISOString().slice(0,10)}.csv`,
        ['Pseudo','Téléphone','Email','Budget','Solde','Devise','Paris','En attente',
         'Gagnés','Perdus','Taux réussite %','Profit','ROI %','Créé le'], rows);
    } catch (e) {
      res.redirect('/admin/bankroll?error=' + encodeURIComponent('Export impossible : ' + (e.response?.data?.message ?? e.message)));
    }
  });

  app.get('/admin/bankroll', requireAuth, requirePerm('bankroll'), async (req, res) => {
    const a = api(req.cookies.admin_token);
    const search  = (req.query.search  ?? '').trim();
    const sortBy  = req.query.sort_by  ?? 'currentBalance';
    const sortDir = req.query.sort_dir ?? 'desc';
    const page    = Math.max(1, parseInt(req.query.page ?? '1') || 1);
    try {
      // Les agrégats ne doivent pas faire échouer la page : la liste reste
      // affichable même si le calcul global tombe.
      const [r, st] = await Promise.all([
        a.get('/bankroll/admin/list', { params: {
          page, per_page: 20,
          ...(search ? { search } : {}),
          sort_by: sortBy, sort_dir: sortDir,
        }}),
        a.get('/bankroll/admin/stats').catch(() => ({ data: null })),
      ]);
      res.render('bankroll', {
        adminName: req.cookies.admin_name ?? 'Admin',
        // `error` peut venir d'un export en échec qui redirige ici.
        ...r.data, stats: st.data, search, sortBy, sortDir, error: req.query.error ?? null,
      });
    } catch (e) {
      if (e.response?.status === 401) return res.redirect('/admin/login?expired=1');
      res.render('bankroll', {
        adminName: req.cookies.admin_name ?? 'Admin',
        data: [], stats: null, total: 0, page: 1, per_page: 20, total_pages: 0,
        search, sortBy, sortDir, error: e.response?.data?.message ?? e.friendlyMessage ?? e.message,
      });
    }
  });

  app.get('/admin/bankroll/:userId', requireAuth, requirePerm('bankroll'), async (req, res) => {
    const a = api(req.cookies.admin_token);
    try {
      const r = await a.get('/bankroll/admin/' + req.params.userId);
      res.render('bankroll_detail', { adminName: req.cookies.admin_name ?? 'Admin', ...r.data, error: null });
    } catch (e) {
      if (e.response?.status === 401) return res.redirect('/admin/login?expired=1');
      if (e.response?.status === 404) return res.status(404).render('error', { message: 'Utilisateur introuvable.' });
      res.redirect('/admin/bankroll?error=' + encodeURIComponent(e.response?.data?.message ?? e.friendlyMessage ?? e.message));
    }
  });

  // ─── LIGUES (liste blanche du flux public) ────────────────────────────────────

  app.get('/admin/transactions', requireAuth, requirePerm('transactions'), async (req, res) => {
    const a = api(req.cookies.admin_token);
    // Le filtre `type` a disparu avec les dépôts : toutes les lignes sont
    // des versements de gains de parrainage.
    const { search = '', method = '', page = '1' } = req.query;
    try {
      const [pendingRes, methodsRes] = await Promise.allSettled([
        a.get('/payments/admin/pending', { params: { search, method, page, per_page: 20 } }),
        a.get('/payments/admin/methods').catch(() => ({ data: [] })),
      ]);
      if (pendingRes.status === 'rejected' && pendingRes.reason?.response?.status === 401)
        return res.redirect('/admin/login?expired=1');

      const raw     = pendingRes.status === 'fulfilled' ? pendingRes.value.data : { data: [], total: 0 };
      const methods = methodsRes.status === 'fulfilled' ? methodsRes.value.data : [];

      // Stats calculées localement (pas d'endpoint de stats globales côté /payments)
      const items       = raw.data ?? [];
      const totalAmount = items.reduce((s, tx) => s + (tx.amount ?? 0), 0);

      res.render('transactions', {
        data: raw, search, method, methods,
        // Pourquoi la file est vide : sans ces chiffres, une page vide se lit
        // comme une page en panne. Voir `_contexteParrainage` cote API.
        contexte: raw.contexte ?? null,
        page: parseInt(page), totalPages: Math.max(1, Math.ceil((raw.total ?? 0) / 20)),
        localStats: { totalAmount, total: raw.total ?? 0 },
        success: req.query.success ?? null,
        error:   req.query.error   ?? null,
      });
    } catch (e) {
      if (e.response?.status === 401) return res.redirect('/admin/login?expired=1');
      res.render('transactions', {
        data: { data: [], total: 0 }, search, method, methods: [], page: 1, totalPages: 1,
        contexte: null,
        localStats: { totalAmount:0, total:0 },
        success: null, error: e.response?.data?.message ?? e.message,
      });
    }
  });

  app.post('/admin/transactions/:id', requireAuth, requirePerm('transactions', 'write'), async (req, res) => {
    const a = api(req.cookies.admin_token);
    try {
      await a.patch('/payments/admin/' + req.params.id, { status: req.body.status, admin_note: req.body.admin_note ?? null });
      const action = req.body.status === 'completed' ? 'transaction_approved' : 'transaction_rejected';
      logAction(req, action, `Versement #${req.params.id}`, { txId: req.params.id, status: req.body.status, note: req.body.admin_note });
      sseBroadcast('action', { type: action, adminName: req.cookies.admin_name ?? 'Admin', ts: Date.now() });
      res.redirect('/admin/transactions?success=1');
    } catch (e) { res.redirect('/admin/transactions?error=' + encodeURIComponent(e.response?.data?.message ?? 'Erreur')); }
  });

  // ─── MÉTHODES DE PAIEMENT ─────────────────────────────────────────────────────
  //
  // Le numéro affiché à l'abonné vivait en deux exemplaires : trois variables
  // MOBCASH_* côté serveur, et une constante compilée dans l'app mobile — qui ne
  // portaient déjà pas les mêmes valeurs. Cette page est la source unique.

  // ─── Code promo partenaire ────────────────────────────────────────────────
  //
  // Le code d'affiliation etait une variable d'environnement, donc modifiable
  // seulement par quelqu'un ayant un acces SSH au serveur. Trois replis ecrits
  // en dur — backend, mobile, admin — nommaient encore `PRONOWIN2025` alors que
  // le code en service etait `PRONOWIN2026`.
  //
  // Un code perime ne produit aucune erreur : l'utilisateur ouvre son compte
  // avec, nous ne sommes jamais credites, et il reclame son mois offert. La
  // page existe pour que changer ce code prenne dix secondes et se voie.

  app.get('/admin/code-promo', requireAuth, requireMain, async (req, res) => {
    let config = null, stats = null, erreur = null;
    try {
      const a = api(req.cookies.admin_token);
      const [c, s] = await Promise.all([
        a.get('/admin/app-config'),
        a.get('/admin/promo-stats?days=30'),
      ]);
      config = c.data;
      stats  = s.data;
    } catch (e) {
      if (e.response?.status === 401) return res.redirect('/admin/login?expired=1');
      erreur = e.response?.data?.message ?? e.message;
    }
    res.render('code_promo', {
      config, stats, erreur,
      success: req.query.success ?? null,
      error:   req.query.error   ?? null,
    });
  });

  app.post('/admin/code-promo', requireAuth, requireMain, async (req, res) => {
    try {
      // Seules ces quatre cles sont transmises. `ecrireConfig` ignore de toute
      // facon les autres, mais on ne compte pas sur la protection d'en face
      // pour decider ce que cette page a le droit d'ecrire.
      const corps = {
        PROMO_CODE:           sanitize(req.body.PROMO_CODE ?? '', 40),
        PROMO_CODE_1XBET:     sanitize(req.body.PROMO_CODE_1XBET ?? '', 40),
        PROMO_CODE_MELBET:    sanitize(req.body.PROMO_CODE_MELBET ?? '', 40),
        PROMO_CODE_BETWINNER: sanitize(req.body.PROMO_CODE_BETWINNER ?? '', 40),
      };
      await api(req.cookies.admin_token).put('/admin/app-config', corps);
      logAction(req, 'settings_changed', 'Code promo partenaire mis a jour',
        { general: corps.PROMO_CODE });
      res.redirect('/admin/code-promo?success=' + encodeURIComponent('Code promo enregistre.'));
    } catch (e) {
      res.redirect('/admin/code-promo?error=' + encodeURIComponent(e.response?.data?.message ?? e.message));
    }
  });

  app.get('/admin/paiements', requireAuth, requireMain, async (req, res) => {
    let methodes = null, erreur = null;
    try {
      const r = await api(req.cookies.admin_token).get('/admin/payment-methods');
      methodes = r.data;
    } catch (e) {
      if (e.response?.status === 401) return res.redirect('/admin/login?expired=1');
      erreur = e.response?.data?.message ?? e.message;
    }
    res.render('paiements', {
      methodes, erreur,
      success: req.query.success ?? null,
      error:   req.query.error   ?? null,
    });
  });

  app.post('/admin/paiements', requireAuth, requireMain, async (req, res) => {
    try {
      const r = await api(req.cookies.admin_token).post('/admin/payment-methods', {
        label:      sanitize(req.body.label ?? '', 40),
        phone:      (req.body.phone ?? '').trim(),
        sort_order: clampInt(req.body.sort_order, 0, 99, 0),
      });
      logAction(req, 'settings_changed', `Opérateur ajouté : ${r.data?.label ?? ''}`,
        { key: r.data?.key, phone: r.data?.phone });
      res.redirect('/admin/paiements?success=' + encodeURIComponent('Opérateur ajouté.'));
    } catch (e) {
      res.redirect('/admin/paiements?error=' + encodeURIComponent(e.response?.data?.message ?? e.message));
    }
  });

  app.post('/admin/paiements/:id', requireAuth, requireMain, async (req, res) => {
    try {
      const r = await api(req.cookies.admin_token).put('/admin/payment-methods/' + req.params.id, {
        label:      sanitize(req.body.label ?? '', 40),
        phone:      (req.body.phone ?? '').trim(),
        sort_order: clampInt(req.body.sort_order, 0, 99, 0),
      });
      logAction(req, 'settings_changed', `Opérateur modifié : ${r.data?.label ?? ''}`,
        { key: r.data?.key, phone: r.data?.phone });
      res.redirect('/admin/paiements?success=' + encodeURIComponent('Opérateur mis à jour.'));
    } catch (e) {
      res.redirect('/admin/paiements?error=' + encodeURIComponent(e.response?.data?.message ?? e.message));
    }
  });

  app.post('/admin/paiements/:id/toggle', requireAuth, requireMain, async (req, res) => {
    const a = api(req.cookies.admin_token);
    try {
      // L'état courant vient du serveur : se fier à ce que la page affichait
      // ouvrirait une fenêtre où deux admins inversent le même interrupteur.
      const liste  = (await a.get('/admin/payment-methods')).data ?? [];
      const cible  = liste.find(m => m.id === req.params.id);
      if (!cible) throw new Error('Opérateur introuvable.');
      await a.put('/admin/payment-methods/' + req.params.id, { is_active: !cible.isActive });
      logAction(req, 'settings_changed',
        `Opérateur ${cible.isActive ? 'masqué' : 'affiché'} : ${cible.label}`, { key: cible.key });
      res.redirect('/admin/paiements?success=' + encodeURIComponent(
        cible.isActive ? "Opérateur masqué dans l'application." : "Opérateur affiché dans l'application."));
    } catch (e) {
      res.redirect('/admin/paiements?error=' + encodeURIComponent(e.response?.data?.message ?? e.message));
    }
  });

  app.post('/admin/paiements/:id/supprimer', requireAuth, requireMain, async (req, res) => {
    try {
      const r = await api(req.cookies.admin_token).delete('/admin/payment-methods/' + req.params.id);
      logAction(req, 'settings_changed', 'Opérateur supprimé', { id: req.params.id, ...r.data });
      res.redirect('/admin/paiements?success=' + encodeURIComponent(r.data?.desactive
        ? `Opérateur conservé mais masqué : ${r.data.transactions} versement(s) y font référence.`
        : 'Opérateur supprimé.'));
    } catch (e) {
      res.redirect('/admin/paiements?error=' + encodeURIComponent(e.response?.data?.message ?? e.message));
    }
  });

  // ─── HISTORIQUE ───────────────────────────────────────────────────────────────

  app.get('/admin/historique', requireAuth, requirePerm('historique'), async (req, res) => {
    const a = api(req.cookies.admin_token);
    const { search='', status='', method='', date_from='', date_to='', page='1',
            amount_min='', amount_max='' } = req.query;
    try {
      const [histRes, statsRes, methodsRes] = await Promise.all([
        a.get('/admin/history', { params: { search, status, method, date_from, date_to, page, per_page: 20, amount_min, amount_max } }),
        a.get('/admin/history/stats'),
        a.get('/payments/admin/methods').catch(() => ({ data: [] })),
      ]);
      res.render('historique', {
        adminName: req.cookies.admin_name ?? 'Admin',
        data: histRes.data.data, stats: statsRes.data, total: histRes.data.total, methods: methodsRes.data,
        page: parseInt(page), perPage: 20, totalPages: histRes.data.total_pages,
        search, status, method, dateFrom: date_from, dateTo: date_to, amount_min, amount_max,
        sortBy: req.query.sort_by ?? '',
        success: req.query.success ?? null, error: req.query.error ?? null,
      });
    } catch (e) {
      if (e.response?.status === 401) return res.redirect('/admin/login?expired=1');
      res.render('historique', {
        adminName: req.cookies.admin_name ?? 'Admin',
        data: [], stats: { total_withdrawals:0, completed_withdrawals:0, rejected_withdrawals:0,
                           volume_withdrawals:0, pending_count:0, pending_volume:0,
                           today_withdrawals:0, monthly_volume:0 },
        total:0, page:1, perPage:20, totalPages:1, methods: [],
        search, status, method, dateFrom: date_from, dateTo: date_to, amount_min, amount_max, sortBy: '',
        success: null, error: e.response?.data?.message ?? e.message,
      });
    }
  });

  app.post('/admin/historique/:id', requireAuth, requirePerm('historique', 'write'), async (req, res) => {
    const a = api(req.cookies.admin_token);
    try {
      await a.patch('/admin/history/' + req.params.id, { status: req.body.status, admin_note: req.body.admin_note });
      logAction(req, 'history_updated', `Versement #${req.params.id}`, { txId: req.params.id, status: req.body.status });
      res.redirect('/admin/historique?success=' + encodeURIComponent('Versement mis à jour.'));
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
      const { search='', status='', method='', date_from='', date_to='',
              amount_min='', amount_max='' } = req.query;
      const r = await a.get('/admin/history', { params: {
        search, status, method, date_from, date_to, amount_min, amount_max,
        page: 1, per_page: 5000,
      }});
      const txs  = r.data.data ?? [];
      const date = new Date().toISOString().slice(0,10);
      const headers = ['ID','Utilisateur','Téléphone','Montant (FCFA)','Méthode','Statut','ID 1xBet','N° Envoyeur','Note admin','Date création','Date traitement'];
      const rows = txs.map(tx => [
        tx.id,
        tx.user?.pseudo ?? '',
        tx.user?.phoneNumber ?? '',
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

  // Statuts consultables. `pending` est la file de travail, les autres
  // constituent l'historique des décisions — invisible jusqu'ici : une preuve
  // traitée disparaissait de l'écran sans laisser de trace consultable.
  const STATUTS_PREUVES = ['pending', 'approved', 'rejected', 'all'];

  app.get('/admin/abonnements', requireAuth, requirePerm('abonnements'), async (req, res) => {
    const a = api(req.cookies.admin_token);
    const statut  = STATUTS_PREUVES.includes(req.query.statut) ? req.query.statut : 'pending';
    const recherche = (req.query.q ?? '').trim();
    try {
      // `per_page` explicite : sans lui l'API applique son défaut de 20, et la
      // recherche côté client ne filtrait donc que les 20 premières preuves. Un
      // client dont la preuve était en 34e position ressortait « introuvable »,
      // et l'admin en concluait qu'il n'avait pas payé.
      const r = await a.get('/subscriptions/admin/proofs', {
        params: { page: 1, per_page: 5000, status: statut, search: recherche },
      });
      res.render('abonnements', {
        adminName: req.cookies.admin_name ?? 'Admin', data: r.data,
        statut, recherche, contexte: r.data.contexte ?? null,
        success: req.query.success === '1', error: req.query.error ?? null,
      });
    } catch (e) {
      if (e.response?.status === 401) return res.redirect('/admin/login?expired=1');
      res.render('abonnements', {
        adminName: req.cookies.admin_name ?? 'Admin', data: { data:[],total:0 },
        statut, recherche, contexte: null,
        success: false, error: e.response?.data?.message ?? e.message,
      });
    }
  });

  app.get('/admin/abonnements/export', requireAuth, requirePerm('abonnements'), async (req, res) => {
    const a = api(req.cookies.admin_token);
    try {
      // L'export suit le filtre affiché : exporter systématiquement la file en
      // attente alors que l'écran montre l'historique produisait un fichier
      // sans rapport avec ce que l'administrateur avait sous les yeux.
      const statut = STATUTS_PREUVES.includes(req.query.statut) ? req.query.statut : 'pending';
      const r    = await a.get('/subscriptions/admin/proofs', {
        params: { page: 1, per_page: 5000, status: statut, search: (req.query.q ?? '').trim() },
      });
      const data = r.data.data ?? [];
      const date = new Date().toISOString().slice(0,10);
      const headers = ['ID Preuve','Utilisateur','Téléphone','Type','Statut','Montant (FCFA)','Date soumission','Date traitement','Note admin'];
      // `processedAt` n'existe pas sur le modèle : la colonne « Date traitement »
      // sortait vide sur toutes les lignes. Le champ s'appelle `reviewedAt`.
      const rows = data.map(p => [
        p.id,
        p.user?.pseudo ?? '',
        p.user?.phoneNumber ?? '',
        p.type === 'payment_screenshot' ? 'Paiement direct' : 'Code partenaire',
        p.status ?? '',
        p.amount ?? '',
        p.createdAt  ? new Date(p.createdAt).toLocaleString('fr-FR')  : '',
        p.reviewedAt ? new Date(p.reviewedAt).toLocaleString('fr-FR') : '',
        p.adminNote ?? '',
      ]);
      sendCSV(res, `abonnements_${statut}_${date}.csv`, headers, rows);
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
};
