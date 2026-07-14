import { Router } from 'express';
import { adminMiddleware } from '../middleware/admin.middleware';
import * as C from '../controllers/stats.controller';

const r = Router();
r.use(adminMiddleware);

r.get('/dashboard',    C.getDashboard);     // GET /admin/stats/dashboard?days=30
r.get('/revenue',      C.getRevenueSeries); // GET /admin/stats/revenue?days=30
r.get('/users',        C.getUsersSeries);   // GET /admin/stats/users?days=30
r.get('/top-users',    C.getTopUsers);      // GET /admin/stats/top-users

export default r;
