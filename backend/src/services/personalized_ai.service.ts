import { prisma } from '../lib/prisma';
import { computeProbability } from './ai_prediction.service';

// ── Types ─────────────────────────────────────────────────────────────────────

export interface UserProfile {
  totalBets:    number;
  winRate:      number;
  topLeagues:   string[];
  topBetTypes:  string[];
  oddsSweetMin: number;
  oddsSweetMax: number;
  isEmpty:      boolean;
}

export interface PersonalizedRecommendation {
  score:      number;
  reasons:    string[];
  pronostic:  any;
}

// ── Profiling ─────────────────────────────────────────────────────────────────

export async function buildUserProfile(userId: string): Promise<UserProfile> {
  const bankroll = await prisma.userBankroll.findUnique({
    where: { userId },
    include: {
      bets: {
        where:   { result: { not: null }, settledAt: { not: null } },
        include: { pronostic: { include: { match: true } } },
        orderBy: { createdAt: 'desc' },
        take:    60,
      },
    },
  });

  const bets = bankroll?.bets ?? [];

  if (bets.length < 3) {
    return {
      totalBets:    bets.length,
      winRate:      0,
      topLeagues:   [],
      topBetTypes:  [],
      oddsSweetMin: 1.0,
      oddsSweetMax: 4.0,
      isEmpty:      true,
    };
  }

  const wins = bets.filter((b) => b.result === 'WIN').length;
  const winRate = Math.round((wins / bets.length) * 100);

  // ── Ligues ────────────────────────────────────────────────────────────────
  const leagueStats: Record<string, { wins: number; total: number }> = {};
  for (const b of bets) {
    const league = b.pronostic.match.league;
    if (!leagueStats[league]) leagueStats[league] = { wins: 0, total: 0 };
    leagueStats[league].total++;
    if (b.result === 'WIN') leagueStats[league].wins++;
  }
  // Score mixte : (win_rate * 0.6 + volume_normalized * 0.4), seuil ≥ 2 paris
  const maxVol = Math.max(...Object.values(leagueStats).map((s) => s.total));
  const leagueScored = Object.entries(leagueStats)
    .filter(([, s]) => s.total >= 2)
    .map(([l, s]) => ({
      league: l,
      score: (s.wins / s.total) * 0.6 + (s.total / maxVol) * 0.4,
    }))
    .sort((a, b) => b.score - a.score);
  const topLeagues = leagueScored.slice(0, 3).map((l) => l.league);

  // ── Types de paris ────────────────────────────────────────────────────────
  const typeStats: Record<string, { wins: number; total: number }> = {};
  for (const b of bets) {
    const t = b.pronostic.predictionType;
    if (!typeStats[t]) typeStats[t] = { wins: 0, total: 0 };
    typeStats[t].total++;
    if (b.result === 'WIN') typeStats[t].wins++;
  }
  const topBetTypes = Object.entries(typeStats)
    .filter(([, s]) => s.total >= 2)
    .sort((a, b) => (b[1].wins / b[1].total) - (a[1].wins / a[1].total))
    .slice(0, 2)
    .map(([t]) => t);

  // ── Zone de cotes ─────────────────────────────────────────────────────────
  const winningOdds = bets
    .filter((b) => b.result === 'WIN')
    .map((b) => b.oddsUsed);

  let oddsSweetMin = 1.0;
  let oddsSweetMax = 4.0;
  if (winningOdds.length >= 2) {
    const sorted = [...winningOdds].sort((a, b) => a - b);
    const p25   = sorted[Math.floor(sorted.length * 0.25)];
    const p75   = sorted[Math.floor(sorted.length * 0.75)];
    oddsSweetMin = Math.max(1.0, +(p25 - 0.2).toFixed(2));
    oddsSweetMax = Math.min(10, +(p75 + 0.2).toFixed(2));
  }

  return {
    totalBets:   bets.length,
    winRate,
    topLeagues,
    topBetTypes,
    oddsSweetMin,
    oddsSweetMax,
    isEmpty: false,
  };
}

// ── Scoring & recommandations ─────────────────────────────────────────────────

