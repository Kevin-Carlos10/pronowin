
import { prisma } from '../lib/prisma';

// Données de démo si la table est vide ou inexistante
const DEMO_TUTORIALS = [
  {
    id: 'tut_001', title: 'Comprendre le Value Bet',
    description: 'Le Value Bet est la stratégie la plus rentable. Apprenez à calculer la valeur réelle d\'une cote et détecter quand le bookmaker sous-estime une équipe.',
    level: 'beginner', category: 'valuebet', duration_seconds: 720,
    is_premium: false, view_count: 4823, rating: 4.7, author_name: 'Expert PronoWin',
    thumbnail_url: null, video_url: null, has_video: false,
    published_at: new Date().toISOString(),
  },
  {
    id: 'tut_002', title: 'Bankroll Management',
    description: 'La règle d\'or : ne jamais miser plus de 2-5% de votre bankroll sur un seul pari. Méthodes Kelly, Flat et Fixed.',
    level: 'beginner', category: 'bankroll', duration_seconds: 540,
    is_premium: false, view_count: 3201, rating: 4.9, author_name: 'Expert PronoWin',
    thumbnail_url: null, video_url: null, has_video: false,
    published_at: new Date().toISOString(),
  },
  {
    id: 'tut_003', title: 'Statistiques avancées : xG et pressing',
    description: 'Les buts attendus (xG) révolutionnent l\'analyse foot. Utilisez ces métriques pour anticiper les résultats.',
    level: 'intermediate', category: 'analyse', duration_seconds: 1080,
    is_premium: true, view_count: 1847, rating: 4.8, author_name: 'Expert PronoWin',
    thumbnail_url: null, video_url: null, has_video: false,
    published_at: new Date().toISOString(),
  },
  {
    id: 'tut_004', title: 'Psychologie du parieur',
    description: 'Évitez les biais cognitifs : biais de confirmation, effet de récence, gambling fallacy. Prenez des décisions rationnelles.',
    level: 'intermediate', category: 'psychologie', duration_seconds: 660,
    is_premium: false, view_count: 2156, rating: 4.6, author_name: 'Expert PronoWin',
    thumbnail_url: null, video_url: null, has_video: false,
    published_at: new Date().toISOString(),
  },
  {
    id: 'tut_005', title: 'Stratégie des handicaps asiatiques',
    description: 'Les handicaps asiatiques éliminent le match nul et offrent de meilleures cotes. Maîtrisez cette technique avancée.',
    level: 'advanced', category: 'strategie', duration_seconds: 900,
    is_premium: true, view_count: 987, rating: 4.9, author_name: 'Expert PronoWin',
    thumbnail_url: null, video_url: null, has_video: false,
    published_at: new Date().toISOString(),
  },
];

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

    } catch (_) {
      let demos = DEMO_TUTORIALS;
      if (params.category) demos = demos.filter(t => t.category === params.category);
      if (params.level)    demos = demos.filter(t => t.level    === params.level);
      return demos.map(t => this.fmt(t, null));
    }
  }

  async getOne(id: string, userId?: string) {
    try {
      const t = await prisma.tutorial.findUnique({ where: { id } });
      if (!t) {
        const demo = DEMO_TUTORIALS.find(d => d.id === id);
        if (!demo) throw new Error('Tutoriel introuvable.');
        return this.fmt(demo, null);
      }

      // Incrémenter vues (fire and forget)
      prisma.tutorial.update({ where: { id }, data: { viewCount: { increment: 1 } } }).catch(() => {});

      const prog = userId ? await prisma.tutorialProgress.findUnique({
        where:  { userId_tutorialId: { userId, tutorialId: id } },
        select: { isCompleted: true, watchedSeconds: true },
      }) : null;

      return this.fmt(t, prog);
    } catch (e: any) {
      const demo = DEMO_TUTORIALS.find(d => d.id === id);
      if (demo) return this.fmt(demo, null);
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
