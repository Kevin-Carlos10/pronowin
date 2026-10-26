import { Prisma } from '@prisma/client';

import { prisma } from '../lib/prisma';
import { ErreurMetier } from '../utils/erreurs';
import logger from '../utils/logger';
import { envoyerAlerteAdmin } from './email.service';

/**
 * Modération des commentaires : signaler, bloquer, trancher.
 *
 * L'App Store (règle 1.2) et Google Play exigent, pour des contenus publiés
 * par les membres, un moyen de signaler un contenu choquant avec une réponse
 * rapide, et un moyen de bloquer un membre abusif. Le filtre des contenus à la
 * publication est dans `utils/filtre_contenu.ts`.
 */

export const MOTIFS_SIGNALEMENT = ['spam', 'insulte', 'haine', 'sexuel', 'autre'] as const;
export type MotifSignalement = (typeof MOTIFS_SIGNALEMENT)[number];

/**
 * Signalements distincts à partir desquels un commentaire est retiré de
 * l'affichage en attendant la décision. Un seul ne suffit pas : un membre
 * mécontent masquerait ce qui le contredit.
 */
export const SEUIL_MASQUAGE = 3;

export type DecisionModeration = 'retenir' | 'rejeter';

export class ModerationService {

  // ─── Signaler ─────────────────────────────────────────────────────────────
  async signaler(auteurId: string, commentId: string, motif: MotifSignalement, detail?: string) {
    const comment = await prisma.comment.findUnique({
      where:  { id: commentId },
      select: { id: true, userId: true, content: true, masque: true, user: { select: { pseudo: true } } },
    });
    if (!comment) throw new ErreurMetier('Commentaire introuvable.', 404, 'COMMENTAIRE_INTROUVABLE');
    if (comment.userId === auteurId) {
      throw new ErreurMetier('Vous ne pouvez pas signaler votre propre commentaire.', 400, 'SIGNALEMENT_SOI');
    }

    try {
      await prisma.signalementCommentaire.create({
        data: { commentId, auteurId, motif, detail: detail?.trim() || null },
      });
    } catch (e) {
      if (e instanceof Prisma.PrismaClientKnownRequestError && e.code === 'P2002') {
        throw new ErreurMetier('Vous avez déjà signalé ce commentaire.', 409, 'DEJA_SIGNALE');
      }
      throw e;
    }

    const enAttente = await prisma.signalementCommentaire.count({
      where: { commentId, statut: 'en_attente' },
    });
    const masqueDOffice = !comment.masque && enAttente >= SEUIL_MASQUAGE;
    if (masqueDOffice) {
      await prisma.comment.update({ where: { id: commentId }, data: { masque: true, masqueLe: new Date() } });
    }

    // Une alerte au premier signalement, une autre quand le commentaire est
    // retiré d'office : Apple attend une réponse rapide, il faut le savoir.
    if (enAttente === 1 || masqueDOffice) {
      const extrait = comment.content.length > 200 ? `${comment.content.slice(0, 200)}…` : comment.content;
      envoyerAlerteAdmin(
        masqueDOffice
          ? `[PronoWin] Commentaire masqué d'office (${enAttente} signalements)`
          : '[PronoWin] Commentaire signalé',
        `Auteur : ${comment.user.pseudo}\nMotif : ${motif}\n\n« ${extrait} »\n\n`
        + 'À traiter dans le panneau d\'administration, page Modération.',
      ).catch((e) => logger.error('[Modération] alerte impossible', { message: e?.message }));
    }

    return { masque: comment.masque || masqueDOffice };
  }

  // ─── Bloquer ──────────────────────────────────────────────────────────────
  async bloquer(bloqueurId: string, bloqueId: string) {
    if (bloqueurId === bloqueId) {
      throw new ErreurMetier('Vous ne pouvez pas vous bloquer vous-même.', 400, 'BLOCAGE_SOI');
    }
    const cible = await prisma.user.findUnique({ where: { id: bloqueId }, select: { id: true } });
    if (!cible) throw new ErreurMetier('Membre introuvable.', 404, 'MEMBRE_INTROUVABLE');
    await prisma.blocageUtilisateur.upsert({
      where:  { bloqueurId_bloqueId: { bloqueurId, bloqueId } },
      create: { bloqueurId, bloqueId },
      update: {},
    });
  }

