
import { prisma } from '../lib/prisma';

// Tutoriels par défaut (seed) — chargés si la table est vide
const DEFAULT_TUTORIALS = [
  {
    id: 'tut_001', title: 'Comprendre le Value Bet : identifier les cotes sous-évaluées',
    description: 'Le Value Bet est la stratégie la plus rentable sur le long terme. Apprenez à calculer la valeur réelle d\'une cote et à détecter quand le bookmaker sous-estime une équipe.',
    level: 'beginner', category: 'valuebet', durationSeconds: 720,
    isPremium: false, viewCount: 4823, rating: 4.7, authorName: 'Expert PronoWin',
  },
  {
    id: 'tut_002', title: 'Bankroll Management : protéger et faire croître votre capital',
    description: 'La règle d\'or : ne jamais miser plus de 2-5% de votre bankroll sur un seul pari. Découvrez les méthodes Kelly, Flat et Fixed.',
    level: 'beginner', category: 'bankroll', durationSeconds: 540,
    isPremium: false, viewCount: 3201, rating: 4.9, authorName: 'Expert PronoWin',
  },
  {
    id: 'tut_003', title: 'Analyse des statistiques avancées : xG, possession et pressing',
    description: 'Les buts attendus (xG) révolutionnent l\'analyse foot. Apprenez à utiliser ces métriques pour anticiper les résultats.',
    level: 'intermediate', category: 'analyse', durationSeconds: 1080,
    isPremium: true, viewCount: 1847, rating: 4.8, authorName: 'Expert PronoWin',
  },
  {
    id: 'tut_004', title: 'Psychologie du parieur : éviter les biais cognitifs',
    description: 'Le biais de confirmation, l\'effet de récence, le gambling fallacy... Apprenez à prendre des décisions rationnelles.',
    level: 'intermediate', category: 'psychologie', durationSeconds: 660,
    isPremium: false, viewCount: 2156, rating: 4.6, authorName: 'Expert PronoWin',
  },
  {
    id: 'tut_005', title: 'Stratégie des handicaps asiatiques',
    description: 'Les handicaps asiatiques éliminent le match nul et offrent de meilleures cotes. Maîtrisez cette technique avancée.',
    level: 'advanced', category: 'strategie', durationSeconds: 900,
    isPremium: true, viewCount: 987, rating: 4.9, authorName: 'Expert PronoWin',
  },
];

export class TutorialAdminService {

  /** Liste tous les tutoriels avec filtres */
  async getAll(params: { search?: string; category?: string; level?: string; page: number; perPage: number }) {
    const { search, category, level, page, perPage } = params;

    const where: any = {};
    if (search) {
      where.OR = [
        { title:      { contains: search, mode: 'insensitive' } },
        { description:{ contains: search, mode: 'insensitive' } },
        { authorName: { contains: search, mode: 'insensitive' } },
      ];
    }
    if (category) where.category = category;
    if (level)    where.level    = level;

    try {
      const [items, total] = await Promise.all([
        prisma.tutorial.findMany({
          where, orderBy: { createdAt: 'desc' },
          skip: (page - 1) * perPage, take: perPage,
        }),
        prisma.tutorial.count({ where }),
      ]);
      return { data: items, total, page, total_pages: Math.ceil(total / perPage) };
    } catch (_) {
      // Table vide ou inexistante → retourner les défauts
      return {
        data:        DEFAULT_TUTORIALS.slice((page - 1) * perPage, page * perPage),
        total:       DEFAULT_TUTORIALS.length,
        page,
        total_pages: Math.ceil(DEFAULT_TUTORIALS.length / perPage),
      };
    }
  }

  /** Détail d'un tutoriel */
  async getOne(id: string) {
    const t = await prisma.tutorial.findUnique({ where: { id } });
    if (!t) throw new Error('Tutoriel introuvable.');
    return t;
  }

