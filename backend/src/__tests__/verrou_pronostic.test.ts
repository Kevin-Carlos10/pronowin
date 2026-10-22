import fs from 'fs';
import path from 'path';
import { estVerrouille, matchTermine } from '../services/verrou_pronostic';

/**
 * Ce qu'un pronostic premium cache, et jusqu'à quand.
 *
 * La règle vivait en double, sous la même forme, dans deux fichiers :
 * `p.isPremium && !isPremium`. Deux copies d'une règle d'accès finissent par
 * diverger, et celle-ci décide de ce qu'un utilisateur payant reçoit.
 *
 * Depuis le 17 octobre 2026 (décision de l'utilisateur), un pronostic Premium
 * reste masqué aux non-abonnés après le match aussi ; son résultat reste
 * visible (historique_premium_verrouille.test.ts).
 */
describe('verrou d\'un pronostic premium', () => {
  describe('avant le match', () => {
    it('un premium est masqué à un utilisateur gratuit', () => {
      expect(estVerrouille(true, false)).toBe(true);
    });

    it('un abonné voit tout', () => {
      expect(estVerrouille(true, true)).toBe(false);
    });

    it('un pronostic gratuit n\'est jamais masqué', () => {
      expect(estVerrouille(false, false)).toBe(false);
    });
  });

  describe('après le match', () => {
    it('un premium terminé reste masqué à un non-abonné', () => {
      // La règle ne regarde plus le statut du match : il n'y a plus de
      // paramètre par lequel un match terminé pourrait la rouvrir.
      expect(estVerrouille.length).toBe(2);
      expect(estVerrouille(true, false)).toBe(true);
    });

    it('le statut est reconnu quelle que soit sa casse', () => {
      // Sert encore à `premiumSaufMatchTermine` (analyse et commentaires
      // d'un pronostic gratuit après le match).
      for (const s of ['finished', 'FINISHED', 'Finished']) {
        expect(matchTermine(s)).toBe(true);
      }
      for (const s of ['upcoming', 'live', 'LIVE', '', null, undefined]) {
        expect(matchTermine(s)).toBe(false);
      }
    });
  });

  describe('la règle ne vit qu\'à un endroit', () => {
    const lire = (p: string) =>
      fs.readFileSync(path.join(__dirname, '..', p), 'utf8')
        .split('\n')
        .filter(l => {
          const t = l.trimStart();
          return !t.startsWith('//') && !t.startsWith('*') && !t.startsWith('/*');
        })
        .join('\n');

    it('ni la liste ni le détail ne recalculent le verrou', () => {
      // `isPremium && !isPremium` recopié : c'est la forme d'origine, celle
      // qui finit par diverger de la règle commune.
      const ancienne = /isPremium\s*&&\s*!\s*\w*[Pp]remium/;

      for (const f of ['services/pronostics.service.ts',
                       'controllers/pronostics.controller.ts']) {
        const code = lire(f);
        expect(ancienne.test(code)).toBe(false);
        expect(code).toContain('estVerrouille(');
      }
    });

    it('l\'historique applique la même règle que la liste et le détail', () => {
      // Il servait les choix Premium en clair à tout utilisateur connecté,
      // sans passer par le verrou.
      const code = lire('controllers/pronostics.controller.ts');
      const historique = code.slice(code.indexOf('export const getHistory'));
      expect(historique.slice(0, historique.indexOf('\n};'))).toContain('estVerrouille(');
    });
  });
});
