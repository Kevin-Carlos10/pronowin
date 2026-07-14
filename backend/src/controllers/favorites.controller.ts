import { Response } from 'express';
import { AuthRequest } from '../middleware/auth.middleware';

import { prisma } from '../lib/prisma';

export const getFavorites = async (req: AuthRequest, res: Response) => {
  try {
    const favs = await prisma.userFavoriteMatch.findMany({
      where:   { userId: req.userId! },
      include: { match: { include: { pronostic: true } } },
      orderBy: { createdAt: 'desc' },
    });
    const result = favs.map(f => {
      const p = f.match.pronostic;
      const rawStatus = f.match.status.toLowerCase();
      const status = rawStatus === 'live' ? 'live'
                   : rawStatus === 'finished' ? 'finished'
                   : 'upcoming';
      return {
        // Identifiants
        id:               p?.id ?? f.matchId,
        // Match
        league:           f.match.league,
        league_country:   f.match.leagueCode ?? '',
        home_team:        f.match.homeTeam,
        away_team:        f.match.awayTeam,
        home_team_logo:   f.match.homeTeamLogo ?? null,
        away_team_logo:   f.match.awayTeamLogo ?? null,
        match_date:       f.match.matchDate,
        status,
        home_score:       f.match.homeScore ?? null,
        away_score:       f.match.awayScore ?? null,
        has_pronostic:    p !== null,
        // Pronostic (valeurs par défaut si pas de prono)
        prediction_type:  p?.predictionType  ?? 'win1',
        prediction_label: p?.predictionLabel ?? '',
        odds_recommended: p?.oddsRecommended ?? 0,
        odds_home:        p?.oddsHome        ?? 0,
        odds_draw:        p?.oddsDraw        ?? 0,
        odds_away:        p?.oddsAway        ?? 0,
        confidence_score: p?.confidenceScore ?? 1,
        is_premium:       p?.isPremium       ?? false,
        analyst_note:     p?.analystNote     ?? null,
        home_form_points: f.match.homeFormPoints ?? 0,
        away_form_points: f.match.awayFormPoints ?? 0,
        ai_probability:   p?.aiProbability   ?? null,
        ai_explanation:   p?.aiExplanation   ?? null,
      };
    });
    res.json(result);
  } catch (e: any) {
    res.status(500).json({ message: e.message });
  }
};

export const addFavorite = async (req: AuthRequest, res: Response) => {
  try {
    const matchId = req.params.id;
    const match = await prisma.match.findUnique({ where: { id: matchId } });
    if (!match) { res.status(404).json({ message: 'Match introuvable.' }); return; }

    await prisma.userFavoriteMatch.upsert({
      where:  { userId_matchId: { userId: req.userId!, matchId } },
      create: { userId: req.userId!, matchId },
      update: {},
    });
    res.json({ success: true });
  } catch (e: any) {
    res.status(500).json({ message: e.message });
  }
};

export const removeFavorite = async (req: AuthRequest, res: Response) => {
  try {
    await prisma.userFavoriteMatch.deleteMany({
      where: { userId: req.userId!, matchId: req.params.id },
    });
    res.json({ success: true });
  } catch (e: any) {
    res.status(500).json({ message: e.message });
  }
};