  /** Créer un tutoriel */
  async create(data: {
    title:           string;
    description:     string;
    level:           string;
    category:        string;
    authorName?:     string;
    durationSeconds?: number;
    isPremium?:      boolean;
    videoUrl?:       string;
    thumbnailUrl?:   string;
  }) {
    if (!data.title?.trim())       throw new Error('Titre requis.');
    if (!data.description?.trim()) throw new Error('Description requise.');
    if (!data.level)               throw new Error('Niveau requis.');
    if (!data.category)            throw new Error('Catégorie requise.');

    // Générer un ID unique
    const id = `tut_${Date.now()}`;

    return prisma.tutorial.create({
      data: {
        id,
        title:           data.title.trim(),
        description:     data.description.trim(),
        level:           data.level,
        category:        data.category,
        authorName:      data.authorName?.trim() ?? 'Expert PronoWin',
        durationSeconds: data.durationSeconds ?? 0,
        isPremium:       data.isPremium ?? false,
        hasVideo:        !!data.videoUrl,
        videoUrl:        data.videoUrl  ?? null,
        thumbnailUrl:    data.thumbnailUrl ?? null,
        viewCount:       0,
        rating:          0,
        publishedAt:     new Date(),
      },
    });
  }

  /** Modifier un tutoriel */
  async update(id: string, data: {
    title?:          string;
    description?:    string;
    level?:          string;
    category?:       string;
    authorName?:     string;
    durationSeconds?: number;
    isPremium?:      boolean;
    videoUrl?:       string;
    thumbnailUrl?:   string;
  }) {
    const existing = await prisma.tutorial.findUnique({ where: { id } });
    if (!existing) throw new Error('Tutoriel introuvable.');

    return prisma.tutorial.update({
      where: { id },
      data: {
        ...(data.title           ? { title:           data.title.trim()           } : {}),
        ...(data.description     ? { description:     data.description.trim()     } : {}),
        ...(data.level           ? { level:           data.level                  } : {}),
        ...(data.category        ? { category:        data.category               } : {}),
        ...(data.authorName      ? { authorName:      data.authorName.trim()      } : {}),
        ...(data.durationSeconds !== undefined ? { durationSeconds: data.durationSeconds } : {}),
        ...(data.isPremium       !== undefined ? { isPremium:   data.isPremium        } : {}),
        ...(data.videoUrl        !== undefined ? { videoUrl:    data.videoUrl, hasVideo: !!data.videoUrl } : {}),
        ...(data.thumbnailUrl    !== undefined ? { thumbnailUrl: data.thumbnailUrl    } : {}),
      },
    });
  }

  /** Supprimer un tutoriel */
  async delete(id: string) {
    const existing = await prisma.tutorial.findUnique({ where: { id } });
    if (!existing) throw new Error('Tutoriel introuvable.');
    await prisma.tutorial.delete({ where: { id } });
    return { success: true };
  }

  /** Toggle Premium */
  async togglePremium(id: string) {
    const t = await prisma.tutorial.findUnique({ where: { id } });
    if (!t) throw new Error('Tutoriel introuvable.');
    return prisma.tutorial.update({ where: { id }, data: { isPremium: !t.isPremium } });
  }

  /** Stats */
  async getStats() {
    try {
      const [total, premium, beginner, intermediate, advanced] = await Promise.all([
        prisma.tutorial.count(),
        prisma.tutorial.count({ where: { isPremium: true } }),
        prisma.tutorial.count({ where: { level: 'beginner' } }),
        prisma.tutorial.count({ where: { level: 'intermediate' } }),
        prisma.tutorial.count({ where: { level: 'advanced' } }),
      ]);
      return { total, premium, free: total - premium, beginner, intermediate, advanced };
    } catch (_) {
      return { total: DEFAULT_TUTORIALS.length, premium: 2, free: 3, beginner: 2, intermediate: 2, advanced: 1 };
    }
  }

  /** Seed — insérer les tutoriels par défaut si table vide */
  async seed() {
    try {
      const count = await prisma.tutorial.count();
      if (count > 0) return { message: 'Tutoriels déjà présents.', count };

      for (const t of DEFAULT_TUTORIALS) {
        await prisma.tutorial.upsert({
          where:  { id: t.id },
          update: {},
          create: { ...t, hasVideo: false, publishedAt: new Date() },
        });
      }
      return { message: `${DEFAULT_TUTORIALS.length} tutoriels insérés.`, count: DEFAULT_TUTORIALS.length };
    } catch (e: any) {
      throw new Error(`Erreur seed: ${e.message}`);
    }
  }
}
