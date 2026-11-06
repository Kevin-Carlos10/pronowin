/**
 * Ce que le tableau de bord sait de la machine (constats A7 et I6).
 *
 * Le compte de service est resté en échec des semaines sans que personne ne
 * le voie, et rien ne disait quand les scores avaient été synchronisés ni ce
 * qu'il restait du quota football. Chaque tâche note désormais son issue, et
 * `/admin/sante` rassemble ce qu'il faut voir.
 */
import fs from 'fs';
import os from 'os';
import path from 'path';

const ETAT = path.join(os.tmpdir(), `sauvegarde-banc-${process.pid}.json`);
process.env.SAUVEGARDE_ETAT = ETAT;

jest.mock('../lib/prisma', () => ({
  prisma: {
    $queryRaw: jest.fn(async () => [{ '?column?': 1 }]),
    iapNotification: { groupBy: jest.fn(async () => [{ statut: 'echec', _count: { _all: 2 } }]) },
    subscriptionProof: {
      count: jest.fn(async () => 3),
      findFirst: jest.fn(async () => ({ createdAt: new Date('2026-09-22T10:00:00Z') })),
    },
  },
}));

import { _reinitialiser, etatDesTaches, noterQuota, suivre } from '../services/etat_taches';
import { lireSante } from '../services/sante.service';
import { prisma } from '../lib/prisma';

afterAll(() => { try { fs.unlinkSync(ETAT); } catch { /* déjà absent */ } });
beforeEach(() => _reinitialiser());

describe('état des tâches de fond', () => {
  it('une réussite et un échec sont notés, l\'erreur est relancée', async () => {
    await suivre('synchro', async () => 4, (n) => `${n} matchs`);
    await expect(suivre('synchro', async () => { throw new Error('quota épuisé'); })).rejects.toThrow('quota épuisé');
    const t = etatDesTaches().taches.synchro;
    expect(t.derniereReussite).not.toBeNull();
    expect(t.dernierEchec).not.toBeNull();
    expect(t.derniereErreur).toBe('quota épuisé');
    expect(t.detail).toBe('4 matchs');
  });

  it('le quota football se lit dans les en-têtes, et seulement s\'ils sont exploitables', () => {
    noterQuota({ 'x-ratelimit-requests-limit': '7500', 'x-ratelimit-requests-remaining': '312' });
    expect(etatDesTaches().quotaFootball).toMatchObject({ limite: 7500, restant: 312 });
    noterQuota({});
    expect(etatDesTaches().quotaFootball).toMatchObject({ restant: 312 });
  });
});

describe('/admin/sante', () => {
  it('rassemble base, file des stores, preuves et sauvegarde', async () => {
    fs.writeFileSync(ETAT, JSON.stringify({ derniere: '2026-09-24T02:30:00Z', taille: '2.1M', panneau: true }));
    const s = await lireSante();
    expect(s.base.ok).toBe(true);
    expect(s.fileStore).toEqual({ echec: 2 });
    expect(s.preuves).toEqual({ nombre: 3, plusAncienne: '2026-09-22T10:00:00.000Z' });
    // Sans copie hors serveur configurée (O4) : null, pas une réussite.
    expect(s.sauvegarde).toEqual({ derniere: '2026-09-24T02:30:00Z', taille: '2.1M', panneau: true, copieDistante: null });
  });

  it('la copie hors serveur est reportée, réussie ou en échec (O4)', async () => {
    fs.writeFileSync(ETAT, JSON.stringify({ derniere: '2026-09-24T02:30:00Z', taille: '2.1M', panneau: true,
      copieDistante: { distante: '2026-09-24T02:31:00Z', envoyes: ['x.dump.enc'] } }));
    expect((await lireSante()).sauvegarde?.copieDistante).toEqual({ distante: '2026-09-24T02:31:00Z' });

    fs.writeFileSync(ETAT, JSON.stringify({ derniere: '2026-09-24T02:30:00Z', taille: '2.1M', panneau: true,
      copieDistante: { erreur: 'le préfixe « prod » est lisible sans identifiants' } }));
    expect((await lireSante()).sauvegarde?.copieDistante).toEqual({ erreur: 'le préfixe « prod » est lisible sans identifiants' });
  });

  it('une base injoignable se dit, et le reste s\'affiche quand même', async () => {
    (prisma.$queryRaw as jest.Mock).mockRejectedValueOnce(new Error('ECONNREFUSED'));
    fs.unlinkSync(ETAT);
    const s = await lireSante();
    expect(s.base.ok).toBe(false);
    expect(s.sauvegarde).toBeNull();
    expect(s.preuves).not.toBeNull();
  });
});
