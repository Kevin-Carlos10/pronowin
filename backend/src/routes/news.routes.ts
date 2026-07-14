import { Router, Request, Response } from 'express';
import fs   from 'fs';
import path from 'path';
import https from 'https';
import http  from 'http';
import { fetchRssNews } from '../services/rss.service';

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

// ─── Proxy image (contourne les restrictions CDN côté client mobile) ──────────
const ALLOWED_HOSTS = ['images.bfmtv.com'];

router.get('/image-proxy', (req: Request, res: Response) => {
  const raw = req.query.url as string | undefined;
  if (!raw) return res.status(400).end();

  let target: URL;
  try { target = new URL(raw); } catch { return res.status(400).end(); }

  if (!ALLOWED_HOSTS.includes(target.hostname)) {
    return res.status(403).end();
  }

  const referer = target.hostname.includes('bfmtv')
    ? 'https://rmcsport.bfmtv.com/'
    : 'https://www.bbc.com/';

  const lib = target.protocol === 'https:' ? https : http;
  const reqOpts = {
    hostname: target.hostname,
    path:     target.pathname + target.search,
    headers:  {
      'Referer':    referer,
      'User-Agent': 'Mozilla/5.0 (compatible; PronoWinApp/1.0)',
    },
  };

  const MAX_SIZE = 5 * 1024 * 1024; // 5 Mo max

  const proxyReq = lib.get(reqOpts, (upstream) => {
    const ct = upstream.headers['content-type'] ?? 'image/jpeg';
    if (!ct.startsWith('image/')) { upstream.destroy(); return res.status(400).end(); }

    const contentLength = parseInt(upstream.headers['content-length'] ?? '0', 10);
    if (contentLength > MAX_SIZE) { upstream.destroy(); return res.status(413).end(); }

    res.setHeader('Content-Type', ct);
    res.setHeader('Cache-Control', 'public, max-age=3600');

    let received = 0;
    upstream.on('data', (chunk: Buffer) => {
      received += chunk.length;
      if (received > MAX_SIZE) { upstream.destroy(); res.destroy(); }
    });
    upstream.pipe(res);
  });
  proxyReq.setTimeout(8000, () => { proxyReq.destroy(); res.status(504).end(); });
  proxyReq.on('error', () => { if (!res.headersSent) res.status(502).end(); });
});

// GET /api/v1/actualites — articles admin épinglés + flux RSS fusionnés
router.get('/', async (_req: Request, res: Response) => {
  // 1. Articles admin publiés
  const adminArticles = loadNews()
    .filter((a: any) => a.isPublished)
    .map((a: any) => ({
      id:         a.id,
      titre:      a.title,
      resume:     (a.summary || a.content || '').slice(0, 300),
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
  const mixed = [...unpinned, ...filteredRss].sort(
    (a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
  );

  const result = [...pinned, ...mixed].slice(0, 20);
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
