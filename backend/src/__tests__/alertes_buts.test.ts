/**
 * Alertes de but pour les matchs suivis (18 octobre 2026).
 *
 * Le favori ou le pari sur un match donnait le coup d'envoi et la fin, rien
 * entre les deux. Chaque but est désormais annoncé — une fois, avec le
 * buteur quand il est sûr, et jamais en salve au redémarrage du serveur.
 */
import { messageDeBut, releverScores, _oublierScoresDuDirect } from '../services/alertes_direct';
import type { AFFixture } from '../services/api_football.service';

const T0 = Date.UTC(2026, 9, 18, 15, 0, 0);

function rencontre(id: number, dom: number, ext: number, o: {
  elapsed?: number; extra?: number | null; statut?: string; buts?: Array<[number, string, string, number?]>;
} = {}): AFFixture {
  return {
    fixture: { id, date: '2026-10-18T14:00:00+00:00', status: { short: o.statut ?? '1H', elapsed: o.elapsed ?? 24, extra: o.extra ?? null } },
    league: { id: 39, name: 'Premier League', logo: null },
    teams: { home: { id: 42, name: 'Arsenal', logo: null }, away: { id: 49, name: 'Chelsea', logo: null } },
    goals: { home: dom, away: ext },
    // [minute, équipe (42 ou 49), détail, temps additionnel]
    events: (o.buts ?? []).map(([minute, equipe, detail, extra]) => ({
      time: { elapsed: minute, extra: extra ?? null }, team: { id: equipe === 'dom' ? 42 : 49 },
      player: { name: detail === 'Own Goal' ? 'R. James' : equipe === 'dom' ? 'B. Saka' : 'C. Palmer' },
      type: 'Goal', detail,
    })),
  };
}
const equipes = { dom: 'Arsenal', ext: 'Chelsea' };

describe('le texte de l\'alerte', () => {
  it('un but, buteur et minute de l\'événement', () => {
    const f = rencontre(1, 1, 0, { buts: [[23, 'dom', 'Normal Goal']] });
    expect(messageDeBut(f, { dom: 0, ext: 0 }, equipes, 'fr'))
      .toEqual({ title: 'But pour Arsenal !', body: 'Arsenal 1-0 Chelsea · B. Saka 23\'' });
    expect(messageDeBut(f, { dom: 0, ext: 0 }, equipes, 'en'))
      .toEqual({ title: 'Goal for Arsenal!', body: 'Arsenal 1-0 Chelsea · B. Saka 23\'' });
  });

  it('événements en retard sur le score : pas de buteur (ce serait le précédent), la minute du jeu', () => {
    const f = rencontre(1, 2, 0, { elapsed: 61, buts: [[23, 'dom', 'Normal Goal']] });
    expect(messageDeBut(f, { dom: 1, ext: 0 }, equipes, 'fr')?.body).toBe('Arsenal 2-0 Chelsea · 61\'');
  });

  it('penalty et temps additionnel', () => {
    const f = rencontre(1, 1, 1, { elapsed: 90, extra: 4, buts: [[23, 'dom', 'Normal Goal'], [90, 'ext', 'Penalty', 3]] });
    expect(messageDeBut(f, { dom: 1, ext: 0 }, equipes, 'fr'))
      .toEqual({ title: 'But pour Chelsea !', body: 'Arsenal 1-1 Chelsea · C. Palmer (pen.) 90+3\'' });
  });

  it('but contre son camp : l\'équipe qui en profite, sans nom de joueur', () => {
    const f = rencontre(1, 0, 1, { elapsed: 12, buts: [[11, 'dom', 'Own Goal']] });
    expect(messageDeBut(f, { dom: 0, ext: 0 }, equipes, 'fr'))
      .toEqual({ title: 'But pour Chelsea !', body: 'Arsenal 0-1 Chelsea · 12\'' });
  });

  it('un penalty manqué ne compte pas comme un but listé', () => {
    const f = rencontre(1, 1, 0, { buts: [[10, 'ext', 'Missed Penalty'], [23, 'dom', 'Normal Goal']] });
    expect(messageDeBut(f, { dom: 0, ext: 0 }, equipes, 'fr')?.body).toBe('Arsenal 1-0 Chelsea · B. Saka 23\'');
  });

  it('score qui baisse : but annulé', () => {
    const f = rencontre(1, 1, 0, { elapsed: 67 });
    expect(messageDeBut(f, { dom: 1, ext: 1 }, equipes, 'fr'))
      .toEqual({ title: 'But annulé pour Chelsea', body: 'Arsenal 1-0 Chelsea · 67\'' });
    expect(messageDeBut(f, { dom: 1, ext: 1 }, equipes, 'en')?.title).toBe('Goal disallowed for Chelsea');
  });

  it('les deux camps à la fois : score mis à jour', () => {
    const f = rencontre(1, 1, 1, { elapsed: 30 });
    expect(messageDeBut(f, { dom: 0, ext: 0 }, equipes, 'fr'))
      .toEqual({ title: 'Score mis à jour', body: 'Arsenal 1-1 Chelsea · 30\'' });
  });

  it('sélections nationales : le nom du pays dans la langue de l\'appareil', () => {
    const f = rencontre(1, 1, 0, { elapsed: 5 });
    const pays = { dom: 'Belgium', ext: 'Germany' };
    expect(messageDeBut(f, { dom: 0, ext: 0 }, pays, 'fr')?.title).toBe('But pour Belgique !');
    expect(messageDeBut(f, { dom: 0, ext: 0 }, pays, 'en')?.title).toBe('Goal for Belgium!');
  });

  it('score inchangé : pas d\'alerte', () => {
    expect(messageDeBut(rencontre(1, 1, 0), { dom: 1, ext: 0 }, equipes, 'fr')).toBeNull();
  });
});

