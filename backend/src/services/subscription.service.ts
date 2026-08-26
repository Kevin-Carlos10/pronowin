import { NotificationService } from './notification.service';
import { prisma } from '../lib/prisma';
import { Prisma } from '@prisma/client';
import { ReferralService } from './referral.service';
import { listerPubliques } from './payment_method.service';
import { estProfilComplet } from '../middleware/profile.middleware';

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

// Import circulaire assumé : referral.service importe `PREMIUM_PRICE_FCFA_MONTHLY`
// d'ici, et on a besoin de son service. Instancier au chargement du module
// échouait (`ReferralService is not a constructor`) dès que referral.service
// était chargé en premier — l'app ne démarrait que grâce à l'ordre d'import
// des routes. On diffère l'instanciation au premier appel, quand les deux
// modules sont entièrement évalués.
let _referralSvc: ReferralService | null = null;
const referralSvc = () => _referralSvc ??= new ReferralService();

// Prix affichés à l'utilisateur (USD) — la conversion FCFA n'apparaît que sur l'écran de paiement Mobile Money
export const PREMIUM_PRICE_USD_MONTHLY  = parseFloat(process.env.PREMIUM_PRICE_USD_MONTHLY  ?? '10');
export const PREMIUM_PRICE_USD_ANNUAL   = parseFloat(process.env.PREMIUM_PRICE_USD_ANNUAL   ?? '90');
// Montants réellement collectés en FCFA via Mobile Money (Orange Money / Wave / MTN / Moov)
export const PREMIUM_PRICE_FCFA_MONTHLY = parseInt(process.env.PREMIUM_PRICE_FCFA_MONTHLY ?? '6000');
export const PREMIUM_PRICE_FCFA_ANNUAL  = parseInt(process.env.PREMIUM_PRICE_FCFA_ANNUAL  ?? '54000');

/**
 * Parcours « code promo » : plus un tarif, une offre.
 *
 * Il donnait droit à −30 % — l'utilisateur ouvrait un compte chez un partenaire
 * *et* payait quand même. Il donne désormais le **premier mois** de Premium,
 * offert : la contrepartie est l'ouverture d'un compte partenaire avec notre
 * code **et le dépôt initial**, tous deux justifiés par capture.
 *
 * Une seule fois par compte, et une seule fois dans la vie du compte. Ce
 * parcours débloque le premier mois, rien d'autre : au renouvellement,
 * l'abonné paie le tarif normal comme tout le monde. Sans cette limite, le
 * même justificatif se reconduirait indéfiniment, alors que l'ouverture d'un
 * compte partenaire ne se fait qu'une fois.
 *
 * Le canal store ne voit jamais ce parcours : `isStoreBuildProvider` le masque
 * côté mobile (Apple 3.1.1 et politiques jeux d'argent).
 */
export const OFFRE_CODE_JOURS = parseInt(process.env.PREMIUM_CODE_OFFER_DAYS ?? '30');

// Tarif des builds publiés sur l'App Store / Google Play (+50 %).
//
// Apple et Google prélèvent 30 % (15 % au-delà d'un an d'ancienneté de
// l'abonné) : à 10 $ il ne resterait que 7 $, soit exactement le tarif code
// promo. Le canal Mobile Money ne paie aucune commission et garde donc les
// prix ci-dessus.
//
// ⚠️ Ces valeurs ne FIXENT pas le prix facturé : c'est le montant saisi dans
// App Store Connect et la Play Console qui fait foi, et l'écran d'achat
// affiche celui que le store renvoie (déjà localisé et taxé). Elles ne servent
// qu'aux écrans d'accroche (« à partir de X »), qui doivent rester cohérents.
export const PREMIUM_PRICE_USD_STORE_MONTHLY = parseFloat(process.env.PREMIUM_PRICE_USD_STORE_MONTHLY ?? '15');
export const PREMIUM_PRICE_USD_STORE_ANNUAL  = parseFloat(process.env.PREMIUM_PRICE_USD_STORE_ANNUAL  ?? '135');

