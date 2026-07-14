
import { prisma } from '../lib/prisma';

export class ProfileService {

  async getProfile(userId: string) {
    const user = await prisma.user.findUnique({ where: { id: userId } });
    if (!user) throw new Error('Utilisateur introuvable.');

    const betStats = await prisma.bankrollBet.groupBy({
      by:     ['result'],
      where:  { bankroll: { userId } },
      _count: { _all: true },
    });
    const wins      = betStats.find(r => r.result === 'WIN')?._count._all  ?? 0;
    const losses    = betStats.find(r => r.result === 'LOSS')?._count._all ?? 0;
    const totalBets = wins + losses + (betStats.find(r => r.result === null)?._count._all ?? 0);
    const winRate   = wins + losses > 0 ? Math.round((wins / (wins + losses)) * 100) : 0;

    return {
      id:                      user.id,
      pseudo:                  user.pseudo,
      phone_number:            user.phoneNumber,
      email:                   user.email,
      avatar_url:              user.avatarUrl,
      country_code:            user.countryCode,
      subscription_plan:       user.subscriptionPlan,
      subscription_expires_at: user.subscriptionExpiresAt?.toISOString() ?? null,
      referral_code:           user.referralCode,
      referral_earnings:       user.referralEarnings,
      phone_verified:          user.phoneVerified,
      email_verified:          user.emailVerified,
      total_bets:              totalBets,
      total_wins:              wins,
      total_losses:            losses,
      win_rate:                winRate,
      created_at:              user.createdAt.toISOString(),
      notif_prefs: {
        match_alerts:    true,
        promo_alerts:    true,
        referral_alerts: true,
        payment_alerts:  true,
        premium_alerts:  true,
      },
    };
  }

  async updateProfile(userId: string, data: { pseudo?: string; email?: string; avatarUrl?: string }) {
    // Vérifier unicité du pseudo
    if (data.pseudo) {
      const existing = await prisma.user.findFirst({
        where: { pseudo: data.pseudo, NOT: { id: userId } },
      });
      if (existing) throw new Error('Ce pseudo est déjà utilisé.');
    }

    // Vérifier unicité de l'email
    if (data.email) {
      const existing = await prisma.user.findFirst({
        where: { email: data.email, NOT: { id: userId } },
      });
      if (existing) throw new Error('Cet email est déjà associé à un autre compte.');
    }

    const updated = await prisma.user.update({
      where: { id: userId },
      data:  {
        ...(data.pseudo    && { pseudo:    data.pseudo }),
        ...(data.email     && { email:     data.email }),
        ...(data.avatarUrl && { avatarUrl: data.avatarUrl }),
      },
    });

    return this.getProfile(userId);
  }

  async updateNotifPrefs(userId: string, prefs: Record<string, boolean>) {
    // En prod : sauvegarder dans table user_notification_prefs
    console.log(`[NOTIF] Préférences mises à jour pour ${userId}:`, prefs);
    return { success: true };
  }

  async deleteAccount(userId: string) {
    // Anonymiser plutôt que supprimer (conformité RGPD)
    await prisma.user.update({
      where: { id: userId },
      data:  {
        pseudo:      `Supprimé_${userId.slice(-6)}`,
        phoneNumber: `+000${Date.now()}`,
        email:       null,
        avatarUrl:   null,
        isActive:    false,
      },
    });
    // Supprimer les tokens
    await prisma.refreshToken.deleteMany({ where: { userId } });
  }
}
