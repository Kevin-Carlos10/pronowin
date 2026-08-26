import { Response } from 'express';
import { AuthRequest } from '../middleware/auth.middleware';

import { prisma } from '../lib/prisma';
import { NOTIF_CATEGORIES } from '../services/notification.service';
import { estMajeur, AGE_MINIMUM } from '../utils/age';

/**
 * PATCH /profile/notification-prefs
 *
 * Le mobile s'abonnait uniquement à des topics FCM, ce qui ne pouvait pas
 * filtrer les notifications personnelles (envoyées par token). Les préférences
 * sont désormais aussi stockées côté serveur, et `sendToUser` les respecte.
 */
export const updateNotificationPrefs = async (req: AuthRequest, res: Response) => {
  try {
    const body = req.body as Record<string, unknown>;
    const prefs: Record<string, boolean> = {};
    for (const key of NOTIF_CATEGORIES) {
      const v = body[key];
      if (typeof v === 'boolean') prefs[key] = v;
    }
    if (Object.keys(prefs).length === 0) {
      res.status(400).json({
        message: `Aucune préférence valide. Attendu : ${NOTIF_CATEGORIES.join(', ')} (booléens).`,
      });
      return;
    }

    // Fusion avec l'existant : le mobile n'envoie que la clé modifiée.
    const current = await prisma.user.findUnique({
      where: { id: req.userId! }, select: { notificationPrefs: true },
    });
    const merged = {
      ...(current?.notificationPrefs as Record<string, boolean> | null ?? {}),
      ...prefs,
    };

    await prisma.user.update({
      where: { id: req.userId! },
      data:  { notificationPrefs: merged },
    });
    res.json({ success: true, notification_prefs: merged });
  } catch (e: any) {
    res.status(500).json({ message: e.message });
  }
};

// Import S3 différé : le module lit les credentials AWS à son chargement, et
// on doit pouvoir démarrer sans eux.
let s3Svc: any = null;
async function getS3() {
  if (!s3Svc && process.env.AWS_ACCESS_KEY_ID && process.env.AWS_SECRET_ACCESS_KEY) {
    const { S3Service } = await import('../services/s3.service');
    s3Svc = new S3Service();
  }
  return s3Svc;
}

/**
 * PATCH /profile/avatar
 *
 * La photo de profil était envoyée par le mobile depuis toujours ; l'endpoint
 * n'existait pas et l'upload échouait systématiquement en 404.
 *
 * Format base64, comme les preuves d'abonnement : c'est le seul chemin
 * d'upload déjà éprouvé du projet, et il évite d'ajouter du multipart.
 */
export const updateAvatar = async (req: AuthRequest, res: Response) => {
  const { image_base64 } = req.body as { image_base64?: string };
  if (!image_base64?.startsWith('data:image/')) {
    res.status(422).json({
      message: 'image_base64 requis, au format « data:image/jpeg;base64,... ».',
    });
    return;
  }

  const s3 = await getS3();
  if (!s3) {
    res.status(503).json({
      message: 'Stockage d\'images non configuré. Ajoutez AWS_ACCESS_KEY_ID dans .env',
    });
    return;
  }

  try {
    const previous = await prisma.user.findUnique({
      where: { id: req.userId! }, select: { avatarUrl: true },
    });

    const url = await s3.uploadImage({
      base64: image_base64, folder: 'avatars', userId: req.userId!,
    });
    await prisma.user.update({
      where: { id: req.userId! }, data: { avatarUrl: url },
    });

    // Supprimer l'ancienne image : sans ça, chaque changement de photo laisse
    // un fichier orphelin facturé indéfiniment.
    if (previous?.avatarUrl) {
      await s3.deleteImage(previous.avatarUrl).catch((e: any) =>
        console.warn('[Avatar] Ancienne image non supprimée :', e.message));
    }

    res.json({ success: true, avatar_url: url });
  } catch (e: any) {
    // uploadImage lève sur un format invalide ou une image > 5 Mo : ce sont
    // des erreurs d'entrée, pas des pannes serveur.
    res.status(422).json({ message: e.message });
  }
};

