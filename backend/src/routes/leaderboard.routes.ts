import { Router } from 'express';
import { authMiddleware } from '../middleware/auth.middleware';
import { getLeaderboard } from '../controllers/leaderboard.controller';

const r = Router();
r.get('/', authMiddleware, getLeaderboard);
export default r;
