/**
 * Moteur de règlement — décide si un pronostic est gagnant, perdant ou
 * remboursé à partir du score final (et du score à la mi-temps).
 *
 * Extrait de `pronostics.service.ts` pour une raison précise : ce sont les
 * seules fonctions de l'application dont une erreur **retire de l'argent aux
 * utilisateurs sans le dire**. `settleBets` crédite et débite les bankrolls à
 * partir de leur verdict ; une régression ici est silencieuse. Isolées et
 * exportées, elles se testent sans base de données ni Prisma — voir
 * `__tests__/settlement.test.ts`.
 *
 * Tout est pur : score en entrée, verdict en sortie. Aucun accès réseau,
 * aucun état.
 */

// Calcule WIN ou LOSS selon le type de pronostic et le score final
export function _computeResult(
  type: string,
  home: number,
  away: number,
): 'WIN' | 'LOSS' | null {
  const total = home + away;
  const correct = (() => {
    switch (type.toLowerCase()) {
      case 'win1':    return home > away;
      case 'draw':    return home === away;
      case 'win2':    return away > home;
      case 'btts':    return home > 0 && away > 0;
      case 'over25':  return total > 2;
      case 'under25': return total < 3;
      case 'over35':  return total > 3;
      case 'under35': return total < 4;
      default:        return null;
    }
  })();
  if (correct === null) return null;
  return correct ? 'WIN' : 'LOSS';
}

// ─── Règlement des marchés "personnalisés" (predictionType === 'other') ──────
// marketName/marketValue sont stockés en anglais brut (cohérence avec l'API
// — cf. pronostic_form.ejs), c'est donc sur ce format qu'on parse ici.

export type ScoreLine = { home: number; away: number };

export function _winner(s: ScoreLine): 'Home' | 'Draw' | 'Away' {
  if (s.home > s.away) return 'Home';
  if (s.away > s.home) return 'Away';
  return 'Draw';
}

export function _secondHalf(ft: ScoreLine, fh: ScoreLine): ScoreLine {
  return { home: ft.home - fh.home, away: ft.away - fh.away };
}

export function _parseOverUnder(value: string): { over: boolean; line: number } | null {
  const m = value.match(/^(Over|Under)\s+(\d+(?:\.\d+)?)$/);
  if (!m) return null;
  return { over: m[1] === 'Over', line: parseFloat(m[2]) };
}

export function _overUnderResult(over: boolean, line: number, total: number): 'WIN' | 'LOSS' | 'PUSH' {
  if (total === line) return 'PUSH'; // seulement possible sur une ligne ronde (Over 2.0, Over 3.0...)
  return (total > line) === over ? 'WIN' : 'LOSS';
}

export function _parseExactScore(value: string): ScoreLine | null {
  const m = value.match(/^(\d+):(\d+)$/);
  if (!m) return null;
  return { home: parseInt(m[1], 10), away: parseInt(m[2], 10) };
}

export function _parseCombo(value: string): [string, string] | null {
  const parts = value.split('/');
  return parts.length === 2 ? [parts[0], parts[1]] : null;
}

export function _parseHandicapValue(value: string): { side: 'Home' | 'Away'; line: number } | null {
  const m = value.match(/^(Home|Away)\s*([+-]?\d+(?:\.\d+)?)$/);
  if (!m) return null;
  return { side: m[1] as 'Home' | 'Away', line: parseFloat(m[2]) };
}

/** Résultat d'un handicap sur une ligne entière ou demi-entière (push possible uniquement sur ligne entière). */
export function _handicapOutcome(side: 'Home' | 'Away', line: number, s: ScoreLine): 'WIN' | 'LOSS' | 'PUSH' {
  const teamScore = side === 'Home' ? s.home : s.away;
  const oppScore  = side === 'Home' ? s.away : s.home;
  const adjusted  = teamScore + line;
  if (adjusted > oppScore) return 'WIN';
  if (adjusted < oppScore) return 'LOSS';
  return 'PUSH';
}

/**
 * Handicap asiatique complet, y compris les lignes à quart (-0.25, -0.75...)
 * qui n'existent pas en pari classique : elles scindent virtuellement la
 * mise en deux moitiés sur les deux lignes demi-entières adjacentes.
 * Notre système n'a que 3 états (pas de "demi-victoire") : gagné+remboursé
 * devient WIN net, perdu+remboursé devient LOSS net — c'est la convention
 * standard des calculateurs de handicap asiatique.
 */
