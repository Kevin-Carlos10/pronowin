import { Router } from 'express';

import { adminMiddleware } from '../middleware/admin.middleware';
import { valider } from '../middleware/valider';
import { decisionModeration } from '../schemas/entrees';
import * as C from '../controllers/moderation.controller';

/** Les commentaires signalés, et la décision du panneau. */
const r = Router();
r.use(adminMiddleware);

r.get ('/commentaires',             C.commentairesSignales);
r.get ('/a-traiter',                C.aTraiter);
r.post('/commentaires/:commentId',  valider({ body: decisionModeration }), C.trancher);

export default r;
