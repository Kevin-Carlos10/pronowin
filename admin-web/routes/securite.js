/**
 * Routes « sécurité » : la double authentification de chaque compte.
 *
 * Aucun second facteur n'existait sur le panneau : un mot de passe hameçonné
 * suffisait pour valider des paiements, bannir ou publier (constat A1 de
 * l'audit du 24 septembre 2026). Chaque compte — administrateur principal ou
 * sous-admin — active ici un code TOTP ; l'administrateur principal peut le
 * réinitialiser pour un sous-admin qui a perdu son téléphone, et le rendre
 * obligatoire pour tous dans les Paramètres.
 */
const QRCode = require('qrcode');

module.exports = (app, ctx) => {
  const {
    requireAuth, requireMain, logAction, loadSubs, loadSettings, sessions,
    deuxFacteurs, genererSecret, uriOtpauth,
  } = ctx;

  const retour = (res, cle, message) =>
    res.redirect('/admin/profile/2fa?' + cle + '=' + encodeURIComponent(message));

  app.get('/admin/profile/2fa', requireAuth, async (req, res) => {
    const session = req.admin.session;
    const cle = session.cle2fa;
    const active = !!cle && deuxFacteurs.estActive(cle);
    let secret = null, qr = null, uri = null;

    if (!active && cle) {
      // Le secret proposé reste le même tant que la page est rechargée : sinon
      // chaque rechargement invaliderait le QR code déjà scanné.
      secret = session.secret2faEnCours ?? genererSecret();
      if (!session.secret2faEnCours) sessions.modifier(session, { secret2faEnCours: secret });
      uri = uriOtpauth({ secret, compte: req.admin.nom ?? 'admin' });
      qr = await QRCode.toString(uri, { type: 'svg', margin: 1, errorCorrectionLevel: 'M' });
    }

    res.render('profile_2fa', {
      adminName: req.admin.nom ?? 'Admin',
      active, secret, qr, uri,
      restants: active ? deuxFacteurs.secoursRestants(cle) : 0,
      obligatoire: !!loadSettings().exiger2fa,
      doitActiver: !!session.doitActiver2fa,
      codesSecours: null,
      disponible: !!cle,
      success: req.query.success ?? null,
      error: req.query.error ?? null,
      secoursUtilise: req.query.secours === '1',
    });
  });

  app.post('/admin/profile/2fa/activer', requireAuth, (req, res) => {
    const session = req.admin.session;
    const cle = session.cle2fa;
    if (!cle || !session.secret2faEnCours) return retour(res, 'error', 'Rechargez la page et recommencez.');
    if (deuxFacteurs.estActive(cle)) return retour(res, 'error', 'La double authentification est déjà active.');

    const codesSecours = deuxFacteurs.activer(cle, session.secret2faEnCours, req.body.code);
    if (!codesSecours) {
      return retour(res, 'error', 'Code incorrect : vérifiez l\'heure du téléphone et saisissez le code affiché.');
    }
    sessions.modifier(session, { secret2faEnCours: null, doitActiver2fa: false });
    logAction(req, '2fa_active', req.admin.nom ?? '');
    // Les codes de secours ne s'affichent qu'une fois, ici.
    res.render('profile_2fa', {
      adminName: req.admin.nom ?? 'Admin',
      active: true, secret: null, qr: null, uri: null, restants: codesSecours.length,
      obligatoire: !!loadSettings().exiger2fa, doitActiver: false, disponible: true,
      codesSecours, success: 'Double authentification activée.', error: null, secoursUtilise: false,
    });
  });

  app.post('/admin/profile/2fa/desactiver', requireAuth, (req, res) => {
    const cle = req.admin.session.cle2fa;
    if (loadSettings().exiger2fa) {
      return retour(res, 'error', 'La double authentification est obligatoire : elle ne peut pas être désactivée.');
    }
    if (!cle || !deuxFacteurs.verifier(cle, req.body.code)) {
      return retour(res, 'error', 'Code incorrect : la double authentification reste active.');
    }
    deuxFacteurs.desactiver(cle);
    logAction(req, '2fa_desactive', req.admin.nom ?? '');
    retour(res, 'success', 'Double authentification désactivée.');
  });

  // Un sous-admin a perdu son téléphone et ses codes de secours.
  app.post('/admin/sub-admins/:id/2fa/reinitialiser', requireAuth, requireMain, (req, res) => {
    const sub = loadSubs().find((s) => s.id === req.params.id);
    if (!sub) return res.redirect('/admin/sub-admins?error=' + encodeURIComponent('Sous-admin introuvable.'));
    deuxFacteurs.desactiver('sub:' + sub.id);
    // Ses sessions se ferment : il se reconnectera et réactivera le second
    // facteur — obligatoirement, si le réglage l'exige.
    sessions.fermerSi((s) => s.role === 'sub' && s.subId === sub.id);
    logAction(req, '2fa_reinitialise', sub.name, { id: sub.id });
    res.redirect('/admin/sub-admins?success=' + encodeURIComponent(
      `Double authentification de « ${sub.name} » réinitialisée.`));
  });
};