export const XBET_PROMO_CODE    = process.env.XBET_PROMO_CODE ?? 'PRONOWIN2025';
export const BETTING_PLATFORMS  = ['1xbet', 'melbet', 'betwinner'] as const;
export type BettingPlatform = typeof BETTING_PLATFORMS[number];

/**
 * Délai de validation annoncé à l'utilisateur — **source unique**.
 *
 * Il était écrit en dur ici (réponse à la soumission) et à quatre endroits de
 * l'écran mobile, avec des valeurs qui ne se contrôlaient pas les unes les
 * autres. Le raccourcir côté serveur laissait quatre écrans promettre
 * l'ancien délai, sans qu'aucune erreur ne le signale.
 *
 * Exposé dans `/subscriptions/current` pour que les écrans l'affichent
 * *avant* la soumission — c'est là que l'utilisateur se pose la question,
 * juste après avoir envoyé son argent.
 */
export const REVIEW_DELAY_DIRECT = process.env.REVIEW_DELAY_DIRECT ?? '30 minutes ouvrables';
export const REVIEW_DELAY_CODE   = process.env.REVIEW_DELAY_CODE   ?? '2 heures ouvrables';

/** Jours avant expiration où l'on prévient l'abonné. */
const EXPIRY_REMINDER_DAYS = [7, 3, 1];

export class SubscriptionService {

  /**
   * Prévenir les abonnés dont le Premium expire bientôt.
   *
   * L'interrupteur « Abonnement Premium — Expiration et renouvellement » des
   * Paramètres promettait cette notification, mais rien ne l'envoyait : aucun
   * job ne regardait `subscriptionExpiresAt`. Appelé une fois par jour depuis
   * index.ts.
   *
   * L'idempotence repose sur les paliers : on ne notifie que le jour où il
   * reste exactement 7, 3 ou 1 jour(s), donc au plus une fois par palier tant
   * que le job ne tourne qu'une fois par jour.
   */
  async notifyExpiringSubscriptions() {
    const now = new Date();
    let notified = 0;

    for (const days of EXPIRY_REMINDER_DAYS) {
      // Fenêtre = le jour calendaire situé `days` jours plus tard.
      const from = new Date(now.getTime() + days * 86400000);
      from.setHours(0, 0, 0, 0);
      const to = new Date(from.getTime() + 86400000);

      const users = await prisma.user.findMany({
        where: {
          subscriptionPlan:      'premium',
          isActive:              true,
          subscriptionExpiresAt: { gte: from, lt: to },
        },
        select: { id: true },
      });

      for (const u of users) {
        await notifSvc.sendToUser(u.id, {
          title: days === 1
            ? '⏳ Ton Premium expire demain'
            : `⏳ Ton Premium expire dans ${days} jours`,
          body: days === 1
            ? 'Renouvelle maintenant pour ne pas perdre l\'accès aux pronostics VIP.'
            : 'Renouvelle depuis Compte › Abonnement pour rester couvert sans interruption.',
          data: { deep_link: '/compte', type: 'premium' },
        }, 'premium').catch(() => {});
        notified++;
      }
    }

    return { notified };
  }

