/**
 * « Donne-nous ton avis » (8 novembre 2026), comme Sofascore.
 *
 * Un message, une capture d'écran facultative et la version de
 * l'application. Rien ne partait jusqu'ici que par e-mail, WhatsApp ou
 * Telegram : sans version ni capture, chaque signalement commençait par trois
 * questions. L'équipe les lit dans l'administration (page « Avis ») et les
 * marque traités.
 *
 * La capture va dans le dossier S3 privé « avis » : une capture d'écran du
 * téléphone montre souvent plus que ce qu'on voulait montrer. L'administration
 * la lit par une adresse signée qui expire.
 */
import { prisma } from '../lib/prisma';
import { ErreurMetier, ServiceIndisponible } from '../utils/erreurs';
import { journal } from '../utils/logger';

export const MESSAGE_MIN = 10;
export const MESSAGE_MAX = 2000;
/** Avis par compte (ou par invité, à l'adresse près) et par heure. */
export const AVIS_PAR_HEURE = 5;
const PAR_PAGE = 30;

// Import S3 différé, comme ailleurs : le module lit les identifiants AWS à
// son chargement, et l'API doit démarrer sans eux.
type StockageImages = {
  uploadImage(p: { base64: string; folder: string; userId: string }): Promise<string>;
  urlLectureSignee(url: string | null | undefined, dureeS?: number): Promise<string | null>;
};
let stockage: StockageImages | null = null;
/** Remplaçable pour les tests. */
export let lireStockage = async (): Promise<StockageImages | null> => {
  if (!stockage && process.env.AWS_ACCESS_KEY_ID && process.env.AWS_SECRET_ACCESS_KEY) {
    const { S3Service } = await import('./s3.service');
    stockage = new S3Service() as unknown as StockageImages;
  }
  return stockage;
};
export function remplacerStockage(f: () => Promise<StockageImages | null>): void { lireStockage = f; }

const EMAIL = /^[^\s@]{1,64}@[^\s@]{1,255}\.[^\s@]{2,63}$/;

export async function envoyerAvis(p: {
  userId?: string | null;
  email?: string | null;
  message: string;
  imageBase64?: string | null;
  plateforme?: string | null;
  versionApp?: string | null;
}): Promise<{ id: string }> {
  const message = (p.message ?? '').trim();
  if (message.length < MESSAGE_MIN) {
    throw new ErreurMetier(`Décris ton problème ou ta suggestion en ${MESSAGE_MIN} caractères au moins.`, 422);
  }
  if (message.length > MESSAGE_MAX) {
    throw new ErreurMetier(`${MESSAGE_MAX} caractères au plus.`, 422);
  }

  // L'adresse où répondre : celle du compte d'abord.
  let email = (p.email ?? '').trim().toLowerCase() || null;
  if (p.userId) {
    const compte = await prisma.user.findUnique({ where: { id: p.userId }, select: { email: true } });
    email = email ?? compte?.email ?? null;
  } else if (!email) {
    throw new ErreurMetier('Indique ton adresse e-mail pour qu’on puisse te répondre.', 422);
  }
  if (email && !EMAIL.test(email)) throw new ErreurMetier('Adresse e-mail invalide.', 422);

  const depuis = new Date(Date.now() - 3600_000);
  const recents = await prisma.avisUtilisateur.count({
    where: { creeLe: { gte: depuis }, ...(p.userId ? { userId: p.userId } : { email }) },
  });
  if (recents >= AVIS_PAR_HEURE) {
    throw new ErreurMetier('Merci, nous avons bien reçu tes messages. Réessaie dans une heure.', 429);
  }

  let captureUrl: string | null = null;
  if (p.imageBase64) {
    const s3 = await lireStockage();
    if (!s3) {
      throw new ServiceIndisponible('La capture ne peut pas être envoyée pour le moment. Envoie ton message sans elle.');
    }
    try {
      captureUrl = await s3.uploadImage({ base64: p.imageBase64, folder: 'avis', userId: p.userId ?? 'invite' });
    } catch (e: any) {
      // Un format refusé se dit tel quel ; une panne de S3, non.
      if (e instanceof ErreurMetier) throw e;
      journal.error('[Avis] Échec du dépôt de la capture', { message: e?.message });
      throw new ServiceIndisponible('La capture n’a pas pu être envoyée. Réessaie, ou envoie ton message sans elle.');
    }
  }

  const avis = await prisma.avisUtilisateur.create({
    data: {
      userId:     p.userId ?? null,
      email,
      message,
      captureUrl,
      plateforme: (p.plateforme ?? '').slice(0, 20) || null,
      versionApp: (p.versionApp ?? '').slice(0, 40) || null,
    },
    select: { id: true },
  });
  return avis;
}

export type FiltreAvis = 'nouveaux' | 'traites' | 'tous';
export const FILTRES_AVIS: FiltreAvis[] = ['nouveaux', 'traites', 'tous'];

/** La page « Avis » de l'administration : les plus récents d'abord. */
export async function listerAvisAdmin(p: { filtre: FiltreAvis; page: number }) {
  const where = p.filtre === 'nouveaux' ? { traite: false } : p.filtre === 'traites' ? { traite: true } : {};
  const page = Math.max(1, Math.min(p.page, 1000));
  const [total, nouveaux, lignes] = await Promise.all([
    prisma.avisUtilisateur.count({ where }),
    prisma.avisUtilisateur.count({ where: { traite: false } }),
    prisma.avisUtilisateur.findMany({
      where,
      orderBy: { creeLe: 'desc' },
      skip: (page - 1) * PAR_PAGE,
      take: PAR_PAGE,
      include: { user: { select: { id: true, pseudo: true } } },
    }),
  ]);
  const s3 = lignes.some(l => l.captureUrl) ? await lireStockage() : null;
  const avis = await Promise.all(lignes.map(async l => ({
    id:          l.id,
    message:     l.message,
    email:       l.email,
    plateforme:  l.plateforme,
    versionApp:  l.versionApp,
    traite:      l.traite,
    traiteLe:    l.traiteLe,
    creeLe:      l.creeLe,
    utilisateur: l.user ? { id: l.user.id, pseudo: l.user.pseudo } : null,
    aCapture:    !!l.captureUrl,
    // Adresse signée, valable dix minutes.
    capture:     l.captureUrl && s3 ? await s3.urlLectureSignee(l.captureUrl, 600).catch(() => null) : null,
  })));
  return { avis, total, nouveaux, page, pages: Math.max(1, Math.ceil(total / PAR_PAGE)) };
}

export async function marquerAvis(id: string, traite: boolean) {
  const existe = await prisma.avisUtilisateur.findUnique({ where: { id }, select: { id: true } });
  if (!existe) return null;
  return prisma.avisUtilisateur.update({
    where: { id },
    data:  { traite, traiteLe: traite ? new Date() : null },
    select: { id: true, traite: true, message: true },
  });
}

/** Le nombre d'avis non traités, pour le badge du menu. */
export async function compterAvisNouveaux(): Promise<number> {
  return prisma.avisUtilisateur.count({ where: { traite: false } });
}
