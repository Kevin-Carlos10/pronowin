import { AsyncLocalStorage } from 'node:async_hooks';
import crypto from 'crypto';
import util from 'util';
import type { NextFunction, Request, Response } from 'express';
import winston from 'winston';

const { combine, timestamp, errors, json, colorize, simple } = winston.format;

/**
 * Le contexte de la requête en cours : son identifiant suit chaque ligne du
 * journal écrite pendant son traitement.
 *
 * Les journaux étaient surtout du texte libre (`console.*`, 81 appels contre
 * 28 au logger), sans identifiant commun : impossible de suivre une requête
 * d'un bout à l'autre, ou de retrouver ce qui s'était passé autour d'une
 * activation échouée (constat Q1 de l'audit du 24 septembre 2026).
 */
const contexte = new AsyncLocalStorage<{ requestId: string }>();

/** Ajoute l'identifiant de la requête en cours à chaque ligne. */
const avecRequete = winston.format((info) => {
  const id = contexte.getStore()?.requestId;
  if (id) info.requestId = id;
  return info;
});

const logger = winston.createLogger({
  level: process.env.LOG_LEVEL ?? 'info',
  format: combine(
    avecRequete(),
    timestamp(),
    errors({ stack: true }),
    json(),
  ),
  transports: [
    new winston.transports.Console({
      format: process.env.NODE_ENV === 'production'
        ? json()
        : combine(colorize(), simple()),
    }),
  ],
});

/**
 * L'identifiant de chaque requête : repris de `X-Request-Id` quand nginx ou un
 * client l'envoie (s'il a une forme raisonnable), fabriqué sinon, et renvoyé
 * dans la réponse — c'est lui qu'on demande à qui signale un problème.
 */
export function identifiantDeRequete(req: Request, res: Response, suite: NextFunction) {
  const recu = req.headers['x-request-id'];
  const id = typeof recu === 'string' && /^[\w-]{8,64}$/.test(recu) ? recu : crypto.randomUUID();
  (req as any).id = id;
  res.setHeader('X-Request-Id', id);
  contexte.run({ requestId: id }, suite);
}

/** L'identifiant de la requête en cours, ou `null` hors requête. */
export const requeteCourante = () => contexte.getStore()?.requestId ?? null;

/**
 * Une façade à la manière de `console`, pour les appels qui en avaient la
 * forme : les arguments sont assemblés comme `console` le ferait, puis écrits
 * par le logger — donc en JSON, horodatés, avec l'identifiant de requête.
 */
export const journal = {
  info:  (...a: unknown[]) => logger.info(util.format(...a)),
  warn:  (...a: unknown[]) => logger.warn(util.format(...a)),
  error: (...a: unknown[]) => logger.error(util.format(...a)),
};

export default logger;
