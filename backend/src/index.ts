import 'dotenv/config';
import { prisma } from './lib/prisma';
import express from 'express';
import jwt from 'jsonwebtoken';
import logger from './utils/logger';
import cors from 'cors';
import helmet from 'helmet';
import morgan from 'morgan';
import rateLimit from 'express-rate-limit';
import compression from 'compression';
import axios from 'axios';

import authRoutes            from './routes/auth.routes';
import { PronosticsService } from './services/pronostics.service';
import { SubscriptionService } from './services/subscription.service';
import pronosticsRoutes      from './routes/pronostics.routes';
import paymentRoutes         from './routes/payment.routes';
import subscriptionRoutes    from './routes/subscription.routes';
import referralRoutes        from './routes/referral.routes';
import tutorialRoutes        from './routes/tutorial.routes';
import notificationRoutes    from './routes/notification.routes';
import notificationAdminRoutes    from './routes/notification_admin.routes';
import profileRoutes         from './routes/profile.routes';
import adminRoutes           from './routes/admin.routes';
import usersAdminRoutes      from './routes/users_admin.routes';
import paymentHistoryRoutes  from './routes/payment_history.routes';
import statsRoutes          from './routes/stats.routes';
import tutorialAdminRoutes   from './routes/tutorial_admin.routes';
import newsRoutes            from './routes/news.routes';
import configRoutes          from './routes/config.routes';
import favoritesRoutes       from './routes/favorites.routes';
import bankrollRoutes        from './routes/bankroll.routes';
import commentsRoutes        from './routes/comments.routes';
import leaderboardRoutes     from './routes/leaderboard.routes';

const app  = express();
const PORT = process.env.PORT ?? 3000;

/**
 * Un seul intermédiaire de confiance : nginx.
 *
 * Sans ce réglage, `req.ip` vaut l'adresse du proxy — la même pour tout le
 * monde. Or c'est la clé de tous les limiteurs de débit ci-dessous, et le plus
 * strict autorise **trois demandes d'OTP par dix minutes**. Trois personnes
 * demandaient un code, la quatrième était bloquée : pas la quatrième depuis la
 * même adresse, la quatrième de toute l'application.
 *
 * `express-rate-limit` le signalait à chaque requête
 * (`ERR_ERL_UNEXPECTED_X_FORWARDED_FOR`), dans un journal d'erreurs que
 * personne ne lisait.
 *
 * La valeur `1` et non `true` : elle dit « fais confiance au dernier maillon,
 * pas à la chaîne entière ». Avec `true`, n'importe qui pourrait usurper une
 * adresse en envoyant son propre en-tête `X-Forwarded-For` et contourner les
 * limiteurs — le remède serait pire que le mal.
 */
app.set('trust proxy', 1);

app.use(helmet());
const allowedOrigins = process.env.ALLOWED_ORIGINS
  ? process.env.ALLOWED_ORIGINS.split(',').map(o => o.trim())
  : (process.env.NODE_ENV === 'production' ? [] : ['http://localhost:4000']);
app.use(cors({ origin: allowedOrigins, credentials: true }));
app.use(express.json({ limit: '10mb' }));
app.use(morgan(process.env.NODE_ENV === 'production' ? 'combined' : 'dev', {
  stream: { write: (msg: string) => logger.http(msg.trim()) },
  // En production : ne logger que les erreurs (4xx/5xx) pour réduire le bruit
  skip: (_req, res) => process.env.NODE_ENV === 'production' && res.statusCode < 400,
}));
// Compression gzip/brotli — réduit la taille des réponses JSON de ~70%
app.use(compression());

// ── Rate limiting ─────────────────────────────────────────────────────────────
// Clé par IP + userId (quand le JWT est présent) pour éviter qu'un user change d'IP
const keyGenerator = (req: express.Request) => {
  const authHeader = req.headers['authorization'];
  if (authHeader?.startsWith('Bearer ')) {
    try {
      // Utiliser jwt.decode (sans vérifier la signature) uniquement pour le rate-limiting
      // La vérification de signature se fait dans authMiddleware
      const token   = authHeader.split(' ')[1];
      const decoded = jwt.decode(token) as { userId?: string } | null;
      if (decoded?.userId) return `user:${decoded.userId}`;
    } catch (_) { /* token malformé → fallback IP */ }
  }
  return req.ip ?? 'unknown';
};

