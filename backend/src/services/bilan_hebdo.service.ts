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
 * dont l'interrupteur des Paramètres est respecté. Aucun
 * prix ni moyen de paiement : le message part aussi vers les versions Google
 * Play et iPhone.
 *
 * Les taux suivent la Performance de l'application : pronostics publiés,
 * match terminé, remboursés exclus.
 *
 * ── Personnel, depuis le 27 octobre 2026 ───────────────────────────────────
 *
 * Le même texte partait à tous : 90 envoyés, 3 lus sur la semaine du
 * 19 octobre. Il commence désormais par ce que la personne a fait : ses
 * votes « Qui va gagner ? » (combien bien vus), ses matchs suivis (combien
 * de leurs pronostics gagnés). Sans activité, le bilan général seul, comme
 * avant. Un envoi par personne (`sendToUser`) : la push porte l'identifiant
 * de la notification, et la toucher la marque lue (1.0.32).
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

/** Ce que la personne a fait pendant la semaine. */
export interface BilanPerso { votes: number; votesJustes: number; suivis: number; suivisGagnes: number; suivisDecisifs: number }

const VIDE: BilanPerso = { votes: 0, votesJustes: 0, suivis: 0, suivisGagnes: 0, suivisDecisifs: 0 };

/** L'issue d'un match terminé, au score final : « 1 », « N » ou « 2 ». */
const issue = (dom: number | null, ext: number | null) =>
  dom === null || ext === null ? null : dom > ext ? '1' : dom < ext ? '2' : 'N';

/** Les bilans personnels de [userIds], sur les matchs joués entre [debut] et [fin]. */
export async function bilansPersonnels(userIds: string[], debut: Date, fin: Date): Promise<Map<string, BilanPerso>> {
  const joues = { status: 'FINISHED' as const, matchDate: { gte: debut, lt: fin } };
  const [votes, suivis] = await Promise.all([
    prisma.voteMatch.findMany({
      where:  { userId: { in: userIds }, match: joues },
      select: { userId: true, choix: true, match: { select: { homeScore: true, awayScore: true } } },
    }),
    prisma.userFavoriteMatch.findMany({
      where:  { userId: { in: userIds }, match: joues },
      select: { userId: true, match: { select: { pronostic: { select: { result: true, publicationRecordedAt: true } } } } },
    }),
  ]);
  const bilans = new Map<string, BilanPerso>();
  const de = (u: string) => bilans.get(u) ?? (bilans.set(u, { ...VIDE }), bilans.get(u)!);
  for (const v of votes) {
    const b = de(v.userId);
    b.votes++;
    if (v.choix === issue(v.match.homeScore, v.match.awayScore)) b.votesJustes++;
  }
  for (const f of suivis) {
    const b = de(f.userId);
    b.suivis++;
    const p = f.match.pronostic;
    // Le pronostic publié, gagné ou perdu (un remboursé ne compte pas).
    if (p?.publicationRecordedAt && (p.result === 'WIN' || p.result === 'LOSS')) {
      b.suivisDecisifs++;
      if (p.result === 'WIN') b.suivisGagnes++;
    }
  }
  return bilans;
}

/** La partie personnelle du bilan ; null sans activité. */
export function textePerso(b: BilanPerso | undefined, langue: 'fr' | 'en'): string | null {
  if (!b) return null;
  const fr = langue === 'fr';
  const parties: string[] = [];
  if (b.votes > 0) {
    parties.push(fr
      ? `Vos votes : ${b.votesJustes} ${b.votesJustes > 1 ? 'bien vus' : 'bien vu'} sur ${b.votes}`
      : `Your votes: ${b.votesJustes} of ${b.votes} spot on`);
  }
  if (b.suivis > 0) {
    const suivis = fr
      ? (b.suivis > 1 ? `Vos ${b.suivis} matchs suivis` : 'Votre match suivi')
      : (b.suivis > 1 ? `Your ${b.suivis} followed matches` : 'Your followed match');
    parties.push(b.suivisDecisifs === 0 ? suivis
      : fr ? `${suivis} : ${b.suivisGagnes} ${b.suivisGagnes > 1 ? 'pronostics gagnés' : 'pronostic gagné'} sur ${b.suivisDecisifs}`
           : `${suivis}: ${b.suivisGagnes} of ${b.suivisDecisifs} predictions won`);
  }
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
): Promise<{ envoye: boolean; raison?: string; destinataires?: number; personnels?: number }> {
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

  // Les comptes gratuits joignables, qui n'ont pas coupé « Offres &
  // Promotions » — ceux qu'atteignait l'envoi par segment.
  const comptes = await notifSvc.destinatairesJoignables('free');
  const perso = await bilansPersonnels(comptes.map(u => u.id), lundiPrecedent, lundi);

  let atteints = 0, personnels = 0;
  // Par lots de dix : une centaine de comptes, sans file d'attente.
  for (let i = 0; i < comptes.length; i += 10) {
    await Promise.all(comptes.slice(i, i + 10).map(async u => {
      const pFr = textePerso(perso.get(u.id), 'fr');
      const pEn = textePerso(perso.get(u.id), 'en');
      if (pFr) personnels++;
      const r = await notifSvc.sendToUser(u.id, {
        title: TITRE_BILAN, titleEn: 'Weekly recap',
        body:   pFr ? `${pFr}\n${fr}` : fr,
        bodyEn: pEn ? `${pEn}\n${en}` : en,
        data:   { type: 'promo', deep_link: '/historique' },
      }, 'promo').catch(() => ({ success: false }));
      if (r.success) atteints++;
    }));
  }
  journal.info(`[BilanHebdo] ${fr} — ${atteints} destinataire(s), dont ${personnels} bilan(s) personnel(s)`);
  return { envoye: true, destinataires: atteints, personnels };
}
