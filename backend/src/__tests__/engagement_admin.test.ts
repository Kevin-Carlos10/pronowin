/**
 * L'engagement sur le tableau de bord (25 octobre 2026) : suivis, notifications
 * par famille et part lue, articles écrits seuls, adoption des versions,
 * paiements Mobile Money.
 */
import { familleNotification, compareVersions, resumeEngagement } from '../services/engagement_admin.service';

describe('la famille d\'une notification, d\'après son titre', () => {
  it.each([
    ['But pour Arsenal !', 'buts'],
    ['But annulé pour Chelsea', 'buts_annules'],
    ['Score mis à jour', 'buts_annules'],
    ['Match en direct !', 'coup_envoi'],
    ['Mi-temps', 'mi_temps'],
    ['Carton rouge pour Lens', 'cartons'],
    ['Compositions officielles', 'compositions'],
    ['Fin de match : Arsenal 2-1 Chelsea', 'fin_match'],
    ['Le résumé est prêt', 'resume_pret'],
    ['Pronostic gagnant !', 'resultats'],
    ['Pronostic perdant', 'resultats'],
    ['Pronostic remboursé', 'resultats'],
    ['Résultat corrigé : Lyon – Nice', 'resultats'],
    ['Bienvenue Premium !', 'premium'],
    ['⏳ Ton Premium expire demain', 'premium'],
    ['Preuve refusée', 'premium'],
    ['Bilan de la semaine', 'bilan_hebdo'],
    ['Nouveau filleul !', 'autres'],
  ])('%s → %s', (titre, cle) => expect(familleNotification(titre).cle).toBe(cle));
});

it('1.0.30 est plus récente que 1.0.9 et que 1.0.29', () => {
  expect(['1.0.9', '1.0.30', '1.0.29', '1.0.18'].sort(compareVersions)).toEqual(['1.0.9', '1.0.18', '1.0.29', '1.0.30']);
});

