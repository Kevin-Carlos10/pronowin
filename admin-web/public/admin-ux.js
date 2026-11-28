/* Progressive enhancement for the admin's review and editing workflows. */
(function () {
  const workspace = document.getElementById('proof-workspace');
  if (workspace) {
    const cards = Array.from(workspace.querySelectorAll('.pf-card'));
    const choices = Array.from(workspace.querySelectorAll('.proof-select'));
    function select(index) {
      cards.forEach(card => card.toggleAttribute('data-current', card.dataset.proofIndex === index));
      choices.forEach(button => button.setAttribute('aria-pressed', String(button.dataset.proofIndex === index)));
    }
    window.filterProofQueue = function (type) {
      choices.forEach(button => { button.hidden = !!type && button.dataset.type !== type; });
      const current = choices.find(button => button.getAttribute('aria-pressed') === 'true' && !button.hidden);
      select((current || choices.find(button => !button.hidden))?.dataset.proofIndex);
    };
    workspace.querySelectorAll('.proof-select').forEach(button => button.addEventListener('click', () => select(button.dataset.proofIndex)));
    select(choices[0]?.dataset.proofIndex);
    workspace.setAttribute('data-enhanced', '');
  }

  document.querySelectorAll('.proof-review').forEach(form => {
    form.addEventListener('submit', event => {
      event.preventDefault();
      if (form.dataset.sending) return;
      const action = event.submitter?.value;
      if (!['approve', 'reject'].includes(action)) return;
      const error = form.querySelector('.proof-error');
      const note = form.elements.admin_note;
      const reason = form.querySelector('.proof-reason').value;
      const rejectNote = [reason && reason !== 'autre' ? reason : '', note.value.trim()].filter(Boolean).join(' ');
      error.hidden = true;
      function fail(message, field) { error.textContent = message; error.hidden = false; field.focus(); }
      if (action === 'reject' && !rejectNote) {
        fail('Choisissez un motif ou rédigez un message pour expliquer le rejet.', note); return;
      }
      if (action === 'approve' && form.dataset.type === 'xbet_account_screenshot' && !form.elements.xbet_id.value.trim()) {
        fail('Relevez l’identifiant du compte partenaire avant de valider.', form.elements.xbet_id); return;
      }
      if (action === 'approve' && !form.reportValidity()) return;
      const duration = form.elements.duration_days;
      const description = duration ? 'pendant ' + duration.value + ' jours' : 'pour la durée prévue par l’offre partenaire';
      askConfirm({
        icon: action === 'approve' ? 'check' : 'x',
        title: action === 'approve' ? 'Activer l’accès Premium' : 'Rejeter cette preuve',
        msg: action === 'approve'
          ? 'Activer Premium ' + description + ' pour ' + form.dataset.user + ' ? Confirmez après vérification de la preuve.'
          : 'Rejeter la demande de ' + form.dataset.user + ' ? Message envoyé : ' + rejectNote,
        btnLabel: action === 'approve' ? 'Confirmer l’activation' : 'Confirmer le rejet',
        btnClass: action === 'approve' ? 'btn-success' : 'btn-danger',
        onConfirm: () => {
          if (form.dataset.sending) return;
          if (action === 'reject') note.value = rejectNote;
          const field = document.createElement('input');
          field.type = 'hidden'; field.name = 'action'; field.value = action;
          form.appendChild(field);
          form.dataset.sending = 'true';
          form.querySelectorAll('button').forEach(button => { button.disabled = true; });
          HTMLFormElement.prototype.submit.call(form);
        },
      });
    });
  });

  // Warn about lost work without storing personal content on this device.
  const editors = Array.from(document.querySelectorAll('#pro-form, #af-form, #tut-form'));
  const dirty = new Set();
  editors.forEach(form => {
    const message = document.createElement('p');
    message.className = 'form-dirty'; message.setAttribute('role', 'status'); message.hidden = true;
    form.prepend(message);
    function mark() {
      dirty.add(form); message.hidden = false;
      message.textContent = 'Modifications non enregistrées';
    }
    form.addEventListener('input', mark);
    form.addEventListener('change', mark);
    form.addEventListener('click', event => {
      if (event.target.closest('[role="radio"], [role="checkbox"], [role="switch"], .market-value-chip')) mark();
    });
    form.addEventListener('keydown', event => {
      if (['Enter', ' ', 'ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown'].includes(event.key) && event.target.closest('[role="radio"], [role="checkbox"], [role="switch"]')) mark();
    });
    form.addEventListener('submit', event => {
      if (!event.defaultPrevented) dirty.delete(form);
    });
  });
  window.addEventListener('beforeunload', event => {
    if (!dirty.size) return;
    event.preventDefault(); event.returnValue = '';
  });
})();
