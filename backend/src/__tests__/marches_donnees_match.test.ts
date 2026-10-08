/**
 * Les marchés 1xBet de la phase 2 : réglés avec les événements et les
 * statistiques du match, lus auprès du fournisseur une fois le match fini.
 *
 * Un match complet, tel que le fournisseur le décrit — Aston Villa (66) –
 * Brentford (55), 1-0 à la pause, 2-2 à la fin :
 *   12'   Villa, but
 *   30'   Villa, carton jaune
 *   52'   Brentford, penalty marqué                      1-1
 *   60'   Brentford, carton jaune
 *   70'   Villa, penalty manqué
 *   78'   but contre son camp d'un joueur de Brentford     2-1
 *   85'   Brentford, deuxième jaune (expulsion)
 *   90+3' Brentford, but                                   2-2
 * Corners 6 – 4, cartons jaunes 1 – 2, un rouge.
 */
import { normaliserDonnees, resoudrePronostic, ATTENTE_APRES_COUP_ENVOI } from '../services/donnees_reglement';

// eslint-disable-next-line @typescript-eslint/no-var-requires
const { MARCHES, encoder, regler, LIGNES_PAR_OPTION } = require('../marches/complementaires');

const ev = (elapsed: number, extra: number | null, team: number, type: string, detail: string) =>
  ({ time: { elapsed, extra }, team: { id: team }, type, detail });

function fiche(options: { statut?: string; sans?: number; ownGoalTeam?: number; events?: any[] } = {}) {
  const events = options.events ?? [
    ev(12, null, 66, 'Goal', 'Normal Goal'),
    ev(30, null, 66, 'Card', 'Yellow Card'),
    ev(52, null, 55, 'Goal', 'Penalty'),
    ev(60, null, 55, 'Card', 'Yellow Card'),
    ev(64, null, 66, 'subst', 'Substitution 1'),
    ev(70, null, 66, 'Goal', 'Missed Penalty'),
    // Le fournisseur nomme ici l'équipe du joueur (Brentford) ; l'autre
    // convention est essayée plus bas.
    ev(78, null, options.ownGoalTeam ?? 55, 'Goal', 'Own Goal'),
    ev(85, null, 55, 'Card', 'Second Yellow card'),
    ev(90, 3, 55, 'Goal', 'Normal Goal'),
  ].filter((_, i) => i !== options.sans);
  return {
    fixture: { id: 1, status: { short: options.statut ?? 'FT' } },
    teams: { home: { id: 66 }, away: { id: 55 } },
    events,
    statistics: [
      { team: { id: 66 }, statistics: [{ type: 'Corner Kicks', value: 6 }, { type: 'Yellow Cards', value: 1 }, { type: 'Red Cards', value: null }] },
      { team: { id: 55 }, statistics: [{ type: 'Corner Kicks', value: 4 }, { type: 'Yellow Cards', value: 2 }, { type: 'Red Cards', value: 1 }] },
    ],
  };
}

const FT = { home: 2, away: 2 }, FH = { home: 1, away: 0 };
const D = normaliserDonnees(fiche());
const r = (nom: string, valeur: string, donnees = D) => regler(nom, valeur, FT, FH, donnees);

describe('les données du fournisseur', () => {
  it('ramenées à ce que les marchés lisent', () => {
    expect(D!.prolongation).toBe(false);
    expect(D!.evenements[0]).toEqual({ minute: 12, extra: null, equipe: 'Home', type: 'Goal', detail: 'Normal Goal' });
    // `null` pour zéro chez le fournisseur.
    expect(D!.stats).toEqual({ Home: { corners: 6, jaunes: 1, rouges: null }, Away: { corners: 4, jaunes: 2, rouges: 1 } });
  });

  it('un match non terminé ne donne rien', () => {
    expect(normaliserDonnees(fiche({ statut: '2H' }))).toBeNull();
    expect(normaliserDonnees(null)).toBeNull();
  });
});

