import crypto from 'crypto';
import { prisma } from '../lib/prisma';

const notes = new Map<string, number>();
const DELAI = 120_000;
export function plateformeSession(headers: Record<string, unknown>): string | null {
  const p = headers['x-app-plateforme'];
  return typeof p === 'string' && ['ios', 'android', 'web'].includes(p) ? p : null;
}

/** Métadonnées indicatives, jamais utilisées comme preuve d'identité. */
export async function noterSession(userId: string, sessionId: string | undefined,
    headers: Record<string, unknown>, force = false): Promise<void> {
  if (!sessionId || sessionId.length > 64) return;
  const platform = plateformeSession(headers);
  const cle = `${userId}:${sessionId}:${platform ?? ''}`;
  const now = Date.now();
  if (!force && now - (notes.get(cle) ?? 0) < DELAI) return;
  if (notes.size > 50_000) notes.clear();
  notes.set(cle, now);
  try {
    await prisma.refreshToken.updateMany({
      where: { userId, OR: [{ sessionId }, { id: sessionId, sessionId: null }],
        used: false, expiresAt: { gt: new Date(now) } },
      data: { sessionId, lastSeenAt: new Date(now), ...(platform ? { platform } : {}) },
    });
  } catch (e) { notes.delete(cle); throw e; }
}

/** Une ligne par session ouverte, aucune donnée d'un autre compte ni secret. */
export async function listerSessions(userId: string, sessionId?: string,
    refreshToken?: string, headers: Record<string, unknown> = {}) {
  let actuelle = sessionId;
  // Les anciens JWT n'ont pas de sessionId. Le jeton ne sert qu'à identifier
  // la session, après vérification du propriétaire par le filtre userId.
  if (!actuelle && refreshToken) {
    const token = crypto.createHash('sha256').update(refreshToken).digest('hex');
    const row = await prisma.refreshToken.findFirst({
      where: { userId, token: { in: [token, refreshToken] }, expiresAt: { gt: new Date() } },
      select: { id: true, sessionId: true },
    });
    if (row) actuelle = row.sessionId ?? row.id;
  }
  if (actuelle) await noterSession(userId, actuelle, headers, true);
  const rows = await prisma.refreshToken.findMany({
    where: { userId, used: false, expiresAt: { gt: new Date() } },
    select: { id: true, sessionId: true, platform: true, startedAt: true,
      createdAt: true, lastSeenAt: true },
    orderBy: [{ lastSeenAt: { sort: 'desc', nulls: 'last' } }, { createdAt: 'desc' }],
  });
  const uniques = new Map<string, typeof rows[number]>();
  for (const row of rows) {
    const id = row.sessionId ?? row.id;
    if (!uniques.has(id)) uniques.set(id, row);
  }
  return [...uniques].map(([id, row]) => ({
    id, platform: row.platform, current: id === actuelle,
    startedAt: row.startedAt ?? row.createdAt, lastSeenAt: row.lastSeenAt,
  })).sort((a, b) => Number(b.current) - Number(a.current));
}
