import { Response } from 'express';
import { AdminRequest } from '../middleware/admin.middleware';
import { PaymentHistoryService } from '../services/payment_history.service';

const svc = new PaymentHistoryService();

export const getHistory = async (req: AdminRequest, res: Response) => {
  try {
    res.json(await svc.getHistory({
      page:     parseInt(req.query.page     as string ?? '1'),
      perPage:  parseInt(req.query.per_page as string ?? '20'),
      search:   req.query.search   as string,
      type:     req.query.type     as string,
      status:   req.query.status   as string,
      method:   req.query.method   as string,
      dateFrom: req.query.date_from as string,
      dateTo:   req.query.date_to   as string,
      sortDir:  (req.query.sort_dir as 'asc' | 'desc') ?? 'desc',
    }));
  } catch (e: any) { res.status(500).json({ message: e.message }); }
};

export const getStats = async (_req: AdminRequest, res: Response) => {
  try { res.json(await svc.getStats()); }
  catch (e: any) { res.status(500).json({ message: e.message }); }
};

export const updateTransaction = async (req: AdminRequest, res: Response) => {
  try {
    res.json(await svc.updateTransaction(req.params.id, {
      status:    req.body.status,
      adminNote: req.body.admin_note,
    }));
  } catch (e: any) { res.status(400).json({ message: e.message }); }
};

export const exportCsv = async (req: AdminRequest, res: Response) => {
  try {
    const csv = await svc.exportCsv({
      type:     req.query.type     as string,
      status:   req.query.status   as string,
      dateFrom: req.query.date_from as string,
      dateTo:   req.query.date_to   as string,
    });
    const date = new Date().toISOString().split('T')[0];
    res.setHeader('Content-Type', 'text/csv; charset=utf-8');
    res.setHeader('Content-Disposition', `attachment; filename="transactions_${date}.csv"`);
    res.send('\uFEFF' + csv);
  } catch (e: any) { res.status(500).json({ message: e.message }); }
};
