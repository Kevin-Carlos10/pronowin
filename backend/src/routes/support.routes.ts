import { Router } from 'express';
import rateLimit from 'express-rate-limit';

import { AuthRequest, optionalAuthMiddleware } from '../middleware/auth.middleware';
import { valider } from '../middleware/valider';
import { avisUtilisateur } from '../schemas/entrees';
import { envoyerAvis } from '../services/avis_utilisateurs.service';
import { repondreErreur } from '../utils/erreurs';

/**
 * « Donne-nous ton avis » (8 novembre 2026) : ouvert aux invités, qui
 * laissent alors une adresse où répondre. Le service limite à cinq avis par
 * heure ; ce limiteur arrête les rafales avant même la base.
 */
const r = Router();

const rafales = rateLimit({
  windowMs: 60_000, max: 5,
  message: { message: 'Trop d’envois. Réessaie dans une minute.' },
});

r.post('/avis', rafales, optionalAuthMiddleware, valider({ body: avisUtilisateur }), async (req: AuthRequest, res) => {
  try {
    const avis = await envoyerAvis({
      userId:      req.userId ?? null,
      email:       req.body.email ?? null,
      message:     req.body.message,
      imageBase64: req.body.image_base64 ?? null,
      plateforme:  req.body.plateforme ?? null,
      versionApp:  req.body.version_app ?? null,
    });
    res.status(201).json({ id: avis.id });
  } catch (e) { repondreErreur(res, e); }
});

export default r;
