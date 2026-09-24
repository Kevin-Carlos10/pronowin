/**
 * Le journal d'administration : chaîné, et l'auteur attesté (A3, D02).
 *
 * Banc sur la base de développement : les entrées écrites ici sont retirées à
 * la fin. Elles sont les dernières de la chaîne, qui reste donc valable.
 */
import { prisma } from '../lib/prisma';
import { ajouterAuJournal, verifierChaine } from '../services/journal_admin.service';
import { BASE_LOCALE, decrireSurBaseLocale } from './aides/base_locale';

const acteur = { id: 'banc-journal', nom: 'Banc journal', role: 'sub' as const, perms: [] };

afterAll(async () => {
  if (!BASE_LOCALE) return;
  await prisma.journalAdmin.deleteMany({ where: { acteurId: acteur.id } });
  await prisma.$disconnect();
});

decrireSurBaseLocale('journal d\'administration chaîné', () => {
  it('vingt entrées écrites en même temps forment une chaîne intacte', async () => {
    const avant = await verifierChaine();
    expect(avant.ok).toBe(true);
    await Promise.all(Array.from({ length: 20 }, (_, i) =>
      ajouterAuJournal(acteur, {
        action: 'proof_approved', cible: `preuve-${i}`,
        // Clés dans le désordre et date : la base les rendra autrement.
        details: { z: i, a: { y: 2, b: [1, 'x'] }, quand: new Date('2026-09-24T12:00:00Z') },
        ip: '203.0.113.9',
      })));
    const apres = await verifierChaine();
    expect(apres).toEqual({ ok: true, total: avant.total + 20, rupture: null });
  });

  it('une entrée modifiée après coup casse la chaîne, à cet endroit', async () => {
    const cible = await prisma.journalAdmin.findFirst({
      where: { acteurId: acteur.id, cible: 'preuve-7' } });
    await prisma.journalAdmin.update({ where: { id: cible!.id }, data: { cible: 'preuve-effacee' } });
    const r = await verifierChaine();
    expect(r.ok).toBe(false);
    expect(r.rupture?.id).toBe(cible!.id);

    // Remise en état : la chaîne redevient valable.
    await prisma.journalAdmin.update({ where: { id: cible!.id }, data: { cible: 'preuve-7' } });
    expect((await verifierChaine()).ok).toBe(true);
  });

  it('une entrée retirée casse la chaîne à l\'entrée suivante', async () => {
    const [a, b] = await prisma.journalAdmin.findMany({
      where: { acteurId: acteur.id }, orderBy: { id: 'asc' }, take: 2 });
    const copie = { ...a };
    await prisma.journalAdmin.delete({ where: { id: a.id } });
    const r = await verifierChaine();
    expect(r.ok).toBe(false);
    expect(r.rupture?.id).toBe(b.id);
    await prisma.journalAdmin.create({ data: copie as any });
    expect((await verifierChaine()).ok).toBe(true);
  });
});
