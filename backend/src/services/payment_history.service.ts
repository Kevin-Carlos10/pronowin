
import { prisma } from '../lib/prisma';

export class PaymentHistoryService {

  /** Historique paginé avec tous les filtres */
  async getHistory(params: {
    page:      number;
    perPage:   number;
    search?:   string;   // pseudo, téléphone, xbetId
    status?:   string;   // pending | processing | completed | rejected
    method?:   string;   // orange_money | moov_money | mtn_momo
    dateFrom?: string;   // YYYY-MM-DD
    dateTo?:   string;
    sortDir?:  'asc' | 'desc';
  }) {
    const { page, perPage, search, status, method, dateFrom, dateTo, sortDir = 'desc' } = params;

    const where: any = {};

    // Filtre recherche
    if (search) {
      where.OR = [
        { user: { pseudo:      { contains: search, mode: 'insensitive' } } },
        { user: { phoneNumber: { contains: search } } },
        { xbetId:      { contains: search } },
        { senderPhone: { contains: search } },
      ];
    }

    if (status) where.status        = status;
    if (method) where.paymentMethod = method;

    // Filtre date
    if (dateFrom || dateTo) {
      where.createdAt = {};
      if (dateFrom) where.createdAt.gte = new Date(dateFrom);
      if (dateTo)   where.createdAt.lte = new Date(dateTo + 'T23:59:59');
    }

    const [items, total] = await Promise.all([
      prisma.transaction.findMany({
        where,
        include: {
          user: { select: { pseudo: true, phoneNumber: true, xbetId: true } },
        },
        orderBy: { createdAt: sortDir },
        skip:    (page - 1) * perPage,
        take:    perPage,
      }),
      prisma.transaction.count({ where }),
    ]);

    return {
      data:        items,
      total,
      page,
      per_page:    perPage,
      total_pages: Math.ceil(total / perPage),
    };
  }

  /**
   * Statistiques des versements.
   *
   * Huit compteurs sur dix portaient sur les dépôts. Ceux-ci ayant disparu,
   * ils auraient affiché zéro à perpétuité : ne restent que les chiffres qui
   * décrivent réellement la file de versements.
   */
  async getStats() {
    const now   = new Date();
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const month = new Date(today.getTime() - 30 * 86400000);

    const [total, completed, rejected, pendingAll, todayCount, monthlyVolumeRaw] =
      await Promise.all([
        prisma.transaction.count(),
        prisma.transaction.aggregate({ where: { status: 'completed' }, _sum: { amount: true }, _count: true }),
        prisma.transaction.count({ where: { status: 'rejected' } }),
        prisma.transaction.aggregate({ where: { status: 'pending' }, _sum: { amount: true }, _count: true }),
        prisma.transaction.count({ where: { createdAt: { gte: today } } }),
        prisma.transaction.aggregate({ where: { status: 'completed', createdAt: { gte: month } }, _sum: { amount: true } }),
      ]);

    return {
      total_withdrawals:     total,
      completed_withdrawals: completed._count,
      rejected_withdrawals:  rejected,
      volume_withdrawals:    completed._sum.amount ?? 0,
      pending_count:         pendingAll._count,
      pending_volume:        pendingAll._sum.amount ?? 0,
      today_withdrawals:     todayCount,
      monthly_volume:        monthlyVolumeRaw._sum.amount ?? 0,
    };
  }

  /** Mettre à jour une transaction déjà traitée */
  async updateTransaction(txId: string, params: {
    status?:    string;
    adminNote?: string;
  }) {
    const tx = await prisma.transaction.findUnique({ where: { id: txId } });
    if (!tx) throw new Error('Versement introuvable.');

    return prisma.transaction.update({
      where: { id: txId },
      data:  {
        ...(params.status    ? { status: params.status as any } : {}),
        ...(params.adminNote !== undefined ? { adminNote: params.adminNote } : {}),
        processedAt: params.status && params.status !== 'pending' ? new Date() : undefined,
      },
      include: { user: { select: { pseudo: true, phoneNumber: true } } },
    });
  }

  /** Exporter CSV */
  async exportCsv(params: { status?: string; dateFrom?: string; dateTo?: string }) {
    const where: any = {};
    if (params.status) where.status = params.status;
    if (params.dateFrom || params.dateTo) {
      where.createdAt = {};
      if (params.dateFrom) where.createdAt.gte = new Date(params.dateFrom);
      if (params.dateTo)   where.createdAt.lte = new Date(params.dateTo + 'T23:59:59');
    }

    const txs = await prisma.transaction.findMany({
      where,
      include: { user: { select: { pseudo: true, phoneNumber: true } } },
      orderBy: { createdAt: 'desc' },
    });

    // La colonne « Type » ne portait plus d'information : toutes les lignes
    // sont des versements de gains de parrainage.
    const header = 'ID,Utilisateur,Téléphone,Montant,Méthode,ID 1xBet,N° Envoyeur,Statut,Note Admin,Date,Traité le';
    const rows   = txs.map(t => [
      t.id,
      t.user.pseudo,
      t.user.phoneNumber,
      t.amount,
      t.paymentMethod.replace(/_/g, ' '),
      t.xbetId ?? '',
      t.senderPhone ?? '',
      t.status,
      t.adminNote ?? '',
      t.createdAt.toISOString().replace('T', ' ').slice(0, 16),
      t.processedAt?.toISOString().replace('T', ' ').slice(0, 16) ?? '',
    ].map(v => `"${v}"`).join(','));

    return [header, ...rows].join('\n');
  }
}
