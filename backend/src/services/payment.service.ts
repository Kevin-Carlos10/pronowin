import { NotificationService } from './notification.service';
import { prisma } from '../lib/prisma';

const notifSvc = new NotificationService();

// ─── Numéros MobCash affichés à l'utilisateur ─────────────────────────────────
export const MOBCASH_NUMBERS = {
  orange_money: process.env.MOBCASH_ORANGE  ?? '+22670000000',
  moov_money:   process.env.MOBCASH_MOOV    ?? '+22660000000',
  mtn_momo:     process.env.MOBCASH_MTN     ?? '+22650000000',
};

export type PaymentMethodKey = keyof typeof MOBCASH_NUMBERS;

export class PaymentService {

  /** Créer une demande de dépôt/retrait — traitement MANUEL par l'admin */
  async createRequest(params: {
    userId:       string;
    type:         'deposit' | 'withdrawal';
    amount:       number;
    method:       PaymentMethodKey;
    xbetId:       string;
    senderPhone:  string;
  }) {
    const { userId, type, amount, method, xbetId, senderPhone } = params;

    if (amount < 500)     throw new Error('Montant minimum : 500 FCFA.');
    if (!xbetId?.trim())  throw new Error('Votre ID 1xBet est requis.');
    if (!senderPhone?.trim()) throw new Error('Votre numéro Mobile Money est requis.');

    // Transaction atomique : créer la demande ET mettre à jour le profil ensemble
    const [tx] = await prisma.$transaction([
      prisma.transaction.create({
        data: {
          userId, type, amount, currency: 'XOF',
          xbetId:        xbetId.trim(),
          senderPhone:   senderPhone.trim(),
          paymentMethod: method,
          status: 'pending',
          metadata: {
            mobcash_number: MOBCASH_NUMBERS[method],
            instructions:   `Envoyez ${amount} FCFA au ${MOBCASH_NUMBERS[method]} via ${method.replace('_', ' ').toUpperCase()}`,
          },
        },
      }),
      prisma.user.update({
        where: { id: userId },
        data:  { xbetId: xbetId.trim() },
      }),
    ]);

    return {
      transaction_id:   tx.id,
      status:           'pending',
      mobcash_number:   MOBCASH_NUMBERS[method],
      method_label:     method.replace('_money','').replace('_momo','').replace('_', ' ').toUpperCase(),
      amount,
      instructions:     [
        `1. Ouvrez votre application ${method.replace('_money','').replace('_momo','').replace('_',' ').toUpperCase()}`,
        `2. Envoyez ${amount.toLocaleString()} FCFA au numéro ${MOBCASH_NUMBERS[method]}`,
        `3. Utilisez comme référence votre ID 1xBet : ${xbetId}`,
        `4. Votre demande sera traitée sous 30 minutes ouvrables`,
      ],
      estimated_processing: '30 minutes ouvrables',
    };
  }

  /** Admin — traiter une demande (approuver / rejeter) */
  async processRequest(params: {
    transactionId: string;
    adminId:       string;
    status:        'completed' | 'rejected';
    adminNote?:    string;
  }) {
    const { transactionId, adminId, status, adminNote } = params;

    const tx = await prisma.transaction.findUnique({
      where: { id: transactionId }, include: { user: true },
    });
    if (!tx) throw new Error('Transaction introuvable.');
    if (tx.status === 'completed' || tx.status === 'rejected') {
      throw new Error('Cette transaction a déjà été traitée.');
    }

    const updated = await prisma.transaction.update({
      where: { id: transactionId },
      data:  {
        status,
        adminNote:   adminNote ?? null,
        processedBy: adminId,
        processedAt: new Date(),
      },
    });

    // Notifier l'utilisateur
    if (tx.user.fcmToken) {
      if (status === 'completed') {
        await notifSvc.sendToUser(tx.userId, {
          title: tx.type === 'deposit' ? '✅ Dépôt confirmé !' : '✅ Retrait effectué !',
          body:  `${tx.amount.toLocaleString()} FCFA ${tx.type === 'deposit' ? 'crédité sur votre compte 1xBet' : 'envoyé sur votre Mobile Money'}.`,
          data:  { deep_link: '/depot-retrait', type: 'payment' },
        });
      } else {
        await notifSvc.sendToUser(tx.userId, {
          title: '❌ Demande refusée',
          body:  adminNote ?? 'Votre demande n\'a pas pu être traitée. Contactez le support.',
          data:  { deep_link: '/depot-retrait', type: 'payment' },
        });
      }
    }

    return updated;
  }

  /** Admin — liste des demandes en attente */
  async getPendingRequests(page = 1, perPage = 20) {
    const [items, total] = await Promise.all([
      prisma.transaction.findMany({
        where:   { status: 'pending' },
        include: { user: { select: { pseudo: true, phoneNumber: true, xbetId: true } } },
        orderBy: { createdAt: 'asc' },
        skip:    (page - 1) * perPage,
        take:    perPage,
      }),
      prisma.transaction.count({ where: { status: 'pending' } }),
    ]);
    return { data: items, total, page, per_page: perPage };
  }

  /** Historique des transactions d'un utilisateur */
  async getUserTransactions(userId: string, page = 1) {
    const [items, total] = await Promise.all([
      prisma.transaction.findMany({
        where:   { userId },
        orderBy: { createdAt: 'desc' },
        skip:    (page - 1) * 20,
        take:    20,
      }),
      prisma.transaction.count({ where: { userId } }),
    ]);
    return { data: items.map(this._format), total, page };
  }

  async getWalletInfo(userId: string) {
    const user = await prisma.user.findUnique({ where: { id: userId } });
    const pending = await prisma.transaction.count({ where: { userId, status: 'pending' } });
    return {
      xbet_id:         user?.xbetId ?? null,
      pending_requests: pending,
      mobcash_numbers:  MOBCASH_NUMBERS,
      currency:         'XOF',
      message: user?.xbetId
        ? `Compte 1xBet lié : ${user.xbetId}`
        : 'Liez votre ID 1xBet pour effectuer des transactions',
    };
  }

  private _format(tx: any) {
    return {
      id: tx.id, type: tx.type, amount: tx.amount, currency: tx.currency,
      xbet_id: tx.xbetId, sender_phone: tx.senderPhone,
      payment_method: tx.paymentMethod, status: tx.status,
      admin_note: tx.adminNote, created_at: tx.createdAt,
      processed_at: tx.processedAt,
    };
  }
}
