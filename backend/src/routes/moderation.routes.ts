import { Router } from 'express';

import { authMiddleware } from '../middleware/auth.middleware';
import { valider } from '../middleware/valider';
import { blocageMembre, signalementCommentaire } from '../schemas/entrees';
import * as C from '../controllers/moderation.controller';

/**
 * Ce que chaque membre peut faire contre un contenu ou un membre abusif :
 * signaler un commentaire, bloquer son auteur (règle 1.2 de l'App Store).
 */
const r = Router();
r.use(authMiddleware);

r.post  ('/signalements',      valider({ body: signalementCommentaire }), C.signaler);
r.get   ('/blocages',          C.listeBloques);
r.post  ('/blocages',          valider({ body: blocageMembre }), C.bloquer);
r.delete('/blocages/:userId',  C.debloquer);

export default r;