describe('le relevé des scores du direct', () => {
  beforeEach(() => _oublierScoresDuDirect());

  it('premier relevé : référence, aucun but annoncé', () => {
    expect(releverScores([rencontre(1, 2, 1)], T0).size).toBe(0);
  });

  it('un changement est rendu une fois, avec le score d\'avant', () => {
    releverScores([rencontre(1, 0, 0)], T0);
    const c = releverScores([rencontre(1, 1, 0)], T0 + 15_000);
    expect([...c.keys()]).toEqual([1]);
    expect(c.get(1)!.avant).toEqual({ dom: 0, ext: 0 });
    expect(releverScores([rencontre(1, 1, 0)], T0 + 30_000).size).toBe(0);
  });

  it('un match qui sort un instant du direct garde son score ; oublié après 15 minutes', () => {
    releverScores([rencontre(1, 0, 0)], T0);
    releverScores([], T0 + 60_000);
    expect(releverScores([rencontre(1, 1, 0)], T0 + 120_000).size).toBe(1);
    releverScores([], T0 + 20 * 60_000);
    expect(releverScores([rencontre(1, 2, 0)], T0 + 21 * 60_000).size).toBe(0);
  });

  it('score absent : ignoré', () => {
    releverScores([rencontre(1, 0, 0)], T0);
    const sansScore = { ...rencontre(1, 0, 0), goals: { home: null, away: null } };
    expect(releverScores([sansScore], T0 + 15_000).size).toBe(0);
  });
});

