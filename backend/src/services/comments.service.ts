import { prisma } from '../lib/prisma';

export class CommentsService {

  /**
   * Le mobile envoie tantôt un id de pronostic, tantôt un id de match : la
   * liste de l'Accueil (`getPublishedPronostics`) sérialise `id: pronostic.id`
   * alors que la liste des matchs (`getAllMatches`) sérialise `id: match.id`,
   * et la page détail relaie l'un ou l'autre selon l'écran d'origine.
   *
   * Sans cette résolution, les commentaires ouverts depuis l'onglet Pronostics
   * étaient silencieusement vides à la lecture et échouaient en violation de
   * clé étrangère à la publication. Les autres endpoints du détail match font
   * déjà cette résolution (cf. `findPronoByIdOrMatchId`).
   *
   * Renvoie `null` si aucun pronostic ne correspond.
   */
  private async _resolvePronosticId(idOrMatchId: string): Promise<string | null> {
    const byProno = await prisma.pronostic.findUnique({
      where: { id: idOrMatchId }, select: { id: true },
    });
    if (byProno) return byProno.id;

    const byMatch = await prisma.pronostic.findUnique({
      where: { matchId: idOrMatchId }, select: { id: true },
    });
    return byMatch?.id ?? null;
  }

  // ─── Récupérer les commentaires d'un pronostic ───────────────────────────────
  async getComments(idOrMatchId: string, userId: string) {
    const pronosticId = await this._resolvePronosticId(idOrMatchId);
    // Match sans pronostic publié : pas de fil de discussion, mais ce n'est pas
    // une erreur — on renvoie un fil vide plutôt qu'un 500.
    if (!pronosticId) {
      return { comments: [], vote: { userVote: null, agree: 0, disagree: 0, total: 0 } };
    }

    const [comments, userVote, voteCounts] = await Promise.all([
      prisma.comment.findMany({
        where:   { pronosticId, parentId: null },
        include: {
          user:    { select: { pseudo: true, avatarUrl: true } },
          replies: {
            include: { user: { select: { pseudo: true, avatarUrl: true } } },
            orderBy: { createdAt: 'asc' },
          },
        },
        orderBy: { createdAt: 'desc' },
        take:    50,
      }),
      prisma.pronosticVote.findUnique({
        where: { pronosticId_userId: { pronosticId, userId } },
      }),
      prisma.pronosticVote.groupBy({
        by:    ['type'],
        where: { pronosticId },
        _count: { type: true },
      }),
    ]);

    const agree    = voteCounts.find(v => v.type === 'AGREE')?._count.type ?? 0;
    const disagree = voteCounts.find(v => v.type === 'DISAGREE')?._count.type ?? 0;

    return {
      comments: comments.map(c => this._formatComment(c)),
      vote: {
        userVote:  userVote?.type ?? null,
        agree,
        disagree,
        total: agree + disagree,
      },
    };
  }

  // ─── Poster un commentaire ────────────────────────────────────────────────────
  async postComment(idOrMatchId: string, userId: string, content: string, parentId?: string) {
    if (!content?.trim() || content.trim().length < 3) {
      throw new Error('Le commentaire est trop court.');
    }
    if (content.trim().length > 500) {
      throw new Error('Le commentaire ne peut pas dépasser 500 caractères.');
    }

    const pronosticId = await this._resolvePronosticId(idOrMatchId);
    if (!pronosticId) throw new Error('Pronostic introuvable.');

    const comment = await prisma.comment.create({
      data: {
        pronosticId,
        userId,
        content: content.trim(),
        parentId: parentId ?? null,
      },
      include: {
        user:    { select: { pseudo: true, avatarUrl: true } },
        replies: { include: { user: { select: { pseudo: true, avatarUrl: true } } } },
      },
    });

    return this._formatComment(comment);
  }

