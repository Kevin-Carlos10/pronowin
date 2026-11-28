import Parser from 'rss-parser';
import { extraitTexte } from '../utils/extrait';

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

/**
 * L'image que le média joint lui-même à l'article dans son flux.
 *
 * Servie telle quelle, à son adresse d'origine : leur CDN la donne à toute
 * requête (vérifié le 20 octobre 2026, sans Referer comme avec un autre).
 * L'en-tête usurpé qu'ajoutaient le relais du serveur et l'application
 * n'était donc pas nécessaire ; il a disparu, les images reviennent.
 */
export function imageDuFlux(item: any): string | null {
  const url = (item?.enclosure?.url && String(item.enclosure.type ?? '').startsWith('image'))
    ? item.enclosure.url
    : item?.['media:thumbnail']?.$?.url ?? item?.['media:content']?.$?.url ?? null;
  return typeof url === 'string' && url.startsWith('https://') ? url : null;
}

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

export async function fetchRssNews(): Promise<RssArticle[]> {
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
          resume:     extraitTexte(item.contentSnippet ?? item.content),
          categorie:  feed.label,
          emoji:      feed.emoji,
          image_url:  imageDuFlux(item),
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
