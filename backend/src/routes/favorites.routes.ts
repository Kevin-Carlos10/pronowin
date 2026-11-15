import { Router } from 'express';
import { authMiddleware } from '../middleware/auth.middleware';
import * as C from '../controllers/favorites.controller';

const r = Router();

r.get   ('/',       authMiddleware, C.getFavorites);
// Avant `/:id` : « suivis » n'est pas un identifiant de match.
r.get   ('/suivis', authMiddleware, C.getSuivis);
r.put   ('/suivis', authMiddleware, C.putSuivis);
r.post  ('/:id',    authMiddleware, C.addFavorite);
r.delete('/:id',    authMiddleware, C.removeFavorite);
r.get   ('/:id/alertes', authMiddleware, C.getAlertes);
r.put   ('/:id/alertes', authMiddleware, C.putAlertes);

export default r;
