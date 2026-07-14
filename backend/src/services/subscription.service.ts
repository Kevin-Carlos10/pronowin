import { NotificationService } from './notification.service';
import { prisma } from '../lib/prisma';
import { ReferralService } from './referral.service';

// Import S3 de façon lazy pour éviter le crash si AWS pas configuré
let s3Svc: any = null;
async function getS3() {
  if (!s3Svc && process.env.AWS_ACCESS_KEY_ID && process.env.AWS_SECRET_ACCESS_KEY) {
    const { S3Service } = await import('./s3.service');
    s3Svc = new S3Service();
  }
  return s3Svc;
}

const notifSvc = new NotificationService();
const referralSvc = new ReferralService();

export const PREMIUM_PRICE_FCFA = parseInt(process.env.PREMIUM_PRICE_FCFA ?? '5000');
export const XBET_PROMO_CODE    = process.env.XBET_PROMO_CODE ?? 'PRONOWIN2025';

export class SubscriptionService {

  getPlans() {
    return [
      {
        id: 'free', type: 'free', name: 'Plan Gratuit',
        description: 'Pour découvrir PronoWin',
        price: 0, currency: 'FCFA', duration_days: 0, is_popular: false,
        features:        ['3 pronostics par jour', 'Tutoriels basiques', 'Notifications matchs'],
        locked_features: ['Pronostics VIP illimités', 'Statistiques avancées', 'Sans publicité'],
      },
      {
        id: 'premium', type: 'premium', name: 'Plan Premium',
        description: 'Accès total à tous les pronostics VIP',
        price:           PREMIUM_PRICE_FCFA,
        currency:        'FCFA',
        duration_days:   30,
        is_popular:      true,
        features:        ['Pronostics VIP illimités', 'Tous les tutoriels', 'Statistiques avancées', 'Sans publicité', 'Support prioritaire'],
        locked_features: [],
        xbet_promo_code: XBET_PROMO_CODE,
      },
    ];
  }

  /** Abonnement actuel — resilient aux erreurs */
  async getCurrentSubscription(userId: string) {
    try {
      const user = await prisma.user.findUnique({ where: { id: userId } });
      if (!user) throw new Error('Utilisateur introuvable.');

      let sub          = null;
      let pendingProof = null;

      // Chercher l'abonnement actif (table peut ne pas encore exister)
      try {
        sub = await prisma.subscription.findFirst({
          where:   { userId, endDate: { gt: new Date() } },
          orderBy: { endDate: 'desc' },
        });
      } catch (_) { /* Table pas encore créée */ }

      // Chercher une preuve en attente
      try {
        pendingProof = await prisma.subscriptionProof.findFirst({
          where:   { userId, status: 'pending' },
          orderBy: { createdAt: 'desc' },
        });
      } catch (_) { /* Table pas encore créée */ }

      const daysLeft = sub
        ? Math.ceil((sub.endDate.getTime() - Date.now()) / 86400000)
        : 0;

      return {
        plan:          user.subscriptionPlan ?? 'free',
        expires_at:    sub?.endDate?.toISOString() ?? null,
        days_left:     Math.max(0, daysLeft),    // toujours un int >= 0
        xbet_id:       user.xbetId ?? null,
        promo_code:    XBET_PROMO_CODE,
        premium_price: PREMIUM_PRICE_FCFA,       // toujours un int
        pending_proof: pendingProof ? {
          id:         pendingProof.id,
          type:       pendingProof.type,
          status:     pendingProof.status,
          created_at: pendingProof.createdAt.toISOString(),
        } : null,
      };
    } catch (e: any) {
      console.error('[SubscriptionService] getCurrentSubscription:', e.message);
      // Retourner un état par défaut plutôt que de crasher
      return {
        plan:          'free',
        expires_at:    null,
        days_left:     0,
        xbet_id:       null,
        promo_code:    XBET_PROMO_CODE,
        premium_price: PREMIUM_PRICE_FCFA,
        pending_proof: null,
        error:         e.message,
      };
    }
  }

  async getProofStatus(userId: string) {
    try {
      const proof = await prisma.subscriptionProof.findFirst({
        where:   { userId },
        orderBy: { createdAt: 'desc' },
      });
      if (!proof) return { status: 'none' };
      return {
        id:          proof.id,
        status:      proof.status,
        type:        proof.type,
        admin_note:  proof.adminNote,
        created_at:  proof.createdAt.toISOString(),
        reviewed_at: proof.reviewedAt?.toISOString() ?? null,
      };
    } catch (_) { return { status: 'none' }; }
  }

  async getUploadUrl(userId: string, mimeType: string) {
    const s3 = await getS3();
    if (!s3) throw new Error('AWS S3 non configuré. Ajoutez AWS_ACCESS_KEY_ID dans .env');
    return s3.getPresignedUrl({ folder: 'proofs', userId, mimeType, expiresIn: 300 });
  }