export function _asianHandicapResult(side: 'Home' | 'Away', line: number, s: ScoreLine): 'WIN' | 'LOSS' | 'PUSH' {
  const quarterUnits  = Math.round(line * 4);
  const isQuarterLine = Math.abs(line * 4 - quarterUnits) < 1e-9 && quarterUnits % 2 !== 0;
  if (!isQuarterLine) return _handicapOutcome(side, line, s);

  const lower = Math.floor(line * 2) / 2;
  const upper = lower + 0.5;
  const outcomes = [_handicapOutcome(side, lower, s), _handicapOutcome(side, upper, s)];
  if (outcomes.every(o => o === 'WIN'))  return 'WIN';
  if (outcomes.every(o => o === 'LOSS')) return 'LOSS';
  return outcomes.includes('WIN') ? 'WIN' : 'LOSS'; // moitié gagnée/remboursée ou perdue/remboursée
}

/**
 * Règle un pronostic "marché personnalisé" à partir du marketName/marketValue
 * bruts 1xBet. Couvre la quasi-totalité des ~31 marchés proposés dans
 * l'admin ; retourne null pour les cas non couverts ("To Qualify", qui n'a
 * pas de sens sur un match simple — concept aller-retour) ou quand une
 * donnée nécessaire manque (score mi-temps absent pour un marché "MT").
 */