  async debloquer(bloqueurId: string, bloqueId: string) {
    await prisma.blocageUtilisateur.deleteMany({ where: { bloqueurId, bloqueId } });
  }

  async listeBloques(bloqueurId: string) {
    const blocages = await prisma.blocageUtilisateur.findMany({
      where:   { bloqueurId },
      include: { bloque: { select: { id: true, pseudo: true, avatarUrl: true } } },
      orderBy: { creeLe: 'desc' },
    });
    return blocages.map((b) => ({
      user_id:    b.bloque.id,
      pseudo:     b.bloque.pseudo,
      avatar_url: b.bloque.avatarUrl ?? null,
      bloque_le:  b.creeLe,
    }));
  }

  async idsBloques(bloqueurId: string): Promise<string[]> {
    const blocages = await prisma.blocageUtilisateur.findMany({
      where: { bloqueurId }, select: { bloqueId: true },
    });
    return blocages.map((b) => b.bloqueId);
  }

  // ─── Trancher (panneau d'administration) ──────────────────────────────────
  /**
   * Les commentaires signalés, avec leurs signalements, par statut :
   * `en_attente` (à traiter) ou `traites`.
   */
  async commentairesSignales(statut: 'en_attente' | 'traites', page = 1, parPage = 20) {
    const filtre: Prisma.SignalementCommentaireWhereInput = statut === 'en_attente'
      ? { statut: 'en_attente' }
      : { statut: { in: ['retenu', 'rejete'] } };
    const where: Prisma.CommentWhereInput = { signalements: { some: filtre } };

    const [total, commentaires] = await Promise.all([
      prisma.comment.count({ where }),
      prisma.comment.findMany({
        where,
        include: {
          user:      { select: { id: true, pseudo: true } },
          pronostic: { select: { match: { select: { homeTeam: true, awayTeam: true } } } },
          signalements: {
            where:   filtre,
            include: { auteur: { select: { pseudo: true } } },
            orderBy: { creeLe: 'desc' },
          },
        },
        orderBy: { createdAt: 'desc' },
        skip:    (page - 1) * parPage,
        take:    parPage,
      }),
    ]);

    return {
      total,
      data: commentaires.map((c) => ({
        comment_id: c.id,
        contenu:    c.content,
        masque:     c.masque,
        publie_le:  c.createdAt,
        auteur:     { id: c.user.id, pseudo: c.user.pseudo },
        match:      `${c.pronostic.match.homeTeam} – ${c.pronostic.match.awayTeam}`,
        signalements: c.signalements.map((s) => ({
          motif:      s.motif,
          detail:     s.detail,
          statut:     s.statut,
          par:        s.auteur.pseudo,
          le:         s.creeLe,
          traite_par: s.traitePar,
          traite_le:  s.traiteLe,
        })),
      })),
    };
  }

  /**
   * Retenir : le commentaire reste retiré de l'affichage. Rejeter : il
   * revient, s'il avait été masqué d'office. Les signalements en attente
   * prennent la décision.
   */
  async trancher(commentId: string, decision: DecisionModeration, adminNom: string) {
    const enAttente = await prisma.signalementCommentaire.count({
      where: { commentId, statut: 'en_attente' },
    });
    if (enAttente === 0) {
      throw new ErreurMetier('Aucun signalement en attente pour ce commentaire.', 409, 'DEJA_TRAITE');
    }
    const maintenant = new Date();
    const retenu = decision === 'retenir';
    await prisma.$transaction([
      prisma.signalementCommentaire.updateMany({
        where: { commentId, statut: 'en_attente' },
        data:  { statut: retenu ? 'retenu' : 'rejete', traiteLe: maintenant, traitePar: adminNom },
      }),
      prisma.comment.update({
        where: { id: commentId },
        data:  { masque: retenu, masqueLe: retenu ? maintenant : null },
      }),
    ]);
    return { comment_id: commentId, decision, signalements: enAttente };
  }

  /** Nombre de commentaires à traiter, pour le panneau. */
  async aTraiter(): Promise<number> {
    return prisma.comment.count({ where: { signalements: { some: { statut: 'en_attente' } } } });
  }
}
