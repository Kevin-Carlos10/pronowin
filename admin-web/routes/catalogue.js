/**
 * Routes « catalogue » — extraites de server.js.
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

  app.get('/admin/pronostics', requireAuth, requirePerm('pronostics'), async (req, res) => {
    const a = api(req.cookies.admin_token);
    const competition   = req.query.competition ?? '';
    const statusFilter  = req.query.status ?? '';
    const q             = (req.query.q ?? '').trim();
    const date          = req.query.date ?? '';
    const mine          = req.query.mine === '1';
    const live          = req.query.live === '1';
    try {
      const [r, leaguesRes] = await Promise.all([
        a.get('/pronostics/admin/upcoming', { params: {
          ...(competition ? { competition } : {}),
          // Plafond d'affichage : « Tout » ouvre sur plusieurs milliers de
          // rencontres. L'export CSV, lui, n'envoie pas de limite.
          limit: 400,
          ...(q            ? { search: q }   : {}),
          ...(live         ? { live: '1' }   : mine ? { mine: '1' } : date ? { date } : {}),
        }}),
        // Raccourcis de ligue dans le filtre = les compétitions activées dans
        // /admin/leagues (liste blanche du flux public), plutôt qu'une liste
        // figée dans le template — reste à jour automatiquement.
        a.get('/pronostics/admin/leagues').catch(() => ({ data: [] })),
      ]);
      const visibleLeagues = (leaguesRes.data ?? []).filter(l => l.isVisible);
      // Total avant troncature — l'en-tête existe pour que la page annonce
      // « 400 sur 3 197 » au lieu de laisser croire qu'il n'y a que 400 matchs.
      const totalMatchs = parseInt(r.headers?.['x-total-count'] ?? '', 10);
      res.render('pronostics', { adminName: req.cookies.admin_name ?? 'Admin', matches: r.data ?? [], visibleLeagues, competition, statusFilter, q, date, mine, live,
        totalMatchs: Number.isFinite(totalMatchs) ? totalMatchs : null,
        success: req.query.success === '1', error: null,
        flash: req.query.ok ? {
          ok:    req.query.ok === 'publie' ? 'publie' : 'brouillon',
          match: sanitize(req.query.match ?? '', 80),
          tip:   sanitize(req.query.tip   ?? '', 60),
        } : null });
    } catch (e) {
      if (e.response?.status === 401) return res.redirect('/admin/login?expired=1');
      res.render('pronostics', { adminName: req.cookies.admin_name ?? 'Admin', matches: [], visibleLeagues: [], competition, statusFilter, q, date, mine, live, totalMatchs: null, success: false, flash: null, error: e.response?.data?.message ?? e.message });
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

  // Avis du modèle API-Football pour ce match — aide à la décision affichée à
  // côté des cotes 1xBet dans le formulaire.

  app.get('/admin/pronostics/edit/:matchId/prediction', requireAuth, requirePerm('pronostics'), async (req, res) => {
    const a = api(req.cookies.admin_token);
    try {
      const r = await a.get('/pronostics/admin/match/' + req.params.matchId + '/prediction');
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
      // Le formulaire renvoie les noms d'équipe en champs cachés : le journal
      // affichait « Match #09fa3d5a-a0c7-4011-a5f1… », un identifiant que
      // personne ne peut relier à un match en le lisant.
      const libelle = req.body.home_team && req.body.away_team
        ? `${req.body.home_team} – ${req.body.away_team}`
        : `Match #${req.params.matchId}`;
      const publie = req.body.publish === 'true';
      logAction(req, 'pronostic_published', libelle, { matchId: req.params.matchId, tip: req.body.tip, published: publie });

      // « success=1 » ne disait rien : ni quel match, ni quel pronostic, ni même
      // si c'était une publication ou un brouillon — les deux boutons du
      // formulaire redirigeaient ici, et la page annonçait « publié » dans les
      // deux cas. On transporte de quoi confirmer ce qui vient d'être fait.
      const params = new URLSearchParams({
        ok:    publie ? 'publie' : 'brouillon',
        match: libelle.slice(0, 80),
      });
      if (req.body.tip) params.set('tip', String(req.body.tip).slice(0, 60));
      res.redirect('/admin/pronostics?' + params.toString());
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

  /**
   * Désigner le pronostic gratuit du jour.
   *
   * La capacité existait de bout en bout — colonne `isDailyFree`, endpoint
   * `set-daily`, route publique `/pronostics/daily` consommée par l'app — mais
   * aucun écran ne l'exposait. Résultat mesuré : 0 pronostic marqué sur 43, et
   * l'application retombait en permanence sur son repli, « le premier
   * pronostic gratuit du jour par ordre d'heure ». La vitrine gratuite, celle
   * qui décide si un visiteur s'abonne, était donc choisie par un tri.
   *
   * L'API bascule le drapeau et retire celui des autres : un seul à la fois.
   */
  app.post('/admin/pronostics/daily/:pronosticId', requireAuth, requirePerm('pronostics', 'write'), async (req, res) => {
    const a = api(req.cookies.admin_token);
    const retour = req.body.retour ?? '/admin/pronostics';
    try {
      await a.patch('/pronostics/admin/pronostic/' + req.params.pronosticId + '/set-daily');
      logAction(req, 'pronostic_daily_set', `Pronostic #${req.params.pronosticId}`, { pronosticId: req.params.pronosticId });
      sseBroadcast('action', { type: 'pronostic_daily_set', adminName: req.cookies.admin_name ?? 'Admin', ts: Date.now() });
      res.redirect(retour + (retour.includes('?') ? '&' : '?') + 'success='
        + encodeURIComponent('Pronostic gratuit du jour mis à jour — il est désormais visible par tous.'));
    } catch (e) {
      res.redirect(retour + (retour.includes('?') ? '&' : '?') + 'error='
        + encodeURIComponent(e.response?.data?.message ?? e.message));
    }
  });

  /**
   * Relancer la synchronisation des scores.
   *
   * `POST /pronostics/admin/sync-scores` existait sans aucun bouton. Or le
   * service porte deja un « filet de securite anti-blocage » pour les matchs
   * coinces en LIVE : le probleme est connu, mais l'administrateur n'avait
   * aucun recours depuis l'interface — il fallait attendre le cron.
   */
  app.post('/admin/pronostics/sync-scores', requireAuth, requirePerm('pronostics', 'write'), async (req, res) => {
    const a = api(req.cookies.admin_token);
    const retour = req.body.retour ?? '/admin/pronostics';
    try {
      const r = await a.post('/pronostics/admin/sync-scores');
      const n = r.data?.updated ?? r.data?.count ?? null;
      logAction(req, 'scores_synced', n !== null ? `${n} match(s)` : 'manuel', { updated: n });
      const msg = n !== null
        ? `Synchronisation terminée — ${n} match${n !== 1 ? 's' : ''} mis à jour.`
        : 'Synchronisation des scores lancée.';
      res.redirect(retour + (retour.includes('?') ? '&' : '?') + 'success=' + encodeURIComponent(msg));
    } catch (e) {
      res.redirect(retour + (retour.includes('?') ? '&' : '?') + 'error='
        + encodeURIComponent('Synchronisation impossible : ' + (e.response?.data?.message ?? e.friendlyMessage ?? e.message)));
    }
  });

  // Route AJAX pour forcer le résultat depuis la liste des pronostics

  app.post('/admin/pronostics/force-result/:pronosticId', requireAuth, requirePerm('pronostics', 'write'), async (req, res) => {
    const a = api(req.cookies.admin_token);
    try {
      const result = req.body.result === 'null' ? null : req.body.result;
      if (result !== 'WIN' && result !== 'LOSS' && result !== 'PUSH' && result !== null) {
        return res.status(400).json({ ok: false, message: 'result doit être WIN, LOSS, PUSH ou null.' });
      }
      await a.patch('/pronostics/admin/pronostic/' + req.params.pronosticId + '/result', { result });
      logAction(req, 'pronostic_result_force', `Pronostic #${req.params.pronosticId}`, { result });
      res.json({ ok: true });
    } catch (e) {
      res.status(e.response?.status ?? 500).json({ ok: false, message: e.response?.data?.message ?? e.message });
    }
  });

  // ─── BANKROLL (suivi des budgets/paris utilisateurs) ──────────────────────────
  // Export CSV des bankrolls — les autres listes du panel en avaient un, pas
  // celle-ci. On repart des mêmes filtres que l'écran affiché.

  app.get('/admin/leagues', requireAuth, requirePerm('pronostics'), async (req, res) => {
    const a = api(req.cookies.admin_token);
    try {
      const r = await a.get('/pronostics/admin/leagues');
      res.render('leagues', { adminName: req.cookies.admin_name ?? 'Admin', leagues: r.data ?? [], error: null });
    } catch (e) {
      if (e.response?.status === 401) return res.redirect('/admin/login?expired=1');
      res.render('leagues', { adminName: req.cookies.admin_name ?? 'Admin', leagues: [], error: e.response?.data?.message ?? e.friendlyMessage ?? e.message });
    }
  });

  // Route AJAX — bascule la visibilité d'une ligue dans le flux public

  app.post('/admin/leagues/:code/toggle', requireAuth, requirePerm('pronostics', 'write'), async (req, res) => {
    const a = api(req.cookies.admin_token);
    try {
      const league  = req.body.league;
      const visible = req.body.visible === true || req.body.visible === 'true';
      await a.post('/pronostics/admin/leagues/' + encodeURIComponent(req.params.code), { league, visible });
      logAction(req, 'league_visibility_toggle', `${league} (${req.params.code})`, { visible });
      res.json({ ok: true });
    } catch (e) {
      res.status(e.response?.status ?? 500).json({ ok: false, message: e.response?.data?.message ?? e.message });
    }
  });

  // Route AJAX — bascule un lot de compétitions en un seul appel

  app.post('/admin/leagues/bulk', requireAuth, requirePerm('pronostics', 'write'), async (req, res) => {
    const a = api(req.cookies.admin_token);
    try {
      const leagues = Array.isArray(req.body.leagues) ? req.body.leagues : [];
      const visible = req.body.visible === true || req.body.visible === 'true';
      const r = await a.post('/pronostics/admin/leagues-bulk', { leagues, visible });
      logAction(req, 'league_visibility_bulk',
        `${leagues.length} compétition(s) → ${visible ? 'visibles' : 'masquées'}`,
        { count: leagues.length, visible, codes: leagues.map(l => l.leagueCode) });
      res.json({ ok: true, ...r.data });
    } catch (e) {
      res.status(e.response?.status ?? 500).json({ ok: false, message: e.response?.data?.message ?? e.message });
    }
  });

  // ─── TRANSACTIONS ─────────────────────────────────────────────────────────────
};
