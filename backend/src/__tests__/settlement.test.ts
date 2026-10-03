import {
  _computeResult,
  _overUnderResult,
  _handicapOutcome,
  _asianHandicapResult,
  _computeCustomMarketResult,
  _resolvePronosticResult,
  type ScoreLine,
} from '../services/settlement';

/**
 * Moteur de règlement — c'est lui qui décide si la mise d'un utilisateur est
 * créditée ou débitée de sa bankroll. Une erreur ici ne lève aucune exception
 * et n'apparaît dans aucun log : elle prend simplement de l'argent à quelqu'un.
 *
 * Les cas ci-dessous sont écrits pour couvrir les pièges, pas pour faire du
 * chiffre : lignes rondes (remboursement), lignes à quart du handicap asiatique
 * (demi-mise), marchés de mi-temps quand le score MT est absent, et la
 * convention "null = résolution manuelle" plutôt qu'un verdict deviné.
 */

const s = (home: number, away: number): ScoreLine => ({ home, away });

// ─── Les 8 types historiques ─────────────────────────────────────────────────

describe('_computeResult — types de pronostic connus', () => {
  it.each([
    ['win1', 2, 0, 'WIN'], ['win1', 0, 2, 'LOSS'], ['win1', 1, 1, 'LOSS'],
    ['draw', 1, 1, 'WIN'], ['draw', 2, 0, 'LOSS'],
    ['win2', 0, 1, 'WIN'], ['win2', 1, 1, 'LOSS'],
    ['btts', 1, 1, 'WIN'], ['btts', 3, 0, 'LOSS'], ['btts', 0, 0, 'LOSS'],
  ])('%s sur %i-%i → %s', (type, h, a, attendu) => {
    expect(_computeResult(type as string, h as number, a as number)).toBe(attendu);
  });

  // « Plus de 2.5 » gagne à partir de 3 buts, pas de 2 : c'est l'erreur
  // classique du seuil inclusif.
  it.each([
    ['over25', 1, 1, 'LOSS'], ['over25', 2, 1, 'WIN'],
    ['under25', 1, 1, 'WIN'], ['under25', 2, 1, 'LOSS'],
    ['over35', 2, 1, 'LOSS'], ['over35', 2, 2, 'WIN'],
    ['under35', 2, 1, 'WIN'], ['under35', 2, 2, 'LOSS'],
  ])('%s sur %i-%i → %s (seuil non inclusif)', (type, h, a, attendu) => {
    expect(_computeResult(type as string, h as number, a as number)).toBe(attendu);
  });

  it('rend null sur un type inconnu, pour laisser la main à l’admin', () => {
    expect(_computeResult('inconnu', 1, 0)).toBeNull();
  });

  it('est insensible à la casse', () => {
    expect(_computeResult('WIN1', 2, 0)).toBe('WIN');
  });
});

// ─── Over / Under ────────────────────────────────────────────────────────────

describe('_overUnderResult', () => {
  it('rembourse sur une ligne ronde atteinte exactement', () => {
    expect(_overUnderResult(true, 2, 2)).toBe('PUSH');
    expect(_overUnderResult(false, 3, 3)).toBe('PUSH');
  });

  it('tranche normalement hors ligne ronde', () => {
    expect(_overUnderResult(true, 2.5, 3)).toBe('WIN');
    expect(_overUnderResult(true, 2.5, 2)).toBe('LOSS');
    expect(_overUnderResult(false, 2.5, 2)).toBe('WIN');
    expect(_overUnderResult(false, 2.5, 3)).toBe('LOSS');
  });

  it('traite le 0 comme un total valide', () => {
    expect(_overUnderResult(false, 0.5, 0)).toBe('WIN');
    expect(_overUnderResult(true, 0.5, 0)).toBe('LOSS');
  });
});

// ─── Handicap : lignes entières et demi-entières ─────────────────────────────

describe('_handicapOutcome', () => {
  it('rembourse quand le handicap annule exactement l’écart', () => {
    expect(_handicapOutcome('Home', -1, s(1, 0))).toBe('PUSH');
    expect(_handicapOutcome('Away', +1, s(2, 1))).toBe('PUSH');
  });

  it('tranche sur ligne entière', () => {
    expect(_handicapOutcome('Home', -1, s(2, 0))).toBe('WIN');
    expect(_handicapOutcome('Home', -1, s(0, 1))).toBe('LOSS');
  });

  it('ne rembourse jamais sur ligne demi-entière', () => {
    expect(_handicapOutcome('Home', -0.5, s(1, 0))).toBe('WIN');
    expect(_handicapOutcome('Home', -0.5, s(1, 1))).toBe('LOSS');
    expect(_handicapOutcome('Away', +0.5, s(1, 1))).toBe('WIN');
  });

  it('lit le bon côté du score pour l’extérieur', () => {
    // 1-2 : l’extérieur gagne déjà, +1 le renforce.
    expect(_handicapOutcome('Away', +1, s(1, 2))).toBe('WIN');
    expect(_handicapOutcome('Away', -1, s(1, 2))).toBe('PUSH');
    expect(_handicapOutcome('Away', -2, s(1, 2))).toBe('LOSS');
  });
});

