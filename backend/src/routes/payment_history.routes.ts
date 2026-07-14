import { Router } from 'express';
import { adminMiddleware } from '../middleware/admin.middleware';
import * as C from '../controllers/payment_history.controller';

const r = Router();
r.use(adminMiddleware);

r.get('/',           C.getHistory);
r.get('/stats',      C.getStats);
r.get('/export/csv', C.exportCsv);
r.patch('/:id',      C.updateTransaction);

export default r;
