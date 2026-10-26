/**
 * Bilan de la semaine, chaque lundi, aux comptes gratuits (18 octobre 2026).
 *
 * « Pronostics gratuits : 7 gagnés sur 10 · VIP : 4 gagnés sur 5 ». Depuis
 * le 17 octobre, un pronostic VIP reste verrouillé pour un compte gratuit,
 * même après le match : son résultat se voit dans l'historique, pas son
 * choix. Ce bilan rappelle ce que ces pronostics ont donné.
 *
 * Il part CHAQUE semaine, bonne ou mauvaise. N'envoyer que les bonnes
 * présenterait comme un bilan ce qui n'en serait qu'une sélection. Seule
 * exception : une semaine sans aucun pronostic réglé — il n'y a rien à dire.
 *
 * C'est une incitation à l'abonnement : la catégorie « Offres & Promotions »,
 * dont l'interrupteur des Paramètres est respecté (`sendToSegment`). Aucun
 * prix ni moyen de paiement : le message part aussi vers les versions Google
 * Play et iPhone.
 *
 * Les taux suivent la Performance de l'application : pronostics publiés,
 * match terminé, remboursés exclus.
 */
import { prisma } from '../lib/prisma';
import { NotificationService } from './notification.service';
import { journal } from '../utils/logger';

export const TITRE_BILAN = 'Bilan de la semaine';
/** Lundi, à partir de 10 h UTC (10 h à Ouagadougou), jusqu'à 22 h. */
const HEURE_DEBUT = 10;
const HEURE_FIN = 22;

export interface Decompte { gagnes: number; decisifs: number }
export interface Bilan { gratuits: Decompte; vip: Decompte }

/** Lundi 00:00 UTC de la semaine de [d]. */
export function debutSemaine(d: Date): Date {
  const lundi = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
  lundi.setUTCDate(lundi.getUTCDate() - ((lundi.getUTCDay() + 6) % 7));
  return lundi;
}

/** Les pronostics réglés des matchs joués entre [debut] (inclus) et [fin] (exclu). */
export async function bilanEntre(debut: Date, fin: Date): Promise<Bilan> {
  const regles = await prisma.pronostic.findMany({
    where: {
      publicationRecordedAt: { not: null },
      result: { in: ['WIN', 'LOSS'] },
      match:  { status: 'FINISHED', matchDate: { gte: debut, lt: fin } },
    },
    select: { isPremium: true, result: true },
  });
  const bilan: Bilan = { gratuits: { gagnes: 0, decisifs: 0 }, vip: { gagnes: 0, decisifs: 0 } };
  for (const p of regles) {
    const d = p.isPremium ? bilan.vip : bilan.gratuits;
    d.decisifs++;
    if (p.result === 'WIN') d.gagnes++;
  }
  return bilan;
}

/** Le texte du bilan ; null si aucun pronostic n'a été réglé. */
export function texteBilan(b: Bilan, langue: 'fr' | 'en'): string | null {
  const parties: string[] = [];
  const partie = (libelle: { fr: string; en: string }, d: Decompte) => {
    if (d.decisifs === 0) return;
    parties.push(langue === 'fr'
      ? `${libelle.fr} : ${d.gagnes} ${d.gagnes > 1 ? 'gagnés' : 'gagné'} sur ${d.decisifs}`
      : `${libelle.en}: ${d.gagnes} of ${d.decisifs} won`);
  };
  partie({ fr: 'Pronostics gratuits', en: 'Free predictions' }, b.gratuits);
  partie({ fr: 'VIP', en: 'VIP' }, b.vip);
  return parties.length ? parties.join(' · ') : null;
}

/**
 * Envoie le bilan de la semaine écoulée si c'est le moment et qu'il n'est pas
 * déjà parti. Appelée toutes les heures : un redémarrage du serveur le lundi
 * ne le fait ni sauter ni partir deux fois — l'historique des notifications
 * sert de témoin.
 */
export async function envoyerBilanHebdo(
  maintenant = new Date(),
  notifSvc = new NotificationService(),
): Promise<{ envoye: boolean; raison?: string; destinataires?: number }> {
  const heure = maintenant.getUTCHours();
  if (maintenant.getUTCDay() !== 1 || heure < HEURE_DEBUT || heure >= HEURE_FIN) {
    return { envoye: false, raison: 'hors créneau' };
  }
  const lundi = debutSemaine(maintenant);
  const deja = await prisma.notification.findFirst({
    where:  { type: 'promo', title: TITRE_BILAN, createdAt: { gte: lundi } },
    select: { id: true },
  });
  if (deja) return { envoye: false, raison: 'déjà envoyé' };

  const lundiPrecedent = new Date(lundi.getTime() - 7 * 24 * 3600_000);
  const bilan = await bilanEntre(lundiPrecedent, lundi);
  const fr = texteBilan(bilan, 'fr');
  const en = texteBilan(bilan, 'en');
  if (!fr || !en) return { envoye: false, raison: 'aucun pronostic réglé' };

  const r = await notifSvc.sendToSegment('free', {
    title: TITRE_BILAN, titleEn: 'Weekly recap',
    body: fr, bodyEn: en,
    deepLink: '/historique',
  });
  journal.info(`[BilanHebdo] ${fr} — ${r.sent} destinataire(s)`);
  return { envoye: true, destinataires: r.sent };
}