// ─── Handicap asiatique : lignes à quart ─────────────────────────────────────

describe('_asianHandicapResult — lignes à quart', () => {
  // La mise est scindée sur les deux demi-lignes voisines. Le système n’ayant
  // que trois états, gagné+remboursé devient WIN net et perdu+remboursé LOSS
  // net — convention standard des calculateurs de handicap asiatique.
  it('-0.25 : gagne franchement quand l’équipe gagne', () => {
    expect(_asianHandicapResult('Home', -0.25, s(1, 0))).toBe('WIN');
  });

  it('-0.25 sur un nul : moitié perdue, moitié remboursée → LOSS net', () => {
    expect(_asianHandicapResult('Home', -0.25, s(0, 0))).toBe('LOSS');
  });

  it('-0.75 sur une victoire d’un but : moitié gagnée, moitié remboursée → WIN net', () => {
    expect(_asianHandicapResult('Home', -0.75, s(1, 0))).toBe('WIN');
  });

  it('-0.75 sur une victoire de deux buts : gain plein', () => {
    expect(_asianHandicapResult('Home', -0.75, s(2, 0))).toBe('WIN');
  });

  it('+0.25 sur un nul : moitié gagnée, moitié remboursée → WIN net', () => {
    expect(_asianHandicapResult('Home', +0.25, s(0, 0))).toBe('WIN');
  });

  it('+0.25 sur une défaite : perte pleine', () => {
    expect(_asianHandicapResult('Home', +0.25, s(0, 1))).toBe('LOSS');
  });

  it('délègue aux lignes non-quart sans les scinder', () => {
    expect(_asianHandicapResult('Home', -1, s(1, 0))).toBe('PUSH');
    expect(_asianHandicapResult('Home', -0.5, s(1, 0))).toBe('WIN');
    expect(_asianHandicapResult('Home', 0, s(1, 1))).toBe('PUSH');
  });

  it('gère les quarts négatifs profonds sans erreur d’arrondi', () => {
    // -1.25 = moitié sur -1, moitié sur -1.5.
    expect(_asianHandicapResult('Home', -1.25, s(2, 0))).toBe('WIN');
    expect(_asianHandicapResult('Home', -1.25, s(1, 0))).toBe('LOSS');
  });
});

// ─── Marchés personnalisés ───────────────────────────────────────────────────

const ft = s(2, 1);        // score final
const fh = s(1, 0);        // mi-temps  → 2e mi-temps déduite : 1-1

describe('_computeCustomMarketResult — vainqueur et mi-temps', () => {
  it('Match Winner', () => {
    expect(_computeCustomMarketResult('Match Winner', 'Home', ft, fh)).toBe('WIN');
    expect(_computeCustomMarketResult('Match Winner', 'Away', ft, fh)).toBe('LOSS');
    expect(_computeCustomMarketResult('Match Winner', 'Draw', ft, fh)).toBe('LOSS');
  });

  it('First Half Winner lit la mi-temps, pas le score final', () => {
    expect(_computeCustomMarketResult('First Half Winner', 'Home', ft, fh)).toBe('WIN');
  });

  it('Second Half Winner déduit correctement la 2e période', () => {
    // 2-1 final moins 1-0 à la pause = 1-1 : nul en 2e mi-temps.
    expect(_computeCustomMarketResult('Second Half Winner', 'Draw', ft, fh)).toBe('WIN');
    expect(_computeCustomMarketResult('Second Half Winner', 'Home', ft, fh)).toBe('LOSS');
  });

  it('rend null sur un marché de mi-temps quand le score MT manque', () => {
    expect(_computeCustomMarketResult('First Half Winner', 'Home', ft, null)).toBeNull();
    expect(_computeCustomMarketResult('Second Half Winner', 'Draw', ft, null)).toBeNull();
    expect(_computeCustomMarketResult('Goals Over/Under First Half', 'Over 0.5', ft, null))
      .toBeNull();
  });
});

