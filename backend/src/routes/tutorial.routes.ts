import { Router } from 'express';
import { authMiddleware } from '../middleware/auth.middleware';
import { getAll, getOne, markProgress, getProgress } from '../controllers/tutorial.controller';

const r = Router();
r.use(authMiddleware);

r.get('/progress',      getProgress);          // GET  /tutorials/progress  — AVANT /:id
r.get('/',              getAll);               // GET  /tutorials
r.get('/:id',           getOne);              // GET  /tutorials/:id
r.post('/:id/progress', markProgress);        // POST /tutorials/:id/progress

export default r;