  // ─── Réponse d'expert (admin) ─────────────────────────────────────────────────
  async postExpertReply(idOrMatchId: string, adminId: string, content: string, parentId: string) {
    const admin = await prisma.admin.findUnique({ where: { id: adminId } });
    if (!admin) throw new Error('Expert introuvable.');

    const pronosticId = await this._resolvePronosticId(idOrMatchId);
    if (!pronosticId) throw new Error('Pronostic introuvable.');

    // On crée un faux commentaire marqué isExpert = true
    const comment = await prisma.comment.create({
      data: {
        pronosticId,
        userId:   (await this._getOrCreateExpertUser()).id,
        content:  content.trim(),
        parentId,
        isExpert: true,
      },
      include: {
        user:    { select: { pseudo: true, avatarUrl: true } },
        replies: { include: { user: { select: { pseudo: true, avatarUrl: true } } } },
      },
    });

    return this._formatComment(comment);
  }

  // ─── Voter sur un pronostic ───────────────────────────────────────────────────
  async vote(idOrMatchId: string, userId: string, type: 'AGREE' | 'DISAGREE') {
    const pronosticId = await this._resolvePronosticId(idOrMatchId);
    if (!pronosticId) throw new Error('Pronostic introuvable.');

    const existing = await prisma.pronosticVote.findUnique({
      where: { pronosticId_userId: { pronosticId, userId } },
    });

    if (existing) {
      if (existing.type === type) {
        // Retirer le vote (toggle off)
        await prisma.pronosticVote.delete({
          where: { pronosticId_userId: { pronosticId, userId } },
        });
      } else {
        // Changer de vote
        await prisma.pronosticVote.update({
          where: { pronosticId_userId: { pronosticId, userId } },
          data:  { type },
        });
      }
    } else {
      await prisma.pronosticVote.create({ data: { pronosticId, userId, type } });
    }

    const counts = await prisma.pronosticVote.groupBy({
      by:    ['type'],
      where: { pronosticId },
      _count: { type: true },
    });

    const agree    = counts.find(v => v.type === 'AGREE')?._count.type ?? 0;
    const disagree = counts.find(v => v.type === 'DISAGREE')?._count.type ?? 0;
    const newVote  = await prisma.pronosticVote.findUnique({
      where: { pronosticId_userId: { pronosticId, userId } },
    });

    return { userVote: newVote?.type ?? null, agree, disagree, total: agree + disagree };
  }

  // ─── Supprimer un commentaire (auteur uniquement) ─────────────────────────────
  async deleteComment(commentId: string, userId: string) {
    const comment = await prisma.comment.findUnique({ where: { id: commentId } });
    if (!comment) throw new Error('Commentaire introuvable.');
    if (comment.userId !== userId) throw new Error('Action non autorisée.');
    await prisma.comment.delete({ where: { id: commentId } });
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────────
  private _formatComment(c: any) {
    return {
      id:         c.id,
      userId:     c.userId,
      content:    c.content,
      isExpert:   c.isExpert,
      parentId:   c.parentId,
      createdAt:  c.createdAt,
      user: {
        pseudo:    c.user.pseudo,
        avatarUrl: c.user.avatarUrl ?? null,
      },
      replies: (c.replies ?? []).map((r: any) => ({
        id:        r.id,
        userId:    r.userId,
        content:   r.content,
        isExpert:  r.isExpert,
        parentId:  r.parentId,
        createdAt: r.createdAt,
        user: {
          pseudo:    r.user.pseudo,
          avatarUrl: r.user.avatarUrl ?? null,
        },
      })),
    };
  }

  private async _getOrCreateExpertUser() {
    const EXPERT_EMAIL = 'expert@pronowin.internal';
    let user = await prisma.user.findUnique({ where: { email: EXPERT_EMAIL } });
    if (!user) {
      user = await prisma.user.create({
        data: {
          email:        EXPERT_EMAIL,
          pseudo:       'Expert PronoWin',
          referralCode: 'EXPERT00',
          isActive:     true,
        },
      });
    }
    return user;
  }
}
