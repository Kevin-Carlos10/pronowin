import { NotificationService } from './notification.service';
import { prisma } from '../lib/prisma';

const notifSvc = new NotificationService();

export const COMMISSION_L1 = parseInt(process.env.REFERRAL_COMMISSION_L1 ?? '500');
export const COMMISSION_L2 = parseInt(process.env.REFERRAL_COMMISSION_L2 ?? '200');
export const MIN_WITHDRAWAL = parseInt(process.env.REFERRAL_MIN_WITHDRAWAL ?? '2000');

export class ReferralService {

  /** Statistiques de parrainage d'un utilisateur */
  async getStats(userId: string) {
    const user = await prisma.user.findUnique({ where: { id: userId } });
    if (!user) throw new Error('Utilisateur introuvable.');

    const [l1Referrals, l2Referrals] = await Promise.all([
      prisma.referral.findMany({
        where:   { referrerId: userId, level: 1 },
        include: { referred: { select: { pseudo: true, phoneNumber: true, subscriptionPlan: true, createdAt: true } } },
        orderBy: { createdAt: 'desc' },
      }),
      prisma.referral.findMany({
        where:   { referrerId: userId, level: 2 },
        include: { referred: { select: { pseudo: true, subscriptionPlan: true, createdAt: true } } },
        orderBy: { createdAt: 'desc' },
      }),
    ]);

    const totalL1       = l1Referrals.length;
    const totalL2       = l2Referrals.length;
    const premiumL1     = l1Referrals.filter(r => r.referred.subscriptionPlan === 'premium').length;
    const premiumL2     = l2Referrals.filter(r => r.referred.subscriptionPlan === 'premium').length;
    const totalEarnings = user.referralEarnings;
    const canWithdraw   = totalEarnings >= MIN_WITHDRAWAL;

    return {
      referral_code:    user.referralCode,
      total_earnings:   totalEarnings,
      can_withdraw:     canWithdraw,
      min_withdrawal:   MIN_WITHDRAWAL,
      commission_l1:    COMMISSION_L1,
      commission_l2:    COMMISSION_L2,
      stats: {
        total_l1:   totalL1,
        premium_l1: premiumL1,
        total_l2:   totalL2,
        premium_l2: premiumL2,
        total_referrals: totalL1 + totalL2,
      },
      l1_referrals: l1Referrals.map(r => ({
        pseudo:       r.referred.pseudo,
        phone:        r.referred.phoneNumber,
        plan:         r.referred.subscriptionPlan,
        commission:   r.commissionAmount,
        is_paid:      r.isPaid,
        joined_at:    r.createdAt,
      })),
      l2_referrals: l2Referrals.map(r => ({
        pseudo:     r.referred.pseudo,
        plan:       r.referred.subscriptionPlan,
        commission: r.commissionAmount,
        is_paid:    r.isPaid,
        joined_at:  r.createdAt,
      })),
    };
  }

  /** Appliquer un code parrain (après inscription ou depuis le profil) */
  async applyReferralCode(userId: string, referralCode: string) {
    // Vérifier que l'user n'a pas déjà un parrain
    const user = await prisma.user.findUnique({ where: { id: userId } });
    if (!user) throw new Error('Utilisateur introuvable.');
    if (user.referredBy) throw new Error('Vous avez déjà un parrain.');

    // Trouver le parrain via son code
    const referrer = await prisma.user.findUnique({ where: { referralCode } });
    if (!referrer) throw new Error('Code parrainage invalide.');
    if (referrer.id === userId) throw new Error('Vous ne pouvez pas utiliser votre propre code.');

    // Lier le parrain à l'utilisateur
    await prisma.user.update({
      where: { id: userId },
      data:  { referredBy: referrer.id },
    });

    // Créer la relation de parrainage L1
    await prisma.referral.upsert({
      where:  { referrerId_referredId: { referrerId: referrer.id, referredId: userId } },
      update: {},
      create: {
        referrerId:       referrer.id,
        referredId:       userId,
        level:            1,
        commissionAmount: 0, // Commission versée quand le filleul devient Premium
      },
    });

    // Créer la relation L2 si le parrain a lui-même un parrain
    if (referrer.referredBy) {
      await prisma.referral.upsert({
        where:  { referrerId_referredId: { referrerId: referrer.referredBy, referredId: userId } },
        update: {},
        create: {
          referrerId:       referrer.referredBy,
          referredId:       userId,
          level:            2,
          commissionAmount: 0,
        },
      });
    }

    // Notifier le parrain
    await notifSvc.sendToUser(referrer.id, {
      title: '👥 Nouveau filleul !',
      body:  `${user.pseudo} vient de rejoindre PronoWin avec votre code. +${COMMISSION_L1} FCFA quand il s'abonne Premium !`,
      data:  { deep_link: '/compte', type: 'referral' },
    }).catch(() => {});

    return { success: true, referrer_pseudo: referrer.pseudo };
  }