/** GET /profile */
export const getProfile = async (req: AuthRequest, res: Response) => {
  try {
    const user = await prisma.user.findUnique({
      where:  { id: req.userId! },
      select: {
        id: true, phoneNumber: true, email: true, pseudo: true,
        firstName: true, lastName: true, birthDate: true,
        avatarUrl: true, countryCode: true, xbetId: true,
        subscriptionPlan: true, subscriptionExpiresAt: true,
        referralCode: true, referralEarnings: true,
        isActive: true, createdAt: true, lastLoginAt: true,
      },
    });
    if (!user) { res.status(404).json({ message: 'Utilisateur introuvable.' }); return; }

    res.json({
      id:                      user.id,
      phone_number:            user.phoneNumber,
      email:                   user.email,
      pseudo:                  user.pseudo,
      first_name:              user.firstName,
      last_name:               user.lastName,
      birth_date:              user.birthDate,
      full_name:               user.firstName && user.lastName
                                 ? `${user.firstName} ${user.lastName}` : null,
      avatar_url:              user.avatarUrl,
      country_code:            user.countryCode,
      xbet_id:                 user.xbetId,
      subscription_plan:       user.subscriptionPlan,
      subscription_expires_at: user.subscriptionExpiresAt,
      referral_code:           user.referralCode,
      referral_earnings:       user.referralEarnings,
      is_active:               user.isActive,
      created_at:              user.createdAt,
      last_login_at:           user.lastLoginAt,
    });
  } catch (e: any) { res.status(500).json({ message: e.message }); }
};

/** PATCH /profile */
export const updateProfile = async (req: AuthRequest, res: Response) => {
  const { pseudo, email, phone_number, first_name, last_name, birth_date, country_code } = req.body;

  // Validations
  const PSEUDO_REGEX = /^[a-zA-Z0-9_\-À-ÿ]{3,20}$/;
  const RESERVED_PSEUDOS = ['admin', 'support', 'pronowin', 'moderateur', 'root', 'system'];
  if (pseudo !== undefined) {
    const p = pseudo.trim();
    if (p.length < 3) {
      res.status(422).json({ message: 'Pseudo trop court (minimum 3 caractères).' }); return;
    }
    if (p.length > 20) {
      res.status(422).json({ message: 'Pseudo trop long (maximum 20 caractères).' }); return;
    }
    if (!PSEUDO_REGEX.test(p)) {
      res.status(422).json({ message: 'Pseudo invalide : lettres, chiffres, _ et - uniquement.' }); return;
    }
    if (RESERVED_PSEUDOS.includes(p.toLowerCase())) {
      res.status(422).json({ message: 'Ce pseudo est réservé.' }); return;
    }
  }
  if (email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim())) {
    res.status(422).json({ message: 'Email invalide.' }); return;
  }
  if (first_name !== undefined && first_name.trim().length < 2) {
    res.status(422).json({ message: 'Prénom trop court (minimum 2 caractères).' }); return;
  }
  if (last_name !== undefined && last_name.trim().length < 2) {
    res.status(422).json({ message: 'Nom trop court (minimum 2 caractères).' }); return;
  }

  // Validation date de naissance — doit avoir au moins 18 ans.
  //
  // `estMajeur` remplace un calcul par division (365,25 jours) qui se trompait
  // d'un jour autour de l'anniversaire, et refuse aussi les dates futures.
  if (birth_date) {
    const dob = new Date(birth_date);
    if (isNaN(dob.getTime())) {
      res.status(422).json({ message: 'Date de naissance invalide.' }); return;
    }
    if (!estMajeur(dob)) {
      res.status(422).json({
        message: `Vous devez avoir au moins ${AGE_MINIMUM} ans pour utiliser PronoWin.`,
      });
      return;
    }
  }

  try {
    // Vérifier unicité du pseudo (insensible à la casse)
    if (pseudo) {
      const pseudoLower = pseudo.trim().toLowerCase();
      const existing = await prisma.user.findFirst({
        where: { pseudo: { equals: pseudoLower, mode: 'insensitive' }, NOT: { id: req.userId! } },
      });
      if (existing) { res.status(400).json({ message: 'Ce pseudo est déjà utilisé.' }); return; }
    }

    // Vérifier unicité de l'email
    const emailTrimmed = email?.trim() || null;
    if (emailTrimmed) {
      const existingEmail = await prisma.user.findFirst({
        where: { email: emailTrimmed, NOT: { id: req.userId! } },
      });
      if (existingEmail) { res.status(400).json({ message: 'Cet email est déjà utilisé par un autre compte.' }); return; }
    }

    // Vérifier unicité du numéro de téléphone
    const phoneTrimmed = phone_number?.trim() || null;
    if (phoneTrimmed) {
      if (!/^\+?[1-9]\d{7,14}$/.test(phoneTrimmed)) {
        res.status(422).json({ message: 'Format de numéro de téléphone invalide.' }); return;
      }
      const existingPhone = await prisma.user.findFirst({
        where: { phoneNumber: phoneTrimmed, NOT: { id: req.userId! } },
      });
      if (existingPhone) { res.status(400).json({ message: 'Ce numéro est déjà utilisé par un autre compte.' }); return; }
    }

    const updated = await prisma.user.update({
      where: { id: req.userId! },
      data:  {
        ...(pseudo       ? { pseudo:       pseudo.trim()    } : {}),
        ...(emailTrimmed ? { email:        emailTrimmed     } : {}),
        ...(phoneTrimmed ? { phoneNumber:  phoneTrimmed     } : {}),
        ...(first_name   ? { firstName:    first_name.trim()  } : {}),
        ...(last_name    ? { lastName:     last_name.trim()   } : {}),
        ...(birth_date   ? { birthDate:    new Date(birth_date) } : {}),
        ...(country_code ? { countryCode:  country_code     } : {}),
      },
      select: {
        id: true, phoneNumber: true, email: true, pseudo: true,
        firstName: true, lastName: true, birthDate: true,
        countryCode: true, subscriptionPlan: true,
        referralCode: true, referralEarnings: true, createdAt: true,
      },
    });

    res.json({
      message: 'Profil mis à jour avec succès.',
      user: {
        id:                updated.id,
        phone_number:      updated.phoneNumber,
        email:             updated.email,
        pseudo:            updated.pseudo,
        first_name:        updated.firstName,
        last_name:         updated.lastName,
        birth_date:        updated.birthDate,
        full_name:         updated.firstName && updated.lastName
                             ? `${updated.firstName} ${updated.lastName}` : null,
        country_code:      updated.countryCode,
        subscription_plan: updated.subscriptionPlan,
        referral_code:     updated.referralCode,
        created_at:        updated.createdAt,
      },
    });
  } catch (e: any) { res.status(500).json({ message: e.message }); }
};

