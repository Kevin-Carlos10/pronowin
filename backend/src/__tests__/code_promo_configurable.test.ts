import fs from 'fs';
import path from 'path';
import {
  CLES_CONFIG, codePromoPour, codesPromoParPlateforme, type CleConfig,
} from '../services/app_config.service';

/**
 * Le code d'affiliation se règle depuis l'administration, plus dans un `.env`.
 *
 * Il vivait dans `process.env.XBET_PROMO_CODE` : seul quelqu'un ayant un accès
 * SSH au serveur pouvait le changer. Et **trois** replis écrits en dur — dans
 * le backend, dans le mobile, dans l'administration — nommaient encore
 * `PRONOWIN2025` alors que le code en service était `PRONOWIN2026`.
 *
 * Un code périmé ne produit aucune erreur. L'utilisateur ouvre son compte chez
 * le partenaire, l'inscription réussit, nous ne sommes jamais crédités — et il
 * réclame malgré tout son mois offert. La perte est double, et rien ne la
 * signale avant le relevé.
 */
const valeursAvec = (o: Partial<Record<CleConfig, string>>) =>
  Object.fromEntries(
    CLES_CONFIG.map(c => [c, o[c] ?? '']),
  ) as Record<CleConfig, string>;

describe('code promo — une valeur administrable', () => {
  it('les quatre clés sont reconnues par la configuration', () => {
    for (const c of ['PROMO_CODE', 'PROMO_CODE_1XBET',
                     'PROMO_CODE_MELBET', 'PROMO_CODE_BETWINNER']) {
      expect(CLES_CONFIG).toContain(c);
    }
  });

  it('sans surcharge, toutes les plateformes prennent le code général', () => {
    const v = valeursAvec({ PROMO_CODE: 'PRONOWIN2026' });

    expect(codePromoPour(v, '1xbet')).toBe('PRONOWIN2026');
    expect(codePromoPour(v, 'melbet')).toBe('PRONOWIN2026');
    expect(codePromoPour(v)).toBe('PRONOWIN2026');
  });

  it('une surcharge ne vaut que pour sa plateforme', () => {
    const v = valeursAvec({
      PROMO_CODE: 'GENERAL', PROMO_CODE_MELBET: 'MELBET2026',
    });

    expect(codePromoPour(v, 'melbet')).toBe('MELBET2026');
    expect(codePromoPour(v, '1xbet')).toBe('GENERAL');
  });

  it('un champ vidé rétablit le général, il ne coupe pas le code', () => {
    // C'est le piège de l'écran : effacer une surcharge doit revenir au
    // général, pas laisser la plateforme sans code.
    const v = valeursAvec({ PROMO_CODE: 'GENERAL', PROMO_CODE_1XBET: '   ' });

    expect(codePromoPour(v, '1xbet')).toBe('GENERAL');
  });

  it('sans aucun code, rien n\'est inventé', () => {
    // Vide, l'écran mobile annonce l'indisponibilité. C'est la seule réponse
    // honnête : un code inventé ne crédite personne.
    const v = valeursAvec({});

    expect(codePromoPour(v, '1xbet')).toBe('');
    expect(codesPromoParPlateforme(v, ['1xbet', 'melbet'])).toEqual({});
  });

  it('la carte publiée omet les plateformes sans code', () => {
    const v = valeursAvec({ PROMO_CODE_MELBET: 'MELBET2026' });

    expect(codesPromoParPlateforme(v, ['1xbet', 'melbet', 'betwinner']))
      .toEqual({ melbet: 'MELBET2026' });
  });

  it('la casse de la plateforme n\'a pas d\'importance', () => {
    const v = valeursAvec({ PROMO_CODE_1XBET: 'X1' });

    expect(codePromoPour(v, '1XBET')).toBe('X1');
    expect(codePromoPour(v, '1xbet')).toBe('X1');
  });
});

describe('plus aucun code écrit en dur', () => {
  /** Sources sans leurs commentaires : ils citent le défaut corrigé. */
  const sansCommentaires = (rel: string) =>
    fs.readFileSync(path.join(__dirname, '..', rel), 'utf8')
      .split('\n')
      .filter(l => {
        const t = l.trimStart();
        return !t.startsWith('//') && !t.startsWith('*') && !t.startsWith('/*');
      })
      .join('\n');

  it('le service d\'abonnement lit la configuration', () => {
    const code = sansCommentaires('services/subscription.service.ts');

    // Le nom du code de l'an dernier ne doit plus figurer nulle part.
    expect(code).not.toContain('PRONOWIN2025');
    expect(code).toContain('codePromoPour(');
  });

  it('les deux branches de l\'abonnement annoncent le même code', () => {
    // La charge utile est écrite deux fois — cas nominal et repli d'erreur.
    // Les lire séparément ferait diverger ce que reçoit l'utilisateur selon
    // que le serveur a réussi ou non à lire son profil.
    const code = sansCommentaires('services/subscription.service.ts');
    const annonces = code.match(/promo_code:\s*codePromoPour\(/g) ?? [];

    expect(annonces.length).toBeGreaterThanOrEqual(2);
  });

  it('le repli d\'environnement reste vide', () => {
    const code = sansCommentaires('services/subscription.service.ts');

    // `?? ''` et non `?? 'PRONOWIN…'` : sans configuration, l'offre se masque.
    expect(code).toMatch(/XBET_PROMO_CODE\s*=\s*process\.env\.XBET_PROMO_CODE\s*\?\?\s*''/);
  });
});