  /** Déclencher les commissions quand un filleul devient Premium */
  async triggerCommissions(newPremiumUserId: string) {
    const referrals = await prisma.referral.findMany({
      where:   { referredId: newPremiumUserId, isPaid: false },
      include: { referrer: true, referred: true },
    });

    for (const ref of referrals) {
      const commission = ref.level === 1 ? COMMISSION_L1 : COMMISSION_L2;

      await Promise.all([
        // Mettre à jour le montant et marquer comme payé
        prisma.referral.update({
          where: { id: ref.id },
          data:  { commissionAmount: commission, isPaid: true },
        }),
        // Créditer les gains du parrain
        prisma.user.update({
          where: { id: ref.referrerId },
          data:  { referralEarnings: { increment: commission } },
        }),
      ]);

      // Notifier le parrain
      await notifSvc.sendToUser(ref.referrerId, {
        title: `💰 Commission L${ref.level} reçue !`,
        body:  `${ref.referred.pseudo} vient de s'abonner Premium ! +${commission} FCFA crédités sur votre compte.`,
        data:  { deep_link: '/compte', type: 'referral' },
      }).catch(() => {});
    }

    return { commissions_paid: referrals.length };
  }

  /** Demande de retrait des gains */
  async requestWithdrawal(params: {
    userId:      string;
    amount:      number;
    method:      string;
    phone:       string;
    useAsCredit: boolean; // true = crédit Premium, false = virement Mobile Money
  }) {
    const { userId, amount, method, phone, useAsCredit } = params;

    const user = await prisma.user.findUnique({ where: { id: userId } });
    if (!user) throw new Error('Utilisateur introuvable.');
    if (user.referralEarnings < amount) throw new Error('Solde insuffisant.');
    if (amount < MIN_WITHDRAWAL) throw new Error(`Minimum ${MIN_WITHDRAWAL} FCFA.`);

    if (useAsCredit) {
      // Convertir en jours Premium (5000 FCFA = 30 jours)
      const premiumDays = Math.floor((amount / 5000) * 30);
      const newExpiry = new Date(
        Math.max(Date.now(), user.subscriptionExpiresAt?.getTime() ?? Date.now()) +
        premiumDays * 86400000
      );

      await prisma.user.update({
        where: { id: userId },
        data: {
          referralEarnings:      { decrement: amount },
          subscriptionPlan:      'premium',
          subscriptionExpiresAt: newExpiry,
        },
      });

      return {
        success: true,
        type:    'credit',
        message: `${amount} FCFA convertis en ${premiumDays} jours Premium. Expiration : ${newExpiry.toLocaleDateString('fr-FR')}`,
        days_added: premiumDays,
      };

    } else {
      // Créer une transaction de retrait
      const tx = await prisma.transaction.create({
        data: {
          userId,
          type:          'withdrawal',
          amount,
          currency:      'XOF',
          senderPhone:   phone,
          paymentMethod: method,
          xbetId:        user.xbetId ?? undefined,
          status:        'pending',
          metadata:      { source: 'referral_earnings' },
        },
      });

      // Déduire provisoirement (sera confirmé par l'admin)
      await prisma.user.update({
        where: { id: userId },
        data:  { referralEarnings: { decrement: amount } },
      });

      return {
        success:        true,
        type:           'withdrawal',
        transaction_id: tx.id,
        message:        `Retrait de ${amount} FCFA sur ${phone} demandé. Traitement sous 30 min ouvrables.`,
      };
    }
  }

  /** Historique des gains */
  async getEarningsHistory(userId: string) {
    const referrals = await prisma.referral.findMany({
      where:   { referrerId: userId, isPaid: true },
      include: { referred: { select: { pseudo: true } } },
      orderBy: { createdAt: 'desc' },
    });

    return referrals.map(r => ({
      pseudo:     r.referred.pseudo,
      level:      r.level,
      amount:     r.commissionAmount,
      date:       r.createdAt,
    }));
  }
}
