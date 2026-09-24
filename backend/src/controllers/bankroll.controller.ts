import { Response } from 'express';
import { AuthRequest } from '../middleware/auth.middleware';
import { AdminRequest } from '../middleware/admin.middleware';
import { prisma } from '../lib/prisma';
import * as svc from '../services/bankroll.service';
import { partSelonConfiance } from '../services/mise_suggeree';
import { repondreErreur } from '../utils/erreurs';

export const getBankroll = async (req: AuthRequest, res: Response) => {
  try {
    const bankroll = await svc.getBankroll(req.userId!);
    if (!bankroll) { res.json(null); return; }

    // Le bilan porte sur tout l'historique, la liste sur ce qu'on affiche.
    //
    // L'écran calculait ses compteurs, son taux et sa courbe depuis les
    // cinquante paris renvoyés, et les présentait comme le bilan complet. Au
    // cinquante-et-unième, les chiffres devenaient faux en silence.
    const resume = await svc.resumeParis(bankroll.id);

    res.json({
      id:             bankroll.id,
      total_budget:   bankroll.totalBudget,
      current_balance: bankroll.currentBalance,
      currency:       bankroll.currency,
      resume,
      // Combien de lignes accompagnent ce bilan — pour que l'écran puisse dire
      // « 50 des 128 paris » au lieu de laisser croire qu'il les montre tous.
      paris_affiches: bankroll.bets.length,
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
  } catch (e: any) { repondreErreur(res, e); }
};

export const setBudget = async (req: AuthRequest, res: Response) => {
  try {
    const { total_budget, currency } = req.body;
    if (!total_budget || total_budget <= 0) {
      res.status(400).json({ message: 'Budget invalide.' }); return;
    }
    const b = await svc.setBudget(req.userId!, parseFloat(total_budget), currency);
    res.json({ total_budget: b.totalBudget, current_balance: b.currentBalance, currency: b.currency });
  } catch (e: any) { repondreErreur(res, e, 400); }
};

export const resetBankroll = async (req: AuthRequest, res: Response) => {
  try {
    const b = await svc.resetBankroll(req.userId!);
    res.json({ current_balance: b.currentBalance });
  } catch (e: any) { repondreErreur(res, e, 400); }
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
    // La saisie fermée n'est pas une demande malformée : l'état du match a
    // changé. Le code permet au mobile de rafraîchir sa liste plutôt que
    // d'afficher une erreur que l'utilisateur ne peut pas corriger.
    if (e instanceof svc.PariFerme) {
      res.status(e.statut).json({
        message: e.message,
        code:    `BET_CLOSED_${e.motif.toUpperCase()}`,
      });
      return;
    }
    if (e instanceof svc.MiseAActualiser) {
      res.status(409).json({message:e.message, code:'STAKE_CHANGED'}); return;
    }
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
  } catch (e: any) { repondreErreur(res, e); }
};

export const getSuggestedStake = async (req: AuthRequest, res: Response) => {
  try {
    const bankroll = await svc.getBankroll(req.userId!);
    if (!bankroll) { res.status(404).json({ message: 'Pas de bankroll configurée.' }); return; }

    // Le nouveau mobile transmet le pronostic : la note vient du serveur.
    // Compatibilité avec les versions déjà installées : confidence ne sert
    // qu'à l'aperçu ; placeBet impose toujours la vraie note du pronostic.
    let confidenceScore = Number(req.query.confidence ?? 3);
    if (req.query.pronostic_id != null) {
      if (typeof req.query.pronostic_id !== 'string' || req.query.pronostic_id.length > 80) {
        res.status(400).json({message:'Pronostic invalide.'}); return;
      }
      const id = req.query.pronostic_id;
      const pro = await prisma.pronostic.findUnique({where:{id}}) ??
        await prisma.pronostic.findUnique({where:{matchId:id}});
      if (!pro) { res.status(404).json({message:'Pronostic introuvable.'}); return; }
      confidenceScore = pro.confidenceScore;
    }
    if (!Number.isInteger(confidenceScore) || confidenceScore < 1 || confidenceScore > 5) {
      res.status(400).json({message:'Confiance invalide : note attendue de 1 à 5.'}); return;
    }
    const suggested = svc.suggestStake(
      bankroll.currentBalance, confidenceScore, bankroll.currency);
    res.json({
      suggested_amount: suggested,
      stake_percent:    partSelonConfiance(confidenceScore) * 100,
      confidence_score: confidenceScore,
      stake_rule:       "analyst_confidence",
      current_balance:  bankroll.currentBalance,
      currency:         bankroll.currency,
    });
  } catch (e: any) { repondreErreur(res, e); }
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
  } catch (e: any) { repondreErreur(res, e); }
};

/** GET /bankroll/admin/stats — agrégats sur toutes les bankrolls */
export const adminBankrollStats = async (_req: AdminRequest, res: Response) => {
  try { res.json(await svc.listBankrollsStats()); }
  catch (e: any) { repondreErreur(res, e); }
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
  } catch (e: any) { repondreErreur(res, e); }
};
