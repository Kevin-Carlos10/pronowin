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
        // Identifiants — `id` sert à la navigation vers le détail (le
        // backend résout aussi bien un id de pronostic que de match), tandis
        // que `match_id` est nécessaire pour l'action de retrait des favoris
        // (endpoint strict sur l'id du match).
        id:               p?.id ?? f.matchId,
        match_id:         f.matchId,
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

/**
 * Le paramètre reçu est tantôt un id de match, tantôt un id de pronostic :
 * la liste de l'Accueil sérialise `id: pronostic.id` alors que la liste des
 * matchs sérialise `id: match.id`, et la page détail relaie l'un ou l'autre.
 * Sans cette résolution, le bouton favori de la page détail échouait en 404
 * lorsqu'on y arrivait depuis l'Accueil.
 */
async function resolveMatchId(idOrPronosticId: string): Promise<string | null> {
  const match = await prisma.match.findUnique({
    where: { id: idOrPronosticId }, select: { id: true },
  });
  if (match) return match.id;

  const prono = await prisma.pronostic.findUnique({
    where: { id: idOrPronosticId }, select: { matchId: true },
  });
  return prono?.matchId ?? null;
}

export const addFavorite = async (req: AuthRequest, res: Response) => {
  try {
    const matchId = await resolveMatchId(req.params.id);
    if (!matchId) { res.status(404).json({ message: 'Match introuvable.' }); return; }

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
    // Symétrique de addFavorite : sans résolution, retirer un favori depuis
    // l'Accueil ne supprimait rien (deleteMany sur un id inexistant, silencieux).
    const matchId = await resolveMatchId(req.params.id);
    await prisma.userFavoriteMatch.deleteMany({
      where: { userId: req.userId!, matchId: matchId ?? req.params.id },
    });
    res.json({ success: true });
  } catch (e: any) {
    res.status(500).json({ message: e.message });
  }
};