describe('les buts et leur minute', () => {
  it('résultat, double chance et total à la minute (incluse)', () => {
    expect(r('Result At Minute', '45 / Home')).toBe('WIN');     // 1-0
    expect(r('Result At Minute', '60 / Draw')).toBe('WIN');     // 1-1
    expect(r('Result At Minute', '80 / Home')).toBe('WIN');     // 2-1
    expect(r('Result At Minute', '80 / Draw')).toBe('LOSS');
    expect(r('Double Chance At Minute', '75 / X2')).toBe('WIN');
    expect(r('Total At Minute', '30 / Over 0.5')).toBe('WIN');
    expect(r('Total At Minute', '10 / Over 0.5')).toBe('LOSS');
  });

  it('les deux équipes marquent avant la minute, but dans le temps additionnel', () => {
    expect(r('Both Teams To Score By Minute', '60 / Yes')).toBe('WIN');
    expect(r('Both Teams To Score By Minute', '45 / Yes')).toBe('LOSS');
    expect(r('Goal In Added Time', 'Yes')).toBe('WIN');           // 90+3
  });

  it('premier à n buts, marque le premier et perd', () => {
    expect(r('First To Score Goals', '2 / Home')).toBe('WIN');     // Villa à la 78e, Brentford à la 90+3
    expect(r('First To Score Goals', '1 / Away')).toBe('LOSS');
    expect(r('First To Score Goals', '3 / Neither')).toBe('WIN');
    expect(r('Score First And Lose', 'Home / Yes')).toBe('LOSS');  // Villa a marqué le premier, mais nul
    expect(r('Score First And Lose', 'Home / No')).toBe('WIN');
  });

  it('contre son camp, penalty, expulsion', () => {
    expect(r('Own Goal', 'Yes')).toBe('WIN');
    expect(r('Penalty Awarded', 'Yes')).toBe('WIN');
    expect(r('Red Card', 'Yes')).toBe('WIN');                      // deuxième jaune
    expect(r('Penalty Awarded Or Red Card', 'No')).toBe('LOSS');
  });

  it('un penalty manqué n\'est pas un but, mais reste un penalty accordé', () => {
    const sansPenaltyMarque = normaliserDonnees(fiche({ sans: 2 }));
    // Sans le 52e, les buts ne retombent plus sur 2-2 : rien n'est réglé…
    expect(regler('Penalty Awarded', 'Yes', FT, FH, sansPenaltyMarque)).toBeNull();
    // …et sur le score qu'ils décrivent (2-1), le penalty manqué compte.
    expect(regler('Penalty Awarded', 'Yes', { home: 2, away: 1 }, FH, sansPenaltyMarque)).toBe('WIN');
  });

  it('le but contre son camp, quelle que soit l\'équipe que le fournisseur nomme', () => {
    const autreConvention = normaliserDonnees(fiche({ ownGoalTeam: 66 }));
    expect(regler('Result At Minute', '80 / Home', FT, FH, autreConvention)).toBe('WIN');
  });
});

describe('ce qui laisse le pronostic à la main', () => {
  it('un but absent du flux', () => {
    expect(regler('Result At Minute', '80 / Home', FT, FH, normaliserDonnees(fiche({ sans: 8 })))).toBeNull();
  });

  it('un match allé en prolongation', () => {
    const aet = normaliserDonnees(fiche({ statut: 'AET' }));
    expect(regler('Result At Minute', '45 / Home', FT, FH, aet)).toBeNull();
    expect(regler('Total Corners', 'Over 9.5', FT, FH, aet)).toBeNull();
  });

  it('un flux d\'événements vide, ou aucune donnée', () => {
    expect(regler('Penalty Awarded', 'No', { home: 0, away: 0 }, { home: 0, away: 0 }, normaliserDonnees(fiche({ events: [] })))).toBeNull();
    expect(regler('Red Card', 'No', FT, FH, null)).toBeNull();
  });

  it('des statistiques absentes', () => {
    const sansStats = { ...D!, stats: null };
    expect(regler('Total Corners', 'Over 9.5', FT, FH, sansStats)).toBeNull();
  });
});