describe('dans la synchronisation des scores', () => {
  // Chargés ici : le service des pronostics tire la base, simulée ci-dessous.
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const { prisma } = require('../lib/prisma');
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const { apiFootballService } = require('../services/api_football.service');
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const { NotificationService } = require('../services/notification.service');
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const { PronosticsService, _oublierDirectPrecedent } = require('../services/pronostics.service');

  let envois: Array<{ userId: string; title: string; body: string; titleEn?: string; data: any }>;
  /** Le match tel qu'en base, modifiable entre deux cycles (la liste des matchs y écrit aussi). */
  let enBase: any;

  beforeEach(() => {
    _oublierDirectPrecedent();
    envois = [];
    enBase = { id: 'm1', externalId: 1, status: 'LIVE', homeTeam: 'Arsenal', awayTeam: 'Chelsea',
      homeScore: 0, awayScore: 0, homeScoreHT: null, awayScoreHT: null, elapsedMinutes: 20,
      matchDate: new Date('2026-10-18T14:00:00+00:00') };
    jest.spyOn(NotificationService.prototype, 'sendToUser').mockImplementation(async (...a: any[]) => {
      envois.push({ userId: a[0], ...a[1] }); return { success: true };
    });
    jest.spyOn(prisma.match, 'findMany').mockResolvedValue([]);
    jest.spyOn(prisma.match, 'findUnique').mockImplementation(async () => ({ ...enBase }));
    jest.spyOn(prisma.match, 'update').mockImplementation(async ({ data }: any) => {
      enBase = { ...enBase, ...data, elapsedMinutes: data.elapsedMinutes ?? enBase.elapsedMinutes }; return enBase;
    });
    jest.spyOn(prisma.pronostic, 'findMany').mockResolvedValue([]);
    jest.spyOn(prisma.pronostic, 'findUnique').mockResolvedValue({ id: 'p1' });
    jest.spyOn(prisma.userFavoriteMatch, 'findMany').mockResolvedValue([{ userId: 'u1' }, { userId: 'u2' }]);
    // u2 suit aussi le pronostic dans sa bankroll : une seule alerte.
    jest.spyOn(prisma.bankrollBet, 'findMany').mockResolvedValue([{ bankroll: { userId: 'u2' } }, { bankroll: { userId: 'u3' } }]);
  });
  afterEach(() => jest.restoreAllMocks());

  async function cycle(direct: AFFixture[]) {
    jest.spyOn(apiFootballService, 'getLiveFixtures').mockResolvedValue(direct);
    jest.spyOn(apiFootballService, 'getAllLiveAndRecentFixtures').mockResolvedValue(direct);
    await new PronosticsService().syncMatchScores();
  }
  const buts = () => envois.filter(e => e.data.type === 'match');

  it('un but : une alerte par suiveur (favori ou pari), lien vers le pronostic', async () => {
    await cycle([rencontre(1, 0, 0, { elapsed: 20 })]);
    expect(envois).toEqual([]);
    await cycle([rencontre(1, 1, 0, { elapsed: 24, buts: [[23, 'dom', 'Normal Goal']] })]);
    expect(buts().map(e => e.userId).sort()).toEqual(['u1', 'u2', 'u3']);
    expect(buts()[0]).toMatchObject({
      title: 'But pour Arsenal !', body: 'Arsenal 1-0 Chelsea · B. Saka 23\'', titleEn: 'Goal for Arsenal!',
      data: { type: 'match', deep_link: '/pronostics/p1', match_id: 'm1' },
    });
    // Cycle suivant, même score : rien de plus.
    await cycle([rencontre(1, 1, 0, { elapsed: 25, buts: [[23, 'dom', 'Normal Goal']] })]);
    expect(buts()).toHaveLength(3);
  });

  it('la liste des matchs a déjà écrit le nouveau score en base : le but est quand même annoncé', async () => {
    await cycle([rencontre(1, 0, 0, { elapsed: 20 })]);
    enBase = { ...enBase, homeScore: 1, elapsedMinutes: 24 };
    await cycle([rencontre(1, 1, 0, { elapsed: 24 })]);
    expect(buts()).toHaveLength(3);
  });

  it('un score plus ancien réécrit en base ne fait pas annoncer deux fois le même but', async () => {
    await cycle([rencontre(1, 0, 0, { elapsed: 20 })]);
    await cycle([rencontre(1, 1, 0, { elapsed: 24 })]);
    enBase = { ...enBase, homeScore: 0 };          // relevé périmé écrit par-dessus
    await cycle([rencontre(1, 1, 0, { elapsed: 25 })]);
    expect(buts()).toHaveLength(3);
  });

  it('redémarrage du serveur en plein match : aucune salve d\'alertes', async () => {
    enBase = { ...enBase, homeScore: 2, awayScore: 1, elapsedMinutes: 70 };
    await cycle([rencontre(1, 2, 1, { elapsed: 71 })]);
    expect(envois).toEqual([]);
  });

  it('match sans pronostic : le lien ouvre la fiche du match', async () => {
    jest.spyOn(prisma.pronostic, 'findUnique').mockResolvedValue(null);
    await cycle([rencontre(1, 0, 0)]);
    await cycle([rencontre(1, 0, 1)]);
    expect(buts().map(e => e.userId).sort()).toEqual(['u1', 'u2']);   // pas de pari sans pronostic
    expect(buts()[0].data.deep_link).toBe('/pronostics/m1');
  });

  describe('coup d\'envoi', () => {
    const coupsEnvoi = () => envois.filter(e => e.data.type === 'match_live');

    it('déjà « en direct » en base (écrit par la liste) : annoncé à l\'entrée dans le direct, une fois', async () => {
      await cycle([]);                                   // avant le coup d'envoi
      enBase = { ...enBase, elapsedMinutes: null };
      await cycle([rencontre(1, 0, 0, { elapsed: 1 })]);
      expect(coupsEnvoi().map(e => e.userId).sort()).toEqual(['u1', 'u2', 'u3']);
      expect(coupsEnvoi()[0]).toMatchObject({ title: 'Match en direct !', data: { deep_link: '/pronostics/p1' } });
      await cycle([rencontre(1, 0, 0, { elapsed: 2 })]);
      expect(coupsEnvoi()).toHaveLength(3);
    });

    it('statut rétrogradé en base puis repassé en direct : pas de second coup d\'envoi', async () => {
      enBase = { ...enBase, status: 'SCHEDULED', elapsedMinutes: null };
      await cycle([rencontre(1, 0, 0, { elapsed: 1 })]);
      expect(coupsEnvoi()).toHaveLength(3);
      enBase = { ...enBase, status: 'SCHEDULED' };
      await cycle([rencontre(1, 0, 0, { elapsed: 2 })]);
      expect(coupsEnvoi()).toHaveLength(3);
    });

    it('au premier relevé après un redémarrage, un match déjà en cours n\'est pas annoncé', async () => {
      await cycle([rencontre(1, 0, 0, { elapsed: 3 })]);
      expect(coupsEnvoi()).toHaveLength(0);
    });
  });
});