describe('le résumé', () => {
  // Base simulée : les méthodes Prisma ne se typent pas comme de simples promesses.
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const { prisma } = require('../lib/prisma');
  const MAINTENANT = new Date(Date.UTC(2026, 9, 25, 12, 0, 0));
  const lectures: Record<string, any> = {};
  afterEach(() => jest.restoreAllMocks());

  beforeEach(() => {
    jest.spyOn(prisma.userFavoriteMatch, 'findMany').mockImplementation(async (args: any) => {
      if (args.where.match) { lectures.suivis = args; return [
        { userId: 'u1', matchId: 'm1' }, { userId: 'u1', matchId: 'm2' }, { userId: 'u2', matchId: 'm1' }]; }
      lectures.nouveaux = args;
      return [{ userId: 'u1' }, { userId: 'u3' }, { userId: 'u3' }];
    });
    jest.spyOn(prisma.notification, 'groupBy').mockImplementation(async (args: any) => {
      lectures.notifs = args;
      return [
        { title: 'But pour Arsenal !', isRead: false, _count: { _all: 6 } },
        { title: 'But pour Chelsea !', isRead: true,  _count: { _all: 2 } },
        { title: 'Le résumé est prêt', isRead: true,  _count: { _all: 1 } },
        { title: 'Le résumé est prêt', isRead: false, _count: { _all: 3 } },
        { title: 'Nouveau filleul !',  isRead: false, _count: { _all: 1 } },
      ];
    });
    jest.spyOn(prisma.resumeMatch, 'count').mockImplementation(async (args: any) =>
      args.where.genre === 'resume' ? 41 : 12);
    jest.spyOn(prisma.versionAppCompte, 'groupBy').mockImplementation(async (args: any) => {
      lectures.versions = args;
      return [
        { plateforme: 'android', canal: 'store',  version: '1.0.23', _count: { _all: 48 } },
        { plateforme: 'android', canal: 'store',  version: '1.0.18', _count: { _all: 33 } },
        { plateforme: 'android', canal: 'direct', version: '1.0.30', _count: { _all: 2 } },
        { plateforme: 'ios',     canal: 'store',  version: '1.0.23', _count: { _all: 3 } },
      ];
    });
    jest.spyOn(prisma.paiementGeniusPay, 'aggregate').mockImplementation(async (args: any) => {
      lectures.paiements = args;
      return { _count: { _all: 2 }, _sum: { montant: 12000 } };
    });
  });

  it('suivis, notifications par famille et part lue, articles, versions, paiements — sur 7 jours', async () => {
    const r = await resumeEngagement({}, MAINTENANT);
    const il7j = new Date(MAINTENANT.getTime() - 7 * 86_400_000);
    expect(r.jours).toBe(7);
    // Les suivis qui servent encore : matchs à venir ou en cours.
    expect(lectures.suivis.where).toEqual({ match: { status: { in: ['SCHEDULED', 'LIVE'] } } });
    expect(r.suivis).toEqual({ matchs: 2, personnes: 2, nouveaux: 3, nouveauxPersonnes: 2 });
    expect(lectures.nouveaux.where).toEqual({ createdAt: { gte: il7j } });

    expect(lectures.notifs.where).toEqual({ createdAt: { gte: il7j } });
    expect(r.notifications.creees).toBe(13);
    expect(r.notifications.lues).toBe(3);
    expect(r.notifications.familles).toEqual([
      { cle: 'buts', libelle: 'Buts', creees: 8, lues: 2 },
      { cle: 'resume_pret', libelle: 'Résumé prêt', creees: 4, lues: 1 },
      { cle: 'autres', libelle: 'Autres (campagnes, parrainage…)', creees: 1, lues: 0 },
    ]);

    expect(r.contenus).toEqual({ resumes: 41, avantMatchs: 12 });

    // Les appareils vus depuis 30 jours ; la version la plus récente vue : 1.0.30.
    expect(lectures.versions.where).toEqual({ vuLe: { gte: new Date(MAINTENANT.getTime() - 30 * 86_400_000) } });
    expect(r.versions.cible).toBe('1.0.30');
    expect(r.versions.comptes).toBe(86);
    expect(r.versions.aJour).toBe(2);
    expect(r.versions.parCanal[0]).toEqual({ plateforme: 'android', canal: 'store', comptes: 81, aJour: 0,
      versions: [{ version: '1.0.23', comptes: 48 }, { version: '1.0.18', comptes: 33 }] });

    // Seuls les vrais paiements, accordés dans la période.
    expect(lectures.paiements.where).toEqual({ environnement: 'live', premiumAccordeLe: { gte: il7j } });
    expect(r.mobileMoney).toEqual({ payes: 2, brut: 12000 });
  });

  it('sur 30 jours ; toute autre période revient à 7', async () => {
    expect((await resumeEngagement({ jours: 30 }, MAINTENANT)).jours).toBe(30);
    expect((await resumeEngagement({ jours: 365 }, MAINTENANT)).jours).toBe(7);
  });

  it('aucune donnée : des zéros, pas d\'erreur', async () => {
    jest.spyOn(prisma.userFavoriteMatch, 'findMany').mockResolvedValue([]);
    jest.spyOn(prisma.notification, 'groupBy').mockResolvedValue([]);
    jest.spyOn(prisma.versionAppCompte, 'groupBy').mockResolvedValue([]);
    jest.spyOn(prisma.paiementGeniusPay, 'aggregate').mockResolvedValue({ _count: { _all: 0 }, _sum: { montant: null } });
    const r = await resumeEngagement({}, MAINTENANT);
    expect(r.suivis).toEqual({ matchs: 0, personnes: 0, nouveaux: 0, nouveauxPersonnes: 0 });
    expect(r.notifications).toEqual({ creees: 0, lues: 0, familles: [] });
    expect(r.versions).toEqual({ cible: null, comptes: 0, aJour: 0, parCanal: [] });
    expect(r.mobileMoney).toEqual({ payes: 0, brut: 0 });
  });
});
