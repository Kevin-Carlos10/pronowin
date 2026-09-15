
import { prisma } from '../lib/prisma';

// Le catalogue de démonstration a été retiré.
//
// Il servait de repli « si la table est vide ou inexistante ». La table vide
// n'y passait jamais — elle rend `[]`, qui est un état vide légitime. Le seul
// cas où il sortait était donc une **panne** : l'utilisateur recevait alors un
// catalogue qui n'est pas le nôtre, portant d'autres identifiants, à la place
// des quatre tutoriels réels — et personne n'était averti.
//
// Ses compteurs avaient déjà dû être corrigés une fois : 4 823 vues et 4,7
// étoiles inscrites en dur, pour une application qui comptait six comptes.
// Un repli qui doit être corrigé pour cesser de mentir vaut moins qu'une
// erreur franche.

export class TutorialService {

  private fmt(t: any, prog?: { isCompleted: boolean; watchedSeconds: number } | null) {
    return {
      id:               t.id,
      title:            t.title,
      description:      t.description,
      level:            t.level,
      category:         t.category,
      thumbnail_url:    t.thumbnailUrl    ?? t.thumbnail_url    ?? null,
      video_url:        t.videoUrl        ?? t.video_url        ?? null,
      article_content:  t.articleContent  ?? t.article_content  ?? null,
      duration_seconds: t.durationSeconds ?? t.duration_seconds ?? 0,
      is_premium:       t.isPremium       ?? t.is_premium       ?? false,
      has_video:        t.hasVideo        ?? t.has_video        ?? false,
      view_count:       t.viewCount       ?? t.view_count       ?? 0,
      rating:           t.rating          ?? 0,
      author_name:      t.authorName      ?? t.author_name      ?? null,
      published_at:     t.publishedAt     ?? t.published_at     ?? null,
      is_completed:     prog?.isCompleted    ?? false,
      watched_seconds:  prog?.watchedSeconds ?? 0,
    };
  }

  async getAll(params: { category?: string; level?: string; userId?: string }) {
    try {
      const where: any = {};
      if (params.category) where.category = params.category;
      if (params.level)    where.level    = params.level;

      const tutorials = await prisma.tutorial.findMany({
        where,
        orderBy: [{ isPremium: 'asc' }, { createdAt: 'desc' }],
      });

      // Charger le progress de l'utilisateur en une seule requête
      let progMap = new Map<string, { isCompleted: boolean; watchedSeconds: number }>();
      if (params.userId) {
        const progList = await prisma.tutorialProgress.findMany({
          where: { userId: params.userId, tutorialId: { in: tutorials.map(t => t.id) } },
          select: { tutorialId: true, isCompleted: true, watchedSeconds: true },
        });
        progMap = new Map(progList.map(p => [p.tutorialId, p]));
      }

      return tutorials.map(t => this.fmt(t, progMap.get(t.id) ?? null));

    } catch (e: any) {
      // Une panne de base ne se déguise pas en catalogue.
      //
      // Ce `catch` remplaçait silencieusement les tutoriels par ceux de
      // démonstration : l'utilisateur lisait un catalogue qui n'est pas le
      // nôtre — quatre tutoriels réels échangés contre d'autres, portant
      // d'autres identifiants — et personne n'était averti de la panne. Une
      // table vide, elle, rend `[]` sans passer par ici : c'est un état vide
      // légitime, et l'écran sait le dire.
      console.error('[Tutoriels] lecture du catalogue impossible :', e?.message);
      throw e;
    }
  }

  async getOne(id: string, userId?: string) {
    try {
      const t = await prisma.tutorial.findUnique({ where: { id } });
      // Un tutoriel supprimé ou un identifiant erroné rendait un tutoriel de
      // démonstration, qui ne figure dans aucune liste : l'utilisateur
      // ouvrait un contenu qu'il ne peut retrouver nulle part.
      if (!t) throw new Error('Tutoriel introuvable.');

      // Incrémenter vues (fire and forget)
      prisma.tutorial.update({ where: { id }, data: { viewCount: { increment: 1 } } }).catch(() => {});

      const prog = userId ? await prisma.tutorialProgress.findUnique({
        where:  { userId_tutorialId: { userId, tutorialId: id } },
        select: { isCompleted: true, watchedSeconds: true },
      }) : null;

      return this.fmt(t, prog);
    } catch (e: any) {
      // Même raison qu'au-dessus : un identifiant demandé doit rendre le
      // tutoriel demandé, ou un échec. Pas un autre tutoriel.
      console.error('[Tutoriels] lecture de %s impossible :', id, e?.message);
      throw e;
    }
  }

  async markProgress(userId: string, tutorialId: string, watchedSeconds: number, completed: boolean) {
    const now = new Date();
    return prisma.tutorialProgress.upsert({
      where:  { userId_tutorialId: { userId, tutorialId } },
      create: {
        userId, tutorialId, watchedSeconds,
        isCompleted: completed,
        completedAt: completed ? now : null,
      },
      update: {
        watchedSeconds,
        isCompleted: completed,
        completedAt: completed ? now : undefined,
        updatedAt:   now,
      },
    });
  }

  async getProgress(userId: string) {
    const list = await prisma.tutorialProgress.findMany({
      where:   { userId },
      include: { tutorial: { select: { id: true, title: true, category: true, level: true } } },
      orderBy: { updatedAt: 'desc' },
    });
    return list.map(p => ({
      tutorial_id:      p.tutorialId,
      is_completed:     p.isCompleted,
      watched_seconds:  p.watchedSeconds,
      completed_at:     p.completedAt,
      tutorial: {
        id:       p.tutorial.id,
        title:    p.tutorial.title,
        category: p.tutorial.category,
        level:    p.tutorial.level,
      },
    }));
  }
}