describe('corners et cartons', () => {
  it('totaux, équipe, vainqueur et combiné', () => {
    expect(r('Total Corners', 'Over 9.5')).toBe('WIN');            // 10
    expect(r('Total Corners', 'Over 10.5')).toBe('LOSS');
    expect(r('Team Total Corners', 'Away / Under 4.5')).toBe('WIN');
    expect(r('Corners 1X2', 'Home')).toBe('WIN');
    expect(r('Result/Total Corners', 'Draw / Over 9.5 / Yes')).toBe('WIN');
    expect(r('Result/Total Corners', 'Home / Over 9.5 / Yes')).toBe('LOSS');
    expect(r('Total Yellow Cards', 'Over 2.5')).toBe('WIN');       // 1 + 2
  });
});

describe('le panneau et le moteur parlent la même langue', () => {
  const exemples: Record<string, unknown> = {
    equipe: 'Away', issue: 'Draw', issueMt: 'Home', double: 'X2', ouiNon: 'No', minute: '45',
    nButs: '2', premier: 'Neither', total: 'Under 2.5', auMoins: 'Over 0.5', corners: 'Over 9.5',
    cornersEquipe: 'Under 4.5', cartons: 'Over 2.5', handicap: -2,
  };
  it('chaque valeur construite par le panneau est réglée, données comprises', () => {
    for (const m of MARCHES as { nom: string; options: string[] }[]) {
      const valeur = encoder(m.nom, Object.fromEntries(m.options.map(o => [o, exemples[o]])));
      expect([m.nom, valeur]).toEqual([m.nom, expect.any(String)]);
      expect([m.nom, regler(m.nom, valeur, FT, FH, D)]).toEqual([m.nom, expect.stringMatching(/^(WIN|LOSS)$/)]);
    }
    expect(LIGNES_PAR_OPTION.corners).toContain(9.5);
  });
});

describe('le règlement d\'un pronostic, au bon moment', () => {
  const prono = { predictionType: 'other', marketName: 'Result At Minute', marketValue: '80 / Home' };
  const coupEnvoi = new Date('2026-10-10T14:00:00Z');
  const match = (id: number) => ({ source: 'API_FOOTBALL', externalId: id, matchDate: coupEnvoi });

  it('attend 2 h 15 après le coup d\'envoi, puis lit le fournisseur une seule fois', async () => {
    const lireFiche = jest.fn(async () => fiche());
    const t = coupEnvoi.getTime();
    expect(await resoudrePronostic(prono, match(901), FT, FH, { maintenant: t + 2 * 3600_000, lireFiche })).toBeNull();
    expect(lireFiche).not.toHaveBeenCalled();
    const apres = t + ATTENTE_APRES_COUP_ENVOI + 60_000;
    expect(await resoudrePronostic(prono, match(901), FT, FH, { maintenant: apres, lireFiche })).toBe('WIN');
    expect(await resoudrePronostic(prono, match(901), FT, FH, { maintenant: apres + 60_000, lireFiche })).toBe('WIN');
    expect(lireFiche).toHaveBeenCalledTimes(1);
  });

  it('abandonne au bout de trois jours, et ignore un match d\'une autre source', async () => {
    const lireFiche = jest.fn(async () => fiche());
    expect(await resoudrePronostic(prono, match(902), FT, FH,
      { maintenant: coupEnvoi.getTime() + 4 * 24 * 3600_000, lireFiche })).toBeNull();
    expect(await resoudrePronostic(prono, { ...match(903), source: 'FOOTBALL_DATA' }, FT, FH,
      { maintenant: coupEnvoi.getTime() + 3 * 3600_000, lireFiche })).toBeNull();
    expect(lireFiche).not.toHaveBeenCalled();
  });

  it('un marché réglé par le score n\'appelle pas le fournisseur', async () => {
    const lireFiche = jest.fn();
    expect(await resoudrePronostic({ predictionType: 'win1', marketName: null, marketValue: null },
      match(904), { home: 2, away: 1 }, null, { lireFiche })).toBe('WIN');
    expect(await resoudrePronostic({ predictionType: 'other', marketName: 'To Win Either Half', marketValue: 'Away / Yes' },
      match(904), { home: 1, away: 2 }, { home: 1, away: 0 }, { lireFiche })).toBe('WIN');
    expect(lireFiche).not.toHaveBeenCalled();
  });
});
