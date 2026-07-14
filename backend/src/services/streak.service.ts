
import { prisma } from '../lib/prisma';

// XP accordé selon la longueur du streak
function xpForStreak(streak: number): number {
  if (streak >= 30) return 50;
  if (streak >= 14) return 30;
  if (streak >= 7)  return 20;
  if (streak >= 3)  return 15;
  return 10;
}

// Milestones pour l'affichage côté client
export const STREAK_MILESTONES = [3, 7, 14, 30];

function toDateKey(d: Date): string {
  return `${d.getFullYear()}-${d.getMonth()}-${d.getDate()}`;
}

/**
 * Appelé à chaque login réussi.
 * Retourne les infos streak mises à jour + le XP gagné ce jour (0 si déjà réclamé).
 */
export async function updateStreak(userId: string): Promise<{
  streakDays:    number;
  xpTotal:       number;
  xpEarned:      number;
  todayClaimed:  boolean;
  isMilestone:   boolean;
}> {
  const user = await prisma.user.findUnique({
    where:  { id: userId },
    select: { streakDays: true, streakLastDate: true, xpTotal: true },
  });
  if (!user) throw new Error('Utilisateur introuvable.');

  const now      = new Date();
  const todayKey = toDateKey(now);

  // Déjà réclamé aujourd'hui → rien à faire
  if (user.streakLastDate && toDateKey(user.streakLastDate) === todayKey) {
    return {
      streakDays:   user.streakDays,
      xpTotal:      user.xpTotal,
      xpEarned:     0,
      todayClaimed: true,
      isMilestone:  false,
    };
  }

  // Calcul du nouveau streak
  let newStreak: number;
  if (!user.streakLastDate) {
    newStreak = 1;
  } else {
    const yesterday = new Date(now);
    yesterday.setDate(yesterday.getDate() - 1);
    const lastKey = toDateKey(user.streakLastDate);
    newStreak = lastKey === toDateKey(yesterday) ? user.streakDays + 1 : 1;
  }

  const xpEarned    = xpForStreak(newStreak);
  const newXp       = user.xpTotal + xpEarned;
  const isMilestone = STREAK_MILESTONES.includes(newStreak);

  await prisma.user.update({
    where: { id: userId },
    data: {
      streakDays:     newStreak,
      streakLastDate: now,
      xpTotal:        newXp,
      lastLoginAt:    now,
    },
  });

  return {
    streakDays:   newStreak,
    xpTotal:      newXp,
    xpEarned,
    todayClaimed: false,
    isMilestone,
  };
}

/** Lecture seule — GET /me/streak */
export async function getStreak(userId: string) {
  const user = await prisma.user.findUnique({
    where:  { id: userId },
    select: { streakDays: true, streakLastDate: true, xpTotal: true },
  });
  if (!user) throw new Error('Utilisateur introuvable.');

  const now      = new Date();
  const todayKey = toDateKey(now);
  const todayClaimed = !!user.streakLastDate &&
      toDateKey(user.streakLastDate) === todayKey;

  // Streak cassé si dernier login > hier (et pas aujourd'hui)
  let activeStreak = user.streakDays;
  if (user.streakLastDate && !todayClaimed) {
    const yesterday = new Date(now);
    yesterday.setDate(yesterday.getDate() - 1);
    const lastKey = toDateKey(user.streakLastDate);
    if (lastKey !== toDateKey(yesterday)) activeStreak = 0;
  }

  const nextMilestone = STREAK_MILESTONES.find(m => m > activeStreak) ?? 30;

  return {
    streakDays:     activeStreak,
    xpTotal:        user.xpTotal,
    todayClaimed,
    nextMilestone,
    milestones:     STREAK_MILESTONES,
  };
}