/** DELETE /profile — Droit à l'oubli RGPD : anonymise les données personnelles */
export const deleteAccount = async (req: AuthRequest, res: Response) => {
  try {
    const anonymized = `deleted_${Date.now()}`;
    await prisma.user.update({
      where: { id: req.userId! },
      data: {
        phoneNumber:    `+00000000000_${anonymized}`,
        email:          null,
        pseudo:         anonymized,
        firstName:      null,
        lastName:       null,
        avatarUrl:      null,
        fcmToken:       null,
        xbetId:         null,
        birthDate:      null,
        isActive:       false,
        deletedAt:      new Date(),
      } as any,
    });
    // Révoquer tous les tokens de refresh
    await prisma.refreshToken.updateMany({
      where: { userId: req.userId! },
      data:  { used: true },
    });
    res.json({ message: 'Compte supprimé. Vos données personnelles ont été anonymisées.' });
  } catch (e: any) { res.status(500).json({ message: e.message }); }
};

/** GET /profile/stats */
export const getStats = async (req: AuthRequest, res: Response) => {
  try {
    const [bets, txCompleted, referrals, bankroll] = await Promise.all([
      prisma.bankrollBet.findMany({
        where:   { bankroll: { userId: req.userId! } },
        select:  {
          result: true, createdAt: true, settledAt: true,
          stakedAmount: true, oddsUsed: true, potentialGain: true, profit: true,
          pronostic: { select: { match: { select: { league: true } } } },
        },
        orderBy: { createdAt: 'desc' },
      }),
      prisma.transaction.count({ where: { userId: req.userId!, status: 'completed' } }),
      prisma.referral.count({ where: { referrerId: req.userId! } }),
      prisma.userBankroll.findFirst({
        where:   { userId: req.userId! },
        select:  { currentBalance: true },
      }),
    ]);

    const settled  = bets.filter(b => b.result !== null);
    const wins     = settled.filter(b => b.result === 'WIN');
    const losses   = settled.filter(b => b.result === 'LOSS');
    // Un remboursé (PUSH) n'est ni une victoire ni une défaite — exclu du taux de réussite.
    const decisive = wins.length + losses.length;
    const taux     = decisive > 0 ? Math.round((wins.length / decisive) * 100) : 0;

    // Série gagnante en cours (un PUSH est neutre, il n'interrompt pas la série)
    let serie = 0;
    for (const b of settled) {
      if (b.result === 'WIN') serie++;
      else if (b.result === 'LOSS') break;
    }

    // Meilleure série historique
    let bestSerie = 0, cur = 0;
    for (const b of [...settled].reverse()) {
      if (b.result === 'WIN') { cur++; if (cur > bestSerie) bestSerie = cur; }
      else if (b.result === 'LOSS') cur = 0;
    }

    // ROI & profit net — la mise remboursée (PUSH) n'a jamais été réellement à risque
    const totalStaked = settled.filter(b => b.result !== 'PUSH').reduce((s, b) => s + b.stakedAmount, 0);
    const totalProfit = settled.reduce((s, b) => s + (b.profit ?? 0), 0);
    const roi = totalStaked > 0 ? Math.round((totalProfit / totalStaked) * 100 * 10) / 10 : 0;

    // Meilleure cote gagnée
    const bestOdds = wins.length > 0
      ? Math.max(...wins.map(b => b.oddsUsed))
      : 0;

    // Évolution bankroll sur 30 jours (1 point par jour)
    const now   = new Date();
    const from  = new Date(now.getTime() - 30 * 86400000);
    const bankrollHistory: { date: string; balance: number }[] = [];
    let runningBalance = (bankroll?.currentBalance ?? 0) - totalProfit;

    // Regrouper les bets réglés par jour
    const profitByDay = new Map<string, number>();
    for (const b of settled) {
      const d = b.settledAt ?? b.createdAt;
      if (d < from) continue;
      const key = d.toISOString().slice(0, 10);
      profitByDay.set(key, (profitByDay.get(key) ?? 0) + (b.profit ?? 0));
    }

    for (let i = 30; i >= 0; i--) {
      const d   = new Date(now.getTime() - i * 86400000);
      const key = d.toISOString().slice(0, 10);
      runningBalance += profitByDay.get(key) ?? 0;
      bankrollHistory.push({ date: key, balance: Math.round(runningBalance) });
    }

    // Répartition par ligue (top 5)
    const leagueMap = new Map<string, { total: number; wins: number }>();
    for (const b of settled) {
      const league = b.pronostic?.match?.league ?? 'Autre';
      const prev   = leagueMap.get(league) ?? { total: 0, wins: 0 };
      leagueMap.set(league, {
        total: prev.total + 1,
        wins:  prev.wins + (b.result === 'WIN' ? 1 : 0),
      });
    }
    const leagueStats = [...leagueMap.entries()]
      .map(([name, v]) => ({ name, ...v, taux: Math.round((v.wins / v.total) * 100) }))
      .sort((a, b) => b.total - a.total)
      .slice(0, 5);

    res.json({
      // Base
      pronostics_suivis: bets.length,
      paris_gagnes:      wins.length,
      paris_perdus:      losses.length,
      taux_reussite:     taux,
      serie_gagnante:    serie,
      transactions:      txCompleted,
      referrals,
      // Enrichi
      roi,
      profit_net:        Math.round(totalProfit),
      total_mise:        Math.round(totalStaked),
      meilleure_cote:    Math.round(bestOdds * 100) / 100,
      meilleure_serie:   bestSerie,
      solde_actuel:      bankroll?.currentBalance ?? 0,
      bankroll_history:  bankrollHistory,
      league_stats:      leagueStats,
    });
  } catch (e: any) { res.status(500).json({ message: e.message }); }
};
