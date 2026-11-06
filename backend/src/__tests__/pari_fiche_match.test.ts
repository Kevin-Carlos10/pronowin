/**
 * La fiche d'un pari montre le match comme le reste de l'application :
 * écussons, coup d'envoi, statut et score.
 *
 * La bankroll ne publiait que les noms, la ligue et la date. La fiche du pari
 * affichait donc deux noms nus et, sous le match, la date du pari — que
 * l'écran présentait comme celle du match.
 */
import fs from 'fs';
import path from 'path';

describe('le match d\'un pari', () => {
  const code = fs.readFileSync(path.join(__dirname, '..', 'controllers', 'bankroll.controller.ts'), 'utf8');
  // Les deux réponses qui listent des paris : la bankroll et ses statistiques.
  const blocs = code.split('match: {').slice(1).map((b) => b.slice(0, b.indexOf('}')));

  it('deux réponses publient le match d\'un pari', () => {
    expect(blocs.length).toBe(2);
  });

  it.each(['match_date', 'home_team_logo', 'away_team_logo', 'status', 'home_score', 'away_score'])(
    'chacune publie %s', (champ) => {
      for (const b of blocs) expect(b).toContain(`${champ}:`);
    });
});
