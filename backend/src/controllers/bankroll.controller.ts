import { Response } from 'express';
import { AuthRequest } from '../middleware/auth.middleware';
import { AdminRequest } from '../middleware/admin.middleware';
import { prisma } from '../lib/prisma';
import * as svc from '../services/bankroll.service';

export const getBankroll = async (req: AuthRequest, res: Response) => {
  try {
    const bankroll = await svc.getBankroll(req.userId!);
    if (!bankroll) { res.json(null); return; }

    res.json({
      id:             bankroll.id,
      total_budget:   bankroll.totalBudget,
      current_balance: bankroll.currentBalance,
      currency:       bankroll.currency,
      bets: bankroll.bets.map(b => ({
        id:              b.id,
        pronostic_id:    b.pronosticId,
        staked_amount:   b.stakedAmount,
        suggested_amount: b.suggestedAmount,
        odds_used:       b.oddsUsed,
        potential_gain:  b.potentialGain,
        result:          b.result,
        profit:          b.profit,
        settled_at:      b.settledAt,
        created_at:      b.createdAt,
        match: {
          id:          b.pronostic.match.id,
          home_team:   b.pronostic.match.homeTeam,
          away_team:   b.pronostic.match.awayTeam,
          match_date:  b.pronostic.match.matchDate,
          league:      b.pronostic.match.league,
        },
        prediction_label: b.pronostic.predictionLabel,
        confidence_score: b.pronostic.confidenceScore,
      })),
    });
  } catch (e: any) { res.status(500).json({ message: e.message }); }
};

export const setBudget = async (req: AuthRequest, res: Response) => {
  try {
    const { total_budget, currency } = req.body;
    if (!total_budget || total_budget <= 0) {
      res.status(400).json({ message: 'Budget invalide.' }); return;
    }
    const b = await svc.setBudget(req.userId!, parseFloat(total_budget), currency);
    res.json({ total_budget: b.totalBudget, current_balance: b.currentBalance, currency: b.currency });
  } catch (e: any) { res.status(400).json({ message: e.message }); }
};

export const resetBankroll = async (req: AuthRequest, res: Response) => {
  try {
    const b = await svc.resetBankroll(req.userId!);
    res.json({ current_balance: b.currentBalance });
  } catch (e: any) { res.status(400).json({ message: e.message }); }
};

export const placeBet = async (req: AuthRequest, res: Response) => {
  try {
    const { pronostic_id, staked_amount } = req.body;
    if (!pronostic_id || !staked_amount) {
      res.status(400).json({ message: 'pronostic_id et staked_amount requis.' }); return;
    }
    const bet = await svc.placeBet(req.userId!, pronostic_id, parseFloat(staked_amount));
    res.status(201).json(bet);
  } catch (e: any) {
    const isDuplicate = e.message?.includes('déjà misé');
    res.status(isDuplicate ? 409 : 400).json({
      message: e.message,
      ...(isDuplicate ? { code: 'BET_ALREADY_PLACED' } : {}),
    });
  }
};

export const getStats = async (req: AuthRequest, res: Response) => {
  try {
    const stats = await svc.getBankrollStats(req.userId!);
    res.json(stats);
  } catch (e: any) { res.status(500).json({ message: e.message }); }
};

export const getSuggestedStake = async (req: AuthRequest, res: Response) => {
  try {
    const bankroll = await svc.getBankroll(req.userId!);
    if (!bankroll) { res.status(404).json({ message: 'Pas de bankroll configurée.' }); return; }

    const confidenceScore = parseInt(req.query.confidence as string ?? '60');
    const suggested = svc.suggestStake(bankroll.currentBalance, confidenceScore);
    res.json({
      suggested_amount: suggested,
      current_balance:  bankroll.currentBalance,
      currency:         bankroll.currency,
    });
  } catch (e: any) { res.status(500).json({ message: e.message }); }
};

// ── ADMIN ──────────────────────────────────────────────────────────────────────
/** GET /bankroll/admin/list — vue d'ensemble de toutes les bankrolls utilisateur */
export const adminListBankrolls = async (req: AdminRequest, res: Response) => {
  try {
    const result = await svc.listBankrolls({
      page:    parseInt(req.query.page as string ?? '1'),
      perPage: parseInt(req.query.per_page as string ?? '20'),
      search:  req.query.search as string,
      sortBy:  req.query.sort_by as any,
      sortDir: (req.query.sort_dir as 'asc' | 'desc') ?? 'desc',
    });
    res.json(result);
  } catch (e: any) { res.status(500).json({ message: e.message }); }
};

/** GET /bankroll/admin/stats — agrégats sur toutes les bankrolls */
export const adminBankrollStats = async (_req: AdminRequest, res: Response) => {
  try { res.json(await svc.listBankrollsStats()); }
  catch (e: any) { res.status(500).json({ message: e.message }); }
};

/** GET /bankroll/admin/:userId — détail complet de la bankroll d'un utilisateur */
export const adminGetBankrollDetail = async (req: AdminRequest, res: Response) => {
  try {
    const user = await prisma.user.findUnique({
      where:  { id: req.params.userId },
      select: { id: true, pseudo: true, phoneNumber: true, email: true, avatarUrl: true, createdAt: true },
    });
    if (!user) { res.status(404).json({ message: 'Utilisateur introuvable.' }); return; }

    const [bankroll, stats] = await Promise.all([
      svc.getBankroll(req.params.userId),
      svc.getBankrollStats(req.params.userId),
    ]);

    res.json({
      user,
      bankroll: bankroll ? {
        id:              bankroll.id,
        total_budget:    bankroll.totalBudget,
        current_balance: bankroll.currentBalance,
        currency:        bankroll.currency,
        last_reset_at:   bankroll.lastResetAt,
        created_at:      bankroll.createdAt,
        bets: bankroll.bets.map(b => ({
          id:               b.id,
          staked_amount:    b.stakedAmount,
          suggested_amount: b.suggestedAmount,
          odds_used:        b.oddsUsed,
          potential_gain:   b.potentialGain,
          result:           b.result,
          profit:           b.profit,
          settled_at:       b.settledAt,
          created_at:       b.createdAt,
          match: {
            id:         b.pronostic.match.id,
            home_team:  b.pronostic.match.homeTeam,
            away_team:  b.pronostic.match.awayTeam,
            match_date: b.pronostic.match.matchDate,
            league:     b.pronostic.match.league,
          },
          prediction_label: b.pronostic.predictionLabel,
          confidence_score: b.pronostic.confidenceScore,
        })),
      } : null,
      stats,
    });
  } catch (e: any) { res.status(500).json({ message: e.message }); }
};
