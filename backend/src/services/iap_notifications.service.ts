import crypto from 'crypto';

import { prisma } from '../lib/prisma';
import logger from '../utils/logger';
import { IapService } from './iap.service';

/**
 * La file de réception des notifications des stores.
 *
 * ── Ce qu'elle remplace ────────────────────────────────────────────────────
 *
 * Les webhooks Apple et Google traitaient la notification pendant la requête
 * et répondaient 200 quoi qu'il arrive — y compris quand le traitement
 * échouait. Pour le store, un 200 veut dire « reçu, ne renvoie pas ». Une
 * panne de la base pendant un renouvellement ou un remboursement, et
 * l'événement était perdu pour de bon (constat I10 de l'audit du
 * 24 septembre 2026).
 *
 * ── Ce qu'elle fait ────────────────────────────────────────────────────────
 *
 * Le webhook n'écrit que ceci : l'événement, tel que reçu. S'il y parvient, il
 * répond 200 ; s'il n'y parvient pas, il répond 503, et c'est le store qui
 * réessaie. Le traitement a lieu ensuite, ici, et se refait avec un délai
 * croissant tant qu'il échoue. Un même événement reçu deux fois n'est inscrit
 * qu'une fois.
 *
 * Une notification qui arrive avant que l'application ait déclaré l'achat —
 * cas normal, le store est souvent plus rapide — n'est pas perdue non plus :
 * elle est retentée, puis classée « ignorée » seulement après le dernier
 * essai.
 */
export const TENTATIVES_MAX = 10;
/** Durée pendant laquelle un traitement en cours est réservé à son exécutant. */
const BAIL_MS = 10 * 60 * 1000;

/** Délai avant le prochain essai : 1, 2, 4… minutes, six heures au plus. */
export function delaiAvantEssai(tentatives: number): number {
  return Math.min(6 * 3600_000, 60_000 * 2 ** Math.max(0, tentatives - 1));
}

/** Raisons pour lesquelles un événement doit être retenté plus tard. */
const EN_ATTENTE_ACHAT = new Set(['unknown_original_transaction', 'unknown_purchase_token']);

type Store = 'apple' | 'google';

export class FileNotificationsIap {
  constructor(private readonly iap = new IapService()) {}

  /**
   * Inscrit un événement reçu. Rend `doublon: true` s'il l'était déjà.
   * Lève si l'écriture échoue : c'est au webhook de répondre 503.
   */
  async recevoir(store: Store, evenementId: string, charge: object): Promise<{ doublon: boolean }> {
    try {
      // Dates posées ici plutôt que par le défaut de la base : une colonne
      // `timestamp` sans fuseau reçoit l'heure locale du serveur PostgreSQL,
      // que Prisma relit comme de l'UTC. Sur une base réglée hors UTC, un
      // événement tout juste reçu paraissait dû dans plusieurs heures.
      const maintenant = new Date();
      await prisma.iapNotification.create({
        data: { store, evenementId, charge: charge as any, recueLe: maintenant, prochaineTentative: maintenant },
      });
      return { doublon: false };
    } catch (e: any) {
      if (e?.code === 'P2002') return { doublon: true };
      throw e;
    }
  }

  /** Traite les événements dus. Rend le nombre d'événements examinés. */
  async traiterEnAttente(limite = 20): Promise<number> {
    const maintenant = new Date();
    const dus = await prisma.iapNotification.findMany({
      where: {
        statut: { in: ['recue', 'echec', 'en_cours'] },
        prochaineTentative: { lte: maintenant },
      },
      orderBy: { recueLe: 'asc' },
      take: limite,
    });

    for (const n of dus) {
      // Réserver l'événement : deux exécutants ne le traitent pas ensemble,
      // et un exécutant tombé en cours de route le libère à l'échéance du bail.
      const { count } = await prisma.iapNotification.updateMany({
        where: { id: n.id, statut: n.statut, prochaineTentative: n.prochaineTentative },
        data:  {
          statut: 'en_cours', tentatives: { increment: 1 },
          prochaineTentative: new Date(Date.now() + BAIL_MS),
        },
      });
      if (count === 0) continue;
      const tentatives = n.tentatives + 1;

      try {
        const resultat: any = n.store === 'apple'
          ? await this.iap.handleAppleNotification((n.charge as any).signedPayload)
          : await this.iap.handleGoogleNotification((n.charge as any).message ?? {});

        if (resultat?.ignored && EN_ATTENTE_ACHAT.has(resultat.reason) && tentatives < TENTATIVES_MAX) {
          // L'achat n'est pas encore connu : l'application ne l'a pas déclaré.
          await this._reporter(n.id, tentatives, `en attente de l'achat (${resultat.reason})`);
          continue;
        }
        await prisma.iapNotification.update({
          where: { id: n.id },
          data:  {
            statut: resultat?.ignored ? 'ignoree' : 'traitee',
            derniereErreur: resultat?.ignored ? String(resultat.reason ?? '') : null,
            traiteeLe: new Date(),
          },
        });
      } catch (e: any) {
        const message = String(e?.message ?? e).slice(0, 500);
        if (tentatives >= TENTATIVES_MAX) {
          logger.error(`[IAP] Notification ${n.store} abandonnée après ${tentatives} essais : ${message}`);
          await prisma.iapNotification.update({
            where: { id: n.id }, data: { statut: 'abandonnee', derniereErreur: message },
          });
        } else {
          await this._reporter(n.id, tentatives, message);
        }
      }
    }
    return dus.length;
  }

  private _reporter(id: string, tentatives: number, raison: string) {
    return prisma.iapNotification.update({
      where: { id },
      data:  {
        statut: 'echec', derniereErreur: raison.slice(0, 500),
        prochaineTentative: new Date(Date.now() + delaiAvantEssai(tentatives)),
      },
    });
  }
}

/**
 * L'identifiant d'un événement Apple : son `notificationUUID`, lu dans la
 * charge sans la croire pour autant (elle n'est qu'un index). À défaut,
 * l'empreinte de la charge : deux envois identiques restent un doublon.
 */
export function identifiantApple(signedPayload: string): string {
  try {
    const charge = JSON.parse(Buffer.from(signedPayload.split('.')[1], 'base64url').toString());
    if (typeof charge?.notificationUUID === 'string' && charge.notificationUUID) return charge.notificationUUID;
  } catch { /* charge illisible : l'empreinte suffit */ }
  return 'sha256:' + crypto.createHash('sha256').update(signedPayload).digest('hex');
}

/** L'identifiant d'un message Pub/Sub, ou l'empreinte de ses données. */
export function identifiantGoogle(message: { messageId?: string; message_id?: string; data?: string }): string {
  const id = message?.messageId ?? message?.message_id;
  if (typeof id === 'string' && id) return id;
  return 'sha256:' + crypto.createHash('sha256').update(String(message?.data ?? '')).digest('hex');
}
