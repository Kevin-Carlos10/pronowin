import crypto from 'crypto';
import { Response } from 'express';

import logger from './logger';

/**
 * Une erreur dont le message est destiné à l'utilisateur.
 *
 * C'est la seule dont le texte peut sortir tel quel de l'API. Le statut dit
 * ce qui s'est passé : 400 saisie refusée, 403 interdit, 404 introuvable, 409
 * conflit, 422 données invalides, 503 service indisponible.
 */
export class ErreurMetier extends Error {
  constructor(message: string, public statut = 400, public code?: string) {
    super(message);
    this.name = 'ErreurMetier';
  }
}

/** Une dépendance indispensable manque ou ne répond pas. */
export class ServiceIndisponible extends ErreurMetier {
  constructor(message: string, code = 'SERVICE_INDISPONIBLE') {
    super(message, 503, code);
    this.name = 'ServiceIndisponible';
  }
}

/**
 * Cette erreur vient-elle de la mécanique — base, réseau, bibliothèque, bug —
 * plutôt que d'une règle métier ?
 *
 * Quatre-vingt-sept routes renvoyaient `err.message` dans leurs réponses 500
 * (constat S2 de l'audit du 24 septembre 2026). Pour une erreur Prisma, ce
 * message nomme la table, la colonne, la contrainte, parfois la requête : de
 * quoi cartographier la base depuis l'extérieur. Pour une erreur Axios, il
 * dit quel fournisseur a répondu quoi.
 *
 * Les services lèvent aussi des `Error` ordinaires porteuses de messages
 * écrits pour l'utilisateur (« Preuve déjà traitée. »). On ne peut pas les
 * convertir toutes d'un coup ; on reconnaît donc ce qui, à coup sûr, n'en est
 * pas une.
 */
export function estErreurTechnique(e: unknown): boolean {
  if (!e || typeof e !== 'object') return true;
  if (e instanceof ErreurMetier) return false;
  const err = e as { name?: unknown; message?: unknown; code?: unknown; isAxiosError?: unknown };
  const nom = String(err.name ?? '');
  if (/^PrismaClient/.test(nom)) return true;
  if (err.isAxiosError) return true;
  if (e instanceof TypeError || e instanceof ReferenceError
      || e instanceof RangeError || e instanceof SyntaxError) return true;
  if (typeof err.code === 'string' && /^(P\d{4}|E[A-Z]{3,})$/.test(err.code)) return true;
  const message = String(err.message ?? '');
  if (!message) return true;
  return /prisma|invocation|\bE(CONN|TIMEDOUT|NOTFOUND|AI_AGAIN)|column|relation "|constraint|violates|null value|Cannot read|is not a function|Unexpected token|socket hang up|timeout of \d+ms|status code \d{3}/i
    .test(message);
}

/** La base de données, ou le réseau qui y mène, ne répond pas. */
export function estIndisponibilite(e: unknown): boolean {
  const err = (e ?? {}) as { name?: unknown; message?: unknown; code?: unknown };
  return /^PrismaClient(Initialization|RustPanic)Error$/.test(String(err.name ?? ''))
    || ['P1001', 'P1002', 'P1008', 'P1017', 'P2024'].includes(String(err.code ?? ''))
    || /Can't reach database|ECONNREFUSED|ETIMEDOUT|Connection terminated/i.test(String(err.message ?? ''));
}

/**
 * Répond à une erreur attrapée par un contrôleur.
 *
 * Une erreur métier sort avec son message et son statut. Une erreur technique
 * sort sans détail : un message générique, une référence, et le détail
 * complet dans le journal du serveur sous cette même référence — c'est elle
 * qu'un utilisateur transmet au support.
 *
 * [statut] est celui que la route employait pour ses erreurs métier.
 */
export function repondreErreur(res: Response, e: unknown, statut = 500): void {
  if (e instanceof ErreurMetier) {
    res.status(e.statut).json({ message: e.message, ...(e.code ? { code: e.code } : {}) });
    return;
  }
  if (!estErreurTechnique(e)) {
    // Certains services portent leur propre statut (`statut`), comme le
    // quota d'envoi des codes : on le respecte.
    const propre = (e as { statut?: unknown }).statut;
    res.status(typeof propre === 'number' ? propre : statut).json({ message: (e as Error).message });
    return;
  }
  const reference = crypto.randomBytes(4).toString('hex');
  const req = res.req;
  logger.error(`[API] réf. ${reference} — ${req?.method ?? '?'} ${req?.originalUrl ?? '?'} — `
    + ((e as Error)?.stack ?? String(e)));
  if (estIndisponibilite(e)) {
    res.status(503).json({
      message: 'Service momentanément indisponible. Réessayez dans un instant.',
      code: 'SERVICE_INDISPONIBLE', reference,
    });
    return;
  }
  res.status(500).json({
    message: 'Erreur interne. Si elle persiste, communiquez cette référence au support.',
    code: 'ERREUR_INTERNE', reference,
  });
}
