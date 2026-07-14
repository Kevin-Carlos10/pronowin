import { Router } from 'express';
import { authMiddleware } from '../middleware/auth.middleware';
import * as C from '../controllers/favorites.controller';

const r = Router();

r.get   ('/',       authMiddleware, C.getFavorites);
r.post  ('/:id',    authMiddleware, C.addFavorite);
r.delete('/:id',    authMiddleware, C.removeFavorite);

export default r;