export function _computeCustomMarketResult(
  marketName: string,
  marketValue: string,
  ft: ScoreLine,
  fh: ScoreLine | null,
): 'WIN' | 'LOSS' | 'PUSH' | null {
  const sh = fh ? _secondHalf(ft, fh) : null;
  const isWDA = (v: string) => v === 'Home' || v === 'Draw' || v === 'Away';

  switch (marketName) {
    case 'Match Winner':
      return isWDA(marketValue) ? (_winner(ft) === marketValue ? 'WIN' : 'LOSS') : null;
    case 'First Half Winner':
      return fh && isWDA(marketValue) ? (_winner(fh) === marketValue ? 'WIN' : 'LOSS') : null;
    case 'Second Half Winner':
      return sh && isWDA(marketValue) ? (_winner(sh) === marketValue ? 'WIN' : 'LOSS') : null;

    case 'Both Teams Score':
      return marketValue === 'Yes' || marketValue === 'No'
        ? ((ft.home > 0 && ft.away > 0) === (marketValue === 'Yes') ? 'WIN' : 'LOSS') : null;
    case 'Both Teams Score - First Half':
      return fh && (marketValue === 'Yes' || marketValue === 'No')
        ? ((fh.home > 0 && fh.away > 0) === (marketValue === 'Yes') ? 'WIN' : 'LOSS') : null;
    case 'Both Teams To Score - Second Half':
      return sh && (marketValue === 'Yes' || marketValue === 'No')
        ? ((sh.home > 0 && sh.away > 0) === (marketValue === 'Yes') ? 'WIN' : 'LOSS') : null;

    case 'Goals Over/Under': {
      const ou = _parseOverUnder(marketValue);
      return ou ? _overUnderResult(ou.over, ou.line, ft.home + ft.away) : null;
    }
    case 'Goals Over/Under First Half': {
      const ou = fh && _parseOverUnder(marketValue);
      return fh && ou ? _overUnderResult(ou.over, ou.line, fh.home + fh.away) : null;
    }
    case 'Goals Over/Under - Second Half': {
      const ou = sh && _parseOverUnder(marketValue);
      return sh && ou ? _overUnderResult(ou.over, ou.line, sh.home + sh.away) : null;
    }
    case 'Total - Home': {
      const ou = _parseOverUnder(marketValue);
      return ou ? _overUnderResult(ou.over, ou.line, ft.home) : null;
    }
    case 'Total - Away': {
      const ou = _parseOverUnder(marketValue);
      return ou ? _overUnderResult(ou.over, ou.line, ft.away) : null;
    }
    case 'Home Team Total Goals(1st Half)': {
      const ou = fh && _parseOverUnder(marketValue);
      return fh && ou ? _overUnderResult(ou.over, ou.line, fh.home) : null;
    }
    case 'Away Team Total Goals(1st Half)': {
      const ou = fh && _parseOverUnder(marketValue);
      return fh && ou ? _overUnderResult(ou.over, ou.line, fh.away) : null;
    }
    case 'Home Team Total Goals(2nd Half)': {
      const ou = sh && _parseOverUnder(marketValue);
      return sh && ou ? _overUnderResult(ou.over, ou.line, sh.home) : null;
    }
    case 'Away Team Total Goals(2nd Half)': {
      const ou = sh && _parseOverUnder(marketValue);
      return sh && ou ? _overUnderResult(ou.over, ou.line, sh.away) : null;
    }

    case 'Exact Score': {
      const s = _parseExactScore(marketValue);
      return s ? (s.home === ft.home && s.away === ft.away ? 'WIN' : 'LOSS') : null;
    }
    case 'Correct Score - First Half': {
      const s = fh && _parseExactScore(marketValue);
      return fh && s ? (s.home === fh.home && s.away === fh.away ? 'WIN' : 'LOSS') : null;
    }
    case 'Correct Score - Second Half': {
      const s = sh && _parseExactScore(marketValue);
      return sh && s ? (s.home === sh.home && s.away === sh.away ? 'WIN' : 'LOSS') : null;
    }

    case 'Highest Scoring Half': {
      if (!fh || !sh) return null;
      const fhTotal = fh.home + fh.away, shTotal = sh.home + sh.away;
      const actual = fhTotal > shTotal ? '1st Half' : fhTotal < shTotal ? '2nd Half' : 'Draw';
      return actual === marketValue ? 'WIN' : 'LOSS';
    }

    case 'HT/FT Double': {
      const combo = fh && _parseCombo(marketValue);
      return fh && combo ? (_winner(fh) === combo[0] && _winner(ft) === combo[1] ? 'WIN' : 'LOSS') : null;
    }
    case 'Double Chance': {
      const combo = _parseCombo(marketValue);
      return combo ? (combo.includes(_winner(ft)) ? 'WIN' : 'LOSS') : null;
    }
    case 'Double Chance - First Half': {
      const combo = fh && _parseCombo(marketValue);
      return fh && combo ? (combo.includes(_winner(fh)) ? 'WIN' : 'LOSS') : null;
    }
    case 'Double Chance - Second Half': {
      const combo = sh && _parseCombo(marketValue);
      return sh && combo ? (combo.includes(_winner(sh)) ? 'WIN' : 'LOSS') : null;
    }

    case 'Odd/Even':
      return marketValue === 'Odd' || marketValue === 'Even'
        ? (((ft.home + ft.away) % 2 === 1) === (marketValue === 'Odd') ? 'WIN' : 'LOSS') : null;
    case 'Odd/Even - First Half':
      return fh && (marketValue === 'Odd' || marketValue === 'Even')
        ? (((fh.home + fh.away) % 2 === 1) === (marketValue === 'Odd') ? 'WIN' : 'LOSS') : null;
    case 'Odd/Even - Second Half':
      return sh && (marketValue === 'Odd' || marketValue === 'Even')
        ? (((sh.home + sh.away) % 2 === 1) === (marketValue === 'Odd') ? 'WIN' : 'LOSS') : null;
    case 'Home Odd/Even':
      return marketValue === 'Odd' || marketValue === 'Even'
        ? ((ft.home % 2 === 1) === (marketValue === 'Odd') ? 'WIN' : 'LOSS') : null;
    case 'Away Odd/Even':
      return marketValue === 'Odd' || marketValue === 'Even'
        ? ((ft.away % 2 === 1) === (marketValue === 'Odd') ? 'WIN' : 'LOSS') : null;

    case 'Asian Handicap': {
      const h = _parseHandicapValue(marketValue);
      return h ? _asianHandicapResult(h.side, h.line, ft) : null;
    }
    case 'Asian Handicap First Half': {
      const h = fh && _parseHandicapValue(marketValue);
      return fh && h ? _asianHandicapResult(h.side, h.line, fh) : null;
    }
    case 'Asian Handicap (2nd Half)': {
      const h = sh && _parseHandicapValue(marketValue);
      return sh && h ? _asianHandicapResult(h.side, h.line, sh) : null;
    }

    // "To Qualify" (concept aller-retour) et tout marché non reconnu restent
    // en résolution manuelle via les boutons WIN/LOSS/Remboursé de l'admin.
    default:
      return null;
  }
}

/** Point d'entrée unique de règlement — dispatche vers les 8 types connus ou le moteur de marchés personnalisés. */
export function _resolvePronosticResult(
  prono: { predictionType: string; marketName: string | null; marketValue: string | null },
  ft: ScoreLine,
  fh: ScoreLine | null,
): 'WIN' | 'LOSS' | 'PUSH' | null {
  if (prono.predictionType === 'other') {
    if (!prono.marketName || !prono.marketValue) return null;
    return _computeCustomMarketResult(prono.marketName, prono.marketValue, ft, fh);
  }
  return _computeResult(prono.predictionType, ft.home, ft.away);
}
