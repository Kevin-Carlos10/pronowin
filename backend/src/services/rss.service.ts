import Parser from 'rss-parser';

const parser = new Parser({
  timeout: 8000,
  customFields: {
    item: [
      ['media:thumbnail', 'media:thumbnail', { keepArray: false }],
      ['media:content',   'media:content',   { keepArray: false }],
      ['enclosure',       'enclosure'],
    ],
  },
});

// ─── Sources RSS football ─────────────────────────────────────────────────────
const RSS_FEEDS: { url: string; label: string; emoji: string; lang: string }[] = [
  {
    url:   'https://rmcsport.bfmtv.com/rss/football/',
    label: 'RMC Sport',
    emoji: '📻',
    lang:  'fr',
  },
];

// ─── Cache simple en mémoire (15 min) ────────────────────────────────────────
let _cache: RssArticle[] | null = null;
let _cacheAt = 0;
const CACHE_TTL = 15 * 60 * 1000;

export interface RssArticle {
  id:         string;
  titre:      string;
  resume:     string;
  categorie:  string;
  emoji:      string;
  image_url:  string | null;
  source_url: string | null;
  source:     string;
  date:       string;
  created_at: string;
  is_pinned:  boolean;
  from_rss:   boolean;
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

function extractImage(item: any): string | null {
  // RMC / BFMTV → enclosure.url
  if (item.enclosure?.url && item.enclosure.type?.startsWith('image')) {
    return item.enclosure.url;
  }
  // BBC Sport → media:thumbnail.$.url
  if (item['media:thumbnail']?.$?.url) {
    return item['media:thumbnail'].$.url;
  }
  // Générique media:content
  if (item['media:content']?.$?.url) {
    return item['media:content'].$.url;
  }
  // itunes
  if (item['itunes:image']?.$?.href) {
    return item['itunes:image'].$.href;
  }
  return null;
}

/**
 * Construit l'URL du proxy à partir de la requête entrante (protocole + host
 * réellement utilisés par le client) — jamais d'adresse en dur : un même
 * backend est joint différemment selon le contexte (10.0.2.2 en émulateur
 * Android, IP locale sur un vrai téléphone en dev, domaine en prod).
 */
export function proxyImage(url: string | null, baseUrl: string): string | null {
  if (!url) return null;
  return `${baseUrl}/api/v1/actualites/image-proxy?url=${encodeURIComponent(url)}`;
}

export async function fetchRssNews(): Promise<RssArticle[]> {
  // Le cache garde les URLs d'image BRUTES (pas encore proxées) — sinon les
  // liens de proxy resteraient figés sur le host du tout premier appelant
  // pendant 15 min, cassant les images pour tous les autres clients.
  if (_cache && Date.now() - _cacheAt < CACHE_TTL) return _cache;

  const results = await Promise.allSettled(
    RSS_FEEDS.map(async (feed) => {
      const parsed = await parser.parseURL(feed.url);
      return parsed.items.slice(0, 8).map((item): RssArticle => {
        const pubDate = item.pubDate ? new Date(item.pubDate) : new Date();
        const id      = `rss_${Buffer.from(item.link ?? item.title ?? '').toString('base64').slice(0, 16)}`;
        return {
          id,
          titre:      item.title ?? '',
          resume:     item.contentSnippet?.slice(0, 300) ?? item.content?.slice(0, 300) ?? '',
          categorie:  feed.label,
          emoji:      feed.emoji,
          image_url:  extractImage(item), // brut — proxé à la demande dans news.routes.ts
          source_url: item.link ?? null,
          source:     feed.label,
          date:       relTimeShort(pubDate),
          created_at: pubDate.toISOString(),
          is_pinned:  false,
          from_rss:   true,
        };
      });
    }),
  );

  const articles: RssArticle[] = [];
  for (const r of results) {
    if (r.status === 'fulfilled') articles.push(...r.value);
  }

  // Dédupliquer par titre (même article repris par plusieurs sources)
  const seen = new Set<string>();
  const deduped = articles.filter((a) => {
    const key = a.titre.toLowerCase().slice(0, 40);
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });

  // Trier par date décroissante
  deduped.sort((a, b) =>
    new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
  );

  // Un résultat vide (raté transitoire de toutes les sources) ne doit pas
  // écraser un cache valide précédent — sinon un seul blip réseau prive les
  // utilisateurs d'actualités pendant 15 minutes alors que le flux fonctionne.
  if (deduped.length > 0 || !_cache) {
    _cache   = deduped;
    _cacheAt = Date.now();
  }
  return deduped.length > 0 ? deduped : (_cache ?? []);
}

/** Invalide le cache (appelé si un admin publie un article) */
export function invalidateRssCache() {
  _cache = null;
}
