import { Router } from 'express';
import { authMiddleware } from '../middleware/auth.middleware';
import * as C from '../controllers/profile.controller';
import { getProfile, updateProfile, getStats } from '../controllers/profile.controller';

const r = Router();
r.use(authMiddleware);
r.get   ('/',      getProfile);    // GET  /profile
r.patch ('/',      updateProfile); // PATCH /profile
r.get   ('/stats', getStats);      // GET  /profile/stats
r.delete('/',      C.deleteAccount); // DELETE /profile  (droit à l'oubli RGPD)
export default r;