  async submitProof(params: {
    userId:         string;
    type:           'payment_screenshot' | 'xbet_account_screenshot';
    imageBase64?:   string;
    screenshotUrl?: string;
    xbetId?:        string;
    amount?:        number;
    senderPhone?:   string;
  }) {
    const { userId, type, imageBase64, xbetId, amount, senderPhone } = params;
    let screenshotUrl = params.screenshotUrl;

    // Vérifier preuve en attente
    try {
      const existing = await prisma.subscriptionProof.findFirst({
        where: { userId, status: 'pending' },
      });
      if (existing) throw new Error('Vous avez déjà une preuve en cours de vérification. Patientez.');
    } catch (e: any) {
      if (e.message.includes('en cours')) throw e;
      // Table pas encore créée → continuer
    }

    // Upload S3 si base64 fourni
    if (imageBase64 && !screenshotUrl) {
      const s3 = await getS3();
      if (s3) {
        try {
          screenshotUrl = await s3.uploadImage({ base64: imageBase64, folder: 'proofs', userId });
        } catch (e: any) {
          throw new Error(`Erreur upload image: ${e.message}`);
        }
      } else {
        // Sans S3 → stocker l'URL en placeholder (dev)
        screenshotUrl = `dev://proof/${userId}/${Date.now()}`;
        console.warn('[Subscription] S3 non configuré, URL placeholder utilisée');
      }
    }

    if (!screenshotUrl) throw new Error('Image requise.');

    if (type === 'payment_screenshot') {
      if (!amount || amount < PREMIUM_PRICE_FCFA)
        throw new Error(`Le montant doit être d'au moins ${PREMIUM_PRICE_FCFA} FCFA.`);
      if (!senderPhone) throw new Error('Numéro Mobile Money requis.');
    }
    if (type === 'xbet_account_screenshot') {
      if (!xbetId?.trim()) throw new Error('ID 1xBet requis.');
    }

    const proof = await prisma.subscriptionProof.create({
      data: { userId, type, screenshotUrl, xbetId: xbetId?.trim() ?? null, amount: amount ?? null, senderPhone: senderPhone ?? null, status: 'pending' },
    });

    if (xbetId) {
      await prisma.user.update({ where: { id: userId }, data: { xbetId: xbetId.trim() } }).catch(() => {});
    }

    return {
      proof_id:         proof.id,
      status:           'pending',
      estimated_review: type === 'payment_screenshot' ? '30 minutes ouvrables' : '2 heures ouvrables',
      message:          type === 'payment_screenshot'
        ? 'Preuve de paiement soumise. Validation sous 30 minutes.'
        : 'Preuve de compte 1xBet soumise. Validation sous 2 heures.',
    };
  }

  async getPendingProofs(page = 1, perPage = 20) {
    try {
      const [items, total] = await Promise.all([
        prisma.subscriptionProof.findMany({
          where: { status: 'pending' }, include: { user: { select: { pseudo: true, phoneNumber: true, xbetId: true } } },
          orderBy: { createdAt: 'asc' }, skip: (page - 1) * perPage, take: perPage,
        }),
        prisma.subscriptionProof.count({ where: { status: 'pending' } }),
      ]);
      return { data: items, total, page };
    } catch (_) { return { data: [], total: 0, page }; }
  }

  async reviewProof(params: { proofId: string; adminId: string; approved: boolean; adminNote?: string; durationDays?: number }) {
    const { proofId, adminId, approved, adminNote, durationDays = 30 } = params;
    const proof = await prisma.subscriptionProof.findUnique({ where: { id: proofId }, include: { user: true } });
    if (!proof)                    throw new Error('Preuve introuvable.');
    if (proof.status !== 'pending') throw new Error('Preuve déjà traitée.');

    if (approved) {
      const startDate = new Date();
      const endDate   = new Date(startDate.getTime() + durationDays * 86400000);
      const [sub] = await Promise.all([
        prisma.subscription.create({ data: { userId: proof.userId, plan: 'premium', amountPaid: proof.amount ?? 0, paymentMethod: proof.type === 'payment_screenshot' ? 'manual_mobcash' : 'xbet_promo', promoCodeUsed: proof.type === 'xbet_account_screenshot' ? XBET_PROMO_CODE : null, startDate, endDate } }),
        prisma.user.update({ where: { id: proof.userId }, data: { subscriptionPlan: 'premium', subscriptionExpiresAt: endDate } }),
        prisma.subscriptionProof.update({ where: { id: proofId }, data: { status: 'approved', adminNote, reviewedBy: adminId, reviewedAt: new Date() } }),
      ]);

      // ── DÉCLENCHER LES COMMISSIONS DE PARRAINAGE ──────────────────────────
      await referralSvc.triggerCommissions(proof.userId).catch(e =>
        console.error('[Parrainage] Erreur triggerCommissions:', e.message)
      );
      
      await notifSvc.sendToUser(proof.userId, { title: '🎉 Bienvenue Premium !', body: `Votre accès Premium est activé pour ${durationDays} jours !`, data: { deep_link: '/pronostics', type: 'system' } }).catch(() => {});
    } else {
      await prisma.subscriptionProof.update({ where: { id: proofId }, data: { status: 'rejected', adminNote, reviewedBy: adminId, reviewedAt: new Date() } });
      await notifSvc.sendToUser(proof.userId, { title: '❌ Preuve refusée', body: adminNote ?? 'Votre preuve n\'a pas pu être validée.', data: { deep_link: '/compte', type: 'system' } }).catch(() => {});
    }
    return { success: true, approved };
  }
}