export async function getPersonalizedPronostics(
  userId:  string,
  profile: UserProfile,
  limit = 10,
): Promise<PersonalizedRecommendation[]> {
  // Pronos publiés à venir (7 prochains jours)
  const now    = new Date();
  const cutoff = new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000);

  // IDs des pronos déjà misés par cet utilisateur
  const bankroll = await prisma.userBankroll.findUnique({ where: { userId } });
  const alreadyBetIds = bankroll
    ? (await prisma.bankrollBet.findMany({
        where:  { bankrollId: bankroll.id },
        select: { pronosticId: true },
      })).map((b) => b.pronosticId)
    : [];

  const pronostics = await prisma.pronostic.findMany({
    where: {
      isPublished: true,
      match: { matchDate: { gte: now, lte: cutoff }, status: 'SCHEDULED' },
      id: { notIn: alreadyBetIds },
    },
    include: { match: true, analyst: { select: { name: true } } },
    take: 50,
  });

  if (pronostics.length === 0) return [];

  const scored = pronostics.map((p) => {
    let score   = 0;
    const reasons: string[] = [];

    // ── Ligue favorite ──────────────────────────────────────────────────
    const leagueIdx = profile.topLeagues.indexOf(p.match.league);
    if (leagueIdx === 0) {
      score += 40; reasons.push('Ta ligue préférée 🏆');
    } else if (leagueIdx === 1) {
      score += 28; reasons.push('Une de tes meilleures ligues');
    } else if (leagueIdx === 2) {
      score += 18; reasons.push('Ligue où tu performes bien');
    }

    // ── Type de pari favori ─────────────────────────────────────────────
    const typeIdx = profile.topBetTypes.indexOf(p.predictionType);
    if (typeIdx === 0) {
      score += 30; reasons.push(`Ton type de pari gagnant (${_typeLabel(p.predictionType)})`);
    } else if (typeIdx === 1) {
      score += 18; reasons.push(`Type de pari maîtrisé (${_typeLabel(p.predictionType)})`);
    }

    // ── Zone de cotes ───────────────────────────────────────────────────
    const odds = p.oddsRecommended;
    if (odds >= profile.oddsSweetMin && odds <= profile.oddsSweetMax) {
      score += 20;
      reasons.push(`Cote dans ta zone de confort (${odds.toFixed(2)})`);
    } else if (odds >= profile.oddsSweetMin - 0.3 && odds <= profile.oddsSweetMax + 0.3) {
      score += 10;
      reasons.push(`Cote proche de tes habitudes (${odds.toFixed(2)})`);
    }

    // ── Confiance de l'analyste ─────────────────────────────────────────
    const confNorm = Math.min(p.confidenceScore, 100) / 100;
    score += Math.round(confNorm * 10);
    if (p.confidenceScore >= 80) reasons.push('Forte confiance de l\'analyste');

    // ── Probabilité statistique ─────────────────────────────────────────
    const aiProb = p.aiProbability ?? computeProbability(
      p.predictionType,
      p.oddsHome, p.oddsDraw, p.oddsAway, p.oddsRecommended,
      p.match.homeFormPoints, p.match.awayFormPoints,
    );
    if (aiProb >= 75) {
      score += 8; reasons.push(`Probabilité statistique élevée (${aiProb}%)`);
    }

    // Fallback si l'utilisateur n'a pas d'historique
    if (profile.isEmpty && reasons.length === 0) {
      if (p.confidenceScore >= 75) reasons.push('Sélection haute confiance');
      if (p.isPremium) reasons.push('Pronostic VIP');
    }

    if (reasons.length === 0) reasons.push('Pronostic de qualité sélectionné pour toi');

    return {
      score,
      reasons: reasons.slice(0, 3),
      pronostic: {
        id:             p.id,
        match_id:       p.matchId,
        league:         p.match.league,
        league_code:    p.match.leagueCode,
        home_team:      p.match.homeTeam,
        away_team:      p.match.awayTeam,
        match_date:     p.match.matchDate,
        prediction_type:  p.predictionType,
        prediction_label: p.predictionLabel,
        odds_recommended: p.oddsRecommended,
        confidence_score: p.confidenceScore,
        analyst_note:   p.analystNote,
        is_premium:     p.isPremium,
        ai_probability: Math.round(aiProb),
        analyst_name:   p.analyst?.name ?? 'Analyste',
      },
    };
  });

  return scored
    .sort((a, b) => b.score - a.score)
    .slice(0, limit);
}

function _typeLabel(t: string): string {
  return ({
    win1:    '1 (Victoire domicile)',
    draw:    'Nul',
    win2:    '2 (Victoire extérieur)',
    btts:    'Les 2 équipes marquent',
    over25:  'Plus de 2.5 buts',
    under25: 'Moins de 2.5 buts',
    over35:  'Plus de 3.5 buts',
    under35: 'Moins de 3.5 buts',
  } as Record<string, string>)[t] ?? t;
}