const globalLim = rateLimit({
  windowMs: 900000, max: 1000,
  keyGenerator,
  message: { message: 'Trop de requêtes.' },
});
const otpLim = rateLimit({
  windowMs: 600000, max: 3,
  keyGenerator,
  message: { message: 'Trop de demandes OTP.' },
});
// login/register n'ont aucune protection anti brute-force applicative (contrairement
// aux flux OTP qui ont déjà _checkOtpBrute côté contrôleur) — limite dédiée par IP.
const authLim = rateLimit({
  windowMs: 900000, max: 10,
  keyGenerator,
  message: { message: 'Trop de tentatives. Réessayez plus tard.' },
});
const payLim = rateLimit({
  windowMs: 60000, max: 10,
  keyGenerator,
  message: { message: 'Trop de tentatives.' },
});
// Rate limit strict par IP sur les endpoints publics sensibles (évite scraping)
const publicLim = rateLimit({
  windowMs: 60000, max: 30,
  message: { message: 'Trop de requêtes.' },
});
app.use(globalLim);

app.get('/health', (_, res) => res.json({ status: 'ok', app: 'PronoWin API', version: '1.0.0', timestamp: new Date().toISOString() }));

// ── Deep links verification files ─────────────────────────────────────────────
// Android App Links : https://pronowin.app/.well-known/assetlinks.json
app.get('/.well-known/assetlinks.json', (_req, res) => {
  res.setHeader('Content-Type', 'application/json');
  res.json([{
    relation: ['delegate_permission/common.handle_all_urls'],
    target: {
      namespace:              'android_app',
      package_name:           'com.pronowin.app',
      // SHA-256 du keystore de production (à remplacer avant la mise en prod)
      // Pour debug : 6A:41:18:45:7F:B1:80:B8:4C:BC:4F:4D:A8:37:83:E1:0B:A5:1D:6E:FA:19:1C:F0:75:9F:CB:9A:7B:BB:6A:5C
      sha256_cert_fingerprints: [
        '6A:41:18:45:7F:B1:80:B8:4C:BC:4F:4D:A8:37:83:E1:0B:A5:1D:6E:FA:19:1C:F0:75:9F:CB:9A:7B:BB:6A:5C',
      ],
    },
  }]);
});

// iOS Universal Links : https://pronowin.app/.well-known/apple-app-site-association
app.get('/.well-known/apple-app-site-association', (_req, res) => {
  res.setHeader('Content-Type', 'application/json');
  // Remplacer TEAMID par l'identifiant d'équipe Apple Developer (10 caractères)
  // Visible sur https://developer.apple.com/account → Membership → Team ID
  const TEAM_ID = process.env.APPLE_TEAM_ID ?? 'XXXXXXXXXX';
  res.json({
    applinks: {
      apps: [],
      details: [{
        appID:  `${TEAM_ID}.com.pronowin.app`,
        paths:  ['/pronostics/*', '/tutoriels/*', '/parrainage/*', '/*'],
      }],
    },
    webcredentials: {
      apps: [`${TEAM_ID}.com.pronowin.app`],
    },
  });
});

// ── Image proxy (logos équipes depuis crests.football-data.org) ───────────────
app.get('/api/img', async (req, res) => {
  const url = req.query.url as string | undefined;
  if (!url || !url.startsWith('https://crests.football-data.org/')) {
    return res.status(400).json({ message: 'URL invalide.' });
  }
  try {
    const upstream = await axios.get(url, {
      responseType: 'arraybuffer',
      headers: { 'User-Agent': 'PronoWin/1.0' },
      timeout: 8000,
    });
    const ct = String(upstream.headers['content-type'] ?? 'image/svg+xml');
    res.setHeader('Content-Type', ct);
    res.setHeader('Cache-Control', 'public, max-age=86400');
    res.send(Buffer.from(upstream.data));
  } catch {
    res.status(502).end();
  }
});

