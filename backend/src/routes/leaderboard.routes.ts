import { Router } from 'express';
import { optionalAuthMiddleware } from '../middleware/auth.middleware';
import { getLeaderboard } from '../controllers/leaderboard.controller';

const r = Router();
r.get('/', optionalAuthMiddleware, getLeaderboard);
export default r;
