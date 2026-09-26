import { Response } from 'express';
import { AdminRequest } from '../middleware/admin.middleware';
import { FiltresHistorique, PaymentHistoryService } from '../services/payment_history.service';
import { lirePagination } from '../utils/pagination';
import { repondreErreur } from '../utils/erreurs';

const svc = new PaymentHistoryService();

/** Les filtres de l'historique, lus de la même façon pour l'écran et l'export. */
function filtresDe(req: AdminRequest): FiltresHistorique {
  const texte  = (v: unknown) => (typeof v === 'string' && v.trim() ? v.trim() : undefined);
  const nombre = (v: unknown) => {
    const n = parseFloat(String(v ?? ''));
    return Number.isFinite(n) ? n : undefined;
  };
  return {
    search:    texte(req.query.search),
    status:    texte(req.query.status),
    method:    texte(req.query.method),
    dateFrom:  texte(req.query.date_from),
    dateTo:    texte(req.query.date_to),
    amountMin: nombre(req.query.amount_min),
    amountMax: nombre(req.query.amount_max),
  };
}

export const getHistory = async (req: AdminRequest, res: Response) => {
  try {
    res.json(await svc.getHistory({
      ...lirePagination(req.query),
      ...filtresDe(req),
      sortDir:  req.query.sort_dir === 'asc' ? 'asc' : 'desc',
    }));
  } catch (e: any) { repondreErreur(res, e); }
};

export const getStats = async (_req: AdminRequest, res: Response) => {
  try { res.json(await svc.getStats()); }
  catch (e: any) { repondreErreur(res, e); }
};

export const updateTransaction = async (req: AdminRequest, res: Response) => {
  try {
    res.json(await svc.updateTransaction(req.params.id, {
      status:    req.body.status,
      adminNote: req.body.admin_note,
    }));
  } catch (e: any) { repondreErreur(res, e, 400); }
};

export const exportCsv = async (req: AdminRequest, res: Response) => {
  try {
    // Les mêmes filtres que l'écran : l'export ignorait recherche et méthode.
    const csv = await svc.exportCsv(filtresDe(req));
    const date = new Date().toISOString().split('T')[0];
    res.setHeader('Content-Type', 'text/csv; charset=utf-8');
    res.setHeader('Content-Disposition', `attachment; filename="transactions_${date}.csv"`);
    res.send('\uFEFF' + csv);
  } catch (e: any) { repondreErreur(res, e); }
};
