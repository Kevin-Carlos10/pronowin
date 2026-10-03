/* Les lignes restent en place : filtres, focus et cases cochées sont conservés. */
(function () {
  const rows = new Map(Array.from(document.querySelectorAll('[data-match-id]')).map(row => [row.dataset.matchId, row]));
  const status = document.getElementById('scores-status');
  if (!rows.size || !status) return;
  let timer, controller, stopped = false, lastCheck = '';
  function apply(match) {
    const row = rows.get(match.id);
    if (!row) return;
    const live = match.status === 'LIVE', finished = match.status === 'FINISHED';
    const score = row.querySelector('[data-match-score]');
    if (score) {
      const hasScore = match.homeScore != null && match.awayScore != null;
      score.textContent = hasScore ? match.homeScore + '–' + match.awayScore : 'vs';
      score.className = hasScore ? 'score' : 'vs';
      score.style.color = live ? 'var(--on-danger)' : 'var(--text)';
    }
    row.classList.toggle('is-live', live);
    row.querySelector('.when')?.classList.toggle('live', live);
    if (live || finished) row.querySelector('.when')?.classList.remove('soon');
    const phase = row.querySelector('.match-phase');
    const labels = {SCHEDULED:'À venir', FINISHED:'Terminé', POSTPONED:'Reporté', CANCELLED:'Annulé', SUSPENDED:'Suspendu'};
    if (phase) phase.textContent = live ? (Number.isInteger(match.elapsedMinutes) ? match.elapsedMinutes + '′ · En direct' : 'En direct') : (labels[match.status] || match.status);
    const result = row.querySelector('[data-match-result]');
    if (result) result.textContent = finished ? ({WIN:' · Gagné', LOSS:' · Perdu', PUSH:' · Remboursé'}[match.pronostic?.result] || '') : '';
  }
  async function refresh() {
    clearTimeout(timer);
    if (document.hidden || stopped || controller) return;
    controller = new AbortController();
    const timeout = setTimeout(() => controller?.abort(), 12000);
    try {
      const response = await fetch('/admin/api/pronostics/scores', {
        method:'POST', headers:{'Content-Type':'application/json'}, credentials:'same-origin',
        body:JSON.stringify({ids:Array.from(rows.keys())}), signal:controller.signal,
      });
      if (response.status === 401 || response.redirected) {
        stopped = true; status.textContent = 'Session expirée : reconnectez-vous pour actualiser les scores.'; return;
      }
      if (!response.ok) throw new Error('Scores indisponibles');
      const data = await response.json();
      if (!Array.isArray(data.matches)) throw new Error('Réponse invalide');
      if (document.hidden || stopped) return;
      data.matches.forEach(apply);
      lastCheck = new Date().toLocaleTimeString('fr-FR');
      status.textContent = 'Scores actualisés automatiquement · Dernière vérification : ' + lastCheck;
    } catch {
      if (!document.hidden && !stopped) status.textContent = 'Connexion interrompue · Nouvelle tentative automatique' + (lastCheck ? ' · Dernière vérification : ' + lastCheck : '');
    } finally {
      clearTimeout(timeout); controller = null;
      if (!stopped && !document.hidden) timer = setTimeout(refresh, 15000);
    }
  }
  document.addEventListener('visibilitychange', () => {
    clearTimeout(timer);
    if (document.hidden) controller?.abort(); else refresh();
  });
  window.addEventListener('pagehide', () => { stopped = true; clearTimeout(timer); controller?.abort(); });
  window.addEventListener('pageshow', e => { if (e.persisted) { stopped = false; refresh(); } });
  refresh();
})();
