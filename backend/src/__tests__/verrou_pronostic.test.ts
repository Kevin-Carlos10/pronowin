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
 * Le changement de fond : un match terminé ne se verrouille plus. Ce qui se
 * vend, c'est de connaître le pronostic **avant** le coup d'envoi ; après le
 * coup de sifflet final, il n'y a plus rien à protéger. Le cacher coûtait même
 * quelque chose — l'accueil annonce un taux de réussite qu'un utilisateur
 * gratuit n'avait aucun moyen de vérifier.
 */
describe('verrou d\'un pronostic premium', () => {
  describe('avant le match', () => {
    it('un premium est masqué à un utilisateur gratuit', () => {
      expect(estVerrouille(true, 'upcoming', false)).toBe(true);
      expect(estVerrouille(true, 'UPCOMING', false)).toBe(true);
    });

    it('un premium reste masqué pendant le direct', () => {
      // Le pari est encore ouvert : l'information garde toute sa valeur.
      expect(estVerrouille(true, 'live', false)).toBe(true);
      expect(estVerrouille(true, 'LIVE', false)).toBe(true);
    });

    it('un abonné voit tout', () => {
      expect(estVerrouille(true, 'upcoming', true)).toBe(false);
      expect(estVerrouille(true, 'live', true)).toBe(false);
    });

    it('un pronostic gratuit n\'est jamais masqué', () => {
      expect(estVerrouille(false, 'upcoming', false)).toBe(false);
    });
  });

  describe('après le match', () => {
    it('un premium terminé est ouvert à tous', () => {
      expect(estVerrouille(true, 'finished', false)).toBe(false);
      // Prisma stocke le statut en majuscules ; le mobile le reçoit en
      // minuscules. Les deux doivent donner le même verdict.
      expect(estVerrouille(true, 'FINISHED', false)).toBe(false);
    });

    it('le statut est reconnu quelle que soit sa casse', () => {
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
      // `isPremium && !isPremium` recopié : c'est la forme d'origine, et c'est
      // elle qui aurait continué de masquer les matchs terminés.
      const ancienne = /isPremium\s*&&\s*!\s*\w*[Pp]remium/;

      for (const f of ['services/pronostics.service.ts',
                       'controllers/pronostics.controller.ts']) {
        const code = lire(f);
        expect(ancienne.test(code)).toBe(false);
        expect(code).toContain('estVerrouille(');
      }
    });

    it('les deux appels passent bien le statut du match', () => {
      // Oublier ce paramètre compilerait — TypeScript accepte `undefined` — et
      // reverrouillerait silencieusement tous les matchs terminés.
      for (const f of ['services/pronostics.service.ts',
                       'controllers/pronostics.controller.ts']) {
        const code = lire(f);
        // **Chaque** appel, pas au moins un. Ma première version se contentait
        // du premier : le fichier de service en contient deux, et en casser un
        // laissait l'autre valider le test. Une injection l'a montré.
        const appels = code.match(/estVerrouille\([^)]*\)/g) ?? [];
        expect(appels.length).toBeGreaterThan(0);

        for (const appel of appels) {
          expect(appel).toMatch(/\bstatus\b/);
        }
      }
    });
  });
});
