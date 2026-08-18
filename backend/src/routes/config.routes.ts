import { Router } from 'express';
import { lireConfig } from '../services/app_config.service';

const router = Router();

/**
 * GET /api/v1/config — configuration publique de l'app.
 *
 * Deux canaux de mise à jour cohabitent, et ils ne peuvent pas partager les
 * mêmes numéros de version :
 *
 *  - **store** (App Store / Google Play) : le binaire est mis à jour par le
 *    store. Le bouton renvoie vers la fiche du store.
 *  - **direct** (APK téléchargé sur le site) : rien ne se met à jour tout
 *    seul. Les seuils et l'URL du fichier viennent d'ici, et le bouton
 *    déclenche le téléchargement.
 *
 * Les deux jeux de versions divergent forcément : une release Play attend la
 * validation de Google pendant que l'APK est déjà en ligne. Les mélanger
 * enverrait la moitié des utilisateurs vers une mise à jour inexistante.
 *
 * Les valeurs sont modifiables depuis le panneau d'administration ; le `.env`
 * sert de repli. `APK_URL` vide = aucune invitation à mettre à jour n'est
 * affichée sur le canal direct, plutôt qu'un bouton menant à un lien mort.
 */
router.get('/', async (_req, res) => {
  const { valeurs } = await lireConfig();
  res.json({
    // ── Canal store ──────────────────────────────────────────────────────
    minVersion:    valeurs.APP_MIN_VERSION,
    latestVersion: valeurs.APP_LATEST_VERSION,
    forceUpdate:   valeurs.APP_FORCE_UPDATE === 'true',

    // ── Canal direct (APK hors store) ────────────────────────────────────
    apkMinVersion:    valeurs.APK_MIN_VERSION,
    apkLatestVersion: valeurs.APK_LATEST_VERSION,
    apkForceUpdate:   valeurs.APK_FORCE_UPDATE === 'true',
    apkUrl:           valeurs.APK_URL || null,

    // ── Commun ───────────────────────────────────────────────────────────
    updateMessage: valeurs.APP_UPDATE_MESSAGE,
    maintenance:   process.env.APP_MAINTENANCE === 'true',
  });
});

export default router;