describe('_computeCustomMarketResult — buts', () => {
  it('Both Teams Score', () => {
    expect(_computeCustomMarketResult('Both Teams Score', 'Yes', ft, fh)).toBe('WIN');
    expect(_computeCustomMarketResult('Both Teams Score', 'No', ft, fh)).toBe('LOSS');
    expect(_computeCustomMarketResult('Both Teams Score', 'Yes', s(3, 0), fh)).toBe('LOSS');
  });

  it('Goals Over/Under sur le total du match', () => {
    expect(_computeCustomMarketResult('Goals Over/Under', 'Over 2.5', ft, fh)).toBe('WIN');
    expect(_computeCustomMarketResult('Goals Over/Under', 'Under 2.5', ft, fh)).toBe('LOSS');
    expect(_computeCustomMarketResult('Goals Over/Under', 'Over 3', ft, fh)).toBe('PUSH');
  });

  it('Total - Home / Total - Away ne comptent qu’une équipe', () => {
    expect(_computeCustomMarketResult('Total - Home', 'Over 1.5', ft, fh)).toBe('WIN');
    expect(_computeCustomMarketResult('Total - Away', 'Over 1.5', ft, fh)).toBe('LOSS');
  });

  it('Odd/Even', () => {
    expect(_computeCustomMarketResult('Odd/Even', 'Odd', ft, fh)).toBe('WIN');   // 3 buts
    expect(_computeCustomMarketResult('Odd/Even', 'Even', ft, fh)).toBe('LOSS');
    expect(_computeCustomMarketResult('Home Odd/Even', 'Even', ft, fh)).toBe('WIN'); // 2
  });
});

describe('_computeCustomMarketResult — combinés', () => {
  it('Double Chance', () => {
    expect(_computeCustomMarketResult('Double Chance', 'Home/Draw', ft, fh)).toBe('WIN');
    expect(_computeCustomMarketResult('Double Chance', 'Draw/Away', ft, fh)).toBe('LOSS');
  });

  it('HT/FT Double exige les deux moitiés du combiné', () => {
    expect(_computeCustomMarketResult('HT/FT Double', 'Home/Home', ft, fh)).toBe('WIN');
    expect(_computeCustomMarketResult('HT/FT Double', 'Draw/Home', ft, fh)).toBe('LOSS');
  });

  it('Exact Score', () => {
    expect(_computeCustomMarketResult('Exact Score', '2:1', ft, fh)).toBe('WIN');
    expect(_computeCustomMarketResult('Exact Score', '1:2', ft, fh)).toBe('LOSS');
  });

  it('Highest Scoring Half', () => {
    // 1-0 puis 1-1 : la 2e mi-temps a plus de buts.
    expect(_computeCustomMarketResult('Highest Scoring Half', '2nd Half', ft, fh)).toBe('WIN');
    expect(_computeCustomMarketResult('Highest Scoring Half', '1st Half', ft, fh)).toBe('LOSS');
    expect(_computeCustomMarketResult('Highest Scoring Half', 'Draw', s(2, 0), s(1, 0)))
      .toBe('WIN'); // 1-0 puis 1-0
  });

  it('Asian Handicap passe bien la ligne au moteur asiatique', () => {
    expect(_computeCustomMarketResult('Asian Handicap', 'Home -1', ft, fh)).toBe('PUSH');
    expect(_computeCustomMarketResult('Asian Handicap', 'Home -0.25', ft, fh)).toBe('WIN');
    expect(_computeCustomMarketResult('Asian Handicap', 'Away +1', ft, fh)).toBe('PUSH');
  });
});

describe('_computeCustomMarketResult — refus explicites', () => {
  // Retourner null, c'est renvoyer le pronostic à l'arbitrage manuel de
  // l'admin. Deviner un verdict serait bien pire.
  it.each([
    ['To Qualify', 'Home'],
    ['Marché Inexistant', 'Home'],
    ['Goals Over/Under', 'Plus de 2,5'],   // valeur non anglaise → non parsable
    ['Exact Score', '2-1'],                // séparateur inattendu
    ['Match Winner', 'Domicile'],          // valeur traduite
    ['Asian Handicap', 'Home'],            // ligne manquante
  ])('null pour (%s, %s)', (marche, valeur) => {
    expect(_computeCustomMarketResult(marche, valeur, ft, fh)).toBeNull();
  });
});

// ─── Point d'entrée ──────────────────────────────────────────────────────────

describe('_resolvePronosticResult — aiguillage', () => {
  it('route les types connus vers le moteur historique', () => {
    expect(_resolvePronosticResult(
      { predictionType: 'win1', marketName: null, marketValue: null }, ft, fh)).toBe('WIN');
  });

  it('route "other" vers le moteur de marchés', () => {
    expect(_resolvePronosticResult(
      { predictionType: 'other', marketName: 'Double Chance', marketValue: 'Home/Draw' },
      ft, fh)).toBe('WIN');
  });

  it('rend null si "other" sans marché renseigné', () => {
    expect(_resolvePronosticResult(
      { predictionType: 'other', marketName: null, marketValue: null }, ft, fh)).toBeNull();
    expect(_resolvePronosticResult(
      { predictionType: 'other', marketName: 'Double Chance', marketValue: null }, ft, fh))
      .toBeNull();
  });
});