const v1 = '/api/v1';
app.use(`${v1}/auth/send-otp`,       otpLim);
// `/login` et `/register` ont été supprimées ; le code par e-mail est le seul
// chemin d'entrée et il passe déjà par `otpLim` côté envoi et par le
// compteur anti-force-brute côté vérification.
app.use(`${v1}/auth/verify-email-otp`, authLim);
app.use(`${v1}/auth`,                authRoutes);
app.use(`${v1}/profile`,             profileRoutes);
app.use(`${v1}/admin`,               adminRoutes);
app.use(`${v1}/pronostics`,          pronosticsRoutes);
app.use(`${v1}/comments`,            commentsRoutes);
app.use(`${v1}/payments`,            payLim, paymentRoutes);
app.use(`${v1}/subscriptions`,       subscriptionRoutes);
app.use(`${v1}/referral`,            referralRoutes);
app.use(`${v1}/tutorials`,           tutorialRoutes);
app.use(`${v1}/notifications`,       notificationRoutes);
app.use(`${v1}/admin/notifications`, notificationAdminRoutes);
app.use(`${v1}/admin/users`,         usersAdminRoutes);
app.use(`${v1}/admin/history`,       paymentHistoryRoutes);
app.use(`${v1}/admin/stats`,       statsRoutes);
app.use(`${v1}/admin/tutorials`,     tutorialAdminRoutes);
app.use(`${v1}/actualites`,          publicLim, newsRoutes);
app.use(`${v1}/config`,              publicLim, configRoutes);
app.use(`${v1}/favorites`,           favoritesRoutes);
app.use(`${v1}/bankroll`,            bankrollRoutes);
app.use(`${v1}/leaderboard`,         leaderboardRoutes);

app.use((req, res) => res.status(404).json({ message: `Route introuvable : ${req.method} ${req.path}` }));
app.use((err: Error, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  logger.error('[ERROR]', { message: err.message, stack: err.stack });
  res.status(500).json({ message: 'Erreur interne.' });
});

app.listen(PORT, () => {
  logger.info(`PronoWin API démarrée — port ${PORT}`);
  logger.info('admin/tutorials actif');

  // ─── SYNC AUTOMATIQUE DES SCORES ──────────────────────────────────────────
  // Lance une 1ère sync immédiate au démarrage, puis toutes les 5 minutes.
  // Ne tourne que si la clé API est configurée.
  if (process.env.API_FOOTBALL_KEY) {
    const pronoSvc = new PronosticsService();

    // Sync intelligente : 30s si matchs LIVE, 2min sinon — 24h/24. Des matchs
    // (Amériques, Asie...) sont live en dehors de la plage 5h-23h UTC qu'on
    // excluait avant ; avec la marge de quota dégagée par le throttle du
    // filet de sécurité, plus besoin de ce blackout.
    const runSync = async () => {
      pronoSvc.syncMatchScores().catch((err: Error) =>
        logger.error('[ScoreSync] Erreur', { message: err.message }));
    };

    const scheduleLiveSync = async () => {
      const liveCount = await prisma.match.count({ where: { status: 'LIVE' } }).catch(() => 0);
      return liveCount > 0 ? 30_000 : 2 * 60 * 1000;
    };

    // Boucle adaptative : re-planifie selon présence de matchs LIVE
    const adaptiveSync = async () => {
      await runSync();
      const delay = await scheduleLiveSync();
      setTimeout(adaptiveSync, delay);
    };

    setTimeout(adaptiveSync, 30_000);
    logger.info('Score sync actif — 30s si LIVE, 2min sinon (24h/24)');

    const runMatchSoon = () => {
      const hour = new Date().getUTCHours();
      if (hour < 5 || hour > 23) return;
      pronoSvc.checkMatchesSoon().then(({ notified }) => {
        if (notified > 0) logger.info(`[MatchSoon] ${notified} notification(s) envoyée(s)`);
      }).catch(err => logger.error('[MatchSoon] Erreur', { message: err.message }));
    };
    setTimeout(runMatchSoon, 60_000);
    setInterval(runMatchSoon, 15 * 60 * 1000);
    logger.info('Notif "match bientôt" actif — toutes les 15 min');

    // Rappel d'expiration Premium (J-7, J-3, J-1). L'interrupteur
    // « Abonnement Premium » des Paramètres annonçait cette notification alors
    // qu'aucun job ne la produisait. Une fois par jour : l'idempotence des
    // paliers suppose exactement une exécution quotidienne.
    const subSvc = new SubscriptionService();
    const runExpiryReminder = () => {
      subSvc.notifyExpiringSubscriptions().then(({ notified }) => {
        if (notified > 0) logger.info(`[PremiumExpiry] ${notified} rappel(s) envoyé(s)`);
      }).catch(err => logger.error('[PremiumExpiry] Erreur', { message: err.message }));
    };
    setTimeout(runExpiryReminder, 120_000);
    setInterval(runExpiryReminder, 24 * 60 * 60 * 1000);
    logger.info('Rappel expiration Premium actif — 1×/jour (J-7, J-3, J-1)');
  } else {
    logger.warn('FOOTBALL_DATA_API_KEY manquante — score sync désactivé');
  }
});
