import { Response } from 'express';
import { AdminRequest } from '../middleware/admin.middleware';
import { prisma } from '../lib/prisma';

/** Lecture groupée en base : aucun appel au fournisseur de scores par navigateur. */
export async function getAdminScores(req: AdminRequest, res: Response) {
  const ids = req.body?.ids;
  if (!Array.isArray(ids) || !ids.length || ids.length > 400 ||
      ids.some(id => typeof id !== 'string' || !/^[a-zA-Z0-9_-]{1,80}$/.test(id))) {
    res.status(400).json({message: 'Liste de matchs invalide (1 à 400 identifiants).'}); return;
  }
  try {
    const matches = await prisma.match.findMany({
      where: {id: {in: [...new Set<string>(ids)]}},
      select: {id:true, status:true, homeScore:true, awayScore:true, elapsedMinutes:true,
        pronostic:{select:{result:true}}},
    });
    res.setHeader('Cache-Control','no-store');
    res.json({matches, checkedAt: new Date().toISOString()});
  } catch {
    res.status(503).json({message:'Scores temporairement indisponibles.'});
  }
}
