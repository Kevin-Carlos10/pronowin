import { Router } from 'express';
import { authMiddleware, optionalAuthMiddleware } from '../middleware/auth.middleware';
import { getAll, getOne, markProgress, getProgress } from '../controllers/tutorial.controller';

const r = Router();

// ── Progression personnelle — connexion requise (AVANT /:id) ───────────────────
r.get('/progress',      authMiddleware, getProgress);
r.post('/:id/progress', authMiddleware, markProgress);

// ── Navigation ouverte aux invités ─────────────────────────────────────────────
r.get('/',               optionalAuthMiddleware, getAll);  // GET  /tutorials
r.get('/:id',             optionalAuthMiddleware, getOne); // GET  /tutorials/:id

export default r;
