/**
 * « Versements à effectuer » : la recherche filtre, et le total porte sur la
 * file (constat A5 de l'audit du 24 septembre 2026).
 *
 * Le panneau envoyait `search` et `method`, que la requête ignorait ; et le
 * « total à verser » additionnait la page affichée, vingt lignes.
 *
 * Banc sur la base de développement. Les autres versements en attente de la
 * base ne gênent pas : chaque recherche porte sur un marqueur propre au banc.
 */
import { prisma } from '../lib/prisma';
import { PaymentService } from '../services/payment.service';
import { BASE_LOCALE, decrireSurBaseLocale } from './aides/base_locale';

const marque = `banc-a5-${Date.now()}`;
const svc = new PaymentService();
const ids: string[] = [];

beforeAll(async () => {
  if (!BASE_LOCALE) return;
  for (const k of ['a', 'b']) {
    const u = await prisma.user.create({
      data: { pseudo: `${marque}-${k}`, referralCode: `${marque.slice(-9)}${k}`.toUpperCase() } });
    ids.push(u.id);
  }
  const versement = (userId: string, amount: number, paymentMethod: string, senderPhone: string) =>
    prisma.transaction.create({ data: { userId, type: 'withdrawal', amount, paymentMethod, senderPhone } });
  await versement(ids[0], 5000, 'orange_money', '+22698765401');
  await versement(ids[0], 2500, 'moov_money',   '+22611112222');
  await versement(ids[1], 7000, 'orange_money', '+22633334444');
});

afterAll(async () => {
  if (!BASE_LOCALE) return;
  await prisma.transaction.deleteMany({ where: { userId: { in: ids } } });
  await prisma.user.deleteMany({ where: { id: { in: ids } } });
  await prisma.$disconnect();
});

decrireSurBaseLocale('versements à effectuer (A5)', () => {
  it('la recherche par pseudo filtre, et le total porte sur les lignes trouvées', async () => {
    const r = await svc.getPendingRequests({ search: `${marque}-a` });
    expect(r.total).toBe(2);
    expect(r.total_montant).toBe(7500);
  });

  it('par numéro Mobile Money, et par méthode', async () => {
    expect((await svc.getPendingRequests({ search: '98765401' })).total).toBe(1);
    const r = await svc.getPendingRequests({ search: marque, method: 'orange_money' });
    expect(r.total).toBe(2);
    expect(r.total_montant).toBe(12000);
  });

  it('le total ne dépend pas de la page affichée', async () => {
    const r = await svc.getPendingRequests({ search: marque, perPage: 1 });
    expect(r.data).toHaveLength(1);
    expect(r.total).toBe(3);
    expect(r.total_montant).toBe(14500);
  });
});
