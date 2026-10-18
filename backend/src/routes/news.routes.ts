import { Router, Request, Response } from 'express';
import fs   from 'fs';
import path from 'path';
import { fetchRssNews } from '../services/rss.service';
import { resumesPourActualites } from '../services/resumes_match.service';
import { extraitTexte } from '../utils/extrait';

const router = Router();

const NEWS_FILE = path.join(__dirname, '../../../admin-web/data/actualites.json');

function loadNews(): any[] {
  try {
    if (!fs.existsSync(NEWS_FILE)) return [];
    return JSON.parse(fs.readFileSync(NEWS_FILE, 'utf8'));
  } catch {
    return [];
  }
}

function relTimeShort(d: Date): string {
  const diff = Date.now() - d.getTime();
  const m = Math.floor(diff / 60000);
  if (m < 60)   return m <= 1 ? "À l'instant" : `Il y a ${m} min`;
  const h = Math.floor(m / 60);
  if (h < 24)   return h === 1 ? 'Il y a 1h' : `Il y a ${h}h`;
  const days = Math.floor(h / 24);
  if (days === 1) return 'Hier';
  if (days < 7)  return `Il y a ${days}j`;
  return d.toLocaleDateString('fr-FR', { day: 'numeric', month: 'short' });
}

// ─── Plus de relais d'images ─────────────────────────────────────────────────
// Le serveur relayait les images de RMC Sport en se faisant passer pour leur
// site (en-tête Referer), pour contourner leur protection contre la reprise
// d'images. Dans une application commerciale, c'est un risque juridique : les
// articles des médias s'affichent désormais sans image (titre, source, lien
// vers l'article d'origine), comme Google Actualités (18 octobre 2026).
// L'adresse répond 410 aux versions de l'app qui l'ont encore en cache : elles
// affichent leur visuel de repli.
router.get('/image-proxy', (_req: Request, res: Response) => { res.status(410).end(); });

// GET /api/v1/actualites — articles admin épinglés, résumés de match et flux
// RSS, fusionnés
router.get('/', async (req: Request, res: Response) => {
  // 20 pour l'accueil ; la page Actualités de l'app en demande jusqu'à 50.
  const limite = Math.min(Math.max(parseInt(String(req.query.limite ?? '20')) || 20, 1), 50);
  // 1. Articles admin publiés
  const adminArticles = loadNews()
    .filter((a: any) => a.isPublished)
    .map((a: any) => ({
      id:         a.id,
      titre:      a.title,
      titre_en: a.titleEn ?? null, resume_en: a.summaryEn || a.contentEn ? extraitTexte(a.summaryEn || a.contentEn) : null,
      resume:     extraitTexte(a.summary || a.content),
      categorie:  a.category ?? 'news',
      emoji:      a.emoji ?? '📰',
      image_url:  a.imageUrl || null,
      source_url: a.sourceUrl || null,
      is_pinned:  a.isPinned ?? false,
      date:       relTimeShort(new Date(a.createdAt)),
      created_at: a.createdAt,
      from_rss:   false,
    }));

  // 2. Articles RSS (fire-and-forget si erreur réseau)
  let rssArticles: any[] = [];
  try {
    rssArticles = await fetchRssNews();
  } catch {
    // Réseau indisponible → on continue avec les articles admin seuls
  }

  // 2 bis. Résumés automatiques des matchs pronostiqués (resumes_match.service.ts)
  const resumes = (await resumesPourActualites(limite > 20 ? 20 : 8).catch(() => []))
    .map((r) => ({ ...r, date: relTimeShort(new Date(r.created_at)) }));

  // 3. Fusion : admin d'abord (épinglés en tête), puis RSS
  //    On retire du RSS les articles dont le titre est proche d'un article admin
  const adminTitles = new Set(
    adminArticles.map((a) => a.titre.toLowerCase().slice(0, 40))
  );
  const filteredRss = rssArticles.filter(
    (r) => !adminTitles.has(r.titre.toLowerCase().slice(0, 40))
  );

  const pinned    = adminArticles.filter((a) => a.is_pinned);
  const unpinned  = adminArticles.filter((a) => !a.is_pinned);

  // Mélange unpinned admin + RSS, trié par date
  const mixed = [...unpinned, ...resumes, ...filteredRss].sort(
    (a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
  );

  const result = [...pinned, ...mixed].slice(0, limite);
  res.json(result);
});

// GET /api/v1/actualites/:id — détail d'un article admin uniquement
router.get('/:id', (req: Request, res: Response) => {
  const all     = loadNews();
  const article = all.find((a: any) => a.id === req.params.id && a.isPublished);
  if (!article) return res.status(404).json({ message: 'Article introuvable.' });
  res.json({
    id:           article.id,
    titre:        article.title,
    titre_en: article.titleEn ?? null, resume_en: article.summaryEn ?? null, contenu_en: article.contentEn ?? null,
    resume:       article.summary || '',
    contenu:      article.content || '',
    categorie:    article.category ?? 'news',
    emoji:        article.emoji ?? '📰',
    image_url:    article.imageUrl || null,
    source_url:   article.sourceUrl || null,
    is_pinned:    article.isPinned ?? false,
    date:         relTimeShort(new Date(article.createdAt)),
    created_at:   article.createdAt,
    is_premium:   article.isPremiumOnly ?? false,
  });
});

export default router;
