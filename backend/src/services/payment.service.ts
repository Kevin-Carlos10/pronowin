import { NotificationService } from './notification.service';
import { prisma } from '../lib/prisma';
import { MIN_WITHDRAWAL } from './referral.service';

const notifSvc = new NotificationService();

/**
 * Versements Mobile Money.
 *
 * Ce service gérait un portefeuille dépôt/retrait générique : l'utilisateur
 * demandait un dépôt vers son compte 1xBet ou un retrait, l'admin validait.
 * L'écran mobile correspondant a été supprimé, plus rien n'appelait
 * `POST /payments/request` — la fonctionnalité était devenue inatteignable.
 *
 * Ce qui reste alimente une seule chose : le **versement des gains de
 * parrainage**. `ReferralService.requestWithdrawal` crée une transaction de
 * type `withdrawal` portant `metadata.source = 'referral_earnings'`, que
 * l'administrateur approuve ou rejette ici. Il n'existe plus aucun chemin
 * capable de créer un dépôt.
 */

// ─── Numéros MobCash utilisés pour verser les gains ───────────────────────────
export const MOBCASH_NUMBERS = {
  orange_money: process.env.MOBCASH_ORANGE  ?? '+22670000000',
  moov_money:   process.env.MOBCASH_MOOV    ?? '+22660000000',
  mtn_momo:     process.env.MOBCASH_MTN     ?? '+22650000000',
};

export type PaymentMethodKey = keyof typeof MOBCASH_NUMBERS;

/**
 * Cette somme a-t-elle été prélevée sur les gains de parrainage ?
 *
 * Le test conditionne le remboursement, et il doit rester strict : ne
 * recréditer que ce qui a été débité. Un versement d'une autre provenance n'a
 * jamais fait baisser `referralEarnings` ; le rembourser là créerait de
 * l'argent qui n'a jamais existé.
 *
 * `requestWithdrawal` pose `metadata.source = 'referral_earnings'` sur tout ce
 * qu'il crée, et c'est aujourd'hui le seul chemin qui crée une transaction. La
 * vérification vaut donc pour les lignes anciennes, et pour le jour où un
 * second chemin apparaîtra.
 */
function provientDesGainsParrainage(tx: { type: string; metadata: unknown }): boolean {
  if (tx.type !== 'withdrawal') return false;
  const meta = tx.metadata as { source?: unknown } | null;
  return meta?.source === 'referral_earnings';
}

export class PaymentService {

  /** Admin — traiter un versement (approuver / rejeter) */
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
    if (!tx) throw new Error('Versement introuvable.');
    if (tx.status === 'completed' || tx.status === 'rejected') {
      throw new Error('Ce versement a déjà été traité.');
    }

    /**
     * Un refus rend l'argent, et le rend une seule fois.
     *
     * `ReferralService.requestWithdrawal` déduit les gains **au moment de la
     * demande**, pour qu'on ne puisse pas demander deux fois la même somme
     * pendant que l'administrateur regarde. La contrepartie obligatoire est
     * qu'un refus les restitue — elle manquait. La transaction passait à
     * `rejected`, l'utilisateur recevait « Versement refusé », et la somme
     * restait déduite. Il perdait l'argent sans jamais le recevoir, et son
     * solde avait simplement baissé sans explication.
     *
     * Le changement de statut est conditionnel (`status: 'pending'` dans le
     * `where`) : le contrôle « déjà traité » plus haut lit puis écrit, et deux
     * administrateurs qui cliquent en même temps le passaient tous les deux.
     * Ici, la base ne laisse qu'un seul appel obtenir `count: 1` — donc un
     * seul recrédite.
     */
    const rembourse = status === 'rejected' && provientDesGainsParrainage(tx);

    const updated = await prisma.$transaction(async (t) => {
      const change = await t.transaction.updateMany({
        where: { id: transactionId, status: 'pending' },
        data:  {
          status,
          adminNote:   adminNote ?? null,
          processedBy: adminId,
          processedAt: new Date(),
        },
      });
      if (change.count === 0) return null;

      if (rembourse) {
        await t.user.update({
          where: { id: tx.userId },
          data:  { referralEarnings: { increment: tx.amount } },
        });
      }
      return t.transaction.findUnique({ where: { id: transactionId } });
    });

    if (!updated) throw new Error('Ce versement a déjà été traité.');

    // Notifier l'utilisateur.
    // Le lien profond pointait vers `/depot-retrait`, un écran supprimé du
    // mobile : la notification ouvrait une route inexistante. Il mène
    // désormais à la page parrainage, d'où part réellement la demande.
    // Sans condition sur un appareil : sendToUser garde la notification dans
    // l'historique de l'application, même quand aucune push ne peut partir.
    if (status === 'completed') {
      await notifSvc.sendToUser(tx.userId, {
        title: 'Versement effectué !',
        body:  `${tx.amount.toLocaleString()} FCFA envoyés sur votre Mobile Money.`,
        data:  { deep_link: '/parrainage', type: 'payment' },
      });
    } else {
      await notifSvc.sendToUser(tx.userId, {
        title: 'Versement refusé',
        body:  adminNote ?? 'Votre demande n\'a pas pu être traitée. Contactez le support.',
        data:  { deep_link: '/parrainage', type: 'payment' },
      });
    }

    return updated;
  }

  /** Admin — versements en attente d'approbation */
  async getPendingRequests(page = 1, perPage = 20) {
    const [items, total, contexte] = await Promise.all([
      prisma.transaction.findMany({
        where:   { status: 'pending' },
        include: { user: { select: { pseudo: true, phoneNumber: true, xbetId: true } } },
        orderBy: { createdAt: 'asc' },
        skip:    (page - 1) * perPage,
        take:    perPage,
      }),
      prisma.transaction.count({ where: { status: 'pending' } }),
      this._contexteParrainage(),
    ]);
    return { data: items, total, page, per_page: perPage, contexte };
  }

  /**
   * De quoi expliquer une file vide.
   *
   * « Aucun versement en attente » ne dit pas si le système fonctionne ou s'il
   * est en panne : la page reste vide tant qu'aucun parrain n'a demandé son
   * argent, ce qui peut durer des semaines. Ces trois chiffres répondent à la
   * question « est-ce normal ? » sans quitter l'écran.
   */
  private async _contexteParrainage() {
    const [parrains, eligibles, cumul] = await Promise.all([
      prisma.user.count({ where: { referralEarnings: { gt: 0 } } }),
      prisma.user.count({ where: { referralEarnings: { gte: MIN_WITHDRAWAL } } }),
      prisma.user.aggregate({
        where: { referralEarnings: { gt: 0 } },
        _sum:  { referralEarnings: true },
      }),
    ]);
    return {
      parrains_avec_gains: parrains,
      parrains_eligibles:  eligibles,
      total_gains:         Math.round(cumul._sum.referralEarnings ?? 0),
      seuil_retrait:       MIN_WITHDRAWAL,
    };
  }
}
