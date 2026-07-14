import { Router } from 'express';

const router = Router();

/**
 * GET /api/v1/config
 * Retourne la configuration publique de l'app (version, feature flags…).
 * Utilisé par le version checker Flutter au démarrage.
 */
router.get('/', (_req, res) => {
  res.json({
    minVersion:    process.env.APP_MIN_VERSION    ?? '1.0.0',
    latestVersion: process.env.APP_LATEST_VERSION ?? '1.0.0',
    forceUpdate:   process.env.APP_FORCE_UPDATE   === 'true',
    updateMessage: process.env.APP_UPDATE_MESSAGE
      ?? 'Une nouvelle version de PronoWin est disponible avec des améliorations et corrections.',
    maintenance:   process.env.APP_MAINTENANCE    === 'true',
  });
});

export default router;