  getPlans() {
    return [
      {
        id: 'free', type: 'free', name: 'Plan Gratuit',
        description: 'Pour découvrir PronoWin',
        price_usd: 0, duration_days: 0, is_popular: false,
        features:        ['3 pronostics par jour', 'Tutoriels basiques', 'Notifications matchs'],
        locked_features: ['Pronostics VIP illimités', 'Statistiques avancées', 'Sans publicité'],
      },
      {
        id: 'premium_monthly', type: 'premium', name: 'Premium Mensuel',
        description: 'Accès total à tous les pronostics VIP',
        price_usd:       PREMIUM_PRICE_USD_MONTHLY,
        price_fcfa:      PREMIUM_PRICE_FCFA_MONTHLY,
        duration_days:   30,
        is_popular:      false,
        features:        ['Pronostics VIP illimités', 'Tous les tutoriels', 'Statistiques avancées', 'Sans publicité', 'Support prioritaire'],
        locked_features: [],
        xbet_promo_code: XBET_PROMO_CODE,
      },
      {
        id: 'premium_annual', type: 'premium', name: 'Premium Annuel',
        description: 'Accès total à tous les pronostics VIP — 2 mois offerts',
        price_usd:       PREMIUM_PRICE_USD_ANNUAL,
        price_fcfa:      PREMIUM_PRICE_FCFA_ANNUAL,
        duration_days:   365,
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
        betting_platforms: BETTING_PLATFORMS,
        premium_price_monthly_usd:  PREMIUM_PRICE_USD_MONTHLY,
        premium_price_annual_usd:   PREMIUM_PRICE_USD_ANNUAL,
        premium_price_monthly_fcfa: PREMIUM_PRICE_FCFA_MONTHLY,
        premium_price_annual_fcfa:  PREMIUM_PRICE_FCFA_ANNUAL,
        // Parcours « code promo » : une durée offerte, plus un tarif.
        code_offer_days: OFFRE_CODE_JOURS,
        // Tarif des builds store (commission Apple/Google incluse).
        premium_price_monthly_store_usd: PREMIUM_PRICE_USD_STORE_MONTHLY,
        premium_price_annual_store_usd:  PREMIUM_PRICE_USD_STORE_ANNUAL,
        // Numéros de réception, gérés depuis l'administration. L'app affichait
        // jusqu'ici une constante compilée dans le binaire.
        // Numéros de réception : servis uniquement à un profil complet et
        // majeur.
        //
        // Ils accompagnaient jusqu'ici toute réponse authentifiée. La barrière
        // « 18 ans » n'existait donc que dans le sélecteur de date de
        // l'application : trois appuis pour créer un compte Google, un appel à
        // cette route, et le numéro était lisible — sans nom, sans âge, sans
        // téléphone. Ce champ n'est pas un affichage, c'est la destination
        // d'un virement.
        payment_methods: (await estProfilComplet(userId))
          ? await listerPubliques()
          : [],
        // Délais annoncés — l'écran les affiche avant la soumission, sans les
        // réécrire de son côté.
        review_delay_direct: REVIEW_DELAY_DIRECT,
        review_delay_code:   REVIEW_DELAY_CODE,
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
        betting_platforms: BETTING_PLATFORMS,
        premium_price_monthly_usd:  PREMIUM_PRICE_USD_MONTHLY,
        premium_price_annual_usd:   PREMIUM_PRICE_USD_ANNUAL,
        premium_price_monthly_fcfa: PREMIUM_PRICE_FCFA_MONTHLY,
        premium_price_annual_fcfa:  PREMIUM_PRICE_FCFA_ANNUAL,
        // Parcours « code promo » : une durée offerte, plus un tarif.
        code_offer_days: OFFRE_CODE_JOURS,
        // Tarif des builds store (commission Apple/Google incluse).
        premium_price_monthly_store_usd: PREMIUM_PRICE_USD_STORE_MONTHLY,
        premium_price_annual_store_usd:  PREMIUM_PRICE_USD_STORE_ANNUAL,
        // Branche d'erreur : on ne publie aucun numéro. Ne pas avoir pu lire
        // le profil, c'est ne pas avoir pu vérifier l'âge.
        payment_methods: [],
        review_delay_direct: REVIEW_DELAY_DIRECT,
        review_delay_code:   REVIEW_DELAY_CODE,
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
    userId:              string;
    type:                'payment_screenshot' | 'xbet_account_screenshot';
    imageBase64?:        string;
    screenshotUrl?:      string;
    xbetId?:             string;
    platform?:           string;
    amount?:             number;
    senderPhone?:        string;
    planId?:             string;
  }) {
    const { userId, type, imageBase64, xbetId, platform, amount, senderPhone, planId } = params;
    let screenshotUrl        = params.screenshotUrl;

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

    const s3 = await getS3();

    // Upload S3 si base64 fourni (image principale — paiement direct, ou compte partenaire pour le code)
    if (imageBase64 && !screenshotUrl) {
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

    // Le parcours « code promo » ne comporte plus de versement : la seconde
    // capture, qui prouvait un paiement Mobile Money, n'a plus d'objet.

    if (type === 'payment_screenshot') {
      const expectedFcfa = planId === 'premium_annual' ? PREMIUM_PRICE_FCFA_ANNUAL : PREMIUM_PRICE_FCFA_MONTHLY;
      if (!amount || amount < expectedFcfa)
        throw new Error(`Le montant doit être d'au moins ${expectedFcfa} FCFA.`);
      if (!senderPhone) throw new Error('Numéro Mobile Money requis.');
    }
    if (type === 'xbet_account_screenshot') {
      if (!xbetId?.trim()) throw new Error('ID de compte requis.');
      if (!platform || !BETTING_PLATFORMS.includes(platform as BettingPlatform))
        throw new Error('Plateforme partenaire invalide.');

      // Le premier mois, une seule fois dans la vie du compte. Le contrôle vit
      // ici et non dans l'écran : l'application ne garde pas l'historique des
      // preuves, et un appel direct à l'API contournerait de toute façon une
      // vérification côté client.
      const dejaOfferte = await prisma.subscriptionProof.findFirst({
        where: { userId, type: 'xbet_account_screenshot', status: 'approved' },
      });
      if (dejaOfferte)
        throw new Error(
          'Le mois offert a déjà été accordé sur ce compte. '
          + 'Le renouvellement se fait au tarif normal.');
    }

    const proof = await prisma.subscriptionProof.create({
      data: {
        userId, type, screenshotUrl,
        xbetId:      xbetId?.trim() ?? null,
        platform:    type === 'xbet_account_screenshot' ? (platform ?? null) : null,
        planId:      planId ?? null,
        amount:      amount ?? null,
        senderPhone: senderPhone ?? null,
        status:      'pending',
      },
    });

    if (xbetId) {
      await prisma.user.update({ where: { id: userId }, data: { xbetId: xbetId.trim() } }).catch(() => {});
    }

    return {
      proof_id:         proof.id,
      status:           'pending',
      // `message` répétait le délai en dur : la même réponse annonçait
      // `estimated_review` construit depuis la constante, et « Validation sous
      // 30 minutes » écrit à la main. Raccourcir la variable faisait dire à la
      // même réponse deux choses différentes, dans deux champs que l'écran
      // affiche l'un sous l'autre.
      estimated_review: type === 'payment_screenshot' ? REVIEW_DELAY_DIRECT : REVIEW_DELAY_CODE,
      message:          type === 'payment_screenshot'
        ? `Preuve de paiement soumise. Validation sous ${REVIEW_DELAY_DIRECT}.`
        : `Preuve de compte partenaire soumise. Validation sous ${REVIEW_DELAY_CODE}, `
          + `puis ${OFFRE_CODE_JOURS} jours de Premium offerts.`,
    };
  }

  /**
   * Preuves d'abonnement, filtrables par statut.
   *
   * Cette méthode ne servait que la file « en attente », et l'écran admin
   * n'affichait donc rien d'autre : une fois une preuve traitée elle
   * disparaissait sans laisser de trace consultable, alors que c'est une
   * décision financière qu'on doit pouvoir retrouver et justifier.
   *
   * L'ancien `catch` renvoyait silencieusement une liste vide : une panne de
   * base de données s'affichait comme « aucune preuve en attente ». L'erreur
   * remonte désormais, à charge de l'appelant de la montrer.
   */
  async listProofs(params: {
    page?: number; perPage?: number;
    statut?: 'pending' | 'approved' | 'rejected' | 'all';
    recherche?: string;
  } = {}) {
    const page    = Math.max(1, params.page ?? 1);
    const perPage = Math.min(5000, Math.max(1, params.perPage ?? 20));
    const statut  = params.statut ?? 'pending';
    const q       = (params.recherche ?? '').trim();

    const where: Prisma.SubscriptionProofWhereInput = {};
    if (statut !== 'all') where.status = statut;
    if (q) {
      where.OR = [
        { xbetId:      { contains: q, mode: 'insensitive' } },
        { senderPhone: { contains: q, mode: 'insensitive' } },
        { user: { pseudo:      { contains: q, mode: 'insensitive' } } },
        { user: { phoneNumber: { contains: q, mode: 'insensitive' } } },
      ];
    }

    const [items, total, contexte] = await Promise.all([
      prisma.subscriptionProof.findMany({
        where,
        include: { user: { select: { id: true, pseudo: true, phoneNumber: true, xbetId: true } } },
        // En attente : le plus ancien d'abord (ordre de la file). Traitées :
        // le plus récent d'abord (ordre d'un historique).
        orderBy: statut === 'pending' ? { createdAt: 'asc' } : { reviewedAt: 'desc' },
        skip: (page - 1) * perPage,
        take: perPage,
      }),
      prisma.subscriptionProof.count({ where }),
      this._contexteProofs(),
    ]);

    return { data: items, total, page, per_page: perPage, statut, recherche: q,
             promo_code: XBET_PROMO_CODE, contexte };
  }

  /** Conservé pour les appelants existants. */
  async getPendingProofs(page = 1, perPage = 20) {
    return this.listProofs({ page, perPage, statut: 'pending' });
  }

  /**
   * Chiffres d'ensemble : ils expliquent une file vide et donnent la mesure de
   * l'activité de validation, que l'écran ne montrait nulle part.
   */
  private async _contexteProofs() {
    const [parStatut, revenu, dernieres] = await Promise.all([
      prisma.subscriptionProof.groupBy({ by: ['status'], _count: { _all: true } }),
      prisma.subscriptionProof.aggregate({ where: { status: 'approved' }, _sum: { amount: true } }),
      // Délai de traitement : mesuré sur les 100 dernières décisions, pas sur
      // tout l'historique — la moyenne doit refléter le rythme actuel.
      prisma.subscriptionProof.findMany({
        where:   { status: { not: 'pending' }, reviewedAt: { not: null } },
        select:  { createdAt: true, reviewedAt: true },
        orderBy: { reviewedAt: 'desc' },
        take:    100,
      }),
    ]);

    const compte = (s: string) =>
      parStatut.find(g => g.status === s)?._count._all ?? 0;

    // Borne a 0 : une date de revue anterieure a la soumission (horloge
    // decalee, reprise de donnees) donnerait une moyenne negative, affichee
    // telle quelle a l'ecran.
    const delais = dernieres.map(d => Math.max(0,
      (d.reviewedAt!.getTime() - d.createdAt.getTime()) / 3600000));
    const delaiMoyen = delais.length
      ? Math.round((delais.reduce((a, b) => a + b, 0) / delais.length) * 10) / 10
      : null;

    return {
      en_attente:        compte('pending'),
      approuvees:        compte('approved'),
      rejetees:          compte('rejected'),
      total:             parStatut.reduce((n, g) => n + g._count._all, 0),
      revenu_approuve:   Math.round(revenu._sum.amount ?? 0),
      derniere_decision: dernieres[0]?.reviewedAt ?? null,
      delai_moyen_h:     delaiMoyen,
      delai_echantillon: dernieres.length,
    };
  }

  /**
   * Accorder (ou prolonger) le Premium. Point d'entrée unique.
   *
   * Extrait de `reviewProof` pour que l'achat intégré emprunte exactement le
   * même chemin : sans ça, un abonnement acheté sur l'App Store ne
   * déclencherait pas les commissions de parrainage et n'apparaîtrait pas dans
   * l'historique `Subscription`.
   *
   * `expiresAt` permet à l'IAP d'imposer la date du store plutôt que de
   * calculer une durée : c'est Apple/Google qui font foi sur l'échéance.
   */
  async grantPremium(params: {
    userId:        string;
    durationDays?: number;
    expiresAt?:    Date;
    amountPaid?:   number;
    paymentMethod: string;
    promoCodeUsed?: string | null;
    notify?:       boolean;
  }) {
    const { userId, durationDays = 30, expiresAt, amountPaid = 0,
            paymentMethod, promoCodeUsed = null, notify = true } = params;

    const user = await prisma.user.findUnique({
      where: { id: userId }, select: { subscriptionExpiresAt: true },
    });
    if (!user) throw new Error('Utilisateur introuvable.');

    const startDate = new Date();
    // Prolonge depuis la date d'expiration en cours si l'abonnement est encore
    // actif, au lieu d'écraser les jours déjà payés et non consommés.
    const endDate = expiresAt ?? new Date(
      Math.max(Date.now(), user.subscriptionExpiresAt?.getTime() ?? Date.now()) +
      durationDays * 86400000
    );

    await Promise.all([
      prisma.subscription.create({ data: {
        userId, plan: 'premium', amountPaid, paymentMethod, promoCodeUsed,
        startDate, endDate,
      } }),
      prisma.user.update({ where: { id: userId }, data: {
        subscriptionPlan: 'premium', subscriptionExpiresAt: endDate,
      } }),
    ]);

    // ── DÉCLENCHER LES COMMISSIONS DE PARRAINAGE ────────────────────────────
    await referralSvc().triggerCommissions(userId).catch(e =>
      console.error('[Parrainage] Erreur triggerCommissions:', e.message)
    );

    if (notify) {
      const days = Math.max(1, Math.ceil((endDate.getTime() - Date.now()) / 86400000));
      await notifSvc.sendToUser(userId, {
        title: '🎉 Bienvenue Premium !',
        body:  `Votre accès Premium est activé pour ${days} jours !`,
        data:  { deep_link: '/pronostics', type: 'system' },
      }, 'premium').catch(() => {});
    }

    return { endDate };
  }

  async reviewProof(params: { proofId: string; adminId: string; approved: boolean; adminNote?: string; durationDays?: number }) {
    const { proofId, adminId, approved, adminNote, durationDays = 30 } = params;
    const proof = await prisma.subscriptionProof.findUnique({ where: { id: proofId }, include: { user: true } });
    if (!proof)                    throw new Error('Preuve introuvable.');
    if (proof.status !== 'pending') throw new Error('Preuve déjà traitée.');

    if (approved) {
      // La durée du parcours « code promo » est celle de l'offre, jamais celle
      // saisie côté administration : une offre annoncée « un mois » qui en
      // accorderait douze parce qu'une liste déroulante traînait sur l'annuel
      // resterait invisible jusqu'à ce que quelqu'un compte.
      const jours = proof.type === 'xbet_account_screenshot'
        ? OFFRE_CODE_JOURS
        : durationDays;

      await Promise.all([
        this.grantPremium({
          userId:        proof.userId,
          durationDays:  jours,
          amountPaid:    proof.amount ?? 0,
          paymentMethod: proof.type === 'payment_screenshot'
            ? 'manual_mobcash'
            : `promo_${proof.platform ?? 'code'}`,
          promoCodeUsed: proof.type === 'xbet_account_screenshot' ? XBET_PROMO_CODE : null,
        }),
        prisma.subscriptionProof.update({ where: { id: proofId }, data: { status: 'approved', adminNote, reviewedBy: adminId, reviewedAt: new Date() } }),
      ]);
    } else {
      await prisma.subscriptionProof.update({ where: { id: proofId }, data: { status: 'rejected', adminNote, reviewedBy: adminId, reviewedAt: new Date() } });
      await notifSvc.sendToUser(proof.userId, { title: '❌ Preuve refusée', body: adminNote ?? 'Votre preuve n\'a pas pu être validée.', data: { deep_link: '/compte', type: 'system' } }, 'premium').catch(() => {});
    }
    return { success: true, approved };
  }
}
