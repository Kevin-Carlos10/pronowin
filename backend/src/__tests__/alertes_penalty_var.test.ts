/**
 * Penalties manqués et décisions de la VAR sur un penalty (8 novembre 2026),
 * comme Sofascore (« Penalty accordé »).
 */
import {
  _oublierEtatsDuDirect, messagePenaltyManque, messageVarPenalty, releverEvenements,
} from '../services/alertes_direct';
import type { AFFixture } from '../services/api_football.service';

type Ev = NonNullable<AFFixture['events']>[number];

const fixture = (events: Ev[], statut = '2H'): AFFixture => ({
  fixture: { id: 1208021, date: '2026-11-08T16:30:00Z', status: { short: statut, elapsed: 70 } },
  league: { id: 39, name: 'Premier League', logo: null },
  teams: { home: { id: 33, name: 'Manchester United', logo: null }, away: { id: 66, name: 'Aston Villa', logo: null } },
  goals: { home: 0, away: 2 },
  events,
});

const manque: Ev = { type: 'Goal', detail: 'Missed Penalty', team: { id: 33 }, player: { name: 'B. Fernandes' }, time: { elapsed: 13 } };
const varOui: Ev = { type: 'Var', detail: 'Penalty confirmed', team: { id: 33 }, time: { elapsed: 12 } };
const varNon: Ev = { type: 'Var', detail: 'Penalty cancelled', team: { id: 66 }, time: { elapsed: 55 } };
const tirAuBut: Ev = { type: 'Goal', detail: 'Missed Penalty', team: { id: 66 }, comments: 'Penalty Shootout', time: { elapsed: 120 } };

beforeEach(() => _oublierEtatsDuDirect());

describe('relevé du direct', () => {
  it('le premier relevé sert de référence, puis chaque nouvel événement une fois', () => {
    expect(releverEvenements([fixture([])]).size).toBe(0);
    let r = releverEvenements([fixture([varOui, manque])]).get(1208021)!;
    expect(r.varPenalties).toEqual([varOui]);
    expect(r.penaltiesManques).toEqual([manque]);
    // Rien de neuf : rien d'annoncé.
    expect(releverEvenements([fixture([varOui, manque])]).size).toBe(0);
    r = releverEvenements([fixture([varOui, manque, varNon])]).get(1208021)!;
    expect(r.varPenalties).toEqual([varNon]);
    expect(r.penaltiesManques).toEqual([]);
  });

  it('pas la séance de tirs au but', () => {
    releverEvenements([fixture([], 'P')]);
    expect(releverEvenements([fixture([tirAuBut], 'P')]).size).toBe(0);
  });
});

describe('messages', () => {
  const equipes = { dom: 'Manchester United', ext: 'Aston Villa' };

  it('penalty manqué', () => {
    expect(messagePenaltyManque(fixture([]), manque, equipes, 'fr')).toEqual({
      title: 'Penalty manqué par Manchester United',
      body: "B. Fernandes 13' · Manchester United 0-2 Aston Villa",
    });
    expect(messagePenaltyManque(fixture([]), manque, equipes, 'en').title).toBe('Missed penalty for Manchester United');
  });

  it('VAR : accordé, ou annulé', () => {
    expect(messageVarPenalty(fixture([]), varOui, equipes, 'fr').title).toBe('Penalty accordé à Manchester United après VAR');
    expect(messageVarPenalty(fixture([]), varNon, equipes, 'fr').title).toBe('Penalty annulé par la VAR (Aston Villa)');
    expect(messageVarPenalty(fixture([]), varOui, equipes, 'en').body).toBe("12' · Manchester United 0-2 Aston Villa");
  });
});
